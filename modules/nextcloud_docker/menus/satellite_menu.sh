#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/satellite_menu.sh
#
#  Satellite service menu — optional companion services for Nextcloud.
#  Visibility of each entry is controlled by NC_TIER_SATELLITE_* variables:
#
#    hidden   — not rendered; option does not appear in any menu
#    optional — rendered with default state OFF
#    default  — rendered with default state ON
#
#  Source lib/tier_config.sh before calling menu_satellites() so the
#  NC_TIER_SATELLITE_* variables are set; this file sources it automatically
#  if they are absent.
#
#  Public functions:
#    menu_satellites          — interactive satellite menu
#    _nc_satellite_visible    — returns 0 if satellite should be shown
# ==============================================================================

# ── Satellite definitions ─────────────────────────────────────────────────────
# Each entry: "KEY:LABEL:DESCRIPTION:VAR_SUFFIX"
_NC_SATELLITES=(
    "immich:IMMICH:Photo management & AI recognition:IMMICH"
    "collabora:COLLABORA:Online office (Collabora CODE):COLLABORA"
    "onlyoffice:ONLYOFFICE:Office suite (OnlyOffice):ONLYOFFICE"
    "coturn:COTURN:WebRTC TURN relay (Talk calls):COTURN"
)

# ── _nc_satellite_load_tier ───────────────────────────────────────────────────
# Ensures NC_TIER_SATELLITE_* variables are set.  Idempotent.
_nc_satellite_load_tier() {
    [ -n "${NC_TIER_SATELLITE_COTURN:-}" ] && return 0   # already loaded
    local _mod_dir
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local _tier_cfg="${_mod_dir}/lib/tier_config.sh"
    [ -f "$_tier_cfg" ] && source "$_tier_cfg" || true
}

# ── _nc_satellite_visible KEY ────────────────────────────────────────────────
# Returns 0 (true) when the satellite should appear in menus.
# Returns 1 (false) when it is hidden for the current tier.
_nc_satellite_visible() {
    local _key="${1:-}"
    local _varname="NC_TIER_SATELLITE_$(printf '%s' "$_key" | tr '[:lower:]' '[:upper:]')"
    local _vis="${!_varname:-hidden}"
    [ "$_vis" != "hidden" ]
}

# ── _nc_satellite_default KEY ─────────────────────────────────────────────────
# Returns 0 when the satellite defaults to ON for the current tier.
_nc_satellite_default() {
    local _key="${1:-}"
    local _varname="NC_TIER_SATELLITE_$(printf '%s' "$_key" | tr '[:lower:]' '[:upper:]')"
    [ "${!_varname:-hidden}" = "default" ]
}

# ── _nc_satellite_stub KEY ────────────────────────────────────────────────────
# Placeholder action for satellites not yet provisioned.
_nc_satellite_stub() {
    local _label="${1:-satellite}"
    echo ""
    warn "${_label} provisioning is not yet implemented."
    info "This menu entry reserves the slot for a future Igor module."
    info "To provision manually, see: https://github.com/nextcloud/all-in-one"
    echo ""
    pause
}

# ── menu_satellites ───────────────────────────────────────────────────────────
# Interactive satellite service menu.  Entries are shown or hidden based on
# NC_TIER_SATELLITE_* visibility values for the current tier.
menu_satellites() {
    _nc_satellite_load_tier

    while true; do
        # ── Build fzf item list ────────────────────────────────────────────────
        # Collect visible satellites and compose igor_render_menu action strings.
        local -a _menu_items=()
        local -a _key_map=()   # "action_id → satellite key" for dispatch

        for _sat_def in "${_NC_SATELLITES[@]}"; do
            local _key _label _desc _varsuffix
            IFS=':' read -r _key _label _desc _varsuffix <<< "$_sat_def"

            _nc_satellite_visible "$_key" || continue   # skip hidden

            local _varname="NC_TIER_SATELLITE_${_varsuffix}"
            local _vis="${!_varname:-optional}"
            local _state_tag
            [ "$_vis" = "default" ] && _state_tag=" [default ON]" || _state_tag=""

            _menu_items+=("${_key}:${_label}:${_desc}${_state_tag}")
            _key_map+=("${_key}")
        done

        # ── Right pane ─────────────────────────────────────────────────────────
        if declare -f igor_right_render &>/dev/null; then
            local -a _rpane=("Satellite Services" "Tier" "${IGOR_TIER:-constrained}")
            for _sat_def in "${_NC_SATELLITES[@]}"; do
                local _key _label _desc _varsuffix
                IFS=':' read -r _key _label _desc _varsuffix <<< "$_sat_def"
                local _varname="NC_TIER_SATELLITE_${_varsuffix}"
                local _vis="${!_varname:-hidden}"
                _rpane+=("${_label}" "${_vis}")
            done
            _rpane+=("---" "Quick actions" "hint" "[b]  BACK")
            igor_right_render "${_rpane[@]}"
        fi

        if [ ${#_menu_items[@]} -eq 0 ]; then
            header 2>/dev/null || true
            breadcrumb "Igor" "Satellites"
            echo ""
            info "No satellite services are available for the '${IGOR_TIER:-constrained}' tier."
            info "Upgrade to 'standard' or higher to unlock satellite options."
            echo ""
            pause
            return
        fi

        # ── Render menu ────────────────────────────────────────────────────────
        local _action
        _action=$(igor_render_menu "Satellites" \
            "${_menu_items[@]}" \
            "back:BACK:Return to previous menu")
        case $? in
            1) return ;;   # fzf aborted
            2)             # fzf unavailable — plain text fallback
                header 2>/dev/null || true
                breadcrumb "Igor" "Satellites"
                echo -e "  ${BOLD:-}Satellite Services  (tier: ${IGOR_TIER:-constrained})${NC:-}"
                echo ""
                local _i=1
                for _sat_def in "${_NC_SATELLITES[@]}"; do
                    local _key _label _desc _varsuffix
                    IFS=':' read -r _key _label _desc _varsuffix <<< "$_sat_def"
                    _nc_satellite_visible "$_key" || continue
                    local _varname="NC_TIER_SATELLITE_${_varsuffix}"
                    local _vis="${!_varname:-optional}"
                    local _state_tag; [ "$_vis" = "default" ] && _state_tag=" [default ON]" || _state_tag=""
                    printf "  %d) %-12s — %s%s\n" "$_i" "$_label" "$_desc" "$_state_tag"
                    _i=$(( _i + 1 ))
                done
                echo "   b) Back"
                echo ""
                read -rp "  Select: " _action
                # map numeric to key
                local _ci=1
                for _k in "${_key_map[@]}"; do
                    [ "$_action" = "$_ci" ] && { _action="$_k"; break; }
                    _ci=$(( _ci + 1 ))
                done
                ;;
        esac

        [ "$_action" = "_" ] && continue

        case "$_action" in
            immich)      _nc_satellite_stub "Immich"      ;;
            collabora)   _nc_satellite_stub "Collabora"   ;;
            onlyoffice)  _nc_satellite_stub "OnlyOffice"  ;;
            coturn)      _nc_satellite_stub "COTURN"      ;;
            back|q|Q)    return ;;
        esac
    done
}
