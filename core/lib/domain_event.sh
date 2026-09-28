#!/usr/bin/env bash
# Session-local domain bus. The Python validator owns the envelope and buffer;
# these functions bind it to the active module index and Core callbacks.

if [ "${IGOR_DOMAIN_EVENT_OWNER:-}" != "$$" ] ||
   [ -z "${IGOR_DOMAIN_EVENT_FILE:-}" ] || [ ! -f "${IGOR_DOMAIN_EVENT_FILE:-}" ]; then
    IGOR_DOMAIN_EVENT_FILE="$(mktemp "${TMPDIR:-/tmp}/igor-domain-events.XXXXXXXX")" || return 1
    IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE="$(mktemp "${TMPDIR:-/tmp}/igor-domain-diagnostics.XXXXXXXX")" || return 1
    IGOR_DOMAIN_EVENT_OWNER="$$"
    chmod 600 -- "$IGOR_DOMAIN_EVENT_FILE" "$IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE"
    export IGOR_DOMAIN_EVENT_FILE IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE IGOR_DOMAIN_EVENT_OWNER
fi
declare -ga _IGOR_DOMAIN_SUBSCRIBERS

igor_domain_event_subscribe() {
    local _callback="${1:-}"
    [[ "$_callback" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] &&
        declare -F "$_callback" >/dev/null 2>&1 || return 2
    _IGOR_DOMAIN_SUBSCRIBERS+=("$_callback")
}

_igor_domain_deliver() {
    local _event="$1" _callback
    [ "${_IGOR_DOMAIN_DELIVERING:-0}" = 0 ] || return 2
    _IGOR_DOMAIN_DELIVERING=1
    for _callback in "${_IGOR_DOMAIN_SUBSCRIBERS[@]}"; do
        if ! ( "$_callback" "$_event" ) >> "$IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE" 2>&1; then
            printf 'domain event: subscriber %s failed\n' "$_callback" >> "$IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE"
        fi
    done
    _IGOR_DOMAIN_DELIVERING=0
}

_igor_domain_result_published() {
    local _event
    [ "${_IGOR_DOMAIN_DELIVERING:-0}" = 0 ] || return 2
    _event="$(printf '%s' "$1" | "$(_ml_python)" "${_IGOR_LOADER_DIR}/core/lib/domain_event.py" result "$IGOR_DOMAIN_EVENT_FILE" 2>> "$IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE")" || return 2
    _igor_domain_deliver "$_event"
}

# Only a runtime-bound module handler may use this API; caller data has no
# owner/source/identity fields. The index is rechecked on every request.
igor_domain_event_publish() {
    local _id="${1:-}" _request="${2:-}" _owner="${_IGOR_DOMAIN_HANDLER_OWNER:-}" _record _event
    [ "${_IGOR_DOMAIN_DELIVERING:-0}" = 0 ] || return 2
    [ -n "$_owner" ] && [ "$_owner" != core ] || return 2
    _record="$(igor_v2_contribution_get domain_event "$_id")" || return 2
    [ "${_IGOR_CONTRIBUTION_OWNER[domain_event:$_id]:-}" = "$_owner" ] || return 2
    _event="$(printf '%s' "$_request" | "$(_ml_python)" "${_IGOR_LOADER_DIR}/core/lib/domain_event.py" module "$IGOR_DOMAIN_EVENT_FILE" "$_record")" || return 2
    _igor_domain_deliver "$_event"
    printf '%s\n' "$_event"
}

igor_domain_event_types() {
    local _key _owner _record _state
    {
        printf '%s\0' capability.completed core core:capability_runtime active '{"schema_version":1}'
        while IFS= read -r _key; do
            [[ "$_key" = domain_event:* ]] || continue
            _owner="${_IGOR_CONTRIBUTION_OWNER[$_key]}"
            _record="${_IGOR_CONTRIBUTIONS[$_key]}"
            _state="$(igor_contribution_state "$_key")"
            printf '%s\0' "${_key#domain_event:}" "$_owner" "module:$_owner" "$_state" "$_record"
        done < <(printf '%s\n' "${!_IGOR_CONTRIBUTIONS[@]}" | sort)
    } | "$(_ml_python)" -c '
import json,sys
parts=sys.stdin.buffer.read().split(b"\0")
rows=[]
for i in range(0,len(parts)-1,5):
    ident,owner,source,state,record=(v.decode() for v in parts[i:i+5])
    descriptor=json.loads(record)
    rows.append({"event_type":ident,"schema_version":1,"owner":owner,"source":source,
                 "availability":state,"payload_schema":descriptor.get("payload_schema")})
print(json.dumps(rows,sort_keys=True,separators=(",",":")))
'
}

igor_domain_event_recent() {
    local _filters="${1-}"
    [ -n "$_filters" ] || _filters='{}'
    "$(_ml_python)" "${_IGOR_LOADER_DIR}/core/lib/domain_event.py" inspect "$IGOR_DOMAIN_EVENT_FILE" "$_filters"
}
