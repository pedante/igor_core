#!/bin/bash
# =============================================================================
# MODULE LOADER FAST PATH — Boundary H
#
# Installed after the base loader definitions. It compiles Module API v2
# structural metadata once per package generation and keeps runtime/host truth
# at the existing requirement and capability boundaries.
# =============================================================================

_ml_fast_clone_function() {
    local _old="$1" _new="$2" _definition
    _definition="$(declare -f "$_old")" || return 1
    eval "$_new${_definition#"$_old"}"
}

_ml_fast_clone_function _ml_v2_query _ml_v2_query_legacy
_ml_fast_clone_function _ml_v2_rows _ml_v2_rows_legacy
_ml_fast_clone_function _ml_v2_record _ml_v2_record_legacy
_ml_fast_clone_function _ml_v2_module_requirements _ml_v2_module_requirements_legacy
_ml_fast_clone_function _ml_v2_validate _ml_v2_validate_legacy
_ml_fast_clone_function _ml_load_v2 _ml_load_v2_legacy
_ml_fast_clone_function igor_load_all_modules igor_load_all_modules_legacy
unset -f _ml_fast_clone_function

declare -gA _IGOR_V2_VALIDATION_ERROR 2>/dev/null || true
declare -gA _IGOR_V2_ROWS_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_RECORD_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_RECORD_SOURCE_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_MODULE_REQUIREMENTS_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_ENTRYPOINT_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_VERSION_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_V1_HOOKS_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_MOD_REQ_MODULES 2>/dev/null || true
declare -gA _IGOR_V2_MOD_REQ_CAPABILITIES 2>/dev/null || true
declare -gA _IGOR_V2_MOD_REQ_FAMILIES 2>/dev/null || true
declare -gA _IGOR_V2_MOD_REQ_BINS 2>/dev/null || true
declare -gA _IGOR_V2_REQ_MODULES_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_REQ_CAPABILITIES_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_REQ_FEATURES_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_REQ_FAMILIES_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_REQ_BINS_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_HANDLER_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_TIMEOUT_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_CAP_DEPS_COMPILED 2>/dev/null || true
declare -gA _IGOR_V2_STATIC_REASON_COMPILED 2>/dev/null || true
declare -g _IGOR_V2_COMPILED_READY=0
declare -g _IGOR_MODULE_V2_CACHE_STATE=none

_ml_v2_compiled_reset() {
    _IGOR_V2_VALIDATION_ERROR=()
    _IGOR_V2_ROWS_COMPILED=()
    _IGOR_V2_RECORD_COMPILED=()
    _IGOR_V2_RECORD_SOURCE_COMPILED=()
    _IGOR_V2_MODULE_REQUIREMENTS_COMPILED=()
    _IGOR_V2_ENTRYPOINT_COMPILED=()
    _IGOR_V2_VERSION_COMPILED=()
    _IGOR_V2_V1_HOOKS_COMPILED=()
    _IGOR_V2_MOD_REQ_MODULES=()
    _IGOR_V2_MOD_REQ_CAPABILITIES=()
    _IGOR_V2_MOD_REQ_FAMILIES=()
    _IGOR_V2_MOD_REQ_BINS=()
    _IGOR_V2_REQ_MODULES_COMPILED=()
    _IGOR_V2_REQ_CAPABILITIES_COMPILED=()
    _IGOR_V2_REQ_FEATURES_COMPILED=()
    _IGOR_V2_REQ_FAMILIES_COMPILED=()
    _IGOR_V2_REQ_BINS_COMPILED=()
    _IGOR_V2_HANDLER_COMPILED=()
    _IGOR_V2_TIMEOUT_COMPILED=()
    _IGOR_V2_CAP_DEPS_COMPILED=()
    _IGOR_V2_STATIC_REASON_COMPILED=()
    _IGOR_V2_DATA=()
    _IGOR_V2_COMPILED_READY=0
    _IGOR_MODULE_V2_CACHE_STATE=none
}

_ml_fast_read_field() {
    local _fd="$1" _target="$2" _value
    IFS= read -r -d '' _value <&$_fd || return 1
    printf -v "$_target" '%s' "$_value"
}

