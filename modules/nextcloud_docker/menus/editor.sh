#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/editor.sh
#  Configuration editor module.
#
#  This module handles:
#    • nginx configuration management (template-based via envsubst)
#    • Upload limit configuration
#    • Password management
# ==============================================================================

# ── Module helpers (prefixed with _mod_editor_) ─────────────────────────────

_mod_editor_inject_nginx() {
    step "Injecting nginx configuration from template"

    local tmpl="${IGOR_DIR}/web/nginx.conf.tmpl"
    local conf="${IGOR_DIR}/web/nginx.conf"

    if [ ! -f "$tmpl" ]; then
        fail "Template not found: $tmpl"
        pause
        return 1
    fi

    if ! command -v envsubst &>/dev/null; then
        fail "envsubst not found. Install gettext package."
        pause
        return 1
    fi

    # Auto-backup before overwrite
    if [ -f "$conf" ]; then
        local bak="${conf}.bak.$(date +%s)"
        cp "$conf" "$bak"
        info "Backed up existing config → $(basename "$bak")"
    fi

    # Gather template variables
    local nginx_domain
    nginx_domain=$(get_env NEXTCLOUD_TRUSTED_DOMAINS | awk '{print $2}')
    [ -z "$nginx_domain" ] && nginx_domain="localhost"

    export NGINX_DOMAIN="$nginx_domain"
    export UPLOAD_MAX="${UPLOAD_MAX:-10G}"
    export FASTCGI_TIMEOUT="${FASTCGI_TIMEOUT:-300}"

    # Render template — only substitute our three variables; nginx $vars pass through
    envsubst '${NGINX_DOMAIN} ${UPLOAD_MAX} ${FASTCGI_TIMEOUT}' \
        < "$tmpl" > "$conf"

    info "Rendered: NGINX_DOMAIN=${NGINX_DOMAIN}  UPLOAD_MAX=${UPLOAD_MAX}  FASTCGI_TIMEOUT=${FASTCGI_TIMEOUT}"

    # Test nginx configuration
    info "Testing nginx configuration..."
    if docker compose exec web nginx -t 2>/dev/null; then
        ok "nginx.conf syntax is valid."
    else
        fail "nginx.conf has syntax errors. Restoring backup..."
        [ -f "$bak" ] && cp "$bak" "$conf" && warn "Restored from backup."
        pause
        return 1
    fi

    # Reload nginx
    step "Reloading nginx"
    docker compose restart web

    ok "nginx configuration injected and reloaded."
    pause
}

_mod_editor_restore_nginx() {
    step "Restore nginx configuration"

    local conf="${IGOR_DIR}/web/nginx.conf"
    local tmpl="${IGOR_DIR}/web/nginx.conf.tmpl"

    local opt
    opt=$(igor_fzf_pick "Configure — Restore nginx config" \
        "1:FROM TEMPLATE:Re-render template (${UPLOAD_MAX:-10G} / ${FASTCGI_TIMEOUT:-300}s)" \
        "2:FROM BACKUP FILE:Choose a .bak file to restore" \
        "b:BACK:Go back without restoring")
    case $? in 1|2)
        echo "   1) Restore from template (re-renders ${UPLOAD_MAX:-10G} / ${FASTCGI_TIMEOUT:-300}s)"
        echo "   2) Restore from a backup file"
        echo "   b) Back"
        read -rp "  Select: " opt ;; esac
    case $opt in
        1)
            _mod_editor_inject_nginx
            return ;;
        2)
            # List available backups newest-first
            local backups=()
            while IFS= read -r f; do
                backups+=("$f")
            done < <(ls -1t "${IGOR_DIR}/web/nginx.conf.bak."* 2>/dev/null)

            if [ ${#backups[@]} -eq 0 ]; then
                warn "No backups found in web/."
                pause
                return
            fi

            echo ""
            local i=1
            for f in "${backups[@]}"; do
                local ts
                ts=$(basename "$f" | sed 's/nginx.conf.bak.//')
                echo "   ${i}) $(basename "$f")  ($(date -d "@${ts}" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$ts"))"
                (( i++ ))
            done
            echo ""
            read -rp "  Select backup number: " bnum
            if [[ "$bnum" =~ ^[0-9]+$ ]] && [ "$bnum" -ge 1 ] && [ "$bnum" -le ${#backups[@]} ]; then
                local chosen="${backups[$((bnum-1))]}"
                cp "$chosen" "$conf"
                ok "Restored from: $(basename "$chosen")"
                info "Testing restored config..."
                if docker compose exec web nginx -t 2>/dev/null; then
                    ok "Syntax valid. Reloading nginx..."
                    docker compose restart web
                    ok "nginx reloaded."
                else
                    fail "Restored config has syntax errors. Manual fix required."
                fi
            else
                warn "Invalid selection."
            fi
            pause
            ;;
        b|B) return ;;
    esac
}

