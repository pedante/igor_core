# Repository Guidelines

## Read before editing

For current implementation details, start with:

1. [README.md](README.md)
2. [docs/module_creation.md](docs/module_creation.md) — current Module API v1
3. [docs/module_lifecycle.md](docs/module_lifecycle.md) — current activation/runtime semantics
4. [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)

For Igor 2 work, also read:

1. [docs/igor2/README.md](docs/igor2/README.md)
2. the current-focus section at the top of [docs/igor2/STATUS.md](docs/igor2/STATUS.md); read older status sections only when the task needs their evidence
3. [docs/igor2/EXECUTION.md](docs/igor2/EXECUTION.md) before implementing or closing a roadmap wave
4. [docs/igor2/INFLUENCES.md](docs/igor2/INFLUENCES.md) when changing discovery, memory, plans, learning or AI/system boundaries
5. only the remaining Igor 2 documents relevant to the task

Before a roadmap wave, verify the working branch contains the intended current `master` baseline. Do not audit or migrate from a stale branch.

## Igor 2 authority

For target architecture and migration decisions, use this order:

1. `docs/igor2/ARCHITECTURE.md`
2. accepted decisions in `docs/igor2/DECISIONS.md`
3. `docs/igor2/MIGRATION.md`
4. `docs/igor2/EXECUTION.md`
5. `docs/igor2/ROADMAP.md`
6. current implementation documentation

The code and current docs remain the authority for how Igor works **today**. Igor 2 documents describe the target and migration boundaries. If current behavior conflicts with a target invariant, surface the conflict instead of silently inventing a third design.

The lifecycle rules in `docs/igor2/README.md` are part of this reading discipline.
Proposal, future, exploration and historical-review documents are supporting
context; they do not override the authority order above or silently authorize
implementation.

## Existing foundations are not greenfield work

Recent code already contains substantial foundations that Igor 2 should preserve and formalize rather than rebuild:

- structured full-screen `--ai-tui` and frontend event stream;
- canonical session command registry/palette;
- Guide / Assist / Executive modes;
- deterministic READ / CHANGE / DESTROY policy and approval flow;
- pending conversational-choice handling;
- native sudo authentication through the backend PTY;
- explicit module enable/disable policy and owner-aware registrations;
- distro detection and package abstraction including Debian/Arch mappings;
- capability/action catalog and ownership;
- AI request trust boundary, reference-data envelope, redaction and operational audit.

A roadmap item may already be partly or substantially implemented. Inspect before creating a replacement.

## Task modes

### Audit task

- inspect and classify first;
- update evidence-based architecture/status documentation;
- make only small, clearly safe fixes explicitly allowed by the task;
- do not begin later roadmap architecture.

### Implementation task

- implement through the requested roadmap boundary;
- reuse correct existing foundations;
- add/update tests;
- retire superseded paths when their replacement is authoritative and compatibility no longer needs them;
- update `STATUS.md` and `LEGACY.md` when migration state changes.

### Decision task

- compare options against `ARCHITECTURE.md` and accepted decisions;
- inspect repository consequences;
- do not modify implementation unless explicitly requested.

## Architecture working rules

