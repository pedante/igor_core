#!/usr/bin/env bats

load '../helpers/common'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    export IGOR_DISTRO_ID=debian
    export IGOR_DISTRO_FAMILY=debian
    export IGOR_PLATFORM_QUERY_TIMEOUT_SECONDS=5
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config" "$IGOR_DIR/bin"
    cp -a "$REPO_DIR/modules/system" "$IGOR_DIR/modules/system"
    printf 'system=enabled\n' > "$IGOR_DIR/config/modules.conf"

    cat > "$IGOR_DIR/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "-s upgrade" ]; then
    printf 'Inst curl [1] (2 repo)\nInst openssl [1] (2 repo)\n'
elif [ "$1 $2" = "-s autoremove" ]; then
    printf 'Remv old-kernel [1]\nRemv unused-lib [1]\n'
else
    exit 2
fi
EOF
    cat > "$IGOR_DIR/bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -Qu) printf 'curl 1 -> 2\nlinux 1 -> 2\n' ;;
    -Qdtq) printf 'unused-a\nunused-b\n' ;;
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
            *) printf 'unknown\n'; exit 4 ;;
        esac
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
    chmod +x "$IGOR_DIR/bin/apt-get" "$IGOR_DIR/bin/pacman" "$IGOR_DIR/bin/systemctl" "$IGOR_DIR/bin/journalctl"
    export PATH="$IGOR_DIR/bin:$PATH"

    source "$REPO_DIR/core/lib/module_loader.sh"
    _ml_log() { :; }
    igor_load_all_modules >/dev/null
}

teardown() { teardown_igor_tmpdir; }

_execute_read() {
    local id="$1" inputs="${2:-{}}" proposal
    proposal="$(igor_capability_prepare "$id" "$inputs" system 2)" || return 1
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    IGOR_CAPABILITY_APPROVAL_STATUS=auto_approved
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    igor_capability_execute "$proposal"
}

@test "system administration contracts project into the generic operator namespace" {
    modules="$(igor_module_records)"
    contributions="$(igor_contribution_records)"
    capabilities="$(igor_capability_list)"
    configurations="$(igor_configuration_declarations)"
    surface="$(printf '%s\0%s\0%s\0%s\0' "$modules" "$contributions" "$capabilities" "$configurations" |
        python3 - "$REPO_DIR/core/lib/operator_surface.py" <<'PY'
import json,subprocess,sys
parts=sys.stdin.buffer.read().split(b"\0")
if parts[-1:]==[b""]: parts.pop()
payload=dict(zip(("modules","contributions","capabilities","configurations"),
                 (json.loads(part) for part in parts)))
proc=subprocess.run([sys.executable,sys.argv[1],"build"],
                    input=json.dumps(payload),text=True,capture_output=True,check=True)
print(proc.stdout,end="")
PY
    )"
    python3 - "$surface" <<'PY'
import json,sys
surface=json.loads(sys.argv[1])
paths={row["path"] for row in surface["entries"]}
expected={
 "system.host.summary",
 "system.package.updates.list",
 "system.package.cleanup.preview",
 "system.service.list",
 "system.service.status",
 "system.service.restart",
 "system.logs.recent",
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

@test "recent logs are a bounded READ capability" {
    run _execute_read system.logs.recent '{}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"source":"systemd.journal"'* ]]
    [[ "$output" == *'boot ok'* ]]
    [[ "$output" == *'service ready'* ]]
}

@test "service restart reuses the reviewed exact-argv privilege adapter" {
    run igor_capability_prepare system.service.restart '{"unit":"cron.service"}' system 1
    [ "$status" -eq 0 ]
    [[ "$output" == *'"privilege":"required"'* ]]
    [[ "$output" == *'"privileged_argv":["sudo","-n","--","systemctl","restart","cron.service"]'* ]]
    [[ "$output" == *'"precondition_status":"satisfied"'* ]]
}
