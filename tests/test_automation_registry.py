"""Focused Step 14 registry and execution proofs, using disposable state."""

import concurrent.futures
import copy
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
from automation_registry import AutomationError, Registry
from module_contract import validate_module

TRIGGER = {"kind": "once_at", "schema_version": 1, "once_at": "2030-01-01T00:00:00Z"}
PERIODIC = {"kind": "periodic", "schema_version": 1,
            "anchor": "2030-01-01T00:00:00Z", "interval_seconds": 60}


class AutomationRegistryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        module = validate_module(ROOT / "modules/system")
        desc = next(x for x in module["contributions"] if x["kind"] == "capability")
        proposal = next(x for x in module["contributions"] if x["kind"] == "automation")
        self.capabilities = [{"id": desc["id"], "provider": "system", "availability": "active", "descriptor": desc}]
        self.proposals = [{"id": proposal["id"], "owner": "system", "module_version": "2.0.0",
                           "source": proposal["source"], "availability": "active", "descriptor": proposal}]
        self.root = Path(self.temp.name)
        self.registry = Registry(self.root, self.capabilities, self.proposals)

    def config(self):
        return {"owner": "user", "proposal_id": "system.host.memory.once", "trigger": copy.deepcopy(TRIGGER)}

    def create(self):
        return self.registry.create(self.config(), "operator")

    def create_periodic(self, trigger=None):
        return self.registry.create({"owner": "user", "trigger": trigger or PERIODIC,
                                     "target": {"capability_id": "system.host.memory.refresh",
                                                "provider": "system", "inputs": {}}}, "operator")

    def test_periodic_trigger_schema_and_cursor_fail_closed(self):
        for trigger in (
            {**PERIODIC, "interval_seconds": 0},
            {**PERIODIC, "interval_seconds": 31536001},
            {**PERIODIC, "interval_seconds": True},
            {**PERIODIC, "interval_seconds": 1.5},
            {**PERIODIC, "anchor": "2030-01-01T00:00:00+01:00"},
            {**PERIODIC, "schema_version": 2},
            {**PERIODIC, "extra": 1},
        ):
            with self.subTest(trigger=trigger), self.assertRaises(AutomationError):
                self.create_periodic(trigger)
        self.assertFalse(self.registry.path.exists())
        row = self.create_periodic()
        self.registry.mutate("enable", row["id"], "operator")
        self.registry.claim_due("Assist", datetime(2030, 1, 1, 0, 2, 5, tzinfo=timezone.utc))
        original = self.registry.path.read_bytes()
        data = json.loads(original)
        data["instances"][0]["schedule_cursor"] = "2030-01-01T00:02:01Z"
        data["instances"][0]["last_attempt"]["slot"] = data["instances"][0]["schedule_cursor"]
        self.registry.path.write_text(json.dumps(data))
        with self.assertRaisesRegex(AutomationError, "cursor is invalid"):
            self.registry.inspect()
        self.registry.path.write_bytes(original)

    def test_periodic_slots_skip_missed_and_restart_without_duplicate(self):
        row = self.create_periodic()
        self.registry.mutate("enable", row["id"], "operator")
        before = datetime(2029, 12, 31, 23, 59, 59, tzinfo=timezone.utc)
        now = datetime(2030, 1, 1, 0, 2, 5, tzinfo=timezone.utc)
        self.assertIsNone(self.registry.claim_due("Assist", before))
        self.assertEqual(self.registry.inspect(row["id"], now=before)["instances"][0]["next_due_at"],
                         PERIODIC["anchor"])
        self.assertIsNone(self.registry.claim_due("Guide", now))
        before_read = self.registry.path.read_bytes()
        self.assertEqual(self.registry.inspect(row["id"], now=now)["instances"][0]["next_due_at"],
                         "2030-01-01T00:02:00Z")
        self.assertEqual(self.registry.path.read_bytes(), before_read)

        def claim():
            return Registry(self.root, self.capabilities, self.proposals).claim_due("Assist", now)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            claims = list(pool.map(lambda _: claim(), range(4)))
        self.assertEqual(len([claim for claim in claims if claim]), 1)
        fresh = Registry(self.root, self.capabilities, self.proposals)
        state = fresh.inspect(row["id"], now=now)["instances"][0]
        self.assertEqual(state["schedule_cursor"], "2030-01-01T00:02:00Z")
        self.assertEqual(state["last_attempt"]["outcome"], "interrupted_unknown")
        self.assertEqual(state["next_due_at"], "2030-01-01T00:03:00Z")
        self.assertIsNone(fresh.claim_due("Assist", now))
        earlier = datetime(2030, 1, 1, 0, 1, 30, tzinfo=timezone.utc)
        self.assertIsNone(fresh.claim_due("Assist", earlier))
        self.assertEqual(fresh.inspect(row["id"], now=earlier)["instances"][0]["next_due_at"],
                         "2030-01-01T00:03:00Z")
        later = datetime(2030, 1, 1, 0, 5, 17, tzinfo=timezone.utc)
        next_claim = fresh.claim_due("Assist", later)
        self.assertIsNotNone(next_claim)
        state = fresh.inspect(row["id"], now=later)["instances"][0]
        self.assertEqual(state["schedule_cursor"], "2030-01-01T00:05:00Z")
        self.assertEqual(state["last_attempt"]["slot"], "2030-01-01T00:05:00Z")
        self.assertIsNone(fresh.claim_due("Assist", later))

    def test_periodic_edit_disables_and_resets_cursor(self):
        row = self.create_periodic()
        self.registry.mutate("enable", row["id"], "operator")
        self.registry.claim_due("Assist", datetime(2030, 1, 1, tzinfo=timezone.utc))
        edited = self.registry.mutate("edit", row["id"], "operator",
                                      {"trigger": {**PERIODIC, "interval_seconds": 120}})
        self.assertFalse(edited["enabled"])
        self.assertIsNone(edited["schedule_cursor"])
        self.assertIsNone(edited["last_attempt"])

    def test_periodic_overlapping_ticks_do_not_dispatch_concurrently(self):
        row = self.create_periodic()
        self.registry.mutate("enable", row["id"], "operator")
        capabilities = self.root / "capabilities.json"
        capabilities.write_text(json.dumps(self.capabilities))
        marker = self.root / "dispatch.started"
        script = '''
            export IGOR_DIR="$PWD"
            source core/lib/automation.sh
            igor_capability_list() { cat "$CAPABILITIES_FILE"; }
            igor_automation_proposals() { :; }
            ai_get_mode() { printf 'assist\\n'; }
            date() { printf '%s\\n' "$AUTOMATION_TICK"; }
            ai_execute_tool() {
                printf 'started' > "$DISPATCH_MARKER"
                sleep 1
                IGOR_CAPABILITY_LAST_RESULT='{"operation_id":"op-overlap","capability_id":"system.host.memory.refresh","provider":"system","execution_status":"succeeded","verification_status":"passed","outcome":"success"}'
            }
            igor_automation_run_due Assist
        '''
        env = {**os.environ, "IGOR_DATA_DIR": str(self.root), "CAPABILITIES_FILE": str(capabilities),
               "DISPATCH_MARKER": str(marker)}
        first = subprocess.Popen(["bash", "-c", script], cwd=ROOT,
                                 env={**env, "AUTOMATION_TICK": "2030-01-01T00:00:00Z"},
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not marker.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue(marker.exists(), "first dispatch did not start")
            second = subprocess.run(["bash", "-c", script], cwd=ROOT,
                                    env={**env, "AUTOMATION_TICK": "2030-01-01T00:01:00Z"},
                                    capture_output=True, text=True, check=True)
            self.assertEqual(json.loads(second.stdout), {"admitted": 0, "reason": "overlap_skipped"})
            output, errors = first.communicate(timeout=10)
            self.assertEqual(first.returncode, 0, errors)
            self.assertEqual(json.loads(output)["admitted"], 1)
        finally:
            if first.poll() is None:
                first.kill()
                first.communicate()
        self.assertEqual(self.registry.inspect(row["id"])["instances"][0]["schedule_cursor"],
                         "2030-01-01T00:00:00Z")
        third = subprocess.run(["bash", "-c", script], cwd=ROOT,
                               env={**env, "AUTOMATION_TICK": "2030-01-01T00:01:00Z"},
                               capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(third.stdout)["admitted"], 1)

    def test_proposal_is_inactive_and_untrusted_data_cannot_activate(self):
        self.assertEqual(len(self.registry.list_proposals()), 1)
        self.assertEqual(self.registry.inspect()["instances"], [])
        for actor in ("module", "ai", "reference", "domain_event"):
            with self.assertRaisesRegex(AutomationError, "operator"):
                self.registry.create(self.config(), actor)
        row = self.create()
        self.assertFalse(row["enabled"])
        for actor in ("module", "ai", "reference", "domain_event"):
            with self.assertRaisesRegex(AutomationError, "operator"):
                self.registry.mutate("enable", row["id"], actor)
        self.assertFalse(self.registry.inspect(row["id"])["instances"][0]["enabled"])

    def test_explicit_enable_disable_restart_and_no_execution(self):
        row = self.create()
        path = self.registry.path
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(path.parent).st_mode & 0o777, 0o700)
        self.registry.mutate("enable", row["id"], "operator")
        fresh = Registry(self.root, self.capabilities, self.proposals)
        inspected = fresh.inspect(row["id"])["instances"][0]
        self.assertTrue(inspected["enabled"])
        self.assertEqual(inspected["availability_reason"], "not_due")
        self.assertIsNone(inspected["last_attempt"])
        self.assertIsNone(inspected["schedule_cursor"])
        before = path.read_bytes()
        fresh.inspect()
        self.assertEqual(path.read_bytes(), before)
        fresh.mutate("disable", row["id"], "operator")
        self.assertEqual(Registry(self.root, self.capabilities, self.proposals).inspect(row["id"])["instances"][0]["state"], "disabled")

    def test_module_disable_and_compatible_reenable_preserve_intent(self):
        row = self.create()
        self.registry.mutate("enable", row["id"], "operator")
        disabled = Registry(self.root, self.capabilities, [])
        state = disabled.inspect(row["id"])["instances"][0]
        self.assertTrue(state["enabled"])
        self.assertEqual(state["availability_reason"], "source_proposal_inactive")
        with self.assertRaises(AutomationError):
            disabled.mutate("enable", row["id"], "operator")
        self.assertEqual(Registry(self.root, self.capabilities, self.proposals).inspect(row["id"])["instances"][0]["availability_reason"], "not_due")
        changed = copy.deepcopy(self.proposals)
        changed[0]["module_version"] = "3.0.0"
        self.assertEqual(Registry(self.root, self.capabilities, changed).inspect(row["id"])["instances"][0]["availability_reason"], "source_proposal_changed")

    def test_strict_configuration_policy_and_secrets(self):
        bad = [
            {**self.config(), "enabled": True},
            {**self.config(), "trigger": {**TRIGGER, "extra": 1}},
            {**self.config(), "trigger": {**TRIGGER, "schema_version": 2}},
            {**self.config(), "trigger": {**TRIGGER, "once_at": "tomorrow"}},
            {"owner": "user", "trigger": TRIGGER, "target": {"capability_id": "system.host.memory.refresh", "inputs": {"password": "unsafe"}}},
            {"owner": "user", "trigger": TRIGGER, "target": {"capability_id": "system.host.memory.refresh", "inputs": {"extra": 1}}},
        ]
        for config in bad:
            with self.subTest(config=config), self.assertRaises(AutomationError):
                self.registry.create(config, "operator")
        self.assertFalse(self.registry.path.exists())
        changed = copy.deepcopy(self.capabilities)
        changed[0]["descriptor"]["safety"]["tier"] = "CHANGE"
        registry = Registry(self.root, changed, self.proposals)
        row = registry.create(self.config(), "operator")
        with self.assertRaisesRegex(AutomationError, "READ"):
            registry.mutate("enable", row["id"], "operator")
        changed[0]["descriptor"]["safety"]["tier"] = "READ"
        changed[0]["descriptor"]["privilege"] = "required"
        with self.assertRaisesRegex(AutomationError, "READ"):
            registry.mutate("enable", row["id"], "operator")

    def test_manual_intent_has_core_stamped_source_and_edit_disables(self):
        row = self.registry.create({"owner": "user", "trigger": TRIGGER,
                                    "target": {"capability_id": "system.host.memory.refresh", "inputs": {}}}, "operator")
        self.assertEqual(row["source"], {"kind": "manual", "actor": "operator"})
        self.registry.mutate("enable", row["id"], "operator")
        edited = self.registry.mutate("edit", row["id"], "operator",
                                      {"trigger": {**TRIGGER, "once_at": "2031-01-01T00:00:00Z"}})
        self.assertFalse(edited["enabled"])
        self.assertEqual(self.registry.inspect(row["id"])["instances"][0]["trigger"]["once_at"], "2031-01-01T00:00:00Z")

    def test_corrupt_version_symlink_and_explicit_removal(self):
        row = self.create()
        original = self.registry.path.read_bytes()
        data = json.loads(original)
        data["schema_version"] = 2
        self.registry.path.write_text(json.dumps(data))
        with self.assertRaisesRegex(AutomationError, "version is unsupported"):
            self.registry.inspect()
        self.assertEqual(json.loads(self.registry.path.read_text()), data)
        self.registry.path.write_bytes(b"not json")
        with self.assertRaisesRegex(AutomationError, "store invalid"):
            self.registry.mutate("enable", row["id"], "operator")
        self.registry.mutate("reset", "all", "operator")
        self.assertEqual((self.registry.directory / "registry.v1.recovery.json").read_bytes(), b"not json")
        self.assertEqual(Registry(self.root, self.capabilities, self.proposals).inspect()["instances"], [])
        self.assertEqual(json.loads(self.registry.path.read_text())["schema_version"], 1)
        replacement = self.create()
        self.registry.mutate("reset", replacement["id"], "operator")
        self.assertEqual(self.registry.inspect()["instances"], [])
        self.registry.path.unlink()
        self.registry.path.symlink_to(self.registry.directory / "registry.v1.recovery.json")
        with self.assertRaisesRegex(AutomationError, "symlink"):
            self.registry.inspect()

    def test_store_unknown_fields_and_wrong_types_fail_closed(self):
        self.create()
        original = self.registry.path.read_bytes()
        for change in (
            lambda data: data.update(unexpected=True),
            lambda data: data["instances"][0].update(enabled="true"),
            lambda data: data["instances"][0]["execution_policy"].update(schema_version=True),
            lambda data: data["instances"][0]["target"].update(inputs={"password": "value"}),
        ):
            data = json.loads(original)
            change(data)
            self.registry.path.write_text(json.dumps(data))
            with self.subTest(data=data), self.assertRaisesRegex(AutomationError, "store invalid"):
                self.registry.inspect()
            with self.subTest(data=data), self.assertRaisesRegex(AutomationError, "store invalid"):
                self.registry.mutate("enable", data["instances"][0]["id"], "operator")
        self.registry.path.write_bytes(original)

    def test_cli_fresh_process_no_capability_invocation(self):
        env = {**os.environ, "IGOR_DATA_DIR": str(self.root)}
        def cli(*args):
            result = subprocess.run(["bash", "igor.sh", "--automations", *args],
                                    cwd=ROOT, env=env, capture_output=True, text=True, check=True)
            return json.loads(result.stdout)

        created = cli("create", json.dumps(self.config()))
        ident = created["id"]
        self.assertEqual(cli("inspect", ident)["instances"][0]["availability_reason"], "disabled")
        cli("enable", ident)
        self.assertTrue(cli("inspect", ident)["instances"][0]["enabled"])
        cli("disable", ident)
        self.assertEqual(cli("inspect", ident)["instances"][0]["state"], "disabled")
        self.assertFalse((self.root / "runtime").exists())
        self.assertEqual(json.loads(self.registry.path.read_text())["instances"][0]["last_attempt"], None)
        cli("delete", ident)
        self.assertEqual(cli("list")["instances"], [])

    def test_once_due_mode_source_and_read_only_inspection(self):
        row = self.create()
        now = datetime(2030, 1, 1, tzinfo=timezone.utc)
        self.assertIsNone(self.registry.claim_due("Assist", now))
        self.registry.mutate("enable", row["id"], "operator")
        self.assertIsNone(self.registry.claim_due("Guide", now))
        self.assertIsNone(self.registry.claim_due("Assist", datetime(2029, 12, 31, tzinfo=timezone.utc)))
        before = self.registry.path.read_bytes()
        inspected = self.registry.inspect(row["id"], mode="Assist", now=now)["instances"][0]
        self.assertTrue(inspected["due"])
        self.assertEqual(self.registry.path.read_bytes(), before)
        self.assertEqual(self.registry.inspect(row["id"], mode="Guide", now=now)["instances"][0]["availability_reason"], "guide_mode")
        self.assertIsNone(Registry(self.root, self.capabilities, []).claim_due("Assist", now))
        changed = copy.deepcopy(self.proposals)
        changed[0]["module_version"] = "3.0.0"
        self.assertIsNone(Registry(self.root, self.capabilities, changed).claim_due("Assist", now))
        self.assertEqual(self.registry.path.read_bytes(), before)

    def test_atomic_claim_crash_restart_terminal_and_result_status(self):
        row = self.create()
        self.registry.mutate("enable", row["id"], "operator")
        now = datetime(2030, 1, 2, tzinfo=timezone.utc)
        def claim():
            return Registry(self.root, self.capabilities, self.proposals).claim_due("Executive", now)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            claims = list(pool.map(lambda _: claim(), range(4)))
        claimed = [item for item in claims if item is not None]
        self.assertEqual(len(claimed), 1)
        fresh = Registry(self.root, self.capabilities, self.proposals)
        state = fresh.inspect(row["id"], now=now)["instances"][0]
        self.assertEqual(state["claim_state"], "interrupted_unknown")
        self.assertEqual(state["last_attempt"]["outcome"], "interrupted_unknown")
        self.assertIsNone(fresh.claim_due("Assist", now))
        result = {"operation_id": "op-test", "capability_id": "system.host.memory.refresh",
                  "provider": "system", "execution_status": "succeeded", "verification_status": "failed",
                  "outcome": "unverified_result"}
        attempt = fresh.finish(row["id"], claimed[0]["claim_id"], result)
        self.assertEqual((attempt["execution_status"], attempt["verification_status"], attempt["outcome"]),
                         ("succeeded", "failed", "unverified_result"))
        with self.assertRaisesRegex(AutomationError, "already finished"):
            fresh.finish(row["id"], claimed[0]["claim_id"], result)
        self.assertEqual(fresh.inspect(row["id"], now=now)["instances"][0]["claim_state"], "terminal")
        self.assertIsNone(fresh.claim_due("Assist", now))

    def test_target_policy_and_resolution_rechecked_at_admission(self):
        row = self.create()
        self.registry.mutate("enable", row["id"], "operator")
        now = datetime(2030, 1, 2, tzinfo=timezone.utc)
        for tier, privilege in (("CHANGE", "none"), ("DESTROY", "none"), ("READ", "required")):
            changed = copy.deepcopy(self.capabilities)
            changed[0]["descriptor"]["safety"]["tier"] = tier
            changed[0]["descriptor"]["privilege"] = privilege
            registry = Registry(self.root, changed, self.proposals)
            self.assertEqual(registry.inspect(row["id"], now=now)["instances"][0]["availability_reason"],
                             "target_policy_incompatible")
            self.assertIsNone(registry.claim_due("Assist", now))
        unavailable = Registry(self.root, [], self.proposals)
        self.assertEqual(unavailable.inspect(row["id"], now=now)["instances"][0]["availability_reason"],
                         "target_unavailable")
        self.assertIsNone(unavailable.claim_due("Assist", now))
        ambiguous = Registry(self.root, self.capabilities * 2, self.proposals)
        self.assertEqual(ambiguous.inspect(row["id"], now=now)["instances"][0]["availability_reason"],
                         "target_ambiguous")
        self.assertIsNone(ambiguous.claim_due("Assist", now))
        self.assertIsNone(self.registry.inspect(row["id"], now=now)["instances"][0]["last_attempt"])

    def test_real_one_time_memory_dispatch_modes_and_restart(self):
        due = {**TRIGGER, "once_at": "2020-01-01T00:00:00Z"}
        env = {**os.environ, "IGOR_DATA_DIR": str(self.root)}
        def cli(*args):
            return subprocess.run(["bash", "igor.sh", "--automations", *args], cwd=ROOT,
                                  env=env, capture_output=True, text=True, check=True)
        created = json.loads(cli("create", json.dumps({"owner": "user", "proposal_id": "system.host.memory.once",
                                                     "trigger": due})).stdout)
        ident = created["id"]
        cli("enable", ident)
        self.assertEqual(json.loads(cli("run-due", "Guide").stdout)["admitted"], 0)
        self.assertIsNone(self.registry.inspect(ident)["instances"][0]["last_attempt"])
        script = '''
            export IGOR_DIR="$PWD"
            source core/lib/config_loader.sh
            source core/lib/module_loader.sh
            source core/lib/automation.sh
            igor_load_config >/dev/null
            igor_load_all_modules >/dev/null
            igor_load_capabilities >/dev/null
            source core/ai/safety.sh
            igor_automation_run_due Assist
            igor_domain_event_recent '{"event_type":"capability.completed"}'
        '''
        dispatched = subprocess.run(["bash", "-c", script], cwd=ROOT, env=env,
                                    capture_output=True, text=True, check=True)
        lines = dispatched.stdout.strip().splitlines()
        self.assertEqual(json.loads(lines[0])["admitted"], 1)
        events = json.loads(lines[1])
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["event_type"], "capability.completed")
        state = self.registry.inspect(ident)["instances"][0]
        self.assertEqual((state["last_attempt"]["execution_status"],
                          state["last_attempt"]["verification_status"], state["last_attempt"]["outcome"]),
                         ("succeeded", "passed", "success"))
        self.assertTrue(state["last_attempt"]["operation_id"].startswith("op-"))
        self.assertEqual(events[0]["correlation_id"], state["last_attempt"]["operation_id"])
        self.assertEqual(json.loads(cli("run-due", "Assist").stdout)["admitted"], 0)
        self.assertEqual(json.loads(cli("run-due", "Executive").stdout)["admitted"], 0)
        # A separate Executive instance proves its automatic READ policy.
        second = json.loads(cli("create", json.dumps({"owner": "user", "proposal_id": "system.host.memory.once",
                                                    "trigger": due})).stdout)
        cli("enable", second["id"])
        self.assertEqual(json.loads(cli("run-due", "Executive").stdout)["admitted"], 1)
        self.assertEqual(self.registry.inspect(second["id"])["instances"][0]["last_attempt"]["outcome"], "success")

    def test_real_periodic_memory_refresh_uses_canonical_dispatch(self):
        trigger = {"kind": "periodic", "schema_version": 1,
                   "anchor": "2020-01-01T00:00:00Z", "interval_seconds": 86400}
        row = self.create_periodic(trigger)
        self.registry.mutate("enable", row["id"], "operator")
        env = {**os.environ, "IGOR_DATA_DIR": str(self.root)}
        script = '''
            export IGOR_DIR="$PWD"
            source core/lib/config_loader.sh
            source core/lib/module_loader.sh
            source core/lib/automation.sh
            igor_load_config >/dev/null
            igor_load_all_modules >/dev/null
            igor_load_capabilities >/dev/null
            source core/ai/safety.sh
            igor_automation_run_due Assist
            igor_domain_event_recent '{"event_type":"capability.completed"}'
        '''
        first = subprocess.run(["bash", "-c", script], cwd=ROOT, env=env,
                               capture_output=True, text=True, check=True)
        admitted, events = map(json.loads, first.stdout.strip().splitlines())
        self.assertEqual(admitted["admitted"], 1)
        self.assertEqual(len(events), 1)
        state = self.registry.inspect(row["id"])["instances"][0]
        self.assertEqual(state["last_attempt"]["outcome"], "success")
        self.assertEqual(state["last_attempt"]["verification_status"], "passed")
        self.assertEqual(events[0]["correlation_id"], state["last_attempt"]["operation_id"])
        self.assertEqual(state["next_due_at"],
                         (datetime.fromisoformat(state["schedule_cursor"].replace("Z", "+00:00"))
                          + timedelta(days=1)).isoformat().replace("+00:00", "Z"))
        second = subprocess.run(["bash", "-c", script], cwd=ROOT, env=env,
                                capture_output=True, text=True, check=True)
        admitted, events = map(json.loads, second.stdout.strip().splitlines())
        self.assertEqual(admitted["admitted"], 0)
        self.assertEqual(events, [])

    def test_fixed_inputs_reach_dispatch_request_unchanged(self):
        capability = copy.deepcopy(self.capabilities[0])
        capability["descriptor"]["inputs"] = {
            "properties": {"sample": {"type": "string", "minLength": 1, "maxLength": 80}},
            "required": ["sample"], "additionalProperties": False,
        }
        inputs = {"sample": "literal input"}
        registry = Registry(self.root, [capability], [])
        row = registry.create({"owner": "user", "trigger": {**TRIGGER, "once_at": "2020-01-01T00:00:00Z"},
                               "target": {"capability_id": "system.host.memory.refresh", "provider": "system",
                                          "inputs": inputs}}, "operator")
        registry.mutate("enable", row["id"], "operator")
        capture = self.root / "request.json"
        # An already loaded dispatcher is the normal in-session integration
        # boundary; this stub observes only the request handed to it.
        script = '''
            export IGOR_DIR="$PWD"
            source core/lib/automation.sh
            igor_capability_list() { cat "$CAPABILITIES_FILE"; }
            igor_automation_proposals() { :; }
            ai_execute_tool() {
                printf '%s' "$1" > "$CAPTURE_FILE"
                IGOR_CAPABILITY_LAST_RESULT='{"operation_id":"op-input","capability_id":"system.host.memory.refresh","provider":"system","execution_status":"succeeded","verification_status":"passed","outcome":"success"}'
            }
            ai_get_mode() { printf 'assist\\n'; }
            igor_automation_run_due Assist
        '''
        capability_file = self.root / "capability.json"
        capability_file.write_text(json.dumps([capability]))
        env = {**os.environ, "IGOR_DATA_DIR": str(self.root), "CAPTURE_FILE": str(capture),
               "CAPABILITIES_FILE": str(capability_file)}
        run = subprocess.run(["bash", "-c", script], cwd=ROOT, env=env,
                             capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(run.stdout)["admitted"], 1)
        request = json.loads(capture.read_text())
        self.assertEqual(request, {"tool": "run_capability", "id": "system.host.memory.refresh",
                                   "provider": "system", "inputs": inputs})
        self.assertEqual(registry.inspect(row["id"])["instances"][0]["last_attempt"]["outcome"], "success")

    def test_canonical_precondition_failure_is_recorded_without_execution(self):
        row = self.registry.create({"owner": "user", "trigger": {**TRIGGER, "once_at": "2020-01-01T00:00:00Z"},
                                    "target": {"capability_id": "system.host.memory.refresh", "provider": "system",
                                               "inputs": {}}}, "operator")
        self.registry.mutate("enable", row["id"], "operator")
        script = '''
            export IGOR_DIR="$PWD"
            source core/lib/config_loader.sh
            source core/lib/module_loader.sh
            source core/lib/automation.sh
            igor_load_config >/dev/null
            igor_load_all_modules >/dev/null
            igor_load_capabilities >/dev/null
            source core/ai/safety.sh
            _igor_capability_preconditions() { return 1; }
            igor_automation_run_due Assist
        '''
        env = {**os.environ, "IGOR_DATA_DIR": str(self.root)}
        subprocess.run(["bash", "-c", script], cwd=ROOT, env=env,
                       capture_output=True, text=True, check=False)
        attempt = self.registry.inspect(row["id"])["instances"][0]["last_attempt"]
        self.assertEqual(attempt["outcome"], "precondition_failed")
        self.assertEqual(attempt["execution_status"], "not_executed")
        self.assertEqual(attempt["verification_status"], "not_applicable")
        self.assertIsNone(self.registry.claim_due("Assist", datetime.now(timezone.utc)))


if __name__ == "__main__":
    unittest.main()
