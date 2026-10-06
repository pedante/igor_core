"""Small curses frontend for the structured Igor AI event stream.

This module is intentionally a frontend boundary.  It never classifies or
executes actions: input is written to the backend PTY and all visible state is
derived from the ordered JSONL event stream.  The pure state helpers make the
renderer usable in tests and by a future frontend without importing curses.
"""

from __future__ import annotations

import codecs
import copy
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
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

_CORE_LIB = Path(__file__).resolve().parents[1] / "lib"
if str(_CORE_LIB) not in sys.path:
    sys.path.insert(0, str(_CORE_LIB))
from interaction import (
    FocusModel,
    Property,
    display_text,
    parse_control_input,
    parse_property,
    property_text,
    propose_property,
    render_properties,
    render_structured,
)
from operator_surface import children as operator_children

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BACKEND = ("bash", str(REPO_ROOT / "igor.sh"), "--ai-tui-backend")
_ANSI = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))")
EVENT_TYPES = frozenset(
    {
        "session_started", "model_status", "assistant_message", "action_proposed",
        "approval_waiting", "explanation", "action_started", "action_output",
        "action_result", "action_skipped", "action_declined", "action_stopped",
        "privilege_waiting", "privilege_result", "continuation", "warning", "error",
        "mode_changed", "settings_snapshot", "operator_snapshot", "operator_candidates",
        "session_finished", "context_routing",
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
    duration_ms: int | None = None
    timestamp: str = ""
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
    show_timestamps: bool = False
    command_state: str = "ready"
    backend_ready: bool = False
    settings_snapshot: dict[str, Any] | None = None
    settings_sources: dict[str, str] = field(default_factory=dict)
    operator_snapshot: dict[str, Any] | None = None
    operator_candidates: dict[str, Any] | None = None
    session_id: str = ""
    role: str = ""
    context_routing: dict[str, Any] | None = None

    def accept(self, event: dict[str, Any]) -> bool:
        """Apply one event if it is valid and newer than the current stream."""
        if not isinstance(event, dict):
            return False
        kind = event.get("event_type")
        sequence = event.get("sequence", 0)
        # The backend stream uses strictly positive integer sequence numbers.
        # Reject malformed values at the projection boundary so a forged or
        # truncated frontend record cannot move the rendered state backwards
        # or make the first event appear authoritative.
        if (not isinstance(kind, str) or kind not in EVENT_TYPES or not isinstance(sequence, int)
                or isinstance(sequence, bool) or sequence <= 0):
            return False
        if sequence <= self.sequence:
            return False
        if kind not in {"settings_snapshot", "operator_snapshot", "operator_candidates"}:
            self.cancel_terminal_capture()
        self.sequence = sequence
        if kind == "context_routing":
            decision = event.get("decision")
            if isinstance(decision, dict):
                self.context_routing = copy.deepcopy(decision)
                self.role = str(decision.get("routing", {}).get("selected_role") or "unavailable")
                self.provider = str(decision.get("routing", {}).get("provider") or self.provider)
                self.model = str(decision.get("routing", {}).get("model") or self.model)
            return True
        if kind == "operator_snapshot":
            snapshot = event.get("surface")
            if isinstance(snapshot, dict):
                self.operator_snapshot = copy.deepcopy(snapshot)
            return True
        if kind == "operator_candidates":
            result = event.get("result")
            capability_id = event.get("capability_id")
            input_name = event.get("input_name")
            provider = event.get("provider")
            if (isinstance(result, dict) and isinstance(capability_id, str) and
                    isinstance(input_name, str) and isinstance(provider, str)):
                self.operator_candidates = {
                    "capability_id": capability_id,
                    "provider": provider,
                    "input_name": input_name,
                    "result": copy.deepcopy(result),
                }
            return True
        self.mode = str(event.get("mode") or self.mode)
        self.provider = str(event.get("provider") or self.provider)
        self.model = str(event.get("model") or self.model)
        for key in ("session_id", "role"):
            if isinstance(event.get(key), str):
                setattr(self, key, event[key])
        event_status = str(event.get("status") or "")
        if kind == "model_status":
            if event_status == "input_ready":
                self.backend_ready = True
            elif event_status in {
                "request_started", "response_received", "validating_provider", "preparing_context"
            }:
                self.backend_ready = False
        if kind == "session_finished":
            self.backend_ready = False
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
            sources = event.get("sources")
            if isinstance(snapshot, dict):
                self.settings_snapshot = copy.deepcopy(snapshot)
                self.mode = str(snapshot.get("mode") or self.mode)
                self.provider = str(snapshot.get("provider") or self.provider)
                self.model = str(snapshot.get("model") or self.model)
            self.settings_sources = ({
                str(key): str(value)
                for key, value in sources.items()
                if isinstance(key, str) and isinstance(value, str)
            } if isinstance(sources, dict) else {})
            return True
        if kind == "approval_waiting":
            self.pending_action = dict(event)
        elif kind == "privilege_waiting":
            self.privilege_waiting = dict(event)
        elif (kind in {"privilege_result", "action_result", "action_stopped"}
              and self.privilege_waiting):
            waiting_id = str(self.privilege_waiting.get("operation_id") or "")
            event_id = str(event.get("operation_id") or "")
            if waiting_id and waiting_id == event_id:
                self.privilege_waiting = None
        if (kind in {"action_started", "action_output", "action_result",
                     "action_skipped", "action_declined", "action_stopped"}
                and kind != "action_output" and self.pending_action):
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
            duration_ms=event.get("duration_ms") if isinstance(event.get("duration_ms"), int) else None,
            timestamp=str(event.get("timestamp") or ""),
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
        self.console_capture = Activity("terminal", "", timestamp=_local_timestamp())
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
            self.activity.append(Activity("user", text, timestamp=_local_timestamp()))
            if len(self.activity) > 2000:
                del self.activity[:-2000]

    def add_operator_input(self, text: str) -> None:
        if text:
            label = text.removeprefix("invoke ").strip()
            self.activity.append(Activity("operator", label or text, timestamp=_local_timestamp()))
            if len(self.activity) > 2000:
                del self.activity[:-2000]


def apply_event(state: EventState, event: dict[str, Any]) -> bool:
    """Testable event application entry point."""
    return state.accept(event)


def _local_timestamp() -> str:
    return datetime.now().astimezone().isoformat()


def _display_timestamp(value: str) -> str:
    if not value:
        return ""
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is not None:
            parsed = parsed.astimezone()
        return parsed.strftime("%H:%M:%S.%f")[:-3]
    except ValueError:
        return ""


def _format_duration(duration_ms: int | None) -> str:
    if duration_ms is None:
        return ""
    if duration_ms < 1000:
        return f"{duration_ms} ms"
    return f"{duration_ms / 1000:.2f} s"


_TOOL_ENVELOPE = re.compile(r"^TOOL:[^ \r\n]+ EXIT:\d+(?:\\n|\n)OUTPUT:(?:\\n|\n)?")


def _display_result_output(value: Any) -> str:
    """Remove the provider transport envelope from a locally rendered result."""
    text = str(value or "")
    match = _TOOL_ENVELOPE.match(text)
    return text[match.end():] if match else text


def _structured_action_output(text: str, label: str) -> str | None:
    """Render JSON capability output as bounded operator data, not opaque prose."""
    raw = _display_result_output(text).strip()
    if not raw or raw[0] not in "[{":
        return None
    try:
        decoded = json.loads(raw)
    except (TypeError, ValueError):
        return None
    if not isinstance(decoded, (dict, list)):
        return None

    payload: Any = decoded
    if isinstance(decoded, dict) and "result" in decoded and any(
            key in decoded for key in ("capability_id", "operation_id", "execution_status", "outcome")):
        payload = decoded.get("result")
        if payload is None:
            payload = {
                key: decoded[key]
                for key in ("execution_status", "outcome", "output_status")
                if key in decoded
            }
    return "\n".join(render_structured(
        payload,
        root_label=label,
        max_rows=200,
        max_depth=8,
    ))


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
        "operator": "Operator",
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
    if item.event_type == "action_output" and item.duration_ms is not None:
        prefix += f" ({_format_duration(item.duration_ms)})"
    if item.event_type == "action_output":
        structured = _structured_action_output(item.text, prefix)
        if structured is not None:
            return structured
    if item.event_type == "terminal":
        return _clean_terminal_output(item.text)
    if item.event_type == "action_result":
        status = item.status or (item.result or {}).get("execution_status") or "complete"
        exit_code = (item.result or {}).get("exit_code")
        suffix = f" (exit {exit_code})" if exit_code is not None else ""
        output = _display_result_output(
            (item.result or {}).get("combined_output") or (item.result or {}).get("output"))
        if item.show_result_output and output:
            return f"Result: {status}{suffix}\n{output}"
        return f"Result: {status}{suffix}"
    if not item.text and item.result:
        result_status = item.result.get("execution_status") or item.result.get("status") or "complete"
        result_output = _display_result_output(
            item.result.get("combined_output") or item.result.get("output") or "")
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
    if item.event_type == "operator":
        return "action"
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
        if state.show_timestamps:
            stamp = _display_timestamp(item.timestamp)
            if stamp:
                lines = text.split("\n")
                lines[0] = f"[{stamp}] {lines[0]}"
                text = "\n".join(lines)
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


def settings_properties(
    snapshot: dict[str, Any],
    sources: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    """Adapt backend settings without inventing authority or missing values."""
    schemas = []
    for key, label, kind, options in SETTINGS_FIELDS:
        schema: dict[str, Any] = {
            "id": key,
            "label": label,
            "editable": True,
            "source": (sources or {}).get(key, "AI backend settings snapshot"),
        }
        schema["type"] = {"choice": "enum", "toggle": "boolean"}.get(kind, "text")
        if options:
            schema["options"] = list(options)
        if key == "temperature":
            schema.update(type="number", minimum=0, maximum=2)
        elif key == "max_tokens":
            schema.update(type="integer", minimum=1)
        if key in snapshot:
            value = snapshot[key]
            try:
                if schema["type"] == "boolean":
                    if str(value).lower() not in {"true", "false", "on", "off", "1", "0"}:
                        raise ValueError("invalid boolean snapshot")
                    value = str(value).lower() in {"true", "on", "1"}
                elif schema["type"] in {"integer", "number"}:
                    value = parse_control_input(parse_property(schema), str(value))
                elif key in {"mode", "provider"} and isinstance(value, str):
                    value = value.lower()
                schema["value"] = value
                parse_property(schema)
            except (ValueError, TypeError, OverflowError):
                schema.pop("value", None)
        schemas.append(schema)
    return schemas


def settings_proposal_command(proposal: dict[str, Any], snapshot: dict[str, Any]) -> str:
    """The only edit adapter: whitelist existing session commands, revalidate data."""
    if not isinstance(proposal, dict) or proposal.keys() != {"property_id", "value"}:
        raise ValueError("invalid property proposal")
    schema = next((row for row in settings_properties(snapshot)
                   if row["id"] == proposal["property_id"]), None)
    if schema is None:
        raise ValueError("unknown setting")
    value = propose_property(parse_property(schema), proposal["value"])["value"]
    text = ("on" if value else "off") if type(value) is bool else str(value)
    return settings_change_command(schema["id"], text)


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


class HistoryInspection:
    """On-demand async read of the existing durable history inspection CLI.

    No module loading, verifier/recovery, config parsing or shell-selected
    commands. Results remain disposable display data, never a history store.
    """

    label = "Operational History"
    command = ("--history", "recent", "20")

    def __init__(self) -> None:
        self.process: subprocess.Popen | None = None
        self.data: Any = None
        self.status = f"Enter to load {self.label}"
        self.started = 0.0
        self.output = bytearray()

    def start(self) -> None:
        if self.process is not None:
            return
        self.output.clear()
        try:
            self.process = subprocess.Popen(
                ("bash", str(REPO_ROOT / "igor.sh"), *self.command),
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                close_fds=True, start_new_session=True)
            os.set_blocking(self.process.stdout.fileno(), False)
        except OSError:
            self.close()
            self.status = f"{self.label} unavailable"
            return
        self.started = time.monotonic()
        self.status = f"Loading {self.label}…"

    def poll(self) -> bool:
        process = self.process
        if process is None:
            return False
        try:
            while True:
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    break
                self.output.extend(chunk)
                if len(self.output) > 1_048_576:
                    self.close()
                    self.status = f"{self.label} display exceeds bound"
                    return True
        except BlockingIOError:
            pass
        except OSError:
            self.close()
            self.status = f"{self.label} unavailable"
            return True
        if process.poll() is None:
            if time.monotonic() - self.started <= 5:
                return False
            self.close()
            self.status = f"{self.label} inspection timed out"
            return True
        code = process.returncode
        self.close()
        try:
            result = json.loads(self.output.decode("utf-8"))
            if code != 0 or not isinstance(result, (list, dict)):
                raise ValueError("unavailable")
            self.data = result
            self.status = "Read-only · Enter refresh"
        except (ValueError, UnicodeDecodeError):
            self.status = f"{self.label} unavailable/invalid response"
        return True

    def close(self) -> None:
        if self.process is not None:
            if self.process.poll() is None:
                try:
                    os.killpg(self.process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    self.process.wait(timeout=0.2)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(self.process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    self.process.wait()
            if self.process.stdout is not None:
                self.process.stdout.close()
            self.process = None
            if self.status.startswith("Loading"):
                self.status = "Inspection cancelled · Enter refresh"


class InvestigationInspection(HistoryInspection):
    """Read-only investigation records through the owning CLI, never its files."""

    label = "Investigations"
    command = ("--investigations", "list")


def panel_sections(state: EventState, inspection: HistoryInspection,
                   investigations: InvestigationInspection | None = None) -> list[dict[str, Any]]:
    """Reusable section data, projected from backend-owned interfaces only."""
    sections = [
        {"id": "session", "label": "Session", "source": "frontend event stream",
         "data": {"session_id": state.session_id or "unavailable", "mode": state.mode,
                  "status": state.session_status, "sequence": state.sequence,
                  "pending_approval": state.pending_action,
                  "administrator_authentication": bool(state.privilege_waiting)}},
        {"id": "ai", "label": "AI (read-only)", "source": "frontend event stream",
         "data": {"role": state.role or "unavailable (not reported)",
                  "provider": state.provider or "unavailable",
                  "model": state.model or "unavailable",
                  "routing_authority": "backend"}},
        {"id": "properties", "label": "Settings", "source": "backend settings_snapshot",
         "properties": settings_properties(
             state.settings_snapshot or {}, state.settings_sources),
         "hint": "Enter opens existing backend settings; ownership is shown per field"},
        {"id": "history", "label": "Operational History", "source": "--history recent 20",
         "data": inspection.data, "hint": inspection.status},
    ]
    if investigations is not None:
        sections.append({"id": "investigations", "label": "Investigations",
                         "source": "--investigations list", "data": investigations.data,
                         "hint": investigations.status})
    sections.append({"id": "context_routing", "label": "Context / Routing",
                     "source": "backend context_routing decision",
                     "data": state.context_routing or {"availability": "not reported"},
                     "hint": "Read-only operational provenance"})
    result = next((item.result for item in reversed(state.activity) if item.result), None)
    if result is not None:
        sections.append({"id": "result", "label": "Latest result", "data": result,
                         "source": "frontend action_result"})
    return sections


def panel_rows(section: dict[str, Any]) -> list[str]:
    if not isinstance(section, dict):
        return ["Invalid inspection section"]
    rows = ["Source: " + display_text(section.get("source", "unavailable"))]
    rows.extend(render_properties(section["properties"]) if "properties" in section
                else render_structured(section.get("data")))
    if section.get("hint"):
        rows.append(display_text(section["hint"]))
    return rows


def _surface_width(width: int, focus: FocusModel | None = None) -> tuple[int, int]:
    if focus is None or not focus.panel_open or width < 20:
        return max(1, width - 1), 0
    panel_width = min(38, max(10, width // 3))
    return max(1, width - panel_width - 2), panel_width


def navigation_key(key: int, focus: FocusModel, navigator: ActivityNavigator,
                   page: int, maximum: int) -> bool:
    """Presentation-only key dispatch; never edits the composer or sends input."""
    if key == 9:
        focus.cycle()
    elif key == curses.KEY_BTAB:
        focus.cycle(reverse=True)
    elif key == 2:  # Ctrl+B
        focus.toggle_panel()
    elif key == 6:  # Ctrl+F: return to latest, regardless of composer contents
        navigator.latest()
    elif key == curses.KEY_PPAGE and focus.region != "panel":
        navigator.page_up(page, maximum)
    elif key == curses.KEY_NPAGE and focus.region != "panel":
        navigator.page_down(page)
    elif key == curses.KEY_SR:
        navigator.line_up(maximum)
    elif key == curses.KEY_SF:
        navigator.line_down()
    elif focus.region == "output":
        if key == curses.KEY_UP:
            navigator.line_up(maximum)
        elif key == curses.KEY_DOWN:
            navigator.line_down()
        elif key == curses.KEY_HOME:
            navigator.oldest(maximum)
        elif key == curses.KEY_END:
            navigator.latest()
        else:
            return False
    else:
        return False
    return True


def mouse_navigation(position: tuple[int, int, int, int, int], focus: FocusModel,
                     navigator: ActivityNavigator, height: int, width: int,
                     page: int, maximum: int) -> bool:
    """Wheel only scrolls output under the pointer; clicks select a region."""
    _device, x, y, _z, buttons = position
    output_width, panel_width = _surface_width(width, focus)
    in_output = 1 <= y <= page and 0 <= x < output_width
    wheel_up = getattr(curses, "BUTTON4_PRESSED", 0)
    wheel_down = getattr(curses, "BUTTON5_PRESSED", 0)
    if buttons & (wheel_up | wheel_down):
        if not in_output:
            return False
        if buttons & wheel_up:
            navigator.page_up(3, maximum)
        else:
            navigator.page_down(3)
        return True
    click = getattr(curses, "BUTTON1_CLICKED", 0) | getattr(curses, "BUTTON1_PRESSED", 0)
    if buttons & click:
        if in_output:
            focus.set_focus("output")
        elif panel_width and x > output_width and 1 <= y <= page:
            focus.set_focus("panel")
        elif height - min(3, max(1, height - 3)) <= y < height:
            focus.set_focus("input")
        return True
    return False


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


def _activity_limits(screen: Any, state: EventState,
                     focus: FocusModel | None = None) -> tuple[int, int, int]:
    height, width = screen.getmaxyx()
    input_rows = min(3, max(1, height - 3))
    activity_height = max(0, height - input_rows - 3)
    output_width, _ = _surface_width(width, focus)
    line_count = len(_activity_rows(state, output_width))
    return activity_height, max(0, line_count - activity_height), line_count


def _draw_panel(screen: Any, focus: FocusModel, sections: list[dict[str, Any]],
                output_width: int, panel_width: int, page: int) -> None:
    left = output_width + 1
    try:
        for row in range(1, page + 1):
            screen.addnstr(row, output_width, "│", 1)
        screen.addnstr(1, left, "Control · " + focus.region.upper(), panel_width,
                       curses.A_BOLD)
        focus.panel_selection = min(focus.panel_selection, max(0, len(sections) - 1))
        for index, section in enumerate(sections):
            if index + 2 > page:
                break
            selected = index == focus.panel_selection
            screen.addnstr(index + 2, left, ("> " if selected else "  ") + section["label"],
                           panel_width, curses.A_REVERSE if selected else curses.A_NORMAL)
        first_row = len(sections) + 3
        available = max(0, page - first_row + 1)
        section = sections[focus.panel_selection]
        rows = [wrapped for line in panel_rows(section)
                for wrapped in _wrap_line(line, max(1, panel_width))]
        focus.panel_scroll = min(focus.panel_scroll, max(0, len(rows) - available))
        for row, line in enumerate(rows[focus.panel_scroll:focus.panel_scroll + available], first_row):
            screen.addnstr(row, left, line, panel_width)
    except curses.error:
        pass


def _session_status_label(state: EventState) -> str:
    if state.privilege_waiting:
        return "AUTH"
    if state.pending_action:
        return "APPROVAL"
    if state.backend_ready:
        return "READY"
    return {
        "validating_provider": "CONNECTING",
        "preparing_context": "PREPARING",
        "request_started": "THINKING",
        "response_received": "PROCESSING",
        "input_ready": "READY",
    }.get(state.session_status, state.session_status)


def _draw(screen: Any, state: EventState, buffer: InputBuffer,
          scroll: int | ActivityNavigator, focus: FocusModel | None = None,
          sections: list[dict[str, Any]] | None = None) -> None:
    screen.erase()
    height, width = screen.getmaxyx()
    if height < 1 or width < 1:
        return
    scroll_offset = scroll.scroll if isinstance(scroll, ActivityNavigator) else scroll
    activity_height, maximum_scroll, _ = _activity_limits(screen, state, focus)
    scroll_offset = min(max(0, scroll_offset), maximum_scroll)
    if isinstance(scroll, ActivityNavigator):
        scroll.scroll = scroll_offset
    header = f"Igor  {state.mode.upper()}  {_session_status_label(state)}"
    header += f"  ↑{scroll_offset} Ctrl+F=live" if scroll_offset else "  LIVE"
    if focus is not None:
        header += "  Focus:" + focus.region.upper()
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
    viewport_width, panel_width = _surface_width(width, focus)
    rows = _activity_rows(state, viewport_width)
    theme = color_theme(screen)
    start = max(0, len(rows) - activity_height - scroll_offset)
    visible_rows = rows[start : start + activity_height]
    for row, (line, role) in enumerate(visible_rows, 1):
        try:
            screen.addnstr(row, 0, line, viewport_width, theme.get(role, curses.A_NORMAL))
        except curses.error:
            pass
    if panel_width and focus is not None and sections:
        _draw_panel(screen, focus, sections, viewport_width, panel_width, activity_height)
    try:
        screen.hline(separator, 0, curses.ACS_HLINE, width)
        hint = "Tab focus  Ctrl+B panel  Ctrl+F live  Enter send  F1 keys"
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
        elif focus is not None and focus.region == "output":
            hint = "Output: ↑↓/PageUp/PageDown scroll  Home oldest  End latest  Tab focus"
        elif focus is not None and focus.region == "panel":
            hint = "Control: ↑↓ select  PageUp/PageDown inspect  Enter open/refresh  Esc back"
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
        curses.curs_set(1 if focus is None or focus.region == "input" else 0)
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
                    if not state.backend_ready:
                        notice = "Backend busy — wait for READY or press Ctrl+C to stop"
                        continue
                    _send(master, entry["name"])
                    state.backend_ready = False
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


def _operator_alias_target(snapshot: dict[str, Any] | None, alias: str) -> str | None:
    """Resolve one backend-projected root alias without inventing identities."""
    if not isinstance(snapshot, dict):
        return None
    aliases = snapshot.get("aliases")
    if not isinstance(aliases, dict):
        return None
    target = aliases.get(alias)
    if (not isinstance(target, str) or
            re.fullmatch(r"[a-z][a-z0-9_-]*", alias) is None or
            re.fullmatch(r"[a-z][a-z0-9_-]*", target) is None):
        return None
    return target


def _operator_display_prefix(prefix: str, active_alias: tuple[str, str] | None) -> str:
    """Render a chosen presentation alias while retaining the canonical prefix."""
    if active_alias is None:
        return prefix
    alias, target = active_alias
    if prefix == target:
        return alias
    if prefix.startswith(target + "."):
        return alias + prefix[len(target):]
    return prefix


def _operator_alias_hint(snapshot: dict[str, Any] | None) -> str:
    if not isinstance(snapshot, dict) or not isinstance(snapshot.get("aliases"), dict):
        return ""
    pairs = []
    for alias, target in sorted(snapshot["aliases"].items()):
        if (_operator_alias_target(snapshot, alias) == target and
                isinstance(target, str)):
            pairs.append(f":{alias} → :{target}")
    return "Aliases " + ", ".join(pairs) if pairs else ""


def _operator_invoke_command(entry: dict[str, Any]) -> tuple[str, bool]:
    """Return canonical invoke command and whether operator input is required."""
    target = str(entry.get("target_id") or "")
    if not target:
        raise ValueError("operator entry has no target")
    provider = str(entry.get("provider") or "")
    if entry.get("provider_required") and provider:
        target += "@" + provider
    inputs = entry.get("inputs") if isinstance(entry.get("inputs"), dict) else {}
    required = inputs.get("required") if isinstance(inputs.get("required"), list) else []
    return "invoke " + target, bool(required)


def _operator_required_inputs(entry: dict[str, Any]) -> list[str]:
    """Return required capability inputs in declared order."""
    inputs = entry.get("inputs") if isinstance(entry.get("inputs"), dict) else {}
    required = inputs.get("required") if isinstance(inputs.get("required"), list) else []
    return [name for name in required if isinstance(name, str)]


def _operator_selector_input(entry: dict[str, Any]) -> str | None:
    """Compatibility helper for the single-input selector case."""
    required = _operator_required_inputs(entry)
    inputs = entry.get("inputs") if isinstance(entry.get("inputs"), dict) else {}
    selectors = inputs.get("selectors") if isinstance(inputs.get("selectors"), dict) else {}
    if len(required) != 1:
        return None
    return required[0] if isinstance(selectors.get(required[0]), dict) else None


def _operator_input_spec(entry: dict[str, Any], input_name: str) -> dict[str, Any]:
    inputs = entry.get("inputs") if isinstance(entry.get("inputs"), dict) else {}
    properties = inputs.get("properties") if isinstance(inputs.get("properties"), dict) else {}
    spec = properties.get(input_name)
    return spec if isinstance(spec, dict) else {}


def _operator_input_selector(entry: dict[str, Any], input_name: str) -> dict[str, Any] | None:
    inputs = entry.get("inputs") if isinstance(entry.get("inputs"), dict) else {}
    selectors = inputs.get("selectors") if isinstance(inputs.get("selectors"), dict) else {}
    selector = selectors.get(input_name)
    return selector if isinstance(selector, dict) else None


def _operator_inputs_collectable(entry: dict[str, Any]) -> bool:
    """Keep the generic form away from secret or non-text typed inputs."""
    required = _operator_required_inputs(entry)
    if not required:
        return False
    for input_name in required:
        if _operator_input_selector(entry, input_name):
            continue
        if _operator_input_spec(entry, input_name).get("type") not in {"string", "path", "object_id"}:
            return False
    return True


def _operator_candidate_request(
    entry: dict[str, Any], input_name: str, query: str | None = None
) -> str:
    target = str(entry.get("target_id") or "")
    if not target:
        raise ValueError("operator entry has no target")
    provider = str(entry.get("provider") or "")
    if entry.get("provider_required") and provider:
        target += "@" + provider
    request = f"candidates {target} {input_name}"
    if query is not None:
        request += " " + json.dumps(query)
    return request


def _operator_candidate_matches(
    record: dict[str, Any] | None,
    entry: dict[str, Any],
    input_name: str,
    query: str | None = None,
) -> bool:
    if not isinstance(record, dict):
        return False
    if record.get("capability_id") != entry.get("target_id") or record.get("input_name") != input_name:
        return False
    if entry.get("provider_required") and record.get("provider") != entry.get("provider"):
        return False
    return query is None or record.get("query", "") == query


def _operator_candidate_overlay(
    screen: Any,
    master: int,
    reader: EventReader,
    state: EventState,
    buffer: InputBuffer,
    entry: dict[str, Any],
    input_name: str,
    *,
    invoke_on_select: bool = True,
) -> tuple[str, str | None]:
    """Choose one ephemeral candidate without acquiring execution authority."""
    selector = _operator_input_selector(entry, input_name)
    path_selector = (
        isinstance(selector, dict)
        and selector.get("resource_kind") in {"path", "mutable_path"}
    )
    query, selected = "", 0
    requested_query: str | None = None
    try:
        request = _operator_candidate_request(
            entry, input_name, query if path_selector else None
        )
    except ValueError:
        return "back", None
    state.operator_candidates = None
    _send(master, request)
    state.backend_ready = False
    requested_query = query if path_selector else None
    notice = "Loading candidates…"
    screen.timeout(100)
    try:
        while True:
            for event in reader.read():
                apply_event(state, event)
                if event.get("event_type") in {"warning", "error"}:
                    notice = str(event.get("display") or "Candidate selection unavailable")
            if path_selector and state.backend_ready and requested_query != query:
                state.operator_candidates = None
                _send(master, _operator_candidate_request(entry, input_name, query))
                state.backend_ready = False
                requested_query = query
                notice = "Loading path candidates…"
            record = state.operator_candidates
            result = record.get("result") if _operator_candidate_matches(
                record, entry, input_name, query if path_selector else None
            ) else None
            rows = result.get("candidates") if isinstance(result, dict) else []
            rows = [row for row in rows if isinstance(row, dict) and isinstance(row.get("value"), str)]
            needle = query.casefold()
            if needle:
                rows = [
                    row for row in rows
                    if needle in str(row.get("value", "")).casefold()
                    or needle in str(row.get("label", "")).casefold()
                    or needle in str(row.get("detail", "")).casefold()
                ]
            if isinstance(result, dict):
                state_name = str(result.get("state") or "")
                if state_name in {"unavailable", "error"}:
                    notice = str(result.get("reason") or "Candidate source unavailable")
                elif state_name == "empty":
                    notice = "No candidates are currently available"
                elif state_name == "ready":
                    notice = ""
            if selected >= len(rows):
                selected = max(0, len(rows) - 1)

            height, width = screen.getmaxyx()
            screen.erase()
            target = str(entry.get("target_id") or "")
            try:
                screen.addnstr(
                    0, 0, f"Select {input_name}  {target}", max(1, width - 1), curses.A_BOLD
                )
                source = result.get("source") if isinstance(result, dict) else None
                source_text = ""
                if isinstance(source, dict):
                    source_text = f"source: {source.get('id', source.get('kind', 'unknown'))}"
                screen.addnstr(
                    1, 0, f"filter: {query}  {source_text}".rstrip(),
                    max(1, width - 1), curses.A_DIM
                )
                visible = max(1, height - 4)
                first = max(0, selected - visible + 1)
                for row_number, candidate in enumerate(rows[first:first + visible], 2):
                    index = first + row_number - 2
                    marker = ">" if index == selected else " "
                    label = str(candidate.get("label") or candidate["value"])
                    detail = str(candidate.get("detail") or "")
                    line = f"{marker} {label}"
                    if detail:
                        line += f"  {detail}"
                    screen.addnstr(
                        row_number, 0, line, max(1, width - 1),
                        curses.A_REVERSE if index == selected else 0,
                    )
                if path_selector:
                    footer = notice or "Type path · ↑↓ choose · Tab/→ descend · Enter select · Esc back"
                else:
                    footer = notice or "Type filter · ↑↓ choose · Enter select · Tab manual · Esc back"
                screen.addnstr(max(0, height - 1), 0, footer, max(1, width - 1), curses.A_DIM)
            except curses.error:
                pass
            screen.refresh()

            key = _next_key(screen)
            if key in (27, 3):
                if key == 3:
                    _send(master, "/stop")
                return "back", None
            if key == 9:
                if path_selector and rows:
                    candidate = rows[selected]
                    label = str(candidate.get("label") or "")
                    if label.endswith("/"):
                        query = label
                        selected = 0
                        continue
                    if not state.backend_ready:
                        notice = "Backend busy — path selection must wait for READY"
                        continue
                    value = candidate["value"]
                    if not invoke_on_select:
                        return "selected", value
                    command, _ = _operator_invoke_command(entry)
                    command += " " + json.dumps(
                        {input_name: value}, sort_keys=True, separators=(",", ":")
                    )
                    _send(master, command)
                    state.backend_ready = False
                    return "invoke", command
                if not invoke_on_select:
                    return "manual", None
                command, _ = _operator_invoke_command(entry)
                buffer.replace(command + " ")
                return "draft", None
            if key == curses.KEY_RIGHT and path_selector and rows:
                label = str(rows[selected].get("label") or "")
                if label.endswith("/"):
                    query = label
                    selected = 0
                continue
            if key == curses.KEY_UP:
                selected = max(0, selected - 1)
                continue
            if key == curses.KEY_DOWN:
                selected = min(max(0, len(rows) - 1), selected + 1)
                continue
            if key in (curses.KEY_BACKSPACE, 127, 8):
                query = query[:-1]
                selected = 0
                continue
            if key in (10, 13, curses.KEY_ENTER) and rows:
                if not state.backend_ready:
                    notice = "Backend busy — candidate is selected but invocation must wait for READY"
                    continue
                value = rows[selected]["value"]
                if not invoke_on_select:
                    return "selected", value
                command, _ = _operator_invoke_command(entry)
                command += " " + json.dumps(
                    {input_name: value}, sort_keys=True, separators=(",", ":")
                )
                _send(master, command)
                state.backend_ready = False
                return "invoke", command
            if isinstance(key, str) and key not in "\n\r":
                query += key
                selected = 0
            elif isinstance(key, int) and 32 <= key <= 126:
                query += chr(key)
                selected = 0
    finally:
        screen.timeout(100)


def _operator_text_input_overlay(
    screen: Any,
    entry: dict[str, Any],
    input_name: str,
) -> tuple[str, str | None]:
    """Collect one bounded textual input; canonical validation still happens in Core."""
    value = ""
    screen.timeout(100)
    try:
        while True:
            height, width = screen.getmaxyx()
            screen.erase()
            target = str(entry.get("target_id") or "")
            spec = _operator_input_spec(entry, input_name)
            try:
                screen.addnstr(
                    0, 0, f"Enter {input_name}  {target}", max(1, width - 1), curses.A_BOLD
                )
                shown = value or "…"
                screen.addnstr(2, 0, shown, max(1, width - 1))
                screen.addnstr(
                    max(0, height - 1), 0,
                    "Type value · Enter accept · Esc back",
                    max(1, width - 1), curses.A_DIM,
                )
            except curses.error:
                pass
            screen.refresh()
            key = _next_key(screen)
            if key in (27, 3):
                return "back", None
            if key in (curses.KEY_BACKSPACE, 127, 8):
                value = value[:-1]
                continue
            if key in (10, 13, curses.KEY_ENTER):
                if not value:
                    continue
                if spec.get("type") == "path" and spec.get("root") == "/":
                    value = value.lstrip("/")
                return "selected", value
            if isinstance(key, str) and key not in "\n\r" and ord(key) >= 32:
                if len(value) < int(spec.get("maxLength", 4096)):
                    value += key
            elif isinstance(key, int) and 32 <= key <= 126:
                if len(value) < int(spec.get("maxLength", 4096)):
                    value += chr(key)
    finally:
        screen.timeout(100)


def _operator_required_input_overlay(
    screen: Any,
    master: int,
    reader: EventReader,
    state: EventState,
    buffer: InputBuffer,
    entry: dict[str, Any],
) -> tuple[str, str | None]:
    """Collect multiple required inputs without moving domain authority into the TUI."""
    values: dict[str, str] = {}
    for input_name in _operator_required_inputs(entry):
        selector = _operator_input_selector(entry, input_name)
        if selector is not None:
            outcome, value = _operator_candidate_overlay(
                screen, master, reader, state, buffer, entry, input_name,
                invoke_on_select=False,
            )
            if outcome == "back":
                return "back", None
            if outcome == "manual":
                outcome, value = _operator_text_input_overlay(screen, entry, input_name)
            if outcome != "selected" or value is None:
                return outcome, value
        else:
            outcome, value = _operator_text_input_overlay(screen, entry, input_name)
            if outcome != "selected" or value is None:
                return outcome, value
        values[input_name] = value

    if not state.backend_ready:
        return "busy", None
    command, _ = _operator_invoke_command(entry)
    command += " " + json.dumps(values, sort_keys=True, separators=(",", ":"))
    _send(master, command)
    state.backend_ready = False
    return "invoke", command


def _operator_surface_summary(snapshot: dict[str, Any] | None) -> tuple[str, str]:
    """Return compact source counts and an actionable state message."""
    if not isinstance(snapshot, dict):
        return "Waiting for backend snapshot", ""
    sources = snapshot.get("sources") if isinstance(snapshot.get("sources"), dict) else {}
    parts = []
    failed = []
    missing = []
    for name in ("modules", "contributions", "capabilities", "configurations"):
        row = sources.get(name) if isinstance(sources.get(name), dict) else {}
        count = row.get("count")
        count = count if isinstance(count, int) and not isinstance(count, bool) and count >= 0 else 0
        status = str(row.get("status") or "unknown")
        parts.append(f"{name} {count}")
        if status == "error":
            failed.append(name)
        elif status == "missing":
            missing.append(name)
    entry_count = snapshot.get("entry_count")
    if not isinstance(entry_count, int) or isinstance(entry_count, bool) or entry_count < 0:
        entries = snapshot.get("entries")
        entry_count = len(entries) if isinstance(entries, list) else 0
    summary = f"{entry_count} entries · " + " · ".join(parts)
    state_name = str(snapshot.get("state") or ("empty" if entry_count == 0 else "ready"))
    if failed:
        return summary, "Projection failed for: " + ", ".join(failed) + " · Ctrl+R retry"
    if state_name == "empty":
        detail = (" No registry providers are loaded." if len(missing) == 4
                  else " The loaded registries contain no operator contracts.")
        return summary, "No operator contracts registered." + detail + " · Ctrl+R refresh"
    if missing:
        return summary, "Partial surface; unavailable sources: " + ", ".join(missing) + " · Ctrl+R refresh"
    return summary, ""


def _operator_overlay(screen: Any, master: int, reader: EventReader,
                      state: EventState, buffer: InputBuffer) -> str | None:
    """Browse contract-derived namespaces without owning execution."""
    if state.pending_action or state.privilege_waiting or state.finished:
        return None
    prefix, query, selected = "", "", 0
    active_alias: tuple[str, str] | None = None
    snapshot = state.operator_snapshot
    refreshing = False
    requested_at = None
    requested_once = False
    notice = "Operator Surface is loading…" if not isinstance(snapshot, dict) else ""
    if not isinstance(snapshot, dict) and state.backend_ready:
        refreshing = True
        requested_at = time.monotonic()
        requested_once = True
        _send(master, "surface snapshot")
        state.backend_ready = False
    screen.timeout(100)
    try:
        while True:
            for event in reader.read():
                apply_event(state, event)
                if event.get("event_type") == "operator_snapshot":
                    refreshing = False
                    requested_at = None
                    notice = ""
                elif event.get("event_type") in {"warning", "error"}:
                    display = str(event.get("display") or "Operator surface unavailable")
                    if refreshing and "operator surface" in display.casefold():
                        refreshing = False
                        requested_at = None
                        notice = (display + " · showing current snapshot"
                                  if isinstance(state.operator_snapshot, dict) else display)
                    else:
                        notice = display
            if state.pending_action or state.privilege_waiting or state.finished:
                return None
            if (state.operator_snapshot is None and state.backend_ready and
                    not refreshing and not requested_once):
                refreshing = True
                requested_at = time.monotonic()
                requested_once = True
                notice = "Operator Surface is loading…"
                _send(master, "surface snapshot")
                state.backend_ready = False
            try:
                os.read(master, 4096)
            except (BlockingIOError, OSError):
                pass

            snapshot = state.operator_snapshot
            if (active_alias is not None and
                    _operator_alias_target(snapshot, active_alias[0]) != active_alias[1]):
                active_alias = None
            nodes = operator_children(snapshot, prefix) if isinstance(snapshot, dict) else []
            alias_target = _operator_alias_target(snapshot, query) if not prefix else None
            needle = query.casefold()
            if needle:
                nodes = [
                    node for node in nodes
                    if needle in str(node.get("name", "")).casefold()
                    or (alias_target is not None and node.get("path") == alias_target)
                ]
            summary, surface_notice = _operator_surface_summary(snapshot)
            if snapshot is not None and not refreshing and not notice:
                notice = surface_notice
            elif (snapshot is None and refreshing and requested_at is not None and
                  time.monotonic() - requested_at >= 2.0 and
                  notice == "Operator Surface is loading…"):
                notice = "Operator Surface is still loading… · Esc close"
            if selected >= len(nodes):
                selected = max(0, len(nodes) - 1)

            height, width = screen.getmaxyx()
            screen.erase()
            display_prefix = _operator_display_prefix(prefix, active_alias)
            location = ":" + (display_prefix + "." if display_prefix else "") + query
            try:
                screen.addnstr(0, 0, f"Explore  {location}", max(1, width - 1), curses.A_BOLD)
                screen.addnstr(1, 0, summary, max(1, width - 1), curses.A_DIM)
                visible = max(1, height - 4)
                first = max(0, selected - visible + 1)
                for row, node in enumerate(nodes[first:first + visible], 2):
                    index = first + row - 2
                    marker = ">" if index == selected else " "
                    available = node.get("availability") == "active"
                    flag = " " if available else "×"
                    branch = " ›" if node.get("has_children") else ""
                    kind = "" if node.get("kind") == "namespace" else f" [{node.get('kind')}]"
                    desc = str(node.get("description") or "")
                    line = f"{marker}{flag} {node.get('name')}{branch}{kind}"
                    if desc:
                        line += f"  {desc}"
                    style = curses.A_REVERSE if index == selected else curses.A_DIM if not available else 0
                    screen.addnstr(row, 0, line, max(1, width - 1), style)
                footer = notice or "Type filter · . / Enter descend · Ctrl+R refresh · Backspace parent · Esc back"
                if not prefix and not query and not notice:
                    alias_hint = _operator_alias_hint(snapshot)
                    if alias_hint:
                        footer += " · " + alias_hint
                screen.addnstr(max(0, height - 1), 0, footer, max(1, width - 1), curses.A_DIM)
            except curses.error:
                pass
            screen.refresh()

            key = _next_key(screen)
            if key == 18:  # Ctrl+R: refresh without discarding the last good snapshot.
                if refreshing:
                    notice = ("Refresh already in progress… · showing current snapshot"
                              if isinstance(state.operator_snapshot, dict)
                              else "Operator Surface is still loading… · Esc close")
                    continue
                if not state.backend_ready:
                    notice = "Backend busy — refresh available when READY"
                    continue
                refreshing = True
                requested_at = time.monotonic()
                requested_once = True
                notice = ("Refreshing Operator Surface… · showing current snapshot"
                          if isinstance(state.operator_snapshot, dict)
                          else "Operator Surface is loading…")
                _send(master, "surface snapshot")
                state.backend_ready = False
                continue
            if key in (27, 3):
                if key == 3:
                    _send(master, "/stop")
                    return None
                if query:
                    query = ""
                    selected = 0
                    continue
                if prefix:
                    prefix = prefix.rpartition(".")[0]
                    if not prefix:
                        active_alias = None
                    selected = 0
                    continue
                return None
            if key == curses.KEY_UP:
                selected = max(0, selected - 1)
                continue
            if key == curses.KEY_DOWN:
                selected = min(max(0, len(nodes) - 1), selected + 1)
                continue
            if key in (curses.KEY_BACKSPACE, 127, 8):
                if query:
                    query = query[:-1]
                elif prefix:
                    prefix = prefix.rpartition(".")[0]
                    if not prefix:
                        active_alias = None
                selected = 0
                notice = ""
                continue

            exact = next((node for node in nodes
                          if str(node.get("name", "")).casefold() == query.casefold()), None)
            alias_node = next(
                (node for node in nodes if alias_target is not None
                 and node.get("path") == alias_target),
                None,
            )
            if key == ord(".") and alias_node and alias_node.get("has_children"):
                active_alias = (query, alias_target)
                prefix, query, selected, notice = str(alias_node["path"]), "", 0, ""
                continue
            if key == ord(".") and exact and exact.get("has_children"):
                prefix, query, selected, notice = str(exact["path"]), "", 0, ""
                continue

            if key in (10, 13, curses.KEY_ENTER) and nodes:
                node = nodes[selected]
                if node.get("has_children"):
                    if (not prefix and alias_target is not None and
                            node.get("path") == alias_target):
                        active_alias = (query, alias_target)
                    prefix, query, selected, notice = str(node["path"]), "", 0, ""
                    continue
                if not node.get("leaf"):
                    continue
                if node.get("availability") != "active":
                    notice = str((node.get("entry") or {}).get("unavailable_reason")
                                 or "This contribution is unavailable")
                    continue
                entry = node.get("entry") if isinstance(node.get("entry"), dict) else {}
                if entry.get("kind") == "capability":
                    try:
                        command, needs_input = _operator_invoke_command(entry)
                    except ValueError as error:
                        notice = str(error)
                        continue
                    if needs_input:
                        if _operator_inputs_collectable(entry):
                            if not state.backend_ready:
                                notice = "Backend busy — input selection available when READY"
                                continue
                            outcome, selected_command = _operator_required_input_overlay(
                                screen, master, reader, state, buffer, entry
                            )
                            if outcome == "back":
                                continue
                            if outcome == "invoke":
                                return selected_command
                            if outcome == "busy":
                                notice = "Backend busy — wait for READY or press Ctrl+C to stop current work"
                                continue
                            return None
                        buffer.replace(command + " ")
                        return None
                    if not state.backend_ready:
                        notice = "Backend busy — wait for READY or press Ctrl+C to stop current work"
                        continue
                    _send(master, command)
                    state.backend_ready = False
                    return command
                notice = f"{entry.get('kind', 'item')}: {entry.get('target_id', node.get('path'))}"
                continue

            if isinstance(key, str) and key not in "\n\r.":
                query += key
                selected = 0
                notice = ""
            elif isinstance(key, int) and 32 <= key <= 126 and key != ord("."):
                query += chr(key)
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
        "Tab / Shift+Tab focus input, output, open control panel",
        "Ctrl+B toggle panel  Ctrl+F latest output (preserves draft)",
        "Output focus: arrows scroll, Home oldest, End latest",
        "PageUp/PageDown scroll output or focused panel",
        "Mouse drag selects terminal text for copy; IGOR_TUI_MOUSE=1 enables TUI mouse navigation",
        "Control focus: arrows select section, Enter open/refresh, Esc input",
        "Ctrl+P opens commands · : on empty input explores modules/capabilities",
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


def edit_property(screen: Any, prop: Property) -> dict[str, Any] | None:
    """Reusable typed editor returns a proposal; it cannot execute or write."""
    if not prop.editable or prop.secret:
        raise ValueError("property is read-only")
    if prop.type == "boolean":
        value = not prop.value
    elif prop.type == "enum":
        text = _settings_choice(screen, prop.label, prop.options, str(prop.value))
        if text is None:
            return None
        value = parse_control_input(prop, text)
    else:
        text = _settings_edit(screen, prop.label, str(prop.value))
        if text is None:
            return None
        value = parse_control_input(prop, text)
    return propose_property(prop, value)


def _settings_overlay(screen: Any, master: int, reader: EventReader,
                      state: EventState) -> None:
    """Show backend settings snapshots and send edits through local commands."""
    if state.pending_action or state.privilege_waiting or state.finished:
        return
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
            if state.pending_action or state.privilege_waiting or state.finished:
                return
            # Settings commands may still print a classic summary. The view
            # consumes structured snapshots only, while draining PTY bytes.
            try:
                os.read(master, 4096)
            except (BlockingIOError, OSError):
                pass
            snapshot = state.settings_snapshot
            schemas = settings_properties(snapshot or {}, state.settings_sources)
            if snapshot is not None and notice == "Loading settings…":
                notice = ""
            height, width = screen.getmaxyx()
            screen.erase()
            try:
                screen.addnstr(0, 0, "Settings", max(1, width - 1), curses.A_BOLD)
                if snapshot is not None:
                    first = max(0, selected - max(1, height - 5) + 1)
                    for row, schema in enumerate(schemas[first:first + max(1, height - 4)], 2):
                        index = first + row - 2
                        marker = ">" if index == selected else " "
                        try:
                            text = property_text(parse_property(schema))
                        except (ValueError, TypeError):
                            text = "Invalid/unsupported property"
                        line = f"{marker} {text}"
                        screen.addnstr(row, 0, line, max(1, width - 1),
                                       curses.A_REVERSE if index == selected else 0)
                selected_source = ""
                if snapshot is not None and schemas:
                    selected_source = str(schemas[selected].get("source") or "")
                footer = notice or (
                    f"{selected_source} · ↑↓ move  Enter edit/toggle  Esc back"
                    if selected_source else "↑↓ move  Enter edit/toggle  Esc back"
                )
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
                try:
                    prop = parse_property(schemas[selected])
                    proposal = edit_property(screen, prop)
                    if proposal is None:
                        continue
                    command = settings_proposal_command(proposal, snapshot)
                except ValueError as error:
                    notice = str(error)
                    continue
                field_key = prop.id
                current = str(snapshot.get(field_key, ""))
                value = (("on" if proposal["value"] else "off") if prop.type == "boolean"
                         else str(proposal["value"]))
                requested = (field_key, value, current)
                request_failed = False
                notice = "Saving…"
                # The backend emits the authoritative post-change snapshot only
                # after the mutation has completed. Never queue a refresh behind
                # a command: Configuration Service-backed settings may stop for
                # approval and queued text must not become approval input.
                _send(master, command)
    finally:
        screen.timeout(100)


def run_tui(backend: Iterable[str] = DEFAULT_BACKEND, stream: Path | None = None) -> int:
    """Run the frontend and its backend in a PTY."""
    own_stream = stream is None
    path = (stream or _private_stream_path()).expanduser().resolve()
    environment = os.environ.copy()
    environment.update(
        IGOR_TUI_MODE="true",
        IGOR_AI_EVENT_RENDER="false",
        IGOR_AI_EVENT_STREAM=str(path),
        IGOR_RUNTIME_DIR=str(path.parent),
        IGOR_TUI_STARTED_MS=str(time.time_ns() // 1_000_000),
    )
    backend_command = tuple(backend)
    pid, master = pty.fork()
    if pid == 0:
        attributes = termios.tcgetattr(0)
        attributes[3] &= ~termios.ECHO
        termios.tcsetattr(0, termios.TCSANOW, attributes)
        os.execvpe(backend_command[0], backend_command, environment)
    flags = fcntl.fcntl(master, fcntl.F_GETFL)
    fcntl.fcntl(master, fcntl.F_SETFL, flags | os.O_NONBLOCK)
    show_timestamps = os.environ.get("IGOR_TUI_TIMESTAMPS", "true").lower() not in {
        "false", "off", "0", "no",
    }
    state = EventState(show_timestamps=show_timestamps)
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
    inspection = HistoryInspection()
    investigations = InvestigationInspection()
    try:
        return _interaction_loop(screen, pid, master, path, state, inspection, investigations)
    finally:
        inspection.close()
        investigations.close()


def _configure_mouse() -> bool:
    """Prefer terminal-native selection/copy; TUI mouse navigation is opt-in."""
    enabled = os.environ.get("IGOR_TUI_MOUSE", "").strip().lower() in {
        "1", "true", "yes", "on",
    }
    try:
        if enabled:
            curses.mousemask(getattr(curses, "BUTTON4_PRESSED", 0) |
                             getattr(curses, "BUTTON5_PRESSED", 0) |
                             getattr(curses, "BUTTON1_CLICKED", 0) |
                             getattr(curses, "BUTTON1_PRESSED", 0))
            curses.mouseinterval(0)
        else:
            curses.mousemask(0)
    except curses.error:
        pass
    return enabled


def _interaction_loop(screen: Any, pid: int, master: int, path: Path,
                      state: EventState | None, inspection: HistoryInspection,
                      investigations: InvestigationInspection | None = None) -> int:
    screen.keypad(True)
    screen.timeout(100)
    state, buffer = state or EventState(), InputBuffer()
    navigator, history = ActivityNavigator(), InputHistory()
    focus = FocusModel()
    mouse_navigation_enabled = _configure_mouse()
    commands = registry_commands()
    reader = EventReader(path)
    terminal_decoder = codecs.getincrementaldecoder("utf-8")("replace")
    dirty = True
    while True:
        events = reader.read()
        before_count = _activity_limits(screen, state, focus)[2] if events and navigator.scroll else 0
        awaiting_approval = bool(state.pending_action)
        for event in events:
            apply_event(state, event)
        if (state.pending_action and not awaiting_approval) or state.privilege_waiting:
            focus.set_focus("input")
        if events and navigator.scroll:
            _, maximum, after_count = _activity_limits(screen, state, focus)
            navigator.preserve_view(after_count - before_count, maximum)
        dirty = inspection.poll() or dirty or bool(events)
        if investigations is not None:
            dirty = investigations.poll() or dirty
        try:
            raw = os.read(master, 4096)
            if not raw:
                return _child_exit_code(pid, True) or 0
            if state.console_capture:
                before_count = _activity_limits(screen, state, focus)[2] if navigator.scroll else 0
                state.add_terminal_output(terminal_decoder.decode(raw))
                if navigator.scroll:
                    _, maximum, after_count = _activity_limits(screen, state, focus)
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
            _draw(screen, state, buffer, navigator, focus, panel_sections(state, inspection, investigations))
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
            if focus.region == "input":
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
        page, maximum, before_count = _activity_limits(screen, state, focus)
        if key == curses.KEY_MOUSE and mouse_navigation_enabled:
            try:
                mouse_navigation(curses.getmouse(), focus, navigator, *screen.getmaxyx(),
                                 page, maximum)
            except curses.error:
                pass
            continue
        if navigation_key(key, focus, navigator, page, maximum):
            if key == 2:
                _, maximum, after_count = _activity_limits(screen, state, focus)
                navigator.preserve_view(after_count - before_count, maximum)
                if not focus.panel_open:
                    inspection.close()
                    if investigations is not None:
                        investigations.close()
            continue
        if focus.region == "panel":
            sections = panel_sections(state, inspection, investigations)
            if key == curses.KEY_UP:
                focus.select(-1, len(sections))
            elif key == curses.KEY_DOWN:
                focus.select(1, len(sections))
            elif key in (curses.KEY_PPAGE, curses.KEY_NPAGE, curses.KEY_HOME, curses.KEY_END):
                rows = [wrapped for line in panel_rows(sections[focus.panel_selection])
                        for wrapped in _wrap_line(line, max(1, _surface_width(screen.getmaxyx()[1], focus)[1]))]
                visible = max(1, page - len(sections) - 2)
                maximum_panel = max(0, len(rows) - visible)
                if key == curses.KEY_HOME:
                    focus.panel_scroll = 0
                elif key == curses.KEY_END:
                    focus.panel_scroll = maximum_panel
                else:
                    delta = visible if key == curses.KEY_NPAGE else -visible
                    focus.panel_scroll = min(maximum_panel, max(0, focus.panel_scroll + delta))
            elif key in (10, 13, curses.KEY_ENTER):
                section_id = sections[focus.panel_selection]["id"]
                if section_id == "history":
                    inspection.start()
                elif section_id == "investigations" and investigations is not None:
                    investigations.start()
                elif section_id == "properties" and not state.pending_action:
                    _settings_overlay(screen, master, reader, state)
                    focus.set_focus("input")
            elif key == 27:
                focus.set_focus("input")
            continue
        if focus.region == "output":
            if key in (27, 10, 13, curses.KEY_ENTER):
                focus.set_focus("input")
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
        if key == 16 and not state.pending_action:
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
        if key == ord(":") and not buffer.text() and not state.pending_action:
            selected = _operator_overlay(screen, master, reader, state, buffer)
            if selected:
                state.end_terminal_capture()
                state.add_operator_input(selected)
                state.begin_terminal_capture()
                navigator.latest()
            continue
        page, maximum, _ = _activity_limits(screen, state, focus)
        if key == curses.KEY_HOME:
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
            pending = bool(state.pending_action)
            draft = buffer.text()
            if not pending and draft.strip() and not state.backend_ready:
                message = "Backend busy — input kept as draft; wait for READY or press Ctrl+C to stop"
                if not state.activity or state.activity[-1].event_type != "warning" or state.activity[-1].text != message:
                    state.activity.append(Activity("warning", message))
                continue
            submitted = buffer.clear()
            if pending:
                submitted = submitted.splitlines()[0] if submitted.splitlines() else ""
            if not pending and submitted.strip() == "settings":
                _settings_overlay(screen, master, reader, state)
                navigator.latest()
                continue
            state.end_terminal_capture()
            operator_control = not pending and submitted.strip().startswith("invoke ")
            local = not pending and (operator_control or registry_is_local(submitted))
            if not local and not pending:
                history.add(submitted)
            if submitted:
                if operator_control:
                    state.add_operator_input(submitted)
                else:
                    state.add_user_input(submitted)
            if local:
                state.begin_terminal_capture()
            _send(master, submitted)
            if not pending and submitted:
                state.backend_ready = False
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
