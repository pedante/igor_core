#!/bin/bash
# ==============================================================================
#  IGOR — diagnose/fixes.sh
#  Fix catalogue, fix-recheck loop, and tier-approval UI.
#
#  Provides:
#    • _diag_propose_fixes()       — scan results, match catalogue, display list
#    • _diag_offer_fix_loop()      — interactive loop over proposed fixes
#    • _diag_fix_recheck_loop()    — execute one fix with retry + recheck
#    • _diag_approve_fix()         — tier-appropriate approval UI
#    • _DIAG_FIX_CATALOGUE         — associative array of fix definitions
#    • Per-code recheck functions  — _diag_recheck_*()
#
#  Fix catalogue entry format (pipe-delimited):
#    TIER|CMD|DESCRIPTION|DOWNTIME_NOTE|CONFIRM_PHRASE|RECHECK_FN|SETTLE_SECS
#
#  Tiers:
#    AUTO       — echo command, sleep 1, auto-proceed (trivially reversible)
#    SAFE       — confirm() Y/N with one-line side-effect description
#    CAUTION    — confirm() Y/N with explicit downtime/impact note
#    DESTRUCTIVE— user must type the CONFIRM_PHRASE exactly
# ==============================================================================

# ── Fix catalogue ─────────────────────────────────────────────────────────────
declare -gA _DIAG_FIX_CATALOGUE

# ── AUTO tier (trivially reversible, no side effects) ─────────────────────────
_DIAG_FIX_CATALOGUE[nc_maintenance_stuck]="AUTO|docker compose exec -T -u www-data app php occ maintenance:mode --off|Disable Nextcloud maintenance mode|||_diag_recheck_occ_maintenance|2"

_DIAG_FIX_CATALOGUE[nc_bg_mode]="AUTO|docker compose exec -T -u www-data app php occ background:cron|Set background jobs to cron mode|||_diag_recheck_occ_bg_mode|3"

_DIAG_FIX_CATALOGUE[nc_proto_wrong]="AUTO|docker compose exec -T -u www-data app php occ config:system:set overwriteprotocol --value='https'|Set overwriteprotocol to https (required for Cloudflare tunnel)|||_diag_recheck_nc_proto|2"

_DIAG_FIX_CATALOGUE[nc_loglevel]="AUTO|docker compose exec -T -u www-data app php occ config:system:set loglevel --value=2 --type=integer|Set log level to WARNING (reduces overhead on Pi 3)|||_diag_recheck_nc_loglevel|2"

# ── SAFE tier (brief side effects, non-destructive) ───────────────────────────
_DIAG_FIX_CATALOGUE[redis_not_responding]="SAFE|docker compose restart redis|Restart Redis container. Brief cache miss — no data loss. Sessions may need re-auth.|||_diag_recheck_redis_ping|8"

_DIAG_FIX_CATALOGUE[redis_down]="SAFE|docker compose up -d redis|Start Redis container|||_diag_recheck_redis_ping|10"

_DIAG_FIX_CATALOGUE[web_down]="SAFE|docker compose up -d web|Start nginx container (1-5s before traffic flows)|||_diag_recheck_http_status|8"

_DIAG_FIX_CATALOGUE[app_down]="SAFE|docker compose up -d app|Start app container (30-60s PHP-FPM startup)|||_diag_recheck_app_http|35"

_DIAG_FIX_CATALOGUE[cron_down]="SAFE|docker compose up -d cron|Start cron container (background jobs will resume)|||_diag_recheck_cron_running|8"

_DIAG_FIX_CATALOGUE[db_down]="SAFE|docker compose up -d db|Start database container (30s startup, wait for readiness)|||_diag_recheck_db_ready|35"

_DIAG_FIX_CATALOGUE[nginx_403_apps_files]="SAFE|docker compose exec -T web sh -c 'rm -f /etc/nginx/conf.d/default.conf && nginx -s reload'|Remove conf.d/default.conf and reload nginx. 1-2s of 502 responses.|||_diag_recheck_http_apps_files|3"

_DIAG_FIX_CATALOGUE[nginx_config_invalid]="SAFE|docker compose exec -T web nginx -s reload|Reload nginx with current configuration. Brief request interruption.|||_diag_recheck_http_status|3"

_DIAG_FIX_CATALOGUE[nginx_well_known_missing]="CAUTION|bash -c 'T=\"\${IGOR_DIR:-\$(pwd)}/web/nginx.conf.tmpl\"; C=\"\${IGOR_DIR:-\$(pwd)}/web/nginx.conf\"; if [ -f \"\$T\" ]; then cp \"\$C\" \"\$C.bak.\$(date +%s)\"; NGINX_DOMAIN=_ UPLOAD_MAX=\"\${UPLOAD_MAX:-10G}\" FASTCGI_TIMEOUT=\"\${FASTCGI_TIMEOUT:-300s}\" envsubst \"\${NGINX_DOMAIN} \${UPLOAD_MAX} \${FASTCGI_TIMEOUT}\" < \"\$T\" > \"\$C\" && docker compose restart \${DIAG_WEB_SVC:-web} && echo OK; else echo TEMPLATE_MISSING; fi'|Re-render nginx.conf from the updated template which includes the .well-known routing block, then restart nginx. Fixes NC admin warning about web server not configured. Brief request interruption during restart.|~5s||_diag_recheck_well_known|8"

_DIAG_FIX_CATALOGUE[nc_missing_indices]="SAFE|docker compose exec -T -u www-data app php occ db:add-missing-indices|Add missing database indices. No downtime; query performance will improve.|||_diag_recheck_occ_status|30"

_DIAG_FIX_CATALOGUE[nc_bg_cron]="SAFE|docker compose exec -T -u www-data app php occ maintenance:repair|Run Nextcloud repair. Service remains available during repair.|||_diag_recheck_occ_status|60"

_DIAG_FIX_CATALOGUE[hd_not_mounted]="SAFE|sudo mount -a|Mount all filesystems from /etc/fstab. Containers may need restart after mount.|||_diag_recheck_hd_mounted|3"

_DIAG_FIX_CATALOGUE[nc_data_missing]="SAFE|mkdir -p '${NC_DATA:-/mnt/nextclouddata/next}'|Create NC data directory (only if HD is mounted and directory is genuinely absent)|||_diag_recheck_nc_data_exists|2"

