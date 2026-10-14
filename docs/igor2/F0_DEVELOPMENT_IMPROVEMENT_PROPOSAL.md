# F0 — development improvement proposal

Status: **F0.1 ACCEPTED by Owner — RELEASE_FREEZE for local commit**, 2026-10-14.
The Owner authorized this small documentation-first slice after deferring
Increment E verification. Closing evidence and the independent review are
recorded below; the runtime pilot remains unverified. F0 is development discipline,
not product Wave F. Increment E remains STABILIZATION/unaccepted, with its
budget, Pi verification, 30-second TTL and memory limits unchanged. Only the local
F0.1 commit is authorized; no push.

## Problem and recommendation

Increment E has passing contract/security and real-consumer evidence alongside
inconclusive resource bounds, a missing Pi target and a provisional lease that
normal measured navigation exhausts. Mechanism checks were useful but could not
close workload acceptance. Historical reports and repeated policy text also make
it costly to recover the current candidate, unresolved gates and next safe action.

Recommend a **documentation-first pilot using existing infrastructure**:
[architecture authority/read order](README.md), accepted decisions,
[EXECUTION proof classes](EXECUTION.md), [.codex lifecycle](../../.codex/README.md)
and `tests/validate.sh`. No new agent platform, registry, dashboard, dependency
or development-state daemon. Keep [D078](DEVELOPMENT_POLICY.md), safety, ownership,
privacy, platform contracts, root accountability and explicit Owner approvals.

## Working agreement — F0.1 scope confirmed by Owner

| Area | Smallest practical improvement | Acceptance of the pilot |
|---|---|---|
| Architectural context and continuity | One concise task/handoff section: objective, phase, allowed next action, accepted decision links, affected consumers/data, candidate, complete/unverified proof and invalidating changes. Keep current facts at the top; link historical evidence rather than reread every chronology. | A fresh reviewer can identify the authority, candidate, unresolved decisions and next permitted action from that section and links; no silent third design. |
| Smaller vertical increments | Before implementation, state one observable user path and its negative/recovery cases, exclusions, five proof classes, required environment and estimated validation durations. Separate mechanism calibration from maximum workload acceptance. | Each increment has executable exit scenarios and a feasible governed plan; missing hardware/decisions are detected in DISCOVERY. |
| Reliable resource measurements | Specify metric, baseline, units, scope, uncertainty, transient/overlap coverage, overhead and target hardware. Calibrate with known workloads before expensive canonical cases. Define a stop rule for inconclusive instruments. | Known transients/concurrency are bounded correctly; canonical workload results remain distinct from calibration, sampled RSS and different kernel metrics. |
| Regression and integration | Map changed contracts to focused tests and a real canonical consumer. Preserve approval, privilege, secrets, History and recovery proof; use affected validation and exact-node groups. Reuse unchanged evidence and classify failures before corrections/reruns. | The final candidate has explicit applicable pass/fail/skip/unverified evidence; no broad rerun loop, obsolete-contract assertions or prose-only closure. |
| Independent code review | Owner-designated human or separate review session reads connected callers, state/data boundaries and raw acceptance evidence. Record findings and disposition independently of the author's summary. | A reviewer can trace a real success, refusal and recovery path; unresolved material findings block acceptance. Single-agent defaults remain; delegates require explicit authorization. |
| AI model/context efficiency | Keep root model/effort with the Owner. Use the least costly capable choice for bounded lookup/mechanical validation; escalate only for concrete authorization/migration/debugging uncertainty. Carry a compact handoff across compaction and do not duplicate passing work on a stronger model. | Scope, context inputs, escalation reason and validation reuse are recorded; no automatic root override, duplicate implementation or unauthorized agents. |
| Evidence-based completion | One current matrix binds proof to candidate/environment/raw logs, classifications and invalidation. Distinguish ready technical evidence from pending Owner acceptance; freeze when gates pass. | No completion with a missing gate; concrete failures trigger only the smallest affected correction, and acceptance/commit authorization is explicit. |

The handoff is engineering context, never Igor operational state or execution
authority. Mandatory authorization and stopping rules remain explicit in agent
instructions; a compact context is not permission to replace them with opaque
links. Resolve duplicated wording only after policy-consistency review, preserving
the authority order and all hard gates. `.codex/config.toml` currently selects no
root model and disables delegation; neither changes in this proposal.

## Bounded slices

**F0.1 — task records and examples (authorized).** Add the missing compact
task/specification/handoff template to existing lifecycle/execution documentation,
with a worked example, budget planning and calibration stop rules. Review changed
links/policy and parse TOML. No runtime suite for a documentation-only change.

