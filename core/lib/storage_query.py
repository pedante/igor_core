#!/usr/bin/env python3
"""Bounded read-only Linux storage discovery for Igor Core.

This module normalizes kernel/util-linux storage data.  It owns no health
meaning, desired state or mutation path.  System observers/capabilities consume
the normalized rows and Igor's existing authority boundaries remain unchanged.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path
from typing import Any, Iterable

MAX_STORAGE_OBJECTS = 128
MAX_TEXT = 512
_PSEUDO_FILESYSTEMS = {
    "proc", "sysfs", "devpts", "cgroup", "cgroup2", "mqueue", "pstore",
    "securityfs", "debugfs", "tracefs", "configfs", "fusectl", "hugetlbfs",
    "autofs", "binfmt_misc", "rpc_pipefs", "nsfs", "tmpfs", "ramfs",
}
_MOUNT_ESCAPE = re.compile(r"\\([0-7]{3})")


class StorageQueryError(ValueError):
    """Invalid or unavailable storage discovery input."""


def _decode_mount_field(value: str) -> str:
    return _MOUNT_ESCAPE.sub(lambda match: chr(int(match.group(1), 8)), value)


def _bounded(value: Any, field: str, limit: int = MAX_TEXT) -> str:
    if not isinstance(value, str) or len(value) > limit or any(ord(char) < 32 for char in value):
        raise StorageQueryError(f"{field} is not bounded printable text")
    return value


def storage_object_id(kind: str, value: str) -> str:
    if kind not in {"mount", "filesystem"}:
        raise StorageQueryError("unsupported storage object kind")
    value = _bounded(value, "storage identity")
    if not value.startswith("/"):
        raise StorageQueryError("storage identity must be an absolute local path")
    encoded = urllib.parse.quote(value, safe="/._+-")
    ident = f"{kind}:{encoded}"
    if len(ident) > 160:
        raise StorageQueryError("storage object identity is too long")
    return ident


def parse_mountinfo(text: str, *, statvfs=os.statvfs) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in text.splitlines():
        before, separator, after = raw.partition(" - ")
        if not separator:
            continue
        left = before.split()
        right = after.split()
        if len(left) < 6 or len(right) < 2:
            continue
        target = _decode_mount_field(left[4])
        fs_type = _decode_mount_field(right[0])
        source = _decode_mount_field(right[1])
        if fs_type in _PSEUDO_FILESYSTEMS or not target.startswith("/"):
            continue
        try:
            object_id = storage_object_id("mount", target)
            info = statvfs(target)
        except (OSError, StorageQueryError, ValueError):
            continue
        if object_id in seen:
            continue
        seen.add(object_id)
        block = int(info.f_frsize or info.f_bsize or 0)
        total = max(0, block * int(info.f_blocks))
        free = max(0, block * int(info.f_bfree))
        available = max(0, block * int(info.f_bavail))
        used = max(0, total - free)
        percent = min(100, max(0, round((used * 100 / total) if total else 0)))
        options = set(left[5].split(","))
        rows.append({
            "object_id": object_id,
            "target": _bounded(target, "mount target"),
            "source": _bounded(source, "mount source"),
            "filesystem_type": _bounded(fs_type, "mount filesystem type", 128),
            "total_bytes": total,
            "used_bytes": used,
            "available_bytes": available,
            "use_percent": percent,
            "read_only": "ro" in options,
        })
        if len(rows) >= MAX_STORAGE_OBJECTS:
            break
    rows.sort(key=lambda row: (row["target"] != "/", row["target"]))
    return rows


def _iter_lsblk(nodes: Iterable[Any]) -> Iterable[dict[str, Any]]:
    for raw in nodes:
        if not isinstance(raw, dict):
            continue
        yield raw
        children = raw.get("children")
        if isinstance(children, list):
            yield from _iter_lsblk(children)


def normalize_lsblk(payload: Any) -> list[dict[str, Any]]:
    if not isinstance(payload, dict) or not isinstance(payload.get("blockdevices"), list):
        raise StorageQueryError("lsblk returned an invalid document")
    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in _iter_lsblk(payload["blockdevices"]):
        path = raw.get("path")
        fs_type = raw.get("fstype")
        dev_type = raw.get("type")
        if not isinstance(path, str) or not path.startswith("/") or not isinstance(fs_type, str) or not fs_type:
            continue
        if dev_type in {"loop", "rom"}:
            continue
        try:
            object_id = storage_object_id("filesystem", path)
        except StorageQueryError:
            continue
        if object_id in seen:
            continue
        seen.add(object_id)
        mountpoints = raw.get("mountpoints")
        if isinstance(mountpoints, list):
            mountpoint = next((item for item in mountpoints if isinstance(item, str) and item), "")
        else:
            one = raw.get("mountpoint")
            mountpoint = one if isinstance(one, str) else ""
        size = raw.get("size", 0)
        if isinstance(size, str) and size.isdigit():
            size = int(size)
        if type(size) is not int or size < 0:
            size = 0
        uuid = raw.get("uuid") if isinstance(raw.get("uuid"), str) else ""
        label = raw.get("label") if isinstance(raw.get("label"), str) else ""
        try:
            row = {
                "object_id": object_id,
                "device": _bounded(path, "filesystem device"),
                "filesystem_type": _bounded(fs_type, "filesystem type", 128),
                "uuid": _bounded(uuid, "filesystem uuid", 256),
                "label": _bounded(label, "filesystem label", 256),
                "size_bytes": size,
                "mounted": bool(mountpoint),
                "mountpoint": _bounded(mountpoint, "filesystem mountpoint"),
            }
        except StorageQueryError:
            continue
        rows.append(row)
        if len(rows) >= MAX_STORAGE_OBJECTS:
            break
    rows.sort(key=lambda row: row["device"])
    return rows


def query_mounts(path: Path = Path("/proc/self/mountinfo")) -> list[dict[str, Any]]:
    try:
        text = path.read_text(encoding="utf-8", errors="strict")
    except OSError as exc:
        raise StorageQueryError("mount information is unavailable") from exc
    return parse_mountinfo(text)


def query_filesystems(*, timeout_seconds: int = 5) -> list[dict[str, Any]]:
    if type(timeout_seconds) is not int or not 1 <= timeout_seconds <= 99:
        raise StorageQueryError("storage timeout is invalid")
    try:
        result = subprocess.run(
            [
                "lsblk", "-J", "-b", "-o",
                "PATH,TYPE,FSTYPE,UUID,LABEL,SIZE,MOUNTPOINTS",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            env={**os.environ, "LC_ALL": "C"},
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise StorageQueryError("lsblk is unavailable") from exc
    if result.returncode != 0:
        raise StorageQueryError("lsblk query failed")
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise StorageQueryError("lsblk returned invalid JSON") from exc
    return normalize_lsblk(payload)


def main(argv: list[str]) -> int:
    try:
        if len(argv) != 2 or argv[1] not in {"mounts", "filesystems"}:
            raise StorageQueryError("usage: storage_query.py {mounts|filesystems}")
        if argv[1] == "mounts":
            rows = query_mounts()
        else:
            raw_timeout = os.environ.get("IGOR_PLATFORM_QUERY_TIMEOUT_SECONDS", "5")
            if not raw_timeout.isdigit():
                raise StorageQueryError("storage timeout is invalid")
            rows = query_filesystems(timeout_seconds=int(raw_timeout))
        print(json.dumps(rows, sort_keys=True, separators=(",", ":")))
        return 0
    except (StorageQueryError, ValueError, TypeError) as exc:
        print(f"storage query: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
