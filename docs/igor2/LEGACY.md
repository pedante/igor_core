# Igor 2 legacy and preservation map

Wave D, bounded Wave E and Steps 13–14 are present on `igor2`.
This map records the v1 compatibility surfaces that remain live alongside the
typed host model and canonical capability path. The Wave E contract is in
[AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md).

Wave A / Step 1 audit of the `igor2` tree at `6675ece` (2026-09-26). Local
`master` (`76f04e3`) is an ancestor. Code and tests establish current behavior;
the [architecture](ARCHITECTURE.md) sets the target. `KEEP/ADAPT` means preserve
the working implementation while extending its contract. Compatibility entries
give a removal condition.

| Area | Current evidence and assessment | Classification | Migration target / removal condition |
|---|---|---|---|
| Module activation and ownership | `core/lib/module_loader.sh` now separates v1/v2 discovery, policy, validation, staged activation and owner-aware contribution inspection. Hooks, menus and actions retain inactive-owner filtering; v2 state/reason and contribution queries are exposed alongside the existing views. | KEEP/ADAPT | Keep the single loader, state vocabulary and restart semantics. Retire v1 views only after their consumers migrate and equivalent behavior is proven; no hot unload. |
| Healing check activation | `core/healing/core.sh:43-65` now uses `igor_has_module` for module identity. `tests/modules/test_healing_activation.bats` guards active, disabled, unavailable and installed-only discovery against Diagnose's active set. | KEEP/ADAPT | Step 10 can unify result/discovery contracts without regressing active-owner filtering. |
| Diagnose and healing checks | `core/lib/health_runner.sh` now owns active check execution and structured v2 results with v1 line adapters. Diagnose and Healing project the shared results into their distinct UI/cache flows. | KEEP/ADAPT | Retire v1 line adapters only after all active modules migrate and equivalent workflow coverage passes. |
| System memory duplicate checks | `host.memory` and `host.memory.health` are now the canonical RAM fact/check. Legacy RAM emissions in `system__diagnose`, `system__health` and `checks/hardware.sh` are retired; other hardware findings remain. The effective 80/150 MiB thresholds remain in the system check, while `system.env` names are still not effective policy. | ADAPT | Q012 later resolves general threshold configuration with an explicit migration; preserve these effective boundaries until then. |
| Module API v1 | `docs/module_creation.md` and `module_loader.sh` define the permissive manifest, hook and isolated check contracts. `nextcloud_docker` remains v1; `system` retains explicit v1 hooks while adding disjoint v2 contributions. | TEMPORARY COMPATIBILITY | V2 declarations and necessary v1 registrations feed the owner-aware model while old hook views remain for current consumers. Remove v1 in Step 23 after bundled/external migration, equivalent tests, consumer retirement and a deprecation period. |
| Legacy menu loader | `core/lib/module_loader.sh:766-789` has owner-aware dispatch plus `_igor_load_module` fallback for old menu-file arguments. | TEMPORARY COMPATIBILITY | Remove after menus use the active registry/shared backend (Steps 5/20/23); meanwhile test disabled owners cannot be loaded. |
| Combined Nextcloud deployment | `modules/nextcloud_docker/` owns a working combined deployment, context and actions. | KEEP / TEMPORARY COMPATIBILITY | Preserve until v2 contracts and relationships prove a replacement in Step 18; do not split in Step 1. |
| AI request trust boundary | `core/ai/request_boundary.py:12-19,50-106` separates policy from `IGOR_REFERENCE_V1`; `core/ai/privacy.py:9-58` redacts before transport. | KEEP | Step 12 composes better reference material into this boundary. Reference material never authorizes. |
| Knowledge/context hooks | `core/ai/context.sh` gathers owner-filtered knowledge, context, tiers, patterns and catalog; `core/ai/knowledge.sh` reads saved files. These lack item-level relevance/provenance. | ADAPT; old text blocks TEMPORARY COMPATIBILITY | Step 12 selects typed, bounded reference items inside the existing pipeline. Retire an equivalent text source per consumer when its typed item is proven; preserve active-owner filtering and the `IGOR_REFERENCE_V1` boundary. Local learned artifacts remain separate from shipped knowledge. |
| Direct context probes | The memory request uses bounded typed System Model fact, health, active knowledge and capability items with provenance. `system__ai_context` no longer supplies a parallel RAM value. Other host/network/file and Nextcloud context probes remain labeled legacy reference data. | ADAPT | Migrate each remaining domain only after its observer/fact contract and selection mapping are authoritative; preserve `IGOR_REFERENCE_V1` and avoid duplicate facts. |
| System Model and observer bridge | `core/lib/system_model.py`, `model_bridge.py` and `observation.sh` now validate and commit typed active v2 observations into a private runtime snapshot, with failure/staleness and inspection. Direct `igor_v2_invoke` remains a raw compatibility/debug path, not a fact mutation path. | KEEP/ADAPT | Add further object kinds only with real observers and contract tests; D048 keeps the model current-state; Step 15B owns retained operational meaning. |
| Action catalog | The Wave C contribution index now supplies executable complete v2 descriptors to `run_capability` through the existing dispatcher and projects v1 `ai_capabilities` as `legacy.<owner>.<action>`. V1 `run_igor_action` still dispatches its own functions; those functions may use internal sudo and have no v2 verification guarantee. Bare Wave C declarations stay `contract_incomplete`. | KEEP/ADAPT; v1 actions TEMPORARY COMPATIBILITY | Map a v1 name to a canonical replacement only through a reviewed one-to-one cutover that preserves tier/behavior and suppresses duplicate execution. No v1 action was removed in Wave E; Nextcloud stays v1. |
| Legacy `ai_tools` text | V1 hook remains registered/documented but is not an executable catalog source (`README.md` hook table; `modules/*/module.sh`). | TEMPORARY COMPATIBILITY | Remove after v1 consumers migrate (Steps 6/11/23); test prose cannot add executable tools. |
| Interaction runtime and frontend events | `core/ai/core.sh` owns session command routing, approval state and an explicit ephemeral assistant-owned conversational choice; `core/ai/tui.py` projects ordered `core/ai/events.sh` activity events. Wave B guards short replies, local choice cancellation and malformed event sequence rejection. Step 15UI adds presentation-only focus/navigation, panel and schema/property primitives over this projection; durable history and Step 15C investigation inspection use their owning read-only CLIs. | KEEP/ADAPT | Reuse this backend in Step 20 and future interfaces. Frontend JSONL events stay distinct from future domain events; choice extraction remains limited to explicit alternatives in the latest reply. |
| Safety and privilege | `core/ai/safety.sh` owns the single READ/CHANGE/DESTROY gate and native PTY sudo authentication. Complete v2 descriptors declare privilege, and a reviewed Core adapter freezes exact argv before approval. D038 makes raw CHANGE explicit approval even in Executive. `executive_mode` setting translation remains (`:35-54`). | KEEP/ADAPT; TEMPORARY COMPATIBILITY for old setting | Additional privileged capabilities need reviewed exact-argv adapters before availability. Remove the old setting only after persisted callers migrate. Autonomy never grants root. |
| Classic menu, line chat and `--extra` | `igor.sh:471-485,1097-1120`, `core/lib/ui.sh:224-362`, `core/ai/core.sh` retain older interfaces. `core/extras/extra.sh:229-303` directly probes applications. | TEMPORARY COMPATIBILITY | Retain until shared TUI/backend covers their workflows (Step 20), then consolidate/remove in Step 23. |
| Legacy hybrid AI path | `core/lib/ai_hybrid.sh` is still sourced by the classic main menu when `AI_HYBRID_MODE=true`, but it maintains a separate conversation/context/provider/tool loop and its current config description no longer matches that implementation. Its useful cost/multi-model motivation is covered more cleanly by `MODEL_ROLES.md` / `AI_SPECIALISTS.md`. | ADAPT/REMOVE, live compatibility | Preserve only while current hybrid-menu users/behavior are checked. Do not evolve it into a second AI backend; later remove the implementation/settings surface once the primary TUI/runtime covers the user need and regression proves no consumer remains. |
| Core application leakage | `core/diagnose/phases.sh:450-453,644-648,923-927,1040-1044`, `core/lib/config.sh:13-45,145-200`, `core/lib/security_config.sh:20-60`, `core/lib/helpers.sh:35-61`, `core/extras/extra.sh:264-309` and recovery files embed Nextcloud/Docker/Cloudflare/Redis logic. Some paths gate on active capability, but core still owns deployment behavior. | ADAPT/REMOVE | Move domain behavior behind modules/integrations as Steps 5–12/18 make them authoritative. Preserve working gated workflows until then. |
| Generic healing configuration | `core/healing/core.sh:279-302` checks Nextcloud compose, root `db.env` and mount variables only when `nextcloud_docker` is active. This removes the inactive-owner requirement but leaves application logic in core. | ADAPT/REMOVE | Step 5 or later moves domain validation behind its owner when a replacement is ready; Step 2 tests preserve the active-owner gate. |
| Platform helpers | `core/lib/pkg.sh` now has tested Debian/Arch package query, install/remove/update/upgrade argv and systemd query/operation argv. Existing install callers and Docker post-install provisioner remain. | KEEP/ADAPT | Step 11 connects new mutation specifications to the approval/privilege gate; other families and unused host operations remain unclaimed. |
| Platform authority boundary | Package logical resolution currently defaults unknown family to Debian; `pkg_install` calls `sudo` directly. `core/lib/ui.sh`, `core/ai/context.sh` and `core/ai/scrub.sh` each probe LAN IP. | ADAPT | Step 7 makes new normalized operations fail closed and adds tested read/query plus mutation argv resolution while keeping `pkg_install` compatibility. Step 11 connects new mutation execution to existing approval/privilege gate. Keep redaction's live privacy probe independent of model freshness. |
| Docker post-install in platform code | `core/lib/pkg.sh:130-169` mixes package lifecycle with Docker provisioning. | ADAPT | Step 7 separates generic platform work once a domain owner/capability can take provisioning. |
| Configuration ownership | D059 / `CONFIGURATION.md` establish the Core Configuration Service and the bounded `ai.verbose` cutover. The loaders still own unmigrated defaults, variables, secrets, keys and root env; `config.sh` and `security_config.sh` still overlap paths/migrations. Declarative v2 schema admission is available without migrating a real module's values. | ADAPT / BOUNDED CUTOVER | Only `ai.verbose` transfers authority on an explicit canonical write; its old inputs are then ignored and its legacy settings writer no longer owns the key. Other keys retain current precedence. Remove each direct path only through its own source/target, validation, idempotency, verification and recovery proof. |
| AI verbosity preference | The existing verbose commands use the owning configuration change boundary. Legacy literal `verbose` inputs remain pre-cutover import sources; desired persistence, current-session consumption and verification are distinct. Other AI settings still use the specialized writer. | SINGLE-KEY MIGRATION | Retain old files as recovery/compatibility for their other keys; they cannot override migrated `ai.verbose`. No broad AI settings or environment migration is implied. |
| Root env and old settings | `config_loader.sh:190-211` and `config.sh` retain legacy file/settings locations. | TEMPORARY COMPATIBILITY | Remove after migration and usage checks (Steps 6/23); old files must not override new ownership indefinitely. |
| Notifications and admin communications | `core/notify/core.sh` is working outbound SMTP/notification behavior; `core/notify/aggregator.sh` retains another preference/state path. The historical `core/mailcmd/` implementation is absent, while UI/config/cron/docs preserve parts of its product intent. `COMMUNICATIONS.md` now records the proposed replacement architecture: shared outbound transport/configuration for notifications, reports and replies; replay-resistant authenticated inbound email; natural remote conversation; and bounded remote administration through normal capabilities/policy/history. | KEEP/ADAPT notifications; REDESIGN/PRESERVE mail intent | Do not delete the mail-control product intent during cleanup and do not resurrect the old verb/shell dispatcher. Preserve current outbound notification behavior until the shared transport/configuration boundary is proven. Step 22 owns authenticated external-interface/remote-approval work; old mailcmd hooks/config/UI become removable only after the replacement and migration are real. |
| AI operation audit | `core/ai/operations.py` and `control.sh` retain bounded tool classification/request traces and canonical operation references. They cannot describe the complete capability lifecycle. | TEMPORARY COMPATIBILITY PROJECTION | Step 15B records canonical episodes directly at execution; AI traces remain diagnostic projections/references. Never import partial tool events as authoritative episodes. Retire only after `--ai last` and audit consumers have an equivalent supported view. |
| Recovery journal and rollback | `core/recovery/journal.sh` retains command-oriented pipe records and an optional SQLite mirror for raw/v1 AI actions, Diagnose fixes, recovery menus, backups and rollback. | TEMPORARY LEGACY SOURCE | Canonical capabilities cut over to Operational History; preserve noncanonical callers and existing rollback/UI until their exact capabilities and recovery semantics replace them. No command-text import or generic history replay/undo. |
| Backup/recovery artifacts | Full-backup manifests, module-hook snapshots and configuration archives remain recovery artifacts with their existing retention/restore behavior. | KEEP | Operational episodes may reference real artifacts; history does not own archive contents or backup configuration. Preserve legacy journal records for these noncanonical workflows until an explicit cutover. |
| Chat `history` / `replay` | `core/ai/core.sh` and `session_commands.py` display session postmortems/transcripts. | TEMPORARY SESSION COMPATIBILITY | Preserve existing command names/behavior; Operational History has separate CLI inspection. Never reconstruct omitted episodes, approval, privilege or execution state from chat. Retire only after equivalent session-view consumers migrate. |
| Scheduling and long waits | Step 14 now has an Igor-owned automation registry plus one-time, periodic, event and typed condition READ admission, while older cron/scripts still serve real compatibility purposes such as backups. Long-running setup/install flows still lack a generic durable wait/resume contract. | ADAPT / REPLACE where authoritative replacements exist | Step 14 owns automation scheduling; `RESUMABLE_WORK.md` proposes separate durable `WAITING_USER` / `WAITING_EXTERNAL` plan state so OAuth, DNS, reboot and other dependencies do not become sleeping processes or subsystem-specific marker files. Retire cron/resume paths only after their exact consumer has an authoritative replacement. |
| Duplicate module tooling | `tests/test module scripts depreciated?/validate_module*.sh` contains overlapping experimental validators; CI lints them. | REMOVE / TEMPORARY COMPATIBILITY | Step 22 selects one v2 create/validate/test path, checks external use, then removes duplicates. These files must not define another module contract. |

