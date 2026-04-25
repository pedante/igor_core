#!/bin/bash
# ==============================================================================
#  engine_anthropic/build_prompt.sh
#
#  Anthropic prompt strategy:
#  - Full XML-heavy system prompt (scratchpad + XML tool tags)
#  - MODULE_TOOLS already set to XML by format_tools.sh
#  - No changes needed — the default ai_render.py handles it
# ==============================================================================

engine_build_system_prompt() {
    # Anthropic uses the full XML prompt — nothing to adjust.
    # IGOR_MODULE_TOOLS is already set to XML by format_tools_for_prompt().
    : # no-op
}
