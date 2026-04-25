# secrets/

**Your personal data and credentials live here. This directory is never committed to git.**

Everything in this directory is gitignored. Back it up separately — if you lose
it, you lose your credentials and site configuration.

## Files

| File | Contents | Required by |
|------|----------|-------------|
| `site.env` | Site identity: `DOMAIN`, `NC_USER_NAME`, `INSTALL_DIR`, `HD_MOUNT` | all modules |
| `db.env` | PostgreSQL + Nextcloud admin credentials | nextcloud_docker |
| `notifications.env` | SMTP host/user/password, `NOTIFY_FROM`, `NOTIFY_TO`, event toggles | notify subsystem |
| `mailcmd.env` | Full mailcmd config: IMAP/SMTP hosts, users, passwords, GPG key ID | mailcmd |
| `onlyoffice.env` | `JWT_SECRET` shared between Nextcloud and OnlyOffice | nextcloud_docker (`--profile extra`) |
| `anthropic.key` | Anthropic API key (single line: `sk-ant-...`) | AI assistant |
| `openrouter.key` | OpenRouter API key (single line: `sk-or-...`) | AI assistant (OpenRouter) |
| `openai.key` | OpenAI API key (single line: `sk-...`) | AI assistant (optional) |
| `gpg/` | GPG keyring for email command authentication | mailcmd |

## What goes here vs config/variables/

`config/variables/` holds generic defaults that are the same for everyone —
ports, thresholds, flags. `secrets/` holds everything that identifies you or
your machine:

- Your domain name
- Your Linux username
- Your mount paths
- Any password or API key
- Any email address

## Rules

- **`chmod 600` required** on all `.env` files. Igor warns at startup if permissions are wrong.
- **Never put personal data in `config/variables/`.** Those files are tracked by git.
- **`.key` files** contain a single API key string and nothing else.
- If a required file is missing, the module loads in degraded mode and Igor
  prompts: run `S. SETUP & INSTALL → 0 WIZARD` to configure, or create the file manually.

## First-time setup

```bash
cd secrets/

cp site.env.example          site.env
cp db.env.example            db.env
cp notifications.env.example notifications.env
cp mailcmd.env.example       mailcmd.env
cp onlyoffice.env.example    onlyoffice.env   # only if using OnlyOffice

chmod 600 *.env
# Edit each file and fill in your real values
```

Or run the install wizard:
```bash
bash igor.sh   # → S. SETUP & INSTALL → 0 WIZARD
```
