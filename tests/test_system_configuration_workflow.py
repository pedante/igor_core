"""First real module-owned setting through the Core configuration lifecycle."""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
import module_contract
from configuration import ConfigurationService
from configuration_schema import ConfigurationError

SETTING = "system.memory.warning_threshold_mib"
TARGET = "module:system"


def isolated_system(tmp_path):
    """Use a copied real package and isolated Core state for every shell proof."""
    igor_dir = tmp_path / "igor"
    (igor_dir / "modules").mkdir(parents=True)
    (igor_dir / "config").mkdir()
    shutil.copytree(ROOT / "modules/system", igor_dir / "modules/system")
    shutil.copytree(ROOT / "core", igor_dir / "core")
    (igor_dir / "config/modules.conf").write_text("system=enabled\n")
    env = {
        **os.environ,
        "IGOR_DIR": str(igor_dir),
        "IGOR_DATA_DIR": str(igor_dir / "data"),
        "IGOR_RUNTIME_DIR": str(igor_dir / "runtime"),
    }
    return igor_dir, env


def run_system_shell(tmp_path, script, input_text=None, timeout=120):
    igor_dir, env = isolated_system(tmp_path)
    result = subprocess.run(
        ["bash", "-c", script], env=env, input=input_text, text=True, capture_output=True,
        timeout=timeout, check=False,
    )
    return igor_dir, result


def load_schema(package):
    validated = module_contract.validate_module(package)
    row = next(row for row in validated["contributions"] if row["kind"] == "configuration")
    return row["schema"]


def test_system_package_declares_core_managed_warning_threshold_and_separate_critical_boundary(tmp_path):
    schema = load_schema(ROOT / "modules/system")
    field = next(row for row in schema["fields"] if row["id"] == SETTING)
    assert schema["owner"] == "system"
    assert field["type"] == "integer" and field["scope"] == "module"
    assert (field["default"], field["minimum"], field["maximum"]) == (150, 81, 4096)

    service = ConfigurationService(tmp_path, schemas=[("system", schema)])
    view = service.inspect(SETTING, TARGET)
    assert view["schema_owner"] == "system"
    assert view["desired"]["status"] == "absent"
    assert view["resolved"] == {"status": "resolved", "value": 150, "source": "default"}
    assert view["observed"]["status"] == "unavailable"
    assert view["application"]["status"] == "not_verified"
    assert service.export()["records"] == []
    # The existing critical threshold remains an independent health rule.
    check = (ROOT / "modules/system/lib/memory_warning.py").read_text()
    assert "value < 80 * 1024 * 1024" in check
    assert "SYSTEM_RAM_WARN_MB" not in check + (ROOT / "modules/system/contracts/host.json").read_text()


def test_core_schema_rejects_values_outside_module_range_and_stale_revision(tmp_path):
    schema = load_schema(ROOT / "modules/system")
    service = ConfigurationService(tmp_path, schemas=[("system", schema)])
    for value in (80, 4097, True, 150.0):
        with pytest.raises(ConfigurationError):
            service.validate([{"target": TARGET, "id": SETTING, "value": value}])

    prepared = service.status()
    changes = [{"target": TARGET, "id": SETTING, "value": 200}]
    first = service.commit(changes, expected_revision=0,
                           expected_state=prepared["state_token"],
                           operation_id="op-" + "1" * 32)
    assert first["application"] == "not_verified"
    with pytest.raises(ConfigurationError, match="conflict"):
        service.commit(changes, expected_revision=0,
                       expected_state=prepared["state_token"],
                       operation_id="op-" + "2" * 32)


