# Resource Discovery and Domain Recognition

Status: **Igor 2 roadmap architecture direction; runtime contract not yet implemented**.

This document makes explicit the seam between low-level observation and
Deployment Service adoption. It does not create a second System Model,
inventory database, workflow engine or deployment authority.

## Product goal

Igor should be able to understand a machine it did not build.

A user may ask Igor to find a technology, point Igor at a specific resource, or
inspect what is already known. Igor should deterministically establish what
exists, let domain providers interpret that evidence, present candidates and
ambiguity, and only create bindings/responsibility through the existing
explicit adoption path.

The intended progression is:

```text
machine reality
  -> deterministic observations
  -> domain recognition
  -> ephemeral candidate
  -> deterministic inspection
  -> frozen proposal
  -> explicit adoption
```

Recognition never implies adoption, desired state, responsibility or execution
authority.

## Separate concepts

| Concept | Question answered | Authority |
|---|---|---|
| Observation | What resource/fact exists right now? | System Model / owning observer |
| Recognition | What domain object may these observations represent? | Reviewed active domain provider |
| Candidate | What interpretation is worth inspecting/selecting? | Ephemeral reference data |
| User hint | Which exact resource/domain does the operator mean? | Selector only, not proof |
| Inspection | Does the selected target deterministically satisfy the domain contract? | Read-only reviewed provider |
| Adoption | Which concrete objects/settings are deliberately bound and what duty is accepted? | Deployment Service |
| Operation | What may Igor change and how is it verified? | Capability runtime + policy/approval/privilege |

A recognizer may enrich evidence; it cannot manufacture low-level observations
or create a deployment.

## Discovery initiation modes

Igor 2 does not require one universal machine-wide scanner before discovery is
useful.

### Targeted / user-hinted discovery

This is the preferred first useful mode.

Examples:

```text
"This container is my Nextcloud."
"Look for the Samba share named media."
"My tunnel is managed by cloudflared.service."
```

The hint supplies a locator or narrows a domain. The relevant provider then
inspects the exact target. A user statement is not accepted as machine truth.

### Domain discovery

A user may ask:

```text
find Nextcloud
show Samba shares
find reverse tunnels
```

The domain provider enumerates only evidence relevant to its reviewed domain,
returns zero/one/many candidates and never silently chooses the first ambiguous
match.

### Inventory-driven recognition

As generic resource observations mature, recognizers may evaluate already-known
containers, services, mounts, configuration sources and endpoints instead of
probing the same host repeatedly.

This is incremental: Igor should add generic resource observation only when a
real observer/recognizer consumes it. It is not a mandate for an exhaustive
filesystem/process/network crawler.

### Event-driven recognition

Later, domain events may make selected recognizers eligible to re-evaluate
changed evidence. This is explicitly deferred. Step 13 events do not create
background scanning, adoption or unattended execution authority.

## Candidate contract

The first reusable candidate should be small, immutable for one recognition
result, non-secret and cheap to recompute. Illustrative fields:

```json
{
  "candidate_version": 1,
  "candidate_id": "ephemeral-local-id",
  "domain_kind": "nextcloud",
  "provider": {
    "owner": "nextcloud_docker",
    "version": "..."
  },
  "matched_objects": ["..."],
  "evidence": ["..."],
  "interpretation": {},
  "ambiguities": [],
  "missing_evidence": [],
  "observed_at": "...",
  "expires_at": "..."
}
```

A candidate contains no approval, desired value, accepted relationship,
responsibility, privilege or execution permission.

Candidates are initially ephemeral. Durable low-level facts remain in System
Model and accepted bindings/responsibility remain in Deployment Service. When a
candidate is selected for adoption, the proposal freezes the exact relevant
evidence/provider/revisions and ordinary stale/ambiguity fencing applies.

## Module/provider direction

Domain recognition belongs with the package/provider that understands the
domain, not as hard-coded Core vocabulary.

The future Module API may add a reviewed recognizer contribution or extend an
existing read-only contribution contract. That exact contract is deliberately
not declared here: the implementation gate must first prove the smallest shape
needed by real domains.

Core may coordinate eligible recognizers, validate their result envelope,
deduplicate candidates and route exact user hints. Core does not decide what
looks like Nextcloud, Samba, Caddy, SSH tunnels or Cloudflare tunnels.

The existing Step 19 Nextcloud Docker attachment provider is the first narrow
recognition/discovery slice. It remains valid evidence for that domain, but
`core.deployments.discover` must not become the accidental universal discovery
API without this reusable seam being settled.

## Examples

### Nextcloud on Docker

Generic evidence can identify Docker daemon/container/image/mount/Compose facts.
The Nextcloud-aware provider interprets a matching set as a Nextcloud candidate,
then performs exact read-only inspection before an adoption proposal.

### Samba share

Host/filesystem/service observations may establish `smbd.service`, a concrete
configuration source and a path. A Samba provider interprets sections such as
`[media]` as `samba.share` candidates and records file/selector provenance.
Igor may know about the share without managing it.

### Reverse tunnel

Generic service/process/network observations may show a unit, process and
endpoints. An OpenSSH, Cloudflare or other provider interprets its own evidence
as a typed tunnel candidate. A relationship to an application is a separate
claim/binding; Core does not infer tunnel semantics from process text.

## Safety and privacy

Recognition is read-only but still bounded:

- no arbitrary recursive filesystem or network scan by default;
- no secret values in candidates/evidence;
- bounded provider timeout/cost;
- exact targets and provider identity retained;
- stale evidence cannot be presented as current;
- ambiguity is explicit;
- AI may suggest a domain/provider or explain evidence but cannot stamp a
  recognized object as authoritative;
- recognition output cannot grant capability execution or management duty.

## Relationship to the brownfield lab

A brownfield integration lab creates an application independently of Igor,
records external provenance, and leaves it running. Igor then exercises the same
recognition -> inspection -> adoption path it would use on an existing server.

The lab is a test-environment producer, not an Igor installer and not a
recognition authority.

## Implementation proof gate

Before calling the recognition model reusable, prove at minimum:

1. one exact user-hinted target;
2. zero/one/many domain-discovery results with ambiguity preserved;
3. evidence/provenance/freshness validation and stale fencing;
4. candidate output that creates no System Model desired state, deployment or
   responsibility;
5. selection followed by the existing frozen adoption proposal;
6. provider disablement removes active recognition without erasing independent
   low-level observations;
7. two materially different domains use the contract (target direction:
   Nextcloud plus a non-application resource such as Samba);
8. CLI/TUI inspection uses the same backend candidate representation.

Network-wide discovery, background scheduling, persistent candidate databases
and AI-only recognition are not required for this gate.
