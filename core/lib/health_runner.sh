#!/usr/bin/env bash
# Unified structured health result adapter (Wave D, Step 10).

_igor_health_python() {
    if declare -f _igor_model_python >/dev/null 2>&1; then
        _igor_model_python
    elif [ -n "${IGOR_PYTHON:-}" ] && command -v "$IGOR_PYTHON" >/dev/null 2>&1; then
        printf '%s\n' "$IGOR_PYTHON"
    elif command -v python3 >/dev/null 2>&1; then
        printf 'python3\n'
    elif command -v python >/dev/null 2>&1 && python --version 2>&1 | grep -q '^Python 3'; then
        printf 'python\n'
    else
        return 1
    fi
}

# igor_health_result_json CHECK OWNER OBJECT STATUS FINDING MESSAGE [FACTS] [EVIDENCE] [SOURCE]
igor_health_result_json() {
    local _check="${1:-}" _owner="${2:-}" _object="${3:-}" _status="${4:-}"
    local _finding="${5:-}" _message="${6:-}" _facts="${7:-[]}" _evidence="${8:-[]}" _source="${9:-${2:-}}"
    local _py; _py="$(_igor_health_python)" || return 1
    "$_py" - "$_check" "$_owner" "$_object" "$_status" "$_finding" "$_message" "$_facts" "$_evidence" "$_source" <<'PY'
import json, sys
from datetime import datetime, timezone
check, owner, obj, status, finding, message, facts, evidence, source = sys.argv[1:]
if not check or not owner or not obj or status not in {"OK", "WARN", "FAIL", "CRITICAL", "UNKNOWN", "SKIP"}:
    raise SystemExit(1)
try:
    used = json.loads(facts); ev = json.loads(evidence)
except json.JSONDecodeError:
    raise SystemExit(1)
if not isinstance(used, list) or not isinstance(ev, list) or len(message) > 2048:
    raise SystemExit(1)
if not all(isinstance(x, (str, dict)) for x in used + ev):
    raise SystemExit(1)
print(json.dumps({"check_id": check, "owner": owner, "object_id": obj,
                  "status": status, "finding_code": finding, "message": message,
                  "used_facts": used, "evidence": ev,
                  "source": source,
                  "evaluated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")},
                 separators=(",", ":")))
PY
}

_igor_health_emit() {
    local _json="$1"
    declare -f igor_model_store_health >/dev/null 2>&1 &&
        igor_model_store_health "$_json" >/dev/null 2>&1 || true
    printf '%s\n' "$_json"
}

# Convert legacy CHECK and CHECK_RESULT lines. This is an adapter only.
igor_health_legacy_to_json() {
    local _line="${1:-}" _check _status _message _sev _code
    local _owner="${IGOR_HEALTH_LEGACY_OWNER:-legacy}" _source="${IGOR_HEALTH_LEGACY_SOURCE:-line}"
    case "$_line" in
        CHECK:*)
            IFS=: read -r _ _check _status _message <<<"$_line"
            case "$_status" in ok) _sev=OK;; warn) _sev=WARN;; fail) _sev=FAIL;; skip) _sev=SKIP;; *) return 1;; esac ;;
        CHECK_RESULT\ *)
            read -r _ _sev _code _message <<<"$_line"
            _check="${_code:-legacy.unknown}"
            case "$_sev" in OK|WARN|FAIL|CRITICAL) ;; *) return 1;; esac ;;
        *) return 1;;
    esac
    [ -n "${_check:-}" ] || return 1
    [ -n "${_message:-}" ] || _message="legacy check returned $_sev"
    igor_health_result_json "legacy.${_owner}.${_source}.${_check}" "$_owner" \
        "${IGOR_HEALTH_LEGACY_OBJECT:-host:local}" "$_sev" "$_check" "$_message" '[]' '["legacy_direct"]' "legacy_direct:${_source}"
}

igor_health_json_to_diagnose() {
    local _json="$1" _py; _py="$(_igor_health_python)" || return 1
    printf '%s' "$_json" | "$_py" -c 'import json,sys; x=json.load(sys.stdin); m=x.get("message","").replace(":",";"); s={"OK":"ok","WARN":"warn","FAIL":"fail","CRITICAL":"fail","UNKNOWN":"skip","SKIP":"skip"}[x["status"]]; print("CHECK:{}:{}:{}".format(x["finding_code"],s,m))'
}

igor_health_json_to_healing() {
    local _json="$1" _py; _py="$(_igor_health_python)" || return 1
    printf '%s' "$_json" | "$_py" -c 'import json,sys; x=json.load(sys.stdin); print("CHECK_RESULT {} {} {}".format(x["status"],x["finding_code"],x.get("message","")))'
}

