# Step 16B — Evidence-Backed Local Learning

Status: **implemented; broader repository release gate non-green**. See [STATUS.md](STATUS.md)
for the recorded checks and outstanding gate.

Step 16B adds one Core-owned `LocalLearningService` for deterministic candidate
derivation, read-only inspection, explicit review, and durable local reference
artifacts. It builds on Step 16A baselines, Operational History, Investigations,
and the existing Context Engine. Candidate derivation is on demand; there is
no background learner, model dependency, or automatic acceptance.

## Authority and source flow

```text
Operational History ─┐
Investigations ───────┼──> derived candidate ──> exact reviewed snapshot
Step 16A baselines ──┘                                  |
                                              accepted reference knowledge
```

The service owns only local learning records and review lifecycle. It references
canonical source records by their scoped IDs and does not copy History episodes
or Investigation records as a second authority. A baseline can summarize
repeated behavior; it does not establish why the behavior occurred. No causal
claim is derived from correlation.

System Model, Configuration, Deployment, Operational History, Investigations,
Local Learning, Context, and execution policy retain separate meanings. A
learning artifact cannot create machine facts, desired values, responsibility,
approval, privilege, executable capability, automation policy, or module code.
All content remains reference-only, including command-like text.

## Versioned learning record

The service exposes versioned structured records suitable for later Markdown
with structured metadata/front matter. The record contract includes:

- stable artifact and candidate identities, schema/derivation version, learning
  type, lifecycle status, owner and applicable scope/object references;
- the exact reviewed statement/content and applicability;
- canonical History operation and Investigation references, explicit source
  provenance, evidence counts, and source availability at review;
- capability ID/version, provider and owner when applicable;
- creation, derivation and review metadata, including actor/interface where
  supplied by the operator boundary;
- an evidence/candidate revision used for review concurrency.

It preserves uncertainty and makes missing source records visible. References
identify evidence; the learning store is not a replacement archive for canonical
History or Investigation content. Secret values, sudo/authentication input,
credentials, and unredacted sensitive output are excluded. Unknown or unsafe
evidence fields fail closed or are omitted with an inspectable reason.

The closed version-1 candidate uses `igor.local_learning.candidate`, a scoped
`lc-` identity, `candidate_revision`, `learning_type`, `owner: core`,
`applicability_owners`, `statement`, `uncertainty`, `related_objects`,
`capability`, `provider`, `compatibility`, `outcome`, `evidence`, `counts`,
and `provenance`. Investigation candidates have null capability/provider/outcome
and preserve each source compatibility entry separately. Content and evidence
are `reference_only`. A SHA-256 revision binds the complete deterministic
candidate, including source digests and derivation/query metadata; it proves
content identity, not factual correctness or cryptographic source authenticity.

Reviewed `igor.local_learning.artifact` records have a fresh opaque `learn-`
identity, the immutable candidate, initial review actor/interface/reason/time,
status, explicit transition reviews and creation/update timestamps. A supersede
transition preserves the original review and candidate. Review fields are
operator-supplied attribution, not authentication or execution permission.

## Candidate derivation

Candidate discovery is deterministic, bounded, and read-only. It performs no
provider/capability invocation, observer refresh, verification, History write,
Investigation mutation, or desired-state change. Counts and evidence ordering
are deterministic; source references must resolve and validate against the
owning APIs.

History retrieval defaults to the latest 100 episodes (allowed 1–100), with
capability filtering inside that window. The service separately retrieves at
most 20 resolved Investigations and resolves at most 256 distinct operation IDs
including the recent window. Candidate output is limited by the requested
limit; unavailable sources, insufficient samples, overflow and already-reviewed
revisions have explicit omission reasons. Discovery is not an exhaustive scan.

The learning types are:

### `recurring_outcome`

At least three eligible finalized History episodes must agree on canonical
capability ID and version, provider ID and owner, exact applicable scope/object
set, terminal outcome, execution status, and verification status. Different
capability versions, providers/owners, scopes, or outcome-quality classes are
never combined. Failed outcomes remain inspectable. In-flight, interrupted,
unknown/dead-owner projections, and otherwise unfinished episodes are excluded
from the repeated terminal group. The resulting statement describes repeated
behavior only.

### `investigation_finding`

A resolved Investigation may yield a candidate for a finding it explicitly
attributes and supports. The candidate retains the Investigation and eligible
canonical History references. Investigation resolution does not by itself
prove a typed cause, action, successful resolution procedure, or verification;
the candidate states only what the available finding supports. Missing,
unavailable, or ineligible references do not become fabricated evidence.

