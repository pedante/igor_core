#!/usr/bin/env bash
# Private bridge to the Operational History service. Records are reference
# material; recovery queries only current registered deterministic verifiers.

_igor_history_call() {
    local _action="$1" _fields="${2:-}" _request
    [ -n "$_fields" ] || _fields='{}'
    _request="$(printf '%s' "$_fields" | python3 -c 'import json,sys; r=json.load(sys.stdin); r["data_dir"]=sys.argv[1]; print(json.dumps(r,separators=(",",":")))' "${IGOR_DATA_DIR:-${IGOR_DIR}/data}")" || return 1
    printf '%s' "$_request" | python3 "${_IGOR_LOADER_DIR:-${IGOR_DIR}}/core/lib/operational_history.py" "$_action"
}

_igor_history_begin() {
    local _proposal="$1" _correlation="${2:-}" _mode="${3:-assist}" _requirement _request _record _tier
    _tier="$(_igor_capability_field "$_proposal" safety.tier)" || return 1
    case "$_tier:$_mode" in
        DESTROY:*) _requirement=exact_yes ;;
        CHANGE:executive) _requirement=executive_policy ;;
        CHANGE:*) _requirement=change_confirm ;;
        READ:guide) _requirement=guide_confirm ;;
        *) _requirement=policy_read ;;
    esac
    _request="$(python3 - "$_proposal" "$_correlation" "$_requirement" "$$" <<'PY'
import json, os, sys, uuid
refs = {}
for key, name in (("automation_id", "IGOR_HISTORY_AUTOMATION_ID"),
                  ("automation_claim_id", "IGOR_HISTORY_AUTOMATION_CLAIM_ID"),
                  ("automation_slot", "IGOR_HISTORY_AUTOMATION_SLOT"),
                  ("causation_id", "IGOR_HISTORY_CAUSATION_ID"),
                  ("plan_digest", "IGOR_HISTORY_PLAN_DIGEST"), ("plan_step", "IGOR_HISTORY_PLAN_STEP")):
    if os.environ.get(name):
        refs[key] = os.environ[name]
print(json.dumps({"proposal": json.loads(sys.argv[1]), "correlation_id": sys.argv[2] or "corr-" + uuid.uuid4().hex,
                  "approval_requirement": sys.argv[3], "owner_pid": int(sys.argv[4]), "references": refs,
                  "provenance": {"actor": os.environ.get("IGOR_HISTORY_ACTOR", "ai" if os.environ.get("IGOR_AI_REQUEST_ID") else "operator"),
                                 "interface": os.environ.get("IGOR_HISTORY_INTERFACE", "ai_dispatcher" if sys.argv[2] else "capability_api"),
                                 "request_id": os.environ.get("IGOR_AI_REQUEST_ID") or None}}, separators=(",", ":")))
PY
)" || return 1
    # New execution admission also reconciles abandoned prior-process claims.
    # History inspection never enters this path.
    igor_history_recover >/dev/null || return 1
    _record="$(_igor_history_call prepare "$_request")" || return 1
    _igor_capability_field "$_record" operation_id
}

_igor_history_update() {
    local _action="$1" _id="$2" _first="${3:-}" _second="${4:-}" _fields
    _fields="$(python3 - "$_action" "$_id" "$_first" "$_second" <<'PY'
import json, sys
act, ident, first, second = sys.argv[1:]
request = {"operation_id": ident}
if act == "authority":
    request.update(approval=first, privilege=second)
elif act == "running":
    request["proposal"] = json.loads(first)
elif act == "provider-complete":
    request["execution_status"] = first
elif act == "finish":
    request["result"] = json.loads(first)
elif act == "reconcile":
    request.update(verification_status=first, evidence=json.loads(second or "{}"))
print(json.dumps(request,separators=(",", ":")))
PY
)" || return 1
    _igor_history_call "$_action" "$_fields" >/dev/null
}

# One execution-boundary adapter owns terminal hand-off. Result commitment is
# independent of history/event diagnostics after a provider has already run.
_igor_capability_publish_result() {
    local _result="$1" _id
    _id="$(_igor_capability_field "$_result" operation_id)" || return 1
    printf '%s\n' "$_result" >> "$IGOR_CAPABILITY_RESULT_FILE" || return 1
    if ! _igor_history_update finish "$_id" "$_result" 2>/dev/null; then
        printf 'operational history: terminal persistence unavailable for %s; canonical result retained\n' "$_id" >> "$IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE"
    fi
    _igor_domain_result_published "$_result" || printf 'domain event: capability result publication failed\n' >> "$IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE"
    printf '%s\n' "$_result"
}

