# Module Platform v2 — selected design

Status: **accepted Wave C contract with the first implementation complete**. V1
remains the compatibility API for modules that have not migrated. The existing
loader remains the single activation authority; the strict validator,
owner-aware contribution index and Bash adapter implement the initial v2 path.
The kind-specific observer and check result/ingestion contract selected for
Wave D is in [HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md); it extends this
existing envelope when implemented.

Step 18A's architecture is approved in D060. Boundary 1 completes the bounded
capability output/version and inspection contracts below; composition
prerequisites and the reversible application proof remain separate boundaries.
Current validation and migration evidence belongs in [STATUS.md](STATUS.md).

## First-class module boundary (Step 18A)

A module is a portable reviewed package that teaches and operates a coherent
domain. It may contribute knowledge, schemas, observers, checks, capabilities
and lifecycle operations without owning another Igor runtime. Knowledge-only
packages remain valid. Modules do not own configuration storage, authorization,
privilege, policy, scheduling, history or custom frontends.

Four concepts remain separate:

| Concept | Meaning and authority |
|---|---|
| Package | Replaceable code, knowledge, templates, declarations and compatibility metadata. |
| Registration | Core's validated, owner-stamped, eligibility-aware contribution view. |
| Binding | Igor-owned association with machine objects, settings, secret references and selected providers; general deployment reconciliation remains Q007. |
| Operational record | Typed state, History, Investigations and local learning under their respective owning services. |

Modules supply domain meaning and implementation. Core owns module identity
admission, lifecycle enforcement, dependency evaluation, security, approval,
privilege, execution, provenance and Operational History. Configuration retains
D059: modules declare defaults/types/domain validation and application needs;
Core owns desired values, precedence, revisions, validation sequencing,
persistence and migration orchestration. Application-native settings remain
external authority unless explicitly adopted; discovering a file does not
transfer ownership to Igor.

Module knowledge answers what a component is and how it may operate. System
Model answers what is currently known; History records what happened;
Investigations organize questions/hypotheses/evidence; Context Routing selects
relevant eligible reference material. Runbooks/patterns are procedures/reference
data until explicitly promoted through reviewed capability contracts. Source
instructions, confidence or successful prior outcomes cannot activate code,
register actions, change facts or authorize execution.

Shipped knowledge is explicit package content, distinct from installation-local
learned artifacts. Domain metadata belongs with contributions rather than Core
keyword tables. AI receives eligible knowledge and capability descriptions and
may propose typed intent; Core resolves it. Module-provided prose cannot change
model roles, policy, ownership or available tools.

## Capability output and compatibility contract (Boundary 1)

Package version, Module API version, contribution-envelope version, capability
version and configuration schema version have independent meanings. Updating
package code does not silently change an operation's observable contract.
Version 1 remains compatible with existing capability declarations. Version 2
adds mandatory typed domain outputs and retains the same Core execution path;
this is not Module API v3 or a second action registry.

Version 2 declares `outputs` as a closed object with `schema_version: 1`,
`properties`, `required` and `additionalProperties: false`. The bounded fields
are string, integer, finite number, boolean, enum and object ID. Unknown schema
versions, fields/types, invalid constraints/default assumptions and malformed
results fail deterministically. Secret material and arbitrary file/path outputs
are not admitted as typed domain properties. Rich nested schemas remain deferred
until a real consumer requires them.

Core validates the handler's domain result against the frozen output contract.
Domain data cannot supply its own execution, verification, owner, safety,
approval or privilege status. Provider completion, output validity and
verification are separate facts. Invalid output after a provider completed may
still mean the system changed: retain execution completion, report invalid
output/unknown verification, record the attempt in History and never claim
success or automatically retry. Do not retain the rejected raw payload as
ordinary result/audit material.

Requests/plans may pin an exact supported `capability_version`. A mismatch fails
before handler effects; pending approval must retain and recheck the selected
version/provider/descriptor. Unpinned compatibility callers use the currently
resolved supported contract. A breaking input/output change requires a new
supported capability version or ID, with explicit consumer migration. There is
no version-range solver, silent provider substitution or reinterpretation of
historical operation references.

