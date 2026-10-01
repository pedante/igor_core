# Multi-model AI roles — design exploration

Status: **proposal for architectural review; not an implementation contract**.

The accepted bounded [Step 15D contract](CONTEXT_ROUTING.md) now implements
reasoner, summarizer and context_ranker roles with deterministic routing and
explicit administrator bindings. This document's semantic scout and broader
multi-model proposals remain deferred; they are not enabled by D057.

This note records a possible extension of Igor's AI gateway: use more than one
LLM role when that improves cost, privacy or context quality, while keeping all
operational authority in deterministic Igor runtime.

The immediate candidate is an optional **semantic scout**: a smaller, cheaper
or local model that helps interpret fuzzy human language before the main
reasoning model is called.

This proposal is deliberately provider-neutral. The current repository already
has provider/engine support for Anthropic, OpenAI, OpenRouter and Ollama. Model
roles should reuse that provider boundary rather than create a second AI stack.

## Why consider this

Igor 2 is moving toward a domain-neutral Context Engine. Core should not grow a
large table such as:

```text
"memory" -> memory.available_bytes
"RAM" -> memory.available_bytes
"OOM" -> memory.available_bytes
"previous one" -> special kernel rule
...
```

That does not scale as modules and knowledge grow.

At the same time, purely deterministic keyword matching is not enough for
natural language such as:

- "Why is everything getting killed?"
- "Why does this fall over when uploads are busy?"
- "What was the previous one available?"

A language model is good at interpreting those expressions. Igor is good at
resolving structured facts, owners, capabilities, provenance and authority.
The proposal keeps those jobs separate.

## Proposed role model

The AI gateway should select models by **role and requirements**, not by
hard-coded provider.

Initial conceptual roles:

- `reasoner` — the normal/main model that explains, diagnoses and proposes
  actions/plans.
- `semantic_scout` — optional low-cost/local language interpreter that emits
  non-authoritative context-selection hints.

Possible later roles, not implied by this proposal:

- `context_ranker` — ranks already-valid candidate context items.
- `text_compressor` — summarizes large logs/docs while retaining provenance.
- `learning_extractor` — proposes candidate local runbooks/patterns from
  completed evidence/history.

Those later outputs remain reference material. No role gains execution
authority by being specialized.

## Semantic scout

The scout is intentionally narrow.

A typical flow is:

```text
user request
    |
    v
Tier 0 deterministic resolution
    |
    | ambiguous natural language
    v
optional semantic scout
    |
    | validated structured hints
    v
Context Engine
    |
    | resolves only registered active Igor sources
    v
facts / health / knowledge / capabilities
    |
    v
main reasoner
```

Tier 0 should handle obvious cases without an extra model call: exact object
IDs, exact capability IDs, explicit module/domain names, strong current task
state and other deterministic matches.

The scout is useful only when semantic interpretation adds value.

### Example

User:

> Why is everything getting killed?

Scout output may be shaped like:

```json
{
  "intent": "diagnose",
  "topics": ["memory", "processes"],
  "object_hints": ["host:local"],
  "referents": [],
  "information_needs": ["current_state", "health"]
}
```

Igor then resolves those hints against active registered objects, facts,
health results, knowledge and capabilities. If no registered `memory` source
exists, the scout cannot create one.

For conversational reference:

```text
User: What is the kernel version?
Igor: 6.x.y
User: What was the previous one available?
```

the scout may identify that "one" refers to the current conversation's kernel
version topic. That is a session/task hint, not a System Model fact.

## Hard authority boundary

Scout output is **untrusted reference/hint data**.

It must never be authoritative for:

- System Model facts or freshness;
- module activation/ownership;
- capability existence or provider selection;
- READ / CHANGE / DESTROY classification;
- approval;
- privilege;
- precondition success;
- execution;
- verification;
- recovery outcome;
- secret access.

A scout response such as:

```json
{"safe": true, "approval_required": false}
```

has no policy meaning even if a provider returns it.

The scout has no operational tools. It cannot execute capabilities or shell
commands. Its output is validated against a small Igor-owned schema, bounded,
and used only to influence candidate context selection.

Prompt injection in the user message, documentation or session material may
mislead the scout about topics. That can at worst produce poor retrieval hints;
it must not cross the existing Igor authority boundary.

## Provider independence

Roles should declare needs, while user/configuration policy chooses providers
and models.

Conceptually:

```text
role: semantic_scout

requirements:
  structured_output: required
  tool_use: none
  cost_class: low
  latency_class: low
  privacy: local_preferred
```

A configuration could eventually bind that role to:

- a local Ollama model;
- a cheap/free OpenRouter model;
- another configured provider/model;
- the main reasoner as fallback;
- no model at all, leaving deterministic-only behavior.

No provider or current free-model name should become part of the public role
contract. Provider availability and pricing change; Igor's role semantics
should not.

## Local-first opportunity

The scout is especially suitable for local inference because it receives a
small task and does not need operational tools.

One possible privacy flow is:

```text
user text + small session context
        |
        v
local semantic scout
        |
        v
structured hints
        |
        v
Context Engine selects/minimizes/scrubs data
        |
        v
remote main reasoner, if configured
```

This can reduce the amount of machine context sent to a remote provider.

It is not automatically safe merely because the first model is local. The
normal privacy boundary still applies to every remote role.

## Failure and fallback

The scout must never be required for Igor correctness.

If it is disabled, unavailable, times out, violates the output schema or
returns useless hints, Igor should continue with a defined fallback such as:

