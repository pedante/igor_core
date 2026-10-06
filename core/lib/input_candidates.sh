# Core-owned ephemeral input candidate resolution.
#
# Candidate sources are read-only reference helpers. They cannot execute a
# capability or grant approval/privilege. The chosen value is still submitted
# through the canonical capability dispatcher.

_igor_input_candidate_root() {
    local _root="${_IGOR_LOADER_DIR:-${IGOR_DIR:-}}"
    [ -n "$_root" ] || return 2
    printf '%s\n' "$_root"
}

_igor_input_candidate_spec() {
    local _id="${1:-}" _provider="${2:-}" _input="${3:-}" _inspection _root
    [ "$#" -eq 3 ] && [ -n "$_id" ] && [ -n "$_input" ] || return 2
    declare -f igor_capability_inspect >/dev/null 2>&1 || return 2
    _inspection="$(igor_capability_inspect "$_id" "$_provider")" || return 2
    _root="$(_igor_input_candidate_root)" || return 2
    printf '%s' "$_inspection" | "${IGOR_PYTHON:-python3}" -c '
import json
import sys

input_name, lib_dir = sys.argv[1:]
sys.path.insert(0, lib_dir)
from input_candidates import CandidateError, validate_selector

inspection = json.load(sys.stdin)
if inspection.get("resolution") != "resolved":
    raise SystemExit(2)
provider = inspection.get("selected_provider")
rows = [
    row for row in inspection.get("providers", [])
    if row.get("provider") == provider and row.get("availability") == "active"
]
if len(rows) != 1:
    raise SystemExit(2)
descriptor = rows[0].get("descriptor")
if not isinstance(descriptor, dict):
    raise SystemExit(2)
inputs = descriptor.get("inputs")
properties = inputs.get("properties") if isinstance(inputs, dict) else None
spec = properties.get(input_name) if isinstance(properties, dict) else None
if not isinstance(spec, dict) or "selector" not in spec:
    raise SystemExit(2)
try:
    selector = validate_selector(spec["selector"], input_type=spec.get("type"))
except CandidateError:
    raise SystemExit(2)
print(provider)
print(spec.get("type", ""))
print(json.dumps(selector, sort_keys=True, separators=(",", ":")))
print(selector["resource_kind"])
' "$_input" "$_root/core/lib"
}

_igor_service_candidate_raw() {
    local _rows
    if ! declare -f svc_list_query >/dev/null 2>&1; then
        # shellcheck source=core/lib/pkg.sh
        source "$(_igor_input_candidate_root)/core/lib/pkg.sh"
    fi
    if ! _rows="$(svc_list_query)"; then
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"service enumeration unavailable"}'
        return 0
    fi
    printf '%s\n' "$_rows" | "${IGOR_PYTHON:-python3}" -c '
import json
import re
import sys

rows = []
seen = set()
for raw in sys.stdin:
    parts = raw.rstrip("\n").split("\t")
    if len(parts) < 3:
        continue
    unit, active, sub = parts[:3]
    if (not unit or unit in seen or
            re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.@:+-]*", unit) is None):
        continue
    seen.add(unit)
    rows.append({
        "value": unit,
        "label": unit,
        "detail": f"{active} / {sub}",
        "object_id": f"service:systemd:{unit}",
    })
rows.sort(key=lambda row: row["value"])
rows = rows[:128]
print(json.dumps({
    "state": "ready" if rows else "empty",
    "candidates": rows,
}, sort_keys=True, separators=(",", ":")))
'
}

_igor_storage_platform_candidate_raw() {
    local _kind="${1:-}" _rows
    if ! declare -f storage_mounts_query >/dev/null 2>&1; then
        # shellcheck source=core/lib/storage.sh
        source "$(_igor_input_candidate_root)/core/lib/storage.sh"
    fi
    case "$_kind" in
        mount|unmountable_mount) _rows="$(storage_mounts_query)" || _rows="" ;;
        filesystem|mountable_filesystem) _rows="$(storage_filesystems_query)" || _rows="" ;;
        *) return 2 ;;
    esac
    [ -n "$_rows" ] || {
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"storage discovery unavailable"}'
        return 0
    }
    STORAGE_ROWS="$_rows" STORAGE_KIND="$_kind" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

