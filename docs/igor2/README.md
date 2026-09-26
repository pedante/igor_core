# Igor 2 architecture package

This directory is the repository-resident design authority for the Igor 2 migration.

Its purpose is to let maintainers and coding agents understand the target architecture without repeatedly reconstructing it from chat history or auditing the entire repository.

## Read order

For most work:

1. `STATUS.md` — where the migration currently is.
2. `ARCHITECTURE.md` — stable principles and boundaries.
3. The document relevant to the task:
   - `ROADMAP.md` — implementation sequence.
   - `MODULE_API.md` — target module contract.
   - `MIGRATION.md` — compatibility and cleanup rules.
   - `DECISIONS.md` — accepted and unresolved architectural decisions.
   - `LEGACY.md` — known old paths and their planned replacement/removal.

## Current versus target architecture

The normal project documentation and code describe the current implementation.

The files in `docs/igor2/` describe the target architecture and migration constraints.

In particular, `docs/module_creation.md` remains the reference for Module API v1 until v2 is implemented and adopted.

## Design goal

Igor is a local AI-assisted operating layer for Linux. It should understand the host, gain domain knowledge and abilities through modules, investigate before acting, execute safely through deterministic capabilities, verify changes, retain useful operational history, and let users operate the machine without needing to know the underlying commands.

The primary human interface is the Codex-like TUI. CLI and external interfaces remain valuable, but they should use the same backend capabilities and state model rather than implement parallel operating logic.

## Keep this package compact

These documents are architectural memory, not a second codebase.

- Stable principles belong in `ARCHITECTURE.md`.
- Decisions belong in `DECISIONS.md`.
- Temporary migration state belongs in `STATUS.md`.
- Old paths belong in `LEGACY.md`.
- Implementation details belong next to the code and tests.
