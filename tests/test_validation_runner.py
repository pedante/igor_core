"""Tiny fixtures prove the harness without invoking Igor product regressions."""

import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import validation_runner as runner


class ValidationRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("tests/validation_baseline.json", json.dumps({"schema_version": 1, "source_commit": "a" * 40, "entries": []}))

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def command(self, *args):
        return subprocess.run(args, cwd=self.root, capture_output=True, check=True)

    def init_git(self):
        self.command("git", "init", "-b", "igor2")
        self.command("git", "config", "user.email", "fixture@example.invalid")
        self.command("git", "config", "user.name", "Fixture")
        self.write("tracked.txt", "original")
        self.command("git", "add", ".")
        self.command("git", "commit", "-m", "fixture base")

    def run_main(self, *args):
        evidence = self.root / "evidence"
        with patch.object(runner, "ROOT", self.root), contextlib.redirect_stdout(io.StringIO()):
            code = runner.main([*args, "--output-dir", str(evidence)])
        return code, json.loads((evidence / "summary.json").read_text())

    def test_pass_and_assertion_failure_preserve_raw_logs(self):
        for script, status in (("print('fixture pass')", "PASS"), ("assert False, 'fixture assertion'", "FAIL")):
            log = self.root / f"{status}.log"
            result = runner.execute([sys.executable, "-c", script], self.root, log, 5)
            self.assertEqual(result["status"], status)
            self.assertIn("fixture", log.read_text())

    def test_missing_command_is_distinct(self):
        result = runner.execute([str(self.root / "missing-tool")], self.root, self.root / "missing.log", 1)
        self.assertEqual(result["status"], "TOOL_UNAVAILABLE")

    def test_timeout_kills_descendant_and_preserves_evidence(self):
        marker = self.root / "child-marker"
        script = ("import subprocess,sys,time; "
                  f"subprocess.Popen([sys.executable,'-c',\"import time,pathlib; time.sleep(1); pathlib.Path({str(marker)!r}).touch()\"]); "
                  "print('before timeout',flush=True); time.sleep(30)")
        log = self.root / "timeout.log"
        result = runner.execute([sys.executable, "-c", script], self.root, log, 0.2)
        self.assertEqual(result["status"], "TIMEOUT")
        self.assertLess(result["elapsed_seconds"], 2)
        time.sleep(1.1)
        self.assertFalse(marker.exists())
        self.assertIn("before timeout", log.read_text())
        self.assertIn("TIMEOUT", log.read_text())

    def test_successful_runner_cleans_background_children(self):
        marker = self.root / "orphan-marker"
        script = ("import subprocess,sys; "
                  f"subprocess.Popen([sys.executable,'-c',\"import time,pathlib; time.sleep(1); pathlib.Path({str(marker)!r}).touch()\"])")
        self.assertEqual(runner.execute([sys.executable, "-c", script], self.root,
                                       self.root / "orphan.log", 5)["status"], "PASS")
        time.sleep(1.1)
        self.assertFalse(marker.exists())

    def test_git_selection_includes_committed_staged_unstaged_untracked_deleted(self):
        self.init_git()
        self.command("git", "branch", "base")
        self.write("committed.py", "pass\n")
        self.command("git", "add", ".")
        self.command("git", "commit", "-m", "change")
        self.write("staged.json", "{}")
        self.command("git", "add", "staged.json")
        self.write("committed.py", "# unstaged\n")
        self.write("untracked space.py", "pass")
        (self.root / "tracked.txt").unlink()
        self.assertEqual(runner.changed_files(self.root, "base"),
                         ["committed.py", "staged.json", "tracked.txt", "untracked space.py"])

    def test_focused_selects_conventional_and_explicit_tests(self):
        self.write("tests/test_widget.py", "pass")
        self.write("tests/test_extra.py", "pass")
        _, plan = runner.make_plan(self.root, "focused", ["core/widget.py"], ["tests/test_extra.py::test_one"])
        self.assertEqual([group["files"] for group in plan if group["kind"] == "pytest"],
                         [["tests/test_extra.py::test_one"], ["tests/test_widget.py"]])

    def test_full_plan_cannot_omit_canonical_suites_or_nested_python(self):
        self.write("tests/test_igor_core.sh", "exit 0")
        self.write("tests/test_ai_render.py", "pass")
        self.write("tests/core/test_nested.py", "pass")
        for directory in ("core", "modules", "integration"):
            self.write(f"tests/{directory}/test_fixture.bats", '@test "pass" { true; }')
        _, plan = runner.make_plan(self.root, "full", [])
        identifiers = [group["id"] for group in plan]
        self.assertIn("canonical:bash", identifiers)
        self.assertIn("canonical:rendering", identifiers)
        self.assertIn("pytest:tests/core/test_nested.py", identifiers)
        for directory in ("core", "modules", "integration"):
            self.assertTrue(any(identity.startswith(f"canonical:{directory}:") for identity in identifiers))
        (self.root / "tests/integration/test_fixture.bats").unlink()
        with self.assertRaisesRegex(ValueError, "Canonical BATS"):
            runner.make_plan(self.root, "full", [])

    def test_changed_module_json_schedules_semantic_contract_validation(self):
        self.write("modules/example/module.conf", "module_api=2")
        self.write("modules/example/contracts/example.json", "{}")
        _, plan = runner.make_plan(self.root, "focused", ["modules/example/contracts/example.json"])
        self.assertIn({"id": "contract:modules/example", "kind": "module-contract", "files": ["modules/example"]}, plan)

    def test_missing_tool_makes_summary_nonzero(self):
        self.init_git()
        self.write("example.py", "pass")
        code, summary = self.run_main("focused", "--ruff", str(self.root / "missing-ruff"))
        self.assertEqual(code, 1)
        self.assertEqual(summary["counts"]["TOOL_UNAVAILABLE"], 1)

    def test_mode_runs_do_not_schedule_full_implicitly(self):
        self.write("tests/test_one.py", "pass")
        for mode in ("focused", "affected"):
            _, plan = runner.make_plan(self.root, mode, ["tests/validate.sh"])
            self.assertFalse(any(group["id"].startswith("canonical:") for group in plan))

    def test_structure_checks_json_python_docs_and_deleted_paths(self):
        self.write("sample.json", "{}")
        self.write("sample.py", "pass")
        self.write("docs/page.md", "[valid](../sample.json) [external](https://example.invalid) [anchor](#x)")
        checked, errors = runner.structural_checks(self.root, ["sample.json", "sample.py", "docs/page.md", "deleted.py"])
        self.assertEqual(len(checked), 3)
        self.assertEqual(errors, [])
        self.write("docs/page.md", "[bad](missing.md)")
        self.assertTrue(runner.structural_checks(self.root, ["docs/page.md"])[1])

    def test_bad_json_and_python_fail(self):
        for name, content in (("bad.json", "{"), ("bad.py", "if:")):
            self.write(name, content)
            with self.assertRaises((ValueError, SyntaxError)):
                runner.structural_checks(self.root, [name])

    def test_summary_success_and_failure_exit_codes(self):
        self.init_git()
        self.write("bad.json", "{")
        code, summary = self.run_main("focused")
        self.assertEqual(code, 1)
        self.assertEqual(summary["counts"]["FAIL_NEW"], 1)
        self.assertEqual(summary["count_unit"], "test_identities_and_check_groups")
        self.assertTrue(Path(summary["groups"][0]["log"]).is_file())

    def test_summary_pass(self):
        self.init_git()
        code, summary = self.run_main("focused")
        self.assertEqual(code, 0)
        self.assertEqual(summary["counts"]["PASS"], 1)

    def test_invalid_ref_reports_error_not_empty_success(self):
        self.init_git()
        code, summary = self.run_main("focused", "--base", "missing-ref")
        self.assertEqual(code, 1)
        self.assertEqual(summary["counts"]["ERROR"], 1)

    def test_malformed_baseline_reports_error_before_any_tests(self):
        self.init_git()
        self.write("tests/validation_baseline.json", '{"schema_version":999}')
        code, summary = self.run_main("focused")
        self.assertEqual(code, 1)
        self.assertEqual(summary["counts"]["ERROR"], 1)
        self.assertEqual(len(summary["groups"]), 1)

    def test_accepted_failure_has_success_exit_and_raw_failed_group(self):
        self.write("tests/test_example.py", "def test_failure(): assert False\n")
        self.write("tests/validation_baseline.json", json.dumps({"schema_version": 1, "source_commit": "a" * 40,
                   "entries": [{"suite": "pytest", "identity": "tests/test_example.py::test_failure",
                                "classification": "FAIL", "reason": "reproduced fixture"}]}))
        self.init_git()
        code, summary = self.run_main("focused", "--test", "tests/test_example.py")
        self.assertEqual(code, 0)
        self.assertEqual(summary["counts"]["FAIL_BASELINE"], 1)
        self.assertEqual(summary["groups"][-1]["status"], "FAIL")

    def test_paths_outside_repository_fail_closed(self):
        with self.assertRaises(ValueError):
            runner.local_path(self.root, "../outside.py")

    def test_bats_native_timeout_continues_and_retains_skip_without_classification(self):
        bats = shutil.which("bats")
        self.assertIsNotNone(bats, "BATS required for harness acceptance")
        self.write("tests/test_fixture.bats", '@test "slow" { sleep 20; }\n@test "after" { echo continued; }\n@test "skip" { skip "fixture reason"; }\n')
        args = type("Args", (), {"bats": bats, "python": sys.executable, "ruff": "ruff",
                                 "shellcheck": "shellcheck", "bats_timeout": 1,
                                 "group_timeout": 10, "slow_timeout": 20})()
        result = runner.run_group({"id": "fixture", "kind": "bats", "files": ["tests/test_fixture.bats"]},
                                  self.root, self.root, 0, args)
        self.assertEqual(result["status"], "TIMEOUT")
        self.assertEqual(result["native_timeout_count"], 1)
        self.assertEqual(result["runner_skip_count"], 1)
        self.assertIn("ok 2 after", Path(result["log"]).read_text())

    def test_bats_watchdog_is_disabled_unless_explicitly_requested(self):
        args = type("Args", (), {"bats": "bats", "python": sys.executable, "ruff": "ruff",
                                 "shellcheck": "shellcheck", "bats_timeout": 0,
                                 "group_timeout": 600, "slow_timeout": 1200})()

        def fake_execute(command, root, log, seconds, env):
            self.assertNotIn("BATS_TEST_TIMEOUT", env)
            log.write_text("1..1\nok 1 fixture in 1ms\n")
            return {"status": "PASS", "returncode": 0, "elapsed_seconds": 0, "log": str(log)}

        with patch.dict(os.environ, {"BATS_TEST_TIMEOUT": "999"}, clear=False):
            with patch.object(runner, "execute", side_effect=fake_execute):
                runner.run_group({"id": "fixture", "kind": "bats", "files": ["tests/test_fixture.bats"]},
                                 self.root, self.root, 0, args)

    def test_system_administration_slice_uses_larger_file_budget(self):
        args = type("Args", (), {"bats": "bats", "python": sys.executable, "ruff": "ruff",
                                 "shellcheck": "shellcheck", "bats_timeout": 180,
                                 "group_timeout": 600, "slow_timeout": 1200})()

        def fake_execute(command, root, log, seconds, env):
            log.write_text("1..1\nok 1 fixture in 1ms\n")
            return {"status": "PASS", "returncode": 0, "elapsed_seconds": 0, "log": str(log)}

        with patch.object(runner, "execute", side_effect=fake_execute) as execute:
            runner.run_group({"id": "fixture", "kind": "bats",
                              "files": ["tests/modules/test_system_admin_surface.bats"]},
                             self.root, self.root, 0, args)
            self.assertEqual(execute.call_args.args[3], 1200)
            self.assertEqual(execute.call_args.args[4]["BATS_TEST_TIMEOUT"], "180")
            runner.run_group({"id": "fixture", "kind": "bats", "files": ["tests/test_other.bats"]},
                             self.root, self.root, 1, args)
            self.assertEqual(execute.call_args.args[3], 600)

    def test_missing_pytest_fails_distinctly(self):
        python = self.write("python-without-pytest", "#!/bin/sh\necho 'No module named pytest' >&2\nexit 1\n")
        python.chmod(0o755)
        args = type("Args", (), {"bats": "bats", "python": str(python), "ruff": "ruff",
                                 "shellcheck": "shellcheck", "bats_timeout": 1,
                                 "group_timeout": 5, "slow_timeout": 20})()
        result = runner.run_group({"id": "fixture", "kind": "pytest", "files": ["tests/test_fixture.py"]},
                                  self.root, self.root, 0, args)
        self.assertEqual(result["status"], "TOOL_UNAVAILABLE")


if __name__ == "__main__":
    unittest.main()
