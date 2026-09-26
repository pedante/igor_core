# Igor documentation

## Current implementation

| Document | Purpose |
|---|---|
| [../README.md](../README.md) | Current project overview, usage and layout |
| [module_creation.md](module_creation.md) | Current Module API v1 development guide |
| [module_lifecycle.md](module_lifecycle.md) | Current module activation/runtime semantics |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution and validation workflow |
| [CHANGELOG.md](CHANGELOG.md) | Release/unreleased history |

## Igor 2 migration

The target architecture and migration authority live under [igor2/](igor2/README.md).

Start with:

1. [igor2/STATUS.md](igor2/STATUS.md)
2. [igor2/ARCHITECTURE.md](igor2/ARCHITECTURE.md)
3. the task-relevant roadmap/decision/module document

Current docs describe how Igor works today. Igor 2 docs describe the target and how to migrate without rebuilding correct recent foundations.

## Documentation rule

Do not keep stale handoff, audit or superseded roadmap documents in the active documentation tree merely for history. Git history is the archive.

When behavior changes, update the current subsystem documentation. When architecture/migration state changes, update the relevant `docs/igor2/` file.
