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
    proposal="$(igor_capability_prepare system.host.runtime.status '{}' system 2)"
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
            printf "%s\n" '''{
              "uptime_seconds":42,
              "load_1":0.25,"load_5":0.5,"load_15":0.75,
              "swap_total_bytes":1048576,"swap_free_bytes":786432,
              "swap_used_bytes":262144,"swap_use_percent":25
            }'''
        }
        printf "%s\n" '''{"api_version":2,"contribution_id":"host.runtime","input":{}}''' |
            system__observe_runtime
        printf "%s\n" '''{"api_version":2,"contribution_id":"system.host.runtime.status","input":{}}''' |
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
                printf "%s\n" '''{
                  "uptime_seconds":"wrong",
                  "load_1":0.25,"load_5":0.5,"load_15":0.75,
                  "swap_total_bytes":1,"swap_free_bytes":1,
                  "swap_used_bytes":0,"swap_use_percent":0
                }'''
            }
            printf "%s\n" '''{"api_version":2,"contribution_id":"host.runtime","input":{}}''' |
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
            printf "%s\n" '''{
              "uptime_seconds":1,"load_1":0,"load_5":0,"load_15":0,
              "swap_total_bytes":0,"swap_free_bytes":0,
              "swap_used_bytes":0,"swap_use_percent":0
            }'''
        }
        printf "%s\n" '''{"api_version":2,"contribution_id":"system.host.runtime.status","input":{}}''' |
            system__host_runtime_status
    ' _ "$REPO_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *MUTATION_CALLED* ]]
}

@test "inactive System owner cannot refresh or prepare S8.1 telemetry" {
    _IGOR_MODULE_STATUS[system]=disabled
    run igor_observer_refresh host.runtime
    [ "$status" -ne 0 ]
    run igor_capability_prepare system.host.runtime.status '{}' system 2
    [ "$status" -ne 0 ]
}
