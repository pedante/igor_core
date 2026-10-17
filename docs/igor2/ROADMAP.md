# Igor 2 delivery roadmap

Status: **accepted direction and bounded M1 scope (D080/D081); runtime work not started**.

Updated: 2026-10-17, source baseline `1aac86a`. This replaces the A–H/23-step
planning structure, not historical acceptance or retained proof. The
current-work cursor lives in [STATUS.md](STATUS.md). The recommendation and
tradeoffs are in [the audit](ARCHITECTURE_READINESS.md); accepted policy is in
[DEVELOPMENT_POLICY.md](DEVELOPMENT_POLICY.md) and [DECISIONS.md](DECISIONS.md).
The Owner has accepted complete Igor 1 cutoff (D080) and the bounded M1/M2
architecture below (D081). The audit's other proposals are not automatically
accepted. This governance task implements no runtime milestone.

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
| M1 — One module and operation platform | Final Python executor/module coordination; useful System/Docker operations and Nextcloud configuration through CLI/TUI | Bash execution/module coordination, v1 interfaces and direct menu execution | High: bounded consumer/data cutover |
| M2 — A reliable conversational operator | Durable AI tasks/conversations, exact pending questions and safe restart through M1 execution | Bash AI loop, prose-based continuation and provider launch wrappers | High: transaction and recovery correctness |
| M3 — A machine that Igor remembers | Persistent stale-aware inventory and continuing investigations with relevant evidence | Redundant probes, chat/WIP files used as machine memory | Medium/high: retention and provenance |
| M4 — Substantial verified work | Resume installation/configuration procedures safely with explicit recovery | Ad-hoc install/recovery scripts as independent controllers | High: irreversible effects and real environments |
| M5 — Installable, supportable Igor 2 | Documented Debian/Arch release with onboarding, diagnostics, upgrades and bounded resource use | Remaining obsolete docs/helpers and unreleased scaffolding | Medium/high: release integration |

M1 is already a useful operator for existing machines; M2 makes natural
interaction dependable. M3/M4 add memory and substantial work. Packaging and
installation instructions are maintained from M1; M5 closes the full release
matrix, not the first opportunity to run the software.

## M1 — One module and operation platform

**Purpose/result:** final Python execution and module coordination, with useful
integrated System/Docker operations and one attached Nextcloud configuration
workflow through CLI and the same generic curses TUI. No Igor 1 compatibility,
mandatory feature parity or temporary Bash coordinator awaiting M2 replacement.
Disabling a module removes its active behavior/context without deleting data.

**Architecture and implementation:**

