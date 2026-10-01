# Contract-Driven Operator Surface and Namespace Explorer

Status: **initial bounded implementation**. This extends the existing 15UI
frontend foundation and Module API v2 inspection contracts; it does not make
the TUI authoritative or replace Step 18 composition work.

## Purpose

Igor must remain directly operable by a human even as Module API v2 removes
module-owned menu code. The replacement is not a new menu contribution.
Instead, Igor projects the contracts it already owns into a generic operator
surface.

The same declarations can therefore serve multiple interfaces:

```text
module/configuration/capability/check registries
                    |
                    v
           operator projection
          /         |          \
         v          v           v
       TUI        CLI/future     AI
       ":"        interface    catalog
                    |
                    v
          existing authorities
```

A frontend may organize and navigate those records, but it does not acquire a
configuration writer, capability executor, approval authority, privilege
boundary or System Model writer.

## Initial projection

`core/lib/operator_surface.py` builds a bounded, read-only version-1 document
from existing registry snapshots:

- installed/runtime module metadata;
- owner-stamped Module API contributions;
- the existing capability catalog, including Core configuration capabilities;
- Configuration Service declarations.

The projection contains presentation paths, kind, owner, target identity,
availability and bounded kind-specific metadata. Capability rows additionally
carry existing provider, input, safety, privilege, verification and recovery
metadata. Configuration rows contain schema semantics and apply metadata, not
secret values.

The projection is disposable. Its digest is useful for frontend cache/change
detection, but it is not a persistent identity or source of authority.

No extra operator database, capability registry, module registry or command
table is introduced.

## Namespace explorer

In the full-screen AI TUI:

- `Ctrl+P` continues to open the local session-command palette;
- `:` on an empty input opens the contract-driven operator explorer;
- `.` descends through an exact namespace match;
- Enter descends through a branch or selects a leaf;
- Backspace/Esc moves toward the parent/root.

For example, the current v2 System slice can be discovered as:

```text
:
:system.
:system.host.
:system.host.memory.
:system.host.memory.refresh
```

The dotted path is a **presentation/navigation path**, not a second durable
identity scheme. Where a contribution already has a canonical dotted ID, that
ID remains the target. Generic module contributions that are not owner-prefixed
may be displayed beneath their owner so they are discoverable without changing
their contract identity.

If multiple active providers expose the same capability ID, the projection
keeps that ambiguity visible and qualifies the navigation leaf by provider. It
never silently chooses a provider.

## Selection behavior

The first slice deliberately distinguishes browsing from execution.

A capability leaf with no required inputs can become:

```text
invoke system.host.memory.refresh
```

The backend validates that adapter and turns it into the existing structured
`run_capability` request. From that point onward the normal resolver,
preconditions, READ/CHANGE/DESTROY classification, Guide/Assist/Executive
policy, approval, sudo authentication, provider invocation, verification and
Operational History remain authoritative.

A capability with required inputs is not invoked and no values are guessed.
The TUI prepares an `invoke <id> ` draft so the operator can supply an explicit
JSON input object through the same backend route.

Checks, observers, configuration, knowledge, lifecycle, relationships,
automations and domain events are browsable metadata in this first slice.
Selecting them does not manufacture an operation. Rich inspection screens,
configuration editors and lifecycle views may consume the same projection as
their owning backend contracts mature.

## Generated operator UI direction

The namespace explorer is the first generic consumer of the operator projection.
It establishes the missing bridge between v2 contracts and human
discoverability without restoring module-owned menus.

A later generated module view can group the exact same records into sections
such as:

```text
NEXTCLOUD

Overview
Health
Services
Apps
Configuration
Automation
Lifecycle
Information
```

Those section labels are presentation. The behavior underneath remains
configuration, checks, capabilities, lifecycle, observations and other
registered contracts.

This means a module should gain a useful operator surface by declaring useful
contracts rather than by shipping TUI-specific menu functions. The AI, TUI and
future external interfaces can then refer to the same backend objects.

## Resource and refresh model

Browsing and completion are deterministic local operations. They require no
model call and no host probe. The backend publishes an `operator_snapshot`
from its already-loaded registries, and the TUI performs prefix/child lookups in
memory.

The snapshot is refreshed explicitly when the explorer opens and may later be
cached against its digest/revision. Module activation remains restart-based
under the current Module Runtime contract; this slice does not add hot unload.

The current v1 Nextcloud package remains a compatibility module. Its legacy menu
continues to work. This implementation does **not** claim that the v1 Nextcloud
menu has already been synthesized into a full v2 operator view. That requires
its later contract/configuration migration and the Step 18 reversible
application proof.

## Authority rules

The operator surface follows the 15UI rule:

> The backend owns truth and policy; the UI renders state and submits typed
> user intent.

Specifically, browsing or selecting an item cannot by itself:

- activate/disable a module;
- change desired configuration;
- refresh a fact;
- approve an operation;
- grant privilege;
- select an ambiguous capability provider;
- satisfy a precondition;
- change verification;
- enable an automation;
- create a new capability.

The `invoke` adapter is intentionally thin. It constructs only the same
semantic `run_capability` input already accepted by the canonical dispatcher.

## Deferred work

This bounded implementation does not yet provide the complete generated
Nextcloud-style screen. Deferred pieces include:

- generic rich inspection pages for non-capability leaves;
- staged configuration Apply/Discard UX and backend-provided restart/reload
  effects;
- lifecycle/configuration input forms generated from full schemas;
- generated grouping/labels beyond the dotted hierarchy;
- v1 menu-to-v2 contract migration;
- default-launch cutover in Step 20.

Those should extend this projection rather than introduce module-owned UI logic
or another command/permission system.
