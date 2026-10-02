"""Deployment metadata v1: identities, relationships and explicit responsibility.

The SQLite layout is private. This service never observes resources, executes a
capability, grants execution approval or certifies adoption/detach. A trusted
Core authorizer gates metadata transitions; retained provenance is not authority.
"""
from __future__ import annotations

import argparse
import contextlib
import copy
import fcntl
import hashlib
import json
import math
import os
import re
import sqlite3
import stat
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from operational_history import OBJECT, SCOPE, HistoryError, OperationalHistory

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ai"))
from privacy import redactions, scrub_text

VERSION = 1
OWNER = "core.deployments"
MAX_RECORDS = 4096
MAX_BYTES = 4 * 1024 * 1024
IDENT = re.compile(r"[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*")
OPERATION = re.compile(r"op-[0-9a-f]{32}")
EPOCH = re.compile(r"[0-9a-f]{32}")
KINDS = {"service", "database", "storage", "network", "endpoint", "configuration_target",
         "secret_reference", "external_dependency"}
RELATIONSHIPS = {"includes", "depends_on", "uses", "exposes"}
DUTIES = {"observation", "configuration", "lifecycle", "backup", "update"}
SOURCES = {"operator", "module", "discovery", "configuration", "installer", "ai", "restore"}
RECORD_TYPES = {"deployment", "resource", "relationship", "responsibility", "claim"}
BASE = {"schema_version", "record_type", "reference", "record_owner", "revision", "created_at",
        "source", "last_change", "lifecycle"}
EXTRA = {
    "deployment": {"label", "application", "providers"},
    "resource": {"identity_owner", "kind", "label", "origin", "native"},
    "relationship": {"deployment", "kind", "subject", "target", "role", "evidence", "claim"},
    "responsibility": {"deployment", "subject", "duty", "setting_id", "providers", "accepted_by", "disposition"},
    "claim": {"deployment", "kind", "subject", "target", "role", "evidence", "resolution"},
}
LIFECYCLES = {"deployment": {"known", "retained"}, "resource": {"known", "retained"},
              "relationship": {"active", "retired"}, "responsibility": {"active", "released"},
              "claim": {"proposed", "accepted", "rejected"}}


class DeploymentError(ValueError):
    """Unsupported, unavailable or conflicting metadata; original is retained."""


def _check(condition: bool, message: str) -> None:
    if not condition:
        raise DeploymentError(message)


def _closed(value: Any, required: set[str], optional: set[str] | None = None) -> dict:
    _check(type(value) is dict and required <= set(value) and not set(value) - required - (optional or set()),
           "invalid deployment contract fields")
    return value


def decode(value: str) -> Any:
    """Decode closed-protocol JSON without duplicate fields or nonfinite numbers."""
    def unique(pairs):
        result = {}
        for key, item in pairs:
            _check(key not in result, "duplicate deployment JSON field")
            result[key] = item
        return result
    def invalid(_constant):
        raise DeploymentError("nonfinite deployment JSON number")
    def finite(number):
        result = float(number)
        _check(math.isfinite(result), "nonfinite deployment JSON number")
        return result
    try:
        _check(type(value) is str and len(value.encode()) <= MAX_BYTES, "deployment document exceeds limit")
        return json.loads(value, object_pairs_hook=unique, parse_constant=invalid, parse_float=finite)
    except (TypeError, ValueError, RecursionError) as exc:
        if isinstance(exc, DeploymentError):
            raise
        raise DeploymentError("malformed deployment JSON") from exc


def _compact(value: Any) -> str:
    try:
        text = json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)
        _check(len(text.encode()) <= MAX_BYTES, "deployment document exceeds limit")
        return text
    except (TypeError, ValueError, RecursionError) as exc:
        if isinstance(exc, DeploymentError):
            raise
        raise DeploymentError("malformed deployment document") from exc


def _copy(value: Any) -> Any:
    return decode(_compact(value))


def _text(value: Any, limit: int = 256) -> str:
    _check(type(value) is str and 0 < len(value) <= limit and not re.search(r"[\x00-\x1f\x7f]", value),
           "invalid deployment text")
    _check(scrub_text(value, pairs=[]) == value, "secret-bearing deployment metadata")
    return value


def _screen_metadata(value: Any) -> None:
    """Screen free metadata once at admission; IDs remain deterministic on reads."""
    pairs = redactions()
    def visit(item, depth=0):
        _check(depth <= 16, "deployment metadata exceeds depth limit")
        if type(item) is dict:
            for key, child in item.items():
                if key in {"label", "native_id", "provider_scope", "incarnation"} and type(child) is str:
                    _check(scrub_text(child, pairs=pairs) == child, "secret-bearing deployment metadata")
                visit(child, depth + 1)
        elif type(item) is list:
            for child in item:
                visit(child, depth + 1)
    visit(value)


def _ident(value: Any) -> str:
    _text(value, 160)
    _check(bool(IDENT.fullmatch(value)), "invalid deployment identifier")
    return value


def _ref(value: Any) -> dict:
    _closed(value, {"scope_id", "object_id"})
    _check(type(value["scope_id"]) is str and bool(SCOPE.fullmatch(value["scope_id"])) and
           type(value["object_id"]) is str and bool(OBJECT.fullmatch(value["object_id"])), "invalid scoped deployment reference")
    _text(value["object_id"], 160)
    return dict(value)


def _key(value: dict) -> str:
    return value["scope_id"] + "/" + value["object_id"]


def _source(value: Any) -> dict:
    _closed(value, {"kind", "id", "owner"})
    _check(type(value["kind"]) is str and value["kind"] in SOURCES, "invalid deployment source kind")
    _ident(value["id"])
    _ident(value["owner"])
    return value


def _operation(value: Any) -> str:
    _check(type(value) is str and bool(OPERATION.fullmatch(value)), "invalid metadata operation identity")
    return value


def _timestamp(value: Any) -> str:
    _text(value, 64)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        _check(parsed.tzinfo is not None, "timestamp requires timezone")
    except ValueError as exc:
        raise DeploymentError("invalid deployment timestamp") from exc
    return value


def _array(value: Any, limit: int = 64) -> list:
    _check(type(value) is list and len(value) <= limit, "unbounded deployment list")
    return value


