"""Tiny fixtures prove the harness without invoking Igor product regressions."""

import concurrent.futures
import contextlib
import io
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
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

    def run_main(self, *args, output_name="evidence"):
        evidence = self.root / output_name
        with patch.object(runner, "ROOT", self.root), contextlib.redirect_stdout(io.StringIO()):
            code = runner.main([*args, "--output-dir", str(evidence)])
        return code, json.loads((evidence / "summary.json").read_text())

    def test_repository_checkpoint_does_not_expand_affected_selection(self):
        self.write("tests/test_unrelated.py", "def test_unrelated(): pass\n")
        self.write("tests/test_documentation_health.py", "def test_documentation(): pass\n")
        self.init_git()
        self.write("docs/change.md", "A real documentation change.\n")
        code, summary = self.run_main("affected", "--base", "HEAD", "--dry-run",
                                      output_name="validation-results")
        self.assertEqual(code, 0)
        self.assertEqual(summary["changed_files"], ["docs/change.md"])
        self.assertEqual(summary["domains"], ["documentation"])
        self.assertEqual([group["files"] for group in summary["plan"] if group["kind"] == "pytest"],
                         [["tests/test_documentation_health.py"]])
        self.assertEqual(summary["run_state"], "planned")

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
        self.assertEqual(sum(group["files"] == ["tests/test_ai_render.py"] for group in plan), 1)
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

    def test_fail_fast_preflight_stops_before_behavior_groups(self):
        self.init_git()
        self.write("bad.py", "if:")
        self.write("tests/test_bad.py", "def test_never_runs(): pass\n")
        code, summary = self.run_main("focused", "--fail-fast-preflight")
        self.assertEqual(code, 1)
        self.assertEqual([group["id"] for group in summary["groups"]], ["structure"])

    def test_interactive_pytest_uses_shorter_timeout_budget(self):
        args = type("Args", (), {"bats": "bats", "python": sys.executable, "ruff": "ruff",
                                 "shellcheck": "shellcheck", "bats_timeout": 0,
                                 "group_timeout": 600, "interactive_timeout": 45,
                                 "slow_timeout": 1200})()

        def fake_execute(command, root, log, seconds, env):
            self.assertEqual(seconds, 45)
            log.write_text("fixture\n")
            return {"status": "PASS", "returncode": 0, "elapsed_seconds": 0, "log": str(log)}

        with patch.object(runner, "execute", side_effect=fake_execute):
            runner.run_group(
                {"id": "fixture", "kind": "pytest", "files": ["tests/test_ai_tui.py"]},
                self.root,
                self.root,
                0,
                args,
            )

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

    def test_fast_failing_bats_does_not_pay_native_watchdog_deadline_by_default(self):
        bats = shutil.which("bats")
        self.assertIsNotNone(bats, "BATS required for harness acceptance")
        self.write("tests/test_fixture.bats", '@test "fast failure" { false; }\n')
        args = type("Args", (), {"bats": bats, "python": sys.executable, "ruff": "ruff",
                                 "shellcheck": "shellcheck", "bats_timeout": 0,
                                 "group_timeout": 5, "slow_timeout": 20})()

        result = runner.run_group(
            {"id": "fixture", "kind": "bats", "files": ["tests/test_fixture.bats"]},
            self.root,
            self.root,
            0,
            args,
        )
        self.assertEqual(result["status"], "FAIL")
        self.assertEqual(result["native_failure_count"], 1)
        self.assertEqual(result["native_timeout_count"], 0)
        self.assertLess(result["elapsed_seconds"], 3)

    def test_bats_watchdog_is_disabled_unless_explicitly_requested(self):
        args = type("Args", (), {"bats": "bats", "python": sys.executable, "ruff": "ruff",
                                 "shellcheck": "shellcheck", "bats_timeout": 0,
                                 "group_timeout": 600, "slow_timeout": 1200})()

        def fake_execute(command, root, log, seconds, env):
            self.assertNotIn("BATS_TEST_TIMEOUT", env)
            log.write_text("1..1\nok 1 fixture in 1ms\n")
            return {"status": "PASS", "returncode": 0, "elapsed_seconds": 0, "log": str(log)}

        with (
            patch.dict(os.environ, {"BATS_TEST_TIMEOUT": "999"}, clear=False),
            patch.object(runner, "execute", side_effect=fake_execute),
        ):
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

    def test_serial_lane_overlaps_private_service_and_preserves_plan_order(self):
        plan = [
            {"id": "structure", "kind": "structure", "files": []},
            {"id": "serial:first", "kind": "bats", "files": ["tests/first.bats"]},
            {"id": "serial:second", "kind": "bats", "files": ["tests/second.bats"]},
            {"id": "private", "kind": "pytest", "files": ["tests/test_local_learning.py"]},
            {"id": "contract", "kind": "module-contract", "files": ["modules/example"]},
        ]
        args = SimpleNamespace(jobs=2, progress_interval=.1, fail_fast_preflight=False,
                               cancel_event=threading.Event())
        serial_started, private_started, private_checkpointed = [threading.Event() for _ in range(3)]
        finished = []
        snapshots = []

        def fixture(group, root, output, index, _args):
            if group["id"] == "serial:first":
                self.assertEqual(finished, ["structure", "contract"])
                serial_started.set()
                self.assertTrue(private_started.wait(3), "private lane never overlapped serial lane")
                self.assertTrue(private_checkpointed.wait(3), "completed private evidence was not checkpointed")
            elif group["id"] == "private":
                self.assertTrue(serial_started.wait(3))
                private_started.set()
            elif group["id"] == "serial:second":
                self.assertIn("serial:first", finished)
            finished.append(group["id"])
            return {**group, "status": "PASS", "returncode": 0, "elapsed_seconds": 0}

        def checkpoint(state, completed, active, pending):
            snapshots.append((state, sorted(completed), sorted(active), sorted(pending)))
            if 3 in completed:
                private_checkpointed.set()

        with patch.object(runner, "run_group", side_effect=fixture), contextlib.redirect_stdout(io.StringIO()):
            state = runner.run_plan(plan, self.root, self.root, args, checkpoint)
        self.assertEqual(state, "complete")
        self.assertEqual(snapshots[-1], ("complete", [0, 1, 2, 3, 4], [], []))
        self.assertTrue(any(3 in complete and 1 in active for _, complete, active, _ in snapshots))

    def test_worker_crash_is_error_and_other_groups_continue(self):
        self.write("tests/test_a.py", "def test_a(): pass\n")
        self.write("tests/test_local_learning.py", "def test_b(): pass\n")
        self.init_git()

        def fixture(group, root, output, index, args):
            if group["files"] == ["tests/test_a.py"]:
                raise RuntimeError("fixture worker crash")
            return {**group, "status": "PASS", "returncode": 0, "elapsed_seconds": 0}

        with patch.object(runner, "run_group", side_effect=fixture):
            code, summary = self.run_main("focused", "--jobs", "2", "--test", "tests/test_a.py",
                                          "--test", "tests/test_local_learning.py")
        self.assertEqual(code, 1)
        self.assertEqual(summary["counts"]["ERROR"], 1)
        self.assertEqual(summary["run_state"], "complete")
        self.assertEqual(summary["groups"][-1]["status"], "PASS")
        self.assertEqual(summary["pending_groups"], [])

    def test_private_bats_and_pytest_overlap_with_one_unsafe_bats_lane(self):
        plan = [
            {"id": "unsafe:first", "kind": "bats", "files": ["tests/modules/test_unknown.bats"]},
            {"id": "unsafe:second", "kind": "bats", "files": ["tests/core/test_unknown.bats"]},
            {"id": "private:bats", "kind": "bats", "files": ["tests/core/test_ai_privilege.bats"]},
            {"id": "private:pytest", "kind": "pytest", "files": ["tests/test_local_learning.py"]},
        ]
        args = SimpleNamespace(jobs=3, progress_interval=.1, fail_fast_preflight=False,
                               cancel_event=threading.Event())
        overlap = threading.Barrier(3, timeout=3)
        lock = threading.Lock()
        unsafe_active = []
        final = {}

        def fixture(group, root, output, index, _args):
            unsafe = group["id"].startswith("unsafe:")
            if unsafe:
                with lock:
                    self.assertEqual(unsafe_active, [], "unsafe BATS groups overlapped")
                    unsafe_active.append(group["id"])
            if group["id"] != "unsafe:second":
                # All three distinct workers must be active simultaneously.
                overlap.wait()
            if unsafe:
                with lock:
                    unsafe_active.remove(group["id"])
            return {**group, "status": "PASS", "returncode": 0, "elapsed_seconds": 0}

        def checkpoint(state, completed, active, pending):
            self.assertFalse(0 in active and 1 in active, "scheduler dispatched two unsafe BATS groups")
            if state == "complete":
                final.update(completed)

        with patch.object(runner, "run_group", side_effect=fixture), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.run_plan(plan, self.root, self.root, args, checkpoint), "complete")
        self.assertEqual(len(final), 4)
        self.assertEqual([final[index]["status"] for index in sorted(final)], ["PASS"] * 4)

    def test_serial_and_parallel_preserve_exact_identities_and_failure_classifications(self):
        self.write("tests/test_local_learning.py", '''def test_pass(): pass
def test_accepted(): assert False, "accepted fixture"
def test_regression(): assert False, "introduced fixture"
def test_timeout(): raise TimeoutError("inner fixture timeout")
''')
        self.write("tests/test_serial.py", "def test_serial(): pass\n")
        entry = {"suite": "pytest", "identity": "tests/test_local_learning.py::test_accepted",
                 "classification": "FAIL", "reason": "reviewed fixture failure"}
        self.write("tests/validation_baseline.json", json.dumps({"schema_version": 1,
                   "source_commit": "a" * 40, "entries": [entry]}))
        self.init_git()
        outcomes = []
        for jobs in (1, 2):
            code, summary = self.run_main("focused", "--jobs", str(jobs),
                                          "--test", "tests/test_serial.py",
                                          "--test", "tests/test_local_learning.py", output_name=f"jobs-{jobs}")
            self.assertEqual(code, 1)
            self.assertEqual(summary["counts"]["FAIL_BASELINE"], 1)
            self.assertEqual(summary["counts"]["FAIL_NEW"], 1)
            self.assertEqual(summary["counts"]["TIMEOUT_NEW"], 1)
            outcomes.append([(row["suite"], row["identity"], row["classification"])
                             for row in summary["results"]])
        self.assertEqual(outcomes[0], outcomes[1])

    def test_periodic_progress_reports_active_work_without_waiting_for_completion(self):
        plan = [{"id": "slow:fixture", "kind": "pytest", "files": ["tests/test_other.py"]}]
        args = SimpleNamespace(jobs=1, progress_interval=.1, fail_fast_preflight=False,
                               cancel_event=threading.Event())
        release = threading.Event()
        console = io.StringIO()

        def fixture(group, root, output, index, _args):
            self.assertTrue(release.wait(3), "no periodic progress arrived while fixture was active")
            return {**group, "status": "PASS", "returncode": 0, "elapsed_seconds": 0}

        def checkpoint(state, completed, active, pending):
            if "Progress:" in console.getvalue():
                release.set()

        with patch.object(runner, "run_group", side_effect=fixture), contextlib.redirect_stdout(console):
            self.assertEqual(runner.run_plan(plan, self.root, self.root, args, checkpoint), "complete")
        self.assertIn("0/1 complete; 0 pending; active: slow:fixture", console.getvalue())

    def test_simultaneous_pytest_groups_have_private_environment_and_fixture_storage(self):
        source = '''import json, os, pathlib, subprocess, sys, tempfile
def test_isolated(tmp_path):
    poisoned = ("IGOR_TEST_SENTINEL", "NEXUS_TEST_SENTINEL", "PYTEST_ADDOPTS", "PYTEST_PLUGINS", "PYTHONHOME", "ai_mode", "executive_mode", "BASH_ENV", "ENV", "BASH_FUNC_fixture%%", "OPENROUTER_API_KEY", "ANTHROPIC_BASE_URL", "OLLAMA_HOST", "PRIVATE_TOKEN", "APP_PASSWORD", "AWS_ACCESS_KEY_ID")
    assert not any(key in os.environ for key in poisoned)
    assert tempfile.gettempdir() == os.environ["TMPDIR"]
    shell_python = subprocess.check_output(["bash", "-c", "python3 -c 'import sys; print(sys.executable)'"], text=True).strip()
    assert pathlib.Path(shell_python).parent == pathlib.Path(sys.executable).parent
    fields = ("HOME", "TMPDIR", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_RUNTIME_DIR", "IGOR_DATA_DIR")
    info = {key: os.environ[key] for key in fields}
    info["pytest_tmp"] = str(tmp_path)
    pathlib.Path(info["HOME"], "same-name.json").write_text(json.dumps(info))
'''
        names = ["tests/test_first.py", "tests/test_second.py"]
        for name in names:
            self.write(name, source)
        args = SimpleNamespace(python=sys.executable, bats="bats", ruff="ruff", shellcheck="shellcheck",
                               bats_timeout=0, group_timeout=10, slow_timeout=20)
        ambient = {"IGOR_TEST_SENTINEL": "ambient", "NEXUS_TEST_SENTINEL": "ambient",
                   "PYTEST_ADDOPTS": "--not-a-real-option", "PYTEST_PLUGINS": "not_a_real_plugin",
                   "PYTHONHOME": "/not/a/python/home", "PYTHONPATH": "/unreviewed/plugins",
                   "ai_mode": "executive", "executive_mode": "1", "BASH_ENV": "/unreviewed/startup",
                   "ENV": "/unreviewed/startup", "BASH_FUNC_fixture%%": "() { exit 99; }",
                   "OPENROUTER_API_KEY": "fixture-secret", "ANTHROPIC_BASE_URL": "https://unreviewed.invalid",
                   "OLLAMA_HOST": "https://unreviewed.invalid", "PRIVATE_TOKEN": "fixture-secret",
                   "APP_PASSWORD": "fixture-secret", "AWS_ACCESS_KEY_ID": "fixture-secret"}
        with patch.dict(os.environ, ambient), concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(runner.run_group, {"id": name, "kind": "pytest", "files": [name]},
                                   self.root, self.root, index, args) for index, name in enumerate(names)]
            results = [future.result() for future in futures]
        self.assertEqual([result["status"] for result in results], ["PASS", "PASS"])
        environments = [json.loads((self.root / "work" / f"{index:03d}" / "home/same-name.json").read_text())
                        for index in range(2)]
        for field in environments[0]:
            self.assertNotEqual(environments[0][field], environments[1][field], field)
            for index, environment in enumerate(environments):
                self.assertTrue(Path(environment[field]).is_relative_to(self.root / "work" / f"{index:03d}"))

    def test_sigint_and_sigterm_checkpoint_completed_active_and_pending_evidence(self):
        started = self.root / "slow-started"
        descendant = self.root / "descendant-marker"
        self.write("tests/test_a.py", "def test_complete(): pass\n")
        slow = f'''import pathlib, subprocess, sys, time
def test_slow():
    subprocess.Popen([sys.executable, "-c", "import pathlib,time; time.sleep(1); pathlib.Path({str(descendant)!r}).touch()"])
    pathlib.Path({str(started)!r}).touch()
    time.sleep(30)
'''
        self.write("tests/test_slow.py", slow)
        self.write("tests/test_local_learning.py", "import time\ndef test_private(): time.sleep(30)\n")
        self.write("tests/test_z.py", "def test_pending(): pass\n")
        self.init_git()
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signum):
                evidence = self.root / f"signal-{signum}"
                arguments = ["focused", "--jobs", "2", "--output-dir", str(evidence)]
                for name in ("test_a.py", "test_slow.py", "test_local_learning.py", "test_z.py"):
                    arguments.extend(["--test", f"tests/{name}"])
                code = (f"import sys; sys.path.insert(0, {str(Path(runner.__file__).parent)!r}); "
                        f"import validation_runner as r; from pathlib import Path; r.ROOT=Path({str(self.root)!r}); "
                        f"sys.exit(r.main({arguments!r}))")
                with (self.root / f"signal-{signum}.log").open("w") as log:
                    process = subprocess.Popen([sys.executable, "-c", code], stdout=log, stderr=log,
                                               start_new_session=True)
                    try:
                        deadline = time.monotonic() + 10
                        while time.monotonic() < deadline:
                            try:
                                current = json.loads((evidence / "summary.json").read_text())
                            except (OSError, ValueError):
                                current = {}
                            if (started.exists() and len(current.get("active_groups", [])) == 2
                                    and any(row.get("identity") == "tests/test_a.py::test_complete"
                                            for row in current.get("results", []))):
                                break
                            self.assertIsNone(process.poll(), log.name)
                            time.sleep(.02)
                        else:
                            self.fail("runner did not checkpoint expected active/completed groups")
                        self.assertEqual(current["exit_code"], 1, "running checkpoint must not claim success")
                        for group in current["active_groups"]:
                            self.assertTrue(Path(group["log"]).is_relative_to(evidence))
                            self.assertTrue(group["log"].endswith("-pytest.log"))
                            self.assertTrue(Path(group["report"]).is_relative_to(evidence))
                            self.assertTrue(group["report"].endswith("-pytest.jsonl"))
                        process.send_signal(signum)
                        self.assertEqual(process.wait(timeout=5), 128 + signum)
                    finally:
                        if process.poll() is None:
                            process.send_signal(signal.SIGTERM)
                            process.wait(timeout=5)
                summary = json.loads((evidence / "summary.json").read_text())
                self.assertEqual(summary["run_state"], "interrupted")
                self.assertEqual(summary["exit_code"], 128 + signum)
                self.assertEqual(summary["active_groups"], [])
                self.assertIn("pytest:tests/test_z.py", [row["id"] for row in summary["pending_groups"]])
                self.assertEqual(summary["counts"]["PASS"], 2)  # structure and completed test
                self.assertGreaterEqual(summary["counts"]["ERROR"], 2)
                time.sleep(1.1)
                self.assertFalse(descendant.exists(), "interrupted worker left a live descendant")


if __name__ == "__main__":
    unittest.main()
