#!/bin/bash
# ==============================================================================
#  IGOR — diagnose/sequences.sh
#  Named multi-step fix sequences for common compound failure states.
#
#  Provides:
#    • _diag_run_sequence()              — execute a named step sequence
#    • _diag_sequence_cold_start()       — full stack cold-start procedure
#    • _diag_sequence_unclean_shutdown() — recovery from unclean shutdown
#    • _diag_sequence_post_update()      — recovery after NC version upgrade
#
#  Each sequence is a pipe-delimited list of fix codes from _DIAG_FIX_CATALOGUE.
#  Steps run in order. Failure at any step halts the sequence and gives the user
#  the choice to retry, skip, or abort. Continuation past a failed step always
#  requires explicit user confirmation.
# ==============================================================================

# ── Sequence definitions ───────────────────────────────────────────────────────
# Format: pipe-delimited fix_code list, executed left-to-right
declare -gA _DIAG_SEQUENCES

_DIAG_SEQUENCES[cold_start]="seq_check_docker|seq_start_stack|seq_wait_db|seq_verify_http"
_DIAG_SEQUENCES[unclean_shutdown]="seq_check_hd_mount|seq_restart_db|seq_flush_redis|seq_occ_repair|seq_clear_maintenance|seq_verify_http"
_DIAG_SEQUENCES[post_update]="seq_enable_maintenance|seq_occ_upgrade|seq_db_indices|seq_occ_repair|seq_clear_maintenance|seq_verify_http"

# ── Sequence-specific fix definitions ─────────────────────────────────────────
# These are sequence steps that may not be in the standard fix catalogue.
# Format matches _DIAG_FIX_CATALOGUE: TIER|CMD|DESCRIPTION|DOWNTIME|PHRASE|RECHECK_FN|SETTLE
_diag_register_sequence_steps() {
    _DIAG_FIX_CATALOGUE[seq_check_docker]="AUTO|docker info >/dev/null 2>&1|Verify Docker daemon is running|||_diag_recheck_docker_running|1"
    _DIAG_FIX_CATALOGUE[seq_start_stack]="CAUTION|docker compose up -d|Start full container stack|All services starting — may take 60-90s|||_diag_recheck_stack_up|90"
    _DIAG_FIX_CATALOGUE[seq_wait_db]="AUTO|docker compose exec -T db pg_isready -q 2>/dev/null || sleep 10|Wait for database readiness|||_diag_recheck_db_ready|5"
    _DIAG_FIX_CATALOGUE[seq_check_hd_mount]="AUTO|mount | grep -q '${HD_MOUNT:-/mnt/nextclouddata}'|Verify HD is mounted|||_diag_recheck_hd_mounted|1"
    _DIAG_FIX_CATALOGUE[seq_restart_db]="SAFE|docker compose restart db|Restart database container (recovery from unclean shutdown)|||_diag_recheck_db_ready|30"
    _DIAG_FIX_CATALOGUE[seq_flush_redis]="SAFE|docker compose exec -T redis redis-cli FLUSHDB|Flush Redis cache database (session data will be cleared)|||_diag_recheck_redis_ping|3"
    _DIAG_FIX_CATALOGUE[seq_occ_repair]="SAFE|docker compose exec -T -u www-data app php occ maintenance:repair|Run Nextcloud repair (may take 1-2 minutes)|||_diag_recheck_occ_status|60"
    _DIAG_FIX_CATALOGUE[seq_clear_maintenance]="AUTO|docker compose exec -T -u www-data app php occ maintenance:mode --off|Disable Nextcloud maintenance mode|||_diag_recheck_occ_maintenance|2"
    _DIAG_FIX_CATALOGUE[seq_verify_http]="AUTO|curl -sf --max-time 10 \"http://localhost:${IGOR_WEB_PORT:-8080}/status.php\" >/dev/null|Verify HTTP response from Nextcloud|||_diag_recheck_nc_http|3"
    _DIAG_FIX_CATALOGUE[seq_enable_maintenance]="AUTO|docker compose exec -T -u www-data app php occ maintenance:mode --on|Enable maintenance mode for upgrade|||_diag_recheck_occ_maintenance_on|2"
    _DIAG_FIX_CATALOGUE[seq_occ_upgrade]="CAUTION|docker compose exec -T -u www-data app php occ upgrade|Run Nextcloud upgrade (may take several minutes)|All users offline during upgrade|||_diag_recheck_occ_status|120"
    _DIAG_FIX_CATALOGUE[seq_db_indices]="SAFE|docker compose exec -T -u www-data app php occ db:add-missing-indices|Add any missing database indices|||_diag_recheck_occ_status|30"
}

