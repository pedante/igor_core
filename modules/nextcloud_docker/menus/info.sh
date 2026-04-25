#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/info.sh
#  System information module.
#
#  This module handles:
#    • Live status display
#    • Architecture information
#    • File locations
# ==============================================================================

# ── Module helpers (prefixed with _mod_info_) ─────────────────────────────

_mod_info_live_status() {
    step "Live system status"

    # Docker containers
    info "Docker containers:"
    docker compose ps

    # Resource usage
    echo ""
    info "Resource usage:"
    echo "Memory:"
    free -h

    echo "Disk:"
    df -h | grep -v "tmpfs\|udev\|loop"

    # CPU load
    echo "CPU load:"
    uptime

    pause
}

_mod_info_architecture() {
    step "System architecture"

    echo "Stack Architecture:"
    echo ""
    echo "  Internet"
    echo "     │"
    echo "  Cloudflare Tunnel (cloudflared -- systemd service on host)"
    echo "     │  HTTPS only -- no ports exposed to internet"
    echo "     ▼"
    echo "  nginx  :8080  (web container -- Alpine-based)"
    echo "     │  Reverse proxy + static file serving"
    echo "     ▼"
    echo "  php-fpm  :9000  (app container -- custom NC image)"
    echo "     │  Nextcloud PHP application"
    echo "     ├──► PostgreSQL  :5432  (db container)"
    echo "     │    Primary database"
    echo "     └──► Redis  :6379  (redis container)"
    echo "          Session cache + file locking"
    echo ""
    echo "  cron  (separate container -- runs occ cron every 5 min)"
    echo ""
    echo "  [Optional]"
    echo "  OnlyOffice Document Server  :8081  (onlyoffice container)"
    echo ""

    echo "Docker Volumes:"
    echo "  • nextcloud_data -- Nextcloud files, config.php, apps"
    echo "  • nextcloud_db -- PostgreSQL data"
    echo ""
    echo "Bind Mounts:"
    echo "  • /mnt/nextclouddata/next -- User data (external HD)"
    echo "  • ./web/nginx.conf -- nginx config (generated, read-only)"
    echo ""

    pause
}

_mod_info_file_locations() {
    step "File locations"

    echo "Project files:"
    echo "  • igor.sh -- Main entry point"
    echo "  • VERSION -- Version string"
    echo "  • LICENSE -- GPL v3 license"
    echo "  • README.md -- User documentation"
    echo "  • CHANGELOG.md -- Version history"
    echo "  • CONTRIBUTING.md -- Contribution guidelines"
    echo ""
    local _cfg="${NEXUS_CONFIG:-\$IGOR_DIR}"
    echo "Configuration:"
    echo "  • config/defaults.env -- Default configuration values"
    echo "  • ${_cfg}/config.env -- User overrides"
    echo "  • ${_cfg}/db.env -- Database and NC credentials"
    echo "  • ${_cfg}/ai_settings.env -- AI provider, model, temperature"
    echo ""
    echo "Documentation:"
    echo "  • docs/ARCHITECTURE.md -- System architecture"
    echo "  • docs/adding-a-provider.md -- Provider implementation guide"
    echo "  • docs/adding-a-check.md -- Health check implementation guide"
    echo ""
    echo "Modules:"
    echo "  • modules/ -- Menu-specific modules (lazy-loaded)"
    echo "  • lib/ -- Core library functions (always sourced)"
    echo ""
    echo "Generated files:"
    echo "  • ./web/nginx.conf -- Generated nginx configuration"
    echo "  • /data/reports/ -- Health check reports"
    echo "  • ${_cfg}/ -- All runtime config and state"
    echo ""

    pause
}

