"""Canonical metadata attempts retain bounded structure and exact input fencing."""
import copy
import hashlib
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
from operational_history import HistoryError, OperationalHistory


def request(document):
    return {"capability_id": "core.deployments.adopt", "capability_version": 1,
            "provider": "core", "owner": "core", "inputs": {"proposal": document},
            "affected_objects": ["installation:local"], "safety": {"tier": "CHANGE"},
            "privilege": "none", "verification": {"kind": "deployment_metadata_revision", "required": True},
            "recovery": {"class": "reversible"}, "precondition_status": "satisfied"}


def test_history_preserves_structured_evidence_beyond_transcript_string_bound(tmp_path):
    evidence = {"action": "adopt", "inspection": {"mounts": [
        {"source": "/fixture/volume/" + str(i), "container": "a" * 64} for i in range(20)]}}
    document = json.dumps(evidence)
    assert len(document) > 1024
    history = OperationalHistory(tmp_path)
    proposal = request(document)
    row = history.prepare(proposal, correlation_id="fixture.attachment", approval_requirement="change_confirm",
                          provenance={"actor": "operator", "interface": "fixture", "request_id": None})
    assert row["inputs"]["proposal"] == evidence
    assert row["inputs"]["proposal_sha256"] == hashlib.sha256(document.encode()).hexdigest()
    assert row["inputs_redacted"] is False
    history.authority(row["operation_id"], "approved", "not_required")
    changed = copy.deepcopy(proposal)
    changed["inputs"]["proposal"] += " "
    with pytest.raises(HistoryError, match="differs from current approved"):
        history.running(row["operation_id"], changed)
    history.running(row["operation_id"], proposal)
    assert history.inspect(row["operation_id"])["lifecycle"] == "running"


def test_metadata_history_structure_keeps_existing_privacy_rules(tmp_path):
    history = OperationalHistory(tmp_path)
    proposal = request(json.dumps({"action": "adopt", "inspection": {"password": "NEVER_RETAIN", "env": ["SECRET"]}}))
    row = history.prepare(proposal, correlation_id="fixture.redaction", approval_requirement="change_confirm",
                          provenance={"actor": "operator", "interface": "fixture", "request_id": None})
    assert row["inputs_redacted"] is True
    assert "NEVER_RETAIN" not in json.dumps(row)
    assert row["inputs"]["proposal"]["inspection"]["env"] == "[REDACTED]"


@pytest.mark.parametrize("document", ['{"action":"adopt","action":"release"}', "[]", '{"bad":NaN}'])
def test_invalid_serialized_metadata_fails_closed(tmp_path, document):
    history = OperationalHistory(tmp_path)
    with pytest.raises(HistoryError):
        history.prepare(request(document), correlation_id="fixture.invalid", approval_requirement="change_confirm",
                        provenance={"actor": "operator", "interface": "fixture", "request_id": None})
