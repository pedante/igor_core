# Wave E agent architecture — Steps 11–12 design gate

Status: **accepted design, not implemented**. Wave D Steps 7–10 are the green
baseline. This contract extends the single Wave C contribution index, the
current action catalog and dispatcher, Wave D System Model/health interfaces,
and the existing AI request/reference boundary. Runtime completion still
requires the five proof classes in [EXECUTION.md](EXECUTION.md).

```text
User / AI / TUI / later automation -> intent -> canonical capability lookup
  -> validated inputs -> availability/preconditions/safety -> Igor approval
  -> existing privilege gate -> exact provider invocation -> deterministic
  verification -> structured result / System Model reference / inspection

Igor state + active knowledge + available capabilities + selected context
  -> Context Engine -> IGOR_REFERENCE_V1 reference envelope -> AI reasoning
```

## Baseline and ownership of the change

At `a07de42` on `igor2`, `master` is an ancestor and the worktree was clean
before this design edit. Wave D's `system` memory observer/check, typed model,
platform argv resolvers and shared health runner are present; D033–D036 are
accepted. This is a repository inspection, not a new runtime test result.

`igor_load_capabilities()` currently parses v1 `ai_capabilities` text into
`_IGOR_CAPABILITIES[name]=desc|function|lazy_module|tier|problems|menu` and
indexes `legacy.<owner>.<name>` contributions. `ai_catalog_json()` filters
active owners and policy. `run_igor_action` accepts only a name, rechecks its
owner after approval, then calls the Bash function in process. The current
function's exit code is the outcome; there is no input schema, precondition,
privilege declaration or deterministic postcondition. Legacy actions such as
Nextcloud `scan_files` remain useful, but their `sudo` calls can happen inside
the function rather than being declared to the dispatcher. Do not claim they
already satisfy the v2 privilege contract.

Wave C v2 `capability` descriptors are validated and indexed, including
duplicate-provider visibility, but the loader marks this kind unavailable to
invocation. `igor_v2_invoke` currently accepts observer/check/knowledge only;
the validator has no capability-specific fields. Step 11 extends that path
and `run_igor_action` rather than adding a second action registry or a
module-authored executable tool grammar. The current `core/ai/catalog.py` and
`tool_input.py` define the AI parser; `core/ai/safety.sh` owns classification,
approval and the PTY sudo sequence. `core/ai/control.sh` owns tool/action
policy and bounded audit. Provider adapters translate the same Igor grammar.

Step 12 starts from `context.sh`/`knowledge.sh` and
`request_boundary.py`/`privacy.py`. Today context includes broad direct host
probes, all active module hooks, catalog text, saved primer/WIP/diagnosis and
patterns. Memory already uses the Wave D fact path, but much context has no
item-level provenance or relevance filter. `IGOR_REFERENCE_V1` and the
last-mile redaction boundary are the transport authority to preserve.
`core/ai/operations.py` records bounded private AI audit; the recovery
journal records actions separately. Neither is currently a typed,
automatically selected operational-history context source.

## Step 11: canonical capability contract

### Identity, provider and availability

The canonical ID is a stable dotted operation name, for example
`system.service.restart`, `package.install` or `nextcloud.files.scan`. Use the
existing Module API v2 ID grammar (`[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*`),
with at least two dot-separated semantic segments for new capabilities.
`legacy.<owner>.<action>` remains the transient v1 namespace and is never
silently treated as a substitutable canonical ID. ID denotes the operation's
observable contract, not its Bash function, OS command, provider or menu
label. A material input/outcome change requires a new contract version or ID;
the initial descriptor records `capability_version: 1`.

