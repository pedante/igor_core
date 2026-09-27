#!/usr/bin/env python3
"""Strict Module API v2 manifest and contribution contract validation.

This module deliberately validates data only.  It does not import or execute a
module entrypoint.  The shell loader uses the command line interface below:

    module_contract.py probe MODULE_DIR
    module_contract.py validate MODULE_DIR

The JSON emitted by ``validate`` is a normalized representation intended for
the loader's staging/registration boundary.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

SUPPORTED_API = 2
SUPPORTED_CONTRACT = 1
SUPPORTED_RUNTIME = "bash"
_ID_RE = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
_VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$")
_HANDLER_RE = re.compile(r"^[a-z][a-z0-9_]*__[a-z][a-z0-9_]*$")
_KNOWN_SECTIONS = {"module", "requirements", "compat"}
_SECTION_KEYS = {
    "module": {"module_api", "name", "display_name", "version", "runtime", "entrypoint", "contracts"},
    "requirements": {
        "required_modules", "optional_modules", "required_capabilities",
        "optional_capabilities", "platform_families", "required_bins",
    },
    "compat": {"v1_hooks"},
}
_KINDS = {
    "knowledge", "observer", "capability", "check", "domain_event",
    "automation", "relationship", "configuration", "lifecycle",
}
_COMMON_KEYS = {"kind", "id", "requires", "path", "handler", "output_type", "timeout_seconds"}
_REQUIRES_KEYS = {"modules", "capabilities", "platform_families", "platform_features", "bins"}
_PLATFORM_FAMILIES = {"debian", "arch"}
_REQUIRED_MODULE_KEYS = {"module_api", "name", "display_name", "version"}


class ValidationError(ValueError):
    """A deterministic, user-facing contract validation failure."""


def _error(message: str) -> ValidationError:
    return ValidationError(message)


def _parse_scalar_list(value: str, field: str) -> list[str]:
    if not value.strip():
        return []
    items = [part.strip() for part in value.split(",")]
    if any(not item for item in items):
        raise _error(f"{field} contains an empty item")
    if any("\n" in item or "\r" in item for item in items):
        raise _error(f"{field} contains a newline")
    return items


def _parse_bool(value: str, field: str) -> bool:
    if value == "true":
        return True
    if value == "false":
        return False
    raise _error(f"{field} must be true or false")


def _parse_manifest(path: Path) -> dict[str, dict[str, str]]:
    """Parse the v2 INI subset, rejecting configparser's permissive behavior."""
    values: dict[str, dict[str, str]] = {}
    section: str | None = None
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise _error(f"cannot read module.conf: {exc.strerror or exc}") from exc
    for line_number, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("["):
            if not line.endswith("]") or line.count("[") != 1 or line.count("]") != 1:
                raise _error(f"module.conf line {line_number}: malformed section")
            section = line[1:-1].strip()
            if section not in _KNOWN_SECTIONS:
                raise _error(f"module.conf line {line_number}: unknown section [{section}]")
            if section in values:
                raise _error(f"module.conf line {line_number}: duplicate section [{section}]")
            values[section] = {}
            continue
        if section is None:
            raise _error(f"module.conf line {line_number}: key outside section")
        if "=" not in line:
            raise _error(f"module.conf line {line_number}: expected key=value")
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        if not key or not re.fullmatch(r"[a-z][a-z0-9_]*", key):
            raise _error(f"module.conf line {line_number}: invalid key")
        if key not in _SECTION_KEYS[section]:
            raise _error(f"module.conf line {line_number}: unknown key {key}")
        if key in values[section]:
            raise _error(f"module.conf line {line_number}: duplicate key {key}")
        # Comments are line oriented by contract.  Reject likely inline
        # comments rather than silently changing a declared value.
        if " #" in value or " ;" in value:
            raise _error(f"module.conf line {line_number}: inline comments are not allowed")
        values[section][key] = value
    return values


def probe_api(module_dir: str | os.PathLike[str]) -> str:
    """Return the API marker (``1``, ``2`` or ``unsupported:<value>``).

    A missing marker is the v1 compatibility form.  A malformed marker is an
    error and must never fall through to the v1 parser.
    """
    path = Path(module_dir) / "module.conf"
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise _error(f"cannot read module.conf: {exc.strerror or exc}") from exc
    section: str | None = None
    marker: str | None = None
    marker_outside_module: tuple[int, str] | None = None
    for line_number, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            continue
        if "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        if key != "module_api":
            continue
        if section != "module":
            marker_outside_module = (line_number, value)
            continue
        if marker is not None:
            raise _error(f"module.conf line {line_number}: duplicate key module_api")
        if " #" in value or " ;" in value or not re.fullmatch(r"[0-9]+", value):
            raise _error(f"module_api marker is malformed: {value!r}")
        marker = value
    if marker_outside_module is not None:
        raise _error(
            f"module.conf line {marker_outside_module[0]}: module_api must be in [module]"
        )
    if marker is None:
        return "1"
    if not re.fullmatch(r"[0-9]+", marker):
        raise _error(f"module_api marker is malformed: {marker!r}")
    if marker == "1":
        return "1"
    if marker == str(SUPPORTED_API):
        return "2"
    return f"unsupported:{marker}"


