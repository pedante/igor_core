"""Local Learning evidence, review, authority and persistence contract proofs."""

import concurrent.futures
import copy
import json
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))

from investigations import InvestigationService
from local_learning import (
    LearningError,
    LocalLearningService,
    validate_candidate,
    validate_learning,
)
from operational_history import OperationalHistory


def operation(data, *, version=1, owner="system", provider="fixture.read", objects=None,
              outcome="failed", execution="failed", verification="failed", finish=True, inputs=None):
    history = OperationalHistory(data)
    proposal = {"capability_id": "system.fixture.read", "capability_version": version,
                "provider": provider, "owner": owner, "inputs": inputs or {},
                "safety": {"tier": "READ"}, "privilege": "none", "precondition_status": "satisfied",
                "verification": {"kind": "none", "required": False},
                "recovery": {"class": "not_applicable"}, "affected_objects": objects or ["host:local"]}
    row = history.prepare(proposal, correlation_id="learning-fixture",
                          provenance={"actor": "operator", "interface": "fixture", "request_id": None})
    history.authority(row["operation_id"], "not_required", "not_required")
    history.running(row["operation_id"])
    if finish:
        history.provider_complete(row["operation_id"], execution)
        history.finish(row["operation_id"], {"operation_id": row["operation_id"],
            "capability_id": proposal["capability_id"], "capability_version": version,
            "provider": provider, "owner": owner, "safety": proposal["safety"], "privilege": "none",
            "affected_objects": proposal["affected_objects"], "precondition_status": "satisfied",
            "execution_status": execution, "outcome": outcome, "approval_status": "not_required",
            "privilege_status": "not_required", "verification_status": verification,
            "verification_evidence": [{"source": "fixture", "observed": "failed"}]})
    return row["operation_id"]


def repeated(data, **kwargs):
    return [operation(data, **kwargs) for _ in range(3)]


def resolved(data, operation_id=None, *, finding="Provider failure recurred; cause remains unknown"):
    service = InvestigationService(data)
    row = service.create(title="Understand provider failure", summary="Resolution assessed by operator",
                         source="operator", owner="operator",
                         provenance={"source": "operator.cli", "recorded_at": "2026-10-01T12:00:00Z"})
    ident = row["investigation_id"]
    if operation_id:
        service.add_evidence(ident, {"id": "observed-operation", "kind": "operation",
            "scope_id": row["scope_id"], "target": operation_id, "source": "operational_history",
            "recorded_at": "2026-10-01T12:00:00Z", "availability": "available"})
    service.set_findings(ident, [finding])
    service.set_questions(ident, ["What caused this failure?"])
    service.transition(ident, "evaluating", "Evidence considered")
    return service.transition(ident, "resolved", "Finding assessed; cause still uncertain")


def resolved_typed(data, operation_id, *, kind="cause", status="supported",
                   statement="Storage exhaustion caused the retained failure"):
    service = InvestigationService(data)
    row = service.create(title="Typed provider investigation", summary="Typed evidence retained",
                         source="operator", owner="operator",
                         provenance={"source": "operator.cli", "recorded_at": "2026-10-01T12:00:00Z"})
    ident = row["investigation_id"]
    evidence_kind = "verification" if kind == "verification" else "operation"
    service.add_evidence(ident, {"id": "typed-support", "kind": evidence_kind,
        "scope_id": row["scope_id"], "target": operation_id, "source": "operational_history",
        "recorded_at": "2026-10-01T12:00:00Z", "availability": "available"})
    fields = {"investigation_id": ident, "kind": kind, "statement": statement, "status": status}
    if status == "supported":
        fields["supporting_evidence"] = ["typed-support"]
    elif status == "contradicted":
        fields["contradicting_evidence"] = ["typed-support"]
    typed = service.add_typed_finding(**fields)
    finding_id = typed["typed_findings"][0]["finding_id"]
    service.set_questions(ident, ["Does this recur outside this incident?"])
    service.transition(ident, "evaluating", "Typed evidence considered")
    resolved_row = service.transition(ident, "resolved", "Typed finding retained as reference")
    return resolved_row, finding_id


def choose(service, kind="recurring_outcome", **kwargs):
    return next(row for row in service.candidates(**kwargs)["candidates"] if row["learning_type"] == kind)


