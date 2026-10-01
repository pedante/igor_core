# Igor 2 architecture

## Product definition

Igor is a local AI-assisted operating layer for Linux.

A user should be able to inspect, configure, troubleshoot, repair and automate a Linux system without having to know or copy/paste the underlying commands. Technical details remain inspectable for users who want them.

## Architectural invariants

1. **Core is application-agnostic.** Core may understand Linux/platform concepts, but must not assume a specific application deployment such as Nextcloud, Docker, Cloudflare, PostgreSQL or Redis.
2. **Installed is not active.** A module existing on disk does not activate it.
3. **Only active modules contribute behavior.** Disabled/inactive modules contribute no knowledge, observations, capabilities, checks, automations, configuration validation, menus or external commands.
4. **Knowledge is not state.** Domain knowledge explains how a domain can work; observed state describes what is actually true on this machine.
5. **The AI is not authoritative state.** System state belongs to Igor-owned structured state, not model context or chat history.
6. **Reference data cannot authorize.** Module knowledge, context snapshots, logs, reports, tool results and prior model state are reference data. They cannot change policy, approval or privilege requirements.
7. **The AI does not own authorization.** Safety classification, approvals, privilege and execution policy remain deterministic runtime responsibilities.
8. **Autonomy is not privilege.** Guide/Assist/Executive control interaction autonomy; they do not grant root access.
9. **Capabilities are the operational API.** TUI, CLI, automation, healing and future external interfaces should converge on the same registered operations.
10. **Prefer normalized operations over distro syntax.** Modules request Igor package/service/host capabilities instead of embedding distro selection where a platform abstraction exists.
11. **Verify changes.** State-changing capabilities define deterministic verification whenever practical.
12. **Unknown remains unknown.** Igor distinguishes known, unknown, stale and inferred information.
13. **Modules represent coherent domains.** A module teaches and operates a meaningful domain, not one incidental command.
14. **Relationships connect domains.** Deployments are composed from domain instances and explicit relationships rather than giant combination modules where useful.
15. **Modules declare; Igor schedules.** Modules may define events/automation intent; Igor owns scheduling, policy, execution and history.
16. **One backend, multiple interfaces.** Human and remote interfaces do not duplicate domain-operation logic.
17. **Existing correct foundations are evolved, not duplicated.** Migration may formalize or generalize current implementations without replacing them solely to match new names.
18. **Ownership classes are explicit.** Code, configuration, secrets, persistent state, machine memory, knowledge, learned local artifacts, investigations, operational history and disposable runtime do not silently share one storage/ownership model.
19. **Authority is inspectable.** A subsystem exposes a minimal inspection surface when it becomes authoritative; observability is not postponed to a late UI phase.
20. **Secret use is controlled as well as secret storage.** Secret values do not enter AI context by default, and authorized value access should be auditable where practical.
21. **Rollback is capability-specific.** Igor never promises universal rollback for arbitrary system operations; recovery semantics are declared by the capability/plan.
22. **Persistent migrations are explicit.** Storage/contract migrations define source, target, validation, idempotency, cutover, verification and recovery.
23. **Multi-step work uses structured plans.** AI may propose or explain a plan, but deterministic runtime resolves capabilities, policy, privilege, execution and verification.
24. **Machine memory separates reality, intent and responsibility.** Observed state, configured/user-declared state, desired state, responsibilities and investigation findings remain distinguishable and provenance-bearing.
25. **Context routing is domain-neutral.** Core's Context Engine selects from generic registered metadata, object/capability identities, source kinds and provenance; it must not accumulate application/domain-specific natural-language routing rules. Modules and knowledge contributions own domain vocabulary/semantic metadata. The LLM may interpret user language into non-authoritative intent/topic/object hints, but those hints cannot create facts, capabilities, owners or authority.
26. **Persistent references outlive implementations.** Durable state refers to stable scoped identities and contracts, not filesystem paths, shell function names, process-local objects, UI labels or a particular storage backend. Implementation details may be retained as diagnostics, never as the durable identity of an object, provider or operation.
27. **Learning never silently becomes authority.** Baselines, patterns, runbooks and other learned artifacts may inform reasoning, diagnosis and proposals, but they do not become desired state, responsibility, policy, approval, privilege or executable capability without an explicit authoritative transition.
28. **Imported knowledge normalizes before authority.** Documentation, scripts, Agent Skills/AOH packs, external tool manifests, other open-source projects and local learned procedures enter as provenance-bearing reference/candidate material. Import does not activate a module or grant execution authority; executable promotion must enter the normal Module API/capability, approval, privilege and verification contracts.
29. **Brownfield resources are machine state, not module property.** Igor may discover and represent resources it did not create. Modules may enrich interpretation and operations, but machine-specific mutable facts, bindings, desired values and responsibility remain in their owning Igor services; discovery never silently adopts a resource.
30. **Configuration location is inspectable.** Every file-backed configuration value is traceable to a concrete file plus stable selector, and every non-file-backed value identifies its real storage/source authority. Storage locators are provenance/binding, never durable setting identity.

