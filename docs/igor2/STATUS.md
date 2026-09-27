# Igor 2 migration status

Last updated: 2026-09-27

## Baseline and stage

**Wave C design gate complete; Steps 5–6 implementation not started.**
Decisions D017–D022 select a language-neutral data contract with a Bash-first
handler adapter, a small strict v2 `module.conf` plus explicit JSON contract
files, typed dependency semantics, a core/platform versus `system` rule, one
loader with temporary v1 compatibility, and an initial reviewed-local-code
trust boundary. The current module runtime and green Wave B behavioral
baseline are unchanged by this documentation-only pass.

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
| 5 Module Runtime v2 | Implemented in substantial form: policy, discovered/active/unavailable state and owner-aware registrations exist. The completion design is settled; formal state/reason queries, v2 validation, staged registration and consistent ownership still require implementation. |
| 6 Module API v2 | Target design settled in `MODULE_API.md` and D017–D022; implementation is missing. V1 hooks remain live compatibility, and `system` is the first incremental reference case. |
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

The next task can implement Steps 5–6 in the sequence in `MODULE_API.md`.
Q004 remains open only for a future third-party distribution policy; Q003 and
Q007–Q011 remain at their planned later steps. None blocks Wave C
implementation. The behavioral baseline remains the Wave B result above;
documentation checks for this pass are recorded with the final diff.
