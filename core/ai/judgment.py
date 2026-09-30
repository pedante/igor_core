"""In-memory, reference-only judgments. No state, policy, tools or transport.

Adapters are trusted local integration code, not model-authored callbacks. They
receive a detached request and return JSON data; they must expose no tools and
enforce their own transport deadline. Igor validates every returned value.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
import uuid
from datetime import datetime, timezone
from typing import Protocol

CONTRACT = "igor.judgment"
VERSION = 1
MAX_BYTES = 16_384
MAX_RECORD_BYTES = 2 * MAX_BYTES + 4096
MAX_DEPTH = 8
MAX_NODES = 512
MAX_REFERENCES = 32
STATUSES = {
    "valid", "abstain", "unknown", "invalid_output", "provider_failure",
    "unavailable", "timeout",
}
REASONS = {
    "valid": {None},
    "abstain": {"insufficient_information", "insufficient_confidence", "cannot_decide"},
    "unknown": {"insufficient_information", "cannot_decide"},
    "invalid_output": {"schema_failure"},
    "provider_failure": {"provider_failed"},
    "unavailable": {"provider_unavailable"},
    "timeout": {"provider_timeout"},
}
VALIDATION = {
    "valid": "valid", "abstain": "valid", "unknown": "valid",
    "invalid_output": "invalid", "provider_failure": "not_run",
    "unavailable": "not_run", "timeout": "not_run",
}
_NAME = re.compile(r"[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*")


class JudgmentError(ValueError):
    """Invalid caller contract or record; contains no input/provider text."""


class ProviderUnavailable(Exception):
    """An adapter is disabled, unconfigured or unavailable."""


class ProviderFailure(Exception):
    """An adapter failed to obtain a completed model response."""


class JudgmentAdapter(Protocol):
    def __call__(self, request: dict) -> str | dict:
        """Return one JSON response, or raise a provider/timeout exception."""


def _check(condition: bool) -> None:
    if not condition:
        raise JudgmentError("judgment contract validation failed")


def _bounded(value: object, *, record: bool = False) -> None:
    nodes = 0

    def visit(item: object, depth: int) -> None:
        nonlocal nodes
        nodes += 1
        _check(nodes <= (2 * MAX_NODES + 64 if record else MAX_NODES) and depth <= MAX_DEPTH)
        if type(item) is dict:
            _check(all(type(key) is str and len(key) <= 160 for key in item))
            for child in item.values():
                visit(child, depth + 1)
        elif type(item) is list:
            for child in item:
                visit(child, depth + 1)
        elif type(item) is float:
            _check(math.isfinite(item))
        elif type(item) is str:
            _check(len(item) <= MAX_BYTES)
        else:
            _check(type(item) in (str, int, bool, type(None)))

    visit(value, 0)


def _encode(value: object, *, record: bool = False) -> str:
    _bounded(value, record=record)
    try:
        text = json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)
        _check(len(text.encode("utf-8")) <= (MAX_RECORD_BYTES if record else MAX_BYTES))
        return text
    except (ValueError, TypeError, UnicodeError) as exc:
        raise JudgmentError("judgment contract validation failed") from exc


def _pairs(pairs: list) -> dict:
    result = {}
    for key, value in pairs:
        _check(key not in result)
        result[key] = value
    return result


def _copy(value: object, *, record: bool = False) -> object:
    if type(value) is str:
        try:
            _check(len(value.encode("utf-8")) <= (MAX_RECORD_BYTES if record else MAX_BYTES))
            value = json.loads(value, object_pairs_hook=_pairs,
                               parse_constant=lambda _: _check(False))
        except (ValueError, TypeError, RecursionError, UnicodeError) as exc:
            raise JudgmentError("judgment contract validation failed") from exc
    return json.loads(_encode(value, record=record))


def _closed(value: object, required: set, optional: set | None = None) -> None:
    _check(type(value) is dict)
    _check(required <= value.keys() <= required | (optional or set()))


def _text(value: object, limit: int = 160) -> None:
    _check(type(value) is str and 0 < len(value) <= limit)
    _check(not any(ord(char) < 32 or ord(char) == 127 for char in value))


def _version(value: object) -> None:
    _check(type(value) is int and 1 <= value <= 2**31 - 1)


def _timestamp(value: object) -> datetime:
    _text(value, 40)
    try:
        _check(value.endswith("Z"))
        return datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        raise JudgmentError("judgment contract validation failed") from exc


def _schema(schema: object, depth: int = 0) -> None:
    """A deliberately small closed JSON Schema subset; no executable validators."""
    _check(depth <= 4 and type(schema) is dict)
    typ = schema.get("type")
    _check(type(typ) is str)
    common = {"type", "enum"}
    if typ == "object":
        _closed(schema, {"type", "properties", "required", "additionalProperties"})
        _check(schema["additionalProperties"] is False)
        props, required = schema["properties"], schema["required"]
        _check(type(props) is dict and len(props) <= 32 and type(required) is list)
        _check(all(type(name) is str for name in required))
        _check(len(set(required)) == len(required) and set(required) <= props.keys())
        for name, child in props.items():
            _text(name, 64)
            _schema(child, depth + 1)
    elif typ == "array":
        _closed(schema, {"type", "items", "maxItems"}, {"minItems"})
        _check(type(schema["maxItems"]) is int and 0 <= schema["maxItems"] <= 64)
        minimum = schema.get("minItems", 0)
        _check(type(minimum) is int and 0 <= minimum <= schema["maxItems"])
        _schema(schema["items"], depth + 1)
    elif typ == "string":
        _closed(schema, {"type", "maxLength"}, {"minLength", "enum"})
        _check(type(schema["maxLength"]) is int and 0 <= schema["maxLength"] <= 4096)
        minimum = schema.get("minLength", 0)
        _check(type(minimum) is int and 0 <= minimum <= schema["maxLength"])
    elif typ in {"number", "integer"}:
        _closed(schema, {"type"}, {"minimum", "maximum", "enum"})
        for key in ("minimum", "maximum"):
            if key in schema:
                _check(type(schema[key]) in (int, float))
                _check(type(schema[key]) is int or math.isfinite(schema[key]))
        _check(schema.get("minimum", -math.inf) <= schema.get("maximum", math.inf))
    else:
        _check(typ in {"boolean", "null"})
        _closed(schema, {"type"}, common - {"type"})
    if "enum" in schema:
        values = schema["enum"]
        _check(type(values) is list and 0 < len(values) <= 32)
        for value in values:
            _value(value, {key: val for key, val in schema.items() if key != "enum"})
        _check(len({_encode(value) for value in values}) == len(values))


def _value(value: object, schema: dict) -> None:
    typ = schema["type"]
    if typ == "object":
        _closed(value, set(schema["required"]), set(schema["properties"]))
        for name, child in value.items():
            _value(child, schema["properties"][name])
    elif typ == "array":
        _check(type(value) is list)
        _check(schema.get("minItems", 0) <= len(value) <= schema["maxItems"])
        for child in value:
            _value(child, schema["items"])
    elif typ == "string":
        _check(type(value) is str)
        _check(schema.get("minLength", 0) <= len(value) <= schema["maxLength"])
    elif typ in {"number", "integer"}:
        _check(type(value) in ((int,) if typ == "integer" else (int, float)))
        _check(type(value) is int or math.isfinite(value))
        _check(schema.get("minimum", -math.inf) <= value <= schema.get("maximum", math.inf))
    else:
        _check(type(value) is (bool if typ == "boolean" else type(None)))
    if "enum" in schema:
        _check(any(type(value) is type(candidate) and value == candidate for candidate in schema["enum"]))


def validate_request(request: dict | str) -> dict:
    """Validate and detach a caller-owned request before invoking any adapter."""
    request = _copy(request)
    _closed(request, {"contract", "version", "kind", "kind_version", "input",
                      "references", "output_schema"})
    _check(request["contract"] == CONTRACT and type(request["version"]) is int
           and request["version"] == VERSION)
    _text(request["kind"], 64)
    _check(_NAME.fullmatch(request["kind"]) is not None)
    _version(request["kind_version"])
    _check(type(request["input"]) is dict and type(request["references"]) is list)
    _check(len(request["references"]) <= MAX_REFERENCES)
    ids = set()
    for reference in request["references"]:
        _closed(reference, {"id", "source", "recorded_at"},
                {"locator", "scope_id", "object_id"})
        for key, value in reference.items():
            _text(value, 512 if key == "locator" else 160)
        _timestamp(reference["recorded_at"])
        _check(reference["id"] not in ids)
        ids.add(reference["id"])
        _check(("scope_id" in reference) == ("object_id" in reference))
    _schema(request["output_schema"])
    _check(request["output_schema"]["type"] == "object")
    return request


def _response(response: object, request: dict) -> dict:
    _closed(response, {"status", "payload", "evidence", "reason"}, {"confidence"})
    status = response["status"]
    _check(type(status) is str and status in {"valid", "abstain", "unknown"})
    _check(type(response["reason"]) in (str, type(None)) and response["reason"] in REASONS[status])
    evidence = response["evidence"]
    _check(type(evidence) is list and all(type(ident) is str for ident in evidence))
    _check(len(evidence) <= MAX_REFERENCES and len(set(evidence)) == len(evidence))
    _check(set(evidence) <= {ref["id"] for ref in request["references"]})
    if status == "valid":
        _value(response["payload"], request["output_schema"])
        if "confidence" in response:
            confidence = response["confidence"]
            _check(type(confidence) in (int, float) and math.isfinite(confidence)
                   and 0 <= confidence <= 1)
    else:
        _check(response["payload"] is None and "confidence" not in response)
    return response


def _digest(request: dict) -> str:
    return hashlib.sha256(_encode(request).encode("utf-8")).hexdigest()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def judge(request: dict | str, adapter: JudgmentAdapter, *, provider: str, model: str) -> dict:
    """One adapter invocation; no retries, repair, selection, execution or writes.

    Caller errors raise JudgmentError. Completed invalid output and transport
    failures become closed records. Adapter exception text/raw output is dropped.
    """
    request = validate_request(request)
    _text(provider)
    _text(model)
    invocation = {"id": uuid.uuid4().hex, "provider": provider, "model": model}
    started_at = _now()
    try:
        raw = adapter(_copy(request))
    except ProviderUnavailable:
        status = "unavailable"
    except TimeoutError:
        status = "timeout"
    except Exception:  # noqa: BLE001 — adapter boundary; never retain exception text
        status = "provider_failure"
    else:
        try:
            response = _response(_copy(raw), request)
            status = response["status"]
        except (JudgmentError, TypeError, OverflowError, RecursionError):
            status = "invalid_output"
    if status not in {"valid", "abstain", "unknown"}:
        response = {"status": status, "payload": None, "evidence": [],
                    "reason": next(iter(REASONS[status]))}
    return {
        "contract": CONTRACT, "version": VERSION, "judgment_id": uuid.uuid4().hex,
        "kind": request["kind"], "kind_version": request["kind_version"],
        "input_provenance": {"request_digest": _digest(request),
                             "references": _copy(request["references"])},
        "invocation": invocation, **response,
        "started_at": started_at, "completed_at": _now(),
        "validation": VALIDATION[status],
    }


def validate_record(record: dict | str, request: dict | str) -> dict:
    """Inspect/revalidate a detached record against its kind/schema and inputs.

    Validation proves shape and binding, not factual truth or authenticity.
    """
    request = validate_request(request)
    record = _copy(record, record=True)
    _closed(record, {"contract", "version", "judgment_id", "kind", "kind_version",
                     "input_provenance", "invocation", "status", "payload", "evidence",
                     "reason", "started_at", "completed_at", "validation"}, {"confidence"})
    for key in ("contract", "version", "kind", "kind_version"):
        _check(type(record[key]) is type(request[key]) and record[key] == request[key])
    _check(type(record["judgment_id"]) is str
           and re.fullmatch(r"[0-9a-f]{32}", record["judgment_id"]) is not None)
    _check(record["input_provenance"] == {
        "request_digest": _digest(request), "references": request["references"]})
    _closed(record["invocation"], {"id", "provider", "model"})
    _check(type(record["invocation"]["id"]) is str
           and re.fullmatch(r"[0-9a-f]{32}", record["invocation"]["id"]) is not None)
    _text(record["invocation"]["provider"])
    _text(record["invocation"]["model"])
    _check(_timestamp(record["started_at"]) <= _timestamp(record["completed_at"]))
    status = record["status"]
    _check(type(status) is str and status in STATUSES)
    _check(record["validation"] == VALIDATION[status])
    if status in {"valid", "abstain", "unknown"}:
        _response({key: record[key] for key in ("status", "payload", "evidence", "reason", "confidence")
                   if key in record}, request)
    else:
        _check(record["payload"] is None and record["evidence"] == [] and "confidence" not in record)
        _check(type(record["reason"]) is str and record["reason"] in REASONS[status])
    return record


def payload_or_fallback(record: dict | str, request: dict | str, fallback: dict) -> dict:
    """Return validated reference payload or a detached deterministic default.

    The caller chooses its default before the model call. This helper executes
    nothing and never invokes another model. Even a valid payload has no authority.
    """
    request = validate_request(request)
    fallback = _copy(fallback)
    _value(fallback, request["output_schema"])
    try:
        record = validate_record(record, request)
    except (JudgmentError, TypeError, OverflowError, RecursionError):
        return fallback
    return record["payload"] if record["status"] == "valid" else fallback
