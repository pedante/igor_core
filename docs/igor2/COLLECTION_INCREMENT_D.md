# Increment D — Backend-authorized READ inspection

Date: 2026-10-13. Implementation on `igor2`, based on Owner-accepted
C checkpoint `7946742184225e2f14cb3588e21cca654cf3b9b0`.
Owner accepted Increment D at its defined READ inspection scope on 2026-10-13.
Acceptance covers backend-authorized inspection, authoritative snapshot input
derivation, READ-only binding enforcement, canonical execution, generic details,
Guide/approval enforcement and lifecycle recovery. It does not accept the complete
Collection Operator milestone. Runtime gates are complete; the Owner authorized
one checkpoint commit. No push, merge, live service operation or Increment E.
The first interrupted session below is historical and is superseded by the final
stabilization evidence.

## Authorization and execution

Enter sends the selected D049 reference, collection/provider identity, snapshot
revision and view-request correlation through the existing backend PTY/session
invoke command. An optional explicit READ provider resolves existing ambiguity.
The frontend sends no row properties, target capability name or derived inputs.

`Snapshots.selection()` checks the closed scoped reference against the original
live session owner, History scope, descriptor binding, absolute snapshot expiry,
active owner and membership of the private frozen snapshot. It validates the
backend row and its privacy projection using the existing shared validators.
`prepare_inspection()` resolves `CapabilityRegistry.inspection_binding()`, maps
`inputs_from_row`, calls the existing registry preparation/input/selector checks,
and checks READ eligibility and compatible target version/provider/owner.

The existing registration closure now includes descriptor-owned inspection
targets when preparing/checking inspection. It previously included composition
dependencies only, which made the real System READ binding unavailable despite
correct descriptor admission. Ordinary registry and dispatch paths are retained.

The backend keeps a bounded, mode-600 per-request context under its existing
private runtime. `ai_execute_tool` applies the unchanged Guide, approval and
privilege rules. `igor_capability_execute` repeats registry/snapshot/binding/input
derivation against the frozen request immediately before the existing execution
fence. Failure produces canonical nonexecution evidence; the target handler is
never called. Only then can the existing handler, output validator, verification,
History and result/event machinery run. There is no frontend executor, alternate
registry, identity system, dispatch protocol or mutation action.

Normal completion and rejected preparation remove the private request context.
Dead-backend contexts are swept at the existing snapshot lifecycle boundary;
unreadable abandoned context files expire after the existing TTL. Snapshot
reservations, budgets, ownership and cleanup remain Increment B's implementation.
Inspection never renews the absolute 30-second snapshot authority. An already
admitted READ can complete after inventory expiry; Back then shows expired rows
without restoring inspection authority. History cannot reconstruct selection.

## Generic frontend

The same collection navigator enters nonblocking details loading and suppresses
repeated Enter while loading. Correlated action results require a compatible READ
descriptor, matching reference/revision/provider/version and canonical result;
shared output validation precedes generic `render_structured` property rendering.
Rejected values and internal cursors are not displayed. Terminal-safe bounded
rendering, event sequencing and the 96-KiB frontend event ceiling remain in force.
Inspection capture uses the existing 30-second/96-KiB bounded handler transport.
Details retain at most the current collection page and a 64-KiB validated result.

Esc/b returns to the same inventory page, filter and selected identity without an
inventory query. Arrows/Page Up/Down scroll details; r repeats READ only while the
snapshot remains valid. Collection r requests explicit inventory refresh. Missing
inspection metadata shows validated inline row properties and executes nothing.
The details label distinguishes newly observed READ results from frozen inventory
properties. Expired/unavailable/failed results require explicit recovery.
Closing or switching a view retires its correlation; late/duplicate results do not
restore a dismissed view or cancel an already admitted operation. Guide approval
remains backend-owned when leaving details.

## Evidence ledger

All executions below followed inspected `tests/validate.sh --dry-run` plans.
Raw reports and historical failures remain preserved under `/tmp/igor2-d-*`.

| Evidence | Actual result | Classification |
| --- | --- | --- |
| d-authorization | 20 PASS, 1 new fixture failure | Registry inspection metadata's `available` field was incorrectly passed to closed descriptor admission; corrected fixture. |
| d-provider | 1 PASS | Corrected ambiguous/explicit provider case. |
| d-details | 79 PASS; Ruff failed | Raw output contained two new I001 diagnostics, despite broad runner baseline classification. |
| d-lint | 1 BASELINE_FIXED | Selected changed-file lint clean after correcting both new imports. Historical debt remains separate. |
| d-pty | 4 PASS, 1 FAIL_NEW | Real System selection unavailable due to omitted inspection target in registration closure. ShellCheck and three Bash syntax checks passed. |
| d-pty-corrected | 1 PASS | Real curses/PTY System list → Enter → canonical status → validated details → Back. |
| d-fence | 3 PASS | Expired, cross-session and changed-target requests produced canonical nonexecution with a handler side-effect sentinel remaining absent. |

