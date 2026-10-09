"""Focused synthetic governor acceptance checks; no Igor runtime regressions."""

import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import tomllib
import validation_runner as runner
from validation_governor import BudgetError, Governor

REPOSITORY = Path(__file__).resolve().parents[1]


class GovernorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.write("tests/validation_baseline.json", json.dumps(
            {"schema_version": 1, "source_commit": "a" * 40, "entries": []}))
        self.write("source.py", "pass\n")
        self.write(".gitignore", ".igor-governor/\n")
        for arguments in (["init", "-b", "igor2"], ["config", "user.email", "fixture@example.invalid"],
                          ["config", "user.name", "Fixture"], ["add", "."], ["commit", "-m", "fixture"]):
            subprocess.run(["git", *arguments], cwd=self.root, check=True, capture_output=True)
        self.number = 0
        self.calls = []

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def fixture(self, group, root, output, index, args):
        self.calls.append(group["id"])
        log = output / f"{index:03d}-fixture.log"
        result = runner.execute([sys.executable, "-c", "print('synthetic check')"], root, log, 2)
        return {**group, **result}

    def run_validation(self, *arguments, fixture=None, mode="focused"):
        self.number += 1
        output = self.root / f"evidence{self.number}"
        with patch.object(runner, "ROOT", self.root), patch.object(
            runner, "run_group", side_effect=fixture or self.fixture
        ), patch.dict(os.environ, {"CI": ""}), contextlib.redirect_stdout(io.StringIO()):
            code = runner.main([mode, "--base", "HEAD", "--output-dir", str(output), *arguments])
        return code, json.loads((output / "summary.json").read_text())

    def test_unchanged_reuses_and_source_test_environment_baseline_changes_invalidate(self):
        self.assertEqual(self.run_validation()[0], 0)
        calls = len(self.calls)
        code, summary = self.run_validation()
        self.assertEqual(code, 0)
        self.assertTrue(summary["reused"])
        self.assertEqual(len(self.calls), calls)
        self.assertTrue(self.run_validation()[1]["reused"])
        self.assertEqual(len(self.calls), calls)
        self.write("source.py", "# corrected\npass\n")
        self.assertFalse(self.run_validation()[1]["reused"])
        self.write("tests/test_fixture.py", "def test_fixture(): pass\n")
        self.assertFalse(self.run_validation()[1]["reused"])
        self.assertFalse(self.run_validation("--environment-key", "changed-fixture")[1]["reused"])
        baseline = self.root / "tests/validation_baseline.json"
        baseline.write_text(baseline.read_text() + "\n")
        self.assertFalse(self.run_validation()[1]["reused"])

    def test_security_gates_are_not_reused_and_ci_executes_again(self):
        self.write("tests/test_security.py", "def test_security(): pass\n")

        def failure(group, root, output, index, args):
            result = self.fixture(group, root, output, index, args)
            if group["kind"] == "pytest":
                result.update(status="FAIL", returncode=1, observations=[{
                    "suite": "pytest", "identity": "tests/test_security.py::test_security",
                    "status": "FAIL", "log": result["log"]}])
            return result

        code, first = self.run_validation(fixture=failure)
        self.assertEqual(code, 1)
        self.assertEqual(first["counts"]["FAIL_NEW"], 1)
        calls = len(self.calls)
        code, blocked = self.run_validation(fixture=failure)
        self.assertEqual(code, 1)
        self.assertEqual(blocked["run_state"], "incomplete")
        self.assertEqual(len(self.calls), calls)
        # CI normally has a fresh checkout/ledger. Renew explicitly in this shared fixture.
        with patch.dict(os.environ, {"CI": "true"}), patch.object(runner, "ROOT", self.root), \
                patch.object(runner, "run_group", side_effect=failure), contextlib.redirect_stdout(io.StringIO()):
            code = runner.main(["focused", "--base", "HEAD", "--new-budget", "synthetic CI job",
                                "--output-dir", str(self.root / "evidence-ci")])
        self.assertEqual(code, 1)
        self.assertFalse(json.loads((self.root / "evidence-ci/summary.json").read_text())["reused"])

    def test_missing_or_tampered_evidence_is_unverified_and_one_targeted_rerun_is_bounded(self):
        def failure(group, root, output, index, args):
            return {**self.fixture(group, root, output, index, args), "status": "FAIL", "returncode": 1}

        code, first = self.run_validation(fixture=failure)
        self.assertEqual(code, 1)
        code, reused = self.run_validation(fixture=failure)
        self.assertEqual(code, 1)
        self.assertTrue(reused["reused"])
        self.assertGreater(reused["counts"]["FAIL_NEW"], 0)
        Path(first["groups"][0]["log"]).write_text("tampered")
        code, blocked = self.run_validation()
        self.assertEqual(code, 1)
        self.assertEqual(blocked["run_state"], "incomplete")
        self.assertGreater(blocked["counts"]["ERROR"], 0)
        code, corrected = self.run_validation("--rerun-reason", "recreate missing evidence")
        self.assertEqual(code, 0)
        Path(corrected["groups"][0]["log"]).unlink()
        self.assertEqual(self.run_validation("--rerun-reason", "third attempt")[0], 1)

    def test_command_timeout_kills_detached_descendant_stops_pending_and_persists_exhaustion(self):
        self.write("tests/test_a.py", "def test_a(): pass\n")
        self.write("tests/test_z.py", "def test_z(): pass\n")
        marker = self.root / "descendant"
        self.write(".gitignore", ".igor-governor/\nevidence*/\ndescendant\n")
        script = ("import subprocess,sys,time; "
                  f"subprocess.Popen([sys.executable,'-c',\"import pathlib,time; time.sleep(.8); pathlib.Path({str(marker)!r}).touch()\"],start_new_session=True); "
                  "print('before timeout',flush=True); time.sleep(30)")

        def timeout(group, root, output, index, args):
            if group["kind"] == "structure":
                return self.fixture(group, root, output, index, args)
            self.calls.append(group["id"])
            return {**group, **runner.execute([sys.executable, "-c", script], root,
                                               output / f"{index}-timeout.log", .15)}

        code, summary = self.run_validation(fixture=timeout)
        self.assertEqual(code, 1)
        self.assertEqual(summary["run_state"], "budget_exhausted")
        self.assertEqual(summary["pending_groups"][-1]["id"], "pytest:tests/test_z.py")
        self.assertGreater(summary["counts"]["TIMEOUT_NEW"], 0)
        calls = len(self.calls)
        self.assertEqual(self.run_validation(fixture=timeout)[0], 1)
        self.assertEqual(len(self.calls), calls)
        time.sleep(.9)
        self.assertFalse(marker.exists())
        code, renewed = self.run_validation("--new-budget", "Owner approved synthetic correction")
        self.assertEqual(code, 0)
        self.assertEqual(renewed["budget"]["authorization"], "Owner approved synthetic correction")

    def test_total_deadline_cancels_active_and_keeps_pending_unverified(self):
        plan = [{"id": str(i), "kind": "bash", "files": ["fixture.sh"]} for i in range(3)]
        args = SimpleNamespace(jobs=1, progress_interval=1, fail_fast_preflight=False,
                               cancel_event=threading.Event(), deadline=time.monotonic() + .15)
        final = {}

        def slow(group, root, output, index, args):
            return {**group, **runner.execute([sys.executable, "-c", "import time; time.sleep(30)"],
                                               root, output / "slow.log", 5, cancel_event=args.cancel_event)}

        def checkpoint(state, completed, active, pending):
            final.update(state=state, completed=completed.copy(), pending=pending.copy())

        with patch.object(runner, "run_group", side_effect=slow), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.run_plan(plan, self.root, self.root, args, checkpoint), "budget_exhausted")
        self.assertEqual(final["pending"], {1, 2})
        self.assertNotEqual(final["completed"][0]["status"], "PASS")
        with patch.object(runner.subprocess, "Popen") as spawn:
            result = runner.execute(["must-not-execute"], self.root, self.root / "exhausted.log", 0)
        spawn.assert_not_called()
        self.assertEqual(result["status"], "TIMEOUT")

    def test_budget_lock_crash_reservation_and_broad_once_per_candidate(self):
        directory = self.root / ".igor-governor"
        governor = Governor(directory, 1)
        with self.assertRaises(BudgetError):
            Governor(directory, 100, "concurrent reset")
        governor.begin("key", "candidate", "full", self.root / "evidence1")
        governor.close()  # Simulated killed process: no settlement.
        governor = Governor(directory, 100)
        with self.assertRaisesRegex(BudgetError, "exhausted"):
            governor.begin("other", "other", "focused", self.root / "evidence2")
        governor.close()
        governor = Governor(directory, 1, "Owner approved reset")
        governor.begin("key", "candidate", "full", self.root / "evidence1")
        governor.finish()
        with self.assertRaisesRegex(BudgetError, "Broad"):
            governor.begin("different-plan", "candidate", "full", self.root / "evidence2")
        governor.close()

    def test_command_ceiling_overrides_slow_file_exception(self):
        args = SimpleNamespace(python=sys.executable, ruff="ruff", shellcheck="shellcheck", bats="bats",
                               group_timeout=600, slow_timeout=1200, command_timeout=.1, bats_timeout=0)
        group = {"id": "slow", "kind": "bats", "files": ["tests/test_system_admin_surface.bats"]}

        def execute(command, root, log, seconds, env):
            self.assertEqual(seconds, .1)
            log.write_text("1..1\nok 1 fixture\n")
            return {"status": "PASS", "returncode": 0, "elapsed_seconds": 0, "log": str(log)}

        with patch.object(runner, "execute", side_effect=execute):
            runner.run_group(group, self.root, self.root, 0, args)

    def test_session_supervisor_kills_double_fork_and_records_timeout(self):
        marker = self.root / "escaped-child"
        fake = self.write("fake-codex", f'''#!{sys.executable}
import os, pathlib, time
if os.fork() == 0:
    os.setsid()
    if os.fork() == 0:
        time.sleep(.8)
        pathlib.Path({str(marker)!r}).touch()
    os._exit(0)
print('session evidence', flush=True)
time.sleep(30)
''')
        fake.chmod(0o755)
        output = self.root / "evidence-session"
        result = subprocess.run([sys.executable, str(REPOSITORY / "tools/codex_supervised.py"),
                                 "--seconds", ".2", "--codex", str(fake), "--output-dir", str(output),
                                 "--", "exec", "synthetic"], capture_output=True, timeout=5, check=False)
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertEqual(json.loads((output / "session.json").read_text())["status"], "TIMEOUT")
        self.assertIn("session evidence", (output / "session.log").read_text())
        time.sleep(.9)
        self.assertFalse(marker.exists())

    def test_delegation_disabled_and_hooks_block_supported_paths(self):
        config = tomllib.loads((REPOSITORY / ".codex/config.toml").read_text())
        self.assertFalse(config["features"]["multi_agent"])
        self.assertFalse(config["features"]["multi_agent_v2"]["enabled"])
        self.assertFalse(config["agents"]["enabled"])
        self.assertTrue(config["features"]["hooks"])
        spec = importlib.util.spec_from_file_location("governor_hook", REPOSITORY / ".codex/hooks/development_policy.py")
        hook = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(hook)
        for tool, inputs in [("spawn_agent", {}), ("Bash", {"command": "bash tests/run_all.sh"}),
                             ("exec", {"code": "await tools.spawn_agent({})"}),
                             ("Bash", {"command": "tests/validate.sh focused --new-budget fake"}),
                             ("Bash", {"command": "ruff check ."})]:
            self.assertIsNotNone(hook.denial({"tool_name": tool, "tool_input": inputs}))
        self.assertIsNone(hook.denial({"tool_name": "Bash", "tool_input": {"command": "tests/validate.sh full"}}))


if __name__ == "__main__":
    unittest.main()