def review(service, candidate, status="accepted", **changes):
    state = service.status()
    fields = {"candidate_id": candidate["candidate_id"], "candidate_revision": candidate["candidate_revision"],
              "status": status, "expected_revision": state["revision"], "expected_state": state["state_token"],
              "actor": "operator", "interface": "operator.cli", "reason": "Explicit reference review"}
    fields.update(changes)
    return service.review(**fields)


def cas(service):
    state = service.status()
    return {"expected_revision": state["revision"], "expected_state": state["state_token"]}


def snapshot(data):
    return {str(p.relative_to(data)): (p.read_bytes(), p.stat().st_mode, p.stat().st_mtime_ns)
            for p in data.rglob("*") if p.is_file()}


def source_snapshot(data):
    return {name: value for name, value in snapshot(data).items()
            if name.startswith(("operational_history/", "investigations/"))}


def test_empty_read_only_inspection_never_allocates_identity_or_store(tmp_path):
    data = tmp_path / "absent"
    service = LocalLearningService(data)
    assert service.status()["availability"] == "not_created"
    assert service.candidates()["candidates"] == []
    assert service.list() == []
    assert not data.exists()


def test_sufficient_evidence_is_deterministic_traceable_and_noncausal(tmp_path):
    ids = repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    before = source_snapshot(tmp_path)
    first, second = service.candidates(), service.candidates()
    assert first == second
    candidate = choose(service)
    assert candidate["counts"]["operations"] == 3
    assert candidate["counts"]["minimum_samples"] == 3
    refs = [ref["operation_id"] for ref in candidate["evidence"] if ref["kind"] == "operational_history"]
    assert set(refs) == set(ids)
    assert candidate["owner"] == "core" and candidate["applicability_owners"] == ["system"]
    assert candidate["authority"] == "reference_only"
    assert "cause" not in candidate and "procedure" not in candidate
    assert "disk" not in candidate["statement"].lower()
    assert any(ref["kind"] == "baseline" for ref in candidate["evidence"])
    assert source_snapshot(tmp_path) == before
    assert not (tmp_path / "local_learning").exists()


def test_insufficient_evidence_and_unfinished_are_not_invented(tmp_path):
    operation(tmp_path)
    operation(tmp_path)
    operation(tmp_path, finish=False)
    service = LocalLearningService(tmp_path)
    assert service.candidates()["candidates"] == []


@pytest.mark.parametrize("change", [
    {"version": 2}, {"owner": "other"}, {"provider": "other.read"},
    {"objects": ["service:systemd:sshd.service"]},
    {"outcome": "unverified_change", "execution": "succeeded", "verification": "unknown"},
    {"execution": "succeeded"}, {"verification": "unknown"},
])
def test_incompatible_evidence_is_never_combined(tmp_path, change):
    operation(tmp_path)
    operation(tmp_path)
    operation(tmp_path, **change)
    assert LocalLearningService(tmp_path).candidates()["candidates"] == []


def test_exact_object_set_is_order_independent(tmp_path):
    objects = ["host:local", "service:systemd:sshd.service"]
    operation(tmp_path, objects=objects)
    operation(tmp_path, objects=list(reversed(objects)))
    operation(tmp_path, objects=objects)
    assert choose(LocalLearningService(tmp_path))["counts"]["operations"] == 3


def test_failed_execution_and_verification_remain_distinct_candidates(tmp_path):
    repeated(tmp_path)
    repeated(tmp_path, execution="succeeded")
    service = LocalLearningService(tmp_path)
    candidates = service.candidates()["candidates"]
    assert len(candidates) == 2
    assert all(row["counts"]["operations"] == 3 for row in candidates)
    assert len({row["candidate_id"] for row in candidates}) == 2


def test_dead_owner_interruption_is_excluded_without_source_writes(tmp_path):
    ids = repeated(tmp_path)
    code = "import sys; sys.path.insert(0,sys.argv[1]); from test_local_learning import operation; from pathlib import Path; operation(Path(sys.argv[2]),finish=False)"
    subprocess.run([sys.executable, "-c", code, str(ROOT / "tests"), str(tmp_path)], check=True)
    service = LocalLearningService(tmp_path)
    before = source_snapshot(tmp_path)
    candidate = choose(service)
    assert candidate["counts"]["operations"] == len(ids)
    assert source_snapshot(tmp_path) == before


