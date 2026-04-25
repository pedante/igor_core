#!/usr/bin/env bash
# =============================================================================
#  tests/helpers/common.bash
#  Shared BATS helpers: tmp dir management, fixtures, stubs.
#  Load with:  load '../helpers/common'   (from tests/core/ or tests/modules/)
#              load '../../helpers/common' (from tests/integration/)
# =============================================================================

# ── Tmpdir lifecycle ──────────────────────────────────────────────────────────
# Call in BATS setup() / teardown()
setup_igor_tmpdir() {
    IGOR_TEST_DIR="$(mktemp -d)"
    export IGOR_DIR="$IGOR_TEST_DIR"

    # Core directory skeleton expected by various subsystems
    mkdir -p \
        "$IGOR_DIR/secrets" \
        "$IGOR_DIR/config/patterns" \
        "$IGOR_DIR/config/knowledge" \
        "$IGOR_DIR/data/runtime" \
        "$IGOR_DIR/data/sessions" \
        "$IGOR_DIR/data/alerts" \
        "$IGOR_DIR/data/patterns" \
        "$IGOR_DIR/data/backups" \
        "$IGOR_DIR/data/reports"
}

teardown_igor_tmpdir() {
    [ -n "${IGOR_TEST_DIR:-}" ] && rm -rf "$IGOR_TEST_DIR"
    unset IGOR_TEST_DIR
}

# ── db.env fixture ─────────────────────────────────────────────────────────────
# Writes a secrets/db.env with known, fake values.
# PASSWORD is deliberately set to a string that must NEVER appear in SCRUB_FROM.
write_test_db_env() {
    cat > "$IGOR_DIR/secrets/db.env" << 'EOF'
NEXTCLOUD_TRUSTED_DOMAINS=localhost testcloud.example.com
NEXTCLOUD_ADMIN_USER=testadmin
NEXTCLOUD_ADMIN_PASSWORD=SHOULD_NEVER_APPEAR_IN_SCRUB_TABLE
POSTGRES_DB=testdb
POSTGRES_USER=testuser
POSTGRES_PASSWORD=SHOULD_NEVER_APPEAR_IN_SCRUB_TABLE
REDIS_HOST_PASSWORD=SHOULD_NEVER_APPEAR_IN_SCRUB_TABLE
EOF
}

# ── Config stubs ───────────────────────────────────────────────────────────────
# Define no-op stubs for config.sh auto-run functions so that sourcing it in
# tests doesn't trigger filesystem migrations or config validation warnings.
stub_config_init() {
    _detect_config_dir() { :; }
    _load_config()       { :; }
    _validate_config()   { :; }
}

# ── UI stubs ───────────────────────────────────────────────────────────────────
# Minimal stubs for ui.sh functions that safety.sh / modules may call.
stub_ui() {
    ok()   { :; }
    fail() { :; }
    warn() { :; }
    info() { :; }
    step() { :; }
    # Color vars used in printf strings — define as empty strings
    GRN=""; RED=""; YEL=""; CYAN=""; MAG=""; DIM=""; BOLD=""; NC=""
    export GRN RED YEL CYAN MAG DIM BOLD NC
}

# ── Module loader stubs ────────────────────────────────────────────────────────
# Stub functions that module.sh files call during register/source time.
stub_module_env() {
    # igor_has_bin — just check real PATH (acceptable in tests)
    igor_has_bin() { command -v "$1" &>/dev/null; }
    export -f igor_has_bin
    # Silence any _ml_log output in tests
    _ml_log() { :; }
    export -f _ml_log
}
