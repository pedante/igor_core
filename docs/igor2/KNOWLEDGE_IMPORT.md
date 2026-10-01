# Knowledge import and module synthesis

Status: **accepted architectural direction; implementation deferred**.

Igor should be able to grow from heterogeneous operational material without
turning every external document, script or agent skill into executable authority.

The previous import concept is expanded into the broader **Igor Knowledge
Architecture**. Import is one entry point into a knowledge lifecycle, not the
final model.

The goal is to transform useful external knowledge into provenance-bearing
operational knowledge artifacts that Igor can reason over and, after review,
compile into modules, checks, capabilities and playbooks.

See [KNOWLEDGE_ARCHITECTURE.md](KNOWLEDGE_ARCHITECTURE.md).

## Core principle

External material enters Igor as evidence/reference material first.

It does not become an active observer, capability, check, automation or
privileged handler merely because a source contained a script, skill or
imperative instruction.

The pipeline is:

```text
source material
      ↓
capture + provenance
      ↓
classification + extraction
      ↓
Operational Knowledge Artifact
      ↓
validation + conflict handling
      ↓
knowledge pack / candidate module
      ↓
explicit promotion of executable parts
      ↓
normal Igor capability and Module API
```

## Sources

Supported future sources include:

- installation documentation;
- guides and runbooks;
- scripts;
- configuration examples;
- native Igor modules;
- Agent Skills/AOH material;
- ServerMind and Steward patterns;
- other open-source operational knowledge;
- local Igor investigations and learned procedures.

## Knowledge compiler direction

Igor should not build a collection of rigid importers for every possible
format. The preferred direction is a Knowledge Compiler:

- classify source material;
- extract operational concepts;
- identify relationships and requirements;
- preserve alternatives and uncertainty;
- create structured knowledge artifacts;
- produce candidate Igor objects.

The LLM assists semantic extraction. Igor remains responsible for memory,
provenance, validation, ownership, policy and execution authority.

## Module relationship

A module is not the raw destination of imported material.

The direction is:

```text
knowledge source
        ↓
Operational Knowledge Artifact
        ↓
reviewed knowledge pack
        ↓
module / capability / check / playbook
```

A knowledge pack may exist without executable actions.

## Trust boundary

Imported knowledge can suggest:

- capabilities;
- observers;
- checks;
- configuration schemas;
- playbooks;
- templates.

Promotion into executable Igor functionality still requires the normal
capability, privilege, approval, verification and ownership contracts.

The original import-specific considerations remain valid:

- provenance;
- licensing awareness;
- portable package versus machine binding;
- source compatibility;
- safe installation ownership;
- AOH/Agent Skills compatibility as an input, not as Igor authority.

## Scope

Igor 2 should establish the foundation:

- knowledge artifacts;
- provenance;
- structured operational understanding;
- retrieval/indexing strategy;
- module authoring workflow.

A public registry, signing infrastructure, automatic external code execution,
full autonomous module creation and live external ecosystem interoperability
remain future work.