def test_history_window_is_bounded_and_filter_inside_window(tmp_path):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    assert service.candidates(limit=2)["candidates"] == []
    assert service.candidates(capability_id="system.unrelated.read")["candidates"] == []
    for limit in (0, 101, True, "100"):
        with pytest.raises(LearningError):
            service.candidates(limit=limit)


def test_investigation_finding_is_attributed_not_verified_repair(tmp_path):
    ident = operation(tmp_path)
    inv = resolved(tmp_path, ident)
    service = LocalLearningService(tmp_path)
    before = source_snapshot(tmp_path)
    candidate = choose(service, "investigation_finding")
    assert inv["findings"][0] in candidate["statement"]
    refs = candidate["evidence"]
    assert any(r.get("investigation_id") == inv["investigation_id"] for r in refs)
    assert any(r.get("operation_id") == ident for r in refs)
    assert candidate["counts"]["investigations"] == 1
    assert "What caused this failure?" in json.dumps(candidate["uncertainty"])
    assert candidate["capability"] is None and candidate["provider"] is None
    assert candidate["compatibility"][0]["capability"]["version"] == 1
    assert "cause" not in candidate and "procedure" not in candidate
    assert source_snapshot(tmp_path) == before


def test_supported_typed_finding_becomes_distinct_reviewable_reference(tmp_path):
    operation_id = operation(tmp_path)
    investigation, finding_id = resolved_typed(tmp_path, operation_id)
    service = LocalLearningService(tmp_path)
    before = source_snapshot(tmp_path)
    candidate = choose(service, "typed_investigation_finding")

    assert candidate["provenance"]["derivation_version"] == 2
    assert candidate["counts"] == {
        "operations": 1, "investigations": 1, "baselines": 0, "minimum_samples": 1}
    typed_ref = next(ref for ref in candidate["evidence"]
                     if ref["kind"] == "investigation_typed_finding")
    assert typed_ref["investigation_id"] == investigation["investigation_id"]
    assert typed_ref["finding_id"] == finding_id
    assert typed_ref["finding_kind"] == "cause"
    assert any(ref.get("operation_id") == operation_id for ref in candidate["evidence"])
    assert "supports cause finding" in candidate["statement"]
    assert "reusable causal rule" in " ".join(candidate["uncertainty"])
    assert candidate["authority"] == "reference_only"
    assert candidate["capability"] is None and candidate["provider"] is None
    assert "procedure" not in candidate
    assert source_snapshot(tmp_path) == before


@pytest.mark.parametrize("status", ["inconclusive", "contradicted"])
def test_non_supported_typed_findings_are_not_learning_candidates(tmp_path, status):
    operation_id = operation(tmp_path)
    _investigation, finding_id = resolved_typed(
        tmp_path, operation_id, status=status, statement="Typed claim remains unresolved")
    result = LocalLearningService(tmp_path).candidates()
    assert not any(row["learning_type"] == "typed_investigation_finding"
                   for row in result["candidates"])
    assert any(item["source"] == finding_id and item["reason"] == "typed_finding_not_supported"
               for item in result["omitted"])


def test_typed_finding_identity_uses_stable_finding_id_and_stale_review_is_refused(tmp_path):
    operation_id = operation(tmp_path)
    investigation, finding_id = resolved_typed(tmp_path, operation_id)
    service = LocalLearningService(tmp_path)
    candidate = choose(service, "typed_investigation_finding")
    typed_ref = next(ref for ref in candidate["evidence"]
                     if ref["kind"] == "investigation_typed_finding")
    assert typed_ref["finding_id"] == finding_id

    InvestigationService(tmp_path).reopen(investigation["investigation_id"], "Reassess typed evidence")
    with pytest.raises(LearningError):
        review(service, candidate)
    assert service.list() == []


def test_typed_learning_evidence_status_detects_reopen_without_rewriting_snapshot(tmp_path):
    operation_id = operation(tmp_path)
    investigation, _finding_id = resolved_typed(tmp_path, operation_id)
    service = LocalLearningService(tmp_path)
    accepted = review(service, choose(service, "typed_investigation_finding"))
    frozen = copy.deepcopy(accepted)
    InvestigationService(tmp_path).reopen(investigation["investigation_id"], "New evidence expected")

    before = snapshot(tmp_path)
    status = service.evidence_status(accepted["learning_id"])
    typed = next(item for item in status["evidence"]
                 if item["reference"]["kind"] == "investigation_typed_finding")
    assert typed["status"] == "changed"
    assert service.inspect(accepted["learning_id"]) == frozen
    assert snapshot(tmp_path) == before


