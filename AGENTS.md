# Repository Guidelines

## Read Before Editing

Start with [README.md](README.md), [module guide](docs/module_creation.md), and [contributing guide](docs/CONTRIBUTING.md). Use these for detailed contracts; verify older examples against `core/lib/module_loader.sh` and `tests/modules/`. Inspect `git status` and preserve unrelated work. Some tests assume `nextcloud_docker` exists even when absent from the working tree; report baseline failures rather than restoring it automatically.

## Architecture & Module Structure

`igor.sh` starts the Bash platform; `core/` owns shared infrastructure and Python helpers. Keep service-specific behavior in `modules/<name>/`, connected through hooks. Use `modules/system/` as a reference. New modules need `module.conf` and `module.sh`; add `checks/`, `menus/`, `lib/`, `defaults/`, `config/`, and `docs/` only as needed.

Manifest tests require `[module]`, `[dependencies]`, nonempty `name` and `display_name`, `version=X.Y.Z`, and a `requires_core` field. Declared `variables_file` paths must exist. These requirements are stricter than the loader's permissive parser. Avoid inline value comments: the parser retains them.

## Lifecycle, Hooks & Naming

Loading follows discovery → `depends_on` ordering → required binary/module checks → syntax check → source → `<name>__register()`. Use `required_modules` for mandatory dependencies as well as `depends_on` for ordering. Sourcing should define functions without operational side effects; registration wires hooks/menus. Optional `__install`, `__upgrade`, and `__uninstall` are separate lifecycle calls; installation must be idempotent.

`igor_register_hook` deduplicates registrations. `igor_run_all_hooks` uses fresh Bash processes with a default 30-second timeout: do not assume unexported helpers/globals are available or mutate parent state. Check each caller for direct in-process dispatch. Keep hooks noninteractive and preserve documented output formats.

Use four spaces, `<name>__*` for module APIs, `_mod_<short>_*` for helpers, and `menu_*` for menus. Healing plugins define isolated `run_check()` functions emitting `CHECK_RESULT SEVERITY code message`.

## Configuration & Secrets

Keep generic defaults in `config/variables/`; personal settings and credentials belong in ignored `secrets/` files with mode `600`. Secrets override defaults; root-level env files are deprecated. Preserve scrubbing and safety gates. Resolve paths through `IGOR_DIR`, `_igor_resolve_dir`, and `<NAME>_STACK_DIR`; never depend on the current directory.

## Validation & Contribution

Module BATS tests parse manifests and probe explicitly named modules in fresh shells with temporary fixtures and mocked Docker/UI. Add contract probes for new modules; manifest discovery alone does not test their hooks.

Before completing code changes, run from the repository root:

- `bash -n <changed-script>` and ShellCheck with flags from [.github/workflows/ci.yml](.github/workflows/ci.yml).
- `bats tests/modules/` for module changes.
- `bash tests/run_all.sh` for Bash, Python, and BATS suites; `--fast` omits integration tests.
- `ruff check .` for Python changes.

Report failures and skips; missing BATS can yield an incomplete successful run. For documentation-only edits, check links and the diff. Use descriptive commits and the PR template; explain behavior, validation, and relevant documentation updates.


## Agent Delegation

For non-trivial coding tasks, the primary agent should act as lead engineer and reviewer.

Prefer delegating implementation work to subagents, especially for:

- source-file edits
- test creation and updates
- straightforward bug fixes
- repetitive refactors
- running test suites and linters
- independent workstreams that can run in parallel

The primary agent should retain responsibility for:

- repository inspection
- architecture and implementation strategy
- task decomposition
- difficult debugging
- reviewing delegated changes
- integration decisions
- final validation

After delegated work finishes, inspect the resulting diff and verify it against the repository guidelines above. Do not assume subagent output is correct simply because the task completed successfully.

For very small or tightly coupled changes, direct implementation by the primary agent is acceptable.
