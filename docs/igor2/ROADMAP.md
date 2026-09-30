# Igor 2 roadmap

The numbered step names are stable references. They describe outcomes, not instructions to rebuild functionality that already exists.

Status labels describe the current `igor2` baseline:

- **CURRENT** — substantially present; audit/formalize rather than rebuild.
- **PARTIAL** — useful implementation exists but target contract is incomplete.
- **FUTURE** — target architecture is not yet established.
- **NOW** — current work.

## Execution gates

Roadmap prose does not make a wave complete. Each foundation/wave closes with
evidence for the five proof classes in [EXECUTION.md](EXECUTION.md):

1. contract proof;
2. regression proof;
3. a real vertical slice;
4. inspection/observability proof;
5. migration/recovery proof where persistent data or contracts change.

Exit conditions should be scriptable/falsifiable wherever practical. The
existing green baseline remains part of every later wave's regression gate.

## Development waves

- **Wave A — Foundation:** Steps 1–2
- **Wave B — Runtime & Safety:** Steps 3–4
- **Wave C — Module Platform:** Steps 5–6
- **Wave D — Host Intelligence:** Steps 7–10
- **Wave E — Agent Architecture:** Steps 11–12
- **Wave F — Reactive Igor:** Steps 13–16 and 19
- **Wave G — Composable Igor:** Steps 17–18 and 20–22
- **Wave H — Consolidation:** Step 23

Recent work means Waves B and parts of C/D/E already have substantial foundations. The roadmap must preserve and generalize them rather than create parallel systems.

## Cross-cutting Ownership Foundation

Before broad Module v2 migration, Igor must establish one authoritative
ownership model for:

- canonical paths;
- user configuration;
- secrets and secret references/access;
- persistent state;
- machine memory;
- knowledge;
- learned local artifacts;
- investigations;
- operational history;
- disposable runtime.

Every important persistent value should have an owner, source, scope,
lifecycle, migration/reset behavior and appropriate inspection surface.

The configuration direction in [CONFIGURATION.md](CONFIGURATION.md) keeps
canonical setting identity and semantics independent from current env-file or
future database storage. Modules describe configuration; Igor owns mutable
values, secret references, validation and migration. The document is a design
proposal, not an implemented Configuration Service.

This is a hard architectural gate, not a new wave name. Early non-conflicting
Wave C loader/contract implementation may proceed, but Wave C must not freeze
the current mixed config/secret/state layout into the public Module v2
contract, and broad application-module migration waits for this foundation to
be green.

## Igor 2.0 scope boundary

The A-H roadmap through Step 23 defines Igor 2.0. Post-2.0 ideas such as
AI-assisted capability promotion, a module marketplace/packs/signing
infrastructure, sophisticated dependency solving, hot unload and a second
handler-language adapter do not block Igor 2.0 unless a concrete requirement
moves one into scope.

---

## Step 1 — Legacy Audit & Cleanup Map — NOW

Audit the **current** repository against Igor 2 invariants.

Classify significant architecture paths as:

- KEEP;
- ADAPT;
- REPLACE;
- REMOVE;
- TEMPORARY COMPATIBILITY.

Also classify roadmap requirements as already implemented, partial, implemented differently-but-acceptably, or missing.

Update `LEGACY.md` and `STATUS.md` with evidence. Establish the test/lint baseline. Make only small, clearly safe baseline/doc fixes; do not start later architecture.

## Step 2 — Architecture Rules — PARTIAL

The repository-resident architecture package exists.

Complete this step by turning critical invariants into focused regression tests where practical and reconciling accepted decisions with Step 1 evidence.

## Step 3 — Interaction Runtime — CURRENT / HARDEN

The structured TUI, event stream, command registry, session states, approvals and pending conversational choices already exist.

Audit and harden:

- explicit pending interaction state;
- deterministic replies such as `3`, `logs`, `yes`, `continue`, `cancel`;
- conversation/approval state transitions;
- frontend/backend ownership;
- reuse by future interfaces.

Do not replace this runtime with a second state machine merely to satisfy the roadmap.

## Step 4 — Privilege Boundary — CURRENT / HARDEN

Native sudo authentication through the backend PTY and privilege events already separate OS authentication from AI autonomy.

Formalize the general contract:

- privilege metadata belongs to capabilities/runtime;
- exact approved operation is preserved;
- authentication never enters model context/history/events;
- Executive never grants blanket root;
- failures close safely.

Extend only where current behavior does not cover general capabilities/interfaces.

## Step 5 — Module Runtime v2 — COMPLETE FOR WAVE C

Current code already has:

- installed/discovered modules;
- explicit enable/disable policy in `config/modules.conf`;
- active/unavailable state;
- owner-aware hooks, menus and capabilities;
- active-module filtering in major subsystems;
- regression tests.

Do not introduce a parallel loader or rename states without value.

The Wave C implementation extends the existing loader in place. It preserves
the lifecycle vocabulary and restart semantics while adding strict v2
preflight, staged owner-aware contributions, typed requirement failures and
inspection queries. Contract, regression, inspection and policy migration
evidence is recorded in `STATUS.md`.

Restart-based activation is acceptable; hot unload is not a requirement.

Wave C completion must prove at minimum:

- invalid v2 metadata fails before handler execution;
- inactive/unavailable owners contribute no active v2 behavior or reference
  data;
- one owner-stamped contribution index serves v2 plus temporary v1 consumer
  views;
- the Bash adapter executes the language-neutral handler envelope;
- `system` exercises a small mixed v1/v2 slice;
- `nextcloud_docker` remains working on v1;
- current Wave B interaction/approval/privilege regressions remain green;
- module state, API version, ownership and unavailable reasons are inspectable.

## Step 6 — Module API v2 — INITIAL CONTRACT COMPLETE FOR WAVE C

Define and validate a versioned contract based on durable concepts rather than an expanding hook list:

- identity;
- knowledge;
- observers;
- capabilities;
- checks;
- domain events;
- automations;
- relationships;
- configuration;
- lifecycle.

The Wave C design gate selected the contract in `MODULE_API.md` and D017–D022.
The initial Bash adapter, strict validator and JSON contribution path are now
implemented. The `system` slice proves knowledge and observer declarations;
kind-specific consumers and broader migration remain future work.

Contracts are optional. Keep API v1 working through an explicit migration/compatibility path until real v2 modules prove the contract.

Implementation follows D017–D022: one loader, strict v2 validation, one
owner-aware contribution index and Bash as the first handler adapter.
`system` is the incremental v2 reference module during Wave C;
`nextcloud_docker` stays on v1 throughout the wave.

## Step 7 — Platform Abstraction — WAVE D BOUNDARY COMPLETE

Current `distro.sh`, `pkg.sh` and Python resolution already include Debian/Arch-aware behavior and additional family mappings.

Audit and generalize rather than replace.

Target at minimum:

- tested distro/platform detection;
- package query/install/remove/update abstractions;
- systemd service operations;
- host identity and common user/filesystem/network operations needed by capabilities;
- tests for Debian and Arch behavior.

Do not claim full derivative support merely from `ID_LIKE` or package mappings.

The Wave D design in [HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md) keeps the
existing helpers and limits immediate additions to read/query mechanisms and
tested package/service mutation argv resolution. Actual new privileged
execution remains behind the current gate and Step 11 generalization. New
normalized resolution fails closed on unknown families; preserve legacy
`pkg_install` callers until their cutover. Move Docker
post-install behavior with its domain capability, not into `system`.

## Step 8 — System Model — INITIAL CONTRACT COMPLETE FOR WAVE D

Create Igor-owned structured state for host, OS, storage, networking, services/packages, Igor runtime/modules, domain instances and relationships.

Facts distinguish:

- observed;
- configured;
- inferred;
- user-declared;
- desired;
- responsibility/maintain-watch intent;
- known/unknown/stale.

Machine memory also links relevant installation/deployment records,
investigation findings and deterministic verification outcomes without turning
chat history into state.

Every fact/intent record should expose owner, source/provenance and freshness as
applicable. Start with stable interfaces and simple storage; do not choose a
large persistence system prematurely.

Wave D implementation uses the accepted D033/D036 record, availability,
responsibility and source-backed intent contract in
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md). Observed facts are rebuildable
in the first slice; Q003 remains open for later durable observed history.

## Step 9 — Observation Framework — INITIAL CONTRACT COMPLETE FOR WAVE D

Standardize observers that populate the System Model.

