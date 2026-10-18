#!/usr/bin/env bats

load '../helpers/common'
load '../helpers/system_admin'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

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
parts=sys.stdin.buffer.read().split(b"\0")
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
 "system.storage.summary",
 "system.storage.mounts.list",
 "system.storage.filesystems.list",
 "system.storage.mount.status",
 "system.storage.filesystem.status",
 "system.storage.mount",
 "system.storage.unmount",
 "system.users.list",
 "system.users.status",
 "system.groups.list",
 "system.groups.status",
 "system.permissions.path.status",
 "system.permissions.owner.set",
 "system.permissions.group.set",
 "system.permissions.mode.set",
 "system.network.summary",
 "system.network.interfaces.list",
 "system.network.interface.status",
 "system.network.routes.list",
 "system.network.dns.status",
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
