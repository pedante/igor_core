#!/usr/bin/env bats

load '../helpers/common'

setup() {
    setup_igor_tmpdir
    REPO_DIR="${BATS_TEST_DIRNAME}/../.."
}

teardown() {
    teardown_igor_tmpdir
}

@test "mailcmd menu stops when its subsystem is unavailable" {
    # Load only the wrapper, avoiding interactive startup and host operations.
    source <(sed -n '/^menu_mailcmd()/p' "$REPO_DIR/igor.sh")
    _igor_load_subsystem() {
        echo unavailable
        return 1
    }
    run menu_mailcmd
    [ "$status" -eq 1 ]
    [ "$output" = unavailable ]
}

@test "mailcmd heartbeat fails clearly when implementation is absent" {
    # Exercise the real CLI branch in isolation from startup.
    local branch
    branch=$(sed -n '/^            --mailcmd)/,/^            --profile)/p' "$REPO_DIR/igor.sh" | sed '$d')
    run bash -c 'case "$1" in '"$branch"' esac' _ --mailcmd heartbeat
    [ "$status" -eq 1 ]
    [[ "$output" == *"Email control unavailable"* ]]
}

@test "mailcmd heartbeat preserves the poller failure status" {
    mkdir -p "$IGOR_DIR/core/mailcmd"
    touch "$IGOR_DIR/core/mailcmd/core.sh" "$IGOR_DIR/core/mailcmd/service.sh"
    printf 'raise SystemExit(7)\n' > "$IGOR_DIR/core/mailcmd/poller.py"
    local branch
    branch=$(sed -n '/^            --mailcmd)/,/^            --profile)/p' "$REPO_DIR/igor.sh" | sed '$d')
    run bash -c 'case "$1" in '"$branch"' esac' _ --mailcmd heartbeat
    [ "$status" -eq 7 ]
}
