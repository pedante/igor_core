#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/network.sh
#  DIAGNOSE module: health checks, diagnostics, permissions, integrity.
#
#  Menu 8:
#    [1] Quick health check       — all healing checks (summary first)
#    [2] Full diagnostic report   — all checks + save to reports/
#    [3] Network & routing        — internet, DNS, Docker nets, container links
#    [4] Nextcloud permissions    — find files not owned by UID 1004
#    [5] File integrity check     — occ integrity:check-core
#    [6] PHP/FPM status           — php -v, key php.ini values
#    [7] Database integrity       — occ db:add-missing-indices + bigint conversion
# ==============================================================================

_occ() { docker compose exec -T -u www-data app php occ "$@"; }

# ── [1] Quick health check ────────────────────────────────────────────────────
_mod_network_health_check() {
    if declare -f health_check_full &>/dev/null; then
        health_check_full true
    else
        step "Quick health check"
        warn "health_check_full not available — running fallback checks"
        docker compose ps 2>/dev/null
        echo "status.php: $(_nc_check_http /status.php)"
    fi
    pause
}

# ── [2] Full diagnostic report ────────────────────────────────────────────────
_mod_network_full_report() {
    step "Full diagnostic report"
    echo ""
    info "Running all health checks and saving report..."

    if declare -f health_check_full &>/dev/null; then
        health_check_full true
    else
        warn "health_check_full not available."
    fi

    # Additional context beyond the healing checks
    echo ""
    info "HTTP routing spot-check:"
    for url in /status.php /login /apps/files/; do
        local code; code=$(_nc_check_http "$url")
        printf "  %-30s → %s\n" "localhost:${NEXTCLOUD_HTTP_PORT:-8080}${url}" "$code"
    done

    echo ""
    info "Container resource usage:"
    docker stats --no-stream --format "  {{.Name}}  CPU:{{.CPUPerc}}  MEM:{{.MemUsage}}" 2>/dev/null || true

    echo ""
    info "Recent NC errors (last 10):"
    docker compose exec -T app tail -40 /var/www/html/data/nextcloud.log 2>/dev/null \
        | python3 -c "
import sys,json
lines=[]
for l in sys.stdin:
    try:
        e=json.loads(l.strip())
        lines.append('['+str(e.get('level','?'))+'] '+e.get('message','')[:120])
    except: pass
for l in lines[-10:]: print('  '+l)
" 2>/dev/null || echo "  (log unavailable)"

    # Save report
    local rdir="${REPORTS_DIR:-${IGOR_DIR}/reports}"
    mkdir -p "$rdir" 2>/dev/null || true
    local rfile="${rdir}/full_diag_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "# IGOR Full Diagnostic Report — $(date)"
        echo ""
        declare -f health_check_full &>/dev/null && health_check_full false 2>/dev/null || true
        echo ""
        echo "--- HTTP spot-check ---"
        for url in /status.php /login /apps/files/; do
            local code; code=$(_nc_check_http "$url")
            echo "  ${url}: ${code}"
        done
        echo ""
        echo "--- NC errors ---"
        docker compose exec -T app tail -40 /var/www/html/data/nextcloud.log 2>/dev/null \
            | python3 -c "
import sys,json
for l in sys.stdin:
    try:
        e=json.loads(l.strip())
        print('['+str(e.get('level','?'))+'] '+e.get('message','')[:200])
    except: pass
" 2>/dev/null || true
    } > "$rfile" 2>/dev/null \
        && ok "Report saved: reports/$(basename "$rfile")" \
        || warn "Could not save report (check REPORTS_DIR)"

    pause
}

