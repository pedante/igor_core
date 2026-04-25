#!/bin/bash
# IGOR — recovery/core.sh
# Main recovery menu: orchestrates all recovery subsystems.
# Sourced by modules/recovery.sh on first use (lazy-loaded).
#
# Sources: journal.sh, config_backup.sh, full_backup.sh, apps.sh, schedule.sh
#
# Public functions:
#   menu_recovery                    — main recovery menu loop
#   _mod_recovery_browser            — unified restore point browser
#   _mod_recovery_exec_tier CMD TIER — tier-gated execution for rollback steps
#   _mod_recovery_journal_ui         — journal viewer + rollback launcher
#   _mod_recovery_startup_check      — called from igor.sh startup (app diff + alert scan)

# ── Load all recovery subsystems ──────────────────────────────────────────────
_recovery_load_all() {
    local base="${IGOR_DIR}"
    for mod in journal.sh config_backup.sh full_backup.sh apps.sh schedule.sh cron_setup.sh; do
        local f="${base}/core/recovery/${mod}"
        if [ -f "$f" ]; then
            # journal.sh may already be sourced at startup — re-sourcing is safe (only defines funcs)
            source "$f" 2>/dev/null || true
        else
            warn "Recovery module not found: ${f}"
        fi
    done
    # Init journal (creates dirs, SQLite schema)
    declare -f journal_init &>/dev/null && journal_init 2>/dev/null || true
}

