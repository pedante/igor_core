"""Gate A3: common recognition view, not live scan/adoption/authority."""
from __future__ import annotations

import copy
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "core/lib"), str(ROOT / "core/ai")]

import tui
from recognition_view import (
    RecognitionViewError,
    project_recognition,
    text_lines,
    unavailable,
)
from resource_recognition import Recognizer, normalize_candidates

NOW = datetime(2026, 10, 10, 12, tzinfo=timezone.utc)


def raw_candidate(selector="share:media", *, stale=False, missing=(), ambiguity=()):
    return {
        "candidate_version": 1, "selector": selector,
        "matched_objects": [selector],
        "evidence": [{"source_kind": "provider", "source_ref": "samba:dev:1:inode:2:mtime:3:size:4",
                      "observed_at": "2026-10-10T11:50:00Z"}],
        "observed_at": "2026-10-10T11:50:00Z",
        "expires_at": "2026-10-10T11:55:00Z" if stale else "2026-10-10T12:10:00Z",
        "ambiguities": list(ambiguity), "missing_evidence": list(missing),
    }


def snapshot(*candidates):
    binding = Recognizer(
        "samba", "samba.shares", "1", "samba.share", True,
        lambda _hint: list(candidates),
    )
    return normalize_candidates(binding, list(candidates), now=NOW)


def test_ready_view_has_no_execution_authority():
    original = snapshot(raw_candidate())
    after = copy.deepcopy(original)
    view = project_recognition(original)
    assert view["view_version"] == 1
    assert view["kind"] == "recognition"
    assert view["state"] == "ready"
    assert view["authority"] == "reference_only"
    assert view["actions"] == []
    assert view["candidates"][0]["selector"] == "share:media"
    assert "Read-only candidates" in view["hint"]
    assert original == after


@pytest.mark.parametrize("raw,status", [
    ([], "empty"),
    ([raw_candidate()], "ready"),
    ([raw_candidate("share:a"), raw_candidate("share:b")], "ambiguous"),
    ([raw_candidate(stale=True)], "stale"),
    ([raw_candidate(missing=("source_missing",))], "incomplete"),
    ([raw_candidate(ambiguity=("shared_name",))], "ambiguous"),
])
def test_all_candidate_states_are_visible(raw, status):
    view = project_recognition(snapshot(*raw))
    assert view["state"] == status
    assert view["selection_required"] == (status == "ambiguous")
    assert "not adopted" in "\n".join(text_lines(view))


def test_unavailable_and_error_are_not_empty_success():
    for response in (
        {"schema_version": 1, "domain_kind": "samba.share",
         "status": "unavailable", "reason": "provider_inactive_or_absent",
         "candidates": [], "selection_required": False},
        {"schema_version": 1, "domain_kind": "samba.share",
         "status": "error", "reason": "provider_read_failed",
         "candidates": [], "selection_required": False},
    ):
        view = project_recognition(response)
        assert view["state"] in {"unavailable", "error"}
        assert "Reason:" in "\n".join(text_lines(view))
    assert unavailable()["state"] == "unavailable"


@pytest.mark.parametrize("addition", [
    {"capability": "core.deployments.adopt"},
    {"approval": True},
    {"secret": "SENTINEL"},
    {"commands": ["rm -rf /"]},
])
def test_unrecognized_authority_or_raw_text_fields_rejected(addition):
    raw = snapshot(raw_candidate())
    with pytest.raises(RecognitionViewError):
        project_recognition({**raw, **addition})


def test_malformed_provider_status_and_candidate_rejected():
    raw = snapshot(raw_candidate())
    with pytest.raises(RecognitionViewError):
        project_recognition({**raw, "status": "ready", "selection_required": True})
    with pytest.raises(RecognitionViewError):
        project_recognition({**raw, "provider": {"owner": "other", "id": "samba.shares", "version": "1"}})
    forged = copy.deepcopy(raw)
    forged["candidates"][0]["secret"] = "SENTINEL"
    with pytest.raises(RecognitionViewError):
        project_recognition(forged)


def test_cli_json_and_text_are_same_read_only_projection():
    sample = snapshot(raw_candidate("share:media"))
    json_result = subprocess.run(
        ["bash", str(ROOT / "igor.sh"), "--json", "recognition", "view"],
        input=json.dumps(sample), text=True, capture_output=True, timeout=8,
    )
    assert json_result.returncode == 0, json_result.stderr
    view = json.loads(json_result.stdout)
    assert view == project_recognition(sample)
    text_result = subprocess.run(
        ["bash", str(ROOT / "igor.sh"), "recognition", "view"],
        input=json.dumps(sample), text=True, capture_output=True, timeout=8,
    )
    assert text_result.returncode == 0, text_result.stderr
    assert text_result.stdout.strip().splitlines() == text_lines(view)
    assert "SENTINEL" not in repr(view)


def test_status_cli_is_explicitly_unavailable_without_provider():
    result = subprocess.run(["bash", str(ROOT / "igor.sh"), "--json", "recognition", "status"],
                            text=True, capture_output=True, timeout=8)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == unavailable()
    assert not json.loads(result.stdout)["candidates"]


def test_tui_panel_uses_same_cli_projection_and_has_no_capability():
    view = project_recognition(snapshot(raw_candidate("share:media")))
    inspector = tui.RecognitionInspection()
    assert inspector.command == ("--json", "recognition", "status")
    inspector.data = view
    sections = tui.panel_sections(tui.EventState(), tui.HistoryInspection(),
                                  recognition=inspector)
    selected = next(section for section in sections if section["id"] == "recognition")
    assert selected["data"] == view
    lines = tui.panel_rows(selected)
    assert lines[1:1 + len(text_lines(view))] == text_lines(view)
    assert "core.deployments.adopt" not in repr(selected)


def test_does_not_treat_corrupt_or_oversized_snapshot_as_success():
    invalid = subprocess.run(["bash", str(ROOT / "igor.sh"), "--json", "recognition", "view"],
                             input='{"secret":"SENTINEL"}', text=True, capture_output=True,
                             timeout=8)
    assert invalid.returncode != 0
    assert "SENTINEL" not in invalid.stdout + invalid.stderr
    oversized = subprocess.run(["bash", str(ROOT / "igor.sh"), "--json", "recognition", "view"],
                               input="x" * (262145), text=True, capture_output=True,
                               timeout=8)
    assert oversized.returncode != 0
