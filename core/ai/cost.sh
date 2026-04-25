#!/bin/bash
# ==============================================================================
#  IGOR — ai/cost.sh
#  Token cost tracking and session banner.
#
#  Provides:
#    ai_set_cost_rates()    set per-model rates after model is finalised
#    ai_add_cost()          accumulate token costs for the session
#    ai_banner()            print current session cost/token status
# ==============================================================================

# ── Session totals (reset at session start) ───────────────────────────────────
AI_COST_INPUT_PER_M=0.80
AI_COST_OUTPUT_PER_M=4.00
AI_SESSION_INPUT_TOKENS=0
AI_SESSION_OUTPUT_TOKENS=0
AI_SESSION_COST="0.000000"

# ── Mode tracking ─────────────────────────────────────────────────────────────
# (Removed: AI_MODE, AI_TASK_LIST, AI_CURRENT_TASK - THK/ACT mode removed)


# ── Per-model rate table (per million tokens, input:output) ───────────────────
# Keys MUST match exactly what goes into $model / $model_think / $model_act.
declare -gA _OR_MODEL_RATES=(
    # Anthropic (direct)
    ["claude-haiku-4-5-20251001"]="0.80:4.00"
    ["claude-haiku-4-5"]="0.80:4.00"
    ["claude-sonnet-4-5"]="3.00:15.00"
    ["claude-sonnet-4-6"]="3.00:15.00"
    ["claude-opus-4-6"]="15.00:75.00"
    # Anthropic via OpenRouter (prefixed)
    ["anthropic/claude-haiku-4-5-20251001"]="0.80:4.00"
    ["anthropic/claude-haiku-4-5"]="0.80:4.00"
    ["anthropic/claude-sonnet-4-5-20251001"]="3.00:15.00"
    ["anthropic/claude-sonnet-4-5"]="3.00:15.00"
    ["anthropic/claude-sonnet-4-6"]="3.00:15.00"
    # Google
    ["google/gemini-2.5-flash"]="0.15:0.60"
    ["google/gemini-2.5-pro"]="1.25:10.00"
    ["google/gemini-flash-1.5"]="0.075:0.30"
    # OpenAI
    ["openai/gpt-4o-mini"]="0.15:0.60"
    ["openai/gpt-4o"]="2.50:10.00"
    # Meta
    ["meta-llama/llama-3.3-70b-instruct"]="0.00:0.00"
    ["meta-llama/llama-3.1-8b-instruct"]="0.00:0.00"
    # DeepSeek — all known variants
    ["deepseek/deepseek-chat-v3-0324"]="0.20:0.77"
    ["deepseek/deepseek-v3"]="0.27:1.10"
    ["deepseek/deepseek-v3.2-speciale"]="0.27:0.41"
    ["deepseek/deepseek-r1"]="0.55:2.19"
    ["deepseek/deepseek-r1-0528"]="0.55:2.19"
    ["deepseek/deepseek-r1-distill-llama-70b"]="0.23:0.69"
    ["deepseek/deepseek-r1-distill-qwen-32b"]="0.18:0.72"
)

# ── Model context window limits (in tokens) ───────────────────────────────────
# Used by _ai_check_context_size() to warn before hitting model limits.
# Keys must match exactly what goes into $model. Default: 64000 (safest).
declare -gA _MODEL_CTX_TOKENS=(
    # Anthropic (direct) — 200k context
    ["claude-haiku-4-5-20251001"]=200000
    ["claude-haiku-4-5"]=200000
    ["claude-sonnet-4-5-20251001"]=200000
    ["claude-sonnet-4-5"]=200000
    ["claude-sonnet-4-6"]=200000
    ["claude-opus-4-6"]=200000
    # Anthropic via OpenRouter
    ["anthropic/claude-haiku-4-5-20251001"]=200000
    ["anthropic/claude-haiku-4-5"]=200000
    ["anthropic/claude-sonnet-4-5-20251001"]=200000
    ["anthropic/claude-sonnet-4-5"]=200000
    ["anthropic/claude-sonnet-4-6"]=200000
    # Google — very large context
    ["google/gemini-2.5-flash"]=1000000
    ["google/gemini-2.5-pro"]=1000000
    ["google/gemini-flash-1.5"]=1000000
    # OpenAI
    ["openai/gpt-4o"]=128000
    ["openai/gpt-4o-mini"]=128000
    # Meta
    ["meta-llama/llama-3.3-70b-instruct"]=128000
    ["meta-llama/llama-3.1-8b-instruct"]=128000
    # DeepSeek — 64k context (conservative; actual varies by endpoint)
    ["deepseek/deepseek-chat-v3-0324"]=64000
    ["deepseek/deepseek-v3"]=64000
    ["deepseek/deepseek-v3.2-speciale"]=64000
    ["deepseek/deepseek-r1"]=64000
    ["deepseek/deepseek-r1-0528"]=64000
    ["deepseek/deepseek-r1-distill-llama-70b"]=32000
    ["deepseek/deepseek-r1-distill-qwen-32b"]=32000
)

