# Igor — I Guard. Observe. Repair.

[![Version](https://img.shields.io/badge/version-1.0.0-blue)](https://github.com/yourusername/igor/releases)
[![License](https://img.shields.io/badge/license-GPLv3-green)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-Bash%204.2%2B-yellow)]()
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)]()

**A modular Bash platform that runs, monitors, and repairs self-hosted services —
with an AI assistant that can actually fix things.**

> Built on a Raspberry Pi 3. Operates a Nextcloud instance reliably since the
> alternative was waking up at 3am.

---

## What it does

```
 You: "my files aren't showing up"
Igor: Checking... file index is stale. Run occ files:scan? [y/N]
 You: y
Igor: Scanning... done. 1,847 files indexed. Files are visible.
```

Igor gives you a **TUI menu** for every operation, a **self-healing engine** that
watches your services around the clock, and an **AI assistant** that has full
context of your running system — and can act on it safely.

---

## Core features

**AI assistant with safety gates**
- Chat with Claude, OpenRouter models, or a local Ollama instance
- Three-tier command classification: `READ` runs silently, `CHANGE` asks you, `DESTROY` warns loudly
- Secrets scrubbed before leaving your machine — passwords never reach the API; domain, IP, hostname replaced with `[IGOR:DOMAIN]` tokens
- Modules inject their own knowledge, live state, and tool definitions into every session
- AI can call registered module functions directly (`scan_files`, `flush_redis`, `fix_permissions`, …) — not arbitrary shell, only what the module explicitly declared safe

**Self-healing**
- Pluggable check files run on a schedule
- Health score 0–100 with stale-alert suppression
- Fires notifications and logs patterns on CRITICAL/FAIL

**GPG-secured email control**
- IMAP poller reads commands from your inbox
- Messages must be both **encrypted and signed** — unsigned messages are silently dropped
- Send `status`, `restart`, `diagnose` from anywhere, even when you can't SSH in

**6-phase diagnostic engine**
- env → system → storage → container → cross-container → app
- Auto-fix catalogue with recheck loop
- Saves full reports to `data/reports/`

**Backup / restore**
- Full snapshots with per-module hooks
- Auto-rotation, action journal, AI-driven rollback

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                      igor.sh                        │
│                   (entry point)                     │
└──────────┬──────────────────────────────────────────┘
           │ loads
    ┌──────▼──────────────────────────────────────┐
    │              core/  (platform)              │
    │  ai/  heal/  diagnose/  mailcmd/  notify/   │
    │  recovery/  extras/  tunnel/  lib/          │
    └──────┬──────────────────────────────────────┘
           │ hook registry
    ┌──────▼──────────────────────────────────────┐
    │            modules/  (domain logic)         │
    │  nextcloud_docker/        system/           │
    │  (your_module/)      (add your own)         │
    └─────────────────────────────────────────────┘
```

The core knows nothing about Nextcloud. Modules plug in via a hook registry —
`health`, `ai_context`, `ai_knowledge`, `backup`, `notify_events`, and 15 more.
Add a module without touching a line of core code.

---

## Quick start

```bash
git clone https://github.com/yourusername/igor.git && cd igor

# Fill in your credentials
cd secrets/
cp site.env.example site.env && cp db.env.example db.env
cp notifications.env.example notifications.env
chmod 600 *.env
# edit each file

# Add an AI key (Anthropic or OpenRouter)
echo "sk-ant-..." > anthropic.key && chmod 600 anthropic.key

cd .. && bash igor.sh
```

First time with Nextcloud: `S. SETUP & INSTALL → 0 WIZARD`

---

## Secrets — nothing personal ever touches git

Igor splits config into two layers:

| Layer | Location | In git | Contains |
|-------|----------|--------|---------|
| Variables | `config/variables/` | yes | Generic defaults — ports, flags, thresholds |
| Secrets | `secrets/` | **never** | Domain, username, paths, every password and key |

`secrets/` is gitignored. `chmod 600` required on all `.env` files — Igor warns
at startup if permissions are wrong. The AI scrubs secrets from context before
any external API call.

---

## Writing a module

```bash
# 1. Create the directory
mkdir -p modules/my_service/{checks,defaults}

# 2. Write module.conf
cat > modules/my_service/module.conf << 'EOF'
[module]
name=my_service
version=1.0.0
description=Manages my service
EOF

# 3. Write module.sh with __register()
```

```bash
my_service__register() {
    igor_register_hook "health"       "my_service__health"
    igor_register_hook "ai_context"   "my_service__ai_context"
    igor_register_hook "ai_knowledge" "my_service__ai_knowledge"
    igor_register_hook "backup"       "my_service__backup"
}

my_service__health() {
    systemctl is-active my_service &>/dev/null \
        && echo "ok:running" \
        || echo "fail:service down"
}
```

See **[docs/module_creation.md](docs/module_creation.md)** for the complete guide
covering all 22 hook points, health check plugins, AI injection, capability catalog,
and config integration.

---

## Requirements

| | |
|-|-|
| Bash 4.2+ | associative arrays |
| Python 3.6+ | JSON/API only, no logic |
| curl | health probes + API calls |
| Linux (any) | Raspberry Pi OS, Ubuntu, Debian, Arch, … |
| Docker *(module)* | only needed for `nextcloud_docker` |
| tmux + fzf *(optional)* | enhanced TUI — plain menus work without |

---

## Docs

| | |
|-|-|
| [docs/module_creation.md](docs/module_creation.md) | How to write a module — every hook point |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | What changed in each release |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | How to contribute |
| [README.md](README.md) | Full operational reference |

---

## License

[GNU General Public License v3.0](LICENSE)
