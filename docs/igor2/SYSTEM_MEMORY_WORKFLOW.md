# System memory warning configuration proof

Step 18 Boundary 3 implements the owner-approved [D062](DECISIONS.md) slice.
This is Linux host health policy in the current Igor process, not OS memory
allocation or service deployment. System already owns the memory observer,
health check, typed refresh capability and packaged host knowledge, making it
a real small consumer with deterministic verification.

## Operator path

In an active System chat session, `memory-warning 220` proposes a 220 MiB
warning boundary. The canonical command registry exposes the same command to
existing interaction consumers. Normal mode approval applies to the desired
commit and module application; readback remains READ. The command reports
verified completion only when all stages succeed.

Inspect desired state with
`bash igor.sh --configuration inspect system.memory.warning_threshold_mib`.
A fresh CLI process cannot prove a different running session's consumption.
Runtime `igor_module_inspect system` exposes that session's separate consumption
snapshot. The existing operator projection discovers the schema and capability
metadata, and generic 15UI record rendering can display structured inspection.
This slice adds no custom module UI or generic setting editor.

## Ownership and state

The System package declares `system.memory.warning_threshold_mib`, an integer
with default 150 MiB and range 81–4096 MiB. The critical boundary is independently
80 MiB. The ineffective legacy `SYSTEM_RAM_WARN_MB` is not imported or consulted.
Core owns validation, desired persistence, revision/state-token preconditions,
provenance and recovery. Modules never write the configuration store directly.

Desired state is what the operator requested. Resolved state is the desired
value or package default. Runtime state is the value consumed by this process's
memory-health handler. These are separate inspection results. Configuration
application creates no System Model fact: `memory.available_bytes` continues
to come only from the existing kernel observer.

## Capability contracts

`core.configuration.system_memory_warning.set` is a Core-owned CHANGE for
the desired value, expected revision and frozen state token.
`system.memory.warning.apply` is the System-owned typed CHANGE for the exact
committed value/revision/state. `system.memory.warning.readback` is the typed
System-owned READ. Core retains capability resolution, input/output validation,
approval, privilege and deterministic verification. All use existing Operational
History episodes rather than a second workflow log.

Readback reports the consumed MiB value, desired revision/state token consumed,
current process identity and `system.host.memory.health.consumer` provenance.
The Core verifier compares readback to approved intent and current desired
state; inspection does not infer successful application merely from a commit.

## Approved lifecycle

1. User intent supplies one threshold, through the existing deterministic
   command/capability path.
2. Core validates the module schema and the expected desired revision/state.
3. Core evaluates normal CHANGE policy and approval before committing desired.
4. The System CHANGE capability applies the exact committed value/revision to
   this process, under a separate normal approval decision.
5. Independent READ readback uses the module health consumer. Core compares it
   with the approved application intent and reports verification separately
   from provider completion.
6. Operational History records requested inputs, authority, provider execution,
   result and verification. The explicit READ produces its own evidence record.
7. Structured owning-service inspection exposes desired/resolved and process
   consumption/provenance; existing 15UI rendering consumes the records.

The isolated module handler returns typed application intent. Core validates
it and consumes it in the session process. A narrowly reviewed dispatcher
exception avoids command-substitution child state for this exact capability;
it still executes the same canonical prepared operation, approvals, privilege
and History path. Other module handlers retain their existing adapter semantics.

No approval, privilege or execution policy is replaced. The reviewed local
System package is trusted executable code; Module API v2 is not a sandbox.

## Failure and recovery

Invalid or stale proposals fail before desired writes. Declined changes produce
no corresponding effect. A successful desired commit followed by failed module
application leaves the new desired revision visible alongside the old runtime
consumer. A subsequent active System process consumes the already-authorized
resolved desired value at startup, including when an earlier explicit apply
failed or was declined. Startup is read-only consumption, creates no success
episode and does not claim verified runtime application. Provider success with failed readback is an unverified change, never
application success. Readback failure remains distinct from execution failure.

Recovery is explicit: submit the prior threshold (or the 150 MiB default)
through the same approved commit/apply/readback path. This creates new revisions
and History; it does not erase the failed episode or promise generic undo.
There is no automatic rollback. Disabling System prevents its runtime workflow
while retained Core-owned desired records remain inspectable when the valid
package schema is present. Complete removal/detach and schema-retention across
package deletion remain outside this proof.

## Limits

The proof changes only one System health setting. Application/readback evidence
is scoped to the current Igor process, not all running sessions or managed
machines. Consumption is tied to Step 17's global configuration revision and
frozen state token: a later Core configuration commit can require fresh
application/readback evidence even when this threshold value is unchanged. No background reconciliation, automatic retry, generic settings UI,
AI decision, application migration, marketplace, sandbox/signing, broad detach,
Step 19 or Step 20 is introduced. [STATUS.md](STATUS.md) records the final
contract, regression, vertical-slice, inspection and recovery evidence.
