# Igor 2 delivery roadmap

Status: **proposed reset (DISCOVERY); implementation awaits architecture confirmation**.

Updated: 2026-10-17, source baseline `1aac86a`. This replaces the A–H/23-step
planning structure, not historical acceptance or retained proof. The
current-work cursor lives in [STATUS.md](STATUS.md). The recommendation and
tradeoffs are in [the audit](ARCHITECTURE_READINESS.md); accepted policy is in
[DEVELOPMENT_POLICY.md](DEVELOPMENT_POLICY.md) and [DECISIONS.md](DECISIONS.md).
The Owner has accepted complete Igor 1 cutoff (D080); the proposed runtime
organization below is not accepted merely because this file was rewritten.

## Delivery rule

Five milestones deliver complete usable results. Each includes implementation,
callers, essential tests, practical docs and retirement of replaced paths.
Internal integration commits are encouraged; they are not new architecture
phases or independent roadmap items. No milestone may claim completion from
schemas, prose, mocked execution or passing unit tests alone.

Use [EXECUTION](EXECUTION.md)'s contract, regression, vertical-slice, inspection
and migration/recovery proof classes in one concise scenario ledger. Size the
Owner-approved validation budget from a dry run and existing durations. Reuse
unchanged proof; one final affected gate and an explicitly needed broad CI gate.
Do not renew the governor or waive missing real-consumer evidence.

## Sequence

| Milestone | Usable result | Main deletion | Complexity |
|---|---|---|---|
| M1 — One module and operation platform | Inspect and operate System, Docker and an attached Nextcloud through the same safe CLI/TUI path | v1 loader/hooks/actions, legacy configuration sources and direct menu execution | High: cross-cutting consumer/data migration |
| M2 — A reliable conversational operator | Complete a bounded task, answer its questions, recover after interruption; one Python coordinator | Bash control-plane plumbing, prose-based continuation, provider launch wrappers | High: PTY, transaction and state parity |
| M3 — A machine that Igor remembers | Persistent stale-aware inventory and continuing investigations with relevant evidence | Redundant probes, chat/WIP files used as machine memory | Medium/high: retention and provenance |
| M4 — Substantial verified work | Resume installation/configuration procedures safely with explicit recovery | Ad-hoc install/recovery scripts as independent controllers | High: irreversible effects and real environments |
| M5 — Installable, supportable Igor 2 | Documented Debian/Arch release with onboarding, diagnostics, upgrades and bounded resource use | Remaining obsolete docs/helpers and unreleased scaffolding | Medium/high: release integration |

M1 is already a useful operator for existing machines; M2 makes natural
interaction dependable. M3/M4 add memory and substantial work. Packaging and
installation instructions are maintained from M1; M5 closes the full release
matrix, not the first opportunity to run the software.

## M1 — One module and operation platform

**Purpose:** close the authority, lifecycle and ownership gaps before adding
more operations. Finish the clean module system in one coherent batch.

**User-visible result:** the user can inspect active modules and their settings,
operate System/Docker, attach an existing Nextcloud, read/change/verify a setting,
and use retained application operations through CLI and the same generic TUI.
Disabling a module removes its active behavior/context without deleting its data.
Every operation reports actual execution and verification, never unconditional OK.

**Architecture and implementation:**

- Keep strict v2 INI + explicit JSON declarations; one admitted contribution
  index. Migrate System's remaining hooks and all Nextcloud registrations.
  Docker stays v2. Samba remains an unadvertised recognition adapter until needed.
- Route all shipped operational entry points through canonical dispatch, including
  menus, diagnosis/healing, recovery, automation and AI. Retain the current Bash
  coordinator for this milestone; move deterministic policy ownership out of AI
  and remove competing invocation contracts. No new parallel backend.
- Finish one configuration/secret/path ownership model for shipped consumers.
  Reuse Configuration, Secret and Deployment services. Module packages carry
  no mutable machine values. Native application settings remain bound external
  authority; desired values and apply/readback are distinct.
- Move application-specific diagnosis/recovery/provider loading out of Core.
  Keep Nextcloud-on-Docker as one coherent application module; Docker's generic
  operations remain reusable. Do not split nginx/Redis/PostgreSQL/tunnel modules.
