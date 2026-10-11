# Igor 2 RFC v2 — Collection Results and Operator Interface

**Status:** DISCOVERY — proposed amendment, not approved or implemented  
**Date:** 2026-10-10  
**Baseline to verify:** local `igor2` branch at `5b80740`  
**Scope:** Step 18 output contracts + Step 20 operator interfaces; **not** a rewrite of Waves C–F  
**Supersedes for this feature:** `igor2_capability_tui_rfc.md` (first draft)

## 0. Source and verification boundary

This revision incorporates a source-inspection report supplied for the **local** `igor2` tree. Those findings are the working baseline, **not independently verified runtime behavior**. The earlier RFC inspected a different, remote/default-branch baseline and therefore understated what Igor already has. The report says no files changed or committed, and no runtime tests or live service operations ran. All statements below about local implementation must be confirmed against the local tree before code changes.

**Reported implemented baseline**

- `modules/system/contracts/host.json` around line 675: capability **`system.service.list` version 2**, currently returning scalar properties `count`, a **bounded `services` string**, and `source`.
- Same file around line 743: **`system.service.status`** and **`system.service.restart`**, with selectors, preconditions and restart verification.
- `docs/igor2/OPERATOR_SURFACE.md`: operator explorer generated from existing registries; `:system`, `:sys`, and a generic candidate chooser with provider ambiguity.
- Deterministic `invoke` path reaches the existing dispatcher without a model call; CLI already supports **`capability run`**.
- D049 establishes **opaque scope identity** together with existing object IDs.
- Existing authoritative result envelope retains execution, output validity, verification, provider and operation identity.
- Local `master` reportedly contains **12 commits absent from `igor2` ancestry**; semantic equivalence has not been verified.

**Do not** interpret this as permission to replace existing contracts, registries, resolver, dispatcher, selectors, approval state machine, result envelope, or module lifecycle.

## 1. Decision sought

Add a **typed, bounded collection output shape** under Igor's **existing authoritative capability result envelope**, then teach the **existing operator explorer/TUI** to present, select, inspect, and refresh rows. A row uses D049's existing scope identity and object ID representation. Frontends remain projections of backend state; module providers remain owners of domain operations; Igor Core retains authority for validation, routing, policy, approval, privilege, and verification.

This is an **output-contract and operator-interface extension**, not a new resource runtime. No Wave C architectural reset; no new module loader, command registry, generic handler adapter, transport, permission system, or GUI framework.

### Non-goals for the initial slice

No editing of swap, changing configuration, generic form generator, remote GUI, bulk operations, new plan engine, live service restart, or persistence of results into desired-state memory. A controlled restart proof is a **later independent gate** reusing the already existing restart capability.

## 2. Decisions that must be made in DISCOVERY

### D1 — Backward-compatible output strategy (blocking)

The current list v2 output contract admits only scalar properties; nested resource collections do not validate against it. Preserve the existing `count`/`services`/`source` behavior for existing consumers. Choose **one** strategy after inspecting the real validator and call sites:

**Preferred if version dispatch/negotiation and consumer migration are demonstrably safe:** authorize a **new versioned output contract** for `system.service.list`, with explicit old/new consumer routing and migration. Define exactly how both shapes coexist and what an unupgraded caller receives. Do **not** assume that bumping a declared version automatically permits two simultaneous response shapes or that old consumers can parse nested values.

**Fallback if version coexistence is not supported without invasive work:** add a **separately named collection capability** (final ID chosen to fit the canonical registry), leaving `system.service.list` v2 untouched. This enlarges the public capability surface but avoids breaking stable consumers. Document relationship/aliasing and eventual consolidation; do not register a shadow duplicate provider.

A draft change is blocked until there is (1) a call-site inventory, (2) an explicit compatibility decision, (3) schema validation evidence, and (4) a migration or coexistence test.

### D2 — Row identity (blocking)

Reuse the **D049 scoped-reference model**: opaque scope identity + existing object identifier/selector. The collection must carry the same scope/object semantics accepted by `system.service.status` and other existing capability selectors. **No new host ID, `local:system:...` convention, or TUI-derived identity.** Table index, display name, row position, and raw pasted text are not an action target. Re-resolve scope, object, active provider, and preconditions at invocation time.

### D3 — Result envelope and presentation (blocking)

Preserve the current canonical envelope and its execution, output-validation, verification, operation, and provider information. Add an optional, versioned typed collection payload **inside the existing result data** (exact field names to be selected from actual Step 18 schemas). Do not invent a parallel authoritative `igor.result/v1` envelope or a second outcome model. Frontend events should project this same result, not independently reconstruct success or authority.

Illustrative structure only (NOT an implementable canonical schema):