# ── Getting Started guide ────────────────────────────────────────────────────
_mod_info_getting_started() {
    while true; do
        local _gs_opt
        _gs_opt=$(igor_fzf_pick "Getting Started — Overview" \
            "1:PREREQUISITES:Linux host + Docker installed" \
            "2:STORAGE SETUP:Mount point and data directory" \
            "3:CLOUDFLARE TUNNEL:Create tunnel and copy token" \
            "4:INSTALL WIZARD:Run the first-time setup wizard" \
            "5:FIRST SCAN:Index files after install" \
            "6:VERIFY:Read the STATUS dashboard" \
            "7:DAY-TO-DAY:Maintenance, restarts, and routine tasks" \
            "8:RECOVERY:When things go wrong" \
            "b:BACK:Return to Info menu")
        case $? in 1) return ;; 2)
        header
        echo -e "  ${YEL}${BOLD}Getting Started — Igor + Nextcloud${NC}"
        echo "   1) Prerequisites"
        echo "   2) Storage setup"
        echo "   3) Cloudflare tunnel"
        echo "   4) Install wizard"
        echo "   5) First scan"
        echo "   6) Verify"
        echo "   7) Day-to-day"
        echo "   8) Recovery"
        echo "   b) Back"
        read -rp "  Select: " _gs_opt ;; esac
        [ "$_gs_opt" = "_" ] && continue
        case $_gs_opt in
            1)
                header
                cat << 'EOF'

  STEP 1 — PREREQUISITES
  ────────────────────────────────────────────────────────────────
  Supported Linux distributions:
    • Debian / Ubuntu (and derivatives — Raspberry Pi OS, etc.)
    • Arch Linux (and derivatives — Manjaro, EndeavourOS, etc.)
    • Any distro with bash 4+, curl, and a working Docker Engine

  Install Docker:
    Debian/Ubuntu:  sudo apt install docker.io docker-compose-plugin
    Arch:           sudo pacman -S docker docker-compose
                    sudo systemctl enable --now docker
                    sudo usermod -aG docker $USER

  Minimum resources:
    RAM:   512 MB (1 GB recommended — less causes OOM on PHP)
    Disk:  8 GB for system + external storage for user data
    CPU:   Any 64-bit or 32-bit ARMv7+ / x86_64 processor

  Verify Docker is running:
    docker ps          ← should return an empty table, not an error

EOF
                pause ;;
            2)
                header
                cat << 'EOF'

  STEP 2 — STORAGE SETUP
  ────────────────────────────────────────────────────────────────
  Igor stores Nextcloud user data on a separate mount point.
  The location is controlled by two variables in your config:

    HD_MOUNT   — where the storage device is mounted
                 default: /mnt/nextclouddata
                 change in: config/variables/igor.env

    NC_DATA    — the Nextcloud data directory (inside HD_MOUNT)
                 default: ${HD_MOUNT}/next
                 change in: config/variables/nextcloud.env

  The storage does NOT need to be a dedicated device. You can
  point HD_MOUNT at any directory that has enough space — an
  external USB drive, an NFS mount, or just a folder on the
  system disk. No formatting required if the filesystem already
  exists (ext4, btrfs, xfs, and ntfs-3g all work).

  Recommended fstab entry (add nofail so a missing drive does
  not prevent boot):
    UUID=xxxx  /mnt/nextclouddata  ext4  defaults,nofail  0  2

  Igor can add this for you: [S] SETUP & INSTALL → STORAGE

EOF
                pause ;;
            3)
                header
                cat << 'EOF'

  STEP 3 — CLOUDFLARE TUNNEL
  ────────────────────────────────────────────────────────────────
  Cloudflare Tunnel gives you HTTPS access to Nextcloud from
  anywhere, without opening any ports on your router.

  How to create a tunnel:
    1. Go to: one.dash.cloudflare.com → Zero Trust → Networks → Tunnels
    2. Click "Create a tunnel" → choose Cloudflared → give it a name
    3. Copy the long tunnel token (starts with "eyJ...")
    4. Back in Igor: [S] SETUP & INSTALL → TUNNEL → paste the token

  Igor will install cloudflared as a systemd service and configure
  it to route your domain to nginx on port 8080.

  If you don't have a Cloudflare account, create one at cloudflare.com
  (free plan is sufficient). Add your domain or use a subdomain of
  a domain you already manage there.

