# Step 17 — Configuration Ownership and Schema Foundation

Status: **accepted bounded architecture (D059)**. The implementation boundary is
the foundation and one Core preference, `ai.verbose`. Current implementation,
validation results and limitations are recorded in [STATUS.md](STATUS.md).
Deployment/relationship work under the roadmap's original Step 17 remains
future work.

## Authority and state

Core's Configuration Service owns schema admission, validated desired values,
resolution, revisions, provenance and migration/recovery. It is an internal
service boundary, not a daemon requirement or a universal state database.
Consumers use versioned records and service operations, never SQL or filenames.

| Category | Meaning | Owner |
|---|---|---|
| Declared/default | Package baseline tied to a schema version | Core or module declaration |
| Desired | Durable validated operator intent, including explicit unset | Configuration Service |
| Effective input | Resolved value for a target/consumer, with selected source | Configuration resolution; consumer owns its consumed snapshot |
| Observed runtime | What the target actually reports, with freshness | System Model observer |
| Secret reference | Handle and safe configured/available status | Configuration stores reference; Secret Service owns material |
| Temporary override | Explicit validated input with session/process lifetime | Session runtime under configuration precedence |

A desired commit is not evidence that an application accepted a value.
Resolution is not consumption; consumption is not an observation. A running
process can still use an older revision. Unknown, unavailable, unset and
defaulted remain distinct. Drift never rewrites desired intent.

Capabilities own application and verification. Operational History owns
attempts, approvals, execution, verification and outcomes. Configuration retains
revision/source metadata and operation references, not a second outcome journal.
Investigations and judgments are reference consumers, with no write authority.
15UI renders safe backend projections and submits typed intent.

## Scope and identity

A durable setting reference consists of an Igor installation `scope_id`, a
target object reference and a stable `setting_id`. Reuse D049 scope identity
and existing object IDs. Restoration of the same installation preserves scope;
a distinct installation cannot silently reuse it. Read-only inspection never
allocates a scope.

Version 1 supports installation and module targets. Lookup uses the exact
target; there is no implicit inheritance. Modules own setting definitions,
not mutable instance values. Unknown target identities fail closed.
Deployment, instance, capability/provider and durable user scopes require their
own established target registries before implementation.

Handlers, paths, labels and discovery/load order are not setting identity.

## Schema version 1

Configuration declarations extend the existing owner-stamped Module API v2
contribution rather than creating another hook registry. The descriptor is
strict versioned JSON data. Configuration schema, package, Module API and
private store versions have separate meanings.

A schema declares stable fields, scope, required/optional status, type,
optional default, bounded constraints, help, sensitivity, behavior,
mutability/application semantics and explicit override permissions.
Core stamps ownership; a declaration cannot impersonate another owner.

Initial value types are text, boolean, integer, finite number, enum, size,
path reference and secret reference. Sizes normalize to bytes with explicit
units. Ambiguous legacy units require an explicit conversion.
Paths are typed root-relative references or deliberately external absolute
paths. Secret fields accept handles only and have no literal secret defaults.

The implemented descriptor uses `schema_version: 1` and a bounded `fields`
array. Field names are `id`, `type`, `scope`, `required`, `default`, `enum`,
`minimum`, `maximum`, `min_length`, `max_length`, `label`, `help`, `sensitivity`,
`behavior`, `apply`, `overrides`, `secret_purpose`, `path_roots` and `path_kind`.
Type spellings are `string`, `boolean`, `integer`, `number`, `enum`, `size`,
`path` and `secret_ref`. `behavior` is `stored` or `managed`; a managed `apply`
describes capability/verification IDs and `restart` (`none`, `reload`, `restart`).
Secret-reference values have a `reference`; path values have `root` and
`relative`. The bounded API accepts sizes as integer bytes and root-relative
paths only. Human-unit parsing, external absolute paths, general mutability
controls and richer validation/migration contribution metadata remain deferred.

Primitive constraints remain small: lengths, numeric ranges, enum membership
and bounded path rules. Domain/cross-field validators are registered, bounded,
non-mutating functions. They do not embed commands or authorize execution.
Unsupported descriptor versions/fields, duplicate identities, invalid
defaults and malformed values fail before writes.

