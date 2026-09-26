#!/usr/bin/env python3
"""Canonical registry for commands handled by the interactive AI session.

The Bash session remains the command executor.  This module only answers two
questions: how a command is documented, and whether an input line is a local
session command.  Keeping the registry data-only makes it safe to use before
any model request is constructed.
"""

from __future__ import annotations

import json
import sys
from typing import Any


_COMMANDS: tuple[dict[str, Any], ...] = (
    {
        "id": "help",
        "name": "help",
        "aliases": ("?",),
        "syntax": "help",
        "category": "session",
        "description": "show the local AI session commands",
        "handler": "help",
    },
    {
        "id": "stats",
        "name": "stats",
        "aliases": (),
        "syntax": "stats",
        "category": "session",
        "description": "show token, cost, and context statistics",
        "handler": "stats",
    },
    {
        "id": "refresh",
        "name": "refresh",
        "aliases": (),
        "syntax": "refresh",
        "category": "session",
        "description": "refresh the server context",
        "handler": "refresh",
    },
    {
        "id": "solved",
        "name": "solved",
        "aliases": ("new", "wip clear", "wip done", "mark solved", "new session", "start fresh", "clear session"),
        "syntax": "solved",
        "category": "session",
        "description": "clear the investigation and start a fresh topic",
        "handler": "solved",
    },
    {
        "id": "stop",
        "name": "stop",
        "aliases": ("/stop",),
        "syntax": "stop",
        "category": "control",
        "description": "pause the task when the chat prompt is available",
        "handler": "stop",
        "states": ("ready", "running", "investigating", "tools_requested", "tool_running",
                    "completed", "no_further_action", "provider_failed", "action_denied",
                    "verification_denied", "repeated_action", "malformed_response", "continuation_limit",
                    "tool_succeeded", "tool_failed", "validation_blocked"),
    },
    {
        "id": "continue",
        "name": "continue",
        "aliases": ("cont",),
        "syntax": "continue",
        "category": "control",
        "description": "resume a paused or capped continuation loop",
        "handler": "continue",
        "states": ("ready", "running", "investigating", "tools_requested", "tool_running",
                    "stopped_by_user", "continuation_limit", "completed", "no_further_action",
                    "provider_failed", "action_denied", "verification_denied", "repeated_action",
                    "malformed_response", "tool_succeeded", "tool_failed", "validation_blocked"),
    },
    {
        "id": "undo",
        "name": "undo",
        "aliases": (),
        "syntax": "undo [all|list]",
        "category": "changes",
        "description": "reverse the last change, list changes, or reverse all changes",
        "handler": "undo",
    },
    {
        "id": "history",
        "name": "history",
        "aliases": (),
        "syntax": "history [session-id]",
        "category": "history",
        "description": "list sessions or show one session post-mortem",
        "handler": "history",
    },
    {
        "id": "replay",
        "name": "replay",
        "aliases": (),
        "syntax": "replay <session-id>",
        "category": "history",
        "description": "show a session command log",
        "handler": "replay",
    },
    {
        "id": "hypo",
        "name": "hypo",
        "aliases": ("hypotheses",),
        "syntax": "hypo [add|del|edit|pin|clear|reset] [value]",
        "category": "investigation",
        "description": "inspect or manage investigation hypotheses",
        "handler": "hypo",
    },
    {
        "id": "exec",
        "name": "exec",
        "aliases": (),
        "syntax": "exec on|off",
        "category": "control",
        "description": "toggle automatic approval for change actions",
        "handler": "exec",
    },
    {
        "id": "mode",
        "name": "mode",
        "aliases": (),
        "syntax": "mode guide|assist|executive",
        "category": "control",
        "description": "select Guide, Assist, or Executive interaction mode",
        "handler": "mode",
    },
    {
        "id": "quiet",
        "name": "quiet",
        "aliases": (),
        "syntax": "quiet on|off",
        "category": "control",
        "description": "toggle collapsed display for read-only steps",
        "handler": "quiet",
    },
    {
        "id": "verbose",
        "name": "verbose",
        "aliases": (),
        "syntax": "verbose on|off",
        "category": "control",
        "description": "toggle explanatory output",
        "handler": "verbose",
    },
    {
        "id": "settings",
        "name": "settings",
        "aliases": (),
        "syntax": "settings [FIELD VALUE]",
        "category": "control",
        "description": "show or edit AI settings",
        "handler": "settings",
    },
    {
        "id": "apikey",
        "name": "apikey",
        "aliases": (),
        "syntax": "apikey",
        "category": "control",
        "description": "replace the current provider key",
        "handler": "apikey",
    },
    {
        "id": "canary",
        "name": "canary",
        "aliases": (),
        "syntax": "canary dismiss",
        "category": "investigation",
        "description": "clear the post-fix canary alert",
        "handler": "canary",
    },
    {
        "id": "diagnose",
        "name": "/diagnose",
        "aliases": ("/diag",),
        "syntax": "/diagnose [focus]",
        "category": "tools",
        "description": "run local diagnostics and ask Igor to analyze them",
        "handler": "diagnose",
    },
    {
        "id": "cmd",
        "name": "/cmd",
        "aliases": (),
        "syntax": "/cmd <description>",
        "category": "tools",
        "description": "generate a copy-ready shell command",
        "handler": "cmd",
    },
    {
        "id": "exit",
        "name": "exit",
        "aliases": ("quit", "q"),
        "syntax": "exit",
        "category": "session",
        "description": "end the AI session",
        "handler": "exit",
    },
    {
        "id": "palette",
        "name": "palette",
        "aliases": (":",),
        "syntax": "palette [filter]",
        "category": "session",
        "description": "list and invoke local session commands",
        "handler": "palette",
    },
)


