# System / `:sys` Operator Evolution — Discovery Proposal

Status: **D070 accepted; S1–S3 merged and S4 implemented on the storage feature
branch pending validation.** The discovery rationale is retained here as the
design record.

Current S4 branch: `feature/sys-storage-read-model`

## Purpose

Evolve the existing first-class `system` Module API v2 package into a
high-quality everyday Linux administration surface covering host, storage,
networking, services, users/permissions, configuration, packages, logs and
health, with deterministic typed selection/completion where useful.

The intended user experience may eventually include interactions such as:

```text
:sys.service.restart <select an existing unit>
:sys.storage.mount <select a filesystem> <select or enter a mountpoint>
:sys.permissions.owner <path> <select a user>
:sys.network.wifi.connect <select an observed network>
```

These examples describe product intent only. They are not accepted capability
IDs or input schemas.

## Discovery findings

### 1. Do not create a second module

The repository already contains `modules/system/` as Module API v2 package
`system`, currently version 2.5.0. It already owns host-domain semantics and
declares host, package, service, log, memory, configuration and administration
capabilities.

The accepted D020 boundary assigns reusable Linux mechanisms to Core/Platform
and host observations, health meaning, knowledge and higher-level
administration to `system`. A separate `sys` or `sysadmin` package would
split that domain and risk ambiguous providers.

**Proposal:** all work remains under `modules/system/`. The canonical package
owner and capability prefix remain `system`.

### 2. `:system.*` already exists as a generated operator surface

The current Operator Surface derives dotted paths from registered contracts.
It already exposes entries such as `:system.host.summary`,
`:system.service.status` and `:system.service.restart`. It does not use a
System-specific menu or duplicate execution path.

Capabilities with required inputs currently create an explicit invocation draft;
the frontend does not guess values. This is the correct authority boundary to
extend.

**Accepted/implemented in S3:** `:sys` is only a presentation alias for the
existing `:system` tree. `:system` remains valid and all backend IDs remain
`system.*`. The Operator Surface projects the alias only while the canonical
`system` root exists and no real `sys` root collides with it.

### 3. Do not invent a second entity/inventory model

Host Intelligence already defines System Model object identity and provenance.
Examples include:

```text
host:local
mount:/
service:systemd:docker.service
package:docker.io
interface:eth0
module:system
```

The System Model already separates object identity, observed/configured/desired
state, freshness and responsibility.

**Proposal:** reusable machine state continues to use that model. The new work
does not introduce `system.service`, `system.filesystem`, etc. as a second
durable entity database merely to support completion.

### 4. The missing layer is semantic input selection

Capability schemas already define typed input properties and validators. The
Operator Surface already projects those properties. What is missing for the
desired experience is a generic way for a property to say, conceptually:

- this value selects an existing systemd service;
- this value selects a mountable filesystem;
- this value selects an existing user/group;
- this value is an absolute path with mountpoint semantics;
- this value selects an observed network interface or Wi-Fi network.

That semantic declaration should let a shared TUI/CLI candidate UI operate
without System-specific frontend code.

**Proposal:** after Q014 is accepted, extend the existing input-property
descriptor with one small optional selector declaration. Do not add another
contribution kind unless real evidence later requires one.

An illustrative, **non-authoritative** shape could be:

```json
{
  "unit": {
    "type": "string",
    "validator": "systemd_unit",
    "selector": {
      "kind": "resource",
      "object_kind": "service"
    }
  }
}
```

The exact field names and allowed values are deliberately not fixed by this
proposal.

Selection metadata never replaces the property's validator, capability
preconditions, safety tier, approval, privilege or verification.

### 5. Candidate data is not machine truth or recognition

Dynamic completion requires current candidates, but a candidate list is not
itself durable machine memory.

The candidate path must remain separate from:

- System Model facts and their authoritative freshness/provenance;
- Resource Recognition candidates used to interpret/adopt domain resources;
- Deployment bindings/responsibility;
- capability authorization and verification.

**Proposal:** after Q015 is accepted, use one Core-owned ephemeral candidate
resolver. It may project eligible fresh System Model state or perform a bounded
normalized Core/Platform READ explicitly allowed by the selector contract.
Candidates are cheap to recompute and never persisted merely because they were
shown.

