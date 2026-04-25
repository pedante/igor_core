#!/bin/bash
# ==============================================================================
#  engine_anthropic/format_tools.sh
#
#  Formats abstract module tool JSON for the Anthropic engine.
#
#  Reads:  IGOR_TOOLS_JSON  — merged JSON array of abstract tool defs
#  Sets:   IGOR_MODULE_TOOLS — XML tool definitions for system prompt injection
#          NEXUS_TOOLS_JSON  — Anthropic native tool_use schemas for API payload
#
#  Both formats are populated because Anthropic benefits from XML descriptions
#  in the system prompt AND native tool_use schemas in the API payload.
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
    local _json="${IGOR_TOOLS_JSON:-[]}"
    local _py="${IGOR_DIR}/core/ai/engine_anthropic/format_tools.py"
    if [ -f "$_py" ] && [ -n "$_json" ] && [ "$_json" != "[]" ]; then
        NEXUS_TOOLS_JSON=$(printf '%s\n' "$_json" | python3 "$_py" schema 2>/dev/null || echo "[]")
    else
        NEXUS_TOOLS_JSON="[]"
    fi
    export NEXUS_TOOLS_JSON
}
