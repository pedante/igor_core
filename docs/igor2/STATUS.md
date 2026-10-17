# Igor 2 current status

Last updated: 2026-10-17

## Current focus — M1 implementation from `21da2b5`

- **Phase/candidate:** IMPLEMENTATION on `okigor2`, clean base `21da2b5`.
  Owner explicitly requested M1 runtime implementation and internal commits.
  D080/D081 architecture is accepted; no roadmap redesign or delegation.
- **Scope:** [selected operation/data inventory](LEGACY.md#m1-operation-disposition-at-21da2b5).
  Final Python execution/module coordination, selected System/Docker operations,
  Nextcloud attachment/configuration, offline preservation and v1 retirement.
  Existing roots remain; no production deployment or user-data mutation authorized.
- **Batch:** Python isolated handler invocation shared by capability, observer and
  check callers; remove the separate collection-only subprocess wrapper. Tests
  migrate the existing namespace/path/envelope/collection protections and add
  cancellation, bounded diagnostics, startup injection and child cleanup cases.
- **Validation:** Owner replied “continue” to the proposed 1,800-second allowance;
  renewed once with that reason, retaining the ledger. **1455.629 s remain**,
  240 s per subprocess. The initial focused pass took 56.327 s; corrected checks
  and canonical safety/History proof took 267.306 s; the approval-only environment
  correction took 20.720 s. No broad/full suite or live deployment changes.
- **Batch exit:** handler implementation, callers and focused safety proof complete;
  author diff review and internal commit. Next: Python module/execution authority,
  selected package/configuration cutovers and v1 retirement. M1 remains open.
- **Blockers for milestone acceptance:** disposable Nextcloud setup remains
  separately unauthorized/unavailable per the prior fixture record; no independent
  reviewer designated. Neither is treated as a waiver or an implementation pass.

### M1 evidence ledger

| EXECUTION class | Current evidence / remaining proof |
|---|---|
| Contract | Shared Python handler and existing shell bridge tests PASS: namespace/path/input/envelope rejection, bounded output, TERM-ignoring timeout/cancellation, descendants, startup injection and private error handling |
| Regression | Handler/collection/event/validation mapping, canonical dispatcher, exact approval and native privilege tests PASS. Two existing lint issues in touched tests corrected. No broad gate claimed |
| Vertical-slice | Canonical History suite PASS, including real System memory READ and durable reopen, pre-effect History, interrupted CHANGE/no replay, refusal and failed verification. Full CLI/TUI/Docker and Nextcloud `2 → 3 → 2` remain open |
| Inspection | Clean base, declarations/callers and final adapter diff reviewed by author; no independent review claimed |
| Migration/recovery | Separate collection wrapper and bypass flags retired with caller/tests; interrupted-operation History proof PASS. Operation/data disposition recorded; persistent transition and v1 cutoff remain unimplemented |

The safety run initially failed one destructive-approval fixture because its
workspace was under `/home`, which the unchanged deletion denylist correctly
protects. The same approval file passed all 25 tests using isolated `/tmp` targets
(`m1-disposable-tmp-v1`). This was an environment correction, not a safety waiver.
The corrected evidence plus that targeted run covers 183 distinct checks/test
identities; do not add rerun counts to claim extra coverage.

Evidence summaries (initial failures retained):

- `.igor-governor/evidence/m1-handler-focused-20261017/summary.json`; SHA-256 `8af6e13eaa2d761088465b61c72b71960a5fa27e678d994b39c10cc0819fdd1d`.
- `.igor-governor/evidence/m1-handler-safety-20261017/summary.json`; SHA-256 `ec0b49c244866a3a40f5382e0c85a3501c255d9f6509653afc4adced899455b3`.
- `/tmp/igor-m1-handler-approval-20261017/summary.json`; SHA-256 `20752af67495f528b81f5176e7e2a17999d2b6ddca92fe7b811476787f81b1a9`.

## Previous task — governance cleanup and accepted M1/M2 handoff

- **Task/base:** finish interrupted governance work on `igor2` at `dd5d0ac`.
  Preserved the six pre-existing changes to AGENTS, Codex config/workflow, removed
  role/hook and documentation tests; no runtime edits, host setup or data moves.
- **Phase:** RELEASE_FREEZE. Required checks and author diff review are complete.
  Only scoped commit/status verification and completion report remain; those close
  this task. No automatic M1 implementation.
- **Authority:** Owner's explicit cleanup instruction and [D081](DECISIONS.md#d081--bounded-m1-platform-and-m2-durable-ai-orchestration).
  No Igor 1 compatibility or mandatory feature parity. Final Python execution/
  module coordination in M1; durable AI tasks/conversations in M2. Minimal v2
  contract, useful integrated System/Docker operations and Nextcloud configuration.
- **Next implementation scope:** [M1 exact handoff](ROADMAP.md#immediate-implementation-batch--exact-handoff).
  Inventory selected operations/data disposition, finish Python authority and its
  callers, migrate selected ownership/packages, prove real operations and Nextcloud
  `2 → 3 → 2`, retire v1 and stop. No full Nextcloud menu/action migration or M2.
- **Unconfirmed/outstanding:** exact new persistent roots are not accepted by
  D081; retain current declared roots unless a required change is confirmed.
  Disposable Nextcloud runtime/real acceptance, independent implementation review
  and sufficient governed validation remain M1 gates. No host setup or renewal
  is authorized by this cleanup. Existing runtime defects below remain unfixed.
- **Budget/plan:** 37.949 seconds remain at entry, 240-second subprocess ceiling
  further bounded by that allowance. Dry run selected structural/Ruff/docs/governor
  groups only. Runs completed in 13.836 s and 15.258 s; governor accounting now
  reports 0 seconds remaining. All required checks finished successfully before
  closeout; no renewal, further validation or broad runtime suite.
- **Review:** author self-review; no delegation or independent review claimed.

### Governance cleanup evidence ledger

| EXECUTION class | Evidence / applicability |
|---|---|
| Contract | D081 and architecture/roadmap/cutoff consistency; minimal module contract and M1/M2 separation; no executable contract migration |
| Regression | All 10 documentation and 9 governor tests PASS; corrected governor file rerun PASS. Structure/references and changed-test Ruff PASS; project/user TOML parsing PASS. Initial import-order failure was a test-infrastructure lint defect, corrected rather than waived by the broad baseline |
| Vertical-slice | Not applicable: no product/runtime implementation; no real System/Docker/Nextcloud evidence claimed |
| Inspection | Project/user config and hook registrations inspected: removed command is unregistered; user trust hash is inert metadata, unrelated hooks preserved; final diff reviewed at freeze |
| Migration/recovery | Interrupted working changes preserved (snapshot `/tmp/igor-governance-interrupted.patch`); no user data/schema migration; offline preservation requirements retained |

Evidence under `.igor-governor/evidence/` (both runs complete):

- `governance-cleanup-20261017/summary.json`, SHA-256
  `b6e55d48d18479ab424d00df7167ac7500e609f6bd7fbabbf5083832575beaa0`:
  20 PASS identities/checks, one raw Ruff failure reported as `FAIL_BASELINE`.
  Raw review found only import order; corrected rather than accepted as debt.
- `governance-cleanup-corrected-20261017/summary.json`, SHA-256
  `3281c1b464a21b00194f8e61904d9c5d319c0dff5fd3d6fffc645f2d4e7822bb`:
  10 PASS plus Ruff `BASELINE_FIXED`; zero failures, skips, timeouts or unavailable
  tools. Only structure, lint and the changed governor test file were rerun.
  The unchanged documentation suite retains its first-run evidence; excluded
  groups are not claimed as executed by the corrected run.

The final ledger/phase annotation changes no validated policy or link target.
No repository-wide or real application acceptance is claimed by this cleanup.

Historical audit evidence and its old phase/budget below are retained provenance,
not current instructions or proof for this candidate.

## Completed architectural audit — historical task record

- **Task:** documentation-only deep audit requested by the Owner; source baseline
  `igor2` at `1aac86a`, initially clean. No runtime rewrite, deletion, host setup,
  live AI calls or privileged operations performed.
- **Phase:** RELEASE_FREEZE. Documentation and required scoped checks are complete.
  Allowed next action: final diff/status review and local documentation commit.
  Commit/status verification and the completion report close this audit; no push
  or runtime milestone follows automatically.
- **Delivered direction:** [technical audit and architecture proposal](ARCHITECTURE_READINESS.md),
  [five-milestone roadmap and exact first batch](ROADMAP.md), and
  [finite Igor 1 cutoff/data transition plan](LEGACY.md).
- **Accepted decision:** D080 records the Owner's complete Igor 1 cutoff and
  supersedes requirements to preserve v1/Nextcloud compatibility. It does not
  claim the current runtime has migrated.
- **Architecture gate:** Python coordination, proposed persistent roots and the
  full M1 implementation scope remain DISCOVERY until Owner confirmation.
  Ordinary implementation choices need no repeated architecture vote.
- **Critical source findings:** legacy Nextcloud Services NUKE enumerates global
  Docker volumes/images outside canonical approval/History; start/stop/restart
  can report success after command failure; legacy config diagnostic captures
  can expose source errors; startup moves data without a complete migration
  transaction. These findings are documented, not fixed by this audit.
- **Budget:** 46.028 seconds governed allowance at entry; 37.949 seconds remain
  after the two scoped structural runs. No renewal or broad runtime gate.

## Implemented baseline and open proof

| Area | State retained by this reset |
|---|---|
| System operator | Bounded CLI/TUI package accepted `5efca3d`; swap-health accepted `73a4c06`; no reopening of those accepted slices |
| Module platform | System mixed v1/v2; Docker v2; Nextcloud v1. Full cutoff not implemented |
| Collections | Accepted contract/increments retained; Increment E deferred/unaccepted, no implied new acceptance |
| Step 19 | Metadata attachment and fixture preparation exist; real loglevel `2 → 3 → 2` and desired/apply workflow remain open |
| Step 20 | Bounded System package accepted; broader application/configuration and 20C acceptance open |
| F0 | Accepted/closed; do not repeat the pilot |
| Memory/AI | Private History/investigation/learning foundations exist; general durable observed inventory and resumable assistant tasks incomplete |

The previous host-setup task is no longer the active work queue. Its permissions,
blocked rootless launcher, absent Docker endpoint, private fixture and unexecuted
checks remain in the [historical current-focus record](archive/STATUS_2026-10-16.md#current-focus--step-19-disposable-nextcloud-environment)
and [deployment preflight](DEPLOYMENTS.md#step-19-loglevel-preflight--2026-10-16).
The audit does not authorize continuing that setup or renewing its budget.

## Audit evidence ledger

| EXECUTION class | Applicable evidence for this documentation task |
|---|---|
| Contract | Compare D078/D080, current runtime contracts and explicit proposal labels; no runtime contract changed |
| Regression | Governed changed-document references PASS, including the final crosswalk correction; policy consistency, both Codex TOML parses and corrected anchors PASS; final diff checked at freeze |
| Vertical-slice | Trace canonical operation, legacy menu, config/secret, AI and persistence consumers in source; no new live-runtime proof claimed |
| Inspection | Baseline inventory, file/function/line evidence and current-versus-proposed classification in the audit |
| Migration/recovery | Executable cutoff/import/recovery plan; historical evidence archived with links preserved. No data migration executed |

Scope: all tracked paths inventoried; relevant production call paths and
representative tests inspected. Not every fixture line or possible exploit was
reviewed. No independent subagent/reviewer tool was available. The report is
an author audit; existing test records are attributed, not recertified.

## Historical evidence

Read [the archive](archive/STATUS_2026-10-16.md) only for a relevant prior proof.
Old phase statements and allowances are historical, not instructions to resume.

<a id="step-15b-operational-history--implemented-validation-gate"></a>
Operational History's retained [Step 15B proof](archive/STATUS_2026-10-16.md#step-15b-operational-history--implemented-historical-validation-evidence).

<a id="stabilization-evidence-ledger-2026-10-12"></a>
Collections' retained [stabilization ledger](archive/STATUS_2026-10-16.md#stabilization-evidence-ledger-2026-10-12).

## Historical audit documentation change manifest

All 19 changed paths are Markdown. Runtime, tests, fixtures and Codex TOML/hooks
are unchanged. The new archive preserves historical acceptance/failure records.

- [AGENTS.md](../../AGENTS.md)
- [README.md](../../README.md)
- [docs/igor2/AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md)
- [docs/igor2/ARCHITECTURE.md](ARCHITECTURE.md)
- [docs/igor2/ARCHITECTURE_READINESS.md](ARCHITECTURE_READINESS.md)
- [docs/igor2/DECISIONS.md](DECISIONS.md)
- [docs/igor2/DEVELOPMENT_POLICY.md](DEVELOPMENT_POLICY.md)
- [docs/igor2/EVENT_BUS.md](EVENT_BUS.md)
- [docs/igor2/EXECUTION.md](EXECUTION.md)
- [docs/igor2/HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md)
- [docs/igor2/LEGACY.md](LEGACY.md)
- [docs/igor2/MIGRATION.md](MIGRATION.md)
- [docs/igor2/MODULE_API.md](MODULE_API.md)
- [docs/igor2/README.md](README.md)
- [docs/igor2/ROADMAP.md](ROADMAP.md)
- [docs/igor2/STATUS.md](STATUS.md)
- [docs/igor2/archive/STATUS_2026-10-16.md](archive/STATUS_2026-10-16.md)
- [docs/module_creation.md](../module_creation.md)
- [docs/module_lifecycle.md](../module_lifecycle.md)

Static preflight parsed both existing Codex TOML files and confirmed documentation-only
scope and unique decision IDs. A phase-label assertion initially expected the
literal DISCOVERY; the already-proposed roadmap label was made explicit. Anchor
inspection found two stale references (History and the legacy register-function
TOC); both targets were corrected. No runtime check was attempted or claimed.

Governed evidence: `.igor-governor/evidence/architecture-reset-20261017/summary.json`
and `architecture-reset-20261017-final/summary.json` under the same evidence root.
Each run: one structural check PASS, zero failures/skips/timeouts/unavailable tools;
2.039 s and 2.097 s elapsed respectively. The second run was justified only by
the final crosswalk correction and closeout text. Eleven runtime baseline entries
were unexercised. Historical roadmap-wording tests were not run or claimed green.
The final ledger/phase annotation changes no validated link target or policy.
