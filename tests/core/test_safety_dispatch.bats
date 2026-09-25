#!/usr/bin/env bats

load '../helpers/common'

setup() {
    setup_igor_tmpdir
    stub_ui
    source "${BATS_TEST_DIRNAME}/../../core/ai/safety.sh"
    source "${BATS_TEST_DIRNAME}/../../core/lib/input_validation.sh"
    ai_unscrub_inbound() { printf '%s' "$1"; }
    _ai_validate_tool_call() { echo 'BLOCKED: false'; }
    ai_knowledge_mark_changed() { :; }
    igor_has_capability() { [ "$1" = docker ] || [ "$1" = nextcloud ]; }
    confirm() { echo requested >> "$IGOR_DIR/approvals"; return 1; }
    export executive_mode=false IGOR_QUIET_LOOP=true IGOR_VERBOSE=false
    mkdir -p "$IGOR_DIR/bin"
    cat > "$IGOR_DIR/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$IGOR_DIR/docker-args"
printf 'normal log\nFATAL example\n'
EOF
    chmod +x "$IGOR_DIR/bin/docker"
    export PATH="$IGOR_DIR/bin:$PATH"
    cd "$IGOR_DIR" || return 1
}

teardown() {
    teardown_igor_tmpdir
}

@test "dispatcher rejects JSON key injection before any execution" {
    run ai_execute_tool '{"tool":"reply","message":"ok","x; :>MARKER; #":"unused"}'
    [ "$status" -ne 0 ]
    [ ! -e MARKER ]
    [ ! -e approvals ]
}

@test "dispatcher rejects malformed objects, field types and stale fields" {
    local payload
    for payload in '[]' '{"tool":"host","cmd":{}}' '{"tool":"host"}' \
        '{"tool":"read_log","target":"app","lines":true}' \
        '{"tool":"host","cmd":"cat\u0000 /etc/hosts"}'; do
        T_CMD='printf stale>MARKER'
        run ai_execute_tool "$payload"
        [ "$status" -ne 0 ]
        [ ! -e MARKER ]
    done
}

@test "dispatcher fails closed when its parser cannot run" {
    _AI_INPUT_PARSER="$IGOR_DIR/missing-parser.py"
    run ai_execute_tool '{"tool":"host","cmd":"printf proof>MARKER"}'
    [ "$status" -ne 0 ]
    [ ! -e MARKER ]
    [ ! -e approvals ]
}

@test "module-backed semantic tools require an active capability" {
    igor_has_capability() { return 1; }
    run ai_execute_tool '{"tool":"occ","cmd":"status"}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Capability 'nextcloud' is unavailable"* ]]
    [ ! -e docker-args ]

    run ai_execute_tool '{"tool":"container","action":"restart","target":"app"}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Capability 'docker' is unavailable"* ]]
    [ ! -e docker-args ]
}

@test "capability lookup rejects shell syntax in action names" {
    run ai_execute_tool '{"tool":"run_igor_action","cmd":"$(touch MARKER)"}'
    [ "$status" -ne 0 ]
    [ ! -e MARKER ]
}

@test "registered actions reject inactive owning modules" {
    declare -gA _IGOR_CAPABILITIES=()
    declare -gA _IGOR_CAPABILITY_OWNERS=()
    _IGOR_CAPABILITIES[stale_action]='description|stale_fn||READ||'
    _IGOR_CAPABILITY_OWNERS[stale_action]=disabled_module
    _ml_owner_active() { return 1; }
    run ai_execute_tool '{"tool":"run_igor_action","cmd":"stale_action"}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"owning module is inactive"* ]]
}

@test "reply preserves literal shell-looking text and native metadata" {
    run ai_execute_tool '{"tool":"reply","message":"$(touch MARKER)\nquoted text","status":"INFO","__native_id":"test"}'
    [ "$status" -eq 0 ]
    [[ "$output" == '[REPLY] $(touch MARKER)'* ]]
    [ ! -e MARKER ]
}

@test "read_log rejects target and line-count injections" {
    local payload
    for payload in \
        '{"tool":"read_log","target":"app; :>MARKER","lines":1}' \
        '{"tool":"read_log","target":"app","lines":"1; :>MARKER"}' \
        '{"tool":"read_log","target":"--help","lines":1}' \
        '{"tool":"read_log","target":"app","lines":0}'; do
        run ai_execute_tool "$payload"
        [ "$status" -ne 0 ]
        [ ! -e MARKER ]
        [ ! -e docker-args ]
    done
}

@test "read_log caps lines and filters logs without executing search text" {
    run ai_execute_tool '{"tool":"read_log","target":"app","lines":999,"search":"fatal"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'FATAL example'* ]]
    [[ "$output" != *'normal log'* ]]
    [ "$(cat docker-args)" = $'compose\nlogs\n--tail\n50\napp' ]
    run ai_execute_tool '{"tool":"read_log","target":"app","search":"$(touch MARKER)"}'
    [ ! -e MARKER ]
    [ ! -e approvals ]
}

