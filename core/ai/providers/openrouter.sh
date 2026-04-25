#!/bin/bash
# ==============================================================================
#  IGOR — ai/providers/openrouter.sh
#  OpenRouter provider plugin (OpenAI-compatible API, 200+ models).
#
#  API Key: ~/.nexus_or_key or OPENROUTER_API_KEY env var
#  Endpoint: https://openrouter.ai/api/v1/chat/completions
#  Format:  OpenAI SSE streaming
# ==============================================================================

_PROVIDER_NAME="openrouter"
_PROVIDER_KEY_FILE="$HOME/.nexus_or_key"
_PROVIDER_KEY_ENV="OPENROUTER_API_KEY"
_PROVIDER_NEXUS_ID="openrouter"

_PROVIDER_MODELS=(
    "google/gemini-2.5-flash"
    "google/gemini-2.5-pro"
    "deepseek/deepseek-v3.2-speciale"
    "deepseek/deepseek-v3-2-speciale"
    "deepseek/deepseek-r1"
    "meta-llama/llama-3.3-70b-instruct"
    "openai/gpt-4o-mini"
    "openai/gpt-4o"
    "anthropic/claude-haiku-4-5"
    "anthropic/claude-sonnet-4-5"
)

# ── Get provider display name ─────────────────────────────────────────────────
_provider_get_name() {
    echo "OpenRouter"
}

# ── Get API key ───────────────────────────────────────────────────────────────
_provider_get_key() {
    local key="${OPENROUTER_API_KEY:-}"
    [ -z "$key" ] && [ -f "$_PROVIDER_KEY_FILE" ] && key=$(cat "$_PROVIDER_KEY_FILE" 2>/dev/null)
    echo "${key}"
}

# ── Get API endpoint ──────────────────────────────────────────────────────────
_provider_get_endpoint() {
    echo "https://openrouter.ai/api/v1/chat/completions"
}

# ── Get request headers ───────────────────────────────────────────────────────
_provider_get_headers() {
    local api_key="$1"
    echo "Content-Type: application/json"
    echo "Authorization: Bearer ${api_key}"
    echo "HTTP-Referer: ${IGOR_GITHUB_URL:-https://github.com/yourusername/igor}"
    echo "X-Title: ${IGOR_APP_TITLE:-IGOR}"
    echo "Accept: text/event-stream"
}

# ── Build request body ────────────────────────────────────────────────────────
# OpenRouter uses OpenAI format: system injected as first message with role "system"
_provider_build_request() {
    local system="$1" conversation="$2" model="$3" max_tokens="$4"
    python3 -c "
import json, os
system = os.environ.get('_PR_SYSTEM','')
conv   = os.environ.get('_PR_CONV','[]')
model  = os.environ.get('_PR_MODEL','google/gemini-2.5-flash')
mt     = int(os.environ.get('_PR_MAX','2048'))
try:
    msgs = json.loads(conv)
except:
    msgs = []
or_msgs = []
if system:
    or_msgs.append({'role':'system','content':system})
or_msgs.extend(msgs)
print(json.dumps({'model':model,'max_tokens':mt,'messages':or_msgs,'stream':True}))
" _PR_SYSTEM="$system" _PR_CONV="$conversation" _PR_MODEL="$model" _PR_MAX="$max_tokens"
}

# ── Parse SSE stream ──────────────────────────────────────────────────────────
_provider_parse_stream() {
    while IFS= read -r line; do
        if [[ "$line" == data:* ]]; then
            local data="${line#data: }"
            [ "$data" = "[DONE]" ] && break
            local content
            content=$(echo "$data" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    delta = d.get('choices',[{}])[0].get('delta',{})
    print(delta.get('content',''), end='')
except: pass
" 2>/dev/null)
            [ -n "$content" ] && echo "$content"
        fi
    done
}

# ── Check availability (validate key) ─────────────────────────────────────────
_provider_check_available() {
    local key; key=$(_provider_get_key)
    [ -z "$key" ] && return 1
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
        -H "Authorization: Bearer ${key}" \
        "https://openrouter.ai/api/v1/auth/key" 2>/dev/null)
    [ "$code" = "200" ]
}

# ── Get available models ──────────────────────────────────────────────────────
_provider_get_models() {
    local json=""
    for m in "${_PROVIDER_MODELS[@]}"; do
        json+="{\"id\":\"${m}\",\"name\":\"${m}\"},"
    done
    echo "[${json%,}]"
}

# ── Get default model ─────────────────────────────────────────────────────────
_provider_get_default_model() {
    echo "google/gemini-2.5-flash"
}

# ── Validate model ────────────────────────────────────────────────────────────
_provider_validate_model() {
    local model="$1"
    for m in "${_PROVIDER_MODELS[@]}"; do
        [ "$m" = "$model" ] && return 0
    done
    return 1
}

# ── Get pricing info ──────────────────────────────────────────────────────────
_provider_get_pricing() {
    cat <<EOF
{
  "provider": "openrouter",
  "free": false,
  "note": "Pricing per million tokens. See https://openrouter.ai/models",
  "models": {
    "google/gemini-2.5-flash":              {"input": 0.15, "output": 0.60},
    "google/gemini-2.5-pro":                {"input": 1.25, "output": 10.00},
    "deepseek/deepseek-v3.2-speciale":      {"input": 0.27, "output": 0.41},
    "deepseek/deepseek-r1":                 {"input": 0.55, "output": 2.19},
    "meta-llama/llama-3.3-70b-instruct":    {"input": 0.00, "output": 0.00},
    "openai/gpt-4o-mini":                   {"input": 0.15, "output": 0.60},
    "openai/gpt-4o":                        {"input": 2.50, "output": 10.00}
  }
}
EOF
}