EOF
                pause ;;
            4)
                header
                cat << 'EOF'

  STEP 4 — INSTALL WIZARD
  ────────────────────────────────────────────────────────────────
  Run: [S] SETUP & INSTALL → WIZARD (or press 0 from main menu)

  The wizard will ask for:
    • Database password      (choose something strong, stored in secrets/db.env)
    • Nextcloud admin user   (your login name, e.g. "admin")
    • Nextcloud admin pass   (stored in secrets/db.env, not logged)
    • Your domain            (e.g. cloud.example.com)
    • Data directory         (defaults to NC_DATA, press Enter to accept)

  What the wizard does:
    1. Validates prerequisites (Docker running, storage mounted)
    2. Renders the docker-compose.yml from the template
    3. Builds the custom app container (may take 5-15 min on slow hardware)
    4. Starts all containers
    5. Runs occ installation to configure Nextcloud
    6. Sets up trusted_proxies for Cloudflare

  After the wizard completes, your Nextcloud is live at your domain.

EOF
                pause ;;
            5)
                header
                cat << 'EOF'

  STEP 5 — FIRST SCAN
  ────────────────────────────────────────────────────────────────
  Run: [4] MAINTENANCE → SCAN FILES

  After a fresh install, Nextcloud's file index is empty even
  though the data directory may already contain files (e.g. if
  you migrated from another instance). The scan command tells
  Nextcloud about those files.

  On a Raspberry Pi 3 with a large data directory:
    • Expect 1-5 minutes for the first scan
    • Progress is shown in the Igor output pane
    • The scan runs inside the app container as www-data

  For future scans (after adding files from outside Nextcloud):
    [4] MAINTENANCE → SCAN FILES

EOF
                pause ;;
            6)
                header
                cat << 'EOF'

  STEP 6 — VERIFY
  ────────────────────────────────────────────────────────────────
  Run: [1] STATUS from the main menu

  STATUS shows:
    • Container list and uptime (should see app, web, db, redis, cron)
    • HTTP probe result (should say 200 OK)
    • Cloudflare tunnel state (should say "active")
    • Disk usage on your storage mount

  If STATUS shows anything red or missing:
    → [6] DIAGNOSE runs deeper checks and suggests fixes
    → [A] AI ASSISTANT can diagnose and repair interactively

  You can also open your domain in a browser — if you see the
  Nextcloud login page, setup is complete.

EOF
                pause ;;
            7)
                header
                cat << 'EOF'

  STEP 7 — DAY-TO-DAY USE
  ────────────────────────────────────────────────────────────────
  Routine tasks and when to use each menu:

  [1] STATUS        — check at a glance that everything is healthy
  [2] SERVICES      — start/stop/restart containers, view live logs
  [3] APPS          — install, enable, or disable Nextcloud apps
  [4] MAINTENANCE   — run these periodically:
      • SCAN FILES         after copying files to the data directory
      • DB MAINTENANCE     monthly, keeps PostgreSQL healthy
      • GENERATE PREVIEWS  after bulk file uploads
      • UPGRADE NEXTCLOUD  when a new NC version is available
  [5] CONFIGURE     — change nginx settings, upload limit, admin password
  [6] DIAGNOSE      — when something is wrong and you're not sure why

  Nextcloud cron runs every 5 minutes automatically inside the
  cron container — no host crontab needed.

EOF
                pause ;;
            8)
                header
                cat << 'EOF'

  STEP 8 — RECOVERY
  ────────────────────────────────────────────────────────────────
  When something goes wrong:

  1. First try [6] DIAGNOSE — runs 6 phases of checks and offers fixes
  2. Then try  [A] AI ASSISTANT — describe the problem in plain text
  3. Then try  [R] RECOVERY — journal rollback, config backups, supervised restart

  Common issues and quick fixes:
    "502 Bad Gateway"       → [2] SERVICES → RESTART ALL
    "Maintenance mode"      → [5] CONFIGURE → NC SETTINGS (disable)
    "Database error"        → [6] DIAGNOSE → FULL DIAGNOSTIC
    "Files not showing"     → [4] MAINTENANCE → SCAN FILES
    "Tunnel disconnected"   → [S] SETUP & INSTALL → TUNNEL → restart

  Igor saves diagnostic reports to:
    ${IGOR_DIR}/data/reports/

  If containers won't start after a reboot:
    → The docker-compose.yml may need regeneration
    → [6] DIAGNOSE → FULL DIAGNOSTIC → accepts and runs the fix

