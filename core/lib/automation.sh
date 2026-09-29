#!/bin/bash
# Index bridge, explicit operator CLI, and one-time READ tick.

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
    local _action="$1" _argument="${2:-}" _config="${3:-}" _capabilities _proposals _context
    _capabilities="$(igor_capability_list)" || return 1
    _proposals="$(igor_automation_proposals)" || return 1
    _context="$(python3 -c 'import json,sys; print(json.dumps({"data_dir":sys.argv[1],"capabilities":json.loads(sys.argv[2]),"proposals":[json.loads(line) for line in sys.argv[3].splitlines() if line]},separators=(",", ":")))' \
        "${IGOR_DATA_DIR:-${IGOR_DIR}/data}" "$_capabilities" "$_proposals")" || return 1
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
    local _mode _context _claim _request _completion _result _count=0 _rc=0
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
    _context="$(python3 -c 'import json,sys; print(json.dumps({"data_dir":sys.argv[1],"capabilities":json.loads(sys.argv[2]),"proposals":[json.loads(line) for line in sys.argv[3].splitlines() if line]},separators=(",", ":")))' \
        "${IGOR_DATA_DIR:-${IGOR_DIR}/data}" "$(igor_capability_list)" "$(igor_automation_proposals)")" || return 1
    # Keep the normal policy and capability runtime in the same process so
    # the canonical result and Step 13 publication remain authoritative.
    declare -f ai_execute_tool >/dev/null 2>&1 || source "${IGOR_DIR}/core/ai/safety.sh" || return 1
    ai_mode="${_mode,,}"
    while :; do
        _claim="$(printf '%s' "$_context" | python3 "${IGOR_DIR}/core/lib/automation_registry.py" claim --mode "$_mode")" || return 1
        [ "$_claim" != null ] || break
        _request="$(python3 -c 'import json,sys; c=json.loads(sys.argv[1]); t=c["target"]; r={"tool":"run_capability","id":t["capability_id"],"inputs":t["inputs"]}; r.update({"provider":t["provider"]} if "provider" in t else {}); print(json.dumps(r,separators=(",", ":")))' "$_claim")" || return 1
        IGOR_CAPABILITY_LAST_RESULT=""
        ai_execute_tool "$_request" >/dev/null || _rc=1
        _result="${IGOR_CAPABILITY_LAST_RESULT:-null}"
        _completion="$(python3 -c 'import json,sys; c=json.loads(sys.argv[1]); print(json.dumps({"claim_id":c["claim_id"],"result":json.loads(sys.argv[2])},separators=(",", ":")))' "$_claim" "$_result")" || return 1
        printf '%s' "$_context" | python3 "${IGOR_DIR}/core/lib/automation_registry.py" finish \
            "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["id"])' "$_claim")" "$_completion" >/dev/null || return 1
        ((_count+=1))
    done
    printf '{"admitted":%d}\n' "$_count"
    return "$_rc"
}
