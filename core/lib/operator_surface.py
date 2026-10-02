#!/usr/bin/env python3
"""Read-only projection of Igor-owned contracts into a browsable operator surface.

This module never executes a capability, mutates configuration, probes the host,
or loads a module.  It turns existing registry/inspection records into stable UI
metadata so TUI, CLI, and future frontends can share one discoverability model.
"""

from __future__ import annotations

import copy
import hashlib
import json
import re
import sys
from typing import Any

SURFACE_VERSION = 1
_ID = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
_KINDS = {
    "automation", "capability", "check", "configuration", "domain_event",
    "knowledge", "lifecycle", "observer", "relationship",
}
_SOURCE_NAMES = ("modules", "contributions", "capabilities", "configurations")
_SOURCE_STATES = {"ok", "missing", "error"}


class SurfaceError(ValueError):
    """Malformed projection input."""


def _bounded_list(value: Any, name: str, limit: int = 4096) -> list[dict[str, Any]]:
    if not isinstance(value, list) or len(value) > limit or any(not isinstance(row, dict) for row in value):
        raise SurfaceError(f"invalid {name}")
    return value


def _safe_id(value: Any, name: str) -> str:
    if not isinstance(value, str) or not _ID.fullmatch(value):
        raise SurfaceError(f"invalid {name}")
    return value


def _path(owner: str, ident: str) -> str:
    # A contribution ID is its durable identity.  The operator path is only a
    # presentation/navigation identity, so owner-prefix IDs that are not already
    # owner-scoped without rewriting the underlying contract.
    return ident if ident == owner or ident.startswith(owner + ".") else f"{owner}.{ident}"


def _availability(value: Any) -> str:
    return value if value in {"active", "inactive", "unavailable", "disabled"} else "unavailable"


def _capability_entry(row: dict[str, Any]) -> dict[str, Any]:
    ident = _safe_id(row.get("id"), "capability id")
    owner = _safe_id(row.get("owner") or row.get("provider"), "capability owner")
    descriptor = row.get("descriptor")
    if not isinstance(descriptor, dict):
        raise SurfaceError("invalid capability descriptor")
    inputs = descriptor.get("inputs") if isinstance(descriptor.get("inputs"), dict) else {}
    required = inputs.get("required") if isinstance(inputs.get("required"), list) else []
    properties = inputs.get("properties") if isinstance(inputs.get("properties"), dict) else {}
    safety = descriptor.get("safety") if isinstance(descriptor.get("safety"), dict) else {}
    return {
        "path": ident,
        "kind": "capability",
        "owner": owner,
        "target_id": ident,
        "provider": str(row.get("provider") or owner),
        "provider_required": False,
        "availability": _availability(row.get("availability")),
        "unavailable_reason": row.get("unavailable_reason") if isinstance(row.get("unavailable_reason"), str) else None,
        "label": ident.rsplit(".", 1)[-1].replace("_", " "),
        "description": str(descriptor.get("description") or "Capability"),
        "safety": safety.get("tier") if safety.get("tier") in {"READ", "CHANGE", "DESTROY"} else None,
        "privilege": descriptor.get("privilege") if isinstance(descriptor.get("privilege"), str) else None,
        "inputs": {
            "required": [name for name in required if isinstance(name, str)],
            "properties": copy.deepcopy(properties),
        },
        "verification": copy.deepcopy(descriptor.get("verification")) if isinstance(descriptor.get("verification"), dict) else None,
        "recovery": copy.deepcopy(descriptor.get("recovery")) if isinstance(descriptor.get("recovery"), dict) else None,
    }


def _contribution_entry(row: dict[str, Any]) -> dict[str, Any] | None:
    kind = row.get("kind")
    if kind not in _KINDS or kind in {"capability", "configuration"}:
        return None
    ident = _safe_id(row.get("id"), "contribution id")
    owner = _safe_id(row.get("owner"), "contribution owner")
    descriptor = row.get("descriptor")
    if not isinstance(descriptor, dict):
        descriptor = {}
    descriptions = {
        "observer": "Observation source",
        "check": "Health check",
        "knowledge": "Knowledge",
        "automation": "Automation",
        "lifecycle": "Lifecycle",
        "relationship": "Relationship",
        "domain_event": "Domain event",
    }
    return {
        "path": _path(owner, ident),
        "kind": kind,
        "owner": owner,
        "target_id": ident,
        "availability": _availability(row.get("availability")),
        "unavailable_reason": row.get("unavailable_reason") if isinstance(row.get("unavailable_reason"), str) else None,
        "label": ident.rsplit(".", 1)[-1].replace("_", " "),
        "description": str(descriptor.get("description") or descriptions.get(kind, kind.replace("_", " ").title())),
    }


def _configuration_entries(record: dict[str, Any], active_owners: set[str]) -> list[dict[str, Any]]:
    owner = _safe_id(record.get("owner"), "configuration owner")
    schema = record.get("schema")
    if not isinstance(schema, dict) or not isinstance(schema.get("fields"), list):
        raise SurfaceError("invalid configuration schema")
    availability = "active" if owner in active_owners or owner == "core" else "inactive"
    result: list[dict[str, Any]] = []
    for field in schema["fields"]:
        if not isinstance(field, dict):
            raise SurfaceError("invalid configuration field")
        ident = _safe_id(field.get("id"), "setting id")
        # Never project secret values; schema contains references/semantics only.
        result.append({
            "path": _path(owner, ident),
            "kind": "configuration",
            "owner": owner,
            "target_id": ident,
            "availability": availability,
            "unavailable_reason": None,
            "label": str(field.get("label") or ident.rsplit(".", 1)[-1].replace("_", " ")),
            "description": str(field.get("help") or "Configuration"),
            "value_type": field.get("type") if isinstance(field.get("type"), str) else None,
            "behavior": field.get("behavior") if isinstance(field.get("behavior"), str) else None,
            "apply": copy.deepcopy(field.get("apply")) if isinstance(field.get("apply"), dict) else None,
        })
    return result


