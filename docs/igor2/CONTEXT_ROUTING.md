# Step 15D — Context Relevance and Model Role Routing

Status: accepted bounded contract (D057); implementation evidence in
[STATUS.md](STATUS.md). This extends the existing Context Engine and provider
path, not a parallel context system or AI gateway.

## Ownership and interfaces

Igor collects candidates deterministically, checks eligibility, optionally
consumes a validated relevance judgment, enforces selection policy and assembles
the existing `IGOR_REFERENCE_V1` reference envelope. Routing binds an Igor role
to explicit administrator configuration. Neither component has an executor,
approval, privilege, observer-refresh or System Model writer handle.

`core/ai/context_engine.py` owns selection. Its existing `select_context` and
memory inspection remain compatible. The new interface is:

```python
selection = select_request_context(request, sources, active_owners=owners)
inspection = inspect_context(selection)  # content-free
judgment_request = build_relevance_request(selection)  # no model call
# A caller may supply a validated Judgment Contract record on a later call:
selection = select_request_context(request, sources,
    judgment_request=judgment_request, judgment_record=record)
```

`core/ai/request_context.py` adapts existing reference categories, owner-stamped
module knowledge, current read-only System Model/health queries, capability
descriptions and explicit history/investigation references. It publishes bounded
operational provenance through the existing audit/frontend event owners.
`core/ai/model_roles.py` owns pure `route_model` policy; `role_transport.py` binds
existing administrator settings for the current transport.

## Candidate and selection contract

Candidates have bounded ID, kind, owner, source ID/version, optional scoped
identity/object/capability references, provenance, recorded time, freshness,
availability, sensitivity, tags and content. Collection time is distinct from
source-recorded time; unknown source time stays absent and is not fabricated
for a judgment reference. Igor adds serialized content bytes, an approximate
byte/4 token estimate, sanitized content digest and selection
reason. Authority class distinguishes current-state projection, historical
evidence, investigation material, judgment, conversational reference and other
reference data. No class grants the model authority.

Supported source kinds retain Step 12's kinds and add `conversation`,
`investigation` and `judgment`. Configuration contributes status-only metadata
when a real owning query exists; no new configuration service or arbitrary
configuration reader is introduced. Secret candidates and unknown sensitivity
are excluded; secret-bearing System Model properties are excluded. Source-level
field filtering and last-mile privacy scrubbing remain mandatory.

Runtime selection requests accept `ids`, `tags`/`domain`, `object_id`,
`capability_id` and `scope_id`. Exact IDs are required references. Durable
history/investigation retrieval requires the caller's matching scope; it never
allocates one. Missing or mismatched evidence blocks that request visibly.
The programmatic selector also accepts `candidate_ids` and `references` as ID
lists. Natural-language keywords are not mapped to application domains in Core.
Registered property/source identifiers supply generic metadata; module owners
retain their vocabulary.

Eligibility rejects inactive owners, unavailable sources, wrong scope, unknown
kinds, malformed metadata and secrets before ranking. Explicit references,
object/capability matches and registered tags establish relevance tiers. An
explicit domain does not select unrelated facts merely because they share a host.
Mandatory/core guidance survives relevance filtering. Severity, time and ID give
deterministic ordering. Collection is capped at 512 candidates; selection at
32 items, 24,000 serialized bytes and eight items per source by default.
Unenumerated overflow is reported as a collection bound, not fabricated
individual exclusions. Required eligibility failures return
`insufficient_context`; required budget failures return
`context_budget_exceeded`. Neither is sent to a provider.

The existing conversation transaction coordinator remains responsible for
trimming and compaction. Selected evidence is a separate reference message;
the current protocol history and tool-call/result groups are mandatory and
cannot be split by the context selector. Bundled runtime policy and tool schemas
remain outside optional reference selection. The final serialized request has
a hard administrator byte limit (262,144 by default). Token estimates are
diagnostics, not provider tokenizer guarantees.

## Optional judgments and investigations

Default selection invokes no ranking model. A supplied D055 judgment is bound
to the generated `context.relevance` request, candidate metadata/content digest,
and closed candidate-ID schema. At most 32 eligible IDs enter that request.
Valid ranking can reorder optional candidates only within an existing relevance
tier. It cannot invent candidates, change metadata, remove required context,
override eligibility or expand budgets. Abstain, unknown, invalid/unbound
records, failures, duplicate/invented IDs and confidence below 0.5 (including
missing confidence) preserve deterministic ordering. Judgment ID, status,
validation, reason and self-reported confidence remain inspectable. Confidence
does not establish truth or permission.

An explicitly selected investigation contributes its question, hypotheses,
findings, evidence references and unresolved questions. Its attached judgments
are validated using D055 and remain distinct reference candidates. Explicit
history episode IDs resolve through Operational History's inspection service.
There is no recursive evidence gathering, automatic investigation attachment,
judgment creation or finding-to-fact promotion. A history outcome cannot satisfy
current preconditions or make an observation fresh.

## Roles and deterministic routing

