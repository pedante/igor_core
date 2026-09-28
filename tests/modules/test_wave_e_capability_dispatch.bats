#!/usr/bin/env bats

# Step 11 vertical proof. The fixture is an isolated file-backed service; the
# reviewed capability adapter supplies the exact sudo argv and the test's fake
# sudo/systemctl pair records it without touching a host service.
load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    mkdir -p "$IGOR_DIR/modules/fixture_service/contracts" "$IGOR_DIR/config" "$IGOR_DIR/runtime" "$IGOR_DIR/bin"
    export FIXTURE_STATE="$IGOR_DIR/runtime/service.state"
    export FIXTURE_ARGV="$IGOR_DIR/runtime/argv"
    export FIXTURE_TRACE="$IGOR_DIR/runtime/trace"
    printf 'active\n' > "$FIXTURE_STATE"
    : > "$FIXTURE_ARGV"
    : > "$FIXTURE_TRACE"

    cat > "$IGOR_DIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$FIXTURE_TRACE"
if [ "$1" = -n ] && [ "$2" = -v ]; then exit 0; fi
printf '%s\n' "$@" > "$FIXTURE_ARGV"
shift 2 # -n --
exec "$@"
EOF
    cat > "$IGOR_DIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[ "$1" = restart ] && [ "$2" = igor-wave-e-fixture.service ] || exit 2
printf 'active\n' > "$FIXTURE_STATE"
if [ "${FIXTURE_FAIL_VERIFY:-0}" = 1 ]; then
    printf 'inactive\n' > "$FIXTURE_STATE"
fi
EOF
    chmod 700 "$IGOR_DIR/bin/sudo" "$IGOR_DIR/bin/systemctl"
    export PATH="$IGOR_DIR/bin:$PATH"

    cat > "$IGOR_DIR/modules/fixture_service/module.conf" <<'EOF'
[module]
module_api=2
name=fixture_service
display_name=Wave E fixture service
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
{"contract_version":1,"contributions":[{"kind":"capability","id":"system.service.restart","handler":"fixture_service__restart","capability_version":1,"description":"Restart the isolated fixture service.","inputs":{"properties":{"unit":{"type":"string","validator":"systemd_unit"}},"required":["unit"],"additionalProperties":false},"safety":{"tier":"CHANGE"},"privilege":"required","preconditions":[{"kind":"service_exists","input":"unit"}],"verification":{"kind":"service_state","input":"unit","equals":"active","required":true},"recovery":{"class":"best_effort"},"affects":[{"object":"service","input":"unit"}]}]}
EOF
    # The privileged Core adapter owns the exact argv, so this handler is only
    # a marker and cannot substitute a command after approval.
    cat > "$IGOR_DIR/modules/fixture_service/module.sh" <<'EOF'
fixture_service__restart() {
    printf '%s\n' '{"status":"ok","result":{"fixture":"handler reached"}}'
}
EOF
    printf 'fixture_service=enabled\n' > "$IGOR_DIR/config/modules.conf"
    _ml_log() { :; }
    export -f _ml_log
    source "$REPO_DIR/core/lib/module_loader.sh"
    igor_load_all_modules >/dev/null
    # Capability execution sources these helpers through the loader, but keep
    # the fake query authoritative for the fixture's deterministic checks.
    svc_restart_argv() { printf 'systemctl restart %s' "$1"; }
    svc_query() { [ "$1" = igor-wave-e-fixture.service ] || return 1; cat "$FIXTURE_STATE"; }
    export -f svc_restart_argv svc_query
    source "$REPO_DIR/core/ai/safety.sh"
    _ai_validate_tool_call() { printf 'BLOCKED: false\n'; }
}

@test "Assist approval and existing PTY gate precede exact CHANGE execution" {
    ai_mode=assist
    _approved_fixture() {
        printf 'y\n' | ai_execute_tool '{"tool":"run_capability","id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-wave-e-fixture.service"}}'
    }
    run _approved_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *'"execution_status":"succeeded"'* ]]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    [ "$(sed -n '1p' "$FIXTURE_TRACE")" = 'sudo -n -v' ]
    [ "$(sed -n '2p' "$FIXTURE_TRACE")" = 'sudo -n -- systemctl restart igor-wave-e-fixture.service' ]
}

