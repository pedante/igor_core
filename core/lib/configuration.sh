#!/usr/bin/env bash
# Core configuration adapter. The canonical dispatcher owns approval/history;
# this component owns typed desired values, never observed system state.

_igor_configuration_call() {
    local _action="$1" _fields="${2:-}" _request _active='["core"]'
    [ -n "$_fields" ] || _fields='{}'
    if declare -f _ml_owner_active >/dev/null 2>&1 && _ml_owner_active system; then
        _active='["core","system"]'
    fi
    _request="$(printf '%s' "$_fields" | python3 -c '
import json,sys
r=json.load(sys.stdin)
r.update(data_dir=sys.argv[1],igor_dir=sys.argv[2],inherited_verbose=sys.argv[3] or None,session_id=sys.argv[4] or None)
r["active_owners"]=json.loads(sys.argv[5])
print(json.dumps(r,separators=(",", ":")))
' "${IGOR_DATA_DIR:-${IGOR_DIR}/data}" "$IGOR_DIR" "${verbose:-}" "${IGOR_AI_EVENT_SESSION_ID:-$$}" "$_active")" || return 1
    printf '%s' "$_request" | python3 "${_IGOR_LOADER_DIR:-${IGOR_DIR}}/core/lib/configuration.py" "$_action"
}

# Startup-only Core consumer.  Configuration Service remains authoritative: the
# Python process reads the current private SQLite store and compatibility source,
# but does not discover module schemas or compute a global state token because
# this consumer needs only ai.verbose plus the current global revision.
_igor_configuration_ai_verbose_resolve() {
    IGOR_CONFIGURATION_ROOT="$IGOR_DIR" \
    IGOR_CONFIGURATION_DATA_DIR="${IGOR_DATA_DIR:-${IGOR_DIR}/data}" \
    IGOR_CONFIGURATION_INHERITED_VERBOSE="${verbose:-}" \
        python3 "${_IGOR_LOADER_DIR:-${IGOR_DIR}}/core/lib/configuration.py" resolve-ai-verbose
}

# Startup-only System health consumer. The declaration comes from the canonical
# loader registry after Module API validation; Configuration Service revalidates
# that single schema and reads the authoritative store directly. No global
# state token is computed here.
_igor_configuration_system_memory_warning_resolve() {
    local _record="${_IGOR_CONTRIBUTIONS[configuration:system.memory.preferences]:-}"
    [ -n "$_record" ] || return 1
    IGOR_CONFIGURATION_DATA_DIR="${IGOR_DATA_DIR:-${IGOR_DIR}/data}" \
    IGOR_CONFIGURATION_SYSTEM_MEMORY_RECORD="$_record" \
        python3 "${_IGOR_LOADER_DIR:-${IGOR_DIR}}/core/lib/configuration.py" \
            resolve-system-memory-warning
}

# Read-only schema projection for generic frontends. This creates no store and
# exposes no desired/secret values.
igor_configuration_declarations() {
    _igor_configuration_call declarations
}

_igor_configuration_precondition() {
    local _proposal="$1" _id="${2:-}" _inputs="${3:-}"
    [ -n "$_id" ] || _id="$(_igor_capability_field "$_proposal" capability_id)" || return 1
    [ -n "$_inputs" ] || _inputs="$(_igor_capability_field "$_proposal" inputs)" || return 1
    case "$_id" in
        system.memory.warning.apply|system.memory.warning.readback)
            _igor_configuration_memory_warning_contract "$_proposal" || return 1
            _igor_configuration_call memory-prepare "$_inputs" >/dev/null
            return $? ;;
        core.configuration.*) ;;
        *) return 0 ;;
    esac
    _igor_configuration_call prepare "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); r["capability_id"]=sys.argv[2]; print(json.dumps(r))' "$_inputs" "$_id")" >/dev/null
}

