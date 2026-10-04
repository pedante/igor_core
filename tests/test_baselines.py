"""Step 16 explainable operational baseline tests."""

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))

from baselines import (
    BaselineError,
    OperationalBaselines,
    summarize_episodes,
)
from operational_history import OperationalHistory


def proposal(provider="fixture_read"):
    return {
        "capability_id": "system.host.memory.refresh",
        "capability_version": 1,
        "provider": provider,
        "owner": "system",
        "inputs": {},
        "safety": {"tier": "READ"},
        "privilege": "none",
        "precondition_status": "satisfied",
        "verification": {"kind": "fact_refresh", "required": True},
        "recovery": {"class": "not_applicable"},
        "affected_objects": ["host:local"],
    }


def finish_result(row, *, execution="succeeded", outcome="success", verification="passed"):
    return {
        "operation_id": row["operation_id"],
        "capability_id": row["capability"]["id"],
        "capability_version": row["capability"]["version"],
        "provider": row["provider"]["id"],
        "owner": row["provider"]["owner"],
        "safety": {"tier": row["safety_tier"]},
        "privilege": row["privilege"]["requirement"],
        "affected_objects": [ref["object_id"] for ref in row["affected_objects"]],
        "execution_status": execution,
        "precondition_status": "satisfied",
        "outcome": outcome,
        "approval_status": "approved",
        "privilege_status": "not_required",
        "verification_status": verification,
        "verification_evidence": [{"source": "system_model", "observed": "refreshed"}],
    }


def record_terminal(history, *, provider="fixture_read", outcome="success",
                    execution="succeeded", verification="passed"):
    row = history.prepare(
        proposal(provider),
        correlation_id="corr-baseline",
        provenance={"actor": "operator", "interface": "capability_api", "request_id": "baseline-test"},
        approval_requirement="policy_read",
    )
    history.authority(row["operation_id"], "approved", "not_required")
    history.running(row["operation_id"])
    history.provider_complete(row["operation_id"], execution)
    history.finish(
        row["operation_id"],
        finish_result(row, execution=execution, outcome=outcome, verification=verification),
    )
    return row["operation_id"]


def fixture_episode(ident, *, admitted, terminal, running, complete, outcome="success"):
    return {
        "operation_id": ident,
        "capability": {"id": "system.host.memory.refresh", "version": 1},
        "provider": {"id": "fixture_read", "owner": "system"},
        "safety_tier": "READ",
        "execution_status": "succeeded",
        "verification": {"status": "passed"},
        "outcome": outcome,
        "lifecycle": "terminal",
        "timestamps": {"admitted_at": admitted, "terminal_at": terminal},
        "transitions": [
            {"state": "admitted", "at": admitted},
            {"state": "running", "at": running},
            {"state": "provider_complete", "at": complete},
            {"state": "terminal", "at": terminal},
        ],
    }


class OperationalBaselineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_absent_history_is_reported_without_creating_storage(self):
        baselines = OperationalBaselines(self.root)
        self.assertEqual(baselines.status()["availability"], "not_created")
        result = baselines.summarize()
        self.assertEqual(result["availability"], "not_created")
        self.assertEqual(result["baselines"], [])
        self.assertFalse((self.root / "operational_history").exists())

    def test_three_terminal_episodes_form_reference_only_baseline(self):
        history = OperationalHistory(self.root)
        ids = [
            record_terminal(history),
            record_terminal(history),
            record_terminal(history, outcome="provider_failed", execution="failed", verification="failed"),
        ]

        result = OperationalBaselines(self.root).summarize()
        self.assertEqual(result["authority"], "reference_only")
        self.assertEqual(result["source"]["episodes_used"], 3)
        self.assertEqual(len(result["baselines"]), 1)
        baseline = result["baselines"][0]
        self.assertEqual(baseline["availability"], "available")
        self.assertEqual(baseline["sample_count"], 3)
        self.assertEqual(baseline["success_count"], 2)
        self.assertEqual(baseline["success_fraction"], 0.667)
        self.assertEqual(baseline["outcomes"], {"provider_failed": 1, "success": 2})
        self.assertEqual(baseline["verification_statuses"], {"failed": 1, "passed": 2})
        self.assertEqual(set(baseline["evidence"]["operation_ids"]), set(ids))
        self.assertEqual(baseline["provider_elapsed_ms"]["samples"], 3)

    def test_unfinished_attempt_is_not_learned(self):
        history = OperationalHistory(self.root)
        record_terminal(history)
        record_terminal(history)
        history.prepare(
            proposal(),
            correlation_id="corr-active",
            provenance={"actor": "operator", "interface": "capability_api", "request_id": "active-test"},
            approval_requirement="policy_read",
        )

        result = OperationalBaselines(self.root).summarize()
        baseline = result["baselines"][0]
        self.assertEqual(baseline["availability"], "insufficient_history")
        self.assertEqual(baseline["sample_count"], 2)
        self.assertEqual(result["source"]["excluded_unfinished"], 1)

    def test_provider_identity_keeps_baselines_separate(self):
        history = OperationalHistory(self.root)
        record_terminal(history, provider="provider_a")
        record_terminal(history, provider="provider_a")
        record_terminal(history, provider="provider_b")

        result = OperationalBaselines(self.root).summarize()
        self.assertEqual(
            [(item["provider"]["id"], item["sample_count"]) for item in result["baselines"]],
            [("provider_a", 2), ("provider_b", 1)],
        )

    def test_elapsed_metrics_are_explicit_and_deterministic(self):
        episodes = [
            fixture_episode(
                "op-" + "1" * 32,
                admitted="2026-10-04T10:00:00+00:00",
                running="2026-10-04T10:00:01+00:00",
                complete="2026-10-04T10:00:02+00:00",
                terminal="2026-10-04T10:00:03+00:00",
            ),
            fixture_episode(
                "op-" + "2" * 32,
                admitted="2026-10-04T10:01:00+00:00",
                running="2026-10-04T10:01:01+00:00",
                complete="2026-10-04T10:01:03+00:00",
                terminal="2026-10-04T10:01:05+00:00",
            ),
            fixture_episode(
                "op-" + "3" * 32,
                admitted="2026-10-04T10:02:00+00:00",
                running="2026-10-04T10:02:01+00:00",
                complete="2026-10-04T10:02:05+00:00",
                terminal="2026-10-04T10:02:07+00:00",
            ),
        ]
        result = summarize_episodes(
            episodes,
            scope_id="scope:" + "a" * 32,
            limit=100,
        )
        baseline = result["baselines"][0]
        self.assertEqual(
            baseline["episode_elapsed_ms"],
            {"samples": 3, "min_ms": 3000, "median_ms": 5000, "max_ms": 7000},
        )
        self.assertEqual(
            baseline["provider_elapsed_ms"],
            {"samples": 3, "min_ms": 1000, "median_ms": 2000, "max_ms": 4000},
        )

    def test_capability_filter_and_limit_validate(self):
        history = OperationalHistory(self.root)
        record_terminal(history)
        result = OperationalBaselines(self.root).summarize(
            capability_id="system.host.memory.refresh",
            limit=10,
        )
        self.assertEqual(len(result["baselines"]), 1)
        with self.assertRaises(BaselineError):
            OperationalBaselines(self.root).summarize(limit=0)
        with self.assertRaises(BaselineError):
            summarize_episodes(
                [],
                scope_id=history.status()["scope_id"],
                limit=10,
                capability_id="../bad",
            )


if __name__ == "__main__":
    unittest.main()
