#!/bin/bash
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/control.sh"

_ai_prepare_transport() {
    [ "${IGOR_AI_ENABLED:-true}" = true ] || { printf 'ERROR: AI disabled by policy\n'; return 1; }
    case "${NEXUS_PROVIDER:-anthropic}" in
        anthropic|openrouter|ollama) ;;
        *) printf 'ERROR: Unsupported AI provider\n'; return 1 ;;
    esac
    [ -n "${IGOR_AI_REQUEST_ID:-}" ] || ai_begin_request || return 1
    ai_export_privacy_map || return 1
    export IGOR_AI_ROLE_BINDINGS IGOR_AI_REQUEST_TYPE IGOR_AI_TEXT_ONLY
    IGOR_AI_ROUTING=$(python3 "${_AI_CONTROL_DIR}/role_transport.py") || return 1
    local -a _route_fields
    mapfile -t _route_fields < <(printf '%s' "$IGOR_AI_ROUTING" | python3 -c '
import json,sys
r=json.load(sys.stdin)
for key in ("status", "provider", "model", "selected_role"):
    print(r.get(key) or "")
')
    if [ "${_route_fields[0]:-}" != selected ]; then
        PYTHONPATH="${_AI_CONTROL_DIR}" IGOR_AI_ROUTING="$IGOR_AI_ROUTING" python3 -c '
import json,os
from request_context import publish
publish({"request_id": os.environ.get("IGOR_AI_REQUEST_ID", ""), "routing": json.loads(os.environ["IGOR_AI_ROUTING"]), "outcome": "not_invoked"})
' 2>/dev/null || true
        printf 'ERROR: Model role unavailable or invalid\n'
        return 1
    fi
    if [ "${_route_fields[1]}" != "${NEXUS_PROVIDER:-anthropic}" ]; then
        case "${_route_fields[1]}" in
            anthropic) NEXUS_API_KEY="${ANTHROPIC_API_KEY:-}" ;;
            openrouter) NEXUS_API_KEY="${OPENROUTER_API_KEY:-}" ;;
            ollama) NEXUS_API_KEY='' ;;
        esac
    fi
    NEXUS_PROVIDER="${_route_fields[1]}"
    NEXUS_MODEL="${_route_fields[2]}"
    [ "${_route_fields[3]}" = reasoner ] || IGOR_AI_TEXT_ONLY=true
    export NEXUS_PROVIDER NEXUS_MODEL NEXUS_API_KEY IGOR_AI_ROUTING IGOR_AI_TEXT_ONLY
    if declare -f igor_active_modules >/dev/null 2>&1; then
        IGOR_AI_ACTIVE_OWNERS=$(igor_active_modules | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().split()))')
        export IGOR_AI_ACTIVE_OWNERS
    fi
    if [ "${IGOR_AI_CONTEXT:-standard}" != minimal ] && [ "${_route_fields[3]}" = reasoner ] && declare -f igor_model_list >/dev/null 2>&1; then
        IGOR_AI_MODEL_SNAPSHOT=$(igor_model_list) || return 1
        export IGOR_AI_MODEL_SNAPSHOT
    fi
    if [ "${IGOR_AI_CONTEXT:-standard}" != minimal ] && [ "${_route_fields[3]}" = reasoner ] && declare -f igor_capability_list >/dev/null 2>&1; then
        IGOR_AI_CAPABILITY_SNAPSHOT=$(igor_capability_list) || return 1
        export IGOR_AI_CAPABILITY_SNAPSHOT
    fi
    source "${_AI_CONTROL_DIR}/ai_router.sh"
    ai_router_format_tools || return 1
    # Copy-ready commands and history summaries are isolated text requests.
    # Router regeneration must not silently re-enable native tools for them.
    if [ "${IGOR_AI_TEXT_ONLY:-false}" = true ]; then
        NEXUS_TOOLS_JSON='[]'
        IGOR_MODULE_TOOLS=''
        export NEXUS_TOOLS_JSON IGOR_MODULE_TOOLS
    fi
    IGOR_AI_CATALOG=$(ai_catalog_json) || return 1
    export IGOR_AI_CATALOG IGOR_AI_ENABLED IGOR_AI_ALLOWED_TOOLS IGOR_AI_DISABLED_ACTIONS
    export IGOR_AI_CONTEXT IGOR_AI_AUDIT IGOR_AI_CONTEXT_REQUEST IGOR_AI_REQUEST_MAX_BYTES
}
#  IGOR — ai/api.sh
#  Python bridge for AI API calls.
#
#  Provides:
#    _nexus_py_append()       append a message to conversation JSON
#    _nexus_validate_or_key() validate an OpenRouter API key
#    _nexus_api_call()        make an API call (sources active provider)
#    _nexus_parse_result()    decode the raw output into components
#
#  Data flow:
#    Caller sets env vars → _nexus_api_call() runs Python → stdout has result
#    Result parsed by _nexus_parse_result() into bash refs
#
#  Environment vars consumed by _nexus_api_call():
#    NEXUS_PROVIDER    "anthropic" or "openrouter"
#    NEXUS_API_KEY     API key (already selected by caller)
#    NEXUS_MODEL       model ID
#    NEXUS_MAX_TOKENS  integer
#    NEXUS_SYSTEM      system prompt string
#    NEXUS_CONV        JSON array of {role, content} messages
# ==============================================================================

