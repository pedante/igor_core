# Configuration, Secrets and Ownership Foundation — Boundary A

Status: **discovery complete; implementation proposal, not accepted architecture**.
Audit date: 2026-10-05. Audited checkout: `igor2`,
`8850b6777345e1bee27a2982f0cea8f2d96c6198`; initial working tree clean.

## Recommendation

Implement one **OpenRouter credential lifecycle through Igor's existing AI
workflow** as Boundary B, after the decisions below are confirmed. Reuse
Configuration Service, `secret_refs.py`, model-role routing, the request/privacy
boundary, canonical change approval and Operational History. Add protected local
material storage, durable registration, controlled import/update, safe inspection
and access audit. Cut over every selected-provider reader and writer together.
Prove the real request path with a mocked HTTP connection, without an external
provider account, Nextcloud or Docker.

This is useful because an operator can configure a credential, restart Igor,
send an existing chat request, replace the credential and recover a failed local
transition with one inspectable authority. A file adapter alone, or a stored
reference that transport never consumes, does not satisfy the boundary.

Boundary A changes documentation only. It has not read personal credential
values, sourced configuration, dumped environment contents, invoked Igor startup,
made provider requests, installed applications or migrated data. Runtime tests
were inspected as evidence, not executed. Boundary B is not started and the
whole Ownership Foundation remains open.

## Authority, baseline and proof limits

The authority order is [ARCHITECTURE](ARCHITECTURE.md), accepted
[D023–D031, D049/D054 and D058–D063](DECISIONS.md),
[MIGRATION](MIGRATION.md), [EXECUTION](EXECUTION.md), then
[ROADMAP](ROADMAP.md). [CONFIGURATION](CONFIGURATION.md) and
[PERSISTENT_MEMORY](PERSISTENT_MEMORY.md) define the existing configuration,
secret-reference and ownership seams. This proposal extends those seams; it
does not introduce a replacement configuration, memory or execution service.

Local `master` and `origin/master` both resolve to `54782bd58c72fbeabae67fbbb99b671d3fb26c13`.
Neither is an ancestor of this `igor2` revision (merge base `76f04e3`). Older
STATUS reconciliation covers `852ce8f`, not this later master. `git cherry HEAD
master` finds one exact equivalent patch (`5a7c61d`) and ten unmatched patches;
unmatched patch IDs alone do not prove missing behavior. Inspection finds the
local-output separation, latency recording, systemd-identifier scrubbing and
private-event documentation in current code, with later modifications. However,
master's `4c8a0dd` tool-envelope regex correction is absent from
[current tui.py](../../core/ai/tui.py) at line 294. No remote freshness query or
complete master content reconciliation is claimed. The audit describes the
requested current branch; **before Boundary B, reconcile the intended current
master baseline explicitly**. Do not use the historical two-commit reconciliation
as today's proof or fold unrelated runtime repair into this documentation task.

STATUS is an append-oriented evidence record. Its earlier Step 17 exclusion of
module settings/host thresholds describes that original boundary. Later D062 /
Step 18 Boundary 3 proves System memory-warning consumption and readback; it is
the current exception. Likewise Step 19 Boundary 2 now proves bounded attachment
metadata, while older Boundary 1 entries say attachment had not started. Neither
entry proves general application configuration or secret migration. Latest
Step 16F affected validation is green within its selection; historical broader
suite failures remain separately recorded. No old pass count is presented as a
fresh test result for this audit.

`@RTK.md` was supplied in the session instructions but is absent from the
checkout and no copy was found under `/home/pooo`. Repository AGENTS and
[.codex/README](../../.codex/README.md) were followed; no missing RTK behavior
is inferred.

## Current-state assessment

“Demonstrated” below means code plus existing tests/recorded accepted evidence,
not a newly executed audit test. “Missing proof” is different from absence.

| Function | Classification | Evidence and limit |
|---|---|---|
| Configuration schema admission, exact targets, validation, revisions/CAS, private desired store | Implemented and demonstrated, bounded | [configuration_schema.py](../../core/lib/configuration_schema.py):62–137; [configuration.py](../../core/lib/configuration.py):213–359; [test_configuration.py](../../tests/test_configuration.py). Owner-stamped module contributions reuse the existing registry. No provider/deployment configuration scope is added. |
| `ai.verbose` migration and consumption | Implemented and demonstrated | [configuration.py](../../core/lib/configuration.py):143–210, [configuration.sh](../../core/lib/configuration.sh), tests at `test_configuration.py`:300,418,445 and Step 17 STATUS. Explicit first-write cutover; other AI keys retain their writer. |
| System warning desired/apply/independent process readback | Implemented and demonstrated | [System workflow](SYSTEM_MEMORY_WORKFLOW.md), [test_system_configuration_workflow.py](../../tests/test_system_configuration_workflow.py), D062 and later Boundary 3 STATUS. Process policy only; stored desired state does not prove consumption in another process. |
| Secret-reference types in config/capability inputs | Implemented and demonstrated as contracts | [configuration_schema.py](../../core/lib/configuration_schema.py):38–40,112–116; [configuration.py](../../core/lib/configuration.py):336–344; [capability_runtime.py](../../core/lib/capability_runtime.py):43–70,146; config secret fixture at `test_configuration.py`:275. No shipped credential setting or service wiring. |
| Private FD access, owner/purpose/consumer match and value-free callback | Implemented and demonstrated as adapter primitive | [secret_refs.py](../../core/lib/secret_refs.py):27–90; [test_secret_refs.py](../../tests/test_secret_refs.py):16–51. Registration is in-memory, authorization is a trusted caller boolean, audit defaults to no-op. File checks reject group/world access but do not establish parent-directory ownership or a complete durable lifecycle. |
| Real OpenRouter key setup/update and real HTTP request implementation | Implemented with missing integrated proof | [keys.sh](../../core/ai/keys.sh), [api.sh](../../core/ai/api.sh), [ai_engine.py](../../core/ai/ai_engine.py):606–655,788–832; [key tests](../../tests/core/test_ai_keys.bats) and [request tests](../../tests/test_ai_architecture.py):184. Isolated file/update and mocked transport proofs exist; no reference-mediated setup→request→restart/recovery proof. |
| Durable secret catalog, import/cutover, rotation revisions, safe secret CLI and durable access audit | Absent from the current adapter | No persistence/import/update methods in `secret_refs.py`; no current production AI consumer invokes it. Existing AI request/tool audit is not secret-value access audit. |
| Secret redaction/exclusion | Implemented and demonstrated in existing boundaries; lifecycle proof incomplete | [privacy.py](../../core/ai/privacy.py), [request_boundary.py](../../core/ai/request_boundary.py), [operational_history.py](../../core/lib/operational_history.py):100–145; existing redaction tests. Direct file scanners and global env injection remain. Credential-bearing provider errors and private frontend events need selected-consumer proof. |
| Config export/recovery | Implemented and demonstrated, desired state only | [configuration.py](../../core/lib/configuration.py):579–583,630–712 and config tests. Same-scope validated recovery, private recovery point and stale-proposal fencing. No secret-material backup or application rollback claim. |
| Legacy backup/restore | Implemented compatibility; missing secret-service composition proof | [config_backup.sh](../../core/recovery/config_backup.sh):38–45,110–126,330–387,629–658; [full_backup.sh](../../core/recovery/full_backup.sh):60–70,260–268. Copies env/key material, encryption optional; restore writes files directly. Not ordinary Configuration export. |
| Canonical roots and broad ownership/reset | Incomplete | [helpers.sh](../../core/lib/helpers.sh):18–38, [path_resolution.sh](../../core/lib/path_resolution.sh), [security_config.sh](../../core/lib/security_config.sh):44–57 disagree on some roots/defaults. No complete root/owner/lifecycle inventory service; several owning persistence services are already authoritative and must be preserved. |
| Shell env loaders, old home keys/root settings | Temporary compatibility | [config_loader.sh](../../core/lib/config_loader.sh):64–85,129–210,298–337; [config.sh](../../core/lib/config.sh):52–164. They still serve unmigrated workflows; retire only the selected key paths with explicit cutover. |

