#!/usr/bin/env bats

# Step 15B integration proof through the real canonical capability dispatcher.
load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    export _IGOR_LOADER_DIR="$REPO_DIR"
    export REPO_DIR
    mkdir -p "$IGOR_DIR/modules/fixture_service/contracts" "$IGOR_DIR/bin" \
        "$IGOR_DIR/runtime" "$IGOR_DIR/config"
    cp -a "$REPO_DIR/modules/system" "$IGOR_DIR/modules/system"
    export FIXTURE_STATE="$IGOR_DIR/runtime/service.state"
    export FIXTURE_TRACE="$IGOR_DIR/runtime/trace"
    export FIXTURE_PRE_EFFECT="$IGOR_DIR/runtime/pre-effect"
    printf 'active\n' > "$FIXTURE_STATE"
    : > "$FIXTURE_TRACE"

    cat > "$IGOR_DIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$FIXTURE_TRACE"
if [ "$1" = -n ] && [ "$2" = -v ]; then
    [ "${FIXTURE_SUDO_FAIL:-0}" = 0 ]
    exit $?
fi
[ "${FIXTURE_SUDO_FAIL:-0}" = 0 ] || exit 1
shift 2
exec "$@"
EOF
    cat > "$IGOR_DIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[ "$1" = restart ] && [ "$2" = igor-step15b-fixture.service ] || exit 2
source "$REPO_DIR/core/lib/operational_history.sh"
rows="$(igor_history_cli recent 10)" || exit 4
python3 - "$rows" "$FIXTURE_PRE_EFFECT" <<'PY' || exit 5
import json,sys
rows=json.loads(sys.argv[1])
episode=next((row for row in rows if row["capability"]["id"] == "system.service.restart"), None)
if not episode or episode["lifecycle"] != "running":
    raise SystemExit(1)
open(sys.argv[2], "w").write(json.dumps(episode))
PY
printf 'restart\n' >> "$FIXTURE_TRACE"
if [ "${FIXTURE_FAIL_EXEC:-0}" = 1 ]; then exit 9; fi
printf 'active\n' > "$FIXTURE_STATE"
if [ "${FIXTURE_FAIL_VERIFY:-0}" = 1 ]; then printf 'inactive\n' > "$FIXTURE_STATE"; fi
if [ "${FIXTURE_INTERRUPT:-0}" = 1 ]; then
    kill -KILL -- "-$(cat "$FIXTURE_DRIVER_PID")"
fi
EOF
    chmod 700 "$IGOR_DIR/bin/sudo" "$IGOR_DIR/bin/systemctl"
    export PATH="$IGOR_DIR/bin:$PATH"

    cat > "$IGOR_DIR/modules/fixture_service/module.conf" <<'EOF'
[module]
module_api=2
name=fixture_service
display_name=Step 15B fixture service
version=1.0.0
runtime=bash
entrypoint=module.sh
contracts=contracts/contract.json

[requirements]
required_modules=
optional_modules=
required_capabilities=
optional_capabilities=
platform_families=
required_bins=

[compat]
v1_hooks=false
EOF
    cat > "$IGOR_DIR/modules/fixture_service/contracts/contract.json" <<'EOF'
{"contract_version":1,"contributions":[{"kind":"capability","id":"system.service.restart","handler":"fixture_service__restart","capability_version":1,"description":"Restart an isolated test service.","inputs":{"properties":{"unit":{"type":"string","validator":"systemd_unit"}},"required":["unit"],"additionalProperties":false},"safety":{"tier":"CHANGE"},"privilege":"required","preconditions":[{"kind":"service_exists","input":"unit"}],"verification":{"kind":"service_state","input":"unit","equals":"active","required":true},"recovery":{"class":"best_effort"},"affects":[{"object":"service","input":"unit"}]}]}
EOF
    cat > "$IGOR_DIR/modules/fixture_service/module.sh" <<'EOF'
fixture_service__restart() { printf '%s\n' '{"status":"ok","result":{"fixture":true}}'; }
EOF
    printf 'system=enabled\nfixture_service=enabled\n' > "$IGOR_DIR/config/modules.conf"
    _ml_log() { :; }
    export -f _ml_log
    source "$REPO_DIR/core/lib/module_loader.sh"
    igor_load_all_modules >/dev/null
    svc_restart_argv() { printf 'systemctl restart %s' "$1"; }
    svc_query() { [ "$1" = igor-step15b-fixture.service ] || return 1; cat "$FIXTURE_STATE"; }
    export -f svc_restart_argv svc_query
    source "$REPO_DIR/core/ai/safety.sh"
    ai_unscrub_inbound() { printf '%s' "$1"; }
    _ai_validate_tool_call() { printf 'BLOCKED: false\n'; }
}

