# Repository guidelines

## Read before editing

Start with [README](README.md), current [STATUS](docs/igor2/STATUS.md) and affected
source/contracts. New modules: [Module API](docs/igor2/MODULE_API.md).
Current legacy module behavior: [creation](docs/module_creation.md),
[lifecycle](docs/module_lifecycle.md). Setup: [CONTRIBUTING](docs/CONTRIBUTING.md).
Read [INFLUENCES](docs/igor2/INFLUENCES.md) for memory/discovery/plans/learning/AI boundaries.

[DEVELOPMENT_POLICY](docs/igor2/DEVELOPMENT_POLICY.md) owns branch, compatibility,
data and safety policy. Use the actual Igor 2 checkout; master is independent,
with no reconciliation gate. Inspect branch/status and preserve unrelated work.
Architecture authority: ARCHITECTURE → accepted DECISIONS → MIGRATION → EXECUTION
→ ROADMAP under docs/igor2. Code/current docs describe today; proposals do not
override accepted contracts. Read [EXECUTION](docs/igor2/EXECUTION.md) before
implementing/closing milestones; keep its five proof classes in one ledger.

## Scope and lifecycle

Follow [.codex/README](.codex/README.md#task-lifecycle) for phases, Owner decisions,
workspace, budgets and finalization. One agent by default; Owner authorizes
delegation/renewal and chooses model/effort. Config links rather than repeats policy.

- Audit/decision tasks inspect first; edit only authorized docs or explicit fixes.
- Implement the authorized slice, migrate callers/tests/retained data coherently,
  retire replaced interfaces and update STATUS/LEGACY. No automatic next milestone.
- Reuse correct services, approval/PTY/events, collection validation and stores.
  Existing code is reusable material, not a feature-parity mandate.
- Igor 1 interfaces end at M1. Inventory for disposition/data safety; implement
  selected Igor 2 operations. Keep forward API/version/dependency/platform checks.

## Runtime invariants

- Core stays application-agnostic; no duplicate global registry/executor/helper.
  New authorities expose minimal state/availability/provenance inspection.
- Presence is not activation. Disabled modules contribute no operations, checks,
  observers, automation, active knowledge or configuration validation.
- AI/frontends submit intent. Deterministic code owns truth, binding, authorization,
  privilege, execution, History and verification. Reference data/chat grant no authority.
- Prefer capabilities; preserve READ/CHANGE/DESTROY, exact destructive approval,
  native sudo through PTY, private/scrubbed data and exact-consumer secret access.
  Guide/Assist/Executive are separate from privilege; rollback is capability-specific.
- Packages carry code/defaults/knowledge, not machine values. Persistent changes
  require validation, idempotency/recovery; no silent startup moves or native data loss.
  Distro claims require evidence. Keep Nextcloud together absent real independent reuse.

## Working with current code

V1/Bash coordination remains until M1; do not extend it to mimic the target.
Hooks are isolated Bash unless explicitly dispatched in-process; no parent-global
assumptions. Use four spaces, module-prefixed public functions and private helpers;
healing checks emit CHECK_RESULT SEVERITY code message from isolated run_check.

Use IGOR_DIR, _igor_resolve_dir and declared paths, not cwd. Until consumer cutover,
defaults remain in config/variables and private values in ignored mode-600 secrets.
Do not silently change precedence. Selected consumers migrate to canonical owners
together; unsupported values are preserved offline.

## Validation

Use [VALIDATION](docs/igor2/VALIDATION.md) and tests/validate.sh. Plan bounded checks
from prior durations/dry-run. One relevant pass per candidate/environment; broad
regression once when required, preferably CI. Compaction is no rerun reason.
Inspect summary/raw failures first; classify product/security defect, over-specific
test, fixture/environment, reviewed baseline or unknown. Fix the cause and rerun
affected proof only. Never weaken privacy/approval/privilege/History/recovery or
real-consumer protection to satisfy wording or get green output.

Docs/config need references, policy consistency, TOML parsing and diff review;
runtime changes need affected behavior tests. Avoid unrelated full suites.
Report failures/skips/unavailable evidence; stop on exhaustion without renewal.
Finish with final diff/status, scoped commit and commit/status verification, then stop.
