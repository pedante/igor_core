#!/usr/bin/env python3
"""Bounded semantic input-candidate contracts for Igor operator interfaces.

This module owns no machine truth and performs no host discovery by itself.
It validates selector metadata, registers trusted Core-side candidate sources,
normalizes ephemeral candidate results and exposes read-only resolver
inspection. Capability input validation, preconditions, approval, privilege,
execution and verification remain authoritative in their existing services.
"""

from __future__ import annotations

import copy
import re
from datetime import datetime, timezone
from typing import Any, Callable

CANDIDATE_API_VERSION = 1
SELECTOR_SCHEMA_VERSION = 1
MAX_CANDIDATES = 128
_SOURCE_ORDER = ("system_model", "platform")
_SOURCE_KINDS = set(_SOURCE_ORDER)
_STATES = {"ready", "empty", "unavailable", "error"}
_ID = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
_OBJECT_ID = re.compile(r"^[a-z][a-z0-9_-]*:[A-Za-z0-9_./:%+@-]+$")


class CandidateError(ValueError):
    """Malformed selector, source registration or candidate result."""


class CandidateSourceUnavailable(RuntimeError):
    """A registered source is currently unavailable without a contract error."""


class CandidateSourceError(RuntimeError):
    """A registered source failed while attempting a bounded read."""


def _error(message: str) -> CandidateError:
    return CandidateError(message)


def _bounded_text(value: Any, field: str, limit: int, *, required: bool = True) -> str | None:
    if value is None and not required:
        return None
    if (not isinstance(value, str) or (required and not value) or len(value) > limit or
            any(ord(char) < 32 for char in value)):
        raise _error(f"{field} must be bounded printable text")
    return value


def _timestamp(value: Any, field: str) -> str | None:
    if value is None:
        return None
    text = _bounded_text(value, field, 64)
    try:
        datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as exc:
        raise _error(f"{field} must be an ISO-8601 timestamp") from exc
    return text


def _now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def validate_selector(value: Any, *, input_type: str | None = None) -> dict[str, Any]:
    """Validate the bounded S1 resource-selector descriptor.

    S1 deliberately supports one semantic selector shape. More selector kinds
    are added only when a concrete later System domain proves the need.
    """
    if not isinstance(value, dict):
        raise _error("selector must be an object")
    if set(value) != {"schema_version", "kind", "resource_kind"}:
        raise _error("selector requires schema_version, kind and resource_kind")
    if type(value["schema_version"]) is not int or value["schema_version"] != SELECTOR_SCHEMA_VERSION:
        raise _error("selector.schema_version must be 1")
    if value["kind"] != "resource":
        raise _error("selector.kind must be resource")
    resource_kind = value["resource_kind"]
    if not isinstance(resource_kind, str) or not _ID.fullmatch(resource_kind):
        raise _error("selector.resource_kind must be a canonical lowercase identifier")
    if input_type is not None and input_type not in {"string", "object_id"}:
        raise _error("resource selector requires a string or object_id input")
    return copy.deepcopy(value)


def _candidate_rows(value: Any, limit: int) -> list[dict[str, Any]]:
    if not isinstance(value, list) or len(value) > limit:
        raise _error("candidates must be a bounded array")
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, raw in enumerate(value):
        if not isinstance(raw, dict) or set(raw) - {"value", "label", "detail", "object_id"}:
            raise _error(f"candidates[{index}] has invalid fields")
        candidate_value = _bounded_text(raw.get("value"), f"candidates[{index}].value", 512)
        if candidate_value in seen:
            raise _error("candidate values must be unique")
        seen.add(candidate_value)
        label = _bounded_text(raw.get("label", candidate_value), f"candidates[{index}].label", 160)
        detail = _bounded_text(raw.get("detail"), f"candidates[{index}].detail", 512, required=False)
        object_id = raw.get("object_id")
        if object_id is not None:
            if not isinstance(object_id, str) or not _OBJECT_ID.fullmatch(object_id):
                raise _error(f"candidates[{index}].object_id is invalid")
        row = {"value": candidate_value, "label": label}
        if detail is not None:
            row["detail"] = detail
        if object_id is not None:
            row["object_id"] = object_id
        result.append(row)
    return result


