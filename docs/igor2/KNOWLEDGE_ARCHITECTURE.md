# Igor Knowledge Architecture

Status: **accepted architectural direction; compiler/tooling deferred**. The portable representation and memory-boundary clarification below is accepted direction; it does not create runtime authority.

## Purpose

Igor should not depend on humans manually writing every module. The long-term
value of Igor is its ability to acquire, structure, retain and operationalize
knowledge about systems.

The goal is not an automatic module generator. The goal is a knowledge system
that can transform heterogeneous operational material into a structured model
that Igor can reason about and, when appropriate, compile into modules.

## Core model

```text
source material
    |
    v
Igor Knowledge Compiler
    |
    v
Operational Knowledge Artifact
    |
    +--------------------+
    |                    |
    v                    v
knowledge             operational objects
facts                 observers
relationships         checks
procedures            capabilities
options               playbooks
templates             responsibilities
requirements          verification
    |
    v
Igor module / knowledge pack
```

## Sources

Sources may include:

- documentation;
- installation guides;
- scripts;
- configuration examples;
- Docker Compose files;
- Agent Skills/AOH material;
- ServerMind and Steward patterns;
- existing Igor modules;
- incident reports;
- previous Igor investigations;
- user-provided operational knowledge.

Sources are evidence. They are not automatically truth.

## Operational Knowledge Artifact (OKA)

The intermediate representation between raw knowledge and Igor operation.

An OKA may contain:

- concepts;
- relationships;
- requirements;
- architecture options;
- procedures;
- configuration concepts;
- observers;
- checks;
- capability candidates;
- playbooks;
- verification methods;
- risks;
- unknowns;
- confidence;
- provenance.

The artifact preserves uncertainty and conflicting information instead of
forcing an immediate decision.

## Knowledge storage direction

Igor should separate:

### Raw knowledge store

Original documents, scripts and external material preserved with provenance.

### Knowledge index

Metadata for discovery:

- source;
- domain;
- version;
- compatibility;
- confidence;
- ownership.

### Operational knowledge model

Relationships and structured understanding used by Igor reasoning.

### Active operational packages

Modules, checks, capabilities and playbooks derived from reviewed knowledge.

## Portable representation and OKF compatibility

Igor should own the **Knowledge Artifact semantics** while keeping storage and
interchange replaceable. A useful portable artifact needs enough metadata to
answer:

- what kind of knowledge is this;
- who owns it;
- where did it come from;
- what scope/domain/version does it apply to;
- when is it stale;
- who/what verified it;
- whether it is shipped, imported or learned locally.

The preferred repository/export shape is human-readable content with structured
metadata, normally Markdown plus front matter. Where practical that shape should
be compatible with Open Knowledge Format (OKF) so knowledge packs can move
between Igor and other tools without requiring Igor to adopt an external memory
runtime.

OKF compatibility applies to **reference knowledge**, for example:

- documentation and operational notes;
- known failure modes;
- patterns and symptom/cause/resolution relationships;
- runbooks and procedures;
- reviewed investigation conclusions;
- portable knowledge-pack material.

It does not make OKF the representation for current machine facts,
Configuration Service records, secrets, Operational History, approvals,
privilege state, deployment authority or runtime/session state.

Igor remains free to index these artifacts in SQLite, a text index or a later
semantic index. Those indexes are derived and replaceable; the artifact's typed
meaning, provenance and authority boundary are the durable contract.

## Retrieval direction

Start with deterministic metadata/object/domain retrieval and the existing
Context Engine. The normal path should prefer a small relevant projection over
large prompt dumps. Semantic or vector search is a later optimization when
measured corpus size or recall problems justify it; it must not become a second
source of truth.

## LLM role

The LLM is a knowledge compiler/reasoning engine, not Igor's memory or
authority.

## Evidence-backed local learning

Step 16B implements the first bounded local-learning contract in
[LOCAL_LEARNING.md](LOCAL_LEARNING.md). Core derives recurring operational
outcomes and attributed findings from resolved Investigations using canonical
History/Investigation references. Derivation is deterministic and on demand;
the operator explicitly reviews a revision-bound snapshot before it becomes
accepted local reference knowledge. Baselines are explicit evidence summaries,
not causal explanations.

The service owns learning semantics and review state; it does not become a
generic memory store or take ownership of source records. Reviewed artifacts
preserve content, applicability, provenance and exact evidence references when
source records disappear. Owner/module inactivity may withhold the artifact
from active Context while retaining inspection. Accepted artifacts can inform
context but cannot establish machine facts, desired configuration,
responsibility, approval, privilege, automation or executable behavior.

This initial implementation has no LLM dependency and does not infer causes or
verified procedures absent typed supporting Investigation evidence. Legacy
pattern files and session notes remain compatibility references without
automatic import or dual-write. Portable OKF-compatible import/export remains
separate work.

Step 16D now adds one deterministic cross-incident pattern layer above reviewed
typed incident learning. It groups only exact reviewed symptom/cause pairs with
matching scope/compatibility across at least three distinct Investigations.
This produces reviewable reference knowledge, not a knowledge-graph edge,
diagnostic rule or procedure. Semantic equivalence and reference-procedure
synthesis remain later explicit contracts.

The intended architecture is:

```text
LLM
+
Igor knowledge store
+
System Model
+
current machine facts
```

Igor retains provenance, ownership, validation and authority boundaries.

Training a dedicated Igor model is not a requirement for Igor 2. Retrieval,
structured knowledge and external model reasoning are the initial direction.

## Realistic scope

Igor can realistically:

- extract concepts from operational material;
- identify dependencies;
- detect conflicts;
- create candidate operational models;
- suggest checks and capabilities;
- generate configuration templates;
- create draft modules.

Igor should not initially claim to:

- automatically determine the perfect architecture;
- trust arbitrary scripts;
- resolve all documentation conflicts;
- create production deployments without review.

## Relationship to modules

Modules are not the first layer of knowledge. They are operational expressions
of knowledge.

A knowledge pack may exist without executable actions.

A module is a reviewed combination of:

- knowledge;
- configuration schema;
- templates;
- checks;
- observers;
- capabilities;
- verification;
- lifecycle management.

## Future direction

The future authoring flow is:

```text
external knowledge
        |
        v
Igor Knowledge Compiler
        |
        v
reviewed operational model
        |
        v
Igor module / knowledge pack
```

This foundation enables future improvements without tying Igor to one skill
format, one LLM provider or one external ecosystem.
