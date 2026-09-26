#!/usr/bin/env python3
"""Small curses frontend for the structured Igor AI event stream.

This module is intentionally a frontend boundary.  It never classifies or
executes actions: input is written to the backend PTY and all visible state is
derived from the ordered JSONL event stream.  The pure state helpers make the
renderer usable in tests and by a future frontend without importing curses.
"""

from __future__ import annotations

import codecs
import curses
import errno
import fcntl
import json
import os
import pty
import re
import shlex
import signal
import subprocess
import sys
import termios
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BACKEND = ("bash", str(REPO_ROOT / "igor.sh"), "--ai-tui-backend")
_ANSI = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))")
EVENT_TYPES = frozenset(
    {
        "session_started", "model_status", "assistant_message", "action_proposed",
        "approval_waiting", "explanation", "action_started", "action_output",
        "action_result", "action_skipped", "action_declined", "action_stopped",
        "continuation", "warning", "error", "mode_changed", "session_finished",
    }
)


@dataclass
class Activity:
    """One displayable activity item retained by the lightweight history."""

    event_type: str
    text: str
    action_id: str = ""
    classification: str = ""
    status: str = ""
    result: dict[str, Any] | None = None
    repeats: int = 1
    show_result_output: bool = True


@dataclass
class EventState:
    """Frontend projection of canonical backend events."""

    mode: str = "assist"
    session_status: str = "starting"
    provider: str = ""
    model: str = ""
    sequence: int = 0
    activity: list[Activity] = field(default_factory=list)
    pending_action: dict[str, Any] | None = None
    finished: bool = False
    console_capture: Activity | None = None
    output_action_ids: set[str] = field(default_factory=set)

    def accept(self, event: dict[str, Any]) -> bool:
        """Apply one event if it is valid and newer than the current stream."""
        kind = event.get("event_type")
        sequence = event.get("sequence", 0)
        if kind not in EVENT_TYPES or not isinstance(sequence, int):
            return False
        if sequence <= self.sequence:
            return False
        self.cancel_terminal_capture()
        self.sequence = sequence
        self.mode = str(event.get("mode") or self.mode)
        self.provider = str(event.get("provider") or self.provider)
        self.model = str(event.get("model") or self.model)
        if kind in {"session_started", "model_status", "continuation", "session_finished"}:
            self.session_status = str(event.get("status") or self.session_status)
        if kind == "session_finished":
            self.finished = True
        if kind == "approval_waiting":
            self.pending_action = dict(event)
        elif kind in {"action_started", "action_output", "action_result",
                      "action_skipped", "action_declined", "action_stopped"}:
            if kind != "action_output" and self.pending_action:
                pending_ids = {str(self.pending_action.get(key) or "") for key in
                               ("action_id", "operation_id", "tool_call_id")} - {""}
                event_ids = {str(event.get(key) or "") for key in
                             ("action_id", "operation_id", "tool_call_id")} - {""}
                if pending_ids & event_ids:
                    self.pending_action = None
        text = str(event.get("display") or event.get("output") or "")
        result = event.get("result")
        action_ids = {str(event.get(key) or "") for key in
                      ("action_id", "operation_id", "tool_call_id")} - {""}
        adjacent_output = bool(self.activity and self.activity[-1].event_type == "action_output")
        if kind == "action_output":
            self.output_action_ids.update(action_ids)
        if kind in {"session_started", "model_status", "session_finished"} and not text:
            return True
        if kind in {"warning", "error"} and self.activity:
            previous = self.activity[-1]
            if previous.event_type == kind and previous.text == text:
                previous.repeats += 1
                return True
        self.activity.append(Activity(
            event_type=kind,
            text=text,
            action_id=str(event.get("action_id") or event.get("operation_id") or event.get("tool_call_id") or ""),
            classification=str(event.get("classification") or ""),
            status=str(event.get("status") or ""),
            result=result if isinstance(result, dict) else None,
            show_result_output=not (kind == "action_result" and
                                    (bool(action_ids & self.output_action_ids) or
                                     (not action_ids and adjacent_output))),
        ))
        if len(self.activity) > 2000:
            del self.activity[:-2000]
        return True

    def begin_terminal_capture(self) -> None:
        """Show opaque output only for a local command without event output."""
        self.console_capture = Activity("terminal", "")
        self.activity.append(self.console_capture)

    def end_terminal_capture(self) -> None:
        if self.console_capture and not self.console_capture.text:
            self.activity = [item for item in self.activity if item is not self.console_capture]
        self.console_capture = None

    def cancel_terminal_capture(self) -> None:
        if self.console_capture:
            self.activity = [item for item in self.activity if item is not self.console_capture]
        self.console_capture = None

    def add_terminal_output(self, text: str) -> None:
        """Append PTY chunks to one opaque local-command output block."""
        if self.console_capture:
            self.console_capture.text = (self.console_capture.text + text)[-100_000:]


