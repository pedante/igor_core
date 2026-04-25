#!/bin/bash
# =============================================================================
#  PANEL SYSTEM — core/lib/panels.sh
#
#  Manages tmux split-panes for live monitoring views declared by modules.
#  Each module declares panels in module.conf [panels] section:
#
#    [panels]
#    panels=name:command:description
#    panels=name2:command2:description2
#
#  Degrades gracefully when tmux is not available — prints a message instead
#  of opening a pane.
#
#  Public API:
#    igor_has_tmux               — returns 0 if tmux is available and a session exists
#    igor_panel_open <name> <cmd>  — open a named tmux split-pane running <cmd>
#    igor_panel_close <name>     — close a named panel
#    igor_panel_list             — list all panels declared by loaded modules
#    igor_panels_menu            — interactive panel selector (fzf/select)
# =============================================================================

# Registry: _IGOR_PANELS[name]="module:command:description"
declare -gA _IGOR_PANELS 2>/dev/null || true

# Open pane tracking: _IGOR_OPEN_PANELS[name]=tmux_pane_id
declare -gA _IGOR_OPEN_PANELS 2>/dev/null || true

# ---------------------------------------------------------------------------
# igor_has_tmux
#   Returns 0 if tmux binary exists AND we are inside a tmux session.
#   Returns 1 otherwise (panels degrade gracefully).
# ---------------------------------------------------------------------------
igor_has_tmux() {
    command -v tmux >/dev/null 2>&1 && [ -n "${TMUX:-}" ]
}

# ---------------------------------------------------------------------------
# igor_panels_load_modules
#
#   Scan all loaded modules and register their declared panels.
#   Called once after all modules are loaded (wired in igor.sh).
#   Safe to call multiple times — dedup'd by name.
# ---------------------------------------------------------------------------
igor_panels_load_modules() {
    local _mod _dir _conf
    for _mod in "${!_IGOR_LOADED_MODULES[@]:-}"; do
        _dir="${_IGOR_MODULE_DIRS[$_mod]:-}"
        [ -z "$_dir" ] && continue
        _conf="${_dir}/module.conf"
        [ -f "$_conf" ] || continue
        _panels_parse_conf "$_conf" "$_mod"
    done
}

# ---------------------------------------------------------------------------
# _panels_parse_conf <conf_file> <module_name>
#   Internal: reads all panels= lines from [panels] section.
# ---------------------------------------------------------------------------
_panels_parse_conf() {
    local _conf="$1" _mod="$2"
    local _line _name _cmd _desc

    awk '
        /^\[panels\]/ { in_section=1; next }
        /^\[/         { in_section=0 }
        in_section && /^panels[[:space:]]*=/ {
            sub(/^panels[[:space:]]*=[[:space:]]*/, "")
            print
        }
    ' "$_conf" | while IFS= read -r _line; do
        [ -z "$_line" ] && continue
        IFS=':' read -r _name _cmd _desc <<< "$_line"
        _name="${_name// /}"
        [ -z "$_name" ] && continue
        [ -z "$_cmd" ]  && continue
        # Write to a temp file because subshell can't update parent array
        printf '%s\t%s\t%s\t%s\n' "$_name" "$_mod" "$_cmd" "${_desc:-$_name}"
    done
}

# ---------------------------------------------------------------------------
# _panels_register_all
#   Reload all module panels into the _IGOR_PANELS associative array.
#   Must run in the current shell (not a subshell) to populate the array.
# ---------------------------------------------------------------------------
_panels_register_all() {
    local _mod _dir _conf _line _name _cmd _desc
    for _mod in "${!_IGOR_LOADED_MODULES[@]:-}"; do
        _dir="${_IGOR_MODULE_DIRS[$_mod]:-}"
        [ -z "$_dir" ] && continue
        _conf="${_dir}/module.conf"
        [ -f "$_conf" ] || continue

        local _in_panels=0
        while IFS= read -r _line; do
            case "$_line" in
                \[panels\])   _in_panels=1 ;;
                \[*)          _in_panels=0 ;;
                panels=*)
                    if [ "$_in_panels" -eq 1 ]; then
                        local _entry="${_line#panels=}"
                        IFS=':' read -r _name _cmd _desc <<< "$_entry"
                        _name="${_name// /}"
                        [ -z "$_name" ] || [ -z "$_cmd" ] && continue
                        _IGOR_PANELS["$_name"]="${_mod}:${_cmd}:${_desc:-$_name}"
                    fi
                    ;;
            esac
        done < "$_conf"
    done
}

