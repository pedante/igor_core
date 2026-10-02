#!/usr/bin/env python3
"""Contract projection coverage for the generated operator surface."""

import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core" / "lib"))
from operator_surface import SurfaceError, build_surface, children  # noqa: E402


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
        self.assertNotIn("value", json.dumps(surface))

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

    def test_plan_contribution_projects_as_generated_leaf_with_availability(self):
        payload = self.payload()
        payload["modules"].append({
            "name": "docker", "display_name": "Docker",
            "status": "active", "enabled": True, "module_api": 2,
        })
        payload["contributions"].append({
            "id": "docker.install",
            "kind": "plan",
            "owner": "docker",
            "availability": "active",
            "unavailable_reason": None,
            "descriptor": {
                "description": "Install Docker.",
                "plan_version": 1,
                "steps": [{"capability_id": "system.package.install",
                           "inputs": {"package": "pkg_docker"}}],
            },
        })
        surface = build_surface(payload)
        row = next(item for item in surface["entries"]
                   if item["target_id"] == "docker.install")
        self.assertEqual(row["kind"], "plan")
        self.assertEqual(row["path"], "docker.install")
        docker = children(surface, "docker")
        install = next(item for item in docker if item["name"] == "install")
        self.assertTrue(install["leaf"])
        self.assertEqual(install["kind"], "plan")
        self.assertEqual(install["availability"], "active")

        payload["contributions"][-1]["availability"] = "unavailable"
        payload["contributions"][-1]["unavailable_reason"] = "missing dependency"
        surface = build_surface(payload)
        row = next(item for item in surface["entries"]
                   if item["target_id"] == "docker.install")
        self.assertEqual(row["availability"], "unavailable")
        self.assertEqual(row["unavailable_reason"], "missing dependency")

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

    def test_malformed_payload_fails_closed(self):
        with self.assertRaises(SurfaceError):
            build_surface({"modules": "not-a-list"})


if __name__ == "__main__":
    unittest.main()