The existing `system.host.memory.refresh` operation proves version 2 with a
closed `observer_id` output identifying `host.memory`. No new domain operation,
privileged adapter, secret consumer or real module configuration migrates here.
The package version is `2.1.0`; Module API remains 2. Privileged version-2
declarations remain unavailable until a reviewed Core adapter supplies typed
output; the existing version-1 privileged adapter retains its behavior. A
version-2 success result requires valid typed output, not merely a zero command
exit. Retained version-1 History stays inspectable; recovery cannot silently
verify it through the current version-2 contract.

## Composite capability providers

A capability may be implemented either by one declared handler or by one
data-only `implementation.kind=composition`; it cannot declare both. Composition
does not add another contribution kind, tool namespace or execution engine.
The capability ID remains the public operational contract while Core resolves
its implementation into the existing immutable plan value.

The bounded composition contract contains platform variants, an ordered list of
canonical child capability requests and one typed READ final check with expected
output fields. Variant selection is deterministic and exactly one supported
platform family must match. Child inputs are literal JSON data or direct parent
input references; arbitrary expressions, shell, loops, branching, step-output
chaining, parallelism and nested composite capabilities are not admitted.

External child capability IDs must exactly match the capability-level
`requires.capabilities` declaration. Resolution freezes each child provider,
capability version and validated input before effects and hashes the resulting
plan. Execution then re-enters the canonical capability dispatcher for every
child, preserving ordinary policy, approval, privilege, exact-argv and
verification behavior. A failed step or final expectation stops the sequence
and records completed steps; there is no implicit retry or rollback.

The final check must resolve to a capability-version-2 READ provider with typed
outputs. Its expected fields are validated against that output schema and are
compared deterministically after the child invocation. This allows a domain
capability to verify its intended outcome without treating process exit or AI
interpretation as proof.

A resolved plan is therefore an execution artifact of a composite capability,
not a separately registered operation. Interfaces continue to invoke the same
canonical capability API.

## Inspection and detach accounting contract (Boundary 1)

One structured projection combines manifest/registry metadata with owning-service
snapshots where available. It distinguishes package/policy/activation,
contribution availability, dependencies, capabilities, knowledge, configuration
declarations, System Model evidence and lifecycle/detach impact. The projection
does not become another configuration, state, History or binding store.

Static package inspection is data-only and never sources module code, loads
legacy shell configuration, migrates policy, initializes persistent stores,
authenticates or probes applications. Enabled policy is not active state: static
inspection reports activation as not evaluated. A loaded backend may supply
actual process-local registration/model snapshots without invoking an observer.
Missing desired/application/health information remains unavailable; declarations
and defaults do not manufacture observations or success.

15UI consumes these structured backend records through its reusable renderer;
this boundary supplies the contract without adding custom module UI or moving
authority into presentation helpers.

The data-only CLI is:

```bash
bash igor.sh --modules inspect system
bash igor.sh --modules detach-plan system
```

The existing `--modules` text listing remains compatible. A loaded backend uses
`igor_module_inspect NAME` or `igor_module_detach_plan NAME`; these query existing
registrations/model/configuration snapshots without loading another package or
refreshing facts. Both return a version-1 inspection envelope. Static CLI
activation is `not_evaluated`, not a live status inferred from enabled policy.
Detach `ready` remains false while accounting is incomplete. Unknown inventories
remain explicit even when the module is disabled.

Detach removes management participation/responsibility, not necessarily retained
resources. A read-only assessment accounts for known contributions/dependencies
and explicitly names absent session, binding, resource, secret and responsibility
inventories. Incomplete accounting cannot certify detach. Existing-process
replacement remains restart-based; no hot unload is implied.

The long-term lifecycle distinguishes package installation, enablement,
attachment/adoption, provisioning, disablement, detachment, code removal,
resource destruction and update/replacement. Provision/apply/migrate/destroy
operations use canonical capabilities and declared recovery; package deletion
does not erase desired values, History or investigation evidence. Dependents
become explicitly unavailable without automatic enable/install/provider switch.
Restoring old code is safe only when retained schema/data contracts are compatible.