_igor_configuration_memory_warning_contract() {
    python3 - "$1" <<'PY'
import json,sys
p=json.loads(sys.argv[1]); descriptor=p["descriptor"]
expected={"system.memory.warning.apply":("system__apply_memory_warning","CHANGE"),
          "system.memory.warning.readback":("system__read_memory_warning","READ")}
handler,tier=expected.get(p["capability_id"],(None,None))
valid=(handler is not None and p["owner"]=="system" and p["provider"]=="system" and
       p["capability_version"]==2 and descriptor["handler"]==handler and
       p["privilege"]=="none" and p["safety"]["tier"]==tier and
       p["verification"]=={"kind":"trusted_query","check_id":"system.memory.warning.consumer","required":True})
raise SystemExit(0 if valid else 1)
PY
}

_igor_configuration_invoke() {
    local _proposal="$1" _inputs _id _action
    _id="$(_igor_capability_field "$_proposal" capability_id)" || return 1
    _inputs="$(_igor_capability_field "$_proposal" inputs)" || return 1
    case "$_id" in
        core.configuration.ai_verbose.set) _action="set" ;;
        core.configuration.ai_verbose.verify) _action=verify-session ;;
        core.configuration.system_memory_warning.set) _action=memory-set ;;
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
        inspect)
            case "${_argument:-ai.verbose}" in
                ai.verbose) _igor_configuration_call inspect ;;
                system.memory.warning_threshold_mib)
                    _igor_configuration_call inspect '{"id":"system.memory.warning_threshold_mib","target":"module:system"}' ;;
                *) return 2 ;;
            esac ;;
        validate)
            _fields="$(python3 -c 'import json,sys; print(json.dumps({"changes_document":sys.argv[1]}))' "$_argument")" || return 2
            _igor_configuration_call validate "$_fields" ;;
        *) printf 'Usage: --configuration [status|list|inspect SETTING|export|validate CHANGES_JSON]\n' >&2; return 2 ;;
    esac
}

# Boundary O startup consumption is intentionally narrower than the explicit
# apply/readback contract. Health checks need the authoritative threshold and
# revision, but not a global state token. The stronger proof is acquired only
# when an operation actually requires it.
_igor_configuration_memory_warning_startup_load() {
    _ml_owner_active system || return 1
    local _snapshot _value _revision
    _snapshot="$(_igor_configuration_system_memory_warning_resolve)" || return 1
    IFS=: read -r _value _revision <<< "$_snapshot"
    [[ "$_value" =~ ^[0-9]+$ ]] && [ "$_value" -ge 81 ] && [ "$_value" -le 4096 ] || return 1
    [[ "$_revision" =~ ^[0-9]+$ ]] || return 1

    IGOR_SYSTEM_MEMORY_WARNING_MIB="$_value"
    IGOR_SYSTEM_MEMORY_WARNING_REVISION="$_revision"
    unset IGOR_SYSTEM_MEMORY_WARNING_STATE
    IGOR_SYSTEM_MEMORY_CONSUMER_ID="${IGOR_AI_EVENT_SESSION_ID:-$}"
    export IGOR_SYSTEM_MEMORY_WARNING_MIB IGOR_SYSTEM_MEMORY_WARNING_REVISION IGOR_SYSTEM_MEMORY_CONSUMER_ID
}

