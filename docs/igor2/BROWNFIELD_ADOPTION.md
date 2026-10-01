# Brownfield Discovery, Adoption, and Configuration Location

Status: **accepted architecture refinement (D061)**. Runtime implementation is
pending the Step 17/18 ownership, binding and composition work.

## Problem

Igor must be able to understand and operate a machine it did not build.

An existing server may already contain services, containers, compose projects,
mounts, application configuration, databases, reverse proxies and manually
maintained files. Those resources must not disappear from Igor's model merely
because Igor did not install them or because no application module owns their
mutable state.

This design extends the existing System Model, Configuration Service, module
binding and responsibility boundaries. It does not create a second inventory or
configuration system.

## Core rule

**The machine belongs to the machine model, not to modules.**

A module/package may teach Igor how to recognize, interpret, validate and
operate a domain. It does not own the existence of machine resources or store
machine-specific mutable facts inside its package.

For example, an existing Nextcloud deployment may be represented first as
Docker containers, volumes, networks, mounts and processes. A Nextcloud module
may later interpret those resources as one Nextcloud application and contribute
domain-specific checks/capabilities. Disabling that module removes its active
behavior and module-owned interpretation. It does not erase independently
observed Docker/host resources supplied by other still-active sources.

Machine-specific facts, bindings, desired values, responsibility and history
remain in their owning Igor services.

## Brownfield state separation

Igor keeps the following concepts separate:

| Concept | Meaning | Owner |
|---|---|---|
| Resource/object | A thing known to exist or have existed on the machine | System Model identity/source |
| Observed fact | What a deterministic source currently reports | System Model |
| Domain interpretation | What those resources mean in a technology/domain | Active module knowledge/observers, reference unless committed as valid facts |
| Configuration source | Where a setting/value was read from or is meant to be written | Configuration provenance/binding |
| Desired value | What the operator wants | Configuration Service |
| Binding/deployment | Which machine objects/settings form a concrete instance/deployment | Igor-owned relationship/deployment authority |
| Responsibility | Whether Igor is asked to watch or maintain an object/outcome | Responsibility authority |
| Operation outcome | What Igor attempted and verified | Operational History |

Observed existence never implies desired state or responsibility.

## Brownfield lifecycle

The conceptual lifecycle is:

```text
external/unknown origin
        |
        v
     discovered
        |
        v
   interpreted
        |
        v
explicitly adopted
        |
        v
 watched / maintained
```

The first three stages are non-authoritative with respect to management. Igor
may inspect and explain an existing deployment without taking ownership of it.

Adoption is an explicit authoritative transition. It may create or update
Igor-owned bindings, desired configuration and responsibility records, but does
not claim Igor originally created the resources. The original provenance is
retained.

There is no silent transition from discovery to management. Enabling a module,
recognizing a service, finding a configuration file or successfully reading a
value does not create responsibility.

## Discovery and enrichment

Deterministic discovery establishes basic reality. Examples include host,
filesystem, storage, network, services, packages, processes and container
runtime objects where an eligible provider exists.

Higher-level modules enrich that reality rather than replacing it. A module may:

- recognize a set of existing objects as one domain instance;
- contribute typed domain observations;
- identify relevant configuration locations;
- add health/check semantics;
- expose canonical capabilities;
- explain known failure modes and safe operating guidance.

The resulting machine state remains queryable through Igor-owned records, not
files under `modules/<name>/`.

If a domain module is unavailable, Igor may retain object identity, History and
facts supplied by independent sources. Facts whose only valid source was that
module follow the ordinary source-withdrawal/staleness rules; Igor does not
pretend they remain actively known.

## Configuration location and provenance

Every configuration value must be traceable to where its authoritative or
observed representation comes from.

A setting's durable identity remains its scoped `setting_id`; **a filename is
provenance/binding, not identity**. This preserves D054 and allows storage
backends or application layouts to migrate without changing the setting's
meaning.

Configuration inspection therefore carries a typed `storage_locator` (or
equivalent record) for every value/source:

- **file-backed** — semantic path plus a stable selector within the file;
- **environment-backed** — declared variable plus the file/service/process that
  supplies it when known;
