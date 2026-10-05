"""Durable investigations: scoped reference knowledge, never operational authority.

Version 2 adds typed investigation findings while preserving version-1 stores
without read-time migration. No method invokes a model, capability, observer or
policy service.
"""
from __future__ import annotations

import argparse
import contextlib
import copy
import fcntl
import json
import math
import os
import re
import stat
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ai"))
from judgment import JudgmentError, validate_record, validate_request
from operational_history import HistoryError, OperationalHistory, object_ref
from privacy import redactions, scrub_text

CONTRACT = "igor.investigation"
LEGACY_VERSION = 1
VERSION = 2
SUPPORTED_VERSIONS = {LEGACY_VERSION, VERSION}
EXPORT_CONTRACT = "igor.investigations.export"
_STORE_CONTRACT = "igor.investigations.store"
MAX_RECORD_BYTES = 524288
MAX_STORE_BYTES = 8388608
MAX_INVESTIGATIONS = 256
MAX_ITEMS = 32
STATES = {"open", "collecting_evidence", "evaluating", "resolved", "closed", "abandoned"}
TERMINAL = {"resolved", "closed", "abandoned"}
TRANSITIONS = {
    "open": {"collecting_evidence", "evaluating", "closed", "abandoned"},
    "collecting_evidence": {"open", "evaluating", "closed", "abandoned"},
    "evaluating": {"collecting_evidence", "resolved", "closed", "abandoned"},
    "resolved": {"open"}, "closed": {"open"}, "abandoned": {"open"},
}
HYPOTHESIS_STATES = {"proposed", "supported", "contradicted", "inconclusive"}
# Reassessment is explicit and remains a claim, including a return to proposed.
HYPOTHESIS_TRANSITIONS = {state: HYPOTHESIS_STATES - {state} for state in HYPOTHESIS_STATES}
TYPED_FINDING_KINDS = {"symptom", "cause", "action", "verification"}
TYPED_FINDING_STATES = {"supported", "contradicted", "inconclusive"}
EVIDENCE_KINDS = {"operation", "verification", "capability_result", "system_fact", "file", "judgment"}
_INVESTIGATION = re.compile(r"inv-[0-9a-f]{32}")
_HYPOTHESIS = re.compile(r"hyp-[0-9a-f]{32}")
_TYPED_FINDING = re.compile(r"tf-[0-9a-f]{32}")
_OPERATION = re.compile(r"op-[0-9a-f]{32}")
_JUDGMENT = re.compile(r"[0-9a-f]{32}")
_IDENT = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9._:-]{0,159}")
_SENSITIVE = re.compile(r"password|passwd|credential|api[_-]?key|(?:^|_)token(?:$|_)|secret(?!_ref)", re.IGNORECASE)
_FIELDS_V1 = {"contract", "version", "investigation_id", "scope_id", "title", "summary", "source", "owner",
              "provenance", "status", "timestamps", "related_objects", "related_history", "evidence",
              "hypotheses", "judgments", "findings", "unresolved_questions", "closure_reason", "transitions"}
_FIELDS_V2 = _FIELDS_V1 | {"typed_findings"}


class InvestigationError(ValueError):
    """Invalid/unavailable investigation; originals are retained without repair."""


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _check(condition: bool, message: str = "investigation contract validation failed") -> None:
    if not condition:
        raise InvestigationError(message)


def _closed(value: Any, required: set[str], optional: set[str] | None = None) -> dict:
    _check(type(value) is dict and required <= value.keys() <= required | (optional or set()))
    return value


def _scrub(value: str, pairs: list | None = None) -> str:
    pairs = redactions() if pairs is None else pairs
    result = scrub_text(value, pairs)
    for key, literal in os.environ.items():
        if literal and len(literal) < 4 and re.search(r"(?:PASSWORD|PASSWD|SECRET|TOKEN|API_KEY)$", key):
            result = re.sub(r"(?<![A-Za-z0-9])" + re.escape(literal) + r"(?![A-Za-z0-9])", "[REDACTED]", result)
    return result


def _text(value: Any, limit: int = 1024, *, empty: bool = False) -> str:
    _check(type(value) is str and (empty or bool(value)) and len(value) <= limit)
    _check(not re.search(r"[\x00-\x1f\x7f]", value))
    _check(_scrub(value) == value, "secret-bearing investigation content")
    return value


def _timestamp(value: Any) -> datetime:
    _text(value, 64)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        _check(parsed.tzinfo is not None)
        return parsed
    except ValueError as exc:
        raise InvestigationError("invalid investigation timestamp") from exc


