# Igor 1 cutoff and simplification plan

Status: **bounded M1 cutoff and Python coordination accepted (D080/D081); not implemented**.

Updated: 2026-10-18. Inventory baseline `1aac86a`. This plan replaces the earlier legacy
inventory; original evidence remains in Git and [archived STATUS](archive/STATUS_2026-10-16.md).
[Development policy](DEVELOPMENT_POLICY.md) protects data, platforms and safety,
not obsolete Igor 1 interfaces. [M1](ROADMAP.md#m1--one-module-and-operation-platform)
is the finite cutoff milestone; later cleanup is not permission to keep v1 alive.

## Unprivileged execution continuation from `2ad217b` — implemented boundary

The current source extends the existing Python capability runtime with module
admission against the loader's active owner/handler/timeout/version facts, exact
proposal fencing, atomic unprivileged History claim and isolated invocation.
Core configuration/deployment adapters use the same Python claim before effects.
Python finalizes proposal status/version/digest and evaluates owner-active and
contained path-existence preconditions. The previous shell implementations of
those checks/claim are removed in this candidate; no parallel executor or registry
is added. Verification-only readbacks retain their bounded READ invocation.

Shell still supplies the active contribution index and admission snapshot,
platform argv preparation and live configuration/service/package/model probes,
approval/native sudo PTY, collection leases/context and synchronous event delivery.
It also owns Core service adapter dispatch, the approved process-local memory
consumer, verifier selection, provider completion/result publication, plan and
composite sequencing. These responsibilities remain M1 work; native OS privilege
and terminal handling stay where they are until a concrete consumer requires change.

The exact prior 447 identities pass; additional affected, fixture-consumer,
frontend event/native PTY and targeted final runtime/History/collection/CLI/
process-local configuration checks pass. The final transport distinguishes
unclaimed setup/launch refusal from post-claim provider failure; neither duplicate
nor unknown attempts replay or overwrite prior results. Context stays on stdin,
outside child environments, and raw-handler error status remains unchanged.
See the five-class ledger and stage-attributed counts in [STATUS](STATUS.md).
The final runtime correction has targeted proof, not a fresh repository-wide run.

Existing History records keep their meaning and are not reinterpreted or replayed.
Changed pending proposals must reprepare and pass normal approval/fencing. There
is no data/schema/root migration. Historical ownership/evidence below describes
its named committed baseline; this paragraph owns the newer boundary. Remaining
Python index/loading, live preparation/authorization, verification/publication
and plan coordination need their own coherent consumer cutovers. No package/config
migration, offline data transition, v1 retirement or M1 completion is claimed.

## Target and non-goals

Only strict Module API v2 is supported in the Igor 2 runtime. No v1 parser,
registration callback, compatibility hook, legacy action adapter, implicit
activation default or environment fallback remains reachable. Reject an old
package with a clear unsupported-interface error; do not translate it at runtime.
`master` remains an independent program and is not modified by this cutoff.

Preserve user data and native applications; reuse useful algorithms and selected
capabilities. No Igor 1 compatibility or mandatory feature parity. Account for
omitted operations explicitly and preserve unsupported configuration offline.
Module API v1 is **not** the same version axis as a version-1 capability result,
History schema or reference envelope. Do not delete records or rename every
`v1` token. Each changed internal contract migrates its own consumers/data.
No permanent compatibility framework is needed for a one-time explicit import.

## Remove, replace, retain

| Surface/source | Required disposition | Removal proof |
|---|---|---|
| `module_loader.sh` permissive v1 manifest parsing, `__register`, `igor_register_hook`, legacy registration maps | Remove after all consumers use admitted v2 declarations | v1 package rejected before source; no callable registration path |
| `module_loader_fast.sh` old-function copies/overrides | Retire with the authoritative loader implementation; keep necessary digest/activation invalidation | cold/warm registry equivalence and stale-owner refusal |
| `compat.v1_hooks`, omitted-api/implicit-enable semantics | Remove; explicit `module_api=2` and activation policy | inactive code/knowledge/checks never load |
| `ai_capabilities`, `ai_tools`, `ai_tiers`, ACTION/FUNCTION blocks, `legacy.*`, `run_igor_action` | Replace with canonical capability metadata/dispatch | no alternative executable ID or fallback resolution |
| Module-owned menu operations and direct shared menu writes | Replace selected operations with canonical typed presentation; defer/remove other interfaces and retain useful source material | each UI/AI/automation request reaches same operation ID/History |
| Core Nextcloud diagnosis/recovery/helpers/provider imports | Move domain semantics to Nextcloud package; use shared owner-aware resolution | Core contract/dispatch works without Nextcloud installed |
| `config.sh`/`config_loader.sh` sourcing, root/HOME env fallback and startup moves | One scoped desired/secret/path authority; explicit offline import | startup ignores legacy files and writes no migration state |
| Module schemas/defaults versus machine config | Retain schemas/defaults in packages; persist local values outside | installed package can be read-only; disable has no active validation contribution |
| Canonical approval/privilege/verification, private History | Retain and extend to all selected operations | exact approval, refusal, pre-effect History, independent readback |
| Platform package/service adapters, useful Bash/Python handlers | Retain where correct; remove orchestration/implicit globals from handler contract | declared distro behavior and bounded I/O |
| Safe configuration/secret/deployment/investigation/learning stores | Retain identity/recovery semantics; migrate only affected fields/roots | export/import/interrupt/re-entry/ref-unavailable scenarios |
| Classic hybrid/line/operator duplication | Keep one primary curses UI and first-class CLI; port selected interactions before retirement | selected operations, provider setup and native PTY flow |
| Textual `core/lib/igor_tui.py`, dormant path wrapper chain | Delete if final caller inventory confirms no supported consumer | no tracked/dynamic registration/export references |
| Deprecated test script copies and duplicate canary | Keep one called canonical copy; delete duplicates | callers updated; same canonical behavior |
| Old install/recovery scripts | Preserve useful mechanics as inactive source material; M4 implements canonical durable procedures | no separate authorization/History/execution controller |

M1 delivers final Python execution and module coordination, reusing reviewed
Bash/Python leaf handlers. M2 adds durable AI task/conversation orchestration;
it does not replace a transitional M1 executor or module coordinator.

## Shipped-module disposition

| Module | Current state | Required rewrite/retention |
|---|---|---|
| `system` | v2 plus v1 hooks; host/storage/access/network declarations | Select useful integrated operations from the 40 capabilities; migrate selected observers/checks/knowledge/config and remove compatibility hooks |
| `docker` | v2, four capabilities, optional System dependencies | Retain; adapt to sole executor/config API, verify explicit targets and disable isolation |
| `nextcloud_docker` | v1 with extensive menus/hooks, 12 AI actions, recognition/attachment code | V2 attachment and configuration only in M1; explicit deployment/config/secret refs and native readback; other operations deferred/removed |
| `samba` | recognition Python adapter only, no module manifest | Keep as bounded recognition fixture/reference consumer if used; do not advertise a complete package or create a new product milestone |

Do not split Nextcloud's PostgreSQL, Redis, web proxy and tunnel into independent
module products merely to satisfy a diagram. Domain decomposition needs actual
reuse and independent lifecycle value. Docker already supplies generic substrate.

### M1 operation disposition at `21da2b5`

This is the implementation inventory for the Owner-authorized M1 task, not
an acceptance claim. Selected operations keep their existing IDs, versions,
typed results, privilege requirements and verification semantics. The eight
unselected System mutations remain reusable source material until their old
callable interfaces are retired during the M1 cutoff; no native state is removed.

| Capability | Tier | M1 disposition |
|---|---|---|
| `docker.container.list` | READ | Retain |
| `docker.container.restart` | CHANGE | Retain |
| `docker.install` | CHANGE | Retain |
| `docker.status` | READ | Retain |
| `system.groups.list` | READ | Retain |
| `system.groups.status` | READ | Retain |
| `system.host.memory.refresh` | READ | Retain |
| `system.host.runtime.status` | READ | Retain |
| `system.host.summary` | READ | Retain |
| `system.logs.summary` | READ | Retain |
| `system.memory.warning.apply` | CHANGE | Retain |
| `system.memory.warning.readback` | READ | Retain |
| `system.network.dns.status` | READ | Retain |
| `system.network.interface.status` | READ | Retain |
| `system.network.interfaces.list` | READ | Retain |
| `system.network.routes.list` | READ | Retain |
| `system.network.summary` | READ | Retain |
| `system.network.wifi.connect_known` | CHANGE | Defer |
| `system.network.wifi.profiles.list` | READ | Retain |
| `system.network.wifi.scan` | READ | Retain |
| `system.network.wifi.status` | READ | Retain |
| `system.package.cache.clean` | CHANGE | Defer |
| `system.package.cleanup.preview` | READ | Retain |
| `system.package.install` | CHANGE | Retain |
| `system.package.updates.list` | READ | Retain |
| `system.package.upgrade` | CHANGE | Defer |
| `system.permissions.group.set` | CHANGE | Defer |
| `system.permissions.mode.set` | CHANGE | Defer |
| `system.permissions.owner.set` | CHANGE | Defer |
| `system.permissions.path.status` | READ | Retain |
| `system.service.enable` | CHANGE | Retain |
| `system.service.list` | READ | Retain |
| `system.service.restart` | CHANGE | Retain |
| `system.service.start` | CHANGE | Retain |
| `system.service.status` | READ | Retain |
| `system.storage.filesystem.status` | READ | Retain |
| `system.storage.filesystems.list` | READ | Retain |
| `system.storage.mount` | CHANGE | Defer |
| `system.storage.mount.status` | READ | Retain |
| `system.storage.mounts.list` | READ | Retain |
| `system.storage.summary` | READ | Retain |
| `system.storage.unmount` | CHANGE | Defer |
| `system.users.list` | READ | Retain |
| `system.users.status` | READ | Retain |

Nextcloud retains recognition and explicit metadata attachment plus the bounded
`nextcloud_docker.loglevel` desired-state/commit/apply/readback/recovery workflow.
Core configuration and deployment capability IDs retain their existing meaning;
application-specific provider selection moves to the Nextcloud package in M1.
The new native-setting operation declarations will be recorded with their package
conversion, before exposing them through the shared executor.

| Former interface group | M1 disposition / data handling |
|---|---|
| System health, diagnose and AI-context hooks | Replace selected observations/checks/knowledge with existing v2 declarations; no duplicate hook registration |
| System mail, notify, recovery hooks and legacy menus | Remove callable interfaces; retained native configuration stays in place |
| Docker four v2 capabilities | Retain through Python execution; install composes selected System capabilities and still needs explicit authorization |
| Nextcloud health/status/diagnosis/permission reads | Retain only recognition/attachment/configuration reads; defer broader diagnostics |
| Nextcloud scan, cache flush, repair, permission repair and database maintenance actions | Defer; retire v1 actions, preserve useful implementation in source history |
| Nextcloud services start/stop/restart/logs | Generic selected Docker operations only; defer application-wide administration |
| Nextcloud app, maintenance, upgrade and configuration menus | Defer except loglevel; no replacement callable menu or fallback |
| Nextcloud setup/wizard/install/backup/restore/recovery | Defer to explicitly authorized later work; preserve existing backups and native application data |
| Nextcloud notify/mail/AI tooling/tier/pattern/knowledge/health-gate/role/alert/config/rollback/menu-header hooks | Remove registrations; selected reference knowledge and configuration belong to v2 declarations |
| Host-wide Nextcloud NUKE | Remove without a replacement; never enumerate/delete native volumes or images as migration |

Data sources, conflicts, private export, idempotency and recovery follow the
source-family table and offline migration protocol below. This task changes no
production deployment, policy file, personal configuration or data store. Existing
declared roots remain authoritative. Unsupported values must be preserved offline
before the runtime sourcing paths are cut off.

### M1 implementation batches

- **Python handler process boundary (implemented; focused proof in STATUS):** `module_handler.py` owns
  isolated invocation, request/path validation, bounded pipes, deadline and process
  cleanup. `module_handler.sh` only transports remaining shell callers and forwards
  session-local domain events. The separate collection-only `bounded_handler.py`
  process wrapper is retired; its limits and negative tests migrate to the shared
  adapter. Canonical typed-output validation and approval/History remain upstream.
- **Python activation policy (implemented; focused proof in STATUS):** the existing
  registry owns parsing and atomic explicit changes in `config/modules.conf`.
  Loader, inspection, attachment and collection consumers share it. Omitted
  packages stay inactive; malformed policy fails closed. The startup System-policy
  migration and v1 implicit activation are retired. Existing policy/backups remain
  untouched until an explicit enable/disable command; no data import is implied.
- **Python execution fencing/results (implemented; focused proof in STATUS):** the existing
  capability runtime compares exact frozen/live proposal content and derives
  single-operation terminal outcomes from provider/output/verifier observations. The shared shell adapter
  transports those observations and retains current approval/native PTY, History
  ordering and process-local configuration effects; no competing executor exists.
  Focused evidence covers approval, privilege, History, CLI, typed outputs,
  collections and process-local configuration; broader M1 acceptance stays open.
- **Python privileged dispatch (implemented; bounded proof in STATUS):** the
  capability runtime now validates the reviewed native argv, repeats the exact
  approved-proposal fence, atomically claims the admitted History operation and
  executes its ordered commands with noninteractive sudo. Claim failure prevents
  effects; duplicate claims cannot replay. The former inline shell executor is
  removed. Approval/native PTY and common verification/publication stay upstream
  and downstream respectively; this is not full execution-coordinator migration.
- **Still required in M1:** Python loading/resolution/authorization/History
  coordination and all consumers; selected package and configuration cutovers;
  offline data transition; retirement of v1 loader/hooks/actions/menus/startup
  sourcing; real System/Docker/Nextcloud proof and independent review.

The remaining shell coordination is the pre-existing implementation being migrated
inside M1, not a new runtime to be carried into M2. No M1 completion is claimed.

### Execution ownership and remaining cutover at `4fa4abb`

The operation path is shared: AI tool parsing/native transaction validation,
operator CLI/backend requests, collection selections and automation submit
`run_capability` to `ai_execute_tool` in `core/ai/safety.sh`. No frontend result
grants execution authority. The current ownership boundaries after this batch are:

| Stage | Current authority / remaining shell responsibility |
|---|---|
| Admission and proposal | Python `module_contract.py`, `module_registry.py` and `CapabilityRegistry` validate policy/descriptors/inputs/resolution/composition; shell loader still builds the active contribution index. `igor_capability_prepare` binds reviewed platform argv, evaluates live preconditions and stamps provider version/digest |
| Identity and approval | Python `OperationalHistory` owns durable identity, transitions, binding, export and interrupted-state recovery. Shell `_igor_history_begin` sequences recovery/admission before approval; `ai_execute_tool` selects deterministic mode/tier policy, freezes pending content, handles Explain/No/Stop/exact YES and records authority |
| Privilege | Existing native sudo PTY stays in `safety.sh`; refusal never authenticates. Python native dispatch uses only reviewed `sudo -n --` commands and claims History before effects |
| Execution | Python exact fence and privileged command sequence; shared Python `module_handler.py` isolates Bash leaf handlers. Shell still re-resolves availability/preconditions, checks collection leases, selects Core configuration/deployment handlers, claims unprivileged operations and applies process-local memory configuration/observer/check effects |
| Verification and result | Shell selects and invokes deterministic current verifiers and sends provider-complete observations to History. Python validates typed output/collections and constructs canonical single-operation outcomes. Plan sequencing/final checks and composite result construction remain in `capability.sh`/`safety.sh` |
| Publication and projection | Shell `_igor_capability_publish_result` writes the session result, finishes Python History and publishes domain events; dispatcher projects status/audit/events. CLI and generic Python TUI consume the same result/History. Durable History stays authoritative across restart; session result files are projections |

Smallest safe continuation: migrate preparation/preconditions/platform binding
and the admitted index to Python, then move shared authorization and single-
operation sequencing using the existing PTY transport and configuration services.
The process-local memory consumer must be migrated with its callers: executing
it in a disposable Python/Bash child would lose the approved session effect.
Move verification/History/publication and plan/composite sequencing with their
consumers; remove each old coordinator at its tested cutover. M2 conversation
state is not required for these deterministic execution changes.

| Remaining M1 work | Dependency / readiness |
|---|---|
| Selected System/Docker operations | Existing disposition above is frozen; declarations and useful handlers exist. Sole Python index/executor and CLI/TUI/disabled-owner proof must precede removal of System compatibility hooks; deferred mutations need no new features |
| Nextcloud configuration | Recognition/metadata attachment services exist, but the package is still v1. Needs v2 bound configuration contracts, desired/commit/apply/readback and exact deployment/application-user checks before real loglevel acceptance |
| Offline transition | Source families/protocol below are defined; complete offline inventory/import/export/conflict/interruption/re-entry/recovery tooling and sentinel startup proof are not implemented. Reuse declared roots; no new layout or native-data moves authorized |
| V1 retirement | Blocked on selected consumers and offline preservation: loader/fast-loader, registrations/hooks/actions/menus, startup sourcing/moves and Core Nextcloud coupling remain reachable. Search-only evidence cannot justify deletion |
| Acceptance | Needs real System/Docker and CLI/curses/native PTY slices, disposable Nextcloud attach and `2 → 3 → 2`, one broad integration pass and Owner-designated independent review. Existing fixture/mocked proof is not closure; production data remains excluded |

## Configuration and retained data transition

The audit did not open personal secrets or enumerate their values. These are
source-derived location families to inventory during migration, not a claim that
all exist on this machine.

| Source family | Handling |
|---|---|
| `config/variables/*.env`, `core/config/defaults.env` | Reconcile shipped defaults into schemas; do not treat tracked defaults as personal state |
| Root/project `.env`, `config.env`, `ai_settings.env`, `system.env`, `secrets/site.env`, module-declared env inputs | Data-only parse supported assignments; report duplicate/conflicting values with source, never evaluate shell |
| `secrets/*.env`, provider `.key` files, HOME provider fallbacks, DB/JWT/tunnel credentials | Private import into secret authority; config receives references; never print values or automatically fall back after cutover |
| Managed OpenRouter catalog/generation state | Preserve current fail-closed lifecycle, reference identity and cutover semantics; do not re-import retired aliases |
| `$HOME/.config/igor`, `NEXUS_CONFIG`, explicit `IGOR_DATA_DIR`, checkout `data/` | Inventory actual resolved roots and store versions; preserve scope/identity relationships |
| History SQLite, deployments, investigations, learning/pattern/procedure/knowledge records | Use owning service exports/validation; retain unknown/orphaned references explicitly, never reinterpret old effects |
| Backups, session/issue/report archives, GPG homedir, user-authored knowledge | Copy privately and verify; distinguish reference archives from active AI context; preserve GPG permissions |
| Native Nextcloud/Compose/DB/volume data and config | Leave in place; bind native locators and ownership. No volume migration or data deletion as module cleanup |
| Runtime locks/caches/PTY state | Stop sessions; discard only identified disposable state after durable records are safe |

Proposed canonical roots: per-user XDG configuration/state/runtime with explicit
supported overrides and a declared system-install profile. Exact paths are selected
only if a required layout change is separately confirmed; D081 does not select
them. The importer records a concrete map; no
runtime search chain guesses among old locations.

### Executable migration protocol

1. Stop Igor sessions, quiesce owned stores and record source versions/roots.
   Do not stop unrelated application services merely to import Igor metadata.
2. Run a read-only inventory/dry run. Classify defaults, user intent, secret,
   native setting, durable record or disposable cache. Report missing/unsafe
   permissions, unsupported shell syntax, duplicate values and unresolved refs.
3. Resolve conflicts explicitly. No silent precedence choice; shell expressions
   require manual export to data. Back up source stores through their own
   consistent export/backup mechanism, including SQLite WAL considerations.
4. Stage private destination copies/imports with validated schema, identities,
   counts/digests and permissions. Secret digests/values do not enter public logs.
   Use owner-approved space and retain the original until verification succeeds.
5. Commit one cutover marker/root selection only after all required inventories
   validate. Atomic replace/fsync where supported; retain a private migration
   manifest recording completed phases and recoverable failures.
6. Restart Igor using only canonical sources. Inspect effective values/refs and
   records; run a non-destructive read plus the approved disposable application
   cycle. Re-entry detects completed work and does not duplicate identities.
7. Interruption before cutover leaves sources authoritative; interruption after
   cutover uses the new roots and resumes verification. Explicit recovery restores
   a consistent snapshot/root selection, never mixes stores from different phases.
8. Supply a one-shot importer/export/manual transition guide with the cutoff
   release. It is offline tooling, absent from normal startup/dispatch. Remove
   source material only by explicit user disposition after backup verification;
   no permanent runtime compatibility or automatic old-version retry.

## Tests to retire or rewrite

- v1 manifests, implicit activation, registration callback/hook ordering, dual
  views and `legacy.*` invocation: replace with strict rejection, explicit
  enablement and canonical behavior; preserve disabled-owner edge cases.
- legacy configuration precedence/sourcing and automatic data moves: replace
  with data-only import/conflict/idempotency/recovery/non-exposure coverage.
- menu-specific operation success strings: replace with actual exit/outcome,
  approval, History and verification through the shared executor.
- XML/internal environment transport and shell phase instrumentation: retire
  with their owner: execution/module transports in M1, AI conversation transports
  in M2. Preserve supported transaction/context/provider safety coverage.
- roadmap numbers and status phrases: replace with structural links/authority
  checks during governance cleanup; do not preserve obsolete roadmap headings to
  satisfy assertions.
- duplicate deprecated script tests and unused frontend tests: remove with
  confirmed unused implementations.

Retain independent protection for secret leakage, injection, symlinks, ownership,
privilege refusal, exact DESTROY approval, History before effect, uncertain
outcomes, restore/recovery, concurrency, freshness and real consumers. Old
operation records remain inspectable and may be non-replayable; historical
record format support is data integrity, not Igor 1 runtime compatibility.

## Documentation retirement

- Replace `docs/module_creation.md`'s v1 extension guide with the sole v2 author
  guide during M1. Until then its prominent legacy label prevents new v1 work.
- Update `module_lifecycle.md`, current CLI/install docs and root README to the
  actual sole runtime after cutover; remove v1 hook examples and old env setup.
- D021's compatibility obligation, D018's retained v1 parser and old Wave C
  instructions are superseded by D080. Historical assertions remain history.
- Delete the late Step 23 cleanup gate; cleanup belongs to each replacement.
- Keep current detailed contracts until their consumers migrate. Accepted
  D081 architecture is recorded in ARCHITECTURE; unaccepted storage proposals
  remain proposals. Do not change current runtime claims before migration.
- Historical status is archived; obsolete roadmap/review versions are in Git.
  Future agents read current STATUS, not every historical evidence paragraph.

## Prove no old interface is active

Use **all** of these; a grep alone is insufficient:

1. Tracked executable/config search for v1 parser entry points, `v1_hooks`,
   `__register`, `igor_register_hook`, old hook consumers, `run_igor_action`,
   legacy action IDs, old config source/fallback paths and startup migration.
   Review legitimate history/schema version strings rather than banning `v1`.
2. Trace public launch/CLI/TUI/AI/diagnose/recovery/automation call graphs to the
   same executor. Assert no old operation can execute via aliases/dynamic lookup.
3. Supply an old manifest/hook module fixture: fail before sourcing. Supply
   disabled/stale/missing/ambiguous providers: zero handler side effects and no
   active knowledge/check contribution. Remove and re-enable real packages.
4. Place sentinel legacy env/config files at old paths: ordinary startup neither
   reads/evaluates them nor moves them. Import is explicit and fails on unsafe
   syntax/conflict; secret sentinels do not enter output/logs/AI/child environment.
5. Exercise retained operations through real consumers and inspect canonical
   operation identity, approval, execution result and independent verification.
6. Verify data transition, interruption and recovery, retained record meaning,
   package read-only operation, and no implicit native application deletion.
7. Review final dependency graph, active docs and disposition/evidence ledger. Retired
   names may occur in historical documentation or rejection fixtures only, not
   callable production paths. Commit the coherent cutover; no compatibility flag.

This governance cleanup executes no runtime deletion or data migration. The
accepted handoff is concrete; current runtime defects remain until implemented.
