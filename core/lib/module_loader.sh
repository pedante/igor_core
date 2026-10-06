#!/bin/bash
# =============================================================================
#  MODULE LOADER — core/lib/module_loader.sh
#
#  Discovers, sorts, loads, and registers Igor modules.
#
#  Public API:
#    igor_discover_modules   — scan modules/, return sorted name list
#    igor_sort_modules       — topological sort by depends_on
#    igor_load_module        — syntax-check, dep-check, source, call __register
#    igor_register_hook      — add function to named hook
#    igor_run_all_hooks      — run all functions for a hook (timeout 30)
#    igor_get_hooks          — echo functions registered for a hook
#    igor_has_bin            — test if a binary is on PATH
#    igor_has_module         — test if a module has been loaded
#
#  All functions are safe to call multiple times (idempotent discovery).
#  Errors are logged but never fatal — a broken module is skipped, not a crash.
# =============================================================================

# Hook registry: _IGOR_HOOKS[hook_name]="fn1 fn2 fn3"
declare -gA _IGOR_HOOKS 2>/dev/null || true

# Loaded module tracker: _IGOR_LOADED_MODULES["name"]=1
declare -gA _IGOR_LOADED_MODULES 2>/dev/null || true

# Capability catalog: _IGOR_CAPABILITIES[action_name]="description|function|load_module|tier|problems|menu_path"
# Populated by igor_load_capabilities() at AI session start from ai_capabilities hooks.
declare -gA _IGOR_CAPABILITIES 2>/dev/null || true

# Menu registry: _IGOR_MENU_REGISTRY[key]="label|load_type|load_arg|menu_func"
#   load_type: "module" → _igor_load_module arg  |  "subsystem" → _igor_load_subsystem label path
#   Modules call igor_register_menu_item to add entries here.
#   The main menu dispatcher checks this registry in the *) catch-all.
declare -gA _IGOR_MENU_REGISTRY 2>/dev/null || true

# Module lifecycle state.  The registry is deliberately a data-only file;
# module.conf remains the source of metadata and dependency declarations.
declare -gA _IGOR_MODULE_STATE 2>/dev/null || true
declare -gA _IGOR_MODULE_REASON 2>/dev/null || true
declare -gA _IGOR_MODULE_STATUS 2>/dev/null || true
declare -gA _IGOR_HOOK_OWNERS 2>/dev/null || true
declare -gA _IGOR_MENU_OWNERS 2>/dev/null || true
declare -gA _IGOR_CAPABILITY_OWNERS 2>/dev/null || true
declare -gA _IGOR_MODULE_API 2>/dev/null || true
declare -gA _IGOR_V2_DATA 2>/dev/null || true
declare -gA _IGOR_CONTRIBUTIONS 2>/dev/null || true
declare -gA _IGOR_CONTRIBUTION_STATE 2>/dev/null || true
declare -gA _IGOR_CONTRIBUTION_REASON 2>/dev/null || true
declare -gA _IGOR_CONTRIBUTION_OWNER 2>/dev/null || true
declare -gA _IGOR_CONTRIBUTION_SOURCE 2>/dev/null || true
declare -gA _IGOR_REQ_INDEXED 2>/dev/null || true
declare -gA _IGOR_REQ_MODULES 2>/dev/null || true
declare -gA _IGOR_REQ_CAPABILITIES 2>/dev/null || true
declare -gA _IGOR_REQ_PLATFORM_FEATURES 2>/dev/null || true
declare -gA _IGOR_REQ_PLATFORM_FAMILIES 2>/dev/null || true
declare -gA _IGOR_REQ_BINS 2>/dev/null || true
# Static Module API v2 handler metadata compiled at load time. Dynamic
# contribution/module availability is still checked at invocation.
declare -gA _IGOR_HANDLER_FUNCTION 2>/dev/null || true
declare -gA _IGOR_HANDLER_TIMEOUT 2>/dev/null || true
declare -gA _IGOR_MODULE_ENTRYPOINT 2>/dev/null || true
declare -gA _IGOR_OWNER_HAS_DOMAIN_EVENTS 2>/dev/null || true
declare -gA _IGOR_MODULE_VERSION 2>/dev/null || true
declare -gA _IGOR_CAPABILITY_DEPENDENCIES 2>/dev/null || true
# Boundary N diagnostics. These are observations only and are populated only
# for the standalone TUI startup path.
declare -gA _IGOR_TUI_MODULE_REGISTRATION_BY_NAME 2>/dev/null || true
declare -gA _IGOR_TUI_MODULE_PHASE_MS 2>/dev/null || true
declare -g _IGOR_TUI_MODULE_REGISTRATION_ORDER=""
declare -g _IGOR_REGISTERING_MODULE=""
declare -g _IGOR_MODULE_CONFIG_LOADED="${_IGOR_MODULE_CONFIG_LOADED:-0}"
declare -g _IGOR_SYSTEM_POLICY_MIGRATION_FAILED=0

# Root of the Igor installation — resolved relative to this file's location
_IGOR_LOADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && cd ../.. && pwd)"
# shellcheck source=core/lib/domain_event.sh
source "${_IGOR_LOADER_DIR}/core/lib/domain_event.sh"
# shellcheck source=core/lib/observation.sh
source "${_IGOR_LOADER_DIR}/core/lib/observation.sh"
# shellcheck source=core/lib/capability.sh
source "${_IGOR_LOADER_DIR}/core/lib/capability.sh"

# ---------------------------------------------------------------------------
# _ml_log <level> <message>
#   Internal logging. Human sessions get normal diagnostics. Structured CLI
#   surfaces suppress non-fatal loader chatter so their output remains a clean
#   machine interface; fatal loader errors still go to stderr.
# ---------------------------------------------------------------------------
_ml_log() {
    local _level="$1"; shift
    local _msg="$*"
    if [ "${IGOR_STRUCTURED_OUTPUT:-false}" = true ] && [ "$_level" != error ]; then
        return 0
    fi
    case "$_level" in
        ok)    printf '  [module_loader] ✔  %s\n' "$_msg" ;;
        info)  printf '  [module_loader]    %s\n' "$_msg" ;;
        warn)  printf '  [module_loader] ⚠  %s\n' "$_msg" >&2 ;;
        error) printf '  [module_loader] ✗  %s\n' "$_msg" >&2 ;;
    esac
}