## Regression properties to preserve

Step 15D extends the existing Context Engine and request boundary with bounded
selection and operational provenance; it does not create another gateway.
Owner-stamped knowledge candidates replace their aggregate runtime equivalent.
The summarizer now uses an explicit/inherited administrator binding instead of
a hard-coded vendor/model substitution. Existing settings, memory inspection,
legacy context domains, audit retention, native tool transaction handling,
v1 Nextcloud and classic/headless launch remain compatible. Removal of these
remaining paths requires their own equivalent-authority/consumer proof.
History/investigation storage is unchanged; selection records are not imported
as durable knowledge, memory or episodes. See [15D](CONTEXT_ROUTING.md).

1. Exercise activation across hooks, menus, action advertisement **and execution**, diagnose/healing, AI knowledge/context, config validation, backup/restore and notifications. Include disabled, unavailable and lazy/stale owners.
2. Keep the Step 2 Healing/Diagnose active-set and host-only storage guards when check contracts evolve; avoid reintroducing installed-only discovery.
3. Prove generic operation without an active application module does not require Nextcloud files, settings or commands, including healing validation and legacy UI/context.
4. Prove reference data and frontend event payloads cannot change tier, approval, privilege or ownership. Test pending mode changes and failed sudo authentication.
5. Pin Debian and Arch detection/package mappings with fixtures and mocked calls; test unsupported families separately.
6. Preserve exact operation dispatch and active ownership across interfaces; add verification-state guards when the capability contract defines them.

