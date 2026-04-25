#!/bin/bash
# ==============================================================================
#  IGOR — lib/helpers.sh
#  Helper functions for system operations.
#
#  Provides:
#    • Environment variable management (get_env, set_env)
#    • File/directory ownership helpers (own_dir, own_nc_file, own_nc_dir)
#    • Docker compose utilities (check_compose, wait_for_db)
#    • Report generation (save_report)
#    • Path resolution (_igor_resolve_dir)
# ==============================================================================

# ── Centralised runtime directory resolution ──────────────────────────────────
# Usage: _igor_resolve_dir <type>
# All runtime paths are relative to IGOR_DIR (the repo root).
# Override individual vars (IGOR_RUNTIME_DIR etc.) before sourcing to relocate.
_igor_resolve_dir() {
    local _type="${1:-}"
    local _base="${IGOR_DIR:-.}"
    case "$_type" in
        runtime)  echo "${IGOR_RUNTIME_DIR:-${_base}/data/runtime}" ;;
        sessions) echo "${IGOR_SESSIONS_DIR:-${_base}/data/sessions}" ;;
        alerts)   echo "${IGOR_ALERTS_DIR:-${_base}/data/alerts}" ;;
        patterns) echo "${IGOR_PATTERNS_DIR:-${_base}/config/patterns}" ;;
        reports)  echo "${IGOR_REPORTS_DIR:-${_base}/data/reports}" ;;
        knowledge) echo "${IGOR_KNOWLEDGE_DIR:-${_base}/config/knowledge}" ;;
        backups)  echo "${IGOR_BACKUPS_DIR:-${_base}/data/backups}" ;;
        secrets)  echo "${IGOR_SECRETS_DIR:-${_base}/secrets}" ;;
        recovery)  echo "${IGOR_RECOVERY_DIR:-${_base}/data/recovery}" ;;
        *)        echo "${_base}/${_type}" ;;
    esac
}

# ── File paths (can be overridden by sourcing scripts) ──────────────────────────
COMPOSE_FILE="${COMPOSE_FILE:-${IGOR_DIR:-.}/config/stacks/nextcloud/docker-compose.yml}"
DB_ENV="${DB_ENV:-${IGOR_DIR:-.}/secrets/db.env}"
REPORTS_DIR="${REPORTS_DIR:-$(_igor_resolve_dir "reports")}"

# ── Docker compose utilities ─────────────────────────────────────────────────────
check_compose() {
    [ ! -f "$COMPOSE_FILE" ] && { fail "docker-compose.yml not found in $(pwd)"; pause; return 1; }
    return 0
}

wait_for_db() {
    local max="${1:-90}" i=0
    info "Waiting for PostgreSQL (up to ${max}s)..."
    while [ $i -lt "$max" ]; do
        docker compose exec -T db pg_isready -U "${POSTGRES_USER:-nextcloud}" \
            -d "${POSTGRES_DB:-nextcloud}" &>/dev/null && { ok "PostgreSQL ready."; return 0; }
        sleep 3; i=$((i+3)); printf "."
    done
    echo ""; fail "PostgreSQL not ready after ${max}s."; return 1
}

# ── File/directory ownership ─────────────────────────────────────────────────────
# Relies on global NC_UID and NC_GID variables
own_dir()     { sudo mkdir -p "$1"; sudo chown "$USER:$USER" "$1"; sudo chmod 755 "$1"; }
own_nc_file() { sudo chown "${NC_UID:-1004}:${NC_GID:-1004}" "$1" 2>/dev/null; sudo chmod 640 "$1" 2>/dev/null; }
own_nc_dir()  { sudo chown "${NC_UID:-1004}:${NC_GID:-1004}" "$1" 2>/dev/null; sudo chmod 750 "$1" 2>/dev/null; }

# ── Environment variable management ──────────────────────────────────────────────
get_env() { grep "^${1}=" "$DB_ENV" 2>/dev/null | cut -d= -f2-; }

set_env() {
    local key="$1" val="$2"
    # Escape characters special to sed's replacement string (|, &, \)
    local escaped_val; escaped_val=$(printf '%s' "$val" | sed 's/[&|\\]/\\&/g')
    if grep -q "^${key}=" "$DB_ENV" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${escaped_val}|" "$DB_ENV"
    else
        echo "${key}=${val}" >> "$DB_ENV"
    fi
}

# ── Block device validation ──────────────────────────────────────────────────────
# validate_block_device <path>  — returns 0 if valid, 1 with error message if not.
# Used before any sudo mkfs/mount/fdisk call to prevent typo-induced data loss.
validate_block_device() {
    local dev="$1"
    if [[ ! "$dev" =~ ^/dev/[a-zA-Z0-9]+$ ]]; then
        fail "Invalid device path: ${dev}  (must match /dev/<alphanumeric>)"
        return 1
    fi
    if [ ! -b "$dev" ]; then
        fail "Not a block device: ${dev}"
        return 1
    fi
    return 0
}

