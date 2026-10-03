# Igor 2 execution discipline

## Why this document exists

Igor's broad architecture is now clearer than its completion gates. The main
project risk is no longer choosing the wrong high-level direction; it is
allowing a large wave to become "done by narrative" instead of done by
evidence.

This document defines how roadmap work is executed, inspected and closed.

## Completion model

Every foundation or roadmap wave must provide five classes of proof.

### 1. Contract proof

The intended contract works and malformed or unsupported states fail
deterministically.

### 2. Regression proof

The previously green baseline remains green. A new architecture layer does not
earn completion by breaking established interaction, approval, privilege,
module-activation or frontend behavior.

### 3. Vertical-slice proof

A real component exercises the new path end to end.

### 4. Inspection proof

Operators and developers can inspect authoritative state, ownership,
availability and provenance without reading arbitrary implementation files.

### 5. Migration/recovery proof

Persistent-state or contract changes have a tested migration path and defined
recovery semantics.

A wave may contain more checks, but it should not omit one of these proof
classes without an explicit reason recorded in STATUS.md.

## Acceptance-check style

Prefer falsifiable checks such as:

- invalid v2 manifest fails before handler execution;
- disabled module contributes zero active capabilities or reference data;
- declined sudo action does not authenticate;
- a secret value is absent from the AI-context fixture;
- a persistent migration is idempotent and verifies its target;
- an executed CHANGE capability records deterministic verification.

Avoid exit statements shaped only like:

- "the module system is stable";
- "configuration is robust";
- "observability is good".

If a statement cannot be falsified, it is not sufficient as an exit condition.

## Thin-slice strategy

Use the smallest real implementation that crosses the new boundary.

### Wave C

Use a small part of system to prove Module Platform v2.

Keep nextcloud_docker on v1 throughout Wave C to prove compatibility. Do not
pull its migration into the Wave C implementation just because it is a richer
example.

### After Wave C

Use a narrow Nextcloud workflow as the first broader integration slice across:

- ownership/configuration;
- module contribution;
- capability selection;
- approval/privilege;
- execution;
- deterministic verification;
- state/history update.

Only generalize the new contracts to more application modules after that slice
proves the layers compose correctly.

## Continuous observability

Observability starts with each subsystem, not at a late UI milestone.

Each authoritative service exposes a minimal inspection/query surface for the
properties it owns.

Examples:

- module: lifecycle state, API version, owner, unavailable reason;
- capability: canonical name, provider, availability, safety, privilege,
  recovery semantics and verification metadata;
- configuration: owner, effective source, scope and validation state;
- secret: configured/not configured plus authorized-access metadata where
  appropriate, never the value;
- fact: owner, source, timestamp, freshness and confidence/type;
- recognition candidate: domain/provider, matched objects, evidence/freshness,
  ambiguity and missing evidence, never adoption authority;
- deployment: identity, accepted bindings/relationships, scoped responsibility,
  conflicts and retained disposition;
- plan: steps, provider, approval requirement, recovery semantics and
  verification result;
- resumable work: durable wait reason, prior committed results, readiness
  condition and current authority status;
- investigation: question, evidence, hypotheses, findings and status;
- history: operation/correlation identity, scoped affected objects, provider, authority/privilege, execution, verification and outcome.

The later TUI/consolidation work turns these inspection surfaces into one
coherent operator experience; it is not the first point at which inspection
exists.

## Internal Core service discipline

Core remains conceptually authoritative but internally separated.

The target internal services/components include:

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
- machine memory/system model;
- context/AI gateway;
- provenance/audit.

This is not a microservices requirement. It is a dependency and testability
requirement.

A module should not:

- construct another component's storage path;
- parse another component's configuration files directly;
- read secret values outside the secret service;
- mutate the capability registry outside the extension contract;
- invent approval or privilege behavior;
- treat AI output as authoritative state.

## Ownership Foundation gate

Before broad Module v2 migration, Igor must have one authoritative ownership
model for:

- code/package content;
- user configuration;
- secrets;
- persistent state;
- machine memory;
- knowledge;
- learned local artifacts;
- investigations;
- operational history;
- disposable runtime.

Every important persistent value should be able to answer:

- who owns it;
- where it lives;
- who may modify it;
- whether it is secret;
- whether it is portable;
- what its source and scope are;
- how it is migrated;
- how it is reset or recovered.

Early non-conflicting Wave C loader work may proceed while this foundation is
being established, but broad module migration must not freeze the current
mixed storage assumptions into Module API v2.

