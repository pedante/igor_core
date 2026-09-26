# Igor 2 legacy map

This is a migration ledger, not a criticism of working code.

Entries describe current architectural paths that should be retained, adapted, replaced or removed as Igor 2 becomes authoritative.

Statuses:

- KEEP
- ADAPT
- REPLACE
- REMOVE
- TEMPORARY COMPATIBILITY

## Known items

| Area | Current path/behavior | Status | Igor 2 direction | Removal/transition target |
|---|---|---|---|---|
| Module activation | Modules discovered from directories and generally loaded from filesystem presence | REPLACE | Explicit available/enabled/loaded/failed/disabled runtime state | Step 5 |
| Diagnose checks | Direct discovery of `modules/*/checks/*.sh` in addition to module hooks | REPLACE | Active-module registry + unified check contract | Steps 5, 10 |
| Healing checks | Direct discovery of module check files | REPLACE | Active-module registry + observation/check model | Steps 5, 10, 19 |
| Module contract | Large named-hook surface documented in `docs/module_creation.md` | TEMPORARY COMPATIBILITY | Module API v2 concepts + compatibility adapter | Steps 6, 18, 23 |
| AI module context | Multiple `ai_*` hooks concatenate knowledge/context/tools/patterns | ADAPT | Knowledge & Context Engine consumes active module contracts/state | Step 12 |
| AI live probing | AI context gathering independently probes host/network/system data | ADAPT | System Model + observers become authoritative | Steps 8–12 |
| Core application leakage | Known Nextcloud-specific validation/assumptions remain in core paths | REMOVE/ADAPT | Move domain assumptions to modules/integration rules | Steps 1, 5–10 |
| Current host profile | Hardware/tier-focused host profile | KEEP/ADAPT | Contributor to broader System Model | Steps 7–9 |
| Capabilities | Existing `ai_capabilities` catalog and `run_igor_action` | KEEP/ADAPT | General Capability System v2 used by all interfaces | Step 11 |
| Safety tiers | READ/CHANGE/DESTROY classification and approvals | KEEP/ADAPT | Preserve deterministic backend; integrate capabilities/privilege broker | Steps 3–4, 11 |
| New AI TUI | `./igor.sh --ai-tui` structured Codex-like interface | KEEP/ADAPT | Become canonical Igor human interface | Step 20 |
| Old/menu interfaces | Traditional menus and older terminal flows | TEMPORARY COMPATIBILITY | Keep while needed; migrate useful surfaces into TUI/palette/backend | Step 20/23 |
| Mail control | `core/mailcmd/` owns transport and command dispatch | ADAPT | Mail transport + interface adapter invoking shared capabilities | Step 22 |
| Notification email | SMTP-centric notification implementation | ADAPT | Notification service with email as one transport | Step 22 |
| Config ownership | Subsystems/scripts own portions of env/config behavior | ADAPT | Shared schema/settings ownership while preserving secrets separation | Incremental; Steps 6, 20, 22 |
| Cron/scheduled behavior | External or subsystem-specific scheduling | REPLACE where applicable | Igor-owned Automation Engine | Step 14 |
| Operational memory | Healing patterns/journal/chat each carry partial history | ADAPT | Structured incident/action/outcome history | Steps 15, 19 |
| `--extra`/older split-pane UI | Legacy six-pane UI described in README | TEMPORARY COMPATIBILITY | New structured TUI is primary UX | Steps 1, 20, 23 |

## Rules for this file

When implementation proves a replacement:

1. update the entry;
2. remove the superseded code if compatibility no longer requires it;
3. do not leave an entry permanently marked "temporary" without a concrete reason.

Add newly discovered legacy paths here only when they have architectural significance. Ordinary dead-code cleanup does not require a ledger entry.
