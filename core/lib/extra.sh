#!/bin/bash
# ==============================================================================
#  IGOR — core/lib/extra.sh
#  Pane 4 content management.
#
#  Public API:
#    igor_extra_launch  — start pane 4 content (--extra TUI or IGOR_EXTRA_CMD)
#    igor_extra_swap    — interactively replace pane 4 content
#
#  Config (config/variables/igor.env):
#    IGOR_EXTRA_CMD=    — custom command for pane 4 (empty = default --extra TUI)
# ==============================================================================

# ── igor_extra_launch ─────────────────────────────────────────────────────────
# (Re-)launch pane 4 content via send-keys.  Used by igor_extra_swap after
# killing the previous process.  igor_layout_standard now starts the pane
# with the correct command directly — this function is NOT called at startup.
igor_extra_launch() {
    [ -z "${IGOR_PANE_EXTRA:-}" ] && return 0
    local _cmd="${IGOR_EXTRA_CMD:-}"
    if [ -n "$_cmd" ]; then
        tmux send-keys -t "$IGOR_PANE_EXTRA" "$_cmd" Enter 2>/dev/null
    else
        tmux send-keys -t "$IGOR_PANE_EXTRA" \
            "bash '${IGOR_DIR}/igor.sh' --extra" Enter 2>/dev/null
    fi
}

# ── igor_extra_swap ───────────────────────────────────────────────────────────
# Interactively replace pane 4 content. Bound to ctrl+b e via igor_layout_standard.
igor_extra_swap() {
    [ -z "${IGOR_PANE_EXTRA:-}" ] && return 0
    # Kill whatever is running in pane 4
    tmux send-keys -t "$IGOR_PANE_EXTRA" "q" "" 2>/dev/null
    tmux send-keys -t "$IGOR_PANE_EXTRA" "" C-c 2>/dev/null
    sleep 0.3

    local _cmd
    echo ""
    read -rp "  Extra pane command (leave blank for default --extra): " _cmd </dev/tty
    if [ -n "$_cmd" ]; then
        tmux send-keys -t "$IGOR_PANE_EXTRA" "$_cmd" Enter 2>/dev/null
    else
        tmux send-keys -t "$IGOR_PANE_EXTRA" \
            "bash '${IGOR_DIR}/igor.sh' --extra" Enter 2>/dev/null
    fi
}
