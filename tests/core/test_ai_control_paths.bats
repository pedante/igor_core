#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    # core.sh resolves its sibling sources through IGOR_DIR at load time.
    export IGOR_DIR="$REPO_DIR"
    source "${REPO_DIR}/core/ai/core.sh"
    # Keep the focused tests independent of the interactive UI and host state.
    warn() { printf '%s\n' "$*"; }
    header() { printf 'HEADER\n'; }
}

teardown() {
    teardown_igor_tmpdir
}

@test "local command router captures /cmd before ordinary model input" {
    run _ai_session_route "/cmd inspect boot warnings"
    [ "$status" -eq 0 ]
    [ "$output" = "/cmd inspect boot warnings" ]

    run _ai_session_route "/cmd"
    [ "$status" -eq 0 ]
    [[ "$output" == INVALID:* ]]

    run _ai_session_route "check warnings in boot logs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "isolated text requests cannot regain native tools during transport setup" {
    export IGOR_AI_ENABLED=true
    export IGOR_AI_TEXT_ONLY=true
    export IGOR_RUNTIME_DIR="$BATS_TEST_TMPDIR"
    run bash -c 'source "$IGOR_DIR/core/ai/api.sh"; _ai_prepare_transport; printf "tools=%s\n" "$NEXUS_TOOLS_JSON"'
    [ "$status" -eq 0 ]
    [ "$output" = "tools=[]" ]
}

@test "provider error marker is separate from assistant prose" {
    local reply="" tokens_in=0 tokens_out=0
    local -a commands=()
    _nexus_parse_result $'REPLY_START\nERROR: a log line, not transport failure\nREPLY_END' \
        reply commands tokens_in tokens_out
    [ "$IGOR_PROVIDER_ERROR" = false ]
    [ "$reply" = "ERROR: a log line, not transport failure" ]

    _nexus_parse_result $'REPLY_START\nERROR: HTTP 400\nREPLY_END\nPROVIDER_ERROR: true\nERROR_KIND: provider' \
        reply commands tokens_in tokens_out
    [ "$IGOR_PROVIDER_ERROR" = true ]
    [ "$IGOR_ERROR_KIND" = provider ]
}

@test "diagnostic burst fails closed without docker capability" {
    marker="${BATS_TEST_TMPDIR}/docker-called"
    docker() { : > "$marker"; }
    igor_has_capability() { return 1; }
    export -f docker igor_has_capability

    run _ai_diagnostic_burst "the service is broken"
    [ "$status" -eq 0 ]
    [ ! -e "$marker" ]
    [[ "$output" == *"no active module provides docker"* ]]
}

@test "canary uses the semantic dispatcher and rejects non-read commands" {
    marker="${BATS_TEST_TMPDIR}/canary-executed"
    ai_cmd_is_read() { [[ "$1" == "printf safe" ]]; }
    ai_execute_tool() {
        printf 'TOOL:host EXIT:0\n'
        printf '%s\n' "$1"
        : > "$marker"
    }
    export -f ai_cmd_is_read ai_execute_tool

    run _ai_run_canary_read "printf safe"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"tool": "host"'* ]]
    [ -e "$marker" ]

    rm -f "$marker"
    run _ai_run_canary_read "touch $marker"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CANARY REJECTED"* ]]
    [ ! -e "$marker" ]
}

@test "canary does not mistake delivered failure output for success" {
    ai_cmd_is_read() { return 0; }
    ai_execute_tool() { printf 'TOOL:host EXIT:7\nOUTPUT: failed\n'; return 0; }
    run _ai_run_canary_read "uname"
    [ "$status" -eq 7 ]
}

@test "disabled AI exits before prompting" {
    export IGOR_AI_ENABLED=false
    run menu_ai
    [ "$status" -eq 1 ]
    [[ "$output" == *"AI assistant is disabled"* ]]
    [[ "$output" != *"HEADER"* ]]
}

@test "undo dispatches edit through the semantic tool gate" {
    marker="${BATS_TEST_TMPDIR}/undo-dispatched"
    ai_execute_tool() {
        printf '%s\n' "$1"
        : > "$marker"
    }
    export -f ai_execute_tool
    entry='{"tool":"edit_file","manual_undo":false,"reverse":{"path":"safe.txt","find":"new","replace":"old"}}'

    run _ai_run_undo_entry "$entry"
    [ "$status" -eq 0 ]
    [ -e "$marker" ]
    [[ "$output" == *'"tool": "edit_file"'* ]]
}

@test "undo rejects unsupported reverse tools" {
    entry='{"tool":"host","manual_undo":false,"reverse":{"command":"touch /tmp/should-not-run"}}'
    run _ai_run_undo_entry "$entry"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No automatic reverse"* ]]
}

@test "scratchpad persistence is private and mode restricted" {
    export IGOR_DIR="$BATS_TEST_TMPDIR"
    mkdir -p "$IGOR_DIR/data"
    export SECRET_TOKEN="scratchpad-secret"
    run _ai_write_scratchpad '{"status":"investigating","note":"token=scratchpad-secret"}'
    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$IGOR_DIR/data/scratchpad.txt")" = 600 ]
    ! grep -q "scratchpad-secret" "$IGOR_DIR/data/scratchpad.txt"
}
