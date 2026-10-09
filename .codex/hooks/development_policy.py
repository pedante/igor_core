"""Supplementary PreToolUse guard; runner/supervisor budgets are authoritative."""

import json
import re
import sys


def denial(event):
    tool = event.get("tool_name", "")
    inputs = event.get("tool_input", {})
    text = json.dumps(inputs) if not isinstance(inputs, str) else inputs
    if tool in ("Agent", "spawn_agent", "resume_agent", "followup_task") or re.search(
        r"\b(?:spawn_agent|resume_agent|followup_task)\s*\(", text
    ):
        return "Igor is single agent; delegation requires explicit Owner configuration."
    if tool in ("apply_patch", "Edit", "Write"):
        return None
    if re.search(r"--new-budget\b|codex_supervised\.py", text):
        return "Only the Owner may renew a budget or start a supervised session from their terminal."
    if "--dry-run" in text:
        return None
    if re.search(r"run_all\.sh|\bpytest\s+(?:-\S+\s+)*tests(?:[\s\"']|$)|"
                 r"\bbats\s+tests/(?:core|modules|integration)/?(?:[\s\"']|$)|"
                 r"\bruff\s+check\s+\.(?:[\s\"']|$)", text):
        return "Direct broad validation blocked; use tests/validate.sh for governed validation."
    return None


def main():
    try:
        reason = denial(json.load(sys.stdin))
    except (ValueError, TypeError):
        reason = "Malformed development-policy hook input."
    if reason:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                          "permissionDecision": "deny", "permissionDecisionReason": reason}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