### Historical interrupted closing selection

The first closing selection, `/tmp/igor2-d-closing-executed/summary.json`, stopped at
98.979 s with **220 reported PASS identities/check groups, 1 lint failure,
4 governor-induced TIMEOUT groups and 1 ENV_SKIP**. There were zero reported
FAIL_NEW test assertions, BASELINE_FIXED, tool-unavailable results or errors.
The lint failure was labelled FAIL_BASELINE by the broad runner rule, but its raw
I001 diagnostic in `test_collection_inspection_pty.py` is **new Increment D debt**.
At that stop, formatting was corrected but verification was unexecuted. Historical new
diagnostics and failures remain accurately classified above, not hidden as debt.

The 33 focused D tests passed, including all three canonical handler sentinels
and dead-backend context cleanup/Guide Back. Completed groups also establish
50 collection-view, 21 operator-TUI, four privilege-TUI and 22 capability tests;
fresh privilege and scrubbing suites; targeted binding/limit, snapshot lifecycle,
runtime permissions, TTL, UTF-8 event-bound and secret-publication checks.
The all-mode mock PTY regression passed. These are not a complete acceptance gate.

Gates outstanding at the first stop (now resolved below):

- Approval BATS emitted 24/25 passing identities before its subprocess was killed
  by the total governor. Its final identity and whole-group completion are
  unverified; no product hang or 240-second timeout is claimed.
- History `test_read_and_change_terminal_outcomes_and_read_only_inspection`,
  `test_running_claim_binds_to_the_live_canonical_proposal` and
  `test_secrets_are_redacted_and_never_retained_in_episode_or_evidence` were killed
  at the shared deadline. The middle node emitted one subtest PASS before
  interruption, included in the runner's 220 count; this did not complete its gate.
- `tests/test_secret_refs.py` was pending and never dispatched (two tests).
- Corrected changed-file Ruff verification remains unexecuted.
- Fresh inspection-specific Guide admission/approval evidence beyond mocked
  all-mode interaction and the pending-approval Back unit test remains open.

The permitted scrub skip was `hostname -I unavailable`, not a passing privacy
test. Four subprocess groups were interrupted; the report records them as
TIMEOUT_NEW, active groups were cancelled, and the secret-reference group remained
pending. The governor then reported zero remaining seconds. No model retry or
renewal was attempted. The initial closing launch found that the preview had
created its output directory and exited before validation; a new directory was
planned and used, with no product or test result attributed to that launch.

Earlier passes overlap this run and must not be added to 220 as unique final
proof. The positive real curses demo is separate earlier evidence; its exact
candidate preceded private-context orphan cleanup/view-inspection metadata and
final help/import/documentation changes. Closing authorization/recovery checks
exercised those production changes, but no new final real-PTY run was dispatched.
All raw logs and plans remain preserved.
Accepted A/B/C baseline failures and environmental limitations remain historical;
they were not repaired or represented as passing D checks.

## Five proof classes at D scope

Contract: snapshot membership, closed references, compatible READ binding,
input/selector derivation, ambiguity/version/owner changes and bounded details.
Regression: completed closing collection/capability, privilege, operator,
all-mode mock PTY and privacy groups above passed. Fresh completed approval,
History, secret-reference and inspection-specific Guide proof is recorded below.
Vertical slice: actual curses/System mock uses canonical System list and status,
logs the exact `is-active -- unit0000.service` READ, verifies validated status v2,
and returns without a second inventory query or new backend session.
Inspection: private backend derivation and public bounded view inspection expose
selection/status without frontend execution authority or private arguments.
Recovery: expired/tampered/cross-session selections, detached owners, missing or
changed bindings/providers/versions, dismissed/late results and backend loss;
the execution-fence sentinel proves rejected selections do not reach handlers.

Independent second-provider runtime integration remains Increment E, and the
complete Collection Operator milestone is open. No Raspberry Pi acceptance or
maximum-page memory/performance acceptance is claimed.

## Measurements