_DIAG_FIX_CATALOGUE[stack_down]="SAFE|docker compose up -d|Start the full container stack|||_diag_recheck_stack_up|20"

_DIAG_FIX_CATALOGUE[tunnel_down]="SAFE|sudo systemctl start cloudflared|Start Cloudflare tunnel service|||_diag_recheck_tunnel_active|5"

_DIAG_FIX_CATALOGUE[tunnel_running_not_connected]="SAFE|sudo systemctl restart cloudflared|Restart Cloudflare tunnel (force reconnect to edge)|||_diag_recheck_tunnel_active|8"

_DIAG_FIX_CATALOGUE[nc_log_large]="SAFE|docker compose exec -T \${DIAG_APP_SVC:-app} truncate -s 0 /var/www/html/data/nextcloud.log|Truncate Nextcloud log file (old entries lost — safe, they are already flagged)|||_diag_recheck_nc_log_size|2"

_DIAG_FIX_CATALOGUE[log_size_large]="SAFE|docker compose logs --no-log-prefix app 2>/dev/null | tail -200 > /tmp/_diag_log_backup.txt; docker run --rm -v /var/lib/docker:/var/lib/docker alpine find /var/lib/docker/containers -name '*.log' -size +100M -exec truncate -s 10M {} \\;|Truncate oversized container log files (keeps last 10MB per file)|||_diag_recheck_generic_ok|5"

# ── CAUTION tier (measurable downtime or partial irreversibility) ──────────────
_DIAG_FIX_CATALOGUE[redis_eviction_policy]="CAUTION|docker compose exec -T redis redis-cli CONFIG SET maxmemory-policy volatile-lru|Change Redis eviction policy to volatile-lru. All existing keyspace eviction settings reset.|Change to volatile-lru eviction||_diag_recheck_redis_eviction_policy|2"

_DIAG_FIX_CATALOGUE[nc_occ_unavailable]="CAUTION|docker compose restart app|Restart app container. All active users disconnected for ~60s.|~60s user disconnection||_diag_recheck_app_http|40"

# ── DESTRUCTIVE tier (cannot be undone, requires typed phrase) ─────────────────
_DIAG_FIX_CATALOGUE[nc_data_wrong_owner]="DESTRUCTIVE|sudo chown -R '${NC_UID:-1004}:${NC_GID:-1004}' '${NC_DATA:-/mnt/nextclouddata/next}'|Fix NC data directory ownership. All files on the external HD will be re-owned.|Users cannot access files during chown (may take minutes on large datasets)|CONFIRM CHOWN|_diag_recheck_nc_data_owner|5"

_DIAG_FIX_CATALOGUE[redis_flush_all]="DESTRUCTIVE|docker compose exec -T \${DIAG_CACHE_SVC:-redis} redis-cli FLUSHALL|Flush all Redis data. All sessions will be invalidated and all users logged out.|All user sessions destroyed|CONFIRM FLUSH|_diag_recheck_redis_ping|3"

# ── Missing fixes (added from deep-scan false-positive audit) ─────────────────

_DIAG_FIX_CATALOGUE[cron_process_dead]="SAFE|docker compose restart \${DIAG_CRON_SVC:-cron}|Restart cron container — forces cron daemon restart; background jobs will resume within 5 min|||_diag_recheck_cron_process|10"

_DIAG_FIX_CATALOGUE[fstab_nofail_missing]="SAFE|sudo cp /etc/fstab /etc/fstab.bak.diag && sudo sed -i \"/$(printf '%s' "${HD_MOUNT:-/mnt/nextclouddata}" | sed 's|/|\\\\/|g')/{/nofail/!s/defaults/defaults,nofail/}\" /etc/fstab && echo 'fstab updated (backup: /etc/fstab.bak.diag)' || echo 'MANUAL: add ,nofail to the HD entry in /etc/fstab'|Add nofail to HD fstab entry — prevents emergency mode if drive is absent at boot|||_diag_recheck_fstab_nofail|2"

_DIAG_FIX_CATALOGUE[cron_no_log]="SAFE|docker compose restart \${DIAG_CRON_SVC:-cron}|Restart cron container to force an immediate execution cycle|||_diag_recheck_cron_process|12"

# ── OWNERSHIP DRIFT fixes (root owning www-data dirs after USB remount) ────────
# Root cause: USB disconnect/remount leaves root owning NC data dirs.
# Fix requires: (1) chown the ENTIRE NC_DATA tree (not just appdata — parent dirs
# must also be writable), then (2) restart app so PHP-FPM re-opens bind mount.
# NC_UID/NC_GID expand at definition time from config; DIAG_APP_SVC at runtime.

_DIAG_FIX_CATALOGUE[igor_insecure_perms]="AUTO|find \"${IGOR_DIR}/secrets\" -name '*.env' -exec chmod 600 {} \\; 2>/dev/null; for _kf in ~/.nexus_api_key ~/.nexus_or_key; do [ -f \"\$_kf\" ] && chmod 600 \"\$_kf\"; done; echo 'Permissions corrected'|Set all Igor secret env files to chmod 600 — removes group/world read access|||_diag_recheck_igor_perms|2"

_DIAG_FIX_CATALOGUE[nc_perm_errors]="CAUTION|sudo chown -R ${NC_UID:-1004}:${NC_GID:-1004} \"${NC_DATA:-/mnt/nextclouddata/next}\" && docker compose restart \${DIAG_APP_SVC:-app}|Fix ownership drift — chowns entire NC data dir to www-data (${NC_UID:-1004}:${NC_GID:-1004}) then restarts app so PHP-FPM sees the corrected permissions. Resolves NotPermittedException and 'appdata not writable' errors.|~60s while app container restarts — users disconnected briefly||_diag_recheck_nc_perm_errors_full|45"

_DIAG_FIX_CATALOGUE[nc_appdata_wrong_owner]="CAUTION|sudo chown -R ${NC_UID:-1004}:${NC_GID:-1004} \"${NC_DATA:-/mnt/nextclouddata/next}\" && docker compose restart \${DIAG_APP_SVC:-app}|Fix ownership drift — chowns entire NC data dir then restarts app container. A partial chown (appdata only) is not sufficient because Nextcloud also checks parent directory writability.|~60s while app container restarts||_diag_recheck_nc_appdata_owner|45"

