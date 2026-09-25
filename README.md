# Igor

**I Guard. Observe. Repair.**

Igor is a modular Bash platform for operating self-hosted services on Linux.
The core provides an AI assistant, a self-healing engine, diagnostics,
notifications, and backup/restore. The service-agnostic split is still in progress:
some core diagnostics retain application code behind capability checks.
Modules plug into the core via a hook registry and add domain-specific logic.

`nextcloud_docker`, when present, manages a Nextcloud-on-Docker stack.
Check `modules/` for the modules available in your checkout.
The included `system` module monitors the host (CPU, RAM, disk, temperature).
New modules can be added without touching core code.

Modules can stay installed while disabled. Use `bash igor.sh --modules` to inspect
state and `bash igor.sh --disable nextcloud_docker` to disable its participation
in new Igor processes. Restart existing sessions after a policy change. This does
not stop running services or delete their data. See the
[module lifecycle and architecture assessment](docs/module_lifecycle.md).

> Built on a Raspberry Pi 3. Every design decision exists because something broke
> first at 3am. Nothing is theoretical.

---

## What the core provides

### Interactive TUI
fzf-powered menus for every operation. Falls back to plain numbered menus when
fzf or tmux is not available. Module sections use manifest menu items and registered callbacks; the core also
provides static assistant, diagnostics, recovery, and communications entries.

### AI assistant
Multi-provider in-terminal chat (Anthropic Claude, OpenRouter, Ollama/local).
At the chat prompt, type `help` for local commands or `:` to open the numbered
command palette. Enter a number to choose an action, `/text` to filter the list,
or `b` to return to chat. Actions that need arguments prompt for them before
running through the same command handler used by typed commands.

**Three-tier safety gate** — every AI-proposed command is classified before running:

| Tier | Examples | Behaviour |
|------|----------|-----------|
| `READ` | `docker ps`, `occ status`, log tails | Runs automatically |
| `CHANGE` | `docker compose restart`, `occ files:scan` | Pauses for `y/n` confirmation |
| `DESTROY` | `docker compose down -v`, `rm -rf` | Pauses with explicit warning |

Only explicitly recognized read-only command forms run automatically. A compound
command remains READ when every branch is recognized as read-only; stderr
suppression to `/dev/null` is allowed. Unknown commands, mutating branches,
other redirections, and substitutions require approval (CHANGE commands can
still run automatically in executive mode). Semantic OCC,
container, and log tools validate their arguments and execute them without a shell.

**Outbound secrets scrubbing** — before any context is sent to an external API,
`ai_scrub_outbound()` replaces sensitive values with tokens:
- Known passwords and API keys are redacted again at the transport boundary
- Domain, hostname, LAN IP, admin username → `[IGOR:DOMAIN]`, `[IGOR:HOSTNAME]`, etc.
- Module-declared scrub patterns (from `module.conf [secrets]`) are included automatically
- `ai_unscrub_inbound()` restores executable command fields before classification; unresolved tokens are rejected

**Module reference data** — active modules can provide:
- `ai_knowledge` — static architecture docs, decision trees, known failure modes
- `ai_context` — live system state (container status, occ output, recent logs)
- `ai_tiers` — advisory tier descriptions, never authorization rules
- `ai_patterns` — known repair patterns the AI can reference
- `ai_capabilities` — catalog of callable module actions

**`<run_igor_action>` tool** — the AI can call registered module functions directly
(e.g. `scan_files`, `flush_redis`, `fix_permissions`) with full tier gating. It does
not call arbitrary shell commands — only functions the module explicitly declared in
its capability catalog.

Inspect AI policy and capabilities with `bash igor.sh --ai status` or `--ai tools`.
Use `--ai last` for the latest structured operational trace. The catalog comes
from Igor's supported tool grammar and active module actions; legacy `ai_tools`
text cannot introduce executable tools. Configure policy in `config/variables/ai.env`
with private overrides in `secrets/ai.env`. See the [AI architecture report](aireport.md)
for configuration, trust boundaries, completed changes, and remaining limitations.

### Self-healing
Pluggable check files in `modules/*/checks/*.sh`. Each check emits
`CHECK_RESULT SEVERITY code message` lines. The healing engine runs all checks
on a configurable interval, calculates a health score (0–100), logs patterns,
suppresses repeated alerts (4 h stale window), and fires the `alert_hook`.

### Diagnostic engine
Six-phase session: env → system → storage → container → cross-container → app.
Module hooks for health gate, app-layer checks, and in-process role checks.
Auto-fix catalogue with recheck loop. Saves reports to `data/reports/`.

### Email control (unavailable)
The menus and configuration templates retain references to GPG-secured email
control, but `core/mailcmd/` is absent from this tree. Command mail and its
heartbeat require that implementation; configuring `secrets/mailcmd.env` alone
does not enable them.

### Notifications
SMTP email alerts via the `notify_events` hook. Each module declares its own
events (e.g. `nc_tunnel_down`, `stack_down`). Every event has a
`NOTIFY_ON_<EVENT>=true/false` toggle configurable from the menus without
editing files.

