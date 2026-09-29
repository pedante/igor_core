# Configuration Model & Surfaces — design proposal

Status: **design proposal; no implementation in this PR**.

This document extends the existing Module API v2 configuration contribution
into a future Igor-owned configuration service. It does not change current
.env loading, secrets, module activation, or capability execution.

The goal is to make configuration a first-class Igor concept rather than a
collection of file locations and interactive shell menus.

## Problem

Today Igor configuration is primarily expressed as files and shell variables.
That is simple and useful, but it becomes limiting when Igor needs to answer or
perform requests such as:

- "Set the Nextcloud maximum upload size to 20 GB."
- "Change my administrator email address."
- "What else depends on this setting?"
- "Configure Cloudflare."
- "Open the email setup, then return me to this AI conversation."
- "Why is this module installed but not fully usable?"
- "Which deployment does this setting belong to?"

A module should not need to teach every interface which file and line contains a
setting. A TUI, CLI, AI session, installer and future external interface should
all resolve the same canonical configuration objects.

## Core principle

**Modules describe configuration. Igor owns configuration. Interfaces present
configuration. Capabilities apply configuration. Verification proves
configuration.**

The module package owns the schema and domain meaning. Mutable machine-specific
values, secret references, provenance, lifecycle and storage remain Igor-owned.

Configuration metadata never grants execution authority. The existing
capability, policy, approval, privilege and verification boundaries remain
authoritative.

## Configuration model versus configuration surface

These are separate contracts.

### Configuration model

The model defines what can be configured and what it means:

- canonical setting identity;
- owner/module;
- data type and constraints;
- default;
- scope;
- secret status;
- user-facing description/help;
- non-authoritative AI semantic metadata;
- relationships to other settings;
- apply/verification semantics;
- requirements and availability.

The model is stable independent of storage and UI.

### Configuration surface

A surface describes how configuration may be presented or collected:

- pages/groups/sections;
- ordering;
- labels and help;
- conditional visibility;
- setup/review flows;
- bounded actions such as discover, test, import, generate, verify and apply.

A surface is presentation/workflow metadata, not the source of truth.

Most modules should be able to provide useful configuration without writing a
custom interactive Bash wizard.

## Stable canonical setting IDs

A setting has a stable namespaced ID, for example:

    communications.email.smtp.host
    communications.email.imap.host
    communications.identity.email
    ai.reasoner.provider
    ai.reasoner.model
    nextcloud.upload.max_size

Canonical IDs do not encode the file path where a value happens to be stored and
do not encode a TUI/menu path.

Human aliases and semantic tags may be attached, for example:

    id: nextcloud.upload.max_size
    aliases:
      - max upload
      - maximum upload size
      - max_uploadsize
      - largest upload
    topics:
      - uploads
      - files
      - php
      - reverse proxy

AI-generated interpretation may help select a registered setting, but it cannot
invent one. Ambiguous material matches require clarification.

## Direct semantic configuration

The AI should not "navigate the menu" internally.

For:

    Change max_uploadsize of Nextcloud to 20 GB.

the intended flow is:

    user language
      -> semantic/context selection
      -> registered canonical setting
      -> typed value validation
      -> relationship/impact evaluation
      -> structured change plan if needed
      -> normal capability/policy boundary
      -> verification

The human presentation tree remains useful for browsing, but it is not the API
used by the AI.

## Setting classes

At minimum the design must distinguish:

### Stored setting

An Igor-owned value whose change primarily updates configuration, for example
AI verbosity or a notification recipient.

### Managed setting

A desired setting whose effective application requires operational work, for
example a Nextcloud upload limit that must coordinate Nextcloud/PHP/proxy
configuration and service reloads.

Changing a managed setting produces or resolves a structured plan; it is not
implemented as arbitrary file editing.

### Derived/read-only value

Context displayed beside configuration but obtained from observation or another
authoritative source, such as detected version, current available RAM or a
discovered installation path.

Derived values are not silently converted into writable configuration.

## Relationships and impact graph

Settings may declare typed relationships. The initial contract should remain
small and deterministic rather than becoming a general rule language.

Useful relationship semantics include:

