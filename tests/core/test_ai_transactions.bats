#!/usr/bin/env bats

@test "AI native transaction and provider serialization regressions pass" {
    run python3 -m unittest tests.test_ai_transactions
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AI command registry regressions pass" {
    run python3 -m unittest tests.test_ai_session_commands
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AI interstitial and scrub status regressions pass" {
    run python3 -m unittest tests.test_ai_interstitial
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