kind = os.environ["STORAGE_KIND"]
rows = json.loads(os.environ["STORAGE_ROWS"])
base_kind = "mount" if kind in {"mount", "unmountable_mount"} else "filesystem"
candidates = []
for row in rows[:128]:
    if kind == "mountable_filesystem":
        if row.get("mounted") is not False:
            continue
        if not str(row.get("device", "")).startswith("/dev/"):
            continue
        if row.get("filesystem_type") in {
            "swap", "crypto_LUKS", "LVM2_member", "linux_raid_member", "zfs_member"
        }:
            continue
    if kind == "unmountable_mount":
        if not str(row.get("target", "")).startswith(("/mnt/", "/media/", "/srv/")):
            continue
        if not str(row.get("source", "")).startswith("/dev/"):
            continue
    if base_kind == "mount":
        detail = "{} · {}% used · {}".format(
            row["filesystem_type"], row["use_percent"], row["source"]
        )
        label = row["target"]
    else:
        mount = "mounted at " + row["mountpoint"] if row["mounted"] else "unmounted"
        detail = "{} · {} bytes · {}".format(
            row["filesystem_type"], row["size_bytes"], mount
        )
        label = row["device"]
    candidates.append({
        "value": row["object_id"],
        "label": label,
        "detail": detail,
        "object_id": row["object_id"],
    })
print(json.dumps({
    "state": "ready" if candidates else "empty",
    "candidates": candidates,
}, sort_keys=True, separators=(",", ":")))
PY
}

_igor_storage_model_candidate_raw() {
    local _kind="${1:-}" _snapshot
    declare -f igor_model_list >/dev/null 2>&1 || {
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"System Model unavailable","freshness":"stale"}'
        return 0
    }
    _snapshot="$(igor_model_list 2>/dev/null)" || {
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"System Model read failed","freshness":"stale"}'
        return 0
    }
    STORAGE_MODEL="$_snapshot" STORAGE_KIND="$_kind" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

kind = os.environ["STORAGE_KIND"]
base_kind = "mount" if kind in {"mount", "unmountable_mount"} else "filesystem"
snapshot = json.loads(os.environ["STORAGE_MODEL"])
observer = {"mount": "storage.mounts", "filesystem": "storage.filesystems"}[base_kind]
facts = [
    fact for fact in snapshot.get("facts", [])
    if fact.get("observer") == observer
    and str(fact.get("object_id", "")).startswith(base_kind + ":")
]
attempt = snapshot.get("observers", {}).get(observer)
if isinstance(attempt, dict) and attempt.get("status") not in {"ok", None}:
    print(json.dumps({
        "state": "unavailable",
        "candidates": [],
        "reason": "storage observation is incomplete",
        "freshness": "stale",
    }, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0)
if not facts:
    if isinstance(attempt, dict) and attempt.get("status") == "ok":
        print(json.dumps({
            "state": "empty",
            "candidates": [],
            "freshness": "fresh",
            "recorded_at": attempt.get("at"),
        }, sort_keys=True, separators=(",", ":")))
    else:
        print(json.dumps({
            "state": "unavailable",
            "candidates": [],
            "reason": "fresh storage observation unavailable",
            "freshness": "stale",
        }, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0)
if any(fact.get("availability") != "known" for fact in facts):
    print(json.dumps({
        "state": "unavailable",
        "candidates": [],
        "reason": "storage observation is stale",
        "freshness": "stale",
    }, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0)

grouped = {}
for fact in facts:
    grouped.setdefault(fact["object_id"], {})[fact["property"]] = fact
candidates = []
for object_id, props in sorted(grouped.items()):
    if base_kind == "mount":
        target = props.get("mount.target", {}).get("value")
        fs_type = props.get("mount.filesystem_type", {}).get("value")
        used = props.get("mount.use_percent", {}).get("value")
        source = props.get("mount.source", {}).get("value")
        if not all(isinstance(value, str) for value in (target, fs_type, source)) or type(used) is not int:
            continue
        if kind == "unmountable_mount" and (
                not target.startswith(("/mnt/", "/media/", "/srv/"))
                or not source.startswith("/dev/")):
            continue
        label = target
        detail = f"{fs_type} · {used}% used · {source}"
    else:
        device = props.get("filesystem.device", {}).get("value")
        fs_type = props.get("filesystem.type", {}).get("value")
        size = props.get("filesystem.size_bytes", {}).get("value")
        mounted = props.get("filesystem.mounted", {}).get("value")
        mountpoint = props.get("filesystem.mountpoint", {}).get("value")
        if (not isinstance(device, str) or not isinstance(fs_type, str) or
                type(size) is not int or type(mounted) is not bool or
                not isinstance(mountpoint, str)):
            continue
        if kind == "mountable_filesystem" and (
                mounted or not device.startswith("/dev/")
                or fs_type in {"swap", "crypto_LUKS", "LVM2_member",
                               "linux_raid_member", "zfs_member"}):
            continue
        label = device
        detail = f"{fs_type} · {size} bytes · " + (
            f"mounted at {mountpoint}" if mounted else "unmounted"
        )
    candidates.append({
        "value": object_id,
        "label": label,
        "detail": detail,
        "object_id": object_id,
    })
times = [fact.get("recorded_at") for fact in facts if isinstance(fact.get("recorded_at"), str)]
expires = [fact.get("expires_at") for fact in facts if isinstance(fact.get("expires_at"), str)]
print(json.dumps({
    "state": "ready" if candidates else "empty",
    "candidates": candidates[:128],
    "freshness": "fresh",
    **({"recorded_at": max(times)} if times else {}),
    **({"expires_at": min(expires)} if expires else {}),
}, sort_keys=True, separators=(",", ":")))
PY
}

_igor_account_platform_candidate_raw() {
    local _kind="${1:-}" _rows
    if ! declare -f account_users_query >/dev/null 2>&1; then
        # shellcheck source=core/lib/access.sh
        source "$(_igor_input_candidate_root)/core/lib/access.sh"
    fi
    case "$_kind" in
        user) _rows="$(account_users_query)" || _rows="" ;;
        group) _rows="$(account_groups_query)" || _rows="" ;;
        *) return 2 ;;
    esac
    [ -n "$_rows" ] || {
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"local account discovery unavailable"}'
        return 0
    }
    ACCOUNT_ROWS="$_rows" ACCOUNT_KIND="$_kind" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

