#!/usr/bin/env bash
# Stateless Knowledge Artifact portability; no import persistence or authority.
igor_knowledge_cli() {
    local _action="${1:-status}" _argument="${2:-}" _request
    case "$_action" in
        status)
            [ -z "$_argument" ] || { printf 'status takes no argument\n' >&2; return 2; }
            _request='{}'
            ;;
        export|import)
            [ -n "$_argument" ] || { printf 'Supply JSON or - for standard input\n' >&2; return 2; }
            _request="$_argument"
            ;;
        *)
            printf 'Usage: --knowledge [status|export JSON|-|import JSON|-]\n' >&2
            return 2
            ;;
    esac
    if [ "$_argument" = - ]; then
        python3 "${IGOR_DIR}/core/lib/knowledge_artifacts.py" "$_action"
    else
        printf '%s' "$_request" | python3 "${IGOR_DIR}/core/lib/knowledge_artifacts.py" "$_action"
    fi
}
