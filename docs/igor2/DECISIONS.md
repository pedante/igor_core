# Igor 2 architectural decisions

Accepted decisions should not be repeatedly reopened without new repository evidence. Open decisions are resolved at the roadmap stage where they become necessary.

## Accepted

### D001 — Codex-like TUI is the primary human-interface direction

The structured full-screen TUI is the main Igor UX direction. CLI/headless paths remain for scripting, recovery, testing and automation. Long-term, `./igor.sh` should launch the primary TUI when migration permits.

### D002 — AI autonomy and OS privilege are separate

Guide/Assist/Executive determine interaction autonomy. They do not grant root. Privilege is authenticated/authorized by the runtime for the exact operation.

### D003 — Module presence is not module activation

A module existing under `modules/` is insufficient for runtime contribution.

### D004 — Core remains application-agnostic

Application/deployment-specific behavior belongs to modules or integration rules rather than core.

### D005 — Debian and Arch Linux are initial tested platform targets

Existing family detection/package mappings are useful seeds. Support is claimed only to the level tests demonstrate.

### D006 — Knowledge and observed state are different

Knowledge explains domains. The System Model represents what is known about this machine.

### D007 — Capabilities are the shared operational API

TUI, CLI, healing, automation and future external control converge on shared capabilities instead of duplicate domain operations.

### D008 — Modules may declare automation; Igor owns scheduling

Scheduling, policy, retries, privilege, execution and history are runtime responsibilities.

### D009 — Modules compose through instances/relationships

Prefer coherent reusable domain modules plus deployment relationships over monolithic combination modules when the separation provides real reuse. Do not split working modules before composition contracts exist.

### D010 — Mail control, if reintroduced, is an interface

The current tree does not contain the old `core/mailcmd/` implementation. If authenticated mail control returns, it must invoke shared Igor capabilities/safety/privilege/verification/history. Notifications remain conceptually separate from incoming control.

### D011 — Operational memory is not chat history

Incidents/actions/outcomes belong in structured Igor-owned history.

### D012 — Cleanup is continuous

A new authoritative path retires the superseded path when safe. Final consolidation is not an excuse to leave duplicates active indefinitely.

### D013 — Preserve the current AI reference-data trust boundary

Module prose, context, logs, reports, tool results and history summaries are reference data. They can inform reasoning but cannot authorize actions or modify deterministic policy.

### D014 — Frontend events and domain events are different contracts

`core/ai/events.sh` is a valuable frontend activity stream. The future Domain Event Bus represents operational events consumed by automation/healing/notifications/history. Do not conflate the two.

### D015 — Evolve the existing module activation runtime

Current enable/disable and owner-aware activation is the Module Runtime v2 starting point. Do not introduce a parallel module loader or rename state vocabulary solely for architectural cosmetics.

### D016 — Evolve the existing platform helpers

`distro.sh`, `pkg.sh` and Python resolution are the platform-abstraction starting point. Expand/test them rather than create a second distro layer.

### D017 — Module API v2 has a language-neutral contract and a Bash-first adapter (Q001)

The manifest, contribution descriptors and handler input/output envelope are
data contracts independent of implementation language. Wave C implements Bash
handlers through the existing loader; a Python handler adapter is added only
when a real module needs one. The API names domain contributions and their
requirements, while the adapter knows how to invoke a handler. This preserves
the two working Bash modules without making Bash hook names the public v2 API
or adding a plugin process manager now. Unsupported handler runtimes fail
validation clearly; they are not silently interpreted as Bash.

### D018 — Keep a small INI bootstrap manifest and use explicit JSON declarations (Q002)

`module.conf` remains the discovery and identity file. A v2 manifest declares
`module_api=2`, identity/version, handler runtime/entrypoint if needed, explicit
contract file paths and module-wide requirements. V2 parsing is strict and
section-aware; the permissive first-key v1 parser remains compatibility only.
JSON files named by the manifest contain optional contribution descriptors and
can be split only by explicit path, never directory auto-discovery. Python's
standard library can validate them without a new dependency. TOML would imply
an unestablished Python 3.11 floor, YAML adds a parser dependency, and a large
INI manifest cannot express nested metadata cleanly.

### D019 — Dependencies are small, typed gates, not a solver (Q005)

A hard module dependency names an exact module and determines load order. An
optional module integration never activates its provider or blocks the base
module. A capability requirement names a canonical registered capability;
use it when the provider identity is irrelevant, and require one unambiguous
active executable provider. Module-wide requirements can block activation;
requirements on one contribution only withhold that contribution. Platform/runtime
requirements are checked by core before activation or invocation as declared.
Disabled, missing or failed providers never auto-enable; the dependent reports
an unavailable reason. V1 `depends_on` remains ordering-only compatibility;
v2 has no new ordering-only field until a concrete need arises.

### D020 — Core provides OS mechanisms; `system` owns host-domain meaning (Q006)

If an operation is needed to activate modules or offers a reusable Linux
mechanism without host-health meaning, it belongs in core/platform: distro
detection, normalized package/service/process/filesystem/user/network
operations, privilege, execution and registries. If it interprets host facts,
thresholds or administrative intent that should disappear when `system` is
disabled, it belongs in `system`: host observations, health checks, knowledge
and higher-level service administration. Modules request normalized operations;
core does not choose application-specific workflows. This rule applies on both
Debian and Arch. Moving existing files follows later steps and is not implied
by this decision alone.

### D021 — V2 evolves one activation runtime with explicit compatibility

The current discovered/disabled/active/unavailable states and restart-based
activation remain; no hot unload or new persistent state is needed. V2
declarations join one owner-stamped contribution index under the current
loader. V1 registrations are adapted into that index while legacy hook views
remain temporary for current consumers. A package may opt into v1 compatibility
alongside v2 declarations, but the same canonical contribution may have only
one execution path per consumer. Unsupported API versions or invalid v2
declarations make the module unavailable with a reason. Step 23 removes v1 only
after consumers, bundled modules and external-use checks are migrated.

### D022 — Initial v2 module trust is reviewed local code (initial Q004)

V2 executable modules remain trusted local code, not sandboxed plugins.
Unlike the v1 omitted-entry compatibility default, a newly installed v2
module requires an explicit enabled policy entry before its code can run.
Migrating an already active bundled module must preserve its prior policy by
writing or carrying an explicit enabled entry; a disabled entry remains
disabled. Module knowledge and handler output are reference data for AI,
never approval or privilege. Executable capability metadata may declare a
privilege requirement, but Igor's existing runtime remains the authority for
authorization and OS authentication. A future third-party trust model can add
provenance/permissions without changing the contribution envelope.

