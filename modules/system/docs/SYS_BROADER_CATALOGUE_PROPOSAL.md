# System S8 — Broader System Catalogue Discovery Proposal

Status: **S8 is complete for the Igor 2 System release scope on
`feature/sys-broader-catalogue`. S8.1 host runtime telemetry is implemented
and green; the additional catalogue phases below are explicitly deferred as
post-release growth, consistent with the System scope rule requiring
representative high-quality domains rather than exhaustive Linux coverage. No
new S8 mutation authority is accepted by this document.**

Base: completed S7 stack at `feature/sys-network-wifi`

## Approved swap-health increment — 2026-10-15

- **Historical checkpoint:** original implementation/STABILIZATION budget exhaustion;
  superseded by the focused acceptance record below. Owner approved the bounded READ-only continuation
  after the local System assessment; no broader S8 catalogue is reopened.
- **Objective:** one System swap evaluator shared by `host.swap.health` over
  existing `host.runtime` facts and the current `system.host.runtime.status`
  READ. Retire the superseded Diagnose/hardware-check swap probes, including the
  separately discovered phased Diagnose consumer.
- **Candidate:** clean `igor2` at `5efca3db`; scoped working diff. Core collection,
  model, approval, privilege, History and frontend mechanisms remain authoritative.
- **Reach:** System manifest/host contract, handlers, packaged knowledge, Core phased
  Diagnose projection (no thresholds/collector), Python
  evaluator tests, runtime BATS and the existing real CLI/curses workflow test;
  STATUS/LEGACY and module documentation. No configuration/secrets/storage writes.
- **Contract:** WARN at 60%, FAIL at 85%, compared with integer byte counters;
  zero total is SKIP, unavailable/stale/malformed evidence is UNKNOWN. Model
  freshness is owned by Core. Current READ output has its own timestamp and
  `current_read` scope and never updates an older model/check snapshot.
- **Version/data:** runtime capability 3/output schema 2, package 2.12.0. Update
  live pins/fixtures together; retained v2 History is not reinterpreted or rewritten.
  No persistent layout migration; process observations rebuild after restart.
- **Acceptance/proof:** threshold and invalid-fact unit cases (contract); existing
  model, health, module/capability and runtime neighbors (regression); actual CLI
  and curses/PTY runtime READ with History identity (vertical); model/check used
  facts, provenance and operator result (inspection); disabled/stale refusal and
  fresh-process re-enable recovery (recovery). No host mutation or secret input.
- **Validation plan:** governed focused selection, dry-run first, up to 300 seconds
  from the existing 353.542-second allowance, command ceiling 120 seconds, preserving
  at least 50 seconds closing/correction reserve. Prior actual operator workflow:
  27.468 seconds; runtime/health BATS estimate 60–100 seconds; unit/contract/model
  neighbors estimate 15 seconds. Automatic affected mapping spans 39 groups and
  unrelated network/storage/administration domains: use explicitly scoped affected
  neighbors, not a broad release sweep. No renewal or E/Pi/resource validation.
- **Evidence:** initial `/tmp/igor-swap-preflight/summary.json`: 23 evaluator
  scenarios pass; integration Bash syntax error and two new Ruff findings were
  inspected and corrected. `/tmp/igor-swap-corrected/summary.json`: contract,
  Ruff and corrected syntax pass; raw BATS tests 1–10 pass. This includes current
  READ/model independence with History identity, missing/stale fact evidence and
  one swap finding in both Diagnose and Healing without legacy `free` calls.
  First-run syntax/structure proof for unchanged files is retained.
- **Failure classification:** runtime BATS timeout at 120.164 seconds is a
  validation-workload/partition failure, not a demonstrated product failure.
  The governor sets remaining allowance to **0** after that timeout; do not
  reconstruct allowance from elapsed time. BATS test 8 reports an impossible
  8922670-ms duration inside the 120-second file run; do not use that per-test
  timing for planning. Raw logs are retained. Seventeen ShellCheck diagnostics
  concern unchanged phased-Diagnose lines (10 SC2154, 7 SC2155); independent
  accepted-source comparison is prepared but undispatched. Raw lint remains FAIL.
- **Remaining gates:** the last two BATS scenarios (phased Diagnose delegation/
  disablement and stale-proposal refusal/fresh-session recovery), independent
  lint-baseline test, final evaluator suite, connected model/health/capability/
  module regressions, actual CLI/curses runtime READ/History/re-enable workflow,
  and closing documentation structure. Existing accepted generic operator
  evidence does not prove this new runtime output. No all-green claim.
- **Review:** author self-review only. Independent reviewer designation remains
  with Owner; no delegation authorized. Hash-bound raw reports/source snapshot:
  `.igor-governor/evidence/system-swap-20261015/index.json` at repository root.
- **Exit/handoff:** stop development/testing at the exhausted governor. After
  Owner-terminal authorization, partition the two pending BATS scenarios into a
  bounded file with the same fixture; preserve the first ten passed scenarios
  instead of repeating them merely to finish a file. Complete only the remaining
  affected proof, then freeze for review. No commit/push authorized. Step 20C
  stays open; Increment E stays deferred/unaccepted.