```text
EXISTING_AUTHORITATIVE_RESULT_ENVELOPE {
  ... existing operation / provider / execution / validity / verification ...
  output: {
    kind: resource_collection,
    collection_schema_version: <version>,
    row_type: systemd.service,
    rows: [
      {scope_ref: <D049 opaque scope>, object_id: <existing ID>, fields: {...}}
    ],
    page: {...}
  }
}
```

No row may contain an executable shell template or approval authority; any display/action hints are non-authoritative metadata.

### D4 — Operator invocation (blocking)

Extend the **existing** explorer and registry-backed candidate chooser. Retain `:system`, `:sys`, provider ambiguity and previously supported interactions. A complete literal/pasted colon command must reach backend command resolution rather than being sent to an LLM or interpreted as a shell string. Define the interaction with `:`-opens-explorer so typing, pasting, autocompleting and selecting a matching capability converge on the **same canonical operation ID, selected provider, validated arguments and dispatcher invocation**. Do not add a TUI-specific implementation for `system.service.list`.

### D5 — Boundedness and pagination consistency (blocking)

Enforce **both row-count and byte-count** bounds (including serialized output and emitted event payloads), with a defined failure/truncation contract; no silently cut JSON. Establish an explicit consistency policy:

- **Option A, preferred for small initial collections:** one bounded, private, immutable snapshot per traversal (or one bounded page containing all results); opaque cursor/offset refers to that snapshot, with expiry and ownership checks. Refresh starts a new snapshot.
- **Option B, if no snapshot can be retained:** deterministically order by stable scoped object identity and detect inventory changes between pages; invalidate/restart pagination rather than silently mixing pages. Label any remaining best-effort semantics.

Do not promise stable inventory if systemd changes while pages are fetched. Selections retain scope+object reference and must be revalidated before further operations. Define terminal width truncation separately from backend byte bounds. Keep the design economical for low-memory hosts.

### D6 — Privacy and event projection (blocking)

Results may include private machine identifiers. Keep existing owner-only runtime/event protections; size-limit and sanitize terminal-control output before rendering; do not automatically send raw collections into AI provider context, logs, or exports. Apply the established outbound scrub boundary whenever crossing to an external model. Frontend event records carry correlation to canonical operations; avoid duplicating outcome authority and avoid one event per row. If handles are introduced for larger payloads, validate ownership, path confinement, expiry and cleanup; do not make handles a prerequisite for the first bounded proof unless actual limits require them.

## 3. Minimal implementation shape

### Igor Core / Step 18

1. Inventory current output-schema validators, consumers of the `services` string, result-envelope serializer, version dispatch and operation identity.
2. Amend an existing result-schema extension point to support a bounded typed collection (only after D1 approval). Define field types, optional/required values, row-level validation, error behavior and deterministic serialization.
3. Preserve scalar capability outputs and old result-envelope validation unchanged for non-collection capabilities.
4. Keep canonical dispatch, provider selection, module-state checks, approval, privilege, and verification exactly where they are today.
5. Ensure explicit errors for invalid collection structure, stale/expired page, unknown scoped reference, disabled provider and oversized result.

### System provider

1. Reuse existing `system.service.list` and `system.service.status` where contract compatibility allows; do not reimplement restart.
2. Adapt discovery output into typed rows with D049 scoped object references, state, labels and data provenance. Decide from existing behavior whether the inventory covers loaded services, installed unit files, or another subset; label it honestly.
3. Make `status` the detail action: selected list row passes its existing selector/reference through the canonical invocation path. Refresh simply re-invokes the collection capability.
4. Keep the existing v2 scalar output available according to D1.

### Operator surface / Step 20

1. Extend the existing explorer with a generic collection view: focus, arrow/PageUp/PageDown navigation, search/filter, Enter → details (`status`), explicit refresh and Esc/back.
2. The same generic view renders a second **synthetic, unrelated provider** without new systemd-specific rendering code.
3. Make typed/pasted colon invocations and explorer selections resolve through the same **backend** route; no model calls for deterministic direct invocation.
4. Present source, scoped identity where useful, result freshness, validation errors, and empty/unavailable states without implying the data is durable machine truth.
5. Preserve existing TUI accessibility on small terminals, current pending approvals, sudo-through-PTY semantics, color conventions and the session event projection.

## 4. Deliberately bounded proof sequence

**Gate 0 — Baseline reconciliation (DISCOVERY).** Inspect `igor2@5b80740` plus the 12 differing `master` commits. Determine whether any changes relevant to contracts, explorer, results or tests are semantically equivalent; avoid blind cherry-picks or treating branch difference as automatically missing functionality. Use merge-base, ancestry and focused diffs. Record exact baseline SHA/dirty status and current relevant tests.

