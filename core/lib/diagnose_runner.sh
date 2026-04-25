#!/bin/bash
# =============================================================================
#  DIAGNOSE RUNNER — core/lib/diagnose_runner.sh
#
#  Hook-based diagnostic aggregator. Replaces hardcoded calls into diagnose/.
#  Each loaded module contributes checks via its __diagnose() hook and via
#  check scripts in modules/<name>/checks/*.sh.
#
#  Check output protocol (one line per check):
#    CHECK:<name>:<status>:<message>
#    status values: ok | warn | fail | skip
#
#  Public API:
#    igor_diagnose_all()      — run all checks, print results
#    igor_diagnose_collect()  — run all checks, return raw lines (no print)
#    igor_diagnose_display()  — render a CHECK: line array to terminal
#    igor_diagnose_score()    — return 0-100 score from a set of CHECK: lines
# =============================================================================

# Colour aliases (safe even if ui.sh not loaded yet)
_DR_GRN="${GRN:-\033[0;32m}"
_DR_YEL="${YEL:-\033[1;33m}"
_DR_RED="${RED:-\033[0;31m}"
_DR_DIM="${DIM:-\033[2m}"
_DR_NC="${NC:-\033[0m}"
_DR_BOLD="${BOLD:-\033[1m}"

# ---------------------------------------------------------------------------
# igor_diagnose_collect [--timeout <seconds>]
#
#   Run all diagnostic sources and return raw CHECK: lines on stdout.
#   Sources (in order):
#     1. igor_run_all_hooks "diagnose" — module __diagnose() functions
#     2. modules/*/checks/*.sh         — convention-based check plugins
#
#   Each source gets its own timeout (default 60s for hooks, 30s for scripts).
#   Malformed output lines are silently dropped.
# ---------------------------------------------------------------------------
igor_diagnose_collect() {
    local _hook_timeout=60
    local _script_timeout=30

    while [[ "$1" == --* ]]; do
        case "$1" in
            --timeout) _hook_timeout="$2"; _script_timeout="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local _results=()
    local _fn _out _line

    # ── Source 1: module __diagnose() hooks ───────────────────────────────
    if declare -f igor_get_hooks >/dev/null 2>&1; then
        for _fn in $(igor_get_hooks "diagnose"); do
            declare -f "$_fn" >/dev/null 2>&1 || continue
            _out=$(timeout "$_hook_timeout" bash -c \
                "$(declare -f "$_fn"); $_fn" 2>/dev/null)
            while IFS= read -r _line; do
                [[ "$_line" =~ ^CHECK:[^:]+:(ok|warn|fail|skip): ]] && \
                    _results+=("$_line")
            done <<< "$_out"
        done
    fi

    # ── Source 2: modules/*/checks/*.sh convention-based plugins ──────────
    local _modules_root="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)}/modules"
    if [ -d "$_modules_root" ]; then
        local _check_script
        for _check_script in "${_modules_root}"/*/checks/*.sh; do
            [ -f "$_check_script" ] || continue
            bash -n "$_check_script" 2>/dev/null || continue   # skip broken scripts
            _out=$(timeout "$_script_timeout" bash "$_check_script" 2>/dev/null)
            while IFS= read -r _line; do
                [[ "$_line" =~ ^CHECK:[^:]+:(ok|warn|fail|skip): ]] && \
                    _results+=("$_line")
            done <<< "$_out"
        done
    fi

    printf '%s\n' "${_results[@]}"
}

# ---------------------------------------------------------------------------
# igor_diagnose_display [CHECK: lines on stdin or as args]
#
#   Render CHECK: lines to the terminal with colour coding and counts.
#   Reads from stdin if no args given.
# ---------------------------------------------------------------------------
igor_diagnose_display() {
    local _lines=()

    if [ $# -gt 0 ]; then
        _lines=("$@")
    else
        local _l
        while IFS= read -r _l; do
            [ -n "$_l" ] && _lines+=("$_l")
        done
    fi

    local _ok=0 _warn=0 _fail=0 _skip=0

    echo ""
    echo -e "${_DR_BOLD}  Diagnostic Results${_DR_NC}"
    echo -e "  ${_DR_DIM}────────────────────────────────────────────────${_DR_NC}"

    local _entry _name _status _msg _color _icon
    for _entry in "${_lines[@]}"; do
        IFS=':' read -r _ _name _status _msg <<< "$_entry"
        case "$_status" in
            ok)   _color="$_DR_GRN"; _icon="✔"; (( _ok++   )) || true ;;
            warn) _color="$_DR_YEL"; _icon="⚠"; (( _warn++ )) || true ;;
            fail) _color="$_DR_RED"; _icon="✗"; (( _fail++ )) || true ;;
            skip) _color="$_DR_DIM"; _icon="–"; (( _skip++ )) || true ;;
            *)    _color="$_DR_DIM"; _icon="?"; ;;
        esac
        printf "  ${_color}${_icon}${_DR_NC}  %-35s %b\n" \
            "${_name//_/ }:" "${_color}${_msg}${_DR_NC}"
    done

    if [ ${#_lines[@]} -eq 0 ]; then
        echo -e "  ${_DR_DIM}No checks ran — no modules loaded or no checks registered${_DR_NC}"
    fi

    echo -e "  ${_DR_DIM}────────────────────────────────────────────────${_DR_NC}"
    printf "  %b%d ok%b  │  %b%d warn%b  │  %b%d fail%b  │  %b%d skipped%b\n" \
        "$_DR_GRN" "$_ok"   "$_DR_NC" \
        "$_DR_YEL" "$_warn" "$_DR_NC" \
        "$_DR_RED" "$_fail" "$_DR_NC" \
        "$_DR_DIM" "$_skip" "$_DR_NC"
    echo ""
}

# ---------------------------------------------------------------------------
# igor_diagnose_score <CHECK: lines...>
#
#   Return a 0-100 health score based on check results:
#     fail  → -15 pts each
#     warn  → -5 pts each
#     skip  → neutral
#   Floor: 0. Prints score as integer.
# ---------------------------------------------------------------------------
igor_diagnose_score() {
    local _score=100
    local _line _status

    for _line in "$@"; do
        IFS=':' read -r _ _ _status _ <<< "$_line"
        case "$_status" in
            fail) (( _score -= 15 )) || true ;;
            warn) (( _score -= 5  )) || true ;;
        esac
    done

    [ $_score -lt 0 ] && _score=0
    echo "$_score"
}

# ---------------------------------------------------------------------------
# igor_diagnose_all [--timeout <seconds>] [--no-fallback]
#
#   Convenience: collect → display → return exit code.
#   Exit 0 if all checks ok/skipped, 1 if any warn, 2 if any fail.
#
#   --no-fallback: don't fall back to the legacy diagnose/ module even if
#                  no module hooks are registered. Default: fall back.
# ---------------------------------------------------------------------------
igor_diagnose_all() {
    local _timeout=60
    local _no_fallback=false
    while [[ "${1:-}" == --* ]]; do
        case "$1" in
            --timeout)     _timeout="$2"; shift 2 ;;
            --no-fallback) _no_fallback=true; shift ;;
            *) shift ;;
        esac
    done

    local _raw_lines
    mapfile -t _raw_lines < <(igor_diagnose_collect --timeout "$_timeout")

    if [ ${#_raw_lines[@]} -eq 0 ] && [ "$_no_fallback" = "false" ]; then
        # No module hooks produced output — fall back to legacy diagnose module
        if [ -f "${IGOR_DIR:-}/modules/diagnose.sh" ]; then
            echo -e "  ${_DR_DIM}[diagnose_runner] No module checks registered — " \
                    "falling back to legacy diagnose/...${_DR_NC}" >&2
            source "${IGOR_DIR}/core/diagnose/core.sh" 2>/dev/null || true
            declare -f menu_diagnose >/dev/null 2>&1 && menu_diagnose
            return $?
        fi
    fi

    igor_diagnose_display "${_raw_lines[@]}"

    local _any_fail=0 _any_warn=0 _l _st
    for _l in "${_raw_lines[@]}"; do
        IFS=':' read -r _ _ _st _ <<< "$_l"
        [ "$_st" = "fail" ] && _any_fail=1
        [ "$_st" = "warn" ] && _any_warn=1
    done

    [ "$_any_fail" -eq 1 ] && return 2
    [ "$_any_warn" -eq 1 ] && return 1
    return 0
}
