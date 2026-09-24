#!/bin/bash
# ==============================================================================
#  IGOR — diagnose/core.sh
#  Igor Diagnose: self-guided diagnostic, fix & recovery tool.
#
#  Entry point: menu_diagnose()
#
#  Provides:
#    • menu_diagnose()              — interactive mode selection menu
#    • _diag_init_session()         — initialise session state + heartbeat
#    • _diag_run_session()          — mode dispatch: normal/deep/fix/watch/report/recovery
#    • _diag_run_all_phases()       — gated phase orchestration with output
#    • _diag_run_all_phases_silent()— same, no step() output (for watch/report modes)
#    • _diag_show_results_summary() — count + list non-OK results
#    • _diag_gate_fail()            — record phase skip with reason
#    • _diag_phase_had_critical()   — check if a phase produced CRITICAL results
#    • Gate helpers                 — _diag_gate_check_hd_mounted, _stack_up, _app_responding
#    • _diag_run_watch_loop()       — watch mode timer loop
#    • _diag_run_recovery_sequence()— heartbeat-triggered recovery
#    • _diag_cleanup()              — remove heartbeat file on EXIT
#    • _diag_log()                  — append timestamped entry to _DIAG_LOG[]
#
#  Sourced files: roles.sh, phases.sh, fixes.sh, sequences.sh, report.sh
# ==============================================================================

# ── Source all diagnose subsystem files ───────────────────────────────────────
_DIAG_DIR="${IGOR_DIR}/core/diagnose"
for _diag_file in roles.sh phases.sh fixes.sh sequences.sh report.sh; do
    if [ -f "${_DIAG_DIR}/${_diag_file}" ]; then
        source "${_DIAG_DIR}/${_diag_file}"
    else
        fail "Diagnose subsystem missing: ${_DIAG_DIR}/${_diag_file}"
        pause
        return 1
    fi
done
unset _diag_file

# ── Session state ─────────────────────────────────────────────────────────────
# Initialised fresh per _diag_init_session(). Global so all functions share state.
# Guard: only declare on first source — re-sourcing would reset all state.
if ! declare -p _DIAG &>/dev/null 2>&1; then
declare -gA _DIAG=(
    [session_id]=""
    [start_ts]=""
    [mode]="normal"
    [deep]="false"
    [current_phase]=""
    [fixes_proposed]=0
    [fixes_applied]=0
    [fixes_verified]=0
    [watch_interval]="${DIAG_WATCH_INTERVAL:-30}"
    [watch_prev_hash]=""
    [recovery_triggered]=""
    [heartbeat_file]="${IGOR_RUNTIME_DIR:-${IGOR_DIR}/data/runtime}/diag_heartbeat"
    [report_path]=""
    [env_hostname]=""
    [env_pi_model]=""
    [env_docker_version]=""
    [env_compose_version]=""
    [env_ram_total]=""
    [env_swap_total]=""
    [env_uptime]=""
    [env_roles_summary]=""
)
fi  # end _DIAG guard

_DIAG_RESULTS=()
_DIAG_FIXES_APPLIED=()
_DIAG_LOG=()
declare -gA _DIAG_ROLES=()

# Application/container phases are opt-in.  A module directory or a Docker
# binary alone does not make Nextcloud diagnostics applicable.
_diag_nextcloud_active() {
    if declare -f igor_has_capability >/dev/null 2>&1; then
        igor_has_capability nextcloud
        return $?
    elif declare -f igor_has_module >/dev/null 2>&1; then
        igor_has_module nextcloud_docker
        return $?
    fi
    return 1
}

# ── Log helper ─────────────────────────────────────────────────────────────────
_diag_log() {
    _DIAG_LOG+=("[$(date '+%H:%M:%S')] $1")
}

