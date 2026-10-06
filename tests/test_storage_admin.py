"""S5 reviewed storage-administration planner tests."""

from __future__ import annotations

import stat
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core" / "lib"))

from storage_admin import (
    StorageAdminError,
    freeze_mount,
    freeze_unmount,
    mount_ready,
    unmount_ready,
    verify_mount,
    verify_unmount,
)


def filesystem(*, mounted=False, fs_type="ext4", label="DATA"):
    return {
        "object_id": "filesystem:/dev/sdb1",
        "device": "/dev/sdb1",
        "filesystem_type": fs_type,
        "uuid": "u-data",
        "label": label,
        "size_bytes": 4096,
        "mounted": mounted,
        "mountpoint": "/mnt/DATA" if mounted else "",
    }


def mount(*, target="/mnt/DATA", source="/dev/sdb1"):
    return {
        "object_id": "mount:" + target,
        "target": target,
        "source": source,
        "filesystem_type": "ext4",
        "total_bytes": 4096,
        "used_bytes": 1024,
        "available_bytes": 2048,
        "use_percent": 25,
        "read_only": False,
    }


def root_dir(mode=0o755):
    return SimpleNamespace(st_mode=stat.S_IFDIR | mode, st_uid=0)


class StorageAdminTests(unittest.TestCase):
    def test_mount_plan_freezes_default_runtime_only_argv(self):
        plan = freeze_mount(
            {"filesystem": "filesystem:/dev/sdb1"},
            filesystems=[filesystem()],
        )

        self.assertEqual(plan["target"], "/mnt/DATA")
        self.assertEqual(plan["persistence"], "runtime_only")
        self.assertEqual(
            plan["commands"],
            [
                ["sudo", "-n", "--", "mkdir", "-p", "--", "/mnt/DATA"],
                ["sudo", "-n", "--", "mount", "--", "/dev/sdb1", "/mnt/DATA"],
            ],
        )

    def test_mount_plan_accepts_bounded_custom_target_but_never_persistence(self):
        plan = freeze_mount(
            {
                "filesystem": "filesystem:/dev/sdb1",
                "target": "srv/archive",
                "persistence": "runtime_only",
            },
            filesystems=[filesystem()],
        )
        self.assertEqual(plan["target"], "/srv/archive")

        for bad in ("etc/archive", "../srv/archive", "/srv/archive"):
            with self.assertRaises(StorageAdminError):
                freeze_mount(
                    {"filesystem": "filesystem:/dev/sdb1", "target": bad},
                    filesystems=[filesystem()],
                )
        with self.assertRaises(StorageAdminError):
            freeze_mount(
                {
                    "filesystem": "filesystem:/dev/sdb1",
                    "persistence": "persistent",
                },
                filesystems=[filesystem()],
            )

    def test_mount_plan_rejects_noncanonical_or_nonmountable_filesystem(self):
        with self.assertRaises(StorageAdminError):
            freeze_mount(
                {"filesystem": "filesystem:/dev/sdb1%2f"},
                filesystems=[filesystem()],
            )
        with self.assertRaises(StorageAdminError):
            freeze_mount(
                {"filesystem": "filesystem:/dev/sdb1"},
                filesystems=[filesystem(fs_type="swap")],
            )

    def test_mount_preflight_requires_unmounted_source_free_target_and_root_controlled_ancestry(self):
        def missing_target(path):
            if path == "/mnt":
                return root_dir()
            raise FileNotFoundError(path)

        ready = mount_ready(
            {"filesystem": "filesystem:/dev/sdb1"},
            filesystems=[filesystem()],
            mounts=[],
            lstat=missing_target,
        )
        self.assertTrue(ready["ready"])

        with self.assertRaises(StorageAdminError):
            mount_ready(
                {"filesystem": "filesystem:/dev/sdb1"},
                filesystems=[filesystem(mounted=True)],
                mounts=[],
                lstat=missing_target,
            )
        with self.assertRaises(StorageAdminError):
            mount_ready(
                {"filesystem": "filesystem:/dev/sdb1"},
                filesystems=[filesystem()],
                mounts=[mount()],
                lstat=missing_target,
            )

        def writable_parent(path):
            if path == "/mnt":
                return root_dir(0o777)
            raise FileNotFoundError(path)

        with self.assertRaises(StorageAdminError):
            mount_ready(
                {"filesystem": "filesystem:/dev/sdb1"},
                filesystems=[filesystem()],
                mounts=[],
                lstat=writable_parent,
            )

    def test_unmount_plan_is_normal_runtime_only_umount_and_rejects_protected_roots(self):
        plan = freeze_unmount(
            {"mount": "mount:/srv/archive", "persistence": "runtime_only"}
        )
        self.assertEqual(
            plan["commands"],
            [["sudo", "-n", "--", "umount", "--", "/srv/archive"]],
        )
        self.assertEqual(plan["persistence"], "runtime_only")

        for protected in ("mount:/", "mount:/home", "mount:/boot"):
            with self.assertRaises(StorageAdminError):
                freeze_unmount({"mount": protected})

    def test_unmount_preflight_requires_present_local_device_mount(self):
        self.assertTrue(
            unmount_ready(
                {"mount": "mount:/mnt/DATA"},
                mounts=[mount()],
            )["ready"]
        )
        for rows in (
            [],
            [mount(source="server:/share")],
        ):
            with self.assertRaises(StorageAdminError):
                unmount_ready({"mount": "mount:/mnt/DATA"}, mounts=rows)

    def test_verification_binds_exact_target_and_source(self):
        evidence = verify_mount(
            {"filesystem": "filesystem:/dev/sdb1"},
            filesystems=[filesystem()],
            mounts=[mount()],
        )
        self.assertEqual(evidence["check_id"], "system.storage.mount.present")
        self.assertEqual(evidence["object_id"], "mount:/mnt/DATA")
        self.assertEqual(evidence["persistence"], "runtime_only")

        with self.assertRaises(StorageAdminError):
            verify_mount(
                {"filesystem": "filesystem:/dev/sdb1"},
                filesystems=[filesystem()],
                mounts=[mount(source="/dev/sdc1")],
            )

        gone = verify_unmount({"mount": "mount:/mnt/DATA"}, mounts=[])
        self.assertEqual(gone["check_id"], "system.storage.mount.absent")
        with self.assertRaises(StorageAdminError):
            verify_unmount({"mount": "mount:/mnt/DATA"}, mounts=[mount()])


if __name__ == "__main__":
    unittest.main()
