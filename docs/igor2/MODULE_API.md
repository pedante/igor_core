# Module API v2 — target contract

Status: **design target, not yet implemented**.

The current module contract is documented in `docs/module_creation.md`. That documentation remains authoritative for Module API v1 until migration occurs.

## Purpose

A module teaches Igor how to understand and operate a coherent domain.

A module is not merely a menu bundle or a collection of hooks.

Installing a module makes a domain available. Enabling/loading it may contribute knowledge, observations and abilities to the current Igor runtime.

## Runtime states

Target states:

- **available** — package exists and can be inspected;
- **enabled** — administrator configuration says it participates in this installation;
- **loaded** — initialization succeeded for the current runtime;
- **failed** — enabled but initialization failed;
- **disabled** — present but intentionally inactive.

Only loaded modules may contribute runtime behavior.

## Versioning

The v2 contract must be explicitly versioned, for example:

```text
module_api = 2
```

Igor must reject unsupported contracts clearly or use an explicit compatibility layer. Compatibility must never be inferred silently.

## Contract areas

A module may implement any subset of the following.

### Identity

Defines:

- canonical module name;
- display name;
- module version;
- module API version;
- domain;
- compatibility constraints;
- dependencies.

### Knowledge

Durable domain knowledge for reasoning:

- architecture;
- terminology;
- normal behavior;
- known failure modes;
- operating constraints;
- troubleshooting guidance.

Knowledge is not live system state.

### Observers

Deterministic ways to discover domain state.

Observers should declare enough metadata for Igor to manage them, including where applicable:

- produced fact/object types;
- cost;
- freshness;
- timeout;
- privilege requirement;
- dependencies.

Observers populate Igor-owned state rather than returning arbitrary prompt text as the primary contract.

### Capabilities

Canonical actions the module can perform.

A capability should expose:

- canonical name;
- description;
- input schema;
- safety tier;
- privilege requirement;
- preconditions;
- execution;
- verification;
- optional rollback;
- affected object types;
- emitted events;
- supported platforms/requirements.

Capabilities are reusable by every Igor interface and automation path.

### Checks

Checks evaluate state and produce structured results usable by Diagnose, Health, Healing, AI and notifications.

Checks should not be independently auto-discovered merely because a file exists in a module directory.

### Events

A module may emit and/or consume defined event types.

Event handling should prefer structured contracts over direct calls into unrelated modules.

### Automations

A module may propose scheduled, periodic, conditional or event-driven behavior.

Igor owns:

- enable/disable state;
- scheduling;
- safety policy;
- privilege handling;
- retries;
- history;
- notification/escalation.

Modules do not create unmanaged cron jobs as their normal integration path.

### Relationships

A module defines relationship types meaningful to its objects and may discover/propose relationships.

Relationships connect instances from different domains without requiring giant combination modules.

### Configuration

A module declares configuration schema, defaults, sensitive fields, validation and migration.

The final manifest/config representation is an open design decision; do not hard-code a v2 format before that decision is accepted.

### Lifecycle

Lifecycle covers installation-specific operations such as:

- enable/disable;
- install/bootstrap;
- upgrade/migrate;
- uninstall/remove.

Lifecycle behavior must distinguish removing a module package from changing/removing the domain resources it manages.

## Dependencies

Module API v2 must distinguish at least conceptually:

- hard module dependency;
- optional module integration;
- capability requirement;
- platform requirement.

A dependency on a capability is preferable when the implementation provider does not matter.

Exact semantics remain an open decision.

## Composition

Modules represent domains; deployments represent connected instances.

Example:

```text
nextcloud:home
  hosted_by -> docker:compose/home
  exposed_by -> cloudflare:tunnel/home
```

This allows Docker, Nextcloud and Cloudflare to remain reusable domains.

## Integration rules

Some behavior exists only at domain boundaries. Igor 2 may support lightweight integration rules activated by the presence/relationship of specific domains.

The physical ownership/packaging of these rules remains an open decision.

## Trust

Third-party modules may eventually provide executable code, knowledge and automation definitions.

The v2 design must leave room for an explicit trust/permission model. Exact signing/sandbox policy is not yet decided.

## Migration rule

Do not split `nextcloud_docker` merely to satisfy this document.

First establish the runtime/contracts and compatibility path; then use the existing working deployment as a regression fixture and composition proof case.
