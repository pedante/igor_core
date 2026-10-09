"""Shared read-only projection for A1 recognition candidate snapshots (Gate A3).

CLI and TUI consume the same validated model. This module never loads a
recognizer, probes the host, persists candidates, or creates executable actions.
An inbound JSON snapshot is reference data, not evidence of approved adoption.
"""
from __future__ import annotations

import json
import re
import sys
from typing import Any

MAX_INPUT = 262_144
MAX_CANDIDATES = 128
_TEXT = re.compile(r"^[^\x00-\x1f\x7f]+$")
_PROVIDER = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
_SELECTOR = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/+-]{0,255}$")
_STATES = frozenset({"empty", "ready", "ambiguous", "stale", "incomplete", "unavailable", "error"})
_TOP = frozenset({"schema_version", "domain_kind", "provider", "status",
                  "selection_required", "candidates"})
_CANDIDATE = frozenset({"candidate_id", "selector", "matched_objects", "evidence",
                        "observed_at", "expires_at", "ambiguities", "missing_evidence", "stale"})
_EVIDENCE = frozenset({"source_kind", "source_ref", "observed_at"})
_ISSUE = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")


class RecognitionViewError(ValueError):
    """A snapshot is not a valid, bounded read-only recognition projection."""


def _text(value: Any, *, limit: int = 256) -> str:
    if not isinstance(value, str) or not value or len(value) > limit or not _TEXT.fullmatch(value):
        raise RecognitionViewError("invalid recognition reference")
    return value


def _codes(value: Any) -> list[str]:
    if type(value) is not list or len(value) > 16:
        raise RecognitionViewError("invalid issue list")
    codes = [_text(item, limit=128) for item in value]
    if any(not _ISSUE.fullmatch(item) for item in codes) or len(codes) != len(set(codes)):
        raise RecognitionViewError("invalid issue code")
    return codes


def project_recognition(snapshot: Any) -> dict[str, Any]:
    """Return a strict non-authorizing, stable model for both frontends.

    Only already-normalized candidates from a trusted A1/A2 integration should
    be supplied as an operational snapshot. This gate does not implement that
    binding or trust the caller to establish it.
    """
    if type(snapshot) is not dict:
        raise RecognitionViewError("invalid recognition snapshot")
    status = snapshot.get("status")
    if type(status) is not str or status not in _STATES or type(snapshot.get("schema_version")) is not int or snapshot["schema_version"] != 1:
        raise RecognitionViewError("unsupported recognition snapshot")
    allowed = set(_TOP)
    if status in {"unavailable", "error"}:
        allowed.add("reason")
        allowed.discard("provider")  # A1 intentionally omits absent providers
    fields = set(snapshot)
    if fields != allowed and not (status in {"unavailable", "error"} and fields == allowed | {"provider"}):
        raise RecognitionViewError("unexpected recognition fields")
    domain = _text(snapshot.get("domain_kind"), limit=128)
    if not re.fullmatch(r"[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+", domain):
        raise RecognitionViewError("invalid recognition domain")
    provider = snapshot.get("provider")
    if status in {"unavailable", "error"}:
        if provider is not None or snapshot.get("reason") not in {
            "provider_inactive_or_absent", "provider_read_failed"
        }:
            raise RecognitionViewError("invalid unavailable recognition source")
    elif (type(provider) is not dict or set(provider) != {"owner", "id", "version"} or
          not _PROVIDER.fullmatch(_text(provider["owner"], limit=128)) or
          not _PROVIDER.fullmatch(_text(provider["id"], limit=128)) or
          not provider["id"].startswith(provider["owner"] + ".")):
        raise RecognitionViewError("invalid recognition provider")
    if provider is not None:
        _text(provider["version"], limit=64)
    if type(snapshot.get("selection_required")) is not bool:
        raise RecognitionViewError("invalid selection marker")
    raw = snapshot.get("candidates")
    if type(raw) is not list or len(raw) > MAX_CANDIDATES:
        raise RecognitionViewError("invalid candidate collection")
    rows = []
    seen = set()
    for item in raw:
        if type(item) is not dict or set(item) != _CANDIDATE:
            raise RecognitionViewError("unexpected candidate fields")
        ident = _text(item["candidate_id"], limit=32)
        selector = _text(item["selector"])
        if not _SELECTOR.fullmatch(selector):
            raise RecognitionViewError("unsupported exact candidate selector")
        if ident in seen or selector in seen:
            raise RecognitionViewError("duplicate recognition identity")
        seen.update((ident, selector))
        if type(item["stale"]) is not bool:
            raise RecognitionViewError("invalid freshness marker")
        matched = item["matched_objects"]
        evidence = item["evidence"]
        if (type(matched) is not list or not 1 <= len(matched) <= 16 or
                type(evidence) is not list or not 1 <= len(evidence) <= 16):
            raise RecognitionViewError("invalid candidate references")
        for obj in matched:
            _text(obj)
        for source in evidence:
            if type(source) is not dict or set(source) != _EVIDENCE:
                raise RecognitionViewError("invalid evidence reference")
            _text(source["source_kind"], limit=128)
            _text(source["source_ref"])
            _text(source["observed_at"], limit=40)
        _text(item["observed_at"], limit=40)
        _text(item["expires_at"], limit=40)
        ambiguity = _codes(item["ambiguities"])
        missing = _codes(item["missing_evidence"])
        row_state = ("stale" if item["stale"] else
                     "incomplete" if missing else
                     "ambiguous" if ambiguity else "ready")
        # Display only bounded references and counts; never opaque raw provider
        # records, configuration contents, approval claims or commands.
        rows.append({
            "candidate_id": ident,
            "selector": selector,
            "state": row_state,
            "matched_object_count": len(matched),
            "evidence_sources": [e["source_kind"] for e in evidence],
            "ambiguities": ambiguity,
            "missing_evidence": missing,
        })
    if status in {"unavailable", "error"}:
        if rows:
            raise RecognitionViewError("unavailable provider cannot yield candidates")
    else:
        expected = (
            "empty" if not rows else
            "stale" if any(row["state"] == "stale" for row in rows) else
            "incomplete" if any(row["missing_evidence"] for row in rows) else
            "ambiguous" if len(rows) > 1 or any(row["ambiguities"] for row in rows) else
            "ready"
        )
        if status != expected:
            raise RecognitionViewError("inconsistent recognition status")
    if snapshot["selection_required"] != (status == "ambiguous"):
        raise RecognitionViewError("inconsistent recognition selection")
    if status == "empty" and provider is None:
        raise RecognitionViewError("empty recognition requires an active provider")
    # A1 treats candidate state as observational. Presentation cannot confer
    # operational authority, regardless of apparent readiness.
    return {
        "view_version": 1,
        "kind": "recognition",
        "domain_kind": domain,
        "provider": provider,
        "state": status,
        "reason": snapshot.get("reason"),
        "selection_required": snapshot["selection_required"],
        "candidates": rows,
        "authority": "reference_only",
        "actions": [],
        "hint": "Read-only candidates; selection is not adoption or execution",
    }


