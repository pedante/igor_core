# Igor 2 migration status

Last updated: 2026-09-26

## Baseline

The `igor2` branch was created from current `master` after the recent TUI/runtime/module work. The architecture package is being reconciled to that baseline before implementation starts.

Roadmap descriptions are **not evidence that functionality is missing**. Step 1 must inspect current code/tests first.

## Current stage

**Wave A — Foundation / Step 1 ready**

No new Igor 2 architecture implementation has begun on this branch beyond documentation preparation.

## Strong foundations already present

Preserve and formalize these:

- full-screen Codex-like `--ai-tui`;
- structured frontend JSONL event stream;
- canonical session command registry and palette;
- Guide / Assist / Executive modes;
- READ / CHANGE / DESTROY classification and approval/explain/decline/stop flow;
- structured provider/tool transactions and execution results;
- pending conversational choice handling for numbered/textual replies;
- native sudo authentication through the backend PTY with privilege events;
- request/reference-data trust boundary and last-mile redaction;
- bounded AI operational audit;
- explicit module enable/disable policy;
- owner-aware module hooks, menus and capability actions;
- active-module filtering in diagnostics/healing and subsystem regression tests;
- distro detection and package abstraction with Debian/Arch mappings;
- existing action/capability catalog and `run_igor_action`;
- recovery journal, diagnostics, healing and notifications.

## Important corrections to the earlier plan

- Interaction Runtime is no longer greenfield; Step 3 is audit/hardening.
- Privilege Broker is no longer greenfield; Step 4 is generalization/hardening.
- Module Runtime v2 has a substantial current implementation; Step 5 must reconcile/complete it, not replace it.
- Platform Abstraction already has `distro.sh`/`pkg.sh`; Step 7 expands/tests them.
- The existing AI frontend event stream is not the future Domain Event Bus.
- The existing AI request boundary/reference envelope is a foundation for Step 12.
- The old `core/mailcmd/` implementation is absent from the current tree. Email control should not be treated as a working subsystem to migrate.

## Known architectural work still ahead

- establish a trustworthy test/lint baseline and current legacy map;
- remove/contain remaining application-specific core behavior;
- define Module API v2 without proliferating hooks;
- build a coherent System Model and observer framework;
- unify diagnose/healing check semantics;
- generalize capabilities beyond AI-specific catalog terminology;
- compose relevant knowledge/state/history instead of broad direct context probing;
- add operational Domain Event Bus and Igor-owned automation;
- add relationships/deployments and prove module composition;
- evolve audit/journal data into operational history and baselines;
- converge interfaces on the shared engine;
- eventually make the new TUI the default Igor human interface.

## Wave A / Step 1 objective

Step 1 should:

1. audit the current repository against Igor 2 invariants;
2. classify significant current/legacy paths;
3. identify which later roadmap outcomes are already implemented or partial;
4. establish the real test/lint/CI baseline;
5. update `LEGACY.md` and this file from evidence;
6. identify architecture regression tests that Step 2 should add;
7. make only small, clearly safe baseline/documentation fixes.

It must not begin Module API v2, System Model, module splitting or other later-wave architecture.

## Do not do yet

- do not split `nextcloud_docker`;
- do not replace the current module loader;
- do not replace the TUI/event/approval runtime with a second implementation;
- do not rewrite all v1 hooks;
- do not choose a persistence database before System Model requirements are concrete;
- do not re-create mail control merely because old docs referenced it;
- do not make `./igor.sh` default to the new TUI yet;
- do not claim cross-distro support beyond tested behavior.

## After each substantial Igor 2 task

- update this file;
- update `LEGACY.md` when compatibility/debt changes;
- record accepted decisions in `DECISIONS.md`;
- update current subsystem docs when behavior actually changes;
- keep detailed implementation notes in code/tests, not this status file.
