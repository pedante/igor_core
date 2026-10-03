"""Baseline schema and comparison behavior using tiny local fixtures."""

import json
import tempfile
import unittest
from pathlib import Path

from validation_results import BaselineError, compare_results, load_baseline

COMMIT = "525cc76" + "0" * 33


class ValidationResultsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tests").mkdir()
        (self.root / "tests/test_widget.py").write_text(
            "class TestWidget:\n    def test_flaky(self): pass\ndef test_plain(): pass\n")
        (self.root / "tests/widget.bats").write_text('@test "fixture failure" { false; }\n')

    def manifest(self, entries=(), **overrides):
        data = {"schema_version": 1, "source_commit": COMMIT, "entries": list(entries)}
        data.update(overrides)
        path = self.root / "baseline.json"
        path.write_text(json.dumps(data))
        return load_baseline(path, self.root)

    @staticmethod
    def entry(suite="pytest", identity="tests/test_widget.py::TestWidget::test_flaky", classification="FAIL"):
        return {"suite": suite, "identity": identity, "classification": classification,
                "reason": "reproduced fixture issue"}

    def observe(self, status, suite="pytest", identity="tests/test_widget.py::test_plain", **more):
        return {"suite": suite, "identity": identity, "status": status, **more}

    def compare(self, observations, baseline=(), permitted=None):
        return compare_results(observations, list(baseline), permitted or {})

    def test_clean_pass_with_empty_baseline(self):
        result = self.compare([self.observe("PASS")])
        self.assertEqual(result["counts"]["PASS"], 1)
        self.assertEqual(result["exit_code"], 0)

    def test_accepted_failure_is_visible_and_successful(self):
        entry = self.entry(identity="tests/test_widget.py::TestWidget::test_flaky")
        result = self.compare([self.observe("FAIL", identity=entry["identity"])], [entry])
        self.assertEqual(result["counts"]["FAIL_BASELINE"], 1)
        self.assertEqual(result["exit_code"], 0)

    def test_accepted_timeout_is_visible_and_successful(self):
        entry = self.entry(identity="tests/test_widget.py::test_plain", classification="TIMEOUT")
        result = self.compare([self.observe("TIMEOUT")], [entry])
        self.assertEqual(result["counts"]["TIMEOUT_BASELINE"], 1)
        self.assertEqual(result["exit_code"], 0)

    def test_new_failure_fails(self):
        result = self.compare([self.observe("FAIL")])
        self.assertEqual(result["counts"]["FAIL_NEW"], 1)
        self.assertEqual(result["exit_code"], 1)

    def test_new_timeout_fails(self):
        result = self.compare([self.observe("TIMEOUT")])
        self.assertEqual(result["counts"]["TIMEOUT_NEW"], 1)
        self.assertEqual(result["exit_code"], 1)

    def test_baseline_failure_now_passing_is_fixed(self):
        entry = self.entry(identity="tests/test_widget.py::test_plain")
        result = self.compare([self.observe("PASS")], [entry])
        self.assertEqual(result["counts"]["BASELINE_FIXED"], 1)
        self.assertEqual(result["exit_code"], 0)

    def test_unexercised_baseline_is_not_reported_fixed(self):
        entry = self.entry()
        result = self.compare([self.observe("PASS")], [entry])
        self.assertEqual(result["counts"]["BASELINE_FIXED"], 0)
        self.assertEqual(result["unexercised_baseline"], [entry])

    def test_permitted_environment_skip_requires_exact_reason(self):
        obs = self.observe("SKIP", skip_reason="optional network fixture unavailable")
        permitted = {(obs["suite"], obs["identity"]): {obs["skip_reason"]}}
        result = self.compare([obs], permitted=permitted)
        self.assertEqual(result["counts"]["ENV_SKIP"], 1)
        self.assertEqual(result["exit_code"], 0)
        denied = self.compare([obs])
        self.assertEqual(denied["counts"]["ERROR"], 1)
        self.assertEqual(denied["exit_code"], 1)

    def test_required_tool_unavailable_fails_distinctly(self):
        result = self.compare([self.observe("TOOL_UNAVAILABLE")])
        self.assertEqual(result["counts"]["TOOL_UNAVAILABLE"], 1)
        self.assertEqual(result["exit_code"], 1)

    def test_malformed_baseline_metadata_fails_closed(self):
        with self.assertRaises(BaselineError):
            self.manifest([self.entry()], schema_version=True)
        path = self.root / "baseline.json"
        path.write_text('{"schema_version":1,"schema_version":1,"source_commit":"' + COMMIT + '","entries":[]}')
        with self.assertRaises(BaselineError):
            load_baseline(path, self.root)

    def test_duplicate_identity_rejected(self):
        entry = self.entry()
        with self.assertRaisesRegex(BaselineError, "duplicate"):
            self.manifest([entry, dict(entry, classification="TIMEOUT")])

    def test_unknown_classification_and_schema_rejected(self):
        with self.assertRaises(BaselineError):
            self.manifest([dict(self.entry(), classification="SKIP")])
        with self.assertRaises(BaselineError):
            self.manifest([], schema_version=2)
        with self.assertRaises(BaselineError):
            self.manifest([dict(self.entry(), classification=[])])

    def test_type_mismatch_is_new_and_mixed_outcomes_do_not_claim_fixed(self):
        entry = self.entry(identity="tests/test_widget.py::test_plain", classification="TIMEOUT")
        result = self.compare([self.observe("PASS"), self.observe("FAIL")], [entry])
        self.assertEqual(result["counts"]["BASELINE_FIXED"], 0)
        self.assertEqual(result["counts"]["FAIL_NEW"], 1)
        self.assertEqual(result["exit_code"], 1)

    def test_malformed_subtest_identity_rejected(self):
        with self.assertRaises(BaselineError):
            self.manifest([self.entry(identity="tests/test_widget.py::test_plain::subtest[not-json]")])

    def test_stable_python_bats_and_group_identities_are_validated(self):
        accepted = [self.entry(identity="tests/test_widget.py::TestWidget::test_flaky[param]"),
                    self.entry(suite="bats", identity="tests/widget.bats::fixture failure"),
                    self.entry(suite="group", identity="syntax:tests/widget.bats")]
        self.assertEqual(len(self.manifest(accepted)), 3)
        for invalid in (self.entry(identity="tests/test_widget.py::test_absent"),
                        self.entry(suite="bats", identity="tests/widget.bats::absent"),
                        self.entry(suite="group", identity="canonical:modules:all")):
            with self.assertRaises(BaselineError):
                self.manifest([invalid])


if __name__ == "__main__":
    unittest.main()
