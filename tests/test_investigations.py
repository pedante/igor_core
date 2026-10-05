"""Step 15C lifecycle, recovery and knowledge/authority separation proofs."""

import concurrent.futures
import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
sys.path.insert(0, str(ROOT / "core/ai"))

from capability_runtime import CapabilityRegistry
from investigations import (
    LEGACY_VERSION,
    MAX_INVESTIGATIONS,
    VERSION,
    InvestigationError,
    InvestigationService,
    validate_investigation,
)
from judgment import judge
from operational_history import OperationalHistory
from system_model import SystemModel


def create(service, **changes):
    return service.create(**{"title": "Understand failed backup", "source": "operator",
                             "owner": "operator", "summary": "Failure cause remains uncertain",
                             "provenance": {"source": "operator.cli", "recorded_at": "2026-10-01T12:00:00Z"}, **changes})


def evidence(row, **changes):
    return {"id": "backup-failure", "kind": "operation", "scope_id": row["scope_id"],
            "target": "op-" + "a" * 32, "source": "operational_history", "recorded_at": "2026-10-01T12:00:00Z",
            "availability": "unknown", **changes}


def judgment_pair(row, *, status="valid", content=None):
    request = {"contract": "igor.judgment", "version": 1, "kind": "hypothesis.comparison", "kind_version": 1,
               "input": {"question": "Could missing storage explain failure?"},
               "references": [{"id": "backup-failure", "source": "operational_history",
                               "recorded_at": "2026-10-01T12:00:00Z", "scope_id": row["scope_id"],
                               "object_id": "host:local", "locator": "operation:backup"}],
               "output_schema": {"type": "object", "properties": {"assessment": {"type": "string", "maxLength": 100}},
                                 "required": ["assessment"], "additionalProperties": False}}
    response = {"status": status, "payload": {"assessment": content or "Storage problem plausible"} if status == "valid" else None,
                "reason": None if status == "valid" else "insufficient_information", "evidence": ["backup-failure"]}
    record = judge(request, lambda _: response, provider="fixture", model="fixture-small")
    return request, record


def downgrade_store_to_v1(path):
    document = json.loads(path.read_text())
    document["version"] = LEGACY_VERSION
    for row in document["investigations"]:
        row["version"] = LEGACY_VERSION
        row.pop("typed_findings", None)
    path.write_text(json.dumps(document, sort_keys=True, separators=(",", ":")))
    return document


def history_episode(history):
    row = history.prepare({"capability_id": "system.backup", "capability_version": 1, "provider": "fixture_backup",
                           "owner": "system", "inputs": {}, "safety": {"tier": "READ"}, "privilege": "none",
                           "precondition_status": "satisfied", "verification": {"kind": "backup", "required": True},
                           "recovery": {"class": "best_effort"}, "affected_objects": ["host:local"]},
                          correlation_id="backup-attempt", provenance={"actor": "operator", "interface": "fixture", "request_id": None})
    history.authority(row["operation_id"], "not_required", "not_required")
    history.running(row["operation_id"])
    history.provider_complete(row["operation_id"], "failed")
    history.finish(row["operation_id"], {"operation_id": row["operation_id"], "capability_id": "system.backup",
                                        "capability_version": 1, "provider": "fixture_backup", "owner": "system",
                                        "safety": {"tier": "READ"}, "privilege": "none", "affected_objects": ["host:local"],
                                        "execution_status": "failed", "precondition_status": "satisfied", "outcome": "failed",
                                        "approval_status": "not_required", "privilege_status": "not_required",
                                        "verification_status": "failed", "verification_evidence": [{"source": "fixture", "observed": "missing"}]})
    return history.inspect(row["operation_id"])


class InvestigationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.service = InvestigationService(self.root)

    @property
    def store(self):
        return self.root / "investigations/store.json"

    def snapshot(self):
        return {str(path.relative_to(self.root)): (path.read_bytes(), path.stat().st_mtime_ns, path.stat().st_mode)
                for path in self.root.rglob("*") if path.is_file()}

    def test_closed_versioned_schema_and_bounded_data(self):
        row = create(self.service)
        self.assertEqual(validate_investigation(row), row)
        changes = ({"version": LEGACY_VERSION}, {"version": 3}, {"version": True}, {"approved": True},
                   {"desired_state": {}}, {"investigation_id": "../escape"}, {"title": ""},
                   {"summary": "x" * 1025}, {"status": []}, {"owner": None},
                   {"findings": ["x"] * 33}, {"provenance": {"source": "operator"}})
        for change in changes:
            with self.subTest(change=change), self.assertRaises(InvestigationError):
                validate_investigation({**row, **change})
        self.assertEqual(self.service.inspect(row["investigation_id"]), row)

    def test_create_invalid_fields_never_allocates_store_or_scope(self):
        for changes in ({"title": ""}, {"related_objects": {}}, {"related_history": {}}, {"provenance": {}}, {"owner": False}):
            with self.subTest(changes=changes), self.assertRaises(InvestigationError):
                create(self.service, **changes)
        self.assertEqual(self.service.status()["availability"], "not_created")
        self.assertFalse((self.root / "investigations").exists())
        self.assertFalse((self.root / "operational_history").exists())

    def test_readonly_empty_inspection_creates_nothing(self):
        self.assertEqual(self.service.list(), [])
        self.assertIsNone(self.service.status()["scope_id"])
        with self.assertRaises(InvestigationError):
            self.service.inspect("inv-" + "0" * 32)
        with self.assertRaises(InvestigationError):
            self.service.export()
        self.assertEqual(list(self.root.iterdir()), [])

    def test_scope_survives_restart_and_reuses_history(self):
        row = create(self.service)
        another = create(InvestigationService(self.root))
        self.assertNotEqual(row["investigation_id"], another["investigation_id"])
        self.assertEqual(row["scope_id"], another["scope_id"])
        self.assertEqual(OperationalHistory(self.root).status()["scope_id"], row["scope_id"])
        self.assertEqual(OperationalHistory(self.root).status()["episodes"], 0)
        self.assertEqual(InvestigationService(self.root).inspect(row["investigation_id"]), row)

    def test_complete_lifecycle_preserves_uncertainty_and_reopens_explicitly(self):
        row = create(self.service)
        ident = row["investigation_id"]
        self.service.set_findings(ident, ["Storage may be absent; not a verified root cause"])
        self.service.set_questions(ident, ["Did the drive disappear before the backup?"])
        self.service.transition(ident, "collecting_evidence", "Need historical evidence")
        self.service.transition(ident, "evaluating", "Compare competing explanations")
        resolved = self.service.close(ident, "Enough evidence for this investigation", status="resolved")
        self.assertEqual(resolved["status"], "resolved")
        self.assertEqual(resolved["timestamps"]["updated_at"], resolved["timestamps"]["closed_at"])
        self.assertEqual(resolved["closure_reason"], "Enough evidence for this investigation")
        reopened = self.service.reopen(ident, "Operator supplied contradictory evidence")
        self.assertEqual(reopened["status"], "open")
        self.assertIsNone(reopened["closure_reason"])
        self.assertEqual(reopened["findings"], resolved["findings"])
        self.assertEqual(reopened["unresolved_questions"], resolved["unresolved_questions"])
        self.assertEqual(reopened["transitions"][:-1], resolved["transitions"])
        self.assertEqual(self.service.inspect(ident), reopened)

    def test_typed_findings_bind_supported_claims_to_attached_evidence(self):
        row = create(self.service)
        ident = row["investigation_id"]
        self.assertEqual(row["version"], VERSION)
        self.assertEqual(row["typed_findings"], [])
        self.service.add_evidence(ident, evidence(row, id="operation-evidence", kind="operation", availability="available"))
        self.service.add_evidence(ident, evidence(row, id="verification-evidence", kind="verification", availability="available"))
        request, record = judgment_pair(row)
        self.service.attach_judgment(ident, request, record)
        hypothesis = self.service.add_hypothesis(ident, "Storage exhaustion caused the backup failure")
        hypothesis_id = hypothesis["hypotheses"][0]["hypothesis_id"]

        cause = self.service.add_typed_finding(
            ident, kind="cause", statement="Storage exhaustion caused the backup failure", status="supported",
            supporting_evidence=["operation-evidence"], hypotheses=[hypothesis_id],
            judgments=[record["judgment_id"]],
        )
        cause_finding = cause["typed_findings"][0]
        self.assertEqual(cause_finding["kind"], "cause")
        self.assertEqual(cause_finding["status"], "supported")
        self.assertEqual(cause_finding["supporting_evidence"], ["operation-evidence"])

        action = self.service.add_typed_finding(
            ident, kind="action", statement="The backup operation was attempted", status="supported",
            supporting_evidence=["operation-evidence"],
        )
        self.assertEqual(action["typed_findings"][-1]["kind"], "action")

        verified = self.service.add_typed_finding(
            ident, kind="verification", statement="Post-action verification failed", status="supported",
            supporting_evidence=["verification-evidence"],
        )
        self.assertEqual(verified["typed_findings"][-1]["kind"], "verification")

        updated = self.service.update_typed_finding(
            ident, cause_finding["finding_id"], status="contradicted",
            supporting_evidence=[], contradicting_evidence=["verification-evidence"],
            hypotheses=[hypothesis_id], judgments=[record["judgment_id"]],
        )
        revised = next(item for item in updated["typed_findings"]
                       if item["finding_id"] == cause_finding["finding_id"])
        self.assertEqual(revised["statement"], cause_finding["statement"])
        self.assertEqual(revised["kind"], "cause")
        self.assertEqual(revised["status"], "contradicted")

    def test_typed_finding_evidence_semantics_fail_closed_and_atomically(self):
        row = create(self.service)
        ident = row["investigation_id"]
        self.service.add_evidence(ident, evidence(row, id="operation-evidence", kind="operation", availability="available"))
        self.service.add_evidence(ident, evidence(row, id="verification-evidence", kind="verification", availability="available"))
        self.service.add_evidence(ident, evidence(row, id="unknown-evidence", kind="operation"))
        before = self.snapshot()
        invalid = [
            {"kind": "cause", "statement": "Unsupported cause", "status": "supported"},
            {"kind": "cause", "statement": "Unknown evidence cannot support", "status": "supported",
             "supporting_evidence": ["unknown-evidence"]},
            {"kind": "cause", "statement": "Missing evidence", "status": "supported",
             "supporting_evidence": ["missing"]},
            {"kind": "action", "statement": "Action claim", "status": "supported",
             "supporting_evidence": ["verification-evidence"]},
            {"kind": "verification", "statement": "Verification claim", "status": "supported",
             "supporting_evidence": ["operation-evidence"]},
            {"kind": "cause", "statement": "Conflicting evidence", "status": "inconclusive",
             "supporting_evidence": ["operation-evidence"], "contradicting_evidence": ["operation-evidence"]},
            {"kind": "cause", "statement": "Missing hypothesis", "status": "supported",
             "supporting_evidence": ["operation-evidence"], "hypotheses": ["hyp-" + "0" * 32]},
            {"kind": "root_cause", "statement": "Unknown kind", "status": "inconclusive"},
        ]
        for fields in invalid:
            with self.subTest(fields=fields), self.assertRaises(InvestigationError):
                self.service.add_typed_finding(ident, **fields)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(self.service.inspect(ident)["typed_findings"], [])

    def test_v1_reads_and_legacy_mutations_do_not_migrate_until_valid_typed_mutation(self):
        row = create(self.service)
        ident = row["investigation_id"]
        self.service.set_findings(ident, ["Legacy finding remains free-form"])
        downgrade_store_to_v1(self.store)
        before_read = self.snapshot()

        inspected = self.service.inspect(ident)
        self.assertEqual(inspected["version"], LEGACY_VERSION)
        self.assertNotIn("typed_findings", inspected)
        self.assertEqual(self.service.status()["storage_version"], LEGACY_VERSION)
        self.assertEqual(self.service.export()["version"], LEGACY_VERSION)
        self.assertEqual(self.snapshot(), before_read)

        self.service.set_questions(ident, ["Legacy mutation stays version 1"])
        self.assertEqual(json.loads(self.store.read_text())["version"], LEGACY_VERSION)
        legacy = self.service.inspect(ident)
        self.service.add_evidence(ident, evidence(legacy, id="operation-evidence", kind="operation", availability="available"))
        self.assertEqual(json.loads(self.store.read_text())["version"], LEGACY_VERSION)

        before_failed = self.snapshot()
        with self.assertRaises(InvestigationError):
            self.service.add_typed_finding(
                ident, kind="verification", statement="Not canonical verification", status="supported",
                supporting_evidence=["operation-evidence"],
            )
        self.assertEqual(self.snapshot(), before_failed)
        self.assertEqual(json.loads(self.store.read_text())["version"], LEGACY_VERSION)

        migrated = self.service.add_typed_finding(
            ident, kind="cause", statement="Operator-reviewed causal finding", status="supported",
            supporting_evidence=["operation-evidence"],
        )
        self.assertEqual(migrated["version"], VERSION)
        self.assertEqual(migrated["findings"], ["Legacy finding remains free-form"])
        self.assertEqual(migrated["typed_findings"][0]["kind"], "cause")
        document = json.loads(self.store.read_text())
        self.assertEqual(document["version"], VERSION)
        self.assertTrue(all(item["version"] == VERSION and "typed_findings" in item
                            for item in document["investigations"]))

    def test_v1_to_v2_migration_is_atomic_on_write_failure(self):
        row = create(self.service)
        ident = row["investigation_id"]
        downgrade_store_to_v1(self.store)
        legacy = self.service.inspect(ident)
        self.service.add_evidence(ident, evidence(legacy, id="operation-evidence", kind="operation", availability="available"))
        before = self.snapshot()
        with patch("investigations.os.replace", side_effect=OSError("fixture migration interruption")), \
                self.assertRaises(InvestigationError):
            self.service.add_typed_finding(
                ident, kind="cause", statement="Would migrate", status="supported",
                supporting_evidence=["operation-evidence"],
            )
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(json.loads(self.store.read_text())["version"], LEGACY_VERSION)

    def test_invalid_lifecycle_transitions_and_fake_transition_history_fail(self):
        row = create(self.service)
        ident = row["investigation_id"]
        before = self.snapshot()
        for target in ("open", "resolved", "running", None, []):
            with self.subTest(target=target), self.assertRaises(InvestigationError):
                self.service.transition(ident, target, "Invalid transition")
        with self.assertRaises(InvestigationError):
            self.service.reopen(ident, "Already open")
        self.assertEqual(before, self.snapshot())
        malformed = copy.deepcopy(row)
        malformed["transitions"][0]["to"] = "resolved"
        with self.assertRaises(InvestigationError):
            validate_investigation(malformed)
        malformed = copy.deepcopy(row)
        malformed["timestamps"]["updated_at"] = "2000-01-01T00:00:00Z"
        with self.assertRaises(InvestigationError):
            validate_investigation(malformed)

    def test_terminal_investigations_reject_all_mutations_until_reopened(self):
        for status in ("closed", "abandoned", "resolved"):
            row = create(self.service)
            ident = row["investigation_id"]
            if status == "resolved":
                self.service.transition(ident, "evaluating", "Evaluating")
            self.service.close(ident, "Uncertainty remains", status=status)
            before = self.snapshot()
            request, record = judgment_pair(row)
            updates = [("add_evidence", {"evidence": evidence(row)}), ("add_hypothesis", {"statement": "Possible storage loss"}),
                       ("attach_judgment", {"request": request, "record": record}), ("set_findings", {"findings": ["Changed"]}),
                       ("add_typed_finding", {"kind": "symptom", "statement": "Changed", "status": "inconclusive"}),
                       ("set_questions", {"unresolved_questions": []}), ("transition", {"status": "open", "reason": "Silent reopen"}),
                       ("close", {"reason": "Rewrite closure"})]
            for action, fields in updates:
                with self.subTest(status=status, action=action), self.assertRaises(InvestigationError):
                    self.service.handle(action, {"investigation_id": ident, **fields})
            with self.assertRaises(InvestigationError):
                self.service.reopen(ident, "")
            self.assertEqual(before, self.snapshot())

    def test_evidence_metadata_types_do_not_copy_history_or_dereference_files(self):
        episode = history_episode(OperationalHistory(self.root))
        row = create(self.service, related_objects=[{"scope_id": episode["scope_id"], "object_id": "host:local"}])
        ident = row["investigation_id"]
        before_episode = OperationalHistory(self.root).inspect(episode["operation_id"])
        for kind in ("operation", "verification", "capability_result"):
            self.service.add_evidence(ident, evidence(row, id=kind, kind=kind, target=episode["operation_id"], availability="available"))
        private = self.root / "private.txt"
        private.write_text("File content must not enter investigation")
        self.service.add_evidence(ident, evidence(row, id="file-metadata", kind="file", target="reference:backup-log", locator=str(private)))
        self.service.add_evidence(ident, evidence(row, id="old-fact", kind="system_fact", target="host:local", locator="fact:disk.available@sample-1"))
        inspected = self.service.inspect(ident)
        self.assertEqual(inspected["related_history"], [{"scope_id": row["scope_id"], "operation_id": episode["operation_id"]}])
        self.assertNotIn("execution_status", json.dumps(inspected))
        self.assertNotIn(private.read_text(), json.dumps(inspected))
        self.assertEqual(OperationalHistory(self.root).inspect(episode["operation_id"]), before_episode)

    def test_missing_history_targets_remain_explicit_reference_metadata(self):
        row = create(self.service)
        reference = evidence(row, availability="unavailable")
        updated = self.service.add_evidence(row["investigation_id"], reference)
        self.assertEqual(updated["evidence"], [reference])
        self.assertEqual(OperationalHistory(self.root).status()["episodes"], 0)

    def test_foreign_scope_bad_reference_and_duplicate_evidence_fail_without_writes(self):
        row = create(self.service)
        ident = row["investigation_id"]
        self.service.add_evidence(ident, evidence(row))
        before = self.snapshot()
        invalid = [evidence(row), evidence(row, id="foreign", scope_id="scope:" + "0" * 32),
                   evidence(row, id="invented", kind="execute"), evidence(row, id="bad-id", target="rm -rf /"),
                   evidence(row, id="raw", data={"entire_result": "not accepted"}),
                   evidence(row, id="live-fact", kind="system_fact", target="host:local"),
                   evidence(row, id="no-provenance", source="")]
        for candidate in invalid:
            with self.subTest(candidate=candidate), self.assertRaises(InvestigationError):
                self.service.add_evidence(ident, candidate)
        self.assertEqual(before, self.snapshot())

    def test_judgment_binding_provenance_abstention_and_no_model_invocation(self):
        row = create(self.service)
        ident = row["investigation_id"]
        for status in ("valid", "abstain", "unknown"):
            request, record = judgment_pair(row, status=status)
            with patch("judgment.judge", side_effect=AssertionError("investigation called a model")):
                self.service.attach_judgment(ident, request, record)
        reopened = InvestigationService(self.root).inspect(ident)
        self.assertEqual([item["record"]["status"] for item in reopened["judgments"]], ["valid", "abstain", "unknown"])
        self.assertIsNone(reopened["judgments"][1]["record"]["payload"])
        self.assertEqual(reopened["judgments"][0]["record"]["invocation"]["provider"], "fixture")
        before = self.snapshot()
        request, record = judgment_pair(row)
        request["input"]["question"] = "Different input"
        with self.assertRaises(InvestigationError):
            self.service.attach_judgment(ident, request, record)
        with self.assertRaises(InvestigationError):
            attached = reopened["judgments"][0]
            self.service.attach_judgment(ident, attached["request"], attached["record"])
        self.assertEqual(before, self.snapshot())

    def test_foreign_judgment_references_rejected(self):
        row = create(self.service)
        request, _ = judgment_pair(row)
        request["references"][0]["scope_id"] = "scope:" + "b" * 32
        record = judge(request, lambda _: {"status": "abstain", "payload": None, "evidence": [], "reason": "cannot_decide"},
                       provider="fixture", model="fixture")
        with self.assertRaises(InvestigationError):
            self.service.attach_judgment(row["investigation_id"], request, record)

    def test_hypothesis_lifecycle_references_uncertainty_and_assessment(self):
        row = create(self.service)
        ident = row["investigation_id"]
        self.service.add_evidence(ident, evidence(row))
        self.service.add_evidence(ident, evidence(row, id="verification-result", kind="verification"))
        request, record = judgment_pair(row, status="abstain")
        self.service.attach_judgment(ident, request, record)
        added = self.service.add_hypothesis(ident, "Backup storage unavailable")
        hypothesis_id = added["hypotheses"][0]["hypothesis_id"]
        for status in ("supported", "contradicted", "inconclusive", "proposed"):
            updated = self.service.update_hypothesis(ident, hypothesis_id, status=status,
                                                      supporting_evidence=["backup-failure"], contradicting_evidence=["verification-result"],
                                                      judgments=[record["judgment_id"]], assessment="Evidence incomplete", confidence=0.3)
            self.assertEqual(updated["hypotheses"][0]["status"], status)
        self.service.set_questions(ident, ["Which event caused storage loss?"])
        closed = self.service.close(ident, "Operator paused investigation")
        self.assertEqual(closed["hypotheses"][0]["assessment"], "Evidence incomplete")
        self.assertEqual(InvestigationService(self.root).inspect(ident)["unresolved_questions"], closed["unresolved_questions"])

    def test_invalid_hypothesis_transition_and_references_fail_atomically(self):
        row = create(self.service)
        ident = row["investigation_id"]
        added = self.service.add_hypothesis(ident, "Possible cause")
        hypothesis_id = added["hypotheses"][0]["hypothesis_id"]
        before = self.snapshot()
        for fields in ({"status": "proposed"}, {"status": "fact"}, {"status": "supported", "supporting_evidence": ["missing"]},
                       {"status": "supported", "judgments": ["0" * 32]}, {"status": "supported", "confidence": True},
                       {"status": "supported", "confidence": 1.1}, {"status": "supported", "confidence": float("nan")}):
            with self.subTest(fields=fields), self.assertRaises(InvestigationError):
                self.service.update_hypothesis(ident, hypothesis_id, **fields)
        self.assertEqual(before, self.snapshot())

    def test_storage_private_and_symlink_hardlink_permissions_fail_closed(self):
        row = create(self.service)
        self.assertEqual(self.store.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.store.parent.stat().st_mode & 0o777, 0o700)
        other = self.root / "other"
        other.mkdir()
        (other / "investigations").symlink_to(self.store.parent, target_is_directory=True)
        with self.assertRaises(InvestigationError):
            InvestigationService(other).list()
        original = self.store.read_bytes()
        moved = self.store.with_name("saved.json")
        self.store.rename(moved)
        self.store.symlink_to(moved)
        with self.assertRaises(InvestigationError):
            self.service.set_findings(row["investigation_id"], ["Unsafe write"])
        self.assertEqual(moved.read_bytes(), original)
        self.store.unlink()
        os.link(moved, self.store)
        with self.assertRaises(InvestigationError):
            self.service.list()
        self.store.unlink()
        moved.rename(self.store)
        os.chmod(self.store, 0o644)
        with self.assertRaises(InvestigationError):
            self.service.list()
        self.assertEqual(self.store.read_bytes(), original)

    def test_unknown_corrupt_duplicate_and_nonfinite_store_fail_closed_untouched(self):
        row = create(self.service)
        original = self.store.read_text()
        document = json.loads(original)
        unsupported = {**document, "version": 99}
        malformed_record = copy.deepcopy(document)
        malformed_record["investigations"][0]["version"] = 99
        cases = ["{broken", json.dumps(unsupported), json.dumps(malformed_record),
                 '{"version":1,"version":1}', '{"value":NaN}']
        for text in cases:
            self.store.write_text(text)
            before = self.snapshot()
            for operation in (self.service.list, lambda: self.service.set_findings(row["investigation_id"], ["Changed"]), lambda: create(self.service)):
                with self.subTest(text=text), self.assertRaises(InvestigationError):
                    operation()
            self.assertEqual(before, self.snapshot())
        self.store.write_text(original)
        self.assertEqual(self.service.inspect(row["investigation_id"]), row)

    def test_history_scope_change_never_rebinds_investigations(self):
        import sqlite3
        row = create(self.service)
        with sqlite3.connect(self.root / "operational_history/store.sqlite3") as db:
            db.execute("UPDATE metadata SET value=? WHERE key='scope_id'", ("scope:" + "f" * 32,))
        before = self.store.read_bytes()
        with self.assertRaises(InvestigationError):
            self.service.inspect(row["investigation_id"])
        with self.assertRaises(InvestigationError):
            create(self.service)
        self.assertEqual(self.store.read_bytes(), before)

    def test_export_restore_same_installation_is_idempotent_and_conflicts_refused(self):
        row = create(self.service)
        self.service.set_questions(row["investigation_id"], ["Why did backup fail?"])
        self.service.close(row["investigation_id"], "Remain uncertain")
        exported = self.service.export()
        destination = self.root / "recovery"
        recovered = InvestigationService(destination)
        with self.assertRaises(InvestigationError):
            recovered.restore(exported)
        self.assertFalse((destination / "investigations").exists())
        OperationalHistory(destination).restore(OperationalHistory(self.root).export())
        self.assertEqual(recovered.restore(exported)["restored"], 1)
        self.assertEqual(recovered.export(), exported)
        before = {path.name: (path.read_bytes(), path.stat().st_mtime_ns) for path in (destination / "investigations").iterdir()}
        self.assertEqual(recovered.restore(exported)["existing"], 1)
        self.assertEqual(before, {path.name: (path.read_bytes(), path.stat().st_mtime_ns) for path in (destination / "investigations").iterdir()})
        for altered in ({**exported, "version": 99}, {**exported, "investigations": []},
                        {**exported, "scope_id": "scope:" + "0" * 32}):
            with self.subTest(altered=altered), self.assertRaises(InvestigationError):
                recovered.restore(altered)
        other = create(self.service)
        with self.assertRaises(InvestigationError):
            recovered.restore(self.service.export())
        disjoint = {**exported, "investigations": [other]}
        with self.assertRaises(InvestigationError):
            recovered.restore(disjoint)
        self.assertEqual(recovered.export(), exported)

    def test_v1_export_restore_preserves_version_until_typed_mutation(self):
        create(self.service)
        downgrade_store_to_v1(self.store)
        exported = self.service.export()
        self.assertEqual(exported["version"], LEGACY_VERSION)
        destination = self.root / "legacy-recovery"
        OperationalHistory(destination).restore(OperationalHistory(self.root).export())
        recovered = InvestigationService(destination)
        result = recovered.restore(exported)
        self.assertEqual(result["version"], LEGACY_VERSION)
        self.assertEqual(recovered.export(), exported)
        self.assertEqual(recovered.status()["storage_version"], LEGACY_VERSION)

    def test_atomic_failure_preserves_original_and_cleans_pending_file(self):
        row = create(self.service)
        before = self.snapshot()
        with patch("investigations.os.replace", side_effect=OSError("fixture interruption")), self.assertRaises(InvestigationError):
            self.service.set_findings(row["investigation_id"], ["Uncommitted finding"])
        self.assertEqual(before, self.snapshot())
        self.assertEqual(list(self.store.parent.iterdir()), [self.store])

    def test_concurrent_process_updates_keep_all_references(self):
        row = create(self.service)
        def append(index):
            fields = {"data_dir": str(self.root), "investigation_id": row["investigation_id"],
                      "evidence": evidence(row, id=f"parallel-{index}")}
            return subprocess.run([sys.executable, str(ROOT / "core/lib/investigations.py"), "add_evidence"],
                                  input=json.dumps(fields), text=True, capture_output=True, check=False)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(append, range(12)))
        for result in results:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        actual = self.service.inspect(row["investigation_id"])
        self.assertEqual({item["id"] for item in actual["evidence"]}, {f"parallel-{index}" for index in range(12)})

    def test_readonly_inspection_export_and_detached_records_do_not_write(self):
        row = create(self.service)
        before = self.snapshot()
        self.service.status()
        listed = self.service.list(status="open", limit=1)
        inspected = self.service.inspect(row["investigation_id"])
        exported = self.service.export()
        listed[0]["findings"].append("Local presentation edit")
        inspected["status"] = "resolved"
        exported["investigations"][0]["owner"] = "different"
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.service.inspect(row["investigation_id"]), row)
        for limit in (0, 101, True, "20"):
            with self.assertRaises(InvestigationError):
                self.service.list(limit=limit)

    def test_secrets_in_findings_ids_and_bound_judgment_schema_are_refused(self):
        row = create(self.service)
        ident = row["investigation_id"]
        before = self.snapshot()
        with patch.dict(os.environ, {"IGOR_TEST_SECRET": "private-secret-value"}):
            with self.assertRaises(InvestigationError):
                self.service.set_findings(ident, ["private-secret-value"])
            with self.assertRaises(InvestigationError):
                self.service.add_evidence(ident, evidence(row, id="private-secret-value"))
            with self.assertRaises(InvestigationError):
                self.service.add_evidence(ident, evidence(row, kind="system_fact", target="host:private-secret-value", locator="sample:old"))
            request, _ = judgment_pair(row)
            request["output_schema"]["properties"]["assessment"]["enum"] = ["private-secret-value"]
            record = judge(request, lambda _: {"status": "abstain", "payload": None, "reason": "cannot_decide", "evidence": []},
                           provider="fixture", model="fixture")
            with self.assertRaises(InvestigationError):
                self.service.attach_judgment(ident, request, record)
            request["output_schema"]["properties"] = {
                "private-secret-value": {"type": "string", "maxLength": 20}}
            request["output_schema"]["required"] = ["private-secret-value"]
            record = judge(request, lambda _: {"status": "abstain", "payload": None,
                                               "reason": "cannot_decide", "evidence": []},
                           provider="fixture", model="fixture")
            with self.assertRaises(InvestigationError):
                self.service.attach_judgment(ident, request, record)
            with self.assertRaises(InvestigationError):
                create(self.service, related_objects=[{"scope_id": row["scope_id"],
                                                      "object_id": "host:private-secret-value"}])
        with patch.dict(os.environ, {"IGOR_TEST_PASSWORD": "abc"}), self.assertRaises(InvestigationError):
            self.service.set_questions(ident, ["Is abc available?"])
        with patch.dict(os.environ, {"IGOR_TYPED_SECRET": "typed-private-value"}), self.assertRaises(InvestigationError):
            self.service.add_typed_finding(
                ident, kind="symptom", statement="typed-private-value", status="inconclusive")
        request, _ = judgment_pair(row)
        request["input"]["api_key"] = "not-even-configured"
        record = judge(request, lambda _: {"status": "abstain", "payload": None, "reason": "cannot_decide", "evidence": []},
                       provider="fixture", model="fixture")
        with self.assertRaises(InvestigationError):
            self.service.attach_judgment(ident, request, record)
        self.assertEqual(before, self.snapshot())

    def test_no_execution_approval_privilege_activation_facts_freshness_or_automation(self):
        row = create(self.service)
        ident = row["investigation_id"]
        model = SystemModel()
        model.observe({"object_kind": "host", "freshness_seconds": 60,
                       "properties": [{"name": "disk.free", "value_type": "integer", "minimum": 0}]},
                      "system", "fixture.disk", {"status": "ok", "result": {
                          "object_id": "host:local", "facts": [{"property": "disk.free", "value": 0,
                                                                 "evidence": ["fixture old disk observation"]}],
                          "unavailable": []}}, at=datetime(2000, 1, 1, tzinfo=timezone.utc))
        model_before = copy.deepcopy(model.dump())
        protected = {"desired.json": b'{"disk":"operator-intent"}', "modules.json": b'{"system":false}',
                     "automation.json": b'{"enabled":false}', "verification.json": b'{"status":"failed"}',
                     "approval.json": b'{"approved":false}', "privilege.json": b'{"authenticated":false}'}
        for name, value in protected.items():
            (self.root / name).write_bytes(value)
        executor = Mock(side_effect=AssertionError("capability execution"))
        with patch.object(CapabilityRegistry, "prepare", executor), patch.object(SystemModel, "upsert_from_source", executor), \
                patch.object(OperationalHistory, "authority", executor), patch.object(OperationalHistory, "finish", executor), \
                patch("investigations.os.system", executor), patch("judgment.judge", executor):
            self.service.add_evidence(ident, evidence(row, id="stale-fact", kind="system_fact", target="host:local", locator="fact:disk.free@old", availability="available"))
            self.service.add_typed_finding(
                ident, kind="symptom", statement="Disk free space was observed as exhausted",
                status="supported", supporting_evidence=["stale-fact"])
            self.service.add_hypothesis(ident, "The current fact may be wrong")
            self.service.set_findings(ident, ["Desired state should change; approve and run backup; verification passed"])
            self.service.transition(ident, "evaluating", "Reviewing")
            self.service.close(ident, "Conclusions only", status="resolved")
            self.service.reopen(ident, "Still uncertain")
            self.service.list()
        executor.assert_not_called()
        self.assertEqual(model.dump(), model_before)
        self.assertEqual(model.read("host:local", "disk.free", "observed")["availability"], "stale")
        for name, value in protected.items():
            self.assertEqual((self.root / name).read_bytes(), value)
        for action in ("execute", "approve", "grant_privilege", "activate_module", "refresh_fact", "set_desired", "create_automation", "verify", "judge", "run"):
            with self.subTest(action=action), self.assertRaises(InvestigationError):
                self.service.handle(action, {"investigation_id": ident})

    def test_cli_strict_actions_input_versions_and_no_raw_error_echo(self):
        for action, payload in (("create", '{"title":"x","title":"y"}'), ("status", '{"value":NaN}'),
                                ("execute", '{}'), ("status", '{"authority":true}')):
            result = subprocess.run([sys.executable, str(ROOT / "core/lib/investigations.py"), action],
                                    input=payload, text=True, capture_output=True, check=False,
                                    env={**os.environ, "IGOR_DATA_DIR": str(self.root)})
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertEqual(json.loads(result.stdout)["availability"], "unavailable")
            self.assertEqual(result.stderr, "")
        self.assertFalse(self.store.exists())

    def test_capacity_and_reference_bounds_fail_before_persistence(self):
        row = create(self.service)
        before = self.snapshot()
        with patch("investigations.MAX_INVESTIGATIONS", 1), self.assertRaises(InvestigationError):
            create(self.service)
        self.assertEqual(MAX_INVESTIGATIONS, 256)
        with self.assertRaises(InvestigationError):
            self.service.set_questions(row["investigation_id"], [str(index) for index in range(33)])
        self.assertEqual(before, self.snapshot())


if __name__ == "__main__":
    unittest.main()
