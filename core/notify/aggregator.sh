#!/bin/bash
# =============================================================================
#  NOTIFY AGGREGATOR — core/notify/aggregator.sh
#
#  Collects notification source declarations from all loaded modules via
#  their __notify_sources() hook, then presents them in the Communications
#  menu so the user can configure which events trigger notifications.
#
#  Source declaration protocol (one line per source):
#    SOURCE:<key>:<severity>:<description>
#    severity values: critical | warning | info
#
#  Public API:
#    igor_notify_sources_all()     — collect + print all SOURCE: lines
#    igor_notify_sources_display() — render source list to terminal
#    igor_notify_is_enabled()      — return 0 if a source key is enabled
# =============================================================================

# State file: which sources the user has enabled/disabled
_NOTIFY_AGG_STATE="${IGOR_DIR}/notify_sources.conf"

# ---------------------------------------------------------------------------
# igor_notify_sources_all
#
#   Call __notify_sources() on each loaded module and print all SOURCE: lines.
#   Malformed lines are silently dropped.
# ---------------------------------------------------------------------------
igor_notify_sources_all() {
    declare -f igor_get_hooks >/dev/null 2>&1 || return 0

    local _fn _out _line
    for _fn in $(igor_get_hooks "notify"); do
        declare -f "$_fn" >/dev/null 2>&1 || continue
        _out=$(timeout 10 bash -c "$(declare -f "$_fn"); $_fn" 2>/dev/null)
        while IFS= read -r _line; do
            [[ "$_line" =~ ^SOURCE:[^:]+:(critical|warning|info): ]] && \
                printf '%s\n' "$_line"
        done <<< "$_out"
    done
}

# ---------------------------------------------------------------------------
# igor_notify_sources_display
#
#   Render all registered notification sources to the terminal.
#   Shows enabled/disabled state from the state file.
# ---------------------------------------------------------------------------
igor_notify_sources_display() {
    local _GRN="${GRN:-\033[0;32m}"
    local _YEL="${YEL:-\033[1;33m}"
    local _RED="${RED:-\033[0;31m}"
    local _DIM="${DIM:-\033[2m}"
    local _NC="${NC:-\033[0m}"
    local _BOLD="${BOLD:-\033[1m}"

    local _sources=()
    mapfile -t _sources < <(igor_notify_sources_all)

    echo ""
    echo -e "${_BOLD}  Notification Sources${_NC}"
    echo -e "  ${_DIM}────────────────────────────────────────────────${_NC}"

    if [ ${#_sources[@]} -eq 0 ]; then
        echo -e "  ${_DIM}No notification sources registered by any module${_NC}"
        echo ""
        return 0
    fi

    local _entry _key _sev _desc _enabled _state_color _state_label
    for _entry in "${_sources[@]}"; do
        IFS=':' read -r _ _key _sev _desc <<< "$_entry"

        # Check enabled state (default: enabled)
        if [ -f "$_NOTIFY_AGG_STATE" ] && \
           grep -q "^${_key}=disabled" "$_NOTIFY_AGG_STATE" 2>/dev/null; then
            _enabled=false
            _state_color="$_DIM"
            _state_label="off"
        else
            _enabled=true
            _state_color="$_GRN"
            _state_label="on "
        fi

        # Severity colour
        local _sev_color
        case "$_sev" in
            critical) _sev_color="$_RED" ;;
            warning)  _sev_color="$_YEL" ;;
            info)     _sev_color="$_DIM" ;;
            *)        _sev_color="$_DIM" ;;
        esac

        printf "  [%b%s%b]  %b%-8s%b  %s\n" \
            "$_state_color" "$_state_label" "$_NC" \
            "$_sev_color"   "$_sev"         "$_NC" \
            "$_desc  ${_DIM}(${_key})${_NC}"
    done

    echo -e "  ${_DIM}────────────────────────────────────────────────${_NC}"
    echo -e "  ${_DIM}Toggle: igor_notify_toggle <key>  to enable/disable a source${_NC}"
    echo ""
}

# ---------------------------------------------------------------------------
# igor_notify_toggle <source_key>
#
#   Toggle a notification source on or off.
#   Persists state to the state file.
# ---------------------------------------------------------------------------
igor_notify_toggle() {
    local _key="$1"
    [ -n "$_key" ] || return 1

    mkdir -p "$(dirname "$_NOTIFY_AGG_STATE")" 2>/dev/null || true

    if grep -q "^${_key}=disabled" "$_NOTIFY_AGG_STATE" 2>/dev/null; then
        # Currently disabled → enable (remove the line)
        local _tmp; _tmp=$(grep -v "^${_key}=" "$_NOTIFY_AGG_STATE" 2>/dev/null)
        printf '%s\n' "$_tmp" > "$_NOTIFY_AGG_STATE"
        echo "  Enabled notification source: ${_key}"
    else
        # Currently enabled → disable (add/update the line)
        local _tmp; _tmp=$(grep -v "^${_key}=" "$_NOTIFY_AGG_STATE" 2>/dev/null)
        printf '%s\n%s\n' "$_tmp" "${_key}=disabled" > "$_NOTIFY_AGG_STATE"
        echo "  Disabled notification source: ${_key}"
    fi
}

# ---------------------------------------------------------------------------
# igor_notify_is_enabled <source_key>
#
#   Return 0 if the source is enabled (or has no state entry), 1 if disabled.
#   Use this in notify_event before sending to check user preference.
# ---------------------------------------------------------------------------
igor_notify_is_enabled() {
    local _key="$1"
    [ -n "$_key" ] || return 0   # unknown key → allow

    if [ -f "$_NOTIFY_AGG_STATE" ] && \
       grep -q "^${_key}=disabled" "$_NOTIFY_AGG_STATE" 2>/dev/null; then
        return 1
    fi
    return 0
}
