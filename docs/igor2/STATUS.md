# Igor 2 migration status

Last updated: 2026-10-02

## System 2.3.0 administration surface — experimental candidate

A bounded experiment extends the existing `system` owner rather than creating a
second sysadmin module. Core/Platform keeps Debian/Arch package-manager and
systemd mechanics; System declares host-domain semantics that the generic
Operator Surface can discover as `system.host.*`, `system.package.*`,
`system.service.*` and `system.logs.*`.

The READ slice includes host summary, pending-update discovery, package-cleanup
preview/cache usage, service list/status and journal summary metadata. Raw
journal message bodies are deliberately excluded because v2 capability results
become durable Operational History. The mutation slice is intentionally small:
service restart reuses the existing reviewed exact-argv adapter; package upgrade
and package-cache clean add narrowly admitted System-owned v1 privilege adapters.
Debian upgrade freezes `apt-get update` then `apt-get upgrade -y`; Arch freezes
`pacman -Syu --noconfirm`. Upgrade rechecks pending updates after execution.
Cache cleaning is marked irreversible and does not claim a generic verifier.

Orphan/autoremove candidates are preview-only. Reboot, journal vacuum, arbitrary
shell, user/group, firewall/network, filesystem deletion and storage repair are
not added. This experiment does not complete a roadmap boundary or establish a
general privileged-module mechanism.

Focused Platform/System tests are added on the experiment branch, including
Debian/Arch normalization, Operator Surface discovery, exact privileged argv,
post-upgrade verification and forged-adapter rejection. Runtime pass counts are
not claimed here because the current execution environment cannot resolve
GitHub for a local branch checkout.

## Step 19 Boundary 2 — brownfield attachment implementation candidate

This work starts from clean `igor2` at Boundary 1 commit `72552d3`, under the
already approved [D063](DECISIONS.md). The same two unmatched local-master
orchestration/documentation commits recorded by Boundary 1 remain; no branch,
worktree or persistent baseline migration is performed. Boundary 3 is not started.

The [attachment contract](ATTACHMENT.md) adds a read-only deterministic provider
inside the existing v1 Nextcloud package and an application-neutral Core
coordinator. Exact daemon/container/image identity, creation incarnation,
Compose project/service and inspected configuration/storage topology are frozen
before approval. Zero/multiple candidates fail closed without first-match or
path fallback. Provider domain metadata flows into the existing Deployment
Service rather than a second attachment registry.

Canonical capabilities discover/propose, explicitly initialize the private
registry when needed, adopt metadata and release scoped responsibility. Registry
revision/state/epoch and fresh provider inspection fence old proposals and
sessions. Mutation requires a matching running canonical History episode with
explicit approval; Executive auto-approval cannot accept this responsibility.
Application state, desired loglevel, Compose files and secrets remain untouched.
Only selected `nextcloud_docker.loglevel` configuration/readback/recovery duty is
accepted; no lifecycle, backup, update or general OCC authority is granted.

Configuration Service's deployment-target admission delegates to Deployment
Service's exact active grant/provider checks and creates no desired value or
writer. System Model's bounded resource/deployment observer targets retain
independent provenance and freshness. Generic inspection joins retained canonical
History and supplied observations, and reports provider policy without loading or
probing it. Unsupplied authorities remain explicit. Scoped release retains native
resources, historical identity/relationships and operation references; incomplete
consumer/job/legacy-session inventories prevent complete-detach certification.

**Closure gate:** Docker, a Docker socket and an isolated existing Nextcloud
runtime are unavailable in this checkout. Deterministic fixture proofs do not
replace the approved real application gate. Boundary 2 remains an implementation
candidate pending that evidence; no Boundary 3 setting workflow or legacy-writer
cutover is authorized by this entry.

**EXECUTION evidence (2026-10-02):**

| Proof/check | Result |
|---|---|
| Contract/focused Python | 85 cases pass across attachment, provider, History, Configuration/System Model prerequisites, Deployment Service and module inspection. Zero/multiple candidates, exact native evidence, inspectable frozen proposals, stale proposal/session/revision rejection, explicit approval, narrow grants, provider disablement and retained release are covered. |
| Canonical fixture slice | Four new Bash cases pass through the existing capability/approval/History path. Executive initialization still requires approval. Adoption persists four resources and seven typed relationships; the independently verified scoped release retains them. Before/after native inventory and target file hashes are identical. The transport allows only exact read queries and fixed file stat; no application writer, configuration store or secret import is invoked. This is an isolated transport fixture, not a running Nextcloud proof. |
| Inspection/service prerequisites | Persisted deployment structure renders through generic 15UI. Independent observations retain freshness/provenance and do not erase bindings. Configuration target admission checks Deployment Service's active exact grant, scope, revision and provider; it creates no desired value, schema or writer. Disabled-provider inspection remains meaningful and does not load another provider. |
| Migration/recovery | Legacy adoption remains compatibility only and is never invoked by the new path. Release retains resources, relationship revisions and History references; old grants/proposals cannot admit a target. Broader detach is explicitly uncertified. Actual loglevel apply/readback/recovery and legacy-writer cutover remain Boundary 3. |
| Affected Bash regression | All 132 approval, safety/dispatch and Operational History cases pass. |
| Full Bash regression | `bash tests/run_all.sh`: all five groups pass, zero failed/skipped groups. Counts: 46 legacy Bash checks, 46 rendering tests, 305 Core BATS, 167 module BATS and 40 integration BATS. Two existing Core cases skip for unavailable GPG agent and `hostname -I`; all other cases pass. |
| Python regression | Full suite: 546 passed, 319 subtests passed, 10 failures. Nine failure entries match Boundary 1's recorded baseline. The additional System configuration workflow times out at 120 seconds in the full concurrent run and passes separately in 108.60 seconds; no implementation change was made for it. The full suite is not green. Logs are retained outside the repository at `/tmp/igor19b2-*`. |
| Syntax/lint | Changed Bash syntax and Python compilation pass. Full Ruff has the same 154 baseline rules/messages, with only line shifts. CI ShellCheck reports three unchanged warnings in `safety.sh`; the new adapter and fixture have none. |
| Documentation/diff | All 254 local Markdown references resolve; diff whitespace check passes. |
| Real application gate | Unavailable: no Docker executable/socket or isolated existing Nextcloud endpoint has been supplied. No application was provisioned to replace the missing brownfield object. |

No completion, release freeze or commit is claimed while the required real
application evidence remains missing.

## Step 19 Boundary 1 — deployment identity, relationships and responsibility

The Project Owner approved [D063](DECISIONS.md) and [DEPLOYMENTS.md](DEPLOYMENTS.md)
after the Step 19 discovery proposal. This owner-scoped Step 19 takes the original
Relationships/Deployments outcome; self-healing and Step 20 remain deferred.
Execution stops with evidence after each boundary. This entry covers Boundary 1
only; brownfield attachment/composition and the real Nextcloud loglevel workflow
remain Boundaries 2 and 3.

The starting checkout was clean `igor2` at `22b0c5f`. A read-only remote query
confirmed `origin/igor2=22b0c5f` and unchanged `origin/master=852ce8f`. Master is
not an ancestor; the previously recorded content reconciliation of its two
unmatched documentation/orchestration commits remains applicable. No checkout,
worktree or baseline migration was performed.

The application-neutral Core-owned Deployment Service uses opaque scoped
identities, reuses owning-service object references, preserves relationship
claims and accepts only positive explicit scoped responsibility. It owns no
application observations, desired values, capability execution, approval,
privilege or operational episodes. Private transactional SQLite keeps atomic
metadata revisions, conflicts, idempotency and versioned export/recovery.
Trusted internal mutation interfaces deny by default; serialized provenance
cannot authorize. Public `--deployments` commands are read-only and bypass
module/configuration startup. Generic 15UI rendering consumes the backend record.

Boundary 1 imports no application and changes no deployment target. It exposes
no writable attachment or recovery CLI. Metadata responsibility release does
not certify detach; absent resource/job/session inventories remain unknown.
No deployment configuration target, observation adapter, provisioning,
destruction, application update or legacy Nextcloud writer cutover is included.

**EXECUTION evidence (2026-10-02):**

| Proof/check | Result |
|---|---|
| Contract | Opaque scoped identities survive rename/reopen and explicit native incarnation replacement. Existing owning-service references retain identity/owner and are revalidated at commit. Four closed relationship types, participation, scoped grants, competing claims and explicit resolution reject malformed/dangling/conflicting changes before effects. Discovery, binding and resource origin confer no duty. Default-deny trusted authorization cannot be supplied by serialized provenance or AI claims. |
| Vertical slice | The real Core service creates a private registry, prepares and atomically commits generic deployment/resource/relationship metadata, then separately accepts an explicit setting grant. Public CLI reads the persisted record and the real generic 15UI renderer consumes that projection. Model/desired-state sentinel bytes stay unchanged and Operational History remains empty; this metadata proof executes no application capability. The representative real application slice is explicitly reserved for Boundary 3. |
| Inspection | Read-only status/list/inspect/export bypass module/configuration startup. Absent reads create neither a store nor an installation identity. Actual persisted identity, provenance, resources, claims, conflicts and positive duties are visible. Unsupplied Configuration/System Model/History joins, unverified evidence and uncertified detach remain explicit. Reads preserve the complete private-file byte inventory. Public mutation flags and malformed argument counts fail before storage access. |
| Migration/recovery | New private storage coexists with existing authorities; no legacy application/configuration import. Versioned same-scope restore validates before writes, saves a recovery point, retains later identities/operation fences and invalidates old proposals. Exact operation retry is idempotent; payload reuse fails. Concurrent commits have one CAS winner; failed batches and failed recovery backup preserve the registry. Unknown/corrupt versions, malformed exports, foreign scope and unsafe filesystem paths fail closed without repair. Metadata release retains resources and does not claim completed detach or resource rollback. |
| Authority/model integrity | Existing service references are reused rather than copied into a second resource authority. Source claims never authorize acceptance. Shared-setting/deployment-wide grant conflicts are fenced, while unrelated scopes remain usable. Persisted structural validation is stable when environment secrets change; admission screens sensitive metadata. No observations, desired values, execution approval, privilege, application destruction or Operational History episodes are synthesized. |
| Focused validation | All 47 Core contract cases and three real CLI/15UI integration cases pass. Focused Ruff and compilation of the service and both test files pass. |
| Python regression/lint | Full Python: 520 passed, 319 subtests passed and nine failures, compared with clean-HEAD baseline 470 passed, 319 subtests passed and the same nine failure entries. All 50 new cases pass; no new failing names. Retained failures are two operator-backend cases, four Guide/Assist automation cases, one operator-projection case and startup choices `s`/`f` timing out at 20 seconds. The full suite is not green. Full Ruff is byte-identical to baseline: 154 existing findings, no new findings. Logs are outside the repository under `/tmp/igor19b1-*`. |
| Bash regression | `bash tests/run_all.sh` passes all five groups: 46 legacy Bash cases, 46 rendering tests, 305 Core BATS, 163 module BATS and 40 integration BATS. Two existing Core cases skip because the GPG agent and `hostname -I` are unavailable; the other 506 BATS pass. No external deployment is part of this proof. |
| Syntax/lint | Changed Bash passes `bash -n`. CI ShellCheck finds only two unchanged SC2155 warnings in `igor.sh` (current lines 13 and 1017, HEAD lines 13 and 1009); the new bridge is clean. |
| Documentation | All 145 local Markdown references resolve. The final diff check passes. The approved decision, service contract, roadmap and legacy map distinguish Boundary 1 from pending attachment/application proof. |

Boundary 1 is complete within its application-neutral metadata contract,
inspection and recovery scope. Required contract, regression, vertical-slice,
inspection and migration/recovery evidence is recorded above; baseline failures
and environment skips remain explicit. Release freeze permits only final scope
review and the scoped commit. Boundaries 2 and 3 have not started.

## Operator Surface refresh/diagnostics follow-up — implementation candidate

The merged Operator Surface already requested a fresh backend snapshot whenever
`:` opened. The blank-screen failure mode came from observability: collector or
projection failures could be suppressed, while a valid zero-entry snapshot had
no distinct empty-state presentation.

This follow-up keeps the same authority boundary and adds no registry, database
or execution path. Snapshot projection now reports per-source status/counts plus
`ready`, `empty` or `error`; malformed registry JSON becomes an explicit
failed source. The TUI shows those counts/states, reports a missing response
after a bounded wait, and supports `Ctrl+R` to request another snapshot. Capability
selection still re-enters the canonical dispatcher unchanged.

Focused projection/backend/TUI tests are updated on the branch. Runtime pass
counts are not claimed here: the current execution environment cannot resolve
GitHub for a local branch checkout, and the repository Actions workflow does not
run for pull requests whose base is `igor2`.

