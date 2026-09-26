# Igor 2 roadmap

The numbered steps are stable references. Implementation may combine adjacent steps into larger development waves when their contracts are tightly coupled.

## Development waves

### Wave A — Foundation
Covers Steps 1–2.

### Wave B — Runtime & Safety
Covers Steps 3–4.

### Wave C — Module Platform
Covers Steps 5–6.

### Wave D — Host Intelligence
Covers Steps 7–10.

### Wave E — Agent Architecture
Covers Steps 11–12.

### Wave F — Reactive Igor
Covers Steps 13–16 and later Step 19.

### Wave G — Composable Igor
Covers Steps 17–18 and 20–22.

### Wave H — Consolidation
Covers Step 23.

---

## Step 1 — Legacy Audit & Cleanup Map

Inspect current architecture and classify significant paths as:

- KEEP;
- ADAPT;
- REPLACE;
- REMOVE;
- TEMPORARY COMPATIBILITY.

Record surviving legacy paths in `LEGACY.md` with a replacement and removal target.

Do not perform a speculative rewrite during this step.

## Step 2 — Architecture Rules

Maintain the stable Igor 2 invariants in `ARCHITECTURE.md` and architecture-level regression tests where practical.

## Step 3 — Interaction Runtime

Make TUI interaction state deterministic:

- pending question/selection;
- approval/explain/decline/stop;
- session state transitions;
- replies such as `3`, `logs`, `yes`, `continue`, `cancel`;
- structured event rendering.

Do not solve state continuity only by increasing prompt history.

## Step 4 — Privilege Broker

Separate OS privilege from Guide/Assist/Executive autonomy.

Support per-operation elevation with explicit authorization, scoped execution and auditable results. Do not expose blanket root authority to the model.

## Step 5 — Module Runtime v2

Introduce explicit module state:

- available;
- enabled;
- loaded;
- failed;
- disabled.

Remove filesystem presence as a source of runtime activation. Active behavior must derive from the module registry.

Keep v1 compatibility during migration.

## Step 6 — Module API v2

Define and validate a versioned contract based on durable concepts rather than an expanding hook list:

- identity;
- knowledge;
- observers;
- capabilities;
- checks;
- events;
- automations;
- relationships;
- configuration;
- lifecycle.

Contracts are optional: simple modules implement only what they need.

## Step 7 — Platform Abstraction

Build normalized platform services with tested Debian and Arch Linux backends.

Initial areas:

- package operations;
- systemd service operations;
- host identity and platform facts;
- common filesystem/user/network primitives needed by Igor capabilities.

Do not claim derivative support solely by ancestry.

## Step 8 — System Model

Create Igor-owned structured state for host, OS, storage, networking, services/packages, Igor runtime/modules, domain instances and relationships.

Facts must distinguish observation, configuration, inference and uncertainty.

## Step 9 — Observation Framework

Standardize observers that populate the System Model.

Observers declare ownership, cost, freshness, privilege, timeout, dependencies and outputs where applicable.

## Step 10 — Unified Health

Unify the underlying check model used by diagnostics and healing.

Keep Diagnose and Self-healing as different user-facing workflows, but make them consume the same structured observations/check results.

## Step 11 — Capability System v2

Promote capabilities to Igor's canonical operational API.

Capabilities define structured inputs, safety, privilege, preconditions, execution, verification and optional rollback.

TUI, CLI, automation, healing and external interfaces use the same capabilities.

## Step 12 — Knowledge & Context Engine

Separate durable knowledge from live state and operational history.

Compose only context relevant to the current intent. Disabled modules contribute nothing.

Replace ad-hoc prompt concatenation as the architecture becomes authoritative.

## Step 13 — Event Bus

Introduce structured internal events with source, type, related object, timestamp, severity/evidence and correlation where useful.

Avoid direct module-to-module hard wiring when an event/relationship can express the interaction.

## Step 14 — Automation Engine

Igor owns scheduled, periodic, conditional and event-triggered actions.

Modules may declare automations; they do not independently create invisible scheduling infrastructure.

Expose automations and their history in the TUI.

## Step 15 — Operational History

Persist meaningful incidents/actions:

- observations;
- diagnosis;
- approvals;
- privilege use;
- action;
- verification;
- result.

Chat history is not operational memory.

## Step 16 — Baselines

Use transparent history-based baselines to identify what is unusual for this machine.

Begin with explainable statistics and thresholds rather than opaque ML.

## Step 17 — Relationships & Deployments

Model module-owned instances and explicit relationships between them.

Separate:

- module/domain knowledge;
- discovered/configured instances;
- relationships;
- deployments.

## Step 18 — Composable Modules

Use the current `nextcloud_docker` deployment as the first proof case.

Only after the v2 contracts exist, evaluate decomposition into coherent domains such as Nextcloud, Docker and Cloudflare.

Preserve the working v1 deployment during migration.

## Step 19 — Self-Healing v2

Rebuild healing as normal Igor operation:

observation -> check -> incident -> diagnosis -> capability -> policy -> execution -> verification -> history.

Automatic recovery considers safety, confidence, policy, privilege, retries and prior outcomes.

## Step 20 — Igor TUI as Default

Once normal workflows are available through the new backend, make `./igor.sh` launch the primary TUI.

Keep CLI/headless paths for scripting, tests, recovery and automation. Preserve `--ai-tui` as a migration alias until safe to remove.

## Step 21 — Integration Rules

Support lightweight rules for knowledge/checks/capabilities that only make sense when specific domains interact.

Avoid combinatorial giant modules.

## Step 22 — Module Developer Tooling & Unified External Interfaces

After Module API v2 is proven:

- module create/validate/test/inspect tooling;
- standard module skeletons;
- email control migrated to shared capabilities/policy/history;
- notifications separated from command/control;
- future external interfaces use the same engine.

## Step 23 — Igor 2 Consolidation

Before declaring the migration complete:

- remove obsolete v1 compatibility paths;
- remove dead hooks/helpers;
- remove deprecated config paths where migration is complete;
- remove duplicate execution/state paths;
- update primary documentation to the final architecture;
- verify core is application-agnostic;
- run architecture-level regression checks.

No compatibility path should survive indefinitely without an explicit reason.
