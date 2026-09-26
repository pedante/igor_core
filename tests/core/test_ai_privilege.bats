#!/usr/bin/env bats

load '../helpers/common'

setup() {
    setup_igor_tmpdir
    stub_ui
    source "${BATS_TEST_DIRNAME}/../../core/ai/events.sh"
    source "${BATS_TEST_DIRNAME}/../../core/ai/safety.sh"
    source "${BATS_TEST_DIRNAME}/../../core/lib/input_validation.sh"
    ai_unscrub_inbound() { printf '%s' "$1"; }
    ai_scrub_outbound() { printf '%s' "$1"; }
    _ai_validate_tool_call() { echo 'BLOCKED: false'; }
    ai_knowledge_mark_changed() { :; }
    ai_audit_tool() { printf '%s\n' "$*" >> "$IGOR_DIR/audit.log"; }
    export IGOR_AI_EVENT_STREAM="$IGOR_DIR/data/runtime/events.jsonl"
    export IGOR_QUIET_LOOP=true IGOR_VERBOSE=false ai_mode=assist executive_mode=false
    mkdir -p "$IGOR_DIR/bin"
    cat > "$IGOR_DIR/bin/sudo" <<'EOF'
#!/bin/bash
if [ "$1" = "-n" ] && [ "$2" = "-v" ]; then
    exit 0
fi
printf '%s\n' "$*" >> "$IGOR_DIR/sudo-argv"
"$@"
EOF
    chmod +x "$IGOR_DIR/bin/sudo"
    export PATH="$IGOR_DIR/bin:$PATH"
    cd "$IGOR_DIR" || return 1
}

teardown() {
    teardown_igor_tmpdir
}

run_sudo_tool() {
    printf '%s\n' "$1" | ai_execute_tool '{"tool":"host","cmd":"sudo touch exact-marker"}'
}

run_destroy_tool() {
    printf '%s\n' "$1" | ai_execute_tool '{"tool":"host","cmd":"sudo rm -f destroy-marker"}'
}

@test "approved sudo action remains exact and advertises authentication without secrets" {
    run run_sudo_tool 'y'
    [ "$status" -eq 0 ]
    [ -e "$IGOR_DIR/exact-marker" ]
    [ "$(cat "$IGOR_DIR/sudo-argv")" = "touch exact-marker" ]
    run cat "$IGOR_DIR/data/runtime/events.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"event_type":"action_proposed"'* ]]
    [[ "$output" == *'"requires_admin_auth":true'* ]]
    [[ "$output" != *password* ]]
    [[ "$output" != *SHOULD_NEVER_APPEAR* ]]
}

@test "executive mode does not bypass DESTROY exact confirmation" {
    ai_mode=executive
    run run_destroy_tool 'yes'
    [ "$status" -eq 0 ]
    [ ! -e "$IGOR_DIR/destroy-marker" ]
    [[ "$output" == *"Type YES exactly"* ]]
}

@test "sudo detection is metadata only and does not classify read commands" {
    run _ai_command_requires_admin 'printf sudo text'
    [ "$status" -ne 0 ]
    run _ai_command_requires_admin 'sudo pacman -S vlc'
    [ "$status" -eq 0 ]
}

@test "uncached sudo fails closed without a tty before backups or exact action" {
    cat > "$IGOR_DIR/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$IGOR_DIR/sudo-argv"
if [ "$1" = "-n" ] && [ "$2" = "-v" ]; then
    exit 1
fi
if [ "$1" = "-v" ]; then
    exit 1
fi
"$@"
EOF
    chmod +x "$IGOR_DIR/bin/sudo"
    config_backup_auto() { : > "$IGOR_DIR/backup-called"; }
    ai_mode=executive
    run ai_execute_tool '{"tool":"host","cmd":"sudo touch should-not-run"}'
    [ "$status" -eq 0 ]
    [ ! -e "$IGOR_DIR/should-not-run" ]
    [ ! -e "$IGOR_DIR/backup-called" ]
    [[ "$output" == *"ADMIN AUTHENTICATION FAILED"* ]]
    run cat "$IGOR_DIR/data/runtime/events.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"event_type":"privilege_result"'* ]]
    [[ "$output" == *'"status":"failed"'* ]]
    [[ "$output" != *SUPER_SECRET* ]]
    run cat "$IGOR_DIR/audit.log"
    [ "$status" -eq 0 ]
    [[ "$output" != *SUPER_SECRET* ]]
    ! grep -q 'touch should-not-run' "$IGOR_DIR/sudo-argv"
}
