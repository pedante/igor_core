#!/usr/bin/env bats

REPO_DIR="${BATS_TEST_DIRNAME}/../.."
HELPERS="$REPO_DIR/modules/nextcloud_docker/lib/install/helpers.sh"
START_STACK="$REPO_DIR/modules/nextcloud_docker/lib/install/start_stack.sh"
INSTALL_MENU="$REPO_DIR/modules/nextcloud_docker/menus/install.sh"

@test "S9.1 already-accessible Docker performs no cross-module capability call" {
    run bash -c '
        source "$1"
        info() { :; }
        fail() { :; }
        docker() { [ "$1" = info ]; }
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