Capability authorization is already deterministic. Secret-bearing declarations
without reviewed adapters are withheld; they do not become available because a
handle validates. Preserve [capability.sh](../../core/lib/capability.sh),
[safety.sh](../../core/ai/safety.sh), active-owner admission and native PTY
privilege mediation. AI HTTP transport is not currently a secret-consuming v2
capability: authorize its reviewed credential use after deterministic AI policy
and final provider selection, rather than inventing a capability call per token
or using model prose as permission.

## Ownership and migration inventory

This is a repository-family inventory, not a census of personal files. Names,
selectors and source metadata only are recorded. Paths below are current
implementation locators, never new durable identities. Lifetime is persistent
unless stated; effective shell values last for the process. “Legacy tiers” means
`core/config/defaults.conf` → sorted `config/variables/*.env` → sorted
`secrets/*.env` → `secrets/*.key` → sorted deprecated root `*.env`. Later
assignments win, so an inherited process value is not universally highest
precedence. The separate `config.sh` path has its own precedence.

| Family / owner and purpose | Current source, readers/writers and override behavior | Class, scope/lifetime; inspection and redaction | Target, risks/dependencies and disposition |
|---|---|---|---|
| Package defaults, schemas and templates / Core or module: portable meaning | Tracked `core/config/defaults.conf`, `defaults.env`, `config/variables/*`, module declarations/templates. Readers: [loader](../../core/lib/config_loader.sh):298–337, [schema service](../../core/lib/configuration.py):43–65, [module contract](../../core/lib/module_contract.py). Git/package upgrade and operators editing legacy templates are writers. Legacy tiers override defaults. | Package content; package version lifetime, installation defaults. Schema/owner inspection exists for v2, not a unified v1 inventory. Defaults must contain no credentials. | Preserve schemas/defaults; adapt legacy mutable template use individually. Do not put machine data in modules or create a new schema registry. Package replacement must not overwrite desired values. |
| Root bindings / Core bootstrap: locate services before loading state | `IGOR_DIR`, supported per-root env and [helpers.sh](../../core/lib/helpers.sh):18–38; [configuration.sh](../../core/lib/configuration.sh):17–56; [security_config.sh](../../core/lib/security_config.sh):44–57; older [path_resolution.sh](../../core/lib/path_resolution.sh):12–60. Env/export initialization and package defaults write process bindings; some consumers still construct paths directly. | Bootstrap configuration, installation binding, process lifetime; paths may be sensitive. No complete provenance/ownership projection. | Preserve supported bootstrap roots, adapt selected new store to explicit validated roots. Root relocation remains an explicit future migration. Helper patterns/knowledge defaults conflict with security defaults; do not silently choose a new global layout. No Docker dependency. |
| `ai.verbose` / Core: current AI display preference | Desired private `data/config/config.db` after explicit cutover; literal legacy resolution before it. [configuration.py](../../core/lib/configuration.py):143–210,630–678; [core.sh](../../core/ai/core.sh):537–558/settings commands; [configuration.sh](../../core/lib/configuration.sh). Canonical writer; old save hook excludes this key. No arbitrary env override after cutover. | Desired configuration, installation target; durable desired versus current-session consumed snapshot. Configuration inspection/export and safe recovery point. | Preserve authoritative service and demonstrated workflow; no remigration. Generic backup is not proven to restore this database. No application/privilege dependency. |
| System warning threshold / System meaning, Core storage | Shipped System configuration contribution; default 150 MiB, desired store; [module.sh](../../modules/system/module.sh), [configuration.sh](../../core/lib/configuration.sh). Canonical desired/apply/readback writers; `SYSTEM_RAM_WARN_MB` ignored for this setting, not imported. | Desired configuration, `module:system`; process-local applied policy. Module/config inspection exposes consumed revision; independent readback exists. | Preserve D062 workflow. Requires active System for application, no Nextcloud/Docker/root. Other thresholds and package-removal recovery remain open. |
| Other AI preferences / Core AI: provider/model/mode/budgets/roles/autostart/hybrid/Ollama | Legacy tiers plus `config/variables/ai_settings.env`, root `ai_settings.env` fallback. Specialized [_ai_save_settings](../../core/ai/core.sh):537–558 and settings editor write; [hybrid](../../core/lib/ai_hybrid.sh):52–74 and [role_transport](../../core/ai/role_transport.py) read. Saved preferences overlay startup values; runtime commands update session. | Legacy desired/bootstrap inputs plus runtime values; installation and session. Settings snapshot exists; not all fields have configuration schema/source/revision inspection. Policy meaning differs from model parameters. | Adapt later by bounded consumed-setting migrations (e.g. temperature/max tokens), using existing writer/UI. Retire each key writer only at its cutover. Do not migrate autonomy/privilege policy as arbitrary overrides. No Nextcloud needed. |
| OpenRouter credential / Core AI: authenticate selected provider | Env `OPENROUTER_API_KEY`, `secrets/openrouter.key`, `$HOME/.nexus_or_key`, generic env tiers, session caches/`NEXUS_API_KEY`. Readers/writers traced below; [keys.sh](../../core/ai/keys.sh):15–58 writes canonical file and exported cache. Global loader can change the effective precedence before chat. | Secret, local installation/operator account; external credential lifetime independent of Igor. Presence checks and generic exact-value scrubbing, no durable access catalog. | Migrate in B to protected material + durable service registration + config handle. Adapt every selected reader, update writer, privacy scanner and restore path. Provider validation/balance and chat use network in ordinary operation, mocked in required proof; no OS privilege/deployment. |
| Anthropic credential / Core AI: authenticate alternate provider | Parallel `ANTHROPIC_API_KEY`, `secrets/anthropic.key`, `$HOME/.nexus_api_key`; [provider](../../core/ai/providers/anthropic.sh):10–34, [loader](../../core/lib/config_loader.sh):129–187, [keys.sh](../../core/ai/keys.sh). Same exported-cache writer; hybrid preflight reads home key. | Secret, installation/account, persistent plus session injection; same legacy privacy protections and missing lifecycle proof. | Preserve supported behavior during B; adapt shared helper only to fence OpenRouter bypasses. Separate later migration; do not advertise Anthropic as migrated. No application dependency. |
| Site/host and other System policy / operator, System or owning application | `secrets/site.env`, `config/variables/system.env`, `igor.env`, root/config env aliases; generic loader, host/check/menu readers, [System module](../../modules/system/module.sh). Editing files/legacy menus writes. Generic last-assignment tiers, plus hardcoded executed thresholds in consumers. | Mixed bootstrap, desired configuration and sensitive site metadata; installation/host. Legacy selected-config display and outbound scrubbing, no comprehensive schema/application inspection. | Inventory/split per key later; do not infer behavior from an unused env name. Preserve actual thresholds until independent consumer proof. Host-only changes can follow without Nextcloud; app-specific paths/domain bindings cannot. |
| SMTP transport/preferences / Core notifications; module event meaning | `config/variables/notifications.env`, `secrets/notifications.env` with `notify.env` fallback. [notify/core.sh](../../core/notify/core.sh):23–107 sources vars then secrets, initializes flags and upserts settings into the selected secret file; `:176–196` injects transport values. [Nextcloud diagnose](../../modules/nextcloud_docker/module.sh):1152–1185 independently reads old `notify.env`. | Desired configuration + SMTP secret mixed in one writer; installation, event flags depend on active owners. Presence/status/menu inspection and generic scrub; no secret-service audit. | Adapt/split later; keep outbound behavior. New transport slice can be tested without Nextcloud, live delivery optional. Old/new files and diagnostic readers compete. SMTP account dependency, no general root requirement. |
| Notification source toggles / Core notifications: enable/disable sources | Root `notify_sources.conf`; [aggregator.sh](../../core/notify/aggregator.sh):20,74–75,115–125 reads/writes. Separate from `NOTIFY_ON_*` flags. | Desired preference mixed with source registry participation; persistent installation. Menu views, no v2 provenance/CAS. | Migrate separately after defining source identity/active-owner rules; retire root writer only with equivalent behavior. No Nextcloud required for Core/System sources. |
| DB, Nextcloud admin, OnlyOffice/JWT, Compose and tunnel configuration / application/integration owners | `secrets/db.env`, `onlyoffice.env`, site/root env, `${NEXUS_CONFIG}/config.env`, legacy project db files; generated `config/stacks/...` and native app settings. [config.sh](../../core/lib/config.sh):129–164 uses defaults→config.env→first DB source→first JWT source; [helpers.sh](../../core/lib/helpers.sh):33–38,65–76 reads/writes DB env; [configure menu](../../modules/nextcloud_docker/menus/configure.sh):59–128 uses native OCC; [reset_stack](../../modules/nextcloud_docker/lib/install/reset_stack.sh) and setup/install scripts write/use application inputs. Generic loader adds another tier path. | Mixed desired/bootstrap/secret/application persistent state; deployment and external-resource lifetimes. Module checks/presence and generic scrub, not one bound authority; file existence is not native application readback. | Preserve v1; inventory locators and adapt after deployment binding/native readback proof. Docker/Nextcloud/DB and often sudo/resources required. Different application settings need different recovery semantics; no generic undo. Excluded from B. |
| Mail/IMAP/GPG material / future communications owner, legacy compatibility | `secrets/mailcmd.env`, legacy vars/root files and `secrets/gnupg`; [config.sh](../../core/lib/config.sh):84–103 moves files if target absent; [Nextcloud checks](../../modules/nextcloud_docker/module.sh):1188–1264 inspect presence. Backups/legacy settings can write. `core/mailcmd/` is absent. | Secret + desired/bootstrap inputs; account/keyring lifetime. Presence checks are not a working authenticated mail workflow. | Preserve recovery inputs and product intent; defer to [communications proposal](COMMUNICATIONS.md)/Step 22. Do not use absent implementation as first consumer or install anything. |
| Module activation / Core module runtime: participation | Data-only `config/modules.conf`; [module_loader.sh](../../core/lib/module_loader.sh), enable/disable commands, explicit System migration and legacy backup restore. New v2 needs enablement; omitted v1 entries retain compatibility. | Bootstrap/persistent policy configuration, installation; process activation lasts until restart. Module inspection and detach assessment separate retained data from activity. | Preserve existing authority, backup and active-owner gates. No broad import to desired settings or scope change in B. Package removal is not secret deletion. |
| Recovery archives, journal and schedule / Core recovery: snapshots/legacy operational recovery | [config_backup.sh](../../core/recovery/config_backup.sh), [full_backup.sh](../../core/recovery/full_backup.sh), [journal.sh](../../core/recovery/journal.sh), [schedule.sh](../../core/recovery/schedule.sh). Backup settings/cron are legacy desired inputs; archive creation/rotation and staged restore are writers. | Bootstrap/preferences + persistent recovery artifacts/history compatibility; retention determined by owning workflow. Archives may contain plaintext credentials; encryption failure can leave plaintext. Archive listing is not safe ordinary export. | Preserve unrelated artifacts/retention; adapt selected key restore/export handling in B. Separate sensitive secret recovery from config export. Direct restore must not replace service material or re-enable fallback. System-file restore has independent sudo/application dependencies. |
| History, Investigations, Deployments, Automation and Learning / their Core services | [operational_history.py](../../core/lib/operational_history.py), [investigations.py](../../core/lib/investigations.py), [deployments.py](../../core/lib/deployments.py), [automation_registry.py](../../core/lib/automation_registry.py), [local_learning.py](../../core/lib/local_learning.py). Own APIs write stores; each has separate status/recovery/deletion semantics. No config loader owns these records. | Persistent state/history/investigations; learning remains reference knowledge. Installation-scoped IDs, retained across module inactivity. Existing service inspection/export, privacy admission and separate reset. | Preserve; reference operations/scope without copying records into secret metadata. History reset does not revoke credentials; config restore does not restore secret values. B must not reset/migrate these stores. |
| Packaged knowledge, local patterns, session/runtime / package owner or Core reference/session owners | Packaged module knowledge, [local learning](LOCAL_LEARNING.md), legacy `config/patterns/*.pattern`, session transcripts, [events.sh](../../core/ai/events.sh), `_igor_resolve_dir` runtime. Existing learning/session writers and legacy pattern paths. | Package knowledge, learning, persistent session narrative and disposable runtime are distinct. Ownerless patterns are compatibility. Frontend event files are private but may carry faithful unsanitized host output. | Preserve active-owner/reference trust boundaries. Secret lifecycle projects metadata only; no key, digest, terminal input or auth transcript in these records. Broad path/layout consolidation remains open. |

