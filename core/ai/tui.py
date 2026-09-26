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
        "privilege_waiting", "privilege_result", "continuation", "warning", "error",
        "mode_changed", "settings_snapshot", "session_finished",
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
    exit_code: int | None = None
    requires_admin_auth: bool = False


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
    privilege_waiting: dict[str, Any] | None = None
    finished: bool = False
    console_capture: Activity | None = None
    output_action_ids: set[str] = field(default_factory=set)
    collapse_output: bool = False
    command_state: str = "ready"
    settings_snapshot: dict[str, Any] | None = None

    def accept(self, event: dict[str, Any]) -> bool:
        """Apply one event if it is valid and newer than the current stream."""
        kind = event.get("event_type")
        sequence = event.get("sequence", 0)
        # The backend stream uses strictly positive integer sequence numbers.
        # Reject malformed values at the projection boundary so a forged or
        # truncated frontend record cannot move the rendered state backwards
        # or make the first event appear authoritative.
        if (kind not in EVENT_TYPES or not isinstance(sequence, int)
                or isinstance(sequence, bool) or sequence <= 0):
            return False
        if sequence <= self.sequence:
            return False
        if kind != "settings_snapshot":
            self.cancel_terminal_capture()
        self.sequence = sequence
        self.mode = str(event.get("mode") or self.mode)
        self.provider = str(event.get("provider") or self.provider)
        self.model = str(event.get("model") or self.model)
        event_status = str(event.get("status") or "")
        if event_status in {"ready", "running", "stopped_by_user", "continuation_limit",
                            "tool_succeeded", "tool_failed", "provider_failed"}:
            self.command_state = event_status
        elif kind == "continuation":
            self.command_state = "running"
        if kind in {"session_started", "model_status", "continuation", "session_finished"}:
            self.session_status = str(event.get("status") or self.session_status)
        elif kind in {"warning", "error"} and event_status:
            self.session_status = event_status
        if kind == "session_finished":
            self.finished = True
        if kind == "settings_snapshot":
            snapshot = event.get("settings")
            if isinstance(snapshot, dict):
                self.settings_snapshot = dict(snapshot)
                self.mode = str(snapshot.get("mode") or self.mode)
                self.provider = str(snapshot.get("provider") or self.provider)
                self.model = str(snapshot.get("model") or self.model)
            return True
        if kind == "approval_waiting":
            self.pending_action = dict(event)
        elif kind == "privilege_waiting":
            self.privilege_waiting = dict(event)
        elif kind in {"privilege_result", "action_result", "action_stopped"}:
            if self.privilege_waiting:
                waiting_id = str(self.privilege_waiting.get("operation_id") or "")
                event_id = str(event.get("operation_id") or "")
                if waiting_id and waiting_id == event_id:
                    self.privilege_waiting = None
        if kind in {"action_started", "action_output", "action_result",
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
            exit_code=event.get("exit_code") if isinstance(event.get("exit_code"), int) else None,
            requires_admin_auth=event.get("requires_admin_auth") is True,
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

    def add_user_input(self, text: str) -> None:
        if text:
            self.activity.append(Activity("user", text))
            if len(self.activity) > 2000:
                del self.activity[:-2000]


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
        "user": "You",
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
        "privilege_waiting": "Privilege",
        "privilege_result": "Privilege",
    }
    prefix = labels.get(item.event_type, item.event_type)
    if item.event_type in {"action_proposed", "approval_waiting"} and item.classification:
        prefix = f"{prefix} [{item.classification}]"
    if item.event_type in {"action_proposed", "approval_waiting"} and item.requires_admin_auth:
        prefix += " · administrator privileges"
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


# These roles are deliberately small and describe presentation only.  They
# are derived from the structured event type, so renderers never need to
# inspect or colour arbitrary assistant text.
COLOR_ROLES = ("user", "assistant", "action", "output", "warning", "error")


def activity_color_role(item: Activity) -> str:
    """Return the semantic presentation role for one structured activity."""
    if item.event_type == "user":
        return "user"
    if item.event_type in {"assistant_message", "explanation"}:
        return "assistant"
    if item.event_type in {"action_proposed", "approval_waiting", "action_started",
                           "action_skipped", "action_declined", "action_stopped",
                           "mode_changed", "privilege_waiting", "privilege_result"}:
        return "action"
    if item.event_type in {"action_output", "action_result", "terminal"}:
        return "output"
    if item.event_type == "error":
        return "error"
    if item.event_type == "warning":
        return "warning"
    return "assistant"


