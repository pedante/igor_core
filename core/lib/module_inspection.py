"""Read-only, data-only module inspection projection.

The loader supplies runtime-owned registration and system snapshots through
stdin. Static package inspection validates declarations without importing or
executing module code. This is an inspection boundary, not a sandbox.
"""

from __future__ import annotations

import argparse
import json
import re
import stat
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from module_contract import ValidationError, probe_api, validate_module

NAME_RE = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")


class InspectionError(ValueError):
    """Unsafe or malformed input prevents a reliable inspection."""


def _json_copy(value: Any) -> Any:
    try:
        return json.loads(json.dumps(value, sort_keys=True, allow_nan=False))
    except (TypeError, ValueError) as exc:
        raise InspectionError("runtime snapshot must contain JSON data") from exc


def _strict_json_loads(raw: str) -> Any:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result = {}
        for key, value in pairs:
            if key in result:
                raise InspectionError(f"snapshot contains duplicate JSON key {key}")
            result[key] = value
        return result

    def reject_constant(value: str) -> None:
        raise InspectionError(f"snapshot contains non-finite number {value}")

    return json.loads(raw, object_pairs_hook=reject_duplicates, parse_constant=reject_constant)


def _safe_package(root: Path, name: str) -> tuple[Path, Path]:
    if not isinstance(name, str) or not NAME_RE.fullmatch(name) or name in {".", ".."}:
        raise InspectionError("module name must be a canonical lowercase identifier")
    root = root.absolute()
    modules = root / "modules"
    package = modules / name
    if modules.is_symlink() or package.is_symlink():
        raise InspectionError("module path contains a symlink")
    try:
        resolved_root = root.resolve(strict=True)
        resolved_package = package.resolve(strict=True)
        resolved_package.relative_to((resolved_root / "modules").resolve(strict=True))
    except (OSError, ValueError) as exc:
        raise InspectionError("module directory is missing or escapes the installation root") from exc
    if not resolved_package.is_dir():
        raise InspectionError("module directory is missing")
    # Reject symlinks anywhere in the package, including unreferenced files.
    for path in resolved_package.rglob("*"):
        try:
            if path.is_symlink():
                raise InspectionError("module package contains a symlink")
            if not (path.is_dir() or path.is_file()):
                raise InspectionError("module package contains a non-regular file")
        except OSError as exc:
            raise InspectionError("cannot safely inspect module package") from exc
    return resolved_root, resolved_package


