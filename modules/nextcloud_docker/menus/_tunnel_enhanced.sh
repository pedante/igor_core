#!/bin/bash
# ==============================================================================
#  IGOR — Enhanced Tunnel Module with Context-Aware Menus
#  Solves the architectural duplication between general and Nextcloud tunneling
# ==============================================================================

# ── Module helpers (prefixed with _mod_tunnel_) ─────────────────────────────

# (Keep all existing helper functions from tunnel.sh here...)
_mod_tunnel_install_cloudflared() {
    # [Existing code - unchanged]
    step "Installing Cloudflare tunnel"

    # Check if already installed
    if command -v cloudflared &>/dev/null; then
        ok "cloudflared already installed: $(cloudflared --version)"
        return 0
    fi

    # Detect architecture
    local arch
    arch=$(uname -m)
    case "$arch" in
        armv6l|armv7l)
            local cloudflared_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"
            ;;
        aarch64)
            local cloudflared_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        x86_64)
            local cloudflared_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        *)
            fail "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    info "Downloading cloudflared for $arch..."
    curl -L "$cloudflared_url" -o /tmp/cloudflared || { fail "Download failed."; return 1; }

    step "Installing cloudflared"
    sudo mv /tmp/cloudflared /usr/local/bin/
    sudo chmod +x /usr/local/bin/cloudflared
    ok "cloudflared installed successfully."

    pause
}

_mod_tunnel_service_install() {
    # [Existing code - unchanged]
    step "Setting up Cloudflare tunnel service"

    # Get tunnel token
    local tunnel_token
    info "You need a Cloudflare tunnel token."
    info "Get one from: https://dash.cloudflare.com/ -> Zero Trust -> Networks -> Tunnels"
    tunnel_token=$(ask "Enter your Cloudflare tunnel token" "" secret)

    if [ -z "$tunnel_token" ]; then
        fail "No token provided. Aborting."
        return 1
    fi

    # Create systemd service file
    local service_file="/etc/systemd/system/cloudflared.service"

    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/local/bin/cloudflared tunnel run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    ok "Systemd service file created: $service_file"

    # Create config directory
    local config_dir="$HOME/.cloudflared"
    mkdir -p "$config_dir"

    # Create tunnel config
    local config_file="$config_dir/config.yml"
    cat > "$config_file" << YAMLEOF
tunnel: $tunnel_token
YAMLEOF

    ok "Tunnel configuration created: $config_file"

    # Enable and start service
    step "Enabling and starting cloudflared service"
    sudo systemctl daemon-reload
    sudo systemctl enable cloudflared
    sudo systemctl start cloudflared

    sleep 3

    # Check service status
    if sudo systemctl is-active cloudflared &>/dev/null; then
        ok "Cloudflare tunnel service is running."
        info "Check status with: sudo systemctl status cloudflared"
        info "View logs with: sudo journalctl -u cloudflared -f"
    else
        fail "Failed to start cloudflared service."
        info "Check logs: sudo journalctl -u cloudflared -n 20"
        return 1
    fi

    pause
}

_mod_tunnel_check_status() {
    # [Existing code - unchanged]
    step "Checking Cloudflare tunnel status"

    if sudo systemctl is-active cloudflared &>/dev/null; then
        # Check if tunnel is connected
        if sudo journalctl -u cloudflared -n 50 --no-pager 2>/dev/null \
                | grep -q "Connection registered\|Connection established\|Registered tunnel"; then
            ok "Tunnel is CONNECTED and working."
        else
            warn "Tunnel service is running but not yet connected."
        fi
    else
        fail "Cloudflare tunnel service is NOT running."
        info "Start it with: sudo systemctl start cloudflared"
    fi

    pause
}

