"""Read-only package and runtime module inspection contract tests."""

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
import module_inspection


class ModuleInspectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.modules = self.root / "modules"
        self.modules.mkdir()
        (self.root / "config").mkdir()

    def package(self, name="fixture", api=2, contributions=None, manifest_extra=""):
        package = self.modules / name
        package.mkdir()
        if api == 2:
            (package / "contracts").mkdir()
            (package / "contracts/host.json").write_text(json.dumps({
                "contract_version": 1,
                "contributions": contributions or [],
            }), encoding="utf-8")
            manifest = (f"[module]\nmodule_api=2\nname={name}\ndisplay_name=Fixture\n"
                        "version=1.2.3\nruntime=bash\nentrypoint=module.sh\n"
                        "contracts=contracts/host.json\n" + manifest_extra)
        else:
            manifest = f"[module]\nname={name}\ndisplay_name=Legacy\nversion=0.9\n" + manifest_extra
        (package / "module.conf").write_text(manifest, encoding="utf-8")
        handlers = [item["handler"] for item in contributions or [] if item.get("handler")]
        (package / "module.sh").write_text(
            "".join(f"{handler}() {{ :; }}\n" for handler in handlers), encoding="utf-8")
        return package

    def test_v2_inspection_is_static_and_marks_omitted_policy_disabled(self):
        marker = self.root / "executed"
        package = self.package(contributions=[
            {"kind": "knowledge", "id": "fixture.basics", "path": "knowledge.md"}
        ])
        (package / "module.sh").write_text(f"touch {marker}\n", encoding="utf-8")
        (package / "knowledge.md").write_text("reference", encoding="utf-8")
        result = module_inspection.inspect_module(self.root, "fixture")
        self.assertFalse(marker.exists())
        self.assertEqual(result["module"]["validation"], "verified_by_module_api_v2_validator")
        self.assertEqual(result["lifecycle"]["policy_state"], "disabled_by_default")
        self.assertEqual(result["declarations"][0]["availability"], "owner_disabled")
        self.assertFalse(result["detach"]["ready"])

    def test_loader_snapshot_contributes_runtime_provenance_and_state(self):
        self.package(contributions=[
            {"kind": "capability", "id": "fixture.refresh", "handler": "fixture__refresh"}
        ])
        runtime = {
            "module_states": {"fixture": {"status": "active", "reason": "", "loaded": True, "enabled": True}},
            "contributions": [{"index_key": "capability:fixture.refresh", "id": "fixture.refresh",
                               "kind": "capability", "owner": "fixture", "source": "contracts/host.json",
                               "availability": "active", "descriptor": {"selected": True}}],
            "configuration": [{"id": "fixture.limit", "owner": "fixture", "availability": "available"}],
            "model": {"facts": [{"id": "host.memory", "owner": "fixture"}],
                      "responsibilities": [], "observers": {}, "health": {}},
        }
        result = module_inspection.inspect_module(self.root, "fixture", runtime)
        self.assertEqual(result["lifecycle"]["runtime_status"], "active")
        self.assertTrue(result["lifecycle"]["loaded"])
        self.assertEqual(result["capabilities"][0]["availability"], "active")
        self.assertEqual(result["capabilities"][0]["descriptor"]["id"], "fixture.refresh")
        self.assertEqual(result["system_model"]["facts"][0]["id"], "host.memory")
        self.assertEqual(result["configuration"]["service"][0]["id"], "fixture.limit")

    def test_detach_plan_reports_dependencies_and_unavoidable_unknowns(self):
        self.package(contributions=[
            {"kind": "capability", "id": "fixture.refresh", "handler": "fixture__refresh"}
        ])
        dependent = self.modules / "dependent"
        dependent.mkdir()
        (dependent / "module.conf").write_text(
            "[module]\nmodule_api=2\nname=dependent\ndisplay_name=Dependent\nversion=1.0.0\n"
            "contracts=contracts/host.json\n[requirements]\nrequired_modules=fixture\n",
            encoding="utf-8")
        (dependent / "contracts").mkdir()
        (dependent / "contracts/host.json").write_text(json.dumps({"contract_version": 1, "contributions": []}))
        result = module_inspection.inspect_module(self.root, "fixture", action="detach-plan")
        detach = result["detach"]
        self.assertFalse(detach["ready"])
        self.assertEqual(detach["completeness"], "incomplete")
        self.assertTrue(any(row["module"] == "dependent" and row["requirement"] == "required_module"
                            for row in detach["declared_dependents"]))
        self.assertIn("resource_bindings", detach["unknown"])
        self.assertIn("operational_history", detach["retained"])

    def test_v1_metadata_is_best_effort_and_uses_compatibility_default(self):
        self.package(api=1, manifest_extra="display_name=From another section\n")
        runtime = {"contributions": [{"index_key": "hook:health", "owner": "fixture",
                                      "availability": "active", "descriptor": "legacy hook"}]}
        result = module_inspection.inspect_module(self.root, "fixture", runtime)
        self.assertEqual(result["module"]["api"], 1)
        self.assertEqual(result["module"]["validation"], "best_effort_unverified")
        self.assertEqual(result["lifecycle"]["policy_state"], "enabled_compatibility_default")
        self.assertEqual(result["lifecycle"]["runtime_status"], "not_evaluated")
        self.assertIsNone(result["lifecycle"]["loaded"])
        self.assertEqual(result["declarations"][0]["id"], "health")
        self.assertEqual(result["declarations"][0]["kind"], "hook")
        self.assertEqual(result["declarations"][0]["descriptor"], {})
        self.assertIsNone(result["dependencies"]["required_modules"])
        self.assertIn("required_modules", result["dependencies"]["dependency_metadata_unknown_fields"])

    def test_v1_dependency_lists_are_parsed_and_ordering_is_not_hard_dependency(self):
        self.package(api=1, manifest_extra=(
            "required_modules=system\noptional_modules=other:Optional integration\n"
            "required_capabilities=system.restart\noptional_capabilities=system.inspect\n"
            "required_bins=curl,systemctl\ndepends_on=system\n"))
        dependencies = module_inspection.inspect_module(self.root, "fixture")["dependencies"]
        self.assertEqual(dependencies["required_modules"], ["system"])
        self.assertEqual(dependencies["optional_modules"], ["other"])
        self.assertEqual(dependencies["required_capabilities"], ["system.restart"])
        self.assertEqual(dependencies["optional_capabilities"], ["system.inspect"])
        self.assertEqual(dependencies["required_bins"], ["curl", "systemctl"])
        self.assertEqual(dependencies["depends_on_ordering_only"], ["system"])

    def test_runtime_service_rows_are_scoped_to_requested_owner(self):
        self.package()
        runtime = {
            "configuration": [
                {"id": "fixture.safe", "owner": "fixture", "desired_value": False},
                {"id": "other.secret", "owner": "other"},
                {"id": "fixture.schema", "schema_owner": "fixture"},
            ],
            "model": {
                "facts": [{"id": "fixture.fact", "owner": "fixture"}, {"id": "other.fact", "owner": "other"}],
                "responsibilities": [{"id": "fixture.resp", "owner": "fixture"},
                                     {"id": "other.resp", "owner": "other"}],
                "observers": {"one": {"id": "fixture.observe", "owner": "fixture"},
                              "two": {"id": "other.observe", "owner": "other"}},
                "health": [{"id": "fixture.health", "schema_owner": "fixture"},
                           {"id": "other.health", "owner": "other"}],
            },
        }
        result = module_inspection.inspect_module(self.root, "fixture", runtime)
        self.assertEqual([row["id"] for row in result["configuration"]["service"]], ["fixture.safe", "fixture.schema"])
        self.assertEqual([row["id"] for row in result["system_model"]["facts"]], ["fixture.fact"])
        self.assertEqual([row["id"] for row in result["system_model"]["responsibilities"]], ["fixture.resp"])
        self.assertEqual([row["id"] for row in result["system_model"]["observers"]], ["fixture.observe"])
        self.assertEqual([row["id"] for row in result["system_model"]["health"]], ["fixture.health"])
        self.assertEqual(result["configuration"]["desired_availability"], "available")
        self.assertEqual(result["configuration"]["application_availability"], "not_observed")

    def test_detach_accounts_local_requirements_contributions_and_unresolved_packages(self):
        self.package(contributions=[
            {"kind": "capability", "id": "fixture.refresh", "handler": "fixture__refresh"}
        ])
        dependent = self.modules / "dependent"
        dependent.mkdir()
        (dependent / "contracts").mkdir()
        (dependent / "module.conf").write_text(
            "[module]\nmodule_api=2\nname=dependent\ndisplay_name=Dependent\nversion=1.0.0\n"
            "contracts=contracts/host.json\n",
            encoding="utf-8")
        (dependent / "contracts/host.json").write_text(json.dumps({"contract_version": 1, "contributions": [
            {"kind": "knowledge", "id": "dependent.guide", "path": "guide.md", "requires": {
                "modules": ["fixture"], "capabilities": ["fixture.refresh"]}}
        ]}))
        (dependent / "guide.md").write_text("guide", encoding="utf-8")
        broken = self.modules / "unreadable"
        broken.mkdir()
        (broken / "module.conf").write_text("[module]\nmodule_api=2\n", encoding="utf-8")
        result = module_inspection.inspect_module(self.root, "fixture", action="detach-plan")
        detach = result["detach"]
        matches = [row for row in detach["declared_dependents"] if row.get("module") == "dependent"]
        self.assertEqual({row["requirement"] for row in matches}, {"contribution_module", "contribution_capability"})
        self.assertTrue(all(row["impact"] == "declared_requirement_provider_may_be_affected" for row in matches))
        self.assertEqual(detach["contributions"], [{"key": "capability:fixture.refresh", "availability": "owner_disabled"}])
        self.assertEqual(detach["unresolved_packages"], ["unreadable"])

    def test_secret_system_fact_values_are_redacted_in_inspection_and_detach(self):
        self.package()
        raw_marker = "credential-marker-avoid-output"
        runtime = {"model": {"facts": [
            {"id": "fixture.password", "owner": "fixture", "property": "database.password",
             "value": raw_marker, "availability": "available", "source": "observer.fixture"},
            {"id": "other.token", "owner": "other", "property": "api_token", "value": raw_marker},
        ], "responsibilities": [], "observers": {}, "health": {}}}
        result = module_inspection.inspect_module(self.root, "fixture", runtime, action="detach-plan")
        self.assertNotIn(raw_marker, json.dumps(result))
        self.assertEqual(result["system_model"]["facts"][0]["availability"], "available")
        self.assertEqual(result["system_model"]["facts"][0]["source"], "observer.fixture")
        self.assertTrue(result["system_model"]["facts"][0]["redacted"])
        self.assertTrue(result["detach"]["facts"][0]["redacted"])

    def test_snapshot_cli_rejects_duplicate_and_nonfinite_json_without_traceback(self):
        for request in ('{"root":"/tmp","name":"fixture","name":"fixture"}',
                        '{"root":"/tmp","name":"fixture","runtime":{"x":NaN}}',
                        '{"root":7,"name":"fixture"}'):
            stderr = io.StringIO()
            with (contextlib.redirect_stderr(stderr), contextlib.redirect_stdout(io.StringIO()),
                  mock.patch.object(sys, "stdin", io.StringIO(request))):
                code = module_inspection.main(["--snapshot"])
            self.assertEqual(code, 2)
            self.assertNotIn("Traceback", stderr.getvalue())

    def test_static_projection_marks_runtime_configuration_and_health_unobserved(self):
        self.package()
        result = module_inspection.inspect_module(self.root, "fixture")
        self.assertEqual(result["system_model"]["availability"], "not_evaluated")
        self.assertEqual(result["system_model"]["health_availability"], "not_evaluated")
        self.assertEqual(result["configuration"]["service_availability"], "not_supplied")
        self.assertEqual(result["configuration"]["desired_availability"], "not_supplied")
        self.assertEqual(result["configuration"]["application_availability"], "not_supplied")
        facts_only = module_inspection.inspect_module(self.root, "fixture", {
            "model": {"facts": [{"id": "fixture.fact", "owner": "fixture"}]}
        })["system_model"]
        self.assertEqual(facts_only["facts_availability"], "available")
        self.assertEqual(facts_only["health_availability"], "not_evaluated")

    def test_symlinked_package_and_malformed_policy_are_rejected(self):
        package = self.package()
        (package / "external").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(module_inspection.InspectionError, "symlink"):
            module_inspection.inspect_module(self.root, "fixture")
        (package / "external").unlink()
        (self.root / "config/modules.conf").write_text("fixture=maybe\n", encoding="utf-8")
        with self.assertRaisesRegex(module_inspection.InspectionError, "malformed"):
            module_inspection.inspect_module(self.root, "fixture")


if __name__ == "__main__":
    unittest.main()
