# Step 13 — Domain Event Bus implementation contract

Status: **accepted design; Step 13 implemented**. This is the bounded Step
13 contract, subordinate to [ARCHITECTURE.md](ARCHITECTURE.md) and D040–D042 in
[DECISIONS.md](DECISIONS.md). The existing Wave E capability result and Wave C
owner-aware contribution index are its inputs. Completion still requires all
five proof classes in [EXECUTION.md](EXECUTION.md).

## Boundary and authority

A domain event is a validated signal about an operational occurrence. It is
neither System Model truth nor an instruction. Publishing or receiving one
cannot authorize a capability, satisfy approval, grant OS privilege, bypass
READ/CHANGE/DESTROY policy, establish verification success, activate a module,
or expose a secret. The canonical capability result and its verifier remain
authoritative for execution and verification status. Later automation must
enter the same capability resolution, policy, approval, privilege, execution
and verification path as any other caller. An event is never an approval token.

`core/ai/events.sh` carries AI/TUI presentation activity, including approval
prompts and rendered action results. It remains a separate contract and file.
The domain bus owns operational events and its own type registry, validation,
transient delivery and inspection. A future read-only projector may render a
validated domain event into the frontend stream; that projection grants no
domain authority and must not feed back into the bus.

## Types, producers and ownership

Core declares built-in types in trusted code. Step 13 registers exactly
`capability.completed` with schema version 1. It means a canonical capability
invocation has a terminal structured result, including denied, failed and
unverified outcomes; it does **not** imply success. Do not also emit
`capability.failed` for the same result. The existing v1 action dispatcher and
raw shell have no canonical Wave E result and are outside this first emission
slice.

Module API v2 already recognizes `domain_event` as a contribution kind, but
today that placeholder does not validate an event payload or publish one. Step
13 tightens its declaration: an active module may declare a type named
`<owner>.<domain>.<occurrence>` with a `payload_schema` for envelope version 1.
Reuse the capability-input schema shape: `properties`, `required` and
`additionalProperties: false`. Step 13 permits only flat `string`, `boolean`,
`integer`, `number`, `enum` and `object_id` fields; no paths, secret references,
nested objects or arrays. The event contribution is data only, has no
handler, and enters the existing owner-aware index. Reject malformed,
duplicate or Core-reserved declarations before they become active. Keep the
existing v1 `notify_events` hook separate; it does not register domain types.
For example, a future `system` declaration can use `kind: domain_event`,
`id: system.disk.threshold_exceeded` and a `payload_schema` with required
bounded numeric fields; declaring it does not publish or subscribe to it.

Core publishes its built-in type only from the component that owns the
canonical result. A module may request publication only for its own active,
registered type through the module runtime boundary; the publisher derives
the owner from the registered contribution and stamps the source as
`module:<owner>`. The runtime binds the calling owner from its active handler
context, not a module-supplied owner argument. A caller may supply only
declared payload and related object IDs, never owner, source, event ID,
timestamps or correlation fields. Core
checks current owner/contribution state on **each** publish, including after a
disable in the current process. Disabled/unavailable modules cannot publish
through this boundary or leave active types behind. Reviewed local Bash code
is not a hostile-code sandbox; these checks define the supported API, not OS
isolation. Module handler stdout, logs, knowledge, observer output and check
results do not become events merely by containing event-shaped text.

Unknown type/version, inactive owner, undeclared field, bad object ID, invalid
status combination, excessive size or secret-bearing data is rejected before
the event enters the buffer or reaches subscribers. A rejected publish returns
a typed error to its caller. It must not be silently converted to a different
event. Core-origin capability emission is best effort after result commit:
publication errors may be diagnosed but cannot rewrite or rerun the result.

## Version-1 envelope

One published event is a JSON object. Required fields are `schema_version`,
`event_id`, `event_type`, `source`, `owner`, `related_objects`, `occurred_at`,
`recorded_at`, `evidence` and `payload`. The remaining fields are optional and
omitted when unavailable, not filled with invented IDs. No other top-level
fields are allowed:

| Field | Contract |
|---|---|
| `schema_version` | Integer `1`; unknown versions fail closed. |
| `event_id` | Core-generated UUIDv4; never supplied by payload. |
| `event_type` | Registered dotted type ID. |
| `source` | Core-stamped producer, e.g. `core:capability_runtime` or `module:system`. |
| `owner` | Core-stamped domain owner, e.g. the resolved capability owner; never inferred from payload prose. |
| `related_objects` | Zero or more validated Wave D object IDs, bounded to eight; capability events use the frozen result's `affected_objects`. |
| `occurred_at` | UTC timestamp from the trusted canonical result when one exists, otherwise Core publish time. |
| `recorded_at` | UTC timestamp when Core accepts the event; may be later than `occurred_at`. |
| `severity` | Optional `info`, `warning` or `critical`; describes signal priority, not action authority. Capability completion uses `info` for `success`, `warning` otherwise. |
| `evidence` | At most eight redacted references `{kind, ref}` to owning subsystem records, not embedded logs, fact values, command output or secrets. |
| `correlation_id` | Optional bounded ID shared by one operation or later workflow. For the first slice, the canonical `operation_id`. |
| `causation_id` | Optional `event_id` of the immediate triggering event, supplied only by trusted Core orchestration; absent in the first slice. |
| `operation_id`, `capability_id` | Optional canonical IDs only when the source record actually has them. Wave E has no plan ID, so Step 13 does not invent one; later plan correlation uses a real plan identifier when that contract exists. |
| `payload` | Type-specific JSON object validated against the registered bounded schema. |