The initial Core-owned vocabulary is `reasoner`, `summarizer`, `context_ranker`.
No module role registry, vendor-specific role, price database or optimizer exists.

| Trusted request type | Role / rule |
|---|---|
| `conversation` | reasoner / `conversation_reasoner` |
| `operational` | reasoner / `operational_reasoner` |
| `unclassified` | reasoner / `default_reasoner` |
| `summarize` | summarizer / `conversation_summarization` |
| `rank_context` | context_ranker / `context_relevance_ranking` |
| `inspect`, `local` | no model / local inspection or operation |

Unrecognized types fail closed. Ordinary assistant calls use reasoner;
the existing foreground conversation compaction uses summarizer. No extra
ranking/helper call is enabled. Local CLI/session commands remain local.

Bindings are closed objects containing `provider`, `model`, optional boolean
`enabled`, `available`, `tools`, and optional `output_formats` (`text`, `json`).
Supported transports remain Anthropic, OpenRouter and Ollama. Binding
availability is configuration, not a provider-health probe. `route_model`
checks output/tool requirements and optional context-budget metadata.
Summarizer/ranker are always tool-free; ranker requires JSON output.
Reasoner tools still pass the existing registration and deterministic dispatch
policy. A role's tool requirement never approves an operation.

The existing configured provider/model is the compatibility primary binding.
Absent reasoner/summarizer bindings inherit it; absent ranker is unavailable and
falls back to deterministic selection. An explicitly disabled/unavailable
binding does not silently inherit a different provider. No runtime retry,
escalation or cross-provider fallback occurs. A failed summarization preserves
the existing transaction-safe fallback. Provider failure remains an explicit
failure, not permission to transfer data elsewhere.

Configure optional bindings in existing AI settings ownership layers:

```bash
IGOR_AI_ROLE_BINDINGS='{"summarizer":{"provider":"ollama","model":"your-local-model"}}'
IGOR_AI_REQUEST_MAX_BYTES=262144
```

Optional output/tool declarations describe administrator-approved requirements;
no model name is used to infer pricing or reasoning depth. Latency/cost
optimization and automatic natural-language complexity classification are
deferred. Explicit bindings let operators choose a suitable summarizer without
the former vendor-specific model substitution.

## Provenance, inspection and persistence

Each actual request produces an `igor.context_routing` version-1 operational
decision linked by request ID. It includes selection policy/digest, included
metadata, omitted IDs/reasons, limits, optional judgment provenance, requested
and selected role, provider/model, rule/reason, constraint failures, request
bytes and estimated tokens. `prepared` means assembled for invocation, never
provider success. Existing response/audit records carry the invocation outcome
under the same request ID; no success is inferred from selection.

The existing 15UI panel displays the latest backend decision in Context / Routing.
Opening it performs no gathering, judgment, model request, refresh or routing
change. It renders bounded provenance, not prompts or private reasoning.

```bash
bash igor.sh --context inspect       # existing read-only memory inspection
bash igor.sh --context last          # latest retained decision metadata
bash igor.sh --context select '{"ids":["inv-OPAQUE","op-OPAQUE"],"scope_id":"scope:OPAQUE"}'
```

`select` is a read-only evidence selection preview, explicitly marked `preview`;
it does not invoke a model or allocate storage. `last` reads the existing audit
without module/configuration/AI startup and reports `not_recorded` when absent.
Inside chat, `context JSON` sets explicit references/tags for subsequent
requests, `context` displays that disposable request and `context reset` clears
it. Minimal context policy suppresses automatic evidence resolution even when
a selection request exists. The backend validates these inputs; the UI does
not decide routing.

There is no new durable context database, identity service or history schema.
Session decisions are disposable; optional metadata retention uses the existing
bounded private AI audit and respects audit-off. Records are operational
provenance only: **not durable knowledge or memory**, and never automatically
imported into an investigation or other owning subsystem. Restart cannot replay
an approval, route or operation from provenance. Audit failure/rotation is not
an operational-history migration or loss of System Model truth.

Existing provider/model settings remain the source of primary binding; missing
new settings use compatible defaults. History/investigation storage and export/
restore are unchanged. No state import, dual write or new persistent migration
is needed. Existing memory inspection remains available. Legacy domains lacking
typed source/relevance metadata keep bounded labeled legacy candidates; this
milestone does not claim a complete observer or knowledge migration.

## Authority and deferred work

Routing/context decisions cannot execute, approve, grant privilege, refresh
facts, alter System Model truth, activate modules, register capabilities,
satisfy preconditions, bypass AI-disable/security policy or change verification.
Judgments remain reference-only. Guide/Assist/Executive, READ/CHANGE/DESTROY,
exact `YES`, privacy and approval-before-PTY authentication are unchanged.

Deferred: automatic ranker/scout invocation, agents/autonomous gathering,
embeddings, compression services, workflow engines, remediation, provider
optimization/expansion, pricing, background AI, Jet/Laya, module-defined roles
and Step 20. Completion supplies Step 20's context/routing foundation only;
its normal-workflow/default-launch readiness remains a separate gate.
