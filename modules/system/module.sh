#!/bin/bash
# =============================================================================
#  MODULE: system
#  Linux system management: services, storage, cron, and hardware monitoring.
#  Architecture-agnostic — uses /proc, /sys, and optional vcgencmd/lsblk.
# =============================================================================

# Module API v2 observer handler. The loader invokes this function in an
# isolated Bash process with one JSON request on stdin. Keep the response to
# one JSON document on stdout; diagnostics belong on stderr.
system__observe_memory() {
    local request available_kb
    IFS= read -r request || {
        printf '%s\n' '{"status":"error","error":{"code":"invalid_request","message":"request is required"}}'
        return 0
    }

    # The adapter validates the complete envelope. This check prevents
    # accidental execution when the handler is called directly with another
    # payload while keeping the Bash adapter independent of jq.
    case "$request" in
        *'"api_version":2'*'"contribution_id":"host.memory"'*) ;;
        *)
            printf '%s\n' '{"status":"error","error":{"code":"invalid_request","message":"expected host.memory v2 request"}}'
            return 0
            ;;
    esac

    available_kb=$(awk '/^MemAvailable:[[:space:]]+[0-9]+[[:space:]]+kB$/ { print $2; exit }' /proc/meminfo 2>/dev/null)
    if [[ ! "$available_kb" =~ ^[0-9]+$ ]]; then
        printf '%s\n' '{"status":"error","error":{"code":"unavailable","message":"MemAvailable is not available"}}'
        return 0
    fi

    printf '{"status":"ok","result":{"object_id":"host:local","facts":[{"property":"memory.available_bytes","value":%s,"evidence":["/proc/meminfo:MemAvailable"]}],"unavailable":[]}}\n' "$((available_kb * 1024))"
    return 0
}

# The capability handler names the declared observer. Igor validates this
# response and performs the refresh in the parent process, where the Wave D
# System Model lives. The handler cannot publish a fact or choose another
# observer by returning arbitrary data.
system__refresh_memory() {
    local request
    IFS= read -r request || return 1
    case "$request" in
        *'"api_version":2'*'"contribution_id":"system.host.memory.refresh"'*'"input":{}'*)
            printf '%s\n' '{"status":"ok","result":{"observer_id":"host.memory"}}'
            ;;
        *)
            printf '%s\n' '{"status":"error","error":{"code":"invalid_request","message":"expected memory refresh request"}}'
            ;;
    esac
}

# A v2 check receives only Igor's fact snapshot. It does not probe /proc or
# choose its own check identity, owner, time, approval or execution policy.
_mod_sys_memory_warning_request() {
    local action="$1" request package
    IFS= read -r request || return 1
    package="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || return 1
    "${IGOR_PYTHON:-python3}" "$package/lib/memory_warning.py" "$action" "$request"
}

system__check_memory() { _mod_sys_memory_warning_request check; }
system__apply_memory_warning() { _mod_sys_memory_warning_request apply; }
system__read_memory_warning() { _mod_sys_memory_warning_request readback; }


# S4 storage read model. Core owns the normalized Linux mechanism; System owns
# host-domain observation and presentation. Nothing in this block mutates mount
# state, filesystems or persistence.
_mod_sys_storage_rows() {
    local kind="${1:-}"
    [ -n "${_IGOR_LOADER_DIR:-}" ] || return 1
    # shellcheck source=core/lib/storage.sh
    source "${_IGOR_LOADER_DIR}/core/lib/storage.sh"
    case "$kind" in
        mounts) storage_mounts_query ;;
        filesystems) storage_filesystems_query ;;
        *) return 2 ;;
    esac
}

_mod_sys_storage_observe() {
    local contribution="$1" kind="$2" rows input
    input="$(_mod_sys_admin_request "$contribution")" || {
        _mod_sys_admin_error invalid_request "expected $contribution v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "$contribution takes no inputs"
        return 0
    }
    rows="$(_mod_sys_storage_rows "$kind")" || {
        _mod_sys_admin_error unavailable "$kind storage discovery failed"
        return 0
    }
    STORAGE_ROWS="$rows" STORAGE_KIND="$kind" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

kind = os.environ["STORAGE_KIND"]
rows = json.loads(os.environ["STORAGE_ROWS"])
maps = {
    "mounts": {
        "mount.target": "target",
        "mount.source": "source",
        "mount.filesystem_type": "filesystem_type",
        "mount.total_bytes": "total_bytes",
        "mount.used_bytes": "used_bytes",
        "mount.available_bytes": "available_bytes",
        "mount.use_percent": "use_percent",
        "mount.read_only": "read_only",
    },
    "filesystems": {
        "filesystem.device": "device",
        "filesystem.type": "filesystem_type",
        "filesystem.uuid": "uuid",
        "filesystem.label": "label",
        "filesystem.size_bytes": "size_bytes",
        "filesystem.mounted": "mounted",
        "filesystem.mountpoint": "mountpoint",
    },
}
objects = []
for row in rows:
    object_id = row["object_id"]
    evidence = [f"core.storage.{kind}:{object_id}"]
    objects.append({
        "object_id": object_id,
        "facts": [
            {"property": prop, "value": row[field], "evidence": evidence}
            for prop, field in maps[kind].items()
        ],
        "unavailable": [],
    })
print(json.dumps({"status": "ok", "result": {"objects": objects}},
                 separators=(",", ":")))
PY
}

system__observe_mounts() { _mod_sys_storage_observe storage.mounts mounts; }
system__observe_filesystems() { _mod_sys_storage_observe storage.filesystems filesystems; }

