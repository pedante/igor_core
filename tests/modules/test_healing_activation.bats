#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config"
    printf 'disabled=disabled\n' > "$IGOR_DIR/config/modules.conf"
    source "$REPO_DIR/core/lib/module_loader.sh"
    source "$REPO_DIR/core/lib/diagnose_runner.sh"
    source "$REPO_DIR/core/healing/core.sh"
}

teardown() {
    teardown_igor_tmpdir
}

make_check_module() {
    local name="$1"
    mkdir -p "$IGOR_DIR/modules/$name/checks"
    printf 'name=%s\n' "$name" > "$IGOR_DIR/modules/$name/module.conf"
    printf 'run_check() { echo "CHECK_RESULT OK %s ready"; }\n' "$name" \
        > "$IGOR_DIR/modules/$name/checks/check.sh"
    printf '%s__register() { :; }\n' "$name" \
        > "$IGOR_DIR/modules/$name/module.sh"
}

@test "Healing and Diagnose discover only active module checks" {
    make_check_module active
    make_check_module disabled
    make_check_module installed
    make_check_module unavailable
    printf 'broken_function() { :; }\n' > "$IGOR_DIR/modules/unavailable/module.sh"

    igor_discover_modules >/dev/null
    igor_load_module active >/dev/null
    local load_rc=0
    igor_load_module disabled >/dev/null 2>&1 || load_rc=$?
    [ "$load_rc" -ne 0 ]
    load_rc=0
    igor_load_module unavailable >/dev/null 2>&1 || load_rc=$?
    [ "$load_rc" -ne 0 ]
    [ "${_IGOR_MODULE_STATUS[unavailable]}" = unavailable ]

    _healing_discover_checks >/dev/null
    [ "${#_HEALING_CHECK_FILES[@]}" -eq 1 ]
    [ "${_HEALING_CHECK_FILES[0]}" = "$IGOR_DIR/modules/active/checks/check.sh" ]

    run igor_diagnose_collect --timeout 2
    [ "$status" -eq 0 ]
    [ "$output" = "CHECK:active:ok:ready" ]
}

@test "Healing without an activation authority discovers no installed checks" {
    make_check_module installed
    unset -f igor_has_module
    _healing_discover_checks >/dev/null
    [ "${#_HEALING_CHECK_FILES[@]}" -eq 0 ]
}

@test "generic Healing configuration validation ignores inactive Nextcloud files" {
    mkdir -p "$IGOR_DIR/modules/nextcloud_docker"
    printf 'name=nextcloud_docker\n' > "$IGOR_DIR/modules/nextcloud_docker/module.conf"
    igor_discover_modules >/dev/null
    [ -z "${_IGOR_LOADED_MODULES[nextcloud_docker]:-}" ]

    run validate_configuration
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "active Nextcloud owner retains its configuration validation" {
    mkdir -p "$IGOR_DIR/modules/nextcloud_docker"
    printf 'name=nextcloud_docker\n' > "$IGOR_DIR/modules/nextcloud_docker/module.conf"
    printf 'nextcloud_docker__register() { :; }\n' \
        > "$IGOR_DIR/modules/nextcloud_docker/module.sh"
    igor_discover_modules >/dev/null
    igor_load_module nextcloud_docker >/dev/null

    run validate_configuration
    [ "$status" -eq 0 ]
    [[ "$output" == *"docker-compose.yml not found"* ]]
    [[ "$output" == *"db.env missing"* ]]
}

@test "disabling a loaded Nextcloud owner removes checks and configuration requirements" {
    make_check_module nextcloud_docker
    igor_discover_modules >/dev/null
    igor_load_module nextcloud_docker >/dev/null
    _healing_discover_checks >/dev/null
    [ "${#_HEALING_CHECK_FILES[@]}" -eq 1 ]

    igor_module_set_enabled nextcloud_docker disabled >/dev/null
    _healing_discover_checks >/dev/null
    [ "${#_HEALING_CHECK_FILES[@]}" -eq 0 ]

    run validate_configuration
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
