import tempfile
import unittest
from pathlib import Path

from validation_domains import affected_tests

ROOT = Path(__file__).resolve().parents[1]


class AffectedDomainTests(unittest.TestCase):
    def test_learning_mapping_retains_source_context_and_authority_regressions(self):
        domains, tests = affected_tests(["core/lib/local_learning.py"], ROOT)
        self.assertEqual(domains, ["learning"])
        self.assertTrue(
            {
                "tests/test_operational_history.py",
                "tests/test_investigations.py",
                "tests/test_baselines.py",
                "tests/test_context_engine.py",
                "tests/test_capability_runtime.py",
                "tests/core/test_ai_approval.bats",
                "tests/core/test_ai_privilege.bats",
            }.issubset(tests)
        )

        domains, tests = affected_tests(["igor.sh", "core/lib/local_learning.py"], ROOT)
        self.assertEqual(domains, ["entrypoint", "learning"])
        self.assertIn("tests/test_local_learning.py", tests)
        self.assertIn("tests/test_ai_architecture.py", tests)
        self.assertNotIn("tests/test_ai_tui.py", tests)

    def test_d064_capability_change_selects_required_domains_without_tui(self):
        domains, tests = affected_tests(
            [
                "core/lib/capability_runtime.py",
                "core/lib/package_admission.py",
                "core/lib/pkg.sh",
                "core/lib/operational_history.py",
                "core/lib/module_contract.py",
                "core/ai/safety.sh",
                "modules/docker/contracts/docker.json",
                "modules/system/contracts/host.json",
                "modules/nextcloud_docker/module.sh",
            ],
            ROOT,
        )

        self.assertTrue({"capability", "history", "module", "system"}.issubset(domains))
        self.assertTrue(
            {
                "tests/test_capability_runtime.py",
                "tests/core/test_safety_dispatch.bats",
                "tests/core/test_ai_approval.bats",
                "tests/core/test_ai_privilege.bats",
                "tests/test_operational_history.py",
                "tests/modules/test_operational_history_dispatch.bats",
                "tests/modules/test_wave_e_capability_dispatch.bats",
                "tests/modules/test_step18_module_contract.bats",
                "tests/modules/test_step18_module_composition.bats",
                "tests/modules/test_system_admin_surface.bats",
                "tests/test_docker_module.py",
            }.issubset(tests)
        )
        self.assertFalse(any("tui" in path.lower() for path in tests))
        pkg_domains, pkg_tests = affected_tests(["core/lib/pkg.sh"], ROOT)
        self.assertEqual(pkg_domains, ["capability"])
        self.assertFalse(any("tui" in path for path in pkg_tests))

    def test_unknown_implementation_change_falls_back_to_all_tests(self):
        domains, tests = affected_tests(["core/unmapped/new_boundary.py"], ROOT)
        self.assertEqual(domains, ["all"])
        self.assertIn("tests/test_ai_tui.py", tests)
        self.assertIn("tests/modules/test_loader_regressions.bats", tests)

    def test_root_entrypoint_alone_remains_broad_but_mapped_feature_bounds_it(self):
        domains, tests = affected_tests(["igor.sh"], ROOT)
        self.assertEqual(domains, ["all", "entrypoint"])
        self.assertIn("tests/test_ai_tui.py", tests)
        self.assertIn("tests/modules/test_loader_regressions.bats", tests)

        domains, tests = affected_tests(["igor.sh", "core/lib/operational_history.py"], ROOT)
        self.assertEqual(domains, ["entrypoint", "history"])
        self.assertIn("tests/test_ai_architecture.py", tests)
        self.assertIn("tests/test_startup_privilege.py", tests)
        self.assertIn("tests/core/test_ai_tui_backend.bats", tests)
        self.assertIn("tests/test_operational_history.py", tests)
        self.assertNotIn("tests/test_ai_tui.py", tests)
        self.assertNotIn("tests/modules/test_loader_regressions.bats", tests)

    def test_docs_only_change_selects_no_test_files(self):
        self.assertEqual(affected_tests(["docs/igor2/STATUS.md"], ROOT), (["documentation"], []))

    def test_changed_test_selects_itself_and_validation_tests_select_harness(self):
        domains, tests = affected_tests(["tests/test_context_engine.py"], ROOT)
        self.assertEqual(domains, ["tests"])
        self.assertEqual(tests, ["tests/test_context_engine.py"])

        _domains, harness_tests = affected_tests(["tests/validation_domains.py"], ROOT)
        self.assertIn("tests/test_validation_domains.py", harness_tests)
        self.assertEqual(affected_tests(["tests/validate.sh"], ROOT)[0], ["validation"])

    def test_shared_ci_change_selects_harness_contracts(self):
        domains, tests = affected_tests([".github/workflows/ci.yml"], ROOT)
        self.assertEqual(domains, ["validation"])
        self.assertTrue(tests)
        self.assertTrue(all(path.startswith("tests/test_validation_") for path in tests))

    def test_mapping_outputs_sorted_relative_existing_paths(self):
        domains, tests = affected_tests(["core/lib/operational_history.py"], ROOT)
        self.assertEqual(domains, sorted(domains))
        self.assertEqual(tests, sorted(tests))
        self.assertTrue(all(not Path(path).is_absolute() for path in tests))
        self.assertTrue(all((ROOT / path).is_file() for path in tests))

    def test_temp_fixture_unknown_fallback_is_bounded_to_test_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tests/core").mkdir(parents=True)
            (root / "tests/test_one.py").touch()
            (root / "tests/core/test_two.bats").touch()
            (root / "tests/not_a_test.txt").touch()
            self.assertEqual(
                affected_tests(["core/new_component.py"], root),
                (["all"], ["tests/core/test_two.bats", "tests/test_one.py"]),
            )


if __name__ == "__main__":
    unittest.main()
