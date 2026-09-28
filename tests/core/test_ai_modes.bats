#!/usr/bin/env bats

load '../helpers/common'

setup() {
    setup_igor_tmpdir
    stub_ui
    source "${BATS_TEST_DIRNAME}/../../core/ai/safety.sh"
    source "${BATS_TEST_DIRNAME}/../../core/lib/input_validation.sh"
    ai_unscrub_inbound() { printf '%s' "$1"; }
    _ai_validate_tool_call() { echo 'BLOCKED: false'; }
    ai_knowledge_mark_changed() { :; }
    igor_has_capability() { [ "$1" = docker ] || [ "$1" = nextcloud ]; }
    export IGOR_QUIET_LOOP=true IGOR_VERBOSE=false ai_mode=assist executive_mode=false
    mkdir -p "$IGOR_DIR/bin"
    cat > "$IGOR_DIR/bin/docker" <<'EOF'
#!/bin/bash
printf 'mode-read\n'
EOF
    chmod +x "$IGOR_DIR/bin/docker"
    export PATH="$IGOR_DIR/bin:$PATH"
    cd "$IGOR_DIR" || return 1
}

teardown() {
    teardown_igor_tmpdir
}

run_mode_tool() {
    printf '%s\n' "$1" | ai_execute_tool '{"tool":"host","cmd":"docker ps"}'
}

run_input_tool() {
    printf '%s\n' "$1" | ai_execute_tool "$2"
}

install_version_probe_fixture() {
    local app="$1"
    cat > "$IGOR_DIR/bin/$app" <<'EOF'
#!/bin/bash
printf 'version probe ran\n' >> "$IGOR_DIR/probe-runs"
printf 'probe version 1.0\n'
EOF
    cat > "$IGOR_DIR/bin/pacman" <<'EOF'
#!/bin/bash
[ "$1" = -Q ] || exit 1
printf '%s 1.0\n' "$2"
EOF
    chmod +x "$IGOR_DIR/bin/$app" "$IGOR_DIR/bin/pacman"
}

@test "Guide READ waits, then Run executes through the dispatcher" {
    ai_mode=guide
    run run_mode_tool r
    [ "$status" -eq 0 ]
    [[ "$output" == *"mode-read"* ]]
    [[ "$output" == *"PROPOSED"* ]]
}

@test "Guide Skip records a declined result without execution" {
    ai_mode=guide
    run run_mode_tool s
    [ "$status" -eq 0 ]
    [[ "$output" == *"USER DECLINED"* ]]
    [[ "$output" != *"mode-read"* ]]
}

@test "Guide Explain returns to the same pending READ prompt" {
    ai_mode=guide
    _ai_explain_pending_approval() { printf 'read explanation\n'; return 0; }
    run run_mode_tool $'e\nr'
    [ "$status" -eq 0 ]
    [[ "$output" == *"read explanation"* ]]
    [[ "$output" == *"mode-read"* ]]
}

@test "Guide Stop cancels a proposed READ" {
    ai_mode=guide
    run run_mode_tool /stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"USER STOPPED"* ]]
    [[ "$output" != *"mode-read"* ]]
}

@test "Assist and Executive READ actions auto-run" {
    for ai_mode in assist executive; do
        run ai_execute_tool '{"tool":"host","cmd":"docker ps"}'
        [ "$status" -eq 0 ]
        [[ "$output" == *"mode-read"* ]]
    done
}

@test "Guide proposes a multi-READ version probe until Run" {
    install_version_probe_fixture vlc
    ai_mode=guide IGOR_QUIET_LOOP=false
    local request='{"tool":"host","cmd":"which vlc 2>/dev/null; vlc --version 2>/dev/null | head -1; pacman -Q vlc 2>/dev/null"}'
    run run_input_tool s "$request"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PROPOSED (read-only)"* ]]
    [[ "$output" != *"NEEDS APPROVAL"* ]]
    [ ! -e "$IGOR_DIR/probe-runs" ]
    run run_input_tool r "$request"
    [ "$status" -eq 0 ]
    [ -s "$IGOR_DIR/probe-runs" ]
}

@test "Assist auto-runs a multi-READ version probe without approval" {
    install_version_probe_fixture kdeconnect-cli
    ai_mode=assist IGOR_QUIET_LOOP=false
    run ai_execute_tool '{"tool":"host","cmd":"which kdeconnect-cli 2>/dev/null; kdeconnect-cli --version 2>/dev/null | head -1; pacman -Q kdeconnect 2>/dev/null"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-RUNNING (read-only)"* ]]
    [[ "$output" != *"NEEDS APPROVAL"* ]]
    [ -s "$IGOR_DIR/probe-runs" ]
}

@test "Executive auto-runs a multi-READ version probe without change warning" {
    install_version_probe_fixture dolphin
    ai_mode=executive IGOR_QUIET_LOOP=false
    run ai_execute_tool '{"tool":"host","cmd":"which dolphin 2>/dev/null; dolphin --version 2>/dev/null | head -1; pacman -Q dolphin 2>/dev/null"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-RUNNING (read-only)"* ]]
    [[ "$output" != *"NEEDS APPROVAL"* ]]
    [ -s "$IGOR_DIR/probe-runs" ]
}

@test "Assist CHANGE requires approval" {
    ai_mode=assist
    run run_input_tool s '{"tool":"host","cmd":"printf changed>MARKER"}'
    [ "$status" -eq 0 ]
    [ ! -e MARKER ]
    [[ "$output" == *"USER DECLINED"* ]]
}

@test "Executive structured CHANGE auto-runs while raw shell CHANGE requires approval" {
    ai_mode=executive IGOR_QUIET_LOOP=false
    run run_input_tool y '{"tool":"host","cmd":"printf changed>MARKER"}'
    [ "$status" -eq 0 ]
    [ "$(cat MARKER)" = changed ]
    [[ "$output" == *"explicit approval is required"* ]]
}

@test "DESTROY still requires exact YES in every mode" {
    for ai_mode in guide assist executive; do
        rm -f MARKER
        run run_input_tool yes '{"tool":"host","cmd":"rm -f MARKER"}'
        [ "$status" -eq 0 ]
        [ ! -e MARKER ]
        [[ "$output" == *"Type YES exactly"* ]]
        printf 'YES\n' | ai_execute_tool '{"tool":"host","cmd":"touch MARKER"}' >/dev/null
        run run_input_tool YES '{"tool":"host","cmd":"rm -f MARKER"}'
        [ "$status" -eq 0 ]
        [ ! -e MARKER ]
    done
}

@test "hard denials remain blocked in Executive mode" {
    ai_mode=executive
    run ai_execute_tool '{"tool":"host","cmd":"rm -rf /"}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCKED BY DENYLIST"* ]]
    [ ! -e MARKER ]
}

@test "policy denial remains authoritative in Executive mode" {
    ai_mode=executive
    ai_policy_tool_allowed() { [ "$1" != host ]; }
    run ai_execute_tool '{"tool":"host","cmd":"printf changed>MARKER"}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"not allowed by active AI policy"* ]]
    [ ! -e MARKER ]
}

@test "ai_get_mode maps legacy executive_mode only when ai_mode is unset" {
    unset ai_mode
    executive_mode=true
    [ "$(ai_get_mode)" = executive ]
    ai_mode=invalid
    [ "$(ai_get_mode)" = assist ]
}