def _activity_rows(state: EventState, width: int) -> list[tuple[str, str]]:
    """Return wrapped rows and their semantic roles in stream order."""
    width = max(1, width)
    rows: list[tuple[str, str]] = []
    for item in state.activity:
        if (state.collapse_output and item.event_type == "action_output" and
                item.exit_code == 0):
            line_count = len(item.text.splitlines())
            text = f"Output: {line_count} lines collapsed (Ctrl+G expands)"
        else:
            text = _activity_text(item)
        if not text:
            continue
        role = activity_color_role(item)
        if rows and rows[-1][0] != "":
            rows.append(("", role))
        for logical_line in text.split("\n"):
            rows.extend((line, role) for line in _wrap_line(logical_line, width))
    return rows


def color_theme(screen: Any) -> dict[str, int]:
    """Build a restrained role-to-attribute map with a monochrome fallback.

    ``curses`` capability calls can fail on fake screens and minimal terminals,
    so every step is guarded.  Attribute-only fallback still separates the
    most important roles when colour is unavailable.
    """
    fallback = {
        "user": curses.A_BOLD,
        "assistant": curses.A_NORMAL,
        "action": curses.A_BOLD,
        "output": curses.A_NORMAL,
        "warning": curses.A_BOLD,
        "error": curses.A_BOLD,
    }
    try:
        if not curses.has_colors():
            return fallback
        curses.start_color()
        if hasattr(curses, "use_default_colors"):
            try:
                curses.use_default_colors()
            except curses.error:
                pass
        colours = {
            "user": getattr(curses, "COLOR_CYAN", 6),
            "assistant": getattr(curses, "COLOR_GREEN", 2),
            "action": getattr(curses, "COLOR_YELLOW", 3),
            "output": getattr(curses, "COLOR_WHITE", 7),
            "warning": getattr(curses, "COLOR_YELLOW", 3),
            "error": getattr(curses, "COLOR_RED", 1),
        }
        result: dict[str, int] = {}
        for pair, role in enumerate(COLOR_ROLES, 1):
            curses.init_pair(pair, colours[role], -1)
            result[role] = curses.color_pair(pair)
        result["user"] |= curses.A_BOLD
        result["action"] |= curses.A_BOLD
        result["warning"] |= curses.A_BOLD
        result["error"] |= curses.A_BOLD
        return result
    except (AttributeError, curses.error, TypeError, ValueError):
        return fallback


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
    return [line for line, _role in _activity_rows(state, width)]


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


def registry_commands() -> list[dict[str, Any]]:
    """Load command metadata once from the Step 2 registry."""
    registry = Path(__file__).with_name("session_commands.py")
    try:
        completed = subprocess.run(
            [sys.executable, str(registry), "commands"],
            check=True, capture_output=True, text=True,
        )
        value = json.loads(completed.stdout)
        return [item for item in value if isinstance(item, dict)] if isinstance(value, list) else []
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return []


def palette_entries(commands: list[dict[str, Any]], query: str,
                    session_state: str) -> list[dict[str, Any]]:
    """Filter registry metadata and annotate availability for display only."""
    needle = query.strip().casefold()
    entries = []
    for command in commands:
        if command.get("name") == "palette":
            continue
        searchable = " ".join(str(part) for part in (
            command.get("name", ""), command.get("syntax", ""),
            command.get("description", ""), *(command.get("aliases") or [])))
        if needle and needle not in searchable.casefold():
            continue
        allowed_states = command.get("states") or []
        entries.append({**command, "available": not allowed_states or
                        session_state in allowed_states})
    if needle:
        def rank(entry: dict[str, Any]) -> int:
            name = str(entry.get("name", "")).casefold()
            syntax = str(entry.get("syntax", "")).casefold()
            aliases = [str(alias).casefold() for alias in entry.get("aliases") or []]
            if name.startswith(needle):
                return 0
            if needle in name:
                return 1
            if any(alias.startswith(needle) for alias in aliases):
                return 2
            if needle in syntax:
                return 3
            return 4
        entries.sort(key=rank)
    return entries