system__storage_mounts_list() {
    local input rows
    input="$(_mod_sys_admin_request system.storage.mounts.list)" || {
        _mod_sys_admin_error invalid_request "expected system.storage.mounts.list v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.storage.mounts.list takes no inputs"
        return 0
    }
    rows="$(_mod_sys_storage_rows mounts)" || {
        _mod_sys_admin_error unavailable "mount discovery failed"
        return 0
    }
    STORAGE_ROWS="$rows" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os
rows = json.loads(os.environ["STORAGE_ROWS"])
lines = [
    f'{row["object_id"]}\t{row["target"]}\t{row["filesystem_type"]}\t'
    f'{row["use_percent"]}%\t{row["source"]}'
    for row in rows
]
print(json.dumps({"status": "ok", "result": {
    "count": len(rows),
    "mounts": "\n".join(lines)[:4096],
    "source": "core.storage.mounts",
}}, separators=(",", ":")))
PY
}

system__storage_filesystems_list() {
    local input rows
    input="$(_mod_sys_admin_request system.storage.filesystems.list)" || {
        _mod_sys_admin_error invalid_request "expected system.storage.filesystems.list v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.storage.filesystems.list takes no inputs"
        return 0
    }
    rows="$(_mod_sys_storage_rows filesystems)" || {
        _mod_sys_admin_error unavailable "filesystem discovery failed"
        return 0
    }
    STORAGE_ROWS="$rows" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os
rows = json.loads(os.environ["STORAGE_ROWS"])
lines = [
    f'{row["object_id"]}\t{row["device"]}\t{row["filesystem_type"]}\t'
    f'{row["size_bytes"]}\t{row["mountpoint"] or "unmounted"}'
    for row in rows
]
print(json.dumps({"status": "ok", "result": {
    "count": len(rows),
    "filesystems": "\n".join(lines)[:4096],
    "source": "core.storage.filesystems",
}}, separators=(",", ":")))
PY
}

system__storage_summary() {
    local input mounts filesystems
    input="$(_mod_sys_admin_request system.storage.summary)" || {
        _mod_sys_admin_error invalid_request "expected system.storage.summary v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.storage.summary takes no inputs"
        return 0
    }
    mounts="$(_mod_sys_storage_rows mounts)" || {
        _mod_sys_admin_error unavailable "mount discovery failed"
        return 0
    }
    filesystems="$(_mod_sys_storage_rows filesystems)" || {
        _mod_sys_admin_error unavailable "filesystem discovery failed"
        return 0
    }
    STORAGE_MOUNTS="$mounts" STORAGE_FILESYSTEMS="$filesystems" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os
mounts = json.loads(os.environ["STORAGE_MOUNTS"])
filesystems = json.loads(os.environ["STORAGE_FILESYSTEMS"])
root = next((row for row in mounts if row["target"] == "/"), None)
mounted = sum(bool(row["mounted"]) for row in filesystems)
print(json.dumps({"status": "ok", "result": {
    "mount_count": len(mounts),
    "filesystem_count": len(filesystems),
    "mounted_filesystem_count": mounted,
    "unmounted_filesystem_count": len(filesystems) - mounted,
    "root_use_percent": root["use_percent"] if root else 0,
    "source": "core.storage",
}}, separators=(",", ":")))
PY
}

_mod_sys_storage_status() {
    local expected="$1" kind="$2" input_name="$3" input object_id rows
    input="$(_mod_sys_admin_request "$expected")" || {
        _mod_sys_admin_error invalid_request "expected $expected v2 request"
        return 0
    }
    object_id="$(STORAGE_INPUT="$input" STORAGE_INPUT_NAME="$input_name"         "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os
value = json.loads(os.environ["STORAGE_INPUT"]).get(os.environ["STORAGE_INPUT_NAME"])
if not isinstance(value, str):
    raise SystemExit(1)
print(value)
PY
)" || object_id=""
    case "$kind:$object_id" in
        mounts:mount:*) ;;
        filesystems:filesystem:*) ;;
        *)
            _mod_sys_admin_error invalid_request "storage object identity does not match selector kind"
            return 0
            ;;
    esac
    rows="$(_mod_sys_storage_rows "$kind")" || {
        _mod_sys_admin_error unavailable "$kind storage discovery failed"
        return 0
    }
    STORAGE_ROWS="$rows" STORAGE_OBJECT_ID="$object_id" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os
rows = json.loads(os.environ["STORAGE_ROWS"])
ident = os.environ["STORAGE_OBJECT_ID"]
row = next((item for item in rows if item.get("object_id") == ident), None)
if row is None:
    raise SystemExit(3)
print(json.dumps({"status": "ok", "result": row}, separators=(",", ":")))
PY
    case "$?" in
        0) ;;
        3) _mod_sys_admin_error unavailable "storage object is not currently present" ;;
        *) _mod_sys_admin_error unavailable "storage status normalization failed" ;;
    esac
}

system__storage_mount_status() {
    _mod_sys_storage_status system.storage.mount.status mounts mount
}

system__storage_filesystem_status() {
    _mod_sys_storage_status system.storage.filesystem.status filesystems filesystem
}


# S6 local accounts, permissions and bounded path inspection. Core owns
# deterministic Linux reads and reviewed privileged mechanics; System owns
# host-domain object meaning and presentation.
_mod_sys_account_rows() {
    local kind="${1:-}"
    [ -n "${_IGOR_LOADER_DIR:-}" ] || return 1
    # shellcheck source=core/lib/access.sh
    source "${_IGOR_LOADER_DIR}/core/lib/access.sh"
    case "$kind" in
        users) account_users_query ;;
        groups) account_groups_query ;;
        *) return 2 ;;
    esac
}

