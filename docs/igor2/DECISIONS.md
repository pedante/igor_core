# Igor 2 architectural decisions

Accepted decisions should not be repeatedly reopened without new repository evidence. Open decisions are resolved at the roadmap stage where they become necessary.

## Accepted

### D001 — Codex-like TUI is the primary human-interface direction

The structured full-screen TUI is the main Igor UX direction. CLI/headless paths remain for scripting, recovery, testing and automation. Long-term, `./igor.sh` should launch the primary TUI when migration permits.

### D002 — AI autonomy and OS privilege are separate

Guide/Assist/Executive determine interaction autonomy. They do not grant root. Privilege is authenticated/authorized by the runtime for the exact operation.

### D003 — Module presence is not module activation

A module existing under `modules/` is insufficient for runtime contribution.

### D004 — Core remains application-agnostic

Application/deployment-specific behavior belongs to modules or integration rules rather than core.

### D005 — Debian and Arch Linux are initial tested platform targets

Existing family detection/package mappings are useful seeds. Support is claimed only to the level tests demonstrate.

### D006 — Knowledge and observed state are different

Knowledge explains domains. The System Model represents what is known about this machine.

### D007 — Capabilities are the shared operational API

TUI, CLI, healing, automation and future external control converge on shared capabilities instead of duplicate domain operations.

### D008 — Modules may declare automation; Igor owns scheduling

Scheduling, policy, retries, privilege, execution and history are runtime responsibilities.

### D009 — Modules compose through instances/relationships

Prefer coherent reusable domain modules plus deployment relationships over monolithic combination modules when the separation provides real reuse. Do not split working modules before composition contracts exist.

### D010 — Mail control, if reintroduced, is an interface

The current tree does not contain the old `core/mailcmd/` implementation. If authenticated mail control returns, it must invoke shared Igor capabilities/safety/privilege/verification/history. Notifications remain conceptually separate from incoming control.

### D011 — Operational memory is not chat history

Incidents/actions/outcomes belong in structured Igor-owned history.

### D012 — Cleanup is continuous

A new authoritative path retires the superseded path when safe. Final consolidation is not an excuse to leave duplicates active indefinitely.

### D013 — Preserve the current AI reference-data trust boundary

Module prose, context, logs, reports, tool results and history summaries are reference data. They can inform reasoning but cannot authorize actions or modify deterministic policy.

### D014 — Frontend events and domain events are different contracts

`core/ai/events.sh` is a valuable frontend activity stream. The future Domain Event Bus represents operational events consumed by automation/healing/notifications/history. Do not conflate the two.

### D015 — Evolve the existing module activation runtime

Current enable/disable and owner-aware activation is the Module Runtime v2 starting point. Do not introduce a parallel module loader or rename state vocabulary solely for architectural cosmetics.

### D016 — Evolve the existing platform helpers

`distro.sh`, `pkg.sh` and Python resolution are the platform-abstraction starting point. Expand/test them rather than create a second distro layer.

### D017 — Module API v2 has a language-neutral contract and a Bash-first adapter (Q001)

The manifest, contribution descriptors and handler input/output envelope are
data contracts independent of implementation language. Wave C implements Bash
handlers through the existing loader; a Python handler adapter is added only
when a real module needs one. The API names domain contributions and their
requirements, while the adapter knows how to invoke a handler. This preserves
the two working Bash modules without making Bash hook names the public v2 API
or adding a plugin process manager now. Unsupported handler runtimes fail
validation clearly; they are not silently interpreted as Bash.

### D018 — Keep a small INI bootstrap manifest and use explicit JSON declarations (Q002)

`module.conf` remains the discovery and identity file. A v2 manifest declares
`module_api=2`, identity/version, handler runtime/entrypoint if needed, explicit
contract file paths and module-wide requirements. V2 parsing is strict and
section-aware; the permissive first-key v1 parser remains compatibility only.
JSON files named by the manifest contain optional contribution descriptors and
can be split only by explicit path, never directory auto-discovery. Python's
standard library can validate them without a new dependency. TOML would imply
an unestablished Python 3.11 floor, YAML adds a parser dependency, and a large
INI manifest cannot express nested metadata cleanly.

### D019 — Dependencies are small, typed gates, not a solver (Q005)