`/tmp/igor2-d-pty-corrected/collection-inspection-measurement.json` records actual
Linux 7.2.6-1-cachyos x86_64/glibc 2.44 curses/PTY fixture timings: visible loading
0.003551 s, observed detail result 12.355853 s, Back 1.007723 s, first page
11.247236 s. The detail interval includes backend preparation, execution, result
projection, frontend rendering and fixture polling; it is not isolated handler
latency. Back likewise includes the fixture's rendering/polling wait and is not
a claimed CPU-only navigation time. No D RSS/peak-memory measurement
was taken. B's 11.261-s and C's 14.395-s first-page follow-ups remain open; C's
RSS/VmHWM evidence does not establish maximum-page or Raspberry Pi performance.

## Changed files and disposition

Production: `core/ai/collection_view.py` owns disposable bounded details state;
`core/ai/tui.py` renders/navigates it and fences correlated events;
`core/ai/core.sh` adapts opaque selections to backend-derived canonical READ
requests; `core/lib/capability.sh` resolves declared targets and rechecks selection
at the existing fence; `core/lib/capability_runtime.py` shares existing registry
admission with the metadata bridge; `core/lib/collection_runtime.py` resolves
snapshot membership and derives/freeze-checks trusted inputs;
`core/lib/module_handler.sh` reuses bounded capture for inspection.

Tests: `tests/test_collection_inspection.py`,
`tests/test_collection_inspection_pty.py`, `tests/test_ai_tui_collection_backend.py`
and `tests/test_ai_tui_collections.py`. Documentation: `README.md`,
`docs/igor2/STATUS.md`, `docs/igor2/LEGACY.md`,
`docs/igor2/OPERATOR_SURFACE.md` and this report. No unrelated changes, System
producer redesign, architecture change or mutation capability was introduced.

## Final stabilization — 2026-10-13

At resumption, all 16 scoped file hashes and the diff matched
`/tmp/igor2-d-stopped-candidate-proof.json`; recorded summary hashes matched
`/tmp/igor2-d-evidence-ledger.json`. The Owner renewed the governor externally:
847.913 s was available with authorization `Owner approved Increment D stabilization`.
No model renewal, hook bypass, new architecture or production edit was performed.
Only seven missing Guide scenarios were added to the existing inspection test,
and this report/STATUS were updated. Existing A–C and D implementation is retained.

Every new execution followed an inspected `--dry-run`, with exact `--only-group`
selections. Automatically inferred changed test files were excluded when not
required. No broad rerun, slow System BATS inventory group or new test-file split
was needed. The approval group fit the existing 240-second command ceiling;
the first four interruptions were caused by the shared total deadline.

| Gate / identity | Interrupted subprocess time | Fresh completed time | Result |
| --- | ---: | ---: | --- |
| `tests/core/test_ai_approval.bats` | 46.612 s, 24/25 identities emitted | 33.109 s | All 25 identities PASS, including `Yes after Explain calls the provider once and leaves execution to dispatcher`. |
| History `test_read_and_change_terminal_outcomes_and_read_only_inspection` | 4.286 s | 5.552 s | PASS |
| History `test_running_claim_binds_to_the_live_canonical_proposal` | 1.861 s | 7.026 s | All field subtests and primary identity PASS |
| History `test_secrets_are_redacted_and_never_retained_in_episode_or_evidence` | 1.640 s | 2.615 s | PASS |
| `tests/test_secret_refs.py::SecretReferenceTests::test_authorized_consumer_gets_private_fd_and_audit_has_no_value_or_path` | Not dispatched; no duration | File 1.198 s | PASS |
| `tests/test_secret_refs.py::SecretReferenceTests::test_symlink_and_loose_permissions_fail_closed` | Not dispatched; no duration | Same file | PASS |

The three History methods belong to
`tests/test_operational_history.py::OperationalHistoryTests`. Raw interrupted
logs show remaining-total-budget command deadlines of 46.423, 4.155, 1.712 and
1.491 s respectively. Their fresh bounded completion demonstrates no continuing
hang or product defect. Interrupted subprocesses were cancelled, not passed.

New runs, without adding overlapping passes together:

- `/tmp/igor2-d-final-lint/summary.json`: clean changed-file Ruff, one runner
  BASELINE_FIXED classification, 3.539 s. This verifies the new I001 correction;
  it does not repair or pass unrelated historical lint debt.
- `/tmp/igor2-d-guide/summary.json`: 2 PASS, 5 FAIL_NEW, one lint BASELINE_FIXED,
  66.402 s. The five failures were a new test's incorrect assumption equating the
  session action ID with the durable History operation ID. Actual canonical
  results, approval events and matching terminal History records were inspected
  before correcting the assertion; execution semantics were preserved.
- `/tmp/igor2-d-guide-corrected/summary.json`: only those five failed identities
  and changed-file lint reran; 5 PASS, one BASELINE_FIXED, 75.622 s. The two earlier
  passing negative cases return before the corrected assertion and remain valid.
