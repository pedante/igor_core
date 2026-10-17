# Igor 2 design and development

Igor is an unreleased Linux-native assisted system operator. `igor2` is its
independent baseline; `master` is the separate original program. Follow
[DEVELOPMENT_POLICY](DEVELOPMENT_POLICY.md), including the accepted complete
Igor 1 cutoff. Current source behavior and proposed changes are different claims.

## Start here

1. [STATUS](STATUS.md): current work, accepted evidence and open gates.
2. [ARCHITECTURE](ARCHITECTURE.md): accepted principles/authority boundaries.
3. [ROADMAP](ROADMAP.md): proposed five substantial milestones and exact first batch.
4. [Architectural audit](ARCHITECTURE_READINESS.md): evidence, verdict, design
   alternatives, testing/development recommendations and limits.
5. [LEGACY](LEGACY.md): finite cutoff, preservation/import and deletion proof.

For implementation, read [EXECUTION](EXECUTION.md), [MIGRATION](MIGRATION.md)
and only affected contracts. The reset architecture remains DISCOVERY until
Owner confirmation; D080's no-v1-compatibility direction is already accepted.
Documentation edits do not implement or validate a runtime migration.

## Document lifecycle and authority

- **Development obligations:** DEVELOPMENT_POLICY, repository AGENTS and
  [.codex/README](../../.codex/README.md).
- **Accepted architecture:** ARCHITECTURE → accepted DECISIONS → MIGRATION →
  EXECUTION → ROADMAP → implementation documentation. A proposed roadmap cannot
  override an accepted contract; confirmation records the changed decision first.
- **Current behavior:** source, tests and current operator/subsystem docs. A green
  fixture or old acceptance proves its named boundary, not universal readiness.
- **Proposal:** explicitly proposed/future/exploratory text is input, never runtime
  authorization. New reset recommendations stay in the audit/roadmap until accepted.
- **History:** [archived STATUS](archive/STATUS_2026-10-16.md), dated reviews and Git
  preserve evidence. Old phase statements, approvals and budgets do not resume work.

Use one top-level Status marker. Update the owning document instead of adding a
parallel specification. Current STATUS stays short and links to the task ledger.
The prior 23-step roadmap and 2026-10-01 readiness review remain available in Git.

## Read contracts only when needed

| Work | Primary contract/evidence |
|---|---|
| Module/operation/lifecycle | [MODULE_API](MODULE_API.md), [current lifecycle](../module_lifecycle.md), [AGENT_ARCHITECTURE](AGENT_ARCHITECTURE.md) |
| Settings, secrets, paths | [CONFIGURATION](CONFIGURATION.md), [ownership inventory](OWNERSHIP_FOUNDATION_PROPOSAL.md), [LEGACY](LEGACY.md) |
| Machine facts/health | [HOST_INTELLIGENCE](HOST_INTELLIGENCE.md), [PERSISTENT_MEMORY](PERSISTENT_MEMORY.md) |
| History/investigations/context/learning | [History](../operational_history.md), [INVESTIGATIONS](INVESTIGATIONS.md), [CONTEXT_ROUTING](CONTEXT_ROUTING.md), [LOCAL_LEARNING](LOCAL_LEARNING.md) |
| Application identity/adoption | [DEPLOYMENTS](DEPLOYMENTS.md), [ATTACHMENT](ATTACHMENT.md), [BROWNFIELD_ADOPTION](BROWNFIELD_ADOPTION.md) |
| CLI/curses/collections | [OPERATOR_INTERFACES](OPERATOR_INTERFACES.md), [COLLECTION_OPERATOR_RFC](COLLECTION_OPERATOR_RFC.md), [interaction](../interaction_surface.md) |
| Events/scheduling | [EVENT_BUS](EVENT_BUS.md), [AUTOMATION_ENGINE](AUTOMATION_ENGINE.md) |
| Validation/performance | [VALIDATION](VALIDATION.md), [measured validation costs](VALIDATION_PERFORMANCE.md), [runtime retrospective](PERFORMANCE_INVESTIGATION.md) |
| Architecture rationale | [DECISIONS](DECISIONS.md), [INFLUENCES](INFLUENCES.md) |

`docs/module_creation.md` documents the still-live legacy interface and is marked
accordingly. New extension design uses v2; M1 replaces the legacy author guide.
Existing contracts remain useful while their actual consumers exist. Their old
wave labels do not require preserving v1 after D080.

## Optional research, not entry requirements

AI_SPECIALISTS, MODEL_ROLES, COMMUNICATIONS, PROVISIONING, RESUMABLE_WORK,
KNOWLEDGE_IMPORT and RESOURCE_RECOGNITION contain future or bounded directions.
Read them for the named task, not before every edit. Accepted parts remain tied
to their decisions; unimplemented ideas are not a backlog commitment. Generalized
imports, remote operation, marketplaces and agent networks are Igor 2.x candidates.

After reset confirmation/implementation, consolidate overlapping target prose into
ARCHITECTURE and the live contracts. Keep the useful reasons in DECISIONS and Git;
do not force developers to reconstruct the project's full evolution.
