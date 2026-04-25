#!/bin/bash
# ==============================================================================
#  IGOR — ai/safety.sh
#  Command safety layer — auditable in isolation.
#
#  Provides:
#    ai_is_denied()         hard denylist check (never runs regardless of tier)
#    ai_cmd_is_read()       tier 1: read-only, auto-runs
#    ai_cmd_is_destroy()    tier 3: destructive, always requires YES
#    ai_execute_tool()      dispatch semantic tool dicts from the AI
#    _safe_file_edit()      literal-replace file editing with backup
#
#  Three tiers:
#    READ    — auto-runs without confirmation
#    CHANGE  — requires confirm (or executive mode auto-runs it)
#    DESTROY — always requires typing YES
#
#  Verbose mode:
#    When IGOR_VERBOSE=true, shows the <explain> reasoning block (if present)
#    before executing each tool. Toggle with 'verbose on/off' in chat.
# ==============================================================================

# Load input validation library
if [ -f "${IGOR_DIR}/core/lib/input_validation.sh" ]; then
    source "${IGOR_DIR}/core/lib/input_validation.sh"
else
    echo "WARNING: input_validation.sh not found - some security features disabled" >&2
fi

# P3-2: Session-level command counters (reset at session start via _ai_reset_cmd_counters)
AI_CMD_READ=0
AI_CMD_CHANGE=0
AI_CMD_BLOCKED=0

_ai_reset_cmd_counters() {
    AI_CMD_READ=0
    AI_CMD_CHANGE=0
    AI_CMD_BLOCKED=0
}

# ── Hard denylist ─────────────────────────────────────────────────────────────
# Commands that can NEVER run regardless of tier or executive mode.
# nexusai.sh entries are intentional: that script is the v1 predecessor and may
# still exist on the host. Blocking it prevents the AI from accidentally running
# the old monolith and creating a recursive or conflicting management session.
# Other v1 function names (install_stack, nuke_and_reinstall, etc.) are NOT in
# this list because they don't exist as executables — they can't be shell-invoked.
ai_is_denied() {
    local cmd="$1"

    local denied_fixed=(
        "> /etc/fstab"      "> /etc/passwd"     "> /etc/shadow"
        "> /etc/hosts"      "> /etc/ssh"
        "mkfs"              "dd if="
        "curl | sh"         "curl | bash"       "curl|sh"   "curl|bash"
        "wget | sh"         "wget | bash"       "wget|sh"   "wget|bash"
        ":(){ :|:& };:"
        "dd if=/dev/zero of=/dev/mm"
        "dd if=/dev/zero of=/dev/sd"
        "bash ~/igor.sh"    "./igor.sh"         "bash ./igor.sh"
        "bash ~/nexusai.sh" "./nexusai.sh"      "bash ./nexusai.sh"   # nexusai.sh is the monolith predecessor — intentionally kept to block accidental execution if it still exists on host
        "cp ~/templates/nginx"  "cat ~/templates/nginx"
        "DELETE FROM oc_appconfig"
        "DELETE FROM oc_apps"
        "DROP TABLE oc_"
        "TRUNCATE oc_"
    )

    local denied_regex=(
        # Root and critical system directories
        "rm[[:space:]]+-[rf]+[[:space:]]+/$"
        "rm[[:space:]]+-[rf]+[[:space:]]+/\*"
        "rm[[:space:]]+-[rf]+[[:space:]]+/(etc|mnt|usr|bin|sbin|var/lib|home|root|dev|sys|proc|boot)($|/)"
        "rm[[:space:]]+-[rf]+[[:space:]]+~(/.*)?$"

        # Protect chmod/chown on root
        "chmod[[:space:]]+(-R[[:space:]]+)?777[[:space:]]+/$"
        "chown[[:space:]]+-R[[:space:]]+root[[:space:]]+/$"

        # Protect project modules and knowledge
        "rm[[:space:]]+-[rf]*[[:space:]]+.*igor/?$"
        "rm[[:space:]]+-[rf]*[[:space:]]+.*knowledge/?$"

        # Dangerous piping and execution
        "curl.+[|].+(sh|bash)"
        "wget.+[|].+(sh|bash)"
        "mkfs\."
        "nc[[:space:]]+-[el]"
        "base64[[:space:]]+-d.+[|]"
        "python[0-9]?[[:space:]]+-c.+exec"

        # Protect active script files — nexusai.sh kept intentionally (predecessor script may still exist on host)
        "rm.*(igor\.sh|nexusai\.sh|ai_knowledge\.sh|ai_scrub\.sh|docker-compose\.yml)[^.]"
        "rm.*web/nginx.*\.conf"
    )

    for pattern in "${denied_fixed[@]}"; do
        echo "$cmd" | grep -qF "$pattern" && return 0
    done
    for pattern in "${denied_regex[@]}"; do
        echo "$cmd" | grep -qE "$pattern" && return 0
    done
    return 1
}