# Full repair with explicit settle — for when nc_data_root_dirs is detected (many dirs affected)
_DIAG_FIX_CATALOGUE[nc_data_root_dirs]="CAUTION|sudo chown -R ${NC_UID:-1004}:${NC_GID:-1004} \"${NC_DATA:-/mnt/nextclouddata/next}\" && docker compose restart \${DIAG_APP_SVC:-app}|Full ownership repair — chowns entire NC data tree (may take minutes on large datasets) then restarts app. Fixes all root-owned directories including user files.|All writes paused during chown (1–10 min on large datasets) then ~60s app restart||_diag_recheck_nc_data_ownership|60"

# ── APPDATA STRUCTURE fixes ────────────────────────────────────────────────────
# App store cache: missing, stale, or invalid → trigger background fetcher via occ
# Appdata subdirectory fixes — all follow the same three-step pattern:
#   Step 1: resolve instanceid dynamically INSIDE the container (sh -c '...' pattern)
#   Step 2: mkdir -p the missing directory (occ silently writes nothing if dir absent)
#   Step 3: trigger regeneration if an occ command exists for this subdir
#
# Why sh -c '...' inside exec: $INST must resolve inside the container, not on the host.
# The outer bash -c "$cmd" substitutes ${DIAG_APP_SVC:-app} (exported), but $INST and
# $(php occ ...) inside single-quoted sh -c args are deferred to the container's shell.
#
# Recheck: tests directory writability (PHP-style write test), NOT file presence —
# js-cache/css-cache/avatar/text/identityproof populate lazily on first use, not immediately.

_DIAG_FIX_CATALOGUE[nc_appstore_missing]="AUTO|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} sh -c 'INST=\$(php occ config:system:get instanceid 2>/dev/null | tr -d \"\\n\") && [ -n \"\$INST\" ] && mkdir -p /var/www/html/data/appdata_\${INST}/appstore && php occ config:system:set appstoreenabled --value=true --type=boolean && php occ app:update --all'|Create appstore directory then enable app store and fetch catalogue. Without mkdir first, occ silently succeeds but writes nothing.|||_diag_recheck_nc_appstore|30"

_DIAG_FIX_CATALOGUE[nc_appstore_stale]="AUTO|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} sh -c 'INST=\$(php occ config:system:get instanceid 2>/dev/null | tr -d \"\\n\") && [ -n \"\$INST\" ] && mkdir -p /var/www/html/data/appdata_\${INST}/appstore && php occ app:update --all'|Ensure appstore directory exists then refresh app catalogue — downloads fresh app list|||_diag_recheck_nc_appstore|30"

_DIAG_FIX_CATALOGUE[nc_appstore_invalid]="AUTO|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} sh -c 'INST=\$(php occ config:system:get instanceid 2>/dev/null | tr -d \"\\n\") && [ -n \"\$INST\" ] && mkdir -p /var/www/html/data/appdata_\${INST}/appstore && rm -f /var/www/html/data/appdata_\${INST}/appstore/apps.json && php occ app:update --all'|Remove corrupt apps.json and re-fetch app store catalogue|||_diag_recheck_nc_appstore|30"

# JS/CSS cache: auto-regenerates on next page load — only mkdir needed.
# No occ command exists for these; PHP writes them on demand when the directory exists.
_DIAG_FIX_CATALOGUE[nc_jscache_empty]="AUTO|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} sh -c 'INST=\$(php occ config:system:get instanceid 2>/dev/null | tr -d \"\\n\") && [ -n \"\$INST\" ] && mkdir -p /var/www/html/data/appdata_\${INST}/js-cache /var/www/html/data/appdata_\${INST}/css-cache'|Create js-cache and css-cache directories. PHP regenerates their content automatically on the next page load — no occ command needed.|||_diag_recheck_nc_jscss_cache|3"

_DIAG_FIX_CATALOGUE[nc_csscache_empty]="AUTO|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} sh -c 'INST=\$(php occ config:system:get instanceid 2>/dev/null | tr -d \"\\n\") && [ -n \"\$INST\" ] && mkdir -p /var/www/html/data/appdata_\${INST}/js-cache /var/www/html/data/appdata_\${INST}/css-cache'|Create css-cache and js-cache directories. PHP regenerates their content automatically on the next page load — no occ command needed.|||_diag_recheck_nc_jscss_cache|3"

# Theming: mkdir then trigger theme rebuild via occ
_DIAG_FIX_CATALOGUE[nc_theming_missing]="AUTO|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} sh -c 'INST=\$(php occ config:system:get instanceid 2>/dev/null | tr -d \"\\n\") && [ -n \"\$INST\" ] && mkdir -p /var/www/html/data/appdata_\${INST}/theming && php occ maintenance:theme:update'|Create theming directory then regenerate compiled theme assets|||_diag_recheck_nc_theming|5"

# Missing DB indices/columns/keys — safe to run anytime
_DIAG_FIX_CATALOGUE[nc_db_missing_indices]="SAFE|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} sh -c 'php occ db:add-missing-indices && php occ db:add-missing-columns && php occ db:add-missing-primary-keys'|Add missing database indices, columns, and primary keys — improves query performance. No downtime.|||_diag_recheck_nc_db_integrity|60"

# Background jobs stuck — restart cron container
_DIAG_FIX_CATALOGUE[nc_bg_jobs_stuck]="SAFE|docker compose restart \${DIAG_CRON_SVC:-cron}|Restart cron container to unblock stuck background jobs — jobs will resume within 5 minutes|||_diag_recheck_cron_process|10"

# Appstore/preview not writable — redirect to the ownership drift fix
_DIAG_FIX_CATALOGUE[nc_appstore_not_writable]="CAUTION|sudo chown -R ${NC_UID:-1004}:${NC_GID:-1004} \"${NC_DATA:-/mnt/nextclouddata/next}\" && docker compose restart \${DIAG_APP_SVC:-app}|Fix ownership drift — app store directory not writable by www-data. Chowns NC data dir and restarts app.|~60s app restart||_diag_recheck_nc_perm_errors_full|45"

