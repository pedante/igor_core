#!/bin/bash
# ==============================================================================
#  IGOR — core/recovery/cron_setup.sh
#  Cron job discovery, status display, and management for all Igor tasks.
#
#  Discovers what was configured by reading:
#    • Live crontab (what's actually scheduled)
#    • secrets/mailcmd.env  (mailcmd + heartbeat setup)
#    • secrets/notifications.env (notification setup)
#    • config/variables/*.env (backup timing)
#
#  Public functions:
#    igor_cron_discover    — build _IGOR_CRON state array (idempotent)
#    igor_cron_status_show — print a status table to stdout
#    menu_cron_setup       — interactive management menu
# ==============================================================================

# ── State ─────────────────────────────────────────────────────────────────────
# Populated by igor_cron_discover; read by status_show and menu_cron_setup.
declare -A _IGOR_CRON 2>/dev/null || true

# ── igor_cron_discover ────────────────────────────────────────────────────────
# Reads crontab + env files and populates _IGOR_CRON[*] keys:
#
#   cron_backup_config  — "installed" | "missing"
#   cron_backup_full    — "installed" | "missing"
#   cron_heartbeat      — "installed" | "missing"
#   backup_time_config  — HH:MM
#   backup_time_full    — HH:MM on DOW
#   heartbeat_time      — HH:MM
#   mailcmd_configured  — "yes" | "no"
#   mailcmd_imap_host   — hostname or ""
#   mailcmd_smtp_host   — hostname or ""
#   mailcmd_gpg_email   — email or ""
#   notify_configured   — "yes" | "no"
#   notify_smtp_host    — hostname or ""
#   notify_to           — email or ""
#   cron_line_backup_config — raw crontab line or ""
#   cron_line_backup_full   — raw crontab line or ""
#   cron_line_heartbeat     — raw crontab line or ""
#   extra_igor_lines        — any other igor.sh cron lines (newline-separated)

