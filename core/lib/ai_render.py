#!/usr/bin/env python3
"""Render stable policy and a reference envelope separated at the API boundary.

Only Igor-generated tool metadata and bundled model overrides enter policy.
The encoded envelope is an internal transport format, decoded into an untrusted
data message by core/ai/request_boundary.py before any provider call.
"""
import base64
import json
import os
import re
import sys


def detect_family(model_id: str) -> str:
    m = model_id.lower()
    if "claude" in m:
        return "claude"
    if "deepseek" in m:
        return "deepseek"
    return "openai"


def main() -> None:
    model_id = sys.argv[1] if len(sys.argv) > 1 else ""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    template_path = os.path.join(script_dir, "prompts", "system_prompt.md")
    if not os.path.exists(template_path):
        print("ai_render.py: template not found", file=sys.stderr)
        sys.exit(1)
    with open(template_path, encoding="utf-8") as handle:
        prompt = handle.read()
    override_path = os.path.join(
        script_dir, "prompts", "model_overrides", detect_family(model_id) + ".md")
    override = ""
    if os.path.exists(override_path):
        with open(override_path, encoding="utf-8") as handle:
            override = handle.read().strip()
    values = {"MODULE_TOOLS": os.environ.get("IGOR_MODULE_TOOLS", ""),
              "MODEL_OVERRIDE": override}
    # One pass: injected strings must not expand other template variables.
    prompt = re.sub(r"\{\{(MODULE_TOOLS|MODEL_OVERRIDE)\}\}",
                    lambda match: values[match[1]], prompt)
    reference = {
        "module_knowledge": os.environ.get("IGOR_MODULE_KNOWLEDGE", ""),
        "module_tier_claims": os.environ.get("IGOR_MODULE_TIERS", ""),
        "persistent_knowledge_and_reports": os.environ.get("IGOR_KNOWLEDGE", ""),
        "host_and_module_state": os.environ.get("IGOR_CONTEXT", ""),
        "administrator_reference": os.environ.get("IGOR_USER_REFERENCE", ""),
        "module_contributors": os.environ.get("IGOR_AI_CONTEXT_OWNERS", ""),
    }
    envelope = base64.b64encode(json.dumps(reference).encode()).decode()
    sys.stdout.write(prompt + "\nIGOR_REFERENCE_V1:" + envelope + "\n")


if __name__ == "__main__":
    main()