def unavailable(domain: str = "recognition.pending") -> dict[str, Any]:
    """Honest front-end state before a trusted domain snapshot exists."""
    return project_recognition({
        "schema_version": 1, "domain_kind": domain, "provider": None,
        "status": "unavailable", "reason": "provider_inactive_or_absent",
        "selection_required": False, "candidates": [],
    })


def text_lines(view: dict[str, Any]) -> list[str]:
    """Use exactly the same validated projection as the structured CLI/TUI."""
    if view.get("kind") != "recognition" or view.get("authority") != "reference_only":
        raise RecognitionViewError("invalid recognition view")
    lines = [f"Recognition: {view['domain_kind']} [{view['state']}]",
             f"Authority: {view['authority']} · candidates are not adopted"]
    if view.get("reason"):
        lines.append("Reason: " + view["reason"])
    for candidate in view.get("candidates", []):
        lines.append(f"- {candidate['selector']} [{candidate['state']}] "
                     f"evidence={len(candidate['evidence_sources'])}")
        if candidate["ambiguities"]:
            lines.append("  Ambiguous: " + ", ".join(candidate["ambiguities"]))
        if candidate["missing_evidence"]:
            lines.append("  Missing: " + ", ".join(candidate["missing_evidence"]))
    if view.get("selection_required"):
        lines.append("Exact selection required; never choose the first candidate")
    return lines


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in {"status", "view", "status-text", "view-text"}:
        print("usage: recognition_view.py {status|view|status-text|view-text}", file=sys.stderr)
        return 2
    try:
        if argv[1].startswith("status"):
            result = unavailable()
        else:
            raw = sys.stdin.buffer.read(MAX_INPUT + 1)
            if len(raw) > MAX_INPUT:
                raise RecognitionViewError("recognition snapshot exceeds size limit")
            result = project_recognition(json.loads(raw.decode("utf-8")))
        if argv[1].endswith("-text"):
            print("\n".join(text_lines(result)))
        else:
            print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 0
    except (RecognitionViewError, ValueError, UnicodeError, TypeError):
        print("recognition view: invalid or unavailable snapshot", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
