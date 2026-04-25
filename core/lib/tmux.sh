#!/bin/bash
# ==============================================================================
#  IGOR — core/lib/tmux.sh
#  Tmux awareness layer. Single source of truth for all tmux integration.
#
#  Public API:
#    igor_in_tmux          — returns 0 if running inside an active tmux session
#    igor_ensure_session   — relaunch inside tmux if IGOR_USE_TMUX=true
#    igor_layout_standard  — build the 2-pane layout (left=Igor/fzf, right=info)
#    igor_layout_ai        — mark AI mode with yellow border on left pane
#    igor_layout_restore   — clear AI mode border
#    igor_right_render/clear/append — in core/lib/output.sh (TTY-based, ANSI safe)
#    igor_fzf_cmd          — echo the right fzf invocation
#    igor_setup_features   — one-time startup check (rich, fzf, tmux binaries)
#
#  Legacy (kept for backward compat with any external callers):
#    igor_split_panel      — delegates to igor_layout_standard
#    igor_merge_panels     — no-op
#
#  Config (config/variables/igor.env):
#    IGOR_USE_TMUX=true    — set false to disable all tmux features
#
#  Pane ID variables (set by igor_layout_standard, exported):
#    IGOR_PANE_LEFT    — left pane (Igor shell, fzf menus)   alias: IGOR_PANE_MENU
#    IGOR_PANE_RIGHT   — right pane (info output via igor_right_* API)
#    _IGOR_RIGHT_FILE  — backing file for right pane content
# ==============================================================================

# ── igor_in_tmux ──────────────────────────────────────────────────────────────
# Returns 0 if we are inside an active tmux session with a usable pane.
# Nothing else in Igor should check $TMUX directly.
igor_in_tmux() {
    [ -n "${TMUX:-}" ] && command -v tmux &>/dev/null
}

# ── igor_ensure_session ───────────────────────────────────────────────────────
# If IGOR_USE_TMUX=true and not already in tmux, relaunch Igor inside a new
# tmux session named "igor". Uses exec — does not return.
igor_ensure_session() {
    [ "${IGOR_USE_TMUX:-false}" != "true" ] && return 0
    igor_in_tmux && return 0                       # already inside tmux
    command -v tmux &>/dev/null || return 0        # tmux not installed

    local _session="igor"
    local _entry="${IGOR_DIR}/igor.sh"
    if tmux has-session -t "$_session" 2>/dev/null; then
        exec tmux attach-session -t "$_session"
    else
        exec tmux new-session -s "$_session" "bash \"${_entry}\" ${*}"
    fi
}

