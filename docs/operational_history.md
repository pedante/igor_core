# Operational History

Operational History records what happened at Igor's canonical capability
boundary. Its versioned episodes are reference records: reading or recovering
one cannot approve an operation, grant privilege, activate automation or
invoke a provider. The accepted identity and ownership rules are
[D048–D054](igor2/DECISIONS.md) and
[Persistent Memory](igor2/PERSISTENT_MEMORY.md).

## Ownership and record contract

The history service owns episodes, transitions and retained verification
evidence. Callers use service operations and versioned records; storage tables
and paths are private implementation details. The System Model continues to
own current-state projections; automation owns configured eligibility and
schedule claims; chat sessions own conversation transcripts.

An episode retains an Igor-generated operation/attempt identity, correlation,
request/interface provenance, local scope, canonical capability/version,
selected provider with owner/source provenance, safe frozen inputs, scoped
affected objects, safety, approval and privilege results, preconditions,
execution, verification, final outcome, declared recovery semantics and
timestamps. Existing stable automation references are retained where available.
Handlers, commands, package paths and display labels are not durable identity.

The version-1 record groups those fields as follows:

| Record fields | Meaning |
|---|---|
| `schema_version`, `operation_id`, `correlation_id` | Versioned episode and stable attempt/correlation identity. |
| `provenance`, `references` | Actor/interface/request and existing automation/claim/slot, event causation or plan references; none grants authority. |
| `scope_id`, `capability`, `provider`, `affected_objects` | Explicit execution scope, canonical ID/version, provider/owner/source contract and scoped ObjectRefs. |
| `inputs`, `inputs_redacted` | Frozen non-secret inputs; redaction prevents reconstruction/reconciliation from an incomplete value. |
| `safety_tier`, `approval`, `privilege`, `precondition_status` | Trusted runtime decisions recorded as historical metadata. |
| `execution_status`, `verification`, `outcome`, `recovery` | Separate provider result, retained deterministic evidence/reconciliation, final canonical outcome and declared recovery semantics. |
| `lifecycle`, `timestamps`, `transitions` | Admission, authority, running, provider completion, terminal/interruption and reconciliation times. |

Igor's local scope is opaque identity, independent of hostname, address and
installation path. Restoring the same installation preserves that identity;
cloning a distinct managed installation must create a fresh identity. Deleting
history does not authorize reuse of any operation ID. Missing/pruned references
remain unavailable.

## Execution and interruption

The preimplementation audit found one existing execution lifecycle:

| Boundary | Existing owner and behavior |
|---|---|
| Prepared | `igor_capability_prepare` resolves active provider, validates/freezes inputs, privilege argv and deterministic preconditions. Preparation/plan inspection alone does not mean execution was requested. |
| Approval | `ai_execute_tool` in `safety.sh` applies Guide/Assist/Executive and exact DESTROY confirmation to that frozen proposal. |
| Privilege | The same dispatcher authenticates through the existing native sudo/PTY broker after approval; failure returns nonexecution. |
| Executing | `igor_capability_execute` re-resolves the approved digest and preconditions, then invokes exact privileged argv or the v2 handler adapter. |
| Provider complete | Provider exit/envelope determines execution success; it does not prove the postcondition. |
| Verification | `_igor_capability_verify` supplies deterministic evidence and a separate verification status. |
| Terminal | Execution/nonexecution helpers commit one canonical result, then project Step 13 completion. Before 15B, these helpers generated the operation ID only at terminal time. |

History attaches directly to capability execution. The existing dispatcher,
approval broker, privilege broker and verifier remain the execution authority.
Step 13 `capability.completed` is a separate transient projection after the
canonical terminal result, with no replay or restart guarantee.

An admitted episode exists before approval and possible provider effects.
Approval and privilege outcomes are recorded as metadata; authentication
transcripts and credentials are excluded. A durable running transition is
committed immediately before invoking the provider. Provider execution and
deterministic verification are separate transitions. The terminal record keeps
the canonical result, including denial, provider failure and
`unverified_change`.

Restart never repeats a recorded attempt. An unfinished prepared attempt means
the provider did not start; an abandoned running attempt means an external
effect is unknown. Recovery can append deterministic reconciliation evidence
where the current registered capability/version/provider and safe inputs
still match. It queries the existing verifier without invoking the provider
or authenticating. A passing current postcondition cannot prove that the
interrupted provider completed; execution uncertainty remains explicit.
Unavailable verification requires an explicit operator recovery decision.

Inspection is read-only. It can explain interrupted/unknown status without
updating the record, probing the host, running a check or authenticating.
Before explicit recovery, an interruption timestamp in that view means the
time Igor detected a dead owner; it does not claim the exact time of the crash.
Recovery is a separate explicit operation that durably records that detection.

## Headless inspection

```bash
bash igor.sh --history status
bash igor.sh --history recent 20
bash igor.sh --history inspect <operation-id>
bash igor.sh --history correlation <correlation-id>
```

These commands return JSON and work without the TUI. `recent` accepts a limit
from 1 to 100; `inspect` returns one complete episode. The record exposes
capability/version/provider, scoped affected objects, approval, privilege,
execution, verification/evidence, outcome, provenance and interruption status.
An absent store reports `not_created`; inspection does not create one.

## Private persistence and recovery

