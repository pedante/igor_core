"""Step 13 event contract, validation and disposable buffer tests."""

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core/lib"))
from domain_event import (
    BUILTIN,
    EventError,
    append,
    from_result,
    inspect,
    publish,
    validate_envelope,
)


class DomainEventTests(unittest.TestCase):
    def result(self, **changes):
        value = {"operation_id": "op-fixture", "capability_id": "system.host.memory.refresh",
                 "owner": "system", "affected_objects": ["host:local"],
                 "recorded_at": "2026-09-28T10:00:00+00:00",
                 "execution_status": "succeeded", "verification_status": "passed",
                 "outcome": "success", "safety": {"tier": "READ"}}
        value.update(changes)
        return value

    def test_success_stamps_identity_source_and_correlation(self):
        event = from_result(self.result())
        self.assertEqual(event["source"], "core:capability_runtime")
        self.assertEqual(event["owner"], "system")
        self.assertEqual(event["correlation_id"], "op-fixture")
        self.assertEqual(event["evidence"], [{"kind": "capability_result", "ref": "op-fixture"}])
        self.assertEqual(event["payload"], {"execution_status": "succeeded", "verification_status": "passed", "outcome": "success"})

    def test_unverified_change_preserves_independent_statuses(self):
        event = from_result(self.result(capability_id="system.service.restart",
                                        execution_status="succeeded", verification_status="failed",
                                        outcome="unverified_change", safety={"tier": "CHANGE"}))
        self.assertEqual(event["payload"], {"execution_status": "succeeded", "verification_status": "failed", "outcome": "unverified_change"})

    def test_invalid_rejected_before_buffer(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "buffer"
            path.touch(mode=0o600)
            with self.assertRaises(EventError):
                from_result(self.result(outcome="success", verification_status="failed"))
            with self.assertRaises(EventError):
                publish("capability.completed", {"execution_status": "succeeded", "verification_status": "failed", "outcome": "success"},
                        owner="system", source="core:capability_runtime", schema=BUILTIN)
            self.assertEqual(inspect(str(path), {}), [])

    def test_unknown_fields_secrets_and_sizes_rejected(self):
        event = from_result(self.result())
        event["approval_status"] = "approved"
        with self.assertRaises(EventError):
            validate_envelope(event, BUILTIN)
        schema = {"properties": {"detail": {"type": "string"}}, "required": ["detail"], "additionalProperties": False}
        for detail in ("password=hunter2", "x" * 2049):
            with self.assertRaises(EventError):
                publish("system.host.changed", {"detail": detail}, owner="system", source="module:system", schema=schema)
        with self.assertRaises(EventError):
            publish("system.host.changed", {"detail": "safe", "owner": "other"}, owner="system", source="module:system", schema=schema)
        spoof_schema = {"properties": {"owner": {"type": "string"}}, "required": ["owner"], "additionalProperties": False}
        with self.assertRaises(EventError):
            publish("system.host.changed", {"owner": "other"}, owner="system", source="module:system", schema=spoof_schema)
        event.pop("approval_status")
        event["schema_version"] = 2
        with self.assertRaises(EventError):
            validate_envelope(event, BUILTIN)
        with self.assertRaises(EventError):
            publish("system.host.changed", {"detail": "safe"}, owner="system", source="module:system",
                    schema=schema, related_objects=["not-an-object-id"])
        numeric = {"properties": {"value": {"type": "number"}}, "required": ["value"], "additionalProperties": False}
        with self.assertRaises(EventError):
            publish("system.host.changed", {"value": float("inf")}, owner="system", source="module:system", schema=numeric)

    def test_bounded_filters_and_fresh_restart_buffer(self):
        with tempfile.TemporaryDirectory() as root:
            first, second = (str(Path(root) / name) for name in ("first", "second"))
            for path in (first, second):
                Path(path).touch(mode=0o600)
            for i in range(130):
                append(first, from_result(self.result(operation_id=f"op-{i}")))
            self.assertEqual(len(inspect(first, {})), 128)
            self.assertEqual(len(inspect(first, {"object_id": "host:local", "owner": "system"})), 128)
            self.assertEqual(len(inspect(first, {"correlation_id": "op-129"})), 1)
            self.assertEqual(inspect(second, {}), [])
            self.assertEqual(os.stat(first).st_mode & 0o777, 0o600)
            os.chmod(first, 0o400)
            self.assertEqual(len(inspect(first, {})), 128)


if __name__ == "__main__":
    unittest.main()