def _policy(root: Path) -> dict[str, str]:
    config_dir = root / "config"
    if config_dir.is_symlink():
        raise InspectionError("module policy directory must not be a symlink")
    path = config_dir / "modules.conf"
    if path.is_symlink():
        raise InspectionError("module policy file must not be a symlink")
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return {}
    except OSError as exc:
        raise InspectionError("cannot inspect module policy file") from exc
    if not stat.S_ISREG(mode):
        raise InspectionError("module policy path must be a regular file")
    states: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        raise InspectionError("cannot read module policy file") from exc
    for number, raw in enumerate(lines, 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        match = re.fullmatch(r"([a-z][a-z0-9]*(?:[._-][a-z0-9]+)*)\s*=\s*(enabled|disabled)", line)
        if not match:
            raise InspectionError(f"module policy line {number} is malformed")
        name, state = match.groups()
        if name in states:
            raise InspectionError(f"module policy has duplicate entry for {name}")
        states[name] = state
    return states


def _v1_metadata(package: Path) -> dict[str, Any]:
    """Best-effort legacy metadata; section-blind by design, never verified."""
    values: dict[str, str] = {}
    try:
        lines = (package / "module.conf").read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        raise InspectionError("cannot read module.conf") from exc
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith(("#", ";")) or "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        values.setdefault(key, value)
    def legacy_items(field: str) -> list[str] | None:
        if field not in values:
            return None
        raw = values[field]
        result = []
        groups = raw.split(",")
        for group in groups:
            # Legacy optional module values can include a label after a colon;
            # the label may contain spaces and is not a dependency token.
            tokens = [group.split(":", 1)[0].strip()] if ":" in group else group.split()
            for item in tokens:
                if not item:
                    continue
                valid = (re.fullmatch(r"[A-Za-z0-9_.+-]+", item) if field == "required_bins"
                         else NAME_RE.fullmatch(item))
                if not valid:
                    return None
                result.append(item)
        return sorted(set(result))

    legacy_fields = {field: legacy_items(field) for field in (
        "required_modules", "optional_modules", "required_capabilities", "optional_capabilities", "required_bins")}
    unknown = [field for field, result in legacy_fields.items() if result is None]
    return {"display_name": values.get("display_name") or values.get("name") or package.name,
            "declared_name": values.get("name"), "version": values.get("version"),
            "validation": "best_effort_unverified", "legacy_dependencies": legacy_fields,
            "dependency_metadata_unknown_fields": unknown,
            "depends_on_ordering_only": legacy_items("depends_on")}


def _module_data(root: Path, name: str) -> tuple[dict[str, Any], list[dict[str, Any]], dict[str, Any], dict[str, str]]:
    resolved_root, package = _safe_package(root, name)
    try:
        api = probe_api(package)
    except ValidationError as exc:
        raise InspectionError(str(exc)) from exc
    policy = _policy(resolved_root)
    if api == "2":
        try:
            validated = validate_module(package)
        except ValidationError as exc:
            raise InspectionError(f"module v2 validation failed: {exc}") from exc
        manifest = validated["manifest"]
        policy_state = policy.get(name)
        if policy_state is None:
            if name == "system":
                policy_state = "migration_pending_unknown"
            else:
                policy_state = "disabled_by_default"
        module = {"id": name, "api": 2, "display_name": manifest["display_name"],
                  "package_version": manifest["version"], "package_path": str(package),
                  "manifest": manifest, "validation": "verified_by_module_api_v2_validator"}
        contributions = validated["contributions"]
        deps = manifest["requirements"]
        v1 = False
    elif api == "1":
        meta = _v1_metadata(package)
        module = {"id": name, "api": 1, "display_name": meta["display_name"],
                  "package_version": meta["version"], "package_path": str(package),
                  "manifest": meta, "validation": meta["validation"]}
        contributions = []
        deps = {**meta["legacy_dependencies"],
                "dependency_metadata_unknown_fields": meta["dependency_metadata_unknown_fields"],
                "depends_on_ordering_only": meta["depends_on_ordering_only"]}
        policy_state = policy.get(name, "enabled_compatibility_default")
        v1 = True
    else:
        raise InspectionError(f"unsupported or malformed module API: {api}")
    return module, contributions, deps, {"policy_state": policy_state, "v1": v1, "root": str(resolved_root)}


def _runtime_for(runtime: Mapping[str, Any] | None, name: str) -> dict[str, Any]:
    if runtime is None:
        return {}
    copied = _json_copy(runtime)
    if not isinstance(copied, dict):
        raise InspectionError("runtime snapshot must be an object")
    states = copied.get("module_states", {})
    if not isinstance(states, dict):
        raise InspectionError("runtime.module_states must be an object")
    selected = states.get(name, {})
    if not isinstance(selected, dict):
        raise InspectionError("runtime module state must be an object")
    return copied


def _runtime_contribution(runtime: Mapping[str, Any], item: Mapping[str, Any], name: str) -> dict[str, Any] | None:
    rows = runtime.get("contributions", [])
    if not isinstance(rows, list):
        raise InspectionError("runtime.contributions must be an array")
    for row in rows:
        if not isinstance(row, dict):
            raise InspectionError("runtime contribution rows must be objects")
        if row.get("owner") == name and row.get("kind") == item.get("kind") and row.get("id") == item.get("id"):
            return row
        key = row.get("index_key")
        if row.get("owner") == name and key in {f"{item.get('kind')}:{item.get('id')}", f"{item.get('kind')}:{item.get('id')}@{name}"}:
            return row
    return None


def _row_identity(row: Mapping[str, Any]) -> tuple[str, str] | None:
    kind, ident = row.get("kind"), row.get("id")
    if isinstance(kind, str) and isinstance(ident, str):
        return kind, ident
    key = row.get("index_key")
    if isinstance(key, str) and ":" in key:
        kind, ident = key.split(":", 1)
        if "@" in ident:
            ident = ident.split("@", 1)[0]
        return kind, ident
    return None


def _owned_rows(value: Any, owner: str) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        value = list(value.values())
    if not isinstance(value, list):
        return []
    return [row for row in value if isinstance(row, dict) and
            (row.get("owner") == owner or row.get("schema_owner") == owner)]


_SECRET_PROPERTY_RE = re.compile(r"secret|password|credential|private.?key|api.?key|token", re.IGNORECASE)
_SAFE_PROVENANCE_FIELDS = {"id", "owner", "schema_owner", "source", "source_id", "provenance",
                           "availability", "recorded_at", "observed_at", "collected_at", "updated_at",
                           "object_id", "property", "state_class", "sensitivity", "freshness", "confidence"}


def _safe_inspection_row(row: dict[str, Any]) -> dict[str, Any]:
    """Mask fact values whose metadata identifies them as secret or sensitive."""
    result = dict(row)
    prop = result.get("property")
    sensitivity = result.get("sensitivity")
    sensitive = (isinstance(sensitivity, str) and sensitivity.lower() in {"secret", "sensitive"})
    sensitive = sensitive or bool(result.get("secret"))
    sensitive = sensitive or (isinstance(prop, str) and bool(_SECRET_PROPERTY_RE.search(prop)))
    if sensitive:
        for key in tuple(result):
            if key not in _SAFE_PROVENANCE_FIELDS and key not in {"secret", "redacted"}:
                result[key] = "[redacted]"
        result["redacted"] = True
        return result
    for key, value in tuple(result.items()):
        if isinstance(key, str) and _SECRET_PROPERTY_RE.search(key):
            result[key] = "[redacted]"
        elif isinstance(value, dict):
            result[key] = _safe_inspection_row(value)
        elif isinstance(value, list):
            result[key] = [_safe_inspection_row(item) if isinstance(item, dict) else item for item in value]
    return result


def _contribution_views(contributions: list[dict[str, Any]], module: dict[str, Any], lifecycle: dict[str, Any],
                        runtime: Mapping[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    declarations: list[dict[str, Any]] = []
    capabilities: list[dict[str, Any]] = []
    knowledge: list[dict[str, Any]] = []
    matched_rows: set[int] = set()
    for item in contributions:
        row = _runtime_contribution(runtime, item, module["id"])
        if row:
            matched_rows.add(id(row))
            availability = row.get("availability", "unknown")
            reason = row.get("unavailable_reason")
            runtime_descriptor = row.get("descriptor")
            descriptor = {**item, **runtime_descriptor} if isinstance(runtime_descriptor, dict) else item
        elif lifecycle["enabled"] is False:
            availability, reason = "owner_disabled", "module policy disables this owner"
            descriptor = item
        else:
            availability, reason = "not_evaluated", "runtime eligibility was not supplied"
            descriptor = item
        view = {"id": item["id"], "kind": item["kind"], "owner": module["id"],
                "source": row.get("source", item.get("source")) if row else item.get("source"),
                "path": item.get("path"), "availability": availability, "reason": reason,
                "descriptor": descriptor}
        declarations.append(view)
        if item["kind"] == "capability":
            capabilities.append(view)
        elif item["kind"] == "knowledge":
            knowledge.append({"id": item["id"], "owner": module["id"], "source": item.get("source"),
                              "package_version": module.get("package_version"), "path": item.get("path"),
                              "availability": availability, "reason": reason})
    rows = runtime.get("contributions", [])
    if isinstance(rows, list):
        for row in rows:
            if not isinstance(row, dict) or row.get("owner") != module["id"] or id(row) in matched_rows:
                continue
            identity = _row_identity(row)
            if identity is None:
                continue
            kind, ident = identity
            descriptor = row.get("descriptor")
            descriptor = descriptor if isinstance(descriptor, dict) else {}
            availability = row.get("availability", "unknown")
            reason = row.get("unavailable_reason")
            view = {"id": ident, "kind": kind, "owner": module["id"],
                    "source": row.get("source"), "path": descriptor.get("path"),
                    "availability": availability, "reason": reason, "descriptor": descriptor}
            declarations.append(view)
            if kind == "capability":
                capabilities.append(view)
            elif kind == "knowledge":
                knowledge.append({"id": ident, "owner": module["id"], "source": row.get("source"),
                                  "package_version": module.get("package_version"),
                                  "path": descriptor.get("path"), "availability": availability,
                                  "reason": reason})
    return declarations, capabilities, knowledge


def _detach_plan(root: Path, module: dict[str, Any], deps: dict[str, Any], contributions: list[dict[str, Any]],
                 runtime: Mapping[str, Any], declarations: list[dict[str, Any]]) -> dict[str, Any]:
    dependents = []
    unresolved_packages = []
    modules_dir = root / "modules"
    if modules_dir.is_dir() and not modules_dir.is_symlink():
        for path in sorted(modules_dir.iterdir()):
            if path.name == module["id"]:
                continue
            if path.is_symlink():
                unresolved_packages.append(path.name)
                continue
            if not path.is_dir():
                continue
            try:
                other, other_contributions, other_deps, _ = _module_data(root, path.name)
            except InspectionError:
                unresolved_packages.append(path.name)
                continue
            if module["id"] in (other_deps.get("required_modules") or []):
                dependents.append({"module": other["id"], "requirement": "required_module",
                                   "impact": "declared_requirement_provider_may_be_affected"})
            required_caps = set(other_deps.get("required_capabilities") or [])
            provided_ids = {item["id"] for item in contributions if item["kind"] == "capability"}
            for cap in sorted(required_caps & provided_ids):
                dependents.append({"module": other["id"], "requirement": "required_capability", "capability": cap,
                                   "impact": "declared_requirement_provider_may_be_affected"})
            for contribution in other_contributions:
                requirements = contribution.get("requires", {})
                if module["id"] in (requirements.get("modules") or []):
                    dependents.append({"module": other["id"],
                                       "contribution": f"{contribution['kind']}:{contribution['id']}",
                                       "requirement": "contribution_module",
                                       "impact": "declared_requirement_provider_may_be_affected"})
                for capability in sorted(set(requirements.get("capabilities") or []) & provided_ids):
                    dependents.append({"module": other["id"],
                                       "contribution": f"{contribution['kind']}:{contribution['id']}",
                                       "requirement": "contribution_capability", "capability": capability,
                                       "impact": "declared_requirement_provider_may_be_affected"})
    own_reqs = []
    for item in contributions:
        requires = item.get("requires", {})
        if requires:
            own_reqs.append({"contribution": f"{item['kind']}:{item['id']}", "requires": requires})
    model = runtime.get("model", {}) if isinstance(runtime.get("model", {}), dict) else {}
    owned_facts = [_safe_inspection_row(row) for row in _owned_rows(model.get("facts", []), module["id"])]
    owned_responsibilities = [_safe_inspection_row(row) for row in _owned_rows(model.get("responsibilities", []), module["id"])]
    return {"ready": False, "completeness": "incomplete",
            "declared_dependents": dependents,
            "declared_contribution_requirements": own_reqs,
            "contributions": [{"key": f"{row['kind']}:{row['id']}", "availability": row["availability"]}
                              for row in declarations],
            "facts": owned_facts, "responsibilities": owned_responsibilities,
            "unresolved_packages": unresolved_packages,
            "retained": ["configuration", "secret_references", "operational_history", "investigations",
                         "local_learning", "external_resources"],
            "unknown": ["resource_bindings", "session_inventory", "secret_inventory", "binding_ownership",
                        "application_resource_ownership", "background_worker_inventory"]}


def inspect_module(root: str | Path, name: str, runtime: Mapping[str, Any] | None = None,
                   action: str = "inspect") -> dict[str, Any]:
    if action not in {"inspect", "detach-plan"}:
        raise InspectionError("action must be inspect or detach-plan")
    if not isinstance(root, (str, Path)):
        raise InspectionError("root must be a filesystem path")
    root_path = Path(root)
    module, contributions, deps, static = _module_data(root_path, name)
    runtime_data = _runtime_for(runtime, name)
    runtime_state = runtime_data.get("module_states", {}).get(name, {}) if runtime_data else {}
    if not isinstance(runtime_state, dict):
        raise InspectionError("runtime module state must be an object")
    enabled: bool | None = None
    policy = static["policy_state"]
    if policy in {"enabled", "enabled_compatibility_default"}:
        enabled = True
    elif policy in {"disabled", "disabled_by_default"}:
        enabled = False
    lifecycle = {"policy_state": policy, "enabled": enabled,
                 "runtime_status": runtime_state.get("status", "not_evaluated"),
                 "runtime_reason": runtime_state.get("reason"),
                 "loaded": runtime_state.get("loaded"),
                 "runtime_enabled": runtime_state.get("enabled"),
                 "evidence": "loader_snapshot" if runtime_state else "static_policy_only"}
    declarations, capabilities, knowledge = _contribution_views(contributions, module, lifecycle, runtime_data)
    model = runtime_data.get("model", {}) if isinstance(runtime_data.get("model"), dict) else {}
    configuration = runtime_data.get("configuration", [])
    if not isinstance(configuration, list):
        raise InspectionError("runtime.configuration must be an array")
    owned_configuration = _owned_rows(configuration, name)
    owned_facts = [_safe_inspection_row(row) for row in _owned_rows(model.get("facts", []), name)]
    owned_responsibilities = [_safe_inspection_row(row) for row in _owned_rows(model.get("responsibilities", []), name)]
    owned_observers = _owned_rows(model.get("observers", []), name)
    owned_health = _owned_rows(model.get("health", []), name)
    model_has_owned_rows = any((
        _owned_rows(model.get("facts", []), name),
        _owned_rows(model.get("responsibilities", []), name),
        _owned_rows(model.get("observers", []), name),
        _owned_rows(model.get("health", []), name),
    ))
    model_availability = "available" if model_has_owned_rows else "not_evaluated"
    config_supplied = isinstance(runtime_data.get("configuration"), list)
    desired_rows = [row for row in owned_configuration
                    if any(key in row for key in ("desired", "desired_value", "value", "revision", "unset"))]
    apply_rows = [row for row in owned_configuration
                  if any(key in row for key in ("applied", "applied_value", "application", "apply_status"))]
    config_availability = "available" if config_supplied else "not_supplied"
    desired_availability = "available" if desired_rows else ("not_supplied" if not config_supplied else "not_observed")
    application_availability = "available" if apply_rows else ("not_supplied" if not config_supplied else "not_observed")

    def model_category_availability(key: str, rows: list[dict[str, Any]]) -> str:
        if key not in model:
            return "not_evaluated"
        raw = model[key]
        if isinstance(raw, (list, dict)) and not raw:
            return "available"
        return "available" if rows else "not_evaluated"

    result = {"schema_version": 1, "action": action, "module": module, "lifecycle": lifecycle,
              "declarations": declarations, "capabilities": capabilities, "knowledge": knowledge,
              "configuration": {"schemas": [d for d in declarations if d["kind"] == "configuration"],
                                "service": owned_configuration, "service_availability": config_availability,
                                "desired_availability": desired_availability,
                                "application_availability": application_availability},
              "system_model": {"availability": model_availability,
                               "facts": owned_facts, "facts_availability": model_category_availability("facts", owned_facts),
                               "observers": owned_observers,
                               "observers_availability": model_category_availability("observers", owned_observers),
                               "responsibilities": owned_responsibilities,
                               "responsibilities_availability": model_category_availability("responsibilities", owned_responsibilities),
                               "health": owned_health,
                               "health_availability": model_category_availability("health", owned_health)},
              "dependencies": {**deps, "local_requirements": [
                  {"contribution": f"{d['kind']}:{d['id']}", "requires": d.get("requires", {})}
                  for d in contributions if d.get("requires")]}}
    if action == "detach-plan":
        result["detach"] = _detach_plan(Path(static["root"]), module, deps, contributions, runtime_data,
                                        declarations)
    else:
        result["detach"] = {"ready": False, "completeness": "not_requested"}
    return result


def _emit_error(message: str) -> int:
    print(json.dumps({"schema_version": 1, "error": message}, sort_keys=True, separators=(",", ":")), file=sys.stderr)
    return 2


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", action="store_true", help="read {root,name,action,runtime} JSON from stdin")
    parser.add_argument("action", nargs="?", choices=("inspect", "detach-plan"))
    parser.add_argument("root", nargs="?")
    parser.add_argument("name", nargs="?")
    args = parser.parse_args(argv)
    try:
        if args.snapshot:
            if any((args.action, args.root, args.name)):
                raise InspectionError("--snapshot accepts its request only through stdin")
            request = _strict_json_loads(sys.stdin.read())
            if not isinstance(request, dict):
                raise InspectionError("snapshot request must be an object")
            result = inspect_module(request.get("root", ""), request.get("name", ""),
                                    request.get("runtime"), request.get("action", "inspect"))
        else:
            if not args.action or not args.root or not args.name:
                parser.error("action, ROOT and NAME are required")
            result = inspect_module(args.root, args.name, action=args.action)
    except (InspectionError, ValidationError, OSError, TypeError, json.JSONDecodeError) as exc:
        return _emit_error(str(exc))
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
