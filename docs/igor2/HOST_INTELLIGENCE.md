# Wave D host-intelligence contract — design gate

Status: **accepted design; not implemented**. Steps 7–10 use the Wave C
Module API v2 loader, contribution index and Bash handler envelope. The
implementation must satisfy the five proof classes in [EXECUTION.md](EXECUTION.md)
before Wave D is marked complete. This document specifies the smallest first
authority path, not a general inventory database or monitoring service.

```text
deterministic platform/module discovery
  -> active observer -> validated typed result -> Igor System Model
  -> one fact snapshot -> check -> structured health result
  -> Diagnose / Healing / AI reference context / inspection
```

## Repository boundary and Step 7 assessment

The clean `igor2` baseline at `a8dda91` contains Wave C. `core/lib/distro.sh`
detects `/etc/os-release` ID/family; `core/lib/pkg.sh` maps a small set of
logical package names, maps `svc_cron`, and installs via apt/pacman (plus
other family branches). `igor.sh` resolves Arch versus Debian Python. Current
tests prove Debian/Arch detection, names and **install command selection**;
they do not prove query/remove/update, systemd operations, actual installation,
or derivative support. `pkg.sh` currently defaults an unset/unknown family to
Debian in its name resolvers and `pkg_install` invokes `sudo` itself. Do not
interpret either behavior as a new authorization contract.

Host operations exist as scattered direct calls: `system` reads `/proc`,
`/sys`, `free` and `df`; Diagnose uses `ps`, `ip`, `stat`, `df`, `systemctl`
and optional privileged SMART/tune2fs probes; `core/lib/helpers.sh` has
generic `own_dir` beside Nextcloud-specific ownership helpers; AI context,
scrubbing and UI repeat a LAN-IP fallback. There is no shared service/process/
filesystem/network operation set to replace. Preserve working callers until a
tested consumer is cut over. A platform helper returns mechanism/data or a
validated argv specification; `system` supplies observation meaning and
thresholds. Platform code must not infer health, install Docker, manage
Nextcloud, or decide that a detected service should be restarted.

| Wave D platform work | First implementation boundary |
|---|---|
| Keep | Extend `distro.sh`, `pkg.sh`, Python resolution, `IGOR_DIR` paths and current loader platform gates. Keep present package-install callers working. |
| Needed for the memory slice | No new OS wrapper: `system__observe_memory` already reads `MemAvailable`. Add strict typed validation and freshness above its handler. |
| Add in Step 7 | A new normalized resolver fails closed for unsupported/unset families; package-installed query and deterministic Debian/Arch package install/remove/update argv resolution; systemd unit state query and deterministic start/stop/restart/enable/disable argv resolution; minimal host identity, mount/filesystem usage, process and interface queries **only where a Wave D observer/check actually consumes them**. Reuse one LAN-IP mechanism for UI/context later without making scrubber depend on model freshness. |
| Execution boundary | Read queries may execute directly with bounded timeouts. Mutating argv is data until an already-authorized caller executes the exact operation. Preserve the existing `pkg_install` compatibility entry point, including its other-family branches, until tested callers migrate; its direct-sudo behavior and Debian fallback are not templates for new APIs. Step 11 connects general package/service mutations to the shared approval/privilege/capability gate. Observers and checks cannot invoke a new sudo path. |
| Later | Broad process control, user/group mutation, network configuration, filesystem mutation, distro-specific policy solving, service managers other than systemd, and actual end-to-end package installation support claims. Add only for a real capability/observer. |

Before claiming Debian/Arch support for each new operation, fixture-test
distribution identification, exact mapped and bare package names, installed/
missing/error package queries (`dpkg-query`/`pacman -Q`), apt/pacman argv for
install/remove/update, exact systemd unit states and mutation argv, root/nonroot
handling at the existing privilege gate, timeout/error behavior and unknown
family/absent-systemd failure. Test the supported exact IDs separately from
`ID_LIKE` derivatives. The current tests only establish the subset stated
above. A generic filesystem or network query needs the same fixture and error
proof on both families when it becomes a promised operation. Package and unit
inputs must be validated as names and passed as argv, never interpolated into
shell text.