# ── menu_recovery ─────────────────────────────────────────────────────────────
menu_recovery() {
    _recovery_load_all

    local RED='\033[0;31m' GRN='\033[0;32m' YEL='\033[1;33m'
    local CYAN='\033[0;36m' MAG='\033[0;35m' BOLD='\033[1m' NC='\033[0m'

    while true; do
        # ── Header stats ──────────────────────────────────────────────────────
        local _bdir; _bdir=$(declare -f _cb_backup_dir &>/dev/null && _cb_backup_dir || \
            echo "${IGOR_BACKUPS_DIR:-${IGOR_DIR}/data/backups}")
        local last_snapshot="" last_full_backup=""
        local latest_snap; latest_snap=$(ls -t "${_bdir}"/config_*.tar.gz 2>/dev/null | head -1)
        local latest_full; latest_full=$(ls -dt "${_bdir}"/full_* 2>/dev/null | head -1)
        if [ -n "$latest_snap" ]; then
            local _ep; _ep=$(basename "$latest_snap" | grep -oE '[0-9]+' | head -1)
            last_snapshot=$(date -d "@${_ep}" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$_ep")
        fi
        if [ -n "$latest_full" ]; then
            local _ep2; _ep2=$(basename "$latest_full" | grep -oE '[0-9]+' | head -1)
            last_full_backup=$(date -d "@${_ep2}" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$_ep2")
        fi
        local journal_count=0
        [ -f "${JOURNAL_LOG:-}" ] && \
            journal_count=$(wc -l < "${JOURNAL_LOG}" 2>/dev/null || echo 0)

        # ── Right pane: recovery context ──────────────────────────────────────
        if declare -f igor_right_render &>/dev/null; then
            igor_right_render "Recovery & Backup" \
                "Last snapshot"   "${last_snapshot:-(none)}" \
                "Last full backup" "${last_full_backup:-(none)}" \
                "Journal entries" "${journal_count}" \
                "---"             "Quick actions" \
                "hint"            "[1]  TAKE SNAPSHOT" \
                "hint"            "[2]  FULL BACKUP" \
                "hint"            "[4]  BROWSE SNAPSHOTS" \
                "hint"            "[6]  BASELINE MANAGEMENT" \
                "hint"            "[7]  JOURNAL & ROLLBACK" \
                "hint"            "[8]  CRON & SCHEDULED JOBS" \
                "hint"            "[b]  BACK"
        fi

        clear 2>/dev/null || echo ""
        echo -e ""
        echo -e "  ${BOLD}IGOR — RECOVERY & BACKUP${NC}"
        echo -e "  ${CYAN}$(printf '═%.0s' {1..55})${NC}"
        printf "  Snapshot: ${CYAN}%-18s${NC}  Full: ${CYAN}%-18s${NC}  Journal: ${CYAN}%d${NC}\n" \
            "${last_snapshot:-(none)}" "${last_full_backup:-(none)}" "$journal_count"
        echo -e "  ${CYAN}$(printf '─%.0s' {1..55})${NC}"
        echo ""
        echo -e "  ${BOLD}1.${NC} TAKE SNAPSHOT        Capture full environment right now"
        echo -e "  ${BOLD}2.${NC} FULL BACKUP          Snapshot + all module hooks + archive"
        echo -e "  ${BOLD}3.${NC} SCHEDULE BACKUPS     Configure automatic backup schedule"
        echo -e "  ${BOLD}4.${NC} BROWSE SNAPSHOTS     View, diff, and restore from past snapshots"
        echo -e "  ${BOLD}5.${NC} LIVE HEALTH SUMMARY  Current system state at a glance"
        echo -e "  ${BOLD}6.${NC} BASELINE MANAGEMENT  Set / view drift from known-good state"
        echo -e "  ${BOLD}7.${NC} JOURNAL & ROLLBACK   Undo recent Igor-managed changes"
        echo -e "  ${BOLD}8.${NC} CRON & SCHEDULED JOBS  Discover, install, and manage cron jobs"

        # Module-provided extra actions (nextcloud_docker: a=supervised install, r=risk register)
        local _ncd_loaded=false
        [ -n "${_IGOR_LOADED_MODULES[nextcloud_docker]:-}" ] && _ncd_loaded=true
        if $_ncd_loaded; then
            echo ""
            echo -e "  ${BOLD}a.${NC} SUPERVISED NEXTCLOUD APP INSTALL   (install with 90s observation)"
            echo -e "  ${BOLD}r.${NC} NEXTCLOUD APP RISK REGISTER         (review app install history)"
        fi
        echo ""

        # Build fzf pick args — core items always present
        local _fzf_args=(
            "1:TAKE SNAPSHOT:Capture full environment right now"
            "2:FULL BACKUP:Snapshot + all module hooks + archive"
            "3:SCHEDULE BACKUPS:Configure automatic backup schedule"
            "4:BROWSE SNAPSHOTS:View, diff, and restore from past snapshots"
            "5:LIVE HEALTH SUMMARY:Current system state at a glance"
            "6:BASELINE MANAGEMENT:Set / view drift from known-good state"
            "7:JOURNAL & ROLLBACK:Undo recent Igor-managed changes"
            "8:CRON & SCHEDULED JOBS:Discover, install, and manage Igor cron jobs"
        )
        $_ncd_loaded && _fzf_args+=(
            "a:SUPERVISED NC APP INSTALL:Install a Nextcloud app safely with journaling"
            "r:NC APP RISK REGISTER:Review Nextcloud app install history and risk"
        )
        _fzf_args+=("b:BACK:Return to main menu")

        local _choice
        _choice=$(igor_fzf_pick "Recovery & Backup" "${_fzf_args[@]}")
        case $? in 1) return ;; 2)
        echo ""
        echo -e "  ${CYAN}b.${NC} Back to main menu"
        read -rp "  Choice: " _choice ;; esac
        [ "$_choice" = "_" ] && continue
        case "$_choice" in
            1)
                read -rp "  Reason for snapshot [Enter for 'manual']: " _reason
                config_backup_take "${_reason:-manual}"
                pause
                ;;
            2)
                full_backup_take
                pause
                ;;
            3) _mod_recovery_schedule_ui ;;
            4) _mod_recovery_browser ;;
            5) _mod_recovery_health_summary ;;
            6) _mod_recovery_baseline_ui ;;
            7) _mod_recovery_journal_ui ;;
            8) menu_cron_setup ;;
            a|A)
                if $_ncd_loaded && declare -f supervised_app_install &>/dev/null; then
                    read -rp "  App name to install: " _app
                    [ -n "$_app" ] && supervised_app_install "$_app"
                    pause
                else
                    warn "Supervised install requires nextcloud_docker module"
                fi
                ;;
            r|R)
                if $_ncd_loaded && declare -f app_risk_register_list &>/dev/null; then
                    app_risk_register_list
                    echo ""
                    read -rp "  Enter app name to view details (or Enter to go back): " _app
                    [ -n "$_app" ] && { app_risk_register_get "$_app"; echo ""; pause; }
                else
                    warn "App risk register requires nextcloud_docker module"
                fi
                ;;
            b|B|q|Q) return 0 ;;
            *) warn "Invalid choice." ;;
        esac
    done
}

