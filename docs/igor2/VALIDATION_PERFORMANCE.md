# Validation infrastructure performance

Status: Controlled benchmarks and scoped acceptance evidence recorded.

## Scope and reference

This is developer infrastructure work from post-PR #70 `igor2` at
`79e6f732ff9ae8223e293fd768a7c7bb2f01b778`. It changes no product authority,
roadmap feature, accepted baseline or timeout ceiling. The OpenRouter stash
and personal settings remain outside the task.

The historical reference is [run 37834523305](https://github.com/pedante/igor_core/actions/runs/37834523305)
at `56024205f3a711f112b81124f89d18312e8014f7`: **1000.946 seconds**, 129
affected groups, 1,814 PASS, six FAIL_BASELINE, four BASELINE_FIXED and zero new
regressions, timeouts, unavailable tools or runner errors. PR #70's merge
contains that validated tree. The decoded job log supplied per-group timings;
artifact metadata was accessible, but its download returned HTTP 403. No
claim relies on contents of the unavailable ZIP.

| Historical group | Seconds |
|---|---:|
| Local Learning | 151.033 |
| Local Learning integration | 30.395 |
| System administration | 84.489 |
| Operational History dispatch | 68.038 |
| System Configuration workflow | 56.042 |
| Automation Registry | 47.125 |
| These six groups combined | 437.122 |
| Changed-file ShellCheck | 8.557 |

These groups consume 43.7% of the historical wall time. Tool installation took
about 22 seconds before validation; changing caching alone cannot solve the
test execution bottleneck.

## Bottleneck evidence and choices

The runner executed files serially. It already isolated each native process
session and imposed file deadlines, but it discarded BATS durations and
recorded no pytest phase timings. It wrote its only summary after the last
file, so an interruption lost classified partial evidence.

System administration and History dispatch create private module/stub fixtures
and initialize the real loader per test. Configuration shell proofs copy Core
and System and exercise real initialization, dispatch and verification. These
subprocesses are part of the vertical-slice proof; pooling or replacing them
with mocks would reduce coverage. The interrupted preliminary administration
probe completed 16 of 38 planned cases, usually 7–17 seconds each; it was
stopped before History to avoid concurrent product-suite load during the full
benchmark. Its observed JSON parsing assertion was retained as failure
evidence, not counted as a passing run.

Five local micromeasurements on tmpfs found means of **0.0070 seconds** to copy
System plus Docker, **0.0368 seconds** to copy Core, and **0.0449 seconds** to
validate the System manifest (including a 0.101-second cold first call).
File copying is small compared with multi-second cases on this host. The
Automation fixture caches immutable manifest validation once per class and
deep-copies it for each test. Writable stores and module initialization remain
private and real. Its shell proofs now use an explicit synthetic Assist
configuration, private home/runtime and an empty secrets directory rather
than reading ignored personal configuration. This corrects test inputs while
preserving Guide/Assist and approval policy assertions.

No unnecessary polling/wait was found in the named administration setup.
Automation's one-second effect window and 50-ms readiness polling exercise
overlap exclusion; they remain intact. Local Learning performs real private
History/Investigation/review persistence and candidate derivation. Caching a
persisted corpus across those tests risks changing independent source identity,
immutability and recovery proofs; it is not introduced. No fsync, approval,
privilege, secret or filesystem check is removed.

The loader/configuration implementation still writes fixed `/tmp` diagnostic
files. Groups that can reach them stay in one serial lane. Only explicitly
reviewed groups whose state is private may overlap. Unknown groups default to
serial. Broad parallel execution is rejected because diagnostic collisions
would make failures unreliable; changing product storage is outside this slice.
Separate file subprocesses also prevent process-global import/env pollution.

Affected selection retains every existing domain and the unknown/shared-helper
fallback. Ten plan measurements averaged **0.0302 seconds**; the small
filesystem/domain scan is not the measured bottleneck.
A dependency database, narrower source coverage, automatic baseline updates,
passing-result caches, persistent resume and timing-driven schedules are
rejected or deferred: they add correctness contracts without demonstrated need.
Only the duplicate rendering invocation is removed; its canonical group still
exercises every rendering identity. A module-contract filesystem check now sorts
its `rg --files` listings before comparing membership. The original full run
failed that assertion once, while a direct diagnostic rerun passed with identical
before/after membership. Sorting removes traversal-order variance without
removing the source-marker, activation-policy or filesystem assertions.

## Implementation and diagnostic proof

The existing runner gains bounded workers, deterministic plan-index aggregation,
serial preflight, private process state, atomically checkpointed evidence,
periodic progress and coordinated SIGINT/SIGTERM cleanup. Pytest collection
manifests detect missing node evidence; valid rows survive a later truncated
report with an explicit ERROR. Native timing is separate from stable identities.
Slow group/test lists and run-wide child user/system CPU expose cost without
attributing overlapping CPU use to individual groups.

CI uses the same entry point and two workers. Python requirements pin the
historical pytest/Ruff versions; Python/npm downloads are cached. BATS installs
without sudo in a private tool prefix. Apt refresh/install is conditional on
missing ShellCheck/ripgrep. Cache hits never substitute for execution.

Required acceptance evidence:

- original and optimized runner on the same tracked product/test revision and
  controlled environment; identical unique required identities and outcomes;
- exact accepted/new failure and timeout comparison, including injected faults;
- worker order, crashes, unavailable tools, missing/truncated reports and
  incomplete collection fail closed;
- simultaneous fixtures cannot observe each other's mutable state;
- SIGINT/SIGTERM retain completed identities and pending inventory, return
  nonzero and clean descendants;
- full product regression plus focused runner and Automation fixture tests;
- local/CI compatible schema, selection, classifications and workflow parsing;
- final diff, lint, documentation references and scoped commit/PR review.

The existing reviewed baseline and `compare_results` remain byte-identical.
Interruption checkpoints are diagnostic evidence, not a resume authority. The
last checkpoint after SIGKILL remains unfinished; SIGKILL cannot run cleanup.

## Controlled measurements

The benchmark uses fresh `git archive` exports of `79e6f73` under `/tmp`,
excluding ignored configuration, credentials and state. The original harness
is retained in its export; the optimized harness points to an independently
fresh export of the same source/tests. A preliminary optimized attempt was
stopped after detecting untracked state left by the original run; its unfinished
checkpoint is retained but its time is excluded. All tracked export files were
verified byte-identical to the source archive. Both runs use
the same pytest 9.1.1 interpreter, BATS 1.13.0, scrubbed environment, private
HOME/TMPDIR/XDG and identical deadline values. The full plan includes canonical
legacy Bash/BATS and all Python files. Rendering executes twice originally and
once after optimization; compare unique identities, classifications and the
remaining plan rather than treating duplicate execution as extra coverage.

Local host: eight logical CPUs, Intel i7-1065G7, Python 3.14.7 and tmpfs `/tmp`.
Historical CI uses Ubuntu 24.04 and Python 3.11.17. Local and historical absolute
times are not interchangeable. Monotonic wall time, per-group time and
`RUSAGE_CHILDREN` user/system CPU are measured for each local run.

| Metric | Original, serial | Optimized, two workers |
|---|---:|---:|
| Wall time | 2900.139 s | 2523.572 s |
| Child user CPU | 2493.979 s | 2821.892 s |
| Child system CPU | 390.851 s | 414.170 s |
| Executed groups | 121 | 120 |
| Unique classified identities | 1816 | 1816 |

**Wall time falls 12.98%, saving 376.57 seconds (6.28 minutes).** Total child CPU
increases 12.18%. This is one controlled pair, not a statistical confidence
claim or a projection onto GitHub hardware. Overlap improves elapsed time while
individual groups become slower; two workers trade additional CPU for quicker
completion. `--jobs 1` remains the default. The conservative serial lane limits
further speedup; relaxing it without resolving shared diagnostics is rejected.

| Named group | Original seconds | Optimized seconds |
|---|---:|---:|
| Local Learning | 412.489 | 494.772 |
| Local Learning integration | 88.609 | 98.445 |
| System administration | 258.670 | 298.586 |
| Operational History dispatch | 222.732 | 254.578 |
| System Configuration workflow | 188.247 | 215.670 |
| Automation Registry | 145.637 | 156.180 |

The longest measured native tests after optimization are Local Learning source
review/status (99.774 s), procedure identity/pattern rereview (88.054 s),
Configuration same-path recovery (64.802 s), Automation one-time dispatch
(50.000 s), and Knowledge procedure round trip (48.926 s). These tests remain
in the suite with their original deadlines and assertions. The timing reports
make their cost visible rather than omitting them.

## Correctness evidence and limitations

The [machine-readable evidence](validation-performance-evidence.json) records
source/baseline hashes, every group duration, classifications and raw identity
differences. Both exports have identical tracked contents from the same revision.
The only removed group is the duplicate Python rendering invocation; its
canonical invocation retains every rendering node.

- **892 declared pytest nodes and 623 BATS identities match exactly.** Both
  runs classify 1,816 unique identities. Three passing Investigation subtest
  labels contain generated scope IDs and therefore differ byte-for-byte; the
  raw differences are retained, and passing subtest counts per declared parent
  match. No runtime identity or baseline comparison is normalized. All common
  identity classifications, all failure/timeout identities and all ten baseline
  outcomes match exactly.
- Both comparisons contain 1,802 PASS, six FAIL_BASELINE, four BASELINE_FIXED,
  two ENV_SKIP, two FAIL_NEW, zero timeouts, unavailable tools or unexercised
  baseline entries. **The archive benchmarks are not green release runs.**
  The two FAIL_NEW identities are reproduced by both harnesses: the tracked
  package proof requires absent Git metadata, and the unsorted filesystem
  listing is intermittent. The active-checkout recovery run exercises the
  complete package and BATS contract files: 124 PASS, one accepted baseline
  failure, zero new failures/skips/errors. Git metadata is present there and
  the sorted membership assertion passes. Neither failure is added to the
  baseline or suppressed in the benchmark.
- The optimized native run exposed a timing-plus-skip parser bug: two permitted
  skips initially became ERROR because milliseconds remained in their identity.
  The adapter was corrected and its combined timing/skip/timeout test passes.
  All completed native reports were reparsed with the final adapter and the
  unchanged `compare_results` and skip permissions. The original summary is
  retained separately; corrected counts match the original runner exactly.
  Execution, wall/CPU measurements and raw logs are unchanged by this diagnostic
  reparse. This correction requires report tests, not re-execution of product
  effects.
- The first affected check reports **123 PASS**, no failures/skips/errors.
  Final runner/report/domain/baseline self-tests report **68 PASS plus two signal subtests**.
  They prove reversed completion order, serial preflight, exact accepted/new
  failure and timeout handling in serial/parallel schedules, crash/missing-tool
  failure, incomplete collection, truncated-report evidence, simultaneous
  environment/cache/data isolation, and SIGINT/SIGTERM cleanup/checkpoints.
- Safety, approval, privilege, secret and filesystem suites remain in the full
  plan. Approved BATS overlap is limited to reviewed private fixtures. Real
  Automation authorization/mode/dispatch assertions pass under synthetic
  configuration; poisoning ambient settings does not change the fixture mode.
  Its active-checkout file takes 140.3 seconds, including the new isolation case;
  this separate focused timing is not substituted into the controlled pair.
- CI inspection exposed a checkout-local checkpoint being included in its own
  changed-file query and triggering broad fallback. A minimal ordering correction
  captures changes before the first checkpoint write. Its regression fixture
  proves the real documentation change still selects documentation tests and
  excludes an unrelated test. No path exclusion or dependency-map change is added.
  The controlled benchmark supplies a fixed empty changed-file list, so this
  selection correction changes neither benchmark execution nor its measurements.
- CI and local commands use the same runner, adapters, baseline, domains and
  result schema. Workflow YAML and embedded Bash parse. Changed Python lint,
  BATS CI-flag ShellCheck/count checks, compilation, JSON and documentation
  references pass. Repository-wide Ruff still reports **136 pre-existing
  diagnostics versus 137 on the base**, with zero introduced diagnostics;
  one unused suppression in the touched fixture is removed. Unrelated lint
  debt remains visible rather than being repaired or waived.

The contract and regression evidence is the runner fault/isolation suite plus
the same-revision full native comparison and active-checkout fixture recovery.
The native CLI/dispatch proofs remain real vertical slices; summary inventory,
raw paths, timings and provenance provide inspection evidence. Interruption
and malformed-report tests prove diagnostic recovery. No product persistence
layout or migration changes, so persistent product migration proof is not
applicable. This closes developer infrastructure evidence, not a later Igor 2
roadmap wave. Partial artifacts are never treated as a passing gate.
