# Igor 2 migration status

Last updated: 2026-09-28

## Step 14 Automation Engine design gate

**Step 14 has an accepted design, no runtime implementation. 14A is unblocked.**
The authoritative [AUTOMATION_ENGINE.md](AUTOMATION_ENGINE.md) contract and
D044–D047 resolve Q008: active module declarations are proposals; only
explicit Igor administrator/runtime policy enables configured instances.
The versioned Core-owned private store will retain configured intent, due
claims and bounded last-attempt metadata across restart. It is separate from
Step 13's transient events, Q003 System Model persistence and Step 15 history.

The safe Step 14 execution boundary is unprivileged unattended READ in
Assist/Executive through the existing `run_capability` dispatcher. Guide
does not auto-run; CHANGE, DESTROY and privileged unattended runs remain
disabled pending a separate policy contract. Implementation is split into
14A registry/inspection, 14B one-time scheduled memory READ, 14C periodic,
14D event and 14E typed condition slices. This design gate ran no runtime
tests or regression suite; the five Step 14 proof classes remain required
before completion. Q003, Q007, Q009 and Q011 retain their later owners.

## Step 13 Domain Event Bus implementation

**Step 13 is complete at the accepted [EVENT_BUS.md](EVENT_BUS.md) boundary;
Step 14 runtime is not implemented.** `core/lib/domain_event.py` validates
the version-1 envelope and closed payload schemas. The owner-aware v2 index
admits active `<owner>.<domain>.<occurrence>` declarations. The module handler
API validates explicit requests and rechecks active ownership at publication.
The session-local bus stamps identity/source, retains 128 events, delivers to
Core subscribers best effort, and exposes read-only `igor_domain_event_types`,
`igor_domain_event_recent` and `--events types|recent` queries. It remains
separate from `core/ai/events.sh`; events grant no operational authority.

**Contract and vertical slice:** focused tests reject malformed, oversized,
unknown-version, secret-bearing and spoofed fields before delivery; inactive
owners cannot publish. Each committed canonical Wave E result uses one
publication path. Real `system.host.memory.refresh` produced one correlated
`succeeded`/`passed`/`success` event for `host:local`. The disposable
`system.service.restart` fixture produced one `succeeded`/`failed`/
`unverified_change` event. A failing subscriber did not change the committed
result or prevent later delivery. No event is emitted before a result exists.

**Inspection and recovery:** type/event queries and exact filters are read-only;
focused guards show no observer, check, capability or privilege invocation.
The owner-only scratch is a bounded, disposable session buffer. A fresh
process begins empty and cannot replay old callbacks or reconstruct lost IDs
or ordering. No persistent layout migration occurred. Existing AI audits and
recovery journals remain separate pending Step 15.

**Regression:** `bash tests/run_all.sh` passed all five groups (46 Bash core,
46 Python render, 305 core BATS, 130 module BATS, 40 integration BATS). The
full Python suite passed 254 tests and 94 subtests. Focused Step 13 tests,
Bash syntax, Python compilation, changed Python Ruff and `git diff --check`
passed. CI-configured ShellCheck passed on changed event, capability, loader,
handler and BATS paths; `igor.sh` retains two warnings on untouched lines.

Step 14 automation runtime, Step 15 durable history and later
baselines/healing remain deferred. Q008 is resolved by D044; Q003, Q007,
Q009 and Q011 retain their assigned decisions.

## Wave E Agent Architecture implementation

**Steps 11–12 are implemented for the bounded Wave E slice.** The accepted
D037–D039 contract remains [AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md).
The owner-stamped Wave C index now backs read-only capability list/inspection
and one structured invocation path through the existing AI dispatcher.
Canonical dotted IDs resolve one active provider automatically; absent and
ambiguous providers cannot execute, and an ambiguous call requires an explicit
provider. Complete v2 declarations expose version, schema, safety, privilege,
preconditions, verifier, recovery, affected objects and source. Bare Wave C
declarations, secret consumers without a reviewed adapter and privileged
operations without reviewed Core argv remain inspectable but unavailable.
The v1 action catalog is projected into `legacy.<owner>.<action>` and
`run_igor_action` remains its compatibility dispatcher.