# ── Tier 1: read-only commands ────────────────────────────────────────────────
# Returns 0 if command is read-only (auto-run), 1 if it writes state.
ai_cmd_is_read() {
    local cmd="$1"
    local write_patterns=(
        " > "   " >> "   "tee "
        "rm "  "mv "  "cp "  "mkdir "  "touch "  "chmod "  "chown "  "ln "
        "shred" "wipe" "truncate"
        "apt "  "apt-get"  "dpkg "  "pip "  "npm install"  "brew "
        "systemctl start"  "systemctl stop"  "systemctl restart"
        "systemctl enable"  "systemctl disable"  "systemctl mask"
        "service start"  "service stop"  "service restart"
        "docker compose up"    "docker compose down"   "docker compose restart"
        "docker compose pull"  "docker compose build"
        "docker exec"          "docker run"            "docker rm"
        "docker rmi"           "docker volume create"  "docker network create"
        "docker network rm"    "docker system prune"
        "occ config:system:set"  "occ config:app:set"  "occ maintenance"
        "occ upgrade"  "occ user:add"  "occ user:delete"  "occ app:enable"
        "occ app:disable"  "occ app:install"  "occ files:cleanup"
        "FLUSHALL"  "DROP "  "DELETE "  "TRUNCATE "  "INSERT "  "UPDATE "
        "redis-cli SET"  "redis-cli DEL"  "redis-cli FLUSHDB"
        "nano "  "vim "  "vi "  "emacs "  "pico "
        "nginx -s reload"  "nginx -s stop"
        "crontab -e"
        "sed -i"  "awk.*>"
    )
    for pattern in "${write_patterns[@]}"; do
        echo "$cmd" | grep -qF "$pattern" && return 1
    done
    return 0
}

# ── Tier 3: destructive commands ──────────────────────────────────────────────
ai_cmd_is_destroy() {
    local cmd="$1"
    local destroy_patterns=(
        "rm "               "docker volume rm"      "docker volume prune"
        "docker compose down"   "docker system prune"
        "FLUSHALL"          "DROP TABLE"            "DROP DATABASE"
        "DELETE FROM"       "TRUNCATE "
        "nuke"              "shred "                "wipe "
        "> /mnt/"
    )
    for pattern in "${destroy_patterns[@]}"; do
        echo "$cmd" | grep -qF "$pattern" && return 0
    done
    return 1
}

