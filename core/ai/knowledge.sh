#!/bin/bash
# ==============================================================================
#  IGOR — ai/knowledge.sh
#  Persistent knowledge layer for the AI assistant.
#
#  FILES (all in ${IGOR_DIR}/knowledge/):
#    primer.md       Always loaded. Condensed key facts and hard-won lessons.
#    wip.md          Loaded if it contains an open problem from last session.
#    session_log.md  Appended (not replaced) when meaningful changes are made.
#    runbook.md      Full detail. NOT auto-loaded. AI can read on request.
# ==============================================================================

KNOWLEDGE_DIR="${IGOR_DIR}/knowledge"
PRIMER_FILE="$KNOWLEDGE_DIR/primer.md"
WIP_FILE="$KNOWLEDGE_DIR/wip.md"
SESSION_LOG_FILE="$KNOWLEDGE_DIR/session_log.md"
REPAIR_HISTORY_FILE="$KNOWLEDGE_DIR/repair_history.md"

# Session change tracker — set by ai_execute_tool after TIER 2/3 commands
AI_SESSION_HAD_CHANGES=false

# ── Mark that a meaningful change happened this session ───────────────────────
ai_knowledge_mark_changed() {
    AI_SESSION_HAD_CHANGES=true
}

# ── Load knowledge into system prompt block ───────────────────────────────────
ai_knowledge_load() {
    mkdir -p "$KNOWLEDGE_DIR" 2>/dev/null
    local block=""

    if [ -f "$PRIMER_FILE" ]; then
        block+="=== IGOR PERSISTENT KNOWLEDGE ===\n"
        block+="$(cat "$PRIMER_FILE")\n"
    else
        block+="=== IGOR PERSISTENT KNOWLEDGE ===\n"
        block+="(primer.md not found at $PRIMER_FILE)\n"
    fi

    if [ -f "$WIP_FILE" ]; then
        if ! grep -q "^\*\*Status:\*\* EMPTY" "$WIP_FILE" 2>/dev/null; then
            block+="\n=== WORK IN PROGRESS (from previous session) ===\n"
            block+="$(cat "$WIP_FILE")\n"
            block+="=== END WIP — continue from here ===\n"
        fi
    fi

    local last_diag_file="$KNOWLEDGE_DIR/last_diag.md"
    if [ -f "$last_diag_file" ]; then
        block+="\n=== LAST DIAGNOSE REPORT ===\n"
        block+="$(cat "$last_diag_file")\n"
        block+="=== END DIAGNOSE REPORT ===\n"
    fi

    echo -e "$block"
}

# ── Show knowledge status at session start ────────────────────────────────────
ai_knowledge_show_status() {
    local primer_status wip_status

    if [ -f "$PRIMER_FILE" ]; then
        local lines; lines=$(wc -l < "$PRIMER_FILE")
        primer_status="${GRN}✔ loaded${NC} (${lines} lines)"
    else
        primer_status="${YEL}! not found${NC} — create $PRIMER_FILE"
    fi

    if [ -f "$WIP_FILE" ] && ! grep -q "^\*\*Status:\*\* EMPTY" "$WIP_FILE" 2>/dev/null; then
        wip_status="${YEL}⚠ open problem from previous session${NC}"
    else
        wip_status="${CYAN}none${NC}"
    fi

    echo -e "  ${CYAN}Knowledge:${NC} primer $primer_status"
    echo -e "  ${CYAN}WIP:${NC}       $wip_status"

    local last_diag_file="$KNOWLEDGE_DIR/last_diag.md"
    if [ -f "$last_diag_file" ]; then
        local diag_ts; diag_ts=$(head -1 "$last_diag_file" 2>/dev/null | sed 's/## Diagnose Report — //')
        echo -e "  ${CYAN}Diagnose:${NC}  ${YEL}⚡ last report loaded${NC} (${diag_ts:-unknown date})"
    fi
}

# ── Public: clear WIP when problem is solved ─────────────────────────────────
ai_knowledge_clear_wip() {
    _ai_knowledge_clear_wip
}

# ── Internal: clear WIP ───────────────────────────────────────────────────────
_ai_knowledge_clear_wip() {
    mkdir -p "$KNOWLEDGE_DIR" 2>/dev/null
    if [ -f "$WIP_FILE" ] && ! grep -q "^\*\*Status:\*\* EMPTY" "$WIP_FILE"; then
        cat > "$WIP_FILE" << 'WIPEEOF'
# IGOR — Work In Progress
*This file is written automatically when a session ends with an unsolved problem.*
*It is loaded at the start of the next AI session so work continues where it left off.*
*Delete or clear this file once the problem is resolved.*

**Status:** EMPTY — no open problems.
WIPEEOF
        ok "WIP cleared."
    fi
}

