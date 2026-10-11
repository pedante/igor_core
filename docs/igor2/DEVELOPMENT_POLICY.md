# Igor 2 development policy

Status: **authoritative Project Owner policy, accepted 2026-10-10 (D078)**.

This is the single development-policy authority for Igor 2. It governs branch
selection and pre-release compatibility obligations alongside
[ARCHITECTURE.md](ARCHITECTURE.md). Architecture, accepted decisions and
[EXECUTION.md](EXECUTION.md) continue to govern ownership, safety and evidence.
Older contradictory development requirements are superseded; historical test
outcomes and implementation records are not rewritten.

## Independent baseline

`igor2` is the sole authoritative development baseline for Igor 2. `master`
is the independent original Igor program, not a compatibility target.

- Inspect the actual local `igor2` tree, branch and working-tree status before
  work. Feature branches use their intended **Igor 2** baseline.
- No merge, cherry-pick, comparison, ancestry check, remote freshness query or
  reconciliation with `master` is a prerequisite for Igor 2 progress.
- Divergence from `master` is not a defect, validation failure or blocker.
- Original Igor may be studied or deliberately reused after review; its changes
  are never automatically inherited.
- This policy does not authorize renaming, deleting, merging, resetting or
  otherwise modifying either branch, or changing remote default-branch settings.

Validation comparison refs identify an Igor 2 candidate and its relevant prior
revision. They select changed-file coverage, not cross-program equivalence.
CI subscriptions for other branches do not impose a reconciliation gate.

## Pre-release contract changes

Igor 2 is unreleased and has no released internal backward-compatibility promise.
Capability contracts, schemas, registries, module interfaces and contribution
formats may be deliberately redesigned. Prefer the architecture intended for
release and migrate all affected internal consumers directly.

An authorized migration must:

1. Name the canonical replacement and the affected callers, frontends, modules,
   fixtures, tests, configuration and retained data.
2. Update implementation, consumers, fixtures and tests together. Version the
   changed contract using its own version axis; do not reinterpret old operation
   records or silently accept a mismatched version pin.
3. Retire superseded internal formats and execution paths once migration is
   complete. Simultaneous obsolete versions, compatibility adapters, duplicate
   capability IDs, parallel registries and frontend executors are not required
   solely to preserve pre-release behavior.
4. Define deliberate data handling, validation, cutover, idempotency,
   interruption/re-entry, verification and recovery for storage/configuration
   changes. Unreleased software can still hold valuable persistent user data.
5. Satisfy all applicable EXECUTION proof classes and document actual results,
   limitations and remaining migration dependencies in STATUS/LEGACY.

Preserve correct foundations where they satisfy the target. Existing code is
evidence and reusable material, not a veto on a better complete migration.
New or revised architecture still needs Owner confirmation before runtime
implementation. A proposal does not supersede today's executable contract.

## Compatibility has distinct meanings

| Constraint | Policy |
|---|---|
| Igor 1 / `master` equivalence | No obligation. |
| Deliberately superseded internal pre-release Igor 2 APIs/formats | Backward compatibility is optional; complete migration is mandatory. |
| Obsolete internal implementations | No mandatory coexistence or automatic deprecation period. A temporary path needs a named consumer/data dependency and retirement condition. |
| Linux distributions, operating environments, software/platform versions | Preserve declared support and test it; do not broaden claims beyond evidence. |
| Module/capability dependencies and provider eligibility | Preserve deterministic validation, availability and ambiguity handling. |
| Explicit supported third-party module contracts | Honor their stated scope or approve/document a deliberate versioned migration; do not confuse them with Igor 1 compatibility. |
| Configuration/data integrity and retained operational records | Preserve deliberate migration/recovery and historical identity/meaning. |
| Security, approval, privilege and privacy invariants | Non-negotiable. |

## Safety and correctness remain mandatory

Preserve authoritative approval and execution, deterministic READ / CHANGE /
DESTROY semantics, exact destructive `YES`, privilege isolation and native
sudo-through-PTY authentication. AI, module prose, collections and frontends
cannot bypass authorization or supply their own success/verification state.

Strict module ownership and lifecycle isolation remain: disabled modules
contribute no executable behavior or active reference data. Configuration and
secret ownership, private runtime/event permissions, private-data protection,
outbound scrubbing and audited secret access remain required. Canonical results
retain execution outcome, output validity, verification, provider identity and
operation identity. Inspection, auditability and deterministic test evidence
must survive migration; no generic undo or unverified completion is promised.

## Tests and completion

Tests prove current accepted Igor 2 contracts. During an authorized contract
migration, replace obsolete assertions with coverage of the intended contract;
do not merely delete coverage or preserve obsolete output by default. Keep
behavioral safety, lifecycle, authorization, privilege, isolation, secrets,
History and execution-verification regressions.

Until a runtime migration occurs, tests for a live old format remain correct.
Record their dependency and update them with their implementation and consumers,
not during a policy-only edit. Reviewed baseline failures are evidence, not a
compatibility promise or permission to weaken behavior.

Use the existing governed [validation procedure](VALIDATION.md). Retain the
five formal [EXECUTION proof classes](EXECUTION.md#completion-model): Contract
proof, Regression proof, Vertical-slice proof, Inspection proof and
Migration/recovery proof. Record scope-based applicability explicitly. Preserve
DISCOVERY entry criteria, Owner decision gates and execution budgets.
Documentation/schema/static checks are documentation evidence, not runtime
validation. Report executed passes/failures, permitted skips, unexecuted checks
and source inspection separately. Editing expectations or prose alone cannot
complete a feature or move its RFC into EXECUTION.

## Policy audit and deferred migrations (2026-10-10)

Inspected local `igor2` at `5b80740`; no runtime behavior was changed by this
policy pass. Tracked docs, project instructions/configuration, CI, validators,
test policies and representative fixtures were searched and classified.

| Finding | Classification and disposition |
|---|---|
| AGENTS intended-`master` baseline; Ownership proposal Boundary B prerequisites; roadmap copy of that gate | Active obsolete requirements: removed/superseded by D078. |
| D021/D060 and Module API/Wave E output-version language | Accepted decisions/current contracts: explicit D078 amendment permits complete internal replacement without indefinite coexistence; current implementations remain described accurately. |
| Dated master ancestry/cherry/comparison and test outcomes in STATUS, LEGACY and reviews | Historical evidence: retained with a superseding-policy reference; not current gates. |
| V1 loader/hooks/actions, menu/hybrid paths, scalar list output and source imports | Temporary migration mechanisms: retain for named current consumers/data until an authorized tested cutover; no perpetual obligation. |
| Distribution/version/dependency metadata, third-party contracts, scoped identities, data recovery and safety fixtures | Legitimate compatibility/correctness constraints: retained. |
| CI branch subscriptions; validator `--base igor2` and local `BASE...HEAD` selection | Coverage/selection mechanisms, not master reconciliation: unchanged. |

The collection proposal's deferred migration includes
`modules/system/contracts/host.json`, `system__service_list`, shared output and
module validators, backend result/event/History projections, CLI/TUI consumers,
selector binding, and their fixtures/tests. In particular,
`tests/modules/test_system_admin_surface.bats` currently checks the scalar
service inventory; `tests/test_capability_runtime.py` and
`tests/test_module_contract.py` enforce today's bounded scalar schema/version
rules. These checks must change together with the accepted runtime migration,
while preserving rejection, identity, privacy and safety coverage.

The proposed extension has one canonical document:
[Collection Results and Operator Interface RFC](COLLECTION_OPERATOR_RFC.md).
It remains DISCOVERY and creates no runtime authorization.