IDs and scalar strings are limited to 160 and 256 characters respectively;
the UTF-8 encoded payload is at most 2048 bytes and the full event at most
4096 bytes. Timestamps are UTC RFC 3339 with `Z`. Reject unknown
envelope/payload fields, non-finite numbers and values outside declared
bounds. Redaction is applied before publication and inspection, with rejection
for known secret-bearing fields or literal values. Evidence references are
metadata, not proof of a verifier's success; consumers must query the owning
subsystem for authoritative details while available.

The built-in `capability.completed` payload is exactly:

```json
{
  "execution_status": "succeeded",
  "verification_status": "failed",
  "outcome": "unverified_change"
}
```

These three fields copy the **validated, committed** Wave E result, retaining
its status vocabulary and consistency rules. `operation_id`, `capability_id`,
owner, affected objects and result time come from the same result, not from
provider output. `evidence` contains a `capability_result` reference to that
operation ID, shaped as `{"kind":"capability_result","ref":"op-..."}`;
the event does not copy the potentially large verifier evidence.
The event can be inspected even if its referenced transient result has expired,
but must not claim that the evidence remains retrievable. A terminal result
produces at most one such event. No event is emitted for an invocation rejected
before a canonical result exists.

## Delivery and failure model

The bus belongs to one Igor backend process tree/session, with no durable
event store. Publishing validates, stamps and
appends synchronously, then invokes trusted Core subscribers in registration
order. A subscriber receives an immutable event value. Its exception or
nonzero return is diagnosed and does not stop later subscribers, change the
accepted event, or change the capability result. Step 13 has no module
subscriber API; later consumers subscribe through Core-owned adapters.

Publication order is the serialized acceptance order in this one session,
including cooperating shell subprocesses. No ordering is promised across
sessions or machines. Event IDs are identities, not sortable sequence numbers.
Subscribers may not recursively publish during a Step 13 callback; a later
step may define a bounded follow-up mechanism when needed. There is no queue,
retry, replay, acknowledgement, exactly-once delivery or cross-restart
delivery. A subscriber present after publication receives no past callbacks.

Keep the most recent 128 accepted events in a session-local inspection buffer.
The Bash/Python boundary may use a private, session-scoped runtime scratch
file to make accepted events visible across existing command substitutions;
it is disposable IPC, not an operational-history log. The owner session must
not replay a prior session's file. That scratch must have a fresh session
identity, owner-only permissions and bounded size matching the 128-event
limit. A crash can lose events; stale scratch is
ignored and may be cleaned up. Step 15 owns any durable operational history,
retention, replay and reconciliation contract. Step 14 owns scheduling,
automation activation and retry decisions.

## Inspection and first proof slice

Expose read-only backend queries for registered types and the bounded recent
events, with optional exact type/owner/object/correlation filters. Type
inspection shows schema version, declared source/owner and active/unavailable
state; event inspection returns source, owner, related objects, times,
correlation/causation, statuses and safe evidence references. Inspection does
not refresh an observer, run a check, invoke a capability, authenticate, or
dereference a secret. An empty buffer is a valid result.

First real slice: invoke active `system.host.memory.refresh` through its
existing capability path. After its deterministic verifier commits a result,
publish one `capability.completed` with `host:local`, operation correlation,
`execution_status=succeeded`, `verification_status=passed` and
`outcome=success`. Inspect the same ID and source. The existing disposable
`system.service.restart` fixture supplies the failure case: process execution
succeeds, verifier fails and the event carries `unverified_change`. No real
service restart is needed. Denial/precondition/privilege terminal results can
be covered with focused fixture tests without broadening the slice.

## Falsifiable Step 13 completion checks

| Proof class | Required evidence |
|---|---|
| Contract | Strict type and envelope validation rejects unknown/malformed/oversize/secret-bearing events before buffering or callbacks. Owner/source cannot be spoofed by payload. Inactive module types cannot publish. `capability.completed` preserves all three result statuses, including `unverified_change`; an event cannot satisfy approval, privilege or verification. |
| Regression | Previously green Wave E capability, Wave D model/check, Wave C activation/v1 compatibility, safety/PTY and frontend event behavior remain green. The new domain path does not rename or consume `core/ai/events.sh` events. |
| Vertical slice | Real memory refresh produces exactly one correlated, inspectable success event after result commit; disposable service fixture produces exactly one event with execution success, verification failure and `unverified_change`. A subscriber failure leaves each canonical result unchanged and later subscribers receive the accepted event. |
| Inspection | Type and recent-event queries show owner/source, object, correlation/causation and evidence metadata; filters and disabled-owner state work; query causes no observer, check, capability or privilege side effect. |
| Migration/recovery | Existing installations require no persistent layout migration. A new session starts with an empty event buffer and does not replay previous scratch. Current facts/results can be refreshed or recomputed only through their normal boundaries; lost event IDs, ordering and callback delivery cannot be reconstructed. Existing audits/journals remain separate until Step 15 defines cutover. |

## Implemented Step 13 sequence

1. Tighten the v2 `domain_event` declaration and add the version-1 event
   schema/validator using the owner-aware index.
2. Add the session-local publisher, bounded recent buffer, Core subscriber
   registration and read-only inspection.
3. Project one event from each committed canonical capability result, after
   the existing policy/privilege/verifier path; leave v1 and raw shell alone.
4. Prove the memory success and disposable service verification-failure
   slices, malformed/disabled-owner rejection and subscriber isolation.
5. Run focused tests plus the existing compatibility/regression gate; prove
   empty-on-restart and no persistent migration.
6. Update implementation status and current docs only after those checks pass.

Q003 remains a Step 15 persistence decision; Q008 remains Step 14 automation
activation. Q007, Q009 and Q011 remain at their assigned later steps. This
contract does not turn exploratory AI-role ideas into event requirements.
