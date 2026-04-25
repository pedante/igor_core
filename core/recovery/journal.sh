#!/bin/bash
# IGOR — recovery/journal.sh
# Change journal: append-only log of every Igor/diagnose/menu/web-ui action.
# Sourced unconditionally at igor.sh startup (after lib/) so journal_record()
# is always available to ai/safety.sh, diagnose/fixes.sh, and modules/*.sh.
#
# ZERO SIDE EFFECTS ON SOURCE — only function definitions and variable assignments.
# Do not call any function, run any command, or produce any output at source time.
#
# ACTOR values:
#   igor          — AI assistant (ai/safety.sh:ai_execute_tool) ran it
#   diag:SID      — diagnose/fixes.sh auto-fix, SID = _DIAG[session_id]
#   menu:MODULE   — a modules/*.sh menu function ran it
#   web-ui        — detected via occ app:list diff (unsupervised install)
#
# Record format (pipe-delimited, one line per entry):
#   EPOCH|ACTOR|ACTION|TIER|CMD|STATUS|DETAIL
# Fields:
#   EPOCH   Unix timestamp (date +%s)
#   ACTOR   see above
#   ACTION  snake_case verb (occ_exec|fix_applied|app_enable|app_disable|
#           app_install|backup_taken|service_restart|file_edit|db_backup|
#           stack_start|stack_stop)
#   TIER    READ|CHANGE|DESTROY|AUTO|SAFE|CAUTION|DESTRUCTIVE
#   CMD     literal command, max 300 chars, newlines→space, |→[PIPE]
#   STATUS  OK|FAIL|SKIPPED|PARTIAL
#   DETAIL  free text, max 200 chars, |→[PIPE]

# ── Storage paths (resolved via _igor_resolve_dir when available) ─────────────
_journal_resolve_dir() {
    if declare -f _igor_resolve_dir &>/dev/null; then
        _igor_resolve_dir recovery
    else
        echo "${IGOR_RECOVERY_DIR:-${IGOR_DIR}/data/recovery}"
    fi
}
JOURNAL_DIR="$(_journal_resolve_dir)"
JOURNAL_LOG="${JOURNAL_DIR}/journal.log"
JOURNAL_DB="${JOURNAL_DIR}/journal.db"
APP_SNAPSHOT="${JOURNAL_DIR}/app_list_snapshot.json"

# ── Internal: ensure storage exists ───────────────────────────────────────────
_journal_ensure_dir() {
    mkdir -p "$JOURNAL_DIR" 2>/dev/null || true
    [ -f "$JOURNAL_LOG" ] || touch "$JOURNAL_LOG" 2>/dev/null || true
}

# ── Internal: rotate log if over JOURNAL_MAX_SIZE ─────────────────────────────
_journal_rotate() {
    local max="${JOURNAL_MAX_SIZE:-5242880}"
    [ -f "$JOURNAL_LOG" ] || return 0
    local sz; sz=$(stat -c%s "$JOURNAL_LOG" 2>/dev/null || echo 0)
    if [ "$sz" -gt "$max" ]; then
        mv -f "${JOURNAL_LOG}.1" "${JOURNAL_LOG}.2" 2>/dev/null || true
        mv -f "$JOURNAL_LOG" "${JOURNAL_LOG}.1" 2>/dev/null || true
        touch "$JOURNAL_LOG" 2>/dev/null || true
    fi
}

# ── Internal: sanitise a field (strip/escape pipe chars and newlines) ──────────
_journal_sanitise() {
    local s="${1:-}" maxlen="${2:-300}"
    s="${s//$'\n'/ }"
    s="${s//$'\r'/ }"
    s="${s//|/[PIPE]}"
    printf '%s' "${s:0:$maxlen}"
}

