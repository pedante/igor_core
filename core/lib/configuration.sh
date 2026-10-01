#!/usr/bin/env bash
# Core configuration adapter. The canonical dispatcher owns approval/history;
# this component owns typed desired values, never observed system state.

_igor_configuration_call() {
    local _action="$1" _fields="${2:-}" _request
    [ -n "$_fields" ] || _fields='{}'
    _request="$(printf '%s' "$_fields" | python3 -c '
import json,sys
r=json.load(sys.stdin)
r.update(data_dir=sys.argv[1],igor_dir=sys.argv[2],inherited_verbose=sys.argv[3] or None,session_id=sys.argv[4] or None)
print(json.dumps(r,separators=(",", ":")))
' "${IGOR_DATA_DIR:-${IGOR_DIR}/data}" "$IGOR_DIR" "${verbose:-}" "${IGOR_AI_EVENT_SESSION_ID:-$$}")" || return 1
    printf '%s' "$_request" | python3 "${_IGOR_LOADER_DIR:-${IGOR_DIR}}/core/lib/configuration.py" "$_action"
}

# Read-only schema projection for generic frontends. This creates no store and
# exposes no desired/secret values.
igor_configuration_declarations() {
    _igor_configuration_call declarations
}

_igor_configuration_precondition() {
    local _proposal="$1" _inputs _id
    _id="$(_igor_capability_field "$_proposal" capability_id)" || return 1
    case "$_id" in core.configuration.*) ;; *) return 0 ;; esac
    _inputs="$(_igor_capability_field "$_proposal" inputs)" || return 1
    _igor_configuration_call prepare "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); r["capability_id"]=sys.argv[2]; print(json.dumps(r))' "$_inputs" "$_id")" >/dev/null
}

_igor_configuration_invoke() {
    local _proposal="$1" _inputs _id _action
    _id="$(_igor_capability_field "$_proposal" capability_id)" || return 1
    _inputs="$(_igor_capability_field "$_proposal" inputs)" || return 1
    case "$_id" in
        core.configuration.ai_verbose.set) _action="set" ;;
        core.configuration.ai_verbose.verify) _action=verify-session ;;
        core.configuration.restore) _action=restore ;;
        *) return 1 ;;
    esac
    _inputs="$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); r["operation_id"]=sys.argv[2]; print(json.dumps(r))' "$_inputs" "${IGOR_HISTORY_OPERATION_ID:-}")" || return 1
    _igor_configuration_call "$_action" "$_inputs"
}

igor_configuration_cli() {
    local _action="${1:-status}" _argument="${2:-}" _fields
    case "$_action" in
        status|list|export) [ -z "$_argument" ] || return 2; _igor_configuration_call "$_action" ;;
        inspect) [ "${_argument:-ai.verbose}" = ai.verbose ] || return 2; _igor_configuration_call inspect ;;
        validate)
            _fields="$(python3 -c 'import json,sys; print(json.dumps({"changes_document":sys.argv[1]}))' "$_argument")" || return 2
            _igor_configuration_call validate "$_fields" ;;
        *) printf 'Usage: --configuration [status|list|inspect ai.verbose|export|validate CHANGES_JSON]\n' >&2; return 2 ;;
    esac
}

# Consume only the current authoritative resolution. This records no observed
# fact and never treats a desired commit as proof of application.
_ai_configuration_verbose_load() {
    local _state _value _revision
    _state="$(_igor_configuration_call resolve)" || return 1
    _value="$(printf '%s' "$_state" | python3 -c 'import json,sys; print("true" if json.load(sys.stdin)["resolved"]["value"] else "false")')" || return 1
    _revision="$(printf '%s' "$_state" | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])')" || return 1
    [ -z "${1:-}" ] || [ "$_revision" = "$1" ] || return 1
    IGOR_VERBOSE="$_value"
    IGOR_VERBOSE_REVISION="$_revision"
    export IGOR_VERBOSE IGOR_VERBOSE_REVISION
}

_ai_configuration_verbose_set() {
    local _value="$1" _state _revision _token _payload _committed
    case "$_value" in true|false) ;; *) return 2 ;; esac
    declare -f igor_capability_prepare >/dev/null 2>&1 || {
        # The loader already sources this adapter; avoid recursive lint loading.
        # shellcheck source=/dev/null
        source "${IGOR_DIR}/core/lib/module_loader.sh"
    }
    _state="$(_igor_configuration_call inspect)" || return 1
    _revision="$(printf '%s' "$_state" | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])')" || return 1
    _token="$(printf '%s' "$_state" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state_token"])')" || return 1
    _payload="$(python3 -c 'import json,sys; print(json.dumps({"tool":"run_capability","id":"core.configuration.ai_verbose.set","provider":"core","inputs":{"value":sys.argv[1]=="true","revision":int(sys.argv[2]),"state":sys.argv[3]}}))' "$_value" "$_revision" "$_token")" || return 1
    local IGOR_HISTORY_INTERFACE=ai_settings
    export IGOR_HISTORY_INTERFACE
    IGOR_CAPABILITY_LAST_RESULT=""
    ai_execute_tool "$_payload" || return 1
    [ "$(printf '%s' "$IGOR_CAPABILITY_LAST_RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["outcome"])')" = success ] || return 1
    _committed="$(( _revision + 1 ))"
    _state="$(_igor_configuration_call inspect)" || return 1
    [ "$(printf '%s' "$_state" | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])')" = "$_committed" ] || return 1
    _ai_configuration_verbose_load "$_committed" || return 1
    _payload="$(python3 -c 'import json,sys; print(json.dumps({"tool":"run_capability","id":"core.configuration.ai_verbose.verify","provider":"core","inputs":{"revision":int(sys.argv[1])}}))' "$_committed")" || return 1
    # Independent READ verification of this session's consumption, not global
    # application success. Guide still owns its normal READ confirmation.
    ai_execute_tool "$_payload"
}
