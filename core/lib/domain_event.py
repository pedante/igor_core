"""Step 13 domain signals. No policy, execution, or durable history lives here."""

from __future__ import annotations

import fcntl
import json
import math
import os
import re
import stat
import sys
import uuid
from datetime import datetime, timezone
from typing import Any

from capability_runtime import CapabilityError, _validate_result, validate_inputs


class EventError(ValueError):
    """A rejected domain declaration or publication."""


OBJECT = re.compile(r"^[a-z][a-z0-9_-]*:[A-Za-z0-9_./:%+@-]+$")
IDENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,159}$")
UTC = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z$")
SECRET = re.compile(r"secret|password|token|credential|private.key|api.key", re.IGNORECASE)
FIELDS = {"schema_version", "event_id", "event_type", "source", "owner", "related_objects",
          "occurred_at", "recorded_at", "severity", "evidence", "correlation_id", "causation_id",
          "operation_id", "capability_id", "payload"}
STATUSES = {"execution_status": {"not_executed", "failed", "succeeded"},
            "verification_status": {"not_applicable", "passed", "failed", "unknown", "unavailable"},
            "outcome": {"success", "failed", "unverified_result", "unverified_change",
                        "precondition_failed", "approval_denied", "privilege_failed"}}
BUILTIN = {"properties": {key: {"type": "enum", "enum": sorted(values)} for key, values in STATUSES.items()},
           "required": list(STATUSES), "additionalProperties": False}


def _dump(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True, allow_nan=False)


def _stamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _id(value: Any, name: str) -> str:
    if not isinstance(value, str) or not IDENT.fullmatch(value):
        raise EventError(f"invalid {name}")
    return value


def _time(value: Any) -> str:
    if not isinstance(value, str) or not UTC.fullmatch(value):
        raise EventError("invalid UTC timestamp")
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise EventError("invalid UTC timestamp") from exc
    return value


def _safe(value: Any, key: str = "") -> None:
    if SECRET.search(key):
        raise EventError("secret-bearing field")
    if isinstance(value, dict):
        for name, item in value.items():
            _safe(item, str(name))
    elif isinstance(value, list):
        for item in value:
            _safe(item)
    elif isinstance(value, str):
        if len(value) > 256 or any(ord(c) < 32 for c in value) or SECRET.search(value):
            raise EventError("unsafe scalar")
    elif isinstance(value, float) and not math.isfinite(value):
        raise EventError("non-finite number")


def publish(event_type: str, payload: Any, *, owner: str, source: str,
            schema: dict[str, Any], related_objects: Any = None,
            occurred_at: str | None = None, evidence: Any = None,
            severity: str | None = None, correlation_id: str | None = None,
            operation_id: str | None = None, capability_id: str | None = None,
            causation_id: str | None = None) -> dict[str, Any]:
    """Validate caller data before Core stamps authoritative envelope fields."""
    _id(event_type, "event_type")
    _id(owner, "owner")
    _id(source, "source")
    if isinstance(payload, dict) and set(payload) & (FIELDS - {"payload"}):
        raise EventError("payload cannot redeclare Core envelope fields")
    try:
        validated = validate_inputs(schema, payload)
    except CapabilityError as exc:
        raise EventError(str(exc)) from exc
    if event_type == "capability.completed":
        _validate_status(validated)
    objects = related_objects if related_objects is not None else []
    if not isinstance(objects, list) or len(objects) > 8 or any(not isinstance(obj, str) or not OBJECT.fullmatch(obj) or len(obj) > 160 for obj in objects):
        raise EventError("invalid related_objects")
    refs = evidence if evidence is not None else []
    if not isinstance(refs, list) or len(refs) > 8:
        raise EventError("invalid evidence")
    for ref in refs:
        if not isinstance(ref, dict) or set(ref) != {"kind", "ref"}:
            raise EventError("invalid evidence reference")
        _id(ref["kind"], "evidence kind")
        _id(ref["ref"], "evidence ref")
    if severity is not None and severity not in {"info", "warning", "critical"}:
        raise EventError("invalid severity")
    for name, value in (("correlation_id", correlation_id), ("operation_id", operation_id),
                        ("capability_id", capability_id), ("causation_id", causation_id)):
        if value is not None:
            _id(value, name)
    if causation_id is not None:
        try:
            uuid.UUID(causation_id, version=4)
        except ValueError as exc:
            raise EventError("invalid causation_id") from exc
    _safe(validated)
    _safe(refs)
    if len(_dump(validated).encode()) > 2048:
        raise EventError("payload exceeds 2048 bytes")
    now = _stamp()
    event = {"schema_version": 1, "event_id": str(uuid.uuid4()), "event_type": event_type,
             "source": source, "owner": owner, "related_objects": objects,
             "occurred_at": _time(occurred_at) if occurred_at is not None else now,
             "recorded_at": now, "evidence": refs, "payload": validated}
    for name, value in (("severity", severity), ("correlation_id", correlation_id),
                        ("causation_id", causation_id), ("operation_id", operation_id),
                        ("capability_id", capability_id)):
        if value is not None:
            event[name] = value
    validate_envelope(event, schema)
    return event