_ml_v2_prepare_compiled() {
    _ml_v2_compiled_reset
    local _name _py _cache _tag _status _error _data _entrypoint _version _v1_hooks
    local _module_requires _req_modules _req_caps _req_families _req_bins _rows
    local _owner _key _record _source _req_features _handler _timeout _deps _static_reason
    local _compiled_key _cache_state _complete=false _fd
    local -a _dirs=()

    for _name in "${!_IGOR_MODULE_DIRS[@]}"; do
        [ "${_IGOR_MODULE_API[$_name]:-1}" = 2 ] || continue
        _dirs+=("${_IGOR_MODULE_DIRS[$_name]}")
    done
    if [ "${#_dirs[@]}" -eq 0 ]; then
        _IGOR_V2_COMPILED_READY=1
        _IGOR_MODULE_V2_CACHE_STATE=none
        return 0
    fi

    _py="$(_ml_python)"
    command -v "$_py" >/dev/null 2>&1 || return 1
    [ -f "${_IGOR_LOADER_DIR}/core/lib/module_registry.py" ] || return 1
    _cache="${IGOR_DATA_DIR:-${IGOR_DIR:-$_IGOR_LOADER_DIR}/data}/cache/module-registry-v2.json"

    exec {_fd}< <(
        "$_py" "${_IGOR_LOADER_DIR}/core/lib/module_registry.py" emit "$_cache" "${_dirs[@]}" 2>/dev/null
    ) || return 1

    while IFS= read -r -d '' _tag <&$_fd; do
        case "$_tag" in
            MODULE)
                _ml_fast_read_field "$_fd" _name || break
                _ml_fast_read_field "$_fd" _status || break
                _ml_fast_read_field "$_fd" _error || break
                _ml_fast_read_field "$_fd" _data || break
                _ml_fast_read_field "$_fd" _entrypoint || break
                _ml_fast_read_field "$_fd" _version || break
                _ml_fast_read_field "$_fd" _v1_hooks || break
                _ml_fast_read_field "$_fd" _module_requires || break
                _ml_fast_read_field "$_fd" _req_modules || break
                _ml_fast_read_field "$_fd" _req_caps || break
                _ml_fast_read_field "$_fd" _req_families || break
                _ml_fast_read_field "$_fd" _req_bins || break
                _ml_fast_read_field "$_fd" _rows || break
                if [ "$_status" = ok ]; then
                    _IGOR_V2_DATA["$_name"]="$_data"
                    _IGOR_V2_ENTRYPOINT_COMPILED["$_name"]="$_entrypoint"
                    _IGOR_V2_VERSION_COMPILED["$_name"]="$_version"
                    _IGOR_V2_V1_HOOKS_COMPILED["$_name"]="$_v1_hooks"
                    _IGOR_V2_MODULE_REQUIREMENTS_COMPILED["$_name"]="$_module_requires"
                    _IGOR_V2_MOD_REQ_MODULES["$_name"]="$_req_modules"
                    _IGOR_V2_MOD_REQ_CAPABILITIES["$_name"]="$_req_caps"
                    _IGOR_V2_MOD_REQ_FAMILIES["$_name"]="$_req_families"
                    _IGOR_V2_MOD_REQ_BINS["$_name"]="$_req_bins"
                    _IGOR_V2_ROWS_COMPILED["$_name"]="$_rows"
                else
                    _IGOR_V2_VALIDATION_ERROR["$_name"]="$_error"
                fi
                ;;
            CONTRIBUTION)
                _ml_fast_read_field "$_fd" _owner || break
                _ml_fast_read_field "$_fd" _key || break
                _ml_fast_read_field "$_fd" _record || break
                _ml_fast_read_field "$_fd" _source || break
                _ml_fast_read_field "$_fd" _req_modules || break
                _ml_fast_read_field "$_fd" _req_caps || break
                _ml_fast_read_field "$_fd" _req_features || break
                _ml_fast_read_field "$_fd" _req_families || break
                _ml_fast_read_field "$_fd" _req_bins || break
                _ml_fast_read_field "$_fd" _handler || break
                _ml_fast_read_field "$_fd" _timeout || break
                _ml_fast_read_field "$_fd" _deps || break
                _ml_fast_read_field "$_fd" _static_reason || break
                _compiled_key="${_owner}|${_key}"
                _IGOR_V2_RECORD_COMPILED["$_compiled_key"]="$_record"
                _IGOR_V2_RECORD_SOURCE_COMPILED["$_compiled_key"]="$_source"
                _IGOR_V2_REQ_MODULES_COMPILED["$_compiled_key"]="$_req_modules"
                _IGOR_V2_REQ_CAPABILITIES_COMPILED["$_compiled_key"]="$_req_caps"
                _IGOR_V2_REQ_FEATURES_COMPILED["$_compiled_key"]="$_req_features"
                _IGOR_V2_REQ_FAMILIES_COMPILED["$_compiled_key"]="$_req_families"
                _IGOR_V2_REQ_BINS_COMPILED["$_compiled_key"]="$_req_bins"
                _IGOR_V2_HANDLER_COMPILED["$_compiled_key"]="$_handler"
                _IGOR_V2_TIMEOUT_COMPILED["$_compiled_key"]="$_timeout"
                _IGOR_V2_CAP_DEPS_COMPILED["$_compiled_key"]="$_deps"
                _IGOR_V2_STATIC_REASON_COMPILED["$_compiled_key"]="$_static_reason"
                ;;
            END)
                _ml_fast_read_field "$_fd" _cache_state || break
                _IGOR_MODULE_V2_CACHE_STATE="$_cache_state"
                _complete=true
                break
                ;;
            *) break ;;
        esac
    done
    exec {_fd}<&-

    if [ "$_complete" != true ]; then
        _ml_v2_compiled_reset
        _IGOR_MODULE_V2_CACHE_STATE=fallback
        return 1
    fi
    _IGOR_V2_COMPILED_READY=1
    return 0
}