# ── Menu entry ─────────────────────────────────────────────────────────────────
menu_diagnose() {
    # CLI mode bypass: if _DIAG_CLI_MODE is set, skip the menu
    if [ -n "${_DIAG_CLI_MODE:-}" ]; then
        _diag_init_session "$_DIAG_CLI_MODE"
        _diag_run_session
        return
    fi

    # Auto-recovery: if called with _DIAG_RECOVERY_REQUESTED set
    if [ "${_DIAG_RECOVERY_REQUESTED:-false}" = "true" ]; then
        unset _DIAG_RECOVERY_REQUESTED
        _diag_init_session "recovery"
        _diag_run_session
        return
    fi

    while true; do
        # ── Right pane: diagnose context ──────────────────────────────────────
        if declare -f igor_right_render &>/dev/null; then
            igor_right_render "Diagnose" \
                "---"  "Scan modes" \
                "hint" "[1]  NORMAL SCAN" \
                "hint" "[2]  DEEP SCAN" \
                "hint" "[3]  FIX MODE" \
                "hint" "[4]  WATCH MODE" \
                "hint" "[5]  SAVE REPORT" \
                "---"  "Sequences" \
                "hint" "[7]  COLD START" \
                "hint" "[8]  POST-UPDATE" \
                "hint" "[b]  BACK"
        fi

        local opt
        opt=$(igor_fzf_pick "Diagnose" \
            "_:SCAN MODES:" \
            "1:NORMAL SCAN:All checks — propose fixes interactively" \
            "2:DEEP SCAN:Extended checks — slow queries, full log scan" \
            "3:FIX MODE:Skip straight to fix loop (rescan if needed)" \
            "4:WATCH MODE:Re-scan on interval, show state changes only" \
            "5:SAVE REPORT:Scan silently — write report file (cron-safe)" \
            "6:RECOVERY MODE:Guided recovery for unclean shutdowns" \
            "_:SEQUENCES:" \
            "7:COLD START:Full stack start from stopped state" \
            "8:POST-UPDATE:occ upgrade + repair + disable maintenance" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        echo -e "  ${CYAN}${BOLD}Igor Diagnose${NC} — Deep diagnostic, fix & recovery"
        echo ""
        echo -e "  ${CYAN}1.${NC} Normal scan      — All checks, propose fixes interactively"
        echo -e "  ${CYAN}2.${NC} Deep scan         — Extended checks (slow queries, full log scan)"
        echo -e "  ${CYAN}3.${NC} Fix mode          — Skip straight to fix loop (rescan if needed)"
        echo -e "  ${CYAN}4.${NC} Watch mode        — Re-scan on interval, show state changes only"
        echo -e "  ${CYAN}5.${NC} Save report       — Scan silently, write report file (cron-safe)"
        echo -e "  ${CYAN}6.${NC} Recovery mode     — Guided recovery for unclean shutdowns"
        echo ""
        echo -e "  ${CYAN}7.${NC} Cold-start sequence   — Full stack start from stopped state"
        echo -e "  ${CYAN}8.${NC} Post-update recovery  — occ upgrade + repair + disable maintenance"
        echo ""
        echo -e "  ${CYAN}B.${NC} Back to main menu"
        echo ""
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case "$opt" in
            1) _diag_init_session "normal";    _diag_run_session ;;
            2) _diag_init_session "deep";      _diag_run_session ;;
            3) _diag_init_session "fix";       _diag_run_session ;;
            4)
                local interval
                interval=$(ask "Watch interval (seconds)" "${DIAG_WATCH_INTERVAL:-30}")
                _diag_init_session "watch"
                _DIAG[watch_interval]="${interval:-30}"
                _diag_run_session
                ;;
            5) _diag_init_session "report";   _diag_run_session ;;
            6) _diag_init_session "recovery"; _diag_run_session ;;
            7) _diag_init_session "normal";   _diag_sequence_cold_start;      _diag_cleanup ;;
            8) _diag_init_session "normal";   _diag_sequence_post_update;     _diag_cleanup ;;
            b|B) return ;;
            *) warn "Invalid option." ; pause ;;
        esac
    done
}