igor_history_recover() {
    local _only="${1:-}" _episodes _episode _id _proposal _inputs _capability _provider _version _kind _matches _evidence _status
    _episodes="$(_igor_history_call recover)" || return 1
    while IFS= read -r -d '' _episode; do
        _id="$(_igor_capability_field "$_episode" operation_id)" || return 1
        [ -z "$_only" ] || [ "$_id" = "$_only" ] || continue
        _status=unavailable
        _evidence='{"source":"operational_history.recovery","reason":"current matching unprivileged verifier unavailable; explicit operator recovery required"}'
        _inputs="$(_igor_capability_field "$_episode" inputs)" || return 1
        _capability="$(_igor_capability_field "$_episode" capability.id)" || return 1
        _version="$(_igor_capability_field "$_episode" capability.version)" || return 1
        _provider="$(_igor_capability_field "$_episode" provider.id)" || return 1
        # A historical descriptor cannot dispatch or grant privilege. Resolve
        # the live active provider and compare its contract and safe inputs.
        if [ "$(_igor_capability_field "$_episode" inputs_redacted)" = False ] &&
           _proposal="$(igor_capability_prepare "$_capability" "$_inputs" "$_provider" 2>/dev/null)"; then
            _kind="$(_igor_capability_field "$_proposal" verification.kind)" || _kind=none
            _matches="$(python3 - "$_episode" "$_proposal" <<'PY'
import json,sys
row,p=map(json.loads,sys.argv[1:])
print("yes" if (row["capability"]["version"] == p["capability_version"] and
                row["provider"]["owner"] == p["owner"] and row["inputs"] == p["inputs"] and
                row["provider"]["source"].get("module_version") == p.get("provider_source_module_version") and
                row["verification"]["contract"] == p["verification"] and
                [x["object_id"] for x in row["affected_objects"]] == p["affected_objects"]) else "no")
PY
)" || _matches=no
            # service_state is currently the only state-changing verifier with
            # an unprivileged, side-effect-free platform query. No observer
            # refresh, privileged verifier, historical handler or retry here.
            if [ "$_matches" = yes ] && [ "$_kind" = service_state ]; then
                if _evidence="$(_igor_capability_verify "$_proposal")"; then
                    _status=passed
                else
                    _status=failed
                    [ -n "$_evidence" ] || { _status=unknown; _evidence='{"source":"platform.service_query","reason":"query unavailable"}'; }
                fi
            fi
        fi
        _igor_history_update reconcile "$_id" "$_status" "$_evidence" || return 1
    done < <(printf '%s' "$_episodes" | python3 -c 'import json,sys; [sys.stdout.buffer.write(json.dumps(r,separators=(",", ":")).encode()+b"\0") for r in json.load(sys.stdin)]')
    _igor_history_call recent
}

_igor_history_restore_document() {
    # Decode the original document strictly before wrapping it for the service;
    # an ordinary json.load would silently discard duplicate version/fields.
    python3 -c '
import json,sys
sys.path.insert(0,sys.argv[2])
from operational_history import _decode
print(json.dumps({"data_dir":sys.argv[1],"export":_decode(sys.stdin.read())},allow_nan=False))
' "${IGOR_DATA_DIR:-${IGOR_DIR}/data}" "${_IGOR_LOADER_DIR:-${IGOR_DIR}}/core/lib" | \
        python3 "${_IGOR_LOADER_DIR:-${IGOR_DIR}}/core/lib/operational_history.py" restore
}

igor_history_cli() {
    local _action="${1:-recent}" _argument="${2:-}" _fields
    case "$_action" in
        status|export) [ -z "$_argument" ] || return 2; _igor_history_call "$_action" ;;
        recent)
            _fields="$(python3 -c 'import json,sys; print(json.dumps({"limit":int(sys.argv[1])}))' "${_argument:-20}")" || return 2
            _igor_history_call recent "$_fields" ;;
        inspect|correlation)
            _fields="$(python3 -c 'import json,sys; print(json.dumps({"operation_id" if sys.argv[1]=="inspect" else "correlation_id":sys.argv[2]}))' "$_action" "$_argument")" || return 2
            _igor_history_call "$_action" "$_fields" ;;
        recover) igor_history_recover "$_argument" ;;
        restore)
            if [ "$_argument" = - ]; then
                _igor_history_restore_document
            else
                printf '%s' "$_argument" | _igor_history_restore_document
            fi ;;
        reset) [ "$_argument" = YES ] || { printf 'Usage: --history reset YES\n' >&2; return 2; }; _igor_history_call reset ;;
        *) printf 'Usage: --history [recent [LIMIT]|inspect ID|correlation ID|status|export|restore EXPORT_JSON|recover [ID]|reset YES]\n' >&2; return 2 ;;
    esac
}
