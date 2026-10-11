# Igor 2 Collection Results and Operator Interface RFC

Status: **proposed extension in DISCOVERY; no runtime implementation authorized**.

Prepared 2026-10-10 against local `igor2` commit `5b80740`, under
[Development Policy / D078](DEVELOPMENT_POLICY.md). This document extends
Step 18 output contracts and Step 20 operator rendering without reopening
completed waves. It does not replace the capability runtime, registry,
operator explorer, D049 identity or approval/execution machinery.

## Fidelity evidence (2026-10-11)

The Owner supplied the completed comparison of the original 170-line
`igor2_collection_operator_rfc_v2.md` with the integrated proposal: **no material
architectural or acceptance requirements are missing**. D078/D079 supersede the
original compatibility, obsolete-output coexistence and master-reconciliation
obligations. This is Owner-provided review evidence; the superseded 309-line
`igor2_capability_tui_rfc.md` is not the source for that conclusion.

Expected original SHA-256 supplied by the Owner:
`e5ea31b14c8e0f3f9776485002742242442f7378b120d69a8052ee8c11a2dd35`.
The integrated candidate before these evidence-only corrections has computed
SHA-256 `4ac8c9a916fe748aaab2b2a8e1313beeaf06ae83d7f62d53df8fdbdc668e1286`.
The v2 file and comparison artifact are still inaccessible to this checkout;
therefore the original hash and its binding to this reviewed candidate have
**not been independently verified**. The old missing-comparison blocker is
superseded by the Owner's review, but the requested integrity verification
remains necessary before declaring formal DISCOVERY closure. No architectural
or acceptance contract is changed by this evidence update.

## Inspected baseline

These are source-inspection findings, not behavior retested in this pass:

| Existing foundation | Local evidence and limits |
|---|---|
| `system.service.list` capability v2 | [host.json](../../modules/system/contracts/host.json), `system__service_list` in [module.sh](../../modules/system/module.sh): closed `count`, scalar `services` string (4096 characters), `source`; handler previews at most 80 lines/4096 bytes. This is not a structured collection or pagination contract. |
| Service status/restart | Same declarations: `system.service.status` v2 is READ with D070 `service` selector; `system.service.restart` v1 is CHANGE, requires privilege, checks existence and verifies active state through the reviewed Core adapter. Restart is outside the initial proof. |
| Canonical validation/dispatch | [module_contract.py](../../core/lib/module_contract.py) delegates output schema validation to [capability_runtime.py](../../core/lib/capability_runtime.py); [capability.sh](../../core/lib/capability.sh) owns execution, output validity, verification and History. Validators currently admit capability versions 1/2 and scalar output-schema version 1. |
| Operator explorer and aliases | [operator_surface.py](../../core/lib/operator_surface.py), [tui.py](../../core/ai/tui.py), [OPERATOR_SURFACE.md](OPERATOR_SURFACE.md): `:system`, collision-safe `:sys`, qualified provider ambiguity and `invoke` through backend `run_capability`. Direct pasted capability invocation is the proposed extension, not a completed baseline claim. |
| Structured CLI | [operator_cli.sh](../../core/lib/operator_cli.sh) maps `capability run` to `--capability-run`; [igor.sh](../../igor.sh) enters canonical backend execution. No CLI executor is needed. |
| Results and scoped identity | [D049–D051](DECISIONS.md), [Operational History](../operational_history.md): opaque Igor-owned scope plus existing object IDs, canonical capability/version/provider and operation identity. |

