#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."
HELPERS="$REPO_DIR/modules/nextcloud_docker/lib/install/helpers.sh"
START_STACK="$REPO_DIR/modules/nextcloud_docker/lib/install/start_stack.sh"
INSTALL_MENU="$REPO_DIR/modules/nextcloud_docker/menus/install.sh"

setup() { setup_igor_tmpdir; }
teardown() { teardown_igor_tmpdir; }

# Load the real System/Docker declarations and Core runtime without AI core.
# All possible host mutations are redirected to fixture executables.
_setup_classic_fixture() {
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    export IGOR_DISTRO_ID=debian IGOR_DISTRO_FAMILY=debian
    export CLASSIC_TRACE="$IGOR_DIR/host-mutations"
    export CLASSIC_ENGINE_STATE="$IGOR_DIR/engine-ready"
    export CLASSIC_COMPOSE_READY=1
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/bin" "$IGOR_DIR/core/lib"
    cp -a "$REPO_DIR/modules/system" "$REPO_DIR/modules/docker" "$IGOR_DIR/modules/"
    cp "$REPO_DIR/core/lib/input_validation.sh" "$IGOR_DIR/core/lib/"
    printf 'system=enabled\ndocker=enabled\n' > "$IGOR_DIR/config/modules.conf"
    cat > "$IGOR_DIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    --version) printf 'Docker version fixture\n' ;;
    info) [ -f "$CLASSIC_ENGINE_STATE" ] || exit 1; printf 'fixture-engine\n' ;;
    compose) [ "$2" = version ] && [ "$CLASSIC_COMPOSE_READY" = 1 ] ;;
    volume) exit 1 ;;
    *) printf 'docker %s\n' "$*" >> "$CLASSIC_TRACE"; exit 99 ;;
esac
EOF
    cat > "$IGOR_DIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$CLASSIC_TRACE"
exit 99
EOF
    cat > "$IGOR_DIR/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >> "$CLASSIC_TRACE"
exit 99
EOF
    cat > "$IGOR_DIR/bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    cat > "$IGOR_DIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    is-active) printf 'inactive\n'; exit 3 ;;
    is-enabled) printf 'disabled\n'; exit 1 ;;
    *) printf 'systemctl %s\n' "$*" >> "$CLASSIC_TRACE"; exit 99 ;;
esac
EOF
    chmod +x "$IGOR_DIR/bin/"*
    export PATH="$IGOR_DIR/bin:$PATH"
    stub_ui
    source "$REPO_DIR/core/lib/module_loader.sh"
    _ml_log() { :; }
    igor_load_all_modules >/dev/null
    cd "$IGOR_DIR" || return 1
}

@test "S9.1 already-accessible Docker performs no cross-module capability call" {
    run bash -c '
        source "$1"
        info() { :; }
        fail() { :; }
        docker() { [ "$1" = info ] || [ "$1 $2" = "compose version" ]; }
        ai_execute_tool() { printf "unexpected-dispatch\n"; return 99; }
        _mod_install_ensure_docker_runtime
    ' _ "$HELPERS"
    [ "$status" -eq 0 ]
    [[ "$output" != *unexpected-dispatch* ]]
}

@test "S9.1 unavailable Docker requests exact canonical docker.install capability" {
    trace="$BATS_TEST_TMPDIR/request.json"
    run env TRACE="$trace" bash -c '
        source "$1"
        info() { :; }
        fail() { printf "FAIL:%s\n" "$*"; }
        DOCKER_READY=0
        docker() {
            [ "$1 $2" = "compose version" ] && return 0
            [ "$1" = info ] || return 2
            [ "$DOCKER_READY" = 1 ]
        }
        ai_execute_tool() {
            printf "%s\n" "$1" > "$TRACE"
            [ "$2" = "Nextcloud requires an installed, enabled, active and reachable Docker Engine." ] || return 3
            DOCKER_READY=1
            return 0
        }
        _mod_install_ensure_docker_runtime
    ' _ "$HELPERS"
    [ "$status" -eq 0 ]
    run python3 - "$trace" <<'PY'
import json,sys
with open(sys.argv[1], encoding="utf-8") as stream:
    request=json.load(stream)
assert request == {
    "tool": "run_capability",
    "id": "docker.install",
    "provider": "docker",
    "inputs": {},
    "capability_version": 1,
}
PY
    [ "$status" -eq 0 ]
}

