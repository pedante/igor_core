# Igor 2 architectural decisions

This file records decisions that coding agents should not repeatedly reopen without new evidence.

Accepted decisions are architecture constraints. Open decisions are questions to resolve at the indicated roadmap stage.

## Accepted

### D001 — The Codex-like TUI is the primary human interface

Status: accepted.

The new structured AI TUI is the direction for the main Igor experience. CLI/headless interfaces remain for automation, scripting, recovery and testing.

Long-term, `./igor.sh` should launch the primary TUI when migration permits.

### D002 — AI autonomy and OS privilege are separate

Status: accepted.

Guide/Assist/Executive determine decision/execution autonomy. They do not grant root privileges.

Privilege must be brokered for approved operations.

### D003 — Module presence is not module activation

Status: accepted.

A module existing under `modules/` is not sufficient for runtime contribution.

### D004 — Core must remain application-agnostic

Status: accepted.

Application/deployment-specific behavior belongs to modules/integration rules rather than core.

### D005 — Debian and Arch Linux are initial platform targets

Status: accepted.

Igor should provide normalized platform operations with tests for Debian and Arch. Derivative support must not be assumed without validation.

### D006 — Knowledge and observed state are different

Status: accepted.

Module/core knowledge may explain how a domain works. The System Model represents what is actually known about this machine.

### D007 — Capabilities are the shared operational API

Status: accepted.

TUI, CLI, healing, automations and external control should converge on shared capabilities rather than duplicate domain operations.

### D008 — Modules may declare automations; Igor owns scheduling

Status: accepted.

Scheduling, policy, retries, privilege, execution and history are Igor runtime responsibilities.

### D009 — Modules should compose through instances/relationships

Status: accepted direction.

Prefer reusable coherent domain modules plus deployment relationships over monolithic combination modules when the separation is useful.

Do not prematurely split working modules before the composition contracts exist.

### D010 — Mail control is an interface

Status: accepted.

Mail transport/authentication/encryption may remain as implementation code, but incoming commands must ultimately use the same Igor capabilities, safety, privilege, verification and history as other interfaces.

Notifications are conceptually separate from incoming control.

### D011 — Operational memory is not chat history

Status: accepted.

Incidents/actions/outcomes belong in structured Igor-owned history.

### D012 — Cleanup is continuous

Status: accepted.

A new authoritative path should retire its superseded path when safe. Final consolidation is not an excuse to leave duplicates active throughout development.

---

## Open decisions

### Q001 — Module implementation boundary

Question: Should Module API v2 remain Bash-first, or be language-neutral with Bash/Python/other implementations behind a structured contract?

Decision target: Steps 5–6.

### Q002 — Module manifest/schema format

Question: Keep INI/current `module.conf`, adopt YAML/TOML/JSON, or separate a simple manifest from structured schemas?

Decision target: Step 6.

### Q003 — System Model persistence

Question: Which state should survive restart, and which storage mechanism best fits the required operations (ephemeral JSON/files, SQLite, hybrid, other)?

Do not block System Model v1 on premature storage selection.

Decision target: before Step 15.

### Q004 — Module trust model

Question: What trust/permission levels apply to third-party modules that can provide executable code, knowledge, capabilities and automations?

Decision target: initial constraints in Step 6; deeper hardening later.

### Q005 — Dependency semantics

Question: How are hard module dependencies, optional integrations, capability dependencies and platform requirements represented/resolved?

Decision target: Step 6.

### Q006 — Core versus system module boundary

Question: Which host/Linux responsibilities are core platform primitives versus higher-level domain behavior in the `system` module?

Decision target: Steps 5–9.

### Q007 — Relationship/deployment ownership

Question: How are relationships created and reconciled between discovery, configuration, installers, users and AI proposals?

Likely requires provenance rather than a single owner.

Decision target: Step 17.

### Q008 — Automation activation policy

Question: Can installed modules activate automations automatically, or only propose defaults that require administrator policy/approval?

Current preference: modules propose; administrator/runtime policy activates.

Decision target: Step 14.

### Q009 — Integration-rule packaging

Question: Do cross-module rules live with one module, in separate integration packages, or in a normalized registry supporting both?

Resolve using concrete Nextcloud/Docker/Cloudflare cases.

Decision target: Steps 18–21.

### Q010 — Raw shell fallback policy

Question: Under what conditions may the AI use arbitrary shell when no registered capability fits, and what extra approval/verification requirements apply?

Decision target: Step 11.

### Q011 — Remote approval policy

Question: What READ/CHANGE/DESTROY operations may an authenticated email interface execute without an interactive TUI approval?

Decision target: Step 22.
