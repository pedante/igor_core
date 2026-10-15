# Operator Interfaces: CLI and TUI

Status: **Step 20 partially implemented; complete operator acceptance remains open**.

The current source includes structured CLI normalization (`capability run`
among other commands), the backend-driven explorer and an interactive default
TUI selection path. These are inspected foundations, not a claim that all
Step 20 application/workflow acceptance gates have passed. Follow
[Development Policy / D078](DEVELOPMENT_POLICY.md); internal pre-release aliases
may retire with complete consumer migration. The
[collection RFC](COLLECTION_OPERATOR_RFC.md) is the proposed Step 18/20 extension
for generic typed results and identical typed/explorer invocation, in DISCOVERY.

Igor should expose one backend operating model through multiple frontends. The
CLI and TUI must not become separate command/permission systems.

## Shared rule

```text
TUI ----------\
CLI -----------+--> backend/session + owning services
automation ----+        -> capability policy/approval
future API ----/        -> privilege/execution/verification
                        -> History
```

A frontend may select, render and submit typed intent. It cannot invent facts,
bindings, capabilities, approvals, privilege or success.

## Step 20A — First-class CLI

### Integrated System operator package — 2026-10-15

- **Owner acceptance:** **ACCEPTED, 2026-10-15**, for the bounded Step 20A/B System
  operator package, including the verified History navigation correction. Owner
  authorized one local scoped acceptance commit; no push or next implementation.
  Step 20 remains **PARTIAL**; broader scenarios and 20C remain open. Collection
  Increment E remains deferred/unaccepted; its evidence and authorization are
  unchanged.
- **Final minor correction:** Owner accepted the independent review's
  APPROVE WITH MINOR CORRECTIONS and authorized only History selection visibility,
  one overflowing-viewport regression, affected validation and focused review.
  The correction uses the existing allowance, no renewal. Left/Right now counts
  the rendered, wrapped prefix before the selected record; selection, identities,
  Enter and rendering contracts are unchanged. The new 20-record regression
  crosses the viewport in both directions, checks every selected identity remains
  visible and verifies Enter at both clamped endpoints. Focused navigation and
  operator regressions: 31 PASS, zero new failures/timeouts; Ruff retains only the
  inherited FURB162. Evidence: `history-navigation/` within the package directory.
  Focused independent review returned **APPROVE** with no remaining defects;
  unchanged package evidence and E deferral are preserved.
- **Authority/scope:** Owner approved continuous CLI completion, bounded TUI
  integration and one final acceptance/review package. Reuse D070/D078 and the
  shared backend rule; no new executor, ownership/storage contract, 20C cutover,
  Collection E verification or push. Implementation was single agent; Owner later
  explicitly authorized one independent read-only correction reviewer and the
  final local acceptance commit.
- **Candidate:** `igor2`, HEAD `ce97fbb` plus the existing uncommitted Step 20A
  candidate. Its hash-bound evidence is preserved separately; prior independent
  acceptance is not inferred. Package entry/source hashes retained locally.
- **Phase:** RELEASE_FREEZE for the Owner-authorized local acceptance checkpoint.
  Functional/security evidence, affected navigation regression, independent review
  and Owner acceptance are complete. Commit the scoped checkpoint, then stop;
  no further development or push is authorized.
- **Acceptance/proof:** readable and JSON CLI result/exit behavior; inspect
  System/module/capability availability in TUI; select existing System READ;
  display canonical execution/output/verification and open its History operation.
  Both interfaces read the same owning History service. Disabled/stale/invalid
  requests execute no handler; recovery follows current restart semantics.
  Privacy, approval and privilege regressions stay fresh. Contract/regression,
  real System CLI/PTy vertical slice and History/registry inspection are required.
  No persistent format migration; recovery proves re-enable/restart and navigation.
- **Validation:** 900 s cumulative, 240 s maximum per command; 200/450/250 s
  focused/final/reserve allocations are ceilings inside that total. Serial private
  fixtures, actual procfs READ, no network/provider API, sudo effect or Pi workload.
  Updated activation plan: `/tmp/igor20-package-activation-plan-ready/summary.json`;
  final integrated selection: `/tmp/igor20-package-final-plan/summary.json`, including
  the real integration fixture. Owner activated the 900-s allowance; no renewal,
  governor/ledger/rule modification or security evidence cache reuse. The later
  independent reviewer reused the 31 passing tests without running validation.
- **Delivered behavior:** public CLI READs expose readable or redacted canonical
  JSON results with outcome-based exit status and History identity. The existing
  TUI explorer/control panel connects module availability, System READ selection,
  result states, recent History and operation details. A bounded section list
  preserves content space at 24 lines. Canonical scalar result/refusal events and
  a TUI-only Quit guard complete the path; classic wrap-up is unchanged.