- Inventory and preserve useful existing operations. Replace interactive menu
  orchestration with typed inputs and generated presentation; reuse correct leaf
  scripts. Remove the host-wide NUKE action, replacing only a scoped operation
  when its resource/recovery contract is justified.
- Apply the finite data transition and no-old-interface proof in [LEGACY](LEGACY.md).
  Existing process sessions cannot straddle the cutover; require explicit restart.

**Scope:** the three shipped packages, live consumers, existing operations,
configuration/secret ownership, immediate F01–F04 defects, one real Nextcloud
configuration cycle. Includes a short install/doctor path for the declared roots.
Excludes new domains, remote control, third-party marketplace, hot unload,
generic rollback, full AI-loop rewrite, and new background automation behavior.

**Dependencies:** Owner confirmation of the reset architecture/scope; reviewed
current operation inventory and private data inventory; disposable Nextcloud
runtime supplied without altering the Owner's production stack. The existing
Step 19 fixture/runbook is reusable, but its host setup remains unexecuted.
The prior narrow loglevel execution architecture remains useful; the broader
cutoff is a new scope, not silently covered by that approval.

**Completion criteria:**

1. No v1 manifest/registration/action/hook consumer is executable in the Igor 2
   tree. No compatibility mode or fallback reactivates it. All shipped modules
   validate and require explicit activation; disabled/stale proposals fail closed.
2. Every retained operation has exactly one owner/provider, input contract,
   effect tier, privilege route, outcome and verification/recovery definition.
   A parity table accounts for all former menu/action functions. Valuable
   functionality is retained; any proposed removal beyond obsolete/unsafe paths
   is surfaced as an explicit scope change, never silently dropped.
3. User can inspect effective config source/owner and secret reference without
   exposing values. No normal startup sources legacy env files or moves data.
   Conflicts require explicit import decisions. Re-entry and recovery work.
4. Actual CLI and curses operation: attach fixture, read loglevel `2`, approve
   `3`, independently read `3`, approve return to `2`, read `2`, inspect History.
   OCC runs as the intended application user; no unbound deployment is touched.
5. System/Docker/Nextcloud disabling removes operations, checks, observations,
   active knowledge and automation; retained records remain historical. Re-enable
   recovers availability without inventing responsibility or applying settings.
6. No success result after a failed service command; no global Docker-volume
   enumeration in application destruction; all destructive approval is exact.

**Small meaningful validation set:** one shared authorization/secret/History
matrix; strict-v2/lifecycle contract tests; migration interruption/conflict tests;
one real System operation and the real Nextcloud cycle through CLI/TUI; affected
regressions for changed execution/storage/AI boundaries. Preserve targeted safety
edge cases. One broad integration run is justified by this cross-cutting cutoff,
preferably governed CI, not repeated after every correction. Lack of a real
application environment blocks closure, not implementation of independent code.

**Cleanup:** v1 parser, `compat.v1_hooks`, `__register`, hook registries and
`legacy.<owner>.<action>` dispatch; legacy env writers/fallbacks; direct menu
execution; obsolete v1 tests/guides; exact duplicate deprecated scripts; dormant
Textual frontend after caller check. Data import is an offline one-shot utility,
not an installed compatibility service. Keep existing collection validation;
Increment E's deferred acceptance is not automatically closed by M1.

**Expected complexity:** high, the largest migration. The finite boundary is
three packages/current operations. No calendar estimate is credible before the
operation mapping; do not disguise this as a small patch or enlarge it with M2.

### Immediate implementation batch — exact handoff

This is the first batch after architecture confirmation, not another open-ended
audit. Implement all of M1 with the following dependency order:

1. **Freeze a parity/data inventory at the implementation base.** Enumerate
   `module.sh` registrations, manifest menus, AI actions, diagnose/recovery hooks,
   configuration writes and data locations. Use the tables in LEGACY as the
   seed; append each remaining callable menu operation. For every row name
   retained v2 capability/check/observer/knowledge/config owner or explicit
   approved retirement. No broad additional architecture study is needed.