_mod_editor_set_upload_limit() {
    step "Setting upload limits"

    local conf="${IGOR_DIR}/web/nginx.conf"
    echo ""
    info "Current UPLOAD_MAX: ${UPLOAD_MAX:-10G}"
    info "This value is set in config/defaults.env or ~/.config/igor/config.env"
    echo ""
    read -rp "  Enter new upload limit (e.g. 20G, 500M) or Enter to keep current: " new_limit
    if [ -n "$new_limit" ]; then
        # Persist to user config
        local user_conf="${HOME}/.config/igor/config.env"
        mkdir -p "$(dirname "$user_conf")"
        if grep -q '^UPLOAD_MAX=' "$user_conf" 2>/dev/null; then
            sed -i "s/^UPLOAD_MAX=.*/UPLOAD_MAX=${new_limit}/" "$user_conf"
        else
            echo "UPLOAD_MAX=${new_limit}" >> "$user_conf"
        fi
        export UPLOAD_MAX="$new_limit"
        ok "UPLOAD_MAX set to ${new_limit}. Re-inject nginx to apply (option 1)."
    else
        info "No change."
    fi
    pause
}

_mod_editor_reset_passwords() {
    step "Resetting Nextcloud admin password"
    local new_pass
    local occ="docker compose exec -T -u www-data app php occ"

    while true; do
        new_pass=$(ask "Enter new admin password (min 8 chars)" "" secret)
        [ ${#new_pass} -ge 8 ] && break
        warn "Must be at least 8 characters."
    done

    confirm_pass=$(ask "Confirm new password" "" secret)
    [ "$new_pass" != "$confirm_pass" ] && { fail "Passwords do not match."; pause; return 1; }

    $occ user:resetpassword "$(get_env NEXTCLOUD_ADMIN_USER)" --password-from-env

    ok "Password reset successful."
    pause
}

# ── Public entry point ───────────────────────────────────────────────────────────
menu_editor() {
    while true; do
        local opt
        opt=$(igor_fzf_pick "5: Configure" \
            "_:  NGINX  :" \
            "1:INJECT NGINX CONFIG:Apply config from template" \
            "2:RESTORE NGINX CONFIG:Restore from template or backup" \
            "3:SET UPLOAD LIMIT:Change max upload size" \
            "_:  NEXTCLOUD  :" \
            "4:RESET ADMIN PASSWORD:Change Nextcloud admin password" \
            "5:NC SETTINGS:trusted_proxies, domain URL, occ config fixes" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "5: Configure"
        echo -e "  ${YEL}${BOLD}[5] CONFIGURE${NC}"
        echo "  ── nginx ──"
        echo "   1) Inject nginx config (from template)"
        echo "   2) Restore nginx config (template or backup)"
        echo "   3) Set upload limit"
        echo "  ── nextcloud ──"
        echo "   4) Reset admin password"
        echo "   5) NC settings (trusted_proxies, domain URL, occ config)"
        echo "   b) Back"
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case $opt in
            1)  _mod_editor_inject_nginx ;;
            2)  _mod_editor_restore_nginx ;;
            3)  _mod_editor_set_upload_limit ;;
            4)  _mod_editor_reset_passwords ;;
            5)  _igor_load_module "network" 2>/dev/null || true
                _mod_network_inject_nc_config ;;
            q|Q|b|B) return ;;
        esac
    done
}