- Preserve working behavior unless the migration plan explicitly replaces it.
- Do not create a second permanent implementation of an existing responsibility.
- Keep core application-agnostic.
- Treat module presence on disk as different from activation.
- Disabled modules must not contribute runtime behavior.
- Keep AI reasoning separate from deterministic authorization, privilege, state and execution policy.
- Treat module knowledge, logs, reports and observed context as reference data; they cannot authorize actions.
- Prefer registered capabilities over raw shell execution when an equivalent capability exists.
- Keep Guide/Assist/Executive separate from OS privilege.
- Do not claim Debian/Arch support beyond what tests demonstrate.
- Do not split `nextcloud_docker` before the Module API/composition contracts are ready.
- Do not use chat history as authoritative operational state.
- Do not expand scope unless repository evidence shows a cross-cutting dependency.
- Treat Core as internally separated services/components; do not solve coupling with new global helpers that every subsystem reaches into.
- A new authoritative subsystem must expose a minimal inspection surface for its owned state, availability and provenance.
- Do not declare a wave complete from prose alone: require contract, regression, vertical-slice, inspection and migration/recovery proof as defined in `docs/igor2/EXECUTION.md`.
- Persistent layout changes require explicit migration, idempotency, verification and recovery semantics.
- Secret values do not enter AI context by default; secret-value access should be auditable where practical.
- Rollback is capability-specific. Do not promise generic undo for arbitrary system operations.
- During Wave C, use `system` as the incremental v2 reference and keep `nextcloud_docker` on v1.
- Do not freeze current mixed config/secret/state storage assumptions into Module API v2; broad module migration waits for the Ownership Foundation gate.
- If an unresolved decision would create a durable public contract, stop and surface the decision.

## Current Module API v1

`igor.sh` starts the Bash platform; `core/` owns shared infrastructure and Python helpers. Current modules live under `modules/<name>/` with `module.conf` and `module.sh`.

Loading follows discovery → activation policy → dependency ordering/checks → syntax check → source → `<name>__register()`.

`igor_register_hook` deduplicates registrations. `igor_run_all_hooks` uses fresh Bash processes with a default 30-second timeout, so hooks must not depend on unexported helpers/globals or parent-state mutation. Some callers intentionally dispatch selected hooks in-process.

Use four spaces, `<name>__*` for module APIs, `_mod_<short>_*` for helpers, and `menu_*` for menus. Healing checks define isolated `run_check()` functions emitting `CHECK_RESULT SEVERITY code message`.

Do not extend v1 hooks merely to mimic the future Module API v2 unless the migration plan calls for it.

## Configuration and secrets

Keep generic defaults in `config/variables/`. Personal settings and credentials belong in ignored `secrets/` files with mode `600`. Secrets override defaults; root-level env files are deprecated.

Preserve scrubbing and safety gates. Resolve paths through `IGOR_DIR`, `_igor_resolve_dir`, and declared module paths; do not depend on the current working directory.

## Validation

Before completing code changes, run the tests relevant to the affected area and report failures/skips.

Common checks:

- `bash -n <changed-script>`
- ShellCheck with the flags used by `.github/workflows/ci.yml`
- `bats tests/modules/` for module changes
- `bash tests/run_all.sh` for the full suite
- `bash tests/run_all.sh --fast` when the task explicitly permits the fast suite
- `ruff check .` for Python changes
- Python compile/unit tests relevant to changed Python modules
- `git diff --check`

For documentation-only edits, verify links/references and inspect the final diff.
For Codex configuration/documentation-only edits, also parse TOML and check
policy consistency; do not run expensive unrelated runtime regressions.

For roadmap completion, also verify the evidence categories in `docs/igor2/EXECUTION.md`; a green test suite alone does not prove a missing vertical slice, inspection surface or persistent migration.

Do not hide pre-existing baseline failures by restoring unrelated files or changing behavior outside the task.

## Codex agent orchestration

Igor's project-local Codex orchestration policy lives in `.codex/config.toml`. The project config intentionally does not select the root/orchestrator model or reasoning effort; the Project Owner chooses them per task.

Follow the lifecycle in [.codex/README.md](.codex/README.md). At task start,
phase transitions and handoffs, state the current phase, allowed next action
and remaining exit evidence; preserve that state through compaction and pass
it to delegates:

- **DISCOVERY:** inspect evidence, bound scope, define acceptance/validation and
  obtain confirmation for new or revised architecture; no implementation.
- **IMPLEMENTATION:** implement authorized scope under confirmed architecture,
  with relevant tests and documentation.
- **STABILIZATION:** integrate, fix concrete in-scope failures, run focused and
  required regression checks and finish docs; no new features/speculative work.