_mod_sys_account_observe() {
    local contribution="$1" kind="$2" rows input
    input="$(_mod_sys_admin_request "$contribution")" || {
        _mod_sys_admin_error invalid_request "expected $contribution v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "$contribution takes no inputs"
        return 0
    }
    rows="$(_mod_sys_account_rows "$kind")" || {
        _mod_sys_admin_error unavailable "$kind account discovery failed"
        return 0
    }
    ACCOUNT_ROWS="$rows" ACCOUNT_KIND="$kind" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

kind = os.environ["ACCOUNT_KIND"]
rows = json.loads(os.environ["ACCOUNT_ROWS"])
maps = {
    "users": {
        "user.name": "name",
        "user.uid": "uid",
        "user.primary_gid": "primary_gid",
        "user.home": "home",
        "user.shell": "shell",
    },
    "groups": {
        "group.name": "name",
        "group.gid": "gid",
        "group.member_count": "member_count",
        "group.members": "members",
    },
}
objects = []
for row in rows:
    object_id = row["object_id"]
    evidence = [f"core.accounts.{kind}:{object_id}"]
    objects.append({
        "object_id": object_id,
        "facts": [
            {"property": prop, "value": row[field], "evidence": evidence}
            for prop, field in maps[kind].items()
        ],
        "unavailable": [],
    })
print(json.dumps({"status": "ok", "result": {"objects": objects}},
                 separators=(",", ":")))
PY
}

system__observe_users() { _mod_sys_account_observe accounts.users users; }
system__observe_groups() { _mod_sys_account_observe accounts.groups groups; }

_mod_sys_account_list() {
    local expected="$1" kind="$2" output_key="$3" input rows
    input="$(_mod_sys_admin_request "$expected")" || {
        _mod_sys_admin_error invalid_request "expected $expected v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "$expected takes no inputs"
        return 0
    }
    rows="$(_mod_sys_account_rows "$kind")" || {
        _mod_sys_admin_error unavailable "$kind account discovery failed"
        return 0
    }
    ACCOUNT_ROWS="$rows" ACCOUNT_KIND="$kind" ACCOUNT_OUTPUT="$output_key"         "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

rows = json.loads(os.environ["ACCOUNT_ROWS"])
kind = os.environ["ACCOUNT_KIND"]
key = os.environ["ACCOUNT_OUTPUT"]
if kind == "users":
    lines = [
        f'{row["object_id"]}\t{row["name"]}\tuid={row["uid"]}\t'
        f'gid={row["primary_gid"]}\t{row["home"]}'
        for row in rows
    ]
else:
    lines = [
        f'{row["object_id"]}\t{row["name"]}\tgid={row["gid"]}\t'
        f'members={row["member_count"]}'
        for row in rows
    ]
print(json.dumps({"status": "ok", "result": {
    "count": len(rows),
    key: "\n".join(lines)[:8192],
    "source": "core.accounts." + kind,
}}, separators=(",", ":")))
PY
}

system__users_list() {
    _mod_sys_account_list system.users.list users users
}

system__groups_list() {
    _mod_sys_account_list system.groups.list groups groups
}

_mod_sys_account_status() {
    local expected="$1" kind="$2" input_name="$3" input object_id rows
    input="$(_mod_sys_admin_request "$expected")" || {
        _mod_sys_admin_error invalid_request "expected $expected v2 request"
        return 0
    }
    object_id="$(ACCOUNT_INPUT="$input" ACCOUNT_INPUT_NAME="$input_name"         "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os
value = json.loads(os.environ["ACCOUNT_INPUT"]).get(os.environ["ACCOUNT_INPUT_NAME"])
if not isinstance(value, str):
    raise SystemExit(1)
print(value)
PY
)" || object_id=""
    case "$kind:$object_id" in
        users:user:uid:*) ;;
        groups:group:gid:*) ;;
        *)
            _mod_sys_admin_error invalid_request "account identity does not match selector kind"
            return 0
            ;;
    esac
    rows="$(_mod_sys_account_rows "$kind")" || {
        _mod_sys_admin_error unavailable "$kind account discovery failed"
        return 0
    }
    ACCOUNT_ROWS="$rows" ACCOUNT_OBJECT_ID="$object_id" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os
rows = json.loads(os.environ["ACCOUNT_ROWS"])
ident = os.environ["ACCOUNT_OBJECT_ID"]
row = next((item for item in rows if item.get("object_id") == ident), None)
if row is None:
    raise SystemExit(3)
print(json.dumps({"status": "ok", "result": row}, separators=(",", ":")))
PY
    case "$?" in
        0) ;;
        3) _mod_sys_admin_error unavailable "account object is not currently present" ;;
        *) _mod_sys_admin_error unavailable "account status normalization failed" ;;
    esac
}

system__user_status() {
    _mod_sys_account_status system.users.status users user
}

system__group_status() {
    _mod_sys_account_status system.groups.status groups group
}

