#!/bin/bash
# ==============================================================================
#  IGOR — recovery/run_canary.sh
#  P3-3: Post-fix canary check. Runs a lightweight command 60s after a fix
#  is applied and writes an alert if the fix appears to have reverted.
#
#  Called from ai/core.sh as a background job:
#    ( sleep 60; bash recovery/run_canary.sh SESSION_ID CMD EXPECTED ) &
#
#  Args:
#    $1 — session_id (e.g. "session_20260326_143000")
#    $2 — canary command (shell command to run)
#    $3 — expected pattern (substring expected in output; optional)
#
#  Writes: $IGOR_DIR/runtime/canary_alert.json  (overwritten if multiple alerts)
#  Appends: $IGOR_DIR/runtime/canary.log
# ==============================================================================

SESSION_ID="${1:-unknown}"
CANARY_CMD="${2:-}"
EXPECTED_PATTERN="${3:-}"

# Resolve IGOR_DIR — script may be called directly from repo root or via abs path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IGOR_DIR="${IGOR_DIR:-$(dirname "$SCRIPT_DIR")}"
RUNTIME_DIR="${IGOR_RUNTIME_DIR:-${IGOR_DIR}/data/runtime}"
LOG_FILE="${RUNTIME_DIR}/canary.log"
ALERT_FILE="${RUNTIME_DIR}/canary_alert.json"

mkdir -p "$RUNTIME_DIR" 2>/dev/null

ts=$(date '+%Y-%m-%d %H:%M:%S')

if [ -z "$CANARY_CMD" ]; then
    echo "[$ts] [SKIP] No canary command for session $SESSION_ID" >> "$LOG_FILE"
    exit 0
fi

# Run the canary command (force read-only context — no interactive TTY)
output=$(bash -c "$CANARY_CMD" </dev/null 2>&1)
exit_code=$?

echo "[$ts] [CANARY] session=$SESSION_ID cmd=$CANARY_CMD exit=$exit_code" >> "$LOG_FILE"
echo "[$ts]          output: ${output:0:200}" >> "$LOG_FILE"

# Determine pass/fail
passed=true
if [ $exit_code -ne 0 ]; then
    passed=false
    fail_reason="Command exited with code $exit_code"
elif [ -n "$EXPECTED_PATTERN" ]; then
    if ! echo "$output" | grep -q "$EXPECTED_PATTERN"; then
        passed=false
        fail_reason="Expected pattern not found: $EXPECTED_PATTERN"
    fi
fi

if [ "$passed" = "true" ]; then
    echo "[$ts] [PASS] Fix still in place for session $SESSION_ID" >> "$LOG_FILE"
    # Remove stale alert if any
    rm -f "$ALERT_FILE" 2>/dev/null
    exit 0
fi

echo "[$ts] [FAIL] Canary FAILED for session $SESSION_ID: $fail_reason" >> "$LOG_FILE"

# Write alert JSON for Igor to display at next session start
export _CANARY_SESSION="$SESSION_ID"
export _CANARY_CMD="$CANARY_CMD"
export _CANARY_FAIL="$fail_reason"
export _CANARY_OUTPUT="$output"
export _CANARY_TS="$ts"
export _CANARY_ALERT="$ALERT_FILE"
python3 - << 'PYEOF'
import json, os
data = {
    "session_id": os.environ.get("_CANARY_SESSION", ""),
    "canary_cmd": os.environ.get("_CANARY_CMD", ""),
    "fail_reason": os.environ.get("_CANARY_FAIL", ""),
    "output": os.environ.get("_CANARY_OUTPUT", "")[:500],
    "timestamp": os.environ.get("_CANARY_TS", "")
}
with open(os.environ["_CANARY_ALERT"], "w") as f:
    json.dump(data, f, indent=2)
PYEOF

exit 1