### D023 — Core is internally separated into testable services/components

Core remains one conceptual authority boundary, but configuration, secrets,
canonical paths/ownership, persistent state, module registration, capability
registration, compatibility, authority/privilege, events, machine memory,
context/AI and provenance/audit must not become one undifferentiated global
implementation. This is a contract/dependency rule, not a microservices
requirement.

### D024 — Roadmap completion is evidence-based

A foundation/wave is not complete because its design prose exists. Completion
requires the relevant proof categories defined in EXECUTION.md: contract,
regression, real vertical slice, inspection, and migration/recovery where
persistent state/contracts change. Exit criteria should be falsifiable and
automated where practical.

### D025 — Observability begins with subsystem authority

A subsystem exposes a minimal inspection surface when it becomes authoritative.
Later TUI work consolidates those surfaces; it does not postpone observability
until the UI consolidation step.

### D026 — Persistent ownership classes are explicit

Code/package content, configuration, secrets, persistent state, machine memory,
knowledge, learned local artifacts, investigations, operational history and
disposable runtime have distinct ownership/lifecycle semantics. Modules may
declare schemas/contributions but do not store mutable machine-specific state
inside their installed package.

### D027 — Secret use is mediated and auditable

Secret storage and secret use are separate concerns. Secret values do not enter
AI context by default. Consumers should receive references or non-secret status
where sufficient. Authorized value access is mediated by Igor and should be
auditable where practical without logging the value.

### D028 — Recovery semantics belong to capabilities/plans

Igor does not guarantee generic rollback for arbitrary system work.
State-changing capabilities declare recovery semantics such as reversible,
best-effort, compensating action, snapshot-required or irreversible. Plans
surface these semantics before execution and verify recovery/compensation where
practical.

### D029 — Machine memory separates observed state, desired state and responsibility

Igor-owned structured memory distinguishes what is observed, configured or
user-declared, desired, inferred, stale/unknown and what Igor has been asked to
maintain/watch. Investigation findings and verification outcomes may reference
this model. Chat history is never the authoritative substitute.

### D030 — Multi-step system work uses structured plans

Installation, configuration, repair and migration workflows compose registered
capabilities into inspectable plans with preconditions, ordered steps,
approval/privilege points, affected objects, recovery semantics and
verification. AI may propose/explain plans; deterministic Igor runtime resolves
providers, authorizes, executes and verifies them.

### D031 — Persistent migrations require explicit cutover and recovery

Any change to persistent layout or contract defines source, target, validation,
idempotency/re-entry, verification, recovery/backup behavior where needed and a
cutover rule that prevents indefinite dual-source ambiguity.

### D032 — ServerMind and Steward are design influences, not dependencies

The discovery/machine-model lessons adopted from ServerMind and the durable
state/desired-state/planning/investigation lessons adopted from Steward are
recorded in INFLUENCES.md. Igor adapts those ideas to its own local Linux,
module, capability and deterministic authority model; no compatibility or
runtime dependency on either project is implied.

### D033 — System Model facts have independent state-class slots (Wave D)

The canonical fact key is `(object_id, property, state_class)`. `observed`,
`configured`, `user_declared`, `desired` and `inferred` are distinct slots;
`known`, `unknown`, `stale` and `not_observed` are separate availability states.
Intent never overwrites observation. Responsibility is a separate sourced
`watch`/`maintain` record, not a fact value or execution authorization. Core
owns typed validation, provenance, freshness and inspection. The minimum
record, object identifiers and source rules are in
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md).

### D034 — Igor commits observer output through one validation boundary (Wave D)

Active v2 observers return declared typed data through the existing handler
envelope. Igor stamps identity/time, validates the complete response and
commits it to the System Model. Modules cannot write internal storage or
declare themselves authoritative. Refresh is explicit/on-demand and bounded;
there is no Wave D scheduler. A failed/invalid/timeout refresh makes prior
values stale or new slots unknown without deleting last evidence. Privileged
observers cannot create another sudo path. See
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md).

### D035 — One structured check result feeds existing health workflows (Wave D)

One active-owner check registry/runner produces reusable structured results.
Diagnose and Healing retain their distinct workflows and receive projections
from the same result. V1 `CHECK:` and `CHECK_RESULT` are compatibility inputs
until each canonical check cuts over; one pass must not execute that check
twice. Health text and remediation references are advisory and cannot
authorize an action. See [HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md).

### D036 — Wave D defers a persistent observed-fact backend (Q003 remains open)

Rebuildable observations and health results may be runtime snapshots. Existing
authoritative configuration/user policy or verified installer records remain
the persistent source for configured, desired and responsibility intent where
such source exists; Wave D rehydrates them through a backend-independent
System Model interface and adds no general intent editor or fact database.
Absent sources remain absent. Q003 still decides whether observed snapshots or
history need durable storage before Step 15. See
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md).

### D037 — One canonical capability registry extends the owned action catalog (Wave E)

Step 11 extends the Wave C owner-stamped contribution index and existing
`run_igor_action`/AI dispatcher, not a second execution catalog. Canonical
dotted IDs identify observable operations; reviewed adapters explicitly map
v1 actions into them. One active executable provider resolves automatically;
multiple active providers are ambiguous unless the caller explicitly selects
one. Inputs, tier/privilege floor, preconditions, affected objects,
verification and recovery are validated contract metadata. Igor freezes the
resolved operation before the existing approval and PTY privilege gates;
provider output cannot alter authority. Process success and deterministic
postcondition success are separate result fields. A minimal ordered plan is a
resolved composition of those same capabilities, not a new execution engine.
See [AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md).

### D038 — Raw shell is a stricter unstructured fallback (Q010, Wave E)

AI uses a registered available capability for a recognized equivalent
operation. It may use bounded allowlisted shell READ discovery where no
structured capability fits. AI-proposed raw CHANGE requires explicit
approval even in Executive; raw DESTROY still requires exact `YES` in every
mode. The existing denylist, validation, privilege and exact-command gates
remain. Known equivalent shell forms are rejected at dispatch in favor of
the capability; unavailable/disabled domain providers do not authorize an AI
shell workaround. Shell has no implied verifier or recovery: record it as
unstructured with verification unavailable unless a separate named
deterministic postcondition ran. An operator's explicit OS command remains
subject to the shell interface's safety policy, independent of module
activation. See [AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md).

### D039 — Context selection stays inside the AI reference boundary (Wave E)