### `typed_investigation_finding`

A resolved version-2 Investigation may yield a distinct candidate for an
explicit **supported** typed `symptom`, `cause`, `action` or
`verification` finding. Local Learning does not infer the type or support
state. It consumes the typed Investigation assessment exactly as attributed.

Eligibility is conservative: the finding must have retained, available
supporting evidence that resolves to usable canonical Operational History.
System-fact/file/judgment-only support can remain valid Investigation knowledge
but does not become this Local Learning candidate type. The candidate freezes
only the semantic source projection used for review: the stable `finding_id`,
typed finding record, its referenced supporting evidence metadata, related
objects, unresolved questions and Investigation resolution status. Unrelated
Investigation edits therefore do not become accidental learning evidence.

Candidate identity is based on scope + Investigation ID + stable typed
`finding_id`, not list position. Typed derivation uses derivation version 2;
existing recurring/free-form derivation remains version 1 so already-reviewed
artifacts retain their exact validation and identity. Reopening the Investigation
or changing the typed finding/support changes or removes the current candidate
and stale review is refused.

A typed `cause` candidate preserves an explicit Investigation causal
assessment; it does **not** infer a cross-incident causal rule. A typed
`action` does not authorize repeating that action. A typed `verification`
does not replace canonical verifier/History truth. All still require explicit
Local Learning review before entering Context.

### `cross_incident_pattern`

Step 16D adds the first reusable cross-incident pattern without introducing
semantic inference. The initial pattern kind is `symptom_cause`.

Eligibility requires at least **three distinct resolved Investigations**. Each
incident must already have an accepted, still-current Local Learning artifact
for one supported typed symptom and one supported typed cause. The source
artifacts must match exactly on:

- symptom statement text;
- cause statement text;
- related-object scope;
- capability/provider compatibility.

This exact-match rule is intentionally conservative. Similar wording is not
merged automatically and no model/embedding/fuzzy matcher participates in
derivation.

The pattern candidate references the six-or-more exact reviewed Local Learning
artifacts plus their retained canonical History evidence. Its structured
`pattern` records the symptom, cause and distinct-Investigation count.
Candidate identity is based on the semantic pattern key, not the source
artifact IDs; adding a fourth compatible incident keeps the candidate identity
but changes its revision and requires a fresh review.

A reviewed pattern means only:

> across these compatible reviewed incidents, the same supported symptom/cause
> pair recurred.

It does **not** mean that the symptom always has that cause. It is not machine
truth, automatic diagnosis, remediation authority, a procedure or a runbook.
Superseding a source incident artifact removes it from current derivation and
makes stale pattern review fail; accepted historical pattern snapshots remain
immutable and their source status stays inspectable.

Baselines may provide an explicit summary/source alongside these records, but
do not independently qualify as causal evidence. Cross-incident **exact-match** symptom/cause pattern derivation is implemented
under D066. Semantic-equivalence grouping and verified reference-procedure/
runbook derivation remain deferred. Repeated patterns do not themselves justify
a reusable procedure.

## Review and persistence

Discovered candidates are derived and are not individually persisted. On an
explicit operator review, the service stores a bounded private versioned JSON
snapshot containing the exact candidate revision, evidence references,
applicability, resulting content, provenance, and review disposition. Canonical
History and Investigation records are not duplicated. The persisted artifact
remains inspectable when source records are later pruned or unavailable; source
availability is reported separately from the immutable reviewed snapshot.

Review uses the candidate revision/state token and compare-and-swap semantics.
If evidence or derivation changes before review, stale acceptance/rejection is
refused and the operator must inspect the newly derived candidate. Additional
evidence creates a new candidate/review; it never silently rewrites accepted
content. Accepted snapshots retain the content and evidence identity that the
operator saw.

Lifecycle transitions are:

```text
candidate -> accepted | rejected | superseded
accepted  -> superseded
```

Rejected and superseded are terminal. Acceptance means “accepted as reference
knowledge”; it confers no execution authority. New evidence does not mutate an
existing accepted artifact. Superseding requires an explicit review action with
actor/interface and reason; this slice has no automatic replacement link.

The private backend is bounded and versioned, follows Investigation persistence
conventions for private permissions, locking, validated atomic updates,
export/recovery and schema rejection, and lives outside installed module
directories. Reset/delete is explicit and scoped to Local Learning; it does not
reset History or Investigations and does not require module reinstall. Module
or owner inactivity cannot erase reviewed artifacts or provenance. It can make
an artifact ineligible for active Context retrieval while leaving it available
for inspection.

