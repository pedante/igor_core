#!/usr/bin/env bats

load '../helpers/common'

setup() {
    setup_igor_tmpdir
    source "${BATS_TEST_DIRNAME}/../../core/ai/keys.sh"
    ok() { :; }
    warn() { :; }
    fail() { :; }
}

teardown() {
    teardown_igor_tmpdir
}

@test "hidden input helper captures only the entered value" {
    source "${BATS_TEST_DIRNAME}/../../core/lib/ui.sh"
    local key
    key=$(ask Key '' secret <<< 'fake-test-key')
    [ "$key" = fake-test-key ]
}

@test "visible key entry trims surrounding paste whitespace without capturing prompt" {
    local key
    key=$(_ai_prompt_key openrouter <<< '  fake-test-key  ')
    [ "$key" = fake-test-key ]
    run _ai_prompt_key openrouter <<< 'fake key'
    [ "$status" -eq 1 ]
}

@test "replacement key updates exported cache, persists securely, and reaches provider" {
    export OPENROUTER_API_KEY=old-test-key
    _ai_write_key openrouter $'\nnew-test-key\r\n'
    [ "$OPENROUTER_API_KEY" = new-test-key ]
    [ "$(cat "$IGOR_DIR/secrets/openrouter.key")" = new-test-key ]
    [ "$(stat -c %a "$IGOR_DIR/secrets/openrouter.key")" = 600 ]
    source "${BATS_TEST_DIRNAME}/../../core/ai/providers/openrouter.sh"
    [ "$(_provider_get_key)" = new-test-key ]
    run bash -c 'test "$OPENROUTER_API_KEY" = new-test-key'
    [ "$status" -eq 0 ]
}

@test "failed save preserves the cached credential" {
    export OPENROUTER_API_KEY=old-test-key
    mkdir "$IGOR_DIR/secrets/openrouter.key"
    # Force rename failure independently of the test user's permissions.
    mv() { return 1; }
    if _ai_write_key openrouter new-test-key; then
        return 1
    fi
    [ "$OPENROUTER_API_KEY" = old-test-key ]
}

@test "chat key replacement validates and updates the active session" {
    local or_api_key=old-test-key
    _nexus_validate_or_key() { [ "$1" = new-test-key ]; }
    _ai_change_key openrouter <<< new-test-key
    [ "$or_api_key" = new-test-key ]
    [ "$OPENROUTER_API_KEY" = new-test-key ]
    _nexus_validate_or_key() { return 1; }
    if _ai_change_key openrouter <<< rejected-test-key; then
        return 1
    fi
    [ "$or_api_key" = new-test-key ]
    [ "$(cat "$IGOR_DIR/secrets/openrouter.key")" = new-test-key ]
}

@test "Anthropic replacement leaves OpenRouter unchanged" {
    local api_key=old-test-key
    export OPENROUTER_API_KEY=other-provider-key
    _nexus_validate_ant_key() { return 0; }
    _ai_change_key anthropic <<< new-test-key
    [ "$api_key" = new-test-key ]
    [ "$ANTHROPIC_API_KEY" = new-test-key ]
    [ "$OPENROUTER_API_KEY" = other-provider-key ]
}

@test "cancelled entry and failed persistence keep the active chat key" {
    local or_api_key=old-test-key
    export OPENROUTER_API_KEY=old-test-key
    _nexus_validate_or_key() { return 0; }
    if _ai_change_key openrouter <<< ''; then
        return 1
    fi
    mv() { return 1; }
    if _ai_change_key openrouter <<< new-test-key; then
        return 1
    fi
    [ "$or_api_key" = old-test-key ]
    [ "$OPENROUTER_API_KEY" = old-test-key ]
}
