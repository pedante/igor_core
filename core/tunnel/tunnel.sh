#!/bin/bash
# ==============================================================================
#  IGOR — core/tunnel/tunnel.sh
#  Core tunnel and remote access functions.
#  Zero knowledge of Nextcloud — generic tunnel management only.
#
#  Sourced unconditionally at igor startup (igor.sh) so all tunnel_* functions
#  are available to every module without a load call.
#
#  State file:  ${IGOR_DIR}/data/runtime/tunnel.state
#  Consumers:   read via tunnel_load_state() — never write directly.
#
#  Public API:
#    tunnel_install_cloudflared    — download & install cloudflared binary
#    tunnel_configure_http         — Cloudflare HTTP tunnel (quick or named)
#    tunnel_configure_ssh          — Cloudflare SSH access
#    tunnel_configure_reverse_ssh  — VPS reverse SSH tunnel
#    tunnel_enable_service         — create + start persistent systemd service
#    tunnel_status                 — print current tunnel status
#    tunnel_teardown               — stop services, clear state
#    tunnel_load_state             — source state file into caller's shell
#    menu_tunnel                   — interactive tunnel menu
#
#  Igor hook functions (registered via _tunnel_register_hooks):
#    _tunnel_hook_health           — health hook: "ok|warn:message"
#    _tunnel_hook_diagnose         — diagnose hook: "CHECK:name:status:msg"
#    _tunnel_hook_status_line      — header status line hook
# ==============================================================================

# ── State file path ────────────────────────────────────────────────────────────
# Resolved once at source time.  IGOR_DIR is always set before this file is
# sourced (igor.sh exports it as the very first thing).
TUNNEL_STATE_FILE="${IGOR_DIR}/data/runtime/tunnel.state"

# ── Runtime State Management ───────────────────────────────────────────────────

_tunnel_init_state() {
    mkdir -p "$(dirname "$TUNNEL_STATE_FILE")"
    if [ ! -f "$TUNNEL_STATE_FILE" ]; then
        cat > "$TUNNEL_STATE_FILE" <<'EOF'
TUNNEL_TYPE=""
TUNNEL_PUBLIC_URL=""
TUNNEL_SSH_HOST=""
TUNNEL_SSH_PORT=""
TUNNEL_SERVICE_ENABLED=""
TUNNEL_CONFIGURED_AT=""
EOF
    fi
}

_tunnel_write_state() {
    local _type="$1" _url="$2" _ssh_host="$3" _ssh_port="$4"
    _tunnel_init_state
    local _tmp
    _tmp=$(mktemp "/tmp/tunnel.state.XXXXXX")
    cat > "$_tmp" <<EOF
TUNNEL_TYPE="${_type}"
TUNNEL_PUBLIC_URL="${_url}"
TUNNEL_SSH_HOST="${_ssh_host}"
TUNNEL_SSH_PORT="${_ssh_port}"
TUNNEL_SERVICE_ENABLED="${TUNNEL_SERVICE_ENABLED:-}"
TUNNEL_CONFIGURED_AT="$(date +%s)"
EOF
    mv "$_tmp" "$TUNNEL_STATE_FILE"
}

_tunnel_clear_state() {
    _tunnel_init_state
    cat > "$TUNNEL_STATE_FILE" <<'EOF'
TUNNEL_TYPE=""
TUNNEL_PUBLIC_URL=""
TUNNEL_SSH_HOST=""
TUNNEL_SSH_PORT=""
TUNNEL_SERVICE_ENABLED=""
TUNNEL_CONFIGURED_AT=""
EOF
}

# Source state into caller's shell.  Idempotent — safe to call many times.
tunnel_load_state() {
    _tunnel_init_state
    # shellcheck disable=SC1090
    [ -f "$TUNNEL_STATE_FILE" ] && source "$TUNNEL_STATE_FILE"
}

# ── Installation ───────────────────────────────────────────────────────────────

tunnel_install_cloudflared() {
    step "Installing Cloudflared"

    if command -v cloudflared &>/dev/null; then
        ok "cloudflared already installed: $(cloudflared --version | head -n1)"
        return 0
    fi

    local _arch _url
    _arch=$(uname -m)
    case "$_arch" in
        armv6l|armv7l) _url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"    ;;
        aarch64)        _url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"  ;;
        x86_64)         _url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
        *)              fail "Unsupported architecture: $_arch"; return 1 ;;
    esac

    info "Downloading cloudflared for ${_arch}..."
    local _tmp
    _tmp=$(mktemp "/tmp/cloudflared.XXXXXX")
    if ! curl -fsSL "$_url" -o "$_tmp"; then
        fail "Download failed"; rm -f "$_tmp"; return 1
    fi

    if ! sudo mv "$_tmp" /usr/local/bin/cloudflared; then
        fail "Failed to install cloudflared (sudo required)"; rm -f "$_tmp"; return 1
    fi
    sudo chmod +x /usr/local/bin/cloudflared

    if command -v cloudflared &>/dev/null; then
        ok "cloudflared installed: $(cloudflared --version | head -n1)"
    else
        fail "cloudflared binary not found after install"; return 1
    fi
}

