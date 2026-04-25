#!/bin/bash
# ==============================================================================
#  IGOR — healing/alerts.sh
#  Alert logging and banner system.
#
#  Provides:
#    alert_log()            append a structured alert to pending.log
#    alert_banner_write()   write formatted banner text into pending.log
#    alert_banner_clear()   remove pending.log (called after alerts viewed)
#    alert_nextcloud()      send notification via occ notification:generate
#
#  Alert file: ~/.config/igor/alerts/pending.log
#  Format: plain text, human-readable, one entry per line.
# ==============================================================================

_ALERTS_DIR="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/data/alerts"
_ALERTS_PENDING="${_ALERTS_DIR}/pending.log"

# ── Log a single alert entry ──────────────────────────────────────────────────
# $1 = severity  (OK | WARN | FAIL | CRITICAL)
# $2 = code      (short identifier, e.g. "app_down")
# $3 = message   (human-readable description)
alert_log() {
    local severity="$1" code="$2" message="$3"
    [ -z "$severity" ] || [ -z "$message" ] && return 1
    mkdir -p "$_ALERTS_DIR"

    # Deduplication: skip if the same code+message was already written to pending.log
    # this session. Prevents triple-print when health_check_full is called multiple times.
    if [ -f "$_ALERTS_PENDING" ] && \
       grep -qF "${code:-unknown} | ${message}" "$_ALERTS_PENDING" 2>/dev/null; then
        return 0
    fi

    printf '[%s] [%s] %s | %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$severity" \
        "${code:-unknown}" \
        "$message" \
        >> "$_ALERTS_PENDING"

    # ── Email notification hook ────────────────────────────────────────────────
    # Fires on CRITICAL or FAIL severity; maps to the health_critical event toggle.
    if [[ "$severity" == "CRITICAL" || "$severity" == "FAIL" ]]; then
        declare -f notify_event &>/dev/null && \
            notify_event "health_critical" \
                "[${severity}] ${code}: ${message}" \
                "Health Alert: ${code}" \
            2>/dev/null || true
        # ── Module alert hooks (in-process; fn receives severity code message) ──
        local _fn
        for _fn in $(declare -f igor_get_hooks &>/dev/null && \
                     igor_get_hooks "alert_hook" 2>/dev/null || true); do
            declare -f "$_fn" &>/dev/null && \
                "$_fn" "$severity" "${code:-unknown}" "$message" 2>/dev/null || true
        done
    fi
}

# ── Write a formatted alert banner block ─────────────────────────────────────
# $@ = array of "[SEVERITY] message" strings
# Appends a banner header + all issues to pending.log.
alert_banner_write() {
    mkdir -p "$_ALERTS_DIR"
    {
        echo "=== IGOR HEALTH ALERT — $(date '+%Y-%m-%d %H:%M:%S') ==="
        for issue in "$@"; do
            echo "  $issue"
        done
        echo "==================================================================="
    } >> "$_ALERTS_PENDING"
}

# ── Clear pending alerts ──────────────────────────────────────────────────────
# Called after the user has viewed alerts.
alert_banner_clear() {
    rm -f "$_ALERTS_PENDING"
}

# ── In-app notification hook dispatch ─────────────────────────────────────────
# Modules register alert hooks via: igor_register_hook "alert_hook" "fn_name"
# Each fn receives (severity code message). Called by alert_log() on CRITICAL/FAIL.
# (Moved from core: alert_nextcloud is now in modules/nextcloud_docker/module.sh)

# ── Display pending alerts banner ─────────────────────────────────────────────
# Called from igor.sh main_menu() before showing the menu.
# Returns 0 if alerts were displayed, 1 if no alerts pending.
alert_show_pending() {
    [ ! -f "$_ALERTS_PENDING" ] && return 1
    [ ! -s "$_ALERTS_PENDING" ] && { rm -f "$_ALERTS_PENDING"; return 1; }

    # Discard alerts older than 4 hours — stale alerts from a previous session
    # where containers were temporarily down should not alarm on next startup.
    local _age_secs _mtime _now
    _now=$(date +%s 2>/dev/null)
    _mtime=$(stat -c %Y "$_ALERTS_PENDING" 2>/dev/null || stat -f %m "$_ALERTS_PENDING" 2>/dev/null)
    if [ -n "$_mtime" ] && [ -n "$_now" ]; then
        _age_secs=$(( _now - _mtime ))
        if [ "$_age_secs" -gt 14400 ]; then
            rm -f "$_ALERTS_PENDING"
            return 1
        fi
    fi

    echo ""
    echo -e "  ${RED}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${RED}${BOLD}║  ⚠  IGOR HEALTH ALERTS — ACTION MAY BE REQUIRED         ║${NC}"
    echo -e "  ${RED}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    while IFS= read -r line; do
        # Skip legacy banner lines (=== IGOR HEALTH ALERT === blocks)
        [[ "$line" == "==="* ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        echo -e "  ${YEL}${line}${NC}"
    done < "$_ALERTS_PENDING"
    echo ""
    echo -e "  ${CYAN}Run a full health check (Menu 9 → INFO) to review and clear alerts.${NC}"
    echo ""
    return 0
}