## Step 18 Boundary 3 — System memory warning configuration workflow

The Project Owner approved [D062](DECISIONS.md): the real System memory health
consumer, not Nextcloud, is the first reversible module configuration proof.
`system.memory.warning_threshold_mib` is an integer System schema contribution,
default 150 MiB and range 81–4096 MiB. Critical stays 80 MiB. The ineffective
legacy `SYSTEM_RAM_WARN_MB` is neither imported nor made authoritative.

The shipped System 2.2.0 package contributes the schema, typed CHANGE application,
typed READ readback and host knowledge. Core owns desired persistence and
revision/state-token validation. A narrow Core desired CHANGE and separate
System CHANGE both use existing approval/privilege/execution policy. Independent
READ verifies the shared memory-health consumer in the current process.
Operational History keeps separate correlated episodes for desired commit,
application and explicit readback; no new log or System Model configuration fact
is created. Desired, resolved and process-consumed state remain separate.

Failed application leaves the approved desired revision visible. Failed readback
is an unverified change, distinguishable from failed execution. Recovery means
explicitly submitting the prior/default threshold through the same approved
path, producing new revisions and History. Startup consumes an already-approved
resolution for active System only, without a verification claim or success
episode. Disabled owners retain inspectable desired state while the valid schema
package remains installed; no disabled application is admitted.

The narrow `memory-warning MIB` command uses the existing command registry;
structured inspection and schema/capability discovery reuse owning-service
records, operator projection and generic 15UI rendering. No module UI, generic
settings editor, automatic rollback, AI decision, application migration, full
detach, sandbox/signing, Step 19 or Step 20 is introduced.
[The workflow](SYSTEM_MEMORY_WORKFLOW.md) describes use and process-local limits.

The starting checkout was clean `igor2` at `0f48df4`, containing Boundary 1
`77b2e40` and Boundary 2 `d7da5e8`. A read-only remote query confirmed the same
`origin/igor2` and unchanged `origin/master=852ce8f`; the prior content
reconciliation remains applicable. Clean-HEAD Python baseline: 454 passed,
320 subtests passed and seven failures (four existing Guide/Assist automation
cases, two merged operator-surface cases and a 20-second startup timeout).
Full Ruff baseline: 154 existing findings. Validation logs are outside the
repository under `/tmp/igor18b3-*`; final evidence follows below.

**EXECUTION evidence (2026-10-02):**

| Proof/check | Result |
|---|---|
| Contract | The shipped System schema enforces integer 81–4096 MiB, default 150, with a separate 80 MiB critical rule. Focused cases reject invalid/stale desired state and stale application intent. Exact reviewed adapter admission rejects weakened READ safety, omitted verification and required privilege before handler effects. |
| Vertical slice | `memory-warning 220` crosses canonical proposal/validation, desired CHANGE, separate approved System CHANGE, current-process consumption and independent typed READ. Three successful correlated History episodes preserve Core/System ownership, authority, execution and verification. The outer process consumes 220; desired state alone remains unverified. |
| Inspection | Real module inspection exposes the shipped schema, desired/resolved and distinct process-consumption provenance. The generic 15UI `panel_rows` renderer consumes this actual structured record. The existing operator projection discovers declarations/capabilities; no custom UI is added. Disabled owners retain data-only inspection while application/readback remain unavailable. |
| Recovery/migration | No persistent layout or broad value migration. Existing Core configuration coexists with the new System record. Legacy `SYSTEM_RAM_WARN_MB` is not imported. Failed application leaves desired intent visible with prior runtime consumption. Mismatched verification records `unverified_change`; a later mismatched READ records `unverified_result`. Explicit prior/default-value recovery creates a new desired revision, approved application and verified READ without erasing failed evidence. No automatic rollback. |
| Authority/model integrity | Declining the second CHANGE leaves the already-approved desired commit and prior runtime consumption distinct. Frozen inputs/revisions remain mandatory. The unchanged model bytes in the real workflow prove no configuration-to-fact promotion; independent health cases show the consumed warning policy changes classification while critical remains separate. |
| Focused validation | 38 existing configuration plus 47 module-contract/capability-runtime/inspection Python cases pass. Eleven workflow cases are proved across bounded focused runs; the final full regression covers the latest actual module-inspection/rendering assertion. All 18 retained Boundary 1/2 BATS cases pass, including the new forged-adapter case. |
| Python regression/lint | Full Python: 465 passed and 319 subtests passed; all eleven workflow cases, including final actual inspection/rendering assertions, pass. Eight failures remain: the six baseline operator/Guide–Assist automation cases plus startup choices `s` and `f` timing out at 20 seconds. The full baseline had only startup `s` fail; isolated runs reproduce both choices on the unchanged committed baseline export (40.64 seconds) and current checkout (40.88 seconds), establishing existing timing fragility rather than a new independent failure. The full suite is not green. Full Ruff is byte-identical to baseline: 154 existing findings. |
| Bash regression | `bash tests/run_all.sh` completes all five groups with no failures: 46 legacy Bash cases, 46 rendering tests, 305 Core BATS, 163 module BATS and 40 integration BATS. Two existing Core cases skip because the GPG agent and `hostname -I` are unavailable; the other 506 BATS pass. No external deployment is part of this proof. |
| Syntax/compilation/lint | Changed shell scripts pass `bash -n`; changed/new Python compilation passes. CI ShellCheck on changed production Bash and BATS shows only six existing warnings: three in `core/ai/core.sh` (SC2174, SC2010, SC2011) and three in `core/ai/safety.sh` (SC2024, two SC2155). Other changed scripts/tests are clean. |
| Documentation | All 115 local references in changed Markdown resolve. The accepted decision, roadmap, module/configuration docs and legacy map record only this owner-approved System proof and its explicit deferrals. |

Evidence is scoped to the current Igor process. Fresh active sessions consume
approved desired resolution but do not automatically create verified History.
Removing a package/schema, general binding/adoption and complete detach remain
unproven. An isolated complete workflow took approximately 90 seconds in this
environment; no performance optimization or execution-time guarantee is claimed.
Boundary 3 is complete within this selected reversible configuration proof.
Required focused, regression, inspection, recovery and documentation evidence
is recorded above; existing full-suite failures/skips are explicitly retained.
Release freeze permits only final scope review and the scoped commit. Step 19,
Step 20 and broader application/detach work are not started.

## Step 18 Boundary 2 — module composition prerequisites

The Project Owner authorized a bounded integration proof after Boundary 1 at
`77b2e40`. The representative is the existing mixed v1/v2 **System** package:
real `host.basics` knowledge and the typed `system.host.memory.refresh` READ
capability. An isolated package copy contributes one test-only module-scoped
configuration field to cross the Step 17 schema seam; no production setting or
application configuration is introduced or migrated.

Discovery confirmed the existing loader, capability registry, knowledge candidate
path, Configuration Service, structured module projection and generic 15UI
renderer already compose. One concrete compatibility fix preserves the package
version in v2 context candidates by reading Core's validated registration rather
than an absent contribution field. Approval, privilege and execution flow remain
unchanged. Knowledge is descriptive reference data, never a System Model fact.

The existing generic 15UI renderer consumes the real inspection record in the
acceptance fixture. A live Modules panel is not added; default UI consolidation
remains Step 20. Schema admission/inspection is proved, not a general module
write CLI or application apply workflow. Reviewed Bash modules are trusted code,
not a security sandbox.

The starting checkout was clean `igor2` at `77b2e40`. A read-only remote query
confirmed `origin/igor2=77b2e40` and unchanged `origin/master=852ce8f`. The
Boundary 1 content reconciliation of the two unmatched master documentation/
orchestration commits remains applicable; no missing runtime baseline was
identified. The existing focused module/configuration/context/interaction
checks passed: 100 tests plus 16 subtests.

**EXECUTION evidence (2026-10-02):**

| Proof/check | Result |
|---|---|
| Contract | Ten composition cases cover valid/idempotent individual module admission, rejected Module API/package/capability versions and foreign schema identity before source, typed capability discovery/output, disabled-owner exclusion, invented capability rejection, exact approval digest enforcement, and required-privilege unavailability without a reviewed Core adapter. Negative assertions check explicit exit status. Existing Boundary 1 cases retain invalid typed-output and version-recovery proof. |
| Vertical slice | The copied System package crosses actual registration, capability inspection, knowledge candidates, Context Routing, configuration declarations, Core service inspection and existing generic 15UI `panel_rows`. The real typed memory READ separately crosses the canonical dispatcher, observer, verification and durable History with System/package/version provenance. No policy or privilege stub grants admission. |
| Inspection | Active and disabled lifecycle/declaration states remain structured. Host knowledge keeps owner, source identity and package version in context selection with `authority_class=reference`. The test-only field resolves a declared default with absent desired state, unobserved runtime and unverified application. Rendering, context selection and inspection preserve the entire fixture file inventory/hashes and model bytes. |
| Configuration ownership | A schema is admitted through Core's owner-stamped contribution index and consumed by Step 17, not a module storage path. Forged owners/targets and executable configuration invocation are rejected. Validation/inspection create no desired store or package writes; no general write/apply capability is added. |
| Migration/recovery | No production schema, application setting or persistent layout changes. Existing v1 compatibility and Boundary 1 History recovery remain tested. The read-only composition slice requires no data migration; actual application rollback, resource bindings and detach recovery remain Boundary 3 prerequisites. |
| Python regression/lint | Full Python: 443 passed plus 321 subtests; the same four baseline Guide/Assist automation cases fail, with no additional failure or startup timeout. The full run is not green. Full Ruff output is byte-identical to Boundary 1: 142 existing findings. |
| Bash regression | All 207 BATS pass with no skips: 162 module cases (including all ten new composition cases and retained Boundary 1 acceptance) plus 45 relevant Core context-refresh, host-context and safety-dispatch cases. The unmodified execution-policy/approval/privilege paths retain their regression evidence. |
| Bash syntax/lint | `context.sh` passes Bash syntax; CI ShellCheck finds only its three unchanged SC2155 warnings, confirmed against HEAD. The new composition BATS passes CI ShellCheck after converting bare negation into explicit exit-status assertions. |
| Documentation | All 67 local references in changed documents resolve; whitespace checks pass. The roadmap and module/configuration documentation distinguish this integration proof from production migration and later application ownership. |

Boundary 3 still requires selection of a narrow non-secret application setting,
review of existing writers/ownership, a canonical approved apply capability,
independent readback, desired/observed/consumed distinction, History and declared
recovery. General bindings/resource ownership, complete detach and Q007 are
not closed by this integration proof. No Nextcloud rewrite/split, broad module
migration, marketplace, hot unload, automatic dependency installation or
external trust system is introduced. Boundary 3 was not started by this earlier
result; the owner-authorized System workflow is recorded above.

Boundary 2 is complete within this integration-proof scope. The result stops
here for Project Owner review; it does not close the whole Step 18 roadmap item
or automatically begin Boundary 3.

## Contract-driven Operator Surface — bounded implementation candidate

A bounded interaction slice now projects the existing module/contribution,
capability and configuration registries into a disposable operator-surface
snapshot. The full-screen TUI keeps `Ctrl+P` for local session commands and uses
`:` for deterministic dotted namespace discovery. This is a projection over
existing owners, not a Module API menu contribution or a second registry.

Capability leaves return through the existing `run_capability` dispatcher.
Zero-input leaves can be submitted directly; required input remains an explicit
operator JSON draft. Provider ambiguity is preserved rather than guessed.
Checks, observers, configuration, knowledge and other non-capability
contributions are browse-only in this first slice. Core configuration exposes a
read-only declaration query that creates no store; v2 module configuration
schemas are projected from owner-stamped contribution records.

This work does **not** advance Step 18 Boundary 2/3, migrate the v1
`nextcloud_docker` menu, implement staged Apply/restart UX or make the TUI the
default launcher. It establishes the shared discoverability seam those later
workflows can consume. Focused projection/backend/TUI/configuration tests are
included on the implementation branch. Runtime pass counts are intentionally not
claimed here because the repository CI workflow currently targets pull requests
to `master`/`main`, not `igor2`, and this environment cannot fetch the branch
for local execution.

## Step 18 Boundary 1 — module contract completion

The Project Owner approved the Step 18A discovery architecture (D060) and
authorized three sequential boundaries with an evidence stop after each.
This entry covers **Boundary 1 only**. Composition prerequisites (including
Q007), real module configuration migration and the reversible Nextcloud proof
remain outside this result. No bundled application is split or rewritten.