A hard module dependency names an exact module and determines load order. An
optional module integration never activates its provider or blocks the base
module. A capability requirement names a canonical registered capability;
use it when the provider identity is irrelevant, and require one unambiguous
active executable provider. Module-wide requirements can block activation;
requirements on one contribution only withhold that contribution. Platform/runtime
requirements are checked by core before activation or invocation as declared.
Disabled, missing or failed providers never auto-enable; the dependent reports
an unavailable reason. V1 `depends_on` remains ordering-only compatibility;
v2 has no new ordering-only field until a concrete need arises.

### D020 — Core provides OS mechanisms; `system` owns host-domain meaning (Q006)

If an operation is needed to activate modules or offers a reusable Linux
mechanism without host-health meaning, it belongs in core/platform: distro
detection, normalized package/service/process/filesystem/user/network
operations, privilege, execution and registries. If it interprets host facts,
thresholds or administrative intent that should disappear when `system` is
disabled, it belongs in `system`: host observations, health checks, knowledge
and higher-level service administration. Modules request normalized operations;
core does not choose application-specific workflows. This rule applies on both
Debian and Arch. Moving existing files follows later steps and is not implied
by this decision alone.

### D021 — V2 evolves one activation runtime with explicit compatibility

The current discovered/disabled/active/unavailable states and restart-based
activation remain; no hot unload or new persistent state is needed. V2
declarations join one owner-stamped contribution index under the current
loader. V1 registrations are adapted into that index while legacy hook views
remain temporary for current consumers. A package may opt into v1 compatibility
alongside v2 declarations, but the same canonical contribution may have only
one execution path per consumer. Unsupported API versions or invalid v2
declarations make the module unavailable with a reason. Step 23 removes v1 only
after consumers, bundled modules and external-use checks are migrated.

### D022 — Initial v2 module trust is reviewed local code (initial Q004)

V2 executable modules remain trusted local code, not sandboxed plugins.
Unlike the v1 omitted-entry compatibility default, a newly installed v2
module requires an explicit enabled policy entry before its code can run.
Migrating an already active bundled module must preserve its prior policy by
writing or carrying an explicit enabled entry; a disabled entry remains
disabled. Module knowledge and handler output are reference data for AI,
never approval or privilege. Executable capability metadata may declare a
privilege requirement, but Igor's existing runtime remains the authority for
authorization and OS authentication. A future third-party trust model can add
provenance/permissions without changing the contribution envelope.

### D023 — Core is internally separated into testable services/components

Core remains one conceptual authority boundary, but configuration, secrets,
canonical paths/ownership, persistent state, module registration, capability
registration, compatibility, authority/privilege, events, machine memory,
context/AI and provenance/audit must not become one undifferentiated global
implementation. This is a contract/dependency rule, not a microservices
requirement.

### D024 — Roadmap completion is evidence-based

A foundation/wave is not complete because its design prose exists. Completion
requires the relevant proof categories defined in EXECUTION.md: contract,
regression, real vertical slice, inspection, and migration/recovery where
persistent state/contracts change. Exit criteria should be falsifiable and
automated where practical.

### D025 — Observability begins with subsystem authority

A subsystem exposes a minimal inspection surface when it becomes authoritative.
Later TUI work consolidates those surfaces; it does not postpone observability
until the UI consolidation step.

### D026 — Persistent ownership classes are explicit

Code/package content, configuration, secrets, persistent state, machine memory,
knowledge, learned local artifacts, investigations, operational history and
disposable runtime have distinct ownership/lifecycle semantics. Modules may
declare schemas/contributions but do not store mutable machine-specific state
inside their installed package.

### D027 — Secret use is mediated and auditable

Secret storage and secret use are separate concerns. Secret values do not enter
AI context by default. Consumers should receive references or non-secret status
where sufficient. Authorized value access is mediated by Igor and should be
auditable where practical without logging the value.

### D028 — Recovery semantics belong to capabilities/plans

Igor does not guarantee generic rollback for arbitrary system work.
State-changing capabilities declare recovery semantics such as reversible,
best-effort, compensating action, snapshot-required or irreversible. Plans
surface these semantics before execution and verify recovery/compensation where
practical.

### D029 — Machine memory separates observed state, desired state and responsibility

Igor-owned structured memory distinguishes what is observed, configured or
user-declared, desired, inferred, stale/unknown and what Igor has been asked to
maintain/watch. Investigation findings and verification outcomes may reference
this model. Chat history is never the authoritative substitute.

### D030 — Multi-step system work uses structured plans

Installation, configuration, repair and migration workflows compose registered
capabilities into inspectable plans with preconditions, ordered steps,
approval/privilege points, affected objects, recovery semantics and
verification. AI may propose/explain plans; deterministic Igor runtime resolves
providers, authorizes, executes and verifies them.