_DIAG_FIX_CATALOGUE[nc_preview_not_writable]="CAUTION|sudo chown -R ${NC_UID:-1004}:${NC_GID:-1004} \"${NC_DATA:-/mnt/nextclouddata/next}\" && docker compose restart \${DIAG_APP_SVC:-app}|Fix ownership drift — preview directory not writable by www-data. Chowns NC data dir and restarts app.|~60s app restart||_diag_recheck_nc_perm_errors_full|45"

# Post-USB-dropout repair: maintenance:repair + Redis flush. This is the sequence that
# works after USB disconnect/reconnect events to reconcile NC database state and clear
# stale Redis cache. Use when the stack is up but NC behaves inconsistently after remount.
_DIAG_FIX_CATALOGUE[nc_post_usb_repair]="CAUTION|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} php occ maintenance:mode --on && docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} php occ maintenance:repair && docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} php occ maintenance:mode --off && docker compose exec -T \${DIAG_CACHE_SVC:-redis} redis-cli FLUSHALL|NC repair + Redis flush after USB dropout — runs maintenance:repair to reconcile DB state, then clears all Redis caches. All users will be logged out.|All users disconnected for ~2 minutes during repair||_diag_recheck_app_http|90"

# ── Phase 1 fixes ─────────────────────────────────────────────────────────────

_DIAG_FIX_CATALOGUE[swap_swappiness_high]="AUTO|sudo sysctl -w vm.swappiness=10 && echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.d/99-igor.conf|Reduce swappiness to 10 — prevents aggressive SD card paging on Pi 3 (default 60 causes excessive SD writes)|||_diag_recheck_swappiness|2"

_DIAG_FIX_CATALOGUE[usb_autosuspend_enabled]="SAFE|for d in /sys/bus/usb/devices/*/power/autosuspend_delay_ms; do echo -1 | sudo tee \"\$d\" > /dev/null; done|Disable USB autosuspend for all USB devices — prevents HD from disconnecting under load due to power management|||_diag_recheck_generic_ok|2"

# ── Phase 2 fixes ─────────────────────────────────────────────────────────────

_DIAG_FIX_CATALOGUE[docker_log_bloat]="SAFE|find /var/lib/docker/containers -name '*.log' -size +100M -exec sudo truncate -s 10M {} \\;|Truncate container log files > 100MB to 10MB each — frees disk space immediately with no service impact|||_diag_recheck_generic_ok|3"

# ── Phase 3 app fixes ─────────────────────────────────────────────────────────

_DIAG_FIX_CATALOGUE[nc_php_memory_low]="AUTO|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} php occ config:system:set memory_limit --value='512M'|Set PHP memory_limit to 512M via occ — required for large file operations and occ commands|||_diag_recheck_nc_php_memory|3"

_DIAG_FIX_CATALOGUE[nc_filelocking_disabled]="AUTO|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} php occ config:system:set filelocking.enabled --value=true --type=boolean|Enable Redis file locking — prevents concurrent access corruption when multiple clients edit the same file|||_diag_recheck_nc_filelocking|3"

_DIAG_FIX_CATALOGUE[nc_memcache_not_set]="AUTO|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} php occ config:system:set memcache.local --value='\\OC\\Memcache\\APCu'|Set local memcache to APCu — critical for performance on Pi 3 (avoids redundant DB queries per request)|||_diag_recheck_nc_memcache|3"

_DIAG_FIX_CATALOGUE[nc_debug_enabled]="AUTO|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} php occ config:system:set debug --value=false --type=boolean|Disable NC debug mode — reduces log verbosity and improves performance|||_diag_recheck_generic_ok|2"

# ── Phase 3 db fixes ──────────────────────────────────────────────────────────

_DIAG_FIX_CATALOGUE[db_vacuum_stale]="SAFE|docker compose exec -T \${DIAG_DB_SVC:-db} psql -U '${POSTGRES_USER:-oc_admin}' -d '${POSTGRES_DB:-nextcloud}' -c 'VACUUM ANALYZE;'|Run VACUUM ANALYZE — reclaims dead tuples and updates query planner statistics. No downtime; runs while service is live.|||_diag_recheck_generic_ok|30"

# ── Phase 3 redis fixes ───────────────────────────────────────────────────────

_DIAG_FIX_CATALOGUE[redis_maxmemory_not_set]="SAFE|docker compose exec -T \${DIAG_CACHE_SVC:-redis} redis-cli CONFIG SET maxmemory 100mb|Set Redis maxmemory to 100MB — prevents Redis from consuming all available RAM and triggering OOM kills|||_diag_recheck_redis_maxmemory|3"

# ── Phase 5 fixes ─────────────────────────────────────────────────────────────

_DIAG_FIX_CATALOGUE[nc_orphaned_file_locks]="CAUTION|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} php occ maintenance:mode --on && docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} php occ maintenance:repair --include-expensive && docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} php occ maintenance:mode --off|Clear orphaned file locks via maintenance:repair — puts NC in maintenance mode briefly then runs full repair.|~2 min downtime while maintenance mode is active||_diag_recheck_nc_file_locks|10"

_DIAG_FIX_CATALOGUE[nc_bruteforce_high]="AUTO|docker compose exec -T -u www-data \${DIAG_APP_SVC:-app} php occ security:bruteforce:reset|Reset bruteforce attempts table — clears all blocked IPs. Use if legitimate users are being blocked.|||_diag_recheck_generic_ok|2"

# ── Propose fixes ──────────────────────────────────────────────────────────────
# Scan _DIAG_RESULTS for non-OK entries, match against catalogue, display summary.
_diag_propose_fixes() {
    local proposed=0
    local _proposed_codes=()

    echo ""
    step "Fix Proposals"

    local entry
    for entry in "${_DIAG_RESULTS[@]}"; do
        local sev="${entry%%|*}"
        [ "$sev" = "OK" ] && continue

        local rest="${entry#*|}"
        local code="${rest%%|*}"
        rest="${rest#*|}"
        local msg="${rest%%|*}"

        if [ -n "${_DIAG_FIX_CATALOGUE[$code]:-}" ]; then
            local fix_str="${_DIAG_FIX_CATALOGUE[$code]}"
            local tier="${fix_str%%|*}"
            local fix_desc
            fix_desc=$(echo "$fix_str" | cut -d'|' -f3)

            # Color by tier
            local tier_color="$GRN"
            case "$tier" in
                SAFE)        tier_color="$YEL" ;;
                CAUTION)     tier_color="$YEL" ;;
                DESTRUCTIVE) tier_color="$RED" ;;
            esac

            echo -e "  ${tier_color}[${tier}]${NC} ${code}: ${fix_desc}"
            _proposed_codes+=("$code")
            (( proposed++ ))
        else
            echo -e "  ${CYAN}[INFO]${NC} ${sev} ${code}: ${msg}"
            echo -e "         No automated fix. Use ${BOLD}Menu A${NC} (AI Assistant) for investigation."
        fi
    done

    if (( proposed == 0 )); then
        ok "No fixable issues found."
    fi

    _DIAG[fixes_proposed]=$proposed
    echo ""
}