def apply_event(state: EventState, event: dict[str, Any]) -> bool:
    """Testable event application entry point."""
    return state.accept(event)


def _clean_terminal_output(raw: str) -> str:
    """Keep legacy command output readable without interpreting it as state."""
    clean = "".join(char for char in _ANSI.sub("", raw).replace("\r", "")
                    if char in "\n\t" or ord(char) >= 32)
    show_debug = (os.environ.get("IGOR_VERBOSE", "").lower() == "true" or
                  os.environ.get("IGOR_DEBUG", "").lower() == "true")
    lines: list[str] = []
    for line in clean.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("DEBUG:") and not show_debug:
            continue
        if (lines and line == lines[-1] and
                stripped.startswith(("DEBUG:", "WARNING:"))):
            continue
        lines.append(line)
    return "\n".join(lines).rstrip("\n")


def _activity_text(item: Activity) -> str:
    labels = {
        "terminal": "",
        "session_started": "Session",
        "model_status": "Model",
        "assistant_message": "Igor",
        "action_proposed": "Action",
        "approval_waiting": "Approval",
        "explanation": "Explain",
        "action_started": "Started",
        "action_output": "Output",
        "action_result": "Result",
        "action_skipped": "Skipped",
        "action_declined": "Declined",
        "action_stopped": "Stopped",
        "continuation": "Progress",
        "warning": "Warning",
        "error": "Error",
        "mode_changed": "Mode",
        "session_finished": "Session",
    }
    prefix = labels.get(item.event_type, item.event_type)
    if item.event_type == "action_proposed" and item.classification:
        prefix = f"{prefix} [{item.classification}]"
    if item.event_type == "terminal":
        return _clean_terminal_output(item.text)
    if item.event_type == "action_result":
        status = item.status or (item.result or {}).get("execution_status") or "complete"
        exit_code = (item.result or {}).get("exit_code")
        suffix = f" (exit {exit_code})" if exit_code is not None else ""
        output = (item.result or {}).get("combined_output") or (item.result or {}).get("output")
        if item.show_result_output and output:
            return f"Result: {status}{suffix}\n{output}"
        return f"Result: {status}{suffix}"
    if not item.text and item.result:
        result_status = item.result.get("execution_status") or item.result.get("status") or "complete"
        result_output = item.result.get("combined_output") or item.result.get("output") or ""
        item_text = f"{result_status}: {result_output}" if result_output else str(result_status)
        return f"{prefix}: {item_text}"
    message = (item.text if item.text.lower().startswith(f"{prefix.lower()}: ") else
               f"{prefix}: {item.text}" if item.text else prefix)
    return f"{message} (×{item.repeats})" if item.repeats > 1 else message


def _wrap_line(line: str, width: int) -> list[str]:
    """Wrap at word boundaries without dropping or changing any characters."""
    if not line:
        return [""]
    rows: list[str] = []
    current = ""
    for token in re.findall(r"\s+|\S+", line):
        if len(current) + len(token) > width and current and not token.isspace():
            rows.append(current)
            current = ""
        while token:
            available = width - len(current)
            if available == 0:
                rows.append(current)
                current = ""
                available = width
            take = min(len(token), available)
            current += token[:take]
            token = token[take:]
    if current:
        rows.append(current)
    return rows


def render_activity(state: EventState, width: int) -> list[str]:
    """Return wrapped activity lines, with no terminal side effects."""
    width = max(1, width)
    lines: list[str] = []
    for item in state.activity:
        text = _activity_text(item)
        if not text:
            continue
        if lines and lines[-1] != "":
            lines.append("")
        for logical_line in text.split("\n"):
            lines.extend(_wrap_line(logical_line, width))
    return lines


def registry_is_local(text: str) -> bool:
    """Ask the canonical registry whether an input is a local command."""
    if not text.strip():
        return False
    registry = Path(__file__).with_name("session_commands.py")
    try:
        completed = subprocess.run(
            [sys.executable, str(registry), "lookup", "--state", "ready", text],
            check=True, capture_output=True, text=True,
        )
        return bool(json.loads(completed.stdout).get("matched"))
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return False