**F0.2 — one real pilot.** On the next separately authorized small engineering
task, demonstrate DISCOVERY → implementation → focused/affected validation →
independent review → freeze/acceptance. Record validation wall time, repeated/
invalidated checks, unverified gates and reviewer findings. Use existing governed
reports and task documentation; evaluate whether the agreement improved closure
before adding automation. This does not retroactively close Increment E or start
later product work.

## Options and Owner decision

| Option | Consequences |
|---|---|
| Documentation/templates plus one pilot — recommended | Lowest implementation and maintenance cost; reuse enforcement already in the governor, with reviewable human/model obligations. |
| New automated completion/orchestration service | Larger scope and a second source of development state; only justified later by repeated pilot failures that existing reports/runner cannot address. Not proposed for initial F0. |

The Owner confirmed F0.1 documentation scope. F0.2's concrete engineering task,
independent-review identity and execution allowance remain separate decisions.
No resource acceptance criteria, product architecture, root model choice or
delegation policy is revised by this working agreement.

## F0.1 increment record

- **Objective:** a future session can recover architectural context, requirements,
  evidence and the next permitted action from one current summary and linked record.
- **Authority:** Owner's F0.1 instruction; [D078](DEVELOPMENT_POLICY.md),
  [authority order](README.md#document-lifecycle-and-authority),
  [lifecycle](../../.codex/README.md#task-lifecycle) and
  [five proof classes](EXECUTION.md#completion-model). No architecture revision.
- **Candidate/scope:** `igor2`, base `d729449f2bb26ac97791418a402956ff7e7740f0`;
  this document, `EXECUTION.md`, `STATUS.md` and `.codex/README.md` only.
  Retain the dirty E implementation/tests/report and private evidence archive.
  Task-entry hashes and F0-only before/after snapshots distinguish this slice
  from existing uncommitted work. No callers, fixtures, configuration or data migrate.
- **Budget:** governed documentation structure check, initially estimated about
  7.2 seconds from retained E documentation evidence; actual initial check 6.741 s.
  Affected final handoff-content check estimated another 7.2 s, command cap 10 s;
  both fit the existing 20.550-second entry allowance, without renewal.
  Policy/link/TOML/diff inspection
  is bounded to these documents. Serial, local files only; no service, Pi, network,
  privileged operation, tracing or resource workload. Stop on exhaustion;
  any remaining allowance is not permission for further process work or E tests.
- **Review:** the separately authorized independent review returned **APPROVE
  WITH MINOR CORRECTIONS**, with no architectural blocker. STATUS now points to
  `handoff.json` (0 seconds remaining) and prohibits reconstructing allowance
  from test durations and configured ceilings. Scoped documentation/diff inspection
  closes this correction; the retained archive describes the pre-correction candidate.
  No delegation is enabled. Independent implementation
  review is required for the later runtime pilot, before its acceptance.

| Requirement | F0.1 acceptance check |
|---|---|
| Persistent architectural context | Lifecycle points to current STATUS and one task record with accepted authority links; no copied architecture or chat-only decision. |
| Requirements before implementation | Record includes observable success/refusal/recovery, affected consumers and decisions before edits. |
| Small verifiable slices | One outcome and exclusions; worked example stops if proof already exists or required scope/budget is unavailable. |
| Proportionate testing | Explicit selection, historical duration, allowance versus estimate, resource scope, closing reserve and calibration/exhaustion stop rules. |
| Independent review | Reviewer checks candidate, connected behavior and raw evidence; author self-review cannot satisfy independence; pending review is visible. |
| Status and handoff | Current summary contains phase, next permitted action, exit evidence, deferred E pointer and remaining Owner decisions. |

Proof applicability: contract proof is the policy/template consistency inspection;
inspection proof is the discoverable current summary and worked task record.
Runtime regression and runtime vertical-slice proof are **not applicable** because
no runtime changes; the worked example is documentation, not executed behavior.
Migration/recovery is **not applicable** because no runtime data/contract migrates;
E source/evidence preservation is checked separately. These checks close only
the documentation slice, never a product wave or the F0.2 effectiveness pilot.

Closing evidence is retained with the F0-only diff, candidate hashes and entry
snapshot under `.igor-governor/evidence/f0-1-20261014/`; it must state actual
results, limitations and remaining budget. Do not restore budget state from it.
Initial governed structure PASS (6.741 s); added local destinations/anchors and
TOML/policy consistency PASS; task-entry comparison confirms E sources/tests/report
unchanged. Final handoff-content validation is retained in that archive alongside
the initial run. Root diff/policy review is self-review, not independent proof.
The dry-run output directory initially collided with the execution destination;
no check ran in that attempt. A distinct evidence directory resolved it without
changing implementation, allowances or test expectations.

Owner acceptance (2026-10-14): F0.1 — Development Process Foundations is
**ACCEPTED** after the independent **APPROVE WITH MINOR CORRECTIONS** verdict
and verified allowance-reference correction. Documentation/reference and diff
checks passed; no runtime tests or budget renewal. Prior evidence remains intact.

Handoff: RELEASE_FREEZE; only staged-diff inspection, authorized local F0.1 commit
and commit verification remain. No push. F0.2 stays DISCOVERY
until its task, reviewer and budget are settled; do not start it automatically.

## Worked next-increment example — planning only

**Candidate F0.2 pilot:** one bounded regression of an existing registered READ
capability when its provider is disabled. This demonstrates using the record;
it does not assert a coverage gap or authorize changes. Inspect existing tests
first. If they already prove the invariant, retain that evidence and choose a
genuine small task with the Owner rather than writing a duplicate test.

| Record field | Example before implementation |
|---|---|
| Outcome/authority | Deterministic disabled-provider refusal under existing activation/capability contracts; no new API. Read [module lifecycle](../module_lifecycle.md) and [Module API](MODULE_API.md), then obtain the separate task authorization. |
| Scope | One capability and its current consumer/test fixture; inspect `tests/test_capability_runtime.py` and connected resolver/dispatcher. No production fix unless an actual contract failure is demonstrated; otherwise test-only if missing proof. No collection runtime, features or real host changes. |
| Success/refusal/recovery | Enabled fixture reaches the expected READ handler; disabled fixture is unavailable and handler sentinel proves zero execution; explicitly re-enabled fixture in a new process is available again. Existing approval/privacy/History behavior remains covered by applicable affected checks. |
| Five proof classes | Contract: deterministic availability/refusal. Regression: affected capability/activation and required-fresh safety tests. Vertical slice: real canonical consumer with isolated provider. Inspection: unavailable reason/provider identity. Migration/recovery: no retained-data migration; new-process activation recovery verified. |
| Candidate/environment | Actual branch/base plus scoped source hashes at task entry; Linux/test-tool versions, isolated private state and fixture activation recorded. Existing E dirty work preserved and excluded from task ownership. |
| Validation/budget | Dry-run exact focused nodes, then affected selection once. Use historical durations to choose partitions and reserve closing time. Illustrative request: 120 seconds validation, command cap 60 seconds, one serial fixture process tree, no network/sudo/live services; confirm fixture RAM/temp-disk needs during DISCOVERY. These are unapproved planning figures, not renewed governor allowance or measured resource ceilings. If required coverage does not fit, split or stop before dispatch. |
| Evidence/review | Raw summaries/logs/sentinel observations tied to candidate/environment; explicit unexecuted gates. Owner designates independent human or separate review session to inspect call path and evidence; unresolved material findings prevent acceptance. |
| Handoff/stop | Missing coverage established and scope/reviewer/budget settled before IMPLEMENTATION. If coverage exists, stop this candidate. On failure inspect/classify first; on exhausted allowance stop. Once required proof passes, freeze; await explicit acceptance/commit and do not start another slice. |

For a later resource-sensitive task, fill the same record's metric, baseline,
hardware, uncertainty and calibration fields before any expensive workload.
This example makes no memory or Pi claim and does not resume Increment E.

## F0.2 READ lifecycle pilot record

- **Authority/scope:** Owner authorized the final F0 engineering pilot on
  2026-10-15 under existing module activation, capability dispatch, ownership
  and approval contracts. F0.1 is ACCEPTED, locally committed and verified at
  `5aa8bdd0e2042d8b7833f4b4a180ad1ccfa12c65`. No new architecture or further F0
  increment; no F0.2 commit or push is authorized.
- **Candidate:** `igor2` at that commit, with one new
  `tests/modules/test_read_capability_lifecycle.bats` regression plus this record
  and the STATUS pointer. Dirty Increment E work is preserved and excluded from
  ownership; entry contents/hashes are retained in `/tmp/igor-f02-entry.json`.
- **Discovery:** existing `test_step18_module_composition.bats` proves typed READ
  dispatch/History and disabled-owner preparation refusal separately;
  `test_module_state.bats` proves owner filtering, and `test_module_v2.bats`
  proves registration recovery. These do not prove the complete same-operation
  dispatch lifecycle or stale-proposal refusal. Source inspection is reused as
  coverage analysis, not claimed as passing execution evidence.
- **Acceptance:** an isolated v2 fixture's READ succeeds through `ai_execute_tool`;
  disabling its owner refuses both that request and an already-prepared proposal
  without another handler call. A fresh disabled process neither sources the
  provider nor registers it. Re-enable plus a fresh process restores one active,
  correctly owned contribution and a second successful READ. History retains two
  success records with no approval or privilege escalation. Production services,
  configuration and runtime implementation are unchanged.
- **Proof:** contract/regression/vertical slice are the single canonical-dispatch
  regression; inspection is the filtered contribution registry and History.
  Migration is not applicable because no retained-data format changes; recovery
  is the explicit new-process re-enable scenario. The Owner-executed regression
  passed all of these assertions; no production behavior or E gate is accepted by it.
- **Validation plan:** four exact focused groups in the retained dry-run
  `/tmp/igor-f02-plan-20261015/summary.json`: structure, shellcheck,
  `syntax:tests/modules/test_read_capability_lifecycle.bats` and
  `bats:tests/modules/test_read_capability_lifecycle.bats`. The runner's structural
  and shell checks also see existing dirty paths; no E runtime test is selected.
  Planning estimate: 60 seconds, not a measurement; one serial temporary fixture,
  no network, sudo, live service, Pi or performance workload. Command cap 120 s,
  below the existing 240-s ceiling; Owner maximum 300 s cumulative execution.
  Stop on sufficient proof, exhaustion or a concrete failure requiring inspection.
- **Execution evidence:** Owner activated the supported 300-s budget and executed
  the exact focused selection. `/tmp/igor-f02-validation-20261015/summary.json`
  reports complete, exit 0, four PASS, zero failures/timeouts/skips/errors, fresh
  execution (`reused=false`). Raw TAP confirms the single lifecycle test passed
  in 24.179 s; its BATS group took 24.497 s. Total runner wall time: **30.002 s**
  against the 60-s planning estimate. Structural, ShellCheck and BATS-count checks
  also passed. Excluded groups remain unverified and outside this test-only pilot.
  No successful check was repeated.
- **Evidence retention/budget:** raw summary/logs, the test snapshot and entry
  record are retained under `.igor-governor/evidence/f0-2-20261015/`, with SHA-256
  hashes in `index.json`. Summary hash:
  `8d3cfe956b38cfb9c28475a69d5f9a7337310662f53f4accb0f08bfb721203f8`;
  test hash: `9cc92c7d28b886915da3bc7ed03a549f583476f5b872f9b09490fa7a14f26af0`.
  Unrelated dirty source/evidence hashes match task entry. Ledger inspection records
  269.9968952399995 s remaining; this is not reconstructed from durations and is
  not authorization for more work, E verification or another process increment.
- **Workflow evaluation:** current summary/authority links recovered the scope,
  contracts and deferred E boundary; this continuing session is not an independent
  fresh-session experiment, and no context-recovery time was measured. Acceptance
  criteria were clear. Existing fixtures/patterns and coverage analysis were reused;
  a duplicate F0.1 commit, runtime fix, broad suite and resource measurements were
  avoided. The one planned execution supplied sufficient proof without a correction
  or rerun. No missing architecture or product defect was identified. Owner-terminal
  activation introduced a handoff, now resolved through the supported mechanism.
  The workflow proved practical for this bounded pilot; no general efficiency gain
  or independent fresh-session result is claimed.
- **Independent review / Owner acceptance (2026-10-15):** a separate review
  returned **APPROVE** after tracing canonical dispatch, current owner availability,
  the matching-digest stale proposal, handler nonexecution sentinels, approval,
  privilege and authoritative History. All retained evidence hashes and the current
  test snapshot matched; the 23 pre-existing E files matched task entry. No material
  findings or production/architecture changes were identified. Owner accepted F0.2
  and authorized the scoped local checkpoint, explicitly acknowledging outstanding
  isolated-baseline regression evidence. Author self-review remains separate.
- **Evidence applicability:** the four PASS results above belong to the retained
  mixed-tree candidate containing E runtime edits. The isolated committed baseline
  has not executed the lifecycle regression. No clean-baseline pass is inferred from
  acceptance or Git separation. The one required follow-up is
  `bats:tests/modules/test_read_capability_lifecycle.bats` through `tests/validate.sh`
  against the clean accepted history, with fresh retained output and the existing
  governor. This checkpoint identifies that check; it does not execute it.
- **Handoff:** RELEASE_FREEZE; accepted F0.2 is locally checkpointed separately from
  E. Finish the authorized E WIP preservation and return to clean `igor2`; no push,
  Step 20A implementation, further process milestone or regression execution.
  E remains deferred/unaccepted with its existing criteria and evidence. Historical
  no-commit authorization above describes the pilot run before this Owner checkpoint.