# ── Configuration ──────────────────────────────────────────────────────────────

tunnel_configure_http() {
    local _local_url="$1"

    if [ -z "$_local_url" ]; then
        fail "Local URL required (e.g. http://localhost:8080)"
        return 1
    fi

    step "Configuring HTTP Tunnel"

    if ! command -v cloudflared &>/dev/null; then
        warn "cloudflared not installed"
        confirm "Install cloudflared now?" || { fail "cloudflared required"; return 1; }
        tunnel_install_cloudflared || return 1
    fi

    info "Local service: $_local_url"
    echo ""
    echo "  HTTP Tunnel Options:"
    echo "    1) Quick Tunnel  (ephemeral URL, easy setup)"
    echo "    2) Named Tunnel  (persistent URL, requires Cloudflare account)"
    echo ""
    local _sel; read -rp "  Select [1]: " _sel
    _sel="${_sel:-1}"

    local _tunnel_url=""
    case "$_sel" in
        1)
            info "Starting quick tunnel (may take a moment)..."
            local _out
            _out=$(timeout 30 cloudflared tunnel --url "$_local_url" 2>&1 | head -20 || true)
            _tunnel_url=$(echo "$_out" | grep -o 'https://[^[:space:]]*' | head -1)
            [ -n "$_tunnel_url" ] || { fail "Could not extract tunnel URL"; echo "$_out"; return 1; }
            ;;
        2)
            _tunnel_configure_named_tunnel "$_local_url" || return 1
            tunnel_load_state
            _tunnel_url="$TUNNEL_PUBLIC_URL"
            ;;
        *)
            warn "Invalid selection"; return 1 ;;
    esac

    _tunnel_write_state "http" "$_tunnel_url" "" ""
    ok "HTTP tunnel configured: $_tunnel_url"
    echo ""
    info "Run 'tunnel_enable_service' to make it persistent."
    echo ""
}

_tunnel_configure_named_tunnel() {
    local _local_url="$1"
    info "Named tunnel requires Cloudflare dashboard setup."
    echo "  1. Zero Trust → Networks → Tunnels → Create tunnel"
    echo "  2. Copy the tunnel token shown in the dashboard"
    echo ""
    confirm "Have you created a tunnel in Cloudflare dashboard?" || { warn "Create the tunnel first"; return 1; }

    local _token; read -rp "  Enter your tunnel token: " _token
    [ -n "$_token" ] || { fail "Token required"; return 1; }

    local _cfg_dir="$HOME/.cloudflared"
    mkdir -p "$_cfg_dir"
    local _cfg_file="$_cfg_dir/config.yml"
    cat > "$_cfg_file" <<EOF
tunnel: $_token

ingress:
  - hostname: yourdomain.com
    service: $_local_url
    originRequest:
      http:
        - hostHeader: rewrite
EOF
    info "Config written to: $_cfg_file — edit hostname to match your domain."
    confirm "Edit the config file now?" && ${EDITOR:-nano} "$_cfg_file"

    local _hostname
    _hostname=$(grep "hostname:" "$_cfg_file" | head -1 \
        | sed 's/.*hostname:[[:space:]]*//' | sed 's/[[:space:]]*$//')
    [ -n "$_hostname" ] || { warn "Could not extract hostname from config"; return 1; }

    _tunnel_write_state "http" "https://$_hostname" "" ""
    ok "Named tunnel configured for: https://$_hostname"
}

tunnel_configure_ssh() {
    step "Configuring Cloudflare SSH Access"

    if ! command -v cloudflared &>/dev/null; then
        confirm "Install cloudflared now?" || { fail "cloudflared required"; return 1; }
        tunnel_install_cloudflared || return 1
    fi

    tunnel_load_state
    if [ -z "$TUNNEL_PUBLIC_URL" ]; then
        warn "HTTP tunnel must be configured first."
        confirm "Configure HTTP tunnel now?" || { fail "HTTP tunnel required"; return 1; }
        tunnel_configure_http "http://localhost:22" || return 1
        tunnel_load_state
    fi

    info "SSH access requires Cloudflare Access setup (Zero Trust → Access → Applications)."
    echo ""
    local _domain
    _domain=$(echo "$TUNNEL_PUBLIC_URL" | sed 's|https://||' | sed 's|/.*||')

    confirm "Create SSH access for '${_domain}'?" || { fail "Cancelled"; return 1; }

    local _ssh_host="ssh.${_domain}"
    _tunnel_write_state "ssh" "$TUNNEL_PUBLIC_URL" "$_ssh_host" ""
    _tunnel_add_ssh_to_tunnel_config "$_ssh_host"

    ok "SSH access configured for: $_ssh_host"
    info "Connect with: cloudflared access ssh --hostname $_ssh_host"
    echo ""
}

