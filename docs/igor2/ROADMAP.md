# Igor 2 roadmap

The numbered step names are stable references. They describe outcomes, not instructions to rebuild functionality that already exists.

Status labels describe the current `igor2` baseline:

- **CURRENT** — substantially present; audit/formalize rather than rebuild.
- **PARTIAL** — useful implementation exists but target contract is incomplete.
- **FUTURE** — target architecture is not yet established.
- **NOW** — current work.

## Development waves

- **Wave A — Foundation:** Steps 1–2
- **Wave B — Runtime & Safety:** Steps 3–4
- **Wave C — Module Platform:** Steps 5–6
- **Wave D — Host Intelligence:** Steps 7–10
- **Wave E — Agent Architecture:** Steps 11–12
- **Wave F — Reactive Igor:** Steps 13–16 and 19
- **Wave G — Composable Igor:** Steps 17–18 and 20–22
- **Wave H — Consolidation:** Step 23

Recent work means Waves B and parts of C/D/E already have substantial foundations. The roadmap must preserve and generalize them rather than create parallel systems.

---

## Step 1 — Legacy Audit & Cleanup Map — NOW

Audit the **current** repository against Igor 2 invariants.

Classify significant architecture paths as:

- KEEP;
- ADAPT;
- REPLACE;
- REMOVE;
- TEMPORARY COMPATIBILITY.

Also classify roadmap requirements as already implemented, partial, implemented differently-but-acceptably, or missing.

Update `LEGACY.md` and `STATUS.md` with evidence. Establish the test/lint baseline. Make only small, clearly safe baseline/doc fixes; do not start later architecture.

## Step 2 — Architecture Rules — PARTIAL

The repository-resident architecture package exists.

Complete this step by turning critical invariants into focused regression tests where practical and reconciling accepted decisions with Step 1 evidence.

## Step 3 — Interaction Runtime — CURRENT / HARDEN

The structured TUI, event stream, command registry, session states, approvals and pending conversational choices already exist.

Audit and harden:

- explicit pending interaction state;
- deterministic replies such as `3`, `logs`, `yes`, `continue`, `cancel`;
- conversation/approval state transitions;
- frontend/backend ownership;
- reuse by future interfaces.

Do not replace this runtime with a second state machine merely to satisfy the roadmap.

## Step 4 — Privilege Boundary — CURRENT / HARDEN

Native sudo authentication through the backend PTY and privilege events already separate OS authentication from AI autonomy.

Formalize the general contract:

- privilege metadata belongs to capabilities/runtime;
- exact approved operation is preserved;
- authentication never enters model context/history/events;
- Executive never grants blanket root;
- failures close safely.

Extend only where current behavior does not cover general capabilities/interfaces.

## Step 5 — Module Runtime v2 — CURRENT / FORMALIZE

Current code already has:

- installed/discovered modules;
- explicit enable/disable policy in `config/modules.conf`;
- active/unavailable state;
- owner-aware hooks, menus and capabilities;
- active-module filtering in major subsystems;
- regression tests.

Do not introduce a parallel loader or rename states without value.

Complete the target semantics by auditing every runtime contribution path and ensuring inactive modules contribute nothing. Clarify dependency/lifecycle semantics and compatibility boundaries for Module API v2.

Restart-based activation is acceptable; hot unload is not a requirement.

## Step 6 — Module API v2 — FUTURE

Define and validate a versioned contract based on durable concepts rather than an expanding hook list:

- identity;
- knowledge;
- observers;
- capabilities;
- checks;
- domain events;
- automations;
- relationships;
- configuration;
- lifecycle.

Contracts are optional. Keep API v1 working through an explicit migration/compatibility path until real v2 modules prove the contract.

## Step 7 — Platform Abstraction — PARTIAL

Current `distro.sh`, `pkg.sh` and Python resolution already include Debian/Arch-aware behavior and additional family mappings.

Audit and generalize rather than replace.

Target at minimum:

- tested distro/platform detection;
- package query/install/remove/update abstractions;
- systemd service operations;
- host identity and common user/filesystem/network operations needed by capabilities;
- tests for Debian and Arch behavior.

Do not claim full derivative support merely from `ID_LIKE` or package mappings.

## Step 8 — System Model — FUTURE

Create Igor-owned structured state for host, OS, storage, networking, services/packages, Igor runtime/modules, domain instances and relationships.

Facts distinguish:

- observed;
- configured;
- inferred;
- user-declared;
- known/unknown/stale.

Start with stable interfaces and simple storage; do not choose a large persistence system prematurely.

## Step 9 — Observation Framework — FUTURE

Standardize observers that populate the System Model.

Observers declare ownership, output types, cost/freshness, privilege, timeout and dependencies as needed.