2. **Fix the dangerous legacy edges while converting their consumers.**
   `modules/nextcloud_docker/menus/services.sh`: start/stop/restart must report
   failures; eliminate `_mod_services_nuke`'s global resource selection. Preserve
   a failure fixture. `config_loader.sh`/`module_loader.sh`: eliminate fixed
   diagnostic captures and raw secret error output as those paths are retired.
   These are integrated fixes, not an excuse to ship the rest of the cutoff later.
3. **Complete data ownership and explicit import first.** Extend
   `configuration.py`, `secret_refs.py`, `openrouter_import.py`, `deployments.py`
   and declared path resolution only where shipped consumers require it.
   Select the proposed roots once; preserve supported explicit overrides.
   Implement dry-run inventory, conflict decisions, private staged copy,
   verification, atomic cutover marker, idempotent re-entry and recovery.
   Disable startup moves/source fallback in the same candidate.
4. **Convert the packages and consumers together.** Touch
   `modules/system/module.conf`, `module.sh` and contracts; Nextcloud manifest,
   contracts, `lib/` providers and menu leaf functions; Docker consumers as needed.
   The 12 existing Nextcloud AI actions are: health check, full diagnostic,
   services status, scan files, flush Redis, flush caches, repair, full repair,
   fix permissions, DB maintenance, permission inspection and native config
   injection. Also cover service lifecycle/logs, apps, configuration, backup,
   restore and installation workflows currently reachable through menus/hooks.
   Typed parameterization replaces hardcoded broad commands, not a generic
   shell-string escape hatch. Do not turn all verbs into a new mini-language.
5. **Unify dispatch and visibility.** Update `module_contract.py`,
   `module_registry.py`, `module_loader.sh`, `module_loader_fast.sh`,
   `module_handler.sh`, `capability.sh`, AI catalog/tool dispatch, operator CLI,
   TUI projection, health/diagnose, recovery and automation. Move Nextcloud
   provider selection out of `deployment_attachment.py`'s hardcoded import.
   Keep one live implementation per operation; cache invalidation/owner checks
   must survive removal of old views. Do not add another fast-loader override.
6. **Prove the complete application slice.** Use
   `tests/fixtures/step19-nextcloud/`; bind exact endpoint/project/application
   identity. Extend the existing approved narrow Nextcloud setting adapter for
   desired/apply/readback with canonical History. Run `2 → 3 → 2`, rejection,
   stale/disabled refusal and external-drift handling. Inject command failure
   without touching production Docker. Never install host dependencies merely
   to satisfy the audit; implementation setup has its own explicit authority.
7. **Retire and close.** Delete obsolete runtime paths and associated tests/docs,
   run the cutoff proof, required affected/CI gates once, update actual operator
   instructions and status, inspect final diff, commit and stop. No M2 work.

**Affected safety tests to retain/adapt, not simply delete:** module contract/
capability runtime, approval/privilege BATS, request/transaction privacy,
configuration/secret references, deployment/Nextcloud attachment, History,
module lifecycle and actual CLI/curses integration. Document-wording tests may
be replaced with link/authority checks; legacy invocation tests become canonical
behavior tests. Map removed cases to retained invariants in the single ledger.

**First-batch stopping rule:** missing real fixture, unsafe data transition,
unknown operation parity or exhausted validation budget means incomplete M1.
No successful unit count or documentation change substitutes for those gates.

## M2 — A reliable conversational operator

**Purpose/result:** users can state an objective, answer the exact question Igor
asked, see progress, cancel, and continue after a failure/restart without losing
the target or silently repeating a change. CLI and TUI share one application.

**Implementation:** Python owns session/task/registry/context orchestration and
imports existing services. Retain curses and native PTY authentication. Adopt
one typed internal model/tool transaction format and small provider adapters.
Reuse structured capability plans; persist task objective, pending question,
selected refs, steps/operation IDs, outcomes and explicit wait/unknown states.
Fresh authority/target checks remain in the executor. Persist bounded state,
not the whole conversation as operational truth. Consolidate policy under the
application executor and retire Bash orchestration together with its consumers.

**Scope/dependencies:** M1 contracts and operation parity. Anthropic, OpenRouter,
Ollama parity; configured ordinary/strong bindings; bounded context and accounting.
No autonomous multi-agent system, new provider requirement, arbitrary workflow
DSL, background daemon or remote approval. Native provider differences remain
inside adapters, not a universal least-common-denominator loss of tool safety.