_mod_tunnel_reverse_ssh() {
    # [Existing code - unchanged]
    step "Reverse SSH Tunnel"
    echo ""
    info "Use case: Access this Pi from outside without port-forwarding on your router."
    info "The Pi connects OUT to a remote host, which opens a port back to this Pi."
    echo ""
    echo "   Example: ssh to remote-server:remote_port → lands on Pi:local_port"
    echo ""

    local remote_host remote_port local_port remote_user

    read -rp "  Remote host (e.g. myserver.com): " remote_host
    [ -z "$remote_host" ] && { warn "Aborted — no host entered."; pause; return; }

    read -rp "  Remote port to open on the remote host (e.g. 2222) [2222]: " remote_port
    remote_port="${remote_port:-2222}"

    read -rp "  Local port on this Pi to forward (e.g. 22 for SSH) [22]: " local_port
    local_port="${local_port:-22}"

    read -rp "  SSH user on remote host [$(whoami)]: " remote_user
    remote_user="${remote_user:-$(whoami)}"

    local cmd="ssh -N -R ${remote_port}:localhost:${local_port} ${remote_user}@${remote_host}"

    echo ""
    info "Generated command:"
    echo ""
    echo -e "  ${CYAN}${cmd}${NC}"
    echo ""
    info "To verify from the remote side (run ON ${remote_host}):"
    echo "    ssh -p ${remote_port} localhost"
    echo ""
    info "Connection test (run on this Pi to check host is reachable):"
    echo "    ssh -T ${remote_user}@${remote_host}"
    echo ""
    info "Useful options to add: -o ServerAliveInterval=30 -o ServerAliveCountMax=3"
    echo ""
    local persist_choice
    persist_choice=$(igor_fzf_pick "Reverse SSH — Persistence" \
        "1:SYSTEMD SERVICE:autossh if available — reconnects automatically" \
        "2:CRON @REBOOT:Simpler, less reliable" \
        "3:MANUAL:I will run the command myself")
    case $? in 1|2)
        echo "   1) systemd service  (autossh if available — reconnects automatically)"
        echo "   2) cron @reboot     (simpler, less reliable)"
        echo "   3) Neither          — I will run the command manually"
        echo ""
        read -rp "  Select [3]: " persist_choice ;; esac

    case "${persist_choice:-3}" in
        1) _mod_tunnel_reverse_ssh_systemd \
               "$remote_host" "$remote_port" "$local_port" "$remote_user" ;;
        2) _mod_tunnel_reverse_ssh_cron "$cmd" ;;
        *) info "Run the command above manually. Add -i /path/to/key for key auth." ;;
    esac

    pause
}

_mod_tunnel_reverse_ssh_systemd() {
    # [Existing code - unchanged]
    local remote_host="$1" remote_port="$2" local_port="$3" remote_user="$4"
    local exec_start service_name service_file

    if command -v autossh &>/dev/null; then
        exec_start="autossh -M 0 -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
-R ${remote_port}:localhost:${local_port} ${remote_user}@${remote_host}"
        info "autossh detected — service will use autossh for auto-reconnect."
    else
        exec_start="ssh -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
-R ${remote_port}:localhost:${local_port} ${remote_user}@${remote_host}"
        warn "autossh not found — using plain ssh (pkg_install autossh for better reliability)."
    fi

    service_name="igor-reverse-tunnel"
    service_file="/etc/systemd/system/${service_name}.service"

    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=IGOR Reverse SSH Tunnel -> ${remote_user}@${remote_host}:${remote_port}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER}
ExecStart=${exec_start}
Restart=on-failure
RestartSec=15s

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "${service_name}"
    sudo systemctl start "${service_name}"

    sleep 2
    if sudo systemctl is-active "${service_name}" &>/dev/null; then
        ok "Service ${service_name} started and enabled at boot."
        info "Check status: sudo systemctl status ${service_name}"
        info "View logs:    sudo journalctl -u ${service_name} -f"
    else
        warn "Service may have failed. Check: sudo journalctl -u ${service_name} -n 20"
    fi
}

_mod_tunnel_reverse_ssh_cron() {
    # [Existing code - unchanged]
    local cmd="$1"
    local cron_line="@reboot sleep 30 && ${cmd} -o ServerAliveInterval=30 -o ServerAliveCountMax=3 &"
    echo ""
    info "Cron entry to add (runs at every reboot):"
    echo ""
    echo -e "  ${CYAN}${cron_line}${NC}"
    echo ""
    info "Run 'crontab -e' and paste the line above."
    if confirm "Open crontab -e now?"; then
        crontab -e
    fi
}

# ── NEW: Nextcloud-Specific Tunnel Functions ─────────────────────────────────────

# Configure tunnel specifically for Nextcloud
_mod_tunnel_configure_nextcloud() {
    step "Configure Nextcloud Cloudflare Tunnel"
    
    info "This sets up Cloudflare tunnel specifically for Nextcloud web access"
    info "Your Nextcloud stack expects tunnel access via localhost:8080"
    echo ""
    
    # Use existing service install but with Nextcloud context
    _mod_tunnel_service_install
    
    # Add Nextcloud-specific guidance
    echo ""
    info "Nextcloud tunnel setup complete!"
    info "Next steps:"
    echo "  1. Use option 4 (Integration) to update Nextcloud trusted domains"
    echo "  2. Test Nextcloud access via your tunnel domain"
    echo ""
}