@test "declined CHANGE never authenticates or executes" {
    ai_mode=assist
    _declined_fixture() {
        printf 'n\n' | ai_execute_tool '{"tool":"run_capability","id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-wave-e-fixture.service"}}'
    }
    run _declined_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *'"approval_status":"denied"'* ]]
    [[ "$output" == *'"execution_status":"not_executed"'* ]]
    [ ! -s "$FIXTURE_TRACE" ]
}

@test "Executive may auto-approve structured CHANGE through the same privilege gate" {
    ai_mode=executive
    run ai_execute_tool '{"tool":"run_capability","id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-wave-e-fixture.service"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"approval_status":"auto_approved"'* ]]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    [ "$(sed -n '1p' "$FIXTURE_TRACE")" = 'sudo -n -v' ]
}

@test "failed deterministic precondition returns structured nonexecution before approval" {
    ai_mode=executive
    run ai_execute_tool '{"tool":"run_capability","id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"absent-fixture.service"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *'"precondition_status":"failed"'* ]]
    [[ "$output" == *'"execution_status":"not_executed"'* ]]
    [ ! -s "$FIXTURE_TRACE" ]
}

teardown() { teardown_igor_tmpdir; }

@test "canonical CHANGE fixture freezes exact privileged argv and verifies success" {
    run igor_capability_prepare system.service.restart '{"unit":"igor-wave-e-fixture.service"}' fixture_service
    [ "$status" -eq 0 ]
    proposal="$output"
    IGOR_CAPABILITY_APPROVED_DIGEST="$(printf '%s' "$proposal" | python3 -c 'import json,sys;print(json.load(sys.stdin)["digest"])')"
    export IGOR_CAPABILITY_APPROVED_DIGEST
    [[ "$proposal" == *'"privileged_argv":["sudo","-n","--","systemctl","restart","igor-wave-e-fixture.service"]'* ]]
    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    result="$output"
    [[ "$result" == *'"execution_status":"succeeded"'* ]]
    [[ "$result" == *'"verification_status":"passed"'* ]]
    [[ "$result" == *'"outcome":"success"'* ]]
    [ "$(paste -sd' ' "$FIXTURE_ARGV" | sed 's/[[:space:]]*$//')" = '-n -- systemctl restart igor-wave-e-fixture.service' ]
    operation_id="$(printf '%s' "$result" | python3 -c 'import json,sys;print(json.load(sys.stdin)["operation_id"])')"
    trace_before="$(wc -l < "$FIXTURE_TRACE")"
    run igor_capability_result "$operation_id"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    [ "$(wc -l < "$FIXTURE_TRACE")" -eq "$trace_before" ]
}

@test "canonical CHANGE fixture reports unverified_change after execution succeeds but verification fails" {
    export FIXTURE_FAIL_VERIFY=1
    run igor_capability_prepare system.service.restart '{"unit":"igor-wave-e-fixture.service"}' fixture_service
    [ "$status" -eq 0 ]
    proposal="$output"
    IGOR_CAPABILITY_APPROVED_DIGEST="$(printf '%s' "$proposal" | python3 -c 'import json,sys;print(json.load(sys.stdin)["digest"])')"
    export IGOR_CAPABILITY_APPROVED_DIGEST
    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    result="$output"
    [[ "$result" == *'"execution_status":"succeeded"'* ]]
    [[ "$result" == *'"verification_status":"failed"'* ]]
    [[ "$result" == *'"outcome":"unverified_change"'* ]]
    events="$(igor_domain_event_recent)"
    [ "$(printf '%s' "$events" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" -eq 1 ]
    [[ "$events" == *'"execution_status":"succeeded"'* ]]
    [[ "$events" == *'"verification_status":"failed"'* ]]
    [[ "$events" == *'"outcome":"unverified_change"'* ]]
}

