#!/usr/bin/env bats

load '../helpers/common'

setup() {
    setup_igor_tmpdir
}

teardown() {
    teardown_igor_tmpdir
}

@test "context LAN address uses hostname -I when supported" {
    source "${BATS_TEST_DIRNAME}/../../core/ai/context.sh"
    hostname() {
        [ "$1" = "-I" ] && { printf '2001:db8::5 192.0.2.55\n'; return 0; }
        printf 'test-host\n'
    }
    ip() { return 1; }
    run _ai_lan_ip
    [ "$status" -eq 0 ]
    [ "$output" = "192.0.2.55" ]
}

@test "context LAN address falls back when hostname does not support -I" {
    source "${BATS_TEST_DIRNAME}/../../core/ai/context.sh"
    hostname() {
        [ "$1" = "-I" ] && return 2
        printf 'test-host\n'
    }
    ip() {
        printf '1.1.1.1 via 192.0.2.1 dev eth0 src 192.0.2.44 uid 0\n'
    }
    run _ai_lan_ip
    [ "$status" -eq 0 ]
    [ "$output" = "192.0.2.44" ]
}

@test "scrub table uses the same portable LAN address fallback" {
    source "${BATS_TEST_DIRNAME}/../../core/ai/scrub.sh"
    hostname() {
        [ "$1" = "-I" ] && return 2
        printf 'test-host\n'
    }
    ip() {
        printf '1.1.1.1 via 192.0.2.1 dev eth0 src 192.0.2.44 uid 0\n'
    }
    ai_scrub_build_table
    local found=false value
    for value in "${SCRUB_FROM[@]}"; do
        [ "$value" = "192.0.2.44" ] && found=true
    done
    [ "$found" = true ]
}

@test "scrub table prefers IPv4 when hostname returns IPv6 first" {
    source "${BATS_TEST_DIRNAME}/../../core/ai/scrub.sh"
    hostname() {
        [ "$1" = "-I" ] && { printf '2001:db8::5 192.0.2.55\n'; return 0; }
        printf 'test-host\n'
    }
    ip() { return 1; }
    ai_scrub_build_table
    local found=false value
    for value in "${SCRUB_FROM[@]}"; do
        [ "$value" = "192.0.2.55" ] && found=true
    done
    [ "$found" = true ]
}
