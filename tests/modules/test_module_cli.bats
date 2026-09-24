#!/usr/bin/env bats

load '../helpers/common'

setup() {
    setup_igor_tmpdir
    local root="${BATS_TEST_DIRNAME}/../.."
    mkdir -p "$IGOR_DIR/core/lib" "$IGOR_DIR/modules/example" "$IGOR_DIR/config"
    cp "$root/igor.sh" "$IGOR_DIR/igor.sh"
    cp "$root/core/lib/module_loader.sh" "$IGOR_DIR/core/lib/module_loader.sh"
    printf 'name=example\n' > "$IGOR_DIR/modules/example/module.conf"
    # Management must run before any operational startup code is sourced.
    printf 'touch "%s/module-sourced"\n' "$IGOR_DIR" > "$IGOR_DIR/modules/example/module.sh"
}

teardown() {
    teardown_igor_tmpdir
}

@test "disable and enable CLI retain module files and do not source them" {
    run bash "$IGOR_DIR/igor.sh" --disable example
    [ "$status" -eq 0 ]
    [ -f "$IGOR_DIR/modules/example/module.sh" ]
    [ ! -e "$IGOR_DIR/module-sourced" ]
    grep -q '^example=disabled$' "$IGOR_DIR/config/modules.conf"

    run bash "$IGOR_DIR/igor.sh" --enable example
    [ "$status" -eq 0 ]
    [ ! -e "$IGOR_DIR/module-sourced" ]
    grep -q '^example=enabled$' "$IGOR_DIR/config/modules.conf"
}

@test "module policy CLI rejects missing names and unknown modules" {
    run bash "$IGOR_DIR/igor.sh" --disable
    [ "$status" -ne 0 ]
    run bash "$IGOR_DIR/igor.sh" --enable nonexistent
    [ "$status" -ne 0 ]
    [ ! -e "$IGOR_DIR/module-sourced" ]
}
