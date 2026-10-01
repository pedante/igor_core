# Adopted design influences: ServerMind, Steward and AOH

This document records the design lessons Igor intentionally adopted after
studying ServerMind and Steward so those lessons do not disappear into chat
history.

It is a design-influence map, not an API-compatibility commitment, dependency,
or claim that Igor should reproduce either project.

## ServerMind-derived lessons adopted by Igor

### Deterministic discovery before AI reasoning

Igor should not ask the model to rediscover basic machine truth on every
request. Host and domain observers collect typed facts first; AI reasons over
that result.

Roadmap coverage:

- Step 8 System Model;
- Step 9 Observation Framework;
- Step 10 Unified Health;
- Step 12 Knowledge & Context Engine.

### Reusable machine inventory and provenance

Facts should be reusable by diagnosis, AI, healing, automation and inspection.
They carry source/freshness/ownership instead of becoming unstructured prompt
text.

Roadmap coverage:

- System Model provenance/freshness;
- observer ownership;
- continuous inspection in EXECUTION.md;
- operational history in Step 15.

### Problem discovery is a system function

Igor should have deterministic mechanisms to discover unhealthy or surprising
state before the AI explains or investigates it. The model may choose the next
question or capability, but it is not the only sensor.

Roadmap coverage:

- observers and checks;
- Domain Event Bus;
- Unified Health;
- durable investigations.

### Configuration and installation are inspectable state

Installation/configuration work should leave Igor with an updated,
inspectable understanding of what exists and why, rather than only a command
transcript.

Roadmap coverage:

- Ownership Foundation;
- structured plans;
- System Model;
- relationships/deployments;
- verification/history.

## Steward-derived lessons adopted by Igor

### Durable machine understanding, not conversation memory

Operational truth survives model/provider/session changes. Chat is narrative;
Igor-owned state is authoritative.

Machine memory includes:

- observed facts;
- configured/user-declared facts;
- desired state;
- responsibilities;
- installation/deployment records;
- findings and verification outcomes;
- operational history.

Roadmap coverage:

- Step 8 System Model;
- Step 15 Operational History;
- the Ownership Foundation.

### Desired state and responsibilities

Igor should be able to distinguish:

- what is observed now;
- what the user/configuration says should be true;
- what Igor has been asked to maintain or watch.

This makes drift, reconciliation and proactive problem discovery possible
without pretending every observation is an error.

Roadmap coverage:

- Step 8 System Model;
- Step 13 Domain Event Bus;
- Step 14 Automation Engine;
- Step 19 Self-Healing v2.

### Structured plans for installation and configuration

Complex work should be decomposed into capability-backed steps with
preconditions, approvals, recovery semantics and deterministic verification.

Roadmap coverage:

- Step 11 Capability System v2;
- structured-plan rules in EXECUTION.md;
- Step 17 Relationships & Deployments.

### Durable investigations

A problem investigation should be able to outlive one chat turn or one model
call. Igor should preserve the important operational structure:

- problem/question;
- evidence;
- hypotheses;
- decisions;
- actions;
- findings;
- verification;
- resolution/status.

Roadmap coverage:

- Step 15 Operational History;
- Step 12 context composition;
- later self-healing and automation consumers.

### Reusable local learning

Igor should retain evidence-backed local operating experience such as useful
runbooks, patterns and symptom/cause/resolution relationships without editing
the installed module package or treating AI prose as authority.

Roadmap coverage:

- Knowledge & Context Engine;
- Operational History/Baselines;
- post-2.0 capability-promotion work only after explicit trust review.

### AI as a reasoning layer over a deterministic system

The model is valuable for interpretation, hypothesis generation, explanation
and plan proposal. It does not own system truth, authorization, privilege,
execution success or secret access.

Roadmap coverage:

- ARCHITECTURE.md invariants;
- accepted safety/trust decisions;
- Capability System;
- deterministic verification;
- secret discipline in EXECUTION.md.

## AOH / Agent Skills-derived lessons adopted by Igor

### Portable operational knowledge should not be tied to one agent runtime

