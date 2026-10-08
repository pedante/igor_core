#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/lib/install/helpers.sh
#  Installation helper functions (prefixed _mod_install_).
#
#  Sourced by modules/nextcloud_docker/install.sh.
# ==============================================================================


# ── _mod_install_ensure_docker_runtime ────────────────────────────────────────
# S9 cross-module reuse: Nextcloud owns the need for an accessible Docker
# runtime; Docker/System own package and service host mechanics. If Docker is
# not already usable, request canonical docker.install through Igor's existing
# capability dispatcher. Never regain equivalent host authority with raw
# systemctl/pkg helpers when that provider is unavailable or declined.
_mod_install_ensure_docker_runtime() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        return 0
    fi

    info "Docker runtime is unavailable — requesting canonical Docker setup..."

    if ! declare -f ai_execute_tool >/dev/null 2>&1; then
        fail "Canonical capability dispatcher is unavailable; cannot prepare Docker safely."
        return 1
    fi

    local _request
    _request='{"tool":"run_capability","id":"docker.install","provider":"docker","inputs":{},"capability_version":1}'
    if ! ai_execute_tool "$_request"         "Nextcloud requires an installed, enabled, active and reachable Docker Engine."; then
        fail "Docker setup was not completed through the canonical capability path."
        return 1
    fi

    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        fail "Canonical Docker setup completed, but the daemon is still not accessible to this user."
        return 1
    fi
    return 0
}


# ── _mod_install_load_tier ────────────────────────────────────────────────────
# Sources lib/tier_config.sh to populate NC_TIER_* variables, then applies any
# user overrides from config/stacks/nextcloud/tier_overrides.env.
# Prints the detected tier and lists any overridden variables.
_mod_install_load_tier() {
    local _mod_dir
    # BASH_SOURCE[0] = lib/install/helpers.sh → ../../ = nextcloud_docker module root
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    local _tier_cfg="${_mod_dir}/lib/tier_config.sh"

    if [ -f "$_tier_cfg" ]; then
        source "$_tier_cfg"
    else
        warn "tier_config.sh not found — using constrained defaults"
        NC_TIER_VOLUME_STRATEGY=named
        NC_TIER_PHP_MEMORY=256M
        NC_TIER_PHP_PM_MAX=5
        NC_TIER_OPCACHE_MEMORY=64M
        NC_TIER_REDIS_MEMORY=64m
        NC_TIER_ENABLE_PREVIEWS=false
        NC_TIER_CRON_MODE=webcron
        NC_TIER_SATELLITE_IMMICH=hidden
        NC_TIER_SATELLITE_COLLABORA=hidden
        NC_TIER_SATELLITE_ONLYOFFICE=hidden
        NC_TIER_SATELLITE_COTURN=optional
        export NC_TIER_VOLUME_STRATEGY NC_TIER_PHP_MEMORY NC_TIER_PHP_PM_MAX \
               NC_TIER_OPCACHE_MEMORY NC_TIER_REDIS_MEMORY NC_TIER_ENABLE_PREVIEWS \
               NC_TIER_CRON_MODE NC_TIER_SATELLITE_IMMICH NC_TIER_SATELLITE_COLLABORA \
               NC_TIER_SATELLITE_ONLYOFFICE NC_TIER_SATELLITE_COTURN
    fi

    # User overrides — apply AFTER tier defaults, print changed variables
    local _overrides="${IGOR_STACKS:-${IGOR_DIR}/config/stacks}/nextcloud/tier_overrides.env"
    if [ -f "$_overrides" ]; then
        local _v _before _after
        declare -A _before_snap
        for _v in NC_TIER_VOLUME_STRATEGY NC_TIER_DATA_PATH NC_TIER_PHP_MEMORY \
                  NC_TIER_PHP_PM_MAX NC_TIER_OPCACHE_MEMORY NC_TIER_REDIS_MEMORY \
                  NC_TIER_ENABLE_PREVIEWS NC_TIER_CRON_MODE \
                  NC_TIER_SATELLITE_IMMICH NC_TIER_SATELLITE_COLLABORA \
                  NC_TIER_SATELLITE_ONLYOFFICE NC_TIER_SATELLITE_COTURN; do
            _before_snap[$_v]="${!_v}"
        done
        set -a; source "$_overrides" 2>/dev/null || true; set +a
        info "Tier overrides loaded from: ${_overrides}"
        for _v in "${!_before_snap[@]}"; do
            if [ "${!_v}" != "${_before_snap[$_v]}" ]; then
                info "  override: ${_v}=${!_v}  (was: ${_before_snap[$_v]:-<unset>})"
            fi
        done
    fi

    info "Hardware tier: ${IGOR_TIER:-constrained}  (volume strategy: ${NC_TIER_VOLUME_STRATEGY})"
}

