#!/usr/bin/env python3
"""
engine_openrouter/format_tools.py

Formats abstract tool JSON as simplified markdown for models that do not
support native tool calling (DeepSeek, Llama, Gemini-Flash, etc.).

These models receive tool descriptions as text in the system prompt.
The AI generates XML tags in its response; _extract_xml_tools() parses them.

Usage:
    echo '[...]' | python3 format_tools.py
"""

import json
import sys


def _load_tools(raw: str) -> list:
    tools = []
    for segment in raw.strip().split("\n"):
        segment = segment.strip()
        if not segment:
            continue
        try:
            data = json.loads(segment)
            if isinstance(data, list):
                tools.extend(data)
            elif isinstance(data, dict):
                tools.extend(data.get("tools", [data]))
        except json.JSONDecodeError:
            pass
    return tools


def to_markdown(tools: list) -> str:
    """Minimal markdown tool descriptions for non-native-tool-calling models."""
    if not tools:
        return ""
    lines = []
    for i, tool in enumerate(tools, start=5):
        display     = tool.get("display", tool.get("name", ""))
        desc        = tool.get("description", "")
        tier        = tool.get("tier", "CHANGE")
        xml_example = tool.get("xml_example", "")
        notes       = tool.get("notes", [])

        lines.append(f"{i}. **{display}** [{tier}]")
        if desc:
            lines.append(f"   {desc}")
        if xml_example:
            lines.append(f"   Usage: `{xml_example}`")
        for note in notes:
            lines.append(f"   Note: {note}")
        lines.append("")

    return "\n".join(lines).rstrip()


def main() -> None:
    raw   = sys.stdin.read()
    tools = _load_tools(raw)
    print(to_markdown(tools))


if __name__ == "__main__":
    main()
