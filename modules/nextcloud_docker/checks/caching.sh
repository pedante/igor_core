#!/bin/bash
# ==============================================================================
#  IGOR — healing/checks/caching.sh
#  Redis and Nextcloud caching configuration health check.
#
#  Checks Redis container response, memcache.local, and memcache.locking config.
#  Without Redis, Nextcloud will use file-based locking which degrades badly
#  under load — especially important on Pi 3 where I/O is already constrained.
# ==============================================================================

CHECK_NAME="caching"
CHECK_DESCRIPTION="Redis health and Nextcloud memcache configuration"
CHECK_SCHEDULE="120"

# PATTERN_HINT redis_not_responding "Redis not responding to PING" CHANGE "docker compose restart redis"
# PATTERN_HINT memcache_not_configured "memcache.local not configured in Nextcloud" CHANGE "occ config:system:set memcache.local --value='\\\\OC\\\\Memcache\\\\Redis'"

run_check() {
    # ── Redis container check ─────────────────────────────────────────────────
    if ! command -v docker &>/dev/null; then
        echo "CHECK_RESULT FAIL caching_no_docker Docker not available — cannot check Redis"
        return 0
    fi

    local redis_state
    redis_state=$(docker compose ps --format json 2>/dev/null | \
        python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
        svc = d.get('Service','') or d.get('Name','')
        if svc == 'redis' or 'redis' in svc.lower():
            print(d.get('State','unknown'))
            break
    except:
        pass
" 2>/dev/null)

    if [ -z "$redis_state" ]; then
        # Fallback: plain text
        redis_state=$(docker compose ps 2>/dev/null | awk '/redis/{print $NF; found=1} END {if(!found) print "missing"}')
    fi

    case "${redis_state:-missing}" in
        running|Up*)
            echo "CHECK_RESULT OK redis_running Redis container is running"
            ;;
        missing|"")
            echo "CHECK_RESULT FAIL redis_not_found Redis container not found — session locking will fail"
            return 0
            ;;
        *)
            echo "CHECK_RESULT FAIL redis_down Redis container state: ${redis_state} — session locking unavailable"
            return 0
            ;;
    esac

    # ── Redis PING ────────────────────────────────────────────────────────────
    local ping_result
    ping_result=$(docker compose exec -T redis redis-cli PING 2>/dev/null | tr -d '[:space:]')

    if [ "$ping_result" = "PONG" ]; then
        echo "CHECK_RESULT OK redis_ping Redis responding to PING"
    else
        echo "CHECK_RESULT FAIL redis_not_responding Redis not responding to PING (got: '${ping_result:-no response}')"
        return 0
    fi

    # ── Redis connection count ────────────────────────────────────────────────
    local connected_clients
    connected_clients=$(docker compose exec -T redis redis-cli INFO clients 2>/dev/null | \
        grep "^connected_clients:" | cut -d: -f2 | tr -d '[:space:]')

    if [ -n "$connected_clients" ] && [ "$connected_clients" -ge 50 ] 2>/dev/null; then
        echo "CHECK_RESULT WARN redis_many_clients Redis has ${connected_clients} connected clients — unusually high"
    elif [ -n "$connected_clients" ]; then
        echo "CHECK_RESULT OK redis_clients Redis client count: ${connected_clients}"
    fi

    # ── Nextcloud memcache.local ──────────────────────────────────────────────
    local memcache_local
    memcache_local=$(docker compose exec -T -u www-data app php occ \
        config:system:get memcache.local 2>/dev/null | tr -d '[:space:]')

    if echo "$memcache_local" | grep -qi "Redis\|APCu\|Memcached"; then
        echo "CHECK_RESULT OK memcache_local memcache.local configured: ${memcache_local}"
    elif [ -z "$memcache_local" ]; then
        echo "CHECK_RESULT WARN memcache_not_configured memcache.local not configured — Nextcloud uses file-based caching (slow on Pi 3)"
    else
        echo "CHECK_RESULT WARN memcache_unknown memcache.local set to unexpected value: ${memcache_local}"
    fi

    # ── Nextcloud memcache.locking ────────────────────────────────────────────
    local memcache_lock
    memcache_lock=$(docker compose exec -T -u www-data app php occ \
        config:system:get memcache.locking 2>/dev/null | tr -d '[:space:]')

    if echo "$memcache_lock" | grep -qi "Redis"; then
        echo "CHECK_RESULT OK memcache_locking memcache.locking configured: ${memcache_lock}"
    elif [ -z "$memcache_lock" ]; then
        echo "CHECK_RESULT WARN memcache_locking_not_set memcache.locking not configured — file locking active (can cause stalls on Pi 3)"
    else
        echo "CHECK_RESULT WARN memcache_locking_unknown memcache.locking set to unexpected value: ${memcache_lock}"
    fi

    # ── Redis memory usage ────────────────────────────────────────────────────
    local redis_mem
    redis_mem=$(docker compose exec -T redis redis-cli INFO memory 2>/dev/null | \
        grep "^used_memory_human:" | cut -d: -f2 | tr -d '[:space:]')

    if [ -n "$redis_mem" ]; then
        echo "CHECK_RESULT OK redis_memory Redis memory usage: ${redis_mem}"
    fi
}
