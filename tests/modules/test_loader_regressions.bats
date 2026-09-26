#!/usr/bin/env bats

load '../helpers/common'

setup() {
    setup_igor_tmpdir
    source "${BATS_TEST_DIRNAME}/../../core/lib/module_loader.sh"
    source "${BATS_TEST_DIRNAME}/../../core/lib/config_loader.sh"
    mkdir -p "$IGOR_DIR/modules/example" "$IGOR_DIR/config/variables"
    _IGOR_MODULE_DIRS[example]="$IGOR_DIR/modules/example"
    printf 'name=example\n' > "$IGOR_DIR/modules/example/module.conf"
}

teardown() {
    teardown_igor_tmpdir
}

@test "module configuration paths are relative to the repository root" {
    cat >> "$IGOR_DIR/modules/example/module.conf" <<'CONF'
variables_file=config/variables/example.env
secrets_files=secrets/example.env,secrets/second.env
CONF
    touch "$IGOR_DIR/config/variables/example.env" "$IGOR_DIR/secrets/example.env" "$IGOR_DIR/secrets/second.env"
    igor_validate_module_config example
    rm "$IGOR_DIR/secrets/second.env"
    run igor_validate_module_config example
    [ "$status" -eq 1 ]
    [[ "$output" == *"secrets/second.env"* ]]
}

@test "startup config validation ignores an inactive loaded owner" {
    printf 'variables_file=config/variables/missing.env\n' \
        >> "$IGOR_DIR/modules/example/module.conf"
    _IGOR_LOADED_MODULES[example]=1
    _IGOR_MODULE_STATUS[example]=active

    run _cfg_validate_all_loaded_modules
    [[ "$output" == *"missing.env"* ]]

    _IGOR_MODULE_STATUS[example]=disabled
    run _cfg_validate_all_loaded_modules
    [ "$status" -eq 0 ]
    [[ "$output" != *"missing.env"* ]]
}

@test "a module without registration is not marked loaded" {
    printf 'example__health() { echo ok:ready; }\n' > "$IGOR_DIR/modules/example/module.sh"
    if igor_load_module example; then
        false
    fi
    [ -z "${_IGOR_LOADED_MODULES[example]:-}" ]
}

@test "menu dispatch loads a discovered module and preserves callback status" {
    cat > "$IGOR_DIR/modules/example/module.sh" <<'MODULE'
example__register() { igor_register_hook health example__health; }
example__health() { echo ok:ready; }
menu_example() { return 7; }
MODULE
    _igor_record_recent() { :; }
    _igor_load_module() { return 99; }
    igor_register_menu_item x Example module example menu_example
    local rc=0
    igor_dispatch_menu_item x || rc=$?
    [ "$rc" -eq 7 ]
    [ "${_IGOR_LOADED_MODULES[example]:-}" = 1 ]
}

@test "menu dispatch does not call the menu after a failed legacy load" {
    _igor_record_recent() { :; }
    _igor_load_module() { return 1; }
    menu_example() { touch "$IGOR_DIR/menu-ran"; }
    igor_register_menu_item x Example module legacy_file menu_example
    run igor_dispatch_menu_item x
    [ "$status" -eq 1 ]
    [ ! -e "$IGOR_DIR/menu-ran" ]
}

@test "legacy lazy menu cannot load or run after its owner becomes inactive" {
    _IGOR_LOADED_MODULES[example]=1
    _IGOR_MODULE_STATUS[example]=active
    _IGOR_REGISTERING_MODULE=example
    igor_register_menu_item l Legacy module legacy_file menu_example
    _IGOR_REGISTERING_MODULE=""
    _igor_record_recent() { :; }
    _igor_load_module() { touch "$IGOR_DIR/legacy-loaded"; }
    menu_example() { touch "$IGOR_DIR/menu-ran"; }

    _IGOR_MODULE_STATUS[example]=disabled
    run igor_dispatch_menu_item l
    [ "$status" -eq 1 ]
    [ ! -e "$IGOR_DIR/legacy-loaded" ]
    [ ! -e "$IGOR_DIR/menu-ran" ]

    _IGOR_MODULE_STATUS[example]=unavailable
    run igor_dispatch_menu_item l
    [ "$status" -eq 1 ]
    [ ! -e "$IGOR_DIR/legacy-loaded" ]
}

