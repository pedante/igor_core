#!/bin/bash
# ==============================================================================
#  IGOR — ai/context.sh
#  System context gathering and system prompt construction.
#
#  Provides:
#    ai_gather_context()         build the server state snapshot
#    _ai_build_system_prompt()   assemble the full system prompt
#    _ai_load_user_prompt()      load user override from config dir
#    _ai_inject_patterns()       append pattern context (stub for M4)
#    _ai_inject_health_history() append health history (stub for M4)
# ==============================================================================

# ── Gather system context snapshot ───────────────────────────────────────────
# Runs diagnostic commands on the host and returns a structured text block.
# Context is scrubbed by ai_scrub_outbound() before being sent to any API.
ai_gather_context() {
    local ctx=""
    ctx+="=== IGOR — SYSTEM CONTEXT (auto-gathered) ===\n"
    ctx+="Timestamp: $(date)\n"
    ctx+="Hostname: $(hostname)  LAN IP: $(hostname -I | awk '{print $1}')\n"
    ctx+="OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')\n"
    ctx+="RAM: $(free -h | awk '/^Mem:/{print $2}') total  $(free -h | awk '/^Mem:/{print $7}') available\n"
    ctx+="Swap: $(free -h | awk '/^Swap:/{print $2}')\n"
    ctx+="Load: $(cat /proc/loadavg | cut -d' ' -f1-3)\n"

    ctx+="\n=== DISK ===\n"
    ctx+="$(df -h | grep -v 'tmpfs\|udev\|loop')\n"

    ctx+="\n=== PROJECT FILES ===\n"
    ctx+="Igor dir: ${IGOR_DIR}\n"
    ctx+="Files: $(ls -1 "${IGOR_DIR}" 2>/dev/null | tr '\n' ' ')\n"
    ctx+="variables/igor.env: $([ -f "${IGOR_DIR}/variables/igor.env" ] && echo 'present' || echo 'not found')\n"

    ctx+="\n=== PORT BINDINGS ===\n"
    if command -v netstat &>/dev/null; then
        ctx+="$(netstat -tuln 2>/dev/null | grep -v '127.0.0.1' | tail -10)\n"
    fi

    # Module-specific context — each loaded module prints its own context block
    if declare -f igor_run_all_hooks &>/dev/null; then
        local _module_ctx
        _module_ctx=$(igor_run_all_hooks "ai_context" 2>/dev/null || true)
        [ -n "$_module_ctx" ] && ctx+="\n${_module_ctx}"
    fi

    ctx+="\n=== NETWORK STATUS ===\n"
    if command -v ping &>/dev/null; then
        ping -c 1 -W 2 8.8.8.8 &>/dev/null && ctx+="Internet: REACHABLE\n" || ctx+="Internet: UNREACHABLE\n"
        ping -c 1 -W 2 google.com &>/dev/null && ctx+="DNS (google.com): RESOLVING\n" || ctx+="DNS (google.com): NOT RESOLVING\n"
    fi

    ctx+="\n=== HEALTH SCORE ===\n"
    local health_score
    health_score=$(calculate_health_score 2>/dev/null || echo "unknown")
    ctx+="System health score: ${health_score}/100\n"

    # Inject hook inventory — live listing of what modules have plugged in
    local _hook_inv; _hook_inv=$(_ai_inject_hook_inventory 2>/dev/null)
    [ -n "$_hook_inv" ] && ctx+="\n${_hook_inv}"

    # Inject capability catalog — callable Igor actions with problem keywords
    local _cap_inv; _cap_inv=$(_ai_inject_capabilities 2>/dev/null)
    [ -n "$_cap_inv" ] && ctx+="\n${_cap_inv}"

    # Inject patterns context (no-op until healing/ is built in M4)
    ctx+="$(_ai_inject_patterns)\n"

    # Inject dynamic menu items context
    if declare -f _ai_inject_dynamic_menu_items &>/dev/null; then
        ctx+="$(_ai_inject_dynamic_menu_items)\n"
    fi

    printf '%s' "$ctx"
}

