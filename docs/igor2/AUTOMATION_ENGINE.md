# Step 14 — Automation Engine implementation contract

Status: **accepted design; 14A and 14B implemented, 14C–14E pending**. This contract is subordinate
to [ARCHITECTURE.md](ARCHITECTURE.md) and D044–D047 in
[DECISIONS.md](DECISIONS.md). Step 13's [EVENT_BUS.md](EVENT_BUS.md), the Wave E
[AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md) capability path and the
[EXECUTION.md](EXECUTION.md) ownership and proof rules remain authoritative.
This design does not mark Step 14 complete.

14B provides an explicit `--automations run-due [Guide|Assist|Executive]`
tick. It atomically claims each eligible due `once_at` slot in the version-1
store, then enters `ai_execute_tool` with the frozen target. A pre-dispatch
claim survives restart as `interrupted_unknown` if dispatch never reaches a
canonical result. Terminal summaries retain canonical execution, verification
and outcome statuses without retaining capability output. Guide admits no
runs. Inspection reports due state, claim state, last attempt and the reason
for ineligibility without mutation. No periodic or background scheduling is
installed.

## Authority and identities

Igor Core owns the automation registry, scheduler, eligibility decisions and
run state. A module's v2 `automation` contribution is an **inactive template**:
an owner-namespaced proposal ID, source module/version, proposed trigger kind
and defaults, canonical capability ID and proposed fixed input values.
The operator must supply missing required trigger parameters (such as an
absolute `once_at` time) and review the resulting complete instance. The
validated proposal digest is retained as provenance. Its presence,
installation or activation never creates or enables an instance. The existing owner-aware contribution
index is the only module proposal source; v1 hooks and package scripts gain no
scheduling contract. Inactive modules expose no active proposals.

A configured instance is separate, mutable Igor-owned intent. Its minimum
versioned record contains:

| Field | Meaning |
|---|---|
| `id`, `schema_version` | Opaque Core-assigned stable instance ID and record format. |
| `owner`, `source` | `owner` is `user` or `system`; `source` is a Core-stamped manual creation or a copied `module` proposal ID, owner and validated proposal digest. Source is provenance, not ongoing authority. |
| `enabled` | Explicit policy decision; defaults false. |
| `trigger` | One typed trigger, with its own version and parameters. |
| `target` | Canonical capability ID, optional explicit provider and validated, fixed inputs. No event/condition substitution or shell command. |
| `execution_policy` | Versioned `read_unattended` policy only in Step 14. No stored approval token or privilege credential. |
| `retry_policy` | `max_attempts: 1` in the first slices; later bounded READ retries require a separate slice. |

Core validates and freezes target inputs on create/edit, then resolves and
revalidates provider, input schema, effective safety, availability and
preconditions **at each run**. It does not persist a prepared capability
proposal or treat a stored tier/provider declaration as authoritative. An
unresolved or changed provider makes the instance unavailable until an
operator edits or re-enables it; it never falls back to another provider
silently. An omitted provider must resolve unambiguously on each run.

`enabled` is durable intent; `availability` and its exact reason are derived
at inspection/eligibility from module activation, proposal provenance, target
resolution, policy, trigger support and current runtime mode. A copied
module proposal remains owned by the user/system, but is unavailable while
its source module is disabled, removed or has an incompatible proposal
digest. Restoring the compatible active proposal restores eligibility;
there is no automatic deletion or catch-up run. Manual Core/user instances
remain subject to the target provider's active ownership. This preserves
the rule that a disabled module contributes no runtime behavior.

Transient run state holds the in-process lock, pending event/condition signal,
operation correlation and current attempt. It is never a configured
automation. A separate bounded `last_attempt` summary and schedule cursor
belong to Automation Engine operational state, not Step 15 history.

## Q008: activation and mutation