# ── _mod_recovery_journal_ui ──────────────────────────────────────────────────
_mod_recovery_journal_ui() {
    local CYAN='\033[0;36m' BOLD='\033[1m' YEL='\033[1;33m' NC='\033[0m'

    while true; do
        echo ""
        echo -e "  ${BOLD}JOURNAL & ROLLBACK${NC}"
        echo -e "  ${CYAN}$(printf '─%.0s' {1..40})${NC}"
        echo ""
        local _jchoice
        _jchoice=$(igor_fzf_pick "Recovery — Journal & Rollback" \
            "1:LAST 20 ENTRIES:Show last 20 journal entries" \
            "2:LAST 50 ENTRIES:Show last 50 journal entries" \
            "3:IGOR ACTIONS:Show only AI-executed actions" \
            "4:RECENT FAILURES:Show FAIL status entries from last 24h" \
            "5:ROLLBACK BY TIME:Undo changes since a specific timestamp" \
            "6:ROLLBACK LAST HOUR:Undo changes from the last 60 minutes" \
            "7:ROLLBACK TODAY:Undo changes since midnight today" \
            "b:BACK:Return to recovery menu")
        case $? in 1) return 0 ;; 2)
        echo -e "  ${CYAN}1.${NC} Show last 20 entries"
        echo -e "  ${CYAN}2.${NC} Show last 50 entries"
        echo -e "  ${CYAN}3.${NC} Show only Igor (AI) actions"
        echo -e "  ${CYAN}4.${NC} Show only recent failures (FAIL status)"
        echo -e "  ${CYAN}5.${NC} Rollback — undo changes since a time"
        echo -e "  ${CYAN}6.${NC} Rollback — undo last hour"
        echo -e "  ${CYAN}7.${NC} Rollback — undo today"
        echo -e "  ${CYAN}b.${NC} Back"
        echo ""
        read -rp "  Choice: " _jchoice ;; esac
        [ "$_jchoice" = "_" ] && continue

        case "$_jchoice" in
            1) journal_tail 20; pause ;;
            2) journal_tail 50; pause ;;
            3)
                echo ""
                echo -e "  ${CYAN}Igor (AI) actions:${NC}"
                journal_query --actor "igor" | while IFS='|' read -r ts actor action tier cmd status detail; do
                    local dt; dt=$(date -d "@${ts}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
                    printf "  %-19s  %-11s  %-10s  %-7s  %s\n" \
                        "$dt" "$action" "$tier" "$status" "${cmd:0:55}"
                done
                pause
                ;;
            4)
                echo ""
                echo -e "  ${CYAN}Recent failures:${NC}"
                local since_24h=$(( $(date +%s) - 86400 ))
                journal_query --since "$since_24h" | while IFS='|' read -r ts actor action tier cmd status detail; do
                    [ "$status" = "FAIL" ] || continue
                    local dt; dt=$(date -d "@${ts}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
                    printf "  %-19s  %-14s  %-11s  %s\n" "$dt" "$actor" "$action" "${cmd:0:55}"
                done
                pause
                ;;
            5) journal_rollback; pause ;;
            6)
                local since_1h=$(( $(date +%s) - 3600 ))
                journal_rollback "$since_1h"
                pause
                ;;
            7)
                # Midnight today
                local midnight; midnight=$(date -d "today 00:00:00" +%s 2>/dev/null || \
                    date +%s | awk '{print $1 - ($1 % 86400)}')
                journal_rollback "$midnight"
                pause
                ;;
            b|B) return 0 ;;
            *) warn "Invalid choice." ;;
        esac
    done
}

