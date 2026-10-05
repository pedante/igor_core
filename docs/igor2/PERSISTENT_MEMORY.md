# Step 15A — Persistent Identity & Memory Foundation

Status: **accepted Step 15A architecture contract**. The bounded Step 15B
implementation and its service behavior are documented in
[Operational History](../operational_history.md); completion evidence lives in
[STATUS.md](STATUS.md). D048–D054 remain unchanged.

This document resolves the persistent-identity and System Model persistence
questions that must be settled before Operational History becomes an
authoritative Igor subsystem. It is intentionally narrower than implementing a
general database, event store, workflow engine or multi-machine controller.

The goal is to make later Steps 15–19 easier: history, investigations,
baselines/learning, relationships/deployments, resumable work and self-healing
should share stable references and provenance without becoming one
undifferentiated memory system.

## Why this gate exists

Steps 8–14 established current-state facts, capabilities, deterministic
verification, context, transient domain events and durable automation intent.
Step 15 is the first point where Igor begins retaining broad operational
meaning over long periods.

A poor persistence contract here would make later features depend on current
file paths, Bash handlers, one local host, one module instance or one database
layout. Those details are valid implementation choices today but must not
become durable identity.

The Step 15A rule is:

**persist meaning and stable references; keep implementation replaceable.**

## Architectural outcomes

Step 15A establishes these outcomes:

1. the System Model stays a current-state projection instead of becoming the
   historical database;
2. durable object references explicitly include a stable Igor scope plus the
   existing object ID;
3. capability/operation history records canonical contract/provider identity,
   not handler/function/path identity;
4. history attaches to the canonical execution boundary rather than depending
   on transient domain events;
5. history, investigations, durable work, deployments and learning remain
   distinct authorities;
6. persistent backends stay private and migratable;
7. learned material remains non-authoritative unless a later explicit trust
   transition promotes it.

The accepted decisions are D048–D054.

## Practical memory model

Igor uses **memory** as an architectural umbrella, not as one database or one
authority. The existing subsystems deliberately retain different meanings:

```text
System Model          -> what Igor currently understands about the machine
Configuration         -> durable desired configuration and user intent
Deployment Service    -> accepted bindings, relationships and responsibility
Operational History   -> what happened over time
Investigations        -> durable problem-solving state
Knowledge / learning  -> reference material, patterns, runbooks and local experience
Session/runtime       -> current interaction and disposable process state
Context Engine        -> bounded projection of relevant material to a model/interface
```

Those authorities may reference one another through typed/scoped IDs, but one
must not silently become the source of truth for another. In particular:

- conversation history is not machine memory;
- a persisted observation does not become fresh current state after restart;
- history is not desired state;
- a learned pattern is not responsibility or execution permission;
- knowledge is reference data and cannot grant approval, privilege or capability
  authority;
- the Context Engine selects and projects memory; it does not own or rewrite it.

This means Igor does **not** need a generic `memory.db` that absorbs all durable
state. Separate services may use SQLite, versioned files or another private
backend when their own consistency requirements justify it. Callers use service
contracts and stable identities, never backend paths or SQL schemas.

## Retrieval and derived indexes

Useful memory depends on bounded retrieval rather than injecting all retained
state into every AI request. The default retrieval order should remain
deterministic and inspectable:

1. select by semantic type and owning authority;
2. constrain by scope/object/domain and active owner;
3. enforce freshness/known/availability rules;
4. retain provenance, verification and sensitivity;
5. project only the material relevant to the current request.

A search index, embedding index or vector database may later accelerate or rank
reference material, but it is a **derived index**, not durable truth or
authorization. Igor should add such machinery only after measured retrieval
needs justify it.

## Knowledge representation and OKF compatibility

Knowledge, learned patterns and runbooks benefit from a portable,
human-readable representation. Igor should keep the Knowledge Artifact model
representable as ordinary content plus typed metadata such as:

```text
type
owner
source/provenance
scope
status
freshness/stale_after
verification
compatibility/version
content
```

Markdown with structured front matter is a suitable repository/export form.
Where practical, Igor knowledge import/export should remain compatible with the
Open Knowledge Format (OKF) model rather than inventing an incompatible
Igor-only document syntax.

