#!/usr/bin/env bats

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    export IGOR_DIR="$REPO_DIR"
    export IGOR_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
    export IGOR_AI_EVENT_STREAM="$BATS_TEST_TMPDIR/events.jsonl"
    export IGOR_AI_EVENT_RENDER=false
    export IGOR_AI_EVENT_SESSION_ID=session-fixture
    mkdir -p "$IGOR_RUNTIME_DIR"
    source "$REPO_DIR/core/ai/core.sh"
    ai_mode=guide
    executive_mode=false
    provider=fixture-provider
    model=fixture-model
}

@test "core session and response hooks emit ordered frontend events" {
    _ai_set_session_state start_requested
    _ai_set_session_state ready
    grep -Fxq "AI_EVENT_STREAM=$IGOR_AI_EVENT_STREAM" "$IGOR_RUNTIME_DIR/state.env"
    _ai_frontend_event assistant_message "fixture answer" received
    _ai_frontend_event continuation "continuing" running
    _ai_set_session_state user_exited

    run python3 - "$IGOR_AI_EVENT_STREAM" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
assert [event["event_type"] for event in events] == [
    "session_started", "model_status", "assistant_message",
    "continuation", "session_finished",
]
assert [event["sequence"] for event in events] == [1, 2, 3, 4, 5]
assert events[2]["display"] == "fixture answer"
assert events[3]["status"] == "running"
assert all(event["session_id"] == "session-fixture" for event in events)
PY
    [ "$status" -eq 0 ]
}

@test "mode changes are emitted with the canonical mode value" {
    _ai_set_mode assist >"$BATS_TEST_TMPDIR/mode-output"
    [ "$(<"$BATS_TEST_TMPDIR/mode-output")" = assist ]
    [ "$ai_mode" = assist ]

    _ai_set_mode executive >"$BATS_TEST_TMPDIR/mode-output"
    [ "$(<"$BATS_TEST_TMPDIR/mode-output")" = executive ]
    [ "$ai_mode" = executive ]

    run python3 - "$IGOR_AI_EVENT_STREAM" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
assert [event["event_type"] for event in events] == [
    "mode_changed", "settings_snapshot", "mode_changed", "settings_snapshot",
]
mode_events = [event for event in events if event["event_type"] == "mode_changed"]
settings = [event for event in events if event["event_type"] == "settings_snapshot"]
assert [event["mode"] for event in mode_events] == ["assist", "executive"]
assert [event["status"] for event in mode_events] == ["assist", "executive"]
assert [event["settings"]["mode"] for event in settings] == ["assist", "executive"]
PY
    [ "$status" -eq 0 ]
}

@test "core action result event carries the canonical transaction result" {
    _ai_frontend_action_result '{"tool_call_id":"call-fixture","classification":"READ","approval_status":"not_required","execution_status":"tool_succeeded","exit_code":0,"combined_output":"fixture output"}'

    run python3 - "$IGOR_AI_EVENT_STREAM" <<'PY'
import json
import sys

event = json.loads(open(sys.argv[1], encoding="utf-8").readline())
assert event["event_type"] == "action_result"
assert event["action_id"] == "call-fixture"
assert event["result"]["classification"] == "READ"
assert event["result"]["execution_status"] == "tool_succeeded"
assert event["result"]["approval_status"] == "not_required"
assert event["result"]["combined_output"] == "fixture output"
PY
    [ "$status" -eq 0 ]
}