def _providers(value: Any) -> list:
    seen = set()
    for item in _array(value):
        _closed(item, {"id", "owner", "version"})
        _ident(item["id"])
        _ident(item["owner"])
        _check(type(item["version"]) is int and 1 <= item["version"] <= 2**31, "invalid provider version")
        _check(item["id"] not in seen, "duplicate deployment provider")
        seen.add(item["id"])
    return value


def _native(value: Any) -> None:
    if value is None:
        return
    _closed(value, {"provider", "provider_scope", "native_id", "incarnation"})
    _ident(value["provider"])
    for key in ("provider_scope", "native_id"):
        _text(value[key], 512)
    if value["incarnation"] is not None:
        _text(value["incarnation"], 256)


def _evidence(value: Any) -> list:
    seen = set()
    for item in _array(value):
        _closed(item, {"reference", "source", "availability", "recorded_at"})
        _ref(item["reference"])
        _source(item["source"])
        _timestamp(item["recorded_at"])
        _check(type(item["availability"]) is str and item["availability"] in {"retained", "unavailable"},
               "invalid evidence availability")
        identity = _compact(item)
        _check(identity not in seen, "duplicate relationship evidence")
        seen.add(identity)
    return value


def _topology_fields(row: dict) -> None:
    for field in ("deployment", "subject", "target"):
        _ref(row[field])
    _check(type(row["kind"]) is str and row["kind"] in RELATIONSHIPS, "unknown relationship kind")
    _ident(row["role"])
    _evidence(row["evidence"])


def validate_record(value: Any) -> dict:
    """Validate a public closed record without consulting observations/modules."""
    row = _copy(value)
    _check(type(row) is dict and type(row.get("record_type")) is str and row["record_type"] in RECORD_TYPES,
           "unknown deployment record type")
    typ = row["record_type"]
    _closed(row, BASE | EXTRA[typ])
    _check(type(row["schema_version"]) is int and row["schema_version"] == VERSION, "unknown deployment record version")
    _ref(row["reference"])
    _check(row["record_owner"] == OWNER, "deployment record owner mismatch")
    _check(type(row["revision"]) is int and 1 <= row["revision"] <= 2**63 - 1, "invalid record revision")
    _timestamp(row["created_at"])
    _source(row["source"])
    _closed(row["last_change"], {"operation_id", "source", "at"})
    _operation(row["last_change"]["operation_id"])
    _source(row["last_change"]["source"])
    _timestamp(row["last_change"]["at"])
    _check(type(row["lifecycle"]) is str and row["lifecycle"] in LIFECYCLES[typ], "invalid metadata lifecycle")
    if typ != "resource":
        _check(bool(re.fullmatch(typ + r":[0-9a-f]{32}", row["reference"]["object_id"])), "nonopaque Igor identity")
    if typ == "deployment":
        _text(row["label"])
        _ident(row["application"])
        _providers(row["providers"])
    elif typ == "resource":
        _ident(row["identity_owner"])
        if row["identity_owner"] == OWNER:
            _check(bool(re.fullmatch(r"resource:[0-9a-f]{32}", row["reference"]["object_id"])), "nonopaque enrolled resource identity")
        _check(type(row["kind"]) is str and row["kind"] in KINDS, "unknown resource class")
        _text(row["label"])
        _check(type(row["origin"]) is str and row["origin"] in {"external", "igor_provisioned", "unknown"}, "invalid resource origin")
        _native(row["native"])
    elif typ in {"relationship", "claim"}:
        _topology_fields(row)
        if typ == "relationship":
            if row["claim"] is not None:
                _ref(row["claim"])
        elif row["resolution"] is not None:
            _closed(row["resolution"], {"decision", "operation_id", "source", "at"})
            _check(type(row["resolution"]["decision"]) is str and row["resolution"]["decision"] in {"accept", "reject"}, "invalid claim decision")
            _operation(row["resolution"]["operation_id"])
            _source(row["resolution"]["source"])
            _check(row["resolution"]["source"]["kind"] == "operator", "claim resolution requires operator provenance")
            _timestamp(row["resolution"]["at"])
        if typ == "claim":
            expected = {"proposed": None, "accepted": "accept", "rejected": "reject"}[row["lifecycle"]]
            _check((None if row["resolution"] is None else row["resolution"]["decision"]) == expected,
                   "claim lifecycle differs from resolution")
    else:
        _ref(row["deployment"])
        _ref(row["subject"])
        _check(type(row["duty"]) is str and row["duty"] in DUTIES, "unknown responsibility duty")
        if row["setting_id"] is not None:
            _ident(row["setting_id"])
            _check(row["duty"] == "configuration", "setting selector requires configuration duty")
        provider_ids = [_ident(item) for item in _array(row["providers"])]
        _check(len(provider_ids) == len(set(provider_ids)), "duplicate grant provider")
        _source(row["accepted_by"])
        _check(row["accepted_by"]["kind"] == "operator", "responsibility requires positive operator acceptance")
        _check(row["disposition"] is None or (type(row["disposition"]) is str and row["disposition"] in
               {"retained_external", "transferred", "unresolved"}), "invalid retained disposition")
        _check((row["lifecycle"] == "active") == (row["disposition"] is None), "grant lifecycle differs from disposition")
    return row