The starting checkout was clean `igor2` at `227d5c2`. A read-only remote branch
query confirmed `origin/igor2=227d5c2` and `origin/master=852ce8f`. Master is not
an ancestor; its two unmatched commits contain an obsolete roadmap and older
orchestration policy already superseded by this branch's design authority and
current `.codex` policy. This is content reconciliation, not a merge or a claim
that the ancestor check passed. The earlier Step 17 wording is corrected below.

The bounded change completes supported capability versions 1/2, closed typed
version-2 outputs, exact request/plan version checks, one structured module
inspection projection and read-only detach accounting. The existing `system`
memory refresh is the real version-2 reference; its static host knowledge is
packaged instead of depending on an ignored local asset. V1 capabilities and
the combined `nextcloud_docker` deployment retain their compatibility paths.

Static inspection never sources module code/legacy configuration, evaluates
process activation, refreshes an observer or initializes private state. A
loaded backend can project its current registry/model snapshots. Detach
accounting exposes known contributions/dependencies and unknown binding,
resource, session and responsibility inventories. It is not a detach executor
or completion certificate. 15UI may consume the shared records; no module UI
or default-interface cutover is added.

Baseline evidence before runtime edits: 28 focused module/capability tests
passed. Full Python reported 424 passed, 321 subtests passed and the same four
Guide/Assist automation failures recorded for Step 17. Full Ruff reported the
same 142 existing findings. Personal ignored configuration was not rewritten.
The Boundary 1 proof covers the following bounded acceptance evidence:

| Proof/check | Result |
|---|---|
| Contract | Capability versions 1/2, closed typed outputs, unsupported/mismatched consumer pins, malformed/duplicate/non-finite results, bounded values and Core-owned result status are covered. V2 privileged declarations remain unavailable without a typed Core adapter. |
| Regression | Full Python: 443 passed plus 320 subtests; the same four baseline Guide/Assist automation failures remain. One additional startup subtest exceeded its unchanged 20-second subprocess timeout during concurrent validation. After concurrent suites finished, that exact startup test passed unchanged: 1 passed plus 2 subtests. The unmodified full run was not green; the timeout did not reproduce in isolation. Full Ruff's 142 diagnostic identities match the baseline, with none added or removed. |
| Bash regression | Full runner passes all five groups: 46 Bash checks, 46 render checks, 305 core BATS, 152 module BATS and 40 integration BATS. Two existing core cases skip for unavailable GPG agent and `hostname -I`. The focused dispatch/History/module-v2 suite also passes all 58 BATS. |
| Vertical slice | Seven new dispatch/inspection BATS pass. The real `system.host.memory.refresh` version-2 operation returns a valid typed result, refreshes the existing observer and records provider/package/version plus verification in durable History. A CHANGE fixture proves invalid output preserves an actual effect and execution completion, reports unknown verification and excludes rejected raw data from results/History. |
| Inspection | Static CLI inspection executes no module code, migrates no omitted policy and creates no runtime files. Runtime projection reads existing facts without another observer, filters owning-service rows and redacts sensitive fact values. Detach reports known contributions/dependents, retained records and explicit unknown inventories with `ready=false`. Eleven inspection unit tests pass. |
| Migration/recovery | No persistent backend/layout migration is introduced. V1 capabilities remain compatible; `nextcloud_docker` stays v1. Retained version-1 History remains inspectable and reconciliation refuses to reinterpret it through version 2. The `system` package validates when reconstructed from tracked files plus its declared host knowledge asset, which is included in this commit. This proves package delivery, not application rollback or complete detach. |
| Python lint/compile | Changed/new capability, module-contract and inspection helpers/tests pass scoped Ruff; runtime helpers compile. Full Ruff retains 142 baseline findings. `tool_input.py` retains its existing SIM103 finding. |
| Bash syntax/lint | Changed scripts pass syntax checks. Capability/module-loader adapters and the new acceptance BATS pass CI ShellCheck flags. Six unchanged whole-file warnings remain in safety, startup and the older History fixture. |
| Documentation/diff | All 119 local documentation references resolve; whitespace checks pass. Accepted D060 and the bounded public contracts, migration disposition and roadmap boundaries are documented. |

This closes **Boundary 1 only**. The approved architecture is retained; no
composition/binding authority or application migration was introduced. Boundary
2 and Boundary 3 are not started. The boundary stops here with its evidence for
Project Owner review rather than automatically expanding scope.

## Step 17 Configuration Ownership and Schema Foundation — bounded implementation

The Project Owner accepted Step 17A's architecture and authorized the bounded
foundation plus the Core `ai.verbose` vertical slice. D059 and
[CONFIGURATION.md](CONFIGURATION.md) are the accepted boundary. The working
baseline was clean `igor2` at `619d0cd`. The original ancestor statement was
incorrect: `master` and `origin/master` are not ancestors. Step 18's read-only
remote check confirmed `igor2=227d5c2` and `master=852ce8f`; the two unmatched
master commits contain an obsolete roadmap and earlier orchestration policy,
superseded on this branch by the accepted design documents and current `.codex`
policy. No missing runtime baseline change was identified. Remote freshness was
not checked during Step 17 itself.

Configuration owns validated desired values, resolution, schema admission,
private persistence, precedence, provenance and recovery. It does not own
System Model observations or Operational History outcomes. Canonical
capabilities retain authorization, application and verification; configuration
stores secret references only. 15UI keeps its existing typed proposal boundary.

Scope excludes real module/Nextcloud configuration, secrets, host thresholds,
broad environment migration, generic settings UI, inheritance, external secret
managers, agents and Steps 18/19/20. Q007 and Q012 remain open. The full
Ownership Foundation gate is not closed by this slice.

The foundation is implemented in `configuration_schema.py`, `configuration.py`
and its Bash adapter. Version-1 declarative module schemas are admitted through
the existing contribution index; no bundled module settings migrate. Read-only
`--configuration` status/list/inspect/export/validate creates no configuration
store and runs no legacy shell. Private SQLite commits validate the candidate,
bind to revision plus a frozen state token, and retain JSON recovery. Recovery
into an empty backend cannot admit an old proposal merely because an integer
revision repeats.

Existing verbose commands use canonical CHANGE admission and History. The
successful desired write verifies persistence only; the AI session then consumes
the exact revision and invokes separate READ verification of that session.
Inspection continues to report observed state unavailable and application
not verified; it never manufactures a System Model fact or global runtime
success. Declined changes leave the session and desired store unchanged. Saving
other AI preferences ceases writing verbose after the explicit single-key cutover.

**EXECUTION evidence (2026-10-01):**

| Proof/check | Result |
|---|---|
| Contract | Closed version-1 schemas, scoped ownership, types/constraints, inactive-owner retention, duplicate/non-finite JSON rejection, secret handles, path validation, domain rejection and concurrent CAS are covered. Focused configuration/startup/privilege checks: 59 passed plus 16 subtests. Module contract tests and all 145 module BATS also pass. |
| Regression | Full Python: 424 passed plus 321 subtests; four existing automation cases fail because the ignored checkout preference selects Guide while they request automatic Assist. The automation implementation and tests are unchanged from HEAD; the existing Guide guard rejects them. All four pass in a separate in-memory harness with explicit test-only Assist configuration: five Bash contexts and eight CLI contexts were adjusted, preserving arguments and installation paths. No repository or personal files changed. No claim of a green unmodified full Python run is made. |
| Bash regression | Full runner passes all five groups: 46 Bash checks, 46 render checks, 305 core BATS, 145 module BATS and 40 integration BATS. Two existing core cases skip for unavailable GPG agent and `hostname -I`. After the recovery/startup fixes, 49 affected dispatch/event BATS pass. |
| Vertical slice | Real `ai.verbose` canonical write, desired verification, session consumption, separate session verification, process reopen and legacy-writer retirement pass; the decline fixture proves nonexecution without session mutation. History links the desired change to the canonical operation. |
| Inspection | Absent storage creates nothing. Owner, scope, desired/default/resolved source, revision/state token, safe secret status, operation reference and History availability are queryable. Observations and application remain explicitly separate. |
| Migration/recovery | Literal legacy precedence and first-write cutover, prior-value recovery, export/scope validation, retained damaged backend/empty-store restore, initialization/backup failure and stale proposals across recovery pass. Private paths reject unsafe links/permissions/corruption/versions. Trusted linked Core defaults remain readable. No other settings or secret material are copied. |
| Python lint/compile | All five changed/new Python files pass focused Ruff; runtime helpers compile. Full Ruff retains the same 142 baseline findings in unrelated files. |
| Bash syntax/lint | All changed scripts pass syntax checks. Configuration/capability/module-loader adapters and changed module BATS pass CI ShellCheck flags. `igor.sh` retains its two existing SC2155 warnings. Whole-file `core.sh` lint times out, matching its previously documented resource limitation; its exact changed regions pass separately with CI flags. |
| Documentation/diff | 107 local documentation references resolve; diff/whitespace checks pass. Final staged scope is reviewed before the scoped commit. |

Baseline affected tests before implementation were 53 passed plus 16 subtests;
those are not presented as evidence of the new implementation. Personal ignored
configuration is preserved, and no unrelated lint/safety behavior is repaired.
This closes only the owner-authorized configuration foundation and Core slice;
the original roadmap's Relationships & Deployments Step 17 remains FUTURE.

## Step 16 Architecture Integration Review and Readiness Assessment — complete

The completed read-only review is finalized in
[ARCHITECTURE_READINESS.md](ARCHITECTURE_READINESS.md). The 15-series foundations
compose coherently; Step 20 can build on existing UI and owning inspection
contracts. Configuration ownership, a representative application workflow and
default-launch cutover evidence remain readiness gaps. Legacy paths, AI helper
coverage and knowledge-delivery risks remain documented, with explicit
deferrals and Step 17 prerequisites.

Closure is documentation-only: references, formatting, repository consistency
and the final diff are checked. Under [EXECUTION.md](EXECUTION.md), runtime
contract/regression, a new vertical slice, a new inspection surface and
persistent migration/recovery proofs are not applicable to this review artifact:
no runtime contract, behavior or persistent layout changes. Existing foundation
evidence is inherited, not rerun. This completes the owner-scoped Step 16 review;
the roadmap's Baselines implementation remains FUTURE. At that review's closure,
Step 17 and Step 20 were not started, and the TUI default cutover was not approved.
## Knowledge import / module synthesis direction — accepted, not implemented

D057 and [KNOWLEDGE_IMPORT.md](KNOWLEDGE_IMPORT.md) now define the architecture
for turning heterogeneous operational material into Igor-managed knowledge or
module candidates. Supported source classes include installation docs, scripts,
guides/runbooks, native Igor modules, Agent Skills/AOH, ServerMind/Steward
material and local evidence-backed learning.

This changes no runtime authority. Import is reference/candidate normalization
with provenance; executable promotion must still satisfy the normal Module API,
capability, compatibility, approval, privilege and verification contracts.
Portable package content remains separate from machine-specific
binding/configuration. Step 22 owns future import/authoring tooling; a public
registry/signing service and live external-system interoperability remain later
work.

## Step 15A Persistent Identity & Memory Foundation — architecture gate

**Step 15A is accepted and remains an architecture-only gate.** Its contract is
[PERSISTENT_MEMORY.md](PERSISTENT_MEMORY.md), with D048–D054 in
[DECISIONS.md](DECISIONS.md). It resolves Q003 without turning the current
System Model, AI audit, recovery journal or Step 13 event buffer into a general
memory database.

## Step 15 implementation order — accepted planning

After the merged 15A architecture gate, the bounded sequence is:

```text
15B Operational History
-> provider-neutral Decision/Judgment Contract
-> 15UI Interaction Surface Foundation
-> 15C Durable Investigations
-> 15D Context Relevance and Model Role Routing
```

15UI is defined in [INTERACTION_SURFACE.md](INTERACTION_SURFACE.md). It is a
frontend/interaction foundation over shared backend contracts: mouse scrolling,
keyboard navigation and selection, explicit focus, a toggleable control panel,
generic typed input/property rendering and visibility into backend-reported AI
role/provider state. It does not implement model routing, named cheap models,
investigation storage, Nextcloud-specific settings or backend authority.

The small Decision/Judgment Contract before 15UI/15C is accepted in D055 and
implemented in-memory; [JUDGMENT_CONTRACT.md](JUDGMENT_CONTRACT.md) defines its
provider-neutral record, tool-free adapter, abstain/unknown, provenance,
validation and deterministic fallback. It does not select Jet/Laya. Step 15D
remains the owner of context relevance/model routing policy.

The selected boundary keeps the System Model as current-state projection.
Configured/user-declared/desired/responsibility state survives through its
authoritative source; inferred state is recomputed; old observed snapshots are
never fresh merely because they were persisted. Historical observations,
execution, verification and outcomes belong to Operational History.

