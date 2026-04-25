#!/bin/bash
# IGOR — recovery/schedule.sh
# Backup scheduling via host crontab.
# Cron is the right mechanism here — the runtime worker handles IPC between
# the main session and --extra TUI, not tasks that must run when igor.sh is offline.
#
# Crontab entries managed by this file:
#   0 3 * * *   bash /path/igor.sh --backup config >> backup.log 2>&1
#   30 3 * * 0  bash /path/igor.sh --backup full   >> backup.log 2>&1
#
# Public functions:
#   backup_schedule_show              — current schedule + retention
#   backup_schedule_config            — interactive configure
#   backup_crontab_install            — write crontab entries (idempotent)
#   backup_crontab_remove             — remove only Igor crontab entries
#   backup_run_scheduled [config|full] — non-interactive cron entry point

BACKUP_LOG="${IGOR_DIR}/backup.log"

# ── backup_schedule_show ──────────────────────────────────────────────────────
backup_schedule_show() {
    local CYAN='\033[0;36m' BOLD='\033[1m' GRN='\033[0;32m' YEL='\033[1;33m' NC='\033[0m'

    echo ""
    echo -e "  ${BOLD}Backup Schedule${NC}"
    echo -e "  ${CYAN}$(printf '─%.0s' {1..40})${NC}"

    # Config backup
    local config_time="${BACKUP_CONFIG_TIME:-03:00}"
    local config_h="${config_time%%:*}"
    local config_m="${config_time##*:}"
    local config_entry="${config_m} ${config_h} * * *"
    echo -e "  Config backup:   daily at ${CYAN}${config_time}${NC}  (keep ${BACKUP_CONFIG_KEEP:-7} archives)"

    # Full backup
    local full_time="${BACKUP_FULL_TIME:-03:30}"
    local full_h="${full_time%%:*}"
    local full_m="${full_time##*:}"
    local full_dow="${BACKUP_FULL_DOW:-0}"
    local dow_names=("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat")
    echo -e "  Full backup:     weekly ${CYAN}${dow_names[$full_dow]:-Sun}${NC} at ${CYAN}${full_time}${NC}  (keep ${BACKUP_FULL_KEEP:-3} archives)"

    # Check if crontab is installed
    echo ""
    if crontab -l 2>/dev/null | grep -q "igor.sh --backup"; then
        echo -e "  Crontab status: ${GRN}✔ installed${NC}"
        crontab -l 2>/dev/null | grep "igor.sh --backup" | while IFS= read -r line; do
            echo "    $line"
        done
    else
        echo -e "  Crontab status: ${YEL}! not installed${NC}"
        echo "  Use 'Schedule' menu to install."
    fi

    # Last backup info from backup.log
    if [ -f "$BACKUP_LOG" ]; then
        echo ""
        echo -e "  ${BOLD}Recent backup log:${NC}"
        tail -5 "$BACKUP_LOG" 2>/dev/null | while IFS= read -r line; do
            echo "    $line"
        done
    fi
    echo ""
}

# ── _sched_set_cfg KEY VALUE ──────────────────────────────────────────────────
# Persist a backup schedule setting to the user config.env file.
# set_env() writes to db.env (credentials), which is wrong for schedule vars.
_sched_set_cfg() {
    local key="$1" val="$2"
    local cfg_file="${IGOR_DIR}/config.env"
    mkdir -p "$(dirname "$cfg_file")" 2>/dev/null || true
    touch "$cfg_file" 2>/dev/null || true
    if grep -q "^${key}=" "$cfg_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$cfg_file" 2>/dev/null || true
    else
        echo "${key}=${val}" >> "$cfg_file" 2>/dev/null || true
    fi
}