_tunnel_add_ssh_to_tunnel_config() {
    local _ssh_host="$1"
    local _cfg="$HOME/.cloudflared/config.yml"
    [ -f "$_cfg" ] || { warn "No cloudflared config found"; return 1; }

    grep -q "service: ssh://localhost:22" "$_cfg" && { ok "SSH already in config"; return 0; }

    cp "$_cfg" "${_cfg}.backup.$(date +%Y%m%d_%H%M%S)"

    awk -v ssh_host="$_ssh_host" '
    /^ingress:/ {
        print $0
        print "  - hostname: " ssh_host
        print "    service: ssh://localhost:22"
        print "    originRequest:"
        print "      access:"
        print "        required: true"
        next
    }
    { print }
    ' "$_cfg" > "/tmp/_tunnel_cfg.$$" && mv "/tmp/_tunnel_cfg.$$" "$_cfg"

    ok "SSH access added to tunnel config — restart service to apply."
}

tunnel_configure_reverse_ssh() {
    step "Configuring Reverse SSH Tunnel (VPS)"
    info "The system connects OUT to your VPS, which opens a port back in."
    echo ""

    local _vps_host _vps_user _rport _lport
    read -rp "  VPS hostname or IP: " _vps_host
    [ -n "$_vps_host" ] || { warn "VPS hostname required"; return 1; }

    read -rp "  VPS username [$(whoami)]: " _vps_user
    _vps_user="${_vps_user:-$(whoami)}"

    read -rp "  Remote port on VPS [2222]: " _rport
    _rport="${_rport:-2222}"

    read -rp "  Local port on this system [22]: " _lport
    _lport="${_lport:-22}"

    info "Testing VPS connectivity..."
    if ! ssh -T "${_vps_user}@${_vps_host}" \
            -o ConnectTimeout=5 -o BatchMode=yes true 2>/dev/null; then
        warn "Cannot connect to VPS — ensure SSH key is configured."
        confirm "Continue anyway?" || return 1
    fi

    echo ""
    echo "  Persistence Method:"
    echo "    1) Systemd service  (recommended — auto-reconnect)"
    echo "    2) Cron @reboot     (simpler, less reliable)"
    echo "    3) Manual           (no persistent setup)"
    echo ""
    local _method; read -rp "  Select [1]: " _method
    _method="${_method:-1}"

    case "$_method" in
        1) _tunnel_reverse_ssh_systemd "$_vps_host" "$_vps_user" "$_rport" "$_lport" || return 1 ;;
        2) _tunnel_reverse_ssh_cron "ssh -N -R ${_rport}:localhost:${_lport} ${_vps_user}@${_vps_host}" ;;
        3) info "Manual command:"; echo ""
           echo "  ssh -N -R ${_rport}:localhost:${_lport} ${_vps_user}@${_vps_host}"
           echo "" ;;
        *) warn "Invalid selection"; return 1 ;;
    esac

    _tunnel_write_state "reverse_ssh" "" "$_vps_host" "$_rport"
    ok "Reverse SSH configured — connect via: ssh -p ${_rport} ${_vps_user}@${_vps_host}"
    echo ""
}

_tunnel_reverse_ssh_systemd() {
    local _host="$1" _user="$2" _rport="$3" _lport="$4"
    local _svc="igor-reverse-ssh"
    local _svc_file="/etc/systemd/system/${_svc}.service"
    local _exec

    if command -v autossh &>/dev/null; then
        _exec="autossh -M 0 -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R ${_rport}:localhost:${_lport} ${_user}@${_host}"
        info "Using autossh for auto-reconnect."
    else
        _exec="ssh -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R ${_rport}:localhost:${_lport} ${_user}@${_host}"
        warn "autossh not found — using plain SSH. Install: pkg_install autossh"
    fi

    sudo tee "$_svc_file" > /dev/null <<EOF
[Unit]
Description=IGOR Reverse SSH Tunnel to ${_user}@${_host}:${_rport}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER}
ExecStart=${_exec}
Restart=on-failure
RestartSec=15s

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$_svc"
    sudo systemctl start  "$_svc"
    sleep 2

    if sudo systemctl is-active "$_svc" &>/dev/null; then
        ok "Reverse SSH service started and enabled."
        info "  Status: sudo systemctl status $_svc"
        info "  Logs:   sudo journalctl -u $_svc -f"
    else
        warn "Service failed to start — check: sudo journalctl -u $_svc"
        return 1
    fi
}

