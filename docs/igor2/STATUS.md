# Igor 2 current status

Last updated: 2026-10-17

## Current focus — architectural audit and development reset

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

## Documentation change manifest

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