@test "terminal logs use the configured runtime path" {
    printf 'fixture log\n' > "$IGOR_DIR/data/runtime/terminal.log"
    run ai_execute_tool '{"tool":"read_log","target":"terminal"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'fixture log'* ]]
    [ ! -e docker-args ]
}

@test "OCC rejects shell syntax even when a read substring is present" {
    run ai_execute_tool '{"tool":"occ","cmd":"config:list; :>MARKER"}'
    [ "$status" -ne 0 ]
    [ ! -e MARKER ]
    [ ! -e docker-args ]
}

@test "OCC read arguments retain quoted word boundaries" {
    run ai_execute_tool '{"tool":"occ","cmd":"config:system:get \"key with spaces\""}'
    [ "$status" -eq 0 ]
    [ "$(tail -n 2 docker-args)" = $'config:system:get\nkey with spaces' ]
    [ ! -e approvals ]
}

@test "OCC writes containing read-looking arguments still require approval" {
    run ai_execute_tool '{"tool":"occ","cmd":"config:system:set example --value=config:list"}'
    [ -f approvals ]
    [ ! -e docker-args ]
    run ai_execute_tool '{"tool":"occ","cmd":"maintenance:mode --off"}'
    [ "$(wc -l < approvals)" -eq 2 ]
    [ ! -e docker-args ]
}

@test "container tools reject unsupported actions and shell syntax" {
    local payload
    for payload in '{"tool":"container","action":"down","target":"app"}' \
        '{"tool":"container","action":"restart; :>MARKER","target":"app"}' \
        '{"tool":"container","action":"restart","target":"app; :>MARKER"}'; do
        run ai_execute_tool "$payload"
        [ "$status" -ne 0 ]
        [ ! -e MARKER ]
        [ ! -e docker-args ]
    done
}

@test "approved semantic changes execute argument arrays" {
    confirm() { return 0; }
    run ai_execute_tool '{"tool":"container_action","action":"restart","target":"app"}'
    [ "$status" -eq 0 ]
    [ "$(cat docker-args)" = $'compose\nrestart\napp' ]
}

@test "host and legacy writes with unspaced redirection require approval" {
    run ai_execute_tool '{"tool":"host_command","cmd":"printf proof>MARKER"}'
    [ -f approvals ]
    [ ! -e MARKER ]
    run ai_execute_tool '{"tool":"execute","cmd":"printf proof>MARKER"}'
    [ "$(wc -l < approvals)" -eq 2 ]
    [ ! -e MARKER ]
}

@test "read classifier rejects shell composition, mutating options and unknown commands" {
    local cmd
    for cmd in 'cat /etc/hosts>MARKER' 'cat /etc/hosts; uname' \
        'cat $(printf MARKER)' 'cat `printf MARKER`' 'cat /etc/hosts | tee MARKER' \
        $'uname\nprintf proof>MARKER' 'find . -delete' 'python3 -c "print(1)"' \
        'hostname new-name' 'docker compose config --output MARKER' \
        'docker compose exec -T -u www-data app php occ config:system:set x --value=config:list' \
        'tail -f /tmp/log' 'docker compose logs --follow app' 'docker stats'; do
        run ai_cmd_is_read "$cmd"
        [ "$status" -ne 0 ]
    done
}

@test "approved raw shell commands still execute" {
    confirm() { return 0; }
    run ai_execute_tool '{"tool":"host","cmd":"printf proof>MARKER"}'
    [ "$status" -eq 0 ]
    [ "$(cat MARKER)" = proof ]
}

@test "ordinary read-only host commands run without confirmation" {
    run ai_execute_tool '{"tool":"host","cmd":"docker ps"}'
    [ "$status" -eq 0 ]
    [ "$(cat docker-args)" = ps ]
    [ ! -e approvals ]
}

@test "VLC installation probe runs as a read-only host command" {
    cat > "$IGOR_DIR/bin/which" <<'EOF'
#!/bin/bash
printf '%s\n' /fixture/vlc
EOF
    cat > "$IGOR_DIR/bin/vlc" <<'EOF'
#!/bin/bash
printf 'VLC fixture version\n'
EOF
    chmod +x "$IGOR_DIR/bin/which" "$IGOR_DIR/bin/vlc"
    IGOR_QUIET_LOOP=false
    run ai_execute_tool '{"tool":"host","cmd":"which vlc 2>/dev/null && vlc --version 2>/dev/null | head -2 || echo \"VLC not found in PATH\""}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-RUNNING (read-only)"* ]]
    [[ "$output" == *"VLC fixture version"* ]]
    [ ! -e approvals ]
}

@test "normal package install is CHANGE at the host approval boundary" {
    IGOR_QUIET_LOOP=false
    run ai_execute_tool '{"tool":"host","cmd":"sudo pacman -S --noconfirm vlc"}'
    [[ "$output" == *"NEEDS APPROVAL (modifies system)"* ]]
    [[ "$output" != *"DESTRUCTIVE"* ]]
    [ -e approvals ]
}