# Presentation metadata only. Values arrive from the backend settings snapshot,
# and every edit is sent through the same registered command route as typed input.
SETTINGS_FIELDS = (
    ("provider", "Provider", "choice", ("openrouter", "anthropic", "ollama")),
    ("model", "Model", "text", ()),
    ("temperature", "Temperature", "text", ()),
    ("max_tokens", "Max tokens", "text", ()),
    ("mode", "Mode", "choice", ("guide", "assist", "executive")),
    ("verbose", "Verbose", "toggle", ()),
    ("ai_autostart", "AI Autostart", "toggle", ()),
    ("hybrid_menu", "Hybrid menu", "toggle", ()),
)


def settings_value(snapshot: dict[str, Any], key: str) -> str:
    value = snapshot.get(key, "")
    if key in {"verbose", "ai_autostart", "hybrid_menu"}:
        return "On" if str(value).lower() in {"true", "on", "1"} else "Off"
    if key == "provider":
        return {"openrouter": "OpenRouter", "anthropic": "Anthropic",
                "ollama": "Ollama"}.get(str(value).lower(), str(value))
    if key == "mode":
        return str(value).capitalize()
    return str(value)


def settings_change_command(key: str, value: str) -> str:
    """Build a registered local command; backend validation remains final."""
    if "\n" in value or "\r" in value:
        raise ValueError("settings values must fit on one line")
    value = value.strip()
    if not value:
        raise ValueError("a value is required")
    if key == "mode":
        return f"mode {value}"
    if key == "verbose":
        return f"verbose {value}"
    if key == "ai_autostart":
        return f"settings autostart {value}"
    if key == "hybrid_menu":
        return f"settings hybrid {value}"
    if key in {"provider", "model", "temperature", "max_tokens"}:
        return f"settings {key} {value}"
    raise ValueError("unknown setting")


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

    def delete(self) -> None:
        line = self.lines[self.row]
        if self.column < len(line):
            self.lines[self.row] = line[:self.column] + line[self.column + 1:]
        elif self.row < len(self.lines) - 1:
            self.lines[self.row] += self.lines.pop(self.row + 1)

    def delete_word_left(self) -> None:
        line = self.lines[self.row]
        if not self.column:
            self.backspace()
            return
        start = self.column
        while start > 0 and line[start - 1].isspace():
            start -= 1
        while start > 0 and not line[start - 1].isspace():
            start -= 1
        self.lines[self.row] = line[:start] + line[self.column:]
        self.column = start

    def move_left(self) -> None:
        if self.column:
            self.column -= 1
        elif self.row:
            self.row -= 1
            self.column = len(self.lines[self.row])

    def move_right(self) -> None:
        if self.column < len(self.lines[self.row]):
            self.column += 1
        elif self.row < len(self.lines) - 1:
            self.row += 1
            self.column = 0

    def move_up(self) -> bool:
        if self.row == 0:
            return False
        self.row -= 1
        self.column = min(self.column, len(self.lines[self.row]))
        return True

    def move_down(self) -> bool:
        if self.row >= len(self.lines) - 1:
            return False
        self.row += 1
        self.column = min(self.column, len(self.lines[self.row]))
        return True

    def move_home(self) -> None:
        self.column = 0

    def move_end(self) -> None:
        self.column = len(self.lines[self.row])

    def replace(self, text: str) -> None:
        self.lines = text.split("\n")
        self.row = len(self.lines) - 1
        self.column = len(self.lines[self.row])

    def text(self) -> str:
        return "\n".join(self.lines)

    def clear(self) -> str:
        value = self.text()
        self.lines, self.row, self.column = [""], 0, 0
        return value


@dataclass
class InputHistory:
    prompts: list[str] = field(default_factory=list)
    index: int | None = None
    draft: str = ""

    def add(self, text: str) -> None:
        if text and (not self.prompts or self.prompts[-1] != text):
            self.prompts.append(text)
            del self.prompts[:-100]
        self.index = None
        self.draft = ""

    def previous(self, current: str) -> str | None:
        if not self.prompts:
            return None
        if self.index is None:
            self.draft = current
            self.index = len(self.prompts) - 1
        else:
            self.index = max(0, self.index - 1)
        return self.prompts[self.index]

    def next(self) -> str | None:
        if self.index is None:
            return None
        self.index += 1
        if self.index >= len(self.prompts):
            self.index = None
            return self.draft
        return self.prompts[self.index]

    def leave(self) -> None:
        self.index = None


