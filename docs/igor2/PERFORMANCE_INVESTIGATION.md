# Igor 2 Performance Investigation

Status: **closed after Boundary P**. This document records the performance
investigation that ran across capability execution, result publication and
standalone-TUI startup. Boundary P was the final optimization in this pass and
its real-host closure measurement is recorded in [STATUS.md](STATUS.md).

The purpose of this work was not to make Igor "fast at any cost". The objective
was to remove avoidable work from hot paths while preserving the architecture
that gives Igor its safety and explainability: canonical capability authority,
approval, privilege mediation, fresh preconditions, verification, Operational
History, module ownership, Configuration Service ownership and structured
frontend/backend boundaries.

## What we were trying to solve

Two user-visible paths were too slow:

1. **A normal capability execution** spent seconds in Igor around operations
   whose native Linux command took only tens of milliseconds.
2. **Opening the standalone TUI** took about 28 seconds before the composer
   became usable.

The initial temptation would have been broad caching or bypasses. Instead the
investigation used one rule throughout:

> Measure one boundary, identify the dominant synchronous work, remove only
> work that is redundant for that boundary, and preserve the stronger authority
> path for the operation that actually needs it.

This repeatedly exposed the same families of problem:

- full-registry work for a selected capability;
- repeated Python interpreter startup for tiny serialization/extraction jobs;
- repeated validation of structural data that had already been validated;
- presentation work performed before the user could interact;
- global authority/proof work used by consumers that required only a narrow
  authoritative value;
- derived caches that rebuilt most of their source merely to discover that the
  cache was valid;
- synchronous bookkeeping delaying presentation after canonical work was done.

## Method

Each boundary followed the same pattern:

1. instrument the real hot path;
2. reproduce on the same physical Igor host;
3. rank phases by wall-clock cost;
4. inspect the exact code responsible for the largest phase;
5. separate structural metadata, current runtime truth, presentation and
   authority;
6. optimize the narrowest safe seam;
7. add regression tests for the authority boundary, not only the fast path;
8. rerun the same host measurement before claiming success.

Caches introduced by this work are disposable derived metadata. They do not
grant execution authority. Runtime requirements, approval, privilege,
preconditions, verification and History remain fresh where their contracts
require it.

## What we found and changed

### Capability/action path — Boundaries A–E

**Boundary A — Capability Runtime.** A real `system.service.list` trace showed
that the native `systemctl list-units` operation was about 41 ms while Igor's
execution-fence preparation consumed about 10.6 s. The capability registry was
evaluating and reparsing much more than the selected capability needed.
Requirements and static metadata were compiled at module load, preparation was
bounded to the selected dependency closure, and proposal fields were batched.
The measured execution-fence interval fell to about 2.1 s.

**Boundary B — Operational History.** Durable authority transitions were doing
multiple process/serialization passes and broader recovery scans than the hot
path needed. History transitions were consolidated while retaining durable
authority before provider effect, direct-call authority, terminal failure
semantics and recovery.

**Boundary C — Provider Runtime.** The Module API v2 bridge repeated syntax,
request construction, handler metadata and output validation work at every
invocation. Validated handler metadata was compiled at load time, the isolated
provider process remained intact, and envelope/output validation was fused.

**Boundary D — Execution Fence.** Fresh reprepare remained correct but still
paid repeated process/serialization costs. The same authoritative prepare path
was exposed through a cheaper bridge and fields were batched. On the real host,
`authority -> running` fell from about 2.070 s to 1.152 s, and the action was
about 3.45 s overall.

**Boundary E — Result Publication.** After canonical terminal History state, the
visible TUI result was delayed by synchronous non-authoritative work. Automation
received a cheap prefilter, frontend sequence tracking gained a safe advisory
cache, and local result presentation moved ahead of non-authoritative
bookkeeping. Terminal-to-visible fell from about 1.143 s to 0.471 s; the same
action measured about 3.36 s.

The important result of A–E is not that every capability is now maximally fast.
It is that selected execution no longer pays obvious whole-system or repeated
interpreter costs while the safety lifecycle remains intact.

### TUI startup path — Boundaries F–P