# ── _mod_recovery_browser ─────────────────────────────────────────────────────
# Unified restore point browser: snapshots + full backups, sorted newest-first.
# Implements the staged restore flow per spec:
#   list → select → contents summary → scope → diff → confirm → apply → health check
_mod_recovery_browser() {
    local CYAN='\033[0;36m' BOLD='\033[1m' YEL='\033[1;33m' GRN='\033[0;32m' NC='\033[0m'
    local _bdir; _bdir=$(declare -f _cb_backup_dir &>/dev/null && _cb_backup_dir || \
        echo "${IGOR_BACKUPS_DIR:-${IGOR_DIR}/data/backups}")

    echo ""
    echo -e "  ${BOLD}BROWSE SNAPSHOTS — Restore points${NC}"
    echo -e "  ${CYAN}$(printf '─%.0s' {1..65})${NC}"

    # Build merged list: type|epoch|path
    declare -a _browser_items=()

    while IFS= read -r f; do
        local epoch; epoch=$(basename "$f" | grep -oE '[0-9]+' | head -1)
        _browser_items+=("snapshot|${epoch}|${f}")
    done < <(ls -t "${_bdir}"/config_*.tar.gz 2>/dev/null)

    while IFS= read -r d; do
        [ -d "$d" ] || continue
        local epoch; epoch=$(basename "$d" | grep -oE '[0-9]+' | head -1)
        _browser_items+=("full|${epoch}|${d}")
    done < <(ls -dt "${_bdir}"/full_* 2>/dev/null)

    # Sort by epoch descending
    IFS=$'\n' _browser_items=($(for item in "${_browser_items[@]}"; do
        local ep; ep=$(echo "$item" | cut -d'|' -f2)
        printf '%s %s\n' "$ep" "$item"
    done | sort -rn | awk '{$1=""; print substr($0,2)}'))
    unset IFS

    if [ ${#_browser_items[@]} -eq 0 ]; then
        echo ""
        echo "  (no restore points found — take a snapshot first)"
        echo ""
        pause
        return 0
    fi

    local filter="all"
    while true; do
        echo ""
        printf "  ${BOLD}%-4s  %-19s  %-10s  %-8s  %-5s  %s${NC}\n" \
            "#" "DATE" "TYPE" "SIZE" "HOST" "NAME"
        printf "  %s\n" "$(printf '─%.0s' {1..75})"

        local i=0
        for item in "${_browser_items[@]}"; do
            IFS='|' read -r btype epoch bpath <<< "$item"
            [ "$filter" != "all" ] && [ "$filter" != "$btype" ] && continue
            (( i++ ))
            local dt; dt=$(date -d "@${epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$epoch")
            local sz; sz=$(du -sh "$bpath" 2>/dev/null | cut -f1 || echo "?")
            local type_col="$CYAN"
            [ "$btype" = "full" ] && type_col="$GRN"
            # Extract host from manifest if available
            local host=""
            if [ -f "$bpath" ]; then
                host=$(tar -xzf "$bpath" manifest.txt --to-stdout 2>/dev/null | \
                    grep "^HOST:" | cut -d: -f2- | tr -d ' ' | head -1)
            elif [ -d "$bpath" ]; then
                host=$(grep "^HOST:" "${bpath}/FULL_BACKUP_MANIFEST.txt" 2>/dev/null | \
                    cut -d: -f2- | tr -d ' ' | head -1)
            fi
            printf "  %-4s  %-19s  ${type_col}%-10s${NC}  %-8s  %-5s  %s\n" \
                "$i" "$dt" "$btype" "$sz" "${host:--}" "$(basename "$bpath")"
        done

        echo ""
        echo -e "  [f] filter (all/snapshot/full)   [1-${i}] select   [b] back"
        echo ""
        read -rp "  Choice: " _bchoice

        case "$_bchoice" in
            f)
                read -rp "  Filter [all/snapshot/full]: " _ftype
                filter="${_ftype:-all}"
                ;;
            b|B) return 0 ;;
            [0-9]*)
                local sel=$(( _bchoice - 1 ))
                local visible_i=0 selected_item=""
                for item in "${_browser_items[@]}"; do
                    IFS='|' read -r btype epoch bpath <<< "$item"
                    [ "$filter" != "all" ] && [ "$filter" != "$btype" ] && continue
                    if [ "$visible_i" -eq "$sel" ]; then
                        selected_item="$item"; break
                    fi
                    (( visible_i++ ))
                done

                [ -z "$selected_item" ] && { warn "Invalid selection."; continue; }

                IFS='|' read -r btype epoch bpath <<< "$selected_item"
                echo ""
                echo -e "  ${BOLD}Selected:${NC} $(basename "$bpath")"
                echo -e "  ${BOLD}Date:${NC} $(date -d "@${epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)"
                echo -e "  ${BOLD}Size:${NC} $(du -sh "$bpath" 2>/dev/null | cut -f1)"
                echo ""

                # Show contents summary
                if [ "$btype" = "snapshot" ] && [ -f "$bpath" ]; then
                    echo -e "  ${CYAN}Manifest:${NC}"
                    tar -xzf "$bpath" manifest.txt --to-stdout 2>/dev/null | head -30
                elif [ "$btype" = "full" ] && [ -f "${bpath}/FULL_BACKUP_MANIFEST.txt" ]; then
                    echo -e "  ${CYAN}Manifest:${NC}"
                    head -30 "${bpath}/FULL_BACKUP_MANIFEST.txt"
                fi
                echo ""

                case "$btype" in
                    snapshot)
                        local _scope
                        _scope=$(igor_fzf_pick "Restore — Snapshot $(basename "$bpath")" \
                            "1:IGOR STATE:Variables and env files" \
                            "2:SYSTEM CONFIG:fstab, crontab, sshd, ufw" \
                            "3:DOCKER FILES:Compose and .env files" \
                            "4:ALL:Staged restore — per-step confirm" \
                            "b:BACK:Cancel")
                        case $? in 1|2)
                            echo "    1) Igor state"; echo "    2) System config"
                            echo "    3) Docker files"; echo "    4) All (staged)"
                            echo "    b) Back"
                            read -rp "  Choice: " _scope ;; esac
                        case "$_scope" in
                            1) config_backup_restore "$bpath" "igor-state" ;;
                            2) config_backup_restore "$bpath" "system" ;;
                            3) config_backup_restore "$bpath" "docker" ;;
                            4) config_backup_restore "$bpath" "all" ;;
                            b|B) ;;
                            *) warn "Invalid." ;;
                        esac
                        ;;
                    full)
                        local _fscope
                        _fscope=$(igor_fzf_pick "Restore — Full Backup $(basename "$bpath")" \
                            "1:CORE SNAPSHOT:Igor state / system / docker files" \
                            "2:MODULE RESTORE:Run module restore hooks (e.g. DB restore)" \
                            "3:FULL RESTORE:Core + all module hooks (staged)" \
                            "b:BACK:Cancel")
                        case $? in 1|2)
                            echo "    1) Core snapshot"; echo "    2) Module restore hooks"
                            echo "    3) Full restore (staged)"; echo "    b) Back"
                            read -rp "  Choice: " _fscope ;; esac
                        case "$_fscope" in
                            1|2|3) full_backup_restore "$bpath" ;;
                            b|B) ;;
                            *) warn "Invalid." ;;
                        esac
                        ;;
                esac
                pause
                ;;
            *) warn "Invalid choice." ;;
        esac
    done
}

