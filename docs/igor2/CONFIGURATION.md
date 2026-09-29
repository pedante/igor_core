# Igor 2 configuration model and surfaces

Status: **design proposal for architectural review; no implementation is implied by this document**.

This document extends the existing Module API v2 configuration contribution into a future configuration service and user-facing configuration surfaces. It does not replace the Ownership Foundation, capability authority, structured plans, secret mediation, or deployment model. It gives those systems a common configuration vocabulary.

## Product goal

A user should be able to say:

> Set the Nextcloud maximum upload size to 20 GB.

or browse:

~~~text
Nextcloud
└── Uploads
    └── Maximum upload size
~~~

and reach the same canonical setting.

The user should not need to know which file, environment variable, application command, reverse proxy, or database contains the effective setting.

A module describes configuration. Igor owns configured values and secrets. Interfaces present configuration. Capabilities apply configuration. Verification proves the resulting state.

## Architectural invariants

1. A configuration setting has a stable canonical identity independent of its current storage file, UI location, or presentation label.
2. Modules declare configuration schemas and semantics but do not own mutable machine-specific values inside the installed package.
3. A presentation surface is not the configuration source of truth.
4. AI may resolve natural language to registered settings but cannot invent setting identities, dependencies, authority, or successful application.
5. Secrets are represented by mediated references or configured/unconfigured state; secret values do not enter AI context by default.
6. A configured value and the effective observed value are distinct. Changing desired/configured state does not prove the target system accepted it.
7. State-changing configuration is applied through normal Igor capabilities or structured plans and keeps normal approval, privilege, recovery and verification semantics.
8. Configuration storage is behind an Igor service boundary. Modules must not depend on SQLite, environment files, JSON, or another backend directly.
9. Configuration may be scoped to a machine, module, deployment, instance or other future object without changing the canonical setting definition.
10. Configuration relationships are metadata and planning constraints, not a second authorization mechanism.

## Existing foundation

Module API v2 already reserves a configuration contribution kind for namespaced settings, defaults, secret flags, validation and migration metadata. This design evolves that contribution instead of creating another registration hook.

