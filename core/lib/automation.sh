#!/bin/bash
# Read-only index bridge and explicit operator CLI for Step 14A.

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