The loader supplies provider identity `(owner, source contract, handler)`;
module JSON cannot claim another owner. Core platform capabilities use
`owner=core` through the same registry query shape. Multiple active providers
may declare one ID, as Wave C already permits. With one active executable
provider, selection is automatic. With more than one, resolution is
`ambiguous` with sorted provider IDs and **no execution**; a caller may name
an explicit provider in a structured request, and Igor still checks its
activation, compatibility and policy. No priority or provider solver is
introduced. Zero providers is `unavailable`, with missing/disabled/failed or
requirement reasons from the contribution index. Disabled/unavailable owners
are absent from AI advertising and dispatch; inspection may show their
inactive declarations and reasons. Recheck owner, requirements and selected
descriptor just before execution. Alias names belong to an Igor-owned
compatibility map at the interface boundary; alias resolution yields exactly
one canonical ID and never changes tier, provider or arguments. No aliases
are required for the first slice.
Explicit provider selection for one invocation does not relax D019: a
module-wide `required_capabilities` edge still requires one unambiguous
active executable provider unless its contract instead names an exact module.

Current v1 actions project as `legacy.<owner>.<action>` with their current
no-input function, owner and tier. `run_igor_action` remains the supported
legacy entry point during migration. A canonical mapping is explicit and
reviewed: register one v2 descriptor/adapter, route the old action name to
that descriptor, and suppress its separate legacy execution for that consumer.
The mapping must preserve or raise its effective tier and preserve the old
behavior or document its intentional change. V1 `provides` tokens, `ai_tools`
prose and `openai_params` are not capability declarations. Do not infer
canonical operations from a function name or a model description.

### Descriptor and structured inputs

The v2 capability descriptor extends the existing JSON contribution record.
The minimum accepted fields are `kind`, `id`, `handler`,
`capability_version`, `description`, `inputs`, `safety`, `privilege`,
`preconditions`, `verification`, `recovery`, `affects`, and existing `requires`.
`description` is user-facing reference prose; the other fields are typed
contract data validated before registration. `handler` uses the existing
Bash adapter and JSON envelope. The trusted Core adapter may supply its own
descriptor rather than a module file. A bare Wave C capability descriptor
without these Step 11 fields remains visible as `contract_incomplete`, never
executable.

`inputs` is a deliberately small JSON object schema: named properties with
`type` (`string`, `integer`, `boolean`, `enum`, `object_id`, `path`,
`secret_ref`), `required`, bounded length/range or allowed values, and
`additionalProperties=false`. No implicit coercion, shell fragments,
open-ended schema keywords or unknown fields. `enum` values must be literal;
names/paths use named Igor validators (unit/package name, confined path,
object ID) after type validation. Paths are resolved under an explicitly
declared root/scope, reject traversal and unsafe links, and are not composed
as shell text. A descriptor declares accepted secret-reference namespace and
purpose; the model supplies only an opaque reference. Public descriptions
and examples never replace machine validation. Canonical JSON of validated
arguments is retained for the approval record and provider invocation;
model prose or a later tool message cannot modify it. Missing/invalid input
fails before policy or handler execution.

Illustrative declaration for the bounded Wave E CHANGE fixture:

```json
{
  "kind": "capability",
  "id": "system.service.restart",
  "capability_version": 1,
  "handler": "system__restart_service",
  "description": "Restart one managed systemd service.",
  "inputs": {"properties": {"unit": {"type": "string", "validator": "systemd_unit"}}, "required": ["unit"], "additionalProperties": false},
  "safety": {"tier": "CHANGE"},
  "privilege": "required",
  "preconditions": [{"kind": "service_exists", "input": "unit"}],
  "verification": {"kind": "service_state", "input": "unit", "equals": "active", "required": true},
  "recovery": {"class": "best_effort"},
  "affects": [{"object": "service", "input": "unit"}],
  "requires": {"platform_families": ["debian", "arch"]}
}
```

This is a **target contract example**, not a currently valid Wave C
`host.json` record. The implementation adds strict kind-specific validation
to `module_contract.py`; it does not loosen generic unknown-field rejection.

### Safety, privilege and preconditions

The effective tier is determined by trusted descriptor metadata and any
trusted Core operation adapter, taking the more restrictive tier if both
apply. A capability may declare a fixed `READ`, `CHANGE` or `DESTROY` tier;
an input-dependent trusted adapter may raise it for a specific validated
operation. It may never downgrade the descriptor floor. Missing/invalid tier
is unavailable. Module knowledge, handler output and AI prose cannot classify
or downgrade an action. `core/ai/safety.sh` remains the one approval authority:
Guide proposes READ; Assist/Executive may run READ; Assist confirms CHANGE;
Executive may auto-approve structured CHANGE where policy permits; DESTROY
always needs exact `YES`. Core policy/denylists remain additional gates.

