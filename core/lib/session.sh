#!/bin/bash
# ==============================================================================
#  IGOR — core/lib/session.sh
#  AI session lifecycle hooks.
#
#  Public API:
#    igor_ai_entry   — called at AI session start
#    igor_ai_exit    — called at AI session end
#
#  Requires core/lib/tmux.sh and core/lib/output.sh to be sourced first.
# ==============================================================================

# ── igor_ai_entry ─────────────────────────────────────────────────────────────
# Called at the top of the AI chat loop (core/ai/core.sh line ~1917).
# In 4-pane layout: shows output pane, compacts menu to 3-line status strip.
# Fallback (no layout): creates the old 2-pane split.
# Also updates the right panel to show in-session commands (Bug 5 fix).
igor_ai_entry() {
    if [ -z "${IGOR_PANE_MENU:-}" ]; then
        igor_split_panel   # build the 2-pane layout if not already done
    fi
    # Always call igor_layout_ai — it sets mouse on + scroll bindings unconditionally,
    # then optionally the yellow border when IGOR_PANE_LEFT is available.
    declare -f igor_layout_ai &>/dev/null && igor_layout_ai

    # Update right panel: transition from "Session Prompt Ready" to active session.
    # Dynamic values (model/provider) read from calling scope via dynamic scoping.
    if declare -f igor_right_render &>/dev/null; then
        igor_right_render "AI Session Active" \
            "Model"     "${model:-unknown}" \
            "Provider"  "${provider:-unknown}" \
            "Exec mode" "$(${executive_mode:-false} && echo 'ON (auto-CHANGE)' || echo 'off')" \
            "---"       "Session commands" \
            "hint"      "help         show all commands" \
            "hint"      "stats        tokens · context age" \
            "hint"      "refresh      re-scan system state" \
            "hint"      "hypo         hypothesis tracker" \
            "hint"      "hypo add     inject focus direction" \
            "hint"      "exec on/off  toggle TIER 2 auto-run" \
            "hint"      "quiet on/off collapse READ steps" \
            "hint"      "undo         reverse last CHANGE" \
            "hint"      "solved/new   clear WIP, fresh topic" \
            "hint"      "exit / q     end session"
    fi
}

# ── igor_ai_exit ──────────────────────────────────────────────────────────────
# Called when the AI session ends (normal exit, /quit, end_session IPC).
# In 4-pane layout: hides output pane, restores full-height menu.
# Fallback (no layout): closes the 2-pane split.
igor_ai_exit() {
    # Full layout restore (yellow border removal + scroll reset + screen clear).
    # Primary exit paths (exit|quit|q and end_session IPC) do their own inline
    # cleanup so they can run knowledge_session_end prompts before clearing —
    # this function is the fallback for any other callers.
    if [ -n "${IGOR_PANE_MENU:-}" ]; then
        igor_layout_restore
    else
        igor_merge_panels
    fi
}
