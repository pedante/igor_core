# Step 19 Boundary 2 — brownfield attachment

This implementation extends [D063](DECISIONS.md) and the approved
[deployment contract](DEPLOYMENTS.md). It stops before Boundary 3. The evidence
and remaining application gate are recorded in [STATUS.md](STATUS.md).

## Authorities and scope

The module supplies deterministic read-only discovery and installation layout
interpretation. Core freezes the proposal and commits only deployment metadata
through the canonical capability dispatcher. Deployment Service owns identity,
relationships and responsibility; Configuration owns desired values; System
Model owns observations; Operational History owns attempts and outcomes.

The selected application is an existing official Nextcloud Compose container.
Discovery uses daemon identity, exact full container identity, creation
incarnation, immutable image identity and Compose project/service evidence.
Names are display information. Zero matches is a nondecision; multiple matches
require an exact container ID. No first-match or default-stack-path fallback is
available. Unsupported layouts require a separate future preparation capability.

The bounded topology represents the logical application service, its current
container realization, the config.php source/selector and backing mount/storage.
No database/cache/network lifecycle or backup authority is inferred. Existing
resource enrollment retains external origin. Another service's known identity
must be reused through the existing owning-service resolver rather than copied.

Only the `nextcloud_docker.loglevel` configuration duty is proposed, supporting
future selected-setting change, deterministic readback and explicit recovery.
There is no general OCC, application/container lifecycle, storage destruction,
backup, upgrade, networking or secret authority. Responsibility does not grant
execution approval or OS privilege. Boundary 2 registers no setting writer and
creates no desired loglevel value.

## Attachment and release

Initialize Igor's private deployment registry through an explicitly approved
metadata capability when absent. Discovery/inspection/proposal preparation
remain read-only. An adoption proposal freezes provider/native evidence,
resource topology, exact target locator, proposed grant and registry
revision/state/epoch. Changed evidence, provider availability/version, metadata
state or an ambiguous selection invalidates it. Approval is explicit even in
Executive mode. A serialized approval claim is never sufficient.

Adoption and scoped release enter the existing execution/History path. Adoption
writes Igor metadata only and rechecks the application independently. The Docker
transport has read-only queries; it cannot execute OCC, edit config.php, restart
containers, copy Compose files, relabel, provision, import secrets or change
filesystem ownership. Source inspection excludes Docker environment values and configuration contents.
A fixed read-only `stat` argv inside the exact selected container verifies a
regular config.php file; it executes no shell or OCC command. File metadata is
frozen with the locator. Missing or unsupported targets fail closed.

Release retains deployment/resource identity, relationships, grants and their
revision provenance, operation references and application resources. Released
grants cannot validate a configuration target. Old proposals and sessions are
fenced by registry revision/state checks. Missing consumer/job/legacy-session
inventories prevent certification of complete detach. Release does not activate
legacy management.

The existing generic chat command `invoke` exposes the registered backend
capabilities. For example, `invoke core.deployments.discover {}` returns
candidates, and `invoke core.deployments.propose {"locator":"FULL_CONTAINER_ID"}`
returns an inspectable frozen proposal. If the registry is absent, use
`invoke core.deployments.initialize {"proposal":"{}"}` and explicitly approve
Igor metadata initialization first. Submit the serialized returned proposal as
`proposal` to `core.deployments.adopt`; do not construct approval claims or
change the proposed bindings. `core.deployments.release.propose` accepts a
`deployment_id` and prepares the retained-resource release proposal for the
separate explicitly approved `core.deployments.release` capability.

`bash igor.sh --deployments inspect DEPLOYMENT_ID` reads the retained metadata
and canonical History references without invoking a provider. Static provider
policy reports disabled/unavailable/not-evaluated status honestly; an enabled
policy alone is not proof of runtime availability.

## Service prerequisites and inspection

Configuration Service validates `(scope_id, deployment_id, setting_id)` through
Deployment Service's active exact grant and provider query. This target admission
check creates no schema, desired value, configuration store or application writer.
Boundary 3 still needs its setting schema and approved apply/readback/recovery.

System Model accepts an exact opaque deployment/resource observer target through
its internal observation contract. Observations retain independent source,
provenance and freshness. Deployment binding cannot manufacture a fact. Missing,
stale or inactive facts cannot erase deployment metadata.

Inspection uses generic backend structures and the existing generic renderer.
Provider-dependent operations become unavailable on disablement; metadata and
historical responsibility remain inspectable. Inspection never silently selects
another provider. Unsupplied observations and unknown inventories remain explicit.

## Relationship to reusable recognition

This Boundary 2 provider is the first narrow domain-specific discovery slice,
not a complete generic discovery service.

The reusable direction is documented in
[RESOURCE_RECOGNITION.md](RESOURCE_RECOGNITION.md): low-level observations and
exact locators feed a reviewed domain recognizer; recognition returns ephemeral
evidence-bound candidates; exact deterministic inspection prepares the frozen
adoption proposal. Deployment Service remains the only owner of accepted
deployment identity/bindings/responsibility.

The existing `core.deployments.discover` path remains valid for this bounded
Nextcloud proof. It must not be generalized by adding Core technology-specific
matching rules. A later reusable coordinator may enumerate eligible domain
recognizers and accept user hints without changing the adoption authority.

A user may point Igor at an exact full container ID instead of requesting broad
enumeration. That is a selector/hint only; all existing provider identity,
layout, ambiguity and freshness checks still apply.

## Compatibility and completion gate

The old migration wizard in `modules/nextcloud_docker/lib/install/migrate.sh`
selects by names/guessed paths and may copy Compose configuration and write
settings/secrets. It remains temporary v1 compatibility and is never invoked by
this metadata attachment path. Full overlapping loglevel writer cutover is
Boundary 3; no application setting writer is activated here.

Deterministic Docker fixtures prove fail-closed contracts and unchanged target
state. They cannot establish that a real installation was inspected. A real
isolated existing Nextcloud environment must supply read-only evidence before
Boundary 2 is declared complete. Do not provision a deployment merely to conceal
that missing gate. No Debian/Arch application support claim follows from fixtures.
