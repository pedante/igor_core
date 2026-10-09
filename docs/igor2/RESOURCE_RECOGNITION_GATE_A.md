# Resource Recognition Foundation — Gate A discovery and decision proposal

**Status:** the Project Owner confirmed R1 and R2 on 2026-10-10 (D077). **Only A1 implementation is authorized now**. A2/A3 and any public Module API v2 recognizer contribution need separate continuation. This document remains the design record, not proof that runtime recognition exists.

## Goal and authority

Prove one reusable, read-only seam from existing observations or an exact user hint to a **domain-interpreted, ephemeral, evidence-bound candidate**. Candidate selection can feed a domain's existing deterministic inspection; only the separate approved Deployment Service path may adopt responsibility.

Authoritative rules: [ARCHITECTURE.md](ARCHITECTURE.md) (resource-recognition section), accepted decisions in [DECISIONS.md](DECISIONS.md), [MODULE_API.md](MODULE_API.md), [RESOURCE_RECOGNITION.md](RESOURCE_RECOGNITION.md), [ATTACHMENT.md](ATTACHMENT.md), [OPERATOR_INTERFACES.md](OPERATOR_INTERFACES.md) and the five evidence classes in [EXECUTION.md](EXECUTION.md).

## Repository findings (read-only inspection on `igor2`)

- `modules/nextcloud_docker/lib/attachment.py` already implements bounded Docker discovery, exact full-container-ID selection, independent reinspection, incarnation/daemon/image/Compose identity, configuration file stat and frozen topology evidence. It is a read-only **Nextcloud attachment provider**, not a general recognizer.
- `core/lib/deployment_attachment.py` directly loads that v1 package and exposes `core.deployments.discover` and `core.deployments.propose`. The discover route is **Nextcloud-specific**; it must not become a universal discovery implementation by adding more Core technology rules. Existing CHANGE adoption/History and responsibility fences must not move into recognition.
- `core/lib/input_candidates.py` has a bounded ephemeral selector-candidate API for operator inputs, but explicitly **does no host discovery**. Reuse compatible validation/presentation patterns, not its semantic-selector results as proof of domain recognition.
- `core/lib/operator_surface.py` is a read-only metadata projection of existing registries. Its current contribution kinds do not include `recognizer`; a new UI kind or a provider-written UI is not authorized.
- [MODULE_API.md](MODULE_API.md) explicitly defers accepting a new `kind=recognizer` until two different domains demonstrate the minimum contract. Step 19's real isolated Nextcloud application evidence and later `loglevel` writer cutover also remain separate open gates.

## Decision R1: where the first common contract lives

| Choice | Advantages | Costs / risks |
|---|---|---|
| A. Introduce public Module API v2 `recognizer` now | First-class declaration/registration | Freezes an unproved schema and may trigger loader, validator, index and UI migrations across modules |
| **B. Recommended: private stateless Core normalization with reviewed provider adapters** | Proves shared shape with Nextcloud and Samba before a public module kind; preserves existing module activation, attachment and capability authorities | An intentionally temporary adapter must be revisited before general third-party registrations |
| C. Add Samba branches inside existing deployment discover | Small initial patch | Hard-codes domains into Core, couples recognition to adoption and defeats the foundation |

**Owner accepted B (D077).** Keep provider implementations in their domain packages; Core only validates/coordinates. This is a narrow implementation contract, not a new state owner, database, plugin runner, `kind=recognizer` contribution or permanent public API.

## Decision R2: second domain and evidence level

**Owner accepted: Samba shares** as a materially different, non-application resource. For the first slice, accept a trusted explicitly selected configuration source in isolated fixtures and a bounded local read-only adapter. Recognize share section names and only allowlisted nonsecret locator metadata; do not execute or interpret configuration directives, follow recursive includes, enumerate arbitrary files, call management commands or infer external connectivity. Ambiguous/unsupported directives and duplicate names must be visibly unavailable/ambiguous, not guessed as complete truth. Do not add an SMB installer, service setup, write capability or Samba management responsibility.

The Nextcloud provider remains a real reviewed adapter using its already implemented Docker read-only evidence. Existing fixtures prove integration without requiring a live Docker daemon. A **real Nextcloud application gate is still not proven** by these fixtures.

## Proposed *private* v1 candidate/result semantics to demonstrate

The runtime implementer should settle exact field spelling against existing type/validation conventions during discovery and record it before code. The following describes **meaning**, not an accepted JSON schema:

- `domain_kind` (for example `nextcloud.application`, `samba.share`), reviewed `provider_owner/provider_id/provider_version`, and a bounded provider-specific **exact selector**; a display label is never identity.
- Stable source/observer provenance, exact matched native object/incarnation or scoped configuration selector, observation time and explicit freshness/unknown markers. Missing evidence and ambiguity are explicit.
- Candidate result is ephemeral, read-only, bounded and nonsecret; no public value hash of a secret, no commands, no executable recipes, no raw environment/configuration content and no serialized authorization claims.
- Return `ready` with zero/one/many candidates, versus separately reported `unavailable` or `error`. Never choose the first of many. Explicit user hints filter or target inspection but do not establish truth.
- On selection, re-inspect exact evidence and freeze an immutable inspection/proposal using the domain's reviewed path. Stale identity, changed provider activation/version or changed relevant evidence fails closed.
- Recognizers cannot mutate System Model desired state, Configuration, Deployment identity/relationships/responsibility, capability registration or History. Only a later canonical CHANGE can adopt.

