"""Small Wave E secret-reference adapter over existing private files.

Registration is trusted Core configuration. Capability input carries only an
opaque reference ID; paths and values are absent from descriptors, plans,
inspection and audit records. The selected OpenRouter lifecycle extends this
owner with private durable registration below; other reviewed legacy bindings
retain their existing reference/consumer boundary.
"""

from __future__ import annotations

import contextlib
import fcntl
import json
import os
import re
import secrets
import sqlite3
import stat
import tempfile
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import BinaryIO, ClassVar, TypeVar

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


class ManagedOpenRouterSecret(SecretReferenceService):
    """Installation-scoped, private OpenRouter material behind an opaque handle.

    This bounded implementation extends the Wave E secret-reference boundary.
    It does not accept a serialized consumer or authorization flag. Callers in
    Core select one of the closed, reviewed use profiles below.
    """

    REFERENCE = "ai.openrouter.credential"
    OWNER = "core"
    PURPOSE = "auth"
    CONSUMERS = frozenset({"transport", "validation", "balance"})
    VERSION = 1
    _TABLES = frozenset({"metadata", "reference", "access"})
    _COLUMNS: ClassVar[dict[str, tuple[str, ...]]] = {
        "metadata": ("key", "value"),
        "reference": ("id", "scope_id", "owner", "purpose", "revision", "active",
                      "previous", "pending", "ticket", "pending_operation",
                      "expected_revision", "cutover", "source_kind", "operation_id", "handle", "pending_source", "binding", "active_generation", "previous_generation", "pending_generation", "retired"),
        "access": ("id", "at", "operation_id", "reference", "scope_id", "owner",
                   "purpose", "consumer", "generation", "outcome", "external_status"),
    }
    _AUDIT_ID = re.compile(r"(?:op-[0-9a-f]{32}|[0-9a-f]{32}|request-[A-Za-z0-9-]{1,64}|local-redaction|stage-validation|credential-query)")

    def __init__(self, secret_root: Path, data_root: Path, *, pending_operation: str | None = None):
        # The parent adapter remains available to v1 callers. Managed material
        # has its own private subdirectory and does not rely on in-memory paths.
        self.secret_root = Path(secret_root).absolute()
        self.data_root = Path(data_root).absolute()
        self.material_dir = self.secret_root / ".managed"
        self.metadata_dir = self.data_root / "secrets"
        self.db_path = self.metadata_dir / "catalog.db"
        self.pending_operation = pending_operation

    @staticmethod
    def _private_directory(path: Path, *, create: bool = False) -> bool:
        for ancestor in (path, *path.parents):
            if ancestor.is_symlink():
                raise SecretReferenceError("secret path contains a link")
        if path.is_symlink():
            raise SecretReferenceError("secret path is a link")
        if not path.exists():
            if not create:
                return False
            missing = []
            parent = path
            while not parent.exists():
                missing.append(parent)
                parent = parent.parent
            for directory in reversed(missing):
                directory.mkdir(mode=0o700, exist_ok=True)
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            info = os.fstat(fd)
            if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
                raise SecretReferenceError("secret directory is not private")
        finally:
            os.close(fd)
        return True

    def _prepare_roots(self, *, create: bool):
        for root in (self.secret_root, self.data_root):
            if any(ancestor.is_symlink() for ancestor in (root, *root.parents)):
                raise SecretReferenceError("secret root contains a link")
            if not root.exists() and not create:
                return False
            if not root.exists() and create:
                root.mkdir(mode=0o700, parents=True, exist_ok=True)
            if (root.is_symlink() or not root.is_dir() or root.stat().st_uid != os.geteuid()
                    or stat.S_IMODE(root.stat().st_mode) & 0o022):
                raise SecretReferenceError("secret root unavailable")
        # Existing safe containers may be 0755. Only the separate owned
        # material/catalog directories are private; never chmod personal roots.
        meta = self._private_directory(self.metadata_dir, create=create)
        material = self._private_directory(self.material_dir, create=create)
        if meta != material:
            if meta and not material and not self.db_path.exists():
                return False
            raise SecretReferenceError("incomplete secret store")
        return meta and material

    @contextlib.contextmanager
    def _store(self, *, write: bool = False):
        if not self._prepare_roots(create=write):
            yield None
            return
        dir_fd = os.open(self.metadata_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        db = None
        catalog_fd = None
        try:
            fcntl.flock(dir_fd, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
            if self.db_path.is_symlink():
                raise SecretReferenceError("secret catalog is a link")
            if not self.db_path.exists():
                if any(self.material_dir.iterdir()):
                    raise SecretReferenceError("secret catalog missing with retained material")
                if not write:
                    yield None
                    return
                self._create_store()
            for suffix in ("", "-journal", "-wal", "-shm"):
                path = Path(str(self.db_path) + suffix)
                if path.is_symlink():
                    raise SecretReferenceError("secret catalog is a link")
                if path.exists():
                    info = path.stat()
                    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600:
                        raise SecretReferenceError("secret catalog is not private")
            catalog_fd = os.open(self.db_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
            catalog_info = os.fstat(catalog_fd)
            directory_info = os.fstat(dir_fd)
            if (directory_info.st_dev, directory_info.st_ino) != (
                    self.metadata_dir.stat().st_dev, self.metadata_dir.stat().st_ino):
                raise SecretReferenceError("secret catalog directory changed")
            # Read-only inspection cannot mutate or initialize the database.
            if write:
                db = sqlite3.connect(f"/proc/self/fd/{dir_fd}/catalog.db", timeout=5)
                db.execute("PRAGMA journal_mode=DELETE")
                db.execute("BEGIN IMMEDIATE")
            else:
                db = sqlite3.connect(f"file:/proc/self/fd/{catalog_fd}?mode=ro", uri=True, timeout=5)
                db.execute("PRAGMA query_only=ON")
            current_info = self.db_path.lstat()
            if (current_info.st_dev, current_info.st_ino) != (catalog_info.st_dev, catalog_info.st_ino):
                raise SecretReferenceError("secret catalog changed during open")
            row = db.execute("SELECT value FROM metadata WHERE key='schema_version'").fetchone()
            if row != (str(self.VERSION),):
                raise SecretReferenceError("unsupported secret catalog version")
            if db.execute("SELECT key,value FROM metadata").fetchall() != [("schema_version", str(self.VERSION))]:
                raise SecretReferenceError("secret catalog metadata invalid")
            objects = {(kind, name) for kind, name in db.execute(
                "SELECT type,name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'"
            )}
            if objects != {("table", name) for name in self._TABLES}:
                raise SecretReferenceError("secret catalog structure invalid")
            for table, columns in self._COLUMNS.items():
                actual = tuple(row[1] for row in db.execute(f"PRAGMA table_info({table})"))
                if actual != columns:
                    raise SecretReferenceError("secret catalog fields invalid")
            if db.execute("SELECT COUNT(*) FROM reference").fetchone()[0] > 1:
                raise SecretReferenceError("secret catalog registration invalid")
            if db.execute("PRAGMA quick_check").fetchone() != ("ok",):
                raise SecretReferenceError("secret catalog damaged")
            yield db
            if write:
                db.commit()
        except (sqlite3.Error, OSError) as exc:
            if db and write:
                db.rollback()
            raise SecretReferenceError("secret catalog unavailable") from exc
        finally:
            if db:
                db.close()
            if catalog_fd is not None:
                os.close(catalog_fd)
            os.close(dir_fd)

    def _create_store(self):
        fd, name = tempfile.mkstemp(prefix=".catalog-", dir=self.metadata_dir)
        os.close(fd)
        try:
            os.chmod(name, 0o600)
            db = sqlite3.connect(name)
            try:
                db.executescript("""
                    CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                    INSERT INTO metadata VALUES ('schema_version','1');
                    CREATE TABLE reference(
                      id TEXT PRIMARY KEY CHECK(id='ai.openrouter.credential'),
                      scope_id TEXT NOT NULL, owner TEXT NOT NULL CHECK(owner='core'),
                      purpose TEXT NOT NULL CHECK(purpose='auth'),
                      revision INTEGER NOT NULL CHECK(revision>=0),
                      active TEXT, previous TEXT, pending TEXT, ticket TEXT,
                      pending_operation TEXT, expected_revision INTEGER,
                      cutover INTEGER NOT NULL CHECK(cutover IN (0,1)),
                      source_kind TEXT, operation_id TEXT, handle TEXT NOT NULL,
                      pending_source TEXT, binding TEXT NOT NULL,
                      active_generation TEXT, previous_generation TEXT, pending_generation TEXT, retired TEXT);
                    CREATE TABLE access(
                      id INTEGER PRIMARY KEY, at TEXT NOT NULL,
                      operation_id TEXT NOT NULL, reference TEXT NOT NULL,
                      scope_id TEXT NOT NULL, owner TEXT NOT NULL,
                      purpose TEXT NOT NULL, consumer TEXT NOT NULL,
                      generation TEXT, outcome TEXT NOT NULL, external_status INTEGER);
                """)
                db.commit()
            finally:
                db.close()
            os.replace(name, self.db_path)
            fd = os.open(self.metadata_dir, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
        finally:
            if os.path.exists(name):
                os.unlink(name)

    @staticmethod
    def _row(db):
        row = db.execute("SELECT scope_id, revision, active, previous, pending, ticket, pending_operation, expected_revision, cutover, source_kind, operation_id, handle, pending_source, binding, active_generation, previous_generation, pending_generation, retired FROM reference WHERE id=?",
                         (ManagedOpenRouterSecret.REFERENCE,)).fetchone()
        if row is None:
            return None
        scope, revision, active, previous, pending, ticket, pending_op, expected, cutover, source, last_op, handle, pending_source, binding, active_generation, previous_generation, pending_generation, retired = row
        locators = [item for item in (active, previous, pending, retired) if item is not None]
        generations = [item for item in (active_generation, previous_generation, pending_generation) if item is not None]
        if ((active is None) != (active_generation is None) or
                (previous is None) != (previous_generation is None) or
                (pending is None) != (pending_generation is None) or
                len(set(generations)) != len(generations) or
                any(type(item) is not str or not re.fullmatch(r"generation:[0-9a-f]{32}", item) for item in generations) or
                binding != "core.openrouter.v1" or
                (pending is None) != (pending_source is None) or
                (pending_source is not None and pending_source not in {"private_input", "environment_import", "file_import", "home_import", "env_file_import"}) or
                type(handle) is not str or not re.fullmatch(r"secret:[0-9a-f]{32}", handle) or
                type(scope) is not str or not re.fullmatch(r"scope:[0-9a-f]{32}", scope) or
                type(revision) is not int or revision < 0 or
                type(cutover) is not int or cutover not in (0, 1) or
                any(not ManagedOpenRouterSecret._locator(item) for item in locators) or
                len(set(locators)) != len(locators) or
                (cutover == 0 and active is not None) or
                (cutover == 1 and active is None) or
                (revision == 0) != (cutover == 0) or
                (pending is None) != (ticket is None) or
                (pending is None) != (expected is None) or
                (pending is None and pending_op is not None) or
                (ticket is not None and (type(ticket) is not str or
                                         not re.fullmatch(r"[0-9a-f]{48}", ticket))) or
                (pending_op is not None and (type(pending_op) is not str or
                                             not re.fullmatch(r"op-[0-9a-f]{32}", pending_op))) or
                (expected is not None and (type(expected) is not int or expected != revision)) or
                (source is not None and source not in {"private_input", "environment_import",
                                                        "file_import", "home_import", "env_file_import"}) or
                (last_op is not None and (type(last_op) is not str or
                                          not re.fullmatch(r"op-[0-9a-f]{32}", last_op)))):
            raise SecretReferenceError("secret catalog row invalid")
        return row

    @staticmethod
    def _locator(name: str | None) -> bool:
        return name is None or (type(name) is str and bool(re.fullmatch(r"g[0-9a-f]{40}", name)))

    def _material(self, name: str) -> bytes:
        if not self._locator(name) or name is None:
            raise SecretReferenceError("invalid secret generation")
        fd = self._open_generation(name)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 16384:
                raise SecretReferenceError("secret material unavailable")
            data = os.read(fd, 16385)
            if len(data) > 16384 or not data or b"\x00" in data:
                raise SecretReferenceError("secret material unavailable")
            return data
        finally:
            os.close(fd)

    def _open_generation(self, name: str, expected=None) -> int:
        """Pin the directory and compare the opened object before any read."""
        if not self._locator(name) or name is None:
            raise SecretReferenceError("invalid secret generation")
        self._private_directory(self.material_dir)
        directory_fd = os.open(self.material_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        fd = None
        try:
            before = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=directory_fd)
            opened = os.fstat(fd)
            directory = os.fstat(directory_fd)
            current = self.material_dir.lstat()
            if ((directory.st_dev, directory.st_ino) != (current.st_dev, current.st_ino) or
                    (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino) or
                    (expected is not None and (opened.st_dev, opened.st_ino) != expected) or
                    not stat.S_ISREG(opened.st_mode) or opened.st_uid != os.geteuid() or
                    opened.st_nlink != 1 or stat.S_IMODE(opened.st_mode) != 0o600 or
                    not 1 <= opened.st_size <= 16384):
                raise SecretReferenceError("secret generation changed or is unsafe")
            return fd
        except BaseException:
            if fd is not None:
                os.close(fd)
            raise
        finally:
            os.close(directory_fd)

    def _availability(self, name: str | None) -> str:
        if name is None:
            return "missing"
        try:
            if not self._locator(name):
                raise SecretReferenceError("invalid secret generation")
            path = self.material_dir / name
            info = path.lstat()
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or
                    info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600 or
                    not 1 <= info.st_size <= 16384):
                raise SecretReferenceError("secret material unavailable")
            return "available"
        except (OSError, SecretReferenceError):
            return "unsafe_or_missing"

    def status(self) -> dict:
        with self._store() as db:
            if db is None:
                return {"reference": None, "owner": self.OWNER, "purpose": self.PURPOSE,
                        "availability": "not_created", "cutover": False, "revision": 0,
                        "generation": None, "pending": False, "previous_available": False}
            row = self._row(db)
            if row is None:
                return {"reference": None, "owner": self.OWNER, "purpose": self.PURPOSE,
                        "availability": "not_configured", "cutover": False, "revision": 0,
                        "generation": None, "pending": False, "previous_available": False}
            scope, revision, active, previous, pending, ticket, operation, _expected, cutover, source, last_op, handle, pending_source, binding, active_generation, _previous_generation, _pending_generation, retired = row
            last_access = db.execute(
                "SELECT at,operation_id,consumer,generation,outcome,external_status FROM access ORDER BY id DESC LIMIT 1"
            ).fetchone()
            external = db.execute("SELECT at,operation_id,consumer,generation,external_status FROM access WHERE external_status IS NOT NULL ORDER BY id DESC LIMIT 1").fetchone()
            if last_access and (type(last_access[1]) is not str or
                    not self._AUDIT_ID.fullmatch(last_access[1]) or
                    last_access[2] not in self.CONSUMERS | {"redaction", "unknown"} or
                    last_access[4] not in {"accessed", "denied"}):
                raise SecretReferenceError("secret access metadata invalid")
            availability = self._availability(active)
            previous_available = self._availability(previous) == "available"
        from operational_history import OperationalHistory
        history_scope = OperationalHistory(self.data_root).status()["scope_id"]
        if scope != history_scope:
            raise SecretReferenceError("secret installation scope mismatch")
        return {"reference": handle, "owner": self.OWNER,
                "purpose": self.PURPOSE, "scope_id": scope,
                "revision": revision, "generation": active_generation,
                "cutover": bool(cutover), "availability": availability,
                "previous_available": previous_available, "retirement_pending": retired is not None,
                "pending": pending is not None, "pending_ticket": ticket,
                "pending_operation": operation, "source_kind": source,
                "pending_source_kind": pending_source, "binding_profile": binding,
                "last_operation_id": last_op,
                "bindings": sorted(self.CONSUMERS | {"redaction"}),
                "last_external_acceptance": ({"at": external[0], "operation_id": external[1],
                    "consumer": external[2], "generation": external[3], "http_status": external[4]} if external else None),
                "last_access": ({"at": last_access[0], "operation_id": last_access[1],
                                 "consumer": last_access[2], "generation": last_access[3],
                                 "outcome": last_access[4], "external_status": last_access[5]} if last_access else None)}

    def cutover_marker(self) -> bool:
        """Read the local cutover fence without entering History during redaction."""
        with self._store() as db:
            row = self._row(db) if db else None
            return bool(row and row[8] == 1)

    def inspect(self, reference: str, *, owner: str, purpose: str,
                operation_id: str | None = None) -> dict[str, str | bool]:
        state = self.status()
        if (reference, owner, purpose) != (state["reference"], self.OWNER, self.PURPOSE) or reference is None:
            raise SecretReferenceError("secret reference unavailable")
        configured = state["availability"] == "available"
        operation_id = operation_id or self.pending_operation
        if not configured and operation_id:
            with self._store() as db:
                row = self._row(db) if db else None
                configured = bool(row and row[6] == operation_id and row[4] and self._availability(row[4]) == "available")
        return {"reference": reference, "owner": owner, "purpose": purpose,
                "configured": configured}

    def _scope(self):
        from operational_history import OperationalHistory
        return OperationalHistory(self.data_root).ensure_scope()

    def _stage_rebindable(self, operation_id: str | None):
        if operation_id is None:
            return True
        from operational_history import OperationalHistory
        operation = OperationalHistory(self.data_root).inspect(operation_id)
        return operation["lifecycle"] in {"terminal", "interrupted", "reconciled"}

    def staged(self, ticket: str, *, expected_revision: int, source_kind: str) -> dict:
        if (type(ticket) is not str or not re.fullmatch(r"[0-9a-f]{48}", ticket) or
                type(expected_revision) is not int or expected_revision < 0):
            raise SecretReferenceError("invalid secret stage")
        from operational_history import OperationalHistory
        history_scope = OperationalHistory(self.data_root).status()["scope_id"]
        with self._store() as db:
            row = self._row(db) if db else None
            if (row is None or row[0] != history_scope or row[1] != expected_revision or
                    row[4] is None or row[5] != ticket or
                    row[7] != expected_revision or row[12] != source_kind or
                    self._availability(row[4]) != "available"):
                raise SecretReferenceError("secret stage unavailable")
        if not self._stage_rebindable(row[6]):
            raise SecretReferenceError("secret stage remains owned by a running operation")
        return {"reference": row[11], "revision": expected_revision,
                "source_kind": source_kind}

    def use_staged_for_validation(self, ticket: str, *, operation_id: str,
                                  consume: Callable[[BinaryIO], T]) -> T:
        if (type(ticket) is not str or not re.fullmatch(r"[0-9a-f]{48}", ticket) or
                type(operation_id) is not str or not self._AUDIT_ID.fullmatch(operation_id)):
            raise SecretReferenceError("invalid staged credential request")
        self._running(operation_id, self.pending_capability(ticket))
        with self._store(write=True) as db:
            row = self._row(db)
            allowed = bool(row and row[5] == ticket and row[4] is not None and
                           row[6] == operation_id and row[7] == row[1] and
                           self._availability(row[4]) == "available")
            db.execute("INSERT INTO access(at,operation_id,reference,scope_id,owner,purpose,consumer,generation,outcome) VALUES (datetime('now'),?,?,?,?,?,?,?,?)",
                       (operation_id, row[11] if row else "unavailable", row[0] if row else "unavailable",
                        self.OWNER, self.PURPOSE, "validation", row[16] if allowed else None,
                        "accessed" if allowed else "denied"))
            name = row[4] if allowed else None
            expected = ((self.material_dir / name).stat().st_dev,
                        (self.material_dir / name).stat().st_ino) if name else None
        if name is None:
            raise SecretReferenceError("staged credential unavailable")
        fd = self._open_generation(name, expected)
        try:
            info = os.fstat(fd)
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or
                    info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600 or
                    not 1 <= info.st_size <= 16384):
                raise SecretReferenceError("staged credential unavailable")
            with os.fdopen(fd, "rb", closefd=False) as stream:
                return consume(stream)
        finally:
            os.close(fd)

    def pending_capability(self, ticket: str) -> str:
        with self._store() as db:
            row = self._row(db) if db else None
            if row is None or row[5] != ticket:
                raise SecretReferenceError("secret stage unavailable")
            return ("core.configuration.openrouter_credential.rotate" if row[8]
                    else "core.configuration.openrouter_credential.set")

    def _running(self, operation_id: str, capability: str,
                 frozen_inputs: dict | None = None) -> str:
        from operational_history import HistoryError, OperationalHistory
        try:
            row = OperationalHistory(self.data_root).inspect(operation_id)
        except HistoryError as exc:
            raise SecretReferenceError("secret change lacks canonical authority") from exc
        if (row["capability"]["id"] != capability or row["provider"]["owner"] != "core" or
            row["safety_tier"] != "CHANGE" or row["lifecycle"] != "running" or
            row["approval"]["result"] not in {"approved", "auto_approved"}):
            raise SecretReferenceError("secret change lacks canonical authority")
        if frozen_inputs is not None and row["inputs"] != frozen_inputs:
            raise SecretReferenceError("secret change inputs differ from approval")
        return row["scope_id"]

    def stage(self, material: bytes, *, source_kind: str, expected_revision: int) -> str:
        if source_kind not in {"private_input", "environment_import", "file_import", "home_import", "env_file_import"}:
            raise SecretReferenceError("unsupported secret source")
        if type(expected_revision) is not int or expected_revision < 0 or not 1 <= len(material) <= 16384 or b"\x00" in material or any(c in material for c in (b"\r", b"\n", b" ", b"\t")):
            raise SecretReferenceError("invalid private credential")
        try:
            material.decode("ascii")
        except UnicodeDecodeError as exc:
            raise SecretReferenceError("invalid private credential") from exc
        with self._store() as existing_db:
            existing = self._row(existing_db) if existing_db else None
        if existing and existing[17] is not None:
            self._finish_retirement(existing[10])
        scope = self._scope()
        ticket = secrets.token_hex(24)
        name = "g" + secrets.token_hex(20)
        created = False
        try:
            with self._store(write=True) as db:
                row = self._row(db)
                if row is None:
                    if expected_revision != 0:
                        raise SecretReferenceError("secret revision conflict")
                    db.execute("INSERT INTO reference(id,scope_id,owner,purpose,revision,cutover,handle,binding) VALUES (?,?,?,?,0,0,?,?)",
                               (self.REFERENCE, scope, self.OWNER, self.PURPOSE, "secret:" + secrets.token_hex(16), "core.openrouter.v1"))
                elif row[0] != scope or row[1] != expected_revision or row[4] is not None:
                    raise SecretReferenceError("secret revision conflict")
                fd = os.open(self.material_dir / name,
                             os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
                created = True
                try:
                    remaining = memoryview(material)
                    while remaining:
                        count = os.write(fd, remaining)
                        if count <= 0:
                            raise SecretReferenceError("secret material write failed")
                        remaining = remaining[count:]
                    os.fsync(fd)
                finally:
                    os.close(fd)
                directory_fd = os.open(self.material_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
                db.execute("UPDATE reference SET pending=?,ticket=?,expected_revision=?,pending_source=?,pending_operation=NULL,pending_generation=? WHERE id=?",
                           (name, ticket, expected_revision, source_kind, "generation:" + secrets.token_hex(16), self.REFERENCE))
        except BaseException:
            if created:
                try:
                    with self._store() as check_db:
                        current = self._row(check_db) if check_db else None
                    if current is None or name not in current[2:5]:
                        (self.material_dir / name).unlink()
                except (OSError, SecretReferenceError):
                    pass
            raise
        return ticket

    def bind(self, ticket: str, operation_id: str, *, capability: str,
             source_kind: str, expected_revision: int, revision: int, state: str):
        scope = self._running(operation_id, capability, {
            "ticket": ticket, "source_kind": source_kind,
            "generation_revision": expected_revision, "revision": revision, "state": state})
        with self._store() as read_db:
            snapshot = self._row(read_db) if read_db else None
        if snapshot is None or (snapshot[6] != operation_id and not self._stage_rebindable(snapshot[6])):
            raise SecretReferenceError("secret stage remains owned by a running operation")
        with self._store(write=True) as db:
            row = self._row(db)
            if (row != snapshot or row is None or row[0] != scope or row[5] != ticket or row[4] is None or row[7] != row[1]
                    or row[1] != expected_revision or row[12] != source_kind):
                raise SecretReferenceError("secret stage unavailable")
            db.execute("UPDATE reference SET pending_operation=? WHERE id=?", (operation_id, self.REFERENCE))

    def activate(self, ticket: str, operation_id: str, *, expected_revision: int,
                 configuration, rotation: bool = False, recovering: bool = False) -> dict:
        capability = ("core.configuration.openrouter_credential.reimport" if recovering else
                      "core.configuration.openrouter_credential.rotate" if rotation
                      else "core.configuration.openrouter_credential.set")
        scope = self._running(operation_id, capability)
        from operational_history import OperationalHistory
        inputs = OperationalHistory(self.data_root).inspect(operation_id)["inputs"]
        with configuration.openrouter_change_fence(revision=inputs["revision"], state=inputs["state"],
                committed_operation=None if rotation else operation_id):
            view = configuration.inspect(self.REFERENCE, "installation:local")
            if (view["desired"] != {"status": "value", "value": {"reference": self.status()["reference"]}} or
                (not rotation and view["last_change"]["operation_id"] != operation_id)):
                raise SecretReferenceError("secret configuration cutover unverified")
            retired = None
            with self._store(write=True) as db:
                row = self._row(db)
                if (row is None or row[0] != scope or row[1] != expected_revision or
                    row[5] != ticket or row[6] != operation_id or row[4] is None):
                    raise SecretReferenceError("secret activation conflict")
                if self._availability(row[4]) != "available":
                    raise SecretReferenceError("staged secret unavailable")
                validated = db.execute("SELECT 1 FROM access WHERE operation_id=? AND consumer='validation' AND generation=? AND external_status=200 AND outcome='accessed'",
                                       (operation_id, row[16])).fetchone()
                if not validated:
                    raise SecretReferenceError("staged credential external validation unavailable")
                # row[3] is the *older* previous generation. The SQL below
                # retains row[2] (the current active generation) as the new
                # previous generation; row[3] is no longer reachable afterward.
                retired = row[3]
                db.execute("UPDATE reference SET retired=previous,revision=revision+1,previous=active,previous_generation=active_generation,active=pending,active_generation=pending_generation,pending_generation=NULL,pending=NULL,ticket=NULL,pending_operation=NULL,expected_revision=NULL,source_kind=pending_source,pending_source=NULL,cutover=1,operation_id=? WHERE id=?",
                           (operation_id, self.REFERENCE))
            if retired is not None:
                self._finish_retirement(operation_id)
            return self.status()

    def _finish_retirement(self, operation_id: str):
        """Idempotent completion of an already approved immutable-generation cutover."""
        from operational_history import OperationalHistory
        operation = OperationalHistory(self.data_root).inspect(operation_id)
        if (operation["provider"]["owner"] != "core" or operation["safety_tier"] != "CHANGE" or
                operation["capability"]["id"] not in {"core.configuration.openrouter_credential.set", "core.configuration.openrouter_credential.rotate", "core.configuration.openrouter_credential.reimport"} or
                operation["approval"]["result"] not in {"approved", "auto_approved"}):
            raise SecretReferenceError("retirement lacks canonical authority")
        with self._store(write=True) as db:
            row = self._row(db)
            if row is None or row[0] != operation["scope_id"] or row[10] != operation_id:
                raise SecretReferenceError("retirement operation conflict")
            name = row[17]
            if name is None:
                return
            directory_fd = os.open(self.material_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                try:
                    os.unlink(name, dir_fd=directory_fd)
                except FileNotFoundError:
                    pass
                os.fsync(directory_fd)
            except OSError as exc:
                raise SecretReferenceError("retired secret generation cleanup unavailable") from exc
            finally:
                os.close(directory_fd)
            db.execute("UPDATE reference SET retired=NULL WHERE id=?", (self.REFERENCE,))

    def restore_previous(self, *, operation_id: str, expected_revision: int,
                         revision: int, state: str, configuration) -> dict:
        scope = self._running(operation_id, "core.configuration.openrouter_credential.restore_previous",
                              {"generation_revision": expected_revision, "revision": revision, "state": state})
        with configuration.openrouter_change_fence(revision=revision, state=state):
            view = configuration.inspect(self.REFERENCE, "installation:local")
            if view["desired"] != {"status": "value", "value": {"reference": self.status()["reference"]}}:
                raise SecretReferenceError("secret reference is not configured")
            with self._store(write=True) as db:
                row = self._row(db)
                if (row is None or row[0] != scope or row[1] != expected_revision or
                        row[3] is None or row[4] is not None or row[8] != 1 or
                        self._availability(row[3]) != "available"):
                    raise SecretReferenceError("previous secret unavailable")
                db.execute("UPDATE reference SET revision=revision+1,active=previous,previous=active,active_generation=previous_generation,previous_generation=active_generation,operation_id=? WHERE id=?",
                           (operation_id, self.REFERENCE))
            return self.status()

    def discard_pending(self, ticket: str):
        # Explicit local cleanup of cancelled or terminal/interrupted stages.
        # Active and retained previous generations are never affected.
        with self._store() as db:
            row = self._row(db) if db else None
        if row is None or row[5] != ticket or row[4] in {row[2], row[3]}:
            raise SecretReferenceError("secret stage cannot be discarded")
        if row[6] is not None:
            from operational_history import HistoryError, OperationalHistory
            try:
                lifecycle = OperationalHistory(self.data_root).inspect(row[6])["lifecycle"]
            except HistoryError as exc:
                raise SecretReferenceError("bound secret stage cannot be discarded") from exc
            if lifecycle not in {"terminal", "interrupted", "reconciled"}:
                raise SecretReferenceError("running secret stage cannot be discarded")
        with self._store(write=True) as db:
            fresh = self._row(db)
            if fresh != row:
                raise SecretReferenceError("secret stage cannot be discarded")
            name = row[4]
            db.execute("UPDATE reference SET pending=NULL,pending_generation=NULL,ticket=NULL,pending_operation=NULL,expected_revision=NULL,pending_source=NULL WHERE id=?",
                       (self.REFERENCE,))
        if name and self._locator(name):
            try:
                (self.material_dir / name).unlink()
            except FileNotFoundError:
                pass

    def stage_recovery(self, material: bytes, *, source_kind: str, handle: str | None) -> str:
        """Explicit protected staging remains possible for an unavailable catalog."""
        if (source_kind not in {"private_input", "environment_import", "file_import", "home_import", "env_file_import"}
                or not 1 <= len(material) <= 16384 or any(c in material for c in (b"\x00", b"\r", b"\n", b" ", b"\t"))):
            raise SecretReferenceError("invalid private credential")
        try:
            material.decode("ascii")
        except UnicodeDecodeError as exc:
            raise SecretReferenceError("invalid private credential") from exc
        if handle is not None and not re.fullmatch(r"secret:[0-9a-f]{32}", handle):
            raise SecretReferenceError("invalid recovery handle")
        self._prepare_roots(create=True)
        directory = self.metadata_dir / "recovery"
        self._private_directory(directory, create=True)
        ticket, name = secrets.token_hex(24), "g" + secrets.token_hex(20)
        descriptor = {"version": 1, "ticket": ticket, "material": name,
                      "handle": handle or "secret:" + secrets.token_hex(16),
                      "scope_id": self._scope(), "source_kind": source_kind,
                      "generation": "generation:" + secrets.token_hex(16),
                      "catalog_stamp": self._catalog_stamp()}
        for path, data in ((self.material_dir / name, material),
                           (directory / (ticket + ".json"), json.dumps(descriptor).encode())):
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
            try:
                remaining = memoryview(data)
                while remaining:
                    count = os.write(fd, remaining)
                    if count <= 0:
                        raise SecretReferenceError("recovery stage write failed")
                    remaining = remaining[count:]
                os.fsync(fd)
            finally:
                os.close(fd)
        return ticket

    def recovery_stage(self, ticket: str) -> dict:
        if type(ticket) is not str or not re.fullmatch(r"[0-9a-f]{48}", ticket):
            raise SecretReferenceError("invalid recovery stage")
        directory = self.metadata_dir / "recovery"
        self._private_directory(directory)
        fd = os.open(directory / (ticket + ".json"), os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        try:
            info = os.fstat(fd)
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or
                    info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 4096):
                raise SecretReferenceError("unsafe recovery stage")
            descriptor = json.loads(os.read(fd, 4097))
        finally:
            os.close(fd)
        if (type(descriptor) is not dict or set(descriptor) != {"version", "ticket", "material", "handle", "scope_id", "source_kind", "catalog_stamp", "generation"}
                or descriptor["version"] != 1 or descriptor["ticket"] != ticket or
                not self._locator(descriptor["material"]) or
                not re.fullmatch(r"secret:[0-9a-f]{32}", descriptor["handle"]) or
                descriptor["scope_id"] != self._scope() or
                descriptor["source_kind"] not in {"private_input", "environment_import", "file_import", "home_import", "env_file_import"} or
                self._availability(descriptor["material"]) != "available"):
            raise SecretReferenceError("recovery stage unavailable")
        return descriptor

    def _catalog_stamp(self):
        try:
            info = self.db_path.lstat()
            return [info.st_dev, info.st_ino, info.st_mtime_ns, info.st_size]
        except FileNotFoundError:
            return None

    def use_recovery_validation(self, ticket: str, operation_id: str, consume):
        self._running(operation_id, "core.configuration.openrouter_credential.reimport")
        stage = self.recovery_stage(ticket)
        self._private_access_audit(operation_id=operation_id, consumer="validation", reference=stage["handle"], generation=stage["generation"], scope_id=stage["scope_id"])
        fd = self._open_generation(stage["material"])
        try:
            with os.fdopen(fd, "rb", closefd=False) as stream:
                return consume(stream)
        finally:
            os.close(fd)

    def rebuild_registration(self, ticket: str, *, operation_id: str, frozen_inputs: dict):
        """Approved local recovery preserves damaged artifacts; no startup repair."""
        scope = self._running(operation_id, "core.configuration.openrouter_credential.reimport", frozen_inputs)
        stage = self.recovery_stage(ticket)
        if getattr(self, "_validated_recovery", None) != (ticket, operation_id):
            raise SecretReferenceError("recovery credential external validation unavailable")
        self._prepare_roots(create=True)
        try:
            with self._store() as db:
                current = self._row(db) if db else None
        except SecretReferenceError:
            current = None
        if current and self._availability(current[2]) == "available":
            raise SecretReferenceError("available credential requires ordinary rotation")
        lock_fd = os.open(self.metadata_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
            # Concurrent normal updates/other recoveries cannot be overwritten.
            if self._catalog_stamp() != stage["catalog_stamp"]:
                raise SecretReferenceError("recovery catalog revision conflict")
            archive = self.metadata_dir / "damaged" / secrets.token_hex(16)
            self._private_directory(archive, create=True)
            for suffix in ("", "-journal", "-wal", "-shm"):
                path = Path(str(self.db_path) + suffix)
                if path.exists() or path.is_symlink():
                    os.replace(path, archive / ("catalog.db" + suffix))
            damaged = self.material_dir / "damaged" / archive.name
            self._private_directory(damaged, create=True)
            for path in self.material_dir.iterdir():
                if self._locator(path.name) and path.name != stage["material"]:
                    os.replace(path, damaged / path.name)
            self._create_store()
            db = sqlite3.connect(self.db_path)
            try:
                db.execute("INSERT INTO reference(id,scope_id,owner,purpose,revision,cutover,handle,pending,ticket,pending_operation,expected_revision,pending_source,binding,pending_generation) VALUES (?,?,?,?,0,0,?,?,?,?,0,?,?,?)",
                       (self.REFERENCE, scope, self.OWNER, self.PURPOSE, stage["handle"], stage["material"], ticket, operation_id, stage["source_kind"], "core.openrouter.v1", stage["generation"]))
                db.execute("INSERT INTO access(at,operation_id,reference,scope_id,owner,purpose,consumer,generation,outcome,external_status) VALUES (datetime('now'),?,?,?,?,?,?,?,'accessed',200)",
                           (operation_id, stage["handle"], scope, self.OWNER, self.PURPOSE, "validation", stage["generation"]))
                db.commit()
            finally:
                db.close()
        finally:
            os.close(lock_fd)

    def discard_recovery(self, ticket: str):
        stage = self.recovery_stage(ticket)
        (self.metadata_dir / "recovery" / (ticket + ".json")).unlink()
        try:
            with self._store() as db:
                row = self._row(db) if db else None
        except SecretReferenceError:
            row = None
        if row is None or stage["material"] not in row[2:5]:
            (self.material_dir / stage["material"]).unlink(missing_ok=True)

    def _audit_scope(self):
        try:
            with self._store() as db:
                row = self._row(db) if db else None
            return row[0] if row else None
        except SecretReferenceError:
            return None

    def _private_access_audit(self, *, operation_id: str, consumer: str,
                              reference="unavailable", generation=None, scope_id=None) -> None:
        """Sanitization/recovery audit remains writable when catalog is damaged.

        This append-only file grants no transport or mutation authority. It is
        owned by the same secret-reference component and contains no material.
        """
        if not self._AUDIT_ID.fullmatch(operation_id) or consumer not in {"redaction", "validation"}:
            raise SecretReferenceError("invalid private audit request")
        self._private_directory(self.metadata_dir, create=True)
        path = self.metadata_dir / "private-access.jsonl"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        try:
            info = os.fstat(fd)
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or
                    info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600):
                raise SecretReferenceError("private audit unavailable")
            fcntl.flock(fd, fcntl.LOCK_EX)
            data = json.dumps({"at": datetime.now(timezone.utc).isoformat(),
                               "operation_id": operation_id, "reference": reference,
                               "owner": self.OWNER, "purpose": self.PURPOSE,
                               "scope_id": scope_id or self._audit_scope(), "consumer": consumer, "generation": generation,
                               "outcome": "accessed"}, separators=(",", ":")).encode() + b"\n"
            while data:
                written = os.write(fd, data)
                if written <= 0:
                    raise SecretReferenceError("private audit unavailable")
                data = data[written:]
            os.fsync(fd)
        except OSError as exc:
            raise SecretReferenceError("private audit unavailable") from exc
        finally:
            os.close(fd)

    def _response_projector(self, *, operation_id: str, admitted: bytes = b""):
        """Trusted Core projection holds private literals inside this owner.

        Return only a transform. Its bounded suffix is withheld when it could
        begin a credential; unrelated output can stream immediately.
        """
        literals = [admitted] if admitted else []
        if self.material_dir.exists():
            self._private_directory(self.material_dir)
            paths = sorted(path for path in self.material_dir.rglob("g*") if self._locator(path.name))
            if paths or admitted:
                self._private_access_audit(operation_id=operation_id, consumer="redaction")
            for path in paths:
                for ancestor in path.parents:
                    if ancestor == self.material_dir.parent:
                        break
                    self._private_directory(ancestor)
                if path.is_symlink():
                    raise SecretReferenceError("redaction generation unavailable")
                parent_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
                fd = None
                try:
                    before = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
                    fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent_fd)
                    info = os.fstat(fd)
                    if ((info.st_dev, info.st_ino) != (before.st_dev, before.st_ino) or
                            not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or
                            info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600 or
                            not 1 <= info.st_size <= 16384):
                        raise SecretReferenceError("redaction generation unavailable")
                    material = os.read(fd, 16385)
                    material.decode("ascii")
                    literals.append(material)
                finally:
                    if fd is not None:
                        os.close(fd)
                    os.close(parent_fd)
        elif self.material_dir.is_symlink() or admitted:
            raise SecretReferenceError("secret material root unavailable")
        private = tuple(sorted(set(literals), key=len, reverse=True))
        pending = b""

        def project(chunk: bytes, *, final=False):
            nonlocal pending
            data, pending = pending + chunk, b""
            output = bytearray()
            index = 0
            while index < len(data):
                match = next((value for value in private if data.startswith(value, index)), None)
                if match is not None:
                    output.extend(b"[REDACTED]")
                    index += len(match)
                elif not final and any(value.startswith(data[index:]) for value in private):
                    pending = data[index:]
                    break
                else:
                    output.append(data[index])
                    index += 1
            return bytes(output)
        return project

    def sanitize(self, text: str, *, operation_id: str) -> str:
        if not isinstance(text, str):
            raise SecretReferenceError("invalid data for secret redaction")
        project = self._response_projector(operation_id=operation_id)
        return project(text.encode("utf-8"), final=True).decode("utf-8")

    def _audit_denial(self, operation_id: str, consumer: str) -> None:
        with self._store(write=True) as db:
            row = self._row(db)
            db.execute("INSERT INTO access(at,operation_id,reference,scope_id,owner,purpose,consumer,generation,outcome) VALUES (datetime('now'),?,?,?,?,?,?,?,?)",
                       (operation_id, row[11] if row else "unavailable", row[0] if row else "unavailable",
                        self.OWNER, self.PURPOSE, consumer, None, "denied"))

    def use(self, reference: str, *, owner: str, purpose: str, consumer: str,
            operation_id: str, configuration, consume: Callable[[BinaryIO], T]) -> T:
        if type(operation_id) is not str or not self._AUDIT_ID.fullmatch(operation_id):
            raise SecretReferenceError("secret consumer unavailable")
        if ((owner, purpose) != (self.OWNER, self.PURPOSE)
                or type(reference) is not str or not re.fullmatch(r"secret:[0-9a-f]{32}", reference)
                or consumer not in self.CONSUMERS):
            self._audit_denial(operation_id, consumer if consumer in self.CONSUMERS else "unknown")
            raise SecretReferenceError("secret reference unavailable")
        try:
            configured = configuration.resolve_openrouter_credential()
        except ValueError as exc:
            self._audit_denial(operation_id, consumer)
            raise SecretReferenceError("secret configuration unavailable") from exc
        with self._store(write=True) as db:
            row = self._row(db)
            allowed = bool(row and row[8] == 1 and row[2] and
                           configured.get("scope_id") == row[0] and
                           configured.get("reference") == reference == row[11] and
                           self._availability(row[2]) == "available")
            db.execute("INSERT INTO access(at,operation_id,reference,scope_id,owner,purpose,consumer,generation,outcome) VALUES (datetime('now'),?,?,?,?,?,?,?,?)",
                       (operation_id, row[11] if row else "unavailable", row[0] if row else "unavailable",
                        self.OWNER, self.PURPOSE, consumer,
                        row[14] if allowed else None, "accessed" if allowed else "denied"))
            name = row[2] if allowed else None
            expected = ((self.material_dir / name).stat().st_dev,
                        (self.material_dir / name).stat().st_ino) if name else None
        if not allowed or name is None:
            raise SecretReferenceError("secret access denied")
        # Audit was committed before material is opened or returned.
        fd = self._open_generation(name, expected)
        try:
            info = os.fstat(fd)
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or
                    info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600 or
                    not 1 <= info.st_size <= 16384):
                raise SecretReferenceError("secret material changed")
            with os.fdopen(fd, "rb", closefd=False) as stream:
                return consume(stream)
        finally:
            os.close(fd)

    def observe_response(self, *, operation_id: str, consumer: str, status: int) -> None:
        """Record external acceptance independently from configured/consumed state."""
        if (not self._AUDIT_ID.fullmatch(operation_id) or consumer not in self.CONSUMERS or
                type(status) is not int or not 100 <= status <= 599):
            raise SecretReferenceError("invalid credential observation")
        with self._store(write=True) as db:
            db.execute("UPDATE access SET external_status=? WHERE id=(SELECT MAX(id) FROM access WHERE operation_id=? AND consumer=? AND outcome='accessed')",
                       (status, operation_id, consumer))