_tunnel_reverse_ssh_cron() {
    local _cmd="$1"
    local _line="@reboot sleep 30 && ${_cmd} -o ServerAliveInterval=30 -o ServerAliveCountMax=3 &"
    info "Add this to your crontab:"
    echo ""
    echo "  ${_line}"
    echo ""
    confirm "Open crontab -e now?" && crontab -e && ok "Crontab updated."
}

# ── Service Management ────────────────────────────────────────────────────────

tunnel_enable_service() {
    step "Enabling Tunnel Service"
    tunnel_load_state

    [ -n "$TUNNEL_TYPE" ] || { fail "No tunnel configured — configure one first."; return 1; }

    case "$TUNNEL_TYPE" in
        http)
            _tunnel_enable_http_service || return 1
            ;;
        ssh|reverse_ssh)
            ok "SSH tunnel services were already configured during setup."
            ;;
        *)
            fail "Unknown tunnel type: $TUNNEL_TYPE"; return 1 ;;
    esac

    tunnel_load_state
    _tunnel_write_state "$TUNNEL_TYPE" "$TUNNEL_PUBLIC_URL" \
        "$TUNNEL_SSH_HOST" "$TUNNEL_SSH_PORT"
}

_tunnel_enable_http_service() {
    local _svc="cloudflared"
    local _svc_file="/etc/systemd/system/${_svc}.service"
    local _cfg="$HOME/.cloudflared/config.yml"

    if [ ! -f "$_cfg" ]; then
        warn "No cloudflared config found: $_cfg"; return 1
    fi

    if [ ! -f "$_svc_file" ]; then
        sudo tee "$_svc_file" > /dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=${USER}
ExecStart=/usr/local/bin/cloudflared tunnel run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        info "Created service file: $_svc_file"
    fi

    sudo systemctl daemon-reload
    sudo systemctl enable "$_svc"
    sudo systemctl start  "$_svc"
    sleep 3

    if sudo systemctl is-active "$_svc" &>/dev/null; then
        ok "Cloudflare tunnel service enabled and started."
        info "  Status: sudo systemctl status $_svc"
        info "  Logs:   sudo journalctl -u $_svc -f"
    else
        warn "Service failed to start — check: sudo journalctl -u $_svc"
        return 1
    fi
}

# ── Live System Detection Helpers ────────────────────────────────────────────
#
# These functions probe actual system state — process table, systemd, the
# cloudflared API.  They do NOT read the state file.  tunnel_status() calls
# them and reconciles against the state file.

# _tunnel_detect_cloudflared
# Sets: _det_cf_installed ("yes"/"no"), _det_cf_running ("yes"/"no"),
#       _det_cf_url (first URL from `cloudflared tunnel list` or "")
_tunnel_detect_cloudflared() {
    _det_cf_installed="no"
    _det_cf_running="no"
    _det_cf_url=""

    command -v cloudflared &>/dev/null && _det_cf_installed="yes"

    if [ "$_det_cf_installed" = "yes" ]; then
        # Service check via systemctl (preferred) then process table fallback
        if sudo systemctl is-active cloudflared &>/dev/null 2>&1; then
            _det_cf_running="yes"
        elif pgrep -x cloudflared &>/dev/null 2>&1; then
            _det_cf_running="yes"
        fi

        # Try to get a live tunnel URL from the cloudflared API
        # `cloudflared tunnel list` prints a table; grab the first hostname column
        if [ "$_det_cf_running" = "yes" ]; then
            _det_cf_url=$(cloudflared tunnel list 2>/dev/null \
                | awk 'NR>1 && $2 != "" {print $2; exit}' || true)
        fi
    fi
}

