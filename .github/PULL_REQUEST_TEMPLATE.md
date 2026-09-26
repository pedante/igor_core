## Description

- What problem does this solve?
- What changed?
- Why is this approach appropriate?

## Type

- [ ] Bug fix
- [ ] Feature
- [ ] Refactor
- [ ] Documentation
- [ ] Igor 2 migration/architecture
- [ ] Other

## Validation

List the exact checks you ran and their results.

- [ ] Focused tests for affected behavior
- [ ] `bash -n` / ShellCheck for changed shell code where applicable
- [ ] Python tests / `ruff check .` for changed Python code where applicable
- [ ] `bash tests/run_all.sh` or an explained scoped alternative
- [ ] `git diff --check`
- [ ] Manual/PTY validation where interaction behavior changed

Baseline failures/skips:

## Architecture / migration

- Does this alter a current public/runtime contract?
- Does it add or retire a compatibility path?
- For Igor 2 work, were `docs/igor2/STATUS.md`, `LEGACY.md`, or `DECISIONS.md` updated if needed?
- Does the change preserve deterministic safety, privilege, module-ownership and AI reference-data boundaries?

## Documentation

- [ ] Current behavior docs updated if behavior changed
- [ ] CHANGELOG updated for user-facing changes where appropriate
- [ ] No stale duplicate documentation was introduced

## Breaking changes / migration

Describe any compatibility impact and migration steps.

## Related issues

Closes #
