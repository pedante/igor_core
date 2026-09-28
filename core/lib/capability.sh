#!/usr/bin/env bash
# Wave E adapter over the existing owner-stamped contribution index. The AI
# dispatcher owns authorization and PTY authentication; this file never asks
# for approval or reads a password.

if [ "${IGOR_CAPABILITY_RESULT_OWNER:-}" != "$$" ] ||
   [ -z "${IGOR_CAPABILITY_RESULT_FILE:-}" ] ||
   [ ! -f "${IGOR_CAPABILITY_RESULT_FILE:-}" ]; then
    IGOR_CAPABILITY_RESULT_FILE="$(mktemp "${TMPDIR:-/tmp}/igor-capability-results.XXXXXXXX")" || return 1
    IGOR_CAPABILITY_RESULT_OWNER="$$"
    export IGOR_CAPABILITY_RESULT_FILE IGOR_CAPABILITY_RESULT_OWNER
    chmod 600 -- "$IGOR_CAPABILITY_RESULT_FILE"
fi

igor_capability_result() {
    local _id="${1:-}"
    [ -f "${IGOR_CAPABILITY_RESULT_FILE:-}" ] || return 1
    "$(_ml_python)" - "$_id" "$IGOR_CAPABILITY_RESULT_FILE" <<'PY'
import json, sys
ident, path = sys.argv[1:]
found = None
with open(path, encoding="utf-8") as stream:
    for line in stream:
        row = json.loads(line)
        if row.get("operation_id") == ident:
            found = row
if found is None:
    raise SystemExit(1)
print(json.dumps(found, sort_keys=True, separators=(",", ":")))
PY
}

igor_capability_plan_resolve() {
    local _plan="${1:-}" _records _request
    _records="$(igor_capability_list)" || return 1
    _request="$("$(_ml_python)" - "$_plan" "$_records" <<'PY'
import json, sys
plan, records = json.loads(sys.argv[1]), json.loads(sys.argv[2])
if not isinstance(plan, dict) or set(plan) - {"plan_version", "intended_outcome", "steps", "objects", "final_check"}:
    raise SystemExit(1)
if plan.get("plan_version") != 1 or not isinstance(plan.get("intended_outcome"), str) or not plan["intended_outcome"].strip():
    raise SystemExit(1)
steps = plan.get("steps")
if not isinstance(steps, list) or not 1 <= len(steps) <= 16:
    raise SystemExit(1)
for step in steps:
    if not isinstance(step, dict) or set(step) - {"capability_id", "provider", "inputs"}:
        raise SystemExit(1)
final_check = plan.get("final_check")
if final_check is not None and (not isinstance(final_check, dict) or set(final_check) - {"capability_id", "provider", "inputs"}):
    raise SystemExit(1)
print(json.dumps({"op": "plan", "records": records, "plan_version": 1,
                  "intended_outcome": plan["intended_outcome"], "objects": plan.get("objects", []),
                  "steps": steps, "final_check": final_check},
                 separators=(",", ":")))
PY
)" || return 1
    printf '%s' "$_request" | "$(_ml_python)" "${_IGOR_LOADER_DIR}/core/lib/capability_runtime.py"
}

# Each step enters the same AI dispatcher as a single operation. The resolved
# digest is checked again before the first step and every later step is
# re-resolved by igor_capability_prepare inside that dispatcher.
igor_capability_plan_execute() {
    local _resolved="${1:-}" _proposal _expected _actual _step _payload _result _outcome _dispatch_rc _completed='[]'
    _expected="$(_igor_capability_field "$_resolved" digest)" || return 1
    _proposal="$("$(_ml_python)" - "$_resolved" <<'PY'
import json, sys
p = json.loads(sys.argv[1])
def original(s):
    return {"capability_id": s["capability_id"], "provider": s["provider"], "inputs": s["inputs"]}
print(json.dumps({"plan_version": p["plan_version"], "intended_outcome": p["intended_outcome"],
                  "objects": p.get("objects", []), "steps": [original(s) for s in p["steps"]],
                  "final_check": original(p["final_check"]) if p.get("final_check") else None},
                 separators=(",", ":")))
PY
)" || return 1
    _actual="$(igor_capability_plan_resolve "$_proposal")" || return 1
    [ "$_expected" = "$(_igor_capability_field "$_actual" digest)" ] || return 1
    while IFS= read -r -d '' _step <&3; do
        _payload="$("$(_ml_python)" - "$_step" <<'PY'
import json, sys
step = json.loads(sys.argv[1])
print(json.dumps({"tool": "run_capability", "id": step["capability_id"],
                  "provider": step["provider"], "inputs": step["inputs"]}, separators=(",", ":")))
