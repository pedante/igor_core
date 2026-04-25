#!/bin/bash
# ==============================================================================
#  IGOR — healing/checks/containers.sh
#  Docker container health check.
#
#  Checks that all expected containers are running and healthy.
#  Expected: app, web, db, redis, cron  (onlyoffice is optional/profile-based)
# ==============================================================================

CHECK_NAME="containers"
CHECK_DESCRIPTION="Docker container health — all required services running"
CHECK_SCHEDULE="60"

# PATTERN_HINT app_down "App container (php-fpm) is not running" CHANGE "docker compose up -d app"
# PATTERN_HINT web_down "Nginx web container is not running" CHANGE "docker compose up -d web"
# PATTERN_HINT db_down "PostgreSQL container is not running" CHANGE "docker compose up -d db"
# PATTERN_HINT redis_down "Redis container is not running" CHANGE "docker compose up -d redis"
# PATTERN_HINT cron_down "Cron container is not running" CHANGE "docker compose up -d cron"

run_check() {
    # Verify docker compose is available
    if ! command -v docker &>/dev/null; then
        echo "CHECK_RESULT FAIL containers_no_docker Docker is not installed or not in PATH"
        return 0
    fi

    if ! docker compose ps &>/dev/null 2>&1; then
        echo "CHECK_RESULT FAIL containers_compose_unavailable docker compose is not available or no compose file found"
        return 0
    fi

    local required_services=("app" "web" "db" "redis" "cron")
    local any_fail=false

    # Get running services by name (service name, not container name — works regardless of project prefix)
    local running_services exited_services all_known_services
    running_services=$(docker compose ps --status running --services 2>/dev/null)
    exited_services=$(docker compose ps  --status exited  --services 2>/dev/null)
    all_known_services="${running_services}${exited_services}"

    # If no services are running OR exited, the stack is completely down — report a
    # single WARN rather than 5x CRITICAL (being down may be intentional).
    if [ -z "$all_known_services" ]; then
        echo "CHECK_RESULT WARN stack_down Stack is not running — use menu 4 to start services"
        return 0
    fi

    for svc in "${required_services[@]}"; do
        if echo "$running_services" | grep -qx "$svc"; then
            echo "CHECK_RESULT OK ${svc}_running Container '${svc}' is running"
        elif echo "$exited_services" | grep -qx "$svc"; then
            echo "CHECK_RESULT FAIL ${svc}_down Container '${svc}' has exited"
            any_fail=true
        else
            echo "CHECK_RESULT CRITICAL ${svc}_down Container '${svc}' is not running or not found"
            any_fail=true
        fi
    done

    # ── Host disk usage ───────────────────────────────────────────────────────
    local hd_mount="${HD_MOUNT:-/}"
    local _disk_pct
    _disk_pct=$(df "$hd_mount" 2>/dev/null | awk 'NR==2{gsub(/%/,""); print $5}')
    if [ -n "$_disk_pct" ] && [[ "$_disk_pct" =~ ^[0-9]+$ ]]; then
        if [ "$_disk_pct" -ge 90 ]; then
            echo "CHECK_RESULT FAIL disk_usage Host disk (${hd_mount}) at ${_disk_pct}% — critical, containers may fail"
            declare -f notify_event &>/dev/null && \
                notify_event "disk_warning" \
                    "Host disk (${hd_mount}) is at ${_disk_pct}% capacity on $(hostname 2>/dev/null || echo 'host') — containers may fail to write" \
                2>/dev/null || true
        elif [ "$_disk_pct" -ge 80 ]; then
            echo "CHECK_RESULT WARN disk_usage Host disk (${hd_mount}) at ${_disk_pct}% — getting full"
        else
            echo "CHECK_RESULT OK disk_usage Host disk (${hd_mount}): ${_disk_pct}% used"
        fi
    fi

    # Check for containers consuming excessive memory (> 450MB on Pi 3)
    local mem_check
    mem_check=$(docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' 2>/dev/null)
    while IFS= read -r memline; do
        [ -z "$memline" ] && continue
        local cname cmem
        cname=$(echo "$memline" | awk '{print $1}')
        cmem=$(echo "$memline" | awk '{print $2}' | sed 's/MiB//')
        # Only flag if we can parse a numeric value
        if [[ "$cmem" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            local mem_int; mem_int=$(echo "$cmem" | cut -d. -f1)
            if [ "${mem_int:-0}" -gt 450 ]; then
                echo "CHECK_RESULT WARN ${cname}_mem_high Container '${cname}' using ${cmem}MiB — high for Pi 3"
            fi
        fi
    done <<< "$mem_check"
}