system__path_status() {
    local input path row
    input="$(_mod_sys_admin_request system.permissions.path.status)" || {
        _mod_sys_admin_error invalid_request "expected system.permissions.path.status v2 request"
        return 0
    }
    path="$(ACCESS_INPUT="$input" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os
value = json.loads(os.environ["ACCESS_INPUT"]).get("path")
if not isinstance(value, str):
    raise SystemExit(1)
print(value)
PY
)" || path=""
    [ -n "$path" ] || {
        _mod_sys_admin_error invalid_request "path is required"
        return 0
    }
    # shellcheck source=core/lib/access.sh
    source "${_IGOR_LOADER_DIR}/core/lib/access.sh"
    row="$(path_status_query "$path")" || {
        _mod_sys_admin_error unavailable "path metadata is unavailable or outside bounded inspection roots"
        return 0
    }
    ACCESS_ROW="$row" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os
row = json.loads(os.environ["ACCESS_ROW"])
result = {key: row[key] for key in (
    "object_id", "path", "kind", "uid", "gid", "owner", "group", "mode", "size_bytes"
)}
print(json.dumps({"status": "ok", "result": result}, separators=(",", ":")))
PY
}


# S7.2 provider-neutral network read model. Core owns bounded Linux network
# reads; System owns host-domain observation and presentation. Wi-Fi provider
# behavior and every network mutation remain outside this block.
_mod_sys_network_read() {
    local kind="${1:-}"
    [ -n "${_IGOR_LOADER_DIR:-}" ] || return 1
    # shellcheck source=core/lib/network.sh
    source "${_IGOR_LOADER_DIR}/core/lib/network.sh"
    case "$kind" in
        interfaces) network_interfaces_query ;;
        routes) network_routes_query ;;
        dns) network_dns_query ;;
        snapshot) network_snapshot_query ;;
        *) return 2 ;;
    esac
}

_mod_sys_network_surface() {
    local action="${1:-}" object_id="${2:-}" package
    package="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || return 1
    if [ -n "$object_id" ]; then
        "${IGOR_PYTHON:-python3}" "$package/lib/network_surface.py" "$action" "$object_id"
    else
        "${IGOR_PYTHON:-python3}" "$package/lib/network_surface.py" "$action"
    fi
}

system__observe_interfaces() {
    local input rows result
    input="$(_mod_sys_admin_request network.interfaces)" || {
        _mod_sys_admin_error invalid_request "expected network.interfaces v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "network.interfaces takes no inputs"
        return 0
    }
    rows="$(_mod_sys_network_read interfaces)" || {
        _mod_sys_admin_error unavailable "network interface discovery failed"
        return 0
    }
    result="$(printf '%s' "$rows" | _mod_sys_network_surface observe-interfaces)" || {
        _mod_sys_admin_error unavailable "network interface normalization failed"
        return 0
    }
    printf '%s\n' "$result"
}

system__network_summary() {
    local input snapshot result
    input="$(_mod_sys_admin_request system.network.summary)" || {
        _mod_sys_admin_error invalid_request "expected system.network.summary v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.network.summary takes no inputs"
        return 0
    }
    snapshot="$(_mod_sys_network_read snapshot)" || {
        _mod_sys_admin_error unavailable "network snapshot discovery failed"
        return 0
    }
    result="$(printf '%s' "$snapshot" | _mod_sys_network_surface summary)" || {
        _mod_sys_admin_error unavailable "network summary normalization failed"
        return 0
    }
    printf '%s\n' "$result"
}

system__network_interfaces_list() {
    local input rows result
    input="$(_mod_sys_admin_request system.network.interfaces.list)" || {
        _mod_sys_admin_error invalid_request "expected system.network.interfaces.list v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.network.interfaces.list takes no inputs"
        return 0
    }
    rows="$(_mod_sys_network_read interfaces)" || {
        _mod_sys_admin_error unavailable "network interface discovery failed"
        return 0
    }
    result="$(printf '%s' "$rows" | _mod_sys_network_surface interfaces-list)" || {
        _mod_sys_admin_error unavailable "network interface presentation failed"
        return 0
    }
    printf '%s\n' "$result"
}

system__network_interface_status() {
    local input object_id rows result
    input="$(_mod_sys_admin_request system.network.interface.status)" || {
        _mod_sys_admin_error invalid_request "expected system.network.interface.status v2 request"
        return 0
    }
    object_id="$(NETWORK_INPUT="$input" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

value = json.loads(os.environ["NETWORK_INPUT"]).get("interface")
if not isinstance(value, str):
    raise SystemExit(1)
print(value)
PY
)" || object_id=""
    case "$object_id" in
        interface:*) ;;
        *)
            _mod_sys_admin_error invalid_request "interface identity is required"
            return 0
            ;;
    esac
    rows="$(_mod_sys_network_read interfaces)" || {
        _mod_sys_admin_error unavailable "network interface discovery failed"
        return 0
    }
    result="$(printf '%s' "$rows" | _mod_sys_network_surface interface-status "$object_id")" || {
        _mod_sys_admin_error unavailable "interface object is not currently present"
        return 0
    }
    printf '%s\n' "$result"
}

system__network_routes_list() {
    local input rows result
    input="$(_mod_sys_admin_request system.network.routes.list)" || {
        _mod_sys_admin_error invalid_request "expected system.network.routes.list v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.network.routes.list takes no inputs"
        return 0
    }
    rows="$(_mod_sys_network_read routes)" || {
        _mod_sys_admin_error unavailable "network route discovery failed"
        return 0
    }
    result="$(printf '%s' "$rows" | _mod_sys_network_surface routes-list)" || {
        _mod_sys_admin_error unavailable "network route presentation failed"
        return 0
    }
    printf '%s\n' "$result"
}

