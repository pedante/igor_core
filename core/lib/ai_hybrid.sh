#!/bin/bash
# ==============================================================================
#  IGOR — lib/ai_hybrid.sh
#  AI Hybrid menu session — inline AI in the main menu.
#
#  Called from main_menu() in igor.sh when AI_HYBRID_MODE=true.
#
#  Public functions:
#    _igor_hybrid_init()     Load AI subsystem (once), gather context
#    _igor_hybrid_ask(input) One exchange: API call + agentic tool execution
#    _igor_hybrid_reset()    Rebuild context + clear conversation (/menu reset)
# ==============================================================================

# ── Module load guard ─────────────────────────────────────────────────────────
[ "${_IGOR_HYBRID_LIB_LOADED:-false}" = "true" ] && return 0
_IGOR_HYBRID_LIB_LOADED=true

# ── Hybrid session globals ────────────────────────────────────────────────────
_IGOR_HYBRID_CONV='[]'
_IGOR_HYBRID_SYSTEM_PROMPT=''
_IGOR_HYBRID_INITIALIZED=false
_IGOR_HYBRID_ACTIVE=false  # set true once a conversation is in progress

_igor_hybrid_openrouter_cutover() {
    if declare -f _ai_openrouter_cutover >/dev/null 2>&1; then
        _ai_openrouter_cutover
        return $?
    fi
    local _root="${IGOR_DIR:-}" _data _state
    [ -n "$_root" ] || return 0
    _data="${IGOR_DATA_DIR:-${_root}/data}"
    if [ ! -f "${_root}/core/lib/configuration.py" ]; then
        [ -e "${_data}/secrets/catalog.db" ]
        return $?
    fi
    _state=$(IGOR_CONFIGURATION_ROOT="$_root" IGOR_CONFIGURATION_DATA_DIR="$_data" \
        env -u OPENROUTER_API_KEY -u OR_API_KEY -u NEXUS_API_KEY \
        python3 "${_root}/core/lib/configuration.py" openrouter-cutover-guard 2>/dev/null) || return 0
    [ "$_state" != legacy ]
}

