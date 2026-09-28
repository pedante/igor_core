#!/usr/bin/env bash
# Loaded only in a v2 handler process. The parent runtime binds the owner and
# validates each explicit request against the active contribution index.
igor_domain_event_publish() {
    local _index _request_file _reply
    [ "$#" -eq 2 ] && [ -n "${_IGOR_DOMAIN_REQUEST_DIR:-}" ] &&
        [ -n "${_IGOR_DOMAIN_SCHEMAS_FILE:-}" ] || return 2
    printf '%s' "$2" | "${IGOR_PYTHON:-python3}" "${_IGOR_LOADER_DIR}/core/lib/domain_event.py" \
        validate-module "$_IGOR_DOMAIN_SCHEMAS_FILE" "$1" || return 2
    _IGOR_DOMAIN_REQUEST_INDEX=$((${_IGOR_DOMAIN_REQUEST_INDEX:-0} + 1))
    _index="$_IGOR_DOMAIN_REQUEST_INDEX"
    _request_file="$_IGOR_DOMAIN_REQUEST_DIR/$_index.request"
    printf '%s\0%s\0' "$1" "$2" > "${_request_file}.tmp" || return 2
    mv -- "${_request_file}.tmp" "$_request_file" || return 2
    while [ ! -f "$_IGOR_DOMAIN_REQUEST_DIR/$_index.response" ]; do sleep 0.01; done
    _reply="$(cat "$_IGOR_DOMAIN_REQUEST_DIR/$_index.response")" || return 2
    if [ "$_reply" != ok ]; then
        printf 'domain event: request rejected by active owner boundary\n' >&2
        return 2
    fi
}