Existing scalar tests remain valid until the complete runtime migration. The
inventory of affected contracts/tests is in [Development Policy](DEVELOPMENT_POLICY.md#policy-audit-and-deferred-migrations-2026-10-10).

## Purpose and boundaries

Expose typed, bounded resource collections through existing capabilities so
CLI, TUI, future GUI/API, AI, configuration, memory and plans can consume the
same domain semantics. The TUI renders validated backend data and submits
typed intent. A displayed row is reference data, not a new System Model fact,
deployment binding, desired value, approval or execution record.

Initial proof: **list → select → status/details → back → refresh**, READ only.
Use System services and an unrelated synthetic provider (for example a fixture
document catalogue) to prove the same renderer without systemd-specific code.
The second provider must have different columns, selectors and detail data,
not service data renamed. No service restart, configuration mutation, generic
workflow engine, inventory database, background scan or module migration is
included. A later approved-action proof must separately reuse canonical policy,
approval, privilege, execution, verification and History.

## Step 18: evolve the canonical output contract

Replace the scalar `services` preview with a typed collection under the same
`system.service.list` ID. Do not add a second ID or keep the old output operating
indefinitely. Use independent version axes from [MODULE_API.md](MODULE_API.md):
D079 sets capability contract version 3 and structured output schema 2, leaving
Module API version unchanged because the contribution envelope stays unchanged.
Today's validators still allow only capability versions 1/2 and schema 1. Migrate pins and all consumers together; old mismatched pins
fail before effects, and retained History keeps its original version/meaning.
Other capabilities still using live versions 1/2 need no forced migration.

Extend `validate_output_schema` / `validate_outputs` and the existing Module API
admission path. Introduce only bounded arrays, closed records and the existing
scoped-reference shape needed by this slice; no arbitrary recursive JSON,
expressions, provider code in schemas or alternate output validator. Limit depth,
property count, item count, text lengths and serialized bytes. Reject duplicate
keys, non-finite numbers, unknown fields/versions, invalid references and malformed
action bindings deterministically. Schema validation occurs before activation;
result validation occurs before frontend/event/History projection.

Collection domain semantics under the accepted Q022–Q024 direction:

- declared collection/resource kind, closed typed row schema and presentation
  columns referring only to declared fields;
- rows with D049 scoped references where a canonical object exists, bounded
  display properties and explicit selector values under existing D070 contracts;
- backend-stamped source/provider provenance, observation time, expiry and
  snapshot revision; rows cannot spoof execution authority;
- page metadata: snapshot revision, bounded continuation token, returned count,
  completeness and next-page availability; never imply a preview is exhaustive;
- declarative inspection targets referencing existing capability IDs and input
  bindings, validated against their registered schemas; no row shell/function
  names, executable callbacks, invented providers or TUI action handlers.

Collection rows and schema meaning are owned by the contributing domain module;
Core owns admission, eligibility, scope, validation, result provenance and
invocation. The frontend owns disposable navigation/filter/selection state.
Modules remain discoverable and independently detachable; inactive owners supply
no executable targets. Do not introduce a collection registry beside capabilities.

### Authoritative result envelope

Collections occupy the existing `result` domain-data slot. Preserve
`operation_id`, `capability_id`, `capability_version`, `provider`, `owner`,
`execution_status`, `output_status`, `verification_status`, `outcome`, approval,
privilege, affected objects, recovery and verification evidence. A snapshot/page
revision is freshness metadata, not another operation/resource identity scheme.

Provider completion, valid domain output and verification remain separate.
Malformed/oversize data cannot claim success or erase a possible effect; preserve
the canonical failed/invalid/unknown outcome and do not expose rejected payloads
in normal History/events/errors. Rendering and HTTP/AI projection do not change
the retained authoritative result. READ with no verifier remains
`not_applicable`, not a fabricated verification pass.

Reuse D049's opaque scope references and existing selectors. Backend binding
must map a selected service object to the validated `unit` input without parsing
display labels in the frontend. Synthetic provider references use the same
reference contract within the isolated fixture, not a new production identity
system. Selection in the wrong scope or from a retired provider is refused.

## Step 20: one invocation path and generic rendering

Typing or pasting `:system.service.list`, or selecting that capability in the
explorer, must construct the identical canonical backend request. Preserve
`:system`, `:sys` and explicit provider ambiguity handling. Namespace navigation
and leaf invocation must be distinguishable; missing/ambiguous targets cannot
fall through to raw shell or model-selected execution. Required inputs use the
existing validated selector/manual-input flow, never guessed values.

Recommended path:

```text
typed/pasted leaf or explorer selection
  → shared backend capability resolution / run_capability
  → policy, approval, privilege, invocation, output validation, verification
  → canonical result / History / backend frontend projection
  → generic collection renderer
```

The renderer supports keyboard navigation, selection, typed detail inspection,
local filtering, explicit refresh and back navigation. Meaning cannot depend on
color; small terminals need bounded scrolling/columns and visible empty, stale,
unavailable, invalid and failed-refresh states. It consumes column/schema metadata,
not systemd field-name branches. Details use declared canonical READ targets or
validated inline data; they do not acquire another executor.

Back returns to the prior collection/filter/selection only while that snapshot
remains valid. Refresh requests the canonical list operation explicitly and
creates a new result/operation; it never silently executes a mutation. Distinguish
namespace-registry refresh from domain collection refresh. CLI JSON retains the
same typed data; no prose parsing is required for other frontends.

## Bounds, freshness, pagination and privacy (Q023 provisional limits)

| Bound | Recommended first-slice hard ceiling |
|---|---|
| Rows per page | 128; callers may request fewer. |
| Validated serialized domain page | 64 KiB UTF-8 JSON. |
| Serialized frontend result event including envelope | 96 KiB; reject before publication if exceeded. |
| One collection snapshot | 1024 rows and 512 KiB of serialized domain data, whichever is reached first. |
| Schema nesting / row properties / cell text | Depth 4 (collection → array → row → scoped-reference record), 32 properties, 4096 characters maximum; tighter field limits permitted. |
| Snapshot/cursor freshness | 30 seconds maximum for the initial service/synthetic proof; explicit refresh on expiry. |
| Collection transport/read timeout | At most the existing 30-second handler bound; reads must stop at their byte limit before unbounded buffering. |

These are proposed ceilings, not measured Raspberry Pi performance claims.
Check producer reads, validator allocations, IPC, retained History and frontend
caches as well as rendering. Existing shell argv/environment result transport
needs review against these byte ceilings; migrate affected transport if necessary
rather than adding a second execution route. No automatic polling, unbounded
cache, eager offscreen detail queries or arbitrary terminal control sequences.

Recommendation: page one freezes a bounded ephemeral snapshot in the existing
backend session/runtime ownership, with stable order by scoped object reference.
Continuation is opaque, bound to scope/provider/capability version, snapshot,
query/filter and position; reject tampering, expiry or mismatches without mixing
pages from separate inventories. Beyond the total bound return a deterministic
limit error, not silently truncated success. An oversized single row/page also
fails validation with a bounded value-free error; no arbitrary byte slicing of
JSON. A new snapshot requires explicit refresh. Tokens are temporary navigation
references, not a durable identity or secret and never authorization.

Local filtering covers loaded rows only and must say so. A server-side filter,
if needed for this proof, is a bounded typed capability input and part of snapshot
identity, never a shell expression. Repeated pages cannot duplicate/omit rows
inside one snapshot; live changes appear only on a new snapshot.

Before detail invocation, the backend rechecks active provider, scope, expiry,
row membership, object existence and selector/input contract. A missing, changed
or expired selection yields an explicit stale/unavailable result and refresh
option; never substitute a similarly named row. Freeze/recheck the same binding
at execution under existing preconditions. A future CHANGE proof also requires
the established approval/version/provider/execution fences.

Retain private runtime directories/events (0700 directories, 0600 files where
applicable), outbound scrubbing and value-free errors. Valid typed data can still
be private: preserve existing public/private projection and reference-data trust
boundaries. No credential fields or raw logs by default; labels/details cannot
smuggle authority or terminal controls. Do not automatically send whole pages to
AI; use existing bounded eligible context selection and transport redaction.

## Accepted direction and declaration grammar

The Owner accepted Q022–Q024 on 2026-10-11, recorded in
[D079](DECISIONS.md#d079--collection-contract-and-read-inspection-direction).
The version cutover and READ binding are settled; resource limits are provisional
engineering ceilings to validate in the bounded proof, not performance evidence.

### Q022–Q024 contract

**Q022 — one closed typed collection contract.** Keep `system.service.list`,
advance it to capability version 3 and use structured output schema version 2
through the shared validator; keep Module API/contribution-envelope versions
unchanged if their top-level shape stays unchanged. Define collection kind,
closed row schema and optional presentation/inspection metadata in the existing
descriptor, not a separate resource contribution/registry. Use the closed declaration grammar below. Migrate all affected internal callers,
pins and fixtures together; old pins fail before effects.

Required domain fields: `resource_kind`, `inventory`, `rows`, `page`, `freshness`.
Rows have unique `reference: {scope_id, object_id}` under D049 plus only declared
typed properties. For System, start with `unit`, `active_state`, `sub_state`,
matching the Platform read; `unit` retains its `systemd_unit` validator and
256-character limit. Do not fabricate load state, descriptions or installed-unit
status. `page` is closed: `snapshot_revision`, `returned_count`, `total_count`,
`has_more`, with `next_cursor` present iff `has_more`. Counts describe the complete
bounded frozen snapshot. `freshness` contains UTC `observed_at` and `expires_at`,
with Core validation/stamping. Reject duplicate references, invalid scope,
wrong primitive types, unknown fields and inconsistent counts/cursor/timestamps.

Optional column/label hints refer only to declared row fields. Without hints,
use a deterministic schema-order table/property view or escaped **validated**
JSON through existing presentation primitives. Invalid results never bypass
validation into a raw view. No arbitrary recursive schema or action language.

**Q023 — finite ephemeral session snapshots.** Retain the bounds above; default
to 50 rows, accept `limit` 1–128 and an optional `cursor` of at most 256 printable
ASCII bytes. These are the only new initial list inputs. Keep a fixed inventory
and local filtering; no server-side filter/user-manager inventory is needed.
Allow at most two snapshots/1 MiB serialized data per backend session. Release
on expiry, replacement, owner disable or session end; restart invalidates them.
Refresh creates a new snapshot rather than extending the old TTL.

Core owns opaque cursor lookup under existing private session/runtime ownership.
Bind it to scope, owner/provider, descriptor version/digest, snapshot, fixed query,
page size and position; reject cross-session lookup or tampering. A repeated
valid cursor returns the same page while fresh. Use backend elapsed time for
the 30-second TTL, with UTC observation/expiry for display. Publish no successful
partial inventory when the complete source exceeds 1024 rows/512 KiB. Oversize
rows/pages fail without truncation. Keep bounded page data/provenance under existing
History rules; do not persist full snapshots or reconstruct live cursors from
History. No new persistent store/retention policy is introduced.

The TUI keeps one collection view and at most two 64 KiB pages; back/details must
not accumulate copies. Serialized caps do not bound Python allocation overhead:
measure peak resident memory and first-page/refresh/navigation latency on
declared constrained hardware. Record measurements/environment separately from
synthetic boundary tests, with no claim of measured Raspberry Pi performance yet.
The global budget and measurable acceptance requirements below apply as well.

**Q024 — one descriptor-owned READ inspect binding.** Use one optional `inspect`
target with canonical `capability_id` and closed `inputs_from_row` mapping from
target input names to declared scalar row property names. Example: existing
`system.service.status`, `unit` from row `unit`. Allow direct properties only,
not paths/expressions/templates, commands, row-owned providers or general action
lists. Admission validates mapping syntax and declared row properties; registry
evaluation checks the resolved target's input types/selectors and all required
inputs. Missing/ambiguous detail targets make the binding unavailable, not the
read-only collection itself. Pure package validation performs no runtime probe.

Selection submits the scoped reference and registered binding; backend derives
inputs from its validated snapshot, rechecks scope/membership/freshness and
resolves the active READ target through ordinary policy/Guide handling. Preserve
provider ambiguity/explicit selection; do not assume the list provider is the
detail provider. Freeze/recheck the target descriptor/version at execution.
Missing/disabled/ambiguous/incompatible targets or a target that becomes CHANGE
are visibly unavailable, never silently substituted or executed as READ.
Without a binding, show declared inline record details without implying a fresh
probe. Reuse the existing generic property view. Restart/configuration bindings
remain outside this initial metadata and require the later approved-action proof.

### Minimal declaration grammar (Step 18/20)

Extend the existing capability contribution/descriptor with one optional closed
`collection` object, admitted only with capability version 3/output schema 2.
Keep the Module API and contribution envelope unchanged. Both package admission
and runtime descriptor construction use the same validator; operator projection
carries its validated metadata without a new registry or declaration file.
The following is a descriptor **fragment**, not a currently valid runtime contract:

```json
{
  "id": "system.service.list",
  "capability_version": 3,
  "collection": {
    "resource_kind": "service",
    "inventory": "loaded_system_services",
    "columns": [
      {"field": "unit", "label": "Unit"},
      {"field": "active_state", "label": "Active"},
      {"field": "sub_state", "label": "Substate"}
    ],
    "inspect": {
      "capability_id": "system.service.status",
      "inputs_from_row": {"unit": "unit"}
    }
  }
}
```

`collection` requires only `resource_kind` and `inventory` (bounded identifiers,
1–80 characters). Optional `columns` is a nonempty list of at most 32 closed
`{field, label}` records, with unique declared scalar row fields and labels of
1–80 characters. `inspect` has exactly the two keys shown; its map has at most
32 unique target-input keys and direct scalar row-field values. No expressions,
provider pins, callbacks, resource-specific renderer or general action list.
Absent columns use declaration order; absent inspect uses validated inline data.
Reject unknown keys and invalid metadata at admission. Target availability and
provider ambiguity are evaluated through the current registry, not disk presence.

`outputs` retains its existing four root keys: `schema_version: 2`, `properties`,
`required`, `additionalProperties: false`. Extend the shared field grammar only:

- Retain existing bounded scalar types/constraints. Scalar `validator` may reuse
  the existing pure type-compatible validators, including `systemd_unit`; no
  secret/path input semantics or executable validator names become output types.
- `type: object` has exactly `type`, `properties`, `required`,
  `additionalProperties: false`; each record is closed, with at most 32 fields.
- `type: array` has exactly `type`, `items`, `minItems`, `maxItems`; bounds are
  nonnegative integers, `minItems <= maxItems <= 128`. Initially admit only the
  collection's row array with closed object items, not arrays of arrays.
- `type: scoped_reference` has only `type`; values have exactly `scope_id` and
  `object_id` and delegate to D049 validation. This is a schema spelling for
  the existing reference, not a new ID format or resolver.

No unions, nulls, schema references, arbitrary maps, recursive definitions or
arbitrary JSON Schema vocabulary. Depth counts the root record as 1, row array
as 2, row record as 3 and scoped-reference record as 4. Page/freshness records
are depth 2. All required lists are unique subsets of declared properties.

For a `collection` descriptor, root properties are exactly the five domain
fields specified above, all required. `resource_kind`/`inventory` are singleton
string enums matching the descriptor. `rows` has `minItems: 0`, `maxItems: 128`;
its required `reference` uses `scoped_reference`. System's other required fields
are `unit` (string, maxLength 256, validator `systemd_unit`), `active_state` and
`sub_state` (strings, maxLength 80); the synthetic provider declares its own
bounded scalar fields. Output selectors are not duplicated: the inspect target's
existing input schema/selector remains authoritative.

`page` requires `snapshot_revision` (bounded opaque string, 1–128 characters),
`returned_count` (integer 0–128), `total_count` (integer 0–1024) and `has_more`
(boolean); its only optional field is `next_cursor` (string, 1–256 printable
ASCII bytes). `freshness` requires only `observed_at` and `expires_at` (strings,
maxLength 32). Core validates canonical UTC timestamps and the fixed TTL,
returned_count against row count, total_count against the frozen inventory,
and next_cursor presence iff has_more. These fixed collection checks express
cross-field invariants without extending the schema into a condition language.
Core owns page/freshness/reference provenance; handlers cannot supply arbitrary
cursor or scope authority. All byte ceilings apply after strict UTF-8 JSON
serialization as well as before reading/allocating untrusted data.

Admission verifies that every inspect input maps to a declared scalar field;
active-target resolution additionally verifies type/constraint compatibility,
required inputs and selector resource kind. A value is revalidated by the
canonical target input/selector validator at invocation even if its row schema
appeared compatible. The backend freezes the chosen target/provider/version,
checks object existence and identity under its canonical selector, and derives
all arguments from the validated snapshot. The TUI supplies the scoped reference
and optional explicit provider choice through the existing ambiguity flow; it
cannot supply row values, override binding inputs or choose a safety tier.

### Global budget, expiry and measured acceptance

The per-session limits also sit under a **global local-runtime budget**, covering
all backend sessions/processes sharing this Igor runtime directory. Provisional
ceilings: eight snapshots and 4 MiB serialized snapshot data in aggregate,
including reserved/in-flight construction. Reserve count/byte capacity atomically
under the existing private runtime ownership before constructing a snapshot;
stop bounded source reads at the reserved ceiling. Release reservations on
failure, expiry, disable, session end or dead-process recovery. This is ephemeral
accounting, not a persistent inventory or a new daemon. Independent sessions
cannot evict each other's fresh snapshots silently. Exhaustion returns bounded
`collection_budget_exhausted` through the existing error/result path, with no
successful partial inventory. Test simultaneous sessions and abandoned leases.

Use stable value-free reasons in that same path: `collection_limit_exceeded`
for snapshot/row/page/event limits, `collection_expired` for an expired valid
cursor/selection, and the existing validation/unavailable reasons for invalid
or mismatched references/providers. Never include rejected data or cursor values
in errors. Limit checking precedes publication; a failed refresh leaves prior
rows visibly stale/read-only and cannot claim they are a fresh successful result.
A cursor is valid only while elapsed time is **strictly less than 30 seconds**
from snapshot creation. Expiry is absolute, never renewed by paging/detail/back.
All later requests fail deterministically with an explicit refresh affordance;
no automatic refresh, rebind, retry or substitution. Displayed expired rows may
remain bounded for context, but cannot drive detail invocation. Back is allowed
as navigation and shows that stale state; refresh starts a new canonical operation.

Measure peak RSS against an equivalent empty-session baseline for the backend
and TUI separately, including parsing, validation, event serialization, detail,
refresh overlap and cleanup. Provisional acceptance ceilings: at most 16 MiB
incremental peak RSS per active backend session, 64 MiB aggregate backend
increment across the global budget, and 8 MiB incremental TUI peak. Exercise
maximum-size UTF-8 pages/snapshots, repeated refresh/back and simultaneous sessions;
record baseline/peak/released RSS, row/byte counts, hardware/OS, and first-page,
detail, navigation and refresh timings. Count/byte allocation bounds and cleanup must produce predictable resource
errors; RSS ceilings are measured acceptance gates, not a new runtime RSS monitor. Validate these on a declared Raspberry Pi-class system;
fixtures alone cannot establish constrained-hardware performance. A failed
ceiling is evidence for Owner-reviewed tuning, never permission to silently
raise it or create another transport/execution path.

Validate the provisional 30-second TTL with at least ten human-paced
list/select/detail/back/page/refresh sequences, recording elapsed time and how
often ordinary navigation hits expiry; include boundary tests just before/at/
after 30 seconds and deliberate think-time beyond expiry. Detail already
invoked while fresh follows its frozen canonical operation; a later expired
request cannot revive it. If routine navigation regularly expires before detail,
report that usability evidence for Owner review before accepting the TTL;
retain the bounded explicit-expiry behavior regardless of any approved tuning.

| Decision | Alternatives / consequences | Recommendation |
|---|---|---|
| Q022 structured schema and version cutover | Keep scalar preview: no generic typed consumer. Add duplicate ID/parallel validator: permanent duplication. Evolve same ID/shared validator: complete consumer/pin/fixture migration, richer rejection checks and retained History version handling. | Same ID, capability version 3/output schema 2, closed rows/page/freshness and D049 references; use the closed declaration grammar above. |
| Q023 bounded pagination ownership | Single bounded page: simplest but incomplete inventories need explicit error. Live offset pages: unstable membership. Bounded frozen snapshot: stable paging with expiry/cleanup under existing runtime ownership. | Default 50/max 128 rows, 64 KiB page/96 KiB event, 1024 rows/512 KiB snapshot, two snapshots/1 MiB per session, 30-second TTL and bounded opaque cursor; no new persistence. |
| Q024 row inspection binding | Hard-code service actions in TUI: domain coupling. General workflow/action language: excess scope. Minimal declared READ target plus typed input binding: generic frontend with canonical backend revalidation. | One descriptor-owned inspect target/direct property-to-input map, backend scope/selector revalidation and canonical READ policy/dispatch; no row-owned provider or action language. |

No decision here grants mutation authority. Q022–Q024 are resolved by the
Owner's acceptance, and the Owner reports complete v2 fidelity. Independent
source-hash/reviewed-candidate verification still prevents formal DISCOVERY exit
in this checkout.

## Acceptance and bounded implementation sequence

After source/candidate integrity verification closes DISCOVERY, the first bounded EXECUTION
slice crosses Step 18 contracts/consumer migration and Step 20 generic rendering
together: structured READ collection → selection → READ details → back → refresh,
with System and the unrelated synthetic provider. Do not reopen
Waves D–F, duplicate registries or automatically begin later approved actions.
Each slice stops with its own evidence under [EXECUTION.md](EXECUTION.md).

| Formal proof class | Required observable acceptance |
|---|---|
| Contract proof | Valid typed collections, zero rows and exact bounds; reject malformed/nested/duplicate/oversized data, invalid scopes, unknown versions, expired/tampered cursors and bad input bindings. Rejected output never becomes success or ordinary retained payload. |
| Regression proof | Current canonical consumers/pins/fixtures migrated together; scalar expectations replaced with equivalent typed coverage. Preserve safety tiers, exact destructive confirmation, decline-before-authentication, sudo-through-PTY, active-owner/dependency/ambiguity, secrets/scrubbing, History and output/verification separation. |
| Vertical-slice proof | Actual System declaration/handler/platform abstraction through canonical dispatch and frontend: list → select → status/details → back → refresh. Same renderer with unrelated synthetic provider. Typed/pasted and explorer invocations have identical backend request/provider semantics. Mock host services; report synthetic versus live-host evidence separately. No restart. |
| Inspection proof | CLI/TUI expose schema, capability/version/provider/scope/operation, page completeness, freshness, limits and unavailable reasons without executing or granting authority. Registry refresh and domain refresh are distinct. |
| Migration/recovery proof | Inventory and migrate all internal consumers; exact old pins fail safely. Historical records retain meaning and inspection. Snapshot expiry, module disable, backend interruption/restart, refresh failure and selection removal cannot reuse stale authority. Any persistent format change has explicit idempotent cutover/verification/recovery; otherwise record no persistent migration with evidence. |

### Focused acceptance criteria retained from the first draft

- Initial `inventory=loaded_system_services` means loaded system-manager units,
  including inactive loaded units, not installed unit files or user-manager
  services. The existing Platform query uses `systemctl list-units --all`;
  keep parsing there with deterministic locale and alias/template/transient/
  malformed/vanished-unit fixtures. Do not assume every systemctl version emits
  JSON. Missing systemd is canonical unavailable/dependency failure, not a
  successful empty inventory, installation or silent provider fallback.
- Typed, pasted and completed colon commands, explorer/palette choices,
  headless CLI and in-process canonical requests agree on identity, validated
  inputs, provider, policy outcome and result schema, with zero model calls for
  deterministic human invocation. Preserve Ctrl+P session commands; no hard-coded
  module command list, HTTP/RPC daemon or new TUI dependency is needed.
- Retain PTY plus ordered JSONL. Bound serialized capability intent to 8 KiB
  UTF-8 and reject terminal controls/malformed/unknown fields before dispatch.
  Frontend intent remains untrusted data, never shell or caller-selected authority.
  Emit one bounded structured result/error projection per page/detail request
  through the existing writer, never one event per row or a second approval
  state machine. Keep inline pages within the existing proposed event ceiling;
  private result handles are deferred until actually needed.
- Correlate replies with backend operation identity and the active view request.
  Disposable frontend request tags cannot grant authority. Late replies cannot
  replace a newer refresh/detail view or restore a disabled provider's selection.
  Rejected/oversized requests/results must leave the ordered event stream usable
  for the next valid request, with bounded machine-readable errors and no raw
  rejected payload. Pending approval ownership stays backend-owned if navigation
  changes in a separately approved later mutation proof.
- No-hint fallback, keyboard/Page Up/Down/Enter/Esc navigation, local sort/search/
  filter, details/back/refresh and small terminals work with the unrelated
  synthetic provider without frontend edits. Sort/filter applies only to loaded
  rows, is labeled accordingly and never changes reference identity or snapshot
  paging order. Check UTF-8 byte boundaries, allocation failures and declared
  row/page/session caps; report hardware measurements separately from fixtures.

Use `tests/validate.sh` with a planned focused/affected selection and existing
governor limits. Preserve all five proof classes, source/environment/candidate
attribution, actual skips and unverified behavior. Docs-only results from this
task cannot satisfy these runtime acceptance checks.

There is no Gate 0 for the alleged 12 `master`-only commits: the baseline is the
actual current `igor2` tree. No branch comparison or reconciliation is required.

## DISCOVERY entry/exit assessment (2026-10-11)

Entry evidence is satisfied: active independent `igor2` checkout inspected,
existing Step 18/20 registry/validator/dispatcher/result/operator boundaries
identified, READ-only scope bounded, Owner Q022–Q024 direction accepted, and
applicable documentation/current-contract checks selected. No runtime feature
or test contract is superseded by this documentation pass.

The Owner's completed v2 fidelity comparison settles architectural completeness:
no material gaps remain under D078/D079. The remaining exit evidence is the
requested independent original SHA-256 verification and confirmation that the
local candidate is the one covered by that comparison. Neither source bytes nor
a candidate-bound comparison artifact is accessible here, so formal DISCOVERY
completion is not recorded. The grammar, five proof classes, migration
obligations and bounded first slice remain unchanged. Hardware/RSS and
30-second navigation measurements are acceptance work for EXECUTION, not
DISCOVERY results.

Once integrity verification and scoped documentation/contract checks pass,
recommend the first bounded EXECUTION slice described above; stop before any
restart/configuration or later-wave implementation. Record actual runtime
proof separately from documentation evidence.