# Validate a v2 result and stamp authoritative identity. Handler output cannot
# select check/owner/target or grant execution authority.
igor_health_validate_handler_result() {
    local _check="$1" _owner="$2" _object="$3" _response="$4" _input="${5:-}" _py
    [ -n "$_input" ] || _input='{}'
    _py="$(_igor_health_python)" || return 1
    "$_py" - "$_check" "$_owner" "$_object" "$_response" "$_input" <<'PY'
import json
import sys

check, owner, obj, raw, request = sys.argv[1:]
try:
    x = json.loads(raw)
    snapshot = json.loads(request).get("facts", {})
except (ValueError, TypeError):
    raise SystemExit(1)
if not isinstance(x, dict) or set(x) != {"status", "finding_code", "message", "used_facts", "evidence"}:
    raise SystemExit(1)
if x["status"] not in {"OK", "WARN", "FAIL", "CRITICAL", "UNKNOWN", "SKIP"}:
    raise SystemExit(1)
if not isinstance(x["finding_code"], str) or not x["finding_code"] or len(x["finding_code"]) > 100:
    raise SystemExit(1)
if not isinstance(x["message"], str) or len(x["message"]) > 2048:
    raise SystemExit(1)
facts, evidence = x["used_facts"], x["evidence"]
if not isinstance(facts, list) or not isinstance(evidence, list) or len(facts) > 16 or len(evidence) > 8:
    raise SystemExit(1)
if any(not isinstance(item, str) or len(item) > 200 for item in evidence):
    raise SystemExit(1)
seen_props = set()
for used in facts:
    if not isinstance(used, dict) or set(used) != {"key", "recorded_at", "availability"}:
        raise SystemExit(1)
    key = used["key"]
    if not isinstance(key, list) or len(key) != 3 or key[0] != obj or key[2] != "observed":
        raise SystemExit(1)
    supplied = snapshot.get(key[1])
    if key[1] in seen_props or not isinstance(supplied, dict) or supplied.get("recorded_at") != used["recorded_at"] or supplied.get("availability") != used["availability"]:
        raise SystemExit(1)
    seen_props.add(key[1])
if seen_props != set(snapshot):
    raise SystemExit(1)
print(json.dumps(x, separators=(",", ":")))
PY
}