# Configure SSH access to Nextcloud server
_mod_tunnel_nextcloud_ssh() {
    step "Nextcloud SSH Access Setup"
    
    info "Configure SSH access to your Nextcloud server via Cloudflare"
    info "This allows secure system administration without VPS"
    echo ""
    
    # Show SSH options
    echo "  ${CYAN}SSH Access Options:${NC}"
    echo "    1) Cloudflare SSH (recommended - no VPS needed)"
    echo "    2) Reverse SSH (traditional - requires VPS)"
    echo ""
    
    read -rp "  Select SSH method [1]: " ssh_method
    ssh_method="${ssh_method:-1}"
    
    case "$ssh_method" in
        1) 
            # Check if cloudflared is installed
            if ! command -v cloudflared &>/dev/null; then
                warn "cloudflared not found. Installing first..."
                _mod_tunnel_install_cloudflared || {
                    fail "cloudflared installation failed"
                    return 1
                }
            fi
            
            # Configure SSH over Cloudflare
            _mod_tunnel_configure_ssh ;;
        2) _mod_tunnel_reverse_ssh ;;
        *) 
            warn "Invalid selection"
            _mod_tunnel_nextcloud_ssh ;;
    esac
    
    pause
}

# Configure SSH over existing Cloudflare tunnel
_mod_tunnel_configure_ssh() {
    step "Configure Cloudflare SSH Access"
    
    # Check if cloudflared is installed
    if ! command -v cloudflared &>/dev/null; then
        warn "cloudflared not found. Please install it first."
        return 1
    fi
    
    # Check for existing tunnel configuration
    local config_dir="$HOME/.cloudflared"
    local config_file="$config_dir/config.yml"
    
    if [ ! -f "$config_file" ]; then
        warn "No existing Cloudflare tunnel configuration found."
        info "Please set up a basic HTTP tunnel first."
        pause
        return 1
    fi
    
    echo ""
    info "STEP 1: Create SSH Application in Cloudflare Zero Trust"
    info "1. Go to: https://dash.cloudflare.com/"
    info "2. Navigate: Zero Trust → Access → Applications"
    info "3. Click 'Add application'"
    info "4. Select 'Self-hosted'"
    info "5. Application Name: 'Pi SSH Access'"
    info "6. Session Duration: 8h or as preferred"
    info "7. Click 'Next'"
    info "8. Configure 'Identity providers' (if needed)"
    info "9. Under 'Configure', add this domain:"
    
    # Extract domain from config
    local ssh_domain="ssh.your-domain.com"
    if [ -f "$config_file" ]; then
        local extracted_domain
        extracted_domain=$(grep -A 5 "hostname:" "$config_file" 2>/dev/null | grep "ssh\." | head -1 | sed 's/.*hostname: *//' | tr -d ' ')
        if [ -n "$extracted_domain" ]; then
            ssh_domain="$extracted_domain"
        fi
    fi
    
    echo "     $ssh_domain"
    info "10. Click 'Save'"
    echo ""
    
    confirm "Have you created the SSH application in Cloudflare?" || {
        warn "Please create the SSH application first."
        pause
        return 1
    }
    
    # Update tunnel configuration to include SSH
    step "Updating tunnel configuration for SSH"
    
    # Backup existing config
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add SSH configuration to existing tunnel
    if ! grep -q "ingress:" "$config_file"; then
        # Add SSH ingress configuration
        cat >> "$config_file" << EOF

ingress:
  - hostname: $ssh_domain
    service: ssh://localhost:22
    originRequest:
      access:
        required: true
  - hostname: $(grep -A 1 -B 1 "hostname:" "$config_file" 2>/dev/null | head -1 | sed 's/.*hostname: *//' | tr -d ' ' || echo "yourdomain.com")
    service: http://localhost:8080
EOF
    fi
    
    ok "SSH configuration added to tunnel"
    
    # Restart tunnel service
    if sudo systemctl is-active cloudflared &>/dev/null; then
        info "Restarting cloudflared service to apply changes..."
        sudo systemctl restart cloudflared
        sleep 3
        
        if sudo systemctl is-active cloudflared &>/dev/null; then
            ok "Tunnel service restarted successfully"
        else
            fail "Tunnel service failed to restart"
            info "Check: sudo journalctl -u cloudflared -n 20"
        fi
    fi
    
    echo ""
    info "SSH Connection Commands:"
    echo "  ssh $ssh_domain"
    echo "  cloudflared access ssh --hostname $ssh_domain"
    echo ""
    
    pause
}

