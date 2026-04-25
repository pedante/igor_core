#!/usr/bin/env python3
"""
ai_render.py — Terminal output renderer for IGOR.

Reads the ai_engine.py marker stream from stdin, renders Rich panels
to stderr, and passes all markers through to stdout unchanged.

Usage:
    python3 ai_engine.py call | python3 ai_render.py [--debug]
    python3 ai_render.py --mode status "Message to display"

Modes:
    call    — parse marker stream, render panels (default when reading stdin)
    status  — render a single status message to stderr, no stdin consumed

Flags:
    --debug — pass markers through raw, no Rich rendering.
              Set IGOR_RENDER_DEBUG=1 in shell to activate from bash.

Note: This file is core/ai/ai_render.py — the terminal renderer.
      core/lib/ai_render.py is the system prompt renderer. Different files.

MARKER_PROTOCOL_VERSION = "1"
"""

import sys
import os
import json
import base64

# Rich import — degrade gracefully if unavailable
try:
    from rich.console import Console
    from rich.panel import Panel
    from rich.text import Text
    _RICH_AVAILABLE = True
except ImportError:
    _RICH_AVAILABLE = False

# All visual output goes to stderr — stdout reserved for marker pass-through
_CONSOLE = Console(stderr=True, highlight=False) if _RICH_AVAILABLE else None


def _b64dec(s: str) -> str:
    """Decode base64 string. Returns empty string on any error."""
    try:
        return base64.b64decode(s.encode()).decode("utf-8", errors="replace")
    except Exception:
        return ""


def _parse_markers(lines: list) -> dict:
    """
    Parse marker lines into components dict.
    Returns:
        {
            "reply":             list[str],
            "scratchpad":        dict|None,
            "tools":             list[dict],
            "tokens_in":         int,
            "tokens_out":        int,
            "truncated":         bool,
            "evidence_rejected": bool,
            "validation":        list[dict],
        }
    """
    result = {
        "reply": [],
        "scratchpad": None,
        "tools": [],
        "tokens_in": 0,
        "tokens_out": 0,
        "truncated": False,
        "evidence_rejected": False,
        "validation": [],
    }
    in_reply = False

    for line in lines:
        if line == "REPLY_START":
            in_reply = True
        elif line == "REPLY_END":
            in_reply = False
        elif in_reply:
            result["reply"].append(line)
        elif line.startswith("SCRATCHPAD_B64: "):
            raw = _b64dec(line[len("SCRATCHPAD_B64: "):])
            try:
                result["scratchpad"] = json.loads(raw)
            except Exception:
                pass
        elif line.startswith("TOOL_B64: "):
            raw = _b64dec(line[len("TOOL_B64: "):])
            try:
                result["tools"].append(json.loads(raw))
            except Exception:
                pass
        elif line.startswith("TOKENS_IN: "):
            try:
                result["tokens_in"] = int(line.split(": ", 1)[1])
            except (ValueError, IndexError):
                pass
        elif line.startswith("TOKENS_OUT: "):
            try:
                result["tokens_out"] = int(line.split(": ", 1)[1])
            except (ValueError, IndexError):
                pass
        elif line == "TRUNCATED: true":
            result["truncated"] = True
        elif line == "EVIDENCE_REJECTED: true":
            result["evidence_rejected"] = True
        elif line.startswith("VALIDATION_B64: "):
            raw = _b64dec(line[len("VALIDATION_B64: "):])
            try:
                result["validation"] = json.loads(raw)
            except Exception:
                pass

    return result


def render_panel(scratchpad: dict) -> None:
    """
    Render investigating/adjusting panel to stderr.
    Phase 2 imports and calls this directly.
    """
    status = scratchpad.get("status", "investigating")
    hypothesis = scratchpad.get("hypothesis", "")
    confidence = scratchpad.get("confidence", "")
    next_action = scratchpad.get("next_action", "")

    if not _RICH_AVAILABLE or _CONSOLE is None:
        if hypothesis:
            sys.stderr.write(f"  [{status}] {hypothesis}\n")
        return

    content = Text()
    if hypothesis:
        content.append("Hypothesis: ", style="bold")
        content.append(hypothesis + "\n")
    if confidence:
        conf_style = {"high": "green", "medium": "yellow", "low": "red"}.get(confidence.lower(), "white")
        content.append("Confidence: ", style="bold")
        content.append(confidence.capitalize() + "\n", style=conf_style)
    if next_action:
        content.append("Next: ", style="bold dim")
        content.append(next_action)

    title_map = {
        "investigating": "[bold blue]Igor · Investigating[/bold blue]",
        "adjusting":     "[bold yellow]Igor · Adjusting[/bold yellow]",
    }
    title = title_map.get(status, "[bold blue]Igor[/bold blue]")
    _CONSOLE.print(Panel(content, title=title, border_style="blue", padding=(0, 1)))


