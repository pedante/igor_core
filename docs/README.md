# Igor — Documentation Index

| Document | Description |
|----------|-------------|
| [../README.md](../README.md) | Project overview, quick start, layout |
| [module_creation.md](module_creation.md) | Complete module development guide — every hook point |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |

---

## Architecture summary

```
igor.sh                Entry point — sources core/, lazy-loads modules
core/
  ai/                  Chat loop, API dispatch, safety gate, context injection
  healing/             Check runner, score, alerts, pattern learning
  diagnose/            6-phase engine, fix catalogue, session reports
  mailcmd/             GPG-secured IMAP poller, command dispatch
  notify/              SMTP notifications, per-event toggles
  recovery/            Backup/restore framework, action journal
  extras/              --extra split-pane TUI (6 lenses)
  tunnel/              Cloudflare tunnel management
  host/                Host profile, sudoers integration
  lib/                 ui, helpers, config, module_loader, config_loader, …
modules/
  nextcloud_docker/    Nextcloud-on-Docker: full TUI + all hooks
  system/              Linux system: CPU, RAM, disk, undervoltage
config/
  variables/           Non-sensitive settings (tracked)
  stacks/              User-editable compose files (gitignored)
secrets/               Credentials (gitignored); *.example files tracked
data/                  Runtime data — entirely gitignored
```

## Hook system

Modules register functions against named hooks. The core calls each hook at the right time:

| Hook | Called by | Purpose |
|------|-----------|---------|
| `health` | header, status bar | One-line `status:message` |
| `status_line` | header | Key-value display rows |
| `menu_header` | main menu | Section title line |
| `diagnose` | diagnose runner | `CHECK:name:status:msg` lines |
| `app_diagnose` | diagnose phase 5 | In-process app-layer checks |
| `health_gate` | diagnose gate | Is the app reachable? (0/1) |
| `role_check_app` | diagnose phase 3 | In-process container role checks |
| `alert_hook` | alert_log() | Side-effect on CRITICAL/FAIL |
| `ai_context` | context.sh | Live system state for AI |
| `ai_knowledge` | context.sh → ai_render.py | Static knowledge in system prompt |
| `ai_tiers` | context.sh → ai_render.py | READ/CHANGE/DESTROY rules |
| `ai_tools` | ai_router.sh | Tool JSON definitions |
| `ai_patterns` | context.sh | Known repair patterns |
| `ai_capabilities` | igor_load_capabilities() | Callable action catalog |
| `backup` | full_backup.sh | Module backup hook |
| `restore` | full_backup.sh | Module restore hook |
| `rollback_handler` | journal.sh | Undo command for action types |
| `config_validate` | igor.sh startup | Warn on missing config vars |
| `notify_events` | notify/core.sh | Event declarations for toggles |
| `mailcmd` | mailcmd subsystem | Email command verb list |

Full documentation: [module_creation.md](module_creation.md)
