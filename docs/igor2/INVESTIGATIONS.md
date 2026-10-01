# Step 15C — Durable Investigations

Status: **accepted bounded contract** (D056); implementation evidence is in
[STATUS.md](STATUS.md). The owning service is
[InvestigationService](../../core/lib/investigations.py).

An investigation is something Igor or an operator wants to understand, track,
evaluate or resolve over time. It owns knowledge organization and its explicit
lifecycle. It does not own execution, current system state or responsibility.

## Version 1 record

The closed `igor.investigation` version-1 record contains:

- fresh opaque `investigation_id` and the installation's stable local `scope_id`;
- title, summary, creation source, owner and timestamped source provenance;
- status, creation/update/closure timestamps and explicit transition history;
- scoped related objects and Operational History episode references;
- bounded evidence references and hypotheses;
- validated judgments used, findings, unresolved questions and closure reason.

Unknown fields and versions, invalid timestamps, duplicate JSON fields,
nonfinite numbers, invalid IDs and cross-scope links fail validation. Limits
bound text, collections and the store: 256 investigations, 32 hypotheses/findings/
questions per record, 128 evidence/object/history references and transitions,
eight judgment pairs, 512 KiB per record and 8 MiB per store. Lists default to
20 records, with a programmatic maximum of 100. IDs are never interpreted as commands,
paths, capability providers or permissions. Creation owner/provenance identifies
where the investigation came from; it grants neither authority nor operational
responsibility. All retained user/model text is reference data.

## Lifecycle

States are `open`, `collecting_evidence`, `evaluating`, `resolved`, `closed` and
`abandoned`. The service validates each transition and retains its timestamp
and reason. `resolved`, `closed` and `abandoned` are terminal and reject ordinary
updates. Resolution is an investigation assessment, not verified operation
success. Closure does not require every question to have an answer.

| From | Allowed ordinary transition targets |
|---|---|
| `open` | `collecting_evidence`, `evaluating`, `closed`, `abandoned` |
| `collecting_evidence` | `open`, `evaluating`, `closed`, `abandoned` |
| `evaluating` | `collecting_evidence`, `resolved`, `closed`, `abandoned` |
| `resolved`, `closed`, `abandoned` | None; explicit `reopen` only |

Same-state or unknown transitions fail. Resolution requires evaluation first.

Explicit `reopen` requires a reason, returns a terminal investigation to `open`,
and retains earlier transitions, findings and uncertainty. The current closure
metadata is cleared; the prior reason remains in transition history. There is
no automatic progression, reopen, evidence collection or model invocation.

Hypotheses have `proposed`, `supported`, `contradicted` or `inconclusive` status,
linked supporting/contradicting evidence, related judgments, optional assessment
and self-reported confidence. Each hypothesis state may explicitly transition to any other hypothesis state;
same-state transitions fail. References must identify attached evidence/judgments,
and one evidence ID cannot simultaneously support and contradict the same
hypothesis. Updates are explicit. A hypothesis is not a fact,
plan, permission or verification result. Conclusions remain investigation-scoped
findings even when a hypothesis is supported.

## Evidence and subsystem ownership

Evidence has a local ID, kind, scope, target identity, source, recorded timestamp,
availability and optional bounded locator/object metadata. Kinds are `operation`,
`capability_result`, `verification`, `system_fact`, `judgment` and `file`.
Locators are reference metadata only; the service does not read files or fetch
external evidence. Missing/unavailable references may survive retention changes;
they never resolve to a reused identity or silently become truth.

- **Operational History (15B)** answers “what happened?” Episode references retain
  scope and operation ID. Results, verification and recovery evidence remain in
  their history episode; investigations do not duplicate or rewrite that record.
- **System Model** answers “what is the current known state?” A fact reference
  records object/source/time metadata. Investigation inspection does not refresh
  observations. A finding that a fact may be wrong does not modify the fact.
- **Judgment Contract (D055)** answers “what structured interpretation did a model
  provide?” Attachments retain a bounded sanitized request and its validated
  record, including invocation provenance, digest, confidence and abstention.
  The request is needed to revalidate the existing contract's binding after
  restart. Attachments call its validator, never its model adapter. No independent
  judgment database, truth promotion or model routing is introduced.

Supporting and contradicting references may coexist. Unknown/abstain outcomes
and unresolved questions remain inspectable after closure/restart/export.
Historical evidence cannot satisfy current preconditions or override verification.

## Persistence and recovery

The backend is private versioned JSON, protected by an installation-owned private
0700 directory and 0600 file. A directory lock serializes readers/writers;
validated updates use atomic replacement and file/directory synchronization.
Interrupted updates expose the previous or new complete document, never a partial
record. Symlink/ownership/permission checks prevent unsafe store substitution.
The public contract exposes records and service operations, not filenames.

Scope identity is allocated/reused through Operational History's explicit
`ensure_scope()` service method. Allocation creates no episode, recovery,
verification or execution. Read-only investigation operations never allocate a
scope or create a store. Stored investigation scope must match the installation's
history scope; identity mismatch fails closed.

