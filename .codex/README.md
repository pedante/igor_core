# Igor Codex orchestration

This directory contains Igor's project-local Codex policy. Codex loads `.codex/config.toml` for trusted projects, so the policy follows the repository instead of depending on one person's global `~/.codex/config.toml`.

## Root/orchestrator model is intentionally changeable

`config.toml` gives new Igor threads an efficient default:

- **GPT-6.1 Sol / Medium** — normal Igor engineering.

This is a default, not a lock. An explicit model/reasoning choice overrides it. In an interactive Codex session, use `/model` to choose the model and reasoning effort for the root/orchestrator. You can therefore use Luna for cheap bounded work, Sol Medium for normal coding, stronger Sol reasoning for difficult engineering, or Astra only when the task really deserves system-level architectural reasoning.

The project instructions ask the root to flag a meaningful model mismatch before it starts substantial work. Example: `Model fit: Sol Medium is sufficient for this task.` This is meant to prevent doing an ordinary task on Astra by accident.

## Agent hierarchy

```text
Project Owner
    |
    v
Root / orchestrator (chosen per task; default: Sol 6.1 Medium)
    |\
    | +--> Luna helpers (default: Medium)
    |      search, tests, builds, reproduction, docs, mechanical work
    |
    +----> Lead_Eng (Sol 6.1 XHigh)
            difficult engineering, architecture-sensitive implementation,
            hard debugging, cross-cutting integration
                |
                +--> Luna helpers (bounded support work)
```

`Lead_Eng` is a named Codex role declared in `config.toml` and implemented by `Lead_Eng.config.toml`. Ordinary Luna helpers may not recursively delegate. `Lead_Eng` is explicitly allowed to do so for bounded helper work.

## Cost discipline

The design is intentionally asymmetric: cheap agents consume disposable exploration/test context; stronger models keep their context for work where continuity and judgment matter. Multi-agent is not automatically cheaper if it is used unnecessarily, so the instructions explicitly avoid duplicate checks and manufactured parallelism.

The project caps Multi-Agent V2 at four spawned threads per session and uses long `wait_agent` timeouts so agents can finish without routine polling. A wait returns early when the agent completes.

## Compatibility

These files use current Codex project configuration, custom agent roles, `models.new_thread`, and Multi-Agent V2 settings. Keep Codex reasonably current. If Codex reports an unknown setting after an upgrade/downgrade, validate the project configuration against that installed release before removing behavior.
