"""Wave D System Model and observation contract tests."""

from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "core" / "lib"))

from system_model import ModelError, SystemModel

DESCRIPTOR = {"object_kind": "host", "freshness_seconds": 60,
              "properties": [{"name": "memory.available_bytes", "value_type": "integer", "minimum": 0}]}


def envelope(value: object) -> dict:
    return {"status": "ok", "result": {"object_id": "host:local", "facts": [
        {"property": "memory.available_bytes", "value": value,
         "evidence": ["/proc/meminfo:MemAvailable"]}], "unavailable": []}}


class SystemModelTests(unittest.TestCase):
    def setUp(self) -> None:
        self.model = SystemModel()
        self.time = datetime(2026, 9, 27, tzinfo=timezone.utc)

    def test_observed_desired_and_responsibility_are_separate(self) -> None:
        snapshot = {"facts": [{"object_id": "host:local", "property": "memory.available_bytes",
                              "state_class": "desired", "value": 200, "value_type": "integer",
                              "owner": "system", "provenance": {"kind": "user_declaration", "id": "policy"}}],
                    "responsibilities": [{"object_id": "host:local", "property": "memory.available_bytes",
                                          "mode": "watch", "owner": "system",
                                          "provenance": {"kind": "user_declaration", "id": "policy"}}]}
        self.model.upsert_from_source("test:policy", snapshot, at=self.time)
        self.model.observe(DESCRIPTOR, "system", "host.memory", envelope(100), at=self.time)
        self.assertEqual(self.model.read("host:local", "memory.available_bytes", "observed", at=self.time)["value"], 100)
        desired = self.model.read("host:local", "memory.available_bytes", "desired", at=self.time)
        self.assertEqual(desired["value"], 200)
        self.assertEqual(desired["provenance"]["source"], "test:policy")
        self.assertEqual(len(self.model.responsibilities), 1)
        rebuilt = SystemModel()
        self.assertEqual(rebuilt.read("host:local", "memory.available_bytes", "observed")["availability"], "not_observed")
        rebuilt.upsert_from_source("test:policy", snapshot)
        self.assertEqual(rebuilt.read("host:local", "memory.available_bytes", "desired")["value"], 200)
        self.assertEqual(len(rebuilt.responsibilities), 1)

    def test_observed_false_and_desired_true_coexist(self) -> None:
        descriptor = {"object_kind": "host", "freshness_seconds": 60,
                      "properties": [{"name": "service_running", "value_type": "boolean"}]}
        self.model.observe(descriptor, "system", "host.service", {"status": "ok", "result": {
            "object_id": "host:local", "facts": [{"property": "service_running", "value": False,
                                                  "evidence": ["systemctl:is-active"]}], "unavailable": []}}, at=self.time)
        self.model.upsert_from_source("test:policy", {"facts": [{"object_id": "host:local",
            "property": "service_running", "state_class": "desired", "value": True,
            "value_type": "boolean", "owner": "system",
            "provenance": {"kind": "user_declaration", "id": "policy"}}], "responsibilities": []}, at=self.time)
        self.assertIs(self.model.read("host:local", "service_running", "observed", at=self.time)["value"], False)
        self.assertIs(self.model.read("host:local", "service_running", "desired", at=self.time)["value"], True)

    def test_fresh_expired_failed_and_never_observed(self) -> None:
        self.assertEqual(self.model.read("host:local", "memory.available_bytes", "observed")["availability"], "not_observed")
        self.model.observer_failure(DESCRIPTOR, "system", "host.memory", "timeout", at=self.time)
        self.assertEqual(self.model.read("host:local", "memory.available_bytes", "observed")["availability"], "unknown")
        self.model.observe(DESCRIPTOR, "system", "host.memory", envelope(100), at=self.time)
        fresh = self.model.read("host:local", "memory.available_bytes", "observed", at=self.time)
        self.assertEqual((fresh["availability"], fresh["value_type"], fresh["observer"]), ("known", "integer", "host.memory"))
        self.assertEqual(self.model.read("host:local", "memory.available_bytes", "observed", at=self.time + timedelta(seconds=61))["availability"], "stale")
        self.model.observer_failure(DESCRIPTOR, "system", "host.memory", "timeout", at=self.time)
        stale = self.model.read("host:local", "memory.available_bytes", "observed", at=self.time)
        self.assertEqual((stale["availability"], stale["value"]), ("stale", 100))

    def test_invalid_observation_cannot_partially_commit(self) -> None:
        bad = envelope(100)
        bad["result"]["facts"].append({"property": "undeclared", "value": 1, "evidence": []})
        with self.assertRaises(ModelError):
            self.model.observe(DESCRIPTOR, "system", "host.memory", bad)
        self.assertEqual(self.model.facts, {})
        with self.assertRaises(ModelError):
            self.model.observe(DESCRIPTOR, "system", "host.memory", envelope(True))
        self.assertEqual(self.model.facts, {})

    def test_partial_result_and_igor_stamped_provenance(self) -> None:
        descriptor = {"object_kind": "host", "freshness_seconds": 60,
                      "properties": [{"name": "memory.available_bytes", "value_type": "integer", "minimum": 0},
                                     {"name": "memory.total_bytes", "value_type": "integer", "minimum": 0}]}
        result = envelope(100)
        result["result"]["unavailable"] = [{"property": "memory.total_bytes", "reason": "missing"}]
        self.model.observe(descriptor, "system", "host.memory", result, at=self.time)
        known = self.model.read("host:local", "memory.available_bytes", "observed", at=self.time)
        unknown = self.model.read("host:local", "memory.total_bytes", "observed", at=self.time)
        self.assertEqual((known["owner"], known["source"], known["recorded_at"]),
                         ("system", "host.memory", "2026-09-27T00:00:00Z"))
        self.assertEqual(unknown["availability"], "unknown")
        self.assertEqual(unknown["reason"], "missing")

    def test_collection_observer_commits_and_replaces_storage_snapshot_atomically(self) -> None:
        descriptor = {
            "object_kind": "mount",
            "freshness_seconds": 60,
            "properties": [
                {"name": "mount.target", "value_type": "string"},
                {"name": "mount.total_bytes", "value_type": "integer", "minimum": 0},
            ],
        }
        first = {"status": "ok", "result": {"objects": [
            {"object_id": "mount:/", "facts": [
                {"property": "mount.target", "value": "/", "evidence": ["/proc/self/mountinfo"]},
                {"property": "mount.total_bytes", "value": 100, "evidence": ["statvfs:/"]},
            ], "unavailable": []},
            {"object_id": "mount:/srv", "facts": [
                {"property": "mount.target", "value": "/srv", "evidence": ["/proc/self/mountinfo"]},
                {"property": "mount.total_bytes", "value": 200, "evidence": ["statvfs:/srv"]},
            ], "unavailable": []},
        ]}}
        self.model.observe(descriptor, "system", "storage.mounts", first, at=self.time)
        self.assertEqual(
            self.model.read("mount:/srv", "mount.total_bytes", "observed", at=self.time)["value"],
            200,
        )

        second = {"status": "ok", "result": {"objects": [
            {"object_id": "mount:/", "facts": [
                {"property": "mount.target", "value": "/", "evidence": ["/proc/self/mountinfo"]},
                {"property": "mount.total_bytes", "value": 120, "evidence": ["statvfs:/"]},
            ], "unavailable": []},
        ]}}
        self.model.observe(descriptor, "system", "storage.mounts", second, at=self.time)

        self.assertEqual(
            self.model.read("mount:/", "mount.total_bytes", "observed", at=self.time)["value"],
            120,
        )
        self.assertEqual(
            self.model.read("mount:/srv", "mount.total_bytes", "observed", at=self.time)["availability"],
            "not_observed",
        )

    def test_collection_observer_failure_stales_prior_facts_without_phantom_objects(self) -> None:
        descriptor = {
            "object_kind": "filesystem",
            "freshness_seconds": 60,
            "properties": [
                {"name": "filesystem.device", "value_type": "string"},
                {"name": "filesystem.mounted", "value_type": "boolean"},
            ],
        }
        self.model.observer_failure(
            descriptor, "system", "storage.filesystems", "unavailable", at=self.time
        )
        self.assertEqual(self.model.facts, {})
        self.assertEqual(self.model.failures, {})

        envelope = {"status": "ok", "result": {"objects": [{
            "object_id": "filesystem:/dev/sdb1",
            "facts": [
                {"property": "filesystem.device", "value": "/dev/sdb1",
                 "evidence": ["lsblk:/dev/sdb1"]},
                {"property": "filesystem.mounted", "value": False,
                 "evidence": ["lsblk:/dev/sdb1"]},
            ],
            "unavailable": [],
        }]}}
        self.model.observe(
            descriptor, "system", "storage.filesystems", envelope, at=self.time
        )
        self.model.observer_failure(
            descriptor, "system", "storage.filesystems", "timeout", at=self.time
        )
        stale = self.model.read(
            "filesystem:/dev/sdb1", "filesystem.device", "observed", at=self.time
        )
        self.assertEqual((stale["availability"], stale["value"]), ("stale", "/dev/sdb1"))

    def test_collection_observer_rejects_wrong_kind_and_partial_objects_atomically(self) -> None:
        descriptor = {
            "object_kind": "mount",
            "freshness_seconds": 60,
            "properties": [
                {"name": "mount.target", "value_type": "string"},
                {"name": "mount.read_only", "value_type": "boolean"},
            ],
        }
        wrong_kind = {"status": "ok", "result": {"objects": [{
            "object_id": "filesystem:/dev/sda1",
            "facts": [
                {"property": "mount.target", "value": "/", "evidence": []},
                {"property": "mount.read_only", "value": False, "evidence": []},
            ],
            "unavailable": [],
        }]}}
        with self.assertRaises(ModelError):
            self.model.observe(descriptor, "system", "storage.mounts", wrong_kind)
        self.assertEqual(self.model.facts, {})

        incomplete = {"status": "ok", "result": {"objects": [{
            "object_id": "mount:/",
            "facts": [
                {"property": "mount.target", "value": "/", "evidence": []},
            ],
            "unavailable": [],
        }]}}
        with self.assertRaises(ModelError):
            self.model.observe(descriptor, "system", "storage.mounts", incomplete)
        self.assertEqual(self.model.facts, {})

    def test_invalid_source_snapshot_is_atomic(self) -> None:
        snapshot = {"facts": [{"object_id": "host:local", "property": "memory.available_bytes",
                              "state_class": "desired", "value": "wrong", "value_type": "integer",
                              "owner": "system", "provenance": {"kind": "user_declaration"}}],
                    "responsibilities": []}
        with self.assertRaises(ModelError):
            self.model.upsert_from_source("test:policy", snapshot)
        self.assertEqual(self.model.facts, {})

    def test_source_cannot_reassign_an_existing_owner(self) -> None:
        snapshot = {"facts": [{"object_id": "host:local", "property": "service_running",
                              "state_class": "desired", "value": True, "value_type": "boolean",
                              "owner": "system", "provenance": {"kind": "user_declaration"}}],
                    "responsibilities": []}
        self.model.upsert_from_source("test:policy", snapshot)
        reassigned = {"facts": [dict(snapshot["facts"][0], owner="other")], "responsibilities": []}
        with self.assertRaises(ModelError):
            self.model.upsert_from_source("test:policy", reassigned)
        self.assertEqual(self.model.read("host:local", "service_running", "desired")["owner"], "system")

    def test_inference_stays_inferred(self) -> None:
        snapshot = {"facts": [{"object_id": "host:local", "property": "memory.risk",
                              "state_class": "inferred", "value": True, "value_type": "boolean",
                              "owner": "system", "provenance": {"kind": "inference", "rule": "low-memory-v1",
                                                                 "inputs": [["host:local", "memory.available_bytes", "observed"]]}}],
                    "responsibilities": []}
        self.model.upsert_from_source("test:inference", snapshot)
        self.assertEqual(self.model.read("host:local", "memory.risk", "observed")["availability"], "not_observed")
        self.assertEqual(self.model.read("host:local", "memory.risk", "inferred")["value"], True)
        self.assertEqual(self.model.read("host:local", "memory.risk", "inferred")["availability"], "unknown")
        self.model.observe(DESCRIPTOR, "system", "host.memory", envelope(100), at=self.time)
        self.assertEqual(self.model.read("host:local", "memory.risk", "inferred", at=self.time)["availability"], "known")
        self.assertEqual(self.model.read("host:local", "memory.risk", "inferred", at=self.time + timedelta(seconds=61))["availability"], "stale")


if __name__ == "__main__":
    unittest.main()
