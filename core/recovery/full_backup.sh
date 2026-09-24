#!/bin/bash
# IGOR — recovery/full_backup.sh
# Full backup — core snapshot + all module hooks + archive.
#
# Module hook API:
#   modules/*/hooks/backup.sh  — each must define:
#       igor_module_backup_hook "$SNAPSHOT_DIR" "$MODULE_NAME"
#       Module drops its data into $SNAPSHOT_DIR/modules/$MODULE_NAME/
#
#   modules/*/hooks/restore.sh — each must define:
#       igor_module_restore_hook "$SNAPSHOT_DIR" "$MODULE_NAME"
#
# Storage: $IGOR_BACKUPS_DIR/full_{EPOCH}_{UNIQUE}/
#   config_{EPOCH}.tar.gz      — independent copy of config_backup_take output
#   modules/                   — one subdir per module that ran its hook
#
# Public functions:
#   full_backup_take               — core snapshot + module hooks + archive
#   full_backup_list               — list available full backups
#   full_backup_restore [DIR]      — staged restore: module hook restore + scope selection
#   _mod_fb_run_hooks SNAPSHOT_DIR — iterate modules/*/hooks/backup.sh

_fb_backup_dir() {
    if declare -f _igor_resolve_dir &>/dev/null; then
        _igor_resolve_dir backups
    else
        echo "${IGOR_BACKUPS_DIR:-${IGOR_DIR}/data/backups}"
    fi
}