Boundary 2's owner-authorized integration proof uses the existing `system`
package, its typed READ capability and packaged knowledge. An isolated copy adds
a test-only configuration declaration to prove schema admission and inspection
through Step 17 without inventing a production setting or migrating legacy
values. Runtime inspection is consumed by the existing generic 15UI renderer;
the proof does not add a live Modules panel or make the TUI the default.
Context Routing receives eligible knowledge candidates with the package version
from Core's validated registration. Candidate content remains reference data.

General bindings/resource ownership and responsibility transfer remain gaps
to resolve only as required by the selected Boundary 3 workflow. This composition
proof does not establish deployment authority, certify detach or provide a
general module configuration write CLI. Boundary 3 uses the owner-approved
System memory warning policy (D062), not a complex application migration.
Broad migration, structural splitting,
marketplaces, signing/isolation, dependency installation and autonomous module
generation remain outside this boundary. Reviewed local Bash code is trusted
executable code, not a security sandbox.

Boundary 3 adds one real managed System schema and typed application/readback
capabilities. Core commits desired state; the reviewed System consumer applies
only the current-process memory warning policy. Independent readback and Core
verification keep desired state separate from runtime evidence. Both CHANGE
operations retain ordinary approval and privilege enforcement; recovery is a new
explicit same-path operation. [The workflow](SYSTEM_MEMORY_WORKFLOW.md) describes
the setting, state distinctions and limits. This proof creates no configuration
facts, generic settings UI or complete detach guarantee.

## Choice and boundary

The public v2 contract is language-neutral data. Wave C implements a Bash
handler adapter because both shipped modules are Bash. Python is already an
Igor dependency, but no current module needs a Python execution adapter; one
can later implement the same JSON invocation protocol without changing module
identity or contribution metadata. A declared unsupported runtime is
unavailable with a clear reason, never guessed as Bash.

### Execution and ownership boundary

Wave C implements the accepted contribution/handler contract without turning
the current repository layout into a permanent storage API. Module v2 may
declare configuration/state/secret needs, but canonical paths, mutable
machine-specific storage and secret-value access are owned by Igor services,
not by arbitrary paths inside a module package.

Wave C uses a small part of `system` as the incremental v2 reference and keeps
`nextcloud_docker` on v1. Completion follows `EXECUTION.md`: strict contract
proof, regression proof, a real `system` slice, module inspection, and any
required migration/recovery proof. Broad application-module migration waits
for the Ownership Foundation gate in `ROADMAP.md`.

| Option | Repository consequence | Decision |
|---|---|---|
| Extend Bash hooks as the v2 API | Smallest immediate edit, but ties observers, actions and future events to shell function names, in-process globals and current hook output formats. | Reject as the public contract. Keep as v1 compatibility. |
| Language-neutral handlers for every language now | Requires process adapters, packaging and failure semantics without a real non-Bash module. | Defer adapters beyond Bash. |
| Language-neutral declarations and invocation envelope, Bash first | Uses the existing loader and Python JSON tooling; preserves shipped modules and leaves a concrete adapter seam. | **Selected.** |

The API knows **what** a module contributes, its identity, requirements,
owner, schemas and policy metadata. An adapter knows **how** to invoke a
handler. The adapter cannot change activation, authorization or ownership.

## Package and bootstrap manifest

```text
modules/system/
├── module.conf                 # discovery, version, runtime, requirements
├── contracts/
│   └── host.json               # explicitly listed contributions
├── module.sh                   # Bash handlers and temporary v1 hooks
├── knowledge/
│   └── host.md                 # static reference material
└── checks/                     # v1 compatibility until checks migrate
```

The small INI-style `module.conf` remains hand editable. V2 uses a strict,
section-aware, data-only parser with unique keys and comments on separate
lines. The v1 first-matching-key parser remains only for v1 packages; it
ignores sections and retains inline comments, so it must not parse v2 policy.