# ── Session end handler ───────────────────────────────────────────────────────
# Parameters: $1=api_key $2=model $3=conversation_json $4=session_file
#             $5=executive_mode $6=session_cost
ai_knowledge_session_end() {
    local api_key="$1"
    local model="$2"
    local conversation="$3"
    local session_file="$4"

    echo ""
    echo -e "  ${CYAN}──────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Session wrap-up${NC}"
    echo -e "  ${CYAN}──────────────────────────────────────────────────────${NC}"
    echo ""

    if $AI_SESSION_HAD_CHANGES; then
        echo -e "  ${YEL}Changes were made this session (TIER 2/3 commands ran).${NC}"
        echo ""
        if confirm "Save a session log entry?"; then
            _ai_knowledge_save_log_entry "$api_key" "$model" "$conversation" "$session_file"
        fi
        echo ""
    else
        echo -e "  ${CYAN}i${NC}  No system changes this session — no log entry needed."
        echo ""
    fi

    echo -e "  Is there an open/unsolved problem from this session?"
    echo -e "  ${CYAN}y${NC} = save WIP so next session continues here"
    echo -e "  ${CYAN}n${NC} = problem solved (or nothing to save)"
    echo -e "  ${CYAN}s${NC} = skip"
    echo ""
    local wip_choice
    read -rp "  [y/n/s]: " wip_choice
    case "$wip_choice" in
        y|Y) _ai_knowledge_save_wip "$api_key" "$model" "$conversation" "$session_file" ;;
        n|N) _ai_knowledge_clear_wip ;;
        *)   echo -e "  ${CYAN}WIP unchanged.${NC}" ;;
    esac

    echo ""
    echo -e "  ${CYAN}Session log:${NC} $session_file"
    echo -e "  ${CYAN}Knowledge:${NC}   $KNOWLEDGE_DIR"
    echo ""
}

# ── Internal: generate and save session log entry ────────────────────────────
_ai_knowledge_save_log_entry() {
    local api_key="$1" model="$2" conversation="$3" session_file="$4"

    echo ""
    echo -e "  ${CYAN}Asking AI to summarise what happened...${NC}"

    # TODO-08: use haiku for session summaries — cheap, fast, sufficient quality
    # Fall back to whatever model was passed if haiku name looks wrong for provider
    local _sum_model="claude-haiku-4-5-20251001"
    # If provider is openrouter, use OR-prefixed haiku name
    local _cur_prov; _cur_prov=$(echo "${NEXUS_PROVIDER:-anthropic}")
    [ "$_cur_prov" = "openrouter" ] && _sum_model="anthropic/claude-haiku-4-5-20251001"

    local summary_prompt="Based on the conversation so far, write a concise session log entry. Format exactly like this:

## Session — $(date +%Y-%m-%d)
**What was attempted:** one sentence
**Commands run:** bullet list of significant commands (TIER 2/3 only, not reads)
**Outcome:** solved / partial / unsolved
**Notes:** any new facts learned, gotchas, or things to remember next time (2-3 sentences max)

Be specific. Use [IGOR:TOKEN] placeholders for any sensitive values. Keep it under 15 lines total."

    local _sum_conv
    _sum_conv=$(_nexus_py_append "$conversation" "user" "$summary_prompt")

    local _sum_raw _sum_reply _sum_cmds _sum_in _sum_out
    declare -a _sum_cmds=()
    export NEXUS_API_KEY="$api_key"
    export NEXUS_MODEL="$_sum_model"
    export NEXUS_MAX_TOKENS="512"
    export NEXUS_SYSTEM=""
    export NEXUS_CONV="$_sum_conv"
    _sum_raw=$(_nexus_api_call)
    _nexus_parse_result "$_sum_raw" _sum_reply _sum_cmds _sum_in _sum_out
    local summary_response="$_sum_reply"

    if [[ "$summary_response" == ERROR:* ]]; then
        warn "Could not generate summary: $summary_response"
        warn "You can add an entry manually to $SESSION_LOG_FILE"
        return
    fi

    echo ""
    echo -e "  ${YEL}── Draft log entry ──────────────────────────────────────${NC}"
    echo "$summary_response" | sed 's/^/    /'
    echo -e "  ${YEL}────────────────────────────────────────────────────────${NC}"
    echo ""

    echo -e "  ${CYAN}a${NC} = append as-is   ${CYAN}e${NC} = edit in nano   ${CYAN}s${NC} = skip"
    local choice
    read -rp "  [a/e/s]: " choice
    case "$choice" in
        a|A)
            mkdir -p "$KNOWLEDGE_DIR"
            { echo ""; echo "$summary_response"; echo ""; echo "---"; } >> "$SESSION_LOG_FILE"
            ok "Appended to $SESSION_LOG_FILE"
            echo "[SESSION LOG ENTRY SAVED]" >> "$session_file"
            ;;
        e|E)
            local tmpfile; tmpfile=$(mktemp /tmp/igor_log_XXXXXX.md)
            echo "$summary_response" > "$tmpfile"
            nano "$tmpfile"
            mkdir -p "$KNOWLEDGE_DIR"
            { echo ""; cat "$tmpfile"; echo ""; echo "---"; } >> "$SESSION_LOG_FILE"
            rm -f "$tmpfile"
            ok "Edited entry appended to $SESSION_LOG_FILE"
            echo "[SESSION LOG ENTRY SAVED (edited)]" >> "$session_file"
            ;;
        *)
            echo -e "  ${CYAN}Skipped.${NC}"
            ;;
    esac
}