def test_legacy_and_typed_investigation_candidates_coexist_without_rewriting_identity(tmp_path):
    operation_id = operation(tmp_path)
    legacy = resolved(tmp_path, operation_id)
    service = LocalLearningService(tmp_path)
    legacy_candidate = choose(service, "investigation_finding")
    assert legacy_candidate["provenance"]["derivation_version"] == 1

    typed_investigation, _ = resolved_typed(tmp_path, operation_id)
    candidates = service.candidates()["candidates"]
    refreshed_legacy = next(row for row in candidates
                            if row["learning_type"] == "investigation_finding"
                            and any(ref.get("investigation_id") == legacy["investigation_id"]
                                    for ref in row["evidence"]))
    typed_candidate = next(row for row in candidates
                           if row["learning_type"] == "typed_investigation_finding"
                           and any(ref.get("investigation_id") == typed_investigation["investigation_id"]
                                   for ref in row["evidence"]))
    assert refreshed_legacy["candidate_id"] == legacy_candidate["candidate_id"]
    assert refreshed_legacy["provenance"]["derivation_version"] == 1
    assert typed_candidate["candidate_id"] != refreshed_legacy["candidate_id"]


@pytest.mark.parametrize("source", ["missing", "unfinished", "no_history", "reopened"])
def test_missing_or_ineligible_investigation_evidence_surfaces_safely(tmp_path, source):
    ident = "op-" + "a" * 32 if source == "missing" else None
    if source in {"unfinished", "reopened"}:
        ident = operation(tmp_path, finish=source != "unfinished")
    inv = resolved(tmp_path, ident)
    if source == "reopened":
        InvestigationService(tmp_path).reopen(inv["investigation_id"], "Need more evidence")
    result = LocalLearningService(tmp_path).candidates()
    assert not any(row["learning_type"] == "investigation_finding" for row in result["candidates"])
    if source != "reopened":
        assert result["omitted"]


@pytest.mark.parametrize("status", ["accepted", "rejected", "superseded"])
def test_explicit_review_freezes_snapshot_and_survives_reopen(tmp_path, status):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    candidate = choose(service)
    before = source_snapshot(tmp_path)
    row = review(service, candidate, status)
    assert row["candidate"] == candidate and row["status"] == status
    assert row["review"]["actor"] == "operator"
    assert row["review"]["interface"] == "operator.cli"
    assert row["authority"] == "reference_only"
    assert LocalLearningService(tmp_path).inspect(row["learning_id"]) == row
    assert service.list(status=status) == [row]
    assert source_snapshot(tmp_path) == before
    assert (tmp_path / "local_learning").stat().st_mode & 0o777 == 0o700
    assert (tmp_path / "local_learning/store.json").stat().st_mode & 0o777 == 0o600
    with pytest.raises(LearningError):
        review(service, candidate, status)


def test_new_evidence_requires_new_review_and_never_edits_accepted(tmp_path):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    old = choose(service)
    accepted = review(service, old)
    operation(tmp_path)
    new = choose(service)
    assert old["candidate_id"] == new["candidate_id"]
    assert old["candidate_revision"] != new["candidate_revision"]
    assert service.inspect(accepted["learning_id"]) == accepted
    with pytest.raises(LearningError):
        review(service, old)
    revised = review(service, new)
    assert revised["learning_id"] != accepted["learning_id"]
    assert service.inspect(accepted["learning_id"])["status"] == "accepted"


def test_investigation_reopen_changes_revision_and_prevents_stale_acceptance(tmp_path):
    inv = resolved(tmp_path, operation(tmp_path))
    service = LocalLearningService(tmp_path)
    old = choose(service, "investigation_finding")
    InvestigationService(tmp_path).reopen(inv["investigation_id"], "Finding needs reassessment")
    with pytest.raises(LearningError):
        review(service, old)
    assert service.list() == []


def test_supersession_is_explicit_and_terminal(tmp_path):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    row = review(service, choose(service))
    frozen = copy.deepcopy(row["candidate"])
    result = service.supersede(row["learning_id"], **cas(service), actor="operator", interface="operator.cli", reason="No longer applicable")
    assert result["status"] == "superseded" and result["candidate"] == frozen
    assert result["transitions"][-1]["from"] == "accepted"
    with pytest.raises(LearningError):
        service.supersede(row["learning_id"], **cas(service), actor="operator", interface="operator.cli", reason="Again")


