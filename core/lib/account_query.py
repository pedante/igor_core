"""Bounded local account discovery for the System module.

The S6 slice intentionally models local /etc/passwd and /etc/group state only.
It does not enumerate remote NSS/LDAP directories, read shadow secrets, or
perform account mutations.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

MAX_FILE_BYTES = 1024 * 1024
MAX_ROWS = 128


class AccountQueryError(ValueError):
    """Malformed or unsupported local account state."""


def _read_lines(path: Path) -> list[str]:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise AccountQueryError(f"cannot read {path}") from exc
    if len(data) > MAX_FILE_BYTES:
        raise AccountQueryError(f"{path} exceeds bounded account source size")
    try:
        return data.decode("utf-8").splitlines()
    except UnicodeDecodeError as exc:
        raise AccountQueryError(f"{path} is not UTF-8") from exc


def _name(value: str, field: str) -> str:
    if not value or len(value) > 128 or ":" in value or any(ord(ch) < 33 for ch in value):
        raise AccountQueryError(f"invalid {field}")
    return value


def _number(value: str, field: str) -> int:
    try:
        parsed = int(value, 10)
    except ValueError as exc:
        raise AccountQueryError(f"invalid {field}") from exc
    if not 0 <= parsed <= 2**32 - 1:
        raise AccountQueryError(f"{field} is outside supported range")
    return parsed


def _object_id(kind: str, number_kind: str, number: int) -> str:
    return f"{kind}:{number_kind}:{number}"


def query_users(path: Path = Path("/etc/passwd")) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen_uid: set[int] = set()
    for line in _read_lines(path):
        if not line or line.startswith("#"):
            continue
        fields = line.split(":")
        if len(fields) != 7:
            raise AccountQueryError("malformed passwd record")
        name = _name(fields[0], "user name")
        uid = _number(fields[2], "uid")
        gid = _number(fields[3], "primary gid")
        if uid in seen_uid:
            raise AccountQueryError("duplicate local uid is unsupported")
        seen_uid.add(uid)
        home = fields[5]
        shell = fields[6]
        if len(home) > 512 or len(shell) > 256 or any("\x00" in value for value in (home, shell)):
            raise AccountQueryError("account path field is invalid")
        rows.append({
            "object_id": _object_id("user", "uid", uid),
            "name": name,
            "uid": uid,
            "primary_gid": gid,
            "home": home,
            "shell": shell,
        })
        if len(rows) > MAX_ROWS:
            raise AccountQueryError("local user inventory exceeds bounded row count")
    return sorted(rows, key=lambda row: (row["uid"], row["name"]))


def query_groups(path: Path = Path("/etc/group")) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen_gid: set[int] = set()
    for line in _read_lines(path):
        if not line or line.startswith("#"):
            continue
        fields = line.split(":")
        if len(fields) != 4:
            raise AccountQueryError("malformed group record")
        name = _name(fields[0], "group name")
        gid = _number(fields[2], "gid")
        if gid in seen_gid:
            raise AccountQueryError("duplicate local gid is unsupported")
        seen_gid.add(gid)
        members = [] if not fields[3] else fields[3].split(",")
        if len(members) > 256:
            raise AccountQueryError("group membership exceeds bounded count")
        for member in members:
            _name(member, "group member")
        member_text = ",".join(members)
        if len(member_text) > 4096:
            raise AccountQueryError("group member list exceeds bounded text")
        rows.append({
            "object_id": _object_id("group", "gid", gid),
            "name": name,
            "gid": gid,
            "member_count": len(members),
            "members": member_text,
        })
        if len(rows) > MAX_ROWS:
            raise AccountQueryError("local group inventory exceeds bounded row count")
    return sorted(rows, key=lambda row: (row["gid"], row["name"]))


def resolve_user(object_id: str, rows: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    rows = query_users() if rows is None else rows
    matches = [row for row in rows if row.get("object_id") == object_id]
    if len(matches) != 1:
        raise AccountQueryError("user object is not currently present")
    return matches[0]


def resolve_group(object_id: str, rows: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    rows = query_groups() if rows is None else rows
    matches = [row for row in rows if row.get("object_id") == object_id]
    if len(matches) != 1:
        raise AccountQueryError("group object is not currently present")
    return matches[0]


def main(argv: list[str]) -> int:
    try:
        if len(argv) != 2 or argv[1] not in {"users", "groups"}:
            raise AccountQueryError("usage: account_query.py users|groups")
        rows = query_users() if argv[1] == "users" else query_groups()
        print(json.dumps(rows, sort_keys=True, separators=(",", ":")))
        return 0
    except AccountQueryError as exc:
        print(f"account query: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
