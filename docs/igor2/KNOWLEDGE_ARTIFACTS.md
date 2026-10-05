# Portable Knowledge Artifacts

Status: **Step 16F bounded implementation**

Decision: [D068](DECISIONS.md)

## Purpose

Portable Knowledge Artifacts let Igor exchange reviewed reference knowledge
without turning an interchange format into a runtime authority.

The initial source is accepted Local Learning, including:

- recurring operational outcomes;
- reviewed Investigation findings;
- typed Investigation findings;
- cross-incident symptom/cause patterns;
- evidence-backed reference procedures.

## Igor contract

A portable Igor artifact has deterministic `ka-...` identity and remains:

```text
authority: reference_only
origin: learned_local | imported
```

Its portable semantics include:

- knowledge type;
- human-readable statement and uncertainty;
- structured pattern/procedure content when present;
- applicability owners;
- capability/provider compatibility;
- source-object provenance;
- derivation/evidence digests;
- explicit review provenance.

Source object IDs and evidence references are provenance from the originating
installation. Import never treats them as bindings to the receiving machine.

## OKF v0.2 profile

Step 16F targets Open Knowledge Format v0.2. The compatibility target verified
for this slice is the canonical `GoogleCloudPlatform/open-knowledge-format`
specification; the older copy under `knowledge-catalog/okf` is a frozen
snapshot and is not the implementation reference.


Each export is one bundle:

```text
bundle/
  index.md
  ka-<digest>.md
```

The root index declares `okf_version: "0.2"`.

The concept uses ordinary OKF fields:

- `type`;
- `title`;
- `description`;
- `resource`;
- `tags`;
- `status`;
- `generated`;
- `verified`;
- `sources`.

The producer-defined `igor_artifact` field retains Igor's typed structure.
OKF permits producer-defined frontmatter, so this remains an OKF concept while
allowing another Igor installation to reconstruct the richer reference artifact.

Core emits JSON-compatible values on one YAML line. JSON flow values are valid
YAML and keep the parser deterministic without a new YAML dependency.

## Export

```bash
bash igor.sh --knowledge status
bash igor.sh --knowledge export '{"learning_id":"learn-...","directory":"/path/to/bundle"}'
```

Only accepted Local Learning may be exported. Rejected/superseded/candidate
knowledge is not portable as an accepted Igor artifact.

Export creates a new directory and refuses overwrite. Files are private by
default. Export never mutates Local Learning or source authorities.

## Import

```bash
bash igor.sh --knowledge import '{"directory":"/path/to/bundle"}'
```

Import returns a normalized candidate with:

```text
authority: reference_only
trust: untrusted_import
persistence: none
```

This remains true even when OKF `verified` records a human reviewer. OKF trust
signals are provenance, not Igor access control or acceptance.

Generic OKF concepts without `igor_artifact` can be normalized as external
reference candidates. An Igor extension, when present, must validate exactly.

Import is read-only with respect to Igor-owned state. It does not:

- persist the artifact;
- add it to Local Learning;
- enter it into Context;
- establish a System Model fact;
- set desired state or responsibility;
- activate a module;
- grant approval or privilege;
- create an executable capability/playbook;
- execute or remediate anything.

## Initial parser/profile limits

The initial consumer deliberately supports one concept per bundle and bounded
one-line flow/scalar frontmatter. It rejects symlinked concepts, oversized
documents, duplicate/unsafe fields, secret-bearing content, unsupported OKF
versions and advanced/multiline YAML.

This is a bounded portability profile, not a claim to implement every YAML
construct or recursively ingest every possible OKF corpus.

Deferred work includes:

- multi-concept knowledge packs;
- recursive OKF links/graphs;
- persistent imported-knowledge review and acceptance;
- imported knowledge Context retrieval;
- deterministic corpus indexing improvements;
- semantic/vector indexes;
- executable promotion.
