# Igor 2 architecture package

This directory is the repository-resident design authority for the Igor 2 migration.

It exists so maintainers and coding agents can work from durable repository context instead of reconstructing the architecture from chat history.

## Read order

For most Igor 2 work:

1. `STATUS.md` — current migration state and next focus.
2. `ARCHITECTURE.md` — stable target principles and boundaries.
3. Read only the task-relevant document:
   - `ROADMAP.md` — stable step names, development waves and current implementation status.
   - `MODULE_API.md` — target Module API v2.
   - `HOST_INTELLIGENCE.md` — accepted Wave D design and implementation gate for Steps 7–10.
   - `MIGRATION.md` — compatibility, persistent migration and cleanup policy.
   - `EXECUTION.md` — evidence gates, vertical slices, inspection and scope discipline.
   - `INFLUENCES.md` — ServerMind/Steward lessons intentionally adopted by Igor.
   - `DECISIONS.md` — accepted and unresolved architectural decisions.
   - `LEGACY.md` — significant current paths that must be kept, adapted or retired.

## Current implementation versus target

The root README, current subsystem docs, code and tests describe how Igor works today.

The files here describe where Igor is going and how to migrate safely.

Important current foundations already exist. Igor 2 must **not** recreate them under parallel names merely because the roadmap originally described them as future work. The current TUI/runtime, safety/privilege flow, module activation boundary, platform helpers, AI trust boundary and capability catalog are migration inputs.

`docs/module_creation.md` remains the current Module API v1 reference until v2 is implemented and adopted. `docs/module_lifecycle.md` documents the current module activation model.

## Design goal

Igor is a local AI-assisted operating layer for Linux. It should maintain typed machine memory, discover the host deterministically, distinguish observed state from desired state and responsibilities, gain domain knowledge and abilities through modules, preserve durable investigations, plan installation/configuration work through structured capabilities, execute safely, verify changes deterministically, retain useful operational history and local learning, and let users operate the machine without needing to know the underlying commands.

The Codex-like TUI is the primary human-interface direction. CLI and future external interfaces remain useful, but should use the same backend state/capability engine rather than implement parallel operating logic.

## Documentation discipline

These files are architectural memory, not a second implementation.

- Stable principles belong in `ARCHITECTURE.md`.
- Execution/completion rules belong in `EXECUTION.md`.
- Adopted external design lessons belong in `INFLUENCES.md`; they do not override accepted Igor decisions.
- Accepted/open decisions belong in `DECISIONS.md`.
- Temporary migration state belongs in `STATUS.md`.
- Significant compatibility/debt belongs in `LEGACY.md`.
- Current implementation details belong next to current code/tests/docs.
- Git history is the archive for superseded planning/handoff documents; stale copies should not remain in active docs merely for history.
