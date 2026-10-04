#!/usr/bin/env bats

setup() {
    TEST_ROOT=$(mktemp -d)
    export IGOR_DIR="$TEST_ROOT"
    export IGOR_RUNTIME_DIR="$TEST_ROOT/runtime"
    export IGOR_AI_EVENT_STREAM="$TEST_ROOT/events.jsonl"
    export IGOR_AI_EVENT_RENDER=false
    mkdir -m 700 "$IGOR_RUNTIME_DIR"
    source "$BATS_TEST_DIRNAME/../../core/ai/events.sh"
}

teardown() { rm -rf "$TEST_ROOT"; }

@test "events have stable envelope fields and preserve order" {
    [ "$AI_EVENT_TYPES" = 'session_started model_status context_routing assistant_message action_proposed approval_waiting explanation action_started action_output action_result action_skipped action_declined action_stopped privilege_waiting privilege_result continuation warning error mode_changed settings_snapshot session_finished' ]
    _ai_event_emit session_started '{"session_id":"s1","mode":"guide"}'
    _ai_event_emit action_proposed '{"session_id":"s1","action_id":"a1","classification":"READ"}'
    run python3 -c 'import json,sys; e=[json.loads(x) for x in open(sys.argv[1])]; assert [x["event_type"] for x in e] == ["session_started","action_proposed"]; assert [x["sequence"] for x in e] == [1,2]; assert e[1]["classification"] == "READ"' "$IGOR_AI_EVENT_STREAM"
    [ "$status" -eq 0 ]
}

@test "publish renders to stderr and does not execute anything" {
    export IGOR_AI_EVENT_RENDER=true
    run bash -c 'source "$1"; _ai_event_publish action_result '\''{"display":"done","result":{"execution_status":"tool_succeeded"}}'\''' _ "$BATS_TEST_DIRNAME/../../core/ai/events.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Action result: done"* ]]
    ! grep -q 'execute' "$IGOR_AI_EVENT_STREAM"
}

@test "classic renderer uses the event classification for an action label" {
    export IGOR_AI_EVENT_RENDER=true
    run bash -c 'source "$1"; _ai_event_publish action_proposed '\''{"classification":"DESTROY","display":"remove volume"}'\''' _ "$BATS_TEST_DIRNAME/../../core/ai/events.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DESTRUCTIVE — DATA LOSS POSSIBLE: remove volume"* ]]
}

@test "lifecycle events carry canonical result data" {
    _ai_event_emit action_result '{"action_id":"a1","classification":"CHANGE","approval":"approved","result":{"execution_status":"tool_succeeded","exit_code":0}}'
    run python3 -c 'import json,sys; e=json.load(open(sys.argv[1])); assert e["result"]["execution_status"] == "tool_succeeded"; assert e["approval"] == "approved"' "$IGOR_AI_EVENT_STREAM"
    [ "$status" -eq 0 ]
}

@test "event persistence is opt in when no runtime path is configured" {
    unset IGOR_AI_EVENT_STREAM IGOR_RUNTIME_DIR
    run _ai_event_emit session_started '{}'
    [ "$status" -ne 0 ]
}

@test "unknown event types are rejected" {
    run _ai_event_emit made_up_event '{}'
    [ "$status" -ne 0 ]
}

@test "event stream refuses a symlinked destination" {
    printf 'original\n' > "$TEST_ROOT/target"
    ln -s "$TEST_ROOT/target" "$IGOR_AI_EVENT_STREAM"
    run _ai_event_emit session_started '{}'
    [ "$status" -ne 0 ]
    [ "$(cat "$TEST_ROOT/target")" = original ]
}

@test "sequence cache preserves ordering and recovers from stale or corrupt state" {
    _ai_event_emit session_started '{"session_id":"s1"}'
    _ai_event_emit warning '{"display":"first"}'
    [ -f "$IGOR_AI_EVENT_STREAM.seq" ]
    [ "$(stat -c '%a' "$IGOR_AI_EVENT_STREAM.seq")" = 600 ]

    printf 'corrupt\n' > "$IGOR_AI_EVENT_STREAM.seq"
    _ai_event_emit warning '{"display":"after-corrupt-cache"}'
    run python3 - "$IGOR_AI_EVENT_STREAM" <<'PY'
import json,sys
events=[json.loads(line) for line in open(sys.argv[1])]
assert [item["sequence"] for item in events] == [1,2,3]
PY
    [ "$status" -eq 0 ]

    : > "$IGOR_AI_EVENT_STREAM"
    _ai_event_emit warning '{"display":"after-truncate"}'
    run python3 - "$IGOR_AI_EVENT_STREAM" <<'PY'
import json,sys
events=[json.loads(line) for line in open(sys.argv[1])]
assert [item["sequence"] for item in events] == [1]
PY
    [ "$status" -eq 0 ]
}

@test "payload cannot replace envelope identity or ordering" {
    _ai_event_emit warning '{"event_type":"action_started","sequence":99,"timestamp":"fake","status":"validation"}'
    run python3 - "$IGOR_AI_EVENT_STREAM" <<'PY'
import json
import sys
event = json.load(open(sys.argv[1]))
assert event["event_type"] == "warning"
assert event["sequence"] == 1
assert event["timestamp"] != "fake"
assert event["status"] == "validation"
PY
    [ "$status" -eq 0 ]
}