system__network_dns_status() {
    local input row result
    input="$(_mod_sys_admin_request system.network.dns.status)" || {
        _mod_sys_admin_error invalid_request "expected system.network.dns.status v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.network.dns.status takes no inputs"
        return 0
    }
    row="$(_mod_sys_network_read dns)" || {
        _mod_sys_admin_error unavailable "resolver configuration discovery failed"
        return 0
    }
    result="$(printf '%s' "$row" | _mod_sys_network_surface dns-status)" || {
        _mod_sys_admin_error unavailable "resolver presentation failed"
        return 0
    }
    printf '%s\n' "$result"
}


# S7.3 optional NetworkManager Wi-Fi READ provider. This is deliberately
# separate from _mod_sys_network_read so generic network reads never acquire an
# nmcli dependency. No function in this block exposes Wi-Fi mutation.
_mod_sys_wifi_read() {
    local kind="${1:-}"
    [ -n "${_IGOR_LOADER_DIR:-}" ] || return 1
    # shellcheck source=core/lib/networkmanager_wifi.sh
    source "${_IGOR_LOADER_DIR}/core/lib/networkmanager_wifi.sh"
    case "$kind" in
        status) networkmanager_wifi_status_query ;;
        scan) networkmanager_wifi_scan_query ;;
        profiles) networkmanager_wifi_profiles_query ;;
        *) return 2 ;;
    esac
}

system__network_wifi_status() {
    local input row result
    input="$(_mod_sys_admin_request system.network.wifi.status)" || {
        _mod_sys_admin_error invalid_request "expected system.network.wifi.status v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.network.wifi.status takes no inputs"
        return 0
    }
    row="$(_mod_sys_wifi_read status)" || {
        _mod_sys_admin_error unavailable "NetworkManager Wi-Fi status unavailable"
        return 0
    }
    result="$(printf '%s' "$row" | _mod_sys_network_surface wifi-status)" || {
        _mod_sys_admin_error unavailable "NetworkManager Wi-Fi status normalization failed"
        return 0
    }
    printf '%s\n' "$result"
}

system__network_wifi_scan() {
    local input rows result
    input="$(_mod_sys_admin_request system.network.wifi.scan)" || {
        _mod_sys_admin_error invalid_request "expected system.network.wifi.scan v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.network.wifi.scan takes no inputs"
        return 0
    }
    rows="$(_mod_sys_wifi_read scan)" || {
        _mod_sys_admin_error unavailable "NetworkManager Wi-Fi scan unavailable"
        return 0
    }
    result="$(printf '%s' "$rows" | _mod_sys_network_surface wifi-scan)" || {
        _mod_sys_admin_error unavailable "NetworkManager Wi-Fi scan normalization failed"
        return 0
    }
    printf '%s\n' "$result"
}

system__network_wifi_profiles_list() {
    local input rows result
    input="$(_mod_sys_admin_request system.network.wifi.profiles.list)" || {
        _mod_sys_admin_error invalid_request "expected system.network.wifi.profiles.list v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.network.wifi.profiles.list takes no inputs"
        return 0
    }
    rows="$(_mod_sys_wifi_read profiles)" || {
        _mod_sys_admin_error unavailable "NetworkManager Wi-Fi profiles unavailable"
        return 0
    }
    result="$(printf '%s' "$rows" | _mod_sys_network_surface wifi-profiles-list)" || {
        _mod_sys_admin_error unavailable "NetworkManager Wi-Fi profiles normalization failed"
        return 0
    }
    printf '%s\n' "$result"
}


# Experimental generic administration capabilities. Platform-specific package
# and service mechanics stay in Core; this module gives them host-domain meaning.
_mod_sys_admin_platform() {
    [ -n "${_IGOR_LOADER_DIR:-}" ] || return 1
    source "${_IGOR_LOADER_DIR}/core/lib/distro.sh"
    source "${_IGOR_LOADER_DIR}/core/lib/pkg.sh"
    if [ -z "${IGOR_DISTRO_FAMILY:-}" ] || [ -z "${IGOR_DISTRO_ID:-}" ]; then
        igor_detect_distro
    fi
    case "${IGOR_DISTRO_FAMILY:-unknown}" in
        debian|arch) return 0 ;;
        *) return 1 ;;
    esac
}

_mod_sys_admin_request() {
    local expected="$1" request
    IFS= read -r request || return 1
    printf '%s' "$request" | "${IGOR_PYTHON:-python3}" -c '
import json,sys
try:
    value=json.load(sys.stdin)
except ValueError:
    raise SystemExit(1)
if (not isinstance(value,dict) or value.get("api_version") != 2 or
        value.get("contribution_id") != sys.argv[1] or
        not isinstance(value.get("input"),dict)):
    raise SystemExit(1)
print(json.dumps(value["input"],separators=(",",":")))
' "$expected"
}

_mod_sys_admin_error() {
    local code="$1" message="$2"
    ADMIN_CODE="$code" ADMIN_MESSAGE="$message" "${IGOR_PYTHON:-python3}" - <<'PY'
import json,os
print(json.dumps({"status":"error","error":{"code":os.environ["ADMIN_CODE"],
      "message":os.environ["ADMIN_MESSAGE"]}},separators=(",",":")))
PY
}