# ── _mod_recovery_health_summary ─────────────────────────────────────────────
# Item 5: Live health summary — current system state at a glance.
_mod_recovery_health_summary() {
    local CYAN='\033[0;36m' BOLD='\033[1m' GRN='\033[0;32m' YEL='\033[1;33m' RED='\033[0;31m' NC='\033[0m'

    echo ""
    echo -e "  ${BOLD}LIVE HEALTH SUMMARY${NC}"
    echo -e "  ${CYAN}$(printf '─%.0s' {1..50})${NC}"
    echo ""

    # Healing subsystem health check
    if declare -f health_check_full &>/dev/null; then
        health_check_full "false" 2>/dev/null || true
        if declare -f calculate_health_score &>/dev/null; then
            local score; score=$(calculate_health_score 2>/dev/null || echo 0)
            if   [ "$score" -ge 80 ]; then echo -e "  Health score: ${GRN}${score}/100${NC}"
            elif [ "$score" -ge 50 ]; then echo -e "  Health score: ${YEL}${score}/100${NC}"
            else                           echo -e "  Health score: ${RED}${score}/100${NC}"; fi
        fi
    else
        warn "Healing subsystem not loaded — load via main menu first"
    fi

    echo ""
    echo -e "  ${CYAN}Disk usage:${NC}"
    df -h 2>/dev/null | grep -v tmpfs | while IFS= read -r line; do echo "    $line"; done

    echo ""
    echo -e "  ${CYAN}Memory:${NC}"
    free -h 2>/dev/null | while IFS= read -r line; do echo "    $line"; done

    echo ""
    echo -e "  ${CYAN}Docker containers:${NC}"
    docker ps --format "    {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null || \
        echo "    (docker not available)"

    echo ""
    echo -e "  ${CYAN}Open listening ports:${NC}"
    ss -tlnp 2>/dev/null | while IFS= read -r line; do echo "    $line"; done

    # Recent journal failures
    if [ -f "${JOURNAL_LOG:-}" ]; then
        local since_1h=$(( $(date +%s) - 3600 ))
        local fail_count; fail_count=$(
            awk -F'|' -v s="$since_1h" 'NF>=6 && $1+0>=s && $6=="FAIL"' \
                "${JOURNAL_LOG}" 2>/dev/null | wc -l || echo 0)
        if [ "$fail_count" -gt 0 ]; then
            echo ""
            echo -e "  ${YEL}Journal:${NC} ${fail_count} failed action(s) in the last hour — check item 7"
        fi
    fi

    echo ""
    pause
}

