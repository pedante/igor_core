"""Resolution, execution fencing and results for the owned capability index.

The remaining Bash adapter supplies approval/native PTY and verifier observations.
Privileged native dispatch claims existing History authority before any effect;
module handlers continue through the shared isolated handler runtime.
"""

from __future__ import annotations

import copy
import hashlib
import json
import math
import re
import subprocess
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import quote

CAPABILITY_ID = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
SECRET_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,159}$")
TIERS = {"READ", "CHANGE", "DESTROY"}
RECOVERY = {"reversible", "best_effort", "compensating_action", "snapshot_required", "irreversible", "not_applicable"}
INPUT_TYPES = {"string", "integer", "number", "boolean", "enum", "object_id", "path", "secret_ref"}
CAPABILITY_VERSIONS = {1, 2, 3}
OUTPUT_TYPES = {"string", "integer", "number", "boolean", "enum", "object_id"}
COLLECTION_PAGE_BYTES = 64 * 1024
COLLECTION_RESULT_BYTES = 96 * 1024


class CapabilityError(ValueError):
    """A deterministic contract or invocation failure."""


def _json(value: Any) -> Any:
    return json.loads(json.dumps(value, sort_keys=True, separators=(",", ":")))


def _decode(raw: str) -> Any:
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result = {}
        for key, value in pairs:
            if key in result:
                raise CapabilityError("duplicate JSON field")
            result[key] = value
        return result

    def invalid_constant(_value: str) -> Any:
        raise CapabilityError("nonfinite JSON number")

    return json.loads(raw, object_pairs_hook=unique, parse_constant=invalid_constant)


def _cap_id(value: Any) -> str:
    if not isinstance(value, str) or not CAPABILITY_ID.fullmatch(value) or "." not in value:
        raise CapabilityError("capability id must be a dotted lowercase identifier")
    return value


@dataclass(frozen=True)
class SecretReference:
    reference: str
    namespace: str = "default"
    purpose: str = ""

    @classmethod
    def parse(cls, value: Any, *, namespace: str | None = None, purpose: str | None = None) -> SecretReference:
        if isinstance(value, dict):
            if set(value) - {"reference", "namespace", "purpose"} or "reference" not in value:
                raise CapabilityError("secret_ref has unknown or missing fields")
            reference = value["reference"]
            declared_namespace, declared_purpose = namespace, purpose
            namespace = value.get("namespace", namespace or "default")
            purpose = value.get("purpose", purpose or "")
            if declared_namespace is not None and namespace != declared_namespace:
                raise CapabilityError("secret_ref namespace does not match descriptor")
            if declared_purpose is not None and purpose != declared_purpose:
                raise CapabilityError("secret_ref purpose does not match descriptor")
        else:
            reference = value
            namespace = namespace or "default"
            purpose = purpose or ""
        if not isinstance(reference, str) or not SECRET_ID.fullmatch(reference):
            raise CapabilityError("secret_ref.reference is invalid")
        if not isinstance(namespace, str) or not re.fullmatch(r"[a-z][a-z0-9_.-]{0,63}", namespace):
            raise CapabilityError("secret_ref.namespace is invalid")
        if not isinstance(purpose, str) or len(purpose) > 160 or any(ord(c) < 32 for c in purpose):
            raise CapabilityError("secret_ref.purpose is invalid")
        return cls(reference, namespace, purpose)

    def as_dict(self) -> dict[str, str]:
        return {"reference": self.reference, "namespace": self.namespace, "purpose": self.purpose}


def _validate_path(value: Any, spec: dict[str, Any]) -> str:
    if not isinstance(value, str) or not value or len(value) > int(spec.get("maxLength", 4096)):
        raise CapabilityError("path is invalid")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or "\x00" in value:
        raise CapabilityError("path escapes its declared root")
    root = spec.get("root")
    if not isinstance(root, str) or not Path(root).is_absolute():
        raise CapabilityError("path scope is unresolved")
    try:
        base = Path(root).resolve(strict=True)
    except OSError as exc:
        raise CapabilityError("path scope is unavailable") from exc
    candidate = base / value
    for part in (base / Path(value)).parents:
        if part == base:
            break
        if part.is_symlink():
            raise CapabilityError("path traverses a symbolic link")
    if candidate.is_symlink():
        raise CapabilityError("path is a symbolic link")
    try:
        candidate.resolve(strict=False).relative_to(base)
    except ValueError as exc:
        raise CapabilityError("path escapes its declared root") from exc
    return value


def _validate_value(name: str, value: Any, spec: dict[str, Any]) -> Any:
    typ = spec.get("type")
    if typ not in INPUT_TYPES:
        raise CapabilityError(f"input {name} has unsupported type")
    if typ == "string":
        if (not isinstance(value, str) or
                len(value) < int(spec.get("minLength", 0)) or
                len(value) > int(spec.get("maxLength", 4096))):
            raise CapabilityError(f"input {name} must be a bounded string")
        validator = spec.get("validator")
        if validator == "systemd_unit" and not re.fullmatch(r"[A-Za-z0-9_.@:-]+", value):
            raise CapabilityError(f"input {name} is not a valid service name")
        if validator == "package_name" and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9+_.:@-]*", value):
            raise CapabilityError(f"input {name} is not a valid package name")
        if validator == "unix_mode" and not re.fullmatch(r"0[0-7]{3}", value):
            raise CapabilityError(f"input {name} is not a supported Unix mode")
        if "pattern" in spec and (not isinstance(spec["pattern"], str) or not re.fullmatch(spec["pattern"], value)):
            raise CapabilityError(f"input {name} does not match its pattern")
        return value
    if typ == "boolean":
        if type(value) is not bool:
            raise CapabilityError(f"input {name} must be boolean")
        return value
    if typ == "integer" and type(value) is not int:
        raise CapabilityError(f"input {name} must be integer")
    if typ == "number" and type(value) not in (int, float):
        raise CapabilityError(f"input {name} must be number")
    if typ in {"integer", "number"}:
        if not math.isfinite(value):
            raise CapabilityError(f"input {name} must be finite")
        if "minimum" in spec and value < spec["minimum"] or "maximum" in spec and value > spec["maximum"]:
            raise CapabilityError(f"input {name} is outside its range")
        return value
    if typ == "enum":
        allowed = spec.get("allowed") or spec.get("values") or spec.get("enum")
        if not isinstance(allowed, list) or not any(type(value) is type(choice) and value == choice for choice in allowed):
            raise CapabilityError(f"input {name} is not an allowed value")
        return value
    if typ == "object_id":
        if not isinstance(value, str) or not re.fullmatch(r"[a-z][a-z0-9_-]*:[A-Za-z0-9_./:%+@-]+", value):
            raise CapabilityError(f"input {name} is not an object identity")
        return value
    if typ == "path":
        return _validate_path(value, spec)
    if typ == "secret_ref":
        ref = SecretReference.parse(value, namespace=spec.get("namespace"), purpose=spec.get("purpose"))
        return ref.as_dict()
    raise CapabilityError(f"input {name} has unsupported type")


def validate_inputs(schema: dict[str, Any], inputs: Any) -> dict[str, Any]:
    if not isinstance(schema, dict) or set(schema) != {"properties", "required", "additionalProperties"} or schema["additionalProperties"] is not False:
        raise CapabilityError("inputs schema is invalid")
    props = schema.get("properties", {})
    required = schema.get("required", [])
    if not isinstance(props, dict) or not isinstance(required, list) or not all(isinstance(k, str) for k in required):
        raise CapabilityError("inputs schema has invalid properties or required fields")
    if set(required) - set(props) or any(not isinstance(spec, dict) for spec in props.values()):
        raise CapabilityError("inputs schema has invalid required field")
    if not isinstance(inputs, dict):
        raise CapabilityError("capability inputs must be an object")
    unknown = set(inputs) - set(props)
    if unknown:
        raise CapabilityError(f"unknown input {min(unknown)}")
    missing = set(required) - set(inputs)
    if missing:
        raise CapabilityError(f"missing required input {min(missing)}")
    return {key: _validate_value(key, inputs[key], props[key]) for key in sorted(inputs) if key in props}


def _validate_schema(schema: Any) -> None:
    if not isinstance(schema, dict) or set(schema) != {"properties", "required", "additionalProperties"} or schema["additionalProperties"] is not False:
        raise CapabilityError("inputs schema is invalid")
    props = schema.get("properties", {})
    required = schema.get("required", [])
    if not isinstance(props, dict) or not isinstance(required, list) or not all(isinstance(k, str) for k in required):
        raise CapabilityError("inputs schema has invalid properties or required fields")
    if set(required) - set(props):
        raise CapabilityError("inputs schema requires an undeclared field")
    for name, spec in props.items():
        if not isinstance(name, str) or not isinstance(spec, dict) or spec.get("type") not in INPUT_TYPES:
            raise CapabilityError(f"input schema field {name!r} is invalid")


