#!/usr/bin/env python3
"""Native sudo input stays outside the chat input and event projections."""

import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core" / "ai"))
import tui  # noqa: E402


class Screen:
    def __init__(self, stream: Path, keys: list[int | tuple[str, str]]):
        self.stream = stream
        self.keys = keys
        self.drawn = []
        self.deadline = time.monotonic() + 8

    def keypad(self, _value):
        pass

    def timeout(self, _value):
        pass

    def erase(self):
        self.drawn.clear()

    def getmaxyx(self):
        return (24, 80)

    def addnstr(self, *args):
        self.drawn.append(args[2])

    def hline(self, *_args):
        pass

    def move(self, *_args):
        pass

    def refresh(self):
        pass

    def getch(self):
        if time.monotonic() > self.deadline:
            raise AssertionError("backend interaction timed out")
        if not self.keys:
            time.sleep(0.01)
            return -1
        item = self.keys[0]
        if isinstance(item, tuple):
            if not self.stream.exists() or not any(
                json.loads(line).get("event_type") == item[1]
                for line in self.stream.read_text().splitlines()
            ):
                time.sleep(0.01)
                return -1
            self.keys.pop(0)
            return -1
        return self.keys.pop(0)


BACKEND = '''import json, os, sys
from pathlib import Path
stream = Path(os.environ["IGOR_AI_EVENT_STREAM"])
commands = Path(sys.argv[1])
sequence = 0
def event(kind, **fields):
    global sequence
    sequence += 1
    with stream.open("a") as output:
        output.write(json.dumps({"event_type": kind, "sequence": sequence,
                                 "operation_id": "exact-action", **fields}) + "\\n")
event("session_started", status="ready")
event("model_status", status="input_ready")
action = sys.stdin.readline().strip()
with commands.open("a") as output:
    output.write(action + "\\n")
event("approval_waiting", classification="CHANGE", display="sudo true")
approval = sys.stdin.readline().strip()
with commands.open("a") as output:
    output.write(approval + "\\n")
event("action_started", classification="CHANGE", display="sudo true")
event("privilege_waiting", classification="CHANGE",
      display="Administrator authentication required")
password = sys.stdin.readline().strip()
event("privilege_result", classification="CHANGE", status="authenticated",
      display="Administrator authentication completed")
event("action_result", classification="CHANGE", status="tool_succeeded",
      display="done")
sys.exit(0 if action == "run" and approval == "yes" and password == "secret" else 3)
'''


class PrivilegeFrontendTests(unittest.TestCase):
    def test_native_auth_keys_bypass_chat_buffer_and_events(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backend = root / "backend.py"
            backend.write_text(BACKEND, encoding="utf-8")
            stream = root / "events.jsonl"
            commands = root / "commands.txt"
            keys: list[int | tuple[str, str]] = (
                [("wait", "model_status")] +
                [ord(char) for char in "run\n"] +
                [("wait", "approval_waiting")] +
                [ord(char) for char in "yes\n"] +
                [("wait", "privilege_waiting")] +
                [ord(char) for char in "secret\n"]
            )
            screen = Screen(stream, keys)
            with patch.object(tui.curses, "ACS_HLINE", "-", create=True), \
                    patch.object(tui.curses, "wrapper", side_effect=lambda callback: callback(screen)):
                result = tui.run_tui((sys.executable, str(backend), str(commands)), stream)
            self.assertEqual(result, 0)
            self.assertEqual(commands.read_text().splitlines(), ["run", "yes"])
            self.assertNotIn("secret", stream.read_text())
            self.assertNotIn("secret", " ".join(screen.drawn))

    def test_authentication_state_matches_exact_operation_and_keeps_draft(self):
        state = tui.EventState()
        draft = tui.InputBuffer()
        draft.insert("unfinished question")
        state.accept({"event_type": "privilege_waiting", "sequence": 1,
                      "operation_id": "approved-one", "display": "Password needed"})
        self.assertIsNotNone(state.privilege_waiting)
        state.accept({"event_type": "privilege_result", "sequence": 2,
                      "operation_id": "different", "status": "authenticated"})
        self.assertIsNotNone(state.privilege_waiting)
        state.accept({"event_type": "privilege_result", "sequence": 3,
                      "operation_id": "approved-one", "status": "authenticated"})
        self.assertIsNone(state.privilege_waiting)
        self.assertEqual(draft.text(), "unfinished question")

    def test_pending_action_shows_admin_requirement_from_event_metadata(self):
        state = tui.EventState()
        state.accept({"event_type": "action_proposed", "sequence": 1,
                      "operation_id": "approved-one", "classification": "CHANGE",
                      "requires_admin_auth": True, "display": "sudo true"})
        state.accept({"event_type": "approval_waiting", "sequence": 2,
                      "operation_id": "approved-one", "classification": "CHANGE",
                      "requires_admin_auth": True, "display": "sudo true"})
        rendered = tui.render_activity(state, 80)
        self.assertTrue(any("administrator privileges" in line for line in rendered))

    def test_only_tty_keys_are_forwarded(self):
        self.assertEqual(tui._privilege_key_bytes(ord("x")), b"x")
        self.assertEqual(tui._privilege_key_bytes(10), b"\n")
        self.assertEqual(tui._privilege_key_bytes(tui.curses.KEY_UP), b"")


if __name__ == "__main__":
    unittest.main()