**Boundary F — Operator Surface.** Navigation metadata was separated from
execution authority and persisted as a structural projection. This established
the correct architecture, although the original warm validation still did too
much work.

**Boundary G — Readiness.** Provider network/auth validation and full server
context gathering were moved from startup to the first provider-bound request
for the standalone TUI. Local commands/navigation became available before that
work. The TUI also stopped probing classic tmux/fzf/rich presentation features
it does not use.

The first complete real-host trace after G was:

```text
tui.bootstrap_modules       22624 ms
operator_surface              399 ms
tui.startup_to_input_ready  28445 ms
```

That made module bootstrap the next target rather than inviting speculation.

**Boundary H — Module Loader Fast Path.** Module API v2 package validation and
registration repeatedly started Python to read fields from the same validated
package. A single structural registry compiler now validates installed v2
packages and persists an owner-private derived registry. The shell populates the
same canonical runtime registries from those compiled frames; current
enablement, binaries, platform and dynamic requirements remain fresh.

Real-host result:

```text
module bootstrap:          22624 ms -> 808 ms
startup_to_input_ready:    28445 ms -> 4849 ms
```

This was the largest single gain in the investigation.

**Boundary I — Startup attribution.** The remaining TUI path was partitioned
into top-level phases so later work could be evidence-driven. The trace showed
`ai_local_setup` at about 1.9 s.

**Boundary J — TUI Local Setup Fast Path.** Classic banner/right-pane/prompt work
that the standalone curses TUI immediately discarded was removed from the
pre-READY path. Deferred prompt construction was preserved until authoritative
context existed.

Real-host result:

```text
ai_local_setup:            1932 ms -> 97 ms
startup_to_input_ready:    5063 ms -> 3595 ms
```

**Boundary K — AI Pre-Session.** The classic system/header block was also
presentation-only for the standalone TUI. Skipping it reduced pre-session
startup and, more importantly, partitioned the remaining cost. The resulting
trace showed Configuration Service resolution at 460 ms out of a 496 ms
pre-session phase.

**Boundary L — Configuration Read Fast Path.** Reading Core-owned
`ai.verbose` used full Configuration Service inspection even though startup
needed only value + revision. A narrow authoritative read was added. It reads
the same private SQLite desired store on every startup but deliberately returns
no global state token and cannot authorize writes.

Real-host result:

```text
tui.ai_pre_configuration:  460 ms -> 304 ms
tui.ai_pre_session:        496 ms -> 344 ms
```

**Boundary M — Operator Surface Warm Fast Path.** Boundary F's cache still
rebuilt the complete structural seed before determining that the cache was
current. The loader now supplies a structural generation key and a true warm
hit reads the persisted projection without rebuilding the JSON seed. The cache
remains presentation metadata only.

Warm real-host result:

```text
operator_surface:          384 ms -> 285 ms
operator_snapshot:         392 ms -> 295 ms
```

**Boundary N — Module Registration Attribution.** Once the large startup costs
were gone, module registration became worth inspecting. The trace showed:

```text
System configuration consumer   452 ms
Nextcloud legacy v1              96 ms
Docker v2                         28 ms
reconciliation                     2 ms
derived registration             626 ms
```

This prevented the wrong optimization. The legacy Nextcloud path was not the
dominant problem; a single System configuration consumer was.

**Boundary O — System Configuration Consumer Fast Path.** System memory-health
startup used full global Configuration Service inspection to obtain one warning
threshold. The ordinary health consumer needs the authoritative value and
revision, not a global state token. Startup now performs a narrow read using
System's already-validated registered schema. Explicit apply/readback still
acquires the full state token and preserves CAS/verification semantics.

Real-host result:

```text
module bootstrap:          885 ms -> 686 ms
derived registration:      626 ms -> 419 ms
startup_to_input_ready:   2808 ms -> 2653 ms
```

