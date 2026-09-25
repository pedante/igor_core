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

@test "aliases and malformed local commands share the registry route" {
    run _ai_session_route "q"
    [ "$output" = "exit" ]
    run _ai_session_route "wip clear"
    [ "$output" = "solved" ]
    run _ai_session_route "/diag storage"
    [ "$output" = "/diagnose storage" ]
    for input in "stats extra" "replay" "exec maybe" "hypo add" "/cmd"; do
        run _ai_session_route "$input"
        [ "$status" -eq 0 ]
        [[ "$output" == INVALID:* ]]
    done
}

@test "palette lists registry actions and selected commands use the typed route" {
    local selected
    selected=$(printf '1\n' | bash -c '
        source "$IGOR_DIR/core/ai/core.sh"
        _ai_command_palette stats
        printf "SELECTED:%s\n" "$_AI_PALETTE_SELECTION"
        _ai_session_route "$_AI_PALETTE_SELECTION"
    ')
    [[ "$selected" == *"stats"* ]]
    [[ "$selected" == *"SELECTED:stats"* ]]
    [ "${selected##*$'\n'}" = "stats" ]
}

@test "palette cancel and back leave no selected command" {
    for choice in b cancel; do
        local result
        result=$(printf '%s\n' "$choice" | bash -c '
            source "$IGOR_DIR/core/ai/core.sh"
            _ai_command_palette stats
            printf "RESULT:%s\n" "$_AI_PALETTE_SELECTION"
        ')
        [[ "$result" == *"RESULT:" ]]
    done
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

@test "disabled AI reports startup failure before prompting" {
    export IGOR_AI_ENABLED=false
    run menu_ai
    [ "$status" -eq 2 ]
    [[ "$output" == *"stage: configuration"* ]]
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

@test "runtime state is private, atomic, and does not follow a destination symlink" {
    export IGOR_DIR="$BATS_TEST_TMPDIR"
    export IGOR_RUNTIME_DIR="$IGOR_DIR/runtime"
    mkdir -p "$IGOR_RUNTIME_DIR"
    printf 'sentinel\n' > "$BATS_TEST_TMPDIR/redirected"
    ln -s "$BATS_TEST_TMPDIR/redirected" "$IGOR_RUNTIME_DIR/state.env"
    model='fixture-model' provider='fixture-provider' conversation='[]'
    _AI_SESSION_STATE='investigating'
    _ai_update_state
    [ "$(cat "$BATS_TEST_TMPDIR/redirected")" = "sentinel" ]
    [ ! -L "$IGOR_RUNTIME_DIR/state.env" ]
    [ "$(stat -c '%a' "$IGOR_RUNTIME_DIR/state.env")" = 600 ]
    grep -q '^AI_SESSION_ACTIVE=1$' "$IGOR_RUNTIME_DIR/state.env"
}

@test "clear session state replaces state atomically and keeps private mode" {
    export IGOR_DIR="$BATS_TEST_TMPDIR"
    export IGOR_RUNTIME_DIR="$IGOR_DIR/runtime"
    mkdir -p "$IGOR_RUNTIME_DIR"
    printf 'AI_SESSION_ACTIVE=1\nother=value\n' > "$IGOR_RUNTIME_DIR/state.env"
    chmod 600 "$IGOR_RUNTIME_DIR/state.env"
    _ai_clear_session_active
    grep -q '^AI_SESSION_ACTIVE=0$' "$IGOR_RUNTIME_DIR/state.env"
    grep -q '^other=value$' "$IGOR_RUNTIME_DIR/state.env"
    [ "$(stat -c '%a' "$IGOR_RUNTIME_DIR/state.env")" = 600 ]
}

@test "IPC and steering readers honor the configured runtime directory" {
    export IGOR_RUNTIME_DIR="$BATS_TEST_TMPDIR/custom-runtime"
    mkdir -p "$IGOR_RUNTIME_DIR"
    printf 'inspect service\n' > "$IGOR_RUNTIME_DIR/steering.txt"
    [ "$(_ai_read_steering)" = "inspect service" ]
    mkfifo "$IGOR_RUNTIME_DIR/commands.fifo"
    _ai_handle_ipc_command() { printf 'HANDLED:%s\n' "$1"; }
    (printf 'COMMAND|1|resume\n' > "$IGOR_RUNTIME_DIR/commands.fifo") &
    local writer=$!
    run _ai_poll_fifo
    wait "$writer"
    [ "$status" -eq 0 ]
    [ "$output" = "HANDLED:resume" ]
}

@test "session logs use private unpredictable files and reject symlinked directories" {
    export IGOR_DIR="$BATS_TEST_TMPDIR/session-root"
    mkdir -p "$IGOR_DIR/data"
    local first second
    first=$(_ai_session_log_create)
    second=$(_ai_session_log_create)
    [ "$first" != "$second" ]
    [ "$(stat -c '%a' "$first")" = 600 ]
    [ "$(stat -c '%a' "$IGOR_DIR/data/sessions")" = 700 ]
    rm -f -- "$first" "$second"
    rmdir "$IGOR_DIR/data/sessions"
    ln -s "$BATS_TEST_TMPDIR" "$IGOR_DIR/data/sessions"
    run _ai_session_log_create
    [ "$status" -ne 0 ]
}

@test "conversation checkpoints are valid redacted private JSON" {
    export IGOR_DIR="$BATS_TEST_TMPDIR/checkpoint-root"
    mkdir -p "$IGOR_DIR/secrets"
    printf 'PASSWORD=fixture-private-secret\n' > "$IGOR_DIR/secrets/local.env"
    local history='[{"role":"user","content":"fixture-private-secret"}]'
    run save_conversation_to_output "$history"
    [ "$status" -eq 0 ]
    local output_dir="$IGOR_DIR/data/sessions/output"
    local saved="${output#Conversation saved to: }"
    [[ "$saved" == "$output_dir/"* ]]
    [ "$(stat -c '%a' "$output_dir")" = 700 ]
    [ "$(stat -c '%a' "$saved")" = 600 ]
    ! grep -q 'fixture-private-secret' "$saved"
    python3 -m json.tool "$saved" >/dev/null
    run save_conversation_to_output '[{"role":"assistant","tool_calls":[{"id":"pending"}]}]'
    [ "$status" -ne 0 ]
}

@test "session postmortems are private and scrub known secrets" {
    export IGOR_DIR="$BATS_TEST_TMPDIR/postmortem-root"
    mkdir -p "$IGOR_DIR/secrets"
    printf 'PASSWORD=fixture-private-secret\n' > "$IGOR_DIR/secrets/local.env"
    _write_session_postmortem fixture-session 'fixture-private-secret' model provider \
        1 changed_unverified '' '' "$(date +%s)"
    local saved="$IGOR_DIR/data/sessions/fixture-session.json"
    [ -f "$saved" ]
    [ "$(stat -c '%a' "$saved")" = 600 ]
    ! grep -q 'fixture-private-secret' "$saved"
    grep -q 'changed_unverified' "$saved"
}
