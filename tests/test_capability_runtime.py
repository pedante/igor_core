import copy
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, "core/lib")
from capability_runtime import (
    CapabilityDescriptor,
    CapabilityError,
    CapabilityPlan,
    CapabilityRegistry,
    ProviderExecutionError,
    SecretReference,
    _privileged_commands,
    admit_handler,
    execute_privileged,
    execute_unprivileged,
    execution_fence,
    execution_result,
    finalize_preparation,
    local_preconditions,
    nonexecution_result,
    validate_inputs,
    validate_output_schema,
    validate_outputs,
)
from operational_history import HistoryError, OperationalHistory


def descriptor(**changes):
    value = {
        "id": "system.service.restart", "owner": "system", "provider": "system",
        "handler": "system__restart", "capability_version": 1,
        "description": "restart", "inputs": {"properties": {"unit": {"type": "string", "validator": "systemd_unit"}}, "required": ["unit"], "additionalProperties": False},
        "safety": {"tier": "CHANGE"}, "privilege": "required", "preconditions": [],
        "verification": {"required": True}, "recovery": {"class": "best_effort"},
        "affects": [{"object": "service", "input": "unit"}],
    }
    value.update(changes)
    return CapabilityDescriptor.from_dict(value)


class CapabilityRuntimeTests(unittest.TestCase):
    def unprivileged_attempt(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        registry = CapabilityRegistry()
        registry.register(descriptor(privilege="none", handler="system__read"))
        proposal = finalize_preparation(registry.prepare("system.service.restart", {"unit": "demo.service"}), [], "satisfied", "1.0.0")
        admission = {"owner": "system", "state": "active", "handler": "system__read", "timeout": 30,
                     "entrypoint": "module.sh", "package": str(root), "source_version": "1.0.0"}
        history = OperationalHistory(root / "data")
        episode = history.prepare(proposal, correlation_id="corr-unprivileged-runtime",
                                  provenance={"actor": "operator", "interface": "capability_api", "request_id": None})
        request = {"proposal": proposal, "fresh": copy.deepcopy(proposal), "digest": proposal["digest"],
                   "admission": admission, "operation_id": episode["operation_id"], "approval": "approved",
                   "collection": False, "data_dir": str(root / "data")}
        return request, history, root

    def test_unprivileged_sequence_claims_before_source_and_cannot_replay(self):
        request, history, _ = self.unprivileged_attempt()

        def observe(*args, **options):
            row = history.inspect(request["operation_id"])
            self.assertEqual([item["state"] for item in row["transitions"]], ["admitted", "authority", "running"])
            self.assertEqual(row["privilege"]["result"], "not_required")
            self.assertEqual(args[1:5], ("system", "system__read", "system.service.restart", 30))
            self.assertEqual(json.loads(args[5]), request["fresh"]["inputs"])
            self.assertNotIn("V2_HANDLER_EXECUTION_CONTEXT", options["env"])
            return b'{"status":"ok","result":{}}'

        with patch("module_handler.invoke", side_effect=observe) as run:
            self.assertIn(b'"ok"', execute_unprivileged(request, history))
            with self.assertRaises(HistoryError):
                execute_unprivileged(request, history)
            self.assertEqual(run.call_count, 1)

    def test_unprivileged_refuses_changed_admission_fence_or_authority_before_effect(self):
        for kind in ("owner", "state", "handler", "timeout", "entrypoint", "package", "source_version",
                     "approval", "digest", "drift", "precondition", "privilege", "commands", "history"):
            with self.subTest(kind=kind):
                request, history, _ = self.unprivileged_attempt()
                if kind in request["admission"]:
                    request["admission"][kind] = 1 if kind == "timeout" else "" if kind in {"entrypoint", "package"} else "changed"
                elif kind == "approval":
                    request["approval"] = "cancelled"
                elif kind == "digest":
                    request["digest"] = "wrong"
                elif kind == "drift":
                    request["fresh"]["inputs"]["unit"] = "other.service"
                elif kind == "precondition":
                    request["fresh"]["precondition_status"] = "failed"
                elif kind == "privilege":
                    request["fresh"]["privilege"] = "required"
                elif kind == "commands":
                    request["fresh"]["privileged_argv"] = ["true"]
                else:
                    request["operation_id"] = "op-" + "0" * 32
                with patch("module_handler.invoke") as run, self.assertRaises((CapabilityError, HistoryError)):
                    execute_unprivileged(request, history)
                run.assert_not_called()

    def test_unprivileged_partial_effect_failure_stays_claimed_and_never_replays(self):
        request, history, root = self.unprivileged_attempt()
        marker = root / "effect"
        (root / "module.sh").write_text(f"system__read() {{ touch '{marker}'; return 7; }}\n")
        with self.assertRaises(ProviderExecutionError):
            execute_unprivileged(request, history)
        self.assertTrue(marker.exists())
        self.assertEqual(history.inspect(request["operation_id"])["lifecycle"], "running")
        with self.assertRaises(HistoryError):
            execute_unprivileged(request, history)

    def test_unprivileged_malformed_requests_fail_before_claim_without_leaking(self):
        request, history, _ = self.unprivileged_attempt()
        for change in ({"collection": "false"}, {"extra": "private-sentinel"}):
            with self.subTest(change=change), self.assertRaises(CapabilityError):
                execute_unprivileged({**request, **change}, history)
        for descriptor_value in (None, 42, "private-sentinel"):
            malformed = copy.deepcopy(request)
            malformed["fresh"]["descriptor"] = descriptor_value
            with self.subTest(descriptor=descriptor_value), self.assertRaises(CapabilityError):
                execute_unprivileged(malformed, history)
        self.assertEqual(history.inspect(request["operation_id"])["lifecycle"], "admitted")
        for raw in ("private-sentinel", "[]", '{"x":1,"x":2}', '{"data_dir":"private-sentinel"}'):
            result = subprocess.run([sys.executable, "core/lib/capability_runtime.py", "execute-unprivileged"],
                                    input=raw, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 2)
            self.assertFalse(result.stdout)
            self.assertNotIn("private-sentinel", result.stderr)

    def test_unprivileged_cli_cancellation_reaps_child_and_retains_unknown_claim(self):
        request, history, root = self.unprivileged_attempt()
        child = root / "child"
        (root / "module.sh").write_text(f"system__read() {{ trap '' TERM; sleep 30 & echo $! > '{child}'; wait; }}\n")
        process = subprocess.Popen([sys.executable, "core/lib/capability_runtime.py", "execute-unprivileged"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        pid = None
        try:
            process.stdin.write(json.dumps(request).encode())
            process.stdin.close()
            process.stdin = None
            deadline = time.monotonic() + 3
            while not child.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(child.exists())
            pid = int(child.read_text())
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=3)
            self.assertEqual(process.returncode, 3)
            self.assertFalse(stdout)
            self.assertIn(b"cancelled", stderr)
            row = history.inspect(request["operation_id"])
            self.assertEqual(row["execution_status"], "running")
            with self.assertRaises(HistoryError):
                execute_unprivileged(request, history)
            stat = Path(f"/proc/{pid}/stat")
            self.assertTrue(not stat.exists() or stat.read_text().rsplit(") ", 1)[1].startswith("Z "))
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate()
            if pid is not None:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_python_preparation_preconditions_and_digest(self):
        request, _, root = self.unprivileged_attempt()
        proposal = request["fresh"]
        proposal["preconditions"] = [{"kind": "owner_active"}, {"kind": "path_exists", "input": "path"}]
        proposal["descriptor"]["inputs"]["properties"]["path"] = {"type": "path", "root": str(root)}
        proposal["inputs"]["path"] = "present"
        self.assertFalse(local_preconditions(proposal, True))
        (root / "present").touch()
        self.assertTrue(local_preconditions(proposal, True))
        self.assertFalse(local_preconditions(proposal, False))
        (root / "link").symlink_to(root / "present")
        for value in ("link", "../escape", "/etc/passwd"):
            proposal["inputs"]["path"] = value
            self.assertFalse(local_preconditions(proposal, True))
        finalized = finalize_preparation(proposal, [], "failed", "1.0.0")
        self.assertEqual(finalize_preparation(finalized, [], "failed", "1.0.0"), finalized)
        self.assertEqual(execution_fence(finalized, finalized, finalized["digest"]), "precondition_failed")
        with self.assertRaises(CapabilityError):
            finalize_preparation(proposal, ["sudo"], "satisfied", "1.0.0")
        for state in ("inactive", "unavailable", "unknown"):
            with self.assertRaises(CapabilityError):
                admit_handler(request["fresh"], {**request["admission"], "state": state})

    def privileged_attempt(self, proposal=None):
        proposal = proposal or self.execution_proposal()
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        history = OperationalHistory(Path(directory.name))
        episode = history.prepare(proposal, correlation_id="corr-native-runtime",
                                  provenance={"actor": "operator", "interface": "capability_api", "request_id": None})
        return proposal, history, episode["operation_id"]

    def test_privileged_runtime_claims_history_before_effect_and_refuses_duplicate(self):
        proposal, history, ident = self.privileged_attempt()

        def observe(argv, **options):
            row = history.inspect(ident)
            self.assertEqual([item["state"] for item in row["transitions"]], ["admitted", "authority", "running"])
            self.assertEqual(row["privilege"]["result"], "authenticated")
            self.assertEqual(argv, proposal["privileged_argv"])
            self.assertEqual(options, {"check": False, "stdin": subprocess.DEVNULL,
                                       "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL, "timeout": 1800})
            return subprocess.CompletedProcess(argv, 0)

        with patch("capability_runtime.subprocess.run", side_effect=observe) as run:
            self.assertEqual(execute_privileged(proposal, proposal, proposal["digest"], history, ident, "approved", "debian"), "succeeded")
            with self.assertRaises(HistoryError):
                execute_privileged(proposal, proposal, proposal["digest"], history, ident, "approved", "debian")
            self.assertEqual(run.call_count, 1)
        self.assertEqual(history.inspect(ident)["lifecycle"], "running")

    def test_privileged_runtime_refuses_drift_bad_argv_and_authority_before_effect(self):
        for kind in ("digest", "drift", "precondition", "privilege", "argv", "approval", "authentication", "history"):
            with self.subTest(kind=kind):
                proposal, history, ident = self.privileged_attempt()
                fresh = copy.deepcopy(proposal)
                digest, approval = proposal["digest"], "approved"
                if kind == "digest":
                    digest = "wrong"
                elif kind == "drift":
                    fresh["inputs"]["unit"] = "other.service"
                elif kind == "precondition":
                    fresh["precondition_status"] = "failed"
                elif kind == "privilege":
                    proposal["privilege"] = fresh["privilege"] = "none"
                elif kind == "argv":
                    proposal["privileged_argv"] = fresh["privileged_argv"] = ["sudo", "sh", "-c", "bad"]
                elif kind == "approval":
                    approval = "denied"
                elif kind == "authentication":
                    history.authority(ident, "approved", "failed")
                elif kind == "history":
                    ident = "op-" + "0" * 32
                with patch("capability_runtime.subprocess.run") as run, self.assertRaises((CapabilityError, HistoryError)):
                    execute_privileged(proposal, fresh, digest, history, ident, approval, "debian")
                run.assert_not_called()

    def test_privileged_sequence_is_ordered_and_stops_on_failure_or_unavailable_process(self):
        commands = [["sudo", "-n", "--", "apt-get", "update"], ["sudo", "-n", "--", "apt-get", "upgrade", "-y"]]
        for failure in (None, 17, FileNotFoundError(), subprocess.TimeoutExpired(commands[0], 1800)):
            with self.subTest(failure=type(failure).__name__):
                proposal = self.execution_proposal()
                proposal.update(capability_id="system.package.upgrade", inputs={}, privileged_argv=commands)
                proposal, history, ident = self.privileged_attempt(proposal)
                effect = failure if isinstance(failure, Exception) else None
                result = subprocess.CompletedProcess(commands[0], failure or 0)
                with patch("capability_runtime.subprocess.run", side_effect=effect, return_value=result) as run:
                    status = execute_privileged(proposal, proposal, proposal["digest"], history, ident, "approved", "debian")
                self.assertEqual(status, "failed" if failure is not None else "succeeded")
                self.assertEqual([call.args[0] for call in run.call_args_list], commands[:1] if failure is not None else commands)
                self.assertEqual(history.inspect(ident)["lifecycle"], "running")

    def test_privileged_adapter_matrix_preserves_exact_native_commands(self):
        prefix = ["sudo", "-n", "--"]
        cases = [("system.service." + verb, "unknown", [prefix + ["systemctl", verb, "demo.service"]], False)
                 for verb in ("start", "restart", "enable")]
        cases.extend([
            ("system.storage.mount", "unknown", [prefix + ["mkdir", "-p", "--", "/mnt/demo"], prefix + ["mount", "--", "/dev/demo", "/mnt/demo"]], True),
            ("system.storage.unmount", "unknown", [prefix + ["umount", "--", "/mnt/demo"]], True),
            ("system.network.wifi.connect_known", "unknown", [prefix + ["nmcli", "--wait", "30", "connection", "up", "uuid", "12345678-1234-1234-1234-123456789abc", "ifname", "wlan0"]], True),
        ])
        for field, command, value in (("owner", "chown", "1000"), ("group", "chgrp", "1000"), ("mode", "chmod", "0750")):
            cases.append((f"system.permissions.{field}.set", "unknown", [prefix + [command, "--", value, "/srv/demo"]], True))
        for family, install, upgrade, clean in (
            ("debian", ["apt-get", "install", "-y", "demo"], [["apt-get", "update"], ["apt-get", "upgrade", "-y"]], ["apt-get", "clean"]),
            ("arch", ["pacman", "-S", "--noconfirm", "demo"], [["pacman", "-Syu", "--noconfirm"]], ["pacman", "-Sc", "--noconfirm"]),
        ):
            cases.extend([("system.package.install", family, [prefix + install], False),
                          ("system.package.upgrade", family, [prefix + row for row in upgrade], True),
                          ("system.package.cache.clean", family, [prefix + clean], True)])
        for ident, family, commands, nested in cases:
            with self.subTest(ident=ident, family=family):
                spec = commands if nested else commands[0]
                self.assertEqual(_privileged_commands(spec, ident, family), commands)
                for bad in (None, [], "sudo", ["sudo", "sh"], commands + [["sudo", "sh"]]):
                    with self.assertRaises(CapabilityError):
                        _privileged_commands(bad, ident, family)
        for bad in ([prefix + ["umount", "--", "/mnt/../etc"]], [prefix + ["umount", "--", "/etc"]]):
            with self.assertRaises(CapabilityError):
                _privileged_commands(bad, "system.storage.unmount", "unknown")

    def test_privileged_cli_rejects_malformed_arguments_without_exposing_them(self):
        for args in ([], ["private-sentinel"] * 7, ['{"x":1,"x":2}'] * 7):
            result = subprocess.run([sys.executable, "core/lib/capability_runtime.py", "execute-privileged", *args], capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, "")
            self.assertNotIn("private-sentinel", result.stderr)
            self.assertIn("privileged execution unavailable", result.stderr)

    def execution_proposal(self, *, tier="CHANGE", version=1):
        registry = CapabilityRegistry()
        registry.register(descriptor())
        proposal = registry.prepare("system.service.restart", {"unit": "demo.service"})
        proposal.update(precondition_status="satisfied", privileged_argv=["sudo", "-n", "--", "systemctl", "restart", "demo.service"])
        proposal["safety"]["tier"] = tier
        proposal["capability_version"] = version
        return proposal

    def test_execution_fence_requires_approval_and_exact_content_even_with_same_digest(self):
        proposal = self.execution_proposal()
        self.assertEqual(execution_fence(proposal, copy.deepcopy(proposal), proposal["digest"]), "ready")
        for approval in ("", "another-digest"):
            with self.assertRaises(CapabilityError):
                execution_fence(proposal, proposal, approval, inspection=True)
        for field in ("owner", "provider", "inputs", "descriptor", "safety", "privilege", "privileged_argv", "affected_objects", "recovery", "source"):
            with self.subTest(field=field):
                fresh = {**proposal, field: "changed"}
                with self.assertRaises(CapabilityError):
                    execution_fence(proposal, fresh, proposal["digest"])
                self.assertEqual(execution_fence(proposal, fresh, proposal["digest"], inspection=True), "inspection_unavailable")
        with self.assertRaises(CapabilityError):
            execution_fence(proposal, {**proposal, "capability_version": True}, proposal["digest"])

    def test_execution_fence_allows_only_precondition_status_to_change_on_refusal(self):
        proposal = self.execution_proposal()
        fresh = {**proposal, "precondition_status": "failed", "digest": "new-digest"}
        self.assertEqual(execution_fence(proposal, fresh, proposal["digest"]), "precondition_failed")
        for changes in ({"privileged_argv": []}, {"owner": "other"}, {"precondition_status": "unknown"}):
            with self.assertRaises(CapabilityError):
                execution_fence(proposal, {**fresh, **changes}, proposal["digest"], inspection=True)

    def test_execution_outcomes_derive_from_execution_output_and_verification(self):
        cases = [
            ("READ", "succeeded", "not_applicable", "success"),
            ("READ", "succeeded", "failed", "unverified_result"),
            ("READ", "succeeded", "unknown", "unverified_result"),
            ("CHANGE", "succeeded", "passed", "success"),
            ("DESTROY", "succeeded", "passed", "success"),
            ("CHANGE", "succeeded", "failed", "unverified_change"),
            ("CHANGE", "succeeded", "not_applicable", "unverified_change"),
            ("CHANGE", "succeeded", "unavailable", "unverified_change"),
            ("CHANGE", "failed", "passed", "failed"),
        ]
        for tier, execution, verification, outcome in cases:
            for version in (1, 2, 3):
                with self.subTest(tier=tier, execution=execution, verification=verification, version=version):
                    proposal = self.execution_proposal(tier=tier, version=version)
                    result = execution_result(proposal, execution, verification, {"source": "test"}, "approved", "op-test", "valid", {"count": 1})
                    self.assertEqual(result["outcome"], outcome)
                    self.assertEqual(result["operation_id"], "op-test")
                    self.assertEqual(result["verification_evidence"], [{"source": "test"}])
                    self.assertEqual(result["privilege_status"], "authenticated")
                    self.assertEqual("result" in result, version >= 2)

    def test_unusable_typed_output_preserves_effect_and_never_claims_success(self):
        for version in (2, 3):
            for output, domain in (("invalid", {"count": 1}), ("not_applicable", None), ("valid", None)):
                result = execution_result(self.execution_proposal(version=version), "succeeded", "passed", {}, "approved", "op-test", output, domain)
                self.assertEqual(result["execution_status"], "succeeded")
                self.assertEqual(result["outcome"], "invalid_output")
                self.assertEqual(result["verification_status"], "unknown")
                self.assertIsNone(result["result"])
        oversized = execution_result(self.execution_proposal(version=3), "succeeded", "passed", {}, "approved", "op-test", "valid", {"text": "x" * 100000})
        self.assertEqual(oversized["outcome"], "invalid_output")
        self.assertEqual(oversized["verification_evidence"][0]["reason"], "collection_limit_exceeded")
        with self.assertRaises(CapabilityError):
            execution_result(self.execution_proposal(), "running", "passed", {}, "approved", "op-test", "valid", {})

    def test_nonexecution_preserves_identity_and_refusal_without_inventing_effect(self):
        proposal = self.execution_proposal(version=2)
        for reason, approval, privilege in (("approval_denied", "denied", ""), ("privilege_failed", "approved", "failed"), ("precondition_failed", "approved", "")):
            result = nonexecution_result(proposal, reason, approval, privilege, "op-test", "inspection_unavailable")
            self.assertEqual(result["outcome"], reason)
            self.assertEqual(result["execution_status"], "not_executed")
            self.assertEqual(result["verification_status"], "not_applicable")
            self.assertEqual(result["privilege_status"], privilege or "not_requested")
            self.assertEqual(result["precondition_status"], "failed" if reason == "precondition_failed" else "satisfied")
            self.assertNotIn("result", result)
        self.assertEqual(proposal["precondition_status"], "satisfied")

    def test_coordination_cli_rejects_malformed_private_input_without_echoing_it(self):
        for args in (("execution-fence", '{"private":"SENTINEL","private":2}', "{}", "digest", "1"), ("execution-fence", "[]", "{}", "digest", "1"), ("execution-result", "SENTINEL"), ("nonexecution-result", "SENTINEL")):
            result = subprocess.run([sys.executable, "core/lib/capability_runtime.py", *args], text=True, capture_output=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("SENTINEL", result.stdout + result.stderr)

    def test_version_two_requires_closed_typed_output_and_exact_consumer_version(self):
        outputs = {"schema_version": 1, "properties": {"observer_id": {"type": "enum", "enum": ["host.memory"]}}, "required": ["observer_id"], "additionalProperties": False}
        cap = descriptor(capability_version=2, outputs=outputs)
        registry = CapabilityRegistry()
        registry.register(cap)
        proposal = registry.prepare(cap.id, {"unit": "demo.service"}, capability_version=2)
        self.assertEqual(proposal["descriptor"]["outputs"], outputs)
        for version in (1, True, "2", 3):
            with self.assertRaises(CapabilityError):
                registry.prepare(cap.id, {"unit": "demo.service"}, capability_version=version)
        with self.assertRaises(CapabilityError):
            descriptor(capability_version=2)
        with self.assertRaises(CapabilityError):
            descriptor(outputs=outputs)
        plan = CapabilityPlan("typed result", [{"capability_id": cap.id, "inputs": {"unit": "demo.service"}, "capability_version": 2}]).resolve(registry)
        self.assertEqual(plan.steps[0]["capability_version"], 2)
        for version in (1, None, True, 3):
            with self.assertRaises(CapabilityError):
                CapabilityPlan("mismatch", [{"capability_id": cap.id, "inputs": {"unit": "demo.service"}, "capability_version": version}]).resolve(registry)

    def test_output_schema_and_values_are_bounded_without_authority(self):
        schema = {"schema_version": 1, "properties": {"count": {"type": "integer", "minimum": 0, "maximum": 100}, "label": {"type": "string", "maxLength": 4}}, "required": ["count"], "additionalProperties": False}
        self.assertEqual(validate_outputs(schema, {"count": 2, "label": "host"}), {"count": 2, "label": "host"})
        for value in ({}, {"count": True}, {"count": float("nan")}, {"count": 101}, {"count": 2, "label": "longer"}, {"count": 2, "owner": "core"}, {"count": 10**400}):
            with self.assertRaises(CapabilityError):
                validate_outputs(schema, value)
        for spec in ({"type": "secret_ref"}, {"type": "integer", "maximum": float("inf")}, {"type": "integer", "maximum": 10**400}, {"type": "string", "maxLength": 99999}, {"type": "boolean", "unknown": 1}):
            with self.assertRaises(CapabilityError):
                validate_output_schema({**schema, "properties": {"count": spec}})

    def test_output_cli_rejects_duplicate_json_and_never_prints_rejected_values(self):
        schema = {"schema_version": 1, "properties": {"label": {"type": "string", "maxLength": 4}}, "required": ["label"], "additionalProperties": False}
        for envelope in ('{"status":"ok","result":{"label":"ok","label":"REJECTED_SECRET_VALUE"}}', '{"status":"ok","result":{"label":"REJECTED_SECRET_VALUE"}}'):
            result = subprocess.run([sys.executable, "core/lib/capability_runtime.py"], input=json.dumps({"op": "output", "outputs": schema, "envelope": envelope}), text=True, capture_output=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("REJECTED_SECRET_VALUE", result.stdout + result.stderr)

    def test_handler_output_bridge_preserves_provider_vs_typed_output_failures(self):
        schema = {
            "schema_version": 1,
            "properties": {"count": {"type": "integer", "minimum": 0, "maximum": 10}},
            "required": ["count"],
            "additionalProperties": False,
        }
        command = [sys.executable, "core/lib/capability_runtime.py", "handler-output",
                   json.dumps(schema, separators=(",", ":"))]

        valid = subprocess.run(
            command, input='{"status":"ok","result":{"count":2}}',
            text=True, capture_output=True, check=False,
        )
        self.assertEqual(valid.returncode, 0)
        self.assertEqual(json.loads(valid.stdout), {"count": 2})

        for envelope in (
            '{"status":"error","error":{"code":"unavailable","message":"sensor missing"}}',
            'not-json',
            '{"status":"ok","result":{"count":2},"tier":"READ"}',
        ):
            failed = subprocess.run(command, input=envelope, text=True,
                                    capture_output=True, check=False)
            self.assertEqual(failed.returncode, 2)

        invalid_output = subprocess.run(
            command, input='{"status":"ok","result":{"count":99}}',
            text=True, capture_output=True, check=False,
        )
        self.assertEqual(invalid_output.returncode, 3)
        self.assertNotIn("99", invalid_output.stdout + invalid_output.stderr)

    def test_prepare_shell_matches_json_prepare_contract(self):
        record = {
            "index_key": "capability:system.service.restart",
            "id": "system.service.restart",
            "owner": "system",
            "provider": "system",
            "source": "host.json",
            "availability": "active",
            "unavailable_reason": None,
            "descriptor": descriptor().inspect(),
        }
        record["descriptor"].pop("available", None)
        records = [record]
        inputs = {"unit": "demo.service"}
        request = {
            "op": "prepare",
            "records": records,
            "id": "system.service.restart",
            "inputs": inputs,
            "provider": "system",
            "platform_family": "arch",
            "capability_version": 1,
        }
        normal = subprocess.run(
            [sys.executable, "core/lib/capability_runtime.py"],
            input=json.dumps(request), text=True, capture_output=True, check=False,
        )
        direct = subprocess.run(
            [sys.executable, "core/lib/capability_runtime.py", "prepare-shell",
             "system.service.restart", json.dumps(inputs, separators=(",", ":")),
             "system", "1", "arch"],
            input=json.dumps(records), text=True, capture_output=True, check=False,
        )
        self.assertEqual(normal.returncode, 0, normal.stderr)
        self.assertEqual(direct.returncode, 0, direct.stderr)
        self.assertEqual(json.loads(direct.stdout), json.loads(normal.stdout))

        bad_version = subprocess.run(
            [sys.executable, "core/lib/capability_runtime.py", "prepare-shell",
             "system.service.restart", json.dumps(inputs), "system", "3", "arch"],
            input=json.dumps(records), text=True, capture_output=True, check=False,
        )
        self.assertNotEqual(bad_version.returncode, 0)

    def test_prepare_cli_rejects_explicit_null_version(self):
        request = {"op": "prepare", "descriptors": [descriptor().inspect()], "id": "system.service.restart", "inputs": {"unit": "demo.service"}, "capability_version": None}
        # Inspection-only availability keys are not descriptor syntax.
        for key in ("available",):
            request["descriptors"][0].pop(key)
        result = subprocess.run([sys.executable, "core/lib/capability_runtime.py"], input=json.dumps(request), text=True, capture_output=True, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported capability_version", result.stderr)

    def test_tool_input_preserves_only_integer_supported_version_pins(self):
        sys.path.insert(0, "core/ai")
        from tool_input import tool_fields
        for version in (1, 2, 3):
            self.assertEqual(tool_fields(json.dumps({"tool": "run_capability", "id": "system.host.memory.refresh", "inputs": {}, "capability_version": version}))[-1], str(version))
        for version in (None, True, 0, 4, "2"):
            with self.assertRaises(ValueError):
                tool_fields(json.dumps({"tool": "run_capability", "id": "system.host.memory.refresh", "inputs": {}, "capability_version": version}))

    def test_v2_result_cannot_claim_success_without_typed_domain_result(self):
        base = {"operation_id": "op-1", "capability_id": "system.fixture.change", "capability_version": 2,
                "execution_status": "succeeded", "verification_status": "passed", "outcome": "success"}
        for fields in ({}, {"output_status": "not_applicable"}, {"output_status": "valid", "result": None}, {"output_status": "valid", "result": []}):
            completed = subprocess.run([sys.executable, "core/lib/capability_runtime.py"], input=json.dumps({"op": "result", "result": {**base, **fields}}), text=True, capture_output=True, check=False)
            self.assertNotEqual(completed.returncode, 0)
        completed = subprocess.run([sys.executable, "core/lib/capability_runtime.py"], input=json.dumps({"op": "result", "result": {**base, "output_status": "valid", "result": {"count": 2}}}), text=True, capture_output=True, check=False)
        self.assertEqual(completed.returncode, 0)

    def test_registry_resolves_provider_and_reports_ambiguity(self):
        registry = CapabilityRegistry()
        registry.register(descriptor())
        self.assertEqual(registry.resolve("system.service.restart").selected_provider, "system")
        second = descriptor(provider="other", owner="other")
        registry.register(second)
        self.assertEqual(registry.resolve("system.service.restart").status, "ambiguous")
        self.assertEqual(registry.resolve("system.service.restart", "other").status, "available")

    def test_unavailable_and_duplicate_provider_are_deterministic(self):
        registry = CapabilityRegistry()
        inactive = descriptor(active=False, unavailable_reason="owner_disabled")
        registry.register(inactive)
        self.assertEqual(registry.resolve(inactive.id).status, "unavailable")
        self.assertEqual(registry.resolve(inactive.id).reason, "owner_disabled")
        with self.assertRaises(CapabilityError):
            registry.register(descriptor(source="other.json"))

    def test_inputs_are_closed_and_typed(self):
        schema = {"properties": {"enabled": {"type": "boolean"}, "kind": {"type": "enum", "enum": ["a", "b"]}}, "required": ["enabled"], "additionalProperties": False}
        self.assertEqual(validate_inputs(schema, {"enabled": True, "kind": "a"})["enabled"], True)
        for value in ({"enabled": "yes"}, {"enabled": True, "extra": 1}, {"enabled": True, "kind": "c"}):
            with self.assertRaises(CapabilityError):
                validate_inputs(schema, value)
        with self.assertRaises(CapabilityError):
            validate_inputs(schema, {"kind": "a"})

    def test_name_number_and_confined_path_validation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "inside").write_text("ok", encoding="utf-8")
            (root / "link").symlink_to("inside")
            schema = {"properties": {
                "unit": {"type": "string", "validator": "systemd_unit"},
                "count": {"type": "integer", "minimum": 1, "maximum": 5},
                "path": {"type": "path", "root": str(root)},
            }, "required": ["unit", "count", "path"], "additionalProperties": False}
            valid = {"unit": "fixture.service", "count": 2, "path": "inside"}
            self.assertEqual(validate_inputs(schema, valid), valid)
            for bad in (
                {**valid, "unit": "fixture;reboot"},
                {**valid, "count": True},
                {**valid, "count": 6},
                {**valid, "path": "../outside"},
                {**valid, "path": "link"},
            ):
                with self.assertRaises(CapabilityError):
                    validate_inputs(schema, bad)

    def test_secret_reference_never_becomes_a_value(self):
        ref = SecretReference.parse({"reference": "db/password", "namespace": "app", "purpose": "connect"})
        self.assertEqual(ref.as_dict()["reference"], "db/password")
        with self.assertRaises(CapabilityError):
            SecretReference.parse("password value")

    def test_preconditions_remain_authoritative_proposal_metadata(self):
        cap = descriptor(preconditions=[{"kind": "service_exists", "input": "unit"}])
        registry = CapabilityRegistry(); registry.register(cap)
        proposal = registry.prepare(cap.id, {"unit": "demo.service"})
        self.assertEqual(proposal["preconditions"], [{"kind": "service_exists", "input": "unit"}])
        self.assertEqual(proposal["affected_objects"], ["service:systemd:demo.service"])

    def test_irreversible_recovery_is_visible_without_executing(self):
        registry = CapabilityRegistry()
        cap = descriptor(recovery={"class": "irreversible"})
        registry.register(cap)
        proposal = registry.prepare(cap.id, {"unit": "demo.service"})
        self.assertEqual(proposal["recovery"]["class"], "irreversible")
        self.assertEqual(registry.inspect(cap.id)["declarations"][0]["recovery"]["class"], "irreversible")

    def test_plan_resolves_without_execution(self):
        registry = CapabilityRegistry()
        cap = descriptor()
        registry.register(cap)
        plan = CapabilityPlan("restart service", [{"capability_id": cap.id, "inputs": {"unit": "demo.service"}}]).resolve(registry)
        self.assertTrue(plan.digest)
        self.assertEqual(plan.inspect()["steps"][0]["inputs"], {"unit": "demo.service"})

    def test_plan_keeps_objects_and_typed_final_check_expectation(self):
        registry = CapabilityRegistry()
        registry.register(descriptor())
        outputs = {
            "schema_version": 1,
            "properties": {
                "installed": {"type": "boolean"},
                "daemon_accessible": {"type": "boolean"},
            },
            "required": ["installed", "daemon_accessible"],
            "additionalProperties": False,
        }
        check = descriptor(
            id="docker.status", handler="docker__status", owner="docker", provider="docker",
            capability_version=2, outputs=outputs, privilege="none",
            safety={"tier": "READ"}, inputs={"properties": {}, "required": [],
                                               "additionalProperties": False},
            verification={"kind": "none", "required": False},
            affects=[],
        )
        registry.register(check)
        plan = CapabilityPlan(
            "restart then inspect",
            [{"capability_id": "system.service.restart", "inputs": {"unit": "demo.service"}}],
            objects=["service:systemd:demo.service"],
            final_check={"capability_id": check.id, "inputs": {},
                         "expect": {"installed": True, "daemon_accessible": True}},
        ).resolve(registry)
        self.assertEqual(plan.inspect()["objects"], ["service:systemd:demo.service"])
        self.assertEqual(plan.inspect()["final_check"]["capability_id"], check.id)
        self.assertEqual(plan.inspect()["final_check"]["expect"],
                         {"installed": True, "daemon_accessible": True})
        with self.assertRaises(CapabilityError):
            CapabilityPlan(
                "invalid",
                [{"capability_id": check.id, "inputs": {}}],
                final_check={"capability_id": "system.service.restart",
                             "inputs": {"unit": "demo.service"},
                             "expect": {"state": "active"}},
            ).resolve(registry)
        with self.assertRaises(CapabilityError):
            CapabilityPlan(
                "invalid expectation",
                [{"capability_id": "system.service.restart",
                  "inputs": {"unit": "demo.service"}}],
                final_check={"capability_id": check.id, "inputs": {},
                             "expect": {"unknown": True}},
            ).resolve(registry)

    def test_composite_provider_resolves_platform_variant_into_internal_plan(self):
        registry = CapabilityRegistry()
        package = descriptor(
            id="system.package.install", handler="system__privileged_marker",
            inputs={"properties": {"package": {"type": "string", "validator": "package_name"}},
                    "required": ["package"], "additionalProperties": False},
            verification={"kind": "trusted_query", "required": True},
            affects=[{"object": "package", "input": "package"}],
        )
        registry.register(package)
        status_outputs = {
            "schema_version": 1,
            "properties": {"ready": {"type": "boolean"}},
            "required": ["ready"], "additionalProperties": False,
        }
        status = descriptor(
            id="fixture.status", owner="fixture", provider="fixture",
            handler="fixture__status", capability_version=2, outputs=status_outputs,
            privilege="none", safety={"tier": "READ"},
            inputs={"properties": {}, "required": [], "additionalProperties": False},
            verification={"kind": "none", "required": False}, affects=[],
        )
        registry.register(status)
        raw = {
            "kind": "capability", "id": "fixture.install", "owner": "fixture",
            "provider": "fixture", "capability_version": 1,
            "description": "Install fixture.",
            "inputs": {"properties": {}, "required": [], "additionalProperties": False},
            "safety": {"tier": "CHANGE"}, "privilege": "none",
            "preconditions": [], "verification": {"kind": "none", "required": False},
            "recovery": {"class": "best_effort"},
            "affects": [],
            "implementation": {
                "kind": "composition", "intended_outcome": "Fixture is ready.",
                "variants": [
                    {"requires": {"platform_families": ["debian"]},
                     "steps": [{"capability_id": "system.package.install",
                                "inputs": {"package": "fixture-deb"}}]},
                    {"requires": {"platform_families": ["arch"]},
                     "steps": [{"capability_id": "system.package.install",
                                "inputs": {"package": "fixture"}}]},
                ],
                "final_check": {"capability_id": "fixture.status", "inputs": {},
                                "expect": {"ready": True}},
            },
        }
        registry.register(raw)
        proposal = registry.prepare("fixture.install", {}, provider="fixture",
                                    platform_family="debian")
        self.assertEqual(proposal["composition_plan"]["steps"][0]["inputs"],
                         {"package": "fixture-deb"})
        self.assertEqual(proposal["composition_plan"]["final_check"]["expect"],
                         {"ready": True})
        self.assertEqual(proposal["affected_objects"], ["package:fixture-deb"])
        self.assertEqual(proposal["composition_summary"]["privilege"], "required")
        self.assertEqual(proposal["composition_summary"]["child_tier_floor"], "CHANGE")
        self.assertEqual(proposal["composition_summary"]["effective_tier"], "CHANGE")
        self.assertTrue(proposal["composition_plan"]["digest"])
        with self.assertRaises(CapabilityError):
            registry.prepare("fixture.install", {}, provider="fixture",
                             platform_family="unknown")
        with self.assertRaisesRegex(CapabilityError, "direct privilege"):
            CapabilityDescriptor.from_dict({**raw, "privilege": "required"})
        weak = CapabilityDescriptor.from_dict({**raw, "id": "fixture.weak",
                                                "safety": {"tier": "READ"}})
        registry.register(weak)
        with self.assertRaisesRegex(CapabilityError, "safety tier"):
            registry.prepare("fixture.weak", {}, provider="fixture",
                             platform_family="debian")

    def test_inspection_is_read_only(self):
        registry = CapabilityRegistry(); cap = descriptor(); registry.register(cap)
        registry.inspect(cap.id)
        self.assertEqual(registry.list()[0]["id"], cap.id)

    def test_prepare_freezes_authoritative_proposal_without_execution(self):
        registry = CapabilityRegistry(); cap = descriptor(); registry.register(cap)
        proposal = registry.prepare(cap.id, {"unit": "demo.service"})
        self.assertEqual(proposal["provider"], "system")
        self.assertEqual(proposal["affected_objects"], ["service:systemd:demo.service"])
        self.assertTrue(proposal["digest"])
        self.assertNotIn("operation_id", proposal)

    def test_result_rejects_unverified_success_and_secret_fields(self):
        from capability_runtime import _validate_result
        with self.assertRaises(CapabilityError):
            _validate_result({"operation_id": "op-1", "capability_id": "system.x.y", "execution_status": "succeeded", "verification_status": "failed", "outcome": "success"})
        with self.assertRaises(CapabilityError):
            _validate_result({"operation_id": "op-1", "capability_id": "system.x.y", "execution_status": "failed", "verification_status": "not_applicable", "outcome": "failed", "password": "secret"})

    def test_prepare_cli_consumes_loader_rows_and_filters_legacy_rows(self):
        row = {"id": "system.host.memory.refresh", "owner": "system", "provider": "system", "source": "system.json", "availability": "active", "descriptor": {
            "kind": "capability", "id": "system.host.memory.refresh", "handler": "system__memory",
            "capability_version": 1, "description": "memory", "inputs": {"properties": {}, "required": [], "additionalProperties": False},
            "safety": {"tier": "READ"}, "privilege": "none", "preconditions": [], "verification": {},
            "recovery": {"class": "not_applicable"}, "affects": [{"object": "host", "id": "local"}], "timeout_seconds": 30}}
        request = {"op": "prepare", "records": [row, {"id": "legacy.x", "descriptor": {"kind": "legacy_action", "id": "legacy.x"}}], "id": row["id"], "inputs": {}}
        completed = subprocess.run([sys.executable, "core/lib/capability_runtime.py"], input=json.dumps(request), text=True, capture_output=True, check=True)
        proposal = json.loads(completed.stdout)
        self.assertEqual(proposal["owner"], "system")
        self.assertEqual(proposal["inputs"], {})
        self.assertEqual(proposal["recovery"]["class"], "not_applicable")
        self.assertNotIn("legacy.x", completed.stdout)


if __name__ == "__main__":
    unittest.main()