system__host_summary() {
    local input distro_id kernel architecture uptime_seconds package_manager
    input="$(_mod_sys_admin_request system.host.summary)" || {
        _mod_sys_admin_error invalid_request "expected system.host.summary v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.host.summary takes no inputs"
        return 0
    }
    _mod_sys_admin_platform || {
        _mod_sys_admin_error unsupported "host administration currently supports Debian and Arch families"
        return 0
    }
    distro_id="${IGOR_DISTRO_ID:-unknown}"
    kernel="$(uname -r 2>/dev/null || printf unknown)"
    architecture="$(uname -m 2>/dev/null || printf unknown)"
    uptime_seconds="$(awk '{printf "%d",$1}' /proc/uptime 2>/dev/null)"
    [[ "$uptime_seconds" =~ ^[0-9]+$ ]] || uptime_seconds=0
    case "$IGOR_DISTRO_FAMILY" in
        debian) package_manager=apt ;;
        arch) package_manager=pacman ;;
    esac
    ADMIN_DISTRO_ID="$distro_id" ADMIN_FAMILY="$IGOR_DISTRO_FAMILY" ADMIN_KERNEL="$kernel" \
    ADMIN_ARCH="$architecture" ADMIN_UPTIME="$uptime_seconds" ADMIN_PACKAGE_MANAGER="$package_manager" \
        "${IGOR_PYTHON:-python3}" - <<'PY'
import json,os
print(json.dumps({"status":"ok","result":{
    "distro_id":os.environ["ADMIN_DISTRO_ID"][:128],
    "distro_family":os.environ["ADMIN_FAMILY"],
    "kernel":os.environ["ADMIN_KERNEL"][:256],
    "architecture":os.environ["ADMIN_ARCH"][:64],
    "uptime_seconds":int(os.environ["ADMIN_UPTIME"]),
    "package_manager":os.environ["ADMIN_PACKAGE_MANAGER"],
}},separators=(",",":")))
PY
}

system__package_updates_list() {
    local input packages count preview
    input="$(_mod_sys_admin_request system.package.updates.list)" || {
        _mod_sys_admin_error invalid_request "expected system.package.updates.list v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.package.updates.list takes no inputs"
        return 0
    }
    _mod_sys_admin_platform || {
        _mod_sys_admin_error unsupported "package update discovery supports Debian and Arch families"
        return 0
    }
    packages="$(pkg_updates_list)" || {
        _mod_sys_admin_error unavailable "package update query failed"
        return 0
    }
    count="$(printf '%s\n' "$packages" | awk 'NF{n++} END{print n+0}')"
    preview="$(printf '%s\n' "$packages" | awk 'NF' | head -100 | head -c 4096)"
    ADMIN_FAMILY="$IGOR_DISTRO_FAMILY" ADMIN_COUNT="$count" ADMIN_TEXT="$preview" \
        "${IGOR_PYTHON:-python3}" - <<'PY'
import json,os
print(json.dumps({"status":"ok","result":{
    "distro_family":os.environ["ADMIN_FAMILY"],
    "count":int(os.environ["ADMIN_COUNT"]),
    "packages":os.environ.get("ADMIN_TEXT",""),
    "source":"platform.package_updates",
}},separators=(",",":")))
PY
}

system__package_cleanup_preview() {
    local input candidates count preview cache_path cache_bytes cache tab
    input="$(_mod_sys_admin_request system.package.cleanup.preview)" || {
        _mod_sys_admin_error invalid_request "expected system.package.cleanup.preview v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.package.cleanup.preview takes no inputs"
        return 0
    }
    _mod_sys_admin_platform || {
        _mod_sys_admin_error unsupported "package cleanup discovery supports Debian and Arch families"
        return 0
    }
    candidates="$(pkg_cleanup_candidates)" || {
        _mod_sys_admin_error unavailable "package cleanup candidate query failed"
        return 0
    }
    cache="$(pkg_cache_usage)" || {
        _mod_sys_admin_error unavailable "package cache query failed"
        return 0
    }
    tab="$(printf '\t')"
    IFS="$tab" read -r cache_path cache_bytes <<< "$cache"
    [[ "$cache_bytes" =~ ^[0-9]+$ ]] || cache_bytes=0
    count="$(printf '%s\n' "$candidates" | awk 'NF{n++} END{print n+0}')"
    preview="$(printf '%s\n' "$candidates" | awk 'NF' | head -100 | head -c 4096)"
    ADMIN_FAMILY="$IGOR_DISTRO_FAMILY" ADMIN_COUNT="$count" ADMIN_TEXT="$preview" \
    ADMIN_CACHE_PATH="$cache_path" ADMIN_CACHE_BYTES="$cache_bytes" \
        "${IGOR_PYTHON:-python3}" - <<'PY'
import json,os
print(json.dumps({"status":"ok","result":{
    "distro_family":os.environ["ADMIN_FAMILY"],
    "candidate_count":int(os.environ["ADMIN_COUNT"]),
    "candidates":os.environ.get("ADMIN_TEXT",""),
    "cache_path":os.environ.get("ADMIN_CACHE_PATH","")[:256],
    "cache_bytes":int(os.environ["ADMIN_CACHE_BYTES"]),
    "source":"platform.package_cleanup",
}},separators=(",",":")))
PY
}

system__service_list() {
    local input rows count preview
    input="$(_mod_sys_admin_request system.service.list)" || {
        _mod_sys_admin_error invalid_request "expected system.service.list v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.service.list takes no inputs"
        return 0
    }
    _mod_sys_admin_platform || {
        _mod_sys_admin_error unsupported "service discovery supports Debian and Arch families"
        return 0
    }
    rows="$(svc_list_query)" || {
        _mod_sys_admin_error unavailable "systemd service query failed"
        return 0
    }
    count="$(printf '%s\n' "$rows" | awk 'NF{n++} END{print n+0}')"
    preview="$(printf '%s\n' "$rows" | awk 'NF' | head -80 | head -c 4096)"
    ADMIN_COUNT="$count" ADMIN_TEXT="$preview" "${IGOR_PYTHON:-python3}" - <<'PY'
import json,os
print(json.dumps({"status":"ok","result":{
    "count":int(os.environ["ADMIN_COUNT"]),
    "services":os.environ.get("ADMIN_TEXT",""),
    "source":"platform.systemd_services",
}},separators=(",",":")))
PY
}