**Modules propose; trusted administrator/runtime policy activates.** A local
authenticated operator through an Igor interface may create from a proposal
or create manually, review the exact trigger/target/inputs/policy, and
explicitly enable, disable, edit or delete an instance. A trusted Core
administrator policy may perform the same operations only through that
validated mutation API with an attributable actor and explicit configured
rule; no module manifest is itself such a rule. Edits to target, trigger or
policy disable the instance until explicitly re-enabled. Disable/delete take
effect before another run is admitted; an in-flight canonical invocation is
reported, not retroactively undone. Deleting a proposal never deletes an
instance. AI may draft a proposal for operator review but cannot call the
activation/mutation authority merely by generating text. Module data, logs,
domain events and condition results cannot activate or edit an instance.

Step 14's mutation API accepts only an unprivileged READ target under the
`read_unattended` policy for enablement. A CHANGE/DESTROY or privileged target
may be shown as a proposal but is rejected for enablement with an exact
reason. Activation approval confirms recurring *eligibility* for the exact
configured READ operation; it is distinct from per-run capability approval.
Guide mode does not auto-run READ: due instances remain pending/unavailable
for unattended execution until Assist or Executive is active. Assist and
Executive may run the eligible READ through their existing automatic READ
policy. Mode changes and policy revocation are checked at every run.

Existing interactive CHANGE policy is not an unattended grant: Assist needs
per-run confirmation, and Executive's interactive structured CHANGE rule
must not be reused as an implicit persistent scheduler permission. Step 14
does not execute unattended CHANGE or DESTROY. A later explicit scoped
unattended CHANGE policy would need exact target/input bounds, actor,
revocation, expiry, audit and privilege semantics before enablement; it
must still enter the canonical dispatcher. DESTROY retains exact `YES` for
each invocation under current policy; Step 14 has no unattended DESTROY
mode. No activation or mode grants OS privilege. Privileged unattended runs
are excluded; a future policy must use Igor's existing PTY/privilege broker
for the exact operation and never store sudo credentials.

## Trigger contract and slice order

Each trigger has `kind` plus a closed, versioned parameter schema. Core
computes due/eligible state; modules and AI never install cron entries or
register executable callbacks. Wall-clock timestamps are UTC with explicit
timezone conversion only at configuration boundaries. A scheduler restart
does not infer missed events, conditions or elapsed periodic ticks from chat
or event history.

| Kind | Contract | First implementation |
|---|---|---|
| `once_at` | One UTC due timestamp. Claim once durably before dispatch. A missed time is eligible once on next healthy start; a claimed attempt never auto-runs again. | 14B |
| `periodic` | Positive bounded interval in seconds and UTC anchor; Core computes slots from anchor, skips missed slots, and claims at most one current slot. No cron expression or backlog. | 14C |
| `event` | Exact active domain event type and optional exact owner/object filters copied into configuration. Callback only queues eligibility; it cannot dispatch inside publication. No replay or durable queue. | 14D |
| `condition` | Bounded polling interval plus one typed predicate over a named Igor state query. Only fresh, known deterministic values satisfy it; unknown/stale/error fail closed. Evaluate on a tick without implicit observer refresh. | 14E |

The first real execution slice is `once_at` invoking the unprivileged READ
`system.host.memory.refresh` with `{}` inputs. It crosses scheduler admission,
normal capability dispatch, the existing observer and verifier, and a
canonical terminal result. A one-time trigger is smaller than periodic
because it requires no recurring slot arithmetic; memory refresh has an
existing real provider and deterministic verification. During 14A, enabled
`once_at` intent reported `execution_not_installed`; with 14B installed,
inspection reports the actual due and claim state. Other trigger
proposals remain inspectable but cannot be enabled until their slices
implement validation, admission and recovery.

For event triggers, filter fields are fixed at activation and match only the
Core-validated Step 13 envelope (`event_type`, stamped `owner`, membership
in `related_objects`). Payload text and evidence references never supply inputs,
approval, tier, privilege or verification. The trusted Core subscriber uses
the session-local best-effort bus; a lost event is lost. Drain queued matches
outside the publish callback, suppress concurrent runs of the same instance,
and apply a configured minimum interval before another event admission.
Events produced by an automation run are dropped by this trigger adapter
during its drain, and a `capability.completed` event with that automation's
known operation ID cannot retrigger that same instance. They remain ordinary
Step 13 events for other subscribers. This prevents a self-feeding execution
chain without changing the bus.
The event bus remains separate from frontend/TUI events.

