# Igor Knowledge Architecture

Status: **accepted architectural direction; implementation deferred**.

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

## LLM role

The LLM is a knowledge compiler/reasoning engine, not Igor's memory or
authority.

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
