# Igor Module Development Guide

> **Current contract (Module API v1).** This guide documents the v1 compatibility implementation. Igor 2's v2 contract and the first migrated `system` slice are documented separately in [igor2/MODULE_API.md](igor2/MODULE_API.md). New v2 packages use strict `module.conf` metadata and explicit JSON contract files; do not extend v1 with speculative hooks to imitate v2.

## Table of Contents

1. [Overview](#overview)
2. [Module Directory Layout](#module-directory-layout)
3. [module.conf — Manifest File](#moduleconf--manifest-file)
4. [module.sh — The Module Shell Script](#modulesh--the-module-shell-script)
5. [The `__register()` Function](#the-register-function)
6. [Lifecycle Hook Functions](#lifecycle-hook-functions)
7. [All Registered Hooks — Reference](#all-registered-hooks--reference)
   - [health](#hook-health)
   - [status_line](#hook-status_line)
   - [menu_header](#hook-menu_header)
   - [diagnose](#hook-diagnose)
   - [app_diagnose](#hook-app_diagnose)
   - [health_gate](#hook-health_gate)
   - [role_check_app](#hook-role_check_app)
   - [alert_hook](#hook-alert_hook)
   - [ai_context](#hook-ai_context)
   - [ai_knowledge](#hook-ai_knowledge)
   - [ai_tiers](#hook-ai_tiers)
   - [ai_tools](#hook-ai_tools)
   - [ai_patterns](#hook-ai_patterns)
   - [ai_capabilities](#hook-ai_capabilities)
   - [backup](#hook-backup)
   - [restore](#hook-restore)
   - [recovery](#hook-recovery)
   - [rollback_handler](#hook-rollback_handler)
   - [config_validate](#hook-config_validate)
   - [notify](#hook-notify)
   - [notify_events](#hook-notify_events)
   - [mailcmd](#hook-mailcmd)
8. [Check Plugins — Healing Subsystem](#check-plugins--healing-subsystem)
9. [Configuration System — Variables, Secrets, Defaults](#configuration-system--variables-secrets-defaults)
10. [Menu Registration](#menu-registration)
11. [Path Resolution](#path-resolution)
12. [Module Loader API](#module-loader-api)
13. [Function Naming Conventions](#function-naming-conventions)
14. [Complete Minimal Module Example](#complete-minimal-module-example)

---

## Overview

Igor v1 modules are self-contained Bash packages that extend the core platform
with domain-specific functionality. The module loader
(`core/lib/module_loader.sh`) discovers, validates, and loads modules at
startup. Module API v2 packages use the same loader with strict metadata and
explicit contribution files; see the v2 contract for that package shape.

Discovery means installed, not active. `config/modules.conf` contains data-only
`name=enabled` or `name=disabled` entries; omitted v1 modules remain enabled for
compatibility. `bash igor.sh --enable NAME` and `--disable NAME` write this policy
for subsequent Igor processes. Restart existing sessions after changing policy.
An enabled module becomes active only after dependencies and registration succeed.
See [module lifecycle](module_lifecycle.md) for ownership, AI trust, and removal
semantics.

**V1 load sequence:**

1. `igor_discover_modules` — scan `modules/*/module.conf`, populate `_IGOR_MODULE_DIRS`
2. `igor_sort_modules` — topological sort by `depends_on` and `required_modules`
3. `igor_load_module <name>` — for each module in order:
   - Check activation policy, required binaries and modules
   - `bash -n` syntax check
   - `source module.sh`
   - Call `<name>__register()`
   - Set `_IGOR_LOADED_MODULES[name]=1`
   - Export `<NAME>_STACK_DIR` if `stack_dir` is declared

For v2, discovery probes `module_api=2`, validates the strict manifest and
listed JSON contracts before sourcing the declared Bash entrypoint. Disabled
or invalid v2 packages are not sourced. Successful declarations are staged in
the owner-aware contribution index; inspect them with the module inspection
commands described in [module lifecycle](module_lifecycle.md).

**Hook execution model:**

Hooks registered via `igor_register_hook` are stored in `_IGOR_HOOKS[hook_name]="fn1 fn2"`. When Igor runs `igor_run_all_hooks "hook_name"`, each function is called in a `bash -c` subprocess with a 30-second timeout (`IGOR_HOOK_TIMEOUT` to override). Failures are logged but do not stop subsequent hooks.

**Important:** only the hook function definition is copied into the fresh Bash process. Helpers must be exported or explicitly sourced by the hook; unexported shell variables are unavailable. Test hooks through their actual dispatcher, not only by direct calls. Because `igor_run_all_hooks` executes hooks in subshells, hooks cannot modify the caller's global variables. Hooks that must stay in-process (e.g. `health_gate`, `role_check_app`, `alert_hook`, `rollback_handler`) are dispatched via `igor_get_hooks` and called directly in the parent shell.

---

## Module Directory Layout

The module directory structure mirrors the top-level Igor layout: `docs/`, `config/`, `lib/`, and so on each carry the same semantics at the module scope.

```
modules/
└── my_module/               ← directory name becomes default module name
    ├── module.conf          ← REQUIRED: manifest, deps, config declarations
    ├── module.sh            ← REQUIRED: hook functions, __register(), sources menus/
    │
    ├── checks/              ← OPTIONAL: healing check plugins (auto-discovered)
    │   └── my_check.sh
    ├── config/              ← OPTIONAL: runtime config templates (.tpl, .php, .conf)
    │   └── my_service.conf.tpl
    ├── defaults/            ← OPTIONAL: bootstrap files copied during __install()
    │   ├── docker-compose.yml
    │   ├── nginx.conf
    │   └── my_module.env.example
    ├── docs/                ← OPTIONAL: module documentation (README.md, guides)
    │   └── README.md
    ├── knowledge/           ← OPTIONAL: static AI knowledge files
    ├── lib/                 ← OPTIONAL: shared helpers internal to the module
    │   └── helpers.sh
    ├── menus/               ← OPTIONAL: lazy-loaded menu / feature sub-files
    │   ├── setup.sh         ← loaded on demand by _igor_load_module "setup"
    │   ├── services.sh
    │   └── maintenance.sh
    ├── patterns/            ← OPTIONAL: static healing pattern definitions
    └── runbooks/            ← OPTIONAL: procedure runbooks (.yaml)
```

The only strictly required files are `module.conf` and `module.sh`. Everything else is optional and used by specific subsystems.

### Directory purposes

| Directory | Igor parallel | Contents |
|-----------|---------------|----------|
| `checks/` | `core/healing/` | Health check plugins — auto-discovered by the healer |
| `config/` | `config/` | Runtime config templates rendered during setup |
| `defaults/` | `core/config/` | Bootstrap files copied verbatim by `__install()` |
| `docs/` | `docs/` | Module documentation: README, guides, architecture notes |
| `knowledge/` | `knowledge/` | Static text injected into AI system prompt |
| `lib/` | `core/lib/` | Internal helper functions shared within the module |
| `menus/` | `core/*/` | Interactive menus and feature sub-scripts, lazy-loaded |
| `patterns/` | `config/patterns/` | Healing pattern definitions (`.pattern` files) |
| `runbooks/` | — | Structured procedure documentation (`.yaml`) |

---

## module.conf — Manifest File

A simple `key=value` INI file. The parser reads the first matching key regardless
of section and retains inline comments as part of the value. Put comments on
separate lines. Repository tests require `[module]`, `[dependencies]`, nonempty
`name` and `display_name`, a numeric `X.Y.Z` version, and `requires_core`.
The runtime parser is more permissive; `requires_core` is metadata and is not
currently enforced. Use `required_modules` for mandatory dependencies (including
ordering). `depends_on` alone remains an ordering preference. Disabled dependencies
are never automatically enabled.

```ini
[module]
name=my_module
display_name=My Module
version=1.0.0
description=Short description of what this module does
requires_core=1.0.0
depends_on=system
menu_section=My Domain
menu_priority=60
menu_items=S:SETUP,1:STATUS,2:SERVICES
stack_dir=my_service

[config]
variables_file=config/variables/my_module.env
secrets_files=secrets/my_module.env

[secrets]
variables=MY_API_KEY,MY_DB_PASS
scrub_patterns=MY_API_KEY=[^[:space:]]+

[panels]
panels=my-log:docker compose logs -f --tail=50 my_svc:Live service logs

[dependencies]
required_bins=curl,docker
optional_bins=jq:jq:JSON processing
required_modules=
optional_modules=system:System integration
```

### Key fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes (tests) | Use the directory name and function prefix; loader has a basename fallback |
| `display_name` | Yes (tests) | Human label |
| `version` | Yes (tests) | Numeric `X.Y.Z` |
| `requires_core` | Yes (tests) | Compatibility metadata; not checked by the loader |
| `depends_on` | No | Comma/space-separated module names. Loader does topological sort |
| `stack_dir` | No | If set, `MY_MODULE_STACK_DIR` is exported pointing to `config/stacks/<stack_dir>/` |
| `variables_file` | No | Relative to `IGOR_DIR`; use `config/variables/<name>.env`. Declares a file to validate |
| `secrets_files` | No | Relative to `IGOR_DIR`; use `secrets/<name>.env`. Secrets must have mode 600 |
| `required_bins` | No | Module is skipped entirely if any listed binary is absent from PATH |
| `required_modules` | No | Module is skipped if any listed module failed to load |
| `provides` | No | Comma/space-separated operational capabilities exposed only while the module is active |

---

## module.sh — The Module Shell Script

`module.sh` is sourced directly into the Igor shell. It defines functions; it does **not** execute anything at source time. All side effects happen inside the `__register()` function or inside hook implementations.

```bash
#!/bin/bash
# =============================================================================
#  MODULE: my_module
#  Brief description.
# =============================================================================

# Source any sub-files the module needs (also just defines functions)
source "${IGOR_DIR}/modules/my_module/lib/helpers.sh"

# ── REQUIRED ─────────────────────────────────────────────────────────────────
my_module__register() {
    igor_register_hook "health"        "my_module__health"
    igor_register_hook "ai_context"    "my_module__ai_context"
    igor_register_hook "ai_knowledge"  "my_module__ai_knowledge"
    igor_register_hook "ai_tiers"      "my_module__ai_tiers"
    igor_register_hook "ai_capabilities" "my_module__ai_capabilities"
    igor_register_hook "backup"        "my_module__backup"
    igor_register_hook "restore"       "my_module__restore"
    igor_register_hook "status_line"   "my_module__status_line"
    igor_register_hook "notify_events" "my_module__notify_events"
    return 0
}

# ── Hook implementations follow ───────────────────────────────────────────────
```

**Naming rule:** Every function that could conflict with another module must be prefixed with `<module_name>__` (double underscore). Internal helpers use `_mod_<short>_*`.

---

## The `__register()` Function

`igor_load_module` calls `<name>__register()` after sourcing the file. This function registers hooks and any menu entries; it should not perform installation or interactive work.

```bash
my_module__register() {
    igor_register_hook "health"    "my_module__health"
    igor_register_hook "diagnose"  "my_module__diagnose"
    # ... all other hooks
    return 0
}
```

`igor_register_hook` is idempotent — registering the same function twice for the same hook is a no-op. Hooks are stored as a space-separated string in `_IGOR_HOOKS[hook_name]`.

---

## Lifecycle Hook Functions

These are not registered hooks — they are called by the module loader by convention:

| Function | Called by | Purpose |
|----------|-----------|---------|
| `<name>__register()` | `igor_load_module` at startup | Register hooks. **Required.** |
| `<name>__install()` | `igor_module_install <name>` | First-run setup. Bootstrap stack dir, create secrets template, install packages. Must be idempotent. |
| `<name>__upgrade()` | `igor_module_upgrade <name>` | Explicit post-update migration via `bash igor.sh --upgrade <name>`; no automatic version comparison. |
| `<name>__uninstall()` | `igor_module_remove <name>` | Cleanup. User must type YES before this is called. |

```bash
# Example: idempotent install that bootstraps a stack directory from defaults/
my_module__install() {
    local _mod_dir; _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local _stack="${IGOR_STACKS:-${IGOR_DIR}/config/stacks}/my_service"

    if [[ -d "$_stack" ]]; then
        echo "Stack already exists at ${_stack}/ — skipping."
        return 0
    fi

    mkdir -p "$_stack"
    cp "${_mod_dir}/defaults/docker-compose.yml" "$_stack/"
    echo "Stack bootstrapped at ${_stack}/"
}

my_module__upgrade() {
    # Example: add a new config key if it was missing
    local _vars="${IGOR_DIR}/config/variables/my_module.env"
    grep -q "^MY_NEW_KEY=" "$_vars" 2>/dev/null || \
        echo "MY_NEW_KEY=default" >> "$_vars"
}

my_module__uninstall() {
    rm -rf "${IGOR_STACKS:-${IGOR_DIR}/config/stacks}/my_service"
    rm -f "${IGOR_DIR}/secrets/my_module.env"
    echo "my_module removed."
}
```

---

## All Registered Hooks — Reference

### Hook: `health`

**Invoked by:** explicit callers. The current header does not dispatch `health`; it displays the healing score and `status_line` hooks.

**Execution:** subshell via `igor_run_all_hooks`. Output captured.

**Must output:** exactly one line: `status:message`
- `status` is one of: `ok`, `warn`, `fail`
- `message` is a short description (shown in the header bar)

```bash
my_module__health() {
    local issues=""

    if ! command -v docker &>/dev/null; then
        echo "fail:docker not installed"
        return 0
    fi

    local running
    running=$(docker compose ps --status running --services 2>/dev/null | wc -l)
    [ "${running:-0}" -eq 0 ] && { echo "fail:stack down"; return 0; }

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 3 "http://localhost:${MY_PORT:-8080}/health" 2>/dev/null)
    [ "$http_code" != "200" ] && issues+="HTTP ${http_code}; "

    if [ -n "$issues" ]; then
        echo "warn:${issues%; }"
    else
        echo "ok:${running} containers running"
    fi
    return 0
}
```

The output is available to explicit callers. For header display, implement `status_line`; registering `health` alone does not display it.

---

### Hook: `status_line`

**Invoked by:** `core/lib/ui.sh:123` via `igor_run_all_hooks "status_line"` inside the `header()` function.

**Execution:** subshell. Output printed directly to terminal.

**Must output:** one or more lines in `"  Key       : value"` format. Use ANSI color codes for status indicators. Keep lines short — they appear in the header bar.

```bash
my_module__status_line() {
    local GRN='\033[0;32m' RED='\033[0;31m' YEL='\033[1;33m' NC='\033[0m'

    local svc_status
    systemctl is-active my-service &>/dev/null \
        && svc_status="${GRN}● RUNNING${NC}" \
        || svc_status="${RED}● DOWN${NC}"
    echo -e "  MyService : ${svc_status}"

    local api_ok
    curl -sf --max-time 2 "http://localhost:${MY_PORT:-8080}/ping" &>/dev/null \
        && api_ok="${GRN}reachable${NC}" \
        || api_ok="${YEL}unreachable${NC}"
    echo -e "  API       : ${api_ok}"
    return 0
}
```

**Performance budget:** the `header()` function is called at every menu repaint. Keep this fast — three checks maximum, 150ms total. No `occ`, no heavy `docker compose` calls.

---

### Hook: `menu_header`

**Invoked by:** the fzf main-menu display before listing items. The plain-text renderer uses manifest labels.

**Execution:** command substitution in the main-menu renderer. The current renderer uses the first registered header for all module sections; per-module routing is not implemented.

**Must output:** a single line — the section title to display above this module's menu items. Return the `display_name` when healthy; a status summary when degraded.

```bash
my_module__menu_header() {
    if ! command -v docker &>/dev/null; then
        echo "  NOT INSTALLED — run [S] SETUP to get started"
        return 0
    fi

    local running
    running=$(docker ps --filter "name=my_service" --format '{{.Names}}' 2>/dev/null | wc -l)
    if [ "${running:-0}" -eq 0 ]; then
        echo "  STACK STOPPED — run [2] SERVICES → START ALL"
        return 0
    fi

    echo "My Service"   # healthy — just return the display name
    return 0
}
```

---

### Hook: `diagnose`

**Invoked by:** Igor Diagnose aggregator (`core/lib/diagnose_runner.sh`).

**Execution:** a fresh Bash process through `igor_diagnose_collect`, with a 60-second default timeout (`--timeout` overrides it). Only the hook definition is copied, so helper dependencies must be exported or sourced.

**Must output:** one line per check: `CHECK:<name>:<status>:<message>`
- `status` is one of: `ok`, `warn`, `fail`, `skip`

```bash
my_module__diagnose() {
    local _stack="${IGOR_STACKS:-${IGOR_DIR}/config/stacks}/my_service"

    # Check 1: stack directory
    if [[ -d "$_stack" ]]; then
        echo "CHECK:stack_dir:ok:config/stacks/my_service/ present"
    else
        echo "CHECK:stack_dir:fail:config/stacks/my_service/ missing — run S→ SETUP"
        return 0
    fi

    # Check 2: secrets file
    [[ -f "${IGOR_DIR}/secrets/my_module.env" ]] \
        && echo "CHECK:secrets:ok:secrets/my_module.env present" \
        || echo "CHECK:secrets:fail:secrets/my_module.env missing"

    # Check 3: containers
    if command -v docker &>/dev/null; then
        local running
        running=$(docker ps --filter "name=my_service" --format '{{.Names}}' 2>/dev/null | wc -l)
        if [[ "$running" -eq 0 ]]; then
            echo "CHECK:containers:fail:no containers running"
        else
            echo "CHECK:containers:ok:${running} containers running"
        fi
    else
        echo "CHECK:containers:skip:docker not installed"
    fi
}
```

---

### Hook: `app_diagnose`

**Invoked by:** `core/diagnose/phases.sh` Phase 5 (application layer) — called **in-process** (not via `igor_run_all_hooks`), so `_diag_emit` and `_DIAG_RESULTS` are available.

**Purpose:** Deep application-layer checks during a full 6-phase diagnostic session. This hook replaces the hardcoded application checks that used to live in `core/diagnose/phases.sh`.

**Arguments:** `$1=deep` (`true`|`false`)

**Must use `_diag_emit`:** `_diag_emit SEVERITY code "message"`
- Severity: `OK`, `WARN`, `FAIL`, `CRITICAL`

```bash
my_module__app_diagnose() {
    local deep="${1:-false}"
    _my_module_diag_phase5 "$deep"
}

_my_module_diag_phase5() {
    local deep="${1:-false}"

    # occ/app check
    local status_out
    status_out=$(docker compose exec -T -u www-data app php occ status 2>/dev/null)
    if [ -z "$status_out" ]; then
        _diag_emit FAIL my_occ_unavailable "occ not responding — app container may not be ready"
        return
    fi
    _diag_emit OK my_occ_ok "occ command available"

    # Config check
    local proto
    proto=$(docker compose exec -T -u www-data app php occ \
        config:system:get overwriteprotocol 2>/dev/null | tr -d '[:space:]')
    [ "$proto" = "https" ] \
        && _diag_emit OK my_proto "overwriteprotocol=https" \
        || _diag_emit WARN my_proto "overwriteprotocol='${proto:-not set}' — expected https"

    if [ "$deep" = "true" ]; then
        # More expensive checks only in deep mode
        local error_count
        error_count=$(docker compose exec -T app grep -c '"level":3\|"level":4' \
            /var/www/html/data/app.log 2>/dev/null || echo 0)
        (( error_count >= 10 )) \
            && _diag_emit WARN my_errors "${error_count} errors in app log" \
            || _diag_emit OK my_errors "${error_count} errors in app log"
    fi
}
```

---

### Hook: `health_gate`

**Invoked by:** `core/diagnose/core.sh:421` and `core/ai/core.sh:832` — called **in-process**.

**Purpose:** Replaces the hardcoded HTTP/status check that guards whether the application layer is reachable before running diagnose phases. The gate runs before Phase 3; if it returns non-zero, diagnose skips to a failure state.

**Must return:** `0` if application is reachable, `1` if not. No output required.

```bash
_my_health_gate() {
    local port="${MY_HTTP_PORT:-8080}"
    local code
    code=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 8 \
        "http://localhost:${port}/health" 2>/dev/null)
    [ "$code" = "200" ]
}
```

Register with: `igor_register_hook "health_gate" "_my_health_gate"`

Only one module typically registers this hook. If multiple are registered, all must pass.

---

### Hook: `role_check_app`

**Invoked by:** `core/diagnose/phases.sh:664` Phase 3 — called **in-process**.

**Purpose:** Application-role checks for a specific container. The diagnose phases detect which container has the "app" role and pass its service name here.

**Arguments:** `$1=svc` (container service name), `$2=deep` (`true`|`false`)

**Must use `_diag_emit`** (same as `app_diagnose`).

```bash
_my_check_role_app() {
    local svc="$1" deep="$2"

    local status_json
    status_json=$(docker compose exec -T "$svc" my-cli status --json 2>/dev/null)
    if [ -z "$status_json" ]; then
        _diag_emit FAIL my_cli_unavailable "CLI not responding in container ${svc}"
        return
    fi

    local installed
    installed=$(echo "$status_json" | python3 -c \
        "import sys,json; print(json.load(sys.stdin).get('installed',False))" 2>/dev/null)
    [ "$installed" = "True" ] \
        && _diag_emit OK my_installed "Application reports installed=true" \
        || _diag_emit CRITICAL my_not_installed "Application not installed"
}
```

Register with: `igor_register_hook "role_check_app" "_my_check_role_app"`

---

### Hook: `alert_hook`

**Invoked by:** `core/healing/alerts.sh:52` inside `alert_log()` — called **in-process**.

**Purpose:** Side-effect actions when a CRITICAL or FAIL alert is raised by the healing subsystem. Used to push notifications through application-layer channels (e.g. in-app notifications).

**Arguments:** `$1=severity`, `$2=code`, `$3=message`

**Must not block** — runs synchronously during the alert path. Failures are silently swallowed.

```bash
_my_alert_hook() {
    local severity="$1" code="$2" message="$3"

    # Example: send an in-app notification
    local admin_user="${MY_ADMIN_USER:-}"
    [ -z "$admin_user" ] && return 0

    docker compose exec -T -u www-data app php occ \
        notification:generate "$admin_user" "IGOR Health Alert" \
        --long-message "[${severity}] ${code}: ${message}" \
        2>/dev/null || true
}
```

Register with: `igor_register_hook "alert_hook" "_my_alert_hook"`

---

### Hook: `ai_context`

**Invoked by:** `core/ai/context.sh:41` inside `ai_gather_context()` — subshell.

**Purpose:** Inject a live system state snapshot into every AI API call. This is the most important hook for making the AI useful — it tells the AI what the system actually looks like right now.

**Must output:** a formatted text block. Start with a section header. Keep it under ~80 lines — it contributes to the AI's token budget on every call.

```bash
my_module__ai_context() {
    local ctx=""

    ctx+="\n=== MY SERVICE STATUS ===\n"
    ctx+="$(docker compose ps 2>/dev/null || echo 'docker not available')\n"

    ctx+="\n=== MY SERVICE CONFIG (key settings) ===\n"
    for key in max_connections log_level debug_mode; do
        local val
        val=$(my-cli config get "$key" 2>/dev/null || echo "not set")
        ctx+="${key}: ${val}\n"
    done

    ctx+="\n=== RECENT ERRORS (last 10) ===\n"
    ctx+="$(tail -20 "${MY_LOG_PATH:-/var/log/my_service.log}" 2>/dev/null \
        | grep -i error | tail -10 || echo 'log not available')\n"

    ctx+="\n=== HTTP CHECK ===\n"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 3 "http://localhost:${MY_PORT:-8080}/health" 2>/dev/null)
    ctx+="localhost:${MY_PORT:-8080}/health → ${code}\n"

    echo -e "$ctx"
    return 0
}
```

**Note:** This hook runs in a subshell. Do not rely on any global variables set after `igor_load_config`. Use `$IGOR_DIR` and exported env vars only.

---

### Hook: `ai_knowledge`

**Invoked by:** `core/ai/context.sh:122` inside `_ai_load_base_prompt()` — subshell. Output is passed to `ai_render.py` as `IGOR_MODULE_KNOWLEDGE`.

**Purpose:** Static architectural reference information: architecture, command patterns, and decision trees. Active module output is sent as untrusted reference data, separately from Igor's policy. It cannot change approval rules. Minimal-context policy omits this hook.

**Must output:** plain text. No JSON, no special format. Markdown headings with `━━━` separators work well for clarity.

```bash
my_module__ai_knowledge() {
    local _root="${IGOR_DIR:-}"
    local _stack="${IGOR_STACKS:-${_root}/config/stacks}/my_service"

    cat << EOF
━━━ MY SERVICE — ARCHITECTURE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Stack: Internet → nginx (port ${MY_PORT:-8080}) → my_app → postgres
Config dir: ${_stack}
All docker compose commands require:
  docker compose -f ${_stack}/docker-compose.yml <cmd>

━━━ CRITICAL RULES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- NEVER edit config.json directly — use: my-cli config set <key> <value>
- Config lives in the named Docker volume, not in a bind mount
- After any config change, run: my-cli reload
- If HTTP returns 502: check app container first, then nginx

━━━ DIAGNOSTIC LAYERS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

502 Bad Gateway → container status (docker compose ps)
403 Forbidden   → nginx config (${_stack}/nginx.conf)
Auth errors     → my-cli user:list → my-cli config get trusted_proxies
Slow responses  → check redis connection, then DB query stats

━━━ MENU MAP ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  S  SETUP      First-run wizard
  1  STATUS     Quick dashboard
  2  SERVICES   Start/stop/restart
  3  MAINTENANCE Scan, repair, flush caches
  4  CONFIGURE  Settings, nginx, upload limits
  5  DIAGNOSE   Health checks, routing, DB integrity
EOF
}
```

---

### Hook: `ai_tiers`

**Invoked by:** `core/ai/context.sh:121` — subshell. Output passed to `ai_render.py` as `IGOR_MODULE_TIERS`.

**Purpose:** Provide advisory descriptions of command tiers as untrusted reference data. The deterministic dispatcher and registered capability tiers govern execution; this hook cannot authorize commands or override classification. Minimal-context policy omits it.

**Must output:** plain text with READ / CHANGE / DESTROY sections.

```bash
my_module__ai_tiers() {
    cat << 'EOF'
MY SERVICE TIER RULES:

READ (auto-run, no confirmation):
  docker compose -f ... ps
  docker compose -f ... logs [--tail N] <service>
  my-cli status
  my-cli config get <key>
  my-cli user:list
  curl -s ... (HTTP status checks)
  cat <config file> (read-only)

CHANGE (requires user confirmation or executive mode):
  docker compose -f ... restart <service>
  my-cli config set <key> <value>
  my-cli maintenance:on / maintenance:off
  my-cli cache:flush
  <edit_file> on any config file
  systemctl restart my-service

DESTROY (user must type YES):
  docker compose -f ... down --volumes
  docker volume rm
  my-cli data:wipe
  rm -rf <any directory>
EOF
}
```

---

### Hook: `ai_tools`

**Status:** Legacy registration is tolerated, but the AI router no longer consumes
this hook. A JSON declaration never supplied an executor for arbitrary tool names,
and letting module prose define privileged tools created a second source of truth.

Use [`ai_capabilities`](#hook-ai_capabilities) to register a module-owned leaf
action and its enforced tier. Igor exposes it through `run_igor_action`, subject
to active ownership and administrator policy. Core schemas derive from the
dispatcher's supported fields. `occ` and `container` additionally require active
providers of the `nextcloud` and `docker` capabilities, respectively.

Do not place instructions, runtime logs, credentials, or arbitrary schemas in
tool metadata. Use the reference-data hooks for descriptions and observations.
For Igor 2 AI/context migration direction, see [igor2/ARCHITECTURE.md](igor2/ARCHITECTURE.md) and [igor2/ROADMAP.md](igor2/ROADMAP.md).

---

### Hook: `ai_patterns`

**Invoked by:** `core/ai/context.sh:330` inside `_ai_inject_patterns()` — subshell.

**Purpose:** Inject static, known-good repair patterns into the AI context. These are the expert knowledge of recurring failure modes and their fixes, expressed in a machine-readable format the AI can match against the current situation.

**Must output:** one or more `PATTERN:` blocks in this exact format:

```
PATTERN: <pattern_name>  confirmed:<N>  failed:<N>  tier:<TIER>
  Fix: <fix command or tag>
```

```bash
my_module__ai_patterns() {
    cat << 'EOF'
PATTERN: my_service_nginx_default_conf  confirmed:0  failed:0  tier:CHANGE
  Fix: docker compose -f <STACK_DIR>/docker-compose.yml exec -T web rm -f /etc/nginx/conf.d/default.conf && docker compose restart web

PATTERN: my_service_cache_corrupted  confirmed:0  failed:0  tier:CHANGE
  Fix: docker compose -f <STACK_DIR>/docker-compose.yml exec -T redis redis-cli FLUSHALL

PATTERN: my_service_maintenance_stuck  confirmed:0  failed:0  tier:CHANGE
  Fix: <my_cli> maintenance:off </my_cli>
EOF
}
```

The `confirmed` and `failed` counters are for display — the healing subsystem's learned patterns use their own `.pattern` files.

---

### Hook: `ai_capabilities`

**Invoked by:** `igor_load_capabilities()` in `core/lib/module_loader.sh` — collected through command substitution, not the fresh-Bash dispatcher. Parent-shell mutations do not propagate. Called once at AI session start from `menu_ai()`.

**Purpose:** Declare non-interactive leaf functions that the AI can invoke directly via the `<run_igor_action>action_name</run_igor_action>` tool tag. The AI uses the problem keywords to choose the right action when the user describes a symptom.

**Must output:** one or more `ACTION` blocks, one per callable function. Blank lines separate blocks.

```
ACTION <action_name>
DESCRIPTION <one-line description>
FUNCTION <bash_function_name>
LOAD_MODULE <module_name_to_load_before_calling>
TIER READ|CHANGE|DESTROY
PROBLEMS <comma-separated symptom keywords>
MENU_PATH <human-readable location in Igor menu>
```

**Rules for action functions:**
- Must be **non-interactive** — no `read`, no `select`, no `while true` menus
- Must accept input via `</dev/null` (run with stdin closed)
- Should print human-readable output to stdout
- Should return 0 on success, non-zero on failure

```bash
my_module__ai_capabilities() {
    cat << 'EOF'
ACTION health_check
DESCRIPTION Run quick health check — HTTP probe, container count
FUNCTION _mod_my_health_check
LOAD_MODULE my_module
TIER READ
PROBLEMS down, unreachable, not responding, health, check, 502
MENU_PATH [5] DIAGNOSE → QUICK HEALTH CHECK

ACTION flush_cache
DESCRIPTION Flush application cache (Redis + local APCu)
FUNCTION _mod_my_flush_cache
LOAD_MODULE my_module
TIER CHANGE
PROBLEMS cache, slow, stale, redis, not refreshing, outdated
MENU_PATH [3] MAINTENANCE → FLUSH CACHE

ACTION fix_permissions
DESCRIPTION Fix data directory ownership and permissions
FUNCTION _mod_my_fix_permissions
LOAD_MODULE my_module
TIER CHANGE
PROBLEMS permission, 403, denied, ownership, cannot write, www-data
MENU_PATH [3] MAINTENANCE → FIX PERMISSIONS
EOF
}
```

The corresponding functions must be defined in the module:

```bash
_mod_my_health_check() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 "http://localhost:${MY_PORT:-8080}/health" 2>/dev/null)
    echo "HTTP status: ${code}"
    docker compose ps 2>/dev/null
}

_mod_my_flush_cache() {
    docker compose exec -T redis redis-cli FLUSHALL 2>&1
    echo "Cache flushed."
}

_mod_my_fix_permissions() {
    local _data="${MY_DATA_DIR:-/mnt/mydata}"
    sudo chown -R 1000:1000 "$_data" 2>&1
    sudo find "$_data" -type d -exec chmod 755 {} \; 2>&1
    echo "Permissions fixed on ${_data}."
}
```

---

### Hook: `backup`

**Invoked by:** `core/recovery/full_backup.sh:125` via `igor_run_all_hooks "backup" "$snapshot_dir"` — subshell.

**Arguments:** `$1=snapshot_dir` — absolute path to the current backup snapshot directory

**Purpose:** Save module-specific state to `$snapshot_dir/modules/<module_name>/`. The core backup has already captured Igor's own config; the module captures service-specific state (database dumps, volume exports, configuration exports).

```bash
my_module__backup() {
    local snapshot_dir="${1:-}"
    local dest="${snapshot_dir}/modules/my_module"

    [ -z "$snapshot_dir" ] && { echo "my_module__backup: missing snapshot_dir" >&2; return 1; }
    mkdir -p "$dest"

    local GRN='\033[0;32m' YEL='\033[1;33m' NC='\033[0m'

    # Export application configuration
    if docker compose exec -T app my-cli config:export > "${dest}/config_export.json" 2>/dev/null; then
        echo -e "  ${GRN}✔${NC} Config exported"
    else
        rm -f "${dest}/config_export.json"
        echo -e "  ${YEL}!${NC} Config export skipped (service may not be running)"
    fi

    # Database dump
    if docker compose exec -T db pg_dump -U "${DB_USER:-myapp}" "${DB_NAME:-myapp}" \
            > "${dest}/db_dump.sql" 2>/dev/null; then
        gzip -f "${dest}/db_dump.sql"
        echo -e "  ${GRN}✔${NC} Database dumped ($(du -sh "${dest}/db_dump.sql.gz" | cut -f1))"
    else
        echo -e "  ${YEL}!${NC} Database dump skipped"
    fi

    # Copy docker-compose.yml
    local _stack="${IGOR_STACKS:-${IGOR_DIR}/config/stacks}/my_service"
    for _f in docker-compose.yml nginx.conf; do
        [ -f "${_stack}/${_f}" ] && cp "${_stack}/${_f}" "${dest}/" && \
            echo -e "  ${GRN}✔${NC} ${_f} copied"
    done

    return 0
}
```

---

### Hook: `restore`

**Invoked by:** `core/recovery/full_backup.sh:252` via `igor_run_all_hooks "restore" "$backup_dir"` — subshell.

**Arguments:** `$1=backup_dir` — path to the backup directory to restore from

**Purpose:** Restore from `$backup_dir/modules/<module_name>/`. The function must be idempotent (can be run multiple times safely) and should put maintenance mode on/off around the restore if applicable.

```bash
my_module__restore() {
    local backup_dir="${1:-}"
    local src="${backup_dir}/modules/my_module"

    [ -z "$backup_dir" ] && { echo "my_module__restore: missing backup_dir" >&2; return 1; }
    [ -d "$src" ] || { echo "No my_module backup found in ${backup_dir}"; return 0; }

    local GRN='\033[0;32m' YEL='\033[1;33m' NC='\033[0m'

    # Restore compose file
    local _stack="${IGOR_STACKS:-${IGOR_DIR}/config/stacks}/my_service"
    mkdir -p "$_stack"
    for _f in docker-compose.yml nginx.conf; do
        [ -f "${src}/${_f}" ] && cp "${src}/${_f}" "${_stack}/${_f}" && \
            echo -e "  ${GRN}✔${NC} ${_f} restored"
    done

    # Restore database
    if [ -f "${src}/db_dump.sql.gz" ]; then
        echo "  Restoring database..."
        docker compose exec -T db psql -U "${DB_USER:-myapp}" -c \
            "DROP DATABASE IF EXISTS ${DB_NAME:-myapp};" 2>/dev/null || true
        docker compose exec -T db psql -U "${DB_USER:-myapp}" -c \
            "CREATE DATABASE ${DB_NAME:-myapp};" 2>/dev/null
        zcat "${src}/db_dump.sql.gz" | \
            docker compose exec -T db psql -U "${DB_USER:-myapp}" "${DB_NAME:-myapp}"
        echo -e "  ${GRN}✔${NC} Database restored"
    fi

    return 0
}
```

---

### Hook: `recovery`

**Status:** reserved registration point; no production dispatcher currently calls this hook. Use `backup`, `restore`, or `rollback_handler` for implemented recovery integration.

```bash
my_module__recovery() {
    my_module__recovery_hooks
    return 0
}

my_module__recovery_hooks() {
    # Register any recovery-specific callbacks here
    return 0
}
```

---

### Hook: `rollback_handler`

**Invoked by:** `core/recovery/journal.sh:332` when the user triggers `undo` from the AI session — called **in-process**.

**Purpose:** Map an `action` type and original command string to an undo command. The journal records actions taken during an AI session with an action type tag (`app_enable`, `app_disable`, `occ_exec`, etc.). Your module can handle additional action types for its domain.

**Arguments:** `$1=action`, `$2=original_cmd`

**Must:** echo the undo command to stdout and return `0` if the action is undoable. Return `1` (no output) if the action type is unknown to this module.

```bash
_my_rollback_dispatch() {
    local action="$1" cmd="$2"
    case "$action" in
        my_plugin_enable)
            echo "docker compose exec -T -u app app my-cli plugin:disable ${cmd}"
            return 0
            ;;
        my_plugin_disable)
            echo "docker compose exec -T -u app app my-cli plugin:enable ${cmd}"
            return 0
            ;;
        my_maintenance_on)
            echo "docker compose exec -T app my-cli maintenance:off"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
```

Register with: `igor_register_hook "rollback_handler" "_my_rollback_dispatch"`

---

### Hook: `config_validate`

**Invoked by:** `igor.sh` after modules are loaded — called **in-process**.

**Purpose:** Validate that critical config variables are set. Print warnings to stderr. Do not `exit` — validation is advisory only.

```bash
_my_validate_config() {
    [ -z "${MY_ADMIN_USER:-}" ] && \
        echo "  [igor] WARNING: MY_ADMIN_USER not set — some features will not work" >&2
    [ -z "${MY_DOMAIN:-}" ] && \
        echo "  [igor] WARNING: MY_DOMAIN not set — Nextcloud will reject requests" >&2
    [ -z "${MY_DB_PASS:-}" ] && \
        echo "  [igor] WARNING: MY_DB_PASS not set — database connections will fail" >&2
}
```

Register with: `igor_register_hook "config_validate" "_my_validate_config"`

---

### Hook: `notify`

**Invoked by:** the notification subsystem to aggregate notification sources. Most modules delegate to a `notify_sources()` function or return immediately.

```bash
my_module__notify() {
    my_module__notify_sources
    return 0
}

my_module__notify_sources() {
    # Register notification sources for this module.
    # Most modules leave this empty — actual event firing happens via notify_event().
    return 0
}
```

---

### Hook: `notify_events`

**Invoked by:** `core/notify/core.sh:52` inside `_notify_collect_module_events()` via `igor_get_hooks "notify_events"` — output collected through process substitution (shell state changes do not propagate).

**Purpose:** Declare what events this module can emit so Igor's notification settings menu can show them with per-event enable/disable toggles. The notify subsystem auto-creates `NOTIFY_ON_<VAR_SUFFIX>` config flags.

**Must output:** one line per event:
`EVENT|event_key|label|NOTIFY_VAR_SUFFIX|default(true/false)|severity(critical/warning/info)`

```bash
my_module__notify_events() {
    echo "EVENT|my_login_failed|Multiple failed login attempts|MY_LOGIN_FAILED|true|critical"
    echo "EVENT|my_service_down|Service stopped unexpectedly|MY_SERVICE_DOWN|true|critical"
    echo "EVENT|my_low_storage|Data volume running low (<10% free)|MY_LOW_STORAGE|true|critical"
    echo "EVENT|my_maintenance_on|Maintenance mode toggled on|MY_MAINTENANCE_MODE|true|warning"
    echo "EVENT|my_update_available|New version available|MY_UPDATE_AVAILABLE|true|info"
    echo "EVENT|my_backup_done|Backup completed|MY_BACKUP_DONE|false|info"
}
```

To actually fire an event from anywhere in your module code:

```bash
# Inside any module function
declare -f notify_event &>/dev/null && \
    notify_event "my_service_down" \
        "Service my_svc stopped — check logs with [2] SERVICES → LOGS" \
        "Service Down Alert" \
    2>/dev/null || true
```

---

### Hook: `mailcmd`

**Status:** reserved for the mailcmd subsystem, which is absent from this tree. Registering verbs does not currently enable email commands.

**Must output:** a space-separated list of verb strings that can appear in the subject line of a GPG-signed email command.

```bash
my_module__mailcmd() {
    my_module__mailcmd_verbs
    return 0
}

my_module__mailcmd_verbs() {
    echo "mystatus myrestart myupgrade"
    return 0
}
```

The example describes the intended verb format only; there is no available mailcmd dispatch table to integrate with in this tree.

---

## Check Plugins — Healing Subsystem

Check plugins are independent shell scripts placed in `modules/<name>/checks/*.sh`. They are discovered automatically by `_healing_discover_checks()` which globs `modules/*/checks/*.sh`, skipping files prefixed with `_`.

Discovery scans files regardless of whether the owning module loaded successfully; checks must guard unavailable dependencies. Each check runs in a subshell via `_healing_run_check()`. The subshell re-sources `core/lib/ui.sh`, `core/lib/helpers.sh`, and `core/lib/config.sh` before calling your `run_check()`.

The separate `igor_diagnose_collect` aggregator executes check scripts directly
and accepts `CHECK:name:status:message`, not `CHECK_RESULT`. A healing plugin that
only defines `run_check()` produces no output there. Register a `diagnose` hook
for diagnostic integration; do not assume these two protocols are interchangeable.

### Check file structure

```bash
#!/bin/bash
# ==============================================================================
#  IGOR — modules/my_module/checks/my_check.sh
#  Brief description of what this check tests.
# ==============================================================================

CHECK_NAME="my_check"
CHECK_DESCRIPTION="Short description for display"
CHECK_SCHEDULE="60"    # target run interval in seconds (informational)

# PATTERN_HINT lines document recoverable failures (used by future tooling)
# PATTERN_HINT <code> "<description>" <TIER> "<fix command>"
# PATTERN_HINT my_service_down "Service container not running" CHANGE "docker compose up -d my_svc"

run_check() {
    # Check 1: docker available
    if ! command -v docker &>/dev/null; then
        echo "CHECK_RESULT FAIL my_check_no_docker Docker not installed or not in PATH"
        return 0
    fi

    # Check 2: container running
    local running
    running=$(docker compose ps --status running --services 2>/dev/null | grep -c "my_svc" || echo 0)
    if [ "${running:-0}" -eq 0 ]; then
        echo "CHECK_RESULT FAIL my_svc_down my_svc container is not running"
    else
        echo "CHECK_RESULT OK my_svc_running my_svc container running"
    fi

    # Check 3: HTTP probe
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 "http://localhost:${MY_PORT:-8080}/health" 2>/dev/null)
    if [ "$code" = "200" ]; then
        echo "CHECK_RESULT OK my_http_ok HTTP 200 from /health"
    else
        echo "CHECK_RESULT WARN my_http_fail HTTP ${code:-timeout} from /health — service may be starting"
    fi

    # Check 4: data directory mounted
    local _data="${MY_DATA_DIR:-/mnt/mydata}"
    if [ -d "$_data" ]; then
        local pct
        pct=$(df "$_data" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
        if [ -n "$pct" ] && [ "$pct" -ge 90 ]; then
            echo "CHECK_RESULT CRITICAL my_storage_critical Data dir ${pct}% full — CRITICAL"
        elif [ -n "$pct" ] && [ "$pct" -ge 75 ]; then
            echo "CHECK_RESULT WARN my_storage_warn Data dir ${pct}% full"
        else
            echo "CHECK_RESULT OK my_storage Data dir ${pct:-?}% used"
        fi
    else
        echo "CHECK_RESULT FAIL my_storage_missing Data dir ${_data} not found"
    fi
}
```

### CHECK_RESULT format

```
CHECK_RESULT <SEVERITY> <code> <message>
```

| Severity | Meaning |
|----------|---------|
| `OK` | Check passed — contributes positively to health score |
| `WARN` | Degraded but functional — shown in health summary |
| `FAIL` | Service problem — triggers alert banner, lowers health score |
| `CRITICAL` | Severe problem — triggers immediate notification hook |

- `code` is a short camelCase or snake_case identifier (no spaces) used for pattern matching
- `message` is a human-readable description (may contain spaces)
- A single `run_check()` call can emit multiple `CHECK_RESULT` lines
- Output other than `CHECK_RESULT` lines is ignored by the healer

### Health score contribution

The healing core (`core/healing/core.sh`) counts results across all checks. `CRITICAL` reduces the score most, `FAIL` less, `WARN` slightly. `OK` results are weighted positively. The final `0–100` score is displayed in the header.

---

## Configuration System — Variables, Secrets, Defaults

Igor loads configuration in six steps (`core/lib/config_loader.sh`):

| Step | Source | Notes |
|------|--------|-------|
| 0 | `core/config/defaults.conf` | Platform-wide defaults |
| 1 | `config/variables/*.env` | Non-sensitive settings — git-safe |
| 2 | `secrets/*.env` | Credentials — gitignored, must be chmod 600 |
| 3 | `secrets/*.key` | API keys — exported as `<STEM>_API_KEY` |
| 4 | Root-level `*.env` | Deprecated backward compat |
| 5 | Module config validation | `igor_validate_module_config` per loaded module; startup repeats validation after module loading |

The loader scans the standard directories, not arbitrary paths declared in a
manifest. `variables_file` and `secrets_files` are existence-validation declarations;
keep the declared files in those directories. Root-level legacy env files load
last and can override newer settings; migrate them away.

### Adding your module's config

**Variables file** (`config/variables/my_module.env`):

```bash
# Non-sensitive defaults — commit this file
MY_PORT=8080
MY_DATA_DIR=/mnt/mydata
MY_LOG_LEVEL=2
MY_MAX_UPLOAD_SIZE=512M
```

Declare this in `module.conf`:
```ini
[config]
variables_file=config/variables/my_module.env
```

**Secrets file** (`secrets/my_module.env`):

```bash
# Sensitive — gitignored, chmod 600 REQUIRED
MY_DB_PASS=changeme
MY_ADMIN_PASS=changeme
MY_API_KEY=sk-...
```

Declare in `module.conf`:
```ini
[config]
secrets_files=secrets/my_module.env
```

The secrets file is validated for 600 permissions at load time. A warning is logged if permissions are wrong, but loading continues.

### Reading config in your module

All variables from both files are exported into the shell environment by `igor_load_config`, so you can read them directly:

```bash
my_module__ai_context() {
    echo "Port: ${MY_PORT:-8080}"
    echo "Data: ${MY_DATA_DIR:-/mnt/mydata}"
}
```

Use the helper function for safe reads with defaults:

```bash
igor_get_config "MY_PORT" "8080"   # prints value or "8080" if unset
```

### Providing a defaults template for `__install()`

Place a default env file at `modules/my_module/defaults/my_module.env` that `__install()` copies to `secrets/my_module.env` (with a reminder to fill in real values):

```bash
my_module__install() {
    local _mod_dir; _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Note: if __install is defined in a menus/ file, add /.. to _mod_dir
    local _secrets="${IGOR_DIR}/secrets"
    local _target="${_secrets}/my_module.env"

    if [[ ! -f "$_target" ]]; then
        cp "${_mod_dir}/defaults/my_module.env.tmpl" "$_target"
        chmod 600 "$_target"
        echo "Created ${_target} — edit it and fill in real credentials before starting."
    fi

    # Bootstrap stack directory
    local _stack="${IGOR_STACKS:-${IGOR_DIR}/config/stacks}/my_service"
    if [[ ! -d "$_stack" ]]; then
        mkdir -p "$_stack"
        cp "${_mod_dir}/defaults/docker-compose.yml" "$_stack/"
        echo "Stack bootstrapped at ${_stack}/"
    fi
}
```

---

## Menu Registration

Modules can add entries to the Igor main menu using `igor_register_menu_item` (called from `__register()`):

```bash
my_module__register() {
    # ... hook registrations ...

    # Register main menu entry
    # igor_register_menu_item <key> <label> <load_type> <load_arg> <menu_func>
    igor_register_menu_item \
        "m" \
        "MY MODULE — manages my service" \
        "module" \
        "my_module" \
        "menu_my_module"

    return 0
}
```

Parameters:
- `key` — character(s) the user types at the main menu
- `label` — description shown in the recent-items list and dispatch display
- `load_type` — `"module"` (discovered module or legacy feature file) or `"subsystem"` (calls `_igor_load_subsystem`)
- `load_arg` — module name (for `module` type) or `"subsystem_id path/to/core.sh"` (for `subsystem` type)
- `menu_func` — function to call after loading (typically `menu_my_module`)

`menu_items` controls rendering in the Igor main menu. It accepts legacy
`KEY:LABEL` entries and label-only entries with automatically assigned keys.
Registration through `igor_register_menu_item` controls dispatch separately;
registering a callback alone does not render it. Prefer explicit `KEY:LABEL`
entries with matching registry keys. Core reserved keys take precedence.

For `load_type=module`, discovered module names use `igor_load_module`;
legacy feature-file arguments use `_igor_load_module` (a filename search across
module directories). Give lazy-loaded feature files distinctive names to avoid
collisions. The renderer's label-only numbering is not a general callback map.

### The `menu_my_module()` function

This is the top-level interactive menu for your module. It must be a `while true` loop with a `read` or `select`. It lazy-loads feature sub-files from `menus/` on demand:

```bash
menu_my_module() {
    while true; do
        clear
        if declare -f header &>/dev/null; then header; fi
        if declare -f breadcrumb &>/dev/null; then breadcrumb "Igor" "My Module"; fi

        echo ""
        echo "  S  SETUP & INSTALL"
        echo "  1  STATUS"
        echo "  2  SERVICES"
        echo "  3  MAINTENANCE"
        echo "  B  BACK"
        echo ""

        local choice
        read -rp "  Choice: " choice </dev/tty

        case "$choice" in
            S|s) _igor_load_module "setup" 2>/dev/null; menu_my_setup ;;
            1)   _mod_my_status ;;
            2)   _igor_load_module "services" 2>/dev/null; menu_my_services ;;
            3)   _igor_load_module "maintenance" 2>/dev/null; menu_my_maintenance ;;
            B|b|"") return 0 ;;
        esac
    done
}
```

**Do not call `menu_my_module()` from any hook.** Menu functions contain `while true` loops and `read` calls that will hang any hook's subshell or non-interactive context.

### The `menus/` pattern

For modules with multiple interactive screens, split each screen into its own file under `menus/`. This keeps `module.sh` lean and loads UI code only when needed.

`_igor_load_module` searches in order:
1. `modules/<name>.sh`
2. `modules/*/<name>.sh` — module root (simple modules with files at root)
3. `modules/*/*/<name>.sh` — module subdirectory (e.g. `nextcloud_docker/menus/services.sh`)

So `_igor_load_module "services"` finds `menus/services.sh` automatically.

**Path resolution inside `menus/` files**

Files in `menus/` are one directory deeper than the module root. Adjust `BASH_SOURCE[0]`-based path resolution accordingly:

```bash
# In menus/services.sh — resolve module root and Igor root:
_mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # → my_module/
_root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"          # → igor root
_stacks="${IGOR_STACKS:-${_root}/config/stacks}"
```

Compare with `module.sh` at the module root (no `..` needed for `_mod_dir`):

```bash
# In module.sh — BASH_SOURCE[0] is already at the module root:
_mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"      # → my_module/
_root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"          # → igor root
```

**Sourcing sub-files from `module.sh`**

If `module.sh` needs to source a `menus/` file eagerly (e.g. for a file that defines hook functions), use `IGOR_DIR`:

```bash
source "${IGOR_DIR}/modules/my_module/menus/tunnel_integration.sh"
source "${IGOR_DIR}/modules/my_module/menus/recovery.sh"
```

Never use `source menus/file.sh` — relative paths depend on the working directory, which is not guaranteed.

---

## Path Resolution

Use `_igor_resolve_dir` to get canonical paths to Igor's runtime directories. Never hardcode paths:

```bash
_igor_resolve_dir runtime    # → $IGOR_DIR/data/runtime   (IPC, FIFOs)
_igor_resolve_dir sessions   # → $IGOR_DIR/data/sessions  (AI session logs)
_igor_resolve_dir alerts     # → $IGOR_DIR/data/alerts    (health cache, pending alerts)
_igor_resolve_dir patterns   # → $IGOR_DIR/config/patterns  (learned .pattern files)
_igor_resolve_dir reports    # → $IGOR_DIR/data/reports   (health/diagnose reports)
_igor_resolve_dir knowledge  # → $IGOR_DIR/config/knowledge  (primer.md, wip.md)
_igor_resolve_dir backups    # → $IGOR_DIR/data/backups   (full backup snapshots)
_igor_resolve_dir secrets    # → $IGOR_DIR/secrets        (credentials)
_igor_resolve_dir recovery   # → $IGOR_DIR/data/recovery  (recovery artefacts)
```

Each path is overridable via `IGOR_<TYPE>_DIR` env var before sourcing:

```bash
export IGOR_BACKUPS_DIR=/mnt/external/igor_backups
```

### Stack directory

If `module.conf` declares `stack_dir=my_service`, the loader exports:

```bash
MY_MODULE_STACK_DIR=/path/to/config/stacks/my_service
```

The naming convention: `<MODULE_NAME_UPPERCASE>_STACK_DIR` with hyphens converted to underscores. Use this in all compose commands to avoid path-from-wrong-directory bugs:

```bash
docker compose -f "${MY_MODULE_STACK_DIR}/docker-compose.yml" ps
```

---

## Module Loader API

Functions available to all modules after `module_loader.sh` is sourced:

```bash
# Check if a binary is available on PATH
igor_has_bin docker          # → 0 (found) or 1 (not found)

# Check if a module is enabled and successfully active
igor_has_module system       # → 0 (loaded) or 1 (not loaded)

igor_active_modules          # print active module names
igor_has_capability docker   # active module declares provides=docker

# Register a hook function
igor_register_hook "health" "my_module__health"

# Get functions registered for a hook (one per line)
igor_get_hooks "health"

# Run all functions for a hook (subshell, 30s timeout each)
igor_run_all_hooks "health"
igor_run_all_hooks "backup" "$snapshot_dir"   # args forwarded to each hook fn

# Load a module on demand (idempotent)
igor_load_module "my_module"

# Register a main menu item
igor_register_menu_item "m" "MY MODULE" "module" "my_module" "menu_my_module"

# Load the capability catalog from ai_capabilities hooks
igor_load_capabilities   # populates _IGOR_CAPABILITIES

# Load/validate config for a specific module
igor_validate_module_config "my_module"
```

### Global data structures

```bash
# All registered hooks
_IGOR_HOOKS["hook_name"]="fn1 fn2 fn3"

# All loaded modules
_IGOR_LOADED_MODULES["my_module"]=1

# All discovered module directories
_IGOR_MODULE_DIRS["my_module"]="/path/to/modules/my_module"

# AI capability catalog (populated by igor_load_capabilities)
_IGOR_CAPABILITIES["action_name"]="description|function|load_module|tier|problems|menu_path"

# Main menu registry
_IGOR_MENU_REGISTRY["m"]="label|module|my_module|menu_my_module"
```

---

## Function Naming Conventions

| Prefix | Scope | Example |
|--------|-------|---------|
| `<name>__` | Public module API, hooks | `nextcloud_docker__health()` |
| `_mod_<short>_` | Module-internal helpers | `_mod_maint_scan_files()` |
| `menu_` | Interactive menu functions | `menu_my_module()` |
| `_igor_` | Igor core internals | `_igor_resolve_dir()` |
| `igor_` | Igor public API | `igor_load_module()` |
| `_` prefix only | Hook implementations (named after their purpose) | `_nc_health_gate()` |

**Never use unprefixed function names** in a module — they collide with core functions and other modules. The only exception is `run_check()` inside check plugin files (each check runs in its own subshell).

---

## Complete Minimal Module Example

A complete, working module with the most common hooks:

**`modules/my_service/module.conf`:**
```ini
[module]
name=my_service
display_name=My Service
version=1.0.0
description=Manages my_service on Docker
requires_core=1.0.0
depends_on=system
menu_section=My Domain
menu_priority=60
menu_items=m:MY SERVICE
stack_dir=my_service

[config]
variables_file=config/variables/my_service.env
secrets_files=secrets/my_service.env

[dependencies]
required_bins=curl
optional_bins=docker:docker.io:Docker Engine
required_modules=system
```

**`config/variables/my_service.env`:**
```bash
MY_SERVICE_PORT=9000
```

Create `secrets/my_service.env` locally with mode `600` (or run the install
lifecycle below). Do not commit real credentials.

**`modules/my_service/module.sh`:**
```bash
#!/bin/bash
# =============================================================================
#  MODULE: my_service
# =============================================================================

my_service__register() {
    igor_register_menu_item "m" "MY SERVICE" "module" "my_service" "menu_my_service"
    igor_register_hook "health"          "my_service__health"
    igor_register_hook "status_line"     "my_service__status_line"
    igor_register_hook "diagnose"        "my_service__diagnose"
    igor_register_hook "ai_context"      "my_service__ai_context"
    igor_register_hook "ai_knowledge"    "my_service__ai_knowledge"
    igor_register_hook "ai_tiers"        "my_service__ai_tiers"
    igor_register_hook "ai_capabilities" "my_service__ai_capabilities"
    igor_register_hook "backup"          "my_service__backup"
    igor_register_hook "restore"         "my_service__restore"
    igor_register_hook "notify_events"   "my_service__notify_events"
    igor_register_hook "config_validate" "_my_service_validate_config"
    return 0
}

my_service__health() {
    local port="${MY_SERVICE_PORT:-9000}"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 3 "http://localhost:${port}/health" 2>/dev/null)
    [ "$code" = "200" ] \
        && echo "ok:running on port ${port}" \
        || echo "fail:HTTP ${code:-timeout} on port ${port}"
}

my_service__status_line() {
    local GRN='\033[0;32m' RED='\033[0;31m' NC='\033[0m'
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 2 "http://localhost:${MY_SERVICE_PORT:-9000}/health" 2>/dev/null)
    [ "$code" = "200" ] \
        && echo -e "  MyService : ${GRN}● RUNNING${NC}" \
        || echo -e "  MyService : ${RED}● DOWN (HTTP ${code:-timeout})${NC}"
}

my_service__diagnose() {
    local _stack="${MY_SERVICE_STACK_DIR:-${IGOR_DIR}/config/stacks/my_service}"

    [[ -d "$_stack" ]] \
        && echo "CHECK:stack_dir:ok:stack dir present" \
        || { echo "CHECK:stack_dir:fail:${_stack} missing — run setup"; return 0; }

    [[ -f "${IGOR_DIR}/secrets/my_service.env" ]] \
        && echo "CHECK:secrets:ok:secrets/my_service.env present" \
        || echo "CHECK:secrets:fail:secrets/my_service.env missing"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 "http://localhost:${MY_SERVICE_PORT:-9000}/health" 2>/dev/null)
    [ "$code" = "200" ] \
        && echo "CHECK:http:ok:HTTP 200 from /health" \
        || echo "CHECK:http:fail:HTTP ${code:-timeout} — service not responding"
}

my_service__ai_context() {
    echo ""
    echo "=== MY SERVICE ==="
    echo "Port: ${MY_SERVICE_PORT:-9000}"
    echo "Data: ${MY_SERVICE_DATA:-not configured}"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 3 "http://localhost:${MY_SERVICE_PORT:-9000}/health" 2>/dev/null)
    echo "HTTP /health: ${code}"
}

my_service__ai_knowledge() {
    cat << EOF
━━━ MY SERVICE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Stack dir: ${MY_SERVICE_STACK_DIR:-${IGOR_DIR}/config/stacks/my_service}
Port: ${MY_SERVICE_PORT:-9000}

All compose commands: docker compose -f <stack_dir>/docker-compose.yml <cmd>

TIER RULES:
  READ: docker compose ps, logs, curl health check
  CHANGE: docker compose restart, config changes, cache flush
  DESTROY: docker compose down --volumes, rm -rf
EOF
}

my_service__ai_tiers() {
    cat << 'EOF'
MY SERVICE TIER RULES:
READ:   docker compose ps/logs, curl health, config reads
CHANGE: docker compose restart, config set, cache flush
DESTROY: docker compose down --volumes, data wipe
EOF
}

my_service__ai_capabilities() {
    cat << 'EOF'
ACTION health_check
DESCRIPTION Quick health check — HTTP probe and container status
FUNCTION _mod_my_service_health_check
LOAD_MODULE my_service
TIER READ
PROBLEMS down, unreachable, not responding, 502, health
MENU_PATH [3] DIAGNOSE → HEALTH CHECK
EOF
}

_mod_my_service_health_check() {
    local port="${MY_SERVICE_PORT:-9000}"
    echo "HTTP /health: $(curl -s -o /dev/null -w '%{http_code}' \
        --max-time 5 "http://localhost:${port}/health" 2>/dev/null)"
    docker compose -f "${MY_SERVICE_STACK_DIR:-}/docker-compose.yml" ps 2>/dev/null || \
        docker compose ps 2>/dev/null
}

my_service__backup() {
    local snapshot_dir="${1:-}"
    local dest="${snapshot_dir}/modules/my_service"
    [ -z "$snapshot_dir" ] && return 1
    mkdir -p "$dest"
    local _stack="${MY_SERVICE_STACK_DIR:-${IGOR_DIR}/config/stacks/my_service}"
    [ -f "${_stack}/docker-compose.yml" ] && \
        cp "${_stack}/docker-compose.yml" "${dest}/" && \
        echo "  ✔ docker-compose.yml saved"
}

my_service__restore() {
    local backup_dir="${1:-}"
    local src="${backup_dir}/modules/my_service"
    [ -d "$src" ] || return 0
    local _stack="${MY_SERVICE_STACK_DIR:-${IGOR_DIR}/config/stacks/my_service}"
    mkdir -p "$_stack"
    [ -f "${src}/docker-compose.yml" ] && \
        cp "${src}/docker-compose.yml" "${_stack}/" && \
        echo "  ✔ docker-compose.yml restored"
}

my_service__notify_events() {
    echo "EVENT|my_service_down|Service stopped unexpectedly|MY_SERVICE_DOWN|true|critical"
    echo "EVENT|my_service_update|New version available|MY_SERVICE_UPDATE|true|info"
}

_my_service_validate_config() {
    [ -z "${MY_SERVICE_PORT:-}" ] && \
        echo "  [igor] WARNING: MY_SERVICE_PORT not set — using default 9000" >&2
}

my_service__install() {
    local _mod_dir; _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local _stack="${MY_SERVICE_STACK_DIR:-${IGOR_DIR}/config/stacks/my_service}"
    if [[ -d "$_stack" ]]; then
        echo "Stack already exists at ${_stack}/ — skipping."
        return 0
    fi
    mkdir -p "$_stack"
    [ -f "${_mod_dir}/defaults/docker-compose.yml" ] && \
        cp "${_mod_dir}/defaults/docker-compose.yml" "$_stack/"
    local _secrets="${IGOR_DIR}/secrets/my_service.env"
    if [[ ! -f "$_secrets" ]]; then
        printf '# my_service secrets — fill in before starting\nMY_SERVICE_DB_PASS=changeme\n' \
            > "$_secrets"
        chmod 600 "$_secrets"
    fi
    echo "my_service bootstrapped at ${_stack}/"
}

menu_my_service() {
    while true; do
        clear
        declare -f header &>/dev/null && header
        echo ""
        echo "  1  STATUS"
        echo "  2  SERVICES"
        echo "  B  BACK"
        echo ""
        local choice
        read -rp "  Choice: " choice </dev/tty
        case "$choice" in
            1) _mod_my_service_health_check; declare -f pause &>/dev/null && pause ;;
            B|b|"") return 0 ;;
        esac
    done
}
```

**`modules/my_service/checks/my_service_health.sh`:**
```bash
#!/bin/bash
CHECK_NAME="my_service_health"
CHECK_DESCRIPTION="HTTP health probe and container check"
CHECK_SCHEDULE="60"

# PATTERN_HINT my_service_container_down "my_service container not running" CHANGE "docker compose up -d my_svc"

run_check() {
    if ! command -v docker &>/dev/null; then
        echo "CHECK_RESULT FAIL my_svc_no_docker Docker not available"
        return 0
    fi

    local running
    running=$(docker compose ps --status running --services 2>/dev/null \
        | grep -c "my_svc" || echo 0)
    if [ "${running:-0}" -eq 0 ]; then
        echo "CHECK_RESULT FAIL my_svc_down my_svc container is not running"
        return 0
    fi
    echo "CHECK_RESULT OK my_svc_running my_svc container running"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 "http://localhost:${MY_SERVICE_PORT:-9000}/health" 2>/dev/null)
    [ "$code" = "200" ] \
        && echo "CHECK_RESULT OK my_http HTTP 200 from /health" \
        || echo "CHECK_RESULT WARN my_http HTTP ${code:-timeout} from /health"
}
```


## Validation before contributing

Run `bash -n` on changed shell scripts, `bats tests/modules/`, and
`bash tests/run_all.sh` from the repository root. Use ShellCheck with the CI
flags in `.github/workflows/ci.yml`; run `ruff check .` for Python changes.
The test runner skips BATS when unavailable, so inspect skips as well as status.
Manifest tests discover modules automatically; hook contract tests name modules
explicitly. Add probes for new modules, including actual dispatcher execution.
Some existing tests require `nextcloud_docker` even when absent from the checkout.

See [CONTRIBUTING.md](CONTRIBUTING.md) for review expectations. The architecture
split is incomplete: core diagnostics and some system checks still contain
Nextcloud assumptions. Keep new service-specific behavior in its module.