def _identifier(value: Any, pattern: re.Pattern = _IDENT) -> str:
    _check(type(value) is str and pattern.fullmatch(value) is not None)
    _text(value, 160)
    return value


def _scope(value: Any) -> str:
    try:
        object_ref(value, "host:local")
    except HistoryError as exc:
        raise InvestigationError("invalid investigation scope") from exc
    return value


def _array(value: Any, limit: int = MAX_ITEMS) -> list:
    _check(type(value) is list and len(value) <= limit)
    return value


def _unique(values: list, field: str | None = None) -> None:
    ids = [item[field] if field else item for item in values]
    _check(len(ids) == len(set(ids)), "duplicate investigation reference")


def _decode(value: str) -> Any:
    def pairs(items):
        result = {}
        for key, item in items:
            _check(key not in result, "duplicate investigation JSON field")
            result[key] = item
        return result
    try:
        return json.loads(value, object_pairs_hook=pairs,
                          parse_constant=lambda _: _check(False, "invalid investigation JSON number"))
    except (ValueError, RecursionError) as exc:
        raise InvestigationError("invalid investigation JSON") from exc


def _copy(value: Any, limit: int = MAX_RECORD_BYTES) -> Any:
    try:
        text = json.dumps(value, allow_nan=False)
        _check(len(text.encode("utf-8")) <= limit, "investigation document too large")
        return _decode(text)
    except (ValueError, TypeError, RecursionError, UnicodeError) as exc:
        raise InvestigationError("invalid investigation document") from exc


def _provenance(value: Any) -> None:
    _closed(value, {"source", "recorded_at"}, {"locator"})
    _text(value["source"], 160)
    _timestamp(value["recorded_at"])
    if "locator" in value:
        _text(value["locator"], 512)


def _history_refs(value: Any, scope_id: str) -> None:
    for reference in _array(value, 128):
        _closed(reference, {"scope_id", "operation_id"})
        _check(reference["scope_id"] == scope_id, "nonlocal investigation reference")
        _identifier(reference["operation_id"], _OPERATION)
    _unique(value, "operation_id")


def _object_refs(value: Any, scope_id: str) -> None:
    for reference in _array(value, 128):
        _closed(reference, {"scope_id", "object_id"})
        _check(reference["scope_id"] == scope_id, "nonlocal investigation reference")
        try:
            object_ref(**reference)
        except HistoryError as exc:
            raise InvestigationError("invalid investigation object reference") from exc
        _text(reference["object_id"], 160)
    _unique(value, "object_id")


def _evidence(value: Any, scope_id: str) -> None:
    _closed(value, {"id", "kind", "scope_id", "target", "source", "recorded_at", "availability"},
            {"locator", "object_id"})
    _identifier(value["id"])
    _check(type(value["kind"]) is str and value["kind"] in EVIDENCE_KINDS)
    _check(value["scope_id"] == scope_id, "nonlocal investigation evidence")
    _text(value["source"], 160)
    _timestamp(value["recorded_at"])
    _check(type(value["availability"]) is str and value["availability"] in {"available", "unavailable", "unknown"})
    kind = value["kind"]
    if kind in {"operation", "capability_result", "verification"}:
        _identifier(value["target"], _OPERATION)
    elif kind == "judgment":
        _identifier(value["target"], _JUDGMENT)
    elif kind == "system_fact":
        try:
            object_ref(scope_id, value["target"])
        except HistoryError as exc:
            raise InvestigationError("invalid system fact reference") from exc
        _text(value["target"], 160)
        # Locator distinguishes property/source/observation; object identity alone
        # would misleadingly refer to the live object rather than sampled evidence.
        _check("locator" in value, "system fact evidence needs an observation locator")
    else:
        _text(value["target"], 160)
    if "object_id" in value:
        _object_refs([{"scope_id": scope_id, "object_id": value["object_id"]}], scope_id)
    if "locator" in value:
        _text(value["locator"], 512)


def _no_secrets(value: Any, pairs: list | None = None, depth: int = 0) -> None:
    _check(depth <= 16)
    pairs = redactions() if pairs is None else pairs
    if type(value) is dict:
        for key, item in value.items():
            _check(_scrub(key, pairs) == key, "secret-bearing judgment content")
            _check(not _SENSITIVE.search(key) and key.lower() not in {"env", "environment", "transcript", "authentication_transcript"},
                   "secret-bearing judgment content")
            _no_secrets(item, pairs, depth + 1)
    elif type(value) is list:
        for item in value:
            _no_secrets(item, pairs, depth + 1)
    elif type(value) is str:
        _check(_scrub(value, pairs) == value, "secret-bearing judgment content")


