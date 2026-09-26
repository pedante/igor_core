# Igor 2 migration status

Last updated: 2026-09-26

## Baseline and stage

**Wave A / Step 2 — Architecture Rules / Regression Guards complete.** This
step adds focused tests for accepted current invariants and makes three narrow
corrections: Healing check discovery uses module identity; inactive Nextcloud
does not trigger generic Healing configuration checks; same-process disabled
modules do not receive startup configuration validation. The three stale
system-storage tests now reflect host-only `system` ownership. No later-wave
architecture was started.

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
| 3 Interaction Runtime | Implemented in substantial form. `core/ai/tui.py` projects backend JSONL events; command registry, pending choices, modes and approval states exist. Harden/reuse, do not replace. |
| 4 Privilege Boundary | Implemented differently but acceptably for current AI actions: native backend PTY sudo authentication follows exact approval. General capability metadata is partial. |
| 5 Module Runtime v2 | Implemented in substantial form: policy, discovered/active/unavailable state and owner-aware registrations exist. Step 2 corrected Healing's active-check defect and same-process config validation; full contract formalization remains Step 5. |
| 6 Module API v2 | Missing; v1 hooks are live compatibility. No v2 contract was started. |
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
  guard does not settle Q006 or complete physical core/module separation.
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

## Decision gates

Repository evidence does not resolve or materially change an accepted
decision, so `DECISIONS.md` is unchanged. Q006 (core versus `system` ownership)
remains the next material placement question for Steps 5–9. Q001/Q002/Q005
(module implementation, schema and dependency contracts), Q010 (raw shell)
and the other open decisions remain at their assigned roadmap steps. No open
decision blocks Step 2 regression tests.
