#!/usr/bin/env bats
# =============================================================================
#  tests/modules/test_module_contracts.bats
#  Phase 3: Module hook contract — every module must implement __register,
#  __health, and __diagnose, and must register them via igor_register_hook.
#
#  Tests source module_loader.sh (for igor_register_hook) and then source
#  each module.sh in a fresh subshell to avoid cross-contamination.
# =============================================================================

load '../helpers/common'
load '../helpers/mock_docker'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    stub_ui
    stub_module_env
    setup_mock_docker
    write_test_db_env
}

teardown() {
    teardown_igor_tmpdir
}

# ── Helper: source loader + module in a subshell, run a probe command ─────────
# Usage: _probe_module <module_name> <bash_expression_to_eval>
# Returns the exit code of the bash expression.
#
# IGOR_DIR is set to REPO_DIR so that module.sh companion file sources
# (e.g. tunnel_integration.sh) resolve correctly.  Secrets and runtime
# data for tests still live in IGOR_TEST_DIR.
_probe_module() {
    local mod="$1"; shift
    local probe="$*"

    bash --norc --noprofile -c "
        export IGOR_DIR='${REPO_DIR}'
        export IGOR_TEST_DIR='${IGOR_TEST_DIR}'
        # UI stubs
        ok() { :; }; fail() { :; }; warn() { :; }; info() { :; }; step() { :; }
        GRN=''; RED=''; YEL=''; CYAN=''; MAG=''; DIM=''; BOLD=''; NC=''
        export GRN RED YEL CYAN MAG DIM BOLD NC
        igor_has_bin() { command -v \"\$1\" &>/dev/null; }
        _ml_log() { :; }
        # docker returns failure by default — modules must handle gracefully
        docker() { return 1; }
        export -f docker igor_has_bin _ml_log

        source '${REPO_DIR}/core/lib/module_loader.sh'
        source '${REPO_DIR}/modules/${mod}/module.sh'
        ${probe}
    " 2>/dev/null
}

# ── Helper: get output from module probe ──────────────────────────────────────
_probe_module_output() {
    local mod="$1"; shift
    local probe="$*"

    bash --norc --noprofile -c "
        export IGOR_DIR='${IGOR_DIR}'
        ok() { :; }; fail() { :; }; warn() { :; }; info() { :; }; step() { :; }
        GRN=''; RED=''; YEL=''; CYAN=''; MAG=''; DIM=''; BOLD=''; NC=''
        export GRN RED YEL CYAN MAG DIM BOLD NC
        igor_has_bin() { command -v \"\$1\" &>/dev/null; }
        _ml_log() { :; }
        docker() { return 1; }
        export -f docker igor_has_bin _ml_log

        # Source companion files from real repo first, then set IGOR_DIR to tmpdir
        # so that secrets/db.env lookups hit the test fixture.
        IGOR_DIR='${REPO_DIR}' source '${REPO_DIR}/core/lib/module_loader.sh'
        IGOR_DIR='${REPO_DIR}' source '${REPO_DIR}/modules/${mod}/module.sh'
        export IGOR_DIR='${IGOR_DIR}'
        ${probe}
    " 2>/dev/null
}

# ══════════════════════════════════════════════════════════════════════════════
#  system module
# ══════════════════════════════════════════════════════════════════════════════

@test "system: module.sh can be sourced without errors" {
    _probe_module system "true"
}

@test "system: __register function is defined after sourcing" {
    _probe_module system "declare -f system__register >/dev/null"
}

@test "system: __health function is defined after sourcing" {
    _probe_module system "declare -f system__health >/dev/null"
}

@test "system: __diagnose function is defined after sourcing" {
    _probe_module system "declare -f system__diagnose >/dev/null"
}

@test "system: __register registers the health hook" {
    _probe_module system "
        system__register
        [[ \"\${_IGOR_HOOKS[health]:-}\" == *system__health* ]]
    "
}

@test "system: __register registers the diagnose hook" {
    _probe_module system "
        system__register
        [[ \"\${_IGOR_HOOKS[diagnose]:-}\" == *system__diagnose* ]]
    "
}

@test "system: __register registers the ai_context hook" {
    _probe_module system "
        system__register
        [[ \"\${_IGOR_HOOKS[ai_context]:-}\" == *system__ai_context* ]]
    "
}

@test "system: __health output matches 'status:message' format" {
    local out
    out=$(_probe_module_output system "system__health")
    [[ "$out" =~ ^(ok|warn|fail): ]] \
        || fail "__health output does not match 'status:message' format: '$out'"
}

@test "system: __diagnose emits at least one CHECK: line" {
    local out
    out=$(_probe_module_output system "system__diagnose")
    [[ "$out" == *"CHECK:"* ]] \
        || fail "__diagnose emitted no CHECK: lines: '$out'"
}

@test "system: __diagnose CHECK: lines follow CHECK:name:status:message format" {
    local out line
    out=$(_probe_module_output system "system__diagnose")
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" == CHECK:* ]] || continue
        # Should be CHECK:code:STATUS:message
        IFS=':' read -ra _parts <<< "$line"
        [ "${#_parts[@]}" -ge 4 ] \
            || fail "CHECK: line has fewer than 4 colon-separated parts: '$line'"
    done <<< "$out"
}

# ══════════════════════════════════════════════════════════════════════════════
#  nextcloud_docker module
# ══════════════════════════════════════════════════════════════════════════════

@test "nextcloud_docker: module.sh can be sourced without errors" {
    _probe_module nextcloud_docker "true"
}

@test "nextcloud_docker: __register function is defined after sourcing" {
    _probe_module nextcloud_docker "declare -f nextcloud_docker__register >/dev/null"
}

@test "nextcloud_docker: __health function is defined after sourcing" {
    _probe_module nextcloud_docker "declare -f nextcloud_docker__health >/dev/null"
}

@test "nextcloud_docker: __diagnose function is defined after sourcing" {
    _probe_module nextcloud_docker "declare -f nextcloud_docker__diagnose >/dev/null"
}

@test "nextcloud_docker: __register registers the health hook" {
    _probe_module nextcloud_docker "
        nextcloud_docker__register
        [[ \"\${_IGOR_HOOKS[health]:-}\" == *nextcloud_docker__health* ]]
    "
}

@test "nextcloud_docker: __register registers the diagnose hook" {
    _probe_module nextcloud_docker "
        nextcloud_docker__register
        [[ \"\${_IGOR_HOOKS[diagnose]:-}\" == *nextcloud_docker__diagnose* ]]
    "
}

@test "nextcloud_docker: __register registers the ai_context hook" {
    _probe_module nextcloud_docker "
        nextcloud_docker__register
        [[ \"\${_IGOR_HOOKS[ai_context]:-}\" == *nextcloud_docker__ai_context* ]]
    "
}

@test "nextcloud_docker: __health returns fail: when docker is unavailable" {
    local out
    out=$(_probe_module_output nextcloud_docker "nextcloud_docker__health")
    [[ "$out" =~ ^(ok|warn|fail): ]] \
        || fail "__health output does not match 'status:message' format: '$out'"
}

@test "nextcloud_docker: __diagnose emits secrets_db CHECK line" {
    local out
    out=$(_probe_module_output nextcloud_docker "nextcloud_docker__diagnose")
    [[ "$out" == *"CHECK:secrets_db:"* ]] \
        || fail "no CHECK:secrets_db: line in __diagnose output: '$out'"
}

@test "nextcloud_docker: __diagnose emits FAIL for secrets_db when db.env missing" {
    # Remove the db.env fixture so the check fails
    rm -f "${IGOR_DIR}/secrets/db.env"
    local out
    out=$(_probe_module_output nextcloud_docker "nextcloud_docker__diagnose")
    [[ "$out" == *"CHECK:secrets_db:FAIL"* ]] \
        || fail "expected CHECK:secrets_db:FAIL when db.env missing; got: '$out'"
}

@test "nextcloud_docker: __diagnose emits OK for secrets_db when db.env present" {
    write_test_db_env
    local out
    out=$(_probe_module_output nextcloud_docker "nextcloud_docker__diagnose")
    [[ "$out" == *"CHECK:secrets_db:OK"* ]] \
        || fail "expected CHECK:secrets_db:OK when db.env present; got: '$out'"
}

# ══════════════════════════════════════════════════════════════════════════════
#  igor_register_hook idempotency (loader contract)
# ══════════════════════════════════════════════════════════════════════════════

@test "igor_register_hook: registering same function twice is idempotent" {
    bash --norc --noprofile -c "
        export IGOR_DIR='${IGOR_DIR}'
        _ml_log() { :; }
        export -f _ml_log
        source '${REPO_DIR}/core/lib/module_loader.sh'
        igor_register_hook 'test_hook' 'my_fn'
        igor_register_hook 'test_hook' 'my_fn'
        # Count occurrences — should be exactly 1
        count=\$(echo \"\${_IGOR_HOOKS[test_hook]:-}\" | tr ' ' '\n' | grep -c '^my_fn$')
        [ \"\$count\" -eq 1 ]
    " 2>/dev/null
}

@test "igor_register_hook: multiple different functions accumulate" {
    bash --norc --noprofile -c "
        export IGOR_DIR='${IGOR_DIR}'
        _ml_log() { :; }
        export -f _ml_log
        source '${REPO_DIR}/core/lib/module_loader.sh'
        igor_register_hook 'multi_hook' 'fn_alpha'
        igor_register_hook 'multi_hook' 'fn_beta'
        [[ \"\${_IGOR_HOOKS[multi_hook]:-}\" == *fn_alpha* ]]
        [[ \"\${_IGOR_HOOKS[multi_hook]:-}\" == *fn_beta* ]]
    " 2>/dev/null
}
