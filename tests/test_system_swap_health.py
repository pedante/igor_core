"""System interpretation over snapshots; no collection or configuration writes."""

import copy
import importlib.util
import json
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "swap_health", ROOT / "modules/system/lib/swap_health.py")
swap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(swap)


def facts(total=10000, used=0):
    return {prop: {"value": value, "availability": "known",
                   "recorded_at": "2026-10-15T10:00:00Z"}
            for prop, value in zip(swap.PROPERTIES, (total, total - used, used))}


@pytest.mark.parametrize("used,status,code", [
    (0, "OK", "swap"), (5999, "OK", "swap"), (6000, "WARN", "swap_high"),
    (8499, "WARN", "swap_high"), (8500, "FAIL", "swap_critical"),
    (10000, "FAIL", "swap_critical"),
])
def test_byte_thresholds_and_shared_runtime_interpretation(used, status, code):
    snapshot = facts(used=used)
    before = copy.deepcopy(snapshot)
    check = swap.evaluate(snapshot)
    row = {prop.replace(".", "_", 1): fact["value"] for prop, fact in snapshot.items()}
    row["swap_use_percent"] = round(used / 100)
    current = swap.runtime_status(row)
    assert check["status"] == current["swap_health_status"] == status
    assert check["finding_code"] == current["swap_finding_code"] == code
    assert current["observation_scope"] == "current_read"
    assert current["observed_at"] != snapshot[swap.PROPERTIES[0]]["recorded_at"]
    assert snapshot == before
    assert {tuple(ref["key"]) for ref in check["used_facts"]} == {
        ("host:local", prop, "observed") for prop in swap.PROPERTIES}
    assert all(ref["recorded_at"] == "2026-10-15T10:00:00Z"
               for ref in check["used_facts"])
    assert check["evidence"] == swap.EVIDENCE


def test_no_swap_is_explicitly_not_applicable():
    result = swap.evaluate(facts(total=0))
    assert (result["status"], result["finding_code"]) == ("SKIP", "swap_not_configured")


@pytest.mark.parametrize("availability,code", [
    ("stale", "swap_stale"), ("unknown", "swap_unavailable"),
    ("not_observed", "swap_unavailable"), ("inactive_owner", "swap_unavailable"),
])
def test_unavailable_and_stale_facts_are_never_healthy(availability, code):
    snapshot = facts()
    snapshot["swap.used_bytes"]["availability"] = availability
    result = swap.evaluate(snapshot)
    assert result["status"] == "UNKNOWN"
    assert result["finding_code"] == code
    assert result["used_facts"][-1]["availability"] == availability


def test_missing_fact_is_unavailable():
    snapshot = facts()
    del snapshot["swap.used_bytes"]
    result = swap.evaluate(snapshot)
    assert (result["status"], result["finding_code"]) == ("UNKNOWN", "swap_unavailable")


@pytest.mark.parametrize("value", [True, -1, 0.0, "0", None, 10001])
def test_malformed_or_inconsistent_counter_is_unknown(value):
    snapshot = facts()
    snapshot["swap.used_bytes"]["value"] = value
    result = swap.evaluate(snapshot)
    assert (result["status"], result["finding_code"]) == ("UNKNOWN", "swap_malformed")


@pytest.mark.parametrize("replacement", [None, [], {"availability": "known"},
                                        {"availability": "known", "value": 0, "recorded_at": []}])
def test_malformed_fact_record_is_unknown(replacement):
    snapshot = facts()
    snapshot["swap.used_bytes"] = replacement
    result = swap.evaluate(snapshot)
    assert (result["status"], result["finding_code"]) == ("UNKNOWN", "swap_malformed")


def test_mixed_observation_times_are_not_a_coherent_snapshot():
    snapshot = facts()
    snapshot["swap.used_bytes"]["recorded_at"] = "2026-10-15T10:00:01Z"
    assert swap.evaluate(snapshot)["finding_code"] == "swap_malformed"


def test_phased_diagnose_shellcheck_findings_are_inherited():
    path = "core/diagnose/phases.sh"
    baseline = subprocess.run(["git", "show", f"5efca3db:{path}"], cwd=ROOT,
                              capture_output=True, text=True, check=True).stdout

    def findings(source):
        result = subprocess.run([
            "shellcheck", "--severity=warning", "--exclude=SC2086,SC1090,SC1091,SC2034",
            "--shell=bash", "--format=json", "-",
        ], input=source, capture_output=True, text=True, check=False)
        assert result.returncode in (0, 1), result.stderr
        return {(row["code"], row["level"], row["message"],
                 source.splitlines()[row["line"] - 1].strip())
                for row in json.loads(result.stdout)}

    assert findings((ROOT / path).read_text()) <= findings(baseline)