_ml_v2_emit_words() {
    local _item
    for _item in $1; do
        printf '%s\n' "$_item"
    done
}

_ml_v2_query() {
    local _name="$1" _path="$2"
    if [ "${_IGOR_V2_COMPILED_READY:-0}" -eq 1 ] &&
       [ -n "${_IGOR_V2_DATA[$_name]:-}" ]; then
        case "$_path" in
            manifest.entrypoint)
                printf '%s\n' "${_IGOR_V2_ENTRYPOINT_COMPILED[$_name]:-}"; return 0 ;;
            manifest.version)
                printf '%s\n' "${_IGOR_V2_VERSION_COMPILED[$_name]:-}"; return 0 ;;
            manifest.compat.v1_hooks)
                printf '%s\n' "${_IGOR_V2_V1_HOOKS_COMPILED[$_name]:-false}"; return 0 ;;
            manifest.requirements.required_modules)
                _ml_v2_emit_words "${_IGOR_V2_MOD_REQ_MODULES[$_name]:-}"; return 0 ;;
            manifest.requirements.required_capabilities)
                _ml_v2_emit_words "${_IGOR_V2_MOD_REQ_CAPABILITIES[$_name]:-}"; return 0 ;;
            manifest.requirements.platform_families)
                _ml_v2_emit_words "${_IGOR_V2_MOD_REQ_FAMILIES[$_name]:-}"; return 0 ;;
            manifest.requirements.required_bins)
                _ml_v2_emit_words "${_IGOR_V2_MOD_REQ_BINS[$_name]:-}"; return 0 ;;
        esac
    fi
    _ml_v2_query_legacy "$@"
}

_ml_v2_rows() {
    local _name="$1"
    if [ -n "${_IGOR_V2_ROWS_COMPILED[$_name]+set}" ]; then
        [ -n "${_IGOR_V2_ROWS_COMPILED[$_name]}" ] &&
            printf '%s\n' "${_IGOR_V2_ROWS_COMPILED[$_name]}"
        return 0
    fi
    _ml_v2_rows_legacy "$@"
}