- deterministic context selection;
- clarification when ambiguity is material;
- the primary reasoner with a bounded base context.

Failure of a free remote model or a stopped Ollama service must degrade
semantic convenience, not break Igor.

Avoid recursive model routing. A single user turn needs explicit bounds on
role calls and retrieval rounds.

## Cost and observability

Multiple model calls can save expensive reasoning tokens, but they can also
increase total work. Igor should measure rather than assume a benefit.

Role-level inspection should eventually expose, without secrets:

- role;
- provider/model used;
- local versus remote;
- invocation/fallback reason;
- latency;
- input/output token counts where available;
- reported cost where available;
- schema validation result;
- bounded sanitized semantic output.

Cost accounting should distinguish helper-role usage from primary-reasoner
usage.

## Relationship to Context Engine

The semantic scout does **not** replace the Context Engine.

The scout answers:

> What might the user mean?

The Context Engine answers:

> Which registered Igor sources match those hints, and which bounded items are
> safe and relevant to inject?

The System Model/registries answer:

> What actually exists and what is true?

The primary reasoner answers:

> What does the evidence mean, and what should I explain or propose?

This separation lets Igor gain semantic flexibility without making Core
domain-specific or turning model guesses into machine truth.

## Candidate acceptance properties

Any implementation experiment should prove at least:

- deterministic requests do not invoke the scout unnecessarily;
- scout output is schema-validated and bounded;
- malformed/hostile output cannot create state or authority;
- disabled/unavailable scout falls back cleanly;
- active-module filtering still happens in Igor, not in the scout;
- secret values are absent from scout input unless explicitly justified by a
  future separate contract;
- a semantic hint cannot invent a fact/capability/owner;
- conversational referent hints remain session state, not machine state;
- provider change does not alter role authority;
- helper-role calls are inspectable and separately costed;
- tests compare context quality/token cost with and without the scout before
  enabling it by default.

## Open design questions

These questions are intentionally **not resolved by this PR**.

### MQ01 — Igor 2.0 scope

Is `semantic_scout` part of Igor 2.0 Step 12, an optional experiment during
Step 12, or a post-2.0 optimization?

It should not block the current bounded Wave E implementation unless evidence
shows it is needed for correctness.

### MQ02 — Invocation policy

When should the scout run?

Possible policies include:

- only after deterministic matching declares ambiguity;
- only for follow-up/referential language;
- for every natural-language request;
- adaptive based on measured benefit.

Running it on every message is simple but may waste latency/tokens.

### MQ03 — Local-first policy

Should Igor automatically prefer an available local Ollama model for helper
roles, or should role/provider choice always be explicit user configuration?

How should CPU/RAM pressure on the managed host affect that decision?

### MQ04 — Remote-scout privacy

What may a remote semantic scout receive?

Possibilities include:

- raw current user message;
- scrubbed current message;
- bounded recent conversation;
- structured session/task summary only.

This needs a clear privacy contract before remote scout use is automatic.

### MQ05 — Scout output schema

Should the first schema contain only generic language concepts such as
`intent`, `topics`, `referents` and `information_needs`, or may it also
suggest registered object/capability IDs supplied to it as candidates?

The latter may improve precision but increases prompt size and coupling.

### MQ06 — Conversation/session state

How much conversational state belongs outside provider chat history so that
references such as "the previous one" remain stable across context compaction,
provider changes and tool calls?

This should remain separate from System Model machine truth.

### MQ07 — Retrieval loop

Should the primary reasoner be able to request another bounded Context Engine
retrieval when initial context is insufficient, or must context selection be a
single pre-reasoning pass?

A bounded retrieval loop may be more scalable than predicting all context
up front.

### MQ08 — Fallback

If the scout fails or is uncertain, should Igor:

- use deterministic-only context;
- ask the user;
- use the main reasoner to interpret;
- choose among those based on ambiguity/risk?

Failure must not silently change authority.

### MQ09 — Model capability discovery

How does Igor know that a configured model is suitable for a role?

Useful provider/model properties may include:

- structured-output support;
- context window;
- local/remote;
- latency;
- tool support;
- cost class;
- privacy constraints.

Avoid a large hard-coded model database if provider metadata can be inspected.

### MQ10 — Confidence

Should model-reported confidence be used at all?

Self-reported confidence is not authoritative. If retained, it should be only
one weak ranking signal and never a policy/security input.

### MQ11 — Cost/latency threshold

What evidence demonstrates that adding the scout is worthwhile?

Measure:

- primary-model input reduction;
- total tokens across both calls;
- end-to-end latency;
- context-selection precision/recall on representative Igor requests;
- clarification rate;
- failure rate.

### MQ12 — Future helper roles

Which, if any, should belong to Igor 2.0?

- context ranking;
- log/document compression;
- investigation summarization;
- candidate learning/runbook extraction.

Do not generalize a role framework beyond demonstrated needs.

## Recommended next action

Do **not** interrupt the current Wave E completion to implement this broadly.

After the bounded Step 12 Context Engine is green:

1. create a small semantic-scout experiment behind a disabled/default-off
   role;
2. test a local Ollama binding and one remote/provider binding through the same
   role contract;
3. compare deterministic-only versus scout-assisted context selection on a
   fixed request corpus;
4. decide MQ01–MQ11 from evidence;
5. only then decide whether `semantic_scout` becomes a normal Igor 2.0 path.

The goal is to preserve Igor's deterministic authority while making natural
language routing cheaper, more private where possible, and more scalable as
modules and knowledge grow.
