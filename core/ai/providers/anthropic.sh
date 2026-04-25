#!/bin/bash
# ==============================================================================
#  IGOR — ai/providers/anthropic.sh
#  Anthropic Claude provider plugin.
#
#  API Key: ~/.nexus_api_key or ANTHROPIC_API_KEY env var
#  Endpoint: https://api.anthropic.com/v1/messages
#  Format:  Anthropic SSE streaming
# ==============================================================================

_PROVIDER_NAME="anthropic"
_PROVIDER_KEY_FILE="$HOME/.nexus_api_key"
_PROVIDER_KEY_ENV="ANTHROPIC_API_KEY"
_PROVIDER_NEXUS_ID="anthropic"

_PROVIDER_MODELS=(
    "claude-haiku-4-5-20251001"
    "claude-sonnet-4-5-20251001"
    "claude-opus-4-6"
    "claude-sonnet-4-6"
    "claude-haiku-4-5"
)

# ── Get provider display name ─────────────────────────────────────────────────
_provider_get_name() {
    echo "Anthropic"
}

# ── Get API key ───────────────────────────────────────────────────────────────
_provider_get_key() {
    local key="${ANTHROPIC_API_KEY:-}"
    [ -z "$key" ] && [ -f "$_PROVIDER_KEY_FILE" ] && key=$(cat "$_PROVIDER_KEY_FILE" 2>/dev/null)
    echo "${key}"
}

# ── Get API endpoint ──────────────────────────────────────────────────────────
_provider_get_endpoint() {
    echo "https://api.anthropic.com/v1/messages"
}

# ── Get request headers ───────────────────────────────────────────────────────
_provider_get_headers() {
    local api_key="$1"
    echo "Content-Type: application/json"
    echo "x-api-key: ${api_key}"
    echo "anthropic-version: 2023-06-01"
    echo "Accept: text/event-stream"
}

# ── Build request body ────────────────────────────────────────────────────────
_provider_build_request() {
    local system="$1" conversation="$2" model="$3" max_tokens="$4"
    python3 -c "
import json, os, sys
system = os.environ.get('_PR_SYSTEM','')
conv   = os.environ.get('_PR_CONV','[]')
model  = os.environ.get('_PR_MODEL','claude-haiku-4-5-20251001')
mt     = int(os.environ.get('_PR_MAX','2048'))
try:
    msgs = json.loads(conv)
except:
    msgs = []
print(json.dumps({'model':model,'max_tokens':mt,'system':system,'messages':msgs,'stream':True}))
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
    e = json.loads(sys.stdin.read())
    if e.get('type') == 'content_block_delta':
        print(e.get('delta',{}).get('text',''), end='')
except: pass
" 2>/dev/null)
            [ -n "$content" ] && echo "$content"
        fi
    done
}

# ── Check availability ────────────────────────────────────────────────────────
_provider_check_available() {
    local key; key=$(_provider_get_key)
    [ -n "$key" ]
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
    echo "claude-haiku-4-5-20251001"
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
  "provider": "anthropic",
  "free": false,
  "note": "Pricing per million tokens. See https://anthropic.com/pricing",
  "models": {
    "claude-haiku-4-5-20251001":  {"input": 0.80, "output": 4.00},
    "claude-sonnet-4-5-20251001": {"input": 3.00, "output": 15.00}
  }
}
EOF
}