EOF
                pause ;;
            q|Q|b|B) return ;;
        esac
    done
}

# ── Igor Internals — what this module plugs into ─────────────────────────────
_mod_info_igor_internals() {
    while true; do
        local _ii_opt
        _ii_opt=$(igor_fzf_pick "Igor Internals — nextcloud_docker hooks" \
            "_:  AI SUBSYSTEM  :" \
            "1:AI CONTEXT:What Igor reads before every AI conversation" \
            "2:AI KNOWLEDGE:Critical rules injected into system prompt" \
            "3:AI PATTERNS:Learned repair patterns from previous sessions" \
            "4:AI TOOLS:What the AI can execute (occ, containers, logs, edits)" \
            "5:AI TIERS:READ / CHANGE / DESTROY approval levels" \
            "_:  HEALING  :" \
            "6:HEALTH CHECKS:4 check plugins wired into the health subsystem" \
            "7:ALERT HOOK:How CRITICAL alerts reach Nextcloud notifications" \
            "8:HEALTH GATE:Fast HTTP probe used by diagnose before starting" \
            "_:  DIAGNOSE  :" \
            "9:DIAGNOSE PHASES:6-phase deep scan including NC app-layer checks" \
            "a:FIX CATALOGUE:Tiered fixes: READ auto-run, CHANGE confirm, DESTROY type YES" \
            "_:  RECOVERY  :" \
            "b:BACKUP HOOK:What gets backed up (compose, nginx, secrets, config)" \
            "c:RESTORE HOOK:How restore picks up volumes and secrets" \
            "d:ROLLBACK:Journal-based rollback for occ, app_enable, nginx edits" \
            "_:  COMMUNICATION  :" \
            "e:MAILCMD:GPG-signed email commands accepted by this module" \
            "f:ALERT NOTIFY:How health alerts reach the user (NC notification)" \
            "g:STATUS LINE:What appears in the Igor header (tunnel + NC state)" \
            "h:CONFIG VALIDATE:Startup checks for required NC environment variables" \
            "B:BACK:Return to Info menu")
        case $? in 1) return ;; 2)
        header
        echo -e "  ${YEL}${BOLD}Igor Internals — nextcloud_docker${NC}"
        echo "   AI: 1) context  2) knowledge  3) patterns  4) tools  5) tiers"
        echo "   Healing: 6) health checks  7) alert hook  8) health gate"
        echo "   Diagnose: 9) phases  a) fix catalogue"
        echo "   Recovery: b) backup  c) restore  d) rollback"
        echo "   Comms: e) mailcmd  f) notify  g) status line  h) config validate"
        echo "   B) Back"
        read -rp "  Select: " _ii_opt ;; esac
        [ "$_ii_opt" = "_" ] && continue
        case $_ii_opt in
            1) header; cat << 'EOF'

  AI CONTEXT  (hook: ai_context → nextcloud_docker__ai_context)
  ────────────────────────────────────────────────────────────────
  Before every AI conversation, Igor gathers live system state and
  injects it into the AI's context window. For this module, that
  includes:
    • docker compose ps output (container states, uptime)
    • occ status (version, maintenance mode, needsDbUpgrade)
    • occ config:system:get trusted_proxies, overwrite.cli.url
    • nginx.conf snippet (location blocks, fastcgi_params)
    • Recent docker compose logs (last 30 lines from app container)
    • Disk usage at HD_MOUNT and NC_DATA
    • Cloudflare tunnel systemd status
    • Redis PING response
    • Active Nextcloud apps (occ app:list --enabled)

  All values are scrubbed before the API call — domain, IPs,
  admin username, and data paths are replaced with [IGOR:*] tokens.

