#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../core/lib/health_runner.sh"
}

@test "structured result retains identity, evidence and timestamp" {
    run igor_health_result_json system.memory system host:local OK memory_ok "Memory is healthy" '["host:local/memory.available_bytes/observed"]' '["/proc/meminfo:MemAvailable"]'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"check_id":"system.memory"'* ]]
    [[ "$output" == *'"used_facts":["host:local/memory.available_bytes/observed"]'* ]]
    [[ "$output" == *'"evaluated_at":'* ]]
}

@test "invalid structured status is rejected" {
    run igor_health_result_json system.memory system host:local green memory_ok ok
    [ "$status" -ne 0 ]
}

@test "legacy CHECK_RESULT is reference data adapter" {
    run igor_health_legacy_to_json 'CHECK_RESULT CRITICAL low_ram Only 40MB available'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"CRITICAL"'* ]]
    [[ "$output" == *'"evidence":["legacy_direct"]'* ]]
    [[ "$output" == *'"owner":"legacy"'* ]]
}

@test "legacy CRITICAL retains owner source and severity through Healing projection" {
    local result
    result=$(IGOR_HEALTH_LEGACY_OWNER=nextcloud_docker IGOR_HEALTH_LEGACY_SOURCE=file.service \
        igor_health_legacy_to_json 'CHECK_RESULT CRITICAL service_down Service is down')
    [[ "$result" == *'"owner":"nextcloud_docker"'* ]]
    [[ "$result" == *'"source":"legacy_direct:file.service"'* ]]
    run igor_health_json_to_healing "$result"
    [ "$output" = 'CHECK_RESULT CRITICAL service_down Service is down' ]
}

@test "structured result projects to Diagnose and Healing formats" {
    local result
    result=$(igor_health_result_json system.memory system host:local WARN memory_low 'Only 120MB available')
    run igor_health_json_to_diagnose "$result"
    [ "$output" = 'CHECK:memory_low:warn:Only 120MB available' ]
    run igor_health_json_to_healing "$result"
    [ "$output" = 'CHECK_RESULT WARN memory_low Only 120MB available' ]
}

@test "malformed v2 result cannot be normalized" {
    run igor_health_validate_handler_result system.memory system host:local '{"status":"OK"}'
    [ "$status" -ne 0 ]
}

@test "empty structured health summary is UNKNOWN" {
    igor_health_inspect() { printf '{}\n'; }
    run igor_health_summary
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"UNKNOWN"'* ]]
    [[ "$output" == *'"evaluated_count":0'* ]]
}