def _judgment(value: Any, scope_id: str) -> None:
    _closed(value, {"scope_id", "request", "record", "attached_at"})
    _check(value["scope_id"] == scope_id, "nonlocal investigation judgment")
    _timestamp(value["attached_at"])
    try:
        request = validate_request(value["request"])
        validate_record(value["record"], request)
    except JudgmentError as exc:
        raise InvestigationError("invalid investigation judgment binding") from exc
    # Preserve the digest, schema and original provenance. Unsafe pairs must be
    # redacted before judging; rewriting a bound pair would fabricate provenance.
    _no_secrets(request)
    _no_secrets(value["record"])
    for reference in request["references"]:
        _provenance({key: reference[key] for key in ("source", "recorded_at", "locator") if key in reference})
        if "scope_id" in reference:
            _object_refs([{"scope_id": reference["scope_id"], "object_id": reference["object_id"]}], scope_id)
    for key in ("provider", "model"):
        _text(value["record"]["invocation"][key], 160)


def _hypothesis(value: Any, evidence_ids: set[str], judgment_ids: set[str]) -> None:
    _closed(value, {"hypothesis_id", "statement", "status", "supporting_evidence", "contradicting_evidence",
                    "judgments", "assessment", "confidence", "created_at", "updated_at"})
    _identifier(value["hypothesis_id"], _HYPOTHESIS)
    _text(value["statement"])
    _check(type(value["status"]) is str and value["status"] in HYPOTHESIS_STATES)
    for key, allowed in (("supporting_evidence", evidence_ids), ("contradicting_evidence", evidence_ids), ("judgments", judgment_ids)):
        for ident in _array(value[key]):
            _identifier(ident, _JUDGMENT if key == "judgments" else _IDENT)
            _check(ident in allowed, "hypothesis reference unavailable")
        _unique(value[key])
    _check(not set(value["supporting_evidence"]) & set(value["contradicting_evidence"]), "hypothesis evidence conflicts")
    if value["assessment"] is not None:
        _text(value["assessment"])
    confidence = value["confidence"]
    _check(confidence is None or (type(confidence) in {int, float} and math.isfinite(confidence) and 0 <= confidence <= 1))
    _check(_timestamp(value["created_at"]) <= _timestamp(value["updated_at"]))


def _typed_finding(value: Any, evidence: dict[str, dict], hypothesis_ids: set[str],
                   judgment_ids: set[str]) -> None:
    _closed(value, {"finding_id", "kind", "statement", "status", "supporting_evidence",
                    "contradicting_evidence", "hypotheses", "judgments", "created_at", "updated_at"})
    _identifier(value["finding_id"], _TYPED_FINDING)
    _check(type(value["kind"]) is str and value["kind"] in TYPED_FINDING_KINDS,
           "invalid typed finding kind")
    _text(value["statement"])
    _check(type(value["status"]) is str and value["status"] in TYPED_FINDING_STATES,
           "invalid typed finding status")
    for key in ("supporting_evidence", "contradicting_evidence"):
        for ident in _array(value[key]):
            _identifier(ident)
            _check(ident in evidence, "typed finding evidence unavailable")
        _unique(value[key])
    _check(not set(value["supporting_evidence"]) & set(value["contradicting_evidence"]),
           "typed finding evidence conflicts")
    for ident in _array(value["hypotheses"]):
        _identifier(ident, _HYPOTHESIS)
        _check(ident in hypothesis_ids, "typed finding hypothesis unavailable")
    _unique(value["hypotheses"])
    for ident in _array(value["judgments"]):
        _identifier(ident, _JUDGMENT)
        _check(ident in judgment_ids, "typed finding judgment unavailable")
    _unique(value["judgments"])
    if value["status"] == "supported":
        _check(bool(value["supporting_evidence"]), "supported typed finding requires supporting evidence")
        _check(all(evidence[ident]["availability"] == "available" for ident in value["supporting_evidence"]),
               "supported typed finding requires available evidence")
    if value["status"] == "contradicted":
        _check(bool(value["contradicting_evidence"]), "contradicted typed finding requires contradicting evidence")
        _check(all(evidence[ident]["availability"] == "available" for ident in value["contradicting_evidence"]),
               "contradicted typed finding requires available evidence")
    supporting_kinds = {evidence[ident]["kind"] for ident in value["supporting_evidence"]}
    if value["status"] == "supported" and value["kind"] == "action":
        _check(bool(supporting_kinds & {"operation", "capability_result"}),
               "supported action requires operation evidence")
    if value["status"] == "supported" and value["kind"] == "verification":
        _check("verification" in supporting_kinds,
               "supported verification requires verification evidence")
    _check(_timestamp(value["created_at"]) <= _timestamp(value["updated_at"]))


