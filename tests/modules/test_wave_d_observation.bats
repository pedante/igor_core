#!/usr/bin/env bats

setup() {
    IGOR_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export IGOR_DIR
}

@test "active system observer populates an Igor-owned typed fact without implicit query refresh" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        igor_load_all_modules >/dev/null
        igor_model_read host:local memory.available_bytes observed
        igor_observer_refresh host.memory
        igor_model_read host:local memory.available_bytes observed
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"not_observed"'* ]]
    [[ "$output" == *'"availability":"known"'* ]]
    [[ "$output" == *'"owner":"system"'* ]]
    [[ "$output" == *'"value_type":"integer"'* ]]
}

@test "Wave E memory capability crosses observer model result and context boundaries" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        source "$IGOR_DIR/core/ai/safety.sh"
        source "$IGOR_DIR/core/ai/context.sh"
        igor_load_all_modules >/dev/null
        ai_mode=assist
        ai_execute_tool '\''{"tool":"run_capability","id":"system.host.memory.refresh","inputs":{}}'\''
        igor_model_read host:local memory.available_bytes observed
        ai_context_inspect
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'"capability_id":"system.host.memory.refresh"'* ]]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    [[ "$output" == *'"availability":"known"'* ]]
    [[ "$output" == *'"kind":"system_fact"'* ]]
    [[ "$output" == *'"kind":"capability_metadata"'* ]]
}

@test "inactive owner cannot refresh and its last fact is not current" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        igor_load_all_modules >/dev/null
        igor_observer_refresh host.memory
        _IGOR_MODULE_STATUS[system]=disabled
        igor_observer_refresh host.memory && exit 2
        igor_model_read host:local memory.available_bytes observed
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"inactive"'* ]]
}

@test "failed refresh retains previous evidence as stale" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        igor_load_all_modules >/dev/null
        igor_observer_refresh host.memory
        igor_v2_invoke() { return 1; }
        igor_observer_refresh host.memory && exit 2
        igor_model_read host:local memory.available_bytes observed
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"stale"'* ]]
    [[ "$output" == *'"value":'* ]]
}

@test "malformed observer result never replaces the valid fact" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        igor_load_all_modules >/dev/null
        igor_observer_refresh host.memory
        igor_v2_invoke() { printf "%s\n" '\''{"status":"ok","result":{"object_id":"host:local","facts":[{"property":"memory.available_bytes","value":"wrong","evidence":[]}],"unavailable":[]}}'\''; }
        igor_observer_refresh host.memory && exit 2
        igor_model_read host:local memory.available_bytes observed
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"stale"'* ]]
    [[ "$output" == *'"value_type":"integer"'* ]]
}

@test "read-only CLI does not refresh and a new process rebuilds observed state" {
    run bash "$IGOR_DIR/igor.sh" --model fact host:local memory.available_bytes
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"not_observed"'* ]]
    run bash "$IGOR_DIR/igor.sh" --model refresh host.memory
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"known"'* ]]
    run bash "$IGOR_DIR/igor.sh" --model fact host:local memory.available_bytes
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"not_observed"'* ]]
}

@test "structured system memory check preserves 80 and 150 MiB boundaries" {
    run bash -c '
        source "$IGOR_DIR/modules/system/module.sh"
        for mib in 79 80 149 150; do
            printf "{\"api_version\":2,\"contribution_id\":\"host.memory.health\",\"input\":{\"facts\":{\"memory.available_bytes\":{\"availability\":\"known\",\"value\":%s,\"recorded_at\":\"now\"}}}}\n" "$((mib * 1024 * 1024))" | system__check_memory
        done
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"CRITICAL"'* ]]
    [[ "$output" == *'"status":"WARN"'* ]]
    [[ "$output" == *'"status":"OK"'* ]]
    [ "$(printf '%s\n' "$output" | grep -c '"status":"CRITICAL"')" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c '"status":"WARN"')" -eq 2 ]
    [ "$(printf '%s\n' "$output" | grep -c '"status":"OK"')" -eq 1 ]
}

@test "Diagnose projects one canonical RAM finding and retains health evidence" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        source "$IGOR_DIR/core/lib/diagnose_runner.sh"
        igor_load_all_modules >/dev/null
        igor_diagnose_collect | grep -E "^CHECK:(ram|ram_low|low_ram):"
        igor_health_inspect host.memory.health
    '
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -Ec '^CHECK:(ram|ram_low|low_ram):')" -eq 1 ]
    [[ "$output" == *'"used_facts"'* ]]
    [[ "$output" == *'"memory.available_bytes"'* ]]
}

@test "stale memory yields UNKNOWN and check text never invokes an action" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        source "$IGOR_DIR/core/lib/health_runner.sh"
        igor_load_all_modules >/dev/null
        igor_observer_refresh host.memory
        run_igor_action() { printf "ACTION_EXECUTED\n"; }
        igor_v2_invoke() { return 1; }
        igor_observer_refresh host.memory || true
        igor_health_run_v2_check host.memory.health
        igor_health_inspect host.memory.health
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"UNKNOWN"'* ]]
    [[ "$output" != *'ACTION_EXECUTED'* ]]
}

@test "AI memory context selects the model fact without probing free" {
    run bash -c '
        source "$IGOR_DIR/core/lib/helpers.sh"
        source "$IGOR_DIR/core/lib/module_loader.sh"
        source "$IGOR_DIR/core/ai/context.sh"
        igor_load_all_modules >/dev/null
        igor_observer_refresh host.memory
        IGOR_AI_CONTEXT_INTENT=memory
        free() { printf "Mem: 999999 0 0 0 0 999999\nSwap: 0 0 0\n"; }
        ping() { return 1; }
        ai_gather_context
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'CONTEXT_ENGINE_V1:'* ]]
    [[ "$output" == *'memory.available_bytes'* ]]
    [[ "$output" == *'"availability":"known"'* ]]
    [[ "$output" != *'RAM: 999999'* ]]
}

@test "bounded on-demand refresh reuses a fresh observation" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        igor_load_all_modules >/dev/null
        igor_observer_refresh host.memory
        igor_v2_invoke() { printf "unexpected_invoke\n"; return 1; }
        igor_observer_ensure_fresh host.memory host:local
        igor_model_read host:local memory.available_bytes observed
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *'unexpected_invoke'* ]]
    [[ "$output" == *'"availability":"known"'* ]]
}

@test "inactive owner cannot expose a previous health result as current" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        source "$IGOR_DIR/core/lib/health_runner.sh"
        igor_load_all_modules >/dev/null
        igor_health_run_v2_check host.memory.health >/dev/null
        _IGOR_MODULE_STATUS[system]=disabled
        igor_health_inspect host.memory.health
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'{}'* ]]
    [[ "$output" != *'"status":"OK"'* ]]
}
