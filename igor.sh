#!/bin/bash
# ==============================================================================
#  IGOR — Main Entry Point
#  I Guard. Observe. Repair.
#
#  Version: 1.0.0
#  License: GPL v3
# ==============================================================================

set -o pipefail

# Boundary I: capture the backend entry point before normal startup work.  The
# standalone TUI exports IGOR_TUI_STARTED_MS immediately before forking this
# backend, so these observations can account for PTY spawn/exec separately from
# the shell bootstrap that follows.  Timing is diagnostic only.
if [ "${IGOR_TUI_MODE:-false}" = true ]; then
    _IGOR_TUI_BACKEND_ENTRY_MS=$(date +%s%3N)
    if [[ "${IGOR_TUI_STARTED_MS:-}" =~ ^[0-9]+$ ]] &&
       [[ "$_IGOR_TUI_BACKEND_ENTRY_MS" =~ ^[0-9]+$ ]] &&
       [ "$_IGOR_TUI_BACKEND_ENTRY_MS" -ge "$IGOR_TUI_STARTED_MS" ]; then
        _IGOR_TUI_BACKEND_SPAWN_MS=$((_IGOR_TUI_BACKEND_ENTRY_MS - IGOR_TUI_STARTED_MS))
    fi
fi

# ── Script directory detection ───────────────────────────────────────────────────────
export IGOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The UI, AI session, and private runtime belong to the invoking user. Root
# execution would mix root state with a user's checkout and runtime directory.
if [[ "${BASH_SOURCE[0]}" == "$0" ]] && [ "$(id -u)" -eq 0 ]; then
    printf 'Igor is intended to run as a normal user. Privileged operations elevate when required.\nRun: bash igor.sh\n' >&2
    exit 1
fi

# ── Directory layout exports ────────────────────────────────────────────────────────
# IGOR_STACKS: user-editable service configs — one subdirectory per module stack.
# Overridable at runtime: IGOR_STACKS=/custom/path bash igor.sh
export IGOR_STACKS="${IGOR_STACKS:-${IGOR_DIR}/config/stacks}"

