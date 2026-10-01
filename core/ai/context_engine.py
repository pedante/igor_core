"""Deterministic, bounded selection of reference context items.

This module deliberately has no provider or policy knowledge.  It formats the
same item envelope for every model adapter and treats all selected content as
untrusted reference data.  Sources are supplied by the existing Igor runtime;
the selector never probes the host or changes System Model state.
"""

from __future__ import annotations

import hashlib
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
    "conversation", "investigation", "judgment",
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


def select_request_context(request: Mapping[str, Any], sources: Iterable[Mapping[str, Any]], *,
                           max_items: int = 32, max_bytes: int = 24000,
                           per_source: int = 8, active_owners: Iterable[str] | None = None,
                           judgment_request: Mapping[str, Any] | None = None,
                           judgment_record: Mapping[str, Any] | str | None = None,
                           min_confidence: float = 0.5) -> dict[str, Any]:
    """Select bounded request context using closed metadata and optional validated ranking.

    Ranking records can reorder optional candidates only inside an existing
    deterministic relevance tier. No adapter/provider is called here.
    """
    request = dict(request)
    if set(request) - {"candidate_ids", "ids", "references", "tags", "domain", "scope_id", "object_id", "capability_id"}:
        raise ValueError("unsupported context request fields")
    if (any(type(value) is not int or value < 1 for value in (max_items, max_bytes, per_source))
            or max_items > 512 or max_bytes > 262144 or per_source > 512
            or type(min_confidence) not in {int, float} or not 0 <= min_confidence <= 1):
        raise ValueError("invalid context policy limits")
    for key in ("candidate_ids", "ids", "references", "tags"):
        if key in request and (type(request[key]) is not list or any(type(item) is not str for item in request[key])):
            raise ValueError("invalid context request metadata")
    for key in ("scope_id", "object_id", "capability_id", "domain"):
        if key in request and (type(request[key]) is not str or len(request[key]) > 160):
            raise ValueError("invalid context request metadata")
    explicit = set(request.get("candidate_ids", request.get("ids", [])))
    refs = set(request.get("references", []))
    tags = set(request.get("tags", []))
    if type(request.get("domain")) is str:
        tags.add(request["domain"])
    scope = request.get("scope_id")
    if (len(explicit | refs) > 128 or len(tags) > 64 or
            any(type(x) is not str or len(x) > 160 for x in explicit | refs | tags)):
        raise ValueError("invalid bounded context request")
    allowed = set(active_owners) if active_owners is not None else None
    entries: list[tuple[int, str, dict[str, Any], dict[str, Any]]] = []
    omitted: list[dict[str, Any]] = []
    counts: dict[str, int] = {}
    seen_ids: set[str] = set()
    total_candidates = 0
    mandatory_ids = set(explicit | refs)
    for raw in sources:
        total_candidates += 1
        if total_candidates > 512:
            omitted.append({"id": "", "reason": "candidate collection bound"})
            break
        if not isinstance(raw, Mapping):
            omitted.append({"id": "", "reason": "malformed candidate"})
            continue
        ident = raw.get("id")
        if type(ident) is not str or not ident or len(ident) > 160 or any(ord(char) < 32 for char in ident):
            omitted.append({"id": "", "reason": "invalid candidate identity"})
            continue
        if ident in seen_ids:
            omitted.append({"id": ident, "reason": "duplicate candidate identity"}); continue
        seen_ids.add(ident)
        if raw.get("mandatory") is True:
            mandatory_ids.add(ident)
        kind, owner = raw.get("kind"), raw.get("owner", "core")
        if type(kind) is not str or kind not in SOURCE_KINDS:
            omitted.append({"id": ident, "reason": "unknown source kind"}); continue
        if type(owner) is not str or len(owner) > 160 or (allowed is not None and owner not in allowed and owner != "core"):
            omitted.append({"id": ident, "reason": "owner inactive"}); continue
        availability = raw.get("availability", "known")
        if type(availability) is not str:
            omitted.append({"id": ident, "reason": "invalid bounded metadata"}); continue
        if raw.get("active") is False or availability in {"unavailable", "inactive"}:
            omitted.append({"id": ident, "reason": "source unavailable"}); continue
        sensitivity = raw.get("sensitivity", "public")
        if type(sensitivity) is not str or sensitivity not in {"public", "status_only", "secret"}:
            omitted.append({"id": ident, "reason": "unknown sensitivity"}); continue
        if sensitivity == "secret":
            omitted.append({"id": ident, "reason": "secret material excluded"}); continue
        candidate_scope = raw.get("scope_id")
        if scope is not None and candidate_scope is not None and candidate_scope != scope:
            omitted.append({"id": ident, "reason": "scope mismatch"}); continue
        authority = raw.get("authority_class", {
            "system_fact": "current_state_projection", "operational_history": "historical_evidence",
            "investigation": "investigation_material", "judgment": "judgment",
            "conversation": "conversational_reference"}.get(kind, "reference"))
        if type(authority) is not str or authority not in {"reference", "current_state_projection", "historical_evidence",
                "investigation_material", "judgment", "conversational_reference"}:
            omitted.append({"id": ident, "reason": "invalid authority metadata"}); continue
        item_tags = raw.get("tags", [])
        if type(item_tags) is not list or len(item_tags) > 64 or any(type(t) is not str or len(t) > 80 for t in item_tags):
            omitted.append({"id": ident, "reason": "invalid relevance metadata"}); continue
        src = raw.get("source_id", ident)
        provenance = raw.get("provenance", src)
        if type(src) is not str or len(src) > 160 or type(provenance) is not str or len(provenance) > 512:
            omitted.append({"id": ident, "reason": "invalid provenance metadata"}); continue
        matched = set(item_tags) & tags
        core_guidance = kind == "core_guidance"
        pinned = ident in explicit | refs or core_guidance or raw.get("mandatory") is True
        if tags and not matched and not pinned:
            omitted.append({"id": ident, "reason": "no relevance match"}); continue
        if (tags or request.get("object_id") or request.get("capability_id")) and not (
                ident in explicit | refs or matched or core_guidance or raw.get("mandatory") is True or
                any(request.get(key) and raw.get(key) == request[key]
                    for key in ("object_id", "capability_id"))):
            omitted.append({"id": ident, "reason": "no relevance match"}); continue
        tier, reason = (0, "explicit reference") if ident in explicit | refs else (
            (1, "object or capability match") if any(request.get(key) and raw.get(key) == request[key]
                for key in ("object_id", "capability_id")) else
            ((2, "tag match") if matched else (3, "default eligible")))
        content = _public_value(raw.get("content", raw.get("value", "")), sensitivity)
        if len(_text(content).encode("utf-8")) > max_bytes:
            omitted.append({"id": ident, "reason": "candidate exceeds byte bound"}); continue
        if raw.get("source_version") is not None and not (
                type(raw["source_version"]) is int and 0 <= raw["source_version"] <= 1000000 or
                type(raw["source_version"]) is str and len(raw["source_version"]) <= 80):
            omitted.append({"id": ident, "reason": "invalid bounded metadata"}); continue
        if any(raw.get(key) is not None and (type(raw[key]) is not str or len(raw[key]) > 160
                or any(ord(char) < 32 for char in raw[key])) for key in (
                "scope_id", "recorded_at", "collected_at", "freshness", "availability", "object_id", "capability_id")):
            omitted.append({"id": ident, "reason": "invalid bounded metadata"}); continue
        item = {"id": ident, "kind": kind, "owner": owner, "source_id": src,
                "source_version": raw.get("source_version"), "scope_id": candidate_scope,
                "provenance": provenance, "recorded_at": raw.get("recorded_at"), "collected_at": raw.get("collected_at"),
                "freshness": raw.get("freshness"), "availability": raw.get("availability", "known"),
                "sensitivity": sensitivity, "authority_class": authority, "tags": sorted(item_tags),
                "object_id": raw.get("object_id"), "capability_id": raw.get("capability_id"),
                "mandatory": raw.get("mandatory") is True,
                "size_bytes": 0, "token_estimate": 0, "selection_reason": reason, "content": content}
        item["size_bytes"] = len(_text(content).encode("utf-8"))
        item["token_estimate"] = max(1, (item["size_bytes"] + 3) // 4)
        item["content_digest"] = hashlib.sha256(_text(content).encode("utf-8")).hexdigest()
        meta = {key: item[key] for key in ("id", "kind", "owner", "source_id", "source_version", "scope_id",
                "provenance", "recorded_at", "collected_at", "freshness", "availability", "sensitivity", "authority_class",
        "tags", "object_id", "capability_id", "mandatory", "size_bytes", "token_estimate", "content_digest")}
        entries.append((tier, ident, item, meta))
    for ident in sorted(explicit | refs):
        if ident not in seen_ids:
            omitted.append({"id": ident, "reason": "reference unavailable"})
    entries.sort(key=lambda e: (not e[2]["mandatory"], e[0], _severity_key(e[2]), _time_key(e[2].get("recorded_at")), e[1]))
    candidate_digest = hashlib.sha256(json.dumps([e[3] for e in entries], sort_keys=True,
        separators=(",", ":")).encode()).hexdigest()
    ranking_status = "not_requested"
    ranking_provenance: dict[str, Any] = {}
    jreq = _make_relevance_request(candidate_digest, entries)
    if judgment_record is not None or judgment_request is not None:
        ranking_status = "deterministic_fallback"
        try:
            from judgment import JudgmentError, validate_record
            if judgment_request is not None and dict(judgment_request) != jreq:
                raise JudgmentError("request mismatch")
            rec = validate_record(judgment_record, jreq)
            ranking_provenance = {"judgment_id": rec["judgment_id"], "status": rec["status"],
                                  "confidence": rec.get("confidence"), "reason": rec.get("reason"),
                                  "validation": rec["validation"]}
            rank_ids = rec["payload"]["ranked_ids"] if rec["status"] == "valid" else []
            if (rec["status"] != "valid" or len(set(rank_ids)) != len(rank_ids) or
                    not set(rank_ids) <= set(jreq["input"]["candidate_ids"]) or
                    rec.get("confidence", 0.0) < min_confidence):
                raise JudgmentError("ranking not usable")
            position = {ident: i for i, ident in enumerate(rank_ids)}
            entries.sort(key=lambda e: (not e[2]["mandatory"], e[0], position.get(e[1], len(position)), _time_key(e[2].get("recorded_at")), e[1]))
            ranking_status = "validated_ranking"
        except (ImportError, ValueError, TypeError, KeyError, AttributeError):
            ranking_status = "deterministic_fallback"
            if not ranking_provenance:
                ranking_provenance = {"status": "invalid_or_unbound", "reason": "judgment rejected"}
    selected, used = [], 0
    mandatory_failed = False
    budget_failed = False
    for tier, ident, item, _meta in entries:
        if counts.get(item["source_id"], 0) >= per_source:
            omitted.append({"id": ident, "reason": "per-source bound"}); continue
        size = len(json.dumps(item, sort_keys=True, ensure_ascii=True).encode())
        if len(selected) >= max_items or used + size > max_bytes:
            omitted.append({"id": ident, "reason": "selection bound"}); continue
        selected.append(item); counts[item["source_id"]] = counts.get(item["source_id"], 0) + 1; used += size
    selected_ids = {item["id"] for item in selected}
    missing_required = mandatory_ids - selected_ids
    if missing_required:
        mandatory_failed = any(any(x.get("id") == ident and x.get("reason") in {
            "selection bound", "per-source bound", "candidate exceeds byte bound"} for x in omitted)
            for ident in missing_required)
        budget_failed = mandatory_failed
    status = "context_budget_exceeded" if budget_failed else ("insufficient_context" if missing_required else "ok")
    if budget_failed:
        selected, used = [], 0
    return {"status": status, "items": selected, "omitted": omitted, "item_count": len(selected), "bytes": used,
            "candidate_digest": candidate_digest, "ranking_status": ranking_status,
            "judgment_request": jreq,
            "ranking_provenance": ranking_provenance,
            "routing_context": {"selection_rule": "deterministic_tiered_v1", "ranking_status": ranking_status,
                                "judgment": ranking_provenance},
            "limits": {"max_items": max_items, "max_bytes": max_bytes, "per_source": per_source}}


def _make_relevance_request(digest: str, entries: list[tuple[int, str, dict[str, Any], dict[str, Any]]]) -> dict[str, Any]:
    """Return the exact caller-owned Judgment Contract request for eligible candidates."""
    ranked = entries[:32]
    item_schema = {"type": "string", "minLength": 1, "maxLength": 160}
    if ranked:
        item_schema["enum"] = [entry[1] for entry in ranked]
    references = [{"id": e[1], "source": e[3]["source_id"],
                   "recorded_at": e[3]["recorded_at"]} for e in ranked if e[3]["recorded_at"]]
    return {"contract": "igor.judgment", "version": 1, "kind": "context.relevance", "kind_version": 1,
            "input": {"candidate_digest": digest, "candidate_ids": [e[1] for e in ranked]},
            "references": references,
            "output_schema": {"type": "object", "properties": {"ranked_ids": {
                "type": "array", "items": item_schema,
                "minItems": 0, "maxItems": min(64, len(ranked))}}, "required": ["ranked_ids"],
                "additionalProperties": False}}


def build_relevance_request(selection: Mapping[str, Any]) -> dict[str, Any]:
    """Expose a detached Judgment Contract request without invoking a provider."""
    request = selection.get("judgment_request")
    if not isinstance(request, Mapping):
        raise TypeError("selection has no relevance request")
    return json.loads(json.dumps(request))


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
        "selection_reason", "scope_id", "provenance", "authority_class", "mandatory",
        "content_digest", "size_bytes", "token_estimate", "collected_at")}
        for item in selection.get("items", [])],
            "omitted": list(selection.get("omitted", [])), "limits": selection.get("limits", {}),
            "candidate_digest": selection.get("candidate_digest"),
            "routing_context": selection.get("routing_context", {}), "status": selection.get("status", "ok")}


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