def _normalize_result(
    raw: Any,
    *,
    selector: dict[str, Any],
    source_kind: str,
    source_id: str,
    limit: int,
) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise _error("candidate resolver result must be an object")
    allowed = {"state", "candidates", "reason", "freshness", "recorded_at", "expires_at"}
    unknown = set(raw) - allowed
    if unknown:
        raise _error(f"candidate resolver result has unknown field {min(unknown)}")
    state = raw.get("state")
    if state not in _STATES:
        raise _error("candidate resolver state is invalid")
    rows = _candidate_rows(raw.get("candidates", []), limit)
    reason = raw.get("reason")
    if state == "ready" and not rows:
        raise _error("ready candidate result must contain candidates")
    if state == "empty" and rows:
        raise _error("empty candidate result cannot contain candidates")
    if state in {"unavailable", "error"}:
        if rows:
            raise _error("unavailable/error candidate result cannot contain candidates")
        reason = _bounded_text(reason, "candidate resolver reason", 240)
    elif reason is not None:
        raise _error("ready/empty candidate result cannot include a reason")

    recorded_at = _timestamp(raw.get("recorded_at"), "candidate source recorded_at")
    expires_at = _timestamp(raw.get("expires_at"), "candidate source expires_at")
    if source_kind == "system_model":
        freshness = raw.get("freshness")
        if freshness not in {"fresh", "stale"}:
            raise _error("system_model candidate result requires fresh/stale freshness")
        if freshness == "stale" and state in {"ready", "empty"}:
            state = "unavailable"
            rows = []
            reason = "system model candidate source is stale"
    else:
        if raw.get("freshness") not in {None, "not_applicable"}:
            raise _error("platform candidate freshness must be not_applicable")
        if recorded_at is not None or expires_at is not None:
            raise _error("platform candidate result cannot claim System Model timestamps")
        freshness = "not_applicable"

    source = {
        "kind": source_kind,
        "id": source_id,
        "freshness": freshness,
    }
    if recorded_at is not None:
        source["recorded_at"] = recorded_at
    if expires_at is not None:
        source["expires_at"] = expires_at

    return {
        "candidate_api_version": CANDIDATE_API_VERSION,
        "selector": copy.deepcopy(selector),
        "state": state,
        "source": source,
        "candidates": rows,
        "reason": reason,
        "resolved_at": _now(),
    }


class CandidateResolverRegistry:
    """Core-owned ordered registry of ephemeral candidate sources."""

    def __init__(self, *, max_candidates: int = MAX_CANDIDATES):
        if type(max_candidates) is not int or not 1 <= max_candidates <= MAX_CANDIDATES:
            raise _error("max_candidates is invalid")
        self._max_candidates = max_candidates
        self._sources: dict[tuple[str, str], tuple[str, Callable[[dict[str, Any]], Any]]] = {}

    def register(
        self,
        resource_kind: str,
        source_kind: str,
        source_id: str,
        resolver: Callable[[dict[str, Any]], Any],
    ) -> None:
        if not isinstance(resource_kind, str) or not _ID.fullmatch(resource_kind):
            raise _error("candidate resource_kind is invalid")
        if source_kind not in _SOURCE_KINDS:
            raise _error("candidate source_kind is invalid")
        if not isinstance(source_id, str) or not _ID.fullmatch(source_id):
            raise _error("candidate source_id is invalid")
        if not callable(resolver):
            raise _error("candidate resolver must be callable")
        key = (resource_kind, source_kind)
        if key in self._sources:
            raise _error("candidate source already registered")
        self._sources[key] = (source_id, resolver)

    def inspect(self, selector: Any, *, input_type: str | None = None) -> dict[str, Any]:
        normalized = validate_selector(selector, input_type=input_type)
        resource_kind = normalized["resource_kind"]
        sources = []
        for priority, source_kind in enumerate(_SOURCE_ORDER):
            registration = self._sources.get((resource_kind, source_kind))
            if registration is None:
                continue
            sources.append({
                "kind": source_kind,
                "id": registration[0],
                "priority": priority,
            })
        return {
            "candidate_api_version": CANDIDATE_API_VERSION,
            "selector": normalized,
            "state": "available" if sources else "unavailable",
            "sources": sources,
        }

    def resolve(self, selector: Any, *, input_type: str | None = None) -> dict[str, Any]:
        normalized = validate_selector(selector, input_type=input_type)
        resource_kind = normalized["resource_kind"]
        last: dict[str, Any] | None = None
        for source_kind in _SOURCE_ORDER:
            registration = self._sources.get((resource_kind, source_kind))
            if registration is None:
                continue
            source_id, resolver = registration
            try:
                raw = resolver(copy.deepcopy(normalized))
            except CandidateSourceUnavailable as exc:
                raw = {"state": "unavailable", "candidates": [], "reason": str(exc) or "source unavailable"}
                if source_kind == "system_model":
                    raw["freshness"] = "stale"
            except CandidateSourceError as exc:
                raw = {"state": "error", "candidates": [], "reason": str(exc) or "source error"}
                if source_kind == "system_model":
                    raw["freshness"] = "stale"
            result = _normalize_result(
                raw,
                selector=normalized,
                source_kind=source_kind,
                source_id=source_id,
                limit=self._max_candidates,
            )
            if result["state"] in {"ready", "empty"}:
                return result
            last = result
        if last is not None:
            return last
        return {
            "candidate_api_version": CANDIDATE_API_VERSION,
            "selector": normalized,
            "state": "unavailable",
            "source": None,
            "candidates": [],
            "reason": "no candidate source registered",
            "resolved_at": _now(),
        }