system__service_status() {
    local input unit state
    input="$(_mod_sys_admin_request system.service.status)" || {
        _mod_sys_admin_error invalid_request "expected system.service.status v2 request"
        return 0
    }
    unit="$(printf '%s' "$input" | "${IGOR_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin).get("unit",""))')" || unit=""
    [[ "$unit" =~ ^[A-Za-z0-9][A-Za-z0-9_.@:+-]*$ ]] || {
        _mod_sys_admin_error invalid_request "invalid systemd unit"
        return 0
    }
    _mod_sys_admin_platform || {
        _mod_sys_admin_error unsupported "service status supports Debian and Arch families"
        return 0
    }
    state="$(svc_query "$unit")" || {
        _mod_sys_admin_error unavailable "service is unknown or its state could not be read"
        return 0
    }
    ADMIN_UNIT="$unit" ADMIN_STATE="$state" "${IGOR_PYTHON:-python3}" - <<'PY'
import json,os
print(json.dumps({"status":"ok","result":{
    "unit":os.environ["ADMIN_UNIT"],
    "state":os.environ["ADMIN_STATE"][:64],
    "source":"platform.service_query",
}},separators=(",",":")))
PY
}

system__logs_summary() {
    local input recent warning errors latest timeout_seconds
    input="$(_mod_sys_admin_request system.logs.summary)" || {
        _mod_sys_admin_error invalid_request "expected system.logs.summary v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _mod_sys_admin_error invalid_request "system.logs.summary takes no inputs"
        return 0
    }
    command -v journalctl >/dev/null 2>&1 || {
        _mod_sys_admin_error unavailable "journalctl is not available"
        return 0
    }
    command -v timeout >/dev/null 2>&1 || {
        _mod_sys_admin_error unavailable "timeout is not available"
        return 0
    }
    timeout_seconds="${IGOR_PLATFORM_QUERY_TIMEOUT_SECONDS:-5}"
    [[ "$timeout_seconds" =~ ^[1-9][0-9]?$ ]] || timeout_seconds=5
    recent="$(LC_ALL=C timeout "$timeout_seconds" journalctl --quiet -n 40 --no-pager --output=short-iso 2>/dev/null)" || {
        _mod_sys_admin_error unavailable "journal query failed or is not permitted"
        return 0
    }
    warning="$(LC_ALL=C timeout "$timeout_seconds" journalctl --quiet -p warning -n 40 --no-pager --output=short-iso 2>/dev/null)" || {
        _mod_sys_admin_error unavailable "journal warning query failed or is not permitted"
        return 0
    }
    errors="$(LC_ALL=C timeout "$timeout_seconds" journalctl --quiet -p err -n 40 --no-pager --output=short-iso 2>/dev/null)" || {
        _mod_sys_admin_error unavailable "journal error query failed or is not permitted"
        return 0
    }
    latest="$(printf '%s\n' "$recent" | awk 'NF { stamp=$1 } END { print stamp }' | head -c 128)"
    ADMIN_RECENT="$(printf '%s\n' "$recent" | awk 'NF{n++} END{print n+0}')" \
    ADMIN_WARNING="$(printf '%s\n' "$warning" | awk 'NF{n++} END{print n+0}')" \
    ADMIN_ERRORS="$(printf '%s\n' "$errors" | awk 'NF{n++} END{print n+0}')" \
    ADMIN_LATEST="$latest" "${IGOR_PYTHON:-python3}" - <<'PY'
import json,os
print(json.dumps({"status":"ok","result":{
    "recent_count":int(os.environ["ADMIN_RECENT"]),
    "warning_count":int(os.environ["ADMIN_WARNING"]),
    "error_count":int(os.environ["ADMIN_ERRORS"]),
    "latest_entry_at":os.environ.get("ADMIN_LATEST","")[:128],
    "source":"systemd.journal",
}},separators=(",",":")))
PY
}

system__privileged_marker() {
    _mod_sys_admin_error authority "privileged System actions must execute through Core's reviewed adapter"
}

# REQUIRED — called at igor startup
system__register() {
    igor_register_hook "health"      "system__health"
    igor_register_hook "diagnose"    "system__diagnose"
    igor_register_hook "ai_context"  "system__ai_context"
    igor_register_hook "ai_tools"    "system__ai_tools"
    igor_register_hook "mailcmd"     "system__mailcmd_verbs"
    igor_register_hook "notify"      "system__notify_sources"
    igor_register_hook "recovery"    "system__recovery_hooks"
    return 0
}

