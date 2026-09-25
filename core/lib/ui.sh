#!/bin/bash
# ==============================================================================
#  IGOR — lib/ui.sh
#  Core UI functions for the IGOR control system.
#
#  Provides:
#    • Colour definitions
#    • Status output functions (step, ok, warn, fail, info)
#    • User interaction functions (pause, confirm, ask)
#    • Header display with system status
# ==============================================================================

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'
CYAN='\033[0;36m'; MAG='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'; DIM='\033[2m'

# ── Status output ──────────────────────────────────────────────────────────────
# step() creates pane 2 lazily (first action marker — signals work is starting).
# ok/warn/fail/info only write to pane 2 if it already exists (IGOR_PANE_OUTPUT set).
# This avoids spurious pane creation during menu rendering and startup messages.
step() {
    echo -e "\n  ${CYAN}${BOLD}▶ $1${NC}"
    declare -f _igor_output_log_msg &>/dev/null && _igor_output_log_msg "${CYAN}${BOLD}▶${NC}" "$1"
}
ok()   {
    echo -e "  ${GRN}✔${NC} $1"
    [ -n "${IGOR_PANE_OUTPUT:-}${IGOR_PANE_RIGHT:-}" ] && declare -f _igor_output_log_msg &>/dev/null && \
        _igor_output_log_msg "${GRN}✔${NC}" "$1"
}
warn() {
    echo -e "  ${YEL}!${NC} $1"
    [ -n "${IGOR_PANE_OUTPUT:-}${IGOR_PANE_RIGHT:-}" ] && declare -f _igor_output_log_msg &>/dev/null && \
        _igor_output_log_msg "${YEL}!${NC}" "$1"
}
fail() {
    echo -e "  ${RED}✘${NC} $1"
    [ -n "${IGOR_PANE_OUTPUT:-}${IGOR_PANE_RIGHT:-}" ] && declare -f _igor_output_log_msg &>/dev/null && \
        _igor_output_log_msg "${RED}✘${NC}" "$1"
}
info() {
    echo -e "  ${CYAN}i${NC} $1"
    [ -n "${IGOR_PANE_OUTPUT:-}${IGOR_PANE_RIGHT:-}" ] && declare -f _igor_output_log_msg &>/dev/null && \
        _igor_output_log_msg "${CYAN}i${NC}" "$1"
}
pause()   { echo ""; read -rp "  Press Enter to continue..."; }

# ── User interaction ───────────────────────────────────────────────────────────
confirm() {
    local _a
    read -rp "  ${1:-Are you sure?} [y/N]: " _a
    [[ "$_a" =~ ^[Yy]$ ]]
}

ask() {
    local prompt="$1" default="$2" secret="${3:-}" val
    [ -n "$default" ] && { local dp="$default"; [ "$secret" = "secret" ] && dp="****"; prompt="${prompt} [${dp}]"; }
    [ "$secret" = "secret" ] && { read -rsp "  ${prompt}: " val; echo "" >&2; } || read -rp "  ${prompt}: " val
    echo "${val:-$default}"
}

# ── Breadcrumb display ────────────────────────────────────────────────────────
# breadcrumb "Igor" "C: Email Command" "1: Status & Control"
# Shows a navigation path line below the header.
breadcrumb() {
    local path="" sep="${DIM} › ${NC}"
    local first=1
    for part in "$@"; do
        [ $first -eq 0 ] && path+="$sep"
        path+="${CYAN}${part}${NC}"
        first=0
    done
    echo -e "  ${path}"
    echo ""
}

# Resolve a display address on systems whose hostname implementation does not
# support ``-I`` (for example BSD/macOS). Keep this in line with the AI context
# and scrubber fallback order.
_igor_ui_lan_ip() {
    local ips ip
    ips=$(hostname -I 2>/dev/null) || ips=""
    for ip in $ips; do
        case "$ip" in
            *.*) printf '%s' "$ip"; return 0 ;;
        esac
    done
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '
            { for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }
        ')
        [ -n "$ip" ] && { printf '%s' "$ip"; return 0; }
        ip -4 -o addr show scope global 2>/dev/null | awk 'NR == 1 {split($4, a, "/"); print a[1]}'
    fi
}