A chosen value becomes ordinary capability input and is validated again by the
canonical dispatcher. Selection cannot create authority.

### 6. Completion must be deterministic and bounded

Completion/typeahead should not invoke the AI. It should not recursively scan
the filesystem, sweep networks or expose secrets.

For paths, prefix expansion such as `/e<Tab> -> /etc/` can be deterministic.
For semantically constrained paths, ranking should respect the purpose. A
mountpoint selector should normally rank conventional mount roots such as
`/mnt`, `/srv` or `/media` ahead of an unrelated `/etc` path.

A second Tab should show/rank children or candidates; it should not silently
choose an arbitrary state-changing target.

### 7. Start with services, not storage mutation

The System package already has:

```text
system.service.list
system.service.status
system.service.start
system.service.enable
system.service.restart
```

The unit inputs already have validation/preconditions, Core has normalized
systemd mechanics, and focused regression tests exist.

That makes service selection the safest real vertical slice for proving a
generic selector/candidate contract.

Storage is a high-value second domain, but mount/unmount adds privilege,
filesystem identity, target-path, persistence and verification questions. It
should consume the proven generic input-selection contract rather than be used
to invent it.

## S1/S2/S3/S4 implementation status

S1 provides the strict selector contract, Core candidate envelope/registry,
Operator Surface projection and cache invalidation boundaries.

S2 uses the existing System service capabilities as the first real consumer.
The `unit` inputs on status/start/enable/restart declare the shared
`resource_kind=service` selector. The backend re-resolves the active
capability/provider, uses Core's bounded `svc_list_query` Platform read, and
emits ephemeral candidates. The TUI can filter and select those candidates.
Candidate browsing does not run a capability; the chosen unit is submitted
through the unchanged canonical `invoke` path.

Manual JSON input remains available from the chooser via Tab.

S3 adds the collision-safe `:sys` presentation alias in the shared Operator
Surface projection. The TUI can keep `:sys...` in its breadcrumb while
navigation and invocation continue to use canonical `system...` paths. A real
top-level `sys` namespace suppresses the alias rather than being shadowed.

S4 adds the first storage read model without crossing into storage mutation.
Core normalizes bounded Linux mount and filesystem discovery; the System module
publishes `storage.mounts` and `storage.filesystems` collection observers into
the existing System Model using canonical `mount:...` and
`filesystem:...` identities. Collection refresh is atomic, removes disappeared
objects, and stales prior facts after a failed refresh without inventing phantom
objects.

The operator surface adds read-only `system.storage.summary`,
`system.storage.mounts.list`, `system.storage.filesystems.list`,
`system.storage.mount.status` and `system.storage.filesystem.status`.
Mount/filesystem status inputs reuse the S1 selector contract. Candidate
resolution prefers fresh System Model facts and falls back to the same bounded
Core read when those observations are absent or stale. No mount, unmount,
filesystem change, fstab edit, sudo path or persistence mutation is introduced
by S4.

## Proposed architecture

```text
Module API capability input schema
        |
        | optional semantic selector metadata
        v
Core candidate-resolution boundary
        |
        +---- fresh eligible System Model projection
        |
        +---- bounded normalized Platform READ
        |
        v
Operator projection
        |
        +---- TUI chooser/typeahead
        +---- future first-class CLI completion/selection
        |
        v
explicit selected value
        |
        v
existing capability prepare
 validator -> preconditions -> safety -> approval -> privilege
        |
        v
existing execution + deterministic verification + History
```

Authority remains exactly where it is today. The new layer improves selection
and discoverability; it does not create another executor.

## Boundaries for the first implementation

After Q013–Q015 are reviewed, the first implementation should stay deliberately
small:

1. accept one bounded selector metadata shape on capability input properties;
2. project it through the existing Operator Surface;
3. implement one read-only candidate resolution API with inspection;
4. annotate the existing System service `unit` inputs;
5. provide candidates from the existing normalized systemd read path;
6. let the TUI choose/type a unit without requiring hand-written JSON;
7. submit the same canonical capability request used today;
8. retain `:system.*`; add `:sys` only if Q013 is accepted.

No storage mutation, Wi-Fi mutation, new persistent store, recognizer
contribution, custom System frontend or new module is part of that first slice.

## Proof plan

The implementation boundary should satisfy Igor's five proof classes.