- requires: another setting/value/capability is necessary;
- affects: changing this setting may invalidate or change another area;
- must_match: values must remain equal or compatible;
- must_be_at_least: a numeric/size constraint;
- conflicts_with: two states may not coexist;
- suggest_follow: related user intent should be offered, not assumed;
- invalidates: previous verification/effective state becomes stale;
- restart_required: application requires a named managed operation;
- verification: identifies the check/capability used to prove effective state.

Example:

    nextcloud.upload.max_size = 20 GiB

may require an apply plan that coordinates:

    php.upload_max_filesize >= 20 GiB
    php.post_max_size >= 20 GiB
    reverse_proxy.body_limit >= 20 GiB

By contrast, changing an administrator email may only suggest_follow for
notification/report recipients and remote administrator identity. Igor should
ask rather than silently rewrite all related settings.

Relationships describe configuration consequences. They never authorize the
required operations.

## Three trees, one configuration model

The same settings may participate in different structures.

### Canonical identity tree

Stable programmatic namespaces, independent of UI.

### Presentation tree

Human navigation such as:

    Communications
      Email
        Account
        Outbound
        Inbound
        Administrator identity
        Remote administration
        Test & verify

Different interfaces may render the same model differently.

### Dependency/impact graph

Machine-readable relationships used for validation, explanation and planning.

These structures must not be conflated.

## Scopes and future multiple instances

A setting descriptor must not assume one value per module forever.

The contract should leave room for explicit scopes such as:

- global;
- machine;
- module;
- deployment;
- instance;
- user.

Only scopes with real consumers should be implemented. The important design
constraint is that canonical identity and storage must not prevent a later
deployment/instance scope.

This connects to Step 17 relationships and deployments.

## Configuration state

Igor should be able to distinguish at least:

- default;
- configured/desired;
- effective/applied;
- verification status;
- source/provenance;
- unavailable/invalid reason.

Configured intent must not be confused with observed/effective state.

For a managed setting, storing the desired value does not prove the application
now uses it.

## Provenance

Where useful, configuration state should retain non-secret provenance such as:

- owner/schema source;
- scope;
- source: default, user, installer, migration, policy or imported legacy value;
- change time;
- apply/verification state;
- related plan/operation identity.

Chat history is never the authoritative provenance store.

## Secrets

Secret settings use the same configuration identity but not the same ordinary
value exposure.

A descriptor may mark a setting secret. Igor then exposes status/reference
rather than the value where possible:

    communications.email.smtp.password
      -> secret://communications/email/smtp_password

AI context may see "configured" or an approved reference but does not receive
the secret by default.

Secret storage and secret use remain mediated and auditable under D027.

## Storage backend

Module code must depend on the Configuration Service API, not on SQLite or a
particular .env file.

Current .env files remain a valid compatibility/import/export backend during
migration.

A future canonical backend may use SQLite because it provides:

- atomic multi-setting transactions;
- indexed scopes and relationships;
- provenance/status fields;
- low resource usage;
- no background database service;
- Python standard-library support on normal builds.

SQLite is a likely backend, not part of the module public API.

Do not create a single undifferentiated "Igor database" merely because SQLite
is available. Persistent ownership boundaries remain explicit.

## Portability and recovery

A database backend must not make configuration opaque or unrecoverable.

The Configuration Service should support deterministic inspection/export, for
example conceptually:

    igor config list
    igor config get <setting>
    igor config inspect <setting>
    igor config export
    igor config export --module <owner>

Backups should be able to include a human-readable structured export in
addition to the canonical backend.

Persistent backend migration follows D031: explicit source, target, validation,
idempotency/re-entry, verification and recovery/cutover.

## Configuration surfaces

A configuration surface references registered settings and optional bounded
actions. It does not store independent values.

A declarative surface may provide:

- title/description;
- groups/pages;
- setting references;
- conditional visibility;
- warnings;
- completion requirements;
- review summary;
- actions.

Example conceptual email surface:

    Email & Remote Administration
      Account
      Outbound SMTP
      Incoming IMAP
      Administrator identity
      Notifications
      Reports
      Remote conversation
      Remote administration
      Test & verify

## Bounded surface actions

Some setup cannot be expressed as fields alone. Surfaces may reference bounded,
owned actions such as:

- discover;
- test;
- import;
- generate;
- verify;
- apply.

Examples:

    communications.email.smtp.test
    communications.email.imap.test
    communications.identity.import_key