EOF
                pause ;;
            2) header; cat << 'EOF'

  AI KNOWLEDGE  (hook: ai_knowledge → nextcloud_docker__ai_knowledge)
  ────────────────────────────────────────────────────────────────
  A block of critical rules is injected into the AI system prompt
  so the model knows the NC-specific constraints it must follow:

    • Always use: docker compose exec -T -u www-data app php occ
    • Never edit config.php directly — always use occ
    • nginx location / must use rewrite, not try_files
    • .well-known routing issues = nginx problem, not occ
    • trusted_proxies must include all Cloudflare IP ranges
    • Named volumes pi_nextcloud and pi_db must never be deleted
    • The AI menu map (current key → function mapping)
    • Common symptom → check mappings (502, CSRF, Redis errors, etc.)

EOF
                pause ;;
            3) header; cat << 'EOF'

  AI PATTERNS  (hook: ai_patterns → nextcloud_docker__ai_patterns)
  ────────────────────────────────────────────────────────────────
  Igor tracks which repair patterns succeed or fail over time.
  Patterns are stored in:
    ${IGOR_DIR}/data/patterns/nextcloud_docker/

  Each pattern has a CONFIRMED_COUNT and a FAILED_COUNT.
  High-confidence patterns (confirmed ≥ 3, failed = 0) are
  injected into the AI prompt as "KNOWN GOOD FIXES".

  Patterns are written by the healing subsystem when a RESULT:
  STATUS=FIXED is confirmed with evidence, and updated when
  the same fix is retried and fails.

EOF
                pause ;;
            4) header; cat << 'EOF'

  AI TOOLS  (hook: ai_tools → nextcloud_docker__ai_tools)
  ────────────────────────────────────────────────────────────────
  The AI can use these tool tags to take action:

    <occ> command </occ>
        Runs: docker compose exec -T -u www-data app php occ <command>
        Tier: READ for read-only occ, CHANGE for config writes

    <host> command </host>
        Runs a command on the host shell
        Tier: READ for df/uptime/docker ps, CHANGE for restarts

    <container action="restart"> service </container>
        Restarts a named service in the compose stack
        Tier: CHANGE (requires confirmation)

    <read_log target="app" lines="50"> pattern </read_log>
        Tails container logs and greps for a pattern
        Tier: READ (auto-runs)

    <edit_file path="./web/nginx.conf">
      <find>...</find><replace>...</replace>
    </edit_file>
        Edits a file on the host
        Tier: CHANGE for nginx.conf, DESTROY for secrets

EOF
                pause ;;
            5) header; cat << 'EOF'

  AI TIERS  (hook: ai_tiers → nextcloud_docker__ai_tiers)
  ────────────────────────────────────────────────────────────────
  Every tool call the AI makes is gated by an approval tier:

    READ     — runs automatically, no prompt
               Examples: docker ps, occ status, log reads, df

    CHANGE   — shows the command, requires "y" to confirm
               (skipped in executive mode — set in AI menu)
               Examples: container restart, occ config:set, nginx edit

    DESTROY  — always requires typing "YES" regardless of mode
               Examples: docker compose down, volume deletion,
               occ user:delete, rm -rf any data path

  The tier for each occ command is determined by the command verb:
    status/list/config:get/check  → READ
    config:set/app:enable/repair  → CHANGE
    maintenance:mode/user:delete  → DESTROY (context-dependent)