# Module policy management must precede startup: disabling a module must not
# source its code, run its validators, or create a tmux session first.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        --learning)
            # Reference discovery/review only; bypass all operational startup.
            source "${IGOR_DIR}/core/lib/local_learning.sh"
            [ "$#" -le 3 ] || exit 2
            igor_learning_cli "${2:-status}" "${3:-}"
            exit $?
            ;;
        --deployments)
            # Query the owning registry before any module/config startup.
            source "${IGOR_DIR}/core/lib/deployments.sh"
            [ "$#" -le 3 ] || exit 2
            igor_deployment_cli "${2:-status}" "${3:-}"
            exit $?
            ;;
        --configuration)
            source "${IGOR_DIR}/core/lib/configuration.sh"
            igor_configuration_cli "${2:-status}" "${3:-}"
            exit $?
            ;;
        --ai-tui)
            if [ ! -t 0 ] || [ ! -t 1 ]; then
                printf 'The AI TUI needs an interactive terminal. Use bash igor.sh for the classic UI.\n' >&2
                exit 2
            fi
            if command -v python3 >/dev/null 2>&1; then
                exec python3 "${IGOR_DIR}/core/ai/tui.py"
            elif command -v python >/dev/null 2>&1 &&
                 python --version 2>&1 | grep -q '^Python 3'; then
                exec python "${IGOR_DIR}/core/ai/tui.py"
            fi
            printf 'Python 3 is required for the AI TUI. Use bash igor.sh for the classic UI.\n' >&2
            exit 2
            ;;
        --ai)
            source "${IGOR_DIR}/core/lib/config_loader.sh"
            source "${IGOR_DIR}/core/lib/module_loader.sh"
            source "${IGOR_DIR}/core/ai/control.sh"
            igor_load_config >/dev/null
            case "${2:-status}" in
                status|tools)
                    # These are machine-readable inspection interfaces. Module
                    # availability still affects the catalog, but optional
                    # dependency/config warnings must not pollute the interface.
                    IGOR_STRUCTURED_OUTPUT=true
                    export IGOR_STRUCTURED_OUTPUT
                    igor_load_all_modules >/dev/null
                    igor_load_capabilities >/dev/null
                    if [[ "${2:-status}" == tools ]]; then
                        ai_catalog_json | python3 "${_AI_CONTROL_DIR}/operations.py" scrub
                    else
                        ai_catalog_json | python3 "${_AI_CONTROL_DIR}/operations.py" status
                    fi
                    ;;
                last) python3 "${_AI_CONTROL_DIR}/operations.py" last ;;
                *) printf 'Usage: bash igor.sh --ai [status|tools|last]\n' >&2; exit 1 ;;
            esac
            exit $?
            ;;
        --model)
            source "${IGOR_DIR}/core/lib/config_loader.sh"
            source "${IGOR_DIR}/core/lib/module_loader.sh"
            source "${IGOR_DIR}/core/lib/health_runner.sh"
            igor_load_config >/dev/null
            igor_load_all_modules >/dev/null
            case "${2:-facts}" in
                facts) igor_model_list "${3:-}" "${4:-}" "${5:-}" ;;
                observers) igor_observer_inspect "${3:-}" ;;
                fact)
                    [ "$#" -ge 4 ] || { printf 'Usage: bash igor.sh --model fact OBJECT PROPERTY [STATE_CLASS]\n' >&2; exit 2; }
                    igor_model_read "$3" "$4" "${5:-observed}" ;;
                refresh)
                    igor_observer_refresh "${3:-host.memory}" "${4:-host:local}" || exit 1
                    igor_model_list ;;
                evaluate)
                    igor_health_run_v2_check "${3:-host.memory.health}" || exit 1 ;;
                health) igor_health_inspect "${3:-}" ;;
                summary) igor_health_summary ;;
                *) printf 'Usage: bash igor.sh --model [facts|fact|observers|refresh|evaluate|health|summary]\n' >&2; exit 2 ;;
            esac
            exit $?
            ;;
        --capabilities)
            source "${IGOR_DIR}/core/lib/config_loader.sh"
            source "${IGOR_DIR}/core/lib/module_loader.sh"
            igor_load_config >/dev/null
            igor_load_all_modules >/dev/null
            igor_load_capabilities >/dev/null
            case "${2:-list}" in
                list) igor_capability_list ;;
                inspect)
                    [ "$#" -ge 3 ] || { printf 'Usage: bash igor.sh --capabilities inspect ID [PROVIDER]\n' >&2; exit 2; }
                    igor_capability_inspect "$3" "${4:-}" ;;
                plan)
                    [ "$#" -eq 3 ] || { printf 'Usage: bash igor.sh --capabilities plan PLAN_JSON\n' >&2; exit 2; }
                    igor_capability_plan_resolve "$3" ;;
                *) printf 'Usage: bash igor.sh --capabilities [list|inspect ID [PROVIDER]|plan PLAN_JSON]\n' >&2; exit 2 ;;
            esac
            exit $?
            ;;
        --investigations)
            # Knowledge organization only; no module, observer or AI startup.
            source "${IGOR_DIR}/core/lib/investigations.sh"
            [ "$#" -le 3 ] || exit 2
            igor_investigation_cli "${2:-list}" "${3:-}"
            exit $?
            ;;
        --history)
            # Inspection bypasses module/config startup and never refreshes or
            # verifies implicitly. Explicit recovery loads current contracts.
            source "${IGOR_DIR}/core/lib/operational_history.sh"
            if [ "${2:-recent}" = recover ]; then
                source "${IGOR_DIR}/core/lib/config_loader.sh"
                source "${IGOR_DIR}/core/lib/module_loader.sh"
                igor_load_config >/dev/null
                igor_load_all_modules >/dev/null
                igor_load_capabilities >/dev/null
            fi
            [ "$#" -le 3 ] || exit 2
            igor_history_cli "${2:-recent}" "${3:-}"
            exit $?
            ;;
        --baselines)
            # Read-only derived learning projection over canonical History.
            # No module/config startup, observer refresh or execution authority.
            source "${IGOR_DIR}/core/lib/baselines.sh"
            igor_baseline_cli "${2:-list}" "${3:-}" "${4:-}"
            exit $?
            ;;
        --events)
            source "${IGOR_DIR}/core/lib/config_loader.sh"
            source "${IGOR_DIR}/core/lib/module_loader.sh"
            igor_load_config >/dev/null
            igor_load_all_modules >/dev/null
            case "${2:-types}" in
                types) igor_domain_event_types ;;
                recent) igor_domain_event_recent "${3-}" ;;
                *) printf 'Usage: bash igor.sh --events [types|recent [FILTERS_JSON]]\n' >&2; exit 2 ;;
            esac
            exit $?
            ;;
        --automations)
            source "${IGOR_DIR}/core/lib/config_loader.sh"
            source "${IGOR_DIR}/core/lib/module_loader.sh"
            source "${IGOR_DIR}/core/lib/automation.sh"
            igor_load_config >/dev/null
            igor_load_all_modules >/dev/null
            igor_load_capabilities >/dev/null
            case "${2:-list}" in
                run-due)
                    [ "$#" -le 3 ] || exit 2
                    source "${IGOR_DIR}/core/ai/safety.sh"
                    igor_automation_run_due "${3:-}" ;;
                proposals|list) [ "$#" -eq 2 ] || [ "$#" -eq 1 ] || exit 2
                    igor_automation_cli "${2:-list}" ;;
                inspect|create|enable|disable|delete|reset)
                    [ "$#" -eq 3 ] || { printf 'Usage: bash igor.sh --automations %s ARGUMENT\n' "$2" >&2; exit 2; }
                    igor_automation_cli "$2" "$3" ;;
                edit)
                    [ "$#" -eq 4 ] || { printf 'Usage: bash igor.sh --automations edit ID CONFIG_JSON\n' >&2; exit 2; }
                    igor_automation_cli edit "$3" "$4" ;;
                *) printf 'Usage: bash igor.sh --automations [proposals|list|inspect ID|create CONFIG_JSON|enable ID|disable ID|edit ID CONFIG_JSON|delete ID|reset ID|run-due [Guide|Assist|Executive]]\n' >&2; exit 2 ;;
            esac
            exit $?
            ;;
        --context)
            case "${2:-}" in
                last)
                    [ "$#" -eq 2 ] || exit 2
                    python3 "${IGOR_DIR}/core/ai/operations.py" decision-last
                    exit $? ;;
                select)
                    [ "$#" -eq 3 ] || exit 2
                    printf '%s' "$3" | python3 "${IGOR_DIR}/core/ai/request_context.py" select
                    exit $? ;;
            esac
            source "${IGOR_DIR}/core/lib/config_loader.sh"
            source "${IGOR_DIR}/core/lib/module_loader.sh"
            source "${IGOR_DIR}/core/ai/context.sh"
            igor_load_config >/dev/null
            igor_load_all_modules >/dev/null
            case "${2:-}" in
                inspect) ai_context_inspect ;;
                *) printf 'Usage: bash igor.sh --context inspect\n' >&2; exit 2 ;;
            esac
            exit $?
            ;;
        --enable|--disable|--modules)
            if [[ "$1" == --modules ]] && [[ "${2:-}" == inspect || "${2:-}" == detach-plan ]]; then
                [ "$#" -eq 3 ] || { printf 'Usage: bash igor.sh --modules %s NAME\n' "$2" >&2; exit 2; }
                # Package inspection is data-only: no config migration, module
                # source, observer refresh, or disposable runtime initialization.
                python3 "${IGOR_DIR}/core/lib/module_inspection.py" "$2" "$IGOR_DIR" "$3"
                exit $?
            fi
            source "${IGOR_DIR}/core/lib/module_loader.sh"
            if [[ "$1" == --modules ]]; then
                source "${IGOR_DIR}/core/lib/config_loader.sh"
                igor_load_config >/dev/null
                igor_load_all_modules >/dev/null
                igor_load_capabilities >/dev/null
                igor_module_list
                exit $?
            fi
            if [[ $# != 2 ]]; then
                printf 'Usage: bash igor.sh %s <module_name>\n' "$1" >&2
                exit 1
            fi
            igor_discover_modules >/dev/null
            _igor_requested_state=enabled
            [[ "$1" == --disable ]] && _igor_requested_state=disabled
            igor_module_set_enabled "$2" "$_igor_requested_state"
            exit $?
            ;;
    esac
fi

# ── Distro detection (must run before any pkg_install or Python calls) ────────────
source "${IGOR_DIR}/core/lib/distro.sh"
igor_detect_distro

# ── Package manager abstraction ────────────────────────────────────────────────────
source "${IGOR_DIR}/core/lib/pkg.sh"

# ── Python 3 resolution ────────────────────────────────────────────────────────────
# On Arch Linux, the Python 3 binary is named 'python', not 'python3'.
# Resolve whichever is Python 3 and export IGOR_PYTHON for the AI layer.
# Also create a session-scoped shim so that all subshells see 'python3' as a command
# (avoids touching the ~150 python3 call-sites across the codebase).
if command -v python3 &>/dev/null; then
    export IGOR_PYTHON="python3"
elif command -v python &>/dev/null \
        && python --version 2>&1 | grep -q "^Python 3"; then
    export IGOR_PYTHON="python"
    # PATH shim: create a temp dir with a python3 symlink so every subshell
    # that calls 'python3' finds the binary, without patching each call-site.
    _IGOR_SHIM_DIR=$(mktemp -d 2>/dev/null) || _IGOR_SHIM_DIR=""
    if [ -n "$_IGOR_SHIM_DIR" ]; then
        ln -s "$(command -v python)" "${_IGOR_SHIM_DIR}/python3" 2>/dev/null || true
        ln -s "$(command -v python)" "${_IGOR_SHIM_DIR}/python3.x" 2>/dev/null || true
        export PATH="${_IGOR_SHIM_DIR}:${PATH}"
        # shellcheck disable=SC2064
        trap "rm -rf '${_IGOR_SHIM_DIR}'" EXIT
    fi
    unset _IGOR_SHIM_DIR
else
    echo "  [fatal] Python 3 not found. Install it and re-run Igor." >&2
    echo "          Arch: sudo pacman -S python   Debian: sudo apt install python3" >&2
    exit 1
fi

# Resolve pip (IGOR_PIP used by any module that needs to pip-install at runtime)
if command -v pip3 &>/dev/null; then
    export IGOR_PIP="pip3"
elif command -v pip &>/dev/null \
        && pip --version 2>&1 | grep -q "python 3"; then
    export IGOR_PIP="pip"
else
    export IGOR_PIP="${IGOR_PYTHON} -m pip"
fi

# ── Source library files ───────────────────────────────────────────────────────────
source "${IGOR_DIR}/core/lib/ui.sh"
source "${IGOR_DIR}/core/lib/helpers.sh"
source "${IGOR_DIR}/core/lib/config.sh"
source "${IGOR_DIR}/core/lib/cloudflare_ips.sh"

# ── Source security hardening modules ───────────────────────────────────────────────
source "${IGOR_DIR}/core/lib/input_validation.sh"
source "${IGOR_DIR}/core/lib/path_resolution.sh"
source "${IGOR_DIR}/core/lib/file_locking.sh"
source "${IGOR_DIR}/core/lib/resource_management.sh"
source "${IGOR_DIR}/core/lib/error_handling.sh"
source "${IGOR_DIR}/core/lib/atomic_file_ops.sh"
source "${IGOR_DIR}/core/lib/security_config.sh"

# ── Tmux awareness layer ──────────────────────────────────────────────────────
# Sourced early — defines functions only (no side effects, no config reads).
# igor_setup_features() runs later, after igor_load_config populates IGOR_USE_TMUX.
source "${IGOR_DIR}/core/lib/tmux.sh"
source "${IGOR_DIR}/core/lib/session.sh"

# Pre-init: _IGOR_FZF_AVAILABLE and _IGOR_RICH_AVAILABLE default to false until
# igor_setup_features() runs after config is loaded.
_IGOR_FZF_AVAILABLE=false
_IGOR_RICH_AVAILABLE=false

# ── Auto-enter tmux session (before any output) ───────────────────────────────
# Quick-read IGOR_USE_TMUX from igor.env before the full config system loads.
# If true and not already in tmux, igor_ensure_session does exec (no return).
# Skip for sub-modes that run inside an existing pane: --extra, --status,
# --help, --capture, --tune, --check (those must never try to create a session).
_IGOR_SKIP_SESSION=false
for _a in "$@"; do
    case "$_a" in
        --extra|--status|--help|-h|--capture|--tune|--check|--ai-tui-backend)
            _IGOR_SKIP_SESSION=true; break ;;
    esac
done
if [ "$_IGOR_SKIP_SESSION" = "false" ] && [ -z "${IGOR_USE_TMUX+x}" ]; then
    _qtv=$(grep "^IGOR_USE_TMUX=" "${IGOR_DIR}/config/variables/igor.env" 2>/dev/null \
        | head -1 | cut -d= -f2)
    [ -n "$_qtv" ] && export IGOR_USE_TMUX="$_qtv"
    unset _qtv
fi
[ "$_IGOR_SKIP_SESSION" = "false" ] && igor_ensure_session "$@"
unset _a
# _IGOR_SKIP_SESSION kept alive — used below to gate igor_layout_standard

# ── Sub-mode startup silence ──────────────────────────────────────────────────
# --extra / --status / --capture etc. run inside existing tmux panes.
# The full startup sequence (module loading, config, feature checks) runs for
# all modes, but sub-modes must not pollute their pane with the same startup
# chatter as the main session.  Save real FDs, redirect to /dev/null, restore
# just before the execution block at the bottom of this file.
if [ "${_IGOR_SKIP_SESSION:-false}" = "true" ]; then
    exec 3>&1 4>&2 >/dev/null 2>&1
    _IGOR_STDOUT_SAVED=true
fi

# ── Source output and extra pane management ───────────────────────────────────
# output.sh: pane 2 lifecycle (igor_output_show/hide/stream/to_pane)
# extra.sh:  pane 4 content (igor_extra_launch, IGOR_EXTRA_CMD support)
# Both are no-ops outside the 4-pane layout (IGOR_PANE_MENU unset).
if [ -f "${IGOR_DIR}/core/lib/output.sh" ]; then
    source "${IGOR_DIR}/core/lib/output.sh"
fi
if [ -f "${IGOR_DIR}/core/lib/extra.sh" ]; then
    source "${IGOR_DIR}/core/lib/extra.sh"
fi

# ── Source healing subsystem ────────────────────────────────────────────────────
if [ -f "${IGOR_DIR}/core/healing/core.sh" ]; then
    source "${IGOR_DIR}/core/healing/core.sh"
else
    # Fallback stub — healing system not available
    calculate_health_score() {
        echo "-1"
    }
fi

# ── Source recovery journal (zero side effects — functions only) ───────────────
# Must be available everywhere (ai_execute_tool, diagnose fixes, menu hooks).
# Sourced unconditionally — all functions are no-ops if JOURNAL_ENABLED=false.
if [ -f "${IGOR_DIR}/core/recovery/journal.sh" ]; then
    source "${IGOR_DIR}/core/recovery/journal.sh"
fi

# ── Source notify subsystem (zero side effects — defines notify_send/notify_event) ──
# INTENTIONAL EXCEPTION to the lazy-load principle: notify_event() is called by
# core/healing/alerts.sh, core/diagnose/fixes.sh, and core/recovery/*.sh — none of which have
# an explicit "load notify" step. Sourcing here avoids requiring every subsystem
# to guard its notify_event calls with declare -f checks.
if [ -f "${IGOR_DIR}/core/notify/core.sh" ]; then
    source "${IGOR_DIR}/core/notify/core.sh"
fi

# ── Module loader (M0 architecture split) ────────────────────────────────────────
# Loads core/lib/config_loader.sh and core/lib/module_loader.sh, then discovers,
# sorts, and loads all modules in modules/*/. Runs silently alongside the existing
# menu system — hooks are registered but not yet called by menu code (parallel phase).
if [ -f "${IGOR_DIR}/core/lib/config_loader.sh" ] && \
   [ -f "${IGOR_DIR}/core/lib/module_loader.sh" ]; then
    source "${IGOR_DIR}/core/lib/config_loader.sh"
    source "${IGOR_DIR}/core/lib/module_loader.sh"

    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _IGOR_TUI_PHASE_STARTED_MS=$(date +%s%3N)
        if [[ "${_IGOR_TUI_BACKEND_ENTRY_MS:-}" =~ ^[0-9]+$ ]] &&
           [ "$_IGOR_TUI_PHASE_STARTED_MS" -ge "$_IGOR_TUI_BACKEND_ENTRY_MS" ]; then
            _IGOR_TUI_BACKEND_PREBOOTSTRAP_MS=$((_IGOR_TUI_PHASE_STARTED_MS - _IGOR_TUI_BACKEND_ENTRY_MS))
        fi
    fi
    igor_load_config      || warn "Config loading reported an error — check core/lib/config_loader.sh"
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _IGOR_TUI_PHASE_ENDED_MS=$(date +%s%3N)
        _IGOR_TUI_BOOTSTRAP_CONFIG_MS=$((_IGOR_TUI_PHASE_ENDED_MS - _IGOR_TUI_PHASE_STARTED_MS))
        _IGOR_TUI_PHASE_STARTED_MS="$_IGOR_TUI_PHASE_ENDED_MS"
    fi

    igor_load_all_modules || warn "Module loading reported an error — check modules/"
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _IGOR_TUI_PHASE_ENDED_MS=$(date +%s%3N)
        _IGOR_TUI_BOOTSTRAP_MODULES_MS=$((_IGOR_TUI_PHASE_ENDED_MS - _IGOR_TUI_PHASE_STARTED_MS))
        _IGOR_TUI_PHASE_STARTED_MS="$_IGOR_TUI_PHASE_ENDED_MS"
    fi

    _cfg_validate_all_loaded_modules
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _IGOR_TUI_PHASE_ENDED_MS=$(date +%s%3N)
        _IGOR_TUI_BOOTSTRAP_MODULE_CONFIG_MS=$((_IGOR_TUI_PHASE_ENDED_MS - _IGOR_TUI_PHASE_STARTED_MS))
        _IGOR_TUI_PHASE_STARTED_MS="$_IGOR_TUI_PHASE_ENDED_MS"
    fi
    # M2-1: diagnose runner — hook-based aggregator available everywhere
    if [ -f "${IGOR_DIR}/core/lib/diagnose_runner.sh" ]; then
        source "${IGOR_DIR}/core/lib/diagnose_runner.sh"
    fi
    if [ -f "${IGOR_DIR}/core/lib/health_runner.sh" ]; then
        source "${IGOR_DIR}/core/lib/health_runner.sh"
    fi
    # M2-3: notify aggregator
    if [ -f "${IGOR_DIR}/core/notify/aggregator.sh" ]; then
        source "${IGOR_DIR}/core/notify/aggregator.sh"
    fi
    # Register tunnel hooks now that igor_register_hook is available
    declare -f _tunnel_register_hooks &>/dev/null && _tunnel_register_hooks

    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _IGOR_TUI_PHASE_ENDED_MS=$(date +%s%3N)
        _IGOR_TUI_BOOTSTRAP_AUX_SOURCES_MS=$((_IGOR_TUI_PHASE_ENDED_MS - _IGOR_TUI_PHASE_STARTED_MS))
        _IGOR_TUI_PHASE_STARTED_MS="$_IGOR_TUI_PHASE_ENDED_MS"
    fi

    # Run module config validators — checks NC-specific required vars after
    # modules are loaded (can't run at config.sh source time, modules not yet loaded).
    if declare -f igor_get_hooks &>/dev/null; then
        _cv_fn=
        for _cv_fn in $(igor_get_hooks "config_validate" 2>/dev/null); do
            declare -f "$_cv_fn" &>/dev/null && "$_cv_fn" 2>&1 >&2 || true
        done
        unset _cv_fn
    fi
    if [ "${IGOR_TUI_MODE:-false}" = true ]; then
        _IGOR_TUI_PHASE_ENDED_MS=$(date +%s%3N)
        _IGOR_TUI_BOOTSTRAP_CONFIG_HOOKS_MS=$((_IGOR_TUI_PHASE_ENDED_MS - _IGOR_TUI_PHASE_STARTED_MS))
        _IGOR_TUI_PHASE_STARTED_MS="$_IGOR_TUI_PHASE_ENDED_MS"
    fi

    # Debug log: emit loaded module names when NEXUS_VERBOSE=true
    if [ "${NEXUS_VERBOSE:-false}" = "true" ] && \
       [ ${#_IGOR_LOADED_MODULES[@]} -gt 0 ]; then
        _loaded_names="$(IFS=', '; echo "${!_IGOR_LOADED_MODULES[*]}")"
        printf '[module_loader] Loaded modules: %s\n' "$_loaded_names" >&2
    fi
else
    # Fallback: config_loader not present — source igor.env directly so
    # IGOR_USE_TMUX and IGOR_FZF_ALREADY_ASKED are available for igor_setup_features.
    if [ -f "${IGOR_DIR}/config/variables/igor.env" ]; then
        set -a; source "${IGOR_DIR}/config/variables/igor.env"; set +a
    fi
fi

# ── Feature availability setup ────────────────────────────────────────────────
# Must run AFTER config loading so IGOR_USE_TMUX / IGOR_FZF_ALREADY_ASKED are set.
# The standalone curses TUI owns its own interaction surface and never uses the
# tmux/fzf/rich startup probe; skipping that probe also prevents an unrelated
# package-install prompt from blocking the backend PTY.
if [ "${IGOR_TUI_MODE:-false}" != true ]; then
    igor_setup_features
fi

# ── Startup alert banner ──────────────────────────────────────────────────────
# Show pending alerts while startup output is still on screen — BEFORE
# igor_layout_standard reorganises/clears the terminal.
# main_menu() skips the duplicate check when _IGOR_STARTUP_ALERT_SHOWN=true.
_IGOR_STARTUP_ALERT_SHOWN=false
if [ "${_IGOR_SKIP_SESSION:-false}" = "false" ] && declare -f _igor_resolve_dir &>/dev/null; then
    _startup_pending="$(_igor_resolve_dir "alerts")/pending.log"
    if [ -f "$_startup_pending" ] && [ -s "$_startup_pending" ]; then
        echo ""
        if declare -f alert_show_pending &>/dev/null; then
            alert_show_pending
        else
            echo -e "  ${RED:-}${BOLD:-}⚠  IGOR ALERTS PENDING${NC:-}"
            cat "$_startup_pending"
        fi
        _IGOR_STARTUP_ALERT_SHOWN=true
    fi
    unset _startup_pending
fi

# ── Disclaimer + startup pause ────────────────────────────────────────────────
if [ "${_IGOR_SKIP_SESSION:-false}" = "false" ]; then
    echo ""
    echo -e "  ${DIM:-}Use this program at your own risk; the creator assumes no responsibility for any outcomes.${NC:-}"
    echo ""
    read -rp "  Press any key to continue..." -n1 -s
    echo ""
    # igor_start notification — fires after modules loaded so notify_event is available
    declare -f notify_event &>/dev/null && \
        notify_event "igor_start" \
            "Igor session started on $(hostname 2>/dev/null || echo 'host')" \
        2>/dev/null || true
fi

# ── 4-pane layout ─────────────────────────────────────────────────────────────
# Only the main interactive session builds the layout. Sub-modes (--extra,
# --status, --capture, etc.) run inside existing panes and must never spawn
# their own panels — that is what caused the infinite-panel recursion.
[ "${_IGOR_SKIP_SESSION:-false}" = "false" ] && igor_layout_standard
unset _IGOR_SKIP_SESSION

# ── Panel system ─────────────────────────────────────────────────────────────
# Source panels.sh so igor_panel_open/close/list/menu are available everywhere.
# _panels_register_all() is lazy — called on first use, not at source time.
if [ -f "${IGOR_DIR}/core/lib/panels.sh" ]; then
    source "${IGOR_DIR}/core/lib/panels.sh"
fi

# ── Tunnel core ───────────────────────────────────────────────────────────────
# Sourced unconditionally so tunnel_* functions are available everywhere
# without a module load call.  Hooks registered after module_loader runs.
if [ -f "${IGOR_DIR}/core/tunnel/tunnel.sh" ]; then
    source "${IGOR_DIR}/core/tunnel/tunnel.sh"
fi

# ── Hardware-tier profiling ────────────────────────────────────────────────────
# Sets IGOR_TIER global (constrained / standard / comfortable / server).
# Reads from cache; auto-detects on first run or after a RAM change.
if [ -f "${IGOR_DIR}/core/host/profile.sh" ]; then
    source "${IGOR_DIR}/core/host/profile.sh"
    igor_load_profile 2>/dev/null || true
fi

# ── Tuning engine ─────────────────────────────────────────────────────────────
# Lazy-loaded on demand (--tune / 'tune' typed command / igor_tune() callers).
# Not sourced at startup — it reads $IGOR_TIER which is set by igor_load_profile.
# Use: declare -f igor_tune >/dev/null || source "${IGOR_DIR}/core/lib/tuning.sh"

# ── Credential scrub engine ───────────────────────────────────────────────────
# Source core/lib/scrub.sh, then register:
#   1. Secrets declared in each loaded module's [secrets] section
#   2. All literal values found in secrets/*.env
# igor_scrub() is then available to ai_scrub_outbound and any other code that
# sends data off-machine.
if [ -f "${IGOR_DIR}/core/lib/scrub.sh" ]; then
    source "${IGOR_DIR}/core/lib/scrub.sh"
    if [ ${#_IGOR_LOADED_MODULES[@]} -gt 0 ]; then
        for _scrub_mod in "${!_IGOR_LOADED_MODULES[@]}"; do
            _scrub_dir="${_IGOR_MODULE_DIRS[$_scrub_mod]:-}"
            [ -n "$_scrub_dir" ] && igor_scrub_load_module_secrets "$_scrub_dir" 2>/dev/null || true
        done
    fi
    unset _scrub_mod _scrub_dir
    igor_scrub_load_secrets_dir "${IGOR_DIR}/secrets" 2>/dev/null || true
fi

# ── Global variables for self-healing ─────────────────────────────────────────────
SELF_HEALING_ISSUES=()
SELF_HEALING_LAST_REPAIR=""
SELF_HEALING_CONFIG_DRIFT=0

# ── Recently used menu tracker ─────────────────────────────────────────────────────
_IGOR_RECENT_FILE="$(_igor_resolve_dir "runtime")/recent_menus.txt"

_igor_record_recent() {
    # _igor_record_recent KEY LABEL  — appends to recent file, keeps last 10 unique
    local key="$1" label="$2"
    [ -z "$key" ] || [ -z "$label" ] && return
    mkdir -p "$(dirname "$_IGOR_RECENT_FILE")" 2>/dev/null || true
    echo "${key}|${label}" >> "$_IGOR_RECENT_FILE" 2>/dev/null || true
    # Trim to last 20 entries (dedup done at display time)
    if [ -f "$_IGOR_RECENT_FILE" ]; then
        local _tmp; _tmp=$(tail -20 "$_IGOR_RECENT_FILE" 2>/dev/null)
        printf '%s\n' "$_tmp" > "$_IGOR_RECENT_FILE" 2>/dev/null || true
    fi
}

# ── Single call target for Igor status messages ───────────────────────────────
# Phase 2 replaces this body with ai_render.py --mode status rendering.
# Current: delegates to ai_render.py if Rich available, falls back to echo.
_igor_print() {
    # Usage: _igor_print "message"
    local _msg="${1:-}"
    local _render="${IGOR_DIR}/core/ai/ai_render.py"
    if ${_IGOR_RICH_AVAILABLE:-false} && [ -f "$_render" ]; then
        python3 "$_render" --mode status "$_msg"
    else
        echo "  $_msg"
    fi
}

_igor_show_recent() {
    # Show last 3 unique recently-used menu items (newest first)
    [ -f "$_IGOR_RECENT_FILE" ] || return
    local _seen=() _count=0
    while IFS='|' read -r rkey rlabel; do
        [ -z "$rkey" ] && continue
        local _dup=0
        [ ${#_seen[@]} -gt 0 ] && for _s in "${_seen[@]}"; do [ "$_s" = "$rkey" ] && { _dup=1; break; }; done
        [ $_dup -eq 1 ] && continue
        _seen+=("$rkey")
        printf "  ${CYAN}%-4s${NC} %s\n" "${rkey})" "${rlabel}"
        _count=$((_count + 1))
        [ $_count -ge 3 ] && break
    done < <(tac "$_IGOR_RECENT_FILE" 2>/dev/null)
}

# ── M2-5: Dynamic menu rendering ─────────────────────────────────────────────────
# Builds menu sections from registered modules. Each module declares its menu
# items in module.conf as: menu_items=KEY:LABEL,KEY:LABEL
# Modules are rendered in menu_priority order. Core section is always appended last.

_igor_module_conf_get() {
    # _igor_module_conf_get <module_name> <key>
    local _mod="$1" _key="$2"
    local _dir="${_IGOR_MODULE_DIRS[$_mod]:-}"
    [ -z "$_dir" ] && return
    grep -m1 "^${_key}[[:space:]]*=" "${_dir}/module.conf" 2>/dev/null \
        | sed 's/^[^=]*=[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

igor_loaded_modules_by_priority() {
    # Print loaded module names sorted by menu_priority (ascending)
    declare -A _pri_map
    local _mod
    for _mod in "${!_IGOR_LOADED_MODULES[@]}"; do
        local _p; _p=$(_igor_module_conf_get "$_mod" "menu_priority")
        _pri_map["$_mod"]="${_p:-50}"
    done
    # Sort by priority value
    for _mod in "${!_pri_map[@]}"; do
        printf '%s %s\n' "${_pri_map[$_mod]}" "$_mod"
    done | sort -n | awk '{print $2}'
}

igor_render_module_menu_section() {
    # Render menu items for one loaded module (plain-text fallback, no fzf).
    # Supports both legacy KEY:LABEL and new label-only formats in module.conf.
    local _mod="$1"
    local _display; _display=$(_igor_module_conf_get "$_mod" "display_name")
    local _section; _section=$(_igor_module_conf_get "$_mod" "menu_section")
    local _items;   _items=$(_igor_module_conf_get   "$_mod" "menu_items")
    [ -z "$_items" ] && return  # module has no menu items — skip

    local _section_label="${_section:-${_display:-$_mod}}"
    echo -e "  ${DIM}── ${_section_label} ─────────────────────────────────────${NC}"

    local _pair _n=1
    local -a _item_list=()
    IFS=',' read -ra _item_list <<< "$_items"
    for _pair in "${_item_list[@]}"; do
        if [[ "$_pair" == *:* ]]; then
            # Legacy KEY:LABEL — use declared key
            printf "  ${CYAN}%s.${NC} %s\n" "${_pair%%:*}" "${_pair#*:}"
        else
            # New label-only — show positional number
            printf "  ${CYAN}%s.${NC} %s\n" "$_n" "$_pair"
            _n=$(( _n + 1 ))
        fi
    done
    echo ""
}

# ── Core subsystem lazy loading helper ──────────────────────────────────────────
# Source a core subsystem (ai, diagnose, mailcmd, notify, recovery) on first use.
# Unlike domain modules, core subsystems live outside modules/ (in core/ai/, core/diagnose/, core/recovery/, etc.)
# and are sourced by explicit path rather than discovered.
_igor_load_subsystem() {
    local subsys_name="$1" subsys_path="$2"
    if [ -z "$(declare -f _igor_loaded_${subsys_name} 2>/dev/null)" ]; then
        if [ ! -f "$subsys_path" ]; then
            fail "Subsystem not found: ${subsys_path}"
            return 1
        fi
        source "$subsys_path"
        declare -g "_igor_loaded_${subsys_name}"="1"
    fi
}

# ── Module lazy loading helper ───────────────────────────────────────────────────
# Source a domain module file on first use. Searches:
#   1. modules/<name>.sh
#   2. modules/*/<name>.sh       (module root — legacy/simple modules)
#   3. modules/*/*/<name>.sh     (module subdirectory, e.g. menus/)
_igor_load_module() {
    local module_name="$1"
    local module_file="${IGOR_DIR}/modules/${module_name}.sh"

    # Search one level deep (module root files)
    if [ ! -f "$module_file" ]; then
        for _candidate in "${IGOR_DIR}/modules/"*"/${module_name}.sh"; do
            [ -f "$_candidate" ] || continue
            if declare -f igor_has_module >/dev/null 2>&1; then
                local _candidate_owner="${_candidate#${IGOR_DIR}/modules/}"
                _candidate_owner="${_candidate_owner%%/*}"
                igor_has_module "$_candidate_owner" || continue
            fi
            module_file="$_candidate"
            break
        done
    fi

    # Search two levels deep (module subdirectories, e.g. menus/)
    if [ ! -f "$module_file" ]; then
        for _candidate in "${IGOR_DIR}/modules/"*"/"*"/${module_name}.sh"; do
            [ -f "$_candidate" ] || continue
            if declare -f igor_has_module >/dev/null 2>&1; then
                local _candidate_owner="${_candidate#${IGOR_DIR}/modules/}"
                _candidate_owner="${_candidate_owner%%/*}"
                igor_has_module "$_candidate_owner" || continue
            fi
            module_file="$_candidate"
            break
        done
    fi

    if [ ! -f "$module_file" ]; then
        # Write to terminal only — not to right pane (right pane is for context data)
        echo -e "  ${RED:-\033[0;31m}✘${NC:-\033[0m} Module not found: ${module_name}.sh" >&2
        return 1
    fi

    # Legacy menu files are owned by the discovered domain module (for
    # example, modules/nextcloud_docker/menus/services.sh).  Keep the lazy
    # loader for compatibility, but never let it revive a disabled or
    # unavailable owner.  The lifecycle loader remains the source of truth for
    # module activation; this check is deliberately fail-closed when it is
    # present.  Older callers that source igor.sh without module_loader.sh keep
    # the historical behaviour.
    if declare -f igor_has_module >/dev/null 2>&1; then
        local _module_owner=""
        if [ -n "${_IGOR_MODULE_DIRS[$module_name]:-}" ]; then
            _module_owner="$module_name"
        elif [[ "$module_file" == "${IGOR_DIR}/modules/"*/*/* ]]; then
            _module_owner="${module_file#${IGOR_DIR}/modules/}"
            _module_owner="${_module_owner%%/*}"
        elif [[ "$module_file" == "${IGOR_DIR}/modules/"*/* ]]; then
            _module_owner="${module_file#${IGOR_DIR}/modules/}"
            _module_owner="${_module_owner%%/*}"
        fi
        if [ -z "$_module_owner" ] || ! igor_has_module "$_module_owner"; then
            echo "  Module '${module_name}' is disabled or unavailable" >&2
            return 1
        fi
    fi

    if [ -z "$(declare -f _igor_loaded_${module_name} 2>/dev/null)" ]; then
        source "$module_file"
        declare -g "_igor_loaded_${module_name}"="1"
        debug "Loaded module: $module_name" 2>/dev/null || true
    fi

    return 0
}



# ── Help page ───────────────────────────────────────────────────────────────────
_igor_show_help() {
    local B='\033[1m' C='\033[0;36m' Y='\033[1;33m' G='\033[0;32m' N='\033[0m'

    echo ""
    echo -e "${B}IGOR${N} — I Guard. Observe. Repair."
    echo -e "Modular self-hosted service platform. Monitors, repairs, and manages your stack."
    echo ""
    echo -e "${C}${B}USAGE${N}"
    echo "  bash igor.sh [OPTIONS]"
    echo ""

    echo -e "${C}${B}CLI FLAGS${N}"
    printf "  ${Y}%-30s${N} %s\n" "--help, -h"          "Show this help page"
    printf "  ${Y}%-30s${N} %s\n" "--ai-tui"            "Launch the full-screen AI chat (classic UI: bash igor.sh)"
    printf "  ${Y}%-30s${N} %s\n" "--diagnose [mode]"   "Run Igor Diagnose (modes: normal deep fix watch report recovery)"
    printf "  ${Y}%-30s${N} %s\n" "--extra"             "Launch the 6-lens monitoring TUI in a second terminal"
    printf "  ${Y}%-30s${N} %s\n" "--status"            "Print current session / worker status and exit"
    printf "  ${Y}%-30s${N} %s\n" "--restart"           "Restart the background worker daemon"
    printf "  ${Y}%-30s${N} %s\n" "--capture"           "Record full terminal output to runtime/terminal.log"
    printf "  ${Y}%-30s${N} %s\n" "--mailcmd heartbeat" "Send daily heartbeat email (used by crontab)"
    printf "  ${Y}%-30s${N} %s\n" "--backup [config|full]" "Run scheduled backup (used by crontab)"
    printf "  ${Y}%-30s${N} %s\n" "--modules"           "List module policy and activation status"
    printf "  ${Y}%-30s${N} %s\n" "--model [facts|fact|observers|refresh|evaluate|health|summary]" "Inspect or refresh Wave D host facts and checks"
    printf "  ${Y}%-30s${N} %s\n" "--events [types|recent]" "Inspect current-session domain event types or recent events"
    printf "  ${Y}%-30s${N} %s\n" "--history [recent|inspect ID]" "Inspect durable operational episodes"
    printf "  ${Y}%-30s${N} %s\n" "--deployments [status|list|inspect ID|export]" "Inspect deployment identity, bindings and responsibility"
    printf "  ${Y}%-30s${N} %s\n" "--investigations [list|inspect ID]" "Inspect durable investigations"
    printf "  ${Y}%-30s${N} %s\n" "--automations [list|proposals]" "Inspect configured automations or active proposals"
    printf "  ${Y}%-30s${N} %s\n" "--ai [status|tools|last]" "Inspect AI policy, capabilities, or last operation"
    printf "  ${Y}%-30s${N} %s\n" "--enable <module>"   "Enable module for the next Igor process"
    printf "  ${Y}%-30s${N} %s\n" "--disable <module>"  "Disable module for the next Igor process"
    echo ""

    echo -e "${C}${B}MAIN MENU${N}"
    echo "  Module menu items are loaded dynamically from installed modules."
    echo "  Core entries (always present):"
    printf "  ${Y}%-6s${N} %s\n" "A"  "IGOR ASSISTANT  — AI-based diagnostics and repair (L=session log inside)"
    printf "  ${Y}%-6s${N} %s\n" "D"  "DIAGNOSE      — Structured multi-phase health diagnosis"
    printf "  ${Y}%-6s${N} %s\n" "R"  "RECOVERY      — Journal, backups, rollback, supervised installs (V=alias)"
    printf "  ${Y}%-6s${N} %s\n" "P"  "COMMUNICATIONS — Sub-menu: 1 Notifications, 2 Remote access"
    printf "  ${Y}%-6s${N} %s\n" "C"  "COMMAND MAIL  — Secure inbound email command channel (GPG)"
    echo ""

    echo -e "${C}${B}IGOR ASSISTANT — Chat Commands${N}"
    printf "  ${Y}%-22s${N} %s\n" "/stop"          "Pause the current agentic task loop"
    printf "  ${Y}%-22s${N} %s\n" "continue, cont" "Resume the loop after /stop or the 5-step limit"
    printf "  ${Y}%-22s${N} %s\n" "refresh"        "Manually refresh server context snapshot"
    printf "  ${Y}%-22s${N} %s\n" "hypo"           "Show current investigation hypothesis"
    printf "  ${Y}%-22s${N} %s\n" "hypo add <txt>" "Inject a hypothesis hint for Igor"
    printf "  ${Y}%-22s${N} %s\n" "hypo clear"     "Clear the hypothesis block"
    printf "  ${Y}%-22s${N} %s\n" "stats"          "Token usage, cost, and context size for this session"
    printf "  ${Y}%-22s${N} %s\n" "restore"        "Restore nginx.conf from the most recent backup"
    printf "  ${Y}%-22s${N} %s\n" "restart web"    "Immediately restart the web container + HTTP check"
    printf "  ${Y}%-22s${N} %s\n" "context"        "Show the current scrubbed server context"
    printf "  ${Y}%-22s${N} %s\n" "verbose on/off" "Toggle verbose explanation display"
    printf "  ${Y}%-22s${N} %s\n" "exec on/off"    "Toggle executive mode (auto-run CHANGE commands)"
    printf "  ${Y}%-22s${N} %s\n" "settings"       "Show / change AI settings (model, provider, etc.)"
    printf "  ${Y}%-22s${N} %s\n" "q, quit, exit"  "Exit the IGOR ASSISTANT"
    echo ""

    echo -e "${C}${B}AI TOOL TAGS — What Igor Can Execute${N}"
    echo "  Igor emits these XML-style tags to take actions on your server."
    echo "  Each tag requires your approval (READ = auto, CHANGE = confirm, DESTROY = type YES)."
    echo ""
    printf "  ${Y}%-50s${N} %s\n" "<host> df -h </host>"                               "Run a host shell command"
    printf "  ${Y}%-50s${N} %s\n" "<occ> maintenance:mode --off </occ>"                "Run an occ command in the app container"
    printf "  ${Y}%-50s${N} %s\n" '<container action="restart"> web </container>'      "Docker Compose lifecycle action"
    printf "  ${Y}%-50s${N} %s\n" '<read_log target="app" lines="20"> error </read_log>' "Read container logs with optional grep"
    printf "  ${Y}%-50s${N} %s\n" '<edit_file path="./web/nginx.conf"><find>...</find><replace>...</replace></edit_file>' "Safe file edit with backup"
    echo ""

    echo -e "${C}${B}AI COMMAND TIERS${N}"
    printf "  ${G}%-12s${N} %s\n" "READ"    "Auto-runs without prompt (docker ps, df -h, occ status, logs…)"
    printf "  ${Y}%-12s${N} %s\n" "CHANGE"  "Shows command, requires y/n (or auto in executive mode)"
    printf "  ${Y}%-12s${N} %s\n" "DESTROY" "Always requires typing YES explicitly — no exceptions"
    echo ""

    echo -e "${C}${B}CONFIGURATION FILES${N}"
    local cfg="${IGOR_DIR}"
    printf "  ${Y}%-40s${N} %s\n" "${cfg}/config/variables/igor.env"      "Paths, domain, UI flags"
    printf "  ${Y}%-40s${N} %s\n" "${cfg}/config/variables/ai_settings.env" "AI model, provider, temperature"
    printf "  ${Y}%-40s${N} %s\n" "${cfg}/secrets/db.env"                 "DB / service credentials (chmod 600)"
    printf "  ${Y}%-40s${N} %s\n" "${cfg}/secrets/notifications.env"      "SMTP password (chmod 600)"
    printf "  ${Y}%-40s${N} %s\n" "${cfg}/secrets/mailcmd.env"            "IMAP credentials (chmod 600)"
    printf "  ${Y}%-40s${N} %s\n" "${cfg}/secrets/anthropic.key"          "Anthropic API key (chmod 600)"
    printf "  ${Y}%-40s${N} %s\n" "${cfg}/secrets/openrouter.key"         "OpenRouter API key (chmod 600)"
    printf "  ${Y}%-40s${N} %s\n" "${cfg}/config/knowledge/"              "AI persistent knowledge (primer.md, wip.md)"
    printf "  ${Y}%-40s${N} %s\n" "${cfg}/data/sessions/"                 "AI session logs with token usage"
    printf "  ${Y}%-40s${N} %s\n" "${cfg}/data/runtime/"                  "IPC state, FIFO, worker PID"
    printf "  ${Y}%-40s${N} %s\n" "${cfg}/core/config/defaults.env"       "Repo defaults (NC_UID, NC_GID, etc.)"
    echo ""

    echo -e "${C}${B}MORE INFO${N}"
    echo "  docs/ARCHITECTURE.md      Stack diagram and critical design decisions"
    echo "  docs/troubleshooting.md   Common issues and fixes"
    echo "  docs/adding-a-provider.md Add an AI provider (Ollama, etc.)"
    echo "  docs/adding-a-check.md    Add a custom health check"
    echo "  CONTRIBUTING.md           Contribution guidelines"
    echo "  CHANGELOG.md              Full milestone history"
    echo ""
    echo "  Issues / feedback: https://github.com/anthropics/claude-code/issues"
    echo ""
}

# ── Communications sub-menu (Notifications + Remote access) ────────────────────
_igor_communications_menu() {
    while true; do
        if declare -f igor_right_render &>/dev/null; then
            igor_right_render "Communications" \
                "---"  "Quick actions" \
                "hint" "[1]  NOTIFICATIONS" \
                "hint" "[2]  REMOTE ACCESS" \
                "hint" "[b]  BACK"
        fi
        local _opt
        _opt=$(igor_fzf_pick "P: Communications" \
            "1:NOTIFICATIONS:Email alerts — health, fixes, backups, AI actions" \
            "2:REMOTE ACCESS:Cloudflare tunnel, reverse SSH, VPN status" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "P: Communications"
        echo -e "  ${YEL}${BOLD}[P] Communications${NC}"
        echo ""
        echo -e "  ${CYAN}1.${NC} NOTIFICATIONS  — Email alerts (health, fixes, backups, AI actions)"
        echo -e "  ${CYAN}2.${NC} REMOTE ACCESS  — Cloudflare tunnel, reverse SSH, VPN status"
        echo ""
        echo -e "  ${CYAN}b.${NC} Back"
        echo ""
        read -rp "  Select: " _opt ;; esac
        [ "$_opt" = "_" ] && continue
        case "$_opt" in
            1) _igor_load_subsystem "notify" "${IGOR_DIR}/core/notify/core.sh";  menu_notify ;;
            2) menu_tunnel ;;
            b|B|q|Q) return ;;
        esac
    done
}

# ── fzf-based dynamic menu ───────────────────────────────────────────────────
# Builds and launches the fzf menu. Prints the selected key to stdout.
# Returns 0 on selection, 1 on abort (Esc / Ctrl-C).
# Callers must handle key="_" (section header clicked) by looping again.
_igor_fzf_menu() {
    local C=$'\033[1;36m'  # cyan  — key badges
    local B=$'\033[1m'     # bold  — labels
    local D=$'\033[2m'     # dim   — descriptions
    local H=$'\033[1;34m'  # blue  — section headers
    local N=$'\033[0m'     # reset

    # ── Helpers (local to this call) ─────────────────────────────────────────
    local -a _lines=()

    _fzf_hdr() {
        _lines+=("_"$'\t'"${H}── ${1} $(printf '%.0s─' {1..40})${N}")
    }
    _fzf_item() {
        local _key="$1" _lbl="$2" _desc="$3" _pad
        printf -v _pad '%-20s' "$_lbl"
        _lines+=("${_key}"$'\t'"${C}[${_key}]${N}  ${B}${_pad}${N}  ${D}${_desc}${N}")
    }

    # ── Recently used ─────────────────────────────────────────────────────────
    local _rc=0 _rseen=()
    if [ -f "$_IGOR_RECENT_FILE" ]; then
        while IFS='|' read -r _rk _rl; do
            [ -z "$_rk" ] && continue
            local _dup=0
            for _s in "${_rseen[@]:-}"; do [ "$_s" = "$_rk" ] && { _dup=1; break; }; done
            [ "$_dup" -eq 1 ] && continue
            _rseen+=("$_rk")
            [ "$_rc" -eq 0 ] && _fzf_hdr "RECENTLY USED"
            local _cl="${_rl%%[[:space:]]—*}"; _cl="${_cl%%[[:space:]]–*}"
            _fzf_item "$_rk" "$_cl" "↑ recently used"
            _rc=$(( _rc + 1 ))
            [ "$_rc" -ge 3 ] && break
        done < <(tac "$_IGOR_RECENT_FILE" 2>/dev/null)
    fi

    # ── Loaded module sections (auto-discovered, keys assigned dynamically) ─────
    # menu_items in module.conf are label-only (no KEY: prefix).
    # Keys are assigned here from the global sequence, skipping reserved letters.
    if declare -f igor_loaded_modules_by_priority &>/dev/null \
       && [ "${#_IGOR_LOADED_MODULES[@]}" -gt 0 ]; then
        # Key pool: 1-9 then a-z minus reserved (q A D ?)
        local -A _mm_reserved=([q]=1 [Q]=1 [A]=1 [D]=1 [?]=1)
        local -a _mm_keys=(1 2 3 4 5 6 7 8 9)
        local _mc; for _mc in {a..z}; do
            [[ "${_mm_reserved[$_mc]+x}" ]] || _mm_keys+=("$_mc")
        done
        local _mk_idx=0

        local _mn
        while IFS= read -r _mn; do
            [ -z "$_mn" ] && continue
            local _dn _ms _is
            _dn=$(_igor_module_conf_get "$_mn" "display_name")
            _ms=$(_igor_module_conf_get "$_mn" "menu_section")
            _is=$(_igor_module_conf_get "$_mn" "menu_items")
            [ -z "$_is" ] && continue
            # Check for a menu_header hook registered by this module
            local _section_hdr _hdr_fns _hdr_fn
            _hdr_fns="${_IGOR_HOOKS[menu_header]:-}"
            if [ -n "$_hdr_fns" ]; then
                _hdr_fn="${_hdr_fns%% *}"
                if declare -f "$_hdr_fn" &>/dev/null; then
                    _section_hdr=$("$_hdr_fn" 2>/dev/null)
                fi
            fi
            _fzf_hdr "${_section_hdr:-${_ms:-${_dn:-$_mn}}}"
            local _old_IFS="$IFS"; IFS=','
            for _pair in $_is; do
                IFS="$_old_IFS"
                # Support both legacy KEY:LABEL and new label-only formats
                local _lb _mk
                if [[ "$_pair" == *:* ]]; then
                    # Legacy format: KEY:LABEL — keep existing key for backward compat
                    _mk="${_pair%%:*}"; _lb="${_pair#*:}"
                else
                    # New format: LABEL — assign key from pool
                    _lb="$_pair"
                    _mk="${_mm_keys[$_mk_idx]:-x}"
                    _mk_idx=$(( _mk_idx + 1 ))
                fi
                _fzf_item "$_mk" "$_lb" "$(_igor_fzf_desc "$_lb")"
                IFS=','
            done
            IFS="$_old_IFS"
        done < <(igor_loaded_modules_by_priority)
    fi

    # ── Static core sections ──────────────────────────────────────────────────
    _fzf_hdr "ADVANCED"
    _fzf_item "A" "IGOR ASSISTANT"   "AI-based diagnostics and repair"
    _fzf_item "D" "DIAGNOSE"       "Structured multi-phase health diagnosis"
    _fzf_item "R" "RECOVERY"       "Journal, backups, rollback, supervised"
    _fzf_hdr "COMMUNICATIONS"
    _fzf_item "P" "COMMUNICATIONS" "Notifications + Remote access"
    _fzf_item "C" "COMMAND MAIL"   "Secure inbound email (GPG)"

    _fzf_hdr "SYSTEM"
    _fzf_item "Q" "QUIT"           "Exit Igor"

    # ── Launch fzf ────────────────────────────────────────────────────────────
    # Use igor_fzf_cmd so non-layout tmux sessions get the popup geometry.
    local _fzf_cmd _height_flag _sep=()
    _fzf_cmd=$(igor_fzf_cmd 2>/dev/null || echo "fzf")
    _height_flag="--height=100%"
    if [[ "$_fzf_cmd" == fzf-tmux* ]]; then
        _height_flag=""
        _sep=("--")
    fi

    local _sel
    _sel=$(printf '%s\n' "${_lines[@]}" \
        | ${_fzf_cmd} "${_sep[@]}" \
            --ansi \
            ${_height_flag:+"$_height_flag"} \
            --layout=reverse \
            --border=rounded \
            --prompt="  ❯ " \
            --pointer="▶" \
            --info=hidden \
            --no-sort \
            --delimiter=$'\t' \
            --with-nth=2 \
            --color="bg:#0d1117,bg+:#0f2744,fg:#c9d1d9,fg+:white,\
border:#1e3a5f,header:#c9d1d9,prompt:#22d3ee,\
pointer:#38bdf8,hl:#22d3ee,hl+:#38bdf8,\
separator:#1e3a5f,scrollbar:#38bdf8" \
            --bind="esc:abort" \
        2>/dev/null)

    [ $? -ne 0 ] || [ -z "$_sel" ] && return 1
    printf '%s' "$_sel" | cut -f1
}

# Description lookup for module menu items
_igor_fzf_desc() {
    case "$1" in
        "SETUP & INSTALL") echo "→ START HERE   wizard · storage · cloudflare tunnel" ;;
        STATUS)            echo "Quick dashboard — containers, health, tunnel" ;;
        SERVICES)          echo "Start / stop / restart the stack" ;;
        APPS)              echo "Install, enable, or disable apps" ;;
        MAINTENANCE)       echo "Scan files, repair, upgrade, flush caches" ;;
        CONFIGURE)         echo "nginx, upload limit, domain settings, admin password" ;;
        DIAGNOSE)          echo "Deep network checks, routing, PHP, DB integrity" ;;
        INFO)              echo "Architecture · onboarding guide · Igor internals" ;;
        *)                 echo "" ;;
    esac
}