Step 2 added focused guards for current mechanisms. Broader capability
verification belongs with its later contract. D020 now sets the core versus
`system` ownership rule; physical code movement remains later work.

## Resolved in Wave A / Step 2

- Healing discovery no longer confuses manifest `provides` with active module
  identity. Tests reproduce the old failure and guard the corrected behavior.
- The three stale system-storage expectations were replaced with host-only
  assertions and a direct check of `nextcloud_docker` storage behavior. The
  system module was not given back application storage checks.
- Generic Healing configuration checks and startup module-config validation
  now respect active ownership; their broader core/configuration placement
  remains migration work.

## Wave B / Steps 3–4 disposition

- Keep the backend interaction state, registry and `events.sh` stream. The
  choice record now states its owner/type/lifecycle, and a bare `cancel`
  dismisses an active choice before provider input. The TUI rejects invalid
  event sequence values. Neither change creates a second authority.
- Keep the native sudo-through-PTY implementation. Approval precedes
  authentication and exact command execution; a declined action emits no
  privilege event and invokes no sudo command. A shared capability privilege
  declaration is deferred to Step 11 because the current v1 catalog has no
  general privilege metadata to pass through this gate.
- Retain `exec on/off` and persisted `executive_mode` as compatibility with
  current settings and callers. Retain classic line UI and `--extra` until
  Step 20 covers their workflows. No Wave B compatibility path was proven
  unused with an authoritative replacement, so none was removed.