`pkg_install_docker_post` in `pkg.sh` enables/starts Docker, polls `docker info`
and edits Docker group membership. Its callers are Nextcloud install/start
paths. This is Docker provisioning, not package abstraction. Keep those v1
calls while the combined `nextcloud_docker` module owns the workflow; move the
routine behind that domain's capability when Step 11/18 supplies a tested
replacement. Do not make `system` responsible for Docker by moving the file.

## Step 8 — System Model v1

Core owns a query/update service, not a public storage path. Modules return
data through contributions; only Igor validates and commits authoritative
records. A **fact** is one typed value for one `(object_id, property,
state_class)` slot. The tuple is its canonical key. Keep separate slots for
`observed`, `configured`, `user_declared`, `desired` and `inferred`; never
upsert a desired slot from an observation. `known`/`unknown`/`stale` describe
availability of a slot, not its state class. `not_observed` means no attempt
or source has ever supplied that slot. `unknown` means an attempted source
could not establish a value and no last known value exists. A previously known
value whose TTL expired or whose refresh failed is `stale`, with its last
value and original provenance still visible. No consumer may present stale
data as a fresh observation.

Minimum fact record (illustrative JSON, with runtime-assigned timestamps):

```json
{
  "object_id": "host:local",
  "property": "memory.available_bytes",
  "state_class": "observed",
  "value": 123456789,
  "value_type": "integer",
  "owner": "system",
  "provenance": {
    "kind": "observer",
    "id": "host.memory",
    "evidence": ["/proc/meminfo:MemAvailable"]
  },
  "recorded_at": "2026-09-27T10:00:00Z",
  "expires_at": "2026-09-27T10:01:00Z"
}
```

`object_id` identifies a thing; `property` gives the typed question and unit
(for example `_bytes`, avoiding an extra mutable unit field); `state_class`
prevents intent/reality overwrite; `value_type` prevents string/number
ambiguity; `owner` is the active module or core domain; provenance answers why;
timestamps permit freshness. `expires_at` is derived from validated observer
TTL, not handler wall time. Evidence is bounded and redacted; it is a locator
or short non-secret excerpt, never a credential or executable instruction.
Optional evidence references may point to an existing report without importing
that report as state. Do not assign a numeric confidence to directly measured
facts; initial inferred facts must carry a named inference rule and input fact
references, and their availability cannot exceed their inputs' freshness.
No free-form AI confidence is a source of authority.
Facts have no general lifecycle field in v1: source revocation withdraws
source-backed slots, and observation TTL/failure changes availability without
erasing last evidence. Step 15 may retain historical versions separately.

Use stable, locally scoped object IDs with an explicit kind: `host:local`,
`mount:/`, `service:systemd:docker.service`, `package:docker.io`,
`interface:eth0`, `module:system`, and (later) a domain instance such as
`domain:nextcloud_docker:default`. Processes need boot/start identity as well
as PID to avoid reuse. These are object identities, not Step 17 relationships;
renames/moves can produce new IDs. Encode unsafe identifier characters
canonically at the boundary; do not use IDs directly as paths. Only active
owners can publish facts in their declared object kinds/properties.

Provenance kinds are `observer` (direct measurement), `configuration`
(effective validated setting and its owner/source), `user_declaration`,
`installer` (a verified operation record), and `inference` (named rule plus
input facts). An AI proposal stays a proposal/reference item until a trusted
user/configuration or verified capability records it; it is never an
`observed` fact. Configuration and user-declared state do not become
`desired` automatically. Desired state requires explicit intent, with its own
provenance. The same property can therefore simultaneously be observed false
and desired true.

A **responsibility** is a separate Igor-owned intent record, not another
observed/desired value: `(object_id, optional property, mode=watch|maintain,
owner, provenance, recorded_at, lifecycle=active|revoked)`. `watch` permits
evaluation/reporting; `maintain` records an assigned outcome but grants no
automation, approval or privilege. It is created/revoked only through an
authoritative user/configuration or verified installer path. Enabling a module
or detecting a service does not silently create responsibility. Wave D may
return an empty responsibility set. Step 14/19 defines its future action policy.

