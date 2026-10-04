#!/usr/bin/env python3
"""Contract projection coverage for the generated operator surface."""

import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core" / "lib"))
from operator_surface import (  # noqa: E402
    SurfaceError,
    build_surface,
    cached_build_surface,
    cached_read_surface,
    children,
)


CAP = {
    "id": "system.host.memory.refresh",
    "owner": "system",
    "provider": "system",
    "availability": "active",
    "unavailable_reason": None,
    "descriptor": {
        "description": "Refresh memory.",
        "inputs": {"properties": {}, "required": [], "additionalProperties": False},
        "safety": {"tier": "READ"},
        "privilege": "none",
        "verification": {"kind": "observer_fact", "required": True},
        "recovery": {"class": "not_applicable"},
    },
}


class OperatorSurfaceTests(unittest.TestCase):
    def payload(self):
        return {
            "modules": [{"name": "system", "display_name": "System",
                         "status": "active", "enabled": True, "module_api": 2}],
            "capabilities": [CAP],
            "contributions": [
                {"id": "host.memory", "kind": "observer", "owner": "system",
                 "availability": "active", "unavailable_reason": None,
                 "descriptor": {"output_type": "host.memory"}},
                {"id": "host.memory.health", "kind": "check", "owner": "system",
                 "availability": "active", "unavailable_reason": None,
                 "descriptor": {"output_type": "health.result"}},
            ],
            "configurations": [{
                "owner": "system",
                "schema": {"fields": [{
                    "id": "system.memory.policy", "type": "enum", "scope": "module",
                    "label": "Memory policy", "help": "Desired memory policy",
                    "behavior": "stored",
                }]},
            }],
        }

    def test_surface_projects_existing_contracts_without_execution_data(self):
        surface = build_surface(self.payload())
        by_path = {row["path"]: row for row in surface["entries"]}
        self.assertEqual(surface["surface_version"], 1)
        self.assertEqual(surface["state"], "ready")
        self.assertEqual(surface["entry_count"], len(surface["entries"]))
        self.assertEqual(surface["sources"]["modules"], {"status": "ok", "count": 1})
        self.assertEqual(by_path["system.host.memory.refresh"]["kind"], "capability")
        self.assertEqual(by_path["system.host.memory.refresh"]["safety"], "READ")
        self.assertEqual(by_path["system.host.memory"]["kind"], "observer")
        self.assertEqual(by_path["system.host.memory.health"]["kind"], "check")
        self.assertEqual(by_path["system.memory.policy"]["kind"], "configuration")
        self.assertRegex(surface["digest"], r"^[0-9a-f]{64}$")
        serialized = json.dumps(surface, sort_keys=True)
        self.assertNotIn('"value":', serialized)
        self.assertNotIn('"desired":', serialized)
        self.assertNotIn('"resolved":', serialized)

    def test_children_make_owner_scoped_namespace_for_non_scoped_ids(self):
        surface = build_surface(self.payload())
        self.assertEqual([row["name"] for row in children(surface)], ["system"])
        system = children(surface, "system")
        self.assertEqual([row["name"] for row in system], ["host", "memory"])
        host = children(surface, "system.host")
        memory = next(row for row in host if row["name"] == "memory")
        self.assertTrue(memory["leaf"])
        self.assertTrue(memory["has_children"])
        self.assertEqual(memory["kind"], "observer")

    def test_module_configuration_contribution_projects_schema_fields(self):
        payload = self.payload()
        payload["contributions"].append({
            "id": "system.runtime",
            "kind": "configuration",
            "owner": "system",
            "availability": "active",
            "unavailable_reason": None,
            "descriptor": {
                "schema": {
                    "schema_version": 1,
                    "owner": "system",
                    "fields": [{
                        "id": "system.runtime.enabled",
                        "type": "boolean",
                        "scope": "module",
                        "label": "Runtime enabled",
                        "behavior": "stored",
                    }],
                }
            },
        })
        surface = build_surface(payload)
        row = next(item for item in surface["entries"]
                   if item["target_id"] == "system.runtime.enabled")
        self.assertEqual(row["kind"], "configuration")
        self.assertEqual(row["path"], "system.runtime.enabled")


    def test_configuration_from_contribution_and_declaration_is_not_duplicated(self):
        payload = self.payload()
        schema = payload["configurations"][0]["schema"]
        payload["contributions"].append({
            "id": "system.memory.preferences",
            "kind": "configuration",
            "owner": "system",
            "availability": "active",
            "unavailable_reason": None,
            "descriptor": {"schema": schema},
        })
        surface = build_surface(payload)
        rows = [row for row in surface["entries"]
                if row["target_id"] == "system.memory.policy"]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["path"], "system.memory.policy")

    def test_duplicate_capability_providers_remain_explicit(self):
        payload = self.payload()
        duplicate = json.loads(json.dumps(CAP))
        duplicate["owner"] = duplicate["provider"] = "alternate"
        payload["modules"].append({"name": "alternate", "display_name": "Alternate",
                                   "status": "active", "enabled": True, "module_api": 2})
        payload["capabilities"].append(duplicate)
        surface = build_surface(payload)
        rows = [row for row in surface["entries"]
                if row["target_id"] == "system.host.memory.refresh"]
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(row["provider_required"] for row in rows))
        self.assertEqual({row["provider"] for row in rows}, {"system", "alternate"})

    def test_empty_surface_is_explicit_and_reports_source_counts(self):
        surface = build_surface({
            "modules": [], "contributions": [], "capabilities": [],
            "configurations": [],
            "sources": {
                "modules": "ok", "contributions": "ok",
                "capabilities": "ok", "configurations": "ok",
            },
        })
        self.assertEqual(surface["state"], "empty")
        self.assertEqual(surface["entry_count"], 0)
        self.assertEqual(surface["sources"]["capabilities"]["count"], 0)

    def test_source_failure_is_not_silently_presented_as_empty(self):
        surface = build_surface({
            "modules": [], "contributions": [], "capabilities": [],
            "configurations": [],
            "sources": {
                "modules": "ok", "contributions": "ok",
                "capabilities": "error", "configurations": "ok",
            },
        })
        self.assertEqual(surface["state"], "error")
        self.assertEqual(surface["sources"]["capabilities"],
                         {"status": "error", "count": 0})

    def test_compiled_cache_reuses_structural_digest_across_sessions(self):
        payload = {**self.payload(), "seed_version": 1,
                   "availability_model": "registration"}
        with tempfile.TemporaryDirectory() as root:
            cache = Path(root) / "cache" / "operator-surface-v1.json"
            first = cached_build_surface(payload, cache)
            first_mtime = cache.stat().st_mtime_ns
            second = cached_build_surface(payload, cache)
            second_mtime = cache.stat().st_mtime_ns

            self.assertEqual(first, second)
            self.assertEqual(first_mtime, second_mtime)
            self.assertEqual(first["availability_model"], "registration")
            self.assertRegex(first["compiled_source_digest"], r"^[0-9a-f]{64}$")
            self.assertEqual(stat.S_IMODE(cache.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(cache.parent.stat().st_mode), 0o700)

    def test_loader_keyed_cache_reads_without_rebuilding_seed(self):
        payload = {**self.payload(), "seed_version": 1,
                   "availability_model": "registration"}
        generation = "a" * 64
        with tempfile.TemporaryDirectory() as root:
            cache = Path(root) / "cache" / "operator-surface-v1.json"
            built = cached_build_surface(payload, cache, generation)
            hit = cached_read_surface(cache, generation)
            miss = cached_read_surface(cache, "b" * 64)

        self.assertEqual(hit, built)
        self.assertIsNone(miss)
        self.assertEqual(built["compiled_source_digest"], generation)

    def test_compiled_cache_rebuilds_when_registration_seed_changes(self):
        payload = {**self.payload(), "seed_version": 1,
                   "availability_model": "registration"}
        changed = json.loads(json.dumps(payload))
        changed["capabilities"].append({
            **json.loads(json.dumps(CAP)),
            "id": "system.host.summary",
            "descriptor": {
                **json.loads(json.dumps(CAP["descriptor"])),
                "description": "Host summary.",
            },
        })
        with tempfile.TemporaryDirectory() as root:
            cache = Path(root) / "cache" / "operator-surface-v1.json"
            first = cached_build_surface(payload, cache)
            second = cached_build_surface(changed, cache)

        self.assertNotEqual(first["compiled_source_digest"],
                            second["compiled_source_digest"])
        self.assertEqual(second["entry_count"], first["entry_count"] + 1)
        self.assertTrue(any(row["path"] == "system.host.summary"
                            for row in second["entries"]))

    def test_corrupt_compiled_cache_is_ignored_and_rebuilt(self):
        payload = {**self.payload(), "seed_version": 1,
                   "availability_model": "registration"}
        with tempfile.TemporaryDirectory() as root:
            cache = Path(root) / "cache" / "operator-surface-v1.json"
            first = cached_build_surface(payload, cache)
            cache.write_text('{"cache_version":1,"source_digest":"bad"}',
                             encoding="utf-8")
            os.chmod(cache, 0o600)
            second = cached_build_surface(payload, cache)
            self.assertEqual(first, second)
            stored = json.loads(cache.read_text(encoding="utf-8"))
            self.assertEqual(stored["source_digest"],
                             second["compiled_source_digest"])

    def test_malformed_payload_fails_closed(self):
        with self.assertRaises(SurfaceError):
            build_surface({"modules": "not-a-list"})


if __name__ == "__main__":
    unittest.main()
