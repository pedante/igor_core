#!/bin/bash
# =============================================================================
#  IGOR — modules/nextcloud_docker/menus/recovery.sh
#  Backup and restore hooks for the module hook registry.
#
#  Registered via nextcloud_docker__register() in module.sh:
#    igor_register_hook "backup"  "nextcloud_docker__backup"
#    igor_register_hook "restore" "nextcloud_docker__restore"
#
#  Called by core/recovery/full_backup.sh:
#    igor_run_all_hooks "backup"  "$snapshot_dir"
#    igor_run_all_hooks "restore" "$snapshot_dir"
#
#  Each function drops its data into:
#    $snapshot_dir/modules/nextcloud_docker/
# =============================================================================

# ── nextcloud_docker__backup SNAPSHOT_DIR ─────────────────────────────────────
# Backup hook. Called by core full_backup_take() via igor_run_all_hooks "backup".
# Captures NC-specific state into $snapshot_dir/modules/nextcloud_docker/.
nextcloud_docker__backup() {
    local snapshot_dir="${1:-}"
    local module_name="nextcloud_docker"
    local dest="${snapshot_dir}/modules/${module_name}"

    [ -z "$snapshot_dir" ] && { echo "nextcloud_docker__backup: missing snapshot_dir" >&2; return 1; }
    mkdir -p "$dest"

    local GRN='\033[0;32m' YEL='\033[1;33m' NC='\033[0m'

    # Resolve compose file — try module stack_dir first, then common locations
    local _compose_file="${NEXTCLOUD_DOCKER_STACK_DIR:+${NEXTCLOUD_DOCKER_STACK_DIR}/docker-compose.yml}"
    for _cf in "$_compose_file" \
               "${IGOR_DIR}/config/stacks/nextcloud/docker-compose.yml" \
               "${IGOR_DIR}/docker-compose.yml"; do
        [ -f "$_cf" ] && { _compose_file="$_cf"; break; }
    done

    _ncd_backup_run_occ() {
        local args=("$@")
        docker compose ${_compose_file:+-f "$_compose_file"} \
            exec -T -u www-data app php occ "${args[@]}" 2>/dev/null
    }

    # ── 1. occ config:system:export ──────────────────────────────────────────
    if _ncd_backup_run_occ config:system:export > "${dest}/nc_config.json"; then
        echo -e "  ${GRN}✔${NC} NC config exported"
    else
        rm -f "${dest}/nc_config.json" 2>/dev/null
        echo -e "  ${YEL}!${NC} NC config export skipped (NC may not be running)"
    fi

    # ── 2. occ app:list ───────────────────────────────────────────────────────
    if _ncd_backup_run_occ app:list --output=json > "${dest}/app_list.json"; then
        echo -e "  ${GRN}✔${NC} App list captured"
    else
        rm -f "${dest}/app_list.json" 2>/dev/null
    fi

    # ── 3. docker-compose.yml + override ──────────────────────────────────────
    local _stack_dir; _stack_dir=$(dirname "$_compose_file" 2>/dev/null)
    for _cf in docker-compose.yml docker-compose.override.yml; do
        [ -f "${_stack_dir}/${_cf}" ] && \
            cp "${_stack_dir}/${_cf}" "${dest}/${_cf}" 2>/dev/null && \
            echo -e "  ${GRN}✔${NC} ${_cf} captured" || true
    done

    # ── 4. Dockerfile ─────────────────────────────────────────────────────────
    for _df in "${_stack_dir}/Dockerfile" "${IGOR_DIR}/Dockerfile"; do
        [ -f "$_df" ] && cp "$_df" "${dest}/Dockerfile" 2>/dev/null && \
            echo -e "  ${GRN}✔${NC} Dockerfile captured" && break || true
    done

    # ── 5. nginx.conf ─────────────────────────────────────────────────────────
    for _nc in "${_stack_dir}/nginx.conf" \
               "${IGOR_DIR}/web/nginx.conf"; do
        [ -f "$_nc" ] && cp "$_nc" "${dest}/nginx.conf" 2>/dev/null && \
            echo -e "  ${GRN}✔${NC} nginx.conf captured" && break || true
    done

    # ── 6. db.env ─────────────────────────────────────────────────────────────
    local _db_env="${DB_ENV:-${IGOR_DIR}/secrets/db.env}"
    [ -f "$_db_env" ] && cp "$_db_env" "${dest}/db.env" 2>/dev/null && \
        echo -e "  ${GRN}✔${NC} db.env captured" || true

    # ── 7. PostgreSQL dump ────────────────────────────────────────────────────
    _ncd_backup_pg_dump "$dest" "$_compose_file"

    # ── 8. Rebuild script ─────────────────────────────────────────────────────
    _ncd_backup_rebuild_script "$dest" "$_compose_file"

    unset -f _ncd_backup_run_occ
    echo -e "  ${GRN}✔${NC} nextcloud_docker backup complete"
}

