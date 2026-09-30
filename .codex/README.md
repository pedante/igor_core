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
| `IMPLEMENTATION` | Implement authorized scope under confirmed architecture; add relevant tests and documentation; use bounded delegates where useful. | Requested implementation and initial focused checks are ready for integration. |
| `STABILIZATION` | Integrate results, fix concrete in-scope failures, run focused and required regression checks, finish documentation and completion evidence. No new features or speculative improvements. Root owns edits; at most one delegated validation worker. | Implementation, focused tests, required regressions and documentation are complete; all applicable evidence gates are satisfied. |
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

## Agent hierarchy

```text
Project Owner
    |
    v
Root / orchestrator (chosen per task)
    |\
    | +--> Luna helpers (default: Medium)
    |      search, tests, builds, reproduction, docs, mechanical work
    |
    +----> Lead_Eng (Sol 6.1 XHigh)
            difficult engineering, architecture-sensitive implementation,
            hard debugging, cross-cutting integration
                |
                +--> Luna helpers (bounded support work)
```

`Lead_Eng` is a named Codex role declared in `config.toml` and implemented by
`Lead_Eng.config.toml`. Ordinary Luna helpers may not recursively delegate.
`Lead_Eng` may delegate bounded helper work during DISCOVERY and IMPLEMENTATION.

## Delegation policy

Delegate when independent expertise is useful, separate context improves
quality, or verification is valuable. Do not create parallel workers merely
because they are available. Keep short, tightly coupled or sequential work
with its current owner; serial delegation is valid.

Every assignment includes current phase, scope/file ownership, allowed actions,
required evidence and a stopping condition. Tell workers they share the
checkout, must preserve others' edits and must report adjacent issues instead
of acting on them. The root communicates phase changes and finishes or stops
discovery/implementation workers before STABILIZATION.

During STABILIZATION and RELEASE_FREEZE, allow **at most one active delegated
worker across the entire task tree**, solely for validation. The root owns
integration and fixes. If Lead_Eng is that validator, it may neither edit nor
spawn helpers. Release-freeze validation confirms only agreed final evidence;
it cannot become another investigation or open-ended review. Once assigned
checks finish, workers report results and stop. Root owns final commits and the
completion report unless explicitly delegated.

The root remains accountable for scope, accepted contracts, integrating results
and reviewing final evidence. Trust well-evidenced routine findings; recheck
only when impact, surprises, weak evidence or contradictions warrant it.

## Cost discipline

The design is intentionally asymmetric: cheap agents consume disposable exploration/test context; stronger models keep their context for work where continuity and judgment matter. Multi-agent is not automatically cheaper if it is used unnecessarily, so the instructions explicitly avoid duplicate checks and manufactured parallelism.

The configured Multi-Agent V2 concurrency ceiling remains four. It is available
capacity, not a worker target; the phase limits above are stricter. Long
`wait_agent` timeouts let agents finish without routine polling. A wait returns
early when the agent completes.

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