def test_system_desired_record_coexists_with_core_setting_and_survives_disabled_owner(tmp_path):
    schema = load_schema(ROOT / "modules/system")
    service = ConfigurationService(tmp_path, schemas=[("system", schema)])
    before = service.status()
    service.commit([{"target": TARGET, "id": SETTING, "value": 225}],
                   expected_revision=0, expected_state=before["state_token"],
                   operation_id="op-" + "3" * 32)
    intermediate = service.status()
    service.commit([{"target": "installation:local", "id": "ai.verbose", "value": False}],
                   expected_revision=1, expected_state=intermediate["state_token"],
                   operation_id="op-" + "4" * 32)
    assert service.inspect(SETTING, TARGET)["desired"] == {"status": "value", "value": 225}
    assert service.inspect()["desired"] == {"status": "value", "value": False}

    inactive = ConfigurationService(tmp_path, schemas=[("system", schema)],
                                    owner_active=lambda owner: owner == "core")
    state = inactive.inspect(SETTING, TARGET)
    assert state["availability"] == "owner_inactive"
    assert state["desired"] == {"status": "value", "value": 225}
    assert state["runtime_consumption"]["status"] == "owner_inactive"
    assert inactive.inspect()["desired"] == {"status": "value", "value": False}


def test_system_health_consumer_uses_applied_value_and_keeps_critical_boundary(monkeypatch, capsys):
    path = ROOT / "modules/system/lib/memory_warning.py"
    spec = importlib.util.spec_from_file_location("system_memory_warning", path)
    consumer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(consumer)

    def check(available_mib, warning_mib):
        monkeypatch.setenv("IGOR_SYSTEM_MEMORY_WARNING_MIB", str(warning_mib))
        monkeypatch.setenv("IGOR_SYSTEM_MEMORY_WARNING_REVISION", "3")
        monkeypatch.setenv("IGOR_SYSTEM_MEMORY_WARNING_STATE", "a" * 64)
        request = {"api_version": 2, "contribution_id": "host.memory.health", "input": {
            "facts": {"memory.available_bytes": {"availability": "known",
                "value": available_mib * 1024 * 1024, "recorded_at": "test"}}}}
        monkeypatch.setattr(sys, "argv", [str(path), "check", json.dumps(request)])
        assert consumer.main() == 0
        return json.loads(capsys.readouterr().out)["result"]

    assert check(100, 150)["status"] == "WARN"
    assert check(100, 90)["status"] == "OK"
    assert check(200, 220)["status"] == "WARN"
    assert check(79, 220)["status"] == "CRITICAL"


def test_system_startup_consumes_threshold_without_eager_state_token(tmp_path):
    _igor_dir, result = run_system_shell(tmp_path, r'''
source "$IGOR_DIR/core/lib/module_loader.sh"
source "$IGOR_DIR/core/ai/core.sh"
_ml_log() { :; }
igor_load_all_modules >/dev/null || exit 2
printf 'consumer=%s:%s\n' "$IGOR_SYSTEM_MEMORY_WARNING_MIB" "$IGOR_SYSTEM_MEMORY_WARNING_REVISION"
[ -z "${IGOR_SYSTEM_MEMORY_WARNING_STATE+x}" ] || exit 3
request='{"api_version":2,"contribution_id":"host.memory.health","input":{"facts":{"memory.available_bytes":{"availability":"known","value":104857600,"recorded_at":"test"}}}}'
check="$(printf '%s\n' "$request" | system__check_memory)" || exit 4
printf 'CHECK=%s\n' "$check"
''')
    assert result.returncode == 0, result.stdout + result.stderr
    assert "consumer=150:0" in result.stdout
    check = json.loads(next(line.removeprefix("CHECK=") for line in result.stdout.splitlines()
                            if line.startswith("CHECK=")))
    assert check["status"] == "ok"
    assert check["result"]["status"] == "WARN"
    assert "warning_mib=150;revision=0" in check["result"]["evidence"]


