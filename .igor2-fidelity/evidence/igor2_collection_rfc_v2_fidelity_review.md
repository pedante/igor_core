# Igor 2 — Original RFC v2 fidelity comparison

**Review date:** 2026-10-11  
**Scope:** Source-text comparison only. No repository writes, local Igor test runs, runtime validation or live service operations.  
**Original source:** `igor2_collection_operator_rfc_v2.md` — 170 lines, 17,440 bytes, SHA-256 `e5ea31b14c8e0f3f9776485002742242442f7378b120d69a8052ee8c11a2dd35`.  
**Integrated candidate:** supplied `COLLECTION_OPERATOR_RFC.md` text (`Pasted text.txt`) — 523 lines, 37,100 bytes, SHA-256 `4ac8c9a916fe748aaab2b2a8e1313beeaf06ae83d7f62d53df8fdbdc668e1286`.  

## Verdict

**PASS — the integrated candidate materially covers original v2's architectural and acceptance requirements, after applying the later Owner policy decisions D078 and D079.** No significant missing source requirement was identified. This is evidence to resolve the *source-fidelity* DISCOVERY blocker. It is not evidence of local repository file identity, project-wide DISCOVERY exit, running tests, source-code implementation or hardware performance. The local owner/agent should record the source hashes and run its mandated checks before formally changing the phase.

## Requirement mapping

| Original v2 requirement | Integrated candidate | Finding |
|---|---|---|
| §0 reported Igor 2 baseline and no independent runtime validation | `Inspected baseline`; source-inspection disclaimer | Covered; no runtime claims |
| §1 extend current capability runtime, result envelope and explorer; READ first | `Purpose and boundaries`, Step 18/20 sections | Covered |
| D1 scalar-output compatibility decision and consumer inventory | `Step 18`, `Q022`; D078/D079 | Superseded intentionally: same ID, capability v3/output schema v2, complete internal migration. Do not restore old coexistence obligation |
| D2 existing D049 scoped resource references and selection revalidation | `Step 18`, `Q022`, `Q024`, binding rules | Covered and specified more precisely |
| D3 existing authoritative operation/result envelope and event projection | `Authoritative result envelope`, event criteria | Covered; collection in existing `result` data slot |
| D4 literal/pasted colon commands, explorer, provider ambiguity, deterministic dispatcher | `Step 20`, focused criteria | Covered; same canonical resolution and provider semantics |
| D5 rows/bytes limits, snapshot or changed-inventory detection | `Bounds`, `Q023`, global budget and error semantics | Covered; finite frozen snapshot chosen |
| D6 private data, scrub boundary, terminal-control/size handling, event correlation | `Bounds, freshness, pagination and privacy`, focused criteria | Covered |
| §3 Core validation, provider result adapter, details, generic explorer | `Step 18`, `Step 20`, declaration grammar, proof sequence | Covered |
| §4 phased proof: read-only System, generic synthetic provider, optional later restart | `Purpose`, `Acceptance`, `Focused criteria` | Covered; restart explicitly later |
| §5 evidence and five formally defined EXECUTION proof classes | `Acceptance and bounded implementation sequence` | Covered; five classes enumerated |
| §6 module/Core/TUI ownership and no parallel registry | `Purpose`, `Step 18`, `Step 20` | Covered |
| §7 roadmap Step 18 / 20; no Wave C–F restructuring | Header, Step 18/20, `Acceptance` | Covered |
| §8 verify local state and keep DISCOVERY before approved execution | `Inspected baseline`, `DISCOVERY entry/exit assessment` | Covered, subject to recording this comparison |
| Original Gate 0: reconcile 12 master-only commits | D078 explicitly removes that gate | Correctly superseded |

## Notes that do not block fidelity

1. **Operation identity:** The original wording about “the same canonical operation ID” across typed and explorer invocations should not imply reuse of the *same unique operation instance ID* for two separate executions. The integrated wording — identical invocation path/request/provider semantics with per-invocation canonical operation identity — is the sound interpretation.
2. **Color conventions:** The original asked to preserve existing TUI color conventions. The integrated candidate requires that meaning not depend on color but does not explicitly restate preservation of existing role colors. This is a minor presentation-regression criterion, not a source-fidelity blocker. Optional wording: “Retain existing semantic color roles when available; all actions/states remain distinguishable without color.”
3. **Thirty-second TTL and RSS ceilings:** Both are explicit **provisional implementation acceptance hypotheses**, not verified performance. Keep actual human-paced TTL tests and constrained-hardware measurements in EXECUTION; revise only with Owner approval if evidence warrants.
4. **Inventory ceiling:** The proposed 1,024-row/512-KiB frozen-inventory limit intentionally fails when exceeded rather than silently omitting rows. This is acceptable as a first-slice fail-closed rule, not necessarily a permanent production ergonomics decision.
5. **Local file provenance:** This review confirms the actual original v2 source file in this conversation and the candidate text pasted here. It does not prove that the Codex local checkout has exactly that candidate content. Compare hashes or content in the local checkout before recording a formal project exit.

## Minimal local follow-up

1. Make `igor2_collection_operator_rfc_v2.md` available as a local source file in the Codex checkout (not just a chat attachment); verify its 170 lines and SHA-256 above.
2. Confirm that the repository's `docs/igor2/COLLECTION_OPERATOR_RFC.md` matches the candidate, or re-run the short mapping above if it has changed.
3. Add a dated source-fidelity comparison record in the existing RFC/STATUS location, removing the “v2 source unavailable” blocker statement and explicitly noting D078/D079 supersessions. Do not rewrite already accepted decisions.
4. Run mandated documentation/contract checks; distinguish them from runtime test evidence.
5. If the formal DISCOVERY exit conditions hold, mark the source comparison resolved and enter only the approved first READ EXECUTION slice, not restart/configuration mutation.