`privilege` is `none` or `required` for the exact operation, with a trusted
adapter allowed to raise `none` to `required`. It is not authorization. The
dispatcher freezes the selected provider, validated arguments, tier,
privilege requirement and execution specification in its pending approval.
After approval and revalidation, the existing backend PTY path performs sudo
authentication when needed. For `privilege=required`, a reviewed Core adapter
must have resolved the exact privileged argv from validated inputs before
approval; the existing broker executes that argv with non-interactive sudo
after authentication. The module handler may coordinate unprivileged work but
cannot issue its own password prompt or substitute a new privileged command.
A provider without this adapter is unavailable as a v2 privileged capability.
This is the narrow Step 11 bridge over the current platform argv resolvers,
not a second sudo broker. No password, sudo token or authentication transcript
enters AI context, audit or handler input.
Privilege failure produces `not_executed` and no handler call.

Preconditions are a short ordered set of typed, deterministic checks, not a
rule language: active module/capability requirement, platform feature,
validated path existence/type, package installed, service exists, or a
specific System Model fact key/value/availability. A trusted Core adapter or
named reviewed provider validator may implement a check when a declarative
predicate is insufficient. Arbitrary text conditions are invalid. Evaluate
before approval for display, then recheck immediately before execution after
approval/authentication as appropriate; any change fails closed and asks for
a fresh request. Observed facts must be `known` and fresh; stale/unknown facts
cannot satisfy a precondition. An explicit bounded observer refresh is a
separate Igor action, not an inspection query side effect. Validator handlers
cannot set tier or approve their own result.

### Invocation, verification and result

One backend invocation serves AI, CLI, TUI and later healing/automation:

1. Resolve canonical ID and active provider; reject absent or ambiguous.
2. Validate/canonicalize inputs, effective tier and execution specification.
3. Evaluate availability and preconditions; create an inspectable proposal.
4. Apply existing policy and approval, preserving exact frozen operation.
5. Recheck owner/descriptor/preconditions; mediate required OS privilege.
6. Invoke the v2 provider through the Wave C adapter with bounded timeout.
7. Run declared deterministic verification and emit a structured result.

The provider returns the existing `status/result` envelope, but its reported
success is only **execution success**. Igor stamps capability ID/version,
provider, operation ID, tier, approval, privilege outcome, affected objects,
timestamps and verification evidence. For state-changing v2 capabilities,
`verification.required=true` whenever a deterministic query exists. A
verification declaration names a trusted predicate/adapter, expected value,
target derived from validated inputs, timeout/retry bound and evidence source.
It cannot be prose or an AI call. The verifier queries the live platform or
freshly refreshes the relevant System Model observation **after** execution;
it cannot accept an older cached `known` fact as proof. A fact must be fresh
and have a post-execution observation time/attempt ID. If refresh fails or
returns stale/unknown, verification is `unknown` or `failed`, never success.
The platform query may be authoritative verification evidence even before a
corresponding System Model property exists; Igor can later ingest its
observation through the normal model boundary. No provider writes model
truth directly.

The result separates `execution_status` (`not_executed`, `failed`,
`succeeded`) from `verification_status` (`not_applicable`, `passed`, `failed`,
`unknown`, `unavailable`). If execution succeeds and verification fails, the
overall outcome is `unverified_change`, not success or an automatic rollback.
Evidence identifies query/check ID, object, observed value or bounded safe
summary, source, observed time, expected value and failure reason. AI receives
this structured result as reference data and may summarize it; it cannot
overwrite it. Inspection exposes the same fields. Existing AI audit and
recovery journal remain compatibility inputs until Step 15 gives operational
episodes one authoritative history contract; Wave E records operation IDs
and redacted metadata without inventing a new persistent history store.

Illustrative execution-zero/verification-failed result (runtime stamps IDs
and times; evidence values are bounded and scrubbed):

