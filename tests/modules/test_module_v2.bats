#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config"
    # Keep loader output out of assertions unless a test explicitly captures it.
    _ml_log() { :; }
    export -f _ml_log
    source "$REPO_DIR/core/lib/module_loader.sh"
}

teardown() {
    teardown_igor_tmpdir
}

_manifest() {
    local name="$1" api="${2:-2}" runtime="${3:-bash}" compat="${4:-false}" required_modules="${5:-}"
    cat > "$IGOR_DIR/modules/$name/module.conf" <<EOF
[module]
module_api=$api
name=$name
display_name=$name
version=1.0.0
runtime=$runtime
entrypoint=module.sh
contracts=contracts/contract.json

[requirements]
required_modules=$required_modules
optional_modules=
required_capabilities=
optional_capabilities=
platform_families=
required_bins=

[compat]
v1_hooks=$compat
EOF
}

_module() {
    local name="$1" contract="$2" body="${3:-}"
    mkdir -p "$IGOR_DIR/modules/$name/contracts"
    printf '%s\n' "$contract" > "$IGOR_DIR/modules/$name/contracts/contract.json"
    if [ -n "$body" ]; then
        printf '%s\n' "$body" > "$IGOR_DIR/modules/$name/module.sh"
    else
        printf '%s\n' "${name}__register() { :; }" > "$IGOR_DIR/modules/$name/module.sh"
    fi
}

_load() {
    igor_discover_modules >/dev/null
    igor_load_all_modules >/dev/null
}

_restart_loader_state() {
    _IGOR_MODULE_CONFIG_LOADED=0
    _IGOR_MODULE_DIRS=()
    _IGOR_MODULE_API=()
    _IGOR_V2_DATA=()
    _IGOR_MODULE_STATUS=()
    _IGOR_CONTRIBUTIONS=()
    _IGOR_CONTRIBUTION_OWNER=()
    _IGOR_CONTRIBUTION_SOURCE=()
    _IGOR_CONTRIBUTION_STATE=()
    _IGOR_CONTRIBUTION_REASON=()
    _IGOR_LOADED_MODULES=()
}

_basic_contract() {
    printf '%s\n' '{"contract_version":1,"contributions":[]}'
}

@test "valid v2 metadata activates and exposes contribution ownership" {
    local contract='{"contract_version":1,"contributions":[{"kind":"knowledge","id":"demo.basics","path":"knowledge.md"}]}'
    mkdir -p "$IGOR_DIR/modules/demo"
    _manifest demo
    _module demo "$contract"
    printf 'reference data\n' > "$IGOR_DIR/modules/demo/knowledge.md"
    printf 'demo=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status demo)" = active ]
    run igor_contribution_list
    [ "$status" -eq 0 ]
    [[ "$output" == *'knowledge:demo.basics'*$'\t'demo$'\tactive'* ]]
}

@test "configuration declarations are inspectable without enabling value writes" {
    mkdir -p "$IGOR_DIR/modules/config_owner"
    _manifest config_owner
    _module config_owner '{"contract_version":1,"contributions":[{"kind":"configuration","id":"config_owner.preferences","schema":{"schema_version":1,"fields":[{"id":"config_owner.enabled","type":"boolean","scope":"module","default":false}]}}]}'
    printf 'config_owner=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_contribution_state configuration:config_owner.preferences)" = active ]
    run igor_configuration_declarations
    [ "$status" -eq 0 ]
    [[ "$output" == *'"owner":"config_owner"'* ]]
    [[ "$output" == *'"id":"config_owner.enabled"'* ]]
    ! igor_v2_invoke configuration config_owner.preferences '{}'
}

@test "configuration declarations from disabled owners are absent" {
    mkdir -p "$IGOR_DIR/modules/config_disabled"
    _manifest config_disabled
    _module config_disabled '{"contract_version":1,"contributions":[{"kind":"configuration","id":"config_disabled.preferences","schema":{"schema_version":1,"fields":[{"id":"config_disabled.enabled","type":"boolean","scope":"module"}]}}]}'
    printf 'config_disabled=disabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status config_disabled)" = disabled ]
    [ "$(igor_configuration_declarations)" = '[]' ]
}