# ── _ncd_backup_pg_dump DEST COMPOSE_FILE ────────────────────────────────────
_ncd_backup_pg_dump() {
    local dest="$1" compose_file="${2:-}"
    local dump_file="${dest}/db_dump.sql.gz"
    local YEL='\033[1;33m' GRN='\033[0;32m' NC='\033[0m'

    local db_mb; db_mb=$(docker compose ${compose_file:+-f "$compose_file"} exec -T db psql \
        -U "${POSTGRES_USER:-nextcloud}" -d "${POSTGRES_DB:-nextcloud}" \
        -tAc "SELECT pg_database_size(current_database()) / 1048576;" \
        2>/dev/null | tr -d '[:space:]') || true
    db_mb=${db_mb:-0}; [[ "$db_mb" =~ ^[0-9]+$ ]] || db_mb=0

    local free_mb; free_mb=$(df -m "$dest" 2>/dev/null | awk 'NR==2{print $4}' || echo 9999)
    local needed_mb=$(( db_mb + db_mb / 2 + 50 ))

    if [[ "$free_mb" =~ ^[0-9]+$ ]] && [ "$free_mb" -lt "$needed_mb" ] 2>/dev/null; then
        echo -e "  ${YEL}!${NC} Insufficient space for pg_dump (need ${needed_mb}MB, have ${free_mb}MB) — skipping"
        return 0
    fi

    echo -e "  Dumping PostgreSQL (~${db_mb}MB)..."
    docker compose ${compose_file:+-f "$compose_file"} exec -T db pg_dump \
        -U "${POSTGRES_USER:-nextcloud}" -d "${POSTGRES_DB:-nextcloud}" \
        | gzip -9 > "$dump_file" 2>/dev/null
    local rc=$?

    if [ $rc -ne 0 ] || [ ! -s "$dump_file" ]; then
        rm -f "$dump_file" 2>/dev/null
        echo -e "  ${YEL}!${NC} pg_dump failed (exit $rc) — skipping"
        return 0
    fi

    local sz; sz=$(du -sh "$dump_file" 2>/dev/null | cut -f1)
    echo -e "  ${GRN}✔${NC} DB dump: ${sz}"

    declare -f journal_record &>/dev/null && \
        journal_record "menu:recovery" "db_backup" "AUTO" \
            "pg_dump ${POSTGRES_DB:-nextcloud}" "OK" "size:${sz}" 2>/dev/null || true
}

