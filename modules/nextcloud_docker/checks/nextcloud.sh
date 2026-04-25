#!/bin/bash
# ==============================================================================
#  IGOR — healing/checks/nextcloud.sh
#  Nextcloud application health check.
#
#  Checks occ status, maintenance mode, background jobs, log level,
#  and recent error count in the Nextcloud application log.
# ==============================================================================

CHECK_NAME="nextcloud"
CHECK_DESCRIPTION="Nextcloud application status, maintenance mode, error log, ownership drift"
CHECK_SCHEDULE="120"

# PATTERN_HINT nc_maintenance_stuck "Nextcloud stuck in maintenance mode" CHANGE "occ maintenance:mode --off"
# PATTERN_HINT nc_not_installed "Nextcloud reports not installed" CHANGE "docker compose up -d"
# PATTERN_HINT nc_log_errors "Many recent errors in nextcloud.log" READ "docker compose logs app --tail=50"
# PATTERN_HINT nc_perm_errors "NotPermittedException in NC log — root owns www-data dirs" CHANGE "sudo chown -R 1004:1004 NC_DATA/appdata_*"

run_check() {
    # ── occ availability ──────────────────────────────────────────────────────
    if ! command -v docker &>/dev/null; then
        echo "CHECK_RESULT FAIL nc_no_docker Docker not available — cannot check Nextcloud"
        return 0
    fi

    local occ_status
    occ_status=$(docker compose exec -T -u www-data app php occ status --output=json 2>/dev/null)

    if [ -z "$occ_status" ]; then
        echo "CHECK_RESULT FAIL nc_occ_unavailable occ command failed — app container may be down"
        return 0
    fi

    # ── Installation status ───────────────────────────────────────────────────
    local installed
    installed=$(echo "$occ_status" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(str(d.get('installed', False)).lower())
except: print('unknown')
" 2>/dev/null)

    case "$installed" in
        true)  echo "CHECK_RESULT OK nc_installed Nextcloud is installed" ;;
        false) echo "CHECK_RESULT CRITICAL nc_not_installed Nextcloud reports not installed — database may be empty"; return 0 ;;
        *)     echo "CHECK_RESULT WARN nc_status_unknown occ status returned unexpected result" ;;
    esac

    # ── Maintenance mode ──────────────────────────────────────────────────────
    local maintenance
    maintenance=$(echo "$occ_status" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(str(d.get('maintenance', False)).lower())
except: print('unknown')
" 2>/dev/null)

    if [ "$maintenance" = "true" ]; then
        echo "CHECK_RESULT WARN nc_maintenance Nextcloud is in maintenance mode — users cannot log in"
    else
        echo "CHECK_RESULT OK nc_not_maintenance Nextcloud not in maintenance mode"
    fi

    # ── Background jobs mode ──────────────────────────────────────────────────
    local bg_mode
    bg_mode=$(docker compose exec -T -u www-data app php occ \
        config:system:get background_jobs_mode 2>/dev/null | tr -d '[:space:]')

    if [ "$bg_mode" = "cron" ]; then
        echo "CHECK_RESULT OK nc_bg_cron Background jobs mode: cron (correct)"
    elif [ -n "$bg_mode" ]; then
        echo "CHECK_RESULT WARN nc_bg_mode Background jobs mode is '${bg_mode}' — should be 'cron' for Docker setup"
    fi

    # ── Log level ─────────────────────────────────────────────────────────────
    local loglevel
    loglevel=$(docker compose exec -T -u www-data app php occ \
        config:system:get loglevel 2>/dev/null | tr -d '[:space:]')

    if [ -n "$loglevel" ]; then
        if [ "$loglevel" -le 1 ] 2>/dev/null; then
            echo "CHECK_RESULT WARN nc_loglevel Log level is ${loglevel} (DEBUG/INFO) — high logging overhead on Pi 3"
        else
            echo "CHECK_RESULT OK nc_loglevel Log level: ${loglevel}"
        fi
    fi

    # ── Recent error count (last 6 hours) ────────────────────────────────────
    local error_count
    error_count=$(docker compose exec -T app \
        tail -500 /var/www/html/data/nextcloud.log 2>/dev/null | \
        python3 -c "
import sys, json
from datetime import datetime, timezone, timedelta
count = 0
cutoff = datetime.now(timezone.utc) - timedelta(hours=6)
for line in sys.stdin:
    try:
        e = json.loads(line.strip())
        if e.get('level', 0) >= 3:
            ts = e.get('time', '')
            try:
                dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
                if dt > cutoff:
                    count += 1
            except:
                count += 1
    except:
        pass
print(count)
" 2>/dev/null)

    if [ -n "$error_count" ] && [ "$error_count" -gt 0 ] 2>/dev/null; then
        if [ "$error_count" -ge 20 ]; then
            echo "CHECK_RESULT FAIL nc_many_errors ${error_count} errors in nextcloud.log in the last 6h — investigate immediately"
        elif [ "$error_count" -ge 5 ]; then
            echo "CHECK_RESULT WARN nc_some_errors ${error_count} errors in nextcloud.log in the last 6h"
        else
            echo "CHECK_RESULT OK nc_few_errors ${error_count} minor errors in nextcloud.log in the last 6h"
        fi
    else
        echo "CHECK_RESULT OK nc_no_errors No errors in nextcloud.log in the last 6h"
    fi

    # ── overwriteprotocol ─────────────────────────────────────────────────────
    local overwrite_proto
    overwrite_proto=$(docker compose exec -T -u www-data app php occ \
        config:system:get overwriteprotocol 2>/dev/null | tr -d '[:space:]')

    if [ "$overwrite_proto" = "https" ]; then
        echo "CHECK_RESULT OK nc_proto overwriteprotocol: https (correct for Cloudflare)"
    elif [ -n "$overwrite_proto" ]; then
        echo "CHECK_RESULT WARN nc_proto_wrong overwriteprotocol is '${overwrite_proto}' — should be 'https' for Cloudflare tunnel"
    fi

    # ── Ownership drift — NotPermittedException scan ──────────────────────────
    # USB disconnect/remount causes root to own www-data dirs, producing these errors
    local perm_hits
    perm_hits=$(docker compose exec -T app \
        grep -cE "NotPermittedException|could not create path|[Pp]ermission denied.*(appdata|data)" \
        /var/www/html/data/nextcloud.log 2>/dev/null | tail -1 | tr -d '[:space:]')

    if [ -n "$perm_hits" ] && [ "$perm_hits" -gt 0 ] 2>/dev/null; then
        # Confirm ownership drift by checking NC data root and appdata on host
        local nc_data="${NC_DATA:-/mnt/nextclouddata/next}"
        local expected_uid="${NC_UID:-1004}"

        # Check data root dir first — Nextcloud requires parent writable too
        local root_uid
        root_uid=$(stat -c "%u" "$nc_data" 2>/dev/null)

        local appdata_uid
        appdata_uid=$(find "$nc_data" -maxdepth 1 -name 'appdata_*' -type d \
            -exec stat -c "%u" {} \; 2>/dev/null | head -1)

        if [ "${root_uid}" != "$expected_uid" ] || { [ -n "$appdata_uid" ] && [ "$appdata_uid" != "$expected_uid" ]; }; then
            echo "CHECK_RESULT FAIL nc_perm_errors ${perm_hits} NotPermittedException errors + NC data dir owned by UID ${root_uid:-?} (expected ${expected_uid}) — ownership drift after USB remount. Fix: sudo chown -R ${expected_uid}:${NC_GID:-1004} ${nc_data} && docker compose restart app"
        else
            echo "CHECK_RESULT WARN nc_perm_errors ${perm_hits} permission errors in nextcloud.log — ownership looks correct, run deep scan to investigate"
        fi
    else
        echo "CHECK_RESULT OK nc_perm_ok No ownership-related permission errors in nextcloud.log"
    fi

    # ── Failed login attempts (last hour) ─────────────────────────────────────
    local login_fails
    login_fails=$(docker compose exec -T app \
        tail -500 /var/www/html/data/nextcloud.log 2>/dev/null | \
        python3 -c "
import sys, json
from datetime import datetime, timezone, timedelta
count = 0
cutoff = datetime.now(timezone.utc) - timedelta(hours=1)
for line in sys.stdin:
    try:
        e = json.loads(line.strip())
        msg = e.get('message', '')
        if 'Login failed' in msg or \
           (e.get('app','') in ('core','login') and 'failed' in msg.lower()):
            ts = e.get('time','')
            try:
                dt = datetime.fromisoformat(ts.replace('Z','+00:00'))
                if dt > cutoff:
                    count += 1
            except:
                count += 1
    except:
        pass
print(count)
" 2>/dev/null)

    if [ -n "$login_fails" ] && [ "$login_fails" -gt 0 ] 2>/dev/null; then
        if [ "$login_fails" -ge 10 ]; then
            echo "CHECK_RESULT FAIL nc_login_failed ${login_fails} failed login attempt(s) in the last hour — possible brute force"
        else
            echo "CHECK_RESULT WARN nc_login_failed ${login_fails} failed login attempt(s) in the last hour"
        fi
        declare -f notify_event &>/dev/null && \
            notify_event "nc_login_failed" \
                "${login_fails} failed login attempt(s) detected in the last hour on $(hostname 2>/dev/null || echo 'host') — check Nextcloud log for details" \
            2>/dev/null || true
    else
        echo "CHECK_RESULT OK nc_no_login_fails No failed login attempts in the last hour"
    fi

    # ── NC data volume free space ─────────────────────────────────────────────
    local nc_data="${NC_DATA:-/mnt/nextclouddata/next}"
    if [ -d "$nc_data" ]; then
        local _pct_used
        _pct_used=$(df "$nc_data" 2>/dev/null | awk 'NR==2{gsub(/%/,""); print $5}')
        if [ -n "$_pct_used" ] && [[ "$_pct_used" =~ ^[0-9]+$ ]]; then
            if [ "$_pct_used" -ge 95 ]; then
                echo "CHECK_RESULT FAIL nc_low_storage NC data volume ${_pct_used}% full — uploads will fail soon"
                declare -f notify_event &>/dev/null && \
                    notify_event "nc_low_storage" \
                        "NC data volume at ${_pct_used}% capacity on $(hostname 2>/dev/null || echo 'host') — free space critically low" \
                    2>/dev/null || true
            elif [ "$_pct_used" -ge 90 ]; then
                echo "CHECK_RESULT WARN nc_low_storage NC data volume ${_pct_used}% full — consider freeing space"
                declare -f notify_event &>/dev/null && \
                    notify_event "nc_low_storage" \
                        "NC data volume at ${_pct_used}% capacity on $(hostname 2>/dev/null || echo 'host') — running low" \
                    2>/dev/null || true
            else
                echo "CHECK_RESULT OK nc_storage NC data volume: ${_pct_used}% used"
            fi
        fi
    fi
}