# ── Internal: SQLite init (one-time schema creation) ──────────────────────────
_journal_db_init() {
    command -v sqlite3 &>/dev/null || return 0
    [ -f "$JOURNAL_DB" ] && return 0
    sqlite3 "$JOURNAL_DB" 2>/dev/null <<'SQL'
CREATE TABLE IF NOT EXISTS journal (
    id     INTEGER PRIMARY KEY AUTOINCREMENT,
    ts     INTEGER NOT NULL,
    actor  TEXT,
    action TEXT,
    tier   TEXT,
    cmd    TEXT,
    status TEXT,
    detail TEXT
);
CREATE INDEX IF NOT EXISTS idx_ts     ON journal(ts);
CREATE INDEX IF NOT EXISTS idx_actor  ON journal(actor);
CREATE INDEX IF NOT EXISTS idx_status ON journal(status);
SQL
}

# ── Internal: insert one row into SQLite (best-effort, never fatal) ───────────
_journal_db_insert() {
    command -v sqlite3 &>/dev/null || return 0
    [ -f "$JOURNAL_DB" ] || return 0
    local ts="$1" actor="$2" action="$3" tier="$4" cmd="$5" status="$6" detail="$7"
    sqlite3 "$JOURNAL_DB" 2>/dev/null \
        "INSERT INTO journal(ts,actor,action,tier,cmd,status,detail) \
         VALUES($ts,'$(echo "$actor" | sed "s/'/''/g")',\
                '$(echo "$action" | sed "s/'/''/g")',\
                '$(echo "$tier"   | sed "s/'/''/g")',\
                '$(echo "$cmd"    | sed "s/'/''/g")',\
                '$(echo "$status" | sed "s/'/''/g")',\
                '$(echo "$detail" | sed "s/'/''/g")');" || true
}

# ── Internal: flat-file query (grep + awk fallback) ───────────────────────────
# Outputs matching raw lines. Supports --since, --until, --actor, --tier, --limit.
_journal_flat_query() {
    local since=0 until=99999999999 actor="" tier="" limit=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since)  since="$2";  shift 2 ;;
            --until)  until="$2";  shift 2 ;;
            --actor)  actor="$2";  shift 2 ;;
            --tier)   tier="$2";   shift 2 ;;
            --limit)  limit="$2";  shift 2 ;;
            *) shift ;;
        esac
    done

    local files=("$JOURNAL_LOG")
    [ -f "${JOURNAL_LOG}.1" ] && files=("${JOURNAL_LOG}.1" "${JOURNAL_LOG}")

    {
        for f in "${files[@]}"; do
            [ -f "$f" ] && cat "$f"
        done
    } | awk -F'|' -v s="$since" -v u="$until" -v a="$actor" -v t="$tier" -v lim="$limit" '
        NF >= 6 && $1+0 >= s && $1+0 <= u \
        && (a == "" || $2 == a || index($2, a) == 1) \
        && (t == "" || $4 == t) {
            print
            if (lim > 0 && ++cnt >= lim) exit
        }'
}

# ── journal_record ACTOR ACTION TIER CMD STATUS [DETAIL] ──────────────────────
# The primary public function. Called from ai/safety.sh, diagnose/fixes.sh,
# modules/*.sh, and recovery/*.sh. Guarded with JOURNAL_ENABLED check.
journal_record() {
    [ "${JOURNAL_ENABLED:-true}" = "true" ] || return 0
    local actor="$1" action="$2" tier="$3" cmd="$4" status="$5" detail="${6:-}"

    _journal_ensure_dir
    _journal_rotate

    local ts; ts=$(date +%s)
    local safe_cmd;    safe_cmd=$(_journal_sanitise "$cmd" 300)
    local safe_detail; safe_detail=$(_journal_sanitise "$detail" 200)
    local safe_actor;  safe_actor=$(_journal_sanitise "$actor" 64)

    printf '%s|%s|%s|%s|%s|%s|%s\n' \
        "$ts" "$safe_actor" "$action" "$tier" "$safe_cmd" "$status" "$safe_detail" \
        >> "$JOURNAL_LOG" 2>/dev/null || true

    _journal_db_insert "$ts" "$safe_actor" "$action" "$tier" \
        "$safe_cmd" "$status" "$safe_detail"
}