# ── [3] Network & routing ─────────────────────────────────────────────────────
_mod_network_routing() {
    step "Network & routing"

    info "LAN IP: $(hostname -I | awk '{print $1}')"
    echo ""

    info "Internet connectivity:"
    ping -c 1 -W 2 8.8.8.8 &>/dev/null && ok "Internet: REACHABLE" || fail "Internet: UNREACHABLE"
    ping -c 1 -W 2 google.com &>/dev/null && ok "DNS: RESOLVING" || fail "DNS: NOT RESOLVING"

    echo ""
    info "Docker networks:"
    docker network ls 2>/dev/null | head -8

    echo ""
    info "Container port bindings:"
    docker compose ps 2>/dev/null | grep -E "0\.0\.0\.0|::" || echo "  (no public ports)"

    echo ""
    info "Inter-container connectivity:"
    if docker compose exec -T app ping -c 2 -W 2 db &>/dev/null; then
        ok "app → db: OK"
    else
        fail "app → db: FAIL"
    fi
    if docker compose exec -T app ping -c 2 -W 2 redis &>/dev/null; then
        ok "app → redis: OK"
    else
        fail "app → redis: FAIL"
    fi

    echo ""
    info "HTTP routing:"
    for url in /status.php /login /apps/files/; do
        local code; code=$(_nc_check_http "$url")
        printf "  %-30s → %s\n" "${url}" "$code"
    done

    echo ""
    info "Cloudflare tunnel:"
    sudo -n systemctl is-active cloudflared 2>/dev/null || echo "  (cloudflared status unavailable — try: sudo systemctl is-active cloudflared)"

    pause
}

# ── [4] Nextcloud permissions ─────────────────────────────────────────────────
_mod_network_nc_permissions() {
    step "Nextcloud permissions check"
    local nc_data="${NC_DATA:-/mnt/nextclouddata/next}"
    local nc_uid="${NC_UID:-1004}"

    info "Checking NC_DATA ownership (expected UID ${nc_uid})..."
    if [ ! -d "$nc_data" ]; then
        fail "NC_DATA directory not found: ${nc_data}"
        pause
        return
    fi

    local owner; owner=$(stat -c "%u:%g" "$nc_data" 2>/dev/null)
    info "NC_DATA root ownership: ${owner}"

    info "Scanning for files not owned by UID ${nc_uid} (max 30 results)..."
    local bad_files
    bad_files=$(find "$nc_data" ! -user "$nc_uid" -not -path "*/lost+found/*" 2>/dev/null | head -30)

    if [ -z "$bad_files" ]; then
        ok "All files are owned by UID ${nc_uid}."
    else
        warn "Files with wrong ownership:"
        echo "$bad_files" | while IFS= read -r f; do
            local fowner; fowner=$(stat -c "%u:%g" "$f" 2>/dev/null)
            echo "  ${fowner}  ${f}"
        done
        echo ""
        info "To fix: docker compose exec app chown -R ${nc_uid}:${nc_uid} /var/www/html/data"
    fi

    echo ""
    info "Named volume (pi_nextcloud) app directory ownership:"
    docker compose exec -T app stat -c "%u:%g %n" /var/www/html 2>/dev/null || true

    pause
}

# ── [5] File integrity check ──────────────────────────────────────────────────
_mod_network_integrity() {
    step "File integrity check"
    info "Running occ integrity:check-core..."
    info "(failures on shipped core apps are benign — see Nextcloud docs)"
    echo ""

    _occ integrity:check-core 2>/dev/null || warn "integrity:check-core returned non-zero (may be benign)"

    pause
}

# ── [6] PHP/FPM status ────────────────────────────────────────────────────────
_mod_network_php_status() {
    step "PHP/FPM status"

    info "PHP version:"
    docker compose exec -T app php -v 2>/dev/null | head -3

    echo ""
    info "Key PHP ini values:"
    docker compose exec -T app php -r "
\$keys = ['memory_limit','upload_max_filesize','post_max_size',
          'max_execution_time','opcache.enable','opcache.memory_consumption'];
foreach(\$keys as \$k) {
    \$v = ini_get(\$k);
    printf('  %-35s %s\n', \$k, \$v !== false ? \$v : '(not set)');
}
" 2>/dev/null || warn "PHP not available in app container"

    echo ""
    info "OPcache status:"
    docker compose exec -T app php -r "
\$s = opcache_get_status(false);
if (\$s) {
    printf('  enabled: %s\n', \$s['opcache_enabled'] ? 'yes' : 'no');
    if (isset(\$s['memory_usage'])) {
        \$u = \$s['memory_usage'];
        printf('  used: %.1fMB  free: %.1fMB\n', \$u['used_memory']/1048576, \$u['free_memory']/1048576);
    }
} else {
    echo '  OPcache not available.\n';
}
" 2>/dev/null || true

    pause
}