@test "legacy handler-only configuration contribution remains unavailable" {
    mkdir -p "$IGOR_DIR/modules/config_legacy"
    _manifest config_legacy
    _module config_legacy '{"contract_version":1,"contributions":[{"kind":"configuration","id":"config_legacy.preferences","handler":"config_legacy__validate"}]}' $'config_legacy__register() { :; }\nconfig_legacy__validate() { :; }'
    printf 'config_legacy=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_contribution_state configuration:config_legacy.preferences)" = unavailable ]
    [ "$(igor_contribution_reason configuration:config_legacy.preferences)" = schema_missing ]
    [ "$(igor_configuration_declarations)" = '[]' ]
}

@test "malformed configuration schema fails before module source" {
    mkdir -p "$IGOR_DIR/modules/config_bad"
    _manifest config_bad
    _module config_bad '{"contract_version":1,"contributions":[{"kind":"configuration","id":"config_bad.preferences","schema":{"schema_version":7,"fields":[]}}]}' 'printf sourced > "$IGOR_DIR/sourced"'
    printf 'config_bad=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status config_bad)" = unavailable ]
    [[ "$(igor_module_reason config_bad)" == *'schema is invalid'* ]]
    [ ! -e "$IGOR_DIR/sourced" ]
}

@test "malformed v2 metadata fails before module code is sourced" {
    mkdir -p "$IGOR_DIR/modules/broken"
    _manifest broken
    rm "$IGOR_DIR/modules/broken/contracts/contract.json" 2>/dev/null || true
    printf 'printf sourced > "$IGOR_DIR/sourced"\n' > "$IGOR_DIR/modules/broken/module.sh"
    printf 'broken=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status broken)" = unavailable ]
    [ ! -e "$IGOR_DIR/sourced" ]
    [[ "$(igor_module_reason broken)" == *'contract'* ]]
}

@test "a malformed compatibility entrypoint fails before top-level code runs" {
    mkdir -p "$IGOR_DIR/modules/bad_syntax"
    _manifest bad_syntax 2 bash true
    _module bad_syntax "$(_basic_contract)" $'printf sourced > "$IGOR_DIR/sourced"\nbad_syntax__register() { if'
    printf 'bad_syntax=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status bad_syntax)" = unavailable ]
    [[ "$(igor_module_reason bad_syntax)" == *'Bash syntax'* ]]
    [ ! -e "$IGOR_DIR/sourced" ]
}

@test "unsupported API and runtime are unavailable with precise reasons" {
    mkdir -p "$IGOR_DIR/modules/api3" "$IGOR_DIR/modules/runtime3"
    _manifest api3 3
    _module api3 "$(_basic_contract)"
    _manifest runtime3 2 python
    _module runtime3 "$(_basic_contract)"
    printf 'api3=enabled\nruntime3=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status api3)" = unavailable ]
    [[ "$(igor_module_reason api3)" == *'unsupported'* ]]
    [ "$(igor_module_status runtime3)" = unavailable ]
    [[ "$(igor_module_reason runtime3)" == *'unsupported runtime'* ]]
}

@test "disabled v2 modules are not sourced or indexed" {
    mkdir -p "$IGOR_DIR/modules/disabled"
    _manifest disabled
    _module disabled '{"contract_version":1,"contributions":[{"kind":"knowledge","id":"disabled.data","path":"knowledge.md"}]}' 'printf sourced > "$IGOR_DIR/sourced"'
    printf 'data\n' > "$IGOR_DIR/modules/disabled/knowledge.md"
    printf 'disabled=disabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status disabled)" = disabled ]
    [ ! -e "$IGOR_DIR/sourced" ]
    ! igor_v2_contribution_get knowledge disabled.data
}

@test "a new v2 package without a policy entry stays disabled" {
    mkdir -p "$IGOR_DIR/modules/new_package"
    _manifest new_package
    _module new_package "$(_basic_contract)" 'printf sourced > "$IGOR_DIR/sourced"'

    _load

    [ "$(igor_module_status new_package)" = disabled ]
    [[ "$(igor_module_reason new_package)" == *'explicit enablement required'* ]]
    [ ! -e "$IGOR_DIR/sourced" ]
}

