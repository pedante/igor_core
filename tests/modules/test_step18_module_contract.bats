#!/usr/bin/env bats

load '../helpers/common'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config"
    cp -a "$REPO_DIR/modules/system" "$IGOR_DIR/modules/system"
    printf 'system=enabled\n' > "$IGOR_DIR/config/modules.conf"
    source "$REPO_DIR/core/lib/module_loader.sh"
    _ml_log() { :; }
    igor_load_all_modules >/dev/null
}

teardown() { teardown_igor_tmpdir; }

@test "system v2 typed result crosses real dispatcher and durable history" {
    source "$REPO_DIR/core/ai/safety.sh"
    _ai_validate_tool_call() { printf 'BLOCKED: false\n'; }
    ai_mode=assist
    run ai_execute_tool '{"tool":"run_capability","id":"system.host.memory.refresh","inputs":{},"capability_version":2}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"output_status":"valid"'* ]]
    [[ "$output" == *'"result":{"observer_id":"host.memory"}'* ]]
    history="$(igor_history_cli recent 1)"
    python3 - "$history" <<'PY'
import json,sys
row=json.loads(sys.argv[1])[0]
assert row["capability"]["version"] == 2
assert row["provider"]["source"]["module_version"] == "2.10.0"
assert row["outcome"] == "success" and row["verification"]["status"] == "passed"
PY
}

@test "mismatched consumer pin fails before admission or provider invocation" {
    source "$REPO_DIR/core/ai/safety.sh"
    _ai_validate_tool_call() { printf 'BLOCKED: false\n'; }
    ai_mode=assist
    run ai_execute_tool '{"tool":"run_capability","id":"system.host.memory.refresh","inputs":{},"capability_version":1}'
    [ "$status" -ne 0 ]
    [ "$(igor_history_cli recent 1)" = '[]' ]
    run igor_capability_plan_resolve '{"plan_version":1,"intended_outcome":"refresh","steps":[{"capability_id":"system.host.memory.refresh","inputs":{},"capability_version":1}]}'
    [ "$status" -ne 0 ]
}

@test "runtime module inspection projects existing facts without another observer" {
    igor_observer_refresh host.memory host:local
    before="$(cat "$IGOR_MODEL_RUNTIME_FILE")"
    run igor_module_inspect system
    [ "$status" -eq 0 ]
    [[ "$output" == *'"runtime_status":"active"'* ]]
    [[ "$output" == *'"capability_version":2'* ]]
    [[ "$output" == *'"memory.available_bytes"'* ]]
    [ "$(cat "$IGOR_MODEL_RUNTIME_FILE")" = "$before" ]
    run igor_module_detach_plan system
    [ "$status" -eq 0 ]
    [[ "$output" == *'"completeness":"incomplete"'* ]]
    [[ "$output" == *'"ready":false'* ]]
    [ "$(cat "$IGOR_MODEL_RUNTIME_FILE")" = "$before" ]
}

@test "static CLI never initializes runtime or migrates omitted system policy" {
    mkdir -p "$IGOR_DIR/core/lib"
    cp "$REPO_DIR/igor.sh" "$IGOR_DIR/igor.sh"
    for script in module_inspection.py module_contract.py capability_runtime.py configuration_schema.py input_candidates.py; do
        cp "$REPO_DIR/core/lib/$script" "$IGOR_DIR/core/lib/$script"
    done
    printf 'touch "$IGOR_DIR/source-marker"\n' >> "$IGOR_DIR/modules/system/module.sh"
    rm -f "$IGOR_DIR/config/modules.conf"
    before_data="$(rg --files --hidden "$IGOR_DIR/data" || true)"
    run bash "$IGOR_DIR/igor.sh" --modules inspect system
    [ "$status" -eq 0 ]
    [[ "$output" == *'migration_pending_unknown'* ]]
    [ ! -e "$IGOR_DIR/source-marker" ]
    [ ! -e "$IGOR_DIR/config/modules.conf" ]
    [ "$(rg --files --hidden "$IGOR_DIR/data" || true)" = "$before_data" ]
    run bash "$IGOR_DIR/igor.sh" --modules detach-plan system
    [ "$status" -eq 0 ]
    [[ "$output" == *'"ready":false'* ]]
    [ ! -e "$IGOR_DIR/config/modules.conf" ]
}

