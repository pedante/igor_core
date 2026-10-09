"""Gate A1: no domain integrations or host IO, only trusted injected fixtures."""
from __future__ import annotations

import copy
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core/lib"))
from resource_recognition import (RecognitionCoordinator, RecognitionError,
                                  Recognizer, normalize_candidates)

NOW = datetime(2026, 10, 10, 12, tzinfo=timezone.utc)
T0 = "2026-10-10T11:50:00Z"
T1 = "2026-10-10T12:10:00Z"


def binding(reader=lambda locator: [], *, active=True, kind="nextcloud.application"):
    return Recognizer("nextcloud_docker", "nextcloud_docker.attachment", "1", kind, active, reader)


def candidate(selector="a" * 64, **changes):
    row = {"candidate_version": 1, "selector": selector, "matched_objects": ["container:" + selector],
           "evidence": [{"source_kind": "platform", "source_ref": "docker:daemon-fixture",
                         "observed_at": T0}],
           "observed_at": T0, "expires_at": T1,
           "ambiguities": [], "missing_evidence": []}
    row.update(changes)
    return row


def test_zero_one_multiple_are_distinct_and_never_first_match():
    assert normalize_candidates(binding(), [], now=NOW)["status"] == "empty"
    ready = normalize_candidates(binding(), [candidate()], now=NOW)
    assert ready["status"] == "ready" and not ready["selection_required"]
    multiple = normalize_candidates(binding(), [candidate("b"), candidate("a")], now=NOW)
    assert multiple["status"] == "ambiguous" and multiple["selection_required"]
    assert [row["selector"] for row in multiple["candidates"]] == ["a", "b"]
    assert [row["candidate_id"] for row in multiple["candidates"]] == ["candidate-1", "candidate-2"]


def test_no_raw_fields_or_secret_material_are_admitted():
    for field in ("secret", "raw_configuration", "approval", "command", "authorization", "desired_state"):
        with pytest.raises(RecognitionError, match="unknown or missing"):
            normalize_candidates(binding(), [candidate(**{field: "SENTINEL"})], now=NOW)
    bad = candidate(evidence=[{"source_kind": "platform", "source_ref": "docker:x", "observed_at": T0,
                               "headers": {"Authorization": "Bearer SENTINEL"}}])
    with pytest.raises(RecognitionError, match="evidence fields"):
        normalize_candidates(binding(), [bad], now=NOW)


def test_missing_evidence_ambiguity_and_staleness_fail_closed():
    assert normalize_candidates(binding(), [candidate(missing_evidence=["config_stat"])], now=NOW)["status"] == "incomplete"
    assert normalize_candidates(binding(), [candidate(ambiguities=["multiple_mounts"])], now=NOW)["status"] == "ambiguous"
    assert normalize_candidates(binding(), [candidate(expires_at="2026-10-10T11:55:00Z")], now=NOW)["status"] == "stale"
    assert normalize_candidates(binding(), [candidate()], now=NOW)["candidates"][0]["stale"] is False


@pytest.mark.parametrize("change", [
    {"candidate_version": 2},
    {"candidate_version": True},
    {"observed_at": "2026-10-10T12:30:00Z"},
    {"observed_at": "2026-10-10T11:50:00"},
    {"expires_at": T0},
    {"evidence": []},
    {"matched_objects": []},
    {"ambiguities": ["bad", "bad"]},
    {"evidence": [{"source_kind": "invalid", "source_ref": "x", "observed_at": T0}]},
])
def test_malformed_candidates_fail_closed(change):
    with pytest.raises(RecognitionError):
        normalize_candidates(binding(), [candidate(**change)], now=NOW)


def test_duplicate_selector_invalid_even_if_candidates_are_otherwise_valid():
    with pytest.raises(RecognitionError, match="duplicate exact"):
        normalize_candidates(binding(), [candidate(), candidate()], now=NOW)


def test_exact_locator_rejects_wrong_evidence_instead_of_guessing():
    wrong = candidate("other")
    with pytest.raises(RecognitionError, match="does not match"):
        normalize_candidates(binding(), [wrong], now=NOW, exact_locator="specific")


def test_inactive_or_missing_provider_is_not_called():
    def should_not_be_called(_locator):
        raise AssertionError("called inactive provider")
    coordinator = RecognitionCoordinator([binding(should_not_be_called, active=False)])
    assert coordinator.discover("nextcloud.application")["status"] == "unavailable"
    assert coordinator.discover("samba.share")["status"] == "unavailable"


def test_explicit_hint_is_selection_only_and_reader_controls_evidence():
    observed = []
    def read(locator):
        observed.append(locator)
        return [candidate(locator)] if locator == "exact" else []
    result = RecognitionCoordinator([binding(read)]).discover("nextcloud.application", exact_locator="exact", now=NOW)
    assert observed == ["exact"] and result["status"] == "ready"
    assert result["candidates"][0]["selector"] == "exact"
    assert RecognitionCoordinator([binding(lambda _hint: [])]).discover("nextcloud.application", exact_locator="unobserved")["status"] == "empty"


def test_provider_exceptions_are_sanitized_and_not_accepted():
    def bad(_hint):
        raise RuntimeError("Bearer SENTINEL")
    result = RecognitionCoordinator([binding(bad)]).discover("nextcloud.application")
    assert result["status"] == "error" and "SENTINEL" not in repr(result)


def test_bad_registration_and_ambiguous_domain_are_rejected():
    a = binding()
    with pytest.raises(RecognitionError, match="duplicate"):
        RecognitionCoordinator([a, a])
    b = Recognizer("samba", "samba.shares", "1", a.domain_kind, True, lambda _hint: [])
    with pytest.raises(RecognitionError, match="duplicate"):
        RecognitionCoordinator([a, b])
    with pytest.raises(RecognitionError):
        Recognizer("bad", "wrong", "1", "invalid", True, lambda _hint: [])
    with pytest.raises(RecognitionError, match="owner-stamped"):
        Recognizer("samba", "other.shares", "1", "samba.share", True, lambda _hint: [])


def test_no_aliases_or_changes_to_inputs():
    original = candidate()
    before = copy.deepcopy(original)
    result = normalize_candidates(binding(), [original], now=NOW)
    result["candidates"][0]["evidence"][0]["source_ref"] = "changed"
    assert original == before


def test_finite_bounds_and_unknown_status_cannot_be_forged():
    with pytest.raises(RecognitionError):
        normalize_candidates(binding(), [candidate(str(i)) for i in range(129)], now=NOW)
    with pytest.raises(RecognitionError):
        normalize_candidates(binding(), [{**candidate(), "status": "ready"}], now=NOW)