EOF
                pause ;;
            6) header; cat << 'EOF'

  HEALTH CHECKS  (hook: health → nextcloud_docker__health)
  ────────────────────────────────────────────────────────────────
  The healing subsystem runs health_check_full() periodically
  (default: every 5 minutes if a worker daemon is running).

  This module registers checks in:
    core/healing/checks/containers.sh  — are all 5 containers running?
    core/healing/checks/nextcloud.sh   — HTTP probe + occ status
    core/healing/checks/caching.sh     — Redis PING + APCu enabled
    core/healing/checks/network.sh     — DNS resolution + tunnel state

  Each check emits: OK / WARN / FAIL with a short message.
  The overall score is: 100 - (FAIL×30 + WARN×10).

  On CRITICAL (score < 40), the alert hook fires a Nextcloud
  notification to the admin user.

EOF
                pause ;;
            7) header; cat << 'EOF'

  ALERT HOOK  (hook: alert_hook → _nc_alert_hook)
  ────────────────────────────────────────────────────────────────
  When a CRITICAL or FAIL alert is generated, Igor calls the
  module's alert hook to notify the user via Nextcloud itself:

    docker compose exec -T -u www-data app php occ \
      notification:generate <admin_user> "IGOR Health Alert" \
      --long-message "[CRITICAL] code: message"

  This means you'll see Igor's alerts in the Nextcloud bell icon
  in the web UI and in the Nextcloud mobile app.

  Alerts are also logged to:
    ${IGOR_DIR}/data/alerts/pending.log

  Stale alerts (> 4 hours old) are suppressed to avoid noise.

EOF
                pause ;;
            8) header; cat << 'EOF'

  HEALTH GATE  (hook: health_gate → _nc_health_gate)
  ────────────────────────────────────────────────────────────────
  Before the diagnose subsystem runs deep checks, it performs a
  fast "gate check" to see if the application is responding.

  For Nextcloud, the gate check is:
    curl -sf http://localhost:${NEXTCLOUD_HTTP_PORT:-8080}/status.php

  Returns 0 (pass) if HTTP 200, 1 (fail) otherwise.

  If the gate fails, diagnose skips app-layer checks and focuses
  on container and network phases instead — no point checking
  occ if the web server isn't responding.

EOF
                pause ;;
            9) header; cat << 'EOF'

  DIAGNOSE PHASES  (hook: app_diagnose → nextcloud_docker__app_diagnose)
  ────────────────────────────────────────────────────────────────
  Igor Diagnose runs 6 phases in sequence:

    Phase 1  ENV        — required variables, file permissions, secrets present
    Phase 2  SYSTEM     — disk space, memory, swap, load average
    Phase 3  STORAGE    — HD_MOUNT and NC_DATA mounted and writable
    Phase 4  CONTAINERS — each service running, image versions, restart counts
    Phase 5  APP        — NC-specific: occ status, trusted_proxies, permissions,
                          maintenance mode, Redis, database integrity
                          (this phase is provided by this module via app_diagnose hook)
    Phase 6  CROSS      — inter-container connectivity (app→db, app→redis, web→app)

  Each finding is classified as OK / WARN / FAIL with a fix ID.
  Fix IDs map to the fix catalogue (phase 5 / CHANGE tier).

EOF
                pause ;;
            a) header; cat << 'EOF'

  FIX CATALOGUE  (diagnose/fixes.sh + module-contributed fixes)
  ────────────────────────────────────────────────────────────────
  After diagnose phases complete, found issues are presented with
  fix options. Each fix has a tier:

    READ      — auto-runs (e.g. "check occ status again")
    CHANGE    — shown with command, requires "y" to run
    DESTROY   — requires typing "YES"

  Example NC-specific fixes in the catalogue:

    nc_maintenance_off    → occ maintenance:mode --off        (CHANGE)
    nc_trusted_proxies    → occ config:system:set ...         (CHANGE)
    nc_repair             → occ maintenance:repair            (CHANGE)
    nc_permissions        → chown/chmod on NC_DATA            (CHANGE)
    nc_redis_restart      → container restart redis           (CHANGE)
    nc_db_integrity       → occ db:add-missing-indices        (CHANGE)

  After applying a fix, diagnose rechecks the affected phase.
  If the fix resolves the issue, RESULT: STATUS=FIXED is logged.

