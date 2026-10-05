# Igor 2 architecture package

This directory is the repository-resident design authority for the Igor 2 migration.

It exists so maintainers and coding agents can work from durable repository context instead of reconstructing the architecture from chat history.

## Read order

For most Igor 2 work:

1. `STATUS.md` — current migration state and next focus.
2. `ARCHITECTURE.md` — stable target principles and boundaries.
3. Read only the task-relevant document:
   - `ROADMAP.md` — stable step names, development waves and current implementation status.
   - `MODULE_API.md` — target Module API v2.
   - `HOST_INTELLIGENCE.md` — accepted Wave D design and implementation gate for Steps 7–10.
   - `AGENT_ARCHITECTURE.md` — accepted Wave E contract for the bounded Steps 11–12 implementation.
   - `EVENT_BUS.md` — accepted and implemented Step 13 Domain Event Bus contract.
   - `AUTOMATION_ENGINE.md` — accepted and implemented Step 14 Automation Engine contract.
   - `PERSISTENT_MEMORY.md` — accepted Step 15A persistent identity, System Model persistence, durable-reference and memory-ownership contract; [Operational History](../operational_history.md) documents the Step 15B service.
   - `INVESTIGATIONS.md` — accepted Step 15C durable local investigation lifecycle, typed references, hypotheses, scoped findings, private persistence and read-only inspection.
   - `CONTEXT_ROUTING.md` — accepted Step 15D bounded context relevance, optional judgment ranking, provider-neutral roles, explicit bindings and operational provenance.
   - `BASELINES.md` — implemented Step 16A bounded explainable projections over retained Operational History.
   - `LOCAL_LEARNING.md` — approved Step 16B candidate, reviewed snapshot, lifecycle, persistence, Context and authority contract.
   - `INTERACTION_SURFACE.md` — implemented Step 15UI interaction foundation: scrolling, selection/focus, toggleable control panel, schema-driven inputs/properties and backend-reported AI role visibility.
   - `OPERATOR_SURFACE.md` — initial contract-driven operator projection and `:` namespace explorer over existing module/capability/configuration registries; no parallel execution or menu authority.
   - `SYSTEM_ADMIN_EXPERIMENT.md` — experimental System 2.3.0 administration surface: distro-neutral host/package/service/log semantics over Debian/Arch platform mechanics and reviewed privileged adapters.
   - `CONFIGURATION.md` — accepted D059 Core-owned configuration foundation: versioned schemas, scoped desired values, private persistence, references-only secrets, precedence, inspection and the bounded `ai.verbose` cutover; richer surfaces and deployments remain deferred.
   - `BROWNFIELD_ADOPTION.md` — accepted D061 brownfield discovery/adoption refinement: existing machine resources remain independent of modules, adoption is explicit, and configuration values retain concrete storage/source locators.
   - `RESOURCE_RECOGNITION.md` — explicit future seam between low-level observation and adoption: domain recognition, ephemeral evidence-bound candidates, exact user hints and no implicit authority.
   - `ATTACHMENT.md` — Step 19 Boundary 2 deterministic brownfield discovery, metadata attachment, scoped release and service prerequisites.
   - `DEPLOYMENTS.md` — accepted D063 owner-scoped Step 19: application-neutral deployment identity, typed relationships, explicit scoped responsibility, private transactional persistence and three separately gated implementation boundaries.
   - `PROVISIONING.md` — future Igor 2 greenfield installation/provisioning completion gate over capabilities, Deployment Service, Configuration and History; no workflow-engine authority.
   - `OPERATOR_INTERFACES.md` — Step 20A/B/C direction for a first-class CLI, completed backend-driven TUI and later default-launch cutover over one shared authority.
   - `COMMUNICATIONS.md` — design proposal for unified notifications/reports/email transport, authenticated remote conversation and bounded remote administration.
   - `RESUMABLE_WORK.md` — design proposal for durable `WAITING_USER` / `WAITING_EXTERNAL` plan states and safe continuation across restarts.
   - `MODEL_ROLES.md` — design exploration for optional role-based helper models such as a semantic scout; records open questions, not an accepted implementation contract.
   - `JUDGMENT_CONTRACT.md` — accepted bounded provider-neutral, reference-only model judgment record/interface; no role routing, transport or persistence.
   - `AI_SPECIALISTS.md` — design exploration for cheap/local AI specialist roles, bounded agents, module use, risks and open questions.
   - `MIGRATION.md` — compatibility, persistent migration and cleanup policy.
   - `EXECUTION.md` — evidence gates, vertical slices, inspection and scope discipline.
   - `PERFORMANCE_INVESTIGATION.md` — Boundary A–P performance retrospective, measured gains, architectural lessons, stopping rule and remaining low-priority opportunities.
   - `PERFORMANCE_AUDIT_PROMPT.md` — reusable Codex prompt for systematically finding the same classes of performance antipattern without weakening authority.
   - `INFLUENCES.md` — ServerMind/Steward/AOH lessons intentionally adopted by Igor.
   - `KNOWLEDGE_ARCHITECTURE.md` — accepted long-term knowledge model, portable Knowledge Artifact boundary, deterministic retrieval direction and optional OKF-compatible interchange without making external formats authority.
   - `KNOWLEDGE_IMPORT.md` — accepted direction for normalizing docs, scripts, Agent Skills/AOH, ServerMind, Steward and local learning into Igor-managed knowledge/module candidates without granting execution authority.
   - `DECISIONS.md` — accepted and unresolved architectural decisions.
   - `LEGACY.md` — significant current paths that must be kept, adapted or retired.
   - `PERFORMANCE_INVESTIGATION.md` — completed Boundary A–P performance investigation: measurements, architectural fixes, stopping point and remaining opportunities.
   - `PERFORMANCE_AUDIT_PROMPT.md` — reusable Codex prompt for systematically finding the same classes of performance antipattern without weakening Igor authority boundaries.

