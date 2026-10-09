# Igor Codex orchestration

This directory contains Igor's project-local Codex policy. Codex loads `.codex/config.toml` for trusted projects, so the policy follows the repository instead of depending on one person's global `~/.codex/config.toml`.

This document is the engineering orchestration lifecycle reference. The root
and role configurations carry its operational rules; [AGENTS.md](../AGENTS.md)
provides repository constraints. These phases govern Codex engineering work,
not Igor runtime state, AI roles or roadmap architecture.

## Task lifecycle

At task start, every phase transition and each handoff, the root states the
current phase, the allowed next action and the evidence still needed to exit.
Keep that state in the task plan/handoff through compaction; no persistent
runtime phase service is required. Small tasks may pass through phases quickly,
but must satisfy the same gates. Audit/decision tasks retain the restrictions
in AGENTS.md; their IMPLEMENTATION phase permits only authorized deliverables.

| Phase | Allowed actions | Exit condition |
|---|---|---|
| `DISCOVERY` | Inspect the active branch and relevant repository evidence; bound scope; define acceptance checks and required validation; prepare any architecture proposal for owner confirmation. No implementation. | Scope, applicable checks and owner decisions are settled. |
| `IMPLEMENTATION` | Implement authorized scope under confirmed architecture; add relevant tests and documentation; work as a single agent unless the Owner explicitly authorizes delegation. | Requested implementation and initial focused checks are ready for integration. |
| `STABILIZATION` | Integrate results, fix concrete in-scope failures, run focused and required regression checks, finish documentation and completion evidence. No new features or speculative improvements. Root owns edits; single agent by default; an explicitly authorized validator is the only permitted delegate. | Implementation, focused tests, required regressions and documentation are complete; all applicable evidence gates are satisfied. |
| `RELEASE_FREEZE` | STOP development. Inspect final git status/diff, confirm agreed validation evidence, stage and commit the scoped result, verify commit/status and report completion. | Scoped change is committed, required evidence is satisfied and completion is reported. |
| `COMPLETE` | Stop. No further autonomous work or next roadmap item. | Terminal for this task; new work needs owner instruction. |

Example status: `Phase: STABILIZATION. Allowed now: one policy-consistency
review. Exit: TOML, links and final diff checks pass; no unresolved scope issue.`

## Release freeze and stopping conditions

When implementation, focused tests, required regression tests and documentation
are complete: **STOP development and enter RELEASE_FREEZE.**

During release freeze:

- no new features;
- no speculative improvements;
- no unrelated refactoring;
- no new tests unless required by a failing regression;
- no reopening architecture decisions.

Do not search for improvements after final validation, request new exploratory
reviews, add optional checks or repeat passing checks without new changes or
failures. Adjacent observations stay deferred; they do not extend this task.

A concrete acceptance failure found in final review or a required regression
allows an explicit return to STABILIZATION for the smallest in-scope correction
and affected validation, then freeze again. New tests during that return are
limited to those required by the failing regression. This exception cannot
authorize new features or architecture. If correcting a failure needs a new
architecture decision or expanded scope, surface the blocker for the owner
before implementation. Missing required tools/evidence also blocks COMPLETE;
report the specific gap without starting later work or claiming success.

## Owner approval for major tasks

New or revised architecture decisions require Project Owner confirmation before
implementation. During DISCOVERY, prepare a reviewable proposal with options,
tradeoffs, repository consequences, scope and a recommendation. Record the
confirmed decision in the applicable design/decision document when the task
calls for it, then implement within that boundary.

Accepted decisions already covered by the owner's task authorization do not
need repeat confirmation. Routine reversible implementation choices inside
that contract remain engineering judgment. Delegates escalate architectural
questions to the root; neither the root nor Lead_Eng may silently introduce a
durable public contract or major workaround. Release freeze never authorizes
reopening a confirmed architecture decision.

## Workspace rules

Work directly in the existing checkout on the active feature branch by default.
Inspect branch and git status first, preserve unrelated changes and assign file
ownership when delegates edit the shared checkout. Do not automatically create
temporary clones or worktrees.

Use isolated copies only for destructive testing, risky migrations or uncertain
experiments. State the isolation reason and return the scoped result to the
active branch for integration and required validation. Permission or tooling
failures are blockers to resolve through the applicable approval mechanism,
not reasons to create a clone workaround.

## Root/orchestrator model is intentionally changeable

`config.toml` deliberately does **not** set the root model or reasoning effort. The Project Owner chooses the orchestrator per task.

In an interactive Codex session, use `/model` to choose the model and reasoning effort for the root/orchestrator. You can therefore use Luna for cheap bounded work, Sol Medium for normal coding, stronger Sol reasoning for difficult engineering, or Astra only when the task really deserves system-level architectural reasoning. CLI/profile selections remain available as normal.

