# Step 19 — Representative Application Workflow / Relationships and Deployment Ownership

Status: **architecture approved; Boundary 1 complete; Boundary 2 implementation under validation; Boundary 3 pending**.
This owner-scoped Step 19 supersedes the older roadmap numbering of Relationships
and Deployments as Step 17. It does not authorize the older Self-Healing v2 item.

The approval covers three sequential boundaries, each stopping with its own
evidence report. [STATUS.md](STATUS.md) records implementation evidence;
[EXECUTION.md](EXECUTION.md) defines the five proof classes. The approved design
extends [D061](DECISIONS.md) and [Brownfield Adoption](BROWNFIELD_ADOPTION.md),
using the [persistent scoped-reference contract](PERSISTENT_MEMORY.md).

## Authorities

| Authority | Owned meaning |
|---|---|
| Module package | Portable domain implementation, knowledge, schemas and capabilities |
| Deployment Service | Durable deployment identity, bindings, relationships and explicit scoped responsibility |
| Configuration Service | Validated desired configuration and revisions |
| System Model | Current observations, provenance and freshness |
| Capability runtime | Deterministic contracts, policy, approval, privilege, execution and verification |
| Operational History | Execution attempts, outcomes, verification evidence and interruption |
| Investigations | Questions, hypotheses and findings |

Deployment Service is an internally separated Core component. It is not a generic
workflow engine, executor, scheduler, observation cache, configuration store or
replacement for Operational History. Its minimal transition state exists only
to keep its own identity, bindings, relationships and grants consistent.

Discovery, knowledge, participation, observation and Igor-provisioned origin
never imply responsibility. Responsibility is positive, explicit and scoped.
Neither responsibility nor model output substitutes for execution approval,
privilege or unattended-execution policy.

## Identity and references

Version 1 uses one concept, **deployment**: one deliberately identified
application installation/stack and its participating resources. Application
instance and managed stack are descriptive terms, not additional authorities.
Management may cover only one setting or duty; an application can remain
externally operated.

A deployment has an opaque Igor-owned ID inside the existing installation scope.
Checkout paths, labels, hostnames, Compose projects, container names and load
order are attributes or locators, never its identity. Renaming/relocating a
continuing deployment preserves identity. A distinct installation receives a
distinct identity. Re-adoption of a retained deployment is an explicit revision,
not identity reuse.

Resources use existing `(scope_id, object_id)` references where another owning
service already supplies identity. Otherwise the Deployment Service may enroll
a minimal opaque resource identity/binding record for participating resources.
It does not duplicate System Model observations or build a general inventory.
Identity owner, resource origin, reference availability, native/provider identity,
provider scope/incarnation, locator and display label are separate attributes.
Logical services and their native container/process realizations are distinct.
Native name reuse cannot silently rebind an approved resource.

Secret participants reference the existing secret authority; secret material is
never enrolled, exported or projected. Resource kinds and provider metadata are
application-neutral. Concrete adapters belong to their domain contributions.

## Relationships and claims

The closed vocabulary is:

| Type | Meaning |
|---|---|
| `includes` | Deployment participation, without ownership implication |
| `depends_on` | A participant requires another participant/external dependency |
| `uses` | Consumption of a typed storage, network, configuration or secret-reference role |
| `exposes` | An endpoint exposes a deployment/service |

Every durable relationship has stable identity/endpoints, typed role, revision,
lifecycle, record owner, source, provenance and supporting evidence references.
Verification/evidence availability is independent of accepted relationship
lifecycle. Configuration setting targeting remains Configuration Service's
reference; relationships cannot create desired values.

Preserve discovered, configured, installer, user, external and AI-proposed claims.
Claims cannot become accepted topology through last-write-wins. Conflicting
evidence is inspectable and blocks affected mutations until explicitly resolved.
Only an authorized deterministic transition changes an accepted binding.
Evidence references never convey approval; missing evidence is unavailable,
not a new fact or permission.

## Responsibility

Separate knowledge/freshness, participation, origin, responsibility and retained
disposition. Adoption describes an explicit transition; provisioned-by-Igor
describes origin. Neither implies comprehensive management.

A grant names a precise deployment/resource/setting subject, accepted duty,
accepting authority, provider requirements, provenance, lifecycle and exclusions.
Observation, configuration, lifecycle, backup and update duties are distinct.
Shared resource/setting conflicts must be checked transactionally, including
conflicting deployment-wide and narrower exclusive grants. Mere inclusion in
two deployments is permitted; incompatible management cannot be.

The application proof accepts configuration/readback and explicit recovery for
one setting. Database lifecycle, infrastructure, backup and application-version
updates remain outside those grants. Unsupported duties cannot be accepted
merely because a record can represent their names.

## Attach, provision, release and destroy

