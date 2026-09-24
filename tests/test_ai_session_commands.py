import json
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "core" / "ai" / "session_commands.py"
sys.path.insert(0, str(MODULE.parent))

from session_commands import help_text, lookup  # noqa: E402


class SessionCommandRegistryTests(unittest.TestCase):
    def test_aliases_resolve_to_one_canonical_handler(self):
        for line, canonical in (("q", "exit"), ("quit", "exit"), ("cont", "continue"),
                                ("hypotheses", "hypo"), ("/stop", "stop")):
            result = lookup(line)
            self.assertTrue(result["matched"], line)
            self.assertTrue(result["valid"], line)
            self.assertEqual(result["command"]["name"], canonical)
            self.assertEqual(result["command"]["handler"], canonical)

    def test_argument_commands_are_local_and_validated(self):
        self.assertEqual(lookup("/cmd inspect boot logs")["command"]["handler"], "cmd")
        self.assertEqual(lookup("/cmd inspect boot logs")["arguments"], ["inspect boot logs"])
        self.assertTrue(lookup("hypo add check journal")["valid"])
        self.assertTrue(lookup("history session_123")["valid"])
        self.assertTrue(lookup("replay session_123")["valid"])
        self.assertFalse(lookup("exec maybe")["valid"])
        self.assertFalse(lookup("/cmd")["valid"])

    def test_unknown_text_is_not_a_builtin(self):
        self.assertFalse(lookup("check warnings in boot logs")["matched"])
        self.assertFalse(lookup("")["matched"])

    def test_help_uses_registry_descriptions(self):
        text = help_text()
        self.assertIn("/cmd <description>", text)
        self.assertIn("exit (quit, q)", text)
        self.assertIn("exec on|off", text)
        self.assertNotIn("stats\n", text)

    def test_cli_json_is_machine_readable(self):
        result = subprocess.run([sys.executable, str(MODULE), "lookup", "q"],
                                check=True, capture_output=True, text=True)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["command"]["name"], "exit")
        commands = subprocess.run([sys.executable, str(MODULE), "commands"],
                                  check=True, capture_output=True, text=True)
        self.assertTrue(any(item["name"] == "refresh" for item in json.loads(commands.stdout)))


if __name__ == "__main__":
    unittest.main()
