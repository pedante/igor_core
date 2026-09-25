# Igor Codex Handoff

## Step 4 status

**Complete. Ready for Step 5.**

### Manual regression follow-up

The authoritative READ classifier now accepts single-argument `--version`
probes in semicolon chains when every branch is observational; a mutating
branch still prevents READ. The dispatcher uses that same tier for its mode
label and policy, including an Executive auto-run label for allowed CHANGE.
Help rows keep each registry description with its command. Fresh unrelated
questions omit saved WIP, the last diagnosis, scratchpad, and old conversation
while preserving those files for explicit continuation. Capability construction
omits declared actions whose leaf function is unavailable after the permitted
lazy module load. Context refresh reports collection and scrub validation as
separate outcomes, while provider request redaction remains the final gate.

Deterministic Guide, Assist, and Executive fixtures cover VLC, KDE Connect,
Dolphin, a real CHANGE, and DESTROY confirmation. The full runner passed 46
Bash checks, 46 Python tests, 238 core BATS tests, and 40 integration BATS
tests. Its only failures remain the three previously documented Nextcloud
storage expectations in the 61-test module group. ShellCheck and Ruff are
unavailable locally.

During validation, an initial test fixture wrote to the ignored
`knowledge/wip.md` path. The test now uses a temporary directory. The user
confirmed there was no prior WIP file, so no restoration is needed.

The canonical interaction value is `ai_mode=guide|assist|executive`.
`ai_get_mode()` in `core/ai/safety.sh` is the policy-facing accessor; the same
value feeds the session display, prompt context, command handler, palette,
runtime state, and saved settings. Guide proposes READ actions through the
existing pending approval record and dispatcher, with Run, Skip, Explain, and
`/stop`. Assist auto-runs READ and asks before CHANGE. Executive auto-runs READ
and applies the existing executive CHANGE approval policy. DESTROY still
requires exact `YES`; hard denials, action policy, module ownership, and
classification remain backend decisions. Mode changes are rejected while a
session is awaiting or explaining a pending approval.

`mode guide|assist|executive` is registered in the existing command/action
registry, so typed and palette selections reach the same handler. Legacy
`exec on` maps to Executive; `exec off` maps to Assist. This matches the old
behavior: `executive_mode=true` auto-approved CHANGE and `false` auto-ran only
READ. On load, an old `executive_mode=true` setting migrates to Executive and
`false` to Assist when `ai_mode` is absent. New saves write only `ai_mode` in
the existing `config/variables/ai_settings.env` store. Guide must be selected
explicitly. An invalid explicit saved mode fails closed to Assist.

Validation: 88 focused mode, command, approval, and safety BATS tests and 41
focused registry and transaction Python tests pass. Bash syntax and diff checks
pass. The full runner passed 46 Bash checks, 46 Python tests, all 230 core BATS
tests, and all 40 integration BATS tests. Its only failures are the same three
existing Nextcloud storage expectation tests in the 60-test module group.
The GPG-agent test and one hostname probe were skipped. ShellCheck and Ruff
are not installed locally. No Step 4 code blocker remains.

Step 5 can build the frontend event stream on the canonical mode state and
pending approval record. Preserve the Step 1–4 dispatcher, registry, and
provider transaction boundaries; render mode and pending decisions from them.

## Step 3 status

**Complete. Ready for Step 4.** The existing execution gate in
`core/ai/safety.sh` now holds one structured pending approval record with the
tool-call ID, normalized arguments, tier, operation ID, reason, and pending
authorization state. The line prompt handles named APPROVE, DECLINE, EXPLAIN,
and STOP outcomes. Explain moves the existing session from `awaiting_approval`
to `explaining_pending_action` and back without changing the pending record or
approval metadata. No stays `action_denied`; `/stop` records the same canonical
denied tool result with `approval_stopped` and ends in `stopped_by_user` after
the provider transaction commits. DESTROY still requires exact `YES`.

`core/ai/approval_explain.py` projects only pending-action facts into a focused,
text-only request to the configured AI provider. The AI supplies prose; Igor
retains classification, approval, command identity, and execution authority.
The request excludes conversation history and unrelated context, marks action
data as untrusted, and passes through the existing scrub/request boundary.
A successful explanation is cached for the unchanged pending record. Provider
failure, tool output, or an empty reply returns to the same approval prompt.
Policy, module availability, and validation are checked again before execution.
READ remains automatic. The deterministic classifier now accepts semicolon
sequences only when every branch is READ; mutating branches still need approval.
Material changes are `core/ai/safety.sh`, `core/ai/approval_explain.py`,
`core/ai/tool_input.py`, `core/ai/core.sh`, `tests/core/test_ai_approval.bats`,
`tests/core/test_safety_dispatch.bats`, `tests/test_ai_transactions.py`, and
`README.md`.

Validation: 25 focused approval BATS tests, 30 safety dispatcher BATS tests,
53 focused Step 1/2/3 Python tests, Bash syntax, Python compile, and diff checks
pass. The full runner passed 46 Bash checks, 46 Python tests, all 216 core BATS
tests, and all 40 integration BATS tests. Its only failures are the same three
existing Nextcloud storage expectation tests in the 60-test module group. The
GPG-agent test and one hostname probe were skipped. ShellCheck and Ruff are
unavailable locally.
Step 4 can build Guide / Assist / Executive modes on this pending record and
the existing backend authorization path; no Step 3 code blocker remains.

## Step 2 status

**Complete. Ready for Step 3.** `core/ai/session_commands.py` is the single
data-only action registry. Each entry carries a stable ID, command spelling,
aliases, syntax, description, category, handler identity, and applicable session
states. Its lookup validates typed input before the provider path; its help and
palette views come from the same entries. The Bash session retains the existing
handlers and Step 1 provider, result, and safety ownership.

Type `:` at the AI chat prompt to open the numbered palette. Enter a number to
select an action, `/text` to filter, or `b` to return. The palette asks for
arguments where needed and sends the selection through the typed command route.
`help` and the optional right pane also render registry metadata. Material files:
`core/ai/session_commands.py`, `core/ai/core.sh`, `tests/test_ai_session_commands.py`,
`tests/core/test_ai_control_paths.bats`, and `README.md`.

Validation: 15 focused registry tests, 19 control-path BATS tests, 52 focused
Step 1 Python regressions, 94 focused Step 1 BATS regressions, Bash syntax,
Python compile, and diff checks passed. The full runner passed its Bash, Python,
190 core BATS, and 40 integration BATS checks. Three pre-existing Nextcloud
storage expectation tests failed in the 60-test module group; one GPG-agent
test and one hostname probe were skipped. ShellCheck and Ruff were unavailable.
No Step 3 code blocker remains.

## Step 1 summary

Complete.

Established and regression-tested:
- provider-safe tool transaction completion/resume
- canonical execution results and explicit session states
- normal-user runtime/privilege model
- READ / CHANGE / DESTROY classification
- `/stop` vs decline semantics
- secure runtime/context/temp handling

Step 1 backend invariants remain authoritative and must not be reimplemented by later UI layers.