```ini
[module]
module_api=2
name=system
display_name=System Administration
version=2.0.0
runtime=bash
entrypoint=module.sh
contracts=contracts/host.json

[requirements]
required_modules=
optional_modules=
required_capabilities=
optional_capabilities=
platform_families=
required_bins=systemctl

[compat]
v1_hooks=true
```

This is the current `system` v2 manifest shape. `runtime` and `entrypoint` are
omitted for a metadata-only module; handler-bearing packages declare both.
`contracts` is an explicit comma-separated list; a small module can use one
file. The loader never scans a directory to infer v2 contributions. Contract
paths and handler entrypoints must remain inside the package. Module identity
must match its directory; the package version is independent of `module_api`.
The current v1 `requires_core` value is unenforced metadata and is not a v2
compatibility gate. V2 rejects unsupported API/contract versions explicitly.

JSON is used for nested declarations because Python's existing standard
library parses it on supported Python 3 versions, and it supports deterministic
validation without another dependency. TOML would require an unestablished
Python 3.11 minimum or a package; YAML requires a new parser. Keeping every
declaration in INI would create another custom nested syntax. JSON's lack of
comments is acceptable in a small contract file; explanatory prose belongs
in adjacent Markdown.

| Format option | Fit here |
|---|---|
| Extend current INI for everything | Preserves hand editing, but the current parser is section-blind and nested handlers/schemas would require custom syntax. |
| One JSON manifest | Easy to validate, but replaces simple edited identity/dependency files and loses comments at the bootstrap layer. |
| Small INI manifest plus explicit JSON declarations | Preserves current discovery and comments while giving nested contracts a standard parser. **Selected.** |
| TOML | Good editing ergonomics, but `tomllib` is only standard from Python 3.11 and Igor has no established 3.11 floor. |
| YAML | Readable, but adds a parser dependency and ambiguous scalar behavior for no current need. |

## Contribution declarations

Each listed JSON file has one versioned envelope and an array of optional
contributions. A module with only knowledge and observers needs no empty hook
functions. The loader derives `owner=system` from the active package; a file
cannot claim a different owner.

```json
{
  "contract_version": 1,
  "contributions": [
    {
      "kind": "knowledge",
      "id": "host.basics",
      "path": "knowledge/host.md"
    },
    {
      "kind": "observer",
      "id": "host.memory",
      "handler": "system__observe_memory",
      "output_type": "host.memory",
      "timeout_seconds": 10
    }
  ]
}
```

The common descriptor fields are `kind`, canonical `id`, optional
`requires`, and a `path` or `handler` where applicable. A contribution's
`requires` object has optional arrays named `modules`, `capabilities`,
`platform_families`, `platform_features` and `bins`; the same missing-provider
rules apply only to that contribution. `platform_families` is an allowed-family
set; other requirement arrays are all-of. Wave C validates
`platform_families` and `bins` against current helpers; `platform_features`
is reserved until Step 7 defines normalized feature names. An unsupported
feature requirement is unavailable, never assumed satisfied. IDs are unique
within each module and kind. A duplicate non-capability ID across modules
cannot activate twice; duplicate capability IDs remain visible as ambiguous
providers and cannot satisfy a requirement. The registry records source file,
API version and owner separately. Duplicate IDs within a package, path escapes, unknown required fields,
duplicate JSON keys, unsupported kinds/versions and missing handlers fail
validation. The same canonical contribution is never dispatched through both
v1 and v2 for one consumer. Static metadata is registered without running
module code.