_run_approved_change() {
    printf 'y\n' | ai_execute_tool '{"tool":"run_capability","id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-step15b-fixture.service"}}'
}

@test "CHANGE history is durable before effect and separates provider completion from verification" {
    ai_mode=assist
    run _run_approved_change
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"success"'* ]]
    [ -s "$FIXTURE_PRE_EFFECT" ]
    python3 - "$FIXTURE_PRE_EFFECT" <<'PY'
import json,sys
row=json.load(open(sys.argv[1]))
assert row["lifecycle"] == "running"
assert row["execution_status"] == "running"
assert row["capability"] == {"id":"system.service.restart", "version":1}
assert row["provider"]["id"] == "fixture_service"
assert row["affected_objects"][0]["scope_id"] == row["scope_id"]
PY
    result="$(igor_history_cli recent 10)"
    python3 - "$result" <<'PY'
import json,sys
rows=json.loads(sys.argv[1])
row=next(x for x in rows if x["capability"]["id"] == "system.service.restart")
assert row["lifecycle"] == "terminal"
assert row["execution_status"] == "succeeded"
assert row["verification"]["status"] == "passed"
assert row["outcome"] == "success"
assert [item["state"] for item in row["transitions"]] == [
    "admitted", "authority", "running", "provider_complete", "terminal"
]
PY
    [ "$(grep -c '^restart$' "$FIXTURE_TRACE")" -eq 1 ]
}

@test "hot History transition invokes one Python service process" {
    local proposal operation real_python wrapper counter count
    proposal="$(igor_capability_prepare system.service.restart '{"unit":"igor-step15b-fixture.service"}' fixture_service 1)"
    operation="$(_igor_history_begin "$proposal" corr-process-budget assist)"
    real_python="$(command -v python3)"
    counter="$IGOR_DIR/runtime/history-python-count"
    wrapper="$IGOR_DIR/bin/python3"
    : > "$counter"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
printf '.\n' >> "$counter"
exec "$real_python" "\$@"
EOF
    chmod 700 "$wrapper"

    run _igor_history_update authority "$operation" approved authenticated
    [ "$status" -eq 0 ]
    count="$(wc -l < "$counter")"
    [ "$count" -eq 1 ]
}

@test "direct capability execution retains one pre-effect authority transition" {
    local proposal digest recent
    proposal="$(igor_capability_prepare system.service.restart '{"unit":"igor-step15b-fixture.service"}' fixture_service 1)"
    digest="$(_igor_capability_field "$proposal" digest)"
    IGOR_CAPABILITY_APPROVED_DIGEST="$digest"
    IGOR_CAPABILITY_APPROVAL_STATUS=approved
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS

    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    recent="$(igor_history_cli recent 1)"
    python3 - "$recent" <<'PY'
import json,sys
row=json.loads(sys.argv[1])[0]
assert [item["state"] for item in row["transitions"]] == [
    "admitted", "authority", "running", "provider_complete", "terminal"
]
assert row["approval"]["result"] == "approved"
assert row["privilege"]["result"] == "authenticated"
PY
}

@test "provider failure and failed verification are distinct durable terminal outcomes" {
    ai_mode=executive
    export FIXTURE_FAIL_EXEC=1
    run ai_execute_tool '{"tool":"run_capability","id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-step15b-fixture.service"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"failed"'* ]]
    failed="$(igor_history_cli recent 1)"
    python3 - "$failed" <<'PY'
import json,sys
row=json.loads(sys.argv[1])[0]
assert row["execution_status"] == "failed"
assert row["verification"]["status"] == "not_applicable"
assert row["outcome"] == "failed"
PY

    unset FIXTURE_FAIL_EXEC
    export FIXTURE_FAIL_VERIFY=1
    printf 'active\n' > "$FIXTURE_STATE"
    run _run_approved_change
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"unverified_change"'* ]]
    unverified="$(igor_history_cli recent 1)"
    python3 - "$unverified" <<'PY'
import json,sys
row=json.loads(sys.argv[1])[0]
assert row["execution_status"] == "succeeded"
assert row["verification"]["status"] == "failed"
assert row["outcome"] == "unverified_change"
PY
}

