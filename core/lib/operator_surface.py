#!/usr/bin/env python3
"""Read-only projection of Igor-owned contracts into a browsable operator surface.

This module never executes a capability, mutates configuration, probes the host,
or loads a module.  It turns existing registry/inspection records into stable UI
metadata so TUI, CLI, and future frontends can share one discoverability model.
"""

from __future__ import annotations

import copy
import fcntl
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any

SURFACE_VERSION = 1
CACHE_VERSION = 1
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
    allowed = {*_SOURCE_NAMES, "sources", "seed_version", "availability_model",
               "compiled_source_digest"}
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
    configuration_keys: set[tuple[str, str]] = set()
    for row in capabilities:
        entries.append(_capability_entry(row))
    for row in contributions:
        if row.get("kind") == "configuration":
            descriptor = row.get("descriptor")
            schema = descriptor.get("schema") if isinstance(descriptor, dict) else None
            if isinstance(schema, dict):
                projected = _configuration_entries(
                    {"owner": row.get("owner"), "schema": schema}, active_owners)
                for entry in projected:
                    configuration_keys.add((entry["owner"], entry["target_id"]))
                    entries.append(entry)
            continue
        entry = _contribution_entry(row)
        if entry is not None:
            entries.append(entry)
    for record in configurations:
        for entry in _configuration_entries(record, active_owners):
            key = (entry["owner"], entry["target_id"])
            if key in configuration_keys:
                continue
            configuration_keys.add(key)
            entries.append(entry)

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
        "availability_model": str(payload.get("availability_model") or "runtime_snapshot"),
    }
    source_digest = payload.get("compiled_source_digest")
    if source_digest is not None:
        if not isinstance(source_digest, str) or not re.fullmatch(r"[0-9a-f]{64}", source_digest):
            raise SurfaceError("invalid compiled source digest")
        document["compiled_source_digest"] = source_digest
    raw = json.dumps(document, sort_keys=True, separators=(",", ":")).encode()
    document["digest"] = hashlib.sha256(raw).hexdigest()
    return document


def _surface_digest(surface: dict[str, Any]) -> str:
    candidate = copy.deepcopy(surface)
    digest = candidate.pop("digest", None)
    if not isinstance(digest, str):
        raise SurfaceError("cached surface digest missing")
    raw = json.dumps(candidate, sort_keys=True, separators=(",", ":")).encode()
    actual = hashlib.sha256(raw).hexdigest()
    if digest != actual:
        raise SurfaceError("cached surface digest mismatch")
    return digest


def _cache_directory(path: Path) -> Path:
    directory = path.parent
    try:
        directory.mkdir(parents=True, mode=0o700, exist_ok=True)
        info = directory.lstat()
    except OSError as exc:
        raise SurfaceError("operator surface cache directory unavailable") from exc
    if (directory.is_symlink() or not stat.S_ISDIR(info.st_mode) or
            info.st_uid != os.geteuid()):
        raise SurfaceError("operator surface cache directory is unsafe")
    # Do not make an existing shared directory stricter implicitly; simply
    # decline to persist derived metadata there.
    if stat.S_IMODE(info.st_mode) != 0o700:
        raise SurfaceError("operator surface cache directory is not private")
    return directory


def _cache_file_safe(path: Path) -> bool:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    except OSError:
        return False
    return (not path.is_symlink() and stat.S_ISREG(info.st_mode) and
            info.st_uid == os.geteuid() and info.st_nlink == 1 and
            stat.S_IMODE(info.st_mode) == 0o600)


def _read_cache(path: Path, source_digest: str) -> dict[str, Any] | None:
    if not _cache_file_safe(path):
        return None
    try:
        with path.open("r", encoding="utf-8") as stream:
            value = json.load(stream)
    except (OSError, ValueError, TypeError):
        return None
    if (not isinstance(value, dict) or value.get("cache_version") != CACHE_VERSION or
            value.get("source_digest") != source_digest):
        return None
    surface = value.get("surface")
    if not isinstance(surface, dict) or surface.get("surface_version") != SURFACE_VERSION:
        return None
    try:
        _surface_digest(surface)
    except SurfaceError:
        return None
    if surface.get("compiled_source_digest") != source_digest:
        return None
    return surface


def _write_cache(path: Path, source_digest: str, surface: dict[str, Any]) -> None:
    directory = _cache_directory(path)
    payload = {
        "cache_version": CACHE_VERSION,
        "source_digest": source_digest,
        "surface": surface,
    }
    fd, temporary = tempfile.mkstemp(prefix=".operator-surface-", dir=directory)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def cached_build_surface(payload: dict[str, Any], cache_path: Path) -> dict[str, Any]:
    """Return a compiled structural projection, reusing it across sessions.

    The cache is derived presentation metadata only. The digest is computed from
    the current validated registration seed, so package/module/schema changes
    rebuild it. Runtime availability is deliberately not part of this cache and
    remains the capability dispatcher's responsibility.
    """
    if not isinstance(payload, dict) or payload.get("seed_version") != 1:
        raise SurfaceError("invalid operator surface seed")
    source_raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    source_digest = hashlib.sha256(source_raw).hexdigest()

    # Cache failure must never make the operator namespace unavailable. Unsafe,
    # missing or corrupt derived state falls back to an in-memory rebuild.
    try:
        directory = _cache_directory(cache_path)
        lock_path = directory / (cache_path.name + ".lock")
        lock_fd = os.open(
            lock_path,
            os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
            0o600,
        )
        try:
            lock_info = os.fstat(lock_fd)
            if (not stat.S_ISREG(lock_info.st_mode) or lock_info.st_uid != os.geteuid() or
                    stat.S_IMODE(lock_info.st_mode) != 0o600):
                raise SurfaceError("operator surface cache lock is unsafe")
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
            cached = _read_cache(cache_path, source_digest)
            if cached is not None:
                return cached
            build_payload = {**payload, "compiled_source_digest": source_digest}
            surface = build_surface(build_payload)
            _write_cache(cache_path, source_digest, surface)
            return surface
        finally:
            os.close(lock_fd)
    except (OSError, SurfaceError):
        build_payload = {**payload, "compiled_source_digest": source_digest}
        return build_surface(build_payload)


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
        if len(argv) < 2 or argv[1] not in {"build", "cached-build", "children"}:
            raise SurfaceError("usage: operator_surface.py {build|cached-build|children} [CACHE]")
        payload = json.load(sys.stdin)
        if argv[1] == "build":
            if len(argv) != 2:
                raise SurfaceError("build takes no arguments")
            result = build_surface(payload)
        elif argv[1] == "cached-build":
            if len(argv) != 3:
                raise SurfaceError("cached-build requires cache path")
            result = cached_build_surface(payload, Path(argv[2]))
        else:
            if len(argv) != 2:
                raise SurfaceError("children takes no arguments")
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
