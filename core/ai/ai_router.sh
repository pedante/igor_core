#!/bin/bash
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/control.sh"
#  IGOR — ai/ai_router.sh
#  Provider engine dispatcher.
#
#  Provides:
#    ai_router_format_tools()    Collect abstract tool JSON from module hooks,
#                                delegate to the active engine's format_tools.sh,
#                                sets IGOR_MODULE_TOOLS and NEXUS_TOOLS_JSON.
#
#    ai_router_make_api_call()   Source the active engine's api_client.sh and
#                                call engine_make_api_call().
#
#  Engine selection:
#    NEXUS_PROVIDER=anthropic   → engine_anthropic/
#    NEXUS_PROVIDER=openrouter  → engine_openrouter/  (model-aware internally)
#    NEXUS_PROVIDER=openai      → engine_openai/      (reserved for direct OAI)
#    unknown                    → rejected
#
#  Environment vars read:
#    NEXUS_PROVIDER, NEXUS_MODEL, IGOR_DIR
#
#  Environment vars written (by format_tools):
#    IGOR_MODULE_TOOLS   — XML / markdown tool definitions for system prompt
#    NEXUS_TOOLS_JSON    — Native tool schemas for API payload
#    IGOR_TOOLS_JSON     — Raw merged abstract JSON (intermediate, for debugging)
# ==============================================================================

# ── Select engine directory ────────────────────────────────────────────────────
_ai_router_engine_dir() {
    local _provider="${NEXUS_PROVIDER:-anthropic}"
    case "$_provider" in
        anthropic|openai|openrouter|ollama) ;;
        *) printf 'Unsupported AI provider.\n' >&2; return 1 ;;
    esac
    local _dir="${IGOR_DIR}/core/ai/engine_${_provider}"
    if [ ! -d "$_dir" ]; then
        # Unknown provider — fall back to Anthropic XML strategy
        _dir="${IGOR_DIR}/core/ai/engine_anthropic"
    fi
    echo "$_dir"
}

# ── Merge module tool JSON from all registered ai_tools hooks ──────────────────
# Each hook outputs a compact single-line JSON array.
# This function aggregates them into one flat array in IGOR_TOOLS_JSON.
_ai_router_collect_tools_json() {
    # The parser's supported grammar is authoritative. Modules extend it through
    # owned run_igor_action entries, not arbitrary executable schema fragments.
    local catalog
    catalog=$(ai_catalog_json) || return 1
    IGOR_TOOLS_JSON=$(printf '%s' "$catalog" | python3 -c \
        'import json,sys; print(json.dumps(json.load(sys.stdin)["tools"]))') || return 1
    export IGOR_TOOLS_JSON
    return 0
}


# ── Public: format tools for the active provider ───────────────────────────────
# Populates IGOR_MODULE_TOOLS and NEXUS_TOOLS_JSON based on provider + model.
ai_router_format_tools() {
    # 1. Collect raw abstract tool JSON from module hooks
    _ai_router_collect_tools_json || return 1

    # 2. Source and run the engine's format_tools.sh
    local _engine_dir; _engine_dir=$(_ai_router_engine_dir) || return 1
    local _fmt="${_engine_dir}/format_tools.sh"

    if [ -f "$_fmt" ]; then
        # shellcheck source=/dev/null
        source "$_fmt"
        format_tools_for_prompt
        format_tools_for_api
    else
        # Fallback: XML from Anthropic formatter if available
        local _ant="${IGOR_DIR}/core/ai/engine_anthropic/format_tools.sh"
        if [ -f "$_ant" ]; then
            source "$_ant"
            format_tools_for_prompt
            format_tools_for_api
        else
            IGOR_MODULE_TOOLS=""
            NEXUS_TOOLS_JSON="[]"
            export IGOR_MODULE_TOOLS NEXUS_TOOLS_JSON
        fi
    fi

    # 3. Run engine's build_prompt.sh hook (optional adjustments)
    local _bld="${_engine_dir}/build_prompt.sh"
    if [ -f "$_bld" ]; then
        source "$_bld"
        engine_build_system_prompt 2>/dev/null || true
    fi
}

# ── Public: make API call via the active engine ────────────────────────────────
ai_router_make_api_call() {
    local _engine_dir; _engine_dir=$(_ai_router_engine_dir) || return 1
    local _client="${_engine_dir}/api_client.sh"

    if [ -f "$_client" ]; then
        # shellcheck source=/dev/null
        source "$_client"
        engine_make_api_call
    else
        # Fallback: direct call to ai_engine.py
        python3 "${IGOR_DIR}/core/ai/ai_engine.py" call
    fi
}
