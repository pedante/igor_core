#!/bin/bash
# ==============================================================================
#  engine_openai/build_prompt.sh
#
#  OpenAI prompt strategy:
#  - Tools removed from system prompt (handled by format_tools.sh already)
#  - System prompt shortened: OpenAI models work better with concise instructions
#  - Scratchpad format kept as-is (GPT-4o handles JSON in XML tags adequately)
#
#  The model_overrides/openai.md file can add OpenAI-specific behavioral nudges
#  (e.g., "Do not use markdown wrappers around tool calls").
# ==============================================================================

engine_build_system_prompt() {
    # format_tools_for_prompt() already cleared IGOR_MODULE_TOOLS.
    # The model override file (lib/prompts/model_overrides/openai.md) is loaded
    # automatically by ai_render.py when the model family is "openai".
    # Nothing else to do here — extend this function for OpenAI-specific
    # prompt restructuring if needed in the future.
    : # no-op for now
}
