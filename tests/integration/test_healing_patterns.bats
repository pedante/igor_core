#!/usr/bin/env bats
# =============================================================================
#  tests/integration/test_healing_patterns.bats
#  Phase 4: Healing pattern system — pattern_record / pattern_confirm /
#            pattern_fail / pattern_suggest / pattern_eligible_check +
#            calculate_health_score (reads from cache file)
# =============================================================================

load "${BATS_TEST_DIRNAME}/../helpers/common"

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    stub_ui

    # patterns.sh uses _PATTERNS_DIR = ${IGOR_DIR}/data/patterns
    # IGOR_DIR already points to tmpdir from setup_igor_tmpdir

    # shellcheck source=/dev/null
    source "${REPO_DIR}/core/healing/patterns.sh"
    # shellcheck source=/dev/null
    source "${REPO_DIR}/core/healing/core.sh"
}

teardown() {
    teardown_igor_tmpdir
}

# ── Convenience: write a known pattern ────────────────────────────────────────
_write_test_pattern() {
    local code="${1:-test_pattern_code}"
    pattern_record "$code" \
        "Test pattern description" \
        "CHANGE" \
        "docker compose restart app" \
        "app container exited with code 1"
}

# ══════════════════════════════════════════════════════════════════════════════
#  pattern_record
# ══════════════════════════════════════════════════════════════════════════════

@test "pattern_record: creates pattern file" {
    _write_test_pattern "rec_test"
    [ -f "${_PATTERNS_DIR}/rec_test.pattern" ]
}

@test "pattern_record: file contains NAME field" {
    _write_test_pattern "name_test"
    grep -q "^NAME: name_test" "${_PATTERNS_DIR}/name_test.pattern"
}

@test "pattern_record: sets CONFIRMED to 0" {
    _write_test_pattern "confirmed_zero"
    grep -q "^CONFIRMED: 0" "${_PATTERNS_DIR}/confirmed_zero.pattern"
}

@test "pattern_record: sets FAILED to 0" {
    _write_test_pattern "failed_zero"
    grep -q "^FAILED: 0" "${_PATTERNS_DIR}/failed_zero.pattern"
}

@test "pattern_record: sets FIX_CMD correctly" {
    _write_test_pattern "cmd_test"
    grep -q "^FIX_CMD: docker compose restart app" "${_PATTERNS_DIR}/cmd_test.pattern"
}

@test "pattern_record: sets FIX_TIER correctly" {
    _write_test_pattern "tier_test"
    grep -q "^FIX_TIER: CHANGE" "${_PATTERNS_DIR}/tier_test.pattern"
}

@test "pattern_record: sets AUTO_ELIGIBLE to false" {
    _write_test_pattern "eligible_test"
    grep -q "^AUTO_ELIGIBLE: false" "${_PATTERNS_DIR}/eligible_test.pattern"
}

@test "pattern_record: returns 1 if code is empty" {
    run pattern_record "" "desc" "CHANGE" "cmd"
    [ "$status" -ne 0 ]
}

@test "pattern_record: returns 1 if fix_cmd is empty" {
    run pattern_record "code" "desc" "CHANGE" ""
    [ "$status" -ne 0 ]
}

@test "pattern_record: second call updates LAST_SEEN, does not reset CONFIRMED" {
    _write_test_pattern "idempotent_test"
    pattern_confirm "idempotent_test"
    # Call record again — should update LAST_SEEN but not reset CONFIRMED
    _write_test_pattern "idempotent_test"
    local confirmed
    confirmed=$(grep "^CONFIRMED: " "${_PATTERNS_DIR}/idempotent_test.pattern" | awk '{print $2}')
    [ "$confirmed" -eq 1 ] \
        || fail "CONFIRMED was reset by second pattern_record call; got: $confirmed"
}

# ══════════════════════════════════════════════════════════════════════════════
#  pattern_confirm / pattern_fail
# ══════════════════════════════════════════════════════════════════════════════

@test "pattern_confirm: increments CONFIRMED from 0 to 1" {
    _write_test_pattern "confirm_test"
    pattern_confirm "confirm_test"
    local val
    val=$(grep "^CONFIRMED: " "${_PATTERNS_DIR}/confirm_test.pattern" | awk '{print $2}')
    [ "$val" -eq 1 ]
}

@test "pattern_confirm: increments CONFIRMED from 1 to 2" {
    _write_test_pattern "confirm2_test"
    pattern_confirm "confirm2_test"
    pattern_confirm "confirm2_test"
    local val
    val=$(grep "^CONFIRMED: " "${_PATTERNS_DIR}/confirm2_test.pattern" | awk '{print $2}')
    [ "$val" -eq 2 ]
}

@test "pattern_confirm: returns 1 for unknown code" {
    run pattern_confirm "nonexistent_code_xyz"
    [ "$status" -ne 0 ]
}