A declarative configuration contribution does not need a Bash handler just to
describe fields. Legacy handler-only configuration declarations remain
unavailable until explicitly adapted. No real module configuration migrates
in this step; fixture declarations prove the new seam.

Step 18 Boundary 2 composes that seam with an isolated copy of the real System
package. A test-only module-scoped field is admitted through registration and
projected by Core's Configuration Service into structured module inspection.
It is not a shipped setting or an application-consumption claim. The current
configuration CLI still exposes the bounded Core `ai.verbose` slice; general
module writes, binding/resource ownership and application recovery require the
later workflow proof. See [STATUS.md](STATUS.md) for composition evidence.

## Module/Core responsibilities

Modules describe domain meaning, defaults, validation, secret purposes,
application/restart requirements, capabilities and verification. They may
supply reviewed migration mappings/conversions; Core orchestrates migration.

Core owns persistence, precedence, atomic commits, authorization, secret
mediation, provenance, export/recovery and validation sequencing.
Module code cannot choose security-critical file semantics or bypass approval.

Only active eligible owners contribute live schemas/validation/application.
Stored values survive disablement for recovery, but availability is explicit
and disabled modules do not execute to validate or edit them.

## Persistence and recovery

The selected hybrid is private SQLite for desired values/revision metadata,
versioned JSON export/recovery, separate secret material and generated
application/compatibility outputs. This choice supports atomic multi-field
updates and concurrent revision checks without making SQL the module API.
Structured files alone would need additional locking/transaction machinery;
readable exports retain headless recovery.

The initial private store is under the installation's data root. Bootstrap
root bindings locate it before service startup; the store's location must not
depend on a value inside itself. Root relocation is an explicit migration.

Private directories and files have restrictive permissions and checked
ownership. Unsafe links, corrupt stores and unsupported versions fail closed;
existing content is retained. Inspection of an absent store reports absence
and creates nothing.

Validate the full candidate before persistence. Compare the expected revision
and frozen configuration-state token inside the transaction; stale proposals cannot overwrite intervening changes.
Commit values, revision, source and operation reference atomically.
Application side effects are outside this transaction.

Exports are versioned non-secret documents. Restore validates the whole
document before changing authority, requires matching installation identity
and uses the same explicit change boundary. Recovery restores configuration,
not applications, History, Investigations or observations. Revision identity
and interruption handling prevent silent replay.

The implementation keeps a private `recovery.json` before a desired commit.
The first cutover includes a typed `legacy_baseline` for `ai.verbose` so an
existing false value can be recovered after an initial true proposal. It does
not copy other legacy settings or secret material. Restore creates a new
authoritative revision. An empty backend can reuse an integer revision;
proposals also bind to a digest of the current record identities, revisions,
operation references and values. That token is checked atomically, so a stale
proposal cannot cross recovery merely because revision numbers match. The
absent-store token does not depend on History initialization.
For a damaged backend, preserve the damaged files first, then restore a
validated export into an empty configuration backend using the retained
installation scope. A different scope is rejected. There is no automatic
overwrite, startup repair or replay of a failed operation.

## Storage/source locator contract

A setting's durable identity remains its scoped `setting_id`; paths and
filenames are not identity. D054's private/replaceable backend rule still
applies. At the same time, a configuration value must not become an anonymous
scalar with no answer to "where did this come from?" or "where will this be
applied?"

Every inspected value/source therefore carries a typed `storage_locator` (or
equivalent owning-service projection). Locators belong to the particular
default, desired, override, observed/configured value or application target
being described; one ambiguous global filename is insufficient.

For a file-backed value, the locator **must** identify:

- a semantic/rooted path to the concrete file; and
- a stable selector within that file, such as section/key, JSON pointer,
  Compose service/environment key or application setting key.

Line numbers are diagnostic only because ordinary edits move them. A module may
declare how to parse or apply a domain setting, but the machine-specific locator
is Igor-owned binding/provenance and does not live in the portable module
package.