def _validate_status(payload: dict[str, Any]) -> None:
    execution, verification, outcome = (payload[key] for key in STATUSES)
    if outcome == "success" and (execution != "succeeded" or verification not in {"passed", "not_applicable"}):
        raise EventError("invalid success status combination")
    if outcome in {"unverified_result", "unverified_change"} and (execution != "succeeded" or verification not in {"failed", "unknown", "unavailable"}):
        raise EventError("invalid unverified status combination")
    if outcome == "failed" and execution != "failed":
        raise EventError("invalid failure status combination")
    if outcome in {"precondition_failed", "approval_denied", "privilege_failed"} and (execution != "not_executed" or verification != "not_applicable"):
        raise EventError("invalid nonexecution status combination")


def validate_envelope(event: Any, schema: dict[str, Any]) -> None:
    required = FIELDS - {"severity", "correlation_id", "causation_id", "operation_id", "capability_id"}
    if not isinstance(event, dict) or set(event) - FIELDS or required - set(event):
        raise EventError("invalid event envelope")
    if type(event["schema_version"]) is not int or event["schema_version"] != 1:
        raise EventError("unsupported schema version")
    try:
        ident = uuid.UUID(event["event_id"])
    except (ValueError, TypeError, AttributeError) as exc:
        raise EventError("invalid event ID") from exc
    if ident.version != 4:
        raise EventError("invalid event ID")
    _time(event["occurred_at"])
    _time(event["recorded_at"])
    for name in ("source", "owner", "event_type"):
        _id(event[name], name)
    objects = event["related_objects"]
    if not isinstance(objects, list) or len(objects) > 8 or any(not isinstance(obj, str) or len(obj) > 160 or not OBJECT.fullmatch(obj) for obj in objects):
        raise EventError("invalid related_objects")
    refs = event["evidence"]
    if not isinstance(refs, list) or len(refs) > 8 or any(not isinstance(ref, dict) or set(ref) != {"kind", "ref"} for ref in refs):
        raise EventError("invalid evidence")
    for ref in refs:
        _id(ref["kind"], "evidence kind")
        _id(ref["ref"], "evidence ref")
    if "severity" in event and event["severity"] not in {"info", "warning", "critical"}:
        raise EventError("invalid severity")
    for name in ("correlation_id", "operation_id", "capability_id"):
        if name in event:
            _id(event[name], name)
    if "causation_id" in event:
        try:
            if uuid.UUID(event["causation_id"]).version != 4:
                raise EventError("invalid causation_id")
        except (ValueError, TypeError, AttributeError) as exc:
            raise EventError("invalid causation_id") from exc
    try:
        validate_inputs(schema, event["payload"])
    except CapabilityError as exc:
        raise EventError(str(exc)) from exc
    if event["event_type"] == "capability.completed":
        _validate_status(event["payload"])
    _safe(event["payload"])
    _safe(refs)
    if len(_dump(event["payload"]).encode()) > 2048:
        raise EventError("payload exceeds 2048 bytes")
    if len(_dump(event).encode()) > 4096:
        raise EventError("event exceeds 4096 bytes")


