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
    source "$REPO_DIR/core/lib/health_runner.sh"
    _ml_log() { :; }
    igor_load_all_modules >/dev/null
}

teardown() { teardown_igor_tmpdir; }

@test "S8.1 declares one host runtime observer and one typed READ capability" {
    records="$(igor_contribution_records)"
    python3 - "$records" <<'PY'
import json,sys
rows=json.loads(sys.argv[1])
by_id={row["id"]:row for row in rows}
observer=by_id["host.runtime"]
assert observer["kind"]=="observer"
d=observer["descriptor"]
assert d["object_kind"]=="host"
assert d["freshness_seconds"]==15
assert d["privilege"]=="none"
assert {row["name"] for row in d["properties"]}=={
    "runtime.uptime_seconds",
    "load.one_minute","load.five_minute","load.fifteen_minute",
    "swap.total_bytes","swap.free_bytes","swap.used_bytes","swap.use_percent",
}
cap=by_id["system.host.runtime.status"]
assert cap["kind"]=="capability"
assert cap["descriptor"]["capability_version"]==3
assert cap["descriptor"]["outputs"]["schema_version"]==2
check=by_id["host.swap.health"]
assert check["owner"]=="system"
assert check["descriptor"]["required_facts"]==[
    {"property":prop,"state_class":"observed","observer":"host.runtime"}
    for prop in ("swap.total_bytes","swap.free_bytes","swap.used_bytes")
]
assert cap["descriptor"]["safety"]=={"tier":"READ"}
assert cap["descriptor"]["privilege"]=="none"
assert cap["descriptor"]["inputs"]=={
    "properties":{},"required":[],"additionalProperties":False,
}
assert cap["descriptor"]["affects"]==[{"object":"host","id":"local"}]
PY
}

@test "host runtime observer publishes typed host local facts from normalized Core state" {
    run igor_observer_refresh host.runtime
    [ "$status" -eq 0 ]

    run igor_model_read host:local runtime.uptime_seconds observed
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"known"'* ]]
    [[ "$output" == *'"owner":"system"'* ]]
    [[ "$output" == *'"observer":"host.runtime"'* ]]
    [[ "$output" == *'"value_type":"integer"'* ]]

    run igor_model_read host:local load.one_minute observed
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"known"'* ]]
    [[ "$output" == *'"value_type":"number"'* ]]
    [[ "$output" == *'/proc/loadavg'* ]]

    run igor_model_read host:local swap.use_percent observed
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"known"'* ]]
    [[ "$output" == *'"value_type":"integer"'* ]]
    [[ "$output" == *'/proc/meminfo:SwapTotal'* ]]
}

@test "host runtime status returns bounded typed current state" {
    proposal="$(igor_capability_prepare system.host.runtime.status '{}' system 3)"
    [ -n "$proposal" ]
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    IGOR_CAPABILITY_APPROVAL_STATUS=not_required
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"execution_status":"succeeded"'* ]]
    [[ "$output" == *'"output_status":"valid"'* ]]
    [[ "$output" == *'"source":"core.host.runtime"'* ]]
    [[ "$output" == *'"affected_objects":["host:local"]'* ]]
}

@test "System runtime handlers consume only the normalized Core row" {
    run bash -c '
        source "$1/modules/system/module.sh"
        _mod_sys_runtime_read() {
            printf "%s\n" "{\"uptime_seconds\":42,\"load_1\":0.25,\"load_5\":0.5,\"load_15\":0.75,\"swap_total_bytes\":1048576,\"swap_free_bytes\":786432,\"swap_used_bytes\":262144,\"swap_use_percent\":25}"
        }
        printf "%s\n" "{\"api_version\":2,\"contribution_id\":\"host.runtime\",\"input\":{}}" |
            system__observe_runtime
        printf "%s\n" "{\"api_version\":2,\"contribution_id\":\"system.host.runtime.status\",\"input\":{}}" |
            system__host_runtime_status
    ' _ "$REPO_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"property":"runtime.uptime_seconds","value":42'* ]]
    [[ "$output" == *'"property":"swap.use_percent","value":25'* ]]
    [[ "$output" == *'"uptime_seconds":42'* ]]
    [[ "$output" == *'"source":"core.host.runtime"'* ]]
}