`system.host.memory.refresh` is a real READ capability: its active `system`
provider calls the existing observer refresh, validates the Wave D
observation, updates the process-local System Model, runs the memory health
check and returns fresh fact/attempt evidence. The disposable
`system.service.restart` fixture proves structured unit input, CHANGE
approval, existing PTY sudo authentication, a frozen Core argv, live service
query verification, and `unverified_change` when the command succeeds but the
postcondition fails. No production service was restarted for proof.

The minimal plan value resolves ordered steps, typed object references and an
optional verifiable READ final check, keeps a digest, then sends each operation
through that same capability dispatcher. It records completed steps and stops
on failure. D038 leaves raw shell as a visibly
unstructured fallback: recognized canonical forms are rejected, raw CHANGE
requires explicit approval even in Executive, DESTROY requires exact `YES`,
and raw execution has no claimed deterministic verifier. Secret references
are validated as opaque values; a small authorized-consumer adapter provides
private FD access with value-free audit. No current v2 capability uses a
secret value, so secret-using declarations remain unavailable until a reviewed
consumer is installed. The future Ownership Foundation still owns durable
secret/configuration layout.

The Context Engine selects bounded typed items with source kind, owner,
object/capability, freshness and selection reason for the memory domain. It
composes current Wave D fact/health, active `system` knowledge, the available
memory capability and Core guidance into the existing `IGOR_REFERENCE_V1`
boundary. Inspection reads that selection without refreshing observations.
Other domains continue through labeled legacy context until they gain
authoritative facts and a relevance cutover; no second AI pipeline or prompt
authority was added. Disabled owners contribute no active capability or
knowledge. Context does not expand secret references, and existing outbound
privacy/redaction remains the last boundary.

### Wave E proof

- **Contract and inspection:** focused Python/BATS tests exercise provider
  resolution, inputs, preconditions, safety, approval, privilege, verification,
  recovery, raw fallback, plans, source selection and secret references. CLI
  `--capabilities list|inspect|plan` and `--context inspect` are read-only;
  `igor_capability_result(operation_id)` exposes running-session outcomes.
- **Vertical slices:** the live memory capability produced a verified result
  tied to a fresh `host:local` fact and health/context item. The file-backed
  service fixture recorded approval before sudo and exact `systemctl` argv;
  its forced inactive postcondition produced `execution_status=succeeded`,
  `verification_status=failed`, `outcome=unverified_change`.
- **Migration/recovery:** v1 actions and Nextcloud v1 retain their dispatch;
  the new memory capability has one observer/model update path. Observed facts
  remain process-local and rebuildable; no persistent layout migration or
  automatic rollback was introduced. Recovery classes are metadata; a
  recovery action, if registered, must use normal capability authority.
- **Regression and lint:** `bash tests/run_all.sh` passed all five suite
  groups (305 core, 126 module and 40 integration BATS cases); two core cases
  skipped because this runner lacks a GPG agent and `hostname -I`. The full
  Python suite passed 248 tests and 94 subtests. The focused capability and
  observation BATS run passed 23 cases. Bash syntax, Python compilation and
  `git diff --check` passed. Ruff passed on new Python files; full-repository
  Ruff reported the same 135 findings as the untouched `HEAD` baseline, with
  no new finding by file/code/message comparison. CI-configured ShellCheck on
  changed shell/BATS files reported 11 pre-existing warnings and no new
  warnings. These existing lint findings remain outside Wave E.

## Wave E Agent Architecture design gate (historical baseline)

The following paragraphs describe the accepted gate before implementation.

**Steps 11–12 have an accepted implementation contract, not a runtime
implementation.** The contract and falsifiable exit checks are in
[AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md); D037–D039 in
[DECISIONS.md](DECISIONS.md) settle the canonical capability/plan boundary,
Q010 raw-shell fallback and deterministic Context Engine selection. The gate
was prepared on clean `igor2` at `a07de42` (`origin/igor2`), with local
`master` verified as an ancestor. Wave D implementation and D033–D036 are
present. This documentation pass did not rerun runtime tests; the recorded
Wave D green proof below remains the baseline.