The first backend is SQLite: atomic transactions fit pre-effect admission and
transition recording, concurrent capability processes, indexed inspection and
restart recovery. A whole-file JSON replacement would rewrite a growing
history on every transition; the automation registry's bounded intent store
has a different workload. SQLite is provided by Python's standard library and
does not become a public Module API or subsystem authority beyond history.

Storage uses owner-only directories/files and refuses symbolic-link storage
targets. Malformed or unsupported persistent versions fail closed and retain
the original bytes. A persistence failure before provider invocation prevents
execution. A failure after a possible effect cannot rewrite the canonical
result; the incomplete durable attempt remains inspectable as uncertainty.

Export/recovery uses a versioned service document, not SQL or copied private
tables. Recovery validates the entire document before cutover. Reset/deletion
is explicit, independent of configuration, automation, current facts, secrets
and chat. Private layout versioning is separate from public episode/export
versioning. Initial creation is version 1; no historical data migration or fake
version transition is implied. A future transition must provide validation,
idempotency, recovery, verification and one cutover under
[Migration](igor2/MIGRATION.md).

```bash
umask 077
bash igor.sh --history export > history-export.json
bash igor.sh --history recover
bash igor.sh --history reset YES
bash igor.sh --history restore - < history-export.json
```

`recover [operation-id]` records abandoned attempts and performs only supported
matching verification queries. `restore` is an explicit continuation of the
same managed installation into an empty destination; it preserves scope and
operation IDs and supports idempotent re-entry. It never overwrites a nonempty
different store or transfers a live process claim. Unfinished imported attempts
become interrupted/unknown, or never-started when only admitted. A distinct
managed installation starts with a new empty store and new scope.

Export before reset if retained records are needed. Reset refuses live attempts,
preserves the installation scope and removes retained episodes; new operations
get fresh IDs. There is no automatic pruning in version 1. A corrupt/unsupported
store is retained and refuses writes: preserve it for diagnosis and restore a
validated export into a fresh private data destination using `IGOR_DATA_DIR`.
History cannot reconstruct data that was never exported or durably committed.

## Compatibility cutover

- The bounded AI tool audit remains a diagnostic compatibility projection with
  canonical operation references. `--ai last` retains its existing behavior;
  its partial traces are not imported as complete operational episodes.
- Canonical capabilities use Operational History directly. The command-oriented
  recovery journal remains a legacy source for raw/v1 actions, Diagnose,
  recovery and backup callers; their existing rollback and UI remain available.
  Stored command text never becomes a history replay or generic undo contract.
- Backup manifests and archives remain recovery artifacts with their existing
  restore and retention semantics. History does not own their content.
- Chat `history` and `replay` remain session/postmortem views. Igor does not
  reconstruct missing operational records from those transcripts.

Passwords, API keys, sudo credentials, authentication transcripts and raw
environment blocks are excluded. Known sensitive values and bounded evidence
are scrubbed before storage/export. Secret references and configured/use status
may be retained; secret values are not hashed for retention.
The final scrub applies to retained content and preserves Igor-generated
operation/scope IDs and closed result meanings, even when a configured secret
coincidentally resembles a UUID substring or a protocol word.

## Investigation reference consumer (Step 15C)

The separate [investigation service](igor2/INVESTIGATIONS.md) references scoped
episode/result/verification identities without copying operational records. Its
explicit creation path uses `OperationalHistory.ensure_scope()` to reuse or
allocate installation identity without an episode, recovery or execution.
Read-only inspection never allocates identity. History schema and authority
remain unchanged. Investigation findings cannot override outcomes/verification.

## Bounded scope

This service supplies durable canonical operational meaning and headless
inspection. Investigations, Decision/Judgment, TUI consolidation, context/model
routing, learning, deployments, remote execution, resumable workflows and
unattended CHANGE remain separate future steps.
No Configuration Service expansion, Nextcloud decomposition, named cheap-model
architecture, baselines, Self-Healing v2 or 15UI scrolling/control-panel work is
included.

## Architectural review

1. `_igor_capability_publish_result` is the single terminal history hand-off for
   canonical execution and nonexecution results. Admission and transition
   adapters attach to that same existing capability lifecycle.
2. The dispatcher durably admits an operation ID before approval/authentication
   and compatibility backups. The executor binds the attempt to the frozen
   proposal and commits running before provider invocation.
3. A dead owner's unfinished running attempt is displayed as
   `interrupted_unknown`. Explicit recovery records interruption and can append
   matching verifier evidence; it never retries the provider.
4. History/evidence cannot change approval, privilege or execution authority.
   Current registration, validated proposal, approval digest and the existing
   privilege broker still decide execution independently.
5. Step 13 remains session-local, transient and best effort. History writes
   directly at execution/result boundaries.
6. The System Model remains current-state projection. Retained history evidence
   cannot refresh or rehydrate an observed fact into known/current state.
7. AI audit is a compatibility projection/reference; the recovery journal is a
   legacy noncanonical source. Canonical journal duplication is suppressed.
8. The backend can change behind the service operations/versioned episode
   contract. Callers do not query tables or construct private store paths.
9. `--history` supplies JSON inspection without the TUI and without loading
   providers for read-only queries.
10. Step 15B's bounded implementation and behavioral proofs are complete;
    [STATUS.md](igor2/STATUS.md) keeps the unavailable lint/remote checks visible
    as an open final validation gate. Close that gate before the separate
    provider-neutral Decision/Judgment Contract; no part of it, 15UI or 15C is
    implemented here.
