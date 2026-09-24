#!/usr/bin/env bats
# =============================================================================
#  tests/core/test_scrubbing.bats
#  Phase 2: Credential scrubbing — ai_scrub_build_table / ai_scrub_outbound /
#            ai_unscrub_inbound
#
#  Verifies that sensitive values are replaced with [IGOR:*] tokens before
#  being sent to the LLM, and that passwords are NEVER included in the table.
# =============================================================================

load '../helpers/common'
load '../helpers/mock_docker'

# ── IGOR_DIR points to a real repo for sourcing, but SCRUB_FROM reads from
#    the tmpdir's secrets/db.env for fixture values.
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    setup_mock_docker

    # Write fixture db.env with known values
    write_test_db_env

    # Set predictable path values so scrubbing is testable regardless of host
    export NC_DATA="/mnt/nextclouddata/next"
    export HD_MOUNT="/mnt/nextclouddata"

    # Source scrub.sh (defines ai_scrub_build_table, ai_scrub_outbound, etc.)
    # shellcheck source=/dev/null
    source "${REPO_DIR}/core/ai/scrub.sh"

    # Build the scrub table using the tmpdir's db.env
    ai_scrub_build_table
}

teardown() {
    teardown_igor_tmpdir
}

# ── Table population ───────────────────────────────────────────────────────────

@test "scrub table is non-empty after build" {
    [ "${#SCRUB_FROM[@]}" -gt 0 ]
}

@test "scrub table does not contain password (Tier 1 — omit entirely)" {
    local entry
    for entry in "${SCRUB_FROM[@]}"; do
        if [ "$entry" = "SHOULD_NEVER_APPEAR_IN_SCRUB_TABLE" ]; then
            fail "password found in SCRUB_FROM — it must never be sent to the API"
        fi
    done
}

@test "scrub table does not contain empty entries" {
    local entry
    for entry in "${SCRUB_FROM[@]}"; do
        [ -n "$entry" ] || fail "empty string found in SCRUB_FROM at index"
    done
}

# ── ai_scrub_outbound: hostname and IP ────────────────────────────────────────

@test "scrub_outbound replaces hostname with [IGOR:HOSTNAME]" {
    local hostname_val; hostname_val=$(hostname 2>/dev/null)
    [ -z "$hostname_val" ] && skip "hostname command unavailable"
    local result; result=$(ai_scrub_outbound "host is $hostname_val and all is well")
    [[ "$result" != *"$hostname_val"* ]] || fail "hostname still present after scrub: $result"
    [[ "$result" == *"[IGOR:HOSTNAME]"* ]] || fail "[IGOR:HOSTNAME] token missing: $result"
}

@test "scrub_outbound replaces LAN IP with [IGOR:LAN_IP]" {
    local lan_ip; lan_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$lan_ip" ] && skip "hostname -I unavailable"
    local result; result=$(ai_scrub_outbound "IP address is $lan_ip on the LAN")
    [[ "$result" != *"$lan_ip"* ]] || fail "LAN IP still present: $result"
    [[ "$result" == *"[IGOR:LAN_IP]"* ]] || fail "[IGOR:LAN_IP] token missing: $result"
}

@test "scrub_outbound replaces home directory with [IGOR:HOME_DIR]" {
    local result; result=$(ai_scrub_outbound "config lives in $HOME/.config/igor")
    [[ "$result" != *"$HOME"* ]] || fail "HOME still present: $result"
    [[ "$result" == *"[IGOR:HOME_DIR]"* ]] || fail "[IGOR:HOME_DIR] token missing: $result"
}

# ── ai_scrub_outbound: values from db.env ─────────────────────────────────────

@test "scrub_outbound replaces domain with [IGOR:DOMAIN]" {
    local result; result=$(ai_scrub_outbound "visit https://testcloud.example.com/login")
    [[ "$result" != *"testcloud.example.com"* ]] || fail "domain still present: $result"
    [[ "$result" == *"[IGOR:DOMAIN]"* ]] || fail "[IGOR:DOMAIN] token missing: $result"
}

@test "scrub_outbound replaces admin username with [IGOR:ADMIN_USER]" {
    local result; result=$(ai_scrub_outbound "admin user is testadmin please check")
    [[ "$result" != *"testadmin"* ]] || fail "admin user still present: $result"
    [[ "$result" == *"[IGOR:ADMIN_USER]"* ]] || fail "[IGOR:ADMIN_USER] token missing: $result"
}

@test "scrub_outbound replaces db name with [IGOR:DB_NAME]" {
    local result; result=$(ai_scrub_outbound "database testdb has 5 tables")
    [[ "$result" != *"testdb"* ]] || fail "db name still present: $result"
    [[ "$result" == *"[IGOR:DB_NAME]"* ]] || fail "[IGOR:DB_NAME] token missing: $result"
}