```json
{
  "operation_id": "op-123",
  "capability_id": "system.service.restart",
  "provider": "system",
  "execution_status": "succeeded",
  "verification_status": "failed",
  "outcome": "unverified_change",
  "affected_objects": ["service:systemd:nginx.service"],
  "verification_evidence": [{"check_id": "systemd.unit_state", "object_id": "service:systemd:nginx.service", "expected": "active", "observed": "inactive", "observed_at": "2026-09-27T10:00:01Z"}]
}
```

`affects` contains exact object selectors derived from validated inputs,
for example `service:systemd:nginx.service`, `package:docker.io`, or
`host:local`, following Wave D object identity rules. It expresses
scope for approval, inspection, verifier targeting and later event/history/
plan correlation. It is not a relationship graph or a claim that the object
currently exists. Dynamic affected objects outside the declared scope cause
validation failure or require a new approval. Step 17 owns relationships.
For the fixture descriptor, the `service` selector plus validated `unit`
constructs the Wave D `service:systemd:<unit>` identity; the module cannot
return an arbitrary object ID after execution.

Recovery is metadata, not an implicit undo button. A state-changing
descriptor names one of `reversible`, `best_effort`, `compensating_action`,
`snapshot_required`, `irreversible`. `reversible` or `compensating_action`
may reference another canonical capability with its own inputs, tier,
preconditions, approval, privilege and verification; it does not execute
automatically just because the first action failed. `snapshot_required`
names a verified snapshot precondition before approval. `best_effort` states
what may be attempted but makes no success guarantee. `irreversible` and
unavailable recovery are shown before approval. A recovery invocation is an
ordinary capability invocation and is verified where practical. These
declarations implement D028's contract without building a recovery engine.

### Secret references

A `secret_ref` is a validated, owner/scope-bound opaque identifier, never a
password string. Igor's smallest Wave E secret-use boundary resolves it only
after capability validation, policy approval and privilege mediation, at the
last possible point before the authorized subprocess/integration needs it.
The resolver checks owner/purpose, file containment and permissions against
existing `secrets/` sources; the reference may be shown as `configured` or
`missing`, never expanded in a prompt. The value is passed only by the
explicit provider adapter (prefer private fd/stdin over argv/environment
where practical), not returned in the handler result. Audit records operation,
reference ID/purpose, consumer and access outcome/time, never value or secret
path if sensitive. Existing scrub/redaction still applies to output, events
and errors. A provider that cannot avoid exposing a value through logs or AI
is unavailable for that secret-using v2 contract. This boundary does not
choose a new storage layout; the Ownership Foundation later formalizes
canonical secret ownership, migration and reset.

### Q010: raw shell fallback

The `host`/legacy `execute` paths remain an explicit **unstructured fallback**
when no equivalent registered, available capability fits. AI should receive
the matching capability first. Igor rejects recognized equivalent shell
forms for canonical operations at dispatch and points to the capability;
this is a maintained exact-command/argv mapping for supported operations,
not a claim to solve arbitrary shell semantic equivalence. A disabled or
unavailable module does not authorize an AI shell workaround for its domain
operation. An operator can still deliberately request an OS command through
the existing shell interface under its normal safety/approval policy; that
does not activate a disabled module.

Bounded allowlisted READ discovery remains possible, including current
`journalctl` and safe host probes. Unknown commands are at least CHANGE.
AI-proposed raw CHANGE requires **explicit approval even in Executive**;
raw DESTROY requires exact `YES` in every mode. Guide still proposes READ.
The existing hard denylist, command validator and redirection/substitution
classification remain. The legacy `execute` heredoc prohibition is applied
to every AI raw-shell entry point; semantic tools still reject shell operators
and substitutions as data. The current READ parser accepts only allowlisted
commands, including bounded safe `;`, `&&`, `||` and pipeline compositions;
its sole READ redirection is stderr discard to `/dev/null`. Other
redirections, command substitutions (`$()`/backticks), parameter expansion,
globs and unsupported shell operators are never automatic READ. They require
explicit CHANGE/DESTROY approval if otherwise permitted, or are blocked.
Unknown privilege
requirements fail closed; an explicit sudo operation follows the existing
approval-before-PTY-authentication sequence and executes the exact approved
command. Igor does not synthesize a different command after approval.