# ── _igor_hybrid_init ─────────────────────────────────────────────────────────
# Load the AI subsystem (once) and gather server context for the system prompt.
# Returns 1 if no API key is available.
_igor_hybrid_init() {
    # Already initialised this session — no-op
    [ "${_IGOR_HYBRID_INITIALIZED:-false}" = "true" ] && return 0

    # ── Check API key ─────────────────────────────────────────────────────────
    local _hk="" _hor="" _or_available=false
    [ -f "$HOME/.nexus_api_key" ] && _hk=$(cat "$HOME/.nexus_api_key" 2>/dev/null)
    if _igor_hybrid_openrouter_cutover; then
        local _or_state
        _or_state=$(IGOR_CONFIGURATION_ROOT="$IGOR_DIR" \
            IGOR_CONFIGURATION_DATA_DIR="${IGOR_DATA_DIR:-${IGOR_DIR}/data}" \
            python3 "${IGOR_DIR}/core/lib/configuration.py" secret-status 2>/dev/null) || _or_state='{}'
        if printf '%s' "$_or_state" | python3 -c 'import json,sys; raise SystemExit(0 if json.load(sys.stdin).get("availability") == "available" else 1)' 2>/dev/null; then
            _or_available=true
        fi
        unset OPENROUTER_API_KEY OR_API_KEY NEXUS_API_KEY
    else
        [ -f "$HOME/.nexus_or_key" ] && _hor=$(cat "$HOME/.nexus_or_key" 2>/dev/null)
    fi

    if [ -z "$_hk" ] && [ -z "$_hor" ] && [ "$_or_available" != true ]; then
        return 1
    fi

    # ── Source AI subsystem if not already loaded ─────────────────────────────
    if ! declare -f _nexus_api_call &>/dev/null; then
        local _aid="${IGOR_DIR}/ai"
        source "${_aid}/scrub.sh"    2>/dev/null || true
        source "${_aid}/knowledge.sh" 2>/dev/null || true
        source "${_aid}/api.sh"      2>/dev/null || true
        source "${_aid}/cost.sh"     2>/dev/null || true
        source "${_aid}/safety.sh"   2>/dev/null || true
        source "${_aid}/context.sh"  2>/dev/null || true
    fi

    # ── Load settings ─────────────────────────────────────────────────────────
    local _AI_SETTINGS_FILE="${IGOR_DIR}/config/variables/ai_settings.env"
    # Deprecation fallback: root-level copy
    [ ! -f "$_AI_SETTINGS_FILE" ] && _AI_SETTINGS_FILE="${IGOR_DIR}/ai_settings.env"
    if [ -f "$_AI_SETTINGS_FILE" ]; then
        local _sv_prov _sv_think _sv_temp _sv_verbose _sv_exec
        _sv_prov=$(    grep "^provider="       "$_AI_SETTINGS_FILE" 2>/dev/null | cut -d= -f2-)
        _sv_temp=$(    grep "^temperature="    "$_AI_SETTINGS_FILE" 2>/dev/null | cut -d= -f2-)
        _sv_verbose=$( grep "^verbose="        "$_AI_SETTINGS_FILE" 2>/dev/null | cut -d= -f2-)
        _sv_exec=$(    grep "^executive_mode=" "$_AI_SETTINGS_FILE" 2>/dev/null | cut -d= -f2-)
        [ -n "$_sv_prov"    ] && export provider="$_sv_prov"
        [ -n "$_sv_think"   ] && export NEXUS_MODEL="$_sv_think"
        [ -n "$_sv_temp"    ] && export NEXUS_TEMPERATURE="$_sv_temp"
        [ -n "$_sv_verbose" ] && export IGOR_VERBOSE="$_sv_verbose"
        [ "$_sv_exec" = "true" ] && executive_mode=true || executive_mode="${executive_mode:-false}"
    fi

    # Apply defaults for any unset vars
    provider="${provider:-anthropic}"
    NEXUS_MODEL="${NEXUS_MODEL:-claude-haiku-4-5-20251001}"
    NEXUS_TEMPERATURE="${NEXUS_TEMPERATURE:-0.7}"
    IGOR_VERBOSE="${IGOR_VERBOSE:-false}"
    executive_mode="${executive_mode:-false}"
    export provider NEXUS_MODEL NEXUS_TEMPERATURE IGOR_VERBOSE executive_mode

    # ── Build scrub table + load knowledge ───────────────────────────────────
    declare -f ai_scrub_build_table &>/dev/null && ai_scrub_build_table 2>/dev/null || true
    local _knowledge_block=""
    declare -f ai_knowledge_load &>/dev/null && _knowledge_block=$(ai_knowledge_load 2>/dev/null) || true

    # ── Gather server context ─────────────────────────────────────────────────
    echo -e "  ${CYAN}Scanning server for hybrid mode...${NC}"
    local _ctx=""
    declare -f ai_gather_context &>/dev/null && _ctx=$(ai_gather_context 2>/dev/null) || true
    local _scrubbed_ctx=""
    declare -f ai_scrub_outbound &>/dev/null && _scrubbed_ctx=$(ai_scrub_outbound "$_ctx" 2>/dev/null) || _scrubbed_ctx="$_ctx"

    # ── Build system prompt ───────────────────────────────────────────────────
    declare -f _ai_build_system_prompt &>/dev/null \
        && _IGOR_HYBRID_SYSTEM_PROMPT=$(_ai_build_system_prompt "$_knowledge_block" "$_scrubbed_ctx" 2>/dev/null) \
        || _IGOR_HYBRID_SYSTEM_PROMPT="You are Igor, an AI assistant for managing a self-hosted Nextcloud server."

    _IGOR_HYBRID_CONV='[]'
    _IGOR_HYBRID_INITIALIZED=true
    export _IGOR_HYBRID_INITIALIZED _IGOR_HYBRID_SYSTEM_PROMPT _IGOR_HYBRID_CONV
    echo -e "  ${GRN}✔ Hybrid AI ready.${NC}"
    return 0
}

