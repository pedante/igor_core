# Module API v2 — target contract

Status: **design target, not yet implemented**.

The current module contract is documented in `docs/module_creation.md`; current activation/runtime semantics are documented in `docs/module_lifecycle.md`.

The existing loader already provides explicit enable/disable policy, active/unavailable state and owner-aware registrations. Module API v2 must evolve that runtime rather than create a second plugin system.

## Purpose

A module teaches Igor how to understand and operate a coherent domain.

A module is not merely a menu bundle or a list of prompt hooks.

## Runtime semantics

Igor 2 requires these concepts, but does not require renaming the current implementation solely for vocabulary:

- **installed/available** — module package exists and can be inspected;
- **enabled** — administrator policy allows activation;
- **disabled** — policy prevents activation;
- **active/loaded** — initialization and registration succeeded in this process;
- **unavailable/failed** — enabled but requirements/initialization prevented activation.

Only active modules may contribute runtime behavior.

Restart-based activation is acceptable. Hot unloading is not a v2 requirement unless a future use case justifies it.

## Versioning

The v2 contract is explicitly versioned, for example:

```text
module_api = 2
```

Unsupported contracts are rejected clearly or handled through an explicit compatibility adapter. Compatibility is never silently guessed.

## Contract areas

A module may implement any subset of the following.

### Identity

- canonical module name;
- display name;
- module/API version;
- coherent domain;
- compatibility constraints;
- dependencies/requirements.

### Knowledge

Durable reference knowledge:

- architecture;
- terminology;
- normal behavior;
- failure modes;
- operating constraints;
- troubleshooting guidance.

Knowledge is not live state and cannot authorize operations or change Igor policy.

### Observers

Deterministic ways to discover domain state.

Observers may declare:

- produced fact/object types;
- cost;
- freshness;
- timeout;
- privilege requirement;
- dependencies.

Observers populate Igor-owned state instead of primarily returning arbitrary prompt text.

### Capabilities

Canonical actions the module can perform.

A capability should expose:

- canonical name;
- owner;
- description;
- input schema;
- safety tier;
- privilege requirement;
- preconditions;
- execution;
- verification;
- optional rollback;
- affected object types;
- domain events;
- platform requirements.

The existing action catalog / `run_igor_action` path is the migration seed.

### Checks

Checks evaluate structured state and produce results reusable by Diagnose, Health, Healing, AI, notifications and history.

File presence alone is never activation authority.

### Domain events

A module may emit and/or consume operational event types.

These are distinct from the existing AI frontend activity stream. Prefer domain events/relationships over direct calls into unrelated modules.

### Automations

A module may propose scheduled, periodic, conditional or event-driven behavior.

Igor owns activation, scheduling, safety, privilege, retries, history and notification/escalation.

Modules do not create unmanaged cron jobs as their normal contract.

### Relationships

A module defines relationship types meaningful to its objects and may discover/propose relationships.

Relationships connect domain instances without requiring giant combination modules.

### Configuration

A module declares configuration schema, defaults, sensitive fields, validation and migration.

The final manifest/schema representation is an open decision. Do not hard-code a v2 format before that decision is accepted.

### Lifecycle

Lifecycle may cover:

- enable/disable policy;
- install/bootstrap of managed resources;
- upgrade/migrate;
- uninstall/remove.

Removing a module package is distinct from destroying the resources it manages.

## Dependencies

The v2 design must distinguish conceptually:

- hard module dependency;
- optional integration;
- capability requirement;
- platform requirement.

Prefer capability requirements when the provider implementation does not matter.

Exact representation/resolution remains an open decision.

## Composition

Modules represent domains; deployments represent connected instances.

Example:

```text
nextcloud:home
  hosted_by -> docker:compose/home
  exposed_by -> cloudflare:tunnel/home
```

Do not split `nextcloud_docker` before relationships/composition contracts exist.

## Integration rules

Some behavior exists only at domain boundaries. Igor 2 may support lightweight integration rules activated by domain presence/relationships.

Physical ownership/packaging remains an open decision.

## Trust

Current modules are trusted local executable code; the registry is not a sandbox.

For AI reasoning, module prose remains reference data. It may inform decisions but cannot alter authorization, safety or privilege policy.

A future third-party module ecosystem may require explicit trust/permission/signing rules. The v2 contract must leave room for them.

## Migration rule

Preserve working v1 modules and the current activation boundary while v2 is designed.

Prove v2 with real modules before removing v1 compatibility.