# ── igor_layout_standard ─────────────────────────────────────────────────────
# Two-pane side-by-side layout.
#
#   ┌─────────────────────────────┬─────────────────────────────┐
#   │  LEFT  — Igor shell         │  RIGHT  — info / context    │
#   │  header + fzf menu          │  pre-session data, output   │
#   └─────────────────────────────┴─────────────────────────────┘
#
# Left pane  = IGOR_PANE_LEFT = IGOR_PANE_MENU (Igor's shell, fzf runs here)
# Right pane = IGOR_PANE_RIGHT (receives content via igor_right_* API)
#
# Split width adapts to terminal width:
#   ≥140 cols → 50/50     ≥80 cols → 40/60 (right wider)     <80 → single pane
#
# The right pane starts as a quiet bash shell. Content is delivered via
# tmux send-keys; no additional processes are spawned.
igor_layout_standard() {
    igor_in_tmux || return 0
    [ "${IGOR_USE_TMUX:-true}" = "false" ] && return 0
    [ -n "${IGOR_PANE_LEFT:-}" ] && return 0   # idempotent — already built

    # ── Determine split width ─────────────────────────────────────────────────
    local _cols _split_pct
    _cols=$(tput cols 2>/dev/null || echo 80)
    if   [ "$_cols" -ge 140 ]; then _split_pct=50
    elif [ "$_cols" -ge  80 ]; then _split_pct=40
    else
        # Too narrow — single-pane fallback: set aliases only
        IGOR_PANE_LEFT=$(tmux display-message -p '#{pane_id}')
        IGOR_PANE_MENU="$IGOR_PANE_LEFT"
        export IGOR_PANE_LEFT IGOR_PANE_MENU
        return 0
    fi

    # ── Right pane: idle process — content delivered via direct TTY write ────────
    # igor_right_render/append (in output.sh) write to the pane's TTY path.
    # No send-keys, no shell prompts — the pane is a pure display surface.
    IGOR_PANE_RIGHT=$(tmux split-window -h -p "$_split_pct" -d -P -F '#{pane_id}' \
        "bash -c 'while true; do sleep 86400; done'" 2>/dev/null)

    # ── Left pane = Igor's shell ───────────────────────────────────────────────
    IGOR_PANE_LEFT=$(tmux display-message -p '#{pane_id}')
    # Backward-compat alias — igor_fzf_cmd and igor_fzf_pick use IGOR_PANE_MENU
    IGOR_PANE_MENU="$IGOR_PANE_LEFT"

    export IGOR_PANE_LEFT IGOR_PANE_RIGHT IGOR_PANE_MENU
    tmux select-pane -t "$IGOR_PANE_LEFT" 2>/dev/null || true

    # ── Tmux status bar (header strip, replaces per-pane header block) ────────
    # Uses tmux user variables (@IGOR_*) so the static format string is set ONCE
    # here; header_loop.sh updates only the data slots every 10 s.
    local _session; _session=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "igor")
    local _ver="${IGOR_VERSION:-1.1.0-dev}"
    local _shost; _shost=$(hostname -s 2>/dev/null || echo "igor")
    tmux set-option -t "$_session" status on                               2>/dev/null
    tmux set-option -t "$_session" status-position top                     2>/dev/null
    tmux set-option -t "$_session" status-style "bg=#0d1117"               2>/dev/null
    tmux set-option -t "$_session" status-left-length  160                 2>/dev/null
    tmux set-option -t "$_session" status-right-length  40                 2>/dev/null
    # Hide the window list — Igor owns exactly one window; it should never show
    tmux set-option -t "$_session" window-status-format         ""         2>/dev/null
    tmux set-option -t "$_session" window-status-current-format ""         2>/dev/null
    # Static format string — #{@VAR} slots are written by header_loop (data only)
    tmux set-option -t "$_session" status-left \
        "#[fg=#22d3ee,bold] IGOR #[fg=#4a4a5a,nobold]·  v${_ver}  ·  ${_shost}  ·  #{@IGOR_HEALTH_BAR}#{@IGOR_AI_INFO}" \
        2>/dev/null
    tmux set-option -t "$_session" status-centre \
        "#[fg=#4a4a5a,align=centre]#{@IGOR_BREADCRUMB}"                    2>/dev/null
    tmux set-option -t "$_session" status-right \
        "#[fg=#4a4a5a]$(date '+%H:%M  %Y-%m-%d') "                        2>/dev/null
    # Seed initial variable values so the bar renders immediately (no blank slot)
    tmux set -t "$_session" @IGOR_HEALTH_BAR "#[fg=#4a4a5a]health: …  "   2>/dev/null
    tmux set -t "$_session" @IGOR_AI_INFO    ""                            2>/dev/null
    tmux set -t "$_session" @IGOR_BREADCRUMB ""                            2>/dev/null

    # ── Scrollback — left pane readable after long output (reports, logs, etc.) ──
    # history-limit: lines kept per pane; mouse on: wheel-scroll enters copy mode.
    # Keyboard: prefix+[ to enter copy mode, q to exit, arrows/PgUp/PgDn to scroll.
    tmux set-option -t "$_session" history-limit 10000                     2>/dev/null
    tmux set-option -t "$_session" mouse on                                2>/dev/null
    # Launch header loop in background; export PID for cleanup on exit
    if [ -f "${IGOR_DIR}/core/lib/header_loop.sh" ]; then
        bash "${IGOR_DIR}/core/lib/header_loop.sh" "$_session" \
            </dev/null >/dev/null 2>&1 &
        _IGOR_HEADER_LOOP_PID=$!
        export _IGOR_HEADER_LOOP_PID
    fi
}

# ── _igor_set_breadcrumb ──────────────────────────────────────────────────────
# Update the status-centre breadcrumb text.  Called by igor_fzf_pick (entering a
# submenu) and main_menu (clearing on return to root).  No-op outside tmux.
_igor_set_breadcrumb() {
    [ -z "${IGOR_PANE_RIGHT:-}" ] && return 0
    command -v tmux &>/dev/null || return 0
    local _sess; _sess=$(tmux display-message -p '#{session_name}' 2>/dev/null) || return 0
    tmux set -t "$_sess" @IGOR_BREADCRUMB "${1:-}" 2>/dev/null
    tmux refresh-client -S                          2>/dev/null
}