Brownfield attachment follows discovery, explicit candidate selection,
deterministic inspection, proposed relationships/duties, validation, owner
approval, durable binding and independent verification. Freeze selected
references, native evidence and expected revision; changed/ambiguous targets
invalidate the proposal. Adoption modifies Igor metadata only. It does not copy
Compose files, add labels, restart services or alter target configuration.
Configuration import is a separate approved transition; target preparation is a
separate capability-backed operation. Failed verification remains visible.

Module installation/enablement registers domain knowledge and contracts.
Provisioning creates external resources through capabilities/plans, with durable
deployment intent/resource slots and History attempt identity before effects.
Native identities are bound and verified at the earliest safe point. Missing
post-effect identity is unresolved, never permission to blindly create again.
Provisioning execution is deferred.

Release ends selected active responsibility; it retains application resources.
Complete detach additionally requires admission fencing, operation reconciliation,
jobs stopped/reassigned, live consumers quiesced, responsibility disposition and
retained configuration/secret-reference classification. Unknown inventories or
legacy sessions block certification. Boundary 1 metadata grant release is not
a detach executor or certificate.

Retain identity, relationship revisions/tombstones, original provenance,
disposition and historical references so old operations remain meaningful.
Retained desired values cannot be applied after release without explicit new
binding/responsibility. Release must not silently reactivate legacy management.

Destroy is separate explicit capability execution, with exact targets,
shared/dependent-resource checks and existing DESTROY policy including exact
`YES` where applicable. Detach, cleanup, package removal and creator provenance
cannot authorize destruction. General destruction is deferred.

## Update, recovery and consistency

Future update/replacement plans freeze providers/versions, compatibility,
binding revision, native incarnations, configuration revisions/migrations,
recovery prerequisites, ordered capability steps and independent verification.
An explicitly approved continuation preserves deployment identity; replacement
participants require new binding revisions. Separate installations receive new
identities. This is not a universal package manager or an implemented updater.

Recovery remains authority-specific: Configuration Service restores desired
values; application capabilities restore supported resources/data; package
compatibility governs code rollback; Deployment Service restores binding and
responsibility records; History retains outcomes/unknown effects. Restoring
records cannot restore applications, manufacture observations or blindly retry
interrupted execution.

Metadata transitions use atomic expected revision/state-token checks and exact
idempotency receipts. Resource/setting conflicts span deployment boundaries.
Recovery changes the local concurrency epoch, invalidates stale proposals and
retains retired identity/receipt fences. No distributed transaction is claimed
across registry, configuration, History and external application effects.
Later admission-time claims and pending metadata transitions may link those
authorities; they cannot become a generic durable-work journal.

## System Model, configuration, modules and AI

System Model owns current evidence. Missing/stale observation never erases
deployment ownership; an accepted relationship never manufactures observed
existence. Projection of intent/responsibility names Deployment Service as its
source rather than creating a second authoritative writer. Provider disablement
removes active contributions while records and independent observations remain
meaningful.

Deployment-scoped configuration is admitted only after its target identity can
be validated. Its setting reference is `(scope_id, deployment_id, setting_id)`;
the module owns schema meaning and Configuration Service owns desired values.
Separate desired, resolved, consumed revision, native observation and verification.
File targets expose concrete source plus stable selector. Unsupported overrides,
ambiguous source selection and guessed paths fail closed. No deployment
configuration scope is implemented by Boundary 1.

One module may support multiple deployments; one deployment may use multiple
modules. Provider selection is explicit; disablement/removal causes unavailable
operations without identity deletion or silent fallback. Preserve the combined
Nextcloud package; migrate only selected contributions when their proof needs it.

Context Routing may surface a redacted owning-service projection, observations,
configuration, History and knowledge. AI may explain/propose; it cannot invent
bindings, accept duties, attach resources or execute by its own authority.
Sensitivity rules apply to locators/endpoints and secret references. Secret
values remain excluded.

## Inspection and persistence

One versioned backend projection exposes identity/revision, application kind,
providers, resource/native bindings, relationships/claims, responsibility,
configuration availability, observations, History references, unresolved issues
and detach implications. Joined sources identify availability/provenance.
Unavailable sources cannot appear as successfully empty. Inspection creates no
scope/store, refreshes no observer and activates no module.

Existing generic 15UI structured rendering consumes the record. Boundary 1
provides a data-only CLI, not a new application screen or default-TUI cutover:

```bash
bash igor.sh --deployments status
bash igor.sh --deployments list
bash igor.sh --deployments inspect DEPLOYMENT_ID
bash igor.sh --deployments export
```

Public Boundary 1 interfaces are read-only. Mutation/recovery methods are
internal Core service interfaces with a trusted deterministic authorizer that
denies by default. Serialized provenance/approval claims cannot authorize.
Later capability adapters remain responsible for approval, privilege,
verification and History; no writable JSON CLI bypass is introduced here.

