# Increment E — independent provider and final proof

Date: 2026-10-13. Base: Owner-accepted D
`d729449f2bb26ac97791418a402956ff7e7740f0`, local `igor2`.
Phase: STABILIZATION. **Not ready for acceptance; complete Collection Operator
milestone remains open.** No commit, push, merge, live service operation or
unrelated roadmap work. `katemark-git/` is preserved untouched outside scope.

The latest verified 2026-10-14 continuation at the end of this report supersedes
earlier current-candidate findings.
Historical measurements/classifications remain intact.

Current Owner decisions (focused assessment, 2026-10-14): retain 30 seconds for
now; preserve thresholds/acceptance criteria; Pi remains blocked without an
authorized target; four inherited lint findings may remain deferred; no commit
or push. These supersede the earlier pending TTL choice for current work, without
accepting the observed navigation limitations or waiving technical gates.
See [Focused causal assessment and execution plan](#focused-causal-assessment-and-execution-plan--2026-10-14).

Requested validation budget: **DEFERRED — AWAITING OWNER APPROVAL**. The two
900-second tranches remain a proposal; no expensive workload, renewal, criterion
change, commit or push is authorized by this deferral. Increment E is still
STABILIZATION and unaccepted. See [Deferral and resumption](#deferral-and-resumption--2026-10-14)
for preserved evidence and the recommended order of work.

Owner-authorized Git checkpoint (2026-10-15): this report and its STATUS
history are committed as documentation of deferred, unaccepted work. Runtime,
fixtures and tests are preserved separately on `wip/collection-increment-e-deferred`.
E remains STABILIZATION with blocked acceptance and deferred validation;
historical no-commit instructions below describe their original checkpoints.
No push or E acceptance is authorized.

## Independent registered provider

`tests/providers/document_catalogue/` is a test-only Module API v2 package,
copied into private installations and activated by the real module loader.
It is not installed under production `modules/` and introduces no production
dependency or permanent fake interface. `catalogue.documents.list` is contract
3/output schema 2, `resource_kind=document`, `inventory=fixture_document_catalogue`.
Its row fields are scoped reference, typed document identity, title, integer bytes,
boolean archived and enum language. Columns are Title/Bytes/Archived/Language.
`catalogue.documents.read` is READ contract 2 with a D070 document selector and
two snapshot-derived inputs: document and language. Its new observations are
media, revision and summary, through the existing generic property renderer.

D049 references share the installation's existing History scope; document and
service object IDs differ. Provider/session/descriptor/query binding supplies
lease isolation, not an invented provider-specific scope or identity database.
The catalogue READ declares no mutation effects; Module API's existing closed
`affects` vocabulary is preserved. Each source JSONL read is bounded to 65536
bytes; scans stop at 1024 records or 512 KiB source bytes. This source-byte bound
is distinct from the shared serialized snapshot/page ceilings; it may reject a
large source before its projected domain data reaches the snapshot ceiling.
Rejected sources never claim a complete truncated inventory.

## Actual vertical slice and inspection

`/tmp/igor2-e-tui-corrected/summary.json` records the actual curses/PTY path:
registry discovery → canonical document collection → descriptor column order →
frozen next page → cached previous page → explicit refresh → select → declared
READ details → Back without another inventory query → explicit changed-inventory
refresh. The same live backend PID is retained. Inspection logs prove inputs
`{document: document:doc0001, language: en}` came through canonical execution.
Internal cursors are absent from ordinary terminal output.

There is no System-specific change to Core/TUI rendering, execution, resource
parsing or input mapping. The synthetic provider uses the existing registry,
`Snapshots`, descriptor READ binding, capability preparation/execution, result
validation, History, ordered event stream and frontend correlation. The Core
change below is a general lifetime fence, unrelated to provider presentation.

## Cross-provider and security evidence

`/tmp/igor2-e-isolation/summary.json` establishes System/catalogue cursor and
selection fences, distinct scoped identities in one installation, independent
owner release, target version/tier/binding changes and explicit ambiguity
resolution. `/tmp/igor2-e-limits/summary.json` adds real-backend negative requests
with a handler sentinel, catalogue Guide Skip, managed-secret rejection before
publication, reservations/concurrency, lifecycle recovery and event boundaries.
The final regression selection adds restart/restoration rejection of old
selection authority, approval, privilege, secrets, History and retained versions.
Exact final classifications are in the evidence ledger; pending/interrupted
checks must never be inferred to pass.

## Maximum boundaries and necessary Core correction

Independent document-schema tests exercise 1024/1025 rows, 128-row pages,
524287/524288/524289 serialized UTF-8 snapshot bytes, 65535/65536/65537 domain
page bytes, and 256/257 input cursor bytes. A syntactically admitted 256-byte
cursor does not acquire runtime authority. Existing governed boundary tests
exercise two snapshots/1 MiB per session, eight/4 MiB globally including in-flight
reservations, simultaneous allocation, absolute TTL, cleanup and 96-KiB events.
The common handler's bounded capture/30-second ceiling remains unchanged.

The concurrent maximum-snapshot probe demonstrated an existing expiry defect:
one System construction returned success in 31.265620 s. The old `build()`
checked expiry before final all-page validation, then validated and wrote data
without rechecking before commit. A focused reproduction failed on the old code
(`/tmp/igor2-e-expiry-reproduction/summary.json`).

`core/lib/collection_runtime.py` now rechecks the original monotonic construction
lease after final validation and after durable data writing/size encoding, before
marking the snapshot committed. It uses the existing `collection_expired` error
and cleanup machinery. No TTL extension, new mechanism, registry or dispatch.
`/tmp/igor2-e-expiry-fixed/summary.json`: 10 PASS plus one selected-lint
BASELINE_FIXED; late-validation and late-write exact-expiry cases release all
state, and affected construction-failure, TTL and exact-byte checks pass.

## Measurements and failed/unverified performance gates

Actual host: Intel Core i7-1065G7 @ 1.30 GHz, eight logical CPUs visible,
x86_64, Linux 7.2.6-1-cachyos/glibc 2.44. No authorized Raspberry Pi target was
available; no remote access was attempted. The cgroup root is not writable and
CPU/memory limit files were unavailable. Do not infer Pi equivalence.

Small actual frontend fixture (`independent-tui-measurement.json`): loading
0.015144 s, first page 13.709420 s, details interval 15.195666 s, Back 1.006942 s.
Kernel frontend VmHWM: 29172 → 31928 KiB (2756 KiB increment); final sampled RSS
31688 KiB. These intervals include backend/transport/rendering/polling and are
not isolated handler timings or maximum-size memory acceptance.
B 11.261-s and C 14.395-s first-page references and D 12.356-s details reference
remain correctly qualified; D's interval includes fixture polling and processing.

`collection_peak_probe.py` uses fresh exec'd worker processes. Baseline RSS and
released RSS are samples; peaks come from Linux `/proc/self/status` VmHWM, the
kernel per-process high-water mark. Four workers attempt two real Core snapshots
(document/System) each, with 1024 rows and exactly 512 KiB per snapshot. Source
construction happens under reservations. UTC display widths are fixed for exact
bytes; runtime expiry remains the real monotonic clock. Summed process maxima
are a conservative cohort peak upper bound, not a simultaneous RSS sample.

`/tmp/igor2-e-peak/maximum-snapshot-kernel-peaks.json` recorded increments
4932/4508/4740/4768 KiB; aggregate upper bound 18948 KiB. However **the workload
failed**: one construction returned `collection_expired`, others aged out, and
only two snapshots/1 MiB remained when inspected, rather than eight/4 MiB.
Release left zero snapshots. The test is FAIL_NEW, not a passing maximum-memory
check. These measurements precede the late-expiry correction and exclude Bash
sessions/transport descendants/TUI; they cannot satisfy final whole-backend
16-MiB-per-session/64-MiB-aggregate or maximum TUI 8-MiB gates.
The post-hardening rerun (`/tmp/igor2-e-peak-post-hardening/summary.json`) is also
FAIL_NEW, for the final concurrent-retention requirement. All eight constructions
completed without errors; per-construction elapsed times were 13.918–26.646 s.
Earlier absolute leases expired while later constructions ran, leaving two
snapshots/1 MiB at final inspection. Release again left zero state. Kernel worker
increments were 2656/1988/3092/1764 KiB, sum 9500 KiB. This is measured performance
failure, not a governor timeout, hang or allocation-accounting defect. It remains
component-only evidence, not whole-backend memory acceptance.

The actual canonical backend/curses maximum-page probe passed
(`/tmp/igor2-e-frontend-maximum/summary.json`): two retained 128-row pages, each
exactly 65536 serialized UTF-8 bytes, from one frozen snapshot; explicit refresh,
READ details and Back. The first wire event was 66253 bytes, below 96 KiB.
First-page interval was 14.094564 s, including backend/transport/frontend/polling.
Frontend empty-session VmRSS/VmHWM was 29212 KiB; kernel peak VmHWM and final
sampled RSS were 30920 KiB. The 1708-KiB increment satisfies the local 8-MiB
frontend ceiling for this workload, including maximum retained page data.
This excludes backend descendants and does not establish Raspberry Pi acceptance.

A diagnostic cProfile probe identifies repeated existing D049/privacy work as
the dominant maximum-snapshot cost: 3093 `object_ref` calls accounted for 32.216
of 36.593 profiled seconds, including 29.162 s in History redaction preparation.
Nested cumulative times must not be added. Instrumentation consumed the lease;
Core correctly returned `collection_expired` and retained zero bytes. The initial
diagnostic assertion incorrectly demanded success under instrumentation. Its
correction permits only complete validated success or canonical expiry with zero
retained state; other errors fail. Raw failure is preserved. Profile timings are
diagnostic, not isolated uninstrumented latency or a passing maximum workload.
No identity/privacy shortcut, cache, performance redesign or TTL change was made.

## TTL usability

Ten independently selectable real paced sequences are implemented in
`tests/test_collection_provider_usability.py`. Each opens inventory, pauses to
read, pages, pauses, attempts inspection, returns, encounters expiry, verifies
expired Enter cannot restore authority, and refreshes explicitly in the same
session. The fixed delays are 2/2/1 s; expiry uses Core's original lease.
A display UTC value schedules a wait only and never authorizes a request.

Trial 0 (`/tmp/igor2-e-usability-corrected/summary.json`) passed
**safe recovery**, not usability acceptance: first page 15.853158 s, next-page
interval 11.094931 s, inspection rejection interval 12.775906 s (`Details - expired`),
Back 1.002522 s (expired), explicit refresh 11.475417 s. A normal paced
page→inspect→Back cycle could not finish within TTL. Frontend kernel VmHWM
29448 → 31568 KiB; final sampled RSS 26928 KiB.
Trials 1–9 subsequently passed safe recovery in the governed, serial,
individually selected run `/tmp/igor2-e-usability-remaining/summary.json`
(558.752 s). `/tmp/igor2-e-ten-trial-usability.json` consolidates all ten actual
sequences and hashes their measurement sources. **Zero of ten** completed
page → inspection → Back before expiry. Five returned details, five rejected
inspection as expired, and all ten showed an expired collection on Back.
Median intervals: first page 12.058262 s (range 10.583885–15.853158), next page
10.942052 s (9.463459–11.708316), inspection 12.461529 s
(11.162460–13.576474), Back 1.002736 s, refresh 10.713085 s.
These are complete usability observations and a failed usability acceptance
finding, separately from the ten passing safe-recovery identities.
No silent refresh, rebind or TTL increase was used to improve results.

Owner review is now supported by the complete ten-trial observations and failed
maximum cohort. Recommendation: address the measured repeated identity/privacy
preparation within the existing canonical path while retaining the 30-second
lease and all privacy checks, then repeat the affected performance/usability
proof. Any proposed TTL/bound change requires a separate D079 Owner decision.
No numerical change is accepted or implemented here.

## Reproducible target procedure

Use an authorized Linux/Pi target with the repository's pytest/curses tools,
record its actual CPU/OS and an Owner-provided sufficient governor allowance.
The harness performs only private synthetic/mock operations. Run the peak cohort
separately from usability to avoid contaminating latency with validation load:

```bash
node=tests/test_collection_provider_peak.py
tests/validate.sh focused --base d729449f2bb26ac97791418a402956ff7e7740f0 --test "$node" --only-group "pytest:$node" --dry-run
tests/validate.sh focused --base d729449f2bb26ac97791418a402956ff7e7740f0 --test "$node" --only-group "pytest:$node" --output-dir /tmp/igor2-e-target-peak

args=(focused --base d729449f2bb26ac97791418a402956ff7e7740f0)
for i in {0..9}; do
    node="tests/test_collection_provider_usability.py::test_paced_sequence[$i]"
    args+=(--test "$node" --only-group "pytest:$node")
done
tests/validate.sh "${args[@]}" --dry-run
tests/validate.sh "${args[@]}" --output-dir /tmp/igor2-e-target-usability
```

Use new output directories and add `--python` for the target pytest interpreter
when needed. Exact node selection excludes the automatically inferred ten-case
file, avoiding a single oversized subprocess. Budget roughly 70 s per paced
trial on this local environment before planning target runs; Pi times are unknown.
The component probe does not replace a full canonical process-tree memory harness.
Full backend peak measurement must account for transient Bash/Python descendants,
with an authorized isolated process-tree/cgroup methodology; no sampled RSS-only
claim or privileged workaround is introduced here.

The additional frontend and diagnostic nodes can be selected individually with
the same dry-run/only-group procedure:
`tests/test_collection_provider_peak.py::test_maximum_domain_page_frontend_kernel_peak`
and `tests/test_collection_provider_peak.py::test_single_maximum_snapshot_diagnostic_profile`.
Run measurements separately from other validation load. The diagnostic preserves
real monotonic expiry and records profiling overhead; it does not renew authority.

## Five proof classes and remaining blockers

- Contract: both registered typed descriptors, mapping/selectors, closed bounded
  data and value-free rejected output; independent exact-boundary tests and
  canonical handler rejection sentinels established.
- Regression: accepted A–D proof retained where inputs are equivalent; fresh E
  security/History selections recorded separately. No obsolete compatibility
  layer or master reconciliation. Final candidate checks are governed.
- Vertical slice: actual System A–D proof and actual independent document
  curses/PTY canonical READ/back/paging/refresh proof established. Maximum and
  paced usability findings remain distinct: maximum concurrent retention and
  ten-trial ordinary workflow usability failed; safe recovery passed.
- Inspection: registry descriptors, private budget/lease inspection, D049
  references, selected inputs, correlated events and resource measurements are
  visible at their existing owning layers, without frontend authority.
- Migration/recovery: test-module activation/disable/detach plan/restoration,
  rejected sessions/providers, expiry, abandoned leases and failed construction
  covered. No persistent inventory/configuration/History format migration.

Outstanding release gates: failed concurrent maximum workload and ten-trial TTL
usability; unverified full canonical backend/tree peak-memory and Raspberry
Pi-class measurements. Local maximum-page frontend kernel peak is established;
the maximum cohort was rerun against the lifetime correction. Full milestone
acceptance is blocked. No mandatory acceptance assertion is weakened
or baseline failure relabelled to hide these requirements.

## Changed files and evidence

Production: only `core/lib/collection_runtime.py`, the final expiry fence and
elimination of immediately duplicated canonical row/reference validation.
Test-only: document package (README/manifest/contract/Bash adapter/Python producer),
installation and curses helpers, maximum fixture/peak worker helpers, and provider,
isolation, limits, peak, TUI and ten-case usability test files. Documentation:
this report and STATUS. Existing System handlers and production TUI are unchanged.
All files and exact per-identity classifications are recorded in
`/tmp/igor2-e-evidence-ledger.json` and `/tmp/igor2-e-candidate-proof.json`.
Historical new fixture/lint failures, benchmark failure, expiry reproduction and
permitted environmental skips remain preserved. The governor was never renewed
by the model; no hook, ceiling or coverage requirement was bypassed.

Exact scoped files (18, all uncommitted):

```text
core/lib/collection_runtime.py
docs/igor2/COLLECTION_INCREMENT_E.md
docs/igor2/STATUS.md
tests/collection_maximum_support.py
tests/collection_peak_probe.py
tests/collection_provider_support.py
tests/collection_tui_probe.py
tests/providers/document_catalogue/README.md
tests/providers/document_catalogue/contract.json
tests/providers/document_catalogue/module.conf
tests/providers/document_catalogue/module.sh
tests/providers/document_catalogue/provider.py
tests/test_collection_provider.py
tests/test_collection_provider_isolation.py
tests/test_collection_provider_limits.py
tests/test_collection_provider_peak.py
tests/test_collection_provider_tui.py
tests/test_collection_provider_usability.py
```

The first continuation changed only the maximum-page/profile test file and the two
documentation files. Core's already-tested expiry correction and provider,
isolation, bounds, TUI and usability implementations are preserved. Earlier
qualifying security/History observations remain directly applicable: none of
their production code, fixtures, environment or assertions changed. No governor
cached security pass substitutes for those fresh executed observations.

### Final scoped classifications

The evidence ledger deduplicates **171 PASS identities/check groups, 1 unresolved
FAIL_NEW maximum-workload benchmark, 1 selected-lint BASELINE_FIXED and 1 permitted
ENV_SKIP**. No E governor timeout, cancellation, tool-unavailable result or
unexplained assertion failure occurred. The original unparameterized late-expiry
reproduction is superseded by both passing parametrized correction identities;
its original failure remains historical, not deleted or treated as a pass.

Historical attempts retain their raw counts. Stage A had three fixture failures
from invalid `affects` metadata, then a pure-registry owner/provider stamping
mistake; corrections passed. Three failed lint attempts contained four NEW E
Ruff diagnostics (I001/B023), despite broad FAIL_BASELINE labels; all corrected
and final changed-file lint is clean. The first PTY attempt used the wrong arrow
sequence; corrected application-mode input passed. The first paced probe wrongly
required a new frame after a no-op on expired state; corrected level-state and
nonexecution assertions passed. None of these is inherited baseline debt.
The profiled maximum-snapshot probe initially assumed success despite profiler
overhead; corrected canonical-expiry/zero-retention checks passed in
`/tmp/igor2-e-profile-corrected/summary.json`. This diagnostic pass does not
supersede the failed maximum-retention benchmark or usability finding.

`/tmp/igor2-e-regression/summary.json` is complete: 91 PASS, 1 BASELINE_FIXED,
1 ENV_SKIP, zero failures/timeouts/errors/unavailable tools or pending groups,
48.425 s. It includes fresh approval/privilege/scrubbing/secret/History/retained-
version checks and real catalogue restoration rejecting the old selection as
expired without invoking the handler. The permitted skip is `hostname -I
unavailable`. Accepted A–D baseline limitations and D's four budget-induced
timeouts remain historical separate evidence, never passing E classifications.

Current mandatory unverified requirements: whole canonical backend process-tree
incremental peaks (16 MiB/session and 64 MiB aggregate) and Raspberry Pi-class
performance. The ten-trial usability and concurrent maximum-retention findings
are measured failures, not missing or passing evidence. No E test identities are
pending, cancelled or timed out in completed selections. Broader excluded groups
were not dispatched; unchanged qualifying prior observations are retained with
their original scope, not represented as a new whole-suite run.

The prior stopped candidate/evidence are archived under `/tmp/igor2-e-stopped-`
names. On this continuation the governor independently reported 894.210 s with
Owner authorization `Owner approved Increment E acceptance`; the model did not
renew it. New execution: maximum rerun 56.843 s, nine paced trials 558.752 s,
maximum frontend/initial profile 107.096 s, corrected diagnostic/lint 36.330 s,
then the inexpensive closing documentation check. Raw reports retain failures
and distinct measurement scopes. No repeat of passing expensive suites.

Stop in STABILIZATION with the candidate preserved. Performance correction and
repeating the affected ten-trial acceptance proof cannot fit the remaining
allowance; hardware/process-tree acceptance also lacks an authorized measurable
environment here. There is no demonstrated new unresolved authorization,
privacy, identity or result-envelope defect. Increment E and the full milestone
are **not ready for acceptance or RELEASE_FREEZE**.

## Performance and retention stabilization follow-up

Owner authorized focused work with 124.944 s remaining, without renewal. The
18-file/19-run candidate was verified and archived as
`/tmp/igor2-e-before-preparation-candidate-proof.json` and
`/tmp/igor2-e-before-preparation-evidence-ledger.json`; all original raw evidence
and unrelated `katemark-git/` remain intact.

### Minimal production correction and security

Construction previously called D049 `object_ref` to create each reference, then
immediately called it again through `_validate_output_record_value`. Build now
supplies the context scope and producer object ID to that same canonical row
validator once. Its validated reference is used for duplicate detection. All
D049 shape, 160-character identity bounds, current privacy checks and canonical
page/result validation remain. No persistent or cross-request validation cache.

Selection previously validated the matched stored row and its serialized size,
then validated both again through `_page`. It now obtains the row exclusively
from `_page`, which checks the whole closed typed page, D049 references, current
privacy and the stricter combined 64-KiB page bound. Request identity, membership,
session/owner liveness, descriptor binding and execution-time target checks are
unchanged. Rejected stored values cannot become inspection inputs.

`/tmp/igor2-e-preparation-focused/summary.json`: 35 PASS, 1 BASELINE_FIXED,
zero new failures, 14.364 s. New negative tests reject a secret-bearing identity,
corrupted private snapshot row and a newly configured secret at selection time.
Counting tests prove two-row preparation falls from eight to six passes and
selection from four to three. Fresh affected provider/version/session rejection,
construction failure, lifecycle, expiry, History privacy and secret-reference
checks passed. Unchanged Guide/approval/privilege policy has no new bypass.

### Capacity correctness versus real-time performance

The peak harness now selects `[capacity]` and `[performance]` independently.
Controlled capacity uses four synchronized, live workers, each with two small
typed snapshots, and only the existing injected test clock. All eight committed
snapshots coexist; a ninth session fails with `collection_budget_exhausted`
without changing retained state. Disabling the document owner leaves four System
snapshots; exact 30-second expiry removes those, and release leaves zero state.
This proves count capacity, ownership and expiry independently of workload speed.
It does not claim eight maximum-byte snapshots were retained in that test.
Previously established exact reservation/byte-bound evidence remains separate.

Real monotonic time uses four workers with two 1024-row/exact-512-KiB snapshots
each. All eight constructions succeeded individually in 9.079–23.468 s; final
inspection retained four snapshots, not eight, so `[performance]` remains
FAIL_NEW. The highest count observed at post-commit inspection checkpoints was
four, including any reservations; these checkpoints do not establish a continuous
peak. Cleanup left zero snapshots/bytes/reservations. Worker kernel peak increments
were 3476/3308/3628/3032 KiB, sum 13444 KiB. They remain component measurements,
excluding canonical Bash sessions/transport descendants and unable to establish
16-MiB/session or 64-MiB aggregate whole-backend acceptance.

The same profiled maximum snapshot now completes successfully with 1024 rows and
524288 bytes in 25.171018 s. D049 calls fell from 3093 to 2069 (33.1%); total
profiled time fell from the last prior 30.131744 s by 16.5%. Nested cumulative
reference/privacy time is 20.916 s, still dominant. These are actual diagnostic
observations, including profiler overhead, not isolated handler latency.
`/tmp/igor2-e-retention-separated/summary.json`: 2 PASS, 1 FAIL_NEW,
1 BASELINE_FIXED, 81.752 s, zero timeouts/cancellations.

### Remaining measurement gates and Owner decision

The producer/dispatcher route remains System `svc_list_query` → bounded adapter
reads → `Snapshots.build` → canonical capture/output validation → result/event
projection → existing event reader/rendering. Inspection remains snapshot
selection → frozen READ preparation → Guide/approval/execution-time recheck →
canonical execution and detail projection. Per-page validation still rechecks
references/privacy; dispatcher and frontend validate their own trust boundaries.
These retained checks were not removed to improve timings. System discovery,
dispatch, event-delivery and READ phase timings have not yet been isolated.

All ten original paced observations remain preserved (0/10 complete while fresh).
They are **pre-correction performance evidence**, not post-correction usability
results. The unchanged ten sequences must be rerun, with additional visibility,
remaining-lifetime and authorization timing evidence. Their prior 558.752-s run
cannot fit this allowance; none was dispatched merely to leave an interrupted
group. No accelerated pacing, changed TTL start or automatic refresh.

The existing 1708-KiB frontend peak is retained as x86_64 evidence for two exact
maximum pages plus refresh/details/Back; production TUI, frontend validation and
event inputs are unchanged. It is not whole-backend or Pi evidence. A transient
process-tree peak mechanism and the requested one/two/eight-snapshot backend
measurements remain unimplemented/unverified here; sampled RSS, worker VmHWM and
cgroup memory accounting must not be substituted for each other. The cgroup root
is not writable, and no authorized delegated measurement group or Pi target is
available. The target commands above reproduce current component/frontend and
pacing probes; they do not purport to finish the missing process-tree harness.

Thirty seconds is unchanged. Current post-correction TTL usability is unverified,
and concurrent retention remains impractical in the tested maximum workload.
Owner review needs complete post-correction pacing and memory evidence before a
quantified longer-TTL decision. Prior median next/inspection intervals alone total
23.404 s, before reading, discovery, preparation and Back; this motivates further
canonical-path profiling, but is not evidence for an accepted replacement TTL.
Retaining documented limitations requires an explicit acceptance-policy decision;
a longer absolute lease retains stale rows and budget occupancy longer. No
architectural alternative is justified or implemented from incomplete evidence.

This follow-up changes only Core collection runtime, the peak worker/tests,
provider limit tests and the two reports (six existing scoped files). Stop in
STABILIZATION; Increment E remains unaccepted. Current qualifying observations,
superseded performance identities and pending post-correction gates are recorded
in the updated ledger. Original failures and skips are not turned into passes.

## Bounded preparation continuation — 2026-10-14

The governor externally reported 892.433 s with Owner authorization `Owner
approved Increment E`; no renewal was performed by the model. The prior
18-file/23-run candidate and ledger were verified and archived under
`/tmp/igor2-e-before-bounded-reuse-*.json`. No original evidence was deleted.

### Scoped preparation and proof

The canonical structured record validator now shares legacy redaction preparation
only among references in one bounded validation invocation. D049 `object_ref`
still checks each reference's format, length and privacy; managed sanitization
is still performed. The private optional pairs argument preserves the default
fresh behavior of existing History callers. Each new row admission, page,
selection or result validation gets a new context. No session/snapshot
authorization is cached and no descriptor/provider check is removed.

`privacy.sanitize_selected_data` now prepares the existing managed-secret
projector once per projection invocation, lazily at the first string. It projects
each string with `final=True`, preserving field boundaries, keys and non-string
values. The next invocation reloads material and audits access again; no projector
or credential data survives in an application cache. The existing private
streaming projector is reused, not replaced. New tests verify newly staged
material, partial fields, audit failure and newly configured legacy secrets at
the next page validation.

Actual bounded 1000-string projection: 1000 preparations/0.708995 profiled seconds
before, one preparation/0.088105 s after (87.6% lower). The maximum snapshot
profile also completed under the unchanged 30-second lease. Exact profile and
workload artifacts remain in `/tmp/igor2-e-batched-retention/`.

`/tmp/igor2-e-bounded-reuse-focused/summary.json`: 192 PASS, one reviewed
FAIL_BASELINE Ruff group, no functional failures, 89.934 s. This freshly exercises
the collection contract, retained capability versions, History, managed-secret
projection/audit/approval boundaries, secret references and inspection
provider/version/rejection tests. The four History diagnostics (FURB167, B023,
PLR0124, RUF059) match accepted source, as the executed baseline comparison test
proves; they were not repaired or described as passing lint.

### Retention and paced results

Controlled count capacity remains passing. The real monotonic maximum cohort
now also passes: eight committed 1024-row/exact-512-KiB snapshots coexist,
total 4194304 bytes. Construction durations are 5.632–9.646 s; release leaves
zero snapshots/bytes/reservations. The maximum profile and both capacity modes
record 3 PASS in 46.144 s, no failures/timeouts. This is Core snapshot proof,
not whole canonical backend memory acceptance.

The original 2/2/1-second reading delays, requests and absolute lifetime start
are unchanged. Test-only Bash delegates measure existing preparation, handler,
execution, inspection and event-emission functions without inspecting arguments
or changing outputs/decisions. They record UTC phase boundaries and request
correlation; frontend observations include remaining lifetime and expiry.
They add measurement overhead, not a new dispatcher or frontend authority.

Six sequences completed safe recovery: trials 0,1,2,3,4,6, with 0/6 complete
page→inspection→Back while fresh. Median first page 14.414 s, next page 13.634 s,
details interval 14.393 s, Back 1.003 s, refresh 14.156 s. Median remaining
lifetime at first visibility is 26.109 s. These are partial observations;
the ten-sequence acceptance requirement is **not established**.

Trial 0 had 26.945 s remaining when visible. Its inspection preparation began
17.313 s after first visibility, while fresh; execution-time revalidation also
completed while fresh. Details became visible after expiry, an admitted READ
completion permitted by D's contract; Back correctly showed expired state.
The phase records include authorization and handler/dispatch intervals.
First/next/details intervals still include transport/rendering/polling and must
not be labelled isolated handler times. A host load sample was 8.67/6.74/5.50 on
eight visible CPUs; no isolated-hardware performance claim is made.

Trial 5 failed a fixture assertion: terminal already showed expired, but `wait`
required another frame. The test now checks the visible header before awaiting
the expiry transition. Pacing, authority and negative nonexecution assertions
are unchanged. This correction is **unverified**, not a passed test.

The batch was interrupted after recognizing that failure. The tool returned
130, but the raw runner checkpoint remains `running`: five completed PASS
observations, one FAIL_NEW, trial 7 active at interruption and 8/9 pending.
It is partial/interrupted evidence, not a complete run or a governor timeout.
The governor now reports zero and retains the reserved allowance. The model
did not repair the ledger, renew it or dispatch more checks. Completed node logs
are retained independently; the whole interrupted plan cannot be reused as a pass.

### Process-tree mechanism and unverified workloads

New test-only `collection_process_peak.py` observes only a newly created owned
child tree with Linux fork/exec/exit stops. Exit stops capture VmHWM before
short-lived processes disappear; wait4 adds a conservative lifetime bound.
TGID deduplicates threads. Bootstrap launcher memory is excluded. Summed
simultaneous RSS samples are lower bounds; sums of live-process high-water
marks, including wait4 overcount, are conservative upper bounds. These are
neither exact simultaneous peaks nor cgroup memory accounting.

The sandbox rejected tracing. The explicitly approved governed rerun outside
the sandbox passed a child that allocated 20 MiB then exec'd a smaller process:
observed simultaneous RSS lower bound 34072 KiB, conservative tree upper bound
36868 KiB. This proves the measurement mechanism, **not a backend memory gate**.
Its original permission failure remains historical environmental evidence.
A new BLE001 diagnostic in the tracer was corrected; final lint verification
was not dispatched after allowance loss, so it is not absorbed into baseline debt.

`test_collection_process_peak.py` supplies reproducible one-collection,
two-snapshot/session, four-session/eight-snapshot and failed-construction/cleanup
cases through actual module registration and canonical READ execution. It uses
controlled document and System sources and no live service changes. Each case
compares the same empty-inventory workflow against the maximum workflow. Upper
workload peak minus lower empty-workflow peak bounds the difference of peaks;
subtracting two upper bounds would not. The baseline definition and both raw
bounds are retained. These workload cases are **all undispatched/unverified**,
as are their source fixture and threshold assertions; no backend 16/64-MiB claim.

On an authorized Linux/Pi target, install the declared pytest/curses/tools and
record actual CPU, kernel, libc, load and interpreter. Use the existing dry-run
procedure with these exact nodes individually, granting only owned-child tracing
if required by the environment:

```text
tests/test_collection_process_peak.py::test_owned_kernel_trace_observes_transient_exec_memory
tests/test_collection_process_peak.py::test_canonical_backend_process_tree_peaks[1-1-False]
tests/test_collection_process_peak.py::test_canonical_backend_process_tree_peaks[1-2-False]
tests/test_collection_process_peak.py::test_canonical_backend_process_tree_peaks[4-2-False]
tests/test_collection_process_peak.py::test_canonical_backend_process_tree_peaks[1-1-True]
```

Do not run traced memory workloads concurrently with untraced paced/latency
measurements. Use a new output directory, retain threshold failures, preserve
real monotonic expiry and run the ten original pacing nodes separately.
No Raspberry Pi target exists in this session; Pi acceptance stays unverified.
Prior 1708-KiB frontend memory remains historical x86_64 evidence, not fresh
maximum-page acceptance after shared frontend validation changes.

### Candidate, proof classes and stopping state

Six new files join the preserved 18-file scope: production
`core/ai/privacy.py`, `core/lib/capability_runtime.py`,
`core/lib/operational_history.py`; test-only `tests/collection_process_peak.py`,
`tests/test_collection_process_peak.py`, `tests/test_collection_privacy_performance.py`.
Existing helpers/tests/reports are updated within Increment E. No new module,
registry, identity format, dispatch protocol, persistence or UI feature.

Contract and affected privacy/History regression proof passed. Core maximum
retention and the kernel mechanism passed. Prior independent-provider vertical
proof is retained at its original scope; current six paced workflows are
partial real canonical TUI/READ proof. Inspection phase records remain
observational, and prior module/recovery proof is not a substitute for missing
current workload checks. All five classes are tracked with these gaps.

Outstanding: correct-and-rerun trial 5, complete 7–9; final tracer lint;
canonical process-tree workloads and failure/cleanup thresholds; fresh maximum
frontend measurement; Pi-class evidence; complete isolated stage profiling.
No new unresolved production authorization defect is demonstrated. Full
performance/usability acceptance remains blocked, so no RELEASE_FREEZE.

Thirty seconds remains unchanged. Even after faster construction, six actual
sequences expired on Back. An Owner-reviewed longer absolute TTL (e.g. a measured
45/60-second candidate) would extend stale-data exposure and memory residency;
these durations are **unmeasured proposals**, not justified accepted values.
First finish comparable ten-trial and memory evidence, then decide whether to
retain 30 seconds with explicitly permitted limitations or authorize tuning.
No architectural replacement is justified by incomplete evidence.

Documentation changes after interruption have no governed closing pass; prior
passing checks are not represented as validating this final documentation.
Stop with 24 scoped files and all raw evidence preserved; no commit or acceptance.

## Verified stabilization continuation — 2026-10-14

Phase remains STABILIZATION. Allowed work: verify corrected tests, review backend
peak-measurement availability, preserve evidence and finish the scoped report.
Exit requires the outstanding performance/hardware proof and D079 Owner review;
no RELEASE_FREEZE, acceptance or commit. No production/test source was changed
in this continuation. `katemark-git/` remains outside scope.

The retained observations were newer than the previous report. All 24 candidate
file hashes matched before documentation edits. All 134 ledgered summary/log
files and 16 ledgered artifacts matched their recorded hashes. Prior candidate,
ledger and reports were archived under `/tmp/igor2-e-before-verified-continuation-*`
before integration. The external governor authorization is `Owner approved
Increment E final stabilization`; 535.146 s remained at inspection. No model
renewal or interrupted-ledger repair occurred.

### Corrected verification and ten-trial findings

`/tmp/igor2-e-final-paced-remaining/summary.json`: four PASS, no failures,
277.603 s. This verifies the corrected expiry-frame assertion in trial 5 and
completes trials 7–9. The original failed assertion and interrupted checkpoint
remain unchanged. Trials 0–4 and 6 retain their completed node evidence, with
equivalent pacing/authority/nonexecution/refresh assertions; their partial batch
as a whole is never represented as complete.

`/tmp/igor2-e-final-ttl-analysis.json` consolidates all ten observations.
`/tmp/igor2-e-verified-ttl-provenance.json` binds each measurement artifact to
its successful exact node, summary and SHA-256. **10/10 passed safe recovery;
0/10 completed page→inspection→Back before expiry.** One returned ready details,
nine reported expired details, and all ten showed expired state on Back.
Expired Enter did not execute READ, and explicit refresh created new authority.

Median first page / next page / details / Back / refresh intervals were
14.206792 / 13.528198 / 13.536471 / 1.002837 / 12.735559 s. Remaining lifetime
at first visibility was 25.727357–26.945115 s, median 26.108874 s. These are
end-to-end observations on the recorded x86_64 host with varying load and
measurement overhead; they are not isolated handler latency or Pi proof.

`/tmp/igor2-e-final-pending-corrections/000-ruff.log` verifies the BLE001
correction: only the four independently reviewed inherited History diagnostics
remain (FURB167/B023/PLR0124/RUF059). The raw lint group remains FAIL_BASELINE,
not clean whole-scope lint. That attempt's Python lacked pytest and remains
TOOL_UNAVAILABLE; the subsequent pinned-interpreter attempt supplies the actual
mechanism failure below. Neither tooling result weakens a mandatory gate.

### Backend peak availability and fresh frontend peak

`/tmp/igor2-e-final-kernel-availability/summary.json` completed with one raw
FAIL_NEW: `PermissionError: owned-child tracing unavailable` (EPERM), before
the measurement workload. This is a fixture/environment permission failure,
not evidence of a production defect or a measured memory-ceiling failure.
The current shell has seccomp filtering and no-new-privileges; this session
cannot request unsandboxed execution. The earlier externally approved mechanism
self-check remains valid only for its own authorized environment.

All four canonical backend workload cases listed above remain undispatched.
There is **no new backend peak measurement** and no 16/64-MiB acceptance claim.
Repeated tracing attempts in an equivalent restricted environment would not
supply missing evidence. No privileged workaround, alternate checkout, RSS-only
substitute or changed threshold was used. Run the retained exact nodes serially
in an authorized tracing environment, with the pinned pytest interpreter and
a sufficient externally granted governor allowance. Preserve lower/upper bounds,
result validity and cleanup failures. The current list/construction/cleanup
cases alone also cannot prove RFC-required detail and refresh-overlap memory;
those workload observations remain an explicit coverage gap.

`/tmp/igor2-e-final-frontend-maximum/summary.json`: one PASS, no failures,
71.995 s. The real canonical curses workload retained two exact 128-row,
65536-byte pages and exercised refresh, READ details and Back. First wire event:
66253 bytes. Empty frontend VmRSS/VmHWM: 29452 KiB; kernel peak VmHWM:
31332 KiB; final sampled RSS: 17792 KiB. Increment **1880 KiB** satisfies the
local 8-MiB frontend ceiling. First-page interval: 12.438521 s. This fresh
evidence supersedes the historical frontend measurement for the shared-validator
candidate; it excludes backend descendants and Raspberry Pi acceptance.

### Remaining TTL decisions and proof boundaries

The accepted absolute 30-second lease, monotonic authority, explicit refresh
and fresh execution-time revalidation remain unchanged. The complete ten-trial
findings now support D079 Owner review, but backend and Pi memory evidence are
still missing. Owner decisions remain:

- Retain 30 seconds with explicitly accepted ordinary-navigation limitations,
  or authorize a longer absolute TTL candidate and its affected verification.
  Longer retention extends stale-data exposure and count/byte budget occupancy.
- Choose a candidate duration from successful-workflow and memory evidence.
  45/60 seconds are untested proposals. Observed detail-outcome lease age has
  median 38.688342 s, p90 42.893305 s and maximum 44.780475 s; expiry observation
  reaches 47.093787 s. Nine rejected details omit successful READ work, so these
  numbers cannot establish that either proposed TTL permits a full workflow.
- Preserve the remaining backend/Pi performance gates, or explicitly decide
  acceptance limitations under D079. This report grants no waiver or tuning.

Recommendation: preserve 30 seconds pending trace-capable backend/Pi evidence
and Owner review. The existing authority path remains the architecture; no
automatic renewal, altered lease start or replacement dispatch is proposed.

Contract/regression proof and the passing maximum-retention cohort are retained.
Independent-provider vertical/recovery proof now includes all ten post-correction
safe workflows and a fresh maximum frontend workload. Inspection/provenance is
preserved. Usability acceptance failed, whole-backend memory is blocked, Pi and
complete isolated System/serialization/transport/frontend stages remain
unverified. Documentation validation is recorded separately in the updated
ledger; it does not supply missing runtime proof. All historical raw failures,
skips, interruptions and environment-specific results remain preserved.

## Resumed trace-capable stabilization — 2026-10-14

Phase remains STABILIZATION. Allowed work was the missing owned-child backend
memory observations, concrete fixture corrections and evidence integration.
Exit still requires backend/Pi performance proof and D079 Owner review; no
acceptance, RELEASE_FREEZE or commit. Before editing, all 24 candidate file hashes
and 183 retained summary/log/report/artifact hashes matched. Prior candidate,
ledger and reports are archived under `/tmp/igor2-e-before-resume-*`.

The existing external authorization retained 524.554 s at entry. No renewal,
ledger repair, new checkout, production change, threshold change or TTL tuning.
No traced memory run overlapped an untraced latency measurement. Required checks
use the pinned pytest/Ruff interpreter and governed exact-node plans, serially,
with a 180-second subprocess cap for workload cases.

### Trace lifecycle correction

The approved outside-sandbox self-check completed: one PASS in 8.085 s,
`/tmp/igor2-e-resume-trace-availability/summary.json`. The original sandbox EPERM
remains historical environment evidence; this result supplies no Pi proof.

The first canonical one-collection case failed with `ChildProcessError` during
the empty baseline. A targeted diagnostic reproduced the failure and showed
eight already-reaped children re-added after their parent's fork notification.
Both raw FAIL_NEW attempts remain under `/tmp/igor2-e-resume-backend-single/`
and `/tmp/igor2-e-resume-trace-diagnostic/`. These are fixture lifecycle defects,
not production or memory-ceiling failures. The test-only tracer now remembers
exited children and adds children observed at a stop before the parent event.
The temporary diagnostic was removed. Its only caller is the peak test file;
existing canonical workload assertions exercise the correction without changing
runtime authority, sources, result checks or cleanup requirements.

### Completed canonical observations

All values below are KiB. Lower bounds sum simultaneously observed process RSS;
upper bounds conservatively sum live-process high-water marks/wait4 accounting.
Shared pages and wait4 child accounting can overcount. Subtracting the empty
workflow's lower peak from the maximum workflow's upper peak yields a conservative
upper bound on the difference of peaks, not a measured exact incremental peak.

| Case | Empty lower / upper | Workload lower / upper | Increment upper | Ceiling |
|---|---:|---:|---:|---:|
| One session, one collection | 105940 / 125368 | 108036 / 127456 | 21516 | 16384 |
| One session, two collections | 154316 / 201460 | 142240 / 195748 | 41432 | 16384 |
| One session, failed construction | 106096 / 125488 | 107372 / 126720 | 20624 | 16384 |

Every case completed with return code zero and zero snapshots, serialized bytes
and reservations after termination. Successful list outputs were valid. Failed
construction returned only `collection_limit_exceeded`, with no valid result.
All three tests nevertheless remain raw FAIL_NEW at the unchanged RSS assertion.
The difference-of-peaks intervals are respectively [-17332, 21516],
[-59220, 41432] and [-18116, 20624] KiB. Each interval includes the ceiling:
these observations neither prove compliance nor establish an actual violation.
No correct production behavior was changed to satisfy an inconclusive bound.

`/tmp/igor2-e-resume-backend-single-fixed/summary.json`: one FAIL_NEW,
61.003 s, complete; its canonical artifact records the one-collection case.
`/tmp/igor2-e-resume-backend-pair-failure/summary.json`: two FAIL_NEW,
158.235 s, complete; both canonical artifacts are preserved. Traced empty/maximum
durations were 23.941/29.159, 42.972/56.262 and 22.114/27.304 s respectively.
These include instrumentation; they do not replace the untraced ten-trial data.
This x86_64 host remains Intel i7-1065G7, Linux 7.2.6-1-cachyos, glibc 2.44;
an observed load sample was 4.73/4.13/3.75. No isolated-hardware claim.

### Aggregate fixture boundary and remaining acceptance

`/tmp/igor2-e-resume-backend-global/summary.json`: one FAIL_NEW, complete,
84.010 s. The four-session/two-collection case reached the test tracer's
4096-record guard in the empty baseline. No complete baseline/workload artifact
or aggregate memory bound was produced. This is a fixture capacity failure,
not evidence that Igor exceeded the global count/byte or 64-MiB RSS ceiling.
The guard was retained. With 149.550 s left before closing checks, a conservative
serial estimate for the remaining full aggregate pair exceeded the allowance;
no speculative rerun or budget renewal was made. A follow-up needs a scoped
tracer-capacity correction and a bounded plan for complete aggregate evidence.

The prior independent-provider, privacy/History, maximum-retention, ten safe
recovery sequences and fresh 1880-KiB frontend observations retain their recorded
scope: their production/TUI inputs are unchanged. The lifecycle correction
invalidates prior tracer proof, not unrelated runtime regressions. Current tracer
lint, self-check and documentation closing results are recorded in the updated
ledger. Original failures are never converted to passes.

Whole-backend acceptance remains unestablished, with three inconclusive failed
ceiling proofs and one incomplete aggregate fixture. Detail/refresh-overlap,
Pi-class and complete isolated-stage evidence remain missing. The unchanged
30-second lease still yielded 0/10 complete navigation workflows. Preserve it
pending sufficient measurements and D079 Owner review; no unmeasured replacement
TTL, relaxed ceiling or acceptance waiver. Only the tracer and these two reports
changed in this continuation. Stop in STABILIZATION with the 24-file candidate
and raw evidence preserved; no commit or push.

## Owner-requested conclusive assessment — 2026-10-14

**Lifecycle: STABILIZATION. Acceptance disposition: BLOCKED.** Increment E is
not technically ready and is not READY FOR OWNER REVIEW as a completed candidate.
Owner TTL review can proceed on the existing observations, but cannot substitute
for the missing technical gates. All five EXECUTION proof classes retain their
prior scope; missing hardware/performance coverage prevents closure. No commit,
push, Wave F or broader development-process implementation is authorized here.

All 24 candidate file hashes matched at entry. The prior candidate, ledger,
tracer, peak tests and reports are preserved under
`/tmp/igor2-e-before-owner-assessment-*`. The governor retained 139.403 s under
the existing Owner authorization; this request did not renew it. Only the test
tracer, its peak tests and the two E reports changed. Production, descriptor
versions, safety/approval/privilege, privacy, History, snapshot limits and the
absolute 30-second TTL retain the prior candidate hashes/contracts.

### Finding disposition

| Finding | Disposition | Demonstrated / missing evidence |
|---|---|---|
| Child-lifecycle race | VERIFIED at instrument scope | Existing native exec-memory self-check and the 4202-process native workload passed; late-fork fencing remains. These do not stand in for the full canonical backend gate. |
| One-collection RSS ceiling | UNVERIFIED; historical raw proof FAILED | Valid canonical result and cleanup; difference interval [-17332, 21516] KiB includes 16384. No actual peak violation established. |
| Two-collection RSS ceiling | UNVERIFIED; historical raw proof FAILED | Both canonical results valid and cleanup; interval [-59220, 41432] KiB includes 16384. No actual peak violation established. |
| Failed-construction RSS ceiling | UNVERIFIED; historical raw proof FAILED | Correct value-free rejection and cleanup; interval [-18116, 20624] KiB includes 16384. No actual peak violation established. |
| Aggregate record capacity | VERIFIED correction at instrument scope | 4202 processes traced without raising the 4096-record ceiling or losing an early peak. Real four-session pair remains UNVERIFIED after correction. |
| Backend detail/refresh-overlap memory | UNVERIFIED | The canonical backend peak fixture invokes list calls only; it contains no inspect request or refresh replacement workload. Frontend evidence excludes backend descendants. |
| Raspberry Pi-class acceptance | UNVERIFIED / external blocker | Retained host is x86_64; no authorized Pi access/hardware was supplied. Emulation or a label cannot supply constrained-hardware measurements. |
| Inherited lint | FAILED_BASELINE; inheritance VERIFIED | FURB167, B023, PLR0124 and RUF059 independently reproduced on the accepted History source. New diagnostics must still be reviewed in closing lint. |
| TTL usability | FAILED observation; AWAITING OWNER DECISION | 10/10 safe recovery, 0/10 complete while fresh; current absolute lease unchanged. |

### Bounded diagnostic retirement

The old guard counted every historical process record. The four-session fixture
exhausted that cumulative guard during its empty baseline, with bounded sessions.
Discarding live-process state would invalidate memory proof; increasing the
ceiling would only postpone the fixture failure. The smallest correction retires
only completed diagnostic records after their peak contribution is accounted.
The same 4096 guard covers retained records, live tasks and outstanding late-fork
tombstones; active record pressure still fails closed. Parent fork notifications
consume pending tombstones, and acknowledged completed children do not accumulate
in the fencing set. No Core limit or RSS acceptance threshold changes.

The artifact explicitly reports `completed_process_count`,
`discarded_process_records` and `process_records_complete`. Retired diagnostic
detail cannot be presented as a complete process ledger. Peak counters remain
accumulated over the entire observed workload; they are not reset on retirement.

`/tmp/igor2-e-owner-trace-retirement/summary.json`: **2 PASS**, zero failures,
63.761 s. The new native regression allocates 20 MiB, execs a smaller image,
then completes 4200 short children. Artifact
`kernel-trace-record-retirement.json`: 4202 completed processes, 4094 retained
records, 108 discarded, return code zero; remaining records' largest wait4 value
is 1696 KiB, while the preserved RSS lower / conservative upper peak is
33704 / 36280 KiB. The earliest high-memory record is gone, yet its peak survives.
The original exec-memory self-check passed separately in the same governed plan.
These prove bounded recording and lifecycle/counter preservation, not Igor's
16/64-MiB backend acceptance or tighter measurement precision.

### Why the three bounds remain unresolved

Empty-workflow upper-minus-lower uncertainty is 19428, 47144 and 19392 KiB for
one collection, two collections and failed construction respectively. Maximum
workflow uncertainty is 19420, 53508 and 19348 KiB. The uncertainty alone exceeds
the 16384-KiB allowance; even an identical empty trace compared with itself can
fail this conservative proof. Parent/child wait4 accounting and non-simultaneous
lifetime high-water marks overcount; sampled simultaneous RSS is only a lower
bound. Retiring diagnostics preserves this arithmetic and cannot turn any of
the historical failures into passes.

Smaller traces are useful diagnostics, but are not equivalent whole-backend
proof when they omit startup/retention, parsing, validation, event serialization,
READ inspection, refresh overlap or cleanup. Summing isolated worker results,
subtracting two upper bounds, substituting sampled RSS or using cgroup accounting
as RSS would not establish the existing contract. A valid tighter instrument
must retain transient pre-exec/exit allocations and all concurrently live backend
processes, distinguish measurement uncertainty from a ceiling violation, and
document its baseline and phase coverage. Validate that instrument with known
allocation/exec/overlap workloads before applying it to maximum canonical cases.
No unverified instrument replacement is introduced in this assessment.

The corrected canonical aggregate pair needs execution in a trace-capable
environment. Its old empty baseline alone reached the guard after 75.642 s;
the single-session/two-call pair took 99.525 s. The remaining allowance after the
instrument/regression work cannot cover aggregate plus all detail/refresh and
three renewed maximum pairs. None was dispatched merely to leave partial proof.
The three older artifacts remain historical observations of unchanged production;
they are not fresh acceptance under the modified instrument. No budget renewal.

Reproduce the instrument correction with the existing pinned pytest interpreter:

```bash
bash tests/validate.sh focused --base HEAD --python /path/to/pinned/python \
  --test tests/test_collection_process_peak.py::test_trace_retires_diagnostics_without_losing_early_peak \
  --only-group pytest:tests/test_collection_process_peak.py::test_trace_retires_diagnostics_without_losing_early_peak \
  --command-timeout 70 --dry-run
```

After inspecting the plan, run the same selection without `--dry-run`, with a
new `--output-dir` and an environment key identifying the actual target/tracing
environment. Obtain normal environment authorization for owned-child tracing.
Existing canonical peak nodes remain listed in this report; execute one bounded
group at a time. If a complete baseline/workload pair cannot fit a governed
subprocess, first specify an equivalent bounded partition preserving both raw
artifacts, environment, maximum data, concurrency and cleanup. Do not raise the
runner ceilings or infer aggregate proof from independent sessions. Pi execution
also needs actual board/RAM, kernel/libc/interpreter, CPU/load and release RSS
provenance; no access is assumed from retained host data.

### Regression and lint evidence

`/tmp/igor2-e-owner-regressions/summary.json`: **30 PASS**, no failures/skips,
20.383 s. Fresh checks cover capability preparation, supported result versions,
provider versus typed-output failure, shell bridge/version pins, sorted-schema
transport, managed projection refresh/fail-closed behavior, secret references
and secret non-retention in History. An independent test reproduced the four
History diagnostics against the accepted checkpoint. Previous canonical Guide,
approval, privilege, provider isolation, migration/recovery and frontend evidence
retains its source-equivalent scope; these passing checks are not a full-suite
or Pi claim. Closing lint/structure/diff results are recorded in the updated
ledger; a reviewed baseline group is never described as clean lint.

FURB167 is the `re.I` alias; B023 flags the loop token in the synchronously used
redaction callback; PLR0124 flags the existing self-comparison NaN check;
RUF059 flags an unused unpacked owner. All predate E. No new diagnostic is
absorbed into baseline debt and no unrelated History refactor is undertaken.

### Explicit TTL decision request — pending

The lease bounds how long frozen membership and row-derived selectors may be
used, limits stale-state exposure, and releases occupied snapshot count/byte
capacity. Expiry is absolute from construction; paging, details and Back do not
renew it. Execution admitted while fresh retains its frozen operation; a later
expired request cannot revive authority. Explicit refresh creates new authority
and rereads sources under the same safety/privacy/History path.

Owner decision requested: choose a direction, without waiving memory/Pi gates.

- Preserve 30 seconds pending complete backend/Pi evidence (**recommendation**).
  No acceptance yet; the known navigation failure remains visible.
- Accept 30 seconds with explicit ordinary-navigation limitations. This is an
  explicit usability acceptance decision, not proof of a successful workflow or
  permission to waive other technical gates.
- Authorize bounded, measured latency corrections under the same lease.
  This preserves exposure/residency bounds but requires concrete profiling and
  equivalent privacy/authorization regression evidence before further edits.
- Authorize evaluation of a longer **absolute** lease. 45/60 seconds are untested
  candidates, not requested implementation values. Longer retention occupies
  global/session budgets longer, increases stale-data exposure and can increase
  refresh-overlap residency. Require successful READ/navigation and maximum
  memory/hardware evidence before choosing a duration, then explicit approval
  before changing it.

The asynchronous Owner request is pending unless explicitly answered. No
selection, elapsed time or lack of reply authorizes a TTL change. Automatic
renewal or a changed lease start would alter the accepted authority contract
and is outside this stabilization. The thirty-second value remains unchanged.

### Deferred development-improvement milestone outline

This is a requested future outline only. Technical readiness is the prerequisite
for a separate proposal; no process review or implementation begins in E.
That later milestone should inspect existing `.codex/README.md`, architecture/
decisions, EXECUTION proof classes and `tests/validate.sh`, and propose:

- A compact task/handoff context with accepted decisions, ownership, phase,
  source candidate and explicit outstanding gates, reused across compaction.
- Smaller increment specifications with observable acceptance scenarios,
  exclusions, required tools/hardware and duration estimates before coding.
- Contract tests plus canonical real-consumer and recovery paths, with diagnostic
  measurements clearly separated from acceptance and baseline failures.
- Calibrated memory instruments, operation-appropriate baselines, bounded
  stage/concurrency groups and named hardware evidence using the existing runner.
- An independent review of the connected implementation and proof ledger when
  the Owner authorizes it; no delegation or duplicate implementation by default.
- One retained decision/regression/unfinished-work ledger linking candidate,
  raw artifacts, invalidation and Owner acceptance. Reuse existing reports and
  governor state rather than adding another registry or development framework.

That proposal needs its own DISCOVERY scope and Owner confirmation. It does not
authorize Wave F, new process infrastructure or repair of unrelated baseline debt.

## Focused causal assessment and execution plan — 2026-10-14

Phase: STABILIZATION; acceptance remains BLOCKED. This pass analyses retained
evidence and specifies discriminating next work. It changes no runtime or test
source. Owner retention of the current 30-second TTL is resolved for now; longer
leases are not authorized. Pi access and lint deferral follow the decisions above.
The Owner separately authorized a parallel F0 **proposal**, available in
[F0_DEVELOPMENT_IMPROVEMENT_PROPOSAL.md](F0_DEVELOPMENT_IMPROVEMENT_PROPOSAL.md).
This supersedes only the earlier restriction on preparing that proposal while E
is blocked. F0 implementation, Wave F and new runtime architecture remain outside E.

### Navigation: demonstrated causal chain

The 24 candidate hashes matched at entry. Ten observation artifacts and their
successful-node summaries matched the retained SHA-256 provenance. Derived data
is `/tmp/igor2-e-focused-causal-analysis.json`, bound to the ten source artifacts
and `/tmp/igor2-e-final-ttl-analysis.json`. This is offline evidence analysis, not
a new runtime pass. Lease ages below use display UTC only for observation;
actual acceptance/rejection is proved by the monotonic Core check return codes.
Nested preparation/handler timings are not added to their enclosing execution.

| Observable | Retained evidence | Interpretation |
|---|---|---|
| Lifetime left at first page | Median 26.109 s, range 25.727–26.945 | Construction/publication already consumed 3.055–4.273 s of the absolute lease; not a reset or sliding lease. |
| Next-page handler | Median 1.412 s | The small frozen-page handler alone does not explain the wait. |
| Next-page execution wrapper | Median 5.355 s | Includes execution-time preparation, handler and result/History work. |
| Next-page correlated request span | Median 13.594 s | Includes multiple canonical dispatch stages; about 7.855 s median lies outside the execution wrapper. Not an isolated transport time. |
| Initial inspection freshness check | 9 PASS, 1 expiry rejection | Trial 2 crossed expiry during its first check (lease age 29.681→30.776 s). |
| Gap from initial successful check to execution check | Median 7.952 s, range 6.127–9.888 | The selection can be fresh at preparation and stale before execution. |
| Execution inspection revalidation | 1 PASS, 8 expiry rejections | All eight rejected checks began after age 30; exactly one trial invoked the READ handler. |
| Detail outcome visible | Median lease age 38.688 s; minimum 31.185 | Even the one admitted READ completed visibly after inventory expiry, which the accepted contract permits. |
| Readiness/observation gap between first visibility and detail outcome | Median 3.648 s, range 2.930–5.408 | Residual after subtracting next/detail key intervals and two 2-s reading delays; not isolated harness overhead. |
| Back | Approximately 1.003 s in all ten trials | Local navigation, no new canonical READ; not evidence of another backend call. |

**Causal conclusion:** normal two-operation navigation in this observed fixture
spends the lease on canonical dispatch latency, readiness and reading. The fixed
30-second boundary then correctly rejects stale execution. There is a real
usability failure under these conditions, not a demonstrated authorization,
lease-renewal or wrong-row bug. Nine rejected READs are independent backend
evidence; a terminal-string assertion cannot manufacture those rejections.

Code explains the mechanism without attributing every second to a single helper:
`core/ai/core.sh::_ai_operator_invoke` performs inspection preparation before
`ai_execute_tool`. `core/ai/safety.sh` parses/adjudicates the request, prepares
the capability, creates History identity, classifies policy, records authority
and publishes events. `core/lib/capability.sh::igor_capability_execute` prepares
again and revalidates inspection immediately before the handler. Those fences
are intentional and must remain. Existing phase records do not time audit,
History, field extraction, privacy and event-payload construction individually,
so the exact expensive helper is still unverified. Repeated short Python
invocations visible in this call path are a profiling hypothesis, not a proven
optimization target or permission to cache authorization/secret material.

The navigation architecture is serial: next-page retrieval and inspection enter
the canonical backend; cached Back does not. The data does not justify a second
dispatcher, automatic refresh, delayed lease start or speculative prefetch.
It establishes a latency/lease mismatch at this workload, not that every
supported host or navigation sequence necessarily fails. The synthetic provider
has 51 rows, so the 1024-row construction profile is not a causal substitute.

### Harness contributions and smallest next correction

The harness deliberately reads for 2/2/1 seconds and waits for actual
`Backend READY` before sending more work. These waits model permitted input,
not a delay that may simply be deleted. `Session.wait_any` only checks terminal
text after new bytes; already-rendered state can therefore require another frame
or time out. The previously corrected expiry assertion proves this hazard, but
does not establish its share of the retained latency. A global immediate-text
shortcut could accept stale READY/row frames and weaken correlation.

The one-second Back interval is consistent with bare Escape disambiguation:
the fixture sends ESC, the TUI enables keypad mode and does not set ESCDELAY.
[ncurses documents this decoding wait](https://invisible-island.net/ncurses/man/curs_getch.3x.html).
This is a supported user-input cost, not proof of backend navigation latency;
its exact contribution is an inference until compared with the existing `b`
binding. Removing one second alone cannot repair eight execution-fence failures.
The frontend's 100-ms loop and fixture's 50-ms polling do not by themselves
explain 10–19-second request intervals. Wrapper logging and varying recorded
host load were not independently controlled, so published intervals are fixture/
host observations, not isolated-hardware performance claims.

The smallest useful next action is one 30-second-lease diagnostic sequence with
per-request key-send, wire/result, rendered-frame and READY timestamps, plus
durations around currently unmeasured audit/History, field extraction, privacy
and event-payload stages. Pair it with one identical uninstrumented sequence on
the same quiet host. Preserve 2/2/1 pacing, source data, lifecycle, negative
nonexecution assertions and absolute lease start. Measure ESC versus `b` in a
small separate input probe; do not replace the original acceptance sequence.

Only after a specific cost is demonstrated should a correction combine repeated
parsing of the same already-validated proposal within one invocation, using the
existing local tuple/mapfile pattern, or fix correlated frame observation. Keep
both preparation/execution checks, all History/approval transitions and fresh
privacy preparation. This is a candidate correction, not an implemented fix or
a claim that batching three field reads saves the roughly eight-second gap.
No production edit is justified by the present coarse timings alone.

A 30/45/60 comparison is a later conditional option, not the recommendation now.
If corrected observation and measured latency work still show an irreducible
mismatch, seek explicit authorization for isolated fixture TTL candidates, run
matched successful READ/paging/Back/refresh sequences and memory/expiry tests at
each duration, and retain failure outcomes. Rejected details omit successful
READ cost, so the old outcome ages cannot predict 45/60-second success. Such an
experiment has no authorization or budget in this plan.

### Memory: revised method and stop condition

The historical per-process records lack event/epoch membership and RSS-at-stop
series, so an exact simultaneous peak cannot be recovered from them offline.
Examples in the one-collection empty trace pair process VmHWM values of 4212
and 10368 KiB with wait4 lifetime values of 33984 KiB. Across exec, lifetime
statistics retain earlier usage; descendant accounting can further duplicate
contributors. [Linux resource-usage semantics](https://man7.org/linux/man-pages/man2/getrusage.2.html)
explain why those values must not be treated as simultaneous resident memory.
The old upper bounds remain valid only at their documented conservative scope;
subtracting different upper bounds is not a valid repair.

There is also a counter-accuracy qualification: Linux documents both
[`VmRSS` and `VmHWM` as inaccurate](https://man7.org/linux/man-pages/man5/proc_pid_status.5.html).
The historical values remain observations of those kernel counters, not rigorous
physical-RSS bounds without an accounting-error allowance. More accurate
[`smaps`/`smaps_rollup` snapshots](https://man7.org/linux/man-pages/man5/proc_pid_statm.5.html)
can cross-check residency, but snapshots alone still miss transients. M0 must
justify its counter/rounding error budget for the declared kernel or use a
stronger source and boundary coverage; passing known probes alone is insufficient.
Retained frontend VmHWM evidence remains at its recorded counter scope and does
not prove a more precise metric or Pi acceptance. No historical observation is
deleted and no accuracy tolerance is silently added to the ceilings.

Preferred instrument candidate: keep the bounded owned-child tracker, capture
per-process image/epoch memory **before** exec and exit destroy the old address
space, and maintain upper bounds from concurrently live epochs rather than
ancestor wait4 maxima. Record event membership, baseline, maximum, release,
diagnostic completeness and instrument overhead. Preserve a fallback unresolved
interval whenever an epoch cannot be captured; do not omit it or report a pass.
[ptrace syscall-entry/event semantics](https://man7.org/linux/man-pages/man2/ptrace.2.html)
permit investigation of this approach, but implementation/calibration and
overhead are not yet proven. Full syscall tracing may be too expensive; selective
owned-child boundaries are an option only after coverage/permission review.

Calibrate known touched allocations, allocation→exec→exit, parent/child overlap,
sequential children, failure cleanup and the existing late-fork/capacity proof.
Prove transient coverage and that parent accounting cannot duplicate a child's
old peak. Keep the 4096-record limit and explicit retirement metadata. Report a
mathematically supported interval for peak difference: PASS only when its upper
bound is within the existing ceiling; demonstrated violation only when its lower
bound exceeds that ceiling; otherwise UNVERIFIED. Calibration uncertainty must
be small enough to distinguish the canonical candidate from its ceiling.

**Stop before maximum workloads** if calibration loses a known transient,
miscounts concurrent processes, cannot supply a trustworthy bound, or tracing
itself makes required fresh operations impossible. Do not spend another allowance
running the same inconclusive upper-bound tests. Smaller phase traces may locate
allocation cost, but whole-backend proof must include all phases and real
concurrency/refresh overlap; disjoint per-session peaks cannot replace aggregate
observations. RSS is not PSS/USS/cgroup charge. Adopting another metric or accepting
inconclusive intervals would require an explicit D079 acceptance revision.

### Requested validation budget — DEFERRED — AWAITING OWNER APPROVAL

Entry allowance was **45.877 s**. It is reserved here for scoped documentation/
reference/policy validation, not a fresh paced or maximum memory workload. No
new budget or supervised session is launched by the model.

Request **two Owner-authorized 900-second validation tranches (1800 s total)**,
with the existing 240-second per-command ceiling unchanged. This is a planning
estimate, not a claim that instrumentation development or Pi work fits 30 minutes.
Owner disposition: **DEFERRED — AWAITING OWNER APPROVAL**; the plan below is
retained for review and later execution, not immediate dispatch.
Engineering time to build/review the calibrated instrument is separate; obtain
a bounded supervised session before that work. Only the Owner may grant/reset
the governor allowance. An unused reserve is not authorization for new work.

Resource plan for the existing x86 host: one serial measurement at a time, at
most four canonical backend sessions/eight snapshots (4 MiB serialized), and
the unchanged 4096-record tracker ceiling. Plan at least 1 GiB of free memory
headroom before aggregate execution: observed single-session absolute intervals
reach roughly 100–201 MiB, so four sessions plus the external instrument need
more than the 64-MiB **incremental** allowance. This is conservative test-host
planning, not a new runtime bound or measured aggregate/Pi claim. Retain bounded
summaries/peak witnesses instead of unbounded syscall logs, private fixture
directories and cleanup assertions. No live service source changes or swapping
away an acceptance failure. Pi resources must be planned from the actual target.

| Group | Planned allowance | Basis / useful exit evidence |
|---|---:|---|
| N: paired 30-second navigation diagnosis | 180 s | Two ≤90-s exact groups; retained sequences include ~11–18-s list/refresh and ~12–19-s detail intervals. Correlated phase/READY/frame attribution, with one uninstrumented control. |
| M0: instrument calibration and overhead | 180 s | Small discriminating probes; reuse the unchanged 63.761-s retirement proof rather than repeat it. Stop if precision/coverage is inadequate. |
| M1: three unresolved baseline/maximum pairs | 360 s | Prior complete group times 61.003 s, 101.140 s and 51.077 s; ~1.7× combined allowance for changed instrumentation. Preserve valid output/rejection/cleanup and 16-MiB intervals. |
| M2: canonical four-session/eight-call pair | 360 s | Old empty baseline hit the guard at 75.642 s before completion; budget two ≤180-s phases. Prove actual concurrent maximum workload and 64-MiB interval; do not infer from isolated sessions. |
| M3: READ details and refresh/replacement overlap | 360 s | Four ≤90-s baseline/workload phases as an initial estimate; existing end-to-end READ/list/refresh timings support investigation, not completed traced durations. Successful handler invocation, snapshot overlap/reservations and zero cleanup required. |
| R: only affected regressions and closing docs | 120 s | Prior 192-check affected run 89.934 s and document gates ~5–10 s. Preserve/reuse unaffected proof; no automatic broad sweep. |
| Reserve | 240 s | Concrete calibration/fixture corrections only, with affected rerun justification; stop if a complete required group cannot fit. |
| **Total** | **1800 s** | Serial measurement groups; no tracing mixed with untraced latency observations. |

Tranche 1: N/M0/M1 (720 s) plus at most 180 s of correction reserve.
Tranche 2, only if M0 succeeds: M2/M3/R (840 s) plus the remaining 60 s reserve.
Do not request tranche 2 merely to repeat calibration that failed its stop gate.
Prepare exact `--dry-run` selections and confirmed durations before dispatch.
Each phase must fit its assigned cap, at most 240 s. Splitting a pair requires
new **test-only** phase identities and retained raw artifacts bound to the same
source, fixture and environment; the paired assessment verifies both phases.
Baseline/workload construction remains fresh and canonical in each phase.

Keep the current equivalent empty-inventory workflow baseline for list cases.
For detail/refresh, specify the empty-session comparison and expected empty-case
nonexecution explicitly before fixture implementation: an empty collection cannot
provide valid row membership. The maximum case must execute real successful READ
and refresh; a denied READ is not detail memory proof. Do not silently switch to
a one-row or idle-only subtraction that changes the accepted reference. If the
existing empty-session meaning cannot be preserved, present that narrow benchmark
decision to the Owner before execution. Publish absolute baseline/workload peaks
as well as incremental intervals and all outcome/cleanup assertions.

Pi runs are a separate external gate and separate estimate after target details
are supplied; x86 timings cannot guarantee their budget. A provisioned target must
declare board/RAM, OS/kernel/libc/interpreter and tracing permission. Run the same
calibrated real workload and bounds there; emulate neither the hardware claim nor
the acceptance. The requested 1800 s does not authorize Pi access or longer TTLs.

### Finite blocker disposition

| Problem class | Current item | Smallest action that can change status |
|---|---|---|
| Demonstrated implementation-level usability failure | Nine actual READ expiry rejections; no fresh complete navigation in this fixture | Paired 30-s correlated profiling, then one demonstrated-cost correction with safety/History/privacy regressions. |
| Test/instrument limitation | Coarse stage timing, new-frame-only observation, probable ESC delay; loose memory intervals | Separate frame/READY and nested/exclusive timings; calibrate epoch bounds before maximum tests. Do not alter correct authorization to satisfy the fixture. |
| Corrected instrument defect, integration unverified | Cumulative records retired safely; corrected aggregate not executed | One budgeted canonical aggregate pair after calibration; retain instrument-only proof at its scope. |
| Missing evidence | Three decisive memory intervals; successful backend detail and refresh overlap; complete stage profile | M1/M3 and N, conditional on M0 and bounded groups. |
| External authorization | Pi target; new execution allowance; any future lease experiment | Owner-supplied target and explicit staged budget. TTL retention is already resolved; do not ask again for that choice. |
| Architectural performance constraint | Serial canonical requests under one absolute lease, with execution-time authority fencing | Improve demonstrated costs inside the existing path first. Reopen architecture/acceptance only if those measurements show the contract cannot meet its goal. |
| Accepted baseline debt | Four inherited History lint findings | Deferred by Owner; not an E correction or reason to run unrelated refactors. |

Recommendation: keep acceptance **BLOCKED**, with these finite exit actions.
If M0 cannot make RSS proof conclusive within its bounded allowance, report that
instrument outcome and stop maximum dispatch. The Owner may then commission a
different calibrated instrument or formally revise metric/scope; neither decision
is implied by this report. No threshold, acceptance class or incomplete proof is
converted to success. No commit or push.

## Deferral and resumption — 2026-10-14

The Owner deferred the proposed 1800-second allowance. Preserve the procedure,
classifications and all completed proof; no expensive test or acceptance revision
is undertaken. This changes scheduling only, not Increment E acceptance, the
30-second TTL, numeric targets or the blocked Pi gate. The governor ledger is
not renewed or restored from an archive.

Private workspace preservation is under
`.igor-governor/evidence/collection-increment-e-deferred-20261014/` (owner-only).
Its `index.json` maps original evidence/source paths to retained copies, with
SHA-256, size and expected hash where recorded. It includes the evidence ledger,
raw summaries/logs/reports/artifacts, candidate/procedure snapshots and current
scoped sources. Existing `/tmp` originals remain untouched; the extra copy avoids
depending solely on temporary-directory lifetime. This is ignored development
evidence, not an Igor runtime registry or a new execution authority.

On resumption, read the current finding matrix and bounded plan; inspect branch,
candidate and environment against the indexed provenance. Reuse completed proof
whose inputs remain equivalent, and schedule only missing or concretely
invalidated checks under the existing governor/fresh-security rules. Do not
repeat passing tests merely because work resumed. If temporary files disappeared,
use the archive mapping to recover evidence deliberately, verifying hashes;
never restore governor budget/attempt state to manufacture allowance. New tests
still require an Owner-granted allowance, and Pi still requires an authorized
target. No archive alone turns historical or incomplete evidence into a pass.

Recommendation for Owner review: first approve a small documentation-first F0
slice that clarifies task context, measurement meaning/baselines, calibration stop
rules and acceptance evidence using existing infrastructure. It can proceed
without changing runtime behavior or relying on completed E acceptance. Then
resume narrowly scoped 30-second navigation diagnosis and calibrated memory
verification, conditional on useful measurement quality, before broad workload
dispatch. F0 implementation is not authorized merely by this recommendation.

Other independently scoped work can proceed after checking dependencies; changes
to collection, dispatch, privacy or shared consumers can invalidate E proof and
increase resumption work. Do not begin dependent collection features on the
assumption that E or Pi performance is accepted. Postponement leaves responsiveness
and peak-memory risk unresolved; it is not a demonstrated corruption/security
defect or permission to advertise verified constrained-hardware operation.