The project instructions ask the root to flag a meaningful model mismatch before it starts substantial work. Example: `Model fit: Sol Medium is sufficient for this task.` This is meant to prevent doing an ordinary task on Astra by accident.

## Development governor

Default development is single agent. Project configuration disables both
multi-agent feature generations and agent availability; retained role files
are inert. Restart Codex after changing configuration. Trusted project config
can be overridden by a human's session/global settings; it is not an admin
security boundary. See the [official configuration](https://learn.chatgpt.com/docs/config-file/config-reference)
and [hook contracts](https://learn.chatgpt.com/docs/hooks).

Use `tests/validate.sh focused|affected|full`. Existing selection, raw logs,
pytest/BATS adapters, baseline classification and required CI gates remain.
Local default ceilings are **900 seconds cumulative validation** and **240
seconds per subprocess**. Existing file timeouts can tighten these ceilings.
A command timeout or total exhaustion stops dispatch, cancels active trees,
leaves pending checks unverified and exits nonzero. Linux `/proc` tracking
supplements process-group termination for children that create new sessions.

`.igor-governor/` is ignored development state, outside production runtime. A
locked ledger serializes governed runs and charges elapsed wall time across
invocations and compaction. A crash reserves the remaining allowance, so later
invocations cannot replenish it. Increasing `--total-timeout` alone does not
renew the ledger. `--dry-run` executes no tests and consumes no allowance.

Exact local result reuse compares the entire tracked/nonignored source tree,
selected plan, baseline, tools, local Python package file metadata, sanitized
environment, platform and `--environment-key`. It over-invalidates rather than
guesses dependencies. Logs/reports must exist and match their hashes. Complete
failures keep their failure exit code; partial, missing-tool, timeout or
malformed evidence cannot be reused as a pass. Alternate Python interpreters
execute freshly. CI executes all selected gates freshly, with 10800-second
total and 1200-second command ceilings matching existing CI/full limits;
shorter file limits still apply. Recognized security suites (safety, privilege, approvals, secrets, scrubbing,
request boundaries, capabilities and transactions) are never reused. Their
unchanged repeats require a justified targeted rerun or Owner renewal; no
cached pass can waive these gates. New security suites must be included in
`requires_fresh_security` when named outside these categories. External fixture/service state is not inferred: change
`--environment-key` when it changes; local reuse is not proof of live host or
service security. Evidence is trusted local state, not a signed attestation.

One unchanged attempt is allowed; exact complete evidence is reused.
`--rerun-reason REASON` permits one additional targeted attempt when evidence
cannot be reused. A correction changes the fingerprint and permits one new
relevant pass. `full` is limited to one attempt per source/environment candidate
even if selection/options differ. Prefer CI for broad regression. Compaction
does not justify another run. On exhaustion **stop and report**.

Only the Owner may explicitly renew a budget from their terminal:

```bash
tests/validate.sh focused --base HEAD --test tests/test_validation_governor.py \
    --new-budget "Owner approved governor correction" --total-timeout 900
```

This records the reason, resets attempt/time allowances and retains evidence.
It cannot convert a failed gate into a pass. Do not delete the ledger or invent
authorization to continue. Budgets control model use; they cannot prevent a
developer deliberately editing local state.

The supplementary `PreToolUse` hook denies delegation tools, recognized direct
broad-suite/lint commands, and model commands that renew a budget or start a
nested supervised session. Route broad validation through the governed runner.
Coverage depends on Codex version/tool paths; hooks cannot parse arbitrary
programs or enforce a complete session deadline. They change no credential,
approval, privilege or sandbox logic.

For an independent complete-session deadline, use noninteractive Codex:

```bash
python3 tools/codex_supervised.py --seconds 1800 -- exec "Implement the bounded task"
```

The Linux supervisor runs outside the model, forces single-agent settings,
acts as a child subreaper, terminates descendants (including detached/double
forked children), and writes `session.log` plus `session.json`. Deadline exit
is 124; unfinished evidence is unverified. Output is logged; use `tail -f` on
the reported log if desired. `codex exec` retains its normal approval/sandbox
settings. The launcher is intentionally noninteractive and enforces wall
time, not token/dollar quotas or sessions launched elsewhere. A human may
start a fresh bounded session, or add
`--new-budget "Owner approved next correction" --validation-seconds 900` to
renew validation before launch. The model may not relaunch itself to escape
the deadline.

Scope discipline, rerun justification and preferring CI remain advisory.
Runner budgets/reuse/attempts, configured single-agent availability and
supervised process lifetime are mechanically enforced.

## Validation and completion criteria

Define required checks in DISCOVERY from the task's affected contracts and
[repository validation rules](../AGENTS.md#validation). Runtime changes need
focused tests and applicable regression coverage; roadmap completion also needs
the proof categories in [EXECUTION.md](../docs/igor2/EXECUTION.md).
Documentation/configuration-only work needs TOML parsing where applicable,
policy consistency, links/references and diff checks. Do not run expensive
unrelated repository regressions for a change with no runtime code.

Report failures, skips and unavailable checks accurately. A pre-existing failure
is not permission to repair unrelated code; record its baseline and impact.
Passing tests alone cannot waive another required gate. A check may be marked
not applicable with a concrete scope reason, never just to reach completion.

### Failure-first STABILIZATION: a bounded decision procedure

When an acceptance check fails, do not launch another broad validation run
as the first response. Inspect the existing `summary.json`, the smallest raw
failure log and the exact test assertion. Create a brief failure ledger:

1. **Classify:** actual product/security violation; contract-mismatched test
   expectation; fixture/environment/runner failure; reviewed baseline; or
   unresolved. Record the required observable invariant, not merely the
   assertion's current wording.
2. **Fix the demonstrated cause only.** Correct an over-specific assertion
   when a generic safe error satisfies the accepted contract, but retain an
   independent sentinel/side-effect test. Never conceal or downgrade a real
   credential leak, forbidden access, failed recovery or missing History record.
3. **Target the invalidated proof.** Run the previously failing node or small
   fixture first, followed by affected neighboring cases. Reuse complete
   previously passing evidence only under the governor's exact
   source/environment equivalence rules; security checks still follow the
   governor's required-fresh policy. Do not reschedule unrelated tests to
   obtain a larger pass count.
4. **One closing gate.** Once fixes are integrated, run the required affected
   selection against the final candidate, plus any distinct mandatory
   security/vertical-slice/recovery proof not covered by that selection.
   Full-repository validation is a separate explicit release/CI requirement,
   not an automatic loop after every STABILIZATION fix. If broad checks are
   required, prefer CI within its established governor instead of burning
   through the smaller local budget.
5. **Budget before execution.** Check prior group durations and
   `--dry-run` selection. The local 240-second subprocess ceiling overrides
   longer generic group defaults; break work into runner-supported bounded
   groups without changing that ceiling or silently dropping selected tests.
   If equivalent partitioning is unavailable, report the specific unverified
   gate and stop. Budget exhaustion is not a reason to repeat already valid
   proof, reset ledgers, spawn more agents or ask for routine renewal.

Maintain an evidence ledger recording candidate fingerprint, covered contract,
pass/fail/skip, provenance and invalidation reason. Stop once all mandatory
evidence has been established; do not open new exploratory validation after
RELEASE_FREEZE. These economics do not reduce the five proof classes in
`EXECUTION.md` or the secret and authorization acceptance requirements.

Before completion, the root must:

1. Inspect git status and the final diff, including staged changes, to verify
   task scope and preserve unrelated work.
2. Run required validation on the final content; record results and resolve
   concrete in-scope failures. Revalidate affected checks if content changes.
3. Enter RELEASE_FREEZE once implementation, tests and documentation are done;
   stage only task files and commit on the active feature branch.
4. Verify the commit and git status, then report COMPLETE with commit ID,
   changed behavior/policy, validation results and any scoped limitations.
5. Stop. Do not continue searching for improvements or begin the next step.

If commit or required validation is blocked, report the current phase, exact
blocker and remaining action; do not label the task COMPLETE. Existing owner
instructions take precedence, including an explicit request not to commit.

## Step 15B workflow lessons

The [Step 15B evidence](../docs/igor2/STATUS.md#step-15b-operational-history--implemented-validation-gate)
distinguishes completed implementation/behavioral proofs from an open tooling
and remote-baseline gate. It also records a temporary checkout used because
original Git metadata was read-only. These are evidence for explicit closure
gates and workspace decisions; they do not prove or authorize subsequent work.

This lifecycle makes the future default direct feature-branch work, bounded
verification and a clear stop at freeze/completion. It does not close Step 15B's
recorded validation gate or authorize Decision/Judgment, 15UI, 15C, model routing
or investigations. Igor runtime and migration state remain unchanged.

## Compatibility

These files use current Codex project configuration, custom agent roles, and Multi-Agent V2 settings. Keep Codex reasonably current. If Codex reports an unknown setting after an upgrade/downgrade, validate the project configuration against that installed release before removing behavior.

The lifecycle and phase-dependent worker cap are instruction policy, not a new
TOML scheduler or runtime enforcement mechanism. Configuration keys remain
unchanged; guidance uses the existing instruction fields described in the
[official Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).
