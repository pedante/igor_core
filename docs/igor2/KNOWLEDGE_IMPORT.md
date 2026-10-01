# Knowledge import and module synthesis

Status: **accepted architectural direction; import runtime not implemented**.

Igor should be able to grow from heterogeneous operational material without
turning every external document, script or agent skill into executable authority.

The goal is to normalize useful external knowledge into Igor-managed,
provenance-bearing module/knowledge artifacts that use the same Module API,
capability, approval, privilege, verification and ownership boundaries as
native Igor content.

This document defines that direction. It does **not** accept a new executable
plugin format, marketplace, registry, signing system or automatic code-trust
path.

## Problem

Useful operational knowledge already exists in many forms:

- installation documentation;
- shell/Python scripts;
- admin guides and runbooks;
- existing Igor modules;
- Agent Skills / AOH skills and packs;
- ServerMind custom-tool manifests and operating patterns;
- Steward adapters, packs, investigations and playbook patterns;
- other open-source projects;
- local Igor investigations and evidence-backed learned procedures.

Igor should not require a human to rewrite all of this from zero before it can
benefit from it.

But importing source material creates a trust problem. Prose can be wrong,
scripts can be unsafe, external capability names do not imply Igor authority,
and a license that allows reading does not necessarily allow redistribution.

Therefore **source ingestion and operational authority are separate
transitions**.

## Architectural rule

External material enters Igor as source/reference material first.

It may be normalized into Igor-managed candidate artifacts, but it does not
become an active observer, capability, check, automation or privileged handler
merely because the source contained a script, tool definition or imperative
instruction.

The pipeline is:

```text
source material
      ↓
capture + provenance
      ↓
parse / extract
      ↓
normalize into Igor concepts
      ↓
validate structure + compatibility
      ↓
candidate module / knowledge bundle
      ↓
human-visible diff / evidence / tests
      ↓
explicit promotion of executable parts
      ↓
normal Module API + capability activation
```

Igor Core remains the authority for activation, policy, approval, privilege,
execution and verification.

## Supported source classes

Import tooling should eventually accept at least these source classes without
requiring one universal parser:

### Documentation and guides

Examples: upstream installation docs, troubleshooting guides, architecture
notes, release instructions and vendor runbooks.

Potential outputs:

- static knowledge;
- vocabulary/semantic tags;
- configuration candidates;
- compatibility notes;
- process/runbook candidates;
- verification ideas;
- links/references retained as provenance.

Prose never becomes executable authority directly.

### Existing scripts

A script may contain valuable deterministic behavior, but import must not
silently make it callable.

Potential outputs:

- reference asset;
- candidate handler;
- inferred required binaries/platforms;
- candidate inputs;
- candidate safety/privilege classification for review;
- candidate verifier/check;
- tests or fixtures.

Executable promotion requires normal Igor review and capability metadata.
Imported scripts must not bypass the Module API or approval/privilege path.

### Native Igor modules

Existing Igor modules are already closest to the target representation.

Import/migration tooling may:

- validate and inventory v1/v2 contributions;
- split package code from machine-specific bindings/configuration;
- extract reusable knowledge;
- generate candidate v2 descriptors;
- preserve owner/provenance and compatibility state.

Migration must preserve the current working module until the replacement path
passes normal regression and migration gates.

### Agent Skills and AOH

Igor should intentionally understand the Agent Skills-style layout as a
knowledge/process input:

```text
SKILL.md
scripts/
references/
assets/
```

AOH adds useful packaging concepts around skills:

- versioned pack metadata;
- runtime requirements expressed as capabilities;
- role/skill composition;
- evals;
- pack/source locking;
- site-specific bindings separate from the portable pack;
- install ownership manifests;
- runtime adapters.

Igor should **not** make AOH v1alpha2 its native Module API. AOH is
agent-runtime-centric and its alpha schema can change. Instead:

- `SKILL.md` can be imported as bounded knowledge/process material;
- AOH runtime requirements can map to candidate Igor capability requirements;
- AOH evals can inspire/import behavioral tests;
- AOH pack metadata and source commit become provenance;
- AOH bindings reinforce Igor's portable-package vs machine-binding split;
- AOH scripts remain non-executable until explicitly adapted/promoted.

A future AOH importer should compile/translate into Igor's own stable module and
knowledge contracts rather than create a second execution path.

### ServerMind

ServerMind custom tools are valuable because they express constrained,
operator-defined capabilities such as frozen argv, read-only database queries,
HTTP checks and file reads.

An importer may translate such a manifest into a **candidate** Igor capability
descriptor and reference asset.

Igor still recomputes/validates:

- canonical capability identity;
- inputs;
- READ/CHANGE/DESTROY tier;
- privilege;
- platform requirements;
- preconditions;
- verifier;
- recovery semantics;
- secret-reference use.

The imported ServerMind declaration is evidence/source material, not Igor
authorization.

ServerMind's compact deterministic machine profile is an architectural
influence on observers/System Model, not a portable module format by itself.

### Steward

Steward packs/adapters/playbooks can contribute ideas and source material for:

- domain knowledge;
- detect/collect/act/verify/rollback capability decomposition;
- responsibilities/assurances;
- playbook structure;
- investigations and evidence collection;
- compatibility metadata.

A future importer may map compatible declarative material into Igor candidates,
but Steward state and authority remain external unless a separate explicit
interop adapter is implemented.