New durable cross-subsystem records use explicit scope + existing object ID
references. Capability history names the canonical capability/version and
selected provider identity/source; handler names, commands, paths and UI labels
are implementation evidence only. History attaches to the canonical execution
boundary rather than relying on transient domain-event delivery. Later
investigations, resumable work, deployments/relationships and learning remain
separate authorities that share references/provenance.

Step 15A selects no public database schema. Step 15B implements its bounded
Operational History service; runtime and callers use versioned records instead
of backend tables/paths. The implementation and evidence are recorded below;
the accepted Step 15A decisions are unchanged.

## Step 15D Context Relevance and Model Role Routing — implemented; validation complete

**Accepted boundary:** D057 and [CONTEXT_ROUTING.md](CONTEXT_ROUTING.md) extend
the existing selector/provider path. Selection is deterministic by default;
optional D055 ranking is digest/schema-bound assistance within relevance tiers,
with abstention, invalid output and low-confidence fallback. Initial roles are
reasoner, summarizer and context_ranker with explicit administrator bindings,
inspectable rules/reasons and no provider optimizer or cross-provider fallback.

**Contract/inspection:** bounded candidate metadata includes source, scope,
freshness, provenance, sensitivity, authority class, size/estimated tokens and
content digest. Included/excluded reasons, budgets and role-selection rules are
read-only operational provenance through the existing private audit, headless
`--context last`/`select` and 15UI Context / Routing projection. Preview is
distinguished from an actual prepared request. Existing `--context inspect`
remains compatible. Current protocol conversation groups are mandatory.

**Vertical slice:** a real local Operational History episode is referenced by
a durable investigation; explicit scoped selection crosses the existing request
boundary into a mocked provider HTTP payload, then the real frontend event owner,
panel renderer and headless inspection. Source storage bytes remain unchanged;
inactive context is excluded with its reason. No live external provider or
terminal-interaction claim is made by this fixture proof.

**Migration/recovery:** source is existing settings/context/audit behavior;
omitted role bindings inherit the existing configured primary model for reasoner
and summarizer. The old vendor-specific summarizer substitution is removed.
Existing memory selection/inspection, v1 Nextcloud and classic/headless paths
remain. Owner-stamped static knowledge replaces equivalent aggregate knowledge
on the runtime path; legacy sources remain bounded labeled candidates where no
typed replacement exists. No new durable context store, scope allocation,
history/investigation schema, import or dual write exists. Restart cannot replay
authority from disposable decisions; optional existing audit retention is
diagnostic provenance only, never automatic durable knowledge or memory.

**Authority:** selectors/routing have no executor, approver, privilege, observer
refresh or System Model writer. Existing AI-disable, privacy, active-owner,
tool-validation, Guide/Assist/Executive, exact `YES` and PTY approval/security
boundaries remain authoritative. Helper requests are tool-free and do not collect
additional machine/investigation context. Judgments remain reference-only.

**Validation gate (2026-10-01):**

| Check | Result |
|---|---|
| Focused contracts/security | 84 Python tests and 76 subtests passed; 59 focused Bash checks passed. After correcting source-time provenance, 67 affected Python tests and 37 subtests passed, including the additional timestamp regression. |
| Full Python regression | 388 tests and 321 subtests passed. The additional timestamp regression was added after collection and is covered by the affected run above. |
| Full Bash regression and affected correction | All five groups ran: 46 core Bash checks, 46 render checks, 305 core BATS, 141 module BATS and 40 integration BATS. Initial aggregate exit was 1: two obsolete assertions expected the old event vocabulary and aggregate knowledge envelope. Both assertions were corrected; all 32 tests in their affected files then passed. All remaining full-run cases passed, with two existing core skips for unavailable GPG agent and `hostname -I`. |
| Python lint | New/extended selector, routing adapters and focused tests pass Ruff. Full scan retains exactly 142 baseline findings in 28 files. |
| Bash syntax/lint | Changed scripts pass syntax checks; the two corrected BATS files pass ShellCheck. CI-configured ShellCheck on other changed scripts reports only five existing SC2155 warnings. Whole-file `core.sh` ShellCheck is unavailable: both current and unchanged HEAD are killed with exit 137. Its exact changed regions pass separately with CI flags; full syntax and regression coverage also pass. |
| Compile/docs/diff | Changed Python files compile; all 99 local documentation references resolve; diff/whitespace checks pass. Final staged scope is reviewed before the scoped commit. |

Contract, regression, vertical slice, inspection and migration/recovery are the
five required [EXECUTION](EXECUTION.md) evidence categories, demonstrated above.
The whole-file ShellCheck resource limitation is recorded rather than claimed
as a passing check; scoped changed-region lint supplies the affected static gate.

**Baseline:** clean active `igor2` at `99d65a1`; the prerequisite commits are
present. The two local master documentation/orchestration commits outside ancestry
retain the reconciliation recorded in Step 15C; no remote-freshness claim or
temporary checkout is made.

**Deferrals/Step 20:** automatic ranker/scout calls, autonomous gathering, agents,
embeddings, compression services, provider optimization/expansion, background AI,
Jet/Laya and Step 20 are excluded. This implementation supplies Step 20's context/
routing dependency; normal-workflow readiness and default-launch consolidation
remain separate gates. No Step 20 work starts here.

## Step 15C Durable Investigations — complete

The Project Owner confirmed D056's bounded architecture and the explicit rule
that conclusions remain investigation-scoped findings. The
[Investigation contract](INVESTIGATIONS.md) owns knowledge organization: lifecycle,
hypotheses, evidence references, validated judgments, findings and uncertainty.
Creation owner/provenance grants neither operational authority nor responsibility.

**Contract/persistence:** version-1 records share 15B's stable local scope through
its service boundary. Private versioned JSON uses locking, validated atomic
replacement, private permissions and fail-closed version/corruption checks.
History's database/schema and operational episodes remain unchanged. Export and
validated empty-destination/idempotent restore preserve investigation identity;
Operational History scope must be recovered first for a continuation.

**Inspection/vertical slice:** bounded Python and headless data operations bypass
module/config/AI startup. The existing 15UI panel loads investigation records
through the public read-only CLI and existing structured renderer. A lifecycle
can retain related history, supporting/contradicting evidence, judgment
abstention, conclusions and unresolved questions across restart/closure/reopen.
Inspection performs no refresh, verification, model call or storage allocation.

**Migration:** source is no investigation store; first valid creation initializes
version 1, reusing history scope. No legacy/chat/observed data is fabricated or
imported; there is one investigation authority, no dual write or history schema
migration. Unknown/corrupt stores remain intact. Recover an exported document
into a fresh destination sharing the restored history scope; no guessing repair.
[LEGACY.md](LEGACY.md) records unchanged compatibility surfaces.

**Authority:** no capability execution, desired-state change, approval, privilege,
module activation, System Model writes/freshness, automation, verifier changes or
background loop. Hypotheses/findings/creation ownership never silently cross
those boundaries. Judgment attachments validate existing request/record binding
and retain provenance/abstention without invoking a model or promoting truth.

**Focused validation:** 29 investigation/service/headless/panel tests and 84
subtests passed; 22 existing interaction tests and 16 subtests passed; 34
Operational History/Judgment tests and 92 subtests passed. New Python files pass
Ruff. A concrete secret-metadata regression also passes after rejecting known
secrets in object references and judgment schema keys. Fixture failures in the
initial focused run were corrected to use valid history provenance and a real
stale System Model observation; no unrelated runtime behavior changed.

The tests prove explicit transitions, terminal immutability/reopen, retained
uncertainty, typed scoped references, judgment validation/abstention, strict
version/schema/size checks, private storage, concurrent process updates, atomic
replacement failure recovery, idempotent export/restore and no authority/fact
mutation. The real CLI/panel slice displays retained history/evidence, hypothesis,
abstaining judgment, finding/question and provenance with persisted bytes
unchanged.

**Single final validation gate (2026-10-01):**

| Check | Result |
|---|---|
| Python regression | `uvx --offline --from pytest pytest -q`: 371 tests and 321 subtests passed; no failures/skips. |
| Bash regression | `bash tests/run_all.sh`: all five groups passed, zero failed/skipped groups; 46 core Bash checks, 46 render tests, 305 core BATS, 141 module BATS and 40 integration BATS. Two existing core cases skipped for unavailable GPG agent and `hostname -I`. |
| Python lint | New service/tests pass Ruff; full `ruff check .` retains exactly 142 existing findings in 28 files. Changed TUI/history files retain their eight baseline findings; no new lint findings. |
| Bash lint/syntax | Changed Bash syntax passes. CI-configured ShellCheck retains two existing SC2155 warnings in `igor.sh`; new bridge has no warnings. |
| Compile/docs/diff | All changed Python files compile; all 88 local documentation references resolve; final staged diff/whitespace and scope checks pass. |

All five EXECUTION evidence categories are satisfied for this bounded milestone:
contract, regression, real CLI/history-linked vertical slice, read-only inspection
and tested persistence/export recovery. No missing migration/import is claimed:
there was no prior investigation authority to migrate.

**Baseline:** active clean `igor2` started at `c58ae37`; completed 15B, D055 and
15UI are present. Local `master` has two documentation/orchestration commits
outside ancestry, already reconciled by the later local Codex policy and
canonical Igor 2 roadmap. This task preserves that intended functional baseline;
no temporary checkout or remote-freshness claim is made.

**Deferrals:** 15D selective retrieval/relevance/model routing remains a separate
owner gate. No agents, recursive investigations, remediation/self-healing,
workflows, scheduling, monitoring, remote investigations, relationships/deployments,
learning, named models or Step 20 changes. **15D is unblocked at the dependency
level** by completed 15B, D055, 15UI and 15C. Its own scope/architecture approval
remains a separate owner gate; no 15D work is started here.

## Step 15UI Interaction Surface Foundation — complete

The bounded [interaction contract](INTERACTION_SURFACE.md) extends the existing
`--ai-tui`; default launch and classic/headless interfaces are unchanged.
Frontend focus, selection, viewport, panel and property drafts are disposable
presentation state. They cannot change policy, module activation, facts,
automation, history, approval, privilege or provider routing.

**Primitives/contract:** `core/ai/interaction.py` provides explicit disposable
focus/panel state, strict text/enum/boolean/integer/number property schemas,
detached typed proposals and bounded secret-safe structured rendering.
`core/ai/tui.py` integrates them with mouse-wheel and keyboard output navigation,
visible LIVE/history status, input/output/panel focus and movable panel selection.
Tab/Shift+Tab cycles focus, Ctrl+B toggles the panel, Ctrl+F returns to latest;
output arrows/Home/End scroll without changing the draft. Schema carries no
command, storage location or default configuration value.

**Vertical slice/inspection:** the existing AI settings owner receives proposed
non-secret semantic values through its existing commands and returns a snapshot.
Recent Operational History uses its public read-only CLI; session/provider/model
and execution provenance use the existing frontend projection. No subprocess
System Model query is presented as current session truth. Unsupported live
model-role/judgment feeds and configuration owners remain unavailable.

**Migration/recovery:** no persistent layout change, history store, configuration
writer or approval state machine is introduced. Panel reopening and terminal
resize preserve the backend projection and composer. Frontend restart starts
with presentation state and reprojects ordered events; it cannot replay a draft,
selection, approval or property write. Existing PTY sudo and conversational
choice handling retain their owners. LEGACY keeps the existing interfaces until
Step 20/23; no compatibility path is retired in 15UI.

**Validation evidence (2026-10-01):**

| Check | Result |
|---|---|
| Focused interaction/TUI gate | 92 tests and 32 subtests passed across the new interaction fixtures and existing TUI, colors, PTY, privilege, settings and Step 7 suites. |
| Single final Python regression | `uvx --offline --from pytest pytest -q`: 342 tests and 237 subtests passed; no failures or skips. |
| Single final Bash regression | `bash tests/run_all.sh`: all five groups passed, zero failed/skipped groups; 46 Bash core checks, 46 render tests, 305 core BATS, 141 module BATS and 40 integration BATS. Two existing core cases skipped: GPG agent and `hostname -I` unavailable. |
| Lint | New helper/tests pass Ruff. Repository-wide Ruff reports 142 existing findings in 28 files, down from 144; the changed TUI retains three baseline findings (EXE001 and two SIM102). No new lint findings; unrelated debt retained. No shell changes, so additional syntax/ShellCheck coverage is not applicable. |
| Compile/references/diff | Changed Python files compile; all 53 local documentation references resolve; final diff/whitespace checks pass. |

Focused tests prove all five controls, detached proposals, malformed/unknown
payload rejection, hidden secrets, visible focus and selection, keyboard/wheel
navigation, panel reopen/resize and preservation of drafts. Real backend
fixtures persist a typed temperature setting and consume its snapshot, inspect
a durable history episode without modifying any stored bytes, and retain
headless absent-store behavior. Approval/question, PTY and sudo regressions
remain green; AI role/provider/model display sends no routing commands.