# ── _mod_install_setup_host_cron ─────────────────────────────────────────────
# Install and enable the host cron daemon when NC_TIER_CRON_MODE=system.
# Uses pkg_install / pkg_svc_name so the correct package and service name
# are used on both Debian (cron) and Arch (cronie).
_mod_install_setup_host_cron() {
    [ "${NC_TIER_CRON_MODE:-webcron}" = "system" ] || return 0

    local _svc
    _svc=$(declare -f pkg_svc_name &>/dev/null && pkg_svc_name svc_cron || echo "cron")

    if ! command -v cron &>/dev/null && ! command -v crond &>/dev/null; then
        step "Installing host cron daemon (${_svc})..."
        if declare -f pkg_install &>/dev/null; then
            pkg_install pkg_cron
        fi
    fi

    # Enable and start — safe no-op if already running
    sudo systemctl enable "$_svc" 2>/dev/null || true
    sudo systemctl start  "$_svc" 2>/dev/null || true

    if systemctl is-active --quiet "$_svc" 2>/dev/null; then
        ok "Host cron daemon (${_svc}) is running."
    else
        warn "Host cron daemon (${_svc}) could not be started. Check: systemctl status ${_svc}"
    fi
}

# ── _mod_install_ensure_secrets ───────────────────────────────────────────────
# Check and collect all required credentials into secrets/db.env and
# secrets/onlyoffice.env.  Prompts only for missing values.
_mod_install_ensure_secrets() {
    step "Checking credentials (db.env)"

    # Define environment file paths
    local _root _db_env _oo_env
    _root="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
    _db_env="${_root}/secrets/db.env"
    _oo_env="${_root}/secrets/onlyoffice.env"

    # Export for use in this function
    export DB_ENV="$_db_env"
    export OO_ENV="$_oo_env"

    touch "${DB_ENV}"; chmod 600 "${DB_ENV}"
    local changed=false

    [ -z "$(get_env POSTGRES_USER)" ]     && { set_env POSTGRES_USER "nextcloud"; changed=true; }
    [ -z "$(get_env POSTGRES_DB)" ]       && { set_env POSTGRES_DB "nextcloud"; changed=true; }
    if [ -z "$(get_env POSTGRES_PASSWORD)" ]; then
        local p; p=$(ask "PostgreSQL password (blank = auto-generate)" "" secret)
        [ -z "$p" ] && p=$(openssl rand -hex 16)
        set_env POSTGRES_PASSWORD "$p"; changed=true; ok "DB password set."
    fi
    if [ -z "$(get_env NEXTCLOUD_ADMIN_USER)" ]; then
        local u; u=$(ask "Nextcloud admin username" "admin")
        set_env NEXTCLOUD_ADMIN_USER "${u:-admin}"; changed=true
    fi
    if [ -z "$(get_env NEXTCLOUD_ADMIN_PASSWORD)" ]; then
        local p
        while true; do
            p=$(ask "Nextcloud admin password (min 8 chars)" "" secret)
            [ ${#p} -ge 8 ] && break
            warn "Must be at least 8 characters."
        done
        set_env NEXTCLOUD_ADMIN_PASSWORD "$p"; changed=true; ok "Admin password set."
    fi
    if [ -z "$(get_env NEXTCLOUD_TRUSTED_DOMAINS)" ]; then
        local d; d=$(ask "Your public domain (e.g. cloud.example.com)")
        local lan; lan=$(hostname -I 2>/dev/null | awk '{print $1}')
        set_env NEXTCLOUD_TRUSTED_DOMAINS "localhost ${d} ${lan}"; changed=true
    fi
    if [ ! -f "${OO_ENV}" ] || [ -z "$(grep "^JWT_SECRET=" "${OO_ENV}" 2>/dev/null | cut -d= -f2)" ]; then
        printf 'JWT_SECRET=%s\n' "$(openssl rand -hex 32)" > "${OO_ENV}"
        chmod 600 "${OO_ENV}"; ok "OnlyOffice JWT secret generated."; changed=true
    fi
    export JWT_SECRET; JWT_SECRET=$(grep "^JWT_SECRET=" "${OO_ENV}" | cut -d= -f2)
    $changed && ok "Credentials saved to ${DB_ENV}" || ok "All credentials present."
}

# ── _mod_install_handle_existing_data ────────────────────────────────────────
# Handle existing user data before a fresh Nextcloud install.
#
# Safety contract:
#   • User files are NEVER silently deleted — always explicit choice first
#   • The data dir itself is NEVER rm -rf'd — only specific files/subdirs
#   • NC-internal markers (.ocdata, appdata_*, etc.) are removed after the
#     user data question so the NC entrypoint can run occ maintenance:install
#
_mod_install_handle_existing_data() {
    local nc_data="${NC_DATA}"
    [ -d "$nc_data" ] || return 0

    step "Scanning data directory: ${nc_data}"

    # ── Inventory the data dir ────────────────────────────────────────────────
    # user_folders: any subdirectory that isn't an NC-internal one
    # nc_markers:   files/dirs that block occ maintenance:install but are not
    #               user data (safe to remove before entrypoint runs)
    local user_folders=() nc_markers=()

    local _d _dname
    for _d in "${nc_data}"/*/; do
        [ -d "$_d" ] || continue
        _dname=$(basename "$_d")
        case "$_dname" in
            appdata_*|updater-*|__groupfolders) nc_markers+=("$_dname"); continue ;;
        esac
        user_folders+=("$_dname")   # admin folder IS included — it may have files
    done
    [ -f "${nc_data}/.ocdata"       ] && nc_markers+=(".ocdata")
    [ -f "${nc_data}/nextcloud.log" ] && nc_markers+=("nextcloud.log")
    [ -f "${nc_data}/owncloud.log"  ] && nc_markers+=("owncloud.log")

    # ── User data question ────────────────────────────────────────────────────
    local _admin_user; _admin_user=$(get_env NEXTCLOUD_ADMIN_USER 2>/dev/null || echo "")
    if [ ${#user_folders[@]} -gt 0 ]; then
        echo ""
        warn "Existing data folders found in ${nc_data}:"
        echo ""
        local _f _sz _label
        for _f in "${user_folders[@]}"; do
            _sz=$(du -sh "${nc_data}/${_f}" 2>/dev/null | cut -f1 || echo "?")
            _label=""
            [[ -n "$_admin_user" && "$_f" == "$_admin_user" ]] && _label="  (admin user)"
            printf "      %-30s  %-8s%s\n" "${_f}" "${_sz}" "${_label}"
        done
        echo ""
        local _choice
        _choice=$(igor_fzf_pick "Install — Existing User Data" \
            "1:KEEP ALL FILES:Move aside, reinstall fresh, restore after  (recommended)" \
            "2:BACKUP THEN WIPE:Back up to timestamped folder, then delete" \
            "3:DELETE PERMANENTLY:Wipe now — CANNOT be undone" \
            "4:ABORT:I will handle this manually")
        case $? in 1|2)
            echo -e "  ${CYAN}What do you want to do with these folders?${NC}"
            echo "   1) Keep all files — recommended for reinstalls"
            echo "   2) Back up to a timestamped folder, then wipe"
            echo "   3) Delete permanently — CANNOT be undone"
            echo "   4) Abort — I will handle this manually"
            echo ""
            read -rp "  Choose [1/2/3/4]: " _choice ;; esac
        case "${_choice:-4}" in
            1)
                local _tmpdir; _tmpdir="${nc_data%/*}/.igor_nc_tmp_$$"
                step "Moving folders aside (will restore after install)"
                sudo mkdir -p "$_tmpdir"
                for _f in "${user_folders[@]}"; do
                    sudo mv "${nc_data}/${_f}" "${_tmpdir}/" \
                        && info "  Moved: ${_f}" \
                        || warn "  Could not move ${_f} — check sudo"
                done
                export _IGOR_NC_DATA_TMP="$_tmpdir"
                ok "Folders moved aside. They will be restored after Nextcloud installs." ;;
            2)
                local _bdir; _bdir="${nc_data%/*}/igor_backup_$(date +%Y%m%d_%H%M%S)"
                step "Backing up to ${_bdir}"
                sudo mkdir -p "$_bdir"
                for _f in "${user_folders[@]}"; do
                    sudo mv "${nc_data}/${_f}" "${_bdir}/" \
                        && ok "  Backed up: ${_f}" \
                        || warn "  Could not back up ${_f}"
                done
                ok "Backup complete: ${_bdir}" ;;
            3)
                confirm "Delete ALL listed folders permanently? CANNOT be undone." \
                    || { pause; return 1; }
                for _f in "${user_folders[@]}"; do
                    sudo rm -rf "${nc_data:?}/${_f}" && ok "  Deleted: ${_f}"
                done ;;
            4|*)
                warn "Aborted — nothing changed."
                pause; return 1 ;;
        esac
    else
        ok "No user data folders found."
    fi

    # ── Remove NC-internal markers that block occ maintenance:install ─────────
    # These are NOT user data — NC recreates them automatically on first run.
    # .ocdata  : presence tells NC the dir is already initialised → install aborts
    # appdata_ : NC app data cache, safe to remove
    # updater-*: NC updater working dir
    if [ ${#nc_markers[@]} -gt 0 ]; then
        step "Removing NC install markers"
        for _m in "${nc_markers[@]}"; do
            sudo rm -rf "${nc_data:?}/${_m}" \
                && info "  Removed: ${_m}" || true
        done
    fi

    # ── Fix ownership so the entrypoint can write ─────────────────────────────
    sudo chown "${NC_UID:-1004}:${NC_GID:-1004}" "${nc_data}" 2>/dev/null \
        || sudo chown "${NC_UID:-1004}:${NC_GID:-1004}" "${nc_data}" 2>/dev/null || true
    sudo chmod 750 "${nc_data}"
    ok "Data directory ready."
}

# ── _mod_install_wipe_docker_state ────────────────────────────────────────────
# Stop all containers, prune networks, and remove nextcloud_* named volumes.
_mod_install_wipe_docker_state() {
    step "Wiping all stale Docker state"
    nextcloud_docker__compose down --remove-orphans 2>/dev/null || true
    # shellcheck disable=SC2046
    docker rm -f $(docker ps -aq) 2>/dev/null || true
    docker network prune -f 2>/dev/null || true
    sleep 2
    local vol_db vol_nc
    vol_db=$(docker volume ls -q | grep "_db$"        | head -1)
    vol_nc=$(docker volume ls -q | grep "_nextcloud$" | head -1)
    [ -n "$vol_db" ] && docker volume rm "$vol_db" 2>/dev/null && ok "DB volume removed."        || info "No DB volume."
    [ -n "$vol_nc" ] && docker volume rm "$vol_nc" 2>/dev/null && ok "Nextcloud volume removed." || info "No nextcloud volume."
    sudo rm -f "./config/config.php" 2>/dev/null || true
    ok "Docker state clean."
}