### Environment names have different jobs

This classification covers the names encountered in these workflows; it is not
a blanket contract for all variables. Exact consumers above remain authoritative.
“Supported override” here describes existing use, not an automatic new schema
binding. Nonsecret values below are names, not environment contents.

| Name (each listed name has the stated role) | Classification / disposition |
|---|---|
| `IGOR_DIR` | Bootstrap installation root; preserve. |
| `IGOR_DATA_DIR` | Supported bootstrap durable-data root override; preserve and validate for new store. |
| `IGOR_SECRETS_DIR` | Supported helper secret-root override; current AI/loaders still hardcode `IGOR_DIR/secrets`. Resolve explicitly for B; do not claim universal support today. |
| `IGOR_RUNTIME_DIR`, `IGOR_SESSIONS_DIR`, `IGOR_ALERTS_DIR`, `IGOR_REPORTS_DIR`, `IGOR_BACKUPS_DIR`, `IGOR_RECOVERY_DIR` | Each a supported owning-helper location override; retain separate lifetime/ownership classes. |
| `IGOR_PATTERNS_DIR`, `IGOR_KNOWLEDGE_DIR` | Each a supported location override with competing fallback defaults; defer global root reconciliation. |
| `NEXUS_CONFIG`, `NEXUS_PROJECT_DIR` | Each a legacy bootstrap path selector/compatibility alias, not a desired application setting to import wholesale. |
| `OPENROUTER_API_KEY` | Secret injection / compatibility import candidate. Proposed: explicit import only for migrated key; no post-cutover ambient override. |
| `ANTHROPIC_API_KEY` | Secret injection, preserve unmigrated behavior. |
| `NEXUS_API_KEY` | Internal selected-value injection into transport today; proposed selected OpenRouter FD use replaces global cached exposure. Not a supported competing credential authority. |
| `provider`, `model`, `NEXUS_TEMPERATURE`, `IGOR_AI_ROLE_BINDINGS`, `IGOR_OLLAMA_HOST`, `IGOR_OLLAMA_DEFAULT_MODEL` | Each an existing setting/runtime input or supported owning-consumer override; specialized persistence remains. Role binding controls provider selection, not credential authorization. Migrate separately. |
| `NEXUS_PROVIDER`, `NEXUS_MODEL`, `NEXUS_MAX_TOKENS` | Each an internal transport projection of selected settings; do not migrate separately from its owner. Direct engine test inputs are not durable configuration. |
| `IGOR_AI_ENABLED`, `IGOR_AI_ALLOWED_TOOLS`, `IGOR_AI_DISABLED_ACTIONS` | Each a supported administrator policy input. Preserve deterministic policy; no arbitrary settings import that weakens it. |
| `executive_mode` | Compatibility mode alias for Assist/Executive; preserve until exact migration, never OS privilege. |
| `verbose` | Literal compatibility input before `ai.verbose` cutover; ignored afterward. |
| `IGOR_VERBOSE` | Internal consumed verbosity value after resolution; not an independent post-cutover override. |
| `SYSTEM_RAM_WARN_MB` | Ineffective compatibility name for migrated warning consumer; no import. |
| `IGOR_SYSTEM_MEMORY_WARNING_MIB`, `IGOR_SYSTEM_MEMORY_WARNING_REVISION`, `IGOR_SYSTEM_MEMORY_WARNING_STATE` | Each an internal current-process consumption projection, not user override authority. |
| `POSTGRES_PASSWORD`, `NEXTCLOUD_ADMIN_PASSWORD`, `JWT_SECRET`, `NOTIFY_SMTP_PASS` | Each secret injection from its owning legacy family; do not migrate with nonsecret env settings. |
| `POSTGRES_USER`, `POSTGRES_DB` | Each application bootstrap/configuration input, potentially sensitive metadata; not necessarily secret material. Deployment binding required for migration. |
| `HD_MOUNT`, `NC_DATA`, `COMPOSE_FILE`, `DB_ENV` | Each legacy application binding/path input or compatibility locator; not evidence of adoption/authority. |
| `IGOR_CONFIGURATION_ROOT`, `IGOR_CONFIGURATION_DATA_DIR`, `IGOR_CONFIGURATION_INHERITED_VERBOSE`, `IGOR_CONFIGURATION_SYSTEM_MEMORY_RECORD` | Each internal configuration bridge argument; no public override migration. |
| `IGOR_AI_REQUEST_ID`, `IGOR_AI_ROUTING`, `IGOR_AI_MODEL_SNAPSHOT`, `IGOR_AI_CAPABILITY_SNAPSHOT`, `IGOR_AI_SCRUB_MAP` | Each internal request/projection/privacy value; never import as desired configuration or expose as secret status. |

