#!/usr/bin/env bats

load '../helpers/common'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config" "$IGOR_DIR/bin" "$IGOR_DIR/runtime"
    cp -a "$REPO_DIR/modules/system" "$IGOR_DIR/modules/system"
    printf 'system=enabled\n' > "$IGOR_DIR/config/modules.conf"

    export ADMIN_SUDO_TRACE="$IGOR_DIR/runtime/sudo-trace"
    export ADMIN_EFFECT_TRACE="$IGOR_DIR/runtime/effect-trace"
    export ADMIN_MOUNT_STATE="$IGOR_DIR/runtime/mounted"
    export ADMIN_FSTAB_FIXTURE="$IGOR_DIR/runtime/fstab"
    : > "$ADMIN_SUDO_TRACE"
    : > "$ADMIN_EFFECT_TRACE"
    printf 'UUID=root / ext4 defaults 0 1\n' > "$ADMIN_FSTAB_FIXTURE"

    cat > "$IGOR_DIR/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"blockdevices":[]}'
EOF
    cat > "$IGOR_DIR/bin/mkdir" <<'EOF'
#!/usr/bin/env bash
printf 'mkdir %s\n' "$*" >> "$ADMIN_EFFECT_TRACE"
exit 0
EOF
    cat > "$IGOR_DIR/bin/mount" <<'EOF'
#!/usr/bin/env bash
printf 'mount %s\n' "$*" >> "$ADMIN_EFFECT_TRACE"
if [ "${ADMIN_SKIP_MOUNT_STATE:-0}" != 1 ]; then
    printf '%s\n' "$*" > "$ADMIN_MOUNT_STATE"
fi
exit 0
EOF
    cat > "$IGOR_DIR/bin/umount" <<'EOF'
#!/usr/bin/env bash
printf 'umount %s\n' "$*" >> "$ADMIN_EFFECT_TRACE"
rm -f "$ADMIN_MOUNT_STATE"
exit 0
EOF
    cat > "$IGOR_DIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$ADMIN_SUDO_TRACE"
[ "$1" = -n ] && [ "$2" = -- ] || exit 2
shift 2
exec "$@"
EOF
    chmod +x "$IGOR_DIR/bin/"*
    export PATH="$IGOR_DIR/bin:$PATH"

    source "$REPO_DIR/core/lib/module_loader.sh"
    _ml_log() { :; }
    igor_load_all_modules >/dev/null
    _stub_storage_admin
}

teardown() { teardown_igor_tmpdir; }

_stub_storage_admin() {
    storage_admin_plan_mount() {
        python3 - "$1" <<'PY'
import json,sys
inputs=json.loads(sys.argv[1])
if inputs.get("filesystem")!="filesystem:/dev/sdb1":
    raise SystemExit(1)
if inputs.get("persistence","runtime_only")!="runtime_only":
    raise SystemExit(1)
target="/" + inputs.get("target","mnt/DATA").lstrip("/")
if not target.startswith(("/mnt/","/media/","/srv/")):
    raise SystemExit(1)
print(json.dumps({
    "action":"mount","filesystem":"filesystem:/dev/sdb1","device":"/dev/sdb1",
    "target":target,"persistence":"runtime_only",
    "commands":[
        ["sudo","-n","--","mkdir","-p","--",target],
        ["sudo","-n","--","mount","--","/dev/sdb1",target],
    ],
},separators=(",",":")))
PY
    }
    storage_admin_plan_unmount() {
        python3 - "$1" <<'PY'
import json,sys
inputs=json.loads(sys.argv[1])
if inputs.get("mount")!="mount:/mnt/DATA":
    raise SystemExit(1)
if inputs.get("persistence","runtime_only")!="runtime_only":
    raise SystemExit(1)
print(json.dumps({
    "action":"unmount","mount":"mount:/mnt/DATA","target":"/mnt/DATA",
    "persistence":"runtime_only",
    "commands":[["sudo","-n","--","umount","--","/mnt/DATA"]],
},separators=(",",":")))
PY
    }
    storage_admin_ready_mount() {
        [ ! -e "$ADMIN_MOUNT_STATE" ] || return 1
        printf '%s\n' '{"ready":true,"filesystem":"filesystem:/dev/sdb1","target":"/mnt/DATA","persistence":"runtime_only"}'
    }
    storage_admin_ready_unmount() {
        [ -e "$ADMIN_MOUNT_STATE" ] || return 1
        printf '%s\n' '{"ready":true,"mount":"mount:/mnt/DATA","target":"/mnt/DATA","source":"/dev/sdb1","persistence":"runtime_only"}'
    }
    storage_admin_verify_mount() {
        [ -e "$ADMIN_MOUNT_STATE" ] || return 1
        printf '%s\n' '{"source":"platform.storage.mounts","check_id":"system.storage.mount.present","object_id":"mount:/mnt/DATA","filesystem":"filesystem:/dev/sdb1","target":"/mnt/DATA","observed":"mounted","persistence":"runtime_only"}'
    }
    storage_admin_verify_unmount() {
        [ ! -e "$ADMIN_MOUNT_STATE" ] || return 1
        printf '%s\n' '{"source":"platform.storage.mounts","check_id":"system.storage.mount.absent","object_id":"mount:/mnt/DATA","target":"/mnt/DATA","observed":"absent","persistence":"runtime_only"}'
    }
}

