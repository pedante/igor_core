#!/bin/bash
# IGOR — recovery/apps.sh
# Supervised app install + App Risk Register.
# Wraps occ app:install with a 90-second observation window, RAM pre-check,
# and persistent risk profiling.
#
# App Risk Register: ${IGOR_DIR}/app_risk/{app_name}.risk
# Format: KEY: VALUE pairs (same as healing/patterns.sh .pattern files)
#
# Public functions:
#   supervised_app_install APP_NAME   — full supervised install flow
#   app_monitor_window APP_NAME [S]   — 90s observation (returns 0/1/2)
#   app_risk_register_get APP_NAME    — print risk profile
#   app_risk_register_record APP_NAME STATUS [ISSUES] — write/update .risk file
#   _mod_apps_is_heavy APP_NAME       — check HEAVY_APPS list
#   _mod_apps_pre_install_checks      — RAM + disk pre-flight

APP_RISK_DIR="${IGOR_DIR}/app_risk"

# Return success only when the owning module is active.  Without the lifecycle
# loader there is no trustworthy ownership state, so fail closed.
_mod_apps_nextcloud_active() {
    if declare -f igor_has_module >/dev/null 2>&1; then
        igor_has_module nextcloud_docker
    else
        return 1
    fi
}

# ── supervised_app_install APP_NAME ──────────────────────────────────────────
supervised_app_install() {
    local app_name="${1:-}"
    [ -z "$app_name" ] && { fail "App name required"; return 1; }
    _mod_apps_nextcloud_active || {
        warn "Nextcloud app installation is unavailable: nextcloud_docker is disabled"
        return 1
    }

    local RED='\033[0;31m' GRN='\033[0;32m' YEL='\033[1;33m'
    local CYAN='\033[0;36m' MAG='\033[0;35m' BOLD='\033[1m' NC='\033[0m'

    echo ""
    echo -e "  ${BOLD}Supervised Install: ${CYAN}${app_name}${NC}"
    echo -e "  ${CYAN}$(printf '─%.0s' {1..50})${NC}"

    # ── Show existing risk profile ────────────────────────────────────────────
    if [ -f "${APP_RISK_DIR}/${app_name}.risk" ]; then
        echo ""
        echo -e "  ${YEL}⚠ Risk profile found for ${app_name}:${NC}"
        app_risk_register_get "$app_name"
        echo ""
        local prev_fail; prev_fail=$(_mod_apps_risk_get_field "$app_name" "FAIL_COUNT")
        if [ "${prev_fail:-0}" -gt 0 ]; then
            warn "This app has failed ${prev_fail} time(s) on this system."
            confirm "Install anyway?" || return 1
        fi
    fi

    # ── Heavy app warning ─────────────────────────────────────────────────────
    local is_heavy=false
    _mod_apps_is_heavy "$app_name" && is_heavy=true

    if $is_heavy; then
        echo ""
        warn "HEAVY APP — this app requires significant RAM on install/init."
        local free_mb; free_mb=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
        info "Available RAM: ${free_mb}MB"
        if [ "$free_mb" -lt 300 ]; then
            warn "Less than 300MB free — risk of OOM on Pi 3."
        fi
        if confirm "This is a resource-heavy app. Install with safe mode (3-min observation)?"; then
            local SUPERVISED_INSTALL_WINDOW=180  # safe mode = 3 minutes for heavy apps
        else
            confirm "Install with standard observation (${SUPERVISED_INSTALL_WINDOW:-90}s)?" || \
                { echo "  Cancelled."; return 1; }
            # SUPERVISED_INSTALL_WINDOW stays at the configured default
        fi
    fi

    # ── Pre-install checks ────────────────────────────────────────────────────
    _mod_apps_pre_install_checks || return 1

    # ── Config backup before install ──────────────────────────────────────────
    step "Taking config snapshot before install..."
    declare -f config_backup_auto &>/dev/null && \
        config_backup_auto "pre-install:${app_name}" 2>/dev/null || true

    # ── Snapshot current app list ─────────────────────────────────────────────
    local before_json; before_json=$(docker compose exec -T -u www-data app \
        php occ app:list --output=json 2>/dev/null) || before_json="{}"

    # ── Confirm install ───────────────────────────────────────────────────────
    echo ""
    confirm "Install ${app_name}?" || { echo "  Cancelled."; return 1; }

    # ── Run install ───────────────────────────────────────────────────────────
    step "Installing ${app_name}..."
    local install_out; install_out=$(docker compose exec -T -u www-data app \
        php occ app:install "$app_name" 2>&1)
    local install_rc=$?

    echo "$install_out" | head -5

    # If install returns non-zero but app appears in list, treat as install+disabled
    local installed_ok=false
    if [ $install_rc -eq 0 ]; then
        installed_ok=true
    else
        # Some apps return non-zero but are still installed (just disabled)
        if docker compose exec -T -u www-data app php occ app:list 2>/dev/null | \
               grep -q "$app_name"; then
            warn "Install returned non-zero but app is present — trying to enable."
            docker compose exec -T -u www-data app php occ app:enable "$app_name" 2>/dev/null && \
                installed_ok=true || true
        fi
    fi

    if ! $installed_ok; then
        fail "Install failed (exit ${install_rc})."
        app_risk_register_record "$app_name" "FAIL" "install_failed"
        declare -f journal_record &>/dev/null && \
            journal_record "menu:apps" "app_install" "CHANGE" \
                "occ app:install ${app_name}" "FAIL" "exit:${install_rc}"
        return 1
    fi

    ok "App installed."

    # ── Enable if needed ──────────────────────────────────────────────────────
    local is_enabled; is_enabled=$(docker compose exec -T -u www-data app \
        php occ app:list --output=json 2>/dev/null | \
        python3 -c "
import json,sys
d=json.load(sys.stdin)
print('yes' if '${app_name}' in d.get('enabled',{}) else 'no')
" 2>/dev/null || echo "no")

    if [ "$is_enabled" != "yes" ]; then
        step "Enabling ${app_name}..."
        docker compose exec -T -u www-data app php occ app:enable "$app_name" 2>/dev/null || true
    fi

    # ── Observation window ────────────────────────────────────────────────────
    local window="${SUPERVISED_INSTALL_WINDOW:-90}"
    echo ""
    echo -e "  ${CYAN}Observation window: ${window}s — watching for crashes/OOM...${NC}"

    local monitor_result
    app_monitor_window "$app_name" "$window"
    monitor_result=$?

    # ── Record risk profile ───────────────────────────────────────────────────
    local obs_result obs_issues
    case $monitor_result in
        0) obs_result="clean";    obs_issues="none" ;;
        1) obs_result="warnings"; obs_issues="see_monitor_log" ;;
        2) obs_result="fatal";    obs_issues="SIGSEGV_or_OOM" ;;
    esac

    app_risk_register_record "$app_name" \
        "$( [ $monitor_result -le 1 ] && echo OK || echo FAIL)" \
        "$obs_issues"

    # ── Journal ───────────────────────────────────────────────────────────────
    declare -f journal_record &>/dev/null && \
        journal_record "menu:apps" "app_install" "CHANGE" \
            "occ app:install ${app_name}" \
            "$( [ $monitor_result -le 1 ] && echo OK || echo FAIL)" \
            "observation:${obs_result}"

    # ── Notify hook — app_install ─────────────────────────────────────────────
    local _install_status; _install_status="$( [ $monitor_result -le 1 ] && echo "OK (${obs_result})" || echo "FATAL (${obs_result})" )"
    declare -f notify_event &>/dev/null && \
        notify_event "app_install" \
            "Supervised install: ${app_name} — ${_install_status}" \
            "App Installed: ${app_name}" \
        2>/dev/null || true

    # ── Update app list snapshot for journal diff ────────────────────────────
    declare -f journal_detect_app_changes &>/dev/null && \
        journal_detect_app_changes 2>/dev/null || true

    # ── Outcome ───────────────────────────────────────────────────────────────
    echo ""
    if [ $monitor_result -eq 0 ]; then
        ok "${app_name} installed and stable."
    elif [ $monitor_result -eq 1 ]; then
        warn "${app_name} installed but warnings detected during observation. Check logs."
    else
        fail "${app_name} installed but FATAL errors detected (SIGSEGV/OOM)."
        warn "Rollback available: bash igor.sh → V → 1 (Journal Rollback)"
        warn "Or restore config backup: bash igor.sh → V → 2"
        return 1
    fi
}

