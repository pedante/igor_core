# Repository Guidelines

## Read before editing

For current implementation details, start with:

1. [README.md](README.md)
2. [docs/module_creation.md](docs/module_creation.md) — current Module API v1
3. [docs/module_lifecycle.md](docs/module_lifecycle.md) — current activation/runtime semantics
4. [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)

For Igor 2 work, also read:

1. [docs/igor2/README.md](docs/igor2/README.md)
2. [docs/igor2/STATUS.md](docs/igor2/STATUS.md)
3. only the Igor 2 documents relevant to the task

Before a roadmap wave, verify the working branch contains the intended current `master` baseline. Do not audit or migrate from a stale branch.

## Igor 2 authority

For target architecture and migration decisions, use this order:

1. `docs/igor2/ARCHITECTURE.md`
2. accepted decisions in `docs/igor2/DECISIONS.md`
3. `docs/igor2/MIGRATION.md`
4. `docs/igor2/ROADMAP.md`
5. current implementation documentation

The code and current docs remain the authority for how Igor works **today**. Igor 2 documents describe the target and migration boundaries. If current behavior conflicts with a target invariant, surface the conflict instead of silently inventing a third design.

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

Do not hide pre-existing baseline failures by restoring unrelated files or changing behavior outside the task.

## Agent delegation

For non-trivial coding tasks, the primary agent should act as lead engineer and reviewer.

Delegate straightforward source edits, tests, repetitive refactors and independent workstreams when useful. The primary agent remains responsible for repository inspection, architecture, difficult debugging, integration decisions, reviewing delegated changes and final validation.

Do not assume delegated output is correct merely because it completed successfully.