@dataclass
class ActivityNavigator:
    scroll: int = 0

    def line_up(self, maximum: int) -> None:
        self.scroll = min(maximum, self.scroll + 1)

    def line_down(self) -> None:
        self.scroll = max(0, self.scroll - 1)

    def page_up(self, page: int, maximum: int) -> None:
        self.scroll = min(maximum, self.scroll + max(1, page))

    def page_down(self, page: int) -> None:
        self.scroll = max(0, self.scroll - max(1, page))

    def oldest(self, maximum: int) -> None:
        self.scroll = maximum

    def latest(self) -> None:
        self.scroll = 0

    def preserve_view(self, added_lines: int, maximum: int) -> None:
        if self.scroll:
            self.scroll = min(maximum, self.scroll + max(0, added_lines))


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


def _activity_limits(screen: Any, state: EventState) -> tuple[int, int, int]:
    height, width = screen.getmaxyx()
    input_rows = min(3, max(1, height - 3))
    activity_height = max(0, height - input_rows - 3)
    line_count = len(_activity_rows(state, max(1, width - 1)))
    return activity_height, max(0, line_count - activity_height), line_count


def _draw(screen: Any, state: EventState, buffer: InputBuffer,
          scroll: int | ActivityNavigator) -> None:
    screen.erase()
    height, width = screen.getmaxyx()
    if height < 1 or width < 1:
        return
    scroll_offset = scroll.scroll if isinstance(scroll, ActivityNavigator) else scroll
    activity_height, maximum_scroll, _ = _activity_limits(screen, state)
    scroll_offset = min(max(0, scroll_offset), maximum_scroll)
    if isinstance(scroll, ActivityNavigator):
        scroll.scroll = scroll_offset
    header = f"Igor  {state.mode.upper()}  {state.session_status}"
    header += f"  ↑{scroll_offset} End=live" if scroll_offset else "  LIVE"
    if state.provider or state.model:
        header += f"  {state.provider}/{state.model}".rstrip("/")
    try:
        screen.addnstr(0, 0, header, max(1, width - 1), curses.A_BOLD)
    except curses.error:
        pass
    if height < 5:
        try:
            input_text = "Password: [hidden]" if state.privilege_waiting else "> " + buffer.lines[-1]
            screen.addnstr(height - 1, 0, input_text, max(1, width - 1))
            if not state.privilege_waiting:
                screen.move(height - 1, min(2 + buffer.column, width - 1))
            screen.refresh()
        except curses.error:
            pass
        return
    input_rows = min(3, height - 3)
    separator = height - input_rows - 2
    viewport_width = max(1, width - 1)
    rows = _activity_rows(state, viewport_width)
    theme = color_theme(screen)
    start = max(0, len(rows) - activity_height - scroll_offset)
    visible_rows = rows[start : start + activity_height]
    for row, (line, role) in enumerate(visible_rows, 1):
        try:
            screen.addnstr(row, 0, line, viewport_width, theme.get(role, curses.A_NORMAL))
        except curses.error:
            pass
    try:
        screen.hline(separator, 0, curses.ACS_HLINE, width)
        hint = "Enter send  Ctrl+O newline  ↑↓ history  :/Ctrl+P palette  F1 keys"
        if state.privilege_waiting:
            hint = "Administrator authentication required; password goes directly to sudo"
        elif state.pending_action:
            tier = state.pending_action.get("classification", "ACTION")
            if tier == "DESTROY":
                hint = "DESTROY pending: type YES exactly to confirm, or NO / EXPLAIN / STOP"
            elif tier == "CHANGE":
                hint = ("CHANGE · administrator privileges: YES / NO / EXPLAIN / STOP"
                        if state.pending_action.get("requires_admin_auth") is True else
                        "CHANGE pending: type YES / NO / EXPLAIN / STOP, then Enter")
            else:
                hint = "READ proposed: type RUN / SKIP / EXPLAIN / STOP, then Enter"
        hint_style = curses.A_BOLD if state.pending_action or state.privilege_waiting else curses.A_DIM
        screen.addnstr(separator + 1, 0, hint, max(1, width - 1), hint_style)
        input_start = separator + 2
        if state.privilege_waiting:
            screen.addnstr(input_start, 0, "Password: [hidden]", max(1, width - 1),
                           theme["user"])
            screen.move(input_start, min(len("Password: "), width - 1))
        else:
            first_input = max(0, min(buffer.row, len(buffer.lines) - input_rows))
            horizontal = max(0, buffer.column - max(1, width - 4))
            for row, line in enumerate(buffer.lines[first_input:first_input + input_rows], input_start):
                active = first_input + row - input_start == buffer.row
                start_col = horizontal if active else 0
                visible_line = line[start_col:start_col + max(1, width - 3)]
                screen.addnstr(row, 0, "> " + visible_line, max(1, width - 1),
                               theme["user"])
            cursor_row = min(input_start + buffer.row - first_input, height - 1)
            cursor_col = min(2 + buffer.column - horizontal, max(0, width - 1))
            screen.move(cursor_row, cursor_col)
    except curses.error:
        pass
    try:
        screen.refresh()
    except curses.error:
        pass


