#!/usr/bin/env bash
# =============================================================================
#  MODULE API v2 — Bash handler adapter
#
#  This file only knows how to invoke a trusted Bash handler.  Activation,
#  ownership, requirements and policy checks belong to module_loader.sh.
#
#  _ml_bash_handler_invoke <module_dir> <owner> <handler> <contribution_id>
#                          <timeout_seconds> [input_json]
#
#  The function writes one validated response envelope to stdout.  Handler
#  diagnostics may be written to stderr.  A non-zero return means that the
#  handler was not successfully invoked or did not return a valid envelope.
# =============================================================================

_ml_bash_handler_error() {
    printf 'module handler: %s\n' "$*" >&2
    return 1
}

_ml_bash_handler_python() {
    local _py="${IGOR_PYTHON:-}"
    if [ -n "$_py" ] && command -v "$_py" >/dev/null 2>&1; then
        printf '%s\n' "$_py"
    elif command -v python3 >/dev/null 2>&1; then
        printf 'python3\n'
    elif command -v python >/dev/null 2>&1 && python --version 2>&1 | grep -q '^Python 3'; then
        printf 'python\n'
    else
        return 1
    fi
}

_ml_bash_handler_path() {
    local _module_dir="$1" _entrypoint="$2" _base _path _real_base _real_path
    [ -n "$_module_dir" ] && [ -n "$_entrypoint" ] || return 1
    case "$_entrypoint" in
        /*|..|../*|*/../*|*/..) return 1 ;;
    esac
    _base="$(cd -- "$_module_dir" 2>/dev/null && pwd -P)" || return 1
    _path="$_base/$_entrypoint"
    [ -f "$_path" ] || return 1
    _real_base="$(realpath -e -- "$_base" 2>/dev/null)" || return 1
    _real_path="$(realpath -e -- "$_path" 2>/dev/null)" || return 1
    case "$_real_path" in
        "$_real_base"/*) printf '%s\n' "$_real_path" ;;
        *) return 1 ;;
    esac
}

_ml_bash_handler_validate_response() {
    local _response="$1" _py
    _py="$(_ml_bash_handler_python)" || {
        _ml_bash_handler_error "Python JSON runtime is unavailable"
        return 1
    }
    printf '%s' "$_response" | "$_py" -c '
import json, sys
raw = sys.stdin.read()
try:
    value = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"invalid JSON response: {exc}", file=sys.stderr)
    raise SystemExit(1)
if not isinstance(value, dict):
    print("response must be a JSON object", file=sys.stderr)
    raise SystemExit(1)
status = value.get("status")
if status == "ok":
    if set(value) != {"status", "result"}:
        print("ok response must contain result and no error", file=sys.stderr)
        raise SystemExit(1)
elif status == "error":
    error = value.get("error")
    if not isinstance(error, dict) or not isinstance(error.get("code"), str) or not isinstance(error.get("message"), str):
        print("error response must contain error.code and error.message strings", file=sys.stderr)
        raise SystemExit(1)
    if set(value) != {"status", "error"}:
        print("error response must contain only status and error", file=sys.stderr)
        raise SystemExit(1)
    print("handler error {}: {}".format(error["code"], error["message"]), file=sys.stderr)
    raise SystemExit(1)
else:
    print("response status must be ok or error", file=sys.stderr)
    raise SystemExit(1)
' || return 1
}

_ml_bash_handler_run_process() {
    local _request="$1" _py="$2" _timeout="$3" _entrypoint="$4" _handler="$5"
    local _event_dir="$6" _event_schemas="$7"
    printf '%s\n' "$_request" | IGOR_PYTHON="$_py" timeout --signal=TERM "${_timeout}s" \
        bash --noprofile --norc -c '
            set -e
            entrypoint=$1
            handler=$2
            _IGOR_DOMAIN_REQUEST_DIR=$3
            _IGOR_DOMAIN_SCHEMAS_FILE=$4
            _IGOR_LOADER_DIR=$5
            if [ -n "$_IGOR_DOMAIN_REQUEST_DIR" ]; then source -- "$6"; fi
            source -- "$entrypoint"
            declare -F "$handler" >/dev/null 2>&1 || {
                printf "handler function is not defined: %s\n" "$handler" >&2
                exit 127
            }
            "$handler"
        ' _ "$_entrypoint" "$_handler" "$_event_dir" "$_event_schemas" "${_IGOR_LOADER_DIR:-}" "${_IGOR_LOADER_DIR:-}/core/lib/domain_event_client.sh"
}

_ml_bash_handler_invoke() {
    local _module_dir="${1:-}" _owner="${2:-}" _handler="${3:-}"
    local _contribution_id="${4:-}" _timeout="${5:-}" _input="${6:-}"
    local _entrypoint _py _request _response _rc _event_dir="" _event_schemas="" _event_key _event_id _event_data
    local _event_index=1 _event_pid _event_error

    [ -d "$_module_dir" ] || { _ml_bash_handler_error "module directory is missing"; return 1; }
    [[ "$_owner" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || {
        _ml_bash_handler_error "invalid owner '${_owner}'"; return 1;
    }
    [[ "$_handler" =~ ^${_owner}__[A-Za-z_][A-Za-z0-9_]*$ ]] || {
        _ml_bash_handler_error "handler '${_handler}' is outside owner '${_owner}'"; return 1;
    }
    [[ "$_contribution_id" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || {
        _ml_bash_handler_error "invalid contribution id '${_contribution_id}'"; return 1;
    }
    [[ "$_timeout" =~ ^[1-9][0-9]*$ ]] || {
        _ml_bash_handler_error "timeout must be a positive integer"; return 1;
    }
    _entrypoint="${V2_HANDLER_ENTRYPOINT:-module.sh}"
    _entrypoint="$(_ml_bash_handler_path "$_module_dir" "$_entrypoint")" || {
        _ml_bash_handler_error "entrypoint is missing or escapes module package"; return 1;
    }
    if [ "${V2_HANDLER_SYNTAX_VALIDATED:-0}" != 1 ]; then
        bash -n -- "$_entrypoint" 2>&1 || {
            _ml_bash_handler_error "entrypoint failed Bash syntax validation"; return 1;
        }
    fi
    _py="$(_ml_bash_handler_python)" || {
        _ml_bash_handler_error "Python JSON runtime is unavailable"; return 1;
    }
    [ -n "$_input" ] || _input='{}'
    if [ "${V2_HANDLER_INPUT_CANONICAL:-0}" = 1 ]; then
        # contribution_id is restricted above to identifier syntax and the
        # capability runtime already validated/canonicalized the JSON object.
        printf -v _request '{"api_version":2,"contribution_id":"%s","input":%s}' \
            "$_contribution_id" "$_input"
    else
        _request="$(printf '%s' "$_input" | "$_py" -c '
import json, sys
try:
    value = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    print(f"invalid input JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)
if not isinstance(value, dict):
    print("handler input must be a JSON object", file=sys.stderr)
    raise SystemExit(1)
print(json.dumps({"api_version": 2, "contribution_id": sys.argv[1], "input": value}, separators=(",", ":")))
' "$_contribution_id")" || return 1
    fi

    if ! command -v timeout >/dev/null 2>&1; then
        _ml_bash_handler_error "timeout command is unavailable"
        return 1
    fi
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
            _ml_bash_handler_run_process "$_request" "$_py" "$_timeout" "$_entrypoint" "$_handler" "$_event_dir" "$_event_schemas" \
                > "$_event_dir/output" 2> "$_event_dir/error"
            printf '%s\n' "$?" > "$_event_dir/done"
        ) &
        _event_pid=$!
        while [ ! -f "$_event_dir/done" ] || [ -f "$_event_dir/$_event_index.request" ]; do
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
        _response="$(_ml_bash_handler_run_process "$_request" "$_py" "$_timeout" "$_entrypoint" "$_handler" "" "")"
        _rc=$?
    fi
    [ "$_rc" -eq 0 ] || {
        [ "$_rc" -eq 124 ] && _ml_bash_handler_error "handler timed out after ${_timeout}s" ||
            _ml_bash_handler_error "handler exited with status ${_rc}"
        return 1
    }
    [ -n "$_response" ] || { _ml_bash_handler_error "handler returned an empty response"; return 1; }
    if [ "${V2_HANDLER_DEFER_RESPONSE_VALIDATION:-0}" != 1 ]; then
        _ml_bash_handler_validate_response "$_response" || return 1
    fi
    printf '%s\n' "$_response"
}