@test "malformed normalized runtime data fails closed at typed output or observer validation" {
    _bad_runtime() {
        bash -c '
            source "$1/modules/system/module.sh"
            _mod_sys_runtime_read() {
                printf "%s\n" "{\"uptime_seconds\":\"wrong\",\"load_1\":0.25,\"load_5\":0.5,\"load_15\":0.75,\"swap_total_bytes\":1,\"swap_free_bytes\":1,\"swap_used_bytes\":0,\"swap_use_percent\":0}"
            }
            printf "%s\n" "{\"api_version\":2,\"contribution_id\":\"host.runtime\",\"input\":{}}" |
                system__observe_runtime
        ' _ "$REPO_DIR"
    }
    run _bad_runtime
    [ "$status" -eq 0 ]
    # The handler envelope may be syntactically valid, but the authoritative
    # observer boundary rejects the wrong value type before System Model commit.
    bad="$output"
    igor_v2_invoke() { printf '%s\n' "$bad"; }
    run igor_observer_refresh host.runtime
    [ "$status" -ne 0 ]
    run igor_model_read host:local runtime.uptime_seconds observed
    [[ "$output" == *'"availability":"unknown"'* || "$output" == *'"availability":"not_observed"'* ]]
}

@test "S8.1 has no privilege optional provider or mutation dependency" {
    records="$(igor_contribution_records)"
    python3 - "$records" <<'PY'
import json,sys
rows=json.loads(sys.argv[1])
runtime=[row for row in rows if row["id"] in {
    "host.runtime","system.host.runtime.status",
}]
assert len(runtime)==2
for row in runtime:
    d=row["descriptor"]
    assert d.get("privilege")=="none"
    assert "requires" not in d
if runtime[1]["id"]=="host.runtime":
    runtime.reverse()
assert runtime[1]["descriptor"]["safety"]=={"tier":"READ"}
PY

    run bash -c '
        source "$1/modules/system/module.sh"
        sudo() { printf "MUTATION_CALLED\n"; return 99; }
        nmcli() { printf "MUTATION_CALLED\n"; return 99; }
        timedatectl() { printf "MUTATION_CALLED\n"; return 99; }
        _mod_sys_runtime_read() {
            printf "%s\n" "{\"uptime_seconds\":1,\"load_1\":0,\"load_5\":0,\"load_15\":0,\"swap_total_bytes\":0,\"swap_free_bytes\":0,\"swap_used_bytes\":0,\"swap_use_percent\":0}"
        }
        printf "%s\n" "{\"api_version\":2,\"contribution_id\":\"system.host.runtime.status\",\"input\":{}}" |
            system__host_runtime_status
    ' _ "$REPO_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *MUTATION_CALLED* ]]
}

@test "inactive System owner cannot refresh or prepare S8.1 telemetry" {
    _IGOR_MODULE_STATUS["system"]=disabled
    run igor_observer_refresh host.runtime
    [ "$status" -ne 0 ]
    run igor_capability_prepare system.host.runtime.status '{}' system 3
    [ "$status" -ne 0 ]
}

