"""Bounded S6 path inspection, completion and permission administration."""

from __future__ import annotations

import json
import os
import pwd
import grp
import re
import stat
import sys
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import quote

from account_query import AccountQueryError, resolve_group, resolve_user

MAX_CANDIDATES = 128
_INSPECT_ROOTS = (
    Path("/etc"),
    Path("/home"),
    Path("/srv"),
    Path("/var"),
    Path("/opt"),
    Path("/mnt"),
    Path("/media"),
    Path("/usr/local"),
)
_MUTATION_ROOTS = (
    Path("/home"),
    Path("/srv"),
    Path("/opt"),
    Path("/mnt"),
    Path("/media"),
    Path("/usr/local"),
    Path("/var/lib"),
    Path("/var/www"),
)
_MODE = re.compile(r"0[0-7]{3}")


class AccessError(ValueError):
    """Unsafe, malformed or unsupported path/account operation."""


def _absolute_from_relative(value: Any) -> Path:
    if not isinstance(value, str) or not value or len(value) > 512:
        raise AccessError("path input is invalid")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or "\x00" in value:
        raise AccessError("path escapes the declared root")
    return Path("/") / value


def _relative_from_absolute(path: Path) -> str:
    text = path.as_posix()
    if not text.startswith("/") or text == "/":
        raise AccessError("root path is not an eligible candidate")
    return text.lstrip("/")


def _under(path: Path, roots: tuple[Path, ...], *, allow_root: bool = True) -> bool:
    for root in roots:
        try:
            relative = path.relative_to(root)
        except ValueError:
            continue
        if allow_root or relative.parts:
            return True
    return False


def _safe_existing_path(path: Path, *, mutation: bool = False) -> os.stat_result:
    if mutation and not _under(path, _MUTATION_ROOTS, allow_root=False):
        raise AccessError("path is outside reviewed permission-change roots")
    if not mutation and not _under(path, _INSPECT_ROOTS):
        raise AccessError("path is outside bounded inspection roots")
    current = Path("/")
    for part in path.parts[1:]:
        current /= part
        try:
            info = os.lstat(current)
        except OSError as exc:
            raise AccessError("path is not currently present") from exc
        if stat.S_ISLNK(info.st_mode):
            raise AccessError("symbolic-link paths are not supported")
    return os.lstat(path)


def _kind(mode: int) -> str:
    if stat.S_ISREG(mode):
        return "file"
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISCHR(mode):
        return "character_device"
    if stat.S_ISBLK(mode):
        return "block_device"
    if stat.S_ISFIFO(mode):
        return "fifo"
    if stat.S_ISSOCK(mode):
        return "socket"
    return "other"


def path_object_id(path: Path) -> str:
    encoded = quote(path.as_posix(), safe="/._-+%")
    return "path:" + encoded


def inspect_path(relative: Any, *, mutation: bool = False) -> dict[str, Any]:
    path = _absolute_from_relative(relative)
    info = _safe_existing_path(path, mutation=mutation)
    try:
        owner = pwd.getpwuid(info.st_uid).pw_name
    except KeyError:
        owner = str(info.st_uid)
    try:
        group = grp.getgrgid(info.st_gid).gr_name
    except KeyError:
        group = str(info.st_gid)
    return {
        "object_id": path_object_id(path),
        "path": path.as_posix(),
        "kind": _kind(info.st_mode),
        "uid": int(info.st_uid),
        "gid": int(info.st_gid),
        "owner": owner,
        "group": group,
        "mode": format(stat.S_IMODE(info.st_mode), "04o"),
        "size_bytes": int(info.st_size),
        "device": int(info.st_dev),
        "inode": int(info.st_ino),
    }


def _prefix_parts(prefix: Any) -> tuple[Path, str]:
    if prefix in {None, "", "/"}:
        return Path("/"), ""
    if not isinstance(prefix, str) or len(prefix) > 512 or "\x00" in prefix:
        raise AccessError("path prefix is invalid")
    if not prefix.startswith("/"):
        prefix = "/" + prefix
    pure = PurePosixPath(prefix)
    if ".." in pure.parts:
        raise AccessError("path prefix escapes its root")
    if prefix.endswith("/"):
        return Path(pure.as_posix()), ""
    return Path(pure.parent.as_posix()), pure.name


def path_candidates(prefix: Any) -> list[dict[str, Any]]:
    parent, needle = _prefix_parts(prefix)
    if parent == Path("/"):
        entries = list(_INSPECT_ROOTS)
    else:
        _safe_existing_path(parent, mutation=False)
        if not parent.is_dir():
            raise AccessError("path prefix parent is not a directory")
        try:
            entries = sorted(parent.iterdir(), key=lambda item: item.name.casefold())
        except OSError as exc:
            raise AccessError("path prefix directory is unavailable") from exc
    rows: list[dict[str, Any]] = []
    for path in entries:
        if needle:
            if parent == Path("/"):
                requested = "/" + needle
                if not path.as_posix().casefold().startswith(requested.casefold()):
                    continue
            elif not path.name.casefold().startswith(needle.casefold()):
                continue
        if not _under(path, _INSPECT_ROOTS):
            continue
        try:
            info = os.lstat(path)
        except OSError:
            continue
        if stat.S_ISLNK(info.st_mode):
            continue
        if not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
            continue
        label = path.as_posix() + ("/" if stat.S_ISDIR(info.st_mode) else "")
        rows.append({
            "value": _relative_from_absolute(path),
            "label": label,
            "detail": (
                "directory" if stat.S_ISDIR(info.st_mode)
                else f"file · {format(stat.S_IMODE(info.st_mode), '04o')}"
            ),
            "object_id": path_object_id(path),
        })
        if len(rows) >= MAX_CANDIDATES:
            break
    return rows