# ── [7] Database integrity ────────────────────────────────────────────────────
_mod_network_db_integrity() {
    step "Database integrity"

    info "Adding missing indices..."
    _occ db:add-missing-indices 2>/dev/null && ok "Missing indices: done" || warn "db:add-missing-indices returned non-zero"

    echo ""
    info "Converting filecache to bigint..."
    _occ db:convert-filecache-bigint --no-interaction 2>/dev/null && ok "Bigint conversion: done" || warn "db:convert-filecache-bigint returned non-zero"

    echo ""
    info "Adding missing columns..."
    _occ db:add-missing-columns 2>/dev/null && ok "Missing columns: done" || true

    pause
}

# ── [8] Inject Nextcloud network config ───────────────────────────────────────
_mod_network_inject_nc_config() {
    step "Inject Nextcloud network config"
    echo ""
    info "Writes network settings to config.php via occ (trusted_domains, trusted_proxies,"
    info "overwriteprotocol, overwrite.cli.url, forwarded_for_headers)."
    info "A backup of config.php is taken before any write."
    echo ""

    # Check app container is running
    if ! docker compose ps app 2>/dev/null | grep -q "running\|Up"; then
        warn "App container does not appear to be running. Cannot run occ commands."
        pause
        return 1
    fi

    local lan_ip; lan_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    # Auto-detect tunnel domain from db.env
    local tunnel_domain=""
    local _td_raw; _td_raw=$(grep "^NEXTCLOUD_TRUSTED_DOMAINS=" "${IGOR_DIR:-./}/db.env" 2>/dev/null \
        | cut -d= -f2-)
    # Second space-delimited token is usually the tunnel domain
    tunnel_domain=$(echo "$_td_raw" | awk '{print $2}')

    echo "  Detected:"
    echo "    LAN IP:      ${lan_ip:-unknown}"
    echo "    Tunnel URL:  ${tunnel_domain:-(not detected from db.env)}"
    echo ""

    local _input
    read -rp "  Tunnel domain${tunnel_domain:+ [$tunnel_domain]}: " _input
    tunnel_domain="${_input:-$tunnel_domain}"

    echo ""
    info "Planned changes:"
    echo "    trusted_domains[0] = localhost"
    echo "    trusted_domains[1] = ${lan_ip}"
    [ -n "$tunnel_domain" ] && echo "    trusted_domains[2] = ${tunnel_domain}"
    echo "    trusted_proxies    = Cloudflare IP ranges (15 IPv4 ranges)"
    echo "    overwriteprotocol  = https"
    [ -n "$tunnel_domain" ] && echo "    overwrite.cli.url  = https://${tunnel_domain}"
    echo "    forwarded_for_headers[0] = HTTP_X_FORWARDED_FOR"
    echo ""
    info "Current trusted_domains:"
    docker compose exec -T -u www-data app php occ config:system:get trusted_domains 2>/dev/null \
        | sed 's/^/    /' || echo "    (unavailable)"
    echo ""

    confirm "Apply these changes? (config.php will be backed up first)" || {
        info "No changes made."
        pause
        return
    }

    # Backup
    step "Backing up config.php"
    local bkdir="${NEXUS_CONFIG:-$HOME/.config/igor}/backups"
    mkdir -p "$bkdir" 2>/dev/null || true
    local bkts; bkts=$(date +%Y%m%d_%H%M%S)
    docker compose exec -T app cat /var/www/html/config/config.php 2>/dev/null \
        > "${bkdir}/config.php.${bkts}.bak" \
        && ok "Backed up → backups/config.php.${bkts}.bak" \
        || warn "Backup failed — continuing anyway"

    # trusted_domains
    step "Setting trusted_domains"
    _occ config:system:set trusted_domains 0 --value="localhost"  2>/dev/null && ok "localhost"   || warn "index 0 failed"
    _occ config:system:set trusted_domains 1 --value="${lan_ip}"  2>/dev/null && ok "${lan_ip}"   || warn "index 1 failed"
    if [ -n "$tunnel_domain" ]; then
        _occ config:system:set trusted_domains 2 --value="${tunnel_domain}" 2>/dev/null \
            && ok "${tunnel_domain}" || warn "index 2 failed"
    fi

    # trusted_proxies — Cloudflare IPv4 ranges (canonical list: core/lib/cloudflare_ips.sh)
    step "Setting trusted_proxies (Cloudflare IPv4 ranges)"
    local -a _cf_ips=()
    igor_cf_ips_get _cf_ips
    local _idx=0
    for _ip in "${_cf_ips[@]}"; do
        _occ config:system:set trusted_proxies "${_idx}" --value="${_ip}" 2>/dev/null || true
        (( _idx++ ))
    done
    ok "${#_cf_ips[@]} Cloudflare IP ranges set"

    # overwriteprotocol
    step "Setting overwriteprotocol"
    _occ config:system:set overwriteprotocol --value="https" 2>/dev/null \
        && ok "overwriteprotocol = https" || warn "failed"

    # overwrite.cli.url
    if [ -n "$tunnel_domain" ]; then
        step "Setting overwrite.cli.url"
        _occ config:system:set "overwrite.cli.url" --value="https://${tunnel_domain}" 2>/dev/null \
            && ok "overwrite.cli.url = https://${tunnel_domain}" || warn "failed"
    fi

    # forwarded_for_headers
    step "Setting forwarded_for_headers"
    _occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR" 2>/dev/null \
        && ok "HTTP_X_FORWARDED_FOR" || warn "failed"

    echo ""
    ok "Nextcloud network config applied."
    info "Restart the stack to pick up all changes: Menu 4 → 3 (Restart all services)"
    pause
}