EOF
                pause ;;
            b) header; cat << 'EOF'

  BACKUP HOOK  (hook: backup → nextcloud_docker__backup)
  ────────────────────────────────────────────────────────────────
  Igor's scheduled backup (--backup config) calls all registered
  backup hooks. This module backs up:

    config/stacks/nextcloud/docker-compose.yml
    config/stacks/nextcloud/docker-compose.override.yml (if exists)
    config/stacks/nextcloud/nginx.conf
    secrets/db.env
    secrets/nextcloud.env (if exists)
    config/variables/nextcloud.env

  Backups are timestamped and stored in:
    ${IGOR_DIR}/data/backups/nextcloud_docker/

  The backup hook does NOT back up Nextcloud's named volumes
  (pi_nextcloud, pi_db) — those require a separate full backup
  via [R] RECOVERY → FULL BACKUP.

EOF
                pause ;;
            c) header; cat << 'EOF'

  RESTORE HOOK  (hook: restore → nextcloud_docker__restore)
  ────────────────────────────────────────────────────────────────
  [R] RECOVERY → RESTORE calls registered restore hooks.

  This module's restore hook:
    1. Lists available backup timestamps for nextcloud_docker
    2. Prompts to select one
    3. Restores compose files, nginx.conf, and env files
    4. Does NOT restore volumes (data is on the bind mount, not in volumes)

  For a full disaster recovery (new machine):
    1. Install Igor and run WIZARD → installs from your config files
    2. Stop stack, restore volumes from external backup
    3. Start stack, run MAINTENANCE → SCAN FILES

EOF
                pause ;;
            d) header; cat << 'EOF'

  ROLLBACK  (hook: rollback_handler → _nc_rollback_dispatch)
  ────────────────────────────────────────────────────────────────
  Igor keeps a journal of actions taken by the AI and diagnose.
  If a CHANGE-tier action causes a problem, [R] RECOVERY → ROLLBACK
  walks you through undoing it.

  This module handles rollback for:
    app_enable    → occ app:disable <appid>
    app_disable   → occ app:enable <appid>
    nginx_edit    → restore nginx.conf from backup
    occ_set       → occ config:system:delete <key>

  Rollback is not available for:
    DESTROY-tier actions (volume deletion, user deletion)
    Actions with no inverse (e.g. maintenance:repair)

EOF
                pause ;;
            e) header; cat << 'EOF'

  MAILCMD  (hook: mailcmd → nextcloud_docker__mailcmd)
  ────────────────────────────────────────────────────────────────
  Igor can receive commands via GPG-signed email.
  The mailcmd hook registers which verbs this module accepts:

    nc status          → runs nextcloud_docker__health and occ status
    nc maintenance on  → enables maintenance mode (CHANGE tier)
    nc maintenance off → disables maintenance mode (CHANGE tier)
    nc scan            → runs occ files:scan --all (CHANGE tier)
    nc restart         → restarts the compose stack (CHANGE tier)

  Messages must be PGP-encrypted AND signed by the registered
  operator key. Unsigned or wrongly-signed messages are discarded.

  Configure in: [C] COMMAND MAIL from the main menu.

EOF
                pause ;;
            f) header; cat << 'EOF'

  ALERT NOTIFY  (via _nc_alert_hook)
  ────────────────────────────────────────────────────────────────
  When Igor's health score drops below the CRITICAL threshold,
  the alert hook fires a Nextcloud notification to the admin user.

  The notification appears in:
    • The bell icon in Nextcloud web UI
    • The Nextcloud Talk mobile app (if configured)
    • FairEmail / other email clients if NC email is set up

  The notification text format:
    [CRITICAL] <code>: <message>
    e.g. [CRITICAL] containers_down: app,web not running

  Notifications are rate-limited: the same alert code will not
  fire again for 4 hours, to avoid flooding.

