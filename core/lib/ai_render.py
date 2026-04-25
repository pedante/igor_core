#!/usr/bin/env python3
"""
ai_render.py — System Prompt Renderer for IGOR

Renders lib/prompts/system_prompt.md by substituting placeholders:
  {{MODULE_TOOLS}}     <- os.environ.get("IGOR_MODULE_TOOLS", "")
  {{MODULE_TIERS}}     <- os.environ.get("IGOR_MODULE_TIERS", "")
  {{MODULE_KNOWLEDGE}} <- os.environ.get("IGOR_MODULE_KNOWLEDGE", "")
  {{KNOWLEDGE}}        <- os.environ.get("IGOR_KNOWLEDGE", "")
  {{CONTEXT}}          <- os.environ.get("IGOR_CONTEXT", "")
  {{MODEL_OVERRIDE}}   <- content of lib/prompts/model_overrides/<family>.md

Injection order: MODULE_TOOLS → MODULE_TIERS → MODULE_KNOWLEDGE →
                 KNOWLEDGE → CONTEXT → MODEL_OVERRIDE.

Usage:
    IGOR_MODULE_TOOLS="..." IGOR_MODULE_TIERS="..." IGOR_MODULE_KNOWLEDGE="..." \
    IGOR_KNOWLEDGE="..." IGOR_CONTEXT="..." python3 lib/ai_render.py <model_id>

Exit codes:
    0 — success, rendered prompt on stdout
    1 — template file not found (caller should use fallback)

Note: This file is core/lib/ai_render.py — the system prompt renderer.
      There is a SEPARATE core/ai/ai_render.py — the terminal output renderer.
      These are intentionally different files with different purposes.
"""

import os
import re
import sys


def detect_family(model_id: str) -> str:
    """Map a model ID string to an override family name."""
    m = model_id.lower()
    if "claude" in m:
        return "claude"
    if "deepseek" in m:
        return "deepseek"
    return "openai"


def main() -> None:
    model_id = sys.argv[1] if len(sys.argv) > 1 else ""

    # Locate files relative to this script's directory (lib/)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    template_path = os.path.join(script_dir, "prompts", "system_prompt.md")

    if not os.path.exists(template_path):
        print(f"ai_render.py: template not found: {template_path}", file=sys.stderr)
        sys.exit(1)

    with open(template_path, "r", encoding="utf-8") as fh:
        prompt = fh.read()

    # Inject module-provided content first (tools, tiers, knowledge).
    # When a section is empty, strip its header too — avoids confusing the AI
    # with an empty section and saves tokens.
    module_tools     = os.environ.get("IGOR_MODULE_TOOLS", "")
    module_tiers     = os.environ.get("IGOR_MODULE_TIERS", "")
    module_knowledge = os.environ.get("IGOR_MODULE_KNOWLEDGE", "")

    if module_tools:
        prompt = prompt.replace("{{MODULE_TOOLS}}", module_tools)
    else:
        # Remove the ━━━ MODULE TOOLS ━━━ banner and blank line before the placeholder
        prompt = re.sub(
            r'\n━+\s+MODULE TOOLS\s+━+[^\n]*\n+\{\{MODULE_TOOLS\}\}',
            '',
            prompt,
        )
        prompt = prompt.replace("{{MODULE_TOOLS}}", "")

    prompt = prompt.replace("{{MODULE_TIERS}}", module_tiers)

    if module_knowledge:
        prompt = prompt.replace("{{MODULE_KNOWLEDGE}}", module_knowledge)
    else:
        # Remove Section 5 entirely when no module knowledge is loaded
        prompt = re.sub(
            r'\n## Section 5: Module Knowledge\n+\{\{MODULE_KNOWLEDGE\}\}',
            '',
            prompt,
        )
        prompt = prompt.replace("{{MODULE_KNOWLEDGE}}", "")

    # Inject KNOWLEDGE and CONTEXT using os.environ.get so missing vars → ""
    knowledge = os.environ.get("IGOR_KNOWLEDGE", "")
    context = os.environ.get("IGOR_CONTEXT", "")
    prompt = prompt.replace("{{KNOWLEDGE}}", knowledge)
    prompt = prompt.replace("{{CONTEXT}}", context)

    # Inject MODEL_OVERRIDE last — after all other substitutions are in place
    family = detect_family(model_id)
    override_path = os.path.join(
        script_dir, "prompts", "model_overrides", f"{family}.md"
    )
    override = ""
    if os.path.exists(override_path):
        with open(override_path, "r", encoding="utf-8") as fh:
            override = fh.read().strip()
    prompt = prompt.replace("{{MODEL_OVERRIDE}}", override)

    # Write to stdout without adding a trailing newline (caller controls spacing).
    # Reconfigure stdout for UTF-8 to handle Unicode characters on Windows.
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    sys.stdout.write(prompt)


if __name__ == "__main__":
    main()
