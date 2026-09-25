#!/bin/bash
# ==============================================================================
#  IGOR — core/lib/output.sh
#  Right pane display and legacy output helpers.
#
#  Right pane API (two-pane layout — IGOR_PANE_RIGHT set):
#    igor_right_render <title> [key val ...] — structured info block
#    igor_right_clear                        — blank the right pane
#    igor_right_append <text>               — stream a line (no clear)
#
#  igor_right_render key/value pairs — special keys:
#    ---   <name>   → new section header
#    hint  <text>   → action hint line (dimmed, full width)
#
#  Fallback: all right-pane functions print to stdout when IGOR_PANE_RIGHT
#  is unset (no tmux / terminal too narrow).
#
#  Legacy API (kept for backward compat — no-ops in 2-pane layout):
#    igor_output_show / igor_output_hide
#    igor_output_to_pane / igor_output_stream / igor_output_header
# ==============================================================================

# ── _igor_right_tty ───────────────────────────────────────────────────────────
# Returns the TTY path of the right pane.  Fails (returns 1) when no right pane
# exists or the TTY is not writable.
_igor_right_tty() {
    [ -z "${IGOR_PANE_RIGHT:-}" ] && return 1
    local _tty
    _tty=$(tmux display-message -t "$IGOR_PANE_RIGHT" -p '#{pane_tty}' 2>/dev/null)
    [ -z "$_tty" ]   && return 1
    [ -c "$_tty" ]   || return 1
    [ -w "$_tty" ]   || return 1
    printf '%s' "$_tty"
}

# ── igor_right_clear ──────────────────────────────────────────────────────────
# Blank the right pane (cursor to home, clear screen).
igor_right_clear() {
    local _tty; _tty=$(_igor_right_tty) || return 0
    printf '\033[2J\033[H' > "$_tty" 2>/dev/null
}

# ── igor_right_render <title> [key value ...] ─────────────────────────────────
# Single renderer for all right-pane content.  Clears the pane first, then
# draws a titled block with key/value rows.
#
# Special keys:
#   ---   <section name>       → sub-section divider (── NAME ──────)
#   hint  <text>               → dimmed free-form hint line
#   []    KEY:LABEL[:desc]     → quick-action item — [KEY]  LABEL  desc
#                                matches left-pane menu item visual style
#
# Color palette: uses ui.sh vars (DIM, NC, BOLD) — same palette as left pane.
# Fallback (no right pane): prints a plain-text version to stdout.
igor_right_render() {
    local _title="$1"; shift

    # ── No right pane: plain stdout fallback ─────────────────────────────────
    local _tty; _tty=$(_igor_right_tty) || {
        echo ""
        printf '%b\n' "  ${DIM}── ${_title}${NC}"
        echo ""
        while [ $# -ge 2 ]; do
            case "$1" in
                ---) printf '%b\n\n' "\n  ${DIM}── ${2}${NC}" ;;
                hint) printf '%b\n' "  ${DIM}${2}${NC}" ;;
                "[]")
                    local _k _rest _lb _dc
                    _k="${2%%:*}"
                    _rest="${2#*:}"
                    _lb="${_rest%%:*}"
                    _dc="${_rest#*:}"
                    [ "$_dc" = "$_lb" ] && _dc=""
                    printf '%b\n' "  ${DIM}[${_k}]${NC}  ${BOLD}${_lb}${NC}  ${DIM}${_dc}${NC}"
                    ;;
                *) printf '%b\n' "  ${DIM}$(printf '%-16s' "${1}:")${NC} ${2}" ;;
            esac
            shift 2
        done
        echo ""
        return 0
    }

    # ── Right pane: direct TTY write ─────────────────────────────────────────
    local _pw
    _pw=$(tmux display-message -t "$IGOR_PANE_RIGHT" -p '#{pane_width}' 2>/dev/null || echo 40)

    # Helper: fill line to pane width with ─ (U+2500 — matches left pane separator)
    _rfill() {
        local _label="$1"
        local _len=$(( _pw - ${#_label} - 5 ))
        [ "$_len" -lt 1 ] && _len=1
        local _f; printf -v _f '%*s' "$_len" ''; printf '%s' "${_f// /─}"
    }

    {
        printf '\033[0m\033[2J\033[H'   # full attr reset + clear + home
        # Title — same DIM + ── format as left pane section headers
        printf '%b\n\n' "${DIM}── ${_title} $(_rfill "$_title")${NC}"

        while [ $# -ge 2 ]; do
            case "$1" in
                ---)
                    printf '%b\n\n' "\n${DIM}── ${2} $(_rfill "$2")${NC}"
                    ;;
                hint)
                    printf '%b\n' "\n  ${DIM}${2}${NC}"
                    ;;
                "[]")
                    # Quick-action item: [KEY]  LABEL  — no description (would wrap)
                    local _k _rest _lb
                    _k="${2%%:*}"
                    _rest="${2#*:}"
                    _lb="${_rest%%:*}"
                    printf '%b\n' "  ${DIM}[${_k}]${NC}  ${BOLD}${_lb}${NC}"
                    ;;
                *)
                    # Key-value row: DIM label (not teal) — matches left pane muted hints
                    printf '%b\n' "  ${DIM}$(printf '%-16s' "${1}:")${NC} ${2}"
                    ;;
            esac
            shift 2
        done
    } > "$_tty" 2>/dev/null
}