@test "unknown declaration fields and duplicate IDs fail deterministically" {
    mkdir -p "$IGOR_DIR/modules/unknown" "$IGOR_DIR/modules/duplicates"
    _manifest unknown
    _module unknown '{"contract_version":1,"contributions":[{"kind":"knowledge","id":"unknown.data","path":"x","future":true}]}'
    touch "$IGOR_DIR/modules/unknown/x"
    _manifest duplicates
    _module duplicates '{"contract_version":1,"contributions":[{"kind":"knowledge","id":"same.data","path":"x"},{"kind":"knowledge","id":"same.data","path":"x"}]}'
    touch "$IGOR_DIR/modules/duplicates/x"
    printf 'unknown=enabled\nduplicates=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status unknown)" = unavailable ]
    [[ "$(igor_module_reason unknown)" == *'unknown field'* ]]
    [ "$(igor_module_status duplicates)" = unavailable ]
    [[ "$(igor_module_reason duplicates)" == *'duplicate'* ]]
}

@test "path escape is rejected before activation" {
    mkdir -p "$IGOR_DIR/modules/escape"
    _manifest escape
    _module escape '{"contract_version":1,"contributions":[{"kind":"knowledge","id":"escape.data","path":"../outside.md"}]}'
    printf 'escape=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status escape)" = unavailable ]
    [[ "$(igor_module_reason escape)" == *'escapes module package'* ]]
}

@test "missing and disabled hard module providers do not auto-enable dependents" {
    mkdir -p "$IGOR_DIR/modules/missing_dep" "$IGOR_DIR/modules/provider" "$IGOR_DIR/modules/consumer"
    _manifest missing_dep
    _module missing_dep "$(_basic_contract)"
    _manifest provider
    _module provider "$(_basic_contract)"
    _manifest consumer 2 bash false provider
    _module consumer "$(_basic_contract)"
    printf 'provider=disabled\nconsumer=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status provider)" = disabled ]
    [ "$(igor_module_status consumer)" = unavailable ]
    [[ "$(igor_module_reason consumer)" == *'required module provider is disabled'* ]]
    ! igor_module_enabled provider
}

@test "hard module cycles remain unavailable with named dependency edges" {
    mkdir -p "$IGOR_DIR/modules/cycle_a" "$IGOR_DIR/modules/cycle_b"
    _manifest cycle_a 2 bash false cycle_b
    _module cycle_a "$(_basic_contract)"
    _manifest cycle_b 2 bash false cycle_a
    _module cycle_b "$(_basic_contract)"
    printf 'cycle_a=enabled\ncycle_b=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status cycle_a)" = unavailable ]
    [ "$(igor_module_status cycle_b)" = unavailable ]
    [[ "$(igor_module_reason cycle_a)" == *'cycle_b'* ]]
    [[ "$(igor_module_reason cycle_b)" == *'cycle_a'* ]]
}

@test "contribution local requirements withhold only that contribution" {
    mkdir -p "$IGOR_DIR/modules/isolated"
    _manifest isolated
    _module isolated '{"contract_version":1,"contributions":[{"kind":"knowledge","id":"isolated.good","path":"good.md"},{"kind":"observer","id":"isolated.missing_tool","handler":"isolated__observe","output_type":"isolated.data","requires":{"bins":["igor-v2-tool-that-does-not-exist"]}}]}' 'isolated__observe() { printf "{\"status\":\"ok\",\"result\":{}}\n"; }'
    printf 'good\n' > "$IGOR_DIR/modules/isolated/good.md"
    printf 'isolated=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status isolated)" = active ]
    [ "$(igor_contribution_state knowledge:isolated.good)" = active ]
    [ "$(igor_contribution_state observer:isolated.missing_tool)" = unavailable ]
    [[ "$(igor_contribution_list)" == *'required binary igor-v2-tool-that-does-not-exist'* ]]
}