def registry_palette(filter_text: str = "", state: str = "ready") -> list[dict[str, str]]:
    """Read palette entries from the canonical registry for display only."""
    registry = Path(__file__).with_name("session_commands.py")
    command = [sys.executable, str(registry), "palette", "--state", state]
    if filter_text:
        command.append(filter_text)
    try:
        completed = subprocess.run(command, check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError):
        return []
    entries = []
    for line in completed.stdout.splitlines():
        name, _, remainder = line.partition("\t")
        syntax, _, description = remainder.partition("\t")
        entries.append({"name": name, "syntax": syntax, "description": description})
    return entries


@dataclass
class InputBuffer:
    """Multiline input with a small, terminal independent editing surface."""

    lines: list[str] = field(default_factory=lambda: [""])
    row: int = 0
    column: int = 0

    def insert(self, text: str) -> None:
        before, after = self.lines[self.row][: self.column], self.lines[self.row][self.column :]
        parts = text.split("\n")
        self.lines[self.row] = before + parts[0]
        if len(parts) > 1:
            self.lines[self.row + 1 : self.row + 1] = [*parts[1:-1], parts[-1] + after]
            self.row += len(parts) - 1
            self.column = len(parts[-1])
        else:
            self.lines[self.row] += after
            self.column += len(text)

    def backspace(self) -> None:
        if self.column:
            self.lines[self.row] = self.lines[self.row][: self.column - 1] + self.lines[self.row][self.column :]
            self.column -= 1
        elif self.row:
            prior = self.lines.pop(self.row - 1)
            self.row -= 1
            self.column = len(prior)
            self.lines[self.row] = prior + self.lines[self.row]

    def text(self) -> str:
        return "\n".join(self.lines)

    def clear(self) -> str:
        value = self.text()
        self.lines, self.row, self.column = [""], 0, 0
        return value


def event_path(runtime: str | None = None) -> Path:
    configured = os.environ.get("IGOR_AI_EVENT_STREAM")
    if configured:
        return Path(configured).expanduser().resolve()
    raw_runtime = runtime or os.environ.get("IGOR_RUNTIME_DIR")
    runtime_dir = Path(raw_runtime) if raw_runtime else Path(os.environ.get("IGOR_DIR", REPO_ROOT)) / "data" / "runtime"
    return runtime_dir.expanduser().resolve() / "ai-events.jsonl"


def _private_stream_path() -> Path:
    raw_runtime = os.environ.get("IGOR_RUNTIME_DIR")
    runtime_dir = Path(raw_runtime) if raw_runtime else Path(os.environ.get("IGOR_DIR", REPO_ROOT)) / "data" / "runtime"
    runtime_dir = runtime_dir.expanduser().resolve()
    runtime_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    stat_result = runtime_dir.stat()
    if not runtime_dir.is_dir() or stat_result.st_uid != os.getuid() or stat_result.st_mode & 0o077:
        raise RuntimeError(f"runtime directory is not private: {runtime_dir}")
    return runtime_dir / f"ai-tui-{os.getpid()}-{uuid.uuid4().hex}.jsonl"


