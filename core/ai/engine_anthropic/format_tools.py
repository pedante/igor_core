#!/usr/bin/env python3
"""
engine_anthropic/format_tools.py

Reads abstract tool JSON (from stdin) and outputs one of two formats:

  mode xml    — XML tool definitions for {{MODULE_TOOLS}} system prompt injection
  mode schema — Anthropic native tool_use schemas for NEXUS_TOOLS_JSON (API payload)

Usage:
    echo '[...]' | python3 format_tools.py xml
    echo '[...]' | python3 format_tools.py schema
"""

import json
import sys


def _load_tools(raw: str) -> list:
    """Parse raw JSON (array or newline-separated arrays) into a flat tool list."""
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


def to_xml(tools: list) -> str:
    """Convert abstract tool defs to XML block for Anthropic system prompt."""
    lines = []
    for i, tool in enumerate(tools, start=5):  # core tools occupy 1-4
        display = tool.get("display", tool.get("name", ""))
        desc    = tool.get("description", "")
        xml_tag = tool.get("xml_tag", tool.get("name", ""))
        tier    = tool.get("tier", "CHANGE")
        notes   = tool.get("notes", [])
        xml_attrs_ex = tool.get("xml_attrs_example", "")
        xml_content  = tool.get("xml_content", "...")
        xml_example  = tool.get("xml_example", "")

        if xml_example:
            usage_line = f"   {xml_example}"
        elif xml_attrs_ex:
            usage_line = f"   <{xml_tag} {xml_attrs_ex}> {xml_content} </{xml_tag}>"
        else:
            usage_line = f"   <{xml_tag}> {xml_content} </{xml_tag}>"

        lines.append(f"{i}. {display}:")
        lines.append(usage_line)
        if desc:
            lines.append(f"   {desc}")
        lines.append(f"   Tier: {tier}")
        for note in notes:
            lines.append(f"   {note}")
        lines.append("")

    return "\n".join(lines).rstrip()


def to_schema(tools: list) -> str:
    """Convert abstract tool defs to Anthropic native tool_use schema (for payload)."""
    schemas = []
    for tool in tools:
        name       = tool.get("name", "")
        desc       = tool.get("description", "")
        raw_params = tool.get("openai_params", {})

        if not name:
            continue

        if raw_params:
            input_schema = {
                "type": "object",
                "properties": raw_params,
                "required": list(raw_params.keys()),
            }
        else:
            # Single-parameter tool using xml_content as param name
            param_name = tool.get("xml_content", "command")
            input_schema = {
                "type": "object",
                "properties": {
                    param_name: {
                        "type": "string",
                        "description": f"The {param_name} argument",
                    }
                },
                "required": [param_name],
            }

        schemas.append({
            "name": name,
            "description": desc,
            "input_schema": input_schema,
        })

    return json.dumps(schemas)


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "xml"
    raw  = sys.stdin.read()
    tools = _load_tools(raw)

    if mode == "schema":
        print(to_schema(tools))
    else:
        print(to_xml(tools))


if __name__ == "__main__":
    main()