| Contract | Declarative part | Executable part, if any |
|---|---|---|
| Identity | Manifest name, display/version, requirements and API version. | None. |
| Knowledge | Explicit file/reference ID; treated as untrusted AI reference data. | None for static files; generated knowledge may name a handler later. |
| Observer | ID, output type, timeout, cost/freshness and requirements as supported. | A handler returns observed data; Step 9 defines richer fact fields and System Model ingestion. |
| Capability | ID, input shape, safety tier, privilege need and requirements. | Wave E dispatches complete declarations through the shared approval, privilege and verification path. Bare Wave C declarations remain inspectable as `contract_incomplete`; privileged or secret-using declarations require a reviewed Core adapter before becoming executable. Recovery is metadata or a separate normally authorized capability, not automatic rollback. |
| Check | ID, input/result type and requirements. | A handler evaluates evidence; Step 10 defines the shared result consumed by Diagnose and Healing. |
| Domain event | Event type and payload identity. | Emission uses Igor's later domain event API, not `core/ai/events.sh`; no arbitrary event handler is activated in Wave C. |
| Automation | Proposed trigger and canonical capability reference. | Igor schedules and invokes the capability in Step 14; modules do not schedule directly. |
| Relationship | Type and participating object types. | Optional discovery through an observer; Step 17 defines provenance and reconciliation. |
| Configuration | D059 adds a closed version-1 `schema` with owned fields, types, defaults, scope, sensitivity and application semantics. | Declarative schemas need no handler. Core owns mutable values and storage; handler-only legacy declarations stay unavailable. Real module settings remain on their current compatibility paths until separately migrated. |
| Lifecycle | Explicit install/upgrade/remove handler IDs; enable/disable remains runtime policy. | Named handlers run under the normal approval/privilege boundary; removing a package is distinct from destroying managed resources. |

Wave C establishes the common descriptor and invocation envelope and makes the
first knowledge/observer reference case usable. Later roadmap steps add richer
kind-specific fields and consumers. A declaration for a kind whose dispatcher
is not implemented is visible as unavailable metadata and is neither
advertised as an executable action nor scheduled. V2 does not add ten new
registration hooks.

## Configuration declaration (Step 17 foundation)

The existing contribution envelope can carry a data-only schema:

```json
{
  "contract_version": 1,
  "contributions": [{
    "kind": "configuration",
    "id": "fixture.settings",
    "schema": {
      "schema_version": 1,
      "fields": [{
        "id": "fixture.enabled",
        "type": "boolean",
        "scope": "module",
        "default": false
      }]
    }
  }]
}
```

Core stamps the owner/source from the package. Module setting IDs must belong
to that module's namespace and use module scope. Schema versions, unknown
fields, invalid defaults and duplicate/foreign IDs fail validation as data;
inspection does not source disabled code. `igor_configuration_declarations`
returns eligible active schemas from the existing contribution index.
The configuration consumer owns scoped value admission and validation; the
module loader does not write values or apply settings.

See [CONFIGURATION.md](CONFIGURATION.md) for D059's authority split, exact
bounded implementation, secret/reference policy, persistence and migration.
This step uses fixtures to prove declaration admission; neither bundled
module's configuration values migrate.

## Handler invocation

V2 handlers use one backend invocation boundary. The runtime first checks
active ownership, contribution requirements, safety/approval and privilege
policy where applicable. The Bash adapter loads the declared entrypoint in an
isolated process and calls the named function with one JSON request on stdin.
The function must use the owning module's `<name>__*` prefix; a handler name
is never evaluated as shell text. It accepts exactly one JSON response on
stdout; stderr is diagnostic only.
Timeout, nonzero exit, malformed JSON or unsupported result shape fail closed.
Unlike v1's copied-function hook runner, this allows package-local helpers to
be sourced deliberately and never relies on parent shell mutation.

```json
{"api_version":2,"contribution_id":"host.memory","input":{}}
```

```json
{"status":"ok","result":{"available_bytes":123456}}
```

Failures use `{"status":"error","error":{"code":"...","message":"..."}}`.
The runtime supplies and retains owner, invocation identity and policy facts;
handler output cannot set its own owner, tier, approval, privilege or active
state. Kind-specific `result` schemas are introduced with their consumers,
not invented by the generic adapter. No arbitrary shell command in contract
JSON is treated as an executable capability.

## Dependency and platform semantics