# ── Execute a semantic tool dict from the AI ─────────────────────────────────
# $1 = JSON tool dict e.g. {"tool":"occ","cmd":"status"}
# $2 = (optional) explain text to display in verbose mode
ai_execute_tool() {
    local tool_json="$1"
    local explain_text="${2:-}"
    local output=""

    # Extract JSON fields into T_* variables via Python
    eval "$(printf '%s' "$tool_json" | python3 -c '
import sys, json, shlex
try:
    d = json.load(sys.stdin)
    for k, v in d.items():
        print("T_{}={}".format(k.upper(), shlex.quote(str(v))))
except Exception as e:
    print("T_TOOL=error")
    print("T_ERROR=" + shlex.quote(str(e)))
' 2>/dev/null)"

    # P2-1: Normalise native tool names to internal names
    case "$T_TOOL" in
        host_command)     T_TOOL="host" ;;
        occ_command)      T_TOOL="occ" ;;
        container_action) T_TOOL="container" ;;
    esac

    local tier="READ"
    local run_cmd=""
    local display_cmd=""
    # For run_igor_action: populated in case block, used in execution block
    local _ria_fn="" _ria_mod=""

    case "$T_TOOL" in
        occ)
            T_CMD=$(ai_unscrub_inbound "$T_CMD")
            display_cmd="occ ${T_CMD}"
            run_cmd="docker compose exec -T -u www-data app php occ ${T_CMD}"
            # Classify occ commands: read-only subcommands → READ, state-changing → CHANGE
            # READ: :get, :list, :status, plain status, integrity:check-*, maintenance:mode (no args)
            if echo "$T_CMD" | grep -qE \
               '(^status[[:space:]]*$|:get|:list|:status|integrity:check|^maintenance:mode[[:space:]]*$)'; then
                tier="READ"
            else
                tier="CHANGE"
            fi
            ;;
        host)
            T_CMD=$(ai_unscrub_inbound "$T_CMD")
            if ai_is_denied "$T_CMD"; then
                echo -e "\n  ${RED}${BOLD}⛔ BLOCKED:${NC} Command is on the hard denylist." >&2
                echo -e "  ${RED}Matched:${NC} $T_CMD" >&2
                echo "[BLOCKED BY DENYLIST: ${T_CMD}]"
                return 1
            fi
            
            # Enhanced command validation using input_validation if available
            if declare -f sanitize_command >/dev/null; then
                if ! safe_cmd=$(sanitize_command "$T_CMD"); then
                    echo -e "\n  ${RED}${BOLD}⛔ BLOCKED:${NC} Command validation failed." >&2
                    echo -e "  ${RED}Reason:${NC} $safe_cmd" >&2
                    echo "[BLOCKED: Command validation failed]"
                    return 1
                fi
                T_CMD="$safe_cmd"
            fi
            
            if   ai_cmd_is_destroy "$T_CMD"; then tier="DESTROY"
            elif ai_cmd_is_read    "$T_CMD"; then tier="READ"
            else                                  tier="CHANGE"
            fi
            display_cmd="host: ${T_CMD}"
            
            # Use array for safe command execution
            run_cmd=("$T_CMD")
            ;;
        container)
            tier="CHANGE"
            display_cmd="docker compose ${T_ACTION} ${T_TARGET}"
            run_cmd="docker compose ${T_ACTION} ${T_TARGET}"
            ;;
        read_log)
            tier="READ"
            local _max_lines=50
            { [ "${T_LINES:-0}" -gt "$_max_lines" ] 2>/dev/null && T_LINES=$_max_lines; } || true
            display_cmd="read_log: ${T_TARGET} last ${T_LINES:-20} lines  search='${T_SEARCH}'"
            if [ "${T_TARGET}" = "terminal" ]; then
                local _tlog="/data/runtime/terminal.log"
                if [ -n "$T_SEARCH" ]; then
                    run_cmd="tail -n ${T_LINES:-20} $(printf '%q' "$_tlog") 2>/dev/null | grep -i $(printf '%q' "$T_SEARCH")"
                else
                    run_cmd="tail -n ${T_LINES:-20} $(printf '%q' "$_tlog") 2>/dev/null"
                fi
            elif [ -n "$T_SEARCH" ]; then
                run_cmd="docker compose logs --tail ${T_LINES:-20} ${T_TARGET} 2>&1 | grep -i $(printf '%q' "$T_SEARCH")"
            else
                run_cmd="docker compose logs --tail ${T_LINES:-20} ${T_TARGET} 2>&1"
            fi
            ;;
        edit_file)
            tier="CHANGE"
            display_cmd="edit_file: ${T_PATH}\n  find:    ${T_FIND}\n  replace: ${T_REPLACE}"
            ;;
        execute)
            # Legacy fallback — raw bash from <execute> tag
            local _cmd; _cmd=$(ai_unscrub_inbound "$T_CMD")
            if ai_is_denied "$_cmd"; then
                echo -e "\n  ${RED}${BOLD}⛔ BLOCKED:${NC} Command is on the hard denylist." >&2
                echo "[BLOCKED BY DENYLIST: ${_cmd}]"
                return 1
            fi
            if echo "$_cmd" | grep -q '<<'; then
                output="[BLOCKED: heredoc syntax (<<) not allowed. Use: printf '...' > /tmp/fix.py && python3 /tmp/fix.py]"
                echo -e "  ${RED}⛔ BLOCKED: heredoc syntax not allowed.${NC}" >&2
                echo "$output"; return 1
            fi
            if   ai_cmd_is_destroy "$_cmd"; then tier="DESTROY"
            elif ai_cmd_is_read    "$_cmd"; then tier="READ"
            else                                  tier="CHANGE"
            fi
            display_cmd="\$ ${_cmd}"
            run_cmd="$_cmd"
            ;;
        read_report)
            tier="READ"
            display_cmd="read_report: ${T_FILENAME}"
            local _rdir="${REPORTS_DIR:-${IGOR_DIR}/data/reports}"
            local _rfile="${_rdir}/${T_FILENAME}"
            if [ -z "$T_FILENAME" ]; then
                output="[ERROR: read_report requires a filename attribute]"
            elif [ ! -f "$_rfile" ]; then
                output="[ERROR: Report not found: ${T_FILENAME} — check 'RECENT REPORTS' in context]"
            else
                output=$(head -n 100 "$_rfile" 2>/dev/null)
                local _rlines; _rlines=$(wc -l < "$_rfile" 2>/dev/null || echo "?")
                [ "${_rlines:-0}" -gt 100 ] && \
                    output+=$'\n'"[... truncated at 100 lines — full file has ${_rlines} lines]"
            fi
            echo "$output"
            return 0
            ;;
        propose_menu_item)
            # AI proposes a new dynamic menu item
            tier="CHANGE"
            display_cmd="Propose dynamic menu item: ${T_TITLE}"
            output=$(_ai_propose_menu_item "$T_TITLE" "$T_DESCRIPTION" "$T_COMMAND" "$T_TYPE" "$T_TIER" 2>&1)
            local exit_code=$?
            ;;
        reply)
            # P2-1: Final reply tool — output prefixed message for caller to display and exit
            local _reply_msg
            _reply_msg=$(printf '%s' "$tool_json" | python3 -c "
import sys,json
try: print(json.load(sys.stdin).get('message',''))
except: pass
" 2>/dev/null)
            output="[REPLY] ${_reply_msg}"
            ;;
        run_igor_action)
            # Look up action in the capability catalog populated by igor_load_capabilities()
            local _ria_name="${T_CMD:-}"
            local _ria_entry="${_IGOR_CAPABILITIES[${_ria_name}]:-}"
            if [ -z "$_ria_entry" ]; then
                echo "[ERROR: Unknown Igor action '${_ria_name}' — check AVAILABLE IGOR ACTIONS in context]"
                return 1
            fi
            local _ria_desc _ria_tier _ria_probs _ria_mpath
            IFS='|' read -r _ria_desc _ria_fn _ria_mod _ria_tier _ria_probs _ria_mpath <<< "$_ria_entry"
            tier="${_ria_tier:-CHANGE}"
            display_cmd="Igor action: ${_ria_name} → ${_ria_fn}()  [${_ria_mpath:-module: ${_ria_mod}}]"
            ;;
        error|*)
            echo "[ERROR: Unknown or malformed tool — ${T_TOOL:-?}${T_ERROR:+ ($T_ERROR)}]"
            return 1
            ;;
    esac

    # ── P1-4: Pre-execution validation (CHANGE tier) ─────────────────────────
    # Call ai_validate.py for CHANGE-tier commands; block if verdict says blocked.
    # Warnings are shown but do not block; blocked commands return early.
    if [ "$tier" = "CHANGE" ]; then
        local _verdict_lines _v_blocked="" _v_reason="" _v_warnings=""
        _verdict_lines=$(_ai_validate_tool_call "$tool_json")
        while IFS= read -r _vline; do
            case "$_vline" in
                "BLOCKED: true")  _v_blocked="true" ;;
                "REASON: "*)      _v_reason="${_vline#REASON: }" ;;
                "WARNINGS: "*)
                    _v_warnings="${_vline#WARNINGS: }"
                    if [ -n "$_v_warnings" ]; then
                        echo "" >&2
                        IFS='|' read -ra _vw_arr <<< "$_v_warnings"
                        for _vw in "${_vw_arr[@]}"; do
                            [ -n "$_vw" ] && echo -e "  ${YEL}⚠  Validator: ${_vw}${NC}" >&2
                        done
                    fi
                    ;;
            esac
        done <<< "$_verdict_lines"
        if [ "$_v_blocked" = "true" ]; then
            echo -e "\n  ${RED}✘ Command blocked by validator: ${_v_reason}${NC}" >&2
            echo "[VALIDATION BLOCKED: ${_v_reason}]"
            _IGOR_LAST_EXEC_TIER="CHANGE"
            return 1
        fi
    fi

    # ── Verbose explanation box ───────────────────────────────────────────────
    if [ "${IGOR_VERBOSE:-true}" = "true" ] && [ -n "$explain_text" ]; then
        echo "" >&2
        echo -e "  ${CYAN}── WHY ──────────────────────────────────────────────────────${NC}" >&2
        echo "$explain_text" | fold -s -w 70 | sed 's/^/    /' >&2
        echo -e "  ${CYAN}────────────────────────────────────────────────────────────${NC}" >&2
    fi

    # ── UI tier display ───────────────────────────────────────────────────────
    # In quiet loop mode, suppress display for READ-only commands.
    local _ui_quiet=false
    [ "${IGOR_QUIET_LOOP:-false}" = "true" ] && [ "$tier" = "READ" ] && _ui_quiet=true

    if [ "$_ui_quiet" = "false" ]; then
        echo "" >&2
        case "$tier" in
            READ)    echo -e "  ${CYAN}── AUTO-RUNNING (read-only) ──────────────────────────────────${NC}" >&2 ;;
            CHANGE)  echo -e "  ${YEL}── NEEDS APPROVAL (modifies system) ──────────────────────────${NC}" >&2 ;;
            DESTROY) echo -e "  ${RED}${BOLD}── DESTRUCTIVE — DATA LOSS POSSIBLE ─────────────────────────${NC}" >&2 ;;
        esac
        echo -e "  ${BOLD}${display_cmd}${NC}" >&2
        echo "" >&2
    fi

    # ── Pre-CHANGE/DESTROY config auto-backup ─────────────────────────────────
    # Fire-and-forget: always returns 0, suppresses all output.
    if [[ "$tier" == "CHANGE" || "$tier" == "DESTROY" ]]; then
        declare -f config_backup_auto &>/dev/null && \
            config_backup_auto "pre-ai:${T_TOOL}" 2>/dev/null || true
    fi

    # ── Approval gate ─────────────────────────────────────────────────────────
    local run=false
    case "$tier" in
        READ) run=true ;;
        CHANGE)
            if ${executive_mode:-false}; then
                echo -e "  ${YEL}Executive mode — auto-running.${NC}" >&2
                run=true
            else
                confirm "Execute this tool?" && run=true
            fi
            ;;
        DESTROY)
            local conf
            read -rp "  ${RED}Type YES to run this destructive action:${NC} " conf </dev/tty
            [ "$conf" = "YES" ] && run=true
            ;;
    esac

    # ── Capture previous occ value for undo (before execution) ───────────────
    local _undo_prev_occ=""
    if [[ "$tier" == "CHANGE" && "$T_TOOL" == "occ" ]] && \
       [[ "$run_cmd" == *"config:system:set"* ]]; then
        local _undo_occ_arg; _undo_occ_arg=$(echo "$run_cmd" | sed 's/.*php occ //')
        _undo_prev_occ=$(python3 "${IGOR_DIR}/core/lib/undo_stack.py" get-prev-occ "$_undo_occ_arg" 2>/dev/null || echo "UNSET")
    fi

    if $run; then
        if [ "$T_TOOL" = "edit_file" ]; then
            output=$(_safe_file_edit "$T_PATH" "$T_FIND" "$T_REPLACE" 2>&1)
            local exit_code=$?
        elif [ "$T_TOOL" = "run_igor_action" ]; then
            # Load the module that owns this action, then call the function directly.
            # _ria_fn and _ria_mod were set in the case block above.
            if declare -f _igor_load_module &>/dev/null && [ -n "$_ria_mod" ]; then
                _igor_load_module "$_ria_mod" 2>/dev/null || true
            fi
            if ! declare -f "$_ria_fn" &>/dev/null; then
                output="[ERROR: Function ${_ria_fn} not found after loading module ${_ria_mod}]"
                local exit_code=1
            else
                output=$("$_ria_fn" </dev/null 2>&1)
                local exit_code=$?
            fi
        else
            # cd to IGOR_DIR before execution — prevents getcwd() failure when the
            # shell's working directory no longer exists (e.g. deleted temp dir).
            # Use array for safe command execution to prevent injection
            if [[ "$T_TOOL" == "host" && "${run_cmd[*]}" == *"bash -c"* ]]; then
                # For host commands with bash -c, use the array safely
                output=$(cd "${IGOR_DIR:-.}" 2>/dev/null || cd /tmp; "${run_cmd[@]}" </dev/null 2>&1)
                local exit_code=$?
            else
                # For other commands, use bash -c with the command string
                output=$(cd "${IGOR_DIR:-.}" 2>/dev/null || cd /tmp; bash -c "$run_cmd" </dev/null 2>&1)
                local exit_code=$?
            fi
        fi

        # Truncate long output
        local line_count; line_count=$(echo "$output" | wc -l)
        if [ "$line_count" -gt 35 ]; then
            local head_out tail_out
            head_out=$(echo "$output" | head -n 15)
            tail_out=$(echo "$output" | tail -n 10)
            output="${head_out}
