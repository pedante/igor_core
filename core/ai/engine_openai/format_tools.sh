#!/bin/bash
# ==============================================================================
#  engine_openai/format_tools.sh
#
#  Formats abstract module tool JSON for OpenAI-native models.
#
#  Reads:  IGOR_TOOLS_JSON
#  Sets:   IGOR_MODULE_TOOLS — cleared (tools are in API payload, not system prompt)
#          NEXUS_TOOLS_JSON  — OpenAI function-calling schemas for API payload
#
#  OpenAI models ignore long system prompts and perform poorly with XML tags.
#  Tools are passed as native function definitions; system prompt is XML-free.
# ==============================================================================

format_tools_for_prompt() {
    # OpenAI: remove tools from system prompt — they belong in the API payload.
    IGOR_MODULE_TOOLS=""
    export IGOR_MODULE_TOOLS
}

format_tools_for_api() {
    local _json="${IGOR_TOOLS_JSON:-[]}"
    local _py="${IGOR_DIR}/core/ai/engine_openai/format_tools.py"
    if [ -f "$_py" ] && [ -n "$_json" ] && [ "$_json" != "[]" ]; then
        NEXUS_TOOLS_JSON=$(printf '%s\n' "$_json" | python3 "$_py" 2>/dev/null || echo "[]")
    else
        NEXUS_TOOLS_JSON="[]"
    fi
    export NEXUS_TOOLS_JSON
}
