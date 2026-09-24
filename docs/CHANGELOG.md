# Changelog

All notable changes to Igor are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).  
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Fixed

- Validate AI tool fields without shell evaluation, execute semantic tool arguments
  directly, and require approval for raw commands outside the read-only allowlist.
- Include the core archive in full backups as an independent copy. Report missing
  archives, copy failures, and failed module hooks as partial failures; retain good
  backups when an attempt fails and exclude partial attempts from rotation counts.
- Include the encrypted secrets file in the snapshot component list after GPG
  encryption, and separate archive-path output from backup progress messages.
- Fix captured newlines in secret prompts and stale API key caches after key
  replacement. Add visible key entry, a dedicated API KEY menu option, and an
  `apikey` chat command; report save failures and preserve rejected replacements.
- Honor configured AI provider/model defaults and keep credential writes separate
  from ordinary settings saves.
- Stop unavailable email-control menu loading without recursive retries, and
  return failure for missing heartbeat implementation or failed heartbeat runs.
- Resolve manifest configuration paths relative to the repository and validate
  loaded modules after startup discovery.
- Reject modules missing their registration function. Dispatch registered module
  menus through the lifecycle loader while retaining legacy feature-file loading;
  stop on loading failures and preserve menu callback exit status.
- Preserve hook failure exit codes in diagnostics and use the canonical runtime
  directory (including overrides) for the extra monitoring TUI.
- Correct setup commands and document current menu, hook, configuration, and test
  contracts, including unavailable email control and incomplete service isolation.

## [1.0.0] — 2026-04-16

First public release. Igor began as a monolithic ~5800-line script (`nexusai.sh`)
and was restructured into a proper platform + module architecture.

### Platform (core/)

- **Module loader** (`core/lib/module_loader.sh`): discovery, topological sort by
  `depends_on`, syntax check, `source` + `__register()` call, idempotent reload.
  Public API: `igor_load_module`, `igor_register_hook`, `igor_run_all_hooks`,
  `igor_get_hooks`, `igor_has_bin`, `igor_has_module`, `igor_register_menu_item`.
- **Config loader** (`core/lib/config_loader.sh`): six-step load sequence —
  defaults → variables/*.env → secrets/*.env → secrets/*.key → legacy root envs →
  module config validation. Permission check on all secrets files.
- **AI subsystem** (`core/ai/`): multi-provider chat loop (Anthropic, OpenRouter,
  Ollama). Tool execution with three-tier safety gate (READ / CHANGE / DESTROY).
  Dual-model system (`/think` vs `/act`). Agentic task loop with scratchpad,
  hypothesis tracking, loop detection, context trimming. Module hook injection into
  system prompt and context.
- **`<run_igor_action>` tool**: AI can call registered module functions directly via
  the capability catalog (`igor_load_capabilities` + `ai_capabilities` hook).
- **Healing subsystem** (`core/healing/`): pluggable check files in
  `modules/*/checks/*.sh`. Each emits `CHECK_RESULT SEVERITY code message` lines.
  Score 0–100. Alert log with stale suppression (4 h). Pattern learning.
- **Diagnostic engine** (`core/diagnose/`): 6-phase session — env, system, storage,
  container, cross-container, app. Module hooks for health gate, role check, and
  app-layer checks. Fix catalogue with auto-apply and recheck loop.
- **Notification** (`core/notify/`): SMTP email via module event hooks
  (`notify_events`). Per-event NOTIFY_ON_* toggles configurable from menus.
- **Email control** (`core/mailcmd/`): IMAP polling, GPG verify (encrypted + signed
  required), command dispatch. Module `mailcmd` hook for verb registration.
- **Backup/restore** (`core/recovery/`): full snapshot with per-module `backup` /
  `restore` hooks. Auto-rotation. Action journal with `rollback_handler` hook.
- **IPC runtime** (`data/runtime/`): FIFO-based command bus for `--extra` TUI.
- **`--extra` TUI** (`core/extras/`): 6 split-pane lenses — output, control, watch,
  state, steer, conversation.

### Modules

- **`nextcloud_docker`**: Full Nextcloud-on-Docker management module.
  - Services: start/stop/restart/logs per container, maintenance mode.
  - Maintenance: file scan, previews, DB maintenance, cache flush, permissions, repair.
  - Configure: nginx inject/restore, NC settings, upload limit, trusted proxies.
  - Diagnose: HTTP routing, PHP-FPM, DB integrity, WebDAV, cron, app-layer checks.
  - AI integration: context hook (occ status, key config, tunnel, NC log),
    knowledge hook (full architecture, nginx rules, diagnostic decision tree),
    tiers hook, tools hook (`occ`, `container`, `run_igor_action`),
    patterns hook (5 static repair patterns), capabilities hook (12 callable actions).
  - Backup/restore: occ config export, DB dump, compose files.
  - Health check plugins: containers, network, nextcloud app, caching.
- **`system`**: Linux system module — CPU temperature, RAM, undervoltage (Pi),
  disk usage, swap. AI context with hardware model and I/O errors.

### Infrastructure

- `config/variables/` — non-sensitive settings tracked in git.
- `secrets/*.example` — credential templates tracked; real secrets gitignored.
- `config/stacks/` — user-editable compose files gitignored; templates in
  `modules/*/defaults/`.
- `data/` — entirely gitignored runtime directory.
- BATS test suite covering safety tier logic, config scrubbing, module contracts,
  healing patterns, diagnose roles.
- CI workflow: shellcheck on all shell files, BATS tests, Python tests.

---

## [0.x] — Pre-release development

Internal development iterations building up from `nexusai.sh`. Not publicly tagged.