### D031 — Persistent migrations require explicit cutover and recovery

Any change to persistent layout or contract defines source, target, validation,
idempotency/re-entry, verification, recovery/backup behavior where needed and a
cutover rule that prevents indefinite dual-source ambiguity.

### D032 — ServerMind and Steward are design influences, not dependencies

The discovery/machine-model lessons adopted from ServerMind and the durable
state/desired-state/planning/investigation lessons adopted from Steward are
recorded in INFLUENCES.md. Igor adapts those ideas to its own local Linux,
module, capability and deterministic authority model; no compatibility or
runtime dependency on either project is implied.

### D033 — System Model facts have independent state-class slots (Wave D)

The canonical fact key is `(object_id, property, state_class)`. `observed`,
`configured`, `user_declared`, `desired` and `inferred` are distinct slots;
`known`, `unknown`, `stale` and `not_observed` are separate availability states.
Intent never overwrites observation. Responsibility is a separate sourced
`watch`/`maintain` record, not a fact value or execution authorization. Core
owns typed validation, provenance, freshness and inspection. The minimum
record, object identifiers and source rules are in
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md).

### D034 — Igor commits observer output through one validation boundary (Wave D)

Active v2 observers return declared typed data through the existing handler
envelope. Igor stamps identity/time, validates the complete response and
commits it to the System Model. Modules cannot write internal storage or
declare themselves authoritative. Refresh is explicit/on-demand and bounded;
there is no Wave D scheduler. A failed/invalid/timeout refresh makes prior
values stale or new slots unknown without deleting last evidence. Privileged
observers cannot create another sudo path. See
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md).

### D035 — One structured check result feeds existing health workflows (Wave D)

One active-owner check registry/runner produces reusable structured results.
Diagnose and Healing retain their distinct workflows and receive projections
from the same result. V1 `CHECK:` and `CHECK_RESULT` are compatibility inputs
until each canonical check cuts over; one pass must not execute that check
twice. Health text and remediation references are advisory and cannot
authorize an action. See [HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md).

### D036 — Wave D defers a persistent observed-fact backend (Q003 remains open)

Rebuildable observations and health results may be runtime snapshots. Existing
authoritative configuration/user policy or verified installer records remain
the persistent source for configured, desired and responsibility intent where
such source exists; Wave D rehydrates them through a backend-independent
System Model interface and adds no general intent editor or fact database.
Absent sources remain absent. Q003 still decides whether observed snapshots or
history need durable storage before Step 15. See
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md).

---

## Open decisions

### Q003 — System Model persistence

Which state survives restart, and what storage mechanism best fits actual access/history requirements?

Do not block System Model v1 on premature storage selection.

Decision target: before Step 15.

### Q004 — Later third-party module trust policy

D022 settles the initial v2 boundary: explicitly enabled, reviewed local
executable code, with AI reference data kept outside authorization. If Igor
later distributes unreviewed third-party modules, what provenance,
permissions, isolation and signing policy is needed?

Decision target: before a third-party distribution or marketplace contract.

### Q007 — Relationship/deployment ownership

How are relationships created/reconciled among discovery, configuration, installers, users and AI proposals?

Decision target: Step 17.

### Q008 — Automation activation policy

Can a module activate an automation automatically, or only propose defaults that administrator/runtime policy enables?

Current preference: modules propose; policy activates.

Decision target: Step 14.

### Q009 — Integration-rule packaging

Do cross-module rules live with one module, separate integration packages, or a registry supporting both?

Resolve using real Nextcloud/Docker/Cloudflare cases.

Decision target: Steps 18–21.

### Q010 — Raw shell fallback policy

When may AI use arbitrary shell because no capability fits, and what additional approval/verification applies?

Decision target: Step 11.

### Q011 — Remote approval policy

If remote control is added, which READ/CHANGE/DESTROY operations may execute without an interactive TUI approval?

Decision target: Step 22.

### Q012 — Effective `system` threshold configuration

`config/variables/system.env` documents `SYSTEM_RAM_WARN_MB=80`, but current
RAM checks execute hardcoded 80 MiB critical / 150 MiB warning boundaries.
Wave D preserves those executed boundaries and exposes them as effective
check metadata. When the Ownership Foundation gives module configuration one
authoritative validation path, which settings and migration rule should make
host thresholds configurable without silently changing existing behavior?

Decision target: before making `system.env` RAM settings authoritative; this
does not block the Wave D memory slice.
