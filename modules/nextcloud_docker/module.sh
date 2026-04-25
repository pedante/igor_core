#!/bin/bash
# =============================================================================
#  MODULE: nextcloud_docker
#  Manages Nextcloud on Docker: nginx, PostgreSQL, Redis, Cloudflare Tunnel
# =============================================================================

# Source Nextcloud-specific sub-modules
source "${IGOR_DIR}/modules/nextcloud_docker/menus/tunnel_integration.sh"
source "${IGOR_DIR}/modules/nextcloud_docker/menus/recovery.sh"

# ── Shared HTTP helper ────────────────────────────────────────────────────────
# Returns the HTTP status code for a Nextcloud URL path.
# Usage: _nc_check_http [path] [timeout_secs]
# Default: path=/status.php  timeout=4
_nc_check_http() {
    local path="${1:-/status.php}"
    local timeout="${2:-4}"
    curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$timeout" \
        "http://localhost:${NEXTCLOUD_HTTP_PORT:-8080}${path}" 2>/dev/null
}

# REQUIRED — called at igor startup
nextcloud_docker__register() {
    igor_register_hook "health"         "nextcloud_docker__health"
    igor_register_hook "diagnose"       "nextcloud_docker__diagnose"
    igor_register_hook "notify"         "nextcloud_docker__notify"
    igor_register_hook "mailcmd"        "nextcloud_docker__mailcmd"
    igor_register_hook "ai_context"     "nextcloud_docker__ai_context"
    igor_register_hook "ai_tools"       "nextcloud_docker__ai_tools"
    igor_register_hook "ai_tiers"       "nextcloud_docker__ai_tiers"
    igor_register_hook "ai_knowledge"   "nextcloud_docker__ai_knowledge"
    igor_register_hook "ai_patterns"    "nextcloud_docker__ai_patterns"
    igor_register_hook "recovery"       "nextcloud_docker__recovery"
    igor_register_hook "backup"         "nextcloud_docker__backup"
    igor_register_hook "restore"        "nextcloud_docker__restore"
    igor_register_hook "status_line"    "nextcloud_docker__status_line"
    igor_register_hook "app_diagnose"   "nextcloud_docker__app_diagnose"
    # ── Core dispatch hooks (extracted from core/ — registered by module) ──────
    igor_register_hook "health_gate"    "_nc_health_gate"
    igor_register_hook "role_check_app" "_nc_check_role_app"
    igor_register_hook "alert_hook"     "_nc_alert_hook"
    igor_register_hook "config_validate" "_nc_validate_config"
    igor_register_hook "rollback_handler" "_nc_rollback_dispatch"
    igor_register_hook "menu_header"      "nextcloud_docker__menu_header"
    igor_register_hook "ai_capabilities" "nextcloud_docker__ai_capabilities"
    igor_register_hook "notify_events"   "nextcloud_docker__notify_events"

    # ── Main-menu dispatch entries ────────────────────────────────────────────
    igor_register_menu_item "S" "SETUP & INSTALL — wizard, storage, tunnel, stack" \
        "module" "setup_infra"      "menu_setup_infra"
    igor_register_menu_item "0" "WIZARD — First-run installation" \
        "module" "install"          "menu_install"
    igor_register_menu_item "1" "STATUS — Quick dashboard" \
        "module" "nextcloud_docker" "menu_status"
    igor_register_menu_item "2" "SERVICES — Start/stop/restart" \
        "module" "services"         "menu_services"
    igor_register_menu_item "3" "APPS — Nextcloud app management" \
        "module" "apps"             "menu_apps"
    igor_register_menu_item "4" "MAINTENANCE — Scan, repair, upgrade" \
        "module" "maintenance"      "menu_maintenance"
    igor_register_menu_item "5" "CONFIGURE — nginx, limits, passwords" \
        "module" "editor"           "menu_editor"
    igor_register_menu_item "6" "DIAGNOSE — Network, routing, diagnostics" \
        "module" "network"          "menu_network"
    igor_register_menu_item "7" "INFO — Architecture, guide, internals" \
        "module" "info"             "menu_info"
    return 0
}

# Hook: menu_header — returns a one-line section title for the fzf main menu.
# Fast path: ≤3 checks, total budget ≤150ms. No occ, no compose overhead.
# States (priority order — worst shown first):
#   NOT INSTALLED  — no nextcloud docker volumes found
#   STACK STOPPED  — volumes exist but 0 containers running
#   DEGRADED       — some required containers missing
#   UNREACHABLE    — all containers up, HTTP probe failed
#   MAINTENANCE    — HTTP 200 but status.php reports maintenance=true
#   OK             — healthy, return display_name
nextcloud_docker__menu_header() {
    local _port="${NEXTCLOUD_HTTP_PORT:-8080}"
    local _pfx="Nextcloud"

    # Check 1: docker volumes exist? (~10ms)
    if ! docker volume ls -q 2>/dev/null | grep -q "nextcloud"; then
        echo "${_pfx}  ·  not installed — [S] to set up"
        return 0
    fi

    # Check 2: containers running? (single docker ps call, ~40ms)
    local _running_names
    _running_names=$(docker ps --filter "name=nextcloud" --format '{{.Names}}' 2>/dev/null)
    local _total
    _total=$(echo "$_running_names" | grep -c . 2>/dev/null || echo 0)

    if [ "${_total:-0}" -eq 0 ]; then
        echo "${_pfx}  ·  stack stopped — [2] SERVICES → START ALL"
        return 0
    fi

    local _missing=""
    local _svc
    for _svc in app web db redis cron; do
        echo "$_running_names" | grep -q "nextcloud-${_svc}" || _missing+="${_svc} "
    done
    if [ -n "${_missing}" ]; then
        echo "${_pfx}  ·  degraded — missing: ${_missing% } — [6] DIAGNOSE"
        return 0
    fi

    # Check 3: HTTP probe + maintenance flag (500ms cap — Pi localhost needs headroom)
    local _status_json
    _status_json=$(curl -s --max-time 0.5 \
        "http://localhost:${_port}/status.php" 2>/dev/null)

    if [ -z "$_status_json" ]; then
        echo "${_pfx}  ·  containers up, HTTP not responding — [6] DIAGNOSE"
        return 0
    fi

    if echo "$_status_json" | grep -q '"maintenance":true'; then
        echo "${_pfx}  ·  maintenance mode on — [5] CONFIGURE to disable"
        return 0
    fi

    echo "Nextcloud Docker Stack"
    return 0
}

# STATUS — thin wrapper combining services status and a quick health check.
# Dispatched from main_menu() key 1.
menu_status() {
    _igor_load_module "services" 2>/dev/null || true
    _igor_load_module "network"  2>/dev/null || true
    clear
    if declare -f header &>/dev/null; then header; fi
    if declare -f breadcrumb &>/dev/null; then breadcrumb "Igor" "1: Status"; fi
    echo ""
    if declare -f _mod_services_status &>/dev/null; then
        _mod_services_status
    else
        warn "Services module not loaded"
    fi
    echo ""
    if declare -f _mod_network_health_check &>/dev/null; then
        _mod_network_health_check
    else
        warn "Network module not loaded"
    fi
    if declare -f pause &>/dev/null; then pause; fi
}

# Hook: app_diagnose — Phase 5 application-layer checks for the diagnose subsystem.
# Called in-process (not via igor_run_all_hooks) so _diag_emit and _DIAG_RESULTS
# remain accessible. _nc_diag_phase_5 is defined in this module (below).
nextcloud_docker__app_diagnose() {
    local deep="${1:-false}"
    _nc_diag_phase_5 "$deep"
}

# ── Health gate check (replaces hardcoded status.php in diagnose/core.sh) ─────
# Called in-process by _diag_gate_check_app_responding() via health_gate hook.
# Returns 0 if Nextcloud HTTP endpoint responds with 200, 1 otherwise.
_nc_health_gate() {
    local port="${NEXTCLOUD_HTTP_PORT:-${IGOR_WEB_PORT:-8080}}"
    local code
    code=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 8 \
        "http://localhost:${port}/status.php" 2>/dev/null)
    [ "$code" = "200" ]
}