# ── _ncd_backup_rebuild_script DEST COMPOSE_FILE ─────────────────────────────
_ncd_backup_rebuild_script() {
    local dest="$1" compose_file="${2:-}"
    local out="${dest}/rebuild.sh"

    local _dc="docker compose ${compose_file:+-f "$compose_file"}"

    local nc_ver; nc_ver=$($_dc exec -T -u www-data app php occ status --output=json \
        2>/dev/null | python3 -c "import json,sys; \
        d=json.load(sys.stdin); print(d.get('versionstring','unknown'))" 2>/dev/null \
        || echo "unknown")

    local trusted_domain; trusted_domain=$($_dc exec -T -u www-data app \
        php occ config:system:get trusted_domains 1 2>/dev/null | tr -d '[:space:]') || \
        trusted_domain="${NEXTCLOUD_TRUSTED_DOMAINS:-your.domain.here}"

    local app_list; app_list=$($_dc exec -T -u www-data app php occ app:list \
        --output=json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(' '.join(sorted(d.get('enabled',{}).keys())))" 2>/dev/null || echo "")

    cat > "$out" <<REBUILD_SCRIPT
#!/bin/bash
# IGOR — Nextcloud Rebuild Script
# Generated: $(date "+%Y-%m-%d %H:%M:%S")
# Nextcloud: ${nc_ver}
# Domain:    ${trusted_domain}
#
# Brings a fresh Pi OS install to the state at backup time.
# IDEMPOTENT — safe to run multiple times.
#
# BEFORE RUNNING:
#   1. Flash Pi OS, boot, set up SSH
#   2. Install Docker and Docker Compose
#   3. Clone igor repository
#   4. Restore db.env from companion snapshot
#   5. Mount external drive to ${HD_MOUNT:-/mnt/nextclouddata}
#
# RESTORE STEPS:
#   bash rebuild.sh                   — sets up system
#   bash igor.sh -> V -> 2 -> 2 -> 2  — module restore hook (DB restore)

set -euo pipefail
IGOR_DIR="\${IGOR_DIR:-\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)}"
HD_MOUNT=\${HD_MOUNT:-${HD_MOUNT:-/mnt/nextclouddata}}
NC_DATA=\${NC_DATA:-${NC_DATA:-/mnt/nextclouddata/next}}

echo "== Nextcloud Rebuild: ${nc_ver} / ${trusted_domain} =="

command -v docker &>/dev/null || { echo "ERROR: Install Docker first."; exit 1; }
getent group docker | grep -q "\$USER" || sudo usermod -aG docker "\$USER"

# Swap (Pi 3 — 1GB RAM)
if [ ! -f /var/swap ] || [ "\$(swapon --show | wc -l)" -lt 2 ]; then
    echo 'CONF_SWAPSIZE=1024' | sudo tee /etc/dphys-swapfile >/dev/null
    sudo dphys-swapfile setup && sudo dphys-swapfile swapon
fi

mkdir -p "\$HD_MOUNT"
mountpoint -q "\$HD_MOUNT" || echo "WARNING: Mount \$HD_MOUNT before continuing"

# Named volumes from this backup's compose file:
$(grep -E '^\s+name:' "$_compose_file" 2>/dev/null | awk '{print "docker volume inspect "$2" &>/dev/null || docker volume create "$2}' || echo "# Could not read volume names from compose file — create volumes manually")

systemctl is-enabled cloudflared &>/dev/null || \
    echo "INFO: Configure Cloudflare tunnel via igor.sh -> Tunnel menu"

cd "\$IGOR_DIR"
docker compose ${compose_file:+-f "$compose_file"} build app
docker compose ${compose_file:+-f "$compose_file"} up -d
sleep 30

echo "Apps enabled at backup time: ${app_list}"
echo "Next: restore database via igor.sh -> V -> 2 -> 2 -> 2"
REBUILD_SCRIPT

    chmod +x "$out"
    echo -e "  \033[0;32m✔\033[0m Rebuild script generated"
}

# ── nextcloud_docker__restore SNAPSHOT_DIR ────────────────────────────────────
# Restore hook. Called by core full_backup_restore() via igor_run_all_hooks "restore".
nextcloud_docker__restore() {
    local snapshot_dir="${1:-}"
    local module_name="nextcloud_docker"
    local src="${snapshot_dir}/modules/${module_name}"

    [ -z "$snapshot_dir" ] && { echo "nextcloud_docker__restore: missing snapshot_dir" >&2; return 1; }

    local RED='\033[0;31m' GRN='\033[0;32m' YEL='\033[1;33m'
    local CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'

    if [ ! -d "$src" ]; then
        echo -e "  ${YEL}!${NC} No Nextcloud data in this backup — skipping restore"
        return 0
    fi

    echo ""
    echo -e "  ${BOLD}Nextcloud Restore${NC}"
    echo -e "  ${CYAN}$(printf '─%.0s' {1..45})${NC}"
    echo ""
    echo "  Available:"
    [ -f "${src}/db_dump.sql.gz" ] && echo "    • db_dump.sql.gz  ($(du -sh "${src}/db_dump.sql.gz" | cut -f1))"
    [ -f "${src}/nginx.conf" ]     && echo "    • nginx.conf"
    [ -f "${src}/nc_config.json" ] && echo "    • nc_config.json  (informational)"
    [ -f "${src}/app_list.json" ]  && echo "    • app_list.json   (informational)"
    [ -f "${src}/rebuild.sh" ]     && echo "    • rebuild.sh"
    echo ""

    local _scope
    _scope=$(igor_fzf_pick "Nextcloud Restore" \
        "1:DB RESTORE:Restore PostgreSQL from dump — DESTRUCTIVE" \
        "2:NGINX RESTORE:Restore nginx.conf (with test + reload)" \
        "3:VIEW NC CONFIG:occ config from backup (informational)" \
        "4:VIEW APP LIST:Apps enabled at backup time (informational)" \
        "5:VIEW REBUILD:Browse the disaster-recovery rebuild.sh" \
        "b:BACK:Cancel")
    case $? in 1|2)
        echo "    1) DB restore (DESTRUCTIVE)"; echo "    2) nginx.conf restore"
        echo "    3) View NC config"; echo "    4) View app list"
        echo "    5) View rebuild.sh"; echo "    b) Back"
        read -rp "  Choice: " _scope ;; esac

    case "$_scope" in
        1) _ncd_restore_db "${src}/db_dump.sql.gz" ;;
        2) _ncd_restore_nginx "${src}/nginx.conf" ;;
        3)
            if [ -f "${src}/nc_config.json" ]; then
                echo -e "  ${CYAN}NC config at backup time:${NC}"
                python3 -m json.tool "${src}/nc_config.json" 2>/dev/null | head -60 || \
                    head -60 "${src}/nc_config.json"
                echo ""
                echo -e "  ${YEL}Note:${NC} To apply: occ config:import < nc_config.json"
            else
                warn "nc_config.json not in this backup"
            fi
            ;;
        4)
            if [ -f "${src}/app_list.json" ]; then
                python3 -c "