igor_cron_discover() {
    local _root="${IGOR_DIR:-.}"
    local _tab; _tab=$(crontab -l 2>/dev/null || true)

    # ── Crontab entries ───────────────────────────────────────────────────────
    local _bc; _bc=$(printf '%s\n' "$_tab" | grep "igor.sh --backup config" | head -1)
    local _bf; _bf=$(printf '%s\n' "$_tab" | grep "igor.sh --backup full"   | head -1)
    local _hb; _hb=$(printf '%s\n' "$_tab" | grep "igor.sh --mailcmd heartbeat" | head -1)

    _IGOR_CRON[cron_backup_config]=$([ -n "$_bc" ] && echo "installed" || echo "missing")
    _IGOR_CRON[cron_backup_full]=$(  [ -n "$_bf" ] && echo "installed" || echo "missing")
    _IGOR_CRON[cron_heartbeat]=$(    [ -n "$_hb" ] && echo "installed" || echo "missing")
    _IGOR_CRON[cron_line_backup_config]="$_bc"
    _IGOR_CRON[cron_line_backup_full]="$_bf"
    _IGOR_CRON[cron_line_heartbeat]="$_hb"

    # Any other igor.sh lines not already captured
    _IGOR_CRON[extra_igor_lines]=$(printf '%s\n' "$_tab" \
        | grep "igor.sh" \
        | grep -v "igor.sh --backup" \
        | grep -v "igor.sh --mailcmd heartbeat" \
        || true)

    # ── Backup timing (from config + env) ────────────────────────────────────
    _IGOR_CRON[backup_time_config]="${BACKUP_CONFIG_TIME:-}"
    _IGOR_CRON[backup_time_full]="${BACKUP_FULL_TIME:-}"

    # If not in env, parse from live crontab line
    if [ -z "${_IGOR_CRON[backup_time_config]}" ] && [ -n "$_bc" ]; then
        local _bch _bcm
        _bcm=$(printf '%s' "$_bc" | awk '{print $1}')
        _bch=$(printf '%s' "$_bc"  | awk '{print $2}')
        _IGOR_CRON[backup_time_config]=$(printf '%02d:%02d' "${_bch:-3}" "${_bcm:-0}" 2>/dev/null || echo "03:00")
    fi
    _IGOR_CRON[backup_time_config]="${_IGOR_CRON[backup_time_config]:-03:00}"

    if [ -z "${_IGOR_CRON[backup_time_full]}" ] && [ -n "$_bf" ]; then
        local _bfh _bfm
        _bfm=$(printf '%s' "$_bf" | awk '{print $1}')
        _bfh=$(printf '%s' "$_bf"  | awk '{print $2}')
        _IGOR_CRON[backup_time_full]=$(printf '%02d:%02d' "${_bfh:-3}" "${_bfm:-30}" 2>/dev/null || echo "03:30")
    fi
    _IGOR_CRON[backup_time_full]="${_IGOR_CRON[backup_time_full]:-03:30}"

    # ── Heartbeat timing ──────────────────────────────────────────────────────
    _IGOR_CRON[heartbeat_time]="${MAILCMD_HEARTBEAT_TIME:-}"
    if [ -z "${_IGOR_CRON[heartbeat_time]}" ] && [ -n "$_hb" ]; then
        local _hbh _hbm
        _hbm=$(printf '%s' "$_hb" | awk '{print $1}')
        _hbh=$(printf '%s' "$_hb"  | awk '{print $2}')
        _IGOR_CRON[heartbeat_time]=$(printf '%02d:%02d' "${_hbh:-7}" "${_hbm:-0}" 2>/dev/null || echo "07:00")
    fi
    _IGOR_CRON[heartbeat_time]="${_IGOR_CRON[heartbeat_time]:-07:00}"

    # ── mailcmd.env discovery ─────────────────────────────────────────────────
    local _mc_env="${_root}/secrets/mailcmd.env"
    if [ -f "$_mc_env" ]; then
        local _imap; _imap=$(grep -m1 "^MAILCMD_IMAP_HOST=" "$_mc_env" 2>/dev/null | cut -d= -f2-)
        local _smtp; _smtp=$(grep -m1 "^MAILCMD_SMTP_HOST=" "$_mc_env" 2>/dev/null | cut -d= -f2-)
        local _gpg;  _gpg=$( grep -m1 "^MAILCMD_GPG_EMAIL=" "$_mc_env" 2>/dev/null | cut -d= -f2-)
        _IGOR_CRON[mailcmd_imap_host]="${_imap:-}"
        _IGOR_CRON[mailcmd_smtp_host]="${_smtp:-}"
        _IGOR_CRON[mailcmd_gpg_email]="${_gpg:-}"
        if [ -n "$_imap" ] && [ -n "$_smtp" ]; then
            _IGOR_CRON[mailcmd_configured]="yes"
        else
            _IGOR_CRON[mailcmd_configured]="partial"
        fi
    else
        _IGOR_CRON[mailcmd_configured]="no"
        _IGOR_CRON[mailcmd_imap_host]=""
        _IGOR_CRON[mailcmd_smtp_host]=""
        _IGOR_CRON[mailcmd_gpg_email]=""
    fi

    # ── notifications.env discovery ───────────────────────────────────────────
    local _not_env="${_root}/secrets/notifications.env"
    if [ -f "$_not_env" ]; then
        local _nsmtp; _nsmtp=$(grep -m1 "^SMTP_HOST="   "$_not_env" 2>/dev/null | cut -d= -f2-)
        local _nto;   _nto=$(  grep -m1 "^NOTIFY_TO="   "$_not_env" 2>/dev/null | cut -d= -f2-)
        _IGOR_CRON[notify_smtp_host]="${_nsmtp:-}"
        _IGOR_CRON[notify_to]="${_nto:-}"
        [ -n "$_nsmtp" ] && [ -n "$_nto" ] && \
            _IGOR_CRON[notify_configured]="yes" || \
            _IGOR_CRON[notify_configured]="partial"
    else
        _IGOR_CRON[notify_configured]="no"
        _IGOR_CRON[notify_smtp_host]=""
        _IGOR_CRON[notify_to]=""
    fi
}

