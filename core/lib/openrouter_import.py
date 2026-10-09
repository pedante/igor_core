"""Value-free discovery and literal-only selection of legacy OpenRouter inputs.

This module never sources a file. Its only write caller is the private staging
boundary, which passes selected bytes directly to the managed secret service.
"""

from __future__ import annotations

import os
import re
import stat
import sys
from pathlib import Path

from secret_refs import SecretReferenceError

_ASSIGNMENT = re.compile(rb"(?:export[ \t]+)?OPENROUTER_API_KEY[ \t]*=[ \t]*(.*)")
_OTHER_ASSIGNMENT = re.compile(rb"(?:export[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*(.*)")
_LITERAL = re.compile(rb"[A-Za-z0-9._:/+\-=]{1,16384}")
_LIMIT = 65536


def _file_bytes(path: Path) -> bytes:
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise SecretReferenceError("legacy source contains a link")
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError as exc:
        raise SecretReferenceError("legacy source unavailable") from exc
    try:
        info = os.fstat(fd)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or
                info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600 or
                not 1 <= info.st_size <= _LIMIT):
            raise SecretReferenceError("legacy source is unsafe")
        data = os.read(fd, _LIMIT + 1)
        if len(data) > _LIMIT:
            raise SecretReferenceError("legacy source exceeds limit")
        return data
    finally:
        os.close(fd)


def _literal(value: bytes) -> bytes:
    value = value.strip()
    if len(value) >= 2 and value[0:1] == value[-1:] and value[0:1] in {b"'", b'"'}:
        value = value[1:-1]
    if not _LITERAL.fullmatch(value):
        raise SecretReferenceError("legacy assignment is not literal")
    return value


def _selected_assignment(path: Path) -> bytes:
    matches = []
    for raw in _file_bytes(path).splitlines():
        line = raw.strip()
        if not line or line.startswith(b"#"):
            continue
        match = _ASSIGNMENT.fullmatch(line)
        if match:
            matches.append(_literal(match.group(1)))
        elif b"OPENROUTER_API_KEY" in line:
            raise SecretReferenceError("legacy assignment is ambiguous")
        else:
            other = _OTHER_ASSIGNMENT.fullmatch(line)
            if other is None:
                raise SecretReferenceError("legacy env file contains executable syntax")
            _literal(other.group(1))
    if len(matches) != 1:
        raise SecretReferenceError("legacy assignment is missing or ambiguous")
    return matches[0]


def _raw_key(path: Path) -> bytes:
    data = _file_bytes(path).strip()
    return _literal(data)


def _paths(root: Path, home: Path, secret_root: Path) -> list[tuple[str, Path, str]]:
    result = [
        ("file:secrets/openrouter.key", secret_root / "openrouter.key", "file_import"),
        ("home:.nexus_or_key", home / ".nexus_or_key", "home_import"),
    ]
    for directory in (secret_root, root / "config/variables", root):
        if not directory.is_dir() or directory.is_symlink():
            continue
        label = ("secrets" if directory == secret_root else
                 "config/variables" if directory == root / "config/variables" else "root")
        for path in sorted(directory.glob("*.env")):
            if not re.fullmatch(r"[A-Za-z0-9._-]{1,128}\.env", path.name):
                continue
            result.append((f"env_file:{label}/{path.name}", path, "env_file_import"))
    return result


def candidates(root: Path, *, home: Path, secret_root: Path,
               environment: dict[str, str]) -> list[dict[str, str]]:
    rows = [{"source": "private_input", "status": "available", "kind": "private_input"}]
    ambient = environment.get("OPENROUTER_API_KEY")
    if ambient:
        try:
            _literal(ambient.encode("ascii"))
            status = "available"
        except (UnicodeEncodeError, SecretReferenceError):
            status = "unsafe"
        rows.append({"source": "environment:OPENROUTER_API_KEY",
                     "status": status, "kind": "environment_import"})
    for ident, path, kind in _paths(root, home, secret_root):
        if not path.exists() and not path.is_symlink():
            continue
        try:
            _selected_assignment(path) if kind == "env_file_import" else _raw_key(path)
            status = "available"
        except SecretReferenceError:
            status = "unsafe"
        rows.append({"source": ident, "status": status, "kind": kind})
    return rows


def selected(root: Path, *, home: Path, secret_root: Path,
             environment: dict[str, str], source: str) -> tuple[bytes, str]:
    if source == "environment:OPENROUTER_API_KEY":
        value = environment.get("OPENROUTER_API_KEY")
        if not value:
            raise SecretReferenceError("selected environment source unavailable")
        try:
            return _literal(value.encode("ascii")), "environment_import"
        except UnicodeEncodeError as exc:
            raise SecretReferenceError("selected environment source is unsafe") from exc
    for ident, path, kind in _paths(root, home, secret_root):
        if ident == source:
            return (_selected_assignment(path) if kind == "env_file_import" else _raw_key(path)), kind
    raise SecretReferenceError("unknown legacy source")


def _loader_projection(path: Path) -> str:
    aliases = re.compile(rb"(?:export[ \t]+)?(?:OPENROUTER_API_KEY|OR_API_KEY|NEXUS_API_KEY)[ \t]*=[ \t]*(.*)")
    selected_name = re.compile(rb"(?:OPENROUTER_API_KEY|OR_API_KEY|NEXUS_API_KEY)[ \t]*=")
    lines = []
    for line in _file_bytes(path).splitlines():
        stripped = line.strip()
        match = aliases.fullmatch(stripped)
        if match:
            _literal(match.group(1))
        elif selected_name.search(stripped) and not stripped.startswith(b"#"):
            raise SecretReferenceError("ambiguous selected loader assignment")
        else:
            lines.append(line)
    return b"\n".join(lines).decode("utf-8")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3 or sys.argv[1] != "loader-projection":
            raise SystemExit(2)
        print(_loader_projection(Path(sys.argv[2])))
    except (OSError, ValueError):
        raise SystemExit(1) from None