PY
)" || return 1
        IGOR_CAPABILITY_LAST_RESULT=""
        ai_execute_tool "$_payload"
        _dispatch_rc=$?
        _result="${IGOR_CAPABILITY_LAST_RESULT:-}"
        if [ -n "$_result" ]; then
            _completed="$("$(_ml_python)" - "$_completed" "$_result" <<'PY'
import json, sys
completed = json.loads(sys.argv[1])
result = json.loads(sys.argv[2])
completed.append({key: result.get(key) for key in (
    "operation_id", "capability_id", "provider", "outcome",
    "execution_status", "verification_status")})
print(json.dumps(completed, separators=(",", ":")))
PY
)" || return 1
        fi
        _outcome="$(_igor_capability_field "$_result" outcome 2>/dev/null)" || _outcome=dispatch_failed
        if [ "$_dispatch_rc" -ne 0 ] || [ "$_outcome" != success ]; then
            _igor_capability_plan_finish "$_resolved" "$_completed" stopped "$_outcome"
            return 1
        fi
    done 3< <(printf '%s' "$_resolved" | "$(_ml_python)" -c '
import json,sys
plan = json.load(sys.stdin)
for step in plan["steps"] + ([plan["final_check"]] if plan.get("final_check") else []):
    sys.stdout.buffer.write(json.dumps(step,separators=(",", ":")).encode()+b"\0")
')
    _igor_capability_plan_finish "$_resolved" "$_completed" success ""
}

_igor_capability_plan_finish() {
    local _record
    _record="$("$(_ml_python)" - "$1" "$2" "$3" "$4" <<'PY'
import json, sys
plan, completed = map(json.loads, sys.argv[1:3])
print(json.dumps({"plan_version": plan["plan_version"], "digest": plan["digest"],
                  "intended_outcome": plan["intended_outcome"],
                  "completed_steps": completed, "outcome": sys.argv[3],
                  "stopped_reason": sys.argv[4] or None},
                 sort_keys=True, separators=(",", ":")))
PY
)" || return 1
    IGOR_CAPABILITY_PLAN_LAST_RESULT="$_record"
    printf '%s\n' "$_record"
}

_igor_capability_field() {
    printf '%s' "$1" | "$(_ml_python)" -c '
import json, sys
value = json.load(sys.stdin)
for key in sys.argv[1].split("."):
    value = value[key]
if isinstance(value, (dict, list)):
    print(json.dumps(value, sort_keys=True, separators=(",", ":")))
elif value is not None:
    print(value)
' "$2"
}

igor_capability_prepare() {
    local _id="${1:-}" _inputs="${2:-}" _provider="${3:-}" _records _request _proposal _spec='[]' _unit _precondition_status=satisfied
    [ -n "$_inputs" ] || _inputs='{}'
    _records="$(igor_capability_list)" || return 1
    _request="$("$(_ml_python)" - "$_records" "$_id" "$_inputs" "$_provider" <<'PY'
import json, sys
try:
    print(json.dumps({"op": "prepare", "records": json.loads(sys.argv[1]),
                      "id": sys.argv[2], "inputs": json.loads(sys.argv[3]),
                      "provider": sys.argv[4] or None}, separators=(",", ":")))
except (ValueError, TypeError):
    raise SystemExit(1)
PY
)" || return 1
    _proposal="$(printf '%s' "$_request" | "$(_ml_python)" "${_IGOR_LOADER_DIR}/core/lib/capability_runtime.py")" || return 1
    if [ "$(_igor_capability_field "$_proposal" privilege)" = required ]; then
        # Reviewed Core operation adapter. A privileged module handler may not
        # replace argv after approval. Additional privileged operations need a
        # reviewed adapter here before becoming available.
        case "$_id" in
            system.service.restart)
                _unit="$(_igor_capability_field "$_proposal" inputs.unit)" || return 1
                [[ "$_unit" =~ ^[A-Za-z0-9][A-Za-z0-9_.@:+-]*$ ]] || return 1
                if ! declare -f svc_restart_argv >/dev/null 2>&1; then
                    # shellcheck source=core/lib/pkg.sh
                    source "${_IGOR_LOADER_DIR}/core/lib/pkg.sh"
                fi
                local _argv
                _argv="$(svc_restart_argv "$_unit")" || return 1
                [ "$_argv" = "systemctl restart $_unit" ] || return 1
                _spec="$("$(_ml_python)" - "$_unit" <<'PY'