def validate_output_schema(schema: Any, *, collection: Any = None) -> dict[str, Any]:
    """Bounded domain data; never an execution or authority envelope."""
    if (not isinstance(schema, dict) or
            set(schema) != {"schema_version", "properties", "required", "additionalProperties"} or
            type(schema["schema_version"]) is not int or schema["schema_version"] not in {1, 2} or
            schema["additionalProperties"] is not False):
        raise CapabilityError("outputs requires a closed supported schema")
    _validate_output_record(schema, depth=1, structured=schema["schema_version"] == 2)
    if collection is not None:
        _validate_collection_schema(collection, schema)
    return copy.deepcopy(schema)


def _validate_output_record(schema: dict[str, Any], *, depth: int, structured: bool) -> None:
    if depth > 4:
        raise CapabilityError("collection_limit_exceeded")
    props, required = schema.get("properties"), schema.get("required")
    if (not isinstance(props, dict) or len(props) > 32 or not isinstance(required, list) or
            any(type(name) is not str for name in required) or
            len(required) != len(set(required)) or set(required) - set(props)):
        raise CapabilityError("outputs has invalid properties or required fields")
    for name, spec in props.items():
        if (not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", name) or
                any(word in name for word in ("password", "token", "credential", "secret"))):
            raise CapabilityError("outputs has invalid or secret-bearing field")
        if not isinstance(spec, dict):
            raise CapabilityError("output field has unsupported metadata")
        typ = spec.get("type")
        if not isinstance(typ, str):
            raise CapabilityError("output field has unsupported type")
        if structured and typ == "object":
            if set(spec) != {"type", "properties", "required", "additionalProperties"} or spec["additionalProperties"] is not False:
                raise CapabilityError("output record must be closed")
            _validate_output_record(spec, depth=depth + 1, structured=True)
            continue
        if structured and typ == "scoped_reference":
            if set(spec) != {"type"} or depth + 1 > 4:
                raise CapabilityError("invalid scoped reference schema")
            continue
        if structured and typ == "array":
            if (depth != 1 or name != "rows" or
                    set(spec) != {"type", "items", "minItems", "maxItems"} or
                    type(spec["minItems"]) is not int or type(spec["maxItems"]) is not int or
                    not 0 <= spec["minItems"] <= spec["maxItems"] <= 128):
                raise CapabilityError("output array requires bounded collection rows")
            items = spec["items"]
            if (not isinstance(items, dict) or items.get("type") != "object" or
                    set(items) != {"type", "properties", "required", "additionalProperties"} or
                    items["additionalProperties"] is not False):
                raise CapabilityError("output rows require closed records")
            _validate_output_record(items, depth=3, structured=True)
            continue
        allowed = {"type", "enum", "minimum", "maximum", "minLength", "maxLength"}
        if structured:
            allowed.add("validator")
        if set(spec) - allowed:
            raise CapabilityError("output field has unsupported metadata")
        if typ not in OUTPUT_TYPES:
            raise CapabilityError("output field has unsupported type")
        if "validator" in spec and (not isinstance(spec["validator"], str) or spec["validator"] not in {
                "string": {"systemd_unit", "package_name", "unix_mode"},
                "object_id": {"object_id"},
        }.get(typ, set())):
            raise CapabilityError("output validator is invalid for its type")
        if typ == "enum":
            values = spec.get("enum")
            if (not isinstance(values, list) or not 1 <= len(values) <= 32 or
                    any(type(v) not in (str, int, bool) or (isinstance(v, str) and len(v) > 4096) for v in values) or
                    len({(type(v).__name__, str(v)) for v in values}) != len(values)):
                raise CapabilityError("output enum is invalid")
        elif "enum" in spec:
            raise CapabilityError("output enum requires enum type")
        for bound in ("minimum", "maximum"):
            if bound in spec and (typ not in {"integer", "number"} or type(spec[bound]) not in (int, float) or not _finite_output_number(spec[bound])):
                raise CapabilityError("output numeric bound is invalid")
        if "minimum" in spec and "maximum" in spec and spec["minimum"] > spec["maximum"]:
            raise CapabilityError("output numeric bounds are reversed")
        for bound in ("minLength", "maxLength"):
            if bound in spec and (typ not in {"string", "object_id"} or type(spec[bound]) is not int or not 0 <= spec[bound] <= 4096):
                raise CapabilityError("output length bound is invalid")
        if spec.get("minLength", 0) > spec.get("maxLength", 4096):
            raise CapabilityError("output length bounds are reversed")


