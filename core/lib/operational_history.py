"""Igor-owned Operational History v1; private SQLite storage, never execution policy.

Callers exchange episodes and canonical results. SQL/layout and process liveness
are implementation details. No service method invokes a capability or verifier.
"""
from __future__ import annotations

import argparse
import contextlib
import copy
import fcntl
import hashlib
import json
import os
import re
import sqlite3
import stat
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ai"))
from privacy import redactions, scrub_text  # noqa: E402

VERSION = 1
# Backend layout may evolve independently of public episode/export contracts.
_STORE_VERSION = 1
IDENT = re.compile(r"[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*")
OPERATION = re.compile(r"op-[0-9a-f]{32}")
SCOPE = re.compile(r"scope:[0-9a-f]{32}")
OBJECT = re.compile(r"[a-z][a-z0-9_]*:[^\s\x00-\x1f]{1,150}")
SECRET = re.compile(r"password|passwd|credential|api[_-]?key|(?:^|_)token(?:$|_)|secret(?!_ref)", re.I)
STATES = {"admitted", "running", "provider_complete", "terminal", "interrupted"}
APPROVAL = {"pending", "not_requested", "not_required", "approved", "auto_approved", "denied", "stopped"}
PRIVILEGE = {"not_requested", "not_required", "required", "authenticated", "failed"}
EXECUTION = {"not_executed", "running", "failed", "succeeded", "unknown"}
VERIFICATION = {"not_applicable", "pending", "passed", "failed", "unknown", "unavailable"}
EPISODE_FIELDS = {"schema_version", "operation_id", "correlation_id", "provenance", "references", "scope_id",
                  "capability", "provider", "inputs", "inputs_redacted", "affected_objects", "safety_tier",
                  "approval", "privilege", "precondition_status", "execution_status", "verification",
                  "outcome", "recovery", "lifecycle", "timestamps", "transitions"}


class HistoryError(ValueError):
    """Malformed, unsupported or unavailable history; existing content is retained."""


def _closed(value: Any, fields: set[str], name: str, required: set[str] | None = None) -> dict[str, Any]:
    if type(value) is not dict or set(value) - fields or not (fields if required is None else required) <= set(value):
        raise HistoryError(f"invalid {name} fields")
    return value


def _text(value: Any, name: str, limit: int = 160) -> str:
    if type(value) is not str or not value or len(value) > limit or re.search(r"[\x00-\x1f\x7f]", value):
        raise HistoryError(f"invalid {name}")
    if _scrub_text(value) != value:
        raise HistoryError(f"secret-bearing {name}")
    return value


