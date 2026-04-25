#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/tunnel.sh
#  Nextcloud-specific tunnel integration wrapper.
#
#  This module provides Nextcloud-specific tunnel functions by calling the
#  core tunnel module and adding Nextcloud-specific integration.
#  DEPRECATED: Use nc_menu_remote_access() for new functionality.
# ==============================================================================

# core/tunnel/tunnel.sh is sourced at igor startup — no load call needed.
# Guard: source it here only if somehow invoked outside the normal startup path.
declare -f tunnel_install_cloudflared &>/dev/null || \
    source "${IGOR_DIR}/core/tunnel/tunnel.sh" 2>/dev/null || true

# ── Module helpers (prefixed with _mod_tunnel_) ─────────────────────────────

_mod_tunnel_install_cloudflared() {
    # Call the core tunnel module function
    tunnel_install_cloudflared
}

_mod_tunnel_service_install() {
    # Call the core tunnel module function
    tunnel_configure_http
}

_mod_tunnel_check_status() {
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

# ── Reverse SSH tunnel ───────────────────────────────────────────────────────────
_mod_tunnel_reverse_ssh() {
    # Call the core tunnel module function
    tunnel_configure_reverse_ssh
}

_mod_tunnel_reverse_ssh_systemd() {
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

# ── Public entry point ───────────────────────────────────────────────────────────
# DEPRECATED: This function now redirects to the new Nextcloud tunnel integration menu
menu_tunnel() {
    info "Redirecting to Nextcloud tunnel integration menu..."
    nc_menu_remote_access
}