# ── _mod_recovery_baseline_ui ────────────────────────────────────────────────
# Item 6: Baseline management — set a known-good state, detect drift.
_mod_recovery_baseline_ui() {
    local CYAN='\033[0;36m' BOLD='\033[1m' YEL='\033[1;33m' GRN='\033[0;32m' NC='\033[0m'
    local _bdir; _bdir=$(declare -f _cb_backup_dir &>/dev/null && _cb_backup_dir || \
        echo "${IGOR_BACKUPS_DIR:-${IGOR_DIR}/data/backups}")
    local _baseline_link="${_bdir}/baseline"

    while true; do
        echo ""
        echo -e "  ${BOLD}BASELINE MANAGEMENT${NC}"
        echo -e "  ${CYAN}$(printf '─%.0s' {1..50})${NC}"

        if [ -L "$_baseline_link" ] && [ -e "$_baseline_link" ]; then
            local _bl_target; _bl_target=$(readlink -f "$_baseline_link" 2>/dev/null)
            local _bl_epoch; _bl_epoch=$(basename "$_bl_target" | grep -oE '[0-9]+' | head -1)
            local _bl_dt; _bl_dt=$(date -d "@${_bl_epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$_bl_epoch")
            echo -e "  Current baseline: ${GRN}${_bl_dt}${NC}  ($(basename "$_bl_target"))"
        else
            echo -e "  Current baseline: ${YEL}not set${NC}"
        fi
        echo ""

        local _bchoice
        _bchoice=$(igor_fzf_pick "Baseline Management" \
            "1:SET BASELINE:Mark a snapshot as the known-good baseline" \
            "2:DRIFT REPORT:Diff current state against baseline" \
            "3:CLEAR BASELINE:Remove the baseline marker" \
            "b:BACK:Return to recovery menu")
        case $? in 1|2)
            echo "    1) Set baseline"; echo "    2) Drift report"
            echo "    3) Clear baseline"; echo "    b) Back"
            read -rp "  Choice: " _bchoice ;; esac

        case "$_bchoice" in
            1)
                # Pick a snapshot to use as baseline
                config_backup_list
                [ ${#_BACKUP_LIST_ARCHIVES[@]} -eq 0 ] && { warn "No snapshots available."; continue; }
                read -rp "  Select snapshot number to set as baseline: " _sel
                local _src="${_BACKUP_LIST_ARCHIVES[$(( _sel - 1 ))]}"
                [ -z "$_src" ] || [ ! -f "$_src" ] && { warn "Invalid selection"; continue; }
                ln -sf "$_src" "$_baseline_link" 2>/dev/null && \
                    ok "Baseline set: $(basename "$_src")" || \
                    fail "Could not set baseline symlink"
                ;;
            2)
                if [ ! -L "$_baseline_link" ] || [ ! -e "$_baseline_link" ]; then
                    warn "No baseline set. Use option 1 first."
                    continue
                fi
                _mod_recovery_drift_report "$_baseline_link"
                pause
                ;;
            3)
                rm -f "$_baseline_link" 2>/dev/null && ok "Baseline cleared." || \
                    warn "Baseline symlink not found"
                ;;
            b|B) return 0 ;;
            *) warn "Invalid choice." ;;
        esac
    done
}

