"""Focused Step 14A contract and restart proofs, using disposable state."""

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
from automation_registry import AutomationError, Registry
from module_contract import validate_module

TRIGGER = {"kind": "once_at", "schema_version": 1, "once_at": "2030-01-01T00:00:00Z"}


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
        self.assertEqual(inspected["availability_reason"], "execution_not_installed")
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
        self.assertEqual(Registry(self.root, self.capabilities, self.proposals).inspect(row["id"])["instances"][0]["availability_reason"], "execution_not_installed")
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
        self.assertEqual(cli("inspect", ident)["instances"][0]["availability_reason"], "execution_not_installed")
        cli("disable", ident)
        self.assertEqual(cli("inspect", ident)["instances"][0]["state"], "disabled")
        self.assertFalse((self.root / "runtime").exists())
        self.assertEqual(json.loads(self.registry.path.read_text())["instances"][0]["last_attempt"], None)
        cli("delete", ident)
        self.assertEqual(cli("list")["instances"], [])


if __name__ == "__main__":
    unittest.main()
