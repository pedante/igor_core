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

@test "provider key entry trims surrounding paste whitespace without capturing prompt" {
    local key
    key=$(_ai_prompt_key anthropic <<< '  fake-test-key  ')
    [ "$key" = fake-test-key ]
    run _ai_prompt_key openrouter <<< 'fake key'
    [ "$status" -eq 1 ]
}

@test "OpenRouter writer delegates to private managed staging without shell cache" {
    local staged
    _ai_openrouter_commit_private() { staged="$1"; }
    export OPENROUTER_API_KEY=synthetic-old-key
    _ai_write_key openrouter synthetic-new-key
    [ "$staged" = synthetic-new-key ]
    [ "$OPENROUTER_API_KEY" = synthetic-old-key ]
    [ ! -e "$IGOR_DIR/secrets/openrouter.key" ]
}

@test "OpenRouter API KEY approval updates no process cache" {
    local or_api_key=synthetic-old-key
    export OPENROUTER_API_KEY=synthetic-old-key
    _ai_openrouter_commit_private() { [ "$1" = synthetic-new-key ]; }
    _ai_change_key openrouter <<< synthetic-new-key
    [ -z "$or_api_key" ]
    [ -z "${OPENROUTER_API_KEY:-}" ]
}

@test "chat key replacement validates and updates the active session" {
    local or_api_key=synthetic-old-key
    _ai_openrouter_commit_private() { [ "$1" = synthetic-new-key ]; }
    _ai_change_key openrouter <<< synthetic-new-key
    [ -z "$or_api_key" ]
    _ai_openrouter_commit_private() { return 1; }
    if _ai_change_key openrouter <<< rejected-test-key; then
        return 1
    fi
    [ -z "$or_api_key" ]
    [ ! -e "$IGOR_DIR/secrets/openrouter.key" ]
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
    local or_api_key=synthetic-old-key
    export OPENROUTER_API_KEY=synthetic-old-key
    _ai_openrouter_commit_private() { return 0; }
    if _ai_change_key openrouter <<< ''; then
        return 1
    fi
    _ai_openrouter_commit_private() { return 1; }
    if _ai_change_key openrouter <<< new-test-key; then
        return 1
    fi
    [ "$or_api_key" = synthetic-old-key ]
    [ "$OPENROUTER_API_KEY" = synthetic-old-key ]
}

@test "managed cutover permits canonical rotation and blocks old provider fallback" {
    _ai_openrouter_cutover() { return 0; }
    export OPENROUTER_API_KEY=synthetic-inherited-key
    _ai_openrouter_commit_private() { [ "$1" = synthetic-new-key ]; }
    _ai_write_key openrouter synthetic-new-key
    [ ! -e "$IGOR_DIR/secrets/openrouter.key" ]
    _ai_openrouter_commit_private() { return 0; }
    _ai_change_key openrouter <<< synthetic-new-key
    [ -z "${OPENROUTER_API_KEY:-}" ]
    source "${BATS_TEST_DIRNAME}/../../core/ai/providers/openrouter.sh"
    [ -z "$(_provider_get_key)" ]
}

@test "hybrid OpenRouter request uses managed transport without a shell key" {
    source "${BATS_TEST_DIRNAME}/../../core/lib/ai_hybrid.sh"
    _igor_hybrid_openrouter_cutover() { return 0; }
    provider=openrouter
    _nexus_py_append() { printf '[]'; }
    _nexus_api_call() { [ -z "$NEXUS_API_KEY" ] && touch "$IGOR_DIR/managed-request"; printf 'synthetic-response'; }
    _nexus_parse_result() {
        local -n _test_commands="$3"
        _test_commands=()
        printf -v "$2" '%s' 'synthetic reply'
        printf -v "$4" '%s' '1'
        printf -v "$5" '%s' '1'
        printf -v "$6" '%s' ''
        printf -v "$7" '%s' ''
    }
    _igor_hybrid_ask "fixture message"
    [ -e "$IGOR_DIR/managed-request" ]
}
