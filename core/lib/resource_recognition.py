"""Private read-only domain recognition normalization (Gate A1, D077).

Trusted callers inject *reviewed* domain readers and current owner eligibility.
No automatic module loading, host probing, state storage or deployment adoption
is performed here. The output is ephemeral reference data, never authority.
This is intentionally NOT a public Module API v2 recognizer declaration.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

SCHEMA_VERSION = 1
MAX_CANDIDATES = 128
MAX_EVIDENCE = 16
MAX_MATCHED_OBJECTS = 16
MAX_ISSUES = 16
_IDENT = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
_DOMAIN = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$")
_SOURCE_KINDS = frozenset({"system_model", "platform", "provider"})
_FIELDS = frozenset({"candidate_version", "selector", "matched_objects", "evidence", "observed_at", "expires_at",
                     "ambiguities", "missing_evidence"})
_EVIDENCE_FIELDS = frozenset({"source_kind", "source_ref", "observed_at"})


class RecognitionError(ValueError):
    """A recognition declaration or untrusted candidate has an invalid shape."""


def _text(value: Any, field: str, limit: int = 256) -> str:
    if (not isinstance(value, str) or not value or len(value) > limit or
            any(not ch.isprintable() for ch in value)):
        raise RecognitionError(f"invalid {field}")
    return value


def _identifier(value: Any, field: str) -> str:
    value = _text(value, field, 128)
    if not _IDENT.fullmatch(value):
        raise RecognitionError(f"invalid {field}")
    return value


def _timestamp(value: Any, field: str) -> datetime:
    value = _text(value, field, 40)
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise RecognitionError(f"invalid {field}") from exc
    if result.tzinfo is None or result.utcoffset() is None:
        raise RecognitionError(f"invalid {field}")
    return result.astimezone(timezone.utc)


def _issues(value: Any, field: str) -> list[str]:
    if type(value) is not list or len(value) > MAX_ISSUES:
        raise RecognitionError(f"invalid {field}")
    issues = [_identifier(item, field) for item in value]
    if len(set(issues)) != len(issues):
        raise RecognitionError(f"duplicate {field}")
    return issues


@dataclass(frozen=True)
class Recognizer:
    """Trusted, session-scoped binding; active must come from the Core loader."""

    owner: str
    provider_id: str
    version: str
    domain_kind: str
    active: bool
    reader: Callable[[str | None], Sequence[Mapping[str, Any]]]

    def __post_init__(self) -> None:
        _identifier(self.owner, "owner")
        _identifier(self.provider_id, "provider_id")
        if not self.provider_id.startswith(self.owner + "."):
            raise RecognitionError("provider id is not owner-stamped")
        _text(self.version, "version", 64)
        if not _DOMAIN.fullmatch(_text(self.domain_kind, "domain_kind", 128)):
            raise RecognitionError("invalid domain_kind")
        if type(self.active) is not bool or not callable(self.reader):
            raise RecognitionError("invalid recognizer registration")


def normalize_candidates(
    binding: Recognizer, raw: Any, *, now: datetime | None = None,
    exact_locator: str | None = None,
) -> dict[str, Any]:
    """Validate provider reference data; never turn a user hint into machine truth.

    Readers may report *references* to facts, not raw facts, configuration
    contents, credentials or commands. A1 cannot certify arbitrary provider
    strings as nonsecret; A2 adapters must constrain their own selectors.
    """
    now = datetime.now(timezone.utc) if now is None else now
    if not isinstance(now, datetime):
        raise RecognitionError("now must be a datetime")
    if now.tzinfo is None or now.utcoffset() is None:
        raise RecognitionError("now must be timezone-aware")
    now = now.astimezone(timezone.utc)
    if exact_locator is not None:
        _text(exact_locator, "exact_locator")
    if type(raw) is not list or len(raw) > MAX_CANDIDATES:
        raise RecognitionError("invalid candidates")

    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw:
        if type(item) is not dict or set(item) != _FIELDS:
            raise RecognitionError("candidate has unknown or missing fields")
        if type(item["candidate_version"]) is not int or item["candidate_version"] != SCHEMA_VERSION:
            raise RecognitionError("unsupported candidate version")
        selector = _text(item["selector"], "selector")
        if selector in seen:
            raise RecognitionError("duplicate exact candidate selector")
        if exact_locator is not None and selector != exact_locator:
            raise RecognitionError("candidate does not match exact locator")
        seen.add(selector)
        objects = item["matched_objects"]
        if (type(objects) is not list or not objects or
                len(objects) > MAX_MATCHED_OBJECTS):
            raise RecognitionError("invalid matched_objects")
        matched_objects = [_text(obj, "matched_object") for obj in objects]
        if len(set(matched_objects)) != len(matched_objects):
            raise RecognitionError("duplicate matched object")
        evidence = item["evidence"]
        if type(evidence) is not list or not evidence or len(evidence) > MAX_EVIDENCE:
            raise RecognitionError("missing or excessive evidence")
        sources = []
        for ev in evidence:
            if type(ev) is not dict or set(ev) != _EVIDENCE_FIELDS:
                raise RecognitionError("invalid evidence fields")
            kind = _identifier(ev["source_kind"], "source_kind")
            if kind not in _SOURCE_KINDS:
                raise RecognitionError("unsupported evidence source kind")
            ref = _text(ev["source_ref"], "source_ref")
            seen_at = _timestamp(ev["observed_at"], "evidence.observed_at")
            if seen_at > now:
                raise RecognitionError("future evidence is not current")
            sources.append({"source_kind": kind, "source_ref": ref,
                            "observed_at": seen_at.isoformat()})
        observed = _timestamp(item["observed_at"], "observed_at")
        expires = _timestamp(item["expires_at"], "expires_at")
        if observed > now or expires <= observed or any(
                _timestamp(source["observed_at"], "evidence.observed_at") > observed
                for source in sources):
            raise RecognitionError("invalid candidate observation interval")
        ambiguities = _issues(item["ambiguities"], "ambiguities")
        missing = _issues(item["missing_evidence"], "missing_evidence")
        rows.append({
            "selector": selector, "matched_objects": matched_objects,
            "evidence": sources, "observed_at": observed.isoformat(),
            "expires_at": expires.isoformat(), "ambiguities": ambiguities,
            "missing_evidence": missing,
        })

    rows.sort(key=lambda row: row["selector"])
    for index, row in enumerate(rows, 1):
        row["candidate_id"] = f"candidate-{index}"  # result-local, never durable
        row["stale"] = _timestamp(row["expires_at"], "expires_at") <= now
    if not rows:
        status = "empty"
    elif any(row["stale"] for row in rows):
        status = "stale"
    elif any(row["missing_evidence"] for row in rows):
        status = "incomplete"
    elif len(rows) > 1 or any(row["ambiguities"] for row in rows):
        status = "ambiguous"
    else:
        status = "ready"
    return {
        "schema_version": SCHEMA_VERSION,
        "domain_kind": binding.domain_kind,
        "provider": {"owner": binding.owner, "id": binding.provider_id,
                     "version": binding.version},
        "status": status,
        "selection_required": status == "ambiguous",
        "candidates": rows,
    }


class RecognitionCoordinator:
    """Dispatch only pre-admitted, active domain readers; do not load modules."""

    def __init__(self, bindings: Iterable[Recognizer]):
        self._bindings: dict[str, Recognizer] = {}
        ids: set[str] = set()
        for binding in bindings:
            if not isinstance(binding, Recognizer):
                raise RecognitionError("untrusted provider registration shape")
            if binding.provider_id in ids or binding.domain_kind in self._bindings:
                raise RecognitionError("duplicate provider or ambiguous domain registration")
            ids.add(binding.provider_id)
            self._bindings[binding.domain_kind] = binding

    def discover(self, domain_kind: str, *, exact_locator: str | None = None,
                 now: datetime | None = None) -> dict[str, Any]:
        if not _DOMAIN.fullmatch(_text(domain_kind, "domain_kind", 128)):
            raise RecognitionError("invalid domain_kind")
        if exact_locator is not None:
            _text(exact_locator, "exact_locator")
        binding = self._bindings.get(domain_kind)
        if binding is None or not binding.active:
            return {"schema_version": SCHEMA_VERSION, "domain_kind": domain_kind,
                    "status": "unavailable", "reason": "provider_inactive_or_absent",
                    "candidates": [], "selection_required": False}
        try:
            raw = binding.reader(exact_locator)
        except Exception:  # noqa: BLE001 - sanitize all provider failures
            # Do not leak provider-returned exception strings (may contain secrets).
            return {"schema_version": SCHEMA_VERSION, "domain_kind": domain_kind,
                    "status": "error", "reason": "provider_read_failed",
                    "candidates": [], "selection_required": False}
        return normalize_candidates(binding, raw, now=now, exact_locator=exact_locator)
