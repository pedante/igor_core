# AI specialist roles and bounded agents — design exploration

Status: **proposal for architectural review; not an implementation contract**.

This document explores where Igor and its modules could benefit from cheap,
free or local LLM calls beyond the proposed semantic scout.

It also defines terminology so Igor does not accidentally call every helper
model an "agent" or grow into an uncontrolled multi-agent system.

This proposal assumes Igor's existing authority rules remain unchanged:
models may interpret, rank, summarize, propose and explain; Igor-owned runtime
remains authoritative for state, ownership, safety, approval, privilege,
execution and deterministic verification.

## Terminology

### Model role

A **model role** is a named AI task contract.

Examples:

- `semantic_scout`
- `context_ranker`
- `text_compressor`
- `knowledge_extractor`
- `learning_extractor`
- `reasoner`

A role describes what output is wanted and what constraints apply. It should
not name a particular provider or model.

### Worker / specialist

A **worker** or **specialist** is one bounded invocation of a model role.

Example:

```text
role: text_compressor
input: bounded journal excerpt
output: structured summary
tools: none
authority: reference only
```

Most cheap/free-model opportunities in Igor fit this category.

### Agent

An **agent** is more than a single inference. It pursues a goal through multiple
steps and may maintain task state, request more information, use tools or
capabilities, and decide what to do next.

Examples:

- a troubleshooting agent that iteratively gathers evidence;
- an investigation agent that maintains hypotheses across several queries;
- a module-development agent that reads docs, drafts artifacts, tests them and
  revises its proposal.

Agents are therefore higher-risk and need explicit budgets, tool boundaries,
termination rules, observability and authority controls.

**Igor should prefer roles/workers when one bounded call is sufficient.**
Do not turn a summarizer, classifier or ranker into an agent without a concrete
need.

## Architectural principle

Cheap/free/local models should handle work where an imperfect answer is
recoverable through deterministic validation, stronger reasoning, user
clarification or retry.

A useful rule:

> Use cheaper models where being wrong means "Igor checks, retries or asks",
> not where being wrong means "Igor changed the machine."

The following remain deterministic Igor responsibilities regardless of model
price or locality:

- authoritative System Model facts and freshness;
- module activation and contribution ownership;
- capability registration/provider resolution;
- READ / CHANGE / DESTROY classification;
- approval;
- privilege;
- precondition satisfaction;
- exact execution;
- deterministic verification;
- recovery outcome;
- secret authorization.

## Candidate specialist roles

### 1. Semantic scout

Purpose:

- interpret fuzzy language;
- extract likely intent/topics/objects;
- resolve conversational references;
- provide non-authoritative hints to the Context Engine.

Example:

```text
"Why is everything getting killed?"
    ->
topics: [memory, processes]
intent: diagnose
```

This is explored separately in the multi-model roles proposal.

### 2. Context ranker

The deterministic Context Engine may discover many valid candidate items.
A cheap model can rank those already-valid items by likely relevance.

Example:

```text
candidate context:
  4 memory facts
  3 process health results
  8 system knowledge entries
  12 capabilities

cheap ranker:
  "these 7 appear most relevant"
```

The ranker does not create candidates, activate owners, alter provenance or
override hard inclusion/exclusion rules. Igor enforces source and byte limits.

Potential benefit:

- lower primary-model prompt cost;
- better signal-to-noise;
- scalability when Igor has many modules.

### 3. Log compressor

Large logs are expensive input for a strong reasoner.

A bounded worker can extract:

- repeated signatures;
- counts;
- first/last occurrence;
- timestamps;
- components;
- error families;
- small representative excerpts;
- uncertainties.

Original logs remain the evidence. The compressed representation is reference
material with provenance back to the source range/hash.

Potential uses:

- journalctl output;
- container logs;
- application logs;
- failed command output;
- build/test output;
- installer logs.

### 4. Event clusterer

Once Igor has a Domain Event Bus and Operational History, a cheap worker may
group related events into candidate episodes.

Example:

```text
service.failed
redis.connection_error
nextcloud.health_failed
service.recovered
```

may be proposed as one incident cluster.

The model does not rewrite event identity or timestamps. Igor stores clustering
as an inferred relationship until deterministic or human confirmation exists.

Potential benefit:

- reduce hundreds of events into a small number of meaningful incidents;
- improve notification quality;
- reduce strong-model calls.

### 5. Documentation extractor

Modules can ship or reference substantial documentation.

A cheap/local worker can propose structured extraction such as:

- terminology;
- concepts/topics;
- architecture components;
- configuration concepts;
- troubleshooting sections;
- dependencies;
- commands mentioned;
- possible observations/checks;
- possible capability candidates.

The result is candidate `module_knowledge` or module-development input. It is
not executable authority and does not automatically become a capability.

This can make new domains much easier to teach to Igor.

### 6. Knowledge tagger/indexer

A simpler role than documentation extraction.

Given an existing knowledge item, propose:

- semantic tags;
- domains;
- object kinds;
- symptoms;
- related concepts;
- likely query phrases.

This metadata can improve Context Engine retrieval without hard-coding domain
language in Core.

Module-supplied tags remain owner-scoped metadata. AI-generated tags retain
their provenance and can be reset/rebuilt.

### 7. Configuration explainer

Turn structured configuration into human language.

Example:

```text
backup.retention = 7
backup.schedule = daily

->
"Backups run daily and Igor keeps seven copies."
```

The model never changes config and never becomes the configuration parser.

Useful for:

- setup UI;
- review-before-apply;
- migration summaries;
- module settings;
- explaining why a capability is unavailable.

### 8. Plan explainer

The plan itself is resolved by Igor.

A cheap model may explain:

- what will happen;
- why each step exists;
- which steps need approval/root;
- recovery limitations;
- what verification will prove.

This avoids spending the strongest model on prose generated from already
structured plan data.

### 9. Result explainer

Translate structured results into concise user language:

- health results;
- capability results;
- verification evidence;
- installation results;
- recovery outcomes;
- unavailable reasons.

The authoritative structured result remains unchanged.

### 10. Notification writer

Given a structured domain event or incident, produce a human-friendly message.

Example:

```text
backup.failed
destination=nas
reason=unreachable

->
"Tonight's backup failed because the NAS could not be reached."
```

The notification writer should not decide event severity or whether an
automatic repair is authorized unless a separate deterministic policy says so.

### 11. Conversation/task compressor

Long AI conversations should not be Igor's operational memory.

A cheap worker can produce a bounded session/task summary such as:

- current topic;
- unresolved question;
- referenced objects;
- decisions already made;
- last relevant result;
- conversational referents.

This helps references such as "the previous one" survive model/provider
changes and context compaction.

The summary is session/task state, not System Model truth.

### 12. Investigation summarizer

For a durable investigation, periodically summarize:

- question/problem;
- evidence collected;
- hypotheses;
- disproven hypotheses;
- actions;
- findings;
- next unresolved questions.

The underlying structured evidence remains authoritative.

This can keep investigation prompts small even after many steps.

### 13. Hypothesis generator

Given observed evidence, propose possible causes or useful next questions.

Example:

```text
symptom: Nextcloud uploads fail
evidence: storage OK, database OK, memory pressure high

candidate hypotheses:
- process killed by OOM
- PHP worker limit
- application timeout
```

Hypotheses are explicitly inferred/reference data.

Igor or the main reasoner decides which deterministic observations/capabilities
can test them.

### 14. Learning extractor

After completed incidents/investigations, a cheap worker can propose candidate
local learning:

- symptom -> cause -> resolution patterns;
- reusable troubleshooting sequence;
- successful runbook;
- common false hypothesis;
- environment-specific note.

Each candidate should link to supporting evidence/history.

It remains `local_learning`, never trusted executable authority merely because
a model proposed it.

### 15. Baseline anomaly explainer

Step 16 should begin with transparent statistics and thresholds.

A cheap model can explain an already-detected anomaly:

```text
backup duration:
normal median 8m
today 34m
```

-> "Today's backup took about four times the recent median."

The statistical/anomaly decision should remain deterministic where practical.

### 16. Module-development assistant

A module-authoring workflow could use specialist calls to:

- read upstream documentation;
- propose module concepts/tags;
- draft knowledge entries;
- propose observer/check schemas;
- propose capability descriptors;
- generate test cases;
- summarize validation failures.

This may eventually become an actual bounded agent because it can iterate over
docs, generated artifacts and tests.

Promotion into trusted executable module code still requires Igor's review/
validation policy and, initially, human review.

### 17. Migration assistant

During configuration/module migration, a specialist may explain:

- old versus new layout;
- what changed;
- unresolved incompatibilities;
- user-visible effects.

It may propose mappings, but deterministic migration code owns data movement,
validation, cutover and recovery.

### 18. Model/role router

A small model might help estimate whether a request needs:

- no model;
- a cheap worker;
- the primary reasoner;
- a multi-step investigation.

This is potentially useful but risky because a bad routing decision can harm
quality or create loops.

Prefer deterministic routing first. If model-assisted routing is explored, it
must have strict fallback and budget rules.

## Module relationship

Modules should not implement provider-specific LLM calls as their normal API.

Instead, a module may eventually request an Igor-owned role:

```text
role: text_compressor
input: bounded owned log material
requirements:
  local_preferred
  structured_output
  tools: none
```

Igor's AI gateway decides whether the role is:

- available;
- allowed for that source/sensitivity;
- bound to Ollama;
- bound to OpenRouter or another provider;
- delegated to the primary model;
- disabled.

This preserves module portability.

A module can contribute domain vocabulary, knowledge and semantic metadata,
but does not choose which vendor/model Igor uses.

## Background intelligence

Later Wave F components create opportunities for low-cost background analysis.

Examples:

```text
many domain events
    -> cheap event clusterer
    -> a few candidate incidents
    -> strong reasoner only for unusual/important cases
```

or:

```text
completed investigations/history
    -> cheap learning extractor
    -> candidate local patterns
    -> deterministic evidence/provenance checks
    -> local_learning
```

or:

```text
large logs
    -> local compressor
    -> bounded summary
    -> main diagnosis model
```

Background calls must have explicit budgets and must not create unbounded
self-triggering loops.

## When does a specialist become an agent?

A worker becomes agent-like when it gains one or more of:

- an explicit multi-step goal;
- persistent task state;
- ability to choose the next operation;
- capability/tool access;
- iterative retrieval;
- retry/reflection loops;
- delegation to other workers/agents.

This should be a deliberate architectural transition.

For example:

### Not an agent

```text
log -> summarize(log) -> structured summary
```

### Bounded agent

```text
goal: diagnose incident
  -> request memory facts
  -> inspect relevant logs
  -> update hypotheses
  -> request service health
  -> propose next test
  -> stop when evidence is sufficient or budget expires
```

Even a bounded agent does not bypass Igor's capability/safety/approval/
privilege/verification runtime.

## Candidate role categories by risk

### Low-risk reference transformation

Good early candidates:

- text/log compression;
- explanation;
- tagging;
- notification wording;
- conversation summarization.

No tools. No authority.

### Medium-risk semantic/inference roles

Require provenance and explicit uncertainty:

- context ranking;
- hypothesis generation;
- event clustering;
- knowledge extraction;
- learning extraction.

Still no operational authority.

### Higher-risk agentic roles

Require separate design gates:

- multi-step investigation agent;
- module-development agent;
- autonomous remediation agent;
- planning agent that iteratively uses tools.

These need budgets, termination rules, tool allowlists, state ownership,
inspection and user-policy integration.

## Open questions

These questions are intentionally unresolved.

### AQ01 — Role registry ownership

Should Igor have a canonical AI-role registry similar in spirit to capability
registration, or should roles initially be a small Core-owned enum?

Do modules ever declare new roles, or only request Core-defined roles?

### AQ02 — Module access to AI roles

May any active module invoke a helper role, or must modules declare role usage
and data sensitivity in their contract?

How does Igor prevent a badly designed module from generating excessive calls?

### AQ03 — Provider/model binding

Should role bindings be:

- global;
- per role;
- per module;
- per task;
- dynamically selected from requirements?

Avoid making module packages depend on specific provider/model names.

### AQ04 — Free versus local preference

Should "free" ever be an architectural property?

Free-provider availability/pricing can change. A more durable configuration may
express:

- local preferred;
- zero/low cost preferred;
- privacy requirement;
- maximum latency;
- structured-output requirement.

### AQ05 — Cost budgets

What limits exist for:

- calls per user turn;
- tokens per role;
- calls per incident;
- background calls per hour/day;
- remote cost per day/month?

How are free-call rate limits treated?

### AQ06 — Local resource budgets

A local Ollama call is financially cheap but consumes CPU/GPU/RAM.

Should Igor suppress local helper models during:

- high memory pressure;
- CPU saturation;
- thermal constraints;
- backup/install workloads?

The managed machine's health may be more valuable than a "free" call.

### AQ07 — Privacy classes

Which role inputs may go to:

- local models;
- remote cheap/free providers;
- the primary remote reasoner?

Should every role declare allowed sensitivity classes?

### AQ08 — Prompt-injection exposure