@pytest.mark.parametrize("status", ["candidate", "automatic", "", True])
def test_invalid_review_transition_is_refused(tmp_path, status):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    with pytest.raises(LearningError):
        review(service, choose(service), status)
    assert service.list() == []


def test_stale_store_state_and_fabricated_ids_are_refused(tmp_path):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    candidate = choose(service)
    before = cas(service)
    review(service, candidate, "rejected")
    operation(tmp_path)
    with pytest.raises(LearningError):
        review(service, choose(service), **before)
    with pytest.raises(LearningError):
        review(service, candidate, candidate_id="lc-" + "f" * 64)
    with pytest.raises(LearningError):
        review(service, candidate, candidate_revision="0" * 64)


def test_source_pruning_retains_frozen_learning_and_blocks_new_acceptance(tmp_path):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    candidate = choose(service)
    accepted = review(service, candidate)
    history = OperationalHistory(tmp_path)
    scope = history.status()["scope_id"]
    history.reset()
    assert history.status()["scope_id"] == scope
    assert service.inspect(accepted["learning_id"]) == accepted
    assert service.candidates()["candidates"] == []
    before = snapshot(tmp_path)
    status = service.evidence_status(accepted["learning_id"])
    assert all(ref["status"] == "missing" for ref in status["evidence"])
    assert snapshot(tmp_path) == before
    with pytest.raises(LearningError):
        review(service, candidate)


def test_delete_reset_invalidate_old_tokens_and_preserve_source_authorities(tmp_path):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    accepted = review(service, choose(service))
    before_sources = source_snapshot(tmp_path)
    old = cas(service)
    service.delete(accepted["learning_id"], **old)
    with pytest.raises(LearningError):
        service.inspect(accepted["learning_id"])
    with pytest.raises(LearningError):
        review(service, choose(service), **old)
    review(service, choose(service))
    before_reset = cas(service)
    service.reset(**before_reset)
    assert service.list() == []
    assert cas(service) != before_reset
    assert source_snapshot(tmp_path) == before_sources


def test_export_restore_is_validated_idempotent_and_scope_safe(tmp_path):
    original = tmp_path / "original"
    repeated(original)
    service = LocalLearningService(original)
    accepted = review(service, choose(service))
    export = service.export()
    before = snapshot(original)
    assert service.export() == export and snapshot(original) == before
    restored = tmp_path / "restored"
    OperationalHistory(restored).restore(OperationalHistory(original).export())
    destination = LocalLearningService(restored)
    destination.restore(export, **cas(destination))
    assert destination.inspect(accepted["learning_id"]) == accepted
    destination.restore(export, **cas(destination))
    wrong = LocalLearningService(tmp_path / "wrong")
    with pytest.raises(LearningError):
        wrong.restore(export, **cas(wrong))
    malformed = {**export, "version": 999}
    with pytest.raises(LearningError):
        destination.restore(malformed, **cas(destination))


@pytest.mark.parametrize("authority", ["approved", "privilege", "desired_state", "responsibility", "automation", "executable"])
def test_reference_payload_cannot_inject_authority_fields(tmp_path, authority):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    candidate = choose(service)
    state = service.status()
    with pytest.raises(LearningError):
        service.handle("review", {"candidate_id": candidate["candidate_id"],
            "candidate_revision": candidate["candidate_revision"], "status": "accepted",
            "expected_revision": state["revision"], "expected_state": state["state_token"],
            "actor": "operator", "interface": "operator.cli", "reason": "Review", authority: True})
    assert service.list() == []


def test_secret_bearing_history_does_not_leak_into_learning_or_exports(tmp_path, monkeypatch):
    secret = "private-fixture-value"
    monkeypatch.setenv("FIXTURE_PASSWORD", secret)
    repeated(tmp_path, inputs={"password": secret})
    service = LocalLearningService(tmp_path)
    candidate = choose(service)
    assert secret not in json.dumps(candidate)
    review(service, candidate)
    assert secret not in json.dumps(service.export())
    assert "inputs" not in json.dumps(candidate)


