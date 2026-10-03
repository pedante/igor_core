"""Contract and persistence tests for the Step 15B history service."""

import concurrent.futures
import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
from operational_history import HistoryError, OperationalHistory, object_ref, validate_episode  # noqa: E402


def proposal(tier="CHANGE"):
    return {
        "capability_id": "system.service.restart",
        "capability_version": 1,
        "provider": "fixture_service",
        "owner": "system",
        "inputs": {"unit": "demo.service"},
        "safety": {"tier": tier},
        "privilege": "required" if tier != "READ" else "none",
        "precondition_status": "satisfied",
        "verification": {"kind": "service_state", "required": True},
        "recovery": {"class": "best_effort"},
        "affected_objects": ["service:systemd:demo.service"],
    }


def prepare(service, source=None, tier="CHANGE", **kwargs):
    return service.prepare(
        source or proposal(tier), correlation_id="corr-fixture",
        provenance={"actor": "operator", "interface": "capability_api", "request_id": "request-1"},
        **kwargs,
    )


def finish_result(row, *, execution="succeeded", outcome="success", verification="passed",
                  approval="approved", privilege="authenticated"):
    return {
        "operation_id": row["operation_id"],
        "capability_id": row["capability"]["id"],
        "capability_version": row["capability"]["version"],
        "provider": row["provider"]["id"], "owner": row["provider"]["owner"],
        "safety": {"tier": row["safety_tier"]},
        "privilege": row["privilege"]["requirement"],
        "affected_objects": [ref["object_id"] for ref in row["affected_objects"]],
        "execution_status": execution, "precondition_status": "satisfied",
        "outcome": outcome, "approval_status": approval, "privilege_status": privilege,
        "verification_status": verification,
        "verification_evidence": [{"source": "system_model", "observed": "active"}],
    }


class OperationalHistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.history = OperationalHistory(self.root)

    def record_terminal(self, *, tier="CHANGE", execution="succeeded", outcome="success",
                        verification="passed", approval="approved", privilege="authenticated"):
        row = prepare(self.history, tier=tier)
        if approval not in {"denied", "stopped"}:
            self.history.authority(row["operation_id"], approval, privilege)
            if execution != "not_executed":
                self.history.running(row["operation_id"])
                self.history.provider_complete(row["operation_id"], execution)
        else:
            execution, outcome, verification = "not_executed", "approval_denied", "not_applicable"
            privilege = "not_requested"
        self.history.finish(row["operation_id"], finish_result(
            row, execution=execution, outcome=outcome, verification=verification,
            approval=approval, privilege=privilege,
        ))
        return row

    def test_schema_scoped_references_and_provider_identity_ignore_handler_paths(self):
        candidate = proposal()
        candidate.update(handler="old_bash_handler", source_path="/temporary/module.sh", display_name="Old UI")
        row = prepare(self.history, source=candidate)
        candidate.update(handler="replacement_handler", source_path="/new/location.sh", display_name="New UI")
        replacement = prepare(self.history, source=candidate)
        self.assertEqual(row["capability"], replacement["capability"])
        self.assertEqual(row["provider"], replacement["provider"])
        validate_episode(row)
        self.assertEqual(row["affected_objects"], [object_ref(row["scope_id"], "service:systemd:demo.service")])
        self.assertEqual(row["capability"], {"id": "system.service.restart", "version": 1})
        self.assertEqual(row["provider"], {
            "id": "fixture_service", "owner": "system",
            "source": {"kind": "module_contract", "contract_id": "system.service.restart"},
        })
        self.assertNotIn("handler", json.dumps(row))
        self.assertNotIn("path", json.dumps(row))
        malformed = copy.deepcopy(row)
        malformed["schema_version"] = 99
        with self.assertRaises(HistoryError):
            validate_episode(malformed)
        with self.assertRaises(HistoryError):
            object_ref(row["scope_id"], "../etc/passwd")
        malformed = copy.deepcopy(row)
        malformed["affected_objects"][0]["scope_id"] = "scope:" + "0" * 32
        with self.assertRaises(HistoryError):
            validate_episode(malformed)

    def test_ids_are_unique_and_scope_survives_reopen_and_reset(self):
        first = prepare(self.history)
        second = prepare(OperationalHistory(self.root))
        self.assertNotEqual(first["operation_id"], second["operation_id"])
        reopened = OperationalHistory(self.root)
        self.assertEqual(reopened.status()["scope_id"], first["scope_id"])
        self.assertEqual(reopened.inspect(first["operation_id"])["operation_id"], first["operation_id"])
        for row in (first, second):
            reopened.authority(row["operation_id"], "approved", "authenticated")
            reopened.running(row["operation_id"])
            reopened.provider_complete(row["operation_id"], "succeeded")
            reopened.finish(row["operation_id"], finish_result(row))
        old = first["operation_id"]
        self.assertEqual(reopened.reset()["deleted"], 2)
        fresh = prepare(reopened)
        self.assertNotEqual(old, fresh["operation_id"])
        self.assertEqual(fresh["scope_id"], first["scope_id"])

    def test_storage_is_private_and_rejects_symlinks_corruption_and_unknown_versions(self):
        row = prepare(self.history)
        del row
        store_dir = self.root / "operational_history"
        store = store_dir / "store.sqlite3"
        self.assertEqual(store_dir.stat().st_mode & 0o777, 0o700)
        self.assertEqual(store.stat().st_mode & 0o777, 0o600)

        other = self.root / "other"
        other.mkdir()
        (other / "operational_history").symlink_to(store_dir, target_is_directory=True)
        with self.assertRaises(HistoryError):
            OperationalHistory(other).status()

        import sqlite3
        with sqlite3.connect(store) as db:
            db.execute("PRAGMA user_version=99")
        original = store.read_bytes()
        with self.assertRaises(HistoryError):
            self.history.status()
        self.assertEqual(original, store.read_bytes())

        store.unlink()
        store.write_bytes(b"not a sqlite database")
        os.chmod(store, 0o600)
        original = store.read_bytes()
        with self.assertRaises(HistoryError):
            self.history.status()
        self.assertEqual(original, store.read_bytes())

    def test_episode_index_and_record_identity_mismatches_fail_closed(self):
        import sqlite3

        for field in ("correlation", "id"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temp:
                service = OperationalHistory(Path(temp))
                row = prepare(service)
                with sqlite3.connect(Path(temp) / "operational_history/store.sqlite3") as db:
                    if field == "correlation":
                        db.execute("UPDATE episodes SET correlation='other-correlation'")
                    else:
                        db.execute("UPDATE episodes SET id=?", ("op-" + "0" * 32,))
                with self.assertRaises(HistoryError):
                    service.inspect(row["operation_id"] if field == "correlation" else "op-" + "0" * 32)

    def test_invalid_authority_execution_and_terminal_combinations_are_rejected(self):
        row = prepare(self.history)
        with self.assertRaises(HistoryError):
            self.history.authority(row["operation_id"], "denied", "authenticated")
        with self.assertRaises(HistoryError):
            self.history.running(row["operation_id"])
        self.assertEqual(self.history.inspect(row["operation_id"])["lifecycle"], "admitted")

        self.history.authority(row["operation_id"], "approved", "authenticated")
        self.history.running(row["operation_id"])
        with self.assertRaises(HistoryError):
            self.history.finish(row["operation_id"], finish_result(
                row, execution="running", outcome="success", verification="pending"))
        self.assertEqual(self.history.inspect(row["operation_id"])["lifecycle"], "running")

    def test_secrets_are_redacted_and_never_retained_in_episode_or_evidence(self):
        candidate = proposal()
        candidate["inputs"] = {"unit": "demo.service", "api_key": "secret-value",
                                "environment": {"TOKEN": "another-secret"},
                                "note": "password=inline-secret"}
        row = prepare(self.history, source=candidate)
        self.assertTrue(row["inputs_redacted"])
        self.assertNotIn("secret-value", json.dumps(row))
        self.assertNotIn("another-secret", json.dumps(row))
        self.assertNotIn("inline-secret", json.dumps(row))
        self.history.authority(row["operation_id"], "approved", "authenticated")
        self.history.running(row["operation_id"])
        self.history.provider_complete(row["operation_id"], "succeeded")
        result = finish_result(row)
        result["verification_evidence"] = [{"password": "evidence-secret", "detail": "safe"}]
        self.history.finish(row["operation_id"], result)
        inspected = self.history.inspect(row["operation_id"])
        self.assertNotIn("evidence-secret", json.dumps(inspected))
        self.assertEqual(inspected["verification"]["evidence"][0]["data"]["password"], "[REDACTED]")

    def test_read_and_change_terminal_outcomes_and_read_only_inspection(self):
        read = self.record_terminal(tier="READ", privilege="not_required")
        before = (self.root / "operational_history/store.sqlite3").read_bytes()
        episode = self.history.inspect(read["operation_id"])
        recent = self.history.recent(correlation_id="corr-fixture")
        after = (self.root / "operational_history/store.sqlite3").read_bytes()
        self.assertEqual(before, after)
        self.assertEqual(episode["lifecycle"], "terminal")
        self.assertEqual(episode["execution_status"], "succeeded")
        self.assertEqual(episode["verification"]["status"], "passed")
        self.assertTrue(episode["verification"]["evidence"])
        self.assertEqual(len(recent), 1)

        failure = self.record_terminal(execution="failed", outcome="provider_failed",
                                       verification="not_applicable")
        unverified = self.record_terminal(outcome="unverified_change", verification="failed")
        denied = self.record_terminal(approval="denied", privilege="not_requested")
        self.assertEqual(self.history.inspect(failure["operation_id"])["execution_status"], "failed")
        self.assertEqual(self.history.inspect(unverified["operation_id"])["outcome"], "unverified_change")
        self.assertEqual(self.history.inspect(denied["operation_id"])["approval"]["result"], "denied")
        self.assertEqual(self.history.inspect(denied["operation_id"])["execution_status"], "not_executed")

    def test_failed_privilege_authentication_cannot_enter_running(self):
        row = prepare(self.history)
        self.history.authority(row["operation_id"], "approved", "failed")
        with self.assertRaises(HistoryError):
            self.history.running(row["operation_id"])
        self.assertEqual(self.history.inspect(row["operation_id"])["lifecycle"], "admitted")

    def test_known_secret_keys_and_identity_fields_never_enter_the_store(self):
        candidate = proposal()
        candidate["inputs"]["fixture-sensitive-value"] = "safe value"
        with patch.dict(os.environ, {"FIXTURE_API_KEY": "fixture-sensitive-value"}):
            row = prepare(self.history, source=candidate)
            self.assertTrue(row["inputs_redacted"])
            self.assertNotIn("fixture-sensitive-value", json.dumps(row))
            self.assertNotIn(b"fixture-sensitive-value", (self.root / "operational_history/store.sqlite3").read_bytes())
            candidate["affected_objects"] = ["service:fixture-sensitive-value"]
            with self.assertRaises(HistoryError):
                prepare(self.history, source=candidate)

    def test_reset_refuses_live_attempt_and_concurrent_claim_is_unique(self):
        row = prepare(self.history)
        self.history.authority(row["operation_id"], "approved", "authenticated")
        with self.assertRaises(HistoryError):
            self.history.reset()

        def claim(_):
            try:
                OperationalHistory(self.root).running(row["operation_id"], proposal=proposal())
                return True
            except HistoryError:
                return False

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            self.assertEqual(sum(pool.map(claim, range(4))), 1)
        self.assertEqual(self.history.inspect(row["operation_id"])["lifecycle"], "running")

    def test_restore_rejects_missing_schema_and_conflicting_nonempty_destination(self):
        self.record_terminal(tier="READ", privilege="not_required")
        export = self.history.export()
        malformed = copy.deepcopy(export)
        del malformed["episodes"][0]["inputs_redacted"]
        destination = OperationalHistory(self.root / "missing-field")
        with self.assertRaises(HistoryError):
            destination.restore(malformed)
        self.assertEqual(destination.status()["availability"], "not_created")
        destination.restore(export)
        before = (self.root / "missing-field/operational_history/store.sqlite3").read_bytes()
        different = copy.deepcopy(export)
        different["episodes"][0]["inputs"]["unit"] = "different.service"
        with self.assertRaises(HistoryError):
            destination.restore(different)
        self.assertEqual(before, (self.root / "missing-field/operational_history/store.sqlite3").read_bytes())

    def test_corrupt_private_owner_marker_fails_closed(self):
        import sqlite3

        row = prepare(self.history)
        with sqlite3.connect(self.root / "operational_history/store.sqlite3") as db:
            db.execute("UPDATE episodes SET owner='{}'")
        with self.assertRaises(HistoryError):
            self.history.inspect(row["operation_id"])

    def test_headless_stdin_restore_handles_export_larger_than_argument_limit(self):
        candidate = proposal("READ")
        candidate["inputs"].update({f"safe_{index}": "x" * 1000 for index in range(40)})
        for _ in range(4):
            row = prepare(self.history, source=candidate)
            self.history.authority(row["operation_id"], "not_required", "not_required")
            self.history.running(row["operation_id"], proposal=candidate)
            self.history.provider_complete(row["operation_id"], "succeeded")
            self.history.finish(row["operation_id"], finish_result(
                row, approval="not_required", privilege="not_required"))
        export = json.dumps(self.history.export())
        self.assertGreater(len(export), 131072)
        destination = self.root / "stdin-restore"
        restored = subprocess.run(
            ["bash", str(ROOT / "igor.sh"), "--history", "restore", "-"],
            input=export, text=True, capture_output=True,
            env={**os.environ, "IGOR_DATA_DIR": str(destination)}, check=True,
        )
        self.assertEqual(json.loads(restored.stdout)["restored"], 4)
        self.assertEqual(OperationalHistory(destination).status()["episodes"], 4)

    def test_headless_restore_rejects_duplicate_fields_and_non_json_numbers(self):
        for document in ('{"export_version":99,"export_version":1}',
                         '{"export_version":NaN}', '{"export_version":Infinity}'):
            with self.subTest(document=document):
                destination = self.root / "invalid-document"
                completed = subprocess.run(
                    ["bash", str(ROOT / "igor.sh"), "--history", "restore", "-"],
                    input=document, text=True, capture_output=True,
                    env={**os.environ, "IGOR_DATA_DIR": str(destination)},
                )
                self.assertNotEqual(completed.returncode, 0)
                self.assertFalse(destination.exists())

    def test_last_mile_redaction_preserves_generated_ids_and_protocol_values(self):
        from types import SimpleNamespace

        with patch("operational_history.uuid.uuid4", return_value=SimpleNamespace(hex="abab" + "0" * 28)):
            row = self.record_terminal(tier="READ", privilege="not_required")
        with patch.dict(os.environ, {"FIXTURE_API_KEY": "abab", "FIXTURE_PASSWORD": "passed", "FIXTURE_TOKEN": "best_effort"}):
            inspected = self.history.inspect(row["operation_id"])
            exported = self.history.export()
            recent = self.history.recent()[0]
        self.assertEqual(inspected["operation_id"], row["operation_id"])
        self.assertEqual(inspected["scope_id"], row["scope_id"])
        self.assertEqual(inspected["verification"]["status"], "passed")
        self.assertEqual(inspected["recovery"]["class"], "best_effort")
        self.assertEqual(exported["scope_id"], row["scope_id"])
        self.assertEqual(exported["episodes"][0]["operation_id"], row["operation_id"])
        self.assertEqual(recent["operation_id"], row["operation_id"])

    def test_dead_running_attempt_recovers_as_unknown_and_never_reexecutes(self):
        script = r'''
import os, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from operational_history import OperationalHistory
service = OperationalHistory(Path(sys.argv[2]))
proposal = {"capability_id":"system.service.restart", "capability_version":1,
"provider":"fixture_service", "owner":"system", "inputs":{"unit":"demo.service"},
"safety":{"tier":"CHANGE"}, "privilege":"required", "precondition_status":"satisfied",
"verification":{"kind":"service_state","required":True}, "recovery":{"class":"best_effort"},
"affected_objects":["service:systemd:demo.service"]}
row = service.prepare(proposal, correlation_id="corr-dead", provenance={"actor":"operator","interface":"test","request_id":None})
service.authority(row["operation_id"], "approved", "authenticated")
service.running(row["operation_id"])
print(row["operation_id"])
'''
        done = subprocess.run([sys.executable, "-c", script, str(ROOT / "core/lib"), str(self.root)],
                              check=True, text=True, capture_output=True)
        ident = done.stdout.strip()
        recovered = self.history.recover()
        self.assertEqual([episode["operation_id"] for episode in recovered], [ident])
        row = self.history.inspect(ident)
        self.assertEqual(row["lifecycle"], "interrupted")
        self.assertEqual(row["execution_status"], "unknown")
        self.assertEqual(row["outcome"], "interrupted_unknown")
        with self.assertRaises(HistoryError):
            self.history.running(ident)
        self.history.reconcile(ident, "passed", {"source": "fixture_verifier", "state": "active"})
        row = self.history.inspect(ident)
        self.assertEqual(row["outcome"], "interrupted_unknown")
        self.assertEqual(row["verification"]["reconciliation"]["status"], "passed")

    def test_recover_does_not_decode_terminal_history(self):
        terminal_ids = {
            self.record_terminal(tier="READ", privilege="not_required")["operation_id"]
            for _ in range(12)
        }
        original_read = OperationalHistory._read
        calls = []

        def recording_read(db, ident):
            calls.append(ident)
            return original_read(db, ident)

        with patch.object(OperationalHistory, "_read", side_effect=recording_read):
            self.assertEqual(self.history.recover(), [])

        self.assertTrue(terminal_ids)
        self.assertEqual(calls, [])

    def test_export_restore_is_idempotent_and_unknown_versions_fail_closed(self):
        row = self.record_terminal(tier="READ", privilege="not_required")
        export = self.history.export()
        destination = OperationalHistory(self.root / "restore")
        result = destination.restore(export)
        self.assertEqual(result["restored"], 1)
        self.assertEqual(destination.restore(export)["already_present"], True)
        self.assertEqual(destination.inspect(row["operation_id"])["operation_id"], row["operation_id"])
        unsupported = copy.deepcopy(export)
        unsupported["export_version"] = 12
        with self.assertRaises(HistoryError):
            OperationalHistory(self.root / "unsupported").restore(unsupported)

    def test_exporting_running_attempt_restores_as_unknown_without_owner_transfer(self):
        candidate = proposal()
        candidate["inputs"]["note"] = "later-sensitive-value"
        row = prepare(self.history, source=candidate)
        self.history.authority(row["operation_id"], "approved", "authenticated")
        self.history.running(row["operation_id"])
        exported = self.history.export()
        destination = OperationalHistory(self.root / "running-restore")
        first = destination.restore(exported)
        second = destination.restore(exported)
        restored = destination.inspect(row["operation_id"])
        self.assertEqual(first["restored"], 1)
        self.assertTrue(second["already_present"])
        self.assertEqual(restored["lifecycle"], "interrupted")
        self.assertEqual(restored["execution_status"], "unknown")
        self.assertEqual(restored["outcome"], "interrupted_unknown")
        with self.assertRaises(HistoryError):
            destination.running(row["operation_id"])
        with patch.dict(os.environ, {"FIXTURE_PASSWORD": "later-sensitive-value"}):
            recovered = destination.recover()[0]
        self.assertTrue(recovered["inputs_redacted"])
        self.assertNotIn("later-sensitive-value", json.dumps(recovered))

    def test_restore_scrubs_known_environment_secret_from_plain_text_fields(self):
        row = self.record_terminal(tier="READ", privilege="not_required")
        export = self.history.export()
        exported_episode = export["episodes"][0]
        exported_episode["inputs"]["note"] = "plain fixture secret literal"
        with patch.dict(os.environ, {"FIXTURE_PASSWORD": "pw"}):
            export["episodes"][0]["inputs"]["note"] = "pw"
            destination = OperationalHistory(self.root / "secret-restore")
            destination.restore(export)
            raw = (self.root / "secret-restore/operational_history/store.sqlite3").read_bytes()
            inspected = destination.inspect(row["operation_id"])
            second_export = destination.export()
        self.assertFalse(b"pw" in raw, "configured password literal was persisted")
        self.assertNotIn('"pw"', json.dumps(inspected))
        self.assertNotIn('"pw"', json.dumps(second_export))

    def test_running_claim_binds_to_the_live_canonical_proposal(self):
        mutations = (
            ("capability_id", "system.host.memory.refresh"),
            ("capability_version", 2),
            ("provider", "other_provider"),
            ("owner", "other_owner"),
            ("inputs", {"unit": "other.service"}),
            ("safety", {"tier": "DESTROY"}),
            ("privilege", "none"),
            ("affected_objects", ["service:systemd:other.service"]),
            ("verification", {"kind": "different", "required": True}),
            ("recovery", {"class": "irreversible"}),
            ("provider_source_module_version", "2.0.0"),
        )
        for key, value in mutations:
            with self.subTest(field=key), tempfile.TemporaryDirectory() as temp:
                service = OperationalHistory(Path(temp))
                admitted = prepare(service)
                service.authority(admitted["operation_id"], "approved", "authenticated")
                current = proposal()
                current[key] = value
                with self.assertRaises(HistoryError):
                    service.running(admitted["operation_id"], proposal=current)
                self.assertEqual(service.inspect(admitted["operation_id"])["lifecycle"], "admitted")

        with tempfile.TemporaryDirectory() as temp:
            service = OperationalHistory(Path(temp))
            admitted = prepare(service)
            service.authority(admitted["operation_id"], "approved", "authenticated")
            service.running(admitted["operation_id"], proposal=proposal())

    def test_concurrent_prepared_attempts_have_unique_durable_ids(self):
        def create(_):
            return prepare(OperationalHistory(self.root)).get("operation_id")

        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            ids = list(pool.map(create, range(24)))
        self.assertEqual(len(set(ids)), 24)
        self.assertEqual(len(OperationalHistory(self.root).recent(limit=100)), 24)

    def test_concurrent_process_writers_create_all_episodes(self):
        script = r'''
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from operational_history import OperationalHistory
service = OperationalHistory(Path(sys.argv[2]))
proposal = {"capability_id":"system.service.restart", "capability_version":1,
"provider":"fixture_service", "owner":"system", "inputs":{"unit":"demo.service"},
"safety":{"tier":"CHANGE"}, "privilege":"required", "precondition_status":"satisfied",
"verification":{"kind":"service_state","required":True}, "recovery":{"class":"best_effort"},
"affected_objects":["service:systemd:demo.service"]}
for index in range(4):
 row = service.prepare(proposal, correlation_id="process-" + sys.argv[3],
   provenance={"actor":"operator","interface":"subprocess-test","request_id":None})
 print(row["operation_id"])
'''

        def writer(index):
            return subprocess.run([sys.executable, "-c", script, str(ROOT / "core/lib"),
                                   str(self.root / "process-store"), str(index)],
                                  check=True, text=True, capture_output=True).stdout.splitlines()

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            ids = [ident for batch in pool.map(writer, range(4)) for ident in batch]
        store = OperationalHistory(self.root / "process-store")
        self.assertEqual(len(ids), 16)
        self.assertEqual(len(set(ids)), 16)
        self.assertEqual(len(store.recent(limit=100)), 16)


if __name__ == "__main__":
    unittest.main()