# ── igor_layout_ai ────────────────────────────────────────────────────────────
# Enter AI mode. The AI chat loop runs in IGOR_PANE_MENU (the current shell),
# so pane 3 stays at FULL HEIGHT — the user must be able to read and type.
#
# Visual indicator: yellow BORDER on the active pane, set via pane-active-border-style
# (window option). IMPORTANT: do NOT use `select-pane -P fg=yellow` — that sets the
# pane's text foreground to yellow, causing every post-\033[0m reset to produce yellow
# text (color bleed throughout the session).
#
# Scroll fix: enable mouse capture + bind WheelUpPane to copy-mode so the user
# can scroll back through the AI conversation. Two-part fix:
#   1. `tmux set-option mouse on` — without this, many SSH clients/terminals convert
#      wheel events to ^[[A/^[[B at the client level before tmux sees them.
#   2. WheelUpPane → copy-mode — tmux's default with `mouse on` converts wheel events
#      to Up/Down arrows; this binding intercepts them and uses copy-mode instead.
igor_layout_ai() {
    igor_in_tmux || return 0

    # ── Step 1: Enable mouse capture (must happen BEFORE the bindings fire) ───
    # Without `mouse on`, tmux never intercepts wheel events — they arrive as raw
    # ^[[A/^[[B arrow sequences injected by the SSH client or terminal emulator.
    tmux set-option mouse on 2>/dev/null || true

    # ── Step 2: Scroll bindings (unconditional — no pane required) ────────────
    # WheelUp  → enter copy-mode and scroll (so user can read conversation history)
    # WheelDown → scroll within copy-mode; no-op outside copy-mode (avoids arrows)
    tmux bind-key -T root WheelUpPane \
        if-shell -F '#{pane_in_mode}' \
        'send-keys -M' \
        'copy-mode -e; send-keys -M' 2>/dev/null || true
    tmux bind-key -T root WheelDownPane \
        if-shell -F '#{pane_in_mode}' \
        'send-keys -M' 2>/dev/null || true

    # ── Step 3: Yellow border on the active pane (needs pane target) ─────────
    local _tgt="${IGOR_PANE_LEFT:-${IGOR_PANE_MENU:-}}"
    [ -z "$_tgt" ] && return 0
    local _win; _win=$(tmux display-message -t "$_tgt" -p '#{window_id}' 2>/dev/null) || true
    [ -n "$_win" ] && \
        tmux set-window-option -t "$_win" pane-active-border-style 'fg=yellow' 2>/dev/null || true
}

# ── igor_layout_restore ───────────────────────────────────────────────────────
# Return from AI mode to standard menu mode: restore border, scroll, and mouse.
igor_layout_restore() {
    # Remove AI-mode copy-mode scroll bindings.
    tmux unbind-key -T root WheelUpPane   2>/dev/null || true
    tmux unbind-key -T root WheelDownPane 2>/dev/null || true
    # Unset session-level mouse override — falls back to user's tmux.conf default.
    tmux set-option -u mouse 2>/dev/null || true

    # Restore border.
    local _tgt="${IGOR_PANE_LEFT:-${IGOR_PANE_MENU:-}}"
    if [ -n "$_tgt" ]; then
        tmux select-pane -t "$_tgt" -P '' 2>/dev/null || true
        local _win; _win=$(tmux display-message -t "$_tgt" -p '#{window_id}' 2>/dev/null) || true
        [ -n "$_win" ] && \
            tmux set-window-option -t "$_win" -u pane-active-border-style 2>/dev/null || true
    fi
    # Clear the terminal so AI session output doesn't bleed into the main menu.
    tput clear 2>/dev/null || clear
}

# ── igor_split_panel (legacy) ─────────────────────────────────────────────────
# Kept for backward compat. Delegates to igor_layout_standard.
igor_split_panel() {
    igor_layout_standard
}

# ── igor_merge_panels (legacy) ────────────────────────────────────────────────
# Kept for backward compat. The 4-pane layout is persistent; only the output
# pane is transient (managed by igor_output_hide in output.sh).
igor_merge_panels() {
    declare -f igor_output_hide &>/dev/null && igor_output_hide || true
}