Step 12 adds deterministic, bounded selection and item-level provenance to
the existing context pipeline and `IGOR_REFERENCE_V1` envelope. It selects
real System Model/health records, active module knowledge, available
capabilities and other existing non-secret sources by intent/object/owner,
freshness and severity. Disabled owners contribute nothing. Shipped
knowledge, observed/inferred state and local learning retain distinct kinds;
all are AI reference data, never authorization or System Model truth. Secret
values are excluded before composition and redacted again at transport.
Provider adapters render the same Igor semantics without becoming policy.
See [AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md).

### D040 — Context semantics live in modules/metadata, not Core routing tables

Core's Context Engine remains domain-neutral. It may select and rank generic
registered structures by object/capability identity, owner, source kind,
provenance, freshness and module-provided concepts/tags, but it must not grow
application-specific natural-language keyword/synonym branches. Modules and
knowledge contributions own domain vocabulary/semantic metadata. The reasoning
layer may translate user language and conversational references into
non-authoritative topic/object/intent hints; Igor deterministically resolves
those hints against registered active sources. Such hints cannot create facts,
capabilities or owners, assert freshness, activate modules, satisfy
preconditions or affect authorization. Adding a new coherent domain module
should not require Core routing changes. See
[AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md).

### D041 — Domain events are validated signals with Core-stamped provenance (Step 13)

Core declares built-in types; active v2 modules may declare owner-namespaced
types through the existing contribution index. Core stamps event identity,
source, owner and times, validates the declared bounded payload, and rejects
unknown/inactive/malformed events before delivery. Events, including module
events, are reference signals and cannot authorize operations, approval,
privilege, verification or activation. See [EVENT_BUS.md](EVENT_BUS.md).

### D042 — Step 13 delivery is session-local and best effort

The initial bus validates and publishes synchronously to trusted Core
subscribers, with a bounded session-local inspection buffer. Subscriber
failure cannot change a canonical capability result. There is no retry,
replay or restart guarantee; disposable runtime scratch is not operational
history. Step 15 owns durability. See [EVENT_BUS.md](EVENT_BUS.md).

### D043 — Capability completion is the first domain-event projection

After a canonical Wave E capability result is committed, Core emits one
`capability.completed` event for any terminal outcome. Its execution,
verification and final outcome fields retain their distinct result meanings;
`completed` does not mean successful. The current frontend event stream, v1
actions and raw shell are not silently reinterpreted as domain events. See
[EVENT_BUS.md](EVENT_BUS.md).

### D044 — Module automation declarations are proposals; policy activates (Q008, Step 14)

Modules cannot activate an automation by installation, enablement, manifest
or handler. Igor's validated registry creates disabled instances from active
module proposals or explicit operator configuration. An authenticated
operator or explicitly configured trusted Core administrator policy enables,
edits, disables or deletes them; AI/reference text and domain events cannot.
Disabled/removed proposal owners make dependent instances unavailable without
deleting user intent. See [AUTOMATION_ENGINE.md](AUTOMATION_ENGINE.md).

### D045 — Step 14 unattended execution is unprivileged READ only

Enablement grants eligibility for an exact configured READ, not blanket
approval for future operations. Guide does not auto-run; Assist/Executive
use the normal READ policy at each run. CHANGE/DESTROY and privileged targets
cannot be enabled in Step 14. Existing interactive Executive CHANGE policy
and DESTROY exact-`YES` do not become durable scheduler permissions. A later
unattended CHANGE policy needs its own explicit contract and the existing
privilege broker. See [AUTOMATION_ENGINE.md](AUTOMATION_ENGINE.md).

### D046 — Automation owns versioned intent and at-most-once slot claims

Core stores configured instances and minimal schedule/last-attempt state in
its private versioned persistent-state store. It atomically claims a due slot
before dispatch; a crash leaves an inspectable unknown attempt rather than
silently repeating it. Event/condition signals and run locks are transient.
This store is neither the System Model persistence decision Q003 nor Step 15
Operational History. See [AUTOMATION_ENGINE.md](AUTOMATION_ENGINE.md).

### D047 — Triggers make canonical READ invocations eligible

Step 14 adds one-time, periodic, exact-filtered Step 13 event and typed
deterministic condition triggers in bounded slices. A trigger never changes
the configured target or invokes a provider itself. The automation adapter
enters the Wave E `run_capability` dispatcher for each run. No event replay,
cron expressions, shell predicates or general workflow engine are implied.
See [AUTOMATION_ENGINE.md](AUTOMATION_ENGINE.md).

### D048 — System Model remains current-state projection; durable history is separate (Q003, Step 15A)

Q003 is resolved at the architecture level. The System Model remains Igor's
current structured view, not the general historical database. Configured,
user-declared, desired and responsibility state survives restart through its
authoritative source and is rehydrated through source adapters. Inferred state
is recomputed from its named inputs/rules. Observed facts may be cached for
offline explanation, but after restart a cache is reference/stale evidence
until a trusted observer refreshes it; persistence alone never makes an old
observation current or known. Historical observations, operation outcomes and
verification belong to Step 15 Operational History. The System Model service
contract remains independent of its backing store. See
[PERSISTENT_MEMORY.md](PERSISTENT_MEMORY.md).

### D049 — Durable object references are explicitly scoped

Existing local object IDs such as host:local and service:systemd:sshd.service
remain valid inside one Igor scope. New durable cross-subsystem records use a
scoped object reference: stable scope identity plus the existing object ID.
The scope identity is opaque Igor-owned identity, not hostname, IP, MAC,
filesystem path or another mutable machine attribute. Restoring the same
managed installation may preserve its scope identity; cloning or onboarding a
distinct managed machine must not silently reuse it. This preserves current
local APIs while leaving room for future remote/external machine scopes.

### D050 — Durable operational references name contracts/providers, not handlers

Operational history records the canonical capability ID and version, selected
provider identity/owner/source and execution scope. A Bash function, command,
module path, process ID or UI action name may be diagnostic evidence but is not
the durable operation/provider identity. Provider selection and execution
location remain separate concepts so a future local, remote or adapter-backed
provider can implement the same canonical capability without changing history
semantics.

### D051 — Operational durability attaches to the canonical execution boundary

Step 15 history must not depend on the transient Step 13 event bus as its sole
durability path. Domain events remain reactive signals. Durable operation
records attach to the canonical capability/plan execution boundary. For
state-changing work, the Step 15 implementation must durably identify the
attempt before provider invocation and retain enough frozen proposal,
authority and correlation data to distinguish never-started, running,
terminal and interrupted-unknown outcomes. A crash after possible external
effect is reconciled through verification/explicit recovery rather than
blind retry. History failure never rewrites an already committed capability
result into success or failure.