Non-file-backed settings must identify their real authority rather than invent a
fake path: declared environment/process source, secret reference, database
object/key, runtime/command-line source or Configuration Service. When an
environment value comes from a known env/unit/Compose file, include that file
and key. Secret material is never copied into the locator.

For Igor-owned desired values, inspection may expose the current private backend
path as diagnostic storage metadata, but callers cannot use that filename as the
setting reference or bypass Configuration Service. A future move from SQLite to
another backend therefore does not change `setting_id`.

External/application-native configuration remains external authority until an
explicit adoption transition. Read-only discovery may record a value plus its
storage locator as observed/configured state. Adoption preserves the original
locator as `imported_from` provenance, commits desired state through the normal
configuration boundary, and binds any write/readback target explicitly before a
capability can apply it. Finding a file never grants write ownership.

See [Brownfield Discovery, Adoption, and Configuration Location](BROWNFIELD_ADOPTION.md)
for the machine-state and adoption model.

This locator refinement is a forward requirement for application/module
composition. The already implemented bounded `ai.verbose` slice is not claimed
to prove native-file/application locator support; Step 18 must implement and
verify the required locator/binding seam before its first application proof.

## Secrets and sensitivity

Credentials, tokens, private keys and authentication material are secrets.
Hostnames, usernames and paths can be sensitive without being secret.
Sensitivity controls projection/export; it does not change ownership.

Configuration stores opaque secret references only. Reuse the existing
[secret reference service](../../core/lib/secret_refs.py): owner, purpose,
consumer, authorization, safe private file access and value-free access audit.
This step does not migrate or create real credentials.

Secret material is excluded from ordinary config inspection, UI, AI context,
History, events, validation errors and exports. Do not include plaintext
previews, literal defaults or secret-value hashes in provenance.
Normal inspection returns configured/available status and safe references.
Only reviewed consumers resolve material; subprocess exposure is explicit.

Ordinary exports do not back up material. Secret recovery is a separate
sensitive operation. An unresolved restored handle remains unavailable and
blocks a required consumer. External secret managers are deferred.

## Paths and environment

Code/package roots, durable data/config, secrets, disposable runtime,
module data and application/deployment paths are separate ownership classes.
Portable path values bind a semantic root plus relative path. Deliberately
external absolute paths are marked nonportable. Never evaluate shell
interpolation or resolve against incidental current working directory.

For migrated settings with supported overrides, precedence is:

```text
explicit session/CLI override
  > explicitly supported environment override
  > durable desired value
  > declared default
```

Only declared/Core-approved override bindings participate. Invalid explicit
overrides fail validation rather than falling back. Inspection identifies
the override and lifetime separately from the durable value.
Policy, activation and privilege do not become configurable through arbitrary
environment variables. Secret injection goes through a reviewed secret binding.

Classify each existing environment name as bootstrap input, compatibility
import alias, secret injection, session override or internal/derived export.
No broad environment-variable migration occurs here. `ai.verbose` has no
arbitrary environment override after cutover. Unmigrated settings retain their
existing loading behavior.

## Validation and change lifecycle

Validation layers are descriptor/type/normalization, eligible owner,
scope/reference, secret status, path containment, domain/cross-field candidate
validation and application capability/precondition checks. No layer claims
that an external application successfully applied a value. Active filesystem
or network discovery belongs to explicit READ capabilities.

```text
typed proposal
  -> resolve schema, target and current revision
  -> validate candidate and freeze diff/effects
  -> canonical policy, approval and privilege
  -> atomic desired-state commit
  -> explicit capability/plan application where required
  -> independent verification
  -> Operational History outcome
```

Durable writes are CHANGE operations at minimum. Destructive effects use the
existing DESTROY classification and exact `YES` behavior. Guide/Assist/Executive
remain separate from OS privilege. Provider eligibility, frozen inputs and
preconditions are rechecked; native sudo remains on the existing backend PTY.

History identifies the attempt before effect. Configuration links the committed
revision to that operation. Missing/pruned History remains unavailable; it
cannot erase a committed desired value or turn an unknown effect into success.
Interrupted work is inspected/reconciled explicitly, never automatically retried.

