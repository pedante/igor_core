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

> **Igor 2 development:** this README documents the current implementation. The target architecture, migration rules, and current Igor 2 status live in [docs/igor2/](docs/igor2/README.md). Igor 2 evolves the recent TUI, module activation, safety, capability, and platform work rather than rebuilding those foundations.

Modules can stay installed while disabled. Use `bash igor.sh --modules` to inspect
API version, activation state, unavailable reasons and owned contributions.
Use `bash igor.sh --modules inspect system` for data-only JSON package inspection
or `bash igor.sh --modules detach-plan system` for a read-only impact assessment.
These commands source no module code or legacy configuration and do not refresh
observers. Static inspection does not evaluate process activation; detach
assessment reports missing inventories and does not certify or execute detach.
Use `bash igor.sh --disable nextcloud_docker` to disable its participation
in new Igor processes. Restart existing sessions after a policy change. This does
not stop running services or delete their data. See the
[module lifecycle and architecture assessment](docs/module_lifecycle.md).

`bash igor.sh --deployments status`, `--deployments list`,
`--deployments inspect DEPLOYMENT_ID` and `--deployments export` inspect the
Core-owned deployment identity, bindings, relationships and scoped responsibility
registry without loading modules, probing applications or creating storage.
Discovery and resource participation imply no management duty. This first
foundation exposes internal metadata contracts and read-only inspection; it
does not adopt an application, provision resources or certify detach. See the
[deployment contract](docs/igor2/DEPLOYMENTS.md).

With System active, the chat command `memory-warning 220` proposes, commits,
applies and independently verifies a 220 MiB memory warning threshold for the
current Igor process through normal approval and Operational History. The
warning default is 150 MiB (valid range 81–4096); critical remains 80 MiB.
`bash igor.sh --configuration inspect system.memory.warning_threshold_mib`
inspects Core-owned desired state. See the
[System workflow](docs/igor2/SYSTEM_MEMORY_WORKFLOW.md) for runtime evidence,
failure handling and explicit recovery.

> Built on a Raspberry Pi 3. Every design decision exists because something broke
> first at 3am. Nothing is theoretical.

---

## What the core provides

### Classic menu interface
fzf-powered menus for current menu-driven operations. Falls back to plain numbered menus when
fzf or tmux is not available. Module sections use manifest menu items and registered callbacks; the core also
provides static assistant, diagnostics, recovery, and communications entries.

### AI assistant
Multi-provider in-terminal chat (Anthropic Claude, OpenRouter, Ollama/local).
At the chat prompt, type `help` for local commands or `:` to open the numbered
command palette. Enter a number to choose an action, `/text` to filter the list,
or `b` to return to chat. Actions that need arguments prompt for them before
running through the same command handler used by typed commands.

Launch the full-screen AI chat with `bash igor.sh --ai-tui`. It uses Python 3's
standard-library curses support and needs an interactive terminal. The classic
line UI remains available through `bash igor.sh`; use it for initial provider
setup or whenever the full-screen UI is unavailable. In the full-screen UI,
activity scrolls above a fixed input area. Press Enter to send, Ctrl+O or
Alt+Enter for another input line, and F1 for the full key list. Up/Down recall
previous prompts or move within multiline input; Left/Right, Home/End,
Backspace/Delete, and Ctrl+W edit the draft. Page Up/Page Down scroll activity;
End returns to live output when the input is empty. Ctrl+P, or `:` on an empty
input, opens the registry-backed palette. Type to filter, use Up/Down to select,
and Esc to return to the draft. Unavailable commands are marked and cannot be
chosen from the palette; typed commands still go to the backend registry.
Choose **Settings** in the palette to edit provider, model, temperature, token
limit, mode, verbose output, AI autostart, and the hybrid menu. Up/Down selects
a setting, Enter toggles or edits it, and Esc returns to the current draft.
Typing `settings` in the TUI opens the same view; the classic UI still prints
a summary.
Tab/Shift+Tab cycles focus between input, output and the open control panel.
Ctrl+B shows/hides the panel; Ctrl+F returns to latest output while preserving
the draft. With output focused, arrows and Home/End navigate output; mouse
wheel scrolling works over output on terminals that support it. The header
shows focus and LIVE or the distance from newest output. In the panel,
Up/Down selects a section and Page Up/Down scrolls its content. Enter on History
loads recent durable Operational History through the read-only backend CLI;
Enter on Settings opens the existing settings editor. Session/AI and execution
provenance are informational. See [interaction primitives](docs/interaction_surface.md)
for the reusable schema/property model and authority boundary.
Ctrl+G collapses or expands successful tool output, while failures stay visible.
Esc clears the draft; Ctrl+C or `/stop` uses the backend stop action. Pending
actions show Run/Skip/Explain or Yes/No/Explain choices; destructive actions
still require exact `YES`. Stop is handled at an approval prompt or the next
backend chat prompt; it does not interrupt a provider or tool
call already in progress.

