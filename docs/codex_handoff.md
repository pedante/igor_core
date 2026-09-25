# Igor Codex Handoff

## Step 1 status

**Complete. Ready for Step 2.** No Step 2 UI was built.

## Major root causes fixed

- Provider history trimming could split native assistant/tool turns. Complete
  transactions and canonical results now survive continuation and resume.
- Execution success, denial, and verification outcomes were conflated. Igor now
  records structured classification, approval, exit status, and session state;
  an applied change remains applied when later verification is declined.
- AI menu `s`/`f` could leave immediately or hide initialization failures.
  Both use one startup path with explicit startup, running, exit, and failure
  states. The configured private runtime is prepared before state writes and
  rejects symlinks and foreign ownership.
- The main header's Nextcloud status hook ran interactive `sudo` for cosmetic
  READ data. The related health check and AI context had the same unnecessary
  elevation. Hooks also inherited input from the hook runner, and EOF in the
  parent menu could spin. Reads now run unprivileged, hooks receive `/dev/null`
  stdin, and closed menu input exits cleanly.
- Hardware profiling used hardcoded `/data/runtime`. Its cache now uses Igor's
  resolved runtime path and writes only after that directory is private.
- The READ parser rejected all shell composition except one journal pipeline,
  so the host dispatcher fell back to CHANGE for observational VLC and package
  queries. It now checks each command in `&&`, `||`, and `|` expressions and
  permits only stderr discard to `/dev/null`; unknown and mutating branches
  still require approval. Semantic tool argument parsing remains strict.
- The DESTROY check matched `rm ` inside pacman's `--noconfirm ` option. `rm`
  now requires a command-word boundary; package installs/upgrades are CHANGE
  and pacman removals are DESTROY.

## Backend decisions and components

- Igor runs as the regular user; `igor.sh` rejects root launch before startup.
  Privileged operations still elevate after their authorization path.
- `core/ai/transactions.py` owns provider transaction completion and canonical
  results. `core/ai/core.sh` owns session state, runtime preparation, and stop
  semantics. `core/ai/session_commands.py` remains a data-only command registry.
- `core/ai/tool_input.py` remains the authoritative READ classifier;
  `core/ai/safety.sh` retains destructive precedence and the conservative
  CHANGE fallback. Approval labels use the resulting tier.
- Material changes include `igor.sh`, AI core/safety/knowledge, `core/lib/ui.sh`,
  `core/lib/module_loader.sh`, `core/host/profile.sh`, the Nextcloud module and
  network check, README, and focused Python/BATS regressions.

## Validation and Step 2 prerequisites

- All 119 Python tests, 187 core BATS tests, and 40 integration BATS tests pass.
  The exact VLC host command runs as READ without approval; package install
  reaches CHANGE approval. Startup/runtime, provider, result, and denial tests
  also pass. Bash syntax, Python compile, and `git diff --check` pass.
- The full runner reports three pre-existing unrelated Nextcloud storage
  expectation failures in the module group (57/60 pass). ShellCheck and Ruff
  were unavailable locally. There is no unresolved Step 1 code blocker.
- Step 2 may build on the existing command registry, explicit session states,
  and canonical result fields. Keep provider transaction completion,
  authorization, classification, and private runtime checks in the backend.