### Contract proof

- malformed/unsupported selector metadata fails strict Module API validation;
- selector metadata cannot alter input validation, safety, provider, privilege,
  verification or affected-object semantics;
- malformed candidate results fail closed;
- candidates have bounded count/size and no secret values.

### Regression proof

At minimum preserve relevant coverage in:

- Module API v2 contract/loader tests;
- `tests/test_operator_surface.py`;
- `tests/test_ai_tui_operator.py`;
- `tests/modules/test_system_admin_surface.bats`;
- capability approval/privilege regressions.

The full required affected gate is determined at implementation time.

### Vertical-slice proof

An active System module exposes a service selector, the frontend displays
current service candidates, the operator selects one, and the existing
`system.service.status` or `system.service.restart` path receives the exact
explicit unit input.

For CHANGE, ordinary approval/privilege/verification remains unchanged.

### Inspection proof

A backend inspection must answer:

- which input has a selector;
- which resolver/source is eligible;
- candidate availability/failure;
- source/freshness where applicable;
- selected value remains merely input, not authority.

Browsing does not itself run a capability.

### Migration/recovery proof

The first slice introduces no persistent state and changes no durable object
identity. Existing capabilities and explicit JSON invocation remain valid.
`:system` remains valid even if a `:sys` alias is later accepted. Disabling
`system` removes its active selector contribution together with its active
capabilities.

## Probable roadmap and effort guide

These estimates are engineering-sizing guidance, not commitments. Several later
phases can overlap with existing Igor 2 completion work.

| Phase | Outcome | Rough focused effort |
|---|---|---:|
| S0 — Discovery & decisions | This proposal, Q013–Q015, scope/proof gate | current |
| S1 — Semantic input contract | Strict optional selector metadata, generic projection, candidate envelope/API, tests | 1–3 days |
| S2 — Service vertical slice | Existing service inputs gain dynamic selection; TUI chooser/typeahead; canonical execution unchanged | 2–4 days |
| S3 — Namespace UX | **Merged:** `:sys` presentation alias, collision-safe navigation, canonical IDs unchanged | complete |
| S4 — Storage read model | **Implemented on feature branch:** bounded mount/filesystem observations, canonical System Model identities, read-only `system.storage.*` inspection and selectors | complete pending validation |
| S5 — Storage changes | Mount/unmount capabilities with frozen targets, Core privilege mechanics, verification and explicit persistence semantics | 4–8 days |
| S6 — Users, groups, permissions & paths | Bounded user/group/path selectors plus safe inspection/change capabilities | 3–6 days |
| S7 — Network & Wi-Fi | Interface/route/DNS inspection; Wi-Fi only through a reviewed provider/secret-reference/verification contract | 5–10 days |
| S8 — Broader System catalogue | Hardware, boot, time, security, richer logs/packages/health; read-first and selectively verified mutations | 5–15+ days iterative |
| S9 — Cross-module reuse | Other modules consume canonical System capabilities/objects instead of duplicating host mechanics | 2–5 days |
| S10 — Step 20 polish/release gate | CLI/TUI parity, rich generated views, performance budgets, five proof classes and release regression | 4–8 days |

### Scope rule for Igor 2

Igor 2 should require the **generic mechanism and representative high-quality
System domains**, not an exhaustive clone of every Linux command.

A sensible release standard is:

- one canonical `system` module;
- generic typed/semantic input selection;
- deterministic candidate resolution;
- excellent read/inspection coverage for core administration domains;
- a smaller reviewed set of state-changing operations with real verification;
- no frontend-specific domain authority;
- no AI dependency for completion;
- continued Debian/Arch claims only where tests prove them.

Additional domains such as Bluetooth, printers, SELinux/AppArmor, ZFS/Btrfs
special operations, sensors and unusual init/network stacks can grow after the
generic contract is proven.

## Open questions

The public-contract questions raised by this discovery are recorded in the
authoritative decision log:

- Q013 — `:sys` presentation alias versus canonical `system` identity;
- Q014 — bounded semantic selector metadata on capability inputs;
- Q015 — dynamic candidate source, freshness and authority.

D070 resolves these questions. S1 implements the generic selector/candidate
foundation, S2 is the first real System consumer, and S3 adds only the accepted
presentation alias/navigation layer.
