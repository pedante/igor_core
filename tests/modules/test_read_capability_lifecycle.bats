#!/usr/bin/env bats

load '../helpers/common'

setup() {
    setup_igor_tmpdir
    export REPO_DIR="${BATS_TEST_DIRNAME}/../.."
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    export FIXTURE_CALLS="$IGOR_DIR/handler-calls"
    export FIXTURE_SOURCES="$IGOR_DIR/module-sources"
    export READ_REQUEST='{"tool":"run_capability","id":"fixture.read","provider":"fixture","inputs":{},"capability_version":2}'
    mkdir -p "$IGOR_DIR/modules/fixture/contracts" "$IGOR_DIR/config"
    ln -s "$REPO_DIR/core" "$IGOR_DIR/core"
    : > "$FIXTURE_CALLS"
    : > "$FIXTURE_SOURCES"
    cat > "$IGOR_DIR/modules/fixture/module.conf" <<'EOF'
[module]
module_api=2
name=fixture
display_name=READ lifecycle fixture
version=1.0.0
runtime=bash
entrypoint=module.sh
contracts=contracts/read.json

[requirements]
required_modules=
optional_modules=
required_capabilities=
optional_capabilities=
platform_families=
required_bins=

[compat]
v1_hooks=false
EOF
    cat > "$IGOR_DIR/modules/fixture/contracts/read.json" <<'EOF'
{"contract_version":1,"contributions":[{"kind":"capability","id":"fixture.read","handler":"fixture__read","capability_version":2,"description":"Read an isolated fixture.","inputs":{"properties":{},"required":[],"additionalProperties":false},"outputs":{"schema_version":1,"properties":{"observed":{"type":"boolean"}},"required":["observed"],"additionalProperties":false},"safety":{"tier":"READ"},"privilege":"none","preconditions":[],"verification":{"kind":"none","required":false},"recovery":{"class":"not_applicable"},"affects":[]}]}
EOF
    cat > "$IGOR_DIR/modules/fixture/module.sh" <<'EOF'
printf 'source\n' >> "$FIXTURE_SOURCES"
fixture__read() {
    printf 'read\n' >> "$FIXTURE_CALLS"
    printf '%s\n' '{"status":"ok","result":{"observed":true}}'
}
EOF
    printf 'fixture=enabled\n' > "$IGOR_DIR/config/modules.conf"
    stub_ui
    source "$REPO_DIR/core/lib/module_loader.sh"
    _ml_log() { :; }
    igor_load_all_modules >/dev/null
    source "$REPO_DIR/core/ai/safety.sh"
    ai_mode=assist
}

teardown() { teardown_igor_tmpdir; }

_fresh_read_session() {
    bash -c '
        source "$REPO_DIR/tests/helpers/common.bash"
        stub_ui
        source "$REPO_DIR/core/lib/module_loader.sh"
        _ml_log() { :; }
        igor_load_all_modules >/dev/null
        igor_capability_list fixture.read > "$IGOR_DIR/fresh-registry.json"
        source "$REPO_DIR/core/ai/safety.sh"
        ai_mode=assist
        ai_execute_tool "$READ_REQUEST"
    '
}

@test "registered READ dispatch refuses disabled owner and recovers in a fresh session" {
    [ "$(igor_module_status fixture)" = active ]
    run ai_execute_tool "$READ_REQUEST"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"success"'* ]]
    [[ "$output" == *'"result":{"observed":true}'* ]]
    [ "$(wc -l < "$FIXTURE_CALLS")" -eq 1 ]
    sources_before="$(wc -l < "$FIXTURE_SOURCES")"
    proposal="$(igor_capability_prepare fixture.read '{}' fixture 2)"
    export IGOR_CAPABILITY_APPROVED_DIGEST
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"

    igor_module_set_enabled fixture disabled >/dev/null
    [ "$(igor_module_status fixture)" = disabled ]
    run ai_execute_tool "$READ_REQUEST"
    [ "$status" -ne 0 ]
    run igor_capability_execute "$proposal"
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$FIXTURE_CALLS")" -eq 1 ]
    run _fresh_read_session
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$FIXTURE_CALLS")" -eq 1 ]
    [ "$(wc -l < "$FIXTURE_SOURCES")" -eq "$sources_before" ]
    [ "$(cat "$IGOR_DIR/fresh-registry.json")" = '[]' ]

    igor_module_set_enabled fixture enabled >/dev/null
    run _fresh_read_session
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"success"'* ]]
    [[ "$output" == *'"result":{"observed":true}'* ]]
    [ "$(wc -l < "$FIXTURE_CALLS")" -eq 2 ]
    python3 - "$IGOR_DIR/fresh-registry.json" "$(igor_history_cli recent 10)" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    records = json.load(stream)
assert len(records) == 1
record = records[0]
assert record["owner"] == record["provider"] == "fixture"
assert record["availability"] == "active"
history = json.loads(sys.argv[2])
assert len(history) == 2
assert all(row["capability"]["id"] == "fixture.read" and
           row["outcome"] == "success" and
           row["approval"]["result"] == "not_required" and
           row["privilege"]["result"] == "not_required" for row in history)
PY
}
