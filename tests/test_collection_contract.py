"""Increment A: pure typed contracts and canonical dispatch with isolated fixtures."""

import copy
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
import capability_runtime as runtime
import module_contract
import module_registry
from operator_surface import _capability_entry

SCOPE = "scope:" + "a" * 32


def record(properties, required=None):
    return {"type": "object", "properties": properties,
            "required": list(properties) if required is None else required,
            "additionalProperties": False}


def collection_descriptor():
    row = record({
        "reference": {"type": "scoped_reference"},
        "unit": {"type": "string", "maxLength": 256, "validator": "systemd_unit"},
        "active_state": {"type": "string", "maxLength": 80},
        "sub_state": {"type": "string", "maxLength": 80},
    })
    page = record({
        "snapshot_revision": {"type": "string", "minLength": 1, "maxLength": 128},
        "returned_count": {"type": "integer", "minimum": 0, "maximum": 128},
        "total_count": {"type": "integer", "minimum": 0, "maximum": 1024},
        "has_more": {"type": "boolean"},
        "next_cursor": {"type": "string", "minLength": 1, "maxLength": 256},
    }, ["snapshot_revision", "returned_count", "total_count", "has_more"])
    outputs = record({
        "resource_kind": {"type": "enum", "enum": ["service"]},
        "inventory": {"type": "enum", "enum": ["loaded_system_services"]},
        "rows": {"type": "array", "items": row, "minItems": 0, "maxItems": 128},
        "page": page,
        "freshness": record({"observed_at": {"type": "string", "maxLength": 32},
                             "expires_at": {"type": "string", "maxLength": 32}}),
    })
    outputs.pop("type")
    outputs["schema_version"] = 2
    return {
        "kind": "capability", "id": "fixture.resources.list", "capability_version": 3,
        "owner": "fixture", "provider": "fixture", "handler": "fixture__list",
        "description": "READ fixture", "inputs": {"properties": {}, "required": [], "additionalProperties": False},
        "safety": {"tier": "READ"}, "privilege": "none", "preconditions": [],
        "verification": {"kind": "none", "required": False},
        "recovery": {"class": "not_applicable"}, "affects": [], "outputs": outputs,
        "collection": {"resource_kind": "service", "inventory": "loaded_system_services",
                       "columns": [{"field": "unit", "label": "Unit"}],
                       "inspect": {"capability_id": "system.service.status", "inputs_from_row": {"unit": "unit"}}},
    }


def page_value(count=1):
    return {
        "resource_kind": "service", "inventory": "loaded_system_services",
        "rows": [{"reference": {"scope_id": SCOPE, "object_id": f"service:systemd:demo{i}.service"},
                  "unit": f"demo{i}.service", "active_state": "active", "sub_state": "running"} for i in range(count)],
        "page": {"snapshot_revision": "revision-1", "returned_count": count, "total_count": count, "has_more": False},
        "freshness": {"observed_at": "2026-10-12T12:00:00Z", "expires_at": "2026-10-12T12:00:30Z"},
    }


def validate(value, raw=None):
    raw = raw or collection_descriptor()
    return runtime.validate_outputs(raw["outputs"], value, collection=raw["collection"], scope_id=SCOPE)


def admit_package(tmp_path, raw):
    package = tmp_path / "fixture"
    package.mkdir(exist_ok=True)
    (package / "module.conf").write_text(
        "[module]\nmodule_api=2\nname=fixture\ndisplay_name=Fixture\nversion=1.0.0\nruntime=bash\nentrypoint=module.sh\ncontracts=contract.json\n")
    (package / "module.sh").write_text("fixture__list() { :; }\n")
    contribution = {key: value for key, value in raw.items() if key not in {"owner", "provider"}}
    (package / "contract.json").write_text(json.dumps({"contract_version": 1, "contributions": [contribution]}))
    return module_contract.validate_module(package)