# ── Append a message to the conversation JSON ─────────────────────────────────
# Preserves complete turns and the initial exchange when safe.
_nexus_py_append() {
    NEXUS_CONV="$1" NEXUS_ROLE="$2" NEXUS_MSG="$3" \
    python3 "${IGOR_DIR}/core/ai/ai_engine.py" append
}

# ── Progressive context compression (P2-3) ────────────────────────────────────
# Compresses tool output in older turns before each API call.
# Tiers: current turn full (≤4000), n-1 ≤200 chars, n-2+ ≤80 chars.
# Usage: conversation=$(_nexus_compress_conv "$conversation")
_nexus_compress_conv() {
    local _conv="$1"
    [ -z "$_conv" ] && { echo "[]"; return; }
    printf '%s' "$_conv" | python3 "${IGOR_DIR}/core/ai/ai_engine.py" compress 2>/dev/null \
        || printf '%s' "$_conv"
}

# ── Validate an Anthropic API key ──────────────────────────────────────────────
_nexus_validate_ant_key() {
    local _key="$1"
    # Quick format check first (sk-ant-...)
    [[ "$_key" =~ ^sk-ant- ]] || return 1
    # Live check via /v1/models — returns 200 with valid key, 401 otherwise
    local _code
    _code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
        -H "x-api-key: ${_key}" \
        -H "anthropic-version: 2023-06-01" \
        "https://api.anthropic.com/v1/models" 2>/dev/null)
    [ "$_code" = "200" ]
}

# ── Validate an OpenRouter API key ─────────────────────────────────────────────
_nexus_validate_or_key() {
    local _key="$1"
    local _code
    _code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
        -H "Authorization: Bearer ${_key}" \
        "https://openrouter.ai/api/v1/auth/key" 2>/dev/null)
    [ "$_code" = "200" ]
}

# ── Fetch OpenRouter account balance ────────────────────────────────────────────
# IDEA-05: Returns a human-readable balance string, or "unavailable" on error.
# Prints: "$X.XX remaining" or "unlimited" or "unavailable"
_nexus_get_or_balance() {
    local _key="$1"
    [ -z "$_key" ] && { echo "unavailable"; return; }
    local _body
    _body=$(curl -s --max-time 8 \
        -H "Authorization: Bearer ${_key}" \
        "https://openrouter.ai/api/v1/auth/key" 2>/dev/null)
    # Parse usage and limit from JSON
    printf '%s' "$_body" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin).get('data', {})
    limit = d.get('limit')        # None means unlimited
    usage = d.get('usage', 0)
    if limit is None:
        print('unlimited')
    else:
        remaining = float(limit) - float(usage)
        print(f'\${remaining:.2f} remaining (of \${float(limit):.2f})')
except Exception:
    print('unavailable')
" 2>/dev/null || echo "unavailable"
}