@test "pattern_fail: increments FAILED from 0 to 1" {
    _write_test_pattern "fail_test"
    pattern_fail "fail_test"
    local val
    val=$(grep "^FAILED: " "${_PATTERNS_DIR}/fail_test.pattern" | awk '{print $2}')
    [ "$val" -eq 1 ]
}

@test "pattern_fail: returns 1 for unknown code" {
    run pattern_fail "nonexistent_code_xyz"
    [ "$status" -ne 0 ]
}

# ══════════════════════════════════════════════════════════════════════════════
#  pattern_suggest
# ══════════════════════════════════════════════════════════════════════════════

@test "pattern_suggest: returns FIX_CMD for known code" {
    _write_test_pattern "suggest_test"
    local out
    out=$(pattern_suggest "suggest_test")
    [[ "$out" == *"docker compose restart app"* ]] \
        || fail "FIX_CMD not in suggest output: $out"
}

@test "pattern_suggest: returns non-zero exit for unknown code" {
    run pattern_suggest "definitely_nonexistent_code_abc123"
    [ "$status" -ne 0 ]
}

# ══════════════════════════════════════════════════════════════════════════════
#  pattern_eligible_check
# ══════════════════════════════════════════════════════════════════════════════

@test "pattern_eligible_check: false when CONFIRMED < 5" {
    _write_test_pattern "elig_low"
    # Confirm only 4 times
    for _ in 1 2 3 4; do pattern_confirm "elig_low"; done
    run pattern_eligible_check "elig_low"
    [ "$status" -ne 0 ]
}

@test "pattern_eligible_check: false when CONFIRMED >= 5 but FAILED > 0" {
    _write_test_pattern "elig_fail"
    for _ in 1 2 3 4 5; do pattern_confirm "elig_fail"; done
    pattern_fail "elig_fail"
    run pattern_eligible_check "elig_fail"
    [ "$status" -ne 0 ]
}

@test "pattern_eligible_check: true when CONFIRMED >= 5 and FAILED = 0" {
    _write_test_pattern "elig_pass"
    for _ in 1 2 3 4 5; do pattern_confirm "elig_pass"; done
    run pattern_eligible_check "elig_pass"
    [ "$status" -eq 0 ]
}

@test "pattern_eligible_check: returns non-zero for unknown code" {
    run pattern_eligible_check "nonexistent_xyz"
    [ "$status" -ne 0 ]
}

# ══════════════════════════════════════════════════════════════════════════════
#  calculate_health_score (reads from cache file)
# ══════════════════════════════════════════════════════════════════════════════

_cache_file="${IGOR_DIR}/data/alerts/health_cache.txt"

@test "health_score: returns 100 when cache is empty" {
    : > "${IGOR_DIR}/data/alerts/health_cache.txt"
    local score; score=$(calculate_health_score)
    [ "$score" -eq 100 ]
}

@test "health_score: returns 100 when cache file does not exist" {
    rm -f "${IGOR_DIR}/data/alerts/health_cache.txt"
    local score; score=$(calculate_health_score)
    [ "$score" -eq 100 ]
}

@test "health_score: deducts 5 per WARN (1 WARN → 95)" {
    printf 'WARN disk_warn Disk at 76%%\n' > "${IGOR_DIR}/data/alerts/health_cache.txt"
    local score; score=$(calculate_health_score)
    [ "$score" -eq 95 ]
}

@test "health_score: deducts 15 per FAIL (1 FAIL → 85)" {
    printf 'FAIL ram_fail RAM below 80MB\n' > "${IGOR_DIR}/data/alerts/health_cache.txt"
    local score; score=$(calculate_health_score)
    [ "$score" -eq 85 ]
}

@test "health_score: deducts 30 per CRITICAL (1 CRITICAL → 70)" {
    printf 'CRITICAL cpu_critical CPU 87C\n' > "${IGOR_DIR}/data/alerts/health_cache.txt"
    local score; score=$(calculate_health_score)
    [ "$score" -eq 70 ]
}

@test "health_score: accumulates mixed severities correctly" {
    # 1 WARN (-5) + 1 FAIL (-15) = 80
    printf 'WARN disk_warn Disk high\nFAIL ram_fail RAM low\n' \
        > "${IGOR_DIR}/data/alerts/health_cache.txt"
    local score; score=$(calculate_health_score)
    [ "$score" -eq 80 ]
}

@test "health_score: score is clamped to 0 (never negative)" {
    # 4 CRITICAL × -30 = -20 → clamped to 0
    printf 'CRITICAL c1 x\nCRITICAL c2 x\nCRITICAL c3 x\nCRITICAL c4 x\n' \
        > "${IGOR_DIR}/data/alerts/health_cache.txt"
    local score; score=$(calculate_health_score)
    [ "$score" -eq 0 ]
}

@test "health_score: ignores OK lines (score stays 100)" {
    printf 'OK disk_ok Disk normal\nOK ram_ok RAM ok\n' \
        > "${IGOR_DIR}/data/alerts/health_cache.txt"
    local score; score=$(calculate_health_score)
    [ "$score" -eq 100 ]
}