_approve_and_execute() {
    local proposal="$1"
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    IGOR_CAPABILITY_APPROVAL_STATUS=approved
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    igor_capability_execute "$proposal"
}

@test "S5 declarations are reviewed CHANGE operations with runtime-only semantics" {
    mount_cap="$(igor_capability_inspect system.storage.mount system)"
    unmount_cap="$(igor_capability_inspect system.storage.unmount system)"
    python3 - "$mount_cap" "$unmount_cap" <<'PY'
import json,sys
for cap,ident,selector,check in [
    (json.loads(sys.argv[1]),"system.storage.mount","mountable_filesystem",
     "system.storage.mount.present"),
    (json.loads(sys.argv[2]),"system.storage.unmount","unmountable_mount",
     "system.storage.mount.absent"),
]:
    assert cap["resolution"]=="resolved"
    row=next(r for r in cap["providers"] if r["provider"]=="system")["descriptor"]
    assert row["id"]==ident
    assert row["safety"]=={"tier":"CHANGE"}
    assert row["privilege"]=="required"
    assert row["handler"]=="system__privileged_marker"
    required=row["inputs"]["required"]
    assert len(required)==1
    selected=row["inputs"]["properties"][required[0]]["selector"]
    assert selected["resource_kind"]==selector
    assert row["verification"]=={"kind":"trusted_query","check_id":check,"required":True}
    assert "fstab" in row["description"]
PY
}

@test "mount prepare freezes exact default target and never runs an effect" {
    before="$(cat "$ADMIN_FSTAB_FIXTURE")"
    run igor_capability_prepare         system.storage.mount '{"filesystem":"filesystem:/dev/sdb1"}' system 1
    [ "$status" -eq 0 ]
    proposal="$output"
    [[ "$proposal" == *'"precondition_status":"satisfied"'* ]]
    [[ "$proposal" == *'"affected_objects":["filesystem:/dev/sdb1"]'* ]]
    [[ "$proposal" == *'"privileged_argv":[["sudo","-n","--","mkdir","-p","--","/mnt/DATA"],["sudo","-n","--","mount","--","/dev/sdb1","/mnt/DATA"]]'* ]]
    [ ! -s "$ADMIN_SUDO_TRACE" ]
    [ ! -s "$ADMIN_EFFECT_TRACE" ]
    [ "$(cat "$ADMIN_FSTAB_FIXTURE")" = "$before" ]
}

@test "mount execution uses only reviewed argv verifies and does not persist" {
    before="$(cat "$ADMIN_FSTAB_FIXTURE")"
    proposal="$(igor_capability_prepare         system.storage.mount '{"filesystem":"filesystem:/dev/sdb1"}' system 1)"
    run _approve_and_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"execution_status":"succeeded"'* ]]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    [[ "$output" == *'"check_id":"system.storage.mount.present"'* ]]
    [[ "$output" == *'"outcome":"success"'* ]]
    [ "$(sed -n '1p' "$ADMIN_SUDO_TRACE")" = 'sudo -n -- mkdir -p -- /mnt/DATA' ]
    [ "$(sed -n '2p' "$ADMIN_SUDO_TRACE")" = 'sudo -n -- mount -- /dev/sdb1 /mnt/DATA' ]
    ! grep -Eq 'fstab|mount -a|--force|--lazy| -f | -l ' "$ADMIN_SUDO_TRACE"
    [ "$(cat "$ADMIN_FSTAB_FIXTURE")" = "$before" ]
}

@test "custom target is frozen into approval and cannot change after approval" {
    proposal="$(igor_capability_prepare         system.storage.mount         '{"filesystem":"filesystem:/dev/sdb1","target":"srv/archive"}' system 1)"
    [[ "$proposal" == *'/srv/archive'* ]]

    storage_admin_plan_mount() {
        printf '%s\n' '{"action":"mount","filesystem":"filesystem:/dev/sdb1","device":"/dev/sdb1","target":"/mnt/other","persistence":"runtime_only","commands":[["sudo","-n","--","mkdir","-p","--","/mnt/other"],["sudo","-n","--","mount","--","/dev/sdb1","/mnt/other"]]}'
    }
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    IGOR_CAPABILITY_APPROVAL_STATUS=approved
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    run igor_capability_execute "$proposal"
    [ "$status" -ne 0 ]
    [ ! -s "$ADMIN_SUDO_TRACE" ]
    [ ! -s "$ADMIN_EFFECT_TRACE" ]
}

@test "failed mount verification is reported as unverified change" {
    export ADMIN_SKIP_MOUNT_STATE=1
    proposal="$(igor_capability_prepare         system.storage.mount '{"filesystem":"filesystem:/dev/sdb1"}' system 1)"
    run _approve_and_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"execution_status":"succeeded"'* ]]
    [[ "$output" == *'"verification_status":"failed"'* ]]
    [[ "$output" == *'"outcome":"unverified_change"'* ]]
}