def _validate_registry() -> None:
    """Reject ambiguous registry entries when this data module is imported."""
    ids = [entry["id"] for entry in _COMMANDS]
    if len(ids) != len(set(ids)):
        raise ValueError("command action IDs must be unique")
    spellings: dict[str, str] = {}
    for entry in _COMMANDS:
        for spelling in (entry["name"], *entry["aliases"]):
            prior = spellings.get(spelling)
            if prior is not None and prior != entry["id"]:
                raise ValueError(f"command alias {spelling!r} is ambiguous")
            spellings[spelling] = entry["id"]


_validate_registry()


def commands() -> tuple[dict[str, Any], ...]:
    """Return immutable registry entries with JSON-friendly alias lists."""
    return tuple(_public_entry(entry) for entry in _COMMANDS)


def _public_entry(entry: dict[str, Any]) -> dict[str, Any]:
    """Copy an entry so callers cannot mutate the authoritative registry."""
    result = {**entry, "aliases": list(entry["aliases"])}
    if "states" in result:
        result["states"] = list(result["states"])
    return result


def _entry(name: str) -> dict[str, Any] | None:
    for command in _COMMANDS:
        if name == command["name"] or name in command["aliases"]:
            return _public_entry(command)
    return None


def _matching_entry(line: str) -> tuple[dict[str, Any] | None, list[str]]:
    """Match the longest canonical spelling or alias, including multiword ones."""
    candidates: list[tuple[int, dict[str, Any], str]] = []
    for entry in _COMMANDS:
        for spelling in (entry["name"], *entry["aliases"]):
            parts = spelling.split()
            prefix = " ".join(line.split()[:len(parts)])
            if prefix == spelling and (line == spelling or line.startswith(spelling + " ")):
                candidates.append((len(parts), entry, spelling))
    if not candidates:
        return None, []
    _, entry, spelling = max(candidates, key=lambda item: item[0])
    return _public_entry(entry), line[len(spelling):].strip().split() if line[len(spelling):].strip() else []