Observers declare ownership, output types, cost/freshness, privilege, timeout and dependencies as needed.

Problem discovery is a deterministic Igor function: observers/checks can detect
unhealthy, drifting or surprising state before the model explains it. AI may
choose follow-up questions or capabilities, but should not be the only sensor.

Consumers should query Igor state instead of repeatedly issuing their own
probes. Observer/fact provenance and freshness must be inspectable from the
first authoritative implementation.

Wave D extends the existing Wave C observer adapter with declared typed
properties, runtime validation, atomic System Model updates and deterministic
failure/staleness semantics. The invocation and inspection contract is in
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md); no general scheduler is added.

## Step 10 — Unified Health — INITIAL CONTRACT COMPLETE FOR WAVE D

Diagnostics and healing share an active-owner check runner and structured
result contract while keeping separate user workflows. V1 line adapters
remain during module migration.

Unify the underlying structured observation/check result while keeping Diagnose and Self-healing as different user workflows.

One check result should be reusable by health score, diagnosis, AI, healing, notifications and history.

The Wave D gate selects one active-owner runner and structured result with
v1 line adapters. Keep the distinct workflows, suppress a legacy check when
its canonical v2 result becomes authoritative, and prove one execution per
pass. See [HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md).

## Step 11 — Capability System v2 — BOUNDED WAVE E IMPLEMENTED

The current action catalog, `run_igor_action`, ownership and safety metadata are the seed.

**The bounded Wave E runtime is implemented.** D037–D038 and
[AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md) define identity/provider
resolution, typed inputs, deterministic policy/privilege/preconditions,
postcondition verification, recovery, affected objects, secret references,
Q010 shell fallback, inspection and the minimal resolved-plan contract.
The implementation extends the owner-aware catalog and existing dispatcher.
The real READ slice is `system.host.memory.refresh`; an isolated
`system.service.restart` fixture proves CHANGE/privilege/verification,
including the `unverified_change` result. V1 actions remain compatible;
additional privileged and secret-using providers need reviewed adapters.

The bounded runtime now exposes Igor's canonical operational API with structured:

- inputs;
- owner;
- safety;
- privilege;
- preconditions;
- execution;
- deterministic verification where practical;
- per-capability recovery semantics rather than universal rollback;
- affected objects;
- platform requirements;
- secret-reference/access requirements where applicable.

The minimal structured plan model supports ordered capability steps for
installation, configuration, repair and migration proposals. A plan composes capabilities, exposes preconditions,
approval/privilege points, recovery semantics and verification before
execution. AI may propose/explain a plan; Igor resolves providers, authorizes,
executes and verifies it.

TUI, CLI, automation, healing and future external interfaces should invoke the same capabilities.

## Step 12 — Knowledge & Context Engine — BOUNDED WAVE E IMPLEMENTED

The current request boundary/reference envelope is a strong trust foundation. Preserve it.

**The bounded memory-domain Context Engine is implemented.** D039 and
[AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md) define bounded deterministic
selection, source kinds/provenance, active-owner filtering, sensitive-field
exclusion and inspection inside the current `IGOR_REFERENCE_V1` pipeline.
The memory slice selects current fact/health/capability/knowledge items without
dumping unrelated machine/module data. Other domains retain labeled legacy
context until their corresponding authoritative source and relevance mapping
are available.
Core context routing stays domain-neutral: modules/knowledge own domain vocabulary and semantic metadata, while model-derived topic/object hints remain non-authoritative inputs to deterministic retrieval. Adding a new domain must not require a new Core keyword/synonym routing branch (D040).

Extend the memory-domain cutover over time with composition of relevant:

- core operating guidance;
- System Model facts;
- active module knowledge;
- relationships;
- capabilities;
- relevant history.

Disabled modules contribute nothing. Reference material never becomes authorization policy.

Keep shipped/module knowledge separate from local learned artifacts. Evidence-
backed runbooks, patterns and successful investigation procedures may become
local learning with provenance, but they do not become executable authority
merely because the AI produced or used them.

## Step 13 — Domain Event Bus — COMPLETE

Do not confuse this with the existing AI frontend event stream.

