# Igor 2 legacy and preservation map

Wave C implementation is now present on `igor2`. This map records the v1
compatibility surfaces that remain live alongside the first v2 path.

Wave A / Step 1 audit of the `igor2` tree at `6675ece` (2026-09-26). Local
`master` (`76f04e3`) is an ancestor. Code and tests establish current behavior;
the [architecture](ARCHITECTURE.md) sets the target. `KEEP/ADAPT` means preserve
the working implementation while extending its contract. Compatibility entries
give a removal condition.

| Area | Current evidence and assessment | Classification | Migration target / removal condition |
|---|---|---|---|
| Module activation and ownership | `core/lib/module_loader.sh` now separates v1/v2 discovery, policy, validation, staged activation and owner-aware contribution inspection. Hooks, menus and actions retain inactive-owner filtering; v2 state/reason and contribution queries are exposed alongside the existing views. | KEEP/ADAPT | Keep the single loader, state vocabulary and restart semantics. Retire v1 views only after their consumers migrate and equivalent behavior is proven; no hot unload. |
| Healing check activation | `core/healing/core.sh:43-65` now uses `igor_has_module` for module identity. `tests/modules/test_healing_activation.bats` guards active, disabled, unavailable and installed-only discovery against Diagnose's active set. | KEEP/ADAPT | Step 10 can unify result/discovery contracts without regressing active-owner filtering. |
| Diagnose and healing checks | `core/lib/diagnose_runner.sh:39-104` dispatches hooks and active module check files; `core/healing/core.sh:43-147` discovers and caches checks separately. Diagnose accepts `CHECK:` and `CHECK_RESULT`; healing consumes `CHECK_RESULT`. | ADAPT | Steps 5/10 share structured results/discovery while keeping distinct user workflows. |
| Module API v1 | `docs/module_creation.md` and `module_loader.sh` define the permissive manifest, hook and isolated check contracts. `nextcloud_docker` remains v1; `system` retains explicit v1 hooks while adding disjoint v2 contributions. | TEMPORARY COMPATIBILITY | V2 declarations and necessary v1 registrations feed the owner-aware model while old hook views remain for current consumers. Remove v1 in Step 23 after bundled/external migration, equivalent tests, consumer retirement and a deprecation period. |
| Legacy menu loader | `core/lib/module_loader.sh:766-789` has owner-aware dispatch plus `_igor_load_module` fallback for old menu-file arguments. | TEMPORARY COMPATIBILITY | Remove after menus use the active registry/shared backend (Steps 5/20/23); meanwhile test disabled owners cannot be loaded. |
| Combined Nextcloud deployment | `modules/nextcloud_docker/` owns a working combined deployment, context and actions. | KEEP / TEMPORARY COMPATIBILITY | Preserve until v2 contracts and relationships prove a replacement in Step 18; do not split in Step 1. |
| AI request trust boundary | `core/ai/request_boundary.py:12-19,50-106` separates policy from `IGOR_REFERENCE_V1`; `core/ai/privacy.py:9-58` redacts before transport. | KEEP | Step 12 composes better reference material into this boundary. Reference material never authorizes. |
| Knowledge/context hooks | `core/ai/context.sh:135-186` gathers owner-filtered knowledge, context, tiers, patterns and catalog; `core/ai/knowledge.sh:38-70` reads saved files. | ADAPT | Steps 8/9/12 distinguish domain knowledge from observed state and compose relevant facts with provenance/freshness. |
| Direct context probes | `core/ai/context.sh:14-92,218-245` probes host/network/files and filters Nextcloud/Redis/DB pattern names. Module context probes application state (`modules/nextcloud_docker/module.sh:583-640`). | ADAPT | Replace equivalent probes when observers and System Model facts become authoritative (Steps 8–12); preserve the reference envelope. |
| Action catalog | `core/lib/module_loader.sh:877-932`, `core/ai/control.sh:15-100`, `core/ai/catalog.py:36-66` provide owned, tiered `ai_capabilities` and `run_igor_action`. General inputs, privilege, preconditions, verification, affected objects and events are absent. | KEEP/ADAPT | Step 11 generalizes this registry into the shared capability API, without a parallel catalog. |
| Legacy `ai_tools` text | V1 hook remains registered/documented but is not an executable catalog source (`README.md` hook table; `modules/*/module.sh`). | TEMPORARY COMPATIBILITY | Remove after v1 consumers migrate (Steps 6/11/23); test prose cannot add executable tools. |
| Interaction runtime and frontend events | `core/ai/core.sh` owns session command routing, approval state and an explicit ephemeral assistant-owned conversational choice; `core/ai/tui.py` projects ordered `core/ai/events.sh` activity events. Wave B guards short replies, local choice cancellation and malformed event sequence rejection. | KEEP/ADAPT | Reuse this backend in Step 20 and future interfaces. Frontend JSONL events stay distinct from future domain events; choice extraction remains limited to explicit alternatives in the latest reply. |
| Safety and privilege | `core/ai/safety.sh` owns tiers, approval and native sudo authentication for the exact approved command. Wave B guards that a declined action never authenticates; existing PTY tests cover password isolation and failure. `executive_mode` setting translation remains (`:35-54`). | KEEP/ADAPT; TEMPORARY COMPATIBILITY for old setting | Step 11 can declare privilege requirements in capability metadata and feed the same backend execution gate; do not add a second sudo broker. Remove the old setting only after persisted callers migrate. Autonomy never grants root. |
| Classic menu, line chat and `--extra` | `igor.sh:471-485,1097-1120`, `core/lib/ui.sh:224-362`, `core/ai/core.sh` retain older interfaces. `core/extras/extra.sh:229-303` directly probes applications. | TEMPORARY COMPATIBILITY | Retain until shared TUI/backend covers their workflows (Step 20), then consolidate/remove in Step 23. |
| Unused hybrid AI path | `core/lib/ai_hybrid.sh:27-243` has a separate context/provider loop and Nextcloud fallback; no repository caller was found in Step 1. | REMOVE, pending external-use check | Remove after external use is checked (Steps 20/23); do not make it a second active backend. |
| Core application leakage | `core/diagnose/phases.sh:450-453,644-648,923-927,1040-1044`, `core/lib/config.sh:13-45,145-200`, `core/lib/security_config.sh:20-60`, `core/lib/helpers.sh:35-61`, `core/extras/extra.sh:264-309` and recovery files embed Nextcloud/Docker/Cloudflare/Redis logic. Some paths gate on active capability, but core still owns deployment behavior. | ADAPT/REMOVE | Move domain behavior behind modules/integrations as Steps 5–12/18 make them authoritative. Preserve working gated workflows until then. |
| Generic healing configuration | `core/healing/core.sh:279-302` checks Nextcloud compose, root `db.env` and mount variables only when `nextcloud_docker` is active. This removes the inactive-owner requirement but leaves application logic in core. | ADAPT/REMOVE | Step 5 or later moves domain validation behind its owner when a replacement is ready; Step 2 tests preserve the active-owner gate. |
| Platform helpers | `core/lib/distro.sh:16-59`, `core/lib/pkg.sh:31-126` map families, logical packages/services and install; `igor.sh:87-104` resolves Arch Python. Other normalized package operations are absent. | KEEP/ADAPT | Step 7 extends and tests Debian/Arch query/install/remove/update and service/host operations. Other family mappings do not imply support. |
| Docker post-install in platform code | `core/lib/pkg.sh:130-169` mixes package lifecycle with Docker provisioning. | ADAPT | Step 7 separates generic platform work once a domain owner/capability can take provisioning. |
| Configuration ownership | `core/lib/config_loader.sh:190-211,280-335` loads defaults, variables, secrets, keys and deprecated root env; Step 2 now filters same-process disabled owners before config validation. `core/lib/config.sh:21-104,129-165` and `security_config.sh` still define overlapping defaults/migrations, including app paths. | ADAPT | Steps 5/6/7 assign generic and module settings to one authoritative validation path; preserve secret precedence and permissions. |
| Root env and old settings | `config_loader.sh:190-211` and `config.sh` retain legacy file/settings locations. | TEMPORARY COMPATIBILITY | Remove after migration and usage checks (Steps 6/23); old files must not override new ownership indefinitely. |
| Notifications and mail | `core/notify/core.sh:46-90,174-288` collects module events and sends SMTP; `core/notify/aggregator.sh:19-39,105-128` has another state path. `core/mailcmd/` is absent; `igor.sh:579-588,1154-1176` retains mail UI/help and fails closed. | KEEP/ADAPT notifications; REMOVE stale mail affordances | Steps 13/22 feed outbound transports from domain events and reconcile aggregator state. Remove incoming-mail affordances when UI/docs are corrected; any future mail control uses shared capabilities. |
| Recovery and history | `core/recovery/full_backup.sh:31-80` records partial module-hook backups; `core/recovery/journal.sh:1-40,69-102` provides append-only/optional SQLite journal; `core/ai/operations.py:21-48,84-112` keeps bounded private audit. Journal/recovery UI still contain Nextcloud behavior (`journal.sh:389-423`, `core/recovery/core.sh:90-117`). | KEEP/ADAPT | Step 15 evolves operational episodes with approval, privilege, verification and outcome. Domain behavior moves from core later. Chat history is not operational state. |
| Scheduling | Existing scripts/hooks do not form one Igor-owned automation registry, policy and history. | REPLACE where applicable | Step 14 introduces Igor-owned automation; modules declare intent. |
| Duplicate module tooling | `tests/test module scripts depreciated?/validate_module*.sh` contains overlapping experimental validators; CI lints them. | REMOVE / TEMPORARY COMPATIBILITY | Step 22 selects one v2 create/validate/test path, checks external use, then removes duplicates. These files must not define another module contract. |

## Regression properties to preserve

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
