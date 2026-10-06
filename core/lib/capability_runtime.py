"""Pure resolution and input validation for the owned Wave E capability index.

The Bash dispatcher owns approval, privilege, execution and verification.
This module cannot invoke a handler or authorize an operation.
"""

from __future__ import annotations

import copy
import hashlib
import json
import math
import re
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import quote

CAPABILITY_ID = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
SECRET_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,159}$")
TIERS = {"READ", "CHANGE", "DESTROY"}
RECOVERY = {"reversible", "best_effort", "compensating_action", "snapshot_required", "irreversible", "not_applicable"}
INPUT_TYPES = {"string", "integer", "number", "boolean", "enum", "object_id", "path", "secret_ref"}
CAPABILITY_VERSIONS = {1, 2}
OUTPUT_TYPES = {"string", "integer", "number", "boolean", "enum", "object_id"}


class CapabilityError(ValueError):
    """A deterministic contract or invocation failure."""


def _json(value: Any) -> Any:
    return json.loads(json.dumps(value, sort_keys=True, separators=(",", ":")))


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


def validate_output_schema(schema: Any) -> dict[str, Any]:
    """Bounded domain data; never an execution or authority envelope."""
    if (not isinstance(schema, dict) or
            set(schema) != {"schema_version", "properties", "required", "additionalProperties"} or
            type(schema["schema_version"]) is not int or schema["schema_version"] != 1 or
            schema["additionalProperties"] is not False):
        raise CapabilityError("outputs requires a closed version-1 schema")
    props, required = schema["properties"], schema["required"]
    if (not isinstance(props, dict) or len(props) > 32 or not isinstance(required, list) or
            any(type(name) is not str for name in required) or
            len(required) != len(set(required)) or set(required) - set(props)):
        raise CapabilityError("outputs has invalid properties or required fields")
    for name, spec in props.items():
        if (not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", name) or
                any(word in name for word in ("password", "token", "credential", "secret"))):
            raise CapabilityError("outputs has invalid or secret-bearing field")
        if not isinstance(spec, dict) or set(spec) - {"type", "enum", "minimum", "maximum", "minLength", "maxLength"}:
            raise CapabilityError("output field has unsupported metadata")
        typ = spec.get("type")
        if typ not in OUTPUT_TYPES:
            raise CapabilityError("output field has unsupported type")
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
    return copy.deepcopy(schema)


def validate_outputs(schema: Any, value: Any) -> dict[str, Any]:
    schema = validate_output_schema(schema)
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
    implementation: dict[str, Any] | None = None

    @classmethod
    def from_dict(cls, raw: dict[str, Any], *, owner: str | None = None, provider: str | None = None) -> CapabilityDescriptor:
        if not isinstance(raw, dict) or raw.get("kind", "capability") != "capability":
            raise CapabilityError("descriptor kind must be capability")
        required = {"id", "capability_version", "description", "inputs", "safety", "privilege", "preconditions", "verification", "recovery", "affects"}
        missing = required - set(raw)
        if missing:
            raise CapabilityError(f"capability descriptor is incomplete: {min(missing)}")
        unknown = set(raw) - (required | {"kind", "owner", "provider", "source", "requires", "active", "unavailable_reason", "timeout_seconds", "outputs", "handler", "implementation"})
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
        outputs = validate_output_schema(raw.get("outputs")) if version == 2 else None
        if version == 1 and "outputs" in raw:
            raise CapabilityError("outputs requires capability_version 2")
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
            implementation=normalized_implementation,
        )

    def inspect(self) -> dict[str, Any]:
        return {"id": self.id, "capability_version": self.capability_version, "owner": self.owner, "provider": self.provider, "source": self.source, "description": self.description, "available": bool(self.active and not self.unavailable_reason), "unavailable_reason": self.unavailable_reason, "inputs": _json(self.inputs), "safety": _json(self.safety), "privilege": self.privilege, "preconditions": _json(self.preconditions), "verification": _json(self.verification), "recovery": _json(self.recovery), "affects": _json(self.affects), **({"handler": self.handler} if self.handler is not None else {}), **({"implementation": _json(self.implementation)} if self.implementation is not None else {}), **({"timeout_seconds": self.timeout_seconds} if self.timeout_seconds is not None else {}), **({"outputs": _json(self.outputs)} if self.outputs is not None else {})}


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
        return {"resolution": {"status": resolution.status, "providers": list(resolution.providers), "selected_provider": resolution.selected_provider, "reason": resolution.reason}, "declarations": [d.inspect() for d in records]}

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

