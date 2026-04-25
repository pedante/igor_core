#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/install.sh
#  First-run installation wizard module — thin loader.
#
#  Sub-files (sourced below):
#    lib/install/helpers.sh     — _mod_install_* helper functions
#    lib/install/start_stack.sh — _mod_setup_start_stack()
#    lib/install/reset_stack.sh — _mod_setup_reset_stack()
#    lib/install/orphan.sh      — _mod_setup_orphan_cleanup()
#    lib/install/migrate.sh     — _mod_setup_migrate()
#
#  Public entry points (defined in this file):
#    menu_install()             — first-run wizard (S→0 WIZARD)
#    _mod_setup_start_fresh()   — alias for menu_install
# ==============================================================================

_install_mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${_install_mod_dir}/lib/install/helpers.sh"
source "${_install_mod_dir}/lib/install/start_stack.sh"
source "${_install_mod_dir}/lib/install/reset_stack.sh"
source "${_install_mod_dir}/lib/install/orphan.sh"
source "${_install_mod_dir}/lib/install/migrate.sh"

# ── [0] WIZARD — First-run installation ──────────────────────────────────────
menu_install() {
    # Define environment file paths for use throughout the installation
    local _root _db_env _oo_env
    _root="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
    _db_env="${_root}/secrets/db.env"
    _oo_env="${_root}/secrets/onlyoffice.env"

    # Export for use in this function and called functions
    export DB_ENV="$_db_env"
    export OO_ENV="$_oo_env"

    # Load tier defaults + any user overrides (must run before template rendering)
    _mod_install_load_tier

    header
    echo -e "  ${MAG}${BOLD}╔══ FIRST-RUN INSTALLATION WIZARD ══╗${NC}"
    echo ""

    # ── Fast path: existing volumes found ─────────────────────────────────────
    # If nextcloud_* volumes already exist, offer to just start services.
    # This handles: moved Pi, cloned repo to new folder, after docker stop.
    local _existing_vols=0
    docker volume inspect nextcloud_db &>/dev/null        && _existing_vols=$((_existing_vols+1))
    docker volume inspect nextcloud_nextcloud &>/dev/null && _existing_vols=$((_existing_vols+1))

    if [[ "$_existing_vols" -gt 0 ]]; then
        # ── Right pane: volume info + destructive warning ─────────────────────
        if declare -f igor_right_render &>/dev/null; then
            local _vdb_sz _vdb_age _vnc_sz _vnc_age
            _vdb_sz=$(_igor_vol_size  nextcloud_db)
            _vdb_age=$(_igor_vol_age  nextcloud_db)
            _vnc_sz=$(_igor_vol_size  nextcloud_nextcloud)
            _vnc_age=$(_igor_vol_age  nextcloud_nextcloud)
            local _warn_col=$'\033[1;31m' _rst=$'\033[0m'
            igor_right_render "Install Wizard" \
                "---"          "Existing Volumes" \
                "nextcloud_db" "${_vdb_sz}  (${_vdb_age})" \
                "nextcloud_nc" "${_vnc_sz}  (${_vnc_age})" \
                "---"          "Options" \
                "Option 1"     "Start with existing data (safe)" \
                "Option 2"     "${_warn_col}FULL REINSTALL${_rst}" \
                "hint"         "Option 2 DELETES both volumes permanently"
        fi
        echo -e "  ${YEL}Existing Nextcloud volumes detected:${NC}"
        docker volume inspect nextcloud_db &>/dev/null && \
            printf "  ✔ %-30s %s\n" "nextcloud_db" "(${_vdb_sz}  ${_vdb_age})"
        docker volume inspect nextcloud_nextcloud &>/dev/null && \
            printf "  ✔ %-30s %s\n" "nextcloud_nextcloud" "(${_vnc_sz}  ${_vnc_age})"
        echo ""
        local _choice
        _choice=$(igor_fzf_pick "Install — Existing Volumes Detected" \
            "1:START WITH EXISTING DATA:Keep all data — recommended" \
            "2:FULL REINSTALL:DESTROYS database and app files")
        case $? in 1|2)
            echo -e "  ${CYAN}[1]${NC} Start services using existing volumes  (recommended — keeps all data)"
            echo -e "  ${CYAN}[2]${NC} Full reinstall  (DESTROYS database and app files)"
            echo ""
            read -rp "  Choose [1/2]: " _choice ;; esac
        if [[ "${_choice:-1}" == "1" ]]; then
            _mod_setup_start_stack
            return
        fi
        echo ""
        warn "Proceeding with full reinstall — existing volumes will be wiped."
        echo ""
    else
        # ── Right pane: fresh install info ────────────────────────────────────
        if declare -f igor_right_render &>/dev/null; then
            igor_right_render "Install Wizard" \
                "Status"    "No existing volumes" \
                "---"       "Will set up" \
                "Database"  "New PostgreSQL volume" \
                "App data"  "New Nextcloud volume" \
                "Data dir"  "${NC_DATA:-not set}" \
                "hint"      "Fresh install — no data will be deleted"
        fi
        echo "   This wizard will:"
        echo "   • Ask what to do with any existing user data"
        echo "   • Collect passwords and generate all config files"
        echo "   • Wipe stale Docker state"
        echo "   • Let the entrypoint install Nextcloud cleanly"
        echo "   • Apply all recommended settings for Pi 3 + Cloudflare"
        echo ""
        confirm "Start fresh installation?" || return
    fi

    # ── Step 1: Prerequisites ──────────────────────────────────────────────────
    step "Checking prerequisites"
    local abort=false
    command -v docker &>/dev/null || { fail "Docker not installed — run Menu 1 first."; abort=true; }
    if ! docker info &>/dev/null; then
        # On Arch (and any distro where Docker was just installed), the daemon
        # may not be running yet.  Try to start it before giving up.
        info "Docker daemon not responding — attempting to start..."
        if declare -f pkg_install_docker_post &>/dev/null; then
            pkg_install_docker_post 2>/dev/null || true
        else
            sudo systemctl enable docker 2>/dev/null || true
            sudo systemctl start  docker 2>/dev/null || true
            sleep 2
        fi
        docker info &>/dev/null || { fail "Docker not running or user not in docker group."; abort=true; }
    fi
    [ -f "${COMPOSE_FILE}" ]        || { fail "docker-compose.yml not found in $(pwd)"; abort=true; }
    $abort && { warn "Fix issues above and re-run."; pause; return 1; }
    ok "Prerequisites OK."

    # ── Step 1b: Verify / change data directory ────────────────────────────────
    step "Nextcloud data directory"
    echo ""
    info "Current path: ${NC_DATA}"
    echo "  This is where user files live (your external HD folder)."
    echo "  Changing it here updates config.env and all permission operations."
    echo ""
    if confirm "Change data directory path?"; then
        local new_data; new_data=$(ask "New NC_DATA path" "${NC_DATA}")
        if [ -n "$new_data" ] && [ "$new_data" != "${NC_DATA}" ]; then
            touch ./config.env
            grep -q "^NC_DATA=" ./config.env \
                && sed -i "s|^NC_DATA=.*|NC_DATA=${new_data}|" ./config.env \
                || echo "NC_DATA=${new_data}" >> ./config.env
            local new_mount; new_mount=$(dirname "$new_data")
            grep -q "^HD_MOUNT=" ./config.env \
                && sed -i "s|^HD_MOUNT=.*|HD_MOUNT=${new_mount}|" ./config.env \
                || echo "HD_MOUNT=${new_mount}" >> ./config.env
            NC_DATA="$new_data"; HD_MOUNT="$new_mount"
            set -a; . ./config.env; set +a   # reload so rest of session uses new paths
            ok "Data dir : $NC_DATA"
            ok "Mount pt : $HD_MOUNT"
            warn "If docker-compose.yml has a hardcoded data path, update it too."
        fi
    fi

    # ── Step 1c: Keep or reset credentials ────────────────────────────────────
    if [ -f "${DB_ENV}" ] && [ -s "${DB_ENV}" ]; then
        step "Existing credentials found"
        echo ""
        echo -e "  ${CYAN}Stored values (passwords masked):${NC}"
        printf "  %-22s %s\n" "Admin user:"    "$(get_env NEXTCLOUD_ADMIN_USER)"
        printf "  %-22s %s\n" "DB user:"       "$(get_env POSTGRES_USER)"
        printf "  %-22s %s\n" "Trusted domain:" "$(get_env NEXTCLOUD_TRUSTED_DOMAINS | awk '{print $2}')"
        printf "  %-22s %s\n" "DB password:"   "$([ -n "$(get_env POSTGRES_PASSWORD)" ]        && echo '****' || echo 'NOT SET')"
        printf "  %-22s %s\n" "Admin password:" "$([ -n "$(get_env NEXTCLOUD_ADMIN_PASSWORD)" ] && echo '****' || echo 'NOT SET')"
        echo ""
        if confirm "Keep existing credentials? (recommended for reinstalls)"; then
            ok "Keeping existing credentials."
        else
            warn "Clearing db.env — you will be asked for new values."
            > "${DB_ENV}"; chmod 600 "${DB_ENV}"
        fi
    fi

    # ── Step 2: Handle existing user data BEFORE anything starts ──────────────
    _mod_install_handle_existing_data || return 1

    # ── Step 3: Collect credentials ────────────────────────────────────────────
    _mod_install_ensure_secrets

    # ── Step 4: Wipe ALL Docker state ──────────────────────────────────────────
    _mod_install_wipe_docker_state

    # ── Step 5: Write config files ────────────────────────────────────────────
    info "Configuration files will be generated by editor and install modules"
    info "For now, creating basic nginx config..."

    # ── Step 6: Permissions ───────────────────────────────────────────────────
    step "Setting permissions"
    local nc_data="${NC_DATA}"
    own_dir "./web"
    sudo mkdir -p "${nc_data}"
    sudo chown "${NC_UID}:${NC_GID}" "${nc_data}"
    sudo chmod 750 "${nc_data}"
    ok "Permissions set."

    # ── Step 7: Start stack ───────────────────────────────────────────────────
    step "Starting Docker stack"
    nextcloud_docker__compose up -d --build
    echo ""

    # ── Step 8: Wait for DB ───────────────────────────────────────────────────
    wait_for_db 120 || { pause; return 1; }

    # ── Step 9: Wait for entrypoint to install NC ─────────────────────────────
    step "Waiting for Nextcloud entrypoint to install (3-5 min on Pi 3)"
    info "Please wait..."
    local waited=0 max_wait=480
    while [ $waited -lt $max_wait ]; do
        nextcloud_docker__compose logs app 2>/dev/null | grep -q "fpm is running" && break
        sleep 5; waited=$((waited+5)); printf "."
    done
    echo ""
    [ $waited -ge $max_wait ] && warn "Timed out waiting for FPM — continuing anyway."
    sleep 5

    # ── Step 10: Verify installation ──────────────────────────────────────────
    step "Verifying Nextcloud installation"
    local http_port="${NEXTCLOUD_HTTP_PORT:-8080}"
    local is_installed="" tries=0
    while [ $tries -lt 12 ]; do
        is_installed=$(nextcloud_docker__compose exec -T -u www-data app php occ status 2>/dev/null \
            | grep "installed:" | awk '{print $2}' | tr -d '[:space:]')
        [ "$is_installed" = "true" ] && break
        info "Not ready yet — waiting 15s... ($((tries+1))/12)"
        sleep 15; tries=$((tries+1))
    done

    if [ "$is_installed" = "true" ]; then
        ok "Nextcloud installed successfully."
    else
        # HTTP fallback — status.php returns 200 even when installed=false (wizard page)
        # Must check the JSON body for "installed":true
        local status_json; status_json=$(curl -s --max-time 10 \
            "http://localhost:${http_port}/status.php" 2>/dev/null)
        if echo "$status_json" | grep -q '"installed":true'; then
            ok "Nextcloud installed and responding."
        elif echo "$status_json" | grep -q '"installed":false'; then
            fail "Nextcloud shows setup wizard — auto-install did not complete."
            echo ""
            echo "  The data directory may still have files blocking occ maintenance:install."
            echo "  Check logs: nextcloud_docker__compose logs app --tail=50"
            pause; return 1
        else
            fail "Nextcloud did not respond on port ${http_port}."
            info "Check: nextcloud_docker__compose logs --tail=40"
            pause; return 1
        fi
    fi

    # ── Restore user folders that were moved aside (option 1) ─────────────────
    if [[ -n "${_IGOR_NC_DATA_TMP:-}" && -d "$_IGOR_NC_DATA_TMP" ]]; then
        step "Restoring user folders to data directory"
        local _nc_uid="${NC_UID:-1004}"
        for _item in "$_IGOR_NC_DATA_TMP"/*/; do
            [ -d "$_item" ] || continue
            local _iname; _iname=$(basename "$_item")
            sudo mv "$_item" "${nc_data}/" \
                && info "  Restored: ${_iname}" || warn "  Could not restore: ${_iname}"
        done
        sudo rmdir "$_IGOR_NC_DATA_TMP" 2>/dev/null || true
        sudo chown -R "${_nc_uid}:${_nc_uid}" "${nc_data}" 2>/dev/null \
            || sudo chown -R "${_nc_uid}:${_nc_uid}" "${nc_data}" 2>/dev/null || true
        unset _IGOR_NC_DATA_TMP
        ok "User folders restored."
        echo ""
        echo "  Run 5→1 SCAN FILES to rebuild the Nextcloud file cache."
        echo "  Your files will appear in Nextcloud after the scan completes."
    fi

    ok "Installation wizard completed successfully!"
    pause
}

# ── _mod_setup_start_fresh ────────────────────────────────────────────────────
# Alias for the full install wizard — same as 0. WIZARD.
_mod_setup_start_fresh() {
    menu_install
}