# ── igor_cron_status_show ─────────────────────────────────────────────────────
# Print a formatted status table.  Calls igor_cron_discover if not yet run.
igor_cron_status_show() {
    [ -z "${_IGOR_CRON[cron_backup_config]:-}" ] && igor_cron_discover

    local GRN='\033[0;32m' YEL='\033[1;33m' RED='\033[0;31m'
    local CYAN='\033[0;36m' DIM='\033[2m' BOLD='\033[1m' NC='\033[0m'

    local _tick="${GRN}✔${NC}" _cross="${RED}✘${NC}" _warn="${YEL}⚠${NC}"

    _cron_status_icon() {
        [ "${1:-missing}" = "installed" ] && echo "$_tick" || echo "$_cross"
    }
    _cfg_icon() {
        case "${1:-no}" in
            yes)     echo "$_tick" ;;
            partial) echo "$_warn" ;;
            *)       echo "$_cross" ;;
        esac
    }

    echo ""
    echo -e "  ${BOLD}Igor Cron & Service Discovery${NC}"
    echo -e "  ${CYAN}$(printf '─%.0s' {1..52})${NC}"

    echo ""
    echo -e "  ${BOLD}── Scheduled Jobs (crontab) ──────────────────────${NC}"
    printf "  $(_cron_status_icon "${_IGOR_CRON[cron_backup_config]}") %-32s %s\n" \
        "Config backup" "${_IGOR_CRON[backup_time_config]} daily"
    [ -n "${_IGOR_CRON[cron_line_backup_config]}" ] && \
        echo -e "  ${DIM}    ${_IGOR_CRON[cron_line_backup_config]}${NC}"

    printf "  $(_cron_status_icon "${_IGOR_CRON[cron_backup_full]}") %-32s %s\n" \
        "Full backup" "${_IGOR_CRON[backup_time_full]} weekly"
    [ -n "${_IGOR_CRON[cron_line_backup_full]}" ] && \
        echo -e "  ${DIM}    ${_IGOR_CRON[cron_line_backup_full]}${NC}"

    printf "  $(_cron_status_icon "${_IGOR_CRON[cron_heartbeat]}") %-32s %s\n" \
        "Heartbeat email" "${_IGOR_CRON[heartbeat_time]} daily"
    [ -n "${_IGOR_CRON[cron_line_heartbeat]}" ] && \
        echo -e "  ${DIM}    ${_IGOR_CRON[cron_line_heartbeat]}${NC}"

    if [ -n "${_IGOR_CRON[extra_igor_lines]}" ]; then
        echo ""
        echo -e "  ${DIM}── Other Igor cron entries found ──────────────────${NC}"
        while IFS= read -r _l; do
            [ -n "$_l" ] && echo -e "  ${DIM}  ${_l}${NC}"
        done <<< "${_IGOR_CRON[extra_igor_lines]}"
    fi

    echo ""
    echo -e "  ${BOLD}── Configured Services ───────────────────────────${NC}"
    printf "  $(_cfg_icon "${_IGOR_CRON[mailcmd_configured]}") %-22s" "Command mail (mailcmd)"
    if [ "${_IGOR_CRON[mailcmd_configured]}" != "no" ]; then
        printf " IMAP: %s  SMTP: %s\n" \
            "${_IGOR_CRON[mailcmd_imap_host]:-(not set)}" \
            "${_IGOR_CRON[mailcmd_smtp_host]:-(not set)}"
        [ -n "${_IGOR_CRON[mailcmd_gpg_email]}" ] && \
            printf "    ${DIM}%-24s GPG email: %s${NC}\n" "" "${_IGOR_CRON[mailcmd_gpg_email]}"
    else
        printf " (secrets/mailcmd.env not found)\n"
    fi

    printf "  $(_cfg_icon "${_IGOR_CRON[notify_configured]}") %-22s" "Notifications"
    if [ "${_IGOR_CRON[notify_configured]}" != "no" ]; then
        printf " SMTP: %s  → %s\n" \
            "${_IGOR_CRON[notify_smtp_host]:-(not set)}" \
            "${_IGOR_CRON[notify_to]:-(not set)}"
    else
        printf " (secrets/notifications.env not found)\n"
    fi

    echo ""
}

# ── _igor_cron_install_backup ────────────────────────────────────────────────
_igor_cron_install_backup() {
    # Delegate to the existing backup scheduler
    if declare -f backup_crontab_install &>/dev/null; then
        backup_crontab_install
    else
        # Lazy-load schedule.sh
        source "${IGOR_DIR}/core/recovery/schedule.sh" 2>/dev/null || true
        backup_crontab_install
    fi
    # Refresh discovery state
    igor_cron_discover
}

# ── _igor_cron_install_heartbeat ─────────────────────────────────────────────
_igor_cron_install_heartbeat() {
    # Lazy-load mailcmd service
    if ! declare -f _mailcmd_heartbeat_crontab_install &>/dev/null; then
        source "${IGOR_DIR}/core/mailcmd/service.sh" 2>/dev/null || true
    fi
    if declare -f _mailcmd_heartbeat_crontab_install &>/dev/null; then
        _mailcmd_heartbeat_crontab_install
    else
        warn "mailcmd service not available — check core/mailcmd/service.sh"
    fi
    igor_cron_discover
}

# ── _igor_cron_remove ─────────────────────────────────────────────────────────
# Remove a specific Igor cron entry by grep pattern.
_igor_cron_remove() {
    local _label="$1" _pattern="$2"
    if ! crontab -l 2>/dev/null | grep -q "$_pattern"; then
        info "No crontab entry found for: ${_label}"
        pause; return
    fi
    confirm "Remove crontab entry for ${_label}?" || return
    ( crontab -l 2>/dev/null | grep -v "$_pattern" ) | crontab - 2>/dev/null
    ok "Removed: ${_label}"
    igor_cron_discover
    pause
}