def _send(master: int, text: str) -> None:
    os.write(master, text.encode("utf-8", "replace") + b"\n")


def _privilege_key_bytes(key: int | str) -> bytes:
    """Pass one key to sudo's native tty without using the chat input buffer."""
    if isinstance(key, str):
        return key.encode("utf-8") if key.isprintable() else b""
    if key in (10, 13, curses.KEY_ENTER):
        return b"\n"
    if key in (curses.KEY_BACKSPACE, 127, 8):
        return b"\x7f"
    if key == 3:
        return b"\x03"
    if 32 <= key <= 126:
        return bytes((key,))
    return b""


def _next_key(screen: Any) -> int | str:
    """Use wide-character input when the terminal supports it."""
    try:
        key = screen.get_wch() if hasattr(screen, "get_wch") else screen.getch()
    except curses.error:
        return -1
    if isinstance(key, str) and len(key) == 1 and ord(key) <= 255:
        return ord(key)
    return key


def _palette_overlay(screen: Any, master: int, buffer: InputBuffer,
                     state: EventState | None = None,
                     commands: list[dict[str, Any]] | None = None) -> str | None:
    """Search registry commands; never implement their handlers here."""
    state = state or EventState()
    commands = commands if commands is not None else registry_commands()
    query, selected, notice = "", 0, ""
    screen.timeout(100)
    try:
        while True:
            entries = palette_entries(commands, query, state.command_state)
            height, width = screen.getmaxyx()
            screen.erase()
            if height > 0 and width > 0:
                try:
                    screen.addnstr(0, 0, f"Commands  search: {query}", max(1, width - 1), curses.A_BOLD)
                except curses.error:
                    pass
                visible_count = max(1, height - 3)
                first = max(0, selected - visible_count + 1)
                for row, entry in enumerate(entries[first:first + visible_count], 1):
                    marker = ">" if first + row - 1 == selected else " "
                    available = bool(entry["available"])
                    flag = " " if available else "×"
                    text = f"{marker}{flag} {entry['name']}  {entry['description']}"
                    try:
                        style = curses.A_REVERSE if marker == ">" else curses.A_DIM if not available else 0
                        screen.addnstr(row, 0, text, max(1, width - 1), style)
                    except curses.error:
                        pass
                footer = notice or "Enter: choose  ↑↓: select  Esc: back  ×: unavailable"
                try:
                    screen.addnstr(height - 1, 0, footer, max(1, width - 1), curses.A_DIM)
                except curses.error:
                    pass
            screen.refresh()
            key = _next_key(screen)
            if key in (27, 3):
                return None
            if key == curses.KEY_UP:
                selected = max(0, selected - 1)
            elif key == curses.KEY_DOWN:
                selected = min(max(0, len(entries) - 1), selected + 1)
            elif key in (10, 13, curses.KEY_ENTER) and entries:
                entry = entries[selected]
                if not entry["available"]:
                    notice = f"{entry['name']} unavailable in {state.command_state}"
                    continue
                if entry["name"] == "settings":
                    return "settings_view"
                if entry["syntax"] == entry["name"] and not buffer.text():
                    _send(master, entry["name"])
                    return str(entry["name"])
                buffer.replace(str(entry["name"]) +
                               (" " if entry["syntax"] != entry["name"] else ""))
                return None
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                query = query[:-1]
                selected = 0
                notice = ""
            elif isinstance(key, str) or 32 <= key <= 126:
                query += key if isinstance(key, str) else chr(key)
                selected = 0
                notice = ""
    finally:
        screen.timeout(100)


