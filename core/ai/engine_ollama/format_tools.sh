#!/bin/bash
# ==============================================================================
#  engine_ollama/format_tools.sh
#
#  Formats abstract module tool JSON for the Ollama engine.
#
#  Reads:  IGOR_TOOLS_JSON  — merged JSON array of abstract tool defs
#  Sets:   IGOR_MODULE_TOOLS — XML tool definitions for system prompt injection
#          NEXUS_TOOLS_JSON  — empty array (Ollama uses XML tags, not native tools)
#
#  Most local models understand XML tool tags in the system prompt but don't
#  reliably support native function calling. We use the Anthropic XML formatter
#  for the prompt and leave NEXUS_TOOLS_JSON empty.
# ==============================================================================

format_tools_for_prompt() {
    local _json="${IGOR_TOOLS_JSON:-[]}"
    local _py="${IGOR_DIR}/core/ai/engine_anthropic/format_tools.py"
    if [ -f "$_py" ] && [ -n "$_json" ] && [ "$_json" != "[]" ]; then
        IGOR_MODULE_TOOLS=$(printf '%s\n' "$_json" | python3 "$_py" xml 2>/dev/null || echo "")
    else
        IGOR_MODULE_TOOLS=""
    fi
    export IGOR_MODULE_TOOLS
}

format_tools_for_api() {
    # Ollama — no native tool schemas; XML in system prompt handles everything.
    NEXUS_TOOLS_JSON="[]"
    export NEXUS_TOOLS_JSON
}
