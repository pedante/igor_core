"""Deterministic, bounded selection of reference context items.

This module deliberately has no provider or policy knowledge.  It formats the
same item envelope for every model adapter and treats all selected content as
untrusted reference data.  Sources are supplied by the existing Igor runtime;
the selector never probes the host or changes System Model state.
"""

from __future__ import annotations

import json
import re
import sys
from collections.abc import Iterable, Mapping
from datetime import datetime
from typing import Any

SOURCE_KINDS = {
    "core_guidance", "system_fact", "health_result", "module_knowledge",
    "capability_metadata", "config_status", "legacy_context",
    "operational_history", "local_learning",
}
_KIND_ORDER = {kind: index for index, kind in enumerate(sorted(SOURCE_KINDS))}
_SECRET_KEY = re.compile(r"(?:secret|password|passwd|token|credential|private.?key|api.?key)", re.IGNORECASE)


def _text(value: Any) -> str:
    if isinstance(value, str):
        return value
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _public_value(value: Any, sensitivity: str) -> Any:
    """Copy source content while dropping secret bearing fields.

    Public items drop secret-bearing fields. Status-only items retain known
    booleans/status words and replace every other field with a status marker.
    Secret items become a status marker, never their supplied value.
    """
    if sensitivity == "secret":
        return {"status": "configured"}
    if sensitivity == "status_only":
        if isinstance(value, Mapping):
            visible: dict[str, Any] = {}
            for key, child in value.items():
                name = str(key)
                if (name in {"configured", "available", "present", "missing"} and type(child) is bool) or (
                    name == "status" and isinstance(child, str) and
                    child in {"configured", "missing", "available", "unavailable"}
                ):
                    visible[name] = child
                else:
                    visible[name] = {"status": "configured"} if child else {"status": "missing"}
            return visible
        if type(value) is bool:
            return value
        return {"status": "configured"} if value else {"status": "missing"}
    if isinstance(value, Mapping):
        result: dict[str, Any] = {}
        for key, child in value.items():
            if _SECRET_KEY.search(str(key)) or str(key).lower() == "secret_ref":
                result[str(key)] = {"status": "configured"} if child else {"status": "missing"}
            else:
                result[str(key)] = _public_value(child, sensitivity)
        return result
    if isinstance(value, list):
        return [_public_value(child, sensitivity) for child in value]
    return value


def _matches(item: Mapping[str, Any], request: Mapping[str, Any]) -> tuple[int, str]:
    object_id = request.get("object_id") or request.get("object")
    capability_id = request.get("capability_id") or request.get("capability")
    intent = str(request.get("intent") or request.get("domain") or "").lower()
    tags = {str(tag).lower() for tag in item.get("tags", [])} if isinstance(item.get("tags"), list) else set()
    if intent and item.get("kind") != "core_guidance":
        searchable = " ".join((str(item.get("source_id", "")), str(item.get("id", "")), *tags)).lower()
        if intent not in searchable:
            return 99, "outside requested domain"
    if object_id and item.get("object_id") == object_id:
        return 0, "exact object"
    if capability_id and item.get("capability_id") == capability_id:
        return 0, "exact capability"
    if intent and (intent in str(item.get("source_id", "")).lower() or intent in tags):
        return 1, "owner/domain match"
    # An explicit domain is a bounded request.  A host object alone is not
    # enough to make every unrelated fact relevant to that request.
    if intent and item.get("kind") not in {"core_guidance"}:
        return 99, "outside requested domain"
    if item.get("kind") in {"health_result", "system_fact"}:
        # A current health/fact item is useful for the active task even if no
        # explicit object was named; freshness determines the stable tie-break.
        return 2, "relevant state"
    if item.get("kind") == "core_guidance":
        return 3, "core guidance"
    return 4, "explicit request"


def _time_key(value: Any) -> float:
    if not isinstance(value, str):
        return 0.0
    try:
        return -datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except (ValueError, OverflowError):
        return 0.0


def _severity_key(item: Mapping[str, Any]) -> int:
    if item.get("kind") != "health_result":
        return 5
    content = item.get("content", {})
    status = content.get("status") if isinstance(content, Mapping) else None
    return {"CRITICAL": 0, "FAIL": 1, "WARN": 2, "UNKNOWN": 3, "OK": 4}.get(status, 5)