# ── Initialise session ─────────────────────────────────────────────────────────
_diag_init_session() {
    local mode="${1:-normal}"

    # Reset all state for a fresh session
    _DIAG[session_id]="diag_$(date '+%Y%m%d_%H%M%S')"
    _DIAG[start_ts]=$(date +%s)
    _DIAG[mode]="$mode"
    _DIAG[deep]="false"
    [ "$mode" = "deep" ] && _DIAG[deep]="true"
    _DIAG[current_phase]=""
    _DIAG[fixes_proposed]=0
    _DIAG[fixes_applied]=0
    _DIAG[fixes_verified]=0
    _DIAG[watch_prev_hash]=""
    _DIAG[recovery_triggered]=""
    _DIAG[report_path]=""

    _DIAG_RESULTS=()
    _DIAG_FIXES_APPLIED=()
    _DIAG_LOG=()
    declare -gA _DIAG_ROLES=()

    # Write heartbeat file (removed on clean exit via _diag_cleanup)
    local hb="${_DIAG[heartbeat_file]}"
    mkdir -p "$(dirname "$hb")" 2>/dev/null || true
    touch "$hb" 2>/dev/null || true

    # Register EXIT trap (chain with any existing trap)
    trap '_diag_cleanup; exit' EXIT INT TERM

    _diag_log "session init: id=${_DIAG[session_id]} mode=${mode}"
}

# ── Session cleanup ────────────────────────────────────────────────────────────
_diag_cleanup() {
    rm -f "${_DIAG[heartbeat_file]}" 2>/dev/null || true
    _diag_log "session cleanup: heartbeat removed"
}

# ── Mode dispatch ──────────────────────────────────────────────────────────────
_diag_run_session() {
    local mode="${_DIAG[mode]}"
    local deep="${_DIAG[deep]}"

    _diag_log "session start: mode=${mode}"

    case "$mode" in
        normal)
            _diag_run_all_phases
            _diag_show_results_summary
            _diag_propose_fixes
            _diag_offer_fix_loop
            _diag_write_report
            _diag_offer_send_to_ai
            pause
            ;;
        deep)
            _diag_run_all_phases true
            _diag_show_results_summary
            _diag_propose_fixes
            _diag_offer_fix_loop
            _diag_write_report
            _diag_offer_send_to_ai
            pause
            ;;
        fix)
            # If no results from a previous run, scan first
            if [ ${#_DIAG_RESULTS[@]} -eq 0 ]; then
                info "Running scan first..."
                _diag_run_all_phases_silent
            fi
            _diag_show_results_summary
            _diag_propose_fixes
            _diag_offer_fix_loop
            _diag_write_report
            _diag_offer_send_to_ai
            pause
            ;;
        watch)
            _diag_run_watch_loop
            ;;
        report)
            _diag_run_all_phases_silent
            _diag_write_report
            ;;
        recovery)
            _diag_run_recovery_sequence
            _diag_write_report
            _diag_offer_send_to_ai
            pause
            ;;
        *)
            warn "Unknown mode: ${mode} — running normal scan"
            _diag_run_all_phases
            _diag_show_results_summary
            _diag_propose_fixes
            _diag_offer_fix_loop
            _diag_write_report
            pause
            ;;
    esac

    _diag_cleanup
    _diag_log "session end: mode=${mode}"
}

