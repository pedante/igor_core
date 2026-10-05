#!/usr/bin/env bash
# Explicit local reference review; no module, observer, AI or executor startup.
igor_learning_cli() {
    local _action="${1:-status}" _argument="${2:-}" _request
    case "$_action" in
        status|candidates|list|export)
            _request="$_argument"
            [ -n "$_request" ] || _request='{}' ;;
        inspect|candidate|evidence_status)
            _request="$(python3 -c 'import json,sys; print(json.dumps({sys.argv[1]:sys.argv[2]}))' \
                "$([ "$_action" = candidate ] && printf candidate_id || printf learning_id)" "$_argument")" || return 2 ;;
        review|supersede|delete|reset|restore)
            [ -n "$_argument" ] || { printf 'Supply JSON or - for standard input\n' >&2; return 2; }
            _request="$_argument" ;;
        *) printf 'Usage: --learning [status|candidates [JSON]|candidate ID|list [JSON]|inspect ID|evidence_status ID|export|ACTION JSON|-]\n' >&2; return 2 ;;
    esac
    if [ "$_argument" = - ]; then
        python3 "${IGOR_DIR}/core/lib/local_learning.py" "$_action"
    else
        printf '%s' "$_request" | python3 "${IGOR_DIR}/core/lib/local_learning.py" "$_action"
    fi
}