- Retain the `continue` failure recap derived from conversation text as
  non-authoritative narrative. Its pause/resume command is backend-owned;
  Step 15 can replace the recap source once structured operational outcomes
  cover that history. Conversation prose cannot approve or elevate work.
- `/stop` currently acts at an approval prompt or the next backend chat
  prompt. Synchronous provider/tool calls are not
  interrupted mid-call. Keep that boundary explicit in the UI until a tested
  cancellation contract exists; do not imply preemptive cancellation.

## Wave C implementation — compatibility conditions

- Keep `_ml_read_conf` and its section-blind first-key behavior for v1 only.
  A strict section-aware v2 manifest parser replaces it for v2 metadata;
  v1 files do not silently acquire new parsing semantics.
- Keep omitted `config/modules.conf` entries enabled for v1 compatibility.
  Newly installed v2 modules require explicit enablement. Before converting
  the bundled `system` module, preserve an implicitly enabled installation
  with an explicit `system=enabled` entry; never override a disabled entry.
- Keep v1 `depends_on` as ordering-only and `provides` as a legacy feature
  token. `nextcloud_docker` must continue working without active `system`;
  neither field becomes a v2 hard dependency or executable capability by
  inference.
- Existing `test_module_contracts.bats` assumes every module has v1 health
  and diagnose functions. Make that test version-aware when `system` migrates;
  v2 permits a package with only knowledge and observers. Do not restore empty
  hooks merely to satisfy the old test.