# ── Run all phases with gating and output ──────────────────────────────────────
_diag_run_all_phases() {
    local deep="${1:-${_DIAG[deep]:-false}}"

    # Phase 0 — always runs
    _diag_phase_0

    # Phase 1 is generic host diagnostics and does not require Docker.
    _diag_phase_1 "$deep"

    # Phase 2 — always runs (disk/mount checks need no docker)
    _diag_phase_2 "$deep"

    # Container phases belong to the active application module.  On a
    # system-only installation they are not applicable and remain silent.
    if ! _diag_nextcloud_active; then
        _diag_log "container/application phases skipped: nextcloud_docker inactive"
        return
    fi

    # Phase 3 — requires HD mounted AND stack has ≥1 running container
    if _diag_gate_check_hd_mounted && _diag_gate_check_stack_up; then
        _diag_phase_3 "$deep"
    else
        local reason="HD not mounted or no containers running"
        mount | grep -q "${HD_MOUNT:-/mnt/nextclouddata}" 2>/dev/null || reason="HD not mounted"
        _diag_gate_fail 3 "$reason"
        _diag_gate_fail 4 "Phase 3 skipped"
        _diag_gate_fail 5 "Phase 3 skipped"
        return
    fi

    # Phase 4 — requires no CRITICAL results from Phase 3
    if _diag_phase_had_critical 3; then
        _diag_gate_fail 4 "Phase 3 produced CRITICAL results — cross-container checks unreliable"
        _diag_gate_fail 5 "Phase 4 skipped"
        return
    else
        _diag_phase_4 "$deep"
    fi

    # Phase 5 — requires Phase 4 not gated AND app responds
    if [ -n "${_DIAG[gate_skip_4]:-}" ]; then
        _diag_gate_fail 5 "Phase 4 was skipped"
    elif ! _diag_gate_check_app_responding; then
        _diag_gate_fail 5 "App health gate check failed — no module registered or endpoint not responding"
    else
        # Run application-layer checks from loaded modules via "app_diagnose" hook (in-process)
        local _p5_fns _p5_ran=false
        _p5_fns=$(igor_get_hooks "app_diagnose" 2>/dev/null)
        if [ -n "$_p5_fns" ]; then
            for _fn in $_p5_fns; do
                if declare -f "$_fn" &>/dev/null; then
                    _p5_ran=true
                    "$_fn" "$deep"
                fi
            done
        fi
        $_p5_ran || _diag_gate_fail 5 "No application-layer module loaded (nextcloud_docker not active)"
    fi
}

# ── Run all phases silently (no step() output) ─────────────────────────────────
_diag_run_all_phases_silent() {
    local deep="${1:-${_DIAG[deep]:-false}}"
    # Suppress step() by temporarily redefining it
    local _orig_step
    _orig_step=$(declare -f step)
    step() { :; }
    info() { :; }
    _diag_run_all_phases "$deep"
    # Restore step and info
    eval "$_orig_step" 2>/dev/null || true
    # Restore info (simpler since it's in lib/ui.sh)
    source "${IGOR_DIR}/core/lib/ui.sh" 2>/dev/null || true
}

# ── Show results summary ───────────────────────────────────────────────────────
_diag_show_results_summary() {
    local ok=0 warn=0 fail=0 crit=0
    local entry
    for entry in "${_DIAG_RESULTS[@]}"; do
        local sev="${entry%%|*}"
        case "$sev" in
            OK)       (( ok++   )) ;;
            WARN)     (( warn++ )) ;;
            FAIL)     (( fail++ )) ;;
            CRITICAL) (( crit++ )) ;;
        esac
    done

    echo ""
    echo -e "  ${BOLD}── Results ──────────────────────────────────────────────${NC}"
    echo -e "  Health: ${GRN}✔ ${ok} OK${NC}  ${YEL}⚠ ${warn} WARN${NC}  ${RED}✘ ${fail} FAIL${NC}  ${RED}${BOLD}✘ ${crit} CRITICAL${NC}"
    echo ""

    local any_issues=false
    for entry in "${_DIAG_RESULTS[@]}"; do
        local sev="${entry%%|*}"
        [ "$sev" = "OK" ] && continue
        any_issues=true
        local rest="${entry#*|}"
        local code="${rest%%|*}"
        rest="${rest#*|}"
        local msg="${rest%%|*}"
        local phase="${rest##*|}"
        case "$sev" in
            WARN)     echo -e "  ${YEL}⚠${NC} [${phase}] ${code}: ${msg}" ;;
            FAIL)     echo -e "  ${RED}✘${NC} [${phase}] ${code}: ${msg}" ;;
            CRITICAL) echo -e "  ${RED}${BOLD}✘ CRITICAL${NC} [${phase}] ${code}: ${msg}" ;;
        esac
    done

    $any_issues || ok "All checks passed."

    # Show skipped phases
    local p
    for p in 1 2 3 4 5; do
        local skip="${_DIAG[gate_skip_${p}]:-}"
        [ -n "$skip" ] && echo -e "  ${CYAN}i${NC} Phase ${p} skipped: ${skip}"
    done

    echo ""
}