def lookup(line: str, state: str | None = None) -> dict[str, Any]:
    """Resolve an input line without invoking a handler or a model.

    The returned object always has ``matched``.  A matched command includes
    its canonical name, handler, arguments, and original input.  Argument
    validation is intentionally limited to command boundaries; handlers own
    command-specific validation and can preserve legacy behavior.
    """
    original = line
    line = line.strip()
    if not line:
        return {"matched": False, "input": original, "reason": "empty"}

    command, args = _matching_entry(line)
    if command is None:
        return {"matched": False, "input": original, "reason": "unknown"}

    valid = True
    reason = ""
    name = command["name"]
    if name == "/cmd":
        # Keep the complete description as one argument for the legacy route.
        args = [line[len("/cmd"):].strip()] if line[len("/cmd"):].strip() else []
        valid = len(args) == 1
        reason = "missing description" if not valid else ""
    elif name == "/diagnose":
        # A diagnostic focus is free text and may contain several words.
        args = [" ".join(args)] if args else []
    elif name == "palette":
        valid = len(args) <= 1
        reason = "expected at most one filter" if not valid else ""
    elif name in {"exec", "quiet", "verbose"}:
        valid = len(args) == 1 and args[0] in {"on", "off"}
        reason = "expected on or off" if not valid else ""
    elif name == "mode":
        valid = len(args) == 1 and args[0] in {"guide", "assist", "executive"}
        reason = "expected guide, assist, or executive" if not valid else ""
    elif name == "replay":
        valid = len(args) == 1 and bool(args[0])
        reason = "expected a session id" if not valid else ""
    elif name == "undo":
        valid = len(args) <= 1 and (not args or args[0] in {"all", "list"})
        reason = "expected all or list" if not valid else ""
    elif name == "hypo":
        valid = len(args) == 0 or args[0] in {"add", "del", "edit", "pin", "clear", "reset"}
        reason = "unknown hypothesis operation" if not valid else ""
        if args and args[0] in {"add", "del", "edit", "pin"} and len(args) < 2:
            valid = False
            reason = "hypothesis operation needs a value"
        if args and args[0] in {"clear", "reset"} and len(args) != 1:
            valid = False
            reason = "unexpected hypothesis arguments"
    elif name == "history":
        valid = len(args) <= 1
        reason = "expected at most one session id" if not valid else ""
    elif name == "settings":
        # The no-argument form retains the classic textual summary.
        valid = not args
        if args:
            if args == ["snapshot"]:
                valid = True
            elif len(args) == 2 and args[0] in {"autostart", "hybrid"}:
                valid = args[1] in {"on", "off"}
            elif len(args) == 2 and args[0] in {"provider", "model", "temperature", "max_tokens"}:
                valid = bool(args[1])
            else:
                valid = False
        reason = "expected a supported setting and value" if not valid else ""
    elif name == "canary":
        valid = args == ["dismiss"]
        reason = "expected dismiss" if not valid else ""
    elif name in {"help", "stats", "refresh", "solved", "stop", "continue", "apikey", "exit"}:
        valid = not args
        reason = "unexpected arguments" if not valid else ""

    allowed = command.get("states")
    if valid and state and allowed and state not in allowed:
        valid = False
        reason = f"unavailable in session state {state}"
    return {"matched": True, "command": command, "arguments": args, "input": original,
            "valid": valid, **({"reason": reason, "usage": command["syntax"]} if reason else {})}


def palette_entries(filter_text: str = "", state: str | None = None) -> tuple[dict[str, Any], ...]:
    """Return registry entries suitable for the lightweight command palette."""
    needle = filter_text.strip().lower()
    entries = []
    for entry in _COMMANDS:
        if entry["name"] == "palette":
            continue
        haystack = " ".join((entry["name"], entry["syntax"], entry["description"], *entry["aliases"])).lower()
        if needle and needle not in haystack:
            continue
        allowed = entry.get("states")
        if state and allowed and state not in allowed:
            continue
        entries.append(_public_entry(entry))
    return tuple(entries)


def help_text() -> str:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for command in _COMMANDS:
        grouped.setdefault(command["category"], []).append(command)
    lines = []
    for category, entries in grouped.items():
        lines.append(category.title())
        for command in entries:
            aliases = ", ".join(command["aliases"])
            label = command["syntax"] + (f" ({aliases})" if aliases else "")
            lines.append(f"  {label:<42} {command['description']}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main(argv: list[str]) -> int:
    if not argv or argv[0] == "help":
        sys.stdout.write(help_text())
        return 0
    if argv[0] == "commands":
        sys.stdout.write(json.dumps(list(commands()), sort_keys=True) + "\n")
        return 0
    if argv[0] == "palette":
        args = list(argv[1:])
        state = None
        if len(args) >= 2 and args[0] == "--state":
            state = args[1]
            args = args[2:]
        filter_text = " ".join(args).strip()
        for command in palette_entries(filter_text, state=state):
            sys.stdout.write(f"{command['name']}\t{command['syntax']}\t{command['description']}\n")
        return 0
    if argv[0] == "lookup":
        state = None
        args = list(argv[1:])
        if len(args) >= 2 and args[0] == "--state":
            state = args[1]
            args = args[2:]
        line = " ".join(args)
        sys.stdout.write(json.dumps(lookup(line, state=state), sort_keys=True) + "\n")
        return 0
    sys.stderr.write("usage: session_commands.py [help|commands|palette [--state STATE] [FILTER]|lookup [--state STATE] COMMAND]\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
