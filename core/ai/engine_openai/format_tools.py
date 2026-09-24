#!/usr/bin/env python3
"""
engine_openai/format_tools.py

Converts abstract module tool JSON → OpenAI function-calling schema.
Output is a JSON array suitable for the API "tools" payload parameter.

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


def to_openai_schema(tools: list) -> str:
    """Convert abstract tool defs to OpenAI tool-calling schema."""
    schemas = []
    for tool in tools:
        name       = tool.get("name", "")
        desc       = tool.get("description", "")
        raw_params = tool.get("openai_params", {})

        if not name:
            continue

        if raw_params:
            params_schema = {
                "type": "object",
                "properties": raw_params,
                "required": tool.get("required", list(raw_params.keys())),
                "additionalProperties": False,
            }
        else:
            param_name = tool.get("xml_content", "command")
            params_schema = {
                "type": "object",
                "properties": {
                    param_name: {
                        "type": "string",
                        "description": f"The {param_name} argument",
                    }
                },
                "required": [param_name],
            }

        # Also include core tools that OpenAI models need natively
        schemas.append({
            "type": "function",
            "function": {
                "name": name,
                "description": desc,
                "parameters": params_schema,
            },
        })

    return json.dumps(schemas)


def main() -> None:
    raw   = sys.stdin.read()
    tools = _load_tools(raw)
    print(to_openai_schema(tools))


if __name__ == "__main__":
    main()