## First real consumer: OpenRouter

OpenRouter is the current classic-chat default (`core.sh`:2441), has real setup
and `apikey` update, and the actual Python HTTP branch is covered by mocked
request tests. Anthropic shares the structure but is not required to prove this
slice; Ollama has no credential and cannot prove the secret contract. There is
no evidence that makes AI unsuitable, so no unrelated consumer comparison or
SMTP/application expansion is needed.

### Current path and alternate access

1. **Setup/import:** [core.sh](../../core/ai/core.sh):2358–2414,2445–2449
   selects environment, canonical key file, then home key. The generic loader
   may already have overwritten environment from `.key`/env files. Missing TUI
   credentials redirect to classic setup; `apikey` and provider settings use
   `_ai_change_key`. No controlled import transaction currently exists.
2. **Storage/update:** [keys.sh](../../core/ai/keys.sh):4–58 visibly prompts,
   trims paste whitespace, calls provider validation, atomically renames a
   private temporary file and exports the new key. Failed validation/save keeps
   the prior key. The prompt is separate from chat; it is not an audited
   secret-service transition. Provider validation currently uses curl headers
   in argv ([api.sh](../../core/ai/api.sh):107–130).
3. **Alternate readers:** [config_loader.sh](../../core/lib/config_loader.sh):129–210
   exports `.key` files and legacy home keys; generic env tiers can assign the
   same name. [openrouter.sh](../../core/ai/providers/openrouter.sh):10–39
   independently reads env/home. [ai_hybrid.sh](../../core/lib/ai_hybrid.sh):33–34,109–125
   reads home credentials; its Anthropic-only preflight can incorrectly block
   OpenRouter. Selected-session caches also bypass reference resolution.
