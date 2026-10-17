# Igor Codex development workflow

[AGENTS](../AGENTS.md) owns repository guidance;
[DEVELOPMENT_POLICY](../docs/igor2/DEVELOPMENT_POLICY.md) owns compatibility,
data and safety. This file owns the engineering lifecycle. Config links policy.

## Task lifecycle

State phase, next action and exit evidence at start, transitions and handoffs.
Carry candidate, scope, evidence, budget and blockers through compaction in one
concise record; STATUS links it when needed. No separate document per small task.

| Phase | Allowed work | Exit evidence |
|---|---|---|
| DISCOVERY | Inspect relevant source; bound scope/checks; propose major changes. No implementation. | Scope and required Owner decisions settled. |
| IMPLEMENTATION | Implement authorized scope under confirmed architecture, with relevant tests/docs. | Result ready for integration. |
| STABILIZATION | Fix concrete in-scope failures, run required checks, finish docs. No speculative work. | Applicable evidence complete. |
| RELEASE_FREEZE | Stop development; final status/diff/evidence review, scoped commit and verification. | Committed result and completion report. |
| COMPLETE | Stop; no automatic next milestone. | Terminal for this task. |

Concrete acceptance failure permits returning to STABILIZATION for the smallest
fix/affected check, then freezing again. No optional searches/tests after final
validation. Missing proof or blocked commit prevents COMPLETE; report the gap.

## Owner decisions and workspace

Major revised architecture needs a recommendation, options, tradeoffs and repository
consequences for confirmation before runtime implementation. Accepted decisions
within authorized work need no repeat vote; routine reversible choices remain
engineering judgment. Audits implement only explicitly authorized deliverables.

Use the active checkout; inspect branch/status, preserve unrelated work and review
staged/final diffs. Isolate only risky migrations, destructive tests or uncertain
experiments for a stated reason; integrate/validate on the active branch.
Permission failures do not justify clones. Honor instructions such as no commit.

## Agent and model policy

One capable Owner-selected model normally completes the task. No automatic
hierarchy or retained roles. Delegation needs explicit session authorization and
a concrete benefit: independent risky review or separable investigation. Root
owns synthesis/validation; self-review is not independent review. Do not duplicate
work for a stronger model. Mention fit only for a material cost/quality mismatch.

Config disables delegation and leaves root model/effort unset. Restart Codex to
load changed configuration; injected session instructions still apply. Project
settings are not an OS security boundary. See the
[official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).

## Development governor

Use `tests/validate.sh focused|affected|full`; plan with `--dry-run` and prior
durations. `--only-group` selects exact focused IDs; excluded groups remain
unverified, not waived. [VALIDATION](../docs/igor2/VALIDATION.md) owns runner usage;
[EXECUTION](../docs/igor2/EXECUTION.md) owns five proof classes. Use one ledger.

Limits stay **900 seconds cumulative local validation, 240 per subprocess**, or
the existing Owner-granted allowance; shorter file limits apply. CI retains
10800/1200-second ceilings. Locked `.igor-governor/` state accounts across runs;
exhaustion cancels process trees, stops dispatch and leaves pending proof unverified.
Crash reservation, attempts and evidence hashes remain unchanged.

Reuse exact complete evidence under runner source/environment/tool rules. Security
suites and CI execute freshly under existing rules. Change `--environment-key` for
external fixture changes. One relevant pass per candidate; corrections invalidate
affected proof. Inspect failures first; targeted reruns use the same allowance.
Broad regression once when required, preferably CI. Compaction alone is no rerun reason.

Only the Owner authorizes `--new-budget REASON` or another supervised session.
Never reset/delete the ledger or invent authorization. Stop/report on exhaustion.
Owner-launched sessions use `tools/codex_supervised.py`; deadline, descendant
termination and evidence remain unchanged. It limits wall time, not token/dollar quotas.

The project command-text PreToolUse filter is removed: it misclassified read-only
searches without enforcing budgets. Sandbox/approval, runner and supervisor remain.
No project-wide hook-disable flag is set; unrelated approved hooks remain user choice.

## Validation scope and finalization

Define checks in DISCOVERY. Docs/config need parsing, policy/references and diff
review; runtime tasks need focused behavior/affected regressions. Preserve
secret/approval/privilege/History/recovery/real-consumer proof where applicable.
Obsolete headings/status wording are not product contracts.

Classify failures as product/security defect, over-specific test, environment,
reviewed baseline or unknown; fix the cause. Never downgrade safety failures.
Report failures/skips/unavailable checks. Once proof is complete, freeze, commit,
verify commit/status, report and stop.