# Update Nextcloud trusted domains
_mod_tunnel_update_nextcloud_domains() {
    local tunnel_domain="$1"
    
    info "Nextcloud requires the tunnel domain to be in trusted domains"
    info "This allows Nextcloud to generate correct URLs"
    echo ""
    
    local stack_dir="${IGOR_STACKS:-${IGOR_DIR}/config/stacks}/nextcloud"
    if [ ! -d "$stack_dir" ]; then
        warn "Nextcloud stack directory not found: $stack_dir"
        pause
        return 1
    fi
    
    if confirm "Add '$tunnel_domain' to Nextcloud trusted domains?"; then
        if docker compose -f "$stack_dir/docker-compose.yml" exec -T -u www-data app php occ config:system:set trusted_domains 1 --value="$tunnel_domain" 2>/dev/null; then
            ok "Trusted domain added successfully"
        else
            warn "Failed to add trusted domain - check Nextcloud status"
        fi
    fi
}

# Check Nextcloud integration
_mod_tunnel_nextcloud_integration() {
    step "Nextcloud Integration"
    
    info "Ensure Nextcloud works properly with your Cloudflare tunnel"
    echo ""
    
    local stack_dir="${IGOR_STACKS:-${IGOR_DIR}/config/stacks}/nextcloud"
    local integration_passed=true
    local checks=()
    
    # Check tunnel status
    if sudo systemctl is-active cloudflared &>/dev/null; then
        checks+=("✓ Cloudflare tunnel running")
    else
        checks+=("✗ Cloudflare tunnel not running")
        integration_passed=false
    fi
    
    # Check Nextcloud containers
    if command -v docker &>/dev/null && docker compose -f "$stack_dir/docker-compose.yml" ps 2>/dev/null | grep -q "running"; then
        checks+=("✓ Nextcloud containers running")
    else
        checks+=("⚠ Nextcloud containers not all running")
    fi
    
    # Check if Nextcloud is accessible via tunnel
    local tunnel_domain="yourdomain.com"
    local config_file="$HOME/.cloudflared/config.yml"
    if [ -f "$config_file" ]; then
        tunnel_domain=$(grep -A 1 -B 1 "hostname:" "$config_file" 2>/dev/null | head -1 | sed 's/.*hostname: *//' | tr -d ' ' || echo "yourdomain.com")
    fi
    
    echo "Integration checks:"
    for check in "${checks[@]}"; do
        echo "    $check"
    done
    
    echo ""
    info "Next steps for integration:"
    echo "  1. Update Nextcloud trusted domains to include: $tunnel_domain"
    echo "  2. Test Nextcloud access via: https://$tunnel_domain"
    echo "  3. Configure HTTPS/SSL settings in Nextcloud"
    echo ""
    
    if confirm "Update Nextcloud trusted domains now?"; then
        _mod_tunnel_update_nextcloud_domains "$tunnel_domain"
    fi
    
    pause
}

# ── Public Menu Functions ────────────────────────────────────────────────────────

# Generic tunnel menu (for Communications menu)
menu_tunnel_generic() {
    while true; do
        local opt
        opt=$(igor_fzf_pick "3: Tunnel" \
            "1:INSTALL CLOUDFLARED:Download and install cloudflared binary" \
            "2:CONFIGURE SERVICE:Set up cloudflared systemd service" \
            "3:CHECK STATUS:Tunnel connectivity and service health" \
            "R:REVERSE SSH:Access Pi from outside — no port-forwarding needed" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "3: Tunnel"
        echo -e "  ${YEL}${BOLD}[3] Cloudflare Tunnel${NC}"
        echo "   1) Install cloudflared"
        echo "   2) Configure tunnel service"
        echo "   3) Check tunnel status"
        echo "   R) Reverse SSH tunnel  (access Pi from outside, no port-forwarding needed)"
        echo "   b) Back"
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case $opt in
            1) _mod_tunnel_install_cloudflared ;;
            2) _mod_tunnel_service_install ;;
            3) _mod_tunnel_check_status ;;
            r|R) _mod_tunnel_reverse_ssh ;;
            q|Q|b|B) return ;;
        esac
    done
}