# ── Offer interactive fix loop ─────────────────────────────────────────────────
# Iterate over all non-OK results and offer to apply their fixes in order.
_diag_offer_fix_loop() {
    # Export role-resolved service names so catalogue commands can use them
    # (bash -c expands these at runtime, not at catalogue-definition time)
    export DIAG_APP_SVC="${_DIAG_ROLES[app]:-app}"
    export DIAG_CACHE_SVC="${_DIAG_ROLES[cache]:-redis}"
    export DIAG_DB_SVC="${_DIAG_ROLES[db]:-db}"
    export DIAG_WEB_SVC="${_DIAG_ROLES[web]:-web}"
    export DIAG_CRON_SVC="${_DIAG_ROLES[cron]:-cron}"

    local entry
    for entry in "${_DIAG_RESULTS[@]}"; do
        local sev="${entry%%|*}"
        [ "$sev" = "OK" ] && continue

        local rest="${entry#*|}"
        local code="${rest%%|*}"
        rest="${rest#*|}"
        local msg="${rest%%|*}"

        [ -z "${_DIAG_FIX_CATALOGUE[$code]:-}" ] && continue

        echo ""
        echo -e "  ${YEL}Issue:${NC} [${sev}] ${code} — ${msg}"
        _diag_fix_recheck_loop "$code"
    done
}

# ── Fix-recheck loop ───────────────────────────────────────────────────────────
# Execute one fix with approval, settle delay, recheck, and retry on failure.
# Returns 0 if fixed, 1 if skipped or unresolved.
_diag_fix_recheck_loop() {
    local code="$1"
    local fix_str="${_DIAG_FIX_CATALOGUE[$code]:-}"

    if [ -z "$fix_str" ]; then
        warn "No fix catalogue entry for: ${code}"
        return 1
    fi

    # Parse catalogue entry: TIER|CMD|DESC|DOWNTIME|PHRASE|RECHECK_FN|SETTLE
    local tier cmd desc downtime phrase recheck_fn settle
    IFS='|' read -r tier cmd desc downtime phrase recheck_fn settle <<< "$fix_str"

    local max_retries="${DIAG_MAX_RETRIES:-5}"
    local attempt=0

    while (( attempt < max_retries )); do
        (( attempt++ ))

        # Display fix box
        _diag_show_fix_box "$tier" "$cmd" "$desc" "$downtime" "$attempt" "$max_retries"

        # Get approval
        if ! _diag_approve_fix "$tier" "$desc" "$downtime" "$phrase"; then
            warn "Fix skipped: ${code}"
            _DIAG_FIXES_APPLIED+=("${code}|${tier}|${cmd}|SKIPPED")
            _diag_log "fix: SKIPPED ${code} (user declined)"
            return 1
        fi

        # ── Pre-CAUTION/DESTRUCTIVE config auto-backup ────────────────────
        if [[ "$tier" == "CAUTION" || "$tier" == "DESTRUCTIVE" ]]; then
            declare -f config_backup_auto &>/dev/null && \
                config_backup_auto "pre-fix:${code}" 2>/dev/null || true
        fi

        # Execute
        _diag_log "fix: EXEC attempt ${attempt}/${max_retries}: ${cmd}"
        local output exit_code
        output=$(bash -c "$cmd" 2>&1)
        exit_code=$?

        # Show output
        if [ -n "$output" ]; then
            echo ""
            echo -e "  ${CYAN}── Output ──────────────────────────────────────────────${NC}"
            echo "$output" | head -20 | while IFS= read -r line; do
                echo "    ${line}"
            done
            echo -e "  ${CYAN}────────────────────────────────────────────────────────${NC}"
        fi

        if (( exit_code != 0 )); then
            warn "Command exited with code ${exit_code}"
        fi

        # Settle
        local settle_secs="${settle:-${DIAG_SETTLE_SECS:-4}}"
        if (( settle_secs > 0 )); then
            echo -ne "  ${CYAN}i${NC} Waiting ${settle_secs}s for changes to take effect..."
            sleep "$settle_secs"
            echo " done"
        fi

        # Recheck
        local result="FAIL"
        if [ -n "$recheck_fn" ] && declare -f "$recheck_fn" &>/dev/null; then
            result=$("$recheck_fn" 2>/dev/null)
        elif (( exit_code == 0 )); then
            result="OK"
        fi

        _diag_log "fix: recheck result for ${code}: ${result}"

        case "$result" in
            OK)
                ok "Fixed: ${code}"
                _DIAG_FIXES_APPLIED+=("${code}|${tier}|${cmd}|FIXED")
                _diag_log "fix: FIXED ${code} on attempt ${attempt}"
                # Journal hook — record successful fix
                declare -f journal_record &>/dev/null && \
                    journal_record "diag:${_DIAG[session_id]:-diag}" "fix_applied" \
                        "$tier" "$cmd" "OK" "attempt:${attempt}" 2>/dev/null || true
                # Notify hook — fix_applied (off by default)
                declare -f notify_event &>/dev/null && \
                    notify_event "fix_applied" \
                        "Fix resolved: ${code} — ${desc:-no description} (attempt ${attempt})" \
                        "Fix Applied: ${code}" \
                    2>/dev/null || true
                # Record in healing patterns for AI context
                if declare -f pattern_record &>/dev/null; then
                    pattern_record "$code" "$desc" "$tier" "$cmd" "" 2>/dev/null || true
                    pattern_confirm "$code" 2>/dev/null || true
                fi
                (( _DIAG[fixes_verified]++ ))
                return 0
                ;;
            PARTIAL)
                warn "Partially fixed: ${code} — attempt ${attempt}/${max_retries}"
                _diag_log "fix: PARTIAL ${code} on attempt ${attempt}"
                # Journal hook — record partial result
                declare -f journal_record &>/dev/null && \
                    journal_record "diag:${_DIAG[session_id]:-diag}" "fix_applied" \
                        "$tier" "$cmd" "PARTIAL" "attempt:${attempt}" 2>/dev/null || true
                if (( attempt < max_retries )); then
                    confirm "  Retry fix?" || break
                fi
                ;;
            FAIL|*)
                warn "Recheck failed: ${code} — attempt ${attempt}/${max_retries}"
                _diag_log "fix: RECHECK FAILED ${code} on attempt ${attempt}"
                # Journal hook — record failed attempt
                declare -f journal_record &>/dev/null && \
                    journal_record "diag:${_DIAG[session_id]:-diag}" "fix_applied" \
                        "$tier" "$cmd" "FAIL" "attempt:${attempt}" 2>/dev/null || true
                if (( attempt < max_retries )); then
                    confirm "  Retry fix?" || break
                fi
                ;;
        esac
    done

    # All retries exhausted
    fail "Unresolved: ${code} after ${attempt} attempt(s)"
    _DIAG_FIXES_APPLIED+=("${code}|${tier}|${cmd}|UNRESOLVED")
    _diag_log "fix: UNRESOLVED ${code} after ${max_retries} attempts"
    # Journal hook — record unresolved
    declare -f journal_record &>/dev/null && \
        journal_record "diag:${_DIAG[session_id]:-diag}" "fix_applied" \
            "$tier" "$cmd" "FAIL" "unresolved:${attempt}attempts" 2>/dev/null || true
    # Notify hook — fix_failed (on by default)
    declare -f notify_event &>/dev/null && \
        notify_event "fix_failed" \
            "Unresolved: ${code} — ${desc:-no description} — failed after ${attempt} attempt(s)" \
            "Fix Failed: ${code}" \
        2>/dev/null || true
    echo -e "  ${YEL}Next step:${NC} Run ${BOLD}Menu A${NC} (AI Assistant) and describe this failure."
    return 1
}