# ── _igor_hybrid_ask ──────────────────────────────────────────────────────────
# Send one user message to the AI, display reply, run tools (agentic, max 3 steps).
# Sets _IGOR_HYBRID_ACTIVE=true.
_igor_hybrid_ask() {
    local _input="$1"
    [ -z "$_input" ] && return 0
    # Determine active API key
    local _active_key=""
    if [ "$provider" = "openrouter" ] && _igor_hybrid_openrouter_cutover; then
        unset OPENROUTER_API_KEY OR_API_KEY NEXUS_API_KEY
    elif [ "$provider" = "openrouter" ]; then
        _active_key=$(cat "$HOME/.nexus_or_key" 2>/dev/null)
    else
        _active_key=$(cat "$HOME/.nexus_api_key" 2>/dev/null)
    fi

    # Scrub input
    local _scrubbed_input="$_input"
    declare -f ai_scrub_outbound &>/dev/null \
        && _scrubbed_input=$(ai_scrub_outbound "$_input" 2>/dev/null) || true

    # Append user message
    declare -f _nexus_py_append &>/dev/null \
        && _IGOR_HYBRID_CONV=$(_nexus_py_append "$_IGOR_HYBRID_CONV" "user" "$_scrubbed_input" 2>/dev/null) \
        || return 1

    # API call
    export NEXUS_API_KEY="$_active_key"
    export NEXUS_PROVIDER="$provider"
    export NEXUS_MAX_TOKENS="${NEXUS_MAX_TOKENS:-2048}"
    export NEXUS_SYSTEM="$_IGOR_HYBRID_SYSTEM_PROMPT"
    export NEXUS_CONV="$_IGOR_HYBRID_CONV"

    local _raw _reply _in _out _explain _think
    declare -a _cmds=()
    _raw=$(_nexus_api_call 2>/dev/null)
    declare -f _nexus_parse_result &>/dev/null \
        && _nexus_parse_result "$_raw" _reply _cmds _in _out _explain _think \
        || { echo -e "  ${RED}✘ API error in hybrid mode.${NC}"; return 1; }

    # Show thinking in verbose mode
    if [ -n "$_think" ] && [ "${IGOR_VERBOSE:-false}" = "true" ]; then
        echo -e "  ${MAG}[thinking]${NC}"
        echo "$_think" | sed 's/^/  /'
        echo ""
    fi

    # Display reply
    echo ""
    echo -e "  ${MAG}Igor${NC} › "
    echo "$_reply" | fold -s -w 74 | sed 's/^/  /'
    echo ""

    # Cost banner
    declare -f ai_add_cost &>/dev/null && ai_add_cost "$_in" "$_out" "acting" 2>/dev/null || true
    declare -f ai_banner   &>/dev/null && ai_banner 2>/dev/null || true

    # Append assistant reply
    declare -f _nexus_py_append &>/dev/null \
        && _IGOR_HYBRID_CONV=$(_nexus_py_append "$_IGOR_HYBRID_CONV" "assistant" "$_reply" 2>/dev/null) \
        || true

    # Agentic continuation (max 3 steps)
    local _h_steps=0 _h_max=3
    local _h_loop_output="" _h_loop_ran=0

    for _hcmd in "${_cmds[@]}"; do
        local _hcmd_result=""
        declare -f ai_execute_tool &>/dev/null \
            && _hcmd_result=$(ai_execute_tool "$_hcmd" "$_explain" 2>&1) \
            || _hcmd_result="[ai_execute_tool not available]"
        if [[ "$_hcmd_result" != *"[USER SKIPPED"* ]] && \
           [[ "$_hcmd_result" != *"[BLOCKED BY DENYLIST"* ]]; then
            _h_loop_output="[TOOL RESULT]\n${_hcmd_result}\n\n"
            (( _h_loop_ran++ ))
        fi
        break  # one tool per reply
    done

    while [ -n "$_h_loop_output" ] && [ "$_h_loop_ran" -gt 0 ] && [ "$_h_steps" -lt "$_h_max" ]; do
        (( _h_steps++ ))
        local _h_fu_msg
        _h_fu_msg=$(printf "Here are the results of the commands that were run:\n\n%s" "$_h_loop_output")
        declare -f _nexus_py_append &>/dev/null \
            && _IGOR_HYBRID_CONV=$(_nexus_py_append "$_IGOR_HYBRID_CONV" "user" "$_h_fu_msg" 2>/dev/null) \
            || break

        export NEXUS_CONV="$_IGOR_HYBRID_CONV"
        local _h_raw _h_reply _h_in _h_out _h_explain
        declare -a _h_cmds=()
        _h_raw=$(_nexus_api_call 2>/dev/null)
        declare -f _nexus_parse_result &>/dev/null \
            && _nexus_parse_result "$_h_raw" _h_reply _h_cmds _h_in _h_out _h_explain \
            || break
        declare -f ai_add_cost &>/dev/null && ai_add_cost "$_h_in" "$_h_out" "acting" 2>/dev/null || true

        [ -z "$_h_reply" ] && break
        echo ""
        echo "$_h_reply" | fold -s -w 74 | sed 's/^/  /'
        echo ""

        declare -f _nexus_py_append &>/dev/null \
            && _IGOR_HYBRID_CONV=$(_nexus_py_append "$_IGOR_HYBRID_CONV" "assistant" "$_h_reply" 2>/dev/null) \
            || break

        _h_loop_output=""
        _h_loop_ran=0
        for _h_fu_cmd in "${_h_cmds[@]}"; do
            local _h_cmd_result=""
            declare -f ai_execute_tool &>/dev/null \
                && _h_cmd_result=$(ai_execute_tool "$_h_fu_cmd" "$_h_explain" 2>&1) \
                || _h_cmd_result="[ai_execute_tool not available]"
            if [[ "$_h_cmd_result" != *"[USER SKIPPED"* ]] && \
               [[ "$_h_cmd_result" != *"[BLOCKED BY DENYLIST"* ]]; then
                _h_loop_output="[TOOL RESULT]\n${_h_cmd_result}\n\n"
                (( _h_loop_ran++ ))
            fi
            break
        done
        [ ${#_h_cmds[@]} -eq 0 ] && break
    done

    export _IGOR_HYBRID_CONV
    _IGOR_HYBRID_ACTIVE=true
    export _IGOR_HYBRID_ACTIVE
}

# ── _igor_hybrid_reset ────────────────────────────────────────────────────────
# Rebuild context + clear conversation. Called on /menu reset.
_igor_hybrid_reset() {
    _IGOR_HYBRID_CONV='[]'
    _IGOR_HYBRID_ACTIVE=false
    export _IGOR_HYBRID_CONV _IGOR_HYBRID_ACTIVE

    # If already initialised, rebuild context for fresh start
    if [ "${_IGOR_HYBRID_INITIALIZED:-false}" = "true" ]; then
        local _ctx=""
        declare -f ai_gather_context &>/dev/null && _ctx=$(ai_gather_context 2>/dev/null) || true
        local _scrubbed_ctx=""
        declare -f ai_scrub_outbound &>/dev/null && _scrubbed_ctx=$(ai_scrub_outbound "$_ctx" 2>/dev/null) || _scrubbed_ctx="$_ctx"
        local _knowledge_block=""
        declare -f ai_knowledge_load &>/dev/null && _knowledge_block=$(ai_knowledge_load 2>/dev/null) || true
        declare -f _ai_build_system_prompt &>/dev/null \
            && _IGOR_HYBRID_SYSTEM_PROMPT=$(_ai_build_system_prompt "$_knowledge_block" "$_scrubbed_ctx" 2>/dev/null) \
            || true
        export _IGOR_HYBRID_SYSTEM_PROMPT
    fi
}
