#!/usr/bin/env bats

load '../helpers/common'
load '../helpers/system_admin'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

@test "generic package install freezes alias-resolved argv and verifies installed state" {
    run igor_capability_prepare system.package.install '{"package":"pkg_docker"}' system 1
    [ "$status" -eq 0 ]
    proposal="$output"
    [[ "$proposal" == *'"privileged_argv":["sudo","-n","--","apt-get","install","-y","docker.io"]'* ]]
    IGOR_CAPABILITY_APPROVED_DIGEST="$(printf '%s' "$proposal" | python3 -c 'import json,sys;print(json.load(sys.stdin)["digest"])')"
    IGOR_CAPABILITY_APPROVAL_STATUS=approved
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"execution_status":"succeeded"'* ]]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    [[ "$output" == *'"check_id":"system.package.installed"'* ]]
    [ -e "$ADMIN_PACKAGE_STATE" ]
}

@test "generic service enable and start use reviewed argv and deterministic verification" {
    run igor_capability_prepare system.service.enable '{"unit":"docker.service"}' system 1
    [ "$status" -eq 0 ]
    proposal="$output"
    [[ "$proposal" == *'"privileged_argv":["sudo","-n","--","systemctl","enable","docker.service"]'* ]]
    IGOR_CAPABILITY_APPROVED_DIGEST="$(printf '%s' "$proposal" | python3 -c 'import json,sys;print(json.load(sys.stdin)["digest"])')"
    IGOR_CAPABILITY_APPROVAL_STATUS=approved
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    [[ "$output" == *'"check_id":"system.service.enabled"'* ]]
    [ -e "$ADMIN_DOCKER_ENABLED" ]

    run igor_capability_prepare system.service.start '{"unit":"docker.service"}' system 1
    [ "$status" -eq 0 ]
    proposal="$output"
    [[ "$proposal" == *'"privileged_argv":["sudo","-n","--","systemctl","start","docker.service"]'* ]]
    IGOR_CAPABILITY_APPROVED_DIGEST="$(printf '%s' "$proposal" | python3 -c 'import json,sys;print(json.load(sys.stdin)["digest"])')"
    export IGOR_CAPABILITY_APPROVED_DIGEST
    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    [[ "$output" == *'"expected":"active"'* ]]
    [ -e "$ADMIN_DOCKER_ACTIVE" ]
}

@test "Docker install composite capability resolves a frozen platform plan without executing" {
    before_trace="$(cat "$ADMIN_PRIVILEGE_TRACE")"
    run igor_capability_prepare docker.install '{}' docker 1
    if [ "$status" -ne 0 ]; then
        printf '# docker.install prepare failed: %s\n' "$output" >&3
        false
    fi
    proposal="$output"
    python3 - "$proposal" <<'PY'
import json,sys
proposal=json.loads(sys.argv[1])
plan=proposal["composition_plan"]
assert proposal["capability_id"]=="docker.install"
assert proposal["provider"]=="docker"
assert plan["intended_outcome"].startswith("Docker Engine is installed")
assert [step["capability_id"] for step in plan["steps"]]==[
    "system.package.install","system.service.enable","system.service.start"]
assert plan["steps"][0]["inputs"]=={"package":"docker.io"}
assert plan["steps"][0]["provider"]=="system"
assert plan["steps"][1]["inputs"]=={"unit":"docker.service"}
assert plan["steps"][2]["inputs"]=={"unit":"docker.service"}
assert all(step["inspection"]["resolution"]["status"]=="available" for step in plan["steps"])
assert plan["final_check"]["capability_id"]=="docker.status"
assert plan["final_check"]["expect"]=={"installed":True,"daemon_accessible":True}
assert plan["final_check"]["provider"]=="docker"
assert plan.get("digest")
PY
    [ "$(cat "$ADMIN_PRIVILEGE_TRACE")" = "$before_trace" ]
    [ ! -e "$ADMIN_PACKAGE_STATE" ]
    [ ! -e "$ADMIN_DOCKER_ENABLED" ]
    [ ! -e "$ADMIN_DOCKER_ACTIVE" ]
}

@test "Docker install composite becomes unavailable when a required child capability is unavailable" {
    _IGOR_CONTRIBUTION_STATE["capability:system.service.start"]="unavailable"
    _IGOR_CONTRIBUTION_REASON["capability:system.service.start"]="fixture_missing"
    run igor_capability_prepare docker.install '{}' docker 1
    [ "$status" -ne 0 ]
    [ ! -e "$ADMIN_PACKAGE_STATE" ]
    [ ! -e "$ADMIN_DOCKER_ENABLED" ]
    [ ! -e "$ADMIN_DOCKER_ACTIVE" ]
}

@test "composition stays inside the capability contract rather than a second plan registry" {
    records="$(igor_contribution_records)"
    python3 - "$records" <<'PY'
import json,sys
rows=json.loads(sys.argv[1])
assert not any(row.get("kind")=="plan" for row in rows)
install=next(row for row in rows if row.get("kind")=="capability" and row.get("id")=="docker.install")
descriptor=install["descriptor"]
assert descriptor["implementation"]["kind"]=="composition"
assert install["availability"]=="active"
PY
}

@test "Arch package upgrade and cache clean freeze different reviewed commands" {
    IGOR_DISTRO_ID=arch
    IGOR_DISTRO_FAMILY=arch
    export IGOR_DISTRO_ID IGOR_DISTRO_FAMILY
    run igor_capability_prepare system.package.upgrade '{}' system 1
    [ "$status" -eq 0 ]
    [[ "$output" == *'"privileged_argv":[["sudo","-n","--","pacman","-Syu","--noconfirm"]]'* ]]
    run igor_capability_prepare system.package.cache.clean '{}' system 1
    [ "$status" -eq 0 ]
    [[ "$output" == *'"privileged_argv":[["sudo","-n","--","pacman","-Sc","--noconfirm"]]'* ]]
    [[ "$output" == *'"class":"irreversible"'* ]]
}

@test "service restart reuses the reviewed exact-argv privilege adapter" {
    run igor_capability_prepare system.service.restart '{"unit":"cron.service"}' system 1
    [ "$status" -eq 0 ]
    [[ "$output" == *'"privilege":"required"'* ]]
    [[ "$output" == *'"privileged_argv":["sudo","-n","--","systemctl","restart","cron.service"]'* ]]
    [[ "$output" == *'"precondition_status":"satisfied"'* ]]
}