### D052 — History, investigations, work, deployments and learning are separate authorities

Operational History answers what happened. Investigations own durable
problem-solving state. Resumable Work owns current plan/wait/resume state.
Deployments/relationships own installed topology and reconciliation.
Learning owns evidence-backed reusable local experience. These systems may
share a private physical backend later, but they keep separate logical
contracts, lifecycle/reset semantics and inspection APIs. They cross-reference
one another through stable IDs/evidence references rather than copying each
other into one universal memory record.

### D053 — Learning is reference material until explicitly promoted

Baselines, learned patterns, runbooks, symptom/cause/resolution relationships
and AI-extracted local experience retain provenance/evidence and remain
reference material. They cannot silently create desired state, responsibility,
automation enablement, approval, privilege, policy or executable capability.
Any future promotion into trusted executable behavior is a separate reviewed
post-2.0 authority transition.

### D054 — Persistent backends are private and replaceable

Public/runtime contracts expose services and versioned records, not database
tables, JSON filenames or directory layouts. A subsystem may use SQLite,
versioned JSON or another private backend where implementation requirements
justify it, and several logical authorities may share one physical database,
but ownership boundaries remain explicit. Every schema/layout migration follows
the existing source/target, validation, idempotency, cutover, verification and
recovery discipline. Cross-store references tolerate an unavailable/pruned
target and never reuse an old durable ID for a different meaning.

### D055 — Model judgments are provider-neutral reference records

The Project Owner accepted the bounded
[Decision/Judgment Contract](JUDGMENT_CONTRACT.md): one versioned, in-memory
Igor envelope, caller-owned bounded kind/output schema, and an injected
tool-free adapter. Igor validates output and retains input/reference and
invocation provenance. Valid, abstain, unknown, invalid output, provider
failure, unavailable and timeout remain distinct; a caller-chosen validated
default provides deterministic fallback without another model call.

Judgments have no authority over facts/freshness, activation, registration,
operational provider selection, safety, approval, privilege, preconditions,
automation, desired state, responsibility, verification, recovery or secrets.
No live-provider wiring, persistence, roles, routing/model selection, agents,
15UI, 15C or 15D implementation is accepted by this decision. MODEL_ROLES and
AI_SPECIALISTS remain proposals; actual relevance/routing policy belongs to
15D. Future transports reuse the existing provider/privacy boundary.

### D056 — Investigations own bounded durable knowledge organization

The Project Owner confirmed the [Step 15C contract](INVESTIGATIONS.md): a small
versioned local investigation record, explicit lifecycle/terminal immutability
and reasoned reopening, bounded hypotheses, typed provenance-bearing evidence
references and validated Judgment Contract attachments. Conclusions remain
investigation-scoped findings; creation owner/provenance creates neither
operational authority nor responsibility.

Private versioned JSON uses locking, atomic updates, fail-closed validation and
export/idempotent continuation restore. Local identity is reused through the
Operational History service; no second history database or history schema
change is introduced. Python/headless data operations and read-only 15UI
inspection expose the owner state without execution, fact mutation/freshness,
approval, privilege, module activation, automation or verification authority.
Agents, workflows, remediation, routing/15D and Step 20 remain deferred.

### D057 — External knowledge import normalizes before authority

The Project Owner accepted the direction in
[KNOWLEDGE_IMPORT.md](KNOWLEDGE_IMPORT.md): installation documents, scripts,
guides, native Igor modules, Agent Skills/AOH, ServerMind/Steward material and
local learned procedures may all be source material for Igor-managed knowledge
or module candidates.

Import preserves source/provenance and normalizes material into existing Igor
concepts. Imported prose, scripts, tool manifests, skills and source-runtime
guardrails are reference/candidate material by default. They cannot activate a
module, create System Model truth, grant desired-state/responsibility,
authorize an automation, select approval/privilege, or become an executable
capability merely because the source expressed one.

Executable promotion is a separate reviewed transition into the normal Module
API/capability contract, where Igor recomputes and enforces safety, privilege,
preconditions, verification, recovery and ownership. Agent Skills compatibility
and AOH-style Pack/Binding separation may inform the import format, but no
external pack schema becomes Igor's native authority contract.

### D058 — Igor owns bounded context relevance and model-role routing

The Project Owner confirmed [Step 15D](CONTEXT_ROUTING.md): extend the existing
Context Engine with deterministic candidate eligibility/relevance, optional
validated D055 ranking assistance, and bounded operational provenance. Initial
provider-neutral roles are reasoner, summarizer and context_ranker; explicit
administrator bindings and inspectable rules/reasons select the model. There
is no provider optimizer, automatic ranking call or cross-provider fallback.

Context/routing records are operational provenance only, not durable knowledge
or memory unless explicitly stored through an owning Igor subsystem. They use
disposable session state and the existing optional bounded private AI audit,
with no new durable context database or history/investigation schema.
Read-only CLI and 15UI inspection expose included/excluded reasons and routing
rules, not just a selected role. Selection cannot execute, approve, grant
privilege, refresh facts, alter System Model truth or bypass security policy.
Judgments remain reference-only. Agents, autonomous gathering, embeddings,
compression services, provider optimization, background AI, Jet/Laya and Step 20
remain outside this decision.

---

### D059 — Core owns validated desired configuration; application stays separate

The Project Owner accepted Step 17A's configuration architecture and authorized
the bounded Step 17 foundation plus one Core slice, `ai.verbose`. The contract
is [CONFIGURATION.md](CONFIGURATION.md); implementation and proof are recorded
in [STATUS.md](STATUS.md).

Core's Configuration Service owns schema admission, scoped desired values,
validation lifecycle, deterministic precedence, revisions, persistence,
provenance and migration/recovery. Modules declare meaning, defaults, types and
domain semantics through a versioned configuration contribution; they do not
own security-critical storage semantics. A private SQLite store with readable
export/recovery and separate secret storage is selected for atomic updates and
concurrent revision checks, not because another subsystem uses SQLite.

Declared defaults, durable desired values, resolved effective inputs, temporary
overrides and observed runtime state are distinct. Configuration is never a
replacement System Model: desired or resolved values do not prove runtime
application. System Model owns observed state; canonical capabilities own
application and verification; Operational History owns operation outcomes.
Configuration stores secret references only; Secret Service owns material and
mediated access. 15UI renders safe projections and submits typed proposals.

Durable identity uses Igor scope/object/setting references, not handlers,
paths or labels. Explicit supported session/environment overrides are validated
and inspectable; legacy files retain their rules only for unmigrated settings.
Each cutover names sources, validates before commit, preserves recovery,
supports idempotent re-entry and removes competing write authority.