kind = os.environ["ACCOUNT_KIND"]
rows = json.loads(os.environ["ACCOUNT_ROWS"])
candidates = []
for row in rows[:128]:
    if kind == "user":
        detail = "uid {} · gid {} · {}".format(
            row["uid"], row["primary_gid"], row["home"]
        )
    else:
        detail = "gid {} · {} explicit member{}".format(
            row["gid"], row["member_count"], "" if row["member_count"] == 1 else "s"
        )
    candidates.append({
        "value": row["object_id"],
        "label": row["name"],
        "detail": detail,
        "object_id": row["object_id"],
    })
print(json.dumps({
    "state": "ready" if candidates else "empty",
    "candidates": candidates,
}, sort_keys=True, separators=(",", ":")))
PY
}

_igor_account_model_candidate_raw() {
    local _kind="${1:-}" _snapshot
    declare -f igor_model_list >/dev/null 2>&1 || {
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"System Model unavailable","freshness":"stale"}'
        return 0
    }
    _snapshot="$(igor_model_list 2>/dev/null)" || {
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"System Model read failed","freshness":"stale"}'
        return 0
    }
    ACCOUNT_MODEL="$_snapshot" ACCOUNT_KIND="$_kind" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

kind = os.environ["ACCOUNT_KIND"]
snapshot = json.loads(os.environ["ACCOUNT_MODEL"])
observer = {"user": "accounts.users", "group": "accounts.groups"}[kind]
facts = [
    fact for fact in snapshot.get("facts", [])
    if fact.get("observer") == observer
    and str(fact.get("object_id", "")).startswith(kind + ":")
]
attempt = snapshot.get("observers", {}).get(observer)
if isinstance(attempt, dict) and attempt.get("status") not in {"ok", None}:
    print(json.dumps({
        "state": "unavailable", "candidates": [],
        "reason": "account observation is incomplete", "freshness": "stale",
    }, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0)
if not facts:
    if isinstance(attempt, dict) and attempt.get("status") == "ok":
        print(json.dumps({
            "state": "empty", "candidates": [], "freshness": "fresh",
            "recorded_at": attempt.get("at"),
        }, sort_keys=True, separators=(",", ":")))
    else:
        print(json.dumps({
            "state": "unavailable", "candidates": [],
            "reason": "fresh account observation unavailable", "freshness": "stale",
        }, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0)
if any(fact.get("availability") != "known" for fact in facts):
    print(json.dumps({
        "state": "unavailable", "candidates": [],
        "reason": "account observation is stale", "freshness": "stale",
    }, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0)

grouped = {}
for fact in facts:
    grouped.setdefault(fact["object_id"], {})[fact["property"]] = fact
candidates = []
for object_id, props in sorted(grouped.items()):
    name = props.get(kind + ".name", {}).get("value")
    numeric = props.get(kind + (".uid" if kind == "user" else ".gid"), {}).get("value")
    if not isinstance(name, str) or type(numeric) is not int:
        continue
    if kind == "user":
        gid = props.get("user.primary_gid", {}).get("value")
        home = props.get("user.home", {}).get("value")
        if type(gid) is not int or not isinstance(home, str):
            continue
        detail = f"uid {numeric} · gid {gid} · {home}"
    else:
        count = props.get("group.member_count", {}).get("value")
        if type(count) is not int:
            continue
        detail = f"gid {numeric} · {count} explicit member" + ("" if count == 1 else "s")
    candidates.append({
        "value": object_id, "label": name, "detail": detail, "object_id": object_id,
    })
times = [fact.get("recorded_at") for fact in facts if isinstance(fact.get("recorded_at"), str)]
expires = [fact.get("expires_at") for fact in facts if isinstance(fact.get("expires_at"), str)]
print(json.dumps({
    "state": "ready" if candidates else "empty",
    "candidates": candidates[:128],
    "freshness": "fresh",
    **({"recorded_at": max(times)} if times else {}),
    **({"expires_at": min(expires)} if expires else {}),
}, sort_keys=True, separators=(",", ":")))
PY
}

_igor_interface_platform_candidate_raw() {
    local _rows
    if ! declare -f network_interfaces_query >/dev/null 2>&1; then
        # shellcheck source=core/lib/network.sh
        source "$(_igor_input_candidate_root)/core/lib/network.sh"
    fi
    _rows="$(network_interfaces_query)" || _rows=""
    [ -n "$_rows" ] || {
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"network interface discovery unavailable"}'
        return 0
    }
    NETWORK_ROWS="$_rows" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

rows = json.loads(os.environ["NETWORK_ROWS"])
candidates = []
for row in rows[:128]:
    addresses = ",".join(
        value for value in (row.get("ipv4_addresses"), row.get("ipv6_addresses"))
        if isinstance(value, str) and value
    ) or "no address"
    flags = []
    if row.get("wireless") is True:
        flags.append("wireless")
    if row.get("default_route_v4") is True:
        flags.append("default IPv4")
    if row.get("default_route_v6") is True:
        flags.append("default IPv6")
    detail = "{} · {}{}".format(
        row.get("operstate", "unknown"),
        addresses,
        (" · " + ", ".join(flags)) if flags else "",
    )[:512]
    candidates.append({
        "value": row["object_id"],
        "label": row["name"],
        "detail": detail,
        "object_id": row["object_id"],
    })
print(json.dumps({
    "state": "ready" if candidates else "empty",
    "candidates": candidates,
}, sort_keys=True, separators=(",", ":")))
PY
}

_igor_interface_model_candidate_raw() {
    local _snapshot
    declare -f igor_model_list >/dev/null 2>&1 || {
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"System Model unavailable","freshness":"stale"}'
        return 0
    }
    _snapshot="$(igor_model_list 2>/dev/null)" || {
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"System Model read failed","freshness":"stale"}'
        return 0
    }
    NETWORK_MODEL="$_snapshot" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

