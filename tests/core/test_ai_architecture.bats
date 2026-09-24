#!/usr/bin/env bats

@test "AI architecture Python boundary tests pass" {
    run python3 "${BATS_TEST_DIRNAME}/../test_ai_architecture.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
