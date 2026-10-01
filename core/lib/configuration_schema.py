"""Small closed configuration declaration contract; no execution or storage."""

from __future__ import annotations

import copy
import math
import re
from pathlib import PurePosixPath
from typing import Any

ID = re.compile(r"[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+")
TYPES = {"string", "boolean", "integer", "number", "enum", "size", "path", "secret_ref"}
FIELDS = {"id", "type", "scope", "required", "default", "enum", "minimum", "maximum",
          "min_length", "max_length", "label", "help", "sensitivity", "behavior", "apply",
          "overrides", "secret_purpose", "path_roots", "path_kind"}


class ConfigurationError(ValueError):
    """Malformed, unavailable or conflicting configuration; never includes values."""


def closed(value: Any, allowed: set[str], required: set[str], name: str) -> dict:
    if type(value) is not dict or set(value) - allowed or required - set(value):
        raise ConfigurationError(f"invalid {name} fields")
    return value


def validate_value(field: dict, value: Any) -> Any:
    typ = field["type"]
    if typ == "boolean":
        valid = type(value) is bool
    elif typ in {"integer", "size"}:
        valid = type(value) is int
    elif typ == "number":
        valid = type(value) in {int, float} and abs(value) <= 1e308 and math.isfinite(value)
    elif typ in {"string", "enum"}:
        valid = type(value) is str and not any(ord(c) < 32 for c in value)
    elif typ == "secret_ref":
        closed(value, {"reference"}, {"reference"}, "secret reference")
        valid = type(value["reference"]) is str and bool(re.fullmatch(r"[a-z][a-z0-9_.:-]{0,159}", value["reference"]))
    elif typ == "path":
        closed(value, {"root", "relative"}, {"root", "relative"}, "path reference")
        relative = value["relative"]
        valid = (type(value["root"]) is str and value["root"] in field["path_roots"] and type(relative) is str and
                 bool(relative) and not any(ord(c) < 32 for c in relative) and
                 not PurePosixPath(relative).is_absolute() and ".." not in PurePosixPath(relative).parts)
    else:
        valid = False
    if not valid:
        raise ConfigurationError(f"invalid type for {field['id']}")
    if typ in {"integer", "number", "size"} and (value < field.get("minimum", 0 if typ == "size" else -math.inf) or
                                                value > field.get("maximum", math.inf)):
        raise ConfigurationError(f"outside range for {field['id']}")
    if typ in {"string", "enum"}:
        if not field.get("min_length", 0) <= len(value) <= field.get("max_length", 4096):
            raise ConfigurationError(f"invalid length for {field['id']}")
        if typ == "enum" and value not in field["enum"]:
            raise ConfigurationError(f"invalid choice for {field['id']}")
    return copy.deepcopy(value)


