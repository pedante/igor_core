#!/usr/bin/env bats
# =============================================================================
#  tests/core/test_config.bats
#  Phase 2: Configuration functions — _igor_resolve_dir / _source_env_file
#
#  Also covers: correct data/ and config/ subdirectory prefixes that were
#  wrong in the legacy test_igor_core.sh (now fixed).
# =============================================================================

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir

    # Source helpers.sh for _igor_resolve_dir (no side effects on source)
    # shellcheck source=/dev/null
    source "${REPO_DIR}/core/lib/helpers.sh"

    # Stub config.sh init functions BEFORE sourcing so side effects don't fire
    stub_config_init
    # shellcheck source=/dev/null
    source "${REPO_DIR}/core/lib/config.sh"
}

teardown() {
    teardown_igor_tmpdir
}

# ══════════════════════════════════════════════════════════════════════════════
#  _igor_resolve_dir — centralised runtime directory resolution
# ══════════════════════════════════════════════════════════════════════════════

@test "resolve_dir: runtime → data/runtime" {
    result=$(_igor_resolve_dir runtime)
    [ "$result" = "${IGOR_DIR}/data/runtime" ]
}

@test "resolve_dir: sessions → data/sessions" {
    result=$(_igor_resolve_dir sessions)
    [ "$result" = "${IGOR_DIR}/data/sessions" ]
}

@test "resolve_dir: alerts → data/alerts" {
    result=$(_igor_resolve_dir alerts)
    [ "$result" = "${IGOR_DIR}/data/alerts" ]
}

@test "resolve_dir: reports → data/reports" {
    result=$(_igor_resolve_dir reports)
    [ "$result" = "${IGOR_DIR}/data/reports" ]
}

@test "resolve_dir: backups → data/backups" {
    result=$(_igor_resolve_dir backups)
    [ "$result" = "${IGOR_DIR}/data/backups" ]
}

@test "resolve_dir: patterns → config/patterns" {
    result=$(_igor_resolve_dir patterns)
    [ "$result" = "${IGOR_DIR}/config/patterns" ]
}

@test "resolve_dir: knowledge → config/knowledge" {
    result=$(_igor_resolve_dir knowledge)
    [ "$result" = "${IGOR_DIR}/config/knowledge" ]
}

@test "resolve_dir: secrets → secrets (no data/ prefix)" {
    result=$(_igor_resolve_dir secrets)
    [ "$result" = "${IGOR_DIR}/secrets" ]
}

@test "resolve_dir: unknown key falls back to IGOR_DIR/key" {
    result=$(_igor_resolve_dir foobar)
    [ "$result" = "${IGOR_DIR}/foobar" ]
}

@test "resolve_dir: IGOR_RUNTIME_DIR override wins" {
    IGOR_RUNTIME_DIR="/tmp/test_override_runtime"
    result=$(_igor_resolve_dir runtime)
    [ "$result" = "/tmp/test_override_runtime" ]
    unset IGOR_RUNTIME_DIR
}

@test "resolve_dir: IGOR_SESSIONS_DIR override wins" {
    IGOR_SESSIONS_DIR="/tmp/test_override_sessions"
    result=$(_igor_resolve_dir sessions)
    [ "$result" = "/tmp/test_override_sessions" ]
    unset IGOR_SESSIONS_DIR
}

@test "resolve_dir: IGOR_PATTERNS_DIR override wins" {
    IGOR_PATTERNS_DIR="/tmp/test_override_patterns"
    result=$(_igor_resolve_dir patterns)
    [ "$result" = "/tmp/test_override_patterns" ]
    unset IGOR_PATTERNS_DIR
}

# ══════════════════════════════════════════════════════════════════════════════
#  _source_env_file — safe .env file loader
# ══════════════════════════════════════════════════════════════════════════════

@test "source_env_file: loads KEY=value correctly" {
    local env_file; env_file="${IGOR_TEST_DIR}/test.env"
    echo "TEST_VAR_ALPHA=hello123" > "$env_file"
    _source_env_file "$env_file"
    [ "${TEST_VAR_ALPHA:-}" = "hello123" ]
}

@test "source_env_file: loads value with spaces (unquoted)" {
    local env_file; env_file="${IGOR_TEST_DIR}/test.env"
    echo "TEST_VAR_SPACES=hello world" > "$env_file"
    _source_env_file "$env_file"
    [ "${TEST_VAR_SPACES:-}" = "hello world" ]
}

@test "source_env_file: strips double quotes from value" {
    local env_file; env_file="${IGOR_TEST_DIR}/test.env"
    echo 'TEST_VAR_DQ="quoted value"' > "$env_file"
    _source_env_file "$env_file"
    [ "${TEST_VAR_DQ:-}" = "quoted value" ]
}

@test "source_env_file: strips single quotes from value" {
    local env_file; env_file="${IGOR_TEST_DIR}/test.env"
    echo "TEST_VAR_SQ='single quoted'" > "$env_file"
    _source_env_file "$env_file"
    [ "${TEST_VAR_SQ:-}" = "single quoted" ]
}

@test "source_env_file: skips comment lines" {
    local env_file; env_file="${IGOR_TEST_DIR}/test.env"
    printf '# this is a comment\nTEST_VAR_NOCOMMENT=real_value\n' > "$env_file"
    _source_env_file "$env_file"
    # The comment itself should not become a variable named "# this is a comment"
    [ "${TEST_VAR_NOCOMMENT:-}" = "real_value" ]
}

@test "source_env_file: skips blank lines" {
    local env_file; env_file="${IGOR_TEST_DIR}/test.env"
    printf '\n\nTEST_VAR_BLANK=after_blanks\n\n' > "$env_file"
    _source_env_file "$env_file"
    [ "${TEST_VAR_BLANK:-}" = "after_blanks" ]
}

@test "source_env_file: skips lines without = sign" {
    local env_file; env_file="${IGOR_TEST_DIR}/test.env"
    printf 'NOT_AN_ASSIGNMENT\nTEST_VAR_AFTER=ok\n' > "$env_file"
    _source_env_file "$env_file"
    [ "${TEST_VAR_AFTER:-}" = "ok" ]
    # NOT_AN_ASSIGNMENT must not be set as empty-value var
}

@test "source_env_file: non-existent file returns 0 without error" {
    run _source_env_file "/no/such/file/exists.env"
    [ "$status" -eq 0 ]
}

@test "source_env_file: multiple vars in one file all loaded" {
    local env_file; env_file="${IGOR_TEST_DIR}/test.env"
    printf 'TEST_MULTI_A=alpha\nTEST_MULTI_B=beta\nTEST_MULTI_C=gamma\n' > "$env_file"
    _source_env_file "$env_file"
    [ "${TEST_MULTI_A:-}" = "alpha" ]
    [ "${TEST_MULTI_B:-}" = "beta" ]
    [ "${TEST_MULTI_C:-}" = "gamma" ]
}
