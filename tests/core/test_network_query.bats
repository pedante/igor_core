#!/usr/bin/env bats

load '../helpers/common'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    mkdir -p "$IGOR_DIR/bin"
}

teardown() {
    teardown_igor_tmpdir
}

@test "S7.1 network bridge resolves Core helper from loader root" {
    cat > "$IGOR_DIR/bin/fake-python" <<'EOF'
#!/bin/bash
printf '%s\n' "$*"
EOF
    chmod +x "$IGOR_DIR/bin/fake-python"
    export IGOR_PYTHON="$IGOR_DIR/bin/fake-python"
    export _IGOR_LOADER_DIR="$REPO_DIR"

    source "$REPO_DIR/core/lib/network.sh"

    run network_interfaces_query
    [ "$status" -eq 0 ]
    [ "$output" = "$REPO_DIR/core/lib/network_query.py interfaces" ]

    run network_routes_query
    [ "$status" -eq 0 ]
    [ "$output" = "$REPO_DIR/core/lib/network_query.py routes" ]

    run network_dns_query
    [ "$status" -eq 0 ]
    [ "$output" = "$REPO_DIR/core/lib/network_query.py dns" ]

    run network_snapshot_query
    [ "$status" -eq 0 ]
    [ "$output" = "$REPO_DIR/core/lib/network_query.py snapshot" ]
}

@test "S7.1 network bridge rejects unsupported query kinds" {
    export _IGOR_LOADER_DIR="$REPO_DIR"
    source "$REPO_DIR/core/lib/network.sh"

    run _network_query_run mutate
    [ "$status" -eq 2 ]
}
