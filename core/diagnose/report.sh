#!/bin/bash
# ==============================================================================
#  IGOR — diagnose/report.sh
#  Session report formatter and log rotation.
#
#  Provides:
#    • _diag_write_report()          — format and save session report
#    • _diag_rotate_logs()           — prune oldest logs beyond DIAG_REPORT_KEEP
#    • _diag_format_results_section()— render _DIAG_RESULTS as report section
#    • _diag_format_fixes_section()  — render _DIAG_FIXES_APPLIED as report section
#    • _diag_format_raw_log()        — render _DIAG_LOG[] as report section
# ==============================================================================

# ── Write report ──────────────────────────────────────────────────────────────
_diag_write_report() {
    local session_dir="${IGOR_SESSIONS_DIR:-${IGOR_DIR}/data/sessions}"
    mkdir -p "$session_dir" 2>/dev/null || true

    local report_file="${session_dir}/${_DIAG[session_id]}.log"
    _DIAG[report_path]="$report_file"

    local duration=$(( $(date +%s) - ${_DIAG[start_ts]:-$(date +%s)} ))
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo "# Igor Diagnose Session Report — ${ts}"
        echo "# Mode: ${_DIAG[mode]:-normal} | Deep: ${_DIAG[deep]:-false}"
        echo "# Session ID: ${_DIAG[session_id]}"
        echo "# Duration: ${duration}s"
        echo "#"
        echo "# HARDWARE CONTEXT"
        echo "# Pi model:   ${_DIAG[env_pi_model]:-unknown}"
        echo "# Hostname:   ${_DIAG[env_hostname]:-unknown}"
        echo "# RAM total:  ${_DIAG[env_ram_total]:-?} MB"
        echo "# Swap total: ${_DIAG[env_swap_total]:-?} MB"
        echo "# Uptime:     ${_DIAG[env_uptime]:-unknown}"
        echo "# Docker:     ${_DIAG[env_docker_version]:-unknown}"
        echo "# Compose:    ${_DIAG[env_compose_version]:-unknown}"
        echo "# Roles:      ${_DIAG[env_roles_summary]:-none detected}"
        echo "#"

        # Phase summary
        echo "# PHASES"
        local p
        for p in 0 1 2 3 4 5; do
            local gate_key="gate_skip_${p}"
            local skip_reason="${_DIAG[$gate_key]:-}"
            if [ -n "$skip_reason" ]; then
                echo "# Phase ${p}: SKIPPED — ${skip_reason}"
            else
                # Count results for this phase
                local ok=0 warn=0 fail=0 crit=0
                local entry
                for entry in "${_DIAG_RESULTS[@]}"; do
                    [[ "$entry" == *"|phase${p}" ]] || continue
                    local sev="${entry%%|*}"
                    case "$sev" in
                        OK)       (( ok++   )) ;;
                        WARN)     (( warn++ )) ;;
                        FAIL)     (( fail++ )) ;;
                        CRITICAL) (( crit++ )) ;;
                    esac
                done
                if (( ok + warn + fail + crit == 0 )); then
                    echo "# Phase ${p}: (no checks run)"
                else
                    echo "# Phase ${p}: ✔ ${ok} OK  ⚠ ${warn} WARN  ✘ ${fail} FAIL  ✘ ${crit} CRITICAL"
                fi
            fi
        done
        echo "#"

        # Overall totals
        local total_ok=0 total_warn=0 total_fail=0 total_crit=0
        local entry
        for entry in "${_DIAG_RESULTS[@]}"; do
            local sev="${entry%%|*}"
            case "$sev" in
                OK)       (( total_ok++   )) ;;
                WARN)     (( total_warn++ )) ;;
                FAIL)     (( total_fail++ )) ;;
                CRITICAL) (( total_crit++ )) ;;
            esac
        done
        echo "# TOTALS"
        echo "# ✔ ${total_ok} OK  ⚠ ${total_warn} WARN  ✘ ${total_fail} FAIL  ✘ ${total_crit} CRITICAL"
        echo "#"

        # Results section — non-OK only
        echo "# RESULTS (non-OK)"
        _diag_format_results_section

        echo "#"

        # Fixes section
        echo "# FIXES"
        _diag_format_fixes_section

        echo "#"

        # Recovery info if applicable
        if [ -n "${_DIAG[recovery_triggered]:-}" ]; then
            echo "# RECOVERY"
            echo "# Triggered by: ${_DIAG[recovery_triggered]}"
            echo "#"
        fi

        # Raw log
        echo "# RAW LOG"
        _diag_format_raw_log

    } > "$report_file"

    _diag_rotate_logs "$session_dir"

    ok "Report saved: ${report_file}"
}

# ── Format results section ─────────────────────────────────────────────────────
_diag_format_results_section() {
    local any=false
    local entry
    for entry in "${_DIAG_RESULTS[@]}"; do
        local sev="${entry%%|*}"
        [ "$sev" = "OK" ] && continue
        any=true
        local rest="${entry#*|}"
        local code="${rest%%|*}"
        rest="${rest#*|}"
        local msg="${rest%%|*}"
        local phase="${rest##*|}"
        printf "%-10s %-35s %s (%s)\n" "$sev" "$code" "$msg" "$phase"
    done
    $any || echo "# (all checks passed)"
}

# ── Format fixes section ───────────────────────────────────────────────────────
_diag_format_fixes_section() {
    if [ ${#_DIAG_FIXES_APPLIED[@]} -eq 0 ]; then
        echo "# (no fixes attempted)"
        return
    fi
    local entry
    for entry in "${_DIAG_FIXES_APPLIED[@]}"; do
        # Format: CODE|TIER|CMD|OUTCOME
        local code="${entry%%|*}"
        local rest="${entry#*|}"
        local tier="${rest%%|*}"
        rest="${rest#*|}"
        local cmd="${rest%%|*}"
        local outcome="${rest##*|}"
        printf "%-10s %-35s %-12s %s\n" "$outcome" "$code" "$tier" "$cmd"
    done
}

# ── Format raw log section ─────────────────────────────────────────────────────
_diag_format_raw_log() {
    local line
    for line in "${_DIAG_LOG[@]}"; do
        echo "$line"
    done
}

# ── Log rotation ───────────────────────────────────────────────────────────────
# Keep at most DIAG_REPORT_KEEP session logs, deleting oldest first.
_diag_rotate_logs() {
    local session_dir="$1"
    local keep="${DIAG_REPORT_KEEP:-10}"

    # List all diag_*.log files sorted oldest first
    local files
    mapfile -t files < <(ls -t "${session_dir}"/diag_*.log 2>/dev/null | tail -n +"$(( keep + 1 ))")

    local f
    for f in "${files[@]}"; do
        rm -f "$f" 2>/dev/null || true
        _diag_log "report: pruned old log ${f}"
    done
}