| Declaration | Meaning and absence behavior |
|---|---|
| `required_modules` | Exact provider identity is necessary. It is a hard load-order edge. Missing, disabled or unavailable provider makes the dependent unavailable with a named reason; no automatic enable. |
| `optional_modules` | Integration may be used if active. It never blocks base activation or enables the provider. Runtime contribution requirements gate integration-only behavior. |
| `required_capabilities` | Use a canonical capability ID when any provider would satisfy the need. Core finds a unique provider, orders it before the consumer and requires an active, executable capability; absent, disabled, failed, unsupported or ambiguous providers make a module-wide requirement unavailable. |
| `optional_capabilities` | Expose availability to handlers; absence never blocks base activation. A contribution that truly needs one declares it as a hard per-contribution `requires`. |
| `platform_families` / runtime features | Core checks tested OS family and normalized features. A module-wide mismatch makes the module unavailable; a per-contribution mismatch withholds only that contribution. Unknown families do not inherit Debian/Arch support. |
| `required_bins` | Hard requirement only when no normalized platform feature expresses it. Missing binary makes the module unavailable; optional tools belong on specific contributions. |

At discovery, the loader reads declarations as data, builds hard module and
unique capability-provider edges, and extends its existing topological sort.
Hard cycles and ambiguous capability providers fail with provenance rather
than selecting by filesystem order. This is not a package solver. The current
v1 `depends_on` remains an ordering preference: its use in
`nextcloud_docker` does **not** become a hard dependency on `system`. V2 has
no ordering-only declaration until a real case needs one.

Use module identity for implementation-specific integration and capability
identity for substitutable operations. A module may stay active for knowledge
while a feature-specific handler is unavailable; check requirements again at
dispatch so same-process disablement cannot bypass ownership. Broad v1
`provides=nextcloud,docker` tags remain legacy feature tokens, not executable
v2 capability IDs.

V1 `ai_capabilities` actions can be projected as transient
`legacy.<owner>.<action>` records for compatibility. They do not satisfy a
substitutable v2 capability requirement unless an explicit adapter contract
maps that action to the canonical ID and preserves its safety tier. No such
mapping is needed for the first `system` migration.

## Runtime states and compatibility

The current loader keeps its existing concepts and state queries:

- **discovered/installed**: a package candidate with `module.conf` can be
  inspected without execution; validity is reported separately;
- **enabled/disabled**: administrator policy; a new v2 package needs an
  explicit `enabled` entry, while omitted v1 entries remain enabled for
  compatibility;
- **active**: required checks and registration succeeded in this process;
- **unavailable + reason**: enabled but unsupported API, invalid data,
  unmet dependency/platform/runtime requirement or registration failure.

These are not new persistent states. Reasons should identify the failed
requirement and dependency chain, not just say “unmet dependency.” V2 stages
owned registrations and commits them only after validation succeeds; failed
packages contribute nothing. Dispatch rechecks active ownership. Policy
changes require a process restart for replacement of loaded code. No hot
unload is needed now. A disabled package stays `disabled` and is never sourced;
an explicit inspect/validate command may report manifest problems without
changing that activation state.

Absent `module_api` means v1 only for compatibility; explicit `1` is also v1.
The version probe must reject a malformed or unsupported marker rather than
fall back to v1. `module_api=2` selects strict validation. A v2 module may opt into
`[compat] v1_hooks=true` while older consumers still need hooks. The v1
registration adapter gives those hooks owner-stamped records in the same
contribution index; existing hook arrays remain temporary views for current
callers. Mixing is allowed only across distinct consumer surfaces. A v2
contribution replacing a v1 one must suppress the v1 path for that consumer
before both can be advertised or executed. Validation rejects duplicate IDs;
tests must also guard semantic duplicates such as the same host check exposed
through two adapters.

`system` is the first small reference: add static host knowledge and one
structured host observer under v2 while keeping its current v1 health,
diagnose, AI context, notification and recovery behavior until those consumers
migrate. Before changing its API version, preserve an implicitly enabled
installation with an explicit `system=enabled` policy entry; never override an
existing disabled entry. Keep its current `systemctl` requirement initially
so this migration does not silently change activation. Step 7 can move that
requirement to service-specific contributions after platform helpers support
it. `nextcloud_docker` stays an unchanged v1 module with its soft
`depends_on=system`, menus, action catalog and combined deployment.

