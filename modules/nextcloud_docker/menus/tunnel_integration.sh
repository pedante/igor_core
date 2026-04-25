#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/tunnel_integration.sh
#  Nextcloud-specific tunnel integration functions
#  Consumes tunnel state from core tunnel module and applies Nextcloud configs
# ==============================================================================

# ── Tunnel State Consumption ─────────────────────────────────────────────────────

# Read tunnel state from runtime state file
_nc_tunnel_read_state() {
    local state_file="${TUNNEL_STATE_FILE:-${IGOR_DIR}/data/runtime/tunnel.state}"
    
    if [ ! -f "$state_file" ]; then
        warn "No tunnel state found. Configure tunnel first using Communications menu."
        return 1
    fi
    
    # Source the state file
    source "$state_file"
    
    if [ -z "$TUNNEL_TYPE" ]; then
        warn "No tunnel type configured in tunnel state."
        return 1
    fi
    
    return 0
}

# ── Nextcloud Configuration Integration ───────────────────────────────────────────

# Configure Nextcloud to work with HTTP tunnel
_nc_tunnel_configure_nextcloud_http() {
    local tunnel_url="$1"
    
    if [ -z "$tunnel_url" ]; then
        warn "No tunnel URL provided."
        return 1
    fi
    
    info "Configuring Nextcloud for HTTP tunnel..."
    
    # Get stack directory
    local _mod_dir _root _stacks
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    local stack_dir="${_stacks}/nextcloud"
    
    # Check if stack exists
    if [ ! -d "$stack_dir" ]; then
        warn "Nextcloud stack not found. Run wizard first."
        return 1
    fi
    
    # Configure Nextcloud settings via occ
    docker compose -f "${stack_dir}/docker-compose.yml" \
        --env-file "${_root}/secrets/db.env" \
        exec -T -u www-data app php occ config:system:set overwrite.cli.url \
        --value="${tunnel_url}" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        ok "Set overwrite.cli.url to: ${tunnel_url}"
    else
        warn "Failed to set overwrite.cli.url"
        return 1
    fi
    
    # Set overwrite protocol to https
    docker compose -f "${stack_dir}/docker-compose.yml" \
        --env-file "${_root}/secrets/db.env" \
        exec -T -u www-data app php occ config:system:set overwriteprotocol \
        --value="https" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        ok "Set overwriteprotocol to: https"
    else
        warn "Failed to set overwriteprotocol"
        return 1
    fi
    
    # Configure trusted proxies for Cloudflare
    _nc_tunnel_configure_trusted_proxies
    
    ok "Nextcloud configured for HTTP tunnel"
    return 0
}

# Configure trusted proxies for Cloudflare
_nc_tunnel_configure_trusted_proxies() {
    info "Configuring trusted proxies for Cloudflare..."
    
    # Get stack directory
    local _mod_dir _root _stacks
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    local stack_dir="${_stacks}/nextcloud"
    
    # Cloudflare IP ranges (canonical list: core/lib/cloudflare_ips.sh)
    local cf_ips=()
    igor_cf_ips_get cf_ips
    
    # Clear existing trusted proxies
    docker compose -f "${stack_dir}/docker-compose.yml" \
        --env-file "${_root}/secrets/db.env" \
        exec -T -u www-data app php occ config:system:delete trusted_proxies 2>/dev/null || true
    
    # Add Cloudflare IPs as trusted proxies
    for ip in "${cf_ips[@]}"; do
        docker compose -f "${stack_dir}/docker-compose.yml" \
            --env-file "${_root}/secrets/db.env" \
            exec -T -u www-data app php occ config:system:set trusted_proxies \
            --value="$ip" --type=array 2>/dev/null
    done
    
    if [ $? -eq 0 ]; then
        ok "Configured Cloudflare trusted proxies"
    else
        warn "Failed to configure trusted proxies"
        return 1
    fi
    
    return 0
}

# ── Public Integration Functions ───────────────────────────────────────────────────

