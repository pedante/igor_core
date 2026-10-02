#!/usr/bin/env bash
# Data-only deployment inspection. No activation, observation or execution.
igor_deployment_cli() {
    local _action="${1:-status}" _argument="${2:-}"
    case "$_action" in
        status|list|export)
            [ -z "$_argument" ] || return 2
            python3 "${IGOR_DIR}/core/lib/deployments.py" "$_action" ;;
        inspect)
            [ -n "$_argument" ] || return 2
            python3 "${IGOR_DIR}/core/lib/deployments.py" inspect "$_argument" ;;
        *)
            printf 'Usage: --deployments [status|list|inspect ID|export]\n' >&2
            return 2 ;;
    esac
}