# ── _mod_recovery_drift_report BASELINE_ARCHIVE ───────────────────────────────
# Extracts baseline igor-snapshot.json and diffs it against current state.
_mod_recovery_drift_report() {
    local baseline_path="$1"
    local CYAN='\033[0;36m' YEL='\033[1;33m' GRN='\033[0;32m' BOLD='\033[1m' NC='\033[0m'
    local _bl; _bl=$(readlink -f "$baseline_path" 2>/dev/null || echo "$baseline_path")

    echo ""
    echo -e "  ${BOLD}DRIFT REPORT${NC}"
    echo -e "  Baseline: $(basename "$_bl")"
    echo -e "  ${CYAN}$(printf '─%.0s' {1..55})${NC}"
    echo ""

    local _workdir; _workdir=$(mktemp -d)
    trap 'rm -rf "$_workdir"' RETURN

    # Extract baseline snapshot JSON
    local _bl_json="${_workdir}/baseline-snapshot.json"
    if [ -f "$_bl" ]; then
        tar -xzf "$_bl" igor-snapshot.json -O 2>/dev/null > "$_bl_json" || true
    fi

    if [ ! -s "$_bl_json" ]; then
        warn "Baseline does not contain igor-snapshot.json (old format — re-take snapshot to enable drift)"
        return 0
    fi

    # Generate current snapshot JSON
    local _cur_json="${_workdir}/current-snapshot.json"
    _mod_cb_generate_json_to_file "$_cur_json" 2>/dev/null || \
        ( source "${IGOR_DIR}/core/recovery/config_backup.sh" 2>/dev/null
          _mod_cb_generate_json "$_workdir" "drift-check"
          mv "${_workdir}/igor-snapshot.json" "$_cur_json" 2>/dev/null ) || true

    if [ ! -s "$_cur_json" ]; then
        warn "Could not generate current snapshot for comparison"
        return 0
    fi

    python3 - "$_bl_json" "$_cur_json" <<'PYEOF' 2>/dev/null || \
        diff --color=always "$_bl_json" "$_cur_json" 2>/dev/null | head -80
import json, sys

def load(path):
    try:
        return json.load(open(path))
    except Exception as e:
        print(f"  ERROR loading {path}: {e}")
        return {}

baseline = load(sys.argv[1])
current  = load(sys.argv[2])

BOLD = '\033[1m'; CYAN = '\033[0;36m'; YEL = '\033[1;33m'
GRN = '\033[0;32m'; RED = '\033[0;31m'; NC = '\033[0m'

def check_list_drift(label, bl_list, cur_list):
    bl_set  = set(bl_list)
    cur_set = set(cur_list)
    added   = cur_set - bl_set
    removed = bl_set  - cur_set
    if added or removed:
        print(f"  {YEL}{label}:{NC}")
        for x in sorted(added):   print(f"    {GRN}+{NC} {x}")
        for x in sorted(removed): print(f"    {RED}-{NC} {x}")
    else:
        print(f"  {GRN}✔{NC} {label}: no drift")

check_list_drift("Docker networks",    baseline.get('docker',{}).get('networks',[]),
                                       current.get('docker',{}).get('networks',[]))
check_list_drift("Docker volumes",     baseline.get('docker',{}).get('volumes',[]),
                                       current.get('docker',{}).get('volumes',[]))
check_list_drift("Running containers", baseline.get('docker',{}).get('containers',[]),
                                       current.get('docker',{}).get('containers',[]))
check_list_drift("Enabled services",   baseline.get('system',{}).get('enabled_services',[]),
                                       current.get('system',{}).get('enabled_services',[]))
check_list_drift("Open ports",         baseline.get('system',{}).get('open_ports',[]),
                                       current.get('system',{}).get('open_ports',[]))

# Timezone / hostname drift
for key, label in [('timezone','Timezone'), ('hostname','Hostname')]:
    bl_val  = baseline.get('system',{}).get(key,'')
    cur_val = current.get('system',{}).get(key,'')
    if bl_val != cur_val:
        print(f"  {YEL}{label}:{NC} baseline={bl_val!r} → current={cur_val!r}")
    else:
        print(f"  {GRN}✔{NC} {label}: {cur_val!r}")
PYEOF

    echo ""
}

