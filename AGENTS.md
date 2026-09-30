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

## Codex Agent Orchestration

Igor's project-local Codex orchestration policy lives in `.codex/config.toml`. The project config intentionally does not select the root/orchestrator model or reasoning effort; the Project Owner chooses them per task.

For non-trivial work, the root agent is the coordinator, scope/alignment owner, integrator, and final reviewer. Use the named `Lead_Eng` role for substantial architecture-sensitive implementation, difficult debugging, cross-cutting changes, and important integration. Use default Luna helpers for bounded repository search, tests, builds, linting, profiling, reproduction, documentation lookup, straightforward tests, mechanical edits, and independent checks.

Do not delegate merely to create parallel activity. Keep small, tightly coupled, or sequential work in the current agent. Prefer fresh helpers for new bounded tasks unless accumulated context is genuinely useful.

The root remains responsible for:
- repository and product alignment
- task decomposition and scope control
- deciding when `Lead_Eng` is warranted
- reviewing delegated results and resolving contradictions
- integration decisions and final validation

`Lead_Eng` remains responsible for the difficult engineering it owns and may delegate bounded support work to Luna helpers. Ordinary Luna helpers must not recursively delegate unless explicitly assigned a coordination role.

Prefer the cheapest capable model/effort. Do not repeat routine work with stronger models without a concrete reason. If the active root model/effort is materially mismatched to a substantial task, flag the cheaper or stronger appropriate tier before doing expensive repository-wide work.
