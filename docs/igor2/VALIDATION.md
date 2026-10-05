# Developer validation

The validation harness is test infrastructure. It does not change Igor runtime
policy, state, capabilities or roadmap boundaries. It reuses Bash, BATS and
pytest rather than replacing their test frameworks.

Use this workflow:

```text
implementation
    ↓
focused
    ↓
affected
    ↓
stabilization
    ↓
full ONCE
    ↓
release freeze
```

## Modes and local comparison

```bash
tests/validate.sh focused --base igor2 --test tests/test_capability_runtime.py
tests/validate.sh affected --base igor2
tests/validate.sh full --base igor2
```

Choose a local comparison ref appropriate to the branch. `--base` defaults to
`igor2`; on `igor2` itself, supply the pre-task commit to include committed task
changes. Selection unions changes since `BASE...HEAD` with staged, unstaged and
untracked files. It requires neither network access nor GitHub. Renames are
represented as deleted/added paths. Deleted paths still select domains but
cannot be linted. `--changed-file PATH` adds simulated changes for mapping
proofs; `--dry-run` prints the plan without running tests.

`focused` checks changed Python compilation, JSON parsing and local inline
Markdown file links; runs Ruff on changed Python and CI-flag ShellCheck and
syntax checks on changed shell/BATS; validates changed module contracts with
the existing validator; and runs changed tests, conventional
`tests/test_<python-module>.py` matches and explicit `--test` targets. Python
node identities can be supplied; BATS targets are files. Supply feature tests
when their names cannot be inferred.

`affected` adds the explicit subsystem mapping in
[validation_domains.py](../../tests/validation_domains.py). Tests changing
select themselves; harness/CI changes select harness tests; documentation alone
selects structural checks. Shared test helpers or unknown implementation paths
select all discovered tests as a safe fallback. This can be expensive: inspect
`--dry-run` when a path is unfamiliar. This fallback still does not call `full`.

The root `igor.sh` entrypoint is treated specially because most feature work
only adds a thin CLI/router branch there. A standalone `igor.sh` change remains
broad and selects all tests. When the same change set also contains a recognized
implementation domain, affected selection adds a small direct-entrypoint
regression set plus that domain instead of allowing the facade path alone to
escalate the run to every repository test. Unknown implementation files still
retain the broad fallback.

| Changed domain | Broader regression coverage |
|---|---|
| Root entrypoint/router | Root CLI inspection/startup plus non-TTY TUI fallback; standalone `igor.sh` changes still select all |
| Capability/package/safety/approval/privilege | Contracts, resolution/dispatch, admission, safety, privilege, History and Docker/System composition |
| Module API/loader/modules | Module contracts, loading, activation, composition and inspection |
| History | Python History/deployment History and canonical event/History BATS |
| Configuration/secrets | Configuration workflow, secret references and configuration BATS |
| TUI/frontend/operator backend | Frontend, rendering, backend projections, PTY and privilege tests |
| Deployment | Deployment registry, attachment, prerequisites, inspection and History |
| Events/automation/context/investigations/system | Explicit corresponding Python and BATS groups |

Paths can match several domains; selected test files are deduplicated. D064-like
contract/runtime/package/safety/Docker/System changes include capability,
module, History and system slices without automatically adding unrelated TUI
or legacy tests. The mapping is a small reviewed list, not a dependency graph.

`full` is the explicit expensive release/integration gate. It preserves the
existing [run_all.sh](../../tests/run_all.sh) canonical legacy Bash, rendering,
Core BATS, module BATS and integration BATS groups, and adds **every**
`tests/**/test_*.py` file, including nested Python suites. Rendering therefore
also appears in complete Python discovery; counts deduplicate identities.
Missing/empty canonical directories fail closed. Focused/affected never
schedule full automatically. Run full once after stabilization; rerun only
when a concrete correction makes release evidence ambiguous. This is not a
promise that existing product suites pass.

## Tools, bounds and evidence

