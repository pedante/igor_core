#!/usr/bin/env bats

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    TEST_ROOT=$(mktemp -d)
    export IGOR_DIR="$TEST_ROOT" IGOR_RUNTIME_DIR="$TEST_ROOT/runtime"
    export IGOR_AI_EVENT_STREAM="$TEST_ROOT/events.jsonl"
    export IGOR_AI_EVENT_RENDER=false IGOR_AI_EVENT_SESSION_ID=safety-fixture
    mkdir -p "$IGOR_RUNTIME_DIR" "$TEST_ROOT/bin"
    export PATH="$TEST_ROOT/bin:$PATH"
    source "$REPO_DIR/core/ai/events.sh"
    source "$REPO_DIR/core/ai/safety.sh"
    source "$REPO_DIR/core/lib/input_validation.sh"
    ai_unscrub_inbound() { printf '%s' "$1"; }
    _ai_validate_tool_call() { echo 'BLOCKED: false'; }
    ai_knowledge_mark_changed() { :; }
    stub_ui() { :; }
    IGOR_QUIET_LOOP=true IGOR_VERBOSE=false ai_mode=assist executive_mode=false
    export IGOR_QUIET_LOOP IGOR_VERBOSE ai_mode executive_mode
    cd "$TEST_ROOT" || return 1
}

teardown() { rm -rf "$TEST_ROOT"; }

events() { python3 - "$IGOR_AI_EVENT_STREAM" <<'PY'
import json, sys
print("\n".join(json.dumps(e) for e in map(json.loads, open(sys.argv[1]))))
PY
}

event_types() { python3 - "$IGOR_AI_EVENT_STREAM" <<'PY'
import json, sys
print(" ".join(json.loads(line)["event_type"] for line in open(sys.argv[1])))
PY
}

@test "Guide READ emits proposal, approval, start, and output lifecycle" {
    ai_mode=guide
    printf 'r\n' | ai_execute_tool '{"tool":"host","cmd":"uname"}' >/dev/null
    run event_types
    [ "$status" -eq 0 ]
    [ "$output" = "action_proposed approval_waiting action_started action_output" ]
}

@test "Assist and Executive READ both auto-run without approval waiting" {
    for mode in assist executive; do
        : > "$IGOR_AI_EVENT_STREAM"
        ai_mode="$mode"
        ai_execute_tool '{"tool":"host","cmd":"uname"}' >/dev/null
        run event_types
        [ "$output" = "action_proposed action_started action_output" ]
    done
}

@test "CHANGE approval, Explain, Skip, and Stop transitions are structured" {
    ai_mode=assist
    _ai_explain_pending_approval() { AI_EXPLANATION_CACHE_TEXT='safe explanation'; return 0; }
    printf 'e\ns\n' | ai_execute_tool '{"tool":"host","cmd":"touch skipped"}' >/dev/null
    printf 'stop\n' | ai_execute_tool '{"tool":"host","cmd":"touch stopped"}' >/dev/null
    run event_types
    [ "$output" = "action_proposed approval_waiting explanation action_declined action_proposed approval_waiting action_stopped" ]
    [ ! -e skipped ] && [ ! -e stopped ]
}

@test "output event is ordered before the transaction result and scrubbed" {
    ai_scrub_outbound() { printf '%s' "$1" | sed 's/SECRET/[REDACTED]/g'; }
    : > "$TEST_ROOT/bin/SECRET"
    chmod +x "$TEST_ROOT/bin/SECRET"
    ai_execute_tool '{"tool":"host","cmd":"which SECRET"}' >/dev/null
    _ai_frontend_action_result() {
        _ai_event_emit action_result '{"tool_call_id":"fixture-call","result":{"execution_status":"tool_succeeded"}}'
    }
    _ai_frontend_action_result
    run python3 - "$IGOR_AI_EVENT_STREAM" <<'PY'
import json, sys
events = [json.loads(line) for line in open(sys.argv[1])]
assert [e["event_type"] for e in events] == [
    "action_proposed", "action_started", "action_output", "action_result"
]
assert "[REDACTED]" in events[2]["output"]
assert "SECRET" not in open(sys.argv[1]).read()
PY
    [ "$status" -eq 0 ]
}

@test "rendering a proposal does not execute an action twice" {
    export IGOR_AI_EVENT_RENDER=true
    ai_mode=executive
    ai_scrub_outbound() { printf '%s' "$1"; }
    local rendered
    rendered=$(printf 'y\n' | ai_execute_tool '{"tool":"host","cmd":"printf x >> executed"}' 2>&1 >/dev/null)
    [ "$(wc -c < executed)" -eq 1 ]
    [[ "$rendered" == *"CHANGE action:"* ]]
    [[ "$rendered" != *"NEEDS APPROVAL"* ]]
}

@test "quiet READ continuation records events without terminal proposal" {
    export IGOR_AI_EVENT_RENDER=true
    ai_scrub_outbound() { printf '%s' "$1"; }
    local rendered
    rendered=$(ai_execute_tool '{"tool":"host","cmd":"uname"}' 2>&1 >/dev/null)
    [[ "$rendered" != *"READ action:"* ]]
    run event_types
    [ "$output" = "action_proposed action_started action_output" ]
}
