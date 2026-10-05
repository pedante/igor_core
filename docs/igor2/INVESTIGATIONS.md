# Step 15C / Step 16C — Durable Investigations and Typed Findings

Status: **Step 15C implemented under D056; Step 16C typed-evidence extension
implemented under D064**. Evidence is recorded in [STATUS.md](STATUS.md). The
owning service remains [InvestigationService](../../core/lib/investigations.py).

An investigation is something Igor or an operator wants to understand, track,
evaluate or resolve over time. It owns knowledge organization and its explicit
lifecycle. It does not own execution, current system state or responsibility.

## Versioned record

Version 2 is the current contract. Version-1 stores remain valid, readable and
exportable without read-time migration. The closed `igor.investigation` record
retains the original fields:

- fresh opaque `investigation_id` and the installation's stable local `scope_id`;
- title, summary, creation source, owner and timestamped source provenance;
- status, creation/update/closure timestamps and explicit transition history;
- scoped related objects and Operational History episode references;
- bounded evidence references and hypotheses;
- validated judgments used, free-form compatibility findings, unresolved
  questions and closure reason;
- in version 2 only, bounded `typed_findings` that bind an investigation claim
  to already-attached evidence/hypotheses/judgments.

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

## Step 16C typed findings

Version 2 adds stable typed findings without reinterpreting existing free-form
`findings`. A typed finding has an opaque `tf-` identity, immutable
`kind` and `statement`, assessment `status`, supporting/contradicting
evidence IDs, optional hypothesis/judgment IDs and creation/update timestamps.

Initial kinds are:

- `symptom` — an investigation-scoped description of observed behavior;
- `cause` — an explicitly assessed causal claim;
- `action` — an investigation claim that an action occurred;
- `verification` — an investigation claim about verification evidence.

Assessment is one of `supported`, `contradicted` or `inconclusive`.
`supported` requires supporting evidence recorded as `available`;
`contradicted` requires contradicting evidence recorded as `available`.
Unknown/unavailable references may remain attached to inconclusive findings but
cannot establish an asserted assessment. The same evidence cannot support and
contradict one finding. All evidence, hypothesis and judgment IDs must already
be attached to that Investigation.

Additional fail-closed semantics prevent typed prose from impersonating an
operational authority:

- a supported `action` must include attached `operation` or
  `capability_result` evidence;
- a supported `verification` must include attached `verification` evidence;
- a resolved Investigation does not automatically support any typed finding;
- free-form legacy findings are never promoted automatically;
- changing a typed finding's meaning requires a new finding identity. The update
  operation may reassess status/evidence links but cannot rewrite kind/statement.

A supported cause is still an **Investigation assessment**, not a System Model
fact. A supported action is not execution permission. A supported verification
finding is not the canonical capability verifier result; Operational History
continues to own that result.

Supported typed findings may now be consumed by Local Learning as a **separate
reviewable candidate type** when their available supporting evidence resolves
to retained canonical Operational History. That integration preserves the
stable typed `finding_id` and explicit kind/status; it does not infer support,
promote the finding automatically, or change Investigation authority. Local
Learning acceptance remains a second explicit reference-knowledge review.

Step 16E does not add a new Investigation relationship schema. In particular,
Igor still cannot infer that an arbitrary typed verification “verifies” an
arbitrary typed action. Reference-procedure derivation is permitted only when
accepted action and verification findings from the same Investigation both
resolve to the **same canonical History operation**, and that operation records
successful execution with canonical passed verification. Multi-operation
sequencing and explicit action→verification relations remain future
Investigation-contract work.

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

The original Step 15C source layout had **no investigation store** and created
version 1 on the first valid mutation. Step 16C introduces a deterministic
version-1 to version-2 migration:

- read-only status/list/inspect/export of a v1 store never rewrites it;
- ordinary legacy mutations may continue writing valid v1 records;
- the first **successful typed-finding mutation** upgrades the complete document
  atomically to v2, preserving every original semantic field and adding
  `typed_findings: []` to existing records before applying the requested typed
  finding change;
- failed validation or interrupted atomic replacement retains the original v1
  document;
- new stores created by current code start directly at v2.

There is no interpretation/import of legacy finding strings. Existing history
storage/schema is unchanged. Repeated initialization reuses the local scope.
This service remains the single Investigation authority; there is no dual write.

Export before recovery. Restore validates the complete versioned export, accepts
an empty destination or an identical already-restored document, and rejects a
nonempty different store. Restore continues the same managed installation and
preserves IDs/scope. Restore Operational History's export first when recovering
into a new data destination; investigations cannot invent/rebind installation
identity. Unknown/corrupt versions remain untouched and refuse operations. Both valid v1
and v2 exports restore only into an empty matching-scope destination (or an
identical already-restored document) and preserve their storage version. A
restored v1 document migrates only through the same explicit typed mutation
boundary. Recover a validated export into a fresh private destination; no repair
guessing is provided. Future versions must specify source,
target, validation, idempotency, cutover, verification and recovery explicitly.
A distinct installation starts with fresh identity and no imported investigations.

Known sensitive values and secret-bearing fields are excluded from retention.
Judgment bindings that would require secret redaction are rejected instead of
silently changing their digest. Callers must supply sanitized reference data;
provenance and locators must not contain secret values.

## Bounded interfaces and inspection

`InvestigationService(data_dir).handle(action, fields)` dispatches only a closed
set of data operations: `create`, `add_evidence`, `add_hypothesis`,
`update_hypothesis`, `attach_judgment`, `set_findings`,
`add_typed_finding`, `update_typed_finding`, `set_questions`, `transition`,
`close`, `reopen`, `list`, `status`, `inspect`, `export`, `restore`.
Mutations identify `investigation_id`; each operation validates its own fields.
Python callers may also use the named service methods.

| Operation | Additional fields |
|---|---|
| `create` | `title`, optional `summary`, `source`, `owner`, `provenance`, optional `related_objects`, `related_history` |
| `add_evidence` | `evidence`: typed reference object |
| `add_hypothesis` | `statement`; initial status is `proposed` |
| `update_hypothesis` | `hypothesis_id`, required `status`, optional `supporting_evidence`, `contradicting_evidence`, `judgments`, `assessment`, `confidence` |
| `attach_judgment` | `request`, `record` from the existing Judgment Contract |
| `set_findings` | `findings`: bounded free-form compatibility strings, replacing investigation findings |
| `add_typed_finding` | `kind`, immutable `statement`, `status`; optional supporting/contradicting evidence, hypotheses and judgments |
| `update_typed_finding` | stable `finding_id`, `status`; optional replacement evidence/hypothesis/judgment links; kind/statement are immutable |
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
findings, typed findings, uncertainty and provenance. No special investigation UI/editor exists;
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
remote scopes, relationships/deployments, automatic causal inference, runbook
generation/promotion, automatic acceptance, direct typed-finding projection
that bypasses Local Learning review, and Jet/Laya. Step 15C added
no model routing/selection; the subsequent Step 15D contract owns that explicit
integration. Step 20 owns the separate default interface transition.