@test "Engine-ready Compose-missing reports the distinct prerequisite without dispatch" {
    run bash -c '
        source "$1"
        info() { printf "INFO:%s\n" "$*"; }
        fail() { printf "FAIL:%s\n" "$*"; }
        docker() { [ "$1" = info ]; }
        ai_execute_tool() { printf "unexpected-dispatch\n"; return 99; }
        _mod_install_ensure_docker_runtime
    ' _ "$HELPERS"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Docker Engine is accessible, but Docker Compose is unavailable"* ]]
    [[ "$output" != *unexpected-dispatch* ]]
    [[ "$output" != *"Engine is unavailable"* ]]
}

@test "Engine setup success still requires the separate Compose prerequisite" {
    run bash -c '
        source "$1"
        info() { printf "INFO:%s\n" "$*"; }
        fail() { printf "FAIL:%s\n" "$*"; }
        DOCKER_READY=0
        docker() { [ "$1" = info ] && [ "$DOCKER_READY" = 1 ]; }
        ai_execute_tool() { DOCKER_READY=1; }
        _mod_install_ensure_docker_runtime
    ' _ "$HELPERS"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Docker Engine is unavailable"* ]]
    [[ "$output" == *"Docker Engine is accessible, but Docker Compose is unavailable"* ]]
}

@test "classic installation initializes canonical dispatch without AI and decline mutates no host state" {
    _setup_classic_fixture
    source "$INSTALL_MENU"
    run declare -F ai_execute_tool
    [ "$status" -ne 0 ]
    run declare -F _nexus_api_call
    [ "$status" -ne 0 ]
    _mod_install_load_tier() { :; }
    header() { :; }
    pause() { :; }
    confirm() { return 0; }
    fail() { printf 'FAIL:%s\n' "$*"; }
    _mod_install_ensure_secrets() { printf 'secrets\n' >> "$CLASSIC_TRACE"; }
    _mod_install_wipe_docker_state() { printf 'wipe\n' >> "$CLASSIC_TRACE"; }
    _mod_install_handle_existing_data() { printf 'data\n' >> "$CLASSIC_TRACE"; }
    export COMPOSE_FILE="$IGOR_DIR/docker-compose.yml"
    printf 'services: {}\n' > "$COMPOSE_FILE"
    printf 'existing-secret\n' > "$IGOR_DIR/secrets/db.env"
    ai_mode=assist
    _classic_decline() {
        local rc=0
        menu_install < <(printf 'n\n') || rc=$?
        declare -f ai_execute_tool >/dev/null 2>&1 || return 98
        ! declare -f _nexus_api_call >/dev/null 2>&1 || return 99
        printf 'canonical-dispatcher-loaded\n'
        return "$rc"
    }
    run _classic_decline
    [ "$status" -eq 1 ]
    [[ "$output" == *canonical-dispatcher-loaded* ]]
    [[ "$output" == *"system.package.install"* ]]
    [[ "$output" == *'"stopped_reason":"approval_denied"'* ]]
    [[ "$output" == *'"execution_status":"not_executed"'* ]]
    [[ "$output" == *"Docker setup was not completed through the canonical capability path"* ]]
    [ ! -s "$CLASSIC_TRACE" ]
    [ ! -e "$CLASSIC_ENGINE_STATE" ]
    [ "$(cat "$IGOR_DIR/secrets/db.env")" = existing-secret ]
}

@test "dispatcher initialized without AI executes a canonical READ and retains its session state on reuse" {
    _setup_classic_fixture
    _igor_capability_load_dispatcher
    AI_CMD_READ=7
    _igor_capability_load_dispatcher
    [ "$AI_CMD_READ" -eq 7 ]
    run declare -F _nexus_api_call
    [ "$status" -ne 0 ]
    run ai_execute_tool '{"tool":"run_capability","id":"docker.status","provider":"docker","inputs":{},"capability_version":2}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"success"'* ]]
    [[ "$output" == *'"daemon_accessible":false'* ]]
    [ ! -s "$CLASSIC_TRACE" ]
}

@test "dispatcher initialization preserves fail-closed validation when its deterministic validator is missing" {
    _setup_classic_fixture
    _igor_capability_load_dispatcher
    _AI_SAFETY_DIR="$IGOR_DIR/missing-validator"
    _blocked_dispatch() {
        local rc=0
        ai_execute_tool '{"tool":"run_capability","id":"system.package.install","provider":"system","inputs":{"package":"docker.io"},"capability_version":1}' || rc=$?
        printf '%s\n' "$IGOR_CAPABILITY_LAST_RESULT"
        return "$rc"
    }
    run _blocked_dispatch
    [ "$status" -ne 0 ]
    [[ "$output" == *'"outcome":"validation_blocked"'* ]]
    [[ "$output" == *'"execution_status":"not_executed"'* ]]
    [ ! -s "$CLASSIC_TRACE" ]
    [ ! -e "$CLASSIC_ENGINE_STATE" ]
}

