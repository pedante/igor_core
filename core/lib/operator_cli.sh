#!/usr/bin/env bash
# Step 20 CLI argument normalization only. This selects existing Igor backend
# entry points and owns no facts, authorization, privilege or execution.

igor_operator_cli_normalize() {
    _IGOR_OPERATOR_ARGS=()
    if [ "${1:-}" = "--json" ]; then
        export IGOR_CLI_JSON=true
        shift
    else
        export IGOR_CLI_JSON=false
    fi
    [ "${IGOR_CLI_JSON}" != true ] || [ "$#" -gt 0 ] || return 2
    local _cmd="${1:-}" _sub _prompt
    case "$_cmd" in
        "") ;;
        modules)
            shift
            case "${1:-list}" in
                list) _IGOR_OPERATOR_ARGS=(--modules) ;;
                inspect|detach-plan)
                    _sub="$1"; shift
                    [ "$#" -eq 1 ] || return 2
                    _IGOR_OPERATOR_ARGS=(--modules "$_sub" "$1") ;;
                *) return 2 ;;
            esac ;;
        capability|capabilities)
            shift
            case "${1:-list}" in
                list) _IGOR_OPERATOR_ARGS=(--capabilities list) ;;
                inspect)
                    shift
                    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
                    _IGOR_OPERATOR_ARGS=(--capabilities inspect "$@") ;;
                plan)
                    shift; [ "$#" -eq 1 ] || return 2
                    _IGOR_OPERATOR_ARGS=(--capabilities plan "$1") ;;
                run)
                    shift; [ "$#" -ge 1 ] && [ "$#" -le 3 ] || return 2
                    _IGOR_OPERATOR_ARGS=(--capability-run "$1" "${2:-{}}" "${3:-}") ;;
                *) return 2 ;;
            esac ;;
        deployments) shift; _IGOR_OPERATOR_ARGS=(--deployments "${@:-list}") ;;
        history) shift; _IGOR_OPERATOR_ARGS=(--history "${@:-recent}") ;;
        investigations) shift; _IGOR_OPERATOR_ARGS=(--investigations "${@:-list}") ;;
        config|configuration) shift; _IGOR_OPERATOR_ARGS=(--configuration "${@:-status}") ;;
        health)
            shift
            case "${1:-summary}" in
                summary) _IGOR_OPERATOR_ARGS=(--model summary) ;;
                inspect) shift; _IGOR_OPERATOR_ARGS=(--model health "${1:-}") ;;
                *) return 2 ;;
            esac ;;
        facts) shift; _IGOR_OPERATOR_ARGS=(--model facts "$@") ;;
        ask)
            [ "${IGOR_CLI_JSON}" != true ] || return 2
            shift; [ "$#" -ge 1 ] || return 2
            _prompt="$*"; _IGOR_OPERATOR_ARGS=(--ask-once-backend "$_prompt") ;;
        --*) _IGOR_OPERATOR_ARGS=("$@") ;;
        *)
            [ "${IGOR_CLI_JSON}" != true ] || return 2
            _prompt="$*"; _IGOR_OPERATOR_ARGS=(--ask-once-backend "$_prompt") ;;
    esac
}

igor_operator_default_frontend() {
    local _argc="${1:-0}" _stdin_tty="${2:-false}" _stdout_tty="${3:-false}" _classic="${4:-false}"
    if [ "$_argc" -eq 0 ] && [ "$_stdin_tty" = true ] && [ "$_stdout_tty" = true ] && [ "$_classic" != true ]; then
        printf 'tui\n'
    else
        printf 'existing\n'
    fi
}