# ── backup_schedule_config ────────────────────────────────────────────────────
backup_schedule_config() {
    local CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'

    echo ""
    echo -e "  ${BOLD}Backup Schedule Configuration${NC}"
    echo ""

    # Config backup time
    local cur_config_time="${BACKUP_CONFIG_TIME:-03:00}"
    echo -e "  Current config backup time: ${CYAN}${cur_config_time}${NC}"
    local _new_config_time
    read -rp "  New config backup time [HH:MM, Enter to keep]: " _new_config_time
    if [ -n "$_new_config_time" ] && [[ "$_new_config_time" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
        _sched_set_cfg "BACKUP_CONFIG_TIME" "$_new_config_time"
        BACKUP_CONFIG_TIME="$_new_config_time"
    fi

    # Config keep count
    local cur_keep="${BACKUP_CONFIG_KEEP:-7}"
    local _new_keep
    read -rp "  Config backups to keep [current: ${cur_keep}]: " _new_keep
    if [ -n "$_new_keep" ] && [[ "$_new_keep" =~ ^[0-9]+$ ]]; then
        _sched_set_cfg "BACKUP_CONFIG_KEEP" "$_new_keep"
        BACKUP_CONFIG_KEEP="$_new_keep"
    fi

    # Full backup time
    local cur_full_time="${BACKUP_FULL_TIME:-03:30}"
    echo -e "  Current full backup time: ${CYAN}${cur_full_time}${NC} (weekly)"
    local _new_full_time
    read -rp "  New full backup time [HH:MM, Enter to keep]: " _new_full_time
    if [ -n "$_new_full_time" ] && [[ "$_new_full_time" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
        _sched_set_cfg "BACKUP_FULL_TIME" "$_new_full_time"
        BACKUP_FULL_TIME="$_new_full_time"
    fi

    # Day of week
    local cur_dow="${BACKUP_FULL_DOW:-0}"
    echo -e "  Current full backup day: ${CYAN}${cur_dow}${NC} (0=Sun, 1=Mon, ..., 6=Sat)"
    local _new_dow
    read -rp "  New day of week [0-6, Enter to keep]: " _new_dow
    if [ -n "$_new_dow" ] && [[ "$_new_dow" =~ ^[0-6]$ ]]; then
        _sched_set_cfg "BACKUP_FULL_DOW" "$_new_dow"
        BACKUP_FULL_DOW="$_new_dow"
    fi

    # Full keep count
    local cur_full_keep="${BACKUP_FULL_KEEP:-3}"
    local _new_full_keep
    read -rp "  Full backups to keep [current: ${cur_full_keep}]: " _new_full_keep
    if [ -n "$_new_full_keep" ] && [[ "$_new_full_keep" =~ ^[0-9]+$ ]]; then
        _sched_set_cfg "BACKUP_FULL_KEEP" "$_new_full_keep"
        BACKUP_FULL_KEEP="$_new_full_keep"
    fi

    echo ""
    backup_schedule_show

    if confirm "Install/update crontab with these settings?"; then
        backup_crontab_install
    fi
}

# ── backup_crontab_install ────────────────────────────────────────────────────
# Idempotent: removes existing Igor backup lines before re-adding.
backup_crontab_install() {
    local GRN='\033[0;32m' NC='\033[0m'

    local config_time="${BACKUP_CONFIG_TIME:-03:00}"
    local config_h="${config_time%%:*}"
    local config_m="${config_time##*:}"

    local full_time="${BACKUP_FULL_TIME:-03:30}"
    local full_h="${full_time%%:*}"
    local full_m="${full_time##*:}"
    local full_dow="${BACKUP_FULL_DOW:-0}"

    local igor_path="${IGOR_DIR}/igor.sh"
    local log_path="$BACKUP_LOG"

    local config_line="${config_m} ${config_h} * * *   bash \"${igor_path}\" --backup config >> \"${log_path}\" 2>&1"
    local full_line="${full_m} ${full_h} * * ${full_dow}   bash \"${igor_path}\" --backup full >> \"${log_path}\" 2>&1"

    # Remove existing Igor backup lines, append new ones
    ( crontab -l 2>/dev/null | grep -v "igor.sh --backup"; echo "$config_line"; echo "$full_line" ) \
        | crontab - 2>/dev/null

    echo -e "  ${GRN}✔${NC} Crontab updated:"
    echo "    $config_line"
    echo "    $full_line"

    declare -f journal_record &>/dev/null && \
        journal_record "menu:recovery" "service_restart" "CHANGE" \
            "crontab install backup schedule" "OK" \
            "config:${config_time} full:${full_time}/${full_dow}"
}

# ── backup_crontab_remove ─────────────────────────────────────────────────────
backup_crontab_remove() {
    local YEL='\033[1;33m' NC='\033[0m'

    if ! crontab -l 2>/dev/null | grep -q "igor.sh --backup"; then
        echo "  (no Igor backup crontab entries found)"
        return 0
    fi

    confirm "Remove Igor backup crontab entries?" || return 0
    ( crontab -l 2>/dev/null | grep -v "igor.sh --backup" ) | crontab - 2>/dev/null
    echo -e "  ${YEL}!${NC} Igor backup crontab entries removed."
}

# ── backup_run_scheduled [config|full] ────────────────────────────────────────
# Non-interactive entry point for cron-invoked backups.
# Does NOT use UI functions (no colours, no prompts).
# Output goes to BACKUP_LOG via cron redirection.
backup_run_scheduled() {
    local type="${1:-config}"
    local now; now=$(date "+%Y-%m-%d %H:%M:%S")

    echo "== [${now}] Igor backup: ${type} =="

    # Source required subsystems (we may not have them all loaded in cron context)
    local _base="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

    # Source lib/ (required for helpers and config)
    for _lib in ui.sh helpers.sh config.sh; do
        [ -f "${_base}/core/lib/${_lib}" ] && source "${_base}/core/lib/${_lib}" 2>/dev/null || true
    done

    # Source recovery subsystems
    for _mod in journal.sh config_backup.sh full_backup.sh; do
        [ -f "${_base}/core/recovery/${_mod}" ] && source "${_base}/core/recovery/${_mod}" 2>/dev/null || true
    done

    # Source notify subsystem (so notify_event is available in cron context)
    [ -f "${_base}/core/notify/core.sh" ] && source "${_base}/core/notify/core.sh" 2>/dev/null || true

    # Source healing/core for health_check_full (optional)
    [ -f "${_base}/core/healing/core.sh" ] && source "${_base}/core/healing/core.sh" 2>/dev/null || true

    # Init journal
    declare -f journal_init &>/dev/null && journal_init 2>/dev/null || true

    # Health check (warn only — don't block backup)
    local health_score=100
    if declare -f calculate_health_score &>/dev/null; then
        if declare -f health_check_full &>/dev/null; then
            health_check_full "false" 2>/dev/null || true
        fi
        health_score=$(calculate_health_score 2>/dev/null || echo 100)
        echo "[${now}] Health score: ${health_score}/100"
        if [ "$health_score" -lt 50 ]; then
            echo "[${now}] WARNING: System health is degraded (${health_score}/100). Backup flagged."
            declare -f alert_log &>/dev/null && \
                alert_log "WARN" "backup_degraded" \
                    "Scheduled ${type} backup taken from degraded system (score: ${health_score})" 2>/dev/null || true
        fi
    fi

    local rc=0
    case "$type" in
        config)
            declare -f config_backup_take &>/dev/null && \
                config_backup_take "scheduled-${type}" 2>&1 || rc=1
            ;;
        full)
            declare -f full_backup_take &>/dev/null && \
                full_backup_take 2>&1 || rc=1
            ;;
        *)
            echo "[${now}] ERROR: Unknown backup type '${type}'. Use config or full."
            exit 1
            ;;
    esac

    if [ $rc -ne 0 ]; then
        echo "[${now}] ERROR: ${type} backup FAILED."
        declare -f alert_log &>/dev/null && \
            alert_log "FAIL" "backup_failed" \
                "Scheduled ${type} backup failed — check ${BACKUP_LOG}" 2>/dev/null || true
        declare -f notify_event &>/dev/null && \
            notify_event "backup_fail" \
                "Scheduled ${type} backup FAILED — check ${BACKUP_LOG}" \
                "Scheduled Backup Failed" \
            2>/dev/null || true
        exit 1
    fi

    echo "[${now}] ${type} backup complete."
}
