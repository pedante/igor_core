#!/usr/bin/env bash
# Canonical capability adapter for application-neutral brownfield attachment.

_igor_attachment_call() {
    local _action="$1" _fields="${2:-}" _request _active=false
    [ -n "$_fields" ] || _fields='{}'
    if declare -f _ml_owner_active >/dev/null 2>&1 && _ml_owner_active nextcloud_docker; then
        _active=true
    fi
    _request="$(python3 - "${IGOR_DIR}" "${IGOR_DATA_DIR:-${IGOR_DIR}/data}" "$_active" "$_fields" <<'PY'
import json, sys
root, data_dir, active, fields = sys.argv[1:]
request = json.loads(fields)
request.update(igor_dir=root, data_dir=data_dir, provider_active=active == "true")
print(json.dumps(request, separators=(",", ":")))
PY
)" || return 1
    printf '%s' "$_request" | python3 "${_IGOR_LOADER_DIR:-${IGOR_DIR}}/core/lib/deployment_attachment.py" "$_action"
}

_igor_deployment_attachment_invoke() {
    local _proposal="$1" _inputs _id _action
    _id="$(_igor_capability_field "$_proposal" capability_id)" || return 1
    _inputs="$(_igor_capability_field "$_proposal" inputs)" || return 1
    case "$_id" in
        core.deployments.discover) _action=discover ;;
        core.deployments.propose) _action=propose ;;
        core.deployments.release.propose) _action=release-propose ;;
        core.deployments.initialize) _action=initialize ;;
        core.deployments.adopt) _action=adopt ;;
        core.deployments.release) _action=release ;;
        *) return 1 ;;
    esac
    if [ "$_action" = discover ] || [ "$_action" = propose ] || [ "$_action" = release-propose ]; then
        _igor_attachment_call "$_action" "$_inputs"
    else
        _inputs="$(python3 - "$_inputs" "${IGOR_HISTORY_OPERATION_ID:-}" <<'PY'
import json, sys
inputs = json.loads(sys.argv[1])
inputs["operation_id"] = sys.argv[2]
print(json.dumps(inputs, separators=(",", ":")))
PY
)" || return 1
        _igor_attachment_call "$_action" "$_inputs"
    fi
}