_ml_v2_record() {
    local _name="$1" _key="$2" _compiled_key="$1|$2"
    if [ -n "${_IGOR_V2_RECORD_COMPILED[$_compiled_key]+set}" ]; then
        printf '%s\n' "${_IGOR_V2_RECORD_COMPILED[$_compiled_key]}"
        return 0
    fi
    _ml_v2_record_legacy "$@"
}

_ml_v2_module_requirements() {
    local _name="$1"
    if [ -n "${_IGOR_V2_MODULE_REQUIREMENTS_COMPILED[$_name]+set}" ]; then
        printf '%s\n' "${_IGOR_V2_MODULE_REQUIREMENTS_COMPILED[$_name]}"
        return 0
    fi
    _ml_v2_module_requirements_legacy "$@"
}

_ml_v2_validate() {
    local _name="$1"
    if [ -n "${_IGOR_V2_VALIDATION_ERROR[$_name]+set}" ]; then
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="${_IGOR_V2_VALIDATION_ERROR[$_name]}"
        return 1
    fi
    if [ -n "${_IGOR_V2_DATA[$_name]:-}" ]; then
        return 0
    fi
    _ml_v2_validate_legacy "$@"
}

_ml_v2_prepare_all() {
    local _name _api
    _ml_v2_prepare_compiled || true
    for _name in "${!_IGOR_MODULE_DIRS[@]}"; do
        _api="${_IGOR_MODULE_API[$_name]:-1}"
        case "$_api" in
            1) ;;
            2)
                _ml_v2_validate "$_name" || true
                if ! igor_module_enabled "$_name"; then
                    _IGOR_MODULE_STATUS["$_name"]="disabled"
                fi
                ;;
            *)
                if igor_module_enabled "$_name"; then
                    _IGOR_MODULE_STATUS["$_name"]="unavailable"
                fi
                _IGOR_MODULE_REASON["$_name"]="unsupported or malformed module_api: $_api"
                ;;
        esac
    done
}

_ml_v2_module_requirement_failure_fast() {
    local _name="$1" _item _family
    local -a _items=()

    read -r -a _items <<< "${_IGOR_V2_MOD_REQ_MODULES[$_name]:-}"
    for _item in "${_items[@]}"; do
        [ -n "$_item" ] || continue
        if ! igor_has_module "$_item"; then
            printf 'required module %s is %s%s' "$_item" \
                "${_IGOR_MODULE_STATUS[$_item]:-missing}" \
                "${_IGOR_MODULE_REASON[$_item]:+ (${_IGOR_MODULE_REASON[$_item]})}"
            return 1
        fi
    done

    read -r -a _items <<< "${_IGOR_V2_MOD_REQ_CAPABILITIES[$_name]:-}"
    for _item in "${_items[@]}"; do
        [ -n "$_item" ] || continue
        _ml_v2_capability_reason "$_item" || return 1
    done

    if [ -n "${_IGOR_V2_MOD_REQ_FAMILIES[$_name]:-}" ]; then
        if [ -z "${IGOR_DISTRO_FAMILY:-}" ]; then
            source "${_IGOR_LOADER_DIR}/core/lib/distro.sh"
            igor_detect_distro
        fi
        _family="${IGOR_DISTRO_FAMILY:-unknown}"
        case " ${_IGOR_V2_MOD_REQ_FAMILIES[$_name]} " in
            *" $_family "*) ;;
            *)
                printf 'platform family %s is outside allowed set %s' \
                    "$_family" "${_IGOR_V2_MOD_REQ_FAMILIES[$_name]// /, }"
                return 1
                ;;
        esac
    fi

    read -r -a _items <<< "${_IGOR_V2_MOD_REQ_BINS[$_name]:-}"
    for _item in "${_items[@]}"; do
        [ -n "$_item" ] || continue
        if ! command -v "$_item" >/dev/null 2>&1; then
            printf 'required binary %s is missing' "$_item"
            return 1
        fi
    done
    return 0
}