# ── igor_right_append <text> ──────────────────────────────────────────────────
# Append a line to the right pane without clearing.  Use for streaming output
# (scan results, provisioning progress, etc.).  ANSI codes in <text> work.
# Fallback: echo -e to stdout.
igor_right_append() {
    local _tty; _tty=$(_igor_right_tty) || { echo -e "$*"; return; }
    printf '%b\n' "$*" > "$_tty" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════════════════════
#  Legacy output API — kept for backward compatibility.
#  In the 2-pane layout these are no-ops; the right pane is used instead.
# ══════════════════════════════════════════════════════════════════════════════

_igor_output_log() { echo "${IGOR_DIR}/data/runtime/output.log"; }

igor_output_show() {
    [ -z "${IGOR_PANE_MENU:-}" ] && return 0
    [ -n "${IGOR_PANE_RIGHT:-}" ] && return 0   # 2-pane layout: right pane handles display
    [ -n "${IGOR_PANE_OUTPUT:-}" ] && return 0
    local _log; _log=$(_igor_output_log)
    mkdir -p "${IGOR_DIR}/data/runtime" 2>/dev/null; touch "$_log" 2>/dev/null
    IGOR_PANE_OUTPUT=$(tmux split-window -v -b -p 70 -d -P -F '#{pane_id}' \
        -t "$IGOR_PANE_MENU" "tail -f '${_log}'" 2>/dev/null)
    export IGOR_PANE_OUTPUT
}

igor_output_hide() {
    [ -z "${IGOR_PANE_OUTPUT:-}" ] && return 0
    tmux kill-pane -t "$IGOR_PANE_OUTPUT" 2>/dev/null || true
    unset IGOR_PANE_OUTPUT
    [ -n "${IGOR_PANE_MENU:-}" ] && tmux select-pane -t "$IGOR_PANE_MENU" 2>/dev/null || true
}

igor_output_clear() {
    : > "$(_igor_output_log)" 2>/dev/null || true
}

igor_output_header() {
    local _title="${1:-}" _log; _log=$(_igor_output_log)
    local _line="─────────────────────────────────────────────────"
    printf '\n%s\n  %s\n%s\n' "$_line" "$_title" "$_line" >> "$_log" 2>/dev/null
}

igor_output_to_pane() {
    if [ -n "${IGOR_PANE_MENU:-}" ] && [ -z "${IGOR_PANE_RIGHT:-}" ]; then
        igor_output_show
        "$@" >> "$(_igor_output_log)" 2>&1
    else
        "$@"
    fi
}

igor_output_stream() {
    local _title="$1"; shift
    igor_output_show
    igor_output_header "$_title"
    igor_output_to_pane "$@"
    local _rc=$?
    local _log; _log=$(_igor_output_log)
    [ $_rc -eq 0 ] && echo "  ✔ done" >> "$_log" || echo "  ✗ exit ${_rc}" >> "$_log"
    return $_rc
}

_igor_output_log_msg() {
    [ -z "${IGOR_PANE_MENU:-}" ] && return 0
    if [ -n "${IGOR_PANE_RIGHT:-}" ]; then
        igor_right_append "  $1  $2"
        return 0
    fi
    igor_output_show
    echo -e "  $1  $2" >> "$(_igor_output_log)" 2>/dev/null
}