def test_tui_startup_snapshot_feeds_system_and_ai_once(tmp_path):
    _igor_dir, result = run_system_shell(tmp_path, r'''
export IGOR_TUI_MODE=true
source "$IGOR_DIR/core/lib/module_loader.sh"
source "$IGOR_DIR/core/ai/core.sh"
_ml_log() { :; }
igor_load_all_modules >/dev/null || exit 2
printf 'memory=%s:%s\n' "$IGOR_SYSTEM_MEMORY_WARNING_MIB" "$IGOR_SYSTEM_MEMORY_WARNING_REVISION"
printf 'verbose=%s:%s\n' "$IGOR_VERBOSE" "$IGOR_VERBOSE_REVISION"
printf 'pending=%s\n' "$IGOR_CONFIGURATION_STARTUP_AI_PENDING"
[ -z "${IGOR_SYSTEM_MEMORY_WARNING_STATE+x}" ] || exit 3
_igor_configuration_ai_verbose_resolve() { touch "$SECOND_READ_MARKER"; return 91; }
_ai_configuration_verbose_load || exit 4
[ ! -e "$SECOND_READ_MARKER" ] || exit 5
[ -z "${IGOR_CONFIGURATION_STARTUP_AI_PENDING+x}" ] || exit 6
printf 'reuse=%s:%s:%s\n' "$IGOR_VERBOSE" "$_IGOR_TUI_CONFIGURATION_SERVICE_MS" "$_IGOR_TUI_CONFIGURATION_DECODE_MS"
'''.replace("$SECOND_READ_MARKER", str(tmp_path / "second-read")))
    assert result.returncode == 0, result.stdout + result.stderr
    assert "memory=150:0" in result.stdout
    assert "verbose=true:0" in result.stdout
    assert "pending=1" in result.stdout
    assert "reuse=true:0:0" in result.stdout


def test_explicit_readback_acquires_full_state_proof_just_in_time(tmp_path):
    _igor_dir, result = run_system_shell(tmp_path, r'''
source "$IGOR_DIR/core/lib/module_loader.sh"
source "$IGOR_DIR/core/ai/core.sh"
_ml_log() { :; }
igor_load_all_modules >/dev/null || exit 2
[ -z "${IGOR_SYSTEM_MEMORY_WARNING_STATE+x}" ] || exit 3
view="$(_igor_configuration_call inspect '{"id":"system.memory.warning_threshold_mib","target":"module:system"}')" || exit 4
inputs="$(python3 -c 'import json,sys; s=json.loads(sys.argv[1]); print(json.dumps({"revision":s["revision"],"state":s["state_token"]},separators=(",",":")))' "$view")" || exit 5
proposal="$(igor_capability_prepare system.memory.warning.readback "$inputs" system 2)" || exit 6
[ -z "${IGOR_SYSTEM_MEMORY_WARNING_STATE+x}" ] || exit 7
envelope="$(_igor_capability_invoke_handler "$proposal")" || exit 8
[ -z "${IGOR_SYSTEM_MEMORY_WARNING_STATE+x}" ] || exit 9
printf 'VIEW=%s\nENVELOPE=%s\n' "$view" "$envelope"
''', timeout=180)
    assert result.returncode == 0, result.stdout + result.stderr
    view = json.loads(next(line.removeprefix("VIEW=") for line in result.stdout.splitlines()
                           if line.startswith("VIEW=")))
    envelope = json.loads(next(line.removeprefix("ENVELOPE=") for line in result.stdout.splitlines()
                               if line.startswith("ENVELOPE=")))
    assert envelope["status"] == "ok"
    assert envelope["result"]["value"] == 150
    assert envelope["result"]["revision"] == view["revision"]
    assert envelope["result"]["state"] == view["state_token"]


def test_system_module_capabilities_remain_core_policy_boundaries():
    contract = json.loads((ROOT / "modules/system/contracts/host.json").read_text())
    capabilities = {row["id"]: row for row in contract["contributions"]
                    if row["kind"] == "capability"}
    apply = capabilities["system.memory.warning.apply"]
    readback = capabilities["system.memory.warning.readback"]
    assert apply["safety"]["tier"] == "CHANGE" and apply["privilege"] == "none"
    assert apply["recovery"]["class"] == "reversible"
    assert apply["verification"] == {"kind": "trusted_query",
        "check_id": "system.memory.warning.consumer", "required": True}
    assert readback["safety"]["tier"] == "READ" and readback["privilege"] == "none"
    assert readback["verification"]["kind"] == "trusted_query"
    assert readback["outputs"]["properties"]["source"]["enum"] == [
        "system.host.memory.health.consumer"]