@test "Compose-missing classic setup paths stop before configuration, credentials or stack mutation" {
    _setup_classic_fixture
    : > "$CLASSIC_ENGINE_STATE"
    export CLASSIC_COMPOSE_READY=0
    source "$INSTALL_MENU"
    _mod_install_load_tier() { :; }
    header() { :; }
    breadcrumb() { :; }
    pause() { :; }
    confirm() { return 0; }
    fail() { printf 'FAIL:%s\n' "$*"; }
    _mod_install_ensure_secrets() { printf 'secrets\n' >> "$CLASSIC_TRACE"; }
    _mod_install_wipe_docker_state() { printf 'wipe\n' >> "$CLASSIC_TRACE"; }
    _mod_install_handle_existing_data() { printf 'data\n' >> "$CLASSIC_TRACE"; }
    nextcloud_docker__compose() { printf 'compose %s\n' "$*" >> "$CLASSIC_TRACE"; }
    export COMPOSE_FILE="$IGOR_DIR/docker-compose.yml"
    printf 'services: {}\n' > "$COMPOSE_FILE"
    printf 'existing-secret\n' > "$IGOR_DIR/secrets/db.env"
    run menu_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"Docker Engine is accessible, but Docker Compose is unavailable"* ]]
    run _mod_setup_start_stack
    [ "$status" -eq 1 ]
    [[ "$output" == *"Docker Engine is accessible, but Docker Compose is unavailable"* ]]
    [ ! -s "$CLASSIC_TRACE" ]
    [ ! -e ./config.env ]
    [ "$(cat "$IGOR_DIR/secrets/db.env")" = existing-secret ]
}

@test "missing canonical dispatcher remains fail-closed without raw host fallback" {
    trace="$BATS_TEST_TMPDIR/unavailable-authority"
    run env TRACE="$trace" bash -c '
        source "$1"
        info() { :; }
        fail() { printf "FAIL:%s\n" "$*"; }
        docker() { return 1; }
        sudo() { printf "sudo:%s\n" "$*" >> "$TRACE"; }
        pkg_install_docker_post() { printf "legacy-pkg\n" >> "$TRACE"; }
        _mod_install_ensure_docker_runtime
    ' _ "$HELPERS"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Canonical capability dispatcher is unavailable"* ]]
    [ ! -s "$trace" ]
}

@test "S9.1 unavailable or declined canonical provider does not regain raw host authority" {
    trace="$BATS_TEST_TMPDIR/raw-authority"
    run env TRACE="$trace" bash -c '
        source "$1"
        info() { :; }
        fail() { :; }
        docker() { return 1; }
        ai_execute_tool() { return 1; }
        sudo() { printf "sudo:%s\n" "$*" >> "$TRACE"; return 0; }
        pkg_install_docker_post() { printf "legacy-pkg\n" >> "$TRACE"; return 0; }
        _mod_install_ensure_docker_runtime
    ' _ "$HELPERS"
    [ "$status" -ne 0 ]
    [ ! -s "$trace" ]
}

@test "S9.1 canonical success is not enough if Docker remains inaccessible" {
    run bash -c '
        source "$1"
        info() { :; }
        fail() { :; }
        docker() { return 1; }
        ai_execute_tool() { return 0; }
        _mod_install_ensure_docker_runtime
    ' _ "$HELPERS"
    [ "$status" -ne 0 ]
}

@test "migrated Nextcloud prerequisite paths contain no raw Docker service recovery" {
    run python3 - "$START_STACK" "$INSTALL_MENU" <<'PY'
from pathlib import Path
import sys
for raw in sys.argv[1:]:
    data=Path(raw).read_text(encoding="utf-8")
    assert "pkg_install_docker_post" not in data
    assert "systemctl enable docker" not in data
    assert "systemctl start  docker" not in data
    assert "_mod_install_ensure_docker_runtime" in data
PY
    [ "$status" -eq 0 ]
}

@test "docker.install remains a data-only composition of canonical System host capabilities" {
    run python3 - "$REPO_DIR/modules/docker/contracts/docker.json" <<'PY'
import json,sys
with open(sys.argv[1], encoding="utf-8") as stream:
    contract=json.load(stream)
cap=next(row for row in contract["contributions"] if row.get("id")=="docker.install")
assert cap["implementation"]["kind"]=="composition"
assert cap["requires"]["capabilities"]==[
    "system.package.install",
    "system.service.enable",
    "system.service.start",
]
for variant in cap["implementation"]["variants"]:
    assert [step["capability_id"] for step in variant["steps"]]==[
        "system.package.install",
        "system.service.enable",
        "system.service.start",
    ]
assert cap["implementation"]["final_check"]["capability_id"]=="docker.status"
PY
    [ "$status" -eq 0 ]
}
