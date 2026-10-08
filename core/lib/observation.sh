#!/usr/bin/env bash
# Wave D process-local model and active v2 observer boundary.

if [ "${IGOR_MODEL_RUNTIME_OWNER:-}" != "$$" ] || [ -z "${IGOR_MODEL_RUNTIME_FILE:-}" ] ||
   [ ! -f "${IGOR_MODEL_RUNTIME_FILE:-}" ]; then
    IGOR_MODEL_RUNTIME_FILE="$(mktemp "${TMPDIR:-/tmp}/igor-model.XXXXXXXX")" || return 1
    IGOR_MODEL_RUNTIME_OWNER="$$"
    export IGOR_MODEL_RUNTIME_FILE IGOR_MODEL_RUNTIME_OWNER
    chmod 600 -- "$IGOR_MODEL_RUNTIME_FILE"
    printf '{}\n' > "$IGOR_MODEL_RUNTIME_FILE"
fi

_igor_model_state() { cat -- "$IGOR_MODEL_RUNTIME_FILE"; }

_igor_model_python() {
    if [ -n "${IGOR_PYTHON:-}" ] && command -v "$IGOR_PYTHON" >/dev/null 2>&1; then
        printf '%s\n' "$IGOR_PYTHON"
    elif command -v python3 >/dev/null 2>&1; then
        printf 'python3\n'
    elif command -v python >/dev/null 2>&1 && python --version 2>&1 | grep -q '^Python 3'; then
        printf 'python\n'
    else
        return 1
    fi
}

_igor_model_active_owners() {
    local _owner
    for _owner in "${!_IGOR_LOADED_MODULES[@]}"; do
        _ml_owner_active "$_owner" && printf '%s\n' "$_owner"
    done | "$(_igor_model_python)" -c 'import json,sys; print(json.dumps(sys.stdin.read().splitlines()))'
}

igor_model_read() {
    local _object="${1:-}" _property="${2:-}" _class="${3:-observed}" _owners
    _owners="$(_igor_model_active_owners)" || return 1
    "$(_igor_model_python)" "${_IGOR_LOADER_DIR}/core/lib/model_bridge.py" --read \
        "$(_igor_model_state)" "$_object" "$_property" "$_class" "$_owners"
}

# Optional filters are part of the public model-list API even though current
# in-tree callers normally request the full projection.
# shellcheck disable=SC2120
igor_model_list() {
    local _owners
    _owners="$(_igor_model_active_owners)" || return 1
    "$(_igor_model_python)" "${_IGOR_LOADER_DIR}/core/lib/model_bridge.py" --list \
        "$(_igor_model_state)" "${1:-}" "${2:-}" "${3:-}" "$_owners"
}

igor_observer_inspect() {
    local _filter="${1:-}" _key _id _owner _source _state _attempts
    _attempts="$(igor_model_list | "$(_igor_model_python)" -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["observers"]))')" || return 1
    for _key in "${!_IGOR_CONTRIBUTIONS[@]}"; do
        [[ "$_key" == observer:* ]] || continue
        _id="${_key#observer:}"
        [ -z "$_filter" ] || [ "$_filter" = "$_id" ] || continue
        _owner="${_IGOR_CONTRIBUTION_OWNER[$_key]:-}"
        _source="${_IGOR_CONTRIBUTION_SOURCE[$_key]:-}"
        _state="$(igor_contribution_state "$_key")"
        printf '%s\t%s\t%s\t%s\n' "$_id" "$_owner" "$_source" "$_state"
    done | "$(_igor_model_python)" -c '
import json, sys
attempts = json.loads(sys.argv[1])
result = []
for line in sys.stdin:
    observer_id, owner, source, state = line.rstrip("\n").split("\t")
    result.append({"id": observer_id, "owner": owner, "source": source,
                   "availability": state, "last_attempt": attempts.get(observer_id)})
print(json.dumps(result, separators=(",", ":")))
' "$_attempts"
}

