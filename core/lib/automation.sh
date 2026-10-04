#!/bin/bash
# Index bridge, operator CLI, and deferred READ ticks.

_igor_automation_context() {
    local _capabilities _proposals _events
    _capabilities="$(igor_capability_list)" || return 1
    _proposals="$(igor_automation_proposals)" || return 1
    if declare -F igor_domain_event_types >/dev/null 2>&1; then
        _events="$(igor_domain_event_types)" || return 1
    else
        _events='[]'
    fi
    python3 -c 'import json,sys; print(json.dumps({"data_dir":sys.argv[1],"capabilities":json.loads(sys.argv[2]),"proposals":[json.loads(line) for line in sys.argv[3].splitlines() if line],"event_types":json.loads(sys.argv[4])},separators=(",", ":")))' \
        "${IGOR_DATA_DIR:-${IGOR_DIR}/data}" "$_capabilities" "$_proposals" "$_events"
}

igor_automation_proposals() {
    local _key _owner _record _version
    for _key in "${!_IGOR_CONTRIBUTIONS[@]}"; do
        [[ "$_key" == automation:* ]] || continue
        [ "$(igor_contribution_state "$_key")" = active ] || continue
        _owner="${_IGOR_CONTRIBUTION_OWNER[$_key]}"
        _record="$(igor_v2_contribution_get automation "${_key#automation:}")" || continue
        _version="$(printf '%s' "${_IGOR_V2_DATA[$_owner]}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["manifest"]["version"])')" || return 1
        python3 -c 'import json,sys; print(json.dumps({"id":sys.argv[1],"owner":sys.argv[2],"module_version":sys.argv[3],"source":sys.argv[4],"availability":"active","descriptor":json.loads(sys.argv[5])},separators=(",", ":")))' \
            "${_key#automation:}" "$_owner" "$_version" "${_IGOR_CONTRIBUTION_SOURCE[$_key]}" "$_record"
    done
}

igor_automation_cli() {
    local _action="$1" _argument="${2:-}" _config="${3:-}" _context
    _context="$(_igor_automation_context)" || return 1
    case "$_action" in
        proposals|list) printf '%s' "$_context" | python3 "${IGOR_DIR}/core/lib/automation_registry.py" "$_action" --mode "${IGOR_AI_MODE:-Assist}" ;;
        inspect|create|enable|disable|delete|reset)
            printf '%s' "$_context" | python3 "${IGOR_DIR}/core/lib/automation_registry.py" "$_action" "$_argument" --mode "${IGOR_AI_MODE:-Assist}" ;;
        edit)
            printf '%s' "$_context" | python3 "${IGOR_DIR}/core/lib/automation_registry.py" edit "$_argument" "$_config" --mode "${IGOR_AI_MODE:-Assist}" ;;
        *) return 2 ;;
    esac
}

igor_automation_run_due() {
    local _run_dir="${IGOR_DATA_DIR:-${IGOR_DIR}/data}/automation" _run_fd _status
    [ ! -L "$_run_dir" ] || { printf 'automation: store path is a symlink\n' >&2; return 1; }
    mkdir -p "$_run_dir" || return 1
    chmod 700 "$_run_dir" || return 1
    exec {_run_fd}<"$_run_dir" || return 1
    flock -n "$_run_fd"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        exec {_run_fd}<&-
        [ "$_status" -eq 1 ] || return "$_status"
        printf '{"admitted":0,"reason":"overlap_skipped"}\n'
        return 0
    fi
    _igor_automation_run_due_locked "$@"
    _status=$?
    exec {_run_fd}<&-
    return "$_status"
}

_igor_automation_run_due_locked() {
    local _mode _context _claim_context _facts _claim _request _completion _result _tick _count=0 _rc=0
    case "${1:-$(ai_get_mode)}" in
        assist|Assist) _mode=Assist ;;
        executive|Executive) _mode=Executive ;;
        guide|Guide) _mode=Guide ;;
        *) printf 'automation: unsupported mode\n' >&2; return 2 ;;
    esac
    if [ "${ai_mode+x}" = x ] && [ "$(ai_get_mode)" = guide ] && [ "$_mode" != Guide ]; then
        printf 'automation: Guide session cannot auto-run\n' >&2
        return 2
    fi
    [ "$_mode" != Guide ] || { printf '{"admitted":0}\n'; return 0; }
    _context="$(_igor_automation_context)" || return 1
    _tick="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" || return 1
    # Keep the normal policy and capability runtime in the same process so
    # the canonical result and Step 13 publication remain authoritative.
    declare -f ai_execute_tool >/dev/null 2>&1 || source "${IGOR_DIR}/core/ai/safety.sh" || return 1
    ai_mode="${_mode,,}"
    while :; do
        # This is an owner-filtered read of the current model. A missing or
        # failed read supplies no matching facts; it never invokes an observer.
        _facts='[]'
        if declare -F igor_model_list >/dev/null 2>&1; then
            _facts="$(igor_model_list | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["facts"],separators=(",",":")))')" || _facts='[]'
        fi
        _claim_context="$(python3 -c 'import json,sys; c=json.loads(sys.argv[1]); c["facts"]=json.loads(sys.argv[2]); print(json.dumps(c,separators=(",",":")))' "$_context" "$_facts")" || return 1
        _claim="$(printf '%s' "$_claim_context" | python3 "${IGOR_DIR}/core/lib/automation_registry.py" claim --mode "$_mode" --now "$_tick")" || return 1
        [ "$_claim" != null ] || break
        _igor_automation_dispatch_claim "$_context" "$_claim" || _rc=1
        ((_count+=1))
    done
    printf '{"admitted":%d}\n' "$_count"
    return "$_rc"
}