Consumers should query Igor state instead of repeatedly issuing their own probes.

## Step 10 — Unified Health — PARTIAL

Diagnostics and healing already share module check conventions and activation filtering, but remain separate discovery/execution paths.

Unify the underlying structured observation/check result while keeping Diagnose and Self-healing as different user workflows.

One check result should be reusable by health score, diagnosis, AI, healing, notifications and history.

## Step 11 — Capability System v2 — PARTIAL

The current action catalog, `run_igor_action`, ownership and safety metadata are the seed.

Generalize them into Igor's canonical operational API with structured:

- inputs;
- owner;
- safety;
- privilege;
- preconditions;
- execution;
- verification;
- rollback where available;
- affected objects;
- platform requirements.

TUI, CLI, automation, healing and future external interfaces should invoke the same capabilities.

## Step 12 — Knowledge & Context Engine — PARTIAL

The current request boundary/reference envelope is a strong trust foundation. Preserve it.

Replace broad ad-hoc context gathering over time with composition of relevant:

- core operating guidance;
- System Model facts;
- active module knowledge;
- relationships;
- capabilities;
- relevant history.

Disabled modules contribute nothing. Reference material never becomes authorization policy.

## Step 13 — Domain Event Bus — FUTURE

Do not confuse this with the existing AI frontend event stream.

Introduce structured operational events such as:

- service.failed;
- container.stopped;
- disk.threshold_exceeded;
- backup.failed;
- capability.completed/failed;
- module.enabled/disabled.

Events include source, related object, timestamp, severity/evidence and correlation where useful.

## Step 14 — Automation Engine — FUTURE

Igor owns scheduled, periodic, conditional and event-triggered actions.

Modules may declare/propose automations; they do not create unmanaged cron behavior as the normal contract.

Track enablement, trigger, capability, policy, privilege, previous/next run, retries and result. Expose automations in the TUI.

## Step 15 — Operational History — PARTIAL

Current bounded AI audit and recovery journal are useful inputs.

Evolve toward structured incidents/actions containing observations, diagnosis, approvals, privilege use, execution, verification and outcome.

Chat history is not operational memory.

## Step 16 — Baselines — FUTURE

Use transparent operational history to learn normal ranges/behavior for this machine.

Begin with explainable statistics and thresholds, not opaque ML.

## Step 17 — Relationships & Deployments — FUTURE

Separate:

- module/domain knowledge;
- instances on this machine;
- relationships;
- deployments.

Define provenance for discovered, configured, installer-created, user-declared and AI-proposed relationships.

## Step 18 — Composable Modules — FUTURE

Use the current `nextcloud_docker` deployment as the first composition proof case **after** v2 contracts exist.

Evaluate coherent independent domains such as Nextcloud, Docker and Cloudflare. Do not split PostgreSQL/Redis/etc. merely for purity.

Preserve the working v1 deployment during migration.

## Step 19 — Self-Healing v2 — FUTURE

Rebuild self-healing on normal Igor primitives:

```text
observation -> check -> incident -> diagnosis -> capability
            -> policy -> execution -> verification -> history
```

Automatic recovery considers safety, confidence, user policy, privilege, retries and prior outcomes.

## Step 20 — Igor TUI as Default — PARTIAL

The full-screen Codex-like TUI is already a strong interface.

Once normal system/module workflows use the shared backend foundations, make `./igor.sh` launch it by default.

Keep CLI/headless paths for scripting, recovery, tests and automation. Preserve `--ai-tui` as a migration alias until removal is clearly safe.

## Step 21 — Integration Rules — FUTURE

Support lightweight knowledge/check/capability rules that only make sense when specific domains interact.

Avoid combinatorial giant modules.

## Step 22 — Module Developer Tooling & External Interfaces — PARTIAL/FUTURE

After Module API v2 is proven:

- converge module create/validate/test/inspect tooling on one supported path;
- generate v2 module skeletons;
- remove duplicate/experimental validators;
- make notification transports consume shared domain events;
- if authenticated mail control is reintroduced, implement it as an interface over shared capabilities/policy/history;
- future API/webhook interfaces use the same engine.

The current repository does not contain the old `core/mailcmd/` implementation; do not plan a migration of code that is not present.

## Step 23 — Igor 2 Consolidation — FUTURE

Before declaring Igor 2 complete:

- remove obsolete v1 compatibility paths;
- remove dead hooks/helpers and duplicate validators;
- remove deprecated configuration paths where migration is complete;
- remove duplicate state/execution paths;
- update primary documentation to the final architecture;
- verify core is application-agnostic;
- run architecture-level regression suites.

No compatibility path survives indefinitely without an explicit reason.
