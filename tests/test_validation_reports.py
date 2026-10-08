"""Native-report fixtures verify identities and timeout/skip distinctions."""

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from validation_reports import bats_observations, pytest_observations
from validation_results import compare_results
from validation_runner import run_group


class ValidationReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tests").mkdir()
        self.args = SimpleNamespace(python=sys.executable, bats=shutil.which("bats"), ruff="ruff",
                                    shellcheck="shellcheck", bats_timeout=1, group_timeout=10, slow_timeout=20)

    def test_native_python_reports_node_subtest_and_inner_timeout_identities(self):
        (self.root / "tests/test_fixture.py").write_text('''import subprocess
import unittest
import pytest
def test_pass(): pass
def test_fail(): assert False, "fixture assertion"
def test_inner_timeout(): raise subprocess.TimeoutExpired("fixture", 1)
def test_skip(): pytest.skip("fixture unavailable")
@pytest.mark.parametrize("value", [1,2], ids=["first","second"])
def test_parameter(value): assert value
class TestSubtests(unittest.TestCase):
    def test_choices(self):
        for choice in ("s", "f"):
            with self.subTest(choice=choice):
                raise subprocess.TimeoutExpired("fixture", 1)
''')
        result = run_group({"id": "pytest:fixture", "kind": "pytest", "files": ["tests/test_fixture.py"]},
                           self.root, self.root, 0, self.args)
        statuses = {row["identity"]: row["status"] for row in result["observations"]}
        self.assertEqual(statuses["tests/test_fixture.py::test_pass"], "PASS")
        self.assertEqual(statuses["tests/test_fixture.py::test_fail"], "FAIL")
        self.assertEqual(statuses["tests/test_fixture.py::test_inner_timeout"], "TIMEOUT")
        self.assertEqual(statuses["tests/test_fixture.py::test_skip"], "SKIP")
        self.assertIn("tests/test_fixture.py::test_parameter[first]", statuses)
        for choice in ("s", "f"):
            identity = 'tests/test_fixture.py::TestSubtests::test_choices::subtest[{"msg":null,"params":{"choice":"' + choice + '"}}]'
            self.assertEqual(statuses[identity], "TIMEOUT")
        self.assertEqual(compare_results(result["observations"], [], {})["exit_code"], 1)

    def test_nonliteral_passing_subtest_uses_parent_but_failure_stays_closed(self):
        (self.root / "tests/test_fixture.py").write_text("""import unittest
class TestValues(unittest.TestCase):
    def test_pass(self):
        with self.subTest(schema={"value": float("nan")}):
            self.assertTrue(True)
    def test_fail(self):
        with self.subTest(schema={"value": float("nan")}):
            self.assertTrue(False)
""")
        result = run_group({"id": "pytest:fixture", "kind": "pytest", "files": ["tests/test_fixture.py"]},
                           self.root, self.root, 0, self.args)
        statuses = {row["identity"]: row["status"] for row in result["observations"]}
        self.assertEqual(statuses["tests/test_fixture.py::TestValues::test_pass"], "PASS")
        self.assertEqual(statuses["tests/test_fixture.py::TestValues::test_fail"], "ERROR")
        self.assertEqual(compare_results(result["observations"], [], {})["exit_code"], 1)

    def test_outer_deadline_reports_active_node_not_unexecuted_siblings(self):
        (self.root / "tests/test_fixture.py").write_text("import time\ndef test_slow(): time.sleep(20)\ndef test_after(): pass\n")
        self.args.group_timeout = 2
        result = run_group({"id": "pytest:fixture", "kind": "pytest", "files": ["tests/test_fixture.py"]},
                           self.root, self.root, 0, self.args)
        self.assertEqual(result["observations"][0]["identity"], "tests/test_fixture.py::test_slow")
        self.assertEqual(result["observations"][0]["status"], "TIMEOUT")
        self.assertEqual(len(result["observations"]), 1)

    def test_bats_timing_failure_timeout_skip_names_are_stable(self):
        log = self.root / "bats.log"
        log.write_text("1..4\nok 1 passing in 42ms\nnot ok 2 assertion in 8ms\n"
                       "not ok 3 slow in 180000ms # timeout after 180s\nok 4 optional in 136ms # skip missing prerequisite\n")
        group = {"id": "bats:fixture", "kind": "bats", "files": ["tests/fixture.bats"],
                 "log": str(log), "status": "FAIL", "returncode": 1}
        results = bats_observations(group)
        self.assertEqual([row["identity"] for row in results],
                         ["tests/fixture.bats::passing", "tests/fixture.bats::assertion",
                          "tests/fixture.bats::slow", "tests/fixture.bats::optional"])
        self.assertEqual([row["status"] for row in results], ["PASS", "FAIL", "TIMEOUT", "SKIP"])
        self.assertEqual([row.get("elapsed_seconds") for row in results], [0.042, 0.008, 180.0, 0.136])
        self.assertEqual(compare_results(results, [], {
            ("bats", "tests/fixture.bats::optional"): {"missing prerequisite"},
        })["counts"]["ENV_SKIP"], 1)

    def test_truncated_report_retains_completed_results_and_fails_closed(self):
        report = self.root / "pytest.jsonl"
        identity = "tests/test_fixture.py::test_complete"
        records = [{"event": "collection", "identities": [identity]},
                   {"event": "start", "identity": identity},
                   {"event": "result", "identity": identity, "status": "PASS"},
                   {"event": "finish", "identity": identity}]
        report.write_text("".join(json.dumps(record) + "\n" for record in records) + '{"event":')
        group = {"id": "fixture", "log": "fixture.log", "status": "ERROR", "returncode": None}
        results = pytest_observations(group, report, require_collection=True)
        self.assertEqual(results[0]["identity"], identity)
        self.assertEqual(results[0]["status"], "PASS")
        self.assertIn("Invalid pytest report line", results[1]["detail"])
        self.assertEqual(compare_results(results, [], {})["exit_code"], 1)

    def test_collection_manifest_catches_missing_nodes_and_missing_results(self):
        report = self.root / "pytest.jsonl"
        first, missing = "tests/test_fixture.py::test_first", "tests/test_fixture.py::test_missing"
        group = {"id": "fixture", "log": "fixture.log", "status": "PASS", "returncode": 0}
        records = [{"event": "collection", "identities": [first, missing]},
                   {"event": "start", "identity": first},
                   {"event": "result", "identity": first, "status": "PASS"},
                   {"event": "finish", "identity": first}]
        for finish_missing in (False, True):
            current = records + ([{"event": "finish", "identity": missing}] if finish_missing else [])
            report.write_text("".join(json.dumps(record) + "\n" for record in current))
            results = pytest_observations(group, report, require_collection=True)
            self.assertEqual(results[0]["status"], "PASS")
            self.assertTrue(any(row["status"] == "ERROR" for row in results))
            self.assertEqual(compare_results(results, [], {})["exit_code"], 1)

    def test_phase_durations_are_retained_without_changing_identity(self):
        report = self.root / "pytest.jsonl"
        identity = "tests/test_fixture.py::test_first"
        records = [{"event": "collection", "identities": [identity]},
                   {"event": "start", "identity": identity},
                   *[{"event": "duration", "identity": identity, "phase": phase, "elapsed_seconds": duration}
                     for phase, duration in (("setup", .1), ("call", .2), ("teardown", .3))],
                   {"event": "result", "identity": identity, "status": "PASS"},
                   {"event": "finish", "identity": identity}]
        report.write_text("".join(json.dumps(record) + "\n" for record in records))
        group = {"id": "fixture", "log": "fixture.log", "status": "PASS", "returncode": 0}
        results = pytest_observations(group, report, require_collection=True)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["identity"], identity)
        self.assertEqual(results[0]["elapsed_seconds"], .6)
        self.assertEqual(results[0]["phase_seconds"], {"setup": .1, "call": .2, "teardown": .3})

    def test_incomplete_or_duplicate_reports_fail_closed(self):
        log = self.root / "bats.log"
        group = {"id": "bats:fixture", "kind": "bats", "files": ["tests/fixture.bats"],
                 "log": str(log), "status": "PASS", "returncode": 0}
        log.write_text("1..2\nok 1 only\n")
        self.assertEqual(bats_observations(group)[-1]["status"], "ERROR")
        log.write_text("1..2\nok 1 same\nok 2 same\n")
        with self.assertRaises(ValueError):
            bats_observations(group)
        report = self.root / "pytest.jsonl"
        report.write_text(json.dumps({"event": "start", "identity": "tests/test_fixture.py::test_one"}) + "\n")
        self.assertEqual(pytest_observations(group, report)[-1]["status"], "ERROR")


if __name__ == "__main__":
    unittest.main()