# ── _mod_recovery_schedule_ui ─────────────────────────────────────────────────
_mod_recovery_schedule_ui() {
    while true; do
        backup_schedule_show
        local _schoice
        _schoice=$(igor_fzf_pick "Recovery — Backup Schedule" \
            "1:CONFIGURE SCHEDULE:Set backup frequencies and retention" \
            "2:INSTALL CRONTAB:Install or update cron entries" \
            "3:REMOVE CRONTAB:Remove all backup cron entries" \
            "b:BACK:Return to recovery menu")
        case $? in 1) return 0 ;; 2)
        echo -e "  ${CYAN}1.${NC} Configure schedule"
        echo -e "  ${CYAN}2.${NC} Install/update crontab"
        echo -e "  ${CYAN}3.${NC} Remove crontab entries"
        echo -e "  ${CYAN}b.${NC} Back"
        echo ""
        read -rp "  Choice: " _schoice ;; esac
        [ "$_schoice" = "_" ] && continue
        case "$_schoice" in
            1) backup_schedule_config ;;
            2) backup_crontab_install; pause ;;
            3) backup_crontab_remove; pause ;;
            b|B) return 0 ;;
            *) warn "Invalid choice." ;;
        esac
    done
}

# ── _mod_recovery_exec_tier CMD TIER [CONFIRM_MSG] ────────────────────────────
# Tier-gated command execution for rollback and recovery steps.
# Used by journal_rollback() and config_backup_restore() internals.
# Returns 0 if executed, 1 if skipped/denied.
_mod_recovery_exec_tier() {
    local cmd="$1" tier="${2:-CHANGE}" msg="${3:-Execute this recovery step?}"
    local GRN='\033[0;32m' RED='\033[0;31m' NC='\033[0m'

    case "$tier" in
        READ|AUTO)
            # Auto-run
            ;;
        CHANGE|SAFE|CAUTION)
            confirm "$msg" || { echo "  Skipped."; return 1; }
            ;;
        DESTROY|DESTRUCTIVE)
            echo ""
            read -rp "  Type YES to confirm DESTROY-tier action: " _yes
            [ "$_yes" = "YES" ] || { echo "  Skipped."; return 1; }
            ;;
    esac

    local out; out=$(bash -c "$cmd" 2>&1)
    local rc=$?
    echo "$out" | head -10

    if [ $rc -eq 0 ]; then
        echo -e "  ${GRN}✔${NC} Done (exit 0)."
        declare -f journal_record &>/dev/null && \
            journal_record "menu:recovery" "fix_applied" "$tier" "$cmd" "OK" "recovery_step"
        return 0
    else
        echo -e "  ${RED}✘${NC} Failed (exit $rc)."
        declare -f journal_record &>/dev/null && \
            journal_record "menu:recovery" "fix_applied" "$tier" "$cmd" "FAIL" "rc:${rc}"
        return 1
    fi
}

# ── _mod_recovery_startup_check ───────────────────────────────────────────────
# Called once from igor.sh at startup (after heartbeat check, before main_menu).
# Budget: ≤ 3 seconds total.
# 1. Detect unsupervised app changes via occ app:list diff
# 2. Scan journal for recent FAIL entries → alert if any
_mod_recovery_startup_check() {
    # 1. App diff (skips if NC is down — has its own curl timeout)
    declare -f journal_detect_app_changes &>/dev/null && \
        journal_detect_app_changes 2>/dev/null || true

    # 2. Scan journal for FAIL entries in the last 24h
    local since_24h=$(( $(date +%s) - 86400 ))
    if [ -f "$JOURNAL_LOG" ]; then
        local fail_count; fail_count=$(
            awk -F'|' -v s="$since_24h" 'NF>=6 && $1+0>=s && $6=="FAIL"' \
                "${JOURNAL_LOG}" 2>/dev/null | wc -l || echo 0
        )
        if [ "$fail_count" -gt 0 ]; then
            declare -f alert_log &>/dev/null && \
                alert_log "WARN" "journal_failures" \
                    "${fail_count} failed action(s) in the last 24h — check journal (V → 1)" \
                    2>/dev/null || true
        fi
    fi
}
