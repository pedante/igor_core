#!/bin/bash
# Structured frontend events for the AI session.
#
# This file deliberately has no policy or execution responsibilities.  The
# dispatcher emits JSON payloads through _ai_event_emit; terminal and future
# frontends consume the resulting ordered JSONL stream.
#
# The stream is a local presentation boundary and may contain unsanitized host
# identifiers or command output. It is owner-only (0600) and must never be
# reused as provider/export payload without passing the outbound scrub boundary.

AI_EVENT_TYPES='session_started model_status assistant_message action_proposed approval_waiting explanation action_started action_output action_result action_skipped action_declined action_stopped privilege_waiting privilege_result continuation warning error mode_changed settings_snapshot session_finished'

_ai_event_stream_path() {
    if [ -n "${IGOR_AI_EVENT_STREAM:-}" ]; then
        printf '%s' "$IGOR_AI_EVENT_STREAM"
    elif [ -n "${IGOR_RUNTIME_DIR:-}" ]; then
        printf '%s' "${IGOR_RUNTIME_DIR:-${IGOR_DIR:-.}/data/runtime}/ai-events.jsonl"
    else
        return 1
    fi
}

# Usage: _ai_event_emit EVENT_TYPE JSON_OBJECT
# The function is silent on stdout so it is safe inside command substitution.
_ai_event_emit() {
    local event_type="${1:-}" payload="${2-}" path
    path=$(_ai_event_stream_path) || return 2
    [ -n "$event_type" ] || return 2
    case " $AI_EVENT_TYPES " in
        *" $event_type "*) ;;
        *) return 2 ;;
    esac
    # Event persistence is opt-in and must use the already-private runtime.
    local parent
    parent=${path%/*}
    [ "$parent" != "$path" ] && [ -d "$parent" ] && [ ! -L "$parent" ] && [ -O "$parent" ] || return 2
    EVENT_TYPE="$event_type" EVENT_PAYLOAD="$payload" EVENT_PATH="$path" \
        python3 - <<'PY'
import fcntl
import json
import os
import stat
from datetime import datetime, timezone
from pathlib import Path

event_type = os.environ["EVENT_TYPE"]
try:
    payload = json.loads(os.environ.get("EVENT_PAYLOAD", "{}"))
except json.JSONDecodeError:
    raise SystemExit(2)
if not isinstance(payload, dict):
    raise SystemExit(2)
path = Path(os.environ["EVENT_PATH"])
flags = os.O_RDWR | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW
fd = os.open(path, flags, 0o600)
with os.fdopen(fd, "r+", encoding="utf-8") as handle:
    fcntl.flock(handle, fcntl.LOCK_EX)
    file_stat = os.fstat(handle.fileno())
    if not stat.S_ISREG(file_stat.st_mode) or file_stat.st_uid != os.getuid():
        raise SystemExit(2)
    handle.seek(0)
    sequence = 0
    for line in handle:
        try:
            sequence = max(sequence, int(json.loads(line).get("sequence", 0)))
        except (ValueError, TypeError, json.JSONDecodeError):
            continue
    timestamp = datetime.now(timezone.utc).isoformat()
    event = {
        "event_type": event_type,
        "sequence": sequence + 1,
        "timestamp": timestamp,
        **payload,
    }
    # Canonical envelope fields cannot be spoofed by a renderer payload.
    event["event_type"] = event_type
    event["sequence"] = sequence + 1
    event["timestamp"] = timestamp
    handle.seek(0, 2)
    handle.write(json.dumps(event, ensure_ascii=True, separators=(",", ":")) + "\n")
    handle.flush()
    os.fchmod(handle.fileno(), 0o600)
PY
}

# Render one structured event to stderr. Rendering never invokes an action.
_ai_event_render() {
    [ "${IGOR_AI_EVENT_RENDER:-true}" = true ] || return 0
    EVENT_JSON="${1-}" python3 - <<'PY' >&2
import json
import os

try:
    event = json.loads(os.environ.get("EVENT_JSON", "{}"))
except json.JSONDecodeError:
    raise SystemExit(0)
kind = event.get("event_type", "")
text = event.get("display", "")
labels = {
    "session_started": "Session started",
    "model_status": "Model status",
    "assistant_message": "",
    "action_proposed": "Action proposed",
    "approval_waiting": "Waiting for approval",
    "explanation": "Explanation",
    "action_started": "Action started",
    "action_output": "",
    "action_result": "Action result",
    "action_skipped": "Action skipped",
    "action_declined": "Action declined",
    "action_stopped": "Action stopped",
    "privilege_waiting": "Administrator authentication required",
    "privilege_result": "Administrator authentication",
    "continuation": "Progress",
    "warning": "Warning",
    "error": "Error",
    "mode_changed": "Mode changed",
    "session_finished": "Session finished",
}
if text:
    if kind == "action_proposed":
        tier = event.get("classification", "")
        label = "DESTRUCTIVE — DATA LOSS POSSIBLE" if tier == "DESTROY" else f"{tier or 'Unknown'} action"
        print(f"{label}: {text}")
    else:
        print(f"{labels.get(kind, kind)}: {text}" if labels.get(kind, kind) else text)
PY
}

# Render an already emitted payload, without appending or invoking a tool.
_ai_event_render_payload() {
    local event_type="${1:-}" payload="${2-}" event_json
    [ -n "$payload" ] || payload='{}'
    [ "${IGOR_AI_EVENT_RENDER:-true}" = true ] || return 0
    event_json=$(EVENT_TYPE="$event_type" EVENT_PAYLOAD="$payload" python3 - <<'PY'
import json
import os
print(json.dumps({"event_type": os.environ["EVENT_TYPE"], **json.loads(os.environ["EVENT_PAYLOAD"])}))
PY
) || return 0
    _ai_event_render "$event_json"
}

# Emit and render as one ordered operation. The render is intentionally stderr.
_ai_event_publish() {
    local event_type="${1:-}" payload="${2-}"
    [ -n "$payload" ] || payload='{}'
    _ai_event_emit "$event_type" "$payload" || return
    _ai_event_render_payload "$event_type" "$payload"
}