4. **Actual request:** [api.sh](../../core/ai/api.sh):6–67 selects the final
   administrator-bound role/provider and exports `NEXUS_API_KEY`. Direct
   [ai_engine.py](../../core/ai/ai_engine.py):606–643 repeats routing and may
   replace it from `<PROVIDER>_API_KEY`. `:808–819` performs the actual
   OpenRouter HTTPS POST with a Bearer header. The shell provider's header
   helper is not the main Python POST implementation. Follow-up, summary,
   explanation and role-bound requests must not retain an env bypass.
5. **Other real secret use:** [_nexus_get_or_balance](../../core/ai/api.sh):133–158
   calls the account endpoint with the selected key. Initial/deferred key
   validation and replacement validation are separate uses. Preserve these
   supported behaviors through explicit reviewed access, without adding any
   automatic probe to safe inspection.
6. **Inspection/redaction/audit:** configuration secret fixtures call injected
   service inspection, but production AI does not. [privacy.py](../../core/ai/privacy.py):9–34
   reads all flat secret files and environment; [operational_history.py](../../core/lib/operational_history.py):100–125
   duplicates secret scanning, including short values. These are additional
   material readers, not authorized transport. Request/tool audit is distinct
   from secret-access audit. [ai_engine.py](../../core/ai/ai_engine.py):817–825
   can emit provider error bodies; [core.sh](../../core/ai/core.sh):35–73 and
   [safety.sh](../../core/ai/safety.sh):164–208 deliberately preserve local
   presentation. Private file permissions alone do not prevent echoed key
   material entering errors/events. Moving keys must not break exact-value
   redaction or restore global environment export just to keep scanners working.
7. **Recovery:** atomic replacement protects a single file failure. Config
   recovery handles references only. Legacy backups copy flat `.env`/`.key`
   files and can directly restore them; there is no joined secret/config
   migration, failed-cutover reconciliation or credential recovery proof.

The necessary integration is therefore wider than `keys.sh`, but bounded by
one selected credential. Do not silently retire hybrid requests, role routing,
balance lookup, provider validation or alternative-provider behavior to make
the tests easier.

## Proposed Boundary B contract

All new names/layouts in this section are **proposed**. Confirm the decisions
before implementing durable records or behavior changes.

### Protected local storage and registration

Extend the existing `SecretReferenceService`, preserving opaque reference and
owner/purpose/consumer checks and FD/callback use. Keep material separate from
Configuration and History. Use the existing installation scope; a proposed
Core schema field such as `ai.openrouter.credential` has type `secret_ref`,
installation target `installation:local`, schema owner `core`, no literal
default and no environment override. Provider identity is metadata/purpose,
not a new configuration target registry.

Proposed private implementation: immutable material generations under the
validated canonical secret root, in a service-owned subdirectory; a separate
small transactional metadata store under the durable data root. Restrict
directories to 0700 and material/metadata files to 0600 and current UID; check
ancestors, links, ownership and opened FDs. Paths remain private locators, not
references. Reuse existing path binding and safe-storage patterns without
turning `path_resolution.sh` into a new security authority.

Metadata records the opaque reference, installation scope, owner, purpose,
reviewed consumer binding(s), generation/revision, safe source locator,
operation reference and cutover state. No key previews, lengths, value hashes,
derived secret digests, headers or terminal transcripts. Register Core reviewed
consumers from trusted code; on-disk metadata cannot grant new consumers.
Unknown schema/version or corrupt state fails closed and is retained.

### Consumption and safe projection

Resolve the configured reference only after final provider/role selection and
AI-enabled/request policy checks. The reviewed OpenRouter transport consumes
material privately at the HTTP boundary, through a protected FD or in-process
callback. Do not put selected material in argv, general child environment,
Context or ordinary serialized capability input. Direct engine invocation,
hybrid, all model roles, validation and balance must use the same binding or
fail with a value-free unavailable reason. Capability authorization remains
unchanged; `authorized: true` from serialized input is never sufficient.

Separate the trusted **transport** and **redaction** use profiles. The latter
returns sanitized data rather than raw key values to ordinary record producers.
Adapt selected-key reads in `privacy.py` and History to mediated sanitization;
unmigrated secret families retain compatibility. The current adapter binds one
consumer per source; supporting the reviewed transport and redaction profiles
requires an explicit registration extension/decision, not weakening that check.
Redaction must cover active, staged and retained recovery generations within
the slice and survive removal of global env injection. Preserve protocol IDs and
faithful nonsecret host output; do not reapply broad privacy replacement to all
frontend data. Sanitize credential-bearing input/errors at the owning boundary.

Provide side-effect-free status/list/inspect for registration, source/cutover,
scope/owner/purpose/binding, configured/available/missing/unsafe/corrupt,
generation/revision and value-free access metadata. Reads of absent stores
create no root, scope or database, perform no HTTP validation and request no
sudo. Config inspection distinguishes stored reference, resolved availability
and actual consumed generation/request identity. Local storage verification
does not imply external account validity; an HTTP 401 does not delete intent.

