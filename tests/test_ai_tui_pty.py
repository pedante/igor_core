#!/usr/bin/env python3
"""Exercise the TUI event/input boundary with a deterministic PTY backend."""

import json
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core" / "ai"))
import tui  # noqa: E402


BACKEND = '''import json, os, sys
from pathlib import Path
stream = Path(os.environ["IGOR_AI_EVENT_STREAM"])
log = Path(sys.argv[1])
mode, sequence = "assist", 0
def event(kind, **fields):
    global sequence
    sequence += 1
    with stream.open("a") as output:
        output.write(json.dumps({"event_type": kind, "sequence": sequence, **fields}) + "\\n")
event("session_started", mode=mode, status="ready")
while True:
    event("model_status", mode=mode, status="input_ready")
    line = sys.stdin.readline()
    if not line:
        break
    line = line.strip()
    with log.open("a") as output:
        output.write(line + "\\n")
    if line.startswith("mode "):
        mode = line.split()[1]
        event("mode_changed", mode=mode, display="Mode: " + mode)
    elif line == "check package":
        event("action_proposed", mode=mode, operation_id="op1",
              classification="READ", display="which package")
        if mode == "guide":
            event("approval_waiting", mode=mode, operation_id="op1",
                  classification="READ", display="which package")
            continue
        event("action_started", mode=mode, operation_id="op1",
              classification="READ", display="running")
        event("action_result", mode=mode, operation_id="op1",
              classification="READ", display="found")
        break
    elif line == "run":
        event("action_started", mode=mode, operation_id="op1",
              classification="READ", display="running")
        event("action_result", mode=mode, operation_id="op1",
              classification="READ", display="found")
        break
'''


class Screen:
    def __init__(self, stream, keys):
        self.stream = stream
        self.keys = list(keys)

    def keypad(self, _value):
        pass

    def timeout(self, _value):
        pass

    def erase(self):
        pass

    def getmaxyx(self):
        return (24, 80)

    def addnstr(self, *_args):
        pass

    def hline(self, *_args):
        pass

    def move(self, *_args):
        pass

    def refresh(self):
        pass

    def getch(self):
        if not self.keys:
            return -1
        item = self.keys[0]
        if isinstance(item, tuple) and item[0] == "ready":
            expected = item[1]
            count = 0
            if self.stream.exists():
                count = sum(
                    1 for line in self.stream.read_text().splitlines()
                    if json.loads(line).get("event_type") == "model_status"
                    and json.loads(line).get("status") == "input_ready"
                )
            if count < expected:
                return -1
            self.keys.pop(0)
            return -1
        return self.keys.pop(0)


class PtyBoundaryTests(unittest.TestCase):
    def test_short_read_interaction_in_each_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backend = root / "backend.py"
            backend.write_text(BACKEND, encoding="utf-8")
            for mode in ("guide", "assist", "executive"):
                with self.subTest(mode=mode):
                    stream = root / f"{mode}.jsonl"
                    log = root / f"{mode}.input"
                    commands = [f"mode {mode}", "check package"]
                    if mode == "guide":
                        commands.append("run")
                    keys = [("ready", 1)]
                    for index, command in enumerate(commands):
                        keys.extend(ord(char) for char in command + "\n")
                        if index + 1 < len(commands) and command != "check package":
                            keys.append(("ready", index + 2))
                    # In guide mode the third ready event means the fixture has
                    # entered its approval read after emitting approval_waiting.
                    if mode == "guide":
                        keys = ([("ready", 1)] +
                                [ord(char) for char in f"mode {mode}\n"] +
                                [("ready", 2)] +
                                [ord(char) for char in "check package\n"] +
                                [("ready", 3)] +
                                [ord(char) for char in "run\n"])
                    with patch.object(tui.curses, "ACS_HLINE", "-", create=True), \
                            patch.object(tui.curses, "wrapper",
                                         side_effect=lambda callback: callback(Screen(stream, keys))):
                        result = tui.run_tui((sys.executable, str(backend), str(log)), stream)
                    events = [json.loads(line) for line in stream.read_text().splitlines()]
                    types = [entry["event_type"] for entry in events]
                    self.assertEqual(result, 0)
                    self.assertEqual(log.read_text().splitlines(), commands)
                    self.assertEqual("approval_waiting" in types, mode == "guide")
                    self.assertEqual(types[-1], "action_result")

    def test_backend_startup_failure_returns_error_and_message(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backend = root / "fail.py"
            backend.write_text('''import json, os, sys
from pathlib import Path
Path(os.environ["IGOR_AI_EVENT_STREAM"]).write_text(json.dumps({
    "event_type": "error", "sequence": 1, "display": "Provider setup required"
}) + "\\n")
sys.exit(2)
''', encoding="utf-8")
            stderr = io.StringIO()
            with patch.object(tui.curses, "ACS_HLINE", "-", create=True), \
                    patch.object(tui.curses, "wrapper",
                                 side_effect=lambda callback: callback(Screen(root / "events.jsonl", []))), \
                    patch.object(sys, "stderr", stderr):
                result = tui.run_tui((sys.executable, str(backend)), root / "events.jsonl")
            self.assertEqual(result, 2)
            self.assertIn("Provider setup required", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
