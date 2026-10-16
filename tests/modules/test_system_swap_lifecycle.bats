#!/usr/bin/env bats

load '../helpers/common'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config"
    cp -a "$REPO_DIR/modules/system" "$IGOR_DIR/modules/system"
    printf 'system=enabled\n' > "$IGOR_DIR/config/modules.conf"
    source "$REPO_DIR/core/lib/module_loader.sh"
    source "$REPO_DIR/core/lib/health_runner.sh"
    _ml_log() { :; }
    igor_load_all_modules >/dev/null
}

teardown() { teardown_igor_tmpdir; }

@test "runtime READ refuses disabled and stale proposals then recovers in a fresh enabled process" {
    proposal="$(igor_capability_prepare system.host.runtime.status '{}' system 3)"
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    export IGOR_CAPABILITY_APPROVED_DIGEST
    igor_module_set_enabled system disabled >/dev/null
    igor_v2_invoke() { printf 'executed\n' > "$IGOR_DIR/forbidden-handler"; return 1; }
    run igor_capability_execute "$proposal"
    [ "$status" -ne 0 ]
    [ ! -e "$IGOR_DIR/forbidden-handler" ]
    run igor_health_run_v2_check host.swap.health
    [ "$status" -ne 0 ]
    run igor_capability_prepare system.host.runtime.status '{}' system 3
    [ "$status" -ne 0 ]
    igor_module_set_enabled system enabled >/dev/null
    run bash -c '
        source "$1/core/lib/module_loader.sh"
        _ml_log() { :; }
        igor_load_all_modules >/dev/null
        source "$1/core/ai/safety.sh"
        ai_mode=assist
        ai_execute_tool '\''{"tool":"run_capability","id":"system.host.runtime.status","provider":"system","inputs":{},"capability_version":3}'\''
    ' _ "$REPO_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"success"'* ]]
    [[ "$output" == *'"observation_scope":"current_read"'* ]]
    [[ "$output" == *'"swap_health_status"'* ]]
    [ ! -e "$IGOR_DIR/forbidden-handler" ]
}