**Three-tier safety gate** — every AI-proposed command is classified before running:

| Tier | Examples | Behaviour |
|------|----------|-----------|
| `READ` | `docker ps`, `occ status`, log tails | Proposed in Guide; automatic in Assist and Executive |
| `CHANGE` | `docker compose restart`, `occ files:scan` | Pauses for Yes, No, Explain, or `/stop` unless Executive policy auto-approves |
| `DESTROY` | `docker compose down -v`, `rm -rf` | Requires typing `YES`; Explain, No, and `/stop` are also available |

Only explicitly recognized read-only command forms qualify for automatic execution. A compound
command remains READ when every branch is recognized as read-only; stderr
suppression to `/dev/null` is allowed. Unknown commands, mutating branches,
other redirections, and substitutions require approval (CHANGE commands can
still run automatically in executive mode). Semantic OCC,
container, and log tools validate their arguments and execute them without a shell.
Type `mode guide`, `mode assist`, or `mode executive` in chat, or choose `mode`
from the command palette. Guide proposes READ actions with Run, Skip, Explain,
and `/stop`; Assist runs READ actions automatically and asks before CHANGE;
Executive also auto-approves CHANGE under the existing policy. DESTROY always
requires exact `YES`. The old `exec on` and `exec off` commands map to Executive
and Assist, respectively. A pending action must be resolved before switching modes.
At an approval prompt, `e` explains the pending action from Igor's parsed
request and returns to the same prompt without running it. `n` declines that
action; `/stop` cancels it and stops the current continuation. Explain asks the
configured AI model for a focused explanation. The model's wording cannot change
Igor's classification, approval requirement, or pending command. A provider
failure returns to the same approval prompt.
When Igor offers numbered choices in chat, short replies such as `2`, `logs`,
or `the second one` are resolved against that pending question by the backend.
A bare `cancel` dismisses the question locally; a new request clears it before
the provider handles the new topic.

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

**Canonical capabilities** — complete Module API v2 capability declarations
are resolved by dotted ID and active provider. `run_capability` validates
structured inputs and deterministic preconditions before the same approval
gate, then reports execution and verification separately. The first real
capability is `system.host.memory.refresh`; v1 actions remain available through
`run_igor_action`. Use `bash igor.sh --capabilities list`,
`--capabilities inspect <id>`, or `--capabilities plan '<JSON>'` for read-only
inspection and plan resolution. `bash igor.sh --context inspect` shows the
current memory-domain context selection without refreshing an observer.
Raw AI shell requests are identified as unstructured; raw CHANGE requires
explicit approval even in Executive mode and has no automatic postcondition
verification.

The existing memory refresh now uses capability version 2 with a closed typed
domain result; version 1 capabilities remain supported. Requests and plans may
pin an exact capability version. Core validates provider output separately from
execution and verification, and records invalid output without claiming success
or erasing a possible effect. See [the module contract](docs/igor2/MODULE_API.md).

AI requests now use bounded context selection and inspectable model roles.
The Context / Routing TUI panel shows included/excluded sources and routing
rules. `bash igor.sh --context last` reads the latest retained decision metadata;
`--context select 'JSON'` previews explicit scoped investigation/history
references without a model call. In chat, `context JSON` sets selection references
or tags and `context reset` clears them. Configure optional reasoner/summarizer/
context_ranker bindings through `IGOR_AI_ROLE_BINDINGS` in existing AI settings.
Selection records are operational provenance only, never automatic knowledge or
authorization. See [context and routing](docs/igor2/CONTEXT_ROUTING.md).

