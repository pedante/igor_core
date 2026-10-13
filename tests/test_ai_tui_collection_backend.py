"""Actual curses/PTY navigation over controlled System and canonical dispatch."""

import codecs
import fcntl
import json
import os
import platform
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import termios
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Terminal:
    """Track curses' incremental ANSI writes, rather than expecting full frames."""
    def __init__(self):
        self.lines = [[" "] * 110 for _ in range(24)]
        self.row = self.col = 0
        self.partial = ""
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")

    def feed(self, data):
        text = self.partial + self.decoder.decode(data)
        self.partial = ""
        i = 0
        while i < len(text):
            char = text[i]
            if char == "\x1b":
                if i + 1 == len(text):
                    self.partial = text[i:]
                    break
                if text[i + 1] == "[":
                    match = re.match(r"\x1b\[([0-?]*)([ -/]*)([@-~])", text[i:])
                    if not match:
                        self.partial = text[i:]
                        break
                    raw, _, command = match.groups()
                    args = [int(v or 0) for v in raw.split(";")] if not raw.startswith("?") else [0]
                    n = args[0] or 1
                    if command in {"H", "f"}:
                        self.row, self.col = n - 1, (args[1] or 1) - 1 if len(args) > 1 else 0
                    elif command == "d": self.row = n - 1
                    elif command == "G": self.col = n - 1
                    elif command == "A": self.row -= n
                    elif command == "B": self.row += n
                    elif command == "C": self.col += n
                    elif command == "D": self.col -= n
                    elif command == "J":
                        if args[0] == 2:
                            self.lines = [[" "] * 110 for _ in range(24)]
                        else:
                            self.lines[self.row][self.col:] = [" "] * (110 - self.col)
                            for row in range(self.row + 1, 24): self.lines[row] = [" "] * 110
                    elif command == "K": self.lines[self.row][self.col:] = [" "] * (110 - self.col)
                    elif command == "P": self.lines[self.row] = (self.lines[self.row][:self.col] + self.lines[self.row][self.col + n:] + [" "] * n)[:110]
                    self.row, self.col = max(0, min(23, self.row)), max(0, min(109, self.col))
                    i += len(match.group())
                    continue
                size = 3 if text[i + 1] in {"(", ")"} else 2
                if i + size > len(text):
                    self.partial = text[i:]
                    break
                i += size
                continue
            if char == "\r": self.col = 0
            elif char == "\n": self.row = min(23, self.row + 1)
            elif char == "\b": self.col = max(0, self.col - 1)
            elif char >= " ":
                self.lines[self.row][self.col] = char
                self.col = min(109, self.col + 1)
            i += 1

    def text(self):
        return "\n".join("".join(line) for line in self.lines)