# ── igor_setup_features ───────────────────────────────────────────────────────
# Called once at startup AFTER igor_load_config has run (so IGOR_USE_TMUX and
# IGOR_FZF_ALREADY_ASKED are populated from config/variables/igor.env).
#
# Responsibilities:
#   1. Set _IGOR_RICH_AVAILABLE (python3-rich check).
#   2. If IGOR_USE_TMUX=false → disable fzf, done.
#   3. If IGOR_USE_TMUX=true but fzf/tmux missing:
#        - If IGOR_FZF_ALREADY_ASKED=false → offer install; persist answer.
#        - On refusal or failed install → write IGOR_USE_TMUX=false to igor.env.
#   4. Set _IGOR_FZF_AVAILABLE=true only when both binaries are present and
#      IGOR_USE_TMUX=true.
igor_setup_features() {
    local _igor_env="${IGOR_DIR}/config/variables/igor.env"

    # ── python3-rich ──────────────────────────────────────────────────────────
    _IGOR_RICH_AVAILABLE=false
    if ${IGOR_PYTHON:-python3} -c "import rich" 2>/dev/null; then
        _IGOR_RICH_AVAILABLE=true
    elif [ "${IGOR_QUIET:-}" != "1" ]; then
        echo "  [notice] python3-rich not found — AI panels will use plain text."
        echo "           Install: pkg_install pkg_rich"
    fi
    export _IGOR_RICH_AVAILABLE

    # ── Opt-out fast path ────────────────────────────────────────────────────
    if [ "${IGOR_USE_TMUX:-true}" = "false" ]; then
        _IGOR_FZF_AVAILABLE=false
        export _IGOR_FZF_AVAILABLE
        return 0
    fi

    # ── Check binaries ────────────────────────────────────────────────────────
    local _have_fzf=true _have_tmux=true
    command -v fzf  &>/dev/null || _have_fzf=false
    command -v tmux &>/dev/null || _have_tmux=false

    if $_have_fzf && $_have_tmux; then
        _IGOR_FZF_AVAILABLE=true
        export _IGOR_FZF_AVAILABLE
        return 0
    fi

    # ── One or more tools missing ─────────────────────────────────────────────
    if [ "${IGOR_FZF_ALREADY_ASKED:-false}" = "true" ]; then
        # Already asked in a prior run — silently fall back to plain text
        _IGOR_FZF_AVAILABLE=false
        export _IGOR_FZF_AVAILABLE
        return 0
    fi

    # First time — ask the user
    local _C=$'\033[1;36m' _Y=$'\033[1;33m' _R=$'\033[1;31m' _N=$'\033[0m'
    echo ""
    echo -e "  ${_Y}Igor uses fzf and tmux for interactive popup menus.${_N}"
    ! $_have_fzf  && echo -e "  ${_R}✗${_N}  fzf  — not installed"
    ! $_have_tmux && echo -e "  ${_R}✗${_N}  tmux — not installed"
    echo ""

    local _pkg_list=""
    ! $_have_fzf  && _pkg_list="${_pkg_list} fzf"
    ! $_have_tmux && _pkg_list="${_pkg_list} tmux"
    _pkg_list="${_pkg_list# }"

    echo -e "  Install ${_C}${_pkg_list}${_N} now?"
    local _ans; read -rp "  [y/n]: " _ans </dev/tty

    # Persist "already asked" immediately — regardless of answer
    if [ -f "$_igor_env" ]; then
        sed -i "s/^IGOR_FZF_ALREADY_ASKED=.*/IGOR_FZF_ALREADY_ASKED=true/" "$_igor_env"
    fi
    export IGOR_FZF_ALREADY_ASKED=true

    if [[ "$_ans" =~ ^[yY] ]]; then
        pkg_install ${_pkg_list} </dev/tty
        command -v fzf  &>/dev/null && _have_fzf=true
        command -v tmux &>/dev/null && _have_tmux=true
        if $_have_fzf && $_have_tmux; then
            _IGOR_FZF_AVAILABLE=true
            export _IGOR_FZF_AVAILABLE
            return 0
        fi
        echo -e "  ${_Y}Install may have failed — falling back to plain-text menus.${_N}"
    fi

    # Refused or install failed → disable IGOR_USE_TMUX
    if [ -f "$_igor_env" ]; then
        sed -i "s/^IGOR_USE_TMUX=.*/IGOR_USE_TMUX=false/" "$_igor_env"
    fi
    export IGOR_USE_TMUX=false
    echo ""
    echo -e "  ${_C}i${_N}  Switched to plain-text menus (IGOR_USE_TMUX=false)."
    echo -e "     To re-enable: edit ${_igor_env}"
    echo ""
    _IGOR_FZF_AVAILABLE=false
    export _IGOR_FZF_AVAILABLE
}

# ── igor_fzf_cmd ──────────────────────────────────────────────────────────────
# Echo the appropriate fzf invocation string.
#
# In 4-pane layout (IGOR_PANE_MENU set):
#   Igor IS in the menu pane — fzf runs fullscreen there. Return plain "fzf".
#
# In tmux without layout:
#   Use fzf-tmux popup geometry adapted to pane width.
#
# Outside tmux:
#   Plain fzf.
igor_fzf_cmd() {
    # 4-pane layout: fzf runs fullscreen in the menu pane — no popup needed
    if [ -n "${IGOR_PANE_MENU:-}" ]; then
        echo "fzf"
        return 0
    fi
    # In tmux but no layout: use fzf-tmux popup
    if igor_in_tmux && command -v fzf-tmux &>/dev/null; then
        local _width
        _width=$(tmux display-message -p '#{pane_width}' 2>/dev/null || echo 120)
        if [ "${_width}" -ge 100 ] 2>/dev/null; then
            echo "fzf-tmux -p 80%,70%"
        else
            echo "fzf-tmux -p 95%,80%"
        fi
    else
        echo "fzf"
    fi
}