The first `condition` predicate is `fact_equals`, with a fixed object ID,
property, observed state class and typed comparison value. It reads the existing
owner-aware System Model query; disabled owners, stale facts or unknown
values do not match. It neither evaluates shell/AI expressions nor refreshes
observations. A later check predicate needs an explicit validated evaluator.

## Canonical execution, retries and failures

At admission Core reloads the enabled record and evaluates trigger, source
and target availability, runtime mode, READ/unprivileged policy and a
per-instance lock. It freezes the configured capability ID, provider and
inputs into a `run_capability` request and invokes the existing `ai_execute_tool`
dispatcher. That dispatcher resolves the active provider, validates inputs
and preconditions, applies safety/approval policy, rechecks the operation,
uses privilege mediation if a future policy allows it, invokes the Wave C
handler and runs the canonical verifier. Automation records the returned
operation ID and terminal outcome. It never calls `igor_capability_execute`
directly, a module function, raw shell, a verifier or the OS scheduler. An
event match or condition match only makes this admission eligible.

Default retry policy is one attempt. Later READ-only retry support is bounded
to at most three attempts total with a positive fixed delay, one pending
retry per instance and no concurrent runs. Retry may apply only to a
transient dispatch/transport failure explicitly classified by trusted Core;
absence of such a classification means no retry. Approval denial,
precondition failure, unavailable/disabled provider, policy denial,
privilege failure and any `unverified` result never retry automatically.
The scheduler cannot turn a terminal failed result into a success. A later
retry remains a new canonical invocation with new checks and result. The
same trigger slot/event signal cannot launch a second concurrent run;
overlap is skipped with an inspectable reason, not queued indefinitely.

## Storage, restart and inspection

Automation Engine owns one versioned private, owner-only persistent registry
at `${IGOR_DATA_DIR:-${IGOR_DIR}/data}/automation/registry.v1.json`, separate
from module packages,
`config/variables/`, secrets, System Model, Step 13 scratch and Step 15
history. It stores instance records plus the minimal schedule cursor and
last-attempt summary needed to prevent duplicate or unexplained runs:
attempt time/slot, operation ID if one exists, terminal outcome and a bounded
reason. It stores no raw event payload, capability output, secret value,
approval transcript or durable incident log. Only the engine reads/writes
its store; callers use its validated API. The engine resolves the path from
`IGOR_DIR`/`IGOR_DATA_DIR`, creates the directory with mode 700 and file with
mode 600, rejects symlinks and never exposes the path as a Module API v2
contract. Existing cron entries are neither imported nor removed implicitly.

All mutations and due-slot claims use an exclusive interprocess lock and an
atomic, durable replacement before dispatch; readers see a complete version
or a typed error. The scheduler needs no second state database.
For `once_at`, a pre-dispatch claim is an at-most-once **attempt**, not a
guarantee of execution: if Igor crashes after the claim, restart reports
`interrupted_unknown` and never silently retries it. An operator may create
a new run/instance after inspection. Periodic restart skips old slots and
computes the next future slot; a claimed current slot is not repeated.
Event/condition pending signals, in-process locks and Step 13 events vanish
on restart. Missing/corrupt/unsupported store versions fail closed: no
automation starts, with a read-only diagnostic and a recoverable copy of
the original data. No implicit reset or dual source. Reset is an explicit
operator action that disables/removes selected configured intent; it never
silently converts it into an enabled default. Initial creation from no store
is version 1, empty and disabled. Later schema changes require source and
target versions/locations, validation, atomic idempotent migration, recovery
point, post-migration verification and one cutover rule per
[EXECUTION.md](EXECUTION.md). This does not resolve Q003 System Model
persistence.