def _help_overlay(screen: Any) -> None:
    """Show keyboard controls without changing the current draft."""
    controls = [
        "Igor keyboard help — any key returns",
        "Enter send  Ctrl+O / Alt+Enter newline  Esc clear draft",
        "← → Home End move cursor  Backspace/Delete edit",
        "↑ ↓ previous/next prompt (or move within multiline input)",
        "PageUp/PageDown scroll  Home oldest  End latest (empty input)",
        "Ctrl+P or : on empty input opens command palette",
        "Ctrl+G collapse/expand successful tool output",
        "Ctrl+C or /stop sends the backend stop action",
        "Guide: Run / Skip / Explain / Stop",
        "CHANGE: Yes / No / Explain / Stop",
        "DESTROY: exact YES / No / Explain / Stop",
    ]
    screen.erase()
    height, width = screen.getmaxyx()
    for row, line in enumerate(controls[:max(0, height - 1)]):
        try:
            screen.addnstr(row, 0, line, max(1, width - 1),
                           curses.A_BOLD if row == 0 else 0)
        except curses.error:
            pass
    screen.refresh()
    screen.timeout(-1)
    _next_key(screen)
    screen.timeout(100)


def _settings_choice(screen: Any, label: str, options: tuple[str, ...],
                     current: str) -> str | None:
    selected = options.index(current) if current in options else 0
    while True:
        height, width = screen.getmaxyx()
        screen.erase()
        try:
            screen.addnstr(0, 0, f"{label}  ↑↓ choose  Enter select  Esc back",
                           max(1, width - 1), curses.A_BOLD)
            for row, option in enumerate(options[:max(0, height - 2)], 2):
                shown = (settings_value({"provider": option}, "provider")
                         if label == "Provider" else option.capitalize())
                screen.addnstr(row, 0, ("> " if row - 2 == selected else "  ") +
                               shown, max(1, width - 1),
                               curses.A_REVERSE if row - 2 == selected else 0)
        except curses.error:
            pass
        screen.refresh()
        key = _next_key(screen)
        if key in (27, 3):
            return None
        if key == curses.KEY_UP:
            selected = max(0, selected - 1)
        elif key == curses.KEY_DOWN:
            selected = min(len(options) - 1, selected + 1)
        elif key in (10, 13, curses.KEY_ENTER):
            return options[selected]


def _settings_edit(screen: Any, label: str, current: str) -> str | None:
    edit = InputBuffer()
    edit.replace(current)
    while True:
        height, width = screen.getmaxyx()
        screen.erase()
        horizontal = max(0, edit.column - max(1, width - 4))
        try:
            screen.addnstr(0, 0, f"Edit {label}  Enter save  Esc cancel",
                           max(1, width - 1), curses.A_BOLD)
            screen.addnstr(2, 0, "> " + edit.text()[horizontal:], max(1, width - 1))
            screen.move(min(2, height - 1), min(2 + edit.column - horizontal, width - 1))
        except curses.error:
            pass
        screen.refresh()
        key = _next_key(screen)
        if key in (27, 3):
            return None
        if key in (10, 13, curses.KEY_ENTER):
            return edit.text().strip()
        if key == curses.KEY_LEFT:
            edit.move_left()
        elif key == curses.KEY_RIGHT:
            edit.move_right()
        elif key in (curses.KEY_HOME, 1):
            edit.move_home()
        elif key in (curses.KEY_END, 5):
            edit.move_end()
        elif key == curses.KEY_DC:
            edit.delete()
        elif key in (curses.KEY_BACKSPACE, 127, 8):
            edit.backspace()
        elif key == 23:
            edit.delete_word_left()
        elif key in (12, 21):
            edit.clear()
        elif isinstance(key, str) and key not in "\n\r":
            edit.insert(key)
        elif isinstance(key, int) and 32 <= key <= 126:
            edit.insert(chr(key))