This is an interoperability constraint, **not** an OKF dependency and not a
replacement for Igor's memory contracts. Igor owns the semantics and may use a
different internal index/store. OKF-style artifacts are appropriate for
knowledge, patterns, runbooks, references and reviewed learning; they are not
the authoritative representation for current System Model facts, mutable
configuration, secrets, approvals, privilege state, Operational History or
runtime/session state.

If OKF evolves, Igor should adapt at the import/export boundary rather than
letting an external format dictate Core authority or persistence.

## Non-goals

This gate does not require:

- selecting a permanent SQLite schema;
- persisting every System Model observation;
- multi-machine execution;
- remote agents;
- a distributed event log;
- workflow DAG infrastructure;
- implementing Step 15B history;
- implementing investigations;
- implementing baselines/learning;
- implementing Step 17 topology/reconciliation;
- changing current capability IDs;
- changing current local object IDs such as host:local;
- changing Module API v2 handler language;
- merging all current persistent data into one store.

## Scoped durable identity

### Current object identity remains valid

Wave D already defines useful local object IDs:

~~~text
host:local
service:systemd:docker.service
package:docker.io
mount:/
module:system
domain:nextcloud_docker:default
~~~

Do not rename these merely to prepare for future multi-machine use.

They identify a thing **inside one Igor management scope**.

### Scope identity

A durable record that may outlive one process/session uses an explicit Igor
scope identity when referring to a machine/domain object.

Conceptually:

~~~json
{
  "scope_id": "scope:opaque-stable-id",
  "object_id": "service:systemd:docker.service"
}
~~~

The exact serialized shape is an implementation detail, but the semantics are
not.

A scope ID:

- is Igor-owned and stable for the managed installation/machine identity;
- is opaque to modules and AI;
- is not derived from hostname, IP address, MAC address, filesystem path or a
  provider display name;
- is not used directly as a filesystem path;
- is preserved when restoring the same managed installation as a continuation;
- must not be silently reused when cloning/onboarding a distinct managed
  machine;
- can later represent an external/remote managed machine without changing the
  object-ID grammar.

The first Step 15 implementation needs only the local scope. The contract must
not assume that local is the only possible scope forever.

### Scoped object reference

A durable ObjectRef is therefore conceptually:

~~~text
(scope_id, object_id)
~~~

Process-local APIs may continue accepting a bare object ID where the local
scope is unambiguous. New durable cross-subsystem records stamp/retain the
scope explicitly.

This avoids a future collision such as two machines both legitimately having:

~~~text
service:systemd:sshd.service
~~~

### Identity is not presentation

Display labels, hostname, module menu names and UI tree positions are
attributes/presentation. They are not durable identity.

Renaming a label must not rewrite historical meaning.

## Operation and provider identity

### Canonical operation

The durable operation contract is the existing canonical capability identity:

~~~text
capability_id
capability_version
~~~

For an invocation, history additionally retains the selected provider
identity, owner/source provenance and execution scope.

### Provider is not handler

A provider may currently be implemented by a Bash module handler. In future it
could be another adapter or managed node.

Therefore these may be recorded as diagnostics/evidence:

~~~text
handler function
module path
resolved argv
process ID
local command
~~~

but none is the durable provider/operation identity.

A later provider may implement the same capability contract without rewriting
old records.

### Provider and execution location are separate

Provider selection and the scope on which an operation acts are separate
concepts.

This preserves future shapes such as:

~~~text
canonical capability: system.service.restart
provider: external/server adapter
execution scope: managed-machine-B
affected object: managed-machine-B / service:systemd:sshd.service
~~~

No remote provider is implemented in Step 15A.

## Correlation and durable references

Different authorities keep their own IDs rather than sharing one universal
record type.

Expected durable identities include, where applicable:

- operation/attempt ID;
- correlation ID;
- causation/reference ID;
- investigation ID;
- plan ID and step ID;
- deployment ID;
- automation instance/run identity;
- learned-artifact ID.

Exact formats are implementation details, but IDs are stable, opaque to AI
authority, version-safe and never reused for another meaning.

Correlation groups related work; it does not grant authority.

Causation/reference links explain why something happened; they do not permit
the next action.

## Evidence and provenance

A persistent authority should distinguish its own state from evidence that
supports/explains that state.