@test "unmount uses normal umount only and requires an eligible current mount" {
    printf '%s\n' '-- /dev/sdb1 /mnt/DATA' > "$ADMIN_MOUNT_STATE"
    before="$(cat "$ADMIN_FSTAB_FIXTURE")"
    proposal="$(igor_capability_prepare         system.storage.unmount '{"mount":"mount:/mnt/DATA"}' system 1)"
    [[ "$proposal" == *'"privileged_argv":[["sudo","-n","--","umount","--","/mnt/DATA"]]'* ]]
    run _approve_and_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    [[ "$output" == *'"check_id":"system.storage.mount.absent"'* ]]
    [ "$(tail -n 1 "$ADMIN_SUDO_TRACE")" = 'sudo -n -- umount -- /mnt/DATA' ]
    ! grep -Eq -- '--force|--lazy| -f | -l ' "$ADMIN_SUDO_TRACE"
    [ "$(cat "$ADMIN_FSTAB_FIXTURE")" = "$before" ]
}

@test "trusted storage preflight failure blocks execution before sudo" {
    storage_admin_ready_mount() { return 1; }
    run igor_capability_prepare         system.storage.mount '{"filesystem":"filesystem:/dev/sdb1"}' system 1
    [ "$status" -eq 0 ]
    [[ "$output" == *'"precondition_status":"failed"'* ]]
    proposal="$output"

    run _approve_and_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"execution_status":"not_executed"'* ]]
    [[ "$output" == *'"outcome":"precondition_failed"'* ]]
    [ ! -s "$ADMIN_SUDO_TRACE" ]
}

@test "forged storage verifier is unavailable before preparation" {
    python3 - "$IGOR_DIR/modules/system/contracts/storage.json" <<'PY'
import json,sys
from pathlib import Path
path=Path(sys.argv[1]); data=json.loads(path.read_text())
row=next(x for x in data["contributions"] if x.get("id")=="system.storage.mount")
row["verification"]={"kind":"trusted_query","check_id":"other.check","required":True}
path.write_text(json.dumps(data))
PY
    run bash -c '
        source "$1/core/lib/module_loader.sh"
        _ml_log() { :; }
        igor_load_all_modules >/dev/null
        igor_capability_inspect system.storage.mount system
        igor_capability_prepare system.storage.mount             "{"filesystem":"filesystem:/dev/sdb1"}" system 1
    ' _ "$REPO_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *'trusted_adapter_unavailable'* ]]
}

@test "S5 selectors show only mountable filesystems and unmountable reviewed mounts" {
    source "$REPO_DIR/core/lib/input_candidates.sh"
    igor_model_list() { return 1; }
    storage_filesystems_query() {
        printf '%s\n' '[
          {"object_id":"filesystem:/dev/sdb1","device":"/dev/sdb1","filesystem_type":"ext4",
           "uuid":"u1","label":"DATA","size_bytes":1000,"mounted":false,"mountpoint":""},
          {"object_id":"filesystem:/dev/sdc1","device":"/dev/sdc1","filesystem_type":"xfs",
           "uuid":"u2","label":"USED","size_bytes":1000,"mounted":true,"mountpoint":"/mnt/USED"},
          {"object_id":"filesystem:/dev/sdd1","device":"/dev/sdd1","filesystem_type":"swap",
           "uuid":"u3","label":"SWAP","size_bytes":1000,"mounted":false,"mountpoint":""}
        ]'
    }
    storage_mounts_query() {
        printf '%s\n' '[
          {"object_id":"mount:/","target":"/","source":"/dev/root","filesystem_type":"ext4",
           "total_bytes":1000,"used_bytes":100,"available_bytes":800,"use_percent":10,"read_only":false},
          {"object_id":"mount:/mnt/DATA","target":"/mnt/DATA","source":"/dev/sdb1","filesystem_type":"ext4",
           "total_bytes":1000,"used_bytes":100,"available_bytes":800,"use_percent":10,"read_only":false},
          {"object_id":"mount:/srv/net","target":"/srv/net","source":"server:/share","filesystem_type":"nfs",
           "total_bytes":1000,"used_bytes":100,"available_bytes":800,"use_percent":10,"read_only":false}
        ]'
    }

    run igor_input_candidates_resolve system.storage.mount filesystem
    [ "$status" -eq 0 ]
    [[ "$output" == *'"value":"filesystem:/dev/sdb1"'* ]]
    [[ "$output" != *'filesystem:/dev/sdc1'* ]]
    [[ "$output" != *'filesystem:/dev/sdd1'* ]]

    run igor_input_candidates_resolve system.storage.unmount mount
    [ "$status" -eq 0 ]
    [[ "$output" == *'"value":"mount:/mnt/DATA"'* ]]
    [[ "$output" != *'"value":"mount:/"'* ]]
    [[ "$output" != *'mount:/srv/net'* ]]
}