The five EXECUTION proof categories are satisfied for this bounded milestone.
There is no persistent layout change, so storage migration is not applicable;
presentation recovery and no stale-intent replay are tested instead. Work used
the clean active `igor2` checkout at `4f2d4b8`, with local `master` an ancestor.
No temporary clone or remote-freshness claim was needed.

At 15UI closure, 15C became unblocked at the dependency level by completed
15B, D055 and 15UI. The separate Step 15C evidence above records its subsequent
implementation and closure gate.

**Deferrals/next gate:** 15C owns durable investigations; 15D owns relevance and
model routing; Step 20 owns default-TUI transition and consolidated mature
subsystem surfaces. No Nextcloud settings, remote-host UI, unattended CHANGE,
Self-Healing v2, provider solver or named model policy is added.

## Decision/Judgment Contract — complete

The Project Owner confirmed D055's bounded interface after discovery.
`core/ai/judgment.py` implements one closed version-1 request/record contract,
caller-supplied kind/version/output schema and an injected tool-free adapter.
It reads no runtime state and has no operational integration or persistence.
Igor stamps input digest/references, invocation identity/provider/model and
timestamps. Valid, abstain, unknown, invalid output, provider failure,
unavailable and timeout remain separate; a validated deterministic default
handles every nondecision without another model call.

**Authority proof:** focused fixtures retain a stale System Model fact and
unchanged capability registration/provider, CHANGE tier, required privilege,
preconditions, verification and recovery despite hostile schema-valid reference
output claiming approval/freshness/authority. The real `ai_execute_tool`
dispatcher rejects a judgment before approval/authentication or execution.
Judgment records cannot be spliced into the closed tool grammar. The service
has no activation, automation, secret-access or state-writer interface.

**Contract/vertical-slice proof:** focused tests exercise request -> injected
adapter -> Igor record -> read-only revalidation -> deterministic fallback,
including local/remote/future provider identities using the same schema.
Malformed/unsupported versions, bounded input/output/schema, invented evidence,
provenance spoofing, abstention, provider failures and timeout are covered.
Live inference and an operational consumer are deliberately excluded by owner
approval; the fixture slice proves the complete authorized interface.

**Inspection:** `validate_record(record, request)` retains provenance, timestamps,
status, validation and reference payload without dereferencing or writes.
**Migration/recovery:** no persistent layout or existing consumer changes;
there is no migration, restart replay or second history store. Contract/version
failures use deterministic fallback. LEGACY dispositions remain unchanged.

**Validation evidence (2026-10-01):**

| Check | Result |
|---|---|
| Focused contract | 12 tests and 76 subtests passed: schema/version, bounded payloads, explicit abstain/unknown, invalid output, failures/unavailable/timeout, provenance retention, provider independence, authority separation, real dispatcher rejection and deterministic fallback. |
| Single final Python regression | `pytest -q`: 320 tests and 221 subtests passed; no failures or skips. |
| Single final Bash regression | `bash tests/run_all.sh`: all five groups passed, zero failed/skipped groups; 46 Bash core checks, 46 render tests, 305 core BATS, 141 module BATS and 40 integration BATS. Two existing core cases skipped: GPG agent and `hostname -I` unavailable. |
| Lint | New Python files pass Ruff. Repository-wide `ruff check .` reports 144 existing findings in 28 unchanged files; each affected file was compared byte-for-byte with HEAD. Baseline lint debt is retained, with no new findings or claim of a green repository-wide lint result. No Bash files changed, so new ShellCheck coverage is not applicable. |
| Compile/references/diff | New Python files compile; all 59 local references across changed documentation resolve; final diff/whitespace checks pass. |

The scoped contract, regression, fixture vertical slice, inspection and
nonpersistent recovery evidence satisfy this gate. Repository-wide lint debt
is a recorded baseline failure, not repaired or hidden by this task. Work used
the clean active `igor2` checkout at `077c5cd`, with local `master` an ancestor;
no clone, remote-baseline claim or existing runtime contract replacement.

**Deferrals/next gates:** no transport wiring, role registry/requirements,
Jet/Laya, provider solver, routing, persistence, agent, operational capability,
15UI, 15C or 15D implementation. D055 supplies the judgment dependency for
15UI/15C. 15UI is unblocked by this gate; 15C's judgment dependency is satisfied,
but the accepted order still places 15UI before 15C. 15D owns actual
relevance/context and model-routing policy. No later step was started.

## Step 15B Operational History — implemented; historical validation evidence

The bounded service is implemented under the accepted D048–D054 contract.
[Operational History](../operational_history.md) defines the version-1 episode,
headless commands, private backend and the ten-question architectural review.
No Step 15A decision was redesigned. Later Decision/Judgment, 15UI, 15C and 15D
remain separate gates.

**Canonical boundary:** `ai_execute_tool` durably admits the operation before
approval, privilege authentication, compatibility backups and provider effects.
The existing executor checks the approval digest and current registration,
atomically binds/marks the attempt running, records provider completion, then
verifies. `_igor_capability_publish_result` is the single terminal hand-off for
execution and nonexecution. History never dispatches; Step 13 still projects
the result transiently. Automation retains its Step 14 claims and references
the canonical episode; the System Model remains current-state projection.

**Private storage:** Python's standard-library SQLite provides atomic transitions,
concurrent process writes and indexed episode/correlation inspection without
rewriting an unbounded history on every transition. Tables and paths remain
private behind the service. Version 1 persists one opaque local scope and random
operation IDs; reset preserves scope and never recycles operation IDs. Private
permissions, symlink/owner guards, version/schema checks and corruption checks
fail closed. No remote identity or fake historical migration is introduced.

**Lifecycle/recovery:** admitted, running, provider-complete and terminal states
extend the existing execution boundary. A dead running owner becomes
`interrupted_unknown`; admitted work is known never to have started. Inspection
projects this without writes or verification. Explicit recovery records it and
can query the existing matching unprivileged service-state verifier. It never
retries the provider or turns a passing current postcondition into claimed
execution success. Unsupported/inactive/mismatched verification leaves explicit
operator recovery required. Versioned export and validated empty-destination
restore preserve episode/scope identity, normalize unfinished claims and support
idempotent re-entry. Corrupt stores remain intact for diagnosis.

**Vertical slices:** the real `system.host.memory.refresh` READ records canonical
capability/version/provider, local `host:local`, provenance, execution,
verification and outcome, then reopens/inspects the same episode. An isolated
service CHANGE checks the durable running record inside its fake platform
provider before the effect. Normal, failed and unverified results are distinct.
The crash fixture kills only its isolated process group after the disposable
effect; restart shows uncertainty, matching verification adds evidence and
repeated recovery leaves the effect count unchanged. Inactive providers retain
uncertainty. Approval decline and failed sudo authentication never reach it.

**Compatibility cutover:** canonical operations suppress duplicate command-journal
records. The bounded AI audit remains a diagnostic projection/reference for
`--ai last`; raw/v1, Diagnose, backup and rollback journal callers remain legacy
sources. Backup manifests retain artifact ownership. Chat `history`/`replay`
retain session views. None is imported as complete episodes or can confer
execution authority. [LEGACY.md](LEGACY.md) records each disposition.

**Validation evidence:**

| Check | Result |
|---|---|
| Focused history service | 22 tests passed: closed schema, scoped identity, local scope/reopen/reset, handler/path/UI independence, frozen proposal binding, redaction including short secrets and secret-bearing keys while preserving generated IDs/protocol meanings, corrupt/unsupported versions retained, concurrent process writers/claims, read-only queries, export/restore idempotency and stdin documents over 128 KiB. Duplicate JSON fields and non-JSON numbers fail before store creation. |
| Canonical vertical slices | 11 history dispatch BATS cases passed, including the actual post-effect crash, no blind retry, supported/unavailable reconciliation, approval decline, privilege authentication failure, provider/verification distinction, post-effect write failure, legacy journal cutover, headless inspection and existing plan references. |
| Full Bash suite | `bash tests/run_all.sh`: all five groups passed, zero failed/skipped groups; 46 Bash core checks, 46 Python render tests, 305 core BATS, 141 module BATS and 40 integration BATS. Two existing core cases skipped: unavailable GPG agent and `hostname -I`. Capability, approval/safety/privilege, recovery, Step 13, module and integration behavior remains green. |
| Full Python coverage | 293 discovered unittest cases plus 15 nested/function-style cases passed (308 total). This includes capability/runtime, deterministic verification, Step 13 events and all Step 14 automation tests; real automation retains the canonical episode, claim, schedule slot and event causation references. `pytest` is unavailable; no Python test content was omitted. |
| Syntax/compile/references | Changed Bash syntax, Python compilation across `core`/`tests`, documentation references and `git diff --check` passed. |
| Tooling gate | Ruff and CI-configured ShellCheck were attempted but are not installed. Network resolution also prevents refreshing GitHub refs or installing missing tools. No lint success or remote freshness is claimed, and unrelated lint debt was not changed. |

The bounded implementation and behavioral proofs were complete at that
handoff, with lint tools and remote baseline refresh unavailable then. The
Project Owner subsequently authorized the Judgment Contract after completed
15B work. Cached lint/test tools are available for the current task's final
gate. This supersedes the historical hold on beginning judgments; it does not
claim a remote baseline refresh or retroactive lint success.

**Repository baseline:** implementation starts from local `igor2` at `141ff36`,
which contains the intended functional master baseline. Available origin/master
adds orchestration already reconciled here and an obsolete roadmap superseded
by the authoritative Igor 2 documents. Original Git metadata is read-only, so
the feature branch lives in `/tmp/igor-step15b`; fetching there fails DNS.
The existing ignored system host knowledge asset was copied into the isolated
checkout for equivalent module validation, without changing its tracking policy.

## Step 14 Automation Engine — complete

**14A–14E are complete at the bounded unprivileged READ contract.** The authoritative
[AUTOMATION_ENGINE.md](AUTOMATION_ENGINE.md) contract and D044–D047 govern the
implementation. Active v2 module declarations are data-only proposals. The
bundled `system.host.memory.once` proposal targets
`system.host.memory.refresh`; only the explicit local operator
`--automations create` and `enable` path creates and enables Igor-owned intent.
AI text, events and module activation cannot call this authority. CHANGE,
DESTROY, privileged and secret-reference targets cannot be enabled.

**14E conditional READ and recovery:** Version-1 `condition` triggers use a
UTC anchor, a positive polling interval of at most 31,536,000 seconds and one
closed `fact_equals` predicate naming an object ID, property, `observed` state
class, value type and typed comparison value. An explicit due tick reads the
existing owner-aware System Model facts without invoking an observer. Only a
matching `known` fact whose expiry remains in the future at claim time admits
the configured READ. Missing, unequal, stale, inactive, unavailable, invalid
and error facts leave the slot unclaimed. A match still rechecks source,
provider, mode and policy, durably claims the current slot before dispatch,
and enters the existing `run_capability` route through `ai_execute_tool`.
Inspection remains read-only and does not evaluate or refresh the predicate.
Restart does not replay a claimed slot; a later interval may be evaluated
against current facts. No observer scheduler, expression evaluator or durable
history was added.

**14E focused proof:** Condition and System Model tests passed 16 tests and 10
subtests. They cover exact typed success, unequal/unknown/stale/error and
expired facts, wrong-type and malformed predicates, inactive proposal owner,
non-dispatch on false conditions, absence of implicit observer refresh, concurrent
claim prevention and restart. An existing `host.memory` observation admitted
one real `system.host.memory.refresh` through the canonical dispatcher; its
recorded outcome was `success` with `passed` verification and one
`capability.completed` event. Changed-file Ruff, CI-configured ShellCheck,
Bash syntax, Python compile and `git diff --check` passed.
The full `bash tests/run_all.sh` suite passed all five groups with no group
failures; two environment-dependent core BATS cases were skipped (GPG agent
and `hostname -I`). The full Python pytest suite passed 286 tests and 129
subtests. The private version-1 store needed no layout migration; the focused
restart and durable claim checks remain green. Earlier slices continue to
prove Guide mode and active-owner recovery.

**14D event READ and recovery:** Version-1 event triggers fix an exact active
domain event type, optional exact owner/object filters and a bounded minimum
interval at configuration time. The Core subscriber receives only validated
Step 13 envelopes and queues matching signals in bounded, owner-only session
scratch. It does not execute inside publication. A separate in-process drain
rechecks active event type, source proposal, target provider, runtime mode and
READ policy, atomically records a bounded attempt summary, then uses the
existing `run_capability` request through `ai_execute_tool`. Event payloads
cannot supply target inputs. The existing automation run lock prevents overlapping
drains; duplicate event IDs do not launch a second attempt. Completion events
from automation dispatch are dropped by this adapter during the drain.
Pending signals and Step 13 events disappear on restart; no durable event
queue or replay was added. A new event can remain eligible after an
interrupted attempt, subject to the configured minimum interval.

