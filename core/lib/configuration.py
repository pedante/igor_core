"""Core desired-configuration authority. Observations and execution live elsewhere.

The SQLite layout is private. Public snapshots carry versioned, scoped records;
module schemas describe meaning but never choose persistence or authorization.
Mutating methods are internal provider APIs, admitted by the capability boundary.
"""

from __future__ import annotations

import contextlib
import fcntl
import hashlib
import json
import os
import re
import shlex
import sqlite3
import stat
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from configuration_schema import (
    ConfigurationError,
    closed,
    validate_schema,
    validate_value,
)
from operational_history import OperationalHistory, object_ref
from privacy import scrub_text

CORE_SCHEMA = {"schema_version": 1, "fields": [
    {"id": "ai.verbose", "type": "boolean", "scope": "installation", "default": True,
     "label": "Verbose", "help": "Show AI reasoning before a command.", "overrides": []},
]}

MEMORY_WARNING = "system.memory.warning_threshold_mib"
MEMORY_TARGET = "module:system"


def installed_schemas(root: Path) -> list[tuple[str, dict]]:
    """Retain validated installed declarations, including disabled owners.

    This reads package data/syntax only. It neither sources code nor activates
    an owner. Missing/invalid package schemas remain unavailable; this is not a
    detach or package-removal implementation.
    """
    from module_contract import ValidationError, probe_api, validate_module

    schemas = []
    for package in sorted((root / "modules").glob("*")):
        if not (package / "module.conf").is_file():
            continue
        try:
            if probe_api(package) != "2":
                continue
            registration = validate_module(package)
        except (ValidationError, OSError):
            continue
        for row in registration["contributions"]:
            if row["kind"] == "configuration" and "schema" in row:
                schemas.append((row["owner"], row["schema"]))
    return schemas


def _memory_consumption(state: dict) -> dict:
    """Inspection of a process snapshot; never a claim of verification.

    Boundary O allows the ordinary health consumer to hold the authoritative
    value/revision without eagerly acquiring a global configuration state token.
    A token, when present, is still required to match for the stronger snapshot
    comparison used after an explicit apply/readback workflow.
    """
    try:
        value = int(os.environ["IGOR_SYSTEM_MEMORY_WARNING_MIB"])
        revision = int(os.environ["IGOR_SYSTEM_MEMORY_WARNING_REVISION"])
        token = os.environ.get("IGOR_SYSTEM_MEMORY_WARNING_STATE")
        if not 81 <= value <= 4096 or revision < 0:
            raise ValueError("invalid consumer snapshot")
        if token is not None and not re.fullmatch(r"[0-9a-f]{64}", token):
            raise ValueError("invalid consumer state token")
        matches = value == state["resolved"]["value"] and revision == state["revision"]
        result = {"status": "consumed_current_process", "value": value, "revision": revision,
                  "consumer_id": os.environ.get("IGOR_SYSTEM_MEMORY_CONSUMER_ID"),
                  "source": "system.host.memory.health.consumer",
                  "matches_desired": matches and (token == state["state_token"] if token is not None else True),
                  "verification": "not_verified"}
        if token is not None:
            result["state"] = token
        return result
    except (KeyError, ValueError):
        return {"status": "unavailable", "source": "system.host.memory.health.consumer", "verification": "not_verified"}


def decode(text: str) -> Any:
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ConfigurationError("duplicate JSON field")
            result[key] = value
        return result

    def invalid(_value):
        raise ConfigurationError("non-finite JSON value")

    return json.loads(text, object_pairs_hook=unique, parse_constant=invalid)