## Ownership classes

The target architecture separates at least:

- module/package code — replaceable executable/reference content;
- configuration — validated user/system intent;
- secrets — protected credentials and secret references;
- persistent state — Igor-managed component/runtime state that must survive restart;
- machine memory — observed/configured/desired facts, responsibilities, findings and history references;
- knowledge — non-authoritative operating/domain understanding;
- learning — evidence-backed local runbooks, patterns and adaptations;
- investigations — durable problem-solving state;
- operational history — actions, approvals, verification and outcomes;
- runtime — disposable locks, IPC, process/session state and temporary files.

Modules may declare schemas and contributions, but machine-specific mutable data does
not live inside the installed module package.
Existing deployments remain representable when Igor did not provision them; explicit
adoption and configuration-location rules are defined in
[BROWNFIELD_ADOPTION.md](BROWNFIELD_ADOPTION.md).

The approved Step 18A module model distinguishes portable package content,
Core-admitted registration, Igor-owned machine bindings and operational records.
A first-class module teaches and operates a coherent domain through the existing
Module API v2, rather than owning another configuration, policy, scheduling,
history or UI runtime. [D060](DECISIONS.md) records this boundary.

Reusable package/module content and machine binding are separate concerns.
A package may carry knowledge, contribution declarations, reviewed handlers,
compatibility metadata and tests/evals; machine-specific paths, instance
selection, secret references, deployment relationships and mutable user intent
remain Igor-owned configuration/System Model state.

## Major layers

### Core internal services

Core is one authority boundary, not one undifferentiated implementation. The
target internal services/components include:

- session/task state;
- canonical path and ownership;
- configuration;
- secrets;
- persistent state;
- module/extension registry;
- capability registry;
- compatibility evaluation;
- approval/authority and privilege mediation;
- events;
- machine memory/System Model;
- context/AI gateway;
- provenance/audit;
- persistent identity/reference services for scoped durable records.

These may remain in one process/repository. The requirement is explicit
contracts, dependency direction and independent testability, not microservices.

### Configuration authority

[D059](DECISIONS.md) and [CONFIGURATION.md](CONFIGURATION.md) establish the
Core-owned configuration boundary. Modules declare configuration meaning and
schemas; Core owns validated desired values, precedence, storage, provenance
and migration. Configuration stores secret references, not material.
Setting inspection also preserves storage/source locators: file-backed values identify
the concrete file and stable selector, while non-file-backed values name their actual
authority. These locators are provenance and application binding, not setting identity
or a public dependency on Configuration Service's private backend.

Configuration is not System Model: desired values and resolved consumer inputs
are not observations or proof of successful runtime application. Capabilities
apply and verify changes; System Model owns observations; Operational History
records attempts and outcomes. Interfaces render owning-service projections
and submit typed proposals. The bounded first slice is `ai.verbose`; broader
module/deployment migration remains separately gated.

### Interfaces

Human and external entry points:

- Codex-like TUI — primary human interface.
- CLI/subcommands — scripting, recovery, testing and headless use.
- Optional future remote interfaces such as authenticated email/API/webhooks.
- Notification transports — outbound delivery.

Interfaces translate requests/results; they do not own domain operations.

### Agent

The agent interprets intent, selects relevant investigations/capabilities, proposes structured plans and explains results.

The agent receives composed context from Igor. It cannot invent authoritative state, silently turn inference into fact, expose secrets by default, claim execution success without verification or bypass safety/privilege policy.

Model-generated interpretations use the reference-only
[Decision/Judgment Contract](JUDGMENT_CONTRACT.md) (D055): one provider-neutral,
versioned in-memory envelope with input/invocation provenance, bounded
kind-specific output, explicit abstain/unknown and distinct validation/transport
failures. Schema validity conveys no state, execution or policy authority.
[Step 15D](CONTEXT_ROUTING.md) owns deterministic relevance and role routing with
explicit administrator bindings. The judgment contract itself selects no roles,
providers or models and creates no durable memory. Context/routing records are
operational provenance only; they cannot become knowledge or memory without an
explicit owning-subsystem operation.