Step 11 is partial: v1 `ai_capabilities` gives active-owner tiered actions,
`run_igor_action` calls a no-input function, and the AI catalog/parser and
approval dispatcher protect current tools. The Wave C contribution index
records v2 capability declarations but does not dispatch them. Inputs,
preconditions, privilege metadata, deterministic verification, recovery,
affected-object and secret-reference contracts are missing. Legacy action
functions may invoke sudo internally; they are not yet v2 privilege-mediation
proof. Step 12 is partial: `IGOR_REFERENCE_V1`, outbound privacy scrubbing
and active knowledge filtering work, but `context.sh` still gathers broad
direct probes, hooks, patterns and saved text without item-level relevance
and provenance.

The selected Wave E proof combines a real active `system` READ path
(`system.host.memory.refresh` -> existing observer -> fresh System Model fact
-> `host.memory.health` context and verification) with a disposable
`system.service.restart` CHANGE fixture that exercises frozen inputs,
approval, existing PTY privilege mediation and execution-success/
verification-failure distinction. `nextcloud_docker` remains v1; no broad
application migration or persistent layout change is implied. The
Ownership Foundation still gates broad migration and later secret/history/
learning storage rules.

**The bounded Wave E implementation is unblocked by architecture decisions.**
Its required order and contract, regression, vertical-slice, inspection and
migration/recovery proof are specified in the Wave E contract. Q003, Q004,
Q007–Q009 and Q011–Q012 remain at their assigned later gates. Design
acceptance does not mark either Step 11 or 12 complete.

## Wave D Host Intelligence implementation

**Steps 7–10 are implemented at the accepted Wave D boundary.** Platform
package/service query and install/remove/update/upgrade argv resolvers extend `core/lib/pkg.sh`
without adding an execution path. The process-local System Model in
`core/lib/system_model.py` separates observed, configured, user-declared,
desired and inferred slots from watch/maintain responsibilities. Its Bash
bridge in `observation.sh` validates active v2 observer results before an
atomic runtime snapshot update. Observed values are rebuilt after restart;
there is no fact database. The shared `health_runner.sh` evaluates active v2
checks and adapts active v1 checks for Diagnose and Healing.

The real `system` path is `host.memory` → validated
`host:local/memory.available_bytes` → `host.memory.health` → read-only
inspection and Diagnose/Healing/AI projections. Igor stamps provenance,
freshness and check time. The 80/150 MiB boundaries are preserved. The old
`system__diagnose`, `system__health`, hardware check and AI-context RAM probes
were retired for this slice; other hardware and Nextcloud v1 checks remain.
`bash igor.sh --model fact host:local memory.available_bytes` and
`--model observers` are read-only;
`--model refresh host.memory` and `--model evaluate host.memory.health` are
explicit operations. The backend model/health inspection APIs retain state
within a running Igor process. Q003 and Q012 remain open.

### Wave D proof

- Contract: System Model unit tests cover independent slots, provenance,
  type rejection, availability, partial output, inference and source replay.
  Observer BATS cover active/inactive owner, malformed/failure cutover,
  no implicit read refresh and restart reconstruction. The health runner
  validates used-fact references and fails to `UNKNOWN` on stale input.
- Vertical slice: live `system` handler invocation produced a typed memory
  fact and a structured result with the same fact key/time. Diagnose and
  Healing each projected one RAM result. AI context uses the fact and keeps
  it inside `IGOR_REFERENCE_V1`.
- Inspection/recovery: `--model fact` is initially `not_observed`; explicit
  refresh populates it; a new Igor process again starts `not_observed` and
  rebuilds on refresh. Health inspection exposes the check's used fact and
  timestamp. Source-backed desired/responsibility replay is covered without
  adding a persistent layout.
- Regression: `bash tests/run_all.sh` passed all five groups (46 Bash core,
  46 Python render, 303 core BATS, 114 module BATS and 40 integration BATS),
  with one environment-dependent GPG-agent skip inside core. Full `pytest -q`
  passed 224 tests and 93 subtests. Bash syntax and `git diff --check` passed.
  Ruff passed on changed Python files. Full-repo Ruff still reports its
  pre-existing backlog; ShellCheck on changed shell files reports only the
  pre-existing warnings in `core/ai`, Healing and `igor.sh`.

## Wave D Host Intelligence design gate (historical baseline)

**Design accepted before implementation.** The implementation
contract and falsifiable exit checks are in
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md), with D033–D036 accepted in
[DECISIONS.md](DECISIONS.md). Wave C remains the green implementation baseline.
This paragraph records the design gate's preimplementation evidence.

