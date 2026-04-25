#!/usr/bin/env python3
"""
igor_tui.py — Full-screen Textual TUI main menu for IGOR.

Reads menu JSON from stdin, shows an interactive terminal UI with
keyboard navigation, and prints the selected key to stdout on exit.

Input (stdin): JSON produced by _igor_build_menu_json() in igor.sh.
Output (stdout): selected key string (e.g. "A", "4", "Q").
Exit codes: 0 = selection made, 1 = cancelled / error.

Requires: textual >= 0.47 (pacman: python-textual), rich
"""

from __future__ import annotations

import json
import sys
from typing import Optional

# ── Dependency guard ──────────────────────────────────────────────────────────
try:
    from textual.app import App, ComposeResult
    from textual.binding import Binding
    from textual.widget import Widget
    from textual.widgets import Footer, Static
    from textual.widgets import OptionList
    from textual.widgets.option_list import Option
    try:
        from textual.widgets.option_list import Separator as _Sep
        def _mk_separator() -> object:
            return _Sep()
    except ImportError:
        # Older textual (<0.28): use an empty disabled option as a visual gap
        def _mk_separator() -> object:  # type: ignore[misc]
            return Option(" ", disabled=True)
    from textual import events
    from rich.text import Text
except ImportError as _e:
    print(f"igor_tui: missing dependency — {_e}", file=sys.stderr)
    print(
        "  Install: sudo pacman -S python-textual  (Arch)"
        "  or: pip install textual",
        file=sys.stderr,
    )
    sys.exit(127)


# ── Palette ───────────────────────────────────────────────────────────────────
_BG        = "#0d1117"   # main background
_PANEL_BG  = "#0a0e1a"   # header / footer background
_BORDER    = "#1e3a5f"   # border colour
_ACCENT    = "#38bdf8"   # Igor cyan
_TEXT      = "#c9d1d9"   # primary text
_DIM       = "#475569"   # secondary / descriptions
_KEY_COLOR = "#22d3ee"   # shortcut key badges
_HDR_COLOR = "#58a6ff"   # section header labels
_SEL_BG    = "#0f2744"   # selected item background
_HLTH_GOOD = "#4ade80"
_HLTH_WARN = "#fbbf24"
_HLTH_BAD  = "#f87171"


# ── Rich text helpers ─────────────────────────────────────────────────────────

def _health_text(score: int) -> Text:
    t = Text(no_wrap=True)
    if score < 0:
        t.append("● HEALTH UNKNOWN", style=f"bold {_DIM}")
        return t
    color = _HLTH_GOOD if score >= 75 else (_HLTH_WARN if score >= 50 else _HLTH_BAD)
    filled = max(0, min(10, round(score / 10)))
    t.append("●" * filled,         style=f"bold {color}")
    t.append("○" * (10 - filled),  style=_DIM)
    t.append(f"  {score}%",         style=f"bold {color}")
    return t


def _option(item: dict) -> Option:
    t = Text(no_wrap=True)
    t.append(f"[{item['key']}]",           style=f"bold {_KEY_COLOR}")
    t.append(f"  {item['label']:<20}",     style=f"bold {_TEXT}")
    if desc := item.get("desc", ""):
        t.append(f"  {desc}",              style=_DIM)
    return Option(t, id=item["key"])


def _section_header(name: str) -> Option:
    """Non-selectable, styled as a section label."""
    t = Text(no_wrap=True)
    t.append(f" ── {name.upper()}", style=f"bold {_HDR_COLOR}")
    return Option(t, disabled=True)


def _footer_text() -> Text:
    t = Text(no_wrap=True)
    hints = [("↑↓", "Navigate"), ("Enter", "Select"), ("[Key]", "Direct"), ("Esc", "Cancel")]
    for i, (key, label) in enumerate(hints):
        if i:
            t.append("  ·  ", style=_DIM)
        t.append(key,         style=f"bold {_ACCENT}")
        t.append(f" {label}", style=_DIM)
    return t


# ── Header widget ─────────────────────────────────────────────────────────────

class IgorHeader(Widget):
    """Top panel: logo · tagline · version · host · health score."""

    DEFAULT_CSS = f"""
    IgorHeader {{
        height: 5;
        background: {_PANEL_BG};
        border-bottom: heavy {_BORDER};
        layout: horizontal;
        align: left middle;
        padding: 0 3;
    }}
    #header-left {{
        width: 1fr;
        height: 100%;
        align: left middle;
    }}
    #header-right {{
        width: auto;
        height: 100%;
        align: right middle;
        padding: 0 2;
    }}
    """

    def __init__(self, data: dict) -> None:
        super().__init__()
        self._data = data

    def compose(self) -> ComposeResult:
        version = self._data.get("version", "")
        host    = self._data.get("host", "")
        health  = self._data.get("health", -1)

        left = Text(no_wrap=True)
        left.append("IGOR",                    style=f"bold {_ACCENT}")
        left.append("  ·  ",                   style=_DIM)
        left.append("I Guard. Observe. Repair.", style=_DIM)
        left.append("\n")
        meta_parts = [p for p in [
            f"v{version}" if version else "",
            f"host: {host}" if host else "",
        ] if p]
        left.append("  ·  ".join(meta_parts),  style=_DIM)

        yield Static(left,                  id="header-left")
        yield Static(_health_text(health),  id="header-right")


