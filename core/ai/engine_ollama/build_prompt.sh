#!/bin/bash
# ==============================================================================
#  engine_ollama/build_prompt.sh
#
#  Ollama prompt strategy:
#  - Most local models handle XML tool tags via system prompt
#  - No native tool_use API (function calling varies by model)
#  - Use XML-style system prompt (same approach as engine_anthropic)
#  - IGOR_MODULE_TOOLS set to XML by format_tools.sh
# ==============================================================================

engine_build_system_prompt() {
    # Ollama uses the XML system prompt approach — no adjustments needed.
    # IGOR_MODULE_TOOLS is already set to XML by format_tools_for_prompt().
    : # no-op
}