- Reuse strict v2 INI + explicit JSON declarations and one admitted contribution
  index. Keep the minimal forward-compatible [module contract](MODULE_API.md#m1-target-contract-d081):
  versions, owners, activation, dependencies/platform eligibility, typed I/O,
  bounded handlers, availability/provenance and canonical safety semantics.
- Python owns deterministic module loading/activation, resolution, authorization,
  execution and result/History coordination. Existing CLI/TUI/AI/check/automation
  consumers use that same authority. Useful reviewed Bash/Python leaf handlers
  remain; shell globals, duplicate registries and alternate executors do not.
- Reuse Configuration, Secret, Deployment, History and collection services.
  Packages carry code/defaults/knowledge, not machine values. Native application
  settings remain external authority; desired state, apply and readback differ.
- Keep Nextcloud-on-Docker together, with application-specific configuration and
  provider logic in its module. Docker supplies generic substrate operations.
  Do not split Redis, PostgreSQL, proxy or tunnel into new module products.
- Inventory all old interfaces for retain/defer/remove disposition and data
  safety. Port only selected Igor 2 operations. Remove unsafe global NUKE and
  unreachable v1 paths; preserve unsupported values/data offline under [LEGACY](LEGACY.md).

**Scope:** useful existing System host/service/package/storage/access/network
operations and Docker read/lifecycle capabilities that compose through the final
executor, plus Nextcloud recognition/attachment and bounded configuration
inspection, desired-state proposal/commit, apply and independent readback. Keep
existing capability IDs/semantics where correct; record deliberate migrations.
No requirement to port all 40 System capabilities or all 12 old Nextcloud AI
actions merely because they exist. The implementation inventory names the actual
selected IDs and their retain/defer/remove disposition before conversion.

**Excluded:** Nextcloud installation, backup/restore, repair/maintenance, app
management and general service administration; new domains, remote control,
marketplace, hot unload, generic rollback, new automation behavior, and M2's
durable AI tasks/conversations. These exclusions do not justify leaving old
execution interfaces callable. Useful mechanics can remain inactive source material.

**Dependencies:** the accepted D081 architecture needs no repeat vote. Before
runtime edits, bound the operation/data inventory at the implementation base and
plan validation within the existing allowance. Reuse declared roots and explicit
overrides; any required new storage-layout decision stays explicit. A disposable
Nextcloud runtime is needed for closure; the existing Step 19 fixture/runbook is
reusable, but host setup has not been completed or reauthorized by this cleanup.

**Completion criteria:**

1. Python is the final execution/module authority. No v1 manifest, hook,
   registration, legacy action, configuration fallback or competing executor is
   reachable. Unsupported packages fail before executing module code.
2. Each selected operation has one owner/provider, typed contract, effect tier,
   approval/privilege route, honest outcome, verification and recovery limits.
   A disposition inventory accounts for omitted operations; no parity gate.
3. Active/disabled/stale/missing/ambiguous provider behavior fails closed across
   operations, checks, observations, knowledge, config validation and automation.
   Retained records remain historical; re-enable never invents responsibility.
4. Effective config owner/source and secret references are inspectable without
   values. Startup never sources old env files or silently moves data. Explicit
   import/export, conflict handling, interruption/re-entry and recovery preserve
   supported and unsupported user data and historical operation meaning.
5. Real System and Docker operations run through the shared CLI/TUI authority.
   On a disposable bound Nextcloud: attach, read loglevel `2`, approve/apply `3`,
   independently read `3`, approve return to `2`, read `2`, inspect History.
   OCC uses the intended application user and exact deployment identity.
6. Refusal, failure, stale target and external drift never become success or
   authorize another target. Exact destructive approval and native sudo PTY,
   pre-effect History, private/scrubbed data and exact-consumer secrets survive.

**Validation:** one shared authorization/secret/History matrix; strict-v2 and
lifecycle tests; explicit data-transition interruption/conflict/recovery tests;
real System/Docker and Nextcloud CLI/curses slices; affected execution/storage
regressions. One broad integration pass is justified by the executor cutoff,
preferably governed CI. Missing real application evidence blocks closure, not
independent implementation. Collections Increment E remains deferred/unaccepted.

### Immediate implementation batch — exact handoff

The next implementation task is M1 only, in this dependency order:

1. **Freeze a bounded operation/data disposition inventory.** Use LEGACY and
   current manifests, hooks, menus and live callers. Name selected System/Docker
   capability IDs and Nextcloud configuration operations, deferred/removed
   interfaces, data sources and retention/export handling. No new architectural
   investigation or mandatory port of every legacy operation.
2. **Finish the Python module/execution authority.** Reuse `module_contract.py`,
   `module_registry.py`, canonical capability admission, approval/PTY, verification
   and History. Replace Bash coordination in `module_loader*.sh`,
   `module_handler.sh` and `capability.sh` together with their live callers.
   Adapt CLI/TUI, AI tool dispatch, check/observer and automation consumers;
   preserve collection validation and one canonical result path.
3. **Complete selected ownership/data transitions.** Reuse `configuration.py`,
   `secret_refs.py`, `openrouter_import.py`, `deployments.py` and declared paths.
   Provide explicit offline inventory/import/export with conflict decisions,
   private staging, verification, idempotent cutover and recovery where needed.
   Remove startup moves, secret diagnostic captures and env fallback together.
4. **Convert selected package operations.** Remove System compatibility hooks,
   integrate Docker, and give Nextcloud v2 declarations and module-owned bound
   configuration/attachment providers. Remove hardcoded Nextcloud selection from
   Core. Extend the existing narrow setting adapter for desired/apply/readback;
   typed inputs replace menu prompting. Eliminate global NUKE and v1 menus/actions
   without porting excluded operations or deleting native application data.
5. **Prove and retire.** Exercise selected operations and the real loglevel
   `2 → 3 → 2` cycle, refusal, failure, stale/disabled target, drift and recovery.
   Retire replaced interfaces/tests/guides, map safety tests to retained invariants,
   update actual operator docs and STATUS/LEGACY, run the required bounded gates,
   review, commit and stop. No M2 work.

Missing selected-operation disposition, unsafe data transition, unavailable real
fixture or exhausted validation allowance means incomplete M1. Unit counts and
documentation cannot substitute for the five EXECUTION proof classes.

## M2 — A reliable conversational operator

**Purpose/result:** users can state an objective, answer the exact question Igor
asked, see progress, cancel, and continue after a failure/restart without losing
the target or silently repeating a change. CLI and TUI share one application.

**Implementation:** extend M1's Python application with durable AI task and
conversation orchestration and bounded context selection. Execution and module
coordination are already final in M1. Retain curses and native PTY authentication. Adopt
one typed internal model/tool transaction format and small provider adapters.
Reuse structured capability plans; persist task objective, pending question,
selected refs, steps/operation IDs, outcomes and explicit wait/unknown states.
Fresh authority/target checks remain in the executor. Persist bounded state,
not the whole conversation as operational truth. Use M1's deterministic
executor; retire the remaining Bash AI conversation loop with its consumers.

**Scope/dependencies:** M1 contracts and selected operations. Preserve supported
Anthropic/OpenRouter/Ollama transaction safety; configured ordinary/strong bindings;
bounded context and accounting. No Igor 1 feature-parity obligation.
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
AI-specific shell-JSON state transports. Module-loader patching was retired in M1.
Retain useful shell handlers,
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
working implementation. Existing installation mechanics are reusable source material; M1 does not
retain them as callable legacy interfaces. M4 makes the sequence durable/verifiable. No arbitrary
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
**Cleanup:** final obsolete interfaces/docs, unused helpers verified by callers. Governance roles/hooks and config duplication
are removed by the current cleanup, not deferred to M5. No deferred core cleanup gate: earlier
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
| Step 17 / Ownership boundaries | Partial setting/credential cutovers; selected-consumer ownership and offline preservation in M1 |
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