@test "hook failure reports the original exit status and continues" {
    example__fail() { return 7; }
    example__ok() { echo next-hook-ran; }
    igor_register_hook probe example__fail
    igor_register_hook probe example__ok
    run igor_run_all_hooks probe
    [ "$status" -eq 1 ]
    [[ "$output" == *"exit 7"* ]]
    [[ "$output" == *"next-hook-ran"* ]]
}

@test "extra TUI uses canonical runtime path and honors overrides" {
    source "${BATS_TEST_DIRNAME}/../../core/extras/extra.sh"
    [ "$_EXTRA_RT" = "$IGOR_DIR/data/runtime" ]
    IGOR_RUNTIME_DIR="$IGOR_DIR/custom-runtime"
    source "${BATS_TEST_DIRNAME}/../../core/extras/extra.sh"
    [ "$_EXTRA_RT" = "$IGOR_RUNTIME_DIR" ]
}

@test "capability catalog excludes declared actions without executable implementations" {
    _IGOR_LOADED_MODULES[example]=1
    _IGOR_REGISTERING_MODULE=example
    example__capabilities() {
        cat <<'CAPS'
ACTION available_action
DESCRIPTION callable
FUNCTION example_available_action
TIER READ

ACTION unavailable_action
DESCRIPTION stale declaration
FUNCTION example_missing_action
TIER READ
CAPS
    }
    example_available_action() { :; }
    igor_register_hook ai_capabilities example__capabilities
    _IGOR_REGISTERING_MODULE=""

    igor_load_capabilities
    [ -n "${_IGOR_CAPABILITIES[available_action]:-}" ]
    [ -z "${_IGOR_CAPABILITIES[unavailable_action]:-}" ]
}

@test "capability catalog advertises actions only while their owner is active" {
    _IGOR_LOADED_MODULES[example]=1
    _IGOR_MODULE_STATUS[example]=active
    _IGOR_REGISTERING_MODULE=example
    example__capabilities() {
        cat <<'CAPS'
ACTION owned_action
DESCRIPTION owned action
FUNCTION example_owned_action
TIER READ
CAPS
    }
    example_owned_action() { printf owned; }
    igor_register_hook ai_capabilities example__capabilities
    _IGOR_REGISTERING_MODULE=""

    igor_load_capabilities
    [ -n "${_IGOR_CAPABILITIES[owned_action]:-}" ]
    [ "${_IGOR_CAPABILITY_OWNERS[owned_action]}" = example ]

    _IGOR_MODULE_STATUS[example]=disabled
    igor_load_capabilities
    [ -z "${_IGOR_CAPABILITIES[owned_action]:-}" ]
}

@test "legacy ai_tools prose cannot create an executable catalog action" {
    source "${BATS_TEST_DIRNAME}/../../core/ai/control.sh"
    _IGOR_LOADED_MODULES[example]=1
    _IGOR_MODULE_STATUS[example]=active
    _IGOR_REGISTERING_MODULE=example
    example__ai_tools() {
        printf '[{"name":"prose_only_action","description":"legacy text"}]'
    }
    igor_register_hook ai_tools example__ai_tools
    _IGOR_REGISTERING_MODULE=""
    declare -gA _IGOR_CAPABILITIES=()
    declare -gA _IGOR_CAPABILITY_OWNERS=()

    run ai_catalog_json
    [ "$status" -eq 0 ]
    [[ "$output" != *"prose_only_action"* ]]
    [[ "$output" == *'"actions": []'* ]]
}
