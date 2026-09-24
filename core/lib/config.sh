#!/bin/bash
# ==============================================================================
#  IGOR — lib/config.sh
#  Configuration loading and management.
#
#  Variable precedence (later sources override earlier):
#    1. Script defaults (hardcoded in this file)
#    2. config/defaults.env (repository defaults)
#    3. $NEXUS_CONFIG/config.env (user overrides)   — defaults to $IGOR_DIR
#    4. $NEXUS_CONFIG/db.env    (secrets)            — defaults to $IGOR_DIR
#    5. Environment variables (can be set at runtime)
#
#  Environment variables set by this module:
#    • NC_UID, NC_GID - Container user IDs
#    • HD_MOUNT, NC_DATA - Mount points
#    • POSTGRES_USER, POSTGRES_DB, POSTGRES_PASSWORD - DB credentials
#    • NEXTCLOUD_ADMIN_USER, NEXTCLOUD_ADMIN_PASSWORD - NC admin
#    • NEXTCLOUD_TRUSTED_DOMAINS - Public domains
# ==============================================================================

# ── Working directory ──────────────────────────────────────────────────────────
# PROJECT_DIR is always IGOR_DIR — stacks live at stacks/nextcloud/ inside it.
if [ -n "${NEXUS_PROJECT_DIR:-}" ]; then
    PROJECT_DIR="$NEXUS_PROJECT_DIR"
elif [ -n "${IGOR_DIR:-}" ]; then
    PROJECT_DIR="$IGOR_DIR"
else
    PROJECT_DIR="$HOME"
fi
[ ! -d "$PROJECT_DIR" ] && { echo "ERROR: Project dir not found: $PROJECT_DIR"; exit 1; }
cd "$PROJECT_DIR" || exit 1

# ── Configuration directory ───────────────────────────────────────────────────────
# Default: the igor project directory itself (keeps everything in one place).
# Override by setting NEXUS_CONFIG before launching igor.sh.
_IGOR_DIR_FOR_CFG="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
NEXUS_CONFIG="${NEXUS_CONFIG:-${_IGOR_DIR_FOR_CFG}}"

# ── Script defaults (can be overridden) ───────────────────────────────────────────
NC_UID="${NC_UID:-1004}"
NC_GID="${NC_GID:-1004}"
HD_MOUNT="${HD_MOUNT:-/mnt/nextclouddata}"
NC_DATA="${NC_DATA:-/mnt/nextclouddata/next}"
NEXUS_VERBOSE="${NEXUS_VERBOSE:-true}"
NEXUS_BACKEND="${NEXUS_BACKEND:-docker}"

# ── Detect and create config directory if needed ────────────────────────────────
_detect_config_dir() {
    # Ensure config (project) directory exists
    mkdir -p "$NEXUS_CONFIG" 2>/dev/null || true

    # ── Migrate data from old ~/.config/igor/ location ──────────────────
    # Runs once: if old location exists and project-dir data is missing, move it.
    local _old="$HOME/.config/igor"
    if [ "$NEXUS_CONFIG" != "$_old" ] && [ -d "$_old" ]; then
        local _migrated=0
        # Directories: move whole subtree if destination not present
        for _d in backups alerts patterns knowledge sessions runtime recovery; do
            if [ -d "${_old}/${_d}" ] && [ ! -d "${NEXUS_CONFIG}/${_d}" ]; then
                mv "${_old}/${_d}" "${NEXUS_CONFIG}/${_d}" 2>/dev/null && \
                    _migrated=$(( _migrated + 1 )) || true
            fi
        done
        # Files: env configs that may have been written there
        for _f in config.env notify.env mailcmd.env ai_settings.env; do
            if [ -f "${_old}/${_f}" ] && [ ! -f "${NEXUS_CONFIG}/${_f}" ]; then
                mv "${_old}/${_f}" "${NEXUS_CONFIG}/${_f}" 2>/dev/null && \
                    _migrated=$(( _migrated + 1 )) || true
            fi
        done
        # GPG homedir (must keep permissions 700)
        if [ -d "${_old}/gnupg" ] && [ ! -d "${NEXUS_CONFIG}/gnupg" ]; then
            mv "${_old}/gnupg" "${NEXUS_CONFIG}/gnupg" 2>/dev/null && \
                chmod 700 "${NEXUS_CONFIG}/gnupg" 2>/dev/null && \
                _migrated=$(( _migrated + 1 )) || true
        fi
        if [ $_migrated -gt 0 ]; then
            echo "  [igor] Migrated ${_migrated} item(s) from ${_old}/ → ${NEXUS_CONFIG}/"
            # Remove old dir if now empty
            rmdir "$_old" 2>/dev/null || true
        fi
    fi

    # ── Phase 2: NEXUS_CONFIG root → secrets/ (post-split migration) ─────────────
    # notify.env, mailcmd.env, gnupg/ are now canonical at ${IGOR_DIR}/secrets/
    local _secrets_dir="${IGOR_DIR}/secrets"
    mkdir -p "$_secrets_dir" 2>/dev/null || true
    local _sec_migrated=0
    for _sf in notify.env mailcmd.env; do
        if [ -f "${NEXUS_CONFIG}/${_sf}" ] && [ ! -f "${_secrets_dir}/${_sf}" ]; then
            mv "${NEXUS_CONFIG}/${_sf}" "${_secrets_dir}/${_sf}" 2>/dev/null && \
                chmod 600 "${_secrets_dir}/${_sf}" 2>/dev/null && \
                _sec_migrated=$(( _sec_migrated + 1 )) || true
        fi
    done
    if [ -d "${NEXUS_CONFIG}/gnupg" ] && [ ! -d "${_secrets_dir}/gnupg" ]; then
        mv "${NEXUS_CONFIG}/gnupg" "${_secrets_dir}/gnupg" 2>/dev/null && \
            chmod 700 "${_secrets_dir}/gnupg" 2>/dev/null && \
            _sec_migrated=$(( _sec_migrated + 1 )) || true
    fi
    if [ "$_sec_migrated" -gt 0 ]; then
        echo "  [igor] Migrated ${_sec_migrated} secret(s) → ${_secrets_dir}/"
    fi
}