**Persistence boundary.** Initial observed facts, refresh failures and health
results are rebuildable and may live in a process-local/runtime snapshot. On
restart they begin `not_observed` until refreshed; an old Healing text cache
is presentation compatibility, not a System Model source. Configured,
user-declared, desired and responsibility records must survive restart **when
their authoritative source exists**: project them from the currently effective
validated configuration/user policy or verified installer record through a
source adapter, and rehydrate on startup. Wave D adds no generic user-intent
editor or free-standing persistent fact file. If a source cannot be named,
the slot remains absent. The service exposes `read`, `list`, `upsert_from_source`,
`revoke_source` and `refresh` semantics independent of the backing store;
source adapters own writes to their existing authority. This avoids freezing
the present mixed config/secret/state paths into Module API v2. Later Ownership
Foundation work defines canonical locations and migrations. Q003 remains open
until Step 15: choose persistent observed snapshots/history only if startup
probe cost, offline inspection, retained evidence or multi-process consistency
requires it, with measured requirements and migration/recovery proof.

`upsert_from_source(source_id, snapshot)` atomically replaces only records
previously supplied by that named source; `revoke_source(source_id)` withdraws
only those records. Both validate the source's owner and allowed state classes.
Initial real adapters may project `modules.conf` activation as a **configured**
record; this does not mean Igor has been asked to maintain the host or that a
service should run. `system.env` RAM threshold names are not currently used
by the RAM check code, so they must not be presented as effective settings.
Current shipped configuration has no general desired-state or responsibility
declaration, so those lists are genuinely empty on an ordinary Wave D
installation. A test
source adapter must prove desired/observed coexistence and intent rehydration;
adding a user-facing intent writer waits for the Ownership Foundation. Never
infer desire from observed state merely to populate the model.

## Step 9 — Observation Framework v1

