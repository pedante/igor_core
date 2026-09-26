#!/usr/bin/env python3
"""Exercise approved native tty authentication with the real dispatcher."""

import json
import os
import pty
import select
import signal
import tempfile
import termios
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class PrivilegePtyTests(unittest.TestCase):
    def test_password_authenticates_only_the_approved_command(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            binaries = base / "bin"
            binaries.mkdir()
            marker = base / "exact-marker"
            auth_marker = base / "authenticated"
            argv_log = base / "sudo-argv"
            audit_log = base / "audit"
            stream = runtime / "events.jsonl"
            sudo = binaries / "sudo"
            sudo.write_text('''#!/bin/bash
if [ "$1" = -n ] && [ "$2" = -v ]; then exit 1; fi
if [ "$1" = -v ]; then
    IFS= read -r supplied </dev/tty || exit 1
    [ "$supplied" = "test-password" ] || exit 1
    touch "$AUTH_MARKER"
    exit 0
fi
[ -f "$AUTH_MARKER" ] || exit 1
printf '%s\\n' "$*" >> "$SUDO_ARGV_LOG"
"$@"
''', encoding="utf-8")
            sudo.chmod(0o700)
            backend = base / "backend.sh"
            backend.write_text('''#!/bin/bash
source "$IGOR_DIR/core/ai/events.sh"
source "$IGOR_DIR/core/ai/safety.sh"
source "$IGOR_DIR/core/lib/input_validation.sh"
ai_unscrub_inbound() { printf '%s' "$1"; }
ai_scrub_outbound() { printf '%s' "$1"; }
_ai_validate_tool_call() { printf 'BLOCKED: false\\n'; }
ai_audit_tool() { printf '%s\\n' "$*" >> "$AUDIT_LOG"; }
ai_knowledge_mark_changed() { :; }
ai_execute_tool "$TOOL_JSON"
''', encoding="utf-8")
            env = os.environ.copy()
            env.update({
                "IGOR_DIR": str(ROOT), "IGOR_RUNTIME_DIR": str(runtime),
                "IGOR_AI_EVENT_STREAM": str(stream), "IGOR_AI_EVENT_RENDER": "false",
                "IGOR_QUIET_LOOP": "true", "IGOR_VERBOSE": "false",
                "ai_mode": "assist", "executive_mode": "false",
                "AUTH_MARKER": str(auth_marker), "SUDO_ARGV_LOG": str(argv_log),
                "AUDIT_LOG": str(audit_log),
                "TOOL_JSON": json.dumps({"tool": "host", "cmd": f"sudo touch {marker}"}),
                "PATH": str(binaries) + os.pathsep + os.environ.get("PATH", ""),
            })
            pid, master = pty.fork()
            if pid == 0:
                attributes = termios.tcgetattr(0)
                attributes[3] &= ~termios.ECHO
                termios.tcsetattr(0, termios.TCSANOW, attributes)
                os.execve("/bin/bash", ["bash", str(backend)], env)
            raw = bytearray()
            sent_approval = sent_password = False
            deadline = time.monotonic() + 15
            try:
                while time.monotonic() < deadline:
                    if stream.exists():
                        events = [json.loads(line) for line in stream.read_text().splitlines()]
                        types = [event["event_type"] for event in events]
                        if not sent_approval and "approval_waiting" in types:
                            os.write(master, b"y\n")
                            sent_approval = True
                        if not sent_password and "privilege_waiting" in types:
                            os.write(master, b"test-password\n")
                            sent_password = True
                    ready, _, _ = select.select([master], [], [], 0.05)
                    if ready:
                        try:
                            data = os.read(master, 4096)
                        except OSError:
                            data = b""
                        raw.extend(data)
                    finished, status = os.waitpid(pid, os.WNOHANG)
                    if finished:
                        self.assertEqual(os.waitstatus_to_exitcode(status), 0)
                        break
                else:
                    self.fail("approved command did not finish")
            finally:
                os.close(master)
                try:
                    os.kill(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
                except (ProcessLookupError, ChildProcessError):
                    pass
            self.assertTrue(sent_approval and sent_password)
            self.assertTrue(marker.exists())
            self.assertEqual(argv_log.read_text().strip(), f"touch {marker}")
            self.assertIn("privilege_result", types)
            self.assertNotIn("test-password", stream.read_text())
            self.assertNotIn("test-password", audit_log.read_text())
            self.assertNotIn(b"test-password", raw)


if __name__ == "__main__":
    unittest.main()