# _tunnel_detect_reverse_ssh
# Sets: _det_rssh_active ("yes"/"no"),
#       _det_rssh_host (remote host extracted from process args or ""),
#       _det_rssh_port (remote port or ""),
#       _det_rssh_service (matching systemd unit name or "")
_tunnel_detect_reverse_ssh() {
    _det_rssh_active="no"
    _det_rssh_host=""
    _det_rssh_port=""
    _det_rssh_service=""

    # ── Process-table scan ─────────────────────────────────────────────────
    # Look for ssh processes with a -R flag (reverse tunnel)
    local _procs
    _procs=$(pgrep -fa "ssh" 2>/dev/null | grep -E "\-R [0-9]" || true)

    # Also look for autossh processes
    local _aprocs
    _aprocs=$(pgrep -fa "autossh" 2>/dev/null | grep -E "\-R [0-9]" || true)

    local _combined="${_procs}${_aprocs}"

    if [ -n "$_combined" ]; then
        _det_rssh_active="yes"
        # Extract remote port: -R <rport>:localhost:<lport>
        _det_rssh_port=$(echo "$_combined" \
            | grep -oE '\-R [0-9]+:' | head -1 | grep -oE '[0-9]+' || true)
        # Extract remote host (last non-option argument before the -R block)
        _det_rssh_host=$(echo "$_combined" \
            | grep -oE '[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+' | head -1 \
            | sed 's/.*@//' || true)
        # Fall back: bare hostname without user@
        if [ -z "$_det_rssh_host" ]; then
            _det_rssh_host=$(echo "$_combined" \
                | awk '{for(i=1;i<=NF;i++) if($i!~/^-/ && $(i-1)=="-R" && i>1) print $NF}' \
                | head -1 || true)
        fi
    fi

    # ── Systemd unit scan ──────────────────────────────────────────────────
    # Check igor-reverse-ssh first, then any other units matching ssh/autossh
    if sudo systemctl is-active "igor-reverse-ssh" &>/dev/null 2>&1; then
        _det_rssh_active="yes"
        _det_rssh_service="igor-reverse-ssh"
    else
        local _unit
        _unit=$(systemctl list-units --no-legend --state=active 2>/dev/null \
            | awk '{print $1}' \
            | grep -iE "ssh.*tunnel|autossh|reverse.*ssh" | head -1 || true)
        if [ -n "$_unit" ]; then
            _det_rssh_active="yes"
            _det_rssh_service="$_unit"
        fi
    fi
}

# _tunnel_adopt_state TYPE URL SSH_HOST SSH_PORT
# Write detected values into the state file after user confirms.
_tunnel_adopt_state() {
    local _type="$1" _url="$2" _host="$3" _port="$4"
    _tunnel_write_state "$_type" "$_url" "$_host" "$_port"
    ok "State file updated — IGOR now tracks this tunnel."
}

# ── Status ────────────────────────────────────────────────────────────────────

