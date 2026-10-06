# Core-owned ephemeral input candidate resolution.
#
# Candidate sources are read-only reference helpers. They cannot execute a
# capability or grant approval/privilege. The chosen value is still submitted
# through the canonical capability dispatcher.

_igor_input_candidate_spec() {
    local _id="${1:-}" _provider="${2:-}" _input="${3:-}" _inspection
    [ "$#" -eq 3 ] && [ -n "$_id" ] && [ -n "$_input" ] || return 2
    declare -f igor_capability_inspect >/dev/null 2>&1 || return 2
    _inspection="$(igor_capability_inspect "$_id" "$_provider")" || return 2
    printf '%s' "$_inspection" | "${IGOR_PYTHON:-python3}" -c '
import json
import sys

input_name, lib_dir = sys.argv[1:]
sys.path.insert(0, lib_dir)
from input_candidates import CandidateError, validate_selector

inspection = json.load(sys.stdin)
if inspection.get("resolution") != "resolved":
    raise SystemExit(2)
provider = inspection.get("selected_provider")
rows = [
    row for row in inspection.get("providers", [])
    if row.get("provider") == provider and row.get("availability") == "active"
]
if len(rows) != 1:
    raise SystemExit(2)
descriptor = rows[0].get("descriptor")
if not isinstance(descriptor, dict):
    raise SystemExit(2)
inputs = descriptor.get("inputs")
properties = inputs.get("properties") if isinstance(inputs, dict) else None
spec = properties.get(input_name) if isinstance(properties, dict) else None
if not isinstance(spec, dict) or "selector" not in spec:
    raise SystemExit(2)
try:
    selector = validate_selector(spec["selector"], input_type=spec.get("type"))
except CandidateError:
    raise SystemExit(2)
print(provider)
print(spec.get("type", ""))
print(json.dumps(selector, sort_keys=True, separators=(",", ":")))
print(selector["resource_kind"])
' "$_input" "${IGOR_DIR}/core/lib"
}

_igor_service_candidate_raw() {
    local _rows
    if ! declare -f svc_list_query >/dev/null 2>&1; then
        # shellcheck source=core/lib/pkg.sh
        source "${IGOR_DIR}/core/lib/pkg.sh"
    fi
    if ! _rows="$(svc_list_query)"; then
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"service enumeration unavailable"}'
        return 0
    fi
    printf '%s\n' "$_rows" | "${IGOR_PYTHON:-python3}" -c '
import json
import re
import sys

rows = []
seen = set()
for raw in sys.stdin:
    parts = raw.rstrip("\n").split("\t")
    if len(parts) < 3:
        continue
    unit, active, sub = parts[:3]
    if (not unit or unit in seen or
            re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.@:+-]*", unit) is None):
        continue
    seen.add(unit)
    rows.append({
        "value": unit,
        "label": unit,
        "detail": f"{active} / {sub}",
        "object_id": f"service:systemd:{unit}",
    })
rows.sort(key=lambda row: row["value"])
rows = rows[:128]
print(json.dumps({
    "state": "ready" if rows else "empty",
    "candidates": rows,
}, sort_keys=True, separators=(",", ":")))
'
}

igor_input_candidates_resolve() {
    local _target="${1:-}" _input="${2:-}" _id _provider="" _spec_text _raw _result
    local _selected_provider _input_type _selector _resource_kind
    local -a _fields=()

    [ "$#" -eq 2 ] && [ -n "$_target" ] && [[ "$_input" =~ ^[a-z][a-z0-9_]*$ ]] || return 2
    _id="${_target%%@*}"
    if [ "$_target" != "$_id" ]; then
        _provider="${_target#*@}"
        [ -n "$_provider" ] && [[ "$_provider" != *@* ]] || return 2
    fi

    _spec_text="$(_igor_input_candidate_spec "$_id" "$_provider" "$_input")" || return 2
    mapfile -t _fields <<< "$_spec_text"
    [ "${#_fields[@]}" -eq 4 ] || return 2
    _selected_provider="${_fields[0]}"
    _input_type="${_fields[1]}"
    _selector="${_fields[2]}"
    _resource_kind="${_fields[3]}"

    case "$_resource_kind" in
        service)
            _raw="$(_igor_service_candidate_raw)" || return 1
            _result="$(printf '%s' "$_raw" | "${IGOR_PYTHON:-python3}"                 "${IGOR_DIR}/core/lib/input_candidates.py" resolve-source                 "$_selector" "$_input_type" platform systemd.services)" || return 1
            ;;
        *)
            _result="$("${IGOR_PYTHON:-python3}"                 "${IGOR_DIR}/core/lib/input_candidates.py" resolve-none                 "$_selector" "$_input_type")" || return 1
            ;;
    esac

    CANDIDATE_RESULT="$_result" CANDIDATE_ID="$_id"     CANDIDATE_PROVIDER="$_selected_provider" CANDIDATE_INPUT="$_input"         "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

print(json.dumps({
    "capability_id": os.environ["CANDIDATE_ID"],
    "provider": os.environ["CANDIDATE_PROVIDER"],
    "input_name": os.environ["CANDIDATE_INPUT"],
    "result": json.loads(os.environ["CANDIDATE_RESULT"]),
}, sort_keys=True, separators=(",", ":")))
PY
}
