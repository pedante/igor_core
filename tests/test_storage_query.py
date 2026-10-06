"""S4 bounded storage discovery contract tests."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core" / "lib"))

from storage_query import (
    StorageQueryError,
    normalize_lsblk,
    parse_mountinfo,
    storage_object_id,
)


class StorageQueryTests(unittest.TestCase):
    def test_mountinfo_normalizes_usage_and_canonical_ids(self):
        text = (
            "36 29 8:1 / / rw,relatime - ext4 /dev/sda1 rw\n"
            "37 36 8:2 / /srv/data\\040set ro,relatime - xfs /dev/sdb1 rw\n"
            "38 29 0:5 / /proc rw,nosuid - proc proc rw\n"
        )

        def fake_statvfs(path):
            self.assertIn(path, {"/", "/srv/data set"})
            return SimpleNamespace(
                f_frsize=4096,
                f_bsize=4096,
                f_blocks=1000,
                f_bfree=250,
                f_bavail=200,
            )

        rows = parse_mountinfo(text, statvfs=fake_statvfs)

        self.assertEqual([row["target"] for row in rows], ["/", "/srv/data set"])
        self.assertEqual(rows[0]["object_id"], "mount:/")
        self.assertEqual(rows[1]["object_id"], "mount:/srv/data%20set")
        self.assertEqual(rows[0]["total_bytes"], 4096000)
        self.assertEqual(rows[0]["used_bytes"], 3072000)
        self.assertEqual(rows[0]["available_bytes"], 819200)
        self.assertEqual(rows[0]["use_percent"], 75)
        self.assertFalse(rows[0]["read_only"])
        self.assertTrue(rows[1]["read_only"])
        self.assertNotIn("proc", {row["filesystem_type"] for row in rows})

    def test_filesystem_normalization_flattens_children_and_ignores_loop_noise(self):
        payload = {
            "blockdevices": [
                {
                    "path": "/dev/nvme0n1",
                    "type": "disk",
                    "fstype": None,
                    "size": 1000,
                    "children": [
                        {
                            "path": "/dev/nvme0n1p1",
                            "type": "part",
                            "fstype": "ext4",
                            "uuid": "u-1",
                            "label": "root",
                            "size": 900,
                            "mountpoints": ["/"],
                        }
                    ],
                },
                {
                    "path": "/dev/loop0",
                    "type": "loop",
                    "fstype": "squashfs",
                    "uuid": "",
                    "label": "",
                    "size": 100,
                    "mountpoints": ["/snap/x"],
                },
                {
                    "path": "/dev/sdb1",
                    "type": "part",
                    "fstype": "xfs",
                    "uuid": "u-2",
                    "label": "archive",
                    "size": "2048",
                    "mountpoints": [None],
                },
            ]
        }

        rows = normalize_lsblk(payload)

        self.assertEqual([row["device"] for row in rows],
                         ["/dev/nvme0n1p1", "/dev/sdb1"])
        self.assertEqual(rows[0]["object_id"], "filesystem:/dev/nvme0n1p1")
        self.assertTrue(rows[0]["mounted"])
        self.assertEqual(rows[0]["mountpoint"], "/")
        self.assertFalse(rows[1]["mounted"])
        self.assertEqual(rows[1]["size_bytes"], 2048)

    def test_storage_object_identity_rejects_relative_and_unknown_kinds(self):
        with self.assertRaises(StorageQueryError):
            storage_object_id("mount", "srv/data")
        with self.assertRaises(StorageQueryError):
            storage_object_id("disk", "/dev/sda")


if __name__ == "__main__":
    unittest.main()