_igor_automation_dispatch_claim() {
    local _context="$1" _claim="$2" _request _result _completion _id _rc=0
    local IGOR_HISTORY_ACTOR=automation IGOR_HISTORY_INTERFACE=automation
    local IGOR_HISTORY_AUTOMATION_ID IGOR_HISTORY_AUTOMATION_CLAIM_ID IGOR_HISTORY_AUTOMATION_SLOT IGOR_HISTORY_CAUSATION_ID
    local _prior_draining="${_IGOR_AUTOMATION_DRAINING:-0}"
    _request="$(python3 -c 'import json,sys; t=json.loads(sys.argv[1])["target"]; r={"tool":"run_capability","id":t["capability_id"],"inputs":t["inputs"]}; r.update({"provider":t["provider"]} if "provider" in t else {}); print(json.dumps(r,separators=(",", ":")))' "$_claim")" || return 1
    _id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["id"])' "$_claim")" || return 1
    IGOR_CAPABILITY_LAST_RESULT=""
    IGOR_HISTORY_AUTOMATION_ID="$_id"
    IGOR_HISTORY_AUTOMATION_CLAIM_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["claim_id"])' "$_claim")" || return 1
    IGOR_HISTORY_AUTOMATION_SLOT="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("slot", ""))' "$_claim")" || return 1
    IGOR_HISTORY_CAUSATION_ID="$(python3 -c 'import re,sys; s=sys.argv[1]; print(s if re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}",s) else "")' "$IGOR_HISTORY_AUTOMATION_SLOT")" || return 1
    export IGOR_HISTORY_ACTOR IGOR_HISTORY_INTERFACE IGOR_HISTORY_AUTOMATION_ID IGOR_HISTORY_AUTOMATION_CLAIM_ID IGOR_HISTORY_AUTOMATION_SLOT IGOR_HISTORY_CAUSATION_ID
    _IGOR_AUTOMATION_DRAINING=1
    ai_execute_tool "$_request" >/dev/null || _rc=1
    _IGOR_AUTOMATION_DRAINING="$_prior_draining"
    _result="${IGOR_CAPABILITY_LAST_RESULT:-null}"
    _completion="$(python3 -c 'import json,sys; c=json.loads(sys.argv[1]); print(json.dumps({"claim_id":c["claim_id"],"result":json.loads(sys.argv[2])},separators=(",", ":")))' "$_claim" "$_result")" || return 1
    printf '%s' "$_context" | python3 "${IGOR_DIR}/core/lib/automation_registry.py" finish "$_id" "$_completion" >/dev/null || return 1
    return "$_rc"
}

igor_automation_subscribe() {
    [ -n "${IGOR_AUTOMATION_EVENT_QUEUE:-}" ] && [ "${IGOR_AUTOMATION_QUEUE_OWNER:-}" = "$$" ] && return 0
    IGOR_AUTOMATION_EVENT_QUEUE="$(mktemp "${TMPDIR:-/tmp}/igor-automation-events.XXXXXXXX")" || return 1
    chmod 600 "$IGOR_AUTOMATION_EVENT_QUEUE" || return 1
    IGOR_AUTOMATION_QUEUE_OWNER="$$"
    igor_domain_event_subscribe _igor_automation_event_callback
}