# ── Report generation ───────────────────────────────────────────────────────────
save_report() {
    # save_report <name> <content>
    mkdir -p "$REPORTS_DIR"
    local fname="${REPORTS_DIR}/${1}_$(date +%Y%m%d_%H%M%S).txt"
    echo "$2" > "$fname"
    ok "Report saved: $fname"
}

# ── Dynamic menu items helpers ────────────────────────────────────────────────────
# Directory for dynamic menu item files

get_pending_item_count() {
    # Returns count of items with APPROVED=0
    if [ ! -d "$DYNAMIC_ITEMS_DIR" ]; then
        echo "0"
        return
    fi
    local count=0
    for item_file in "$DYNAMIC_ITEMS_DIR"/*.item; do
        [ -f "$item_file" ] || continue
        grep -q "^APPROVED: 0$" "$item_file" && count=$((count + 1))
    done
    echo "$count"
}

get_pending_items_list() {
    # Returns array of pending item IDs (via global array pending_item_ids)
    pending_item_ids=()
    if [ ! -d "$DYNAMIC_ITEMS_DIR" ]; then
        return
    fi
    while IFS= read -r -d '' item_file; do
        grep -q "^APPROVED: 0$" "$item_file" && pending_item_ids+=("$(basename "$item_file" .item)")
    done < <(find "$DYNAMIC_ITEMS_DIR" -maxdepth 1 -name "*.item" -print0 | sort -z)
}

read_item_file() {
    # read_item_file <id> -> sets global item associative array
    # Usage: declare -gA item; read_item_file "1234567890"; echo "${item[TITLE]}"
    local id="$1"
    local item_file="$DYNAMIC_ITEMS_DIR/${id}.item"

    [ ! -f "$item_file" ] && return 1

    while IFS=": " read -r key value; do
        [ -n "$key" ] && item["$key"]="$value"
    done < "$item_file"

    return 0
}

write_item_file() {
    # write_item_file <id> <associative_array_name>
    # Usage: declare -A new_item; write_item_file "1234567890" new_item
    local id="$1"
    local array_name="$2"
    local item_file="$DYNAMIC_ITEMS_DIR/${id}.item"
    mkdir -p "$DYNAMIC_ITEMS_DIR"

    # Iterate through the associative array using indirect reference
    local -n ref_array="$array_name"
    for key in "${!ref_array[@]}"; do
        echo "${key}: ${ref_array[$key]}"
    done > "$item_file"
}

approve_item() {
    # approve_item <id> - sets APPROVED=1
    local id="$1"
    local item_file="$DYNAMIC_ITEMS_DIR/${id}.item"
    [ ! -f "$item_file" ] && return 1
    sed -i 's/^APPROVED: 0$/APPROVED: 1/' "$item_file"
}

delete_item() {
    # delete_item <id> - removes item file
    local id="$1"
    local item_file="$DYNAMIC_ITEMS_DIR/${id}.item"
    [ -f "$item_file" ] && rm -f "$item_file"
}

get_approved_items_list() {
    # Returns array of approved item IDs (via global array approved_item_ids)
    approved_item_ids=()
    if [ ! -d "$DYNAMIC_ITEMS_DIR" ]; then
        return
    fi
    while IFS= read -r -d '' item_file; do
        grep -q "^APPROVED: 1$" "$item_file" && approved_item_ids+=("$(basename "$item_file" .item)")
    done < <(find "$DYNAMIC_ITEMS_DIR" -maxdepth 1 -name "*.item" -print0 | sort -z)
}

# ── Docker volume helpers ─────────────────────────────────────────────────────
# _igor_vol_size <volname>
#   Returns human-readable size of a Docker volume (e.g. "2.3G").
#   Uses du -sh on the volume mountpoint (requires sudo on most Linux systems).
#   Returns "?" when the volume does not exist, mountpoint is inaccessible, or
#   du fails for any reason.  Never raises — always safe to embed in a string.
_igor_vol_size() {
    local _vol="$1"
    local _mp _sz
    _mp=$(docker volume inspect "$_vol" --format '{{.Mountpoint}}' 2>/dev/null) || { echo "?"; return; }
    [ -z "$_mp" ] && { echo "?"; return; }
    _sz=$(sudo du -sh "$_mp" 2>/dev/null | cut -f1)
    echo "${_sz:-?}"
}

# _igor_vol_age <volname>
#   Returns human-readable age of a Docker volume (e.g. "3 days ago", "today").
#   Reads .CreatedAt from docker volume inspect and computes the delta from now.
#   Returns "unknown" on any failure.
_igor_vol_age() {
    local _vol="$1"
    docker volume inspect "$_vol" --format '{{.CreatedAt}}' 2>/dev/null \
        | python3 -c "
import sys, datetime
raw = sys.stdin.read().strip()
try:
    dt = datetime.datetime.fromisoformat(raw[:19])
    delta = datetime.datetime.utcnow() - dt
    days = delta.days
    if days == 0:
        print('today')
    elif days == 1:
        print('1 day ago')
    else:
        print(f'{days} days ago')
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown"
}
