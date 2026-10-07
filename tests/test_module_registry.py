"""S7.5 regression proof for compiled Module API registry admission."""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core" / "lib"))

import module_registry


class ModuleRegistryS7Tests(unittest.TestCase):
    @staticmethod
    def _connect_known_row(compiled: list[dict[str, object]]) -> dict[str, object]:
        system = next(row for row in compiled if row.get("name") == "system")
        if system.get("status") != "ok":
            raise AssertionError(system)
        return next(
            row
            for row in system["contributions"]
            if row["key"] == "capability:system.network.wifi.connect_known"
        )

    def test_compiled_registry_admits_exact_d075_wifi_adapter(self):
        row = self._connect_known_row(
            module_registry.compile_registry([ROOT / "modules" / "system"])
        )
        self.assertEqual(row["static_reason"], "")
        record = row["record"]
        self.assertEqual(record["handler"], "system__privileged_marker")
        self.assertEqual(record["safety"], {"tier": "CHANGE"})
        self.assertEqual(record["privilege"], "required")
        self.assertEqual(
            record["verification"],
            {
                "kind": "trusted_query",
                "check_id": "system.network.wifi.profile.active",
                "required": True,
            },
        )

    def test_compiled_registry_rejects_drifted_d075_trusted_adapter(self):
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "system"
            shutil.copytree(ROOT / "modules" / "system", package)
            contract_path = package / "contracts" / "network.json"
            contract = json.loads(contract_path.read_text(encoding="utf-8"))
            capability = next(
                row
                for row in contract["contributions"]
                if row.get("id") == "system.network.wifi.connect_known"
            )
            capability["verification"]["check_id"] = (
                "system.network.wifi.profile.unreviewed"
            )
            contract_path.write_text(
                json.dumps(contract, indent=2) + "\n", encoding="utf-8"
            )

            row = self._connect_known_row(
                module_registry.compile_registry([package])
            )
            self.assertEqual(row["static_reason"], "trusted_adapter_unavailable")


if __name__ == "__main__":
    unittest.main()