# ── full_backup_take ──────────────────────────────────────────────────────────
full_backup_take() {
    local RED='\033[0;31m' GRN='\033[0;32m' YEL='\033[1;33m'
    local CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'

    local BACKUP_DIR; BACKUP_DIR="$(_fb_backup_dir)"
    step "Full backup — core snapshot + module hooks"

    # Health check (warn if degraded, don't block)
    if declare -f calculate_health_score &>/dev/null; then
        local score; score=$(calculate_health_score 2>/dev/null || echo 0)
        if [ "$score" -lt 60 ]; then
            warn "Health score ${score}/100 — system may be degraded. Backup flagged."
        else
            ok "Health score: ${score}/100"
        fi
    fi

    local ts; ts=$(date +%s)
    mkdir -p "$BACKUP_DIR" || return 1
    local dest
    dest=$(mktemp -d "${BACKUP_DIR}/full_${ts}_XXXXXX") || return 1
    mkdir -p "${dest}/modules" || return 1

    local failed=false
    local -a failures=()

    # ── 1. Core snapshot ──────────────────────────────────────────────────────
    step "Taking core snapshot..."
    declare -f config_backup_take &>/dev/null || \
        source "${IGOR_DIR}/core/recovery/config_backup.sh" 2>/dev/null || true

    local core_archive
    core_archive=$(config_backup_take "full-backup:${ts}") || {
        warn "Core snapshot had errors — continuing"
        failed=true
        failures+=("core snapshot creation failed")
    }
    if [ -n "$core_archive" ] && [ -f "$core_archive" ] &&
       cp -p -- "$core_archive" "${dest}/$(basename "$core_archive")"; then
        ok "Core snapshot copied: $(basename "$core_archive")"
    else
        warn "Core snapshot missing or could not be copied"
        failed=true
        failures+=("core snapshot missing or copy failed")
    fi

    # ── 2. Module backup hooks ─────────────────────────────────────────────────
    if ! _mod_fb_run_hooks "${dest}" 2>"${dest}/MODULE_BACKUP_ERRORS.txt"; then
        failed=true
        failures+=("module backup hooks failed (see MODULE_BACKUP_ERRORS.txt)")
        warn "Module backup hooks failed"
    fi

    # ── 3. Full backup manifest ────────────────────────────────────────────────
    {
        echo "IGOR Full Backup"
        if $failed; then
            echo "STATUS: PARTIAL"
            printf 'ERROR: %s\n' "${failures[@]}"
        else
            echo "STATUS: COMPLETE"
        fi
        echo "TIMESTAMP: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "HOST:      $(hostname 2>/dev/null || echo unknown)"
        echo "IGOR_VER:  $(cat "${IGOR_DIR}/VERSION" 2>/dev/null || echo unknown)"
        echo ""
        echo "CONTENTS:"
        ls -lh "$dest" 2>/dev/null
        echo ""
        echo "MODULE HOOKS:"
        for _mdir in "${dest}/modules/"/*/; do
            [ -d "$_mdir" ] || continue
            printf '  %-30s %s\n' "$(basename "$_mdir")" \
                "$(du -sh "$_mdir" 2>/dev/null | cut -f1)"
        done
    } > "${dest}/FULL_BACKUP_MANIFEST.txt" || {
        failed=true
        failures+=("manifest write failed")
    }

    local sz; sz=$(du -sh "$dest" 2>/dev/null | cut -f1)

    if $failed; then
        warn "Full backup partially complete: $(basename "$dest")/ (${sz})"
        declare -f journal_record &>/dev/null && \
            journal_record "menu:recovery" "backup_taken" "READ" \
                "full_backup_take" "FAIL" "dest:$(basename "$dest") errors:${failures[*]}"
        declare -f alert_log &>/dev/null && \
            alert_log "WARN" "backup_partial" "Full backup incomplete: ${failures[*]}"
        declare -f notify_event &>/dev/null && \
            notify_event "backup_fail" \
                "Full backup FAILED (partial) — $(basename "$dest")/ (${sz})" \
                "Full Backup Failed" 2>/dev/null || true
    else
        ok "Full backup complete: $(basename "$dest")/ (${sz})"
        declare -f journal_record &>/dev/null && \
            journal_record "menu:recovery" "backup_taken" "READ" \
                "full_backup_take" "OK" "dest:$(basename "$dest") size:${sz}"
        declare -f notify_event &>/dev/null && \
            notify_event "backup_done" \
                "Full backup complete: $(basename "$dest")/ (${sz})" \
                "Full Backup Done" 2>/dev/null || true
    fi

    # An incomplete replacement must not evict a known-good backup.
    $failed || _mod_fb_prune_old
    printf '%s' "$dest"
    ! $failed
}

# ── _mod_fb_run_hooks SNAPSHOT_DIR ───────────────────────────────────────────
# Call all functions registered for the "backup" hook point.
# Uses igor_run_all_hooks if available (module_loader.sh loaded),
# falls back to igor_get_hooks + manual dispatch if needed.
_mod_fb_run_hooks() {
    local snapshot_dir="$1"

    if declare -f igor_run_all_hooks &>/dev/null; then
        igor_run_all_hooks "backup" "$snapshot_dir"
    elif declare -f igor_get_hooks &>/dev/null; then
        local hooks_run=0 any_fail=0
        local fn
        for fn in $(igor_get_hooks "backup"); do
            if ! declare -f "$fn" &>/dev/null; then
                printf 'Backup hook missing: %s\n' "$fn" >&2
                any_fail=1
                continue
            fi
            step "Module backup hook: ${fn}"
            if ( "$fn" "$snapshot_dir" ); then
                ok "${fn} completed"
            else
                printf 'Backup hook failed: %s\n' "$fn" >&2
                any_fail=1
            fi
            hooks_run=$(( hooks_run + 1 ))
        done
        [ "$hooks_run" -eq 0 ] && info "No backup hooks registered (igor_register_hook backup ...)"
        return "$any_fail"
    else
        warn "Module loader not available — cannot run module backup hooks" >&2
        return 1
    fi
}

# ── full_backup_list ──────────────────────────────────────────────────────────
full_backup_list() {
    local BOLD='\033[1m' CYAN='\033[0;36m' GRN='\033[0;32m' NC='\033[0m'
    local BACKUP_DIR; BACKUP_DIR="$(_fb_backup_dir)"

    echo ""
    printf "  ${BOLD}%-4s  %-19s  %-10s  %-10s  %-8s  %s${NC}\n" \
        "#" "DATE" "CORE" "MODULES" "SIZE" "DIRECTORY"
    printf "  %s\n" "$(printf '─%.0s' {1..80})"

    local i=0 dirs=()
    while IFS= read -r d; do
        dirs+=("$d")
    done < <(ls -dt "${BACKUP_DIR}"/full_* 2>/dev/null)

    if [ ${#dirs[@]} -eq 0 ]; then
        echo "  (no full backups found)"
        echo ""
        return 0
    fi

    for d in "${dirs[@]}"; do
        [ -d "$d" ] || continue
        (( i++ ))
        local epoch; epoch=$(basename "$d" | grep -oE '[0-9]+' | head -1)
        local dt; dt=$(date -d "@${epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$epoch")
        local core_present; core_present=$(ls "${d}"/config_*.tar.gz 2>/dev/null | wc -l)
        local mods_present; mods_present=$(ls -d "${d}/modules/"*/ 2>/dev/null | wc -l)
        local sz; sz=$(du -sh "$d" 2>/dev/null | cut -f1)
        printf "  %-4s  %-19s  %-10s  %-10s  %-8s  %s\n" \
            "$i" "$dt" "${core_present} archive(s)" "${mods_present} module(s)" "$sz" \
            "$(basename "$d")"
    done
    echo ""
    echo "  Total: ${i} full backup(s)  (keep: ${BACKUP_FULL_KEEP:-3})"
    echo ""
    _FULL_BACKUP_LIST_DIRS=("${dirs[@]}")
}