# ── Main menu ───────────────────────────────────────────────────────────────────
_igor_run_ai_menu() {
    menu_ai
    local session_status=$?
    case "$session_status" in
        0) return 0 ;;
        2) pause ;;
        *) warn "AI Assistant exited unexpectedly (status ${session_status})."; pause ;;
    esac
    return 0
}

main_menu() {
    # ── Alert banner — show once on first launch if pending.log exists ────────
    # Skipped when _IGOR_STARTUP_ALERT_SHOWN=true (already shown before layout built).
    local _pending="$(_igor_resolve_dir "alerts")/pending.log"
    if [ "${_IGOR_STARTUP_ALERT_SHOWN:-false}" = "false" ] && \
       [ -f "$_pending" ] && [ -s "$_pending" ]; then
        clear
        if declare -f alert_show_pending &>/dev/null; then
            alert_show_pending
        else
            echo -e "\n  ${RED}${BOLD}⚠  IGOR HEALTH ALERTS PENDING — check /data/alerts/pending.log${NC}\n"
        fi
        read -rp "  Press Enter to continue to main menu..."
        _IGOR_STARTUP_ALERT_SHOWN=true
    fi

    # ── Hybrid mode state ─────────────────────────────────────────────────────
    local _IGOR_HYBRID_ACTIVE=false
    local _IGOR_HYBRID_INITIALIZED=false

    # Load hybrid library once if hybrid mode is on
    if [ "${AI_HYBRID_MODE:-false}" = "true" ]; then
        source "${IGOR_DIR}/core/lib/ai_hybrid.sh" 2>/dev/null || true
    fi

    while true; do
        # ── Returning to main menu: hide output pane, clear breadcrumb ─────────
        declare -f igor_output_hide &>/dev/null && igor_output_hide
        declare -f _igor_set_breadcrumb &>/dev/null && _igor_set_breadcrumb ""
        # Always clear before rendering the main menu — prevents previous session
        # output (AI chat, tool output, etc.) from persisting on screen.
        clear
        # ── Right pane: main menu context ─────────────────────────────────────
        if declare -f igor_right_render &>/dev/null; then
            local _mm_score _mm_hd _mm_time
            _mm_score=$(calculate_health_score 2>/dev/null || echo "?")
            _mm_hd=$(df -h "${HD_MOUNT:-/mnt}" 2>/dev/null | awk 'NR==2{print $3"/"$2" ("$5" used)"}' || echo "?")
            _mm_time=$(date '+%H:%M  %Y-%m-%d')

            # ── Active modules entries ─────────────────────────────────────────
            local -a _mod_args=()
            if [ ${#_IGOR_LOADED_MODULES[@]} -gt 0 ] \
               && declare -f igor_loaded_modules_by_priority &>/dev/null; then
                _mod_args+=("---" "Active modules")
                local _mn
                while IFS= read -r _mn; do
                    [ -z "$_mn" ] && continue
                    local _ver; _ver=$(_igor_module_conf_get "$_mn" "version" 2>/dev/null)
                    local _entry="● loaded"
                    [ -n "$_ver" ] && _entry="● loaded  v${_ver}"
                    _mod_args+=("$_mn" "$_entry")
                done < <(igor_loaded_modules_by_priority)
            fi

            igor_right_render "Igor Overview" \
                "Host"      "$(hostname -s 2>/dev/null || echo '?')" \
                "Health"    "${_mm_score}%" \
                "Storage"   "${_mm_hd}" \
                "Time"      "${_mm_time}" \
                "${_mod_args[@]}" \
                "---"       "Quick actions" \
                "hint"      "[A]  IGOR ASSISTANT" \
                "hint"      "[D]  DIAGNOSE" \
                "hint"      "[Q]  QUIT"
        fi

        # ── fzf path: handles display + input in one shot ─────────────────────
        if [ "${_IGOR_FZF_AVAILABLE}" = "true" ] \
           && [ "${_IGOR_HYBRID_ACTIVE:-false}" = "false" ]; then
            local choice
            choice=$(_igor_fzf_menu) || exit 0   # Esc/Ctrl-C → quit
            [ "$choice" = "_" ] && continue       # section header selected → redraw
        else
        # ── Plain-text fallback (no fzf, or mid-AI hybrid conversation) ───────
            # Only redraw the menu when not mid AI conversation
            if [ "${_IGOR_HYBRID_ACTIVE:-false}" = "false" ]; then
                header
                echo -e "  ${CYAN}Main Menu${NC}"
                echo ""

                local _recent_output; _recent_output=$(_igor_show_recent 2>/dev/null)
                if [ -n "$_recent_output" ]; then
                    echo -e "  ${DIM}── Recent ──────────────────────────────────────────${NC}"
                    echo "$_recent_output"
                    echo ""
                fi

                local _pcount; _pcount=$(get_pending_item_count 2>/dev/null || echo 0)
                if [ "${_pcount:-0}" -gt 0 ]; then
                    echo -e "  ${YEL}⚡  ${_pcount} new menu item(s) proposed by AI — review in Maintenance (5)${NC}"
                    echo ""
                fi

                if [ ${#_IGOR_LOADED_MODULES[@]} -gt 0 ]; then
                    local _mod_name
                    while IFS= read -r _mod_name; do
                        [ -n "$_mod_name" ] && igor_render_module_menu_section "$_mod_name"
                    done < <(igor_loaded_modules_by_priority)
                else
                    echo -e "  ${DIM}── Modules ─────────────────────────────────────────${NC}"
                    echo -e "  ${DIM}  No modules loaded — check modules/ directory${NC}"
                    echo ""
                fi
                echo -e "  ${DIM}── Advanced ────────────────────────────────────────${NC}"
                echo -e "  ${CYAN}A.${NC} IGOR ASSISTANT  - Ai-based diagnostics and repair"
                echo -e "  ${CYAN}D.${NC} IGOR DIAGNOSE - Deep diagnostic, fix & recovery"
                echo -e "  ${CYAN}R.${NC} RECOVERY      - Journal, backups, rollback, supervised installs"
                echo ""
                echo -e "  ${DIM}── Communications ─────────────────────────────────${NC}"
                echo -e "  ${CYAN}P.${NC} COMMUNICATIONS - Notifications + Remote access"
                echo -e "  ${CYAN}C.${NC} COMMAND MAIL   - Secure inbound email command channel (GPG)"
                echo ""
                echo -e "  ${CYAN}Q.${NC} QUIT          - Exit IGOR"
                echo ""
            fi  # end static menu display

            if [ "${AI_HYBRID_MODE:-false}" = "true" ]; then
                echo -ne "  ${CYAN}Select or ask Igor:${NC} "
            else
                echo -ne "  ${CYAN}Select option:${NC} "
            fi
            IFS= read -r choice || return 0
        fi  # end fzf / plain-text branch

        case "$choice" in
            # ── R: Recovery (was V — V kept as alias) ───────────────────────
            r|R|v|V)
                _igor_record_recent "R" "RECOVERY — Backups, journal, rollback"
                _igor_load_subsystem "recovery" "${IGOR_DIR}/core/recovery/core.sh"
                menu_recovery ;;
            # ── P: Communications sub-menu (Notify + Remote) ────────────────
            p|P)
                _igor_record_recent "P" "COMMUNICATIONS — Notifications, Remote access"
                _igor_communications_menu ;;
            # ── O: Notify direct shortcut (backward compat) ─────────────────
            o|O)
                _igor_record_recent "O" "NOTIFY — Email alerts"
                _igor_load_subsystem "notify" "${IGOR_DIR}/core/notify/core.sh"
                menu_notify ;;
            c|C)
                _igor_record_recent "C" "COMMAND MAIL — GPG email commands"
                _igor_load_subsystem "mailcmd" "${IGOR_DIR}/core/mailcmd/core.sh"
                menu_mailcmd ;;
            d|D)
                _igor_record_recent "D" "IGOR DIAGNOSE — Deep diagnostic"
                _igor_load_subsystem "diagnose" "${IGOR_DIR}/core/diagnose/core.sh"
                menu_diagnose ;;
            a|A)
                _igor_record_recent "A" "IGOR ASSISTANT — Ai diagnostics"
                _igor_load_subsystem "ai" "${IGOR_DIR}/core/ai/core.sh"
                _igor_run_ai_menu ;;
            # ── L: Session log — moved into AI menu, keep shortcut working ──
            l|L)
                _igor_record_recent "L" "SESSION LOG — AI history"
                _igor_load_subsystem "ai" "${IGOR_DIR}/core/ai/core.sh"
                menu_sessions ;;
            profile)
                menu_profile ;;
            panels)
                igor_panels_menu ;;
            tune|tune\ *)
                declare -f igor_tune >/dev/null 2>&1 || \
                    source "${IGOR_DIR}/core/lib/tuning.sh" 2>/dev/null || true
                # Pass any args after 'tune' (e.g. "tune --dry-run")
                _tune_args="${choice#tune}"
                _tune_args="${_tune_args# }"
                # shellcheck disable=SC2086
                igor_tune ${_tune_args}
                pause ;;
            install\ *)
                _igor_lc_mod="${choice#install }"
                igor_module_install "$_igor_lc_mod"
                pause ;;
            upgrade\ *)
                _igor_lc_mod="${choice#upgrade }"
                igor_module_upgrade "$_igor_lc_mod"
                pause ;;
            remove\ *)
                _igor_lc_mod="${choice#remove }"
                igor_module_remove "$_igor_lc_mod"
                pause ;;
            q|Q)
                exit 0 ;;
            *)
                # Check module-registered menu items first
                if declare -f igor_dispatch_menu_item &>/dev/null \
                        && igor_dispatch_menu_item "$choice"; then
                    :   # dispatched successfully
                elif [ "${AI_HYBRID_MODE:-false}" = "true" ]; then
                    # Empty input or /menu → clear AI output, redraw menu
                    if [ -z "$choice" ] || [ "$choice" = "/menu" ] || [ "$choice" = "clear" ]; then
                        _IGOR_HYBRID_ACTIVE=false
                        _igor_hybrid_reset 2>/dev/null || true
                        continue
                    fi
                    # Any other input → send to AI inline
                    if ! _igor_hybrid_init 2>/dev/null; then
                        warn "AI not available. Check API key (~/.nexus_api_key or ~/.nexus_or_key)."
                        pause
                    else
                        _igor_hybrid_ask "$choice"
                    fi
                else
                    warn "Invalid option. Please try again." ; pause
                fi
                ;;
        esac
    done
}