[... $(( line_count - 25 )) lines omitted — use grep/head/tail to target output ...]
${tail_out}"
        fi
        if [ ${#output} -gt 2500 ]; then
            output="${output:0:2500}
[... truncated at 2500 chars ...]"
        fi

        if [ "$_ui_quiet" = "false" ]; then
            echo -e "  ${CYAN}── OUTPUT ────────────────────────────────────────────────────${NC}" >&2
            while IFS= read -r _oline; do echo "  $_oline" >&2; done <<< "$output"
            echo "" >&2
            [ $exit_code -eq 0 ] \
                && echo -e "  ${GRN}✔ done (exit 0)${NC}" >&2 \
                || echo -e "  ${YEL}! exit code: ${exit_code}${NC}" >&2
            echo -e "  ${CYAN}──────────────────────────────────────────────────────────────${NC}" >&2
        fi

        output="TOOL:${T_TOOL} EXIT:${exit_code}\nOUTPUT:\n${output}"
        [[ "$tier" == "CHANGE" || "$tier" == "DESTROY" ]] && ai_knowledge_mark_changed
        # P3-2: track executed command counts
        case "$tier" in
            READ)            (( AI_CMD_READ++ ))   || true ;;
            CHANGE|DESTROY)  (( AI_CMD_CHANGE++ )) || true ;;
        esac
        # Signal tier to the agentic loop so it can inject a verify reminder
        _IGOR_LAST_EXEC_TIER="$tier"

        # ── Change journal hook ────────────────────────────────────────────
        # Records every executed Igor (AI) action. ACTOR=igor distinguishes
        # AI-originated actions from diagnose fixes, menu actions, and web-UI changes.
        if declare -f journal_record &>/dev/null; then
            local _js="OK"; [ $exit_code -ne 0 ] && _js="FAIL"
            journal_record "igor" "occ_exec" "$tier" \
                "${run_cmd:-${display_cmd}}" "$_js" "exit:${exit_code}"
        fi

        # ── Undo stack push (CHANGE tier only, successful executions) ─────────
        if [[ "$tier" == "CHANGE" && $exit_code -eq 0 ]] && \
           declare -f _undo_stack_push_entry &>/dev/null; then
            _undo_stack_push_entry "$T_TOOL" "$run_cmd"
        fi

        # ── Notify hook — DESTROY-tier actions ────────────────────────────────
        if [ "$tier" = "DESTROY" ]; then
            local _ns="OK"; [ $exit_code -ne 0 ] && _ns="FAIL (exit ${exit_code})"
            declare -f notify_event &>/dev/null && \
                notify_event "destroy_action" \
                    "AI ran DESTROY command (${_ns}): ${display_cmd}" \
                    "DESTROY Action Executed" \
                2>/dev/null || true
        fi

        # ── Pattern auto-proposal hook (Milestone 5) ───────────────────────
        # After successful CHANGE/DESTROY repairs, check if pattern is auto-eligible
        if [ $exit_code -eq 0 ] && [[ "$tier" == "CHANGE" || "$tier" == "DESTROY" ]]; then
            declare -f pattern_eligible_check &>/dev/null && _ai_pattern_to_menu_hook "$T_TOOL" "$run_cmd"
        fi
    else
        # P1-6: User declined — write signal for loop banner, skip manual-handoff prompt.
        local _sig_file="/data/runtime/loop_signal.tmp"
        if [ "$tier" = "DESTROY" ]; then
            echo "DESTROY_DECLINED" > "$_sig_file"
            output="[USER DECLINED] Destructive command not confirmed: ${display_cmd}"
        else
            echo "CHANGE_DECLINED" > "$_sig_file"
            output="[USER DECLINED] Command skipped: ${display_cmd}"
        fi
        echo -e "  ${YEL}  (skipped — command not run)${NC}" >&2
        # P3-2: count declined/blocked commands
        (( AI_CMD_BLOCKED++ )) || true
    fi

    echo "$output"
}