**Gate 1 — Contract approval (DISCOVERY).** Resolve D1–D6, specifically v2 output compatibility, canonical result envelope insertion point, D049 row references, payload limits, and pagination consistency. Amend Step 18 / Step 20 documentation (and the RFC) before code. No code implementation until the contracts are settled.

**Gate 2 — Backend read-only proof (EXECUTION).** A supported list/collection invocation returns a schema-valid bounded collection via the authoritative result envelope, while old consumers still pass. `system.service.status` takes the selected D049 reference. Test empty, too-large, invalid and changed-inventory cases with mocks/fixtures.

**Gate 3 — Existing explorer proof (EXECUTION).** Existing explorer renders list → select → status/details → back → refresh. Complete colon commands, pasted forms, and explorer choice use the same backend invocation. No model call, no parallel palette/registry, no direct `systemctl` in TUI.

**Gate 4 — Extensibility/lifecycle proof (EXECUTION).** Another synthetic provider with a different row type uses the identical renderer; disabling a provider removes contributions and blocks stale selections. Preserve provider ambiguity and correct selector routing.

**Gate 5 — Optional, separately approved mutation proof (later).** Reuse existing `system.service.restart` and its approval/sudo/verification contract in mocked integration tests. Not a condition for completion of the **read-only collection** milestone. Any subsequent live integration test must be expressly authorized, bounded to a harmless service and out of the routine test path.

## 5. Required exit evidence

Do not advance from DISCOVERY until decisions D1–D6 and the branch reconciliation are recorded. For the read-only EXECUTION milestone, retain evidence in the existing project style for:

1. **Schema + compatibility:** old `system.service.list` v2 consumers; typed schema acceptance/rejection; serialization/bytes/rows; migration or new-ID rationale.
2. **Lifecycle isolation:** enabled/disabled/unavailable owner, stale selection rejection, provider ambiguity and deterministic routing.
3. **Identical frontend invocation:** typed colon, pasted colon, explorer selection and CLI `capability run` resolve identically without a model; canonical operation IDs and result envelopes preserved.
4. **Generic rendering:** same collection viewer for system services and an unrelated synthetic provider; details/refresh/back/empty/error/small-terminal scenarios.
5. **Privacy and safety:** bounded private result/event data, no terminal-control injection, no leakage to outbound model context, untrusted row fields cannot confer execution permission.
6. **Inherited EXECUTION proof classes:** locate the **five formal EXECUTION proof classes** in the actual local Igor roadmap/status/test conventions; enumerate and satisfy them explicitly in the implementation report. They were mentioned in the source-inspection response but not defined there, so this RFC does **not** guess their names or silently substitute another list.

Also preserve all existing baseline/behavioral tests, including legacy approval and native sudo-through-PTY behavior, and record which tests actually ran. Mock-only results are not live-machine validation evidence.

## 6. Compatibility and ownership invariants

- **Module owns domain implementation; Core owns dispatch/authorization/result validation; TUI owns only presentation.**
- **No second registry, loader, result envelope, command executor, or permission boundary.**
- **Opaque D049 scope + existing object IDs** are the only reference identity for rows.
- **Scalar outputs remain valid** and are not silently broken by nested collections.
- **Presentation hints are data, not authorization.** Selectors are revalidated by the backend.
- **No default restart, sudo, configuration edit or destructive action** in the collection proof.
- **Observed listings are transient observations**, not desired state or durable machine memory.
- **Versioned schemas and frontends are independent:** GUI/AI/TUI consume the same operation and result semantics, with future transport options outside this slice.

## 7. Roadmap placement

- **Wave C:** preserve completed module/capability/dispatcher work; no reset.
- **Step 18:** approved collection-output contract and compatible canonical result validation.
- **Step 20:** existing operator explorer adds generic collection navigation and identical literal/palette invocation.
- **Later existing roadmap steps:** structured configuration edits/plans/verification and machine-memory interpretation can consume collections without changing the dispatcher or frontend authority model. Do not rewrite Waves D–F to accommodate this amendment.

## 8. Guidance to the implementing agent

1. Start from the local checkout and verify the reported baseline; do **not** trust this RFC's inferred paths/field names over code.
2. Produce a **contract decision and consumer impact assessment** first. Report an explicit recommendation between version coexistence and separate capability ID.
3. Present the precise proposed schema amendment, D049 reference use, cursor semantics, maximum rows/bytes and colon-resolution behavior.
4. Check the 12 `master`-only commits for relevant divergence before modifying any overlapping code.
5. **Remain in DISCOVERY until the contract and scope are agreed.** The first EXECUTION increment is read-only and ends before restart.
6. Preserve and report the five actual EXECUTION proof classes from local process documentation, plus the feature-specific acceptance evidence above.

**Summary:** Existing Igor functionality is the foundation. Extend its scalar result contract compatibly into typed collections, project those results into its current explorer, and prove the generic path with read-only resources before extending mutation behavior.