import json, sys
d = json.load(open('${src}/app_list.json'))
print('  Enabled:')
for a in sorted(d.get('enabled', {}).keys()): print('    + ' + a)
print('  Disabled:')
disabled = d.get('disabled', {})
keys = sorted(disabled.keys() if isinstance(disabled, dict) else disabled)
for a in keys: print('    - ' + a)
" 2>/dev/null || cat "${src}/app_list.json"
                echo -e "\n  ${YEL}Note:${NC} Use occ app:enable/disable to apply."
            else
                warn "app_list.json not in this backup"
            fi
            ;;
        5)
            [ -f "${src}/rebuild.sh" ] && \
                { less "${src}/rebuild.sh" 2>/dev/null || cat "${src}/rebuild.sh"; } || \
                warn "rebuild.sh not in this backup"
            ;;
        b|B) return 0 ;;
        *) warn "Invalid choice" ;;
    esac
}

# ── _ncd_restore_db DUMP_FILE ─────────────────────────────────────────────────
# DESTRUCTIVE — double-gated (confirm prompt + type YES).
_ncd_restore_db() {
    local dump_file="$1"
    local RED='\033[0;31m' GRN='\033[0;32m' YEL='\033[1;33m' BOLD='\033[1m' NC='\033[0m'

    [ ! -f "$dump_file" ] && { echo -e "  ${RED}✘${NC} Dump file not found: $dump_file"; return 1; }

    local sz; sz=$(du -sh "$dump_file" 2>/dev/null | cut -f1)
    echo ""
    echo -e "  ${RED}${BOLD}DATABASE RESTORE — DESTRUCTIVE${NC}"
    echo -e "  ${YEL}This will OVERWRITE the live Nextcloud database.${NC}"
    echo -e "  Dump: $dump_file (${sz})"
    echo ""

    declare -f confirm &>/dev/null && { confirm "Proceed with database restore?" || return 0; }
    read -rp "  Type YES to confirm: " _confirm
    [ "$_confirm" = "YES" ] || { echo "  Cancelled."; return 0; }

    docker compose exec -T -u www-data app php occ maintenance:mode --on 2>/dev/null || true

    docker compose exec -T db psql -U "${POSTGRES_USER:-nextcloud}" -d postgres \
        -c "DROP DATABASE IF EXISTS \"${POSTGRES_DB:-nextcloud}\";" 2>/dev/null || {
        echo -e "  ${RED}✘${NC} Drop DB failed"
        docker compose exec -T -u www-data app php occ maintenance:mode --off 2>/dev/null || true
        return 1
    }
    docker compose exec -T db psql -U "${POSTGRES_USER:-nextcloud}" -d postgres \
        -c "CREATE DATABASE \"${POSTGRES_DB:-nextcloud}\" OWNER \"${POSTGRES_USER:-nextcloud}\";" \
        2>/dev/null || { echo -e "  ${RED}✘${NC} Create DB failed"; return 1; }

    echo "  Restoring (may take several minutes on Pi 3)..."
    zcat "$dump_file" | docker compose exec -T db psql \
        -U "${POSTGRES_USER:-nextcloud}" -d "${POSTGRES_DB:-nextcloud}" 2>/dev/null
    local rc=$?

    docker compose exec -T -u www-data app php occ maintenance:mode --off 2>/dev/null || true

    if [ $rc -eq 0 ]; then
        echo -e "  ${GRN}✔${NC} Database restored."
        declare -f journal_record &>/dev/null && \
            journal_record "menu:recovery" "db_backup" "DESTRUCTIVE" \
                "psql restore $(basename "$dump_file")" "OK" "" 2>/dev/null || true
    else
        echo -e "  ${RED}✘${NC} Database restore failed (exit $rc)."
        declare -f journal_record &>/dev/null && \
            journal_record "menu:recovery" "db_backup" "DESTRUCTIVE" \
                "psql restore $(basename "$dump_file")" "FAIL" "rc:${rc}" 2>/dev/null || true
        return 1
    fi
}