Raw shell has no capability-level verifier or recovery guarantee. A caller
may request a separate deterministic verification capability/query after it,
but the shell result itself is `unstructured`, with process exit and output
recorded and `verification_status=unavailable` unless Igor ran a named
postcondition. It cannot update System Model truth from prose or exit code.
Audit records fallback reason, command hash/redacted bounded preview, tier,
approval, privilege and outcome. The Step 11 implementation must preserve
existing safe shell use while adding these stricter AI fallback rules; it may
not bypass them via legacy `execute` or provider-specific parsing.

### Minimal structured plans

A plan proposal is an ordered, inspectable value: `plan_version`, intended
outcome, typed object references, ordered steps (`capability_id`, optional
provider, validated inputs), step preconditions, affected objects, effective
tier/approval point, privilege, verification and recovery, plus an optional
final deterministic check. AI may propose these fields; Igor resolves and
recomputes every authoritative field from registered descriptors. A resolved
plan is immutable and has a digest; changing a step/input/provider after
approval requires re-resolution and approval. Wave E implements plan
validation, resolution and read-only inspection/dry-run for a small ordered
list; actual execution may invoke one step at a time through the normal
capability API with individual approvals and result capture. No plan-wide
blanket approval, durable scheduler, automatic compensation, event trigger or
installation orchestrator is promised. Later work adds those only against
the same resolved-step semantics. Initial sequential execution stops after a
failed precondition, execution or required verification and records completed
steps; it neither silently retries nor runs recovery. Before each next step,
Igor rechecks its frozen provider, inputs and current preconditions. Recovery
requires a separate capability request and approval.

### Inspection surface

Provide backend JSON queries `capability_list` and `capability_inspect(id,
provider?)`, including installed declarations and active executable views.
They answer ID/version, owner/provider/source, selected or ambiguous state,
unavailable reason, validated input schema, effective safety rule, privilege,
preconditions, verifier and its last result, affected-object template,
recovery class and secret-reference requirements without values. A
`capability_result(operation_id)` query exposes execution versus verification
and evidence for the running session. A later TUI panel may project these
queries. Inspection is read-only and cannot refresh facts, authenticate or
execute a handler.

## Step 12: Context Engine contract

`Context Engine` is a selector/formatter in the **existing** AI context path,
not a second prompt renderer or request boundary. It takes a structured
selection request (user intent/domain, named object, contemplated capability,
current task/investigation reference, explicit user request) and returns a
bounded ordered set of reference items. First-pass matching is deterministic:
exact object/capability match, active owner/domain match, then relevant
health severity and freshness. Core guidance needed for the task is always
present; an explicit user request can include broader non-secret context.
Intent/domain matching uses registered capability and source tags plus
validated object references; model-suggested terms may affect selection but
cannot create a fact, capability or owner.
Tie-breaking is stable by source kind, ID and time; per-source and total item/
byte limits make selection inspectable. No embeddings or vector database.

Each item has `id`, `kind`, `owner`, `source_id`, `source_version` where known,
`object_id`/capability ID where relevant, `recorded_at`, freshness or
availability, sensitivity label, selection reason and bounded content/value.
Sensitivity is `public`, `status_only` or `secret`; `secret` fields are omitted,
and `status_only` fields expose a non-secret state such as `configured`.
The source and selection reason survive assembly and outbound scrubbing.
Items can be `core_guidance`, `system_fact`, `health_result`,
`module_knowledge`, `capability_metadata`, `config_status`,
`legacy_context`, `operational_history`, `local_learning`, and later
relationship/deployment references. Wave E reads only real sources: core
guidance, Wave D fact/health
queries, active v2/legacy module knowledge, available capabilities, and
non-secret configuration status where an authoritative query exists. Current
AI audit/journal entries may provide selected bounded history **references**,
not authoritative state or a blanket prompt dump. Later history,
relationships and learning plug into the same item envelope when their own
authorities exist. No Step 12 source may invent a System Model fact.

