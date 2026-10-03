"""Exact skip permissions from existing test contracts; no host-service probes.

Unknown skip identities/reasons fail closed. Docker/systemd fixture suites are
never skipped based on host availability. References identify the skip guards;
these permissions are reviewable code, independent of accepted failures.
"""

PERMITTED_SKIPS = {
    ("bats", "tests/core/test_backup_regressions.bats::encrypted secrets snapshot contains only the GPG payload"):
        {"gpg unavailable", "GPG agent unavailable in this runner"},
    ("bats", "tests/core/test_scrubbing.bats::scrub_outbound replaces hostname with [IGOR:HOSTNAME]"):
        {"hostname command unavailable"},
    ("bats", "tests/core/test_scrubbing.bats::scrub_outbound replaces LAN IP with [IGOR:LAN_IP]"):
        {"hostname -I unavailable"},
    ("bats", "tests/core/test_scrubbing.bats::unscrub_inbound restores hostname token"):
        {"hostname command unavailable"},
}