tunnel_status() {
    step "Tunnel Status"

    # ── 1. Load state file (may be empty / absent) ────────────────────────
    local TUNNEL_TYPE="" TUNNEL_PUBLIC_URL="" TUNNEL_SSH_HOST="" \
          TUNNEL_SSH_PORT="" TUNNEL_SERVICE_ENABLED="" TUNNEL_CONFIGURED_AT=""
    tunnel_load_state   # populates the locals above via source

    # ── 2. Independent system detection ──────────────────────────────────
    local _det_cf_installed _det_cf_running _det_cf_url
    _tunnel_detect_cloudflared

    local _det_rssh_active _det_rssh_host _det_rssh_port _det_rssh_service
    _tunnel_detect_reverse_ssh

    # ── 3. Print state-file section ────────────────────────────────────────
    echo ""
    echo -e "  ${BOLD:-}── State File ─────────────────────────────────────────${NC:-}"
    if [ -n "$TUNNEL_TYPE" ]; then
        local _when
        _when=$(date -d "@${TUNNEL_CONFIGURED_AT}" 2>/dev/null \
            || date -r "${TUNNEL_CONFIGURED_AT}" 2>/dev/null \
            || echo "unknown")
        printf "  %-18s %s\n" "Type:"         "$TUNNEL_TYPE"
        printf "  %-18s %s\n" "Configured:"   "$_when"
        case "$TUNNEL_TYPE" in
            http)
                printf "  %-18s %s\n" "Public URL:"   "${TUNNEL_PUBLIC_URL:-<not set>}"
                ;;
            ssh)
                printf "  %-18s %s\n" "SSH Host:"     "${TUNNEL_SSH_HOST:-<not set>}"
                ;;
            reverse_ssh)
                printf "  %-18s %s\n" "VPS Host:"     "${TUNNEL_SSH_HOST:-<not set>}"
                printf "  %-18s %s\n" "Remote Port:"  "${TUNNEL_SSH_PORT:-<not set>}"
                ;;
        esac
    else
        echo "  (no tunnel recorded in state file)"
    fi

    # ── 4. Print live system detection ────────────────────────────────────
    echo ""
    echo -e "  ${BOLD:-}── Live System ────────────────────────────────────────${NC:-}"

    # cloudflared binary
    if [ "$_det_cf_installed" = "yes" ]; then
        printf "  %-18s %s\n" "cloudflared:" "installed  ($(cloudflared --version 2>/dev/null | head -1))"
    else
        printf "  %-18s %s\n" "cloudflared:" "NOT installed"
    fi

    # cloudflared service
    if [ "$_det_cf_running" = "yes" ]; then
        printf "  %-18s %s\n" "CF service:"  "running"
        [ -n "$_det_cf_url" ] && printf "  %-18s %s\n" "CF live URL:" "$_det_cf_url"
    elif [ "$_det_cf_installed" = "yes" ]; then
        printf "  %-18s %s\n" "CF service:"  "NOT running"
    fi

    # reverse SSH
    if [ "$_det_rssh_active" = "yes" ]; then
        printf "  %-18s %s\n" "Reverse SSH:" "ACTIVE"
        [ -n "$_det_rssh_host" ]    && printf "  %-18s %s\n" "  Remote host:"  "$_det_rssh_host"
        [ -n "$_det_rssh_port" ]    && printf "  %-18s %s\n" "  Remote port:"  "$_det_rssh_port"
        [ -n "$_det_rssh_service" ] && printf "  %-18s %s\n" "  Systemd unit:" "$_det_rssh_service"
    else
        printf "  %-18s %s\n" "Reverse SSH:" "none detected"
    fi

    # ── 5. Reconciliation ─────────────────────────────────────────────────
    echo ""
    local _mismatch=false

    # Case A: CF running but state file says no tunnel / different type
    if [ "$_det_cf_running" = "yes" ] && [ "$TUNNEL_TYPE" != "http" ] && [ "$TUNNEL_TYPE" != "ssh" ]; then
        echo -e "  ${YEL:-}⚠ Reconciliation: cloudflared is running but state file does not record an HTTP/SSH tunnel.${NC:-}"
        _mismatch=true
        if confirm "  Adopt detected cloudflared tunnel into state file?"; then
            _tunnel_adopt_state "http" "${_det_cf_url:-}" "" ""
        fi
    fi

    # Case B: State says http/ssh active but CF is not running
    if { [ "$TUNNEL_TYPE" = "http" ] || [ "$TUNNEL_TYPE" = "ssh" ]; } \
            && [ "$_det_cf_running" = "no" ]; then
        echo -e "  ${YEL:-}⚠ Reconciliation: state file records a ${TUNNEL_TYPE} tunnel but cloudflared is NOT running.${NC:-}"
        _mismatch=true
        if confirm "  Clear stale state file entry?"; then
            _tunnel_clear_state
            ok "State file cleared."
        fi
    fi

    # Case C: Reverse SSH active but state file records nothing / wrong type
    if [ "$_det_rssh_active" = "yes" ] && [ "$TUNNEL_TYPE" != "reverse_ssh" ]; then
        echo -e "  ${YEL:-}⚠ Reconciliation: active reverse SSH tunnel detected but state file type is '${TUNNEL_TYPE:-<empty>}'.${NC:-}"
        _mismatch=true
        if confirm "  Adopt detected reverse SSH tunnel into state file?"; then
            _tunnel_adopt_state "reverse_ssh" "" \
                "${_det_rssh_host:-}" "${_det_rssh_port:-}"
        fi
    fi

    # Case D: State says reverse_ssh but no live tunnel detected
    if [ "$TUNNEL_TYPE" = "reverse_ssh" ] && [ "$_det_rssh_active" = "no" ]; then
        echo -e "  ${YEL:-}⚠ Reconciliation: state file records a reverse_ssh tunnel but none is currently active.${NC:-}"
        _mismatch=true
        if confirm "  Clear stale state file entry?"; then
            _tunnel_clear_state
            ok "State file cleared."
        fi
    fi

    if [ "$_mismatch" = "false" ]; then
        echo -e "  ${GRN:-}✓${NC:-} State file and live system agree."
    fi
    echo ""
}

# ── Teardown ──────────────────────────────────────────────────────────────────

tunnel_teardown() {
    step "Tunnel Teardown"
    tunnel_load_state

    if [ -z "$TUNNEL_TYPE" ]; then
        echo "  No tunnel configured."; return 0
    fi

    case "$TUNNEL_TYPE" in
        http)         _tunnel_teardown_http ;;
        ssh)          _tunnel_teardown_ssh  ;;
        reverse_ssh)  _tunnel_teardown_reverse_ssh ;;
    esac

    _tunnel_clear_state
    ok "Tunnel teardown complete."
    echo ""
}

_tunnel_teardown_http() {
    local _svc="cloudflared" _svc_file="/etc/systemd/system/cloudflared.service"
    sudo systemctl is-active   "$_svc" &>/dev/null && { info "Stopping $_svc...";   sudo systemctl stop    "$_svc"; }
    sudo systemctl is-enabled  "$_svc" &>/dev/null && { info "Disabling $_svc...";  sudo systemctl disable "$_svc"; }
    [ -f "$_svc_file" ] && confirm "Remove systemd service file?" && {
        sudo rm "$_svc_file"; sudo systemctl daemon-reload; ok "Service file removed."
    }
    command -v cloudflared &>/dev/null && confirm "Remove cloudflared binary?" && {
        sudo rm /usr/local/bin/cloudflared; ok "cloudflared removed."
    }
}

