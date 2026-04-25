#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/_tunnel_ssh_enhancement.sh
#  Enhanced Cloudflare tunnel with SSH support
# ==============================================================================

# ── Cloudflare SSH Configuration ──────────────────────────────────────────────
_mod_tunnel_configure_ssh() {
    step "Configure Cloudflare SSH Access"
    
    info "This will add SSH access to your existing Cloudflare tunnel"
    info "Requirements: Cloudflare Zero Trust account with existing tunnel"
    
    # Check if cloudflared is installed
    if ! command -v cloudflared &>/dev/null; then
        warn "cloudflared not found. Please install it first."
        pause
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
    info "Current tunnel configuration found."
    info "We'll add SSH access to this tunnel."
    echo ""
    
    # Create SSH application in Cloudflare Zero Trust (user guidance)
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
    echo "     $(grep -A 5 -B 5 "hostname:" "$config_file" 2>/dev/null | head -1 | sed 's/.*hostname: *//' || echo "ssh.your-domain.com")"
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
  - hostname: ssh.$(grep -A 1 -B 1 "hostname:" "$config_file" 2>/dev/null | head -1 | sed 's/.*hostname: *//' | sed 's/^[^.]*\.//' || echo "your-domain.com")
    service: ssh://localhost:22
    originRequest:
      access:
        required: true
  - hostname: $(grep -A 1 -B 1 "hostname:" "$config_file" 2>/dev/null | head -1 | sed 's/.*hostname: *//' || echo "yourdomain.com")
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
    
    pause
}

# ── SSH Connection Commands ────────────────────────────────────────────────────
_mod_tunnel_show_ssh_commands() {
    step "SSH Connection Commands"
    
    info "Connect to your Pi via Cloudflare SSH tunnel:"
    echo ""
    
    # Extract domain from config
    local config_file="$HOME/.cloudflared/config.yml"
    local ssh_domain="ssh.your-domain.com"
    
    if [ -f "$config_file" ]; then
        local extracted_domain
        extracted_domain=$(grep -A 5 "hostname:" "$config_file" 2>/dev/null | grep "ssh\." | head -1 | sed 's/.*hostname: *//' | tr -d ' ')
        if [ -n "$extracted_domain" ]; then
            ssh_domain="$extracted_domain"
        fi
    fi
    
    echo "  ${CYAN}Method 1: Standard SSH${NC}"
    echo "    ssh $ssh_domain"
    echo ""
    
    echo "  ${CYAN}Method 2: With specific user${NC}"
    echo "    ssh youruser@$ssh_domain"
    echo ""
    
    echo "  ${CYAN}Method 3: Using cloudflared proxy${NC}"
    echo "    cloudflared access ssh --hostname $ssh_domain"
    echo ""
    
    echo "  ${CYAN}Method 4: With SSH key${NC}"
    echo "    ssh -i ~/.ssh/your_key.pem youruser@$ssh_domain"
    echo ""
    
    info "Testing connectivity..."
    if ping -c 1 "$ssh_domain" &>/dev/null; then
        ok "SSH domain is reachable"
    else
        warn "SSH domain not reachable - check tunnel status and DNS"
    fi
    
    echo ""
    info "Cloudflare SSH Requirements:"
    echo "  • cloudflared installed on your local machine"
    echo "  • Or SSH client with Cloudflare Zero Trust support"
    echo "  • Access policies configured in Cloudflare dashboard"
    
    pause
}

# ── Enhanced Menu Integration ──────────────────────────────────────────────────
_mod_tunnel_show_integration_info() {
    step "Nextcloud & Tunnel Integration"
    
    info "Your Nextcloud stack is configured to work with Cloudflare tunnel:"
    echo ""
    
    echo "  ${CYAN}Nextcloud Configuration:${NC}"
    echo "    • Web container: localhost:8080 (published via tunnel)"
    echo "    • Expected tunnel: yourdomain.com → localhost:8080"
    echo ""
    
    echo "  ${CYAN}SSH Access:${NC}"
    echo "    • SSH service: localhost:22 (published via tunnel)"
    echo "    • SSH endpoint: ssh.yourdomain.com"
    echo ""
    
    info "Integration Checklist:"
    local checks=()
    
    # Check if tunnel is running
    if sudo systemctl is-active cloudflared &>/dev/null; then
        checks+=("✓ Cloudflare tunnel service running")
    else
        checks+=("✗ Cloudflare tunnel service not running")
    fi
    
    # Check if Nextcloud is running
    if docker compose ps 2>/dev/null | grep -q "web.*running"; then
        checks+=("✓ Nextcloud web container running")
    else
        checks+=("⚠ Nextcloud web container status unknown")
    fi
    
    # Check for SSH configuration
    local config_file="$HOME/.cloudflared/config.yml"
    if [ -f "$config_file" ] && grep -q "ssh://localhost:22" "$config_file"; then
        checks+=("✓ SSH configuration present in tunnel")
    else
        checks+=("⚠ SSH configuration not found in tunnel")
    fi
    
    for check in "${checks[@]}"; do
        echo "    $check"
    done
    
    echo ""
    info "Next Steps:"
    echo "  1. Ensure Nextcloud trusted domains include your tunnel domain"
    echo "  2. Test Nextcloud access via tunnel"
    echo "  3. Test SSH access via tunnel"
    echo "  4. Configure access policies in Cloudflare Zero Trust"
    
    pause
}

# ── Enhanced Tunnel Menu (Integration Point) ────────────────────────────────────
# This function should be integrated into the existing menu_tunnel() function
_mod_tunnel_enhanced_menu() {
    while true; do
        local opt
        opt=$(igor_fzf_pick "3: Tunnel (Enhanced)" \
            "1:INSTALL CLOUDFLARED:Download and install cloudflared binary" \
            "2:CONFIGURE HTTP:Set up Cloudflare HTTP tunnel" \
            "3:CONFIGURE SSH:Add SSH access to tunnel" \
            "4:CHECK STATUS:Tunnel connectivity and service health" \
            "5:SSH COMMANDS:Show SSH connection methods" \
            "6:INTEGRATION:Nextcloud integration status" \
            "R:REVERSE SSH:Traditional SSH via VPS" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "3: Tunnel"
        echo -e "  ${YEL}${BOLD}[3] Cloudflare Tunnel (Enhanced)${NC}"
        echo ""
        echo "   1) Install cloudflared"
        echo "   2) Configure HTTP tunnel"
        echo "   3) Configure SSH tunnel ← NEW"
        echo "   4) Check tunnel status"
        echo "   5) SSH connection commands ← NEW"
        echo "   6) Nextcloud integration ← NEW"
        echo "   R) Reverse SSH (VPS)"
        echo "   b) Back"
        echo ""
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case $opt in
            1) _mod_tunnel_install_cloudflared ;;
            2) _mod_tunnel_service_install ;;
            3) _mod_tunnel_configure_ssh ;;  # NEW - SSH configuration
            4) _mod_tunnel_check_status ;;
            5) _mod_tunnel_show_ssh_commands ;;  # NEW - Show SSH commands
            6) _mod_tunnel_show_integration_info ;;  # NEW - Integration info
            r|R) _mod_tunnel_reverse_ssh ;;
            b|B|q|Q) return ;;
        esac
    done
}

# Integration note: call _mod_tunnel_enhanced_menu() from within menu_tunnel() to enable SSH features.