The bounded contract is [EVENT_BUS.md](EVENT_BUS.md), accepted in D041–D043.
Core now validates a session-local domain bus and projects one
`capability.completed` signal from each committed canonical Wave E result.
Active v2 modules can declare owned event types and request publication
through the handler boundary. Read-only type and recent-event inspection is
available through `--events`. The real memory refresh and disposable service
failure fixture prove the first slice; [STATUS.md](STATUS.md) records the five
proof classes. Wave F remains incomplete.

Later structured operational event types may include:

- service.failed;
- container.stopped;
- disk.threshold_exceeded;
- backup.failed;
- capability.completed (including failed and unverified outcomes);
- module.enabled/disabled.

Events include Core-stamped source/owner, related objects, times, bounded
evidence references and correlation. They cannot authorize execution.

## Step 14 — Automation Engine — COMPLETE

The bounded implementation contract is
[AUTOMATION_ENGINE.md](AUTOMATION_ENGINE.md), accepted in D044–D047. Q008 is
resolved: modules propose; Igor's explicit administrator/runtime policy
activates. Step 14 owns durable configured intent, scheduling and bounded
run state. Every run enters the canonical capability dispatcher; only
unprivileged READ may run unattended in this step. Inspection precedes TUI
presentation. Step 13 events are transient signals, never approval or replay.

The version-1 registry, explicit operator activation, module proposal
boundary, persistence and read-only inspection were established in 14A.
One-time, periodic, event and typed `fact_equals` condition READ triggers
were added in 14B–14E. A condition tick uses an existing fresh, known System
Model fact and never refreshes an observer to make a predicate true. Every
admitted run retains the durable claim and canonical dispatcher boundary.
The five proof classes and regression results are recorded in
[STATUS.md](STATUS.md). Retries beyond one attempt and unattended CHANGE
require later explicit contracts; Step 15 owns durable history.

## Step 15 — Operational History — 15A ARCHITECTURE CONTRACT; RUNTIME FUTURE

Step 15A is the persistence/identity gate in
[PERSISTENT_MEMORY.md](PERSISTENT_MEMORY.md). D048–D054 resolve Q003 and
establish the rules that later history, investigations, resumable work,
deployments and learning must share without collapsing into one database or
authority.

The implementation sequence is deliberately bounded:

- **15A — Persistent Identity & Memory Foundation:** architecture only. Define
  scoped durable references, System Model persistence semantics, provider and
  correlation identity, evidence/provenance, ownership/lifecycle/reset and the
  canonical history hand-off. No broad runtime store is introduced.
- **15B — Operational History:** persist structured operational episodes from
  canonical Igor execution/results. Treat the current AI audit and recovery
  journal as migration inputs, not the permanent schema. State-changing
  attempts receive interruption/reconciliation semantics.
- **15C — Durable Investigations:** add a separate investigation lifecycle for
  problem/question, evidence, hypotheses, decisions, actions, findings,
  verification and resolution/status, linked to history/System Model by stable
  references.
- **15D — Inspection & Context Integration:** make the new authorities
  inspectable and selectively retrievable by the Context Engine without
  dumping raw history or turning investigation/learning text into authority.

Chat history is not operational memory. Step 13 events remain transient
signals and are not the only durability path. Persistent records refer to
scoped objects and canonical contracts/providers rather than handlers, paths
or UI names.

## Step 16 — Baselines — FUTURE

Use transparent operational history to learn normal ranges/behavior for this machine.

Also allow evidence-backed local learning such as patterns, runbooks and
symptom/cause/resolution relationships, stored outside installed module
packages with provenance and reset semantics.

Begin with explainable statistics and thresholds, not opaque ML. A learned baseline describes evidence about normal behavior; it is not desired state or responsibility. Learned artifacts remain reference material under D053 until an explicit authoritative transition exists.

## Step 17 — Relationships & Deployments — FUTURE

Separate:

- module/domain knowledge;
- instances on this machine;
- relationships;
- deployments.

Define provenance for discovered, configured, installer-created, user-declared and AI-proposed relationships. Relationship storage must preserve source claims/reconciliation instead of relying on unqualified last-write-wins edges. Durable participants use the scoped-reference contract from Step 15A so future local and external machine scopes do not require a new relationship identity model.