# ── Main application ──────────────────────────────────────────────────────────

_CSS = f"""
Screen {{
    background: {_BG};
    color: {_TEXT};
}}

#main-menu {{
    height: 1fr;
    background: {_BG};
    border: none;
    scrollbar-background: {_BG};
    scrollbar-background-hover: {_BG};
    scrollbar-color: {_BORDER};
    scrollbar-color-hover: {_ACCENT};
    padding: 1 2;
}}

OptionList > .option-list--option {{
    padding: 0 1;
    color: {_TEXT};
    background: {_BG};
}}

OptionList > .option-list--option-highlighted {{
    background: {_SEL_BG};
    color: white;
    text-style: bold;
}}


OptionList > .option-list--option-disabled {{
    color: {_HDR_COLOR};
    text-style: bold;
    background: {_BG};
    padding: 0 1;
}}

#igor-footer {{
    height: 1;
    background: {_PANEL_BG};
    border-top: heavy {_BORDER};
    padding: 0 3;
    color: {_DIM};
}}
"""


class IgorTUI(App[Optional[str]]):
    """IGOR full-screen TUI main menu."""

    CSS   = _CSS
    TITLE = "IGOR"

    BINDINGS = [
        Binding("escape", "cancel", "Cancel", show=False),
    ]

    def __init__(self, data: dict) -> None:
        super().__init__()
        self._data = data
        # Flat map: UPPERCASE KEY → original key string, for direct shortcuts
        self._key_map: dict[str, str] = {}
        for section in data.get("sections", []):
            for item in section.get("items", []):
                self._key_map[item["key"].upper()] = item["key"]
        for item in data.get("recent", []):
            self._key_map.setdefault(item["key"].upper(), item["key"])

    # ── Layout ────────────────────────────────────────────────────────────────

    def compose(self) -> ComposeResult:
        yield IgorHeader(self._data)
        yield self._build_option_list()
        yield Static(_footer_text(), id="igor-footer")

    def _build_option_list(self) -> OptionList:
        opts: list = []
        seen_ids: set[str] = set()

        # Recent items get a "r:" prefix to avoid DuplicateID when the same key
        # also appears in a regular section (e.g. "A" in both recent and Advanced).
        recent = self._data.get("recent", [])
        if recent:
            opts.append(_mk_separator())
            opts.append(_section_header("recently used"))
            for item in recent[:3]:
                rid = f"r:{item['key']}"
                t = Text(no_wrap=True)
                # Strip the long "KEY — full label" format the recent file stores
                label = item.get("label", item["key"]).split(" — ")[0].split(" \u2014 ")[0]
                t.append(f"[{item['key']}]", style=f"bold {_KEY_COLOR}")
                t.append(f"  {label}", style=_DIM)
                opts.append(Option(t, id=rid))
                seen_ids.add(rid)

        for section in self._data.get("sections", []):
            opts.append(_mk_separator())
            opts.append(_section_header(section["name"]))
            for item in section.get("items", []):
                # Skip if this key was already added (shouldn't happen in sections,
                # but guard anyway)
                if item["key"] in seen_ids:
                    continue
                opts.append(_option(item))
                seen_ids.add(item["key"])

        return OptionList(*opts, id="main-menu")

    # ── Event handlers ────────────────────────────────────────────────────────

    def on_mount(self) -> None:
        self.query_one("#main-menu", OptionList).focus()

    def on_option_list_option_selected(
        self, event: OptionList.OptionSelected
    ) -> None:
        oid = event.option.id
        if oid:
            # Strip recent prefix before returning to bash
            key = oid[2:] if oid.startswith("r:") else oid
            self.exit(key)

    def on_key(self, event: events.Key) -> None:
        char = (event.character or "").upper()
        if char and char in self._key_map:
            event.stop()
            self.exit(self._key_map[char])

    def action_cancel(self) -> None:
        self.exit(None)


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    raw = sys.stdin.read().strip()
    if not raw:
        print("igor_tui: no input on stdin", file=sys.stderr)
        sys.exit(1)
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"igor_tui: bad JSON — {e}", file=sys.stderr)
        sys.exit(1)

    result = IgorTUI(data).run()
    if result:
        print(result)
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