def _validate_graph(records: list[dict], scope_id: str) -> None:
    _array(records, MAX_RECORDS)
    by_ref = {}
    for row in records:
        validate_record(row)
        key = _key(row["reference"])
        _check(key not in by_ref, "duplicate durable record identity")
        _check(row["record_type"] == "resource" or row["reference"]["scope_id"] == scope_id, "nonlocal deployment record")
        _check(row["record_type"] != "resource" or row["identity_owner"] != OWNER or row["reference"]["scope_id"] == scope_id,
               "service-enrolled resource must have local scope")
        by_ref[key] = row
    includes, topology, natives = set(), set(), set()
    for row in records:
        typ = row["record_type"]
        if typ == "resource" and row["native"] is not None and row["lifecycle"] == "known":
            native = row["native"]
            key = (row["reference"]["scope_id"], *(native[k] for k in ("provider", "provider_scope", "native_id")))
            _check(key not in natives, "native resource already has an Igor identity")
            natives.add(key)
        if typ not in {"relationship", "claim", "responsibility"}:
            continue
        dep = by_ref.get(_key(row["deployment"]))
        _check(dep is not None and dep["record_type"] == "deployment", "deployment reference unavailable")
        for field in (("subject", "target") if typ != "responsibility" else ("subject",)):
            item = by_ref.get(_key(row[field]))
            _check(item is not None and item["record_type"] in {"deployment", "resource"}, "relationship subject/target unavailable")
        if typ in {"relationship", "claim"}:
            subject, target = by_ref[_key(row["subject"])], by_ref[_key(row["target"])]
            _check(row["subject"] != row["target"], "self relationship is unsupported")
            if row["kind"] == "includes":
                _check(row["subject"] == row["deployment"] and target["record_type"] == "resource",
                       "includes requires deployment and resource")
            elif row["kind"] == "uses":
                uses = {"storage": "storage", "network": "network", "configuration": "configuration_target",
                        "secret_reference": "secret_reference", "database": "database", "external_dependency": "external_dependency"}
                _check(target["record_type"] == "resource" and row["role"] in uses and target["kind"] == uses[row["role"]],
                       "uses requires typed consumed resource role")
            elif row["kind"] == "exposes":
                _check(subject["record_type"] == "resource" and subject["kind"] == "endpoint" and
                       (target["record_type"] == "deployment" or target["kind"] == "service"),
                       "exposes requires endpoint and deployment/service")
        if typ != "relationship" or row["lifecycle"] != "active":
            continue
        _check(dep["lifecycle"] == "known", "retained deployment has active relationship")
        slot = (_key(row["deployment"]), row["kind"], _key(row["subject"]), row["role"])
        _check(slot not in topology, "conflicting relationship slot requires explicit reconciliation")
        topology.add(slot)
        if row["kind"] == "includes":
            _check(row["subject"] == row["deployment"] and by_ref[_key(row["target"])]["record_type"] == "resource",
                   "includes requires deployment and resource")
            includes.add((_key(row["deployment"]), _key(row["target"])))
        else:
            _check(row["subject"] != row["target"], "self relationship is unsupported")
    grants = []
    for row in records:
        if row["record_type"] in {"relationship", "responsibility"} and row["lifecycle"] == "active":
            dep_key = _key(row["deployment"])
            fields = ("subject", "target") if row["record_type"] == "relationship" else ("subject",)
            for field in fields:
                ref = _key(row[field])
                _check(ref == dep_key or (dep_key, ref) in includes,
                       "active relationship/grant requires explicit deployment participation")
                _check(by_ref[ref]["lifecycle"] == "known", "retained resource cannot participate actively")
        if row["record_type"] == "relationship" and row["claim"] is not None:
            claim = by_ref.get(_key(row["claim"]))
            _check(claim is not None and claim["record_type"] == "claim" and
                   (row["lifecycle"] != "active" or claim["lifecycle"] == "accepted"),
                   "relationship claim reference unavailable")
            _check(all(row[key] == claim[key] for key in ("deployment", "kind", "subject", "target", "role")),
                   "relationship differs from accepted claim")
        if row["record_type"] != "responsibility" or row["lifecycle"] != "active":
            continue
        dep = by_ref[_key(row["deployment"])]
        _check(dep["lifecycle"] == "known", "retained deployment has active grant")
        _check(set(row["providers"]) <= {p["id"] for p in dep["providers"]}, "grant provider not declared by deployment")
        coverage = {_key(row["subject"])}
        if row["subject"] == row["deployment"]:
            coverage |= {resource for deployment, resource in includes if deployment == _key(row["deployment"])}
        for prior, prior_coverage in grants:
            overlap = (row["setting_id"] is None or prior["setting_id"] is None or row["setting_id"] == prior["setting_id"])
            shared_observation = row["duty"] == "observation" and row["deployment"] != prior["deployment"]
            _check(not (bool(coverage & prior_coverage) and row["duty"] == prior["duty"] and overlap and not shared_observation),
                   "shared resource/setting responsibility conflict")
        grants.append((row, coverage))


def _claim_conflicts(records):
    claims = [row for row in records if row["record_type"] == "claim" and row["lifecycle"] == "proposed"]
    relationships = [row for row in records if row["record_type"] == "relationship" and row["lifecycle"] == "active"]
    conflicts = []
    for claim in claims:
        others = [row for row in [*relationships, *claims] if row != claim and
                  all(claim[key] == row[key] for key in ("deployment", "kind", "subject", "role")) and claim["target"] != row["target"]]
        if others:
            conflicts.append((claim, others))
    return conflicts


def _issued_identity(row, scope_id):
    _closed(row, {"reference", "record_type"})
    reference = _ref(row["reference"])
    typ = row["record_type"]
    _check(type(typ) is str and typ in RECORD_TYPES, "invalid issued identity type")
    if typ != "resource":
        _check(reference["scope_id"] == scope_id and bool(re.fullmatch(typ + r":[0-9a-f]{32}", reference["object_id"])),
               "invalid issued Igor identity")
    return _key(reference), typ


def _safe_path(path: Path) -> None:
    _check(not any(part.is_symlink() for part in (path, *path.parents)), "deployment path contains symlink")


def _private(info, *, directory=False) -> None:
    kind = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
    _check(kind and info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == (0o700 if directory else 0o600)
           and (directory or info.st_nlink == 1), "deployment storage is not private")