**14D proof:** Focused automation/domain-event tests passed 30 tests and 25
subtests, covering exact and nonmatching filters, Guide, inactive owners,
deferred dispatch, duplicate prevention, minimum interval and restart. A
validated `capability.completed` event from a real memory refresh admitted
one later canonical memory READ, whose result was `success`/`passed`; its own
completion event caused no further admission. The full Bash suite passed all
five groups with no group failures or skips. Full Python pytest passed 279
tests and 119 subtests. Changed-file Ruff, CI-configured ShellCheck, Bash
syntax, Python compile and `git diff --check` passed.

**14C periodic READ and recovery:** version-1 `periodic` triggers use a UTC
anchor and a positive interval of at most 31,536,000 seconds. Each explicit
`run-due` tick uses one fixed UTC time, computes the current interval slot,
skips missed slots and atomically claims only that slot before the existing
canonical READ dispatcher runs. A process lock skips overlapping ticks while
one tick dispatches; the existing cursor prevents a restarted tick from
claiming the same slot, including after a backward clock change. Inspection
is read-only and shows the next due slot. A crash after claim remains
`interrupted_unknown`; a later slot can be claimed without
replaying the old one. Editing the trigger disables intent and clears its
cursor. No cron service, event or condition trigger was added.

**14C proof:** focused tests covered invalid versions/intervals/cursors,
Guide, missed slots, concurrent claims, overlapping dispatch ticks, restart
after an unfinished claim, backward time, edit reset and read-only inspection.
A real periodic
`system.host.memory.refresh` run yielded a canonical `success`/`passed`
result and correlated `capability.completed` event; a second process admitted
zero runs for the same slot. All 19 focused automation tests passed. The
full `bash tests/run_all.sh` passed all five groups with no group failures;
the core BATS run skipped two environment-dependent cases (GPG agent and
`hostname -I`). Full Python pytest passed 273 tests and 115 subtests.
Changed-file Ruff, CI-configured ShellCheck, Bash syntax, Python compile
and `git diff --check` passed.

**14B execution and recovery:** `--automations run-due` evaluates one-time UTC
triggers in Guide, Assist or Executive mode. Guide admits none. An exclusive
store lock and durable cursor claim precede each canonical `ai_execute_tool`
READ invocation. Assist and Executive use the existing provider, input,
precondition, approval, observer and verification path. The private store
retains only the slot, claim, operation ID and bounded status summary. A
crash after claim remains `interrupted_unknown` across restart; a terminal
claim cannot run again on another tick. Inspection shows due, claim and
terminal state without execution or mutation.

**14B proof:** an isolated enabled `system.host.memory.refresh` instance was
claimed and dispatched once in Assist, producing canonical `succeeded` /
`passed` / `success` and the existing `capability.completed` event with the
same operation ID. A second tick admitted zero runs; Executive independently
verified the same READ path, while Guide admitted none. Focused tests cover
future/disabled/inactive intent, CHANGE/DESTROY/privileged and ambiguous targets,
atomic concurrency, crash/restart, fixed inputs, canonical precondition failure,
unverified outcome and read-only inspection. Fourteen focused tests passed.
Full `bash tests/run_all.sh` passed all five groups with no failures/skips;
full Python pytest passed 268 tests and 108 subtests. Changed-file Ruff,
syntax/compile and `git diff --check` passed. ShellCheck reported only two
pre-existing warnings on untouched `igor.sh` lines. No scheduler service,
periodic, event or condition execution existed in 14B.

**14A contract and vertical slice at acceptance:** `core/lib/automation_registry.py` strictly
validates closed version-1 records, UTC `once_at`, fixed capability inputs and
the `read_unattended`/one-attempt policies. The CLI created the system proposal
disabled, explicitly enabled it, inspected it from a fresh Igor process,
disabled it and deleted it using an isolated data directory. No capability was
invoked; enabled intent reports `execution_not_installed` and no attempt or
cursor exists. The loader's owner-aware contribution index supplies proposals;
the existing capability index supplies target metadata.

**14A inspection and recovery:** `--automations proposals|list|inspect ID` returns
source/provenance, enabled state, exact availability reason, trigger, target,
policy, next due time and empty run state without side effects. Disabling a
source module retains enabled user intent but reports
`source_proposal_inactive`; restoring the matching proposal restores
availability. The private `${IGOR_DATA_DIR:-${IGOR_DIR}/data}/automation/registry.v1.json`
store is version 1, mode 600 in a mode 700 directory, protected by a lock and
atomic replacement. Invalid/unsupported versions fail closed and leave bytes
intact. Explicit `reset all` retains a recovery copy before creating a new
empty version-1 store; selected reset/delete removes only that instance.
There is no prior automation-store version to migrate and no dual source.

**14A regression at its acceptance:** eight focused automation tests passed. `bash tests/run_all.sh`
passed all five groups (46 Bash core, 46 Python render, 305 core BATS, 130
module BATS, 40 integration BATS); full Python pytest passed 260 tests and
100 subtests. Changed-file Bash syntax, Python compilation, Ruff,
`git diff --check` and ShellCheck passed, except for two pre-existing
`igor.sh` warnings on untouched lines. No scheduler or execution path exists
in 14A. Q003, Q007, Q009 and Q011 retain their later owners.

## Step 13 Domain Event Bus implementation

**Step 13 is complete at the accepted [EVENT_BUS.md](EVENT_BUS.md) boundary;
Step 14B canonical execution emits its existing `capability.completed` event.**
`core/lib/domain_event.py` validates
the version-1 envelope and closed payload schemas. The owner-aware v2 index
admits active `<owner>.<domain>.<occurrence>` declarations. The module handler
API validates explicit requests and rechecks active ownership at publication.
The session-local bus stamps identity/source, retains 128 events, delivers to
Core subscribers best effort, and exposes read-only `igor_domain_event_types`,
`igor_domain_event_recent` and `--events types|recent` queries. It remains
separate from `core/ai/events.sh`; events grant no operational authority.

**Contract and vertical slice:** focused tests reject malformed, oversized,
unknown-version, secret-bearing and spoofed fields before delivery; inactive
owners cannot publish. Each committed canonical Wave E result uses one
publication path. Real `system.host.memory.refresh` produced one correlated
`succeeded`/`passed`/`success` event for `host:local`. The disposable
`system.service.restart` fixture produced one `succeeded`/`failed`/
`unverified_change` event. A failing subscriber did not change the committed
result or prevent later delivery. No event is emitted before a result exists.

**Inspection and recovery:** type/event queries and exact filters are read-only;
focused guards show no observer, check, capability or privilege invocation.
The owner-only scratch is a bounded, disposable session buffer. A fresh
process begins empty and cannot replay old callbacks or reconstruct lost IDs
or ordering. No persistent layout migration occurred. Existing AI audits and
recovery journals remain separate pending Step 15.

**Regression:** `bash tests/run_all.sh` passed all five groups (46 Bash core,
46 Python render, 305 core BATS, 130 module BATS, 40 integration BATS). The
full Python suite passed 254 tests and 94 subtests. Focused Step 13 tests,
Bash syntax, Python compilation, changed Python Ruff and `git diff --check`
passed. CI-configured ShellCheck passed on changed event, capability, loader,
handler and BATS paths; `igor.sh` retains two warnings on untouched lines.

At Step 13 acceptance, durable history and later baselines/healing remained deferred.
Step 15B now supplies the history boundary described above. Q008 is
resolved by D044; Q003, Q007, Q009 and Q011 retain their assigned decisions.

## Wave E Agent Architecture implementation

**Steps 11–12 are implemented for the bounded Wave E slice.** The accepted
D037–D039 contract remains [AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md).
The owner-stamped Wave C index now backs read-only capability list/inspection
and one structured invocation path through the existing AI dispatcher.
Canonical dotted IDs resolve one active provider automatically; absent and
ambiguous providers cannot execute, and an ambiguous call requires an explicit
provider. Complete v2 declarations expose version, schema, safety, privilege,
preconditions, verifier, recovery, affected objects and source. Bare Wave C
declarations, secret consumers without a reviewed adapter and privileged
operations without reviewed Core argv remain inspectable but unavailable.
The v1 action catalog is projected into `legacy.<owner>.<action>` and
`run_igor_action` remains its compatibility dispatcher.

`system.host.memory.refresh` is a real READ capability: its active `system`
provider calls the existing observer refresh, validates the Wave D
observation, updates the process-local System Model, runs the memory health
check and returns fresh fact/attempt evidence. The disposable
`system.service.restart` fixture proves structured unit input, CHANGE
approval, existing PTY sudo authentication, a frozen Core argv, live service
query verification, and `unverified_change` when the command succeeds but the
postcondition fails. No production service was restarted for proof.

The minimal plan value resolves ordered steps, typed object references and an
optional verifiable READ final check, keeps a digest, then sends each operation
through that same capability dispatcher. It records completed steps and stops
on failure. D038 leaves raw shell as a visibly
unstructured fallback: recognized canonical forms are rejected, raw CHANGE
requires explicit approval even in Executive, DESTROY requires exact `YES`,
and raw execution has no claimed deterministic verifier. Secret references
are validated as opaque values; a small authorized-consumer adapter provides
private FD access with value-free audit. No current v2 capability uses a
secret value, so secret-using declarations remain unavailable until a reviewed
consumer is installed. The future Ownership Foundation still owns durable
secret/configuration layout.

The Context Engine selects bounded typed items with source kind, owner,
object/capability, freshness and selection reason for the memory domain. It
composes current Wave D fact/health, active `system` knowledge, the available
memory capability and Core guidance into the existing `IGOR_REFERENCE_V1`
boundary. Inspection reads that selection without refreshing observations.
Other domains continue through labeled legacy context until they gain
authoritative facts and a relevance cutover; no second AI pipeline or prompt
authority was added. Disabled owners contribute no active capability or
knowledge. Context does not expand secret references, and existing outbound
privacy/redaction remains the last boundary.

### Wave E proof

- **Contract and inspection:** focused Python/BATS tests exercise provider
  resolution, inputs, preconditions, safety, approval, privilege, verification,
  recovery, raw fallback, plans, source selection and secret references. CLI
  `--capabilities list|inspect|plan` and `--context inspect` are read-only;
  `igor_capability_result(operation_id)` exposes running-session outcomes.
- **Vertical slices:** the live memory capability produced a verified result
  tied to a fresh `host:local` fact and health/context item. The file-backed
  service fixture recorded approval before sudo and exact `systemctl` argv;
  its forced inactive postcondition produced `execution_status=succeeded`,
  `verification_status=failed`, `outcome=unverified_change`.
- **Migration/recovery:** v1 actions and Nextcloud v1 retain their dispatch;
  the new memory capability has one observer/model update path. Observed facts
  remain process-local and rebuildable; no persistent layout migration or
  automatic rollback was introduced. Recovery classes are metadata; a
  recovery action, if registered, must use normal capability authority.
- **Regression and lint:** `bash tests/run_all.sh` passed all five suite
  groups (305 core, 126 module and 40 integration BATS cases); two core cases
  skipped because this runner lacks a GPG agent and `hostname -I`. The full
  Python suite passed 248 tests and 94 subtests. The focused capability and
  observation BATS run passed 23 cases. Bash syntax, Python compilation and
  `git diff --check` passed. Ruff passed on new Python files; full-repository
  Ruff reported the same 135 findings as the untouched `HEAD` baseline, with
  no new finding by file/code/message comparison. CI-configured ShellCheck on
  changed shell/BATS files reported 11 pre-existing warnings and no new
  warnings. These existing lint findings remain outside Wave E.

## Wave E Agent Architecture design gate (historical baseline)

The following paragraphs describe the accepted gate before implementation.

**Steps 11–12 have an accepted implementation contract, not a runtime
implementation.** The contract and falsifiable exit checks are in
[AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md); D037–D039 in
[DECISIONS.md](DECISIONS.md) settle the canonical capability/plan boundary,
Q010 raw-shell fallback and deterministic Context Engine selection. The gate
was prepared on clean `igor2` at `a07de42` (`origin/igor2`), with local
`master` verified as an ancestor. Wave D implementation and D033–D036 are
present. This documentation pass did not rerun runtime tests; the recorded
Wave D green proof below remains the baseline.