def _inputs(raw: Any, required: set[str]) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise AccessError("permission inputs must be an object")
    allowed = {"path", "user", "group", "mode"}
    unknown = set(raw) - allowed
    if unknown:
        raise AccessError(f"unknown permission input {min(unknown)}")
    missing = required - set(raw)
    if missing:
        raise AccessError(f"missing permission input {min(missing)}")
    return raw


def plan_owner(raw: Any) -> dict[str, Any]:
    inputs = _inputs(raw, {"path", "user"})
    path = inspect_path(inputs["path"], mutation=True)
    try:
        user = resolve_user(inputs["user"])
    except AccountQueryError as exc:
        raise AccessError(str(exc)) from exc
    return {
        "action": "owner_set",
        "path": path["path"],
        "path_object_id": path["object_id"],
        "expected_device": path["device"],
        "expected_inode": path["inode"],
        "uid": user["uid"],
        "user": user["object_id"],
        "commands": [["sudo", "-n", "--", "chown", "--", str(user["uid"]), path["path"]]],
    }


def plan_group(raw: Any) -> dict[str, Any]:
    inputs = _inputs(raw, {"path", "group"})
    path = inspect_path(inputs["path"], mutation=True)
    try:
        group = resolve_group(inputs["group"])
    except AccountQueryError as exc:
        raise AccessError(str(exc)) from exc
    return {
        "action": "group_set",
        "path": path["path"],
        "path_object_id": path["object_id"],
        "expected_device": path["device"],
        "expected_inode": path["inode"],
        "gid": group["gid"],
        "group": group["object_id"],
        "commands": [["sudo", "-n", "--", "chgrp", "--", str(group["gid"]), path["path"]]],
    }


def plan_mode(raw: Any) -> dict[str, Any]:
    inputs = _inputs(raw, {"path", "mode"})
    path = inspect_path(inputs["path"], mutation=True)
    mode = inputs["mode"]
    if not isinstance(mode, str) or not _MODE.fullmatch(mode):
        raise AccessError("mode must be an explicit 0000..0777 value")
    return {
        "action": "mode_set",
        "path": path["path"],
        "path_object_id": path["object_id"],
        "expected_device": path["device"],
        "expected_inode": path["inode"],
        "mode": mode,
        "commands": [["sudo", "-n", "--", "chmod", "--", mode, path["path"]]],
    }


def verify(raw: Any, action: str) -> dict[str, Any]:
    if action == "owner":
        plan = plan_owner(raw)
        current = inspect_path(raw["path"], mutation=True)
        ok = current["uid"] == plan["uid"]
        expected = str(plan["uid"])
        observed = str(current["uid"])
        check_id = "system.permissions.owner.matches"
    elif action == "group":
        plan = plan_group(raw)
        current = inspect_path(raw["path"], mutation=True)
        ok = current["gid"] == plan["gid"]
        expected = str(plan["gid"])
        observed = str(current["gid"])
        check_id = "system.permissions.group.matches"
    elif action == "mode":
        plan = plan_mode(raw)
        current = inspect_path(raw["path"], mutation=True)
        ok = current["mode"] == plan["mode"]
        expected = plan["mode"]
        observed = current["mode"]
        check_id = "system.permissions.mode.matches"
    else:
        raise AccessError("unknown permission verification action")
    result = {
        "source": "platform.path_stat",
        "check_id": check_id,
        "object_id": current["object_id"],
        "path": current["path"],
        "expected": expected,
        "observed": observed,
    }
    if not ok:
        raise AccessError("permission verification failed")
    return result


def main(argv: list[str]) -> int:
    try:
        if len(argv) < 2:
            raise AccessError("missing access action")
        action = argv[1]
        if action == "candidates":
            prefix = argv[2] if len(argv) == 3 else ""
            result = path_candidates(prefix)
        elif action == "inspect" and len(argv) == 3:
            result = inspect_path(argv[2])
        elif action.startswith("plan-") and len(argv) == 3:
            raw = json.loads(argv[2])
            result = {
                "plan-owner": plan_owner,
                "plan-group": plan_group,
                "plan-mode": plan_mode,
            }[action](raw)
        elif action.startswith("verify-") and len(argv) == 3:
            raw = json.loads(argv[2])
            result = verify(raw, action.removeprefix("verify-"))
        else:
            raise AccessError("unsupported access action")
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 0
    except (AccessError, AccountQueryError, json.JSONDecodeError, OSError) as exc:
        print(f"access: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