# ── Core subsystem stub functions ──────────────────────────────────────────────
# menu_tunnel is defined in core/tunnel/tunnel.sh (sourced at startup)
menu_ai()       { fail "AI module not loaded. This should not happen."; }
menu_sessions() { fail "AI module not loaded. This should not happen."; }
menu_diagnose() { _igor_load_subsystem "diagnose" "${IGOR_DIR}/core/diagnose/core.sh"; menu_diagnose "$@"; }
menu_recovery() { _igor_load_subsystem "recovery" "${IGOR_DIR}/core/recovery/core.sh"; menu_recovery "$@"; }
menu_notify()   { _igor_load_subsystem "notify" "${IGOR_DIR}/core/notify/core.sh";   menu_notify   "$@"; }
menu_mailcmd()  { _igor_load_subsystem "mailcmd" "${IGOR_DIR}/core/mailcmd/core.sh" || return 1; menu_mailcmd "$@"; }

# ── Restore stdout for sub-modes ─────────────────────────────────────────────
# Re-open real stdout/stderr so --extra TUI, --status, etc. can write output.
if [ "${_IGOR_STDOUT_SAVED:-false}" = "true" ]; then
    exec 1>&3 2>&4 3>&- 4>&-
    unset _IGOR_STDOUT_SAVED