Step 11 is partial: v1 `ai_capabilities` gives active-owner tiered actions,
`run_igor_action` calls a no-input function, and the AI catalog/parser and
approval dispatcher protect current tools. The Wave C contribution index
records v2 capability declarations but does not dispatch them. Inputs,
preconditions, privilege metadata, deterministic verification, recovery,
affected-object and secret-reference contracts are missing. Legacy action
functions may invoke sudo internally; they are not yet v2 privilege-mediation
proof. Step 12 is partial: `IGOR_REFERENCE_V1`, outbound privacy scrubbing
and active knowledge filtering work, but `context.sh` still gathers broad
direct probes, hooks, patterns and saved text without item-level relevance
and provenance.

The selected Wave E proof combines a real active `system` READ path
(`system.host.memory.refresh` -> existing observer -> fresh System Model fact
-> `host.memory.health` context and verification) with a disposable
`system.service.restart` CHANGE fixture that exercises frozen inputs,
approval, existing PTY privilege mediation and execution-success/
verification-failure distinction. `nextcloud_docker` remains v1; no broad
application migration or persistent layout change is implied. The
Ownership Foundation still gates broad migration and later secret/history/
learning storage rules.

**The bounded Wave E implementation is unblocked by architecture decisions.**
Its required order and contract, regression, vertical-slice, inspection and
migration/recovery proof are specified in the Wave E contract. Q003, Q004,
Q007–Q009 and Q011–Q012 remain at their assigned later gates. Design
acceptance does not mark either Step 11 or 12 complete.

## Wave D Host Intelligence implementation

**Steps 7–10 are implemented at the accepted Wave D boundary.** Platform
package/service query and install/remove/update/upgrade argv resolvers extend `core/lib/pkg.sh`
without adding an execution path. The process-local System Model in
`core/lib/system_model.py` separates observed, configured, user-declared,
desired and inferred slots from watch/maintain responsibilities. Its Bash
bridge in `observation.sh` validates active v2 observer results before an
atomic runtime snapshot update. Observed values are rebuilt after restart;
there is no fact database. The shared `health_runner.sh` evaluates active v2
checks and adapts active v1 checks for Diagnose and Healing.

The real `system` path is `host.memory` → validated
`host:local/memory.available_bytes` → `host.memory.health` → read-only
inspection and Diagnose/Healing/AI projections. Igor stamps provenance,
freshness and check time. The 80/150 MiB boundaries are preserved. The old
`system__diagnose`, `system__health`, hardware check and AI-context RAM probes
were retired for this slice; other hardware and Nextcloud v1 checks remain.
`bash igor.sh --model fact host:local memory.available_bytes` and
`--model observers` are read-only;
`--model refresh host.memory` and `--model evaluate host.memory.health` are
explicit operations. The backend model/health inspection APIs retain state
within a running Igor process. Q003 and Q012 remain open.

### Wave D proof

- Contract: System Model unit tests cover independent slots, provenance,
  type rejection, availability, partial output, inference and source replay.
  Observer BATS cover active/inactive owner, malformed/failure cutover,
  no implicit read refresh and restart reconstruction. The health runner
  validates used-fact references and fails to `UNKNOWN` on stale input.
- Vertical slice: live `system` handler invocation produced a typed memory
  fact and a structured result with the same fact key/time. Diagnose and
  Healing each projected one RAM result. AI context uses the fact and keeps
  it inside `IGOR_REFERENCE_V1`.
- Inspection/recovery: `--model fact` is initially `not_observed`; explicit
  refresh populates it; a new Igor process again starts `not_observed` and
  rebuilds on refresh. Health inspection exposes the check's used fact and
  timestamp. Source-backed desired/responsibility replay is covered without
  adding a persistent layout.
- Regression: `bash tests/run_all.sh` passed all five groups (46 Bash core,
  46 Python render, 303 core BATS, 114 module BATS and 40 integration BATS),
  with one environment-dependent GPG-agent skip inside core. Full `pytest -q`
  passed 224 tests and 93 subtests. Bash syntax and `git diff --check` passed.
  Ruff passed on changed Python files. Full-repo Ruff still reports its
  pre-existing backlog; ShellCheck on changed shell files reports only the
  pre-existing warnings in `core/ai`, Healing and `igor.sh`.

## Wave D Host Intelligence design gate (historical baseline)

**Design accepted before implementation.** The implementation
contract and falsifiable exit checks are in
[HOST_INTELLIGENCE.md](HOST_INTELLIGENCE.md), with D033–D036 accepted in
[DECISIONS.md](DECISIONS.md). Wave C remains the green implementation baseline.
This paragraph records the design gate's preimplementation evidence.

The gate was made on a clean `igor2` worktree at `a8dda91`
(`origin/igor2`), with local `master` `76f04e3` confirmed as an ancestor.
Wave C's recorded baseline is five `run_all.sh` suite groups passing (core
288/288, modules 103/103, integration 40/40), with two environment skips
inside core, and 216 Python tests plus 93 subtests passing. Ruff's 135
pre-existing repository findings are unchanged by documentation. These are
the **recorded Wave C results**, not tests rerun for this gate.

Step 7 remains partial: Debian/Arch detection, logical package/service name
mapping, install command selection and Python resolution exist; package
query/remove/update, service operations and shared host read mechanisms do
not. `pkg.sh` defaults unknown family resolution to Debian and owns Docker
post-install work, both explicit migration points. Step 8 has no Igor-owned
fact store/query. Step 9 has a real invokable `host.memory` handler but no
typed ingestion, freshness or failure model. Step 10 has active-owner legacy
checks, but Diagnose and Healing discover/execute/parse them separately.
Direct AI/context host probes remain compatibility inputs.

The selected first slice is `system` `host.memory` -> validated observation
-> `host:local/memory.available_bytes` -> structured memory check ->
inspection and selected existing workflow/context projection. The source
fact and check must each have one authority per consumer at cutover.
Configured/desired/responsibility intent is rehydrated from an existing
authoritative source when one exists; observed facts are rebuildable. No
database or new persistent layout is selected, so Q003 remains open for
Step 15. The Ownership Foundation still gates broad module migration, not
this bounded host slice.

**Wave D implementation is unblocked by architecture decisions.** It must
follow the order and five proof classes in the contract document. Accepted
D017–D022 and the Wave C loader/adapter are unchanged; `nextcloud_docker`
continues as v1. At that gate Q004 and Q007–Q011 retained later decision
points; Wave E has since resolved Q010. Q012 records the later
effective-threshold configuration question.
The gate does not imply that Step 7 package/service mutations may
bypass current approval or sudo behavior.

## Baseline and stage

**Wave C Steps 5–6 are complete.** The first Module API v2 path is active,
inspectable and covered by contract, regression, vertical-slice and policy
migration proof. Wave D host-intelligence work can proceed within its scope.
Decisions D017–D022 select a language-neutral data contract with a Bash-first
handler adapter, a small strict v2 `module.conf` plus explicit JSON contract
files, typed dependency semantics, a core/platform versus `system` rule, one
loader with temporary v1 compatibility, and an initial reviewed-local-code
trust boundary. The green Wave B behavioral baseline was preserved during
the Wave C implementation.

The roadmap now also makes the ServerMind/Steward-derived design lessons and
execution discipline explicit in `INFLUENCES.md` and `EXECUTION.md`.
The accepted D017–D022 runtime contract was not reopened. The implementation
extends the existing loader with strict v2 validation, staged owner-aware
contributions, a Bash handler adapter and module inspection.

A cross-cutting Ownership Foundation is now a hard gate before broad Module v2
migration: canonical paths, configuration, secrets, persistent state, machine
memory, knowledge, local learning, investigations, history and runtime need
explicit ownership/lifecycle contracts. Wave C established the loader and
contribution boundary without making today's mixed storage layout a permanent
v2 public contract.

Wave B / Steps 3–4 completed the interaction and privilege work. Its backend
session, deterministic approval dispatcher, frontend event stream, TUI
projection and native sudo-through-PTY path remain authoritative.

Wave A / Step 2 completed the accepted architecture guards and removed the
three stale system-storage test failures. Its baseline is retained below for
comparison.

The Step 1 audit was performed on a clean `igor2` tree at `6675ece`; local
`master` `76f04e3` remains an ancestor. Its findings and red baseline are
retained below for comparison.

The audit is a snapshot of this checkout and its local `master` ref, not a
claim about a newer un-fetched remote branch.

## Current-state assessment

| Roadmap steps | Assessment from current repository |
|---|---|
| 1 Legacy Audit | Implemented by this evidence ledger and baseline. |
| 2 Architecture Rules | Implemented for accepted current invariants: focused ownership, trust, platform and safety guards now run in existing test suites. Later contracts get their own tests when implemented. |
| 3 Interaction Runtime | Implemented for current chat/TUI use. Backend command routing, pending choice/approval state, mode policy, provider continuation and ordered frontend events are guarded. Future interfaces can consume the same backend authority; no new interface was built. |
| 4 Privilege Boundary | Native backend PTY sudo authentication follows approval. Wave E v2 capabilities now declare privilege and bind reviewed exact argv before this existing gate; legacy actions retain their internal privilege behavior. |
| 5 Module Runtime v2 | Complete for Wave C in `core/lib/module_loader.sh`: v1/v2 dispatch, strict preflight, staged declarations, owner-aware contribution index, typed module/contribution state and inspection queries. |
| 6 Module API v2 | Initial Bash-first contract complete for Wave C in `core/lib/module_contract.py` and `core/lib/module_handler.sh`. `system` is a mixed v1/v2 reference; `nextcloud_docker` remains v1. Later kind-specific consumers remain deferred. |
| 7 Platform Abstraction | Wave D boundary complete: normalized Debian/Arch package query and install/remove/update argv, systemd state query and operation argv, strict names, timeout/error behavior and unknown-family failure. Legacy `pkg_install` remains compatible. |
| 8 System Model; 9 Observation Framework | Initial Wave D contract complete: typed keyed facts, independent intent/responsibility records, active v2 observation validation, freshness/failure state and read-only inspection. Broader domain inventory and persistence remain later work. |
| 10 Unified Health | Initial Wave D contract complete: one active-owner runner, structured v2 memory result, v1 line adapters and Diagnose/Healing projections. |
| 11 Capability System v2 | Bounded Wave E implementation: canonical owner-aware registry/invocation, typed inputs, deterministic preconditions, existing approval/PTY route, structured result/verification, recovery metadata, D038 fallback, inspection and small plans. V1 actions remain compatible; broader providers wait for reviewed adapters. |
| 12 Knowledge & Context Engine | Bounded Wave E implementation: deterministic typed, source-aware selection and read-only inspection for the memory domain inside `IGOR_REFERENCE_V1`. Other domains retain labeled legacy context until authoritative sources and relevance mappings exist. |
| 13 Domain Event Bus | Complete at the bounded Step 13 contract: validated session-local signals, owner-aware producers, read-only inspection and one `capability.completed` projection per committed result. `core/ai/events.sh` remains frontend activity. |
| 14 Automation Engine | Complete at the bounded unprivileged READ contract: Igor-owned intent, explicit enablement, atomic due-slot claims and canonical dispatch for one-time, periodic, event and condition triggers. |
| 15 Operational History | 15A accepted; 15B service, durable lifecycle, inspection and recovery implemented; judgment and 15UI foundations complete; bounded 15C investigations implemented. D057/15D context relevance and model-role routing implemented with its evidence gate above. |
| 16 Baselines; 17 Relationships/Deployments; 18 Composable Modules; 19 Self-Healing v2 | Missing as target contracts. Preserve the current combined Nextcloud deployment until prerequisites exist. |
| 20 Igor TUI as Default | Partial: full-screen TUI works via `--ai-tui`; classic menu/line UI and `--extra` remain, and default launch is unchanged. |
| 21 Integration Rules | Missing as a shared contract. |
| 22 Module Tooling & External Interfaces | Partial/future: overlapping experimental validators and SMTP notifications exist; incoming mail control implementation is absent. |
| 23 Consolidation | Missing/future; compatibility paths have removal conditions in `LEGACY.md`. |

## Significant findings

- Preserve the current TUI/backend event projection, deterministic safety and
  privilege flow, module loader, action catalog, reference-data boundary and
  platform helpers. Their roadmap steps are extension/hardening work.
- Healing and startup config validation now use active module identity. Generic
  Healing no longer requires Nextcloud files when that owner is inactive.
  Diagnose, configuration, security defaults, recovery, old UI and platform
  post-install paths still contain application assumptions. The active-owner
  guard does not complete physical core/module separation; D020 now sets the
  placement rule for that later migration.
- The three stale `test_system_storage.bats` assertions were corrected to the
  current host-only `system` contract. A Nextcloud module check test preserves
  application storage behavior without restoring it to `system`.
- Configuration has overlapping defaults/migration paths; notifications have
  an event-hook and aggregator state path; Diagnose and Healing discover checks
  separately; several experimental module validators coexist. No second
  implementation should be promoted during cleanup.