Existing config/variables/*.env and secrets/*.env remain compatibility storage during migration. The immediate goal is to establish one configuration service contract before selecting or migrating to a richer canonical backend.

## Three distinct structures

### Canonical settings tree

Canonical IDs express identity, not menu layout.

~~~text
communications.email.smtp.host
communications.email.imap.host
communications.email.remote.mode

ai.reasoner.provider
ai.reasoner.model
ai.verbose

nextcloud.upload.max_size
nextcloud.maintenance.window
~~~

IDs should remain stable across UI redesigns and storage migrations.

### Presentation tree

A configuration surface groups and orders settings for a human workflow.

~~~text
Communications
└── Email
    ├── Account
    ├── Outbound mail
    ├── Incoming mail
    ├── Administrator identity
    ├── Notifications & reports
    ├── Remote administration
    └── Test & verify
~~~

The same canonical setting may appear in more than one useful presentation context without creating multiple values.

### Dependency and impact graph

Igor needs machine-readable relationships between settings and managed state.

Useful relationship concepts include requires, affects, conflicts_with, derived_from, must_match, must_be_at_least, suggest_follow, invalidates, restart_required and verification.

The final public vocabulary should stay intentionally small and evidence-based; new relationship kinds are added only when real modules need them.

## Conceptual setting declaration

The exact JSON schema remains a later design decision. A setting needs enough metadata to support deterministic validation and useful presentation.

~~~json
{
  "kind": "configuration",
  "id": "nextcloud.settings",
  "settings": [
    {
      "id": "nextcloud.upload.max_size",
      "type": "size",
      "default": "10GiB",
      "scope": "deployment",
      "secret": false,
      "label": "Maximum upload size",
      "aliases": ["max upload", "upload size", "max_uploadsize"],
      "topics": ["uploads", "files", "php", "reverse proxy"],
      "user_help": "Largest individual file users may upload.",
      "ai_help": "This setting coordinates application, PHP and reverse-proxy limits."
    }
  ]
}
~~~

AI help is untrusted reference material. It may explain domain semantics but cannot declare an operation safe, remove approval, grant privilege, create a capability or override Core policy.

## Semantic resolution

Natural-language requests resolve against active registered settings.

~~~text
"make uploads allow 20 gig files"
        ↓
semantic/context resolution
        ↓
nextcloud.upload.max_size
        ↓
typed value normalization
        ↓
configuration change proposal
~~~

Strong exact matches should resolve deterministically. A semantic scout or main reasoner may provide non-authoritative hints for fuzzy language. If multiple settings remain materially plausible, Igor asks a clarification instead of guessing.

AI does not navigate menu paths internally. Presentation trees are for humans; AI resolution targets canonical setting IDs.

## Related and cascading settings

A single intent may require coordinated changes.

~~~text
nextcloud.upload.max_size = 20 GiB
            │
            ├── php.upload_max_filesize >= 20 GiB
            ├── php.post_max_size >= 20 GiB
            └── reverse_proxy.body_limit >= 20 GiB
~~~

Required constraints may become part of one structured plan. Advisory relationships do not silently mutate unrelated settings.

For example:

~~~text
communications.identity.email
    ├── suggest_follow -> notifications.recipient
    ├── suggest_follow -> reports.recipient
    └── affects        -> remote_admin.allowed_sender
~~~

Igor should ask whether optional followers should change, while hard invariants must be satisfied or the plan remains invalid.

## Setting behavior

Not all settings are applied the same way.

- **storage-only** — changing the Igor-owned value is the operation.
- **managed** — the value is desired configuration that requires capabilities or a plan to apply to an external system.
- **derived/read-only** — displayed for context but not editable.

A managed setting may have distinct configured, pending, applied and verification states. Exact lifecycle vocabulary should align with the System Model and history instead of creating duplicate concepts.

## Structured apply path

~~~text
requested setting change
        ↓
validate and normalize
        ↓
resolve relationships / affected settings
        ↓
build structured plan
        ↓
preview approval / privilege / recovery implications
        ↓
execute registered capabilities
        ↓
verify effective state
        ↓
commit/report outcome
~~~

The configuration service does not become another shell dispatcher.

## Configuration surfaces

A configuration surface is a discoverable presentation/workflow contribution, not an arbitrary interactive hook.

A surface may describe pages or groups, fields bound to canonical settings, labels and help, visibility conditions, warnings, ordering, and bounded actions such as discover, test, import, generate, verify or apply.

Most surfaces should be declarative so the same model can be rendered by the classic UI, default TUI, CLI, AI-assisted workflow, future web interface, or installer.

### Bounded actions

Some setup cannot be represented by fields alone: OAuth/device authorization, key import/generation, disk or deployment discovery, testing SMTP/IMAP, discovering local models, or validating a remote API.

A surface may reference registered typed handlers or capabilities for these actions. It must not embed arbitrary shell command strings as executable configuration.

## Launching a surface from Igor

~~~text
conversation
    ↓
"configure email"
    ↓
communications.email surface
    ↓
interactive child/configuration session
    ↓
structured completion result
    ↓
original conversation resumes
~~~

The parent Igor session remains authoritative. A surface cannot bypass policy, secret mediation or capability execution merely because it was launched from AI.

## Installation and partial availability

Module installation and configuration are distinct.

~~~text
package installed
    ↓
configuration requirements inspected
    ↓
configuration surface offered
    ↓
values collected
    ↓
apply plan
    ↓
verification
    ↓
deployment record
~~~

A module may remain installed but partially unavailable when required settings are missing. The unavailable reason should identify missing configuration rather than failing later through an unset variable.

## Scopes and multiple instances

Potential scopes include global, machine, module, deployment, instance and user. Only real scopes need implementation initially, but APIs and storage must not assume one value per module forever.

~~~text
deployment:personal / nextcloud.upload.max_size
deployment:family   / nextcloud.upload.max_size
~~~

Step 17 deployment and relationship records are the natural place to attach deployment/instance scope.

## Secrets

A secret setting stores or returns a mediated reference instead of exposing its value through normal configuration inspection.

~~~text
communications.email.smtp.password
    -> secret://communications/email/smtp_password
~~~

Inspection may expose configured state, timestamp and owner, but not the value. Consumers resolve the value only through Igor secret authorization, with use auditable where practical.

## Storage backend

The service contract, not a file format, is the permanent API.

~~~text
Configuration Service
    ├── env compatibility backend
    └── future richer backend
~~~

SQLite is a strong future candidate because it is transactional, serverless, low-resource, available through Python on normal builds, and suitable for relationships and scoped values. Selecting SQLite does not make SQL or table layout part of the module API.

A possible future shape is data/config/config.db with human-readable export/recovery support. Backups should include a readable configuration export so recovery does not depend on a working UI.

Secrets may remain in a separate backend even if non-secret values move to SQLite.

## Transactions and coordinated changes

A richer backend should support atomic updates to Igor-owned desired/configured state when several related values form one logical change.

This does not imply that external system changes are transactionally reversible. External application uses normal plan recovery semantics from D028/D030.

## Inspection

The configuration authority should expose read-only inspection as soon as it becomes authoritative.

~~~text
config list
config inspect <setting>
config effective <setting>
config explain <setting>
config export
~~~

Inspection should reveal provenance, scope, configured/default/effective state, availability reasons and relationships without revealing secrets.

## Migration

Moving from direct environment-file consumers to the configuration service requires explicit cutover:

1. identify the legacy source;
2. import and normalize the value;
3. validate it against the registered schema;
4. preserve or back up the old source where appropriate;
5. switch the consumer to the configuration service;
6. verify equivalent behavior;
7. prevent indefinite dual-source ambiguity;
8. remove the legacy path only after documented consumers migrate.

Environment files may remain supported import/export formats after they stop being Igor's canonical internal configuration model.

## Relationship to AI settings

The current special AI settings writer is a future candidate consumer.

~~~text
ai.reasoner.provider
ai.reasoner.model
ai.reasoner.temperature
ai.reasoner.max_tokens
ai.verbose
~~~

Future model roles naturally extend the namespace:

~~~text
ai.semantic_scout.provider
ai.semantic_scout.model
ai.log_compressor.provider
ai.log_compressor.model
~~~

## Non-goals

This design does not require replacing every environment file immediately, selecting a final SQLite schema now, a web UI, arbitrary hot module reconfiguration, generic rollback of external configuration, AI-generated setting identities, configuration metadata as authorization, or every possible scope before a real use case.

## Roadmap fit

- Ownership Foundation: configuration, secret and persistent-state ownership.
- Module API v2: configuration remains an owner-stamped contribution.
- Step 17: deployment/instance scope and provenance.
- Step 20: default TUI can render shared configuration surfaces.
- Step 22: developer tooling validates configuration descriptors and external interfaces consume the same service.
- Step 23: obsolete direct config paths are removed only after explicit cutover.

## Proof requirements for implementation

1. **Contract proof** — malformed descriptors, duplicate IDs, invalid types, secret misuse and inactive owners fail closed.
2. **Regression proof** — legacy config consumers work during documented compatibility.
3. **Vertical-slice proof** — one real setting can be inspected, changed, applied where necessary and verified.
4. **Inspection proof** — configured/effective/provenance state is visible without exposing secrets.
5. **Migration/recovery proof** — an existing-style configuration migrates idempotently and can export/recover without dual-source ambiguity.

## Questions left for later decisions

- exact descriptor schema and initial relationship vocabulary;
- first implemented scopes;
- when SQLite becomes canonical rather than experimental;
- how much configuration history belongs in configuration storage versus Step 15 history;
- exact TUI suspend/resume protocol for interactive surfaces;
- whether managed-setting application uses generic or module-specific plan templates.