# REQUIRED — called by health status bar
# Returns: "status:message"
system__health() {
    local temp issues=""

    # CPU temperature — try vcgencmd (Pi), fall back to /sys thermal zone
    if igor_has_bin vcgencmd; then
        temp=$(vcgencmd measure_temp 2>/dev/null | grep -o '[0-9]*\.[0-9]*')
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    fi
    if [ -n "$temp" ]; then
        local temp_int; temp_int=$(printf "%.0f" "$temp" 2>/dev/null || echo 0)
        [ "$temp_int" -ge 85 ] && issues+="CPU ${temp}°C CRITICAL; "
        [ "$temp_int" -ge 75 ] && [ "$temp_int" -lt 85 ] && issues+="CPU ${temp}°C; "
    fi

    # Undervoltage (Pi-specific, no-op on other hardware)
    if igor_has_bin vcgencmd; then
        local throttle; throttle=$(vcgencmd get_throttled 2>/dev/null | grep -o '0x[0-9a-f]*')
        case "$throttle" in
            0x5000[05]|0x[0-9a-f]*0005*) issues+="undervoltage; " ;;
        esac
    fi

    if [ -n "$issues" ]; then
        echo "warn:${issues%; }"
    else
        local msg="OK"
        [ -n "$temp" ] && msg="CPU ${temp}°C"
        echo "ok:${msg}"
    fi
    return 0
}

# OPTIONAL — called by IGOR DIAGNOSE aggregator
# Output one line per check: CHECK:<name>:<status>:<message>
system__diagnose() {
    # CPU temperature
    local temp=""
    if igor_has_bin vcgencmd; then
        temp=$(vcgencmd measure_temp 2>/dev/null | grep -o '[0-9]*\.[0-9]*')
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    fi
    if [ -n "$temp" ]; then
        local ti; ti=$(printf "%.0f" "$temp" 2>/dev/null || echo 0)
        if   [ "$ti" -ge 85 ]; then echo "CHECK:cpu_temp:fail:CPU temperature ${temp}°C — CRITICAL (≥85°C)"
        elif [ "$ti" -ge 75 ]; then echo "CHECK:cpu_temp:warn:CPU temperature ${temp}°C — elevated (≥75°C)"
        else                         echo "CHECK:cpu_temp:ok:CPU temperature ${temp}°C"
        fi
    else
        echo "CHECK:cpu_temp:skip:temperature sensor not available"
    fi

    # Undervoltage (Pi-specific)
    if igor_has_bin vcgencmd; then
        local throttle; throttle=$(vcgencmd get_throttled 2>/dev/null | grep -o '0x[0-9a-f]*')
        if [ -n "$throttle" ] && [ "$throttle" != "0x0" ]; then
            echo "CHECK:undervoltage:warn:vcgencmd reports throttle flags: ${throttle} — check power supply"
        else
            echo "CHECK:undervoltage:ok:no undervoltage or throttling detected"
        fi
    fi

    # Root filesystem usage
    local root_pct
    root_pct=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    if [ -n "$root_pct" ]; then
        if   [ "$root_pct" -ge 90 ]; then echo "CHECK:rootfs:fail:root filesystem ${root_pct}% full — CRITICAL"
        elif [ "$root_pct" -ge 75 ]; then echo "CHECK:rootfs:warn:root filesystem ${root_pct}% full"
        else                              echo "CHECK:rootfs:ok:root filesystem ${root_pct}% used"
        fi
    fi

    # Swap usage
    local swap_pct
    swap_pct=$(free 2>/dev/null | awk '/^Swap:/{if($2>0) printf "%d", $3*100/$2; else print 0}')
    if [ -n "$swap_pct" ] && [ "$swap_pct" -gt 0 ]; then
        if   [ "$swap_pct" -ge 85 ]; then echo "CHECK:swap:fail:swap ${swap_pct}% used — CRITICAL"
        elif [ "$swap_pct" -ge 60 ]; then echo "CHECK:swap:warn:swap ${swap_pct}% used — elevated"
        else                              echo "CHECK:swap:ok:swap ${swap_pct}% used"
        fi
    fi
}

# OPTIONAL — called by AI context builder
system__ai_context() {
    local ctx=""
    ctx+="\n=== SYSTEM ===\n"

    # Model identification — Pi-specific or generic
    if [ -f /proc/device-tree/model ]; then
        ctx+="Model: $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)\n"
    fi
    ctx+="OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')\n"
    ctx+="Kernel: $(uname -r 2>/dev/null)\n"
    ctx+="Arch: $(uname -m 2>/dev/null)\n"
    ctx+="Uptime: $(uptime -p 2>/dev/null || uptime 2>/dev/null)\n"
    ctx+="Tier: ${IGOR_TIER:-unknown}\n"

    # Temperature
    local temp=""
    if igor_has_bin vcgencmd; then
        temp=$(vcgencmd measure_temp 2>/dev/null | grep -o '[0-9]*\.[0-9]*')
        ctx+="CPU temp: ${temp}°C\n"
        local throttle; throttle=$(vcgencmd get_throttled 2>/dev/null)
        ctx+="Throttle flags: ${throttle:-unknown}\n"
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        ctx+="CPU temp: ${temp}°C\n"
    fi

    # Memory availability is supplied once by the Igor System Model context.
    ctx+="$(free -h 2>/dev/null | grep -E '^Swap:')\n"
    ctx+="Load: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)\n"

    # Recent I/O errors
    local io_errors
    io_errors=$(dmesg 2>/dev/null | grep -i "i/o error\|mmcblk.*error\|end_request" | tail -5)
    if [ -n "$io_errors" ]; then
        ctx+="\n=== RECENT I/O ERRORS ===\n${io_errors}\n"
    fi

    echo -e "$ctx"
    return 0
}

# OPTIONAL — called by AI tool registrar
system__ai_tools() {
    return 0
}

# OPTIONAL — mailcmd verbs handled by this module
system__mailcmd_verbs() {
    echo "sysstatus sysupdate sysreboot"
    return 0
}

# OPTIONAL — notification sources
system__notify_sources() {
    return 0
}

# OPTIONAL — recovery hooks
system__recovery_hooks() {
    return 0
}
