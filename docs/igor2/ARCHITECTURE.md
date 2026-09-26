# Igor 2 architecture

## Product definition

Igor is a local AI-assisted operating layer for Linux.

A user should be able to inspect, configure, troubleshoot, repair and automate a Linux system without having to know or copy/paste the underlying commands. Technical details remain inspectable for users who want them.

## Architectural invariants

1. **Core is application-agnostic.** Core may understand Linux/platform concepts, but it must not assume a particular application deployment such as Nextcloud, Docker, Cloudflare, PostgreSQL or Redis.
2. **Installed is not active.** A module directory existing on disk does not activate that module.
3. **Only active modules contribute behavior.** Disabled modules contribute no knowledge, observations, capabilities, checks, events, automations, configuration validation, menus or external commands.
4. **Knowledge is not state.** Domain knowledge describes how something can work. Observed state describes what is actually true on this machine.
5. **The AI is not authoritative state.** System state lives in Igor-owned structured state, not in model context or chat history.
6. **The AI does not own authorization.** Safety classification, approvals, privilege and execution policy are deterministic runtime responsibilities.
7. **Autonomy is not privilege.** Guide/Assist/Executive control how independently Igor may act; they do not grant root access.
8. **Capabilities are the operational API.** TUI, CLI, automation, healing, email and future interfaces should invoke the same registered capabilities.
9. **Prefer normalized operations over distro syntax.** Modules should request Igor operations such as package/service actions instead of embedding Debian/Arch command selection when an Igor platform capability exists.
10. **Verify changes.** A state-changing capability should define deterministic verification whenever practical.
11. **Unknown remains unknown.** Igor distinguishes known, unknown, stale and inferred information instead of silently filling gaps.
12. **Modules represent coherent domains.** A module should teach and operate a meaningful domain, not be a wrapper around one incidental command.
13. **Relationships connect domains.** Deployments are composed from module-owned instances and explicit relationships rather than giant combination modules where possible.
14. **Modules declare; Igor schedules.** Modules may provide events and automation definitions, but Igor owns scheduling, policy, execution and history.
15. **One backend, multiple interfaces.** Human and remote interfaces must not duplicate operating logic.

## Major layers

### Interfaces

Human and external entry points:

- Codex-like TUI — primary human interface.
- CLI/subcommands — scripting, recovery, testing and headless use.
- Email control — authenticated remote interface.
- Notification transports — outbound delivery only.
- Future API/webhook interfaces.

Interfaces translate requests/results; they do not own domain operations.

### Agent

The agent interprets intent, selects relevant investigation and capabilities, and explains results.

The agent receives composed context from Igor. It does not invent system state or bypass safety/privilege policy.

### Knowledge

Two sources:

- core/platform knowledge;
- active module domain knowledge.

Knowledge may describe architecture, terminology, operating rules, common failure modes and reasoning guidance.

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

Facts should carry provenance and freshness. Inference must be distinguishable from observation.

### Platform layer

Provides normalized Linux operations with tested backends.

Initial tested targets:

- Debian;
- Arch Linux.

Derivatives are not automatically claimed as supported merely because they share a package family.

### Module runtime

Manages module discovery, activation, loading, dependencies, lifecycle and compatibility.

Target lifecycle states:

- available;
- enabled;
- loaded;
- failed;
- disabled.

### Module API

A module may contribute any subset of:

- identity/compatibility;
- knowledge;
- observers;
- capabilities;
- checks;
- events;
- automations;
- relationships;
- configuration;
- lifecycle.

The contract is versioned.

### Observation and health

Observers gather facts into the System Model.

Checks evaluate structured state and produce reusable health/diagnostic results. Diagnose, self-healing, notifications and the AI consume those results rather than independently rediscovering the same facts.

### Capabilities

Capabilities are canonical operations with structured metadata:

- name;
- owner;
- inputs;
- safety tier;
- privilege requirements;
- preconditions;
- execution;
- verification;
- rollback where available;
- affected objects;
- emitted events;
- supported platforms.

Raw shell remains an escape hatch, not the preferred API when a capability exists.

### Events and automation

Modules and core can emit structured events. Igor owns the event bus, scheduling, retries, policy and execution.

Automations may be:

- scheduled;
- periodic;
- event-driven;
- conditional.

### History

Igor records meaningful operational episodes: observations, diagnosis, action, approval, privilege use, verification and outcome.

The LLM conversation is not Igor's operational memory.

## Module composition

Module installation teaches Igor a domain. A deployment describes which instances are connected on this machine.

Example:

```text
nextcloud:home
  hosted_by -> docker:compose/home-nextcloud
  database  -> postgres:nextcloud-db
  cache     -> redis:nextcloud-cache
  exposed_by -> cloudflare:tunnel/home
```

This allows independent modules to cooperate without forcing every deployment into a monolithic combination module.

Integration-specific knowledge may exist as lightweight integration rules when two domains interact in ways neither module can express alone.

## User experience

The TUI should be simple by default and transparent on demand.

Normal interaction happens through natural language, commands/palette entries, settings and structured activity. Underlying commands, outputs, approvals and evidence remain inspectable.

Long-term, `./igor.sh` should launch the primary TUI by default. `--ai-tui` can remain as a compatibility alias during migration.

## Mail and notifications

Mail control is an interface, not a domain module and not an independent operating engine.

Its responsibilities should be separated into:

- mail transport/authentication/encryption;
- Igor request/result adapter;
- shared configuration/secrets.

Incoming mail should invoke the same capabilities, policy, verification and history as the TUI.

Notifications are a separate concept: events flow to a notification service which may use email or future transports.