### Trust boundary

The current request boundary and reference-data envelope are a foundation to preserve.

Trusted runtime policy includes authorization, tool validation, active module ownership and privilege decisions.

Untrusted/reference input includes module prose, observed context, reports, logs, saved history summaries, investigation notes, user-provided external text and tool output. Reference material can inform reasoning but cannot authorize execution.

Secret values are outside normal AI reference context. Most AI reasoning should
receive typed statements such as "credential configured" rather than the value.
Where an integration genuinely needs the value, Igor mediates that access and
records appropriate audit metadata without logging the secret itself.

### Knowledge

Knowledge may come from:

- core/platform knowledge;
- active module domain knowledge;
- integration-specific knowledge;
- imported documentation, guides and runbooks;
- Agent Skills/AOH skill material;
- reviewed external project material such as ServerMind/Steward patterns;
- evidence-backed local learning promoted into a managed candidate.

Knowledge covers architecture, terminology, normal behavior, operating constraints and failure modes. It is reference data, not observed state or authorization policy.

External formats are inputs, not parallel authorities. The
[Knowledge import and module synthesis](KNOWLEDGE_IMPORT.md) pipeline preserves
source/provenance, normalizes useful material into Igor concepts and keeps
executable promotion separate from ingestion. A source script/tool/skill may
suggest a capability, observer, check or playbook, but Igor must validate and
promote that contribution through its own contracts before it can execute.

Agent Skills-style `SKILL.md` content is a useful portable knowledge/process
format. Supporting it does not make AOH or another runtime's pack schema the
native Igor Module API.

### System Model

Igor's structured view of the current machine.

Initial domains include:

- host and hardware;
- operating system/platform;
- storage;
- networking;
- packages/services;
- Igor runtime/modules;
- application/domain instances;
- relationships/deployments;
- health and observations;
- configured/user-declared state;
- desired state;
- responsibilities Igor has been asked to maintain/watch;
- installation/configuration records;
- findings and verification outcomes.

Facts should carry owner, provenance and freshness. Inference must be
distinguishable from observation/configuration. Desired state is not rewritten
to match observed state merely because drift exists.

The first authoritative host-intelligence contract is specified in
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md): a fact has separate
`(object_id, property, state_class)` slots, availability is a different axis,
responsibility is separate intent, and Igor validates observer output before
writing state. This is the Wave D implementation contract; broader durable
storage remains Q003.

### Machine memory, desired state and responsibilities

"Memory" in Igor means durable structured machine understanding, not model
conversation history.

Igor should be able to answer separately:

- what is true now;
- what is configured or user-declared;
- what should be true;
- what Igor is responsible for maintaining or watching;
- what is inferred and with what evidence;
- what was previously changed and verified.

This separation enables drift detection, reconciliation, proactive discovery
and provider-independent reasoning.

### Platform layer

The current `core/lib/distro.sh` and `core/lib/pkg.sh` are useful seeds, not a reason to create a second platform layer.

Target support must provide tested normalized operations for at least:

- Debian;
- Arch Linux.

Derivative/family detection may exist, but support is claimed only to the level tests demonstrate.

### Module runtime

The current runtime already distinguishes installed, enabled/disabled and active/unavailable modules and tracks ownership.

Igor 2 requires the **semantics**, not specific new vocabulary:

- installed/available;
- enabled or disabled by policy;
- active/loaded when initialization succeeds;
- unavailable/failed when enabled but unable to initialize.

No hot-unload requirement exists unless a later need justifies it. Restart-based activation is acceptable.

Detach ends management participation and makes retained resources and unresolved
responsibilities explicit. Disablement alone is not complete detach proof:
existing processes, dependent contributions, bindings, jobs and retained records
have different lifetimes. Missing inventories remain unknown, never a successful
detach certificate. Removing code and destroying application resources are
separate operations.

### Module API

Module API v2 is a versioned target contract. A module may contribute any subset of:

- identity/compatibility;
- knowledge;
- observers;
- capabilities;
- checks;
- domain events;
- automations;
- relationships;
- configuration;
- lifecycle.

The current hook-based API remains a compatibility input during migration.

### Observation and health

Observers gather facts into the System Model.