# Nextcloud-specific tunnel menu (for Setup & Infra menu)  
menu_tunnel_nextcloud() {
    while true; do
        local opt
        opt=$(igor_fzf_pick "3: Tunnel (Nextcloud-Optimized)" \
            "1:NEXTCLOUD TUNNEL:Set up Cloudflare tunnel for Nextcloud access" \
            "2:SSH ACCESS:Configure SSH access to Nextcloud server" \
            "3:MANAGEMENT:Tunnel status, logs, restart" \
            "4:INTEGRATION:Update Nextcloud trusted domains, test access" \
            "5:ADVANCED:Reverse SSH (VPS), traditional access methods" \
            "b:BACK:Return to Setup & Infra menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "S: Setup & Infra" "Tunnel"
        echo -e "  ${YEL}${BOLD}[S] Setup & Infrastructure → Nextcloud Tunnel${NC}"
        echo ""
        echo "   1) Nextcloud Tunnel - Set up Cloudflare tunnel for web access"
        echo "   2) SSH Access - Configure SSH to Nextcloud server"
        echo "   3) Management - Status, logs, restart tunnel"
        echo "   4) Integration - Update Nextcloud, test access"
        echo "   5) Advanced - VPS options, traditional methods"
        echo "   b) Back"
        echo ""
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case $opt in
            1) _mod_tunnel_configure_nextcloud ;;
            2) _mod_tunnel_nextcloud_ssh ;;
            3) _mod_tunnel_nextcloud_management ;;
            4) _mod_tunnel_nextcloud_integration ;;
            5) _mod_tunnel_nextcloud_advanced ;;
            b|B|q|Q) return ;;
        esac
    done
}

# Nextcloud tunnel management submenu
_mod_tunnel_nextcloud_management() {
    while true; do
        local opt
        opt=$(igor_fzf_pick "Tunnel Management" \
            "1:STATUS:Check tunnel connectivity and health" \
            "2:LOGS:View tunnel logs and errors" \
            "3:RESTART:Restart tunnel service" \
            "4:CONFIG:View current tunnel configuration" \
            "b:BACK:Return to tunnel menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "S: Setup & Infra" "Tunnel" "Management"
        echo -e "  ${YEL}${BOLD}[S] Setup & Infrastructure → Tunnel Management${NC}"
        echo ""
        echo "   1) Status - Check tunnel connectivity"
        echo "   2) Logs - View tunnel logs"
        echo "   3) Restart - Restart tunnel service"  
        echo "   4) Config - View tunnel configuration"
        echo "   b) Back"
        echo ""
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case $opt in
            1) _mod_tunnel_check_status ;;
            2) 
                step "Tunnel Logs"
                if sudo systemctl is-active cloudflared &>/dev/null; then
                    sudo journalctl -u cloudflared -f -n 50
                else
                    warn "cloudflared service not running"
                fi
                ;;
            3)
                step "Restart Tunnel Service"
                if sudo systemctl is-active cloudflared &>/dev/null; then
                    sudo systemctl restart cloudflared
                    sleep 3
                    if sudo systemctl is-active cloudflared &>/dev/null; then
                        ok "Tunnel service restarted successfully"
                    else
                        warn "Tunnel service failed to restart"
                    fi
                else
                    warn "cloudflared service not running"
                fi
                pause
                ;;
            4)
                step "Tunnel Configuration"
                local config_file="$HOME/.cloudflared/config.yml"
                if [ -f "$config_file" ]; then
                    echo "Current tunnel configuration:"
                    echo ""
                    cat "$config_file"
                else
                    warn "Tunnel configuration not found: $config_file"
                fi
                pause
                ;;
            b|B|q|Q) return ;;
        esac
    done
}

# Nextcloud advanced options submenu
_mod_tunnel_nextcloud_advanced() {
    while true; do
        local opt
        opt=$(igor_fzf_pick "Advanced Tunnel Options" \
            "1:REVERSE SSH:Set up reverse SSH to VPS" \
            "2:VPN SETUP:Traditional VPN for server access" \
            "3:BACKUP TUNNEL:Secondary tunnel for redundancy" \
            "b:BACK:Return to tunnel menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "S: Setup & Infra" "Tunnel" "Advanced"
        echo -e "  ${YEL}${BOLD}[S] Setup & Infrastructure → Advanced Tunnel Options${NC}"
        echo ""
        echo "   1) Reverse SSH - Set up SSH via VPS"
        echo "   2) VPN Setup - Traditional VPN access"
        echo "   3) Backup Tunnel - Secondary tunnel"
        echo "   b) Back"
        echo ""
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case $opt in
            1) _mod_tunnel_reverse_ssh ;;
            2) 
                step "VPN Setup"
                info "VPN configuration is not yet implemented in this module"
                info "Consider using Cloudflare Tunnel instead - no VPN client needed"
                pause
                ;;
            3)
                step "Backup Tunnel"
                info "Backup tunnel configuration is not yet implemented"
                info "This would provide redundancy for your primary tunnel"
                pause
                ;;
            b|B|q|Q) return ;;
        esac
    done
}

# Keep the original menu_tunnel function for backward compatibility
menu_tunnel() {
    menu_tunnel_generic
}