## Bounded Core slice: ai.verbose

The first real setting is the existing verbosity preference. Its commands
and existing 15UI interaction remain; the UI gains no storage authority.
Only this key transfers from legacy inputs to Configuration Service. Trusted
package defaults remain readable when the Core code directory is linked;
mutable legacy configuration and private authoritative storage reject links.
Other AI settings remain with their existing writer.

Startup and read-only inspection resolve configuration without migrating.
An explicit canonical change validates/imports the old value as needed,
preserves a recovery point and establishes the new authoritative revision.
Legacy inputs cannot override the value after cutover; the old writer stops
writing this key.

The desired-state capability verifies persistence only. Current-session
consumption happens after a successful canonical result and revision check.
Separate verification identifies the consumer/session evidence it checks.
A headless desired write does not claim that an already-running chat session
changed. Configuration inspection never substitutes a resolved value for an
observed System Model fact.

## Inspection

The owning surface exposes service status, declarations, scoped value
inspection, proposal validation and versioned export. It reports default,
desired and effective input independently, selected source, schema owner/version,
revision, operation reference, secret status and availability. Each projected
value/source also reports its typed storage locator; file-backed values expose the
concrete file plus stable selector, and managed application settings expose the
bound write/readback target separately where applicable. Application/
verification evidence remains explicitly separate, with unavailable observation
when there is no System Model source.

Inspection does not create storage, refresh observers, execute validators with
side effects, authenticate or apply settings. 15UI receives safe projections;
it does not infer schemas from arbitrary files.

The bounded headless interface is:

```bash
bash igor.sh --configuration status
bash igor.sh --configuration list
bash igor.sh --configuration inspect ai.verbose
bash igor.sh --configuration export
bash igor.sh --configuration validate '[{"id":"ai.verbose","target":"installation:local","value":false}]'
```

These commands do not source legacy configuration or module code. The shell
bootstrap data-root binding selects the private store. The headless list
currently exposes the Core slice; module declarations are inspected through
`igor_configuration_declarations` and admitted through the service's explicit
schema boundary in fixtures. It is not a module configuration migration.

Canonical operations are `core.configuration.ai_verbose.set` (CHANGE),
`core.configuration.ai_verbose.verify` (READ, current-session evidence only)
and `core.configuration.restore` (CHANGE, desired-state recovery only).
Set inputs are a boolean `value`, expected `revision` and frozen `state` token
from inspection; verification takes the consumed `revision`; restore takes a
serialized versioned `document`, expected `revision` and frozen `state` token.
They use the existing capability adapter/policy/History path, not a new unmediated CLI writer. Durable desired verification and
session verification produce separate episodes. Existing AI commands provide
the real editable slice; no generic configuration editor is introduced.

## Migration evidence and legacy paths

Current migration inputs include executable `config/variables/*.env`,
`secrets/*.env` and deprecated root env files, the overlapping
[legacy loader](../../core/lib/config.sh), specialized AI settings writer,
module setup/adoption scripts and generated application configuration.
[LEGACY.md](LEGACY.md) records retention and removal conditions.

Each future migration must name source/precedence, target/version, parser,
conversion, validation, backup, idempotency, cutover, verification and recovery.
Imports use bounded literal parsers, not arbitrary shell sourcing. Ambiguous
or executable assignments require explicit resolution.
Generated exports do not remain competing writable authorities.

Nextcloud, module settings, secrets, activation policy and host thresholds
remain unchanged. Q012's documented/executed RAM-threshold mismatch stays open.

## Completion and deferred work

[EXECUTION.md](EXECUTION.md) requires contract, regression, a real vertical
slice, inspection and migration/recovery proof. [STATUS.md](STATUS.md) records
actual validation, failures, skips and unavailable checks. The foundation does
not close the entire Ownership Foundation.

Deferred: deployments/relationships, inheritance, cascades, generic settings
or setup UI, richer 15UI size/path controls, module migrations, external secret
managers, live privileged secret-consuming adapters, resumable workflows,
agents, new AI features, self-healing and Steps 18/19/20. The original broader
configuration-surface ideas remain future design work, not schema-v1 authority.