def render_conclusion(scratchpad: dict, reply_text: str = "") -> None:
    """
    Render conclusion panel to stderr.
    Phase 2 imports and calls this directly.
    """
    status = scratchpad.get("status", "fixed")
    evidence = scratchpad.get("evidence_ref", "") or ""

    style_map = {
        "fixed":          ("green", "Igor · Fixed \u2713"),
        "nothing_to_fix": ("cyan",  "Igor · No Issue"),
        "blocked":        ("red",   "Igor · Blocked"),
    }
    border_color, title_text = style_map.get(status, ("white", "Igor · Done"))

    if not _RICH_AVAILABLE or _CONSOLE is None:
        sys.stderr.write(f"  [{title_text}]" + (f" {evidence}" if evidence else "") + "\n")
        return

    content = Text()
    if status == "fixed":
        content.append("Status: ", style="bold")
        content.append("FIXED\n", style="bold green")
        if evidence:
            content.append("Evidence: ", style="bold")
            content.append(evidence)
    elif status == "blocked":
        content.append("Status: ", style="bold")
        content.append("BLOCKED\n", style="bold red")
        if evidence:
            content.append("Reason: ", style="bold")
            content.append(evidence)
    elif status == "nothing_to_fix":
        content.append("Expected behavior \u2014 no action needed.", style="italic")
    else:
        content.append(f"Status: {status}")

    _CONSOLE.print(Panel(
        content,
        title=f"[bold {border_color}]{title_text}[/bold {border_color}]",
        border_style=border_color,
        padding=(0, 1),
    ))


def render_status(message: str) -> None:
    """
    Render single status line to stderr.
    Phase 2 imports and calls this directly.
    """
    if not _RICH_AVAILABLE or _CONSOLE is None:
        sys.stderr.write(f"  {message}\n")
        return
    _CONSOLE.print(f"  [dim]\u25b8[/dim] {message}")


def _render_from_markers(components: dict) -> None:
    """Select render function based on scratchpad status."""
    sp = components.get("scratchpad")
    if sp is None:
        return

    status = sp.get("status", "investigating")

    if status in ("fixed", "nothing_to_fix", "blocked"):
        render_conclusion(sp, "\n".join(components.get("reply", [])))
    elif status in ("investigating", "adjusting"):
        render_panel(sp)
    # unknown status — silently skip (forward-compatible)

    # Token footer
    tin = components.get("tokens_in", 0)
    tout = components.get("tokens_out", 0)
    if (tin or tout) and _RICH_AVAILABLE and _CONSOLE:
        _CONSOLE.print(f"  [dim]\u2191{tin} \u2193{tout} tokens[/dim]")


def _dispatch_scratchpad(sp: dict, reply: list) -> None:
    """Route a decoded scratchpad dict to the correct render function."""
    status = sp.get("status", "")
    if status in ("fixed", "nothing_to_fix", "blocked"):
        render_conclusion(sp, "\n".join(reply))
    elif status in ("investigating", "adjusting"):
        render_panel(sp)
    # unknown status → silently skip (forward-compatible)


def mode_call(lines, debug: bool) -> None:
    """
    Streaming pipe mode: iterate lines, pass each to stdout immediately.

    SCRATCHPAD_B64 is consumed (not forwarded) in normal mode to keep the
    bash marker stream clean. The panel is rendered to stderr as soon as
    the scratchpad line is seen — before tool results, not after.
    Token footer is deferred until TOKENS_IN/OUT have both been seen.

    In --debug mode all markers pass through unchanged and no rendering occurs.
    """
    reply = []
    in_reply = False
    tokens_in = 0
    tokens_out = 0

    for line in lines:
        line = line.rstrip("\n")

        if line == "REPLY_START":
            in_reply = True
        elif line == "REPLY_END":
            in_reply = False
        elif in_reply:
            reply.append(line)
        elif line.startswith("SCRATCHPAD_B64: "):
            if not debug:
                raw = _b64dec(line[len("SCRATCHPAD_B64: "):])
                try:
                    _dispatch_scratchpad(json.loads(raw), reply)
                except Exception:
                    pass
            # Always forward to stdout — bash saves this to scratchpad.txt
            # for injection into the next API call's system prompt.
        elif line.startswith("TOKENS_IN: "):
            try:
                tokens_in = int(line.split(": ", 1)[1])
            except (ValueError, IndexError):
                pass
        elif line.startswith("TOKENS_OUT: "):
            try:
                tokens_out = int(line.split(": ", 1)[1])
            except (ValueError, IndexError):
                pass

        sys.stdout.write(line + "\n")
        sys.stdout.flush()

    # Token footer — rendered after all markers are consumed
    if not debug and (tokens_in or tokens_out) and _RICH_AVAILABLE and _CONSOLE:
        _CONSOLE.print(f"  [dim]\u2191{tokens_in} \u2193{tokens_out} tokens[/dim]")


def main() -> None:
    args = sys.argv[1:]
    debug = "--debug" in args
    mode = "call"
    positional = []

    i = 0
    while i < len(args):
        if args[i] == "--mode" and i + 1 < len(args):
            mode = args[i + 1]
            i += 2
        elif args[i] == "--debug":
            i += 1
        else:
            positional.append(args[i])
            i += 1

    if mode == "status":
        render_status(positional[0] if positional else "")
        return

    # Stream stdin line-by-line — render panel on SCRATCHPAD_B64 as it arrives
    mode_call(sys.stdin, debug)


if __name__ == "__main__":
    main()