@pytest.mark.parametrize("count", [0, 1, 128])
def test_exact_row_bounds_and_shared_admission(tmp_path, count):
    raw = collection_descriptor()
    with patch.object(runtime, "validate_output_schema", wraps=runtime.validate_output_schema) as shared:
        package = admit_package(tmp_path, raw)
        cap = runtime.CapabilityDescriptor.from_dict(package["contributions"][0])
        value = page_value(count)
        assert validate(value, raw) == value
        assert shared.call_count == 3
    assert cap.inspect()["collection"] == raw["collection"]
    assert list(cap.inspect()["outputs"]["properties"]) == list(raw["outputs"]["properties"])
    registry = runtime.CapabilityRegistry()
    registry.register(cap)
    assert registry.prepare(cap.id, capability_version=3)["descriptor"]["outputs"] == raw["outputs"]
    assert registry.resolve(cap.id).available
    assert registry.inspection_binding(cap)["reason"] == "no_provider"
    projected = _capability_entry({"id": cap.id, "owner": "fixture", "provider": "fixture", "availability": "active", "descriptor": cap.inspect()})
    assert projected["collection"] == raw["collection"]


@pytest.mark.parametrize("spec", [
    {"type": "array", "items": {"type": "array"}, "minItems": 0, "maxItems": 128},
    {"type": "object", "properties": {}, "required": [], "additionalProperties": True},
    {"type": "scoped_reference", "properties": {}}, {"type": "null"},
    {"type": ["string", "null"]}, {"type": "string", "$ref": "other"},
    {"type": "string", "default": "x"}, {"type": "string", "pattern": "x"},
    {"type": "string", "validator": "callback"}, {"type": "string", "validator": {}},
    {"type": "secret_ref"}, {"type": "path"}, {"type": "string", "maxLength": 4097},
    {"type": "integer", "minimum": True}, {"type": "number", "maximum": float("inf")},
    {"type": "enum", "enum": ["same", "same"]},
])
def test_forbidden_nested_grammar_rejected_at_both_admission_boundaries(tmp_path, spec):
    raw = collection_descriptor()
    raw["outputs"]["properties"]["rows"]["items"]["properties"]["extra"] = spec
    with pytest.raises(runtime.CapabilityError):
        runtime.CapabilityDescriptor.from_dict(raw)
    with pytest.raises(module_contract.ValidationError):
        admit_package(tmp_path, raw)


@pytest.mark.parametrize("mutate", [
    lambda r: r.update(capability_version=True), lambda r: r.update(capability_version=4),
    lambda r: r.update(capability_version=2), lambda r: r.update(collection=None),
    lambda r: r["outputs"].update(schema_version=3),
    lambda r: r["outputs"]["properties"]["rows"].update(maxItems=129),
    lambda r: r["outputs"]["properties"]["rows"].update(minItems=True),
    lambda r: r["outputs"]["properties"]["rows"].update(minItems=2, maxItems=1),
    lambda r: r["outputs"]["properties"]["rows"]["items"]["required"].append("unit"),
    lambda r: r["outputs"]["required"].remove("page"),
    lambda r: r["outputs"]["properties"]["page"]["properties"].update(owner={"type": "string"}),
    lambda r: r["outputs"]["properties"]["resource_kind"].update(enum=["other"]),
    lambda r: r["outputs"]["properties"]["rows"]["items"]["properties"].update(password={"type": "string"}),
    lambda r: r["collection"].update(resource_kind="x" * 81),
    lambda r: r["collection"].update(action="shell"),
    lambda r: r["collection"].update(columns=[]),
    lambda r: r["collection"].update(columns=[{"field": "reference", "label": "Ref"}]),
    lambda r: r["collection"]["columns"].append({"field": "unit", "label": "Again"}),
    lambda r: r["collection"]["columns"][0].update(label="x" * 81),
    lambda r: r["collection"]["inspect"].update(provider="system"),
    lambda r: r["collection"]["inspect"].update(capability_id="shell command"),
    lambda r: r["collection"]["inspect"].update(inputs_from_row={"unit": "reference.object_id"}),
    lambda r: r["collection"]["inspect"].update(inputs_from_row={"unit": "reference"}),
    lambda r: r["collection"]["inspect"].update(inputs_from_row={"unit": {"from_row": "unit"}}),
])
def test_invalid_collection_declarations(tmp_path, mutate):
    raw = collection_descriptor()
    mutate(raw)
    with pytest.raises(runtime.CapabilityError):
        runtime.CapabilityDescriptor.from_dict(raw)
    with pytest.raises(module_contract.ValidationError):
        admit_package(tmp_path, raw)