# Run one active v2 check.  Facts are resolved once for this invocation and
# supplied as reference data to the handler; handlers cannot mutate the model.
igor_health_run_v2_check() {
    local _id="${1:-}" _record _owner _handler _timeout _object _input _response _normalized
    local _observer _property _class _fact _availability _used _missing=0
    [ -n "$_id" ] || return 1
    declare -f igor_v2_contribution_get >/dev/null 2>&1 || return 1
    _record="$(igor_v2_contribution_get check "$_id")" || return 1
    _owner="${_IGOR_CONTRIBUTION_OWNER[check:${_id}]:-}"; [ -n "$_owner" ] || return 1
    _handler="$(printf '%s' "$_record" | "$(_igor_health_python)" -c 'import json,sys; print(json.load(sys.stdin).get("handler",""))')" || return 1
    _timeout="$(printf '%s' "$_record" | "$(_igor_health_python)" -c 'import json,sys; print(json.load(sys.stdin).get("timeout_seconds",30))')" || return 1
    _object="$(printf '%s' "$_record" | "$(_igor_health_python)" -c 'import json,sys; print(json.load(sys.stdin).get("object_id","host:local"))')" || return 1
    _input='{"facts":{}}'
    while IFS=$'\t' read -r _observer _property _class; do
        [ -n "$_observer" ] || continue
        declare -f igor_observer_ensure_fresh >/dev/null 2>&1 &&
            igor_observer_ensure_fresh "$_observer" "$_object" >/dev/null 2>&1 || true
        _fact="$(igor_model_read "$_object" "$_property" "$_class" 2>/dev/null)" || return 1
        _input="$("$(_igor_health_python)" - "$_input" "$_property" "$_fact" <<'PY'
import json, sys
data, prop, fact = json.loads(sys.argv[1]), sys.argv[2], json.loads(sys.argv[3])
data["facts"][prop] = fact
print(json.dumps(data, separators=(",", ":")))
PY
)" || return 1
        _availability="$(printf '%s' "$_fact" | "$(_igor_health_python)" -c 'import json,sys; print(json.load(sys.stdin)["availability"])')" || return 1
        [ "$_availability" = known ] || _missing=1
    done < <(printf '%s' "$_record" | "$(_igor_health_python)" -c '
import json,sys
for ref in json.load(sys.stdin).get("required_facts",[]):
    print("{}\t{}\t{}".format(ref["observer"],ref["property"],ref["state_class"]))
')
    if [ "$_missing" -eq 1 ]; then
        _used="$("$(_igor_health_python)" - "$_input" "$_object" <<'PY'
import json, sys
facts, obj = json.loads(sys.argv[1])["facts"], sys.argv[2]
refs = [{"key": [obj, name, fact["state_class"]], "recorded_at": fact.get("recorded_at"),
         "availability": fact["availability"]} for name, fact in facts.items()]
print(json.dumps(refs, separators=(",", ":")))
PY
)" || return 1
        _igor_health_emit "$(igor_health_result_json "$_id" "$_owner" "$_object" UNKNOWN required_fact_unavailable "Required fact is unavailable" "$_used" '[]' "${_IGOR_CONTRIBUTION_SOURCE[check:${_id}]:-unknown}")"
        return 0
    fi
    if ! _response="$(igor_v2_invoke check "$_id" "$_input" 2>/dev/null)"; then
        _igor_health_emit "$(igor_health_result_json "$_id" "$_owner" "$_object" UNKNOWN check_unavailable "check invocation failed" '[]' '["check_invocation_failed"]' "${_IGOR_CONTRIBUTION_SOURCE[check:${_id}]:-unknown}")"
        return 0
    fi
    # Handler envelope is {status:ok,result:{...}}; unwrap and normalize.
    _normalized="$(printf '%s' "$_response" | "$(_igor_health_python)" -c 'import json,sys; x=json.load(sys.stdin); r=x.get("result",{}); print(json.dumps(r,separators=(",",":")))' 2>/dev/null)" || {
        _igor_health_emit "$(igor_health_result_json "$_id" "$_owner" "$_object" UNKNOWN malformed_result "check returned malformed output" '[]' '["malformed_check_result"]' "${_IGOR_CONTRIBUTION_SOURCE[check:${_id}]:-unknown}")"
        return 0
    }
    if ! igor_health_validate_handler_result "$_id" "$_owner" "$_object" "$_normalized" "$_input" >/dev/null; then
        _igor_health_emit "$(igor_health_result_json "$_id" "$_owner" "$_object" UNKNOWN malformed_result "check returned invalid result" '[]' '["malformed_check_result"]' "${_IGOR_CONTRIBUTION_SOURCE[check:${_id}]:-unknown}")"
        return 0
    fi
    local _stamped; _stamped="$(_igor_health_stamp_json "$_normalized" "$_id" "$_owner" "$_object" "${_IGOR_CONTRIBUTION_SOURCE[check:${_id}]:-unknown}")" || return 1
    _igor_health_emit "$_stamped"
}

_igor_health_stamp_json() {
    local _raw="$1" _id="$2" _owner="$3" _object="$4" _source="${5:-}"
    "$(_igor_health_python)" - "$_raw" "$_id" "$_owner" "$_object" "$_source" <<'PY'
import json,sys
from datetime import datetime,timezone
x=json.loads(sys.argv[1]); x.update(check_id=sys.argv[2], owner=sys.argv[3], object_id=sys.argv[4], source=sys.argv[5], evaluated_at=datetime.now(timezone.utc).isoformat().replace('+00:00','Z')); print(json.dumps(x,separators=(',',':')))
PY
}

igor_health_inspect() {
    if declare -f igor_model_list >/dev/null 2>&1; then
        local _snapshot _id="${1:-}" _object="${2:-}"
        _snapshot="$(igor_model_list)" || return 1
        printf '%s' "$_snapshot" | "$(_igor_health_python)" -c '
import json, sys
data = json.load(sys.stdin)["health"]
check, obj = sys.argv[1:]
if check:
    data = {check: data[check]} if check in data else {}
if obj:
    data = {k: v for k, v in data.items() if v.get("object_id") == obj}
print(json.dumps(data, separators=(",", ":")))
' "$_id" "$_object"
    else
        printf '%s\n' '{}'
    fi
}

igor_health_summary() {
    igor_health_inspect | "$(_igor_health_python)" -c '
import json, sys
results = list(json.load(sys.stdin).values())
statuses = {item.get("status") for item in results}
status = next((candidate for candidate in ("CRITICAL", "FAIL", "WARN", "OK") if candidate in statuses), "UNKNOWN")
print(json.dumps({"status": status, "evaluated_count": sum(item.get("status") in {"OK", "WARN", "FAIL", "CRITICAL"} for item in results),
                  "unknown_count": sum(item.get("status") == "UNKNOWN" for item in results)}, separators=(",", ":")))
'
}