Install Python with pytest 9.x (native subtest reports), Ruff, ShellCheck and
BATS 1.13.0. Tool executables can be selected with `--python`, `--ruff`,
`--shellcheck` and `--bats`; `IGOR_VALIDATE_PYTHON` selects the launcher Python.
Missing required tooling is `TOOL_UNAVAILABLE` and nonzero, never a passing
skip. Tests whose fixtures mock Docker/systemd continue to run regardless of
host availability.

Each test file runs in its own process session, with output written directly
to a log. Default outer bounds are 600 seconds per file and 1200 seconds for
the System configuration and administration vertical slices (`--group-timeout`, `--slow-timeout`).
Those process-group bounds are the default timeout authority for BATS as well as
Python. BATS' native `BATS_TEST_TIMEOUT` watchdog is **disabled by default**;
`--bats-timeout N` is an explicit diagnostic opt-in. This avoids the confirmed
BATS 1.13.0 fast-failure watchdog defect described in
[bats-core #1206](https://github.com/bats-core/bats-core/issues/1206), where an
assertion can finish immediately while the runner remains alive until the native
watchdog deadline. The outer bound still fails closed and preserves the raw log.
Python outer timeout ends the file and moves to the next file; the active
reported node receives the timeout, not tests that never started. Passing subtests with nonliteral parameters
(such as NaN) are counted under their declared parent node; a failing subtest
without representable parameters remains a fail-closed error. Typed test-owned `TimeoutExpired`/`TimeoutError`
exceptions also retain their node/subtest identity. No arbitrary sleeps are
used to make timing failures pass.

After exit or timeout, the harness terminates the process group, then kills
remaining members. Raw output survives cleanup. Children that deliberately
create a new session are outside this group boundary; tests must own such
children. Outer timeout before a stable node is available remains a group
identity, which cannot silently match a test baseline.

By default evidence lives in a new `/tmp/igor-validation-*` directory. Use
`--output-dir NEW_DIRECTORY` to choose its location; an existing directory is
rejected to prevent evidence overwrite. Each group has a raw `.log`; pytest
also has a JSONL event sidecar. `summary.json` schema version 2 includes mode,
comparison ref, changed paths/domains, raw groups with elapsed time/exit code/log
references, classified test results, counts, unexercised baseline entries and
exit code. Counts combine unique test identities and structural/tool groups,
not just test cases. Raw group failures remain visible even if accepted by the
baseline. Human output shows classifications, identities and evidence paths.

### BATS watchdog economics

BATS 1.13.0 can emit an assertion failure immediately but leave its native
`BATS_TEST_TIMEOUT` watchdog alive until the configured deadline. Igor
reproduced this behavior locally, and bats-core tracks the same defect as
[#1206](https://github.com/bats-core/bats-core/issues/1206). Upstream's published
workaround is to avoid the native watchdog and bound the suite/process instead.

Igor therefore leaves `BATS_TEST_TIMEOUT` unset by default and relies on the
existing process-session outer timeout. This removes the pathological
approximately-180-second wait after fast assertions without treating the
failure as a pass or truncating TAP finalization. Targeted timeout diagnostics
can still opt into the native watchdog with `--bats-timeout N`. No BATS source,
product fixture, reviewed baseline or result classification is rewritten.

### Step 16B validation-runtime debt

The Step 16B affected run on 2026-10-05 took **4,227.582 seconds (70.5 minutes)**:
1,491 passing test/check identities, seven reviewed baseline failures, 12
unmatched failures, two unmatched TUI palette timeouts and two permitted skips.
The existing unknown-path fallback for `igor.sh` selected all tests even though
its change was a thin headless Local Learning entry point. Repeated BATS
failure cleanup and two 600-second palette group deadlines made that gate
disproportionate to the bounded implementation. The full gate was started once,
then stopped on explicit Project Owner instruction; it has only partial logs,
not a completed release result.

This is infrastructure/test-suite debt: broad entry-point selection, failed
BATS watchdog cleanup, and historical unaccepted palette hangs need a separate
bounded investigation. Step 16B changes no timeout, accepted baseline, unrelated
test expectation or fallback mapping to resolve it. Completed focused/affected
and real vertical-slice evidence supports review of the bounded change; the
repository-wide gate remains non-green. See [STATUS.md](STATUS.md) for the
failure attribution and Owner-directed finalization boundary.

## Reviewed baseline and environmental permissions

[validation_baseline.json](../../tests/validation_baseline.json) is reviewed
repository state and is **never automatically rewritten by validation**.
Schema version 1 requires `schema_version`, the full `source_commit` SHA and
`entries`. Each entry has `suite` (`pytest`, `bats`, `group`), stable `identity`,
`classification` (`FAIL` or `TIMEOUT`), concise `reason` and optional
`reference`. Logs, line numbers, PIDs, timings and transient error text do not
identify failures. Python node/subtest identity, BATS file plus literal test
name, or a permitted validation tool/group identity does.

The accepted baseline is intentionally incomplete. Historical STATUS/D064
reports are candidate evidence only. Every accepted failure/timeout must be
reproduced on unchanged `525cc76` using the smallest targeted invocation;
timing instability requires repeatable evidence. The
[reproduction record](../../tests/validation_baseline_evidence.md) records the
reviewed ten entries: eight assertions and two startup subtest timeouts.
Unaccepted historical conditions remain new if they appear again.

| Classification | Meaning / exit effect |
|---|---|
| `PASS` | Observed pass |
| `FAIL_BASELINE`, `TIMEOUT_BASELINE` | Exact identity and outcome match reviewed metadata; visible, nonblocking |
| `FAIL_NEW`, `TIMEOUT_NEW` | No exact reviewed match, or failure/timeout kind changed; nonzero |
| `BASELINE_FIXED` | Exercised baseline identity now passes; prominently reported, nonblocking; entry remains |
| `ENV_SKIP` | Exact test identity and skip reason explicitly permitted by its existing contract; nonblocking |
| `TOOL_UNAVAILABLE` | Required validation executable/dependency unavailable; nonzero |
| `ERROR` | Internal/report/metadata error or unpermitted skip; nonzero |

An entry not exercised in the selected scope is listed as unexercised, never
fixed. Malformed, duplicate, contradictory, unknown schema/classification or
unknown declared identities fail closed before tests run. A failure becoming
a timeout is not accepted as the same outcome. Unknown skip reasons are errors.

[validation_environment.py](../../tests/validation_environment.py) permits
only exact existing GPG and hostname/LAN guard reasons for named tests. There
is no generic missing Docker, socket, systemd, GPG or network preflight that
turns correctness tests into skips. Add an environmental permission only after
reviewing an explicit fixture/test contract permitting that absence.

To deliberately update a baseline: identify the exact new outcome, reproduce
it against the unchanged source using a targeted bounded command, retain raw
logs separately, and prepare a concise evidence record and manifest diff for
Project Owner review. Approval is required before acceptance. Do not bless
new failures from the current development run. A disappeared entry remains
until a separate reviewed metadata change removes it.

## CI and limitations

[CI](../../.github/workflows/ci.yml) covers PRs targeting `master`, `main` and
`igor2`, and pushes to those branches. Ordinary events run the shared
`affected` entry point. PR selection uses the base SHA; pushes use the previous
SHA. Checkout fetches local history. The affected harness already runs Ruff and
ShellCheck on every changed Python/shell/BATS file, so ordinary PRs do not also
pay for duplicate whole-repository lint scans. Repository-wide Ruff and
ShellCheck remain available as explicit `workflow_dispatch` + `full` audit
jobs; their existing backlog/policy is unchanged and is not silently accepted.
Manual `workflow_dispatch` also selects focused/affected/full validation and a
comparison ref; full is an explicit operator choice. Logs and JSON are uploaded
even on failure. A first-ever branch push with no valid prior SHA needs a manual
comparison ref.

Local Markdown validation checks inline file links, not anchors, external URLs
or reference-style links. YAML workflow parsing/review is separate. Per-file
outer bounds are not a total-session duration guarantee; the CI job has a
180-minute overall ceiling. There is no test dependency database, automatic
baseline generation or runtime persistence service.