# Boundary 3 is one reviewed process consumer, not a generic settings engine.
# This full loader is retained for explicit apply/readback workflows that must
# prove a global configuration revision/state pair.
_igor_configuration_memory_warning_load() {
    _ml_owner_active system || return 1
    local _view _snapshot
    _view="$(_igor_configuration_call inspect '{"id":"system.memory.warning_threshold_mib","target":"module:system"}')" || return 1
    _snapshot="$(python3 -c '
import json,sys
s=json.loads(sys.argv[1])
if s["availability"] != "available": raise SystemExit(1)
if len(sys.argv)>2 and sys.argv[2] and (s["revision"]!=int(sys.argv[2]) or s["state_token"]!=sys.argv[3]): raise SystemExit(1)
print(str(s["resolved"]["value"])+" "+str(s["revision"])+" "+s["state_token"])
' "$_view" "${1:-}" "${2:-}")" || return 1
    read -r IGOR_SYSTEM_MEMORY_WARNING_MIB IGOR_SYSTEM_MEMORY_WARNING_REVISION IGOR_SYSTEM_MEMORY_WARNING_STATE <<< "$_snapshot"
    IGOR_SYSTEM_MEMORY_CONSUMER_ID="${IGOR_AI_EVENT_SESSION_ID:-$$}"
    export IGOR_SYSTEM_MEMORY_WARNING_MIB IGOR_SYSTEM_MEMORY_WARNING_REVISION IGOR_SYSTEM_MEMORY_WARNING_STATE IGOR_SYSTEM_MEMORY_CONSUMER_ID
}

_igor_configuration_memory_warning_apply() {
    local _proposal="$1" _domain="$2" _inputs
    _igor_configuration_memory_warning_contract "$_proposal" || return 1
    [ "$(_igor_capability_field "$_proposal" capability_id)" = system.memory.warning.apply ] || return 1
    _inputs="$(_igor_capability_field "$_proposal" inputs)" || return 1
    python3 -c 'import json,sys; raise SystemExit(0 if json.loads(sys.argv[1])==json.loads(sys.argv[2]) else 1)' "$_inputs" "$_domain" || return 1
    _igor_configuration_call memory-prepare "$_inputs" >/dev/null || return 1
    _igor_configuration_memory_warning_load "$(_igor_capability_field "$_proposal" inputs.revision)" "$(_igor_capability_field "$_proposal" inputs.state)"
}

_igor_configuration_memory_warning_verify() {
    local _proposal="$1" _inputs _read _envelope _request _result _view
    _igor_configuration_memory_warning_contract "$_proposal" || return 1
    _inputs="$(_igor_capability_field "$_proposal" inputs)" || return 1
    _igor_configuration_call memory-prepare "$_inputs" >/dev/null || return 1
    _inputs="$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); r.pop("value",None); print(json.dumps(r))' "$_inputs")" || return 1
    _read="$(igor_capability_prepare system.memory.warning.readback "$_inputs" system 2)" || return 1
    _igor_configuration_memory_warning_contract "$_read" || return 1
    [ "$(_igor_capability_field "$_read" precondition_status)" = satisfied ] || return 1
    [ "$(_igor_capability_field "$_read" descriptor.handler)" = system__read_memory_warning ] || return 1
    [ "$(_igor_capability_field "$_read" safety.tier)" = READ ] || return 1
    [ "$(_igor_capability_field "$_read" privilege)" = none ] || return 1
    # This is the exact reviewed READ verification query within the approved
    # operation, analogous to service_state. It cannot invoke an arbitrary
    # module query. The explicit workflow READ is separately policy-admitted.
    _envelope="$(_igor_capability_invoke_handler "$_read")" || return 1
    _request="$(python3 -c 'import json,sys; p=json.loads(sys.argv[1]); print(json.dumps({"op":"output","outputs":p["descriptor"]["outputs"],"envelope":sys.argv[2]}))' "$_read" "$_envelope")" || return 1
    _result="$(printf '%s' "$_request" | python3 "${_IGOR_LOADER_DIR}/core/lib/capability_runtime.py")" || return 1
    _view="$(_igor_configuration_call inspect '{"id":"system.memory.warning_threshold_mib","target":"module:system"}')" || return 1
    python3 - "$_view" "$_result" "$_inputs" "${IGOR_SYSTEM_MEMORY_CONSUMER_ID:-}" <<'PY'
import json,sys
from datetime import datetime,timezone
state,runtime,expected=map(json.loads,sys.argv[1:4])
valid=(state["availability"]=="available" and state["revision"]==expected["revision"] and
       state["state_token"]==expected["state"] and runtime["value"]==state["resolved"]["value"] and
       runtime["revision"]==expected["revision"] and runtime["state"]==expected["state"] and
       bool(sys.argv[4]) and runtime["consumer_id"]==sys.argv[4])
print(json.dumps({"source":"system.host.memory.health.consumer","observed":runtime,
                  "expected":{"value":state["resolved"]["value"],**expected},
                  "application":"verified_current_process_only" if valid else "unverified_current_process",
                  "observed_at":datetime.now(timezone.utc).isoformat()},separators=(",", ":")))
raise SystemExit(0 if valid else 1)
PY
}