The source layout for this milestone has **no investigation store**. The target
is an empty version-1 private store created on the first valid mutation. No chat,
legacy journal, System Model cache or history records are imported. Existing
history storage/schema is unchanged. Repeated initialization reuses the local
scope. This service is the single investigation authority; there is no dual write.

Export before recovery. Restore validates the complete versioned export, accepts
an empty destination or an identical already-restored document, and rejects a
nonempty different store. Restore continues the same managed installation and
preserves IDs/scope. Restore Operational History's export first when recovering
into a new data destination; investigations cannot invent/rebind installation
identity. Unknown/corrupt versions remain untouched and refuse operations.
Recover a validated export into a fresh private destination; no repair guessing
or automatic version migration is provided. Future versions must specify source,
target, validation, idempotency, cutover, verification and recovery explicitly.
A distinct installation starts with fresh identity and no imported investigations.

Known sensitive values and secret-bearing fields are excluded from retention.
Judgment bindings that would require secret redaction are rejected instead of
silently changing their digest. Callers must supply sanitized reference data;
provenance and locators must not contain secret values.

## Bounded interfaces and inspection

`InvestigationService(data_dir).handle(action, fields)` dispatches only a closed
set of data operations: `create`, `add_evidence`, `add_hypothesis`,
`update_hypothesis`, `attach_judgment`, `set_findings`, `set_questions`,
`transition`, `close`, `reopen`, `list`, `status`, `inspect`, `export`, `restore`.
Mutations identify `investigation_id`; each operation validates its own fields.
Python callers may also use the named service methods.

| Operation | Additional fields |
|---|---|
| `create` | `title`, optional `summary`, `source`, `owner`, `provenance`, optional `related_objects`, `related_history` |
| `add_evidence` | `evidence`: typed reference object |
| `add_hypothesis` | `statement`; initial status is `proposed` |
| `update_hypothesis` | `hypothesis_id`, required `status`, optional `supporting_evidence`, `contradicting_evidence`, `judgments`, `assessment`, `confidence` |
| `attach_judgment` | `request`, `record` from the existing Judgment Contract |
| `set_findings` | `findings`: bounded strings, replacing investigation findings |
| `set_questions` | `unresolved_questions`: bounded strings, replacing unanswered questions |
| `transition` | `status`, `reason` |
| `close` | `reason`, optional terminal `status` |
| `reopen` | `reason` |
| `inspect` | `investigation_id` |
| `list` | Python interface accepts optional `limit` and `status`; shell default is a bounded list |
| `restore` | `export`: complete exported envelope |

A reference example (the caller substitutes the actual retained scope/operation
IDs) is:

```json
{"id":"failed-backup","kind":"operation","scope_id":"scope:OPAQUE_ID","target":"op-OPAQUE_ID","source":"operational_history","recorded_at":"2026-10-01T12:00:00Z","availability":"available"}
```

This references evidence; it asserts no execution or verification outcome.

```bash
bash igor.sh --investigations list
bash igor.sh --investigations status
bash igor.sh --investigations inspect inv-OPAQUE_ID
bash igor.sh --investigations create - <<'JSON'
{"title":"Understand backup failure","summary":"Cause remains unknown","source":"operator","owner":"operator","provenance":{"source":"operator.cli","recorded_at":"2026-10-01T12:00:00Z"}}
JSON
umask 077
bash igor.sh --investigations export > investigations-export.json
# Restore takes {"export": <the exported document>} as JSON on standard input.
```

The headless CLI bypasses module/configuration and AI startup. List/status/
inspect/export are read-only. The existing 15UI panel adds an Investigations
section with lazy read-only loading through this CLI and the existing bounded
structured renderer. It displays lifecycle, evidence, hypotheses, judgments,
findings, uncertainty and provenance. No special investigation UI/editor exists;
panel selection/Enter only requests inspection. Headless inspection exposes the
full bounded record even when the renderer truncates long content.

## Authority boundary and deferrals

The service has no capability executor, approval, privilege, module activation,
System Model writer, automation, observer or verifier handle. It cannot change
desired state, make stale facts fresh, grant authority or trigger operations.
Findings, creation ownership and provenance do not acquire those meanings without
separate authoritative processes. No automatic consumer or AI context injection
is added.

[Step 15D](CONTEXT_ROUTING.md) now provides explicit scoped, read-only selection
of investigation material and attached judgments for AI reference context.
It changes no investigation lifecycle/storage or fact/approval authority;
selection provenance is not automatically retained as investigation knowledge.

Deferred: autonomous/recursive investigation, agents, background monitoring,
self-healing/remediation, plans/workflows, scheduling/automation integration,
remote scopes, relationships/deployments, learning and Jet/Laya. Step 15C added
no model routing/selection; the subsequent Step 15D contract owns that explicit
integration. Step 20 owns the separate default interface transition.