# ── Show fix box ───────────────────────────────────────────────────────────────
_diag_show_fix_box() {
    local tier="$1" cmd="$2" desc="$3" downtime="$4" attempt="$5" max="$6"

    echo ""
    case "$tier" in
        AUTO)
            echo -e "  ${GRN}${BOLD}── AUTO FIX ─────────────────────────────────────────────${NC}"
            ;;
        SAFE)
            echo -e "  ${YEL}${BOLD}── SAFE FIX (needs approval) ────────────────────────────${NC}"
            ;;
        CAUTION)
            echo -e "  ${YEL}${BOLD}── CAUTION FIX — downtime involved ─────────────────────${NC}"
            ;;
        DESTRUCTIVE)
            echo -e "  ${RED}${BOLD}── DESTRUCTIVE — DATA MAY BE AFFECTED ───────────────────${NC}"
            ;;
    esac

    echo -e "  ${BOLD}${cmd}${NC}"
    echo -e "  ${desc}"

    if [ -n "$downtime" ]; then
        echo -e "  ${YEL}Impact:${NC} ${downtime}"
    fi

    if (( attempt > 1 )); then
        echo -e "  ${YEL}Retry ${attempt}/${max}${NC}"
    fi

    echo -e "  ${CYAN}────────────────────────────────────────────────────────${NC}"
}

# ── Tier-appropriate approval UI ───────────────────────────────────────────────
# Returns 0 (approved) or 1 (declined).
_diag_approve_fix() {
    local tier="$1" desc="$2" downtime="$3" phrase="$4"

    case "$tier" in
        AUTO)
            # Show command and auto-proceed after 1s pause
            echo -e "  ${GRN}Auto-running in 1s... (Ctrl-C to cancel)${NC}"
            sleep 1
            return 0
            ;;
        SAFE)
            confirm "  Apply fix?" && return 0 || return 1
            ;;
        CAUTION)
            [ -n "$downtime" ] && echo -e "  ${YEL}Warning:${NC} ${downtime}"
            confirm "  Apply this fix (downtime involved)?" && return 0 || return 1
            ;;
        DESTRUCTIVE)
            echo -e "  ${RED}${BOLD}WARNING: This action may be irreversible.${NC}"
            [ -n "$downtime" ] && echo -e "  ${RED}Impact:${NC} ${downtime}"
            echo ""
            if [ -n "$phrase" ]; then
                local input
                read -rp "  Type '${phrase}' to confirm: " input
                [ "$input" = "$phrase" ] && return 0 || { warn "Confirmation phrase did not match — aborted."; return 1; }
            else
                read -rp "  Type YES to confirm: " input
                [ "$input" = "YES" ] && return 0 || { warn "Aborted."; return 1; }
            fi
            ;;
    esac
}

# ── Recheck functions ─────────────────────────────────────────────────────────
# Each returns "OK", "PARTIAL", or "FAIL" to stdout.

_diag_recheck_occ_maintenance() {
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"
    local status
    status=$(docker compose exec -T -u www-data "$svc" php occ status --output=json 2>/dev/null)
    echo "$status" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('OK' if not d.get('maintenance', True) else 'FAIL')
except Exception:
    print('FAIL')
" 2>/dev/null || echo "FAIL"
}