fi

# ── Execution guard ─────────────────────────────────────────────────────────────
# Only run main_menu if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

    # ── Command-line flag handling ────────────────────────────────────────────
    for _igor_arg in "$@"; do
        case "$_igor_arg" in
            --ai-tui-backend)
                if [ "${IGOR_TUI_MODE:-false}" = true ]; then
                    _IGOR_TUI_PHASE_ENDED_MS=$(date +%s%3N)
                    if [[ "${_IGOR_TUI_PHASE_STARTED_MS:-}" =~ ^[0-9]+$ ]]; then
                        _IGOR_TUI_BACKEND_DISPATCH_MS=$((_IGOR_TUI_PHASE_ENDED_MS - _IGOR_TUI_PHASE_STARTED_MS))
                    fi
                    _IGOR_TUI_PHASE_STARTED_MS="$_IGOR_TUI_PHASE_ENDED_MS"
                fi
                _igor_load_subsystem "ai" "${IGOR_DIR}/core/ai/core.sh"
                if [ "${IGOR_TUI_MODE:-false}" = true ]; then
                    _IGOR_TUI_PHASE_ENDED_MS=$(date +%s%3N)
                    _IGOR_TUI_AI_SOURCE_MS=$((_IGOR_TUI_PHASE_ENDED_MS - _IGOR_TUI_PHASE_STARTED_MS))
                    _IGOR_TUI_AI_SOURCE_ENDED_MS="$_IGOR_TUI_PHASE_ENDED_MS"
                    unset _IGOR_TUI_PHASE_STARTED_MS _IGOR_TUI_PHASE_ENDED_MS
                fi
                IGOR_TUI_MODE=true AI_SKIP_INTERSTITIAL=true menu_ai
                exit $?
                ;;
            --help|-h)
                _igor_show_help
                exit 0
                ;;
            --capture)
                # Capture all terminal output to runtime/terminal.log for AI awareness
                _igor_rt="$(_igor_resolve_dir "runtime")"
                mkdir -p "$_igor_rt" 2>/dev/null || true
                _cap_log="${_igor_rt}/terminal.log"
                echo "  [capture] Logging to: ${_cap_log}  (exit to stop capture)"
                exec script -a -q -c "bash '${BASH_SOURCE[0]}'" "$_cap_log"
                ;;
            --extra)
                # Launch 7-lens TUI in a second terminal
                _igor_rt="$(_igor_resolve_dir "runtime")"
                mkdir -p "$_igor_rt" 2>/dev/null || true
                source "${IGOR_DIR}/core/extras/extra.sh"
                extra_main
                exit 0
                ;;
            --status)
                # Print session / worker status and exit
                source "/data/runtime/state.sh"  2>/dev/null || true
                source "/data/runtime/ipc.sh"    2>/dev/null || true
                source "/data/runtime/status.sh" 2>/dev/null || true
                show_overall_status
                exit 0
                ;;
            --restart)
                # Restart the background worker and exit
                source "/data/runtime/state.sh"  2>/dev/null || true
                source "/data/runtime/ipc.sh"    2>/dev/null || true
                source "/data/runtime/status.sh" 2>/dev/null || true
                restart_worker
                exit 0
                ;;
            --diagnose)
                # Run Igor Diagnose in the specified mode (default: normal)
                # Usage: bash igor.sh --diagnose [normal|deep|fix|watch|report|recovery]
                _DIAG_CLI_MODE="${2:-normal}"
                _igor_load_subsystem "diagnose" "${IGOR_DIR}/core/diagnose/core.sh"
                menu_diagnose
                exit 0
                ;;
            --backup)
                # Non-interactive cron entry point for scheduled backups
                # Usage: bash igor.sh --backup [config|full]
                # backup_run_scheduled() lives in schedule.sh (self-sources its own deps)
                source "${IGOR_DIR}/core/recovery/schedule.sh" 2>/dev/null || true
                backup_run_scheduled "${2:-config}"
                exit 0
                ;;
            --mailcmd)
                # Non-interactive entry point for mailcmd crontab jobs.
                # Usage: bash igor.sh --mailcmd heartbeat
                _igor_mc_base="${IGOR_DIR:-$(dirname "$(readlink -f "$0")")}"
                if [ ! -f "${_igor_mc_base}/core/mailcmd/core.sh" ] ||
                   [ ! -f "${_igor_mc_base}/core/mailcmd/service.sh" ] ||
                   [ ! -f "${_igor_mc_base}/core/mailcmd/poller.py" ]; then
                    echo "Email control unavailable: core/mailcmd implementation is missing." >&2
                    exit 1
                fi
                source "${_igor_mc_base}/core/mailcmd/core.sh"    2>/dev/null || true
                source "${_igor_mc_base}/core/mailcmd/service.sh" 2>/dev/null || true
                case "${2:-}" in
                    heartbeat)
                        python3 "${_igor_mc_base}/core/mailcmd/poller.py" --heartbeat
                        exit $?
                        ;;
                    *)
                        echo "Usage: bash igor.sh --mailcmd heartbeat"
                        exit 1
                        ;;
                esac
                exit 0
                ;;
            --profile)
                # Detect (or re-detect) hardware tier and print the result.
                # Usage: bash igor.sh --profile
                igor_detect_profile
                igor_profile_show
                exit 0
                ;;
            --install)
                # Run first-time setup for a module.
                # Usage: bash igor.sh --install <module_name>
                _igor_lc_module="${2:-}"
                if [ -z "$_igor_lc_module" ]; then
                    echo "Usage: bash igor.sh --install <module_name>"
                    echo "Loaded modules: $(IFS=', '; echo "${!_IGOR_LOADED_MODULES[*]:-none}")"
                    exit 1
                fi
                igor_module_install "$_igor_lc_module"
                exit $?
                ;;
            --upgrade)
                # Run post-update migration for a module.
                # Usage: bash igor.sh --upgrade <module_name>
                _igor_lc_module="${2:-}"
                if [ -z "$_igor_lc_module" ]; then
                    echo "Usage: bash igor.sh --upgrade <module_name>"
                    echo "Loaded modules: $(IFS=', '; echo "${!_IGOR_LOADED_MODULES[*]:-none}")"
                    exit 1
                fi
                igor_module_upgrade "$_igor_lc_module"
                exit $?
                ;;
            --tune)
                # Run the tier-aware tuning engine.
                # Usage: bash igor.sh --tune [--dry-run] [--module <name>]
                declare -f igor_tune >/dev/null 2>&1 || \
                    source "${IGOR_DIR}/core/lib/tuning.sh" 2>/dev/null || true
                igor_tune "$@"
                exit $?
                ;;
            --remove)
                # Remove/uninstall a module (DESTROY-tier — always prompts).
                # Usage: bash igor.sh --remove <module_name>
                _igor_lc_module="${2:-}"
                if [ -z "$_igor_lc_module" ]; then
                    echo "Usage: bash igor.sh --remove <module_name>"
                    echo "Loaded modules: $(IFS=', '; echo "${!_IGOR_LOADED_MODULES[*]:-none}")"
                    exit 1
                fi
                igor_module_remove "$_igor_lc_module"
                exit $?
                ;;
        esac
    done

    # ── Write PID for --extra mode ────────────────────────────────────────────
    _igor_rt="$(_igor_resolve_dir "runtime")"
    mkdir -p "$_igor_rt" 2>/dev/null || true
    echo $$ > "${_igor_rt}/pid" 2>/dev/null || true
    trap 'rm -f "${_igor_rt}/pid" 2>/dev/null; exit 0' EXIT INT TERM

    # ── Orphaned diagnose heartbeat check ────────────────────────────────────
    # If a previous diagnose session exited uncleanly, offer recovery mode.
    _igor_diag_hb="$(_igor_resolve_dir "runtime")/diag_heartbeat"
    if [ -f "$_igor_diag_hb" ]; then
        echo ""
        warn "Orphaned diagnose heartbeat detected — previous session may have crashed."
        if confirm "Launch Igor Diagnose in Recovery mode now?"; then
            _igor_load_subsystem "diagnose" "${IGOR_DIR}/core/diagnose/core.sh"
            _DIAG_RECOVERY_REQUESTED=true
            menu_diagnose
        else
            rm -f "$_igor_diag_hb" 2>/dev/null || true
        fi
    fi

    # ── Recovery startup check (app diff + pending alerts, ≤3s budget) ──────
    declare -f _mod_recovery_startup_check &>/dev/null && \
        _mod_recovery_startup_check 2>/dev/null || true

    # ── AI Autostart ──────────────────────────────────────────────────────────
    if [ "${AI_AUTOSTART:-false}" = "true" ]; then
        info "AI Autostart enabled — launching IGOR ASSISTANT directly."
        info "To reach the main menu: type 'q' or 'quit' inside the AI session."
        _igor_load_subsystem "ai" "${IGOR_DIR}/core/ai/core.sh"
        AI_SKIP_INTERSTITIAL=true _igor_run_ai_menu
        # After AI session ends, fall through to main_menu normally
    fi

    main_menu
fi
