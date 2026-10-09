#!/bin/bash
# =============================================================================
#  CONFIG LOADER — core/lib/config_loader.sh
#
#  Loads all Igor configuration in a defined precedence order:
#
#    1. variables/*.env        — tracked settings (git-safe)
#    2. secrets/*.env          — credentials (gitignored, 600 required)
#    3. secrets/*.key          → exported as <STEM>_API_KEY variables
#    4. Root-level *.env       — backward-compat (deprecated, warned)
#    5. Module validation      — each loaded module's declared files exist
#
#  Public API:
#    igor_load_config          — run all five steps above
#    igor_validate_module_config <name>  — check one module's declared files
#
#  All functions export variables into the calling shell via set -a / set +a.
#  Errors are warnings only — a missing optional file is never fatal.
# =============================================================================

# Root of the Igor installation — resolved relative to this file's location
_IGOR_CFG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && cd ../.. && pwd)"

# ---------------------------------------------------------------------------
# _cfg_log <level> <message>
# ---------------------------------------------------------------------------
_cfg_log() {
    local _level="$1"; shift
    local _msg="$*"
    case "$_level" in
        ok)    printf '  [config_loader] ✔  %s\n' "$_msg" ;;
        info)  printf '  [config_loader]    %s\n' "$_msg" ;;
        warn)  printf '  [config_loader] ⚠  %s\n' "$_msg" >&2 ;;
        error) printf '  [config_loader] ✗  %s\n' "$_msg" >&2 ;;
    esac
}

_cfg_openrouter_cutover() {
    local _root="${IGOR_DIR:-$_IGOR_CFG_DIR}" _data _state
    _data="${IGOR_DATA_DIR:-${_root}/data}"
    if [ ! -f "${_root}/core/lib/configuration.py" ]; then
        [ -e "${_data}/secrets/catalog.db" ]
        return $?
    fi
    _state=$(IGOR_CONFIGURATION_ROOT="$_root" IGOR_CONFIGURATION_DATA_DIR="$_data" \
        env -u OPENROUTER_API_KEY -u OR_API_KEY -u NEXUS_API_KEY \
        python3 "${_root}/core/lib/configuration.py" openrouter-cutover-guard 2>/dev/null) || return 0
    [ "$_state" != legacy ]
}

_cfg_fence_openrouter_aliases() {
    [ "${_IGOR_OPENROUTER_GUARD:-false}" = true ] || return 0
    unset OPENROUTER_API_KEY OR_API_KEY NEXUS_API_KEY
}