The internal `DeploymentService` interface explicitly initializes private
metadata, prepares a closed batch and commits it under trusted caller
authorization. Preparation allocates proposal-local opaque references without
persisting them. Commit validates the complete candidate, checks expected
registry revision/state and writes records plus an exact operation receipt in
one transaction. Exact retry returns the receipt; changed requests with the same
operation ID fail. Batch aliases never appear in durable references.

Mutations cover deployment labels/providers, minimal resource enrollment or
reference reuse through an owning-service resolver, explicit native rebinding,
relationships, positive grants, metadata release and claim resolution. Enrolling
an existing object retains its owning-service identity; it does not observe that
object. Lifecycle labels describe registry records rather than live application
state. The closed generic duties are observation, configuration, lifecycle,
backup and update. A metadata grant conveys no execution availability/approval.
Runtime adapters for these duties are not implemented by Boundary 1.

Inspection marks Configuration, System Model and History as `not_supplied`,
verification as `not_verified` and detach as `not_certified` until their actual
owning adapters/inventories are supplied. Public reads expose no authorizer or
reference-resolver execution hook. Structural record validation does not depend
on changing environment secrets; write admission screens sensitive metadata
through the existing privacy boundary. Context/UI consumers retain their
existing last-mile redaction duties.

The registry uses private transactional SQLite, with a closed versioned export
and recovery contract. Atomicity and shared grant conflicts justify a new store.
The service API remains independent of SQL, table names and storage paths.
Unknown versions/corruption fail closed without automatic repair. Restoration
validates the complete document/scope before changing authority, preserves a
recovery point and identities, and invalidates stale concurrency proposals.
Reset/pruning cannot reuse IDs or turn stale observations into current truth.
Recovery retains later IDs/operation fences even when restoring an older export;
later records remain as retained/released metadata rather than disappearing.
There is no generic deletion/reset CLI and no automatic recovery on a read.

## Representative application and legacy cutover

Boundary 3 uses an isolated existing-style Nextcloud deployment's `loglevel`.
It is a non-secret scalar with native readback, a narrower change than network
or trusted-domain configuration. System memory already proves module settings
but not application relationships. Maintenance-window configuration is coupled
to tier-derived generation. The selected loglevel proof exercises explicit
selection/binding, deployment-scoped configuration, capabilities, History,
independent verification, prior-state recovery and release accounting.

Bind the application service, native realization, configuration target and
storage; verified database/cache/endpoint dependencies remain externally managed.
Known compatible fixture version/layout is required. A native configuration
readback proves the reported setting, not complete application health or backup
recoverability. Mocks alone do not close the real application gate.

Current direct writer: `core/diagnose/fixes.sh` has an automatic `nc_loglevel`
fix writing `2`. Generic OCC and saved OCC undo are other writers. The template
`modules/nextcloud_docker/config/nextcloud.config.php.tpl` renders a default `2`,
but its current apply function does not apply that key. The recovery menu displays
exported configuration and suggests import; it does not implement that import.

For an adopted setting, the canonical deployment-scoped workflow is Igor's sole
writer. The old auto-fix delegates to a proposal or refuses; OCC set/delete and
saved undo route through approved change/recovery. Overlapping file edits,
imports, reset and broad recovery refuse when non-overlap cannot be established.
Ambiguous legacy selectors cannot fall back to a default deployment. Unadopted
workflows retain compatibility without acquiring responsibility. External edits
remain possible and are observed as drift. Release does not silently restore
legacy automatic ownership.

## Implementation boundaries and exclusions

1. **Identity, relationships and responsibility:** application-neutral registry,
   explicit authorization, reference reuse/enrollment, conflict handling,
   atomic revisions/idempotency, inspection and versioned export/recovery.
   Prove restart/rename stability, malformed/conflicting rejection, stale
   proposal/restore fencing, read-only CLI/rendering and recovery identity.
2. **Brownfield attachment and composition prerequisites:** [implementation contract](ATTACHMENT.md), narrow observer
   target extension, explicit selection/inspection, metadata-only attachment,
   exact configuration locator, deployment-target admission and bounded release.
   Prove unchanged targets/external origin, ambiguity rejection, provider
   disablement, stale-session fencing and incomplete-inventory refusal.
3. **Reversible application workflow and legacy cutover:** one loglevel schema,
   approved desired/apply/readback/recovery, History and legacy writer retirement.
   Prove real isolated application behavior, wrong-target/drift rejection,
   declined/failed apply distinctions, interruption, recovery and retained release.

Stop and report evidence after each boundary. No boundary automatically begins
the next. Approved design does not authorize provisioning execution, general
destruction, application upgrades, whole-Nextcloud migration, generic workflows,
agents, self-healing, package marketplaces, new AI features or Step 20.
General integration-rule packaging (Q009) remains deferred; interpretation for
the selected proof stays with the existing domain package.
