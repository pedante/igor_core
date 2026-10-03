#!/usr/bin/env bats

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    TEST_ROOT=$(mktemp -d)
    export IGOR_DIR="$TEST_ROOT"
    source "$REPO_DIR/core/ai/scrub.sh"
}

teardown() { rm -rf "$TEST_ROOT"; }

@test "systemd instance units are not scrubbed as email addresses" {
    run _scrub_sensitive_patterns $'user@1000.service\tactive\trunning\nperson@example.com'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'user@1000.service\tactive\trunning'* ]]
    [[ "$output" == *"[IGOR:EMAIL]"* ]]
    [[ "$output" != *$'[IGOR:EMAIL]\tactive\trunning'* ]]
}

@test "container identifiers are not registered as substring scrub mappings" {
    export IGOR_CONTAINER_WEB=man
    export IGOR_CONTAINER_APP="" IGOR_CONTAINER_DB="" IGOR_CONTAINER_CACHE="" IGOR_CONTAINER_CRON=""
    export IGOR_WEB_PORT="" IGOR_PHPFPM_PORT="" IGOR_POSTGRES_PORT="" IGOR_REDIS_PORT="" IGOR_ONLYOFFICE_PORT=""
    ai_scrub_build_table
    local value
    for value in "${SCRUB_FROM[@]}"; do
        [ "$value" != man ]
    done
}