# ── Safe file editing with backup + validation ───────────────────────────────
# Uses Python for literal string replacement — no sed, no awk, no regex escaping.
# Auto-validates nginx.conf after edit; rolls back on failure.
_safe_file_edit() {
    local path="$1"
    local find_str="$2"
    local replace_str="$3"
    local backup_path="${path}.bak.$(date +%s)"

    # Validate file path with enhanced security
    if declare -f validate_file_operation >/dev/null; then
        if ! safe_path=$(validate_file_operation "$path" "write"); then
            echo "Error: $safe_path"
            return 1
        fi
        path="$safe_path"
    else
        # Fallback validation if input_validation.sh not available
        if [ ! -f "$path" ]; then
            echo "Error: File not found on host: $path"
            return 1
        fi
    fi

    # Validate input strings
    if [ -z "$path" ]; then
        echo "Error: File path cannot be empty"
        return 1
    fi

    # Validate find and replace strings
    if [ -z "$find_str" ]; then
        echo "Error: <find> string cannot be empty"
        return 1
    fi

    # Check for dangerous patterns in replace string
    if echo "$replace_str" | grep -qE 'rm -rf|dd if=|mkfs|:|&|rm /'; then
        echo "Error: Dangerous replacement pattern detected"
        return 1
    fi

    echo "Creating backup: $backup_path"
    cp "$path" "$backup_path" || { echo "Error: Could not create backup."; return 1; }

    # Block empty <find> on nginx configs — "" in Python prepends content, corrupting the file
    if [ -z "$find_str" ] && [[ "$path" == *"nginx"* ]]; then
        echo "Error: Empty <find> is not allowed for nginx config files."
        echo "Read the file first with <host> grep -n 'keyword' ./web/nginx.conf </host>"
        echo "then provide a specific <find> string that uniquely matches the section to modify."
        mv "$backup_path" "$path"
        return 1
    fi

    export _SFE_PATH="$path" _SFE_FIND="$find_str" _SFE_REPLACE="$replace_str"
    python3 - << 'PYEOF'
import os, sys
path    = os.environ["_SFE_PATH"]
find    = os.environ["_SFE_FIND"]
replace = os.environ["_SFE_REPLACE"]
try:
    with open(path, "r") as f:
        content = f.read()
    if find not in content:
        print("Error: <find> text not found in file. No changes made.")
        sys.exit(1)
    with open(path, "w") as f:
        f.write(content.replace(find, replace, 1))
    print("Replacement applied.")
except Exception as e:
    print(f"Python error: {e}")
    sys.exit(1)
PYEOF
    local py_exit=$?
    unset _SFE_PATH _SFE_FIND _SFE_REPLACE

    if [ $py_exit -ne 0 ]; then
        echo "Rolling back to backup."
        mv "$backup_path" "$path"
        return 1
    fi

    if [[ "$path" == *"nginx.conf"* ]]; then
        echo "Validating nginx syntax..."
        if ! docker compose exec web nginx -t 2>&1; then
            echo "Nginx validation FAILED — rolling back."
            mv "$backup_path" "$path"
            return 1
        fi
        echo "Nginx OK — reloading."
        docker compose exec web nginx -s reload
    fi

    echo "Edit applied successfully. Backup kept at: $backup_path"
    return 0
}

