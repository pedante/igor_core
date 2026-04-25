# Module: nextcloud_docker

Manages a self-hosted Nextcloud stack running on Docker Compose.

Stack topology:
- **nginx** — reverse proxy (Alpine, port 8080)
- **app** — Nextcloud php-fpm (UID 1004)
- **db** — PostgreSQL
- **redis** — session cache + file locking
- **cron** — `occ` cron every 5 min
- **cloudflared** — Cloudflare Tunnel (systemd service, external to Docker)
- **onlyoffice** — optional, `--profile extra`, disabled by default (~1.5 GB RAM)

Template stack files live in `defaults/`. The user's running copies live in
`config/stacks/nextcloud/` (gitignored).

---

## Registered hooks

| Hook | Function | Notes |
|------|----------|-------|
| `health` | `nextcloud_docker__health` | Container count, HTTP probe, maintenance flag |
| `status_line` | `nextcloud_docker__status_line` | Tunnel + Nextcloud rows in header |
| `menu_header` | `nextcloud_docker__menu_header` | One-line status for main menu |
| `diagnose` | `nextcloud_docker__diagnose` | Stack dir, secrets, containers, data dir |
| `app_diagnose` | `nextcloud_docker__app_diagnose` | Phase 5 occ checks (in-process) |
| `health_gate` | `_nc_health_gate` | HTTP 200 from /status.php? |
| `role_check_app` | `_nc_check_role_app` | occ status, bg jobs, config, indices |
| `alert_hook` | `_nc_alert_hook` | NC in-app notification on CRITICAL/FAIL |
| `ai_context` | `nextcloud_docker__ai_context` | occ status, key config, tunnel, NC log |
| `ai_knowledge` | `nextcloud_docker__ai_knowledge` | Architecture, nginx rules, decision tree |
| `ai_tiers` | `nextcloud_docker__ai_tiers` | Tool safety classifications |
| `ai_tools` | `nextcloud_docker__ai_tools` | occ, container, run_igor_action tool defs |
| `ai_patterns` | `nextcloud_docker__ai_patterns` | Known repair patterns |
| `ai_capabilities` | `nextcloud_docker__ai_capabilities` | 12 callable actions for run_igor_action |
| `backup` | `nextcloud_docker__backup` | occ config export + DB dump |
| `restore` | `nextcloud_docker__restore` | DB restore + occ config import |
| `recovery` | `nextcloud_docker__recovery` | Recovery procedures |
| `notify_events` | `nextcloud_docker__notify_events` | 7 event declarations |
| `mailcmd` | `nextcloud_docker__mailcmd` | Email command verbs |
| `config_validate` | `_nc_validate_config` | Warn on missing NC credentials |
| `rollback_handler` | `_nc_rollback_dispatch` | Undo app_enable/disable/occ actions |

---

## Files

| File | Purpose |
|------|---------|
| `module.sh` | Hook implementations, main menu dispatch |
| `module.conf` | Module manifest, dependencies, secrets declaration |
| `services.sh` | Container start/stop/restart/logs |
| `maintenance.sh` | occ commands: scan, repair, previews, cache flush |
| `network.sh` | Health checks, nginx config, trusted proxies |
| `configure.sh` | NC settings, upload limits, maintenance mode |
| `apps.sh` | Nextcloud app install/enable/disable |
| `install.sh` | Multi-step installation wizard |
| `storage.sh` | External HD mount, ownership, fstab |
| `tunnel_integration.sh` | Cloudflare Tunnel + Nextcloud URL config |
| `info.sh` | Status views, logs, occ info commands |
| `recovery.sh` | Backup/restore, journal, rollback |
| `checks/containers.sh` | Healing: container states, disk usage |
| `checks/network.sh` | Healing: HTTP routing, nginx |
| `checks/nextcloud.sh` | Healing: occ check, maintenance, cron |
| `defaults/` | Template stack files (docker-compose.yml, nginx.conf, Dockerfile, …) |

---

## Configuration

**Generic defaults** (`config/variables/nextcloud.env`):
- `NEXTCLOUD_HTTP_PORT` — nginx listen port (default: 8080)
- `NC_UID` / `NC_GID` — file ownership for the app container (default: 1004)

**Site-specific** (`secrets/site.env`, gitignored):
- `HD_MOUNT` — external data drive mount point
- `NC_DATA` — Nextcloud user data directory
- `DOMAIN` — public domain via Cloudflare Tunnel

**Credentials** (`secrets/db.env`, gitignored):
- `POSTGRES_PASSWORD`, `POSTGRES_USER`, `POSTGRES_DB`
- `NEXTCLOUD_ADMIN_USER`, `NEXTCLOUD_ADMIN_PASSWORD`
- `NEXTCLOUD_TRUSTED_DOMAINS`

---

## Dependencies

- `system` module — optional (service management integration)
- `docker` + Compose plugin — required
- `curl` — required