# Nextcloud remote access menu - reads tunnel state and provides NC-specific options
nc_menu_remote_access() {
    while true; do
        # Read tunnel state
        if ! _nc_tunnel_read_state; then
            warn "No tunnel configured. Please configure tunnel first."
            pause
            return 1
        fi
        
        # Right panel: Nextcloud + tunnel status
        if declare -f igor_right_render &>/dev/null; then
            local nc_status="unknown"
            local http_code
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
                http://localhost:8080/status.php 2>/dev/null || echo "000")
            [ "$http_code" = "200" ] && nc_status="running" || nc_status="down"
            
            igor_right_render "Nextcloud Remote Access" \
                "Tunnel Type" "$TUNNEL_TYPE" \
                "Nextcloud" "$nc_status" \
                "Public URL" "${TUNNEL_PUBLIC_URL:-none}" \
                "---" "Quick actions" \
                "hint" "[1]  INTEGRATE TUNNEL" \
                "hint" "[2]  TEST ACCESS" \
                "hint" "[b]  BACK"
        fi
        
        local _opt
        _opt=$(igor_fzf_pick "Nextcloud Remote Access" \
            "1:INTEGRATE TUNNEL:Configure Nextcloud to use tunnel" \
            "2:TEST ACCESS:Test remote access to Nextcloud" \
            "3:SHOW CONFIG:Display current tunnel and Nextcloud config" \
            "4:TRUSTED PROXIES:Reconfigure Cloudflare trusted proxies" \
            "b:BACK:Return to previous menu")
        
        case $? in 1) return ;; 2)
        header
        breadcrumb "Nextcloud" "Remote Access"
        echo -e "  ${YEL}${BOLD}Nextcloud Remote Access${NC}"
        echo ""
        echo -e "  ${DIM}── Tunnel Status ─────────────────────────────────────${NC}"
        echo -e "  ${CYAN}Type:${NC}     ${TUNNEL_TYPE}"
        echo -e "  ${CYAN}URL:${NC}      ${TUNNEL_PUBLIC_URL:-none}"
        [ -n "$TUNNEL_SSH_HOST" ] && echo -e "  ${CYAN}SSH:${NC}      ${TUNNEL_SSH_HOST}:${TUNNEL_SSH_PORT:-22}"
        echo ""
        echo -e "  ${DIM}── Integration Options ──────────────────────────────${NC}"
        echo -e "  ${CYAN}1.${NC} INTEGRATE TUNNEL   — Configure Nextcloud to use tunnel"
        echo -e "  ${CYAN}2.${NC} TEST ACCESS        — Test remote access to Nextcloud"
        echo -e "  ${CYAN}3.${NC} SHOW CONFIG        — Display current tunnel and Nextcloud config"
        echo -e "  ${CYAN}4.${NC} TRUSTED PROXIES    — Reconfigure Cloudflare trusted proxies"
        echo ""
        echo -e "  ${CYAN}b.${NC} BACK"
        echo ""
        read -rp "  Select: " _opt ;; esac
        
        [ "$_opt" = "_" ] && continue
        
        case "$_opt" in
            1)
                nc_tunnel_integrate
                pause
                ;;
            2)
                _nc_tunnel_test_access
                pause
                ;;
            3)
                _nc_tunnel_show_config
                pause
                ;;
            4)
                _nc_tunnel_configure_trusted_proxies
                pause
                ;;
            b|B|q|Q)
                return
                ;;
            *)
                warn "Invalid option. Please try again."
                pause
                ;;
        esac
    done
}

# Main integration function - connects tunnel state with Nextcloud configuration
nc_tunnel_integrate() {
    info "Integrating tunnel with Nextcloud..."
    
    # Read tunnel state
    if ! _nc_tunnel_read_state; then
        return 1
    fi
    
    case "$TUNNEL_TYPE" in
        http)
            if [ -n "$TUNNEL_PUBLIC_URL" ]; then
                if _nc_tunnel_configure_nextcloud_http "$TUNNEL_PUBLIC_URL"; then
                    ok "Tunnel integration completed successfully!"
                    info "Nextcloud is now accessible via: ${TUNNEL_PUBLIC_URL}"
                else
                    fail "Tunnel integration failed!"
                    return 1
                fi
            else
                warn "HTTP tunnel configured but no public URL available."
                return 1
            fi
            ;;
        ssh|reverse_ssh)
            info "SSH tunnel detected. Nextcloud integration not required for SSH access."
            info "Use: ssh ${TUNNEL_SSH_HOST}:${TUNNEL_SSH_PORT:-22}"
            ;;
        *)
            warn "Unknown tunnel type: ${TUNNEL_TYPE}"
            return 1
            ;;
    esac
    
    return 0
}

