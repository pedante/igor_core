#!/usr/bin/env bats

load '../helpers/common'

setup() {
    setup_igor_tmpdir
    mkdir -p "$IGOR_DIR/module"
    source "$BATS_TEST_DIRNAME/../../core/lib/module_handler.sh"
}

teardown() {
    teardown_igor_tmpdir
}

write_handler() {
    cat > "$IGOR_DIR/module/module.sh" <<'EOF'
system__observe() {
    local request
    IFS= read -r request
    printf '{"status":"ok","result":{"seen":%s}}' "$(python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["input"]))' <<<"$request")"
}
EOF
}

@test "Bash adapter invokes an owner-prefixed handler with the v2 envelope" {
    write_handler
    run _ml_bash_handler_invoke "$IGOR_DIR/module" system system__observe host.memory 5 '{"answer":42}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"ok"'* ]]
    [[ "$output" == *'"answer": 42'* ]]
}

@test "canonical capability bridge skips duplicate Python and syntax validation" {
    write_handler
    local real_python wrapper counter
    real_python="$(command -v python3)"
    wrapper="$IGOR_DIR/counting-python"
    counter="$IGOR_DIR/python-count"
    : > "$counter"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
printf '.\n' >> "$counter"
exec "$real_python" "\$@"
EOF
    chmod 700 "$wrapper"

    V2_HANDLER_SYNTAX_VALIDATED=1 \
    V2_HANDLER_INPUT_CANONICAL=1 \
    V2_HANDLER_DOMAIN_EVENTS=0 \
    V2_HANDLER_DEFER_RESPONSE_VALIDATION=1 \
    IGOR_PYTHON="$wrapper" \
        run _ml_bash_handler_invoke "$IGOR_DIR/module" system system__observe host.memory 5 '{"answer":42}'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"ok"'* ]]
    [ ! -s "$counter" ]
}

@test "canonical capability bridge still fails closed if validated source becomes invalid" {
    cat > "$IGOR_DIR/module/module.sh" <<'EOF'
system__observe() {
    printf '{"status":"ok","result":{}}'
# missing closing brace
EOF
    V2_HANDLER_SYNTAX_VALIDATED=1 \
    V2_HANDLER_INPUT_CANONICAL=1 \
    V2_HANDLER_DOMAIN_EVENTS=0 \
    V2_HANDLER_DEFER_RESPONSE_VALIDATION=1 \
        run _ml_bash_handler_invoke "$IGOR_DIR/module" system system__observe host.memory 5 '{}'
    [ "$status" -ne 0 ]
}

@test "canonical capability bridge still enforces entrypoint containment" {
    write_handler
    printf 'system__observe() { printf "%s\\n" '"'"'{"status":"ok","result":{}}'"'"'; }\n' > "$IGOR_DIR/outside.sh"
    V2_HANDLER_ENTRYPOINT='../outside.sh' \
    V2_HANDLER_SYNTAX_VALIDATED=1 \
    V2_HANDLER_INPUT_CANONICAL=1 \
    V2_HANDLER_DOMAIN_EVENTS=0 \
    V2_HANDLER_DEFER_RESPONSE_VALIDATION=1 \
        run _ml_bash_handler_invoke "$IGOR_DIR/module" system system__observe host.memory 5 '{}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"escapes module package"* ]]
}

@test "Bash adapter rejects a handler outside the owner namespace" {
    write_handler
    run _ml_bash_handler_invoke "$IGOR_DIR/module" system other__observe host.memory 5 '{}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"outside owner"* ]]
}

@test "Bash adapter rejects malformed handler responses" {
    cat > "$IGOR_DIR/module/module.sh" <<'EOF'
system__observe() { printf 'not-json'; }
EOF
    run _ml_bash_handler_invoke "$IGOR_DIR/module" system system__observe host.memory 5 '{}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid JSON response"* ]]
}

@test "Bash adapter fails closed on handler errors and policy fields" {
    cat > "$IGOR_DIR/module/module.sh" <<'EOF'
system__observe() { printf '{"status":"error","error":{"code":"unavailable","message":"sensor missing"}}'; }
EOF
    run _ml_bash_handler_invoke "$IGOR_DIR/module" system system__observe host.memory 5 '{}'
    [ "$status" -ne 0 ]
    [[ "$output" == *'sensor missing'* ]]

    cat > "$IGOR_DIR/module/module.sh" <<'EOF'
system__observe() { printf '{"status":"ok","result":{},"tier":"READ"}'; }
EOF
    run _ml_bash_handler_invoke "$IGOR_DIR/module" system system__observe host.memory 5 '{}'
    [ "$status" -ne 0 ]
}

@test "Bash adapter rejects an entrypoint that escapes the module package" {
    write_handler
    printf 'system__observe() { :; }\n' > "$IGOR_DIR/outside.sh"
    V2_HANDLER_ENTRYPOINT='../outside.sh' \
        run _ml_bash_handler_invoke "$IGOR_DIR/module" system system__observe host.memory 5 '{}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"escapes module package"* ]]
}

@test "Bash adapter rejects a handler that times out" {
    cat > "$IGOR_DIR/module/module.sh" <<'EOF'
system__observe() { sleep 2; printf '{"status":"ok","result":{}}'; }
EOF
    run _ml_bash_handler_invoke "$IGOR_DIR/module" system system__observe host.memory 1 '{}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"timed out"* ]]
}