_ai_configuration_memory_warning_set() {
    local _value="$1" _view _payload _stage _inputs _revision _state
    [[ "$_value" =~ ^[0-9]+$ ]] || return 2
    _ml_owner_active system || return 1
    local IGOR_HISTORY_INTERFACE=system_memory_configuration
    local IGOR_HISTORY_CORRELATION_ID
    IGOR_HISTORY_CORRELATION_ID="system-memory-warning-$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
    export IGOR_HISTORY_INTERFACE IGOR_HISTORY_CORRELATION_ID
    for _stage in desired apply readback; do
        _view="$(_igor_configuration_call inspect '{"id":"system.memory.warning_threshold_mib","target":"module:system"}')" || return 1
        _revision="$(_igor_capability_field "$_view" revision)" || return 1
        _state="$(_igor_capability_field "$_view" state_token)" || return 1
        _payload="$(python3 - "$_stage" "$_value" "$_revision" "$_state" <<'PY'
import json,sys
stage,value,revision,state=sys.argv[1:]
ident={"desired":"core.configuration.system_memory_warning.set","apply":"system.memory.warning.apply","readback":"system.memory.warning.readback"}[stage]
inputs={"revision":int(revision),"state":state}
if stage!="readback": inputs["value"]=int(value)
print(json.dumps({"tool":"run_capability","id":ident,"provider":"core" if stage=="desired" else "system","inputs":inputs}))
PY
)" || return 1
        IGOR_CAPABILITY_LAST_RESULT=""
        ai_execute_tool "$_payload" || return 1
        [ "$(_igor_capability_field "$IGOR_CAPABILITY_LAST_RESULT" outcome)" = success ] || return 1
    done
}

# Consume only the current authoritative resolution. This records no observed
# fact and never treats a desired commit as proof of application.
_ai_configuration_verbose_load() {
    local _state _decoded _value _revision _started="" _ended=""
    if [ "${IGOR_TUI_MODE:-false}" = true ] && declare -f _ai_now_ms >/dev/null 2>&1; then
        _started="$(_ai_now_ms)"
    fi
    _state="$(_igor_configuration_ai_verbose_resolve)" || return 1
    if [[ "$_started" =~ ^[0-9]+$ ]]; then
        _ended="$(_ai_now_ms)"
        if [[ "$_ended" =~ ^[0-9]+$ ]] && [ "$_ended" -ge "$_started" ]; then
            _IGOR_TUI_CONFIGURATION_SERVICE_MS=$((_ended - _started))
        fi
        _started="$_ended"
    fi
    _decoded="$(printf '%s' "$_state" | python3 -c '
import json,sys
state=json.load(sys.stdin)
value=state["resolved"]["value"]
revision=state["revision"]
if type(value) is not bool or type(revision) is not int or revision < 0:
    raise SystemExit(1)
print(("true" if value else "false") + ":" + str(revision))
')" || return 1
    IFS=: read -r _value _revision <<< "$_decoded"
    if [[ "$_started" =~ ^[0-9]+$ ]]; then
        _ended="$(_ai_now_ms)"
        if [[ "$_ended" =~ ^[0-9]+$ ]] && [ "$_ended" -ge "$_started" ]; then
            _IGOR_TUI_CONFIGURATION_DECODE_MS=$((_ended - _started))
        fi
    fi
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
