#!/bin/bash
# ==============================================================================
#  IGOR — ai/providers/_provider_contract.sh
#  DOCUMENTATION ONLY — this file is never sourced.
#
#  Every provider file in ai/providers/ MUST implement these functions.
#  See docs/adding-a-provider.md for a complete walkthrough with examples.
# ==============================================================================

# ── Required metadata variables ───────────────────────────────────────────────
# Set these at the top of your provider file.
#
# _PROVIDER_NAME="myprovider"
# _PROVIDER_KEY_FILE="$HOME/.igor_myprovider_key"
# _PROVIDER_KEY_ENV="MYPROVIDER_API_KEY"   # env var that overrides key file
# _PROVIDER_NEXUS_ID="myprovider"          # value for NEXUS_PROVIDER env var
#
# Example:
#
# _PROVIDER_NAME="anthropic"
# _PROVIDER_KEY_FILE="$HOME/.nexus_api_key"
# _PROVIDER_KEY_ENV="ANTHROPIC_API_KEY"
# _PROVIDER_NEXUS_ID="anthropic"

# ── Required functions ────────────────────────────────────────────────────────

# _provider_get_name()
# Returns the display name of the provider.
# Output: string
#
# Example:
# _provider_get_name() { echo "Anthropic"; }

# _provider_get_key()
# Returns the API key. Reads from env var first, then key file.
# Output: string (empty if not found)
#
# Example:
# _provider_get_key() {
#     local key="${ANTHROPIC_API_KEY:-}"
#     [ -z "$key" ] && [ -f "$_PROVIDER_KEY_FILE" ] && key=$(cat "$_PROVIDER_KEY_FILE")
#     echo "$key"
# }

# _provider_get_endpoint()
# Returns the API endpoint URL as a string.
#
# Example:
# _provider_get_endpoint() {
#     echo "https://api.anthropic.com/v1/messages"
# }

# _provider_get_headers()
# Returns HTTP headers as newline-separated "Key: Value" strings.
# $1 = api_key
#
# Example:
# _provider_get_headers() {
#     local api_key="$1"
#     echo "Content-Type: application/json"
#     echo "Authorization: Bearer ${api_key}"
# }

# _provider_build_request()
# Builds the JSON request body.
# $1 = system prompt (string)
# $2 = conversation history (JSON array)
# $3 = model name (string)
# $4 = max tokens (integer)
#
# Example:
# _provider_build_request() {
#     local system="$1" conversation="$2" model="$3" max_tokens="$4"
#     cat <<EOF
# {
#   "model": "${model}",
#   "messages": [${conversation}],
#   "max_tokens": ${max_tokens},
#   "stream": true
# }
# EOF
# }

# _provider_parse_stream()
# Parses the SSE stream from curl and outputs content tokens.
# Input: raw SSE stream from curl via stdin
# Output: content tokens, one per line
#
# Example (OpenAI SSE format):
# _provider_parse_stream() {
#     while IFS= read -r line; do
#         if [[ "$line" =~ ^data: ]]; then
#             local data="${line#data: }"
#             [ "$data" = "[DONE]" ] && break
#             local content
#             content=$(echo "$data" | python3 -c "
# import sys, json
# try:
#     d = json.loads(sys.stdin.read())
#     delta = d.get('choices',[{}])[0].get('delta',{})
#     print(delta.get('content',''), end='')
# except: pass
# " 2>/dev/null)
#             [ -n "$content" ] && echo "$content"
#         fi
#     done
# }

# ── Optional functions ────────────────────────────────────────────────────────

# _provider_check_available()
# Returns 0 if provider is reachable, 1 otherwise.

# _provider_get_models()
# Returns available model IDs as a JSON array.

# _provider_get_default_model()
# Returns the recommended default model ID for this provider.

# _provider_validate_model()
# $1 = model ID — returns 0 if valid, 1 if not.

# _provider_get_pricing()
# Returns JSON with pricing info:
# { "provider": "name", "free": false, "input_cost_per_m": 0.80, "output_cost_per_m": 4.00 }
