# Igor

**I Guard. Observe. Repair.**

Igor is a modular Bash platform for operating self-hosted services on Linux.
The core is service-agnostic: it provides an AI assistant, a self-healing engine,
a diagnostic framework, encrypted email control, notifications, and backup/restore.
Modules plug into the core via a hook registry and add domain-specific logic.

The included `nextcloud_docker` module manages a full Nextcloud-on-Docker stack.
The included `system` module monitors the host (CPU, RAM, disk, temperature).
New modules can be added without touching core code.

> Built on a Raspberry Pi 3. Every design decision exists because something broke
> first at 3am. Nothing is theoretical.

---

## What the core provides

### Interactive TUI
fzf-powered menus for every operation. Falls back to plain numbered menus when
fzf or tmux is not available. All menu items are registered by modules — the core
renders whatever is wired up.

### AI assistant
Multi-provider in-terminal chat (Anthropic Claude, OpenRouter, Ollama/local).

**Three-tier safety gate** — every AI-proposed command is classified before running:

| Tier | Examples | Behaviour |
|------|----------|-----------|
| `READ` | `docker ps`, `occ status`, log tails | Runs automatically |
| `CHANGE` | `docker compose restart`, `occ files:scan` | Pauses for `y/n` confirmation |
| `DESTROY` | `docker compose down -v`, `rm -rf` | Pauses with explicit warning |

**Outbound secrets scrubbing** — before any context is sent to an external API,
`ai_scrub_outbound()` replaces sensitive values with tokens:
- Passwords and API keys are omitted entirely (never sent)
- Domain, hostname, LAN IP, admin username → `[IGOR:DOMAIN]`, `[IGOR:HOSTNAME]`, etc.
- Module-declared scrub patterns (from `module.conf [secrets]`) are included automatically
- `ai_unscrub_inbound()` reverses tokens on `EXECUTE` lines only, so commands run with real values

**Module prompt injection** — modules hook into the AI session to provide:
- `ai_knowledge` — static architecture docs, decision trees, known failure modes
- `ai_context` — live system state (container status, occ output, recent logs)
- `ai_tiers` — per-module tool safety classifications
- `ai_tools` — tool definitions (JSON) the AI can call
- `ai_patterns` — known repair patterns the AI can reference
- `ai_capabilities` — catalog of callable module actions

**`<run_igor_action>` tool** — the AI can call registered module functions directly
(e.g. `scan_files`, `flush_redis`, `fix_permissions`) with full tier gating. It does
not call arbitrary shell commands — only functions the module explicitly declared in
its capability catalog.

### Self-healing
Pluggable check files in `modules/*/checks/*.sh`. Each check emits
`CHECK_RESULT SEVERITY code message` lines. The healing engine runs all checks
on a configurable interval, calculates a health score (0–100), logs patterns,
suppresses repeated alerts (4 h stale window), and fires the `alert_hook`.

### Diagnostic engine
Six-phase session: env → system → storage → container → cross-container → app.
Module hooks for health gate, app-layer checks, and in-process role checks.
Auto-fix catalogue with recheck loop. Saves reports to `data/reports/`.

### Email control (GPG-secured)
IMAP poller reads an inbox, verifies each message is **both GPG-encrypted and
GPG-signed** before dispatching. An unsigned or unencrypted message is silently
dropped. Modules register command verbs via the `mailcmd` hook. Built-in verbs:
status, restart, upgrade, diagnose.

### Notifications
SMTP email alerts via the `notify_events` hook. Each module declares its own
events (e.g. `nc_tunnel_down`, `stack_down`). Every event has a
`NOTIFY_ON_<EVENT>=true/false` toggle configurable from the menus without
editing files.

### Backup / restore
Full snapshot with per-module `backup` and `restore` hooks. Auto-rotation
(configurable count). Action journal with `rollback_handler` hook — the AI can
propose and execute rollback of journalled actions.

### `--extra` split-pane TUI
Six tmux lenses running alongside the main session: output, control, watch,
state, steer, conversation. IPC via FIFO-based command bus in `data/runtime/`.

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

`<name>__register()` is called by the module loader at startup. It registers
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
| `health` | header, status bar | subshell | One-line `status:message` |
| `status_line` | header | subshell | Key-value display rows |
| `menu_header` | main menu | subshell | Section title line |
| `diagnose` | diagnose runner | subshell | `CHECK:name:status:msg` lines |
| `app_diagnose` | diagnose phase 5 | in-process | App-layer checks |
| `health_gate` | diagnose gate | in-process | Is the app reachable? (0/1) |
| `role_check_app` | diagnose phase 3 | in-process | Container role checks |
| `alert_hook` | `alert_log()` | in-process | Side-effect on CRITICAL/FAIL |
| `ai_context` | `context.sh` | subshell | Live system state for AI |
| `ai_knowledge` | `context.sh` | subshell | Static knowledge in system prompt |
| `ai_tiers` | `context.sh` | subshell | READ/CHANGE/DESTROY rules |
| `ai_tools` | `ai_router.sh` | subshell | Tool JSON definitions |
| `ai_patterns` | `context.sh` | subshell | Known repair patterns |
| `ai_capabilities` | `igor_load_capabilities()` | subshell | Callable action catalog |
| `backup` | `full_backup.sh` | subshell | Module backup hook |
| `restore` | `full_backup.sh` | subshell | Module restore hook |
| `rollback_handler` | `journal.sh` | in-process | Undo command for action types |
| `config_validate` | `igor.sh` startup | in-process | Warn on missing config vars |
| `notify_events` | `notify/core.sh` | subshell | Event declarations |
| `mailcmd` | mailcmd subsystem | in-process | Email command verb list |

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
variables, so secrets always override defaults.

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

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| Bash 4.2+ | Associative arrays required |
| Python 3.6+ | JSON/API calls only — no application logic |
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
# 1. Clone
git clone https://github.com/yourusername/igor.git
cd igor

# 2. Create secrets from templates
cd secrets/
cp site.env.example          site.env
cp db.env.example            db.env
cp notifications.env.example notifications.env
cp mailcmd.env.example       mailcmd.env
chmod 600 *.env
# Edit each file with your real values

# 3. Add API key (pick one)
echo "sk-ant-..." > secrets/anthropic.key
# or:
echo "sk-or-..."  > secrets/openrouter.key
chmod 600 secrets/*.key

# 4. Run
cd ..
bash igor.sh
```

For the Nextcloud module: `main menu → S SETUP & INSTALL → 0 WIZARD`

---

## Project layout

```
igor/
├── igor.sh                    Entry point
├── core/                      Platform engine — service-agnostic
│   ├── ai/                    Chat loop, API dispatch, scrub, safety gate, context
│   ├── diagnose/              6-phase diagnostic engine
│   ├── healing/               Check runner, score, alert log, pattern learning
│   ├── mailcmd/               GPG-secured IMAP poller, command dispatch
│   ├── notify/                SMTP notifications, per-event toggles
│   ├── recovery/              Backup/restore framework, action journal
│   ├── extras/                --extra split-pane TUI (6 lenses)
│   ├── tunnel/                Cloudflare tunnel management
│   ├── host/                  Host profile, sudoers integration
│   └── lib/                   ui, helpers, config_loader, module_loader
├── modules/
│   ├── nextcloud_docker/      Nextcloud-on-Docker: full TUI + all hooks
│   └── system/                Linux system: CPU, RAM, disk, temperature
├── config/
│   ├── variables/             Generic settings — tracked, no personal data
│   ├── patterns/              Learned repair patterns — gitignored
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
pytest tests/                  # Python tests (requires pytest)
```

---

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).
Open an issue before large changes.

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
