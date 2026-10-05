#!/usr/bin/env bash
# Bounded data interface. No module loading, model calls or operation dispatch.
igor_investigation_cli() {
    local _action="${1:-list}" _argument="${2:-}" _request
    case "$_action" in
        list|status|export)
            [ -z "$_argument" ] || return 2
            _request='{}' ;;
        inspect)
            _request="$(python3 -c 'import json,sys; print(json.dumps({"investigation_id":sys.argv[1]}))' "$_argument")" || return 2 ;;
        create|add_evidence|add_hypothesis|update_hypothesis|attach_judgment|set_findings|add_typed_finding|update_typed_finding|set_questions|transition|close|reopen|restore)
            [ -n "$_argument" ] || { printf 'Supply JSON or - for standard input\n' >&2; return 2; }
            if [ "$_argument" = - ]; then
                python3 "${IGOR_DIR}/core/lib/investigations.py" "$_action"
                return $?
            fi
            _request="$_argument" ;;
        *) printf 'Usage: --investigations [list|status|inspect ID|export|ACTION JSON|-]\n' >&2; return 2 ;;
    esac
    printf '%s' "$_request" | python3 "${IGOR_DIR}/core/lib/investigations.py" "$_action"
}