@test "local requirements become available after a later provider activates" {
    mkdir -p "$IGOR_DIR/modules/aconsumer" "$IGOR_DIR/modules/zprovider"
    _manifest aconsumer
    _module aconsumer '{"contract_version":1,"contributions":[{"kind":"knowledge","id":"consumer.info","path":"info.md","requires":{"modules":["zprovider"]}}]}'
    printf 'provider knowledge\n' > "$IGOR_DIR/modules/aconsumer/info.md"
    _manifest zprovider
    _module zprovider "$(_basic_contract)"
    printf 'aconsumer=enabled\nzprovider=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status aconsumer)" = active ]
    [ "$(igor_module_status zprovider)" = active ]
    [ "$(igor_contribution_state knowledge:consumer.info)" = active ]
    [ "$(igor_v2_knowledge consumer.info)" = 'provider knowledge' ]
}

@test "mixed v1 and v2 system knowledge has one canonical v2 contribution" {
    mkdir -p "$IGOR_DIR/modules/system"
    cp -R "$REPO_DIR/modules/system/." "$IGOR_DIR/modules/system/"
    printf 'other=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status system)" = active ]
    [ "$(printf '%s\n' "${_IGOR_CONTRIBUTIONS[@]}" | grep -c 'host.basics')" -eq 1 ]
    [ "$(igor_contribution_state knowledge:host.basics)" = active ]
}

@test "real system v2 slice is invokable and visible through inspection" {
    mkdir -p "$IGOR_DIR/modules/system"
    cp -R "$REPO_DIR/modules/system/." "$IGOR_DIR/modules/system/"
    printf 'system=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    run igor_v2_invoke observer host.memory '{}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"ok"'* ]]
    [[ "$output" == *'available_bytes'* ]]
    run igor_module_list
    [ "$status" -eq 0 ]
    [[ "$output" == *'system'*'api=2'* ]]
    [[ "$output" == *'observer:host.memory'*'owner=system'* ]]
}

@test "system v2 knowledge enters the existing untrusted AI reference envelope" {
    mkdir -p "$IGOR_DIR/modules/system" "$IGOR_DIR/core/lib"
    cp -R "$REPO_DIR/modules/system/." "$IGOR_DIR/modules/system/"
    cp "$REPO_DIR/core/lib/ai_render.py" "$IGOR_DIR/core/lib/ai_render.py"
    cp -R "$REPO_DIR/core/lib/prompts" "$IGOR_DIR/core/lib/prompts"
    printf 'system=enabled\n' > "$IGOR_DIR/config/modules.conf"
    _igor_resolve_dir() { printf '%s/config/%s' "$IGOR_DIR" "$1"; }
    source "$REPO_DIR/core/ai/context.sh"
    _load

    _ai_load_base_prompt '' '' | python3 -c '
import base64, json, sys
raw = sys.stdin.read().split("IGOR_REFERENCE_V1:", 1)[1].splitlines()[0]
reference = json.loads(base64.b64decode(raw))
items = [item for item in reference["context_candidates"] if item["id"] == "host.basics"]
assert len(items) == 1 and items[0]["owner"] == "system"
assert "# Host basics" in items[0]["content"]
assert not reference["module_knowledge"]
'
}

@test "mixed v1 and v2 knowledge is consumed once through the canonical record" {
    mkdir -p "$IGOR_DIR/modules/mixed"
    _manifest mixed 2 bash true
    _module mixed '{"contract_version":1,"contributions":[{"kind":"knowledge","id":"legacy.mixed.ai_knowledge.mixed.ai_knowledge","path":"knowledge.md"}]}' $'mixed__register() { igor_register_hook ai_knowledge mixed__ai_knowledge; }\nmixed__ai_knowledge() { printf "shared knowledge\\n"; }'
    printf 'shared knowledge\n' > "$IGOR_DIR/modules/mixed/knowledge.md"
    printf 'mixed=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    local output count
    output="$(igor_run_all_hooks ai_knowledge; igor_v2_collect_knowledge)"
    count=$(printf '%s\n' "$output" | grep -c '^shared knowledge$' || true)
    [ "$count" -eq 1 ]
}