# ---------------------------------------------------------------------------
# igor_panel_list
#
#   Print all registered panels, one per line:
#     name  module  description
#   Also shows [OPEN] tag for panels currently running.
# ---------------------------------------------------------------------------
igor_panel_list() {
    _panels_register_all

    if [ ${#_IGOR_PANELS[@]} -eq 0 ]; then
        echo "  (no panels declared by any loaded module)"
        return 0
    fi

    local _name
    for _name in $(printf '%s\n' "${!_IGOR_PANELS[@]}" | sort); do
        local _entry="${_IGOR_PANELS[$_name]}"
        local _mod _cmd _desc
        IFS=':' read -r _mod _cmd _desc <<< "$_entry"
        local _open_tag=""
        [ -n "${_IGOR_OPEN_PANELS[$_name]:-}" ] && _open_tag=" [OPEN]"
        printf '  %-24s %-20s %s%s\n' "$_name" "[$_mod]" "$_desc" "$_open_tag"
    done
}

# ---------------------------------------------------------------------------
# igor_panel_open <name> [command_override]
#
#   Open a tmux split-pane running the command for <name>.
#   If command_override is given, it is used instead of the registered command.
#   The pane is tracked in _IGOR_OPEN_PANELS[name].
#
#   Without tmux: prints the command instead (manual run hint).
# ---------------------------------------------------------------------------
igor_panel_open() {
    local _name="${1:-}"
    local _cmd_override="${2:-}"

    [ -z "$_name" ] && { echo "  [panels] igor_panel_open: panel name required" >&2; return 1; }

    _panels_register_all

    local _cmd _mod _desc
    if [ -n "$_cmd_override" ]; then
        _cmd="$_cmd_override"
        _mod="custom"
        _desc="$_name"
    else
        local _entry="${_IGOR_PANELS[$_name]:-}"
        if [ -z "$_entry" ]; then
            echo "  [panels] Unknown panel: ${_name}" >&2
            echo "  [panels] Available: $(printf '%s ' "${!_IGOR_PANELS[@]}")" >&2
            return 1
        fi
        IFS=':' read -r _mod _cmd _desc <<< "$_entry"
    fi

    # Already open?
    if [ -n "${_IGOR_OPEN_PANELS[$_name]:-}" ]; then
        echo "  [panels] Panel '${_name}' is already open (pane: ${_IGOR_OPEN_PANELS[$_name]})"
        return 0
    fi

    if igor_has_tmux; then
        # Open a new vertical split-pane, capture its pane ID
        local _pane_id
        _pane_id=$(tmux split-window -v -P -F '#{pane_id}' \
            "bash -c '${_cmd}; echo; echo \"[Panel: ${_name} exited. Press Enter]\"; read'" 2>/dev/null)
        if [ -n "$_pane_id" ]; then
            _IGOR_OPEN_PANELS["$_name"]="$_pane_id"
            echo "  [panels] Opened '${_name}' in pane ${_pane_id}"
        else
            echo "  [panels] Failed to open tmux pane for '${_name}'" >&2
            return 1
        fi
    else
        # Degrade: show the command the user can run manually
        echo ""
        echo "  Panel: ${_desc}"
        echo "  No tmux session — run this command manually:"
        echo "    ${_cmd}"
        echo ""
    fi
    return 0
}

# ---------------------------------------------------------------------------
# igor_panel_close <name>
#
#   Close a named panel by killing its tmux pane.
#   No-op if the panel isn't open or tmux isn't available.
# ---------------------------------------------------------------------------
igor_panel_close() {
    local _name="${1:-}"
    [ -z "$_name" ] && { echo "  [panels] igor_panel_close: panel name required" >&2; return 1; }

    local _pane_id="${_IGOR_OPEN_PANELS[$_name]:-}"
    if [ -z "$_pane_id" ]; then
        echo "  [panels] Panel '${_name}' is not open"
        return 0
    fi

    if igor_has_tmux; then
        tmux kill-pane -t "$_pane_id" 2>/dev/null || true
    fi
    unset '_IGOR_OPEN_PANELS[$_name]'
    echo "  [panels] Closed '${_name}'"
    return 0
}

# ---------------------------------------------------------------------------
# igor_panels_menu
#
#   Interactive panel selector. Shows available panels, lets user open/close.
#   Uses a simple numbered select loop — no external deps required.
# ---------------------------------------------------------------------------
igor_panels_menu() {
    _panels_register_all

    if [ ${#_IGOR_PANELS[@]} -eq 0 ]; then
        echo "  No panels declared by any loaded module."
        return 0
    fi

    while true; do
        echo ""
        echo "  ── Panel Manager ──────────────────────────────"
        igor_panel_list
        echo ""
        echo "  Commands:"
        echo "    open <name>    — open a panel in a tmux split-pane"
        echo "    close <name>   — close an open panel"
        echo "    q              — return to menu"
        echo ""
        printf "  > "
        local _input
        read -r _input

        case "$_input" in
            open\ *)
                igor_panel_open "${_input#open }" ;;
            close\ *)
                igor_panel_close "${_input#close }" ;;
            q|Q|quit|exit)
                return 0 ;;
            "")
                continue ;;
            *)
                echo "  Unknown command. Use: open <name> | close <name> | q" ;;
        esac
    done
}