def test_system_curses_pagination_refresh_loading_and_session_preservation(tmp_path):
    root = tmp_path / "installation"
    (root / "modules").mkdir(parents=True)
    shutil.copytree(ROOT / "modules/system", root / "modules/system")
    (root / "core").symlink_to(ROOT / "core", target_is_directory=True)
    (root / "config").mkdir()
    (root / "config/modules.conf").write_text("system=enabled\n")
    (root / "data/runtime").mkdir(parents=True, mode=0o700)
    (root / "bin").mkdir()
    source = root / "inventory"
    source.write_text("".join(f"unit{i:04}.service loaded inactive dead Fixture\n" for i in range(51)))
    adapter = root / "bin/systemctl"
    adapter.write_text('#!/bin/sh\n[ "$1" = list-units ] || exit 2\ncat "$COLLECTION_SOURCE"\n')
    adapter.chmod(0o700)
    stream = root / "data/runtime/events"
    driver = root / "backend.sh"
    driver.write_text(r'''source "$1/core/lib/module_loader.sh"
_ml_log() { :; }
igor_load_all_modules >/dev/null
source "$1/core/ai/core.sh"
_ai_emit_operator_snapshot
_ai_frontend_event model_status '' input_ready
while IFS= read -r request; do
    [ "$request" != quit ] || break
    _ai_frontend_control "$request"
    _ai_frontend_event model_status '' input_ready
done
_ai_frontend_event session_finished '' completed
''')
    env = dict(os.environ, IGOR_DIR=str(root), IGOR_DATA_DIR=str(root / "data"),
               IGOR_RUNTIME_DIR=str(root / "data/runtime"), IGOR_PYTHON=sys.executable,
               IGOR_DISTRO_ID="debian", IGOR_DISTRO_FAMILY="debian", COLLECTION_SOURCE=str(source),
               IGOR_AI_MODE="assist", IGOR_AI_FRONTEND="tui", TERM="xterm",
               IGOR_AI_EVENT_STREAM=str(stream), IGOR_TUI_MOUSE="0",
               PATH=str(root / "bin") + ":" + os.environ["PATH"])
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 110, 0, 0))
    script = 'import sys;from pathlib import Path;sys.path.insert(0,sys.argv[1]);import tui;raise SystemExit(tui.run_tui(["bash",sys.argv[2],sys.argv[3]],stream=Path(sys.argv[4])))'
    process = subprocess.Popen([sys.executable, "-c", script, str(ROOT / "core/ai"), str(driver), str(ROOT), str(stream)],
                               env=env, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    os.close(slave)
    transcript = bytearray()
    terminal = Terminal()
    def wait_text(expected, timeout=65):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.05)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                transcript.extend(data)
                terminal.feed(data)
                if expected in terminal.text():
                    return time.monotonic()
            if process.poll() is not None:
                break
        raise AssertionError(f"missing {expected!r}: {transcript[-5000:].decode(errors='replace')}")
    def events():
        return [json.loads(line) for line in stream.read_text().splitlines()]
    def memory():
        fields = {}
        for line in Path(f"/proc/{process.pid}/status").read_text().splitlines():
            if line.startswith(("VmRSS:", "VmHWM:")):
                name, value, _ = line.split()
                fields[name.rstrip(":")] = int(value)
        return fields
    started = time.monotonic()
    try:
        wait_text("READY")
        baseline_memory = memory()
        sent_at = time.monotonic()
        os.write(master, b":system.service.list\n")
        loading_at = wait_text("Loading; request continues", 5)
        busy_at = time.monotonic()
        os.write(master, b"n")
        busy_drawn_at = wait_text("Backend busy; Esc", 3)
        first_at = wait_text("Rows 1-50 of 51")
        wait_text("Backend READY", 15)
        first = next(e for e in events() if e["event_type"] == "action_result" and e.get("result", {}).get("capability_id") == "system.service.list")
        assert first["result"]["output_status"] == "valid"
        cursor = first["result"]["result"]["page"]["next_cursor"]
        os.write(master, b"n")
        wait_text("Rows 51-51 of 51")
        wait_text("Backend READY", 15)
        os.write(master, b"p")
        previous_at = time.monotonic()
        wait_text("Rows 1-50 of 51", 3)
        previous_latency = time.monotonic() - previous_at
        source.write_text("changed.service loaded active running Updated\n")
        os.write(master, b"r")
        wait_text("Rows 1-1 of 1")
        wait_text("Backend READY", 15)
        records = [e for e in events() if e["event_type"] == "action_result" and e.get("result", {}).get("capability_id") == "system.service.list"]
        assert len(records) == 3
        assert len({e["result"]["operation_id"] for e in records}) == 3
        assert records[0]["result"]["result"]["page"]["snapshot_revision"] == records[1]["result"]["result"]["page"]["snapshot_revision"]
        assert records[2]["result"]["result"]["page"]["snapshot_revision"] != records[0]["result"]["result"]["page"]["snapshot_revision"]
        assert all(len(json.dumps(e, ensure_ascii=False, separators=(",", ":")).encode()) <= 98304 for e in records)
        assert cursor.encode() not in transcript
        os.write(master, b"\x1b")
        wait_text("LIVE", 3)
        released_memory = memory()
        os.write(master, b"quit\n")
        process.wait(timeout=10)
        assert process.returncode == 0
        measurement = {"environment": platform.platform(), "frontend": "actual curses with outer PTY, 24x110",
                       "backend": "existing operator control/ai_execute_tool/canonical System; mocked systemctl",
                       "loading_visible_seconds": loading_at - sent_at,
                       "busy_key_redraw_seconds": busy_drawn_at - busy_at,
                       "first_page_seconds": first_at - sent_at,
                       "cached_back_seconds": previous_latency, "whole_sequence_seconds": time.monotonic() - started,
                       "baseline_frontend_memory_kib": baseline_memory, "after_close_frontend_memory_kib": released_memory,
                       "memory_scope": "actual frontend process VmRSS samples and VmHWM; 51-row fixture, not maximum UTF-8 pages or Pi acceptance"}
        if os.environ.get("IGOR_VALIDATION_REPORT"):
            (Path(os.environ["IGOR_VALIDATION_REPORT"]).parent / "collection-tui-measurement.json").write_text(json.dumps(measurement, indent=2) + "\n")
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=10)
        os.close(master)