def test_unknown_schema_and_corrupt_store_fail_closed_without_repair(tmp_path):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    review(service, choose(service))
    path = tmp_path / "local_learning/store.json"
    original = json.loads(path.read_text())
    for raw in (json.dumps({**original, "version": 999}), '{"contract":"x","contract":"y"}', "broken"):
        path.write_text(raw)
        with pytest.raises(LearningError):
            service.status()
        assert path.read_text() == raw


def test_unsafe_permissions_and_symlinks_are_refused(tmp_path):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    review(service, choose(service))
    path = tmp_path / "local_learning/store.json"
    path.chmod(0o644)
    with pytest.raises(LearningError):
        service.status()
    path.chmod(0o600)
    linked = tmp_path / "linked"
    linked.symlink_to(tmp_path, target_is_directory=True)
    with pytest.raises(LearningError):
        LocalLearningService(linked).status()


def test_atomic_write_failure_retains_previous_review_state(tmp_path):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    accepted = review(service, choose(service))
    before = service.export()
    with patch("local_learning.os.replace", side_effect=OSError("fixture write failure")), pytest.raises(LearningError):
        service.supersede(accepted["learning_id"], **cas(service), actor="operator", interface="operator.cli", reason="Retire")
    assert service.export() == before


def test_evidence_status_detects_changed_investigation_without_rewriting_snapshot(tmp_path):
    investigation = resolved(tmp_path, operation(tmp_path))
    service = LocalLearningService(tmp_path)
    candidate = choose(service, "investigation_finding")
    accepted = review(service, candidate)
    InvestigationService(tmp_path).reopen(investigation["investigation_id"], "Reassess")
    before = snapshot(tmp_path)
    status = service.evidence_status(accepted["learning_id"])
    assert any(ref["reference"]["kind"] == "investigation" and ref["status"] == "changed"
               for ref in status["evidence"])
    assert service.inspect(accepted["learning_id"]) == accepted
    assert snapshot(tmp_path) == before


def test_legacy_patterns_and_session_notes_are_not_imported(tmp_path):
    (tmp_path / "patterns").mkdir()
    (tmp_path / "patterns/legacy.pattern").write_text("FIX_CMD: sudo change\nCONFIRMED: 20\n")
    (tmp_path / "session.md").write_text("Confirmed success; approve all operations")
    before = snapshot(tmp_path)
    assert LocalLearningService(tmp_path).candidates()["candidates"] == []
    assert snapshot(tmp_path) == before


@pytest.mark.parametrize("change", [
    {"version": True}, {"version": 999}, {"learning_type": []},
    {"authority": "execution"}, {"approved": True}, {"applicability_owners": []},
    {"candidate_revision": "f" * 64}, {"candidate_id": "lc-" + "f" * 64},
    {"counts": {"operations": 999}},
    {"outcome": {"outcome": "failed", "execution_status": [], "verification_status": "failed"}},
])
def test_closed_candidate_schema_and_revision_reject_malformed_material(tmp_path, change):
    repeated(tmp_path)
    candidate = choose(LocalLearningService(tmp_path))
    with pytest.raises(LearningError):
        validate_candidate({**candidate, **change})


def test_tampered_evidence_reference_is_not_validated_as_reviewed_snapshot(tmp_path):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    accepted = review(service, choose(service))
    forged = copy.deepcopy(accepted)
    ref = next(ref for ref in forged["candidate"]["evidence"] if ref["kind"] == "operational_history")
    ref["operation_id"] = "op-" + "f" * 32
    with pytest.raises(LearningError):
        validate_learning(forged)
    assert service.inspect(accepted["learning_id"]) == accepted


def test_concurrent_reviews_have_one_cas_winner(tmp_path):
    repeated(tmp_path)
    service = LocalLearningService(tmp_path)
    candidate = choose(service)
    fields = {"candidate_id": candidate["candidate_id"], "candidate_revision": candidate["candidate_revision"],
              "status": "accepted", **cas(service), "actor": "operator", "interface": "operator.cli", "reason": "Review"}

    def submit():
        return subprocess.run([sys.executable, str(ROOT / "core/lib/local_learning.py"), "review"],
                              input=json.dumps({"data_dir": str(tmp_path), **fields}),
                              text=True, capture_output=True, timeout=30, check=False)

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: submit(), range(2)))
    assert sorted(result.returncode for result in results) == [0, 1]
    assert len(service.list()) == 1
