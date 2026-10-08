#!/usr/bin/env bats

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

@test "S8.1 host runtime shell bridge returns normalized read-only procfs state" {
    run bash -c '
        export _IGOR_LOADER_DIR="$1"
        source "$1/core/lib/host_runtime.sh"
        host_runtime_status_query
    ' _ "$REPO_DIR"
    [ "$status" -eq 0 ]
    python3 - "$output" <<'PY'
import json,sys
row=json.loads(sys.argv[1])
assert set(row)=={
    "uptime_seconds","load_1","load_5","load_15",
    "swap_total_bytes","swap_free_bytes","swap_used_bytes","swap_use_percent",
}
assert type(row["uptime_seconds"]) is int and row["uptime_seconds"] >= 0
for key in ("load_1","load_5","load_15"):
    assert type(row[key]) in (int,float) and row[key] >= 0
assert 0 <= row["swap_use_percent"] <= 100
assert row["swap_total_bytes"] >= row["swap_used_bytes"] >= 0
assert row["swap_total_bytes"] >= row["swap_free_bytes"] >= 0
PY
}

@test "S8.1 host runtime shell bridge accepts no caller-controlled arguments" {
    run bash -c '
        export _IGOR_LOADER_DIR="$1"
        source "$1/core/lib/host_runtime.sh"
        host_runtime_status_query unexpected
    ' _ "$REPO_DIR"
    [ "$status" -eq 2 ]
}