### Local Igor learning

Evidence-backed local investigations may eventually produce candidate reusable
knowledge:

```text
symptom
→ evidence
→ diagnostic sequence
→ cause
→ remediation
→ verification
```

Promotion should create a reviewable candidate skill/runbook/module contribution
outside the installed package first.

Learning remains reference material under D053 until an explicit promotion step
is accepted.

## Igor-managed normalized artifact classes

Import does not need one giant intermediate schema. It should normalize toward
existing Igor concepts:

- **knowledge** — architecture, terminology, failure modes, operating guidance;
- **semantic metadata** — concepts/tags/object associations for Context Engine;
- **observer candidate** — deterministic fact collection;
- **check candidate** — structured health/drift evaluation;
- **capability candidate** — possible operation using the canonical capability
  contract;
- **configuration candidate** — namespaced schema/default/secret-reference needs;
- **plan/playbook candidate** — ordered capability-backed process guidance;
- **relationship/deployment hint** — proposed topology, never authoritative by
  import alone;
- **eval/test** — scenario and expected behavior/verification;
- **reference/asset** — retained source material;
- **compatibility declaration** — platform, package, version and tool
  requirements.

The resulting managed bundle may become a normal Igor module/package, a
knowledge-only package, or remain a local candidate set.

## Portable package versus machine binding

Reusable material and local machine intent must remain separate.

A portable package may contain:

- knowledge;
- skills/process guidance;
- contribution descriptors;
- handlers/scripts after review;
- checks/observers;
- compatibility metadata;
- tests/evals;
- configuration schema.

A machine binding owns instance-specific values such as:

- paths;
- hostnames/domains;
- selected provider/implementation;
- data locations;
- secret references;
- instance IDs;
- deployment relationships;
- user-selected responsibilities.

Installed package code must not become the mutable home for those values.

This adopts the useful AOH Pack/Binding separation while keeping Igor's own
configuration and System Model authorities.

## Provenance and licensing

Every imported source should retain, as applicable:

- source kind;
- original project/document;
- canonical URL or local origin;
- version/tag/commit or retrieval time;
- license identifier/text reference when known;
- imported files/sections;
- transformation/importer version;
- local modifications;
- resulting Igor owner/module/candidate IDs.

Provenance supports explanation and upgrades; it does not grant trust.

When source code or substantial licensed material is copied, Igor must preserve
the source license obligations. Architecture inspiration alone is not the same
as copied code. Any direct vendoring/reuse should be recorded in the
repository's third-party provenance/notice mechanism when one is introduced.

Import tooling must not claim that a source is redistributable merely because
it is publicly readable.

## Validation and compatibility

A candidate import should fail closed on unsupported or ambiguous material.

Validation should cover, as relevant:

- contained/safe paths;
- duplicate IDs;
- unsupported source/contract versions;
- declared vs available capabilities;
- required binaries/platform families;
- scripts/references crossing package boundaries;
- secret-shaped or explicitly sensitive material;
- missing license/provenance metadata when redistribution is requested;
- executable candidates lacking complete safety/privilege/verification
  metadata.

The source's own runtime guardrail is never treated as an Igor enforcement
boundary. Igor reports the difference between:

- source intent;
- imported candidate metadata;
- Igor-enforced guarantees.

## Managed install and upgrade direction

The AOH installer demonstrates several useful lifecycle patterns that Igor
should evaluate for its future package installer:

- commit-pinned source locks;
- per-install ownership manifests;
- canonical vs materialized file hashes;
- refusal on locally modified owned files unless explicitly overridden;
- convergent removal of stale owned files;
- staging before commit;
- write-ahead recovery for interrupted installation;
- safe path handling and source-tree hygiene.

These are implementation candidates, not accepted dependencies on AOH.
Selective MIT-licensed code reuse may be appropriate if it matches Igor's
semantics and is recorded with required attribution.

## Authoring and promotion

Igor should eventually support both directions:

```text
external source → Igor candidate → managed module/knowledge
```

and:

```text
local Igor experience → candidate knowledge/skill → review → shared pack/module
```

The second direction should preserve the same trust split: a learned procedure
can be promoted as knowledge before any executable capability is accepted.

A future developer/operator flow might expose commands such as
`module import`, `knowledge import`, `candidate inspect`, `candidate diff`
and `candidate promote`, but command names and persistence schemas are deferred
until the implementation gate.

## Compatibility and interoperability

External formats should be handled by import/adapter layers.

Igor's native internal contract remains:

```text
source/import adapter
        ↓
Igor-managed normalized artifacts
        ↓
Module API / knowledge / capability registry
        ↓
Igor policy + approval + privilege
        ↓
execution + verification + history
```

This leaves room for future live interoperability with AOH, ServerMind,
Steward or other systems without making any of them a mandatory Igor runtime
dependency.

## Scope for Igor 2

Igor 2 should establish the **foundation** for this ecosystem:

- imported knowledge and executable authority remain separate;
- provenance/source identity is explicit;
- portable module/package content is separate from machine binding/configuration;
- Agent Skills-compatible knowledge can be represented without weakening Igor
  authority;
- import output targets existing Module API/System Model/capability contracts;
- module developer tooling has a defined future import/normalize/validate path.

A full public registry/marketplace, signing infrastructure, automatic external
code execution, sophisticated package solver and live ServerMind/Steward/AOH
interop remain later work unless a concrete implementation need moves one
forward.
