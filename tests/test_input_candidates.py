"""Focused S1 tests for semantic input candidates."""

import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(__file__))
sys.path.insert(0, os.path.join(ROOT, "core", "lib"))

from capability_runtime import CapabilityError, validate_inputs
from input_candidates import (
    CandidateError,
    CandidateResolverRegistry,
    resolve_registered_source,
    validate_selector,
)

SELECTOR = {"schema_version": 1, "kind": "resource", "resource_kind": "service"}


class InputCandidateTests(unittest.TestCase):
    def test_selector_shape_is_closed_and_type_bounded(self):
        self.assertEqual(validate_selector(SELECTOR, input_type="string"), SELECTOR)
        with self.assertRaises(CandidateError):
            validate_selector({**SELECTOR, "authority": "execute"}, input_type="string")
        with self.assertRaises(CandidateError):
            validate_selector(SELECTOR, input_type="integer")

    def test_inspection_does_not_call_candidate_sources(self):
        calls = []
        registry = CandidateResolverRegistry()
        registry.register(
            "service", "platform", "systemd.services",
            lambda selector: calls.append(selector),
        )
        inspected = registry.inspect(SELECTOR, input_type="string")
        self.assertEqual(inspected["state"], "available")
        self.assertEqual(
            inspected["sources"],
            [{"kind": "platform", "id": "systemd.services", "priority": 1}],
        )
        self.assertEqual(calls, [])

    def test_fresh_system_model_candidates_are_preferred(self):
        calls = []
        registry = CandidateResolverRegistry()
        registry.register(
            "service", "system_model", "system-model.services",
            lambda selector: {
                "state": "ready",
                "freshness": "fresh",
                "recorded_at": "2026-10-06T10:00:00Z",
                "expires_at": "2026-10-06T10:01:00Z",
                "candidates": [{"value": "cron.service", "object_id": "service:systemd:cron.service"}],
            },
        )
        registry.register(
            "service", "platform", "systemd.services",
            lambda selector: calls.append(selector) or {
                "state": "ready",
                "candidates": [{"value": "ssh.service"}],
            },
        )
        result = registry.resolve(SELECTOR, input_type="string")
        self.assertEqual(result["state"], "ready")
        self.assertEqual(result["source"]["kind"], "system_model")
        self.assertEqual(result["source"]["freshness"], "fresh")
        self.assertEqual(result["candidates"][0]["value"], "cron.service")
        self.assertEqual(calls, [])

    def test_stale_model_source_falls_back_to_platform(self):
        registry = CandidateResolverRegistry()
        registry.register(
            "service", "system_model", "system-model.services",
            lambda selector: {
                "state": "ready",
                "freshness": "stale",
                "recorded_at": "2026-10-06T09:00:00Z",
                "expires_at": "2026-10-06T09:01:00Z",
                "candidates": [{"value": "old.service"}],
            },
        )
        registry.register(
            "service", "platform", "systemd.services",
            lambda selector: {
                "state": "ready",
                "candidates": [{"value": "cron.service", "detail": "active / running"}],
            },
        )
        result = registry.resolve(SELECTOR, input_type="string")
        self.assertEqual(result["source"]["kind"], "platform")
        self.assertEqual(result["source"]["freshness"], "not_applicable")
        self.assertEqual(result["candidates"][0]["value"], "cron.service")

    def test_malformed_source_result_fails_closed_without_fallback(self):
        calls = []
        registry = CandidateResolverRegistry()
        registry.register(
            "service", "system_model", "system-model.services",
            lambda selector: {
                "state": "ready",
                "freshness": "fresh",
                "candidates": [{"value": "cron.service"}],
                "approval": True,
            },
        )
        registry.register(
            "service", "platform", "systemd.services",
            lambda selector: calls.append(selector) or {
                "state": "ready", "candidates": [{"value": "ssh.service"}],
            },
        )
        with self.assertRaises(CandidateError):
            registry.resolve(SELECTOR, input_type="string")
        self.assertEqual(calls, [])

    def test_candidate_values_are_bounded_unique_reference_data(self):
        registry = CandidateResolverRegistry(max_candidates=2)
        registry.register(
            "service", "platform", "systemd.services",
            lambda selector: {
                "state": "ready",
                "candidates": [{"value": "cron.service"}, {"value": "cron.service"}],
            },
        )
        with self.assertRaisesRegex(CandidateError, "unique"):
            registry.resolve(SELECTOR, input_type="string")

    def test_no_registered_source_is_explicitly_unavailable(self):
        result = CandidateResolverRegistry().resolve(SELECTOR, input_type="string")
        self.assertEqual(result["state"], "unavailable")
        self.assertIsNone(result["source"])
        self.assertEqual(result["candidates"], [])


    def test_object_id_selector_rejects_non_object_candidate_values(self):
        selector = {"schema_version": 1, "kind": "resource", "resource_kind": "service"}
        registry = CandidateResolverRegistry()
        registry.register(
            "service", "platform", "systemd.service.objects",
            lambda selected: {"state": "ready", "candidates": [{"value": "cron.service"}]},
        )
        with self.assertRaisesRegex(CandidateError, "object identity"):
            registry.resolve(selector, input_type="object_id")

    def test_registered_platform_source_uses_same_normalized_envelope(self):
        result = resolve_registered_source(
            SELECTOR,
            input_type="string",
            source_kind="platform",
            source_id="systemd.services",
            raw={
                "state": "ready",
                "candidates": [{
                    "value": "cron.service",
                    "label": "cron.service",
                    "detail": "active / running",
                    "object_id": "service:systemd:cron.service",
                }],
            },
        )
        self.assertEqual(result["source"]["id"], "systemd.services")
        self.assertEqual(result["candidates"][0]["value"], "cron.service")

    def test_selector_metadata_never_relaxes_capability_validation(self):
        schema = {
            "properties": {
                "unit": {
                    "type": "string",
                    "validator": "systemd_unit",
                    "selector": SELECTOR,
                }
            },
            "required": ["unit"],
            "additionalProperties": False,
        }
        with self.assertRaises(CapabilityError):
            validate_inputs(schema, {"unit": "bad unit;reboot"})


if __name__ == "__main__":
    unittest.main()