_igor_model_update() {
    local _response="$1" _state
    _state="$(printf '%s' "$_response" | "$(_igor_model_python)" -c \
        'import json,sys; print(json.dumps(json.load(sys.stdin)["state"],separators=(",",":")))')" || return 1
    local _temp
    _temp="$(mktemp "${IGOR_MODEL_RUNTIME_FILE}.XXXXXXXX")" || return 1
    chmod 600 -- "$_temp"
    printf '%s\n' "$_state" > "$_temp" || return 1
    mv -f -- "$_temp" "$IGOR_MODEL_RUNTIME_FILE" || return 1
    if printf '%s' "$_response" | "$(_igor_model_python)" -c \
        'import json,sys; sys.exit(1 if "error" in json.load(sys.stdin) else 0)'; then
        return 0
    fi
    return 1
}

igor_model_upsert_from_source() {
    local _response
    _response="$("$(_igor_model_python)" "${_IGOR_LOADER_DIR}/core/lib/model_bridge.py" --source \
        "$(_igor_model_state)" "$1" "$2")" || return 1
    _igor_model_update "$_response"
}

igor_model_revoke_source() {
    local _response
    _response="$("$(_igor_model_python)" "${_IGOR_LOADER_DIR}/core/lib/model_bridge.py" --revoke \
        "$(_igor_model_state)" "$1")" || return 1
    _igor_model_update "$_response"
}

igor_model_store_health() {
    local _response
    _response="$("$(_igor_model_python)" "${_IGOR_LOADER_DIR}/core/lib/model_bridge.py" --health \
        "$(_igor_model_state)" "$1")" || return 1
    _igor_model_update "$_response"
}

igor_observer_refresh() {
    local _id="${1:-}" _target="${2:-}" _descriptor _owner _envelope _response _failed=0 _kind
    _descriptor="$(igor_v2_contribution_get observer "$_id")" || return 1
    _owner="${_IGOR_CONTRIBUTION_OWNER[observer:${_id}]:-}"
    [ -n "$_owner" ] && _ml_owner_active "$_owner" || return 1
    [ "$(_ml_json_field "$_descriptor" privilege)" = none ] || return 1
    _kind="$(_ml_json_field "$_descriptor" object_kind)" || return 1
    case "$_kind" in
        host)
            [ -z "$_target" ] && _target=host:local
            [ "$_target" = host:local ] || return 1
            ;;
        mount|filesystem|user|group|interface)
            # Collection observers own a bounded snapshot, not one caller-picked
            # object. A target argument would falsely imply per-object probing.
            [ -z "$_target" ] || return 1
            ;;
        *) return 1 ;;
    esac
    if _envelope="$(igor_v2_invoke observer "$_id" '{}')"; then
        _response="$("$(_igor_model_python)" "${_IGOR_LOADER_DIR}/core/lib/model_bridge.py" --observe \
            "$(_igor_model_state)" "$_owner" "$_id" "$_descriptor" "$_envelope")" || return 1
    else
        _failed=1
        _response="$("$(_igor_model_python)" "${_IGOR_LOADER_DIR}/core/lib/model_bridge.py" --observe \
            "$(_igor_model_state)" "$_owner" "$_id" "$_descriptor" --failure invocation_failed)" || return 1
    fi
    _igor_model_update "$_response" || return 1
    [ "$_failed" -eq 0 ]
}

igor_observer_ensure_fresh() {
    local _id="${1:-}" _target="${2:-host:local}" _descriptor _property _slot _availability
    _descriptor="$(igor_v2_contribution_get observer "$_id")" || return 1
    _property="$(printf '%s' "$_descriptor" | "$(_igor_model_python)" -c \
        'import json,sys; d=json.load(sys.stdin); print(d["properties"][0]["name"])')" || return 1
    _slot="$(igor_model_read "$_target" "$_property" observed)" || return 1
    _availability="$(printf '%s' "$_slot" | "$(_igor_model_python)" -c \
        'import json,sys; print(json.load(sys.stdin)["availability"])')" || return 1
    [ "$_availability" = known ] || igor_observer_refresh "$_id" "$_target"
}