Evidence references may point to:

- a System Model fact snapshot/reference;
- a structured health/check result;
- another history episode/result;
- an investigation finding;
- a report/log locator or bounded excerpt;
- a verified configuration/deployment record, including its typed storage/source
  locator when configuration evidence is file-backed or otherwise externally
  stored;
- external/adapted evidence in a future scope.

Evidence is reference material. It cannot authorize execution.

Evidence metadata should retain, as applicable:

- source/provenance kind and source identity;
- scope/object reference;
- timestamp;
- digest or bounded locator where useful;
- sensitivity/redaction status;
- availability/retention status.

Do not copy secret values into evidence merely to make records self-contained.

## System Model persistence: Q003 resolution

### The System Model is current-state projection

The System Model answers questions such as:

- what is currently observed;
- what is currently configured/user-declared;
- what is desired;
- what Igor is responsible for watching/maintaining;
- what is currently inferred;
- what information is known, unknown or stale.

It is not the canonical history of every prior value.

### Observed state

A current observation is authoritative because of its validated observer,
provenance and freshness, not because a database row survived restart.

After restart:

- a trusted source may refresh the observation and make it known/current;
- an optional persisted observation snapshot may be displayed as old/stale
  reference evidence;
- persisted age alone never makes the value fresh;
- a cache cannot silently become observed current state.

This preserves offline explanation without converting stale storage into
machine truth.

### Configured, user-declared, desired and responsibility state

These states survive restart through their authoritative sources:

- Configuration Service / validated compatibility source;
- explicit user/policy authority;
- verified installer/deployment records;
- other named Igor-owned source adapters.

The System Model rehydrates/project those sources.

Do not make a second System Model database an independent competing source of
the same intent.

### Inferred state

Inferred state is recomputed from the named rule and current input
references. Persisted inference may be historical evidence but does not become
current merely because it was stored.

### Historical state

When past observations, checks, actions, verification or outcomes matter over
time, Operational History stores the historical episode/evidence reference.

This gives a clear ownership split:

~~~text
System Model        -> what Igor currently understands
Operational History -> what happened over time
~~~

## Operational History boundary

Step 15B implements the first durable runtime consumer of this contract through
the private Operational History service, directly attached to canonical
capability admission/execution/results. Its versioned episodes and scoped
references implement these semantics without persisting current System Model
facts as historical authority. See
[Operational History](../operational_history.md) for lifecycle, inspection,
export/recovery and compatibility cutover.

### History is not the Step 13 event buffer

The Domain Event Bus remains transient/reactive.

A valid architecture is:

~~~text
canonical execution/result
       |       | -> transient domain event
       |
       ----> durable operational history
~~~

Do not make the only durable path:

~~~text
canonical result -> transient event -> history
~~~

because a process failure between publication and durable consumption would
lose operational memory.

### Operational episode

An operational episode may include, as applicable:

- stable operation/attempt/correlation identity;
- actor/request/interface provenance;
- canonical capability ID/version;
- selected provider/owner/source;
- execution scope;
- validated/frozen inputs or non-secret references;
- scoped affected objects;
- precondition results;
- safety tier and approval decision;
- privilege requirement/use result without credentials;
- provider execution status;
- deterministic verification status/evidence;
- final canonical outcome;
- recovery semantics/action references;
- timestamps;
- related plan/investigation/automation/deployment references.

The permanent schema should describe Igor semantics, not reproduce the
existing pipe journal or AI-audit fields.

### State-changing interruption

For CHANGE/DESTROY work, the Step 15 implementation must create/retain durable
attempt identity before the provider can produce an external effect.

The durable lifecycle must distinguish at least conceptually:

~~~text
never started
admitted/prepared
running/claimed
terminal with canonical result
interrupted / external effect unknown
~~~

Exact vocabulary may align with the existing capability/plan result model.

If Igor restarts with an in-flight state-changing attempt and no terminal
result, it does not blindly execute the operation again. It verifies/reconciles
where possible or requires explicit recovery/decision.

Automation Step 14 already proves the same principle for due-slot claims; Step
15 generalizes the durable operational meaning without turning history into
the scheduler.

### READ history

