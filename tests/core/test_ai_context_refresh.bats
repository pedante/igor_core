#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_DIR="$REPO_DIR"
    source "$REPO_DIR/core/ai/core.sh"
    ai_gather_context() { printf 'fresh context'; }
    ai_scrub_build_table() { :; }
    _ai_build_system_prompt() { printf 'prompt:%s' "$2"; }
    knowledge_block=known
    system_context=old
    scrubbed_context=old
    system_prompt=old
}

teardown() {
    teardown_igor_tmpdir
}

@test "refresh reports scrub validation warning separately from collection" {
    _ai_scrub_context_for_display() { printf 'partly scrubbed'; return 2; }
    _ai_refresh_context >"$BATS_TEST_TMPDIR/status" 2>&1
    [ "$?" -eq 0 ]
    [ "$system_context" = 'fresh context' ]
    [ "$scrubbed_context" = 'partly scrubbed' ]
    [ "$system_prompt" = 'prompt:partly scrubbed' ]
    [ "$_AI_CONTEXT_SCRUB_STATUS" = 2 ]
    [ "$(rg -c 'Context refreshed' "$BATS_TEST_TMPDIR/status")" = 1 ]
    rg -q 'Scrub validation found' "$BATS_TEST_TMPDIR/status"
    ! rg -q 'Scrub validation passed' "$BATS_TEST_TMPDIR/status"
}

@test "refresh reports validation passed only after a clean scrub" {
    _ai_scrub_context_for_display() { printf 'scrubbed'; }
    _ai_refresh_context >"$BATS_TEST_TMPDIR/status" 2>&1
    [ "$_AI_CONTEXT_SCRUB_STATUS" = 0 ]
    rg -q 'Context refreshed' "$BATS_TEST_TMPDIR/status"
    rg -q 'Scrub validation passed' "$BATS_TEST_TMPDIR/status"
}

@test "refresh failure retains the prior context and prompt" {
    _ai_scrub_context_for_display() { return 1; }
    if _ai_refresh_context >"$BATS_TEST_TMPDIR/status" 2>&1; then
        false
    fi
    [ "$system_context" = old ]
    [ "$scrubbed_context" = old ]
    [ "$system_prompt" = old ]
    ! rg -q 'Context refreshed' "$BATS_TEST_TMPDIR/status"
}

@test "prompt build failure does not publish a partial refresh" {
    _ai_scrub_context_for_display() { printf 'scrubbed'; }
    _ai_build_system_prompt() { return 1; }
    if _ai_refresh_context >"$BATS_TEST_TMPDIR/status" 2>&1; then
        false
    fi
    [ "$system_context" = old ]
    [ "$scrubbed_context" = old ]
    [ "$system_prompt" = old ]
    ! rg -q 'Context refreshed' "$BATS_TEST_TMPDIR/status"
}
