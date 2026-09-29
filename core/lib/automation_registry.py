"""Configured automation intent and due READ admission state."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from capability_runtime import CapabilityError, validate_inputs
from domain_event import OBJECT

VERSION = 1
MAX_INTERVAL_SECONDS = 365 * 24 * 60 * 60
IDENT = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
SECRET_NAME = re.compile(r"(?:secret|password|token|credential|private_key)", re.IGNORECASE)


class AutomationError(ValueError):
    """A typed registry, policy, or store failure."""


def _closed(value: Any, fields: set[str], required: set[str], where: str) -> dict[str, Any]:
    if type(value) is not dict or set(value) - fields or required - set(value):
        raise AutomationError(f"{where} has unknown or missing fields")
    return value


def _timestamp(value: Any) -> str:
    if type(value) is not str or not value.endswith("Z"):
        raise AutomationError("once_at must be an absolute UTC timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise AutomationError("once_at is invalid") from exc
    if parsed.tzinfo != timezone.utc:
        raise AutomationError("once_at must be UTC")
    return value


def _trigger(value: Any) -> dict[str, Any]:
    if type(value) is not dict or type(value.get("schema_version")) is not int or value["schema_version"] != 1:
        raise AutomationError("trigger version is unsupported")
    if value.get("kind") == "once_at":
        obj = _closed(value, {"kind", "schema_version", "once_at"},
                      {"kind", "schema_version", "once_at"}, "trigger")
        _timestamp(obj["once_at"])
    elif value.get("kind") == "periodic":
        obj = _closed(value, {"kind", "schema_version", "anchor", "interval_seconds"},
                      {"kind", "schema_version", "anchor", "interval_seconds"}, "trigger")
        _timestamp(obj["anchor"])
        if (type(obj["interval_seconds"]) is not int or
                not 1 <= obj["interval_seconds"] <= MAX_INTERVAL_SECONDS):
            raise AutomationError("periodic interval must be 1 to 31536000 seconds")
    elif value.get("kind") == "event":
        obj = _closed(value, {"kind", "schema_version", "event_type", "owner", "object_id", "min_interval_seconds"},
                      {"kind", "schema_version", "event_type", "min_interval_seconds"}, "trigger")
        if (type(obj["event_type"]) is not str or not IDENT.fullmatch(obj["event_type"]) or
                "." not in obj["event_type"]):
            raise AutomationError("event type is invalid")
        if "owner" in obj and (type(obj["owner"]) is not str or not IDENT.fullmatch(obj["owner"])):
            raise AutomationError("event owner is invalid")
        if "object_id" in obj and (type(obj["object_id"]) is not str or
                                  len(obj["object_id"]) > 160 or not OBJECT.fullmatch(obj["object_id"])):
            raise AutomationError("event object_id is invalid")
        if (type(obj["min_interval_seconds"]) is not int or
                not 0 <= obj["min_interval_seconds"] <= MAX_INTERVAL_SECONDS):
            raise AutomationError("event minimum interval is invalid")
    else:
        raise AutomationError("trigger kind is unsupported")
    return obj


def _periodic_slot(trigger: dict[str, Any], now: datetime) -> datetime | None:
    anchor = datetime.fromisoformat(trigger["anchor"].replace("Z", "+00:00"))
    if now < anchor:
        return None
    seconds = trigger["interval_seconds"]
    return anchor + timedelta(seconds=((now - anchor) // timedelta(seconds=seconds)) * seconds)


def _slot_time(trigger: dict[str, Any], now: datetime) -> datetime | None:
    if trigger["kind"] == "event":
        return None
    if trigger["kind"] == "periodic":
        return _periodic_slot(trigger, now)
    due = datetime.fromisoformat(trigger["once_at"].replace("Z", "+00:00"))
    return due if due <= now else None


def _utc_text(value: datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def _proposal(value: Any) -> dict[str, Any]:
    obj = _closed(value, {"id", "owner", "module_version", "source", "availability", "descriptor"},
                  {"id", "owner", "module_version", "source", "availability", "descriptor"}, "proposal")
    desc = _closed(obj["descriptor"], {"kind", "id", "owner", "source", "trigger", "target", "requires"},
                   {"kind", "id", "trigger", "target"}, "proposal descriptor")
    if (desc["kind"] != "automation" or desc["id"] != obj["id"] or
            type(obj["owner"]) is not str or type(obj["id"]) is not str or
            not obj["id"].startswith(obj["owner"] + ".") or
            type(obj["module_version"]) is not str):
        raise AutomationError("proposal identity or owner is invalid")
    _closed(desc["trigger"], {"kind", "schema_version"}, {"kind", "schema_version"}, "proposal trigger")
    if desc["trigger"] != {"kind": "once_at", "schema_version": 1}:
        raise AutomationError("proposal trigger is unsupported in 14A")
    _target_shape(desc["target"])
    return obj


def _target_shape(value: Any) -> dict[str, Any]:
    obj = _closed(value, {"capability_id", "provider", "inputs"}, {"capability_id", "inputs"}, "target")
    if (type(obj["capability_id"]) is not str or not IDENT.fullmatch(obj["capability_id"]) or
            "." not in obj["capability_id"] or type(obj["inputs"]) is not dict):
        raise AutomationError("target identity or inputs are invalid")
    if "provider" in obj and (type(obj["provider"]) is not str or not IDENT.fullmatch(obj["provider"])):
        raise AutomationError("target provider is invalid")
    if any(SECRET_NAME.search(key) for key in obj["inputs"] if type(key) is str):
        raise AutomationError("secret values are not automation inputs")
    return obj


def _digest(proposal: dict[str, Any]) -> str:
    payload = {key: proposal[key] for key in ("id", "owner", "module_version", "descriptor")}
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _record(value: Any) -> dict[str, Any]:
    fields = {"id", "schema_version", "owner", "source", "enabled", "trigger", "target",
              "execution_policy", "retry_policy", "schedule_cursor", "last_attempt"}
    obj = _closed(value, fields, fields, "automation record")
    if type(obj["id"]) is not str or not re.fullmatch(r"a_[0-9a-f]{32}", obj["id"]):
        raise AutomationError("automation id is invalid")
    if type(obj["schema_version"]) is not int or obj["schema_version"] != VERSION:
        raise AutomationError("automation record version is unsupported")
    if type(obj["owner"]) is not str or obj["owner"] not in {"user", "system"} or type(obj["enabled"]) is not bool:
        raise AutomationError("automation owner or enabled state is invalid")
    source = _closed(obj["source"], {"kind", "actor", "proposal_id", "module_owner", "module_version", "proposal_digest"}, {"kind", "actor"}, "source")
    if type(source["actor"]) is not str or not source["actor"] or len(source["actor"]) > 128:
        raise AutomationError("source actor is invalid")
    if source["kind"] == "manual" and set(source) != {"kind", "actor"}:
        raise AutomationError("manual source is invalid")
    if source["kind"] == "module" and set(source) != {"kind", "actor", "proposal_id", "module_owner", "module_version", "proposal_digest"}:
        raise AutomationError("module source is incomplete")
    if source["kind"] == "module" and (
            any(type(source[key]) is not str or not source[key] for key in ("proposal_id", "module_owner", "module_version")) or
            type(source["proposal_digest"]) is not str or not re.fullmatch(r"[0-9a-f]{64}", source["proposal_digest"])):
        raise AutomationError("module source provenance is invalid")
    if source["kind"] not in {"manual", "module"}:
        raise AutomationError("source kind is invalid")
    _trigger(obj["trigger"])
    _target_shape(obj["target"])
    policy = _closed(obj["execution_policy"], {"schema_version", "kind"}, {"schema_version", "kind"}, "execution policy")
    if type(policy["schema_version"]) is not int or policy != {"schema_version": 1, "kind": "read_unattended"}:
        raise AutomationError("execution policy is unsupported")
    retry = _closed(obj["retry_policy"], {"max_attempts"}, {"max_attempts"}, "retry policy")
    if type(retry["max_attempts"]) is not int or retry != {"max_attempts": 1}:
        raise AutomationError("retry policy is unsupported")
    cursor = obj["schedule_cursor"]
    attempt = obj["last_attempt"]
    if obj["trigger"]["kind"] != "event" and (cursor is None) != (attempt is None):
        raise AutomationError("automation claim state is incomplete")
    if obj["trigger"]["kind"] == "event" and cursor is not None:
        raise AutomationError("event cursor must be transient")
    if cursor is not None:
        _timestamp(cursor)
        trigger = obj["trigger"]
        if trigger["kind"] == "once_at":
            valid_cursor = cursor == trigger["once_at"]
        elif trigger["kind"] == "periodic":
            slot = datetime.fromisoformat(cursor.replace("Z", "+00:00"))
            valid_cursor = _periodic_slot(trigger, slot) == slot
        if not valid_cursor:
            raise AutomationError("automation cursor is invalid")
    if attempt is not None:
        fields = {"attempted_at", "slot", "claim_id", "operation_id", "execution_status",
                  "verification_status", "outcome", "reason"}
        _closed(attempt, fields, fields, "last attempt")
        _timestamp(attempt["attempted_at"])
        if ((cursor is not None and attempt["slot"] != cursor) or
                (cursor is None and (type(attempt["slot"]) is not str or
                 not re.fullmatch(r"[0-9a-f-]{36}", attempt["slot"]))) or
                type(attempt["claim_id"]) is not str or
                not re.fullmatch(r"[0-9a-f]{32}", attempt["claim_id"]) or
                type(attempt["outcome"]) is not str or not attempt["outcome"] or
                len(attempt["outcome"]) > 128):
            raise AutomationError("last attempt is invalid")
        if attempt["operation_id"] is not None and (
                type(attempt["operation_id"]) is not str or len(attempt["operation_id"]) > 128):
            raise AutomationError("last attempt operation ID is invalid")
        for key in ("execution_status", "verification_status", "reason"):
            if attempt[key] is not None and (type(attempt[key]) is not str or len(attempt[key]) > 128):
                raise AutomationError(f"last attempt {key} is invalid")
        if attempt["outcome"] == "interrupted_unknown" and (
                attempt["operation_id"] is not None or attempt["execution_status"] is not None or
                attempt["verification_status"] is not None):
            raise AutomationError("unfinished claim has terminal data")
    return obj


def _json_file(path: Path) -> Any:
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise AutomationError(f"duplicate JSON field {key}")
            result[key] = value
        return result
    return json.loads(path.read_text(), object_pairs_hook=unique)


class Registry:
    def __init__(self, data_dir: Path, capabilities: list[dict[str, Any]], proposals: list[dict[str, Any]],
                 event_types: list[dict[str, Any]] | None = None):
        self.directory = data_dir / "automation"
        self.path = self.directory / "registry.v1.json"
        self.lock_path = self.directory / "registry.v1.lock"
        self.capabilities = capabilities
        self.proposals = {_proposal(row)["id"]: row for row in proposals if row["availability"] == "active"}
        self.event_types = event_types or []

    def _path_check(self) -> None:
        for path in (self.directory, self.path, self.lock_path):
            if path.is_symlink():
                raise AutomationError("automation store path is a symlink")

    def _load(self) -> dict[str, Any]:
        self._path_check()
        if not self.path.exists():
            return {"schema_version": VERSION, "instances": []}
        try:
            data = _json_file(self.path)
            _closed(data, {"schema_version", "instances"}, {"schema_version", "instances"}, "registry")
            if type(data["schema_version"]) is not int or data["schema_version"] != VERSION:
                raise AutomationError("registry version is unsupported")
            if type(data["instances"]) is not list or len(data["instances"]) > 1024:
                raise AutomationError("registry instances are invalid")
            ids = [_record(row)["id"] for row in data["instances"]]
            if len(ids) != len(set(ids)):
                raise AutomationError("duplicate automation id")
            return data
        except (OSError, UnicodeError, json.JSONDecodeError, AutomationError, TypeError, KeyError, AttributeError) as exc:
            raise AutomationError(f"automation store invalid: {exc}; original retained at {self.path}") from exc

    def _write(self, data: dict[str, Any]) -> None:
        self._path_check()
        fd, name = tempfile.mkstemp(prefix=".registry.", dir=self.directory)
        try:
            with os.fdopen(fd, "w") as stream:
                os.fchmod(stream.fileno(), 0o600)
                json.dump(data, stream, sort_keys=True, separators=(",", ":"))
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, self.path)
            dirfd = os.open(self.directory, os.O_RDONLY)
            try:
                os.fsync(dirfd)
            finally:
                os.close(dirfd)
        finally:
            if os.path.exists(name):
                os.unlink(name)

    @contextlib.contextmanager
    def _mutating(self):
        self._path_check()
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.directory, 0o700)
        self._path_check()
        fd = os.open(self.lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            data = self._load()
            yield data
            self._write(data)

    def _target(self, value: Any, *, enable: bool = False) -> tuple[dict[str, Any], str | None]:
        target = _target_shape(value)
        rows = [r for r in self.capabilities if r["id"] == target["capability_id"] and r["availability"] == "active"]
        if "provider" in target:
            rows = [r for r in rows if r["provider"] == target["provider"]]
        if len(rows) != 1:
            return target, "target_unavailable" if not rows else "target_ambiguous"
        descriptor = rows[0]["descriptor"]
        if any(spec.get("type") == "secret_ref" for spec in descriptor["inputs"]["properties"].values()):
            raise AutomationError("secret references are unsupported for automation targets")
        try:
            inputs = validate_inputs(descriptor["inputs"], target["inputs"])
        except CapabilityError as exc:
            raise AutomationError(str(exc)) from exc
        normalized = {**target, "inputs": inputs}
        if enable and (descriptor["safety"]["tier"] != "READ" or descriptor["privilege"] != "none"):
            raise AutomationError("only unprivileged READ targets may be enabled")
        return normalized, None

    def create(self, config: Any, actor: str) -> dict[str, Any]:
        if actor != "operator":
            raise AutomationError("explicit authenticated operator is required")
        cfg = _closed(config, {"owner", "proposal_id", "trigger", "target"}, {"owner", "trigger"}, "configuration")
        if type(cfg["owner"]) is not str or cfg["owner"] not in {"user", "system"}:
            raise AutomationError("owner must be user or system")
        proposal = None
        if "proposal_id" in cfg:
            proposal = self.proposals.get(cfg["proposal_id"])
            if proposal is None:
                raise AutomationError("active proposal is unavailable")
            if "target" in cfg:
                raise AutomationError("proposal target cannot be overridden")
            target = proposal["descriptor"]["target"]
        else:
            if "target" not in cfg:
                raise AutomationError("manual target is required")
            target = cfg["target"]
        trigger = _trigger(cfg["trigger"])
        target, reason = self._target(target)
        if reason:
            raise AutomationError(reason)
        source = ({"kind": "module", "actor": actor, "proposal_id": proposal["id"],
                   "module_owner": proposal["owner"], "module_version": proposal["module_version"],
                   "proposal_digest": _digest(proposal)} if proposal else {"kind": "manual", "actor": actor})
        row = {"id": "a_" + uuid.uuid4().hex, "schema_version": VERSION, "owner": cfg["owner"],
               "source": source, "enabled": False, "trigger": trigger, "target": target,
               "execution_policy": {"schema_version": 1, "kind": "read_unattended"},
               "retry_policy": {"max_attempts": 1}, "schedule_cursor": None, "last_attempt": None}
        _record(row)
        with self._mutating() as data:
            data["instances"].append(row)
        return row

    def mutate(self, action: str, ident: str, actor: str, config: Any = None) -> dict[str, Any]:
        if actor != "operator":
            raise AutomationError("explicit authenticated operator is required")
        if action == "reset" and ident == "all":
            return self.reset_all()
        with self._mutating() as data:
            row = next((r for r in data["instances"] if r["id"] == ident), None)
            if row is None:
                raise AutomationError("automation not found")
            if action == "enable":
                _, reason = self._target(row["target"], enable=True)
                if reason or self._source_reason(row):
                    raise AutomationError(reason or self._source_reason(row))
                if row["trigger"]["kind"] == "event" and not any(
                        event["event_type"] == row["trigger"]["event_type"] and
                        event["availability"] == "active" for event in self.event_types):
                    raise AutomationError("event_type_inactive")
                row["enabled"] = True
            elif action == "disable":
                row["enabled"] = False
            elif action == "edit":
                cfg = _closed(config, {"trigger", "target"}, set(), "edit")
                if not cfg:
                    raise AutomationError("edit requires trigger or target")
                if "trigger" in cfg:
                    trigger = _trigger(cfg["trigger"])
                    if trigger != row["trigger"]:
                        row["schedule_cursor"] = None
                        row["last_attempt"] = None
                    row["trigger"] = trigger
                if "target" in cfg:
                    if row["source"]["kind"] == "module":
                        raise AutomationError("copied proposal target cannot be edited")
                    target, reason = self._target(cfg["target"])
                    if reason:
                        raise AutomationError(reason)
                    row["target"] = target
                row["enabled"] = False
            elif action in {"delete", "reset"}:
                data["instances"].remove(row)
            else:
                raise AutomationError("unknown mutation")
            return row

    def reset_all(self) -> dict[str, Any]:
        """Explicit recovery cutover. Retain original bytes before replacing intent."""
        self._path_check()
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.directory, 0o700)
        self._path_check()
        fd = os.open(self.lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            backup = self.directory / "registry.v1.recovery.json"
            if backup.is_symlink():
                raise AutomationError("recovery path is a symlink")
            if self.path.exists():
                if backup.exists():
                    raise AutomationError("recovery copy already exists; move it before another full reset")
                with self.path.open("rb") as source, backup.open("xb") as target:
                    os.chmod(backup, 0o600)
                    shutil.copyfileobj(source, target)
                    target.flush()
                    os.fsync(target.fileno())
            self._write({"schema_version": VERSION, "instances": []})
            return {"schema_version": VERSION, "instances": [],
                    "recovery_copy": str(backup) if backup.exists() else None}

    def _source_reason(self, row: dict[str, Any]) -> str | None:
        source = row["source"]
        if source["kind"] == "manual":
            return None
        proposal = self.proposals.get(source["proposal_id"])
        if proposal is None:
            return "source_proposal_inactive"
        if _digest(proposal) != source["proposal_digest"]:
            return "source_proposal_changed"
        return None

    def _eligibility_reason(self, row: dict[str, Any], mode: str, now: datetime) -> str | None:
        mode = mode.capitalize()
        if not row["enabled"]:
            return "disabled"
        if row["trigger"]["kind"] == "once_at" and row["schedule_cursor"] is not None:
            return "already_claimed"
        source_reason = self._source_reason(row)
        if source_reason:
            return source_reason
        try:
            _, target_reason = self._target(row["target"])
        except AutomationError:
            return "target_inputs_invalid"
        if target_reason:
            return target_reason
        selected = [r for r in self.capabilities if r["id"] == row["target"]["capability_id"] and
                    r["availability"] == "active" and
                    ("provider" not in row["target"] or r["provider"] == row["target"]["provider"])]
        descriptor = selected[0]["descriptor"]
        if descriptor["safety"]["tier"] != "READ" or descriptor["privilege"] != "none":
            return "target_policy_incompatible"
        if mode not in {"Assist", "Executive"}:
            return "guide_mode" if mode == "Guide" else "mode_unsupported"
        if row["trigger"]["kind"] == "event":
            if not any(event["event_type"] == row["trigger"]["event_type"] and
                       event["availability"] == "active" for event in self.event_types):
                return "event_type_inactive"
            return "awaiting_event"
        slot = _slot_time(row["trigger"], now)
        if slot is None:
            return "not_due"
        if row["trigger"]["kind"] == "periodic" and row["schedule_cursor"] is not None:
            cursor = datetime.fromisoformat(row["schedule_cursor"].replace("Z", "+00:00"))
            if slot <= cursor:
                return "already_claimed"
        return None

    def claim_due(self, mode: str, now: datetime) -> dict[str, Any] | None:
        """Atomically consume one due slot before its canonical invocation."""
        if now.tzinfo != timezone.utc:
            raise AutomationError("claim time must be UTC")
        mode = mode.capitalize()
        if mode not in {"Assist", "Executive"}:
            return None
        with self._mutating() as data:
            for row in data["instances"]:
                if self._eligibility_reason(row, mode, now) is not None:
                    continue
                slot = (row["trigger"]["once_at"] if row["trigger"]["kind"] == "once_at" else
                        _utc_text(_slot_time(row["trigger"], now)))
                claim_id = uuid.uuid4().hex
                row["schedule_cursor"] = slot
                row["last_attempt"] = {
                    "attempted_at": now.isoformat().replace("+00:00", "Z"),
                    "slot": slot, "claim_id": claim_id, "operation_id": None,
                    "execution_status": None, "verification_status": None,
                    "outcome": "interrupted_unknown", "reason": "claimed_before_dispatch",
                }
                return {"id": row["id"], "claim_id": claim_id, "target": row["target"]}
        return None

    def _event_matches(self, row: dict[str, Any], event: dict[str, Any], mode: str,
                       now: datetime) -> bool:
        trigger = row["trigger"]
        if trigger["kind"] != "event" or self._eligibility_reason(row, mode, now) != "awaiting_event":
            return False
        if (event.get("event_type") != trigger["event_type"] or
                ("owner" in trigger and event.get("owner") != trigger["owner"]) or
                ("object_id" in trigger and trigger["object_id"] not in event.get("related_objects", []))):
            return False
        attempt = row["last_attempt"]
        if attempt is not None:
            if attempt["slot"] == event.get("event_id"):
                return False
            previous = datetime.fromisoformat(attempt["attempted_at"].replace("Z", "+00:00"))
            if now < previous + timedelta(seconds=trigger["min_interval_seconds"]):
                return False
        return True

    def match_event(self, event: dict[str, Any], mode: str, now: datetime) -> list[str]:
        if type(event) is not dict or type(event.get("event_id")) is not str:
            raise AutomationError("event signal is invalid")
        return [row["id"] for row in self._load()["instances"] if self._event_matches(row, event, mode, now)]

    def claim_event(self, ident: str, event: dict[str, Any], mode: str,
                    now: datetime) -> dict[str, Any] | None:
        if type(event) is not dict or type(event.get("event_id")) is not str or not re.fullmatch(
                r"[0-9a-f-]{36}", event["event_id"]):
            raise AutomationError("event signal is invalid")
        with self._mutating() as data:
            row = next((r for r in data["instances"] if r["id"] == ident), None)
            if row is None or not self._event_matches(row, event, mode, now):
                return None
            claim_id = uuid.uuid4().hex
            row["last_attempt"] = {
                "attempted_at": _utc_text(now), "slot": event["event_id"], "claim_id": claim_id,
                "operation_id": None, "execution_status": None, "verification_status": None,
                "outcome": "interrupted_unknown", "reason": "claimed_before_dispatch",
            }
            return {"id": row["id"], "claim_id": claim_id, "target": row["target"]}

    def finish(self, ident: str, claim_id: str, result: Any) -> dict[str, Any]:
        """Keep only canonical status fields; an absent result remains unknown."""
        with self._mutating() as data:
            row = next((r for r in data["instances"] if r["id"] == ident), None)
            if row is None or row["last_attempt"] is None or row["last_attempt"]["claim_id"] != claim_id:
                raise AutomationError("claim is unavailable")
            attempt = row["last_attempt"]
            if attempt["outcome"] != "interrupted_unknown":
                raise AutomationError("claim already finished")
            if type(result) is dict and all(type(result.get(key)) is str for key in (
                    "operation_id", "execution_status", "verification_status", "outcome")):
                if (result.get("capability_id") != row["target"]["capability_id"] or
                        ("provider" in row["target"] and result.get("provider") != row["target"]["provider"])):
                    raise AutomationError("capability result does not match claim")
                attempt.update(operation_id=result["operation_id"][:128],
                               execution_status=result["execution_status"][:128],
                               verification_status=result["verification_status"][:128],
                               outcome=result["outcome"][:128], reason=result["outcome"][:128])
            else:
                attempt["reason"] = "canonical_result_unavailable"
            _record(row)
            return attempt

    def inspect(self, ident: str | None = None, *, mode: str = "Assist",
                now: datetime | None = None) -> dict[str, Any]:
        data = self._load()
        now = now or datetime.now(timezone.utc)
        items = []
        for row in data["instances"]:
            if ident and row["id"] != ident:
                continue
            reason = self._eligibility_reason(row, mode, now)
            trigger = row["trigger"]
            if trigger["kind"] == "once_at":
                next_due = trigger["once_at"] if row["schedule_cursor"] is None else None
            elif trigger["kind"] == "periodic":
                current = _periodic_slot(trigger, now)
                if current is None:
                    next_due = trigger["anchor"]
                elif (row["schedule_cursor"] is not None and
                      current <= datetime.fromisoformat(row["schedule_cursor"].replace("Z", "+00:00"))):
                    cursor = datetime.fromisoformat(row["schedule_cursor"].replace("Z", "+00:00"))
                    next_due = _utc_text(cursor + timedelta(seconds=trigger["interval_seconds"]))
                else:
                    next_due = _utc_text(current)
            else:
                next_due = None
            state = ("disabled" if reason == "disabled" else
                     ("claimed" if row["last_attempt"]["outcome"] == "interrupted_unknown" else "completed")
                     if reason == "already_claimed" else
                     "available" if reason is None or reason in {"not_due", "awaiting_event"} else "unavailable")
            items.append({**row, "state": state, "availability_reason": reason,
                          "due": reason is None, "claim_state": (
                              "unclaimed" if row["last_attempt"] is None else
                              "interrupted_unknown" if row["last_attempt"]["outcome"] == "interrupted_unknown" else
                              "terminal"),
                          "next_due_at": next_due,
                          "in_flight": False})
        if ident and not items:
            raise AutomationError("automation not found")
        return {"schema_version": VERSION, "store": str(self.path), "instances": items}

    def list_proposals(self) -> list[dict[str, Any]]:
        return [{**p, "proposal_digest": _digest(p)} for p in self.proposals.values()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["proposals", "list", "inspect", "create", "enable", "disable", "edit", "delete", "reset", "claim", "finish", "match-event", "claim-event"])
    parser.add_argument("argument", nargs="?")
    parser.add_argument("configuration", nargs="?")
    parser.add_argument("--mode", default="Assist")
    parser.add_argument("--now")
    args = parser.parse_args()
    try:
        context = json.load(sys.stdin)
        registry = Registry(Path(context["data_dir"]), context["capabilities"], context["proposals"],
                            context.get("event_types", []))
        if args.action == "proposals":
            result = registry.list_proposals()
        elif args.action in {"list", "inspect"}:
            result = registry.inspect(args.argument if args.action == "inspect" else None, mode=args.mode,
                                      now=datetime.fromisoformat(args.now.replace("Z", "+00:00")) if args.now else None)
        elif args.action == "create":
            result = registry.create(json.loads(args.argument or "{}"), "operator")
        elif args.action == "claim":
            result = registry.claim_due(args.mode, datetime.fromisoformat(args.now.replace("Z", "+00:00"))
                                        if args.now else datetime.now(timezone.utc))
        elif args.action == "match-event":
            result = registry.match_event(json.loads(args.argument or "{}"), args.mode, datetime.now(timezone.utc))
        elif args.action == "claim-event":
            result = registry.claim_event(args.argument or "", json.loads(args.configuration or "{}"), args.mode,
                                          datetime.now(timezone.utc))
        elif args.action == "finish":
            completion = json.loads(args.configuration or "{}")
            result = registry.finish(args.argument or "", completion["claim_id"], completion.get("result"))
        else:
            result = registry.mutate(args.action, args.argument or "", "operator",
                                     json.loads(args.configuration or "{}") if args.action == "edit" else None)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (AutomationError, ValueError, KeyError, OSError, TypeError, AttributeError) as exc:
        print(f"automation: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