@test "omitted system policy is migrated once and explicit disable is preserved" {
    mkdir -p "$IGOR_DIR/modules/system"
    cp -R "$REPO_DIR/modules/system/." "$IGOR_DIR/modules/system/"
    printf 'other=enabled\n' > "$IGOR_DIR/config/modules.conf"
    _load
    grep -q '^system=enabled$' "$IGOR_DIR/config/modules.conf"
    [ -f "$IGOR_DIR/config/modules.conf.pre-wave-c.bak" ]
    grep -q '^other=enabled$' "$IGOR_DIR/config/modules.conf.pre-wave-c.bak"
    run grep -q '^system=' "$IGOR_DIR/config/modules.conf.pre-wave-c.bak"
    [ "$status" -ne 0 ]
    [ "$(stat -c %a "$IGOR_DIR/config/modules.conf")" = 600 ]

    igor_discover_modules >/dev/null
    [ "$(grep -c '^system=enabled$' "$IGOR_DIR/config/modules.conf")" -eq 1 ]

    printf 'system=disabled\n' > "$IGOR_DIR/config/modules.conf"
    unset _IGOR_MODULE_CONFIG_LOADED
    _IGOR_MODULE_CONFIG_LOADED=0
    unset '_IGOR_MODULE_STATE[system]'
    unset '_IGOR_MODULE_STATUS[system]'
    igor_discover_modules >/dev/null
    [ "$(grep -c '^system=disabled$' "$IGOR_DIR/config/modules.conf")" -eq 1 ]
    [ "$(igor_module_status system)" = disabled ]
}

@test "failed system policy migration is inspectable and does not source code" {
    mkdir -p "$IGOR_DIR/modules/system"
    cp -R "$REPO_DIR/modules/system/." "$IGOR_DIR/modules/system/"
    _ml_migrate_system_policy() { return 1; }

    _load

    [ "$(igor_module_status system)" = unavailable ]
    [[ "$(igor_module_reason system)" == *'policy migration failed'* ]]
    [ ! -e "$IGOR_DIR/config/modules.conf" ]
    ! igor_has_module system
}

@test "system policy migration refuses a symlinked policy file" {
    mkdir -p "$IGOR_DIR/modules/system"
    cp -R "$REPO_DIR/modules/system/." "$IGOR_DIR/modules/system/"
    printf 'unrelated=enabled\n' > "$IGOR_DIR/target.conf"
    ln -s "$IGOR_DIR/target.conf" "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status system)" = unavailable ]
    [[ "$(igor_module_reason system)" == *'policy migration failed'* ]]
    [ "$(cat "$IGOR_DIR/target.conf")" = 'unrelated=enabled' ]
}

@test "required capability providers do not auto-enable and ambiguous providers fail" {
    mkdir -p "$IGOR_DIR/modules/provider_one" "$IGOR_DIR/modules/provider_two" "$IGOR_DIR/modules/needs_cap"
    _manifest provider_one
    _module provider_one '{"contract_version":1,"contributions":[{"kind":"capability","id":"host.inspect","handler":"provider_one__inspect"}]}' "provider_one__inspect() { printf '{\"status\":\"ok\",\"result\":{}}\\n'; }"
    _manifest provider_two
    _module provider_two '{"contract_version":1,"contributions":[{"kind":"capability","id":"host.inspect","handler":"provider_two__inspect"}]}' "provider_two__inspect() { printf '{\"status\":\"ok\",\"result\":{}}\\n'; }"
    _manifest needs_cap
    sed -i 's/required_capabilities=/required_capabilities=host.inspect/' "$IGOR_DIR/modules/needs_cap/module.conf"
    _module needs_cap "$(_basic_contract)"
    printf 'provider_one=enabled\nprovider_two=enabled\nneeds_cap=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status needs_cap)" = unavailable ]
    [[ "$(igor_module_reason needs_cap)" == *'host.inspect'* ]]
    [ "$(igor_module_status provider_one)" = active ]
    [ "$(igor_module_status provider_two)" = active ]
    [[ "$(igor_module_reason needs_cap)" == *'ambiguous providers'* ]]
}

