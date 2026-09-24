#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
}

teardown() {
    teardown_igor_tmpdir
}

run_storage_check() {
    bash --noprofile --norc -c "
        export IGOR_DIR='${IGOR_DIR}'
        source '${REPO_DIR}/modules/system/checks/storage.sh'
        run_check
    " 2>/dev/null
}

@test "system storage check skips Nextcloud requirements by default" {
    run run_storage_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"CHECK_RESULT OK disk_ok"* || "$output" == *"CHECK_RESULT WARN disk_high"* || "$output" == *"CHECK_RESULT FAIL disk_full"* || "$output" == *"CHECK_RESULT CRITICAL disk_critical"* ]]
    [[ "$output" != *"hd_not_mounted"* ]]
    [[ "$output" != *"nc_data_missing"* ]]
}

@test "explicit Nextcloud storage toggle preserves legacy checks" {
    run bash --noprofile --norc -c "
        export IGOR_NEXTCLOUD_STORAGE_CHECK=true
        source '${REPO_DIR}/modules/system/checks/storage.sh'
        run_check
    " 2>/dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"hd_not_mounted"* ]]
    [[ "$output" == *"nc_data_missing"* ]]
}

@test "loaded Nextcloud module marker enables legacy checks" {
    run bash --noprofile --norc -c "
        export NEXTCLOUD_DOCKER_STACK_DIR='${IGOR_DIR}/config/stacks/nextcloud'
        source '${REPO_DIR}/modules/system/checks/storage.sh'
        run_check
    " 2>/dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"hd_not_mounted"* ]]
    [[ "$output" == *"nc_data_missing"* ]]
}

@test "custom legacy storage paths enable the application checks" {
    local custom_mount="${IGOR_DIR}/external"
    local custom_data="${custom_mount}/next"
    run bash --noprofile --norc -c "
        export HD_MOUNT='${custom_mount}' NC_DATA='${custom_data}'
        source '${REPO_DIR}/modules/system/checks/storage.sh'
        run_check
    " 2>/dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"hd_not_mounted"* ]]
    [[ "$output" == *"${custom_data}"* ]]
}

@test "explicit false toggle suppresses checks even with custom paths" {
    local custom_mount="${IGOR_DIR}/external"
    run bash --noprofile --norc -c "
        export IGOR_NEXTCLOUD_STORAGE_CHECK=false HD_MOUNT='${custom_mount}' NC_DATA='${custom_mount}/next'
        source '${REPO_DIR}/modules/system/checks/storage.sh'
        run_check
    " 2>/dev/null
    [ "$status" -eq 0 ]
    [[ "$output" != *"hd_not_mounted"* ]]
    [[ "$output" != *"nc_data_missing"* ]]
}
