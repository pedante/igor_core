#!/usr/bin/env bash
# Transport for remaining shell consumers of the Python Module API adapter.
# Admission/approval remain in the canonical dispatcher. Domain-event callbacks
# stay in the owning session until that consumer moves to the Python executor.

_ml_bash_handler_python() {
    if [ -n "${IGOR_PYTHON:-}" ]; then printf '%s\n' "$IGOR_PYTHON"
    else printf '%s\n' python3; fi
}

_ml_bash_handler_run_process() {
    local _input="$1" _py="$2" _timeout="$3" _module_dir="$4" _owner="$5"
    local _handler="$6" _id="$7" _event_dir="$8" _event_schemas="$9"
    local _root="${_IGOR_LOADER_DIR:-}" _adapter
    _adapter="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/module_handler.py" || return 1
    local -a _options=(--entrypoint "${V2_HANDLER_ENTRYPOINT:-module.sh}")
    if [ -n "${IGOR_COLLECTION_CONTEXT:-}" ] || [ -n "${IGOR_COLLECTION_INSPECTION_FILE:-}" ]; then
        _options+=(--collection)
    fi
    if [ "${V2_HANDLER_DEFER_RESPONSE_VALIDATION:-0}" = 1 ]; then
        _options+=(--defer-response-validation)
    fi
    printf '%s' "$_input" | _IGOR_LOADER_DIR="$_root" \
        _IGOR_DOMAIN_REQUEST_DIR="$_event_dir" _IGOR_DOMAIN_SCHEMAS_FILE="$_event_schemas" \
        "$_py" "$_adapter" "$_module_dir" "$_owner" "$_handler" "$_id" "$_timeout" "${_options[@]}"
}

_ml_bash_handler_invoke() {
    local _module_dir="${1:-}" _owner="${2:-}" _handler="${3:-}"
    local _contribution_id="${4:-}" _timeout="${5:-}" _input="${6:-}"
    local _py _response _rc _event_dir="" _event_schemas="" _event_key _event_id _event_data
    local _event_index=1 _event_pid _event_error
    _py="$(_ml_bash_handler_python)" || return 1
    [ -n "$_input" ] || _input='{}'

    if [ "${V2_HANDLER_DOMAIN_EVENTS:-auto}" != 0 ] &&
       declare -F igor_v2_contribution_get >/dev/null 2>&1 &&
       [ -n "${_IGOR_LOADER_DIR:-}" ] && [ -n "${IGOR_DOMAIN_EVENT_FILE:-}" ]; then
        _event_dir="$(mktemp -d "${TMPDIR:-/tmp}/igor-domain-handler.XXXXXXXX")" || return 1
        chmod 700 -- "$_event_dir"
        _event_schemas="$_event_dir/schemas"
        : > "$_event_schemas"
        chmod 600 -- "$_event_schemas"
        for _event_key in "${!_IGOR_CONTRIBUTIONS[@]}"; do
            [[ "$_event_key" = domain_event:* ]] || continue
            [ "${_IGOR_CONTRIBUTION_OWNER[$_event_key]:-}" = "$_owner" ] || continue
            igor_v2_contribution_get domain_event "${_event_key#domain_event:}" >> "$_event_schemas" || true
        done
    fi
    if [ -n "$_event_dir" ]; then
        (
            _ml_bash_handler_run_process "$_input" "$_py" "$_timeout" "$_module_dir" "$_owner" "$_handler" "$_contribution_id" "$_event_dir" "$_event_schemas" \
                > "$_event_dir/output" 2> "$_event_dir/error"
            printf '%s\n' "$?" > "$_event_dir/done"
        ) &
        _event_pid=$!
        while [ ! -f "$_event_dir/done" ] || [ -f "$_event_dir/$_event_index.request" ]; do
            kill -0 "$_event_pid" 2>/dev/null || break
            if [ -f "$_event_dir/$_event_index.request" ]; then
                IFS= read -r -d '' _event_id < "$_event_dir/$_event_index.request"
                _event_data="$("$_py" - "$_event_dir/$_event_index.request" <<'PY'
import sys
with open(sys.argv[1], 'rb') as stream:
    parts = stream.read().split(b'\0')
if len(parts) != 3 or parts[2]:
    raise SystemExit(2)
print(parts[1].decode())
PY
)" || _event_data=''
                _IGOR_DOMAIN_HANDLER_OWNER="$_owner"
                if igor_domain_event_publish "$_event_id" "$_event_data" > /dev/null 2> "$_event_dir/$_event_index.error"; then
                    printf 'ok\n' > "$_event_dir/$_event_index.response.tmp"
                else
                    printf 'error\n' > "$_event_dir/$_event_index.response.tmp"
                fi
                _IGOR_DOMAIN_HANDLER_OWNER=""
                mv -- "$_event_dir/$_event_index.response.tmp" "$_event_dir/$_event_index.response"
                _event_index=$((_event_index + 1))
            else
                sleep 0.01
            fi
        done
        wait "$_event_pid" || true
        _rc="$(cat "$_event_dir/done")"
        _response="$(cat "$_event_dir/output")"
        _event_error="$(cat "$_event_dir/error")"
        [ -z "$_event_error" ] || printf '%s\n' "$_event_error" >&2
        rm -rf -- "$_event_dir"
    else
        _response="$(_ml_bash_handler_run_process "$_input" "$_py" "$_timeout" "$_module_dir" "$_owner" "$_handler" "$_contribution_id" "" "")"
        _rc=$?
    fi
    [ "$_rc" -eq 0 ] || return 1
    printf '%s\n' "$_response"
}