def test_stale_apply_is_rejected_before_module_execution(tmp_path):
    igor_dir, result = run_system_shell(tmp_path, r"""
source "$IGOR_DIR/core/lib/module_loader.sh"
source "$IGOR_DIR/core/ai/core.sh"
_ml_log() { :; }
igor_load_all_modules >/dev/null
view="$(_igor_configuration_call inspect '{"id":"system.memory.warning_threshold_mib","target":"module:system"}')"
stale="$(python3 -c 'import json,sys; s=json.loads(sys.argv[1]); print(json.dumps({"value":220,"revision":s["revision"],"state":s["state_token"]}))' "$view")"
proposal="$(igor_capability_prepare system.memory.warning.apply "$stale" system 2)" || exit 3
current="$(printf '%s' "$stale" | python3 -c 'import json,sys; r=json.load(sys.stdin); r.update(value=230,operation_id="op-"+"5"*32); print(json.dumps(r))')"
_igor_configuration_call memory-set "$current" >/dev/null || exit 4
if igor_capability_execute "$proposal"; then exit 5; fi
[ "$IGOR_SYSTEM_MEMORY_WARNING_MIB" = 150 ] || exit 6
printf 'stale-rejected\n'
""")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "stale-rejected" in result.stdout
    service = ConfigurationService(igor_dir / "data", schemas=[("system", load_schema(igor_dir / "modules/system"))])
    assert service.inspect(SETTING, TARGET)["desired"] == {"status": "value", "value": 230}
    rows = service.history.recent()
    assert not any(row["capability"]["id"] == "system.memory.warning.apply" for row in rows)


def test_approved_change_applies_module_consumer_and_records_independent_readback(tmp_path):
    igor_dir, result = run_system_shell(tmp_path, r'''
    source "$IGOR_DIR/core/lib/module_loader.sh"
    source "$IGOR_DIR/core/ai/core.sh"
_ml_log() { :; }
igor_load_all_modules >/dev/null
ai_mode=assist
_ai_approval_prompt() { _AI_APPROVAL_OUTCOME=APPROVE; return 0; }
before_model="$(cat "$IGOR_MODEL_RUNTIME_FILE")"
_ai_configuration_memory_warning_set 220 || exit 4
view="$(_igor_configuration_call inspect '{"id":"system.memory.warning_threshold_mib","target":"module:system"}')"
module_view="$(igor_module_inspect system)"
printf 'value=%s revision=%s consumer=%s\n' "$IGOR_SYSTEM_MEMORY_WARNING_MIB" \
    "$IGOR_SYSTEM_MEMORY_WARNING_REVISION" "$IGOR_SYSTEM_MEMORY_CONSUMER_ID"
printf 'INSPECTION=%s\n' "$view"
printf 'MODULE_INSPECTION=%s\n' "$module_view"
[ "$(cat "$IGOR_MODEL_RUNTIME_FILE")" = "$before_model" ] || exit 5
''')
    assert result.returncode == 0, result.stdout + result.stderr
    assert "value=220 revision=1 consumer=" in result.stdout
    same_process = next(line.removeprefix("INSPECTION=") for line in result.stdout.splitlines()
                        if line.startswith("INSPECTION="))
    runtime = json.loads(same_process)["runtime_consumption"]
    assert runtime["status"] == "consumed_current_process"
    assert runtime["verification"] == "not_verified" and runtime["matches_desired"] is True
    assert runtime["source"] == "system.host.memory.health.consumer"
    assert runtime["consumer_id"]
    module_view = json.loads(next(line.removeprefix("MODULE_INSPECTION=")
                                  for line in result.stdout.splitlines()
                                  if line.startswith("MODULE_INSPECTION=")))
    inspected = {row["id"]: row for row in module_view["configuration"]["service"]}
    setting = inspected[SETTING]
    assert setting["desired"] == {"status": "value", "value": 220}
    assert setting["runtime_consumption"]["status"] == "consumed_current_process"
    sys.path.insert(0, str(ROOT / "core/ai"))
    from tui import panel_rows
    rows = panel_rows({"source": "Core module inspection", "data": module_view["configuration"]})
    rendered = " ".join(rows)
    assert SETTING in rendered and "220" in rendered
    service = ConfigurationService(igor_dir / "data", schemas=[("system", load_schema(igor_dir / "modules/system"))])
    view = service.inspect(SETTING, TARGET)
    assert view["desired"] == {"status": "value", "value": 220}
    assert view["application"]["status"] == "not_verified"
    assert view["runtime_consumption"]["status"] == "unavailable"
    rows = service.history.recent()
    assert {row["capability"]["id"] for row in rows} == {
        "core.configuration.system_memory_warning.set",
        "system.memory.warning.apply",
        "system.memory.warning.readback",
    }
    assert all(row["outcome"] == "success" and row["verification"]["status"] == "passed" for row in rows)
    apply = next(row for row in rows if row["capability"]["id"] == "system.memory.warning.apply")
    assert apply["provider"]["id"] == "system"
    assert apply["approval"]["result"] in {"approved", "auto_approved"}
    assert any(row["capability"]["id"] == "core.configuration.system_memory_warning.set"
               and row["approval"]["result"] == "approved" for row in rows)