@test "declined approval and failed sudo authentication never reach provider" {
    ai_mode=assist
    _declined() {
        printf 'n\n' | ai_execute_tool '{"tool":"run_capability","id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-step15b-fixture.service"}}'
    }
    run _declined
    [ "$status" -eq 0 ]
    [[ "$output" == *'"approval_status":"denied"'* ]]
    [ "$(igor_history_cli recent 1 | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["execution_status"])')" = not_executed ]
    [ ! -e "$FIXTURE_PRE_EFFECT" ]
    [ ! -s "$FIXTURE_TRACE" ]

    export FIXTURE_SUDO_FAIL=1
    run _run_approved_change
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"privilege_failed"'* ]]
    [ "$(igor_history_cli recent 1 | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["privilege"]["result"])')" = failed ]
    [ ! -e "$FIXTURE_PRE_EFFECT" ]
    [ "$(grep -c '^restart$' "$FIXTURE_TRACE" || true)" -eq 0 ]
}

@test "real system memory READ is durable and inspectable after service reopen" {
    ai_mode=assist
    run ai_execute_tool '{"tool":"run_capability","id":"system.host.memory.refresh","provider":"system","inputs":{}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    result="$(igor_history_cli recent 1)"
    operation_id="$(printf '%s' "$result" | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["operation_id"])')"
    correlation="$(igor_history_cli inspect "$operation_id" | python3 -c 'import json,sys;print(json.load(sys.stdin)["correlation_id"])')"
    inspect="$(igor_history_cli inspect "$operation_id")"
    correlation_rows="$(igor_history_cli correlation "$correlation")"
    python3 - "$inspect" "$correlation_rows" <<'PY'
import json,sys
row=json.loads(sys.argv[1])
matches=json.loads(sys.argv[2])
assert row["lifecycle"] == "terminal"
assert row["capability"] == {"id":"system.host.memory.refresh", "version":2}
assert row["provider"]["id"] == "system"
assert row["affected_objects"] == [{"scope_id":row["scope_id"], "object_id":"host:local"}]
assert row["execution_status"] == "succeeded"
assert row["verification"]["status"] == "passed"
assert row["outcome"] == "success"
assert row["provenance"]["interface"] == "ai_dispatcher"
assert matches[0]["operation_id"] == row["operation_id"]
PY
}

_interrupt_change() {
    export FIXTURE_INTERRUPT=1 FIXTURE_DRIVER_PID="$IGOR_DIR/runtime/driver.pid"
    printf 'inactive\n' > "$FIXTURE_STATE"
    cat > "$IGOR_DIR/runtime/crash-driver.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$FIXTURE_DRIVER_PID"
source "$REPO_DIR/core/lib/module_loader.sh"
igor_load_all_modules >/dev/null
source "$REPO_DIR/core/ai/safety.sh"
_ai_validate_tool_call() { printf 'BLOCKED: false\n'; }
ai_mode=executive
ai_execute_tool '{"tool":"run_capability","id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-step15b-fixture.service"}}' >/dev/null
EOF
    python3 - "$IGOR_DIR/runtime/crash-driver.sh" <<'PY'
import subprocess, sys
result = subprocess.run(["bash", sys.argv[1]], start_new_session=True,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=45)
assert result.returncode == -9, result.returncode
PY
}

@test "real interrupted CHANGE survives reopen and verifier reconciliation never repeats its effect" {
    _interrupt_change
    [ "$(cat "$FIXTURE_STATE")" = active ]
    [ "$(grep -c '^restart$' "$FIXTURE_TRACE")" -eq 1 ]
    episode="$(igor_history_cli recent 1)"
    operation_id="$(printf '%s' "$episode" | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["operation_id"])')"
    printf '%s' "$episode" | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; assert r["outcome"]=="interrupted_unknown" and r["execution_status"]=="unknown"'
    before="$(cat "$FIXTURE_TRACE")"
    run igor_history_recover "$operation_id"
    [ "$status" -eq 0 ]
    recovered="$(igor_history_cli inspect "$operation_id")"
    printf '%s' "$recovered" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["outcome"]=="interrupted_unknown" and r["execution_status"]=="unknown"; assert r["verification"]["reconciliation"]["status"]=="passed"'
    [ "$(cat "$FIXTURE_TRACE")" = "$before" ]
    run igor_history_recover "$operation_id"
    [ "$status" -eq 0 ]
    [ "$(cat "$FIXTURE_TRACE")" = "$before" ]
}