AOH's pack model and Agent Skills-compatible `SKILL.md` layout demonstrate a
useful separation between reusable operational knowledge/processes and the
runtime that materializes them.

Igor should be able to ingest skill-style knowledge without making the source
runtime or source pack format authoritative.

Roadmap coverage:

- Step 12 Knowledge & Context Engine;
- Step 18 Composable Modules;
- Step 22 Module Developer Tooling;
- [KNOWLEDGE_IMPORT.md](KNOWLEDGE_IMPORT.md).

### Portable package and machine binding are different authorities

AOH separates reusable Pack content from site-specific Binding data. Igor
adopts the same principle without adopting AOH as its native Module API:
package/module code and knowledge stay portable; mutable machine-specific paths,
secrets, instance settings and relationships remain Igor-owned configuration /
System Model state.

Roadmap coverage:

- Ownership Foundation;
- Configuration design;
- Step 17 Relationships & Deployments;
- Step 18 Composable Modules.

### Capability requirements are better than implementation coupling

AOH RuntimeRequirements name capabilities such as `shell.read` or `k8s.read`.
This reinforces Igor's selected capability-dependency direction: imported
knowledge/processes should state what they need, while Igor resolves the active
provider.

Roadmap coverage:

- Module API v2;
- Capability System v2;
- compatibility evaluation.

### Pack provenance and install ownership matter

AOH's commit-pinned site lock, install manifest, owned-file hashes, convergent
updates and crash-safe staging/journal are useful implementation references for
a future Igor package installer.

Igor should evaluate those patterns rather than treating package installation as
an untracked recursive copy.

Roadmap coverage:

- Ownership Foundation;
- Step 22 developer/import tooling;
- later package distribution work.

### Local knowledge can be promoted without self-modifying Core

AOH's skill-promotion flow is a useful model for Igor learning: local
evidence-backed knowledge can become a reviewable, versioned candidate and later
be promoted to shared knowledge/module content.

Promotion does not mean automatic execution. D053 and the normal capability
review/authority path still apply.

Roadmap coverage:

- Step 16 Baselines/local learning;
- Step 22 authoring tooling;
- later package ecosystem work.

### Runtime guardrails must be described honestly

AOH distinguishes a hard Kubernetes RBAC boundary from best-effort Claude/Codex
runtime guardrails and documents enforcement gaps.

Igor adopts the principle, not the runtime-specific mechanism: imported/source
guardrails never replace Igor's approval, privilege, capability and verification
boundaries.

Roadmap coverage:

- Steps 3–4;
- Capability System;
- [KNOWLEDGE_IMPORT.md](KNOWLEDGE_IMPORT.md).

## Igor-specific adaptations

Igor does not copy either project wholesale. The adopted ideas are constrained
by Igor's own requirements:

- local Linux-first operation;
- detachable modules;
- one authoritative loader;
- deterministic READ/CHANGE/DESTROY approval;
- OS privilege separated from AI autonomy;
- language-neutral Module API v2 with Bash first;
- reference data never authorizes;
- capabilities are the shared operational API;
- existing green behavior is migrated incrementally rather than replaced.

## Coverage check

The following concepts are therefore explicit Igor 2 goals:

| Concept | Igor 2 home |
|---|---|
| deterministic discovery | System Model + Observation Framework |
| machine memory | System Model + Operational History |
| desired state | System Model |
| responsibilities | System Model + Automation/Self-Healing |
| problem discovery | Observers + Checks + Events |
| durable investigations | Operational History / investigation records |
| configuration ownership | Ownership Foundation |
| secret ownership/audit | Ownership Foundation + secret service |
| adding knowledge | Module API + Knowledge & Context Engine + import/normalization |
| adding capacities/abilities | Capability System |
| installing/configuring a server | structured plans + capabilities + deployments |
| verification | capability/plan verification |
| learning/runbooks/patterns | knowledge/history/baselines with provenance |
| AI reasoning | Agent layer over deterministic state and policy |
| provenance/freshness | System Model + inspection surfaces |
| interoperability | shared capability API + import adapters + future live external interfaces |

This map should be updated when one of these concepts moves from architecture
to an authoritative implementation.
