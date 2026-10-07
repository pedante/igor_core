#!/usr/bin/env bash
igor_operator_cli_normalize() {
    local _cmd _sub _prompt
    if [ "${1:-}" = "--json" ]; then
        export IGOR_CLI_JSON=true
        shift
    else
        export IGOR_CLI_JSON=false
    fi
    _cmd="${1:-}"
    case "$_cmd" in
        "") return 0 ;;
        modules)
            shift
            case "${1:-list}" in
                list) printf '%s\0' --modules ;;
                inspect|detach-plan) _sub="$1"; shift; [ "$#" -eq 1 ] || return 2; printf '%s\0' --modules "$_sub" "$1" ;;
                *) return 2 ;;
            esac ;;
        capability|capabilities)
            shift
            case "${1:-list}" in
                list) printf '%s\0' --capabilities list ;;
                inspect) shift; [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2; printf '%s\0' --capabilities inspect "$@" ;;
                plan) shift; [ "$#" -eq 1 ] || return 2; printf '%s\0' --capabilities plan "$1" ;;
                run) shift; [ "$#" -ge 1 ] && [ "$#" -le 3 ] || return 2; printf '%s\0' --capability-run "$1" "${2:-{}}" "${3:-}" ;;
                *) return 2 ;;
            esac ;;
        deployments) shift; printf '%s\0' --deployments "${@:-list}" ;;
        history) shift; printf '%s\0' --history "${@:-recent}" ;;
        investigations) shift; printf '%s\0' --investigations "${@:-list}" ;;
        config|configuration) shift; printf '%s\0' --configuration "${@:-status}" ;;
        health)
            shift
            case "${1:-summary}" in
                summary) printf '%s\0' --model summary ;;
                inspect) shift; printf '%s\0' --model health "${1:-}" ;;
                *) return 2 ;;
            esac ;;
        facts) shift; printf '%s\0' --model facts "$@" ;;
        ask) shift; [ "$#" -ge 1 ] || return 2; _prompt="$*"; printf '%s\0' --ask-once-backend "$_prompt" ;;
        --*) printf '%s\0' "$@" ;;
        *) _prompt="$*"; printf '%s\0' --ask-once-backend "$_prompt" ;;
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