_ml_valid_name() { [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; }

# Millisecond clock used only by diagnostic startup instrumentation. Bash 5's
# EPOCHREALTIME avoids spawning `date` for every subphase; older shells retain
# a compatible fallback.
_ml_now_ms() {
    local _raw
    if [ -n "${EPOCHREALTIME:-}" ]; then
        _raw="${EPOCHREALTIME/./}"
        printf '%s' "$((10#$_raw / 1000))"
    else
        date +%s%3N
    fi
}

_ml_tui_phase_record() {
    [ "${IGOR_TUI_MODE:-false}" = true ] || return 0
    local _key="${1:-}" _started="${2:-}" _ended
    [ -n "$_key" ] || return 0
    _ended="$(_ml_now_ms)"
    if [[ "$_started" =~ ^[0-9]+$ ]] && [[ "$_ended" =~ ^[0-9]+$ ]] &&
       [ "$_ended" -ge "$_started" ]; then
        _IGOR_TUI_MODULE_PHASE_MS["$_key"]=$((_ended - _started))
    fi
}

# This probe only selects the parser. V2 validity is decided by the strict
# validator before executable code is touched. V1 deliberately keeps its old
# section-blind parser.
_ml_probe_api() {
    local _file="$1/module.conf" _line _value _seen=0 _section=""
    while IFS= read -r _line || [ -n "$_line" ]; do
        [[ "$_line" =~ ^[[:space:]]*# ]] && continue
        [[ "$_line" =~ ^[[:space:]]*\; ]] && continue
        if [[ "$_line" =~ ^[[:space:]]*\[([^]]+)\] ]]; then
            _section="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$_line" =~ ^[[:space:]]*module_api[[:space:]]*= ]]; then
            if [ -n "$_section" ] && [ "$_section" != module ]; then
                printf 'malformed:module_api outside [module]'
                return 0
            fi
            _seen=$((_seen + 1))
            _value="${_line#*=}"
            _value="${_value#"${_value%%[![:space:]]*}"}"
            _value="${_value%"${_value##*[![:space:]]}"}"
        fi
    done < "$_file"
    if [ "$_seen" -gt 1 ]; then printf 'malformed:duplicate module_api';
    elif [ "$_seen" -eq 0 ] || [ "$_value" = 1 ]; then printf '1';
    elif [ "$_value" = 2 ]; then printf '2';
    else printf 'unsupported:%s' "${_value:-empty module_api}"; fi
}

_ml_python() {
    if [ -n "${IGOR_PYTHON:-}" ]; then printf '%s' "$IGOR_PYTHON"
    elif command -v python3 >/dev/null 2>&1; then printf python3
    else printf python; fi
}

_ml_v2_query() {
    local _name="$1" _path="$2" _py
    _py="$(_ml_python)"
    printf '%s' "${_IGOR_V2_DATA[$_name]:-}" | "$_py" -c '
import json,sys
try:
    value=json.load(sys.stdin)
    for key in sys.argv[1].split("."):
        value=value[int(key)] if isinstance(value,list) else value[key]
    if isinstance(value,list):
        print("\n".join(str(item) for item in value))
    elif isinstance(value,bool):
        print("true" if value else "false")
    elif value is not None:
        print(value)
except (ValueError,KeyError,TypeError):
    raise SystemExit(1)
' "$_path"
}

_ml_v2_rows() {
    local _name="$1" _py
    _py="$(_ml_python)"
    printf '%s' "${_IGOR_V2_DATA[$_name]:-}" | "$_py" -c '
import json,sys
for item in json.load(sys.stdin)["contributions"]:
    print(item["kind"]+":"+item["id"])
'
}

_ml_v2_record() {
    local _name="$1" _key="$2" _py
    _py="$(_ml_python)"
    printf '%s' "${_IGOR_V2_DATA[$_name]:-}" | "$_py" -c '
import json,sys
for item in json.load(sys.stdin)["contributions"]:
    if item["kind"]+":"+item["id"] == sys.argv[1]:
        print(json.dumps(item,separators=(",",":")))
        raise SystemExit(0)
raise SystemExit(1)
' "$_key"
}

_ml_v2_module_requirements() {
    local _py
    _py="$(_ml_python)"
    printf '%s' "${_IGOR_V2_DATA[$1]:-}" | "$_py" -c '
import json,sys
r=json.load(sys.stdin)["manifest"]["requirements"]
print(json.dumps({"modules":r["required_modules"],"capabilities":r["required_capabilities"],"platform_families":r["platform_families"],"bins":r["required_bins"]},separators=(",",":")))
'
}

_ml_v2_capability_reason() {
    local _cap="$1" _providers=() _active=() _candidate
    mapfile -t _providers < <(_ml_v2_capability_providers "$_cap")
    for _candidate in "${_providers[@]}"; do
        _ml_owner_active "$_candidate" && _active+=("$_candidate")
    done
    if [ "${#_providers[@]}" -eq 0 ]; then
        printf 'required capability %s has no declared provider' "$_cap"
    elif [ "${#_active[@]}" -gt 1 ]; then
        printf 'required capability %s has ambiguous providers: %s' "$_cap" "${_active[*]}"
    elif [ "${#_active[@]}" -eq 0 ]; then
        if [ "${#_providers[@]}" -gt 1 ]; then
            printf 'required capability %s has ambiguous providers: %s' "$_cap" "${_providers[*]}"
        else
            printf 'required capability %s provider %s is %s' "$_cap" "${_providers[0]}" \
                "${_IGOR_MODULE_STATUS[${_providers[0]}]:-discovered}"
        fi
    else
        local _key="capability:$_cap"
        [ "${_IGOR_CONTRIBUTION_OWNER[$_key]:-}" = "${_active[0]}" ] ||
            _key="${_key}@${_active[0]}"
        if [ "${_IGOR_CONTRIBUTION_STATE[$_key]:-}" = active ]; then
            return 0
        fi
        printf 'required capability %s provider %s is %s' "$_cap" "${_active[0]}" \
            "${_IGOR_CONTRIBUTION_REASON[$_key]:-unavailable}"
    fi
    return 1
}

_ml_v2_capability_providers() {
    local _cap="$1" _owner _entry
    for _owner in "${!_IGOR_V2_DATA[@]}"; do
        while IFS= read -r _entry; do
            [ "$_entry" = "capability:$_cap" ] && printf '%s\n' "$_owner"
        done < <(_ml_v2_rows "$_owner")
    done | sort -u
}

# Emit one precise failure reason, if any. Module-wide and local requirements
# use the same checker; the caller decides whether owner or contribution fails.
_ml_v2_requirement_failure() {
    local _json="$1" _item _list _family
    _list="$(_ml_json_field "$_json" modules)"
    while IFS= read -r _item; do
        [ -n "$_item" ] || continue
        if ! igor_has_module "$_item"; then
            printf 'required module %s is %s%s' "$_item" \
                "${_IGOR_MODULE_STATUS[$_item]:-missing}" \
                "${_IGOR_MODULE_REASON[$_item]:+ (${_IGOR_MODULE_REASON[$_item]})}"
            return 1
        fi
    done <<< "$_list"
    _list="$(_ml_json_field "$_json" capabilities)"
    while IFS= read -r _item; do
        [ -n "$_item" ] || continue
        _ml_v2_capability_reason "$_item" || return 1
    done <<< "$_list"
    _list="$(_ml_json_field "$_json" platform_features)"
    if [ -n "$_list" ]; then
        printf 'unsupported platform feature requirement: %s' "${_list//$'\n'/, }"
        return 1
    fi
    _list="$(_ml_json_field "$_json" platform_families)"
    if [ -n "$_list" ]; then
        if [ -z "${IGOR_DISTRO_FAMILY:-}" ]; then
            # shellcheck source=core/lib/distro.sh
            source "${_IGOR_LOADER_DIR}/core/lib/distro.sh"
            igor_detect_distro
        fi
        _family="${IGOR_DISTRO_FAMILY:-unknown}"
        if ! printf '%s\n' "$_list" | grep -Fxq -- "$_family"; then
            printf 'platform family %s is outside allowed set %s' "$_family" "${_list//$'\n'/, }"
            return 1
        fi
    fi
    _list="$(_ml_json_field "$_json" bins)"
    while IFS= read -r _item; do
        [ -n "$_item" ] || continue
        if ! command -v "$_item" >/dev/null 2>&1; then
            printf 'required binary %s is missing' "$_item"
            return 1
        fi
    done <<< "$_list"
    return 0
}

_ml_json_field() {
    local _json="$1" _field="$2" _py
    _py="$(_ml_python)"
    printf '%s' "$_json" | "$_py" -c '
import json,sys
try:
    value=json.load(sys.stdin)
    for key in sys.argv[1].split("."):
        value=value[key]
    if isinstance(value,list): print("\n".join(str(item) for item in value))
    elif isinstance(value,bool): print("true" if value else "false")
    elif value is not None: print(value)
except (ValueError,KeyError,TypeError): pass
' "$_field"
}

_ml_v2_validate() {
    local _name="$1" _dir="${_IGOR_MODULE_DIRS[$1]}" _py _result
    _py="$(_ml_python)"
    if ! command -v "$_py" >/dev/null 2>&1; then
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="Python 3 runtime unavailable for v2 validation"
        return 1
    fi
    _result="$("$_py" "${_IGOR_LOADER_DIR}/core/lib/module_contract.py" validate "$_dir" 2>&1)" || {
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="$_result"
        return 1
    }
    _IGOR_V2_DATA["$_name"]="$_result"
}

_ml_v2_prepare_all() {
    local _name _api
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

_ml_load_module_config() {
    [ "${_IGOR_MODULE_CONFIG_LOADED:-0}" -eq 1 ] && return 0
    _IGOR_MODULE_CONFIG_LOADED=1
    local _cfg="${IGOR_DIR:-$_IGOR_LOADER_DIR}/config/modules.conf"
    if ! _ml_migrate_system_policy "$_cfg"; then
        _IGOR_SYSTEM_POLICY_MIGRATION_FAILED=1
        _ml_log error "system policy migration failed; module will remain unavailable until config/modules.conf is writable"
    fi
    [ -f "$_cfg" ] || return 0
    local _line _name _state _rhs
    while IFS= read -r _line || [ -n "$_line" ]; do
        _line="${_line%%#*}"
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        if [[ "$_line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*= ]]; then
            _name="${BASH_REMATCH[1]}"
            _rhs="${_line#*=}"
            _rhs="${_rhs#"${_rhs%%[![:space:]]*}"}"
            _rhs="${_rhs%"${_rhs##*[![:space:]]}"}"
            if [ "$_rhs" = enabled ] || [ "$_rhs" = disabled ]; then
                _IGOR_MODULE_STATE["$_name"]="$_rhs"
                unset '_IGOR_MODULE_REASON['"$_name"']'
            else
                _IGOR_MODULE_STATE["$_name"]="disabled"
                _IGOR_MODULE_REASON["$_name"]="invalid module state (expected enabled or disabled)"
            fi
        else
            _ml_log warn "Ignoring malformed module state entry in $_cfg: $_line"
        fi
    done < "$_cfg"
}

# Existing installations implicitly enabled the bundled system module. Record
# that policy once when its package moves to v2; a new v2 package has no such
# compatibility exception. The original policy is retained for recovery.
_ml_migrate_system_policy() {
    local _cfg="$1" _root="${IGOR_DIR:-$_IGOR_LOADER_DIR}"
    local _manifest="$_root/modules/system/module.conf" _tmp
    [ -f "$_manifest" ] || return 0
    [ "$(_ml_probe_api "$_root/modules/system")" = 2 ] || return 0
    [ ! -L "$_cfg" ] && [ ! -L "${_cfg}.pre-wave-c.bak" ] || return 1
    if [ -f "$_cfg" ] && grep -Eq '^[[:space:]]*system[[:space:]]*=' "$_cfg"; then return 0; fi
    mkdir -p "$(dirname "$_cfg")" || return 1
    _tmp="$(mktemp "${_cfg}.XXXXXX")" || return 1
    if [ -f "$_cfg" ]; then
        cat "$_cfg" > "$_tmp" || { rm -f "$_tmp"; return 1; }
        if [ ! -e "${_cfg}.pre-wave-c.bak" ]; then
            cp -p "$_cfg" "${_cfg}.pre-wave-c.bak" || { rm -f "$_tmp"; return 1; }
        fi
    fi
    printf 'system=enabled\n' >> "$_tmp"
    chmod 600 "$_tmp" || { rm -f "$_tmp"; return 1; }
    mv -f "$_tmp" "$_cfg"
}

igor_module_enabled() {
    _ml_load_module_config
    local _name="${1:-}"
    if [ -n "${_IGOR_MODULE_STATE[$_name]+set}" ]; then
        [ "${_IGOR_MODULE_STATE[$_name]}" = enabled ]
    else
        if [ "$_name" = system ] && [ "${_IGOR_SYSTEM_POLICY_MIGRATION_FAILED:-0}" -eq 1 ]; then
            return 0
        fi
        [ "${_IGOR_MODULE_API[$_name]:-1}" != 2 ]
    fi
}

igor_module_set_enabled() {
    local _name="${1:-}" _state="${2:-}"
    _ml_valid_name "$_name" || { _ml_log error "invalid module name: $_name"; return 1; }
    if [ "${#_IGOR_MODULE_DIRS[@]}" -gt 0 ] && [ -z "${_IGOR_MODULE_DIRS[$_name]:-}" ]; then
        _ml_log error "module is not installed: $_name"
        return 1
    fi
    [ "$_state" = enabled ] || [ "$_state" = disabled ] || {
        _ml_log error "module state must be enabled or disabled"; return 1;
    }
    local _cfg="${IGOR_DIR:-$_IGOR_LOADER_DIR}/config/modules.conf"
    local _parent _tmp
    _parent="$(dirname "$_cfg")"
    mkdir -p "$_parent" || return 1
    _tmp="$(mktemp "${_parent}/.modules.conf.XXXXXX")" || return 1
    if [ -f "$_cfg" ]; then
        awk -v target="$_name" -v state="$_state" '
            $0 ~ "^[[:space:]]*" target "[[:space:]]*=" {
                if (!done) { print target "=" state; done=1 }
                next
            }
            { print }
            END { if (!done) print target "=" state }
        ' "$_cfg" > "$_tmp"
    else
        printf '%s=%s\n' "$_name" "$_state" > "$_tmp"
    fi
    chmod 600 "$_tmp" || { rm -f "$_tmp"; return 1; }
    mv -f "$_tmp" "$_cfg" || { rm -f "$_tmp"; return 1; }
    _IGOR_MODULE_STATE["$_name"]="$_state"
    if [ "$_state" = disabled ] && [ -n "${_IGOR_LOADED_MODULES[$_name]:-}" ]; then
        _IGOR_MODULE_STATUS["$_name"]="disabled"
    fi
    _ml_log info "Module $_name set to $_state; restart Igor to apply registration changes"
}

igor_active_modules() {
    local _n
    for _n in "${!_IGOR_LOADED_MODULES[@]}"; do
        _ml_owner_active "$_n" && printf '%s\n' "$_n"
    done | sort
}

igor_has_capability() {
    local _cap="${1:-}" _name _provided _item
    [ -n "$_cap" ] || return 1
    for _name in "${!_IGOR_MODULE_DIRS[@]}"; do
        _ml_owner_active "$_name" || continue
        _provided="$(_ml_read_conf "${_IGOR_MODULE_DIRS[$_name]}" "provides" 2>/dev/null || true)"
        _provided="${_provided//,/ }"
        for _item in $_provided; do
            [ "$_item" = "$_cap" ] && return 0
        done
    done
    return 1
}

igor_module_list() {
    local _n _state _reason _key
    while IFS= read -r _n; do
        _state="${_IGOR_MODULE_STATUS[$_n]:-$(igor_module_enabled "$_n" && printf enabled || printf disabled)}"
        _reason="${_IGOR_MODULE_REASON[$_n]:-}"
        if [ -n "$_reason" ]; then
            printf '%s\t%s api=%s (%s)\n' "$_n" "$_state" "${_IGOR_MODULE_API[$_n]:-1}" "$_reason"
        else
            printf '%s\t%s api=%s\n' "$_n" "$_state" "${_IGOR_MODULE_API[$_n]:-1}"
        fi
        while IFS= read -r _key; do
            [ "${_IGOR_CONTRIBUTION_OWNER[$_key]:-}" = "$_n" ] || continue
            printf '  %s owner=%s state=%s source=%s' "$_key" "$_n" \
                "$(igor_contribution_state "$_key")" "${_IGOR_CONTRIBUTION_SOURCE[$_key]:-unknown}"
            _reason="$(igor_contribution_reason "$_key")"
            [ -z "$_reason" ] || printf ' reason=%s' "$_reason"
            printf '\n'
        done < <(printf '%s\n' "${!_IGOR_CONTRIBUTIONS[@]}" | sort)
    done < <(printf '%s\n' "${!_IGOR_MODULE_DIRS[@]}" | sort)
}

igor_module_status() { printf '%s\n' "${_IGOR_MODULE_STATUS[${1:-}]:-unknown}"; }
igor_module_reason() { printf '%s\n' "${_IGOR_MODULE_REASON[${1:-}]:-}"; }

# Project existing owning-service snapshots. This never loads a package,
# dispatches a probe, changes policy, or creates persistent state.
_igor_module_inspection() {
    local _action="$1" _name="$2" _states _rows _model _schemas _key _owner _record _state _reason
    _ml_valid_name "$_name" && [ -n "${_IGOR_MODULE_DIRS[$_name]:-}" ] || return 2
    _states="$(
        for _owner in "${!_IGOR_MODULE_DIRS[@]}"; do
            printf '%s\0' "$_owner" "${_IGOR_MODULE_STATUS[$_owner]:-not_evaluated}" \
                "${_IGOR_MODULE_REASON[$_owner]:-}" "${_IGOR_LOADED_MODULES[$_owner]:-0}" \
                "${_IGOR_MODULE_STATE[$_owner]:-}"
        done | "$(_ml_python)" -c '
import json, sys
parts = sys.stdin.buffer.read().split(b"\0")[:-1]
result = {}
for i in range(0, len(parts), 5):
    name, status, reason, loaded, policy = (p.decode() for p in parts[i:i+5])
    result[name] = {"status": status, "reason": reason or None, "loaded": loaded == "1",
                    "enabled": policy == "enabled" if policy else None}
print(json.dumps(result,separators=(",", ":")))'
    )" || return 1
    _rows="$(
        for _key in "${!_IGOR_CONTRIBUTIONS[@]}"; do
            _owner="${_IGOR_CONTRIBUTION_OWNER[$_key]:-}"
            _record="${_IGOR_CONTRIBUTIONS[$_key]:-}"
            _state="$(igor_contribution_state "$_key")"
            _reason="$(igor_contribution_reason "$_key")"
            printf '%s\0' "$_key" "$_owner" "${_IGOR_CONTRIBUTION_SOURCE[$_key]:-unknown}" "$_state" "$_reason" "$_record"
        done | "$(_ml_python)" -c '
import json, sys
parts = sys.stdin.buffer.read().split(b"\0")[:-1]
result = []
for i in range(0,len(parts),6):
    key,owner,source,state,reason,raw = (p.decode() for p in parts[i:i+6])
    kind,ident = key.split(":",1)
    ident = ident.split("@",1)[0]
    try: descriptor=json.loads(raw)
    except ValueError: descriptor={"kind":kind,"id":ident,"handler":raw}
    result.append({"index_key":key,"id":ident,"kind":kind,"owner":owner,"source":source,
                   "availability":state,"unavailable_reason":reason or None,"descriptor":descriptor})
print(json.dumps(result,separators=(",", ":")))'
    )" || return 1
    _model="$(igor_model_list)" || return 1
    _schemas="$(igor_configuration_declarations)" || return 1
    "$(_ml_python)" - "${_IGOR_LOADER_DIR}/core/lib" "${IGOR_DIR:-$_IGOR_LOADER_DIR}" \
        "${IGOR_DATA_DIR:-${IGOR_DIR:-$_IGOR_LOADER_DIR}/data}" "$_name" "$_action" "$_states" "$_rows" "$_model" "$_schemas" <<'PY' |
import json, sys
sys.path.insert(0,sys.argv[1])
from pathlib import Path
from configuration import ConfigurationService, installed_schemas
states, rows, model, schemas = map(json.loads,sys.argv[6:10])
configuration=[]
try:
    retained=installed_schemas(Path(sys.argv[2]))
    registered={(owner,field["id"]) for owner,schema in retained for field in schema["fields"]}
    retained.extend((r["owner"],r["schema"]) for r in schemas if r["owner"]!="core" and not all((r["owner"],f["id"]) in registered for f in r["schema"]["fields"]))
    service=ConfigurationService(Path(sys.argv[3]), schemas=retained,
                                 owner_active=lambda owner: states.get(owner,{}).get("status")=="active")
    for field in service.fields.values():
        if field["owner"] == sys.argv[4]:
            configuration.append(service.inspect(field["id"], "module:"+field["owner"]))
except ValueError:
    configuration=[{"schema_owner":sys.argv[4],"availability":"unavailable",
                    "reason":"configuration service inspection unavailable"}]
print(json.dumps({"root":sys.argv[2],"name":sys.argv[4],"action":sys.argv[5],
                  "runtime":{"module_states":states,"contributions":rows,"model":model,
                             "configuration":configuration}},separators=(",", ":")))
PY
        "$(_ml_python)" "${_IGOR_LOADER_DIR}/core/lib/module_inspection.py" --snapshot
}

igor_module_inspect() { _igor_module_inspection inspect "${1:-}"; }
igor_module_detach_plan() { _igor_module_inspection detach-plan "${1:-}"; }

igor_contribution_state() {
    local _key="${1:-}" _owner="${_IGOR_CONTRIBUTION_OWNER[${1:-}]:-}"
    [ -n "${_IGOR_CONTRIBUTIONS[$_key]:-}" ] || { printf 'unknown\n'; return 1; }
    if ! _ml_owner_active "$_owner"; then printf 'inactive\n'
    elif [ "${_IGOR_CONTRIBUTION_STATE[$_key]:-active}" != active ]; then
        printf '%s\n' "${_IGOR_CONTRIBUTION_STATE[$_key]}"
    elif [ -n "$(_ml_contribution_dynamic_failure "$_key")" ]; then
        printf 'unavailable\n'
    else printf 'active\n'; fi
}

_ml_index_capability_runtime_fields() {
    local _key="$1" _record="$2" _parsed
    local -a _fields=()
    [[ "$_record" = \{* ]] || return 0
    _parsed="$(printf '%s' "$_record" | "$(_ml_python)" -c '
import json,sys
record=json.load(sys.stdin)
handler=record.get("handler","")
timeout=record.get("timeout_seconds",30)
deps=[]
impl=record.get("implementation")
if isinstance(impl,dict) and impl.get("kind")=="composition":
    for variant in impl.get("variants",[]):
        for step in variant.get("steps",[]):
            ident=step.get("capability_id")
            if isinstance(ident,str) and ident:
                deps.append(ident)
    final=impl.get("final_check")
    if isinstance(final,dict):
        ident=final.get("capability_id")
        if isinstance(ident,str) and ident:
            deps.append(ident)
print(handler)
print(timeout)
print(" ".join(dict.fromkeys(deps)))
print("ok")
')" || return 1
    mapfile -t _fields <<< "$_parsed"
    [ "${#_fields[@]}" -eq 4 ] && [ "${_fields[3]}" = ok ] || return 1
    if [ -n "${_fields[0]}" ]; then
        _IGOR_HANDLER_FUNCTION["$_key"]="${_fields[0]}"
        _IGOR_HANDLER_TIMEOUT["$_key"]="${_fields[1]}"
    fi
    _IGOR_CAPABILITY_DEPENDENCIES["$_key"]="${_fields[2]}"
}

_ml_index_requirement_fields() {
    local _key="$1" _record="$2" _parsed
    local -a _fields=()
    [[ "$_record" = \{* ]] || return 0
    _parsed="$(printf '%s' "$_record" | "$(_ml_python)" -c '
import json,sys
record=json.load(sys.stdin)
requires=record.get("requires",{})
if not isinstance(requires,dict):
    raise SystemExit(1)
for key in ("modules","capabilities","platform_features","platform_families","bins"):
    value=requires.get(key,[])
    if not isinstance(value,list) or any(not isinstance(item,str) or not item for item in value):
        raise SystemExit(1)
    print(" ".join(value))
print("ok")
')" || return 1
    mapfile -t _fields <<< "$_parsed"
    [ "${#_fields[@]}" -eq 6 ] && [ "${_fields[5]}" = ok ] || return 1
    _IGOR_REQ_INDEXED["$_key"]=1
    _IGOR_REQ_MODULES["$_key"]="${_fields[0]}"
    _IGOR_REQ_CAPABILITIES["$_key"]="${_fields[1]}"
    _IGOR_REQ_PLATFORM_FEATURES["$_key"]="${_fields[2]}"
    _IGOR_REQ_PLATFORM_FAMILIES["$_key"]="${_fields[3]}"
    _IGOR_REQ_BINS["$_key"]="${_fields[4]}"
}

_ml_indexed_requirement_failure() {
    local _key="$1" _item _family
    local -a _items=()
    read -r -a _items <<< "${_IGOR_REQ_MODULES[$_key]:-}"
    for _item in "${_items[@]}"; do
        [ -n "$_item" ] || continue
        if ! igor_has_module "$_item"; then
            printf 'required module %s is %s%s' "$_item" \
                "${_IGOR_MODULE_STATUS[$_item]:-missing}" \
                "${_IGOR_MODULE_REASON[$_item]:+ (${_IGOR_MODULE_REASON[$_item]})}"
            return 1
        fi
    done
    read -r -a _items <<< "${_IGOR_REQ_CAPABILITIES[$_key]:-}"
    for _item in "${_items[@]}"; do
        [ -n "$_item" ] || continue
        _ml_v2_capability_reason "$_item" || return 1
    done
    if [ -n "${_IGOR_REQ_PLATFORM_FEATURES[$_key]:-}" ]; then
        printf 'unsupported platform feature requirement: %s' "${_IGOR_REQ_PLATFORM_FEATURES[$_key]// /, }"
        return 1
    fi
    if [ -n "${_IGOR_REQ_PLATFORM_FAMILIES[$_key]:-}" ]; then
        if [ -z "${IGOR_DISTRO_FAMILY:-}" ]; then
            source "${_IGOR_LOADER_DIR}/core/lib/distro.sh"
            igor_detect_distro
        fi
        _family="${IGOR_DISTRO_FAMILY:-unknown}"
        case " ${_IGOR_REQ_PLATFORM_FAMILIES[$_key]} " in
            *" $_family "*) ;;
            *)
                printf 'platform family %s is outside allowed set %s' "$_family" "${_IGOR_REQ_PLATFORM_FAMILIES[$_key]// /, }"
                return 1
                ;;
        esac
    fi
    read -r -a _items <<< "${_IGOR_REQ_BINS[$_key]:-}"
    for _item in "${_items[@]}"; do
        [ -n "$_item" ] || continue
        if ! command -v "$_item" >/dev/null 2>&1; then
            printf 'required binary %s is missing' "$_item"
            return 1
        fi
    done
    return 0
}

_ml_contribution_dynamic_failure() {
    local _key="$1" _record="${_IGOR_CONTRIBUTIONS[$1]:-}" _requires
    [[ "$_record" = \{* ]] || return 0
    if [ "${_IGOR_REQ_INDEXED[$_key]:-0}" = 1 ]; then
        _ml_indexed_requirement_failure "$_key" || true
        return 0
    fi
    [[ "$_record" == *'"requires"'* ]] || return 0
    _requires="$(printf '%s' "$_record" | "$(_ml_python)" -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("requires",{})))')" || return 0
    _ml_v2_requirement_failure "$_requires" || true
}

igor_contribution_reason() {
    local _key="${1:-}"
    if [ -n "${_IGOR_CONTRIBUTION_REASON[$_key]:-}" ]; then
        printf '%s\n' "${_IGOR_CONTRIBUTION_REASON[$_key]}"
    else
        _ml_contribution_dynamic_failure "$_key"
    fi
}

igor_contribution_list() {
    local _key
    for _key in "${!_IGOR_CONTRIBUTIONS[@]}"; do
        printf '%s\t%s\t%s\t%s\t%s\n' "$_key" \
            "${_IGOR_CONTRIBUTION_OWNER[$_key]}" "$(igor_contribution_state "$_key")" \
            "${_IGOR_CONTRIBUTION_SOURCE[$_key]:-unknown}" \
            "$(igor_contribution_reason "$_key")"
    done | sort
}

# Structured read-only snapshots for generic frontends.  These expose the
# existing owner-stamped registry; they do not create another contribution or
# module catalog.
igor_contribution_records() {
    local _key _owner _record _state _reason _dynamic _base_state _owner_active
    {
        while IFS= read -r _key; do
            [ -n "$_key" ] || continue
            _owner="${_IGOR_CONTRIBUTION_OWNER[$_key]:-}"
            _record="${_IGOR_CONTRIBUTIONS[$_key]:-}"
            _base_state="${_IGOR_CONTRIBUTION_STATE[$_key]:-active}"
            _reason="${_IGOR_CONTRIBUTION_REASON[$_key]:-}"
            _dynamic=""
            if _ml_owner_active "$_owner"; then _owner_active=true; else _owner_active=false; fi
            if [ -z "$_reason" ] || { [ "$_owner_active" = true ] && [ "$_base_state" = active ]; }; then
                _dynamic="$(_ml_contribution_dynamic_failure "$_key" 2>/dev/null || true)"
            fi
            if [ "$_owner_active" != true ]; then
                _state=inactive
            elif [ "$_base_state" != active ]; then
                _state="$_base_state"
            elif [ -n "$_dynamic" ]; then
                _state=unavailable
            else
                _state=active
            fi
            [ -n "$_reason" ] || _reason="$_dynamic"
            printf '%s\0' "$_key" "$_owner" "${_IGOR_CONTRIBUTION_SOURCE[$_key]:-unknown}" \
                "$_state" "$_reason" "$_record"
        done < <(printf '%s\n' "${!_IGOR_CONTRIBUTIONS[@]}" | sort)
    } | "$(_ml_python)" -c '
import json,sys
raw=sys.stdin.buffer.read().split(b"\0")
if raw[-1:]==[b""]: raw.pop()
if len(raw)%6: raise SystemExit("invalid contribution snapshot")
rows=[]
for i in range(0,len(raw),6):
    key,owner,source,state,reason,record=(part.decode() for part in raw[i:i+6])
    kind,ident=key.split(":",1)
    ident=ident.split("@",1)[0]
    try: descriptor=json.loads(record)
    except ValueError: descriptor={"kind":kind,"id":ident,"handler":record}
    rows.append({"index_key":key,"id":ident,"kind":kind,"owner":owner,"source":source,
                 "availability":state,"unavailable_reason":reason or None,
                 "descriptor":descriptor})
print(json.dumps(rows,sort_keys=True,separators=(",",":")))
'
}

# Build the operator namespace from already-validated registration data.
# This is structural metadata only: it deliberately does not evaluate dynamic
# contribution requirements such as command/binary availability. Canonical
# capability prepare/execution remains the authority for current availability.
#
# Boundary M keeps the raw loader-owned framing separate from the Python
# projection.  The same frames can therefore produce a cheap structural
# generation key on the warm path without first rebuilding the JSON seed.
_igor_operator_surface_seed_frames() {
    local _name _api _status _reason _enabled _metadata
    local _key _owner _source _state _record

    while IFS= read -r _name; do
        [ -n "$_name" ] || continue
        _api="${_IGOR_MODULE_API[$_name]:-1}"
        _status="${_IGOR_MODULE_STATUS[$_name]:-discovered}"
        _reason="${_IGOR_MODULE_REASON[$_name]:-}"
        if igor_module_enabled "$_name"; then _enabled=true; else _enabled=false; fi
        if [ "$_api" = 2 ] && [ -n "${_IGOR_V2_DATA[$_name]:-}" ]; then
            # Boundary H already loaded this validated structural package
            # document from its compiled registry/cache.
            _metadata="${_IGOR_V2_DATA[$_name]}"
        else
            _metadata="$(_ml_read_conf "${_IGOR_MODULE_DIRS[$_name]}" display_name 2>/dev/null || printf '%s' "$_name")"
        fi
        printf 'module\0%s\0%s\0%s\0%s\0%s\0%s\0' \
            "$_name" "$_api" "$_status" "$_reason" "$_enabled" "$_metadata"
    done < <(printf '%s\n' "${!_IGOR_MODULE_DIRS[@]}" | sort)

    while IFS= read -r _key; do
        [ -n "$_key" ] || continue
        _owner="${_IGOR_CONTRIBUTION_OWNER[$_key]:-}"
        _source="${_IGOR_CONTRIBUTION_SOURCE[$_key]:-unknown}"
        _state="${_IGOR_CONTRIBUTION_STATE[$_key]:-active}"
        _reason="${_IGOR_CONTRIBUTION_REASON[$_key]:-}"
        _record="${_IGOR_CONTRIBUTIONS[$_key]:-}"
        printf 'contribution\0%s\0%s\0%s\0%s\0%s\0%s\0' \
            "$_key" "$_owner" "$_source" "$_state" "$_reason" "$_record"
    done < <(printf '%s\n' "${!_IGOR_CONTRIBUTIONS[@]}" | sort)
}

igor_operator_surface_seed() {
    _igor_operator_surface_seed_frames |
        "$(_ml_python)" "${_IGOR_LOADER_DIR}/core/lib/operator_surface.py" \
            seed "${_IGOR_LOADER_DIR}/core/lib"
}

# Return a loader-owned fingerprint for the exact structural frames consumed by
# the operator surface plus the Core projection implementations that add
# Core-owned capabilities/configuration.  This is derived presentation identity,
# not execution authority.  If sha256sum is unavailable the caller falls back
# to the original seed/build path.
igor_operator_surface_generation() {
    command -v sha256sum >/dev/null 2>&1 || return 1
    local _surface="${_IGOR_LOADER_DIR}/core/lib/operator_surface.py"
    local _candidates="${_IGOR_LOADER_DIR}/core/lib/input_candidates.py"
    local _configuration="${_IGOR_LOADER_DIR}/core/lib/configuration.py"
    local _deployment="${_IGOR_LOADER_DIR}/core/lib/deployment_attachment.py"
    local _loader="${_IGOR_LOADER_DIR}/core/lib/module_loader.sh"
    local _fast="${_IGOR_LOADER_DIR}/core/lib/module_loader_fast.sh"
    local _digest _rest
    [ -f "$_surface" ] && [ -f "$_candidates" ] && [ -f "$_configuration" ] &&
        [ -f "$_deployment" ] && [ -f "$_loader" ] || return 1

    {
        printf 'igor-operator-surface-generation-v1\0'
        _igor_operator_surface_seed_frames
        printf 'implementation\0'
        if [ -f "$_fast" ]; then
            sha256sum "$_surface" "$_candidates" "$_configuration" "$_deployment" "$_loader" "$_fast"
        else
            sha256sum "$_surface" "$_candidates" "$_configuration" "$_deployment" "$_loader"
        fi
    } | sha256sum | {
        read -r _digest _rest
        [[ "$_digest" =~ ^[0-9a-f]{64}$ ]] || return 1
        printf '%s' "$_digest"
    }
}

igor_module_records() {
    local _name _display _status _reason _enabled
    {
        while IFS= read -r _name; do
            [ -n "$_name" ] || continue
            _display="$(_ml_read_conf "${_IGOR_MODULE_DIRS[$_name]}" display_name 2>/dev/null || printf '%s' "$_name")"
            _status="${_IGOR_MODULE_STATUS[$_name]:-$(igor_module_enabled "$_name" && printf active || printf disabled)}"
            _reason="${_IGOR_MODULE_REASON[$_name]:-}"
            if igor_module_enabled "$_name"; then _enabled=true; else _enabled=false; fi
            printf '%s\0' "$_name" "$_display" "$_status" "$_reason" "$_enabled" "${_IGOR_MODULE_API[$_name]:-1}"
        done < <(printf '%s\n' "${!_IGOR_MODULE_DIRS[@]}" | sort)
    } | "$(_ml_python)" -c '
import json,sys
raw=sys.stdin.buffer.read().split(b"\0")
if raw[-1:]==[b""]: raw.pop()
if len(raw)%6: raise SystemExit("invalid module snapshot")
rows=[]
for i in range(0,len(raw),6):
    name,display,status,reason,enabled,api=(part.decode() for part in raw[i:i+6])
    rows.append({"name":name,"display_name":display,"status":status,
                 "reason":reason or None,"enabled":enabled=="true","module_api":int(api)})
print(json.dumps(rows,sort_keys=True,separators=(",",":")))
'
}

_ml_index_contribution() {
    local _key="$1" _owner="$2" _source="$3" _record="$4"
    if [ -n "${_IGOR_CONTRIBUTIONS[$_key]:-}" ] && \
       [ "${_IGOR_CONTRIBUTION_OWNER[$_key]:-}" != "$_owner" ]; then
        case "$_key" in
            capability:*) _key="${_key}@${_owner}" ;;
            *)
                _ml_log error "duplicate contribution $_key: ${_IGOR_CONTRIBUTION_OWNER[$_key]} and $_owner"
                return 1
                ;;
        esac
    fi
    _IGOR_CONTRIBUTIONS["$_key"]="$_record"
    _IGOR_CONTRIBUTION_OWNER["$_key"]="$_owner"
    _IGOR_CONTRIBUTION_SOURCE["$_key"]="$_source"
    _IGOR_CONTRIBUTION_STATE["$_key"]="active"
    unset '_IGOR_CONTRIBUTION_REASON['"$_key"']'
}

_ml_owner_active() {
    local _owner="${1:-}"
    [ -z "$_owner" ] && return 0
    [ -n "${_IGOR_LOADED_MODULES[$_owner]:-}" ] && igor_module_enabled "$_owner" &&
        [ "${_IGOR_MODULE_STATUS[$_owner]:-active}" = active ]
}

_ml_valid_function() { [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; }

# A capability is useful only when its declared leaf function can be called in
# the current process.  Menu files are loaded lazily, so give the legacy lazy
# loader one chance to attach the declared LOAD_MODULE before rejecting the
# entry.  A successful module load is not sufficient on its own: incomplete
# or stale module declarations must still fail closed at catalog construction.
_ml_capability_function_available() {
    local _fn="${1:-}" _mod="${2:-}"
    _ml_valid_function "$_fn" || return 1
    declare -f "$_fn" >/dev/null 2>&1 && return 0

    if [ -n "$_mod" ] && declare -f _igor_load_module >/dev/null 2>&1; then
        _igor_load_module "$_mod" >/dev/null 2>&1 || true
    fi
    declare -f "$_fn" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# _ml_read_conf <module_dir> <key> [section]
#   Parse a single key from module.conf (simple INI parser, no deps).
#   Reads the first matching key= in the file (section filtering optional).
# ---------------------------------------------------------------------------
_ml_read_conf() {
    local _dir="$1" _key="$2"
    local _conf="${_dir}/module.conf"
    [ -f "$_conf" ] || return 1
    # Strip comments, extract key=value, return value
    grep -m1 "^${_key}[[:space:]]*=" "$_conf" 2>/dev/null \
        | sed 's/^[^=]*=[[:space:]]*//' \
        | sed 's/[[:space:]]*$//'
}

# ---------------------------------------------------------------------------
# igor_has_bin <binary_name>
#   Returns 0 if binary is available on PATH, 1 otherwise.
#   Modules use this at runtime to guard optional features.
# ---------------------------------------------------------------------------
igor_has_bin() {
    command -v "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# igor_has_module <module_name>
#   Returns 0 if the named module has been successfully loaded, 1 otherwise.
# ---------------------------------------------------------------------------
igor_has_module() {
    local _name="${1:-}"
    [ -n "${_IGOR_LOADED_MODULES[$_name]:-}" ] && _ml_owner_active "$_name"
}

# ---------------------------------------------------------------------------
# _ml_check_dependencies <module_dir> <module_name>
#
#   Reads the [dependencies] section of module.conf and validates:
#     required_bins   — comma-separated binary names; all must be on PATH
#     optional_bins   — comma-separated bin[:package[:desc]]; warn if absent
#     required_modules — comma-separated module names; all must be loaded
#     optional_modules — comma-separated mod[:desc]; warn if not loaded
#
#   Returns 0 if all required dependencies are satisfied.
#   Returns 1 if any required dependency is missing (caller should skip module).
#   Missing optional dependencies produce warnings but do not block loading.
# ---------------------------------------------------------------------------
_ml_check_dependencies() {
    local _dir="$1" _name="$2"
    local _conf="${_dir}/module.conf"
    [ -f "$_conf" ] || return 0   # no conf → no deps → pass

    local _fail=0

    # ── required_bins ──────────────────────────────────────────────────────
    local _req_bins
    _req_bins="$(_ml_read_conf "$_dir" "required_bins" 2>/dev/null || true)"
    _req_bins="${_req_bins//,/ }"
    local _bin
    for _bin in $_req_bins; do
        [ -z "$_bin" ] && continue
        if ! command -v "$_bin" >/dev/null 2>&1; then
            _ml_log error "${_name}: missing required binary: ${_bin}"
            _fail=1
        fi
    done

    # ── optional_bins (format per entry: bin[:package[:description]]) ──────
    local _opt_bins
    _opt_bins="$(_ml_read_conf "$_dir" "optional_bins" 2>/dev/null || true)"
    if [ -n "$_opt_bins" ]; then
        local _entry _obin _opkg _odesc
        while IFS= read -r _entry; do
            _entry="${_entry#"${_entry%%[![:space:]]*}"}"   # ltrim
            [ -z "$_entry" ] && continue
            IFS=':' read -r _obin _opkg _odesc <<< "$_entry"
            _obin="${_obin// /}"
            [ -z "$_obin" ] && continue
            if ! command -v "$_obin" >/dev/null 2>&1; then
                if [ -n "$_opkg" ]; then
                    _ml_log warn "${_name}: optional '${_obin}' not found — install ${_opkg} for: ${_odesc:-${_obin} features}"
                else
                    _ml_log warn "${_name}: optional '${_obin}' not found — some features disabled"
                fi
            fi
        done < <(printf '%s\n' "$_opt_bins" | tr ',' '\n')
    fi

    # ── required_modules ───────────────────────────────────────────────────
    local _req_mods
    _req_mods="$(_ml_read_conf "$_dir" "required_modules" 2>/dev/null || true)"
    _req_mods="${_req_mods//,/ }"
    local _mod
    for _mod in $_req_mods; do
        [ -z "$_mod" ] && continue
        if ! igor_has_module "$_mod"; then
            _ml_log error "${_name}: required module '${_mod}' is not loaded"
            _fail=1
        fi
    done

    # ── optional_modules (format per entry: module[:description]) ──────────
    local _opt_mods
    _opt_mods="$(_ml_read_conf "$_dir" "optional_modules" 2>/dev/null || true)"
    if [ -n "$_opt_mods" ]; then
        local _mod_entry _omod _omod_desc
        while IFS= read -r _mod_entry; do
            _mod_entry="${_mod_entry#"${_mod_entry%%[![:space:]]*}"}"   # ltrim
            [ -z "$_mod_entry" ] && continue
            IFS=':' read -r _omod _omod_desc <<< "$_mod_entry"
            _omod="${_omod// /}"
            [ -z "$_omod" ] && continue
            if ! igor_has_module "$_omod"; then
                _ml_log warn "${_name}: optional module '${_omod}' not loaded — ${_omod_desc:-some features may be limited}"
            fi
        done < <(printf '%s\n' "$_opt_mods" | tr ',' '\n')
    fi

    return $_fail
}

# ---------------------------------------------------------------------------
# igor_discover_modules
#
#   Scan ${IGOR_DIR}/modules/ for directories containing module.conf.
#   Prints one module name per line (unsorted — use igor_sort_modules next).
#   Sets global array _IGOR_MODULE_DIRS[name]=path for use by other functions.
# ---------------------------------------------------------------------------
declare -gA _IGOR_MODULE_DIRS 2>/dev/null || true

igor_discover_modules() {
    _ml_load_module_config
    local _modules_root="${IGOR_DIR:-$_IGOR_LOADER_DIR}/modules"
    local _names=()

    if [ ! -d "$_modules_root" ]; then
        _ml_log warn "modules/ directory not found: $_modules_root"
        return 0
    fi

    local _dir _name _api
    for _dir in "${_modules_root}"/*/; do
        [ -d "$_dir" ] || continue
        [ -f "${_dir}module.conf" ] || continue
        _api="$(_ml_probe_api "${_dir%/}")"
        if [ "$_api" = 1 ]; then
            _name="$(_ml_read_conf "$_dir" "name")"
            [ -n "$_name" ] || _name="$(basename "$_dir")"
        else
            # Strict v2 identity is checked against the directory by the
            # validator. Never trust a malformed manifest as an array key.
            _name="$(basename "$_dir")"
        fi
        _ml_valid_name "$_name" || { _ml_log error "invalid module directory/name: $_name"; continue; }
        _IGOR_MODULE_DIRS["$_name"]="${_dir%/}"
        _IGOR_MODULE_API["$_name"]="$_api"
        if ! igor_module_enabled "$_name"; then
            _IGOR_MODULE_STATUS["$_name"]="disabled"
            if [ "$_api" = 2 ] && [ -z "${_IGOR_MODULE_STATE[$_name]+set}" ]; then
                _IGOR_MODULE_REASON["$_name"]="explicit enablement required for new v2 module"
            fi
        else
            _IGOR_MODULE_STATUS["$_name"]="discovered"
        fi
        _names+=("$_name")
    done

    printf '%s\n' "${_names[@]}"
}

# ---------------------------------------------------------------------------
# igor_sort_modules [name...]
#
#   Topological sort of module names passed on stdin or as arguments.
#   Reads depends_on from module.conf for each module.
#   Outputs names in load order (dependencies first).
#   Cycles are detected and cause the offending module to be skipped with a
#   warning.
# ---------------------------------------------------------------------------
igor_sort_modules() {
    local _input_names=("$@")

    # If no args, read from stdin
    if [ ${#_input_names[@]} -eq 0 ]; then
        while IFS= read -r _line; do
            [ -n "$_line" ] && _input_names+=("$_line")
        done
    fi

    [ ${#_input_names[@]} -eq 0 ] && return 0

    # Build dependency map: _deps[name]="dep1 dep2"
    declare -A _deps
    local _n _dep_str
    for _n in "${_input_names[@]}"; do
        local _dir="${_IGOR_MODULE_DIRS[$_n]:-}"
        if [ "${_IGOR_MODULE_API[$_n]:-1}" = 2 ] && [ -n "${_IGOR_V2_DATA[$_n]:-}" ]; then
            _dep_str="$(_ml_v2_query "$_n" manifest.requirements.required_modules 2>/dev/null)"
            _dep_str="${_dep_str//$'\n'/ }"
            local _cap _provider _cap_list
            _cap_list="$(_ml_v2_query "$_n" manifest.requirements.required_capabilities 2>/dev/null)"
            while IFS= read -r _cap; do
                [ -n "$_cap" ] || continue
                _provider="$(_ml_v2_capability_providers "$_cap")"
                if [ -n "$_provider" ] && [[ "$_provider" != *$'\n'* ]]; then
                    _dep_str+=" $_provider"
                fi
            done <<< "$_cap_list"
        elif [ -n "$_dir" ]; then
            _dep_str="$(_ml_read_conf "$_dir" "depends_on" 2>/dev/null || echo "")"
            local _required
            _required="$(_ml_read_conf "$_dir" "required_modules" 2>/dev/null || echo "")"
            _dep_str="$_dep_str ${_required}"
        else
            _dep_str=""
        fi
        # Normalize: comma or space separated → space separated
        _dep_str="${_dep_str//,/ }"
        _deps["$_n"]="$_dep_str"
    done

    # Kahn's algorithm (iterative topological sort)
    declare -A _in_degree
    declare -A _is_input
    local _name

    for _name in "${_input_names[@]}"; do
        _in_degree["$_name"]=0
        _is_input["$_name"]=1
    done

    # Count in-degrees (only count deps that are in our input set)
    for _name in "${_input_names[@]}"; do
        local _dep
        for _dep in ${_deps[$_name]}; do
            [ -n "${_is_input[$_dep]:-}" ] || continue
            _in_degree["$_name"]=$(( ${_in_degree[$_name]:-0} + 1 ))
        done
    done

    # Queue: all nodes with in_degree 0
    local _queue=()
    for _name in "${_input_names[@]}"; do
        [ "${_in_degree[$_name]}" -eq 0 ] && _queue+=("$_name")
    done

    local _sorted=()
    while [ ${#_queue[@]} -gt 0 ]; do
        # Pop first element
        _name="${_queue[0]}"
        _queue=("${_queue[@]:1}")
        _sorted+=("$_name")

        # Reduce in-degree for modules that depend on _name
        local _other
        for _other in "${_input_names[@]}"; do
            local _dep
            for _dep in ${_deps[$_other]}; do
                if [ "$_dep" = "$_name" ]; then
                    _in_degree["$_other"]=$(( ${_in_degree[$_other]} - 1 ))
                    if [ "${_in_degree[$_other]}" -eq 0 ]; then
                        _queue+=("$_other")
                    fi
                fi
            done
        done
    done

    # Detect cycle: if sorted < input, something was in a cycle
    if [ ${#_sorted[@]} -lt ${#_input_names[@]} ]; then
        for _name in "${_input_names[@]}"; do
            local _found=0
            local _s
            for _s in "${_sorted[@]}"; do
                [ "$_s" = "$_name" ] && { _found=1; break; }
            done
            [ "$_found" -eq 0 ] && \
                _ml_log warn "Dependency cycle detected — skipping module: $_name"
        done
    fi

    printf '%s\n' "${_sorted[@]}"
}

# ---------------------------------------------------------------------------
# igor_load_module <name>
#
#   Load a single module by name:
#     1. Locate module.sh via _IGOR_MODULE_DIRS
#     2. _ml_check_dependencies (required bins + modules)
#     3. bash -n syntax check
#     4. source module.sh
#     5. call <name>__register
#
#   Idempotent: already-loaded modules are silently skipped.
#   Returns 0 on success, 1 on failure (and logs the reason).
# ---------------------------------------------------------------------------
igor_load_module() {
    local _name="$1"
    [ -n "$_name" ] || { _ml_log error "igor_load_module: no module name given"; return 1; }

    _ml_load_module_config
    if ! igor_module_enabled "$_name"; then
        _IGOR_MODULE_STATUS["$_name"]="disabled"
        _ml_log info "Module $_name disabled by configuration — skipped"
        return 1
    fi

    # Idempotency check
    if [ -n "${_IGOR_LOADED_MODULES[$_name]:-}" ]; then
        return 0
    fi

    local _dir="${_IGOR_MODULE_DIRS[$_name]:-}"
    if [ -z "$_dir" ]; then
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="not discovered"
        _ml_log error "Module not found in registry: $_name (run igor_discover_modules first)"
        return 1
    fi

    if [ "${_IGOR_MODULE_API[$_name]:-1}" != 1 ]; then
        _ml_load_v2 "$_name"
        return $?
    fi

    local _phase_started=""
    [ "${IGOR_TUI_MODE:-false}" = true ] && _phase_started="$(_ml_now_ms)"

    local _module_sh="${_dir}/module.sh"
    if [ ! -f "$_module_sh" ]; then
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="module.sh missing"
        _ml_log error "module.sh missing for $_name: $_module_sh"
        return 1
    fi

    # Step 1: dependency check
    if ! _ml_check_dependencies "$_dir" "$_name"; then
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="unmet required dependency"
        _ml_log error "Module $_name skipped — unmet required dependencies (see above)"
        return 1
    fi
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _ml_tui_phase_record "$_name.v1.dependencies" "$_phase_started"
        _phase_started="$(_ml_now_ms)"
    fi

    # Step 3: syntax check
    if ! bash -n "$_module_sh" 2>/tmp/_igor_ml_syntax_err; then
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="syntax error"
        local _syntax_err
        _syntax_err="$(cat /tmp/_igor_ml_syntax_err 2>/dev/null)"
        _ml_log error "Syntax error in $_name — SKIPPED: ${_syntax_err:-unknown}"
        return 1
    fi
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _ml_tui_phase_record "$_name.v1.syntax" "$_phase_started"
        _phase_started="$(_ml_now_ms)"
    fi

    # Step 4: source
    # shellcheck disable=SC1090
    if ! source "$_module_sh" 2>/tmp/_igor_ml_source_err; then
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="source failed"
        local _source_err
        _source_err="$(cat /tmp/_igor_ml_source_err 2>/dev/null)"
        _ml_log error "Failed to source $_name — SKIPPED: ${_source_err:-unknown}"
        return 1
    fi
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _ml_tui_phase_record "$_name.v1.source" "$_phase_started"
        _phase_started="$(_ml_now_ms)"
    fi

    # Step 5: call __register
    local _register_fn="${_name}__register"
    if declare -f "$_register_fn" >/dev/null 2>&1; then
        _IGOR_REGISTERING_MODULE="$_name"
        if ! "$_register_fn" 2>/tmp/_igor_ml_register_err; then
            _IGOR_REGISTERING_MODULE=""
            _IGOR_MODULE_STATUS["$_name"]="unavailable"
            _IGOR_MODULE_REASON["$_name"]="registration failed"
            local _reg_err
            _reg_err="$(cat /tmp/_igor_ml_register_err 2>/dev/null)"
            _ml_log error "${_register_fn} failed for $_name — SKIPPED: ${_reg_err:-unknown}"
            return 1
        fi
        _IGOR_REGISTERING_MODULE=""
    else
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="registration function missing"
        _ml_log error "$_name: required ${_register_fn} function missing — SKIPPED"
        return 1
    fi
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _ml_tui_phase_record "$_name.v1.hooks" "$_phase_started"
        _phase_started="$(_ml_now_ms)"
    fi

    _IGOR_LOADED_MODULES["$_name"]=1
    _IGOR_MODULE_STATUS["$_name"]="active"

    # Export STACK_DIR if module declares stack_dir in module.conf
    # e.g. nextcloud_docker + stack_dir=nextcloud → NEXTCLOUD_DOCKER_STACK_DIR=/path/config/stacks/nextcloud
    local _stack_dir
    _stack_dir="$(_ml_read_conf "$_dir" "stack_dir" 2>/dev/null || echo "")"
    if [[ -n "$_stack_dir" ]]; then
        local _stacks="${IGOR_STACKS:-${_IGOR_LOADER_DIR}/config/stacks}"
        local _full_stack="${_stacks}/${_stack_dir}"
        local _var_name="${_name^^}_STACK_DIR"
        _var_name="${_var_name//-/_}"       # normalize hyphens → underscores
        export "${_var_name}"="${_full_stack}"
        if [[ ! -d "$_full_stack" ]]; then
            _ml_log warn "Module ${_name}: stack dir missing at ${_full_stack}"
            _ml_log warn "  → First time? Run:  bash igor.sh --install ${_name}"
        fi
    fi

    _ml_log ok "Loaded module: $_name"
    [ "${IGOR_TUI_MODE:-false}" = true ] &&
        _ml_tui_phase_record "$_name.v1.finalize" "$_phase_started"
    return 0
}

_ml_load_v2() {
    local _name="$1" _dir="${_IGOR_MODULE_DIRS[$1]}" _reason _key _index_key _record _source _requires
    local _entrypoint _kind
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
    if [ -z "${_IGOR_V2_DATA[$_name]:-}" ]; then
        _ml_v2_validate "$_name" || return 1
    fi
    _requires="$(_ml_v2_module_requirements "$_name")" || return 1
    _entrypoint="$(_ml_v2_query "$_name" manifest.entrypoint 2>/dev/null)" || _entrypoint=""
    _IGOR_MODULE_ENTRYPOINT["$_name"]="$_entrypoint"
    _IGOR_MODULE_VERSION["$_name"]="$(_ml_v2_query "$_name" manifest.version 2>/dev/null || true)"
    _IGOR_OWNER_HAS_DOMAIN_EVENTS["$_name"]=0
    _reason="$(_ml_v2_requirement_failure "$_requires")" || {
        _IGOR_MODULE_STATUS["$_name"]="unavailable"
        _IGOR_MODULE_REASON["$_name"]="$_reason"
        return 1
    }
    # Preflight global contribution identities before executing any code.
    while IFS= read -r _key; do
        [ -n "$_key" ] || continue
        if [ -n "${_IGOR_CONTRIBUTIONS[$_key]:-}" ] && \
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

    if [ "$(_ml_v2_query "$_name" manifest.compat.v1_hooks)" = true ]; then
        local _entrypoint _register_fn
        _entrypoint="$(_ml_v2_query "$_name" manifest.entrypoint)"
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

    # Commit static declarations only after validation and compatibility
    # registration succeed. Local failures affect just their contribution.
    while IFS= read -r _key; do
        [ -n "$_key" ] || continue
        _record="$(_ml_v2_record "$_name" "$_key")" || continue
        _source="$(_ml_json_field "$_record" source)"
        _index_key="$_key"
        if [[ "$_key" = capability:* ]] && \
           [ -n "${_IGOR_CONTRIBUTION_OWNER[$_key]:-}" ] && \
           [ "${_IGOR_CONTRIBUTION_OWNER[$_key]}" != "$_name" ]; then
            _index_key="${_key}@${_name}"
        fi
        _ml_index_contribution "$_key" "$_name" "$_source" "$_record" || return 1
        _ml_index_requirement_fields "$_index_key" "$_record" || return 1
        _kind="${_key%%:*}"
        _ml_index_capability_runtime_fields "$_index_key" "$_record" || return 1
        [ "$_kind" = domain_event ] && _IGOR_OWNER_HAS_DOMAIN_EVENTS["$_name"]=1
        # Requirement availability is derived on inspection and dispatch so
        # another module loaded later in this startup can satisfy a local edge.
        case "$_key" in
            capability:*)
                if ! printf '%s' "$_record" | "$(_ml_python)" -c '
import json, sys
record = json.load(sys.stdin)
needed = {"capability_version", "description", "inputs", "safety", "privilege",
          "preconditions", "verification", "recovery", "affects"}
raise SystemExit(0 if needed <= record.keys() else 1)
'; then
                    _IGOR_CONTRIBUTION_STATE["$_index_key"]="unavailable"
                    _IGOR_CONTRIBUTION_REASON["$_index_key"]="contract_incomplete"
                elif printf '%s' "$_record" | "$(_ml_python)" -c '
import json,sys
record=json.load(sys.stdin)
props=record.get("inputs",{}).get("properties",{})
raise SystemExit(0 if any(spec.get("type")=="secret_ref" for spec in props.values()) else 1)
'; then
                    # No reviewed Wave E consumer currently needs a value.
                    # References remain valid contract data but cannot become
                    # an implicit module file-read channel.
                    _IGOR_CONTRIBUTION_STATE["$_index_key"]="unavailable"
                    _IGOR_CONTRIBUTION_REASON["$_index_key"]="secret_consumer_unavailable"
                elif [ "$(_ml_json_field "$_record" privilege)" = required ] &&
                     [ "$(_ml_json_field "$_record" capability_version)" = 2 ]; then
                    _IGOR_CONTRIBUTION_STATE["$_index_key"]="unavailable"
                    _IGOR_CONTRIBUTION_REASON["$_index_key"]="typed_privileged_output_adapter_unavailable"
                elif [ "$(_ml_json_field "$_record" privilege)" = required ] && ! {
                    [ "${_key#capability:}" = system.service.restart ] ||
                    {
                        [ "$_name" = system ] &&
                        [ "$(_ml_json_field "$_record" handler)" = system__privileged_marker ] &&
                        case "${_key#capability:}" in
                            system.package.install|system.package.upgrade|system.package.cache.clean|system.service.start|system.service.enable|system.storage.mount|system.storage.unmount|system.permissions.owner.set|system.permissions.group.set|system.permissions.mode.set|system.network.wifi.connect_known) true ;;
                            *) false ;;
                        esac
                    }
                }; then
                    # A required privilege declaration is executable only
                    # after Core has reviewed the exact argv adapter. Package
                    # administration is intentionally restricted to System's
                    # marker handler; service.restart retains the existing
                    # provider-neutral reviewed adapter.
                    _IGOR_CONTRIBUTION_STATE["$_index_key"]="unavailable"
                    _IGOR_CONTRIBUTION_REASON["$_index_key"]="privileged_adapter_unavailable"
                elif printf '%s' "$_record" | "$(_ml_python)" -c '
import json,sys
record=json.load(sys.stdin)
preconditions=record.get("preconditions",[])
verification=record.get("verification",{})
unsupported=any(p.get("kind")=="platform_feature" for p in preconditions)
reviewed={"system.memory.warning.apply":"system__apply_memory_warning",
          "system.memory.warning.readback":"system__read_memory_warning"}
memory_query=(record.get("owner")=="system" and record.get("id") in reviewed and
              record.get("handler")==reviewed[record["id"]] and
              record.get("capability_version")==2 and record.get("privilege")=="none" and
              verification=={"kind":"trusted_query","check_id":"system.memory.warning.consumer","required":True} and
              record.get("safety",{}).get("tier")==("CHANGE" if record["id"].endswith("apply") else "READ"))
package_upgrade_query=(record.get("owner")=="system" and record.get("id")=="system.package.upgrade" and
              record.get("handler")=="system__privileged_marker" and
              record.get("capability_version")==1 and record.get("privilege")=="required" and
              verification=={"kind":"trusted_query","check_id":"system.package.updates.empty","required":True} and
              record.get("safety",{}).get("tier")=="CHANGE")
package_install_query=(record.get("owner")=="system" and record.get("id")=="system.package.install" and
              record.get("handler")=="system__privileged_marker" and
              record.get("capability_version")==1 and record.get("privilege")=="required" and
              verification=={"kind":"trusted_query","check_id":"system.package.installed","required":True} and
              record.get("safety",{}).get("tier")=="CHANGE")
service_enable_query=(record.get("owner")=="system" and record.get("id")=="system.service.enable" and
              record.get("handler")=="system__privileged_marker" and
              record.get("capability_version")==1 and record.get("privilege")=="required" and
              verification=={"kind":"trusted_query","check_id":"system.service.enabled","required":True} and
              record.get("safety",{}).get("tier")=="CHANGE")
storage_mount=(record.get("owner")=="system" and record.get("id")=="system.storage.mount" and
              record.get("handler")=="system__privileged_marker" and
              record.get("capability_version")==1 and record.get("privilege")=="required" and
              preconditions==[
                  {"kind":"owner_active"},
                  {"kind":"trusted_validator","validator":"system.storage.mount.ready"},
              ] and
              verification=={"kind":"trusted_query","check_id":"system.storage.mount.present","required":True} and
              record.get("safety",{}).get("tier")=="CHANGE")
storage_unmount=(record.get("owner")=="system" and record.get("id")=="system.storage.unmount" and
              record.get("handler")=="system__privileged_marker" and
              record.get("capability_version")==1 and record.get("privilege")=="required" and
              preconditions==[
                  {"kind":"owner_active"},
                  {"kind":"trusted_validator","validator":"system.storage.unmount.ready"},
              ] and
              verification=={"kind":"trusted_query","check_id":"system.storage.mount.absent","required":True} and
              record.get("safety",{}).get("tier")=="CHANGE")
storage_admin=storage_mount or storage_unmount
permission_specs={
    "system.permissions.owner.set": (
        "system.permissions.owner.ready", "system.permissions.owner.matches"
    ),
    "system.permissions.group.set": (
        "system.permissions.group.ready", "system.permissions.group.matches"
    ),
    "system.permissions.mode.set": (
        "system.permissions.mode.ready", "system.permissions.mode.matches"
    ),
}
permission_admin=False
if record.get("id") in permission_specs:
    validator, check_id = permission_specs[record["id"]]
    permission_admin=(
        record.get("owner")=="system" and
        record.get("handler")=="system__privileged_marker" and
        record.get("capability_version")==1 and
        record.get("privilege")=="required" and
        preconditions==[
            {"kind":"owner_active"},
            {"kind":"trusted_validator","validator":validator},
        ] and
        verification=={"kind":"trusted_query","check_id":check_id,"required":True} and
        record.get("safety",{}).get("tier")=="CHANGE"
    )
wifi_connect_known=(
    record.get("owner")=="system" and
    record.get("id")=="system.network.wifi.connect_known" and
    record.get("handler")=="system__privileged_marker" and
    record.get("capability_version")==1 and
    record.get("privilege")=="required" and
    preconditions==[
        {"kind":"owner_active"},
        {"kind":"trusted_validator","validator":"system.network.wifi.connect_known.ready"},
    ] and
    verification=={
        "kind":"trusted_query",
        "check_id":"system.network.wifi.profile.active",
        "required":True,
    } and
    record.get("safety",{}).get("tier")=="CHANGE"
)
trusted_validators=[p for p in preconditions if p.get("kind")=="trusted_validator"]
reviewed_admin=storage_admin or permission_admin or wifi_connect_known
unsupported=unsupported or (bool(trusted_validators) and not reviewed_admin)
trusted_query=(memory_query or package_upgrade_query or package_install_query or
               service_enable_query or reviewed_admin)
unsupported=unsupported or (verification.get("kind") == "trusted_query" and not trusted_query)
unsupported=unsupported or (record.get("id") in reviewed and not memory_query)
raise SystemExit(0 if unsupported else 1)
'; then
                    _IGOR_CONTRIBUTION_STATE["$_index_key"]="unavailable"
                    _IGOR_CONTRIBUTION_REASON["$_index_key"]="trusted_adapter_unavailable"
                elif [ "$(_ml_json_field "$_record" recovery.class)" = snapshot_required ]; then
                    _IGOR_CONTRIBUTION_STATE["$_index_key"]="unavailable"
                    _IGOR_CONTRIBUTION_REASON["$_index_key"]="snapshot_precondition_unavailable"
                fi
                ;;
            automation:*)
                # Step 14A consumes data-only proposals; this never schedules or enables them.
                ;;
            configuration:*)
                if [ -z "$(_ml_json_field "$_record" schema)" ]; then
                    _IGOR_CONTRIBUTION_STATE["$_index_key"]="unavailable"
                    _IGOR_CONTRIBUTION_REASON["$_index_key"]="schema_missing"
                fi
                ;;
            relationship:*|lifecycle:*)
                _IGOR_CONTRIBUTION_STATE["$_index_key"]="unavailable"
                _IGOR_CONTRIBUTION_REASON["$_index_key"]="consumer deferred beyond Wave C"
                ;;
        esac
    done < <(_ml_v2_rows "$_name")
    _IGOR_LOADED_MODULES["$_name"]=1
    _IGOR_MODULE_STATUS["$_name"]="active"
    unset '_IGOR_MODULE_REASON['"$_name"']'
    if [ "$_name" = system ] && [ -n "${_IGOR_CONTRIBUTIONS[configuration:system.memory.preferences]:-}" ]; then
        unset IGOR_SYSTEM_MEMORY_WARNING_MIB IGOR_SYSTEM_MEMORY_WARNING_REVISION IGOR_SYSTEM_MEMORY_WARNING_STATE IGOR_SYSTEM_MEMORY_CONSUMER_ID
        _igor_configuration_memory_warning_load || _ml_log warn "System memory configuration consumption unavailable"
    fi
    _ml_log ok "Loaded Module API v2: $_name"
    return 0
}

igor_v2_contribution_get() {
    local _key="${1:-}:${2:-}" _owner="${_IGOR_CONTRIBUTION_OWNER[${1:-}:${2:-}]:-}"
    [ -n "$_owner" ] && _ml_owner_active "$_owner" || return 1
    [ "${_IGOR_CONTRIBUTION_STATE[$_key]:-}" = active ] || return 1
    local _record="${_IGOR_CONTRIBUTIONS[$_key]}" _requires
    _requires="$(printf '%s' "$_record" | "$(_ml_python)" -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("requires",{})))')" || return 1
    _ml_v2_requirement_failure "$_requires" >/dev/null || return 1
    printf '%s\n' "$_record"
}

# Return validated declarative schemas from active configuration owners. This
# is inspection data only: the module loader does not persist or apply values.
igor_configuration_declarations() {
    local _key _record
    {
        while IFS= read -r _key; do
            case "$_key" in configuration:*) ;; *) continue ;; esac
            _record="$(igor_v2_contribution_get configuration "${_key#configuration:}")" || continue
            [ -n "$(_ml_json_field "$_record" schema)" ] || continue
            printf '%s\n' "$_record"
        done < <(printf '%s\n' "${!_IGOR_CONTRIBUTIONS[@]}" | sort)
    } | "$(_ml_python)" -c '
import json, sys
rows = []
for line in sys.stdin:
    if not line.strip():
        continue
    record = json.loads(line)
    rows.append({"id": record["id"], "owner": record["owner"],
                 "source": record["source"], "schema": record["schema"]})
print(json.dumps(rows, sort_keys=True, separators=(",", ":")))
'
}

# The same owner-stamped contribution index backs active dispatch and
# read-only inspection. Duplicate providers retain their @owner index keys;
# selection is deliberately left to the capability resolver.
_ml_capability_resolution_ids() {
    local _id="${1:-}" _key _item
    local -A _seen=()
    [ -n "$_id" ] || return 2
    _seen["$_id"]=1
    printf '%s\n' "$_id"
    while IFS= read -r _key; do
        case "$_key" in
            "capability:$_id"|"capability:$_id@"*)
                for _item in ${_IGOR_REQ_CAPABILITIES[$_key]:-} ${_IGOR_CAPABILITY_DEPENDENCIES[$_key]:-}; do
                    [ -n "$_item" ] || continue
                    if [ -z "${_seen[$_item]:-}" ]; then
                        _seen["$_item"]=1
                        printf '%s\n' "$_item"
                    fi
                done
                ;;
        esac
    done < <(printf '%s\n' "${!_IGOR_CONTRIBUTIONS[@]}" | sort)
}

_ml_capability_filter_contains() {
    local _filter="$1" _candidate="$2" _item
    while IFS= read -r _item; do
        [ "$_item" = "$_candidate" ] && return 0
    done <<< "$_filter"
    return 1
}

igor_capability_list() {
    local _filter_ids="${1:-}" _key _record_id _owner _record _state _reason _dynamic _base_state _owner_active
    {
        while IFS= read -r _key; do
            case "$_key" in capability:*|legacy_action:*) ;; *) continue ;; esac
            if [[ "$_key" = capability:* ]]; then
                _record_id="${_key#capability:}"
                _record_id="${_record_id%%@*}"
            else
                _record_id="${_key#legacy_action:}"
            fi
            if [ -n "$_filter_ids" ] && ! _ml_capability_filter_contains "$_filter_ids" "$_record_id"; then
                continue
            fi
            _owner="${_IGOR_CONTRIBUTION_OWNER[$_key]:-}"
            _record="${_IGOR_CONTRIBUTIONS[$_key]:-}"
            if [[ "$_key" = legacy_action:* ]]; then
                local _entry="${_IGOR_CAPABILITIES[${_key##*.}]:-}"
                _record="$("$(_ml_python)" - "${_key#legacy_action:}" "$_owner" "$_record" "$_entry" <<'PY'
import json, sys
ident, owner, handler, entry = sys.argv[1:]
parts = entry.split("|")
tier = parts[3] if len(parts) > 3 and parts[3] in {"READ", "CHANGE", "DESTROY"} else "CHANGE"
print(json.dumps({"kind": "legacy_action", "id": ident, "owner": owner,
                  "handler": handler, "description": parts[0] if parts else "",
                  "capability_version": 1,
                  "inputs": {"properties": {}, "required": [], "additionalProperties": False},
                  "safety": {"tier": tier}, "privilege": "legacy_internal",
                  "preconditions": [], "verification": {"kind": "none", "required": False},
                  "recovery": {"class": "not_applicable"}, "affects": []},
                 separators=(",", ":")))
PY
)" || return 1
            fi
            _base_state="${_IGOR_CONTRIBUTION_STATE[$_key]:-active}"
            _reason="${_IGOR_CONTRIBUTION_REASON[$_key]:-}"
            _dynamic=""
            if _ml_owner_active "$_owner"; then _owner_active=true; else _owner_active=false; fi
            if [ -z "$_reason" ] || { [ "$_owner_active" = true ] && [ "$_base_state" = active ]; }; then
                _dynamic="$(_ml_contribution_dynamic_failure "$_key" 2>/dev/null || true)"
            fi
            if [ "$_owner_active" != true ]; then
                _state=inactive
            elif [ "$_base_state" != active ]; then
                _state="$_base_state"
            elif [ -n "$_dynamic" ]; then
                _state=unavailable
            else
                _state=active
            fi
            [ -n "$_reason" ] || _reason="$_dynamic"
            if [ "$_state" = inactive ]; then
                _reason="${_IGOR_MODULE_STATUS[$_owner]:-inactive}${_IGOR_MODULE_REASON[$_owner]:+ (${_IGOR_MODULE_REASON[$_owner]})}"
            fi
            printf '%s\0' "$_key" "$_owner" "${_IGOR_CONTRIBUTION_SOURCE[$_key]:-unknown}" "$_state" "$_reason" "$_record"
        done < <(printf '%s\n' "${!_IGOR_CONTRIBUTIONS[@]}" | sort)
    } | "$(_ml_python)" -c '
import json, sys
raw = sys.stdin.buffer.read().split(b"\0")
if raw[-1:] == [b""]: raw.pop()
if len(raw) % 6: raise SystemExit("invalid contribution records")
result = []
for index in range(0, len(raw), 6):
    key, owner, source, state, reason, record = (item.decode() for item in raw[index:index + 6])
    record = json.loads(record)
    result.append({"index_key": key, "id": record["id"], "owner": owner,
                   "provider": owner, "source": source, "availability": state,
                   "unavailable_reason": reason or None, "descriptor": record})
sys.path.insert(0, sys.argv[1])
wanted=set(sys.argv[4].splitlines()) if sys.argv[4] else None
from configuration import capability_records
core_rows=capability_records(sys.argv[2]=="true")
from deployment_attachment import capability_records as deployment_capability_records
core_rows.extend(deployment_capability_records(sys.argv[3]=="true"))
if wanted is not None:
    core_rows=[row for row in core_rows if row.get("id") in wanted]
result.extend(core_rows)
print(json.dumps(result, sort_keys=True, separators=(",", ":")))
' "${_IGOR_LOADER_DIR}/core/lib" "$(_ml_owner_active system && printf true || printf false)" "$(_ml_owner_active nextcloud_docker && printf true || printf false)" "$_filter_ids"
}


igor_capability_inspect() {
    local _id="${1:-}" _provider="${2:-}" _resolution_ids
    _resolution_ids="$(_ml_capability_resolution_ids "$_id")" || return 1
    igor_capability_list "$_resolution_ids" | "$(_ml_python)" -c '
import json, sys
capability_id, provider = sys.argv[1:]
rows = [r for r in json.load(sys.stdin) if r["id"] == capability_id]
active = [r for r in rows if r["availability"] == "active"]
selected = [r for r in active if r["provider"] == provider] if provider else active
resolution = ("unavailable" if not selected else "ambiguous" if len(selected) > 1 else "resolved")
print(json.dumps({"capability_id": capability_id, "resolution": resolution,
                  "selected_provider": selected[0]["provider"] if len(selected) == 1 else None,
                  "providers": rows}, sort_keys=True, separators=(",", ":")))
' "$_id" "$_provider"
}

igor_v2_invoke() {
    local _kind="${1:-}" _id="${2:-}" _input="${3:-}" _key _owner _handler _timeout _entrypoint
    [ -n "$_input" ] || _input='{}'
    case "$_kind" in observer|check|knowledge) ;; *) return 1 ;; esac
    _key="${_kind}:${_id}"
    [ "$(igor_contribution_state "$_key")" = active ] || return 1
    _owner="${_IGOR_CONTRIBUTION_OWNER[$_key]:-}"
    [ -n "$_owner" ] || return 1
    _handler="${_IGOR_HANDLER_FUNCTION[$_key]:-}"
    [ -n "$_handler" ] || return 1
    _timeout="${_IGOR_HANDLER_TIMEOUT[$_key]:-30}"
    _entrypoint="${_IGOR_MODULE_ENTRYPOINT[$_owner]:-}"
    [ -n "$_entrypoint" ] || return 1
    # shellcheck source=core/lib/module_handler.sh
    source "${_IGOR_LOADER_DIR}/core/lib/module_handler.sh"
    V2_HANDLER_ENTRYPOINT="$_entrypoint" \
    V2_HANDLER_SYNTAX_VALIDATED=1 \
    V2_HANDLER_DOMAIN_EVENTS="${_IGOR_OWNER_HAS_DOMAIN_EVENTS[$_owner]:-0}" \
        _ml_bash_handler_invoke \
        "${_IGOR_MODULE_DIRS[$_owner]}" "$_owner" "$_handler" "$_id" "$_timeout" "$_input"
}

igor_v2_knowledge() {
    local _id="${1:-}" _record _owner _relative _base _file
    _record="$(igor_v2_contribution_get knowledge "$_id")" || return 1
    _owner="${_IGOR_CONTRIBUTION_OWNER[knowledge:${_id}]}"
    _relative="$(_ml_json_field "$_record" path)"
    [ -n "$_relative" ] || return 1
    _base="$(realpath -e -- "${_IGOR_MODULE_DIRS[$_owner]}")" || return 1
    _file="$(realpath -e -- "$_base/$_relative")" || return 1
    case "$_file" in "$_base"/*) cat -- "$_file" ;; *) return 1 ;; esac
}

igor_v2_collect_knowledge() {
    local _key
    while IFS= read -r _key; do
        case "$_key" in knowledge:*) igor_v2_knowledge "${_key#knowledge:}" || true ;; esac
    done < <(printf '%s\n' "${!_IGOR_CONTRIBUTIONS[@]}" | sort)
}

# ---------------------------------------------------------------------------
# igor_load_all_modules
#
#   Convenience: discover → sort → load all modules in dependency order.
#   Returns 0 even if some modules fail (errors are logged).
# ---------------------------------------------------------------------------
igor_load_all_modules() {
    # Call igor_discover_modules directly (NOT in a subshell) so that
    # _IGOR_MODULE_DIRS is populated in the current shell context.
    # Discard stdout — we'll read from _IGOR_MODULE_DIRS directly.
    igor_discover_modules > /dev/null
    _ml_v2_prepare_all

    local _names=("${!_IGOR_MODULE_DIRS[@]}")
    [ ${#_names[@]} -eq 0 ] && return 0
    mapfile -t _names < <(printf '%s\n' "${_names[@]}" | sort)

    local _sorted_list
    _sorted_list="$(igor_sort_modules "${_names[@]}")"

    local _name _seen_names=" " _edges
    while IFS= read -r _name; do
        [ -n "$_name" ] || continue
        _seen_names+="$_name "
        igor_load_module "$_name" || true
    done <<< "$_sorted_list"

    for _name in "${_names[@]}"; do
        if [[ "$_seen_names" != *" $_name "* ]] && [ "${_IGOR_MODULE_STATUS[$_name]:-}" != disabled ]; then
            _IGOR_MODULE_STATUS["$_name"]="unavailable"
            if [ "${_IGOR_MODULE_API[$_name]:-1}" = 2 ]; then
                _edges="$(_ml_v2_query "$_name" manifest.requirements.required_modules 2>/dev/null)"
                _edges="${_edges//$'\n'/, }"
                [ -n "$_edges" ] || _edges="$(_ml_v2_query "$_name" manifest.requirements.required_capabilities 2>/dev/null)"
            else
                _edges="$(_ml_read_conf "${_IGOR_MODULE_DIRS[$_name]}" depends_on 2>/dev/null)"
            fi
            _IGOR_MODULE_REASON["$_name"]="dependency ordering cycle blocks $_name (declared edges: ${_edges:-unknown})"
        fi
    done

    return 0
}

# ---------------------------------------------------------------------------
# igor_module_install <module_name>
#
#   Run first-time setup for a module.
#   Calls <name>__install() if it exists. No-op if the function is absent.
#   Idempotency is the responsibility of each module's __install hook.
# ---------------------------------------------------------------------------
igor_module_install() {
    local _name="${1:-}"
    [ -n "$_name" ] || { _ml_log error "igor_module_install: no module name given"; return 1; }

    if ! igor_has_module "$_name"; then
        _ml_log error "Module '${_name}' is not loaded — run igor_load_all_modules first"
        return 1
    fi

    local _install_fn="${_name}__install"
    if declare -f "$_install_fn" >/dev/null 2>&1; then
        _ml_log info "Running ${_install_fn}..."
        if "$_install_fn"; then
            _ml_log ok "${_name} install complete"
        else
            _ml_log error "${_name}__install failed"
            return 1
        fi
    else
        _ml_log info "Module '${_name}' has no __install hook — nothing to do"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# igor_module_upgrade <module_name>
#
#   Run post-update migration for a module.
#   Calls <name>__upgrade() if it exists. No-op if the function is absent.
# ---------------------------------------------------------------------------
igor_module_upgrade() {
    local _name="${1:-}"
    [ -n "$_name" ] || { _ml_log error "igor_module_upgrade: no module name given"; return 1; }

    if ! igor_has_module "$_name"; then
        _ml_log error "Module '${_name}' is not loaded — run igor_load_all_modules first"
        return 1
    fi

    local _upgrade_fn="${_name}__upgrade"
    if declare -f "$_upgrade_fn" >/dev/null 2>&1; then
        _ml_log info "Running ${_upgrade_fn}..."
        if "$_upgrade_fn"; then
            _ml_log ok "${_name} upgrade complete"
        else
            _ml_log error "${_name}__upgrade failed"
            return 1
        fi
    else
        _ml_log info "Module '${_name}' has no __upgrade hook — nothing to do"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# igor_module_remove <module_name>
#
#   Run cleanup for a module. Always asks for confirmation before proceeding.
#   Calls <name>__uninstall() if it exists. No-op if the function is absent.
#   DESTROY-tier: the hook itself may contain further DESTROY prompts.
# ---------------------------------------------------------------------------
igor_module_remove() {
    local _name="${1:-}"
    [ -n "$_name" ] || { _ml_log error "igor_module_remove: no module name given"; return 1; }

    if ! igor_has_module "$_name"; then
        _ml_log error "Module '${_name}' is not loaded — run igor_load_all_modules first"
        return 1
    fi

    local _uninstall_fn="${_name}__uninstall"
    if ! declare -f "$_uninstall_fn" >/dev/null 2>&1; then
        _ml_log info "Module '${_name}' has no __uninstall hook — nothing to do"
        return 0
    fi

    printf '\n  [module_loader] ⚠  Removing module: %s\n' "$_name"
    printf '  [module_loader]    This may make destructive changes. Type YES to confirm: '
    local _confirm
    read -r _confirm
    if [ "$_confirm" != "YES" ]; then
        _ml_log info "Remove cancelled."
        return 0
    fi

    _ml_log info "Running ${_uninstall_fn}..."
    if "$_uninstall_fn"; then
        _ml_log ok "${_name} removal complete"
    else
        _ml_log error "${_name}__uninstall failed"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# igor_register_hook <hook_name> <function_name>
#
#   Add <function_name> to the registry for <hook_name>.
#   The same function can only be registered once per hook (idempotent).
# ---------------------------------------------------------------------------
igor_register_hook() {
    local _hook="$1" _fn="$2"
    [ -n "$_hook" ] || { _ml_log error "igor_register_hook: missing hook name"; return 1; }
    [ -n "$_fn" ]   || { _ml_log error "igor_register_hook: missing function name"; return 1; }
    _ml_valid_function "$_fn" || { _ml_log error "igor_register_hook: invalid function name: $_fn"; return 1; }

    local _existing="${_IGOR_HOOKS[$_hook]:-}"

    # Idempotency: skip if already registered
    local _entry
    for _entry in $_existing; do
        [ "$_entry" = "$_fn" ] && return 0
    done

    _IGOR_HOOKS["$_hook"]="${_existing:+$_existing }${_fn}"
    _IGOR_HOOK_OWNERS["${_hook}:${_fn}"]="${_IGOR_REGISTERING_MODULE:-}"
    if [ -n "${_IGOR_REGISTERING_MODULE:-}" ]; then
        local _canonical_fn="${_fn//__/.}"
        _ml_index_contribution "legacy_hook:legacy.${_IGOR_REGISTERING_MODULE}.${_hook}.${_canonical_fn}" \
            "$_IGOR_REGISTERING_MODULE" "module.sh" "$_hook:$_fn" || return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# igor_register_menu_item <key> <label> <load_type> <load_arg> <menu_func>
#
#   Register a custom main-menu entry for a module.
#   <key>       — single character or short string the user types at the menu
#   <label>     — description shown in recent-items and on dispatch
#   <load_type> — "module" (calls _igor_load_module) or "subsystem" (calls _igor_load_subsystem)
#   <load_arg>  — module name OR "subsystem_id path/to/core.sh"
#   <menu_func> — function to call after loading (e.g. menu_foo)
#
#   Idempotent: re-registering the same key overwrites the previous entry.
#
#   Example (inside a module's __register function):
#     igor_register_menu_item "x" "MY MODULE — does stuff" "module" "my_module" "menu_my_module"
# ---------------------------------------------------------------------------
igor_register_menu_item() {
    local _key="$1" _label="$2" _type="$3" _arg="$4" _func="$5"
    [ -n "$_key" ]   || { _ml_log error "igor_register_menu_item: missing key";   return 1; }
    [ -n "$_label" ] || { _ml_log error "igor_register_menu_item: missing label"; return 1; }
    [ -n "$_func" ]  || { _ml_log error "igor_register_menu_item: missing func";  return 1; }
    _ml_valid_function "$_func" || { _ml_log error "igor_register_menu_item: invalid func"; return 1; }
    local _prior_owner="${_IGOR_MENU_OWNERS[$_key]:-}"
    if [ -n "$_prior_owner" ] && [ "$_prior_owner" != "${_IGOR_REGISTERING_MODULE:-}" ] && _ml_owner_active "$_prior_owner"; then
        _ml_log error "igor_register_menu_item: key already owned by active module $_prior_owner"
        return 1
    fi
    _IGOR_MENU_REGISTRY["$_key"]="${_label}|${_type}|${_arg}|${_func}"
    _IGOR_MENU_OWNERS["$_key"]="${_IGOR_REGISTERING_MODULE:-}"
    if [ -n "${_IGOR_REGISTERING_MODULE:-}" ]; then
        _ml_index_contribution "legacy_menu:legacy.${_IGOR_REGISTERING_MODULE}.${_key}" \
            "$_IGOR_REGISTERING_MODULE" "module.sh" "$_func" || return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# igor_dispatch_menu_item <key>
#
#   Look up <key> in _IGOR_MENU_REGISTRY and dispatch to the registered entry.
#   Returns 0 if dispatched, 1 if key not found (caller handles unknown input).
# ---------------------------------------------------------------------------
igor_dispatch_menu_item() {
    local _key="$1"
    local _entry="${_IGOR_MENU_REGISTRY[$_key]:-}"
    [ -n "$_entry" ] || return 1
    _ml_owner_active "${_IGOR_MENU_OWNERS[$_key]:-}" || return 1

    local _label _type _arg _func
    IFS='|' read -r _label _type _arg _func <<< "$_entry"

    _igor_record_recent "$_key" "$_label"
    case "$_type" in
        module)
            # Registered module names use the lifecycle loader. Preserve legacy
            # menu-file arguments such as "services" for existing registrations.
            if [ -n "${_IGOR_MODULE_DIRS[$_arg]:-}" ]; then
                igor_load_module "$_arg" || return 1
            else
                _igor_load_module "$_arg" || return 1
            fi
            ;;
        subsystem) _igor_load_subsystem $_arg || return 1 ;;   # _arg may be "id path/to/core.sh"
    esac
    "$_func"
}

# ---------------------------------------------------------------------------
# igor_get_hooks <hook_name>
#
#   Print the list of functions registered for <hook_name>, one per line.
#   Prints nothing if no functions are registered.
# ---------------------------------------------------------------------------
igor_get_hooks() {
    local _hook="$1"
    [ -n "$_hook" ] || return 0
    local _entry _owner _replacement
    for _entry in ${_IGOR_HOOKS[$_hook]:-}; do
        # A v2 knowledge record with the legacy canonical identity replaces
        # this one consumer's old view. Other v1 hooks stay operational.
        _owner="${_IGOR_HOOK_OWNERS[${_hook}:${_entry}]:-}"
        _replacement="knowledge:legacy.${_owner}.${_hook}.${_entry//__/.}"
        if [ "$_hook" = ai_knowledge ] && \
           [ -n "${_IGOR_CONTRIBUTIONS[$_replacement]:-}" ] && \
           [ "$(igor_contribution_state "$_replacement")" = active ]; then
            continue
        fi
        _ml_owner_active "$_owner" && printf '%s\n' "$_entry"
    done
}

# ---------------------------------------------------------------------------
# igor_run_all_hooks <hook_name> [arg...]
#
#   Run every function registered for <hook_name>, in registration order.
#   Each call gets a 30-second timeout (IGOR_HOOK_TIMEOUT overrides).
#   Failures are logged but do not stop subsequent hooks.
#   Returns 0 if all hooks succeeded, 1 if any hook failed.
# ---------------------------------------------------------------------------
igor_run_all_hooks() {
    local _hook="$1"; shift
    [ -n "$_hook" ] || { _ml_log error "igor_run_all_hooks: missing hook name"; return 1; }

    local _timeout="${IGOR_HOOK_TIMEOUT:-30}"
    local _any_fail=0
    local _fn

    while IFS= read -r _fn; do
        [ -n "$_fn" ] || continue
        if ! declare -f "$_fn" >/dev/null 2>&1; then
            _ml_log warn "Hook $_hook: function $_fn not found — skipping"
            _any_fail=1
            continue
        fi

        local _hook_err_file
        _hook_err_file=$(mktemp "${TMPDIR:-/tmp}/igor-hook.XXXXXXXX") || {
            _ml_log warn "Hook $_hook: could not create private error log"
            _any_fail=1
            continue
        }
        # Hooks are noninteractive. Do not let a child consume the hook-list
        # stream (or any UI input when this runner is reused elsewhere).
        if timeout "$_timeout" bash -c "$(declare -f "$_fn"); $_fn $(printf '%q ' "$@")" \
            </dev/null 2>"$_hook_err_file"; then
            rm -f -- "$_hook_err_file"
            continue
        else
            local _exit_code=$?
            local _hook_err
            _hook_err="$(cat "$_hook_err_file" 2>/dev/null)"
            rm -f -- "$_hook_err_file"
            if [ "$_exit_code" -eq 124 ]; then
                _ml_log warn "Hook $_hook: $_fn timed out after ${_timeout}s"
            else
                _ml_log warn "Hook $_hook: $_fn failed (exit ${_exit_code}): ${_hook_err:-}"
            fi
            _any_fail=1
        fi
    done < <(igor_get_hooks "$_hook")

    return $_any_fail
}

# ---------------------------------------------------------------------------
# igor_load_capabilities
#
#   Calls all functions registered for the "ai_capabilities" hook and parses
#   their output into the _IGOR_CAPABILITIES associative array.
#
#   Each module's ai_capabilities function emits one or more blocks:
#     ACTION <name>
#     DESCRIPTION <text>
#     FUNCTION <bash_function_name>
#     LOAD_MODULE <module_name>
#     TIER READ|CHANGE|DESTROY
#     PROBLEMS <comma-separated keywords>
#     MENU_PATH <human-readable path>
#
#   Stored as: _IGOR_CAPABILITIES[name]="desc|fn|mod|tier|problems|menu_path"
#   Idempotent — re-running clears and repopulates.
# ---------------------------------------------------------------------------
igor_load_capabilities() {
    _IGOR_CAPABILITIES=()   # clear before repopulating
    _IGOR_CAPABILITY_OWNERS=()
    local _indexed
    for _indexed in "${!_IGOR_CONTRIBUTIONS[@]}"; do
        case "$_indexed" in
            legacy_action:*)
                unset '_IGOR_CONTRIBUTIONS['"$_indexed"']'
                unset '_IGOR_CONTRIBUTION_OWNER['"$_indexed"']'
                unset '_IGOR_CONTRIBUTION_SOURCE['"$_indexed"']'
                unset '_IGOR_CONTRIBUTION_STATE['"$_indexed"']'
                unset '_IGOR_CONTRIBUTION_REASON['"$_indexed"']'
                ;;
        esac
    done

    local _fns="${_IGOR_HOOKS[ai_capabilities]:-}"
    [ -z "$_fns" ] && return 0

    local _fn
    for _fn in $_fns; do
        _ml_owner_active "${_IGOR_HOOK_OWNERS[ai_capabilities:${_fn}]:-}" || continue
        declare -f "$_fn" &>/dev/null || continue
        local _raw; _raw=$("$_fn" 2>/dev/null) || continue
        [ -z "$_raw" ] && continue

        # Parse blocks separated by blank lines or ACTION lines
        local _name="" _desc="" _func="" _mod="" _tier="CHANGE" _probs="" _mpath=""
        while IFS= read -r _line || [ -n "$_line" ]; do
            case "$_line" in
                ACTION\ *)
                    # Save previous block if complete
                    if [ -n "$_name" ] && [ -n "$_func" ]; then
                        if _ml_valid_name "$_name" && _ml_valid_function "$_func" &&
                           [[ "$_tier" =~ ^(READ|CHANGE|DESTROY)$ ]] &&
                           { [ -z "$_mod" ] || _ml_valid_name "$_mod"; } &&
                           _ml_capability_function_available "$_func" "$_mod"; then
                            _desc="${_desc//|//}"; _probs="${_probs//|/,}"; _mpath="${_mpath//|/／}"
                            _IGOR_CAPABILITIES["$_name"]="${_desc}|${_func}|${_mod}|${_tier}|${_probs}|${_mpath}"
                            # LOAD_MODULE names a lazy menu file; ownership is
                            # always the manifest module that registered this
                            # capability so disabled parents cannot bypass the
                            # lifecycle boundary through a child file.
                            _IGOR_CAPABILITY_OWNERS["$_name"]="${_IGOR_HOOK_OWNERS[ai_capabilities:${_fn}]:-}"
                            if [ -n "${_IGOR_CAPABILITY_OWNERS[$_name]}" ]; then
                                _ml_index_contribution "legacy_action:legacy.${_IGOR_CAPABILITY_OWNERS[$_name]}.${_name}" \
                                    "${_IGOR_CAPABILITY_OWNERS[$_name]}" "ai_capabilities hook" "$_func" || true
                            fi
                        fi
                    fi
                    _name="${_line#ACTION }"; _name="${_name## }"; _name="${_name%% }"
                    _desc=""; _func=""; _mod=""; _tier="CHANGE"; _probs=""; _mpath=""
                    ;;
                DESCRIPTION\ *)  _desc="${_line#DESCRIPTION }" ;;
                FUNCTION\ *)     _func="${_line#FUNCTION }" ;;
                LOAD_MODULE\ *)  _mod="${_line#LOAD_MODULE }" ;;
                TIER\ *)         _tier="${_line#TIER }" ;;
                PROBLEMS\ *)     _probs="${_line#PROBLEMS }" ;;
                MENU_PATH\ *)    _mpath="${_line#MENU_PATH }" ;;
            esac
        done <<< "$_raw"

        # Save final block
        if [ -n "$_name" ] && [ -n "$_func" ]; then
            if _ml_valid_name "$_name" && _ml_valid_function "$_func" &&
               [[ "$_tier" =~ ^(READ|CHANGE|DESTROY)$ ]] &&
               { [ -z "$_mod" ] || _ml_valid_name "$_mod"; } &&
               _ml_capability_function_available "$_func" "$_mod"; then
                _desc="${_desc//|//}"; _probs="${_probs//|/,}"; _mpath="${_mpath//|/／}"
                _IGOR_CAPABILITIES["$_name"]="${_desc}|${_func}|${_mod}|${_tier}|${_probs}|${_mpath}"
                _IGOR_CAPABILITY_OWNERS["$_name"]="${_IGOR_HOOK_OWNERS[ai_capabilities:${_fn}]:-}"
                if [ -n "${_IGOR_CAPABILITY_OWNERS[$_name]}" ]; then
                    _ml_index_contribution "legacy_action:legacy.${_IGOR_CAPABILITY_OWNERS[$_name]}.${_name}" \
                        "${_IGOR_CAPABILITY_OWNERS[$_name]}" "ai_capabilities hook" "$_func" || true
                fi
            fi
        fi
    done

    return 0
}


# Boundary H — compiled Module API v2 startup fast path.
# Install overrides only after all compatibility loader functions above exist,
# so the fast path can delegate to the original implementation on any failure.
if [ -f "${_IGOR_LOADER_DIR}/core/lib/module_loader_fast.sh" ]; then
    # shellcheck source=core/lib/module_loader_fast.sh
    source "${_IGOR_LOADER_DIR}/core/lib/module_loader_fast.sh"
fi