import json, sys
print(json.dumps(["sudo", "-n", "--", "systemctl", "restart", sys.argv[1]], separators=(",", ":")))
PY
)" || return 1
                ;;
            *) return 1 ;;
        esac
    fi
    _igor_capability_preconditions "$_proposal" || _precondition_status=failed
    _proposal="$("$(_ml_python)" - "$_proposal" "$_spec" "$_precondition_status" <<'PY'
import hashlib, json, sys
value = json.loads(sys.argv[1])
value["privileged_argv"] = json.loads(sys.argv[2])
value["precondition_status"] = sys.argv[3]
value["digest"] = hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
print(json.dumps(value, sort_keys=True, separators=(",", ":")))
PY
)" || return 1
    printf '%s\n' "$_proposal"
}

_igor_capability_nonexecution_result() {
    local _result
    _result="$("$(_ml_python)" - "$1" "$2" "${3:-not_requested}" "${4:-not_required}" <<'PY'
import json, sys, uuid
from datetime import datetime, timezone
p = json.loads(sys.argv[1])
reason, approval, privilege = sys.argv[2:5]
print(json.dumps({"operation_id": "op-" + uuid.uuid4().hex,
                  "capability_id": p["capability_id"], "capability_version": p["capability_version"],
                  "provider": p["provider"],
                  "owner": p["owner"], "approval_status": approval,
                  "privilege_status": privilege,
                  "privilege": p["privilege"], "safety": p["safety"],
                  "precondition_status": "failed" if reason == "precondition_failed" else p["precondition_status"],
                  "execution_status": "not_executed",
                  "verification_status": "not_applicable", "outcome": reason,
                  "affected_objects": p["affected_objects"], "recovery": p["recovery"],
                  "verification_evidence": [],
                  "recorded_at": datetime.now(timezone.utc).isoformat()},
                 sort_keys=True, separators=(",", ":")))
PY
    )" || return 1
    printf '%s\n' "$_result" >> "$IGOR_CAPABILITY_RESULT_FILE" || return 1
    _igor_domain_result_published "$_result" || printf 'domain event: capability result publication failed\n' >> "$IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE"
    printf '%s\n' "$_result"
}

_igor_capability_preconditions() {
    local _proposal="$1" _row _kind _arg _object _property _expected _state _value _root
    while IFS=$'\t' read -r _kind _arg _object _property _expected; do
        [ -n "$_kind" ] || continue
        case "$_kind" in
            owner_active)
                _ml_owner_active "$(_igor_capability_field "$_proposal" owner)" || return 1 ;;
            service_exists)
                _value="$(_igor_capability_field "$_proposal" "inputs.$_arg")" || return 1
                declare -f svc_query >/dev/null 2>&1 || source "${_IGOR_LOADER_DIR}/core/lib/pkg.sh"
                svc_query "$_value" >/dev/null || return 1 ;;
            package_installed)
                _value="$(_igor_capability_field "$_proposal" "inputs.$_arg")" || return 1
                declare -f pkg_query >/dev/null 2>&1 || source "${_IGOR_LOADER_DIR}/core/lib/pkg.sh"
                pkg_query "$_value" >/dev/null || return 1 ;;
            path_exists)
                _value="$(_igor_capability_field "$_proposal" "inputs.$_arg")" || return 1
                _root="$(_igor_capability_field "$_proposal" "descriptor.inputs.properties.$_arg.root")" || return 1
                "$(_ml_python)" - "$_root" "$_value" <<'PY' || return 1
from pathlib import Path
import sys
base = Path(sys.argv[1]).resolve(strict=True)
path = base / sys.argv[2]
if not path.exists() or path.is_symlink():
    raise SystemExit(1)
try:
    path.resolve(strict=True).relative_to(base)
except ValueError:
    raise SystemExit(1)
PY
                ;;
            capability_available)
                _state="$(igor_capability_inspect "$_arg")" || return 1
                [ "$(_igor_capability_field "$_state" resolution)" = resolved ] || return 1 ;;
            model_fact)
                _state="$(igor_model_read "$_object" "$_property" observed)" || return 1
                [ "$(_igor_capability_field "$_state" availability)" = known ] || return 1
                [ "$(_igor_capability_field "$_state" value)" = "$_expected" ] || return 1 ;;
            *) return 1 ;;
        esac
    done < <(printf '%s' "$_proposal" | "$(_ml_python)" -c '
import json, sys
p = json.load(sys.stdin)
for x in p["preconditions"]:
    arg = x.get("capability_id") if x.get("kind") == "capability_available" else x.get("input", "")
    print("\t".join(str(v) for v in (x.get("kind", ""), arg or "", x.get("object_id", ""), x.get("property", ""), x.get("equals", ""))))
')
}