def _handler_output_cli(schema_raw: str) -> int:
    """Validate one raw module-handler envelope and v2 output in one process.

    Exit 2 means provider/handler failure (matching the old handler-envelope
    validator). Exit 3 means the handler succeeded but its typed domain output
    is invalid (matching the existing capability output-validation boundary).
    """
    import sys

    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise CapabilityError("duplicate output field")
            result[key] = value
        return result

    try:
        schema = json.loads(schema_raw)
        raw = sys.stdin.read()
        envelope = json.loads(raw, object_pairs_hook=unique)
    except (json.JSONDecodeError, TypeError, CapabilityError):
        print("module handler: invalid JSON response", file=sys.stderr)
        return 2
    if not isinstance(envelope, dict):
        print("module handler: response must be a JSON object", file=sys.stderr)
        return 2
    status = envelope.get("status")
    if status == "error":
        error = envelope.get("error")
        if (set(envelope) != {"status", "error"} or not isinstance(error, dict) or
                not isinstance(error.get("code"), str) or not isinstance(error.get("message"), str)):
            print("module handler: invalid error response", file=sys.stderr)
            return 2
        print(f"module handler: handler error {error['code']}: {error['message']}", file=sys.stderr)
        return 2
    if status != "ok" or set(envelope) != {"status", "result"}:
        print("module handler: invalid output envelope", file=sys.stderr)
        return 2
    try:
        result = validate_outputs(schema, envelope["result"])
    except (CapabilityError, TypeError, OverflowError):
        print("capability runtime: invalid domain output", file=sys.stderr)
        return 3
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


def _cli() -> int:
    """JSON stdin bridge for shell-owned loaders (resolution only)."""
    import sys

    if len(sys.argv) == 3 and sys.argv[1] == "handler-output":
        return _handler_output_cli(sys.argv[2])

    shell_prepare = len(sys.argv) == 7 and sys.argv[1] == "prepare-shell"
    if not shell_prepare and len(sys.argv) != 1:
        print("capability runtime: unsupported arguments", file=sys.stderr)
        return 2

    op = None
    try:
        if shell_prepare:
            records = json.load(sys.stdin)
            ident, inputs_raw, provider, version_raw, family = sys.argv[2:]
            request = {
                "op": "prepare",
                "records": records,
                "id": ident,
                "inputs": json.loads(inputs_raw),
                "provider": provider or None,
                "platform_family": family or None,
            }
            if version_raw:
                if version_raw not in {"1", "2"}:
                    raise CapabilityError("unsupported capability_version")
                request["capability_version"] = int(version_raw)
        else:
            request = json.load(sys.stdin)
        op = request.get("op")
        if op == "output":
            def unique(pairs):
                result = {}
                for key, value in pairs:
                    if key in result:
                        raise CapabilityError("duplicate output field")
                    result[key] = value
                return result
            envelope = json.loads(request["envelope"], object_pairs_hook=unique)
            if not isinstance(envelope, dict) or set(envelope) != {"status", "result"} or envelope["status"] != "ok":
                raise CapabilityError("invalid output envelope")
            result = validate_outputs(request["outputs"], envelope["result"])
            print(json.dumps(result, sort_keys=True, separators=(",", ":")))
            return 0
        if op == "validate":
            descriptor = CapabilityDescriptor.from_dict(request["descriptor"])
            print(json.dumps(descriptor.inspect(), sort_keys=True, separators=(",", ":")))
            return 0
        registry = CapabilityRegistry()
        records = request.get("descriptors", request.get("records", []))
        for item in records:
            if not isinstance(item, dict):
                raise CapabilityError("capability record must be an object")
            # Loader rows may carry a normalized descriptor under descriptor;
            # inactive rows remain inspectable but cannot be prepared.
            descriptor = dict(item.get("descriptor", item))
            # Shell preparation already supplies the selected capability plus
            # its bounded dependency closure. Keep those child/final-check
            # descriptors available for composite resolution. Resolve-only
            # inspection may still filter to one identity.
            if op == "resolve" and request.get("id") and descriptor.get("id") != request["id"]:
                continue
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
    except (CapabilityError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print("capability runtime: invalid domain output" if op == "output" else f"capability runtime: {exc}", file=sys.stderr)
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
    if value.get("capability_version") == 2 and value["outcome"] == "success" and (
            value.get("output_status") != "valid" or not isinstance(value.get("result"), dict)):
        raise CapabilityError("capability version 2 success requires valid domain output")
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
