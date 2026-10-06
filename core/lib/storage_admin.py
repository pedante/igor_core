"""Reviewed Core planning and verification for S5 storage administration.

This module never executes privileged commands. It validates canonical storage
identities, freezes runtime-only mount/unmount targets, checks current state and
returns exact argv for capability.sh to approve and execute.
"""

from __future__ import annotations

import json
import os
import re
import stat
import sys
import urllib.parse
from pathlib import Path, PurePosixPath
from typing import Any, Callable

from storage_query import (
    StorageQueryError,
    query_filesystems,
    query_mounts,
    storage_object_id,
)

_ALLOWED_TARGET_ROOTS = {"mnt", "media", "srv"}
_NON_MOUNTABLE_TYPES = {
    "swap",
    "crypto_LUKS",
    "LVM2_member",
    "linux_raid_member",
    "zfs_member",
}
_SAFE_DEVICE = re.compile(r"^/dev/[A-Za-z0-9_./+@:-]+$")
_SAFE_SLUG = re.compile(r"[^A-Za-z0-9._+-]+")


class StorageAdminError(ValueError):
    """Unsafe, unsupported or unavailable storage administration request."""


def _inputs(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise StorageAdminError("storage administration inputs must be an object")
    unknown = set(value) - {"filesystem", "mount", "target", "persistence"}
    if unknown:
        raise StorageAdminError(f"unknown storage input {min(unknown)}")
    persistence = value.get("persistence", "runtime_only")
    if persistence != "runtime_only":
        raise StorageAdminError("only runtime_only persistence is supported")
    return value


def _decode_object_id(kind: str, object_id: Any) -> str:
    prefix = kind + ":"
    if not isinstance(object_id, str) or not object_id.startswith(prefix):
        raise StorageAdminError(f"{kind} object identity is required")
    encoded = object_id[len(prefix):]
    try:
        decoded = urllib.parse.unquote(encoded, errors="strict")
    except UnicodeDecodeError as exc:
        raise StorageAdminError("storage object identity is not valid UTF-8") from exc
    try:
        canonical = storage_object_id(kind, decoded)
    except StorageQueryError as exc:
        raise StorageAdminError(str(exc)) from exc
    if canonical != object_id:
        raise StorageAdminError("storage object identity is not canonical")
    return decoded


def _target_from_relative(value: Any) -> str:
    if not isinstance(value, str) or not value or len(value) > 512:
        raise StorageAdminError("mount target is invalid")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise StorageAdminError("mount target escapes its storage roots")
    if path.parts[0] not in _ALLOWED_TARGET_ROOTS or len(path.parts) < 2:
        raise StorageAdminError("mount target must be below /mnt, /media or /srv")
    if any(any(ord(char) < 32 for char in part) for part in path.parts):
        raise StorageAdminError("mount target contains control characters")
    return "/" + path.as_posix()


def _default_target(row: dict[str, Any]) -> str:
    label = row.get("label")
    device = row.get("device")
    if not isinstance(device, str) or not _SAFE_DEVICE.fullmatch(device):
        raise StorageAdminError("filesystem device is not a safe local device")
    seed = label if isinstance(label, str) and label.strip() else Path(device).name
    slug = _SAFE_SLUG.sub("-", seed.strip()).strip("-._")[:64]
    if not slug:
        slug = Path(device).name.replace("/", "-")[:64]
    if not slug:
        raise StorageAdminError("cannot derive a mount target")
    return f"/mnt/{slug}"


def _filesystem_row(object_id: str, rows: list[dict[str, Any]]) -> dict[str, Any]:
    matches = [row for row in rows if row.get("object_id") == object_id]
    if len(matches) != 1:
        raise StorageAdminError("filesystem is not currently discoverable")
    row = matches[0]
    device = row.get("device")
    fs_type = row.get("filesystem_type")
    if not isinstance(device, str) or not _SAFE_DEVICE.fullmatch(device):
        raise StorageAdminError("filesystem is not a supported local device")
    if not isinstance(fs_type, str) or not fs_type or fs_type in _NON_MOUNTABLE_TYPES:
        raise StorageAdminError("filesystem type is not mountable by this capability")
    return row


def _mount_target_safe(target: str, *, lstat: Callable[[str], os.stat_result] = os.lstat) -> bool:
    try:
        _target_from_relative(target.lstrip("/"))
    except StorageAdminError:
        return False
    try:
        info = lstat(target)
    except FileNotFoundError:
        return True
    except OSError:
        return False
    return stat.S_ISDIR(info.st_mode) and not stat.S_ISLNK(info.st_mode)


def freeze_mount(
    raw_inputs: Any,
    *,
    filesystems: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    inputs = _inputs(raw_inputs)
    filesystem_id = inputs.get("filesystem")
    _decode_object_id("filesystem", filesystem_id)
    rows = query_filesystems() if filesystems is None else filesystems
    row = _filesystem_row(filesystem_id, rows)
    target = (
        _target_from_relative(inputs["target"])
        if "target" in inputs
        else _default_target(row)
    )
    device = row["device"]
    return {
        "action": "mount",
        "filesystem": filesystem_id,
        "device": device,
        "target": target,
        "persistence": "runtime_only",
        "commands": [
            ["sudo", "-n", "--", "mkdir", "-p", "--", target],
            ["sudo", "-n", "--", "mount", "--", device, target],
        ],
    }


def freeze_unmount(raw_inputs: Any) -> dict[str, Any]:
    inputs = _inputs(raw_inputs)
    mount_id = inputs.get("mount")
    target = _decode_object_id("mount", mount_id)
    target = _target_from_relative(target.lstrip("/"))
    return {
        "action": "unmount",
        "mount": mount_id,
        "target": target,
        "persistence": "runtime_only",
        "commands": [
            ["sudo", "-n", "--", "umount", "--", target],
        ],
    }


def mount_ready(
    raw_inputs: Any,
    *,
    filesystems: list[dict[str, Any]] | None = None,
    mounts: list[dict[str, Any]] | None = None,
    lstat: Callable[[str], os.stat_result] = os.lstat,
) -> dict[str, Any]:
    plan = freeze_mount(raw_inputs, filesystems=filesystems)
    rows = query_filesystems() if filesystems is None else filesystems
    row = _filesystem_row(plan["filesystem"], rows)
    if row.get("mounted") is not False:
        raise StorageAdminError("filesystem is already mounted")
    current = query_mounts() if mounts is None else mounts
    if any(item.get("target") == plan["target"] for item in current):
        raise StorageAdminError("mount target is already mounted")
    if not _mount_target_safe(plan["target"], lstat=lstat):
        raise StorageAdminError("mount target is not a safe directory path")
    return {
        "ready": True,
        "filesystem": plan["filesystem"],
        "target": plan["target"],
        "persistence": "runtime_only",
    }


def unmount_ready(
    raw_inputs: Any,
    *,
    mounts: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    plan = freeze_unmount(raw_inputs)
    current = query_mounts() if mounts is None else mounts
    matches = [row for row in current if row.get("object_id") == plan["mount"]]
    if len(matches) != 1:
        raise StorageAdminError("mount is not currently present")
    source = matches[0].get("source")
    if not isinstance(source, str) or not _SAFE_DEVICE.fullmatch(source):
        raise StorageAdminError("only local device mounts are supported")
    return {
        "ready": True,
        "mount": plan["mount"],
        "target": plan["target"],
        "source": source,
        "persistence": "runtime_only",
    }


def verify_mount(
    raw_inputs: Any,
    *,
    filesystems: list[dict[str, Any]] | None = None,
    mounts: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    plan = freeze_mount(raw_inputs, filesystems=filesystems)
    current = query_mounts() if mounts is None else mounts
    matches = [
        row for row in current
        if row.get("target") == plan["target"] and row.get("source") == plan["device"]
    ]
    if len(matches) != 1:
        raise StorageAdminError("mounted target/source verification failed")
    return {
        "source": "platform.storage.mounts",
        "check_id": "system.storage.mount.present",
        "object_id": storage_object_id("mount", plan["target"]),
        "filesystem": plan["filesystem"],
        "target": plan["target"],
        "observed": "mounted",
        "persistence": "runtime_only",
    }


def verify_unmount(
    raw_inputs: Any,
    *,
    mounts: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    plan = freeze_unmount(raw_inputs)
    current = query_mounts() if mounts is None else mounts
    if any(row.get("object_id") == plan["mount"] for row in current):
        raise StorageAdminError("mount is still present")
    return {
        "source": "platform.storage.mounts",
        "check_id": "system.storage.mount.absent",
        "object_id": plan["mount"],
        "target": plan["target"],
        "observed": "absent",
        "persistence": "runtime_only",
    }


def _run(action: str, raw_inputs: dict[str, Any]) -> dict[str, Any]:
    if action == "plan-mount":
        return freeze_mount(raw_inputs)
    if action == "plan-unmount":
        return freeze_unmount(raw_inputs)
    if action == "ready-mount":
        return mount_ready(raw_inputs)
    if action == "ready-unmount":
        return unmount_ready(raw_inputs)
    if action == "verify-mount":
        return verify_mount(raw_inputs)
    if action == "verify-unmount":
        return verify_unmount(raw_inputs)
    raise StorageAdminError("unknown storage administration action")


def main(argv: list[str]) -> int:
    try:
        if len(argv) != 3:
            raise StorageAdminError(
                "usage: storage_admin.py ACTION INPUTS_JSON"
            )
        raw = json.loads(argv[2])
        result = _run(argv[1], raw)
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 0
    except (StorageAdminError, StorageQueryError, json.JSONDecodeError, OSError) as exc:
        print(f"storage administration: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
