#!/bin/bash
# ==============================================================================
#  IGOR — healing/core.sh
#  Self-healing subsystem core: check discovery, execution, score calculation.
#
#  Provides:
#    health_check_full()         run all checks, update cache, fire alerts
#    calculate_health_score()    read cache → integer 0–100 clamped  (fast, no I/O)
#    validate_configuration()    check critical config files and mounts
#    _healing_discover_checks()  glob healing/checks/ for plugin files
#    _healing_run_check()        source one check file and call run_check()
#
#  Check result cache:
#    $IGOR_DIR/data/alerts/health_cache.txt
#    Format: one line per result — SEVERITY CODE MESSAGE
#
#  Sourced at igor.sh startup (alongside lib/).
#  Overwrites the calculate_health_score() stub defined in igor.sh.
# ==============================================================================

_HEALING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_HEALING_CHECKS_DIR="${IGOR_DIR:-${_HEALING_DIR}/..}/modules"
_HEALING_CACHE_FILE="${IGOR_DIR:-${_HEALING_DIR}/../..}/data/alerts/health_cache.txt"

# Guard: prevent health_check_full from running more than once at startup.
# Set to true by the first call; subsequent calls during the same process skip
# the expensive check run (reads from cache instead). Reset by 'refresh' command.
_HEALING_STARTUP_CHECK_DONE=false

# ── Source healing subsystem dependencies ────────────────────────────────────
source "${_HEALING_DIR}/alerts.sh"
source "${_HEALING_DIR}/patterns.sh"

# Load file locking for concurrent operations
if [ -f "${IGOR_DIR}/core/lib/file_locking.sh" ]; then
    source "${IGOR_DIR}/core/lib/file_locking.sh"
fi