The implementation now applies these conditions. `core/lib/module_contract.py`
is the single strict v2 manifest/contract validator and
`core/lib/module_handler.sh` is the Bash adapter. Invalid metadata is rejected
before entrypoint sourcing; disabled v2 packages are not sourced. The loader's
single contribution index records owner, source, kind and availability, and
`igor_module_list` exposes module API/state/reason plus contribution ownership
and provenance. Local requirement failures withhold only the affected
contribution; module-wide dependency failures make the owner unavailable.

The `system` slice provides static `host.basics` knowledge and the structured
`host.memory` observer while retaining v1 hooks. Its explicit policy migration
preserves omitted-entry compatibility and explicit disablement. This is a
contract migration proof, not a broad storage or application-module migration.
`nextcloud_docker` remains the v1 compatibility proof and is intentionally
unchanged by the v2 package contract.

## Wave D design gate — compatibility conditions

- Keep direct `system` memory/context/check probes until the new fact/check
  path is validated and a consumer has cut over. At that cutover suppress the
  equivalent legacy RAM result for that consumer; do not assert both sources
  or double-count a check.
- Keep Diagnose phases, gates and fix loop, Healing score/cache/alerts, and
  active Nextcloud v1 checks. Their text outputs can be projections or v1
  adapter inputs; they are not authoritative System Model facts.
