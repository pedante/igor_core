"""Focused S6 tests for bounded paths and permission planning."""

import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))

import access


class AccessTests(unittest.TestCase):
    def test_path_identity_and_metadata_do_not_read_contents(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            target = root / "data"
            target.write_text("secret contents are irrelevant", encoding="utf-8")
            with patch.object(access, "_INSPECT_ROOTS", (root,)):
                row = access.inspect_path(str(target).lstrip("/"))
            self.assertEqual(row["path"], str(target))
            self.assertEqual(row["object_id"], "path:" + str(target))
            self.assertEqual(row["kind"], "file")
            self.assertEqual(row["mode"], format(stat.S_IMODE(target.stat().st_mode), "04o"))
            self.assertNotIn("content", row)

    def test_prefix_candidates_descend_only_inside_bounded_roots(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            root = base / "usr" / "local"
            root.mkdir(parents=True)
            (root / "bin").mkdir()
            (root / "share").mkdir()

            with patch.object(access, "_INSPECT_ROOTS", (root,)):
                parent_rows = access.path_candidates(str(base / "usr") + "/l")
                self.assertEqual([row["label"] for row in parent_rows], [str(root) + "/"])
                child_rows = access.path_candidates(str(root) + "/b")
                self.assertEqual([row["label"] for row in child_rows], [str(root / "bin") + "/"])
                with self.assertRaises(access.AccessError):
                    access.path_candidates("/definitely/outside")

    def test_mutable_candidates_do_not_offer_read_only_roots(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            inspect = base / "etc"
            mutable = base / "srv"
            inspect.mkdir()
            mutable.mkdir()
            with (
                patch.object(access, "_INSPECT_ROOTS", (inspect, mutable)),
                patch.object(access, "_MUTATION_ROOTS", (mutable,)),
            ):
                rows = access.path_candidates("/", mutation=True)
            self.assertEqual([row["label"] for row in rows], [str(mutable) + "/"])

    def test_symlink_components_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            real = root / "real"
            real.mkdir()
            link = root / "link"
            link.symlink_to(real, target_is_directory=True)
            with (
                patch.object(access, "_INSPECT_ROOTS", (root,)),
                self.assertRaisesRegex(access.AccessError, "symbolic-link"),
            ):
                access.inspect_path(str(link / "child").lstrip("/"))

    def test_permission_plans_freeze_numeric_nonrecursive_argv(self) -> None:
        path_row = {
            "object_id": "path:/srv/data",
            "path": "/srv/data",
            "kind": "directory",
            "uid": 1000,
            "gid": 1000,
            "owner": "old",
            "group": "old",
            "mode": "0750",
            "size_bytes": 0,
            "device": 12,
            "inode": 34,
        }
        with (
            patch.object(access, "inspect_path", return_value=path_row),
            patch.object(
                access,
                "resolve_user",
                return_value={"object_id": "user:uid:1001", "uid": 1001},
            ),
            patch.object(
                access,
                "resolve_group",
                return_value={"object_id": "group:gid:1002", "gid": 1002},
            ),
        ):
            owner = access.plan_owner({"path": "srv/data", "user": "user:uid:1001"})
            group = access.plan_group({"path": "srv/data", "group": "group:gid:1002"})
            mode = access.plan_mode({"path": "srv/data", "mode": "0755"})

        self.assertEqual(
            owner["commands"],
            [["sudo", "-n", "--", "chown", "--", "1001", "/srv/data"]],
        )
        self.assertEqual(
            group["commands"],
            [["sudo", "-n", "--", "chgrp", "--", "1002", "/srv/data"]],
        )
        self.assertEqual(
            mode["commands"],
            [["sudo", "-n", "--", "chmod", "--", "0755", "/srv/data"]],
        )
        for plan in (owner, group, mode):
            self.assertNotIn("-R", " ".join(plan["commands"][0]))

    def test_special_permission_bits_and_outside_mutation_roots_are_rejected(self) -> None:
        path_row = {
            "object_id": "path:/srv/data",
            "path": "/srv/data",
            "device": 1,
            "inode": 2,
        }
        with (
            patch.object(access, "inspect_path", return_value=path_row),
            self.assertRaisesRegex(access.AccessError, "0000..0777"),
        ):
            access.plan_mode({"path": "srv/data", "mode": "4755"})

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            target = root / "data"
            target.mkdir()
            with (
                patch.object(access, "_MUTATION_ROOTS", (root / "allowed",)),
                self.assertRaisesRegex(access.AccessError, "outside reviewed"),
            ):
                access.inspect_path(str(target).lstrip("/"), mutation=True)


if __name__ == "__main__":
    unittest.main()