def select_context(request: Mapping[str, Any] | None,
                   sources: Iterable[Mapping[str, Any]],
                   *, max_items: int = 32, max_bytes: int = 24000,
                   per_source: int = 8,
                   active_owners: Iterable[str] | None = None) -> dict[str, Any]:
    """Return a bounded, inspectable selection and omission information."""
    request = request or {}
    allowed = set(active_owners) if active_owners is not None else None
    candidates: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
    omitted: list[dict[str, str]] = []
    counts: dict[str, int] = {}
    for raw in sources:
        if not isinstance(raw, Mapping):
            omitted.append({"reason": "malformed source"})
            continue
        kind = str(raw.get("kind", "legacy_context"))
        owner = str(raw.get("owner", "core"))
        if kind not in SOURCE_KINDS:
            omitted.append({"id": str(raw.get("id", "")), "reason": "unknown source kind"})
            continue
        if allowed is not None and owner not in allowed and owner != "core":
            omitted.append({"id": str(raw.get("id", "")), "reason": "owner inactive"})
            continue
        if raw.get("active") is False or raw.get("availability") in {"unavailable", "inactive"}:
            omitted.append({"id": str(raw.get("id", "")), "reason": "source unavailable"})
            continue
        source_id = str(raw.get("source_id") or raw.get("id") or f"{kind}:{owner}")
        rank, reason = _matches(raw, request)
        if rank >= 99:
            omitted.append({"id": str(raw.get("id", source_id)), "reason": reason})
            continue
        sensitivity = str(raw.get("sensitivity", "public"))
        if sensitivity not in {"public", "status_only", "secret"}:
            sensitivity = "secret"
        content = _public_value(raw.get("content", raw.get("value", "")), sensitivity)
        item = {
            "id": str(raw.get("id") or source_id), "kind": kind, "owner": owner,
            "source_id": source_id,
            "source_version": raw.get("source_version"),
            "object_id": raw.get("object_id"), "capability_id": raw.get("capability_id"),
            "recorded_at": raw.get("recorded_at"), "freshness": raw.get("freshness"),
            "availability": raw.get("availability", "known"), "sensitivity": sensitivity,
            "selection_reason": reason, "content": content,
        }
        if kind == "core_guidance":
            rank = -1
        candidates.append(((rank, _severity_key(item), _time_key(item["recorded_at"]),
                            _KIND_ORDER[kind], str(item["id"])), item))

    candidates.sort(key=lambda pair: pair[0])
    selected: list[dict[str, Any]] = []
    used = 0
    for _, item in candidates:
        if counts.get(item["source_id"], 0) >= per_source:
            omitted.append({"id": item["id"], "reason": "per-source bound"})
            continue
        size = len(json.dumps(item, sort_keys=True, ensure_ascii=True).encode())
        if len(selected) >= max_items or used + size > max_bytes:
            omitted.append({"id": item["id"], "reason": "selection bound"})
            continue
        selected.append(item)
        counts[item["source_id"]] = counts.get(item["source_id"], 0) + 1
        used += size
    return {"items": selected, "omitted": omitted, "item_count": len(selected), "bytes": used,
            "limits": {"max_items": max_items, "max_bytes": max_bytes, "per_source": per_source}}


def inspect_context(selection: Mapping[str, Any]) -> dict[str, Any]:
    """Return read-only provenance; content is intentionally excluded."""
    return {"items": [{key: item.get(key) for key in (
        "id", "kind", "owner", "source_id", "source_version", "object_id",
        "capability_id", "recorded_at", "freshness", "availability", "sensitivity",
        "selection_reason")} for item in selection.get("items", [])],
            "omitted": list(selection.get("omitted", [])), "limits": selection.get("limits", {})}


def main() -> int:
    payload = json.load(sys.stdin)
    result = select_context(payload.get("request", {}), payload.get("sources", []),
                            max_items=int(payload.get("max_items", 32)),
                            max_bytes=int(payload.get("max_bytes", 24000)),
                            per_source=int(payload.get("per_source", 8)),
                            active_owners=payload.get("active_owners"))
    if payload.get("inspect"):
        result = inspect_context(result)
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