# ── journal_query [--actor A] [--tier T] [--since EPOCH] [--until EPOCH] ──────
#                 [--limit N] [--action ACT]
# Outputs matching lines in display format.
# Uses SQLite when available, falls back to grep/awk over the flat file.
journal_query() {
    local since=0 until=99999999999 actor="" tier="" limit=0 action=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since)  since="$2";  shift 2 ;;
            --until)  until="$2";  shift 2 ;;
            --actor)  actor="$2";  shift 2 ;;
            --tier)   tier="$2";   shift 2 ;;
            --action) action="$2"; shift 2 ;;
            --limit)  limit="$2";  shift 2 ;;
            *) shift ;;
        esac
    done

    if command -v sqlite3 &>/dev/null && [ -f "$JOURNAL_DB" ]; then
        local where="WHERE ts >= $since AND ts <= $until"
        [ -n "$actor"  ] && where+=" AND actor LIKE '${actor}%'"
        [ -n "$tier"   ] && where+=" AND tier = '$tier'"
        [ -n "$action" ] && where+=" AND action = '$action'"
        local lim_clause=""
        [ "$limit" -gt 0 ] && lim_clause="LIMIT $limit"
        sqlite3 "$JOURNAL_DB" 2>/dev/null \
            "SELECT ts||'|'||actor||'|'||action||'|'||tier||'|'||cmd||'|'||status||'|'||detail \
             FROM journal $where ORDER BY ts ASC $lim_clause;" || true
    else
        _journal_flat_query --since "$since" --until "$until" \
            --actor "$actor" --tier "$tier" --limit "$limit"
    fi
}

# ── journal_tail [N=20] ───────────────────────────────────────────────────────
# Pretty-print the last N journal entries with colour coding by tier.
journal_tail() {
    local n="${1:-20}"
    local RED='\033[0;31m' YEL='\033[1;33m' GRN='\033[0;32m'
    local CYAN='\033[0;36m' MAG='\033[0;35m' BOLD='\033[1m' NC='\033[0m'

    # Gather last N lines from log(s)
    local files=()
    [ -f "${JOURNAL_LOG}.1" ] && files+=("${JOURNAL_LOG}.1")
    [ -f "$JOURNAL_LOG"     ] && files+=("$JOURNAL_LOG")
    [ ${#files[@]} -eq 0 ] && { echo "  (journal is empty)"; return 0; }

    echo ""
    printf "  ${BOLD}%-19s  %-18s  %-11s  %-10s  %-7s  %s${NC}\n" \
        "TIMESTAMP" "ACTOR" "ACTION" "TIER" "STATUS" "COMMAND"
    printf "  %s\n" "$(printf '─%.0s' {1..100})"

    cat "${files[@]}" | tail -n "$n" | while IFS='|' read -r ts actor action tier cmd status detail; do
        [ -z "$ts" ] && continue
        local dt; dt=$(date -d "@${ts}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
        local colour="$NC"
        case "$tier" in
            READ|AUTO)                   colour="$GRN" ;;
            CHANGE|SAFE)                 colour="$CYAN" ;;
            CAUTION|DESTRUCTIVE|DESTROY) colour="$YEL"  ;;
        esac
        [ "$status" = "FAIL" ] && colour="$RED"
        local actor_display="$actor"
        [ "$actor" = "igor" ] && actor_display="${MAG}igor (AI)${NC}"
        printf "  %-19s  ${colour}%-18s  %-11s  %-10s  %-7s${NC}  %s\n" \
            "$dt" "$actor_display" "$action" "$tier" "$status" "${cmd:0:55}"
    done
    echo ""
}