_tunnel_teardown_ssh() {
    local _cfg="$HOME/.cloudflared/config.yml"
    [ -f "$_cfg" ] || return 0
    confirm "Remove SSH access from tunnel config?" || return 0
    cp "$_cfg" "${_cfg}.backup.$(date +%Y%m%d_%H%M%S)"
    awk '
    /^ingress:/ { in_ing=1; print; next }
    in_ing && /service: ssh:/ { skip=1 }
    skip && /^[[:space:]]*$/ { skip=0; next }
    skip { next }
    { print }
    ' "$_cfg" > "/tmp/_t_clean.$$" && mv "/tmp/_t_clean.$$" "$_cfg"
    ok "SSH access removed from tunnel config."
}

_tunnel_teardown_reverse_ssh() {
    local _svc="igor-reverse-ssh" _f="/etc/systemd/system/igor-reverse-ssh.service"
    sudo systemctl is-active  "$_svc" &>/dev/null && { info "Stopping...";   sudo systemctl stop    "$_svc"; }
    sudo systemctl is-enabled "$_svc" &>/dev/null && { info "Disabling...";  sudo systemctl disable "$_svc"; }
    [ -f "$_f" ] && confirm "Remove service file?" && {
        sudo rm "$_f"; sudo systemctl daemon-reload; ok "Service file removed."
    }
}

# ── Igor Hooks ────────────────────────────────────────────────────────────────
# Registered via _tunnel_register_hooks() called from igor.sh.

_tunnel_hook_health() {
    [ -f "$TUNNEL_STATE_FILE" ] || { echo "ok:no tunnel configured"; return 0; }
    local TUNNEL_TYPE="" TUNNEL_SERVICE_ENABLED=""
    # shellcheck disable=SC1090
    source "$TUNNEL_STATE_FILE" 2>/dev/null || true
    if [ "$TUNNEL_SERVICE_ENABLED" = "true" ] && [ -n "$TUNNEL_TYPE" ]; then
        echo "ok:tunnel configured for $TUNNEL_TYPE"
    elif [ -n "$TUNNEL_TYPE" ]; then
        echo "warn:tunnel configured but service not enabled"
    else
        echo "ok:no tunnel configured"
    fi
}

_tunnel_hook_diagnose() {
    if command -v cloudflared &>/dev/null; then
        echo "CHECK:cloudflared_installed:ok:cloudflared binary found"
    else
        echo "CHECK:cloudflared_installed:fail:cloudflared not installed"
    fi

    if [ -f "$TUNNEL_STATE_FILE" ]; then
        echo "CHECK:tunnel_state:ok:tunnel state file exists"
        local TUNNEL_TYPE="" TUNNEL_SERVICE_ENABLED=""
        # shellcheck disable=SC1090
        source "$TUNNEL_STATE_FILE" 2>/dev/null || true
        if [ -n "$TUNNEL_TYPE" ]; then
            echo "CHECK:tunnel_type:ok:tunnel type is $TUNNEL_TYPE"
        else
            echo "CHECK:tunnel_type:warn:tunnel type not set in state"
        fi
        if [ "$TUNNEL_SERVICE_ENABLED" = "true" ]; then
            echo "CHECK:tunnel_service:ok:tunnel service enabled"
        else
            echo "CHECK:tunnel_service:warn:tunnel service not enabled"
        fi
    else
        echo "CHECK:tunnel_state:warn:tunnel state file does not exist"
    fi
}

_tunnel_hook_status_line() {
    local _status=""
    if [ -f "$TUNNEL_STATE_FILE" ]; then
        local TUNNEL_TYPE="" TUNNEL_PUBLIC_URL="" TUNNEL_SSH_HOST="" TUNNEL_SSH_PORT=""
        # shellcheck disable=SC1090
        source "$TUNNEL_STATE_FILE" 2>/dev/null || true
        case "${TUNNEL_TYPE:-}" in
            http)
                [ -n "$TUNNEL_PUBLIC_URL" ] \
                    && _status="${GRN:-}● HTTP${NC:-} $TUNNEL_PUBLIC_URL" \
                    || _status="${YEL:-}● HTTP${NC:-} (no URL)"
                ;;
            ssh)
                [ -n "$TUNNEL_SSH_HOST" ] \
                    && _status="${GRN:-}● SSH${NC:-} $TUNNEL_SSH_HOST" \
                    || _status="${YEL:-}● SSH${NC:-} (no host)"
                ;;
            reverse_ssh)
                [ -n "$TUNNEL_SSH_HOST" ] && [ -n "$TUNNEL_SSH_PORT" ] \
                    && _status="${GRN:-}● REVERSE SSH${NC:-} ${TUNNEL_SSH_HOST}:${TUNNEL_SSH_PORT}" \
                    || _status="${YEL:-}● REVERSE SSH${NC:-} (incomplete)"
                ;;
        esac
    fi
    echo -e "  Tunnel    : ${_status:-${DIM:-}● NONE${NC:-}}"
}

