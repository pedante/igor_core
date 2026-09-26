# Igor 2 architectural decisions

Accepted decisions should not be repeatedly reopened without new repository evidence. Open decisions are resolved at the roadmap stage where they become necessary.

## Accepted

### D001 — Codex-like TUI is the primary human-interface direction

The structured full-screen TUI is the main Igor UX direction. CLI/headless paths remain for scripting, recovery, testing and automation. Long-term, `./igor.sh` should launch the primary TUI when migration permits.

### D002 — AI autonomy and OS privilege are separate

Guide/Assist/Executive determine interaction autonomy. They do not grant root. Privilege is authenticated/authorized by the runtime for the exact operation.

### D003 — Module presence is not module activation

A module existing under `modules/` is insufficient for runtime contribution.

### D004 — Core remains application-agnostic

Application/deployment-specific behavior belongs to modules or integration rules rather than core.

### D005 — Debian and Arch Linux are initial tested platform targets

Existing family detection/package mappings are useful seeds. Support is claimed only to the level tests demonstrate.

### D006 — Knowledge and observed state are different

Knowledge explains domains. The System Model represents what is known about this machine.

### D007 — Capabilities are the shared operational API

TUI, CLI, healing, automation and future external control converge on shared capabilities instead of duplicate domain operations.

### D008 — Modules may declare automation; Igor owns scheduling

Scheduling, policy, retries, privilege, execution and history are runtime responsibilities.

### D009 — Modules compose through instances/relationships

Prefer coherent reusable domain modules plus deployment relationships over monolithic combination modules when the separation provides real reuse. Do not split working modules before composition contracts exist.

### D010 — Mail control, if reintroduced, is an interface

The current tree does not contain the old `core/mailcmd/` implementation. If authenticated mail control returns, it must invoke shared Igor capabilities/safety/privilege/verification/history. Notifications remain conceptually separate from incoming control.

### D011 — Operational memory is not chat history

Incidents/actions/outcomes belong in structured Igor-owned history.

### D012 — Cleanup is continuous

A new authoritative path retires the superseded path when safe. Final consolidation is not an excuse to leave duplicates active indefinitely.

### D013 — Preserve the current AI reference-data trust boundary

Module prose, context, logs, reports, tool results and history summaries are reference data. They can inform reasoning but cannot authorize actions or modify deterministic policy.

### D014 — Frontend events and domain events are different contracts

`core/ai/events.sh` is a valuable frontend activity stream. The future Domain Event Bus represents operational events consumed by automation/healing/notifications/history. Do not conflate the two.

### D015 — Evolve the existing module activation runtime

Current enable/disable and owner-aware activation is the Module Runtime v2 starting point. Do not introduce a parallel module loader or rename state vocabulary solely for architectural cosmetics.

### D016 — Evolve the existing platform helpers

`distro.sh`, `pkg.sh` and Python resolution are the platform-abstraction starting point. Expand/test them rather than create a second distro layer.

---

## Open decisions

### Q001 — Module implementation boundary

Should Module API v2 remain Bash-first, or be language-neutral with Bash/Python/other implementations behind a structured contract?

Decision target: Step 6.

### Q002 — Module manifest/schema format

Keep current INI-style `module.conf`, adopt YAML/TOML/JSON, or separate a simple manifest from structured schemas?

Decision target: Step 6.

### Q003 — System Model persistence

Which state survives restart, and what storage mechanism best fits actual access/history requirements?

Do not block System Model v1 on premature storage selection.

Decision target: before Step 15.

### Q004 — Module trust model

What trust/permission levels apply to future third-party modules providing executable code, knowledge, capabilities and automations?

Decision target: initial constraints in Step 6; deeper hardening later.

### Q005 — Dependency semantics

How are hard module dependencies, optional integrations, capability requirements and platform requirements represented/resolved?

Decision target: Step 6.

### Q006 — Core versus system-module boundary

Which Linux responsibilities are core platform primitives versus higher-level host-domain behavior in `system`?

Decision target: Steps 5–9.

### Q007 — Relationship/deployment ownership

How are relationships created/reconciled among discovery, configuration, installers, users and AI proposals?

Decision target: Step 17.

### Q008 — Automation activation policy

Can a module activate an automation automatically, or only propose defaults that administrator/runtime policy enables?

Current preference: modules propose; policy activates.

Decision target: Step 14.

### Q009 — Integration-rule packaging

Do cross-module rules live with one module, separate integration packages, or a registry supporting both?

Resolve using real Nextcloud/Docker/Cloudflare cases.

Decision target: Steps 18–21.

### Q010 — Raw shell fallback policy

When may AI use arbitrary shell because no capability fits, and what additional approval/verification applies?

Decision target: Step 11.

### Q011 — Remote approval policy

If remote control is added, which READ/CHANGE/DESTROY operations may execute without an interactive TUI approval?

Decision target: Step 22.
