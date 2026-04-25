#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/lib/install/start_stack.sh
#  Start the Docker stack using existing volumes (no data loss).
#
#  Sourced by modules/nextcloud_docker/install.sh.
# ==============================================================================

# ── _mod_setup_start_stack ────────────────────────────────────────────────────
# Starts services using existing volumes and config — no data is touched.
# Useful when moving to a new Pi, new folder, or after a manual docker stop.
_mod_setup_start_stack() {
    # Define environment file paths for use throughout this function
    local _root _db_env _oo_env
    # BASH_SOURCE[0] = lib/install/start_stack.sh → ../../../../ = repo root
    _root="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
    _db_env="${_root}/secrets/db.env"
    _oo_env="${_root}/secrets/onlyoffice.env"

    # Export for use in this function and called functions
    export DB_ENV="$_db_env"
    export OO_ENV="$_oo_env"

    # Load tier defaults + any user overrides
    _mod_install_load_tier

    header
    breadcrumb "Igor" "S: Setup & Infra" "4: Start Stack"
    echo -e "  ${CYAN}${BOLD}[4] Start Stack — Keep All Data${NC}"
    echo ""
    echo "  Starts all containers using your existing volumes and credentials."
    echo "  Nothing is wiped. Your Nextcloud data and database are untouched."
    echo ""

    # ── Prerequisites ──────────────────────────────────────────────────────────
    step "Checking prerequisites"
    local abort=false
    command -v docker &>/dev/null       || { fail "Docker not installed — run S→1 DOCKER first."; abort=true; }
    if ! docker info &>/dev/null; then
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
    [ -f "${COMPOSE_FILE}" ]            || { fail "docker-compose.yml not found at ${COMPOSE_FILE}"; abort=true; }
    [ -f "${IGOR_DIR}/secrets/db.env" ] || { fail "secrets/db.env missing — run S→0 WIZARD first."; abort=true; }
    $abort && { warn "Fix the issues above and re-run."; pause; return 1; }
    ok "Prerequisites OK."

    # ── Show what volumes exist ────────────────────────────────────────────────
    step "Named volumes"
    local _found=0 _v
    for _v in nextcloud_db nextcloud_nextcloud; do
        if docker volume inspect "$_v" &>/dev/null; then
            local _sz; _sz=$(docker volume inspect "$_v" --format '{{.Mountpoint}}' 2>/dev/null \
                | xargs du -sh 2>/dev/null | cut -f1 || echo "?")
            ok "${_v}  (${_sz})"
            _found=$((_found + 1))
        else
            info "${_v}  — not found, will be created on first start"
        fi
    done

    # No existing volumes at all — need to distinguish fresh-machine vs post-reset
    if [[ "$_found" -eq 0 ]]; then
        echo ""
        warn "No existing Nextcloud volumes found."
        echo ""

        # ── Check if user data exists at NC_DATA ──────────────────────────────
        # NC's auto-install (occ maintenance:install) refuses to run when the
        # data directory already contains user files from a previous install.
        # Only the WIZARD handles this correctly via _mod_install_handle_existing_data.
        local _data_fresh="${NC_DATA:-/mnt/nextclouddata/next}"
        local _nc_uid="${NC_UID:-1004}"
        local _has_user_data=false

        if [ -d "$_data_fresh" ]; then
            # Look for any user-owned subdirectory (excluding NC-internal dirs)
            local _d
            for _d in "${_data_fresh}"/*/; do
                [ -d "$_d" ] || continue
                local _dname; _dname=$(basename "$_d")
                case "$_dname" in appdata_*|updater-*|__groupfolders|cache|.ocdata) continue ;; esac
                _has_user_data=true; break
            done
        fi

        if $_has_user_data; then
            echo -e "  ${YEL}${BOLD}Existing user data detected at ${_data_fresh}${NC}"
            echo ""
            echo "  Nextcloud's auto-installer refuses to run when the data directory"
            echo "  already has files — it would show the manual setup wizard."
            echo ""
            echo "  The correct path is S→0 WIZARD which will:"
            echo "    • Let you back up or keep the existing user folders"
            echo "    • Run a clean Nextcloud install"
            echo "    • Leave your files intact for a post-install files:scan"
            echo ""
            confirm "Go to WIZARD now?" && { menu_install; return; }
            warn "Continuing anyway — NC entrypoint will likely show the install wizard."
            echo ""
        else
            # Truly clean data dir — ownership check before entrypoint runs
            if [ -d "$_data_fresh" ]; then
                local _owner; _owner=$(stat -c '%u' "$_data_fresh" 2>/dev/null || echo "?")
                if [[ "$_owner" != "$_nc_uid" ]]; then
                    warn "Data directory owned by UID ${_owner}, Nextcloud needs UID ${_nc_uid}."
                    if confirm "Fix ownership now? (sudo chown ${_nc_uid}:${_nc_uid} ${_data_fresh})"; then
                        if chown -R "${_nc_uid}:${_nc_uid}" "$_data_fresh" 2>/dev/null; then
                            ok "Ownership fixed: ${_data_fresh}"
                        elif sudo chown -R "${_nc_uid}:${_nc_uid}" "$_data_fresh" 2>/dev/null; then
                            ok "Ownership fixed (via sudo): ${_data_fresh}"
                        else
                            fail "chown failed — try manually: sudo chown -R ${_nc_uid}:${_nc_uid} ${_data_fresh}"
                        fi
                    fi
                    echo ""
                fi
            fi
            echo "  Nextcloud will install from scratch on first start."
            echo ""
        fi
        confirm "Start containers?" || { pause; return; }
    fi
    echo ""

    # ── Data directory ─────────────────────────────────────────────────────────
    local _data="${NC_DATA:-/mnt/nextclouddata/next}"
    if [ -d "$_data" ]; then
        local _dsz; _dsz=$(du -sh "$_data" 2>/dev/null | cut -f1 || echo "?")
        ok "User data: ${_data}  (${_dsz})"
    else
        warn "User data dir not found: ${_data} — mount the external HD first (S→2 STORAGE)"
    fi
    echo ""

    # ── Prune stale networks that would block startup ──────────────────────────
    # A previous install with a different project name leaves its network behind
    # with the same subnet. Docker refuses to create a new network overlapping it.
    local _stale_nets
    _stale_nets=$(docker network ls --format '{{.Name}}' 2>/dev/null \
        | grep -E "_nextcloud_network$" | grep -v "^nextcloud_nextcloud_network$" || true)
    if [[ -n "$_stale_nets" ]]; then
        warn "Stale Docker networks from previous installations detected:"
        echo "$_stale_nets" | while read -r _n; do printf "    %s\n" "$_n"; done
        echo ""
        if confirm "Remove stale networks? (safe — only removes unused ones)"; then
            echo "$_stale_nets" | while read -r _n; do
                docker network rm "$_n" 2>/dev/null && ok "Removed: ${_n}" || \
                    warn "Could not remove ${_n} — may still be in use"
            done
        fi
        echo ""
    fi

    confirm "Start services now?" || { pause; return; }

    # ── Start ──────────────────────────────────────────────────────────────────
    step "Starting Docker stack"
    if ! nextcloud_docker__compose up -d; then
        echo ""
        fail "Docker Compose failed to start."
        echo ""
        echo "  Common causes:"
        echo "  • Network subnet conflict  — run S→7 ORPHAN CLEANUP to prune old networks"
        echo "  • Port 8080 already in use — check: sudo ss -tlnp | grep 8080"
        echo "  • secrets/db.env missing   — run S→0 WIZARD"
        echo ""
        echo "  Full logs: nextcloud_docker__compose logs --tail=40"
        pause; return 1
    fi
    echo ""

    # ── Health check ──────────────────────────────────────────────────────────
    local http_port="${NEXTCLOUD_HTTP_PORT:-8080}"
    if [[ "$_found" -eq 0 ]]; then
        # Fresh install — Nextcloud entrypoint needs 3-5 min on Pi 3
        step "Waiting for Nextcloud entrypoint to install (3-5 min on Pi 3)"
        info "Please wait — this is a fresh install, not a restart..."
        local _waited=0 _max_wait=480
        while [ $_waited -lt $_max_wait ]; do
            nextcloud_docker__compose logs app 2>/dev/null | grep -q "fpm is running" && break
            sleep 5; _waited=$((_waited + 5)); printf "."
        done
        echo ""
        [ $_waited -ge $_max_wait ] && warn "Timed out waiting for FPM — continuing anyway."
        sleep 5

        step "Verifying Nextcloud installation"
        local _is_installed="" _vtries=0
        while [ $_vtries -lt 12 ]; do
            _is_installed=$(nextcloud_docker__compose exec -T -u www-data app php occ status 2>/dev/null \
                | grep "installed:" | awk '{print $2}' | tr -d '[:space:]')
            [ "$_is_installed" = "true" ] && break
            info "Not ready yet — waiting 15s... $((_vtries + 1))/12"
            sleep 15; _vtries=$((_vtries + 1))
        done

        if [ "$_is_installed" = "true" ]; then
            ok "Nextcloud installed successfully."
        else
            # HTTP fallback — but status.php returns 200 even when installed=false
            # (the setup wizard page). Must check the JSON body.
            local _status_json; _status_json=$(curl -s --max-time 10 \
                "http://localhost:${http_port}/status.php" 2>/dev/null)
            if echo "$_status_json" | grep -q '"installed":true'; then
                ok "Nextcloud installed and responding."
            elif echo "$_status_json" | grep -q '"installed":false'; then
                fail "Nextcloud entrypoint did not auto-install."
                echo ""
                echo "  Most likely cause: data directory already has user files."
                echo "  NC's occ maintenance:install refuses to run on a non-empty data dir."
                echo ""
                echo "  Fix: use S→0 WIZARD — it handles existing data correctly."
                info "Container logs: nextcloud_docker__compose logs app --tail=50"
                pause; return 1
            else
                fail "Nextcloud did not respond on port ${http_port}."
                info "Check: nextcloud_docker__compose logs --tail=40"
                pause; return 1
            fi
        fi

        # ── Post-install: offer scan + previews for existing user data ─────────
        local _data_post="${NC_DATA:-/mnt/nextclouddata/next}"
        local _data_sz; _data_sz=$(du -sh "$_data_post" 2>/dev/null | cut -f1 || echo "?")
        if [ -d "$_data_post" ] && [ "$_data_sz" != "?" ] && [[ "$_data_sz" != "0"* ]]; then
            echo ""
            info "Existing user data detected at ${_data_post} (${_data_sz})."
            echo "  Nextcloud won't show your files until the file cache is rebuilt."
            echo ""
            if confirm "Scan files now? (rebuilds NC file cache — may be slow)"; then
                step "Scanning files"
                nextcloud_docker__compose exec -T -u www-data app php occ files:scan --all \
                    && ok "File scan complete." || warn "files:scan returned non-zero"
                echo ""
            fi
            if confirm "Generate thumbnails now? (slow on Pi 3 — can skip and do later via 5. MAINTENANCE)"; then
                step "Generating previews (Pi 3 optimized: 1024x1024)"
                nextcloud_docker__compose exec -T -u www-data app php occ preview:generate-all \
                    && ok "Previews generated." || warn "preview:generate-all returned non-zero"
                echo ""
            fi
        fi
    else
        # Existing data — short wait, containers just need to restart
        step "Waiting for Nextcloud to respond (up to 60s)"
        local _tries=0
        while [ $_tries -lt 12 ]; do
            local _hc; _hc=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
                "http://localhost:${http_port}/status.php" 2>/dev/null)
            if [ "$_hc" = "200" ]; then
                ok "Nextcloud is responding (HTTP 200)."
                break
            fi
            printf "."; sleep 5; _tries=$((_tries + 1))
        done
        echo ""
        if [ $_tries -ge 12 ]; then
            warn "No HTTP 200 after 60s — Nextcloud may still be starting."
            info "Check: nextcloud_docker__compose logs app --tail=30"
        fi
    fi

    ok "Done. Use 4. SERVICES to manage containers."
    pause
}