# ── Public entry point ────────────────────────────────────────────────────────
menu_network() {
    while true; do
        # Right pane: network snapshot
        if declare -f igor_right_render &>/dev/null; then
            local _net_ip _net_tun _net_dns
            _net_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "?")
            _net_tun=$(systemctl is-active cloudflared 2>/dev/null || echo "unknown")
            _net_dns=$(resolvectl status 2>/dev/null | grep 'DNS Servers' | head -1 | awk '{print $NF}' || echo "?")
            local _net_domain; _net_domain=$(printf '%s' "${NEXTCLOUD_TRUSTED_DOMAINS:-}" | awk '{print $NF}')
            igor_right_render "Network" \
                "LAN IP"  "${_net_ip}" \
                "Tunnel"  "${_net_tun}" \
                "DNS"     "${_net_dns:-?}" \
                "Domain"  "${_net_domain:-not set}" \
                "hint"    "[1] quick check  [2] full report"
        fi
        local opt
        opt=$(igor_fzf_pick "6: Diagnose" \
            "1:QUICK HEALTH CHECK:HTTP, containers, storage" \
            "2:FULL DIAGNOSTIC:All checks + save report" \
            "3:NETWORK & ROUTING:Routes, DNS, connectivity" \
            "4:NC PERMISSIONS:Nextcloud data dir permissions" \
            "5:FILE INTEGRITY:occ files:check" \
            "6:PHP/FPM STATUS:php-fpm pool and process status" \
            "7:DATABASE INTEGRITY:PostgreSQL consistency check" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "6: Diagnose"
        echo -e "  ${YEL}${BOLD}[6] Diagnose${NC}"
        echo "   1) Quick health check"
        echo "   2) Full diagnostic report (all checks + save report)"
        echo "   3) Network & routing"
        echo "   4) Nextcloud permissions check"
        echo "   5) File integrity check"
        echo "   6) PHP/FPM status"
        echo "   7) Database integrity"
        echo "   b) Back"
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case $opt in
            1)  _mod_network_health_check ;;
            2)  _mod_network_full_report ;;
            3)  _mod_network_routing ;;
            4)  _mod_network_nc_permissions ;;
            5)  _mod_network_integrity ;;
            6)  _mod_network_php_status ;;
            7)  _mod_network_db_integrity ;;
            q|Q|b|B) return ;;
        esac
    done
}