# ── Alert hook (replaces alert_nextcloud() from core/healing/alerts.sh) ───────
# Called in-process by alert_log() via alert_hook dispatch on CRITICAL/FAIL.
# $1=severity $2=code $3=message
_nc_alert_hook() {
    local severity="$1" code="$2" message="$3"
    local nc_user="${NEXTCLOUD_ADMIN_USER:-}"
    [ -z "$nc_user" ] && return 0
    docker compose exec -T -u www-data app php occ \
        notification:generate "$nc_user" "IGOR Health Alert" \
        --long-message "[${severity}] ${code}: ${message}" \
        2>/dev/null || true
}

# ── Config validator (replaces NC vars removed from core/lib/config.sh) ───────
# Called in igor.sh after modules are loaded via config_validate hook dispatch.
_nc_validate_config() {
    [ -z "${NEXTCLOUD_ADMIN_USER:-}" ]     && \
        echo "  [igor] WARNING: NEXTCLOUD_ADMIN_USER not set" >&2
    [ -z "${NEXTCLOUD_ADMIN_PASSWORD:-}" ] && \
        echo "  [igor] WARNING: NEXTCLOUD_ADMIN_PASSWORD not set" >&2
    [ -z "${NEXTCLOUD_TRUSTED_DOMAINS:-}" ] && \
        echo "  [igor] WARNING: NEXTCLOUD_TRUSTED_DOMAINS not set — Nextcloud will reject requests" >&2
}

