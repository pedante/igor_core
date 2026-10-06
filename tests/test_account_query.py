"""Focused S6 tests for bounded local account discovery."""

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))

from account_query import (
    AccountQueryError,
    query_groups,
    query_users,
    resolve_group,
    resolve_user,
)


class AccountQueryTests(unittest.TestCase):
    def source(self, text: str) -> Path:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        path = Path(temp.name) / "accounts"
        path.write_text(text, encoding="utf-8")
        return path

    def test_users_use_uid_stable_object_identity(self) -> None:
        rows = query_users(self.source(
            "root:x:0:0:root:/root:/bin/bash\n"
            "igor:x:1000:1000:Igor:/home/igor:/bin/bash\n"
        ))
        self.assertEqual(rows[0]["object_id"], "user:uid:0")
        self.assertEqual(rows[1], {
            "object_id": "user:uid:1000",
            "name": "igor",
            "uid": 1000,
            "primary_gid": 1000,
            "home": "/home/igor",
            "shell": "/bin/bash",
        })
        self.assertEqual(resolve_user("user:uid:1000", rows)["name"], "igor")

    def test_groups_use_gid_stable_object_identity(self) -> None:
        rows = query_groups(self.source(
            "root:x:0:\n"
            "operators:x:1001:igor,alice\n"
        ))
        self.assertEqual(rows[1], {
            "object_id": "group:gid:1001",
            "name": "operators",
            "gid": 1001,
            "member_count": 2,
            "members": "igor,alice",
        })
        self.assertEqual(resolve_group("group:gid:1001", rows)["name"], "operators")

    def test_duplicate_numeric_identity_is_rejected(self) -> None:
        with self.assertRaisesRegex(AccountQueryError, "duplicate local uid"):
            query_users(self.source(
                "a:x:1000:1000::/home/a:/bin/sh\n"
                "b:x:1000:1001::/home/b:/bin/sh\n"
            ))
        with self.assertRaisesRegex(AccountQueryError, "duplicate local gid"):
            query_groups(self.source("a:x:1000:\nb:x:1000:\n"))

    def test_remote_or_shadow_data_is_not_part_of_the_source_contract(self) -> None:
        rows = query_users(self.source("local:x:1000:1000::/home/local:/bin/sh\n"))
        self.assertEqual([row["name"] for row in rows], ["local"])
        self.assertNotIn("password", rows[0])


if __name__ == "__main__":
    unittest.main()