# Return context window limit for a model ID. Defaults to 64000 for unknowns.
ai_get_ctx_limit() {
    local _m="${1:-}"
    local _lim="${_MODEL_CTX_TOKENS["$_m"]:-}"
    echo "${_lim:-64000}"
}

# ── Set rates for a given model (defaults to active $model if omitted) ─────────
# BUG-FIX: quote the key in associative array lookup ("$1") to prevent bash
# treating slashes and dots in model names as arithmetic operators.
ai_set_cost_rates() {
    local lookup="${1:-${model:-}}"
    local rate="${_OR_MODEL_RATES["$lookup"]:-}"
    if [ -n "$rate" ]; then
        local in_r="${rate%%:*}"
        local out_r="${rate##*:}"
        # Guard: ensure values are valid numbers before assigning
        if [[ "$in_r"  =~ ^[0-9]+(\.[0-9]+)?$ ]] && \
           [[ "$out_r" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            AI_COST_INPUT_PER_M="$in_r"
            AI_COST_OUTPUT_PER_M="$out_r"
        else
            AI_COST_INPUT_PER_M=0.80
            AI_COST_OUTPUT_PER_M=4.00
        fi
    else
        # Fallback: Haiku rates for unknown models
        AI_COST_INPUT_PER_M=0.80
        AI_COST_OUTPUT_PER_M=4.00
    fi
}

# ── Accumulate token cost ─────────────────────────────────────────────────────
# $1=in_tokens  $2=out_tokens  $3=mode ("think"|"act"|"" — optional, for sub-totals)
ai_add_cost() {
    local in_tok="${1:-0}" out_tok="${2:-0}"
    # Guard: only add if values are integers
    [[ "$in_tok"  =~ ^[0-9]+$ ]] || in_tok=0
    [[ "$out_tok" =~ ^[0-9]+$ ]] || out_tok=0
    AI_SESSION_INPUT_TOKENS=$(( AI_SESSION_INPUT_TOKENS + in_tok ))
    AI_SESSION_OUTPUT_TOKENS=$(( AI_SESSION_OUTPUT_TOKENS + out_tok ))
    # Guard: ensure rate vars are numeric before passing to Python
    local rate_in="${AI_COST_INPUT_PER_M:-0.80}"
    local rate_out="${AI_COST_OUTPUT_PER_M:-4.00}"
    [[ "$rate_in"  =~ ^[0-9]+(\.[0-9]+)?$ ]] || rate_in=0.80
    [[ "$rate_out" =~ ^[0-9]+(\.[0-9]+)?$ ]] || rate_out=4.00
    AI_SESSION_COST=$(python3 -c "
i=${AI_SESSION_INPUT_TOKENS}; o=${AI_SESSION_OUTPUT_TOKENS}
cost = (i/1_000_000)*${rate_in} + (o/1_000_000)*${rate_out}
print(f'{cost:.6f}')
" 2>/dev/null || echo "${AI_SESSION_COST:-0.000000}")
}

# ── Session status banner ─────────────────────────────────────────────────────
ai_banner() {
    echo -e "  ${CYAN}tokens in:${NC} ${AI_SESSION_INPUT_TOKENS}  ${CYAN}out:${NC} ${AI_SESSION_OUTPUT_TOKENS}  ${YEL}session cost: \$${AI_SESSION_COST}${NC}"
    echo -e "  Mode: $mode_display  ${CYAN}Executive mode:${NC} $(${executive_mode:-false} && echo -e "${YEL}ON${NC}" || echo "off")"

    if [ "${AI_SESSION_INPUT_TOKENS:-0}" -gt 150000 ] 2>/dev/null; then
        echo -e "  ${YEL}⚠  Context large (${AI_SESSION_INPUT_TOKENS} tokens) — type 'refresh' to shrink it${NC}"
    fi
}