@test "unavailable interrupted provider retains uncertainty and requires operator recovery" {
    _interrupt_change
    _IGOR_MODULE_STATE[fixture_service]=disabled
    before="$(cat "$FIXTURE_TRACE")"
    run igor_history_recover
    [ "$status" -eq 0 ]
    igor_history_cli recent 1 | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; assert r["outcome"]=="interrupted_unknown"; assert r["verification"]["reconciliation"]["status"]=="unavailable"'
    [ "$(cat "$FIXTURE_TRACE")" = "$before" ]
}

@test "history corruption blocks CHANGE before authentication or provider effect" {
    mkdir -m 700 -p "$IGOR_DATA_DIR/operational_history"
    printf 'corrupt\n' > "$IGOR_DATA_DIR/operational_history/store.sqlite3"
    chmod 600 "$IGOR_DATA_DIR/operational_history/store.sqlite3"
    ai_mode=executive
    run ai_execute_tool '{"tool":"run_capability","id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-step15b-fixture.service"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *'capability not admitted'* ]]
    [ ! -s "$FIXTURE_TRACE" ]
    [ "$(cat "$IGOR_DATA_DIR/operational_history/store.sqlite3")" = corrupt ]
}

@test "history persistence failure after effect preserves canonical result and transient event" {
    original="$(declare -f _igor_history_update)"
    eval "${original/_igor_history_update /_fixture_history_update }"
    _igor_history_update() {
        case "$1" in provider-complete|finish) return 1 ;; esac
        _fixture_history_update "$@"
    }
    ai_mode=executive
    run ai_execute_tool '{"tool":"run_capability","id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-step15b-fixture.service"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"success"'* ]]
    [ "$(grep -c '^restart$' "$FIXTURE_TRACE")" -eq 1 ]
    igor_domain_event_recent | python3 -c 'import json,sys; r=json.load(sys.stdin); assert len(r)==1 and r[0]["payload"]["outcome"]=="success"'
    [[ "$(cat "$IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE")" == *'canonical result retained'* ]]
}

@test "canonical operations suppress legacy journal duplication while raw tools retain it" {
    export FIXTURE_JOURNAL="$IGOR_DIR/runtime/legacy-journal"
    journal_record() { printf '%s\n' "$*" >> "$FIXTURE_JOURNAL"; }
    ai_mode=assist
    run ai_execute_tool '{"tool":"run_capability","id":"system.host.memory.refresh","inputs":{}}'
    [ "$status" -eq 0 ]
    [ ! -e "$FIXTURE_JOURNAL" ]
    run ai_execute_tool '{"tool":"host","cmd":"whoami"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'TOOL:host EXIT:0'* ]] || { printf '%s\n' "$output" >&3; return 1; }
    [ -s "$FIXTURE_JOURNAL" ]
}

@test "headless history inspection has no provider refresh or persistence side effects" {
    run env IGOR_DATA_DIR="$IGOR_DIR/uncreated" bash "$REPO_DIR/igor.sh" --history status
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"not_created"'* ]]
    [ ! -e "$IGOR_DIR/uncreated" ]
    ai_mode=assist
    ai_execute_tool '{"tool":"run_capability","id":"system.host.memory.refresh","inputs":{}}' >/dev/null
    operation_id="$(igor_history_cli recent 1 | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["operation_id"])')"
    before="$(sha256sum "$IGOR_DATA_DIR/operational_history/store.sqlite3")"
    run env IGOR_DATA_DIR="$IGOR_DATA_DIR" bash "$REPO_DIR/igor.sh" --history inspect "$operation_id"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"success"'* ]]
    [ "$(sha256sum "$IGOR_DATA_DIR/operational_history/store.sqlite3")" = "$before" ]
    [ ! -s "$FIXTURE_TRACE" ]
}

@test "existing capability plans retain stable plan references in canonical history" {
    ai_mode=assist
    plan='{"plan_version":1,"intended_outcome":"inspect fixture memory","steps":[{"capability_id":"system.host.memory.refresh","provider":"system","inputs":{}}]}'
    resolved="$(igor_capability_plan_resolve "$plan")"
    digest="$(_igor_capability_field "$resolved" digest)"
    run igor_capability_plan_execute "$resolved"
    [ "$status" -eq 0 ]
    igor_history_cli recent 1 | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; assert r["references"]["plan_digest"]==sys.argv[1]; assert r["references"]["plan_step"]=="system.host.memory.refresh"; assert r["provenance"]["interface"]=="capability_plan"; assert r["outcome"]=="success"' "$digest"
}

teardown() { teardown_igor_tmpdir; }
