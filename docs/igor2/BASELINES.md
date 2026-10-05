# Step 16 — Explainable Operational Baselines

Status: **Step 16A and bounded Step 16B implemented; Step 16 remains PARTIAL**. See
[LOCAL_LEARNING.md](LOCAL_LEARNING.md) for the reviewed local-learning
contract and [STATUS.md](STATUS.md) for final implementation evidence.

This first Step 16 slice derives explainable local baselines from existing
canonical Operational History. It adds no new durable authority and no learning
database.

## Purpose

The first useful learning question is deliberately small:

> What has normally happened when Igor invoked this exact capability version
> through this provider on this managed installation?

The answer is a read-only projection over retained episodes. It can help future
diagnosis/context and gives later pattern/runbook learning an evidence-bearing
foundation without turning history into desired state or permission.

## Authority boundary

```text
Operational History
        |
        v
read-only baseline projection
        |
        +--> operator inspection
        +--> future bounded context/learning consumers
```

A baseline is reference material only.

It cannot:

- create or change desired state;
- create responsibility;
- approve an operation;
- grant privilege;
- activate automation;
- invoke a capability or verifier;
- refresh the System Model;
- rewrite History;
- persist a learned executable action.

The projection has `authority: reference_only` explicitly.

## Group identity

Samples are grouped by:

- canonical capability ID;
- capability version;
- provider ID;
- provider owner.

This prevents a replacement provider or capability-version change from silently
rewriting the meaning of the old sample set.

The first implementation reads at most the latest 100 History episodes. A
capability filter applies inside that bounded window; it is not an unbounded
historical scan.

## Sample eligibility

Only finalized, non-interrupted terminal episodes are learned from.

Current/in-flight episodes are excluded. Read-time dead-owner projections and
durable interrupted/unknown outcomes do not become normal-behavior samples.

Failed provider results and failed verification remain valid samples because
reliability is part of operational behavior. Their outcome/execution/
verification distributions stay visible rather than being discarded.

Three eligible samples are the initial minimum for `availability=available`.
Smaller groups are returned as `insufficient_history` so the evidence remains
inspectable without pretending it is a meaningful baseline.

## Explainable statistics

The version-1 projection reports:

- sample count;
- success count/fraction;
- outcome distribution;
- execution-status distribution;
- verification-status distribution;
- safety-tier distribution;
- first/last admission timestamps;
- exact source operation IDs;
- episode elapsed time: admission -> terminal;
- provider elapsed time: `running` -> `provider_complete`, when both transitions
  exist.

Episode elapsed time is intentionally not called execution duration because it
can include approval, verification and other lifecycle time. Provider elapsed
time is narrower but still an Igor-observed lifecycle interval, not an external
profiler.

The initial statistics are min/median/max. No opaque model, anomaly score,
percentile threshold or inferred desired state is introduced.

## Headless inspection

```bash
bash igor.sh --baselines status
bash igor.sh --baselines list [LIMIT]
bash igor.sh --baselines capability CAPABILITY_ID [LIMIT]
```

Inspection does not create History storage when none exists and does not load
modules, refresh observers or run providers.

## Persistence

There is **none** in this slice. Baselines are computed only when explicitly queried; there is no background sampler or learning process.

Operational History remains the source authority. Baselines are recomputed from
the bounded retained window. This keeps the first learning layer cheap to
delete/change and avoids a competing store before actual retention/indexing
requirements are known.

If later baseline persistence is justified, it must retain source episode
references/provenance and follow the persistent identity/migration rules in
[PERSISTENT_MEMORY.md](PERSISTENT_MEMORY.md).

## Step 16B boundary

Step 16B adds evidence-backed candidates and explicitly reviewed local
reference artifacts through the separate Local Learning Service. It may use
baseline summaries as explicit supporting references, but a baseline alone
does not establish causality or justify a cause/resolution claim. Candidate
types, grouping and review semantics are defined in
[LOCAL_LEARNING.md](LOCAL_LEARNING.md).

## Later Step 16 work

This slice does not yet implement:

- fact time-series baselines;
- learned health thresholds;
- causal patterns and verified runbook derivation (deferred until evidence
  contracts support those claims);
- knowledge-artifact persistence/export;
- OKF interchange;
- semantic/vector indexing;
- automatic capability promotion.

The next useful extension should be chosen from real retained evidence. A
pattern/runbook candidate should cite History/Investigation evidence and remain
reference-only until explicitly reviewed.
