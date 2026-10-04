#!/usr/bin/env python3
"""Read-only explainable baselines derived from canonical Operational History."""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any

from operational_history import HistoryError, OperationalHistory

VERSION = 1
MIN_SAMPLES = 3
MAX_LIMIT = 100
_CAPABILITY = re.compile(r"[a-z][a-z0-9_.-]{1,159}")


class BaselineError(ValueError):
    """Invalid baseline query or source data."""


def _timestamp(value: Any) -> datetime:
    if not isinstance(value, str):
        raise BaselineError("invalid history timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise BaselineError("invalid history timestamp") from exc
    if parsed.tzinfo is None:
        raise BaselineError("history timestamp is missing timezone")
    return parsed


def _elapsed_ms(start: Any, end: Any) -> int | None:
    if start is None or end is None:
        return None
    delta = (_timestamp(end) - _timestamp(start)).total_seconds()
    if delta < 0:
        raise BaselineError("history transition order is invalid")
    return round(delta * 1000)


def _transition_at(row: dict[str, Any], state: str) -> str | None:
    for transition in row.get("transitions", []):
        if transition.get("state") == state:
            return transition.get("at")
    return None


def _metric(values: list[int]) -> dict[str, int | float | None]:
    if not values:
        return {"samples": 0, "min_ms": None, "median_ms": None, "max_ms": None}
    middle = statistics.median(values)
    if isinstance(middle, float) and middle.is_integer():
        middle = int(middle)
    return {
        "samples": len(values),
        "min_ms": min(values),
        "median_ms": middle,
        "max_ms": max(values),
    }


def _counts(values: list[str]) -> dict[str, int]:
    return dict(sorted(Counter(values).items()))


def _validate_capability(value: Any) -> str:
    if type(value) is not str or not _CAPABILITY.fullmatch(value) or "." not in value:
        raise BaselineError("invalid capability identity")
    return value


def _group_key(row: dict[str, Any]) -> tuple[str, int, str, str]:
    return (
        row["capability"]["id"],
        row["capability"]["version"],
        row["provider"]["id"],
        row["provider"]["owner"],
    )


def _is_usable_terminal(row: dict[str, Any]) -> bool:
    outcome = row.get("outcome")
    return (
        row.get("lifecycle") == "terminal"
        and row.get("timestamps", {}).get("terminal_at") is not None
        and isinstance(outcome, str)
        and not outcome.startswith("interrupted_")
    )


def summarize_episodes(
    episodes: list[dict[str, Any]],
    *,
    scope_id: str,
    limit: int,
    capability_id: str | None = None,
) -> dict[str, Any]:
    """Build a deterministic, reference-only projection over recent history."""
    if type(limit) is not int or not 1 <= limit <= MAX_LIMIT:
        raise BaselineError(f"baseline limit must be 1..{MAX_LIMIT}")
    if capability_id is not None:
        _validate_capability(capability_id)

    groups: dict[tuple[str, int, str, str], list[dict[str, Any]]] = {}
    excluded_unfinished = 0
    excluded_interrupted = 0
    filtered_other_capability = 0

    for row in episodes:
        if capability_id is not None and row["capability"]["id"] != capability_id:
            filtered_other_capability += 1
            continue
        if row.get("outcome") in {"interrupted_before_execution", "interrupted_unknown"}:
            excluded_interrupted += 1
            continue
        if not _is_usable_terminal(row):
            excluded_unfinished += 1
            continue
        groups.setdefault(_group_key(row), []).append(row)

    baselines = []
    for key in sorted(groups):
        rows = sorted(
            groups[key],
            key=lambda row: (row["timestamps"]["admitted_at"], row["operation_id"]),
        )
        capability, version, provider, owner = key
        episode_elapsed: list[int] = []
        provider_elapsed: list[int] = []
        for row in rows:
            value = _elapsed_ms(row["timestamps"]["admitted_at"], row["timestamps"]["terminal_at"])
            if value is not None:
                episode_elapsed.append(value)
            running_at = _transition_at(row, "running")
            provider_complete_at = _transition_at(row, "provider_complete")
            value = _elapsed_ms(running_at, provider_complete_at)
            if value is not None:
                provider_elapsed.append(value)

        success_count = sum(row["outcome"] == "success" for row in rows)
        baselines.append(
            {
                "capability": {"id": capability, "version": version},
                "provider": {"id": provider, "owner": owner},
                "availability": "available" if len(rows) >= MIN_SAMPLES else "insufficient_history",
                "minimum_samples": MIN_SAMPLES,
                "sample_count": len(rows),
                "success_count": success_count,
                "success_fraction": round(success_count / len(rows), 3),
                "outcomes": _counts([row["outcome"] for row in rows]),
                "execution_statuses": _counts([row["execution_status"] for row in rows]),
                "verification_statuses": _counts([row["verification"]["status"] for row in rows]),
                "safety_tiers": _counts([row["safety_tier"] for row in rows]),
                "episode_elapsed_ms": _metric(episode_elapsed),
                "provider_elapsed_ms": _metric(provider_elapsed),
                "first_admitted_at": rows[0]["timestamps"]["admitted_at"],
                "last_admitted_at": rows[-1]["timestamps"]["admitted_at"],
                "evidence": {"operation_ids": [row["operation_id"] for row in rows]},
            }
        )

    return {
        "schema_version": VERSION,
        "authority": "reference_only",
        "availability": "available" if baselines else "insufficient_history",
        "source": {
            "kind": "operational_history",
            "scope_id": scope_id,
            "query_limit": limit,
            "episodes_seen": len(episodes),
            "episodes_used": sum(item["sample_count"] for item in baselines),
            "excluded_unfinished": excluded_unfinished,
            "excluded_interrupted": excluded_interrupted,
            "filtered_other_capability": filtered_other_capability,
        },
        "filter": {"capability_id": capability_id},
        "baselines": baselines,
    }


class OperationalBaselines:
    """Read-only Step 16 projection over the existing History authority."""

    def __init__(self, data_dir: Path):
        self._history = OperationalHistory(data_dir)

    def status(self) -> dict[str, Any]:
        history = self._history.status()
        return {
            "schema_version": VERSION,
            "authority": "reference_only",
            "availability": history["availability"],
            "source": {
                "kind": "operational_history",
                "scope_id": history["scope_id"],
                "episodes": history["episodes"],
            },
            "persistence": "none",
            "minimum_samples": MIN_SAMPLES,
            "max_query_limit": MAX_LIMIT,
        }

    def summarize(self, *, limit: int = MAX_LIMIT, capability_id: str | None = None) -> dict[str, Any]:
        if type(limit) is not int or not 1 <= limit <= MAX_LIMIT:
            raise BaselineError(f"baseline limit must be 1..{MAX_LIMIT}")
        if capability_id is not None:
            _validate_capability(capability_id)
        status = self._history.status()
        if status["availability"] != "available":
            return {
                "schema_version": VERSION,
                "authority": "reference_only",
                "availability": status["availability"],
                "source": {
                    "kind": "operational_history",
                    "scope_id": status["scope_id"],
                    "query_limit": limit,
                    "episodes_seen": 0,
                    "episodes_used": 0,
                    "excluded_unfinished": 0,
                    "excluded_interrupted": 0,
                    "filtered_other_capability": 0,
                },
                "filter": {"capability_id": capability_id},
                "baselines": [],
            }
        episodes = self._history.recent(limit=limit)
        return summarize_episodes(
            episodes,
            scope_id=status["scope_id"],
            limit=limit,
            capability_id=capability_id,
        )


def _decode_request() -> dict[str, Any]:
    body = sys.stdin.read()
    if not body:
        return {}
    try:
        value = json.loads(body)
    except json.JSONDecodeError as exc:
        raise BaselineError("baseline request must be valid JSON") from exc
    if type(value) is not dict:
        raise BaselineError("baseline request must be an object")
    return value


def _cli() -> int:
    parser = argparse.ArgumentParser(description="Igor explainable operational baseline projection")
    parser.add_argument("action", choices=["status", "list", "capability"])
    args = parser.parse_args()
    try:
        request = _decode_request()
        data_dir = request.pop("data_dir", None) or os.environ.get("IGOR_BASELINE_DATA_DIR")
        if not data_dir:
            raise BaselineError("baseline data directory is unavailable")
        service = OperationalBaselines(Path(data_dir))
        if args.action == "status":
            if request:
                raise BaselineError("status accepts no fields")
            result = service.status()
        elif args.action == "list":
            if set(request) - {"limit"}:
                raise BaselineError("list has unknown fields")
            result = service.summarize(limit=request.get("limit", MAX_LIMIT))
        else:
            if set(request) - {"capability_id", "limit"} or "capability_id" not in request:
                raise BaselineError("capability requires capability_id")
            result = service.summarize(
                limit=request.get("limit", MAX_LIMIT),
                capability_id=request["capability_id"],
            )
        print(json.dumps(result, sort_keys=True, separators=(",", ":"), allow_nan=False))
        return 0
    except (BaselineError, HistoryError, OSError, KeyError, TypeError) as exc:
        print(f"operational baselines unavailable: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(_cli())