@test "missing and disabled capability providers fail with provenance" {
    mkdir -p "$IGOR_DIR/modules/cap_provider" "$IGOR_DIR/modules/cap_consumer" "$IGOR_DIR/modules/cap_missing"
    _manifest cap_provider
    _module cap_provider '{"contract_version":1,"contributions":[{"kind":"capability","id":"host.inspect","handler":"cap_provider__inspect"}]}' "cap_provider__inspect() { printf '{\"status\":\"ok\",\"result\":{}}\\n'; }"
    _manifest cap_consumer
    sed -i 's/required_capabilities=/required_capabilities=host.inspect/' "$IGOR_DIR/modules/cap_consumer/module.conf"
    _module cap_consumer "$(_basic_contract)"
    _manifest cap_missing
    sed -i 's/required_capabilities=/required_capabilities=host.absent/' "$IGOR_DIR/modules/cap_missing/module.conf"
    _module cap_missing "$(_basic_contract)"
    printf 'cap_provider=disabled\ncap_consumer=enabled\ncap_missing=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status cap_provider)" = disabled ]
    [ "$(igor_module_status cap_consumer)" = unavailable ]
    [[ "$(igor_module_reason cap_consumer)" == *'provider cap_provider is disabled'* ]]
    [ "$(igor_module_status cap_missing)" = unavailable ]
    [[ "$(igor_module_reason cap_missing)" == *'host.absent has no declared provider'* ]]
    run igor_has_module cap_provider
    [ "$status" -ne 0 ]

    igor_module_set_enabled cap_provider enabled >/dev/null
    _restart_loader_state
    _load
    [ "$(igor_module_status cap_provider)" = active ]
    [ "$(igor_module_status cap_consumer)" = unavailable ]
    [[ "$(igor_module_reason cap_consumer)" == *'contract_incomplete'* ]]
}

@test "metadata-only v2 modules can activate without executable code" {
    mkdir -p "$IGOR_DIR/modules/metadata"
    cat > "$IGOR_DIR/modules/metadata/module.conf" <<'EOF'
[module]
module_api=2
name=metadata
display_name=Metadata
version=1.0.0

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
    printf 'metadata=enabled\n' > "$IGOR_DIR/config/modules.conf"

    _load

    [ "$(igor_module_status metadata)" = active ]
}

@test "contribution platform family gates distinguish Debian, Arch and unknown" {
    mkdir -p "$IGOR_DIR/modules/platform"
    _manifest platform
    _module platform '{"contract_version":1,"contributions":[{"kind":"observer","id":"platform.debian","handler":"platform__observe","output_type":"platform.data","requires":{"platform_families":["debian"]}},{"kind":"observer","id":"platform.arch","handler":"platform__observe","output_type":"platform.data","requires":{"platform_families":["arch"]}}]}' "platform__observe() { printf '{\"status\":\"ok\",\"result\":{}}\\n'; }"
    printf 'platform=enabled\n' > "$IGOR_DIR/config/modules.conf"
    export IGOR_DISTRO_FAMILY=debian
    _load
    [ "$(igor_contribution_state observer:platform.debian)" = active ]
    [ "$(igor_contribution_state observer:platform.arch)" = unavailable ]

    export IGOR_DISTRO_FAMILY=arch
    _restart_loader_state
    _load
    [ "$(igor_contribution_state observer:platform.arch)" = active ]
    [ "$(igor_contribution_state observer:platform.debian)" = unavailable ]

    export IGOR_DISTRO_FAMILY=unknown
    _restart_loader_state
    _load
    [ "$(igor_contribution_state observer:platform.debian)" = unavailable ]
    [ "$(igor_contribution_state observer:platform.arch)" = unavailable ]
}

@test "v1 modules retain omitted enablement and section-blind manifest parsing" {
    mkdir -p "$IGOR_DIR/modules/legacy"
    cat > "$IGOR_DIR/modules/legacy/module.conf" <<'EOF'
[metadata]
name=legacy
display_name=Legacy
version=1.0.0
requires_core=1.0.0
[dependencies]
required_bins=
EOF
    printf 'legacy__register() { :; }\n' > "$IGOR_DIR/modules/legacy/module.sh"

    _load

    [ "$(igor_module_status legacy)" = active ]
    igor_module_enabled legacy
}
