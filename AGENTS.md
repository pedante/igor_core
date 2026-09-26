# Igor repository guidance for coding agents

Before substantial work:

1. Read `docs/igor2/README.md`.
2. Read `docs/igor2/STATUS.md`.
3. Read only the Igor 2 documents relevant to the current task.
4. Inspect the affected implementation and tests before editing.

## Authority

For Igor 2 work, use this order of authority:

1. `docs/igor2/ARCHITECTURE.md`
2. accepted decisions in `docs/igor2/DECISIONS.md`
3. `docs/igor2/MIGRATION.md`
4. `docs/igor2/ROADMAP.md`
5. current implementation documentation

`docs/module_creation.md` describes the current Module API v1. It is not the Module API v2 specification.

## Working rules

- Preserve working behavior unless the migration plan explicitly replaces it.
- Do not create a second permanent implementation of an existing responsibility.
- When a replacement becomes authoritative, remove or clearly mark the superseded path.
- Expand task scope only when repository evidence shows a cross-cutting dependency.
- Prefer acceptance criteria and regression tests over implementation-specific assumptions.
- Keep core application-agnostic.
- Treat module presence on disk as different from module activation.
- Keep AI reasoning separate from deterministic authorization, privilege, state, and execution policy.
- Prefer registered capabilities over raw shell execution when an equivalent capability exists.
- Do not claim Debian/Arch compatibility without tests for the relevant platform abstraction.
- Update `STATUS.md` and `LEGACY.md` when substantial migration work changes their state.
- If implementation contradicts an accepted architectural decision, stop and surface the conflict instead of silently inventing a new architecture.