def build_surface(payload: dict[str, Any]) -> dict[str, Any]:
    allowed = {*_SOURCE_NAMES, "sources"}
    if not isinstance(payload, dict) or set(payload) - allowed:
        raise SurfaceError("invalid operator surface payload")
    modules = _bounded_list(payload.get("modules", []), "modules", 512)
    contributions = _bounded_list(payload.get("contributions", []), "contributions")
    capabilities = _bounded_list(payload.get("capabilities", []), "capabilities")
    configurations = _bounded_list(payload.get("configurations", []), "configurations", 512)
    source_rows = {
        "modules": modules,
        "contributions": contributions,
        "capabilities": capabilities,
        "configurations": configurations,
    }
    raw_sources = payload.get("sources", {})
    if not isinstance(raw_sources, dict) or set(raw_sources) - set(_SOURCE_NAMES):
        raise SurfaceError("invalid operator surface sources")
    sources = {}
    for name in _SOURCE_NAMES:
        state = raw_sources.get(name, "ok")
        if state not in _SOURCE_STATES:
            raise SurfaceError("invalid operator surface source state")
        sources[name] = {"status": state, "count": len(source_rows[name])}

    active_owners = {
        _safe_id(row.get("name"), "module name")
        for row in modules
        if row.get("status") == "active"
    }
    entries: list[dict[str, Any]] = []
    for row in capabilities:
        entries.append(_capability_entry(row))
    for row in contributions:
        if row.get("kind") == "configuration":
            descriptor = row.get("descriptor")
            schema = descriptor.get("schema") if isinstance(descriptor, dict) else None
            if isinstance(schema, dict):
                entries.extend(_configuration_entries(
                    {"owner": row.get("owner"), "schema": schema}, active_owners))
            continue
        entry = _contribution_entry(row)
        if entry is not None:
            entries.append(entry)
    for record in configurations:
        entries.extend(_configuration_entries(record, active_owners))

    # Multiple providers may expose the same capability ID.  Keep their target
    # metadata but make presentation paths deterministic rather than hiding an
    # ambiguity from the operator.
    counts: dict[str, int] = {}
    for entry in entries:
        counts[entry["path"]] = counts.get(entry["path"], 0) + 1
    for entry in entries:
        if counts[entry["path"]] > 1:
            entry["path"] = f'{entry["path"]}@{entry["owner"]}'
            if entry["kind"] == "capability":
                entry["provider_required"] = True

    entries.sort(key=lambda row: (row["path"], row["kind"], row["owner"]))
    state = "error" if any(row["status"] == "error" for row in sources.values()) else (
        "empty" if not entries else "ready"
    )
    document = {
        "surface_version": SURFACE_VERSION,
        "state": state,
        "entry_count": len(entries),
        "sources": sources,
        "entries": entries,
    }
    raw = json.dumps(document, sort_keys=True, separators=(",", ":")).encode()
    document["digest"] = hashlib.sha256(raw).hexdigest()
    return document


def children(surface: dict[str, Any], prefix: str = "") -> list[dict[str, Any]]:
    """Return immediate namespace children for a frontend.

    This is a pure projection helper.  Selecting a leaf never executes it.
    """
    entries = _bounded_list(surface.get("entries", []), "surface entries")
    prefix = prefix.strip(".")
    result: dict[str, dict[str, Any]] = {}
    base = prefix + "." if prefix else ""
    for entry in entries:
        path = entry.get("path")
        if not isinstance(path, str) or not path.startswith(base):
            continue
        remainder = path[len(base):]
        if not remainder:
            continue
        segment, dot, _rest = remainder.partition(".")
        child_path = base + segment
        node = result.setdefault(segment, {
            "name": segment,
            "path": child_path,
            "leaf": False,
            "has_children": False,
            "kind": "namespace",
            "availability": "active",
            "description": "",
            "entry": None,
        })
        if dot:
            node["has_children"] = True
        else:
            node["leaf"] = True
            node["kind"] = str(entry.get("kind") or "unknown")
            node["availability"] = _availability(entry.get("availability"))
            node["description"] = str(entry.get("description") or "")
            node["entry"] = copy.deepcopy(entry)
    return [result[key] for key in sorted(result)]


def main(argv: list[str]) -> int:
    try:
        if len(argv) != 2 or argv[1] not in {"build", "children"}:
            raise SurfaceError("usage: operator_surface.py {build|children}")
        payload = json.load(sys.stdin)
        if argv[1] == "build":
            result = build_surface(payload)
        else:
            surface = payload.get("surface")
            if not isinstance(surface, dict):
                raise SurfaceError("children requires surface")
            result = children(surface, str(payload.get("prefix") or ""))
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 0
    except (SurfaceError, ValueError, TypeError, json.JSONDecodeError) as exc:
        print(f"operator surface: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