def _settings_overlay(screen: Any, master: int, reader: EventReader,
                      state: EventState) -> None:
    """Show backend settings snapshots and send edits through local commands."""
    selected, notice = 0, "Loading settings…"
    requested: tuple[str, str, str] | None = None
    request_failed = False
    state.settings_snapshot = None
    _send(master, "settings snapshot")
    screen.timeout(100)
    try:
        while True:
            for event in reader.read():
                apply_event(state, event)
                if event.get("event_type") == "settings_snapshot" and requested:
                    key, value, old = requested
                    actual = str((state.settings_snapshot or {}).get(key, "")).lower()
                    expected = ({"on": "true", "off": "false"}.get(value.lower(), value.lower())
                                if key in {"verbose", "ai_autostart", "hybrid_menu"}
                                else value.lower())
                    if request_failed:
                        pass
                    elif actual == expected:
                        notice = "Saved"
                    elif actual != old.lower():
                        notice = f"Applied as {settings_value(state.settings_snapshot or {}, key)}"
                    elif notice == "Saving…":
                        notice = "Unchanged; check warning"
                    requested = None
                    request_failed = False
                elif event.get("event_type") in {"warning", "error"}:
                    notice = str(event.get("display") or "Settings change failed")
                    request_failed = requested is not None
            if state.pending_action or state.finished:
                return
            # Settings commands may still print a classic summary. The view
            # consumes structured snapshots only, while draining PTY bytes.
            try:
                os.read(master, 4096)
            except (BlockingIOError, OSError):
                pass
            snapshot = state.settings_snapshot
            if snapshot is not None and notice == "Loading settings…":
                notice = ""
            height, width = screen.getmaxyx()
            screen.erase()
            try:
                screen.addnstr(0, 0, "Settings", max(1, width - 1), curses.A_BOLD)
                if snapshot is not None:
                    first = max(0, selected - max(1, height - 5) + 1)
                    for row, (key, label, _kind, _options) in enumerate(
                            SETTINGS_FIELDS[first:first + max(1, height - 4)], 2):
                        index = first + row - 2
                        marker = ">" if index == selected else " "
                        line = f"{marker} {label:<15} {settings_value(snapshot, key)}"
                        screen.addnstr(row, 0, line, max(1, width - 1),
                                       curses.A_REVERSE if index == selected else 0)
                footer = notice or "↑↓ move  Enter edit/toggle  Esc back"
                screen.addnstr(max(0, height - 1), 0, footer, max(1, width - 1),
                               curses.A_DIM)
            except curses.error:
                pass
            screen.refresh()
            key = _next_key(screen)
            if key in (27, 3):
                if key == 3:
                    _send(master, "/stop")
                return
            if key == curses.KEY_UP:
                selected = max(0, selected - 1)
            elif key == curses.KEY_DOWN:
                selected = min(len(SETTINGS_FIELDS) - 1, selected + 1)
            elif key in (10, 13, curses.KEY_ENTER) and snapshot is not None:
                field_key, label, kind, options = SETTINGS_FIELDS[selected]
                current = str(snapshot.get(field_key, ""))
                if kind == "toggle":
                    value = "off" if settings_value(snapshot, field_key) == "On" else "on"
                elif kind == "choice":
                    value = _settings_choice(screen, label, options, current)
                else:
                    value = _settings_edit(screen, label, current)
                if value is None:
                    continue
                try:
                    command = settings_change_command(field_key, value)
                except ValueError as error:
                    notice = str(error)
                    continue
                requested = (field_key, value, current)
                request_failed = False
                notice = "Saving…"
                _send(master, command)
                _send(master, "settings snapshot")
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
    state, buffer = state or EventState(), InputBuffer()
    navigator, history = ActivityNavigator(), InputHistory()
    commands = registry_commands()
    reader = EventReader(path)
    terminal_decoder = codecs.getincrementaldecoder("utf-8")("replace")
    dirty = True
    while True:
        events = reader.read()
        before_count = _activity_limits(screen, state)[2] if events and navigator.scroll else 0
        for event in events:
            apply_event(state, event)
        if events and navigator.scroll:
            _, maximum, after_count = _activity_limits(screen, state)
            navigator.preserve_view(after_count - before_count, maximum)
        dirty = dirty or bool(events)
        try:
            raw = os.read(master, 4096)
            if not raw:
                return _child_exit_code(pid, True) or 0
            if state.console_capture:
                before_count = _activity_limits(screen, state)[2] if navigator.scroll else 0
                state.add_terminal_output(terminal_decoder.decode(raw))
                if navigator.scroll:
                    _, maximum, after_count = _activity_limits(screen, state)
                    navigator.preserve_view(after_count - before_count, maximum)
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
            _draw(screen, state, buffer, navigator)
            dirty = False
        key = _next_key(screen)
        if key == -1:
            if state.finished:
                result = _child_exit_code(pid, False)
                if result is not None:
                    return result
            continue
        dirty = True
        if state.privilege_waiting:
            # Native sudo reads from its PTY. Password keystrokes bypass the
            # editable draft, prompt history, activity, and backend commands.
            if key != curses.KEY_RESIZE:
                data = _privilege_key_bytes(key)
                if data:
                    os.write(master, data)
            continue
        if isinstance(key, str):
            buffer.insert(key)
            history.leave()
            continue
        if key == curses.KEY_RESIZE:
            continue
        if key in (curses.KEY_F1, 11):
            _help_overlay(screen)
            continue
        if key == 3:
            _send(master, "/stop")
            state.add_user_input("/stop")
            state.end_terminal_capture()
            navigator.latest()
            continue
        if key == 27:
            screen.timeout(80)
            nxt = _next_key(screen)
            screen.timeout(100)
            if nxt in (10, 13, curses.KEY_ENTER):
                buffer.insert("\n")
            else:
                buffer.clear()
                history.leave()
            continue
        if (key == 16 or (key == ord(":") and not buffer.text())) and not state.pending_action:
            selected = _palette_overlay(screen, master, buffer, state, commands)
            if selected == "settings_view":
                _settings_overlay(screen, master, reader, state)
                continue
            if selected and registry_is_local(selected):
                state.end_terminal_capture()
                state.add_user_input(selected)
                state.begin_terminal_capture()
                navigator.latest()
            continue
        page, maximum, _ = _activity_limits(screen, state)
        if key == curses.KEY_PPAGE:
            navigator.page_up(page, maximum)
        elif key == curses.KEY_NPAGE:
            navigator.page_down(page)
        elif key == curses.KEY_SR:
            navigator.line_up(maximum)
        elif key == curses.KEY_SF:
            navigator.line_down()
        elif key == curses.KEY_HOME:
            buffer.move_home() if buffer.text() else navigator.oldest(maximum)
        elif key == curses.KEY_END:
            buffer.move_end() if buffer.text() else navigator.latest()
        elif key == curses.KEY_LEFT:
            buffer.move_left()
        elif key == curses.KEY_RIGHT:
            buffer.move_right()
        elif key == curses.KEY_UP:
            if not buffer.move_up() and not state.pending_action:
                previous = history.previous(buffer.text())
                if previous is not None:
                    buffer.replace(previous)
        elif key == curses.KEY_DOWN:
            if not buffer.move_down() and not state.pending_action:
                next_prompt = history.next()
                if next_prompt is not None:
                    buffer.replace(next_prompt)
        elif key in (10, 13, curses.KEY_ENTER):
            submitted = buffer.clear()
            pending = bool(state.pending_action)
            if pending:
                submitted = submitted.splitlines()[0] if submitted.splitlines() else ""
            if not pending and submitted.strip() == "settings":
                _settings_overlay(screen, master, reader, state)
                navigator.latest()
                continue
            state.end_terminal_capture()
            local = not pending and registry_is_local(submitted)
            if not local and not pending:
                history.add(submitted)
            if submitted:
                state.add_user_input(submitted)
            if local:
                state.begin_terminal_capture()
            _send(master, submitted)
            navigator.latest()
        elif key == 15:
            buffer.insert("\n")
            history.leave()
        elif key == 7:
            state.collapse_output = not state.collapse_output
        elif key in (1,):
            buffer.move_home()
        elif key in (5,):
            buffer.move_end()
        elif key in (12, 21):
            buffer.clear()
            history.leave()
        elif key == 23:
            buffer.delete_word_left()
            history.leave()
        elif key == curses.KEY_DC:
            buffer.delete()
            history.leave()
        elif key in (curses.KEY_BACKSPACE, 127, 8):
            buffer.backspace()
            history.leave()
        elif key == 9:
            buffer.insert("\t")
            history.leave()
        elif 0 <= key <= 255:
            buffer.insert(chr(key))
            history.leave()



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