The gate was made on a clean `igor2` worktree at `a8dda91`
(`origin/igor2`), with local `master` `76f04e3` confirmed as an ancestor.
Wave C's recorded baseline is five `run_all.sh` suite groups passing (core
288/288, modules 103/103, integration 40/40), with two environment skips
inside core, and 216 Python tests plus 93 subtests passing. Ruff's 135
pre-existing repository findings are unchanged by documentation. These are
the **recorded Wave C results**, not tests rerun for this gate.

Step 7 remains partial: Debian/Arch detection, logical package/service name
mapping, install command selection and Python resolution exist; package
query/remove/update, service operations and shared host read mechanisms do
not. `pkg.sh` defaults unknown family resolution to Debian and owns Docker
post-install work, both explicit migration points. Step 8 has no Igor-owned
fact store/query. Step 9 has a real invokable `host.memory` handler but no
typed ingestion, freshness or failure model. Step 10 has active-owner legacy
checks, but Diagnose and Healing discover/execute/parse them separately.
Direct AI/context host probes remain compatibility inputs.

The selected first slice is `system` `host.memory` -> validated observation
-> `host:local/memory.available_bytes` -> structured memory check ->
inspection and selected existing workflow/context projection. The source
fact and check must each have one authority per consumer at cutover.
Configured/desired/responsibility intent is rehydrated from an existing
authoritative source when one exists; observed facts are rebuildable. No
database or new persistent layout is selected, so Q003 remains open for
Step 15. The Ownership Foundation still gates broad module migration, not
this bounded host slice.

**Wave D implementation is unblocked by architecture decisions.** It must
follow the order and five proof classes in the contract document. Accepted
D017–D022 and the Wave C loader/adapter are unchanged; `nextcloud_docker`
continues as v1. At that gate Q004 and Q007–Q011 retained later decision
points; Wave E has since resolved Q010. Q012 records the later
effective-threshold configuration question.
The gate does not imply that Step 7 package/service mutations may
bypass current approval or sudo behavior.

## Baseline and stage

**Wave C Steps 5–6 are complete.** The first Module API v2 path is active,
inspectable and covered by contract, regression, vertical-slice and policy
migration proof. Wave D host-intelligence work can proceed within its scope.
Decisions D017–D022 select a language-neutral data contract with a Bash-first
handler adapter, a small strict v2 `module.conf` plus explicit JSON contract
files, typed dependency semantics, a core/platform versus `system` rule, one
loader with temporary v1 compatibility, and an initial reviewed-local-code
trust boundary. The green Wave B behavioral baseline was preserved during
the Wave C implementation.

The roadmap now also makes the ServerMind/Steward-derived design lessons and
execution discipline explicit in `INFLUENCES.md` and `EXECUTION.md`.
The accepted D017–D022 runtime contract was not reopened. The implementation
extends the existing loader with strict v2 validation, staged owner-aware
contributions, a Bash handler adapter and module inspection.

A cross-cutting Ownership Foundation is now a hard gate before broad Module v2
migration: canonical paths, configuration, secrets, persistent state, machine
memory, knowledge, local learning, investigations, history and runtime need
explicit ownership/lifecycle contracts. Wave C established the loader and
contribution boundary without making today's mixed storage layout a permanent
v2 public contract.

Wave B / Steps 3–4 completed the interaction and privilege work. Its backend
session, deterministic approval dispatcher, frontend event stream, TUI
projection and native sudo-through-PTY path remain authoritative.

Wave A / Step 2 completed the accepted architecture guards and removed the
three stale system-storage test failures. Its baseline is retained below for
comparison.

The Step 1 audit was performed on a clean `igor2` tree at `6675ece`; local
`master` `76f04e3` remains an ancestor. Its findings and red baseline are
retained below for comparison.

The audit is a snapshot of this checkout and its local `master` ref, not a
claim about a newer un-fetched remote branch.

## Current-state assessment