# ── _ncd_restore_nginx NGINX_SRC ──────────────────────────────────────────────
_ncd_restore_nginx() {
    local nginx_src="$1"
    local GRN='\033[0;32m' RED='\033[0;31m' NC='\033[0m'

    [ ! -f "$nginx_src" ] && { echo "  nginx.conf not found in backup"; return 0; }

    # Locate live nginx.conf
    local nginx_live="${NEXTCLOUD_DOCKER_STACK_DIR:+${NEXTCLOUD_DOCKER_STACK_DIR}/nginx.conf}"
    for _nf in "$nginx_live" "${IGOR_DIR}/web/nginx.conf" \
               "${IGOR_DIR}/config/stacks/nextcloud/nginx.conf"; do
        [ -f "$_nf" ] && { nginx_live="$_nf"; break; }
    done

    echo ""
    echo "  Diff (backup vs live):"
    diff --color=always -u "$nginx_live" "$nginx_src" 2>/dev/null | head -50 || true
    echo ""

    declare -f confirm &>/dev/null && { confirm "Restore nginx.conf?" || return 0; }

    local bak="${nginx_live}.bak.$(date +%s)"
    cp "$nginx_live" "$bak" 2>/dev/null && echo "  Backed up: $(basename "$bak")"
    cp "$nginx_src" "$nginx_live"

    docker compose exec web nginx -t 2>/dev/null && \
        docker compose restart web && echo -e "  ${GRN}✔${NC} nginx restored and reloaded" || {
        echo -e "  ${RED}✘${NC} nginx test failed — rolling back"
        mv "$bak" "$nginx_live"
        docker compose restart web
        return 1
    }
}
