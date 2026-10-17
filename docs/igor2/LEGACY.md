# Igor 1 cutoff and simplification plan

Status: **complete Igor 1 cutoff accepted (D080); runtime migration not executed**.

Updated: 2026-10-17. Baseline `1aac86a`. This plan replaces the earlier legacy
inventory; original evidence remains in Git and [archived STATUS](archive/STATUS_2026-10-16.md).
[Development policy](DEVELOPMENT_POLICY.md) protects data, platforms and safety,
not obsolete Igor 1 interfaces. [M1](ROADMAP.md#m1--one-module-and-operation-platform)
is the finite cutoff milestone; later cleanup is not permission to keep v1 alive.

## Target and non-goals

Only strict Module API v2 is supported in the Igor 2 runtime. No v1 parser,
registration callback, compatibility hook, legacy action adapter, implicit
activation default or environment fallback remains reachable. Reject an old
package with a clear unsupported-interface error; do not translate it at runtime.
`master` remains an independent program and is not modified by this cutoff.

Preserve useful algorithms, capabilities, native applications and user data.
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
| Module-owned menu operations and direct shared menu writes | Replace presentation with canonical typed operations; retain useful leaf implementations | each UI/AI/automation request reaches same operation ID/History |
| Core Nextcloud diagnosis/recovery/helpers/provider imports | Move domain semantics to Nextcloud package; use shared owner-aware resolution | Core contract/dispatch works without Nextcloud installed |
| `config.sh`/`config_loader.sh` sourcing, root/HOME env fallback and startup moves | One scoped desired/secret/path authority; explicit offline import | startup ignores legacy files and writes no migration state |
| Module schemas/defaults versus machine config | Retain schemas/defaults in packages; persist local values outside | installed package can be read-only; disable has no active validation contribution |
| Canonical approval/privilege/verification, private History | Retain and extend to all operations | exact approval, refusal, pre-effect History, independent readback |
| Platform package/service adapters, useful Bash/Python handlers | Retain where correct; remove orchestration/implicit globals from handler contract | declared distro behavior and bounded I/O |
| Safe configuration/secret/deployment/investigation/learning stores | Retain identity/recovery semantics; migrate only affected fields/roots | export/import/interrupt/re-entry/ref-unavailable scenarios |
| Classic hybrid/line/operator duplication | Keep one primary curses UI and first-class CLI; port real interactions before retirement | usable operation parity, provider setup and native PTY flow |
| Textual `core/lib/igor_tui.py`, dormant path wrapper chain | Delete if final caller inventory confirms no supported consumer | no tracked/dynamic registration/export references |
| Deprecated test script copies and duplicate canary | Keep one called canonical copy; delete duplicates | callers updated; same canonical behavior |
| Old install/recovery scripts | Retain useful mechanics as owned handlers; M4 makes multi-step procedures durable | no separate authorization/History/execution controller |

The M1 coordinator may still be Bash. This does not justify v1 compatibility.
M2 consolidates coordination into Python and removes shell state transport;
neither milestone introduces a permanent compatibility bridge.

## Shipped-module disposition

| Module | Current state | Required rewrite/retention |
|---|---|---|
| `system` | v2 plus v1 hooks; host/storage/access/network declarations | Retain 40 capability implementations and useful observers/checks; migrate remaining hooks/knowledge/config consumers and remove compat flag |
| `docker` | v2, four capabilities, optional System dependencies | Retain; adapt to sole executor/config API, verify explicit targets and disable isolation |
| `nextcloud_docker` | v1 with extensive menus/hooks, 12 AI actions, recognition/attachment code | Rewrite interface and control flow to v2, not all application algorithms; explicit deployment binding/config/secret refs, native readback, canonical operations |
| `samba` | recognition Python adapter only, no module manifest | Keep as bounded recognition fixture/reference consumer if used; do not advertise a complete package or create a new product milestone |

Do not split Nextcloud's PostgreSQL, Redis, web proxy and tunnel into independent
module products merely to satisfy a diagram. Domain decomposition needs actual
reuse and independent lifecycle value. Docker already supplies generic substrate.

### Operation parity inventory seed

The implementation agent completes this finite inventory from current registrations
and menu entry points before deleting code; this is accounting, not another design wave.

| Existing behavior | Target |
|---|---|
| System host/package/service/log/storage/access/network operations | Preserve canonical IDs/semantics unless explicitly migrated; retain exact privilege adapters |
| Docker lifecycle/read operations | Existing v2 capabilities with explicit endpoint/target binding |
| Nextcloud health/full diagnostic/status/permission inspection | Owned observers/checks/READ capabilities, application-specific interpretation stays in module |
| scan files, flush Redis/caches, repair/full repair, permission fix, DB maintenance, config injection | Typed canonical capabilities with bounded targets, concrete effect and honest verifier/recovery limits |
| Service start/stop/restart/logs | Explicit bound Compose project; propagate exit status, independent state readback |
| App enable/disable/update and maintenance/upgrade menus | Inventory each reachable leaf; preserve as reviewed capabilities and structured inputs |
| Configure/wizard/install/backup/restore/recovery | Preserve valuable implementations under canonical authority; M4 adds durable multi-step coordination rather than reintroducing raw menus |
| Native Nextcloud loglevel setting | Desired proposal/commit, canonical apply, OCC readback and explicit recovery |
| Notify/status/AI knowledge hooks | Typed domain signals or read projections and module reference knowledge; no authority from prose |
| Mail-control hooks with absent Core consumer | Remove unused registration; communications is a later product decision |
| Global Docker NUKE | Remove unsafe host-wide operation; no automatic generic replacement |

Every former callable operation must have a target or an explicitly documented
retirement reason. If valuable behavior cannot fit M1 safely, surface the scope
conflict to the Owner; do not hide it as cleanup or leave an indefinite adapter.

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
once on M1 architecture confirmation. The importer records a concrete map; no
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
  only in M2 with transaction/context/provider parity coverage.
- roadmap numbers and status phrases: replace with structural links/authority
  checks in M1; do not preserve obsolete roadmap headings to satisfy assertions.
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
- Keep current detailed contracts until their consumers migrate. Consolidate
  accepted reset architecture into ARCHITECTURE after confirmation; do not make
  proposals normative by editing status labels.
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
7. Review final dependency graph, active docs and parity/evidence ledger. Retired
   names may occur in historical documentation or rejection fixtures only, not
   callable production paths. Commit the coherent cutover; no compatibility flag.

This audit executes none of the deletion/migration steps. Findings and proposals
are concrete handoff material; current runtime defects remain until implemented.