# ── Helper Functions ─────────────────────────────────────────────────────────────

# Test remote access to Nextcloud
_nc_tunnel_test_access() {
    if [ -z "$TUNNEL_PUBLIC_URL" ]; then
        warn "No public URL configured for testing."
        return 1
    fi
    
    info "Testing remote access to: ${TUNNEL_PUBLIC_URL}"
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        "${TUNNEL_PUBLIC_URL}/status.php" 2>/dev/null)
    
    case "$http_code" in
        200)
            ok "SUCCESS: Nextcloud is accessible via tunnel!"
            info "HTTP Status: ${http_code} (OK)"
            ;;
        403|404)
            warn "Partial access: HTTP ${http_code}"
            info "Nextcloud responds but may have routing issues."
            info "Check trusted proxies and nginx configuration."
            ;;
        502|503)
            warn "Service error: HTTP ${http_code}"
            info "Tunnel works but Nextcloud service may be down."
            ;;
        000)
            fail "Connection failed: No response from ${TUNNEL_PUBLIC_URL}"
            info "Check tunnel service and firewall settings."
            ;;
        *)
            warn "Unexpected HTTP status: ${http_code}"
            ;;
    esac
}

# Show current tunnel and Nextcloud configuration
_nc_tunnel_show_config() {
    echo ""
    echo -e "  ${BOLD}Tunnel Configuration${NC}"
    echo "  ────────────────────────────────────────────"
    
    if _nc_tunnel_read_state; then
        echo "  Type:              ${TUNNEL_TYPE}"
        [ -n "$TUNNEL_PUBLIC_URL" ] && echo "  Public URL:        ${TUNNEL_PUBLIC_URL}"
        [ -n "$TUNNEL_SSH_HOST" ] && echo "  SSH Host:          ${TUNNEL_SSH_HOST}"
        [ -n "$TUNNEL_SSH_PORT" ] && echo "  SSH Port:          ${TUNNEL_SSH_PORT}"
        echo "  Service Enabled:    ${TUNNEL_SERVICE_ENABLED:-false}"
        [ -n "$TUNNEL_CONFIGURED_AT" ] && echo "  Configured At:     $(date -d "@$TUNNEL_CONFIGURED_AT" 2>/dev/null || echo 'unknown')"
    fi
    
    echo ""
    echo -e "  ${BOLD}Nextcloud Configuration${NC}"
    echo "  ────────────────────────────────────────────"
    
    # Get stack directory
    local _mod_dir _root _stacks
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    local stack_dir="${_stacks}/nextcloud"
    
    if [ -d "$stack_dir" ]; then
        # Get Nextcloud config
        local overwrite_cli_url overwriteprotocol
        overwrite_cli_url=$(docker compose -f "${stack_dir}/docker-compose.yml" \
            --env-file "${_root}/secrets/db.env" \
            exec -T -u www-data app php occ config:system:get overwrite.cli.url 2>/dev/null || echo 'not set')
        
        overwriteprotocol=$(docker compose -f "${stack_dir}/docker-compose.yml" \
            --env-file "${_root}/secrets/db.env" \
            exec -T -u www-data app php occ config:system:get overwriteprotocol 2>/dev/null || echo 'not set')
        
        echo "  overwrite.cli.url:  ${overwrite_cli_url}"
        echo "  overwriteprotocol:  ${overwriteprotocol}"
        
        # Count trusted proxies
        local proxy_count
        proxy_count=$(docker compose -f "${stack_dir}/docker-compose.yml" \
            --env-file "${_root}/secrets/db.env" \
            exec -T -u www-data app php occ config:system:get trusted_proxies 2>/dev/null | wc -l)
        echo "  Trusted Proxies:   ${proxy_count} configured"
    else
        echo "  Nextcloud stack not found"
    fi
}

[ "${NEXUS_VERBOSE:-false}" = "true" ] && echo "  [module_loader] nextcloud tunnel integration loaded" >&2 || true