# ── Internal: generate and save WIP entry ────────────────────────────────────
_ai_knowledge_save_wip() {
    local api_key="$1" model="$2" conversation="$3" session_file="$4"

    echo ""
    echo -e "  ${CYAN}Saving work-in-progress...${NC}"

    # TODO-08: use haiku for WIP summaries
    local _wip_model="claude-haiku-4-5-20251001"
    local _cur_prov2; _cur_prov2="${NEXUS_PROVIDER:-anthropic}"
    [ "$_cur_prov2" = "openrouter" ] && _wip_model="anthropic/claude-haiku-4-5-20251001"

    local wip_prompt="The user is ending this session with the problem unsolved. Write a WIP (work in progress) entry so the next AI session can continue from here.

Format exactly:
## WIP — $(date '+%Y-%m-%d %H:%M')
**Problem:** one sentence description
**What was tried:** bullet list of approaches attempted
**Current state:** what we know, what we don't, where we got stuck
**Next step:** the most promising thing to try next

Keep it under 20 lines. Use [IGOR:TOKEN] for sensitive values. Be specific about commands and their outputs."

    local _wip_conv
    _wip_conv=$(_nexus_py_append "$conversation" "user" "$wip_prompt")

    local _wip_raw _wip_reply _wip_cmds _wip_in _wip_out
    declare -a _wip_cmds=()
    export NEXUS_API_KEY="$api_key"
    export NEXUS_MODEL="$_wip_model"
    export NEXUS_MAX_TOKENS="512"
    export NEXUS_SYSTEM=""
    export NEXUS_CONV="$_wip_conv"
    _wip_raw=$(_nexus_api_call)
    _nexus_parse_result "$_wip_raw" _wip_reply _wip_cmds _wip_in _wip_out
    local wip_summary="$_wip_reply"

    if [[ "$wip_summary" == ERROR:* ]]; then
        warn "Could not generate WIP summary automatically."
        echo ""
        echo -e "  Describe the open problem briefly (or press Enter to skip):"
        local manual_wip
        IFS= read -r manual_wip
        if [ -n "$manual_wip" ]; then
            mkdir -p "$KNOWLEDGE_DIR"
            {
                echo "## WIP — $(date '+%Y-%m-%d %H:%M')"
                echo "**Problem:** $manual_wip"
                echo "**Note:** Auto-summary failed. Check session log for details."
                echo ""
                echo "*(Raw session log: $session_file)*"
            } > "$WIP_FILE"
            ok "WIP saved to $WIP_FILE"
        fi
        return
    fi

    local recent_transcript
    recent_transcript=$(echo "$conversation" | python3 -c "
import sys, json
msgs = json.load(sys.stdin)
recent = msgs[-6:] if len(msgs) > 6 else msgs
for m in recent:
    role = m.get('role','?').upper()
    content = m.get('content','')[:400]
    print(f'[{role}] {content}')
    print()
" 2>/dev/null)

    echo ""
    echo -e "  ${YEL}── WIP entry to save ────────────────────────────────────${NC}"
    echo "$wip_summary" | sed 's/^/    /'
    echo -e "  ${YEL}────────────────────────────────────────────────────────${NC}"
    echo ""

    echo -e "  ${CYAN}s${NC} = save  ${CYAN}e${NC} = edit first  ${CYAN}x${NC} = skip"
    local choice
    read -rp "  [s/e/x]: " choice
    case "$choice" in
        s|S)
            mkdir -p "$KNOWLEDGE_DIR"
            {
                echo "# IGOR — Work In Progress"
                echo "*Updated: $(date '+%Y-%m-%d %H:%M')*"
                echo ""
                echo "$wip_summary"
                echo ""
                echo "---"
                echo "## Recent Conversation"
                echo '```'
                echo "$recent_transcript"
                echo '```'
                echo ""
                echo "*(Full session log: $session_file)*"
            } > "$WIP_FILE"
            ok "WIP saved to $WIP_FILE"
            echo "[WIP SAVED]" >> "$session_file"
            ;;
        e|E)
            local tmpfile; tmpfile=$(mktemp /tmp/igor_wip_XXXXXX.md)
            echo "$wip_summary" > "$tmpfile"
            nano "$tmpfile"
            mkdir -p "$KNOWLEDGE_DIR"
            {
                echo "# IGOR — Work In Progress"
                echo "*Updated: $(date '+%Y-%m-%d %H:%M') (edited)*"
                echo ""
                cat "$tmpfile"
                echo ""
                echo "---"
                echo "## Recent Conversation"
                echo '```'
                echo "$recent_transcript"
                echo '```'
            } > "$WIP_FILE"
            rm -f "$tmpfile"
            ok "WIP saved (edited) to $WIP_FILE"
            ;;
        *)
            echo -e "  ${CYAN}WIP not saved.${NC}"
            ;;
    esac
}