- `core/mailcmd/` does not exist. Remaining menu/help/config references are
  stale affordances, not a functioning subsystem. SMTP notifications are real
  and separate from incoming control.

## Step 2 guards now in the suites

1. Module BATS covers active/disabled/unavailable/installed-only checks,
   owner-filtered hooks, menus including legacy lazy dispatch, config
   validation, backup/restore, notification hooks and owned action catalog.
   Existing dispatch tests reject inactive action owners.
2. Healing and Diagnose agree on the active module check set. Generic Healing
   ignores inactive Nextcloud configuration; active Nextcloud retains its
   current checks. System storage remains host-only.
3. AI tests place hostile module knowledge, logs, reports and tool output in
   the untrusted request envelope; deterministic tool parsing and execution
   tests reject claimed READ/approval authority. Existing tests cover pending
   modes, failed sudo, Executive DESTROY and exact operation handling.
4. Platform BATS pins Debian/Arch detection, current package and service
   mappings, mocked apt/pacman calls and unknown-family behavior.

Wave D added System Model and observer tests; Wave E added capability
verification tests. Domain events remain a later contract.

## Wave B runtime and privilege assessment

- `core/ai/core.sh` remains the backend session authority. Its registry handles
  typed and palette commands; its pending choice record now carries an explicit
  assistant owner, conversational-choice type and awaiting/resolved lifecycle.
  Numbered, ordinal and matching text replies resolve against that record.
  A bare `cancel` dismisses an active choice locally; commands and clearly new
  requests clear stale choice state. Without a pending interaction, ordinary
  chat still goes to the provider.
- `core/ai/safety.sh` remains the approval authority. Explain returns to the
  same pending request; Guide/Assist/Executive alter READ/CHANGE autonomy but
  cannot change DESTROY's exact `YES` requirement or grant OS privilege. The
  TUI sends input to this backend and projects ordered `core/ai/events.sh`
  activity events. Invalid event sequence values now fail at the projection
  boundary; frontend text or event fields cannot authorize execution.
- Sudo authentication stays in the backend PTY after Igor approval. The
  dispatcher uses the approved command for execution, may reuse OS-cached
  credentials, and fails closed on unavailable/failed authentication before
  backup or execution. Password input bypasses chat draft/history/events and
  audit. No separate sudo broker is justified by current callers. Step 11 may
  add declarative capability privilege metadata to this same execution gate;
  it must not create a second elevation path.
- The current pending-choice extraction is intentionally limited to explicit
  alternatives in the most recent assistant reply. Other natural-language
  intent and the narrative after `continue` still use provider conversation;
  the latter builds a failure recap from prior message text in
  `core/ai/core.sh`. Pause/resume routing is explicit and authorization stays
  deterministic at dispatch; this narrative is not authoritative operational
  state. `/stop` is handled at approval or the next backend chat prompt;
  a synchronous provider or tool call is not preempted. The classic
  line UI, `--extra`, old `exec on/off` setting bridge and
  v1 module APIs remain compatibility inputs under their existing removal
  conditions. No compatibility path met the safe-removal criteria in Wave B.

At Wave B completion, no accepted decision changed. Q010 raw-shell policy and
Q011 remote approval remained at their assigned later steps; neither blocked
that backend contract. Q006 was subsequently resolved by the Wave C design
gate in D020.

## Step 1 test and lint baseline (before Step 2)

Run against the clean pre-edit branch; documentation changes cannot affect the
application suites. These are **existing baseline** failures, not regressions
introduced by this audit.

| Check | Result |
|---|---|
| `bash tests/run_all.sh` | Failed: 4 suite groups passed, 1 failed, 0 skipped. `test_igor_core.sh` 46/46, `test_ai_render.py` 46/46 via unittest fallback, core BATS 273/273, integration BATS 40/40. Module BATS 58/61: only `test_system_storage.bats` cases 2–4 fail. |
| `bats --tap tests/modules/test_system_storage.bats` | Reproduced 2/5 passed, same three failures. |
| Full Python `pytest tests/ -q` | 203 passed and 89 subtests passed. The repository's `run_all.sh` itself only targets `test_ai_render.py`; this extra run covered all Python test files. |
| `bash -n` over `igor.sh` and all `core/`, `modules/`, `tests/` `.sh` files | Passed. |
| `ruff check .` (Ruff 0.16.9) | Failed with 135 existing findings; largest groups include I001 (23), PLW1510 (21), UP032 (20) and BLE001 (17). CI's Ruff installation is unpinned, so exact counts can vary by version. |
| ShellCheck with CI warning severity/exclusions (0.11.0) | Failed: core 76 findings (73 for the other 77 scripts, 3 for `core/ai/core.sh`), modules 14, entry point 2, tests 8. Core was split into two equivalent invocations because the all-core invocation ran too long. CI marks all ShellCheck steps `continue-on-error`. |
| `git diff --check` | Passed. |

CI invokes only the render Python test, while the full Python suite above is a
broader local check. CI ShellCheck is non-blocking; Ruff and test jobs are
blocking and were red at the Step 1 baseline for separate existing reasons.

## Step 2 validation and comparison

| Check | Current result and Step 1 comparison |
|---|---|
| Module BATS | 73/73 passed. The three stale system-storage failures from Step 1 are removed; new activation, catalog, config and Healing guards pass. |
| Core BATS | 284/284 passed, including the new trust, forged frontend-event and platform guards (Step 1: 273/273). |
| Full Python suite | 203 tests and 89 subtests passed, matching Step 1. The expanded request-boundary assertions pass. |
| `bash tests/run_all.sh` | Passed: 5 suite groups, 0 failed, 0 skipped. This removes the Step 1 failing module group without adding a new failure. Core BATS 284/284, module BATS 73/73 and integration BATS 40/40. |
| Bash syntax and ShellCheck on changed scripts | `bash -n` passed for `core/healing/core.sh` and `core/lib/config_loader.sh`. ShellCheck reports only the existing SC2155 in Healing; changed BATS files report only two warnings on pre-existing lines. No new lint finding was introduced. |
| Ruff 0.16.9 | 135 findings, exactly the same file/code/line/message set as Step 1; none added or removed. |
| `git diff --check` | Passed. |

Wave A is complete and ready for the next implementation wave. The current
test suite is green; the known Ruff/ShellCheck backlog remains outside Step 2.

## Step 2 decision gates (historical)

At Step 2, repository evidence did not resolve an accepted decision, so
`DECISIONS.md` was unchanged. Q001/Q002/Q005 and Q006 were then open; this
Wave C design gate resolves them in D017–D020. Q010 was later resolved by
Wave E in D038. No decision blocked Step 2 tests.

## Wave B validation compared with Wave A

| Check | Wave B result | Comparison with green Wave A |
|---|---|---|
| Focused interaction, approval, safety, privilege and frontend BATS | 101 focused cases passed. | New choice lifecycle, cancellation and declined-sudo guards pass alongside the existing approval and event guards. |
| Relevant Python TUI/PTY tests and full Python suite | Focused TUI, privilege PTY and session command tests: 56 tests and 46 subtests passed. Full `pytest tests/ -q`: 204 tests and 93 subtests passed. | Wave A full suite: 203 tests and 89 subtests; one new TUI event-sequence test with four subcases, no failure. |
| `bash tests/run_all.sh` | 5 suite groups passed, 0 failed, 0 skipped; core BATS 288/288, module BATS 73/73, integration BATS 40/40. | Wave A: all 5 groups passed; core BATS 284/284, modules 73/73, integration 40/40. No new behavioral failure. |
| `bash -n core/ai/core.sh`; `git diff --check` | Passed. | No syntax or whitespace regression. |
| Ruff 0.16.9 and CI-configured ShellCheck on changed files | Ruff remains at 135 repository findings, unchanged from Wave A. `core/ai/core.sh` retains its three pre-existing ShellCheck warnings (SC2174, SC2010, SC2011); changed BATS files pass ShellCheck. No warning appears on changed lines. | Lint backlog remains outside Wave B. |

Wave B completed with the green behavioral baseline preserved. At that point
`DECISIONS.md` was unchanged; no new decision gate arose for Steps 3–4.

## Wave C Module Platform design gate

The design review inspected the current loader, both bundled manifests and
modules, activation/dependency/capability/configuration tests, the v1 module
docs, config policy and Debian/Arch platform helpers. The branch contains its
local `master` baseline. This pass changed documentation only; it did not
rerun or alter the green Wave B behavioral suite.

- Q001, Q002 and Q005 are resolved by D017–D019. The current first-key
  manifest parser stays v1 compatibility; strict v2 parsing and JSON contracts
  are implementation work. Hard module dependencies name identities;
  substitutable requirements name canonical capabilities. Missing or disabled
  providers never auto-enable.
- Q006 is resolved as an ownership rule in D020: core/platform supplies
  reusable Linux mechanisms; `system` supplies host-domain meaning. Existing
  application logic and platform post-install leakage move only when later
  replacements are ready.
- D021 preserves the current state model and restart behavior. V1 hooks and
  lazy menus continue during migration; v2 declarations join one owner-aware
  index, with `system` as the first mixed reference and `nextcloud_docker`
  unchanged as v1. D022 settles the initial local-code trust boundary and
  explicit enablement for new v2 packages.

The implementation now follows the accepted Steps 5–6 sequence in
`MODULE_API.md`. The strict validator rejects malformed v2 manifests and
contracts before executable module code is sourced. The loader records API
version, lifecycle state and failure reason, stages owner-stamped
contributions, applies module-wide versus contribution-local requirements, and
exposes `igor_module_list`, `igor_module_status`, `igor_module_reason` and
`igor_contribution_list` for inspection. The Bash adapter validates syntax,
invokes one JSON request, and accepts only a valid response envelope.

`system` declares `host.basics` knowledge and the `host.memory` observer under
v2 while retaining its v1 hooks. The observer is exercised through the loader
invocation path and v2 knowledge is included in the active AI reference
context. The bundled system policy migration records an explicit enabled entry
for an installation that previously omitted it, preserves explicit disablement
and keeps a one-time pre-migration copy when an existing policy file is present.
Newly discovered v2 modules require
explicit enablement. `nextcloud_docker` remains on v1.

### Wave C completion evidence

| Proof | Result |
|---|---|
| Contract | 12/12 validator unit tests, 6/6 Bash adapter BATS, and 24/24 v2 runtime BATS. Invalid metadata and Bash syntax fail before source; unsupported API/runtime, duplicate/unknown declarations, path escapes, hard cycles, missing/disabled/ambiguous requirements and contribution-local failures have named reasons. |
| Regression | `bash tests/run_all.sh`: 5 suite groups passed, 0 failed, 0 skipped groups. Core BATS 288/288, module BATS 103/103, integration BATS 40/40. Two existing core BATS cases skipped within the passing group because GPG agent and `hostname -I` were unavailable. Full Python suite: 216 passed and 93 subtests passed. |
| Vertical slice | `system` validates `contracts/host.json`, activates, indexes `host.basics` and `host.memory`, returns structured memory data through `igor_v2_invoke`, and appears in `igor_module_list`. The host knowledge is tested inside the existing `IGOR_REFERENCE_V1` AI reference envelope. V1 `system` hooks still run once. A focused live-loader check confirmed `nextcloud_docker` remains active on v1 with owned menu, diagnose, AI, config, backup, restore and notification registrations; full startup retained eight executable catalog actions, including owned `scan_files`. |
| Inspection | `bash igor.sh --modules` and loader queries expose identity, API version, lifecycle state, owner, kind, source and precise module/contribution reasons. Active ownership is checked again at dispatch. |
| Migration/recovery | V1 omitted entries retain implicit enablement; new v2 entries require explicit enablement. The bundled `system` omitted policy is recorded once as `system=enabled`; explicit disablement is preserved. Existing policy is backed up once, updates use a private temporary file and atomic replacement, symlinks are refused, and write failure is reported as unavailable before source. No other persistent layout changed. |
| Lint and syntax | Bash syntax and `git diff --check` pass. Ruff 0.16.9 passes on new Python files; full `ruff check .` retains 135 pre-existing findings, matching the earlier baseline. CI-configured ShellCheck on changed shell/BATS files reports only five pre-existing SC2155 warnings in `core/ai/context.sh` and `igor.sh`; no new warning remains. |

No accepted Wave C decision was reopened and no new blocking question arose.
Q004 remains a future third-party distribution policy; at Wave C completion,
Q003 and Q007–Q011 remained at their assigned later steps (Q010 is now
resolved by D038). System Model, observer scheduling,
domain events, general Capability System v2, broad Ownership Foundation
migration, non-Bash adapters and composable Nextcloud modules remain deferred.
The Ownership Foundation remains a hard gate before broad module migration.
