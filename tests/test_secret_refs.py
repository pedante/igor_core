"""Value-free Wave E secret-reference boundary tests."""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core/lib"))
from secret_refs import (
    SecretReferenceError,
    SecretReferenceService,
    SecretSource,
)


class SecretReferenceTests(unittest.TestCase):
    def test_authorized_consumer_gets_private_fd_and_audit_has_no_value_or_path(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "secrets"
            root.mkdir()
            secret = root / "fixture.key"
            secret.write_bytes(b"private-value")
            secret.chmod(0o600)
            audit = []
            service = SecretReferenceService(root, audit.append)
            service.register(SecretSource("db.main", "system", "database", "fixture", secret))
            self.assertEqual(service.inspect("db.main", owner="system", purpose="database"),
                             {"reference": "db.main", "owner": "system", "purpose": "database", "configured": True})
            with self.assertRaises(SecretReferenceError):
                service.use("db.main", owner="system", purpose="database", consumer="fixture",
                            operation_id="op-1", authorized=False, consume=lambda stream: stream.read())
            value = service.use("db.main", owner="system", purpose="database", consumer="fixture",
                                operation_id="op-2", authorized=True, consume=lambda stream: stream.read())
            self.assertEqual(value, b"private-value")
            self.assertNotIn("private-value", str(audit))
            self.assertNotIn(str(secret), str(audit))

    def test_symlink_and_loose_permissions_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "secrets"
            root.mkdir()
            secret = root / "fixture.key"
            secret.write_text("value")
            secret.chmod(0o644)
            service = SecretReferenceService(root)
            service.register(SecretSource("db.main", "system", "database", "fixture", secret))
            self.assertFalse(service.inspect("db.main", owner="system", purpose="database")["configured"])
            secret.chmod(0o600)
            secret.unlink()
            secret.symlink_to(Path(temp) / "outside")
            self.assertFalse(service.inspect("db.main", owner="system", purpose="database")["configured"])


if __name__ == "__main__":
    unittest.main()