def _contained(package: Path, relative: str, field: str) -> Path:
    if not relative or "\x00" in relative:
        raise _error(f"{field} must be a non-empty relative path")
    candidate = Path(relative)
    if candidate.is_absolute() or any(part == ".." for part in candidate.parts):
        raise _error(f"{field} escapes module package: {relative}")
    resolved = (package / candidate).resolve()
    try:
        resolved.relative_to(package.resolve())
    except ValueError as exc:
        raise _error(f"{field} escapes module package: {relative}") from exc
    return resolved


def _validate_id(value: Any, field: str) -> str:
    if not isinstance(value, str) or not _ID_RE.fullmatch(value):
        raise _error(f"{field} must be a canonical lowercase identifier")
    return value


def _validate_requirement_map(value: Any, where: str) -> dict[str, list[str]]:
    if not isinstance(value, dict):
        raise _error(f"{where}.requires must be an object")
    unknown = set(value) - _REQUIRES_KEYS
    if unknown:
        raise _error(f"{where}.requires has unknown field {min(unknown)}")
    result: dict[str, list[str]] = {}
    for key in sorted(_REQUIRES_KEYS):
        if key not in value:
            continue
        items = value[key]
        if not isinstance(items, list) or not all(isinstance(item, str) and item for item in items):
            raise _error(f"{where}.requires.{key} must be an array of non-empty strings")
        if len(items) != len(set(items)):
            raise _error(f"{where}.requires.{key} contains duplicate entries")
        if key in {"modules", "capabilities"}:
            items = [_validate_id(item, f"{where}.requires.{key}") for item in items]
        if key == "platform_families":
            unknown = sorted(set(items) - _PLATFORM_FAMILIES)
            if unknown:
                raise _error(f"{where}.requires.platform_families has unsupported family {min(unknown)}")
        if key == "bins":
            for item in items:
                if not re.fullmatch(r"[A-Za-z0-9_.+-]+", item):
                    raise _error(f"{where}.requires.bins has invalid binary name {item!r}")
        result[key] = list(items)
    # Step 7 owns the normalized feature vocabulary.  Keep syntactically valid
    # declarations in the normalized record so the loader can mark only this
    # contribution unavailable; unknown features must never be assumed true.
    return result