# ── menu_cron_setup ───────────────────────────────────────────────────────────
menu_cron_setup() {
    # Ensure schedule.sh is loaded for backup_schedule_config
    declare -f backup_crontab_install &>/dev/null || \
        source "${IGOR_DIR}/core/recovery/schedule.sh" 2>/dev/null || true

    while true; do
        igor_cron_discover
        clear 2>/dev/null || true
        igor_cron_status_show

        local _bc="${_IGOR_CRON[cron_backup_config]}"
        local _bf="${_IGOR_CRON[cron_backup_full]}"
        local _hb="${_IGOR_CRON[cron_heartbeat]}"

        # Dynamic labels based on current state
        local _lbl_bc _lbl_bf _lbl_hb
        [ "$_bc" = "installed" ] && _lbl_bc="REINSTALL CONFIG BACKUP" || _lbl_bc="INSTALL CONFIG BACKUP"
        [ "$_bf" = "installed" ] && _lbl_bf="REINSTALL FULL BACKUP"   || _lbl_bf="INSTALL FULL BACKUP"
        [ "$_hb" = "installed" ] && _lbl_hb="REINSTALL HEARTBEAT"     || _lbl_hb="INSTALL HEARTBEAT"

        local _choice
        _choice=$(igor_fzf_pick "Cron & Service Setup" \
            "1:${_lbl_bc}:Daily config snapshot cron entry" \
            "2:${_lbl_bf}:Weekly full backup cron entry" \
            "3:${_lbl_hb}:Daily heartbeat email cron entry" \
            "4:INSTALL ALL:Install all missing cron entries at once" \
            "_:  REMOVE  :" \
            "5:REMOVE CONFIG BACKUP:Remove config backup cron entry" \
            "6:REMOVE FULL BACKUP:Remove full backup cron entry" \
            "7:REMOVE HEARTBEAT:Remove heartbeat cron entry" \
            "_:  CONFIGURE  :" \
            "8:CONFIGURE BACKUP SCHEDULE:Set backup times and retention" \
            "9:SHOW RAW CRONTAB:Print Igor's crontab entries raw" \
            "b:BACK:Return to recovery menu")
        case $? in 1) return ;; 2)
        echo ""
        echo -e "  ${CYAN:-}1.${NC:-} ${_lbl_bc}"
        echo -e "  ${CYAN:-}2.${NC:-} ${_lbl_bf}"
        echo -e "  ${CYAN:-}3.${NC:-} ${_lbl_hb}"
        echo -e "  ${CYAN:-}4.${NC:-} INSTALL ALL"
        echo -e "  ${CYAN:-}5.${NC:-} REMOVE CONFIG BACKUP"
        echo -e "  ${CYAN:-}6.${NC:-} REMOVE FULL BACKUP"
        echo -e "  ${CYAN:-}7.${NC:-} REMOVE HEARTBEAT"
        echo -e "  ${CYAN:-}8.${NC:-} CONFIGURE BACKUP SCHEDULE"
        echo -e "  ${CYAN:-}9.${NC:-} SHOW RAW CRONTAB"
        echo -e "  ${CYAN:-}b.${NC:-} Back"
        echo ""
        read -rp "  Choice: " _choice ;; esac
        [ "$_choice" = "_" ] && continue
        case "$_choice" in
            1) _igor_cron_install_backup;    pause ;;
            2) _igor_cron_install_backup;    pause ;;
            3) _igor_cron_install_heartbeat; pause ;;
            4)
                _igor_cron_install_backup
                _igor_cron_install_heartbeat
                ok "All cron entries installed."
                pause
                ;;
            5) _igor_cron_remove "config backup"   "igor.sh --backup config" ;;
            6) _igor_cron_remove "full backup"     "igor.sh --backup full" ;;
            7) _igor_cron_remove "heartbeat"       "igor.sh --mailcmd heartbeat" ;;
            8)
                declare -f backup_schedule_config &>/dev/null && backup_schedule_config || \
                    warn "backup_schedule_config not available"
                ;;
            9)
                echo ""
                echo -e "  ${BOLD:-}Igor crontab entries:${NC:-}"
                crontab -l 2>/dev/null | grep "igor.sh" | while IFS= read -r _l; do
                    echo "  $_l"
                done
                echo ""
                pause
                ;;
            b|B|q|Q) return ;;
            *) warn "Invalid choice." ;;
        esac
    done
}