observer = "network.interfaces"
snapshot = json.loads(os.environ["NETWORK_MODEL"])
facts = [
    fact for fact in snapshot.get("facts", [])
    if fact.get("observer") == observer
    and str(fact.get("object_id", "")).startswith("interface:")
]
attempt = snapshot.get("observers", {}).get(observer)
if isinstance(attempt, dict) and attempt.get("status") not in {"ok", None}:
    print(json.dumps({
        "state": "unavailable", "candidates": [],
        "reason": "network interface observation is incomplete",
        "freshness": "stale",
    }, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0)
if not facts:
    if isinstance(attempt, dict) and attempt.get("status") == "ok":
        print(json.dumps({
            "state": "empty", "candidates": [], "freshness": "fresh",
            "recorded_at": attempt.get("at"),
        }, sort_keys=True, separators=(",", ":")))
    else:
        print(json.dumps({
            "state": "unavailable", "candidates": [],
            "reason": "fresh interface observation unavailable",
            "freshness": "stale",
        }, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0)
if any(fact.get("availability") != "known" for fact in facts):
    print(json.dumps({
        "state": "unavailable", "candidates": [],
        "reason": "network interface observation is stale",
        "freshness": "stale",
    }, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0)

grouped = {}
for fact in facts:
    grouped.setdefault(fact["object_id"], {})[fact["property"]] = fact
candidates = []
for object_id, props in sorted(grouped.items()):
    name = props.get("interface.name", {}).get("value")
    operstate = props.get("interface.operstate", {}).get("value")
    ipv4 = props.get("interface.ipv4_addresses", {}).get("value")
    ipv6 = props.get("interface.ipv6_addresses", {}).get("value")
    wireless = props.get("interface.wireless", {}).get("value")
    default_v4 = props.get("interface.default_route_v4", {}).get("value")
    default_v6 = props.get("interface.default_route_v6", {}).get("value")
    if (
        not isinstance(name, str)
        or not isinstance(operstate, str)
        or not isinstance(ipv4, str)
        or not isinstance(ipv6, str)
        or type(wireless) is not bool
        or type(default_v4) is not bool
        or type(default_v6) is not bool
    ):
        continue
    addresses = ",".join(value for value in (ipv4, ipv6) if value) or "no address"
    flags = []
    if wireless:
        flags.append("wireless")
    if default_v4:
        flags.append("default IPv4")
    if default_v6:
        flags.append("default IPv6")
    detail = (
        f"{operstate} · {addresses}" + (
            " · " + ", ".join(flags) if flags else ""
        )
    )[:512]
    candidates.append({
        "value": object_id,
        "label": name,
        "detail": detail,
        "object_id": object_id,
    })
times = [fact.get("recorded_at") for fact in facts if isinstance(fact.get("recorded_at"), str)]
expires = [fact.get("expires_at") for fact in facts if isinstance(fact.get("expires_at"), str)]
print(json.dumps({
    "state": "ready" if candidates else "empty",
    "candidates": candidates[:128],
    "freshness": "fresh",
    **({"recorded_at": max(times)} if times else {}),
    **({"expires_at": min(expires)} if expires else {}),
}, sort_keys=True, separators=(",", ":")))
PY
}

_igor_path_platform_candidate_raw() {
    local _kind="${1:-}" _prefix="${2:-}" _rows
    if ! declare -f path_candidates_query >/dev/null 2>&1; then
        # shellcheck source=core/lib/access.sh
        source "$(_igor_input_candidate_root)/core/lib/access.sh"
    fi
    case "$_kind" in
        path) _rows="$(path_candidates_query "$_prefix")" || _rows="" ;;
        mutable_path) _rows="$(mutable_path_candidates_query "$_prefix")" || _rows="" ;;
        *) return 2 ;;
    esac
    [ -n "$_rows" ] || {
        printf '%s' '{"state":"unavailable","candidates":[],"reason":"bounded path discovery unavailable"}'
        return 0
    }
    PATH_ROWS="$_rows" "${IGOR_PYTHON:-python3}" - <<'PY'