def test_declined_change_does_not_commit_or_apply(tmp_path):
    igor_dir, result = run_system_shell(tmp_path, r'''
    source "$IGOR_DIR/core/lib/module_loader.sh"
    source "$IGOR_DIR/core/ai/core.sh"
_ml_log() { :; }
igor_load_all_modules >/dev/null
ai_mode=assist
approval_count=0
_ai_approval_prompt() {
    approval_count=$((approval_count + 1))
    if [ "$approval_count" -eq 1 ]; then _AI_APPROVAL_OUTCOME=APPROVE; return 0; fi
    _AI_APPROVAL_OUTCOME=DECLINE
    return 1
}
if _ai_configuration_memory_warning_set 240; then exit 4; fi
''')
    assert result.returncode == 0, result.stdout + result.stderr
    service = ConfigurationService(igor_dir / "data", schemas=[("system", load_schema(igor_dir / "modules/system"))])
    assert service.inspect(SETTING, TARGET)["desired"] == {"status": "value", "value": 240}
    history = service.history.recent()
    assert len(history) == 2
    by_id = {row["capability"]["id"]: row for row in history}
    assert by_id["core.configuration.system_memory_warning.set"]["approval"]["result"] == "approved"
    assert by_id["system.memory.warning.apply"]["approval"]["result"] == "denied"


@pytest.mark.parametrize(("mismatch_after", "failed_capability", "failure_outcome"), [
    (0, "system.memory.warning.apply", "unverified_change"),
    (1, "system.memory.warning.readback", "unverified_result"),
])
def test_readback_mismatch_is_recorded_without_rollback(
        tmp_path, mismatch_after, failed_capability, failure_outcome):
    script = r"""
source "$IGOR_DIR/core/lib/module_loader.sh"
source "$IGOR_DIR/core/ai/core.sh"
python3 - "$IGOR_DIR/modules/system/module.sh" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
path.write_text(path.read_text() + r'''
system__read_memory_warning() {
    local response marker count
    marker="$IGOR_DATA_DIR/test-readback-count"
    count=0
    [ ! -f "$marker" ] || count="$(cat "$marker")"
    printf '%s' "$((count + 1))" > "$marker"
    response="$(_mod_sys_memory_warning_request readback)" || return 1
    if [ "$count" -ge __MISMATCH_AFTER__ ]; then
        printf '%s' "$response" | python3 -c 'import json,sys; row=json.load(sys.stdin); row["result"]["value"] += 1; print(json.dumps(row,separators=(",",":")))'
    else
        printf '%s' "$response"
    fi
}
''')
PY
_ml_log() { :; }
igor_load_all_modules >/dev/null
ai_mode=executive
if _ai_configuration_memory_warning_set 220; then exit 4; fi
view="$(_igor_configuration_call inspect '{"id":"system.memory.warning_threshold_mib","target":"module:system"}')"
printf 'INSPECTION=%s\n' "$view"
"""
    igor_dir, result = run_system_shell(tmp_path, script.replace("__MISMATCH_AFTER__", str(mismatch_after)), timeout=240)
    assert result.returncode == 0, result.stdout + result.stderr
    service = ConfigurationService(igor_dir / "data", schemas=[("system", load_schema(igor_dir / "modules/system"))])
    assert service.inspect(SETTING, TARGET)["desired"] == {"status": "value", "value": 220}
    inspection = json.loads(next(line.removeprefix("INSPECTION=") for line in result.stdout.splitlines()
                                 if line.startswith("INSPECTION=")))
    assert inspection["runtime_consumption"]["value"] == 220
    assert inspection["runtime_consumption"]["matches_desired"] is True
    rows = service.history.recent()
    failed = next(row for row in rows if row["capability"]["id"] == failed_capability)
    assert failed["outcome"] == failure_outcome
    assert failed["verification"]["status"] == "failed"
    if mismatch_after == 0:
        assert not any(row["capability"]["id"] == "system.memory.warning.readback" for row in rows)
    else:
        assert any(row["capability"]["id"] == "system.memory.warning.apply"
                   and row["outcome"] == "success" for row in rows)


