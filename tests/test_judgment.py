"""Provider-neutral judgment contract and deterministic authority separation."""

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core" / "ai"))
sys.path.insert(0, str(ROOT / "core" / "lib"))

from capability_runtime import CapabilityRegistry
from judgment import (
    CONTRACT,
    MAX_BYTES,
    JudgmentError,
    ProviderFailure,
    ProviderUnavailable,
    judge,
    payload_or_fallback,
    validate_record,
    validate_request,
)
from system_model import SystemModel
from tool_input import tool_fields


def request():
    return {
        "contract": CONTRACT, "version": 1, "kind": "interpretation", "kind_version": 1,
        "input": {"question": "What might explain the memory pressure?"},
        "references": [{"id": "memory-snapshot", "source": "host.memory",
                        "recorded_at": "2026-09-30T12:00:00Z",
                        "scope_id": "scope:fixture", "object_id": "host:local",
                        "locator": "snapshot:memory-1"}],
        "output_schema": {"type": "object", "properties": {
            "topic": {"type": "string", "maxLength": 80}},
            "required": ["topic"], "additionalProperties": False},
    }


def response(**changes):
    return {"status": "valid", "payload": {"topic": "memory"},
            "evidence": ["memory-snapshot"], "reason": None, **changes}


def result(req=None, raw=None):
    return judge(req or request(), lambda _: raw if raw is not None else response(),
                 provider="fixture-provider", model="fixture-model")