class EventReader:
    """Incremental JSONL reader that retains a writer's partial final line."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.offset = 0
        self.partial = b""

    def read(self) -> list[dict[str, Any]]:
        if not self.path.exists() or not self.path.is_file():
            return []
        try:
            with self.path.open("rb") as stream:
                stream.seek(self.offset)
                data = self.partial + stream.read()
                self.offset = stream.tell()
        except OSError:
            return []
        chunks = data.split(b"\n")
        self.partial = chunks.pop() if chunks else b""
        events = []
        for line in chunks:
            try:
                value = json.loads(line.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if isinstance(value, dict):
                events.append(value)
        return events


def _draw(screen: Any, state: EventState, buffer: InputBuffer, scroll: int) -> None:
    screen.erase()
    height, width = screen.getmaxyx()
    if height < 1 or width < 1:
        return
    header = f"Igor  mode: {state.mode.upper()}  status: {state.session_status}"
    if state.provider or state.model:
        header += f"  {state.provider}/{state.model}".rstrip("/")
    try:
        screen.addnstr(0, 0, header, max(1, width - 1), curses.A_BOLD)
    except curses.error:
        pass
    if height < 5:
        try:
            screen.addnstr(height - 1, 0, "> " + buffer.lines[-1], max(1, width - 1))
            screen.move(height - 1, min(2 + buffer.column, width - 1))
            screen.refresh()
        except curses.error:
            pass
        return
    input_rows = min(3, height - 3)
    separator = height - input_rows - 2
    activity_height = max(0, separator - 1)
    viewport_width = max(1, width - 1)
    lines = render_activity(state, viewport_width)
    start = max(0, len(lines) - activity_height - max(0, scroll))
    visible = lines[start : start + activity_height]
    for row, line in enumerate(visible, 1):
        try:
            screen.addnstr(row, 0, line, viewport_width)
        except curses.error:
            pass
    try:
        screen.hline(separator, 0, curses.ACS_HLINE, width)
        hint = "Enter: send  Ctrl-O/Alt-Enter: newline  PageUp/PageDown: scroll  /stop: stop"
        if state.pending_action:
            tier = state.pending_action.get("classification", "ACTION")
            if tier == "DESTROY":
                hint = "DESTROY pending: type YES exactly to confirm, or NO / EXPLAIN / STOP"
            elif tier == "CHANGE":
                hint = "CHANGE pending: type YES / NO / EXPLAIN / STOP, then Enter"
            else:
                hint = "READ proposed: type RUN / SKIP / EXPLAIN / STOP, then Enter"
        screen.addnstr(separator + 1, 0, hint, max(1, width - 1), curses.A_DIM)
        input_start = separator + 2
        for row, line in enumerate(buffer.lines[-input_rows:], input_start):
            screen.addnstr(row, 0, "> " + line, max(1, width - 1))
        cursor_row = min(input_start + min(buffer.row, input_rows - 1), height - 1)
        cursor_col = min(2 + buffer.column, max(0, width - 1))
        screen.move(cursor_row, cursor_col)
    except curses.error:
        pass
    try:
        screen.refresh()
    except curses.error:
        pass


def _send(master: int, text: str) -> None:
    os.write(master, text.encode("utf-8", "replace") + b"\n")


def _next_key(screen: Any) -> int | str:
    """Use wide-character input when the terminal supports it."""
    try:
        key = screen.get_wch() if hasattr(screen, "get_wch") else screen.getch()
    except curses.error:
        return -1
    if isinstance(key, str) and len(key) == 1 and ord(key) <= 255:
        return ord(key)
    return key


def _palette_overlay(screen: Any, master: int, buffer: InputBuffer) -> str | None:
    """Minimal registry-backed palette; selected commands use the backend route."""
    query, selected = "", 0
    entries = registry_palette(query)
    screen.timeout(100)
    try:
        while True:
            height, width = screen.getmaxyx()
            screen.erase()
            if height > 0 and width > 0:
                try:
                    screen.addnstr(0, 0, f"Palette: {query}", max(1, width - 1), curses.A_BOLD)
                except curses.error:
                    pass
                visible_count = max(1, height - 2)
                first = max(0, selected - visible_count + 1)
                for row, entry in enumerate(entries[first:first + visible_count], 1):
                    marker = ">" if first + row - 1 == selected else " "
                    text = f"{marker} {entry['syntax']}  {entry['description']}"
                    try:
                        screen.addnstr(row, 0, text, max(1, width - 1), curses.A_REVERSE if marker == ">" else 0)
                    except curses.error:
                        pass
            screen.refresh()
            key = screen.getch()
            if key in (27, 3):
                return None
            if key == curses.KEY_UP:
                selected = max(0, selected - 1)
            elif key == curses.KEY_DOWN:
                selected = min(max(0, len(entries) - 1), selected + 1)
            elif key in (10, 13, curses.KEY_ENTER) and entries:
                entry = entries[selected]
                if entry["syntax"] == entry["name"]:
                    _send(master, entry["name"])
                    return entry["name"]
                else:
                    buffer.insert(entry["name"] + " ")
                    return None
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                query = query[:-1]
                selected = 0
                entries = registry_palette(query)
            elif 0 <= key <= 255:
                query += chr(key)
                selected = 0
                entries = registry_palette(query)
    finally:
        screen.timeout(100)


def run_tui(backend: Iterable[str] = DEFAULT_BACKEND, stream: Path | None = None) -> int:
    """Run the frontend and its backend in a PTY."""
    own_stream = stream is None
    path = (stream or _private_stream_path()).expanduser().resolve()
    environment = os.environ.copy()
    environment.update(IGOR_TUI_MODE="true", IGOR_AI_EVENT_RENDER="false",
                       IGOR_AI_EVENT_STREAM=str(path), IGOR_RUNTIME_DIR=str(path.parent))
    backend_command = tuple(backend)
    pid, master = pty.fork()
    if pid == 0:
        attributes = termios.tcgetattr(0)
        attributes[3] &= ~termios.ECHO
        termios.tcsetattr(0, termios.TCSANOW, attributes)
        os.execvpe(backend_command[0], backend_command, environment)
    flags = fcntl.fcntl(master, fcntl.F_GETFL)
    fcntl.fcntl(master, fcntl.F_SETFL, flags | os.O_NONBLOCK)
    state = EventState()
    try:
        try:
            result = curses.wrapper(lambda screen: _loop(screen, pid, master, path, state))
        except curses.error as error:
            print(f"AI TUI could not start: {error}. Use bash igor.sh for the classic UI.",
                  file=sys.stderr)
            return 2
        if result:
            message = next((item.text for item in reversed(state.activity)
                            if item.event_type == "error" and item.text), "Backend exited early")
            print(f"AI TUI: {message}", file=sys.stderr)
        return result
    finally:
        try:
            os.close(master)
        except OSError:
            pass
        try:
            waited, _ = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            waited = pid
        if not waited:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            deadline = time.monotonic() + 1.0
            while time.monotonic() < deadline:
                try:
                    waited, _ = os.waitpid(pid, os.WNOHANG)
                except ChildProcessError:
                    break
                if waited:
                    break
                time.sleep(0.01)
            else:
                try:
                    os.kill(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
                except (ChildProcessError, ProcessLookupError):
                    pass
        if own_stream:
            try:
                path.unlink()
            except FileNotFoundError:
                pass


def _child_exit_code(pid: int, block: bool) -> int | None:
    try:
        waited, status = os.waitpid(pid, 0 if block else os.WNOHANG)
    except ChildProcessError:
        return 0
    return os.waitstatus_to_exitcode(status) if waited else None


def _loop(screen: Any, pid: int, master: int, path: Path,
          state: EventState | None = None) -> int:
    screen.keypad(True)
    screen.timeout(100)
    state, buffer, scroll = state or EventState(), InputBuffer(), 0
    reader = EventReader(path)
    terminal_decoder = codecs.getincrementaldecoder("utf-8")("replace")
    dirty = True
    while True:
        events = reader.read()
        for event in events:
            apply_event(state, event)
        dirty = dirty or bool(events)
        try:
            raw = os.read(master, 4096)
            if not raw:
                return _child_exit_code(pid, True) or 0
            if state.console_capture:
                state.add_terminal_output(terminal_decoder.decode(raw))
                dirty = True
            else:
                terminal_decoder.reset()
        except BlockingIOError:
            pass
        except OSError as error:
            if error.errno == errno.EIO:
                return _child_exit_code(pid, True) or 0
            raise
        if dirty:
            _draw(screen, state, buffer, scroll)
            dirty = False
        key = _next_key(screen)
        if key == -1:
            if state.finished:
                result = _child_exit_code(pid, False)
                if result is not None:
                    return result
            continue
        dirty = True
        if isinstance(key, str):
            buffer.insert(key)
            continue
        if key == curses.KEY_RESIZE:
            continue
        if key in (3, 27):
            if key == 27:
                screen.timeout(80)
                nxt = screen.getch()
                screen.timeout(100)
                if nxt in (10, 13, curses.KEY_ENTER):
                    buffer.insert("\n")
                    continue
            _send(master, "/stop")
            state.end_terminal_capture()
            continue
        if key == ord(":") and not buffer.text() and not state.pending_action:
            selected = _palette_overlay(screen, master, buffer)
            if selected and registry_is_local(selected):
                state.end_terminal_capture()
                state.begin_terminal_capture()
            continue
        if key in (curses.KEY_PPAGE,):
            scroll += 3
        elif key in (curses.KEY_NPAGE,):
            scroll = max(0, scroll - 3)
        elif key in (10, 13, curses.KEY_ENTER):
            submitted = buffer.clear()
            if state.pending_action:
                submitted = submitted.splitlines()[0] if submitted.splitlines() else ""
            state.end_terminal_capture()
            if not state.pending_action and registry_is_local(submitted):
                state.begin_terminal_capture()
            _send(master, submitted)
            scroll = 0
        elif key == 15:
            buffer.insert("\n")
        elif key in (curses.KEY_BACKSPACE, 127, 8):
            buffer.backspace()
        elif key == 9:
            buffer.insert("\t")
        elif 0 <= key <= 255:
            buffer.insert(chr(key))



def main(argv: list[str] | None = None) -> int:
    args = list(argv if argv is not None else sys.argv[1:])
    backend: tuple[str, ...] = DEFAULT_BACKEND
    if args and args[0] == "--backend":
        backend = tuple(shlex.split(" ".join(args[1:]))) or DEFAULT_BACKEND
    try:
        return run_tui(backend)
    except (OSError, RuntimeError) as error:
        print(f"AI TUI could not start: {error}. Use bash igor.sh for the classic UI.",
              file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