### Backup / restore
Full snapshot with per-module `backup` and `restore` hooks. Auto-rotation
(configurable count). Action journal with `rollback_handler` hook — the AI can
propose and execute rollback of journalled actions.

Full backups contain an independent copy of the core snapshot. Missing snapshots,
copy errors, or failed module hooks produce a partial manifest and a nonzero exit
status; partial attempts do not replace complete backups during rotation. Hook
errors are recorded in `MODULE_BACKUP_ERRORS.txt` inside the backup directory.
`config_backup_take` writes only the archive path to stdout and progress to stderr.

### `--extra` monitoring TUI
Run in a second terminal. Seven selectable lenses show output, control, watch,
state, steer, conversation, and captured terminal output. IPC via FIFO-based command bus in `data/runtime/`.

---

## Module system

A module is a directory under `modules/` containing:

```
modules/my_module/
├── module.conf        # manifest: name, version, deps, config files, secrets
├── module.sh          # hook implementations; must define <name>__register()
└── checks/            # optional health check plugins
    └── my_check.sh
```

For enabled modules whose requirements pass, `<name>__register()` is called by
the module loader at startup. It registers
functions against named hooks:

```bash
my_module__register() {
    igor_register_hook "health"          "my_module__health"
    igor_register_hook "ai_context"      "my_module__ai_context"
    igor_register_hook "ai_knowledge"    "my_module__ai_knowledge"
    igor_register_hook "ai_capabilities" "my_module__ai_capabilities"
    igor_register_hook "backup"          "my_module__backup"
    igor_register_hook "notify_events"   "my_module__notify_events"
    return 0
}
```

The core calls each hook at the right time. Modules never need to modify core code.

### Hook reference

| Hook | Called by | Execution | Purpose |
|------|-----------|-----------|---------|
| `health` | Explicit callers only; not currently dispatched by the header | caller-dependent | One-line `status:message` |
| `status_line` | header | subshell | Key-value display rows |
| `menu_header` | main menu | command substitution | Section title line |
| `diagnose` | diagnose runner (60-second default) | fresh Bash process | `CHECK:name:status:msg` lines |
| `app_diagnose` | diagnose phase 5 | in-process | App-layer checks |
| `health_gate` | diagnose gate | in-process | Is the app reachable? (0/1) |
| `role_check_app` | diagnose phase 3 | in-process | Container role checks |
| `alert_hook` | `alert_log()` | in-process | Side-effect on CRITICAL/FAIL |
| `ai_context` | `context.sh` | subshell | Live system state for AI |
| `ai_knowledge` | `context.sh` | subshell | Static reference data, separate from policy |
| `ai_tiers` | `context.sh` | subshell | Advisory tier descriptions |
| `ai_tools` | legacy only | not consumed | Use registered `ai_capabilities` actions |
| `ai_patterns` | `context.sh` | subshell | Known repair patterns |
| `ai_capabilities` | `igor_load_capabilities()` | subshell | Callable action catalog |
| `backup` | `full_backup.sh` | subshell | Module backup hook |
| `restore` | `full_backup.sh` | subshell | Module restore hook |
| `rollback_handler` | `journal.sh` | in-process | Undo command for action types |
| `config_validate` | `igor.sh` startup | in-process | Warn on missing config vars |
| `notify_events` | `notify/core.sh` | subshell | Event declarations |
| `mailcmd` | No dispatcher in this tree | — | Reserved email command verb list |

Full guide: [docs/module_creation.md](docs/module_creation.md)

---

## Configuration

### Two-layer design

Igor splits config into two layers that never mix:

| Layer | Location | Tracked by git | Contains |
|-------|----------|----------------|---------|
| Variables | `config/variables/*.env` | **yes** | Generic defaults — ports, thresholds, flags |
| Secrets | `secrets/*.env` + `secrets/*.key` | **no** | Everything personal or sensitive |

**Variables** are the same for any installation. You can clone the repo and they
work out of the box. **Secrets** identify you — domain, username, mount paths,
every password and API key. They live entirely in `secrets/` which is gitignored.

### secrets/ files

| File | Contents |
|------|----------|
| `site.env` | `DOMAIN`, `NC_USER_NAME`, `INSTALL_DIR`, `HD_MOUNT` |
| `db.env` | PostgreSQL + Nextcloud admin credentials |
| `notifications.env` | SMTP host/user/password, `NOTIFY_FROM`, `NOTIFY_TO`, event toggles |
| `mailcmd.env` | Full mailcmd config: IMAP/SMTP hosts, users, passwords, GPG key ID |
| `onlyoffice.env` | JWT secret for OnlyOffice integration |
| `anthropic.key` | Anthropic API key (single line) |
| `openrouter.key` | OpenRouter API key (single line) |

All `secrets/*.env` files must be `chmod 600`. Igor warns at startup if permissions
are wrong. The loader reads `secrets/` in step 2 of the config sequence — after
variables, so secrets override defaults. Deprecated root-level env files load last and can
override those values; migrate them into the standard directories.