Append a private value-free secret-access record before releasing material:
request/operation ID, reference, scope, owner, purpose, admitted consumer,
generation, access outcome and timestamp. Audit denials where safe, including
missing references and wrong bindings. Fail closed if the required access record
cannot be written; do not reuse the current optional AI diagnostic audit as the
gate. Secret service owns access metadata; canonical History owns CHANGE
approval/execution/recovery outcomes. No invented History episode per HTTP
token or automatic learning artifact.

### Import, update and single-source cutover

Use the existing setup/API KEY/`apikey` entry points and a narrow explicit
headless import operation, not a generic settings UI. Secret entry travels by
protected input, outside public JSON, command args, event transcripts and frozen
History inputs. Canonical CHANGE preparation freezes only source metadata,
reference intent and revisions; trusted provider admission binds the private
staged input. Approval remains the existing deterministic boundary, with no sudo
for user-owned local storage. Prompt cancellation and failed validation preserve
prior usable authority.

Import names all supported source candidates: explicit secret input, inherited
`OPENROUTER_API_KEY`, canonical legacy file, home key and literal selected
assignments from known env files. Parse selected assignments as bounded data;
do not source files or evaluate shell. Present source names/status, never values.
Ambiguous/executable inputs require explicit source selection or new secret
entry. Do not guess equality with exported secret hashes. Recommended selection:
an explicitly selected source wins; otherwise one unambiguous file candidate
may be proposed, while multiple candidates require selection. This changes
legacy precedence only at an approved migration, not during ordinary startup.

Stage validated private material and registration before committing the config
reference. There is no atomic transaction across two stores/files: document and
test the small transition states and crash fences. A new unreferenced generation
cannot be consumed; a reference is usable only with an admitted committed
registration. Rotation atomically advances the secret generation under CAS
while the stable config reference remains unchanged. Concurrent proposals have
one winner; stale updates cannot overwrite or resurrect old generations.

Persist cutover per selected setting/reference. After it:

- loaders do not inject the migrated `.key`/home key; selected ambient/env-file
  aliases and cached `NEXUS_API_KEY` cannot override service resolution;
- ordinary selected-provider startup/request, provider helper, hybrid and role
  paths never fall back to env/home/canonical legacy files;
- existing selected-key writer becomes an adapter to the service, not a second
  writer; generic backup restore refuses or routes selected-key restore into
  explicit service import rather than overwriting authority;
- retained original files remain recovery inputs only. Do not automatically
  delete personal originals, edit unrelated env keys, or remigrate on startup.

No eager bootstrap export of the selected material should remain even when
legacy env files assign its name. Fence/unset selected aliases at the loader/
consumer boundary before unrelated child execution; retain unrelated secret
injection behavior. Trusted executable legacy env files are existing code, not
sandboxed data; B does not promise OS isolation from malicious local scripts.

### Restart, failure and recovery

Document exact source version/locators and target version; initialization is
explicit and imports are idempotent by operation identity and frozen metadata,
not by a public secret digest. Re-entry reconciles local transition state before
any new write. A crash before config cutover retains old authority and private
staging; a crash after committed cutover never restores fallback automatically.
Report missing material/registration or audit failure as unavailable. Retain
damaged files; no startup repair, network probe, automatic retry or credential
deletion.

Recovery is explicit approved local re-import/new credential or activation of
one retained prior protected generation as a new revision. It cannot reverse
provider-side revocation. Retain at most one prior material generation for local
recovery, with explicit discard; do not build general credential retention/GC.
Configuration restore contains handles only and cannot reset secret cutover or
credential generations. Unset/reset of this reference must not automatically
delete material or reactivate old sources. History/learning reset is independent.

Recommended B recovery/export boundary: metadata-only ordinary exports and
explicit local recovery/re-entry; **no new portable secret-value export**.
Exclude managed material **and retained selected legacy key copies/assignments**
from new ordinary capture, and refuse direct legacy restore to managed storage.
For mixed env files, produce a bounded selected-key-free snapshot or explicitly
refuse that component if it cannot be safely projected; never source it or copy
the selected value silently. Preserve unrelated backup contents/behavior.
Make the selected credential's backup omission/status
explicit so operators can recover by protected re-import/new key. Old archives
remain sensitive legacy artifacts; do not rewrite or delete them. If portable
encrypted recovery is required by the owner, accept and estimate that separately
before B rather than leaving optional plaintext fallback as new service policy.

## Decisions requiring owner confirmation

These are approval inputs for the later implementation task, not decisions
accepted by publishing this proposal.

| Decision | Alternatives and repository consequences | Recommendation |
|---|---|---|
| B1: storage/registration transaction | Keep canonical flat key + JSON catalog: fewer moves, but direct scanners/restore and crash recovery compete. Private SQLite metadata + separate immutable files: CAS/audit/transition consistency, but requires file/store crash reconciliation. Material in SQLite: simpler transaction, but secret-bearing WAL/backups complicate separation. | Private SQLite **metadata only** plus protected material generations, reusing current roots and FD service; no external vault. Layout private, versioned record semantics reviewed before code. |
| B2: trusted registration and authorization | Caller boolean/in-memory registration alone is insufficient. Durable metadata alone could forge consumers. Trusted Core bindings plus validated durable reference metadata preserve the service split. Current singular binding must explicitly accommodate transport and sanitizer use profiles. | Core admits a closed set of OpenRouter transport/validation/balance and Core-redaction uses; final routing and AI policy precede access. Never authorize from config/import/AI JSON. Confirm stable identities/record shape and access-audit failure policy. |
| B3: import precedence and env compatibility | Preserve ambient env override: convenient automation but a second material authority and per-use audit/exposure complexity. Automatic legacy precedence migration: familiar but silently selects among competing sources. Explicit source-selected import: extra setup step, deterministic authority. | Explicit source-selected import, no ambient override after cutover. Preserve env as explicit import input. Confirm this supported-behavior change and recovery when several sources exist. |
| B4: recovery and backup | Local retained generation + re-import: smallest recovery, no portable secret backup. Mandatory encrypted portable export: useful disaster recovery, adds key/passphrase/storage/recovery policy. Preserve legacy optional plaintext capture: incompatible with new ordinary-export guarantee. | One private previous generation and explicit re-import; metadata-only exports; selected managed and retained legacy material omitted from new ordinary backup with visible status. Confirm acceptable disaster-recovery limit. |
| B5: private input / mutation seam | Serialize key in ordinary capability input: leaks into frozen proposals/History, reject. Trusted private-input staging alongside normal canonical CHANGE: adds bounded admission plumbing but keeps authority unified. Separate unmediated credential writer: duplicates policy, reject. | Private staging bound to canonical operation/ref/revision; retain existing entry points and network-validation behavior. Confirm proposed narrow import/update capability identities and input contract before implementation. |

