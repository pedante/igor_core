"""Small Wave E secret-reference adapter over existing private files.

Registration is trusted Core configuration. Capability input carries only an
opaque reference ID; paths and values are absent from descriptors, plans,
inspection and audit records. The Ownership Foundation will replace the
registration source without changing the reference/consumer boundary.
"""

from __future__ import annotations

import os
import re
import stat
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, TypeVar

T = TypeVar("T")
_REF_ID = re.compile(r"[a-z][a-z0-9_.:-]{0,159}")


class SecretReferenceError(ValueError):
    pass


@dataclass(frozen=True)
class SecretSource:
    reference: str
    owner: str
    purpose: str
    consumer: str
    path: Path


class SecretReferenceService:
    def __init__(self, root: Path, audit: Callable[[dict[str, str]], None] | None = None):
        self.root = root.resolve(strict=True)
        self.audit = audit or (lambda _record: None)
        self._sources: dict[str, SecretSource] = {}

    def register(self, source: SecretSource) -> None:
        if not _REF_ID.fullmatch(source.reference) or source.reference in self._sources:
            raise SecretReferenceError("invalid or duplicate secret reference")
        if not all((source.owner, source.purpose, source.consumer)):
            raise SecretReferenceError("secret reference requires owner, purpose and consumer")
        self._sources[source.reference] = source

    def inspect(self, reference: str, *, owner: str, purpose: str) -> dict[str, str | bool]:
        source = self._matching(reference, owner, purpose)
        return {"reference": reference, "owner": owner, "purpose": purpose,
                "configured": self._safe_file(source.path)}

    def _matching(self, reference: str, owner: str, purpose: str) -> SecretSource:
        source = self._sources.get(reference)
        if source is None or source.owner != owner or source.purpose != purpose:
            raise SecretReferenceError("secret reference unavailable")
        return source

    def _safe_file(self, path: Path) -> bool:
        try:
            if path.is_symlink():
                return False
            resolved = path.resolve(strict=True)
            resolved.relative_to(self.root)
            mode = resolved.stat().st_mode
            return stat.S_ISREG(mode) and mode & 0o077 == 0
        except (OSError, ValueError):
            return False

    def use(self, reference: str, *, owner: str, purpose: str, consumer: str,
            operation_id: str, authorized: bool,
            consume: Callable[[BinaryIO], T]) -> T:
        source = self._matching(reference, owner, purpose)
        record = {"operation_id": operation_id, "reference": reference,
                  "owner": owner, "purpose": purpose, "consumer": consumer}
        if not authorized or consumer != source.consumer or not self._safe_file(source.path):
            self.audit({**record, "outcome": "denied"})
            raise SecretReferenceError("secret access denied")
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(source.path, flags)
        try:
            opened = os.fstat(fd)
            if not stat.S_ISREG(opened.st_mode) or opened.st_mode & 0o077:
                raise SecretReferenceError("secret permissions changed")
            self.audit({**record, "outcome": "accessed"})
            with os.fdopen(fd, "rb", closefd=False) as stream:
                return consume(stream)
        finally:
            os.close(fd)
