#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/lib/install/migrate.sh
#  Adopt an existing Nextcloud Docker setup into Igor management.
#
#  Sourced by modules/nextcloud_docker/install.sh.
# ==============================================================================

# ── Discovery helpers ─────────────────────────────────────────────────────────

# Find the docker-compose.yml of a running Nextcloud stack.
# Tries container labels first, then walks up from common config locations.
_mod_migrate_find_compose() {
    # 1. Ask Docker for the compose project directory via container label
    local _dir
    _dir=$(docker inspect \
        --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' \
        "$(docker ps --filter "name=nextcloud" --format '{{.Names}}' 2>/dev/null | head -1)" \
        2>/dev/null)
    if [ -n "$_dir" ] && [ -f "${_dir}/docker-compose.yml" ]; then
        echo "${_dir}/docker-compose.yml"; return 0
    fi
    if [ -n "$_dir" ] && [ -f "${_dir}/docker-compose.yaml" ]; then
        echo "${_dir}/docker-compose.yaml"; return 0
    fi

    # 2. Common installation paths
    local _candidate
    for _candidate in \
        /opt/nextcloud/docker-compose.yml \
        /srv/nextcloud/docker-compose.yml \
        /home/*/nextcloud/docker-compose.yml \
        ~/nextcloud/docker-compose.yml; do
        [ -f "$_candidate" ] && { echo "$_candidate"; return 0; }
    done

    return 1
}

# Extract a value from a docker-compose.yml or env file.
# Usage: _mod_migrate_extract_env KEY [file...]
_mod_migrate_extract_env() {
    local _key="$1"; shift
    local _file _val
    for _file in "$@"; do
        [ -f "$_file" ] || continue
        _val=$(grep -m1 "^[[:space:]]*${_key}[[:space:]]*=" "$_file" 2>/dev/null \
            | sed 's/^[^=]*=[ "'\'']*//; s/[ "'\'']*$//')
        [ -n "$_val" ] && { echo "$_val"; return 0; }
    done
    return 1
}

# Find env files declared in a compose file (env_file: sections).
_mod_migrate_find_env_files() {
    local _compose="$1"
    local _dir; _dir="$(dirname "$_compose")"
    grep -o 'env_file:[^#]*' "$_compose" 2>/dev/null \
        | grep -o '[^:space:][^ #]*\.env[^ #]*' \
        | while read -r _f; do
            # Resolve relative paths against compose dir
            case "$_f" in
                /*) echo "$_f" ;;
                *)  echo "${_dir}/${_f}" ;;
            esac
        done
}

# Extract Nextcloud HTTP port from port mapping in compose file.
_mod_migrate_find_port() {
    local _compose="$1"
    grep -o '"[0-9]*:80"' "$_compose" 2>/dev/null | head -1 | tr -d '"' | cut -d: -f1
}

# Find the Nextcloud data directory from a running container's mounts.
_mod_migrate_find_data_dir() {
    local _cname
    _cname=$(docker ps --filter "name=nextcloud" --format '{{.Names}}' 2>/dev/null \
        | grep -E "app|nextcloud" | head -1)
    [ -z "$_cname" ] && return 1
    docker inspect --format \
        '{{range .Mounts}}{{if eq .Destination "/var/www/html/data"}}{{.Source}}{{end}}{{end}}' \
        "$_cname" 2>/dev/null | grep -v '^$' | head -1
}

# ── Interactive confirm helper ────────────────────────────────────────────────
# _mod_migrate_ask LABEL CURRENT_VALUE [hint]
# Prints prompt, reads input. Empty input = keep current. Echoes final value.
_mod_migrate_ask() {
    local _label="$1" _current="$2" _hint="${3:-}"
    local _display="${_current:-<not found>}"
    echo ""
    echo -e "  ${CYAN}${_label}${NC}"
    [ -n "$_hint" ] && echo -e "  ${DIM}${_hint}${NC}"
    echo -e "  Detected: ${YEL}${_display}${NC}"
    echo -ne "  Accept, or type a new value [Enter = accept]: "
    local _input
    IFS= read -r _input
    if [ -z "$_input" ]; then
        echo "$_current"
    else
        echo "$_input"
    fi
}

# ── Write helpers ─────────────────────────────────────────────────────────────

# Upsert a KEY=VALUE line in a file.  Creates the file if absent.
_mod_migrate_upsert() {
    local _file="$1" _key="$2" _val="$3"
    if grep -q "^${_key}=" "$_file" 2>/dev/null; then
        sed -i "s|^${_key}=.*|${_key}=${_val}|" "$_file"
    else
        echo "${_key}=${_val}" >> "$_file"
    fi
}

# ── Main entry point ──────────────────────────────────────────────────────────

_mod_setup_migrate() {
    local _root="${IGOR_DIR}"
    local _db_env="${_root}/secrets/db.env"
    local _site_env="${_root}/secrets/site.env"
    local _nc_env="${_root}/config/variables/nextcloud.env"
    local _stacks_dir="${IGOR_STACKS:-${_root}/config/stacks}/nextcloud"

    header
    breadcrumb "Igor" "S: Setup & Infra" "8: Adopt Existing Stack"
    echo -e "  ${YEL}${BOLD}[8] Adopt Existing Nextcloud Stack${NC}"
    echo ""
    echo "  This wizard discovers your existing Nextcloud Docker setup and"
    echo "  imports its configuration so Igor can manage it."
    echo ""
    echo -e "  ${DIM}Your data and containers are not touched — only config files are written.${NC}"
    echo ""

    # ── Phase 1: Discover ────────────────────────────────────────────────────
    step "Discovering existing setup..."
    echo ""

    local _compose _compose_dir
    if _compose=$(_mod_migrate_find_compose); then
        _compose_dir="$(dirname "$_compose")"
        ok "Found compose file: ${_compose}"
    else
        warn "No running Nextcloud containers found and no compose file detected."
        echo ""
        echo "  Make sure your existing stack is running, then try again."
        echo "  Or enter the path to your docker-compose.yml manually."
        echo ""
        echo -ne "  Path to docker-compose.yml [Enter to cancel]: "
        IFS= read -r _compose
        if [ -z "$_compose" ] || [ ! -f "$_compose" ]; then
            info "Adoption cancelled."
            pause; return
        fi
        _compose_dir="$(dirname "$_compose")"
    fi

    # Collect env files referenced by the compose file
    local -a _env_files=()
    while IFS= read -r _ef; do
        [ -f "$_ef" ] && _env_files+=("$_ef")
    done < <(_mod_migrate_find_env_files "$_compose")
    # Also check sibling .env files in the compose directory
    for _f in "${_compose_dir}/.env" "${_compose_dir}/nextcloud.env" \
               "${_compose_dir}/db.env" "${_compose_dir}/app.env"; do
        [ -f "$_f" ] && _env_files+=("$_f")
    done

    # ── Phase 2: Extract values ──────────────────────────────────────────────
    local _d_pg_user _d_pg_pass _d_pg_db _d_nc_admin _d_nc_pass
    local _d_domain _d_port _d_data_dir _d_install_dir _d_nc_user

    _d_pg_user=$(_mod_migrate_extract_env "POSTGRES_USER"          "${_env_files[@]}" "$_compose" || true)
    _d_pg_pass=$(_mod_migrate_extract_env "POSTGRES_PASSWORD"      "${_env_files[@]}" "$_compose" || true)
    _d_pg_db=$(_mod_migrate_extract_env   "POSTGRES_DB"            "${_env_files[@]}" "$_compose" || true)
    _d_nc_admin=$(_mod_migrate_extract_env "NEXTCLOUD_ADMIN_USER"  "${_env_files[@]}" "$_compose" || true)
    _d_nc_pass=$(_mod_migrate_extract_env  "NEXTCLOUD_ADMIN_PASSWORD" "${_env_files[@]}" "$_compose" || true)
    _d_domain=$(_mod_migrate_extract_env   "NEXTCLOUD_TRUSTED_DOMAINS" "${_env_files[@]}" "$_compose" || true)
    _d_port=$(_mod_migrate_find_port "$_compose" || true)
    _d_port="${_d_port:-8080}"
    _d_data_dir=$(_mod_migrate_find_data_dir || true)
    _d_install_dir="$_compose_dir"
    _d_nc_user=$(stat -c '%U' "${_d_data_dir}" 2>/dev/null || echo "")

    # ── Phase 3: Interactive confirmation ───────────────────────────────────
    echo ""
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────${NC}"
    echo -e "  Review each value. Press Enter to accept, or type a replacement."
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────${NC}"

    echo ""
    echo -e "  ${BOLD}── Stack location ──${NC}"
    _d_install_dir=$(_mod_migrate_ask \
        "Install directory (compose project root)" \
        "$_d_install_dir")
    _d_data_dir=$(_mod_migrate_ask \
        "Nextcloud data directory (host path of /var/www/html/data)" \
        "$_d_data_dir" \
        "Where user files are stored on the host")

    echo ""
    echo -e "  ${BOLD}── Database credentials ──${NC}"
    _d_pg_user=$(_mod_migrate_ask "POSTGRES_USER"     "$_d_pg_user")
    _d_pg_pass=$(_mod_migrate_ask "POSTGRES_PASSWORD" "$_d_pg_pass")
    _d_pg_db=$(_mod_migrate_ask   "POSTGRES_DB"       "${_d_pg_db:-nextcloud}")

    echo ""
    echo -e "  ${BOLD}── Nextcloud admin account ──${NC}"
    _d_nc_admin=$(_mod_migrate_ask "Admin username"    "${_d_nc_admin:-admin}")
    _d_nc_pass=$(_mod_migrate_ask  "Admin password"    "$_d_nc_pass" \
        "Leave blank to skip (Igor will not overwrite an existing password)")

    echo ""
    echo -e "  ${BOLD}── Public access ──${NC}"
    _d_domain=$(_mod_migrate_ask "Domain / trusted domain" \
        "$_d_domain" "Your public hostname, e.g. cloud.example.com")
    _d_port=$(_mod_migrate_ask   "HTTP port (host-side)" \
        "$_d_port" "The port mapped to Nextcloud's web container on this host")

    echo ""
    echo -e "  ${BOLD}── Linux owner ──${NC}"
    _d_nc_user=$(_mod_migrate_ask "Linux user that owns the data directory" \
        "${_d_nc_user:-$(whoami)}")

    # ── Confirm before writing ───────────────────────────────────────────────
    echo ""
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}About to write:${NC}"
    printf "    %-38s %s\n" "secrets/db.env"                  "DB + admin credentials"
    printf "    %-38s %s\n" "secrets/site.env"                "domain, paths, user"
    printf "    %-38s %s\n" "config/variables/nextcloud.env"  "port, container names"
    [ -f "$_compose" ] && \
        printf "    %-38s %s\n" "config/stacks/nextcloud/" "copy of docker-compose.yml"
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────${NC}"
    echo ""
    confirm "Write these values now?" || { info "Adoption cancelled."; pause; return; }

    # ── Phase 4: Write ───────────────────────────────────────────────────────
    step "Writing configuration..."

    # secrets/db.env
    mkdir -p "${_root}/secrets" 2>/dev/null || true
    if [ ! -f "$_db_env" ] && [ -f "${_db_env}.example" ]; then
        cp "${_db_env}.example" "$_db_env"
    fi
    touch "$_db_env"
    chmod 600 "$_db_env"
    _mod_migrate_upsert "$_db_env" "POSTGRES_USER"               "$_d_pg_user"
    _mod_migrate_upsert "$_db_env" "POSTGRES_PASSWORD"           "$_d_pg_pass"
    _mod_migrate_upsert "$_db_env" "POSTGRES_DB"                 "$_d_pg_db"
    _mod_migrate_upsert "$_db_env" "NEXTCLOUD_ADMIN_USER"        "$_d_nc_admin"
    [ -n "$_d_nc_pass" ] && \
        _mod_migrate_upsert "$_db_env" "NEXTCLOUD_ADMIN_PASSWORD" "$_d_nc_pass"
    [ -n "$_d_domain" ] && \
        _mod_migrate_upsert "$_db_env" "NEXTCLOUD_TRUSTED_DOMAINS" "$_d_domain"
    ok "Written: secrets/db.env"

    # secrets/site.env
    if [ ! -f "$_site_env" ] && [ -f "${_site_env}.example" ]; then
        cp "${_site_env}.example" "$_site_env"
    fi
    touch "$_site_env"
    chmod 600 "$_site_env"
    [ -n "$_d_install_dir" ] && \
        _mod_migrate_upsert "$_site_env" "INSTALL_DIR"   "$_d_install_dir"
    [ -n "$_d_data_dir" ] && \
        _mod_migrate_upsert "$_site_env" "NC_DATA"       "$_d_data_dir"
    [ -n "$_d_data_dir" ] && \
        _mod_migrate_upsert "$_site_env" "HD_MOUNT"      "$(dirname "$_d_data_dir")"
    [ -n "$_d_domain" ] && \
        _mod_migrate_upsert "$_site_env" "DOMAIN"        "$_d_domain"
    [ -n "$_d_nc_user" ] && \
        _mod_migrate_upsert "$_site_env" "NC_USER_NAME"  "$_d_nc_user"
    ok "Written: secrets/site.env"

    # config/variables/nextcloud.env — only the port, leave everything else
    _mod_migrate_upsert "$_nc_env" "NEXTCLOUD_HTTP_PORT" "$_d_port"
    ok "Updated: config/variables/nextcloud.env  (HTTP port → ${_d_port})"

    # Copy compose file into Igor's stacks directory
    if [ -f "$_compose" ]; then
        mkdir -p "$_stacks_dir" 2>/dev/null || true
        local _target_compose="${_stacks_dir}/docker-compose.yml"
        if [ -f "$_target_compose" ]; then
            cp "$_target_compose" "${_target_compose}.pre-adopt.bak" 2>/dev/null || true
            info "Backed up existing compose file → docker-compose.yml.pre-adopt.bak"
        fi
        cp "$_compose" "$_target_compose"
        ok "Copied compose file → config/stacks/nextcloud/docker-compose.yml"
    fi

    # ── Phase 5: Quick verify ────────────────────────────────────────────────
    echo ""
    step "Verifying Igor can reach the stack..."
    local _http_code
    _http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        "http://localhost:${_d_port}/status.php" 2>/dev/null || echo "000")

    if [ "$_http_code" = "200" ]; then
        ok "HTTP ${_http_code} — Nextcloud is reachable on port ${_d_port}"
    elif [ "$_http_code" = "503" ]; then
        warn "HTTP 503 — Nextcloud is in maintenance mode (that's OK for now)"
    else
        warn "HTTP ${_http_code} — could not reach Nextcloud on port ${_d_port}"
        info "Check the port and that containers are running, then use [2] SERVICES."
    fi

    echo ""
    ok "Adoption complete. Igor is now managing this Nextcloud stack."
    echo ""
    echo "  Next steps:"
    echo "    [1] STATUS     — verify Igor sees the stack correctly"
    echo "    [6] DIAGNOSE   — run a full health check"
    echo ""
    pause
}
