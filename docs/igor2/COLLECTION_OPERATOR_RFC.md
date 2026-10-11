# Igor 2 Collection Results and Operator Interface RFC

Status: **proposed extension in DISCOVERY; no runtime implementation authorized**.

Prepared 2026-10-10 against local `igor2` commit `5b80740`, under
[Development Policy / D078](DEVELOPMENT_POLICY.md). This document extends
Step 18 output contracts and Step 20 operator rendering without reopening
completed waves. It does not replace the capability runtime, registry,
operator explorer, D049 identity or approval/execution machinery.

Source limitation: the named attachment `igor2_collection_operator_rfc_v2.md`
was not available in this checkout or accessible task attachments. This proposal
is derived from the Owner's explicit RFC revision requirements in the task,
not a claim to have reviewed the missing original. Compare that source before
closing DISCOVERY if it contains additional requirements.

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
the recommendation is a new capability contract version (3 for this migration)
and an explicitly versioned structured output schema (2), leaving Module API
version unchanged unless its contribution envelope actually changes. Exact
versions/shapes require Q022 confirmation; today's validators still allow only
1/2 and schema 1. Migrate pins and all consumers together; old mismatched pins
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

Recommended collection domain semantics (field spellings remain proposed):

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

## Bounds, freshness, pagination and privacy (Q023 proposal)

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

## Options and Owner decisions before EXECUTION

| Decision | Alternatives / consequences | Recommendation |
|---|---|---|
| Q022 structured schema and version cutover | Keep scalar preview: no generic typed consumer. Add duplicate ID/parallel validator: permanent duplication. Evolve same ID/shared validator: complete consumer/pin/fixture migration, richer rejection checks and retained History version handling. | Evolve same ID; approve exact closed schema/reference/result projection and version axes before runtime edits. |
| Q023 bounded pagination ownership | Single bounded page: simplest but incomplete inventories need explicit error. Live offset pages: unstable membership. Bounded frozen snapshot: stable paging with expiry/cleanup under existing runtime ownership. | Frozen bounded snapshot with the ceilings above; approve cursor lifecycle and History/event retention, then measure constrained-host costs. |
| Q024 row inspection binding | Hard-code service actions in TUI: domain coupling. General workflow/action language: excess scope. Minimal declared READ target plus typed input binding: generic frontend with canonical backend revalidation. | Minimal registered READ binding, explicit ambiguity and scope revalidation; approve exact metadata before admission changes. |

No decision here grants mutation authority. The Owner has authorized this
direction and policy, not the unresolved durable collection contract. Missing
original-RFC comparison and Q022–Q024 prevent an implementation-ready claim.

## Acceptance and bounded implementation sequence

After source comparison and decision confirmation, implement through separate
bounded Step 18 contract/consumer and Step 20 renderer slices. Do not reopen
Waves D–F, duplicate registries or automatically begin later approved actions.
Each slice stops with its own evidence under [EXECUTION.md](EXECUTION.md).

| Formal proof class | Required observable acceptance |
|---|---|
| Contract proof | Valid typed collections, zero rows and exact bounds; reject malformed/nested/duplicate/oversized data, invalid scopes, unknown versions, expired/tampered cursors and bad input bindings. Rejected output never becomes success or ordinary retained payload. |
| Regression proof | Current canonical consumers/pins/fixtures migrated together; scalar expectations replaced with equivalent typed coverage. Preserve safety tiers, exact destructive confirmation, decline-before-authentication, sudo-through-PTY, active-owner/dependency/ambiguity, secrets/scrubbing, History and output/verification separation. |
| Vertical-slice proof | Actual System declaration/handler/platform abstraction through canonical dispatch and frontend: list → select → status/details → back → refresh. Same renderer with unrelated synthetic provider. Typed/pasted and explorer invocations have identical backend request/provider semantics. Mock host services; report synthetic versus live-host evidence separately. No restart. |
| Inspection proof | CLI/TUI expose schema, capability/version/provider/scope/operation, page completeness, freshness, limits and unavailable reasons without executing or granting authority. Registry refresh and domain refresh are distinct. |
| Migration/recovery proof | Inventory and migrate all internal consumers; exact old pins fail safely. Historical records retain meaning and inspection. Snapshot expiry, module disable, backend interruption/restart, refresh failure and selection removal cannot reuse stale authority. Any persistent format change has explicit idempotent cutover/verification/recovery; otherwise record no persistent migration with evidence. |

Use `tests/validate.sh` with a planned focused/affected selection and existing
governor limits. Preserve all five proof classes, source/environment/candidate
attribution, actual skips and unverified behavior. Docs-only results from this
task cannot satisfy these runtime acceptance checks.

There is no Gate 0 for the alleged 12 `master`-only commits: the baseline is the
actual current `igor2` tree. No branch comparison or reconciliation is required.
