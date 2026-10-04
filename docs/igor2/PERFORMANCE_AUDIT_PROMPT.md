# Codex Prompt — Systematic Performance-Antipattern Audit

Use this prompt when Igor needs another repository-wide performance review.
The goal is to find repeats of the architectural performance problems uncovered
by the Boundary A–P investigation without weakening Igor's safety model.

---

You are auditing `pedante/igor_core` for **systematic performance
antipatterns that preserve correct behavior but do far more synchronous work
than the consumer actually needs**.

Do not begin by optimizing code. First identify and rank candidates with
evidence.

## Context

A previous performance investigation found recurring classes of problem:

1. full-registry or whole-system evaluation for one selected capability;
2. repeated Python/subprocess startup to serialize, parse or extract tiny fields;
3. repeated validation/parsing of structural module data already validated at
   load time;
4. presentation work on the critical path before the user can interact;
5. global configuration/state proof for consumers that only need a narrow
   authoritative value;
6. caches that reconstruct most of their source just to determine whether the
   cache is valid;
7. duplicate precondition/validation passes around an already-frozen operation;
8. full History/event/JSONL scans where bounded current state is sufficient;
9. synchronous non-authoritative bookkeeping delaying a canonical result;
10. hidden expensive work inside generic hooks or registration consumers.

The successful fixes did **not** bypass authority. They separated:

- structural metadata that may be compiled/cached;
- current runtime truth that must be evaluated fresh;
- authority/proof that must remain fresh and fail closed;
- presentation work that should not block readiness/effect/result publication.

## Audit scope

Inspect the current repository, not roadmap prose alone.

Audit at least these user-visible paths separately:

- process/bootstrap and standalone TUI to first input-ready;
- classic UI startup;
- first provider-bound AI request after TUI READY;
- canonical READ capability execution;
- canonical CHANGE capability execution including approval/privilege;
- result publication after terminal History state;
- module discovery/load/registration;
- module attach/detach/inspection;
- Configuration Service reads/writes/verification;
- System Model refresh/check execution;
- Operational History admission/transition/recovery/inspection;
- operator-surface and CLI/TUI projections;
- Domain Event and Automation post-completion handling;
- knowledge/context gathering;
- deployment/provisioning paths if implemented.

## Search systematically

Look for patterns such as:

- loops that invoke `python3`, `python`, `jq`, `bash -n`, `source`,
  `find`, `stat`, `sha256sum`, external commands or database clients once
  per field/contribution/module;
- multiple `python3 -c` calls parsing the same JSON document;
- constructing JSON in one process only to parse it immediately in another;
- repeated calls to full `inspect`, `list`, `status`, schema discovery or
  registry builders when only one known record is consumed;
- whole-registry dynamic requirement evaluation for one selected object;
- repeated package validation after the package was already validated into a
  canonical loader-owned representation;
- repeated reads/scans of append-only logs or History where an owner-private
  bounded index/generation could be derived safely;
- cache-hit paths that first rebuild/serialize/hash the full uncached source;
- classic/TUI presentation work executed for a frontend that does not consume it;
- synchronous hooks on startup or terminal result publication;
- duplicated preconditions, provider validation, output validation or
  verification;
- full global state tokens/proofs being computed for read-only consumers that
  cannot authorize writes;
- expensive compatibility paths invoked for modern v2 modules;
- module-specific work leaking into startup when the module is disabled or
  detached;
- repeated opening/initialization of the same private SQLite authority during a
  single bounded startup/action;
- subprocesses whose native work is much cheaper than Igor's wrapper overhead.

Search shell, Python, tests and current docs. Trace call chains rather than
reporting grep hits in isolation.

## Authority constraints

For every candidate, state explicitly what must **not** be cached or bypassed.

Preserve:

- canonical capability resolution;
- current owner/module activation;
- dynamic binary/provider/platform requirements where they are runtime truth;
- approval;
- privilege/authentication;
- exact approved argv/inputs;
- execution-fence reprepare and digest binding;
- current preconditions;
- Configuration Service CAS/state-token semantics for writes and verified
  readback;
- provider isolation;
- typed output validation;
- verification;
- Operational History durability and recovery semantics;
- secret boundaries;
- detach/module ownership semantics.

A performance proposal that cannot explain why these remain correct is not
acceptable.

## Evidence model

Do not call something a bottleneck from code inspection alone.

For each candidate, report:

- **Path:** exact file/function/call chain.
- **Consumer:** what user-visible operation triggers it.
- **Work performed:** what synchronous operations occur.
- **Why it may be redundant/broader than needed.**
- **Authority category:** structural metadata / runtime truth / authority/proof /
  presentation.
- **Existing instrumentation:** timing/event evidence already available.
- **Missing instrumentation:** smallest additional timer/counter needed.
- **Expected scale:** fixed, per module, per contribution, per record, per event,
  per capability, etc.
- **Risk of optimization:** low/medium/high and why.
- **Safe seam:** what could be compiled, coalesced, deferred or narrowed without
  weakening authority.
- **Proof required:** focused regression and real-host measurement.
- **Priority:** P0/P1/P2 based on expected user-visible cost and confidence.

## Important negative findings

Also identify paths that look expensive but are intentionally fresh authority
and should **not** be optimized without a new design. Examples may include a
state-token calculation before a write, current preconditions before effect or
verification after effect.

These negative findings are important: the audit should reduce speculative
performance work, not create it.

## Deliverable

Produce one report with:

1. executive summary;
2. measured/instrumentable hot-path map;
3. ranked candidate table;
4. detailed analysis of the top candidates;
5. explicit authority invariants for each;
6. recommended instrumentation-only boundary for any candidate not yet proven;
7. recommended optimization boundary only where evidence is already sufficient;
8. low-value items that should be left alone;
9. possible shared abstractions/generalizations;
10. regression/real-host proof plan.

Do **not** make broad refactors merely because they are cleaner.

If you find a candidate similar to an earlier Boundary A–P issue, explain the
analogy, but inspect the current implementation independently. Do not assume the
old solution automatically fits.

## Stopping rule

Recommend stopping when:

- no remaining measured phase is disproportionate to its real work;
- remaining gains are mostly tens/low hundreds of milliseconds;
- an optimization would add more invalidation/authority complexity than the
  user-visible gain justifies;
- the next candidate lacks real-host evidence.

Igor should prefer a comprehensible, safe 2–3 second startup over a fragile
sub-second startup built from stale or ambiguous authority.