EOF
                pause ;;
            g) header; cat << 'EOF'

  STATUS LINE  (hook: status_line → nextcloud_docker__status_line)
  ────────────────────────────────────────────────────────────────
  The Igor header (shown at the top of every menu) includes a
  status line contributed by this module. It shows:

    NC: <container_status>  Tunnel: <cloudflared_status>

  Examples:
    NC: running (5/5)  Tunnel: active
    NC: DEGRADED (3/5)  Tunnel: active
    NC: down  Tunnel: failed

  The status line uses the same fast checks as the menu header:
  no occ calls, just docker ps and systemctl is-active.

EOF
                pause ;;
            h) header; cat << 'EOF'

  CONFIG VALIDATE  (hook: config_validate → _nc_validate_config)
  ────────────────────────────────────────────────────────────────
  At Igor startup, after all modules are loaded, config_validate
  hooks are called to warn about missing required variables.

  This module checks for:
    NEXTCLOUD_ADMIN_USER       — NC admin login name
    NEXTCLOUD_ADMIN_PASSWORD   — NC admin password (from secrets)
    NEXTCLOUD_TRUSTED_DOMAINS  — at least one domain set

  If any are missing, a warning is printed to stderr at startup.
  Igor continues loading — missing config is not fatal, but the
  stack will likely fail if trusted domains are not set.

  Set these in: config/variables/nextcloud.env (non-secret)
            or: secrets/db.env (credentials)

EOF
                pause ;;
            b|B|q|Q) return ;;
        esac
    done
}

# ── Public entry point ───────────────────────────────────────────────────────────
menu_info() {
    while true; do
        # Right pane: system overview
        if declare -f igor_right_render &>/dev/null; then
            local _inf_ver _inf_mem _inf_disk _inf_uptime
            _inf_ver=$(docker compose -f "${IGOR_DIR}/docker-compose.yml" \
                exec -T -u www-data app php occ status --output=json 2>/dev/null \
                | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('versionstring','?'))" \
                2>/dev/null || echo "?")
            _inf_mem=$(free -h 2>/dev/null | awk 'NR==2{print $3"/"$2}' || echo "?")
            _inf_disk=$(df -h "${NC_DATA:-/mnt}" 2>/dev/null | awk 'NR==2{print $3"/"$2" ("$5")"}' || echo "?")
            _inf_uptime=$(uptime -p 2>/dev/null || echo "?")
            igor_right_render "System Info" \
                "NC version" "${_inf_ver}" \
                "Memory"     "${_inf_mem}" \
                "Data disk"  "${_inf_disk}" \
                "Uptime"     "${_inf_uptime}" \
                "hint"       "[1] live status  [2] architecture"
        fi
        local opt
        opt=$(igor_fzf_pick "7: Info & Status" \
            "1:LIVE STATUS:Container health and uptime" \
            "2:ARCHITECTURE:Stack diagram and design overview" \
            "3:FILE LOCATIONS:Config, logs, data paths" \
            "4:IPC STATUS:Worker and main PID details" \
            "5:GETTING STARTED:Step-by-step guide for new users" \
            "6:IGOR INTERNALS:What's hooked into Igor — AI, healing, diagnose, recovery" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "7: Info & Status"
        echo -e "  ${YEL}${BOLD}[7] System Information${NC}"
        echo "   1) Live status"
        echo "   2) Architecture overview"
        echo "   3) File locations"
        echo "   4) IPC session status (worker / main PID)"
        echo "   5) Getting started guide"
        echo "   6) Igor internals"
        echo "   b) Back"
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case $opt in
            1)
                _mod_info_live_status ;;
            2)
                _mod_info_architecture ;;
            3)
                _mod_info_file_locations ;;
            4)
source "/data/runtime/state.sh"  2>/dev/null || true
source "/data/runtime/ipc.sh"    2>/dev/null || true
                source "${IGOR_DIR}/modules/status.sh" 2>/dev/null || true
                if declare -f show_overall_status &>/dev/null; then
                    show_overall_status
                else
                    warn "Status module not available."
                fi
                pause
                ;;
            5)
                _mod_info_getting_started ;;
            6)
                _mod_info_igor_internals ;;
            q|Q|b|B) return ;;
        esac
    done
}