# ── Discover check plugin files ───────────────────────────────────────────────
# Returns space-separated list of check file paths from modules/*/checks/.
# Files starting with _ are skipped (documentation/contract only).
_healing_discover_checks() {
    local checks=()
    for f in "${_HEALING_CHECKS_DIR}"/*/checks/*.sh; do
        [ -f "$f" ] || continue
        [[ "$(basename "$f")" == _* ]] && continue
        checks+=("$f")
    done
    echo "${checks[@]}"
}

# ── Run a single check file ───────────────────────────────────────────────────
# Runs in a subshell to avoid polluting global namespace.
# $1 = path to check file
# Outputs CHECK_RESULT lines to stdout.
_healing_run_check() {
    local check_file="$1"
    (
        # Provide no-op stubs for any lib functions the check might use
        # (subshell loses parent context)
        source "${_HEALING_DIR}/../lib/ui.sh"       2>/dev/null || true
        source "${_HEALING_DIR}/../lib/helpers.sh"  2>/dev/null || true
        source "${_HEALING_DIR}/../lib/config.sh"   2>/dev/null || true
        source "$check_file" 2>/dev/null
        if declare -f run_check &>/dev/null; then
            run_check 2>/dev/null
        fi
    )
}

# ── Run all health checks ─────────────────────────────────────────────────────
# $1 = show_output  (true|false — default false)
# Updates SELF_HEALING_ISSUES global array.
# Writes results to health cache file.
# Fires alert banner if any FAIL or CRITICAL results found.
health_check_full() {
    local show_output="${1:-false}"

    # ── Startup-once guard ────────────────────────────────────────────────────
    # Suppress output (but not cache write) when called a second time at startup.
    # Prevents triple-print if multiple init paths call health_check_full.
    if [ "$_HEALING_STARTUP_CHECK_DONE" = "true" ] && [ "$show_output" = "false" ]; then
        return 0
    fi
    _HEALING_STARTUP_CHECK_DONE=true

    # ── STARTUP_VERBOSE flag: suppress output before the menu if false ────────
    # Set STARTUP_VERBOSE=false in config/defaults.env or config.env for silent mode.
    if [ "${STARTUP_VERBOSE:-true}" = "false" ] && [ "$show_output" = "false" ]; then
        # Silent mode: still update cache, but emit nothing to terminal.
        show_output="silent"
    fi

    mkdir -p "$(dirname "$_HEALING_CACHE_FILE")"
    : > "$_HEALING_CACHE_FILE"

    local all_results=()
    local check_files_str; check_files_str=$(_healing_discover_checks)
    read -ra _check_files <<< "$check_files_str"

    if [ "$show_output" = "true" ]; then
        step "Running health checks..."
        echo ""
    fi
    local _really_show_output="$show_output"
    [ "$show_output" = "silent" ] && _really_show_output="false"

    for check_file in "${_check_files[@]}"; do
        [ -z "$check_file" ] || [ ! -f "$check_file" ] && continue

        local check_name; check_name=$(basename "$check_file" .sh)

        if [ "$_really_show_output" = "true" ]; then
            echo -ne "  ${CYAN}▶${NC} ${check_name}..."
        fi

        local result
        result=$(_healing_run_check "$check_file" 2>/dev/null)

        while IFS= read -r line; do
            [[ "$line" == CHECK_RESULT* ]] || continue
            # Parse: CHECK_RESULT SEVERITY CODE MESSAGE
            local severity code message
            severity=$(echo "$line" | awk '{print $2}')
            code=$(echo "$line" | awk '{print $3}')
            message=$(echo "$line" | cut -d' ' -f4-)
            [ -z "$severity" ] && continue
            echo "${severity} ${code} ${message}" >> "$_HEALING_CACHE_FILE"
            all_results+=("${severity}|${code}|${message}")
        done <<< "$result"

        if [ "$_really_show_output" = "true" ]; then
            echo " done"
        fi
    done

    # ── Update SELF_HEALING_ISSUES global ────────────────────────────────────
    SELF_HEALING_ISSUES=()
    local has_alert=false
    local alert_issues=()

    for r in "${all_results[@]}"; do
        local sev="${r%%|*}" rest="${r#*|}"
        local code="${rest%%|*}" msg="${rest#*|}"

        case "$sev" in
            CRITICAL)
                SELF_HEALING_ISSUES+=("[CRITICAL] ${msg}")
                alert_issues+=("[CRITICAL] ${msg}")
                has_alert=true
                alert_log "CRITICAL" "$code" "$msg"
                ;;
            FAIL)
                SELF_HEALING_ISSUES+=("[FAIL] ${msg}")
                alert_issues+=("[FAIL] ${msg}")
                has_alert=true
                alert_log "FAIL" "$code" "$msg"
                ;;
            WARN)
                SELF_HEALING_ISSUES+=("[WARN] ${msg}")
                ;;
        esac
    done

    # Auto-clear stale alerts when a clean run finds no issues
    if ! $has_alert; then
        alert_banner_clear 2>/dev/null || true
    fi

    SELF_HEALING_LAST_REPAIR="$(date '+%Y-%m-%d %H:%M:%S')"

    # ── Display results ───────────────────────────────────────────────────────
    if [ "$_really_show_output" = "true" ]; then
        echo ""
        local score; score=$(calculate_health_score)
        local score_color="$GRN"
        [ "$score" -lt 80 ] && score_color="$YEL"
        [ "$score" -lt 50 ] && score_color="$RED"

        # Count by severity first so we can show the summary line up top
        local ok_count=0 warn_count=0 fail_count=0 crit_count=0
        for r in "${all_results[@]}"; do
            local sev="${r%%|*}"
            case "$sev" in
                OK)       (( ok_count++ ))   ;;
                WARN)     (( warn_count++ )) ;;
                FAIL)     (( fail_count++ )) ;;
                CRITICAL) (( crit_count++ )) ;;
            esac
        done

        # Summary line — always shown first
        echo -e "  Health score: ${score_color}${score}/100${NC}   ${GRN}✔ ${ok_count} OK${NC}  ${YEL}⚠ ${warn_count} WARN${NC}  ${RED}✘ ${fail_count} FAIL  ✘ ${crit_count} CRITICAL${NC}"
        echo ""

        # Only list non-OK results — OK results are expected and just add noise
        local _has_issues=false
        for r in "${all_results[@]}"; do
            local sev="${r%%|*}" rest="${r#*|}"
            local msg="${rest#*|}"
            case "$sev" in
                WARN)     warn "$msg";                           _has_issues=true ;;
                FAIL)     fail "$msg";                           _has_issues=true ;;
                CRITICAL) echo -e "  ${RED}${BOLD}✘ CRITICAL${NC} ${msg}"; _has_issues=true ;;
            esac
        done

        if ! $_has_issues; then
            echo -e "  ${GRN}All checks passed.${NC}"
        fi

        if $has_alert; then
            echo ""
            warn "Alerts written to pending.log — banner will show on next launch."
        fi
        echo ""

        # Auto-save report
        local _rdir="${REPORTS_DIR:-${IGOR_DIR}/data/reports}"
        mkdir -p "$_rdir" 2>/dev/null || true
        local _rfile="${_rdir}/health_$(date +%Y%m%d_%H%M%S).txt"
        {
            echo "# IGOR Health Report — $(date)"
            echo "# Score: ${score}/100   OK:${ok_count}  WARN:${warn_count}  FAIL:${fail_count}  CRITICAL:${crit_count}"
            echo ""
            cat "$_HEALING_CACHE_FILE" 2>/dev/null
        } > "$_rfile" 2>/dev/null \
            && echo -e "  ${GRN}✔ Report saved: reports/$(basename "$_rfile")${NC}"
        echo ""
    fi

    return 0
}

# ── Calculate health score (fast, reads cache) ────────────────────────────────
# Overwrites the stub defined in igor.sh.
# Returns integer 0–100 (clamped). The raw formula can produce negative values
# with many CRITICAL results — the [ $score -lt 0 ] clamp catches this.
# No subprocesses — reads the cache file directly.
calculate_health_score() {
    if [ ! -f "$_HEALING_CACHE_FILE" ] || [ ! -s "$_HEALING_CACHE_FILE" ]; then
        echo "100"
        return 0
    fi

    local score=100
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local sev="${line%% *}"
        case "$sev" in
            WARN)     (( score -= 5  )) ;;
            FAIL)     (( score -= 15 )) ;;
            CRITICAL) (( score -= 30 )) ;;
        esac
    done < "$_HEALING_CACHE_FILE"

    [ $score -lt 0 ] && score=0
    echo "$score"
}

# ── Validate critical configuration ──────────────────────────────────────────
# Checks files, mounts, and env vars that must exist for Igor to work.
# Updates SELF_HEALING_CONFIG_DRIFT global.
validate_configuration() {
    local issues=()

    [ ! -f "${IGOR_DIR:-}/config/stacks/nextcloud/docker-compose.yml" ] && \
        issues+=("docker-compose.yml not found in config/stacks/nextcloud/")

    [ ! -f "${IGOR_DIR:-}/db.env" ] && \
        issues+=("db.env missing — services cannot start")

    if ! mount | grep -q "${HD_MOUNT:-/mnt/nextclouddata}" 2>/dev/null; then
        issues+=("HD_MOUNT (${HD_MOUNT:-/mnt/nextclouddata}) is not mounted")
    fi

    if [ -n "${NC_DATA:-}" ] && [ ! -d "$NC_DATA" ]; then
        issues+=("NC_DATA directory does not exist: $NC_DATA")
    fi

    SELF_HEALING_CONFIG_DRIFT=${#issues[@]}
    echo "${issues[@]}"
}