Wave C's `igor_v2_invoke observer host.memory '{}'` and `{"status":"ok",
"result":{"available_bytes":...}}` demonstrate invocation, not System Model
ingestion. Keep that adapter. Step 9 extends the v2 observer descriptor with
an object kind, a small declared property/type set and `freshness_seconds`;
existing `output_type` remains the schema identity and `timeout_seconds`
remains the execution bound. For the first slice, `host.memory` declares one
`host` property, `memory.available_bytes` as a nonnegative integer with a
short positive TTL. The validator rejects unknown fields/types, duplicate
properties and invalid TTL before activation. Do not introduce an arbitrary
telemetry schema language.

Illustrative extension of the current `host.memory` descriptor (the current
Wave C file does **not** yet contain the new fields):

```json
{
  "kind": "observer",
  "id": "host.memory",
  "handler": "system__observe_memory",
  "output_type": "host.memory",
  "object_kind": "host",
  "properties": [{"name": "memory.available_bytes", "value_type": "integer", "minimum": 0}],
  "freshness_seconds": 60,
  "timeout_seconds": 10,
  "privilege": "none"
}
```

The handler still returns the Wave C outer `status=ok|error` envelope. Its
Step 9 `result` contains `object_id`, `facts` (property/value pairs), and
optionally `unavailable` (declared properties with a bounded reason). A
complete successful result accounts for every declared property; a partial
result marks missing properties explicitly in `unavailable`. The runtime,
not the handler, supplies owner, observer ID, recorded time and expiry. The
handler may supply bounded evidence references, but cannot choose state
class, provenance kind, authority, privilege or target outside its declared
object kind. Keep `host.memory`'s current result readable only by the Wave C
direct-invoke compatibility path until its handler and consumers are cut over
together; the Observation Framework accepts the new result shape only.

```json
{
  "status": "ok",
  "result": {
    "object_id": "host:local",
    "facts": [{
      "property": "memory.available_bytes",
      "value": 123456789,
      "evidence": ["/proc/meminfo:MemAvailable"]
    }],
    "unavailable": []
  }
}
```

For this fixed-target observer, `object_id` must be `host:local`. A later
dynamic observer may accept a validated target in the handler request and
return that same target; it cannot create a new object kind by returning a
different ID. `facts` and `unavailable` must form a disjoint complete set of
declared properties for each attempt. An explicitly partial attempt has a
nonempty `unavailable` list. An outer `status=error` has no `result` and is a
failed attempt for all declared properties. The runtime owns the attempt
record even if no fact was committed.

| Responsibility | Owner |
|---|---|
| Descriptor, handler, domain evidence and property meaning | Active module (`system` for host memory) |
| Activation/requirements, invocation, timeout and validation | Existing loader/adapter plus Igor Observation Framework |
| Refresh policy, runtime timestamp, TTL calculation, partial/failure state and authoritative commit | Igor Observation Framework/System Model |
| OS authentication and exact approved execution | Existing deterministic authority/privilege boundary; no observer-owned sudo |

Initial invocation is explicit `refresh(observer_id, target)` and bounded
consumer `ensure_fresh` when a required fact is absent/stale. A Diagnose or
Healing pass shares one refresh/snapshot for all consumers of the same fact;
inspection queries never refresh implicitly. The existing Healing interval
may request refresh through this path, but Step 9 adds no background scheduler,
retry policy or domain event bus. `timeout_seconds` is required or uses the
existing bounded adapter default; TTL is required for an observed fact.
Cost class is deferred until a real competing observer or refresh budget needs
it. A `privilege=none|required` declaration is reserved in the descriptor;
the first `host.memory` observer is unprivileged. A required-privilege observer
is unavailable unless the existing exact-operation privilege gate can mediate
it; Igor never silently runs the module handler under sudo. Step 11 generalizes
that gate for capability-backed privileged observers if needed.

Validate the **entire** response before committing any fact: shape, JSON
types/ranges, declared property/target, bounded evidence, active owner and
current requirements. A malformed response commits nothing and records a
named observer failure. A timeout/nonzero/error response also commits nothing.
If no previous value exists, affected slots are `unknown` with failure reason;
if one exists, it becomes `stale` immediately with its last value/provenance.
A valid partial response atomically commits its present facts and applies the
same unknown/stale rule to explicitly unavailable properties. A clean complete
refresh replaces the prior failure for its covered slots. No failure silently
deletes a previous value. A module deactivation removes its facts from active
queries immediately; any retained last value is inspectable only as inactive
historical evidence, never current machine truth.

## Step 10 — Unified Health v1

One check registry/runner uses active v2 `check` declarations and adapts active
v1 checks during migration. A check receives a bounded System Model snapshot;
it evaluates facts and returns one or more **results**, never execution
instructions. Required slots that are unknown/stale produce `UNKNOWN`, not a
healthy result. `SKIP` is for a declared check that does not apply. A result
has `check_id`, `owner`, `object_id`, `status` (`OK`, `WARN`, `FAIL`,
`CRITICAL`, `UNKNOWN`, `SKIP`), `finding_code`, bounded `message`,
`used_facts` (canonical keys plus recorded times), `evidence` (bounded
non-secret references), and runtime `evaluated_at`. The runner stamps identity
and time; a handler cannot overwrite them. A remediation **capability ID** may
be an advisory reference after Step 11 makes that ID executable. Check text,
evidence and `PATTERN_HINT` comments never grant authority or execute a fix.

The `system` memory check should take `used_facts` with value and availability
in its input, use a declared `host:local` target and return only its finding
fields through the same Wave C handler envelope. The runner supplies the
check ID/owner/time and stores an immutable result snapshot for that pass.
Checks cannot write facts, desired state or responsibilities. A valid result
with missing required fact references is rejected; Igor emits a named
`UNKNOWN` evaluation result for timeout/malformed output instead of treating
the check as passed.

Step 10 extends the existing v2 `check` descriptor/dispatcher, which Wave C
currently indexes but does not invoke. The first check declares an
`object_kind=host` and one `required_facts` entry for observed
`memory.available_bytes`; Igor resolves that entry from a single snapshot,
refreshes it at most once for the pass, and passes the exact value,
availability and canonical key/time in the handler request. The handler's
`result` contains `status`, `finding_code`, `message`, `used_facts` and optional
bounded evidence. The runner rejects a `used_facts` reference absent from the
supplied snapshot and adds authoritative `check_id`, `owner`, `object_id` and
`evaluated_at`. This keeps the check contract declarative without a general
query language or permission-bearing result fields.

The current `CHECK_RESULT SEVERITY code message` contract feeds Healing;
`CHECK:name:status:message` feeds Diagnose hooks. `diagnose_runner.sh` also
discovers check files and maps `CRITICAL` to `fail`; `diagnose/phases.sh`
reuses Healing files; `healing/core.sh` separately discovers/runs and caches
them. First introduce one active-owner check discovery/execution adapter and
normalize both legacy line formats into structured results, preserving the
distinct Diagnose phases, gates, reports and interactive fix loop and the
Healing score/cache/alerts and current Nextcloud v1 behavior. A legacy check
with no structured fact inputs is marked `legacy_direct` in provenance; do
not pretend its text line is a typed observation. Give each execution a
canonical owner/check ID and snapshot key. Within one evaluation pass run
that check once, fan out its result to both projections, and reject duplicate
canonical registrations. Different user-initiated passes may refresh again.

For the real `system` memory slice, introduce a v2 check over
`host:local/memory.available_bytes` using `system` thresholds. Keep the
currently executed boundaries of 80 MB critical and 150 MB warning as the
Wave D defaults; expose those effective values in check inspection. Do not
reinterpret `SYSTEM_RAM_WARN_MB=80` as the 150 MB boundary during this
cutover: that currently documented setting is not read by the RAM code.
Configuration ownership can reconcile it later with an explicit migration.
These boundaries are MiB values (`available_bytes < 80 * 1024 * 1024` and
`< 150 * 1024 * 1024`), matching the current integer-MB comparisons. The
active v1 `system__diagnose` RAM line and `checks/hardware.sh` RAM line must
be suppressed for consumers served by the new canonical check; keep the other legacy
hardware findings. The cutover tests 80/150 MB and avoids a parallel RAM
threshold authority.
The two `system` storage/hardware root-filesystem findings likewise need one
future canonical ID before their shared fact migrates. Nextcloud's v1 files
and hook remain active-owner filtered until a real v2 domain check replaces
them. When all consumers of a check use the shared result, retire its old
discovery/execution path; do not retain two authorities.

Healing may project structured severities into its current 0–100 score and
text cache, and Diagnose may project them into its current phase UI. Those
are presentation/compatibility outputs, not the authoritative health result.
Unknown/stale input is surfaced visibly and does not count as OK or authorize
repair. Current score formulas and alert behavior remain until separately
tested changes are necessary; avoid counting the same canonical result twice.
If no valid check can evaluate, the structured health summary is `UNKNOWN`;
any legacy numeric score must carry that availability label and cannot be
reported as a healthy system solely because an empty cache yields 100.

## Direct context probe cutover

| Current source | Classification and cutover |
|---|---|
| `ai/context.sh` RAM and `system__ai_context` RAM | **REPLACE once authoritative** `host.memory` fact is fresh; use one selected structured fact in the existing `IGOR_REFERENCE_V1` envelope. Keep direct v1 text only during transition, never combine as two asserted values. |
| `system` temperature/load/swap, core disk `df`, Diagnose host CPU/storage probes | **ADAPT to observers/checks** domain by domain after the memory slice. `system` owns health meaning; core may provide generic read primitives. |
| Hostname, OS/family, kernel/arch and LAN IP in context | **ADAPT** to core platform identity/network queries and selected System Model facts where useful. Keep privacy scrub's independent current-value probes; redaction must not depend on a stale fact. |
| Port bindings and external ping/DNS in context | **KEEP temporarily**; later add bounded network observers only if consumers need reusable facts. External reachability is context dependent and must not be mislabeled host truth. |
| Project-file listing/presence and legacy root env checks | **KEEP temporarily**, then **REMOVE** when Ownership Foundation configuration inspection replaces them. They are not host observations. |
| Healing text-cache score, hook/capability inventory, patterns, reports | **ADAPT** health results to the shared check projection; **KEEP** owner-aware catalog/reference material until their own roadmap steps. Neither is an observed fact. |

AI receives only selected, redacted, freshness-labelled facts/results through
the existing reference-data envelope. After memory cutover a stale memory
fact is labelled stale or refreshed through the bounded observer path, never
silently replaced with the old independent RAM probe. AI never refreshes by
inventing a host command when an authoritative fact exists, and fact/check
text cannot alter
approval, sudo or active ownership.

## Inspection and proof required to close Wave D

Provide a backend read-only JSON query (CLI may wrap it) with `facts` filtered
by object/property/state class, `responsibilities` by object, `observers`
with availability/last attempt/failure, and `health` by check/object. A single
fact query shows value/type, owner, provenance/evidence, observer, recorded and
expiry times, computed availability and reason. The same query shows observed
and desired slots side by side. `health` exposes used fact keys/times, status,
finding and evidence. Reuse `--modules` for contribution availability; a small
`--model`/`--health` command or equivalent backend API is sufficient. Queries
do not silently run probes. Unknown, stale and inactive are explicit, and
secret values remain absent.

| Proof class | Falsifiable Wave D implementation checks |
|---|---|
| Contract | Observed=false and desired=true coexist at one object/property; each retains source. TTL expiry, first failure and failure after success yield distinct not-observed/unknown/stale views. Wrong type, undeclared property/target, malformed JSON and inactive owner commit zero facts. Partial output changes only declared slots. A check consumes a fact snapshot, preserves `CRITICAL` and emits `UNKNOWN` on missing/stale input. A result/message containing “restart service” cannot invoke, approve or elevate anything. |
| Regression | Existing Wave C v1/v2 loader and `nextcloud_docker` behavior, activation filtering, module checks, Diagnose phases/fix loop, Healing score/alerts, Guide/Assist/Executive approvals, declined sudo and AI reference boundary remain green. Debian/Arch fixture coverage expands only for newly promised platform operations. |
| Real slice | Active `system` `host.memory` -> v2 handler -> validated nonnegative byte fact -> System Model -> one structured memory check -> inspection and selected AI/Diagnose/Healing projection. Disabled `system` contributes none. Threshold and duplicate RAM-check cutover are tested. |
| Inspection | A query answers memory value/type, source, owner, observer, recorded time, freshness, desired/responsibility (including absence), and why a health check fails or is unknown, without reading module files. |
| Migration/recovery | Existing direct probes/checks remain until their fact/check is authoritative. On cutover, suppress the equivalent legacy emission for that consumer and test one execution/result per pass. Rehydrate source-backed intent after restart; observed values return to not-observed and refresh deterministically. No new persistent layout or database is introduced in Wave D. |

The first implementation order is: (1) Step 7 read-side platform audit fixes
and exact Debian/Arch/unknown fixtures; (2) System Model key/state/query
contract plus source-backed intent adapter and inspection; (3) extend the
existing v2 observer descriptor/result validation and refresh path; (4) move
`host.memory` to that path and prove failure/freshness/activation; (5) build
one check registry/result runner with v1 line adapters; (6) cut over the
`system` memory check once, project to existing workflows and selected AI
reference context; (7) regression, inspection and restart/recovery proof,
then retire only superseded memory-specific probes. Mutation argv resolution
may be finished in Step 7 without making a new execution path. Step 11 owns
general mutation authorization.

## Influence and ownership check

This path implements [INFLUENCES.md](INFLUENCES.md) without importing either
external architecture. ServerMind's deterministic discovery becomes active
module observers, reusable typed inventory, provenance/freshness and checks
that discover problems before AI interpretation. Shared snapshots avoid
model-driven rediscovery. Steward's durable machine understanding becomes
separate Igor-owned state/intent/responsibility records that survive provider
changes; source-backed intent survives restart, while rebuildable observations
are refreshed. The object IDs and evidence references leave room for later
investigations, plans and history without implementing them now. Igor remains
local Linux-first, detachable-module and capability/approval governed; it
does not copy a distributed database, generic CMDB or autonomous command
agent. Ownership Foundation will later settle canonical persistent paths and
Q003 will settle durable observed-history needs. Neither blocks this first
authoritative host-memory path.
