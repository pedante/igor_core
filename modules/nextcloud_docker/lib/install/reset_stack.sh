#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/lib/install/reset_stack.sh
#  Destroy containers + named volumes (user files on disk are never touched).
#
#  Sourced by modules/nextcloud_docker/install.sh.
# ==============================================================================

# ── _mod_setup_reset_stack ────────────────────────────────────────────────────
# Destroys containers + named volumes. Preserves /mnt/nextclouddata (user files)
# and all .env config files and docker-compose.yml. Two separate confirmations.
_mod_setup_reset_stack() {
    # Define environment file paths for use throughout this function
    local _root _db_env _oo_env
    # BASH_SOURCE[0] = lib/install/reset_stack.sh → ../../../../ = repo root
    _root="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
    _db_env="${_root}/secrets/db.env"
    _oo_env="${_root}/secrets/onlyoffice.env"

    # Export for use in this function and called functions
    export DB_ENV="$_db_env"
    export OO_ENV="$_oo_env"

    header
    breadcrumb "Igor" "S: Setup & Infra" "5: Reset Stack"

    local nc_data="${NC_DATA:-/mnt/nextclouddata/next}"
    local data_size; data_size=$(du -sh "$nc_data" 2>/dev/null | cut -f1 || echo "unknown")

    echo -e "  ${RED}${BOLD}⚠  RESET STACK${NC}"
    echo ""
    echo "  This will:"
    echo -e "  ${RED}DESTROY${NC}  all containers (app, db, redis, web, cron)"
    echo -e "  ${RED}DESTROY${NC}  all named volumes (nextcloud_db, nextcloud_nextcloud, etc.)"
    echo -e "  ${RED}DESTROY${NC}  built images"
    echo -e "  ${YEL}KEEP${NC}     ${nc_data}  (your files — ${data_size} — never touched)"
    echo -e "  ${YEL}KEEP${NC}     all .env config files"
    echo -e "  ${YEL}KEEP${NC}     docker-compose.yml"
    echo ""
    echo "  Your user files on the external drive will NOT be affected."
    echo ""

    # ── Pre-flight checks ──────────────────────────────────────────────────────
    step "Checking current state"
    [ -d "$nc_data" ]        && ok "Data directory: ${nc_data} (${data_size})" \
                              || warn "Data directory not found: ${nc_data}"
    [ -f "${DB_ENV}" ]       && ok "Credentials: ${DB_ENV} present" \
                              || warn "Credentials: ${DB_ENV} missing — will need reconfiguration"
    [ -f "${COMPOSE_FILE}" ] && ok "Stack config: ${COMPOSE_FILE} present" \
                              || warn "Stack config: ${COMPOSE_FILE} missing"
    echo ""

    local _confirm
    read -rp "  Type RESET to confirm stopping containers: " _confirm
    [ "$_confirm" != "RESET" ] && { warn "Aborted — nothing changed."; pause; return; }

    # ── Stop containers ────────────────────────────────────────────────────────
    step "Stopping containers"
    nextcloud_docker__compose down --remove-orphans 2>/dev/null || true
    ok "Containers stopped."
    echo ""

    # ── List volumes to remove ─────────────────────────────────────────────────
    step "Named volumes to remove"
    local vols=()
    local _v
    while IFS= read -r _v; do
        [[ "$_v" =~ ^nextcloud_ ]] && vols+=("$_v")
    done < <(docker volume ls -q 2>/dev/null)

    if [ ${#vols[@]} -eq 0 ]; then
        info "No nextcloud_* volumes found — stack may already be clean."
        pause; return
    fi

    echo ""
    for _v in "${vols[@]}"; do
        local _sz; _sz=$(docker volume inspect "$_v" --format '{{.Mountpoint}}' 2>/dev/null \
            | xargs du -sh 2>/dev/null | cut -f1 || echo "?")
        printf "  ${YEL}%-40s${NC} %s\n" "$_v" "(${_sz})"
    done
    echo ""

    local _confirm2
    read -rp "  Type DELETE to confirm volume removal: " _confirm2
    [ "$_confirm2" != "DELETE" ] && { warn "Volume deletion cancelled — containers remain stopped."; pause; return; }

    for _v in "${vols[@]}"; do
        docker volume rm "$_v" 2>/dev/null && ok "Removed: ${_v}" || warn "Could not remove: ${_v}"
    done

    # ── Clean images ───────────────────────────────────────────────────────────
    step "Removing built images"
    docker image rm "$(docker images -q 'nextcloud*' 2>/dev/null)" 2>/dev/null || true
    ok "Stack reset complete."
    echo ""
    echo "  Your user files at ${nc_data} (${data_size}) are intact."
    echo ""
    echo -e "  ${CYAN}Next step: S→0 WIZARD${NC}"
    echo "  The wizard will:"
    echo "    • Detect your existing user data and offer to back it up or keep it"
    echo "    • Run a clean Nextcloud install with your saved credentials"
    echo "    • Guide you through files:scan to reconnect NC to your files"
    echo ""
    if confirm "Run WIZARD now?"; then
        menu_install
    else
        echo ""
        info "Come back later: Igor → S → 0. WIZARD"
        pause
    fi
}
