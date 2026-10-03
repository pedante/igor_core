# Boundary B baseline reproduction evidence

This is a review record for [validation_baseline.json](validation_baseline.json),
not a claim of a green full suite. Baseline metadata is edited explicitly;
validation never writes or automatically accepts entries. CI integration and
the final full release gate remain Boundary C work.

## Source

Candidate tests were reproduced individually on a `git archive` export of
`525cc76ea556bae199fecfaaa6bd931d01a9f6ea` (tree
`713ea865a3bd80cb7166a33b109c5202b3ec54be`). This isolated reproduction avoids
switching the active branch. Only developer harness adapters are supplied to
the export; product code and test fixtures are unchanged. Historical STATUS
and composite logs supply candidate names, never accepted outcomes.
After all probes, all 391 tracked archive files were rehashed against the
source Git blobs, with zero mismatches. Only three harness adapter files were
added; no archived product or test file was edited.

The reproduction uses cached pytest 9.1.1 and BATS 1.13.0. Python commands are
`python -m pytest -q NODE`; BATS commands select an anchored exact test-name
filter and use native per-test deadlines. Raw output is retained outside Git.
Stable identities and the decisive results are recorded here instead of logs.

## Python assertions

Each following pytest node reproduced an assertion failure, with a 180-second
outer bound. Node prefixes and complete identities are in the linked manifest.

| File/class | Test | Elapsed |
|---|---|---|
| `test_ai_architecture.py::AiArchitectureTests` | `test_cli_status_tools_and_last_without_api_key_or_active_modules` | 1.57s |
| `test_ai_interaction_surface.py::InspectionAuthorityTests` | `test_typed_invoke_is_operator_activity_not_conversation` | 1.42s |
| `test_operator_surface.py::OperatorSurfaceTests` | `test_surface_projects_existing_contracts_without_execution_data` | 1.12s |

## BATS assertions

Exact-name filters reproduced the following failures on the exported source,
with `BATS_TEST_TIMEOUT=180` and a 240-second process bound. Source-file names
and complete stable identities are in the manifest. The architecture wrapper
and its underlying Python test remain separately visible canonical identities.

| File | Test | Native TAP test timing |
|---|---|---|
| `core/test_ai_architecture.bats` | `AI architecture Python boundary tests pass` | 1.85s |
| `core/test_ai_events.bats` | `events have stable envelope fields and preserve order` | 0.03s |
| `modules/test_step18_module_contract.bats` | `v2 privileged declarations remain unavailable without typed Core adapter` | 19.43s |
| `modules/test_system_admin_surface.bats` | `system administration contracts project into the generic operator namespace` | 53.16s |
| `modules/test_system_admin_surface.bats` | `package upgrade freezes distro-specific argv and verifies the Debian result` | 46.69s |

Those three targeted invocations retained a watchdog after emitting their
assertion results, completing only at the 180-second native watchdog deadline.
The table reports native TAP test timing, not process elapsed time. This BATS
cleanup/lifecycle delay remains visible evidence; it is not accepted as a
test timeout and no external runner or product code is repaired here.
The final two cases were reproduced with the native watchdog unset and a
180-second outer process bound to avoid that known cleanup delay; their
reported durations are actual runner elapsed time.

## Startup timeouts

`tests/test_startup_privilege.py::StartupPrivilegeTests::test_start_and_fast_enter_after_normal_user_startup`
was run twice, individually, with the structured pytest adapter. Both attempts
reported `TIMEOUT` for each of the named `choice=s` and `choice=f` subtests.
These are the test's own `subprocess.run(..., timeout=20)` exceptions, not an
outer harness deadline. Each parent invocation completed in about 41.8s.
The parent call report passes even when its subtests fail; the adapter retains
the two subtest outcomes independently. Complete JSON-normalized identities
are in the manifest. No timing entry is accepted from a single observation.

## Not accepted

Historical automation assertions `test_canonical_precondition_failure_is_recorded_without_execution`,
`test_real_condition_memory_read_uses_existing_observation_and_dispatch`, and
`test_real_periodic_memory_refresh_uses_canonical_dispatch` passed isolated
reproduction (44.33s, 64.60s, and 77.37s). They are not baseline failures.

Automation `test_cli_fresh_process_no_capability_invocation` and
`test_real_one_time_memory_dispatch_modes_and_restart` reached the targeted
180-second outer budget. Each performs multiple CLI/dispatch operations, with
no per-call deadline. These single budget-limited observations are inconclusive;
they are not accepted assertion failures or timeout baselines.

The historical System configuration workflow timeout occurred under concurrent
full validation and subsequently passed in isolation. It is not accepted from
that historical evidence; no expensive workflow rerun is part of Boundary B.

The three historical TUI palette hang identities (`test_palette_sends_a_complete_local_command_to_backend`,
`test_palette_query_filters_before_invocation`, and
`test_palette_selection_invokes_the_same_backend_input_route`) are not accepted
from historical reports. Bounded reproduction stopped at the selected assertion
and startup candidates; no repeated expensive palette probes are claimed.
Earlier STATUS-only operator-backend failures likewise remain historical
evidence rather than entries in this baseline.

This is a deliberately bounded, incomplete baseline. Unaccepted historical
failures/hangs that reappear remain `FAIL_NEW`/`TIMEOUT_NEW` and block validation
until independently reproduced and reviewed. No exhaustive current regression
or green full suite is claimed.

## Environmental permissions

[validation_environment.py](validation_environment.py) permits only exact
GPG-agent/GPG-command and hostname/LAN-address skip reasons for the named tests
whose existing guards explicitly allow them. The exact encrypted-snapshot
test produced `ENV_SKIP` for its native GPG-agent guard during Boundary B.
There are no host Docker/systemd/network availability skips. Unknown skip
identities or reasons are errors; required missing tools remain nonzero
`TOOL_UNAVAILABLE` outcomes.
