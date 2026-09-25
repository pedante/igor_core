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
        "name": "help",
        "aliases": ("?",),
        "syntax": "help",
        "category": "session",
        "description": "show the local AI session commands",
        "handler": "help",
    },
    {
        "name": "stats",
        "aliases": (),
        "syntax": "stats",
        "category": "session",
        "description": "show token, cost, and context statistics",
        "handler": "stats",
    },
    {
        "name": "refresh",
        "aliases": (),
        "syntax": "refresh",
        "category": "session",
        "description": "refresh the server context",
        "handler": "refresh",
    },
    {
        "name": "solved",
        "aliases": ("new", "wip clear", "wip done", "mark solved", "new session", "start fresh", "clear session"),
        "syntax": "solved",
        "category": "session",
        "description": "clear the investigation and start a fresh topic",
        "handler": "solved",
    },
    {
        "name": "stop",
        "aliases": ("/stop",),
        "syntax": "stop",
        "category": "control",
        "description": "pause the task when the chat prompt is available",
        "handler": "stop",
    },
    {
        "name": "continue",
        "aliases": ("cont",),
        "syntax": "continue",
        "category": "control",
        "description": "resume a paused or capped continuation loop",
        "handler": "continue",
    },
    {
        "name": "undo",
        "aliases": (),
        "syntax": "undo [all|list]",
        "category": "changes",
        "description": "reverse the last change, list changes, or reverse all changes",
        "handler": "undo",
    },
    {
        "name": "history",
        "aliases": (),
        "syntax": "history [session-id]",
        "category": "history",
        "description": "list sessions or show one session post-mortem",
        "handler": "history",
    },
    {
        "name": "replay",
        "aliases": (),
        "syntax": "replay <session-id>",
        "category": "history",
        "description": "show a session command log",
        "handler": "replay",
    },
    {
        "name": "hypo",
        "aliases": ("hypotheses",),
        "syntax": "hypo [add|del|edit|pin|clear|reset] [value]",
        "category": "investigation",
        "description": "inspect or manage investigation hypotheses",
        "handler": "hypo",
    },
    {
        "name": "exec",
        "aliases": (),
        "syntax": "exec on|off",
        "category": "control",
        "description": "toggle automatic approval for change actions",
        "handler": "exec",
    },
    {
        "name": "quiet",
        "aliases": (),
        "syntax": "quiet on|off",
        "category": "control",
        "description": "toggle collapsed display for read-only steps",
        "handler": "quiet",
    },
    {
        "name": "verbose",
        "aliases": (),
        "syntax": "verbose on|off",
        "category": "control",
        "description": "toggle explanatory output",
        "handler": "verbose",
    },
    {
        "name": "settings",
        "aliases": (),
        "syntax": "settings [autostart|hybrid on|off]",
        "category": "control",
        "description": "show settings or change startup options",
        "handler": "settings",
    },
    {
        "name": "apikey",
        "aliases": (),
        "syntax": "apikey",
        "category": "control",
        "description": "replace the current provider key",
        "handler": "apikey",
    },
    {
        "name": "canary",
        "aliases": (),
        "syntax": "canary dismiss",
        "category": "investigation",
        "description": "clear the post-fix canary alert",
        "handler": "canary",
    },
    {
        "name": "/diagnose",
        "aliases": ("/diag",),
        "syntax": "/diagnose [focus]",
        "category": "tools",
        "description": "run local diagnostics and ask Igor to analyze them",
        "handler": "diagnose",
    },
    {
        "name": "/cmd",
        "aliases": (),
        "syntax": "/cmd <description>",
        "category": "tools",
        "description": "generate a copy-ready shell command",
        "handler": "cmd",
    },
    {
        "name": "exit",
        "aliases": ("quit", "q"),
        "syntax": "exit",
        "category": "session",
        "description": "end the AI session",
        "handler": "exit",
    },
)


def commands() -> tuple[dict[str, Any], ...]:
    """Return immutable registry entries with JSON-friendly alias lists."""
    return tuple({**entry, "aliases": list(entry["aliases"])} for entry in _COMMANDS)


def _entry(name: str) -> dict[str, Any] | None:
    for command in _COMMANDS:
        if name == command["name"] or name in command["aliases"]:
            return {**command, "aliases": list(command["aliases"])}
    return None


def lookup(line: str) -> dict[str, Any]:
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

    if line == "/cmd":
        command = _entry("/cmd")
        return {"matched": True, "command": command, "arguments": [], "input": original, "valid": False,
                "reason": "missing description"}
    if line.startswith("/cmd "):
        command = _entry("/cmd")
        description = line[5:].strip()
        return {"matched": True, "command": command, "arguments": [description], "input": original,
                "valid": bool(description)}

    words = line.split()
    # Longest fixed forms must win over their shorter prefixes.
    for fixed in ("wip clear", "wip done", "mark solved", "new session", "start fresh", "clear session"):
        if line == fixed:
            command = _entry(fixed)
            return {"matched": True, "command": command, "arguments": [], "input": original, "valid": True}

    command = _entry(words[0])
    if command is None:
        return {"matched": False, "input": original, "reason": "unknown"}

    args = words[1:]
    valid = True
    reason = ""
    name = command["name"]
    if name in {"exec", "quiet", "verbose"}:
        valid = len(args) == 1 and args[0] in {"on", "off"}
        reason = "expected on or off" if not valid else ""
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
        valid = not args or (len(args) == 2 and args[0] in {"autostart", "hybrid"}
                             and args[1] in {"on", "off"})
        reason = "expected autostart or hybrid followed by on or off" if not valid else ""
    elif name == "canary":
        valid = args == ["dismiss"]
        reason = "expected dismiss" if not valid else ""
    elif name in {"help", "stats", "refresh", "solved", "stop", "continue", "apikey", "exit"}:
        valid = not args
        reason = "unexpected arguments" if not valid else ""

    return {"matched": True, "command": command, "arguments": args, "input": original,
            "valid": valid, **({"reason": reason} if reason else {})}


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
    if argv[0] == "lookup":
        line = " ".join(argv[1:])
        sys.stdout.write(json.dumps(lookup(line), sort_keys=True) + "\n")
        return 0
    sys.stderr.write("usage: session_commands.py [help|commands|lookup COMMAND]\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