def from_result(result: Any) -> dict[str, Any]:
    try:
        _validate_result(result)
    except CapabilityError as exc:
        raise EventError(str(exc)) from exc
    required = {"owner", "affected_objects", "recorded_at"}
    if not required <= set(result):
        raise EventError("incomplete canonical result")
    return publish("capability.completed", {key: result[key] for key in STATUSES},
                   owner=result["owner"], source="core:capability_runtime", schema=BUILTIN,
                   related_objects=result["affected_objects"], occurred_at=result["recorded_at"].replace("+00:00", "Z"),
                   evidence=[{"kind": "capability_result", "ref": result["operation_id"]}],
                   severity="info" if result["outcome"] == "success" else "warning",
                   correlation_id=result["operation_id"], operation_id=result["operation_id"],
                   capability_id=result["capability_id"])


def _open_buffer(path: str, *, writable: bool = False):
    fd = os.open(path, (os.O_RDWR if writable else os.O_RDONLY) | os.O_NOFOLLOW)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        os.close(fd)
        raise EventError("unsafe session buffer")
    return os.fdopen(fd, "r+" if writable else "r", encoding="utf-8")


def append(path: str, event: dict[str, Any]) -> None:
    with _open_buffer(path, writable=True) as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        rows = [json.loads(line) for line in stream if line.strip()]
        if any(row["event_id"] == event["event_id"] for row in rows):
            raise EventError("duplicate event ID")
        rows = (rows + [event])[-128:]
        stream.seek(0)
        stream.truncate()
        stream.write("".join(_dump(row) + "\n" for row in rows))
        stream.flush()


def inspect(path: str, filters: dict[str, str]) -> list[dict[str, Any]]:
    if set(filters) - {"event_type", "owner", "object_id", "correlation_id"}:
        raise EventError("unknown event filter")
    with _open_buffer(path) as stream:
        fcntl.flock(stream, fcntl.LOCK_SH)
        rows = [json.loads(line) for line in stream if line.strip()]
    return [row for row in rows if all((value in row["related_objects"] if key == "object_id" else row.get(key) == value)
                                       for key, value in filters.items() if value)]


def main() -> int:
    try:
        op, path = sys.argv[1:3]
        if op == "result":
            event = from_result(json.load(sys.stdin))
            append(path, event)
            print(_dump(event))
        elif op == "module":
            descriptor = json.loads(sys.argv[3])
            request = json.load(sys.stdin)
            if not isinstance(request, dict) or set(request) - {"payload", "related_objects"}:
                raise EventError("module publish accepts payload and related_objects only")
            event = publish(descriptor["id"], request.get("payload"), owner=descriptor["owner"],
                            source="module:" + descriptor["owner"], schema=descriptor["payload_schema"],
                            related_objects=request.get("related_objects"))
            append(path, event)
            print(_dump(event))
        elif op == "validate-module":
            with open(path, encoding="utf-8") as stream:
                descriptors = [json.loads(line) for line in stream if line.strip()]
            event_type = sys.argv[3]
            matches = [row for row in descriptors if row["id"] == event_type]
            if len(matches) != 1:
                raise EventError("unknown or inactive module event type")
            request = json.load(sys.stdin)
            if not isinstance(request, dict) or set(request) - {"payload", "related_objects"}:
                raise EventError("module publish accepts payload and related_objects only")
            descriptor = matches[0]
            publish(event_type, request.get("payload"), owner=descriptor["owner"],
                    source="module:" + descriptor["owner"], schema=descriptor["payload_schema"],
                    related_objects=request.get("related_objects"))
        elif op == "inspect":
            print(_dump(inspect(path, json.loads(sys.argv[3]))))
        else:
            raise EventError("unknown bus operation")
        return 0
    except (EventError, KeyError, TypeError, ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"domain event: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