| Roadmap steps | Assessment from current repository |
|---|---|
| 1 Legacy Audit | Implemented by this evidence ledger and baseline. |
| 2 Architecture Rules | Implemented for accepted current invariants: focused ownership, trust, platform and safety guards now run in existing test suites. Later contracts get their own tests when implemented. |
| 3 Interaction Runtime | Implemented for current chat/TUI use. Backend command routing, pending choice/approval state, mode policy, provider continuation and ordered frontend events are guarded. Future interfaces can consume the same backend authority; no new interface was built. |
| 4 Privilege Boundary | Native backend PTY sudo authentication follows approval. Wave E v2 capabilities now declare privilege and bind reviewed exact argv before this existing gate; legacy actions retain their internal privilege behavior. |
| 5 Module Runtime v2 | Complete for Wave C in `core/lib/module_loader.sh`: v1/v2 dispatch, strict preflight, staged declarations, owner-aware contribution index, typed module/contribution state and inspection queries. |
| 6 Module API v2 | Initial Bash-first contract complete for Wave C in `core/lib/module_contract.py` and `core/lib/module_handler.sh`. `system` is a mixed v1/v2 reference; `nextcloud_docker` remains v1. Later kind-specific consumers remain deferred. |
| 7 Platform Abstraction | Wave D boundary complete: normalized Debian/Arch package query and install/remove/update argv, systemd state query and operation argv, strict names, timeout/error behavior and unknown-family failure. Legacy `pkg_install` remains compatible. |
| 8 System Model; 9 Observation Framework | Initial Wave D contract complete: typed keyed facts, independent intent/responsibility records, active v2 observation validation, freshness/failure state and read-only inspection. Broader domain inventory and persistence remain later work. |
| 10 Unified Health | Initial Wave D contract complete: one active-owner runner, structured v2 memory result, v1 line adapters and Diagnose/Healing projections. |
| 11 Capability System v2 | Bounded Wave E implementation: canonical owner-aware registry/invocation, typed inputs, deterministic preconditions, existing approval/PTY route, structured result/verification, recovery metadata, D038 fallback, inspection and small plans. V1 actions remain compatible; broader providers wait for reviewed adapters. |
| 12 Knowledge & Context Engine | Bounded Wave E implementation: deterministic typed, source-aware selection and read-only inspection for the memory domain inside `IGOR_REFERENCE_V1`. Other domains retain labeled legacy context until authoritative sources and relevance mappings exist. |
| 13 Domain Event Bus | Complete at the bounded Step 13 contract: validated session-local signals, owner-aware producers, read-only inspection and one `capability.completed` projection per committed result. `core/ai/events.sh` remains frontend activity. |
| 14 Automation Engine | Future. Existing schedules are not an Igor-owned automation contract; Step 13 events do not trigger execution. |
| 15 Operational History | Partial: private bounded AI audit, recovery journal and backup records exist; structured incidents/outcomes are missing. |
| 16 Baselines; 17 Relationships/Deployments; 18 Composable Modules; 19 Self-Healing v2 | Missing as target contracts. Preserve the current combined Nextcloud deployment until prerequisites exist. |
| 20 Igor TUI as Default | Partial: full-screen TUI works via `--ai-tui`; classic menu/line UI and `--extra` remain, and default launch is unchanged. |
| 21 Integration Rules | Missing as a shared contract. |
| 22 Module Tooling & External Interfaces | Partial/future: overlapping experimental validators and SMTP notifications exist; incoming mail control implementation is absent. |
| 23 Consolidation | Missing/future; compatibility paths have removal conditions in `LEGACY.md`. |

## Significant findings

- Preserve the current TUI/backend event projection, deterministic safety and
  privilege flow, module loader, action catalog, reference-data boundary and
  platform helpers. Their roadmap steps are extension/hardening work.
- Healing and startup config validation now use active module identity. Generic
  Healing no longer requires Nextcloud files when that owner is inactive.
  Diagnose, configuration, security defaults, recovery, old UI and platform
  post-install paths still contain application assumptions. The active-owner
  guard does not complete physical core/module separation; D020 now sets the
  placement rule for that later migration.
- The three stale `test_system_storage.bats` assertions were corrected to the
  current host-only `system` contract. A Nextcloud module check test preserves
  application storage behavior without restoring it to `system`.
- Configuration has overlapping defaults/migration paths; notifications have
  an event-hook and aggregator state path; Diagnose and Healing discover checks
  separately; several experimental module validators coexist. No second
  implementation should be promoted during cleanup.
- `core/mailcmd/` does not exist. Remaining menu/help/config references are
  stale affordances, not a functioning subsystem. SMTP notifications are real
  and separate from incoming control.