_tunnel_register_hooks() {
    if declare -f igor_register_hook &>/dev/null; then
        igor_register_hook "health"      "_tunnel_hook_health"
        igor_register_hook "diagnose"    "_tunnel_hook_diagnose"
        igor_register_hook "status_line" "_tunnel_hook_status_line"
    fi
}

# ── Main Menu ─────────────────────────────────────────────────────────────────

menu_tunnel() {
    while true; do
        _tunnel_init_state

        if declare -f igor_right_render &>/dev/null; then
            local _t="" _u=""
            _t=$(grep "^TUNNEL_TYPE="       "$TUNNEL_STATE_FILE" 2>/dev/null | cut -d'"' -f2 || echo "none")
            _u=$(grep "^TUNNEL_PUBLIC_URL=" "$TUNNEL_STATE_FILE" 2>/dev/null | cut -d'"' -f2 || echo "none")
            igor_right_render "Tunnel Management" \
                "Type"  "${_t}" \
                "URL"   "${_u}" \
                "---"   "Quick actions" \
                "hint"  "[1]  INSTALL CLOUDFLARED" \
                "hint"  "[2]  CONFIGURE HTTP" \
                "hint"  "[s]  STATUS" \
                "hint"  "[b]  BACK"
        fi

        local _opt
        _opt=$(igor_fzf_pick "Tunnel Management" \
            "_:INSTALLATION:"  \
            "1:INSTALL CLOUDFLARED:Install Cloudflared tunnel agent" \
            "_:HTTP TUNNEL:"  \
            "2:CONFIGURE HTTP:Set up HTTP tunnel (named or quick)" \
            "_:SSH TUNNEL:"  \
            "3:CLOUDFLARE SSH:SSH access via Cloudflare tunnel" \
            "4:REVERSE SSH:SSH access via VPS reverse tunnel" \
            "_:SERVICE:"  \
            "5:ENABLE SERVICE:Start tunnel service at boot" \
            "6:DISABLE SERVICE:Stop + disable tunnel service" \
            "_:MONITORING:"  \
            "s:STATUS:Show current tunnel status" \
            "t:TEARDOWN:Remove all tunnel configurations" \
            "b:BACK:Return to previous menu")

        case $? in 1) return ;; 2)
            header 2>/dev/null || true
            breadcrumb "Igor" "Tunnel"
            echo -e "  ${BOLD:-}Tunnel Management${NC:-}"
            echo ""
            echo -e "  1) INSTALL CLOUDFLARED  — Install Cloudflared tunnel agent"
            echo -e "  2) CONFIGURE HTTP       — Set up HTTP tunnel"
            echo -e "  3) CLOUDFLARE SSH       — SSH via Cloudflare"
            echo -e "  4) REVERSE SSH          — SSH via VPS reverse tunnel"
            echo -e "  5) ENABLE SERVICE       — Start at boot"
            echo -e "  6) DISABLE SERVICE      — Stop and disable"
            echo -e "  s) STATUS               — Show tunnel status"
            echo -e "  t) TEARDOWN             — Remove all configurations"
            echo -e "  b) BACK"
            echo ""
            read -rp "  Select: " _opt
            ;;
        esac

        [ "$_opt" = "_" ] && continue

        case "$_opt" in
            1) tunnel_install_cloudflared;  pause ;;
            2) tunnel_configure_http;       pause ;;
            3) tunnel_configure_ssh;        pause ;;
            4) tunnel_configure_reverse_ssh; pause ;;
            5) tunnel_enable_service;       pause ;;
            6)
                if sudo systemctl is-active  cloudflared &>/dev/null; then sudo systemctl stop    cloudflared; fi
                if sudo systemctl is-enabled cloudflared &>/dev/null; then sudo systemctl disable cloudflared; fi
                # Clear the service-enabled flag in state without touching other values
                sed -i 's/^TUNNEL_SERVICE_ENABLED=.*/TUNNEL_SERVICE_ENABLED=""/' \
                    "$TUNNEL_STATE_FILE" 2>/dev/null || true
                ok "Tunnel service disabled."
                pause
                ;;
            s|S) echo ""; tunnel_status; pause ;;
            t|T)
                confirm "Remove all tunnel configurations?" \
                    && tunnel_teardown
                pause
                ;;
            b|B|q|Q) return ;;
            *) warn "Invalid option."; pause ;;
        esac
    done
}