# ---------------------------------------------------------------------------
# _cfg_check_permissions <file>
#   Returns 0 if file has 600 permissions, 1 otherwise.
#   On non-Linux (e.g. Windows host dev), skips the check with a notice.
# ---------------------------------------------------------------------------
_cfg_check_permissions() {
    local _file="$1"
    # stat -c is Linux-specific; skip gracefully on other platforms
    if ! command -v stat >/dev/null 2>&1; then
        return 0
    fi
    local _perms
    _perms="$(stat -c '%a' "$_file" 2>/dev/null)" || return 0
    if [ "$_perms" != "600" ]; then
        _cfg_log warn "Insecure permissions on $_file (${_perms}, expected 600)"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# _cfg_source_env <file> [skip_perms_check]
#   Source an env file with set -a so all variables are exported.
#   Uses a subshell-safe approach: source into current shell via process
#   substitution after stripping comments and blank lines.
# ---------------------------------------------------------------------------
_cfg_source_env() {
    local _file="$1"
    local _skip_perms="${2:-false}"

    [ -f "$_file" ] || return 1

    if [ "$_skip_perms" != "true" ]; then
        _cfg_check_permissions "$_file" || true   # warn but continue
    fi

    local _projected="" _rc=0
    if [ "${_IGOR_OPENROUTER_GUARD:-false}" = true ] &&
       grep -aqE '(^|[^A-Za-z0-9_])(OPENROUTER_API_KEY|OR_API_KEY|NEXUS_API_KEY)[[:space:]]*=' "$_file"; then
        # Parse the selected assignments as data BEFORE any Bash evaluation.
        # Ambiguous/compound selected syntax refuses the whole source file.
        _projected=$(env -u OPENROUTER_API_KEY -u OR_API_KEY -u NEXUS_API_KEY \
            python3 "${_IGOR_CFG_DIR}/core/lib/openrouter_import.py" loader-projection "$_file") || {
            _cfg_log warn "Selected credential assignments ignored; ambiguous source not evaluated"
            return 1
        }
        set -a
        # shellcheck disable=SC1090
        source /dev/stdin <<< "$_projected" 2>/tmp/_igor_cfg_src_err
        _rc=$?
    else
        set -a
        # shellcheck disable=SC1090
        source "$_file" 2>/tmp/_igor_cfg_src_err
        _rc=$?
    fi
    set +a
    _cfg_fence_openrouter_aliases

    if [ $_rc -ne 0 ]; then
        _cfg_log error "Failed to source $_file: $(cat /tmp/_igor_cfg_src_err 2>/dev/null)"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# _cfg_load_variables
#   Step 1: Source all variables/*.env files in sorted order.
# ---------------------------------------------------------------------------
_cfg_load_variables() {
    local _vars_dir="${IGOR_DIR:-$_IGOR_CFG_DIR}/config/variables"
    [ -d "$_vars_dir" ] || return 0

    local _file _count=0
    for _file in "${_vars_dir}"/*.env; do
        [ -f "$_file" ] || continue
        if _cfg_source_env "$_file" true; then
            _cfg_log ok "Loaded variables: $(basename "$_file")"
            (( _count++ )) || true
        fi
    done

    [ $_count -eq 0 ] && _cfg_log info "No variables/*.env files found"
    return 0
}

# ---------------------------------------------------------------------------
# _cfg_load_secrets_env
#   Step 2: Source all secrets/*.env files (with permissions check).
# ---------------------------------------------------------------------------
_cfg_load_secrets_env() {
    local _sec_dir="${IGOR_DIR:-$_IGOR_CFG_DIR}/secrets"
    [ -d "$_sec_dir" ] || return 0

    local _file _count=0
    for _file in "${_sec_dir}"/*.env; do
        [ -f "$_file" ] || continue
        if _cfg_source_env "$_file" false; then
            _cfg_log ok "Loaded secrets: $(basename "$_file")"
            (( _count++ )) || true
        fi
    done

    [ $_count -eq 0 ] && _cfg_log info "No secrets/*.env files found"
    return 0
}

# ---------------------------------------------------------------------------
# _cfg_load_key_files
#   Step 3: Read secrets/*.key → export as <STEM>_API_KEY.
#   Example: secrets/anthropic.key → $ANTHROPIC_API_KEY
#            secrets/openrouter.key → $OPENROUTER_API_KEY
# ---------------------------------------------------------------------------
_cfg_load_key_files() {
    local _sec_dir="${IGOR_DIR:-$_IGOR_CFG_DIR}/secrets"
    [ -d "$_sec_dir" ] || return 0

    local _file _stem _varname _value _count=0
    for _file in "${_sec_dir}"/*.key; do
        [ -f "$_file" ] || continue
        _stem="$(basename "$_file" .key)"
        if [ "${_IGOR_OPENROUTER_GUARD:-false}" = true ]; then
            case "$_stem" in openrouter|or|nexus) continue ;; esac
        fi
        _cfg_check_permissions "$_file" || true   # warn but continue
        # Normalize stem to uppercase, replace non-alphanum with _
        _varname="$(printf '%s' "$_stem" | tr '[:lower:]' '[:upper:]' | tr -cs 'A-Z0-9' '_')_API_KEY"

        # Read first non-empty line as the key value
        _value="$(grep -m1 '[^[:space:]]' "$_file" 2>/dev/null | tr -d '[:space:]')"

        if [ -n "$_value" ]; then
            export "$_varname=$_value"
            _cfg_log ok "Loaded key: $(basename "$_file") → \$$_varname"
            (( _count++ )) || true
        else
            _cfg_log warn "Key file empty or unreadable: $(basename "$_file")"
        fi
    done

    # ── Legacy home-dir key files ─────────────────────────────────────────────
    # ~/.nexus_api_key → ANTHROPIC_API_KEY   (historical Anthropic key path)
    # ~/.nexus_or_key  → OPENROUTER_API_KEY  (historical OpenRouter key path)
    # Loaded only when the secrets/ counterpart is not already set.
    local _legacy_count=0
    if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "$HOME/.nexus_api_key" ]; then
        _value="$(tr -d '[:space:]' < "$HOME/.nexus_api_key" 2>/dev/null)"
        if [ -n "$_value" ]; then
            export ANTHROPIC_API_KEY="$_value"
            _cfg_log ok "Loaded key: ~/.nexus_api_key → \$ANTHROPIC_API_KEY"
            (( _legacy_count++ )) || true
            (( _count++ )) || true
        fi
    fi
    if [ "${_IGOR_OPENROUTER_GUARD:-false}" != true ] &&
       [ -z "${OPENROUTER_API_KEY:-}" ] && [ -f "$HOME/.nexus_or_key" ]; then
        _value="$(tr -d '[:space:]' < "$HOME/.nexus_or_key" 2>/dev/null)"
        if [ -n "$_value" ]; then
            export OPENROUTER_API_KEY="$_value"
            _cfg_log ok "Loaded key: ~/.nexus_or_key → \$OPENROUTER_API_KEY"
            (( _legacy_count++ )) || true
            (( _count++ )) || true
        fi
    fi
    [ $_legacy_count -gt 0 ] && \
        _cfg_log info "  (to migrate: cp ~/.nexus_api_key secrets/anthropic.key; chmod 600 secrets/anthropic.key)"

    [ $_count -eq 0 ] && _cfg_log warn "No API keys found — add secrets/anthropic.key or configure via AI menu"
    return 0
}

# ---------------------------------------------------------------------------
# _cfg_load_legacy_root_env
#   Step 4: Backward compat — source root-level *.env files if present.
#   Emits one deprecation warning per file found.
# ---------------------------------------------------------------------------
_cfg_load_legacy_root_env() {
    local _root="${IGOR_DIR:-$_IGOR_CFG_DIR}"
    local _file _found=0

    for _file in "${_root}"/*.env; do
        [ -f "$_file" ] || continue
        _found=1
        _cfg_log warn "DEPRECATED: root-level env file found: $(basename "$_file")"
        _cfg_log warn "  → Move to variables/ (settings) or secrets/ (credentials)"
        if _cfg_source_env "$_file" false; then
            _cfg_log info "  Loaded (legacy): $(basename "$_file")"
        fi
    done

    [ $_found -eq 0 ] && return 0
    _cfg_log warn "Legacy root env files will stop loading in a future release."
    return 0
}

# ---------------------------------------------------------------------------
# igor_validate_module_config <module_name>
#
#   Check that a loaded module's declared variables_file and secrets_files
#   actually exist on disk. Logs warnings for missing files.
#   Requires _IGOR_MODULE_DIRS to be populated (run igor_discover_modules first).
#
#   Returns 0 if all declared files exist, 1 if any are missing.
# ---------------------------------------------------------------------------
igor_validate_module_config() {
    local _name="$1"
    [ -n "$_name" ] || return 1

    # _IGOR_MODULE_DIRS is populated by module_loader.sh
    local _dir="${_IGOR_MODULE_DIRS[$_name]:-}"
    if [ -z "$_dir" ]; then
        _cfg_log warn "Cannot validate $_name: not in module registry"
        return 1
    fi

    local _any_missing=0
    local _root="${IGOR_DIR:-$_IGOR_CFG_DIR}"

    # Check variables_file
    local _vars_file
    _vars_file="$(_cfg_read_conf "$_dir" "variables_file" 2>/dev/null || echo "")"
    if [ -n "$_vars_file" ]; then
        local _vpath="${_root}/${_vars_file}"
        if [ ! -f "$_vpath" ]; then
            _cfg_log warn "Module $_name: variables_file not found: ${_vars_file}"
            _any_missing=1
        fi
    fi

    # Check secrets_files (comma or space separated)
    local _sec_files
    _sec_files="$(_cfg_read_conf "$_dir" "secrets_files" 2>/dev/null || echo "")"
    _sec_files="${_sec_files//,/ }"
    local _sf
    for _sf in $_sec_files; do
        [ -n "$_sf" ] || continue
        local _spath="${_root}/${_sf}"
        if [ ! -f "$_spath" ]; then
            _cfg_log warn "Module $_name: secrets_file not found: ${_sf}"
            _any_missing=1
        fi
    done

    return $_any_missing
}

# Reuse the same conf parser as module_loader uses (avoid duplicate)
_cfg_read_conf() {
    local _dir="$1" _key="$2"
    local _conf="${_dir}/module.conf"
    [ -f "$_conf" ] || return 1
    grep -m1 "^${_key}[[:space:]]*=" "$_conf" 2>/dev/null \
        | sed 's/^[^=]*=[[:space:]]*//' \
        | sed 's/[[:space:]]*$//'
}

# ---------------------------------------------------------------------------
# _cfg_validate_all_loaded_modules
#   Step 5: Run igor_validate_module_config for every loaded module.
#   Requires _IGOR_LOADED_MODULES to be populated.
# ---------------------------------------------------------------------------
_cfg_validate_all_loaded_modules() {
    # _IGOR_LOADED_MODULES is set by module_loader.sh
    if ! declare -p _IGOR_LOADED_MODULES >/dev/null 2>&1; then
        _cfg_log info "Module loader not yet run — skipping module config validation"
        return 0
    fi

    local _name
    for _name in "${!_IGOR_LOADED_MODULES[@]}"; do
        # A loaded function can remain in this process after its owner is
        # disabled; only active owners may contribute validation.
        declare -f igor_has_module >/dev/null 2>&1 || continue
        igor_has_module "$_name" || continue
        igor_validate_module_config "$_name"
    done
    return 0
}

# ---------------------------------------------------------------------------
# _cfg_load_defaults
#   Step 0: Load default configuration from core/config/defaults.conf
# ---------------------------------------------------------------------------
_cfg_load_defaults() {
    local _defaults_file="${IGOR_DIR:-$_IGOR_CFG_DIR}/core/config/defaults.conf"
    [ -f "$_defaults_file" ] || return 0

    _cfg_log info "Loading default configuration..."
    
    # Source defaults with set -a to export all variables
    set -a
    # shellcheck disable=SC1090
    source "$_defaults_file" 2>/tmp/_igor_cfg_defaults_err
    local _rc=$?
    set +a
    _cfg_fence_openrouter_aliases

    if [ $_rc -ne 0 ]; then
        _cfg_log error "Failed to load defaults: $(cat /tmp/_igor_cfg_defaults_err 2>/dev/null)"
        return 1
    fi

    _cfg_log ok "Loaded default configuration"
    return 0
}

# ---------------------------------------------------------------------------
# igor_load_config
#
#   Master entry point. Run all six loading steps in order.
# ---------------------------------------------------------------------------
igor_load_config() {
    _IGOR_OPENROUTER_GUARD=false
    _cfg_openrouter_cutover && _IGOR_OPENROUTER_GUARD=true
    _cfg_fence_openrouter_aliases
    _cfg_load_defaults        # Load centralized defaults first
    _cfg_load_variables       # Then variables/*.env (overrides defaults)
    _cfg_load_secrets_env     # Then secrets/*.env — credentials + site overrides
    _cfg_load_key_files       # Then secrets/*.key (API keys)
    _cfg_load_legacy_root_env # Backward compatibility
    _cfg_validate_all_loaded_modules
    _IGOR_CONFIG_LOADED=true
}

# ---------------------------------------------------------------------------
# igor_get_config <key> [default_value]
#   Get a configuration value, with optional default
# ---------------------------------------------------------------------------
igor_get_config() {
    local _key="$1"
    local _default="${2:-}"
    
    [ -n "$_key" ] || { echo "$_default"; return 1; }
    
    # Use parameter expansion to get the value, or default if not set
    echo "${!_key:-$_default}"
}

# ---------------------------------------------------------------------------
# igor_get_port <service> [default_port]
#   Get a port configuration for a specific service
# ---------------------------------------------------------------------------
igor_get_port() {
    local _service="$1"
    local _default="${2:-}"
    
    case "$_service" in
        "nextcloud_http")
            igor_get_config "NEXTCLOUD_HTTP_PORT" "$_default"
            ;;
        "nextcloud_fpm")
            igor_get_config "NEXTCLOUD_FPM_PORT" "$_default"
            ;;
        "postgres")
            igor_get_config "POSTGRES_PORT" "$_default"
            ;;
        "redis")
            igor_get_config "REDIS_PORT" "$_default"
            ;;
        "onlyoffice")
            igor_get_config "ONLYOFFICE_PORT" "$_default"
            ;;
        *)
            echo "$_default"
            return 1
            ;;
    esac
}


# ---------------------------------------------------------------------------
# igor_show_config
#   Display current configuration values
# ---------------------------------------------------------------------------
igor_show_config() {
    echo "=== IGOR Configuration ==="
    # Show key configuration values
    for _var in NEXTCLOUD_HTTP_PORT NEXTCLOUD_FPM_PORT POSTGRES_PORT REDIS_PORT IGOR_DATA_DIR IGOR_WEB_DIR; do
        [ -n "${!_var:-}" ] && echo "$_var=${!_var}"
    done | sort
    echo "========================="
}