- **secret-backed** — secret reference only; never copy secret material;
- **database-backed** — database/object/key identity without exposing
  credentials;
- **runtime/command-line** — explicit nonpersistent runtime source;
- **Configuration Service** — Igor-owned desired value, with private backend
  location available only as diagnostic storage metadata, never durable
  identity.

For a file-backed value the locator is mandatory and identifies the concrete
file. Prefer a stable semantic selector such as section/key, JSON pointer,
Compose service/environment key or application setting key. Do not use a line
number as the durable selector because ordinary edits move lines.

Illustrative shape:

```json
{
  "setting_id": "nextcloud.trusted_domains",
  "source": "external_application",
  "storage_locator": {
    "kind": "file",
    "path": {
      "root": "deployment",
      "relative": "config/config.php"
    },
    "selector": {
      "format": "php_config",
      "key": "trusted_domains"
    }
  }
}
```

If a value is not file-backed, Igor must say what actually stores/supplies it
instead of inventing a fake file path. The user-visible rule is therefore:
**every file-backed variable points to its file; every variable points to its
real storage/source authority.**

Paths themselves may be sensitive. Projection follows the existing sensitivity
and redaction rules. Secret values never become provenance.

## Existing application configuration

Before adoption, application-native configuration remains external authority.

A read-only observer/parser may record that a value was found in a concrete
file/source and expose that value as observed/configured state with freshness
and provenance. This does not transfer write ownership.

Adoption of a setting follows an explicit flow:

```text
discover source
  -> parse/read deterministically
  -> record observed/configured value + storage locator
  -> propose import/adoption
  -> validate desired value
  -> commit Igor desired state with imported-from provenance
  -> apply through a canonical capability
  -> read back from the bound source independently
  -> record verification in Operational History
```

The import baseline keeps the original locator and, where useful, a safe digest
or revision token so later drift can be explained. A write target is explicit;
Igor does not search for "some matching file" at application time.

Detach/revocation stops Igor management authority without deleting externally
created resources. Retained History, original provenance and independently
observed machine objects survive according to their owning retention policies.

## Example: existing Nextcloud Docker deployment

On a machine Igor did not provision, a container/Docker source may establish:

```text
compose project: nextcloud
container: nextcloud-app
container: nextcloud-db
volume: nextcloud_data
mount: /srv/nextcloud/...
network: nextcloud_default
```

Those are machine resources.

With Nextcloud domain knowledge active, Igor may additionally interpret them as:

```text
application: Nextcloud
deployment: Docker Compose
application container: nextcloud-app
database: nextcloud-db
configuration: .../config/config.php
management: external / not adopted
```

The Nextcloud package does not become the storage location for those facts.
Later, the operator may explicitly ask Igor to adopt selected configuration or
maintain the deployment. That transition records new authority without erasing
the external origin.

## Required inspection

A user must be able to answer:

- What did Igor discover?
- Which source observed it and when?
- Was the resource created by Igor, externally, or is origin unknown?
- Which module/provider currently interprets it?
- Is Igor merely observing it, or has it been asked to maintain it?
- For each configuration value, where was it read from?
- For each managed setting, where will Igor write/apply it?
- Which desired value differs from the currently observed value?
- What happens to the record if the interpreting module is disabled?

Inspection reports unknowns explicitly.

## Roadmap consequences

This refines, but does not prematurely implement, Q007 relationship/deployment
authority.

Step 17 Relationships & Deployments must support discovered external resources,
source claims, adoption and explicit responsibility transfer.

Step 18 composition prerequisites must carry configuration storage locators and
must prove that the first reversible Nextcloud workflow can bind to an existing
configuration source, not only one Igor created.

The eventual proof should include an existing-style fixture that Igor did not
provision. At minimum it must demonstrate:

1. generic resources are discovered and stored outside module packages;
2. a domain module can enrich those resources without becoming their owner;
3. every file-backed configuration value used by the proof exposes file +
   selector provenance;
4. adoption is explicit and preserves external origin;
5. desired state, application and independent readback remain separate;
6. disabling the domain module removes its active contribution without erasing
   independent machine facts or retained History;
7. detach does not delete externally created resources by default.
