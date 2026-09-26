#!/usr/bin/env bats

setup() {
    export IGOR_DIR="$BATS_TEST_DIRNAME/../.."
    export IGOR_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
    mkdir -p "$IGOR_RUNTIME_DIR"
    source "$BATS_TEST_DIRNAME/../../core/ai/core.sh"
}

@test "captures explicit alternatives as structured pending state" {
    _ai_pending_choice_capture $'Would you like:\n- Journal logs\n- Temporary files'
    [ -n "$_AI_PENDING_CHOICE_JSON" ]
    [[ "$_AI_PENDING_CHOICE_JSON" == *'Journal logs'* ]]
    [[ "$_AI_PENDING_CHOICE_JSON" == *'Temporary files'* ]]
    [ "$_AI_PENDING_INTERACTION_OWNER" = assistant ]
    [ "$_AI_PENDING_INTERACTION_TYPE" = conversational_choice ]
    [ "$_AI_PENDING_INTERACTION_STATE" = awaiting_input ]
}

@test "resolves numbered and ordinal answers and clears the question" {
    _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files\n3. Package cache'
    _ai_pending_choice_resolve 2
    [ "$_AI_PENDING_CHOICE_RESOLUTION" = '[USER CHOICE: Temporary files]' ]
    [ -z "$_AI_PENDING_CHOICE_JSON" ]
    [ "$_AI_PENDING_INTERACTION_STATE" = resolved ]
    [ -z "$_AI_PENDING_INTERACTION_OWNER" ]

    _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files\n3. Package cache'
    _ai_pending_choice_resolve 3
    [ "$_AI_PENDING_CHOICE_RESOLUTION" = '[USER CHOICE: Package cache]' ]

    _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files\n3. Package cache'
    _ai_pending_choice_resolve "the first one"
    [ "$_AI_PENDING_CHOICE_RESOLUTION" = '[USER CHOICE: Journal logs]' ]
}

@test "resolves an unambiguous textual answer" {
    _ai_pending_choice_capture $'Would you like:\n- Journal logs\n- Temporary files'
    _ai_pending_choice_resolve logs
    [ "$_AI_PENDING_CHOICE_RESOLUTION" = '[USER CHOICE: Journal logs]' ]

    _ai_pending_choice_capture $'Would you like:\n- Journal logs\n- Temporary files'
    _ai_pending_choice_resolve journal
    [ "$_AI_PENDING_CHOICE_RESOLUTION" = '[USER CHOICE: Journal logs]' ]
}

@test "ambiguous text leaves the pending question for clarification" {
    _ai_pending_choice_capture $'Choose one:\n- Logs\n- Journal logs'
    run _ai_pending_choice_resolve logs
    [ "$status" -ne 0 ]
    [ -n "$_AI_PENDING_CHOICE_JSON" ]
}

@test "cancel and a clearly new topic clear stale choices" {
    _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files'
    _ai_pending_choice_route_input stop || true
    [ -z "$_AI_PENDING_CHOICE_JSON" ]

    _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files'
    _ai_pending_choice_route_input 'check if vlc is installed' || true
    [ -z "$_AI_PENDING_CHOICE_JSON" ]
}

@test "control replies do not get consumed by stale choices" {
    for reply in yes no continue cancel /stop; do
        _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files'
        _ai_pending_choice_route_input "$reply" || true
        [ -z "$_AI_PENDING_CHOICE_JSON" ]
        [ -z "$_AI_PENDING_INTERACTION_OWNER" ]
    done
}

@test "bare cancel dismisses a pending choice locally" {
    _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files'
    local result=0
    _ai_pending_choice_route_input '  CaNcEl  ' || result=$?
    [ "$result" -eq 4 ]
    [ -z "$_AI_PENDING_CHOICE_JSON" ]
    [ -z "$_AI_PENDING_CHOICE_ROUTED_INPUT" ]
    [ -z "$_AI_PENDING_INTERACTION_OWNER" ]

    _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files'
    _ai_pending_choice_route_input 'cancel the backup' || true
    [ -z "$_AI_PENDING_CHOICE_JSON" ]
    [ "$_AI_PENDING_CHOICE_ROUTED_INPUT" = 'cancel the backup' ]
}

@test "short numbered and ordinal replies have deterministic choices" {
    _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files\n3. Package cache'
    _ai_pending_choice_route_input 1
    [[ "$_AI_PENDING_CHOICE_ROUTED_INPUT" == *'[USER CHOICE: Journal logs]'* ]]

    _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files\n3. Package cache'
    _ai_pending_choice_route_input "the second one"
    [[ "$_AI_PENDING_CHOICE_ROUTED_INPUT" == *'[USER CHOICE: Temporary files]'* ]]

    _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files\n3. Package cache'
    _ai_pending_choice_route_input 3
    [[ "$_AI_PENDING_CHOICE_ROUTED_INPUT" == *'[USER CHOICE: Package cache]'* ]]
}

@test "local commands are never consumed as conversational choices" {
    _ai_pending_choice_capture $'Choose one:\n1. Journal logs\n2. Temporary files'
    _ai_pending_choice_route_input help || true
    [ -z "$_AI_PENDING_CHOICE_JSON" ]
}

@test "resolved input preserves the original reply and adds canonical choice metadata" {
    _ai_pending_choice_capture $'Would you like:\n- Journal logs\n- Temporary files'
    _ai_pending_choice_route_input logs
    [[ "$_AI_PENDING_CHOICE_ROUTED_INPUT" == *$'logs\n[USER CHOICE: Journal logs]'* ]]
}

@test "ordinary numbered lists without a choice question are ignored" {
    _ai_pending_choice_capture $'Run these steps:\n1. Inspect logs\n2. Check disk space'
    [ -z "$_AI_PENDING_CHOICE_JSON" ]
}