These actions resolve through typed Igor handlers/capabilities. A surface cannot
smuggle arbitrary shell text into execution.

## Launch and return contract

An interface should be able to launch a configuration surface temporarily and
resume the originating interaction.

Conceptual flow:

    AI/TUI conversation
      -> launch configuration surface
      -> collect/test/apply
      -> structured completion result
      -> resume original interaction

The caller receives a structured result such as completed, cancelled, partial,
failed or waiting_external plus changed setting IDs and verification summary.
The configuration surface does not own the parent conversation.

This makes "configure email" or "configure Nextcloud" usable from inside Igor
without discarding task context.

## Installation/configuration integration

Installation and configuration are distinct.

A future install flow may:

    install package
      -> validate/activate available contributions
      -> detect required missing configuration
      -> offer configuration surface
      -> persist desired configuration
      -> resolve apply plan
      -> approval/privilege
      -> execute
      -> verify
      -> record deployment

An installed module may remain partially usable while one contribution is
unavailable because required configuration is absent. Failure reasons should be
specific.

## AI integration

AI receives configuration descriptors and safe state through the normal Context
Engine. Module-provided AI help is reference material only.

The AI may:

- resolve user language to registered settings;
- explain settings and consequences;
- propose related changes;
- open an appropriate configuration surface;
- propose a structured apply plan.

The AI may not:

- create undeclared settings;
- bypass validation;
- reveal secrets by default;
- change policy/safety metadata;
- treat descriptive module prose as authorization.

Current special AI settings should eventually become clients of the same
Configuration Service so model/provider/temperature/etc. are not a permanent
one-off settings subsystem.

This also leaves clean namespaces for future model roles such as
ai.semantic_scout.model.

## External/user waits

Configuration workflows may require OAuth, device authorization, DNS
propagation, external commands or administrator action. Configuration surfaces
must not implement indefinite blocking loops.

Such work uses the separate Resumable Work contract: persist a structured
waiting state, return control, verify the external condition, then resume.

## Inspection

When the Configuration Service becomes authoritative it must expose enough
read-only inspection to answer:

- which settings exist and who owns them;
- effective scope;
- configured versus default/effective state;
- secret configured/not-configured status without revealing values;
- relationship/impact edges;
- validation/unavailability reasons;
- surface membership;
- apply/verification status where applicable.

## Compatibility and migration

V1 module declarations such as variables_file and secrets_files remain
compatibility inputs until migrated.

The migration should move consumers toward:

    module -> Configuration Service

instead of:

    module -> grep/source arbitrary config path

Do not remove working .env paths until equivalent configuration, export and
recovery behavior is proven.

## Relationship to roadmap

This design spans existing roadmap concerns rather than creating a new wave:

- Ownership Foundation: canonical config/secret ownership;
- Module API v2: richer configuration contributions;
- Step 17: deployment/instance scopes and provenance;
- Step 20: rich TUI configuration surfaces;
- Step 22: developer tooling/external configuration interfaces;
- Step 23: retire deprecated config paths after migration proof.

Implementation sequencing is intentionally deferred until the proposal is
accepted and reconciled with the roadmap.

## Non-goals of this proposal

This document does not:

- implement a SQLite backend;
- migrate existing .env files;
- create a generic expression/rule language;
- redesign secret storage;
- add a web UI;
- execute configuration directly from model output;
- require all modules to migrate at once;
- implement resumable external authorization.

## Proposed design decisions for reconciliation

Decision numbers are intentionally not assigned in this PR to avoid conflicts
with parallel design proposals.

1. Configuration identity and semantics are module-declared, while mutable
   values/lifecycle/storage are Igor-owned.
2. Configuration models are separate from configuration surfaces.
3. Canonical setting IDs are independent of file paths and presentation paths.
4. Relationships may expand a requested change into validation or a structured
   apply plan, but never into authorization.
5. Secret settings expose references/status by default, not values.
6. Storage is behind a Configuration Service API; .env remains transitional
   and SQLite is a likely low-resource canonical backend, not a module API.
7. Managed settings use normal capabilities/plans and deterministic
   verification.
8. Interfaces may launch a configuration surface and resume the originating
   interaction with a structured result.
9. External/user dependencies use the separate resumable-work mechanism rather
   than blocking configuration indefinitely.