@test "swap check retains authoritative fact provenance and current READ leaves that snapshot unchanged" {
    igor_health_run_v2_check host.swap.health > "$IGOR_DIR/check.json"
    before="$(cat "$IGOR_MODEL_RUNTIME_FILE")"
    proposal="$(igor_capability_prepare system.host.runtime.status '{}' system 3)"
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    export IGOR_CAPABILITY_APPROVED_DIGEST
    IGOR_CAPABILITY_APPROVAL_STATUS=not_required
    export IGOR_CAPABILITY_APPROVAL_STATUS
    igor_capability_execute "$proposal" > "$IGOR_DIR/current.json"
    [ "$before" = "$(cat "$IGOR_MODEL_RUNTIME_FILE")" ]
    python3 - "$IGOR_DIR/check.json" "$IGOR_DIR/current.json" "$(igor_history_cli recent 10)" <<'PY'
import json,sys
check=json.load(open(sys.argv[1]))
current=json.load(open(sys.argv[2]))
history=json.loads(sys.argv[3])
assert check["owner"]=="system" and check["object_id"]=="host:local"
assert check["check_id"]=="host.swap.health" and check["evaluated_at"]
assert len(check["used_facts"])==3
assert all(ref["availability"]=="known" and ref["recorded_at"] for ref in check["used_facts"])
assert "/proc/meminfo:SwapTotal" in check["evidence"]
assert current["outcome"]=="success" and current["capability_version"]==3
assert current["result"]["observation_scope"]=="current_read"
assert current["result"]["observed_at"]!=check["used_facts"][0]["recorded_at"]
assert len(history)==1 and history[0]["operation_id"]==current["operation_id"]
assert history[0]["capability"]=={"id":"system.host.runtime.status","version":3}
PY
    run igor_capability_prepare system.host.runtime.status '{}' system 2
    [ "$status" -ne 0 ]
}

@test "missing or failed runtime observation produces UNKNOWN with preserved availability and time" {
    original="$(declare -f igor_v2_invoke)"
    igor_v2_invoke() { return 1; }
    igor_health_run_v2_check host.swap.health > "$IGOR_DIR/missing.json"
    eval "$original"
    igor_health_run_v2_check host.swap.health > "$IGOR_DIR/known.json"
    igor_v2_invoke() { return 1; }
    igor_observer_refresh host.runtime || true
    igor_health_run_v2_check host.swap.health > "$IGOR_DIR/stale.json"
    python3 - "$IGOR_DIR" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
missing,known,stale=[json.loads((root/(name+".json")).read_text())
                     for name in ("missing","known","stale")]
assert missing["status"]==stale["status"]=="UNKNOWN"
assert all(ref["availability"]!="known" for ref in missing["used_facts"])
assert all(ref["availability"]=="stale" for ref in stale["used_facts"])
assert [ref["recorded_at"] for ref in known["used_facts"]]==[
    ref["recorded_at"] for ref in stale["used_facts"]]
PY
}

@test "Diagnose and Healing each project one System swap result without legacy swap probes" {
    ln -s "$REPO_DIR/core" "$IGOR_DIR/core"
    export SWAP_FREE_CALLS="$IGOR_DIR/free-calls"
    free() { printf 'legacy\n' >> "$SWAP_FREE_CALLS"; return 1; }
    export -f free
    source "$REPO_DIR/core/lib/diagnose_runner.sh"
    igor_diagnose_collect > "$IGOR_DIR/diagnose.txt"
    [ "$(grep -Ec '^CHECK:swap[^:]*:' "$IGOR_DIR/diagnose.txt")" -eq 1 ]
    [ ! -e "$SWAP_FREE_CALLS" ]
    source "$REPO_DIR/core/healing/core.sh"
    health_check_full silent
    [ "$(grep -Ec '^[A-Z]+ swap[^ ]* ' "$_HEALING_CACHE_FILE")" -eq 1 ]
    [ ! -e "$SWAP_FREE_CALLS" ]
    igor_health_inspect host.swap.health > "$IGOR_DIR/health.json"
    python3 - "$IGOR_DIR/health.json" <<'PY'
import json,sys
check=json.load(open(sys.argv[1]))["host.swap.health"]
assert check["owner"]=="system" and len(check["used_facts"])==3
assert check["source"].endswith("contracts/host.json")
PY
}