# ── journal_rollback_plan SINCE_EPOCH ─────────────────────────────────────────
# Populates global _JOURNAL_ROLLBACK_PLAN[] with CHANGE/DESTROY entries since
# SINCE_EPOCH. Each element: "TS|ACTOR|ACTION|TIER|CMD|STATUS|DETAIL"
# Returns 1 if no entries found.
journal_rollback_plan() {
    local since="${1:-0}"
    _JOURNAL_ROLLBACK_PLAN=()

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        IFS='|' read -r ts actor action tier cmd status detail <<< "$line"
        # Only include CHANGE/DESTROY/CAUTION/DESTRUCTIVE that succeeded
        case "$tier" in
            CHANGE|DESTROY|CAUTION|DESTRUCTIVE|SAFE) ;;
            *) continue ;;
        esac
        [ "$status" = "SKIPPED" ] && continue
        _JOURNAL_ROLLBACK_PLAN+=("$line")
    done < <(journal_query --since "$since")

    [ ${#_JOURNAL_ROLLBACK_PLAN[@]} -eq 0 ] && return 1
    return 0
}

# ── journal_rollback [SINCE_EPOCH] ────────────────────────────────────────────
# Interactive reverse-walk of the rollback plan.
# Each step goes through the tier gate via _mod_recovery_exec_tier (if available)
# or falls back to confirm()/read directly.
journal_rollback() {
    local since="${1:-}"
    local RED='\033[0;31m' YEL='\033[1;33m' GRN='\033[0;32m'
    local CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'

    if [ -z "$since" ]; then
        echo ""
        echo -e "  ${CYAN}Enter timestamp to roll back from (or press Enter for last 2h):${NC}"
        read -rp "  Epoch timestamp: " since
        if [ -z "$since" ]; then
            since=$(( $(date +%s) - 7200 ))
        fi
    fi

    if ! journal_rollback_plan "$since"; then
        echo -e "  ${GRN}✔${NC} No CHANGE/DESTROY actions found since $(date -d "@${since}" 2>/dev/null || echo "$since")."
        return 0
    fi

    local total=${#_JOURNAL_ROLLBACK_PLAN[@]}
    echo ""
    echo -e "  ${BOLD}Rollback plan — ${total} action(s) to undo (newest first):${NC}"
    echo ""

    # Display in reverse order
    local i
    for (( i=total-1; i>=0; i-- )); do
        IFS='|' read -r ts actor action tier cmd status detail <<< "${_JOURNAL_ROLLBACK_PLAN[$i]}"
        local dt; dt=$(date -d "@${ts}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
        printf "  %2d. ${CYAN}%-19s${NC}  actor=%-14s  tier=%-10s\n" \
            $((total-i)) "$dt" "$actor" "$tier"
        printf "      cmd: %s\n" "${cmd:0:80}"
        [ -n "$detail" ] && printf "      detail: %s\n" "${detail:0:80}"
        echo ""
    done

    echo -e "  ${YEL}NOTE:${NC} Rollback is best-effort. Commands with no known inverse"
    echo "        will be flagged — the recommended path is restoring the"
    echo "        pre-action config backup taken before each CAUTION/DESTRUCTIVE step."
    echo ""
    read -rp "  Proceed with rollback? [y/N]: " _confirm
    [[ "$_confirm" =~ ^[Yy]$ ]] || { echo "  Cancelled."; return 0; }

    # Walk in reverse, attempt undo
    for (( i=total-1; i>=0; i-- )); do
        IFS='|' read -r ts actor action tier cmd status detail <<< "${_JOURNAL_ROLLBACK_PLAN[$i]}"
        echo ""
        echo -e "  ${BOLD}Undoing:${NC} $cmd"
        echo -e "  ${CYAN}Tier:${NC} $tier  |  ${CYAN}Original actor:${NC} $actor"

        # Build undo command
        local undo_cmd undo_tier undo_possible=true

        case "$action" in
            stack_start)
                undo_cmd="docker compose down"
                undo_tier="DESTROY"
                ;;
            stack_stop)
                undo_cmd="docker compose up -d"
                undo_tier="CHANGE"
                ;;
            service_restart)
                # Restart is idempotent — re-running it is the undo
                undo_cmd="$cmd"
                undo_tier="CHANGE"
                ;;
            fix_applied|file_edit|backup_taken|db_backup)
                undo_possible=false
                ;;
            *)
                # Try module rollback hooks (app_enable, app_disable, app_install, occ_exec, etc.)
                local _rollback_result
                _rollback_result=""
                local _rh_fn
                for _rh_fn in $(declare -f igor_get_hooks &>/dev/null && \
                                igor_get_hooks "rollback_handler" 2>/dev/null || true); do
                    declare -f "$_rh_fn" &>/dev/null || continue
                    _rollback_result=$("$_rh_fn" "$action" "$cmd" 2>/dev/null) && break
                    _rollback_result=""
                done
                if [ -n "$_rollback_result" ]; then
                    undo_cmd="$_rollback_result"
                    undo_tier="CHANGE"
                else
                    undo_possible=false
                fi
                ;;
        esac

        if ! $undo_possible; then
            echo -e "  ${YEL}!${NC} No automatic undo for action '${action}'."
            echo -e "  ${YEL}!${NC} Previous state: ${detail}"
            echo ""
            echo -e "  ${CYAN}Tip:${NC} Restore from config backup taken before this action."
            echo -e "       Use: bash igor.sh → V → 2 (Restore Config Backup)"
            read -rp "  Press Enter to skip this step or 's' to stop rollback: " _skip
            [[ "$_skip" == "s" || "$_skip" == "S" ]] && break
            continue
        fi

        echo -e "  ${CYAN}Undo command:${NC} $undo_cmd"

        # Execute via tier gate
        if declare -f _mod_recovery_exec_tier &>/dev/null; then
            _mod_recovery_exec_tier "$undo_cmd" "$undo_tier" || true
        else
            # Fallback tier gate
            if [ "$undo_tier" = "DESTROY" ]; then
                read -rp "  Type YES to confirm DESTROY-tier undo: " _yes
                [ "$_yes" = "YES" ] || { echo "  Skipped."; continue; }
            else
                read -rp "  Execute? [y/N]: " _yn
                [[ "$_yn" =~ ^[Yy]$ ]] || { echo "  Skipped."; continue; }
            fi
            local undo_out; undo_out=$(bash -c "$undo_cmd" 2>&1)
            local undo_rc=$?
            echo "$undo_out" | head -10
            if [ $undo_rc -eq 0 ]; then
                echo -e "  ${GRN}✔${NC} Undo successful."
                journal_record "menu:recovery" "rollback" "$undo_tier" "$undo_cmd" "OK" "undid:${action}@${ts}"
            else
                echo -e "  ${RED}✘${NC} Undo failed (exit $undo_rc)."
                journal_record "menu:recovery" "rollback" "$undo_tier" "$undo_cmd" "FAIL" "undid:${action}@${ts} rc:${undo_rc}"
            fi
        fi
    done

    echo ""
    echo -e "  ${GRN}✔${NC} Rollback walk complete."
}