# ── Safe env-file loader ─────────────────────────────────────────────────────────
# Sources a KEY=VALUE file safely: strips comments and blank lines, handles
# unquoted values with spaces (sets the var to the full value string without
# treating extra words as shell commands). Exports every key it sets.
_source_env_file() {
    local _f="$1"
    [ -f "$_f" ] || return 0
    while IFS= read -r _line || [ -n "$_line" ]; do
        # strip leading whitespace and skip comments / blank lines
        _line="${_line#"${_line%%[! ]*}"}"
        [[ "$_line" == "#"* ]] && continue
        [[ -z "$_line" ]]      && continue
        [[ "$_line" != *"="* ]] && continue
        local _key="${_line%%=*}"
        local _val="${_line#*=}"
        # strip surrounding quotes if present
        if [[ "$_val" == '"'*'"' ]] || [[ "$_val" == "'"*"'" ]]; then
            _val="${_val:1:${#_val}-2}"
        fi
        export "$_key"="$_val"
    done < "$_f"
}

# ── Load configuration files ─────────────────────────────────────────────────────
_load_config() {
    # 1. Load repository defaults
    if [ -f "${IGOR_DIR}/core/config/defaults.env" ]; then
        set -a
        source "${IGOR_DIR}/core/config/defaults.env"
        set +a
    fi

    # 2. Load user config overrides
    if [ -f "${NEXUS_CONFIG}/config.env" ]; then
        set -a
        source "${NEXUS_CONFIG}/config.env"
        set +a
    fi

# 3. Load secrets (db.env) — use safe loader to handle unquoted multi-word values
    if [ -f "${IGOR_DIR}/secrets/db.env" ]; then
        _source_env_file "${IGOR_DIR}/secrets/db.env"
    elif [ -f "${PROJECT_DIR}/db.env" ]; then
        _source_env_file "${PROJECT_DIR}/db.env"
    elif [ -f "${NEXUS_CONFIG}/db.env" ]; then
        _source_env_file "${NEXUS_CONFIG}/db.env"
    fi

    # 4. Load OnlyOffice secret if present
    if [ -f "${IGOR_DIR}/secrets/onlyoffice.env" ]; then
        export JWT_SECRET
        JWT_SECRET=$(grep "^JWT_SECRET=" "${IGOR_DIR}/secrets/onlyoffice.env" 2>/dev/null | cut -d= -f2)
    elif [ -f "${PROJECT_DIR}/onlyoffice.env" ]; then
        export JWT_SECRET
        JWT_SECRET=$(grep "^JWT_SECRET=" "${PROJECT_DIR}/onlyoffice.env" 2>/dev/null | cut -d= -f2)
    elif [ -f "${NEXUS_CONFIG}/onlyoffice.env" ]; then
        export JWT_SECRET
        JWT_SECRET=$(grep "^JWT_SECRET=" "${NEXUS_CONFIG}/onlyoffice.env" 2>/dev/null | cut -d= -f2)
    fi
}

# ── Validate required configuration ───────────────────────────────────────────────
_validate_config() {
    # Compatibility defaults for existing module helpers. Application
    # requirements are validated by the active module's config_validate hook.
    POSTGRES_USER="${POSTGRES_USER:-nextcloud}"
    POSTGRES_DB="${POSTGRES_DB:-nextcloud}"
    # ── Secrets file permissions ──────────────────────────────────────────────────
    local _db_env_path="${IGOR_DIR}/secrets/db.env"
    [ ! -f "$_db_env_path" ] && _db_env_path="${PROJECT_DIR}/db.env"
    if [ -f "$_db_env_path" ]; then
        local _perms; _perms=$(stat -c '%a' "$_db_env_path" 2>/dev/null || echo "")
        if [ -n "$_perms" ] && [ "$_perms" != "600" ] && [ "$_perms" != "400" ]; then
            echo "  [igor] WARNING: ${_db_env_path} has permissions ${_perms} — should be 600" >&2
        fi
    fi

    return 0
}

# ── Get version string ───────────────────────────────────────────────────────────
get_version() {
    local version_file="$(dirname "$0")/../VERSION"
    if [ -f "$version_file" ]; then
        cat "$version_file"
    else
        echo "1.0.0"
    fi
}

# ── Export file paths for other modules ────────────────────────────────────────
export PROJECT_DIR
export NEXUS_CONFIG
export COMPOSE_FILE="${IGOR_DIR:-.}/config/stacks/nextcloud/docker-compose.yml"
export DB_ENV="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/secrets/db.env"
export REPORTS_DIR="${IGOR_DIR}/data/reports"

# ── Initialize configuration on load ─────────────────────────────────────────────
_detect_config_dir
_load_config
_validate_config
