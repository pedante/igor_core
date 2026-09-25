#!/bin/bash
# ==============================================================================
#  IGOR — healing/checks/network.sh
#  Network and tunnel health check.
#
#  Checks internet connectivity, DNS resolution, Cloudflare tunnel status,
#  and HTTP routing through nginx (status.php, login, /apps/files/).
# ==============================================================================

CHECK_NAME="network"
CHECK_DESCRIPTION="Internet, DNS, Cloudflare tunnel, and HTTP routing"
CHECK_SCHEDULE="120"

# PATTERN_HINT tunnel_down "Cloudflare tunnel is not running" CHANGE "sudo systemctl restart cloudflared"
# PATTERN_HINT nginx_routing_fail "nginx not returning 200 on status.php" CHANGE "docker compose restart web"

run_check() {
    # ── Internet connectivity ─────────────────────────────────────────────────
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null 2>&1; then
        echo "CHECK_RESULT OK internet_reachable Internet connectivity: reachable"
    else
        echo "CHECK_RESULT WARN internet_unreachable Internet not reachable — check ISP or router"
    fi

    # ── DNS resolution ────────────────────────────────────────────────────────
    if ping -c 1 -W 3 google.com &>/dev/null 2>&1 || \
       getent hosts google.com &>/dev/null 2>&1; then
        echo "CHECK_RESULT OK dns_resolving DNS resolution working"
    else
        echo "CHECK_RESULT WARN dns_not_resolving DNS not resolving — check /etc/resolv.conf"
    fi

    # ── Cloudflare tunnel ─────────────────────────────────────────────────────
    if command -v systemctl &>/dev/null; then
        local cf_active
        cf_active=$(systemctl is-active cloudflared 2>/dev/null) || true
        cf_active=${cf_active:-unknown}

        case "$cf_active" in
            active)
                # Service is active — check for actual registration
                if journalctl -u cloudflared -n 50 --no-pager 2>/dev/null \
                        | grep -qE "Connection registered|Connection established|Registered tunnel|Connected to|connectedToEdge|Tunnel connection"; then
                    echo "CHECK_RESULT OK tunnel_connected Cloudflare tunnel: connected and registered"
                else
                    echo "CHECK_RESULT WARN tunnel_running_not_connected Cloudflare tunnel service active but no connection confirmed in recent logs"
                fi
                ;;
            inactive|failed)
                echo "CHECK_RESULT FAIL tunnel_down Cloudflare tunnel service is ${cf_active} — external access unavailable"
                declare -f notify_event &>/dev/null && \
                    notify_event "nc_tunnel_down" \
                        "Cloudflare tunnel service is ${cf_active} on $(hostname 2>/dev/null || echo 'host') — external access unavailable" \
                    2>/dev/null || true
                ;;
            *)
                echo "CHECK_RESULT WARN tunnel_unknown Cloudflare tunnel status unknown: ${cf_active}"
                ;;
        esac
    else
        echo "CHECK_RESULT WARN tunnel_no_systemctl Cannot check tunnel — systemctl not available"
    fi

    # ── Port binding ─────────────────────────────────────────────────────────
    local http_port="${NEXTCLOUD_HTTP_PORT:-8080}"
    local port_bound=false
    if command -v ss &>/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -q ":${http_port} " && port_bound=true
    elif command -v netstat &>/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | grep -q ":${http_port} " && port_bound=true
    fi

    if $port_bound; then
        echo "CHECK_RESULT OK port_${http_port}_bound Port ${http_port} is bound (nginx listening)"
    else
        # Port not published on host — nginx may be accessible only via internal
        # Docker network (e.g. through cloudflared). Skip HTTP route checks.
        echo "CHECK_RESULT WARN port_${http_port}_not_bound Port ${http_port} not bound on host — nginx not directly reachable (OK if using tunnel-only setup)"
        return 0
    fi

    # ── HTTP routing via nginx ────────────────────────────────────────────────
    # /apps/files/ requires authentication and will return 401/302 — skip it.
    local routes=("/status.php:200" "/login:200")

    for route_spec in "${routes[@]}"; do
        local url="${route_spec%%:*}"
        local expected="${route_spec##*:}"
        local actual_code

        actual_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 4 \
            "http://localhost:${http_port}${url}" 2>/dev/null)

        if [ "$actual_code" = "$expected" ]; then
            echo "CHECK_RESULT OK nginx_route_$(echo "$url" | tr '/' '_' | tr -d '.' | sed 's/^_//') nginx ${url} → ${actual_code}"
        elif [ "$actual_code" = "000" ] || [ -z "$actual_code" ]; then
            echo "CHECK_RESULT FAIL nginx_not_responding nginx is not responding — port ${http_port} unreachable"
        elif [ "$actual_code" = "403" ]; then
            echo "CHECK_RESULT FAIL nginx_403_$(echo "$url" | tr '/' '_' | tr -d '.' | sed 's/^_//') nginx ${url} → 403 Forbidden — nginx config issue (try_files or conf.d/default.conf)"
        elif [ "$actual_code" = "404" ]; then
            echo "CHECK_RESULT FAIL nginx_404_$(echo "$url" | tr '/' '_' | tr -d '.' | sed 's/^_//') nginx ${url} → 404 — missing location block in nginx.conf"
        else
            echo "CHECK_RESULT WARN nginx_unexpected_$(echo "$url" | tr '/' '_' | tr -d '.' | sed 's/^_//') nginx ${url} → ${actual_code} (expected ${expected})"
        fi
    done
}