def validate_schema(descriptor: Any, owner: str) -> dict:
    closed(descriptor, {"schema_version", "fields"}, {"schema_version", "fields"}, "configuration schema")
    if type(descriptor["schema_version"]) is not int or descriptor["schema_version"] != 1:
        raise ConfigurationError("unsupported configuration schema version")
    fields = descriptor["fields"]
    if type(fields) is not list or not 1 <= len(fields) <= 64:
        raise ConfigurationError("schema requires bounded fields")
    result, seen = [], set()
    for raw in fields:
        closed(raw, FIELDS, {"id", "type", "scope"}, "configuration field")
        field = copy.deepcopy(raw)
        ident = field["id"]
        if (type(ident) is not str or not ID.fullmatch(ident) or ident in seen or
                (owner != "core" and not ident.startswith(owner + "."))):
            raise ConfigurationError("invalid, duplicate or foreign setting identity")
        seen.add(ident)
        if type(field["type"]) is not str or field["type"] not in TYPES or type(field["scope"]) is not str or field["scope"] not in {"installation", "module"}:
            raise ConfigurationError("unsupported setting type or scope")
        if owner != "core" and field["scope"] != "module":
            raise ConfigurationError("module declaration requires module scope")
        field.setdefault("required", False)
        field.setdefault("sensitivity", "public")
        field.setdefault("behavior", "stored")
        field.setdefault("overrides", [])
        field.setdefault("label", ident)
        field.setdefault("help", "")
        if (type(field["required"]) is not bool or type(field["sensitivity"]) is not str or field["sensitivity"] not in {"public", "sensitive", "secret"} or
                type(field["behavior"]) is not str or field["behavior"] not in {"stored", "managed"} or
                type(field["overrides"]) is not list or any(type(x) is not str for x in field["overrides"]) or
                len(set(field["overrides"])) != len(field["overrides"]) or any(x not in {"session", "environment"} for x in field["overrides"])):
            raise ConfigurationError("invalid field semantics")
        for key in ("label", "help"):
            if type(field[key]) is not str or len(field[key]) > 4096 or any(ord(c) < 32 and not (key == "help" and c == "\n") for c in field[key]):
                raise ConfigurationError("invalid documentation")
        for key in ("minimum", "maximum"):
            if key in field and (field["type"] not in {"integer", "number", "size"} or
                                 type(field[key]) not in {int, float} or abs(field[key]) > 1e308 or not math.isfinite(field[key])):
                raise ConfigurationError("invalid numeric constraint")
        if field.get("minimum", -math.inf) > field.get("maximum", math.inf):
            raise ConfigurationError("reversed numeric constraints")
        for key in ("min_length", "max_length"):
            if key in field and (field["type"] not in {"string", "enum"} or type(field[key]) is not int or not 0 <= field[key] <= 4096):
                raise ConfigurationError("invalid length constraint")
        if field.get("min_length", 0) > field.get("max_length", 4096):
            raise ConfigurationError("reversed length constraints")
        if field["type"] == "enum":
            if type(field.get("enum")) is not list or not 1 <= len(field["enum"]) <= 64 or any(type(x) is not str for x in field["enum"]) or len(set(field["enum"])) != len(field["enum"]):
                raise ConfigurationError("invalid enum declaration")
        elif "enum" in field:
            raise ConfigurationError("enum constraint on non-enum")
        if field["type"] == "secret_ref":
            if (field["sensitivity"] != "secret" or "default" in field or
                    type(field.get("secret_purpose")) is not str or not field["secret_purpose"]):
                raise ConfigurationError("secret requires reference, purpose and no default")
        elif "secret_purpose" in field or field["sensitivity"] == "secret":
            raise ConfigurationError("secret material requires secret_ref")
        if field["type"] == "path":
            roots = field.get("path_roots")
            if type(roots) is not list or not roots or any(type(x) is not str or not re.fullmatch(r"[a-z][a-z0-9_.-]*", x) for x in roots):
                raise ConfigurationError("path requires named roots")
            field.setdefault("path_kind", "any")
            if type(field["path_kind"]) is not str or field["path_kind"] not in {"any", "file", "directory"}:
                raise ConfigurationError("invalid path kind")
        elif set(field) & {"path_roots", "path_kind"}:
            raise ConfigurationError("path constraints on non-path")
        if field["behavior"] == "managed":
            apply = closed(field.get("apply"), {"capability_id", "verification_capability_id", "restart"}, {"capability_id", "restart"}, "apply contract")
            if (any(type(apply[x]) is not str or not ID.fullmatch(apply[x]) for x in apply if x != "restart") or
                    type(apply["restart"]) is not str or apply["restart"] not in {"none", "reload", "restart"}):
                raise ConfigurationError("invalid apply contract")
        elif "apply" in field:
            raise ConfigurationError("stored value cannot declare apply")
        if "default" in field:
            field["default"] = validate_value(field, field["default"])
        result.append(field)
    return {"schema_version": 1, "owner": owner, "fields": result}