# ── Build system prompt ────────────────────────────────────────────────────────
# Parameters: $1=knowledge_block $2=scrubbed_context
# Calls _ai_load_base_prompt (renderer) with knowledge and context, then appends
# the user override file if present. Knowledge/context are now injected INSIDE
# the template (Section 6) by the renderer — not appended separately here.
_ai_build_system_prompt() {
    local knowledge_block="$1"
    local scrubbed_context="$2"

    local _base_prompt
    _base_prompt=$(_ai_load_base_prompt "$knowledge_block" "$scrubbed_context")

    # User override — appended after renderer output, unchanged from prior behaviour
    local _user_prompt_file="$(_igor_resolve_dir "knowledge")/system_prompt.txt"
    local _user_override=""
    [ -f "$_user_prompt_file" ] && _user_override=$'\n\n'"=== USER CUSTOMISATION ===\n$(cat "$_user_prompt_file")"

    printf '%s%s' "$_base_prompt" "$_user_override"
}

# ── Internal: base system prompt ─────────────────────────────────────────────
# P1-5: Calls ai_render.py (primary) with IGOR_KNOWLEDGE / IGOR_CONTEXT env vars.
# Falls back to the heredoc below if the renderer is missing or fails.
# Parameters: $1=knowledge_block $2=scrubbed_context
_ai_load_base_prompt() {
    local _knowledge="${1:-}"
    local _context="${2:-}"
    local _lib="${IGOR_DIR}/core/lib/ai_render.py"
    local _model="${NEXUS_MODEL:-}"

    if [ -f "$_lib" ]; then
        # Route tool formatting through the provider-aware router
        local _router="${IGOR_DIR}/core/ai/ai_router.sh"
        if [ -f "$_router" ]; then
            # shellcheck source=/dev/null
            source "$_router"
            ai_router_format_tools
            # IGOR_MODULE_TOOLS and NEXUS_TOOLS_JSON are now set by the router
        fi

        # Collect plain-text module sections (tiers + knowledge)
        local _module_tiers=""
        local _module_knowledge=""
        if declare -f igor_run_all_hooks &>/dev/null; then
            _module_tiers=$(igor_run_all_hooks "ai_tiers" 2>/dev/null || true)
            _module_knowledge=$(igor_run_all_hooks "ai_knowledge" 2>/dev/null || true)
        fi

        local _rendered
        _rendered=$(IGOR_MODULE_TOOLS="${IGOR_MODULE_TOOLS:-}" \
            IGOR_MODULE_TIERS="$_module_tiers" \
            IGOR_MODULE_KNOWLEDGE="$_module_knowledge" \
            IGOR_KNOWLEDGE="$_knowledge" \
            IGOR_CONTEXT="$_context" \
            python3 "$_lib" "$_model" 2>/dev/null)
        if [ -n "$_rendered" ]; then
            printf '%s' "$_rendered"
            return 0
        fi
        echo "[ai_render.py: render failed — using heredoc fallback]" >&2
    fi

    # FALLBACK heredoc — used only when ai_render.py is unavailable.
    # Module-specific context (MODULE_TOOLS, MODULE_TIERS, MODULE_KNOWLEDGE) is
    # injected by _ai_build_system_prompt() after this block via the normal append path.
    cat << 'SYSPROMPT'
You are IGOR, an expert system administrator assistant.
Diagnose and fix issues on the systems you manage. Run commands, read results, and iterate — do not give advice without evidence.

━━━ SCRATCHPAD — MANDATORY ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Begin EVERY response with this block (even the first one in a session):

<scratchpad>
HYPOTHESIS: <one sentence — or "Unknown — gathering info">
TRIED:
  - <command> → <result in one line>
FOCUS: <what you are doing right now>
</scratchpad>

Example of correct scratchpad:
<scratchpad>
HYPOTHESIS: nginx conf.d/default.conf is present, causing 403 on directory URLs.
TRIED:
  - docker compose ps → all containers up
  - curl http://localhost:8080/apps/files/ → 403
  - docker compose exec web ls /etc/nginx/conf.d/ → default.conf present
FOCUS: removing stale default.conf and restarting nginx
</scratchpad>

ACCUMULATION RULE: When writing your scratchpad, ALWAYS copy ALL items from the
injected === INVESTIGATION SCRATCHPAD === TRIED list (preserving their results),
then append any NEW commands you ran in this response. Never omit prior TRIED entries.
If there is no injected scratchpad yet, start with an empty TRIED list.

━━━ LOOP RULES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- ONE tool per response. Wait for the result before the next step.
- Gather info yourself — never ask the user to run commands.
- Emit RESULT: immediately when ANY of these exits is true:
    FIXED        — a READ command confirms the fix worked (show the output as evidence)
    NOTHING_TO_FIX — the reported behavior is expected, not present, or not a real problem
    BLOCKED      — you need human permission (DESTROY tier) or 3 approaches all failed
    STOP         — the user types "stop"
- "This can be safely ignored" said in prose is NOT a valid exit.
  You MUST emit RESULT: STATUS=NOTHING_TO_FIX — no exceptions.
- Do NOT stop after a CHANGE — always verify with a READ immediately after.
- Do NOT ask "should I continue?" — just continue.
- For diagnostic tasks: gather at least 3 independent data points before concluding.
  One passing check does not mean the stack is healthy. Check containers AND storage
  AND the application layer before declaring "all good."
- If a command output contains "No such file or directory" for the specific file or
  directory you were investigating, this IS the root cause. Stop investigating. Emit
  RESULT: with the finding and a recommended fix. Do not keep searching.
- You MUST keep emitting tool tags until you have concrete command output as evidence.
  If you believe the task is done, run ONE verification READ first, then emit RESULT:.
  Never emit RESULT: without verified output — "I think it's fixed" is not evidence.
- The loop pauses after 5 steps as a safety checkpoint. When the user types
  "continue" or "cont", immediately emit the next tool tag to resume.
- When stopping: emit a RESULT: block (see BEHAVIOUR section below).

━━━ TOOL FORMAT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

You MUST use exactly ONE semantic XML tool per response.
Do NOT wrap tools in markdown code blocks.

In verbose mode, you MAY prefix your tool with one annotation:
  <explain> Why you are taking this action (one sentence). </explain>
  <host> the actual command </host>

<explain> is NOT a tool. Never emit <explain> without a tool tag immediately after it
on the same response. If you have nothing to run, emit RESULT: instead.

━━━ AVAILABLE TOOLS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Application configuration management:
   <occ> maintenance:mode --off </occ>
   Use for application configuration, services, users, and maintenance.
   NEVER edit configuration files directly unless specifically instructed.

2. Host shell commands:
   <host> docker compose ps </host>
   For multi-line scripts: use printf to write a temp file then run it.
   NEVER use heredoc (<<) — blocked.

3. Container lifecycle:
   <container action="restart"> web </container>
   action = start | stop | restart

4. Log reading (safe, capped at 50 lines):
   <read_log target="app" lines="20"> Fatal </read_log>

5. Safe file editing (literal replace + backup):
   <edit_file path="./web/nginx.conf">
     <find>fastcgi_read_timeout 60s;</find>
     <replace>fastcgi_read_timeout 600s;</replace>
   </edit_file>

6. Read a saved report (health check or AI diagnosis):
   <read_report filename="health_20260319_143022.txt"/>
   Capped at 100 lines. Filenames are shown in RECENT REPORTS section of context.

7. Run a registered Igor module action (see AVAILABLE IGOR ACTIONS in context):
   <run_igor_action>scan_files</run_igor_action>
   Calls the action's module function directly. Tier (READ/CHANGE/DESTROY) is
   determined by the catalog — same gating as all other tools. Use this instead
   of raw <host> commands when a matching Igor action exists: it is safer (the
   module handles paths and arguments) and appears in the journal.

━━━ INCORRECT — never do this ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✗ "I'll run df -h to check disk space"        ← narrate instead of using a tool
✗ "Let me check the disk: df -h"              ← narrate instead of using a tool
✗ ```<host>df -h</host>```                    ← tool tag inside a markdown block
✗ <host>df -h && docker compose ps</host>     ← two commands in one tool tag
✗ [Running df -h to check...]                 ← fake execution, no tool tag

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━ FAILURE HANDLING ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

If a command returns a non-zero exit code or empty output:
  1. Record it in your scratchpad TRIED list as: <command> → FAILED (<error>)
  2. Revise your HYPOTHESIS
  3. Try a different approach
  Never retry the exact same command twice.
  Empty output ≠ success — re-check with a different command.
If a command returns all-zero or obviously wrong values (e.g., docker stats showing
  0B / 0B memory on a running Pi), treat this as unreliable cgroup data. Use instead:
  <host> docker compose exec app cat /proc/meminfo </host> or <host> free -h </host>

━━━ BEHAVIOUR ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- Do not explain what you are about to do — just do it.
- After EVERY CHANGE or <container> action: run a READ to confirm success.
  e.g. after restarting web: <host> curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health-check </host>
  Only say "fixed" after a READ confirms it. Never assume a CHANGE worked.
- SOLUTION PROTOCOL — use before any multi-step repair:
  Before running the FIRST CHANGE command, output this block exactly:
    FIX: <one line — what you will do and why>
    STEPS: 1.<first> 2.<second> 3.<third>
  Then emit the first tool tag. Continue through ALL steps without stopping unless blocked.
- RESULT PROTOCOL — emit when any exit condition is met. Use the matching template:

    RESULT: STATUS=FIXED
    FINDING: <what was broken>
    EVIDENCE: <literal command output from your verification READ — paste the actual output>
    ACTION: <what was changed>

    RESULT: STATUS=NOTHING_TO_FIX
    FINDING: <what you investigated>
    EXPLANATION: <why this is expected behavior / not a real problem>
    NO ACTION NEEDED.

    RESULT: STATUS=BLOCKED
    FINDING: <what you tried>
    BLOCKER: <why you cannot proceed>
    NEXT STEP: <what the user should do>

  FIXED RULE: You MUST NOT emit STATUS=FIXED unless you ran a verification READ command

  STATUS=FIXED is only permitted after running a verification command that directly confirms the issue is resolved — not after a command that merely succeeded.

  in this session and its output is pasted verbatim in EVIDENCE above.
  "The service restarted successfully" is NOT evidence. Actual curl/docker/occ output IS.
  If you have not yet verified, run the verification command first — do not skip it.

  Once you emit RESULT:, the issue is CLOSED. Do not revisit it in this session.

STYLE: Short. Terminal, not browser. No markdown headers or bullet walls.
SYSPROMPT
    # Fallback path: knowledge and context were not injected by the renderer.
    # Append them manually so the session still has full context.
    printf '\n\n%s\n\n%s' "$_knowledge" "$_context"
}