- **Integrated evidence:** `.igor-governor/evidence/step20-system-20261015/`
  retains raw reports, native terminal bytes/events, History records, candidate
  snapshots/diff and hashes. The actual curses/outer+inner PTYs and
  `bash igor.sh --ai-tui-backend` execute `system.host.summary` through the same
  dispatcher as CLI; distinct successful operations share the authoritative
  History service and System provider/kernel/architecture. The native test also
  proves module inspection, result/verification display, History list/detail/back,
  unavailable request refusal and clean Quit. The final CLI regressions separately
  prove memory READ verification, exact JSON/default transmission, redaction,
  handler-failure exit status and disable/re-enable with no disabled handler/source.
- **Validation ledger:** `integration` is the approved 22-group pass: 277 PASS,
  four new failures, two baseline failures and one baseline fixed identity.
  `corrected` passed the three failing CLI cases, backend result/refusal/redaction,
  25 approval and 5 privilege cases, unchanged F0.2 stale-owner/recovery, ShellCheck
  and syntax; only native Quit timed out. `exit-corrected` passes the complete
  real curses/backend workflow (27.468 s) and classic start/fast exit regression,
  plus closing shell checks; zero new failures/timeouts. Initial scrubbing, module
  state, capability runtime, History and generic UI passes remain applicable to
  unchanged paths. The later exit guard changes no admission/authority behavior.
- **Defects corrected:** the dispatcher-local operation ID cannot be read by its
  caller. The shared result out-parameter now contains its committed canonical
  receipt rather than handler diagnostics; CLI/TUI consume that receipt. Expected
  CLI refusal statuses are handled without generic Bash error-trap output. Native
  Quit previously emitted session_finished then blocked on invisible classic WIP
  prompts; it now returns after the existing saves/state/cleanup, retaining WIP.
- **Baseline dispositions:** inherited Ruff FURB162 is the unchanged timestamp
  parser in HEAD; no new diagnostic. The pre-existing typed-operator activity test
  expects an exact argument-free line, while the current correct operator activity
  includes arguments. Its no-conversation invariant is independently covered by
  backend/UI tests; no production behavior, assertion or baseline list was weakened.
  Both raw baseline failures remain recorded. The previously baselined operator
  projection test now passes. No other unresolved acceptance failure remains.
- **Timing/budget:** preparation before activation was about 13 minutes; validation
  and correction-session elapsed time excludes the intervening Owner wait. Exact
  report durations, charged allowance and final remaining seconds are in retained
  `index.json`. Only affected failed checks/neighbors were rerun; no full-suite run.
- **Governor assessment:** cumulative stage authorization already works. Keep
  conservative invalidation and fresh security checks; use the same installed
  pytest interpreter for runner and tests, bounded selections and one final gate.
  No repeated broad suites or new process framework. Record development elapsed,
  governed time/budget, failures, candidate hashes and evidence at handoff.
- **Deferred E impact:** old evidence stays immutable, not requalified for this
  candidate. Changes to `core/ai/core.sh`, `core/ai/tui.py`, `core/ai/safety.sh`,
  `igor.sh` and `core/lib/operator_cli.sh` invalidate affected future frontend,
  transport/result and resource proof. Collection descriptors, snapshots/bindings,
  TTL and memory criteria are unchanged. No E workload/resource/Pi verification
  ran; E remains deferred/unaccepted. The ANSI test helper was reused without
  executing or altering its collection workload.
- **Review/handoff:** integrated independent review returned APPROVE WITH MINOR
  CORRECTIONS; Owner accepted its conclusions. Its one low-severity History
  viewport finding is corrected and verified above. The separately Owner-authorized
  reviewer `/root/history_correction_review` returned **APPROVE** after read-only
  inspection of wrapped scrolling/final draw clamping, unchanged selection/Enter
  contracts, all-record visibility and endpoint/Enter regression coverage. The
  reviewer verified all 15 candidate hashes and 101 retained artifacts and reused
  the 31 passing tests; no tests, writes or further delegation. Full verdict and
  Owner acceptance are retained under `acceptance/` in the evidence directory;
  `index.json` preserves prior snapshots and records the final local commit.
  All reviewed hashes matched before acceptance-only documentation edits. Owner
  formally accepted the bounded package and authorized this local checkpoint.
  Step 20A beyond this System package and Steps 20B/C remain partial/open. No next
  increment starts; no push.

### Public CLI READ acceptance record — 2026-10-15

