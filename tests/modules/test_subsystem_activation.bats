#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_BACKUPS_DIR="$IGOR_DIR/data/backups"
    mkdir -p "$IGOR_DIR/config/variables" "$IGOR_DIR/data/backups" "$IGOR_DIR/fakebin"
}

teardown() {
    teardown_igor_tmpdir
}

@test "core backup does not probe Docker without an active capability" {
    cat > "$IGOR_DIR/fakebin/docker" <<'SCRIPT'
#!/bin/sh
touch "$IGOR_DIR/docker-was-called"
exit 1
SCRIPT
    chmod +x "$IGOR_DIR/fakebin/docker"
    export PATH="$IGOR_DIR/fakebin:/usr/bin:/bin"
    source "$REPO_DIR/core/recovery/config_backup.sh"
    step() { :; }
    ok() { :; }
    info() { :; }
    warn() { :; }
    fail() { :; }
    run config_backup_take activation-test
    [ "$status" -ne 0 ] || [ -n "$output" ]
    [ ! -e "$IGOR_DIR/docker-was-called" ]
}

@test "journal app discovery fails closed without module lifecycle state" {
    cat > "$IGOR_DIR/fakebin/curl" <<'SCRIPT'
#!/bin/sh
touch "$IGOR_DIR/curl-was-called"
exit 1
SCRIPT
    chmod +x "$IGOR_DIR/fakebin/curl"
    export PATH="$IGOR_DIR/fakebin:/usr/bin:/bin"
    source "$REPO_DIR/core/recovery/journal.sh"
    run journal_detect_app_changes
    [ "$status" -eq 0 ]
    [ ! -e "$IGOR_DIR/curl-was-called" ]
    [ ! -e "$IGOR_DIR/docker-was-called" ]
}

@test "disabled app recovery refuses direct module-specific operations" {
    source "$REPO_DIR/core/recovery/apps.sh"
    igor_has_module() { return 1; }
    run app_monitor_window app 1
    [ "$status" -eq 1 ]
    run app_risk_register_list
    [ "$status" -eq 1 ]
}