# ── Load user system prompt override ─────────────────────────────────────────
_ai_load_user_prompt() {
    local _f="$(_igor_resolve_dir "knowledge")/system_prompt.txt"
    [ -f "$_f" ] && cat "$_f"
}

# ── Inject pattern context ─────────────────────────────────────────────────────
# Collects patterns from two sources and emits exactly ONE header/footer block:
#   1. Module-defined patterns (ai_patterns hook — static, per-module)
#   2. Learned patterns from healing (pattern_to_context or .pattern files)
# pattern_to_context manages its own header/footer; we strip them and merge.
_ai_inject_patterns() {
    local _mod_body=""
    local _healer_body=""

    # ── Module-defined patterns ───────────────────────────────────────────────
    if declare -f igor_run_all_hooks &>/dev/null; then
        _mod_body=$(igor_run_all_hooks "ai_patterns" 2>/dev/null || true)
    fi

    # ── Learned patterns from healing ─────────────────────────────────────────
    if declare -f pattern_to_context &>/dev/null; then
        # pattern_to_context owns its own "=== KNOWN REPAIR PATTERNS ===" block;
        # strip those decorators so we control the single unified header/footer.
        _healer_body=$(pattern_to_context 2>/dev/null \
            | grep -v "^=== " \
            | grep -v "^Igor has recorded" \
            || true)
    else
        # Fallback: read .pattern files directly
        local _patterns_dir="$(_igor_resolve_dir "patterns")"
        if [ -d "$_patterns_dir" ]; then
            local _f
            for _f in "${_patterns_dir}"/*.pattern; do
                [ -f "$_f" ] || continue
                local _name _confirmed _failed _tier _cmd
                _name=$(grep    "^NAME: "      "$_f" | sed 's/^NAME: //')
                _confirmed=$(grep "^CONFIRMED: " "$_f" | sed 's/^CONFIRMED: //')
                _failed=$(grep    "^FAILED: "    "$_f" | sed 's/^FAILED: //')
                _tier=$(grep      "^FIX_TIER: "  "$_f" | sed 's/^FIX_TIER: //')
                _cmd=$(grep       "^FIX_CMD: "   "$_f" | sed 's/^FIX_CMD: //')
                _healer_body+=$(printf 'PATTERN: %s  confirmed:%s  failed:%s  tier:%s\n  Fix: %s\n\n' \
                    "${_name:-?}" "${_confirmed:-0}" "${_failed:-0}" "${_tier:-?}" "${_cmd:-unknown}")
            done
        fi
    fi

    # ── Emit unified block (or nothing if both sources are empty) ─────────────
    [ -z "$_mod_body" ] && [ -z "$_healer_body" ] && return 0

    echo ""
    echo "=== KNOWN REPAIR PATTERNS ==="
    [ -n "$_mod_body"    ] && printf '%s\n' "$_mod_body"
    [ -n "$_healer_body" ] && printf '%s\n' "$_healer_body"
    echo "=== END PATTERNS ==="
}

# ── Inject health check history ───────────────────────────────────────────────
# Reads the health check cache file and formats recent results for AI context.
_ai_inject_health_history() {
    local cache_file="$(_igor_resolve_dir "alerts")/health_cache.txt"
    [ ! -f "$cache_file" ] || [ ! -s "$cache_file" ] && return 0

    echo ""
    echo "=== LAST HEALTH CHECK RESULTS ==="
    local ok=0 warn=0 fail=0 crit=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local sev="${line%% *}"
        case "$sev" in
            OK)       (( ok++ ))   ;;
            WARN)     (( warn++ )) ; echo "  WARN: ${line#* * }" ;;
            FAIL)     (( fail++ )) ; echo "  FAIL: ${line#* * }" ;;
            CRITICAL) (( crit++ )) ; echo "  CRITICAL: ${line#* * }" ;;
        esac
    done < "$cache_file"
    echo "  Summary: OK=${ok} WARN=${warn} FAIL=${fail} CRITICAL=${crit}"
    echo "=== END HEALTH CHECK ==="
}

# ── Inject recent reports manifest ───────────────────────────────────────────
# Lists the last 5 report filenames + line counts so the AI knows what exists.
# AI retrieves content on demand via <read_report filename="..."/>.
_ai_inject_reports_manifest() {
    local rdir="${REPORTS_DIR:-${IGOR_DIR}/data/reports}"
    [ ! -d "$rdir" ] && return 0
    local count=0
    for f in "$rdir"/*.txt; do
        [ -f "$f" ] && (( count++ ))
    done
    [ "$count" -eq 0 ] && return 0

    echo ""
    echo "=== RECENT REPORTS (last 5) ==="
    local i=0
    for f in $(ls -1t "$rdir"/*.txt 2>/dev/null | head -5); do
        local bname; bname=$(basename "$f")
        local lines; lines=$(wc -l < "$f" 2>/dev/null || echo "?")
        local dt; dt=$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || \
                       date -d "@$(stat -c %Y "$f" 2>/dev/null)" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "?")
        echo "  ${bname}  (${lines} lines, ${dt})"
        (( i++ ))
    done
    echo "Use <read_report filename=\"FILENAME\"/> to read a report."
    echo "=== END REPORTS ==="
}

# ── Inject dynamic menu items ───────────────────────────────────────────────
# Reads pending and approved dynamic menu items for AI context.
# Emits a context block listing items waiting for AI review/approval.
_ai_inject_dynamic_menu_items() {
    local _pending_dir="${IGOR_DIR}/data/runtime/dynamic_menu"
    [ -d "$_pending_dir" ] || return 0

    local _items="" _f
    for _f in "${_pending_dir}"/*.pending; do
        [ -f "$_f" ] || continue
        _items+="  PENDING: $(cat "$_f" 2>/dev/null)\n"
    done
    for _f in "${_pending_dir}"/*.approved; do
        [ -f "$_f" ] || continue
        _items+="  APPROVED: $(cat "$_f" 2>/dev/null)\n"
    done

    [ -z "$_items" ] && return 0
    echo ""
    echo "=== DYNAMIC MENU ITEMS ==="
    printf '%b' "$_items"
    echo "=== END DYNAMIC MENU ITEMS ==="
}

# ── Hook inventory — live listing of what modules have registered ─────────────
# Outputs a sorted table of hook_name → function(s) so the AI knows at runtime
# exactly what is plugged in (not just static knowledge).
_ai_inject_hook_inventory() {
    # _IGOR_HOOKS is the global assoc array from module_loader.sh
    # If empty or not declared, skip silently
    if ! declare -p _IGOR_HOOKS &>/dev/null 2>&1; then return 0; fi
    local _total="${#_IGOR_HOOKS[@]}"
    [ "${_total:-0}" -eq 0 ] && return 0

    echo ""
    echo "=== IGOR REGISTERED HOOKS (${_total} total) ==="
    local _hook
    for _hook in $(echo "${!_IGOR_HOOKS[@]}" | tr ' ' '\n' | sort); do
        printf "  %-24s %s\n" "$_hook" "${_IGOR_HOOKS[$_hook]}"
    done
    echo "=== END HOOKS ==="
}

# ── Capability catalog — callable Igor actions ────────────────────────────────
# Formats _IGOR_CAPABILITIES (populated by igor_load_capabilities()) into a
# context block the AI can use to pick and invoke specific Igor actions.
_ai_inject_capabilities() {
    if ! declare -p _IGOR_CAPABILITIES &>/dev/null 2>&1; then return 0; fi
    local _total="${#_IGOR_CAPABILITIES[@]}"
    [ "${_total:-0}" -eq 0 ] && return 0

    echo ""
    echo "=== AVAILABLE IGOR ACTIONS (callable via <run_igor_action>action_name</run_igor_action>) ==="
    echo "  Format: action_name  TIER  [MENU PATH]"
    echo "          → Description"
    echo "          → Problems: keywords that suggest this action"
    echo ""

    local _action _entry _desc _fn _mod _tier _probs _mpath
    for _action in $(echo "${!_IGOR_CAPABILITIES[@]}" | tr ' ' '\n' | sort); do
        _entry="${_IGOR_CAPABILITIES[$_action]}"
        IFS='|' read -r _desc _fn _mod _tier _probs _mpath <<< "$_entry"
        printf "  %-22s %-8s %s\n" "$_action" "${_tier}" "${_mpath}"
        [ -n "$_desc"  ] && printf "    → %s\n" "$_desc"
        [ -n "$_probs" ] && printf "    → Problems: %s\n" "$_probs"
        echo ""
    done
    echo "=== END IGOR ACTIONS ==="
}