# ── List installed providers ─────────────────────────────────────────────────
# Scans core/ai/providers/ for *.sh files (excluding _provider_contract.sh).
# Prints one provider name per line (e.g. "anthropic", "openrouter").
_nexus_list_providers() {
    local _dir="${IGOR_DIR}/core/ai/providers"
    [ -d "$_dir" ] || return 0
    local _f
    for _f in "${_dir}"/*.sh; do
        [ -f "$_f" ] || continue
        local _name; _name=$(basename "${_f%.sh}")
        [[ "$_name" == _* ]] && continue   # skip _provider_contract.sh etc.
        printf '%s\n' "$_name"
    done
}

# ── Spinner — show progress on stderr while waiting for API response ──────────
# Usage: _nexus_spinner_start; ...; _nexus_spinner_stop
_nexus_spinner_start() {
    # Skip if not interactive or quiet mode is set
    [ -t 2 ] || return 0
    [ "${IGOR_QUIET:-}" = "1" ] && return 0
    # Skip if the tput pin status bar is already active (core.sh _ai_pin_update).
    # The pin writes to the last terminal row via tput; the spinner uses \r on the
    # current row — they conflict. When pin is active, it already shows "thinking".
    [ -n "${_AI_PIN_ROWS:-}" ] && return 0
    local _frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    (
        local i=0
        while true; do
            printf '\r  \033[36m%s\033[0m thinking…' "${_frames:$((i % ${#_frames})):1}" >&2
            sleep 0.1
            (( i++ )) || true
        done
    ) &
    _NEXUS_SPINNER_PID=$!
}

_nexus_spinner_stop() {
    if [ -n "${_NEXUS_SPINNER_PID:-}" ]; then
        kill "$_NEXUS_SPINNER_PID" 2>/dev/null
        wait "$_NEXUS_SPINNER_PID" 2>/dev/null
        printf '\r\033[K' >&2
        _NEXUS_SPINNER_PID=""
    fi
}

# ── Make an API call with real-time streaming ─────────────────────────────────
# Sources the active provider file from ai/providers/ before calling.
# Returns raw output with REPLY_START/REPLY_END markers, TOOL_B64, TOKENS_* lines.
_nexus_api_call() {
    _ai_prepare_transport || return 1
    # Source active provider for any provider-specific config/validation
    local _provider_file="${IGOR_DIR}/core/ai/providers/${NEXUS_PROVIDER:-anthropic}.sh"
    [ -f "$_provider_file" ] && source "$_provider_file"

    _nexus_spinner_start

    local _result
    # Dispatch via router (provider-aware engine selection)
    local _router="${IGOR_DIR}/core/ai/ai_router.sh"
    local _render="${IGOR_DIR}/core/ai/ai_render.py"
    if [ -f "$_router" ]; then
        # shellcheck source=/dev/null
        source "$_router"
        local _debug_flag=""
        [ "${IGOR_RENDER_DEBUG:-}" = "1" ] && _debug_flag="--debug"
        if [ -f "$_render" ]; then
            _result=$(ai_router_make_api_call \
                | python3 "$_render" ${_debug_flag:+"$_debug_flag"})
        else
            _result=$(ai_router_make_api_call)
        fi
    else
        # Fallback: direct call
        if [ -f "$_render" ]; then
            local _debug_flag=""
            [ "${IGOR_RENDER_DEBUG:-}" = "1" ] && _debug_flag="--debug"
            _result=$(python3 "${IGOR_DIR}/core/ai/ai_engine.py" call \
                | python3 "$_render" ${_debug_flag:+"$_debug_flag"})
        else
            _result=$(python3 "${IGOR_DIR}/core/ai/ai_engine.py" call)
        fi
    fi

    _nexus_spinner_stop

    # Provider selection is an administrator decision. A failure must not send
    # the same operational data to another company merely because a key exists.

    printf '%s' "$_result"
}

# ── Internal: raw API call without spinner or fallback (used by fallback path) ─
_nexus_api_call_raw() {
    _ai_prepare_transport || return 1
    local _provider_file="${IGOR_DIR}/core/ai/providers/${NEXUS_PROVIDER:-anthropic}.sh"
    [ -f "$_provider_file" ] && source "$_provider_file"

    local _router="${IGOR_DIR}/core/ai/ai_router.sh"
    local _render="${IGOR_DIR}/core/ai/ai_render.py"
    if [ -f "$_router" ]; then
        source "$_router"
        local _debug_flag=""
        [ "${IGOR_RENDER_DEBUG:-}" = "1" ] && _debug_flag="--debug"
        if [ -f "$_render" ]; then
            ai_router_make_api_call | python3 "$_render" ${_debug_flag:+"$_debug_flag"}
        else
            ai_router_make_api_call
        fi
    else
        if [ -f "$_render" ]; then
            local _debug_flag=""
            [ "${IGOR_RENDER_DEBUG:-}" = "1" ] && _debug_flag="--debug"
            python3 "${IGOR_DIR}/core/ai/ai_engine.py" call \
                | python3 "$_render" ${_debug_flag:+"$_debug_flag"}
        else
            python3 "${IGOR_DIR}/core/ai/ai_engine.py" call
        fi
    fi
}

# ── Parse result — decode output lines into named references ─────────────────
# DEPRECATED (P1-5): Silent fallback only. Primary parsing is ai_parse.py via _ai_py_parse().
# The main agentic loop now tries _ai_py_parse() first for scratchpad extraction.
# Remove this function once telemetry confirms no provider is hitting the fallback path.
_nexus_parse_result() {
    local raw="$1"
    local -n _reply_ref=$2
    local -n _cmds_ref=$3
    local -n _in_ref=$4
    local -n _out_ref=$5
    # Optional 6th: nameref for explain text
    local _explain_ref_name="${6:-}"
    # Optional 7th: nameref for think text (DeepSeek-R1 chain-of-thought)
    local _think_ref_name="${7:-}"
    # Optional 8th: nameref for scratchpad text
    local _scratchpad_ref_name="${8:-}"
    # Optional 9th: nameref for ASSISTANT_MSG_B64 (full native content array/dict)
    local _asst_msg_ref_name="${9:-}"
    # Optional 10th: nameref for TOOL_CONV_FMT (anthropic|openai|"")
    local _tconv_fmt_ref_name="${10:-}"
    # Optional 11th: nameref for EVIDENCE_REJECTED flag ("true" or "")
    local _ev_rejected_ref_name="${11:-}"
    # Optional 12th: nameref for STATUS_INJECTION_B64 decoded text
    local _ev_injection_ref_name="${12:-}"
    # Optional 13th: nameref for VALIDATION_B64 decoded JSON string
    local _validation_ref_name="${13:-}"

    _reply_ref=""
    _cmds_ref=()
    _in_ref=0
    _out_ref=0
    IGOR_RESPONSE_TRUNCATED=false
    IGOR_PROVIDER_ERROR=false
    IGOR_ERROR_KIND=""
    [ -n "$_explain_ref_name"    ] && printf -v "$_explain_ref_name"    ""
    [ -n "$_think_ref_name"      ] && printf -v "$_think_ref_name"      ""
    [ -n "$_scratchpad_ref_name" ] && printf -v "$_scratchpad_ref_name" ""
    [ -n "$_asst_msg_ref_name"  ] && printf -v "$_asst_msg_ref_name"  ""
    [ -n "$_tconv_fmt_ref_name" ] && printf -v "$_tconv_fmt_ref_name" ""
    [ -n "$_ev_rejected_ref_name"  ] && printf -v "$_ev_rejected_ref_name"  ""
    [ -n "$_ev_injection_ref_name" ] && printf -v "$_ev_injection_ref_name" ""
    [ -n "$_validation_ref_name"   ] && printf -v "$_validation_ref_name"   ""

    local in_reply=false
    while IFS= read -r line; do
        case "$line" in
            REPLY_START) in_reply=true ;;
            REPLY_END)   in_reply=false ;;
            THINK_B64:\ *)
                if [ -n "$_think_ref_name" ]; then
                    local decoded_think
                    decoded_think=$(printf '%s' "${line#THINK_B64: }" | base64 -d 2>/dev/null)
                    printf -v "$_think_ref_name" '%s' "$decoded_think"
                fi
                ;;
            EXPLAIN_B64:\ *)
                if [ -n "$_explain_ref_name" ]; then
                    local decoded_explain
                    decoded_explain=$(printf '%s' "${line#EXPLAIN_B64: }" | base64 -d 2>/dev/null)
                    printf -v "$_explain_ref_name" '%s' "$decoded_explain"
                fi
                ;;
            SCRATCHPAD_B64:\ *)
                if [ -n "$_scratchpad_ref_name" ]; then
                    local decoded_scratchpad
                    decoded_scratchpad=$(printf '%s' "${line#SCRATCHPAD_B64: }" | base64 -d 2>/dev/null)
                    printf -v "$_scratchpad_ref_name" '%s' "$decoded_scratchpad"
                fi
                ;;
            TOOL_B64:\ *)
                local decoded
                decoded=$(printf '%s' "${line#TOOL_B64: }" | base64 -d 2>/dev/null)
                [ -n "$decoded" ] && _cmds_ref+=("$decoded")
                ;;
            CMD_B64:\ *)
                local decoded
                decoded=$(printf '%s' "${line#CMD_B64: }" | base64 -d 2>/dev/null)
                [ -n "$decoded" ] && _cmds_ref+=("{\"tool\":\"execute\",\"cmd\":$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$decoded")}")
                ;;
            TOKENS_IN:\ *)  _in_ref="${line#TOKENS_IN: }" ;;
            TOKENS_OUT:\ *) _out_ref="${line#TOKENS_OUT: }" ;;
            TRUNCATED:\ *)  IGOR_RESPONSE_TRUNCATED=true ;;
            PROVIDER_ERROR:\ *) IGOR_PROVIDER_ERROR=true ;;
            ERROR_KIND:\ *) IGOR_ERROR_KIND="${line#ERROR_KIND: }" ;;
            ASSISTANT_MSG_B64:\ *)
                if [ -n "$_asst_msg_ref_name" ]; then
                    local decoded_asst
                    decoded_asst=$(printf '%s' "${line#ASSISTANT_MSG_B64: }" | base64 -d 2>/dev/null)
                    printf -v "$_asst_msg_ref_name" '%s' "$decoded_asst"
                fi
                ;;
            TOOL_CONV_FMT:\ *)
                [ -n "$_tconv_fmt_ref_name" ] && printf -v "$_tconv_fmt_ref_name" '%s' "${line#TOOL_CONV_FMT: }"
                ;;
            EVIDENCE_REJECTED:\ *)
                [ -n "$_ev_rejected_ref_name" ] && printf -v "$_ev_rejected_ref_name" "true"
                ;;
            STATUS_INJECTION_B64:\ *)
                if [ -n "$_ev_injection_ref_name" ]; then
                    local _decoded_ev_inj
                    _decoded_ev_inj=$(printf '%s' "${line#STATUS_INJECTION_B64: }" | base64 -d 2>/dev/null)
                    printf -v "$_ev_injection_ref_name" '%s' "$_decoded_ev_inj"
                fi
                ;;
            VALIDATION_B64:\ *)
                if [ -n "$_validation_ref_name" ]; then
                    local _decoded_val
                    _decoded_val=$(printf '%s' "${line#VALIDATION_B64: }" | base64 -d 2>/dev/null)
                    printf -v "$_validation_ref_name" '%s' "$_decoded_val"
                fi
                ;;
            *)
                if $in_reply; then
                    [ -n "$_reply_ref" ] && _reply_ref+=$'\n'
                    _reply_ref+="$line"
                fi
                ;;
        esac
    done <<< "$raw"
}

# ── P1-4: Bridge to lib/ai_parse.py ──────────────────────────────────────────
# Parse raw AI response text into structured JSON using the standalone parser.
# Input:  raw response text (with tool tags intact) via $1
# Output: JSON to stdout (see lib/ai_parse.py for schema)
# Falls back to empty JSON on error — callers must handle gracefully.
_ai_py_parse() {
    local _raw="$1"
    local _lib="${IGOR_DIR}/lib/ai_parse.py"
    if [ ! -f "$_lib" ]; then
        printf '{"scratchpad":null,"tool_calls":[],"reply":null,"raw_reasoning":"","parse_errors":["ai_parse.py not found"]}'
        return 1
    fi
    printf '%s' "$_raw" | python3 "$_lib" 2>/dev/null \
        || printf '{"scratchpad":null,"tool_calls":[],"reply":null,"raw_reasoning":"","parse_errors":["ai_parse.py failed"]}'
}

# ── P1-4: Bridge to lib/ai_validate.py ───────────────────────────────────────
# Validate a single tool_call JSON dict before execution.
# Input:  tool_call JSON dict via $1  e.g. '{"tool":"host","cmd":"df -h"}'
# Output: verdict JSON to stdout:
#         {"valid":true,"warnings":[],"blocked":false,"block_reason":null}
# On any error, returns a permissive verdict (fail-open) so Igor keeps working.
_ai_validate_tool_call() {
    local _tool_json="$1"
    local _raw
    _raw=$(NEXUS_TOOL_JSON="$_tool_json" python3 "${IGOR_DIR}/core/ai/ai_engine.py" validate 2>/dev/null)
    if [ -z "$_raw" ]; then
        # Fail-open: if engine unavailable, allow execution
        printf 'VALID: true\nBLOCKED: false\nREASON: \nWARNINGS: \n'
    else
        printf '%s\n' "$_raw"
    fi
}