# ── journal_detect_app_changes ────────────────────────────────────────────────
# Diff current occ app:list against the stored snapshot.
# Journals any additions/removals as actor=web-ui.
# Skips entirely if Nextcloud is not responding (≤ 3s budget).
# Updates APP_SNAPSHOT on completion.
journal_detect_app_changes() {
    local GRN='\033[0;32m' YEL='\033[1;33m' NC='\033[0m'

    # Skip if NC is not running (quick 2s check)
    local http_code; http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 2 "http://localhost:${IGOR_WEB_PORT:-8080}/status.php" 2>/dev/null || echo "000")
    if [ "$http_code" != "200" ]; then
        return 0
    fi

    _journal_ensure_dir

    # Get current app list
    local current_json; current_json=$(docker compose exec -T -u www-data app \
        php occ app:list --output=json 2>/dev/null) || return 0
    [ -z "$current_json" ] && return 0

    # If no snapshot yet, create it and return
    if [ ! -f "$APP_SNAPSHOT" ]; then
        printf '%s' "$current_json" > "$APP_SNAPSHOT"
        return 0
    fi

    # Compare enabled apps
    local prev_enabled; prev_enabled=$(python3 -c "
import json, sys
try:
    d = json.load(open('$APP_SNAPSHOT'))
    print('\n'.join(sorted(d.get('enabled', {}).keys())))
except: pass
" 2>/dev/null)

    local curr_enabled; curr_enabled=$(python3 -c "
import json, sys
try:
    d = json.loads('''$(echo "$current_json" | sed "s/'/\\\\'/g")''')
    print('\n'.join(sorted(d.get('enabled', {}).keys())))
except: pass
" 2>/dev/null)

    local prev_disabled; prev_disabled=$(python3 -c "
import json, sys
try:
    d = json.load(open('$APP_SNAPSHOT'))
    print('\n'.join(sorted(d.get('disabled', []) if isinstance(d.get('disabled'), list) else d.get('disabled', {}).keys())))
except: pass
" 2>/dev/null)

    local curr_disabled; curr_disabled=$(python3 -c "
import json, sys
try:
    d = json.loads('''$(echo "$current_json" | sed "s/'/\\\\'/g")''')
    print('\n'.join(sorted(d.get('disabled', []) if isinstance(d.get('disabled'), list) else d.get('disabled', {}).keys())))
except: pass
" 2>/dev/null)

    local changed=false

    # Newly enabled apps (were not in enabled before)
    while IFS= read -r app; do
        [ -z "$app" ] && continue
        if ! grep -qx "$app" <<< "$prev_enabled" 2>/dev/null; then
            echo -e "  ${YEL}!${NC} Unsupervised app change detected: ${app} enabled (via web UI or external command)"
            journal_record "web-ui" "app_enable" "CHANGE" "$app" "OK" "detected via occ app:list diff"
            changed=true
            # Update app risk register if available
            declare -f app_risk_register_record &>/dev/null && \
                app_risk_register_record "$app" "OK" "unsupervised" 2>/dev/null || true
        fi
    done <<< "$curr_enabled"

    # Newly disabled apps
    while IFS= read -r app; do
        [ -z "$app" ] && continue
        if ! grep -qx "$app" <<< "$prev_disabled" 2>/dev/null && \
           grep -qx "$app" <<< "$prev_enabled" 2>/dev/null; then
            echo -e "  ${YEL}!${NC} Unsupervised app change detected: ${app} disabled (via web UI or external command)"
            journal_record "web-ui" "app_disable" "CHANGE" "$app" "OK" "detected via occ app:list diff"
            changed=true
        fi
    done <<< "$curr_disabled"

    # Update snapshot
    printf '%s' "$current_json" > "$APP_SNAPSHOT"

    $changed && return 0
    return 1  # no changes detected
}

# ── _journal_db_init at source time (no-op if sqlite3 absent) ─────────────────
# Called from igor.sh after sourcing this file.
journal_init() {
    _journal_ensure_dir
    _journal_db_init
}

# ── _mod_recovery_startup_check ───────────────────────────────────────────────
# Also defined here (mirroring recovery/core.sh) so that it is available at
# igor.sh startup — journal.sh is sourced unconditionally, core.sh is lazy-loaded.
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
        if (( fail_count > 0 )); then
            declare -f alert_log &>/dev/null && \
                alert_log "WARN" "journal_failures" \
                    "${fail_count} failed action(s) in the last 24h — check journal (V → 1)" \
                    2>/dev/null || true
        fi
    fi
}