- `/tmp/igor2-d-final-security/summary.json`: 41 PASS, zero failures, skips,
  timeouts, cancellations, unavailable tools or pending groups, 36.880 s.
- `/tmp/igor2-d-final-docs/summary.json`: closing scoped structure/compile/local
  documentation-reference validation; the final evidence ledger records its
  actual completion and replaces earlier structure proof.

### Inspection-specific Guide proof

Seven fresh controlled cases use `_ai_operator_invoke`, the real
`_ai_approval_prompt`, policy checks, registry preparation, snapshot derivation,
canonical execution, result publication and History. Only System observations
and the external explanation response are mocked; handler and prompt wrappers
record sentinels while delegating to their unchanged original functions.

Run executes the READ handler once and publishes valid System status v2 with a
terminal History episode requiring `guide_confirm`. Skip and Explain→Skip never
reach the handler; Explain retains the same pending request and does not approve.
Changing the allowed-tool policy during Explain rejects the subsequent Run with
canonical `approval_invalid`. Disabling the owner while pending rejects at the
snapshot fence with `collection_expired` evidence. An initially denied policy
and a forged nonmember reference never reach the approval prompt or target
handler. Rejected identity text does not enter emitted output.

The assertions preserve the existing distinct identities: approval events retain
one session action ID; the correlated view request receives a canonical durable
operation ID whose History episode has the same target/version/scoped object.
The frontend creates no target arguments or additional execution authority.
All normal/rejected request contexts are removed in these cases.

### Final qualifying ledger and proof validity

`/tmp/igor2-d-final-evidence-ledger.json` records **244 unique PASS identities/check
groups, 1 selected-lint BASELINE_FIXED classification, 1 permitted ENV_SKIP,
0 unresolved failing/timed-out/cancelled/unverified required D identities**.
It retains exact per-identity provenance and all historical failed attempts.
The historical 220 includes partial approval/History observations; these are
replaced by completed fresh groups, never treated as completed timeout proof.

The 33 original focused D cases and completed C/contract/privilege/privacy/
lifecycle/transport scenarios from the first closing run remain unchanged.
All production bytes match the stopped candidate. The only test change appends
Guide coverage and imports existing helpers; it does not alter old test bodies,
System fixture inputs, execution or rendering. The actual curses vertical slice
is preserved as Owner-directed earlier proof, not represented as a new final
run or automatically cached security pass. Fresh Guide/System execution and
final security checks close the previously missing authority/approval/History
boundaries. No required security selection was satisfied by governor cache reuse.

The selected-lint BASELINE_FIXED classification is not a full-tree baseline fix.
Accepted B's three reviewed baseline failures (History Ruff, System namespace and
package-upgrade fixtures), its two baseline fixes, and accepted A's historical
SIM103/AI CLI/Step 18 limitations remain accurately documented in their reports.
They were not re-exercised as passing D gates. The existing LAN-IP scrub skip
(`hostname -I unavailable`) remains one skip. Maximum-page, hardware/performance
and independent second-provider proof are deferred, not waived D authority gates.

Contract, regression, vertical slice, inspection and recovery evidence above are
complete at D scope. No demonstrated D product defect remains. The complete
Collection Operator milestone remains open; Increment E has not started.

The final scoped manifest is `/tmp/igor2-d-final-candidate-proof.json`. A separate
unrelated untracked `katemark-git/` package-build directory appeared during
validation. It is preserved, excluded from the scoped commit/candidate file list,
and does not contribute Igor runtime contracts. No unrelated work was edited.
The Owner-accepted checkpoint review verified all 16 scoped file hashes and the
tracked diff against that manifest, and verified all 13 summary and 57 raw-log
hashes in the qualifying ledger. Only this acceptance record and STATUS changed
afterward; production/test content and its qualifying evidence remain unchanged.
The 244 passing observations, one BASELINE_FIXED classification, one environmental
skip, historical failures, four budget-induced timeouts and accepted baseline
limitations retain their separate meanings. The observed 12.355853-second detail
interval and measurement limitations above remain unchanged. No expensive
qualifying tests were repeated for the checkpoint.

The Owner authorized `feat(igor2): add backend-authorized collection inspection`.
Stop after this one scoped checkpoint commit; no push, merge, live service
operations or Increment E implementation. Increment E must prove an independently
registered unrelated synthetic collection/READ provider with different columns,
selectors and detail data through the accepted generic backend/TUI. Complete the
remaining RFC five-class integration/recovery evidence and declared hardware/RSS,
maximum-size and normal-navigation TTL measurements without redesigning A–D,
silently increasing provisional limits or adding mutation actions.