_ml_fast_index_compiled_fields() {
    local _name="$1" _key="$2" _index_key="$3" _compiled_key="$1|$2"
    [ -n "${_IGOR_V2_RECORD_COMPILED[$_compiled_key]+set}" ] || return 1

    _IGOR_REQ_INDEXED["$_index_key"]=1
    _IGOR_REQ_MODULES["$_index_key"]="${_IGOR_V2_REQ_MODULES_COMPILED[$_compiled_key]:-}"
    _IGOR_REQ_CAPABILITIES["$_index_key"]="${_IGOR_V2_REQ_CAPABILITIES_COMPILED[$_compiled_key]:-}"
    _IGOR_REQ_PLATFORM_FEATURES["$_index_key"]="${_IGOR_V2_REQ_FEATURES_COMPILED[$_compiled_key]:-}"
    _IGOR_REQ_PLATFORM_FAMILIES["$_index_key"]="${_IGOR_V2_REQ_FAMILIES_COMPILED[$_compiled_key]:-}"
    _IGOR_REQ_BINS["$_index_key"]="${_IGOR_V2_REQ_BINS_COMPILED[$_compiled_key]:-}"
    _IGOR_CAPABILITY_DEPENDENCIES["$_index_key"]="${_IGOR_V2_CAP_DEPS_COMPILED[$_compiled_key]:-}"
    if [ -n "${_IGOR_V2_HANDLER_COMPILED[$_compiled_key]:-}" ]; then
        _IGOR_HANDLER_FUNCTION["$_index_key"]="${_IGOR_V2_HANDLER_COMPILED[$_compiled_key]}"
        _IGOR_HANDLER_TIMEOUT["$_index_key"]="${_IGOR_V2_TIMEOUT_COMPILED[$_compiled_key]:-30}"
    fi
    return 0
}