def _timestamp(value: Any) -> str:
    try:
        parsed = datetime.fromisoformat(_text(value, "timestamp", 64).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError("timezone missing")
    except ValueError as exc:
        raise HistoryError("invalid timestamp") from exc
    return value


def _decode(text: str) -> Any:
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result = {}
        for key, value in pairs:
            if key in result:
                raise HistoryError("duplicate history JSON field")
            result[key] = value
        return result
    def invalid_constant(_value: str) -> Any:
        raise HistoryError("invalid history JSON number")
    return json.loads(text, object_pairs_hook=unique, parse_constant=invalid_constant)


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def object_ref(scope_id: str, object_id: str) -> dict[str, str]:
    if type(scope_id) is not str or not SCOPE.fullmatch(scope_id):
        raise HistoryError("invalid scope identity")
    if type(object_id) is not str or not OBJECT.fullmatch(object_id):
        raise HistoryError("invalid object identity")
    _text(object_id, "object identity")
    return {"scope_id": scope_id, "object_id": object_id}


def _redactions() -> list[tuple[str, str]]:
    pairs = dict(redactions())
    for key, value in os.environ.items():
        if re.search(r"(?:PASSWORD|PASSWD|SECRET|TOKEN|API_KEY)$", key) and value:
            pairs[value] = "[REDACTED]"
    root = Path(os.environ.get("IGOR_DIR", ".")) / "secrets"
    for path in root.glob("*"):
        if path.suffix not in {".env", ".key"} or path.is_symlink() or not path.is_file():
            continue
        for line in path.read_text(errors="replace").splitlines():
            if path.suffix == ".key":
                value = line.strip()
            else:
                match = re.match(r"(?:export\s+)?([A-Za-z_]\w*)\s*=\s*(.*)", line.strip())
                if not match or not SECRET.search(match.group(1)):
                    continue
                value = match.group(2).strip().strip("\"'")
            if value and not value.startswith("[IGOR:"):
                pairs[value] = "[REDACTED]"
    return sorted(pairs.items(), key=lambda item: -len(item[0]))


def _scrub_text(value: str, pairs: Any = None) -> str:
    pairs = _redactions() if pairs is None else pairs
    result = scrub_text(value, [(literal, token) for literal, token in pairs if len(literal) >= 4])
    # Short known values are redacted as tokens; a one-character password does
    # not make unrelated characters in canonical identifiers secret material.
    for literal, token in pairs:
        if len(literal) < 4:
            result = re.sub(r"(?<![A-Za-z0-9])" + re.escape(literal) + r"(?![A-Za-z0-9])", lambda _: token, result)
    return result


def _safe(value: Any, *, pairs: Any = None, depth: int = 0) -> Any:
    """Bound all retained reference data and omit secret-bearing keys/values.

    Secret refs are value-free opaque structures. Environment and terminal
    transcripts have no recording path, even if their current text looks safe.
    """
    if depth > 8:
        return "[omitted: depth]"
    pairs = _redactions() if pairs is None else pairs
    if isinstance(value, dict):
        return {_scrub_text(str(key), pairs)[:128]: ("[REDACTED]" if SECRET.search(str(key)) or str(key).lower() in
                               {"environment", "env", "transcript", "authentication_transcript"}
                               else _safe(item, pairs=pairs, depth=depth + 1))
                for key, item in list(value.items())[:64]}
    if isinstance(value, list):
        return [_safe(item, pairs=pairs, depth=depth + 1) for item in value[:32]]
    if isinstance(value, str):
        return _scrub_text(value, pairs)[:1024]
    if value is None or type(value) in {bool, int}:
        return value
    if type(value) is float and value == value and abs(value) != float("inf"):
        return value
    return "[omitted: unsupported value]"


def _validate_safe(value: Any) -> None:
    if len(json.dumps(value, allow_nan=False)) > 48000 or _safe(value, pairs=[]) != value:
        raise HistoryError("unbounded or secret-bearing reference data")


def project_inputs(capability_id: str, inputs: dict) -> dict:
    """Retain structured metadata evidence plus an exact input digest.

    Opaque serialized proposals exceed the ordinary transcript string bound.
    Decode this closed Core metadata input before normal privacy/bounds checks;
    History records evidence, never authorizes the proposal or owns its bindings.
    """
    if capability_id in {"core.deployments.initialize", "core.deployments.adopt", "core.deployments.release"}:
        document = inputs.get("proposal")
        if type(document) is not str or len(document.encode()) > 262144 or set(inputs) != {"proposal"}:
            raise HistoryError("invalid deployment metadata inputs")
        proposal = _decode(document)
        if type(proposal) is not dict:
            raise HistoryError("invalid deployment metadata proposal")
        return {"proposal": proposal, "proposal_sha256": hashlib.sha256(document.encode()).hexdigest()}
    return inputs


def _public_episode(row: dict[str, Any]) -> dict[str, Any]:
    # Scrub retained content again against currently configured secrets, while
    # preserving Igor-generated identity and the closed protocol vocabulary.
    # A secret-looking substring in a random UUID is not credential evidence.
    row = copy.deepcopy(row)
    pairs = _redactions()
    inputs = _safe(row["inputs"], pairs=pairs)
    row["inputs_redacted"] = row["inputs_redacted"] or inputs != row["inputs"]
    row["inputs"] = inputs
    _recovery_class = row["recovery"]["class"]
    row["recovery"] = _safe(row["recovery"], pairs=pairs)
    # Recovery class is a closed semantic value, rather than retained content.
    row["recovery"]["class"] = _recovery_class
    row["verification"]["contract"] = _safe(row["verification"]["contract"], pairs=pairs)
    for evidence in row["verification"]["evidence"]:
        evidence["data"] = _safe(evidence["data"], pairs=pairs)
    return row


def validate_episode(value: Any) -> dict[str, Any]:
    row = _closed(value, EPISODE_FIELDS, "episode")
    if type(row["schema_version"]) is not int or row["schema_version"] != VERSION:
        raise HistoryError("unsupported episode version")
    if type(row["operation_id"]) is not str or not OPERATION.fullmatch(row["operation_id"]):
        raise HistoryError("invalid operation identity")
    _text(row["correlation_id"], "correlation identity", 160)
    object_ref(row["scope_id"], "host:local")
    provenance = _closed(row["provenance"], {"actor", "interface", "request_id"}, "provenance")
    for key in ("actor", "interface"):
        _text(provenance[key], key, 64)
    if provenance["request_id"] is not None:
        _text(provenance["request_id"], "request identity")
    refs = _closed(row["references"], {"automation_id", "automation_claim_id", "automation_slot", "causation_id", "plan_digest", "plan_step"}, "references", set())
    for key, item in refs.items():
        _text(item, key)
    capability = _closed(row["capability"], {"id", "version"}, "capability")
    if (type(capability["id"]) is not str or not IDENT.fullmatch(capability["id"]) or "." not in capability["id"] or
            type(capability["version"]) is not int or capability["version"] < 1):
        raise HistoryError("invalid canonical capability identity")
    _text(capability["id"], "capability identity")
    provider = _closed(row["provider"], {"id", "owner", "source"}, "provider")
    for key in ("id", "owner"):
        if type(provider[key]) is not str or not IDENT.fullmatch(provider[key]):
            raise HistoryError("invalid provider identity")
        _text(provider[key], "provider identity")
    source = _closed(provider["source"], {"kind", "contract_id", "module_version"}, "provider source", {"kind", "contract_id"})
    if "module_version" in source:
        _text(source["module_version"], "provider module version", 64)
    if source["kind"] not in {"module_contract", "core_contract"} or source["contract_id"] != capability["id"]:
        raise HistoryError("invalid provider source contract")
    if type(row["inputs"]) is not dict or type(row["inputs_redacted"]) is not bool:
        raise HistoryError("invalid frozen inputs")
    _validate_safe(row["inputs"])
    if type(row["affected_objects"]) is not list or len(row["affected_objects"]) > 32:
        raise HistoryError("invalid affected objects")
    for ref in row["affected_objects"]:
        _closed(ref, {"scope_id", "object_id"}, "object reference")
        object_ref(ref["scope_id"], ref["object_id"])
        if ref["scope_id"] != row["scope_id"]:
            raise HistoryError("affected object outside execution scope")
    if row["safety_tier"] not in {"READ", "CHANGE", "DESTROY"}:
        raise HistoryError("invalid safety tier")
    approval = _closed(row["approval"], {"requirement", "result"}, "approval")
    if approval["requirement"] not in {"policy_read", "guide_confirm", "change_confirm", "executive_policy", "exact_yes"} or approval["result"] not in APPROVAL:
        raise HistoryError("invalid approval")
    privilege = _closed(row["privilege"], {"requirement", "result"}, "privilege")
    if privilege["requirement"] not in {"none", "required"} or privilege["result"] not in PRIVILEGE:
        raise HistoryError("invalid privilege")
    if row["precondition_status"] not in {"satisfied", "failed"} or row["execution_status"] not in EXECUTION:
        raise HistoryError("invalid execution or precondition result")
    verification = _closed(row["verification"], {"contract", "status", "evidence", "reconciliation"}, "verification")
    if type(verification["contract"]) is not dict or verification["status"] not in VERIFICATION:
        raise HistoryError("invalid verification contract/status")
    _validate_safe(verification["contract"])
    if type(verification["evidence"]) is not list or len(verification["evidence"]) > 32:
        raise HistoryError("invalid evidence")
    for evidence in verification["evidence"]:
        _closed(evidence, {"source", "recorded_at", "availability", "redaction", "objects", "data"}, "evidence")
        _text(evidence["source"], "evidence source")
        _timestamp(evidence["recorded_at"])
        if evidence["availability"] != "retained" or evidence["redaction"] != "applied":
            raise HistoryError("invalid evidence availability/redaction")
        if type(evidence["objects"]) is not list or len(evidence["objects"]) > 32:
            raise HistoryError("invalid evidence objects")
        for ref in evidence["objects"]:
            _closed(ref, {"scope_id", "object_id"}, "evidence reference")
            object_ref(ref["scope_id"], ref["object_id"])
        _validate_safe(evidence["data"])
    reconciliation = verification["reconciliation"]
    if reconciliation is not None:
        _closed(reconciliation, {"status", "recorded_at"}, "reconciliation")
        if reconciliation["status"] not in {"passed", "failed", "unknown", "unavailable"}:
            raise HistoryError("invalid reconciliation result")
        _timestamp(reconciliation["recorded_at"])
    if row["outcome"] is not None:
        _text(row["outcome"], "outcome", 64)
    _validate_safe(row["recovery"])
    if type(row["recovery"]) is not dict or row["recovery"].get("class") not in {"not_applicable", "reversible", "best_effort", "compensating_action", "snapshot_required", "irreversible"}:
        raise HistoryError("invalid recovery semantics")
    if row["lifecycle"] not in STATES:
        raise HistoryError("invalid lifecycle")
    times = _closed(row["timestamps"], {"admitted_at", "updated_at", "terminal_at"}, "timestamps")
    _timestamp(times["admitted_at"])
    _timestamp(times["updated_at"])
    if times["terminal_at"] is not None:
        _timestamp(times["terminal_at"])
    if type(row["transitions"]) is not list or not 1 <= len(row["transitions"]) <= 32:
        raise HistoryError("invalid transitions")
    for transition in row["transitions"]:
        _closed(transition, {"state", "at"}, "transition")
        if transition["state"] not in STATES | {"authority", "reconciled"}:
            raise HistoryError("invalid transition")
        _timestamp(transition["at"])
    lifecycle = row["lifecycle"]
    execution = row["execution_status"]
    if lifecycle in {"admitted", "running", "provider_complete"} and (row["outcome"] is not None or times["terminal_at"] is not None):
        raise HistoryError("nonterminal episode carries terminal result")
    if lifecycle == "admitted" and execution != "not_executed":
        raise HistoryError("admitted episode already executed")
    if lifecycle == "running" and execution != "running":
        raise HistoryError("running episode has invalid execution")
    if lifecycle == "provider_complete" and execution not in {"succeeded", "failed"}:
        raise HistoryError("provider completion lacks execution result")
    if lifecycle == "terminal" and (row["outcome"] is None or times["terminal_at"] is None or execution not in {"not_executed", "failed", "succeeded"} or verification["status"] == "pending"):
        raise HistoryError("terminal episode lacks canonical result")
    if lifecycle == "interrupted" and (execution not in {"unknown", "succeeded", "failed"} or times["terminal_at"] is None or verification["status"] != "unknown"):
        raise HistoryError("interrupted episode has invalid uncertainty")
    if approval["result"] in {"pending", "not_requested", "denied", "stopped"} and execution not in {"not_executed"}:
        raise HistoryError("unapproved episode cannot execute")
    if approval["result"] in {"pending", "not_requested", "denied", "stopped"} and privilege["result"] == "authenticated":
        raise HistoryError("unapproved episode cannot authenticate")
    if privilege["result"] == "failed" and execution != "not_executed":
        raise HistoryError("failed privilege cannot execute")
    if privilege["requirement"] == "required" and execution in {"running", "succeeded", "failed", "unknown"} and privilege["result"] != "authenticated":
        raise HistoryError("privileged execution lacks authentication")
    if row["lifecycle"] == "interrupted" and row["outcome"] != "interrupted_unknown":
        raise HistoryError("interrupted episode lacks uncertainty")
    if row["outcome"] == "success" and (row["execution_status"] != "succeeded" or verification["status"] in {"failed", "unknown", "unavailable", "pending"} or
                                        (row["safety_tier"] != "READ" and verification["status"] != "passed")):
        raise HistoryError("unverified execution cannot become success")
    return row


def _owner(pid: int) -> dict[str, Any]:
    try:
        start = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]
        boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    except OSError as exc:
        raise HistoryError("cannot establish runtime owner liveness") from exc
    return {"pid": pid, "start": start, "boot": boot}


