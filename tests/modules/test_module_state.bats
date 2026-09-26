#!/usr/bin/env bats

load '../helpers/common'

setup() {
    setup_igor_tmpdir
    source "${BATS_TEST_DIRNAME}/../../core/lib/module_loader.sh"
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config"
}

teardown() { teardown_igor_tmpdir; }

_module() {
    local name="$1" conf="$2" body="$3"
    mkdir -p "$IGOR_DIR/modules/$name"
    printf 'name=%s\n%s\n' "$name" "$conf" > "$IGOR_DIR/modules/$name/module.conf"
    printf '%s\n' "$body" > "$IGOR_DIR/modules/$name/module.sh"
}

@test "disabled modules remain installed but are not sourced, and required dependents are unavailable" {
    _module base '' 'base__register() { touch "$IGOR_DIR/base-sourced"; }'
    _module app 'required_modules=base' 'app__register() { touch "$IGOR_DIR/app-sourced"; }'
    printf 'base=disabled\n' > "$IGOR_DIR/config/modules.conf"

    igor_load_all_modules

    [ ! -e "$IGOR_DIR/base-sourced" ]
    [ ! -e "$IGOR_DIR/app-sourced" ]
    [ "${_IGOR_MODULE_STATUS[base]}" = disabled ]
    [ "${_IGOR_MODULE_STATUS[app]}" = unavailable ]
    ! igor_has_module base
    ! igor_has_module app
}

@test "module state is parsed once and invalid duplicate entries fail closed" {
    _module demo '' 'demo__register() { :; }'
    printf '# comment\ndemo=enabled\ndemo=invalid\n' > "$IGOR_DIR/config/modules.conf"
    igor_discover_modules >/dev/null
    ! igor_module_enabled demo
    printf 'demo=enabled\n' >> "$IGOR_DIR/config/modules.conf"
    ! igor_module_enabled demo
}

@test "required_modules also controls load order" {
    _module first '' 'first__register() { printf first >> "$IGOR_DIR/order"; }'
    _module second 'required_modules=first' 'second__register() { printf second >> "$IGOR_DIR/order"; }'
    igor_load_all_modules
    [ "$(cat "$IGOR_DIR/order")" = firstsecond ]
}

@test "owner-aware hooks and menus disappear when a loaded module is disabled" {
    _module demo '' 'demo__register() {
        igor_register_hook probe demo__probe
        igor_register_menu_item d Demo subsystem ignored demo__menu
    }
    demo__probe() { :; }
    demo__menu() { :; }'
    printf 'demo=enabled\n' > "$IGOR_DIR/config/modules.conf"
    igor_load_all_modules
    [ "$(igor_get_hooks probe)" = demo__probe ]
    igor_module_set_enabled demo disabled >/dev/null
    [ -z "$(igor_get_hooks probe)" ]
    ! igor_dispatch_menu_item d
}

@test "disabled module cannot contribute to runtime hook paths" {
    _module demo '' 'demo__register() {
        igor_register_hook ai_context demo__ai_context
        igor_register_hook ai_knowledge demo__ai_knowledge
        igor_register_hook ai_tools demo__ai_tools
        igor_register_hook ai_capabilities demo__ai_capabilities
        igor_register_hook config_validate demo__config_validate
        igor_register_hook backup demo__backup
        igor_register_hook restore demo__restore
        igor_register_hook notify_events demo__notify_events
    }
    demo__ai_context() { printf disabled-context; }
    demo__ai_knowledge() { printf disabled-knowledge; }
    demo__ai_tools() { printf disabled-tools; }
    demo__ai_capabilities() { printf "ACTION disabled_action\\nFUNCTION demo__disabled_action\\nTIER READ\\n"; }
    demo__config_validate() { printf disabled-config; }
    demo__backup() { printf disabled-backup; }
    demo__restore() { printf disabled-restore; }
    demo__notify_events() { printf disabled-events; }'
    printf 'demo=enabled\n' > "$IGOR_DIR/config/modules.conf"

    igor_load_all_modules
    [ -n "$(igor_get_hooks ai_context)" ]
    [ -n "$(igor_get_hooks ai_knowledge)" ]
    [ -n "$(igor_get_hooks ai_tools)" ]
    [ -n "$(igor_get_hooks ai_capabilities)" ]
    [ -n "$(igor_get_hooks config_validate)" ]
    [ -n "$(igor_get_hooks backup)" ]
    [ -n "$(igor_get_hooks restore)" ]
    [ -n "$(igor_get_hooks notify_events)" ]

    igor_module_set_enabled demo disabled >/dev/null
    for hook in ai_context ai_knowledge ai_tools ai_capabilities config_validate backup restore notify_events; do
        [ -z "$(igor_get_hooks "$hook")" ]
        run igor_run_all_hooks "$hook"
        [ "$status" -eq 0 ]
        [ -z "$output" ]
    done
}

@test "unavailable required dependency cannot contribute hooks or menus" {
    _module app 'required_modules=missing' 'app__register() {
        igor_register_hook ai_context app__ai_context
        igor_register_menu_item a App module app menu_app
    }
    app__ai_context() { touch "$IGOR_DIR/app-context-ran"; }
    menu_app() { touch "$IGOR_DIR/app-menu-ran"; }'
    igor_load_all_modules

    [ "${_IGOR_MODULE_STATUS[app]}" = unavailable ]
    [ -z "$(igor_get_hooks ai_context)" ]
    run igor_dispatch_menu_item a
    [ "$status" -ne 0 ]
    [ ! -e "$IGOR_DIR/app-context-ran" ]
    [ ! -e "$IGOR_DIR/app-menu-ran" ]
}

@test "failed registration cannot expose its hook" {
    _module broken '' 'broken__register() {
        igor_register_hook probe broken__probe
        return 1
    }
    broken__probe() { :; }'
    igor_load_all_modules
    [ "${_IGOR_MODULE_STATUS[broken]}" = unavailable ]
    [ -z "$(igor_get_hooks probe)" ]
}