# ── Propose dynamic menu item ────────────────────────────────────────────────
# Writes a pending dynamic menu item file to the config directory.
# $1=TITLE $2=DESCRIPTION $3=COMMAND $4=TYPE $5=TIER
_ai_propose_menu_item() {
    local title="$1"
    local description="$2"
    local command="$3"
    local item_type="$4"
    local tier="$5"

    # Validate inputs
    [ -z "$title" ] && { echo "Error: TITLE is required."; return 1; }
    [ -z "$description" ] && { echo "Error: DESCRIPTION is required."; return 1; }
    [ -z "$command" ] && { echo "Error: COMMAND is required."; return 1; }
    [ -z "$item_type" ] && { echo "Error: TYPE is required."; return 1; }
    [ -z "$tier" ] && { echo "Error: TIER is required."; return 1; }

    # Validate TYPE
    [[ ! "$item_type" =~ ^(ONE_TIME|REPEATING)$ ]] && \
        { echo "Error: TYPE must be ONE_TIME or REPEATING."; return 1; }

    # Validate TIER
    [[ ! "$tier" =~ ^(READ|CHANGE|DESTROY)$ ]] && \
        { echo "Error: TIER must be READ, CHANGE, or DESTROY."; return 1; }

    # Generate ID from timestamp
    local item_id="$(date +%s)"

    # Write item file
    mkdir -p "$items_dir"
    local item_file="${items_dir}/${item_id}.item"

    {
        echo "ID: ${item_id}"
        echo "TITLE: ${title}"
        echo "DESCRIPTION: ${description}"
        echo "COMMAND: ${command}"
        echo "TYPE: ${item_type}"
        echo "TIER: ${tier}"
        echo "APPROVED: 0"
        echo "CONFIRMED_COUNT: 0"
        echo "FAILED_COUNT: 0"
        echo "CREATED: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "AUTHOR: AI Assistant"
    } > "$item_file"

    echo "Dynamic menu item proposed: ${title}"
    echo "Item ID: ${item_id}"
    echo "Type: ${item_type} | Tier: ${tier}"
    echo ""
    echo "The item is pending user approval. It will appear in:"
    echo "  Maintenance → Pending menu items"
    echo ""
    echo "To approve it manually:"
    echo "  Edit ${item_id}.item and set APPROVED: 1"

    return 0
}