_igor_capability_invoke_handler() {
    local _proposal="$1" _id _owner _key _handler _timeout _entrypoint _input
    _id="$(_igor_capability_field "$_proposal" capability_id)" || return 1
    _owner="$(_igor_capability_field "$_proposal" owner)" || return 1
    _key="capability:${_id}"
    [ "${_IGOR_CONTRIBUTION_OWNER[$_key]:-}" = "$_owner" ] || _key="${_key}@${_owner}"
    [ "$(igor_contribution_state "$_key")" = active ] || return 1
    _handler="$(_igor_capability_field "$_proposal" descriptor.handler)" || return 1
    _timeout="$(_igor_capability_field "$_proposal" descriptor.timeout_seconds 2>/dev/null || printf 30)"
    _entrypoint="$(_ml_v2_query "$_owner" manifest.entrypoint)" || return 1
    _input="$(_igor_capability_field "$_proposal" inputs)" || return 1
    # shellcheck source=core/lib/module_handler.sh
    source "${_IGOR_LOADER_DIR}/core/lib/module_handler.sh"
    V2_HANDLER_ENTRYPOINT="$_entrypoint" _ml_bash_handler_invoke \
        "${_IGOR_MODULE_DIRS[$_owner]}" "$_owner" "$_handler" "$_id" "$_timeout" "$_input"
}

_igor_capability_verify() {
    local _proposal="$1" _kind _observer _fact _attempt _unit _state _expected
    _kind="$(_igor_capability_field "$_proposal" verification.kind)" || return 1
    case "$_kind" in
        observer_fact)
            _observer="$(_igor_capability_field "$_proposal" verification.observer)" || return 1
            _fact="$(igor_model_read "$(_igor_capability_field "$_proposal" verification.object_id)" \
                "$(_igor_capability_field "$_proposal" verification.property)" observed)" || return 1
            _attempt="$(igor_model_list | "$(_ml_python)" -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["observers"].get(sys.argv[1],{})))' "$_observer")" || return 1
            [ "$(_igor_capability_field "$_fact" availability)" = known ] || return 1
            [ "$(_igor_capability_field "$_attempt" status)" = ok ] || return 1
            printf '%s\n' "$("$(_ml_python)" - "$_fact" "$_attempt" <<'PY'
import json, sys
fact, attempt = map(json.loads, sys.argv[1:])
print(json.dumps({"source": "system_model", "check_id": "observer_fact", "fact": fact,
                  "observer_attempt": attempt}, separators=(",", ":")))
PY
)" ;;
        service_state)
            _unit="$(_igor_capability_field "$_proposal" "inputs.$(_igor_capability_field "$_proposal" verification.input)")" || return 1
            _expected="$(_igor_capability_field "$_proposal" verification.equals)" || return 1
            _state="$(svc_query "$_unit")" || return 1
            "$(_ml_python)" - "$_unit" "$_state" "$_expected" <<'PY'
import json, sys
from datetime import datetime, timezone
print(json.dumps({"source": "platform.service_query", "check_id": "service_state",
                  "object_id": "service:systemd:" + sys.argv[1], "observed": sys.argv[2],
                  "expected": sys.argv[3],
                  "observed_at": datetime.now(timezone.utc).isoformat()}, separators=(",", ":")))
PY
            [ "$_state" = "$_expected" ] ;;
        none) printf '{}\n' ;;
        *) return 1 ;;
    esac
}

