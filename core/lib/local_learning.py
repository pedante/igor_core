"""Evidence-backed local reference learning; never an execution authority.

Discovery is a bounded read-only projection. Only explicit review freezes a
candidate in the private versioned store. Source records remain with their
owning services; learning retains references, digests and reusable content.
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
import stat
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from baselines import VERSION as BASELINE_VERSION
from baselines import BaselineError, summarize_episodes
from investigations import SUPPORTED_VERSIONS as INVESTIGATION_VERSIONS
from investigations import InvestigationError, InvestigationService
from operational_history import VERSION as HISTORY_VERSION
from operational_history import HistoryError, OperationalHistory, object_ref

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ai"))
from privacy import scrub_text

VERSION = 1
DERIVATION_VERSION = 1
TYPED_DERIVATION_VERSION = 2
PATTERN_DERIVATION_VERSION = 3
MIN_SAMPLES = 3
MIN_PATTERN_INVESTIGATIONS = 3
MAX_LIMIT = 100
INVESTIGATION_LIMIT = 20
MAX_SOURCE_OPERATIONS = 256
MAX_EVIDENCE_REFS = MAX_SOURCE_OPERATIONS + 2 * INVESTIGATION_LIMIT + 2
MAX_RECORDS = 256
MAX_RECORD_BYTES = 262144
MAX_STORE_BYTES = 8388608
CANDIDATE_CONTRACT = "igor.local_learning.candidate"
CONTRACT = "igor.local_learning.artifact"
EXPORT_CONTRACT = "igor.local_learning.export"
_STORE_CONTRACT = "igor.local_learning.store"
_CANDIDATE = re.compile(r"lc-[0-9a-f]{64}")
_LEARNING = re.compile(r"learn-[0-9a-f]{32}")
_OPERATION = re.compile(r"op-[0-9a-f]{32}")
_INVESTIGATION = re.compile(r"inv-[0-9a-f]{32}")
_TYPED_FINDING = re.compile(r"tf-[0-9a-f]{32}")
_DIGEST = re.compile(r"[0-9a-f]{64}")
_IDENT = re.compile(r"[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*")
_STATES = {"accepted", "rejected", "superseded"}
_CANDIDATE_FIELDS = {"contract", "version", "authority", "candidate_id", "candidate_revision", "scope_id",
                     "learning_type", "owner", "applicability_owners", "statement", "uncertainty",
                     "related_objects", "capability", "provider", "compatibility", "outcome",
                     "evidence", "counts", "provenance"}


class LearningError(ValueError):
    """Invalid, stale or unavailable local learning; original storage retained."""


def _check(condition: bool, message: str = "local learning contract validation failed") -> None:
    if not condition:
        raise LearningError(message)


def _closed(value: Any, fields: set[str], optional: set[str] | None = None) -> dict:
    _check(type(value) is dict and fields <= value.keys() <= fields | (optional or set()))
    return value


def _text(value: Any, limit: int = 1024, *, empty: bool = False) -> str:
    _check(type(value) is str and (empty or bool(value)) and len(value) <= limit)
    _check(not re.search(r"[\x00-\x1f\x7f]", value), "unsafe learning text")
    _check(scrub_text(value) == value, "secret-bearing learning text")
    # Existing privacy utilities cover ordinary values. Short known environment
    # secrets are checked as tokens, without treating UUID characters as secrets.
    for key, literal in os.environ.items():
        if literal and len(literal) < 4 and re.search(r"(?:PASSWORD|PASSWD|SECRET|TOKEN|API_KEY)$", key):
            _check(not re.search(r"(?<![A-Za-z0-9])" + re.escape(literal) + r"(?![A-Za-z0-9])", value),
                   "secret-bearing learning text")
    return value


def _identifier(value: Any, pattern: re.Pattern = _IDENT) -> str:
    _check(type(value) is str and pattern.fullmatch(value) is not None, "invalid learning identity")
    return _text(value, 160)


def _scope(value: Any) -> str:
    try:
        object_ref(value, "host:local")
    except HistoryError as exc:
        raise LearningError("invalid learning scope") from exc
    return _text(value, 160)


def _timestamp(value: Any) -> datetime:
    _text(value, 64)
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        _check(result.tzinfo is not None)
        return result
    except ValueError as exc:
        raise LearningError("invalid learning timestamp") from exc


def _array(value: Any, limit: int = MAX_LIMIT) -> list:
    _check(type(value) is list and len(value) <= limit)
    return value


def _integer(value: Any, minimum: int = 0, maximum: int = 2**63 - 1) -> int:
    _check(type(value) is int and minimum <= value <= maximum)
    return value


def _decode(raw: str) -> Any:
    def pairs(items):
        result = {}
        for key, value in items:
            _check(key not in result, "duplicate learning JSON field")
            result[key] = value
        return result
    try:
        return json.loads(raw, object_pairs_hook=pairs,
                          parse_constant=lambda _: _check(False, "nonfinite learning JSON number"))
    except (ValueError, RecursionError) as exc:
        raise LearningError("invalid learning JSON") from exc


def _compact(value: Any) -> str:
    try:
        return json.dumps(value, allow_nan=False, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    except (ValueError, TypeError, RecursionError, UnicodeError) as exc:
        raise LearningError("invalid learning document") from exc


def _copy(value: Any, limit: int = MAX_RECORD_BYTES) -> Any:
    raw = _compact(value)
    _check(len(raw.encode("utf-8")) <= limit, "learning document exceeds size bound")
    return _decode(raw)


def _digest(value: Any) -> str:
    return hashlib.sha256(_compact(value).encode("utf-8")).hexdigest()


def _objects(value: Any, scope_id: str) -> None:
    keys = []
    for ref in _array(value, 128):
        _closed(ref, {"scope_id", "object_id"})
        _check(ref["scope_id"] == scope_id, "nonlocal learning object")
        try:
            object_ref(**ref)
        except HistoryError as exc:
            raise LearningError("invalid learning object") from exc
        keys.append(ref["object_id"])
    _check(keys == sorted(set(keys)), "learning objects must be unique and ordered")


def _compatibility(value: Any) -> None:
    _closed(value, {"capability", "provider"})
    _closed(value["capability"], {"id", "version"})
    _identifier(value["capability"]["id"])
    _check("." in value["capability"]["id"])
    _integer(value["capability"]["version"], 1)
    _closed(value["provider"], {"id", "owner"})
    _identifier(value["provider"]["id"])
    _identifier(value["provider"]["owner"])


def _query(value: Any) -> None:
    _closed(value, {"limit", "capability_id", "investigation_limit"})
    _integer(value["limit"], 1, MAX_LIMIT)
    _check(value["investigation_limit"] == INVESTIGATION_LIMIT and type(value["investigation_limit"]) is int)
    if value["capability_id"] is not None:
        _identifier(value["capability_id"])
        _check("." in value["capability_id"])


def _pattern(value: Any) -> dict:
    value = _closed(value, {"kind", "symptom", "cause", "distinct_investigations"})
    _check(value["kind"] == "symptom_cause", "invalid cross-incident pattern kind")
    _text(value["symptom"], 2048)
    _text(value["cause"], 2048)
    _integer(value["distinct_investigations"], MIN_PATTERN_INVESTIGATIONS, INVESTIGATION_LIMIT)
    return value


def _evidence(value: Any, scope_id: str) -> None:
    _check(type(value) is dict and type(value.get("kind")) is str)
    kind = value["kind"]
    common = {"kind", "scope_id", "source_version", "digest"}
    if kind == "operational_history":
        _closed(value, common | {"operation_id", "recorded_at"})
        _identifier(value["operation_id"], _OPERATION)
        _timestamp(value["recorded_at"])
    elif kind == "investigation":
        _closed(value, common | {"investigation_id", "recorded_at", "finding_index"})
        _identifier(value["investigation_id"], _INVESTIGATION)
        _timestamp(value["recorded_at"])
        _integer(value["finding_index"], 0, 31)
    elif kind == "investigation_typed_finding":
        _closed(value, common | {"investigation_id", "recorded_at", "finding_id", "finding_kind"})
        _identifier(value["investigation_id"], _INVESTIGATION)
        _identifier(value["finding_id"], _TYPED_FINDING)
        _check(value["finding_kind"] in {"symptom", "cause", "action", "verification"},
               "invalid typed finding evidence kind")
        _timestamp(value["recorded_at"])
    elif kind == "reviewed_learning":
        _closed(value, common | {"learning_id", "candidate_id", "candidate_revision",
                                 "investigation_id", "finding_id", "finding_kind", "reviewed_at"})
        _identifier(value["learning_id"], _LEARNING)
        _identifier(value["candidate_id"], _CANDIDATE)
        _identifier(value["candidate_revision"], _DIGEST)
        _identifier(value["investigation_id"], _INVESTIGATION)
        _identifier(value["finding_id"], _TYPED_FINDING)
        _check(value["finding_kind"] in {"symptom", "cause"},
               "cross-incident patterns require symptom/cause learning")
        _timestamp(value["reviewed_at"])
    elif kind == "baseline":
        _closed(value, common | {"operation_ids"})
        ids = _array(value["operation_ids"])
        for ident in ids:
            _identifier(ident, _OPERATION)
        _check(ids == sorted(set(ids)))
    else:
        raise LearningError("unknown learning evidence kind")
    _check(value["scope_id"] == scope_id, "nonlocal learning evidence")
    source_version = value["source_version"]
    _check(type(source_version) is int, "invalid learning source version")
    if kind == "operational_history":
        _check(source_version == HISTORY_VERSION, "unsupported History evidence version")
    elif kind == "baseline":
        _check(source_version == BASELINE_VERSION, "unsupported baseline evidence version")
    elif kind == "reviewed_learning":
        _check(source_version == VERSION, "unsupported reviewed learning evidence version")
    else:
        _check(source_version in INVESTIGATION_VERSIONS,
               "unsupported Investigation evidence version")
        if kind == "investigation_typed_finding":
            _check(source_version >= 2, "typed finding evidence requires Investigation v2")
    _identifier(value["digest"], _DIGEST)


def _candidate_identity(candidate: dict) -> str:
    if candidate["learning_type"] == "recurring_outcome":
        identity = {key: candidate[key] for key in (
            "scope_id", "learning_type", "capability", "provider", "related_objects", "outcome")}
    elif candidate["learning_type"] == "investigation_finding":
        investigation = next(ref for ref in candidate["evidence"] if ref["kind"] == "investigation")
        identity = {"scope_id": candidate["scope_id"], "learning_type": candidate["learning_type"],
                    "investigation_id": investigation["investigation_id"], "finding_index": investigation["finding_index"]}
    elif candidate["learning_type"] == "typed_investigation_finding":
        investigation = next(ref for ref in candidate["evidence"]
                             if ref["kind"] == "investigation_typed_finding")
        identity = {"scope_id": candidate["scope_id"], "learning_type": candidate["learning_type"],
                    "investigation_id": investigation["investigation_id"],
                    "finding_id": investigation["finding_id"]}
    else:
        pattern = candidate["pattern"]
        identity = {
            "scope_id": candidate["scope_id"],
            "learning_type": candidate["learning_type"],
            "kind": pattern["kind"],
            "symptom": pattern["symptom"],
            "cause": pattern["cause"],
            "related_objects": candidate["related_objects"],
            "compatibility": candidate["compatibility"],
        }
    return "lc-" + _digest(identity)


def validate_candidate(value: Any) -> dict:
    """Validate the closed frozen reference contract, including its revision."""
    value = _copy(value)
    _closed(value, _CANDIDATE_FIELDS, {"pattern"})
    _check(value["contract"] == CANDIDATE_CONTRACT and type(value["version"]) is int and value["version"] == VERSION)
    _check(value["authority"] == "reference_only" and value["owner"] == "core")
    _identifier(value["candidate_id"], _CANDIDATE)
    _identifier(value["candidate_revision"], _DIGEST)
    scope_id = _scope(value["scope_id"])
    _check(type(value["learning_type"]) is str and value["learning_type"] in {
        "recurring_outcome", "investigation_finding", "typed_investigation_finding",
        "cross_incident_pattern"})
    owners = _array(value["applicability_owners"], 128)
    for owner in owners:
        _identifier(owner)
    _check(owners == sorted(set(owners)) and bool(owners))
    _text(value["statement"], 2048)
    for uncertainty in _array(value["uncertainty"], 64):
        _text(uncertainty)
    _objects(value["related_objects"], scope_id)
    compatibility = _array(value["compatibility"], 128)
    for item in compatibility:
        _compatibility(item)
    _check(bool(compatibility) and [_compact(item) for item in compatibility] == sorted({_compact(item) for item in compatibility}))
    _check(owners == sorted({item["provider"]["owner"] for item in compatibility}))
    evidence = _array(value["evidence"], MAX_EVIDENCE_REFS)
    for ref in evidence:
        _evidence(ref, scope_id)
    _check([_compact(ref) for ref in evidence] == sorted({_compact(ref) for ref in evidence}))
    operations = [ref["operation_id"] for ref in evidence if ref["kind"] == "operational_history"]
    investigation_ids = {
        ref["investigation_id"] for ref in evidence
        if ref["kind"] in {"investigation", "investigation_typed_finding", "reviewed_learning"}
    }
    investigations = [ref for ref in evidence
                      if ref["kind"] in {"investigation", "investigation_typed_finding"}]
    reviewed_learning = [ref for ref in evidence if ref["kind"] == "reviewed_learning"]
    baselines = [ref for ref in evidence if ref["kind"] == "baseline"]
    _check(len(operations) == len(set(operations)) and bool(operations))
    counts = _closed(value["counts"], {"operations", "investigations", "baselines", "minimum_samples"})
    for key, actual in (("operations", len(operations)),
                        ("investigations", len(investigation_ids)),
                        ("baselines", len(baselines))):
        _check(type(counts[key]) is int and counts[key] == actual)
    provenance = _closed(value["provenance"], {"derivation_version", "rule", "query"})
    expected_derivation = {
        "typed_investigation_finding": TYPED_DERIVATION_VERSION,
        "cross_incident_pattern": PATTERN_DERIVATION_VERSION,
    }.get(value["learning_type"], DERIVATION_VERSION)
    _check(type(provenance["derivation_version"]) is int
           and provenance["derivation_version"] == expected_derivation)
    _check(provenance["rule"] == value["learning_type"])
    _query(provenance["query"])
    if value["learning_type"] == "recurring_outcome":
        _check("pattern" not in value)
        _compatibility({"capability": value["capability"], "provider": value["provider"]})
        _check(compatibility == [{"capability": value["capability"], "provider": value["provider"]}])
        outcome = _closed(value["outcome"], {"outcome", "execution_status", "verification_status"})
        _text(outcome["outcome"], 64)
        _check(type(outcome["execution_status"]) is str and outcome["execution_status"] in {"not_executed", "succeeded", "failed"})
        _check(type(outcome["verification_status"]) is str and outcome["verification_status"] in {"not_applicable", "passed", "failed", "unknown", "unavailable"})
        _check(not outcome["outcome"].startswith("interrupted_"))
        _check(type(counts["minimum_samples"]) is int and counts["minimum_samples"] == MIN_SAMPLES and len(operations) >= MIN_SAMPLES)
        _check(not investigations and not reviewed_learning and len(baselines) == 1
               and baselines[0]["operation_ids"] == sorted(operations))
    elif value["learning_type"] == "cross_incident_pattern":
        _check(value["capability"] is None and value["provider"] is None and value["outcome"] is None)
        pattern = _pattern(value.get("pattern"))
        _check(type(counts["minimum_samples"]) is int
               and counts["minimum_samples"] == MIN_PATTERN_INVESTIGATIONS)
        _check(counts["investigations"] == pattern["distinct_investigations"]
               and counts["investigations"] >= MIN_PATTERN_INVESTIGATIONS)
        _check(not investigations and not baselines)
        by_investigation = {}
        for ref in reviewed_learning:
            by_investigation.setdefault(ref["investigation_id"], set()).add(ref["finding_kind"])
        _check(len(by_investigation) == counts["investigations"])
        _check(all(kinds == {"symptom", "cause"} for kinds in by_investigation.values()),
               "pattern requires one reviewed symptom/cause pair per investigation")
        _check(len(reviewed_learning) == 2 * counts["investigations"])
    else:
        _check("pattern" not in value)
        _check(value["capability"] is None and value["provider"] is None and value["outcome"] is None)
        _check(type(counts["minimum_samples"]) is int and counts["minimum_samples"] == 1)
        _check(len(investigations) == 1 and not reviewed_learning and not baselines)
    _check(value["candidate_id"] == _candidate_identity(value), "candidate identity mismatch")
    _check(value["candidate_revision"] == _digest({key: child for key, child in value.items() if key != "candidate_revision"}),
           "candidate revision mismatch")
    return value


def _review_metadata(value: Any) -> None:
    _closed(value, {"result", "at", "actor", "interface", "reason", "candidate_revision"})
    _check(type(value["result"]) is str and value["result"] in _STATES)
    _timestamp(value["at"])
    _text(value["actor"], 64)
    _text(value["interface"], 64)
    _text(value["reason"])
    _identifier(value["candidate_revision"], _DIGEST)


def validate_learning(value: Any) -> dict:
    value = _copy(value)
    _closed(value, {"contract", "version", "authority", "owner", "learning_id", "scope_id", "status",
                    "candidate", "review", "transitions", "timestamps"})
    _check(value["contract"] == CONTRACT and type(value["version"]) is int and value["version"] == VERSION)
    _check(value["authority"] == "reference_only" and value["owner"] == "core")
    _identifier(value["learning_id"], _LEARNING)
    scope_id = _scope(value["scope_id"])
    candidate = validate_candidate(value["candidate"])
    _check(candidate["scope_id"] == scope_id)
    _review_metadata(value["review"])
    _check(value["review"]["candidate_revision"] == candidate["candidate_revision"])
    timestamps = _closed(value["timestamps"], {"created_at", "updated_at"})
    created, updated = _timestamp(timestamps["created_at"]), _timestamp(timestamps["updated_at"])
    _check(created <= updated and timestamps["created_at"] == value["review"]["at"])
    previous, last = "candidate", created
    transitions = _array(value["transitions"], 2)
    _check(bool(transitions))
    for index, transition in enumerate(transitions):
        _closed(transition, {"from", "review"})
        _review_metadata(transition["review"])
        metadata = transition["review"]
        _check(transition["from"] == previous and metadata["candidate_revision"] == candidate["candidate_revision"])
        _check((index == 0 and metadata == value["review"]) or
               (index == 1 and previous == "accepted" and metadata["result"] == "superseded"))
        stamp = _timestamp(metadata["at"])
        _check(last <= stamp <= updated)
        previous, last = metadata["result"], stamp
    _check(value["status"] == previous and timestamps["updated_at"] == transitions[-1]["review"]["at"])
    return value


def _document(value: Any, contract: str) -> dict:
    value = _copy(value, MAX_STORE_BYTES)
    _closed(value, {"contract", "version", "scope_id", "revision", "epoch", "records"})
    _check(value["contract"] == contract and type(value["version"]) is int and value["version"] == VERSION,
           "unsupported local learning version; original retained")
    scope_id = _scope(value["scope_id"])
    _integer(value["revision"])
    _identifier(value["epoch"], re.compile(r"[0-9a-f]{32}"))
    ids, revisions = [], []
    for row in _array(value["records"], MAX_RECORDS):
        validate_learning(row)
        _check(row["scope_id"] == scope_id, "learning store scope mismatch")
        ids.append(row["learning_id"])
        revisions.append((row["candidate"]["candidate_id"], row["candidate"]["candidate_revision"]))
    _check(len(ids) == len(set(ids)) and len(revisions) == len(set(revisions)), "duplicate learning review")
    return value


def _usable(row: dict) -> bool:
    return (row["lifecycle"] == "terminal" and row["timestamps"]["terminal_at"] is not None
            and type(row["outcome"]) is str and not row["outcome"].startswith("interrupted_"))


def _canonical_compatibility(row: dict) -> dict:
    return {"capability": copy.deepcopy(row["capability"]),
            "provider": {key: row["provider"][key] for key in ("id", "owner")}}


def _history_ref(row: dict) -> dict:
    return {"kind": "operational_history", "scope_id": row["scope_id"], "operation_id": row["operation_id"],
            "source_version": row["schema_version"], "digest": _digest(row), "recorded_at": row["timestamps"]["terminal_at"]}


def _typed_finding_source(investigation: dict, finding: dict) -> dict:
    """Freeze only semantic source material used by one typed learning candidate."""
    supporting = set(finding["supporting_evidence"])
    evidence = sorted(
        (copy.deepcopy(item) for item in investigation["evidence"] if item["id"] in supporting),
        key=_compact,
    )
    _check(len(evidence) == len(supporting), "typed finding supporting evidence unavailable")
    return {
        "investigation_id": investigation["investigation_id"],
        "scope_id": investigation["scope_id"],
        "status": investigation["status"],
        "related_objects": copy.deepcopy(investigation["related_objects"]),
        "unresolved_questions": copy.deepcopy(investigation["unresolved_questions"]),
        "finding": copy.deepcopy(finding),
        "supporting_evidence": evidence,
    }


def _typed_history_ids(source: dict) -> list[str]:
    ids = {
        item["target"]
        for item in source["supporting_evidence"]
        if item["kind"] in {"operation", "verification", "capability_result"}
        and item["availability"] == "available"
    }
    return sorted(ids)


def _reviewed_learning_ref(artifact: dict, typed_ref: dict) -> dict:
    return {
        "kind": "reviewed_learning",
        "scope_id": artifact["scope_id"],
        "source_version": artifact["version"],
        "digest": _digest(artifact),
        "learning_id": artifact["learning_id"],
        "candidate_id": artifact["candidate"]["candidate_id"],
        "candidate_revision": artifact["candidate"]["candidate_revision"],
        "investigation_id": typed_ref["investigation_id"],
        "finding_id": typed_ref["finding_id"],
        "finding_kind": typed_ref["finding_kind"],
        "reviewed_at": artifact["review"]["at"],
    }


def _make_candidate(*, scope_id: str, learning_type: str, statement: str, uncertainty: list,
                    rows: list, related_objects: list, evidence: list, query: dict, outcome: dict | None = None,
                    pattern: dict | None = None, investigation_count: int | None = None,
                    minimum_samples: int | None = None) -> dict:
    compatibility = {_compact(_canonical_compatibility(row)): _canonical_compatibility(row) for row in rows}
    ordered = [compatibility[key] for key in sorted(compatibility)]
    value = {"contract": CANDIDATE_CONTRACT, "version": VERSION, "authority": "reference_only",
             "candidate_id": "", "candidate_revision": "", "scope_id": scope_id, "learning_type": learning_type,
             "owner": "core", "applicability_owners": sorted({row["provider"]["owner"] for row in rows}),
             "statement": statement, "uncertainty": uncertainty, "related_objects": related_objects,
             "capability": ordered[0]["capability"] if learning_type == "recurring_outcome" else None,
             "provider": ordered[0]["provider"] if learning_type == "recurring_outcome" else None,
             "compatibility": ordered, "outcome": outcome, "evidence": sorted(evidence, key=_compact),
             "counts": {"operations": len(rows),
                        "investigations": (
                            investigation_count
                            if investigation_count is not None
                            else int(learning_type in {
                                "investigation_finding", "typed_investigation_finding"})
                        ),
                        "baselines": int(learning_type == "recurring_outcome"),
                        "minimum_samples": (
                            minimum_samples
                            if minimum_samples is not None
                            else MIN_SAMPLES if learning_type == "recurring_outcome" else 1
                        )},
             "provenance": {
                 "derivation_version": {
                     "typed_investigation_finding": TYPED_DERIVATION_VERSION,
                     "cross_incident_pattern": PATTERN_DERIVATION_VERSION,
                 }.get(learning_type, DERIVATION_VERSION),
                 "rule": learning_type,
                 "query": query,
             }}
    if pattern is not None:
        value["pattern"] = copy.deepcopy(pattern)
    value["candidate_id"] = _candidate_identity(value)
    value["candidate_revision"] = _digest({key: child for key, child in value.items() if key != "candidate_revision"})
    return validate_candidate(value)


class LocalLearningService:
    """Local reviewed reference owner. No executor, model, observer or policy handle."""

    def __init__(self, data_dir: Path):
        self._directory = Path(data_dir).absolute() / "local_learning"
        self._history = OperationalHistory(Path(data_dir))
        self._investigations = InvestigationService(Path(data_dir))

    def _local_scope(self, *, required: bool = False) -> str | None:
        try:
            scope_id = self._history.status()["scope_id"]
        except HistoryError as exc:
            if required:
                raise LearningError("local learning source scope unavailable") from exc
            return None
        _check(not required or scope_id is not None, "learning requires retained local scope")
        return scope_id

    @staticmethod
    def _private(info: os.stat_result, *, directory: bool = False) -> None:
        _check(info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == (0o700 if directory else 0o600)
               and (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode) and info.st_nlink == 1),
               "local learning storage is not private")

    @contextlib.contextmanager
    def _store(self, *, write: bool = False, initialize: bool = False):
        _check(not any(path.is_symlink() for path in (self._directory, *self._directory.parents)),
               "learning path contains a symlink")
        if not self._directory.exists():
            if not initialize:
                yield None, None
                return
            self._directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        try:
            fd = os.open(self._directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        except OSError as exc:
            raise LearningError("local learning storage unavailable; original retained") from exc
        try:
            self._private(os.fstat(fd), directory=True)
            fcntl.flock(fd, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
            try:
                record_fd = os.open("store.json", os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd)
            except FileNotFoundError:
                document = None
            else:
                with os.fdopen(record_fd, "r", encoding="utf-8") as stream:
                    self._private(os.fstat(stream.fileno()))
                    raw = stream.read(MAX_STORE_BYTES + 1)
                _check(len(raw.encode("utf-8")) <= MAX_STORE_BYTES, "local learning store too large")
                document = _document(_decode(raw), _STORE_CONTRACT)
                local_scope = self._local_scope(required=write)
                _check(local_scope is None or document["scope_id"] == local_scope,
                       "local learning scope mismatch; original retained")
            yield document, fd
        except (OSError, UnicodeError) as exc:
            raise LearningError("local learning storage unavailable; original retained") from exc
        finally:
            os.close(fd)

    @staticmethod
    def _save(document: dict, directory_fd: int) -> None:
        document = _document(document, _STORE_CONTRACT)
        name = ".pending-" + uuid.uuid4().hex + ".json"
        fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                stream.write(_compact(document))
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, "store.json", src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
            os.fsync(directory_fd)
        finally:
            try:
                os.unlink(name, dir_fd=directory_fd)
            except FileNotFoundError:
                pass

    def _state(self, document: dict | None) -> dict:
        return document or {"contract": _STORE_CONTRACT, "version": VERSION, "scope_id": self._local_scope(),
                            "revision": 0, "epoch": None, "records": []}

    def _cas(self, document: dict | None, expected_revision: int, expected_state: str) -> dict:
        _integer(expected_revision)
        _identifier(expected_state, _DIGEST)
        state = self._state(document)
        _check(state["revision"] == expected_revision and _digest(state) == expected_state,
               "local learning revision/state conflict")
        return state

    @staticmethod
    def _advance(state: dict) -> dict:
        state = copy.deepcopy(state)
        _integer(state["revision"], 0, 2**63 - 2)
        state["revision"] += 1
        if state["epoch"] is None:
            state["epoch"] = uuid.uuid4().hex
        return state

    @staticmethod
    def _record(document: dict | None, learning_id: str) -> dict:
        _identifier(learning_id, _LEARNING)
        row = next((row for row in document["records"] if row["learning_id"] == learning_id), None) if document else None
        _check(row is not None, "local learning artifact unavailable")
        return row

    def status(self) -> dict:
        with self._store() as (document, _):
            state = self._state(document)
            return {"contract": CONTRACT, "version": VERSION, "authority": "reference_only",
                    "availability": "available" if document else "not_created", "scope_id": state["scope_id"],
                    "revision": state["revision"], "state_token": _digest(state),
                    "count": len(state["records"]),
                    "counts": {status: sum(row["status"] == status for row in state["records"]) for status in sorted(_STATES)},
                    "minimum_samples": MIN_SAMPLES, "max_query_limit": MAX_LIMIT,
                    "investigation_query_limit": INVESTIGATION_LIMIT, "source_operation_limit": MAX_SOURCE_OPERATIONS}

    def candidates(self, *, limit: int = MAX_LIMIT, capability_id: str | None = None) -> dict:
        _integer(limit, 1, MAX_LIMIT)
        if capability_id is not None:
            _identifier(capability_id)
            _check("." in capability_id)
        query = {"limit": limit, "capability_id": capability_id, "investigation_limit": INVESTIGATION_LIMIT}
        status = self.status()
        omitted, candidates = [], []
        try:
            source = self._history.status()
            episodes = self._history.recent(limit=limit)
        except HistoryError as exc:
            raise LearningError("local learning history unavailable") from exc
        scope_id = source["scope_id"]
        if scope_id is None:
            return {"contract": "igor.local_learning.candidates", "version": VERSION, "authority": "reference_only",
                    "availability": "insufficient_evidence", "scope_id": None, "query": query, "candidates": [],
                    "omitted": [], "revision": status["revision"], "state_token": status["state_token"]}
        groups, cache = {}, {row["operation_id"]: row for row in episodes}
        for row in episodes:
            if row["scope_id"] != scope_id:
                raise LearningError("history source scope mismatch")
            if capability_id is not None and row["capability"]["id"] != capability_id:
                continue
            if not _usable(row):
                omitted.append({"source": row["operation_id"], "reason": "unfinished_or_interrupted_history"})
                continue
            objects = sorted({ref["object_id"] for ref in row["affected_objects"]})
            key = (row["capability"]["id"], row["capability"]["version"], row["provider"]["id"], row["provider"]["owner"],
                   tuple(objects), row["outcome"], row["execution_status"], row["verification"]["status"])
            groups.setdefault(key, []).append(row)
        for key, rows in sorted(groups.items()):
            if len(rows) < MIN_SAMPLES:
                omitted.append({"source": key[0], "reason": "insufficient_compatible_samples", "sample_count": len(rows)})
                continue
            rows = sorted(rows, key=lambda row: row["operation_id"])
            try:
                baseline = summarize_episodes(rows, scope_id=scope_id, limit=limit, capability_id=capability_id)
                evidence = [_history_ref(row) for row in rows]
                evidence.append({"kind": "baseline", "scope_id": scope_id, "source_version": baseline["schema_version"],
                                 "digest": _digest(baseline), "operation_ids": [row["operation_id"] for row in rows]})
                statement = (f"Retained operations for {key[0]} version {key[1]} by {key[2]} (owner {key[3]}) "
                             f"repeat outcome {key[5]}, execution {key[6]}, verification {key[7]} in {len(rows)} samples.")
                candidates.append(_make_candidate(scope_id=scope_id, learning_type="recurring_outcome", statement=statement,
                    uncertainty=["Repeated outcomes do not establish a cause or a resolution.",
                                 "Evidence is limited to the retained query window."], rows=rows,
                    related_objects=[object_ref(scope_id, obj) for obj in key[4]], evidence=evidence, query=query,
                    outcome={"outcome": key[5], "execution_status": key[6], "verification_status": key[7]}))
            except (LearningError, BaselineError):
                omitted.append({"source": key[0], "reason": "unsafe_or_invalid_evidence"})
        try:
            investigations = self._investigations.list(limit=INVESTIGATION_LIMIT, status="resolved")
        except InvestigationError:
            investigations = []
            omitted.append({"source": "investigations", "reason": "source_unavailable"})
        def source_rows(operation_ids, source_ident):
            rows, unavailable = [], False
            for operation_id in operation_ids:
                if operation_id not in cache:
                    if len(cache) >= MAX_SOURCE_OPERATIONS:
                        omitted.append({"source": source_ident, "operation_id": operation_id,
                                        "reason": "source_operation_bound"})
                        unavailable = True
                        continue
                    try:
                        cache[operation_id] = self._history.inspect(operation_id)
                    except HistoryError:
                        cache[operation_id] = None
                row = cache[operation_id]
                if row is None or row["scope_id"] != scope_id or not _usable(row):
                    omitted.append({"source": source_ident, "operation_id": operation_id,
                                    "reason": "missing_or_unusable_history"})
                    unavailable = True
                else:
                    rows.append(row)
            if unavailable or not rows:
                return None
            if capability_id is not None and any(row["capability"]["id"] != capability_id for row in rows):
                return None
            return rows

        typed_uncertainty = {
            "symptom": "A supported symptom is an Investigation assessment, not current machine truth.",
            "cause": "A supported cause does not establish a reusable causal rule across incidents.",
            "action": "A supported action records assessed occurrence; it does not authorize repetition.",
            "verification": "Canonical capability verification remains owned by Operational History.",
        }

        for investigation in investigations:
            ident = investigation["investigation_id"]
            if investigation["scope_id"] != scope_id:
                omitted.append({"source": ident, "reason": "source_scope_mismatch"})
                continue

            # Preserve the Step 16B free-form compatibility path unchanged.
            legacy_ids = sorted({ref["operation_id"] for ref in investigation["related_history"]})
            if investigation["findings"] and legacy_ids:
                rows = source_rows(legacy_ids, ident)
                if rows is not None:
                    objects = {ref["object_id"] for ref in investigation["related_objects"]}
                    objects.update(ref["object_id"] for row in rows for ref in row["affected_objects"])
                    for index, finding in enumerate(investigation["findings"]):
                        evidence = [_history_ref(row) for row in rows]
                        evidence.append({"kind": "investigation", "scope_id": scope_id,
                                         "source_version": investigation["version"],
                                         "investigation_id": ident, "digest": _digest(investigation),
                                         "recorded_at": investigation["timestamps"]["updated_at"],
                                         "finding_index": index})
                        try:
                            candidates.append(_make_candidate(
                                scope_id=scope_id, learning_type="investigation_finding",
                                statement=f"Investigation {ident} reports: {finding}",
                                uncertainty=[
                                    "This is an attributed investigation finding, not a verified cause or resolution.",
                                    *investigation["unresolved_questions"],
                                ],
                                rows=rows,
                                related_objects=[object_ref(scope_id, obj) for obj in sorted(objects)],
                                evidence=evidence, query=query))
                        except LearningError:
                            omitted.append({"source": ident, "reason": "unsafe_or_invalid_finding"})
            elif investigation["findings"]:
                omitted.append({"source": ident, "reason": "insufficient_investigation_evidence"})

            # Step 16C integration: only explicit supported typed findings with
            # retained canonical History support become reviewable candidates.
            for finding in investigation.get("typed_findings", []):
                finding_id = finding["finding_id"]
                if finding["status"] != "supported":
                    omitted.append({"source": finding_id, "reason": "typed_finding_not_supported"})
                    continue
                try:
                    source_projection = _typed_finding_source(investigation, finding)
                except LearningError:
                    omitted.append({"source": finding_id, "reason": "typed_finding_evidence_unavailable"})
                    continue
                operation_ids = _typed_history_ids(source_projection)
                if not operation_ids:
                    omitted.append({"source": finding_id, "reason": "typed_finding_without_retained_history"})
                    continue
                rows = source_rows(operation_ids, finding_id)
                if rows is None:
                    continue
                objects = {ref["object_id"] for ref in source_projection["related_objects"]}
                objects.update(ref["object_id"] for row in rows for ref in row["affected_objects"])
                evidence = [_history_ref(row) for row in rows]
                evidence.append({
                    "kind": "investigation_typed_finding",
                    "scope_id": scope_id,
                    "source_version": investigation["version"],
                    "investigation_id": ident,
                    "finding_id": finding_id,
                    "finding_kind": finding["kind"],
                    "digest": _digest(source_projection),
                    "recorded_at": finding["updated_at"],
                })
                try:
                    candidates.append(_make_candidate(
                        scope_id=scope_id,
                        learning_type="typed_investigation_finding",
                        statement=(f"Investigation {ident} supports {finding['kind']} finding: "
                                   f"{finding['statement']}"),
                        uncertainty=[
                            "This reviewed candidate remains reference-only and does not create machine truth, desired state, responsibility or permission.",
                            typed_uncertainty[finding["kind"]],
                            *source_projection["unresolved_questions"],
                        ],
                        rows=rows,
                        related_objects=[object_ref(scope_id, obj) for obj in sorted(objects)],
                        evidence=evidence,
                        query=query,
                    ))
                except LearningError:
                    omitted.append({"source": finding_id, "reason": "unsafe_or_invalid_typed_finding"})
        with self._store() as (document, _):
            reviewed = {(row["candidate"]["candidate_id"], row["candidate"]["candidate_revision"]): row
                        for row in document["records"]} if document else {}

        # Step 16D: derive cross-incident symptom/cause patterns only from
        # already-accepted, still-current typed incident learning. Exact text,
        # object scope and compatibility must match; semantic similarity is not
        # inferred by this deterministic layer.
        investigation_by_id = {row["investigation_id"]: row for row in investigations}
        typed_sources = []
        for candidate in candidates:
            if candidate["learning_type"] != "typed_investigation_finding":
                continue
            artifact = reviewed.get((candidate["candidate_id"], candidate["candidate_revision"]))
            if artifact is None or artifact["status"] != "accepted":
                continue
            typed_ref = next(ref for ref in candidate["evidence"]
                             if ref["kind"] == "investigation_typed_finding")
            if typed_ref["finding_kind"] not in {"symptom", "cause"}:
                continue
            investigation = investigation_by_id.get(typed_ref["investigation_id"])
            if investigation is None:
                continue
            finding = next((item for item in investigation.get("typed_findings", [])
                            if item["finding_id"] == typed_ref["finding_id"]), None)
            if finding is None or finding["status"] != "supported":
                continue
            typed_sources.append({
                "artifact": artifact,
                "candidate": candidate,
                "finding": finding,
                "typed_ref": typed_ref,
            })

        per_investigation = {}
        for source_item in typed_sources:
            ident = source_item["typed_ref"]["investigation_id"]
            kind = source_item["typed_ref"]["finding_kind"]
            per_investigation.setdefault(ident, {}).setdefault(kind, []).append(source_item)

        pattern_groups = {}
        for ident, kinds in sorted(per_investigation.items()):
            for symptom in sorted(kinds.get("symptom", []),
                                  key=lambda item: item["artifact"]["learning_id"]):
                for cause in sorted(kinds.get("cause", []),
                                    key=lambda item: item["artifact"]["learning_id"]):
                    if (symptom["candidate"]["related_objects"] != cause["candidate"]["related_objects"]
                            or symptom["candidate"]["compatibility"] != cause["candidate"]["compatibility"]
                            or symptom["candidate"]["applicability_owners"]
                            != cause["candidate"]["applicability_owners"]):
                        continue
                    key = _compact({
                        "symptom": symptom["finding"]["statement"],
                        "cause": cause["finding"]["statement"],
                        "related_objects": symptom["candidate"]["related_objects"],
                        "compatibility": symptom["candidate"]["compatibility"],
                    })
                    current_pair = pattern_groups.setdefault(key, {}).get(ident)
                    pair = (symptom, cause)
                    if current_pair is None or (
                        symptom["artifact"]["learning_id"], cause["artifact"]["learning_id"]
                    ) < (
                        current_pair[0]["artifact"]["learning_id"],
                        current_pair[1]["artifact"]["learning_id"],
                    ):
                        pattern_groups[key][ident] = pair

        for grouped in pattern_groups.values():
            if len(grouped) < MIN_PATTERN_INVESTIGATIONS:
                continue
            pairs = [grouped[ident] for ident in sorted(grouped)]
            symptom_statement = pairs[0][0]["finding"]["statement"]
            cause_statement = pairs[0][1]["finding"]["statement"]
            operation_ids = sorted({
                ref["operation_id"]
                for pair in pairs
                for item in pair
                for ref in item["candidate"]["evidence"]
                if ref["kind"] == "operational_history"
            })
            rows = [cache.get(operation_id) for operation_id in operation_ids]
            if not rows or any(row is None or not _usable(row) for row in rows):
                omitted.append({"source": "cross_incident_pattern",
                                "reason": "pattern_history_unavailable"})
                continue
            evidence = [_history_ref(row) for row in rows]
            for pair in pairs:
                for item in pair:
                    evidence.append(_reviewed_learning_ref(
                        item["artifact"], item["typed_ref"]))
            related_objects = copy.deepcopy(pairs[0][0]["candidate"]["related_objects"])
            pattern = {
                "kind": "symptom_cause",
                "symptom": symptom_statement,
                "cause": cause_statement,
                "distinct_investigations": len(pairs),
            }
            try:
                candidates.append(_make_candidate(
                    scope_id=scope_id,
                    learning_type="cross_incident_pattern",
                    statement=(
                        f"Across {len(pairs)} reviewed investigations with matching compatibility, "
                        "the same supported symptom/cause pair recurred."
                    ),
                    uncertainty=[
                        "Repeated reviewed incident evidence does not prove this symptom always has this cause.",
                        "This pattern is reference-only and does not authorize diagnosis, remediation or execution.",
                        "Only exact typed statements, object scope and compatibility are grouped; semantic similarity is not inferred.",
                    ],
                    rows=rows,
                    related_objects=related_objects,
                    evidence=evidence,
                    query=query,
                    pattern=pattern,
                    investigation_count=len(pairs),
                    minimum_samples=MIN_PATTERN_INVESTIGATIONS,
                ))
            except LearningError:
                omitted.append({"source": "cross_incident_pattern",
                                "reason": "unsafe_or_invalid_pattern"})

        candidates.sort(key=lambda row: row["candidate_id"])
        current = []
        for candidate in candidates:
            row = reviewed.get((candidate["candidate_id"], candidate["candidate_revision"]))
            if row is not None:
                omitted.append({"source": candidate["candidate_id"], "reason": "already_reviewed", "status": row["status"],
                                "learning_id": row["learning_id"]})
            else:
                current.append(candidate)
        if len(current) > limit:
            omitted.append({"source": "candidates", "reason": "candidate_list_bound", "count": len(current) - limit})
        return {"contract": "igor.local_learning.candidates", "version": VERSION, "authority": "reference_only",
                "availability": "available" if current else "insufficient_evidence", "scope_id": scope_id,
                "query": query, "candidates": current[:limit], "omitted": omitted,
                "revision": status["revision"], "state_token": status["state_token"]}

    def candidate(self, candidate_id: str, *, limit: int = MAX_LIMIT, capability_id: str | None = None) -> dict:
        _identifier(candidate_id, _CANDIDATE)
        result = self.candidates(limit=limit, capability_id=capability_id)
        row = next((row for row in result["candidates"] if row["candidate_id"] == candidate_id), None)
        _check(row is not None, "local learning candidate unavailable")
        return row

    def list(self, *, limit: int = 20, status: str | None = None) -> list:
        _integer(limit, 1, MAX_LIMIT)
        _check(status is None or type(status) is str and status in _STATES, "invalid learning status filter")
        with self._store() as (document, _):
            rows = document["records"] if document else []
            return copy.deepcopy(sorted((row for row in rows if status is None or row["status"] == status),
                                        key=lambda row: (_timestamp(row["timestamps"]["updated_at"]), row["learning_id"]),
                                        reverse=True)[:limit])

    def inspect(self, learning_id: str) -> dict:
        with self._store() as (document, _):
            return validate_learning(self._record(document, learning_id))

    def evidence_status(self, learning_id: str) -> dict:
        """Read current source availability separately from the frozen artifact."""
        artifact = self.inspect(learning_id)
        candidate = artifact["candidate"]
        resolved, statuses = {}, []
        for ref in candidate["evidence"]:
            status = "missing"
            try:
                if ref["kind"] == "operational_history":
                    source = self._history.inspect(ref["operation_id"])
                    resolved[ref["operation_id"]] = source
                elif ref["kind"] == "investigation":
                    source = self._investigations.inspect(ref["investigation_id"])
                elif ref["kind"] == "investigation_typed_finding":
                    investigation = self._investigations.inspect(ref["investigation_id"])
                    finding = next(
                        (item for item in investigation.get("typed_findings", [])
                         if item["finding_id"] == ref["finding_id"]),
                        None,
                    )
                    if finding is None:
                        raise InvestigationError("typed finding unavailable")
                    source = _typed_finding_source(investigation, finding)
                elif ref["kind"] == "reviewed_learning":
                    source = self.inspect(ref["learning_id"])
                else:
                    # Evidence lists are canonically ordered, not traversal-ordered;
                    # resolve exact baseline references independently if necessary.
                    rows = []
                    for ident in ref["operation_ids"]:
                        if ident not in resolved:
                            resolved[ident] = self._history.inspect(ident)
                        rows.append(resolved[ident])
                    source = summarize_episodes(rows, scope_id=ref["scope_id"],
                        limit=candidate["provenance"]["query"]["limit"],
                        capability_id=candidate["provenance"]["query"]["capability_id"])
                status = "available" if _digest(source) == ref["digest"] else "changed"
            except (HistoryError, InvestigationError, BaselineError):
                pass
            statuses.append({"reference": copy.deepcopy(ref), "status": status})
        return {"contract": "igor.local_learning.evidence_status", "version": VERSION,
                "authority": "reference_only", "learning_id": learning_id, "scope_id": artifact["scope_id"],
                "candidate_revision": candidate["candidate_revision"], "evidence": statuses}

    @staticmethod
    def _metadata(candidate_revision: str, status: str, actor: str, interface: str, reason: str) -> dict:
        metadata = {"result": status, "at": datetime.now(timezone.utc).isoformat(), "actor": actor,
                    "interface": interface, "reason": reason, "candidate_revision": candidate_revision}
        _review_metadata(metadata)
        return metadata

    def review(self, candidate_id: str, candidate_revision: str, status: str, *, expected_revision: int,
               expected_state: str, actor: str, interface: str, reason: str,
               limit: int = MAX_LIMIT, capability_id: str | None = None) -> dict:
        _identifier(candidate_revision, _DIGEST)
        metadata = self._metadata(candidate_revision, status, actor, interface, reason)
        candidate = self.candidate(candidate_id, limit=limit, capability_id=capability_id)
        _check(candidate["candidate_revision"] == candidate_revision, "local learning candidate revision conflict")
        _check(candidate["scope_id"] == self._local_scope(required=True), "local learning source scope changed")
        # Validate a fresh-state request before creating any local learning path.
        with self._store() as (document, _):
            self._cas(document, expected_revision, expected_state)
        with self._store(write=True, initialize=True) as (document, fd):
            state = self._advance(self._cas(document, expected_revision, expected_state))
            _check(state["scope_id"] == candidate["scope_id"])
            _check(len(state["records"]) < MAX_RECORDS, "local learning capacity reached")
            _check(not any(row["candidate"]["candidate_id"] == candidate_id and
                           row["candidate"]["candidate_revision"] == candidate_revision for row in state["records"]),
                   "local learning candidate revision already reviewed")
            row = {"contract": CONTRACT, "version": VERSION, "authority": "reference_only", "owner": "core",
                   "learning_id": "learn-" + uuid.uuid4().hex, "scope_id": candidate["scope_id"], "status": status,
                   "candidate": candidate, "review": metadata, "transitions": [{"from": "candidate", "review": metadata}],
                   "timestamps": {"created_at": metadata["at"], "updated_at": metadata["at"]}}
            validate_learning(row)
            state["records"].append(row)
            self._save(state, fd)
            return copy.deepcopy(row)

    def supersede(self, learning_id: str, *, expected_revision: int, expected_state: str,
                  actor: str, interface: str, reason: str) -> dict:
        with self._store(write=True) as (document, fd):
            state = self._advance(self._cas(document, expected_revision, expected_state))
            row = self._record(state, learning_id)
            _check(row["status"] == "accepted", "only accepted learning can be superseded")
            metadata = self._metadata(row["candidate"]["candidate_revision"], "superseded", actor, interface, reason)
            row["transitions"].append({"from": "accepted", "review": metadata})
            row["status"] = "superseded"
            row["timestamps"]["updated_at"] = metadata["at"]
            validate_learning(row)
            self._save(state, fd)
            return copy.deepcopy(row)

    def delete(self, learning_id: str, *, expected_revision: int, expected_state: str) -> dict:
        with self._store(write=True) as (document, fd):
            state = self._advance(self._cas(document, expected_revision, expected_state))
            self._record(state, learning_id)
            state["records"] = [row for row in state["records"] if row["learning_id"] != learning_id]
            self._save(state, fd)
            return {"deleted": 1, "learning_id": learning_id, "scope_id": state["scope_id"], "revision": state["revision"]}

    def reset(self, *, expected_revision: int, expected_state: str) -> dict:
        with self._store(write=True) as (document, fd):
            state = self._advance(self._cas(document, expected_revision, expected_state))
            _check(document is not None, "local learning store unavailable for reset")
            count = len(state["records"])
            state["records"] = []
            state["epoch"] = uuid.uuid4().hex
            self._save(state, fd)
            return {"deleted": count, "scope_id": state["scope_id"], "revision": state["revision"]}

    def export(self) -> dict:
        with self._store() as (document, _):
            _check(document is not None, "local learning store unavailable for export")
            return {**copy.deepcopy(document), "contract": EXPORT_CONTRACT}

    def restore(self, export: dict, *, expected_revision: int, expected_state: str) -> dict:
        export = _document(export, EXPORT_CONTRACT)
        _check(export["scope_id"] == self._local_scope(required=True), "restore requires matching retained local scope")
        with self._store() as (document, _):
            self._cas(document, expected_revision, expected_state)
        with self._store(write=True, initialize=True) as (document, fd):
            state = self._cas(document, expected_revision, expected_state)
            existing, imported = ({row["learning_id"]: row for row in rows} for rows in (state["records"], export["records"]))
            if document is not None and existing == imported:
                return {"restored": 0, "existing": len(existing), "scope_id": state["scope_id"], "revision": state["revision"]}
            if existing:
                _check(existing == imported, "restore requires empty or identical destination; original retained")
            state = self._advance(state)
            state["revision"] = max(state["revision"], export["revision"] + 1)
            _integer(state["revision"])
            state["epoch"] = uuid.uuid4().hex
            state["records"] = export["records"]
            self._save(state, fd)
            return {"restored": len(imported), "existing": 0, "scope_id": state["scope_id"], "revision": state["revision"]}

    def handle(self, action: str, fields: dict) -> Any:
        cas = {"expected_revision", "expected_state"}
        operations = {
            "status": (self.status, set(), set()), "candidates": (self.candidates, set(), {"limit", "capability_id"}),
            "candidate": (self.candidate, {"candidate_id"}, {"limit", "capability_id"}),
            "list": (self.list, set(), {"limit", "status"}), "inspect": (self.inspect, {"learning_id"}, set()),
            "evidence_status": (self.evidence_status, {"learning_id"}, set()),
            "review": (self.review, {"candidate_id", "candidate_revision", "status", "actor", "interface", "reason"} | cas,
                       {"limit", "capability_id"}),
            "supersede": (self.supersede, {"learning_id", "actor", "interface", "reason"} | cas, set()),
            "delete": (self.delete, {"learning_id"} | cas, set()), "reset": (self.reset, cas, set()),
            "export": (self.export, set(), set()), "restore": (self.restore, {"export"} | cas, set()),
        }
        _check(type(action) is str and action in operations, "unsupported learning action")
        method, required, optional = operations[action]
        _closed(fields, required, optional)
        return method(**fields)


LocalLearning = LocalLearningService


def _cli() -> int:
    parser = argparse.ArgumentParser(description="Igor local learning: explicit review of reference knowledge")
    parser.add_argument("action")
    args = parser.parse_args()
    try:
        raw = sys.stdin.read(MAX_STORE_BYTES + 1)
        _check(len(raw.encode("utf-8")) <= MAX_STORE_BYTES, "local learning request too large")
        fields = _decode(raw) if raw.strip() else {}
        _check(type(fields) is dict)
        data_dir = fields.pop("data_dir", None)
        if data_dir is None:
            data_dir = os.environ.get("IGOR_DATA_DIR") or str(Path(os.environ.get("IGOR_DIR", ".")) / "data")
        _check(type(data_dir) is str and bool(data_dir))
        result = LocalLearningService(Path(data_dir)).handle(args.action, fields)
        print(_compact(result))
        return 0
    except (LearningError, HistoryError, InvestigationError, BaselineError, OSError, UnicodeError):
        print(_compact({"version": VERSION, "authority": "reference_only", "availability": "unavailable",
                        "error": "local learning request refused"}))
        return 1


if __name__ == "__main__":
    raise SystemExit(_cli())