Do **not** reuse `candidate_id` as a durable deployment or resource ID; do not persist an inventory or duplicate System Model fact storage. Keep the existing `core.deployments.discover` caller and Nextcloud proposal shape compatible; introduce a new clearly named read-only recognition interface, if necessary, behind the same operator backend. Exact CLI spelling and promotion into Module API v2 are later decisions.

## Proposed implementation decomposition — separate stop points

1. **A1: Pure validation/coordination.** Implement an injected, stateless private candidate/result normalizer with strict envelope validation, active-provider filtering and bounded zero/one/many/unknown cases. Preserve source provenance/freshness. Prove no store writes, network scan, approvals or deployment calls. Stop and report.
2. **A2: Two provider adapters.** Adapt Nextcloud's current read-only output without changing its direct attachment behavior. Add the smallest read-only Samba share provider from the reviewed explicit source. Inject fixtures and verify exact target, unsupported/ambiguous input, disabled owner, stale evidence and secret-free output. Stop and report.
3. **A3: One shared presentation.** Project the normalized candidates consistently into existing read-only CLI/TUI/backend primitives; do not create UI-specific authority or generic settings editor. Prove selected Nextcloud candidate can still enter its existing *frozen proposal* path, while Samba remains view-only. Update state/legacy/acceptance documentation, then stop.

**If either provider requires a different durable or public module contract, stop for a specific owner decision rather than silently adding it.** These are implementation sub-boundaries, not authorization for installation/adoption/Step 19 Boundary 3.

## Required acceptance evidence (no full-suite loop)

1. **Contract:** strict version/field/size validation; nonsecret candidate shape; exact selectors; zero/one/many; no first-match; stale/unknown/error distinct; unknown provider disabled; wrong scope/provenance rejected.
2. **Regression:** `core.deployments.discover/propose/adopt` behavior and explicit approval unchanged; existing v1 Nextcloud and active-owner semantics intact; `input_candidates.py` and operator surface semantics not degraded.
3. **Vertical slice:** both Nextcloud and Samba use the same Core candidate contract; Nextcloud exact selection enters its already reviewed inspection/frozen proposal without performing adoption. Fixtures for Samba's source reader use synthetic bounded configuration and no external dependency.
4. **Inspection:** identical normalized candidate semantics accessible through the shared backend projection to CLI and TUI without secrets or authority confusion.
5. **Migration/recovery:** no persistent migration in this slice; removing/disabling the provider removes its active candidates without changing stored Deployment Service state or reactivating stale proposals; no new persisted records to recover.

**Validation economics:** run new pure/unit tests first, existing `tests/test_deployment_attachment.py`, Nextcloud provider and operator/selector regressions impacted by the diff. Inspect `tests/validate.sh affected --dry-run` before invoking the governed affected selection once against the final candidate. Group test invocations below the active 240-second subprocess ceiling. Reuse valid pre-existing evidence in accordance with the development governor; security tests retain required-fresh behavior. No broad full suite solely because Core changes. Report unverified gates instead of renewing validation loops.

## A1 bounded implementation candidate (2026-10-10)

The first **internal** contract is `core/lib/resource_recognition.py`, with
focused fixture tests in `tests/test_resource_recognition.py`. It has no
entrypoint registration, module discovery, deployment import or state store.

One trusted Core caller explicitly injects a frozen `Recognizer` binding:
owner-stamped provider identity/version, domain kind, currently admitted
active state, and a reviewed read-only reader function. A provider does not
become active because it appears on disk or because model/UI data declares it.
The coordinator neither loads packages nor determines ownership; A2 must bind
this field to the existing real module activation runtime.

The provider's **private, version-1 candidate input** is a closed object:
`candidate_version=1`, `selector`, `matched_objects` (identifiers),
`evidence` (closed `source_kind/source_ref/observed_at` records),
`observed_at`, `expires_at`, `ambiguities`, and `missing_evidence`.
No arbitrary body, configuration values, commands, approval flags or
nested interpretation objects are admitted. Current bounds: 128 candidates,
16 evidence records, 16 matched objects and 16 issue codes per candidate.
All times are timezone-aware. Provider output is copied, validated and sorted
by exact selector; duplicate or foreign hinted selectors fail closed.
`candidate-N` identifies a row only within that result, never a deployment.

Results distinguish `empty`, `ready`, `ambiguous`, `stale`,
`incomplete`, `unavailable` and `error`; disabled/absent providers never
run. Exceptions are projected as value-free failures. The normalization
contract does **not** certify arbitrary text as secret-free: reviewed A2
adapters must only emit allowed nonsecret locators and evidence references.

A1's 20 isolated unit cases pass in 0.04 seconds using a synthetic reader
and controlled UTC time; changed Python files compile. New source/test GitHub
blob identities were compared with the locally exercised bytes. Repository
governed affected checks, remote CI and real provider integration are
**not claimed**; approval and integration review are pending on the A1 PR.
No legacy writer or persistent state was migrated. A2/A3 remain out of scope,
and neither the Nextcloud real-application gate nor the two-domain proof is
closed by A1.

## Exclusions and handoff

Not included: a public `kind=recognizer`, generic module auto-loading, discovery background jobs, network-wide scanning, a persistent candidate database, AI-only identification, application provisioning, implicit adoption, Docker installation, Samba installation/config changes, Step 19 real-application gate or Boundary 3 loglevel writer cutover, secrets migration, Step 20 default TUI cutover, agents or self-healing.

**Gate A approval:** R1 and R2 are confirmed by the Owner under D077. Implement A1 only, publish its focused proof and stop. A2 and A3 are not automatically authorized. Do not mark recognition implemented by publishing or merging this design record.