Installation/configuration workflows use structured plans and leave an
inspectable deployment/relationship record plus verification outcome, rather
than only a command transcript. [CONFIGURATION.md](CONFIGURATION.md) proposes
how canonical settings and deployment/instance scopes attach to this model.
[RESUMABLE_WORK.md](RESUMABLE_WORK.md) proposes durable waiting/resumption when
a workflow depends on OAuth, DNS propagation, reboot, user action or another
external condition. Neither proposal is runtime implementation yet.

## Step 18 — Composable Modules — FUTURE

Use the current `nextcloud_docker` deployment as the first composition proof case **after** v2 contracts exist.

Evaluate coherent independent domains such as Nextcloud, Docker and Cloudflare. Do not split PostgreSQL/Redis/etc. merely for purity.

Preserve the working v1 deployment during migration.

## Step 19 — Self-Healing v2 — FUTURE

Rebuild self-healing on normal Igor primitives:

```text
observation -> check -> incident -> diagnosis -> capability
            -> policy -> execution -> verification -> history
```

Automatic recovery considers safety, confidence, user policy, privilege, retries and prior outcomes. Before Self-Healing may perform unattended CHANGE, Step 19 must accept an explicit unattended-CHANGE authority contract; responsibility, Executive mode, automation eligibility, prior success or learned confidence do not themselves grant that authority.

## Step 20 — Igor TUI as Default — PARTIAL

The full-screen Codex-like TUI is already a strong interface.

Once normal system/module workflows use the shared backend foundations, make `./igor.sh` launch it by default.

The TUI consolidates inspection surfaces already introduced with modules,
configuration, facts, capabilities, plans, investigations, events and history;
Wave G is not the first point at which those systems become observable.
The proposed configuration-surface contract can let the TUI temporarily enter
a bounded setup workflow and return to the originating session, while resumable
work lets long external waits survive without keeping that UI open.

Keep CLI/headless paths for scripting, recovery, tests and automation. Preserve `--ai-tui` as a migration alias until removal is clearly safe.

## Step 21 — Integration Rules — FUTURE

Support lightweight knowledge/check/capability rules that only make sense when specific domains interact.

Avoid combinatorial giant modules.

## Step 22 — Module Developer Tooling & External Interfaces — PARTIAL/FUTURE

After Module API v2 is proven:

- converge module create/validate/test/inspect tooling on one supported path;
- generate v2 module skeletons;
- remove duplicate/experimental validators;
- make notification transports consume shared domain events;
- evolve notification/report delivery and authenticated email into the shared
  Admin Communications direction in [COMMUNICATIONS.md](COMMUNICATIONS.md): one
  transport/configuration foundation, replay-resistant authenticated inbound
  requests, and no parallel shell dispatcher;
- route future remote conversation and administration through shared
  capabilities, configuration, policy, privilege, verification and history;
- future API/webhook interfaces use the same engine and may also provide
  authenticated readiness callbacks for resumable work.

The current repository does not contain the old `core/mailcmd/` implementation;
do not plan a migration of code that is not present. Preserve the product intent
while replacing the old verb/command architecture with the shared external
interface. Remote privileged CHANGE and remote approval remain explicit Q011 /
Step 22 design work.

## Step 23 — Igor 2 Consolidation — FUTURE

Before declaring Igor 2 complete:

- remove obsolete v1 compatibility paths;
- remove dead hooks/helpers and duplicate validators;
- remove deprecated configuration paths only after the Configuration Service
  migration has an explicit source/target cutover and recovery proof;
- remove duplicate state/execution paths;
- update primary documentation to the final architecture;
- verify core is application-agnostic;
- run architecture-level regression suites;
- prove the Ownership Foundation and persistent migrations on an existing-style
  installation fixture;
- prove at least one real application workflow end-to-end through ownership,
  module/capability, approval/privilege, execution, verification and history;
- confirm every authoritative subsystem has an inspection surface and explicit
  ownership/provenance;
- confirm secret values stay out of normal AI context and secret access follows
  the secret-service/audit contract;
- confirm irreversible/best-effort recovery semantics are surfaced rather than
  hidden behind a generic rollback promise.

No compatibility path survives indefinitely without an explicit reason.

## Post-2.0 horizons

Keep extension points for, but do not staff as Igor 2.0 requirements:

- reviewed promotion of learned/AI-generated capability candidates into trusted
  executable code;
- module packs/marketplace and third-party signing/distribution;
- richer external adapters and interoperability;
- sophisticated dependency resolution beyond demonstrated need.