import json
import os

rows = json.loads(os.environ["PATH_ROWS"])
print(json.dumps({
    "state": "ready" if rows else "empty",
    "candidates": rows[:128],
}, sort_keys=True, separators=(",", ":")))
PY
}

igor_input_candidates_resolve() {
    local _target="${1:-}" _input="${2:-}" _query="${3:-}" _id _provider="" _spec_text _raw _result
    local _selected_provider _input_type _selector _resource_kind
    local -a _fields=()

    [ "$#" -ge 2 ] && [ "$#" -le 3 ] && [ -n "$_target" ] &&
        [[ "$_input" =~ ^[a-z][a-z0-9_]*$ ]] || return 2
    _id="${_target%%@*}"
    if [ "$_target" != "$_id" ]; then
        _provider="${_target#*@}"
        [ -n "$_provider" ] && [[ "$_provider" != *@* ]] || return 2
    fi

    _spec_text="$(_igor_input_candidate_spec "$_id" "$_provider" "$_input")" || return 2
    mapfile -t _fields <<< "$_spec_text"
    [ "${#_fields[@]}" -eq 4 ] || return 2
    _selected_provider="${_fields[0]}"
    _input_type="${_fields[1]}"
    _selector="${_fields[2]}"
    _resource_kind="${_fields[3]}"

    case "$_resource_kind" in
        service)
            _raw="$(_igor_service_candidate_raw)" || return 1
            _result="$(
                printf '%s' "$_raw" | "${IGOR_PYTHON:-python3}" "$(_igor_input_candidate_root)/core/lib/input_candidates.py" resolve-source "$_selector" "$_input_type" platform systemd.services
            )" || return 1
            ;;
        interface)
            local _model_result _state
            _raw="$(_igor_interface_model_candidate_raw)" || return 1
            _model_result="$(
                printf '%s' "$_raw" | "${IGOR_PYTHON:-python3}" "$(_igor_input_candidate_root)/core/lib/input_candidates.py" resolve-source "$_selector" "$_input_type" system_model system_model.network.interfaces
            )" || return 1
            _state="$(printf '%s' "$_model_result" | "${IGOR_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["state"])')" || return 1
            if [ "$_state" = ready ] || [ "$_state" = empty ]; then
                _result="$_model_result"
            else
                _raw="$(_igor_interface_platform_candidate_raw)" || return 1
                _result="$(
                    printf '%s' "$_raw" | "${IGOR_PYTHON:-python3}" "$(_igor_input_candidate_root)/core/lib/input_candidates.py" resolve-source "$_selector" "$_input_type" platform linux.interfaces
                )" || return 1
            fi
            ;;
        user|group)
            local _model_result _state _source_id
            _raw="$(_igor_account_model_candidate_raw "$_resource_kind")" || return 1
            _source_id="system_model.accounts.${_resource_kind}"
            _model_result="$(
                printf '%s' "$_raw" | "${IGOR_PYTHON:-python3}" "$(_igor_input_candidate_root)/core/lib/input_candidates.py" resolve-source "$_selector" "$_input_type" system_model "$_source_id"
            )" || return 1
            _state="$(printf '%s' "$_model_result" | "${IGOR_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["state"])')" || return 1
            if [ "$_state" = ready ] || [ "$_state" = empty ]; then
                _result="$_model_result"
            else
                _raw="$(_igor_account_platform_candidate_raw "$_resource_kind")" || return 1
                _result="$(
                    printf '%s' "$_raw" | "${IGOR_PYTHON:-python3}" "$(_igor_input_candidate_root)/core/lib/input_candidates.py" resolve-source "$_selector" "$_input_type" platform "linux.local_${_resource_kind}s"
                )" || return 1
            fi
            ;;
        path|mutable_path)
            _raw="$(_igor_path_platform_candidate_raw "$_resource_kind" "$_query")" || return 1
            _result="$(
                printf '%s' "$_raw" | "${IGOR_PYTHON:-python3}" "$(_igor_input_candidate_root)/core/lib/input_candidates.py" resolve-source "$_selector" "$_input_type" platform "linux.${_resource_kind}"
            )" || return 1
            ;;
        mount|filesystem|mountable_filesystem|unmountable_mount)
            local _model_result _state _source_id
            _raw="$(_igor_storage_model_candidate_raw "$_resource_kind")" || return 1
            _source_id="system_model.storage.${_resource_kind}"
            _model_result="$(
                printf '%s' "$_raw" | "${IGOR_PYTHON:-python3}" "$(_igor_input_candidate_root)/core/lib/input_candidates.py" resolve-source "$_selector" "$_input_type" system_model "$_source_id"
            )" || return 1
            _state="$(printf '%s' "$_model_result" | "${IGOR_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["state"])')" || return 1
            if [ "$_state" = ready ] || [ "$_state" = empty ]; then
                _result="$_model_result"
            else
                _raw="$(_igor_storage_platform_candidate_raw "$_resource_kind")" || return 1
                _result="$(
                    printf '%s' "$_raw" | "${IGOR_PYTHON:-python3}" "$(_igor_input_candidate_root)/core/lib/input_candidates.py" resolve-source "$_selector" "$_input_type" platform "linux.${_resource_kind}"
                )" || return 1
            fi
            ;;
        *)
            _result="$(
                "${IGOR_PYTHON:-python3}" "$(_igor_input_candidate_root)/core/lib/input_candidates.py" resolve-none "$_selector" "$_input_type"
            )" || return 1
            ;;
    esac

    "${IGOR_PYTHON:-python3}" - "$_result" "$_id" "$_selected_provider" "$_input" "$_query" <<'PY'
import json
import sys

result, capability_id, provider, input_name, query = sys.argv[1:]
print(json.dumps({
    "capability_id": capability_id,
    "provider": provider,
    "input_name": input_name,
    "query": query,
    "result": json.loads(result),
}, sort_keys=True, separators=(",", ":")))
PY
}