**Completion:** same operations/results through CLI/TUI/AI; a pronoun/short choice
answer resumes the correct pending question; provider timeout/invalid response
preserves task; restart after effect but before response does not repeat effect;
unknown is visible; cancellation is honored; model cannot assert execution success.
A task shows model, selected context, token use, next action and reason.

**Validation:** recorded scenario corpus for question continuity, multistep work,
refusal, tool errors, exhausted budget and restart; existing provider native
transaction fixtures; real PTY approval/decline; actual M1 application workflow
through the assistant. Opt-in live-provider smoke for advertised transports,
with separate budget/privacy authorization. One affected gate for final candidate.

**Cleanup:** `core/ai/core.sh` control-plane loop, duplicated first/follow-up tool
dispatch, prose-based choices/completion, provider shell launchers/router, dynamic
loader patching and shell-JSON state transports. Retain useful shell handlers,
validated schemas, secret/History stores and provider boundary tests.
**Complexity:** high; cancellation, PTY and crash consistency are principal risks.

## M3 — A machine that Igor remembers

**Purpose/result:** Igor remembers installed/attached resources, last observed
health, settings and responsibility across sessions. A user can reopen an
investigation and see evidence, hypotheses, attempts and outstanding questions.
Stale evidence is clearly distinguished from current measurement.

**Implementation:** persist bounded last-observed System Model records with
provenance/age; reuse Deployment, Investigation and History identities. Refresh
explicitly/on declared policy; deterministic observation never becomes desired
configuration or adoption. Bind tasks to investigations rather than duplicating
results. Retrieve relevant facts/evidence/approved learning by target/capability
and time; support retention/export/delete with reference-unavailable handling.

**Scope/dependencies:** M1 ownership, M2 tasks. Existing System/Docker/Nextcloud
resources, current investigation/learning services. No semantic graph, mandatory
vector database, fleet inventory, external knowledge ingestion or new recognizer
framework. A second recognition domain is used only to validate existing generic
assumptions, not to start Samba product development.

**Completion:** restart preserves inventory with stale labels; refresh updates
only eligible owner facts; disabled module supplies no active knowledge/behavior;
missing/pruned sources are explicit; user distinguishes observed/desired/native
configuration/responsibility; reopen a diagnosed failure without rereading chat.
A learned procedure is reference material and cannot activate itself.

**Validation:** one restart/freshness/disable inventory scenario; one continuing
investigation; poisoned/reference-data refusal; bounded retention and interrupted
migration/export/restore; targeted existing investigation/learning/History tests.
**Cleanup:** redundant domain probes and WIP/chat summaries used as machine state;
merge redundant serialization helpers where demonstrated. Keep domain-meaning
separation. **Complexity:** medium/high, mostly integration and data lifecycle.

## M4 — Substantial verified work

**Purpose/result:** Igor can install/configure a supported application using a
reviewable procedure, preflight, per-step verification and explicit recovery. Work
can wait for a user/external prerequisite and resume without replaying effects.

**Implementation:** extend the existing bounded plans and M2 task records, not a
second workflow engine. Package-owned procedures reference canonical capabilities;
freeze plan revision/inputs/target/requirements; record step operation IDs and
checkpoints. Revalidate before continuation, stop on drift or unknown outcomes.
Declare rollback only where a concrete compensating operation is safe. Integrate
configuration, secrets, dependency preparation and deployment responsibility.

**Scope/dependencies:** M1–M3, disposable test environments. First full procedure:
Nextcloud-on-Docker installation/configuration and bounded recovery, using retained
working implementation. Current one-shot installation operations remain useful;
this milestone makes the complete sequence durable/verifiable. No arbitrary
DAG scheduler, universal undo, automatic internet-script execution or remote fleet.

**Completion:** install from declared prerequisites; verify application/user/storage;
interrupt at meaningful checkpoints; resume safely; fail a step and preserve
recovery options; never claim successful install from command exit alone; export
plan/evidence without secrets. User can inspect what remains before approval.

