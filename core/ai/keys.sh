#!/bin/bash
# API key entry and persistence. Prompts never write into captured key output.

_ai_prompt_key() {
    local _key
    printf '  Enter %s API key (visible; Enter cancels):\n' "$1" >&2
    IFS= read -r _key || return 1
    # Remove surrounding paste whitespace, but reject embedded whitespace.
    _key="${_key#"${_key%%[![:space:]]*}"}"
    _key="${_key%"${_key##*[![:space:]]}"}"
    [[ -n "$_key" && "$_key" != *[[:space:]]* ]] || return 1
    printf '%s' "$_key"
}

_ai_write_key() {
    local _provider="$1" _key="$2" _env
    case "$_provider" in
        anthropic) _env=ANTHROPIC_API_KEY ;;
        openrouter) _env=OPENROUTER_API_KEY ;;
        *) return 1 ;;
    esac
    _key="${_key#"${_key%%[![:space:]]*}"}"
    _key="${_key%"${_key##*[![:space:]]}"}"
    [[ -n "$_key" && "$_key" != *[[:space:]]* ]] || return 1
    local _sec_dir="${IGOR_DIR}/secrets" _tmp
    mkdir -p "$_sec_dir" || return 1
    _tmp=$(mktemp "${_sec_dir}/.${_provider}.key.XXXXXX") || return 1
    if ! { chmod 600 "$_tmp" && printf '%s\n' "$_key" > "$_tmp" &&
           mv -fT "$_tmp" "${_sec_dir}/${_provider}.key"; }; then
        rm -f "$_tmp"
        return 1
    fi
    # Startup exports these variables; replace that cached value immediately.
    export "${_env}=${_key}"
}

# Called in menu_ai's scope, so the active chat key changes without a restart.
_ai_change_key() {
    local _provider="$1" _new_key
    case "$_provider" in
        anthropic|openrouter) ;;
        *) echo '  This provider does not require an API key.'; return 0 ;;
    esac
    _new_key=$(_ai_prompt_key "$_provider") || return 1
    if ! _nexus_validate_key "$_provider" "$_new_key"; then
        warn 'Key rejected or provider unreachable — existing key kept.'
        return 1
    fi
    _ai_write_key "$_provider" "$_new_key" || {
        fail 'API key could not be saved — existing key kept.'
        return 1
    }
    case "$_provider" in
        anthropic) api_key="$_new_key" ;;
        openrouter) or_api_key="$_new_key" ;;
    esac
    ok "${_provider} key validated and saved. It is active for your next message."
}

_nexus_validate_key() {
    case "$1" in
        anthropic) _nexus_validate_ant_key "$2" ;;
        openrouter) _nexus_validate_or_key "$2" ;;
        *) return 1 ;;
    esac
}