def _upgrade_document(document: dict) -> dict:
    """In-memory v1->v2 migration; caller persists only after a valid typed mutation."""
    _check(document["version"] in SUPPORTED_VERSIONS, "unsupported investigation version")
    if document["version"] == VERSION:
        return document
    _check(document["version"] == LEGACY_VERSION)
    document["version"] = VERSION
    for row in document["investigations"]:
        _check(row["version"] == LEGACY_VERSION)
        row["version"] = VERSION
        row["typed_findings"] = []
    _document(document, _STORE_CONTRACT)
    return document


def validate_investigation(value: Any) -> dict:
    """Validate/detach investigation knowledge. Shape/binding never proves factual truth."""
    value = _copy(value)
    _check(type(value.get("version")) is int and value["version"] in SUPPORTED_VERSIONS,
           "unsupported investigation version")
    _closed(value, _FIELDS_V2 if value["version"] == VERSION else _FIELDS_V1)
    _check(value["contract"] == CONTRACT)
    _identifier(value["investigation_id"], _INVESTIGATION)
    scope_id = _scope(value["scope_id"])
    _text(value["title"], 160)
    _text(value["summary"], empty=True)
    _text(value["source"], 160)
    _text(value["owner"], 160)
    _provenance(value["provenance"])
    status = value["status"]
    _check(type(status) is str and status in STATES)
    _closed(value["timestamps"], {"created_at", "updated_at", "closed_at"})
    created = _timestamp(value["timestamps"]["created_at"])
    updated = _timestamp(value["timestamps"]["updated_at"])
    _check(created <= updated)
    _object_refs(value["related_objects"], scope_id)
    _history_refs(value["related_history"], scope_id)
    evidence_by_id = {}
    for evidence in _array(value["evidence"], 128):
        _evidence(evidence, scope_id)
        if evidence["kind"] in {"operation", "verification", "capability_result"}:
            _check(evidence["target"] in {ref["operation_id"] for ref in value["related_history"]})
        evidence_by_id[evidence["id"]] = evidence
    _unique(value["evidence"], "id")
    for attached in _array(value["judgments"], 8):
        _judgment(attached, scope_id)
        _check(created <= _timestamp(attached["attached_at"]) <= updated)
    judgment_ids = [item["record"]["judgment_id"] for item in value["judgments"]]
    _unique(judgment_ids)
    for hypothesis in _array(value["hypotheses"]):
        _hypothesis(hypothesis, set(evidence_by_id), set(judgment_ids))
        _check(created <= _timestamp(hypothesis["created_at"]) <= _timestamp(hypothesis["updated_at"]) <= updated)
    hypothesis_ids = {item["hypothesis_id"] for item in value["hypotheses"]}
    _unique(value["hypotheses"], "hypothesis_id")
    if value["version"] == VERSION:
        for finding in _array(value["typed_findings"]):
            _typed_finding(finding, evidence_by_id, hypothesis_ids, set(judgment_ids))
            _check(created <= _timestamp(finding["created_at"]) <= _timestamp(finding["updated_at"]) <= updated)
        _unique(value["typed_findings"], "finding_id")
    for key in ("findings", "unresolved_questions"):
        for item in _array(value[key]):
            _text(item)
        _unique(value[key])
    previous, last_at = None, created
    transitions = _array(value["transitions"], 128)
    _check(bool(transitions))
    for index, transition in enumerate(transitions):
        _closed(transition, {"from", "to", "at", "reason"})
        _check(transition["from"] == previous)
        state = transition["to"]
        _check(type(state) is str and state in STATES)
        _check((index == 0 and state == "open" and transition["at"] == value["timestamps"]["created_at"])
               or (index > 0 and state in TRANSITIONS[previous]))
        _text(transition["reason"])
        stamp = _timestamp(transition["at"])
        _check(last_at <= stamp <= updated)
        previous, last_at = state, stamp
    _check(previous == status)
    if status in TERMINAL:
        _text(value["closure_reason"])
        _check(value["closure_reason"] == transitions[-1]["reason"])
        _check(value["timestamps"]["closed_at"] == transitions[-1]["at"] == value["timestamps"]["updated_at"])
    else:
        _check(value["closure_reason"] is None and value["timestamps"]["closed_at"] is None)
    return value


