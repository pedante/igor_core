import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, "core/lib")
from capability_runtime import (
    CapabilityDescriptor,
    CapabilityError,
    CapabilityPlan,
    CapabilityRegistry,
    SecretReference,
    validate_inputs,
)


def descriptor(**changes):
    value = {
        "id": "system.service.restart", "owner": "system", "provider": "system",
        "handler": "system__restart", "capability_version": 1,
        "description": "restart", "inputs": {"properties": {"unit": {"type": "string", "validator": "systemd_unit"}}, "required": ["unit"], "additionalProperties": False},
        "safety": {"tier": "CHANGE"}, "privilege": "required", "preconditions": [],
        "verification": {"required": True}, "recovery": {"class": "best_effort"},
        "affects": [{"object": "service", "input": "unit"}],
    }
    value.update(changes)
    return CapabilityDescriptor.from_dict(value)


class CapabilityRuntimeTests(unittest.TestCase):
    def test_registry_resolves_provider_and_reports_ambiguity(self):
        registry = CapabilityRegistry()
        registry.register(descriptor())
        self.assertEqual(registry.resolve("system.service.restart").selected_provider, "system")
        second = descriptor(provider="other", owner="other")
        registry.register(second)
        self.assertEqual(registry.resolve("system.service.restart").status, "ambiguous")
        self.assertEqual(registry.resolve("system.service.restart", "other").status, "available")

    def test_unavailable_and_duplicate_provider_are_deterministic(self):
        registry = CapabilityRegistry()
        inactive = descriptor(active=False, unavailable_reason="owner_disabled")
        registry.register(inactive)
        self.assertEqual(registry.resolve(inactive.id).status, "unavailable")
        self.assertEqual(registry.resolve(inactive.id).reason, "owner_disabled")
        with self.assertRaises(CapabilityError):
            registry.register(descriptor(source="other.json"))

    def test_inputs_are_closed_and_typed(self):
        schema = {"properties": {"enabled": {"type": "boolean"}, "kind": {"type": "enum", "enum": ["a", "b"]}}, "required": ["enabled"], "additionalProperties": False}
        self.assertEqual(validate_inputs(schema, {"enabled": True, "kind": "a"})["enabled"], True)
        for value in ({"enabled": "yes"}, {"enabled": True, "extra": 1}, {"enabled": True, "kind": "c"}):
            with self.assertRaises(CapabilityError):
                validate_inputs(schema, value)
        with self.assertRaises(CapabilityError):
            validate_inputs(schema, {"kind": "a"})

    def test_name_number_and_confined_path_validation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "inside").write_text("ok", encoding="utf-8")
            (root / "link").symlink_to("inside")
            schema = {"properties": {
                "unit": {"type": "string", "validator": "systemd_unit"},
                "count": {"type": "integer", "minimum": 1, "maximum": 5},
                "path": {"type": "path", "root": str(root)},
            }, "required": ["unit", "count", "path"], "additionalProperties": False}
            valid = {"unit": "fixture.service", "count": 2, "path": "inside"}
            self.assertEqual(validate_inputs(schema, valid), valid)
            for bad in (
                {**valid, "unit": "fixture;reboot"},
                {**valid, "count": True},
                {**valid, "count": 6},
                {**valid, "path": "../outside"},
                {**valid, "path": "link"},
            ):
                with self.assertRaises(CapabilityError):
                    validate_inputs(schema, bad)

    def test_secret_reference_never_becomes_a_value(self):
        ref = SecretReference.parse({"reference": "db/password", "namespace": "app", "purpose": "connect"})
        self.assertEqual(ref.as_dict()["reference"], "db/password")
        with self.assertRaises(CapabilityError):
            SecretReference.parse("password value")

    def test_preconditions_remain_authoritative_proposal_metadata(self):
        cap = descriptor(preconditions=[{"kind": "service_exists", "input": "unit"}])
        registry = CapabilityRegistry(); registry.register(cap)
        proposal = registry.prepare(cap.id, {"unit": "demo.service"})
        self.assertEqual(proposal["preconditions"], [{"kind": "service_exists", "input": "unit"}])
        self.assertEqual(proposal["affected_objects"], ["service:systemd:demo.service"])

    def test_irreversible_recovery_is_visible_without_executing(self):
        registry = CapabilityRegistry()
        cap = descriptor(recovery={"class": "irreversible"})
        registry.register(cap)
        proposal = registry.prepare(cap.id, {"unit": "demo.service"})
        self.assertEqual(proposal["recovery"]["class"], "irreversible")
        self.assertEqual(registry.inspect(cap.id)["declarations"][0]["recovery"]["class"], "irreversible")

    def test_plan_resolves_without_execution(self):
        registry = CapabilityRegistry()
        cap = descriptor()
        registry.register(cap)
        plan = CapabilityPlan("restart service", [{"capability_id": cap.id, "inputs": {"unit": "demo.service"}}]).resolve(registry)
        self.assertTrue(plan.digest)
        self.assertEqual(plan.inspect()["steps"][0]["inputs"], {"unit": "demo.service"})

    def test_plan_keeps_objects_and_verifiable_final_check(self):
        registry = CapabilityRegistry()
        registry.register(descriptor())
        check = descriptor(id="system.host.memory.refresh", privilege="none",
                           safety={"tier": "READ"}, inputs={"properties": {}, "required": [],
                                                            "additionalProperties": False},
                           verification={"kind": "observer_fact", "required": True},
                           affects=[{"object": "host", "id": "local"}])
        registry.register(check)
        plan = CapabilityPlan("restart then inspect", [
            {"capability_id": "system.service.restart", "inputs": {"unit": "demo.service"}}],
            objects=["service:systemd:demo.service"],
            final_check={"capability_id": check.id, "inputs": {}}).resolve(registry)
        self.assertEqual(plan.inspect()["objects"], ["service:systemd:demo.service"])
        self.assertEqual(plan.inspect()["final_check"]["capability_id"], check.id)
        with self.assertRaises(CapabilityError):
            CapabilityPlan("invalid", [{"capability_id": check.id, "inputs": {}}],
                           final_check={"capability_id": "system.service.restart",
                                        "inputs": {"unit": "demo.service"}}).resolve(registry)

    def test_inspection_is_read_only(self):
        registry = CapabilityRegistry(); cap = descriptor(); registry.register(cap)
        registry.inspect(cap.id)
        self.assertEqual(registry.list()[0]["id"], cap.id)

    def test_prepare_freezes_authoritative_proposal_without_execution(self):
        registry = CapabilityRegistry(); cap = descriptor(); registry.register(cap)
        proposal = registry.prepare(cap.id, {"unit": "demo.service"})
        self.assertEqual(proposal["provider"], "system")
        self.assertEqual(proposal["affected_objects"], ["service:systemd:demo.service"])
        self.assertTrue(proposal["digest"])
        self.assertNotIn("operation_id", proposal)

    def test_result_rejects_unverified_success_and_secret_fields(self):
        from capability_runtime import _validate_result
        with self.assertRaises(CapabilityError):
            _validate_result({"operation_id": "op-1", "capability_id": "system.x.y", "execution_status": "succeeded", "verification_status": "failed", "outcome": "success"})
        with self.assertRaises(CapabilityError):
            _validate_result({"operation_id": "op-1", "capability_id": "system.x.y", "execution_status": "failed", "verification_status": "not_applicable", "outcome": "failed", "password": "secret"})

    def test_prepare_cli_consumes_loader_rows_and_filters_legacy_rows(self):
        row = {"id": "system.host.memory.refresh", "owner": "system", "provider": "system", "source": "system.json", "availability": "active", "descriptor": {
            "kind": "capability", "id": "system.host.memory.refresh", "handler": "system__memory",
            "capability_version": 1, "description": "memory", "inputs": {"properties": {}, "required": [], "additionalProperties": False},
            "safety": {"tier": "READ"}, "privilege": "none", "preconditions": [], "verification": {},
            "recovery": {"class": "not_applicable"}, "affects": [{"object": "host", "id": "local"}], "timeout_seconds": 30}}
        request = {"op": "prepare", "records": [row, {"id": "legacy.x", "descriptor": {"kind": "legacy_action", "id": "legacy.x"}}], "id": row["id"], "inputs": {}}
        completed = subprocess.run([sys.executable, "core/lib/capability_runtime.py"], input=json.dumps(request), text=True, capture_output=True, check=True)
        proposal = json.loads(completed.stdout)
        self.assertEqual(proposal["owner"], "system")
        self.assertEqual(proposal["inputs"], {})
        self.assertEqual(proposal["recovery"]["class"], "not_applicable")
        self.assertNotIn("legacy.x", completed.stdout)


if __name__ == "__main__":
    unittest.main()