The first implementation does not migrate Nextcloud, module configurations,
secrets, host thresholds or broad environment variables. It adds no generic
settings UI, external secret manager, inheritance, agent, self-healing or later
roadmap work. Q007 and Q012 remain open; this bounded foundation does not close
the entire Ownership Foundation gate.

### D060 — First-class modules extend v2 under Core-owned authority (Step 18A)

The Project Owner approved the Step 18A discovery proposal and its three
sequential boundaries: contract completion, composition prerequisites, then
one reversible application proof. Each boundary stops with its own evidence
report before scope expands. [MODULE_API.md](MODULE_API.md) defines the module
contract; [EXECUTION.md](EXECUTION.md) supplies the five proof classes.

A module is a portable reviewed package for a coherent domain. Package content,
registration, Igor-owned machine bindings and operational records are distinct.
Modules contribute knowledge, schemas, capabilities and domain implementations.
Core owns identity admission, lifecycle enforcement, dependency evaluation,
security, approval, privilege, configuration authority, execution policy,
provenance and Operational History. No module-specific operating runtime or UI
is introduced. Module API v1 remains temporary compatibility, not the extension
point for new functionality.

Knowledge explains domains; System Model represents current typed state;
History records operational attempts/outcomes; Investigations organize questions
and evidence; Context Routing selects eligible reference material. None of the
reference consumers can activate modules, invent capabilities or alter policy.
15UI consumes structured owning-service inspection and submits typed proposals.
Configuration retains D059's authority split; portable schemas/defaults do not
give modules ownership of mutable desired values or secret material.

Capability outputs and compatibility become explicit versioned contracts while
Core retains provider resolution, input/output validation, approval, privilege,
verification and history. Provider completion and valid output are separate;
invalid output after execution cannot erase a possible effect or imply success.

Detach ends hidden management participation/responsibility, not necessarily
application resources or retained evidence. Inspection must account for known
dependencies and contributions, retained data, running processes and missing
inventories. Contract completion may expose an incomplete read-only assessment;
it must not certify detach before binding/resource ownership is established.

The approved scope excludes broad module migration, structural splitting without
a proven workflow need, marketplaces, automatic dependency installation, hot
unload and autonomous module generation. Reviewed local executable modules are
not sandboxed. Third-party isolation/signing remains Q004 and future work.
Q007's relationship/deployment reconciliation is not closed by this approval or
the bounded Step 17 configuration foundation.

### D061 — Brownfield resources remain machine state; adoption and configuration location are explicit

The Project Owner directed Igor 2 to support existing installations that Igor
did not deploy. [BROWNFIELD_ADOPTION.md](BROWNFIELD_ADOPTION.md) records the
refinement.

Machine resources are represented by their owning System Model/relationship
services, not stored inside a module package. Modules may contribute recognition,
domain observations, knowledge and capabilities, but discovery or module
activation does not create desired state, responsibility or management
authority. An externally created/unknown-origin resource may be discovered and
understood before any explicit adoption. Adoption is a separate authoritative
transition and preserves the original provenance.

Configuration values are location-transparent in identity but location-explicit
in provenance. Every file-backed configuration value used by Igor must expose a
concrete file plus stable selector; non-file-backed values must identify their
actual storage/source authority rather than a fabricated path. Application
read/write bindings and imported-from provenance remain inspectable. Filenames,
line numbers and Configuration Service's private backend path never become the
durable setting identity, preserving D054/D059 and backend replaceability.

This decision constrains Q007 but does not close it. Step 17 still must define
how competing discovered/configured/installer/user relationship claims reconcile,
and Step 18 still must implement/prove the binding, adoption and reversible
application path. No broad discovery engine, module migration or ownership
transfer is implemented by this documentation change.

### D062 — First reversible module configuration proof uses System memory warning policy

The Project Owner approved Step 18 Boundary 3 using
`system.memory.warning_threshold_mib`: a System-owned schema declaration with
Core-owned desired configuration. The default is 150 MiB, the integer range is
81–4096 MiB, and the independent critical boundary remains 80 MiB.
`SYSTEM_RAM_WARN_MB` is not imported or made a competing authority.

The bounded lifecycle separates validation and approved authoritative desired
commit from module application, independent READ runtime readback, verification
and Operational History. Configuration is not runtime truth. Failed application
and failed verification remain visible without false success; recovery is an
explicit new approved change through the same path, with no automatic rollback.
The proof is process-local System health policy, not OS memory configuration.

This owner-approved workflow replaces the earlier proposed Nextcloud Boundary 3
selection. It does not establish generic deployment/binding/adoption, complete
detach, a settings UI, AI decisions or System Model facts from configuration.
Broader application integration, Steps 19/20 and third-party trust remain deferred.
Q012 is resolved for this warning setting only; other host thresholds retain
their existing executed behavior and require separately bounded migration.

### D063 — Deployment identity, relationships and scoped responsibility (owner-scoped Step 19)

The Project Owner approved the Step 19 discovery proposal and additional
constraints, recorded in [DEPLOYMENTS.md](DEPLOYMENTS.md). One Core-owned,
application-neutral Deployment Service owns durable deployment identity,
bindings, relationships and explicit responsibility. Version 1 has one
deployment concept with opaque Igor-owned scoped identity; existing resource
references are reused rather than duplicated. The relationship vocabulary is
`includes`, `depends_on`, `uses` and `exposes`.

Responsibility is positive, explicit and scoped. Discovery, knowledge, binding,
observation and Igor-provisioned origin imply no responsibility. Preserve
competing claims; accepted bindings change through explicitly authorized,
revision-checked transitions, never unqualified last-write-wins. Shared-resource
and setting conflicts remain visible. The private transactional SQLite registry
has versioned inspection/export/recovery and does not become a generic workflow
engine. It owns only the minimal transition state needed for its consistency.

Modules remain portable contributors. Configuration owns desired values,
System Model owns observations, capabilities own deterministic approval,
privilege, execution and verification, and History owns attempts/outcomes.
Deployment configuration targets wait for deployment identity. Metadata-only
adoption, provisioning, release/detach and destruction are distinct; no generic
rollback is promised. Inspection uses the existing generic backend/15UI model.

Execution proceeds separately through Boundary 1 identity/relationships/
responsibility, Boundary 2 brownfield attachment/composition, and Boundary 3 an
isolated reversible Nextcloud `loglevel` workflow with equivalent legacy writers
subordinated or refused for the adopted setting. Each boundary stops with
evidence before the next starts. Boundary 1 is application-neutral. Provisioning
execution, general destruction, application upgrades, whole-Nextcloud migration,
generic workflows, agents, self-healing and Step 20 remain excluded.

