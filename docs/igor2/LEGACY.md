# Igor 2 legacy map

This is a migration ledger, not a criticism of working code.

Statuses:

- KEEP
- ADAPT
- REPLACE
- REMOVE
- TEMPORARY COMPATIBILITY

Only architecture-significant paths belong here. Step 1 must refine this table with repository evidence.

| Area | Current path/behavior | Status | Igor 2 direction | Target |
|---|---|---|---|---|
| Module activation | `config/modules.conf`, enabled/disabled policy, active/unavailable runtime, owner-aware registrations | KEEP/ADAPT | Formalize as Module Runtime v2; close remaining bypasses; no parallel loader | Steps 1, 5 |
| Diagnose check discovery | Still enumerates active modules' `checks/*.sh` plus hooks | ADAPT | Unified structured check/observation contract | Steps 5, 10 |
| Healing check discovery | Enumerates active module check files separately from diagnose | ADAPT | Unified structured check/observation contract | Steps 5, 10, 19 |
| Module API v1 | Hook-heavy contract in `docs/module_creation.md` | TEMPORARY COMPATIBILITY | Versioned Module API v2 + proven compatibility path | Steps 6, 18, 23 |
| AI module/context hooks | `ai_context`, `ai_knowledge`, `ai_tiers`, `ai_patterns`, capabilities | ADAPT | Knowledge/context composition from active contracts + System Model | Step 12 |
| AI direct host probing | `ai_gather_context` probes host/network/storage directly | ADAPT | Observers + System Model become authoritative where migrated | Steps 8–12 |
| AI reference-data boundary | `request_boundary.py`, privacy/redaction, reference envelope | KEEP | Preserve and feed it better structured context | Step 12 |
| Frontend event stream | `core/ai/events.sh` JSONL activity stream | KEEP | Preserve for interfaces; do not misuse as domain event bus | Steps 3, 13 |
| Interaction runtime | TUI/session registry/modes/approvals/pending choices | KEEP/ADAPT | Harden/generalize; future interfaces reuse backend state | Step 3 |
| Privilege flow | backend/native sudo PTY + privilege events | KEEP/ADAPT | Generalize privilege metadata through capabilities | Steps 4, 11 |
| Platform helpers | `distro.sh`, `pkg.sh`, Python shim | KEEP/ADAPT | Expand/test normalized Debian+Arch platform contract | Step 7 |
| Capability/action catalog | `ai_capabilities`, ownership, `run_igor_action`, catalog/control code | KEEP/ADAPT | General Igor capability API | Step 11 |
| Operational audit/journal | AI bounded audit + recovery journal/pattern history | KEEP/ADAPT | Structured incidents/actions/outcomes | Step 15 |
| Core application leakage | Nextcloud/Docker/Cloudflare-specific assumptions remain in some core paths | REMOVE/ADAPT | Move domain behavior behind modules/integration rules | Steps 1, 5–12 |
| Classic menu/line UI | Older menus and line-mode AI remain alongside full-screen TUI | TEMPORARY COMPATIBILITY | Preserve until TUI/shared backend covers normal workflows | Steps 20, 23 |
| `--extra` monitoring UI | Separate legacy monitoring interface | TEMPORARY COMPATIBILITY | Audit unique value, then consolidate/remove when superseded | Steps 1, 20, 23 |
| Email control references | Config/menu/docs references remain but `core/mailcmd/` implementation is absent | ADAPT/REMOVE | Do not imply availability; if reintroduced, make it a shared-engine interface | Steps 1, 22 |
| SMTP notifications | Notify subsystem is email-centric | ADAPT | Notification service consuming domain events; email is one transport | Steps 13, 22 |
| Subsystem-owned config | Multiple scripts/subsystems own portions of env/settings behavior | ADAPT | Move toward shared schemas/ownership as relevant contracts mature | Incremental |
| External scheduling/cron behavior | Scheduling is not one Igor-owned automation contract | REPLACE where applicable | Automation Engine | Step 14 |

## Rules

When a replacement is proven:

1. update this entry;
2. remove the superseded path if compatibility no longer requires it;
3. do not leave temporary compatibility without a reason/removal condition.

Do not add ordinary dead code here; delete it.
