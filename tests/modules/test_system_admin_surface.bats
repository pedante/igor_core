#!/usr/bin/env bats

load '../helpers/common'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    export IGOR_DISTRO_ID=debian
    export IGOR_DISTRO_FAMILY=debian
    export IGOR_PLATFORM_QUERY_TIMEOUT_SECONDS=5
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config" "$IGOR_DIR/bin" "$IGOR_DIR/runtime"
    export ADMIN_UPDATE_STATE="$IGOR_DIR/runtime/updates-pending"
    export ADMIN_PRIVILEGE_TRACE="$IGOR_DIR/runtime/privileged-argv"
    export ADMIN_PACKAGE_STATE="$IGOR_DIR/runtime/docker-package-installed"
    export ADMIN_DOCKER_ENABLED="$IGOR_DIR/runtime/docker-enabled"
    export ADMIN_DOCKER_ACTIVE="$IGOR_DIR/runtime/docker-active"
    printf 'pending\n' > "$ADMIN_UPDATE_STATE"
    : > "$ADMIN_PRIVILEGE_TRACE"
    cp -a "$REPO_DIR/modules/system" "$IGOR_DIR/modules/system"
    cp -a "$REPO_DIR/modules/docker" "$IGOR_DIR/modules/docker"
    printf 'system=enabled\ndocker=enabled\n' > "$IGOR_DIR/config/modules.conf"

    cat > "$IGOR_DIR/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "-s upgrade" ]; then
    [ -e "$ADMIN_UPDATE_STATE" ] && printf 'Inst curl [1] (2 repo)\nInst openssl [1] (2 repo)\n'
elif [ "$1 $2" = "-s autoremove" ]; then
    printf 'Remv old-kernel [1]\nRemv unused-lib [1]\n'
elif [ "$1" = update ] && [ "$#" -eq 1 ]; then
    exit 0
elif [ "$1 $2 $3" = "install -y docker.io" ]; then
    : > "$ADMIN_PACKAGE_STATE"
elif [ "$1 $2" = "upgrade -y" ]; then
    rm -f "$ADMIN_UPDATE_STATE"
elif [ "$1" = clean ] && [ "$#" -eq 1 ]; then
    exit 0
else
    exit 2
fi
EOF
    cat > "$IGOR_DIR/bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
[ -e "$ADMIN_PACKAGE_STATE" ] || exit 1
case "$*" in
    *"-- docker.io") printf 'install ok installed'; exit 0 ;;
    *) exit 1 ;;
esac
EOF
    cat > "$IGOR_DIR/bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -Qu) [ -e "$ADMIN_UPDATE_STATE" ] && printf 'curl 1 -> 2\nlinux 1 -> 2\n' ;;
    -Qdtq) printf 'unused-a\nunused-b\n' ;;
    -Syu)
        [ "$2" = --noconfirm ] || exit 2
        rm -f "$ADMIN_UPDATE_STATE"
        ;;
    -Sc) [ "$2" = --noconfirm ] || exit 2 ;;
    *) exit 2 ;;
esac
EOF
    cat > "$IGOR_DIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list-units)
        printf 'cron.service loaded active running Cron\n'
        printf 'ssh.service loaded inactive dead SSH\n'
        ;;
    is-active)
        case "$3" in
            cron.service) printf 'active\n'; exit 0 ;;
            ssh.service) printf 'inactive\n'; exit 3 ;;
            docker.service)
                if [ -e "$ADMIN_DOCKER_ACTIVE" ]; then printf 'active\n'; exit 0
                else printf 'inactive\n'; exit 3; fi
                ;;
            *) printf 'unknown\n'; exit 4 ;;
        esac
        ;;
    is-enabled)
        [ "$3" = docker.service ] || exit 2
        if [ -e "$ADMIN_DOCKER_ENABLED" ]; then printf 'enabled\n'; exit 0
        else printf 'disabled\n'; exit 1; fi
        ;;
    enable)
        [ "$2" = docker.service ] || exit 2
        : > "$ADMIN_DOCKER_ENABLED"
        ;;
    start)
        [ "$2" = docker.service ] || exit 2
        : > "$ADMIN_DOCKER_ACTIVE"
        ;;
    restart) exit 0 ;;
    *) exit 2 ;;
esac
EOF
    cat > "$IGOR_DIR/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
printf '2026-10-02T12:00:00+0000 host kernel: boot ok\n'
printf '2026-10-02T12:00:01+0000 host systemd: service ready\n'
EOF
    cat > "$IGOR_DIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$ADMIN_PRIVILEGE_TRACE"
