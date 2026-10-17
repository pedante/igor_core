"""S7.5 regression proof for compiled Module API registry admission."""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core" / "lib"))

import module_registry


def installed(tmp_path):
    for name in ("system", "docker"):
        package = tmp_path / "modules" / name
        package.mkdir(parents=True)
        (package / "module.conf").write_text(f"name={name}\n")
    return tmp_path


def test_missing_policy_is_inactive_and_read_only(tmp_path):
    assert module_registry.read_policy(tmp_path) == {}
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize("content", [
    "system=enabled\nsystem=disabled\n", "system=enabled\nother=unknown\n",
    "system=$(touch injected)\n", "export system=enabled\n", "../system=enabled\n",
    "system=enabled\x00", "#" * 65537,
])
def test_policy_rejects_invalid_data(tmp_path, content):
    (tmp_path / "config").mkdir()
    (tmp_path / "config/modules.conf").write_text(content)
    with pytest.raises(module_registry.RegistryError):
        module_registry.read_policy(tmp_path)


@pytest.mark.parametrize("kind", ["file_symlink", "directory_symlink", "directory", "fifo"])
def test_policy_rejects_unsafe_paths(tmp_path, kind):
    directory = tmp_path / "config"
    external = tmp_path / "external"
    external.mkdir()
    if kind == "directory_symlink":
        directory.symlink_to(external, target_is_directory=True)
    else:
        directory.mkdir()
        path = directory / "modules.conf"
        if kind == "file_symlink":
            (external / "policy").write_text("system=enabled\n")
            path.symlink_to(external / "policy")
        elif kind == "directory":
            path.mkdir()
        else:
            os.mkfifo(path)
    with pytest.raises(module_registry.RegistryError):
        module_registry.read_policy(tmp_path)


def test_explicit_changes_are_private_atomic_and_idempotent(tmp_path):
    installed(tmp_path)
    (tmp_path / "config").mkdir()
    policy = tmp_path / "config/modules.conf"
    policy.write_text("# retained decisions\nsystem=disabled # deliberate\nunknown=disabled\n")
    module_registry.set_policy(tmp_path, "system", "enabled")
    assert policy.read_text() == "# retained decisions\nsystem=enabled # deliberate\nunknown=disabled\n"
    assert policy.stat().st_mode & 0o777 == 0o600
    before = policy.stat()
    module_registry.set_policy(tmp_path, "system", "enabled")
    assert policy.stat().st_ino == before.st_ino
    assert policy.stat().st_mtime_ns == before.st_mtime_ns
    module_registry.set_policy(tmp_path, "docker", "enabled")
    assert module_registry.read_policy(tmp_path) == {"system": "enabled", "docker": "enabled", "unknown": "disabled"}
    assert list((tmp_path / "config").iterdir()) == [policy]


def test_failed_policy_replacement_preserves_original(tmp_path):
    installed(tmp_path)
    module_registry.set_policy(tmp_path, "system", "disabled")
    policy = tmp_path / "config/modules.conf"
    before = policy.read_bytes()
    with (patch.object(module_registry.os, "replace", side_effect=OSError("fixture interruption")),
          pytest.raises(OSError)):
        module_registry.set_policy(tmp_path, "system", "enabled")
    assert policy.read_bytes() == before
    assert list(policy.parent.iterdir()) == [policy]


def test_policy_writer_rejects_uninstalled_names_and_shared_files(tmp_path):
    installed(tmp_path)
    with pytest.raises(module_registry.RegistryError):
        module_registry.set_policy(tmp_path, "absent", "enabled")
    module_registry.set_policy(tmp_path, "system", "disabled")
    policy = tmp_path / "config/modules.conf"
    os.link(policy, tmp_path / "retained")
    with pytest.raises(module_registry.RegistryError):
        module_registry.set_policy(tmp_path, "system", "enabled")
    assert policy.read_text() == "system=disabled\n"


def test_policy_write_limit_preserves_valid_existing_data(tmp_path):
    installed(tmp_path)
    (tmp_path / "config").mkdir()
    policy = tmp_path / "config/modules.conf"
    before = "#" * 65530 + "\n"
    policy.write_text(before)
    with pytest.raises(module_registry.RegistryError, match="size limit"):
        module_registry.set_policy(tmp_path, "system", "enabled")
    assert policy.read_text() == before
    assert module_registry.read_policy(tmp_path) == {}


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
