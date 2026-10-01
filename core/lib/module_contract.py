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
import math
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
_COMMON_KEYS = {"kind", "id", "requires", "path", "handler", "output_type", "timeout_seconds",
                "object_kind", "properties", "freshness_seconds", "privilege", "required_facts",
                "capability_version", "description", "inputs", "safety", "preconditions",
                "verification", "recovery", "affects", "payload_schema", "trigger", "target",
                "schema", "outputs"}
_REQUIRES_KEYS = {"modules", "capabilities", "platform_families", "platform_features", "bins"}
_PLATFORM_FAMILIES = {"debian", "arch"}
_REQUIRED_MODULE_KEYS = {"module_api", "name", "display_name", "version"}
_EVENT_ENVELOPE_KEYS = {"schema_version", "event_id", "event_type", "source", "owner",
                        "related_objects", "occurred_at", "recorded_at", "severity", "evidence",
                        "correlation_id", "causation_id", "operation_id", "capability_id"}


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


def _closed_object(value: Any, allowed: set[str], where: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise _error(f"{where} must be an object")
    unknown = set(value) - allowed
    if unknown:
        raise _error(f"{where} has unknown field {min(unknown)}")
    return value


def _validate_capability_metadata(item: dict[str, Any], where: str) -> dict[str, Any]:
    fields = {"capability_version", "description", "inputs", "safety", "privilege",
              "preconditions", "verification", "recovery", "affects"}
    present = (fields | {"outputs"}) & set(item)
    if not present:
        # Bare Wave C declarations remain inspectable, but unavailable.
        return {}
    missing = fields - set(item)
    if missing:
        raise _error(f"{where} missing capability field {min(missing)}")
    if type(item["capability_version"]) is not int or item["capability_version"] not in {1, 2}:
        raise _error(f"{where}.capability_version must be 1 or 2")
    if item["capability_version"] == 2:
        from capability_runtime import CapabilityError, validate_output_schema
        try:
            validate_output_schema(item.get("outputs"))
        except CapabilityError as exc:
            raise _error(f"{where}.outputs is invalid: {exc}") from exc
        fields.add("outputs")
    elif "outputs" in item:
        raise _error(f"{where}.outputs requires capability_version 2")
    if not isinstance(item["description"], str) or not item["description"].strip() or len(item["description"]) > 500:
        raise _error(f"{where}.description must be bounded non-empty text")
    if item["privilege"] not in {"none", "required"}:
        raise _error(f"{where}.privilege must be none or required")
    safety = _closed_object(item["safety"], {"tier"}, f"{where}.safety")
    if set(safety) != {"tier"} or safety["tier"] not in {"READ", "CHANGE", "DESTROY"}:
        raise _error(f"{where}.safety.tier must be READ, CHANGE or DESTROY")
    inputs = _closed_object(item["inputs"], {"properties", "required", "additionalProperties"}, f"{where}.inputs")
    if set(inputs) != {"properties", "required", "additionalProperties"} or inputs["additionalProperties"] is not False:
        raise _error(f"{where}.inputs requires properties, required and additionalProperties=false")
    props = inputs["properties"]
    required = inputs["required"]
    if not isinstance(props, dict) or not isinstance(required, list) or any(type(n) is not str for n in required):
        raise _error(f"{where}.inputs has invalid properties or required")
    if len(props) > 32 or len(required) != len(set(required)) or set(required) - set(props):
        raise _error(f"{where}.inputs has invalid required fields")
    input_types = {"string", "integer", "number", "boolean", "enum", "object_id", "path", "secret_ref"}
    for name, raw in props.items():
        if not re.fullmatch(r"[a-z][a-z0-9_]*", name):
            raise _error(f"{where}.inputs has invalid property name")
        spec = _closed_object(raw, {"type", "validator", "enum", "minimum", "maximum",
                                    "minLength", "maxLength", "root", "namespace", "purpose"},
                              f"{where}.inputs.{name}")
        kind = spec.get("type")
        if kind not in input_types:
            raise _error(f"{where}.inputs.{name} has invalid type")
        if "validator" in spec:
            valid_validators = {
                "string": {"systemd_unit", "package_name"},
                "object_id": {"object_id"},
                "path": {"confined_path"},
            }
            if spec["validator"] not in valid_validators.get(kind, set()):
                raise _error(f"{where}.inputs.{name} has invalid validator for its type")
        if kind == "enum":
            choices = spec.get("enum")
            if not isinstance(choices, list) or not choices or len(choices) != len(set(map(str, choices))) or not all(type(c) in (str, int, bool) for c in choices):
                raise _error(f"{where}.inputs.{name} has invalid enum")
        elif "enum" in spec:
            raise _error(f"{where}.inputs.{name}.enum requires enum type")
        for bound in ("minimum", "maximum"):
            if bound in spec and (kind not in {"integer", "number"} or type(spec[bound]) not in (int, float)):
                raise _error(f"{where}.inputs.{name}.{bound} is invalid")
        for bound in ("minLength", "maxLength"):
            if bound in spec and (kind not in {"string", "path", "secret_ref", "object_id"} or type(spec[bound]) is not int or spec[bound] < 0):
                raise _error(f"{where}.inputs.{name}.{bound} is invalid")
        if kind == "path" and (not isinstance(spec.get("root"), str) or not spec["root"]):
            raise _error(f"{where}.inputs.{name}.root is required")
        if kind == "secret_ref" and (not isinstance(spec.get("namespace"), str) or not spec["namespace"] or not isinstance(spec.get("purpose"), str) or not spec["purpose"]):
            raise _error(f"{where}.inputs.{name} requires namespace and purpose")
        if kind != "path" and "root" in spec or kind != "secret_ref" and set(spec) & {"namespace", "purpose"}:
            raise _error(f"{where}.inputs.{name} has type-incompatible fields")
    preconditions = item["preconditions"]
    if not isinstance(preconditions, list) or len(preconditions) > 16:
        raise _error(f"{where}.preconditions must be a bounded array")
    precondition_fields = {"kind", "input", "path", "capability_id", "object_id", "property", "state_class", "equals", "feature", "validator"}
    for index, raw in enumerate(preconditions):
        pre = _closed_object(raw, precondition_fields, f"{where}.preconditions[{index}]")
        kind = pre.get("kind")
        allowed_by_kind = {
            "owner_active": {"kind"},
            "capability_available": {"kind", "capability_id"},
            "platform_feature": {"kind", "feature"},
            "path_exists": {"kind", "input"},
            "package_installed": {"kind", "input"},
            "service_exists": {"kind", "input"},
            "model_fact": {"kind", "object_id", "property", "state_class", "equals"},
            "trusted_validator": {"kind", "validator"},
        }
        if kind not in allowed_by_kind:
            raise _error(f"{where}.preconditions[{index}] has invalid kind")
        if set(pre) - allowed_by_kind[kind]:
            raise _error(f"{where}.preconditions[{index}] has incompatible fields")
        if kind in {"path_exists", "package_installed", "service_exists"} and pre.get("input") not in props:
            raise _error(f"{where}.preconditions[{index}] references unknown input")
        if kind == "path_exists" and props[pre["input"]].get("type") != "path":
            raise _error(f"{where}.preconditions[{index}] requires a path input")
        if kind == "capability_available":
            _validate_id(pre.get("capability_id"), f"{where}.preconditions[{index}].capability_id")
        if kind == "model_fact" and (not isinstance(pre.get("object_id"), str) or
                                     not isinstance(pre.get("property"), str) or
                                     pre.get("state_class", "observed") != "observed" or "equals" not in pre):
            raise _error(f"{where}.preconditions[{index}] has invalid model fact selector")
        if kind in {"platform_feature", "trusted_validator"} and not isinstance(
            pre.get("feature" if kind == "platform_feature" else "validator"), str
        ):
            raise _error(f"{where}.preconditions[{index}] requires a named check")
    verification = _closed_object(item["verification"], {"kind", "required", "observer", "object_id", "property", "input", "equals", "check_id", "timeout_seconds"}, f"{where}.verification")
    if verification.get("kind") not in {"none", "observer_fact", "service_state", "trusted_query"} or type(verification.get("required")) is not bool:
        raise _error(f"{where}.verification has invalid kind or required flag")
    if verification["kind"] == "none" and verification["required"]:
        raise _error(f"{where}.verification none cannot be required")
    if "input" in verification and verification["input"] not in props:
        raise _error(f"{where}.verification references unknown input")
    recovery = _closed_object(item["recovery"], {"class", "capability_id", "description"}, f"{where}.recovery")
    if recovery.get("class") not in {"not_applicable", "reversible", "best_effort", "compensating_action", "snapshot_required", "irreversible"}:
        raise _error(f"{where}.recovery has invalid class")
    if "capability_id" in recovery:
        _validate_id(recovery["capability_id"], f"{where}.recovery.capability_id")
    affects = item["affects"]
    if not isinstance(affects, list) or len(affects) > 16:
        raise _error(f"{where}.affects must be a bounded array")
    for index, raw in enumerate(affects):
        affect = _closed_object(raw, {"object", "id", "input"}, f"{where}.affects[{index}]")
        if affect.get("object") not in {"host", "service", "package"} or ("id" in affect) == ("input" in affect):
            raise _error(f"{where}.affects[{index}] has invalid object selector")
        if "input" in affect and affect["input"] not in props:
            raise _error(f"{where}.affects[{index}] references unknown input")
    if safety["tier"] != "READ" and not verification["required"] and verification["kind"] != "none":
        raise _error(f"{where}.verification must be required for a state change")
    return {field: item[field] for field in fields}


def _validate_contribution(package: Path, item: Any, index: int, source: str,
                           owner: str) -> dict[str, Any]:
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
    if kind == "automation":
        trigger = _closed_object(item.get("trigger"), {"kind", "schema_version", "once_at"}, f"{where}.trigger")
        if (trigger.get("kind") != "once_at" or type(trigger.get("schema_version")) is not int or
                trigger["schema_version"] != 1 or "once_at" in trigger):
            raise _error(f"{where}.trigger must propose version-1 once_at without an operator time")
        target = _closed_object(item.get("target"), {"capability_id", "provider", "inputs"}, f"{where}.target")
        if "capability_id" not in target or "inputs" not in target:
            raise _error(f"{where}.target requires capability_id and inputs")
        _validate_id(target["capability_id"], f"{where}.target.capability_id")
        if "." not in target["capability_id"]:
            raise _error(f"{where}.target.capability_id must be dotted")
        if not isinstance(target["inputs"], dict):
            raise _error(f"{where}.target.inputs must be an object")
        if "provider" in target:
            _validate_id(target["provider"], f"{where}.target.provider")
        result.update(trigger=trigger, target=target)
    elif "trigger" in item or "target" in item:
        raise _error(f"{where}.trigger/target are automation-only")
    if kind == "domain_event":
        if not re.fullmatch(r"[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*", result["id"]):
            raise _error(f"{where}.id must be owner.domain.occurrence")
        schema = _closed_object(item.get("payload_schema"),
                                {"properties", "required", "additionalProperties"},
                                f"{where}.payload_schema")
        if set(schema) != {"properties", "required", "additionalProperties"} or schema["additionalProperties"] is not False:
            raise _error(f"{where}.payload_schema must be closed")
        props, required = schema["properties"], schema["required"]
        if (not isinstance(props, dict) or len(props) > 32 or not isinstance(required, list) or
                any(type(field) is not str for field in required) or
                len(required) != len(set(required)) or set(required) - set(props)):
            raise _error(f"{where}.payload_schema has invalid fields")
        for name, raw in props.items():
            if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", name):
                raise _error(f"{where}.payload_schema has invalid property name")
            if name in _EVENT_ENVELOPE_KEYS:
                raise _error(f"{where}.payload_schema cannot redeclare Core field {name}")
            spec = _closed_object(raw, {"type", "enum", "minimum", "maximum", "minLength", "maxLength"}, f"{where}.payload_schema.{name}")
            typ = spec.get("type")
            if typ not in {"string", "boolean", "integer", "number", "enum", "object_id"}:
                raise _error(f"{where}.payload_schema.{name} has invalid type")
            if typ == "enum":
                choices = spec.get("enum")
                if not isinstance(choices, list) or not choices or len(choices) > 32 or any(type(c) not in (str, int, bool) for c in choices):
                    raise _error(f"{where}.payload_schema.{name} has invalid enum")
            elif "enum" in spec:
                raise _error(f"{where}.payload_schema.{name} has unexpected enum")
            for bound in ("minimum", "maximum"):
                if bound in spec and (typ not in {"integer", "number"} or type(spec[bound]) not in (int, float) or
                                      not math.isfinite(spec[bound])):
                    raise _error(f"{where}.payload_schema.{name} has invalid bound")
            if "minimum" in spec and "maximum" in spec and spec["minimum"] > spec["maximum"]:
                raise _error(f"{where}.payload_schema.{name} has reversed bounds")
            for bound in ("minLength", "maxLength"):
                if bound in spec and (typ not in {"string", "object_id"} or type(spec[bound]) is not int or not 0 <= spec[bound] <= 256):
                    raise _error(f"{where}.payload_schema.{name} has invalid length")
        result["payload_schema"] = schema
    elif "payload_schema" in item:
        raise _error(f"{where}.payload_schema is domain_event-only")
    capability_fields = {"capability_version", "description", "inputs", "safety",
                         "preconditions", "verification", "recovery", "affects", "outputs"}
    if kind == "capability":
        if result["id"].count(".") < 1:
            raise _error(f"{where}.id requires at least two dotted segments")
        result.update(_validate_capability_metadata(item, where))
    elif set(item) & capability_fields:
        raise _error(f"{where} has capability-only metadata")
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
    if kind == "configuration" and "schema" in item:
        try:
            from configuration_schema import validate_schema
            result["schema"] = validate_schema(item["schema"], owner)
        except (ImportError, ValueError) as exc:
            raise _error(f"{where}.schema is invalid: {exc}") from exc
    elif "schema" in item:
        raise _error(f"{where}.schema is configuration-only")
    if kind in executable_kinds and "handler" not in result and not (
            kind == "configuration" and "schema" in result):
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
    if kind == "observer" and "properties" in item:
        if item.get("object_kind") != "host":
            raise _error(f"{where}.object_kind must be host")
        props = item["properties"]
        if not isinstance(props, list) or not props:
            raise _error(f"{where}.properties must be non-empty")
        names = set()
        for prop in props:
            if not isinstance(prop, dict) or set(prop) - {"name", "value_type", "minimum"} or set(prop) & {"name", "value_type"} != {"name", "value_type"}:
                raise _error(f"{where}.properties has invalid entry")
            name = prop["name"]
            if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_.]*", name) or name in names:
                raise _error(f"{where}.properties has duplicate or invalid name")
            names.add(name)
            if not isinstance(prop["value_type"], str) or prop["value_type"] not in {"integer", "number", "boolean", "string"}:
                raise _error(f"{where}.properties has unsupported value type")
            if "minimum" in prop and (prop["value_type"] not in {"integer", "number"} or type(prop["minimum"]) not in (int, float)):
                raise _error(f"{where}.properties has invalid minimum")
        ttl = item.get("freshness_seconds")
        if type(ttl) is not int or ttl <= 0 or ttl > 86400:
            raise _error(f"{where}.freshness_seconds must be 1..86400")
        if not isinstance(item.get("privilege", "none"), str) or item.get("privilege", "none") not in {"none", "required"}:
            raise _error(f"{where}.privilege must be none or required")
        result.update(object_kind="host", properties=props, freshness_seconds=ttl,
                      privilege=item.get("privilege", "none"))
    elif kind == "observer" and set(item) & {"object_kind", "freshness_seconds", "privilege"}:
        raise _error(f"{where}.properties required with observer metadata")
    if kind == "check" and "required_facts" in item:
        if item.get("object_kind") != "host":
            raise _error(f"{where}.object_kind must be host")
        required = item["required_facts"]
        if not isinstance(required, list) or not required:
            raise _error(f"{where}.required_facts must be non-empty")
        names = set()
        for fact in required:
            if not isinstance(fact, dict) or set(fact) != {"property", "state_class", "observer"}:
                raise _error(f"{where}.required_facts has invalid entry")
            if not all(isinstance(fact[k], str) and fact[k] for k in fact):
                raise _error(f"{where}.required_facts has invalid value")
            if fact["state_class"] != "observed" or not _ID_RE.fullmatch(fact["observer"]):
                raise _error(f"{where}.required_facts has unsupported source")
            if fact["property"] in names:
                raise _error(f"{where}.required_facts has duplicate property")
            names.add(fact["property"])
        result.update(object_kind="host", required_facts=required)
    elif kind == "check" and "object_kind" in item:
        raise _error(f"{where}.required_facts required with object_kind")
    if kind not in {"observer", "capability"} and set(item) & {"properties", "freshness_seconds", "privilege"}:
        raise _error(f"{where} has observer-only metadata")
    if kind == "capability" and set(item) & {"properties", "freshness_seconds"}:
        raise _error(f"{where} has observer-only metadata")
    if kind not in {"observer", "check"} and "object_kind" in item:
        raise _error(f"{where}.object_kind is unsupported")
    if kind != "check" and "required_facts" in item:
        raise _error(f"{where}.required_facts is check-only")
    if "path" in result and kind != "knowledge":
        raise _error(f"{where}.path is only valid for knowledge contributions")
    if "handler" in result and kind not in {"knowledge", "observer", "check", "capability", "configuration", "lifecycle"}:
        raise _error(f"{where}.handler is not supported for kind {kind}")
    if "output_type" in result and kind not in {"observer", "check"}:
        raise _error(f"{where}.output_type is not supported for kind {kind}")
    if "timeout_seconds" in result and kind not in {"observer", "check", "capability"}:
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
            value = _validate_contribution(package, item, index, contract, name)
            if value["kind"] == "domain_event" and not value["id"].startswith(name + "."):
                raise _error(f"domain event {value['id']} must belong to {name}")
            if value["kind"] == "automation" and not value["id"].startswith(name + "."):
                raise _error(f"automation proposal {value['id']} must belong to {name}")
            if value["kind"] == "domain_event" and value["id"] == "capability.completed":
                raise _error("capability.completed is Core-reserved")
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
