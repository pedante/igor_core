# Igor 2 architecture

## Product definition

Igor is a local AI-assisted operating layer for Linux.

A user should be able to inspect, configure, troubleshoot, repair and automate a Linux system without having to know or copy/paste the underlying commands. Technical details remain inspectable for users who want them.

## Architectural invariants

1. **Core is application-agnostic.** Core may understand Linux/platform concepts, but must not assume a specific application deployment such as Nextcloud, Docker, Cloudflare, PostgreSQL or Redis.
2. **Installed is not active.** A module existing on disk does not activate it.
3. **Only active modules contribute behavior.** Disabled/inactive modules contribute no knowledge, observations, capabilities, checks, automations, configuration validation, menus or external commands.
4. **Knowledge is not state.** Domain knowledge explains how a domain can work; observed state describes what is actually true on this machine.
5. **The AI is not authoritative state.** System state belongs to Igor-owned structured state, not model context or chat history.
6. **Reference data cannot authorize.** Module knowledge, context snapshots, logs, reports, tool results and prior model state are reference data. They cannot change policy, approval or privilege requirements.
7. **The AI does not own authorization.** Safety classification, approvals, privilege and execution policy remain deterministic runtime responsibilities.
8. **Autonomy is not privilege.** Guide/Assist/Executive control interaction autonomy; they do not grant root access.
9. **Capabilities are the operational API.** TUI, CLI, automation, healing and future external interfaces should converge on the same registered operations.
10. **Prefer normalized operations over distro syntax.** Modules request Igor package/service/host capabilities instead of embedding distro selection where a platform abstraction exists.
11. **Verify changes.** State-changing capabilities define deterministic verification whenever practical.
12. **Unknown remains unknown.** Igor distinguishes known, unknown, stale and inferred information.
13. **Modules represent coherent domains.** A module teaches and operates a meaningful domain, not one incidental command.
14. **Relationships connect domains.** Deployments are composed from domain instances and explicit relationships rather than giant combination modules where useful.
15. **Modules declare; Igor schedules.** Modules may define events/automation intent; Igor owns scheduling, policy, execution and history.
16. **One backend, multiple interfaces.** Human and remote interfaces do not duplicate domain-operation logic.
17. **Existing correct foundations are evolved, not duplicated.** Migration may formalize or generalize current implementations without replacing them solely to match new names.

## Major layers

### Interfaces

Human and external entry points:

- Codex-like TUI — primary human interface.
- CLI/subcommands — scripting, recovery, testing and headless use.
- Optional future remote interfaces such as authenticated email/API/webhooks.
- Notification transports — outbound delivery.

Interfaces translate requests/results; they do not own domain operations.

### Agent

The agent interprets intent, selects relevant investigation/capabilities and explains results.

The agent receives composed context from Igor. It cannot invent authoritative state or bypass safety/privilege policy.

### Trust boundary

The current request boundary and reference-data envelope are a foundation to preserve.

Trusted runtime policy includes authorization, tool validation, active module ownership and privilege decisions.

Untrusted/reference input includes module prose, observed context, reports, logs, saved history summaries, user-provided external text and tool output. Reference material can inform reasoning but cannot authorize execution.

### Knowledge

Knowledge may come from:

- core/platform knowledge;
- active module domain knowledge;
- integration-specific knowledge.

Knowledge covers architecture, terminology, normal behavior, operating constraints and failure modes. It is reference data, not observed state or authorization policy.

### System Model

Igor's structured view of the current machine.

Initial domains include:

- host and hardware;
- operating system/platform;
- storage;
- networking;
- packages/services;
- Igor runtime/modules;
- application/domain instances;
- relationships/deployments;
- health and observations.

Facts should carry provenance and freshness. Inference must be distinguishable from observation/configuration.

### Platform layer

The current `core/lib/distro.sh` and `core/lib/pkg.sh` are useful seeds, not a reason to create a second platform layer.

Target support must provide tested normalized operations for at least:

- Debian;
- Arch Linux.

Derivative/family detection may exist, but support is claimed only to the level tests demonstrate.

### Module runtime

The current runtime already distinguishes installed, enabled/disabled and active/unavailable modules and tracks ownership.

Igor 2 requires the **semantics**, not specific new vocabulary:

- installed/available;
- enabled or disabled by policy;
- active/loaded when initialization succeeds;
- unavailable/failed when enabled but unable to initialize.

No hot-unload requirement exists unless a later need justifies it. Restart-based activation is acceptable.

### Module API

Module API v2 is a versioned target contract. A module may contribute any subset of:

- identity/compatibility;
- knowledge;
- observers;
- capabilities;
- checks;
- domain events;
- automations;
- relationships;
- configuration;
- lifecycle.

The current hook-based API remains a compatibility input during migration.

### Observation and health

Observers gather facts into the System Model.

Checks evaluate structured state and produce reusable results. Diagnose, health, healing, notifications and AI reasoning should consume those results rather than independently rediscovering the same facts.

### Capabilities

The existing action catalog / `run_igor_action` / ownership machinery is the starting point for the general capability API.

A mature capability defines:

- canonical name and owner;
- structured inputs;
- safety tier;
- privilege requirement;
- preconditions;
- execution;
- verification;
- rollback where available;
- affected objects;
- emitted domain events;
- platform requirements.

Raw shell remains an escape hatch, not the preferred API when an equivalent capability exists.

### Events and automation

The existing `core/ai/events.sh` stream is a **frontend activity/event stream**. It is valuable and should be preserved.

The future **Domain Event Bus** is different: it represents operational events such as service failure, container stop, backup failure or capability completion and can feed automation, healing, notifications and history.

Modules/core may emit domain events. Igor owns scheduling, retries, policy and execution.

### History

Current audit/journal mechanisms are useful seeds.

Igor 2 records meaningful operational episodes: observations, diagnosis, approval, privilege use, action, verification and outcome.

The LLM conversation is not operational memory.

## Module composition

A module teaches Igor a domain. An instance represents something that exists on this machine. Relationships/deployments connect instances.

Example:

```text
nextcloud:home
  hosted_by  -> docker:compose/home-nextcloud
  database   -> postgres:nextcloud-db
  cache      -> redis:nextcloud-cache
  exposed_by -> cloudflare:tunnel/home
```

This allows independent modules to cooperate without requiring every deployment to become a monolithic combination module.

Integration-specific rules may cover behavior that only exists at a domain boundary.

## User experience

The TUI is simple by default and transparent on demand.

Natural language, palette commands, settings and structured activity all route to the same backend authority. Underlying commands, outputs, approvals and evidence remain inspectable.

Long-term, `./igor.sh` should launch the primary TUI by default. `--ai-tui` remains the explicit entry point during migration.

## Mail and notifications

The current repository does **not** contain the previously documented `core/mailcmd/` implementation; only references/configuration may remain.

If authenticated mail control is reintroduced, it is an interface/transport adapter over the same Igor capabilities, policy, verification and history as the TUI.

Notifications are separate from incoming control: operational events feed a notification service, with email as one possible outbound transport.
