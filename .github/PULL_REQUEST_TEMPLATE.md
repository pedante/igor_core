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
- [ ] Relevant Python tests / Ruff on changed Python code where applicable
- [ ] Governed `tests/validate.sh focused|affected` for the scoped contract
- [ ] Full/CI release gate only if explicitly required; report unexecuted gates
- [ ] `git diff --check`
- [ ] Manual/PTY validation where interaction behavior changed

Baseline failures, permitted skips and unverified checks (separate from source inspection):

## Architecture / migration

- For Igor 2, follow [Development Policy / D078](../docs/igor2/DEVELOPMENT_POLICY.md): no `master` reconciliation gate.
- Does this alter a current public/runtime contract?
- Does it add or retire a compatibility path?
- For Igor 2 work, were `docs/igor2/STATUS.md`, `LEGACY.md`, or `DECISIONS.md` updated if needed?
- Does the change preserve deterministic safety, privilege, module-ownership and AI reference-data boundaries?

## Documentation

- [ ] Current behavior docs updated if behavior changed
- [ ] CHANGELOG updated for user-facing changes where appropriate
- [ ] No stale duplicate documentation was introduced

## Breaking changes / migration

Distinguish optional internal pre-release compatibility from platform/version,
module/dependency, explicit third-party and data-integrity obligations. For an
authorized canonical contract change, migrate implementation, all consumers,
fixtures and tests together; replace obsolete assertions with intended-contract
coverage and retire superseded paths. Preserve safety/privacy/privilege/History
regressions and all five EXECUTION proof classes. Documentation-only evidence
does not prove runtime migration or feature completion.

## Related issues

Closes #