# ── full_backup_restore [BACKUP_DIR] ─────────────────────────────────────────
# Staged restore: list → select → scope → diff → confirm → apply → health check.
full_backup_restore() {
    local backup_dir_arg="${1:-}"
    local RED='\033[0;31m' GRN='\033[0;32m' YEL='\033[1;33m'
    local CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'
    local BACKUP_DIR; BACKUP_DIR="$(_fb_backup_dir)"

    # Picker
    if [ -z "$backup_dir_arg" ]; then
        full_backup_list
        [ ${#_FULL_BACKUP_LIST_DIRS[@]} -eq 0 ] && return 1
        read -rp "  Select backup number: " _sel
        backup_dir_arg="${_FULL_BACKUP_LIST_DIRS[$(( _sel - 1 ))]}"
    fi
    [ ! -d "$backup_dir_arg" ] && { fail "Backup directory not found: $backup_dir_arg"; return 1; }

    echo ""
    echo -e "  ${BOLD}Full Backup:${NC} $(basename "$backup_dir_arg")"
    local _backup_epoch; _backup_epoch=$(basename -- "$backup_dir_arg")
    _backup_epoch="${_backup_epoch#full_}"
    _backup_epoch="${_backup_epoch%%_*}"
    echo -e "  ${BOLD}Date:${NC}        $(date -d "@${_backup_epoch}" 2>/dev/null)"
    echo -e "  ${BOLD}Contents:${NC}"
    ls -lh "$backup_dir_arg" 2>/dev/null | tail -n +2 | while read -r line; do echo "    $line"; done
    echo ""

    # Scope selection
    local _scope
    _scope=$(igor_fzf_pick "Full Backup Restore — Scope" \
        "1:CORE SNAPSHOT:Restore Igor state / system config / Docker files" \
        "2:MODULE DATA:Run module restore hooks (DB restore, etc.)" \
        "3:FULL RESTORE:Core + all modules — staged with per-step confirm" \
        "b:BACK:Cancel")
    case $? in 1|2)
        echo "    1) Core snapshot only"
        echo "    2) Module restore hooks only"
        echo "    3) Full restore (staged)"
        echo "    b) Back"
        read -rp "  Choice: " _scope ;; esac

    case "$_scope" in
        1)
            local _core; _core=$(ls "${backup_dir_arg}"/config_*.tar.gz 2>/dev/null | head -1)
            [ -n "$_core" ] && config_backup_restore "$_core" || \
                warn "No core snapshot found in this backup"
            ;;
        2)
            _mod_fb_run_restore_hooks "$backup_dir_arg"
            ;;
        3)
            local _core2; _core2=$(ls "${backup_dir_arg}"/config_*.tar.gz 2>/dev/null | head -1)
            [ -n "$_core2" ] && config_backup_restore "$_core2" "all" || \
                warn "No core snapshot found"
            _mod_fb_run_restore_hooks "$backup_dir_arg"
            ;;
        b|B) return 0 ;;
        *)   fail "Invalid choice" ;;
    esac

    # Post-restore health check
    declare -f health_check_full &>/dev/null && {
        echo ""
        info "Running health checks post-restore..."
        health_check_full "false" 2>/dev/null || true
    }
}

# ── _mod_fb_run_restore_hooks BACKUP_DIR ─────────────────────────────────────
# Call all functions registered for the "restore" hook point.
_mod_fb_run_restore_hooks() {
    local backup_dir="$1"

    if declare -f igor_run_all_hooks &>/dev/null; then
        igor_run_all_hooks "restore" "$backup_dir"
    elif declare -f igor_get_hooks &>/dev/null; then
        local hooks_run=0
        local fn
        for fn in $(igor_get_hooks "restore"); do
            declare -f "$fn" &>/dev/null || continue
            echo ""
            echo -e "  Module restore: ${fn}"
            ( "$fn" "$backup_dir" ) && \
                ok "${fn} completed" || warn "${fn} failed"
            hooks_run=$(( hooks_run + 1 ))
        done
        [ "$hooks_run" -eq 0 ] && info "No restore hooks registered (igor_register_hook restore ...)"
    else
        info "Module loader not available — skipping module restore hooks"
    fi
}

# ── _mod_fb_prune_old ─────────────────────────────────────────────────────────
_mod_fb_prune_old() {
    local BACKUP_DIR; BACKUP_DIR="$(_fb_backup_dir)"
    local keep="${BACKUP_FULL_KEEP:-3}"
    local i=0
    ls -dt "${BACKUP_DIR}"/full_* 2>/dev/null | while IFS= read -r d; do
        # Partial attempts are not counted as replacements for complete backups.
        [ -f "$d/FULL_BACKUP_MANIFEST.txt" ] || continue
        grep -q '^STATUS: PARTIAL$' "$d/FULL_BACKUP_MANIFEST.txt" 2>/dev/null && continue
        i=$(( i + 1 ))
        [ "$i" -gt "$keep" ] && rm -rf "$d" 2>/dev/null || true
    done
}