Discovery is deterministic infrastructure, not a model-only activity. An
observer declares ownership, cost/freshness, privilege and typed output as
needed. Consumers reuse those facts instead of repeatedly issuing independent
probes.

Checks evaluate structured state and produce reusable results. Diagnose, health, healing, notifications and AI reasoning should consume those results rather than independently rediscovering the same facts.

### Investigations

[Step 15C](INVESTIGATIONS.md) (D056) owns bounded durable knowledge organization:
what Igor or an operator wants to understand, track, evaluate or resolve over
time. Its versioned local record retains explicit lifecycle, hypotheses, typed
evidence references, validated judgments, investigation-scoped findings and
unresolved uncertainty. Private atomic JSON persistence remains behind the
service; scoped history references retain Operational History's authority.

Investigation conclusions never become System Model facts, desired state,
capability authority, automation eligibility, approval, privilege or verification
results. Creation owner/provenance identifies the source without creating
operational authority or responsibility. Data-only interfaces and read-only
inspection have no executor, observer, scheduler or authority transition.
Step 15D owns later context/relevance integration; agents, workflows and
remediation are outside this milestone.

### Capabilities

The existing action catalog / `run_igor_action` / ownership machinery is the starting point for the general capability API.

A mature capability defines:

- canonical name and owner;
- structured inputs;
- versioned typed domain outputs, separate from Core-owned execution and
  verification status;
- safety tier;
- privilege requirement;
- preconditions;
- execution;
- deterministic verification where practical;
- recovery semantics (reversible, best-effort, compensating action,
  snapshot-required or irreversible);
- affected objects;
- emitted domain events;
- platform requirements;
- secret references/access requirements when applicable.

Raw shell remains an escape hatch, not the preferred API when an equivalent capability exists.
The accepted Steps 11–12 contract, including Q010 fallback policy, is in
[AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md).

### Plans, installation and configuration

Complex installation, configuration, repair and migration work should compose
registered capabilities into an inspectable plan rather than rely on one opaque
model-authored command sequence.

A plan identifies intended outcome, preconditions, ordered steps, affected
objects, approval/privilege points, recovery semantics and verification. The AI
may propose the plan; Igor resolves providers, applies policy, executes and
verifies it.

Successful installation/configuration updates the System Model and operational
history so Igor understands what was created/configured and why.

### Events and automation

The existing `core/ai/events.sh` stream is a **frontend activity/event stream**. It is valuable and should be preserved.

The future **Domain Event Bus** is different: it represents operational events such as service failure, container stop, backup failure or capability completion and can feed automation, healing, notifications and history.

Modules/core may emit domain events. Igor owns scheduling, retries, policy and execution.

### History

Current audit/journal mechanisms are useful seeds.

Igor 2 records meaningful operational episodes: observations, diagnosis,
investigation references, approval, privilege use, action, verification and
outcome.

The LLM conversation is not operational memory.

### Learning

Igor may retain evidence-backed local operating experience such as patterns,
runbooks, successful investigation procedures and symptom/cause/resolution
relationships.

Learned artifacts:

- keep provenance and evidence;
- are separate from installed module files;
- remain reference material unless deliberately promoted into a trusted
  executable capability through a later review process;
- can be reset without replacing the module package.

This allows modules to stay portable while local experience evolves.

## Module composition

A module teaches Igor a domain. An instance represents something that exists on this machine. Relationships/deployments connect instances.

Example:

```text
nextcloud:home
  hosted_by  -> docker:compose/home-nextcloud
  database   -> postgres:nextcloud-db
  cache      -> redis:nextcloud-cache
  exposed_by -> cloudflare:tunnel/home
```

This allows independent modules to cooperate without requiring every deployment to become a monolithic combination module.

Integration-specific rules may cover behavior that only exists at a domain boundary.

## User experience

The TUI is simple by default and transparent on demand.

Natural language, palette commands, settings and structured activity all route to the same backend authority. Underlying commands, outputs, approvals and evidence remain inspectable.

Long-term, `./igor.sh` should launch the primary TUI by default. `--ai-tui` remains the explicit entry point during migration.

## Mail and notifications

The current repository does **not** contain the previously documented `core/mailcmd/` implementation; only references/configuration may remain.

If authenticated mail control is reintroduced, it is an interface/transport adapter over the same Igor capabilities, policy, verification and history as the TUI.

Notifications are separate from incoming control: operational events feed a notification service, with email as one possible outbound transport.