def _alive(owner: dict[str, Any]) -> bool:
    try:
        return _owner(owner["pid"]) == owner and Path(f'/proc/{owner["pid"]}/stat').read_text().rsplit(")", 1)[1].split()[0] != "Z"
    except (HistoryError, KeyError, IndexError):
        return False


def _transition(row: dict[str, Any], state: str) -> None:
    stamp = now()
    row["timestamps"]["updated_at"] = stamp
    row["transitions"].append({"state": state, "at": stamp})
    if state in STATES:
        row["lifecycle"] = state
    if state in {"terminal", "interrupted"}:
        row["timestamps"]["terminal_at"] = stamp


def _interrupted(row: dict[str, Any]) -> dict[str, Any]:
    row = copy.deepcopy(row)
    if row["lifecycle"] == "admitted":
        row.update(execution_status="not_executed", outcome="interrupted_before_execution")
        row["verification"]["status"] = "not_applicable"
        _transition(row, "terminal")
    else:
        # Known provider completion survives. Running means possible effect,
        # never success/failure invented from missing provider output.
        if row["lifecycle"] == "running":
            row["execution_status"] = "unknown"
        row["outcome"] = "interrupted_unknown"
        row["verification"]["status"] = "unknown"
        _transition(row, "interrupted")
    return row


