# Step 19 — Representative Application Workflow / Relationships and Deployment Ownership

Status: **architecture approved; Boundary 1 complete; Boundary 2 implementation under validation; Boundary 3 in preflight, implementation pending**.
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

Brownfield attachment consumes the recognition boundary defined in
[RESOURCE_RECOGNITION.md](RESOURCE_RECOGNITION.md): deterministic low-level
evidence plus a reviewed domain interpretation produce an ephemeral candidate.
A bounded domain search or an exact user hint may select the target; neither is
authority. Attachment then follows exact candidate selection, deterministic
inspection, proposed relationships/duties, validation, owner approval, durable
binding and independent verification. Freeze selected
references, native evidence and expected revision; changed/ambiguous targets
invalidate the proposal. Adoption modifies Igor metadata only. It does not copy
Compose files, add labels, restart services or alter target configuration.
Configuration import is a separate approved transition; target preparation is a
separate capability-backed operation. Failed verification remains visible.

Module installation/enablement registers domain knowledge and contracts.
Provisioning creates external resources through capabilities/plans under the
separate [Provisioning/Installation](PROVISIONING.md) completion gate, with
durable deployment intent/resource slots and History attempt identity before
effects.
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
   The current Nextcloud provider is the first narrow recognition slice; the
   reusable candidate/recognizer contract is a cross-cutting gate before this
   pattern is expanded to additional domains.
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

## Step 19 loglevel preflight — 2026-10-16

**Subsequent Owner direction (2026-10-16):** execution architecture B is accepted:
a narrow typed Nextcloud adapter through existing canonical dispatch, approval
and configuration. The architectural investigation is closed; the pending-choice
wording below is retained historical preflight evidence. Owner now authorizes
preparation and, where host access is already authorized, initialization of the
[disposable Nextcloud fixture](../../tests/fixtures/step19-nextcloud/README.md).
This supersedes the earlier no-provisioning instruction only for that fixture.
The actual CachyOS host lacks Docker/Compose. Owner subsequently authorized normal
repository package installation, interactive transaction review and focused
testing, preferring rootless. Docker-group membership, socket permission changes,
unreviewed AUR and unrelated host changes are forbidden. See the fixture runbook
for the actual authentication/launcher blockers; no installation has occurred.
No Igor configuration
workflow, change-and-recovery test, commit/push or swap-budget reuse is authorized
by this environment-preparation task.

**Phase: DISCOVERY.** Allowed next action: settle the execution-boundary choice
and validation allowance below, then implement the authorized Boundary 3 slice.
Exit requires a feasible, authorized fixture/consumer validation plan and no
unresolved ownership, secret or privilege prerequisite. No runtime implementation
or Step 19 test execution has occurred. This record is preflight evidence, not
application proof or Owner acceptance.