- Keep the module loader, contribution index, Bash adapter and AI reference
  boundary. New validation sits between observer output and System Model
  mutation. Inactive modules contribute no current facts or checks.
- Keep current package-install and Docker post-install callers until a tested
  domain capability replaces them. New platform mutation descriptions do not
  create an independent privileged execution path.
- No Wave D persistent fact layout is adopted. Rebuild observations after
  restart and rehydrate only intent with an existing named authoritative
  source. Later Ownership Foundation/Q003 changes require explicit cutover
  and recovery proof.

## Wave D cutover disposition

- The first condition is met for memory: the typed observer/check now serves
  AI context, Diagnose and Healing, and redundant RAM probes/check lines were
  removed. Other temperature, swap, load, storage and network direct probes
  remain compatibility paths until their own observers/checks exist.
- The shared health runner owns active v1 file/hook execution; `CHECK:` and
  `CHECK_RESULT` remain presentation/adaptation formats for v1 modules.
  `nextcloud_docker` remains on v1 with its existing activation filtering.
- Observed facts and health results live only in a private runtime snapshot
  unique to each Igor process. New processes start `not_observed`; no fact
  database, scheduler, domain event bus or new intent editor was introduced.

## Wave E cutover disposition

- Keep v1 `ai_capabilities` and `run_igor_action` for existing actions,
  especially Nextcloud v1. Their synthetic `legacy.<owner>.<action>` records
  are inspection/advertising compatibility, not a second v2 executor. No v1
  action was removed because none has a proven canonical replacement.
- Complete v2 capabilities dispatch through the existing `safety.sh` approval
  and PTY path. A declaration lacking the Step 11 fields, a reviewed secret
  consumer, or a required privileged argv adapter remains unavailable with
  an inspectable reason. The `system` memory capability is the first live
  canonical path; the service CHANGE operation is an isolated fixture proof.
- Keep raw `host`/`execute` shell for unstructured fallback under D038. Exact
  recognized canonical forms are rejected; other raw CHANGE requests require
  explicit approval even in Executive and have no claimed postcondition.
  Retire a raw form only when its canonical replacement is registered and
  usable under the maintained equivalence map.
- Keep broad legacy AI context for domains without an authoritative model
  source. The memory domain now has one bounded Context Engine selection and
  does not repeat the old RAM probe. Legacy `ai_context`, knowledge and saved
  text remain reference data; no new operational state is inferred from them.
- The new secret-reference adapter has no live value consumer. It uses opaque
  references and value-free authorized-access metadata; today's private file
  registration is internal and does not set the future Ownership Foundation
  public layout. No persistent migration or generic rollback was added.

## Cross-cutting execution implications

The ServerMind/Steward-derived machine-model and execution lessons are now
explicit target contracts, but they do not authorize premature rewrites.

- Existing direct probes remain ADAPT paths until authoritative observers/System
  Model facts replace them and regression/inspection proof is green.
- Existing configuration/secrets paths remain migration inputs; broad Module v2
  migration must not make their current mixed ownership layout permanent.
- `system` is the Wave C v2 proving module. `nextcloud_docker` remains v1
  during Wave C and becomes the first broader post-Wave-C vertical slice.
- Existing journal rollback hooks remain useful compatibility/recovery inputs,
  but Igor 2 does not promise generic rollback; capability/plan recovery
  semantics become authoritative when Step 11 is implemented.
- Chat/context/history compatibility paths remain non-authoritative. Durable
  machine memory and investigations replace them only when structured state
  and migration/recovery proof exist.
- Inspection is added with each new authoritative subsystem; later TUI work
  consolidates it rather than introducing it for the first time.

## Step 15C disposition

The investigation service is a new, separate authority for knowledge organization;
there is no legacy investigation store to import or retire. Chat/history/replay
remain session compatibility views, and the command journal keeps its existing
noncanonical callers. Investigation references do not copy/replace Operational
History or current System Model state. 15UI's shared panel/structured renderer
adds read-only inspection without a special UI. No Step 20 interface cutover,
automation integration or automatic context consumer is introduced.
