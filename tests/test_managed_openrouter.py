"""Security, restart and crash fences for the existing secret-reference owner."""

import contextlib
import json
import os
import sqlite3
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

import test_openrouter_production as production
from configuration import ConfigurationService
from secret_refs import SecretReferenceError


class ManagedOpenRouterTests(production.ProductionFixture):
    def setUp(self):
        super().setUp()
        self.environment = patch.dict(os.environ, self.env, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.configuration = ConfigurationService(self.data, secret_service=self.service)

    def test_absent_inspection_has_no_side_effects(self):
        before = list(self.data.iterdir())
        self.assertEqual(self.service.status()["availability"], "not_created")
        self.assertEqual(self.service.sanitize("plain", operation_id="request-absent"), "plain")
        self.assertIsNone(self.configuration.resolve_openrouter_credential()["reference"])
        self.assertEqual(list(self.data.iterdir()), before)
        self.assertFalse(self.service.material_dir.exists())
        self.assertFalse(self.capture.exists())

    def test_private_stage_invalid_inputs_and_concurrent_cas(self):
        for value in (b"", b"space key", b"line\nkey", b"\x00", b"\xff"):
            with self.subTest(value=value), self.assertRaises(SecretReferenceError):
                self.service.stage(value, source_kind="private_input", expected_revision=0)
        def stage(value):
            try:
                return self.service.stage(value, source_kind="private_input", expected_revision=0)
            except SecretReferenceError:
                return None
        with ThreadPoolExecutor(max_workers=2) as workers:
            results = list(workers.map(stage, (b"synthetic-first-candidate", b"synthetic-second-candidate")))
        self.assertEqual(sum(value is not None for value in results), 1)
        ticket = next(value for value in results if value)
        state = self.service.status()
        self.assertTrue(state["pending"])
        self.assertFalse(state["cutover"])
        self.assertFalse(self.capture.exists())
        self.assertNotIn("synthetic-", json.dumps(state))
        with self.assertRaises(SecretReferenceError):
            self.service.use(state["reference"], owner="core", purpose="auth", consumer="transport",
                operation_id="request-staged", configuration=self.configuration,
                consume=lambda _fd: self.fail("staging released"))
        self.service.discard_pending(ticket)
        self.assertFalse(self.service.status()["pending"])

    def test_audit_failure_and_unreviewed_consumer_release_nothing(self):
        result = self.install(production.SENTINEL_1)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        ref = self.service.status()["reference"]
        for fields in ({"owner":"module", "purpose":"auth", "consumer":"transport"},
                       {"owner":"core", "purpose":"context", "consumer":"transport"},
                       {"owner":"core", "purpose":"auth", "consumer":"redaction"},
                       {"owner":"core", "purpose":"auth", "consumer":"authorized"}):
            with self.subTest(fields=fields), self.assertRaises(SecretReferenceError):
                self.service.use(ref, **fields, operation_id="request-denied",
                    configuration=self.configuration, consume=lambda _fd: self.fail("denied release"))
        with self.service._store() as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM access WHERE outcome='denied'").fetchone()[0], 4)
        original = self.service._store
        @contextlib.contextmanager
        def audit_failure(*, write=False):
            if write:
                raise SecretReferenceError("synthetic audit failure")
            with original() as db:
                yield db
        with patch.object(self.service, "_store", audit_failure), self.assertRaises(SecretReferenceError):
            self.service.use(ref, owner="core", purpose="auth", consumer="transport",
                operation_id="request-audit-failure", configuration=self.configuration,
                consume=lambda _fd: self.fail("audit failure released"))
        # Production final socket must also remain unopened on failed access audit.
        self.env["FIXTURE_DENY_AUDIT"] = "1"
        fixture = self.root / "socket-fixture/sitecustomize.py"
        fixture.write_text(fixture.read_text() + '\nif os.environ.get("FIXTURE_DENY_AUDIT"):\n    import sqlite3\n    _execute = sqlite3.Connection.execute\n    class AuditDenied(sqlite3.Connection):\n        def execute(self, sql, *args, **kwargs):\n            if sql.startswith("INSERT INTO access"): raise sqlite3.OperationalError("synthetic audit denied")\n            return super().execute(sql,*args,**kwargs)\n    _connect = sqlite3.connect\n    def denied_connect(*args, **kwargs):\n        kwargs["factory"] = AuditDenied\n        return _connect(*args, **kwargs)\n    sqlite3.connect = denied_connect\n')
        count = len(self.records())
        self.request(route="direct")
        self.assertEqual(len(self.records()), count)

    def test_staging_io_failures_retain_prior_authority(self):
        self.assertEqual(self.install(production.SENTINEL_1).returncode, 0)
        before = self.service.status()
        generations = sorted(self.service.material_dir.iterdir())
        with patch("secret_refs.os.fsync", side_effect=OSError("synthetic material fence failure")), self.assertRaises(SecretReferenceError):
            self.service.stage(production.SENTINEL_2.encode(), source_kind="private_input", expected_revision=1)
        original_store = self.service._store
        class PublicationFailure:
            def __init__(self, db):
                self.db = db
            def execute(self, sql, *args):
                if sql.startswith("UPDATE reference SET pending="):
                    raise sqlite3.OperationalError("synthetic metadata publication failure")
                return self.db.execute(sql, *args)
        @contextlib.contextmanager
        def failed_publication(*, write=False):
            with original_store(write=write) as db:
                yield PublicationFailure(db) if write else db
        with patch.object(self.service, "_store", failed_publication), self.assertRaises(SecretReferenceError):
            self.service.stage(production.SENTINEL_2.encode(), source_kind="private_input", expected_revision=1)
        self.assertEqual(sorted(self.service.material_dir.iterdir()), generations)
        self.assertEqual(self.service.status()["generation"], before["generation"])
        self.assertEqual(self.service.status()["revision"], 1)
        self.assertFalse(self.service.status()["pending"])
        self.request(route="direct")
        self.assert_request(production.SENTINEL_1)

    def test_symlink_modes_unknown_schema_scope_and_binding_fail_closed(self):
        self.assertEqual(self.install(production.SENTINEL_1).returncode, 0)
        with self.service._store() as db:
            name = self.service._row(db)[2]
        material = self.service.material_dir / name
        material.chmod(0o644)
        self.assertEqual(self.service.status()["availability"], "unsafe_or_missing")
        count = len(self.records())
        self.request(route="direct")
        self.assertEqual(len(self.records()), count)
        material.chmod(0o600)
        retained = self.secrets / "protected-original"
        material.rename(retained)
        material.symlink_to(retained)
        self.assertEqual(self.service.status()["availability"], "unsafe_or_missing")
        with self.assertRaises(SecretReferenceError):
            self.service.sanitize("plain", operation_id="request-link")
        material.unlink()
        retained.rename(material)
        for statement, parameters, reverse in (
            ("UPDATE metadata SET value=?", ("99",), ("1",)),
            ("UPDATE reference SET binding=?", ("untrusted.authorized",), ("core.openrouter.v1",)),
            ("UPDATE reference SET scope_id=?", ("scope:"+"0"*32,), (self.service.status()["scope_id"],))):
            with sqlite3.connect(self.service.db_path) as db:
                db.execute(statement, parameters)
            with self.assertRaises(SecretReferenceError):
                self.service.status()
            self.assertTrue(material.exists())
            with sqlite3.connect(self.service.db_path) as db:
                db.execute(statement, reverse)

    def test_stream_projection_handles_split_echo_and_preserves_identifiers(self):
        self.assertEqual(self.install(production.SENTINEL_1).returncode, 0)
        project = self.service._response_projector(operation_id="request-stream", admitted=production.SENTINEL_1.encode())
        self.assertEqual(project(b"systemd-networkd.service TCP/443 hello "), b"systemd-networkd.service TCP/443 hello ")
        key = production.SENTINEL_1.encode()
        self.assertEqual(project(key[:9]), b"")
        self.assertEqual(project(key[9:]+b" safe"), b"[REDACTED] safe")
        self.assertEqual(project(b"", final=True), b"")
        audit = self.data / "secrets/private-access.jsonl"
        audit.chmod(0o644)
        with self.assertRaises(SecretReferenceError):
            self.service.sanitize(production.SENTINEL_1, operation_id="request-redaction-failed")

    def test_approval_decline_and_private_frontend_projection(self):
        result = self.install(production.SENTINEL_1, mode="assist")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.capture.exists())
        self.assertFalse(self.service.status()["pending"])
        self.assertEqual(self.install(production.SENTINEL_1).returncode, 0)
        self.env["IGOR_AI_EVENT_STREAM"] = str(self.root / "runtime/events.jsonl")
        result = self.shell('source "$IGOR_DIR/core/ai/core.sh"; IFS= read -r display; _ai_frontend_event action_output "$display" succeeded',
            private_input="systemd-networkd.service TCP/443 " + production.SENTINEL_1 + "\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        event = json.loads((self.root / "runtime/events.jsonl").read_text().splitlines()[-1])
        self.assertEqual(event["display"], "systemd-networkd.service TCP/443 [REDACTED]")
        projected = self.shell('source "$IGOR_DIR/core/ai/safety.sh"; IFS= read -r output; _ai_sanitize_selected_output "$output"', private_input="systemd-networkd.service TCP/443 " + production.SENTINEL_1 + "\n")
        self.assertEqual(projected.returncode, 0, projected.stderr)
        self.assertEqual(projected.stdout, "systemd-networkd.service TCP/443 [REDACTED]")
        from domain_event import EventError, publish
        with self.assertRaises(EventError):
            publish("core.fixture.echo", {"message":production.SENTINEL_1}, owner="core", source="core.fixture",
                schema={"properties":{"message":{"type":"string"}}, "required":["message"], "additionalProperties":False})

        exported = self.shell('source "$IGOR_DIR/core/lib/configuration.sh"; igor_configuration_cli export')
        self.assertEqual(exported.returncode, 0, exported.stderr)
        self.assertNotIn(production.SENTINEL_1, exported.stdout)
        for path in self.data.rglob("*"):
            if path.is_file():
                self.assertNotIn(production.SENTINEL_1.encode(), path.read_bytes(), str(path))

    def test_configuration_restore_cannot_clear_or_replace_managed_authority(self):
        self.assertEqual(self.install(production.SENTINEL_1).returncode, 0)
        export = self.configuration.export()
        reference = self.service.status()["reference"]
        export["records"] = []
        with self.assertRaises(ValueError):
            self.configuration.prepare_restore(export)
        self.assertEqual(self.configuration.resolve_openrouter_credential()["reference"], reference)
        # Metadata-only restoration preserves the fence without material.
        export = self.configuration.export()
        with self.service._store() as db:
            name = self.service._row(db)[2]
        (self.service.material_dir / name).unlink()
        changes = self.configuration.prepare_restore(export)
        self.assertEqual(changes[0]["value"], {"reference": reference})
        self.assertNotEqual(self.service.status()["availability"], "available")
        audit = self.data / "secrets/private-access.jsonl"
        before = audit.read_bytes()
        self.configuration.inspect("ai.openrouter.credential", "installation:local")
        self.service.status()
        self.assertEqual(audit.read_bytes(), before)

    def test_crash_after_config_commit_has_explicit_canonical_resume(self):
        # Inject *only* the cutover crash, in the actual Configuration CLI.
        fixture = self.root / "socket-fixture/sitecustomize.py"
        fixture.write_text(fixture.read_text() + '\nif os.environ.get("FIXTURE_CRASH_ACTIVATION"):\n    sys.path.insert(0, os.environ["IGOR_DIR"]+"/core/lib")\n    import secret_refs\n    def crash(*args, **kwargs): os.killpg(os.getpgrp(), 9)\n    secret_refs.ManagedOpenRouterSecret.activate = crash\n')
        self.env["FIXTURE_CRASH_ACTIVATION"] = "1"
        self.assertNotEqual(self.install(production.SENTINEL_1).returncode, 0)
        state = self.service.status()
        self.assertTrue(state["pending"])
        self.assertFalse(state["cutover"])
        reference = self.configuration.resolve_openrouter_credential()["reference"]
        self.assertEqual(reference, state["reference"])
        count = len(self.records())
        self.request(route="direct")
        self.assertEqual(len(self.records()), count)
        del self.env["FIXTURE_CRASH_ACTIVATION"]
        resumed = self.shell('source "$IGOR_DIR/core/lib/module_loader.sh"; source "$IGOR_DIR/core/ai/core.sh"; ai_mode=executive; _ai_openrouter_resume_pending')
        self.assertEqual(resumed.returncode, 0, resumed.stdout + resumed.stderr)
        self.request(route="direct")
        self.assert_request(production.SENTINEL_1)
        self.assertFalse(self.service.status()["pending"])
        self.assertEqual(self.service.status()["reference"], reference)


    def test_rotation_refuses_configuration_race_and_explicit_resume_revalidates(self):
        self.assertEqual(self.install(production.SENTINEL_1).returncode, 0)
        first = self.service.status()
        self.env["FIXTURE_CONFIG_RACE"] = "1"
        self.assertNotEqual(self.install(production.SENTINEL_2).returncode, 0)
        self.assertEqual(self.service.status()["generation"], first["generation"])
        self.assertEqual(self.service.status()["revision"], 1)
        self.assertTrue(self.service.status()["pending"])
        del self.env["FIXTURE_CONFIG_RACE"]
        self.request(route="direct")
        self.assert_request(production.SENTINEL_1)
        resumed = self.shell('source "$IGOR_DIR/core/lib/module_loader.sh"; source "$IGOR_DIR/core/ai/core.sh"; ai_mode=executive; _ai_openrouter_resume_pending')
        self.assertEqual(resumed.returncode, 0, resumed.stdout + resumed.stderr)
        self.request(route="direct")
        self.assert_request(production.SENTINEL_2)

    def test_crash_after_activation_retirement_replay_is_idempotent(self):
        self.assertEqual(self.install(production.SENTINEL_1).returncode, 0)
        self.assertEqual(self.install(production.SENTINEL_2).returncode, 0)
        fixture = self.root / "socket-fixture/sitecustomize.py"
        fixture.write_text(fixture.read_text() + '\nif os.environ.get("FIXTURE_CRASH_RETIREMENT"):\n    sys.path.insert(0, os.environ["IGOR_DIR"]+"/core/lib")\n    import secret_refs\n    def crash(*args, **kwargs): os.killpg(os.getpgrp(),9)\n    secret_refs.ManagedOpenRouterSecret._finish_retirement = crash\n')
        self.env["FIXTURE_CRASH_RETIREMENT"] = "1"
        self.assertNotEqual(self.install(production.SENTINEL_3).returncode, 0)
        current = self.service.status()
        self.assertEqual(current["revision"], 3)
        self.assertTrue(current["retirement_pending"])
        del self.env["FIXTURE_CRASH_RETIREMENT"]
        from operational_history import OperationalHistory
        episode = OperationalHistory(self.data).inspect(current["last_operation_id"])
        request = {"igor_dir":str(self.root), "data_dir":str(self.data), "active_owners":["core"],
            "operation_id":episode["operation_id"], **episode["inputs"]}
        replayed = self.shell('python3 "$IGOR_DIR/core/lib/configuration.py" openrouter-rotate', private_input=json.dumps(request))
        self.assertEqual(replayed.returncode, 0, replayed.stdout + replayed.stderr)
        self.assertFalse(self.service.status()["retirement_pending"])
        self.assertEqual(len(list(self.service.material_dir.glob("g*"))), 2)
        again = self.shell('python3 "$IGOR_DIR/core/lib/configuration.py" openrouter-rotate', private_input=json.dumps(request))
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(self.service.status()["revision"], 3)
        request["ticket"] = "0" * 48
        denied = self.shell('python3 "$IGOR_DIR/core/lib/configuration.py" openrouter-rotate', private_input=json.dumps(request))
        self.assertNotEqual(denied.returncode, 0)
        self.request(route="direct")
        self.assert_request(production.SENTINEL_3)