# ── Gate helpers ───────────────────────────────────────────────────────────────
_diag_gate_fail() {
    local phase="$1" reason="$2"
    _DIAG["gate_skip_${phase}"]="$reason"
    warn "Phase ${phase} skipped: ${reason}"
    _diag_log "gate: phase ${phase} skipped — ${reason}"
}

_diag_phase_had_critical() {
    local phase="$1"
    local entry
    for entry in "${_DIAG_RESULTS[@]}"; do
        local sev="${entry%%|*}"
        [[ "$entry" == *"|phase${phase}" ]] && [ "$sev" = "CRITICAL" ] && return 0
    done
    return 1
}

_diag_gate_check_hd_mounted() {
    mount 2>/dev/null | grep -q "${HD_MOUNT:-/mnt/nextclouddata}"
}

_diag_gate_check_stack_up() {
    local count
    count=$(docker compose ps --status running --services 2>/dev/null | wc -l)
    (( count > 0 ))
}

_diag_gate_check_app_responding() {
    # Dispatch to registered health_gate hooks (in-process, returns 0=pass 1=fail).
    # Registered by modules via: igor_register_hook "health_gate" "fn_name"
    # Falls back to 'pass' (return 0) if no hooks registered — degrade gracefully.
    if declare -f igor_get_hooks &>/dev/null; then
        local _any_registered=false _fn
        for _fn in $(igor_get_hooks "health_gate" 2>/dev/null); do
            declare -f "$_fn" &>/dev/null || continue
            _any_registered=true
            "$_fn" && return 0
            return 1
        done
        $_any_registered || return 0  # no hooks = no gate to pass/fail
    fi
    return 0
}

# ── Watch mode loop ────────────────────────────────────────────────────────────
_diag_run_watch_loop() {
    local interval="${_DIAG[watch_interval]:-30}"
    info "Watch mode: scanning every ${interval}s. Press Ctrl-C to stop."
    echo ""

    while true; do
        # Fresh scan
        _DIAG_RESULTS=()
        _DIAG_LOG=()
        declare -gA _DIAG_ROLES=()
        unset "${!_DIAG[gate_skip_*]}" 2>/dev/null || true

        _diag_run_all_phases_silent

        # Hash severity+code (not message — messages contain variable data)
        local current_hash
        current_hash=$(printf '%s\n' "${_DIAG_RESULTS[@]}" | cut -d'|' -f1-2 | sort | md5sum 2>/dev/null | cut -d' ' -f1 || echo "x")

        if [ "${_DIAG[watch_prev_hash]}" != "$current_hash" ]; then
            echo ""
            step "State change — $(date '+%H:%M:%S')"
            _diag_show_results_summary
            _DIAG[watch_prev_hash]="$current_hash"
        else
            echo -ne "\r  ${CYAN}i${NC} No change at $(date '+%H:%M:%S') — next scan in ${interval}s   "
        fi

        sleep "$interval"
    done
}

