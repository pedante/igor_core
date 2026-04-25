#!/bin/bash
# ==============================================================================
#  IGOR — healing/checks/_check_contract.sh
#  DOCUMENTATION ONLY — this file is never sourced by Igor.
#
#  Plugin contract for health check files in healing/checks/.
#
#  To add a new health check:
#    1. Create healing/checks/mycheck.sh
#    2. Set the required metadata variables
#    3. Implement run_check()
#    4. Test by running:  bash -c "source healing/checks/mycheck.sh; run_check"
#
#  See docs/adding-a-check.md for a full walkthrough.
# ==============================================================================

# ── Required metadata variables ───────────────────────────────────────────────
CHECK_NAME="mycheck"                # Short identifier — no spaces
CHECK_DESCRIPTION="What this checks" # One-line human-readable description
CHECK_SCHEDULE="300"                # Seconds between runs (v2 scheduling, ignored in v1)

# ── Required: run_check() ────────────────────────────────────────────────────
# Called by _healing_run_check() in healing/core.sh.
# MUST output CHECK_RESULT lines to stdout.
# Each line format:
#
#   CHECK_RESULT SEVERITY CODE MESSAGE
#
#   SEVERITY: OK | WARN | FAIL | CRITICAL
#   CODE:     unique short identifier, no spaces  (e.g. "app_down", "disk_high")
#   MESSAGE:  human-readable description (rest of line, spaces allowed)
#
# Rules:
#   - Output exactly one CHECK_RESULT line per condition checked.
#   - Always output at least one line (OK or worse).
#   - Do NOT use CRITICAL for temporary issues (short-lived processes, brief spikes).
#   - CRITICAL = needs immediate human attention.
#   - FAIL = definite problem, service likely impacted.
#   - WARN = degraded but still functional.
#   - Keep run_check() fast: avoid blocking calls > 5s total.
#   - All side effects must be idempotent (check is re-run regularly).
#
# run_check() runs in a SUBSHELL — do not rely on modifying global variables.
# Results persist via CHECK_RESULT lines only.

run_check() {
    # Example: always pass
    echo "CHECK_RESULT OK mycheck_example Example check passed"

    # Example: conditional
    # if some_condition_is_bad; then
    #     echo "CHECK_RESULT FAIL mycheck_failed Something went wrong"
    # else
    #     echo "CHECK_RESULT OK mycheck_ok Everything looks fine"
    # fi
}

# ── Optional: repair hints for the AI ────────────────────────────────────────
# If you know the fix for a failure, add a comment below with the pattern.
# The AI can record this as a pattern after a confirmed fix.
#
# Pattern hint format (comment only, not executed):
#   # PATTERN_HINT CODE "description" CHANGE "fix command"
#
# Example:
#   # PATTERN_HINT mycheck_failed "My service went down" CHANGE "docker compose restart myservice"