D027/D031/D059 already accept mediated secrets, references-only config, explicit
cutover/recovery and separated services. Wiring the real workflow and preserving
current configuration scopes implement that architecture. B1's record lifecycle,
B2's registration/use profiles, B3's env cutover, B4's recovery guarantee and B5's
private-input/public-operation seam require a new bounded accepted decision.
No broad configuration architecture, external vault, deployment scope or public
module secret-registration framework is justified by this slice.

## Boundaries, dependencies and exact scope

| Boundary | Can proceed without application installation? | Stop/evidence |
|---|---|---|
| A: this inventory/proposal | Yes, read-only implementation inspection and documentation | Referenced proposal, unaccepted choices explicit, scoped docs validation/commit. No runtime evidence newly claimed. |
| B: one OpenRouter credential lifecycle | Yes, after B1–B5 and intended-master reconciliation | All acceptance checks below; offline real consumer path, restart/update/recovery and no competing writer. Stop before a second credential. |
| Later Core migrations | Yes for individually selected AI model parameters/autostart, host thresholds with executed consumers, recovery preferences and notification source policy | Each key/family has schema, consumed snapshot/readback as appropriate, writer cutover, safe inspection and recovery. SMTP credentials/delivery are a separate real consumer, with optional live account proof. No blanket env conversion. |
| Deployment/application desired settings and credentials | Contract/fixture work can precede installation; real proof requires a concrete bound application | Deployment identity and exact source/write/readback locators, independently observed native state, conflicts/ownership, restart and capability-specific recovery. Nextcloud/Compose/OCC/DB credentials cannot be certified from config rows. |

B is in scope only for OpenRouter registration/material, the Core config handle,
private-input import/update, trusted access/audit, selected-key sanitization,
safe inspection, restart/cutover/recovery, and adaptations of existing
OpenRouter setup/chat/role/hybrid/validation/balance/backup paths necessary to
eliminate bypasses. Preserve Anthropic, Ollama, settings commands, native tools,
approval, privilege and unrelated module/backup behavior.

Out of scope: Nextcloud installation/adoption or Step 19 Boundary 3; Docker
installation; app/DB/JWT/tunnel credential migration; Anthropic/SMTP migration;
OAuth or external vaults; multi-account/provider target registry; generic secret
management UI; broad module/API v2 migration; global root relocation; wholesale
environment loading replacement; persistent state/learning/history migration;
portable secret-value backup unless B4 is revised; OS sandboxing/keyring/at-rest
encryption product; self-healing, agents or new provider features. Current UID
protection does not protect against that UID or root reading local material.

After B the Ownership Foundation still lacks broad Core/module configuration
ownership, application/deployment binding/native readback and source cutovers,
remaining credential families, comprehensive root coherence, legacy mixed
settings/secret writers, package removal/detach/retained-secret lifecycle and
cross-family recovery/reset guarantees. Existing History, Investigations,
Deployments, Learning and runtime owners remain intact; one credential does not
close their integration or the foundation gate.

## Falsifiable Boundary B acceptance checks

Use synthetic sentinel credentials and isolated temporary roots only. Every
negative case asserts zero unauthorized material release and zero network
calls. No personal credential or installation is a test prerequisite.

| Proof | Required checks |
|---|---|
| Contract | Unknown versions/fields, foreign scope, forged owner/purpose/consumer, malformed refs and serialized authorization fail before release/write. Configuration accepts only a handle for the proposed field, has no secret default and rejects unavailable bindings. Symlink/ancestor escape, wrong UID, loose perms, nonregular files and open-time replacement fail closed. Two stale concurrent imports/updates have one CAS winner. Reference remains stable across rotation; private filename is not identity. Audit write failure releases no material. |
| Regression | Existing `ai.verbose` and System desired/apply/readback remain distinct and green within reviewed baseline; other provider credentials/settings, Ollama and role bindings still work. Guide/Assist/Executive, declined CHANGE, DESTROY, privilege and module activation cannot be bypassed by staging/ref input. Ordinary backup/restore of unrelated keys/settings remains supported; selected direct overwrite is refused/adapted. Master reconciliation and affected gate contain no unreviewed new failures/timeouts. |
| Real workflow | Existing setup/API KEY/`apikey` creates reference+protected material; a fresh process resolves it and existing `_nexus_api_call`→`ai_engine.mode_call` emits a real POST through mocked `http.client.HTTPSConnection`. Capture the HTTP call: sentinel appears only in intended auth header, never body/context/normal env/argv. Follow-up, direct engine, hybrid and each selected-provider role use mediated access. Validation and balance use reviewed bindings/mocked endpoints. Replacement changes the next request in current and restarted processes without a stale cache. Other-provider selection never consumes this ref. |
| Inspection | Public secret/config/status reads show owner/scope/purpose/binding/source/cutover, available/missing/unsafe/corrupt and actual generation/access metadata, no key/preview/hash. Absent inspection leaves full filesystem byte inventory and scope unchanged and makes no probe. Config desired handle and actual consumed generation are separate. Access records contain permitted metadata for success/denial, no raw paths/values/headers/input. |
| Non-exposure | Search captured ordinary Context, conversation/session output, History including proposals/recovery, frontend/domain events, exceptions/provider error bodies, AI audit and configuration/metadata/legacy exports for active/staged/prior sentinel bytes: zero occurrences. Force provider to echo sentinel in error body and response/tool output; sanitize at owning projection. Force failed import/validation/rotation/recovery paths. Sanitization still works after env caches and legacy flat source are absent; unrelated systemd/protocol identifiers survive. Private material/staging/recovery files and intended HTTP auth are the only allowed sentinel locations. |
| Migration/recovery | Explicit source list and literal parser; executable env fixture cannot execute. Multiple sources require selection. Inject failures before stage, metadata commit, config commit, cutover finalization and audit append; reopen/re-enter without duplicate identities, automatic network/write replay or fallback resurrection. Before cutover preserve old authority; after cutover missing material blocks the consumer even with valid env/home files. Change legacy file/env/cache and run every reader: service still wins. Legacy backup restore cannot reactivate it. Restore config handle without material: unavailable, not configured-success. Retained prior/new-entry recovery is an approved new revision; foreign-scope/corrupt restore retains originals. Unset/config/History reset does not erase secret or clear cutover. |

