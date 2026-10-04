#!/usr/bin/env bash
# Read-only Step 16 baseline projection over canonical Operational History.

_igor_baseline_call() {
    local _action="$1" _fields="${2:-}"
    [ -n "$_fields" ] || _fields='{}'
    printf '%s' "$_fields" | IGOR_BASELINE_DATA_DIR="${IGOR_DATA_DIR:-${IGOR_DIR}/data}" \
        python3 "${IGOR_DIR}/core/lib/baselines.py" "$_action"
}

igor_baseline_cli() {
    local _action="${1:-list}" _first="${2:-}" _second="${3:-}" _fields
    case "$_action" in
        status)
            [ -z "$_first" ] && [ -z "$_second" ] || return 2
            _igor_baseline_call status
            ;;
        list)
            [ -z "$_second" ] || return 2
            _fields="$(python3 -c 'import json,sys; print(json.dumps({"limit":int(sys.argv[1])}))' "${_first:-100}")" || return 2
            _igor_baseline_call list "$_fields"
            ;;
        capability)
            [ -n "$_first" ] || {
                printf 'Usage: --baselines capability CAPABILITY_ID [LIMIT]\n' >&2
                return 2
            }
            _fields="$(python3 -c 'import json,sys; print(json.dumps({"capability_id":sys.argv[1],"limit":int(sys.argv[2])}))' "$_first" "${_second:-100}")" || return 2
            _igor_baseline_call capability "$_fields"
            ;;
        *)
            printf 'Usage: --baselines [status|list [LIMIT]|capability CAPABILITY_ID [LIMIT]]\n' >&2
            return 2
            ;;
    esac
}