## Step 2 guards now in the suites

1. Module BATS covers active/disabled/unavailable/installed-only checks,
   owner-filtered hooks, menus including legacy lazy dispatch, config
   validation, backup/restore, notification hooks and owned action catalog.
   Existing dispatch tests reject inactive action owners.
2. Healing and Diagnose agree on the active module check set. Generic Healing
   ignores inactive Nextcloud configuration; active Nextcloud retains its
   current checks. System storage remains host-only.
3. AI tests place hostile module knowledge, logs, reports and tool output in
   the untrusted request envelope; deterministic tool parsing and execution
   tests reject claimed READ/approval authority. Existing tests cover pending
   modes, failed sudo, Executive DESTROY and exact operation handling.
4. Platform BATS pins Debian/Arch detection, current package and service
   mappings, mocked apt/pacman calls and unknown-family behavior.

Wave D added System Model and observer tests; Wave E added capability
verification tests. Domain events remain a later contract.

## Wave B runtime and privilege assessment

- `core/ai/core.sh` remains the backend session authority. Its registry handles
  typed and palette commands; its pending choice record now carries an explicit
  assistant owner, conversational-choice type and awaiting/resolved lifecycle.
  Numbered, ordinal and matching text replies resolve against that record.
  A bare `cancel` dismisses an active choice locally; commands and clearly new
  requests clear stale choice state. Without a pending interaction, ordinary
  chat still goes to the provider.
- `core/ai/safety.sh` remains the approval authority. Explain returns to the
  same pending request; Guide/Assist/Executive alter READ/CHANGE autonomy but
  cannot change DESTROY's exact `YES` requirement or grant OS privilege. The
  TUI sends input to this backend and projects ordered `core/ai/events.sh`
  activity events. Invalid event sequence values now fail at the projection
  boundary; frontend text or event fields cannot authorize execution.
- Sudo authentication stays in the backend PTY after Igor approval. The
  dispatcher uses the approved command for execution, may reuse OS-cached
  credentials, and fails closed on unavailable/failed authentication before
  backup or execution. Password input bypasses chat draft/history/events and
  audit. No separate sudo broker is justified by current callers. Step 11 may
  add declarative capability privilege metadata to this same execution gate;
  it must not create a second elevation path.
- The current pending-choice extraction is intentionally limited to explicit
  alternatives in the most recent assistant reply. Other natural-language
  intent and the narrative after `continue` still use provider conversation;
  the latter builds a failure recap from prior message text in
  `core/ai/core.sh`. Pause/resume routing is explicit and authorization stays
  deterministic at dispatch; this narrative is not authoritative operational
  state. `/stop` is handled at approval or the next backend chat prompt;
  a synchronous provider or tool call is not preempted. The classic
  line UI, `--extra`, old `exec on/off` setting bridge and
  v1 module APIs remain compatibility inputs under their existing removal
  conditions. No compatibility path met the safe-removal criteria in Wave B.

At Wave B completion, no accepted decision changed. Q010 raw-shell policy and
Q011 remote approval remained at their assigned later steps; neither blocked
that backend contract. Q006 was subsequently resolved by the Wave C design
gate in D020.

## Step 1 test and lint baseline (before Step 2)

Run against the clean pre-edit branch; documentation changes cannot affect the
application suites. These are **existing baseline** failures, not regressions
introduced by this audit.

| Check | Result |
|---|---|
| `bash tests/run_all.sh` | Failed: 4 suite groups passed, 1 failed, 0 skipped. `test_igor_core.sh` 46/46, `test_ai_render.py` 46/46 via unittest fallback, core BATS 273/273, integration BATS 40/40. Module BATS 58/61: only `test_system_storage.bats` cases 2–4 fail. |
| `bats --tap tests/modules/test_system_storage.bats` | Reproduced 2/5 passed, same three failures. |
| Full Python `pytest tests/ -q` | 203 passed and 89 subtests passed. The repository's `run_all.sh` itself only targets `test_ai_render.py`; this extra run covered all Python test files. |
| `bash -n` over `igor.sh` and all `core/`, `modules/`, `tests/` `.sh` files | Passed. |
| `ruff check .` (Ruff 0.16.9) | Failed with 135 existing findings; largest groups include I001 (23), PLW1510 (21), UP032 (20) and BLE001 (17). CI's Ruff installation is unpinned, so exact counts can vary by version. |
| ShellCheck with CI warning severity/exclusions (0.11.0) | Failed: core 76 findings (73 for the other 77 scripts, 3 for `core/ai/core.sh`), modules 14, entry point 2, tests 8. Core was split into two equivalent invocations because the all-core invocation ran too long. CI marks all ShellCheck steps `continue-on-error`. |
| `git diff --check` | Passed. |

