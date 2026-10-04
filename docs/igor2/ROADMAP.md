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

Several **cross-cutting completion gates** now sit between the stable numbered
steps without renumbering them: Resource Discovery & Domain Recognition,
Configuration & Secrets completion, Provisioning & Installation, Resumable Work
runtime implementation, and the Step 20A/B/C operator-interface cutover. These
make previously implicit Igor 2 requirements explicit while preserving the
existing step references.

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
Imported knowledge/module candidates additionally retain source kind, upstream
project/document identity, version/tag/commit or retrieval point, license/provenance
where applicable and the transformation that produced the Igor-managed artifact.

The configuration foundation in [CONFIGURATION.md](CONFIGURATION.md) now has an
implemented Core-owned Configuration Service: versioned schemas, private
SQLite desired values, revision/state-token authority, the `ai.verbose` Core
slice, and the first real module-owned System memory-warning workflow. Modules
describe configuration meaning; Igor owns mutable values, validation,
persistence and migration. Secrets remain references-only and the broader
configuration/secret migration gate is not yet complete.

This remains a hard architectural gate, not a new wave name. Early
non-conflicting Wave C loader/contract work may proceed, but Wave C must not
freeze the remaining mixed config/secret/state layout into the public Module v2
contract. Broad application-module migration still waits for the unfinished
ownership/secret/binding work, even though the Configuration Service foundation
itself is now real and exercised.

## Igor 2.0 scope boundary

The A-H roadmap through Step 23 defines Igor 2.0. The knowledge/module import
foundation in [KNOWLEDGE_IMPORT.md](KNOWLEDGE_IMPORT.md) is part of that direction:
Igor 2 should preserve source provenance, keep portable package content separate
from machine binding/configuration, accept Agent Skills-style knowledge as a
bounded input, and give module developer tooling a normal import/normalize/
validate path.

Igor 2.0 also requires explicit closure for the reusable
[Resource Recognition](RESOURCE_RECOGNITION.md) seam, one real
[Provisioning/Installation](PROVISIONING.md) workflow, the owned
configuration/secret migration gate, a bounded
[Resumable Work](RESUMABLE_WORK.md) runtime slice, and the shared
[CLI/TUI operator interface](OPERATOR_INTERFACES.md). These are completion gates,
not new authorities or permission systems.

A full public marketplace/registry, third-party signing infrastructure,
sophisticated dependency solving, hot unload, a second handler-language adapter
and live AOH/ServerMind/Steward interoperability remain post-2.0 unless a
concrete requirement moves one into scope.

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

Imported documentation, Agent Skills/AOH material and other external knowledge
must enter through the same reference-data boundary. Source provenance survives
normalization; imported scripts/tool manifests remain candidate/reference
material until explicitly promoted through the normal Module API/capability
contract. See [KNOWLEDGE_IMPORT.md](KNOWLEDGE_IMPORT.md).

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

## Step 15 — Operational History — 15A ACCEPTED; 15B/JUDGMENT/15UI IMPLEMENTED; 15C COMPLETE; 15D IMPLEMENTED

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
- **15B — Operational History:** implemented through a versioned Igor-owned
  episode service with private SQLite persistence, pre-effect durable attempt
  identity, interruption/verification-only reconciliation, read-only CLI
  inspection and export/recovery/reset. The AI audit is a compatibility
  projection; the recovery journal retains noncanonical legacy callers. See
  [Operational History](../operational_history.md) and evidence in
  [STATUS.md](STATUS.md).
- **Decision/Judgment Contract gate:** the accepted D055
  [contract](JUDGMENT_CONTRACT.md) supplies a versioned, provider-neutral
  in-memory schema/interface with explicit abstain/unknown, provenance,
  validation and deterministic fallback. It has no operational authority,
  live transport, persistence, role/model selection or routing policy. See
  [STATUS.md](STATUS.md) for validation evidence.
- **15UI — Interaction Surface Foundation:** implemented after the judgment
  contract and before 15C: mouse scrolling, keyboard navigation/movable
  selection, explicit focus, a toggleable control panel and reusable typed
  schema/property rendering extend the existing TUI. The UI consumes backend
  inspection/edit contracts; it does not own configuration, history, AI
  routing, safety or authority. See [INTERACTION_SURFACE.md](INTERACTION_SURFACE.md).
