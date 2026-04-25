#!/bin/bash
# ==============================================================================
#  IGOR — ai/providers/ollama.sh
#  Ollama local AI provider plugin (no API key required).
#
#  Config:  IGOR_OLLAMA_HOST (default: http://127.0.0.1:11434)
#           IGOR_OLLAMA_DEFAULT_MODEL (tier-aware, set by _ollama_tier_model)
#  Endpoint: ${IGOR_OLLAMA_HOST}/api/chat
#  Format:  Ollama NDJSON streaming
#
#  Tier-based model recommendations (from core/host/profile.sh):
#    constrained  < 1GB   qwen2.5:0.5b
#    standard     1-8GB   llama3.2:3b
#    comfortable  8-32GB  llama3.1:8b
#    server       >32GB   llama3.3:70b
# ==============================================================================

_PROVIDER_NAME="ollama"
_PROVIDER_KEY_FILE=""          # no key file — Ollama runs locally
_PROVIDER_KEY_ENV=""           # no env key needed
_PROVIDER_NEXUS_ID="ollama"

# ── Tier-based model recommendation ──────────────────────────────────────────
_ollama_tier_model() {
    case "${IGOR_TIER:-standard}" in
        constrained)  echo "qwen2.5:0.5b" ;;
        standard)     echo "llama3.2:3b" ;;
        comfortable)  echo "llama3.1:8b" ;;
        server)       echo "llama3.3:70b" ;;
        *)            echo "llama3.2:3b" ;;
    esac
}

# ── Tier-based curl timeout (seconds) ────────────────────────────────────────
_ollama_tier_timeout() {
    case "${IGOR_TIER:-standard}" in
        constrained)  echo 120 ;;
        standard)     echo 90 ;;
        comfortable)  echo 60 ;;
        server)       echo 30 ;;
        *)            echo 90 ;;
    esac
}

# ── Tier-based context window (tokens) ───────────────────────────────────────
_ollama_tier_ctx() {
    case "${IGOR_TIER:-standard}" in
        constrained)  echo 4096 ;;
        standard)     echo 8192 ;;
        comfortable)  echo 16384 ;;
        server)       echo 32768 ;;
        *)            echo 8192 ;;
    esac
}

# ── Get provider display name ─────────────────────────────────────────────────
_provider_get_name() {
    echo "Ollama (local)"
}

# ── Get API key (not required for Ollama) ────────────────────────────────────
_provider_get_key() {
    echo ""   # no key
}

# ── Get API endpoint ──────────────────────────────────────────────────────────
_provider_get_endpoint() {
    echo "${IGOR_OLLAMA_HOST:-http://127.0.0.1:11434}/api/chat"
}

# ── Get request headers ───────────────────────────────────────────────────────
_provider_get_headers() {
    echo "Content-Type: application/json"
}

# ── Build request body ────────────────────────────────────────────────────────
_provider_build_request() {
    local system="$1" conversation="$2" model="$3" max_tokens="$4"
    local _ctx; _ctx=$(_ollama_tier_ctx)
    python3 -c "
import json, os
system = os.environ.get('_PR_SYSTEM','')
conv   = os.environ.get('_PR_CONV','[]')
model  = os.environ.get('_PR_MODEL','llama3.2:3b')
mt     = int(os.environ.get('_PR_MAX','2048'))
ctx    = int(os.environ.get('_PR_CTX','8192'))
temp   = float(os.environ.get('NEXUS_TEMPERATURE','0.7'))
try:
    msgs = json.loads(conv)
except:
    msgs = []
ol_msgs = []
if system:
    ol_msgs.append({'role':'system','content':system})
ol_msgs.extend(msgs)
payload = {
    'model': model,
    'messages': ol_msgs,
    'stream': True,
    'options': {
        'num_ctx': ctx,
        'num_predict': mt,
        'temperature': temp,
    }
}
print(json.dumps(payload))
" _PR_SYSTEM="$system" _PR_CONV="$conversation" _PR_MODEL="$model" _PR_MAX="$max_tokens" _PR_CTX="$_ctx"
}

# ── Parse NDJSON stream (Ollama format) ───────────────────────────────────────
# Ollama sends newline-delimited JSON, NOT SSE (no "data: " prefix).
_provider_parse_stream() {
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local content
        content=$(echo "$line" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    content = d.get('message', {}).get('content', '')
    if content:
        print(content, end='')
except: pass
" 2>/dev/null)
        [ -n "$content" ] && echo "$content"
    done
}

# ── Check availability (ping /api/tags) ──────────────────────────────────────
_provider_check_available() {
    local _host="${IGOR_OLLAMA_HOST:-http://127.0.0.1:11434}"
    local _code
    _code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        "${_host}/api/tags" 2>/dev/null)
    [ "$_code" = "200" ]
}

# ── Get available models from running Ollama instance ─────────────────────────
_provider_get_models() {
    local _host="${IGOR_OLLAMA_HOST:-http://127.0.0.1:11434}"
    local _body
    _body=$(curl -s --max-time 8 "${_host}/api/tags" 2>/dev/null)
    if [ -z "$_body" ]; then
        echo "[]"
        return
    fi
    python3 -c "
import sys, json
try:
    d = json.loads('''$_body''')
    models = d.get('models', [])
    out = [{'id': m.get('name',''), 'name': m.get('name','')} for m in models]
    print(json.dumps(out))
except:
    print('[]')
" 2>/dev/null || echo "[]"
}

# ── Get default model (tier-aware) ───────────────────────────────────────────
_provider_get_default_model() {
    echo "${IGOR_OLLAMA_DEFAULT_MODEL:-$(_ollama_tier_model)}"
}

# ── Validate model (check it's pulled on the running instance) ───────────────
_provider_validate_model() {
    local _model="$1"
    local _models
    _models=$(_provider_get_models)
    python3 -c "
import sys, json
models_json = '''$_models'''
model = '$_model'
try:
    models = json.loads(models_json)
    ids = [m.get('id','') for m in models]
    sys.exit(0 if model in ids else 1)
except:
    sys.exit(1)
" 2>/dev/null
}

# ── Get pricing info (free — runs locally) ───────────────────────────────────
_provider_get_pricing() {
    cat <<EOF
{
  "provider": "ollama",
  "free": true,
  "note": "Runs locally — no API costs. Hardware resources only.",
  "models": {}
}
EOF
}