def _json_load(path: Path, source: str) -> Any:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise _error(f"{source} contains duplicate JSON key {key}")
            result[key] = value
        return result

    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates)
    except ValidationError:
        raise
    except (OSError, UnicodeError) as exc:
        raise _error(f"cannot read {source}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise _error(f"{source} contains invalid JSON at line {exc.lineno} column {exc.colno}") from exc


def _validate_contribution(package: Path, item: Any, index: int, source: str) -> dict[str, Any]:
    where = f"{source} contribution {index}"
    if not isinstance(item, dict):
        raise _error(f"{where} must be an object")
    unknown = set(item) - _COMMON_KEYS
    if unknown:
        raise _error(f"{where} has unknown field {min(unknown)}")
    if "kind" not in item or "id" not in item:
        raise _error(f"{where} requires kind and id")
    kind = item["kind"]
    if kind not in _KINDS:
        raise _error(f"{where} has unsupported kind {kind!r}")
    result: dict[str, Any] = {"kind": kind, "id": _validate_id(item["id"], f"{where}.id")}
    if "requires" in item:
        result["requires"] = _validate_requirement_map(item["requires"], where)
    if "path" in item:
        path = item["path"]
        if not isinstance(path, str):
            raise _error(f"{where}.path must be a string")
        resolved = _contained(package, path, f"{where}.path")
        if not resolved.is_file():
            raise _error(f"{where}.path does not exist: {path}")
        result["path"] = path
    if "handler" in item:
        handler = item["handler"]
        if not isinstance(handler, str) or not _HANDLER_RE.fullmatch(handler):
            raise _error(f"{where}.handler is not a valid Bash handler reference")
        result["handler"] = handler
    executable_kinds = {"observer", "check", "capability", "configuration", "lifecycle"}
    if kind in executable_kinds and "handler" not in result:
        raise _error(f"{where} requires handler")
    if kind == "knowledge" and "path" not in result and "handler" not in result:
        raise _error(f"{where} requires path or handler")
    if "output_type" in item:
        if not isinstance(item["output_type"], str) or not item["output_type"]:
            raise _error(f"{where}.output_type must be a non-empty string")
        result["output_type"] = item["output_type"]
    if "timeout_seconds" in item:
        timeout = item["timeout_seconds"]
        if isinstance(timeout, bool) or not isinstance(timeout, int) or timeout <= 0:
            raise _error(f"{where}.timeout_seconds must be a positive integer")
        result["timeout_seconds"] = timeout
    if kind == "observer" and "output_type" not in result:
        raise _error(f"{where} requires output_type")
    if "path" in result and kind != "knowledge":
        raise _error(f"{where}.path is only valid for knowledge contributions")
    if "handler" in result and kind not in {"knowledge", "observer", "check", "capability", "configuration", "lifecycle"}:
        raise _error(f"{where}.handler is not supported for kind {kind}")
    if "output_type" in result and kind not in {"observer", "check"}:
        raise _error(f"{where}.output_type is not supported for kind {kind}")
    if "timeout_seconds" in result and kind not in {"observer", "check"}:
        raise _error(f"{where}.timeout_seconds is not supported for kind {kind}")
    if "path" in result and "handler" in result and kind not in {"knowledge"}:
        raise _error(f"{where} cannot declare both path and handler")
    return result


def _validate_handler_code(package: Path, entrypoint: str, handlers: list[str], owner: str) -> None:
    """Check handler syntax and declarations without sourcing module code."""
    path = _contained(package, entrypoint, "module.entrypoint")
    try:
        check = subprocess.run(
            ["bash", "-n", str(path)], capture_output=True, text=True, check=False,
        )
    except OSError as exc:
        raise _error(f"cannot validate Bash entrypoint: {exc}") from exc
    if check.returncode:
        raise _error(f"module.entrypoint has invalid Bash syntax: {entrypoint}")
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise _error(f"cannot read module.entrypoint: {exc}") from exc
    declared = set(re.findall(r"(?m)^\s*(?:function\s+)?([a-z][a-z0-9_]*__[a-z][a-z0-9_]*)\s*(?:\(\s*\))?\s*\{", source))
    for handler in handlers:
        if not handler.startswith(owner + "__"):
            raise _error(f"handler {handler} must belong to module {owner}")
        if handler not in declared:
            raise _error(f"handler {handler} is not declared in {entrypoint}")


def validate_module(module_dir: str | os.PathLike[str]) -> dict[str, Any]:
    package = Path(module_dir).resolve()
    if not package.is_dir():
        raise _error(f"module directory does not exist: {module_dir}")
    sections = _parse_manifest(package / "module.conf")
    module = sections.get("module", {})
    marker = module.get("module_api")
    if marker != str(SUPPORTED_API):
        if marker is None:
            raise _error("module_api=2 is required for v2 validation")
        raise _error(f"unsupported module_api: {marker}")
    missing = _REQUIRED_MODULE_KEYS - set(module)
    if missing:
        raise _error(f"[module] missing required key {min(missing)}")
    name = _validate_id(module["name"], "module.name")
    if name != package.name:
        raise _error(f"module.name {name!r} does not match package directory {package.name!r}")
    if not module["display_name"] or "\n" in module["display_name"]:
        raise _error("module.display_name must be non-empty")
    if not _VERSION_RE.fullmatch(module["version"]):
        raise _error("module.version must be MAJOR.MINOR.PATCH")
    runtime = module.get("runtime")
    if runtime is not None and runtime != SUPPORTED_RUNTIME:
        raise _error(f"unsupported runtime: {runtime}")
    entrypoint = module.get("entrypoint")
    if entrypoint is not None:
        resolved = _contained(package, entrypoint, "module.entrypoint")
        if not resolved.is_file():
            raise _error(f"module.entrypoint does not exist: {entrypoint}")
    contracts = _parse_scalar_list(module.get("contracts", ""), "module.contracts")
    if len(contracts) != len(set(contracts)):
        raise _error("module.contracts contains duplicate paths")
    normalized = {
        "module_api": SUPPORTED_API,
        "name": name,
        "display_name": module["display_name"],
        "version": module["version"],
        "runtime": runtime,
        "entrypoint": entrypoint,
        "contracts": contracts,
        "requirements": {},
        "compat": {},
    }
    requirements = sections.get("requirements", {})
    for key in sorted(_SECTION_KEYS["requirements"]):
        normalized["requirements"][key] = _parse_scalar_list(requirements.get(key, ""), f"requirements.{key}")
    for key in ("required_modules", "optional_modules", "required_capabilities", "optional_capabilities"):
        for item in normalized["requirements"][key]:
            _validate_id(item, f"requirements.{key}")
    for key, values in normalized["requirements"].items():
        if len(values) != len(set(values)):
            raise _error(f"requirements.{key} contains duplicates")
    families = set(normalized["requirements"]["platform_families"])
    unsupported = sorted(families - _PLATFORM_FAMILIES)
    if unsupported:
        raise _error(f"requirements.platform_families has unsupported family {unsupported[0]}")
    for item in normalized["requirements"]["required_bins"]:
        if not re.fullmatch(r"[A-Za-z0-9_.+-]+", item):
            raise _error(f"requirements.required_bins has invalid binary name {item!r}")
    normalized["compat"]["v1_hooks"] = _parse_bool(sections.get("compat", {}).get("v1_hooks", "false"), "compat.v1_hooks")
    contributions: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    for contract in contracts:
        contract_path = _contained(package, contract, "module.contracts")
        if not contract_path.is_file():
            raise _error(f"module.contracts path does not exist: {contract}")
        payload = _json_load(contract_path, contract)
        if not isinstance(payload, dict):
            raise _error(f"{contract} must contain an object")
        if set(payload) - {"contract_version", "contributions"}:
            raise _error(f"{contract} has unknown top-level field {min(set(payload) - {'contract_version', 'contributions'})}")
        if payload.get("contract_version") != SUPPORTED_CONTRACT:
            raise _error(f"{contract} has unsupported contract_version {payload.get('contract_version')!r}")
        declared = payload.get("contributions")
        if not isinstance(declared, list):
            raise _error(f"{contract}.contributions must be an array")
        for index, item in enumerate(declared, 1):
            value = _validate_contribution(package, item, index, contract)
            identity = (value["kind"], value["id"])
            if identity in seen:
                raise _error(f"duplicate contribution {value['kind']}:{value['id']}")
            seen.add(identity)
            value["source"] = contract
            value["owner"] = name
            contributions.append(value)
    handlers = [value["handler"] for value in contributions if "handler" in value]
    if normalized["compat"]["v1_hooks"] and (runtime != SUPPORTED_RUNTIME or not entrypoint):
        raise _error("v1_hooks requires runtime=bash and module.entrypoint")
    if handlers:
        if runtime != SUPPORTED_RUNTIME:
            raise _error("handler declarations require runtime=bash")
        if not entrypoint:
            raise _error("handler declarations require module.entrypoint")
    if entrypoint and runtime == SUPPORTED_RUNTIME:
        _validate_handler_code(package, entrypoint, handlers, name)
    return {"manifest": normalized, "contributions": contributions}


def _main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in {"probe", "validate", "fields"}:
        print("usage: module_contract.py {probe|validate|fields} MODULE_DIR", file=sys.stderr)
        return 2
    try:
        if argv[1] == "probe":
            print(probe_api(argv[2]))
        elif argv[1] == "validate":
            print(json.dumps(validate_module(argv[2]), sort_keys=True, separators=(",", ":")))
        else:
            data = validate_module(argv[2])
            manifest = data["manifest"]
            manifest_fields = {
                "module_api": "2",
                "name": manifest["name"],
                "display_name": manifest["display_name"],
                "version": manifest["version"],
                "runtime": manifest["runtime"],
                "entrypoint": manifest["entrypoint"],
                "contracts": ",".join(manifest["contracts"]),
                "v1_hooks": "true" if manifest["compat"]["v1_hooks"] else "false",
            }
            for key, raw_value in manifest_fields.items():
                value = "" if raw_value is None else str(raw_value)
                if "\t" in value or "\n" in value:
                    raise _error(f"manifest field {key} contains a tab or newline")
                print("manifest\t" + key + "\t" + value)
            for key, values in sorted(manifest["requirements"].items()):
                value = ",".join(values)
                print("manifest\t" + key + "\t" + value)
            for contribution in data["contributions"]:
                requires = json.dumps(contribution.get("requires", {}), sort_keys=True, separators=(",", ":"))
                fields = [
                    "contribution", contribution["kind"], contribution["id"], contribution["source"],
                    contribution.get("handler", ""), contribution.get("path", ""), requires,
                    str(contribution.get("timeout_seconds", "")),
                ]
                if any("\t" in field or "\n" in field for field in fields):
                    raise _error(f"contribution {contribution['id']} contains a tab or newline")
                print("\t".join(fields))
        return 0
    except ValidationError as exc:
        print(f"module contract: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv))