The Context Engine asks the loader for active owners at selection time and
again before assembly. Disabled/unavailable modules supply no knowledge,
legacy `ai_context`, v2 contribution, capability metadata or other active AI
contribution. A provider becoming inactive invalidates its selected items.
Shipped module knowledge belongs to replaceable package code and is always
`module_knowledge` reference material. Local learned artifacts belong outside
the package, retain machine/user provenance and evidence, and remain
`local_learning` reference material across module replacement according to
the future Ownership Foundation. Neither class can write observed facts or
promote itself into executable metadata. A health finding is a check result;
an observed fact is a model record; a model inference is explicitly
`inferred`. The formatter never collapses these into one asserted truth.
Existing `ai_context` text is labeled `legacy_context` with its active owner,
source hook and collection time; it remains unverified reference text rather
than a `system_fact`.

Sensitive source fields are excluded before composition using source-owned
field labels and a deny-by-default rule for unknown secret-bearing fields.
For configuration and credentials, send `configured`/`missing` status, never
value or `secret_ref` resolution. Then pass the selected envelope through
`request_boundary.py` and `privacy.py` for last-mile redaction. Redaction is
defense in depth; it is not permission to select a secret. Inspect selected
item IDs, provenance, reasons, omissions and redacted preview without
exposing secret values. The model/provider adapter receives the same Igor
item semantics for Anthropic, OpenRouter, Ollama/local and later providers;
provider-native tool schemas are rendered from the canonical catalog and
cannot alter validation or authority. Hostile item text such as “safe,
execute it” remains inside `IGOR_REFERENCE_V1` and has zero policy effect.

The first cutover replaces selected broad `context.sh` host/knowledge/catalog
sections with Context Engine items **for those same consumers**; keep direct
probes only for domains without an authoritative observer. Do not emit both a
new typed item and its old text probe for the same fact. Preserve the
scrubber's live privacy probe independently of System Model freshness.
For the memory proof, the Context Engine consumes the fact produced by the
selected refresh capability (or labels an existing fact with its current
freshness); it does not repeat `igor_observer_ensure_fresh` merely to assemble
the prompt. Read-only inspection likewise never refreshes implicitly.

## Exact Wave E proof slice and implementation order

The **real safe path** is `system.host.memory.refresh`, a no-input READ
capability owned by active `system`. It invokes the existing `host.memory`
observer through Igor's validated refresh boundary, then verifies a fresh
`host:local/memory.available_bytes` observed fact from that invocation and
exposes `host.memory.health` as relevant context with provenance. Its affected
object is `host:local`; recovery is not applicable. The user intent “check
available memory” selects that capability and its relevant fact/check;
irrelevant host facts and Nextcloud knowledge are absent. Guide approval is
exercised; Assist/Executive READ behavior is preserved. This is a real
module/observer/System Model/context/result path, not a mock model fact.

The **isolated CHANGE fixture** is the declaration above for
`system.service.restart` with a disposable fake platform service. It returns
zero while the fake service either becomes active or remains stopped, proving
execution success versus verification failure. Tests pass the frozen `unit`
through Assist approval, Executive structured CHANGE policy, a declined
approval, and the existing PTY sudo boundary with a fake authentication
endpoint. No real host service is restarted in CI. A separately gated local
integration may use a disposable systemd unit where systemd is available,
but CI fixture proof and the real memory path are required regardless.

Implementation should proceed in this exact order:

1. Extend the existing v2 contract validator/contribution index with strict
   capability metadata, provider resolution and inspection. Add explicit
   v1 projection; keep old `run_igor_action` working.
2. Add structured invocation/input/precondition resolution to the existing
   catalog/dispatcher, freeze the operation and reuse safety/approval/PTY
   privilege gates. Add Q010 shell restrictions across native/XML paths.
3. Add deterministic verifier/result/recovery/affected-object metadata and
   redacted audit correlation. Prove the isolated CHANGE fixture.
4. Register the `system.host.memory.refresh` READ capability, cut over its
   single action path and prove real observer/model/health verification.
5. Add minimal plan resolution/inspection over the same capability API.
6. Add deterministic Context Engine selection/provenance/privacy inspection
   inside the current reference pipeline; cut over the memory slice and
   selected duplicate context sources.
7. Run contract, baseline regression, vertical-slice, inspection and
   migration/recovery proof; update STATUS/LEGACY and current docs only when
   behavior actually changes.