def _safe_path(path: Path) -> None:
    for part in (path, *path.parents):
        if part.is_symlink():
            raise HistoryError("history path contains a symlink")


class OperationalHistory:
    """Versioned service boundary. Callers never read the private backend."""

    def __init__(self, data_dir: Path):
        self._directory = data_dir.absolute() / "operational_history"
        self._path = self._directory / "store.sqlite3"

    @contextlib.contextmanager
    def _store(self, *, write: bool = False):
        _safe_path(self._directory)
        if not self._directory.exists():
            if not write:
                yield None
                return
            self._directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        directory_fd = os.open(self._directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            info = os.fstat(directory_fd)
            if info.st_uid != os.geteuid():
                raise HistoryError("history directory has another owner")
            if write:
                os.fchmod(directory_fd, 0o700)
            elif stat.S_IMODE(info.st_mode) != 0o700:
                raise HistoryError("history directory permissions are not private")
            fcntl.flock(directory_fd, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
            _safe_path(self._path)
            for candidate in (self._path, Path(str(self._path) + "-journal"), Path(str(self._path) + "-wal"), Path(str(self._path) + "-shm")):
                if candidate.is_symlink():
                    raise HistoryError("history backend path is a symlink")
                if candidate.exists():
                    info = candidate.stat()
                    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600:
                        raise HistoryError("history backend is not a private regular file")
            created = False
            if not self._path.exists():
                if not write:
                    yield None
                    return
                fd = os.open(self._path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
                os.close(fd)
                created = True
            connection = sqlite3.connect(self._path.as_uri() + ("?mode=rw" if write else "?mode=ro"), uri=True, timeout=10)
            try:
                if created:
                    connection.executescript("""
                        PRAGMA user_version=1;
                        CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                        CREATE TABLE episodes (id TEXT PRIMARY KEY, correlation TEXT NOT NULL,
                            admitted TEXT NOT NULL, record TEXT NOT NULL, owner TEXT);
                        CREATE INDEX episode_correlation ON episodes(correlation);
                    """)
                    connection.execute("INSERT INTO metadata VALUES ('scope_id', ?)", ("scope:" + uuid.uuid4().hex,))
                    connection.commit()
                    fd = os.open(self._directory, os.O_RDONLY)
                    try:
                        os.fsync(fd)
                    finally:
                        os.close(fd)
                if connection.execute("PRAGMA user_version").fetchone()[0] != _STORE_VERSION:
                    raise HistoryError("unsupported history store version; original retained")
                objects = {(kind, name) for kind, name in connection.execute("SELECT type,name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'")}
                if objects != {("table", "metadata"), ("table", "episodes"), ("index", "episode_correlation")}:
                    raise HistoryError("invalid history schema; original retained")
                if connection.execute("PRAGMA quick_check").fetchone()[0] != "ok":
                    raise HistoryError("corrupt history store; original retained")
                scope_rows = connection.execute("SELECT key,value FROM metadata").fetchall()
                if len(scope_rows) != 1 or scope_rows[0][0] != "scope_id":
                    raise HistoryError("invalid local scope metadata")
                object_ref(scope_rows[0][1], "host:local")
                connection.execute("PRAGMA synchronous=FULL")
                if write:
                    connection.execute("PRAGMA secure_delete=ON")
                if write:
                    connection.execute("BEGIN IMMEDIATE")
                else:
                    connection.execute("PRAGMA query_only=ON")
                yield connection
                if write:
                    connection.commit()
            except BaseException:
                connection.rollback()
                raise
            finally:
                connection.close()
        except sqlite3.Error as exc:
            raise HistoryError("history backend unavailable/corrupt; original retained") from exc
        finally:
            os.close(directory_fd)

    @staticmethod
    def _scope(db: sqlite3.Connection) -> str:
        return db.execute("SELECT value FROM metadata WHERE key='scope_id'").fetchone()[0]

    @staticmethod
    def _read(db: sqlite3.Connection, ident: str) -> tuple[dict[str, Any], Any]:
        if type(ident) is not str or not OPERATION.fullmatch(ident):
            raise HistoryError("invalid operation identity")
        record = db.execute("SELECT record,owner FROM episodes WHERE id=?", (ident,)).fetchone()
        if record is None:
            raise HistoryError("episode unavailable")
        try:
            row = validate_episode(_decode(record[0]))
            owner = _decode(record[1]) if record[1] else None
            if row["lifecycle"] in {"admitted", "running", "provider_complete"}:
                _closed(owner, {"pid", "start", "boot"}, "runtime owner")
                if (type(owner["pid"]) is not int or owner["pid"] <= 0 or type(owner["start"]) is not str or
                        not owner["start"].isdigit() or type(owner["boot"]) is not str or
                        not re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", owner["boot"])):
                    raise HistoryError("invalid runtime owner marker")
            elif owner is not None:
                raise HistoryError("terminal episode retains runtime ownership")
        except (json.JSONDecodeError, TypeError) as exc:
            raise HistoryError("corrupt history episode") from exc
        indexed = db.execute("SELECT correlation,admitted FROM episodes WHERE id=?", (ident,)).fetchone()
        if row["operation_id"] != ident or indexed != (row["correlation_id"], row["timestamps"]["admitted_at"]):
            raise HistoryError("history index differs from episode identity")
        if row["scope_id"] != OperationalHistory._scope(db):
            raise HistoryError("episode scope differs from local installation")
        return row, owner

    @staticmethod
    def _save(db: sqlite3.Connection, row: dict[str, Any], owner: Any) -> None:
        validate_episode(row)
        db.execute("UPDATE episodes SET record=?,owner=? WHERE id=?", (json.dumps(row, sort_keys=True, separators=(",", ":")), json.dumps(owner) if owner else None, row["operation_id"]))

    def prepare(self, proposal: dict[str, Any], *, correlation_id: str, provenance: dict[str, Any],
                references: dict[str, str] | None = None, owner_pid: int | None = None,
                approval_requirement: str = "policy_read") -> dict[str, Any]:
        with self._store(write=True) as db:
            scope = self._scope(db)
            stamp = now()
            projected_inputs = project_inputs(proposal["capability_id"], proposal["inputs"])
            safe_inputs = _safe(projected_inputs)
            row = {"schema_version": VERSION, "operation_id": "op-" + uuid.uuid4().hex,
                   "correlation_id": correlation_id, "provenance": _safe(provenance),
                   "references": _safe(references or {}), "scope_id": scope,
                   "capability": {"id": proposal["capability_id"], "version": proposal["capability_version"]},
                   "provider": {"id": proposal["provider"], "owner": proposal["owner"],
                                "source": {"kind": "core_contract" if proposal["owner"] == "core" else "module_contract", "contract_id": proposal["capability_id"]}},
                   "inputs": safe_inputs, "inputs_redacted": safe_inputs != projected_inputs,
                   "affected_objects": [object_ref(scope, ident) for ident in proposal["affected_objects"]],
                   "safety_tier": proposal["safety"]["tier"],
                   "approval": {"requirement": approval_requirement, "result": "pending"},
                   "privilege": {"requirement": proposal["privilege"], "result": "not_requested" if proposal["privilege"] == "required" else "not_required"},
                   "precondition_status": proposal["precondition_status"], "execution_status": "not_executed",
                   "verification": {"contract": _safe(proposal["verification"]), "status": "pending", "evidence": [], "reconciliation": None},
                   "outcome": None, "recovery": _safe(proposal["recovery"]), "lifecycle": "admitted",
                   "timestamps": {"admitted_at": stamp, "updated_at": stamp, "terminal_at": None},
                   "transitions": [{"state": "admitted", "at": stamp}]}
            if proposal.get("provider_source_module_version"):
                row["provider"]["source"]["module_version"] = proposal["provider_source_module_version"]
            validate_episode(row)
            owner = _owner(owner_pid or os.getpid())
            db.execute("INSERT INTO episodes VALUES (?,?,?,?,?)", (row["operation_id"], correlation_id, stamp, json.dumps(row, sort_keys=True, separators=(",", ":")), json.dumps(owner)))
            return row

    def authority(self, ident: str, approval: str, privilege: str) -> None:
        with self._store(write=True) as db:
            row, owner = self._read(db, ident)
            if row["lifecycle"] != "admitted":
                raise HistoryError("authority recording requires admitted episode")
            row["approval"]["result"] = approval
            row["privilege"]["result"] = privilege
            _transition(row, "authority")
            self._save(db, row, owner)

    @staticmethod
    def _assert_binding(row: dict[str, Any], proposal: dict[str, Any]) -> None:
        if (row["capability"] != {"id": proposal["capability_id"], "version": proposal["capability_version"]} or
                row["provider"]["id"] != proposal["provider"] or row["provider"]["owner"] != proposal["owner"] or
                row["inputs"] != _safe(project_inputs(proposal["capability_id"], proposal["inputs"])) or row["safety_tier"] != proposal["safety"]["tier"] or
                row["privilege"]["requirement"] != proposal["privilege"] or
                row["affected_objects"] != [object_ref(row["scope_id"], value) for value in proposal["affected_objects"]] or
                row["verification"]["contract"] != _safe(proposal["verification"]) or row["recovery"] != _safe(proposal["recovery"]) or
                row["provider"]["source"].get("module_version") != proposal.get("provider_source_module_version")):
            raise HistoryError("durable attempt differs from current approved operation")

    def running(self, ident: str, proposal: dict[str, Any] | None = None) -> None:
        with self._store(write=True) as db:
            row, owner = self._read(db, ident)
            if row["lifecycle"] != "admitted" or row["approval"]["result"] not in {"approved", "auto_approved", "not_required"} or (row["privilege"]["requirement"] == "required" and row["privilege"]["result"] != "authenticated"):
                raise HistoryError("cannot record running attempt")
            if proposal is not None:
                self._assert_binding(row, proposal)
            row["execution_status"] = "running"
            _transition(row, "running")
            self._save(db, row, owner)

    def provider_complete(self, ident: str, execution: str) -> None:
        with self._store(write=True) as db:
            row, owner = self._read(db, ident)
            if row["lifecycle"] != "running" or execution not in {"succeeded", "failed"}:
                raise HistoryError("invalid provider completion")
            row["execution_status"] = execution
            _transition(row, "provider_complete")
            self._save(db, row, owner)

    @staticmethod
    def _evidence(row: dict[str, Any], data: Any) -> list[dict[str, Any]]:
        if not data:
            return []
        if not isinstance(data, list):
            data = [data]
        return [{"source": _safe(item.get("source", "canonical_verifier") if isinstance(item, dict) else "canonical_verifier"),
                 "recorded_at": now(), "availability": "retained", "redaction": "applied",
                 "objects": copy.deepcopy(row["affected_objects"]), "data": _safe(item)} for item in data[:32]]

    def finish(self, ident: str, result: dict[str, Any]) -> None:
        with self._store(write=True) as db:
            row, owner = self._read(db, ident)
            if row["lifecycle"] not in {"admitted", "running", "provider_complete"}:
                raise HistoryError("episode cannot accept terminal result")
            if (result.get("operation_id") != ident or result.get("capability_id") != row["capability"]["id"] or
                    result.get("capability_version") != row["capability"]["version"] or result.get("provider") != row["provider"]["id"] or
                    result.get("owner") != row["provider"]["owner"] or result.get("safety", {}).get("tier") != row["safety_tier"] or
                    result.get("privilege") != row["privilege"]["requirement"] or
                    result.get("affected_objects") != [ref["object_id"] for ref in row["affected_objects"]]):
                raise HistoryError("canonical result identity differs from attempt")
            execution = result["execution_status"]
            if row["lifecycle"] == "running":
                if execution not in {"succeeded", "failed"}:
                    raise HistoryError("running episode lacks canonical provider result")
                row["execution_status"] = execution
                _transition(row, "provider_complete")
            if (row["lifecycle"] == "admitted" and execution != "not_executed") or (row["lifecycle"] == "provider_complete" and execution != row["execution_status"]):
                raise HistoryError("canonical result execution differs from attempt")
            row.update(execution_status=execution, precondition_status=result["precondition_status"], outcome=result["outcome"])
            row["approval"]["result"] = result["approval_status"]
            row["privilege"]["result"] = result["privilege_status"]
            row["verification"]["status"] = result["verification_status"]
            row["verification"]["evidence"] = self._evidence(row, result.get("verification_evidence", []))
            _transition(row, "terminal")
            self._save(db, row, None)

    def inspect(self, ident: str) -> dict[str, Any]:
        with self._store() as db:
            if db is None:
                raise HistoryError("episode unavailable")
            row, owner = self._read(db, ident)
            # Projection only: queries never claim/recover/write or verify.
            if owner and not _alive(owner) and row["lifecycle"] in {"admitted", "running", "provider_complete"}:
                row = _interrupted(row)
            return _public_episode(row)

    def recent(self, *, limit: int = 20, correlation_id: str | None = None) -> list[dict[str, Any]]:
        if type(limit) is not int or not 1 <= limit <= 100:
            raise HistoryError("history limit must be 1..100")
        with self._store() as db:
            if db is None:
                return []
            if correlation_id is not None:
                _text(correlation_id, "correlation identity")
                ids = db.execute("SELECT id FROM episodes WHERE correlation=? ORDER BY admitted DESC LIMIT ?", (correlation_id, limit)).fetchall()
            else:
                ids = db.execute("SELECT id FROM episodes ORDER BY admitted DESC LIMIT ?", (limit,)).fetchall()
            output = []
            for (ident,) in ids:
                row, owner = self._read(db, ident)
                if owner and not _alive(owner) and row["lifecycle"] in {"admitted", "running", "provider_complete"}:
                    row = _interrupted(row)
                output.append(_public_episode(row))
            return output

    def ensure_scope(self) -> str:
        """Allocate/reuse local identity without an episode or recovery action.

        Durable reference consumers use this explicit write boundary; inspection
        uses status() and never allocates identity.
        """
        with self._store(write=True) as db:
            return self._scope(db)

    def status(self) -> dict[str, Any]:
        with self._store() as db:
            if db is None:
                return {"schema_version": VERSION, "availability": "not_created", "scope_id": None, "episodes": 0}
            return {"schema_version": VERSION, "availability": "available", "scope_id": self._scope(db), "episodes": db.execute("SELECT count(*) FROM episodes").fetchone()[0]}

    def recover(self) -> list[dict[str, Any]]:
        with self._store(write=True) as db:
            recovered = []
            # Runtime ownership exists only for unfinished attempts. Previously
            # recovery decoded every terminal episode on every new admission.
            # Interrupted/unreconciled rows have no owner, so include only that
            # narrow JSON shape for reconciliation without re-reading terminal
            # history in Python.
            candidates = db.execute(
                """SELECT id FROM episodes
                   WHERE owner IS NOT NULL
                      OR (owner IS NULL
                          AND instr(record, '"lifecycle":"interrupted"') > 0
                          AND instr(record, '"reconciliation":null') > 0)"""
            ).fetchall()
            for (ident,) in candidates:
                row, owner = self._read(db, ident)
                if owner and not _alive(owner) and row["lifecycle"] in {"admitted", "running", "provider_complete"}:
                    row = _interrupted(row)
                    self._save(db, row, None)
                if row["lifecycle"] == "interrupted" and row["verification"]["reconciliation"] is None:
                    recovered.append(_public_episode(row))
            return recovered

    def reconcile(self, ident: str, status: str, evidence: Any) -> None:
        with self._store(write=True) as db:
            row, _ = self._read(db, ident)
            if row["lifecycle"] != "interrupted" or status not in {"passed", "failed", "unknown", "unavailable"}:
                raise HistoryError("only interrupted attempts can be reconciled")
            row["verification"]["reconciliation"] = {"status": status, "recorded_at": now()}
            row["verification"]["evidence"] = self._evidence(row, evidence)
            # Canonical execution/outcome remain unknown; a current query proves
            # a current postcondition, not which process caused it.
            _transition(row, "reconciled")
            self._save(db, row, None)

    def export(self) -> dict[str, Any]:
        with self._store() as db:
            if db is None:
                raise HistoryError("history unavailable for export")
            rows = [self._read(db, ident)[0] for (ident,) in db.execute("SELECT id FROM episodes ORDER BY admitted,id")]
            return {"export_version": VERSION, "scope_id": self._scope(db), "episodes": [_public_episode(row) for row in rows]}

    def restore(self, export: Any) -> dict[str, Any]:
        """Restore an explicit same-installation continuation; never overwrite.

        First version has no migration. Future version transitions require a
        named migration implementation; unsupported input remains untouched.
        Re-entry with an identical validated export is idempotent.
        """
        data = _closed(export, {"export_version", "scope_id", "episodes"}, "export")
        if type(data["export_version"]) is not int or data["export_version"] != VERSION:
            raise HistoryError("unsupported history export version")
        object_ref(data["scope_id"], "host:local")
        if type(data["episodes"]) is not list:
            raise HistoryError("invalid export episodes")
        data = copy.deepcopy(data)
        ids = set()
        for row in data["episodes"]:
            # Establish the first-version record shape before redaction; a
            # restore never upgrades/repairs a malformed schema implicitly.
            validate_episode(row)
            original_inputs = row["inputs"]
            for key in ("inputs", "provenance", "references", "recovery"):
                if key in row:
                    row[key] = _safe(row[key])
            row["inputs_redacted"] = row.get("inputs_redacted", False) or row.get("inputs") != original_inputs
            if isinstance(row.get("verification"), dict):
                row["verification"]["contract"] = _safe(row["verification"].get("contract"))
                for evidence in row["verification"].get("evidence", []):
                    evidence["data"] = _safe(evidence.get("data"))
            validate_episode(row)
            if row["scope_id"] != data["scope_id"] or row["operation_id"] in ids:
                raise HistoryError("export scope or operation identity collision")
            ids.add(row["operation_id"])
        with self._store(write=True) as db:
            existing = [self._read(db, ident)[0] for (ident,) in db.execute("SELECT id FROM episodes ORDER BY admitted,id")]
            ordered = sorted(data["episodes"], key=lambda row: (row["timestamps"]["admitted_at"], row["operation_id"]))
            if existing:
                normalized = []
                by_id = {row["operation_id"]: row for row in existing}
                for source in ordered:
                    row = copy.deepcopy(source)
                    prior = by_id.get(row["operation_id"])
                    if row["lifecycle"] in {"admitted", "running", "provider_complete"} and prior is not None:
                        row = _interrupted(row)
                        # First restoration timestamps are retained on re-entry.
                        row["timestamps"] = copy.deepcopy(prior["timestamps"])
                        row["transitions"][-1]["at"] = prior["transitions"][-1]["at"]
                    normalized.append(row)
                if self._scope(db) == data["scope_id"] and existing == normalized:
                    return {"restored": len(existing), "already_present": True, "scope_id": data["scope_id"]}
                raise HistoryError("restore requires an empty destination; existing history retained")
            db.execute("UPDATE metadata SET value=? WHERE key='scope_id'", (data["scope_id"],))
            for source in data["episodes"]:
                row = copy.deepcopy(source)
                # Export never transfers live-process authority/liveness.
                if row["lifecycle"] in {"admitted", "running", "provider_complete"}:
                    row = _interrupted(row)
                db.execute("INSERT INTO episodes VALUES (?,?,?,?,NULL)", (row["operation_id"], row["correlation_id"], row["timestamps"]["admitted_at"], json.dumps(row, sort_keys=True, separators=(",", ":"))))
            return {"restored": len(data["episodes"]), "already_present": False, "scope_id": data["scope_id"]}

    def reset(self) -> dict[str, Any]:
        with self._store(write=True) as db:
            for (ident,) in db.execute("SELECT id FROM episodes").fetchall():
                row, owner = self._read(db, ident)
                if owner and _alive(owner) and row["lifecycle"] in {"admitted", "running", "provider_complete"}:
                    raise HistoryError("cannot reset history with live attempts")
            count = db.execute("SELECT count(*) FROM episodes").fetchone()[0]
            db.execute("DELETE FROM episodes")
            return {"deleted": count, "scope_id": self._scope(db)}


def _cli() -> int:
    parser = argparse.ArgumentParser(description="Private Igor history service bridge")
    parser.add_argument("action", choices=["prepare", "authority", "running", "provider-complete", "finish", "recent", "inspect", "correlation", "status", "recover", "reconcile", "export", "restore", "reset"])
    args = parser.parse_args()
    try:
        request = _decode(sys.stdin.read())
        data_dir = request.pop("data_dir", None) or os.environ.get("IGOR_HISTORY_DATA_DIR")
        if not data_dir:
            raise HistoryError("history data directory is unavailable")
        service = OperationalHistory(Path(data_dir))
        action = args.action
        result: Any = None
        if action == "prepare":
            result = service.prepare(request["proposal"], correlation_id=request["correlation_id"], provenance=request["provenance"], references=request.get("references"), owner_pid=request["owner_pid"], approval_requirement=request["approval_requirement"])
        elif action == "authority":
            service.authority(request["operation_id"], request["approval"], request["privilege"])
        elif action == "running":
            service.running(request["operation_id"], request.get("proposal"))
        elif action == "provider-complete":
            service.provider_complete(request["operation_id"], request["execution_status"])
        elif action == "finish":
            service.finish(request["operation_id"], request["result"])
        elif action == "recent":
            result = service.recent(limit=request.get("limit", 20))
        elif action == "inspect":
            result = service.inspect(request["operation_id"])
        elif action == "correlation":
            result = service.recent(correlation_id=request["correlation_id"], limit=request.get("limit", 100))
        elif action == "status":
            result = service.status()
        elif action == "recover":
            result = service.recover()
        elif action == "reconcile":
            service.reconcile(request["operation_id"], request["verification_status"], request["evidence"])
        elif action == "export":
            result = service.export()
        elif action == "restore":
            result = service.restore(request["export"])
        elif action == "reset":
            result = service.reset()
        print(json.dumps(result, sort_keys=True, separators=(",", ":"), allow_nan=False))
        return 0
    except (HistoryError, OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print(f"operational history unavailable: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(_cli())