CI invokes only the render Python test, while the full Python suite above is a
broader local check. CI ShellCheck is non-blocking; Ruff and test jobs are
blocking and were red at the Step 1 baseline for separate existing reasons.

## Step 2 validation and comparison

| Check | Current result and Step 1 comparison |
|---|---|
| Module BATS | 73/73 passed. The three stale system-storage failures from Step 1 are removed; new activation, catalog, config and Healing guards pass. |
| Core BATS | 284/284 passed, including the new trust, forged frontend-event and platform guards (Step 1: 273/273). |
| Full Python suite | 203 tests and 89 subtests passed, matching Step 1. The expanded request-boundary assertions pass. |
| `bash tests/run_all.sh` | Passed: 5 suite groups, 0 failed, 0 skipped. This removes the Step 1 failing module group without adding a new failure. Core BATS 284/284, module BATS 73/73 and integration BATS 40/40. |
| Bash syntax and ShellCheck on changed scripts | `bash -n` passed for `core/healing/core.sh` and `core/lib/config_loader.sh`. ShellCheck reports only the existing SC2155 in Healing; changed BATS files report only two warnings on pre-existing lines. No new lint finding was introduced. |
| Ruff 0.16.9 | 135 findings, exactly the same file/code/line/message set as Step 1; none added or removed. |
| `git diff --check` | Passed. |

Wave A is complete and ready for the next implementation wave. The current
test suite is green; the known Ruff/ShellCheck backlog remains outside Step 2.

## Step 2 decision gates (historical)

At Step 2, repository evidence did not resolve an accepted decision, so
`DECISIONS.md` was unchanged. Q001/Q002/Q005 and Q006 were then open; this
Wave C design gate resolves them in D017–D020. Q010 was later resolved by
Wave E in D038. No decision blocked Step 2 tests.

## Wave B validation compared with Wave A

| Check | Wave B result | Comparison with green Wave A |
|---|---|---|
| Focused interaction, approval, safety, privilege and frontend BATS | 101 focused cases passed. | New choice lifecycle, cancellation and declined-sudo guards pass alongside the existing approval and event guards. |
| Relevant Python TUI/PTY tests and full Python suite | Focused TUI, privilege PTY and session command tests: 56 tests and 46 subtests passed. Full `pytest tests/ -q`: 204 tests and 93 subtests passed. | Wave A full suite: 203 tests and 89 subtests; one new TUI event-sequence test with four subcases, no failure. |
| `bash tests/run_all.sh` | 5 suite groups passed, 0 failed, 0 skipped; core BATS 288/288, module BATS 73/73, integration BATS 40/40. | Wave A: all 5 groups passed; core BATS 284/284, modules 73/73, integration 40/40. No new behavioral failure. |
| `bash -n core/ai/core.sh`; `git diff --check` | Passed. | No syntax or whitespace regression. |
| Ruff 0.16.9 and CI-configured ShellCheck on changed files | Ruff remains at 135 repository findings, unchanged from Wave A. `core/ai/core.sh` retains its three pre-existing ShellCheck warnings (SC2174, SC2010, SC2011); changed BATS files pass ShellCheck. No warning appears on changed lines. | Lint backlog remains outside Wave B. |

Wave B completed with the green behavioral baseline preserved. At that point
`DECISIONS.md` was unchanged; no new decision gate arose for Steps 3–4.

## Wave C Module Platform design gate

The design review inspected the current loader, both bundled manifests and
modules, activation/dependency/capability/configuration tests, the v1 module
docs, config policy and Debian/Arch platform helpers. The branch contains its
local `master` baseline. This pass changed documentation only; it did not
rerun or alter the green Wave B behavioral suite.

