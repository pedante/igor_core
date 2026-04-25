#!/bin/bash
# ==============================================================================
#  IGOR — core/lib/header_loop.sh
#  Drives the tmux status bar data slots.  Launched as a background process by
#  igor_layout_standard(); receives the tmux SESSION NAME as $1.
#
#  The static format string (branding, version, hostname) is written ONCE by
#  igor_layout_standard().  This loop updates ONLY the data variables:
#    @IGOR_HEALTH_BAR  — coloured health bar + percentage
#    @IGOR_AI_INFO     — active AI model + cost (empty when no AI session)
#
#  Refreshes every 10 seconds; exits cleanly when the session disappears.
# ==============================================================================

IGOR_DIR="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
_STATE="${IGOR_RUNTIME_DIR:-${IGOR_DIR}/data/runtime}/state.env"
_SESSION="${1:-igor}"

command -v tmux &>/dev/null          || exit 0
tmux has-session -t "$_SESSION" 2>/dev/null || exit 0

while true; do
    tmux has-session -t "$_SESSION" 2>/dev/null || exit 0

    _health="" _model="" _cost="" _ai=""
    if [ -f "$_STATE" ]; then
        _health=$(grep "^health_score="      "$_STATE" 2>/dev/null | cut -d= -f2)
        _model=$(grep  "^NEXUS_MODEL="       "$_STATE" 2>/dev/null | cut -d= -f2)
        _cost=$(grep   "^AI_SESSION_COST="   "$_STATE" 2>/dev/null | cut -d= -f2)
        _ai=$(grep     "^AI_SESSION_ACTIVE=" "$_STATE" 2>/dev/null | cut -d= -f2)
    fi

    [ "$_health" = "?" ] && _health=""
    [ "$_ai" != "1" ] && _model="" && _cost=""

    # ── @IGOR_HEALTH_BAR ─────────────────────────────────────────────────────
    # "…" = state file absent (no check has run yet)
    # "—" = state file exists but score is unknown
    if [ -n "$_health" ] && [ "$_health" -ge 0 ] 2>/dev/null; then
        _f=$(( _health / 10 )); _e=$(( 10 - _f ))
        _bar=""
        for (( i=0; i<_f; i++ )); do _bar+="●"; done
        for (( i=0; i<_e; i++ )); do _bar+="○"; done
        if   [ "$_health" -ge 80 ]; then _hfg="#[fg=#4ec9b0]"
        elif [ "$_health" -ge 50 ]; then _hfg="#[fg=#e5c07b]"
        else                              _hfg="#[fg=#e06c75]"
        fi
        _health_bar="${_hfg}${_bar} ${_health}%#[fg=#4a4a5a]  "
    elif [ -f "$_STATE" ]; then
        _health_bar="#[fg=#4a4a5a]health: —  "
    else
        _health_bar="#[fg=#4a4a5a]health: …  "
    fi

    # ── @IGOR_AI_INFO ─────────────────────────────────────────────────────────
    if [ -n "$_model" ]; then
        _ai_info="#[fg=#4a4a5a]${_model}  \$${_cost:-0.00}  "
    else
        _ai_info=""
    fi

    tmux set -t "$_SESSION" @IGOR_HEALTH_BAR "$_health_bar" 2>/dev/null
    tmux set -t "$_SESSION" @IGOR_AI_INFO    "$_ai_info"    2>/dev/null
    tmux refresh-client -S                                   2>/dev/null

    sleep 10
done