**Boundary P — Configuration Startup Snapshot.** L and O left two independent
narrow authoritative reads during one standalone-TUI process: Core
`ai.verbose` and System's memory warning threshold. P coalesces those initial
consumers into one process-scoped Configuration Service snapshot when System is
active. The snapshot reads the same SQLite authority once, uses System's
validated loader-owned schema, returns only both values + the current revision,
and contains no state token. AI consumes that bootstrap snapshot exactly once.
Classic/late AI entry and later reloads keep the existing fresh resolver.
Mutation/readback authority is unchanged.

The second unchanged real-host P launch confirmed the intended behavior:
`configuration.core_resolve=0ms`, `configuration.decode=0ms`,
`tui.ai_pre_configuration=6ms`, `tui.ai_pre_session=46ms` and
`tui.startup_to_input_ready=2302ms`. The operator surface remained warm with
no rebuild. The new `configuration.startup_snapshot` timer did not surface on
the physical host, so that missing diagnostic remains observability debt rather
than a performance blocker.

## Result so far

The clearest startup comparison is:

```text
Initial measured READY:    28.445 s
After Boundary H:           4.849 s
After Boundary J:           3.595 s
Boundary N warm:            2.808 s
Boundary O warm:            2.653 s
Boundary P warm:            2.302 s
```

Boundary P is about **12.4x faster** than the 28.445 s baseline, a reduction of
roughly **91.9%**.

This investigation is now closed. The remaining phases are measured in hundreds
of milliseconds rather than tens of seconds, and further startup work has lower
expected return and higher risk of invalidation/authority complexity. Treat
performance as monitored technical quality, not the active Igor 2 workstream,
until new measurements justify reopening it.

## What remains worth improving later

These are not current blockers. Reopen them only with a measured user-visible
reason.

1. **READY finalization (~0.5 s).** It is now one of the largest remaining
   top-level phases. Attribute it before changing anything.
2. **Module registry warm fingerprinting (~0.18 s in recent runs).** Boundary H
   still fingerprints package contents to validate the structural registry.
   A future package-generation mechanism may reduce this, but only if it retains
   trustworthy invalidation.
3. **Operator-surface warm path (~0.28 s).** Generation + cache read +
   publication remain measurable. Do not weaken structural invalidation or
   capability authority for tens of milliseconds.
4. **Legacy Nextcloud v1 loading (~0.1 s).** Migrate for Module API v2
   architecture/portability when that work is otherwise justified; performance
   alone does not justify a special rewrite.
5. **Classic/late AI configuration reads.** Boundary P intentionally applies to
   standalone-TUI bootstrap only. Classic or late entry must read fresh because
   configuration may have changed since process startup.
6. **First provider request.** Boundary G moved network/auth/context work after
   READY. If first-message latency becomes a UX problem, measure that separate
   path rather than moving it back into startup.
7. **Capability action latency.** A–E removed major generic overhead, but a
   future action-focused pass can repeat the same boundary method on slow real
   operations.
8. **Timing observability.** Some N/O per-module diagnostic observations were
   incomplete on the physical host even though the enclosing aggregate was
   coherent. This should be repaired if module registration is investigated
   again, but it is not a performance blocker.

## Architectural lessons

The repeated lesson is that Igor benefits from distinguishing four kinds of
work:

- **structural knowledge** — package contracts, descriptors, contribution
  shape; validate/compile once and invalidate deterministically;
- **current runtime truth** — binaries, active owners, preconditions, provider
  state; evaluate at the boundary that needs current truth;
- **authority/proof** — approval, privilege, CAS/state token, execution fence,
  verification, History; never replace with a presentation/startup cache;
- **presentation/convenience** — menus, operator projection, banners,
  formatting; never block authority or readiness unnecessarily.

Many of the original slow paths existed because a consumer asked for a stronger
or broader form of one of these than it actually needed.

## When to reopen performance work

Reopen this investigation if one of the following is true:

- same-host warm READY materially regresses from the post-P baseline;
- a normal operator action has multi-second Igor overhead around a much cheaper
  provider operation;
- module count causes startup to scale unexpectedly;
- first provider request becomes a user-visible bottleneck;
- a new subsystem introduces repeated full-registry scans, schema discovery,
  interpreter storms or global proof on a narrow read.

Otherwise performance work should yield to the remaining Igor 2 architectural
roadmap. Optimize from traces, not from aesthetics.