igor_health_memory_check_active() {
    local _key _record
    for _key in "${!_IGOR_CONTRIBUTIONS[@]}"; do
        [[ "$_key" == check:* ]] || continue
        [ "${_IGOR_CONTRIBUTION_STATE[$_key]:-}" = active ] || continue
        _record="${_IGOR_CONTRIBUTIONS[$_key]}"
        printf '%s' "$_record" | "$(_igor_health_python)" -c 'import json,sys; x=json.load(sys.stdin); raise SystemExit(0 if "memory.available_bytes" in json.dumps(x) else 1)' 2>/dev/null && return 0
    done
    return 1
}

# Emit v2 results as presentation-compatible CHECK lines for Diagnose.
igor_health_collect_v2_diagnose() {
    local _json
    while IFS= read -r _json; do
        igor_health_json_to_diagnose "$_json"
    done < <(igor_health_results)
}

# Evaluate active checks in the caller's shell so facts and results remain in
# the process-local System Model after Diagnose or Healing projects them.
igor_health_evaluate_all() {
    local _key _id _tmp
    for _key in "${!_IGOR_CONTRIBUTIONS[@]}"; do
        [[ "$_key" == check:* ]] || continue
        [ "$(igor_contribution_state "$_key")" = active ] || continue
        _id="${_key#check:}"
        _tmp="$(mktemp "${TMPDIR:-/tmp}/igor-health.XXXXXX")" || return 1
        igor_health_run_v2_check "$_id" >"$_tmp" 2>/dev/null || true
        rm -f -- "$_tmp"
    done
}

igor_health_prepare_v2_checks() { igor_health_evaluate_all; }

igor_health_results() {
    igor_health_inspect | "$(_igor_health_python)" -c '
import json, sys
for value in json.load(sys.stdin).values():
    print(json.dumps(value, separators=(",", ":")))
'
}

igor_health_collect_v2_healing() {
    local _json
    while IFS= read -r _json; do
        igor_health_json_to_healing "$_json"
    done < <(igor_health_results)
}

# Normalize a completed legacy pass without running it again. Input is one
# CHECK/CHECK_RESULT line per argument (or stdin when no arguments are given).
igor_health_collect_legacy() {
    local _line
    if [ "$#" -eq 0 ]; then
        while IFS= read -r _line; do
            igor_health_legacy_to_json "$_line" || true
        done
    else
        for _line in "$@"; do
            igor_health_legacy_to_json "$_line" || true
        done
    fi
}

# One active-owner legacy execution pass shared by Diagnose and Healing.
# It returns structured results; each workflow only projects its UI/cache.
igor_health_collect_legacy_results() {
    local _timeout="${1:-60}" _fn _out _line _file _module _owner _source
    if declare -f igor_get_hooks >/dev/null 2>&1; then
        for _fn in $(igor_get_hooks diagnose); do
            declare -f "$_fn" >/dev/null 2>&1 || continue
            _owner="${_IGOR_HOOK_OWNERS[diagnose:${_fn}]:-legacy}"
            _source="hook.${_fn}"
            _out=$(timeout "$_timeout" bash -c "$(declare -f "$_fn"); $_fn" 2>/dev/null)
            while IFS= read -r _line; do
                IGOR_HEALTH_LEGACY_OWNER="$_owner" IGOR_HEALTH_LEGACY_SOURCE="$_source" \
                    igor_health_legacy_to_json "$_line" || true
            done <<<"$_out"
        done
    fi
    local _root="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/modules"
    for _file in "$_root"/*/checks/*.sh; do
        [ -f "$_file" ] || continue
        _module="${_file#"$_root"/}"; _module="${_module%%/*}"
        declare -f igor_has_module >/dev/null 2>&1 && igor_has_module "$_module" || continue
        _source="file.$(basename "$_file" .sh)"
        _out=$(timeout "$_timeout" bash -c 'source "$1" 2>/dev/null || exit 0; declare -f run_check >/dev/null 2>&1 && run_check' _ "$_file" 2>/dev/null)
        while IFS= read -r _line; do
            IGOR_HEALTH_LEGACY_OWNER="$_module" IGOR_HEALTH_LEGACY_SOURCE="$_source" \
                igor_health_legacy_to_json "$_line" || true
        done <<<"$_out"
    done
}

# Temporary line projection for v1 callers that still need the old format.
igor_health_collect_legacy_lines() {
    local _json
    while IFS= read -r _json; do
        igor_health_json_to_diagnose "$_json"
    done < <(igor_health_collect_legacy_results "$@")
}

# Read-only projection helpers used by the two existing user workflows.
igor_health_project_diagnose() {
    local _json
    while IFS= read -r _json; do
        [ -n "$_json" ] && igor_health_json_to_diagnose "$_json"
    done
}

igor_health_project_healing() {
    local _json
    while IFS= read -r _json; do
        [ -n "$_json" ] && igor_health_json_to_healing "$_json"
    done
}