def test_failed_application_stays_visible_until_explicit_same_path_recovery(tmp_path):
    igor_dir, result = run_system_shell(tmp_path, r'''
    source "$IGOR_DIR/core/lib/module_loader.sh"
    source "$IGOR_DIR/core/ai/core.sh"
_ml_log() { :; }
igor_load_all_modules >/dev/null
ai_mode=executive
eval "$(declare -f _igor_configuration_memory_warning_apply | sed '1s/_igor_configuration_memory_warning_apply/_igor_configuration_memory_warning_apply_original/')"
_igor_configuration_memory_warning_apply() { return 23; }
if _ai_configuration_memory_warning_set 230; then exit 4; fi
failed_view="$(_igor_configuration_call inspect '{"id":"system.memory.warning_threshold_mib","target":"module:system"}')"
printf 'AFTER_FAILURE=%s\n' "$failed_view"
eval "$(declare -f _igor_configuration_memory_warning_apply_original | sed '1s/_igor_configuration_memory_warning_apply_original/_igor_configuration_memory_warning_apply/')"
unset -f _igor_configuration_memory_warning_apply_original
_ai_configuration_memory_warning_set 150 || exit 5
recovered_view="$(_igor_configuration_call inspect '{"id":"system.memory.warning_threshold_mib","target":"module:system"}')"
printf 'AFTER_RECOVERY=%s\n' "$recovered_view"
''', timeout=240)
    assert result.returncode == 0, result.stdout + result.stderr
    after_failure = json.loads(next(line.removeprefix("AFTER_FAILURE=") for line in result.stdout.splitlines()
                                    if line.startswith("AFTER_FAILURE=")))
    assert after_failure["desired"] == {"status": "value", "value": 230}
    assert after_failure["runtime_consumption"]["value"] == 150
    assert after_failure["runtime_consumption"]["matches_desired"] is False
    after_recovery = json.loads(next(line.removeprefix("AFTER_RECOVERY=") for line in result.stdout.splitlines()
                                     if line.startswith("AFTER_RECOVERY=")))
    assert after_recovery["desired"] == {"status": "value", "value": 150}
    assert after_recovery["runtime_consumption"]["value"] == 150
    assert after_recovery["runtime_consumption"]["matches_desired"] is True
    service = ConfigurationService(igor_dir / "data", schemas=[("system", load_schema(igor_dir / "modules/system"))])
    rows = service.history.recent()
    failed = [row for row in rows if row["capability"]["id"] == "system.memory.warning.apply"
              and row["outcome"] != "success"]
    recovered = [row for row in rows if row["capability"]["id"] == "system.memory.warning.apply"
                 and row["outcome"] == "success"]
    assert len(failed) == len(recovered) == 1
    assert any(row["capability"]["id"] == "system.memory.warning.readback"
               and row["outcome"] == "success" for row in rows)
    assert [row["capability"]["id"] for row in rows].count(
        "core.configuration.system_memory_warning.set") == 2
