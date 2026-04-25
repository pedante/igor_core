#!/bin/bash
# ==============================================================================
#  engine_openrouter/format_tools.sh
#
#  Model-aware tool formatting for OpenRouter's 200+ model catalogue.
#
#  Decision tree (by NEXUS_MODEL):
#    anthropic/* or *claude-*  → Anthropic XML format (delegates to engine_anthropic)
#    openai/* or *gpt-*        → OpenAI schema (delegates to engine_openai)
#    everything else           → Markdown in system prompt (xml "tools_mode")
# ==============================================================================

_or_model_family() {
    local model="${NEXUS_MODEL:-}"
    case "$model" in
        anthropic/*|*claude-*) echo "anthropic" ;;
        openai/*|*gpt-4*|*gpt-3.5*) echo "openai" ;;
        *) echo "xml" ;;
    esac
}

format_tools_for_prompt() {
    local _family; _family=$(_or_model_family)
    local _json="${IGOR_TOOLS_JSON:-[]}"
    local _py="${IGOR_DIR}/core/ai/engine_openrouter/format_tools.py"

    case "$_family" in
        anthropic)
            # Delegate to Anthropic engine — XML in system prompt
            local _ant="${IGOR_DIR}/core/ai/engine_anthropic/format_tools.sh"
            [ -f "$_ant" ] && { source "$_ant"; format_tools_for_prompt; return; }
            ;;
        openai)
            # Delegate to OpenAI engine — clear system prompt tools
            local _oai="${IGOR_DIR}/core/ai/engine_openai/format_tools.sh"
            [ -f "$_oai" ] && { source "$_oai"; format_tools_for_prompt; return; }
            ;;
        xml)
            # Generic models: simplified markdown descriptions in system prompt
            if [ -f "$_py" ] && [ -n "$_json" ] && [ "$_json" != "[]" ]; then
                IGOR_MODULE_TOOLS=$(printf '%s\n' "$_json" | python3 "$_py" 2>/dev/null || echo "")
            else
                IGOR_MODULE_TOOLS=""
            fi
            export IGOR_MODULE_TOOLS
            ;;
    esac
}

format_tools_for_api() {
    local _family; _family=$(_or_model_family)

    case "$_family" in
        anthropic)
            local _ant="${IGOR_DIR}/core/ai/engine_anthropic/format_tools.sh"
            [ -f "$_ant" ] && { source "$_ant"; format_tools_for_api; return; }
            ;;
        openai)
            local _oai="${IGOR_DIR}/core/ai/engine_openai/format_tools.sh"
            [ -f "$_oai" ] && { source "$_oai"; format_tools_for_api; return; }
            ;;
        xml)
            # No native tool calling for these models
            NEXUS_TOOLS_JSON="[]"
            export NEXUS_TOOLS_JSON
            ;;
    esac
}