# Only the already approved in-process proposal may be supplied by the
# dispatcher. Re-resolution binds the same owner, descriptor, inputs and argv.
igor_capability_execute() {
    local _proposal="$1" _id _provider _inputs _fresh _digest _envelope _exec=failed _verify=not_applicable _outcome=failed _evidence='{}' _spec _result _tier
    _id="$(_igor_capability_field "$_proposal" capability_id)" || return 1
    _provider="$(_igor_capability_field "$_proposal" provider)" || return 1
    _inputs="$(_igor_capability_field "$_proposal" inputs)" || return 1
    _fresh="$(igor_capability_prepare "$_id" "$_inputs" "$_provider")" || return 1
    _digest="$(_igor_capability_field "$_proposal" digest)" || return 1
    [ -n "${IGOR_CAPABILITY_APPROVED_DIGEST:-}" ] &&
        [ "$IGOR_CAPABILITY_APPROVED_DIGEST" = "$_digest" ] || return 1
    if [ "$(_igor_capability_field "$_fresh" precondition_status)" != satisfied ]; then
        # A legitimate precondition change keeps the same proposal content
        # except for its evaluated status. Changed inputs/provider/argv never
        # become a new approved operation.
        local _pending_without_status _fresh_without_status
        _pending_without_status="$(printf '%s' "$_proposal" | "$(_ml_python)" -c 'import json,sys; p=json.load(sys.stdin); p.pop("digest",None); p.pop("precondition_status",None); print(json.dumps(p,sort_keys=True))')" || return 1
        _fresh_without_status="$(printf '%s' "$_fresh" | "$(_ml_python)" -c 'import json,sys; p=json.load(sys.stdin); p.pop("digest",None); p.pop("precondition_status",None); print(json.dumps(p,sort_keys=True))')" || return 1
        [ "$_pending_without_status" = "$_fresh_without_status" ] || return 1
        _igor_capability_nonexecution_result "$_fresh" precondition_failed approved
        return 0
    fi
    [ "$_digest" = "$(_igor_capability_field "$_fresh" digest)" ] || return 1
    if ! _igor_capability_preconditions "$_fresh"; then
        _igor_capability_nonexecution_result "$_fresh" precondition_failed
        return 0
    fi
    _spec="$(_igor_capability_field "$_fresh" privileged_argv)" || return 1
    if [ "$_spec" != '[]' ]; then
        # Exact reviewed argv. Authentication has already been handled by
        # safety.sh; -n prevents a hidden prompt here.
        if "$(_ml_python)" - "$_spec" <<'PY'
import json, subprocess, sys
argv = json.loads(sys.argv[1])
if len(argv) != 6 or argv[:5] != ["sudo", "-n", "--", "systemctl", "restart"]:
    raise SystemExit(1)
raise SystemExit(subprocess.run(argv, check=False, stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode)
PY
        then _exec=succeeded; fi
    else
        if _envelope="$(_igor_capability_invoke_handler "$_fresh")"; then
            if [ "$_id" = system.host.memory.refresh ]; then
                [ "$(_igor_capability_field "$_envelope" result.observer_id)" = host.memory ] &&
                    igor_observer_refresh host.memory host:local && _exec=succeeded
                if [ "$_exec" = succeeded ]; then
                    declare -f igor_health_run_v2_check >/dev/null 2>&1 ||
                        source "${_IGOR_LOADER_DIR}/core/lib/health_runner.sh"
                    igor_health_run_v2_check host.memory.health >/dev/null 2>&1 || true
                fi
            else
                _exec=succeeded
            fi
        fi
    fi
    if [ "$_exec" = succeeded ]; then
        _tier="$(_igor_capability_field "$_fresh" safety.tier)" || return 1
        if [ "$(_igor_capability_field "$_fresh" verification.kind)" != none ]; then
            if _evidence="$(_igor_capability_verify "$_fresh")"; then
                _verify=passed
            else
                _verify=failed
                if [ "$_tier" = READ ]; then _outcome=unverified_result; else _outcome=unverified_change; fi
            fi
        elif [ "$_tier" != READ ]; then
            _verify=unavailable
            _outcome=unverified_change
        fi
        [ "$_outcome" = failed ] && _outcome=success
    fi
    _result="$("$(_ml_python)" - "$_fresh" "$_exec" "$_verify" "$_outcome" "$_evidence" "${IGOR_CAPABILITY_APPROVAL_STATUS:-approved}" <<'PY'
import json, sys, uuid
from datetime import datetime, timezone
proposal = json.loads(sys.argv[1])
execution, verification, outcome = sys.argv[2:5]
try:
    evidence = json.loads(sys.argv[5])
except ValueError:
    evidence = {"reason": "verification_failed"}
result = {"operation_id": "op-" + uuid.uuid4().hex, "capability_id": proposal["capability_id"],
          "capability_version": proposal["capability_version"],
          "provider": proposal["provider"], "owner": proposal["owner"], "approval_status": sys.argv[6],
          "precondition_status": proposal["precondition_status"],
          "execution_status": execution, "verification_status": verification, "outcome": outcome,
          "privilege": proposal["privilege"],
          "privilege_status": "authenticated" if proposal["privilege"] == "required" else "not_required",
          "safety": proposal["safety"],
          "affected_objects": proposal["affected_objects"], "recovery": proposal["recovery"],
          "verification_evidence": [evidence] if evidence else [],
          "recorded_at": datetime.now(timezone.utc).isoformat()}
print(json.dumps(result, sort_keys=True, separators=(",", ":")))
PY
    )" || return 1
    printf '%s\n' "$_result" >> "$IGOR_CAPABILITY_RESULT_FILE" || return 1
    _igor_domain_result_published "$_result" || printf 'domain event: capability result publication failed\n' >> "$IGOR_DOMAIN_EVENT_DIAGNOSTICS_FILE"
    printf '%s\n' "$_result"
}
