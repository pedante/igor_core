# config/variables/

**Generic settings live here. These files are tracked by git — no personal data.**

Everything in this directory is safe to commit. It contains defaults and
preferences only. Site-specific values (domain, username, paths, passwords)
all belong in `secrets/`.

## Files

| File | Purpose |
|------|---------|
| `igor.env` | Global defaults: paths, UID/GID, schedules, UI flags |
| `notifications.env` | SMTP port/TLS/flags — no host, user, or password (those are in `secrets/notifications.env`) |
| `nextcloud.env` | Nextcloud module: ports, container names, upload limits |
| `ai.env` | AI assistant: provider, model, token limits, loop behaviour |
| `system.env` | System module: CPU/RAM/disk thresholds |

## What does NOT belong here

| Data | Where it goes |
|------|--------------|
| Your domain, hostname | `secrets/site.env` |
| Your Linux username (`NC_USER_NAME`) | `secrets/site.env` |
| Mount paths specific to your machine | `secrets/site.env` |
| SMTP host, user, password | `secrets/notifications.env` |
| DB + Nextcloud admin passwords | `secrets/db.env` |
| Legacy IMAP/SMTP mail-control credentials | `secrets/mailcmd.env` (template retained; current `core/mailcmd/` implementation is unavailable) |
| API keys | `secrets/anthropic.key`, `secrets/openrouter.key` |

## Rules

- **Tracked by git.** Run `git diff config/variables/` to see what you changed.
- **No personal data.** If a value identifies you or your machine, it belongs in `secrets/`.
- **Sensible defaults are already set.** You only need to edit what differs.