def _validate_collection_schema(collection: Any, schema: dict[str, Any]) -> None:
    if (schema["schema_version"] != 2 or not isinstance(collection, dict) or
            set(collection) - {"resource_kind", "inventory", "columns", "inspect"} or
            not {"resource_kind", "inventory"} <= set(collection)):
        raise CapabilityError("invalid collection metadata")
    for key in ("resource_kind", "inventory"):
        value = collection[key]
        if not isinstance(value, str) or not 1 <= len(value) <= 80 or not CAPABILITY_ID.fullmatch(value):
            raise CapabilityError("invalid collection identifier")
    props = schema["properties"]
    fields = {"resource_kind", "inventory", "rows", "page", "freshness"}
    if set(props) != fields or set(schema["required"]) != fields:
        raise CapabilityError("collection requires its five domain fields")
    for key in ("resource_kind", "inventory"):
        if props[key] != {"type": "enum", "enum": [collection[key]]}:
            raise CapabilityError("collection identifiers must match singleton enums")
    rows = props["rows"]
    if rows.get("type") != "array" or rows["minItems"] != 0 or rows["maxItems"] != 128:
        raise CapabilityError("collection rows require bounds 0..128")
    row = rows["items"]
    if row["properties"].get("reference") != {"type": "scoped_reference"} or "reference" not in row["required"]:
        raise CapabilityError("collection row requires scoped reference")
    fixed_records = {
        "page": {
            "snapshot_revision": {"type": "string", "minLength": 1, "maxLength": 128},
            "returned_count": {"type": "integer", "minimum": 0, "maximum": 128},
            "total_count": {"type": "integer", "minimum": 0, "maximum": 1024},
            "has_more": {"type": "boolean"},
            "next_cursor": {"type": "string", "minLength": 1, "maxLength": 256},
        },
        "freshness": {
            "observed_at": {"type": "string", "maxLength": 32},
            "expires_at": {"type": "string", "maxLength": 32},
        },
    }
    for key, record_props in fixed_records.items():
        record = props[key]
        required = set(record_props) - ({"next_cursor"} if key == "page" else set())
        if (record.get("type") != "object" or record["properties"] != record_props or
                set(record["required"]) != required):
            raise CapabilityError("invalid collection page or freshness schema")
    scalar = {name for name, spec in row["properties"].items() if spec["type"] in OUTPUT_TYPES}
    if "columns" in collection:
        columns = collection["columns"]
        if not isinstance(columns, list) or not 1 <= len(columns) <= 32:
            raise CapabilityError("invalid collection columns")
        seen = set()
        for column in columns:
            if (not isinstance(column, dict) or set(column) != {"field", "label"} or
                    not isinstance(column["field"], str) or column["field"] not in scalar or
                    column["field"] in seen or not isinstance(column["label"], str) or
                    not 1 <= len(column["label"]) <= 80 or
                    any(ord(char) < 32 or 127 <= ord(char) < 160 for char in column["label"])):
                raise CapabilityError("invalid collection column")
            seen.add(column["field"])
    if "inspect" in collection:
        binding = collection["inspect"]
        if not isinstance(binding, dict) or set(binding) != {"capability_id", "inputs_from_row"}:
            raise CapabilityError("invalid collection inspect declaration")
        _cap_id(binding["capability_id"])
        mapping = binding["inputs_from_row"]
        if (not isinstance(mapping, dict) or len(mapping) > 32 or
                any(not isinstance(key, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", key) or
                    not isinstance(value, str) or value not in scalar for key, value in mapping.items())):
            raise CapabilityError("invalid collection inspect mapping")


def validate_outputs(schema: Any, value: Any, *, collection: Any = None, scope_id: str | None = None) -> dict[str, Any]:
    schema = validate_output_schema(schema, collection=collection)
    if schema["schema_version"] == 2:
        try:
            result = _validate_output_record_value(schema, value)
            _serialized_bound(result, COLLECTION_PAGE_BYTES)
            if collection is not None:
                _validate_collection_value(result, scope_id=scope_id)
            import sys
            sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ai"))
            from privacy import sanitize_selected_text
            def text_values(item):
                if isinstance(item, str):
                    yield item
                elif isinstance(item, dict):
                    for child in item.values():
                        yield from text_values(child)
                elif isinstance(item, list):
                    for child in item:
                        yield from text_values(child)
            # One projector load/audit per page; no JSON escaping can hide a
            # credential in a string. Managed material cannot contain NUL.
            text = "\0".join(text_values(result))
            if sanitize_selected_text(text) != text:
                raise CapabilityError("invalid_domain_output")
            return result
        except (ValueError, TypeError, OverflowError, RecursionError) as exc:
            reason = "collection_limit_exceeded" if str(exc) == "collection_limit_exceeded" else "invalid_domain_output"
            raise CapabilityError(reason) from exc
    inputs = {key: schema[key] for key in ("properties", "required", "additionalProperties")}
    try:
        result = validate_inputs(inputs, value)
    except OverflowError as exc:
        raise CapabilityError("output numeric value is outside supported bounds") from exc
    # object_id validation has no input-specific length bound.
    for name, item in result.items():
        if isinstance(item, str) and not schema["properties"][name].get("minLength", 0) <= len(item) <= schema["properties"][name].get("maxLength", 4096):
            raise CapabilityError("output string is outside its bounds")
    return result


def _serialized_bound(value: Any, limit: int) -> None:
    size = 0
    for part in json.JSONEncoder(ensure_ascii=False, allow_nan=False, separators=(",", ":")).iterencode(value):
        size += len(part.encode("utf-8", errors="strict"))
        if size > limit:
            raise CapabilityError("collection_limit_exceeded")


def _validate_output_record_value(schema: dict[str, Any], value: Any) -> dict[str, Any]:
    if (not isinstance(value, dict) or set(value) - set(schema["properties"]) or
            not set(schema["required"]) <= set(value)):
        raise CapabilityError("invalid output record")
    result = {}
    for name, spec in schema["properties"].items():
        if name not in value:
            continue
        item = value[name]
        if spec["type"] == "object":
            result[name] = _validate_output_record_value(spec, item)
        elif spec["type"] == "array":
            if not isinstance(item, list):
                raise CapabilityError("invalid output array")
            if not spec["minItems"] <= len(item) <= spec["maxItems"]:
                raise CapabilityError("collection_limit_exceeded")
            result[name] = [_validate_output_record_value(spec["items"], row) for row in item]
        elif spec["type"] == "scoped_reference":
            from operational_history import object_ref
            if not isinstance(item, dict) or set(item) != {"scope_id", "object_id"}:
                raise CapabilityError("invalid scoped reference")
            result[name] = object_ref(item["scope_id"], item["object_id"])
        else:
            if isinstance(item, str) and len(item) > spec.get("maxLength", 4096):
                raise CapabilityError("collection_limit_exceeded")
            if (spec["type"] in {"integer", "number"} and type(item) in (int, float) and
                    _finite_output_number(item) and "maximum" in spec and item > spec["maximum"]):
                raise CapabilityError("collection_limit_exceeded")
            result[name] = _validate_value(name, item, spec)
            if isinstance(item, str):
                if not spec.get("minLength", 0) <= len(item) <= spec.get("maxLength", 4096):
                    raise CapabilityError("collection_limit_exceeded")
                if any(ord(char) < 32 or 127 <= ord(char) < 160 for char in item):
                    raise CapabilityError("invalid output text")
    return result


def _validate_collection_value(value: dict[str, Any], *, scope_id: str | None) -> None:
    references = [(row["reference"]["scope_id"], row["reference"]["object_id"]) for row in value["rows"]]
    if len(references) != len(set(references)) or len({scope for scope, _ in references}) > 1:
        raise CapabilityError("invalid collection references")
    if scope_id is not None:
        from operational_history import object_ref
        object_ref(scope_id, "host:local")
        if any(scope != scope_id for scope, _ in references):
            raise CapabilityError("invalid collection scope")
    page = value["page"]
    if (page["returned_count"] != len(references) or page["total_count"] < len(references) or
            (page["has_more"] and (not references or page["total_count"] <= len(references))) or
            (page["total_count"] > 0 and not references) or
            ("next_cursor" in page) != page["has_more"]):
        raise CapabilityError("inconsistent collection page")
    if "next_cursor" in page and not re.fullmatch(r"[\x20-\x7e]{1,256}", page["next_cursor"]):
        raise CapabilityError("invalid collection cursor")
    if any(ord(char) < 32 or ord(char) == 127 for char in page["snapshot_revision"]):
        raise CapabilityError("invalid collection revision")
    times = []
    for key in ("observed_at", "expires_at"):
        text = value["freshness"][key]
        if not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z", text):
            raise CapabilityError("invalid collection timestamp")
        times.append(datetime.fromisoformat(text))
    if (times[1] - times[0]).total_seconds() != 30:
        raise CapabilityError("invalid collection lifetime")


def _finite_output_number(value: float) -> bool:
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def _version(value: Any) -> int:
    if type(value) is not int or value not in CAPABILITY_VERSIONS:
        raise CapabilityError("unsupported capability_version")
    return value


def _validate_composite_implementation(raw: Any, parent_inputs: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(raw, dict) or set(raw) != {"kind", "intended_outcome", "variants", "final_check"}:
        raise CapabilityError("composite implementation has invalid fields")
    if raw.get("kind") != "composition":
        raise CapabilityError("implementation.kind must be composition")
    intended = raw.get("intended_outcome")
    if not isinstance(intended, str) or not intended.strip() or len(intended) > 512:
        raise CapabilityError("composition intended_outcome is invalid")
    variants = raw.get("variants")
    if not isinstance(variants, list) or not 1 <= len(variants) <= 8:
        raise CapabilityError("composition variants must contain 1..8 entries")
    parent_props = parent_inputs.get("properties", {})
    seen: set[str] = set()

    def binding(value: Any) -> Any:
        if isinstance(value, dict) and set(value) == {"from_input"}:
            name = value.get("from_input")
            if not isinstance(name, str) or name not in parent_props:
                raise CapabilityError("composition references unknown parent input")
        return _json(value)

    def step(value: Any, *, final: bool = False) -> dict[str, Any]:
        allowed = {"capability_id", "provider", "inputs", "capability_version"} | ({"expect"} if final else set())
        if not isinstance(value, dict) or set(value) - allowed:
            raise CapabilityError("composition step has unknown fields")
        ident = _cap_id(value.get("capability_id"))
        inputs = value.get("inputs")
        if not isinstance(inputs, dict) or len(inputs) > 32:
            raise CapabilityError("composition step inputs are invalid")
        result = {"capability_id": ident, "inputs": {key: binding(item) for key, item in inputs.items()}}
        if "provider" in value:
            if not isinstance(value["provider"], str) or not CAPABILITY_ID.fullmatch(value["provider"]):
                raise CapabilityError("composition provider is invalid")
            result["provider"] = value["provider"]
        if "capability_version" in value:
            result["capability_version"] = _version(value["capability_version"])
        if final:
            expect = value.get("expect")
            if not isinstance(expect, dict) or not expect or len(expect) > 32:
                raise CapabilityError("composition final check expectation is invalid")
            result["expect"] = {key: binding(item) for key, item in expect.items()}
        return result

    normalized = []
    for variant in variants:
        if not isinstance(variant, dict) or set(variant) != {"requires", "steps"}:
            raise CapabilityError("composition variant has invalid fields")
        requires = variant.get("requires")
        if not isinstance(requires, dict) or set(requires) != {"platform_families"}:
            raise CapabilityError("composition variant requires platform_families")
        families = requires.get("platform_families")
        if (not isinstance(families, list) or not families or
                any(family not in {"debian", "arch"} for family in families) or
                len(families) != len(set(families))):
            raise CapabilityError("composition platform families are invalid")
        if seen & set(families):
            raise CapabilityError("composition platform variants overlap")
        seen.update(families)
        steps = variant.get("steps")
        if not isinstance(steps, list) or not 1 <= len(steps) <= 16:
            raise CapabilityError("composition variant requires 1..16 steps")
        normalized.append({"requires": {"platform_families": list(families)},
                           "steps": [step(item) for item in steps]})
    return {"kind": "composition", "intended_outcome": intended,
            "variants": normalized, "final_check": step(raw.get("final_check"), final=True)}


def _bind_composition(value: Any, parent_inputs: dict[str, Any]) -> Any:
    if isinstance(value, dict) and set(value) == {"from_input"}:
        return _json(parent_inputs[value["from_input"]])
    return _json(value)


@dataclass
class CapabilityDescriptor:
    id: str
    owner: str
    provider: str
    handler: str | None
    capability_version: int = 1
    description: str = ""
    inputs: dict[str, Any] = field(default_factory=lambda: {"properties": {}, "required": [], "additionalProperties": False})
    safety: dict[str, Any] = field(default_factory=lambda: {"tier": "READ"})
    privilege: str = "none"
    preconditions: list[Any] = field(default_factory=list)
    verification: dict[str, Any] = field(default_factory=dict)
    recovery: dict[str, Any] = field(default_factory=lambda: {"class": "best_effort"})
    affects: list[Any] = field(default_factory=list)
    source: str = "core"
    timeout_seconds: int | None = None
    active: bool = True
    unavailable_reason: str | None = None
    outputs: dict[str, Any] | None = None
    collection: dict[str, Any] | None = None
    implementation: dict[str, Any] | None = None

    @classmethod
    def from_dict(cls, raw: dict[str, Any], *, owner: str | None = None, provider: str | None = None) -> CapabilityDescriptor:
        if not isinstance(raw, dict) or raw.get("kind", "capability") != "capability":
            raise CapabilityError("descriptor kind must be capability")
        required = {"id", "capability_version", "description", "inputs", "safety", "privilege", "preconditions", "verification", "recovery", "affects"}
        missing = required - set(raw)
        if missing:
            raise CapabilityError(f"capability descriptor is incomplete: {min(missing)}")
        unknown = set(raw) - (required | {"kind", "owner", "provider", "source", "requires", "active", "unavailable_reason", "timeout_seconds", "outputs", "handler", "implementation", "collection"})
        if unknown:
            raise CapabilityError(f"capability descriptor has unknown field {min(unknown)}")
        ident = _cap_id(raw["id"])
        handler = raw.get("handler")
        implementation = raw.get("implementation")
        if (handler is None) == (implementation is None):
            raise CapabilityError("capability requires exactly one handler or implementation")
        if handler is not None and (not isinstance(handler, str) or not handler):
            raise CapabilityError("handler must be a declared adapter name")
        tier = raw["safety"].get("tier") if isinstance(raw["safety"], dict) else None
        if tier not in TIERS:
            raise CapabilityError("safety.tier must be READ, CHANGE or DESTROY")
        if raw["privilege"] not in {"none", "required"}:
            raise CapabilityError("privilege must be none or required")
        version = _version(raw["capability_version"])
        collection = raw.get("collection")
        if "collection" in raw and (version != 3 or not isinstance(collection, dict)):
            raise CapabilityError("collection requires capability_version 3")
        outputs = validate_output_schema(raw.get("outputs"), collection=collection) if version >= 2 else None
        if outputs is not None and outputs["schema_version"] != version - 1:
            raise CapabilityError("output schema version does not match capability contract")
        if version == 1 and "outputs" in raw:
            raise CapabilityError("outputs requires a typed capability contract")
        timeout = raw.get("timeout_seconds")
        if timeout is not None and (type(timeout) is not int or timeout <= 0):
            raise CapabilityError("timeout_seconds must be a positive integer")
        if not isinstance(raw["preconditions"], list) or not isinstance(raw["verification"], dict) or not isinstance(raw["affects"], list):
            raise CapabilityError("preconditions, verification and affects have invalid shape")
        recovery = raw["recovery"]
        if not isinstance(recovery, dict) or recovery.get("class") not in RECOVERY:
            raise CapabilityError("recovery.class is invalid")
        inputs = raw["inputs"]
        _validate_schema(inputs)
        normalized_implementation = _validate_composite_implementation(implementation, inputs) if implementation is not None else None
        if normalized_implementation is not None and raw["privilege"] != "none":
            raise CapabilityError("composite capability cannot declare direct privilege")
        return cls(
            id=ident,
            owner=owner or raw.get("owner", "core"),
            provider=provider or raw.get("provider", owner or "core"),
            handler=handler,
            capability_version=version,
            description=raw["description"],
            inputs=copy.deepcopy(inputs),
            safety=copy.deepcopy(raw["safety"]),
            privilege=raw["privilege"],
            preconditions=copy.deepcopy(raw["preconditions"]),
            verification=copy.deepcopy(raw["verification"]),
            recovery=copy.deepcopy(recovery),
            affects=copy.deepcopy(raw["affects"]),
            source=raw.get("source", "core"),
            timeout_seconds=timeout,
            active=raw.get("active", True),
            unavailable_reason=raw.get("unavailable_reason"),
            outputs=outputs,
            collection=copy.deepcopy(collection),
            implementation=normalized_implementation,
        )

    def inspect(self) -> dict[str, Any]:
        return {"id": self.id, "capability_version": self.capability_version, "owner": self.owner, "provider": self.provider, "source": self.source, "description": self.description, "available": bool(self.active and not self.unavailable_reason), "unavailable_reason": self.unavailable_reason, "inputs": _json(self.inputs), "safety": _json(self.safety), "privilege": self.privilege, "preconditions": _json(self.preconditions), "verification": _json(self.verification), "recovery": _json(self.recovery), "affects": _json(self.affects), **({"handler": self.handler} if self.handler is not None else {}), **({"implementation": _json(self.implementation)} if self.implementation is not None else {}), **({"timeout_seconds": self.timeout_seconds} if self.timeout_seconds is not None else {}), **({"outputs": copy.deepcopy(self.outputs)} if self.outputs is not None else {}), **({"collection": copy.deepcopy(self.collection)} if self.collection is not None else {})}


@dataclass(frozen=True)
class Resolution:
    capability_id: str
    status: str
    providers: tuple[str, ...] = ()
    selected_provider: str | None = None
    reason: str | None = None

    @property
    def available(self) -> bool:
        return self.status == "available"


class CapabilityRegistry:
    def __init__(self) -> None:
        self._records: dict[str, list[CapabilityDescriptor]] = {}

    def register(self, descriptor: CapabilityDescriptor | dict[str, Any], **kwargs: Any) -> CapabilityDescriptor:
        desc = descriptor if isinstance(descriptor, CapabilityDescriptor) else CapabilityDescriptor.from_dict(descriptor, **kwargs)
        current = self._records.setdefault(desc.id, [])
        if any(d.provider == desc.provider for d in current):
            raise CapabilityError(f"duplicate capability provider {desc.provider}")
        current.append(desc)
        return desc

    def resolve(self, capability_id: str, provider: str | None = None) -> Resolution:
        ident = _cap_id(capability_id)
        records = self._records.get(ident, [])
        active = [d for d in records if d.active and not d.unavailable_reason]
        if provider:
            selected = [d for d in active if d.provider == provider]
            if len(selected) == 1:
                return Resolution(ident, "available", tuple(sorted(d.provider for d in active)), provider)
            return Resolution(ident, "unavailable", tuple(sorted(d.provider for d in active)), reason="provider_unavailable")
        if len(active) == 1:
            return Resolution(ident, "available", (active[0].provider,), active[0].provider)
        if len(active) > 1:
            return Resolution(ident, "ambiguous", tuple(sorted(d.provider for d in active)), reason="multiple_active_providers")
        return Resolution(ident, "unavailable", tuple(sorted(d.provider for d in records)), reason=(records[0].unavailable_reason if records else "no_provider"))

    def _selected(self, ident: str, provider: str | None) -> CapabilityDescriptor:
        resolution = self.resolve(ident, provider)
        if not resolution.available:
            raise CapabilityError(f"capability {ident} is {resolution.status}: {resolution.reason or ','.join(resolution.providers)}")
        return next(d for d in self._records[ident] if d.provider == resolution.selected_provider and d.active)

    def list(self, *, include_unavailable: bool = False) -> list[dict[str, Any]]:
        output = []
        for ident in sorted(self._records):
            resolution = self.resolve(ident)
            if include_unavailable or resolution.available:
                output.append({"id": ident, "status": resolution.status, "providers": list(resolution.providers), "selected_provider": resolution.selected_provider, "reason": resolution.reason})
        return output

    def inspect(self, capability_id: str, provider: str | None = None) -> dict[str, Any]:
        ident = _cap_id(capability_id)
        resolution = self.resolve(ident, provider)
        records = self._records.get(ident, [])
        return {"resolution": {"status": resolution.status, "providers": list(resolution.providers), "selected_provider": resolution.selected_provider, "reason": resolution.reason}, "declarations": [dict(d.inspect(), **({"inspection_binding": self.inspection_binding(d)} if d.collection is not None else {})) for d in records]}

    def inspection_binding(self, descriptor: CapabilityDescriptor, *, provider: str | None = None) -> dict[str, Any]:
        """Evaluate declared READ metadata only; never probe or invoke a target."""
        if descriptor.collection is None or "inspect" not in descriptor.collection:
            return {"status": "unavailable", "reason": "not_declared"}
        if not descriptor.active or descriptor.unavailable_reason:
            return {"status": "unavailable", "reason": "collection_unavailable"}
        binding = descriptor.collection["inspect"]
        resolution = self.resolve(binding["capability_id"], provider)
        result = {"status": resolution.status, "reason": resolution.reason,
                  "providers": list(resolution.providers), "selected_provider": resolution.selected_provider}
        if not resolution.available:
            return result
        target = self._selected(binding["capability_id"], resolution.selected_provider)
        mapping = binding["inputs_from_row"]
        if (target.safety["tier"] != "READ" or set(mapping) - set(target.inputs["properties"]) or
                set(target.inputs["required"]) - set(mapping)):
            return {**result, "status": "unavailable", "reason": "incompatible_inspection_target"}
        row = descriptor.outputs["properties"]["rows"]["items"]["properties"]
        required = descriptor.outputs["properties"]["rows"]["items"]["required"]
        for input_name, field_name in mapping.items():
            spec = target.inputs["properties"][input_name]
            if (input_name in target.inputs["required"] and field_name not in required or
                    not _inspection_field_compatible(row[field_name], spec, descriptor.collection["resource_kind"])):
                return {**result, "status": "unavailable", "reason": "incompatible_inspection_target"}
        return {**result, "capability_version": target.capability_version}

    def prepare(self, capability_id: str, inputs: dict[str, Any] | None = None, *, provider: str | None = None, capability_version: int | None = None, platform_family: str | None = None) -> dict[str, Any]:
        """Resolve and freeze a proposal without approval or execution."""
        desc = self._selected(capability_id, provider)
        if capability_version is not None and _version(capability_version) != desc.capability_version:
            raise CapabilityError("capability_version does not match selected provider")
        validated = validate_inputs(desc.inputs, inputs or {})
        proposal = {
            "capability_id": desc.id,
            "capability_version": desc.capability_version,
            "owner": desc.owner,
            "provider": desc.provider,
            "source": desc.source,
            "description": desc.description,
            "descriptor": desc.inspect(),
            "inputs": _json(validated),
            "validated_inputs": _json(validated),
            "safety": _json(desc.safety),
            "privilege": desc.privilege,
            "preconditions": _json(desc.preconditions),
            "verification": _json(desc.verification),
            "recovery": _json(desc.recovery),
            "affected_objects": [_affected(item, validated) for item in desc.affects if _affected(item, validated)],
        }
        if desc.implementation is not None:
            if platform_family not in {"debian", "arch"}:
                raise CapabilityError("composite capability requires a supported platform family")
            matches = [variant for variant in desc.implementation["variants"]
                       if platform_family in variant["requires"]["platform_families"]]
            if len(matches) != 1:
                raise CapabilityError("composite capability has no unique platform variant")
            steps = []
            for step in matches[0]["steps"]:
                steps.append({**{key: value for key, value in step.items() if key != "inputs"},
                              "inputs": {name: _bind_composition(value, validated)
                                         for name, value in step["inputs"].items()}})
            final = desc.implementation["final_check"]
            final_check = {**{key: value for key, value in final.items() if key not in {"inputs", "expect"}},
                           "inputs": {name: _bind_composition(value, validated)
                                      for name, value in final["inputs"].items()},
                           "expect": {name: _bind_composition(value, validated)
                                      for name, value in final["expect"].items()}}
            plan = CapabilityPlan(desc.implementation["intended_outcome"], steps,
                                  objects=proposal["affected_objects"],
                                  final_check=final_check).resolve(self)
            resolved_plan = plan.inspect()
            tier_rank = {"READ": 0, "CHANGE": 1, "DESTROY": 2}
            child_tier = max(
                (step["safety"]["tier"] for step in resolved_plan["steps"]),
                key=lambda value: tier_rank[value],
            )
            if tier_rank[desc.safety["tier"]] != tier_rank[child_tier]:
                raise CapabilityError("composite capability safety tier must match the maximum child tier")
            privilege_records = list(resolved_plan["steps"])
            if resolved_plan.get("final_check"):
                privilege_records.append(resolved_plan["final_check"])
            proposal["affected_objects"] = list(resolved_plan["objects"])
            proposal["composition_summary"] = {
                "effective_tier": desc.safety["tier"],
                "child_tier_floor": child_tier,
                "privilege": "required" if any(
                    step["privilege"] == "required" for step in privilege_records
                ) else "none",
                "affected_objects": list(resolved_plan["objects"]),
            }
            proposal["composition_plan"] = resolved_plan
        proposal["digest"] = hashlib.sha256(json.dumps(proposal, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        return proposal


def _inspection_field_compatible(row: dict[str, Any], target: dict[str, Any], resource_kind: str) -> bool:
    if "selector" in target:
        from input_candidates import CandidateError, validate_selector
        try:
            selector = validate_selector(target["selector"], input_type=target["type"])
        except CandidateError:
            return False
        if selector["resource_kind"] != resource_kind:
            return False
    if target["type"] not in OUTPUT_TYPES:
        return False
    if row["type"] == "enum":
        try:
            for value in row["enum"]:
                _validate_value("inspection", value, target)
            return True
        except (CapabilityError, TypeError, OverflowError):
            return False
    if row["type"] != target["type"]:
        return False
    if "validator" in target and row.get("validator") != target["validator"]:
        return False
    if "pattern" in target:
        return False
    if row["type"] in {"string", "object_id"}:
        return (row.get("minLength", 0) >= target.get("minLength", 0) and
                row.get("maxLength", 4096) <= target.get("maxLength", 4096))
    if row["type"] in {"integer", "number"}:
        return all(bound not in target or bound in row and (
            row[bound] >= target[bound] if bound == "minimum" else row[bound] <= target[bound])
            for bound in ("minimum", "maximum"))
    return True


def _affected(template: Any, inputs: dict[str, Any]) -> str | None:
    if isinstance(template, str):
        return template.format(**inputs)
    if isinstance(template, dict):
        kind = template.get("object") or template.get("kind")
        value = template.get("id") if "id" in template else inputs.get(template.get("input"))
        if kind == "service" and value:
            return f"service:systemd:{value}"
        if kind == "package" and value:
            return f"package:{value}"
        if kind == "interface" and isinstance(value, str):
            if re.fullmatch(
                    r"interface:(?:[A-Za-z0-9_.+@-]|%[0-9A-F]{2})+", value):
                return value
            return None
        if kind in {"mount", "filesystem", "user", "group"} and isinstance(value, str):
            if (value.startswith(kind + ":") and
                    re.fullmatch(r"[a-z][a-z0-9_-]*:[A-Za-z0-9_./:%+@-]+", value)):
                return value
            return None
        if kind == "path" and isinstance(value, str):
            if value.startswith("path:") and re.fullmatch(
                    r"path:/[A-Za-z0-9_./:%+@-]+", value):
                return value
            if not value.startswith("/") and ".." not in value.split("/"):
                return "path:/" + quote(value, safe="/._-+%")
            return None
        if kind == "host":
            return "host:local"
    return None


@dataclass
class CapabilityPlan:
    intended_outcome: str
    steps: list[dict[str, Any]]
    plan_version: int = 1
    objects: list[str] = field(default_factory=list)
    final_check: dict[str, Any] | None = None
    digest: str | None = None

    def resolve(self, registry: CapabilityRegistry) -> CapabilityPlan:
        if self.plan_version != 1 or not isinstance(self.intended_outcome, str) or not self.intended_outcome.strip():
            raise CapabilityError("plan version or intended outcome is invalid")
        if not isinstance(self.steps, list) or not 1 <= len(self.steps) <= 16:
            raise CapabilityError("plan must have 1 to 16 ordered steps")
        if not isinstance(self.objects, list) or len(self.objects) > 16:
            raise CapabilityError("plan objects must be a bounded array")
        for object_id in self.objects:
            _validate_value("object", object_id, {"type": "object_id"})

        def resolve_step(step: dict[str, Any], *, check: bool = False) -> dict[str, Any]:
            allowed = {"capability_id", "provider", "inputs", "capability_version"} | ({"expect"} if check else set())
            if not isinstance(step, dict) or set(step) - allowed:
                raise CapabilityError("plan step has unknown fields")
            ident = _cap_id(step.get("capability_id"))
            desc = registry._selected(ident, step.get("provider"))
            if desc.implementation is not None:
                raise CapabilityError("nested composite capabilities are not supported")
            if "capability_version" in step and _version(step["capability_version"]) != desc.capability_version:
                raise CapabilityError("plan capability_version does not match selected provider")
            args = validate_inputs(desc.inputs, step.get("inputs", {}))
            result = {"capability_id": ident, "capability_version": desc.capability_version,
                      "provider": desc.provider, "inputs": args,
                      "safety": _json(desc.safety), "privilege": desc.privilege,
                      "recovery": _json(desc.recovery),
                      "affected_objects": [_affected(item, args) for item in desc.affects
                                           if _affected(item, args)],
                      "inspection": registry.inspect(ident, desc.provider)}
            if check:
                if desc.safety.get("tier") != "READ" or desc.outputs is None:
                    raise CapabilityError("final check must be a typed READ capability")
                expect = step.get("expect")
                if not isinstance(expect, dict) or not expect:
                    raise CapabilityError("final check requires expected typed output")
                unknown = set(expect) - set(desc.outputs["properties"])
                if unknown:
                    raise CapabilityError("final check expects unknown output field")
                subset_schema = {"properties": {key: desc.outputs["properties"][key] for key in expect},
                                 "required": list(expect), "additionalProperties": False}
                result["expect"] = validate_inputs(subset_schema, expect)
            return result

        self.steps = [resolve_step(step) for step in self.steps]
        self.final_check = resolve_step(self.final_check, check=True) if self.final_check is not None else None
        if not self.objects:
            self.objects = sorted({
                object_id
                for step in self.steps
                for object_id in step.get("affected_objects", [])
            })
        payload = {"plan_version": self.plan_version, "intended_outcome": self.intended_outcome,
                   "objects": self.objects, "steps": self.steps, "final_check": self.final_check}
        self.digest = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        return self

    def inspect(self) -> dict[str, Any]:
        return {"plan_version": self.plan_version, "intended_outcome": self.intended_outcome,
                "objects": _json(self.objects), "steps": _json(self.steps),
                "final_check": _json(self.final_check), "digest": self.digest}

def _handler_output_cli(schema_raw: str, collection_raw: str = "null", scope_id: str | None = None) -> int:
    """Validate one raw module-handler envelope and v2 output in one process.

    Exit 2 means provider/handler failure (matching the old handler-envelope
    validator). Exit 3 means the handler succeeded but its typed domain output
    is invalid (matching the existing capability output-validation boundary).
    """
    import sys

    schema = None
    try:
        schema = _decode(schema_raw)
        collection = _decode(collection_raw)
        validate_output_schema(schema, collection=collection)
        if schema.get("schema_version") == 2:
            # Bound the wire envelope before JSON parsing; leave domain limits
            # to the shared validator, including escaped UTF-8 representation.
            raw_bytes = sys.stdin.buffer.read(COLLECTION_RESULT_BYTES + 1)
            if len(raw_bytes) > COLLECTION_RESULT_BYTES:
                print("capability runtime: collection_limit_exceeded", file=sys.stderr)
                return 3
            raw = raw_bytes.decode("utf-8", errors="strict")
        else:
            raw = sys.stdin.read()
        envelope = _decode(raw)
    except (ValueError, TypeError, RecursionError):
        typed_collection = isinstance(schema, dict) and schema.get("schema_version") == 2
        print("capability runtime: invalid domain output" if typed_collection else
              "module handler: invalid JSON response", file=sys.stderr)
        return 3 if typed_collection else 2
    if not isinstance(envelope, dict):
        print("module handler: response must be a JSON object", file=sys.stderr)
        return 3 if schema["schema_version"] == 2 else 2
    status = envelope.get("status")
    if status == "error":
        error = envelope.get("error")
        if (set(envelope) != {"status", "error"} or not isinstance(error, dict) or
                not isinstance(error.get("code"), str) or not isinstance(error.get("message"), str)):
            print("module handler: invalid error response", file=sys.stderr)
            return 2
        if schema["schema_version"] == 2 and error["code"] in {
                "collection_limit_exceeded", "collection_expired", "collection_budget_exhausted", "invalid_collection_cursor"}:
            print("capability runtime: " + error["code"], file=sys.stderr)
        else:
            print("module handler: handler error" if schema["schema_version"] == 2 else
                  f"module handler: handler error {error['code']}: {error['message']}", file=sys.stderr)
        return 2
    if status != "ok" or set(envelope) != {"status", "result"}:
        print("module handler: invalid output envelope", file=sys.stderr)
        return 3 if schema["schema_version"] == 2 else 2
    try:
        result = validate_outputs(schema, envelope["result"], collection=collection, scope_id=scope_id)
    except (CapabilityError, TypeError, OverflowError) as exc:
        reason = "collection_limit_exceeded" if str(exc) == "collection_limit_exceeded" else "invalid domain output"
        print(f"capability runtime: {reason}", file=sys.stderr)
        return 3
    print(json.dumps(result, ensure_ascii=schema["schema_version"] == 1, sort_keys=True, separators=(",", ":")))
    return 0


def _registry_from_records(records):
    registry = CapabilityRegistry()
    for item in records:
        if not isinstance(item, dict):
            raise CapabilityError("capability record must be an object")
        # Loader rows may carry a normalized descriptor under descriptor;
        # inactive rows remain inspectable but cannot be prepared.
        descriptor = dict(item.get("descriptor", item))
        # Keep supplied targets available for composition and collection
        # inspection; the query itself still projects only its requested ID.
        if descriptor.get("kind", "capability") != "capability":
            continue
        # Loader metadata is authoritative for ownership and activation;
        # it must not be inferred from descriptor prose.
        for field_name in ("owner", "provider", "source"):
            if field_name in item:
                descriptor[field_name] = item[field_name]
        availability = item.get("availability")
        if availability is not None:
            descriptor["active"] = availability == "active"
            if availability != "active":
                descriptor["unavailable_reason"] = item.get("unavailable_reason") or availability
        if item.get("unavailable_reason"):
            descriptor["unavailable_reason"] = item["unavailable_reason"]
        registry.register(CapabilityDescriptor.from_dict(descriptor))
    return registry


def execution_fence(proposal: dict[str, Any], fresh: dict[str, Any],
                    approved_digest: str, *, inspection: bool = False) -> str:
    """Bind current execution to the exact proposal admitted by the dispatcher."""
    if not isinstance(proposal, dict) or not isinstance(fresh, dict):
        raise CapabilityError("invalid execution proposal")
    if not approved_digest or approved_digest != proposal.get("digest"):
        raise CapabilityError("execution proposal is not approved")
    if fresh.get("precondition_status") not in {"satisfied", "failed"}:
        raise CapabilityError("invalid execution precondition status")
    pending_content = {key: value for key, value in proposal.items() if key != "digest"}
    fresh_content = {key: value for key, value in fresh.items() if key != "digest"}
    if fresh["precondition_status"] == "failed":
        pending_content.pop("precondition_status", None)
        fresh_content.pop("precondition_status")
    unchanged = json.dumps(pending_content, sort_keys=True, allow_nan=False) == json.dumps(fresh_content, sort_keys=True, allow_nan=False)
    if fresh["precondition_status"] == "failed":
        if not unchanged:
            raise CapabilityError("execution proposal changed")
        return "precondition_failed"
    if proposal["digest"] != fresh.get("digest") or not unchanged:
        if inspection:
            return "inspection_unavailable"
        raise CapabilityError("execution proposal changed")
    return "ready"


def _result_base(proposal: dict[str, Any], operation_id: str,
                 approval: str, privilege: str) -> dict[str, Any]:
    return {
        "operation_id": operation_id,
        **{key: copy.deepcopy(proposal[key]) for key in (
            "capability_id", "capability_version", "provider", "owner", "privilege",
            "safety", "precondition_status", "affected_objects", "recovery")},
        "approval_status": approval, "privilege_status": privilege,
        "recorded_at": datetime.now(UTC).isoformat(),
    }


def nonexecution_result(proposal: dict[str, Any], reason: str, approval: str,
                        privilege: str, operation_id: str, detail: str = "") -> dict[str, Any]:
    privilege = privilege or ("not_requested" if proposal["privilege"] == "required" else "not_required")
    result = _result_base(proposal, operation_id, approval, privilege)
    result.update(execution_status="not_executed", verification_status="not_applicable",
                  outcome=reason, verification_evidence=(
                      [{"source": "capability.inspection", "reason": detail}] if detail else []))
    if reason == "precondition_failed":
        result["precondition_status"] = "failed"
    return result


def execution_result(proposal: dict[str, Any], execution: str, verification: str,
                     evidence: dict[str, Any], approval: str, operation_id: str,
                     output_status: str, domain_result: Any) -> dict[str, Any]:
    """Derive outcome from deterministic observations, never a provider's claim."""
    if execution not in {"succeeded", "failed"} or verification not in {
        "not_applicable", "passed", "failed", "unknown", "unavailable"
    } or output_status not in {"valid", "invalid", "not_applicable"}:
        raise CapabilityError("invalid execution observation")
    outcome = "failed"
    if execution == "succeeded":
        if output_status == "invalid" or (proposal["capability_version"] >= 2 and
                                          (output_status != "valid" or not isinstance(domain_result, dict))):
            outcome, verification, domain_result, output_status = "invalid_output", "unknown", None, "invalid"
        elif verification in {"failed", "unknown", "unavailable"}:
            outcome = "unverified_result" if proposal["safety"]["tier"] == "READ" else "unverified_change"
        elif proposal["safety"]["tier"] != "READ" and verification != "passed":
            outcome, verification = "unverified_change", "unavailable"
        else:
            outcome = "success"
    privilege = "authenticated" if proposal["privilege"] == "required" else "not_required"
    result = _result_base(proposal, operation_id, approval, privilege)
    result.update(execution_status=execution, verification_status=verification,
                  outcome=outcome, verification_evidence=[evidence] if evidence else [])
    if proposal["capability_version"] >= 2:
        result.update(output_status=output_status, result=domain_result)
    if proposal["capability_version"] == 3:
        try:
            _validate_result(result)
        except CapabilityError as exc:
            reason = "collection_limit_exceeded" if str(exc) == "collection_limit_exceeded" else "invalid_domain_output"
            result.update(output_status="invalid", result=None, verification_status="unknown", outcome="invalid_output",
                          verification_evidence=[{"source": "capability.output_validation", "reason": reason}])
    return result


def _privileged_commands(spec: Any, ident: str, family: str) -> list[list[str]]:
    """Accept only the reviewed native adapters; never run a model command."""
    if ident in {"system.service.restart","system.service.start","system.service.enable"}:
        operation={
            "system.service.restart":"restart",
            "system.service.start":"start",
            "system.service.enable":"enable",
        }[ident]
        if not isinstance(spec,list) or len(spec)!=6 or spec[:5]!=["sudo","-n","--","systemctl",operation]:
            raise CapabilityError("invalid privileged command")
        commands=[spec]
    elif ident=="system.storage.mount":
        if not isinstance(spec,list) or len(spec)!=2 or any(not isinstance(row,list) for row in spec):
            raise CapabilityError("invalid privileged command")
        mkdir_cmd,mount_cmd=spec
        if not (len(mkdir_cmd)==7 and
                mkdir_cmd[:6]==["sudo","-n","--","mkdir","-p","--"]):
            raise CapabilityError("invalid privileged command")
        target=mkdir_cmd[6]
        if not isinstance(target,str):
            raise CapabilityError("invalid privileged command")
        if not (target.startswith(("/mnt/","/media/","/srv/")) and
                ".." not in target.split("/") and
                all(ord(ch)>=32 for ch in target)):
            raise CapabilityError("invalid privileged command")
        if (len(mount_cmd)!=7 or mount_cmd[:5]!=["sudo","-n","--","mount","--"] or
                mount_cmd[6]!=target):
            raise CapabilityError("invalid privileged command")
        device=mount_cmd[5]
        if not isinstance(device,str) or not re.fullmatch(r"/dev/[A-Za-z0-9_./+@:-]+",device):
            raise CapabilityError("invalid privileged command")
        commands=spec
    elif ident=="system.storage.unmount":
        if not isinstance(spec,list) or len(spec)!=1 or not isinstance(spec[0],list):
            raise CapabilityError("invalid privileged command")
        argv=spec[0]
        if len(argv)!=6 or argv[:5]!=["sudo","-n","--","umount","--"]:
            raise CapabilityError("invalid privileged command")
        target=argv[5]
        if (not isinstance(target,str) or
                not target.startswith(("/mnt/","/media/","/srv/")) or
                ".." in target.split("/") or any(ord(ch)<32 for ch in target)):
            raise CapabilityError("invalid privileged command")
        commands=spec
    elif ident in {"system.permissions.owner.set","system.permissions.group.set","system.permissions.mode.set"}:
        if not isinstance(spec,list) or len(spec)!=1 or not isinstance(spec[0],list):
            raise CapabilityError("invalid privileged command")
        argv=spec[0]
        command={
            "system.permissions.owner.set":"chown",
            "system.permissions.group.set":"chgrp",
            "system.permissions.mode.set":"chmod",
        }[ident]
        if len(argv)!=7 or argv[:5]!=["sudo","-n","--",command,"--"]:
            raise CapabilityError("invalid privileged command")
        value,path=argv[5:7]
        if (not isinstance(path,str) or not path.startswith("/") or
                any(ord(ch)<32 for ch in path) or ".." in path.split("/")):
            raise CapabilityError("invalid privileged command")
        roots=("/home/","/srv/","/opt/","/mnt/","/media/","/usr/local/","/var/lib/","/var/www/")
        if not path.startswith(roots):
            raise CapabilityError("invalid privileged command")
        if ident in {"system.permissions.owner.set","system.permissions.group.set"}:
            if not isinstance(value,str) or not value.isdigit():
                raise CapabilityError("invalid privileged command")
        elif not isinstance(value,str) or re.fullmatch(r"0[0-7]{3}",value) is None:
            raise CapabilityError("invalid privileged command")
        commands=spec
    elif ident=="system.network.wifi.connect_known":
        if not isinstance(spec,list) or len(spec)!=1 or not isinstance(spec[0],list):
            raise CapabilityError("invalid privileged command")
        argv=spec[0]
        expected=["sudo","-n","--","nmcli","--wait","30","connection","up","uuid"]
        if len(argv)!=12 or argv[:9]!=expected or argv[10]!="ifname":
            raise CapabilityError("invalid privileged command")
        profile,interface=argv[9],argv[11]
        uuid_re=r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
        if re.fullmatch(uuid_re,profile) is None:
            raise CapabilityError("invalid privileged command")
        if re.fullmatch(r"[^\s/:]{1,32}",interface) is None:
            raise CapabilityError("invalid privileged command")
        commands=spec
    elif ident=="system.package.install":
        if (not isinstance(spec,list) or len(spec)!=7 or
                not isinstance(spec[-1],str) or
                not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9+_.:@-]*", spec[-1])):
            raise CapabilityError("invalid privileged command")
        expected_prefix={
            "debian":["sudo","-n","--","apt-get","install","-y"],
            "arch":["sudo","-n","--","pacman","-S","--noconfirm"],
        }.get(family)
        if expected_prefix is None or spec[:-1]!=expected_prefix:
            raise CapabilityError("invalid privileged command")
        commands=[spec]
    elif ident=="system.package.upgrade":
        expected={
            "debian":[["sudo","-n","--","apt-get","update"],
                      ["sudo","-n","--","apt-get","upgrade","-y"]],
            "arch":[["sudo","-n","--","pacman","-Syu","--noconfirm"]],
        }.get(family)
        if spec!=expected:
            raise CapabilityError("invalid privileged command")
        commands=spec
    elif ident=="system.package.cache.clean":
        expected={
            "debian":[["sudo","-n","--","apt-get","clean"]],
            "arch":[["sudo","-n","--","pacman","-Sc","--noconfirm"]],
        }.get(family)
        if spec!=expected:
            raise CapabilityError("invalid privileged command")
        commands=spec
    else:
        raise CapabilityError("invalid privileged command")
    if not commands or any(not isinstance(argv, list) or not argv or
                           any(not isinstance(arg, str) or not arg or "\0" in arg for arg in argv)
                           for argv in commands):
        raise CapabilityError("invalid privileged command")
    return commands


def execute_privileged(proposal: dict[str, Any], fresh: dict[str, Any], approved_digest: str,
                       history: Any, operation_id: str, approval: str, family: str) -> str:
    """Claim once in History before dispatching the exact approved native argv."""
    if execution_fence(proposal, fresh, approved_digest) != "ready" or fresh["privilege"] != "required":
        raise CapabilityError("privileged execution is unavailable")
    commands = _privileged_commands(fresh.get("privileged_argv"), fresh["capability_id"], family)
    history.running(operation_id, proposal=fresh, approval=approval, privilege="authenticated")
    command_timeout = 120 if fresh["capability_id"] in {
        "system.storage.mount", "system.storage.unmount",
        "system.permissions.owner.set", "system.permissions.group.set",
        "system.permissions.mode.set", "system.network.wifi.connect_known",
    } else 1800
    for argv in commands:
        try:
            result = subprocess.run(argv, check=False, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                    timeout=command_timeout)
        except (OSError, subprocess.TimeoutExpired):
            return "failed"
        if result.returncode:
            return "failed"
    return "succeeded"


def _cli() -> int:
    """Deterministic runtime bridge; never prompts or authenticates."""
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "execute-privileged":
        from operational_history import OperationalHistory
        try:
            if len(sys.argv) != 9:
                raise CapabilityError("invalid privileged execution arguments")
            proposal, fresh = map(_decode, sys.argv[2:4])
            digest, data_dir, operation_id, approval, family = sys.argv[4:]
            status = execute_privileged(
                proposal, fresh, digest, OperationalHistory(Path(data_dir)), operation_id, approval, family)
            print(status)
            return 0
        except (ValueError, OSError, KeyError, TypeError, RecursionError):
            print("capability runtime: privileged execution unavailable", file=sys.stderr)
            return 1

    if len(sys.argv) > 1 and sys.argv[1] in {"execution-fence", "execution-result", "nonexecution-result"}:
        try:
            lengths = {"execution-fence": 6, "execution-result": 9, "nonexecution-result": 8}
            if len(sys.argv) != lengths[sys.argv[1]]:
                raise CapabilityError("invalid coordination arguments")
            if sys.argv[1] == "execution-fence":
                if sys.argv[5] not in {"0", "1"}:
                    raise CapabilityError("invalid inspection context")
                proposal, fresh = map(_decode, sys.argv[2:4])
                print(execution_fence(proposal, fresh, sys.argv[4], inspection=sys.argv[5] == "1"))
            elif sys.argv[1] == "nonexecution-result":
                result = nonexecution_result(_decode(sys.argv[2]), *sys.argv[3:])
                print(json.dumps(result, sort_keys=True, separators=(",", ":")))
            else:
                proposal = _decode(sys.argv[2])
                execution, verification, evidence_raw, approval, operation_id, output_status = sys.argv[3:]
                try:
                    evidence = _decode(evidence_raw)
                except ValueError:
                    evidence = {"reason": "verification_failed"}
                result = execution_result(proposal, execution, verification, evidence, approval,
                                          operation_id, output_status, _decode(sys.stdin.read()))
                print(json.dumps(result, ensure_ascii=proposal["capability_version"] != 3, sort_keys=True, separators=(",", ":")))
            return 0
        except (ValueError, KeyError, TypeError, IndexError, RecursionError):
            print("capability runtime: invalid execution coordination", file=sys.stderr)
            return 1

    if len(sys.argv) in {5, 6, 7} and sys.argv[1] in {"inspection-prepare", "inspection-check"}:
        from collection_runtime import inspection_cli
        try:
            records = _decode(sys.stdin.read())
            print(json.dumps(inspection_cli(records, *sys.argv[1:]), ensure_ascii=False, separators=(",", ":")))
            return 0
        except (CapabilityError, OSError, ValueError, KeyError, TypeError):
            reason = str(sys.exc_info()[1])
            print(reason if reason in {"collection_expired", "invalid_collection_selection", "collection_limit_exceeded"} else "inspection_unavailable")
            return 2

    if 3 <= len(sys.argv) <= 5 and sys.argv[1] == "handler-output":
        return _handler_output_cli(*sys.argv[2:])

    shell_prepare = len(sys.argv) == 7 and sys.argv[1] == "prepare-shell"
    if not shell_prepare and len(sys.argv) != 1:
        print("capability runtime: unsupported arguments", file=sys.stderr)
        return 2

    op = None
    try:
        if shell_prepare:
            records = _decode(sys.stdin.read())
            ident, inputs_raw, provider, version_raw, family = sys.argv[2:]
            request = {
                "op": "prepare",
                "records": records,
                "id": ident,
                "inputs": _decode(inputs_raw),
                "provider": provider or None,
                "platform_family": family or None,
            }
            if version_raw:
                if version_raw not in {"1", "2", "3"}:
                    raise CapabilityError("unsupported capability_version")
                request["capability_version"] = int(version_raw)
        else:
            request = _decode(sys.stdin.read())
        op = request.get("op")
        if op == "output":
            envelope = _decode(request["envelope"])
            if not isinstance(envelope, dict) or set(envelope) != {"status", "result"} or envelope["status"] != "ok":
                raise CapabilityError("invalid output envelope")
            result = validate_outputs(request["outputs"], envelope["result"], collection=request.get("collection"), scope_id=request.get("scope_id"))
            print(json.dumps(result, ensure_ascii=request["outputs"]["schema_version"] == 1, sort_keys=True, separators=(",", ":")))
            return 0
        if op == "validate":
            descriptor = CapabilityDescriptor.from_dict(request["descriptor"])
            print(json.dumps(descriptor.inspect(), sort_keys=True, separators=(",", ":")))
            return 0
        registry = _registry_from_records(request.get("descriptors", request.get("records", [])))
        if op == "resolve":
            print(json.dumps(registry.inspect(request["id"], request.get("provider")), sort_keys=True, separators=(",", ":")))
            return 0
        if op == "plan":
            plan = CapabilityPlan(request.get("intended_outcome", ""), request.get("steps", []),
                                  objects=request.get("objects", []),
                                  final_check=request.get("final_check")).resolve(registry)
            print(json.dumps(plan.inspect(), sort_keys=True, separators=(",", ":")))
            return 0
        if op == "prepare":
            if "capability_version" in request:
                _version(request["capability_version"])
            print(json.dumps(registry.prepare(request["id"], request.get("inputs", {}), provider=request.get("provider"), capability_version=request.get("capability_version"), platform_family=request.get("platform_family")), sort_keys=True, separators=(",", ":")))
            return 0
        if op == "result":
            # Result inspection is deliberately a value projection; it never
            # executes or looks up a provider.
            value = request.get("result", {})
            _validate_result(value)
            print(json.dumps(value, sort_keys=True, separators=(",", ":")))
            return 0
        raise CapabilityError("unsupported operation")
    except (ValueError, KeyError, TypeError, RecursionError) as exc:
        reason = "collection_limit_exceeded" if str(exc) == "collection_limit_exceeded" else "invalid domain output"
        print(f"capability runtime: {reason}" if op == "output" else f"capability runtime: {exc}", file=sys.stderr)
        return 1


def _validate_result(value: Any) -> None:
    if not isinstance(value, dict):
        raise CapabilityError("result must be an object")
    required = {"operation_id", "capability_id", "execution_status", "verification_status", "outcome"}
    if not required <= set(value):
        raise CapabilityError("result is missing required status fields")
    if value["execution_status"] not in {"not_executed", "failed", "succeeded"}:
        raise CapabilityError("invalid execution_status")
    if value["verification_status"] not in {"not_applicable", "passed", "failed", "unknown", "unavailable"}:
        raise CapabilityError("invalid verification_status")
    safety = value.get("safety", {})
    if not isinstance(safety, dict):
        raise CapabilityError("invalid result safety")
    if value.get("output_status") not in {None, "valid", "invalid", "not_applicable"}:
        raise CapabilityError("invalid output_status")
    if value.get("output_status") == "invalid" and (value.get("result") is not None or value["outcome"] == "success"):
        raise CapabilityError("invalid domain output cannot be reported as success")
    if value.get("capability_version") in {2, 3} and value["outcome"] == "success" and (
            value.get("output_status") != "valid" or not isinstance(value.get("result"), dict)):
        raise CapabilityError("typed capability success requires valid domain output")
    if value.get("capability_version") == 3:
        _serialized_bound(value, COLLECTION_RESULT_BYTES)
    if value["outcome"] == "success":
        if value["execution_status"] != "succeeded" or value["verification_status"] in {"failed", "unknown", "unavailable"}:
            raise CapabilityError("unverified execution cannot be reported as success")
        if safety.get("tier") in {"CHANGE", "DESTROY"} and value["verification_status"] != "passed":
            raise CapabilityError("state change requires passed verification for success")
    def walk(item: Any, key: str = "") -> None:
        if isinstance(item, dict):
            for child_key, child in item.items():
                lowered = str(child_key).lower()
                if any(token in lowered for token in ("password", "token", "credential", "secret_value")):
                    raise CapabilityError("result contains secret-bearing field")
                walk(child, lowered)
        elif isinstance(item, list):
            for child in item:
                walk(child, key)
    walk(value)


if __name__ == "__main__":
    raise SystemExit(_cli())
