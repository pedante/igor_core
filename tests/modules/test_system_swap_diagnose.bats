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

@test "phased Diagnose delegates swap classification and excludes it when System is disabled" {
    source "$REPO_DIR/core/diagnose/phases.sh"
    declare -A _DIAG=()
    declare -a _DIAG_RESULTS=()
    stub_ui
    _diag_log() { :; }
    dmesg() { return 1; }
    timedatectl() { return 1; }
    free() { printf 'Mem: 1000 1 999 0 0 999\n'; }
    # Legacy phases run without errexit; an OK display can return false.
    _diag_phase_1 false >/dev/null 2>&1 || return 1
    # vm.swappiness is a distinct legacy policy check, not swap usage health.
    python3 - "$(igor_health_inspect host.swap.health)" "${_DIAG_RESULTS[@]}" <<'PY'
import json,sys
check=json.loads(sys.argv[1])["host.swap.health"]
matches=[row for row in sys.argv[2:] if row.split("|")[1]==check["finding_code"]]
assert matches==[f'{check["status"]}|{check["finding_code"]}|{check["message"]}|phase1']
assert not any("|swap_none|" in row or "|swap_ok|" in row for row in sys.argv[2:])
PY
    _IGOR_MODULE_STATUS["system"]=disabled
    _DIAG_RESULTS=()
    _diag_phase_1 false >/dev/null 2>&1 || return 1
    [[ "${_DIAG_RESULTS[*]}" != *'|swap_not_configured|'* ]]
    [[ "${_DIAG_RESULTS[*]}" != *'|swap_high|'* ]]
    [[ "${_DIAG_RESULTS[*]}" != *'|swap_critical|'* ]]
    [[ "${_DIAG_RESULTS[*]}" != *'|swap|'* ]]
}
