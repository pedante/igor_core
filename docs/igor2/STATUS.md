# Igor 2 migration status

Last updated: 2026-09-27

## Wave D Host Intelligence design gate

**Design accepted; Steps 7–10 are not implemented.** The implementation
contract and falsifiable exit checks are in
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md), with D033–D036 accepted in
[DECISIONS.md](DECISIONS.md). Wave C remains the green implementation baseline.
This gate changes documentation only; it does not claim a new runtime test run
or Wave D completion.

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
continues as v1. Remaining Q004 and Q007–Q011 retain their later decision
points; Q012 records the later effective-threshold configuration question.
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
| 4 Privilege Boundary | Implemented differently but acceptably for current AI actions: native backend PTY sudo authentication follows approval of the exact command. General capability privilege metadata remains Step 11 work. |
| 5 Module Runtime v2 | Complete for Wave C in `core/lib/module_loader.sh`: v1/v2 dispatch, strict preflight, staged declarations, owner-aware contribution index, typed module/contribution state and inspection queries. |
| 6 Module API v2 | Initial Bash-first contract complete for Wave C in `core/lib/module_contract.py` and `core/lib/module_handler.sh`. `system` is a mixed v1/v2 reference; `nextcloud_docker` remains v1. Later kind-specific consumers remain deferred. |
| 7 Platform Abstraction | Partial: distro/family detection, Debian/Arch-aware package mappings/install and Python resolution exist. Other normalized operations and broad test proof are missing. |
| 8 System Model; 9 Observation Framework | Missing as coherent shared contracts; current direct probes are inputs, not a System Model. |
| 10 Unified Health | Partial: module check conventions and activation filtering exist, but Diagnose and Healing have separate discovery/execution/result paths. |
| 11 Capability System v2 | Partial: current owned, tiered AI action catalog and `run_igor_action` are the seed. General structured metadata, verification and shared interface use are missing. |
| 12 Knowledge & Context Engine | Partial: a sound request/reference trust boundary and active module hooks exist; composition still uses broad direct probes and saved files. |
| 13 Domain Event Bus; 14 Automation Engine | Missing. `core/ai/events.sh` is a frontend activity stream, not the domain bus. Existing schedules are not an Igor-owned automation contract. |
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

Generalized capability verification, System Model, observers and domain events
receive tests when those later contracts are implemented.

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
Wave C design gate resolves them in D017–D020. Q010 and other later questions
remain at their assigned roadmap steps. No decision blocked Step 2 tests.

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
Q004 remains a future third-party distribution policy; Q003 and Q007–Q011
remain at their assigned later steps. System Model, observer scheduling,
domain events, general Capability System v2, broad Ownership Foundation
migration, non-Bash adapters and composable Nextcloud modules remain deferred.
The Ownership Foundation remains a hard gate before broad module migration.