@test "scrub_outbound replaces db user with [IGOR:DB_USER]" {
    local result; result=$(ai_scrub_outbound "connecting as testuser to postgres")
    [[ "$result" != *"testuser"* ]] || fail "db user still present: $result"
    [[ "$result" == *"[IGOR:DB_USER]"* ]] || fail "[IGOR:DB_USER] token missing: $result"
}

@test "scrub_outbound replaces data path with [IGOR:DATA_PATH]" {
    local result; result=$(ai_scrub_outbound "user files at /mnt/nextclouddata/next/admin")
    [[ "$result" != *"/mnt/nextclouddata/next"* ]] || fail "data path still present: $result"
    [[ "$result" == *"[IGOR:DATA_PATH]"* ]] || fail "[IGOR:DATA_PATH] token missing: $result"
}

@test "scrub_outbound replaces HD mount with [IGOR:HD_MOUNT]" {
    local result; result=$(ai_scrub_outbound "disk at /mnt/nextclouddata has 500GB")
    # DATA_PATH is a subpath of HD_MOUNT — that should be replaced first (longer match)
    # Test that HD_MOUNT itself is also replaced when not prefixed by DATA_PATH
    [[ "$result" != *"/mnt/nextclouddata "* ]] || fail "HD_MOUNT still present: $result"
}

# ── ai_scrub_outbound: safe values pass through unchanged ─────────────────────

@test "scrub_outbound does not alter text with no sensitive values" {
    local plain="docker compose ps shows all services running"
    local result; result=$(ai_scrub_outbound "$plain")
    [ "$result" = "$plain" ] || fail "plain text was modified: $result"
}

@test "scrub_outbound handles empty string" {
    local result; result=$(ai_scrub_outbound "")
    [ -z "$result" ] || [ "$result" = "" ]
}

@test "scrub_outbound does not replace container names (Tier 3 — safe to send)" {
    local result; result=$(ai_scrub_outbound "container web and app are running")
    [[ "$result" == *"web"* ]] || fail "container name 'web' was incorrectly scrubbed"
    [[ "$result" == *"app"* ]] || fail "container name 'app' was incorrectly scrubbed"
}

# ── ai_unscrub_inbound: token reversal ────────────────────────────────────────

@test "unscrub_inbound restores hostname token" {
    local hostname_val; hostname_val=$(hostname 2>/dev/null)
    [ -z "$hostname_val" ] && skip "hostname command unavailable"
    local result; result=$(ai_unscrub_inbound "ssh pi@[IGOR:HOSTNAME] -p 22")
    [[ "$result" == *"$hostname_val"* ]] || fail "hostname not restored: $result"
}

@test "unscrub_inbound restores domain token" {
    local result; result=$(ai_unscrub_inbound "curl https://[IGOR:DOMAIN]/status.php")
    [[ "$result" == *"testcloud.example.com"* ]] || fail "domain not restored: $result"
}

@test "unscrub_inbound restores db user token" {
    local result; result=$(ai_unscrub_inbound "psql -U [IGOR:DB_USER] -d [IGOR:DB_NAME]")
    [[ "$result" == *"testuser"* ]]  || fail "db user not restored: $result"
    [[ "$result" == *"testdb"* ]]    || fail "db name not restored: $result"
}

@test "unscrub_inbound leaves non-token text unchanged" {
    local plain="docker compose restart app"
    local result; result=$(ai_unscrub_inbound "$plain")
    [ "$result" = "$plain" ] || fail "plain text was modified: $result"
}

@test "unscrub_inbound restores an extracted command without an execute marker" {
    local result; result=$(ai_unscrub_inbound "curl https://[IGOR:DOMAIN]/status.php")
    [[ "$result" == *"https://testcloud.example.com/status.php"* ]] \
        || fail "extracted command token was not restored: $result"
}

@test "known mappings win over generic IP scrubbing" {
    SCRUB_FROM=("192.0.2.5")
    SCRUB_TO=("[IGOR:LAN_IP]")
    local result; result=$(ai_scrub_outbound "ping 192.0.2.5")
    [ "$result" = "ping [IGOR:LAN_IP]" ] || fail "mapping was replaced generically: $result"
}

@test "known domain token survives generic URL scrubbing" {
    local result; result=$(ai_scrub_outbound "curl https://[IGOR:DOMAIN]/status.php")
    [ "$result" = "curl https://[IGOR:DOMAIN]/status.php" ] \
        || fail "labelled domain was scrubbed as a URL: $result"
}

@test "longer mappings are applied before parent paths" {
    SCRUB_FROM=("/mnt/nextclouddata" "/mnt/nextclouddata/next")
    SCRUB_TO=("[IGOR:HD_MOUNT]" "[IGOR:DATA_PATH]")
    local result; result=$(ai_scrub_outbound "/mnt/nextclouddata/next/admin")
    [ "$result" = "[IGOR:DATA_PATH]/admin" ] || fail "parent mapping consumed child: $result"
}
