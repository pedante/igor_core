#!/bin/bash
# ==============================================================================
#  engine_openrouter/build_prompt.sh
#
#  Model-aware prompt building for OpenRouter.
#
#    anthropic/* or *claude-*  → Full XML prompt (same as engine_anthropic)
#    openai/* or *gpt-*        → OpenAI-style adjustments
#    everything else           → Default prompt with markdown tool descriptions
# ==============================================================================

engine_build_system_prompt() {
    local model="${NEXUS_MODEL:-}"
    case "$model" in
        anthropic/*|*claude-*)
            local _ant="${IGOR_DIR}/core/ai/engine_anthropic/build_prompt.sh"
            [ -f "$_ant" ] && { source "$_ant"; engine_build_system_prompt; }
            ;;
        openai/*|*gpt-4*|*gpt-3.5*)
            local _oai="${IGOR_DIR}/core/ai/engine_openai/build_prompt.sh"
            [ -f "$_oai" ] && { source "$_oai"; engine_build_system_prompt; }
            ;;
        *)
            # Generic XML mode — markdown tools already in IGOR_MODULE_TOOLS,
            # deepseek.md model override is applied automatically by ai_render.py
            : # no-op
            ;;
    esac
}