_ml_load_v2() {
    local _name="$1" _dir="${_IGOR_MODULE_DIRS[$1]}" _reason _key _index_key _record _source
    local _entrypoint _kind _compiled_key _static_reason
    local _phase_started=""
    [ "${IGOR_TUI_MODE:-false}" = true ] && _phase_started="$(_ml_now_ms)"

    if [ "${_IGOR_V2_COMPILED_READY:-0}" -ne 1 ] ||
       [ -z "${_IGOR_V2_DATA[$_name]:-}" ] ||
       [ -z "${_IGOR_V2_ROWS_COMPILED[$_name]+set}" ]; then
        _ml_load_v2_legacy "$@"
        return $?
    fi
    if [ "$_name" = system ] && [ "${_IGOR_SYSTEM_POLICY_MIGRATION_FAILED:-0}" -eq 1 ]; then
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="system policy migration failed; config/modules.conf is not writable"
        return 1
    fi
    if [ "${_IGOR_MODULE_API[$_name]:-}" != 2 ]; then
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="unsupported or malformed module_api: ${_IGOR_MODULE_API[$_name]:-missing}"
        return 1
    fi

    _entrypoint="${_IGOR_V2_ENTRYPOINT_COMPILED[$_name]:-}"
    _IGOR_MODULE_ENTRYPOINT["$_name"]="$_entrypoint"
    _IGOR_MODULE_VERSION["$_name"]="${_IGOR_V2_VERSION_COMPILED[$_name]:-}"
    _IGOR_OWNER_HAS_DOMAIN_EVENTS["$_name"]=0

    _reason="$(_ml_v2_module_requirement_failure_fast "$_name")" || {
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="$_reason"
        return 1
    }

    while IFS= read -r _key; do
        [ -n "$_key" ] || continue
        if [ -n "${_IGOR_CONTRIBUTIONS[$_key]:-}" ] &&
           [ "${_IGOR_CONTRIBUTION_OWNER[$_key]:-}" != "$_name" ]; then
            case "$_key" in
                capability:*) ;;
                *)
                    _IGOR_MODULE_STATUS["$_name"]="unavailable"
                    _IGOR_MODULE_REASON["$_name"]="duplicate contribution $_key owned by ${_IGOR_CONTRIBUTION_OWNER[$_key]}"
                    return 1
                    ;;
            esac
        fi
    done < <(_ml_v2_rows "$_name")
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _ml_tui_phase_record "$_name.v2.preflight" "$_phase_started"
        _phase_started="$(_ml_now_ms)"
    fi

    if [ "${_IGOR_V2_V1_HOOKS_COMPILED[$_name]:-false}" = true ]; then
        local _register_fn
        if [ -z "$_entrypoint" ]; then
            _IGOR_MODULE_STATUS["$_name"]="unavailable"
            _IGOR_MODULE_REASON["$_name"]="v1_hooks requires a Bash entrypoint"
            return 1
        fi
        _register_fn="${_name}__register"
        # shellcheck disable=SC1090
        if ! source "$_dir/$_entrypoint"; then
            _IGOR_MODULE_STATUS["$_name"]="unavailable"
            _IGOR_MODULE_REASON["$_name"]="Bash entrypoint source failed"
            return 1
        fi
        if ! declare -f "$_register_fn" >/dev/null 2>&1; then
            _IGOR_MODULE_STATUS["$_name"]="unavailable"
            _IGOR_MODULE_REASON["$_name"]="v1 compatibility registration function $_register_fn missing"
            return 1
        fi
        _IGOR_REGISTERING_MODULE="$_name"
        if ! "$_register_fn"; then
            _IGOR_REGISTERING_MODULE=""
            _IGOR_MODULE_STATUS["$_name"]="unavailable"
            _IGOR_MODULE_REASON["$_name"]="v1 compatibility registration failed"
            return 1
        fi
        _IGOR_REGISTERING_MODULE=""
    fi
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _ml_tui_phase_record "$_name.v2.compat" "$_phase_started"
        _phase_started="$(_ml_now_ms)"
    fi

    while IFS= read -r _key; do
        [ -n "$_key" ] || continue
        _compiled_key="${_name}|${_key}"
        _record="${_IGOR_V2_RECORD_COMPILED[$_compiled_key]:-}"
        [ -n "$_record" ] || continue
        _source="${_IGOR_V2_RECORD_SOURCE_COMPILED[$_compiled_key]:-}"
        _index_key="$_key"
        if [[ "$_key" = capability:* ]] &&
           [ -n "${_IGOR_CONTRIBUTION_OWNER[$_key]:-}" ] &&
           [ "${_IGOR_CONTRIBUTION_OWNER[$_key]}" != "$_name" ]; then
            _index_key="${_key}@${_name}"
        fi
        _ml_index_contribution "$_key" "$_name" "$_source" "$_record" || return 1
        _ml_fast_index_compiled_fields "$_name" "$_key" "$_index_key" || return 1
        _kind="${_key%%:*}"
        [ "$_kind" = domain_event ] && _IGOR_OWNER_HAS_DOMAIN_EVENTS["$_name"]=1

        _static_reason="${_IGOR_V2_STATIC_REASON_COMPILED[$_compiled_key]:-}"
        if [ -n "$_static_reason" ]; then
            _IGOR_CONTRIBUTION_STATE["$_index_key"]="unavailable"
            _IGOR_CONTRIBUTION_REASON["$_index_key"]="$_static_reason"
        fi
    done < <(_ml_v2_rows "$_name")
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _ml_tui_phase_record "$_name.v2.contributions" "$_phase_started"
        _phase_started="$(_ml_now_ms)"
    fi

    _IGOR_LOADED_MODULES["$_name"]=1
    _IGOR_MODULE_STATUS["$_name"]="active"
    unset '_IGOR_MODULE_REASON['"$_name"']'
    if [ "$_name" = system ] &&
       [ -n "${_IGOR_CONTRIBUTIONS[configuration:system.memory.preferences]:-}" ]; then
        unset IGOR_SYSTEM_MEMORY_WARNING_MIB IGOR_SYSTEM_MEMORY_WARNING_REVISION IGOR_SYSTEM_MEMORY_WARNING_STATE IGOR_SYSTEM_MEMORY_CONSUMER_ID
        _igor_configuration_memory_warning_load ||
            _ml_log warn "System memory configuration consumption unavailable"
    fi
    _ml_log ok "Loaded Module API v2: $_name"
    [ "${IGOR_TUI_MODE:-false}" = true ] &&
        _ml_tui_phase_record "$_name.v2.consumer" "$_phase_started"
    return 0
}