class JudgmentTests(unittest.TestCase):
    def test_closed_versioned_request_and_record(self):
        req = request()
        record = result(req)
        self.assertEqual(validate_request(json.dumps(req)), req)
        self.assertEqual(validate_record(json.dumps(record), req), record)
        for changes in ({"version": 2}, {"version": True}, {"kind_version": 0},
                        {"contract": "vendor.judgment"}, {"kind": "Invalid Kind"},
                        {"kind_version": True}, {"tools": []}):
            with self.subTest(changes=changes), self.assertRaises(JudgmentError):
                validate_request({**req, **changes})
        for changes in ({"version": 2}, {"version": True}, {"kind_version": 2},
                        {"approved": True}, {"validation": "invalid"},
                        {"judgment_id": "model-chosen"}, {"status": "error"},
                        {"completed_at": "2000-01-01T00:00:00Z"}):
            with self.subTest(changes=changes), self.assertRaises(JudgmentError):
                validate_record({**record, **changes}, req)

    def test_abstain_and_unknown_are_valid_successful_outcomes(self):
        for status, reason in (("abstain", "insufficient_confidence"),
                               ("abstain", "insufficient_information"),
                               ("unknown", "cannot_decide")):
            with self.subTest(status=status, reason=reason):
                record = result(raw=response(status=status, payload=None, reason=reason))
                self.assertEqual(record["status"], status)
                self.assertEqual(record["validation"], "valid")
                self.assertIsNone(record["payload"])
                self.assertEqual(validate_record(record, request()), record)
                self.assertEqual(record["evidence"], ["memory-snapshot"])

    def test_nonjudgment_failures_remain_distinct_and_drop_exception_text(self):
        for exception, status in ((ProviderFailure("credential=private"), "provider_failure"),
                                  (RuntimeError("raw provider details"), "provider_failure"),
                                  (ProviderUnavailable("missing key"), "unavailable"),
                                  (TimeoutError("deadline expired"), "timeout")):
            adapter = Mock(side_effect=exception)
            record = judge(request(), adapter, provider="any", model="any")
            with self.subTest(status=status):
                self.assertEqual(record["status"], status)
                self.assertEqual(record["validation"], "not_run")
                self.assertEqual(record["evidence"], [])
                self.assertIsNone(record["payload"])
                self.assertEqual(validate_record(record, request()), record)
                self.assertNotIn(str(exception), json.dumps(record))
                adapter.assert_called_once()

    def test_invalid_model_output_is_not_abstention_or_provider_failure(self):
        invalid = ["not JSON", [], {}, response(payload={"extra": True}),
                   response(payload={"topic": 42}), response(status="provider_failure"),
                   response(evidence=["invented"]), response(evidence=["memory-snapshot"] * 2),
                   response(status="abstain", payload=None, reason=None),
                   response(status="unknown", payload=None, reason="insufficient_confidence"),
                   response(status="abstain", payload=None, reason="cannot_decide", confidence=0),
                   response(reason="long or arbitrary failure text"),
                   response(invocation={"provider": "spoofed"}),
                   response(judgment_id="spoofed"), response(tool="run_capability"),
                   response(confidence=True), response(confidence=-0.1),
                   response(confidence=1.1), response(confidence=float("nan")),
                   response(payload={"topic": "x" * 81}),
                   response(payload={"topic": "x" * MAX_BYTES}),
                   '{"status":"unknown","status":"valid"}',
                   '{"status":"valid","payload":{"topic":NaN},"evidence":[],"reason":null}']
        for raw in invalid:
            with self.subTest(raw=str(raw)[:90]):
                record = result(raw=raw)
                self.assertEqual(record["status"], "invalid_output")
                self.assertEqual(record["validation"], "invalid")
                self.assertEqual(record["reason"], "schema_failure")
                self.assertIsNone(record["payload"])
                validate_record(record, request())

    def test_schema_subset_rejects_unbounded_or_executable_contracts_before_call(self):
        schemas = [
            {"type": "object", "properties": {}, "required": [], "additionalProperties": True},
            {"type": "string", "maxLength": 4},
            {"type": "object", "properties": {"x": {"type": "string"}},
             "required": [], "additionalProperties": False},
        ]
        children = [
            {"type": []}, {"type": "array", "items": {"type": "boolean"}},
            {"type": "string", "maxLength": 10, "pattern": ".*"},
            {"type": "number", "minimum": float("inf")},
            {"type": "number", "minimum": 2, "maximum": 1},
            {"type": "integer", "enum": [True]},
            {"type": "string", "maxLength": 10, "enum": ["a", "a"]},
            {"$ref": "external"}, {"type": "string", "maxLength": True},
            {"type": "string", "maxLength": 10, "validator": "execute"},
        ]
        for child in children:
            schema = request()["output_schema"]
            schema["properties"]["topic"] = child
            schemas.append(schema)
        for schema in schemas:
            adapter = Mock()
            with self.subTest(schema=schema), self.assertRaises(JudgmentError):
                judge({**request(), "output_schema": schema}, adapter, provider="x", model="y")
            adapter.assert_not_called()

    def test_nested_payload_schema_handles_ranking_assessment_and_scalars(self):
        req = request()
        req["kind"] = "candidate.ranking"
        req["output_schema"]["properties"] = {
            "ranking": {"type": "array", "maxItems": 2, "items": {
                "type": "object", "properties": {
                    "candidate": {"type": "string", "maxLength": 10, "enum": ["a", "b"]},
                    "score": {"type": "number", "minimum": 0, "maximum": 1},
                    "count": {"type": "integer", "minimum": 0},
                    "likely": {"type": "boolean"}, "missing": {"type": "null"}},
                "required": ["candidate", "score", "count", "likely", "missing"],
                "additionalProperties": False}}}
        req["output_schema"]["required"] = ["ranking"]
        item = {"candidate": "a", "score": 0.4, "count": 1, "likely": True, "missing": None}
        raw = response(payload={"ranking": [item]}, confidence=0.8)
        self.assertEqual(result(req, raw)["status"], "valid")
        for change in ({"candidate": "invented"}, {"score": True}, {"count": 0.5},
                       {"likely": "yes"}, {"missing": "null"}, {"extra": 1}):
            raw["payload"]["ranking"] = [{**item, **change}]
            self.assertEqual(result(req, raw)["status"], "invalid_output")
        raw["payload"]["ranking"] = [item] * 3
        self.assertEqual(result(req, raw)["status"], "invalid_output")

    def test_input_bounds_and_reference_provenance(self):
        req = request()
        for changes in ({"input": {"text": "x" * MAX_BYTES}},
                        {"input": {"values": list(range(600))}},
                        {"input": {"value": float("inf")}},
                        {"references": req["references"] * 33},
                        {"references": [dict(req["references"][0], scope_id="x", object_id=None)]},
                        {"references": [dict(req["references"][0], recorded_at="yesterday")]},
                        {"references": [dict(req["references"][0], fresh=True)]}):
            with self.subTest(changes=str(changes)[:80]), self.assertRaises(JudgmentError):
                validate_request({**req, **changes})
        nested = {}
        for _ in range(10):
            nested = {"x": nested}
        with self.assertRaises(JudgmentError):
            validate_request({**req, "input": nested})
        with self.assertRaises(JudgmentError):
            validate_request(json.dumps(req).replace('"version": 1', '"version": 1, "version": 1'))

    def test_provider_independence_and_provenance_cannot_be_overwritten(self):
        req = request()
        records = []
        for provider, model in (("openai", "remote-a"), ("openrouter", "remote-b"),
                                ("ollama", "local-c"), ("anthropic", "remote-d"),
                                ("future-provider", "unknown-model")):
            def adapter(detached):
                self.assertEqual(detached, req)
                self.assertNotIn("tools", detached)
                self.assertNotIn("provider", detached)
                detached["references"][0]["source"] = "spoofed"
                detached["input"].clear()
                detached["output_schema"]["additionalProperties"] = True
                return json.dumps(response())
            records.append(judge(req, adapter, provider=provider, model=model))
        for record in records:
            self.assertEqual(record["payload"], {"topic": "memory"})
            self.assertEqual(record["input_provenance"]["references"], req["references"])
            validate_record(record, req)
        self.assertEqual(len({r["judgment_id"] for r in records}), len(records))
        self.assertEqual(len({r["invocation"]["id"] for r in records}), len(records))
        self.assertEqual(len({r["input_provenance"]["request_digest"] for r in records}), 1)
        changed = copy.deepcopy(req)
        changed["input"]["question"] = "different"
        with self.assertRaises(JudgmentError):
            validate_record(records[0], changed)

    def test_deterministic_fallback_for_every_nondecision(self):
        req = request()
        fallback = {"topic": "ask_user"}
        records = [result(raw=response(status=status, payload=None, reason="cannot_decide"))
                   for status in ("abstain", "unknown")]
        records.append(result(raw="broken"))
        for exception in (ProviderFailure(), ProviderUnavailable(), TimeoutError()):
            records.append(judge(req, Mock(side_effect=exception), provider="x", model="y"))
        records.extend([{}, {**result(), "version": 999}, {**result(), "approved": True}])
        for record in records:
            with self.subTest(status=record.get("status")):
                chosen = payload_or_fallback(record, req, fallback)
                self.assertEqual(chosen, fallback)
                chosen["topic"] = "detached"
                self.assertEqual(fallback["topic"], "ask_user")
        self.assertEqual(payload_or_fallback(result(), req, fallback), {"topic": "memory"})
        with self.assertRaises(JudgmentError):
            payload_or_fallback(result(), req, {"bad_default": True})

    def test_near_limit_output_and_provenance_record_round_trip(self):
        req = request()
        req["references"] = [{"id": f"ref-{i}", "source": "source",
                              "recorded_at": "2026-09-30T12:00:00Z", "locator": "x" * 512}
                             for i in range(20)]
        req["output_schema"] = {"type": "object", "properties": {
            f"part{i}": {"type": "string", "maxLength": 4000} for i in range(3)},
            "required": [], "additionalProperties": False}
        payload = {f"part{i}": "x" * 4000 for i in range(3)}
        record = result(req, response(payload=payload, evidence=[]))
        self.assertGreater(len(json.dumps(record)), MAX_BYTES)
        self.assertEqual(validate_record(json.dumps(record), req)["payload"], payload)

    def test_judgment_never_mutates_facts_freshness_or_runtime_authority(self):
        model = SystemModel()
        observed_at = datetime(2026, 9, 30, tzinfo=timezone.utc)
        expired_at = observed_at + timedelta(seconds=61)
        model.observe({"object_kind": "host", "freshness_seconds": 60,
                       "properties": [{"name": "memory.available_bytes", "value_type": "integer"}]},
                      "system", "host.memory", {"status": "ok", "result": {
                          "object_id": "host:local", "facts": [
                              {"property": "memory.available_bytes", "value": 100,
                               "evidence": ["/proc/meminfo"]}], "unavailable": []}}, at=observed_at)
        registry = CapabilityRegistry()
        registry.register({
            "id": "system.service.restart", "owner": "system", "provider": "system",
            "handler": "fixture_restart", "capability_version": 1, "description": "restart",
            "inputs": {"properties": {}, "required": [], "additionalProperties": False},
            "safety": {"tier": "CHANGE"}, "privilege": "required",
            "preconditions": [{"kind": "service_exists", "unit": "fixture.service"}],
            "verification": {"required": True}, "recovery": {"class": "best_effort"}, "affects": [],
        })
        before = registry.prepare("system.service.restart", {})
        stale = model.read("host:local", "memory.available_bytes", "observed", at=expired_at)
        original_facts = copy.deepcopy(model.facts)
        req = request()
        req["input"] = {"facts": [stale], "capability": before}
        req["output_schema"] = {"type": "object", "properties": {
            "recommendation": {"type": "string", "maxLength": 4096},
            "approved": {"type": "boolean"}, "fresh": {"type": "boolean"}},
            "required": ["recommendation"], "additionalProperties": False}
        payload = {"approved": True, "fresh": True, "recommendation": json.dumps({
            "tool": "run_capability", "id": "system.service.restart", "inputs": {},
            "tier": "READ", "privilege": "none", "preconditions": "satisfied",
            "provider": "invented", "verified": True, "recovery": "reversible",
            "module_active": True, "enable_automation": True, "desired_state": "active",
            "responsibility": "maintain", "secret_access": "authorized", "facts": "fresh"})}
        adapter = Mock(return_value=response(payload=payload))
        record = judge(req, adapter, provider="fixture", model="fixture")
        self.assertEqual(record["status"], "valid")
        self.assertTrue(payload_or_fallback(record, req, {"recommendation": "ask_user"})["approved"])
        self.assertEqual(model.facts, original_facts)
        self.assertEqual(model.responsibilities, [])
        self.assertEqual(model.read("host:local", "memory.available_bytes", "observed",
                                    at=expired_at), stale)
        self.assertEqual(stale["availability"], "stale")
        self.assertEqual(registry.prepare("system.service.restart", {}), before)
        self.assertEqual(registry.resolve("invented.operation").status, "unavailable")
        self.assertEqual(registry.resolve("system.service.restart", "invented").status, "unavailable")
        self.assertEqual(before["safety"]["tier"], "CHANGE")
        self.assertEqual(before["privilege"], "required")
        self.assertTrue(before["verification"]["required"])
        adapter.assert_called_once()

    def test_judgment_is_rejected_by_real_dispatcher_before_approval_or_privilege(self):
        record = result()
        for tool in (record, {"tool": "run_capability", "id": "system.service.restart",
                              "inputs": {}, "judgment": record}):
            with self.subTest(tool=tool.get("tool")), self.assertRaises((TypeError, ValueError)):
                tool_fields(json.dumps(tool))
        with tempfile.TemporaryDirectory() as temp:
            # Exercise the existing dispatcher, not a replacement safety policy.
            script = r'''
source "$JUDGMENT_REPO/core/ai/safety.sh"
_ai_audit_dispatch() { :; }
sudo() { printf 'privilege invoked\n' >> "$JUDGMENT_EFFECT"; }
fixture_restart() { printf 'capability invoked\n' >> "$JUDGMENT_EFFECT"; }
_ai_prompt_pending_approval() { printf 'approval invoked\n' >> "$JUDGMENT_EFFECT"; }
ai_mode=assist
ai_execute_tool "$JUDGMENT_RECORD"
'''
            effect = Path(temp) / "effect"
            proc = subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=False,
                                  env={**os.environ, "IGOR_DIR": temp, "JUDGMENT_REPO": str(ROOT),
                                       "JUDGMENT_EFFECT": str(effect), "JUDGMENT_RECORD": json.dumps(record)},
                                  timeout=10)
            self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
            self.assertIn("BLOCKED: Invalid tool input", proc.stdout)
            self.assertFalse(effect.exists())
            self.assertEqual(list(Path(temp).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