@test "invalid typed CHANGE output retains possible effect and safe History evidence" {
    python3 - "$IGOR_DIR/modules/system" <<'PY'
import json,sys
from pathlib import Path
package=Path(sys.argv[1]); path=package/"contracts/host.json"
data=json.loads(path.read_text())
cap=next(r for r in data["contributions"] if r["kind"]=="capability")
cap.update(id="system.fixture.change",handler="system__fixture_change",safety={"tier":"CHANGE"},
           verification={"kind":"none","required":False},
           outputs={"schema_version":1,"properties":{"count":{"type":"integer"}},"required":["count"],"additionalProperties":False})
path.write_text(json.dumps(data))
with (package/"module.sh").open("a") as stream:
    stream.write('system__fixture_change() { printf X > "$IGOR_DIR/effect-marker"; printf \'%s\\n\' \'{"status":"ok","result":{"count":"REJECTED_SECRET_VALUE"}}\'; }\n')
PY
    # New process is required for updated reviewed package code.
    _change() {
        bash -c '
            source "$1/core/lib/module_loader.sh"
            _ml_log() { :; }
            igor_load_all_modules >/dev/null
            proposal="$(igor_capability_prepare system.fixture.change)" || exit 1
            IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
            IGOR_CAPABILITY_APPROVAL_STATUS=approved
            igor_capability_execute "$proposal"
        ' _ "$REPO_DIR"
    }
    run _change
    [ "$status" -eq 0 ]
    [ -f "$IGOR_DIR/effect-marker" ]
    [[ "$output" == *'"execution_status":"succeeded"'* ]]
    [[ "$output" == *'"output_status":"invalid"'* ]]
    [[ "$output" == *'"verification_status":"unknown"'* ]]
    [[ "$output" == *'"result":null'* ]]
    history="$(igor_history_cli recent 1)"
    [[ "$history" == *'invalid_domain_output'* ]]
    [[ "$history" != *'REJECTED_SECRET_VALUE'* ]]
    [[ "$output" != *'REJECTED_SECRET_VALUE'* ]]
}

@test "v2 privileged declarations remain unavailable without typed Core adapter" {
    python3 - "$IGOR_DIR/modules/system/contracts/host.json" <<'PY'
import json,sys
from pathlib import Path
path=Path(sys.argv[1]); data=json.loads(path.read_text())
cap=next(r for r in data["contributions"] if r["kind"]=="capability")
cap.update(id="system.service.restart",privilege="required")
path.write_text(json.dumps(data))
PY
    run bash -c '
        source "$1/core/lib/module_loader.sh"
        _ml_log() { :; }
        igor_load_all_modules >/dev/null
        igor_capability_inspect system.service.restart
        igor_capability_prepare system.service.restart
    ' _ "$REPO_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *'typed_privileged_output_adapter_unavailable'* ]]
}

@test "memory apply cannot weaken CHANGE, omit verification, or request privilege" {
    local contract="$IGOR_DIR/modules/system/contracts/host.json"
    cp "$contract" "$IGOR_DIR/memory-contract.original.json"
    cat >> "$IGOR_DIR/modules/system/module.sh" <<'EOF'
system__apply_memory_warning() { printf 'effect' > "$IGOR_DIR/memory-apply-effect"; return 1; }
EOF
    local mutation
    for mutation in read-tier no-verifier privilege-required; do
        cp "$IGOR_DIR/memory-contract.original.json" "$contract"
        python3 - "$contract" "$mutation" <<'PY'
import json,sys
from pathlib import Path
path=Path(sys.argv[1]); data=json.loads(path.read_text())
cap=next(row for row in data["contributions"]
         if row.get("id")=="system.memory.warning.apply")
if sys.argv[2]=="read-tier":
    cap["safety"]["tier"]="READ"
elif sys.argv[2]=="no-verifier":
    cap["verification"]={"kind":"none","required":False}
else:
    cap["privilege"]="required"
path.write_text(json.dumps(data))
PY
        run bash -c '
            source "$1/core/lib/module_loader.sh"
            _ml_log() { :; }
            igor_load_all_modules >/dev/null
            [ "$(igor_module_status system)" = active ] || exit 7
            inputs="{\"value\":220,\"revision\":0,\"state\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}"
            if proposal="$(igor_capability_prepare system.memory.warning.apply "$inputs" system 2)"; then
                IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
                igor_capability_execute "$proposal"
                exit 8
            fi
            printf "not-admitted\\n"
        ' _ "$REPO_DIR"
        [ "$status" -eq 0 ]
        [[ "$output" == *not-admitted* ]]
        [ ! -e "$IGOR_DIR/memory-apply-effect" ]
    done
}

@test "retained capability v1 History remains inspectable after current v2 update" {
    proposal="$(igor_capability_prepare system.host.memory.refresh)"
    operation="$(python3 - "$REPO_DIR/core/lib" "$IGOR_DATA_DIR" "$proposal" <<'PY'
import json,sys
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from operational_history import OperationalHistory
p=json.loads(sys.argv[3]); p["capability_version"]=1
service=OperationalHistory(Path(sys.argv[2]))
row=service.prepare(p,correlation_id="old-version",provenance={"interface":"test","actor":"user","request_id":None})
service.authority(row["operation_id"],"approved","not_required")
service.running(row["operation_id"],p)
print(row["operation_id"])
PY
)"
    _igor_capability_verify() { printf X > "$IGOR_DIR/old-verifier-marker"; return 0; }
    run igor_history_recover "$operation"
    [ "$status" -eq 0 ]
    [ ! -e "$IGOR_DIR/old-verifier-marker" ]
    record="$(igor_history_cli inspect "$operation")"
    python3 - "$record" <<'PY'
import json,sys
row=json.loads(sys.argv[1])
assert row["capability"]["version"] == 1
assert row["outcome"] == "interrupted_unknown"
assert row["verification"]["reconciliation"]["status"] == "unavailable"
PY
}