# ── app_monitor_window APP_NAME [SECS=90] ─────────────────────────────────────
# Polls docker compose logs for fatal patterns every 5 seconds.
# Returns: 0=clean  1=warnings  2=fatal
app_monitor_window() {
    local app_name="$1"
    local secs="${2:-90}"
    _mod_apps_nextcloud_active || return 1
    local RED='\033[0;31m' GRN='\033[0;32m' YEL='\033[1;33m'
    local CYAN='\033[0;36m' NC='\033[0m'

    local iterations=$(( secs / 5 ))
    local fatal_found=false
    local warn_found=false
    local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_i=0

    for i in $(seq 1 "$iterations"); do
        sleep 5

        local log_chunk; log_chunk=$(docker compose logs --tail=15 app 2>/dev/null)

        # Fatal patterns — immediate fail
        if echo "$log_chunk" | grep -qiE 'SIGSEGV|SIGBUS|Segmentation fault|OOM killer|Out of memory|Killed process'; then
            echo ""
            fail "FATAL: OOM/SIGSEGV detected in app container!"
            echo "$log_chunk" | grep -iE 'SIGSEGV|OOM|Killed|Segmentation' | tail -3
            fatal_found=true
            break
        fi

        # Warning patterns
        if echo "$log_chunk" | grep -qiE 'PHP Fatal error|Allowed memory size|maximum execution time'; then
            echo ""
            warn "PHP Fatal error detected during observation:"
            echo "$log_chunk" | grep -iE 'PHP Fatal|Allowed memory|maximum execution' | tail -3
            warn_found=true
        fi

        # Container restart check
        local restart_count; restart_count=$(docker inspect --format='{{.RestartCount}}' \
            "$(docker compose ps -q app 2>/dev/null)" 2>/dev/null || echo 0)
        if [ "${restart_count:-0}" -gt 1 ]; then
            fail "App container has restarted ${restart_count} times!"
            warn_found=true
        fi

        printf "\r  %s Observing %s... [%ds/%ds]" \
            "${spinner[$spin_i]}" "$app_name" "$(( i * 5 ))" "$secs"
        spin_i=$(( (spin_i + 1) % ${#spinner[@]} ))
    done

    echo ""

    if $fatal_found; then
        fail "Fatal errors detected — consider rollback."
        return 2
    elif $warn_found; then
        warn "Warnings detected during observation. Monitor logs."
        return 1
    else
        ok "Observation complete — no issues detected."
        return 0
    fi
}

# ── app_risk_register_get APP_NAME ────────────────────────────────────────────
app_risk_register_get() {
    local app_name="${1:-}"
    _mod_apps_nextcloud_active || return 1
    local CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'
    local risk_file="${APP_RISK_DIR}/${app_name}.risk"

    if [ ! -f "$risk_file" ]; then
        echo "  (no risk profile for ${app_name})"
        return 1
    fi

    echo ""
    echo -e "  ${BOLD}Risk profile: ${CYAN}${app_name}${NC}"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        echo "  $line"
    done < "$risk_file"
}

# ── app_risk_register_record APP_NAME STATUS [ISSUES] ─────────────────────────
# STATUS: OK | FAIL | PARTIAL
app_risk_register_record() {
    local app_name="${1:-}" status="${2:-OK}" issues="${3:-none}"
    _mod_apps_nextcloud_active || return 1
    [ -z "$app_name" ] && return 1

    mkdir -p "$APP_RISK_DIR"
    local risk_file="${APP_RISK_DIR}/${app_name}.risk"
    local now; now=$(date "+%Y-%m-%d %H:%M:%S")

    # Gather metadata
    local nc_ver; nc_ver=$(docker compose exec -T -u www-data app \
        php occ status 2>/dev/null | grep -oP "version:\s+\K[\d.]+" | head -1 || echo "unknown")
    local app_ver; app_ver=$(docker compose exec -T -u www-data app \
        php occ app:list --output=json 2>/dev/null | \
        python3 -c "
import json,sys
d=json.load(sys.stdin)
enabled=d.get('enabled',{})
if '${app_name}' in enabled:
    v=enabled['${app_name}']
    print(v if isinstance(v,str) else 'installed')
else: print('unknown')
" 2>/dev/null || echo "unknown")
    local ram_free; ram_free=$(awk '/MemAvailable/ {printf "%dMB", $2/1024}' /proc/meminfo 2>/dev/null || echo "?")

    if [ ! -f "$risk_file" ]; then
        # New profile
        cat > "$risk_file" <<RISK
APP: ${app_name}
INSTALL_DATE: ${now}
INSTALL_STATUS: ${status}
NC_VERSION_AT_INSTALL: ${nc_ver}
APP_VERSION_AT_INSTALL: ${app_ver}
RAM_FREE_AT_INSTALL: ${ram_free}
OBSERVATION_RESULT: $( [ "$status" = "OK" ] && echo "clean" || echo "failed" )
OBSERVATION_ISSUES: ${issues}
LAST_UPDATE_DATE: ${now}
LAST_UPDATE_STATUS: ${status}
INSTALL_COUNT: 1
FAIL_COUNT: $( [ "$status" = "OK" ] && echo "0" || echo "1" )
NOTES: $( _mod_apps_is_heavy "$app_name" && echo "Heavy app." || echo "" )
RISK
    else
        # Update existing profile
        local install_count; install_count=$(_mod_apps_risk_get_field "$app_name" "INSTALL_COUNT")
        local fail_count;    fail_count=$(_mod_apps_risk_get_field "$app_name" "FAIL_COUNT")
        install_count=$(( ${install_count:-0} + 1 ))
        [ "$status" != "OK" ] && fail_count=$(( ${fail_count:-0} + 1 ))

        sed -i \
            -e "s|^LAST_UPDATE_DATE:.*|LAST_UPDATE_DATE: ${now}|" \
            -e "s|^LAST_UPDATE_STATUS:.*|LAST_UPDATE_STATUS: ${status}|" \
            -e "s|^INSTALL_COUNT:.*|INSTALL_COUNT: ${install_count}|" \
            -e "s|^FAIL_COUNT:.*|FAIL_COUNT: ${fail_count}|" \
            -e "s|^OBSERVATION_ISSUES:.*|OBSERVATION_ISSUES: ${issues}|" \
            "$risk_file" 2>/dev/null || true
    fi
}

# ── _mod_apps_risk_get_field APP_NAME FIELD ───────────────────────────────────
_mod_apps_risk_get_field() {
    local app_name="$1" field="$2"
    local risk_file="${APP_RISK_DIR}/${app_name}.risk"
    [ -f "$risk_file" ] || return 1
    grep -m1 "^${field}:" "$risk_file" 2>/dev/null | cut -d: -f2- | sed 's/^ *//'
}

# ── _mod_apps_is_heavy APP_NAME ───────────────────────────────────────────────
# Returns 0 (true) if app is in the HEAVY_APPS list.
_mod_apps_is_heavy() {
    local app_name="${1:-}"
    local heavy="${HEAVY_APPS:-memories recognize AppAPI onlyoffice richdocuments fulltextsearch}"
    for h in $heavy; do
        [ "$h" = "$app_name" ] && return 0
    done
    return 1
}

# ── _mod_apps_pre_install_checks ─────────────────────────────────────────────
_mod_apps_pre_install_checks() {
    local YEL='\033[1;33m' NC='\033[0m'

    # RAM check
    local free_mb; free_mb=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 999)
    if [ "$free_mb" -lt 100 ]; then
        warn "Very low RAM: ${free_mb}MB available."
        confirm "Continue with less than 100MB RAM free?" || return 1
    fi

    # Disk check (external drive)
    if [ -n "${NC_DATA:-}" ] && mountpoint -q "$(dirname "$NC_DATA")" 2>/dev/null; then
        local disk_free; disk_free=$(df -m "$NC_DATA" 2>/dev/null | awk 'NR==2{print $4}' || echo 9999)
        if [ "$disk_free" -lt 500 ]; then
            warn "Less than 500MB free on NC data drive (${disk_free}MB)."
            confirm "Continue anyway?" || return 1
        fi
    fi

    # Confirm NC is running
    local http_code; http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 3 "http://localhost:${IGOR_WEB_PORT:-8080}/status.php" 2>/dev/null || echo "000")
    if [ "$http_code" != "200" ]; then
        warn "Nextcloud may not be running (HTTP ${http_code})."
        confirm "Continue with app install?" || return 1
    fi

    return 0
}

# ── app_risk_register_list ────────────────────────────────────────────────────
# List all risk profiles.
app_risk_register_list() {
    _mod_apps_nextcloud_active || return 1
    local BOLD='\033[1m' CYAN='\033[0;36m' GRN='\033[0;32m' RED='\033[0;31m' NC='\033[0m'

    echo ""
    printf "  ${BOLD}%-25s  %-12s  %-6s  %-6s  %s${NC}\n" \
        "APP" "LAST STATUS" "INST" "FAIL" "LAST DATE"
    printf "  %s\n" "$(printf '─%.0s' {1..65})"

    local count=0
    mkdir -p "$APP_RISK_DIR"
    for f in "${APP_RISK_DIR}"/*.risk; do
        [ -f "$f" ] || continue
        local app; app=$(basename "$f" .risk)
        local status; status=$(_mod_apps_risk_get_field "$app" "LAST_UPDATE_STATUS")
        local inst;   inst=$(_mod_apps_risk_get_field "$app" "INSTALL_COUNT")
        local fail;   fail=$(_mod_apps_risk_get_field "$app" "FAIL_COUNT")
        local dt;     dt=$(_mod_apps_risk_get_field "$app" "LAST_UPDATE_DATE")
        local col="$GRN"
        [ "${fail:-0}" -gt 0 ] && col="$RED"
        printf "  ${col}%-25s  %-12s  %-6s  %-6s${NC}  %s\n" \
            "$app" "${status:-?}" "${inst:-?}" "${fail:-?}" "${dt:-?}"
        (( count++ ))
    done

    if [ $count -eq 0 ]; then
        echo "  (no risk profiles yet — install apps via menu V → 5)"
    fi
    echo ""
}