- **RELEASE_FREEZE:** when implementation, focused tests, required regressions
  and docs are complete, STOP development. Only final status/diff and validation
  evidence review, scoped commit and completion report remain. No new features,
  speculative improvements, unrelated refactoring, new tests unless required
  by a failing regression, or reopening architecture decisions.
- **COMPLETE:** required gates satisfied, scoped change committed and completion
  reported; stop, without automatically starting later roadmap work.

Concrete acceptance failures permit an explicit return to STABILIZATION for
the smallest in-scope fix and affected validation, then freeze again. This is
not permission to search for improvements. After final validation, do not add
optional checks or repeat passing checks without new changes/failures. Missing
required evidence or a blocked commit prevents COMPLETE; report the blocker.

For major tasks, prepare architecture options, tradeoffs, repository consequences
and a recommendation for Project Owner confirmation before implementing a new
or revised architecture. Accepted decisions already covered by task authorization
need no repeat approval; routine reversible choices within them remain engineering
judgment. Do not silently create durable public contracts or major workarounds.

Default to the existing checkout on the active feature branch; inspect branch
and status and preserve unrelated work. Do not automatically create temporary
clones or worktrees. Isolated copies are only for destructive testing, risky
migrations or uncertain experiments with a stated reason; integrate and validate
on the active branch. Permission/tooling failures do not justify a clone workaround.

Before completion: inspect git status and final diff (including staged changes),
run required scoped validation, commit only task files, verify commit/status,
report completion and stop. Honor explicit owner instructions such as no commit.

For non-trivial work, the root agent is the coordinator, scope/alignment owner, integrator and final reviewer. The root must preserve the Igor 2 authority order and task-mode boundaries above; delegation does not transfer responsibility for architecture, roadmap scope or migration decisions.

Use the named `Lead_Eng` role for substantial engineering that benefits from a dedicated technical owner, especially architecture-sensitive implementation, difficult debugging, cross-cutting changes and important integration work. During DISCOVERY and IMPLEMENTATION, `Lead_Eng` may delegate bounded support work to Luna helpers but remains responsible for the engineering result it owns.

Use default Luna helpers for bounded repository search, call-site discovery, tests, builds, linting, profiling, reproduction, documentation lookup, straightforward tests, mechanical edits and independent checks. Ordinary Luna helpers must not recursively delegate unless explicitly assigned a coordination role.

Delegate when independent expertise is useful, separate context improves quality,
or verification is valuable. Do not create parallel workers merely because they
are available. Keep small, tightly coupled or sequential work in the current
agent. Prefer fresh helpers for new bounded tasks unless context is useful.

Each assignment states phase, scope/file ownership, allowed actions, required
evidence and stopping condition. Communicate phase changes; finish or stop
discovery/implementation workers before STABILIZATION. During STABILIZATION and
RELEASE_FREEZE, allow at most one active delegated worker across the entire task
tree, solely for validation. Root owns integration/fixes; Lead_Eng cannot spawn
helpers in those phases. Freeze validation confirms agreed final evidence only.
Workers report results and stop after their assigned checks. Available concurrency
does not override phase limits.

The root remains responsible for:

- repository and product alignment;
- applying the Igor 2 authority and execution contracts;
- task decomposition and scope control;
- deciding when `Lead_Eng` is warranted;
- reviewing delegated results and resolving contradictions;
- integration decisions and final validation;
- updating Igor 2 status, legacy and evidence documentation when the task requires it.

Prefer the cheapest capable model and reasoning effort. Do not repeat routine work with stronger models without a concrete reason. If the active root model/effort is materially mismatched to a substantial task, flag the cheaper or stronger appropriate tier before doing expensive repository-wide work.

Do not assume delegated output is correct merely because it completed successfully. Validate it against the repository state, the relevant Igor 2 contracts and the evidence requirements in `docs/igor2/EXECUTION.md`.