- **Objective/authority:** Owner authorized one existing READ capability through
  `bash igor.sh capability run`, under D078 and the shared dispatcher contract
  below. F0 is closed; its accepted workflow applies normally. No CLI redesign,
  ownership refactor, Collection Increment E stabilization, commit or push.
- **Candidate/scope:** `igor2`, task base `1feddd10e913c2359de193f4e6321b3ae7cfaf0c`.
  External local checkpoint `ce97fbbf5a5f934f4ffc80ab536b56136f5fc154` appeared
  during work and contains initial Step 20A tests/docs; preserved, not created by
  this implementation session. Remaining changes are uncommitted; no E runtime.
  Affected paths: `core/lib/operator_cli.sh`, `igor.sh`, CLI regressions and
  this task/status record. No persisted format or capability contract migration.
- **Phase:** RELEASE_FREEZE for independent review. Implementation and required
  runtime evidence are complete; only closing documentation/diff inspection remains.
- **Requirements/proof:** enabled public READ succeeds; disabled owner refuses
  without execution; re-enable restores execution; invalid inputs refuse;
  omitted/explicit `{}` and populated JSON arrive intact; History identifies
  `cli` and `operator`; noninteractive execution avoids startup UI while keeping
  security/module/approval/authentication initialization. Existing F0.2 regression
  supplies stale-proposal and ownership coverage on this baseline. Existing CLI
  frontend tests plus approval/privilege regressions protect interactive policy.
  Contract/regression proof uses the public CLI fixture and canonical dispatcher;
  the real vertical slice executes existing `system.host.memory.refresh`, reads
  `/proc/meminfo` and verifies the observation with private fixture storage.
  Inspection uses History and owner registry. Migration is inapplicable
  (no format change); recovery is fresh-process disable/re-enable.
- **Budget plan:** single agent, serial temporary fixtures, no network, live service,
  Pi or privileged operation. Prior F0.2 lifecycle: 24.497 s; preflight: about 6 s.
  Estimate 150 s including CLI reproduction/final pass and policy neighbors,
  Owner activated 450 s from their terminal, with 120 s command cap. The initial
  system-Python run could not execute pytest; the installed
  `surlife/.venv/bin/python` interpreter supplied pytest without installing anything.
  Corrections consumed the planned reserve; exact closing allowance is retained
  in `.igor-governor/evidence/step20a-20261015/index.json`. No renewal or E allowance.
- **Implementation:** separate empty-input default assignments replace ambiguous
  brace expansions in both CLI paths. Capability startup uses the existing saved-FD
  quiet-bootstrap pattern and skips session/feature/layout/pause UI. Security,
  module config/loading, scrub setup and `IGOR_HISTORY_INTERFACE=cli ai_execute_tool`
  remain in the existing operational path; no second executor or authority changes.
- **Evidence ledger:** raw summaries/logs and source snapshots with hashes are
  retained under `.igor-governor/evidence/step20a-20261015/`.
  `reproduction-pytest` demonstrates `{}` → `{}}` and attempted tmux startup.
  `entry-arguments` separately demonstrates JSON Extra data in `igor.sh`.
  `focused` passed 25 approval tests, 5 privilege tests and the unchanged F0.2
  lifecycle (20.324 s); these shared-code paths were not changed afterward.
  `cli-corrected` passed JSON normalization, invalid-input and noninteractive CHANGE
  refusal, real System READ/verification/CLI History and classic startup checks;
  its remaining failure was the test's incorrect History provider field.
  `history-corrected` passed the corrected public lifecycle (41.867 s), including
  exact handler inputs, enabled/disabled/re-enabled execution, no disabled source,
  provider ownership and four successful `cli`/`operator` History records.
  Final affected Python lint, ShellCheck and Bash syntax passed. No successful
  runtime proof was rerun solely to produce an all-green aggregate report.
- **Failure dispositions:** literal quotes in the first default fix were corrected
  with separate assignments. Fixture argv/stdin and History-field assumptions
  were corrected to the existing contracts, without changing backend behavior.
  Tool absence and intermediate failures remain retained, not reported as passes.
- **Review:** author inspected connected paths, final scope and evidence;
  independent review is pending. No unresolved runtime failure in this READ slice.
  No full suite, Pi/resource gate or complete interactive application workflow claim.
- **Handoff:** review this bounded READ slice against the retained evidence; no
  new development, Step 20A commit or push without separate authorization.
  Step 20A as a whole and 20B/C remain open; Increment E remains deferred/unaccepted.

The current headless inspection flags remain migration inputs. Igor 2 should
also offer one coherent user-facing CLI.

Target interaction shapes include:

```bash
igor "check why Nextcloud is slow"
igor ask "show me my Samba shares"

igor modules list
igor discover nextcloud
igor deployments list
igor deployments inspect <id>
igor capability inspect docker.install
igor config get system.memory.warning_threshold_mib

igor --json deployments list
```

The current CLI already supports structured `capability run` through the
existing dispatcher. Additional command spelling is bounded implementation
work; the shared contract is:

- natural-language one-shot use enters the normal Igor conversation/backend;
- structured commands address the same canonical backend objects;
- machine-readable output is versioned/typed enough for scripting;
- inspection remains read-only unless a canonical mutation is explicitly
  requested;
- interactive CLI may present the same approval and PTY authentication flow;
- non-interactive CLI never answers approval/authentication prompts on the
  user's behalf;
- when authorization is required but unavailable, return a clear typed/nonzero
  result such as approval required rather than silently changing policy;
- secrets stay redacted under the same projection rules;
- no CLI-only shell dispatcher or alternate privilege path exists.

CLI/headless operation remains available after the TUI becomes default.

## Step 20B — TUI completion

The full-screen TUI already has the interaction foundation. Completion means
turning backend contracts into a coherent operator experience, not merely
changing the default launcher.

The normal session should visually distinguish at least:

- user input;
- Igor conversational output;
- proposed/executing capability activity;
- command/tool output;
- success/verification results;
- warnings/errors/unknown state;
- pending question/choice;
- approval/privilege prompts.

Color/style may help, but meaning must not depend on color alone.

Generated backend-driven views should cover mature surfaces such as:

- System/current facts and health;
- Modules and availability;
- Discovery/recognition candidates and ambiguity;
- Deployments/relationships/responsibility;
- Configuration and source/desired/applied/observed distinctions;
- Capabilities and proposed effects;
- Operational History;
- Investigations;
- waiting/resumable work when implemented;
- AI/provider role state where useful.

### Proposal and approval review

Before a meaningful CHANGE/DESTROY, the UI should be able to present the
backend's frozen target/effects, current/requested value where applicable,
provider, privilege need, verification and recovery limitations.

Presentation does not replace canonical approval. DESTROY keeps its exact
confirmation rule.

### Configuration UX

Typed schema controls may edit proposals/staged values, show validation and
source/provenance, and submit through Configuration Service/canonical
capabilities. The TUI does not parse arbitrary module files or become the
configuration authority.

### Generated module/domain surfaces

Modules declare contracts and semantic metadata. The TUI groups/renders them
through shared projections. Modules do not ship a second custom frontend or
menu authority.

### Empty/error/refresh behavior

A surface must distinguish:

- genuinely empty;
- unavailable provider;
- failed refresh/projection;
- stale data;
- permission/approval required.

No indefinite blank panel should masquerade as success.

## Step 20C — Default cutover

Only after representative system/module/application workflows are usable through
shared backend contracts should `./igor.sh` launch the full-screen TUI by
default.

Preserve CLI/headless scripting, recovery and test paths. Keep `--ai-tui` as a
migration alias until removal is proven safe.

## Discovery interaction

Both CLI and TUI consume the same recognition candidate contract:

```text
find Nextcloud
  -> zero/one/many candidates
  -> inspect exact evidence
  -> select
  -> frozen adoption proposal
```

A user's "this one" answer selects a candidate; it is not proof or authority.

### A3 bounded recognition view (candidate)

A3's `recognition` CLI only projects a separately supplied A1 result; it
does not query the host. Examples:

```bash
# JSON produced by a trusted, reviewed recognition caller:
cat candidate.json | bash igor.sh --json recognition view
cat candidate.json | bash igor.sh recognition view
bash igor.sh --json recognition status  # unavailable until provider integration
```

The control panel's Recognition inspector consumes the same read-only model
and returns `unavailable` until A2 active-provider binding is implemented.
Nothing in this view selects a deployment or submits a proposal. A future
domain-discovery CLI and a live panel require separately verified active
module/provider eligibility and exact target inspection, without accepting
candidate data as authorization. This partial A3 view is not Step 20 CLI/TUI
completion.

## Proof gate

Before Step 20 completion, prove:

1. CLI and TUI invoke the same canonical capability without semantic drift;
2. a noninteractive CLI refuses/returns approval-required rather than bypassing
   policy;
3. discovery candidates and ambiguous selection render consistently;
4. configuration proposal/apply/readback distinctions are visible;
5. approval/privilege/result states are distinguishable from conversation;
6. History/Investigation/Deployment inspection uses owning-service records;
7. frontend restart cannot reinterpret stale selection as authority;
8. headless/JSON paths remain usable when TUI is default.
