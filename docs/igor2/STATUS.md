# Igor 2 migration status

Last architecture-package update: 2026-09-26

## Current stage

**Pre-implementation architecture package / Wave A preparation**

No Igor 2 subsystem should be considered implemented merely because it is described in this directory.

The current codebase remains the production implementation.

## Already achieved in the current codebase

These are useful foundations to preserve and adapt:

- Codex-like full-screen `--ai-tui`;
- structured backend event stream;
- canonical command registry/palette direction;
- READ / CHANGE / DESTROY backend classification;
- approval / decline / explain / stop workflow;
- Guide / Assist / Executive interaction modes;
- AI-powered explanation while backend owns authorization;
- improved structured rendering and history/navigation direction;
- existing module loader/hook registry;
- existing capability catalog / `run_igor_action`;
- secret scrubbing;
- diagnostics, healing, recovery journal, notifications and GPG mail control.

## Known immediate concerns

- conversational selection continuity needs deterministic runtime state;
- privilege/elevation UX is not yet the desired per-operation broker;
- active module behavior still leaks from filesystem discovery in some subsystems;
- core still contains application-specific assumptions;
- host/system knowledge is not yet a coherent System Model;
- prompt/module knowledge injection is hook-heavy and mostly text-oriented;
- README/current docs still describe legacy UI/module architecture as current behavior;
- Debian/Arch support needs a deliberate platform abstraction and tests rather than broad claims.

## Next implementation focus

### Wave A — Foundation

1. Perform Step 1 Legacy Audit against the current repository and expand `LEGACY.md` only with evidence.
2. Turn critical Igor 2 invariants into targeted tests where practical.
3. Resolve only the architectural questions needed before Wave B/C implementation.

### Then Wave B — Runtime & Safety

- Step 3 Interaction Runtime;
- Step 4 Privilege Broker.

### Then Wave C — Module Platform

- Step 5 Module Runtime v2;
- Step 6 Module API v2.

## Do not do yet

- Do not split `nextcloud_docker` into separate modules.
- Do not rewrite all current hooks.
- Do not choose a persistence database before System Model requirements are concrete.
- Do not rewrite working mail transport solely to move files.
- Do not make `./igor.sh` default to the new TUI until migration acceptance criteria are met.
- Do not claim Arch/Debian-family support beyond what tests demonstrate.

## Package maintenance

After a substantial Igor 2 task:

- update this file with the current wave and completed milestones;
- update `LEGACY.md` if a compatibility path was added/removed;
- add accepted architectural decisions to `DECISIONS.md`;
- keep details in code/tests rather than expanding this status file into a changelog.