@pytest.mark.parametrize("mutate", [
    lambda v: v.update(owner="REJECTED_SECRET_VALUE"),
    lambda v: v["rows"][0].update(unit=1),
    lambda v: v["rows"][0].update(unit="bad;command"),
    lambda v: v["rows"][0].update(active_state="\x1b[31m"),
    lambda v: v["rows"][0].update(sub_state="x" * 81),
    lambda v: v["rows"][0].update(active_state=[]),
    lambda v: v["rows"][0].update(unknown="REJECTED_SECRET_VALUE"),
    lambda v: v["rows"][0].pop("reference"),
    lambda v: v["rows"][0]["reference"].update(scope_id="hostname"),
    lambda v: v["rows"][0]["reference"].update(scope_id="scope:" + "b" * 32),
    lambda v: v["rows"][0]["reference"].update(object_id="not-an-id"),
    lambda v: v["rows"][0]["reference"].update(object_id="service:" + "x" * 151),
    lambda v: v["rows"][0]["reference"].update(owner="fixture"),
    lambda v: v["rows"].append(copy.deepcopy(v["rows"][0])),
    lambda v: v["rows"].extend([v["rows"][0]] * 128),
    lambda v: v["page"].update(returned_count=True),
    lambda v: v["page"].update(returned_count=2),
    lambda v: v["page"].update(total_count=0),
    lambda v: v["page"].update(total_count=1025),
    lambda v: v["page"].update(has_more=True),
    lambda v: v["page"].update(next_cursor="cursor"),
    lambda v: v["page"].update(has_more=True, total_count=2, next_cursor="é"),
    lambda v: v["page"].update(has_more=True, total_count=2, next_cursor="x" * 257),
    lambda v: v["freshness"].update(expires_at="2026-10-12T12:00:31Z"),
    lambda v: v["freshness"].update(expires_at="2026-10-12T12:00:29Z"),
    lambda v: v["freshness"].update(observed_at="2026-10-12T12:00:00+00:00"),
    lambda v: v["freshness"].update(observed_at="2026-02-30T12:00:00Z"),
    lambda v: v["freshness"].update(extra="REJECTED_SECRET_VALUE"),
])
def test_invalid_results_are_bounded_value_free(mutate):
    value = page_value()
    mutate(value)
    with pytest.raises(runtime.CapabilityError) as failure:
        validate(value)
    assert str(failure.value) in {"invalid_domain_output", "collection_limit_exceeded"}
    assert "REJECTED_SECRET_VALUE" not in str(failure.value)


def test_property_depth_text_and_metadata_exact_bounds():
    raw = collection_descriptor()
    props = raw["outputs"]["properties"]["rows"]["items"]["properties"]
    for i in range(28):
        props[f"extra_{i}"] = {"type": "string"}
    props["extra_0"] = record({"cell": {"type": "string", "maxLength": 4096}})
    raw["collection"]["columns"][0]["label"] = "界" * 80
    value = page_value()
    value["rows"][0]["extra_0"] = {"cell": "界" * 4096}
    value["rows"][0]["unit"] = "a" * 256
    value["rows"][0]["reference"]["object_id"] = "service:" + "a" * 150
    value["page"].update(snapshot_revision="r" * 128, total_count=1024, has_more=True, next_cursor="c" * 256)
    assert validate(value, raw) == value
    too_many = copy.deepcopy(raw)
    too_many["outputs"]["properties"]["rows"]["items"]["properties"]["overflow"] = {"type": "boolean"}
    with pytest.raises(runtime.CapabilityError):
        runtime.CapabilityDescriptor.from_dict(too_many)
    props["extra_0"] = record({"nested": record({"cell": {"type": "string"}})})
    with pytest.raises(runtime.CapabilityError):
        runtime.CapabilityDescriptor.from_dict(raw)