This settles Q007's architecture: provenance-bearing claims are retained;
deterministic approval/CAS controls accepted topology and responsibility;
conflict/drift is explicit. It does not claim brownfield/runtime proof before
Boundaries 2/3. General integration-rule packaging Q009 remains deferred.

### D064 — Typed Investigation findings require explicit evidence relationships (Step 16C)

The Project Owner approved the bounded Step 16C extension to
[INVESTIGATIONS.md](INVESTIGATIONS.md). Investigation schema version 2 adds
stable typed findings for `symptom`, `cause`, `action` and `verification`
without changing the authority of Investigations or reinterpreting existing
free-form findings.

A typed finding binds an immutable kind/statement to explicit attached evidence,
optional hypotheses/judgments and an assessment of `supported`,
`contradicted` or `inconclusive`. Supported/contradicted assessments require
evidence recorded as available on the asserted side. Supported actions
additionally require operation/capability-result evidence; supported verification
findings require verification evidence. Resolution of an Investigation never
promotes a claim automatically.

Existing version-1 stores remain readable/exportable without migration.
Ordinary legacy mutations may remain v1. The first successful typed-finding
mutation performs one atomic additive v1->v2 document migration, preserving
existing semantics and adding empty typed-finding collections before applying
the explicit change. Failed validation or interrupted persistence retains the
original v1 document. New stores use v2; v1/v2 export and restore preserve their
version.

Typed findings remain investigation-scoped reference knowledge. Cause does not
become a System Model fact, action does not grant execution permission, and an
Investigation verification claim does not replace canonical capability
verification/Operational History. This step adds no automatic inference,
runbook generation, Local Learning promotion/consumer change, model call,
remediation or execution authority.

### D065 — Local learning stores only explicitly reviewed evidence snapshots (Step 16B)

The Project Owner approved [LOCAL_LEARNING.md](LOCAL_LEARNING.md) for the
bounded Step 16B implementation. One Core-owned Local Learning Service derives
deterministic, bounded candidates on demand from canonical Operational History,
Investigations and explicit Step 16A baseline references. Initial types are
recurring terminal outcomes and attributed findings from resolved
Investigations. Statistical correlation alone does not establish cause,
resolution or verification.

Candidates are derived, not durably queued. Explicit review freezes the exact
candidate/derivation revision, content, applicability, provenance, disposition
and canonical evidence references in a private versioned snapshot. Source
records are referenced rather than copied. Revision/state-token comparison
rejects stale review; changed evidence requires a new candidate and review.
Lifecycle is candidate to accepted, rejected or superseded, and accepted to
superseded; rejected and superseded are terminal. Owner/module inactivity may
exclude an accepted artifact from active Context but cannot erase it or its
provenance. Explicit scoped reset/delete remains available.

Only accepted, eligible artifacts enter bounded Context retrieval. All learning
is reference-only and cannot set machine/desired state, responsibility,
approval, privilege, automation or executable capability. No legacy pattern or
session-note import/dual-write, causal pattern derivation, verified runbook
generation, automatic acceptance, or LLM dependency is introduced.

### D066 — Cross-incident patterns require repeated reviewed typed incident knowledge (Step 16D)

The Project Owner selected Step 16D after the Step 16B/16C learning foundation
was merged. Core may derive a `cross_incident_pattern` candidate only from
already **accepted**, still-current `typed_investigation_finding` Local
Learning artifacts. Raw Investigation prose, unresolved typed findings and
unreviewed incident candidates do not qualify.

The first bounded pattern is `symptom_cause`. It requires at least three
distinct resolved Investigations, each contributing one accepted supported
symptom and one accepted supported cause. The deterministic layer groups only
**exactly equal typed symptom text, cause text, related-object scope and
compatibility**. It does not use an LLM, embeddings, fuzzy matching or inferred
semantic equivalence. Similar wording remains separate evidence until a future
explicit proposal/review contract exists.

Pattern identity is semantic (scope, pattern kind, exact symptom/cause,
objects and compatibility), while revision includes the exact reviewed source
artifacts and retained History evidence. A fourth compatible incident therefore
keeps the pattern identity but creates a new revision requiring another explicit
review. Superseded/changed source learning makes stale review fail and remains
visible through evidence-status inspection.

The pattern remains `reference_only`. Repetition does not prove that every
future occurrence of the symptom has the cause, does not authorize diagnosis or
remediation, and does not create desired state, responsibility, permission,
automation or executable behavior. Step 16D deliberately excludes action/
verification procedure synthesis, runbook generation and capability promotion;
those require a later explicit contract.

### D067 — Reference procedures require an accepted pattern and same-operation passed verification (Step 16E)

The Project Owner selected Step 16E after Step 16D was merged. Core may derive
a `reference_procedure` only from an already **accepted, still-current**
`cross_incident_pattern` plus accepted typed `action` and
`verification` Local Learning artifacts from at least three of that pattern's
distinct Investigations.

The first bounded procedure kind is `single_action_verified`. Action and
verification text must match exactly across the contributing incidents, and
their object scope, compatibility and applicability owners must match the
accepted pattern. The initial contract is deliberately single-compatibility.

Investigation v2 does not encode a general “verification V verifies action A”
relationship. Therefore Step 16E may pair an action and verification only when
both reviewed typed findings reference the **same canonical Operational History
operation** in that incident. That operation must have
`execution_status=succeeded` and canonical `verification.status=passed`.
Separate operations, failed/unknown verification and prose-only association do
not qualify.

The candidate references the exact accepted pattern artifact, accepted action/
verification artifacts and one bound canonical operation per contributing
Investigation. Procedure identity is semantic (scope, procedure kind, pattern
candidate identity, exact action/verification, objects and compatibility);
revision binds the exact reviewed evidence. New evidence therefore requires a
fresh review without rewriting prior accepted snapshots.

A reviewed procedure is `reference_only` guidance. It grants no execution,
approval, privilege, automation, remediation, desired state, responsibility,
capability or executable runbook/playbook authority. Multi-step sequencing,
separate verification-operation relationships, semantic/fuzzy equivalence,
automatic acceptance and executable promotion remain later explicit contracts.

### D068 — OKF is a stateless reference-knowledge interchange boundary (Step 16F)

The Project Owner selected Step 16F after the reviewed Local Learning,
cross-incident pattern and reference-procedure semantics were established.

