#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_DIR="$REPO_DIR"
    export IGOR_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
    export IGOR_AI_EVENT_STREAM="$IGOR_RUNTIME_DIR/tui-events.jsonl"
    export IGOR_AI_EVENT_RENDER=false
    mkdir -p "$IGOR_RUNTIME_DIR"
    source "$REPO_DIR/core/ai/core.sh"
    stub_ui
}

teardown() {
    teardown_igor_tmpdir
}

@test "--ai-tui gives a deterministic classic UI fallback on a non-TTY" {
    run bash "$REPO_DIR/igor.sh" --ai-tui
    [ "$status" -eq 2 ]
    [[ "$output" == *"needs an interactive terminal"* ]]
    [[ "$output" == *"bash igor.sh for the classic UI"* ]]
}

@test "TUI backend skips the classic preflight and preserves its event stream" {
    local marker="$BATS_TEST_TMPDIR/fzf-called"
    export IGOR_TUI_MODE=true OPENROUTER_API_KEY=fixture-key
    provider=openrouter model=fixture-model
    header() { :; }
    ai_set_cost_rates() { :; }
    _nexus_validate_or_key() { return 0; }
    _nexus_get_or_balance() { :; }
    igor_right_render() { :; }
    igor_fzf_pick() { : >"$marker"; return 1; }
    _ai_set_session_state() {
        [ "$1" = start_requested ] && return 1
        return 0
    }

    run menu_ai
    [ "$status" -eq 2 ]
    [ ! -e "$marker" ]
    [ "$IGOR_AI_EVENT_STREAM" = "$IGOR_RUNTIME_DIR/tui-events.jsonl" ]
}

@test "classic backend still uses the existing preflight" {
    local marker="$BATS_TEST_TMPDIR/fzf-called"
    export OPENROUTER_API_KEY=fixture-key
    provider=openrouter model=fixture-model
    header() { :; }
    ai_set_cost_rates() { :; }
    _nexus_validate_or_key() { return 0; }
    _nexus_get_or_balance() { :; }
    igor_right_render() { :; }
    igor_fzf_pick() { : >"$marker"; return 1; }

    run menu_ai
    [ "$status" -eq 0 ]
    [ -e "$marker" ]
}

@test "TUI WIP skip leaves resumable investigation data intact" {
    export IGOR_TUI_MODE=true OPENROUTER_API_KEY=fixture-key
    provider=openrouter model=fixture-model
    KNOWLEDGE_DIR="$BATS_TEST_TMPDIR/knowledge"
    WIP_FILE="$KNOWLEDGE_DIR/wip.md"
    mkdir -p "$KNOWLEDGE_DIR"
    printf '%s\n' '**Problem:** preserve this investigation' '**Status:** OPEN' >"$WIP_FILE"
    local before
    before=$(<"$WIP_FILE")

    header() { :; }
    clear() { :; }
    ai_set_cost_rates() { :; }
    _nexus_validate_or_key() { return 0; }
    _nexus_get_or_balance() { :; }
    igor_right_render() { :; }
    igor_ai_entry() { :; }
    ai_knowledge_show_status() { :; }
    ai_knowledge_load() { printf 'fresh context\n'; }
    ai_gather_context() { printf 'context\n'; }
    ai_scrub_build_table() { :; }
    _ai_scrub_context_for_display() { printf 'scrubbed context\n'; }
    _ai_build_system_prompt() { return 1; }
    _ai_session_log_create() { printf '%s/session.log' "$BATS_TEST_TMPDIR"; : >"$BATS_TEST_TMPDIR/session.log"; }
    _ai_set_session_state() { return 0; }

    run menu_ai
    [ "$status" -eq 2 ]
    [[ "$output" == *"WIP kept for later"* ]]
    [ "$(<"$WIP_FILE")" = "$before" ]
}

@test "TUI backend keeps CHANGE approval semantics in the dispatcher" {
    export IGOR_QUIET_LOOP=true IGOR_VERBOSE=false ai_mode=assist executive_mode=false
    ai_unscrub_inbound() { printf '%s' "$1"; }
    _ai_validate_tool_call() { echo 'BLOCKED: false'; }
    ai_knowledge_mark_changed() { :; }
    local marker="$BATS_TEST_TMPDIR/should-not-exist"

    run bash -c '
        source "$1/core/ai/core.sh"
        ai_mode=assist executive_mode=false
        ai_unscrub_inbound() { printf "%s" "$1"; }
        _ai_validate_tool_call() { echo "BLOCKED: false"; }
        ai_knowledge_mark_changed() { :; }
        printf "n\n" | ai_execute_tool "{\"tool\":\"host\",\"cmd\":\"printf changed > $2\"}"
    ' _ "$REPO_DIR" "$marker"
    [ "$status" -eq 0 ]
    [ ! -e "$marker" ]
    [[ "$output" == *"DECLINED"* || "$output" == *"declined"* ]]
}