- **Next functional dependency (not started):** Step 19 Boundary 3's reversible
  Nextcloud `loglevel` workflow after its ownership/attachment, exact configuration
  locator and target-admission prerequisites. Existing System memory configuration
  and metadata-only attachment are foundations, not proof of application apply,
  native readback, competing-writer cutover or recovery. See
  [the roadmap](../../../docs/igor2/ROADMAP.md#step-19--representative-application-workflow--relationships-and-deployment-ownership).

## Swap-health validation continuation — prepared 2026-10-16

**Historical preparation checkpoint (before Owner activation).** Owner authorized test partitioning
and an exact execution plan, with no test execution, production edits, governor
changes or budget request. The ledger remains at zero. This plan supersedes the
earlier whole-Python-file activation command and 120-second BATS-file schedule.
Step 19, Step 20C and Collection Increment E remain outside this continuation.

All seven selections below were checked with the runner's `--dry-run`: every
selected group ID resolved, all reports were `planned` with zero executed groups,
and the budget file hash stayed unchanged at zero seconds. This proves selection,
not runtime behavior. The preparation record retains those plans and hashes.

### Retained evidence and partition

All 14 candidate source hashes and 17 raw report/log hashes matched the retained
index before preparation. The original index and raw reports are unchanged:
`.igor-governor/evidence/system-swap-20261015/index.json`. The new preparation
record alongside it preserves scenario/fixture hashes and the move mapping.

| Existing proof | Disposition |
|---|---|
| 23 evaluator cases: exact 60/85% boundaries, shared READ/check interpretation, no swap, unavailable/stale/missing/malformed facts, timestamp consistency | Retain the original 23-pass log. The only subsequent evaluator edit was the equivalent standard-library `timezone.utc` → `UTC` import/alias; no interpretation or assertion changed. Added lint-test imports do not invalidate those cases. No whole-file rerun. |
| Corrected System contract, Ruff and module syntax; unchanged phased/hardware syntax | Retain passes. No production file changed during preparation. |
| Runtime BATS 1–7: declarations, typed facts/result, normalized reads, malformed output rejection, READ isolation and inactive owner | Retain individual passing TAP records. |
| Runtime BATS 8–10: authoritative provenance/History with unchanged model snapshot; missing/stale input; one Diagnose/Healing swap finding and no legacy swap probes | Retain individual passing TAP records. |
| Full runtime BATS file | Still TIMEOUT/incomplete, never promoted to a cached PASS. Ignore the impossible test-8 duration; use governed file elapsed time. |
| ShellCheck | Raw FAIL retained: 17 phased-Diagnose warnings on unchanged lines. The independent baseline comparison is pending; lint is not claimed clean. |

Tests 11 and 12 were moved, without changing either body or the original
setup/teardown, into two independently executable one-test files:

- `tests/modules/test_system_swap_diagnose.bats`: phased Diagnose classification
  and disabled-provider exclusion.
- `tests/modules/test_system_swap_lifecycle.bats`: refusal of an old proposal
  after disablement, no forbidden handler, and fresh-process re-enable recovery.

`test_system_runtime_read_model.bats` retains test definitions 1–10 byte-for-byte,
including their shared fixture; only separator blank lines at new EOFs were
trimmed. Static body/header comparison confirms the split; the new
files have **not** been executed. Only their lint/syntax and two pending bodies
need new execution. Scenario evidence retention is explicit; the governor's
whole-tree fingerprint cache is not overridden or represented as a partial pass.

### Mandatory remaining gates and time estimate

| Stage | Selection | Estimated wall time | Subprocess ceiling |
|---|---|---:|---:|
| A — Owner activation | Only the unexecuted `test_phased_diagnose_shellcheck_findings_are_inherited` Python node | 12–20 s | 60 s |
| B — partition preflight | ShellCheck plus BATS syntax/count of the retained file and two new files | 6–12 s | 60 s |
| C — phased consumer | New one-test Diagnose BATS file | 20–35 s | 60 s |
| D — lifecycle | New one-test lifecycle BATS file | 15–30 s | 60 s |
| E — affected contract regressions | Capability runtime, module contract, System Model Python files and generic health-runner BATS | 5–15 s | 60 s per file |
| F — real operator vertical | Only the `[swap]` CLI/curses/PTY workflow node: typed READ, distinct CLI/TUI operation IDs and provider, authoritative History/navigation, refusal and re-enable recovery | 40–75 s | 90 s |
| G — closeout | Final task documentation, structure/reference validation and read-only diff/status review | 1–3 s governed | 30 s |

Estimated tests/preflight: **99–190 seconds**, approximately **110–210 seconds
including governor/process overhead**. A 300-second allowance therefore appears
sufficient, leaving roughly 90 seconds at the upper estimate for closing work or
a concrete correction. This is an estimate, not a guarantee: C/D have not been
measured independently, and F previously took 27.468 seconds for the smaller
summary workflow. No estimate uses the corrupt BATS test-8 timing. Execute
serially, inspect each report and remaining ledger allowance, and keep 20 seconds
for closing evidence. Do not launch a stage when its estimate plus that reserve
exceeds the remaining allowance. A timeout/exhaustion stops execution; no automatic
renewal or repeat of passing work.

These are mandatory for this bounded slice: A establishes that lint debt is
inherited; B checks the test-only partition; C/D close the two missing consumer/
recovery scenarios; E protects the changed declaration/output's generic model,
health and capability contracts; F proves the actual new operator result and
History; G closes documentation/evidence. The four E files were not dispatched
in the swap runs. No secret-bearing or privileged operation is added; existing
secret/approval/privilege proof is retained, with capability admission covered
fresh in E and refusal covered in D/F. No safety gate is waived.

Unrelated to this increment: full `affected`/`full` mapping, package/service/
storage/network/Wi-Fi administration regressions, configuration/secret migration,
Pi/resource benchmarks, provider/LLM calls, and new application workflows. Core
collector and generic frontend code are unchanged; do not repeat collector tests,
the already-accepted `[summary]` PTY workflow, the 23 evaluator cases or the ten
passing runtime BATS cases merely because files moved. A relevant implementation
correction invalidates only its affected scenarios; inspect before selecting them.
Owner-designated review remains separate from test execution; no delegate,
commit or push is authorized.

### Exact commands after Owner chooses to activate

From the repository root, the Owner-terminal activation command is:

```bash
bash tests/validate.sh focused --base HEAD \
  --python /home/pooo/Documents/GitHub/surlife/.venv/bin/python \
  --test tests/test_system_swap_health.py::test_phased_diagnose_shellcheck_findings_are_inherited \
  --only-group pytest:tests/test_system_swap_health.py::test_phased_diagnose_shellcheck_findings_are_inherited \
  --total-timeout 300 --command-timeout 60 \
  --new-budget "Owner authorizes bounded swap-health validation continuation"
```

`--test` adds the exact Python node to the plan; `--only-group` is essential
because focused mode also infers changed test files. It excludes those inferred
whole-file runs, including the 23 evaluator cases already passed. This invocation
both records the Owner's single 300-second allowance and spends only stage A's
actual governed elapsed time. It does **not** certify excluded BATS/operator gates.
Do not run this activation command during preparation.

After A's report is inspected, the continuation uses the **same persistent
ledger**. Each command below omits `--new-budget`; `--total-timeout 300` does not
refill the allowance. Define this argument array once in the continuation shell:

```bash
swap_validation=(focused --base HEAD
  --python /home/pooo/Documents/GitHub/surlife/.venv/bin/python
  --total-timeout 300)
```

Run B, inspect its raw warnings, then C and D separately:

```bash
bash tests/validate.sh "${swap_validation[@]}" --command-timeout 60 \
  --only-group shellcheck \
  --only-group syntax:tests/modules/test_system_runtime_read_model.bats \
  --only-group syntax:tests/modules/test_system_swap_diagnose.bats \
  --only-group syntax:tests/modules/test_system_swap_lifecycle.bats

bash tests/validate.sh "${swap_validation[@]}" --command-timeout 60 \
  --test tests/modules/test_system_swap_diagnose.bats \
  --only-group bats:tests/modules/test_system_swap_diagnose.bats

bash tests/validate.sh "${swap_validation[@]}" --command-timeout 60 \
  --test tests/modules/test_system_swap_lifecycle.bats \
  --only-group bats:tests/modules/test_system_swap_lifecycle.bats
```

B's raw ShellCheck exit can remain nonzero for the 17 existing warnings. Proceed
only after A passes and B shows no additional diagnostic; preserve and report the
raw failure rather than suppressing it or altering the baseline list. Any new
warning is a concrete gate failure requiring inspection, not blanket baseline debt.

Then run E and F as separate governed selections:

```bash
bash tests/validate.sh "${swap_validation[@]}" --command-timeout 60 \
  --test tests/test_capability_runtime.py \
  --test tests/test_module_contract.py \
  --test tests/core/test_system_model.py \
  --test tests/core/test_health_runner.bats \
  --only-group pytest:tests/test_capability_runtime.py \
  --only-group pytest:tests/test_module_contract.py \
  --only-group pytest:tests/core/test_system_model.py \
  --only-group bats:tests/core/test_health_runner.bats

bash tests/validate.sh "${swap_validation[@]}" --command-timeout 90 \
  --test 'tests/test_capability_operator_workflow.py::test_system_read_cli_and_real_tui_share_history[swap]' \
  --only-group 'pytest:tests/test_capability_operator_workflow.py::test_system_read_cli_and_real_tui_share_history[swap]'
```

After results/evidence are recorded and the final task docs are ready, run G:

```bash
bash tests/validate.sh "${swap_validation[@]}" --command-timeout 30 \
  --only-group structure
```

Each stage uses a unique default evidence directory; retain its summary/raw logs
and link them into the same scenario ledger. Inspect failures before any further
dispatch. No shell loop, automatic retry or broad fallback is intended. After
mandatory gates and final diff/status review, freeze and report for Owner review;
do not start another roadmap item or commit/push.

## Swap-health focused acceptance — 2026-10-16

- **Phase/exit:** closing STABILIZATION; all mandatory runtime proofs are satisfied.
  Run only planned documentation/structure stage G, then enter RELEASE_FREEZE
  when its retained summary is PASS. No further development, optional tests,
  commit, push or next roadmap work. Independent review remains pending.
- **Candidate:** `igor2`, base `5efca3db`, scoped uncommitted diff. Six original
  production source hashes and 17 original raw artifact hashes matched at entry.
  Ten retained BATS definitions and the two partitioned test bodies/fixtures
  matched the preparation record. The sole production correction in this
  continuation is the generic scalar-v3 TUI result branch described below.
- **Evaluator retention:** the standard-library source binds `UTC` and
  `timezone.utc` to the same singleton (`/usr/lib/python3.14/_pydatetime.py:2521`).
  The post-test import/alias edit changes neither the timestamp calculation nor
  evaluation logic. Retain the 23 original threshold/invalid-data cases; no
  duplicate evaluator or completed BATS run was scheduled. Unchanged backend
  health/model/lifecycle proof survives the later presentation-only correction.
- **Proof:** contract (retained evaluator/typed-output cases plus E), regression
  (E and affected UI neighbors), vertical (F's actual CLI and curses/PTY workflow),
  inspection (retained used-fact/time/owner checks and F's authoritative History),
  recovery (D/F disable/refuse/re-enable) are covered. There is no persistent
  layout migration; old capability-version-2 History keeps its original meaning.

| Stage/scenario | Actual result and evidence |
|---|---|
| A: independent accepted-source ShellCheck comparison | PASS, one Python node, 4.075 s subprocess; Owner activation and its overhead charged to the same 300-second ledger. |
| B: partition lint/syntax | Three syntax/count checks PASS. Raw ShellCheck FAIL retains exactly 17 inherited phased-Diagnose warnings; A proves no new diagnostic. No baseline file/rule changed. |
| C: phased Diagnose/disablement | Initial FAIL was a fixture mismatch: BATS `errexit` stopped on unchanged `_diag_emit` OK-display false status before swap assertions. Conditional invocation now mirrors the non-errexit legacy caller, preserving the phase status, canonical result and disabled-provider assertions. Only this test and affected lint/syntax reran. PASS, 5.636 s subprocess. |
| D: stale proposal and fresh-process recovery | PASS, 7.510 s. Disabled/stale proposals never invoke the handler; a fresh enabled process returns the version-3 current READ. |
| E: affected generic contracts | PASS, 67 cases across health runner, System Model, capability runtime and module contract; 5.205 s complete runner elapsed. |
| F: server restart | The original attempt was cancelled externally before a test result. Raw report remains incomplete; it is not a pass or product failure. A single targeted retry used an explicit interruption reason, without renewing the allowance. |
| F: demonstrated presentation defect | Backend READ and canonical result succeeded, but TUI rejected every version-3 result as a collection. Corrected the existing event branch to validate canonical results and match registered non-collection capability/provider/owner metadata before normal scalar presentation. Unknown/ambiguous collection metadata still fails closed. No new registry, executor, contract or resource machinery. |
| F: affected correction proof | PASS, eight focused cases: scalar-v3 result/provider/owner, generic collection projection, unknown-descriptor rejection, session fencing and managed-secret non-retention. Resource measurements and Increment E tests were excluded. Ruff retains only two warnings on unchanged lines: TUI FURB162 and test-fixture UP017; no new diagnostic. |
| F: real swap CLI/curses/History | PASS, 21.025 s subprocess. Native outer/inner PTYs show the result footer and swap fields; CLI/TUI operations are distinct and refer to capability version 3 with owner/provider System. Authoritative History navigation, refusal, clean Quit and public CLI re-enable recovery pass. |
| G: final structure/references | Final result, raw summary and exact used/remaining budget are recorded after execution in the index below. No successful runtime check is repeated for closing prose. |

Raw reports, terminal/event artifacts, candidate hashes, failure dispositions and
final budget/phase are retained in
`.igor-governor/evidence/system-swap-20261015/execution-20261016.json`. Original
implementation/preparation evidence remains intact; the original timed-out
12-test file is not rewritten into a whole-suite PASS. The C fixture correction
changes only its invocation context, not the required acceptance assertions.

Review is author self-review only so far. Once G passes, this bounded slice is
ready for Owner-designated independent review; acceptance/commit are not implied.
Known raw lint failures remain visible baseline debt, not clean lint. Broad
release suites, Pi/resource proof, configuration/secret migration and provider
calls are outside this scope. Step 19, Step 20C and Collection Increment E remain
unstarted/deferred; no additional health or application increment is proposed.

### Final snapshot correction and separate-review handoff — 2026-10-16

The author-session read-only inspection returned CHANGES REQUIRED for a concrete
TUI crash: a v3 result dereferenced an absent operator snapshot before rejection.
The Owner accepted this blocker and authorized its bounded correction. That
inspection is **not independent review** and does not satisfy that acceptance gate.

The correction normalizes absent/malformed snapshot metadata to no entries locally
in `EventState.accept`, before collection lookup and scalar matching. Unverifiable
v3 results emit “Capability descriptor unavailable; result not displayed.” without
retaining the payload. Valid scalar and collection paths, canonical validation,
provider/owner matching, result identities, execution and History are preserved.

- **Focused proof:** 20 new cases cover scalar/collection results with `None`,
  non-object snapshots, absent entries, non-list entries and malformed rows.
  Eight affected scalar/provider/owner, collection, session, privacy and bounded
  rejection cases also pass. Raw Ruff retains only the same two inherited findings.
- **Real consumer proof:** the swap-only actual CLI/curses/History workflow passes
  after this correction, including disabled refusal and re-enable recovery.
- **Evidence reuse:** only TUI source and its test changed in production/test scope.
  Preserve earlier evaluator, model, ownership, lifecycle, BATS and lint-comparison
  proof. The affected TUI and real-consumer evidence is superseded by these new
  passes; prior artifacts and the pre-correction index remain intact.
- **Validation discipline:** only selected governed groups ran under the existing
  Owner-granted 300-second allowance; no renewal. The final documentation/structure
  check, report paths, candidate hashes and exact budget are in
  `.igor-governor/evidence/system-swap-20261015/execution-20261016.json`.
- **Phase/handoff:** RELEASE_FREEZE after the recorded closing check passes. Stop
  development; no commit/push. Request one genuinely independent read-only review
  in a separate Owner-authorized session, focused on this correction and retained
  evidence validity. Do not reopen the full implementation without a concrete reason.
  Step 19 and Step 20C remain unstarted/open; Collection Increment E stays deferred.

### Snapshot ingestion-boundary correction — 2026-10-16

The separate independent review returned CHANGES REQUIRED: an open collection
followed by `operator_snapshot` with `surface.entries = null` bypassed the local
action-result guard and crashed in `result_entry`. The Owner authorized this
bounded correction, with no budget renewal, commit, push or later roadmap work.

- **Scope/authority:** existing frontend metadata admission and disposable view
  state only, under the accepted one-backend/selection contract. No backend,
  evaluator, persistent data, History, approval or capability contract changes.
- **Boundary:** `EventState.accept` checks snapshot/entries/row containers before
  storage; the same helper guards action-result routing. Optional alias and row
  metadata containers are checked where explorer/result consumers require them.
  Rejected updates retain the last good snapshot, set an explicit rejection flag,
  emit a bounded warning and revoke collection pages, detail and pending requests.
  Explorer and candidate selection and collection actions cannot use rejected
  metadata. A valid snapshot clears rejection; explicit collection refresh is
  still required to obtain selectable rows. A rejected update never counts as a
  successful explorer refresh.
- **Reproduction:** the new focused regression failed all five initial shapes,
  including the exact uncaught `TypeError` for null entries. Inspection classified
  this as a product input-validation defect, not fixture or baseline debt.
- **Acceptance/validation:** one parameterized scenario now covers seven nearby
  malformed shapes, opens/selects a real validated collection, rejects the update,
  checks retained metadata and warning, empty/nonselectable rows, blocked collection
  and explorer actions, late-result refusal and valid-snapshot/explicit-refresh
  recovery. All seven cases and 64 affected existing cases pass: bounded rendering,
  scalar/provider/owner results, malformed action-result metadata, selection,
  lifecycle, request/session fences, secret non-retention and the operator explorer
  (including canonical History panels). No resource/Increment E measurement ran.
- **Lint disposition:** the initial scoped run also exposed a new I001 import
  formatting finding despite the runner's aggregate FAIL_BASELINE label. The
  import-only correction gets an affected Ruff-only closing check; runtime proof
  remains equivalent. Inherited FURB162/UP017 remain explicit baseline debt.
- **Evidence/proof:** contract, regression and in-process consumer/recovery proof
  are refreshed here. Earlier System evaluator/model/lifecycle and CLI/curses/
  authoritative History proof remain retained for unchanged backend behavior;
  no new real-PTY integration claim. Warning/rejection state is inspectable in the
  frontend; no persistent migration applies. Exact candidates, logs, source/artifact
  hashes, closing check and allowance are recorded in
  `.igor-governor/evidence/system-swap-20261015/execution-20261016.json`, with the
  previous checkpoint preserved as `execution-20261016-before-ingestion-correction.json`.
- **Phase/handoff:** RELEASE_FREEZE once scoped lint/structure evidence is closed;
  independent correction review and Owner acceptance remain pending. Stop without
  commit/push. Step 19, Step 20C and Collection Increment E remain unchanged.

### Complete TUI snapshot admission contract — 2026-10-16

The independent review again returned CHANGES REQUIRED. The Owner authorized a
bounded correction of the shared admission contract, with remaining allowance
only, no renewal/commit/push, and unchanged Step 19, Step 20C and Collection E.

**Consumer inspection and scope.** Inspected `EventState.accept`/`apply_event`,
`operator_surface.children`/canonical prefix resolution, alias hints/navigation,
invoke/required-input/candidate/text overlays, collection result routing,
`CollectionView` construction/selection/inspection, collection key dispatch and
System/result/History panels. Only `core/ai/tui.py`, focused tests, two existing
test fixtures and this task/status evidence change. No new schema or execution
authority is introduced; backend authorization/ownership/availability stays intact.

| Consumer metadata | Admission requirement / existing parser |
|---|---|
| Snapshot and entries | Object with a list of at most 4096 object rows; supplied display state/digest/availability model are strings, entry count is a nonnegative integer, supplied sources map names to status-string/count-integer objects. |
| Aliases and prefixes | Optional object mapping root names to root names under the existing `[a-z][a-z0-9_-]*` alias grammar, checked with the explorer's alias parser before canonical prefix resolution can raise. |
| Entry identities/types | Supplied navigation/routing/display fields have their consumed string types; nullable safety/privilege/reason remain allowed. Provider-required is boolean. Canonical IDs use `operator_surface._safe_id`; paths allow the existing `@provider` disambiguation. Capability rows require path, target, provider and owner. |
| Capability inputs | Object with required-name list and property-spec objects; adapt the existing projection's omitted `additionalProperties=false` and lifted selectors to `capability_runtime._validate_schema`. Preserve its eight input types; enforce existing property-name grammar, 32-property bound, declared/unique required names. Text length bounds are nonnegative integers and supplied roots strings. |
| Selectors | Supplied lifted selectors must name declared properties. Both lifted and embedded descriptors use existing `validate_selector`, including resource kind and compatible input type. |
| Collections/outputs | Supplied outputs and collections are objects. Collection capability rows must construct successfully through `CollectionView`, which uses canonical `validate_output_schema` for nested rows, columns and READ inspection bindings; standalone output metadata uses that same validator. |

Unconsumed optional descriptor data is not made into a second full Module API
schema. Missing optional fields retain existing presentation defaults. Two old
fixtures now supply a scalar capability path and a declared integer property for
the intentional non-text/manual-input case; neither change alters its assertion.

**Failure and recovery.** Both reported examples were reproduced before the fix
through actual explorer operations: `{"system":"."}` raised uncaught
`SurfaceError` in canonical prefix resolution, and `{"type":[]}` raised uncaught
`TypeError` in input collectability. Raw reproduction evidence retains both.
Admission now rejects before snapshot replacement. Existing bounded visible
warning/rejection state, candidate/request/detail/page revocation, stale-result
refusal and valid-metadata plus explicit collection refresh recovery remain.
Backend approvals are not discarded or replaced by frontend metadata.

**Evidence ledger.** The admission-specific checkpoint is
`.igor-governor/evidence/system-swap-20261015/admission-contract-20261016/`.
It retains entry source hashes/copies and the correction diff; its `index.json`
records the final candidate, governed reports, budget and proof retention.
Reproduction: `/tmp/igor-admission-contract-reproduction` (two expected failures).
Initial correction: `/tmp/igor-admission-contract-fixed` (27 new cases pass;
two new import-format findings subsequently corrected, two inherited warnings).
Closing selection: `/tmp/igor-admission-contract-closing`, planned explicitly
from prior subsecond consumer groups plus the directly affected real swap
CLI/curses/History workflow. No resource/Increment E tests or broad sweep.
All **102 selected tests pass**: 30 new admission cases (both reported crashes,
25 malformed-container/field scenarios with actual pending-selection refusal and
refresh recovery, three valid textual input forms), 71 affected consumer cases,
and the real swap CLI/curses/History workflow. No runtime failure or skip remains.
Final scoped Ruff reports only the inherited FURB162 and UP017; no new finding.
The closing runtime run leaves 62.561 seconds of the existing allowance before
documentation checks; exact final remainder is in the admission index.

Earlier unchanged evaluator/backend/model/lifecycle/History-persistence and
shell evidence remains applicable; TUI admission/selection/result/History-panel
proof is refreshed for this correction. These are contract, focused regression,
consumer vertical-slice, rejection inspection and recovery proofs; no persistent
layout or data migration applies. Independent review and Owner acceptance remain
pending; author self-review is not independent review.
Phase: RELEASE_FREEZE after the documentation/reference/diff check. Allowed next
action is separate Owner-authorized independent review of this correction and
its evidence, then Owner acceptance; no commit/push or automatic later work.

### Final collection inspection-provider correction — 2026-10-16

- **Authority/scope:** Owner-authorized correction of the independent review's
  concrete collection Enter KeyError only. `core/ai/tui.py` restricts provider
  discovery to capability entries before indexing `provider`; the existing
  target, READ and active filters remain. No snapshot schema, ownership,
  approval, History, evaluator or backend change; no persistent migration.
- **Reproduction:** one targeted regression admits a valid services snapshot
  with the reported provider-less check, selects a real collection row and
  presses Enter through `_collection_key`. Before correction it raises the exact
  `KeyError: 'provider'`. The first system-Python attempt lacked pytest; it is
  retained as TOOL_UNAVAILABLE, followed by the actual reproduction using the
  prior evidence's Python interpreter. Neither attempt is promoted to a pass.
- **Acceptance:** the same test now passes both the provider-less check and a
  check carrying an impostor provider. Only two active READ capability providers
  appear in the chooser; disabled and CHANGE capabilities and both check forms
  are excluded. The selected reference/provider produce exactly one backend
  inspection request, no request is sent during navigation, and closing detail
  restores normal row navigation. Execution remains delegated to the backend.
- **Evidence:** nine tests pass: the new regression, existing inline/navigation
  case and seven snapshot-rejection/recovery neighbors. Scoped Ruff reports only
  inherited FURB162/UP017. Documentation structure/reference and final diff checks
  close this candidate. Plans, raw results, before/after sources, correction diff,
  full package hashes and exact remaining 300-second allowance are retained in
  `.igor-governor/evidence/system-swap-20261015/inspection-kind-20261016/index.json`.
  Prior 102-test admission/real CLI/curses/History and unchanged swap evaluator,
  lifecycle, model, backend and shell evidence are retained by applicability,
  not claimed as a new whole-candidate run. Only collection Enter provider
  discovery changed; its navigation/selection/recovery proof is refreshed here.
- **Final acceptance / closeout — 2026-10-16:** final independent delta review
  returned **APPROVE**, with no blocking defects. The Owner formally **ACCEPTED
  the complete bounded System swap-health package** and authorized one local Git
  commit. This acceptance supersedes the pending-review/acceptance handoffs above.
  All 20 `candidate_hashes` in the inspection-kind evidence index matched the
  working files before acceptance-only updates to this record and `STATUS.md`.
  The reviewed implementation/tests remain unchanged; passing evidence is reused.
  Phase: RELEASE_FREEZE; only scoped staging, staged inspection, local commit and
  commit/status verification remain, then COMPLETE and stop. No push, test reruns,
  further reviews, budget renewal or automatic next task. Step 19, Step 20C and
  Collection Increment E remain unchanged.

## Goal

Broaden the existing `:sys` surface into a strong everyday host catalogue
without turning System into a collection of shell-command wrappers.

S8 covers the roadmap areas that remain thin after S1–S7:

- host runtime telemetry and structured health;
- hardware/platform inspection;
- boot and time inspection;
- security posture;
- richer package/log/health inspection;
- only those additional mutations that later earn a narrow reviewed contract.

The existing System package, Module API v2 registry, System Model, Observation
Framework, Capability runtime, D070 selectors and current approval/privilege
path remain authoritative.

## Discovery evidence

### 1. S8 is extension work, not a new module or registry

D020 already places reusable Linux mechanisms in Core/Platform and host-domain
meaning in `system`. S1–S7 established one generated operator namespace,
one semantic-candidate boundary and one capability runtime.

**Recommendation:** keep one `system` owner and one canonical capability
catalogue. Do not add a hardware/security submodule or another inventory
database merely to organize S8.

### 2. The repository already has partial catalogue coverage

The current typed System surface already includes:

- `system.host.summary` and authoritative memory observation/health;
- package update/cleanup inspection and reviewed package mutations;
- service list/status plus reviewed service mutations;
- `system.logs.summary`;
- storage, account/path and network/Wi-Fi surfaces from S4–S7.

S8 should extend those contracts rather than duplicate them.

### 3. Legacy System health/context still contains direct probes

The v1-compatible System hooks still directly read or derive:

- CPU/thermal-zone temperature;
- Raspberry Pi throttle/undervoltage state;
- root filesystem usage;
- swap usage;
- load averages;
- machine model, OS, kernel, architecture and uptime;
- recent I/O-error text.

Host Intelligence already classifies temperature/load/swap and duplicate
CPU/storage probes as **ADAPT to observers/checks** after the memory slice.

**Recommendation:** S8 should close this duplicate-probe debt before adding a
large set of new state-changing commands.

### 4. Current facts and health meaning remain separate

A current load average, swap counter, clock state or security-provider state is
observation. Whether that state is healthy is System-owned interpretation.

**Recommendation:** Core owns bounded normalization; System observers publish
typed facts; System checks interpret only established thresholds. A READ
capability may present normalized current state without turning every value
into a durable System Model object.

Do not infer health from command exit alone, missing providers or stale facts.

### 5. Do not invent durable hardware-component identity yet

S8 does not currently need to select or mutate individual CPUs, PCI devices,
USB devices, thermal zones or firmware records. Serial numbers, board UUIDs,
disk serials and similar hardware identifiers also create unnecessary
fingerprinting exposure.

**Recommendation:** initial hardware/runtime work attaches bounded facts to
`host:local` or returns current READ results. Add component object kinds only
when a real selector, relationship or mutation requires stable identity.

### 6. Thermal state needs provider semantics

The existing fallback assumes `thermal_zone0` is CPU temperature. That is
not a portable semantic guarantee. `vcgencmd` is Raspberry-Pi-specific.

**Recommendation:** do not label an arbitrary Linux thermal zone as CPU truth.
A later hardware slice may use reviewed provider mappings and explicit
source/provenance. Missing provider data is `unknown`/unavailable, not 0°C
and not healthy.

### 7. Security posture should be optional-provider READ first

AppArmor, SELinux, nftables/firewalld/ufw and other controls vary by distro and
installation. Absence of one tool does not imply an insecure host and must not
deactivate System.

**Recommendation:** canonical System security concepts may have optional
provider adapters. Report provider state precisely; do not dump rules, change
policy or synthesize a universal security score in the first slice.

### 8. Richer logs need a data-exposure boundary

The current `system.logs.summary` deliberately returns bounded metadata and
does not persist raw journal messages into Operational History. Raw logs may
contain tokens, paths, usernames, request data or application secrets.

**Recommendation:** S8 may enrich counts, priorities, units and bounded
metadata first. Raw-message retrieval must remain a separate reviewed question;
it must not become an accidental AI/context/History secret channel.

### 9. Reboot, power, clock and security mutation are not implied

The legacy `sysreboot` affordance and the existence of tools such as
`timedatectl`, `bootctl` or firewall managers do not establish a canonical
Capability contract.

**Recommendation:** S8 begins READ-first. Reboot/shutdown, timezone/NTP,
boot-target, firewall and MAC/security-policy changes require explicit later
decisions, exact Core adapters, recovery semantics and deterministic
verification. Remote-session loss risk must remain visible.

## Recommended phases

| Phase | Outcome |
|---|---|
| S8.0 | Discovery, Q019–Q021, proof gate |
| S8.1 | Host runtime telemetry READ substrate: normalized uptime/load/swap; typed host observation/status; no new mutation |
| S8.2 | Hardware/platform READ catalogue: bounded non-identifying hardware summary and reviewed optional thermal provider semantics |
| S8.3 | Boot & time READ catalogue: canonical status with optional provider-specific evidence |
| S8.4 | Security posture READ catalogue: optional AppArmor/SELinux/firewall-provider state without policy mutation |
| S8.5 | Richer packages/logs/health: structured metadata, health cutover from duplicate v1 probes, no unreviewed raw-log channel |
| S8.6 | Selectively verified mutations only where an accepted decision and real operator need justify them |
| S8.7 | Debian/Arch/provider fixtures, detachability proof, docs and stacked affected gate |

S8 remains intentionally iterative. Igor 2 does not need an exhaustive clone
of Linux administration commands.

## Proposed S8.1 boundary

The first implementation slice should be **host runtime telemetry READ only**.

Core should provide one bounded Linux runtime query for data that is common on
the supported Debian/Arch families:

- uptime seconds;
- 1/5/15-minute load averages;
- swap total/free/used bytes and use percentage.

The first slice should not parse human-oriented `uptime` or `free` output
when stable procfs values exist.

System may publish these as fresh `host:local` observed facts and expose a
small canonical READ capability such as `system.host.runtime.status`.
Exact property names and schema must be fixed during S8.1 implementation after
checking existing Host Intelligence conventions.

S8.1 explicitly excludes thermal semantics, raw logs and all mutation. It is
designed to be portable, deterministic and independent of optional desktop or
network managers.

## Provider and failure rules

- contribution-local requirements only;
- an optional provider failure disables only its leaf/contribution;
- bounded byte/row/text limits and timeouts;
- malformed or ambiguous input fails closed;
- missing state is explicit `unknown`/unavailable;
- no AI-dependent sensing or validation;
- no frontend-specific host authority;
- no secret-bearing values in candidate data, facts, History or provider
  diagnostics;
- Debian/Arch support is claimed only where fixtures prove equivalent semantics.

## Proof requirements

### Contract proof

- no second module, registry, inventory or execution path;
- typed bounded schemas;
- initial S8.1 facts remain on canonical `host:local`;
- optional-provider absence is localized;
- no serial/UUID/raw-log/credential leakage.

### Regression proof

- preserve S1–S7 System surfaces;
- preserve module detachability;
- preserve System Model/Observation semantics;
- preserve capability approval/privilege/History;
- preserve Debian/Arch support claims only where exercised.

### Vertical proof

For S8.1:

1. normalize procfs runtime fixtures;
2. publish or present canonical bounded host runtime data;
3. inspect it through the generated `:sys` surface;
4. prove malformed/oversized procfs data fails closed;
5. prove no sudo, mutation, AI or optional provider is required;
6. prove System disabled/inactive state contributes no active behavior.

### Migration/recovery proof

S8.1 introduces no persistent backend, no object-ID migration and no
state-changing capability. Legacy direct probes remain compatibility only until
their structured replacement has equivalent proof; do not double-count one
health signal after cutover.

## Open decisions

The authoritative open questions are recorded in
`docs/igor2/DECISIONS.md`.

- Q019 — should initial S8 hardware/runtime state remain `host:local` facts and
  bounded current reads until a real need proves component identities?
  Recommendation: **yes**.
- Q020 — should richer log work keep raw journal messages outside typed
  capability/History/AI output by default until a dedicated sensitive-log
  contract exists? Recommendation: **yes**.
- Q021 — should reboot/power, time, boot and security-policy mutation remain
  deferred until each has an explicit reviewed capability/recovery decision?
  Recommendation: **yes**.

None of Q019–Q021 blocks the proposed read-only S8.1 telemetry slice if the
Project Owner accepts the recommendations.


## Igor 2 release-scope closure

The Project Owner directed the System sequence forward to S9/S10 after the
green S8.1 gate. Under the release standard in `SYS_OPERATOR_PROPOSAL.md`,
S8 does not need to clone every Linux administration domain before Igor 2 can
ship.

The completed S8 release slice is:

- bounded Core procfs normalization for uptime, load and swap;
- typed `host.runtime` observation on canonical `host:local`;
- `system.host.runtime.status` as a privilege-free READ capability;
- deterministic malformed/oversized-input failure;
- focused and affected stacked validation.

S8.2–S8.7 remain useful future catalogue work, not hidden completion claims.
Hardware component identity, thermal provider semantics, boot/time catalogues,
security-provider posture, raw-log exposure and additional S8 mutations remain
deferred under Q019–Q021 and their existing authority boundaries.

This closure introduces no persistence migration and no new execution authority.