Canonical capability invocations also create durable Operational History.
Use `bash igor.sh --history recent`, `--history inspect <operation-id>`,
`--history correlation <id>` or `--history status` for read-only JSON inspection
without the TUI. CHANGE attempts receive durable identity before execution;
after interruption they remain explicitly unknown and are never automatically
repeated. See [Operational History](docs/operational_history.md) for the record
contract, explicit verification-only recovery, export/restore and reset.
Chat `history`/`replay` still display session transcripts; `--ai last` remains
the bounded AI audit view.

Inspect AI policy and capabilities with `bash igor.sh --ai status` or `--ai tools`.
Use `--ai last` for the latest structured operational trace. The catalog comes
from Igor's supported tool grammar and active module actions; legacy `ai_tools`
text cannot introduce executable tools. Configure policy in `config/variables/ai.env`
with private overrides in `secrets/ai.env`. For Igor 2 trust/context direction and migration constraints, see [docs/igor2/](docs/igor2/README.md).

### Self-healing
Pluggable v1 check files in `modules/*/checks/*.sh` emit
`CHECK_RESULT SEVERITY code message` lines. A shared active-owner runner also
evaluates v2 structured checks and projects their results into the existing
Diagnose and Healing flows. The healing engine runs checks
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

The loader supports Module API v1 and the first Module API v2 path. The v1
package and hook contract below remains live for `nextcloud_docker`; `system`
uses a strict v2 manifest and JSON contributions for host knowledge, a
typed memory observer and a structured memory health check while keeping its
other v1 hooks. Inspect the process-local host model with
`bash igor.sh --model facts`, `--model observers`, `--model health` or
`--model summary`; explicit
`--model refresh host.memory` reads the host. New v2 packages require
explicit enablement. See [Module API v2](docs/igor2/MODULE_API.md).

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

### Configuration ownership

The bounded Configuration Service owns validated desired values for
`ai.verbose`; [its contract](docs/igor2/CONFIGURATION.md) distinguishes desired
configuration, resolved input and observed runtime state. Existing verbose
commands submit changes through the backend capability/approval boundary.
Read-only inspection does not migrate files; an explicit write performs the
single-key cutover. Other settings retain the legacy loading rules below.

The service uses private installation-local storage and readable export/recovery.
Secret material remains separate; no module, Nextcloud, secret or host-threshold
configuration migrates in this foundation.

### Legacy two-layer layout

Unmigrated configuration uses two legacy file groups:

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
| `mailcmd.env` | Legacy mail-control template (current `core/mailcmd/` implementation is unavailable) |
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

Configure in `config/variables/ai.env`: `provider=`, `model=`, `ai_mode=`.
An existing `executive_mode=true` setting migrates to Executive, and `false`
migrates to Assist. New settings use the canonical `ai_mode` value.

To replace a key inside Igor, open **AI Assistant → API KEY**, or select a
provider in **SETTINGS**. Key entry is visible so you can check your paste;
Enter without a key keeps the existing value. Igor validates replacements,
saves them in `secrets/<provider>.key` with mode `600`, and updates the active
session immediately. Saved `config/variables/ai_settings.env` preferences take
precedence over `ai.env` when opening chat for unmigrated settings. After
`ai.verbose` cutover, verbosity comes from Configuration Service rather than
these files; saving other preferences no longer writes a competing verbose key.

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
| Linux with systemd | Debian-family is the primary current baseline. Arch-aware distro/package paths exist; Igor 2 will make Debian and Arch explicitly tested targets. |
| Docker + Compose plugin | Required by `nextcloud_docker` module only |
| tmux *(optional)* | Split-pane AI panel, fzf popup menus |
| fzf *(optional)* | Enhanced menus — plain text menus work without it |
| bats *(optional)* | Running the test suite |

Igor was developed on a **Raspberry Pi 3 (1 GB RAM)**. It is designed for Linux with Bash 4.2+, but broad distro compatibility is not yet a tested guarantee. The `system` module supports Pi-specific hardware readings
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
    ├── module_creation.md     Current Module API v1 guide
    ├── module_lifecycle.md    Current activation/runtime semantics
    ├── igor2/                 Target architecture + migration authority
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
