"""Focused contract tests for the Module API v2 data validator."""

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "core/lib/module_contract.py"
sys.path.insert(0, str(ROOT / "core/lib"))
import module_contract


class ModuleContractTests(unittest.TestCase):
    def package(self, manifest, contract=None):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name) / "fixture"
        root.mkdir()
        (root / "module.conf").write_text(manifest, encoding="utf-8")
        if contract is not None:
            (root / "contracts").mkdir()
            (root / "contracts/host.json").write_text(json.dumps(contract), encoding="utf-8")
        return root

    def valid_manifest(self, **changes):
        values = {
            "module_api": "2", "name": "fixture", "display_name": "Fixture",
            "version": "1.2.3", "runtime": "bash", "entrypoint": "module.sh",
            "contracts": "contracts/host.json",
        }
        values.update(changes)
        return "[module]\n" + "".join(f"{key}={value}\n" for key, value in values.items()) + (
            "\n[requirements]\nrequired_modules=\noptional_modules=\n"
            "required_capabilities=\noptional_capabilities=\nplatform_families=\nrequired_bins=\n"
            "\n[compat]\nv1_hooks=false\n"
        )

    def test_system_reference_validates_and_stamps_owner(self):
        result = module_contract.validate_module(ROOT / "modules/system")
        self.assertEqual(result["manifest"]["name"], "system")
        self.assertEqual(result["contributions"][0]["owner"], "system")
        capability = next(r for r in result["contributions"] if r["kind"] == "capability")
        self.assertEqual(capability["capability_version"], 2)
        self.assertEqual(capability["outputs"]["required"], ["observer_id"])

    def test_system_package_reproduces_from_tracked_content_and_declared_asset(self):
        tracked = subprocess.run(["git", "ls-files", "modules/system"], cwd=ROOT, check=True, text=True, capture_output=True).stdout.splitlines()
        asset = "modules/system/knowledge/host.md"
        ignored = subprocess.run(["git", "check-ignore", asset], cwd=ROOT, text=True, capture_output=True, check=False)
        self.assertEqual(ignored.returncode, 1)
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "system"
            for relative in sorted(set(tracked) | {asset}):
                destination = package / Path(relative).relative_to("modules/system")
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, destination)
            result = module_contract.validate_module(package)
        self.assertEqual(result["contributions"][0]["path"], "knowledge/host.md")

    def test_module_typed_output_contract_rejects_missing_unsupported_or_foreign_shape(self):
        original = json.loads((ROOT / "modules/system/contracts/host.json").read_text())
        cap = next(r for r in original["contributions"] if r["kind"] == "capability")
        cap = {**cap, "id": "fixture.refresh", "handler": "fixture__refresh"}
        for changes in ({"outputs": None}, {"capability_version": True}, {"capability_version": 3}, {"capability_version": 1}, {"outputs": {**cap["outputs"], "additionalProperties": True}}):
            root = self.package(self.valid_manifest(), {"contract_version": 1, "contributions": [{**cap, **changes}]})
            (root / "module.sh").write_text("fixture__refresh() { :; }\n", encoding="utf-8")
            with self.assertRaises(module_contract.ValidationError):
                module_contract.validate_module(root)

    def test_configuration_schema_is_validated_and_core_stamps_owner(self):
        schema = {"schema_version": 1, "fields": [
            {"id": "fixture.enabled", "type": "boolean", "scope": "module", "default": False}
        ]}
        root = self.package(self.valid_manifest(), {"contract_version": 1, "contributions": [
            {"kind": "configuration", "id": "fixture.preferences", "schema": schema}
        ]})
        (root / "module.sh").write_text(":\n", encoding="utf-8")
        result = module_contract.validate_module(root)
        contribution = result["contributions"][0]
        self.assertEqual(contribution["schema"]["owner"], "fixture")
        self.assertEqual(contribution["schema"]["fields"][0]["id"], "fixture.enabled")
        self.assertNotIn("handler", contribution)

    def test_invalid_configuration_schema_rejects_module_contract(self):
        root = self.package(self.valid_manifest(), {"contract_version": 1, "contributions": [
            {"kind": "configuration", "id": "fixture.preferences",
             "schema": {"schema_version": 2, "fields": []}}
        ]})
        (root / "module.sh").write_text(":\n", encoding="utf-8")
        with self.assertRaisesRegex(module_contract.ValidationError, "schema is invalid"):
            module_contract.validate_module(root)

    def test_probe_preserves_permissive_v1_manifest(self):
        root = self.package("[module]\nname=fixture\nunknown_v1_key=value # inline\n")
        self.assertEqual(module_contract.probe_api(root), "1")

    def test_probe_rejects_malformed_marker(self):
        root = self.package("[module]\nmodule_api=two\n")
        with self.assertRaisesRegex(module_contract.ValidationError, "malformed"):
            module_contract.probe_api(root)

    def test_probe_rejects_marker_outside_module_section(self):
        root = self.package("[requirements]\nmodule_api=2\n")
        with self.assertRaisesRegex(module_contract.ValidationError, "must be in \\[module\\]"):
            module_contract.probe_api(root)

    def test_metadata_only_package_may_omit_runtime_and_entrypoint(self):
        contract = {"contract_version": 1, "contributions": [
            {"kind": "knowledge", "id": "host.basics", "path": "knowledge.md"}
        ]}
        manifest = self.valid_manifest()
        manifest = manifest.replace("runtime=bash\n", "").replace("entrypoint=module.sh\n", "")
        root = self.package(manifest, contract)
        (root / "knowledge.md").write_text("host\n")
        result = module_contract.validate_module(root)
        self.assertIsNone(result["manifest"]["runtime"])

    def test_handlers_require_bash_runtime_entrypoint_and_declared_function(self):
        contract = {"contract_version": 1, "contributions": [
            {"kind": "observer", "id": "host.memory", "handler": "fixture__observe", "output_type": "host.memory"}
        ]}
        missing_runtime = self.valid_manifest().replace("runtime=bash\n", "")
        root = self.package(missing_runtime, contract)
        (root / "module.sh").write_text("fixture__observe() { printf '{}'; }\n")
        with self.assertRaisesRegex(module_contract.ValidationError, "runtime=bash"):
            module_contract.validate_module(root)
        root = self.package(self.valid_manifest(), contract)
        (root / "module.sh").write_text(":\n")
        with self.assertRaisesRegex(module_contract.ValidationError, "not declared"):
            module_contract.validate_module(root)

    def test_kind_shapes_and_requirement_types_are_strict(self):
        contract = {"contract_version": 1, "contributions": [
            {"kind": "domain_event", "id": "fixture.host.changed", "path": "knowledge.md",
             "payload_schema": {"properties": {}, "required": [], "additionalProperties": False}}
        ]}
        root = self.package(self.valid_manifest(), contract)
        (root / "module.sh").write_text(":\n")
        (root / "knowledge.md").write_text("host\n")
        with self.assertRaisesRegex(module_contract.ValidationError, "only valid for knowledge"):
            module_contract.validate_module(root)
        contract["contributions"][0] = {
            "kind": "observer", "id": "host.memory", "handler": "fixture__observe",
            "output_type": "host.memory", "timeout_seconds": 1.5,
        }
        (root / "contracts/host.json").write_text(json.dumps(contract), encoding="utf-8")
        with self.assertRaisesRegex(module_contract.ValidationError, "positive integer"):
            module_contract.validate_module(root)

    def test_domain_event_requires_owned_flat_closed_payload(self):
        item = {"kind": "domain_event", "id": "fixture.host.changed",
                "payload_schema": {"properties": {"value": {"type": "integer", "minimum": 0}},
                                   "required": ["value"], "additionalProperties": False}}
        root = self.package(self.valid_manifest(), {"contract_version": 1, "contributions": [item]})
        (root / "module.sh").write_text(":\n")
        result = module_contract.validate_module(root)
        self.assertEqual(result["contributions"][0]["owner"], "fixture")
        item["id"] = "other.host.changed"
        (root / "contracts/host.json").write_text(json.dumps({"contract_version": 1, "contributions": [item]}))
        with self.assertRaisesRegex(module_contract.ValidationError, "must belong"):
            module_contract.validate_module(root)
        item["id"] = "fixture.host.changed"
        item["payload_schema"]["properties"]["value"] = {"type": "secret_ref"}
        (root / "contracts/host.json").write_text(json.dumps({"contract_version": 1, "contributions": [item]}))
        with self.assertRaisesRegex(module_contract.ValidationError, "invalid type"):
            module_contract.validate_module(root)
        item["payload_schema"]["properties"] = {"owner": {"type": "string"}}
        item["payload_schema"]["required"] = ["owner"]
        (root / "contracts/host.json").write_text(json.dumps({"contract_version": 1, "contributions": [item]}))
        with self.assertRaisesRegex(module_contract.ValidationError, "Core field"):
            module_contract.validate_module(root)

    def test_requirement_lists_reject_duplicate_or_unknown_platform_values(self):
        manifest = self.valid_manifest().replace("platform_families=\n", "platform_families=debian,debian\n")
        root = self.package(manifest, {"contract_version": 1, "contributions": []})
        (root / "module.sh").write_text(":\n")
        with self.assertRaisesRegex(module_contract.ValidationError, "duplicates"):
            module_contract.validate_module(root)
        manifest = self.valid_manifest().replace("platform_families=\n", "platform_families=fedora\n")
        root = self.package(manifest, {"contract_version": 1, "contributions": []})
        (root / "module.sh").write_text(":\n")
        with self.assertRaisesRegex(module_contract.ValidationError, "unsupported family"):
            module_contract.validate_module(root)

    def test_duplicate_json_keys_are_rejected(self):
        root = self.package(self.valid_manifest(), None)
        (root / "module.sh").write_text(":\n")
        (root / "contracts").mkdir()
        (root / "contracts/host.json").write_text(
            '{"contract_version":1,"contributions":[],"contributions":[]}'
        )
        with self.assertRaisesRegex(module_contract.ValidationError, "duplicate JSON key"):
            module_contract.validate_module(root)

    def test_path_escape_is_rejected(self):
        contract = {"contract_version": 1, "contributions": [
            {"kind": "knowledge", "id": "host.basics", "path": "../outside.md"}
        ]}
        root = self.package(self.valid_manifest(), contract)
        (root / "module.sh").write_text(":\n")
        with self.assertRaisesRegex(module_contract.ValidationError, "escapes"):
            module_contract.validate_module(root)

    def test_unknown_fields_and_duplicate_contributions_are_rejected(self):
        contract = {"contract_version": 1, "contributions": [
            {"kind": "knowledge", "id": "host.basics", "path": "knowledge.md", "extra": 1}
        ]}
        root = self.package(self.valid_manifest(), contract)
        (root / "module.sh").write_text(":\n")
        (root / "knowledge.md").write_text("host\n")
        with self.assertRaisesRegex(module_contract.ValidationError, "unknown field"):
            module_contract.validate_module(root)

    def test_cli_fields_is_tabular_and_validation_precedes_output(self):
        contract = {"contract_version": 1, "contributions": [
            {"kind": "knowledge", "id": "host.basics", "path": "knowledge.md"}
        ]}
        root = self.package(self.valid_manifest(), contract)
        (root / "module.sh").write_text(":\n")
        (root / "knowledge.md").write_text("host\n")
        result = subprocess.run([sys.executable, str(VALIDATOR), "fields", str(root)],
                                check=True, capture_output=True, text=True)
        self.assertIn("manifest\tname\tfixture\n", result.stdout)
        self.assertIn("contribution\tknowledge\thost.basics", result.stdout)
        self.assertEqual(result.stderr, "")


    def test_composite_capability_is_data_only_and_requires_exact_external_references(self):
        status = {
            "kind": "capability", "id": "fixture.status", "handler": "fixture__status",
            "capability_version": 2, "description": "Read fixture state.",
            "inputs": {"properties": {}, "required": [], "additionalProperties": False},
            "outputs": {"schema_version": 1, "properties": {"ready": {"type": "boolean"}},
                        "required": ["ready"], "additionalProperties": False},
            "safety": {"tier": "READ"}, "privilege": "none",
            "preconditions": [{"kind": "owner_active"}],
            "verification": {"kind": "none", "required": False},
            "recovery": {"class": "not_applicable"}, "affects": [],
        }
        composite = {
            "kind": "capability", "id": "fixture.install", "capability_version": 1,
            "description": "Install the fixture through host capabilities.",
            "inputs": {"properties": {}, "required": [], "additionalProperties": False},
            "safety": {"tier": "CHANGE"}, "privilege": "none",
            "preconditions": [{"kind": "owner_active"}],
            "verification": {"kind": "none", "required": False},
            "recovery": {"class": "best_effort"}, "affects": [],
            "implementation": {
                "kind": "composition", "intended_outcome": "The fixture is ready.",
                "variants": [
                    {"requires": {"platform_families": ["debian"]},
                     "steps": [{"capability_id": "system.package.install",
                                "inputs": {"package": "fixture-debian"}}]},
                    {"requires": {"platform_families": ["arch"]},
                     "steps": [{"capability_id": "system.package.install",
                                "inputs": {"package": "fixture-arch"}}]},
                ],
                "final_check": {"capability_id": "fixture.status", "inputs": {},
                                "expect": {"ready": True}},
            },
            "requires": {"capabilities": ["system.package.install"]},
        }
        root = self.package(
            self.valid_manifest(),
            {"contract_version": 1, "contributions": [status, composite]},
        )
        (root / "module.sh").write_text(
            "fixture__status() { printf '%s\\n' '{\"status\":\"ok\",\"result\":{\"ready\":true}}'; }\n",
            encoding="utf-8",
        )
        result = module_contract.validate_module(root)
        item = next(row for row in result["contributions"] if row["id"] == "fixture.install")
        self.assertNotIn("handler", item)
        self.assertEqual(item["implementation"]["kind"], "composition")
        self.assertEqual(item["implementation"]["variants"][0]["steps"][0]["inputs"]["package"],
                         "fixture-debian")

        forged = json.loads(json.dumps(composite))
        forged["requires"]["capabilities"] = []
        (root / "contracts/host.json").write_text(
            json.dumps({"contract_version": 1, "contributions": [status, forged]}),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(module_contract.ValidationError, "exactly match external"):
            module_contract.validate_module(root)

    def test_composite_capability_rejects_handler_overlap_and_ambiguous_platform_variants(self):
        item = {
            "kind": "capability", "id": "fixture.install", "capability_version": 1,
            "description": "Composite fixture.",
            "inputs": {"properties": {}, "required": [], "additionalProperties": False},
            "safety": {"tier": "CHANGE"}, "privilege": "none",
            "preconditions": [{"kind": "owner_active"}],
            "verification": {"kind": "none", "required": False},
            "recovery": {"class": "best_effort"}, "affects": [],
            "implementation": {
                "kind": "composition", "intended_outcome": "Ready.",
                "variants": [
                    {"requires": {"platform_families": ["debian"]},
                     "steps": [{"capability_id": "fixture.read", "inputs": {}}]},
                    {"requires": {"platform_families": ["debian"]},
                     "steps": [{"capability_id": "fixture.read", "inputs": {}}]},
                ],
                "final_check": {"capability_id": "fixture.read", "inputs": {},
                                "expect": {"ready": True}},
            },
            "requires": {"capabilities": []},
        }
        root = self.package(self.valid_manifest(),
                            {"contract_version": 1, "contributions": [item]})
        (root / "module.sh").write_text(":\n", encoding="utf-8")
        with self.assertRaisesRegex(module_contract.ValidationError, "overlap"):
            module_contract.validate_module(root)

        item["implementation"]["variants"] = item["implementation"]["variants"][:1]
        privileged = json.loads(json.dumps(item))
        privileged["privilege"] = "required"
        (root / "contracts/host.json").write_text(
            json.dumps({"contract_version": 1, "contributions": [privileged]}),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(module_contract.ValidationError, "direct privilege"):
            module_contract.validate_module(root)

        item["handler"] = "fixture__install"
        (root / "module.sh").write_text("fixture__install() { :; }\n", encoding="utf-8")
        (root / "contracts/host.json").write_text(
            json.dumps({"contract_version": 1, "contributions": [item]}),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(module_contract.ValidationError, "both handler and composite"):
            module_contract.validate_module(root)


if __name__ == "__main__":
    unittest.main()