Not every READ must have identical retention policy or pre-execution durability
cost. Step 15B may choose bounded policy for low-value READs. Any recorded READ
still uses the same canonical identities/provenance, and no omitted READ may be
invented later from chat text.

## Investigations are separate durable state

The bounded [Step 15C implementation](INVESTIGATIONS.md) formalizes this
ownership under D056. Step 16C/D064 extends that same authority with typed
symptom/cause/action/verification findings bound to already-attached evidence.
These remain investigation-scoped assessments: a supported cause is not a
System Model fact, a supported action is not execution authority, and a
verification finding does not replace canonical capability verification.
Creation provenance grants no operational responsibility or authority. The
service uses 15B installation identity without duplicating operational episodes.

An investigation answers:

**what problem/question is Igor trying to understand and what is the current
problem-solving state?**

It is not just a filtered history query.

An investigation may own:

- question/problem statement;
- related scoped objects;
- evidence references;
- hypotheses and their status;
- decisions/choices;
- actions requested/performed;
- findings;
- verification;
- current resolution/status.

Actions and evidence point to canonical history records where possible.

Investigation text is reference material and cannot authorize execution.

Investigation lifecycle can be mutable/versioned while history remains
append-oriented/audit-oriented. Version-1 Investigation stores remain readable
and exportable; Step 16C migrates them atomically only when an explicit valid
typed-finding mutation first requires version 2. No read-time or prose-to-typed
migration occurs.

## Resumable Work is separate durable state

RESUMABLE_WORK.md already defines the distinction:

- resumable work owns what plan/step is suspended and why;
- automation owns when/how readiness checks run;
- capability/policy owns what may execute;
- history records what happened.

Step 15A preserves that separation.

A waiting-plan record must reference prior canonical operation/results rather
than copying them into a scheduler-specific model.

## Deployments and relationships are separate durable state

The original roadmap assigned deployment topology/reconciliation to Step 17.
The owner-scoped [Step 19 contract](DEPLOYMENTS.md) now owns this outcome (D063).

Durable participants use scoped ObjectRefs from this contract.

Relationships should be able to retain provenance/source claims such as:

- discovered;
- configured;
- installer-created;
- user-declared;
- external/adapted;
- AI-proposed reference.

D063 resolves reconciliation/authority (Q007) through explicit approved
transitions and preserved source claims. Step 15A supplies the scoped identity
model without rewriting existing local object IDs.

Operational History records that a deployment/relationship changed; it is not
the current deployment source of truth.

Pre-existing resources are valid participants even when Igor did not provision
them. Discovery does not imply adoption or responsibility; an explicit authority
transition preserves external/unknown origin and configuration source locators.
See [BROWNFIELD_ADOPTION.md](BROWNFIELD_ADOPTION.md).

## Baselines and learning are separate

Step 16 can derive explainable baselines and evidence-backed local artifacts
from retained history.

These statements are distinct:

~~~text
observed/learned: CPU normally stays below 70%
desired:          CPU should stay below 70%
responsibility:   Igor should maintain/watch that outcome
authority:        Igor may execute capability X unattended
~~~

No transition between those meanings is implicit.

Learning artifacts retain evidence/provenance and reset semantics outside
installed module packages.

Step 16A baselines are on-demand read-only projections of bounded Operational
History. Step 16B's [Local Learning Service](LOCAL_LEARNING.md) derives
candidates on demand and persists only explicit reviewed snapshots and their
dispositions. Each snapshot freezes the exact candidate revision, content,
applicability, provenance and canonical source references the operator
reviewed; it does not copy History episodes or Investigation records. Changed
evidence requires a new candidate and review. Missing/pruned source records
remain visible as unavailable references, while the reviewed artifact stays
inspectable until explicit Local Learning reset/delete or supersession.

Learning uses private bounded versioned persistence outside installed module
directories. Module/owner inactivity affects Context eligibility, never
retention or inspectability. Its reset/delete scope is separate from History,
Investigations, desired configuration and module installation. Candidates are
not persisted as a discovery queue.

## Persistence/backend contract

### Services are the API

Modules and callers use Igor services/records, not storage paths or SQL table
names.

The permanent contract is the service behavior and versioned record meaning.

### Physical backend can change

A Step 15B implementation may choose SQLite, versioned files or another local
backend based on actual requirements such as:

- atomicity/concurrency;
- indexed queries;
- recovery/export;
- retention;
- migration complexity;
- resource cost.

That backend remains private.

Several logical authorities may share one physical SQLite database later if
that is useful. That does not merge their ownership/contracts.

### Persistent migration

Every persistent schema/layout change follows EXECUTION.md/MIGRATION.md:

1. identify source version/location;
2. identify target version/location;
3. validate before cutover;
4. provide recovery/backup where needed;
5. make migration idempotent/re-enterable;
6. verify target behavior;
7. define one cutover rule;
8. remove indefinite dual authority.

Unknown versions fail closed.

## Retention, reset and deletion

Ownership classes keep separate reset semantics.

Examples:

- runtime scratch can be cleared without deleting history;
- clearing a System Model cache does not erase configuration/desire;
- module package removal does not silently erase machine history;
- learned artifacts can be reset without reinstalling the module;
- investigation cleanup does not rewrite historical operations;
- configuration reset is not equivalent to history reset.

Step 15B may choose initial retention defaults, but deletion/reset is explicit.

A durable ID is never silently reused after pruning. A reference to unavailable
or pruned data resolves as unavailable/redacted/missing according to policy; it
does not point to a new record with the same ID.

Privacy/security-driven deletion may remove content while preserving only the
minimum non-sensitive tombstone/reference metadata required for integrity,
subject to future product policy.

## Secret discipline

Persistent records must follow the existing secret contract:

- store secret references or configured/use metadata, not values;
- never place sudo/password/authentication transcripts into history;
- scrub/redact errors/evidence;
- record authorized secret access metadata where practical without the secret;
- migration/export never copies secret values into ordinary history/memory.

A digest of secret material is also sensitive unless there is a reviewed need;
do not add one by default.

## Future-preservation checks

Before Step 15A-derived contracts are considered complete, ask whether they
remain coherent if:

1. two managed machines both have host:local/service IDs inside different
   scopes;
2. the same capability has a local and external provider;
3. a deployment contains multiple instances of one domain;
4. the storage backend changes;
5. work waits across restart/OAuth/DNS/reboot;
6. an external adapter contributes evidence with its own provenance;
7. a future third-party provider carries signing/trust metadata;
8. a related record is migrated, redacted or pruned.

Passing this review does not require implementing any of those features.

It only requires that today's durable public identities do not make them
impossible.

## Step 15B implementation requirements

Before Operational History becomes authoritative, Step 15B must prove:

### Contract proof

- malformed/unknown persistent versions fail closed;
- scoped references and IDs validate deterministically;
- secret values/authority cannot be injected through evidence/reference data;
- handler/path/UI identity is not required to interpret a history record.

### Regression proof

- current capability, approval, privilege, verification, automation and event
  behavior remains green;
- existing AI audit/recovery journal compatibility remains available until its
  documented migration/cutover.

### Vertical slice

At minimum:

- one real READ capability produces durable history with canonical identity;
- one CHANGE fixture/operation proves durable attempt identity before possible
  external effect, terminal verification/outcome and restart/interruption
  reconciliation behavior.

### Inspection proof

Read-only history inspection explains:

- identity/correlation;
- capability/provider;
- scoped affected objects;
- approval/privilege;
- execution;
- verification;
- outcome;
- provenance/evidence availability.

Inspection has no side effects.

### Migration/recovery proof

- initial store creation;
- restart/reopen;
- interrupted state-changing attempt;
- corrupt/unsupported version;
- explicit export/recovery path;
- idempotent schema migration fixture when the first version transition exists;
- clear compatibility/cutover from existing journal/audit inputs.

## Later decisions intentionally not pulled into Step 15A

The following retain their existing roadmap owners:

- Q004 third-party module trust/signing;
- Q007 relationship/deployment reconciliation (subsequently resolved by D063);
- Q009 integration-rule packaging;
- Q011 remote approval policy;
- Step 16 baseline algorithms/retention policy;
- final relationship vocabulary (subsequently accepted in owner-scoped Step 19);
- future self-healing unattended CHANGE policy (excluded from owner-scoped Step 19);
- post-2.0 capability promotion/marketplace/provider solving.

Step 15A preserves the seams those features need; it does not implement or
pre-decide their policy.