# ── Journal rollback dispatch (replaces occ cases in core/recovery/journal.sh) ─
# Called by journal.sh rollback when action type needs undo.
# Echoes the undo command to stdout. Returns 1 if action is not undoable.
# $1=action  $2=original_cmd
_nc_rollback_dispatch() {
    local action="$1" cmd="$2"
    case "$action" in
        app_enable)
            echo "docker compose exec -T -u www-data app php occ app:disable ${cmd}"
            return 0
            ;;
        app_disable)
            echo "docker compose exec -T -u www-data app php occ app:enable ${cmd}"
            return 0
            ;;
        app_install)
            echo "docker compose exec -T -u www-data app php occ app:remove ${cmd%%|*}"
            return 0
            ;;
        occ_exec)
            if [[ "$cmd" == *"maintenance:mode --on"* ]]; then
                echo "${cmd//--on/--off}"
                return 0
            elif [[ "$cmd" == *"maintenance:mode --off"* ]]; then
                echo "${cmd//--off/--on}"
                return 0
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# ── Phase 3: app role checks (moved from core/diagnose/phases.sh) ─────────────
# Called in-process by phase 3 hook dispatch via role_check_app hook.
# $1=svc (service name)  $2=deep (true|false)
_nc_check_role_app() {
    local svc="$1" deep="$2"
    local occ="docker compose exec -T -u www-data ${svc} php occ"

    # occ status
    local status_json
    status_json=$($occ status --output=json 2>/dev/null)
    if [ -z "$status_json" ]; then
        _diag_emit FAIL nc_occ_unavailable "occ command unavailable — app container may not be ready"
        return
    fi

    local installed maintenance
    installed=$(echo "$status_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('installed','false'))" 2>/dev/null || echo "false")
    maintenance=$(echo "$status_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('maintenance','false'))" 2>/dev/null || echo "false")

    if [ "$installed" = "True" ] || [ "$installed" = "true" ]; then
        _diag_emit OK nc_installed "Nextcloud reports installed=true"
    else
        _diag_emit CRITICAL nc_not_installed "Nextcloud not installed — occ status installed=false"
        return
    fi

    if [ "$maintenance" = "True" ] || [ "$maintenance" = "true" ]; then
        _diag_emit WARN nc_maintenance_stuck "Nextcloud in maintenance mode — if not intentional, may be stuck from failed upgrade"
    else
        _diag_emit OK nc_not_maintenance "Nextcloud not in maintenance mode"
    fi

    # Background jobs last execution
    local bg_json bg_last bg_mode
    bg_json=$($occ background:mode --output=json 2>/dev/null || true)
    bg_mode=$(echo "$bg_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('mode','unknown'))" 2>/dev/null || echo "unknown")
    if [ "$bg_mode" = "cron" ]; then
        _diag_emit OK nc_bg_mode "Background jobs mode: cron (correct)"
    elif [ -n "$bg_mode" ] && [ "$bg_mode" != "unknown" ]; then
        _diag_emit WARN nc_bg_mode "Background jobs mode: ${bg_mode} (expected 'cron' for reliable execution)"
    fi

    # Config checks via occ
    local proto loglevel filelocking memcache_local
    proto=$($occ config:system:get overwriteprotocol 2>/dev/null | tr -d '[:space:]')
    loglevel=$($occ config:system:get loglevel 2>/dev/null | tr -d '[:space:]')
    filelocking=$($occ config:system:get filelocking.enabled 2>/dev/null | tr -d '[:space:]')
    memcache_local=$($occ config:system:get memcache.local 2>/dev/null | tr -d '[:space:]')

    [ "$proto" = "https" ] \
        && _diag_emit OK nc_proto_ok "overwriteprotocol=https (correct for Cloudflare tunnel)" \
        || _diag_emit WARN nc_proto_wrong "overwriteprotocol='${proto:-not set}' — should be 'https' for Cloudflare tunnel"

    if [ -n "$loglevel" ] && (( loglevel >= 3 )); then
        _diag_emit OK nc_loglevel "NC loglevel=${loglevel} (WARNING or above — good for Pi 3)"
    elif [ -n "$loglevel" ]; then
        _diag_emit WARN nc_loglevel "NC loglevel=${loglevel} — verbose logging increases Pi 3 load; recommend ≥2 (WARNING)"
    fi

    [ "$filelocking" = "true" ] \
        && _diag_emit OK nc_filelocking "File locking enabled (Redis)" \
        || _diag_emit WARN nc_filelocking_disabled "File locking disabled — concurrent edits may corrupt files"

    [ -n "$memcache_local" ] \
        && _diag_emit OK nc_memcache "Local memcache: ${memcache_local}" \
        || _diag_emit WARN nc_memcache_not_set "memcache.local not set — significantly reduces performance on Pi 3"

    # PHP memory_limit
    local php_mem_raw php_mem_mb
    php_mem_raw=$($occ config:system:get memory_limit 2>/dev/null | tr -d '[:space:]')
    if [ -n "$php_mem_raw" ]; then
        php_mem_mb=$(echo "$php_mem_raw" | python3 -c "
s=input().strip().upper()
n=int(''.join(filter(str.isdigit,s)) or 0)
if 'G' in s: n*=1024
print(n)
" 2>/dev/null || echo "0")
        if (( php_mem_mb < 256 )); then
            _diag_emit WARN nc_php_memory_low "PHP memory_limit=${php_mem_raw} < 256MB — large files and occ commands may fail"
        else
            _diag_emit OK nc_php_memory "PHP memory_limit=${php_mem_raw}"
        fi
    fi

    # Debug mode
    local nc_debug
    nc_debug=$($occ config:system:get debug 2>/dev/null | tr -d '[:space:]')
    [ "$nc_debug" = "true" ] && \
        _diag_emit WARN nc_debug_enabled "NC debug mode enabled — increases log size and reduces performance"

    # occ check (internal DB/filesystem check)
    local check_out
    check_out=$($occ check 2>/dev/null)
    if echo "$check_out" | grep -qi "error\|fail"; then
        _diag_emit WARN nc_check_failed "occ check reported issues: $(echo "$check_out" | head -1)"
    else
        _diag_emit OK nc_check "occ check passed"
    fi

    # Missing DB indices
    local indices_out
    indices_out=$($occ db:add-missing-indices --dry-run 2>/dev/null || true)
    if echo "$indices_out" | grep -qi "missing\|creating"; then
        _diag_emit WARN nc_missing_indices "Missing database indices detected — run occ db:add-missing-indices to fix"
    else
        _diag_emit OK nc_db_indices "No missing database indices detected"
    fi

    # Deep checks
    if [ "$deep" = "true" ]; then
        _nc_check_role_app_deep "$svc"
    fi
}

_nc_check_role_app_deep() {
    local svc="$1"

    # Recent NC error count
    local error_count
    error_count=$(docker compose exec -T "$svc" tail -200 /var/www/html/data/nextcloud.log 2>/dev/null \
        | python3 -c "
import sys, json
count = 0
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        if d.get('level', 0) >= 3:
            count += 1
    except Exception:
        pass
print(count)
" 2>/dev/null || true)

    if (( error_count >= 20 )); then
        _diag_emit FAIL nc_many_errors "${error_count} ERROR/FATAL entries in last 200 NC log lines"
    elif (( error_count >= 5 )); then
        _diag_emit WARN nc_some_errors "${error_count} errors in last 200 NC log lines"
    else
        _diag_emit OK nc_errors "NC log: ${error_count} errors in last 200 lines"
    fi

    # NC log size
    local log_size
    log_size=$(docker compose exec -T "$svc" stat -c "%s" /var/www/html/data/nextcloud.log 2>/dev/null || true)
    if [ -n "$log_size" ]; then
        local log_mb=$(( log_size / 1048576 ))
        if (( log_mb > 50 )); then
            _diag_emit WARN nc_log_large "nextcloud.log is ${log_mb}MB > 50MB — persistent errors or debug mode enabled"
        else
            _diag_emit OK nc_log_size "nextcloud.log is ${log_mb}MB"
        fi
    fi

    # Heavy/AI app checks — warn if known resource-intensive apps are enabled
    local occ="docker compose exec -T -u www-data ${svc} php occ"
    local heavy_apps="recognize assistant"
    local enabled_apps
    enabled_apps=$($occ app:list --output=json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(' '.join(d.get('enabled', {}).keys()))
except Exception:
    print('')
" 2>/dev/null || echo "")
    local found_heavy=""
    for app in $heavy_apps; do
        echo "$enabled_apps" | grep -qw "$app" && found_heavy+="${app} "
    done
    if [ -n "$found_heavy" ]; then
        _diag_emit WARN nc_heavy_apps "Heavy/AI apps enabled: ${found_heavy% } — high CPU/RAM on Pi 3"
    else
        _diag_emit OK nc_config_full_text "No known heavy/AI apps enabled"
    fi
}

# REQUIRED — called by health status bar
# Returns: "status:message"
#   status: ok | warn | fail
#   message: short human-readable description shown in the status bar
nextcloud_docker__health() {
    local issues="" warnings=""

    # ── Docker available? ─────────────────────────────────────────────────────
    if ! command -v docker &>/dev/null; then
        echo "fail:docker not installed"
        return 0
    fi

    # ── Stack running? ────────────────────────────────────────────────────────
    local running_count
    running_count=$(docker compose ps --status running --services 2>/dev/null | wc -l)
    if [ "${running_count:-0}" -eq 0 ]; then
        echo "fail:stack down — use menu 4 to start"
        return 0
    fi

    # ── Required containers present? ─────────────────────────────────────────
    local required_services="app web db redis cron"
    local running_services
    running_services=$(docker compose ps --status running --services 2>/dev/null)
    local svc
    for svc in $required_services; do
        if ! echo "$running_services" | grep -qx "$svc"; then
            issues+="${svc} down; "
        fi
    done

    # ── HTTP reachability ─────────────────────────────────────────────────────
    local http_code
    http_code=$(_nc_check_http /status.php 3)
    if [ "$http_code" != "200" ]; then
        warnings+="HTTP ${http_code:-timeout}; "
    fi

    # ── Maintenance mode ──────────────────────────────────────────────────────
    local maint
    maint=$(docker compose exec -T -u www-data app php occ \
        maintenance:mode 2>/dev/null | grep -c "enabled")
    [ "${maint:-0}" -gt 0 ] && warnings+="maintenance mode ON; "

    # ── Return status ─────────────────────────────────────────────────────────
    if [ -n "$issues" ]; then
        echo "fail:${issues%; }"
    elif [ -n "$warnings" ]; then
        echo "warn:${warnings%; }"
    else
        echo "ok:${running_count} containers running"
    fi
    return 0
}

# Hook: status_line — prints Tunnel and Nextcloud status rows for the header.
# Each row is printed to stdout in "  Key       : value" format.
nextcloud_docker__status_line() {
    # ── Tunnel ────────────────────────────────────────────────────────────────
    local tunnel_status
    if sudo systemctl is-active cloudflared &>/dev/null; then
        if sudo journalctl -u cloudflared -n 50 --no-pager 2>/dev/null \
                | grep -q "Connection registered\|Connection established\|Registered tunnel"; then
            tunnel_status="${GRN}● CONNECTED${NC}"
        else
            tunnel_status="${YEL}● RUNNING${NC}"
        fi
    else
        tunnel_status="${RED}● DOWN${NC}"
    fi
    echo -e "  Tunnel    : ${tunnel_status}"

    # ── Nextcloud ─────────────────────────────────────────────────────────────
    local http_code nc_status
    http_code=$(_nc_check_http /status.php 3)
    [ "$http_code" = "200" ] \
        && nc_status="${GRN}● RUNNING${NC}" \
        || nc_status="${RED}● DOWN${NC}"
    echo -e "  Nextcloud : ${nc_status}"

    return 0
}

# OPTIONAL — called by IGOR DIAGNOSE aggregator
# Output one line per check: CHECK:<name>:<status>:<message>
nextcloud_docker__diagnose() {
    local _mod_dir _root _stacks _defaults _stack
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    _defaults="${_mod_dir}/defaults"
    _stack="${_stacks}/nextcloud"

    # ── 1. Stack directory exists ──────────────────────────────────────────────
    if [[ ! -d "$_stack" ]]; then
        echo "CHECK:stack_dir:fail:config/stacks/nextcloud/ missing — run S→0 WIZARD to bootstrap"
        return 0   # no point running further checks without the stack
    else
        echo "CHECK:stack_dir:ok:config/stacks/nextcloud/ present"
    fi

    # ── 2. Secrets file present ────────────────────────────────────────────────
    if [[ ! -f "${_root}/secrets/db.env" ]]; then
        echo "CHECK:secrets_db:fail:secrets/db.env missing — run S→0 WIZARD to create credentials"
    else
        echo "CHECK:secrets_db:ok:secrets/db.env present"
    fi

    # ── 3. Config drift: stacks/ vs defaults/ ─────────────────────────────────
    local _f
    for _f in docker-compose.yml nginx.conf; do
        if [[ ! -f "${_stack}/${_f}" ]]; then
            echo "CHECK:config_drift:fail:config/stacks/nextcloud/${_f} missing — run S→0 WIZARD"
        elif [[ -f "${_defaults}/${_f}" ]] && \
             ! diff -q "${_defaults}/${_f}" "${_stack}/${_f}" >/dev/null 2>&1; then
            echo "CHECK:config_drift:warn:${_f} differs from default — check D. DIAGNOSE for upgrade notes"
        fi
    done

    # ── 4. Containers running ─────────────────────────────────────────────────
    if ! command -v docker &>/dev/null; then
        echo "CHECK:containers:fail:docker not installed — run S→1 DOCKER to install"
    else
        local _running
        _running=$(docker ps --filter "name=nextcloud" --format "{{.Names}}" 2>/dev/null | wc -l)
        if [[ "$_running" -eq 0 ]]; then
            echo "CHECK:containers:fail:no nextcloud containers running — run 4. SERVICES to start"
        elif [[ "$_running" -lt 4 ]]; then
            echo "CHECK:containers:warn:only ${_running}/4+ nextcloud containers running — check 4. SERVICES"
        else
            echo "CHECK:containers:ok:${_running} containers running"
        fi
    fi

    # ── 5. Data directory mounted ──────────────────────────────────────────────
    local _data="${NC_DATA:-/mnt/nextclouddata/next}"
    local _mount="${HD_MOUNT:-/mnt/nextclouddata}"
    if [[ ! -d "$_data" ]]; then
        echo "CHECK:data_dir:fail:data dir ${_data} missing — run S→2 STORAGE to mount HD"
    elif ! mount | grep -q "$_mount" 2>/dev/null; then
        echo "CHECK:data_dir:warn:${_mount} not in mount table — HD may not be mounted (S→2 STORAGE)"
    else
        local _used; _used=$(df -h "$_data" 2>/dev/null | awk 'NR==2{print $5}' || echo "?")
        echo "CHECK:data_dir:ok:${_data} mounted (${_used} used)"
    fi

    # ── 6. Orphaned volumes from old installations ────────────────────────────
    local _orphans=()
    local _v
    while IFS= read -r _v; do
        # Flag _nextcloud / _db / _onlyoffice volumes NOT prefixed by current project
        if [[ "$_v" =~ (_nextcloud|_db|_onlyoffice) ]] && [[ ! "$_v" =~ ^nextcloud_ ]]; then
            _orphans+=("$_v")
        fi
    done < <(docker volume ls -q 2>/dev/null || true)

    if [[ ${#_orphans[@]} -gt 0 ]]; then
        local _list; _list=$(IFS=', '; echo "${_orphans[*]}")
        echo "CHECK:orphaned_volumes:warn:old volumes found: ${_list} — run S→6 ORPHAN CLEANUP to recover space"
    else
        echo "CHECK:orphaned_volumes:ok:no orphaned volumes from old installations"
    fi
}

# OPTIONAL — called by notification aggregator
nextcloud_docker__notify_sources() {
    return 0
}

# OPTIONAL — email command verbs this module handles
nextcloud_docker__mailcmd_verbs() {
    echo "ncstatus ncrestart ncupgrade"
    return 0
}

# OPTIONAL — called by AI context builder
# Prints Nextcloud-specific context to stdout (runs in subshell via igor_run_all_hooks).
nextcloud_docker__ai_context() {
    local ctx=""

    ctx+="\n=== NEXTCLOUD STATUS ===\n"
    ctx+="$(docker compose exec -T -u www-data app php occ status 2>/dev/null || echo 'occ not available')\n"

    ctx+="\n=== NC CONFIG (key settings) ===\n"
    for key in overwriteprotocol overwritehost "overwrite.cli.url" trusted_proxies \
               forwarded_for_headers "memcache.local" "memcache.locking" \
               background_jobs_mode loglevel; do
        local val
        val=$(docker compose exec -T -u www-data app php occ config:system:get "$key" 2>/dev/null)
        ctx+="${key}: ${val:-not set}\n"
    done

    ctx+="\n=== TUNNEL ===\n"
    ctx+="cloudflared service: $(sudo -n systemctl is-active cloudflared 2>/dev/null || echo 'unknown (sudo -n failed)')\n"
    ctx+="$(sudo -n journalctl -u cloudflared -n 5 --no-pager 2>/dev/null || echo '(cloudflared journal unavailable without sudo)')\n"

    ctx+="\n=== RECENT NC ERRORS (last 15) ===\n"
    ctx+="$(docker compose exec -T app tail -60 /var/www/html/data/nextcloud.log 2>/dev/null \
        | python3 -c "
import sys,json
lines = []
for l in sys.stdin:
    try:
        e=json.loads(l.strip())
        lines.append('['+str(e.get('level','?'))+'] '+e.get('message','')[:200])
    except:
        pass
for l in lines[-15:]:
    print(l)
" 2>/dev/null)\n"

    ctx+="\n=== HTTP ROUTING QUICK CHECK ===\n"
    for url in /status.php /login /apps/files/; do
        local code
        code=$(_nc_check_http "$url")
        ctx+="localhost:${NEXTCLOUD_HTTP_PORT:-8080}${url} → ${code}\n"
    done

    ctx+="\n=== VOLUME MOUNT STATUS ===\n"
    if mount | grep -q "${HD_MOUNT:-/mnt/nextclouddata}"; then
        ctx+="HD_MOUNT (${HD_MOUNT:-/mnt/nextclouddata}): MOUNTED\n"
    else
        ctx+="HD_MOUNT (${HD_MOUNT:-/mnt/nextclouddata}): NOT MOUNTED\n"
    fi
    if [ -d "${NC_DATA:-/mnt/nextclouddata/next}" ]; then
        local nc_owner; nc_owner=$(stat -c "%u:%g" "${NC_DATA:-/mnt/nextclouddata/next}" 2>/dev/null)
        ctx+="NC_DATA: EXISTS  ownership: ${nc_owner}\n"
    else
        ctx+="NC_DATA: NOT FOUND\n"
    fi

    echo -e "$ctx"
    return 0
}

# NOTIFY HOOK — event declarations for the notification event settings menu.
# Format: EVENT|event_key|label|NOTIFY_ON_VAR_SUFFIX|default(true/false)|severity(critical/warning/info)
# The notify subsystem calls this hook to populate the Nextcloud section of the
# Event Settings menu.  Wiring: each event_key must have a corresponding
# notify_event "event_key" "..." call somewhere in the codebase to actually fire.
nextcloud_docker__notify_events() {
    echo "EVENT|nc_login_failed|Multiple failed login attempts in NC log|NC_LOGIN_FAILED|true|critical"
    echo "EVENT|nc_tunnel_down|Cloudflare tunnel connection lost|NC_TUNNEL_DOWN|true|critical"
    echo "EVENT|nc_low_storage|NC data volume running low (<10% free)|NC_LOW_STORAGE|true|critical"
    echo "EVENT|nc_maintenance_mode|Maintenance mode toggled on or off|NC_MAINTENANCE_MODE|true|warning"
    echo "EVENT|nc_update_available|New Nextcloud version available|NC_UPDATE_AVAILABLE|true|info"
    echo "EVENT|nc_scan_complete|File scan completed|NC_SCAN_COMPLETE|false|info"
    echo "EVENT|nc_services_start|Stack started manually via IGOR|NC_SERVICES_START|false|info"
}

# AI HOOK — capability catalog for run_igor_action tool
# Each block declares a non-interactive leaf function the AI can call directly.
# igor_load_capabilities() in module_loader.sh parses this into _IGOR_CAPABILITIES.
nextcloud_docker__ai_capabilities() {
    cat << 'EOF'
ACTION health_check
DESCRIPTION Run quick health check — HTTP probe, container count, storage
FUNCTION _mod_network_health_check
LOAD_MODULE network
TIER READ
PROBLEMS down, 502, unreachable, slow, health, not responding, check
MENU_PATH [6] DIAGNOSE → QUICK HEALTH CHECK

ACTION full_diagnostic
DESCRIPTION Run full diagnostic — all checks, save report
FUNCTION _mod_network_full_report
LOAD_MODULE network
TIER READ
PROBLEMS full check, report, diagnostic, deep, all checks
MENU_PATH [6] DIAGNOSE → FULL DIAGNOSTIC

ACTION services_status
DESCRIPTION Show container states and uptime
FUNCTION _mod_services_status
LOAD_MODULE services
TIER READ
PROBLEMS status, running, stopped, containers, uptime, state
MENU_PATH [2] SERVICES → status

ACTION scan_files
DESCRIPTION Scan all Nextcloud files and update the index
FUNCTION _mod_maint_scan_files
LOAD_MODULE maintenance
TIER CHANGE
PROBLEMS files missing, new files not appearing, after migration, file count wrong, not syncing
MENU_PATH [4] MAINTENANCE → SCAN FILES

ACTION flush_redis
DESCRIPTION Flush Redis cache (session cache + file locks)
FUNCTION _mod_maint_redis_flush
LOAD_MODULE maintenance
TIER CHANGE
PROBLEMS redis, cache, session, lock, locked files, stale cache
MENU_PATH [4] MAINTENANCE → FLUSH REDIS

ACTION flush_caches
DESCRIPTION Flush all Nextcloud caches at once (APCu + Redis)
FUNCTION _mod_maint_flush_caches
LOAD_MODULE maintenance
TIER CHANGE
PROBLEMS cache, slow, stale, APCu, opcache, not refreshing
MENU_PATH [4] MAINTENANCE → FLUSH ALL CACHES

ACTION repair
DESCRIPTION Run occ maintenance:repair (quick repair)
FUNCTION _mod_maint_repair
LOAD_MODULE maintenance
TIER CHANGE
PROBLEMS repair, broken, corrupt, database error, integrity
MENU_PATH [4] MAINTENANCE → RUN REPAIR

ACTION full_repair
DESCRIPTION Run occ maintenance:repair --include-expensive (thorough)
FUNCTION _mod_maint_full_repair
LOAD_MODULE maintenance
TIER CHANGE
PROBLEMS full repair, expensive, deep repair, thorough, indices missing
MENU_PATH [4] MAINTENANCE → FULL REPAIR

ACTION fix_permissions
DESCRIPTION Fix file ownership and permissions on NC data dir
FUNCTION _mod_maint_fix_permissions
LOAD_MODULE maintenance
TIER CHANGE
PROBLEMS permission, 403, denied, ownership, www-data, cannot write
MENU_PATH [4] MAINTENANCE → FIX PERMISSIONS

ACTION db_maintenance
DESCRIPTION Run database optimization and cleanup
FUNCTION _mod_maint_db_maintenance
LOAD_MODULE maintenance
TIER CHANGE
PROBLEMS database, db, slow query, index, db error, postgresql
MENU_PATH [4] MAINTENANCE → DB MAINTENANCE

ACTION nc_permissions
DESCRIPTION Check Nextcloud data dir ownership and permission flags
FUNCTION _mod_network_nc_permissions
LOAD_MODULE network
TIER READ
PROBLEMS permission check, data dir, ownership audit, who owns
MENU_PATH [6] DIAGNOSE → NC PERMISSIONS

ACTION inject_nc_config
DESCRIPTION Apply occ config: trusted_proxies, overwrite.cli.url, domain settings
FUNCTION _mod_network_inject_nc_config
LOAD_MODULE network
TIER CHANGE
PROBLEMS trusted_proxies, CSRF, overwrite.cli.url, domain, mobile app, cookie error
MENU_PATH [5] CONFIGURE → NC SETTINGS
EOF
}

# AI HOOK — abstract tool definitions (compact single-line JSON array)
# Engines read this JSON and format it for their provider (XML, OpenAI schema, markdown).
nextcloud_docker__ai_tools() {
    printf '%s\n' '[{"name":"occ_command","display":"Nextcloud occ","description":"Run Nextcloud occ commands inside the app container. Use for ALL Nextcloud config, apps, users, indices, cron, cache.","tier":"CHANGE","xml_tag":"occ","xml_content":"command","xml_example":"maintenance:mode --off","notes":["Never edit config.php directly — always use occ config:system:set"],"openai_params":{"command":{"type":"string","description":"The occ subcommand to run (e.g. maintenance:mode --off, status, config:system:get version)"}}},{"name":"container_action","display":"Container lifecycle","description":"Start, stop, or restart a named service container (web, app, db, redis, cloudflared).","tier":"CHANGE","xml_tag":"container","xml_attrs_example":"action=\"restart\"","xml_example":"<container action=\"restart\"> web </container>","notes":[],"openai_params":{"action":{"type":"string","enum":["start","stop","restart"],"description":"Lifecycle action"},"name":{"type":"string","description":"Container name (web, app, db, redis, cloudflared)"}}},{"name":"run_igor_action","display":"Igor module action","description":"Call a registered Igor action by name. Check AVAILABLE IGOR ACTIONS in context for the full list. Prefer this over raw host commands when a matching action exists — Igor loads the right module, handles all paths, and journals the call.","tier":"varies — see catalog","xml_tag":"run_igor_action","xml_content":"action_name","xml_example":"scan_files","notes":["Action names are listed in AVAILABLE IGOR ACTIONS in the context block","Tier (READ/CHANGE/DESTROY) is determined by the catalog entry","READ actions auto-run; CHANGE requires confirmation; DESTROY requires YES"],"openai_params":{"action_name":{"type":"string","description":"The action identifier from AVAILABLE IGOR ACTIONS (e.g. scan_files, health_check, flush_redis)"}}}]'
}

# AI HOOK — per-module READ/CHANGE/DESTROY tier assignments
nextcloud_docker__ai_tiers() {
    cat << 'EOF'
NEXTCLOUD DOCKER TIER RULES:
READ (auto-run, no confirmation):
  docker compose -f ... ps
  docker compose -f ... logs [--tail N] <service>
  docker compose -f ... exec -T <svc> <read-only-cmd>
  occ status
  occ config:system:get <key>
  occ app:list
  occ check
  occ integrity:check-app <app>
  curl -s ... (HTTP status checks)

CHANGE (requires user confirmation or executive mode):
  docker compose -f ... restart <service>
  docker compose -f ... exec -T app php occ maintenance:mode --on/--off
  occ config:system:set <key> --value=<val>
  occ app:enable <app>
  occ app:disable <app>
  occ maintenance:repair
  redis-cli FLUSHALL
  <edit_file> on nginx.conf or any config file

DESTROY (user must type YES):
  docker compose -f ... down
  docker volume rm
  occ files:cleanup --all
  rm -rf <any directory>
EOF
}

# AI HOOK — known repair patterns for the Nextcloud Docker module
# Outputs one PATTERN block per known fix in the same format as _ai_inject_patterns.
# These are static patterns defined by the module (distinct from learned .pattern files).
nextcloud_docker__ai_patterns() {
    cat << 'EOF'
PATTERN: nginx_default_conf_present  confirmed:0  failed:0  tier:CHANGE
  Fix: docker compose -f <STACK_DIR>/docker-compose.yml exec -T web rm -f /etc/nginx/conf.d/default.conf && docker compose restart web

PATTERN: nc_maintenance_mode_stuck  confirmed:0  failed:0  tier:CHANGE
  Fix: <occ> maintenance:mode --off </occ>

PATTERN: redis_connection_refused  confirmed:0  failed:0  tier:CHANGE
  Fix: docker compose -f <STACK_DIR>/docker-compose.yml restart redis

PATTERN: well_known_404_nginx_missing_block  confirmed:0  failed:0  tier:CHANGE
  Fix: <edit_file path="<STACK_DIR>/nginx.conf"> add location ^~ /.well-known block before location /

PATTERN: csrf_cookie_error  confirmed:0  failed:0  tier:CHANGE
  Fix: verify trusted_proxies includes all CF IPs and HTTP_X_FORWARDED_PROTO https is in fastcgi_params
EOF
}

# AI HOOK — domain knowledge for the Nextcloud Docker module
nextcloud_docker__ai_knowledge() {
    # Resolve stack directory from IGOR_DIR (do NOT use BASH_SOURCE[0] — this function
    # is called via igor_run_all_hooks which runs it in a bash -c subprocess where
    # BASH_SOURCE[0] resolves to the wrong path).
    local _root="${IGOR_DIR:-}"
    local _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    local _stack_dir="${_stacks}/nextcloud"
    local _secrets="${_root}/secrets"

    cat << EOF
━━━ STACK DIRECTORY ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

STACK DIR: ${_stack_dir}
SECRETS:   ${_secrets}/db.env

All docker compose commands MUST use the full path — running docker compose
without -f from the wrong directory gives false "no service" results:
  docker compose -f ${_stack_dir}/docker-compose.yml --env-file ${_secrets}/db.env <cmd>
All occ commands:
  docker compose -f ${_stack_dir}/docker-compose.yml --env-file ${_secrets}/db.env exec -T -u www-data app php occ <cmd>

━━━ CRITICAL: OCC COMMANDS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

NEVER use <host> to run occ commands. You have a dedicated <occ> tool — use it.
  WRONG: <host> docker compose -f .../docker-compose.yml exec -T -u www-data app php occ status </host>
  RIGHT: <occ> status </occ>
The <occ> tool automatically uses the correct docker compose path, env-file, and flags.

━━━ ARCHITECTURE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Stack: Cloudflare tunnel → nginx (port 8080) → php-fpm → postgres/redis
- config.php lives in the named Docker volume (NOT a bind mount)
- Read it: <host> docker compose -f ${_stack_dir}/docker-compose.yml exec -T app cat /var/www/html/config/config.php </host>
- Change it: <occ> config:system:set overwriteprotocol --value="https" </occ>
- All CF IPs must be in trusted_proxies or CSRF/cookie checks fail
- HTTP_X_FORWARDED_PROTO https must be in fastcgi_params

NGINX EDITING RULES — read before every nginx change:
- The nginx config on the HOST is ${_stack_dir}/nginx.conf (bind-mounted into the web container).
- NEVER use <edit_file path="/etc/nginx/..."> — that is a container path; edit_file is host-only.
- NEVER leave <find> empty — an empty find string CORRUPTS the file (prepends content in Python).
- Before editing: <host> grep -n "keyword" ${_stack_dir}/nginx.conf </host> to get exact text for <find>.
- After any nginx edit, always verify: <host> curl -s -o /dev/null -w "%{http_code}" http://localhost:${NEXTCLOUD_HTTP_PORT:-8080}/status.php </host>
- If nginx enters a restart loop ("server directive not allowed" or similar): STOP editing — restore from backup.
- .well-known admin warnings are a nginx routing problem — check ${_stack_dir}/nginx.conf for the location ^~ /.well-known block.
  NEVER use occ to fix .well-known warnings. occ overwrite.* settings affect URL generation, not request routing.

RESTORE FROM NGINX BACKUP:
  Step 1: <host> ls -t ${_stack_dir}/nginx.conf.bak.* 2>/dev/null | head -5 </host>  (lists backups, newest first)
  Step 2: <host> cp OLDEST_GOOD_BACKUP ${_stack_dir}/nginx.conf </host>  (use the OLDEST to go back before your edits)
  Step 3: <container action="restart"> web </container>
  Step 4: <host> curl -s -o /dev/null -w "%{http_code}" http://localhost:${NEXTCLOUD_HTTP_PORT:-8080}/status.php </host>
When user says "restore", "rollback", "undo", "revert" regarding nginx: run RESTORE immediately. No diagnostics.

NEXTCLOUD QUIRKS:
- You CANNOT use \`occ app:remove\` on a disabled app. Delete directly:
  <host> docker compose -f ${_stack_dir}/docker-compose.yml exec -T app rm -rf /var/www/html/custom_apps/APPNAME </host>
- occ integrity:check-app failures on shipped core apps are benign — tell the user.
- After removing/disabling any app, ALWAYS flush cache:
  <occ> maintenance:repair </occ>  then  <host> docker compose -f ${_stack_dir}/docker-compose.yml exec -T redis redis-cli FLUSHALL </host>

DIAGNOSTIC LAYERS — check the right layer first:
- Admin warning "web server not configured" / .well-known / 403 on /apps/: nginx FIRST.
  .well-known 301 = redirect working, check destination. 404 = missing location block.
  Fix is always <edit_file path="${_stack_dir}/nginx.conf">, never occ config.
- 502 Bad Gateway / connection refused: container status first.
  <host> docker compose -f ${_stack_dir}/docker-compose.yml ps </host>
- "CSRF check failed" / cookie errors: trusted_proxies + HTTP_X_FORWARDED_PROTO in nginx.
- "Not installed" from occ / maintenance stuck: occ status then maintenance:mode --off.
- Redis errors: test with PING first, then restart redis container.

IMPERATIVE COMMANDS (NC-specific):
- "restore" / "rollback" / "undo nginx" / "revert": run RESTORE FROM NGINX BACKUP above.
- "restart" / "restart web" / "restart containers": <container action="restart"> web </container>

IGOR MENU MAP (what the user can do outside this chat):
  S  SETUP & INSTALL  First-run wizard, storage, cloudflare tunnel, stack ops
  1  STATUS           Quick dashboard — containers, NC health, tunnel
  2  SERVICES         Start/stop/restart/logs/nuke
  3  APPS             NC apps: list/enable/disable/install
  4  MAINTENANCE      Scan, previews, DB, upgrade, permissions, flush caches
  5  CONFIGURE        nginx inject/restore, NC settings, upload limit, admin password
  6  DIAGNOSE         Health checks, routing, PHP, DB integrity
  7  INFO             Architecture, paths, onboarding guide, Igor internals
  A  AI               This assistant (current session)
  D  IGOR DIAGNOSE    Full 6-phase diagnostic session
EOF
}

# OPTIONAL — recovery hooks
nextcloud_docker__recovery_hooks() {
    return 0
}

# OPTIONAL — called by Igor's install wizard to bootstrap config/stacks/nextcloud/ from defaults/
# Idempotent: skips if config/stacks/nextcloud/ already exists.
nextcloud_docker__install() {
    local _mod_dir _root _stacks _defaults _stack
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    _defaults="${_mod_dir}/defaults"
    _stack="${_stacks}/nextcloud"

    if [[ -d "$_stack" ]]; then
        echo "Stack already exists at ${_stack}/ — skipping bootstrap."
        return 0
    fi

    mkdir -p "$_stack"
    local _f
    for _f in docker-compose.yml docker-compose.override.yml Dockerfile \
               nginx.conf nginx.conf.tmpl README.md; do
        [[ -f "${_defaults}/${_f}" ]] && cp "${_defaults}/${_f}" "${_stack}/${_f}"
    done
    echo "Stack bootstrapped at ${_stack}/"
    return 0
}

# Convenience wrapper: run docker compose with correct paths.
# --project-name nextcloud: stable volume names regardless of igor directory name.
# stacks/nextcloud/ is the --project-directory so relative paths in compose file
# (nginx.conf bind mount, build context) resolve correctly.
nextcloud_docker__compose() {
    local _mod_dir _root _stacks
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    docker compose \
        -f "${_stacks}/nextcloud/docker-compose.yml" \
        --env-file "${_root}/secrets/db.env" \
        --project-name nextcloud \
        --project-directory "${_stacks}/nextcloud" \
        "$@"
}

# Hook: notify — notification sources for this module
# Delegates to the existing notify_sources function
nextcloud_docker__notify() {
    nextcloud_docker__notify_sources
    return 0
}

# Hook: mailcmd — mail command verbs this module handles
# Delegates to the existing mailcmd_verbs function
nextcloud_docker__mailcmd() {
    nextcloud_docker__mailcmd_verbs
    return 0
}

# Hook: recovery — recovery hooks for this module
# Delegates to the existing recovery_hooks function
nextcloud_docker__recovery() {
    nextcloud_docker__recovery_hooks
    return 0
}

# ── Phase 5: Application Layer (moved from core/diagnose/phases.sh) ──────────
# Called in-process by nextcloud_docker__app_diagnose() via app_diagnose hook.
# _diag_emit, _DIAG_ROLES, step(), info() are available in-process.
# Fixes from original: http_port and _cfg_dir were undefined — now set locally.
_nc_diag_phase_5() {
    local deep="${1:-false}"
    _DIAG[current_phase]=5
    step "Phase 5: Application Layer"
    _diag_log "phase 5: start"

    # Variables not available in module scope — set from config
    local http_port; http_port=$(declare -f igor_get_port &>/dev/null && \
        igor_get_port "nextcloud_http" "${NEXTCLOUD_HTTP_PORT:-${IGOR_WEB_PORT:-8080}}" \
        || echo "${NEXTCLOUD_HTTP_PORT:-${IGOR_WEB_PORT:-8080}}")
    local _cfg_dir="${IGOR_DIR}"

    # ── End-to-end HTTP ────────────────────────────────────────────────────────
    local start_ts
    start_ts=$(date +%s%N 2>/dev/null || date +%s)
    local status_resp
    status_resp=$(curl -sf --max-time 12 "http://localhost:${http_port}/status.php" 2>/dev/null)
    local end_ts
    end_ts=$(date +%s%N 2>/dev/null || date +%s)
    local elapsed_ms=$(( (end_ts - start_ts) / 1000000 ))
    [ $elapsed_ms -lt 0 ] && elapsed_ms=0

    if [ -z "$status_resp" ]; then
        _diag_emit CRITICAL e2e_http_down "End-to-end HTTP check failed — no response from status.php through full stack"
    else
        local nc_installed
        nc_installed=$(echo "$status_resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('true' if d.get('installed', False) else 'false')
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown")

        if [ "$nc_installed" = "true" ]; then
            if (( elapsed_ms > 3000 )); then
                _diag_emit WARN e2e_http_slow "End-to-end HTTP OK but slow: ${elapsed_ms}ms (>3000ms threshold)"
            else
                _diag_emit OK e2e_http_ok "End-to-end HTTP OK: status.php in ${elapsed_ms}ms"
            fi
        else
            _diag_emit FAIL e2e_http_not_installed "status.php responded but installed=false — Nextcloud not initialised"
        fi
    fi

    # ── Login endpoint ─────────────────────────────────────────────────────────
    local login_code
    login_code=$(curl -s -o /tmp/_diag_login.html -w "%{http_code}" --max-time 10 \
        "http://localhost:${http_port}/login" 2>/dev/null)
    if [ "$login_code" = "200" ]; then
        if grep -qi "name=\"password\"\|id=\"password\"\|loginform\|login-form" /tmp/_diag_login.html 2>/dev/null; then
            _diag_emit OK nc_login_page "Login page returns 200 with login form"
        else
            _diag_emit WARN nc_login_no_form "Login page returns 200 but no login form found — possible trusted domain redirect loop"
        fi
    else
        _diag_emit WARN nc_login_code "Login page returned HTTP ${login_code} (expected 200)"
    fi
    rm -f /tmp/_diag_login.html 2>/dev/null || true

    # ── WebDAV endpoint ────────────────────────────────────────────────────────
    local webdav_code
    webdav_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
        "http://localhost:${http_port}/remote.php/webdav/" 2>/dev/null)
    case "$webdav_code" in
        401) _diag_emit OK nc_webdav "WebDAV endpoint returns 401 (correct — auth required)" ;;
        404) _diag_emit FAIL nc_webdav_404 "WebDAV endpoint returns 404 — WebDAV may be broken (sync clients will fail)" ;;
        000) _diag_emit WARN nc_webdav_no_resp "WebDAV endpoint not responding" ;;
        *)   _diag_emit WARN nc_webdav_unexpected "WebDAV endpoint returned HTTP ${webdav_code} (expected 401)" ;;
    esac

    # ── NC application checks (via occ) ───────────────────────────────────────
    local app_svc="${_DIAG_ROLES[app]:-app}"
    local occ="docker compose exec -T -u www-data ${app_svc} php occ"

    # NC error log
    local error_count
    error_count=$(docker compose exec -T "$app_svc" \
        sh -c 'tail -200 /var/www/html/data/nextcloud.log 2>/dev/null' \
        | python3 -c "
import sys, json
count = 0
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        if d.get('level', 0) >= 3:
            count += 1
    except Exception:
        pass
print(count)
" 2>/dev/null || echo "0")

    if (( error_count >= 20 )); then
        _diag_emit FAIL nc_many_errors "NC log: ${error_count} ERROR/FATAL in last 200 lines — persistent application errors"
    elif (( error_count >= 5 )); then
        _diag_emit WARN nc_some_errors "NC log: ${error_count} errors in last 200 lines"
    else
        _diag_emit OK nc_log_clean "NC log: ${error_count} errors in last 200 lines"
    fi

    # Encryption status
    local enc_enabled
    enc_enabled=$($occ app:list --enabled 2>/dev/null | grep -c "encryption" || true)
    if (( enc_enabled > 0 )); then
        _diag_emit WARN nc_encryption "Server-side encryption is enabled — key issues after restore/migration cause silent file inaccessibility"
    else
        _diag_emit OK nc_no_encryption "Server-side encryption not enabled"
    fi

    # Orphaned file locks
    local db_svc_p5="${_DIAG_ROLES[db]:-db}"
    local db_user_p5="${POSTGRES_USER:-oc_admin}"
    local db_name_p5="${POSTGRES_DB:-nextcloud}"
    local stale_locks
    stale_locks=$(docker compose exec -T "$db_svc_p5" \
        psql -U "$db_user_p5" -d "$db_name_p5" -t \
        -c "SELECT count(*) FROM oc_file_locks WHERE ttl > 0 AND timestamp < (extract(epoch from now())::bigint - 3600);" \
        2>/dev/null | tr -d '[:space:]')
    if [ -n "$stale_locks" ] && (( stale_locks > 100 )); then
        _diag_emit WARN nc_orphaned_file_locks "${stale_locks} stale file locks (ttl>0, timestamp>1h ago) — files may appear locked to users; fix via maintenance:repair"
    elif [ -n "$stale_locks" ]; then
        _diag_emit OK nc_orphaned_file_locks "File locks: ${stale_locks} stale (below threshold)"
    fi

    # Bruteforce attempts
    local bf_count
    bf_count=$(docker compose exec -T "$db_svc_p5" \
        psql -U "$db_user_p5" -d "$db_name_p5" -t \
        -c "SELECT count(*) FROM oc_bruteforce_attempts WHERE occurred > NOW() - INTERVAL '1 hour';" \
        2>/dev/null | tr -d '[:space:]')
    if [ -n "$bf_count" ] && (( bf_count > 50 )); then
        _diag_emit WARN nc_bruteforce_table "${bf_count} bruteforce attempts in the last hour — may be blocking legitimate users; check NC admin panel"
    elif [ -n "$bf_count" ]; then
        _diag_emit OK nc_bruteforce_table "Bruteforce attempts in last hour: ${bf_count}"
    fi

    # Deep: pending migrations + integrity check
    if [ "$deep" = "true" ]; then
        local pending_mig
        pending_mig=$($occ migrations:status 2>/dev/null | grep -ic "not migrated\|pending" || true)
        if (( pending_mig > 0 )); then
            _diag_emit WARN nc_pending_migrations "${pending_mig} pending database migrations — run occ upgrade to apply"
        else
            _diag_emit OK nc_migrations "No pending database migrations"
        fi

        info "Phase 5 deep: running app integrity check (may take 60-120s)..."
        local integrity_result
        integrity_result=$(docker compose exec -T -u www-data "$app_svc" php occ integrity:check-apps --output=json 2>/dev/null)
        if [ -z "$integrity_result" ] || [ "$integrity_result" = "[]" ] || [ "$integrity_result" = "{}" ]; then
            _diag_emit OK occ_integrity_check "App integrity check: all apps passed"
        else
            local bad_apps
            bad_apps=$(echo "$integrity_result" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(','.join(d.keys()))
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown")
            _diag_emit FAIL occ_integrity_check "App integrity check FAILED for: ${bad_apps} — files have been modified; reinstall affected apps"
        fi
    fi

    # ── Notification / Email-command configuration checks ─────────────────────

    local _notify_env="${IGOR_DIR}/secrets/notify.env"
    if [ -f "$_notify_env" ]; then
        local _notify_host _notify_port _notify_user _notify_pass _notify_en
        _notify_host=$(grep "^NOTIFY_SMTP_HOST=" "$_notify_env" 2>/dev/null | cut -d= -f2-)
        _notify_port=$(grep "^NOTIFY_SMTP_PORT=" "$_notify_env" 2>/dev/null | cut -d= -f2-)
        _notify_user=$(grep "^NOTIFY_SMTP_USER=" "$_notify_env" 2>/dev/null | cut -d= -f2-)
        _notify_pass=$(grep "^NOTIFY_SMTP_PASS=" "$_notify_env" 2>/dev/null | cut -d= -f2-)
        _notify_en=$(grep   "^NOTIFY_ENABLED="   "$_notify_env" 2>/dev/null | cut -d= -f2-)

        if [ "${_notify_en}" = "true" ]; then
            if [ -z "$_notify_host" ] || [ -z "$_notify_user" ] || [ -z "$_notify_pass" ]; then
                _diag_emit FAIL notify_smtp_incomplete "notify.env: NOTIFY_ENABLED=true but SMTP host/user/password not fully set"
            else
                _diag_emit OK notify_smtp_configured "Notify SMTP configured: ${_notify_host}:${_notify_port:-587} user=${_notify_user}"
                local _smtp_ok
                _smtp_ok=$(python3 -c "
import socket, sys
try:
    s = socket.create_connection(('${_notify_host}', int('${_notify_port:-587}')), timeout=8)
    s.close(); print('ok')
except Exception as e:
    print('fail:' + str(e))
" 2>/dev/null)
                if [[ "$_smtp_ok" == "ok" ]]; then
                    _diag_emit OK notify_smtp_reachable "Notify SMTP reachable: ${_notify_host}:${_notify_port:-587}"
                else
                    _diag_emit WARN notify_smtp_unreachable "Notify SMTP not reachable: ${_notify_host}:${_notify_port:-587} — ${_smtp_ok#fail:}"
                fi
            fi
        else
            _diag_emit OK notify_smtp_disabled "Outbound notifications not enabled (NOTIFY_ENABLED!=true)"
        fi
    else
        _diag_emit OK notify_not_configured "notify.env not present — outbound notifications not set up"
    fi

    local _mc_env="${IGOR_DIR}/secrets/mailcmd.env"
    local _mc_vars_env="${IGOR_DIR}/config/variables/mailcmd.env"
    if [ -f "$_mc_env" ] || [ -f "$_mc_vars_env" ]; then
        _mc_read_key() {
            local _key="$1" _val=""
            [ -f "$_mc_vars_env" ] && _val=$(grep "^${_key}=" "$_mc_vars_env" 2>/dev/null | cut -d= -f2-)
            local _sec_val
            [ -f "$_mc_env" ] && _sec_val=$(grep "^${_key}=" "$_mc_env" 2>/dev/null | cut -d= -f2-)
            [ -n "$_sec_val" ] && _val="$_sec_val"
            printf '%s' "$_val"
        }
        local _mc_en _mc_imap_host _mc_imap_port _mc_imap_user _mc_imap_pass _mc_op_email _mc_gpg_key _mc_op_key
        _mc_en=$(_mc_read_key        "MAILCMD_ENABLED")
        _mc_imap_host=$(_mc_read_key "MAILCMD_IMAP_HOST")
        _mc_imap_port=$(_mc_read_key "MAILCMD_IMAP_PORT")
        _mc_imap_user=$(_mc_read_key "MAILCMD_IMAP_USER")
        _mc_imap_pass=$(_mc_read_key "MAILCMD_IMAP_PASS")
        _mc_op_email=$(_mc_read_key  "MAILCMD_OPERATOR_EMAIL")
        _mc_gpg_key=$(_mc_read_key   "MAILCMD_GPG_KEY_ID")
        _mc_op_key=$(_mc_read_key    "MAILCMD_OPERATOR_KEY_ID")
        unset -f _mc_read_key
        local _mc_gpg_home="${IGOR_DIR}/secrets/gnupg"

        if [ "${_mc_en}" = "true" ]; then
            if [ -z "$_mc_imap_host" ] || [ -z "$_mc_imap_user" ] || [ -z "$_mc_imap_pass" ]; then
                _diag_emit FAIL mailcmd_imap_incomplete "mailcmd.env: MAILCMD_ENABLED=true but IMAP host/user/password not fully set"
            else
                _diag_emit OK mailcmd_imap_configured "Mailcmd IMAP configured: ${_mc_imap_host}:${_mc_imap_port:-993} user=${_mc_imap_user}"
                local _imap_ok
                _imap_ok=$(python3 -c "
import socket
try:
    s = socket.create_connection(('${_mc_imap_host}', int('${_mc_imap_port:-993}')), timeout=8)
    s.close(); print('ok')
except Exception as e:
    print('fail:' + str(e))
" 2>/dev/null)
                if [[ "$_imap_ok" == "ok" ]]; then
                    _diag_emit OK mailcmd_imap_reachable "Mailcmd IMAP reachable: ${_mc_imap_host}:${_mc_imap_port:-993}"
                else
                    _diag_emit WARN mailcmd_imap_unreachable "Mailcmd IMAP not reachable: ${_mc_imap_host}:${_mc_imap_port:-993} — ${_imap_ok#fail:}"
                fi
            fi

            [ -z "$_mc_op_email" ] \
                && _diag_emit FAIL mailcmd_operator_email "mailcmd.env: MAILCMD_OPERATOR_EMAIL not set — all inbound commands will be rejected" \
                || _diag_emit OK mailcmd_operator_email "Mailcmd operator email: ${_mc_op_email}"

            if [ -z "$_mc_gpg_key" ]; then
                _diag_emit FAIL mailcmd_gpg_pi_key "mailcmd.env: MAILCMD_GPG_KEY_ID not set — Pi cannot decrypt incoming commands"
            else
                local _key_exists
                _key_exists=$(gpg --homedir "$_mc_gpg_home" --list-secret-keys "$_mc_gpg_key" 2>/dev/null | grep -c "^sec" || true)
                if (( _key_exists > 0 )); then
                    local _key_expiry _now_epoch _days_left
                    _key_expiry=$(gpg --homedir "$_mc_gpg_home" --list-keys --with-colons "$_mc_gpg_key" 2>/dev/null \
                        | grep "^pub" | cut -d: -f7)
                    _now_epoch=$(date +%s)
                    if [ -n "$_key_expiry" ] && [ "$_key_expiry" -gt 0 ] 2>/dev/null; then
                        _days_left=$(( (_key_expiry - _now_epoch) / 86400 ))
                        if (( _days_left < 0 )); then
                            _diag_emit FAIL mailcmd_gpg_pi_key "Pi GPG key ${_mc_gpg_key} has EXPIRED — renew via C → GPG keys → Renew"
                        elif (( _days_left < 30 )); then
                            _diag_emit WARN mailcmd_gpg_pi_key_expiry "Pi GPG key expires in ${_days_left} days — renew soon"
                        else
                            _diag_emit OK mailcmd_gpg_pi_key "Pi GPG key present and valid (${_mc_gpg_key}, expires in ${_days_left} days)"
                        fi
                    else
                        _diag_emit OK mailcmd_gpg_pi_key "Pi GPG key present and valid (${_mc_gpg_key}, no expiry)"
                    fi
                else
                    _diag_emit FAIL mailcmd_gpg_pi_key "Pi GPG key ID ${_mc_gpg_key} not found in keyring at ${_mc_gpg_home}"
                fi
            fi

            if [ -z "$_mc_op_key" ]; then
                _diag_emit FAIL mailcmd_gpg_operator_key "mailcmd.env: MAILCMD_OPERATOR_KEY_ID not set — Pi cannot encrypt replies"
            else
                local _opkey_exists
                _opkey_exists=$(gpg --homedir "$_mc_gpg_home" --list-keys "$_mc_op_key" 2>/dev/null | grep -c "^pub" || true)
                if (( _opkey_exists > 0 )); then
                    _diag_emit OK mailcmd_gpg_operator_key "Operator GPG public key present (${_mc_op_key})"
                else
                    _diag_emit FAIL mailcmd_gpg_operator_key "Operator GPG key ID ${_mc_op_key} not found in keyring — Pi cannot send encrypted replies"
                fi
            fi
        else
            _diag_emit OK mailcmd_disabled "Email command interface not enabled (MAILCMD_ENABLED!=true)"
        fi
    else
        _diag_emit OK mailcmd_not_configured "mailcmd config not present — email command interface not set up"
    fi

    # ── Backup health checks ───────────────────────────────────────────────────
    local _backup_dir="${_cfg_dir}/backups"

    local _backup_count
    _backup_count=$(ls "${_backup_dir}"/config_*.tar.gz 2>/dev/null | wc -l)
    if (( _backup_count == 0 )); then
        _diag_emit WARN backup_none "No config backups found in ${_backup_dir} — run V → Take Config Backup"
    else
        local _newest_backup _newest_epoch _now_ep _backup_age_days
        _newest_backup=$(ls -t "${_backup_dir}"/config_*.tar.gz 2>/dev/null | head -1)
        _newest_epoch=$(basename "$_newest_backup" | grep -oE '[0-9]+' | head -1)
        _now_ep=$(date +%s)
        _backup_age_days=$(( (_now_ep - _newest_epoch) / 86400 ))
        if (( _backup_age_days > 7 )); then
            _diag_emit WARN backup_stale "Latest config backup is ${_backup_age_days} days old — consider a fresh backup (V → 1)"
        else
            _diag_emit OK backup_recent "Config backup OK: ${_backup_count} backup(s), newest ${_backup_age_days} day(s) old"
        fi
    fi

    local _secrets_dir="/root/igor-secrets"
    local _secrets_count
    _secrets_count=$(sudo ls "${_secrets_dir}"/igor_secrets_*.tar.gz 2>/dev/null | wc -l)
    if (( _secrets_count == 0 )); then
        _diag_emit WARN backup_secrets_missing "No secrets backup found in ${_secrets_dir} — GPG private key not backed up"
    else
        local _newest_sec _sec_epoch _now_ep2 _sec_age_days
        _newest_sec=$(sudo ls -t "${_secrets_dir}"/igor_secrets_*.tar.gz 2>/dev/null | head -1)
        _sec_epoch=$(basename "$_newest_sec" | grep -oE '[0-9]+' | head -1)
        _now_ep2=$(date +%s)
        _sec_age_days=$(( (_now_ep2 - _sec_epoch) / 86400 ))
        if (( _sec_age_days > 30 )); then
            _diag_emit WARN backup_secrets_stale "Secrets backup is ${_sec_age_days} days old — re-run secrets backup after any key change"
        else
            _diag_emit OK backup_secrets "Secrets backup OK: ${_secrets_count} backup(s), newest ${_sec_age_days} day(s) old"
        fi
    fi

    _diag_log "phase 5: complete"
}