## Inspection and Context

The backend and `bash igor.sh --learning ...` bridge provide headless status,
candidate listing/detail, reviewed-artifact listing/detail, evidence
provenance, and lifecycle/review state. Inspection and derivation are read-only
with respect to source authorities. Review and explicit reset/delete are the
only Local Learning mutations in this slice.

Only accepted artifacts may enter Context. Retrieval is explicit, bounded,
deterministic and scope-relevant; it carries the stored provenance and source
availability, and applies existing sensitivity filtering and last-mile
redaction. Inactive owners are excluded according to owner/scope eligibility,
but their reviewed artifacts remain inspectable. Candidates, rejected and
superseded artifacts are never supplied as current knowledge. Context remains
reference data and cannot authorize an operation.

Context resolves only explicit `learn-` IDs with the matching scope through
`--context select` or the existing session Context request. Every applicability
owner must be active (Core remains eligible). The item uses the existing
`local_learning` kind and `reference` authority class and includes the candidate
revision, frozen evidence and current evidence availability. Pruned or changed
sources do not rewrite the reviewed statement; missing evidence remains visible
as historical uncertainty. No automatic corpus retrieval is added.

## Headless operations and recovery

```bash
bash igor.sh --learning status
bash igor.sh --learning candidates
bash igor.sh --learning candidates '{"limit":50,"capability_id":"system.host.memory.refresh"}'
bash igor.sh --learning candidate lc-CANDIDATE_ID
bash igor.sh --learning list '{"status":"accepted"}'
bash igor.sh --learning inspect learn-ARTIFACT_ID
bash igor.sh --learning evidence_status learn-ARTIFACT_ID
```

`review` accepts strict JSON (or `-` for stdin) containing `candidate_id`,
`candidate_revision`, `status`, `expected_revision`, `expected_state`, `actor`,
`interface` and `reason`, plus optional `limit`/`capability_id` matching the
derivation query. Obtain revision/state from `status` or the candidate envelope.
The service rederives source content and refuses stale or fabricated references;
caller-supplied candidate content cannot replace it. `candidate` is discovery
detail; after review the durable `inspect` interface explains that exact revision.
Cross-service reads are bounded source snapshots, not a transaction spanning
History, Investigations and Learning. Review comparison binds the snapshot read
during derivation; subsequent source changes are separately inspectable.

`supersede` requires `learning_id`, the same CAS fields and review attribution.
`delete` requires `learning_id` and CAS fields; `reset` requires CAS fields and
removes reviewed records while preserving scope. Reset rotates the epoch and
invalidates old tokens. Artifact IDs are fresh and never recycled. Deleting a
disposition permits a fresh explicit review of the currently derived evidence.

The private store is limited to 256 artifacts, 256 KiB per record and 8 MiB per
document; the directory/file require 0700/0600 and owner/symlink checks. Source
layout is no Local Learning store; the first valid review creates version 1.
There is no migration from legacy notes or source records and no dual authority.
Unsupported/corrupt versions remain untouched and refuse writes. Source loss
does not block frozen inspection/export; mutations require matching retained
installation identity.

`export` is read-only. Explicit `restore` receives `export`, `expected_revision`
and `expected_state`, validates the entire versioned document and accepts only
an empty or identical destination. Restore History scope first for installation
continuation; recovering learning does not recover source records. Re-entry is
idempotent and fresh restore state invalidates earlier mutation tokens. A new
installation cannot silently rebind these artifacts to its distinct scope.
Exports retain reviewed references even when sources have been pruned; validation
does not certify unavailable evidence or turn recovery into new evidence discovery.

Legacy `.pattern` files and session notes are compatibility/reference paths.
This slice neither imports them nor dual-writes to them. A future explicit
migration/import contract must define eligibility, provenance and recovery
before those paths can be retired.

## Deferred work

Portable Knowledge Artifact import/export, full OKF support, semantic/vector
search, embeddings, knowledge graphs, causal inference, verified runbook
derivation, learning models, automatic promotion, executable playbooks,
capability generation, autonomous remediation, and TUI work remain separate
roadmap items. Markdown/front-matter compatibility is a representation seam,
not a runtime dependency.

Step 16A operational baselines remain a distinct `reference_only` projection
over bounded History. They answer what normally happened; Step 16B reviewable
learning records preserve evidence-backed reusable statements. Neither changes
machine truth, desired state, responsibility or permission.