# ── Recovery mode ──────────────────────────────────────────────────────────────
# ── Offer to send diagnose report to the AI assistant ─────────────────────────
# Called after self-healing completes for interactive modes (normal/deep/fix/recovery).
# Writes a structured summary to knowledge/last_diag.md and optionally launches AI.
_diag_offer_send_to_ai() {
    local report_path="${_DIAG[report_path]:-}"

    # Nothing to send if no results were collected
    [ ${#_DIAG_RESULTS[@]} -eq 0 ] && return 0

    echo ""
    echo -e "  ${CYAN}──────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Send report to AI assistant?${NC}"
    echo -e "  ${CYAN}──────────────────────────────────────────────────────${NC}"
    echo ""

    # Count severities
    local ok=0 warn=0 fail=0 crit=0
    local entry
    for entry in "${_DIAG_RESULTS[@]}"; do
        case "${entry%%|*}" in
            OK)       (( ok++   )) ;;
            WARN)     (( warn++ )) ;;
            FAIL)     (( fail++ )) ;;
            CRITICAL) (( crit++ )) ;;
        esac
    done

    local fixes_count=${#_DIAG_FIXES_APPLIED[@]}
    local mode="${_DIAG[mode]:-normal}"
    local duration=$(( $(date +%s) - ${_DIAG[start_ts]:-$(date +%s)} ))

    echo -e "  ${GRN}✔ ${ok} OK${NC}  ${YEL}⚠ ${warn} WARN${NC}  ${RED}✘ ${fail} FAIL  ✘ ${crit} CRITICAL${NC}"
    echo -e "  Fixes applied: ${fixes_count} | Duration: ${duration}s"
    echo ""

    confirm "  Add this diagnose report to AI knowledge?" || return 0

    # ── Write knowledge/last_diag.md ──────────────────────────────────────────
    local knowledge_dir="${IGOR_DIR}/knowledge"
    mkdir -p "$knowledge_dir" 2>/dev/null || true
    local last_diag_file="${knowledge_dir}/last_diag.md"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo "## Diagnose Report — ${ts}"
        echo "**Mode:** ${mode} | **Deep:** ${_DIAG[deep]:-false} | **Duration:** ${duration}s"
        echo ""

        # Findings — non-OK only
        echo "### Findings"
        local any_issues=false
        for entry in "${_DIAG_RESULTS[@]}"; do
            local sev="${entry%%|*}"
            [ "$sev" = "OK" ] && continue
            any_issues=true
            local rest="${entry#*|}"
            local code="${rest%%|*}"
            rest="${rest#*|}"
            local msg="${rest%%|*}"
            local phase="${rest##*|}"
            echo "- **${sev}** \`${code}\`: ${msg} (${phase})"
        done
        $any_issues || echo "- All checks passed."
        echo ""

        # Fixes applied
        echo "### Fixes Applied"
        if [ ${#_DIAG_FIXES_APPLIED[@]} -eq 0 ]; then
            echo "- No fixes applied."
        else
            for entry in "${_DIAG_FIXES_APPLIED[@]}"; do
                local code="${entry%%|*}"
                local rest="${entry#*|}"
                local tier="${rest%%|*}"
                rest="${rest#*|}"
                local cmd="${rest%%|*}"
                local outcome="${rest##*|}"
                echo "- **${outcome}** \`${code}\` [${tier}]: \`${cmd}\`"
            done
        fi
        echo ""

        # Phase skip summary (compact)
        local skipped=""
        local p
        for p in 0 1 2 3 4 5; do
            local sk="${_DIAG[gate_skip_${p}]:-}"
            [ -n "$sk" ] && skipped+="Phase ${p}: ${sk}; "
        done
        if [ -n "$skipped" ]; then
            echo "### Skipped Phases"
            echo "${skipped%%; }"
            echo ""
        fi

        echo "### Totals"
        echo "✔ ${ok} OK  ⚠ ${warn} WARN  ✘ ${fail} FAIL  ✘ ${crit} CRITICAL  — ${fixes_count} fix(es) applied"
        [ -n "$report_path" ] && echo "" && echo "_Full report: \`${report_path}\`_"

    } > "$last_diag_file"

    ok "Report saved to AI knowledge: ${last_diag_file}"

    # ── Offer to ask Igor AI assistant ────────────────────────────────────────
    echo ""
    confirm "  Ask Igor AI assistant?" || return 0

    # Read current AI settings for display
    local _ai_cfg="${IGOR_DIR}/ai_settings.env"
    local _cur_provider _cur_model
    _cur_provider=$(grep "^provider=" "$_ai_cfg" 2>/dev/null | cut -d= -f2-)
    _cur_model=$(grep "^model="    "$_ai_cfg" 2>/dev/null | cut -d= -f2-)
    _cur_provider="${_cur_provider:-openrouter}"
    _cur_model="${_cur_model:-default}"

    echo ""
    local _ai_choice
    _ai_choice=$(igor_fzf_pick "Ask Igor AI" \
        "d:DEFAULT:Use current settings  (${_cur_provider} / ${_cur_model})" \
        "c:CONFIGURE:Choose a different provider or model first" \
        "q:CANCEL:Return without opening AI")
    case $? in
        1) return 0 ;;
        2)
            echo -e "  ${BOLD}Ask Igor AI${NC}"
            echo -e "  ${CYAN}d.${NC} Default  (${_cur_provider} / ${_cur_model})"
            echo -e "  ${CYAN}c.${NC} Configure first"
            echo -e "  ${CYAN}q.${NC} Cancel"
            echo ""
            read -rp "  [d/c/q]: " _ai_choice ;;
    esac

    case "$_ai_choice" in
        q|Q) return 0 ;;
        d|D|c|C)
            # Load the real AI subsystem (not the stub in igor.sh)
            if declare -f _igor_load_subsystem &>/dev/null; then
                _igor_load_subsystem "ai" "${IGOR_DIR}/core/ai/core.sh"
            else
                source "${IGOR_DIR}/core/ai/core.sh" 2>/dev/null || {
                    warn "AI subsystem not found at ${IGOR_DIR}/core/ai/core.sh"
                    return 0
                }
            fi
            echo ""
            export _DIAG_AI_REPORT_FILE="$last_diag_file"
            menu_ai
            unset _DIAG_AI_REPORT_FILE
            ;;
    esac
}