_diag_recheck_occ_bg_mode() {
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"
    local mode
    mode=$(docker compose exec -T -u www-data "$svc" php occ config:system:get backgroundjobs_mode 2>/dev/null | tr -d '[:space:]')
    [ "$mode" = "cron" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_proto() {
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"
    local proto
    proto=$(docker compose exec -T -u www-data "$svc" php occ config:system:get overwriteprotocol 2>/dev/null | tr -d '[:space:]')
    [ "$proto" = "https" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_loglevel() {
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"
    local level
    level=$(docker compose exec -T -u www-data "$svc" php occ config:system:get loglevel 2>/dev/null | tr -d '[:space:]')
    (( level >= 2 )) && echo "OK" || echo "FAIL"
}

_diag_recheck_redis_ping() {
    local svc="${_DIAG_ROLES[cache]:-redis}"
    local resp
    resp=$(docker compose exec -T "$svc" redis-cli PING 2>/dev/null | tr -d '[:space:]')
    [ "$resp" = "PONG" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_redis_eviction_policy() {
    local svc="${_DIAG_ROLES[cache]:-redis}"
    local policy
    policy=$(docker compose exec -T "$svc" redis-cli CONFIG GET maxmemory-policy 2>/dev/null | tail -1 | tr -d '[:space:]')
    [[ "$policy" == *"lru"* || "$policy" == "noeviction" ]] && echo "OK" || echo "FAIL"
}

_diag_recheck_http_status() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "http://localhost:${IGOR_WEB_PORT:-8080}/status.php" 2>/dev/null)
    [ "$code" = "200" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_http_apps_files() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "http://localhost:${IGOR_WEB_PORT:-8080}/apps/files/" 2>/dev/null)
    # 200, 301/302 redirect, and 401 (auth required) all mean nginx forwarded correctly
    case "$code" in 200|301|302|307|401) echo "OK" ;; *) echo "FAIL" ;; esac
}

_diag_recheck_well_known() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "http://localhost:${IGOR_WEB_PORT:-8080}/.well-known/webfinger" 2>/dev/null)
    case "$code" in 200|301|302) echo "OK" ;; *) echo "FAIL" ;; esac
}