def _document(value: Any, contract: str) -> dict:
    value = _copy(value, MAX_STORE_BYTES)
    _closed(value, {"contract", "version", "scope_id", "investigations"})
    _check(value["contract"] == contract and type(value["version"]) is int
           and value["version"] in SUPPORTED_VERSIONS,
           "unsupported investigation document version; original retained")
    scope_id = _scope(value["scope_id"])
    for record in _array(value["investigations"], MAX_INVESTIGATIONS):
        validate_investigation(record)
        _check(record["version"] == value["version"], "mixed investigation versions are not supported")
        _check(record["scope_id"] == scope_id, "investigation document scope mismatch")
    _unique(value["investigations"], "investigation_id")
    return value


def _safe_path(path: Path) -> None:
    _check(not any(part.is_symlink() for part in (path, *path.parents)), "investigation path contains a symlink")


def _private(info: os.stat_result, *, directory: bool = False) -> None:
    _check(info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == (0o700 if directory else 0o600)
           and (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode) and info.st_nlink == 1),
           "investigation storage is not private")


class InvestigationService:
    """Bounded lifecycle owner. Inspection and export never create or repair state."""

    def __init__(self, data_dir: Path):
        self._data_dir = Path(data_dir).absolute()
        self._directory = self._data_dir / "investigations"
        self._history = OperationalHistory(self._data_dir)

    def _local_scope(self) -> str | None:
        try:
            return self._history.status()["scope_id"]
        except HistoryError as exc:
            raise InvestigationError("local scope unavailable; history original retained") from exc

    @contextlib.contextmanager
    def _store(self, *, write: bool = False, initialize: bool = False):
        _safe_path(self._directory)
        if not self._directory.exists():
            if not initialize:
                yield None, None
                return
            self._directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd = os.open(self._directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            _private(os.fstat(fd), directory=True)
            fcntl.flock(fd, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
            path = self._directory / "store.json"
            _safe_path(path)
            if path.exists():
                record_fd = os.open("store.json", os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd)
                with os.fdopen(record_fd, "r", encoding="utf-8") as stream:
                    _private(os.fstat(stream.fileno()))
                    raw = stream.read(MAX_STORE_BYTES + 1)
                _check(len(raw.encode("utf-8")) <= MAX_STORE_BYTES, "investigation store too large")
                document = _document(_decode(raw), _STORE_CONTRACT)
                _check(document["scope_id"] == self._local_scope(), "local scope differs; original retained")
            else:
                document = None
            yield document, fd
        except (OSError, UnicodeError) as exc:
            raise InvestigationError("investigation storage unavailable; original retained") from exc
        finally:
            os.close(fd)

    @staticmethod
    def _save(document: dict, directory_fd: int) -> None:
        document = _document(document, _STORE_CONTRACT)
        name = ".pending-" + uuid.uuid4().hex + ".json"
        fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(document, stream, ensure_ascii=True, allow_nan=False, sort_keys=True, separators=(",", ":"))
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, "store.json", src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
            os.fsync(directory_fd)
        finally:
            try:
                os.unlink(name, dir_fd=directory_fd)
            except FileNotFoundError:
                pass

    @staticmethod
    def _record(document: dict | None, investigation_id: str, *, editable: bool = False) -> dict:
        _identifier(investigation_id, _INVESTIGATION)
        _check(document is not None, "investigation unavailable")
        row = next((item for item in document["investigations"] if item["investigation_id"] == investigation_id), None)
        _check(row is not None, "investigation unavailable")
        _check(not editable or row["status"] not in TERMINAL, "terminal investigation requires explicit reopening")
        return row

    def create(self, *, title: str, source: str, owner: str, provenance: dict,
               summary: str = "", related_objects: list | None = None, related_history: list | None = None) -> dict:
        _text(title, 160)
        _text(summary, empty=True)
        _text(source, 160)
        _text(owner, 160)
        _provenance(provenance)
        # Validate explicit scope references before allocating the shared identity.
        scope = self._local_scope()
        if related_objects or related_history:
            _check(scope is not None, "local scope unavailable for supplied references")
        related_objects = [] if related_objects is None else _copy(related_objects)
        related_history = [] if related_history is None else _copy(related_history)
        _object_refs(related_objects, scope)
        _history_refs(related_history, scope)
        with self._store(write=True, initialize=True) as (document, fd):
            if document is None:
                try:
                    scope = self._history.ensure_scope()
                except HistoryError as exc:
                    raise InvestigationError("local scope unavailable") from exc
                document = {"contract": _STORE_CONTRACT, "version": VERSION, "scope_id": scope, "investigations": []}
            _check(len(document["investigations"]) < MAX_INVESTIGATIONS, "investigation capacity reached")
            stamp = now()
            record_version = document["version"]
            row = {"contract": CONTRACT, "version": record_version, "investigation_id": "inv-" + uuid.uuid4().hex,
                   "scope_id": document["scope_id"], "title": title, "summary": summary,
                   "source": source, "owner": owner, "provenance": provenance, "status": "open",
                   "timestamps": {"created_at": stamp, "updated_at": stamp, "closed_at": None},
                   "related_objects": related_objects, "related_history": related_history,
                   "evidence": [], "hypotheses": [], "judgments": [], "findings": [], "unresolved_questions": [],
                   "closure_reason": None, "transitions": [{"from": None, "to": "open", "at": stamp, "reason": "created"}]}
            if record_version == VERSION:
                row["typed_findings"] = []
            document["investigations"].append(row)
            self._save(document, fd)
            return validate_investigation(row)

    def _update(self, investigation_id: str, mutate, *, reopen: bool = False,
                require_v2: bool = False) -> dict:
        with self._store(write=True) as (document, fd):
            _check(document is not None, "investigation unavailable")
            if require_v2:
                _upgrade_document(document)
            row = self._record(document, investigation_id, editable=not reopen)
            mutate(row)
            row["timestamps"]["updated_at"] = now()
            result = validate_investigation(row)
            self._save(document, fd)
            return result

    def add_evidence(self, investigation_id: str, evidence: dict) -> dict:
        evidence = _copy(evidence)
        def mutate(row):
            _evidence(evidence, row["scope_id"])
            _check(evidence["id"] not in {ref["id"] for ref in row["evidence"]}, "evidence identity already attached")
            row["evidence"].append(evidence)
            if evidence["kind"] in {"operation", "capability_result", "verification"}:
                reference = {"scope_id": row["scope_id"], "operation_id": evidence["target"]}
                if reference not in row["related_history"]:
                    row["related_history"].append(reference)
        return self._update(investigation_id, mutate)

    def add_hypothesis(self, investigation_id: str, statement: str) -> dict:
        _text(statement)
        def mutate(row):
            stamp = now()
            row["hypotheses"].append({"hypothesis_id": "hyp-" + uuid.uuid4().hex, "statement": statement,
                                      "status": "proposed", "supporting_evidence": [], "contradicting_evidence": [],
                                      "judgments": [], "assessment": None, "confidence": None,
                                      "created_at": stamp, "updated_at": stamp})
        return self._update(investigation_id, mutate)

    def update_hypothesis(self, investigation_id: str, hypothesis_id: str, *, status: str,
                          supporting_evidence: list | None = None, contradicting_evidence: list | None = None,
                          judgments: list | None = None, assessment: str | None = None, confidence: float | None = None) -> dict:
        _identifier(hypothesis_id, _HYPOTHESIS)
        def mutate(row):
            hypothesis = next((item for item in row["hypotheses"] if item["hypothesis_id"] == hypothesis_id), None)
            _check(hypothesis is not None, "hypothesis unavailable")
            _check(type(status) is str and status in HYPOTHESIS_TRANSITIONS[hypothesis["status"]], "invalid hypothesis transition")
            hypothesis.update(status=status, assessment=assessment, confidence=confidence, updated_at=now())
            for key, values in (("supporting_evidence", supporting_evidence), ("contradicting_evidence", contradicting_evidence), ("judgments", judgments)):
                if values is not None:
                    hypothesis[key] = _copy(values)
        return self._update(investigation_id, mutate)

    def attach_judgment(self, investigation_id: str, request: dict, record: dict) -> dict:
        request, record = _copy(request), _copy(record)
        def mutate(row):
            attached = {"scope_id": row["scope_id"], "request": request, "record": record, "attached_at": now()}
            _judgment(attached, row["scope_id"])
            _check(record["judgment_id"] not in {item["record"]["judgment_id"] for item in row["judgments"]}, "judgment already attached")
            row["judgments"].append(attached)
        return self._update(investigation_id, mutate)

    def set_findings(self, investigation_id: str, findings: list) -> dict:
        return self._update(investigation_id, lambda row: row.update(findings=_copy(findings)))

    def add_typed_finding(self, investigation_id: str, *, kind: str, statement: str, status: str,
                          supporting_evidence: list | None = None,
                          contradicting_evidence: list | None = None,
                          hypotheses: list | None = None, judgments: list | None = None) -> dict:
        _check(type(kind) is str and kind in TYPED_FINDING_KINDS, "invalid typed finding kind")
        _text(statement)
        _check(type(status) is str and status in TYPED_FINDING_STATES, "invalid typed finding status")
        supporting_evidence = [] if supporting_evidence is None else _copy(supporting_evidence)
        contradicting_evidence = [] if contradicting_evidence is None else _copy(contradicting_evidence)
        hypotheses = [] if hypotheses is None else _copy(hypotheses)
        judgments = [] if judgments is None else _copy(judgments)

        def mutate(row):
            stamp = now()
            row["typed_findings"].append({
                "finding_id": "tf-" + uuid.uuid4().hex,
                "kind": kind,
                "statement": statement,
                "status": status,
                "supporting_evidence": supporting_evidence,
                "contradicting_evidence": contradicting_evidence,
                "hypotheses": hypotheses,
                "judgments": judgments,
                "created_at": stamp,
                "updated_at": stamp,
            })
        return self._update(investigation_id, mutate, require_v2=True)

    def update_typed_finding(self, investigation_id: str, finding_id: str, *, status: str,
                             supporting_evidence: list | None = None,
                             contradicting_evidence: list | None = None,
                             hypotheses: list | None = None, judgments: list | None = None) -> dict:
        _identifier(finding_id, _TYPED_FINDING)
        _check(type(status) is str and status in TYPED_FINDING_STATES, "invalid typed finding status")

        def mutate(row):
            finding = next((item for item in row["typed_findings"] if item["finding_id"] == finding_id), None)
            _check(finding is not None, "typed finding unavailable")
            finding["status"] = status
            for key, values in (
                ("supporting_evidence", supporting_evidence),
                ("contradicting_evidence", contradicting_evidence),
                ("hypotheses", hypotheses),
                ("judgments", judgments),
            ):
                if values is not None:
                    finding[key] = _copy(values)
            finding["updated_at"] = now()
        return self._update(investigation_id, mutate, require_v2=True)

    def set_questions(self, investigation_id: str, unresolved_questions: list) -> dict:
        return self._update(investigation_id, lambda row: row.update(unresolved_questions=_copy(unresolved_questions)))

    def transition(self, investigation_id: str, status: str, reason: str) -> dict:
        _text(reason)
        def mutate(row):
            _check(type(status) is str and status in TRANSITIONS[row["status"]], "invalid investigation transition")
            stamp = now()
            row["transitions"].append({"from": row["status"], "to": status, "at": stamp, "reason": reason})
            row["status"] = status
            if status in TERMINAL:
                row["closure_reason"] = reason
                row["timestamps"]["closed_at"] = stamp
        # A transition closes at its exact update timestamp; avoid two clock reads.
        with self._store(write=True) as (document, fd):
            row = self._record(document, investigation_id, editable=True)
            mutate(row)
            row["timestamps"]["updated_at"] = row["transitions"][-1]["at"]
            result = validate_investigation(row)
            self._save(document, fd)
            return result

    def close(self, investigation_id: str, reason: str, status: str = "closed") -> dict:
        _check(type(status) is str and status in TERMINAL, "invalid closure state")
        return self.transition(investigation_id, status, reason)

    def reopen(self, investigation_id: str, reason: str) -> dict:
        _text(reason)
        def mutate(row):
            _check(row["status"] in TERMINAL, "only terminal investigations can reopen")
            row["transitions"].append({"from": row["status"], "to": "open", "at": now(), "reason": reason})
            row.update(status="open", closure_reason=None)
            row["timestamps"]["closed_at"] = None
        return self._update(investigation_id, mutate, reopen=True)

    def inspect(self, investigation_id: str) -> dict:
        with self._store() as (document, _):
            return validate_investigation(self._record(document, investigation_id))

    def list(self, *, limit: int = 20, status: str | None = None) -> list:
        _check(type(limit) is int and 1 <= limit <= 100, "invalid investigation list limit")
        _check(status is None or type(status) is str and status in STATES, "invalid investigation status filter")
        with self._store() as (document, _):
            rows = [] if document is None else document["investigations"]
            return copy.deepcopy(sorted((row for row in rows if status is None or row["status"] == status),
                                        key=lambda row: (_timestamp(row["timestamps"]["updated_at"]), row["investigation_id"]), reverse=True)[:limit])

    def status(self) -> dict:
        with self._store() as (document, _):
            return {"contract": CONTRACT, "version": VERSION, "storage_version": document["version"] if document else None,
                    "availability": "available" if document else "not_created",
                    "scope_id": document["scope_id"] if document else self._local_scope(),
                    "count": len(document["investigations"]) if document else 0}

    def export(self) -> dict:
        with self._store() as (document, _):
            _check(document is not None, "investigation store unavailable for export")
            return {**copy.deepcopy(document), "contract": EXPORT_CONTRACT}

    def restore(self, export: dict) -> dict:
        export = _document(export, EXPORT_CONTRACT)
        _check(export["scope_id"] == self._local_scope(), "restore requires matching local history scope")
        with self._store(write=True, initialize=True) as (document, fd):
            if document is None:
                document = {"contract": _STORE_CONTRACT, "version": export["version"],
                            "scope_id": export["scope_id"], "investigations": []}
            _check(document["version"] == export["version"],
                   "restore version differs from destination; existing retained")
            existing = document["investigations"]
            if existing:
                by_id = {row["investigation_id"]: row for row in existing}
                imported = {row["investigation_id"]: row for row in export["investigations"]}
                _check(by_id == imported, "restore requires empty or identical destination; existing retained")
                return {"version": document["version"], "scope_id": document["scope_id"],
                        "restored": 0, "existing": len(existing)}
            document["investigations"] = export["investigations"]
            self._save(document, fd)
            return {"version": document["version"], "scope_id": document["scope_id"],
                    "restored": len(export["investigations"]), "existing": 0}

    def handle(self, action: str, fields: dict) -> Any:
        """Strict programmatic/CLI dispatch; no arbitrary method or tool access."""
        operations = {
            "create": (self.create, {"title", "source", "owner", "provenance"}, {"summary", "related_objects", "related_history"}),
            "add_evidence": (self.add_evidence, {"investigation_id", "evidence"}, set()),
            "add_hypothesis": (self.add_hypothesis, {"investigation_id", "statement"}, set()),
            "update_hypothesis": (self.update_hypothesis, {"investigation_id", "hypothesis_id", "status"},
                                  {"supporting_evidence", "contradicting_evidence", "judgments", "assessment", "confidence"}),
            "attach_judgment": (self.attach_judgment, {"investigation_id", "request", "record"}, set()),
            "set_findings": (self.set_findings, {"investigation_id", "findings"}, set()),
            "add_typed_finding": (
                self.add_typed_finding,
                {"investigation_id", "kind", "statement", "status"},
                {"supporting_evidence", "contradicting_evidence", "hypotheses", "judgments"},
            ),
            "update_typed_finding": (
                self.update_typed_finding,
                {"investigation_id", "finding_id", "status"},
                {"supporting_evidence", "contradicting_evidence", "hypotheses", "judgments"},
            ),
            "set_questions": (self.set_questions, {"investigation_id", "unresolved_questions"}, set()),
            "transition": (self.transition, {"investigation_id", "status", "reason"}, set()),
            "close": (self.close, {"investigation_id", "reason"}, {"status"}),
            "reopen": (self.reopen, {"investigation_id", "reason"}, set()),
            "inspect": (self.inspect, {"investigation_id"}, set()), "list": (self.list, set(), {"limit", "status"}),
            "status": (self.status, set(), set()), "export": (self.export, set(), set()),
            "restore": (self.restore, {"export"}, set()),
        }
        _check(type(action) is str and action in operations, "unsupported investigation action")
        method, required, optional = operations[action]
        _closed(fields, required, optional)
        return method(**fields)


# Public convenience name; one service implementation, no second owner.
Investigations = InvestigationService


def _cli() -> int:
    parser = argparse.ArgumentParser(description="Igor investigation lifecycle; reference-only")
    parser.add_argument("action")
    args = parser.parse_args()
    try:
        raw = sys.stdin.read(MAX_STORE_BYTES + 1)
        _check(len(raw.encode("utf-8")) <= MAX_STORE_BYTES, "investigation request too large")
        fields = _decode(raw) if raw.strip() else {}
        _check(type(fields) is dict)
        data_dir = fields.pop("data_dir", None)
        if data_dir is None:
            data_dir = os.environ.get("IGOR_DATA_DIR") or str(Path(os.environ.get("IGOR_DIR", ".")) / "data")
        _check(type(data_dir) is str and bool(data_dir), "invalid investigation data directory")
        output = InvestigationService(Path(data_dir)).handle(args.action, fields)
        print(json.dumps(output, allow_nan=False, sort_keys=True, separators=(",", ":")))
        return 0
    except (InvestigationError, OSError, UnicodeError):
        print(json.dumps({"version": VERSION, "availability": "unavailable", "error": "investigation request refused"}))
        return 1


if __name__ == "__main__":
    raise SystemExit(_cli())