def compact(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def safe_path(path: Path) -> None:
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ConfigurationError("configuration path contains a symlink")


def validate_legacy_source(source):
    closed(source, {"kind", "path", "name"}, {"kind"}, "legacy source")
    kind = source["kind"]
    if kind == "default":
        valid = set(source) == {"kind"}
    elif kind == "compatibility_environment":
        valid = source == {"kind": kind, "name": "verbose"}
    elif kind == "compatibility_file":
        path = source.get("path")
        valid = (set(source) == {"kind", "path"} and type(path) is str and
                 (path == "core/config/defaults.conf" or bool(re.fullmatch(r"(?:(?:config/variables|secrets)/)?[A-Za-z0-9_.-]+\.env", path))) and
                 not any(part in {".", ".."} for part in path.split("/")) and len(path) <= 256 and scrub_text(path) == path)
    else:
        valid = False
    if not valid:
        raise ConfigurationError("invalid or secret-bearing legacy provenance")
    return source


def legacy_verbose(root: Path, inherited: str | None = None) -> dict:
    """Import only literal verbose assignments, never execute legacy shell.

    Preserve the primary loader's sorted file tiers. No other setting or secret
    is imported. Shell-dependent assignments are an explicit migration blocker.
    """
    value, source = True, {"kind": "default"}
    if inherited is not None:
        if inherited not in {"true", "false", ""}:
            raise ConfigurationError("legacy verbose environment is not a literal boolean")
        if inherited:
            value, source = inherited == "true", {"kind": "compatibility_environment", "name": "verbose"}
    paths = [root / "core/config/defaults.conf"]
    paths += sorted((root / "config/variables").glob("*.env"))
    paths += sorted((root / "secrets").glob("*.env"))
    paths += sorted(root.glob("*.env"))
    sources = []
    for path in paths:
        if not path.exists():
            continue
        # Package defaults are trusted code inputs; Core may be linked by an
        # installation. Mutable configuration inputs retain strict path checks.
        if path != root / "core/config/defaults.conf":
            safe_path(path)
        if not path.is_file() or path.stat().st_size > 1024 * 1024:
            raise ConfigurationError("legacy configuration source unavailable")
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            lexer = shlex.shlex(line, posix=True, punctuation_chars=";&|()<>")
            lexer.whitespace_split = True
            try:
                words = list(lexer)
            except ValueError as exc:
                raise ConfigurationError("legacy file requires bounded assignment grammar") from exc
            if words[:1] == ["export"]:
                words = words[1:]
            if (len(words) != 1 or not re.match(r"[A-Za-z_][A-Za-z0-9_]*=", words[0]) or
                    "$(" in line or "`" in line):
                raise ConfigurationError("legacy file requires bounded assignment grammar")
            if not words[0].startswith("verbose=") and not re.search(r"\$\{verbose\b", line):
                continue
            match = re.fullmatch(r"\s*(?:export\s+)?verbose\s*=\s*(true|false|'true'|'false'|\"true\"|\"false\")\s*(?:#.*)?", line)
            if match is None:
                raise ConfigurationError("legacy verbose requires explicit literal migration")
            value = match[1].strip("'\"") == "true"
            source = {"kind": "compatibility_file", "path": str(path.relative_to(root))}
            sources.append(source)
    return {"value": value, "source": source, "shadowed_sources": sources[:-1]}


class ConfigurationService:
    def validate_deployment_target(self, scope_id, deployment_id, setting_id, *,
                                   deployment_service, provider_available,
                                   expected_revision=None, expected_state=None):
        """Boundary 2 admission prerequisite; declares/applies no setting.

        Deployment Service is the sole binding/responsibility authority. A
        successful target check does not enable a schema or application writer.
        """
        from deployments import DeploymentError

        try:
            target = deployment_service.validate_configuration_target(
                {"scope_id": scope_id, "object_id": deployment_id}, setting_id,
                provider_available=provider_available, expected_revision=expected_revision,
                expected_state=expected_state)
        except DeploymentError as exc:
            raise ConfigurationError(str(exc)) from exc
        return {"source": "configuration_service", "availability": "target_validated",
                "reference": {"scope_id": scope_id, "deployment_id": deployment_id, "setting_id": setting_id},
                "binding": target, "desired_value": "not_created", "writer": "not_registered"}

    def __init__(self, data_dir: Path, *, schemas: list[tuple[str, dict]] | None = None,
                 owner_active=None, secret_service=None, path_roots=None, domain_validator=None):
        self.data_dir = data_dir.absolute()
        self.directory = self.data_dir / "config"
        self.path = self.directory / "config.db"
        self.history = OperationalHistory(self.data_dir)
        self.fields = {}
        self.owner_active = owner_active or (lambda _owner: True)
        self.secret_service = secret_service
        self.path_roots = path_roots or {}
        self.domain_validator = domain_validator
        for owner, descriptor in [("core", CORE_SCHEMA), *(schemas or [])]:
            if type(descriptor) is dict and "owner" in descriptor:
                closed(descriptor, {"schema_version", "owner", "fields"}, {"schema_version", "owner", "fields"}, "owner-stamped schema")
                if descriptor["owner"] != owner:
                    raise ConfigurationError("schema registry owner mismatch")
                descriptor = {key: value for key, value in descriptor.items() if key != "owner"}
            for field in validate_schema(descriptor, owner)["fields"]:
                if field["id"] in self.fields:
                    raise ConfigurationError("duplicate registered setting identity")
                self.fields[field["id"]] = {**field, "owner": owner, "schema_version": 1}

    @contextlib.contextmanager
    def _store(self, *, write=False):
        safe_path(self.directory)
        if not self.directory.exists():
            if not write:
                yield None
                return
            self.directory.mkdir(parents=True, mode=0o700, exist_ok=True)
        directory_fd = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            info = os.fstat(directory_fd)
            if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
                raise ConfigurationError("configuration directory is not private")
            fcntl.flock(directory_fd, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
            for candidate in (self.path, Path(str(self.path) + "-journal"), Path(str(self.path) + "-wal"), Path(str(self.path) + "-shm")):
                safe_path(candidate)
                if candidate.exists():
                    info = candidate.stat()
                    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600:
                        raise ConfigurationError("configuration backend is not private")
            if not self.path.exists():
                if not write:
                    yield None
                    return
                scope = self.history.ensure_scope()
                fd, temporary = tempfile.mkstemp(prefix=".bootstrap-", dir=self.directory)
                os.close(fd)
                try:
                    bootstrap = sqlite3.connect(temporary)
                    try:
                        bootstrap.executescript("""
                            PRAGMA user_version=1;
                            CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                            CREATE TABLE desired(target TEXT NOT NULL,id TEXT NOT NULL,record TEXT NOT NULL,PRIMARY KEY(target,id));
                        """)
                        bootstrap.executemany("INSERT INTO metadata VALUES (?,?)", [("scope_id", scope), ("revision", "0")])
                        bootstrap.commit()
                    finally:
                        bootstrap.close()
                    os.replace(temporary, self.path)
                finally:
                    if os.path.exists(temporary):
                        os.unlink(temporary)
            connection = sqlite3.connect(self.path.as_uri() + ("?mode=rw" if write else "?mode=ro"), uri=True, timeout=10)
            try:
                if connection.execute("PRAGMA user_version").fetchone()[0] != 1:
                    raise ConfigurationError("unsupported configuration store version; original retained")
                objects = {(kind, name) for kind, name in connection.execute("SELECT type,name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'")}
                if objects != {("table", "metadata"), ("table", "desired")} or connection.execute("PRAGMA quick_check").fetchone()[0] != "ok":
                    raise ConfigurationError("invalid configuration backend; original retained")
                metadata = dict(connection.execute("SELECT key,value FROM metadata"))
                if set(metadata) != {"scope_id", "revision"} or not metadata["revision"].isdigit():
                    raise ConfigurationError("invalid configuration metadata")
                object_ref(metadata["scope_id"], "installation:local")
                try:
                    history_scope = self.history.status()["scope_id"]
                except ValueError:
                    history_scope = None
                if history_scope is not None and history_scope != metadata["scope_id"]:
                    raise ConfigurationError("configuration scope differs from installation")
                if write and history_scope is None:
                    raise ConfigurationError("installation scope unavailable for configuration write")
                connection.execute("PRAGMA synchronous=FULL")
                connection.execute("BEGIN IMMEDIATE" if write else "PRAGMA query_only=ON")
                yield connection
                if write:
                    connection.commit()
            except BaseException:
                connection.rollback()
                raise
            finally:
                connection.close()
        except sqlite3.Error as exc:
            raise ConfigurationError("configuration backend unavailable/corrupt; original retained") from exc
        finally:
            os.close(directory_fd)

    def _metadata(self, db):
        if db:
            return dict(db.execute("SELECT key,value FROM metadata"))
        try:
            scope = self.history.status()["scope_id"]
        except ValueError:
            scope = None
        return {"scope_id": scope, "revision": "0"}

    def _field(self, ident, target, *, active=False):
        if type(ident) is not str or type(target) is not str:
            raise ConfigurationError("invalid scoped setting identity")
        field = self.fields.get(ident)
        if field is None:
            raise ConfigurationError("setting schema unavailable")
        expected = "installation:local" if field["scope"] == "installation" else "module:" + field["owner"]
        if target != expected:
            raise ConfigurationError("setting target outside declared scope")
        if active and not self.owner_active(field["owner"]):
            raise ConfigurationError("setting owner inactive")
        return field

    def _validate(self, field, value):
        value = validate_value(field, value)
        if field["type"] == "secret_ref":
            if self.secret_service is None:
                raise ConfigurationError("secret reference service unavailable")
            try:
                status = self.secret_service.inspect(value["reference"], owner=field["owner"], purpose=field["secret_purpose"])
            except ValueError as exc:
                raise ConfigurationError("secret reference unavailable") from exc
            if not status["configured"]:
                raise ConfigurationError("secret reference unavailable")
        if field["type"] == "path":
            root = self.path_roots.get(value["root"])
            if root is None:
                raise ConfigurationError("path root unavailable")
            root = Path(root).absolute()
            path = root / value["relative"]
            safe_path(path)
            try:
                path.resolve().relative_to(root.resolve())
            except ValueError as exc:
                raise ConfigurationError("path outside owned root") from exc
            kind = field.get("path_kind", "any")
            if kind != "any" and not (path.is_file() if kind == "file" else path.is_dir()):
                raise ConfigurationError("required path unavailable")
        return value

    def _records(self, db):
        records = []
        if db:
            for target, ident, text in db.execute("SELECT target,id,record FROM desired ORDER BY target,id"):
                row = self._record(decode(text))
                if row["target"] != target or row["id"] != ident:
                    raise ConfigurationError("configuration row identity mismatch")
                if row["revision"] > int(self._metadata(db)["revision"]):
                    raise ConfigurationError("configuration row revision exceeds store revision")
                records.append(row)
        return records

    def _record(self, row):
        closed(row, {"target", "id", "owner", "schema_version", "value", "unset", "revision", "operation_id", "changed_at", "source"},
               {"target", "id", "owner", "schema_version", "value", "unset", "revision", "operation_id", "changed_at", "source"}, "desired record")
        field = self._field(row["id"], row["target"])
        if row["owner"] != field["owner"] or row["schema_version"] != 1 or type(row["revision"]) is not int or row["revision"] < 1 or type(row["unset"]) is not bool:
            raise ConfigurationError("invalid desired record metadata")
        if type(row["operation_id"]) is not str or not re.fullmatch(r"op-[0-9a-f]{32}", row["operation_id"]):
            raise ConfigurationError("invalid operation reference")
        if type(row["changed_at"]) is not str or type(row["source"]) is not dict:
            raise ConfigurationError("invalid desired provenance")
        closed(row["source"], {"kind", "legacy"}, {"kind"}, "source")
        if type(row["source"]["kind"]) is not str or row["source"]["kind"] not in {"operator", "restore", "legacy_import"}:
            raise ConfigurationError("invalid source kind")
        if "legacy" in row["source"]:
            validate_legacy_source(row["source"]["legacy"])
        if row["unset"]:
            if row["value"] is not None or field["required"] and "default" not in field:
                raise ConfigurationError("invalid unset value")
        else:
            validate_value(field, row["value"])
        return row

    def _state_token(self, db):
        records = self._records(db)
        identities = sorted((r["target"], r["id"], r["revision"], r["operation_id"], r["value"], r["unset"]) for r in records)
        return hashlib.sha256(compact([int(self._metadata(db)["revision"]), identities]).encode()).hexdigest()

    def status(self):
        with self._store() as db:
            metadata = self._metadata(db)
            return {"schema_version": 1, "availability": "available" if db else "not_created",
                    "scope_id": metadata["scope_id"], "revision": int(metadata["revision"]), "settings": len(self._records(db)), "state_token": self._state_token(db)}

    def declarations(self):
        """Return owner-stamped schemas without opening or creating storage."""
        grouped = {}
        for ident in sorted(self.fields):
            field = self.fields[ident]
            owner = field["owner"]
            public = {key: value for key, value in field.items()
                      if key not in {"owner", "schema_version"}}
            grouped.setdefault(owner, []).append(public)
        return [{"owner": owner,
                 "schema": {"schema_version": 1, "owner": owner, "fields": fields}}
                for owner, fields in sorted(grouped.items())]

    def inspect(self, ident="ai.verbose", target="installation:local", *, compatibility=None, overrides=None):
        field = self._field(ident, target)
        with self._store() as db:
            metadata = self._metadata(db)
            state_token = self._state_token(db)
            row = next((r for r in self._records(db) if (r["target"], r["id"]) == (target, ident)), None)
        value = row["value"] if row and not row["unset"] else field.get("default")
        source = "desired" if row and not row["unset"] else "default"
        if row is None and compatibility is not None:
            value = validate_value(field, compatibility["value"])
            source = "compatibility"
        for kind in ("environment", "session"):
            if overrides and kind in overrides:
                if kind not in field["overrides"]:
                    raise ConfigurationError("override not permitted")
                value, source = self._validate(field, overrides[kind]), kind
        secret = field["type"] == "secret_ref"
        history_reference = None
        if row:
            history_reference = {"operation_id": row["operation_id"], "availability": "unavailable"}
            try:
                self.history.inspect(row["operation_id"])
                history_reference["availability"] = "available"
            except ValueError:
                pass
        result = {"schema_version": 1, "scope_id": metadata["scope_id"], "target": target, "id": ident,
                "schema_owner": field["owner"], "declaration": field,
                "availability": "available" if self.owner_active(field["owner"]) else "owner_inactive",
                "revision": int(metadata["revision"]), "state_token": state_token, "default": field.get("default"),
                "desired": {"status": ("value" if not row["unset"] else "unset") if row else "absent", "value": row["value"] if row else None},
                "resolved": {"status": "resolved" if value is not None else "unconfigured", "value": value, "source": source},
                "secret": secret, "observed": {"status": "unavailable", "owner": "system_model"},
                "application": {"status": "not_verified", "owner": "capability_execution"},
                "last_change": {k: row[k] for k in ("revision", "operation_id", "changed_at", "source")} if row else None,
                "history_reference": history_reference,
                "compatibility": compatibility if row is None else None}
        if ident == MEMORY_WARNING:
            result["runtime_consumption"] = _memory_consumption(result) if self.owner_active("system") else {"status": "owner_inactive", "verification": "not_verified"}
        return result

    def resolve_ai_verbose(self, *, compatibility_loader=None):
        """Resolve the Core-owned startup setting without claiming global state.

        The AI session only needs the current value plus the store revision.
        Computing the normal inspection state token would validate every desired
        record and therefore requires every installed module configuration
        schema.  This narrow consumer reads only the Core-owned row from the
        same authoritative store.  It deliberately returns no state token and
        cannot be used for configuration writes or compare-and-swap admission.
        """
        field = self._field("ai.verbose", "installation:local")
        with self._store() as db:
            metadata = self._metadata(db)
            row = None
            if db:
                raw = db.execute(
                    "SELECT record FROM desired WHERE target=? AND id=?",
                    ("installation:local", "ai.verbose"),
                ).fetchone()
                if raw is not None:
                    row = self._record(decode(raw[0]))
        if row is not None:
            value = field.get("default") if row["unset"] else row["value"]
            source = "default" if row["unset"] else "desired"
        else:
            value = field.get("default")
            source = "default"
            if compatibility_loader is not None:
                compatibility = compatibility_loader()
                value = validate_value(field, compatibility["value"])
                source = "compatibility"
        return {
            "schema_version": 1,
            "id": "ai.verbose",
            "target": "installation:local",
            "revision": int(metadata["revision"]),
            "resolved": {"status": "resolved", "value": value, "source": source},
        }

    def resolve_system_memory_warning(self):
        """Resolve System's health threshold without global configuration proof.

        The caller supplies only System's already-validated configuration schema.
        This consumer reads the same authoritative desired store and current
        global revision, but deliberately does not compute a state token.  State
        tokens remain mandatory for mutation admission and explicit readback
        verification.
        """
        field = self._field(MEMORY_WARNING, MEMORY_TARGET)
        with self._store() as db:
            metadata = self._metadata(db)
            row = None
            if db:
                raw = db.execute(
                    "SELECT record FROM desired WHERE target=? AND id=?",
                    (MEMORY_TARGET, MEMORY_WARNING),
                ).fetchone()
                if raw is not None:
                    row = self._record(decode(raw[0]))
        value = field.get("default") if row is None or row["unset"] else row["value"]
        source = "default" if row is None or row["unset"] else "desired"
        return {
            "schema_version": 1,
            "id": MEMORY_WARNING,
            "target": MEMORY_TARGET,
            "revision": int(metadata["revision"]),
            "resolved": {"status": "resolved", "value": value, "source": source},
        }

    def export(self):
        with self._store() as db:
            metadata = self._metadata(db)
            return {"configuration_export_version": 1, "scope_id": metadata["scope_id"],
                    "revision": int(metadata["revision"]), "records": self._records(db)}

    def validate(self, changes):
        if type(changes) is not list or not 1 <= len(changes) <= 64:
            raise ConfigurationError("changes must be bounded")
        normalized, seen = [], set()
        for change in changes:
            closed(change, {"id", "target", "value", "unset"}, {"id", "target"}, "change")
            field = self._field(change["id"], change["target"], active=True)
            identity = (change["target"], change["id"])
            if identity in seen or type(change.get("unset", False)) is not bool:
                raise ConfigurationError("duplicate or malformed change")
            seen.add(identity)
            unset = change.get("unset", False)
            if unset:
                if "value" in change or field["required"] and "default" not in field:
                    raise ConfigurationError("required value cannot be unset")
                value = None
            else:
                if "value" not in change:
                    raise ConfigurationError("missing proposed value")
                value = self._validate(field, change["value"])
            normalized.append({"id": change["id"], "target": change["target"], "value": value, "unset": unset})
        with self._store() as db:
            self._candidate(normalized, self._records(db))
        return normalized

    def _candidate(self, normalized, previous):
        touched = {c["target"] for c in normalized}
        candidate = {}
        for ident, field in self.fields.items():
            target = "installation:local" if field["scope"] == "installation" else "module:" + field["owner"]
            if target in touched:
                candidate[(target, ident)] = field.get("default")
        for row in previous:
            if row["target"] in touched and not row["unset"]:
                candidate[(row["target"], row["id"])] = row["value"]
        for change in normalized:
            field = self._field(change["id"], change["target"], active=True)
            candidate[(change["target"], change["id"])] = field.get("default") if change["unset"] else change["value"]
        for (target, ident), value in candidate.items():
            if value is None and self._field(ident, target)["required"]:
                raise ConfigurationError("required candidate value unavailable")
        if self.domain_validator:
            self.domain_validator(candidate)
        return candidate

    def _backup(self, document):
        path = self.directory / "recovery.json"
        safe_path(path)
        fd, temporary = tempfile.mkstemp(prefix=".recovery-", dir=self.directory)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                stream.write(compact(document))
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, path)
            directory_fd = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def commit(self, changes, *, expected_revision, expected_state, operation_id, source=None, legacy=None):
        normalized = self.validate(changes)
        if type(expected_revision) is not int or expected_revision < 0 or not re.fullmatch(r"op-[0-9a-f]{32}", operation_id):
            raise ConfigurationError("invalid revision or operation identity")
        with self._store(write=True) as db:
            metadata = self._metadata(db)
            current = int(metadata["revision"])
            if current != expected_revision or self._state_token(db) != expected_state:
                raise ConfigurationError("configuration revision conflict")
            previous = self._records(db)
            for change in normalized:
                if not change["unset"]:
                    self._validate(self._field(change["id"], change["target"], active=True), change["value"])
            self._candidate(normalized, previous)
            backup = {"configuration_export_version": 1, "scope_id": metadata["scope_id"], "revision": current, "records": previous}
            if legacy is not None:
                backup["legacy_baseline"] = {"id": "ai.verbose", "target": "installation:local", "value": legacy["value"], "source": legacy["source"]}
            self._backup(backup)
            revision = current + 1
            for change in normalized:
                field = self._field(change["id"], change["target"], active=True)
                provenance = source or {"kind": "operator"}
                if legacy is not None and not any(r["id"] == change["id"] and r["target"] == change["target"] for r in previous):
                    provenance = {**provenance, "legacy": legacy["source"]}
                row = self._record({**change, "owner": field["owner"], "schema_version": 1,
                                    "revision": revision, "operation_id": operation_id,
                                    "changed_at": datetime.now(timezone.utc).isoformat(), "source": provenance})
                db.execute("INSERT OR REPLACE INTO desired VALUES (?,?,?)", (row["target"], row["id"], compact(row)))
            db.execute("UPDATE metadata SET value=? WHERE key='revision'", (str(revision),))
        return {"revision": revision, "operation_id": operation_id, "application": "not_verified"}

    def prepare_restore(self, document):
        closed(document, {"configuration_export_version", "scope_id", "revision", "records", "legacy_baseline"},
               {"configuration_export_version", "scope_id", "revision", "records"}, "configuration export")
        if type(document["configuration_export_version"]) is not int or document["configuration_export_version"] != 1 or type(document["records"]) is not list or len(document["records"]) > 4096:
            raise ConfigurationError("unsupported or malformed configuration export")
        status = self.status()
        if document["scope_id"] != status["scope_id"] or type(document["revision"]) is not int or document["revision"] < 0:
            raise ConfigurationError("export scope/revision mismatch")
        changes, identities = [], set()
        for raw in document["records"]:
            row = self._record(raw)
            identity = row["target"], row["id"]
            if identity in identities or row["revision"] > document["revision"]:
                raise ConfigurationError("duplicate or future export record")
            identities.add(identity)
            changes.append({"target": row["target"], "id": row["id"], **({"unset": True} if row["unset"] else {"value": row["value"]})})
        for row in self.export()["records"]:
            if (row["target"], row["id"]) not in identities:
                changes.append({"target": row["target"], "id": row["id"], "unset": True})
        if "legacy_baseline" in document:
            baseline = closed(document["legacy_baseline"], {"id", "target", "value", "source"}, {"id", "target", "value", "source"}, "legacy baseline")
            if baseline["id"] != "ai.verbose" or baseline["target"] != "installation:local" or document["records"]:
                raise ConfigurationError("invalid legacy baseline scope")
            validate_legacy_source(baseline["source"])
            changes = [{"target": baseline["target"], "id": baseline["id"], "value": baseline["value"]}]
        if not changes:
            raise ConfigurationError("empty recovery has no settings to restore")
        return self.validate(changes)

    def restore(self, document, *, expected_revision, expected_state, operation_id):
        changes = self.prepare_restore(document)
        proposals = [{"target": c["target"], "id": c["id"], **({"unset": True} if c["unset"] else {"value": c["value"]})} for c in changes]
        return self.commit(proposals, expected_revision=expected_revision, expected_state=expected_state, operation_id=operation_id, source={"kind": "restore"})


def capability_records(system_active=False):
    records = []
    for ident, tier, properties, verification, description in [
        ("core.configuration.ai_verbose.set", "CHANGE", {"value": {"type": "boolean"}, "revision": {"type": "integer", "minimum": 0}, "state": {"type": "string", "minLength": 64, "maxLength": 64}},
         "configuration_revision", "Commit desired ai.verbose; runtime application is separate"),
        ("core.configuration.ai_verbose.verify", "READ", {"revision": {"type": "integer", "minimum": 1}},
         "ai_verbose_session", "Verify this AI session consumed the desired ai.verbose revision"),
        ("core.configuration.restore", "CHANGE", {"document": {"type": "string", "maxLength": 262144}, "revision": {"type": "integer", "minimum": 0}, "state": {"type": "string", "minLength": 64, "maxLength": 64}},
         "configuration_restore", "Restore validated desired configuration; application is separate"),
    ]:
        descriptor = {"kind": "capability", "id": ident, "handler": "core_configuration_adapter", "capability_version": 1,
                      "description": description, "inputs": {"properties": properties, "required": list(properties), "additionalProperties": False},
                      "safety": {"tier": tier}, "privilege": "none", "preconditions": [],
                      "verification": {"kind": verification, "required": True}, "recovery": {"class": "reversible" if tier == "CHANGE" else "not_applicable"},
                      "affects": ["installation:local"]}
        records.append({"id": ident, "owner": "core", "provider": "core", "source": "core.configuration.v1",
                        "availability": "active", "unavailable_reason": None, "descriptor": descriptor})
    properties = {"value": {"type": "integer"}, "revision": {"type": "integer", "minimum": 0},
                  "state": {"type": "string", "minLength": 64, "maxLength": 64}}
    records.append({"id": "core.configuration.system_memory_warning.set", "owner": "core", "provider": "core",
                    "source": "core.configuration.v1", "availability": "active" if system_active else "inactive",
                    "unavailable_reason": None if system_active else "configuration_owner_inactive",
                    "descriptor": {"kind": "capability", "id": "core.configuration.system_memory_warning.set",
                    "handler": "core_configuration_adapter", "capability_version": 1,
                    "description": "Commit System desired memory warning threshold; application is separate",
                    "inputs": {"properties": properties, "required": list(properties), "additionalProperties": False},
                    "safety": {"tier": "CHANGE"}, "privilege": "none", "preconditions": [],
                    "verification": {"kind": "system_memory_configuration_revision", "required": True},
                    "recovery": {"class": "reversible"}, "affects": [MEMORY_TARGET]}})
    return records


def cli():
    try:
        action = sys.argv[1]
        if action == "resolve-ai-verbose":
            # Dedicated startup consumer: arguments arrive as environment data
            # rather than paying for a separate Python JSON-builder process.
            # This path is Core-only and intentionally has no module activation
            # or state-token authority.
            request = {
                "igor_dir": os.environ["IGOR_CONFIGURATION_ROOT"],
                "data_dir": os.environ["IGOR_CONFIGURATION_DATA_DIR"],
                "inherited_verbose": os.environ.get("IGOR_CONFIGURATION_INHERITED_VERBOSE") or None,
            }
            root = Path(request["igor_dir"])
            active = {"core"}
            schemas = []
        elif action == "resolve-system-memory-warning":
            # Boundary O consumes the loader's already-validated System
            # configuration contribution. It neither rediscovers installed
            # schemas nor computes a global state token.
            record = decode(os.environ["IGOR_CONFIGURATION_SYSTEM_MEMORY_RECORD"])
            if (type(record) is not dict or record.get("kind") != "configuration" or
                    record.get("id") != "system.memory.preferences" or
                    type(record.get("schema")) is not dict):
                raise ConfigurationError("invalid System memory configuration declaration")
            request = {"data_dir": os.environ["IGOR_CONFIGURATION_DATA_DIR"]}
            root = None
            active = {"core", "system"}
            schemas = [("system", record["schema"])]
        else:
            request = decode(sys.stdin.read())
            root = Path(request["igor_dir"])
            # Runtime callers supply the actual loader-owned activation snapshot.
            # Standalone inspection admits no module writes without that snapshot.
            active = set(request.get("active_owners", ["core"]))
            schemas = installed_schemas(root)
        service = ConfigurationService(Path(request["data_dir"]), schemas=schemas,
                                       owner_active=lambda owner: owner == "core" or owner in active)
        if action == "resolve-ai-verbose":
            result = service.resolve_ai_verbose(
                compatibility_loader=lambda: legacy_verbose(
                    root, request.get("inherited_verbose")
                )
            )
        elif action == "resolve-system-memory-warning":
            result = service.resolve_system_memory_warning()
            # Fixed internal framing keeps startup to one Python process. Both
            # fields are schema-validated integers before they reach the shell.
            print(f'{result["resolved"]["value"]}\t{result["revision"]}')
            return 0
        elif action == "capabilities":
            result = capability_records("system" in active)
        elif action == "declarations":
            result = service.declarations()
        elif action == "status":
            result = service.status()
        elif action == "export":
            result = service.export()
        elif action == "managed":
            result = {"ai_verbose": service.inspect()["last_change"] is not None}
        elif action in {"inspect", "list", "resolve"}:
            ident = request.get("id", "ai.verbose")
            target = request.get("target", "installation:local")
            state = service.inspect(ident, target)
            if ident == "ai.verbose" and state["last_change"] is None:
                compatibility = legacy_verbose(Path(request["igor_dir"]), request.get("inherited_verbose"))
                state = service.inspect(compatibility=compatibility)
            result = [state if field["id"] == "ai.verbose" else service.inspect(field["id"], "module:" + field["owner"]) for field in service.fields.values()] if action == "list" else state
        elif action == "validate":
            result = service.validate(request["changes"] if "changes" in request else decode(request["changes_document"]))
        elif action == "prepare":
            memory = request["capability_id"] == "core.configuration.system_memory_warning.set"
            state = service.inspect(MEMORY_WARNING, MEMORY_TARGET) if memory else service.inspect()
            if (state["revision"] != request["revision"] or
                    (request["capability_id"] != "core.configuration.ai_verbose.verify" and state["state_token"] != request["state"])):
                raise ConfigurationError("configuration revision conflict")
            capability = request["capability_id"]
            if memory:
                result = service.validate([{"id": MEMORY_WARNING, "target": MEMORY_TARGET, "value": request["value"]}])
            elif capability == "core.configuration.ai_verbose.set":
                result = service.validate([{"id": "ai.verbose", "target": "installation:local", "value": request["value"]}])
                if state["last_change"] is None:
                    legacy_verbose(Path(request["igor_dir"]), request.get("inherited_verbose"))
            elif capability == "core.configuration.restore":
                result = service.prepare_restore(decode(request["document"]))
            elif capability == "core.configuration.ai_verbose.verify":
                result = {"revision": state["revision"]}
            else:
                raise ConfigurationError("unreviewed configuration capability")
        elif action == "set":
            legacy = legacy_verbose(Path(request["igor_dir"]), request.get("inherited_verbose")) if service.inspect()["last_change"] is None else None
            result = service.commit([{"id": "ai.verbose", "target": "installation:local", "value": request["value"]}],
                                    expected_revision=request["revision"], expected_state=request["state"], operation_id=request["operation_id"], legacy=legacy)
        elif action == "memory-set":
            result = service.commit([{"id": MEMORY_WARNING, "target": MEMORY_TARGET, "value": request["value"]}],
                                    expected_revision=request["revision"], expected_state=request["state"], operation_id=request["operation_id"])
        elif action == "memory-prepare":
            state = service.inspect(MEMORY_WARNING, MEMORY_TARGET)
            if (state["availability"] != "available" or state["revision"] != request["revision"] or
                    state["state_token"] != request["state"] or
                    ("value" in request and state["resolved"]["value"] != request["value"])):
                raise ConfigurationError("memory configuration consumption conflict")
            result = {"revision": state["revision"], "value": state["resolved"]["value"]}
        elif action == "memory-verify-desired":
            state = service.inspect(MEMORY_WARNING, MEMORY_TARGET)
            if state["revision"] != request["revision"] + 1 or state["desired"] != {"status": "value", "value": request["value"]}:
                raise ConfigurationError("desired memory revision verification failed")
            result = {"source": "configuration.desired", "revision": state["revision"], "application": "not_verified"}
        elif action == "restore":
            result = service.restore(decode(request["document"]), expected_revision=request["revision"], expected_state=request["state"], operation_id=request["operation_id"])
        elif action == "verify":
            state = service.inspect()
            revision = request["revision"]
            if state["revision"] != revision + 1:
                raise ConfigurationError("desired revision verification failed")
            if "value" in request and state["desired"] != {"status": "value", "value": request["value"]}:
                raise ConfigurationError("desired value verification failed")
            if "document" in request:
                for change in service.prepare_restore(decode(request["document"])):
                    desired = service.inspect(change["id"], change["target"])["desired"]
                    if desired != {"status": "unset" if change["unset"] else "value", "value": change["value"]}:
                        raise ConfigurationError("restored values verification failed")
            result = {"source": "configuration.desired", "revision": state["revision"], "application": "not_verified"}
        elif action == "verify-session":
            state = service.inspect()
            value = os.environ.get("IGOR_VERBOSE")
            if (state["revision"] != request["revision"] or value not in {"true", "false"} or
                    (value == "true") != state["resolved"]["value"] or os.environ.get("IGOR_VERBOSE_REVISION") != str(request["revision"])):
                raise ConfigurationError("current session consumption is unverified")
            result = {"source": "ai.session.consumer", "revision": request["revision"], "value": value == "true",
                      "session_id": request.get("session_id"), "application": "verified_current_session_only"}
        else:
            raise ConfigurationError("unsupported configuration action")
        print(compact(result))
        return 0
    except (ConfigurationError, ValueError, KeyError, TypeError, OSError) as exc:
        # Do not echo malformed proposals, paths, secrets or backend errors.
        print("configuration unavailable: " + (str(exc) if isinstance(exc, ConfigurationError) else "invalid request or source"), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(cli())