def test_utf8_serialized_page_exact_limit_and_surrogate_rejection():
    raw = collection_descriptor()
    props = raw["outputs"]["properties"]["rows"]["items"]["properties"]
    for i in range(16):
        props[f"cell_{i}"] = {"type": "string", "maxLength": 4096}
    value = page_value()
    row = value["rows"][0]
    for i in range(16):
        row[f"cell_{i}"] = ""
    remaining = runtime.COLLECTION_PAGE_BYTES - len(json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode())
    for i in range(16):
        chunk = min(remaining, 4096)
        row[f"cell_{i}"] = "界" * (chunk // 3) + "a" * (chunk % 3)
        remaining -= chunk
    assert remaining == 0
    assert len(json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()) == 65536
    assert validate(value, raw) == value
    row["cell_15"] += "é"
    with pytest.raises(runtime.CapabilityError, match="collection_limit_exceeded"):
        validate(value, raw)
    row["cell_15"] = "\ud800"
    with pytest.raises(runtime.CapabilityError, match="invalid_domain_output"):
        validate(value, raw)


def inspection_target(**changes):
    raw = collection_descriptor()
    raw.update(id="system.service.status", capability_version=2, handler="system__status", owner="system", provider="system",
               inputs={"properties": {"unit": {"type": "string", "maxLength": 256, "validator": "systemd_unit",
                                                "selector": {"schema_version": 1, "kind": "resource", "resource_kind": "service"}}},
                       "required": ["unit"], "additionalProperties": False},
               outputs={"schema_version": 1, "properties": {"state": {"type": "string"}}, "required": ["state"], "additionalProperties": False})
    raw.pop("collection")
    raw.update(changes)
    return runtime.CapabilityDescriptor.from_dict(raw)


def test_inspect_target_resolution_is_read_only_and_preserves_ambiguity():
    registry = runtime.CapabilityRegistry()
    cap = registry.register(collection_descriptor())
    target = registry.register(inspection_target())
    assert registry.inspection_binding(cap)["status"] == "available"
    assert registry.inspect(cap.id)["declarations"][0]["inspection_binding"]["capability_version"] == 2
    request = {"op": "resolve", "id": cap.id, "descriptors": [cap.inspect(), target.inspect()]}
    for declaration in request["descriptors"]:
        declaration.pop("available")
    result = subprocess.run([sys.executable, str(ROOT / "core/lib/capability_runtime.py")],
                            input=json.dumps(request), text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["declarations"][0]["inspection_binding"]["status"] == "available"
    target.active = False
    assert registry.inspection_binding(cap)["status"] == "unavailable"
    assert registry.resolve(cap.id).available
    target.active = True
    registry.register(inspection_target(provider="other"))
    assert registry.inspection_binding(cap)["status"] == "ambiguous"
    assert registry.inspection_binding(cap, provider="other")["status"] == "available"
    assert registry.inspection_binding(cap, provider="missing")["status"] == "unavailable"


@pytest.mark.parametrize("change", ["safety", "type", "bound", "validator", "selector", "required", "extra", "optional_row"])
def test_incompatible_inspection_target_does_not_disable_collection(change):
    registry = runtime.CapabilityRegistry()
    cap = registry.register(collection_descriptor())
    target = inspection_target()
    spec = target.inputs["properties"]["unit"]
    if change == "safety":
        target.safety = {"tier": "CHANGE"}
    elif change == "required":
        target.inputs["required"].append("missing")
    elif change == "extra":
        target.inputs["properties"] = {}
    elif change == "optional_row":
        cap.outputs["properties"]["rows"]["items"]["required"].remove("unit")
    else:
        spec.update({"type": "integer"} if change == "type" else {"maxLength": 255} if change == "bound" else
                    {"validator": "package_name"} if change == "validator" else
                    {"selector": {"schema_version": 1, "kind": "resource", "resource_kind": "package"}})
    registry.register(target)
    assert registry.inspection_binding(cap)["reason"] == "incompatible_inspection_target"
    assert registry.resolve(cap.id).available


def test_handler_bridge_and_shell_version_pin(tmp_path):
    raw = collection_descriptor()
    command = [sys.executable, str(ROOT / "core/lib/capability_runtime.py"), "handler-output",
               json.dumps(raw["outputs"]), json.dumps(raw["collection"]), SCOPE]
    valid = subprocess.run(command, input=json.dumps({"status": "ok", "result": page_value()}), text=True, capture_output=True, check=False)
    assert valid.returncode == 0
    assert json.loads(valid.stdout) == page_value()
    for payload in [json.dumps({"status": "ok", "result": {"rows": "REJECTED_SECRET_VALUE"}}),
                    "x" * (runtime.COLLECTION_RESULT_BYTES + 1),
                    '{"status":"error","error":{"code":"failure","message":"REJECTED_SECRET_VALUE"}}']:
        invalid = subprocess.run(command, input=payload, text=True, capture_output=True, check=False)
        assert invalid.returncode != 0
        assert "REJECTED_SECRET_VALUE" not in invalid.stdout + invalid.stderr
    result = subprocess.run([sys.executable, str(ROOT / "core/lib/capability_runtime.py"), "prepare-shell", raw["id"], "{}", "fixture", "3", ""],
                            input=json.dumps([raw]), text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["capability_version"] == 3
    assert admit_package(tmp_path, raw)["contributions"][0]["capability_version"] == 3


def test_v3_success_and_result_envelope_byte_limit():
    result = {"operation_id": "op-" + "a" * 32, "capability_id": "fixture.resources.list", "capability_version": 3,
              "execution_status": "succeeded", "output_status": "valid", "verification_status": "not_applicable", "outcome": "success", "result": page_value()}
    runtime._validate_result(result)
    result["output_status"] = "invalid"
    with pytest.raises(runtime.CapabilityError):
        runtime._validate_result(result)
    result.update(result=None, outcome="invalid_output")
    runtime._validate_result(result)
    result["padding"] = ""
    size = len(json.dumps(result, ensure_ascii=False, separators=(",", ":")).encode())
    result["padding"] = "a" * (runtime.COLLECTION_RESULT_BYTES - size)
    runtime._validate_result(result)
    result["padding"] += "a"
    with pytest.raises(runtime.CapabilityError, match="collection_limit_exceeded"):
        runtime._validate_result(result)


def test_typed_privilege_still_requires_reviewed_output_adapter():
    raw = collection_descriptor()
    raw.update(id="system.service.restart", owner="system", privilege="required")
    assert module_registry.static_unavailable_reason(raw, "system") == "typed_privileged_output_adapter_unavailable"


@pytest.mark.parametrize("mode", ["valid", "utf8", "invalid", "duplicate", "oversize", "disabled", "old_pin"])
def test_isolated_v3_package_dispatch_and_history(tmp_path, mode):
    root = tmp_path / "igor"
    modules = root / "modules"
    modules.mkdir(parents=True)
    raw = collection_descriptor()
    if mode in {"utf8", "oversize"}:
        raw["outputs"]["properties"]["rows"]["items"]["properties"]["detail"] = {"type": "string", "maxLength": 4096}
    admit_package(modules, raw)
    package = modules / "fixture"
    value = page_value()
    if mode in {"utf8", "oversize"}:
        value = page_value(3 if mode == "utf8" else 4)
        for row in value["rows"]:
            row["detail"] = "😀" * 4096
        if mode == "oversize":
            row = value["rows"][0]
            sentinel = "REJECTED_SECRET_VALUE"
            row["detail"] = sentinel + row["detail"][len(sentinel):]
    if mode == "invalid":
        value["rows"][0]["unit"] = "REJECTED_SECRET_VALUE;"
    envelope = json.dumps({"status": "ok", "result": value}, ensure_ascii=False, separators=(",", ":"))
    if mode == "duplicate":
        envelope = envelope.replace('"unit":"demo0.service"', '"unit":"demo0.service","unit":"REJECTED_SECRET_VALUE"')
    (package / "module.sh").write_text(
        "fixture__list() { printf X > \"$IGOR_DIR/invoked\"; printf '%s\\n' '" + envelope + "'; }\n")
    (root / "core").symlink_to(ROOT / "core", target_is_directory=True)
    (root / "config").mkdir()
    (root / "config/modules.conf").write_text("fixture=" + ("disabled" if mode == "disabled" else "enabled") + "\n")
    env = dict(os.environ, IGOR_DIR=str(root), IGOR_DATA_DIR=str(root / "data"), IGOR_PYTHON=sys.executable)
    script = r'''source "$1/core/lib/module_loader.sh"
_ml_log() { :; }
igor_load_all_modules >/dev/null
source "$1/core/ai/safety.sh"
ai_mode=assist
if [ "$2" = old_pin ]; then version=2; else version=3; fi
if [ "$2" = utf8 ]; then
    proposal="$(igor_capability_prepare fixture.resources.list '{}' fixture 3)" || exit 1
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    IGOR_CAPABILITY_APPROVAL_STATUS=not_required
    igor_capability_execute "$proposal" >/dev/null || exit 1
    igor_capability_result "$(_igor_capability_field "$IGOR_CAPABILITY_LAST_RESULT" operation_id)"
    rc=$?
else
    ai_execute_tool "{\"tool\":\"run_capability\",\"id\":\"fixture.resources.list\",\"inputs\":{},\"capability_version\":$version}" >/dev/null
    rc=$?
    [ -z "${IGOR_CAPABILITY_LAST_RESULT:-}" ] || printf '%s\n' "$IGOR_CAPABILITY_LAST_RESULT"
fi
printf '\nHISTORY\n'
igor_history_cli recent 1
exit "$rc"
'''
    result = subprocess.run(["bash", "-c", script, "_", str(ROOT), mode], env=env, text=True, capture_output=True, timeout=30, check=False)
    if mode in {"disabled", "old_pin"}:
        assert result.returncode != 0
        assert not (root / "invoked").exists()
        assert result.stdout.split("HISTORY\n")[-1].strip() == "[]"
        return
    # Transport completion is separate from the authoritative operation outcome.
    assert result.returncode == 0, result.stdout + result.stderr
    output, history_raw = result.stdout.split("\nHISTORY\n")
    canonical = json.loads(output.strip().splitlines()[-1])
    history = json.loads(history_raw)[0]
    assert (root / "invoked").exists()
    assert canonical["capability_version"] == 3
    assert canonical["execution_status"] == "succeeded"
    assert canonical["privilege_status"] == "not_required"
    assert history["capability"]["version"] == 3
    assert history["execution_status"] == "succeeded"
    runtime._validate_result(canonical)
    if mode in {"valid", "utf8"}:
        assert canonical["result"] == value
        assert canonical["output_status"] == "valid"
        assert canonical["verification_status"] == "not_applicable"
        assert canonical["outcome"] == history["outcome"] == "success"
    else:
        assert canonical["result"] is None
        assert canonical["output_status"] == "invalid"
        assert canonical["verification_status"] == "unknown"
        assert canonical["outcome"] == history["outcome"] == "invalid_output"
        reason = "collection_limit_exceeded" if mode == "oversize" else "invalid_domain_output"
        assert canonical["verification_evidence"][0]["reason"] == reason
        assert history["verification"]["evidence"][0]["data"]["reason"] == reason
        assert "REJECTED_SECRET_VALUE" not in result.stdout + result.stderr
        for path in (root / "data").rglob("*"):
            if path.is_file():
                assert b"REJECTED_SECRET_VALUE" not in path.read_bytes()


def test_optional_hints_mixed_scopes_and_nonfinite_nested_numbers():
    raw = collection_descriptor()
    raw["collection"].pop("columns")
    raw["collection"].pop("inspect")
    cap = runtime.CapabilityDescriptor.from_dict(raw)
    assert validate(page_value(), raw) == page_value()
    assert runtime.CapabilityRegistry().inspection_binding(cap)["reason"] == "not_declared"
    value = page_value(2)
    value["rows"][1]["reference"]["scope_id"] = "scope:" + "b" * 32
    with pytest.raises(runtime.CapabilityError):
        runtime.validate_outputs(raw["outputs"], value, collection=raw["collection"])
    props = raw["outputs"]["properties"]["rows"]["items"]["properties"]
    props["measurement"] = {"type": "number", "minimum": 0, "maximum": 10}
    value = page_value()
    for number in [float("nan"), float("inf"), True, 10**400]:
        value["rows"][0]["measurement"] = number
        with pytest.raises(runtime.CapabilityError):
            validate(value, raw)
    value["rows"][0]["measurement"] = 10
    assert validate(value, raw) == value


def test_strict_json_nested_duplicates_and_invalid_utf8_are_private():
    raw = collection_descriptor()
    command = [sys.executable, str(ROOT / "core/lib/capability_runtime.py"), "handler-output",
               json.dumps(raw["outputs"]), json.dumps(raw["collection"])]
    envelope = json.dumps({"status": "ok", "result": page_value()})
    cases = [envelope.replace('"unit": "demo0.service"', '"unit": "demo0.service", "unit": "REJECTED_SECRET_VALUE"').encode(),
             b'{"status":"ok","result":{"rows":"\xffREJECTED_SECRET_VALUE"}}',
             b'{"status":"ok","result":{"rows":' + b'9' * 5000 + b'}}',
             b'{"status":"ok","result":' + b'[' * 1500 + b'0' + b']' * 1500 + b'}']
    for payload in cases:
        result = subprocess.run(command, input=payload, capture_output=True, check=False)
        assert result.returncode == 3
        assert not result.stdout
        assert result.stderr.strip() == b"capability runtime: invalid domain output"
    request = json.dumps({"op": "validate", "descriptor": raw})
    request = request.replace('"maxLength": 256', '"maxLength": 256, "maxLength": 4096', 1)
    result = subprocess.run([sys.executable, str(ROOT / "core/lib/capability_runtime.py")],
                            input=request, text=True, capture_output=True, check=False)
    assert result.returncode != 0
    assert not result.stdout
    assert "duplicate JSON field" in result.stderr


def test_collection_identifier_enum_and_inspect_map_exact_admission_limits():
    raw = collection_descriptor()
    for key in ("resource_kind", "inventory"):
        raw["collection"][key] = "a" * 80
        raw["outputs"]["properties"][key]["enum"] = ["a" * 80]
    raw["collection"]["inspect"]["inputs_from_row"] = {f"input_{i}": "unit" for i in range(32)}
    row_props = raw["outputs"]["properties"]["rows"]["items"]["properties"]
    row_props["category"] = {"type": "enum", "enum": list(range(32))}
    runtime.CapabilityDescriptor.from_dict(raw)
    raw["collection"]["inspect"]["inputs_from_row"]["overflow"] = "unit"
    with pytest.raises(runtime.CapabilityError):
        runtime.CapabilityDescriptor.from_dict(raw)
    raw["collection"]["inspect"]["inputs_from_row"].pop("overflow")
    row_props["category"]["enum"].append(32)
    with pytest.raises(runtime.CapabilityError):
        runtime.CapabilityDescriptor.from_dict(raw)


def test_inherited_ruff_diagnostic_reproduces_on_reviewed_source():
    source = subprocess.run(["git", "show", "525cc76ea556bae199fecfaaa6bd931d01a9f6ea:core/ai/tool_input.py"],
                            cwd=ROOT, text=True, capture_output=True, check=True).stdout
    ruff = shutil.which("ruff") or str(Path(sys.executable).with_name("ruff"))
    result = subprocess.run([ruff, "check", "--output-format=json", "--stdin-filename",
                             str(ROOT / "core/ai/tool_input.py"), "-"],
                            cwd=ROOT, input=source, text=True, capture_output=True, check=False)
    assert result.returncode == 1, result.stdout + result.stderr
    diagnostics = json.loads(result.stdout)
    assert [(item["code"], item["location"]["row"]) for item in diagnostics] == [("SIM103", 221)]


@pytest.mark.parametrize("mutate", [
    lambda v: v["rows"].extend([v["rows"][0]] * 128),
    lambda v: v["rows"][0].update(sub_state="x" * 81),
    lambda v: v["page"].update(total_count=1025),
    lambda v: v["page"].update(has_more=True, total_count=2, next_cursor="x" * 257),
])
def test_collection_limits_keep_value_free_reason_at_both_bridges(mutate):
    raw = collection_descriptor()
    value = page_value()
    mutate(value)
    with pytest.raises(runtime.CapabilityError, match="^collection_limit_exceeded$"):
        validate(value, raw)
    envelope = json.dumps({"status": "ok", "result": value})
    bridge = subprocess.run([sys.executable, str(ROOT / "core/lib/capability_runtime.py"), "handler-output",
                             json.dumps(raw["outputs"]), json.dumps(raw["collection"]), SCOPE],
                            input=envelope, text=True, capture_output=True, check=False)
    assert bridge.returncode == 3
    assert not bridge.stdout
    assert bridge.stderr.strip() == "capability runtime: collection_limit_exceeded"
    request = {"op": "output", "outputs": raw["outputs"], "collection": raw["collection"],
               "scope_id": SCOPE, "envelope": envelope}
    bridge = subprocess.run([sys.executable, str(ROOT / "core/lib/capability_runtime.py")],
                            input=json.dumps(request), text=True, capture_output=True, check=False)
    assert bridge.returncode == 1
    assert not bridge.stdout
    assert bridge.stderr.strip() == "capability runtime: collection_limit_exceeded"


def test_sorted_schema_transport_preserves_collection_meaning():
    raw = collection_descriptor()
    raw["collection"]["columns"].append({"field": "sub_state", "label": "Substate"})
    transported = json.loads(json.dumps(raw, sort_keys=True))
    assert transported["collection"]["columns"] == raw["collection"]["columns"]
    assert list(transported["outputs"]["properties"]) == sorted(raw["outputs"]["properties"])
    assert runtime.CapabilityDescriptor.from_dict(transported).collection == raw["collection"]
    assert validate(page_value(2), transported) == page_value(2)
    transported["collection"].pop("columns")
    assert validate(page_value(2), transported) == page_value(2)