**Validation:** disposable clean install and configuration cycle; representative
crash before/after effect, drift and credential refusal; restore/recovery on a
fixture; targeted plan/authority/History tests. Platforms tested explicitly, no
blanket Debian/Arch native integration claim from mocks.
**Cleanup:** wizard/restore/install scripts as independent control planes,
subsystem-specific resume markers, duplicate preflight/verification logic.
**Complexity:** high; data integrity and irreversible effects dominate.

## M5 — Installable, supportable Igor 2

**Purpose/result:** a fresh supported machine can install Igor, configure a
provider, inspect capabilities, perform useful work and diagnose failures with
clear resource/cost limits. Existing users have an explicit data transition.

**Implementation:** close dependency/runtime-version and Debian/Arch support
matrix; package read-only code separately from machine data; onboarding and doctor;
private logs with operation/task correlation; reliable upgrade/export/recovery;
measure startup, ordinary READ, task latency, subprocess counts and context tokens.
Tune demonstrated bottlenecks only. Validate existing READ-only automation and
reviewed learning as optional features through the same authority, not new engines.

**Scope/dependencies:** M1–M4 complete, required live evidence available. No new
feature families or new provider obligations. Keep advanced unattended CHANGE,
remote communications, marketplaces, multi-machine management, helper-agent
networks and generalized knowledge imports in Igor 2.x.

**Completion:** clean install/upgrade in declared distro environments; documented
minimum versions; no repo write permission needed for ordinary operation; privacy,
approval, History and migration acceptance; practical troubleshooting and extension
guide; bounded startup/runtime/context targets measured on declared hardware.
Set numeric budgets from M1/M2 measurements, not invented audit targets.

**Validation:** one governed full release regression on final candidate, distro
installation smoke, real CLI/TUI/privilege/application slices, data transition and
recovery, provider smoke with authorized secrets/costs. Failure classifications
remain visible; baseline debt is not a clean pass.
**Cleanup:** final obsolete interfaces/docs, inert agents/config duplication,
unused helpers verified by callers. No deferred core cleanup gate: earlier
milestones already remove the paths they replace.
**Complexity:** medium/high integration; enter RELEASE_FREEZE after evidence,
commit and stop rather than add another architecture round.

## Mapping old work to this roadmap

Historical completion is scoped evidence, not completion of a new milestone.

| Old work | Actual disposition |
|---|---|
| Steps 1–6 / Wave C | Step 1 historical audit complete; Step 2 invariants partial; 3/4 interaction/privilege substantially present; 5/6 bounded Wave C complete. Mixed v1/v2 means M1 incomplete |
| Steps 7–10 / Wave D | Typed model/observation/check foundation; persistent machine inventory belongs to M3 |
| Steps 11–12 / Wave E | Canonical execution and bounded plans retained; assistant/task continuity M2, durable procedures M4 |
| Steps 13–14 | Domain events and READ-only automation retained; no new event/scheduler architecture |
| Steps 15–16 | History, investigations, context, learning/pattern/procedure services reused in M2/M3; no wholesale rebuild |
| Step 17 / Ownership boundaries | Partial setting/credential cutovers; complete shipped-consumer ownership in M1 |
| Step 18 / collections | Contracts and accepted increments retained; [collection RFC](COLLECTION_OPERATOR_RFC.md) and deferred E evidence remain binding within scope |
| Step 19 | Deployment/attachment code reusable; real setting cycle open and required by M1; provisioning M4 |
| Step 20 | Bounded System CLI/TUI and swap accepted; broad acceptance and 20C open; work absorbed into M1/M2/M5 |
| Step 21 / integration rules | Future generic rule packaging deferred; actual cross-module consumers use existing capability requirements |
| Step 22 / module tooling and external interfaces | Consolidate validator/author guidance in M1/M5; external imports, communications and remote interfaces deferred to 2.x |
| Original Step 19 / self-healing v2 | Separate deferred scope; retain current READ-only automation. Unattended CHANGE requires a future explicit authority decision |
| Step 23 | Removed as a late cleanup stage; retirement is part of each replacement milestone |
| F0 | Accepted development improvements remain; no repeat pilot required |

The prior roadmap is available with `git show 1aac86a:docs/igor2/ROADMAP.md`.
[Archived status](archive/STATUS_2026-10-16.md) preserves detailed acceptance,
failures and deferred work. No old wave is reopened solely by renaming the plan.
