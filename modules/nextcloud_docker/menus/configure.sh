#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/configure.sh
#  Configuration management menu for Nextcloud Docker module
# ==============================================================================

# ── Module helpers (prefixed with _mod_nextcloud_) ───────────────────────────

_mod_nextcloud_show_nginx_config() {
    step "Nginx Configuration Status"
    
    local _mod_dir _root _stacks _stack
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    _stack="${_stacks}/nextcloud"
    
    local nginx_file="${_stack}/nginx.conf"
    
    if [ -f "$nginx_file" ]; then
        echo "  Nginx configuration file: $nginx_file"
        echo "  Size: $(wc -l < "$nginx_file") lines"
        
        # Check for common configuration elements
        if grep -q "location ^~ /\.well-known" "$nginx_file"; then
            echo "  ✓ .well-known location block present"
        else
            echo "  ✗ .well-known location block missing"
        fi
        
        if grep -q "HTTP_X_FORWARDED_PROTO https" "$nginx_file"; then
            echo "  ✓ Forwarded proto configuration present"
        else
            echo "  ✗ Forwarded proto configuration missing"
        fi
    else
        echo "  ✗ Nginx configuration file not found"
        echo "  Expected at: $nginx_file"
    fi
    
    pause
}

_mod_nextcloud_upload_limit() {
    step "Upload Limit Configuration"
    
    local _mod_dir _root _stacks _stack
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    _stack="${_stacks}/nextcloud"
    
    echo "  Current upload limit settings:"
    
    if command -v docker &>/dev/null && [ -f "${_stack}/docker-compose.yml" ]; then
        echo "  Checking Docker environment..."
        # Try to get current upload limit from Nextcloud
        docker compose -f "${_stack}/docker-compose.yml" \
            --env-file "${_root}/secrets/db.env" \
            exec -T -u www-data app php occ config:system:get upload_max_filesize 2>/dev/null || \
            echo "    Unable to get current upload limit (Nextcloud not running)"
    else
        echo "    Docker not available or stack not configured"
    fi
    
    echo ""
    echo "  To change upload limit:"
    echo "    1. Use occ command: config:system:set upload_max_filesize --value=<size>"
    echo "    2. Example: 10G, 500M, 1G"
    echo ""
    
    local new_limit
    read -rp "  Enter new upload limit (or press Enter to skip): " new_limit
    
    if [ -n "$new_limit" ]; then
        if command -v docker &>/dev/null && [ -f "${_stack}/docker-compose.yml" ]; then
            docker compose -f "${_stack}/docker-compose.yml" \
                --env-file "${_root}/secrets/db.env" \
                exec -T -u www-data app php occ config:system:set upload_max_filesize --value="$new_limit" 2>/dev/null
            if [ $? -eq 0 ]; then
                ok "Upload limit set to: $new_limit"
            else
                fail "Failed to set upload limit"
            fi
        else
            fail "Cannot set upload limit - Nextcloud not accessible"
        fi
    else
        info "Upload limit unchanged"
    fi
    
    pause
}

_mod_nextcloud_admin_password() {
    step "Admin Password Management"
    
    local _mod_dir _root _stacks _stack
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    _stack="${_stacks}/nextcloud"
    
    echo "  Admin password management:"
    echo "    1. Reset admin password"
    echo "    2. Change admin password"
    echo ""
    
    local choice
    read -rp "  Select action (1-2, or Enter to cancel): " choice
    
    case "$choice" in
        1)
            echo "  Resetting admin password..."
            if command -v docker &>/dev/null && [ -f "${_stack}/docker-compose.yml" ]; then
                docker compose -f "${_stack}/docker-compose.yml" \
                    --env-file "${_root}/secrets/db.env" \
                    exec -T -u www-data app php occ user:resetpassword admin 2>/dev/null
                ok "Admin password reset initiated"
            else
                fail "Cannot reset password - Nextcloud not accessible"
            fi
            ;;
        2)
            echo "  Changing admin password..."
            if command -v docker &>/dev/null && [ -f "${_stack}/docker-compose.yml" ]; then
                docker compose -f "${_stack}/docker-compose.yml" \
                    --env-file "${_root}/secrets/db.env" \
                    exec -T -u www-data app php occ user:resetpassword admin 2>/dev/null
                ok "Admin password change initiated"
            else
                fail "Cannot change password - Nextcloud not accessible"
            fi
            ;;
        *)
            info "Admin password management cancelled"
            ;;
    esac
    
    pause
}

# ── Public entry point ───────────────────────────────────────────────────────────

menu_configure() {
    while true; do
        local opt
        opt=$(igor_fzf_pick "7: Configure" \
            "1:NGINX:Show nginx configuration status" \
            "2:UPLOAD:Change upload limits" \
            "3:PASSWORD:Reset admin password" \
            "4:TRUSTED:Manage trusted proxies" \
            "5:BACKUP:Backup/restore configuration" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "7: Configure"
        echo -e "  ${YEL}${BOLD}[7] Configuration Management${NC}"
        echo ""
        echo "   1) Nginx     - Show nginx configuration status"
        echo "   2) Upload    - Change upload limits"
        echo "   3) Password  - Reset admin password"
        echo "   4) Trusted   - Manage trusted proxies"
        echo "   5) Backup    - Backup/restore configuration"
        echo "   b) Back"
        echo ""
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case $opt in
            1)
                _mod_nextcloud_show_nginx_config ;;
            2)
                _mod_nextcloud_upload_limit ;;
            3)
                _mod_nextcloud_admin_password ;;
            4)
                step "Trusted Proxies Management"
                echo "  Trusted proxy management would be handled here"
                echo "  This typically involves editing nginx configuration"
                pause ;;
            5)
                step "Configuration Backup/Restore"
                echo "  Configuration backup/restore would be handled here"
                echo "  This would backup nginx.conf and other config files"
                pause ;;
            b|B|q|Q) return ;;
            *)
                warn "Invalid option. Please try again." 
                pause ;;
        esac
    done
}