**Objective/authority/candidate:** one discover → propose → approve → desired
commit → apply → independent native readback → History → explicit recovery path,
under [D063](DECISIONS.md#d063--deployment-identity-relationships-and-scoped-responsibility-owner-scoped-step-19)
and the Owner's current Step 19 instruction. Local `igor2` at
`73a4c06` (`Complete accepted System swap-health package`) was clean before this
documentation checkpoint. The accepted swap closeout is committed; no additional
closeout is needed. No Step 19 commit or push is authorized. Collection Increment
E and Step 20C remain outside scope; E's sources, deferred evidence and allowance
are unchanged.

### Affected integration and failure paths

Each row lists the live contract, required extension, authority, refusal/recovery
behavior and existing coverage. Listed new behavior is a requirement, not code.

| Boundary / concrete consumers | Inputs, outputs and validation | Authority / failure / recovery | Existing coverage to retain |
|---|---|---|---|
| Discovery and target binding: module `lib/attachment.py`, Core `deployment_attachment.py` / `deployments.py` | Exact daemon, full container ID, creation incarnation, immutable image, Compose identity, mount and regular config.php evidence. Deployment setting reference is `(scope_id, deployment_id, setting_id)`. Reuse the active exact `nextcloud_docker.loglevel` grant; never select by display name/default stack. | Deployment Service owns identity/responsibility; the module interprets the layout. Missing/ambiguous/replaced target, changed provider, conflicting/released grant or unavailable daemon refuses before effects. Refresh/repropose explicitly; do not re-adopt silently. | `test_nextcloud_attachment_provider.py`, `test_deployment_attachment.py`, `test_deployment_prerequisites.py`, `test_deployment_attachment.bats` |
| Setting declaration and desired persistence: `configuration_schema.py`, `configuration.py` / `.sh`, loader and module inspection | Today schemas allow only installation/module scope and `_field` accepts one corresponding target. `validate_deployment_target` is admission only. Add the accepted deployment-scoped setting to the existing Configuration authority, including schema discovery, inspect/list, export/restore and retained-record validation. Reject booleans, strings, out-of-range numbers, duplicate/unknown fields and mismatched scope. | Module owns meaning; Core owns validation, desired revisions/state tokens and persistence. No global module setting standing in for a deployment. A desired commit never proves application. Disabled-owner desired records remain inspectable; application stays unavailable. | `test_configuration.py`, `test_deployment_prerequisites.py`, `test_system_configuration_workflow.py` |
| Proposal and stale-state fencing: capability prepare/execute, Configuration and Deployment services | Freeze current native value, desired value, exact binding/provider/version, registry and configuration revisions/state, target evidence and prior-state recovery information. Recheck after approval immediately before effects. Distinguish an absent key from a real prior value; missing/unsupported configuration refuses rather than assuming a default. | Neither serialized approval claims nor reference data grant authority. Reject intervening desired/native/binding/activation changes. Do not silently refresh a proposal after approval. Retain failed attempt identity; obtain a fresh proposal before retry. | Attachment stale/tamper cases; configuration CAS tests; `test_wave_e_capability_dispatch.bats` |
| Module registration and executable provider | Nextcloud is currently API v1 with legacy actions; no canonical loglevel setting/read/apply/recovery contribution exists. `installed_schemas` discovers only validated v2 declarations. Use the existing module contribution mechanism, preserving unrelated live hooks/config/path/secret/menu consumers; do not invent v1 configuration hooks or Core-owned Nextcloud operations. | `nextcloud_docker` owns the application operation. Static installed metadata is not active availability. Recheck live loader state and current disabled policy on prepare and execution, including stale sessions. No alternate provider fallback. | Module contract/lifecycle/inspection tests; attachment disable/stale-session cases |
| Approval, OS privilege and Docker transport | Canonical proposals already freeze safety, privilege, handler and input digest. Existing OCC runs Docker as the Igor OS user, with `www-data` inside the container; the attachment transport permits read-only queries/stat only. Typed privileged module capabilities are explicitly unavailable in loader/dispatcher. | Approval stays in canonical dispatch; OS access remains independent. See the required execution-boundary choice below. No hidden sudo, credential import, arbitrary shell, handler-selected privileged argv or Docker-group/permission change. Permission failure must not report execution success. | `test_wave_e_capability_dispatch.bats`, Core approval/privilege BATS, PTY privilege tests |
| Apply, readback and partial effects | New bounded module OCC adapter must accept only the exact approved target and supported scalar value. Fixed argv, bounded output, closed result shapes and sanitized errors; no config export or Docker environment data. Independent native readback must check the applied value and target; do not echo desired state as observation. Establish the effective configuration source, refusing unsupported overrides. | Provider completion, output validity and verification remain separate. Nonzero execution, timeout, malformed output, unavailable/mismatching readback and interrupted/unknown effect stay unsuccessful or unverified. No automatic retry/rollback. Reconcile native state before another change. | Canonical execution/verification/output tests and System mismatch/failed-apply tests; Nextcloud cases are missing |
| Operational History and reversal | Canonical operation/correlation identity, scoped affected objects, frozen inputs, provider/version, approvals/privilege, execution, output and verification provenance. Retain prior native value and its target identity, plus relevant prior desired state, without secrets. | History owns attempts/outcomes, including refusal after admission and unsuccessful effects. Recovery is a newly approved, stale-checked change through the same path with independent verification; failure remains visible. Do not erase the failed operation or blindly restore over external drift. | `test_operational_history.py`, `test_operational_history_dispatch.bats`, System explicit recovery tests |
| CLI, TUI, AI and inspection: `operator_cli.sh`, capability dispatcher, `operator_surface.py`, `interaction.py`, `tui.py` | Reuse public `capability run`, chat `invoke` / `run_capability`, backend events and shared History inspection. Present current/desired values and target before approval; consume canonical outcomes and validated typed scalar properties. Keep structured/JSON and terminal representations consistent, including absent/malformed results. | Frontends request and render; backend authorizes/executes. Noninteractive approval-required exit stays 3; failure/refusal stays nonzero. Do not add a frontend executor or infer success from text. Exercise actual CLI and curses/backend success/refusal/recovery; unit rendering alone is insufficient. | `test_operator_cli.py`, `test_ai_tui_snapshot_admission.py`, `test_ai_tui_operator.py`, real `test_capability_operator_workflow.py` pattern |
| Competing legacy writers and release | `core/diagnose/fixes.sh` automatic `nc_loglevel`; generic OCC set/delete/import; `undo_stack.py`, journal/module rollback; overlapping host/file edits, module restore, installation migration/reset and broad recovery. Template default is not currently applied by the selected config injector. Include retained/released grants when determining historical adoption. | For the adopted setting, delegate to canonical proposal/recovery or refuse when exact non-overlap cannot be proved. Ambiguous legacy selectors fail closed. Preserve unadopted behavior without creating responsibility. Release fences prepared operations and never silently restores legacy authority. Broad detach remains uncertified. | Existing Diagnose, safety/OCC, undo/journal, module recovery and attachment release tests; adopted-setting cutover cases are missing |

### Execution prerequisite and recommendation

There is **no reviewed canonical privileged Nextcloud OCC adapter**. In
`core/lib/module_loader.sh`, `typed_privileged_output_adapter_unavailable` rejects
typed capabilities requiring privilege; `core/lib/capability.sh` permits only
reviewed exact privileged System argv. Calling the legacy OCC tool would lose
the deployment/desired-state contract and is not a safe substitute.

Two bounded choices were presented to the Owner:

1. **Recommended: existing OS-user Docker access only.** Declare no host privilege
   escalation, use the already-authorized OS user's Docker access, and run the
   fixed setting command as container `www-data`. Access denial fails closed;
   no sudo fallback, remote credential acquisition or permission repair. This
   matches the existing unprivileged Docker transport, with a clearly stated
   support boundary. It still needs the new reviewed bounded setting adapter.
2. **Privileged adapter prerequisite.** First confirm/design a narrowly reviewed
   exact-target OCC privilege adapter through existing native PTY authorization,
   including typed output and independent readback. This changes the currently
   supported privileged execution boundary; do not implement it without Owner
   confirmation. No general Docker executor is proposed.

This is a pending scope choice, not a claim that every Nextcloud installation
requires sudo. Deployment-scoped schema/persistence, the setting adapter and
legacy cutover are implementation work within D063, not additional architectural
blockers. No application secret is needed for this one setting; full config.php,
Docker environment values and application credentials must not enter results,
events, History or AI context.

### Validation plan, evidence and handoff

Required new fixture scenarios: valid discovery/read; reviewed current/desired
proposal and approved apply; invalid/malformed values; missing config; denied
approval/OS access; disabled/unavailable provider before and after approval;
stale desired/native state or replaced/released target; execution failure,
timeout/unknown effect and failed/malformed/mismatching readback; verified
explicit restoration; desired/observed divergence; unsuccessful History;
legacy-writer refusal and stale-operation fencing after release. Include the
actual public CLI and curses/backend consumer with private fixture state.

Contract, regression, vertical-slice, inspection and recovery proof are all
applicable. Use private temporary installation/data/config and an injected Docker
fixture; no real installation writes are authorized. A transport fixture is not
a real Nextcloud application proof. This checkout has no Docker executable or
local `/var/run/docker.sock` or `/run/docker.sock`; no isolated Nextcloud endpoint
has been supplied. Boundary 2's previously open real application gate remains
open. Do not provision a stack or describe fixtures as closing that gate.

The initial runner dry run succeeded with base `73a4c06`, jobs 1, structure plus
these exact groups (no tests executed):

```text
bats:tests/modules/test_deployment_attachment.bats
bats:tests/modules/test_wave_e_capability_dispatch.bats
pytest:tests/test_ai_tui_snapshot_admission.py
pytest:tests/test_configuration.py
pytest:tests/test_deployment_attachment.py
pytest:tests/test_deployment_prerequisites.py
pytest:tests/test_nextcloud_attachment_provider.py
pytest:tests/test_operator_cli.py
pytest:tests/test_system_configuration_workflow.py
```

This is an initial coverage inventory, not the final execution selection. Add
the setting workflow, legacy-cutover and real operator fixture tests alongside
implementation; inspect the final affected dry run before scheduling. Select
small exact node groups where existing files exceed the command ceiling. The
earlier System workflow record reports 108.60 seconds standalone; this is a
planning reference, not a current measurement. Provisional envelope: 900 seconds
cumulative, 240 seconds per command, jobs 1; estimate 600–750 seconds for focused
and affected groups, reserving 150 seconds for a demonstrated correction and
closing documentation. Recalculate from final selected groups before spending;
do not promise that a broad affected sweep fits this estimate. Prefer governed
CI for any required remainder. No full suite is authorized.

**Budget:** `.igor-governor/budget.json` retains **46.02779241499229 seconds**, with
authorization `Owner authorizes bounded swap-health validation continuation`.
It is not a new Step 19 allowance. Step 19 governed test time spent: **0 seconds**;
the dry run reported 0.011 seconds and consumed no validation allowance. Request
Owner-terminal Step 19 authorization before executing the planned tests; the
agent must not use `--new-budget` itself or spend E's deferred allowance. A
suitable Owner-terminal initialization, after confirming the scope, is:

```bash
bash tests/validate.sh focused --base 73a4c06 --only-group structure \
    --new-budget "Owner authorizes Step 19 Nextcloud fixture validation" \
    --total-timeout 900 --command-timeout 240
```

Stop on exhausted allowance, a missing ownership/secret/privilege prerequisite,
or an inconclusive acceptance instrument. Inspect failure logs/assertions before
any targeted correction; retain unaffected evidence. No repeated broad runs.

**Review/handoff:** no runtime candidate exists and independent implementation
review is not ready. Author source inspection establishes the inventory only.
Remaining Owner inputs are the Docker privilege support boundary and terminal
validation allowance; real isolated application evidence remains separately
unavailable. Checkpoint files are this section and the linked current focus in
`STATUS.md`. Documentation parsing/link checks remain unexecuted pending the
allowance; Git diff inspection is separate from runtime validation. No agents,
implementation commit, push, Step 20C or Collection E work is authorized here.