class DeploymentService:
    """Application-neutral metadata owner; observations and approval are external."""

    def __init__(self, data_dir: Path, *, authorize=None, reference_resolver=None):
        self.data_dir = Path(data_dir).absolute()
        self.directory = self.data_dir / "deployments"
        self.path = self.directory / "store.sqlite3"
        self.history = OperationalHistory(self.data_dir)
        self.authorize = authorize
        self.reference_resolver = reference_resolver

    def _authorize(self, request: dict) -> None:
        _check(self.authorize is not None and self.authorize(_copy(request)) is True,
               "metadata transition requires trusted Core authorization")

    def _history_scope(self, *, write=False):
        try:
            scope = self.history.status()["scope_id"]
        except HistoryError as exc:
            if write:
                raise DeploymentError("installation scope unavailable for deployment mutation") from exc
            return None
        _check(not write or scope is not None, "installation scope unavailable for deployment mutation")
        return scope

    @contextlib.contextmanager
    def _store(self, *, write=False, initialize=False):
        _safe_path(self.directory)
        if not self.directory.exists():
            if not initialize:
                _check(not write, "deployment registry is not initialized")
                yield None
                return
            self.directory.mkdir(parents=True, mode=0o700, exist_ok=True)
        directory_fd = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            _private(os.fstat(directory_fd), directory=True)
            fcntl.flock(directory_fd, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
            for candidate in (self.path, Path(str(self.path) + "-journal"), Path(str(self.path) + "-wal"), Path(str(self.path) + "-shm"),
                              self.directory / "recovery.json"):
                _safe_path(candidate)
                if candidate.exists():
                    _private(candidate.stat())
            if not self.path.exists():
                if not initialize:
                    _check(not write, "deployment registry is not initialized")
                    yield None
                    return
                try:
                    scope = self.history.ensure_scope()
                except HistoryError as exc:
                    raise DeploymentError("installation scope unavailable for initialization") from exc
                fd, temporary = tempfile.mkstemp(prefix=".bootstrap-", dir=self.directory)
                os.close(fd)
                try:
                    bootstrap = sqlite3.connect(temporary)
                    try:
                        bootstrap.executescript("""
                            PRAGMA user_version=1;
                            CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                            CREATE TABLE records(id TEXT PRIMARY KEY,record TEXT NOT NULL);
                            CREATE TABLE identities(id TEXT PRIMARY KEY,type TEXT NOT NULL);
                            CREATE TABLE operations(id TEXT PRIMARY KEY,epoch TEXT NOT NULL,digest TEXT NOT NULL,result TEXT NOT NULL,kind TEXT NOT NULL);
                        """)
                        bootstrap.executemany("INSERT INTO metadata VALUES (?,?)", [("scope_id", scope), ("revision", "0"), ("epoch", uuid.uuid4().hex)])
                        bootstrap.commit()
                    finally:
                        bootstrap.close()
                    os.replace(temporary, self.path)
                    os.fsync(directory_fd)
                finally:
                    if os.path.exists(temporary):
                        os.unlink(temporary)
            db = sqlite3.connect(self.path.as_uri() + ("?mode=rw" if write else "?mode=ro"), uri=True, timeout=10)
            try:
                _check(db.execute("PRAGMA user_version").fetchone()[0] == 1, "unknown deployment store version; original retained")
                expected = {("table", name) for name in ("metadata", "records", "identities", "operations")}
                objects = set(db.execute("SELECT type,name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'"))
                _check(objects == expected and db.execute("PRAGMA quick_check").fetchone()[0] == "ok",
                       "malformed/corrupt deployment store; original retained")
                metadata = self._metadata(db)
                scope = self._history_scope(write=write)
                _check(scope is None or scope == metadata["scope_id"], "deployment scope differs from installation")
                db.execute("PRAGMA synchronous=FULL")
                db.execute("BEGIN IMMEDIATE" if write else "BEGIN")
                if not write:
                    db.execute("PRAGMA query_only=ON")
                self._snapshot(db)
                yield db
                if write:
                    db.commit()
            except BaseException:
                db.rollback()
                raise
            finally:
                db.close()
        except (sqlite3.Error, OSError) as exc:
            raise DeploymentError("deployment backend unavailable/corrupt; original retained") from exc
        finally:
            os.close(directory_fd)

    def _metadata(self, db) -> dict:
        if db is None:
            return {"scope_id": self._history_scope(), "revision": 0, "epoch": None}
        rows = list(db.execute("SELECT key,value FROM metadata"))
        metadata = dict(rows)
        _check(len(rows) == 3 and set(metadata) == {"scope_id", "revision", "epoch"}, "invalid deployment metadata")
        _ref({"scope_id": metadata["scope_id"], "object_id": "installation:local"})
        _check(bool(re.fullmatch(r"0|[1-9][0-9]{0,18}", metadata["revision"])), "invalid registry revision")
        metadata["revision"] = int(metadata["revision"])
        _check(metadata["revision"] < 2**63 and bool(EPOCH.fullmatch(metadata["epoch"])), "invalid registry revision/epoch")
        return metadata

    def _snapshot(self, db) -> dict:
        metadata = self._metadata(db)
        records, identities, operations = [], [], []
        if db is not None:
            for key, text in db.execute("SELECT id,record FROM records ORDER BY id"):
                row = validate_record(decode(text))
                _check(_key(row["reference"]) == key and row["revision"] <= metadata["revision"], "record index/revision mismatch")
                records.append(row)
            _validate_graph(records, metadata["scope_id"])
            for key, typ in db.execute("SELECT id,type FROM identities ORDER BY id"):
                parts = key.split("/", 1)
                _check(len(parts) == 2 and typ in RECORD_TYPES, "invalid identity ledger")
                ref = _ref({"scope_id": parts[0], "object_id": parts[1]})
                identity = {"reference": ref, "record_type": typ}
                _issued_identity(identity, metadata["scope_id"])
                identities.append(identity)
            ledger = {_key(row["reference"]): row["record_type"] for row in identities}
            _check(len(ledger) == len(identities) and len(ledger) <= MAX_RECORDS and all(ledger.get(_key(row["reference"])) == row["record_type"] for row in records),
                   "record identity missing from ledger")
            for ident, epoch, digest, result, kind in db.execute("SELECT id,epoch,digest,result,kind FROM operations ORDER BY id"):
                _operation(ident)
                _check(bool(EPOCH.fullmatch(epoch)) and bool(re.fullmatch(r"[0-9a-f]{64}", digest)) and kind in {"commit", "restore", "fence"},
                       "invalid metadata receipt")
                receipt = decode(result)
                if kind == "fence":
                    _check(receipt is None, "invalid recovery operation fence")
                else:
                    _closed(receipt, {"schema_version", "operation_id", "scope_id", "revision", "epoch", "changed", "metadata_only"})
                    _check(type(receipt["schema_version"]) is int and receipt["schema_version"] == VERSION and receipt["operation_id"] == ident and receipt["scope_id"] == metadata["scope_id"]
                           and type(receipt["revision"]) is int and 1 <= receipt["revision"] <= metadata["revision"]
                           and receipt["epoch"] == epoch and receipt["metadata_only"] is True, "invalid metadata receipt result")
                    for ref in _array(receipt["changed"], MAX_RECORDS):
                        _ref(ref)
                        _check(_key(ref) in ledger, "receipt references unissued identity")
                operations.append(ident)
            _array(operations, MAX_RECORDS)
            _check(len(operations) == len(set(operations)), "duplicate metadata operation identity")
            _check(all(row["last_change"]["operation_id"] in operations and
                       (row["record_type"] != "claim" or row["resolution"] is None or row["resolution"]["operation_id"] in operations)
                       for row in records), "record provenance operation unavailable")
        return {"schema_version": VERSION, **metadata, "records": records, "identities": identities, "operation_ids": operations}

    @staticmethod
    def _token(snapshot):
        return hashlib.sha256(_compact(snapshot).encode()).hexdigest()

    def initialize(self, *, source: dict) -> dict:
        _source(source)
        self._authorize({"action": "initialize", "source": source})
        with self._store(write=True, initialize=True):
            pass
        return self.status()

    def status(self) -> dict:
        with self._store() as db:
            snapshot = self._snapshot(db)
            counts = {typ: sum(row["record_type"] == typ for row in snapshot["records"]) for typ in sorted(RECORD_TYPES)}
            return {"schema_version": VERSION, "record_owner": OWNER, "availability": "available" if db is not None else "not_created",
                    "scope_id": snapshot["scope_id"], "revision": snapshot["revision"], "epoch": snapshot["epoch"],
                    "state_token": self._token(snapshot), "counts": counts}

    def list(self) -> list[dict]:
        with self._store() as db:
            snapshot = self._snapshot(db)
            return [self._projection(row, snapshot) for row in snapshot["records"] if row["record_type"] == "deployment"]

    def inspect(self, object_id: str | dict) -> dict:
        with self._store() as db:
            snapshot = self._snapshot(db)
            reference = _ref(object_id) if type(object_id) is dict else _ref({"scope_id": snapshot["scope_id"], "object_id": object_id})
            row = next((row for row in snapshot["records"] if row["reference"] == reference), None)
            _check(row is not None, "deployment record unavailable")
            return self._projection(row, snapshot) if row["record_type"] == "deployment" else copy.deepcopy(row)

    def _projection(self, deployment, snapshot):
        ref = deployment["reference"]
        related = [row for row in snapshot["records"] if row.get("deployment") == ref]
        relationships = [row for row in related if row["record_type"] == "relationship"]
        resource_refs = { _key(row[field]) for row in related if row["record_type"] in {"relationship", "claim", "responsibility"}
                          for field in ("subject", "target") if field in row }
        resources = [copy.deepcopy(row) for row in snapshot["records"] if row["record_type"] == "resource" and _key(row["reference"]) in resource_refs]
        claims = [copy.deepcopy(row) for row in related if row["record_type"] == "claim"]
        conflicts = [{"claim": claim["reference"], "conflicts_with": [row["reference"] for row in others]}
                     for claim, others in _claim_conflicts(related)]
        grants = [copy.deepcopy(row) for row in related if row["record_type"] == "responsibility"]
        return {"schema_version": VERSION, "projection": "igor.deployment.inspection", "record_owner": OWNER,
                "availability": "available", "identity": copy.deepcopy(deployment), "registry_revision": snapshot["revision"],
                "state_token": self._token(snapshot), "resources": resources, "relationships": copy.deepcopy(relationships),
                "responsibilities": grants, "claims": claims, "conflicts": conflicts,
                "management": {"status": "responsibility_accepted" if any(g["lifecycle"] == "active" for g in grants) else "no_responsibility",
                               "execution_authority": "separate"},
                "configuration": {"source": "configuration_service", "availability": "not_supplied"},
                "observations": {"source": "system_model", "availability": "not_supplied"},
                "history": {"source": "operational_history", "availability": "not_supplied"},
                "verification": {"status": "not_verified", "availability": "not_supplied"},
                "detach": {"status": "not_certified", "reason": "consumer/job inventories not supplied",
                           "resources_retained": [row["reference"] for row in resources]}}

    def export_document(self) -> dict:
        with self._store() as db:
            snapshot = self._snapshot(db)
            return {"deployment_export_version": VERSION, "scope_id": snapshot["scope_id"], "revision": snapshot["revision"],
                    "epoch": snapshot["epoch"], "records": snapshot["records"], "identities": snapshot["identities"],
                    "operation_ids": snapshot["operation_ids"]}

    def prepare(self, changes: list[dict], *, source: dict) -> dict:
        """Allocate proposal-local IDs, never persist or initialize storage."""
        changes, source = _copy(changes), _copy(source)
        _screen_metadata(changes)
        _source(source)
        _check(0 < len(_array(changes)) <= 64, "empty metadata transition")
        with self._store() as db:
            _check(db is not None, "deployment registry is not initialized")
            snapshot = self._snapshot(db)
        aliases = {}
        prepared = []
        creates = {"create_deployment": "deployment", "enroll_resource": "resource", "add_relationship": "relationship",
                   "grant_responsibility": "responsibility", "record_claim": "claim"}
        for change in changes:
            _check(type(change) is dict and type(change.get("action")) is str, "invalid metadata change")
            change = copy.deepcopy(change)
            action = change["action"]
            if action in creates:
                _check(action == "enroll_resource" or "reference" not in change, "new Igor identity is service allocated")
                typ = creates[action]
                reference = change.get("reference") if action == "enroll_resource" else None
                if reference is not None:
                    reference = _ref(reference)
                    _check(self.reference_resolver is not None, "existing resource identity resolver unavailable")
                    identity_owner = self.reference_resolver(copy.deepcopy(reference))
                    _ident(identity_owner)
                    _check(identity_owner != OWNER, "existing identity must retain owning service")
                else:
                    reference = _ref({"scope_id": snapshot["scope_id"], "object_id": typ + ":" + uuid.uuid4().hex})
                    identity_owner = OWNER
                change["reference"] = reference
                if action == "enroll_resource":
                    change["identity_owner"] = identity_owner
                if "key" in change:
                    key = _ident(change.pop("key"))
                    _check(key not in aliases, "duplicate proposal key")
                    aliases[key] = reference
            elif "key" in change:
                raise DeploymentError("proposal key requires new record")
            if action == "resolve_claim" and change.get("decision") == "accept":
                change["relationship_reference"] = _ref({"scope_id": snapshot["scope_id"], "object_id": "relationship:" + uuid.uuid4().hex})
            prepared.append(change)
        for change in prepared:
            for key in ("deployment", "subject", "target", "reference"):
                if type(change.get(key)) is str and change[key].startswith("$"):
                    alias = change[key][1:]
                    _check(alias in aliases, "unknown proposal reference")
                    change[key] = copy.deepcopy(aliases[alias])
        proposal = {"schema_version": VERSION, "scope_id": snapshot["scope_id"], "expected_revision": snapshot["revision"],
                    "expected_state": self._token(snapshot), "epoch": snapshot["epoch"], "source": source, "changes": prepared}
        self._candidate(snapshot, proposal, "op-" + "0" * 32)
        return proposal

    def _validate_proposal(self, proposal):
        _closed(proposal, {"schema_version", "scope_id", "expected_revision", "expected_state", "epoch", "source", "changes"})
        _check(type(proposal["schema_version"]) is int and proposal["schema_version"] == VERSION, "unknown metadata proposal version")
        _ref({"scope_id": proposal["scope_id"], "object_id": "installation:local"})
        _check(type(proposal["expected_revision"]) is int and 0 <= proposal["expected_revision"] < 2**63 - 1, "invalid expected revision")
        _check(type(proposal["expected_state"]) is str and bool(re.fullmatch(r"[0-9a-f]{64}", proposal["expected_state"])), "invalid expected state token")
        _check(type(proposal["epoch"]) is str and bool(EPOCH.fullmatch(proposal["epoch"])), "invalid proposal epoch")
        _source(proposal["source"])
        _check(bool(_array(proposal["changes"])), "empty metadata transition")

    def _candidate(self, snapshot, proposal, operation_id):
        self._validate_proposal(proposal)
        rows = {_key(row["reference"]): copy.deepcopy(row) for row in snapshot["records"]}
        issued = {_key(row["reference"]): row["record_type"] for row in snapshot["identities"]}
        revision = snapshot["revision"] + 1
        stamp = datetime.now(timezone.utc).isoformat()
        last = {"operation_id": operation_id, "source": proposal["source"], "at": stamp}
        changed = []
        additions = []
        for change in proposal["changes"]:
            _check(type(change) is dict and type(change.get("action")) is str, "invalid metadata action")
            action = change["action"]
            required = {
                "create_deployment": {"label", "application", "providers"},
                "enroll_resource": {"kind", "label", "origin", "native", "identity_owner"},
                "add_relationship": {"deployment", "kind", "subject", "target", "role", "evidence"},
                "grant_responsibility": {"deployment", "subject", "duty", "setting_id", "providers"},
                "record_claim": {"deployment", "kind", "subject", "target", "role", "evidence"},
                "rename_deployment": {"label"}, "replace_providers": {"providers"}, "rebind_resource": {"native"},
                "retire_relationship": set(), "release_responsibility": {"disposition"},
                "resolve_claim": {"decision"},
            }
            _check(action in required, "unknown metadata action")
            optional = {"relationship_reference"} if action == "resolve_claim" else set()
            _closed(change, {"action", "reference"} | required[action], optional)
            reference = _ref(change["reference"])
            key = _key(reference)
            _check(key not in {_key(r) for r in changed}, "duplicate mutation of one record")
            creates = {"create_deployment": "deployment", "enroll_resource": "resource", "add_relationship": "relationship",
                       "grant_responsibility": "responsibility", "record_claim": "claim"}
            if action in creates:
                typ = creates[action]
                _check(key not in issued and key not in rows, "durable identity already issued; never reused")
                _check(typ == "resource" or reference["scope_id"] == snapshot["scope_id"], "new record scope mismatch")
                row = {"schema_version": VERSION, "record_type": typ, "reference": reference, "record_owner": OWNER,
                       "revision": revision, "created_at": stamp, "source": proposal["source"], "last_change": last,
                       "lifecycle": {"deployment": "known", "resource": "known", "relationship": "active", "responsibility": "active", "claim": "proposed"}[typ],
                       **{field: change[field] for field in required[action]}}
                if typ == "responsibility":
                    _check(proposal["source"]["kind"] == "operator", "responsibility requires explicit operator acceptance")
                    row.update(accepted_by=proposal["source"], disposition=None)
                elif typ == "relationship":
                    _check(proposal["source"]["kind"] == "operator", "binding requires explicit operator transition")
                    row["claim"] = None
                elif typ == "claim":
                    row["resolution"] = None
                if typ == "resource" and row["identity_owner"] != OWNER:
                    _check(self.reference_resolver is not None and self.reference_resolver(copy.deepcopy(reference)) == row["identity_owner"],
                           "existing resource identity unavailable or owner changed")
                additions.append({"reference": reference, "record_type": typ})
                issued[key] = typ
            else:
                _check(key in rows, "metadata target unavailable")
                row = rows[key]
                expected_type = {"rename_deployment": "deployment", "replace_providers": "deployment", "rebind_resource": "resource",
                                 "retire_relationship": "relationship", "release_responsibility": "responsibility", "resolve_claim": "claim"}[action]
                _check(row["record_type"] == expected_type, "metadata target type mismatch")
                if action in {"rename_deployment", "replace_providers", "rebind_resource"}:
                    _check(row["lifecycle"] == "known", "retained record cannot be updated")
                    _check(proposal["source"]["kind"] == "operator", "metadata rebinding requires explicit operator transition")
                    for field in required[action]:
                        row[field] = change[field]
                elif action == "retire_relationship":
                    _check(row["lifecycle"] == "active", "relationship already retired")
                    row["lifecycle"] = "retired"
                elif action == "release_responsibility":
                    _check(row["lifecycle"] == "active" and change["disposition"] is not None, "responsibility is not active")
                    row.update(lifecycle="released", disposition=change["disposition"])
                else:
                    _check(row["lifecycle"] == "proposed" and type(change["decision"]) is str and change["decision"] in {"accept", "reject"},
                           "claim requires explicit unresolved decision")
                    _check(proposal["source"]["kind"] == "operator", "claim resolution requires explicit operator transition")
                    row.update(lifecycle="accepted" if change["decision"] == "accept" else "rejected",
                               resolution={"decision": change["decision"], **last})
                    if change["decision"] == "accept":
                        _check("relationship_reference" in change and proposal["source"]["kind"] == "operator", "claim acceptance requires explicit operator transition")
                        rel_ref = _ref(change["relationship_reference"])
                        _check(_key(rel_ref) not in issued and rel_ref["scope_id"] == snapshot["scope_id"], "relationship identity already issued")
                        rel = {"schema_version": VERSION, "record_type": "relationship", "reference": rel_ref, "record_owner": OWNER,
                               "revision": revision, "created_at": stamp, "source": row["source"], "last_change": last, "lifecycle": "active",
                               **{field: row[field] for field in ("deployment", "kind", "subject", "target", "role", "evidence")}, "claim": reference}
                        rows[_key(rel_ref)] = validate_record(rel)
                        issued[_key(rel_ref)] = "relationship"
                        additions.append({"reference": rel_ref, "record_type": "relationship"})
                        changed.append(rel_ref)
                    else:
                        _check("relationship_reference" not in change, "rejected claim cannot create relationship")
                row.update(revision=revision, last_change=last)
            rows[key] = validate_record(row)
            changed.append(reference)
        records = sorted(rows.values(), key=lambda row: _key(row["reference"]))
        _check(len(issued) <= MAX_RECORDS, "identity ledger exceeds limit")
        _validate_graph(records, snapshot["scope_id"])
        for claim, others in _claim_conflicts(records):
            conflict_refs = {_key(item[field]) for item in [claim, *others] for field in ("deployment", "subject", "target")}
            slot = tuple(_key(claim[key]) if key in {"deployment", "subject"} else claim[key]
                         for key in ("deployment", "kind", "subject", "role"))
            for change in proposal["changes"]:
                action = change["action"]
                row = rows[_key(change["reference"])]
                if action in {"add_relationship", "resolve_claim"} and (action != "resolve_claim" or change["decision"] == "accept"):
                    changed_slot = tuple(_key(row[key]) if key in {"deployment", "subject"} else row[key]
                                         for key in ("deployment", "kind", "subject", "role"))
                    _check(slot != changed_slot, "unresolved relationship claims block affected binding")
                elif action == "rebind_resource":
                    _check(_key(row["reference"]) not in conflict_refs, "unresolved relationship claims block resource rebinding")
                elif action == "grant_responsibility":
                    deployment_wide = row["subject"] == row["deployment"] and row["deployment"] == claim["deployment"]
                    _check(_key(row["subject"]) not in conflict_refs and not deployment_wide,
                           "unresolved relationship claims block affected responsibility")
        return records, additions, changed

    @staticmethod
    def _receipt(db, operation_id, digest, epoch):
        existing = db.execute("SELECT epoch,digest,result,kind FROM operations WHERE id=?", (operation_id,)).fetchone()
        if existing is None:
            return None
        _check(existing[0] == epoch and existing[3] != "fence", "operation fenced by recovery epoch")
        _check(existing[1] == digest, "operation identity reused for different metadata request")
        return decode(existing[2])

    @staticmethod
    def _save(db, records, identities):
        for row in records:
            db.execute("INSERT INTO records VALUES (?,?) ON CONFLICT(id) DO UPDATE SET record=excluded.record", (_key(row["reference"]), _compact(row)))
        for row in identities:
            db.execute("INSERT INTO identities VALUES (?,?)", (_key(row["reference"]), row["record_type"]))

    def commit(self, proposal: dict, *, operation_id: str) -> dict:
        proposal = _copy(proposal)
        self._validate_proposal(proposal)
        _screen_metadata(proposal)
        _operation(operation_id)
        self._authorize({"action": "commit", "operation_id": operation_id, "proposal": proposal})
        digest = hashlib.sha256(_compact({"action": "commit", "proposal": proposal}).encode()).hexdigest()
        with self._store(write=True) as db:
            snapshot = self._snapshot(db)
            receipt = self._receipt(db, operation_id, digest, snapshot["epoch"])
            if receipt is not None:
                return receipt
            _check(proposal["scope_id"] == snapshot["scope_id"] and proposal["expected_revision"] == snapshot["revision"] and
                   proposal["expected_state"] == self._token(snapshot) and proposal["epoch"] == snapshot["epoch"], "metadata revision/state conflict")
            records, identities, changed = self._candidate(snapshot, proposal, operation_id)
            _check(len(snapshot["operation_ids"]) < MAX_RECORDS, "metadata operation ledger exceeds limit")
            self._save(db, records, identities)
            revision = snapshot["revision"] + 1
            db.execute("UPDATE metadata SET value=? WHERE key='revision'", (str(revision),))
            result = {"schema_version": VERSION, "operation_id": operation_id, "scope_id": snapshot["scope_id"], "revision": revision,
                      "epoch": snapshot["epoch"], "changed": changed, "metadata_only": True}
            db.execute("INSERT INTO operations VALUES (?,?,?,?,?)", (operation_id, snapshot["epoch"], digest, _compact(result), "commit"))
            return result

    def _export(self, document):
        document = _copy(document)
        _closed(document, {"deployment_export_version", "scope_id", "revision", "epoch", "records", "identities", "operation_ids"})
        _check(type(document["deployment_export_version"]) is int and document["deployment_export_version"] == VERSION, "unknown deployment export version")
        _ref({"scope_id": document["scope_id"], "object_id": "installation:local"})
        _check(type(document["revision"]) is int and 0 <= document["revision"] < 2**63 - 1 and
               type(document["epoch"]) is str and bool(EPOCH.fullmatch(document["epoch"])), "invalid export revision/epoch")
        _validate_graph(document["records"], document["scope_id"])
        issued = {}
        for row in _array(document["identities"], MAX_RECORDS):
            key, typ = _issued_identity(row, document["scope_id"])
            _check(key not in issued, "invalid exported identity ledger")
            issued[key] = typ
        for row in document["records"]:
            _check(issued.get(_key(row["reference"])) == row["record_type"] and row["revision"] <= document["revision"],
                   "export record missing identity or from future revision")
        operations = _array(document["operation_ids"], MAX_RECORDS)
        for ident in operations:
            _operation(ident)
        _check(len(operations) == len(set(operations)), "duplicate exported operation identity")
        _check(all(row["last_change"]["operation_id"] in operations and
                   (row["record_type"] != "claim" or row["resolution"] is None or row["resolution"]["operation_id"] in operations)
                   for row in document["records"]), "export provenance operation unavailable")
        return document

    def _write_recovery(self, snapshot):
        document = {"deployment_export_version": VERSION, **{key: snapshot[key] for key in
                    ("scope_id", "revision", "epoch", "records", "identities", "operation_ids")}}
        self._export(document)
        path = self.directory / "recovery.json"
        _safe_path(path)
        if path.exists():
            _private(path.stat())
        fd, temporary = tempfile.mkstemp(prefix=".recovery-", dir=self.directory)
        try:
            with os.fdopen(fd, "w") as output:
                output.write(_compact(document))
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, path)
            directory_fd = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def restore_document(self, document: dict, *, expected_revision: int, expected_state: str,
                         operation_id: str, source: dict) -> dict:
        """Restore metadata only; retain later identities/records and fence replay."""
        document = self._export(document)
        _screen_metadata(document)
        source = _copy(source)
        _source(source)
        _check(source["kind"] == "restore", "recovery requires restore provenance")
        _operation(operation_id)
        _check(type(expected_revision) is int and 0 <= expected_revision < 2**63 - 1 and type(expected_state) is str and
               bool(re.fullmatch(r"[0-9a-f]{64}", expected_state)), "invalid recovery precondition")
        request = {"action": "restore", "document": document, "expected_revision": expected_revision,
                   "expected_state": expected_state, "source": source}
        self._authorize({**request, "operation_id": operation_id})
        digest = hashlib.sha256(_compact(request).encode()).hexdigest()
        with self._store(write=True) as db:
            snapshot = self._snapshot(db)
            receipt = self._receipt(db, operation_id, digest, snapshot["epoch"])
            if receipt is not None:
                return receipt
            _check(document["scope_id"] == snapshot["scope_id"], "recovery scope mismatch")
            _check(expected_revision == snapshot["revision"] and expected_state == self._token(snapshot), "recovery revision/state conflict")
            _check(operation_id not in document["operation_ids"], "recovery operation already exists in export")
            existing = {_key(row["reference"]): row for row in snapshot["records"]}
            issued = {_key(row["reference"]): row["record_type"] for row in snapshot["identities"]}
            additions = []
            for row in document["identities"]:
                key = _key(row["reference"])
                if key in issued:
                    _check(issued[key] == row["record_type"], "recovery changes issued identity type")
                else:
                    additions.append(row)
                    issued[key] = row["record_type"]
            records = {_key(row["reference"]): row for row in document["records"]}
            revision = snapshot["revision"] + 1
            last = {"operation_id": operation_id, "source": source, "at": datetime.now(timezone.utc).isoformat()}
            for key, row in existing.items():
                if key in records:
                    restored = records[key]
                    immutable = {"record_type", "reference", "record_owner", "created_at", "source"}
                    immutable |= {"identity_owner", "kind", "origin"} if row["record_type"] == "resource" else set()
                    if row["record_type"] in {"relationship", "claim"}:
                        immutable |= {"deployment", "kind", "subject", "target", "role"}
                    elif row["record_type"] == "responsibility":
                        immutable |= {"deployment", "subject", "duty", "setting_id", "providers", "accepted_by"}
                    elif row["record_type"] == "deployment":
                        immutable.add("application")
                    _check(all(row[field] == restored[field] for field in immutable), "recovery changes identity/origin provenance")
                    continue
                # Older snapshots cannot silently erase later grants/topology.
                row = copy.deepcopy(row)
                typ = row["record_type"]
                if typ in {"deployment", "resource"}:
                    row["lifecycle"] = "retained"
                elif typ == "relationship":
                    row["lifecycle"] = "retired"
                elif typ == "responsibility":
                    row.update(lifecycle="released", disposition="unresolved")
                elif row["lifecycle"] == "proposed":
                    row.update(lifecycle="rejected", resolution={"decision": "reject", **last})
                records[key] = row
            for row in records.values():
                row.update(revision=revision, last_change=last)
            _validate_graph(list(records.values()), snapshot["scope_id"])
            _check(len(issued) <= MAX_RECORDS, "recovery identity ledger exceeds limit")
            all_operations = set(document["operation_ids"]) | set(snapshot["operation_ids"]) | {operation_id}
            _check(len(all_operations) <= MAX_RECORDS, "recovery operation ledger exceeds limit")
            self._write_recovery(snapshot)
            epoch = uuid.uuid4().hex
            self._save(db, list(records.values()), additions)
            db.executemany("UPDATE metadata SET value=? WHERE key=?", [(str(revision), "revision"), (epoch, "epoch")])
            for ident in set(document["operation_ids"]) - set(snapshot["operation_ids"]):
                db.execute("INSERT INTO operations VALUES (?,?,?,?,?)", (ident, epoch, "0" * 64, "null", "fence"))
            result = {"schema_version": VERSION, "operation_id": operation_id, "scope_id": snapshot["scope_id"], "revision": revision,
                      "epoch": epoch, "changed": [row["reference"] for row in records.values()], "metadata_only": True}
            db.execute("INSERT INTO operations VALUES (?,?,?,?,?)", (operation_id, epoch, digest, _compact(result), "restore"))
            return result


def _cli() -> int:
    parser = argparse.ArgumentParser(description="Read-only deployment metadata inspection")
    subparsers = parser.add_subparsers(dest="action", required=True)
    for action in ("status", "list", "export"):
        subparsers.add_parser(action)
    inspect_parser = subparsers.add_parser("inspect")
    inspect_parser.add_argument("object_id")
    args = parser.parse_args()
    root = Path(os.environ.get("IGOR_DIR", Path(__file__).resolve().parents[2]))
    service = DeploymentService(Path(os.environ.get("IGOR_DATA_DIR", root / "data")))
    try:
        result = {"status": service.status, "list": service.list, "export": service.export_document,
                  "inspect": lambda: service.inspect(args.object_id)}[args.action]()
        print(_compact(result))
        return 0
    except (DeploymentError, OSError) as exc:
        print(_compact({"schema_version": VERSION, "availability": "unavailable", "error": str(exc)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(_cli())