- **15C — Durable Investigations:** implemented under D056 with a versioned
  local lifecycle, bounded hypotheses, evidence/history references, validated
  judgment attachments, investigation-scoped findings and unresolved questions.
  Private atomic JSON, export/restore, headless data operations and read-only
  15UI inspection grant no operational or current-state authority. See
  [INVESTIGATIONS.md](INVESTIGATIONS.md) and [STATUS.md](STATUS.md).
- **15D — Context Relevance and Model Role Routing:** bounded D057 implementation
  extends the existing Context Engine with deterministic selection, optional
  validated judgment ranking, explicit scoped history/investigation retrieval,
  reasoner/summarizer/context_ranker roles and administrator model bindings.
  Included/excluded reasons and routing rules are read-only CLI/15UI operational
  provenance, never durable knowledge or authority. No automatic ranker call,
  provider optimization or new context database. See [CONTEXT_ROUTING.md](CONTEXT_ROUTING.md)
  and final evidence in [STATUS.md](STATUS.md).

Chat history is not operational memory. Step 13 events remain transient
signals and are not the only durability path. Persistent records refer to
scoped objects and canonical contracts/providers rather than handlers, paths
or UI names.

## Step 16 — Baselines — FUTURE

The owner-scoped **Step 16 — Architecture Integration Review and Readiness
Assessment** is complete; see [ARCHITECTURE_READINESS.md](ARCHITECTURE_READINESS.md)
and [closure evidence](STATUS.md#step-16-architecture-integration-review-and-readiness-assessment--complete).
That documentation-only review does not implement the Baselines work below or
start Step 17. Configuration ownership, a representative application workflow
and cutover evidence remain readiness gates.

Use transparent operational history to learn normal ranges/behavior for this machine.

Also allow evidence-backed local learning such as patterns, runbooks and
symptom/cause/resolution relationships, stored outside installed module
packages with provenance and reset semantics.

Local experience may later be crystallized into a candidate Agent Skill/runbook
or module contribution through the same import/promotion pipeline used for
external knowledge. Promotion creates a reviewable candidate first; it does not
let Igor silently rewrite its installed executable modules.

Begin with explainable statistics and thresholds, not opaque ML. A learned baseline describes evidence about normal behavior; it is not desired state or responsibility. Learned artifacts remain reference material under D053 until an explicit authoritative transition exists.

## Step 17 configuration foundation — owner-scoped bounded implementation

After the Architecture Readiness Review, the Project Owner accepted Step 17A's
configuration architecture (D059) and authorized the foundation plus one Core
slice, `ai.verbose`. [CONFIGURATION.md](CONFIGURATION.md) defines schema/value
ownership, separate desired/effective/observed values, private SQLite hybrid
persistence, secret references, explicit precedence and migration/recovery.
[STATUS.md](STATUS.md) records the bounded implementation and evidence gate.

Configuration does not replace System Model, Operational History or canonical
application/verification. 15UI remains a typed proposal/inspection layer. This
step does not migrate module settings, Nextcloud, secrets, host thresholds or
broad environment variables, and adds no generic settings UI, inheritance,
external secret managers, agents or Steps 18/19/20. It does not close Q007 or
the whole Ownership Foundation.

The original Relationships & Deployments outcome below now proceeds under the
owner-scoped Step 19 architecture and separate implementation gates (D063).

## Original Step 17 — Relationships & Deployments — moved to owner-scoped Step 19

Separate:

- module/domain knowledge;
- instances on this machine;
- relationships;
- deployments.

Treat pre-existing/brownfield resources as normal machine-state participants even
when Igor did not provision them. Discovery may establish objects/facts and
relationship claims, while domain modules enrich interpretation; neither
discovery nor module activation silently creates adoption, desired state or
responsibility. File-backed configuration participating in a deployment must
retain a concrete file + stable selector locator, while non-file-backed values
identify their actual storage/source authority. See
[BROWNFIELD_ADOPTION.md](BROWNFIELD_ADOPTION.md).

The approved [Step 19 contract](DEPLOYMENTS.md) now defines provenance,
identity, claims/reconciliation and responsibility. Durable participants reuse
the scoped-reference contract from Step 15A. Boundary 1 implements only the
application-neutral foundation; attachment and application proof remain later
separately gated boundaries.

Installation/configuration workflows use structured plans and leave an
inspectable deployment/relationship record plus verification outcome, rather
than only a command transcript. [CONFIGURATION.md](CONFIGURATION.md) proposes
how canonical settings and deployment/instance scopes attach to this model.
[RESUMABLE_WORK.md](RESUMABLE_WORK.md) proposes durable waiting/resumption when
a workflow depends on OAuth, DNS propagation, reboot, user action or another
external condition. Neither proposal is runtime implementation yet.

## Step 18 — Composable Modules — architecture approved; bounded execution

The Project Owner approved Step 18A discovery (D060). Execution proceeds through
three boundaries, stopping with evidence after each:

1. **Contract completion:** versioned capability outputs/compatibility,
   structured module inspection, reproducible package knowledge and explicit
   read-only detach accounting.
2. **Composition prerequisites:** the owner-authorized integration proof uses
   the existing System package to cross registration, typed capability discovery,
   knowledge/context candidates, test-only configuration schema discovery and
   structured inspection through the existing 15UI renderer. It adds no production
   setting, application migration or live Modules panel.

   The required ownership/binding, relationship, storage, configuration
   source/target locator, secret and recovery seams remain bounded prerequisites
   for future composition workflows. D063 now settles Q007's architecture under
   Step 19; general application binding/adoption still requires its Boundary 2
   proof. The bounded Step 17 `ai.verbose` slice does not establish a complete
   ownership model.
3. **First reversible module configuration proof:** the owner-selected System
   memory warning threshold (`system.memory.warning_threshold_mib`, D062),
   default 150 MiB and range 81–4096 MiB. Desired validation/commit, module
   application, independent runtime readback, verification, History and explicit
   same-path recovery prove one real process-local consumer. Critical remains
   80 MiB; legacy `SYSTEM_RAM_WARN_MB` is not imported. Nextcloud, brownfield
   deployment/adoption and generic bindings remain later application work.

Contract completion does not certify real detach, migrate module settings,
implement instance/deployment authority or authorize broad splitting. The
implementation/evidence status is recorded in [STATUS.md](STATUS.md).

The initial [contract-driven Operator Surface](OPERATOR_SURFACE.md) is an
interaction/composition aid over those same registries: active v2 contributions,
capabilities and configuration declarations become discoverable through one
read-only projection and the TUI `:` namespace explorer. It does **not** add a
Module API menu kind, infer deployment ownership or make UI selection an
authority. Capability leaves re-enter the canonical dispatcher; required inputs
are never guessed. Rich generated module screens may build on this projection as
the relevant Step 18 contracts mature.

Broader application proof may later use the existing `nextcloud_docker`
deployment after its workflow-specific ownership prerequisites are satisfied.
It is not part of Boundary 3. The Operator Surface itself does not establish
deployment ownership, resource binding or recovery semantics.

Evaluate coherent independent domains such as Nextcloud, Docker and Cloudflare. Do not split PostgreSQL/Redis/etc. merely for purity.

A coherent Igor module/package may be authored natively or synthesized from
reviewed source material: installation documents, scripts, guides/runbooks,
Agent Skills/AOH, ServerMind/Steward material, other open-source projects or
local Igor learning. The source format is not the runtime contract. Import
normalizes material into Igor-managed knowledge/contribution candidates with
provenance, then the ordinary Module API/capability/compatibility rules apply.

Keep reusable package content separate from its machine binding. A module may
ship configuration schema and deployment knowledge, but instance paths, secret
references, selected providers, local relationships and mutable user intent
remain Igor-owned machine configuration/state.

Preserve the working v1 deployment during migration.

## Resource Discovery & Domain Recognition — FUTURE FOUNDATION GATE

The current Observer Framework establishes typed low-level facts, and Step 19's
Nextcloud attachment provider proves one narrow deterministic discovery path.
What is still missing is a reusable middle layer between observation and
adoption.

[RESOURCE_RECOGNITION.md](RESOURCE_RECOGNITION.md) defines the direction:

```text
observation -> domain recognition -> ephemeral candidate
            -> deterministic inspection -> frozen adoption proposal
```

A domain module/provider knows how to recognize the technologies it understands;
Core validates/co-ordinates candidates but does not hard-code what "looks like"
Nextcloud, Samba, Caddy, SSH tunnels or similar domains. A user may either ask
Igor to find a domain or point Igor at an exact candidate. A user hint narrows
selection; it is not machine truth or authorization.

This gate explicitly does **not** require a universal background scanner,
network-wide discovery, a persistent candidate database or AI-only recognition.
Start with targeted/user-hinted and bounded domain discovery. Inventory/event
driven recognition can grow later.

The existing Nextcloud B2 provider remains a valid narrow slice. Before that
shape becomes the template for additional domains, prove a reusable candidate
contract with Nextcloud plus one materially different resource/domain. Recognition
creates no deployment, desired state, responsibility or execution authority.

## Step 19 — Representative Application Workflow / Relationships and Deployment Ownership

The Project Owner approved [D063](DECISIONS.md) and [DEPLOYMENTS.md](DEPLOYMENTS.md)
after discovery. This owner-scoped step takes the original Relationships and
Deployments outcome; it does not start self-healing or Step 20.

One application-neutral Core-owned Deployment Service owns opaque scoped
identity, bindings, the small typed relationship vocabulary and positive,
explicit scoped responsibility. Its private transactional registry remains
separate from configuration, current observations, capability execution and
Operational History. Discovery/binding/observation/provisioned origin implies
no duty. Metadata-only adoption and resource-retaining release remain separate
from provisioning and destruction.

Implement three boundaries, stopping with evidence after each:

1. **Identity, relationships and responsibility:** generic registry, exact
   reference reuse/enrollment, preserved claims, transactional conflicts/CAS,
   idempotency, inspection and export/recovery. No application semantics.
2. **Brownfield attachment and composition prerequisites:** deterministic
   selection/inspection, metadata-only adoption, exact configuration locator,
   deployment target admission and bounded release/fencing proof.
3. **Reversible Nextcloud `loglevel` workflow and legacy cutover:** isolated real
   application proof of configuration, approved capability execution, native
   readback, History, prior-state recovery and release. Competing Igor writers
   for that adopted setting delegate or refuse.

Provisioning execution, general destruction, application upgrades, whole-module
migration, generic workflows, agents, self-healing and Step 20 are excluded.
See [STATUS.md](STATUS.md) for evidence, not merely architecture acceptance.

## Provisioning & Installation — FUTURE COMPLETION GATE

Brownfield adoption proves Igor can understand/manage selected parts of something
that already exists. Igor 2 must also have an explicit greenfield path for
creating external resources.

[PROVISIONING.md](PROVISIONING.md) owns this missing roadmap outcome:

```text
request -> preflight/frozen proposal -> approval
        -> canonical capability effects -> bind real native identities
        -> configure -> independently verify -> record deployment/history
```

Reviewed composite capabilities may implement bounded synchronous portions, but
provisioning is not a new workflow engine and does not add blind retry,
automatic rollback or a public executable plan API. Unknown effects reconcile
before another changing request. External waits use Resumable Work.

Provisioning follows the real Step 19 brownfield/application proof rather than
preceding it. The first provisioning vertical slice is separately selected and
must prove durable pre-effect intent, identity binding, verification, failure/
interruption reconciliation and explicit responsibility.

## Configuration & Secrets completion — FUTURE COMPLETION GATE

Step 17 established the correct Configuration Service architecture and bounded
real settings, but it deliberately did not migrate all module/application
configuration, secrets or legacy mutable sources. Boundary L/O/P later narrowed
and coalesced startup reads without creating a second configuration authority:
write/readback CAS and state-token proof remain on the full service path. See
[PERFORMANCE_INVESTIGATION.md](PERFORMANCE_INVESTIGATION.md) for the completed
performance pass and stopping rule.

Before Igor 2 consolidation, close the Ownership Foundation with evidence for:

- canonical configuration/source ownership across migrated Core/module settings;
- explicit source/target locators for application-backed values;
- secret references rather than secret values in ordinary configuration,
  context, History and UI;
- one real secret import/store/update/access/redaction/audit vertical slice;
- migration/cutover from selected existing secret/config sources without leaving
  competing writable authorities;
- inspectable desired/resolved/applied/observed distinctions;
- explicit reset/recovery behavior.

External secret-manager integrations are not required for Igor 2. The core
requirement is one authoritative local contract and safe migration.

## Resumable Work — FUTURE IMPLEMENTATION GATE

[RESUMABLE_WORK.md](RESUMABLE_WORK.md) already defines the architecture for
legitimate waits such as reboot, OAuth/device authorization, DNS propagation,
external readiness and user action. It still lacks a runtime proof.

This is separate from composite capabilities:

```text
composite capability = bounded operation happening now
resumable work       = durable work whose next step legitimately happens later
```

Implement one bounded vertical slice only after a real workflow needs it.
Persistent waiting state cannot grant future approval/privilege, replay unknown
effects or become a generic scheduler. Resume always revalidates dependencies,
providers, bindings and current policy.

## Original Step 19 — Self-Healing v2 — deferred, separately gated

Rebuild self-healing on normal Igor primitives:

```text
observation -> check -> incident -> diagnosis -> capability
            -> policy -> execution -> verification -> history
```

Automatic recovery considers safety, confidence, user policy, privilege, retries
and prior outcomes. Before Self-Healing may perform unattended CHANGE, a future
self-healing gate must accept an explicit unattended-CHANGE authority contract;
responsibility, Executive mode, automation eligibility, prior success or learned
confidence do not themselves grant that authority. Owner-scoped Step 19 does
not implement or approve that gate.

## Step 20 — Operator Interfaces / Igor TUI as Default — PARTIAL

The full-screen Codex-like TUI is already a strong interface, but Step 20 must
finish the operator experience rather than merely flip the default launcher.
[OPERATOR_INTERFACES.md](OPERATOR_INTERFACES.md) defines one backend contract
shared by CLI, TUI, automation and later APIs.

### Step 20A — First-class CLI

Make Igor usable directly from the command line without creating a parallel
command/permission system.

Target shapes include natural-language one-shot use, structured commands and
machine-readable output, for example:

```bash
igor "check why Nextcloud is slow"
igor discover nextcloud
igor deployments list
igor capability inspect docker.install
igor --json deployments list
```

Exact syntax is implementation work. Interactive CLI may enter the normal
approval/PTY privilege flow; noninteractive use must return approval-required
rather than answer approval/authentication on the user's behalf. CLI/headless
paths remain available after the TUI becomes default.

### Step 20B — TUI completion

Consolidate mature backend surfaces for:

- conversation plus clearly distinct capability/tool/activity/result output;
- pending questions, approval and privilege state;
- System facts/health;
- modules and availability;
- discovery/recognition candidates and ambiguity;
- deployments/relationships/responsibility;
- configuration with source/desired/applied/observed distinctions;
- capabilities/proposals;
- History and Investigations;
- resumable waiting work when implemented.

Color/style may distinguish user input, Igor text, commands/actions, results and
warnings, but meaning must not depend on color alone. Generated module/domain
views consume shared backend contracts; modules do not regain custom menu/UI
authority. Empty, stale, unavailable, failed-refresh and permission-required
states must be visibly different.

### Step 20C — Default-launch cutover

Only once representative system/module/application workflows use those shared
backend contracts should `./igor.sh` launch the full-screen TUI by default.

Preserve `--ai-tui` as a migration alias until safe removal. Keep CLI/headless
paths for scripting, recovery, tests and automation.

## Step 21 — Integration Rules — FUTURE

Support lightweight knowledge/check/capability rules that only make sense when specific domains interact.

Avoid combinatorial giant modules.

## Step 22 — Module Developer Tooling & External Interfaces — PARTIAL/FUTURE

After Module API v2 is proven:

- converge module create/validate/test/inspect tooling on one supported path;
- generate v2 module skeletons;
- add a bounded import/normalize/inspect path for external operational material,
  beginning with documentation/Agent Skills/reference assets and preserving
  source/license/provenance;
- allow scripts, ServerMind tool manifests, Steward/AOH material and local learned
  procedures to produce **candidate** observers/checks/capabilities/playbooks
  without becoming executable merely by import;
- show the normalized candidate/diff and validation/eval results before any
  reviewed promotion into executable Module API contributions;
- evaluate AOH-inspired source locks, owned-file manifests, safe-tree hygiene and
  convergent/crash-safe install semantics for the future package installer
  without making AOH a runtime dependency;
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

Additional Igor 2 completion evidence must also:

- prove reusable recognition/candidate selection without conflating it with
  adoption, using at least two materially different domains;
- prove one real provisioning/install path creates/binds/verifies resources
  without treating origin as blanket responsibility;
- prove one secret-consuming workflow keeps values outside ordinary
  context/History/UI while preserving inspectable references/audit;
- prove one durable wait/resume workflow across process restart without replaying
  a committed effect or reusing stale authority;
- prove the first-class CLI and default TUI use the same backend/capability
  semantics, including noninteractive approval refusal and structured output.

No compatibility path survives indefinitely without an explicit reason.

## Post-2.0 horizons

Keep extension points for, but do not staff as Igor 2.0 requirements:

- broad automatic promotion of learned/AI-generated capability candidates into
  trusted executable code beyond the reviewed candidate path;
- public module/knowledge registry or marketplace and third-party
  signing/distribution infrastructure;
- live richer external adapters/interoperability with AOH, ServerMind, Steward
  and other control planes;
- sophisticated dependency resolution beyond demonstrated need.