# ── Run a named sequence ───────────────────────────────────────────────────────
_diag_run_sequence() {
    local seq_name="$1"
    local steps_str="${_DIAG_SEQUENCES[$seq_name]:-}"

    if [ -z "$steps_str" ]; then
        fail "Unknown sequence: ${seq_name}"
        _diag_log "sequence: unknown sequence '${seq_name}'"
        return 1
    fi

    # Register sequence-specific steps into the fix catalogue
    _diag_register_sequence_steps

    IFS='|' read -ra steps <<< "$steps_str"
    local total=${#steps[@]}
    local i=0
    local failed_steps=0

    step "Sequence: ${seq_name} (${total} steps)"
    _diag_log "sequence: starting '${seq_name}' (${total} steps)"
    echo ""

    local step_code
    for step_code in "${steps[@]}"; do
        (( i++ ))
        echo -e "  ${CYAN}[${i}/${total}]${NC} ${step_code}"
        _diag_log "sequence step ${i}/${total}: ${step_code}"

        if [ -z "${_DIAG_FIX_CATALOGUE[$step_code]:-}" ]; then
            warn "No fix definition for step: ${step_code} — skipping"
            _diag_log "sequence: no catalogue entry for '${step_code}' — skipped"
            continue
        fi

        # Run the fix-recheck loop for this step
        if ! _diag_fix_recheck_loop "$step_code"; then
            (( failed_steps++ ))
            fail "Step failed: ${step_code}"
            echo ""
            if ! confirm "  Step ${i}/${total} failed. Continue sequence anyway?"; then
                warn "Sequence aborted at step ${i}/${total}: ${step_code}"
                _diag_log "sequence: aborted at step ${i} by user"
                return 1
            fi
        fi
        echo ""
    done

    if (( failed_steps == 0 )); then
        ok "Sequence complete: ${seq_name}"
        _diag_log "sequence: '${seq_name}' completed successfully"
    else
        warn "Sequence complete with ${failed_steps} failed step(s): ${seq_name}"
        _diag_log "sequence: '${seq_name}' finished with ${failed_steps} failures"
    fi

    return 0
}

# ── Named sequence convenience wrappers ───────────────────────────────────────
_diag_sequence_cold_start() {
    _diag_run_sequence "cold_start"
}

_diag_sequence_unclean_shutdown() {
    _diag_run_sequence "unclean_shutdown"
}

_diag_sequence_post_update() {
    _diag_run_sequence "post_update"
}

# ── Sequence-specific recheck functions ───────────────────────────────────────
_diag_recheck_docker_running() {
    docker info >/dev/null 2>&1 && echo "OK" || echo "FAIL"
}

_diag_recheck_stack_up() {
    local count
    count=$(docker compose ps --status running --services 2>/dev/null | wc -l)
    (( count > 0 )) && echo "OK" || echo "FAIL"
}

_diag_recheck_db_ready() {
    local svc="${_DIAG_ROLES[db]:-db}"
    docker compose exec -T "$svc" pg_isready -q 2>/dev/null && echo "OK" || echo "FAIL"
}

_diag_recheck_hd_mounted() {
    mount | grep -q "${HD_MOUNT:-/mnt/nextclouddata}" && echo "OK" || echo "FAIL"
}

_diag_recheck_occ_maintenance_on() {
    local status
    status=$(docker compose exec -T -u www-data app php occ status --output=json 2>/dev/null)
    echo "$status" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('OK' if d.get('maintenance', False) else 'FAIL')
except Exception:
    print('FAIL')
" 2>/dev/null || echo "FAIL"
}