# ── Header display ─────────────────────────────────────────────────────────────
# Displays the main header with system status information.
# Relies on global variables and functions that must be defined elsewhere:
#   - DB_ENV, SELF_HEALING_ISSUES, SELF_HEALING_LAST_REPAIR, SELF_HEALING_CONFIG_DRIFT
#   - calculate_health_score() function
header() {
    clear
    local domain lan_ip hostname_str

    # Get domain from db.env if available
    domain=$(grep "^NEXTCLOUD_TRUSTED_DOMAINS=" "${IGOR_DIR}/secrets/db.env" 2>/dev/null | cut -d= -f2- | tr -d '"' | cut -d',' -f1 || echo "NOT SET")
    lan_ip=$(_igor_ui_lan_ip)
    hostname_str=$(hostname 2>/dev/null)

    # Calculate health score for display
    local health_score health_color
    health_score=$(calculate_health_score 2>/dev/null || echo "-1")
    if [ "$health_score" = "-1" ]; then
        health_color="${DIM}"       # unknown — no healing data yet
    elif [ "$health_score" -ge 80 ]; then
        health_color="${GRN}"
    elif [ "$health_score" -ge 50 ]; then
        health_color="${YEL}"
    else
        health_color="${RED}"
    fi

    # Count active issues by severity
    local critical_count=0 warn_count=0
    if [ ${#SELF_HEALING_ISSUES[@]} -gt 0 ]; then
        for issue in "${SELF_HEALING_ISSUES[@]}"; do
            [[ "$issue" =~ \[CRITICAL\] ]] && ((critical_count++))
            [[ "$issue" =~ \[FAIL\] ]] && ((warn_count++))
        done
    fi

    local _ver; _ver=$(cat "${IGOR_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "1.1.0-dev")
    echo -e "${MAG}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║   IGOR  ·  I Guard. Observe. Repair.          ║"
    printf "  ║   %-47s║\n" "v${_ver}  ·  Your Nextcloud guardian"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  Host      : ${YEL}${hostname_str}${NC}  (${lan_ip})"
    echo -e "  Domain    : ${YEL}${domain:-NOT SET}${NC}"
    # Module status lines — each registered hook prints one line
    if declare -f igor_run_all_hooks &>/dev/null; then
        igor_run_all_hooks "status_line" 2>/dev/null || true
    fi

    # Self-healing status display — fixed-width columns, stale indicator, color-coded
    local _health_stale=false
    if [ -f "$_HEALING_CACHE_FILE" ] 2>/dev/null; then
        local _cache_age
        _cache_age=$(python3 -c "
import os, time
try:
    age = time.time() - os.path.getmtime('${_HEALING_CACHE_FILE}')
    print(int(age // 60))
except:
    print(9999)
" 2>/dev/null || echo 9999)
        [ "${_cache_age:-9999}" -gt 30 ] 2>/dev/null && _health_stale=true
    fi

    if [ "$health_score" = "-1" ]; then
        printf "  %-10s: %b\n" "Health" "${DIM}— not checked yet  (run D or A to scan)${NC}"
    else
        local _stale_tag=""
        $_health_stale && _stale_tag="  ${DIM}(stale — run D or 8 to refresh)${NC}"
        printf "  %-10s: %b\n" "Health" "${health_color}${health_score}/100${NC}${_stale_tag}"
    fi
    if [ "$critical_count" -gt 0 ] || [ "$warn_count" -gt 0 ]; then
        printf "  %-10s: %b\n" "Issues" \
            "${RED}${critical_count} critical${NC}  │  ${YEL}${warn_count} warnings${NC}"
    fi

    # Dynamic menu items pending count
    local pending_count
    pending_count=$(source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh" 2>/dev/null && get_pending_item_count 2>/dev/null || echo "0")
    if [ "$pending_count" -gt 0 ]; then
        echo -e "  Pending   : ${YEL}${pending_count} dynamic menu item(s) awaiting approval${NC}"
    fi

    if [ -n "$SELF_HEALING_LAST_REPAIR" ]; then
        local time_since_repair
        time_since_repair=$(python3 -c "
from datetime import datetime, timedelta
try:
    repair_time = datetime.strptime('${SELF_HEALING_LAST_REPAIR}', '%Y-%m-%d %H:%M:%S')
    now = datetime.now()
    diff = now - repair_time
    if diff.seconds < 60:
        print(f'{diff.seconds}s ago')
    elif diff.seconds < 3600:
        print(f'{diff.seconds//60}m ago')
    else:
        print(f'{diff.seconds//3600}h ago')
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
        echo -e "  Last Repair: ${CYAN}${time_since_repair}${NC}"
    fi

    if [ $SELF_HEALING_CONFIG_DRIFT -gt 0 ]; then
        echo -e "  ${YEL}Config drift: $SELF_HEALING_CONFIG_DRIFT issues detected${NC}"
    fi

    # AI Hybrid mode badge
    if [ "${AI_HYBRID_MODE:-false}" = "true" ]; then
        echo -e "  ${MAG}●${NC} AI hybrid ${GRN}${BOLD}ON${NC}  —  type a question or /menu to clear"
    fi

    # Docker access is relevant only when a Docker capability is active.  A
    # system-only installation should not warn about an optional container
    # runtime merely because this shared header is rendered.
    local _docker_ui_enabled=false
    if declare -f igor_has_capability >/dev/null 2>&1; then
        igor_has_capability docker && _docker_ui_enabled=true
    elif command -v docker >/dev/null 2>&1; then
        _docker_ui_enabled=true
    fi
    if $_docker_ui_enabled && ! groups 2>/dev/null | grep -q docker; then
        echo -e "\n  ${RED}${BOLD}!! Not in docker group — log out and back in !!${NC}"
    fi
    echo ""
}

# ── igor_fzf_pick — shared fzf submenu picker ────────────────────────────────
# Usage: igor_fzf_pick "Breadcrumb title" "KEY:LABEL:DESC" ...
#
# Special item format:  "_:SECTION HEADER:"   → styled separator (not selectable)
# Returns 0 and prints the selected KEY to stdout.
# Returns 1 if the user aborted (Esc / Ctrl-C) — caller should `return`.
# Returns 2 if fzf is not available — caller falls through to static display.
#
# Typical usage pattern in a module menu:
#   while true; do
#       local opt
#       opt=$(igor_fzf_pick "4: Services" \
#           "1:START ALL:Bring all containers up" \
#           "b:BACK:Return to main menu") || return
#       [ "$opt" = "_" ] && continue
#       case "$opt" in ...
#   done
igor_fzf_pick() {
    [ "${_IGOR_FZF_AVAILABLE:-false}" != "true" ] && return 2

    # Before rendering fzf, hide the output pane so pane 3 expands to full
    # height.  This covers both the main menu returning and sub-menu re-draws.
    declare -f igor_output_hide &>/dev/null && igor_output_hide

    local _title="$1"; shift
    local _C=$'\033[1;36m' _B=$'\033[1m' _D=$'\033[2m'
    local _H=$'\033[1;34m' _R=$'\033[1;31m' _N=$'\033[0m'
    local -a _lines=()

    # Update tmux status-centre breadcrumb — replaces fzf --header
    declare -f _igor_set_breadcrumb &>/dev/null && _igor_set_breadcrumb "$_title"

    for _raw in "$@"; do
        local _k="${_raw%%:*}"
        local _rest="${_raw#*:}"
        local _lb="${_rest%%:*}"
        local _dc="${_rest#*:}"
        if [ "$_k" = "_" ]; then
            _lines+=("_"$'\t'"${_H}── ${_lb}${_N}")
        else
            local _pad; printf -v _pad '%-20s' "$_lb"
            local _kc="$_C"
            # Red badge for destructive items (label contains NUKE/DELETE/DESTROY/WIPE)
            case "$_lb" in *NUKE*|*DELETE*|*DESTROY*|*WIPE*|*RESET*) _kc="$_R" ;; esac
            _lines+=("${_k}"$'\t'"${_kc}[${_k}]${_N}  ${_B}${_pad}${_N}  ${_D}${_dc}${_N}")
        fi
    done

    local _sel
    local _fzf_cmd; _fzf_cmd=$(igor_fzf_cmd 2>/dev/null || echo "fzf")
    # fzf-tmux: popup manages its own size (drop --height); needs "--" to
    # separate its popup geometry args from the fzf args that follow.
    # Plain fzf:  "--" signals end-of-options and breaks styling — omit it.
    local _height_flag="--height=100%"
    local _sep=()
    if [[ "$_fzf_cmd" == fzf-tmux* ]]; then
        _height_flag=""
        _sep=("--")
    fi
    _sel=$(printf '%s\n' "${_lines[@]}" | ${_fzf_cmd} "${_sep[@]}" \
        --ansi \
        ${_height_flag:+"$_height_flag"} \
        --layout=reverse \
        --border=rounded \
        --prompt="  ❯ " \
        --pointer="▶" \
        --info=hidden \
        --no-sort \
        --delimiter=$'\t' \
        --with-nth=2 \
        --color="bg:#0d1117,bg+:#0f2744,fg:#c9d1d9,fg+:white,border:#1e3a5f,\
header:#c9d1d9,prompt:#22d3ee,pointer:#38bdf8,\
hl:#22d3ee,hl+:#38bdf8,separator:#1e3a5f,scrollbar:#38bdf8" \
        --bind="esc:abort" \
        2>/dev/null) || return 1

    [ -z "$_sel" ] && return 1
    printf '%s' "$_sel" | cut -f1
}

# ── igor_render_menu — dynamic key assignment ────────────────────────────────
# Usage: igor_render_menu "Title" "action_id:LABEL[:desc]" ...
#
# Items use action IDs (not keys).  Keys are assigned at render time:
#   q/quit/back/exit → [q]  (always)
#   ai/assistant/A   → [A]  (always)
#   diagnose/D       → [D]  (always)
#   help/?           → [?]  (always)
#   _                → section header (not selectable)
#   everything else  → [1]–[9] then [a]–[z] (skipping reserved), by position
#
# Returns: prints action_id of selected item to stdout.
# Exit codes mirror igor_fzf_pick: 0=selected, 1=aborted, 2=fzf unavailable.
igor_render_menu() {
    local _title="$1"; shift

    # Guard: no items → treat as fzf unavailable so caller falls through to plain text
    if [ $# -eq 0 ]; then return 2; fi

    # Reserved keys — never auto-assigned
    local -A _RESERVED=([q]=1 [Q]=1 [A]=1 [D]=1 [?]=1)
    # Key assignment sequence: 1-9, then a-z skipping reserved
    local -a _key_seq=(1 2 3 4 5 6 7 8 9)
    local _c; for _c in {a..z}; do
        [[ "${_RESERVED[$_c]+x}" ]] || _key_seq+=("$_c")
    done

    local -a _fzf_items=()
    local -a _action_map=()   # "key=action_id" pairs for reverse lookup
    local _ki=0

    for _raw in "$@"; do
        local _action="${_raw%%:*}"
        local _rest="${_raw#*:}"
        local _label="${_rest%%:*}"
        local _desc="${_rest#*:}"
        [ "$_desc" = "$_label" ] && _desc=""

        local _key
        case "$_action" in
            q|quit|back|exit) _key="q" ;;
            A|ai|assistant)   _key="A" ;;
            D|diagnose)       _key="D" ;;
            "?"|help)         _key="?" ;;
            _)
                _fzf_items+=("_:${_label}:")
                continue
                ;;
            *)
                _key="${_key_seq[$_ki]:-x}"
                _ki=$(( _ki + 1 ))
                ;;
        esac
        _fzf_items+=("${_key}:${_label}:${_desc}")
        _action_map+=("${_key}=${_action}")
    done

    local _sel
    _sel=$(igor_fzf_pick "$_title" "${_fzf_items[@]}") || return $?

    # Map selected key back to action_id
    local _entry
    for _entry in "${_action_map[@]}"; do
        [ "${_entry%%=*}" = "$_sel" ] && { printf '%s' "${_entry#*=}"; return 0; }
    done
    printf '%s' "$_sel"   # fallback: return raw key if no mapping found
}