[ "$1" = -n ] && [ "$2" = -- ] || exit 2
shift 2
exec "$@"
EOF
    chmod +x "$IGOR_DIR/bin/sudo"
    chmod +x "$IGOR_DIR/bin/apt-get" "$IGOR_DIR/bin/dpkg-query" "$IGOR_DIR/bin/pacman" "$IGOR_DIR/bin/systemctl" "$IGOR_DIR/bin/journalctl"
    export PATH="$IGOR_DIR/bin:$PATH"

    source "$REPO_DIR/core/lib/module_loader.sh"
    _ml_log() { :; }
    igor_load_all_modules >/dev/null
}

teardown() { teardown_igor_tmpdir; }

_execute_read() {
    local id="$1" inputs="${2:-}" proposal
    [ -n "$inputs" ] || inputs='{}'
    proposal="$(igor_capability_prepare "$id" "$inputs" system 2)" || return 1
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    IGOR_CAPABILITY_APPROVAL_STATUS=auto_approved
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    igor_capability_execute "$proposal"
}

@test "missing systemctl only disables service capabilities, not System package or host domains" {
    command() {
        if [ "$1" = -v ] && [ "${2:-}" = systemctl ]; then return 1; fi
        builtin command "$@"
    }
    run igor_module_status system
    [ "$status" -eq 0 ]
    [ "$output" = active ]
    run igor_contribution_state capability:system.host.summary
    [ "$status" -eq 0 ]
    [ "$output" = active ]
    run igor_contribution_state capability:system.package.install
    [ "$status" -eq 0 ]
    [ "$output" = active ]
    run igor_contribution_state capability:system.service.start
    [ "$status" -eq 0 ]
    [ "$output" = unavailable ]
}

@test "reviewed package administration declarations are active only in their exact shape" {
    run igor_capability_inspect system.package.upgrade system
    [ "$status" -eq 0 ]
    [[ "$output" == *'"resolution":"resolved"'* ]]
    [[ "$output" == *'"selected_provider":"system"'* ]]
    run igor_capability_inspect system.package.cache.clean system
    [ "$status" -eq 0 ]
    [[ "$output" == *'"resolution":"resolved"'* ]]
}

@test "forged package administration handler is unavailable before preparation" {
    python3 - "$IGOR_DIR/modules/system/contracts/host.json" <<'PY'
import json,sys
from pathlib import Path
path=Path(sys.argv[1]); data=json.loads(path.read_text())
row=next(x for x in data["contributions"] if x.get("id")=="system.package.upgrade")
row["handler"]="system__package_updates_list"
path.write_text(json.dumps(data))
PY
    run bash -c '
        source "$1/core/lib/module_loader.sh"
        _ml_log() { :; }
        igor_load_all_modules >/dev/null
        igor_capability_inspect system.package.upgrade system
        igor_capability_prepare system.package.upgrade "{}" system 1
    ' _ "$REPO_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *'privileged_adapter_unavailable'* ]]
}

@test "forged package upgrade verifier is unavailable before preparation" {
    python3 - "$IGOR_DIR/modules/system/contracts/host.json" <<'PY'
import json,sys
from pathlib import Path
path=Path(sys.argv[1]); data=json.loads(path.read_text())
row=next(x for x in data["contributions"] if x.get("id")=="system.package.upgrade")
row["verification"]={"kind":"trusted_query","check_id":"other.check","required":True}
path.write_text(json.dumps(data))
PY
    run bash -c '
        source "$1/core/lib/module_loader.sh"
        _ml_log() { :; }
        igor_load_all_modules >/dev/null
        igor_capability_inspect system.package.upgrade system
        igor_capability_prepare system.package.upgrade "{}" system 1
    ' _ "$REPO_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *'trusted_adapter_unavailable'* ]]
}

@test "forged generic package install adapter is unavailable before preparation" {
    python3 - "$IGOR_DIR/modules/system/contracts/host.json" <<'PY'
import json,sys
from pathlib import Path
path=Path(sys.argv[1]); data=json.loads(path.read_text())
row=next(x for x in data["contributions"] if x.get("id")=="system.package.install")
row["handler"]="system__package_updates_list"
path.write_text(json.dumps(data))
PY
    run bash -c '
        source "$1/core/lib/module_loader.sh"
        _ml_log() { :; }
        igor_load_all_modules >/dev/null
        igor_capability_inspect system.package.install system
        igor_capability_prepare system.package.install "{"package":"pkg_docker"}" system 1
    ' _ "$REPO_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *'privileged_adapter_unavailable'* ]]
}