Igor owns Knowledge Artifact semantics. Open Knowledge Format is an interchange
encoding only; it is not Igor's memory runtime, trust authority, module format,
execution protocol or source of machine truth.

The initial portable profile targets **OKF v0.2** and exports one accepted Local
Learning artifact per bundle. The root `index.md` declares
`okf_version: "0.2"`; the concept is UTF-8 Markdown with YAML frontmatter and
uses standard OKF provenance/trust/lifecycle fields plus a producer-defined
`igor_artifact` extension for Igor's typed reference semantics.

Core remains dependency-free. The initial importer accepts one-concept bundles
using deterministic one-line JSON-compatible YAML values and simple scalar
frontmatter. Unsupported multiline/advanced YAML fails closed rather than
adding a general YAML runtime. Multi-concept/recursive bundle ingestion is
deferred.

Export is allowed only for **accepted** Local Learning. Import is validate and
normalize only: every imported concept becomes `reference_only`,
`untrusted_import`, and `persistence: none`. External `verified` metadata
is retained as provenance/trust evidence but never becomes Igor acceptance,
permission or authority.

Import does not write Local Learning, enter Context, alter System Model or
Configuration, create deployment/responsibility state, activate modules, grant
approval/privilege, create a capability/runbook, or execute anything. A later
explicit review/persistence contract is required before imported knowledge can
become active Igor reference knowledge.

### D069 — OpenRouter credential lifecycle and explicit local cutover (Ownership Boundary B)

Accepted by the Project Owner on 2026-10-05 after the Boundary A proposal.
[OWNERSHIP_FOUNDATION_PROPOSAL.md](OWNERSHIP_FOUNDATION_PROPOSAL.md) B1–B5
are approved for one OpenRouter credential only:

- **B1:** private SQLite metadata and separately protected immutable material
  generations, extending the existing secret-reference service. Configuration
  stores only the installation-scoped opaque handle; current path roots remain.
- **B2:** trusted Core transport, validation, balance and redaction bindings;
  durable registration cannot invent consumers. Mandatory value-free access
  audit precedes material release; audit failure denies access.
- **B3:** explicit source-selected import and durable single-source cutover.
  Environment credentials become import-only after cutover; missing/corrupt
  managed state never silently restores env/home/file/cache fallback.
- **B4:** one protected previous generation plus explicit approved local recovery
  or re-import. Ordinary exports contain metadata only. New ordinary backups
  omit selected managed and retained legacy material, with visible omission
  status; direct legacy restore cannot overwrite managed authority. No new
  portable secret-value export or provider-side revocation rollback is promised.
- **B5:** private staged credential input bound to the canonical CHANGE operation,
  reference and revisions; values never enter public inputs/proposals/History.
  Existing setup and key-change entry points retain normal policy admission.

Preserve existing provider selection, model-role routing, OpenRouter validation,
balance and request paths. Anthropic/Ollama and unrelated backup behavior remain
supported. Prove production routing and HTTP serialization with synthetic
credentials and only the final HTTP connection mocked; live provider testing
and personal credential migration are outside this task.

Configuration, secret state, Operational History and runtime remain separate
owners. Cross-store transitions require explicit crash fences, idempotent
re-entry and recovery proof; no generic distributed transaction or workflow
engine is introduced. Approval accepts the contract, not implementation closure.
The broader Ownership Foundation and real application-binding gates remain open.

### D070 — System operator semantic selectors and candidate-resolution boundary

Accepted by the Project Owner on 2026-10-06 after the System / `:sys`
discovery proposal. Q013–Q015 are resolved together.

The existing `system` Module API v2 package remains the canonical host-domain
owner. Capability IDs remain `system.*` and the existing `:system.*` operator
paths remain valid. S3 adds `:sys` only as a presentation alias over those
same target IDs; it is not another module, provider, capability namespace or
durable identity.

S1 adds one deliberately small optional capability-input selector shape:

```json
{
  "selector": {
    "schema_version": 1,
    "kind": "resource",
    "resource_kind": "service"
  }
}
```

`resource_kind` is a canonical lowercase identifier and the selector is
initially valid only for `string` or `object_id` inputs. This metadata is
presentation/discovery reference data. It cannot change the input's validator,
requiredness, capability provider, preconditions, safety, approval, privilege,
affected objects, verification or recovery.

Core owns the candidate-resolution interface. Candidate source registration is
not a Module API contribution. For a declared resource kind, resolution prefers
an eligible fresh System Model source and may fall back to an explicitly
registered bounded Platform read. Results use a version-1 ephemeral envelope,
are bounded/non-secret reference data and are never persisted merely because
they were displayed. Malformed source results fail closed rather than falling
through to another source. Stale System Model candidates are not presented as
current.

Candidate selection only produces an explicit input value. Canonical capability
preparation and execution revalidate that value and all existing authority
checks still apply. Candidate resolution performs no AI call, unbounded
filesystem/network scan, adoption, desired-state write, responsibility grant,
approval or execution.

S1 establishes only the generic contract, resolver registry, projection and
inspection API. The existing service capabilities are the approved S2 vertical
slice.

S3 implements Q013 without changing this authority decision: the shared
Operator Surface may advertise `sys -> system` as collision-safe presentation
metadata. The alias is absent when its canonical target is absent and is
suppressed if a real `sys` root exists. Navigation through the alias still
targets the same `system.*` identities.

### D071 — S5 storage administration is runtime-only and Core-executed

Accepted by the Project Owner on 2026-10-06 as the S5 Storage Administration
slice, building on the green S4 storage read model.

The first generic storage mutations are exactly
`system.storage.mount` and `system.storage.unmount`. Their durable identities
remain the S4 `filesystem:...` and `mount:...` objects. Operation-specific
selector resource kinds such as `mountable_filesystem` and
`unmountable_mount` are ephemeral filtered views over those objects, not new
System Model identities or authorization state.

System owns the host-domain capability declarations. Core owns the privileged
mechanism. The System provider uses the existing privileged marker and cannot
construct or replace argv after approval. Core independently resolves current
storage state, performs the reviewed preflight, freezes the exact privileged
argv into the proposal, re-prepares the proposal at the execution fence, and
performs deterministic post-state verification. The existing Igor
approval/authentication/History contracts remain authoritative.

`system.storage.mount` accepts one discovered unmounted local filesystem as
its required semantic input. If no target is supplied, Core derives a
deterministic `/mnt/<label-or-device>` target. A manually supplied target is
relative input confined to a reviewed mount root and resolves below `/mnt`,
`/media` or `/srv`; existing ancestry must be real, root-owned and not
group/other writable. The reviewed effect is only creation of the target
directory followed by a normal local mount of the selected `/dev/...` device.