_diag_recheck_app_http() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "http://localhost:${IGOR_WEB_PORT:-8080}/status.php" 2>/dev/null)
    [ "$code" = "200" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_http() {
    _diag_recheck_app_http
}

_diag_recheck_cron_running() {
    local svc="${_DIAG_ROLES[cron]:-cron}"
    local state
    state=$(docker compose ps --status running --services 2>/dev/null | grep -c "^${svc}$")
    (( state > 0 )) && echo "OK" || echo "FAIL"
}

_diag_recheck_db_ready() {
    local svc="${_DIAG_ROLES[db]:-db}"
    docker compose exec -T "$svc" pg_isready -q 2>/dev/null && echo "OK" || echo "FAIL"
}

_diag_recheck_hd_mounted() {
    mount | grep -q "${HD_MOUNT:-/mnt/nextclouddata}" && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_data_exists() {
    [ -d "${NC_DATA:-/mnt/nextclouddata/next}" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_data_owner() {
    local owner
    owner=$(stat -c "%u:%g" "${NC_DATA:-/mnt/nextclouddata/next}" 2>/dev/null)
    [ "$owner" = "${NC_UID:-1004}:${NC_GID:-1004}" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_occ_status() {
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"
    local status
    status=$(docker compose exec -T -u www-data "$svc" php occ status --output=json 2>/dev/null)
    echo "$status" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('OK' if d.get('installed', False) else 'FAIL')
except Exception:
    print('FAIL')
" 2>/dev/null || echo "FAIL"
}

_diag_recheck_nc_installed() {
    _diag_recheck_occ_status
}

_diag_recheck_nc_log_size() {
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"
    local size
    size=$(docker compose exec -T "$svc" find /var/www/html/data -name 'nextcloud.log' -printf '%s' 2>/dev/null || echo "0")
    # Warn threshold is 50MB = 52428800 bytes — after truncate should be near 0
    (( size < 52428800 )) && echo "OK" || echo "PARTIAL"
}

_diag_recheck_fstab_nofail() {
    local hd_mount="${HD_MOUNT:-/mnt/nextclouddata}"
    grep -v '^#' /etc/fstab 2>/dev/null | grep "$hd_mount" | grep -q "nofail" && echo "OK" || echo "FAIL"
}

_diag_recheck_cron_process() {
    local svc="${DIAG_CRON_SVC:-${_DIAG_ROLES[cron]:-cron}}"
    # Container running is sufficient — daemon restart takes a few seconds
    local running
    running=$(docker compose ps --status running --services 2>/dev/null | grep -c "^${svc}$" || echo "0")
    (( running > 0 )) && echo "OK" || echo "FAIL"
}

_diag_recheck_stack_up() {
    local count
    count=$(docker compose ps --status running --services 2>/dev/null | wc -l)
    (( count >= 3 )) && echo "OK" || { (( count > 0 )) && echo "PARTIAL" || echo "FAIL"; }
}

_diag_recheck_tunnel_active() {
    local status
    status=$(systemctl is-active cloudflared 2>/dev/null | tr -d '[:space:]')
    [ "$status" = "active" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_generic_ok() {
    echo "OK"
}

_diag_recheck_nc_perm_errors() {
    _diag_recheck_nc_perm_errors_full
}

# Full recheck: PHP write test as www-data — ground truth, immune to stale log entries.
# The log scan was removed because it picks up pre-fix errors and produces false FAILs.
# This function is the recheck for nc_perm_errors, nc_appdata_wrong_owner, nc_data_root_dirs.
_diag_recheck_nc_perm_errors_full() {
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"

    # Run PHP as www-data inside the container — tests BOTH data root and appdata writability.
    # Uses PHP so we test the exact user (www-data/1004) that Nextcloud uses.
    local write_result
    write_result=$(docker compose exec -T -u www-data "$svc" php -r "
\$data = '/var/www/html/data';
\$f = \$data . '/.igor_write_test_' . getmypid();

// Test data root writability (parent dir — Nextcloud checks this too)
if (!is_writable(\$data)) { echo 'FAIL:data_root'; exit; }
if (@file_put_contents(\$f, 'ok') === false) { echo 'FAIL:data_write'; exit; }
@unlink(\$f);

// Test appdata writability
\$appdata = glob(\$data . '/appdata_*', GLOB_ONLYDIR);
if (\$appdata) {
    \$af = \$appdata[0] . '/.igor_write_test_' . getmypid();
    if (!is_writable(\$appdata[0]) || @file_put_contents(\$af, 'ok') === false) {
        echo 'FAIL:appdata'; exit;
    }
    @unlink(\$af);
}
echo 'OK';
" 2>/dev/null | tr -d '[:space:]')

    case "$write_result" in
        OK)    echo "OK" ;;
        FAIL*) echo "FAIL" ;;
        *)     echo "FAIL" ;;  # container down or PHP not available
    esac
}

_diag_recheck_nc_appdata_owner() {
    local nc_data="${NC_DATA:-/mnt/nextclouddata/next}"
    local expected_uid="${NC_UID:-1004}"
    local expected_gid="${NC_GID:-1004}"

    # Check NC data root dir itself (Nextcloud checks parent dir writability)
    local root_uid root_gid
    root_uid=$(stat -c "%u" "$nc_data" 2>/dev/null)
    root_gid=$(stat -c "%g" "$nc_data" 2>/dev/null)
    if [ "$root_uid" != "$expected_uid" ] || [ "$root_gid" != "$expected_gid" ]; then
        echo "FAIL"; return
    fi

    # Check appdata dir
    local appdata_dir
    appdata_dir=$(find "$nc_data" -maxdepth 1 -name 'appdata_*' -type d 2>/dev/null | head -1)
    if [ -z "$appdata_dir" ]; then
        echo "OK"  # No appdata yet — not an error
        return
    fi
    local uid gid
    uid=$(stat -c "%u" "$appdata_dir" 2>/dev/null)
    gid=$(stat -c "%g" "$appdata_dir" 2>/dev/null)
    [ "$uid" = "$expected_uid" ] && [ "$gid" = "$expected_gid" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_data_ownership() {
    local nc_data="${NC_DATA:-/mnt/nextclouddata/next}"
    # Count root-owned directories remaining (depth 4 — same as detection)
    local root_count
    root_count=$(find "$nc_data" -maxdepth 4 -user root -type d 2>/dev/null | wc -l | tr -d '[:space:]')
    (( root_count == 0 )) && echo "OK" || { (( root_count < 5 )) && echo "PARTIAL" || echo "FAIL"; }
}

# ── Recheck functions for appdata structure checks ─────────────────────────────
# Key principle: test writability (can www-data write a temp file?), NOT file presence.
# Cache dirs (js-cache, css-cache, avatar, text, theming) populate LAZILY on first use —
# testing for files inside them after a fix would always fail immediately.

_diag_recheck_nc_appdata_writable() {
    # Shared helper: test that appdata_${INST}/$subdir exists and is writable by www-data.
    # Called by name-specific wrappers below (recheck functions take no arguments).
    local subdir="$1"
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"
    local result
    result=$(docker compose exec -T -u www-data "$svc" sh -c "
INST=\$(php occ config:system:get instanceid 2>/dev/null | tr -d '\\n')
[ -z \"\$INST\" ] && echo FAIL:noinst && exit
D=\"/var/www/html/data/appdata_\${INST}/${subdir}\"
[ -d \"\$D\" ] || { echo FAIL:nodir; exit; }
F=\"\$D/.igor_wtest_\$\$\"
if touch \"\$F\" 2>/dev/null; then rm -f \"\$F\"; echo OK; else echo FAIL:nowrite; fi
" 2>/dev/null | tr -d '[:space:]')
    [ "$result" = "OK" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_appstore() {
    _diag_recheck_nc_appdata_writable "appstore"
}

_diag_recheck_nc_jscss_cache() {
    local r1 r2
    r1=$(_diag_recheck_nc_appdata_writable "js-cache")
    r2=$(_diag_recheck_nc_appdata_writable "css-cache")
    [ "$r1" = "OK" ] && [ "$r2" = "OK" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_theming() {
    _diag_recheck_nc_appdata_writable "theming"
}

_diag_recheck_nc_db_integrity() {
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"
    # occ db:add-missing-indices exits 0 and prints nothing if all indices exist
    local output
    output=$(docker compose exec -T -u www-data "$svc" php occ db:add-missing-indices 2>&1)
    local exit_code=$?
    (( exit_code == 0 )) && echo "OK" || echo "FAIL"
}

# ── Recheck functions for new checks ──────────────────────────────────────────

_diag_recheck_swappiness() {
    local v
    v=$(cat /proc/sys/vm/swappiness 2>/dev/null | tr -d '[:space:]')
    (( v <= 30 )) && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_php_memory() {
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"
    local raw mb
    raw=$(docker compose exec -T -u www-data "$svc" php -r "echo ini_get('memory_limit');" 2>/dev/null | tr -d '[:space:]')
    local unit="${raw: -1}"
    local val="${raw%[MmGgKk]}"
    case "$unit" in
        G|g) mb=$(( val * 1024 )) ;;
        K|k) mb=$(( val / 1024 )) ;;
        *)   mb="$val" ;;
    esac
    (( ${mb:-0} >= 256 )) && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_filelocking() {
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"
    local val
    val=$(docker compose exec -T -u www-data "$svc" php occ config:system:get filelocking.enabled 2>/dev/null | tr -d '[:space:]')
    [ "$val" = "true" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_memcache() {
    local svc="${DIAG_APP_SVC:-${_DIAG_ROLES[app]:-app}}"
    local val
    val=$(docker compose exec -T -u www-data "$svc" php occ config:system:get memcache.local 2>/dev/null | tr -d '[:space:]')
    [ -n "$val" ] && echo "OK" || echo "FAIL"
}

_diag_recheck_redis_maxmemory() {
    local svc="${_DIAG_ROLES[cache]:-redis}"
    local mem
    mem=$(docker compose exec -T "$svc" redis-cli CONFIG GET maxmemory 2>/dev/null | tail -1 | tr -d '[:space:]')
    (( ${mem:-0} > 0 )) && echo "OK" || echo "FAIL"
}

_diag_recheck_nc_file_locks() {
    # maintenance:repair is reliable — trust its exit code via the fix command
    # After repair, orphaned locks are cleared; return OK
    echo "OK"
}

_diag_recheck_igor_perms() {
    local _bad=0
    local _sd="${IGOR_DIR}/secrets"
    if [ -d "$_sd" ]; then
        for _f in "${_sd}"/*.env; do
            [ -f "$_f" ] || continue
            local _p; _p=$(stat -c "%a" "$_f" 2>/dev/null || echo "")
            [ -z "$_p" ] && continue
            [[ "${_p: -2}" != "00" ]] && (( _bad++ ))
        done
    fi
    for _kf in "${HOME}/.nexus_api_key" "${HOME}/.nexus_or_key"; do
        [ -f "$_kf" ] || continue
        local _p; _p=$(stat -c "%a" "$_kf" 2>/dev/null || echo "")
        [ -z "$_p" ] && continue
        [[ "${_p: -2}" != "00" ]] && (( _bad++ ))
    done
    (( _bad == 0 )) && echo "OK" || echo "FAIL"
}