@test "forged generic package install verifier is unavailable before preparation" {
    python3 - "$IGOR_DIR/modules/system/contracts/host.json" <<'PY'
import json,sys
from pathlib import Path
path=Path(sys.argv[1]); data=json.loads(path.read_text())
row=next(x for x in data["contributions"] if x.get("id")=="system.package.install")
row["verification"]={"kind":"trusted_query","check_id":"other.check","required":True}
path.write_text(json.dumps(data))
PY
    run bash -c '
        source "$1/core/lib/module_loader.sh"
        _ml_log() { :; }
        igor_load_all_modules >/dev/null
        igor_capability_inspect system.package.install system
        igor_capability_prepare system.package.install "{\"package\":\"docker.io\"}" system 1
    ' _ "$REPO_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *'trusted_adapter_unavailable'* ]]
}

@test "forged service enable verifier is unavailable before preparation" {
    python3 - "$IGOR_DIR/modules/system/contracts/host.json" <<'PY'
import json,sys
from pathlib import Path
path=Path(sys.argv[1]); data=json.loads(path.read_text())
row=next(x for x in data["contributions"] if x.get("id")=="system.service.enable")
row["verification"]={"kind":"trusted_query","check_id":"other.check","required":True}
path.write_text(json.dumps(data))
PY
    run bash -c '
        source "$1/core/lib/module_loader.sh"
        _ml_log() { :; }
        igor_load_all_modules >/dev/null
        igor_capability_inspect system.service.enable system
        igor_capability_prepare system.service.enable "{\"unit\":\"docker.service\"}" system 1
    ' _ "$REPO_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *'trusted_adapter_unavailable'* ]]
}

@test "system administration contracts project into the generic operator namespace" {
    modules="$(igor_module_records)"
    contributions="$(igor_contribution_records)"
    capabilities="$(igor_capability_list)"
    configurations="$(igor_configuration_declarations)"
    surface="$(printf '%s\0%s\0%s\0%s\0' "$modules" "$contributions" "$capabilities" "$configurations" |
        python3 -c '
import json,subprocess,sys
tool=sys.argv[1]
parts=sys.stdin.buffer.read().split(b"\\0")
if parts[-1:]==[b""]: parts.pop()
payload=dict(zip(("modules","contributions","capabilities","configurations"),
                 (json.loads(part) for part in parts)))
proc=subprocess.run([sys.executable,tool,"build"],input=json.dumps(payload),
                    text=True,capture_output=True,check=True)
print(proc.stdout,end="")
' "$REPO_DIR/core/lib/operator_surface.py")"
    python3 - "$surface" <<'PY'
import json,sys
surface=json.loads(sys.argv[1])
paths={row["path"] for row in surface["entries"]}
expected={
 "system.host.summary",
 "system.package.updates.list",
 "system.package.cleanup.preview",
 "system.package.install",
 "system.package.upgrade",
 "system.package.cache.clean",
 "system.service.list",
 "system.service.enable",
 "system.service.start",
 "system.service.status",
 "system.service.restart",
 "system.logs.summary",
}
assert expected <= paths,(expected-paths)
PY
}

@test "Debian and Arch share one package update capability with different platform mechanics" {
    run _execute_read system.package.updates.list '{}'
    [ "$status" -eq 0 ]
    python3 - "$output" <<'PY'
import json,sys
row=json.loads(sys.argv[1])
assert row["outcome"]=="success"
assert row["result"]["distro_family"]=="debian"
assert row["result"]["count"]==2
assert row["result"]["packages"]=="curl\nopenssl"
PY

    IGOR_DISTRO_ID=arch
    IGOR_DISTRO_FAMILY=arch
    export IGOR_DISTRO_ID IGOR_DISTRO_FAMILY
    run _execute_read system.package.updates.list '{}'
    [ "$status" -eq 0 ]
    python3 - "$output" <<'PY'
import json,sys
row=json.loads(sys.argv[1])
assert row["outcome"]=="success"
assert row["result"]["distro_family"]=="arch"
assert row["result"]["count"]==2
assert row["result"]["packages"]=="curl\nlinux"
PY
}

@test "cleanup preview remains read-only and exposes candidates before any deletion" {
    run _execute_read system.package.cleanup.preview '{}'
    [ "$status" -eq 0 ]
    python3 - "$output" <<'PY'
import json,sys
row=json.loads(sys.argv[1])
assert row["outcome"]=="success"
assert row["safety"]["tier"]=="READ"
assert row["result"]["candidate_count"]==2
assert row["result"]["candidates"]=="old-kernel\nunused-lib"
assert row["result"]["cache_bytes"] >= 0
PY
}