## Current implementation versus target

The root README, current subsystem docs, code and tests describe how Igor works today.

The files here describe where Igor is going and how to migrate safely.

Important current foundations already exist. Igor 2 must **not** recreate them under parallel names merely because the roadmap originally described them as future work. The current TUI/runtime, safety/privilege flow, module activation boundary, platform helpers, AI trust boundary and capability catalog are migration inputs.

`docs/module_creation.md` remains the current Module API v1 reference until v2 is implemented and adopted. `docs/module_lifecycle.md` documents the current module activation model.

## Design goal

Igor is a local AI-assisted operating layer for Linux. It should maintain typed machine memory, discover the host deterministically, distinguish observed state from desired state and responsibilities, gain domain knowledge and abilities through modules, preserve durable investigations, plan installation/configuration work through structured capabilities, execute safely, verify changes deterministically, retain useful operational history and local learning, and let users operate the machine without needing to know the underlying commands.

The Codex-like TUI is the primary interactive-interface direction, while the
CLI is a first-class headless/operator interface. Natural-language one-shot,
structured CLI commands, TUI interaction, automation and later external
interfaces must use the same backend state/capability engine rather than
implement parallel operating logic.

## Documentation discipline

These files are architectural memory, not a second implementation.

- Stable principles belong in `ARCHITECTURE.md`.
- Execution/completion rules belong in `EXECUTION.md`.
- Adopted external design lessons belong in `INFLUENCES.md`; they do not override accepted Igor decisions.
- Accepted/open decisions belong in `DECISIONS.md`.
- Temporary migration state belongs in `STATUS.md`.
- Significant compatibility/debt belongs in `LEGACY.md`.
- Current implementation details belong next to current code/tests/docs.
- Git history is the archive for superseded planning/handoff documents; stale copies should not remain in active docs merely for history.
