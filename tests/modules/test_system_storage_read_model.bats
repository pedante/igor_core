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

@test "S4 storage contracts are active read-only System contributions" {
    records="$(igor_contribution_records)"
    python3 - "$records" <<'PY'
import json
import sys

rows = json.loads(sys.argv[1])
by_id = {row["id"]: row for row in rows}
assert by_id["storage.mounts"]["kind"] == "observer"
assert by_id["storage.mounts"]["descriptor"]["object_kind"] == "mount"
assert by_id["storage.filesystems"]["descriptor"]["object_kind"] == "filesystem"
for ident in (
    "system.storage.summary",
    "system.storage.mounts.list",
    "system.storage.filesystems.list",
    "system.storage.mount.status",
    "system.storage.filesystem.status",
):
    row = by_id[ident]
    assert row["kind"] == "capability"
    assert row["descriptor"]["safety"] == {"tier": "READ"}
    assert row["descriptor"]["privilege"] == "none"
assert by_id["system.storage.mount.status"]["descriptor"]["inputs"]["properties"]["mount"]["selector"] == {
    "schema_version": 1, "kind": "resource", "resource_kind": "mount"
}
assert by_id["system.storage.filesystem.status"]["descriptor"]["inputs"]["properties"]["filesystem"]["selector"] == {
    "schema_version": 1, "kind": "resource", "resource_kind": "filesystem"
}
PY
}

@test "mount observer refresh populates canonical multi-object System Model facts" {
    run igor_observer_refresh storage.mounts
    [ "$status" -eq 0 ]

    run igor_model_read mount:/ mount.target observed
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"known"'* ]]
    [[ "$output" == *'"owner":"system"'* ]]
    [[ "$output" == *'"observer":"storage.mounts"'* ]]
    [[ "$output" == *'"value":"/"'* ]]
}

@test "disabled System owner cannot refresh or present prior storage facts as current" {
    igor_observer_refresh storage.mounts >/dev/null
    _IGOR_MODULE_STATUS["system"]=disabled

    run igor_observer_refresh storage.mounts
    [ "$status" -ne 0 ]

    run igor_model_read mount:/ mount.target observed
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"inactive"'* ]]
}

@test "storage summary and status handlers consume only normalized Core rows" {
    run bash -c '
        source "$1/modules/system/module.sh"
        _mod_sys_storage_rows() {
            case "$1" in
                mounts)
                    printf "%s\n" '\''[
                      {"object_id":"mount:/","target":"/","source":"/dev/root","filesystem_type":"ext4",
                       "total_bytes":1000,"used_bytes":420,"available_bytes":500,
                       "use_percent":42,"read_only":false}
                    ]'\''
                    ;;
                filesystems)
                    printf "%s\n" '\''[
                      {"object_id":"filesystem:/dev/root","device":"/dev/root","filesystem_type":"ext4",
                       "uuid":"u-root","label":"root","size_bytes":1000,"mounted":true,"mountpoint":"/"},
                      {"object_id":"filesystem:/dev/sdb1","device":"/dev/sdb1","filesystem_type":"xfs",
                       "uuid":"u-data","label":"data","size_bytes":5000,"mounted":false,"mountpoint":""}
                    ]'\''
                    ;;
            esac
        }
        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.storage.summary","input":{}}'\'' |
            system__storage_summary
        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.storage.mount.status","input":{"mount":"mount:/"}}'\'' |
            system__storage_mount_status
        printf "%s\n" '\''{"api_version":2,"contribution_id":"storage.mounts","input":{}}'\'' |
            system__observe_mounts
    ' _ "$REPO_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"mount_count":1'* ]]
    [[ "$output" == *'"filesystem_count":2'* ]]
    [[ "$output" == *'"unmounted_filesystem_count":1'* ]]
    [[ "$output" == *'"root_use_percent":42'* ]]
    [[ "$output" == *'"object_id":"mount:/"'* ]]
    [[ "$output" == *'"property":"mount.use_percent","value":42'* ]]
}

@test "storage status affected object remains the canonical selected identity" {
    run igor_capability_prepare         system.storage.mount.status '{"mount":"mount:/srv/data"}' system 2
    [ "$status" -eq 0 ]
    [[ "$output" == *'"affected_objects":["mount:/srv/data"]'* ]]

    run igor_capability_prepare         system.storage.filesystem.status '{"filesystem":"filesystem:/dev/sdb1"}' system 2
    if command -v lsblk >/dev/null 2>&1; then
        [ "$status" -eq 0 ]
        [[ "$output" == *'"affected_objects":["filesystem:/dev/sdb1"]'* ]]
    else
        [ "$status" -ne 0 ]
    fi
}

@test "mount selector falls back to bounded platform candidates before observation" {
    source "$REPO_DIR/core/lib/input_candidates.sh"
    storage_mounts_query() {
        printf '%s\n' '[
          {"object_id":"mount:/","target":"/","source":"/dev/root","filesystem_type":"ext4",
           "total_bytes":1000,"used_bytes":420,"available_bytes":500,
           "use_percent":42,"read_only":false},
          {"object_id":"mount:/srv/data","target":"/srv/data","source":"/dev/sdb1","filesystem_type":"xfs",
           "total_bytes":5000,"used_bytes":1000,"available_bytes":3500,
           "use_percent":20,"read_only":false}
        ]'
    }

    run igor_input_candidates_resolve system.storage.mount.status mount
    [ "$status" -eq 0 ]
    [[ "$output" == *'"kind":"platform"'* ]]
    [[ "$output" == *'"value":"mount:/srv/data"'* ]]
    [[ "$output" == *'"label":"/srv/data"'* ]]
}

@test "fresh mount model candidates win over a failing platform fallback" {
    igor_observer_refresh storage.mounts >/dev/null
    source "$REPO_DIR/core/lib/input_candidates.sh"
    storage_mounts_query() {
        printf 'PLATFORM_SHOULD_NOT_RUN\n' >&2
        return 1
    }

    run igor_input_candidates_resolve system.storage.mount.status mount
    [ "$status" -eq 0 ]
    [[ "$output" == *'"kind":"system_model"'* ]]
    [[ "$output" == *'"value":"mount:/"'* ]]
    [[ "$output" != *'PLATFORM_SHOULD_NOT_RUN'* ]]
}

@test "S4 read surface never calls mount umount or sudo" {
    run bash -c '
        source "$1/modules/system/module.sh"
        mount() { printf "MUTATION_CALLED\n"; return 99; }
        umount() { printf "MUTATION_CALLED\n"; return 99; }
        sudo() { printf "MUTATION_CALLED\n"; return 99; }
        _mod_sys_storage_rows() {
            case "$1" in
                mounts) printf "%s\n" "[]" ;;
                filesystems) printf "%s\n" "[]" ;;
            esac
        }
        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.storage.summary","input":{}}'\'' |
            system__storage_summary
    ' _ "$REPO_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *MUTATION_CALLED* ]]
    [[ "$output" == *'"mount_count":0'* ]]
}