### Config load order

```
1. core/config/defaults.conf      — compiled-in defaults
2. config/variables/*.env         — generic settings (tracked)
3. secrets/*.env                  — credentials + site overrides (gitignored)
4. secrets/*.key                  — API keys → exported as <STEM>_API_KEY
5. root-level *.env               — legacy fallback (deprecated, warns)
```

---

## AI providers

| Provider | Key file | Notes |
|----------|----------|-------|
| Anthropic | `secrets/anthropic.key` | Claude Sonnet / Haiku / Opus |
| OpenRouter | `secrets/openrouter.key` | Any model; DeepSeek, Gemini, etc. |
| Ollama | no key | Local models, no data leaves the machine |

Configure in `config/variables/ai.env`: `provider=`, `model=`, `executive_mode=`.

To replace a key inside Igor, open **AI Assistant → API KEY**, or select a
provider in **SETTINGS**. Key entry is visible so you can check your paste;
Enter without a key keeps the existing value. Igor validates replacements,
saves them in `secrets/<provider>.key` with mode `600`, and updates the active
session immediately. Saved `config/variables/ai_settings.env` preferences take
precedence over `ai.env` when opening chat.

If chat reports HTTP 401, type `apikey` to replace the active provider's key,
then resend your message. Enter the key at the separate prompt, not in a chat
message. Saving other AI settings does not rewrite credentials.

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| Bash 4.2+ | Associative arrays required |
| Python 3 | AI transport, tool validation, conversation processing, and rendering; CI uses 3.11 |
| curl | API calls and health probes |
| Linux with systemd | Raspberry Pi OS, Ubuntu, Debian, Arch, etc. |
| Docker + Compose plugin | Required by `nextcloud_docker` module only |
| tmux *(optional)* | Split-pane AI panel, fzf popup menus |
| fzf *(optional)* | Enhanced menus — plain text menus work without it |
| bats *(optional)* | Running the test suite |

Igor was developed on a **Raspberry Pi 3 (1 GB RAM)**. It runs on any Linux where
Bash 4.2 is available. The `system` module supports Pi-specific hardware readings
(vcgencmd temperature, undervoltage) with generic `/proc` fallbacks on other hardware.

---

## Quick start

```bash
# Run from the root of your existing clone.
# Create only the configuration files needed by your modules/features.
cp secrets/site.env.example secrets/site.env
cp secrets/notifications.env.example secrets/notifications.env
chmod 600 secrets/site.env secrets/notifications.env
# Edit these files with your real values.

# Add an API key if using a hosted provider. Create/edit with your editor:
${EDITOR:-vi} secrets/anthropic.key
chmod 600 secrets/anthropic.key
# For OpenRouter use secrets/openrouter.key instead; Ollama needs no key.

# Run
bash igor.sh
```

Launch Igor as your regular user (`bash igor.sh` or `./igor.sh`), not with
`sudo bash igor.sh`. Menus, AI sessions, context collection, and private runtime
files use your user account. Approved operations that require root privileges
use `sudo` for that operation after Igor's authorization step. Root launches
are rejected so a root process cannot use another user's private runtime.

If `nextcloud_docker` is present, also configure its documented secrets and setup menu.

---

## Project layout

```
igor/
├── igor.sh                    Entry point
├── core/                      Platform engine — service-agnostic
│   ├── ai/                    Chat loop, API dispatch, scrub, safety gate, context
│   ├── diagnose/              6-phase diagnostic engine
│   ├── healing/               Check runner, score, alert log, pattern learning
│   ├── notify/                SMTP notifications, per-event toggles
│   ├── recovery/              Backup/restore framework, action journal
│   ├── extras/                --extra monitoring TUI (7 lenses)
│   ├── tunnel/                Cloudflare tunnel management
│   ├── host/                  Host profile, sudoers integration
│   └── lib/                   ui, helpers, config_loader, module_loader
├── modules/
│   ├── nextcloud_docker/      Optional; may be absent from this checkout
│   └── system/                Linux system: CPU, RAM, disk, temperature
├── config/
│   ├── variables/             Generic settings — tracked, no personal data
│   ├── patterns/              Repair patterns; includes tracked files
│   ├── knowledge/             AI knowledge base — gitignored
│   └── stacks/                User-edited compose files — gitignored
├── secrets/                   All personal data + credentials — gitignored
├── data/                      Runtime: alerts, backups, sessions, reports — gitignored
├── scripts/                   inspect.sh — module dependency viewer
├── tests/                     BATS + Python tests
└── docs/
    ├── module_creation.md     Complete module development guide
    ├── CHANGELOG.md
    └── CONTRIBUTING.md
```

---

## Running tests

```bash
./tests/run_all.sh             # full suite (requires bats-core)
bats tests/core/test_safety.bats   # single BATS test
python3 -m pytest tests/       # Python tests (requires pytest)
```

---

BATS must be installed for a complete run; the runner skips its suites otherwise.
Some contract tests explicitly require `nextcloud_docker` and fail when it is absent.

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).
Open an issue before large changes.

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