_igor_automation_event_callback() {
    [ "${_IGOR_AUTOMATION_DRAINING:-0}" = 0 ] || return 0
    local _ids _line _fd _mode
    _mode="$(ai_get_mode)" || return 1
    case "${_mode,,}" in guide) return 0 ;; assist|executive) ;; *) return 1 ;; esac

    # Domain delivery only queues a potential signal. Do the cheapest safe
    # negative test directly against the durable automation registry; do not
    # rebuild the global capability/proposal/event context on every unrelated
    # capability.completed event. claim-event revalidates the complete current
    # context before any automation can dispatch.
    _ids="$(python3 "${IGOR_DIR}/core/lib/automation_registry.py" prefilter-event "$1" \
        --mode "$_mode" --data-dir "${IGOR_DATA_DIR:-${IGOR_DIR}/data}")" || return 1
    [ "$_ids" != '[]' ] || return 0
    _line="$(python3 -c 'import json,sys; print(json.dumps({"event":json.loads(sys.argv[1]),"ids":json.loads(sys.argv[2])},separators=(",", ":")))' "$1" "$_ids")" || return 1
    exec {_fd}>>"$IGOR_AUTOMATION_EVENT_QUEUE" || return 1
    flock -x "$_fd" || { exec {_fd}>&-; return 1; }
    if [ "$(wc -l < "$IGOR_AUTOMATION_EVENT_QUEUE")" -lt 128 ]; then
        printf '%s\n' "$_line" >&"$_fd"
    fi
    exec {_fd}>&-
}

igor_automation_drain_events() {
    local _mode="${1:-$(ai_get_mode)}" _context _pending _signal _id _event _claim _fd _run_fd _count=0 _rc=0
    local _run_dir="${IGOR_DATA_DIR:-${IGOR_DIR}/data}/automation"
    [ -n "${IGOR_AUTOMATION_EVENT_QUEUE:-}" ] || { printf '{"admitted":0}\n'; return 0; }
    [ "${_IGOR_AUTOMATION_DRAINING:-0}" = 0 ] || { printf '{"admitted":0,"reason":"overlap_skipped"}\n'; return 0; }
    case "$_mode" in
        assist|Assist) _mode=Assist ;;
        executive|Executive) _mode=Executive ;;
        guide|Guide) printf '{"admitted":0}\n'; return 0 ;;
        *) return 2 ;;
    esac
    [ "$(ai_get_mode)" != guide ] || { printf '{"admitted":0}\n'; return 0; }
    _context="$(_igor_automation_context)" || return 1
    [ ! -L "$_run_dir" ] || return 1
    mkdir -p "$_run_dir" || return 1
    chmod 700 "$_run_dir" || return 1
    exec {_run_fd}<"$_run_dir" || return 1
    if ! flock -n "$_run_fd"; then
        exec {_run_fd}<&-
        printf '{"admitted":0,"reason":"overlap_skipped"}\n'
        return 0
    fi
    exec {_fd}<>"$IGOR_AUTOMATION_EVENT_QUEUE" || { exec {_run_fd}<&-; return 1; }
    if ! flock -n -x "$_fd"; then
        exec {_fd}>&-
        exec {_run_fd}<&-
        printf '{"admitted":0,"reason":"overlap_skipped"}\n'
        return 0
    fi
    _pending="$(cat "$IGOR_AUTOMATION_EVENT_QUEUE")" || { exec {_fd}>&-; exec {_run_fd}<&-; return 1; }
    : > "$IGOR_AUTOMATION_EVENT_QUEUE" || { exec {_fd}>&-; exec {_run_fd}<&-; return 1; }
    declare -f ai_execute_tool >/dev/null 2>&1 || source "${IGOR_DIR}/core/ai/safety.sh" || {
        exec {_fd}>&-
        exec {_run_fd}<&-
        return 1
    }
    ai_mode="${_mode,,}"
    _IGOR_AUTOMATION_DRAINING=1
    while IFS= read -r _signal; do
        [ -n "$_signal" ] || continue
        _event="$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["event"],separators=(",", ":")))' "$_signal")" || { _rc=1; continue; }
        while IFS= read -r _id; do
            [ -n "$_id" ] || continue
            _claim="$(printf '%s' "$_context" | python3 "${IGOR_DIR}/core/lib/automation_registry.py" claim-event "$_id" "$_event" --mode "$_mode")" || { _rc=1; continue; }
            [ "$_claim" != null ] || continue
            _igor_automation_dispatch_claim "$_context" "$_claim" || _rc=1
            ((_count+=1))
        done < <(python3 -c 'import json,sys; print("\n".join(json.loads(sys.argv[1])["ids"]))' "$_signal")
    done <<< "$_pending"
    _IGOR_AUTOMATION_DRAINING=0
    exec {_fd}>&-
    exec {_run_fd}<&-
    printf '{"admitted":%d}\n' "$_count"
    return "$_rc"
}

if declare -F igor_domain_event_subscribe >/dev/null 2>&1; then
    igor_automation_subscribe
fi
