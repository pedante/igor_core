# Igor 2 current status

Last updated: 2026-10-18

## Current focus — privileged execution coordination from `4fa4abb`

- **Phase/candidate:** RELEASE_FREEZE on `igor2` from clean `4fa4abb`. Owner
  authorizes remaining M1 execution migration; D080/D081 apply. One agent.
- **Slice:** move the remaining inline privileged argv validator/executor into
  `capability_runtime.py`, including its atomic pre-effect History claim. Keep
  existing shell approval/native PTY, common verifier/result publication and
  process-local configuration consumers. No new executor, storage or data move.
- **Reach:** `igor_capability_execute`, shared AI/CLI/TUI/plan/automation callers,
  existing privileged System adapters, runtime and canonical dispatcher tests.
- **Acceptance/validation:** exact proposal fence before effects; reviewed argv
  only, ordered stop on first failure, noninteractive sudo, duplicate claim
  refusal and pre-effect History. Runtime/History Python tests, canonical
  dispatch/approval/privilege and PTY regressions; dry-run selection bounded by
  235.761 seconds remaining, 240 per subprocess. Prior dispatch 33.723 s,
  History Python 24.528 s; reserve time for final references and corrections.
  Full 447-identity regression cannot fit; no renewal authorized.
- **Result:** the inline native executor is removed. Python validates reviewed
  argv and the exact approved proposal, claims the existing History operation
  before effects, runs commands in order and stops on failure. The shared shell
  adapter still performs verification/provider-complete/result publication.
  Detailed lifecycle ownership, smallest continuation and remaining M1 readiness
  are in [LEGACY](LEGACY.md#execution-ownership-and-remaining-cutover-at-4fa4abb).
- **Evidence:** final bounded safety run passes 199 distinct check/test identities
  (198 PASS and Ruff BASELINE_FIXED), zero failures/skips/timeouts/unavailable
  tools, in 204.511 seconds. The initial 12.328-second run passed runtime behavior
  but found two new test lint defects under the broad reviewed Ruff identity;
  both were fixed, not accepted as baseline debt. Final runtime tests executed
  freshly. No baseline metadata changed; no double-counting of the first run.
- **Boundary:** 18.917 seconds remain before closing documentation checks; no
  renewal. The prior 447-identity suite, automatic affected selection and full
  gate were not rerun. No production deployments, user data/secrets, actual host
  services or live Nextcloud changed. Scoped commit and commit/status verification
  close this internal slice; full execution migration and M1 remain incomplete.

### Privileged coordination evidence ledger

| EXECUTION class | Evidence / limitation |
|---|---|
| Contract | PASS: exact content/digest/precondition fence, denied authority/failed authentication, malformed arguments/argv, native adapter matrix, ordered failure/timeout/missing executable and same-operation duplicate refusal |
| Regression | PASS: runtime/result/output matrix, approval Explain/No/Stop/exact YES, native privilege/PTY, History service and canonical dispatcher; no full retained regression claim |
| Vertical-slice | PASS: fake sudo/service through real dispatcher and durable History; real System memory READ, reopen and plan references; native PTY uses fake sudo, no real privileged host/Docker/Nextcloud effects or interactive curses acceptance |
| Inspection | Author reviewed connected callers and final diff; provider/operation/authority/results remain inspectable through existing History and projections. Independent review pending |
| Migration/recovery | Inline executor retired with shared caller cutover; pre-effect claim failure blocks execution; interruption remains unknown without replay; post-effect persistence failure preserves canonical result. No format/root/data transition; offline migration and v1 retirement pending |

Raw summaries (SHA-256; initial failures retained):

- `/tmp/igor-m1-native-runtime-20261018/summary.json`:
  `a573cbba9533896480062645a0c291059c43c670297dcf569704d88e6550b9b3`.
- `/tmp/igor-m1-native-safety-20261018/summary.json`:
  `56c8c7b6d4e65249faf83ac45f3cb4988cc0185a5a71687f87cc69f649fad8b5`.
- Closing references/documentation proof: `/tmp/igor-m1-native-closing-20261018/summary.json`.
  SHA-256 `c9b41591fc65c40b1b106f7a120616619f05078efe634850fdac7cb0217f441e`;
  11 PASS including the repeated structure check. Combined final evidence has
  **209 distinct passing identities/checks**, no remaining failures or skips.
  Governor allowance after closeout: 11.531 seconds; no further validation.
  Final author diff/reference review complete; no independent review claimed.

## Previous execution coordination from `730e75e`

- **Phase/candidate:** RELEASE_FREEZE on `igor2` from clean `730e75e`; history
  confirms the two handoff commits. D080/D081 and the existing M1 disposition
  remain authoritative. One agent; no production/configuration/data changes.
- **Slice:** move execution-fence comparison and canonical terminal-result
  construction/outcome selection for single operations into existing
  `capability_runtime.py`; retire
  their shell implementations. Shared capability callers (CLI/TUI/AI/plans/
  automation), typed outputs/collections and History consume the same results.
  Keep approval/native PTY and in-process System configuration effects intact.
- **Acceptance/plan:** test exact approved content, drift and precondition
  refusal; provider failure, invalid output and failed/unavailable verification;
  canonical approval/privilege/History ordering, collection and process-local
  configuration consumers. Governed focused selection, then bounded affected
  safety/consumer proof; 1069.877 seconds available, 240 per subprocess, with
  closing reserve. No renewed budget or full-suite claim.
- **Remaining M1 dependencies:** full Python loading/authorization/execution/
  History integration; selected package/configuration and offline data cutovers;
  consumer proof before v1 retirement. Real Docker/Nextcloud acceptance, broad
  integration and independent review remain required and unverified.
- **Exit:** implementation, applicable tests, author review and closing
  documentation references complete; scoped commit and commit/status verification remain.
  No further runtime work in this slice; no M1 completion claim.
- **Initial evidence:** the first preflight stopped on an inherited Ruff
  timestamp diagnostic; corrected without a rule suppression. Subsequent focused
  run completed with 183 PASS plus one `BASELINE_FIXED` (Ruff), zero failures,
  skips or timeouts in 270.822 seconds. Author review then tightened comparison
  to serialized JSON equality (Python equality conflates `true` and `1`);
  final affected safety/consumer checks must include that correction.
- **Expanded evidence:** final runtime candidate completed the 23-group consumer
  pass in 383.633 seconds: 400 PASS, one `BASELINE_FIXED` (Ruff), five new fixture
  assertion failures and one reviewed baseline fixture failure. Raw failures are
  retained. System is actually 2.12.0; older Step 18 tests assumed 2.11.0 (including
  a substitution that no longer changed the manifest). The static CLI fixture
  omitted `module_registry.py`; the privileged-output fixture duplicated the
  shipped service capability ID and never reached its intended adapter check.
  Fixtures now read package version, corrupt the version independently of its
  number, include the authoritative policy reader and use a unique negative
  capability ID. Safety assertions remain; final targeted proof below passes.
- **Fixture correction evidence:** composition, privileged-output refusal,
  transaction and safety-dispatch checks pass. The static CLI test then exposed
  its obsolete `migration_pending_unknown` assertion; explicit policy ownership
  now reports `disabled_by_default`. It now asserts that state, false enablement,
  unevaluated runtime and disabled declarations, retaining all no-source/no-write
  markers. Final targeted proof covers both corrected fixture files.
- **Final result:** 447 distinct retained check/test identities pass (445 `PASS`,
  two `BASELINE_FIXED`); no remaining failures, skips, timeouts or unavailable
  tools. Combine the final runtime run with transaction/safety-dispatch evidence
  and the final two fixture files; do not count reruns as additional coverage.
  No baseline metadata or safety rule was changed. The governor reports 240.706
  seconds remaining before the closing documentation reference check; no renewal.

### Coordination evidence ledger

| EXECUTION class | Evidence / remaining proof |
|---|---|
| Contract | Exact approved content/JSON-type comparison, precondition refusal, result state matrix, malformed private input and bounded collection-result tests PASS |
| Regression | Canonical approval/native privilege, transactions/safety dispatch, module contracts/activation, History, typed outputs/collections and System configuration PASS; 447 retained identities including tool checks, no repository-wide gate |
| Vertical-slice | Real System memory READ and private process-local desired/commit/apply/readback/recovery PASS; public CLI READ/disable/re-enable/JSON/History and simulated generic TUI projections PASS. Privileged effects are mocked; Docker package contracts only, no real Docker/Nextcloud or interactive curses acceptance |
| Inspection | Provider/owner/operation identity and verification evidence retained in canonical results/History; author diff/caller review, no independent reviewer |
| Migration/recovery | Replaced shell fence/result implementations removed; no persistent format/root/import change. Historical records, interrupted CHANGE/no replay and explicit configuration recovery PASS; whole-M1 data/v1 cutoff pending |

Evidence summaries (initial failures preserved; SHA-256):

- `/tmp/igor-m1-coordination-20261018/summary.json` — `fa9ac7e12965939e716cabbda4d7c551415263ea182e38fadfb5690bbbaae8cf` (incomplete preflight).
- `/tmp/igor-m1-coordination-behavior-20261018/summary.json` — `98abfb6b735ac5c568468d9bbb521a72e4f6dbdb934f302f7e2a5b963e7383bc` (initial behavior pass; superseded by final runtime proof).
- `/tmp/igor-m1-coordination-final-20261018/summary.json` — `f702273462386186df8e08c929f07ab8d3d28c875c93afcdcd452092573d0897` (final runtime; fixture failures superseded below).
- `/tmp/igor-m1-coordination-fixtures-20261018/summary.json` — `0d66a2b51b415b888925adaaac33df35dda1b4e9453a394bdf04fc4167430f3b` (transaction/safety-dispatch PASS; obsolete policy-state assertion subsequently fixed).
- `/tmp/igor-m1-coordination-fixtures-final-20261018/summary.json` — `b728b6a7718ecfcc63eeaa754d8ecf0ff6233393ff829f503594caf67bc77787` (both final fixture files PASS).

No production deployments, actual user configuration, secrets or live Nextcloud
data were changed. Final phase/evidence annotations change no validated policy
or reference target. Independent implementation review and all unexecuted M1
acceptance remain open; this author review is not independent review.

## Prior M1 batches from `21da2b5`

The following is retained evidence for the preceding batches, not the current
phase or validation allowance.

- **Phase/candidate:** IMPLEMENTATION on `igor2`, clean base `21da2b5`.
  Owner explicitly requested M1 runtime implementation and internal commits.
  D080/D081 architecture is accepted; no roadmap redesign or delegation.
- **Scope:** [selected operation/data inventory](LEGACY.md#m1-operation-disposition-at-21da2b5).
  Final Python execution/module coordination, selected System/Docker operations,
  Nextcloud attachment/configuration, offline preservation and v1 retirement.
  Existing roots remain; no production deployment or user-data mutation authorized.
- **Committed batch `e269867`:** Python isolated handler invocation shared by capability, observer and
  check callers; remove the separate collection-only subprocess wrapper. Tests
  migrate the existing namespace/path/envelope/collection protections and add
  cancellation, bounded diagnostics, startup injection and child cleanup cases.
- **Current batch:** shared Python activation-policy reader/writer; loader,
  inspection, attachment and collection consumers migrated. Omitted modules stay
  inactive. Startup System enablement migration removed; explicit policy writes
  retain unrelated decisions and have atomic/idempotent/recovery proof.
- **Validation:** Owner replied “continue” to the proposed 1,800-second allowance;
  renewed once with that reason, retaining the ledger. **1069.877 s remain**,
  240 s per subprocess. The initial focused pass took 56.327 s; corrected checks
  and canonical safety/History proof took 267.306 s; the approval-only environment
  correction took 20.720 s. Activation-policy initial/correction runs took
  269.928 s and 96.874 s; final lint/reference checks took 15.790 s.
  No broad/full suite or live deployment changes.
- **Batch exit:** handler implementation committed; activation-policy batch in
  RELEASE_FREEZE with behavior, lint/reference checks and author diff review
  complete; scoped internal commit/status verification closes this batch only.
  Next: Python module/execution authority,
  selected package/configuration cutovers and v1 retirement. M1 remains open.
- **Blockers for milestone acceptance:** disposable Nextcloud setup remains
  separately unauthorized/unavailable per the prior fixture record; no independent
  reviewer designated. Neither is treated as a waiver or an implementation pass.

### M1 evidence ledger

| EXECUTION class | Current evidence / remaining proof |
|---|---|
| Contract | Shared Python handler tests PASS for path/input/envelope, limits, cancellation, startup injection and private errors. Activation parser/writer tests PASS for omitted/malformed/duplicate/symlink/nonregular/oversized policy, explicit decisions, private writes and uninstalled targets |
| Regression | Handler/collection/event/validation mapping, canonical dispatcher, exact approval and native privilege tests PASS. Policy consumers, loader activation/dependencies, attachment and collection leases/inspection PASS after fixture updates. No broad gate claimed |
| Vertical-slice | Canonical History suite PASS, including real System memory READ, durable reopen, pre-effect History, interrupted CHANGE/no replay, refusal and failed verification. Real System observer and knowledge loading PASS after explicit activation; attachment CLI proof uses mocked native resources. Full CLI/TUI/Docker and Nextcloud `2 → 3 → 2` remain open |
| Inspection | Clean base, declarations/callers and adapter diff reviewed by author; static inspection reports omitted packages inactive. Malformed policy is inspectable without source execution. No independent review claimed |
| Migration/recovery | Separate collection wrapper, bypass flags, v1 implicit activation and automatic System-policy migration retired. Policy interruption preserves original; repeated decisions are idempotent; unrelated entries/comments retained; stale/disabled attachment and collection proof PASS. Broader persistent transition and v1 runtime cutoff remain unimplemented |

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

Activation-policy evidence (initial failures retained):

- `/tmp/igor-m1-policy-20261017/summary.json`; SHA-256 `ced553673cc2f27895646345d685ac8a026b793814d22e59156871986b78f49e`.
- `/tmp/igor-m1-policy-corrected-20261017/summary.json`; SHA-256 `58de03a1b7b582806b367f1bce23dc60f10034a3e61cca8039e926ad27deaf9d`.
- `/tmp/igor-m1-policy-final-20261017/summary.json`; SHA-256 `e704abf8f94f020b69e62d1af749fa6b6cc6d37ff8f57d21e95dd8053947b249`.

Four behavior failures were obsolete implicit-activation/process-count fixtures:
System knowledge, omitted v1 activation, the separate policy process and a second
collection inspection provider. Fixtures now explicitly activate intended owners;
the omitted-owner tests prove refusal. Lint failures were corrected, including
ineffective BATS negation assertions, unused imports and UTC spelling. The final
fixture array-index correction passes lint; affected BATS syntax checks pass.
Combined retained evidence covers **200 distinct checks/test identities**, all
passing, with zero remaining failures/skips/timeouts/unavailable tools. This
excludes the removed implicit-v1 assertion and does not add rerun counts.
No failure was waived; no production policy or user data was changed.

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