@test "subscriber failure leaves committed result and later delivery intact" {
    export FIXTURE_FAIL_VERIFY=1
    failed_subscriber() { printf 'subscriber noise\n'; return 1; }
    later_subscriber() { printf '%s\n' "$1" > "$IGOR_DIR/runtime/later-event"; }
    igor_domain_event_subscribe failed_subscriber
    igor_domain_event_subscribe later_subscriber
    proposal="$(igor_capability_prepare system.service.restart '{"unit":"igor-wave-e-fixture.service"}' fixture_service)"
    IGOR_CAPABILITY_APPROVED_DIGEST="$(printf '%s' "$proposal" | python3 -c 'import json,sys;print(json.load(sys.stdin)["digest"])')"
    export IGOR_CAPABILITY_APPROVED_DIGEST
    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"unverified_change"'* ]]
    printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)' || return 1
    [[ "$(cat "$IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE")" == *'subscriber failed'* ]]
    [ -s "$IGOR_DIR/runtime/later-event" ]
    [ "$(wc -l < "$IGOR_CAPABILITY_RESULT_FILE")" -eq 1 ]
    [ "$(wc -l < "$IGOR_DOMAIN_EVENT_FILE")" -eq 1 ]
}

@test "AI dispatcher treats failed postcondition as unsuccessful tool outcome" {
    export FIXTURE_FAIL_VERIFY=1
    ai_mode=assist
    _unverified_fixture() {
        printf 'y\n' | ai_execute_tool '{"tool":"run_capability","id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-wave-e-fixture.service"}}'
    }
    run _unverified_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *'TOOL:run_capability EXIT:1'* ]]
    [[ "$output" == *'"outcome":"unverified_change"'* ]]
}

@test "canonical CHANGE fixture rejects invalid unit before privilege execution" {
    run igor_capability_prepare system.service.restart '{"unit":"bad name; reboot"}' fixture_service
    [ "$status" -ne 0 ]
    [ ! -s "$FIXTURE_ARGV" ]
}

@test "validated arguments cannot be replaced after approval" {
    proposal="$(igor_capability_prepare system.service.restart '{"unit":"igor-wave-e-fixture.service"}' fixture_service)"
    IGOR_CAPABILITY_APPROVED_DIGEST="$(printf '%s' "$proposal" | python3 -c 'import json,sys;print(json.load(sys.stdin)["digest"])')"
    export IGOR_CAPABILITY_APPROVED_DIGEST
    tampered="$(printf '%s' "$proposal" | python3 -c 'import json,sys; p=json.load(sys.stdin); p["inputs"]["unit"]="other.service"; print(json.dumps(p))')"
    run igor_capability_execute "$tampered"
    [ "$status" -ne 0 ]
    [ ! -s "$FIXTURE_TRACE" ]
    [ "$(igor_domain_event_recent)" = '[]' ]
}

@test "precondition is rechecked immediately before execution" {
    proposal="$(igor_capability_prepare system.service.restart '{"unit":"igor-wave-e-fixture.service"}' fixture_service)"
    IGOR_CAPABILITY_APPROVED_DIGEST="$(printf '%s' "$proposal" | python3 -c 'import json,sys;print(json.load(sys.stdin)["digest"])')"
    export IGOR_CAPABILITY_APPROVED_DIGEST
    svc_query() { return 1; }
    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"precondition_failed"'* ]]
    [[ "$output" == *'"execution_status":"not_executed"'* ]]
    [ ! -s "$FIXTURE_TRACE" ]
}

@test "plan inspection is read-only and execution stops after failed verification" {
    plan='{"plan_version":1,"intended_outcome":"fixture active","steps":[{"capability_id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-wave-e-fixture.service"}},{"capability_id":"system.service.restart","provider":"fixture_service","inputs":{"unit":"igor-wave-e-fixture.service"}}]}'
    run igor_capability_plan_resolve "$plan"
    [ "$status" -eq 0 ]
    resolved="$output"
    [[ "$resolved" == *'"digest"'* ]]
    [[ "$resolved" == *'"privilege":"required"'* ]]
    [ ! -s "$FIXTURE_TRACE" ]
    export FIXTURE_FAIL_VERIFY=1
    ai_mode=assist
    _execute_plan() { printf 'y\n' | igor_capability_plan_execute "$resolved"; }
    run _execute_plan
    [ "$status" -ne 0 ]
    [[ "$output" == *'"outcome":"unverified_change"'* ]]
    [[ "$output" == *'"completed_steps":[{"capability_id":"system.service.restart"'* ]]
    [[ "$output" == *'"stopped_reason":"unverified_change"'* ]]
    [ "$(wc -l < "$FIXTURE_TRACE")" -eq 2 ]
}