@test "report and file readers reject traversal and credential paths" {
    printf 'SAFE REPORT\n' > "$IGOR_DIR/data/reports/safe.txt"
    printf 'SAFE FILE\n' > "$IGOR_DIR/safe.txt"
    run ai_execute_tool '{"tool":"read_report","filename":"../safe.txt"}'
    [ "$status" -ne 0 ]
    run ai_execute_tool '{"tool":"read_file","path":"secrets/site.env"}'
    [[ "$output" == *"[ERROR:"* ]]
    run ai_execute_tool '{"tool":"read_file","path":"safe.txt","lines":2}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'SAFE FILE'* ]]
}

@test "declined dynamic menu proposal does not write a pending item" {
    export items_dir="$IGOR_DIR/items"
    run ai_execute_tool '{"tool":"propose_menu_item","title":"Unsafe item","description":"fixture","command":"touch MARKER","type":"ONE_TIME","tier":"CHANGE"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"USER DECLINED"* ]]
    [ ! -e MARKER ]
    [ ! -d "$items_dir" ] || [ -z "$(find "$items_dir" -type f -print -quit 2>/dev/null)" ]
}

@test "change and destroy tools fail closed on malformed validator output" {
    _ai_validate_tool_call() { printf 'unexpected validator output\n'; }
    confirm() { return 0; }
    run ai_execute_tool '{"tool":"host","cmd":"printf proof>MARKER"}'
    [ "$status" -ne 0 ]
    [ ! -e MARKER ]
    run ai_execute_tool '{"tool":"execute","cmd":"rm -f MARKER"}'
    [ "$status" -ne 0 ]
    [ ! -e MARKER ]
}

@test "central policy can restrict a parsed tool even in executive mode" {
    executive_mode=true
    ai_policy_tool_allowed() { [ "$1" != host ]; }
    run ai_execute_tool '{"tool":"host","cmd":"printf proof>MARKER"}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"not allowed by active AI policy"* ]]
    [ ! -e MARKER ]
}

@test "audit records read success and nonzero exit with operation ids" {
    run ai_execute_tool '{"tool":"host","cmd":"docker ps"}'
    [ "$status" -eq 0 ]
    confirm() { return 0; }
    run ai_execute_tool '{"tool":"host","cmd":"exit 7"}'
    [ "$status" -eq 0 ]
    local audit="$IGOR_DIR/data/runtime/ai-audit.jsonl"
    [ -s "$audit" ]
    grep -q '"event": "RESULT"' "$audit"
    grep -q '"exit_code": "0"' "$audit"
    grep -q '"exit_code": "7"' "$audit"
    [ "$(grep -o '"operation_id": "[^"]*"' "$audit" | sort -u | wc -l)" -ge 2 ]
}

@test "audit records declined operations and does not retain secret literals" {
    export IGOR_AI_AUDIT=sanitized
    local secret='super-secret-fixture'
    ai_scrub_outbound() { sed "s/${secret}/[SCRUBBED]/g"; }
    run ai_execute_tool "{\"tool\":\"host\",\"cmd\":\"printf ${secret}>MARKER\"}"
    [ "$status" -eq 0 ]
    local audit="$IGOR_DIR/data/runtime/ai-audit.jsonl"
    grep -q '"event": "DECLINED"' "$audit"
    ! grep -q "$secret" "$audit"
}

@test "unrestored privacy tokens are blocked at execution boundary" {
    ai_unscrub_inbound() { printf '%s' "$1"; }
    run ai_execute_tool '{"tool":"host","cmd":"curl https://[IGOR:DOMAIN]/health"}'
    [ "$status" -ne 0 ]
    [[ "$output" == *"unresolved privacy token"* ]]
    [ ! -e docker-args ]
}

@test "early read results write canonical metadata" {
    printf 'SAFE REPORT\n' > "$IGOR_DIR/data/reports/safe.txt"
    local meta
    meta=$(mktemp "$IGOR_DIR/data/runtime/.ai-tool-meta.XXXXXX")
    export IGOR_AI_TOOL_META_FILE="$meta"

    run ai_execute_tool '{"tool":"read_report","filename":"safe.txt"}'
    [ "$status" -eq 0 ]
    grep -q '"classification": "READ"' "$meta"
    grep -q '"execution_status": "tool_succeeded"' "$meta"

    run ai_execute_tool '{"tool":"read_report","filename":"missing.txt"}'
    [ "$status" -ne 0 ]
    grep -q '"execution_status": "tool_failed"' "$meta"

    run ai_execute_tool '{"tool":"reply","message":"done","status":"INFO"}'
    [ "$status" -eq 0 ]
    grep -q '"execution_status": "tool_succeeded"' "$meta"
    rm -f "$meta"
}