V1 removal in Step 23 requires: migrated bundled modules; no live consumers
of v1-only hooks/menus/check-file conventions; equivalent behavior and
activation tests; documented external module usage/migration; and a release
deprecation period. Compatibility is temporary, not a second permanent API.

## Core versus `system`

Core/platform owns mechanisms every domain can use: OS/family detection,
package and service adapters, filesystem/process/user/network primitives,
execution, privilege, config transport, loader, registry and policy. The
`system` module owns host-domain meaning: CPU/RAM/storage/temperature
observations, health thresholds, host troubleshooting knowledge and
higher-level service administration capabilities. A useful test is: **would
disabling `system` legitimately remove this behavior while leaving Igor and
other modules functional?** If yes, it belongs to `system`; if it is needed
to activate modules or implement a portable OS operation, it belongs to core.
The system module should request normalized service/package operations rather
than choose apt or pacman. This boundary does not move existing code during
the design pass.

## Initial trust and validation

Modules remain trusted, reviewed local executable code. V2 requires explicit
enablement before executing a newly installed package. This is activation
policy, not a sandbox or code-signing claim. Migrating a bundled v1 module
preserves its existing enabled/disabled choice. Static module knowledge,
observations and handler output enter AI as reference data; they cannot
authorize an action. Capability tier/privilege declarations are trusted local
metadata, but Igor decides approval, active ownership, OS authentication and
execution. Future third-party provenance/permissions can attach to the same
owner record without changing the envelope.

The Wave C validator uses Igor's existing `IGOR_PYTHON` resolution and Python
standard library for strict manifest and JSON parsing, field/type/ID checks,
duplicate detection, contained paths, supported versions, dependency graphs
and handler references. Bash handlers receive `bash -n` and isolated
invocation tests. Validate both at package
inspection and before activation; do not source disabled or malformed v2
packages. `--modules` should expose state plus a precise reason. Keep existing
v1 tests, then add fixtures for v2 disabled/unavailable/active state, dependency
provenance, duplicate/unknown declarations, path escape, mixed compatibility,
handler protocol failures and both Debian/Arch platform gates. Assert that
inactive owners contribute nothing through knowledge, checks, capabilities,
configuration, menus, backup/restore or notifications.

## Wave C implementation sequence and current boundary

1. `core/lib/module_loader.sh` now performs v1/v2 dispatch, formal state and
   reason queries, staged v2 activation and owner filtering while preserving
   the v1 branch.
2. `core/lib/module_contract.py` validates the strict manifest and JSON
   contracts; `core/lib/module_handler.sh` supplies the Bash JSON adapter.
3. V2 declarations and required v1 compatibility registrations use the same
   owner-aware contribution index while existing dispatcher views remain for
   current consumers.
4. `system` now proves a mixed v1/v2 slice with static host knowledge and a
   host memory observer. `nextcloud_docker` remains the v1 compatibility
   module.
5. Focused and full regression evidence passed. This document records the
   implemented contract; `STATUS.md` records the completion evidence.

Likely touch points are `core/lib/module_loader.sh`, a validator/adapter under
`core/lib/`, `core/ai/context.sh` for active v2 static knowledge,
`core/lib/config_loader.sh` only where v2 configuration ownership requires it,
`igor.sh` module inspection/policy migration, `modules/system/`,
`config/modules.conf.example`, current module docs and module tests. Preserve
`core/ai/safety.sh`, `core/ai/events.sh`, the TUI, current platform helpers,
`nextcloud_docker`, and later System Model, observer scheduling, domain events,
automation and composition work unless a focused test reveals a necessary
boundary correction.

Compatibility risks to test before migrating `system` are the v1 implicit
enable default, current section-blind parsing, v1-only contract tests, lazy
menu/action ownership, helper availability in child processes, and duplicate
delivery when an old consumer and a v2 consumer request the same fact. The
reference observer may be invoked by tests and inspection without creating a
System Model or a background scheduler.