The required real-workflow proof exercises production routing, service resolution,
payload preparation and HTTP serialization with only the final socket mocked.
Tests that invoke `SecretReferenceService.use` alone or inject `NEXUS_API_KEY`
directly are insufficient. Optional live OpenRouter validation can separately
check account validity and one external request with explicit owner authorization;
it is neither required for local lifecycle closure nor performed during A.

## Affected files and validation plan

Expected B subsystems (confirm final exact files at discovery):

- [secret_refs.py](../../core/lib/secret_refs.py): extend the owning adapter with
  private durable registration/material transition/access-audit components;
  bounded helper files are acceptable, no parallel public secret service.
- [configuration.py](../../core/lib/configuration.py),
  [configuration_schema.py](../../core/lib/configuration_schema.py),
  [configuration.sh](../../core/lib/configuration.sh),
  [capability.sh](../../core/lib/capability.sh): Core handle schema, injected
  service, canonical private-input change/recovery and safe inspection.
- [keys.sh](../../core/ai/keys.sh), [core.sh](../../core/ai/core.sh),
  [api.sh](../../core/ai/api.sh), [ai_engine.py](../../core/ai/ai_engine.py),
  [openrouter.sh](../../core/ai/providers/openrouter.sh),
  [ai_hybrid.sh](../../core/lib/ai_hybrid.sh),
  [config_loader.sh](../../core/lib/config_loader.sh): all selected sources,
  caches, role/auxiliary requests and writers.
- [privacy.py](../../core/ai/privacy.py),
  [request_boundary.py](../../core/ai/request_boundary.py),
  [operational_history.py](../../core/lib/operational_history.py) and selected
  error/event producers: mediated selected-key sanitization. Change generic
  privacy semantics only as required by sentinel/protocol proofs.
- [config_backup.sh](../../core/recovery/config_backup.sh) and full-backup
  composition where needed: selected managed-material exclusion/restore fence.
  Unrelated application and system restore remains untouched.
- Entry-point safe inspection routing and existing command registry if needed;
  no UI storage authority. README, CONFIGURATION, STATUS, LEGACY and accepted
  decision/handoff describe actual new behavior and recovery limits.

For A: resolve Markdown local targets, verify cited symbols/selectors/line
locations, inspect consistency with accepted decisions, inspect final/staged diff
and `git diff --check`. No TOML/config changes: parsing is not applicable. No
runtime or full regression run is applicable to this documentation proposal.

For B: use the existing affected-validation harness and explicit supplemental
groups, rather than a full repository suite merely because the facade changes.
Start with [test_secret_refs.py](../../tests/test_secret_refs.py),
[test_configuration.py](../../tests/test_configuration.py),
[test_system_configuration_workflow.py](../../tests/test_system_configuration_workflow.py),
[test_capability_runtime.py](../../tests/test_capability_runtime.py),
[test_operational_history.py](../../tests/test_operational_history.py),
[test_ai_architecture.py](../../tests/test_ai_architecture.py),
[test_context_routing_integration.py](../../tests/test_context_routing_integration.py),
[test_ai_settings_backend.py](../../tests/test_ai_settings_backend.py),
[test_ai_menu_startup.py](../../tests/test_ai_menu_startup.py),
[test_ai_keys.bats](../../tests/core/test_ai_keys.bats),
[test_config.bats](../../tests/core/test_config.bats),
[test_backup_p2.bats](../../tests/core/test_backup_p2.bats), and affected
approval/privilege/events/scrubbing/transaction tests. Add the missing complete
offline lifecycle tests and focused backup/hybrid/auxiliary-consumer cases;
inspect [validation_domains.py](../../tests/validation_domains.py) so narrow
automatic selection does not omit these paths. Changed Bash syntax and CI
ShellCheck flags, changed Python compilation/Ruff, docs links and diff checks
are required. Pin pre-task failures/timeouts from the current branch/harness,
report new versus reviewed baseline outcomes; do not update baseline metadata
to hide failures. Broader release validation remains a separate gate.

## Effort and uncertainties

Rough estimate after owner decisions/baseline reconciliation: **6–10 engineering
days**, not a one-file adapter change. Approximately 2–3 days for protected
storage/registration and failure recovery; 2–3 for real consumers/private-input
cutover and backup fencing; 2–4 for integrated failure/redaction proofs,
regressions and documentation. Independent review can shorten elapsed time but
cannot remove the five proof classes.

Main uncertainty is the private-input/canonical-History seam and crash
consistency across Configuration and secret metadata. Other uncertainties are
hybrid startup assumptions, exact-value redaction without global env exposure,
legacy restore composition and the stale master reconciliation. Portable
encrypted export or multi-account/provider scopes would increase scope and need
a revised estimate. No estimate assumes a Nextcloud deployment or live provider.

## Ready-to-use Boundary B implementation task

> Work on current `igor2`. Implement only the owner-confirmed OpenRouter
> credential lifecycle from this Boundary A proposal. First verify branch/status,
> preserve unrelated work, reconcile the intended current master baseline and
> record accepted B1–B5 choices/record identities. If a choice remains unresolved,
> prepare its concrete contract/options for owner confirmation before code.
>
> Follow AGENTS and `.codex/README` phases. Reuse Configuration Service and
> `secret_refs.py`; add no parallel service or generic settings UI. Implement
> protected local material and durable metadata, installation-scoped Core config
> handle, trusted transport/redaction bindings, canonical CHANGE with private
> input, mandatory value-free access audit and side-effect-free status inspection.
> Preserve existing OpenRouter setup, chat/follow-up, role routing, hybrid,
> validation, balance and current-session key replacement. Retire selected env,
> home/file/cache and restore bypasses only at explicit idempotent cutover.
>
> Prove every row of the Boundary B acceptance table using synthetic credentials
> and isolated fixtures, including production request serialization with mocked
> HTTP, rotation/restart, echoed-key errors, failed migration/recovery and legacy
> writer exclusion. Optional live-provider testing needs separate authorization;
> it is not a prerequisite. Do not inspect/migrate personal credentials, install
> apps, advance Nextcloud/Docker work, migrate another provider or close the whole
> Ownership Foundation.
>
> Run focused and affected validation under current validation economics; retain
> honest baseline failures/skips. Update current behavior/recovery docs, STATUS,
> LEGACY and accepted decisions with contract, regression, real workflow,
> inspection and migration/recovery evidence. Enter RELEASE_FREEZE once those
> gates pass, review/stage only scoped files, commit/verify and report. Stop after
> Boundary B; no next credential or roadmap boundary starts automatically.