`system.storage.unmount` accepts only an eligible current local-device mount
under the reviewed roots. Its reviewed effect is normal `umount`. It does not
fall back to force or lazy unmount when the normal operation fails.

Both capabilities are **runtime-only**. Neither reads, writes, creates, removes
or reconciles `/etc/fstab`, and neither claims desired persistent mount state.
Persistent boot mounts require a separate explicit capability and decision with
their own configuration ownership, preflight, verification, rollback and
migration semantics. Formatting, filesystem repair, encryption/container
activation and arbitrary network mounts are also outside S5.

A successful mutation may trigger best-effort refresh of the S4 storage
observers so current-state facts converge promptly. Those observations remain
machine evidence, not authorization, and refresh failure cannot rewrite an
already verified operation result.

### D072 — S6 local identities, bounded paths and single-path permissions

Accepted by the Project Owner on 2026-10-06 by selecting S6 after the S5
storage slice.

System may model bounded local Unix users and groups as observed collection
objects using stable numeric identities `user:uid:<uid>` and
`group:gid:<gid>`. The initial source is local `/etc/passwd` and
`/etc/group` only. It does not read shadow/password material or claim
enumeration of remote NSS/LDAP/SSSD identity providers.

D070's selector schema remains the authority boundary. S6 does not add a Module
API contribution kind. It extends selector use to existing `path` inputs and
allows the candidate request to carry one bounded printable prefix. Core owns
prefix resolution and may list one directory level under explicitly reviewed
roots. The prefix and candidates are ephemeral reference data: no recursive
scan, durable path inventory, approval, privilege or execution authority is
created by browsing.

Read-only path inspection observes metadata only and rejects symbolic-link
components. Permission-changing capabilities are exactly owner, group and mode
for one existing real path. Mutation candidates are restricted to reviewed
application/data roots and deliberately exclude `/etc`. The mode capability
accepts only explicit `0000..0777`; setuid, setgid and sticky bits are outside
this slice.

System owns host-domain declarations. Core owns the privileged mechanism:
current path/account state is resolved during preflight, exact non-recursive
`chown`, `chgrp` or `chmod` argv is frozen into the proposal, the
operation is re-prepared at the execution fence, and post-state metadata is
verified. Existing approval, authentication and Operational History contracts
remain authoritative.

S6 does not add account creation/deletion, password management, ACL mutation,
recursive permission changes, remote directory administration, arbitrary-root
mutation or a second account/path database.

## Open decisions

### Q016 — S7 network object/read boundary

Should the first S7 durable network object be exactly the already-documented
interface:<name>, while the route table and resolver configuration remain
bounded READ results/derived interface or host facts instead of introducing
durable route:* or DNS objects?

Recommendation: **yes**. This implements the Host Intelligence vocabulary
already chosen, keeps identity understandable, and avoids inventing route
identity before routing mutation/reconciliation exists.

Decision target: before S7.1/S7.2 implementation.

### Q017 — First Wi-Fi provider and initial mutation

Should NetworkManager/nmcli be the first optional reviewed Wi-Fi provider,
with system.network.wifi.connect_known (activate one existing saved profile
on one selected wireless interface) as the only initial Wi-Fi mutation?

Recommendation: **yes**. Generic interface/address/route/DNS reads remain
provider-neutral; NetworkManager is only an optional Wi-Fi adapter. Core must
own preflight, exact argv and post-state verification. No disconnect, interface
down, route/DNS mutation, radio toggle or profile deletion is implied.

Decision target: before S7.3/S7.4 implementation.

### Q018 — New Wi-Fi profile and credential authority

Should S7 defer creation/editing of open or password-bearing Wi-Fi profiles
until Igor has an explicitly reviewed configuration/secret-consumer authority
for that operation?

Recommendation: **yes**. Generic secret_ref consumers are currently
unavailable by policy. A password must not be downgraded into an ordinary
string/argv/History value, and even an open network creates persistent external
NetworkManager configuration whose ownership must be explicit.

Decision target: before any new-profile Wi-Fi capability.

### Q004 — Later third-party module trust policy

D022 settles the initial v2 boundary: explicitly enabled, reviewed local
executable code, with AI reference data kept outside authorization. If Igor
later distributes unreviewed third-party modules, what provenance,
permissions, isolation and signing policy is needed?

Decision target: before a third-party distribution or marketplace contract.

### Q009 — Integration-rule packaging

Do cross-module rules live with one module, separate integration packages, or a registry supporting both?

Resolve using real Nextcloud/Docker/Cloudflare cases.

Decision target: Steps 18–21.

### Q011 — Remote approval policy

If remote control is added, which READ/CHANGE/DESTROY operations may execute without an interactive TUI approval?

Decision target: Step 22.

## Resolved questions retained for traceability

Resolved questions stay here only so older references to their Q-numbers remain
understandable. Their accepted D-decisions, not this section, are authoritative.

### Q007 — Relationship/deployment ownership — resolved by D063

D063 settles the architecture under owner-scoped Step 19. Preserve source
claims, require explicitly approved deterministic transitions to accepted
bindings/grants, and retain conflicts/drift rather than applying source-priority
or last-write-wins. Runtime brownfield adoption, configuration targeting and
application cutover remain the separate Boundary 2/3 proof gates.

### Q012 — Effective `system` warning threshold — resolved for the bounded D062 setting

D062 settles the first warning threshold: Core-owned
`system.memory.warning_threshold_mib`, default 150 MiB, range 81–4096 MiB,
without importing the ineffective legacy `SYSTEM_RAM_WARN_MB=80`. The 80 MiB
critical boundary stays separate. Other host threshold configuration and legacy
names remain outside this bounded proof; no general threshold migration is claimed.

### Q013 — `:sys` operator alias and canonical System identity — resolved by D070

D070 keeps `system` and `system.*` canonical. S3 implements `:sys` as
presentation-only spelling that resolves to the same backend target IDs while
`:system` continues to work.

### Q014 — Bounded semantic selector metadata for capability inputs — resolved by D070

D070 selects one optional closed version-1 `resource` selector on existing
capability input properties. It is reference/presentation metadata only and
does not create a contribution kind or alter capability authority.

### Q015 — Dynamic candidate source, freshness and authority — resolved by D070

D070 selects one Core-owned ephemeral resolver boundary: prefer eligible fresh
System Model candidates, otherwise allow a registered bounded Platform read.
Malformed results fail closed; candidates create no fact, adoption,
responsibility or execution authority.