# ── Recovery mode ──────────────────────────────────────────────────────────────
_diag_run_recovery_sequence() {
    step "Recovery Mode"

    local reason="${_DIAG[recovery_triggered]:-manual}"
    warn "Recovery triggered: ${reason}"
    echo ""

    info "Running quick scan to assess current state..."
    _diag_run_all_phases_silent
    _diag_show_results_summary

    echo ""
    local seq_choice
    seq_choice=$(igor_fzf_pick "Recovery — Select sequence" \
        "1:UNCLEAN SHUTDOWN:Recommended after crash or power cut" \
        "2:COLD START:Full stack was stopped, bring it back up" \
        "3:POST-UPDATE:Failed occ upgrade — repair and clear maintenance" \
        "4:FIX LOOP:Skip sequence, go straight to interactive fix loop")
    case $? in
        1|2)
            info "Available recovery sequences:"
            echo -e "  ${CYAN}1.${NC} Unclean shutdown recovery (recommended after crash/power cut)"
            echo -e "  ${CYAN}2.${NC} Cold-start sequence (stack was fully stopped)"
            echo -e "  ${CYAN}3.${NC} Post-update recovery (failed occ upgrade)"
            echo -e "  ${CYAN}4.${NC} Skip sequence, go to fix loop"
            echo ""
            read -rp "  Select recovery sequence: " seq_choice ;;
    esac
    case "$seq_choice" in
        1) _diag_sequence_unclean_shutdown ;;
        2) _diag_sequence_cold_start ;;
        3) _diag_sequence_post_update ;;
        4)
            _diag_propose_fixes
            _diag_offer_fix_loop
            ;;
        *) warn "Invalid choice — running unclean shutdown recovery"
           _diag_sequence_unclean_shutdown ;;
    esac
}