Read-only list/inspect returns ID, owner/source, enabled and derived
active/disabled/unavailable state with reason, trigger, target capability
and fixed input summary, execution/retry policy, next due time where
meaningful, last-attempt summary and in-flight marker. Secrets are never
expanded. A disabled source, unavailable target, Guide mode, unsupported
trigger or invalid store has a specific reason. Inspection does not mutate
a cursor, subscribe, evaluate a condition, refresh an observation/check,
authenticate, activate or execute a capability. TUI may render this backend
inspection later without owning another scheduler.

## Bounded implementation sessions

| Session | Scope and authoritative contracts | One vertical slice; focused tests | Full regression gate |
|---|---|---|---|
| **14A — registry** | This contract, D044–D047, `MODULE_API.md` and ownership rules. Add versioned private store, validated manual/template creation, explicit READ enable/disable/edit/delete and read-only inspection. No scheduler execution; inspection reports `execution_not_installed` even for enabled intent and warns that 14B will admit due instances. | Active `system` memory READ template completed with an operator-chosen `once_at` time, copied disabled and explicitly enabled; disabling `system` makes it unavailable. Test malformed records, policy/owner rejection, restart, corrupt store and reset. | Full `bash tests/run_all.sh` plus full Python suite before accepting 14A's persistent cutover. |
| **14B — one-time READ** | This contract, Wave E dispatcher and Step 13 result boundary. Implement `once_at` claim, admission and canonical dispatch only. | Real `system.host.memory.refresh` due once, verified through normal result; crash-after-claim and Guide/disabled-owner cases. | Focused checks in session; full regression before declaring 14B accepted. |
| **14C — periodic READ** | This trigger/claim contract and 14A store. Add interval slots, missed-slot skip and restart cursor. | One periodic memory refresh slot executes; overlap/restart does not duplicate. | Focused checks; full regression before accepting 14C. |
| **14D — event READ** | This contract and `EVENT_BUS.md`. Add Core subscriber, exact filters, deferred drain and no replay. | A validated `capability.completed` signal makes one configured READ eligible; payload cannot change target. | Focused checks; full regression before accepting 14D. |
| **14E — conditional READ** | This contract and `HOST_INTELLIGENCE.md`. Add typed fresh observed-fact predicate and bounded tick. | A known fresh host predicate admits memory refresh; stale/unknown does not. | Focused checks; full regression before declaring Step 14 complete. |

For every row, full regression means `bash tests/run_all.sh` and the full
Python `pytest -q` suite; run it in that implementation session before
accepting the slice. This design session executes neither suite.

Retries beyond one attempt and any unattended CHANGE policy need their own
future design/implementation gate; they are not prerequisites for the bounded
READ Step 14 completion. DESTROY, privileged unattended work, workflow DAGs,
durable event queues, incidents/history, baselines, relationships, healing,
remote control and Q003/Q007/Q009/Q011 remain outside this contract.

## Falsifiable Step 14 completion proof

| Class | Required evidence (not executed at this design gate) |
|---|---|
| Contract | Invalid version/trigger/inputs/policy or inactive owner fails before activation/dispatch; no module/event/AI text enables an instance; CHANGE, DESTROY and privileged targets cannot enable. |
| Regression | Previously green interaction, approval, privilege, module activation, Wave E capability and Step 13 event behavior pass full Bash and Python gates after each accepted slice. |
| Vertical slice | Real scheduled and periodic memory READs, one validated event signal and one fresh typed condition each enter the same `run_capability` path and retain canonical verification/outcome; no handler runs on denial. |
| Inspection | Read-only queries explain configured owner/source, trigger, target, policy, next run, last attempt and exact unavailability without side effects. |
| Migration/recovery | Empty version-1 creation, restart, atomic claim, crash-after-claim, corrupted/unknown version, disabled-source recovery and explicit reset are tested; later versions prove idempotent migration and one cutover. |