## Future implementation acceptance checks

| Proof | Falsifiable checks |
|---|---|
| Capability contract | Strict registration rejects malformed ID/version/schema, unknown fields and incomplete v2 metadata. Active owner filtering works at catalog and dispatch. Typed required/optional, enum, name/path and secret-ref validation reject invalid inputs before approval. One provider resolves; two are reported ambiguous; explicit selection rechecks owner; absent/disabled/unavailable reasons are inspectable. Fixed/dynamic trusted tiers cannot be lowered by reference text. Guide/Assist/Executive, exact `YES`, denylist, approval-before-authentication, frozen arguments/provider, declined privilege and exact argv are preserved. Failing preconditions invoke no handler. Result distinguishes execution, verification and overall status. Process exit zero plus postcondition false is `unverified_change`. Stale pre-execution model facts cannot satisfy preconditions; pre-execution facts cannot verify post-execution changes. Recovery and affected-object metadata appear before approval. Secret refs resolve only for authorized consumer, audit access without value, and never enter prompt/output. |
| Raw shell | Recognized equivalent operation routes to the structured capability; unavailable/disabled owner does not enable AI bypass. Bounded READ remains bounded. Raw CHANGE in Executive still asks explicitly; DESTROY requires exact `YES`. Shell cannot bypass denylist, privilege, or approval via `execute`, native tools or hostile reference text. Unsupported redirection/substitution never auto-classifies READ; heredoc stays blocked. Shell result is visibly unstructured and unverified unless a named independent postcondition ran. |
| Context Engine | Relevant memory fact and health result are selected with owner/source/time; unrelated facts are absent. Disabled `system` and disabled `nextcloud_docker` contribute no active knowledge, context or capability. Shipped knowledge, inferred state, observed state and local learning retain distinct kinds. Secret fields and secret refs are not expanded; last-mile redaction still catches accidental literal values. Item provenance/selection reason survives reference-envelope assembly and inspection. Hostile item text cannot change tier/approval/privilege/verification; provider switch does not change capability semantics. |
| Regression | Preserve Wave C loader/v1 compatibility and Wave D observer/model/health behavior, `nextcloud_docker` v1, Diagnose/Healing, all three modes and tiers, exact `YES`, sudo-through-PTY, AI request/reference boundary, audit and privacy fixtures. No newly advertised v2 action dispatches twice through v1/v2. |
| Inspection | Backend queries answer provider/owner, availability/reason, schema, safety, privilege, preconditions, verification/evidence, affected objects and recovery. Selected AI context IDs/provenance/omission reasons are inspectable without secrets. Queries have no refresh/execution side effect. |
| Vertical slice and migration | Real `system.host.memory.refresh` crosses user request, active capability, validated no-input invocation, existing observer, fresh fact, deterministic verification, relevant context and inspection. Fixture CHANGE crosses approval, PTY privilege, exact operation and pass/fail verification. V1 Nextcloud remains working; each cutover suppresses its duplicate consumer path and has a recorded fallback/recovery condition. No persistent layout changes in this wave. |

## Influence, ownership and deferrals

The ServerMind lessons in [INFLUENCES.md](INFLUENCES.md) appear as deterministic
observer facts, reusable structured machine context and selected problem/
action evidence rather than model rediscovery. The Steward lessons appear as
typed capability/plan references, proposals separated from execution, and
local learning separate from module code. Igor deliberately keeps a local
Linux-first, detachable module runtime, deterministic approval and PTY
privilege boundary; neither external project supplies authority or a runtime
dependency.

Wave E needs only a narrow secret-reference resolver and context source
ownership metadata now. The future Ownership Foundation must settle canonical
paths, secret/config/state lifecycles, local-learning storage/reset, and
history/investigation retention before broad module migration. Q003, Q007,
Q008, Q009, Q011 and Q012 stay at their roadmap stages. Step 13 events,
Step 14 automation, Step 15 durable history/investigations, Step 17
relationships, broad Nextcloud migration, advanced provider solving and
automatic recovery remain outside this gate. No architecture decision blocks
starting the bounded Wave E implementation; completing Wave E still requires
the proof above.