- Q001, Q002 and Q005 are resolved by D017–D019. The current first-key
  manifest parser stays v1 compatibility; strict v2 parsing and JSON contracts
  are implementation work. Hard module dependencies name identities;
  substitutable requirements name canonical capabilities. Missing or disabled
  providers never auto-enable.
- Q006 is resolved as an ownership rule in D020: core/platform supplies
  reusable Linux mechanisms; `system` supplies host-domain meaning. Existing
  application logic and platform post-install leakage move only when later
  replacements are ready.
- D021 preserves the current state model and restart behavior. V1 hooks and
  lazy menus continue during migration; v2 declarations join one owner-aware
  index, with `system` as the first mixed reference and `nextcloud_docker`
  unchanged as v1. D022 settles the initial local-code trust boundary and
  explicit enablement for new v2 packages.

The implementation now follows the accepted Steps 5–6 sequence in
`MODULE_API.md`. The strict validator rejects malformed v2 manifests and
contracts before executable module code is sourced. The loader records API
version, lifecycle state and failure reason, stages owner-stamped
contributions, applies module-wide versus contribution-local requirements, and
exposes `igor_module_list`, `igor_module_status`, `igor_module_reason` and
`igor_contribution_list` for inspection. The Bash adapter validates syntax,
invokes one JSON request, and accepts only a valid response envelope.

`system` declares `host.basics` knowledge and the `host.memory` observer under
v2 while retaining its v1 hooks. The observer is exercised through the loader
invocation path and v2 knowledge is included in the active AI reference
context. The bundled system policy migration records an explicit enabled entry
for an installation that previously omitted it, preserves explicit disablement
and keeps a one-time pre-migration copy when an existing policy file is present.
Newly discovered v2 modules require
explicit enablement. `nextcloud_docker` remains on v1.

### Wave C completion evidence

| Proof | Result |
|---|---|
| Contract | 12/12 validator unit tests, 6/6 Bash adapter BATS, and 24/24 v2 runtime BATS. Invalid metadata and Bash syntax fail before source; unsupported API/runtime, duplicate/unknown declarations, path escapes, hard cycles, missing/disabled/ambiguous requirements and contribution-local failures have named reasons. |
| Regression | `bash tests/run_all.sh`: 5 suite groups passed, 0 failed, 0 skipped groups. Core BATS 288/288, module BATS 103/103, integration BATS 40/40. Two existing core BATS cases skipped within the passing group because GPG agent and `hostname -I` were unavailable. Full Python suite: 216 passed and 93 subtests passed. |
| Vertical slice | `system` validates `contracts/host.json`, activates, indexes `host.basics` and `host.memory`, returns structured memory data through `igor_v2_invoke`, and appears in `igor_module_list`. The host knowledge is tested inside the existing `IGOR_REFERENCE_V1` AI reference envelope. V1 `system` hooks still run once. A focused live-loader check confirmed `nextcloud_docker` remains active on v1 with owned menu, diagnose, AI, config, backup, restore and notification registrations; full startup retained eight executable catalog actions, including owned `scan_files`. |
| Inspection | `bash igor.sh --modules` and loader queries expose identity, API version, lifecycle state, owner, kind, source and precise module/contribution reasons. Active ownership is checked again at dispatch. |
| Migration/recovery | V1 omitted entries retain implicit enablement; new v2 entries require explicit enablement. The bundled `system` omitted policy is recorded once as `system=enabled`; explicit disablement is preserved. Existing policy is backed up once, updates use a private temporary file and atomic replacement, symlinks are refused, and write failure is reported as unavailable before source. No other persistent layout changed. |
| Lint and syntax | Bash syntax and `git diff --check` pass. Ruff 0.16.9 passes on new Python files; full `ruff check .` retains 135 pre-existing findings, matching the earlier baseline. CI-configured ShellCheck on changed shell/BATS files reports only five pre-existing SC2155 warnings in `core/ai/context.sh` and `igor.sh`; no new warning remains. |

No accepted Wave C decision was reopened and no new blocking question arose.
Q004 remains a future third-party distribution policy; at Wave C completion,
Q003 and Q007–Q011 remained at their assigned later steps (Q010 is now
resolved by D038). System Model, observer scheduling,
domain events, general Capability System v2, broad Ownership Foundation
migration, non-Bash adapters and composable Nextcloud modules remain deferred.
The Ownership Foundation remains a hard gate before broad module migration.