igor_load_all_modules() {
    local _timed=false _started=0 _ended=0
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _timed=true
        _started=$(date +%s%3N)
    fi

    igor_discover_modules > /dev/null
    if [ "$_timed" = true ]; then
        _ended=$(date +%s%3N)
        _IGOR_TUI_MODULE_DISCOVERY_MS=$((_ended - _started))
        _started=$_ended
    fi

    _ml_v2_prepare_all
    if [ "$_timed" = true ]; then
        _ended=$(date +%s%3N)
        _IGOR_TUI_MODULE_V2_REGISTRY_MS=$((_ended - _started))
        _started=$_ended
    fi

    local _names=("${!_IGOR_MODULE_DIRS[@]}")
    if [ "${#_names[@]}" -eq 0 ]; then
        if [ "$_timed" = true ]; then
            _IGOR_TUI_MODULE_SORT_MS=0
            _IGOR_TUI_MODULE_REGISTRATION_MS=0
        fi
        return 0
    fi
    mapfile -t _names < <(printf '%s\n' "${_names[@]}" | sort)

    local _sorted_list
    _sorted_list="$(igor_sort_modules "${_names[@]}")"
    if [ "$_timed" = true ]; then
        _ended=$(date +%s%3N)
        _IGOR_TUI_MODULE_SORT_MS=$((_ended - _started))
        _started=$_ended
    fi

    local _name _seen=" " _edges
    local _registration_started="$_started" _module_started="" _module_ended=""
    local _reconcile_started=""
    if [ "$_timed" = true ]; then
        _IGOR_TUI_MODULE_REGISTRATION_ORDER=""
        _IGOR_TUI_MODULE_REGISTRATION_BY_NAME=()
        _IGOR_TUI_MODULE_PHASE_MS=()
    fi
    while IFS= read -r _name; do
        [ -n "$_name" ] || continue
        _seen+="$_name "
        if [ "$_timed" = true ]; then
            _module_started="$(_ml_now_ms)"
            _IGOR_TUI_MODULE_REGISTRATION_ORDER+="${_IGOR_TUI_MODULE_REGISTRATION_ORDER:+ }$_name"
        fi
        igor_load_module "$_name" || true
        if [ "$_timed" = true ]; then
            _module_ended="$(_ml_now_ms)"
            if [[ "$_module_started" =~ ^[0-9]+$ ]] &&
               [[ "$_module_ended" =~ ^[0-9]+$ ]] &&
               [ "$_module_ended" -ge "$_module_started" ]; then
                _IGOR_TUI_MODULE_REGISTRATION_BY_NAME["$_name"]=$((_module_ended - _module_started))
            fi
        fi
    done <<< "$_sorted_list"

    [ "$_timed" = true ] && _reconcile_started="$(_ml_now_ms)"
    for _name in "${_names[@]}"; do
        if [[ "$_seen" != *" $_name "* ]] &&
           [ "${_IGOR_MODULE_STATUS[$_name]:-}" != disabled ]; then
            _IGOR_MODULE_STATUS["$_name"]="unavailable"
            if [ "${_IGOR_MODULE_API[$_name]:-1}" = 2 ]; then
                _edges="$(_ml_v2_query "$_name" manifest.requirements.required_modules 2>/dev/null)"
                _edges="${_edges//$'\n'/, }"
                [ -n "$_edges" ] ||
                    _edges="$(_ml_v2_query "$_name" manifest.requirements.required_capabilities 2>/dev/null)"
            else
                _edges="$(_ml_read_conf "${_IGOR_MODULE_DIRS[$_name]}" depends_on 2>/dev/null)"
            fi
            _IGOR_MODULE_REASON["$_name"]="dependency ordering cycle blocks $_name (declared edges: ${_edges:-unknown})"
        fi
    done

    if [ "$_timed" = true ]; then
        _ended="$(_ml_now_ms)"
        if [[ "$_reconcile_started" =~ ^[0-9]+$ ]] &&
           [ "$_ended" -ge "$_reconcile_started" ]; then
            _IGOR_TUI_MODULE_REGISTRATION_RECONCILE_MS=$((_ended - _reconcile_started))
        fi
        _IGOR_TUI_MODULE_REGISTRATION_MS=$((_ended - _registration_started))
    fi
    return 0
}