Log/document/knowledge roles intentionally process untrusted text.

What common wrapper/schema/instruction boundary keeps those texts from being
treated as authority?

How should role outputs preserve the fact that source text was untrusted?

### AQ09 — Structured-output contract

Which roles require strict schema output?

Should Igor reject malformed output completely, attempt one repair call, or
fall back to another role/provider?

### AQ10 — Provenance

How does a transformed artifact point back to originals?

Examples:

- log summary -> source log range/hash;
- documentation extraction -> source document/version;
- learning candidate -> incidents/evidence;
- conversation summary -> session/message range.

### AQ11 — Caching and deduplication

Can deterministic inputs be hashed so repeated helper work is reused?

Examples:

- same documentation version;
- same log range;
- same structured capability result.

What invalidates a cache?

### AQ12 — Background scheduling

Which roles are allowed to run without a current user request?

Background model calls should integrate with the future Automation Engine,
rather than create a hidden AI scheduler.

### AQ13 — Agent termination

For actual agents, what hard bounds exist on:

- number of steps;
- wall-clock duration;
- tool calls;
- model calls;
- context growth;
- retries;
- delegation depth?

No recursive/open-ended agent swarm should be possible by accident.

### AQ14 — Tool access

Should specialist agents receive direct capabilities, or always request actions
through the same Igor intent/capability boundary used by the main reasoner?

The latter preserves one authority path.

### AQ15 — Agent state ownership

Where does an agent's task state live?

Temporary reasoning state, durable investigation state and operational history
must remain distinct.

### AQ16 — User visibility

How much should the TUI show?

Possible views:

- "used local helper model";
- role/provider/model;
- what was summarized/ranked;
- tokens/cost/latency;
- why a strong model was escalated.

Avoid overwhelming normal users while keeping expert inspection possible.

### AQ17 — Quality evaluation

What fixed request/log/document/incident corpus should Igor use to compare:

- deterministic-only;
- cheap helper;
- primary reasoner;
- helper + reasoner?

Measure quality, token reduction, latency and failure behavior before enabling
roles by default.

### AQ18 — Escalation policy

When may a cheap worker say "I am not sufficient"?

Should Igor escalate on:

- schema failure;
- explicit uncertainty;
- missing relevant sources;
- contradictory evidence;
- complexity threshold;
- user request?

Model self-confidence alone should not decide escalation.

### AQ19 — Learning feedback loops

How do we prevent local learning generated by a model from reinforcing its own
mistakes over time?

Candidate learning should require provenance/evidence and remain distinguishable
from shipped knowledge and observed facts.

### AQ20 — Role composition

May one role invoke another?

Example:

```text
investigation agent
  -> log compressor
  -> context ranker
  -> hypothesis generator
```

If yes, Igor needs a call graph, global budget and recursion/depth limit.

### AQ21 — Multi-model disagreement

If a cheap worker and the primary reasoner disagree, what happens?

For factual/operational matters, neither model wins: Igor's structured evidence
and deterministic verification remain authoritative.

### AQ22 — User control

Should users be able to choose:

- helpers off;
- local-only helpers;
- free/low-cost helpers;
- automatic;
- privacy-first;
- fastest;
- quality-first?

How much belongs in normal settings versus advanced configuration?

## Relationship to Igor 2 waves

Possible natural integration points:

- **Step 12:** semantic scout, context ranker, conversation/task compression.
- **Steps 13–15:** event clustering, notification writing, incident/
  investigation summarization.
- **Step 16:** learning extraction and baseline explanation.
- **Steps 17–18:** documentation/relationship assistance for composable domains.
- **Step 20:** user-visible role/cost/privacy inspection.
- **Step 22:** module-development assistance.

This mapping is exploratory. It does not add these roles to the Igor 2.0
completion criteria.

## Recommended sequence

1. Finish the bounded Wave E implementation first.
2. Establish the domain-neutral context invariant.
3. Experiment with `semantic_scout` behind an off-by-default role.
4. Add `text_compressor` as the next low-risk/high-value role.
5. Measure real token/cost/latency improvements.
6. Add conversation/investigation summarization only when corresponding state
   contracts exist.
7. Add learning extraction only after Step 15/16 evidence/history contracts are
   authoritative.
8. Treat any tool-using multi-step agent as a separate design gate.

The long-term goal is not "as many agents as possible".

The goal is:

> Give each kind of reasoning to the cheapest/safest model that can do it well,
> while keeping one deterministic Igor authority boundary.