## Future-preservation review

Before accepting a new durable/public contract, review whether the contract
still works if a currently local implementation later changes in one of these
ways:

- the object/provider lives in another managed machine scope;
- there are multiple domain/deployment instances;
- a provider is reached through an external adapter rather than local Bash;
- the persistence backend changes without changing callers;
- work waits across restart or an external dependency;
- a package/provider is third-party with additional provenance/trust metadata;
- a referenced record is retained, migrated, redacted or no longer locally
  available.

This is not a requirement to implement those futures now. It is a guard
against making filesystem paths, handler names, host-local assumptions,
database schemas or current UI representations part of a durable public
identity. Reject speculative machinery that has no current need; preserve the
identity/reference seam that would allow the future implementation.

## Compatibility discipline

Design metadata rich enough for later growth, but implement the minimum
deterministic evaluator required now.

Wave C needs the accepted D019 semantics:

- exact hard module dependency checks;
- canonical capability requirements;
- module-wide versus contribution-local requirements;
- deterministic unavailable/missing-provider status.

Do not turn Wave C into a package-manager-grade solver. Version ranges,
conflicts and richer resolution should be added when a concrete requirement
needs them.

## Structured plans

Multi-step installation, configuration, repair and migration work should be
represented as structured plans rather than as one model-authored command
blob.

A plan should be inspectable before execution and should identify, where
applicable:

- intended outcome;
- preconditions;
- ordered capability steps;
- affected objects;
- safety/approval points;
- privilege requirements;
- recovery semantics;
- verification for each state-changing step;
- final verification.

The AI may propose or explain a plan. Igor remains the authority that resolves
capabilities, applies policy, executes and verifies.

## Provisioning and recognition discipline

Resource recognition and greenfield provisioning have separate proof burdens.

Recognition is read-only interpretation over deterministic evidence. A candidate
cannot become a deployment, desired value or management responsibility without a
separate authoritative transition. Reusable recognition requires ambiguity,
freshness/provider fencing and at least two materially different domain proofs.

Provisioning changes external reality. Before the first effect it must have
durable intent/attempt identity sufficient to reconcile uncertainty; after
effects it binds/validates real native identity at the earliest safe point.
Unknown effects are read back before another changing request. Provisioned
origin never implies blanket responsibility or destruction permission.

The detailed roadmap contracts are [RESOURCE_RECOGNITION.md](RESOURCE_RECOGNITION.md)
and [PROVISIONING.md](PROVISIONING.md).

## Recovery and rollback discipline

Generic rollback is not a system-wide guarantee.

Each state-changing capability declares recovery semantics. Suggested classes
are:

- reversible;
- best-effort;
- compensating action;
- snapshot required;
- irreversible.

Plans surface those semantics before approval. Recovery or compensation is
itself verified where practical.

## Secret discipline

Secret handling is successful only when both storage and use are controlled.

Required properties:

- separate secret storage/reference model;
- strict permissions;
- redaction in logs, events and errors;
- no default AI exposure;
- explicit subprocess/integration exposure;
- auditable secret-value access where practical;
- migrations that never write secret values into ordinary configuration,
  memory or history.

Most reasoning should need only facts such as "database credentials are
configured", not the credential value.

## Persistent migration discipline

Every persistent migration documents and tests:

- source version/location;
- target version/location;
- validation;
- recovery point or backup behavior where needed;
- idempotency/re-entry;
- verification;
- the cutover rule that prevents permanent dual-source ambiguity.

An elegant new layout is not complete if an existing Igor installation cannot
reach it safely.

## Scope control

Igor 2.0 does not require speculative ecosystem work.

Keep these as post-2.0 horizons until concrete use requires them:

- AI-assisted promotion of learned/generated capabilities into trusted code;
- module packs/marketplace;
- third-party signing/distribution infrastructure;
- sophisticated dependency solving;
- a second handler-language adapter without a real module that needs it;
- hot unload.

The architecture may leave clean extension points for them, but they do not
block Igor 2.0.

## Wave handoff template

A wave handoff should state:

1. what changed;
2. which accepted architecture decisions were implemented;
3. which files/contracts became authoritative;
4. focused tests and results;
5. broader regression tests and results;
6. vertical slice demonstrated;
7. inspection surface added;
8. migration/recovery status;
9. intentional deferrals;
10. remaining open decisions and their later owner;
11. whether the next wave is unblocked.