# ── Pattern to dynamic menu item hook ───────────────────────────────────────
# Checks if a successful repair matches an auto-eligible pattern and proposes
# a dynamic menu item for it. This is the bridge between pattern system
# (M4) and dynamic menu items (M5).
# $1 = tool_type $2 = command_executed
_ai_pattern_to_menu_hook() {
    local tool_type="$1"
    local cmd_executed="$2"

    # Only hook specific tool types
    case "$tool_type" in
        occ|host|container) ;;
        *) return 0 ;;
    esac

    # For Stage 1, this is a skeleton. Full implementation would:
    # 1. Match cmd_executed against known patterns
    # 2. Check pattern_eligible_check() for auto-eligibility
    # 3. If eligible, call _ai_propose_menu_item() with pattern data
    #
    # For now, this is documented for future enhancement as patterns accumulate.

    return 0
}

# ── Undo stack entry builder ─────────────────────────────────────────────────
# Called after successful CHANGE execution. Pushes an undo entry to the stack.
# Args: $1=tool $2=run_cmd
# Expects outer-scope vars: T_PATH T_FIND T_REPLACE _undo_prev_occ session_id
_undo_stack_push_entry() {
    local _tool="$1" _run_cmd="$2"
    local _ts; _ts=$(date -u +"%Y-%m-%dT%H:%M:%S")
    local _turn="${_ai_turn:-0}"
    local _igor_dir="${IGOR_DIR:-.}"
    local _py="${_igor_dir}/lib/undo_stack.py"
    [ -f "$_py" ] || return 0

    local _entry=""
    case "$_tool" in
        edit_file)
            _entry=$(python3 -c "
import json, sys
find_str = sys.argv[1]
repl_str = sys.argv[2]
path_str = sys.argv[3]
e = {
  'turn': int('${_turn}'),
  'timestamp': '${_ts}',
  'tool': 'edit_file',
  'forward': {'path': path_str, 'find': find_str, 'replace': repl_str},
  'reverse': {'path': path_str, 'find': repl_str, 'replace': find_str},
  'backup_path': path_str + '.bak.*'
}
print(json.dumps(e))
" "$T_FIND" "$T_REPLACE" "$T_PATH" 2>/dev/null) ;;
        occ)
            local _fwd_cmd; _fwd_cmd=$(echo "$_run_cmd" | sed 's/.*php occ //')
            local _prev="${_undo_prev_occ:-UNSET}"
            local _key; _key=$(echo "$_fwd_cmd" | awk '{print $2}')
            local _rev_cmd
            if [ "$_prev" = "UNSET" ]; then
                _rev_cmd="config:system:delete ${_key}"
            else
                _rev_cmd="config:system:set ${_key} --value=${_prev}"
            fi
            _entry=$(python3 -c "
import json
e = {
  'turn': int('${_turn}'),
  'timestamp': '${_ts}',
  'tool': 'occ',
  'forward': {'command': '${_fwd_cmd}'},
  'reverse': {'command': '${_rev_cmd}'},
  'previous_value': None if '${_prev}' == 'UNSET' else '${_prev}'
}
print(json.dumps(e))
" 2>/dev/null) ;;
        *)
            _entry=$(python3 -c "
import json
e = {
  'turn': int('${_turn}'),
  'timestamp': '${_ts}',
  'tool': '${_tool}',
  'forward': {'command': '${_run_cmd}'},
  'reverse': None,
  'manual_undo': True
}
print(json.dumps(e))
" 2>/dev/null) ;;
    esac

    [ -n "$_entry" ] && \
        python3 "$_py" push "${session_id:-unknown}" "$_entry" 2>/dev/null || true
}
