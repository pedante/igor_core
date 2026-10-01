"""Bind administrator role settings for the existing Bash transport.

Output contains non-secret routing metadata only. No provider calls or probes.
"""
import json
import os

from model_roles import route_model


def from_environment():
    primary = {"provider": os.environ.get("NEXUS_PROVIDER", "anthropic"),
               "model": os.environ.get("NEXUS_MODEL") or "claude-haiku-4-5-20251001",
               "tools": True, "output_formats": ["text", "json"]}
    try:
        text = os.environ.get("IGOR_AI_ROLE_BINDINGS", "{}")
        if len(text.encode()) > 4096:
            raise ValueError("role configuration too large")
        bindings = json.loads(text)
    except (ValueError, TypeError):
        return {"status": "invalid", "rule": "closed_role_configuration",
                "reason": "invalid_role_configuration", "selected_role": None}
    return route_model(os.environ.get("IGOR_AI_REQUEST_TYPE", "conversation"), primary, bindings,
                       enabled=os.environ.get("IGOR_AI_ENABLED", "true") == "true",
                       required_output="text",
                       tools_allowed=os.environ.get("IGOR_AI_TEXT_ONLY", "false") != "true")


if __name__ == "__main__":
    try:
        record = from_environment()
        print(json.dumps(record, separators=(",", ":")))
    except (ValueError, TypeError, KeyError):
        print('{"status":"unavailable","reason":"invalid_role_configuration"}')