@test "service inventory and status use the shared systemd platform abstraction" {
    run _execute_read system.service.list '{}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'cron.service\tactive\trunning'* ]]
    [[ "$output" == *'ssh.service\tinactive\tdead'* ]]

    run _execute_read system.service.status '{"unit":"cron.service"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"unit":"cron.service"'* ]]
    [[ "$output" == *'"state":"active"'* ]]

    run igor_capability_prepare system.service.status '{"unit":"bad unit;reboot"}' system 2
    [ "$status" -ne 0 ]
}

@test "service-list provider bridge metadata is compiled at module load" {
    [ "${_IGOR_HANDLER_FUNCTION[capability:system.service.list]:-}" = system__service_list ]
    [ "${_IGOR_HANDLER_TIMEOUT[capability:system.service.list]:-}" = 30 ]
    [ "${_IGOR_MODULE_ENTRYPOINT[system]:-}" = module.sh ]
    [ "${_IGOR_OWNER_HAS_DOMAIN_EVENTS[system]:-0}" = 0 ]
}

@test "targeted preparation evaluates only the selected capability requirement path" {
    local trace="$IGOR_DIR/runtime/dynamic-requirements"
    : > "$trace"
    eval "$(declare -f _ml_contribution_dynamic_failure | sed '1s/_ml_contribution_dynamic_failure/_original_dynamic_failure/')"
    _ml_contribution_dynamic_failure() {
        printf '%s\n' "$1" >> "$trace"
        _original_dynamic_failure "$@"
    }

    run igor_capability_prepare system.service.list '{}' system 2
    [ "$status" -eq 0 ]
    [ "$(cat "$trace")" = "capability:system.service.list" ]
}

@test "service-list prepare stays below a bounded Python process budget" {
    local real_python counter wrapper count
    real_python="$(command -v python3)"
    counter="$IGOR_DIR/runtime/python-invocations"
    wrapper="$IGOR_DIR/bin/counting-python"
    : > "$counter"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
printf '.\n' >> "$counter"
exec "$real_python" "\$@"
EOF
    chmod +x "$wrapper"
    export IGOR_PYTHON="$wrapper"

    run igor_capability_prepare system.service.list '{}' system 2
    [ "$status" -eq 0 ]
    count="$(wc -l < "$counter")"
    [ "$count" -le 20 ]
}


@test "execution fence evaluates current preconditions exactly once" {
    local proposal trace
    proposal="$(igor_capability_prepare system.service.list '{}' system 2)"
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    IGOR_CAPABILITY_APPROVAL_STATUS=approved
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    trace="$IGOR_DIR/runtime/precondition-calls"
    : > "$trace"
    eval "$(declare -f _igor_capability_preconditions | sed '1s/_igor_capability_preconditions/_original_capability_preconditions/')"
    _igor_capability_preconditions() {
        printf '.\n' >> "$trace"
        _original_capability_preconditions "$@"
    }

    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$trace")" -eq 1 ]
}

@test "log summary is bounded metadata and never persists raw journal messages" {
    run _execute_read system.logs.summary '{}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"source":"systemd.journal"'* ]]
    [[ "$output" == *'"recent_count":2'* ]]
    [[ "$output" != *'boot ok'* ]]
    [[ "$output" != *'service ready'* ]]
    history="$(igor_history_cli recent 1)"
    [[ "$history" != *'boot ok'* ]]
    [[ "$history" != *'service ready'* ]]
}

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

@test "package upgrade freezes distro-specific argv and verifies the Debian result" {
    run igor_capability_prepare system.package.upgrade '{}' system 1
    [ "$status" -eq 0 ]
    proposal="$output"
    [[ "$proposal" == *'"privileged_argv":[["sudo","-n","--","apt-get","update"],["sudo","-n","--","apt-get","upgrade","-y"]]'* ]]
    IGOR_CAPABILITY_APPROVED_DIGEST="$(printf '%s' "$proposal" | python3 -c 'import json,sys;print(json.load(sys.stdin)["digest"])')"
    IGOR_CAPABILITY_APPROVAL_STATUS=approved
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"execution_status":"succeeded"'* ]]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    [[ "$output" == *'"remaining_updates":0'* ]]
    [ "$(sed -n '1p' "$ADMIN_PRIVILEGE_TRACE")" = 'sudo -n -- apt-get update' ]
    [ "$(sed -n '2p' "$ADMIN_PRIVILEGE_TRACE")" = 'sudo -n -- apt-get upgrade -y' ]
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
