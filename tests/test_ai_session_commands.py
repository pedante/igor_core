import json
import os
import subprocess
import sys
import tempfile
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

    def test_all_interactive_utility_commands_are_local_and_documented(self):
        for line, canonical in (
            ("settings", "settings"),
            ("settings autostart on", "settings"),
            ("settings hybrid off", "settings"),
            ("apikey", "apikey"),
            ("canary dismiss", "canary"),
            ("/diagnose storage", "/diagnose"),
            ("/diag storage", "/diagnose"),
            ("hypo reset", "hypo"),
        ):
            with self.subTest(line=line):
                result = lookup(line)
                self.assertTrue(result["matched"] and result["valid"])
                self.assertEqual(result["command"]["name"], canonical)
        for line in ("settings unknown on", "canary reset", "apikey extra", "stats extra"):
            with self.subTest(invalid=line):
                self.assertFalse(lookup(line)["valid"])
        help_lines = help_text()
        for syntax in ("settings [autostart|hybrid on|off]", "apikey", "canary dismiss",
                       "/diagnose [focus]"):
            self.assertIn(syntax, help_lines)

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

    def test_ipc_trim_preserves_a_complete_native_tool_turn(self):
        history = [
            {"role": "user", "content": "inspect"},
            {"role": "assistant", "content": "", "tool_calls": [
                {"id": "call_1", "type": "function", "function": {"name": "host", "arguments": "{}"}},
            ]},
            {"role": "tool", "tool_call_id": "call_1", "content": "ok"},
        ]
        shell = '''
source "$IGOR_DIR/core/ai/core.sh"
conversation="$TEST_HISTORY"
save_conversation_to_output(){ :; }
_ai_write_conversation(){ :; }
_ai_handle_ipc_command conversation:trim:1
printf '%s\\n' "$conversation"
'''
        with tempfile.TemporaryDirectory() as runtime:
            result = subprocess.run(
                ["bash", "-c", shell], text=True, capture_output=True,
                env={**os.environ, "IGOR_DIR": str(ROOT), "IGOR_RUNTIME_DIR": runtime,
                     "TEST_HISTORY": json.dumps(history)},
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        trimmed = json.loads(result.stdout.splitlines()[-1])
        self.assertEqual(trimmed, history)

    def test_failed_change_does_not_count_as_applied(self):
        shell = '''
source "$IGOR_DIR/core/ai/core.sh"
_ai_tx_batch_changed "$TEST_RESULTS"
'''
        failed = [{"classification": "CHANGE", "approval_status": "approved",
                   "execution_status": "tool_failed"}]
        result = subprocess.run(["bash", "-c", shell], text=True, capture_output=True,
                                env={**os.environ, "IGOR_DIR": str(ROOT),
                                     "TEST_RESULTS": json.dumps(failed)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "false")

    def test_denial_state_preserves_prior_successful_action(self):
        shell = '''
source "$IGOR_DIR/core/ai/core.sh"
_ai_tx_denial_state "$TEST_RESULTS" "$TEST_PRIOR_CHANGE"
'''
        denied = {"classification": "CHANGE", "execution_status": "action_denied"}
        succeeded = {"classification": "CHANGE", "execution_status": "tool_succeeded"}
        verified = {"classification": "READ", "execution_status": "tool_succeeded"}
        for results, prior, expected in (
            ([denied], "false", "action_denied"),
            ([denied], "true", "verification_denied"),
            ([succeeded, denied], "false", "verification_denied"),
            ([succeeded, verified, denied], "false", "action_denied"),
            ([succeeded], "false", ""),
        ):
            with self.subTest(results=results, prior=prior):
                result = subprocess.run(
                    ["bash", "-c", shell], text=True, capture_output=True,
                    env={**os.environ, "IGOR_DIR": str(ROOT),
                         "TEST_RESULTS": json.dumps(results), "TEST_PRIOR_CHANGE": prior},
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

    def test_verification_pending_tracks_successful_reads(self):
        shell = '''
source "$IGOR_DIR/core/ai/core.sh"
_ai_tx_verification_pending "$TEST_RESULTS" "$TEST_PRIOR_PENDING"
'''
        for results, prior, expected in (
            ([{"classification": "CHANGE", "execution_status": "tool_failed"}], "false", "false"),
            ([{"classification": "CHANGE", "execution_status": "tool_succeeded"}], "false", "true"),
            ([{"classification": "READ", "execution_status": "tool_succeeded"}], "true", "false"),
            ([{"classification": "READ", "execution_status": "tool_failed"}], "true", "true"),
        ):
            with self.subTest(results=results, prior=prior):
                result = subprocess.run(
                    ["bash", "-c", shell], text=True, capture_output=True,
                    env={**os.environ, "IGOR_DIR": str(ROOT), "TEST_RESULTS": json.dumps(results),
                         "TEST_PRIOR_PENDING": prior},
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)


if __name__ == "__main__":
    unittest.main()
