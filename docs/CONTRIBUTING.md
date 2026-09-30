# Contributing to Igor

Thanks for contributing to Igor.

## Start here

Before editing:

1. Read the root [README](../README.md).
2. Read [AGENTS.md](../AGENTS.md) for repository and validation rules.
3. For module work, read [module_creation.md](module_creation.md) and [module_lifecycle.md](module_lifecycle.md).
4. For Igor 2 architecture/migration work, read [igor2/README.md](igor2/README.md) and [igor2/STATUS.md](igor2/STATUS.md).

Current code/docs describe how Igor works today. `docs/igor2/` describes the target architecture and migration constraints.

## Development workflow

Codex engineering work follows the [orchestration lifecycle](../.codex/README.md):
DISCOVERY → IMPLEMENTATION → STABILIZATION → RELEASE_FREEZE → COMPLETE.
State the phase, allowed next action and exit evidence. Obtain owner confirmation
before implementing new or revised architecture; existing accepted decisions
within authorized scope do not need repeat approval.

Work directly on the active feature branch by default. Isolated copies are only
for destructive testing, risky migrations or uncertain experiments. Delegate
when expertise, separate context or verification helps; stabilization and release
freeze allow at most one active validation worker across the whole task tree.

- Keep changes scoped and preserve unrelated work.
- Add or update tests for behavior changes.
- Prefer existing backend contracts over duplicate implementations.
- Keep application-specific behavior out of core where practical.
- Preserve deterministic safety, approval, privilege and scrubbing boundaries.
- Update current docs when current behavior changes.
- For Igor 2 work, update `docs/igor2/STATUS.md` and `LEGACY.md` when migration state changes.

When implementation, focused tests, required regressions and documentation are
complete, enter RELEASE_FREEZE and stop development: no new features, speculative
improvements, unrelated refactoring, new tests unless required by a failing
regression, or reopening architecture decisions. Only concrete acceptance
failures justify an explicit return to stabilization for a scoped correction.
Inspect final status/diff, confirm required validation, commit task files, report
completion and stop. Follow explicit owner instructions if they say not to commit.
Do not search for more improvements after final validation.

## Code style

- Bash: follow existing patterns and use four-space indentation.
- Module public functions: `<module>__*`.
- Module helpers: `_mod_<short>_*`.
- AI helpers: `ai_*` / `_ai_*`.
- Healing helpers: `healing_*` / `_healing_*`.
- Prefer comments explaining non-obvious invariants rather than narrating simple code.

## Modules

The current Module API is v1 and is documented in [module_creation.md](module_creation.md).

Current activation semantics are documented in [module_lifecycle.md](module_lifecycle.md).

Do not implement the target Igor 2 Module API by inventing new hooks ad hoc. Igor 2 module-contract work belongs under the versioned migration described in [igor2/MODULE_API.md](igor2/MODULE_API.md).

## Testing

Run tests from the repository root.

Common checks:

```bash
bash tests/run_all.sh
bash tests/run_all.sh --fast
bats tests/modules/
ruff check .
git diff --check
```

For changed shell files also run `bash -n` and ShellCheck with the flags used by `.github/workflows/ci.yml`.

Run focused Python/unit tests for changed Python modules.

For Codex configuration/documentation-only changes, parse TOML, verify policy
consistency and links/references, and inspect the final diff with
`git diff --check`. Do not run expensive unrelated runtime regressions.

Report failures and skips clearly. Do not make unrelated changes just to hide a pre-existing baseline failure.

## Platform support

Igor contains distro/package abstraction code and Arch-aware paths, but support claims should follow tests.

For Igor 2, Debian and Arch Linux are the initial explicit tested platform targets. Do not infer full derivative support from package-family detection alone.

## Pull requests

A PR should explain:

- what changed;
- why;
- relevant architectural/migration impact;
- tests/validation performed;
- known limitations or deferred follow-up.

Keep commits understandable and avoid mixing unrelated cleanup with feature work.

## License

Contributions are licensed under the repository's [GPL v3](../LICENSE).
