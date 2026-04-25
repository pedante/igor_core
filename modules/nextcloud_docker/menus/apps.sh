#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/apps.sh
#  Nextcloud app management module.
#
#  This module handles:
#    • List installed apps
#    • Enable/disable apps
#    • Install apps
#    • View app catalogue
# ==============================================================================

# ── Module helpers (prefixed with _mod_apps_) ─────────────────────────────

# Fetch enabled app names as a sorted newline-separated list (quiet, no header)
_mod_apps_fetch_enabled() {
    local occ="docker compose exec -T -u www-data app php occ"
    $occ app:list --output=json 2>/dev/null | python3 -c "
import sys, json
try:
    apps = json.load(sys.stdin)
    for n in sorted(apps.get('enabled', {}).keys()):
        print(n)
except: pass
"
}

# Fetch disabled app names as a sorted newline-separated list
_mod_apps_fetch_disabled() {
    local occ="docker compose exec -T -u www-data app php occ"
    $occ app:list --output=json 2>/dev/null | python3 -c "
import sys, json
try:
    apps = json.load(sys.stdin)
    for n in sorted(apps.get('disabled', {}).keys()):
        print(n)
except: pass
"
}

_mod_apps_list() {
    step "Installed apps"
    local occ="docker compose exec -T -u www-data app php occ"

    $occ app:list --output=json 2>/dev/null | python3 -c "
import sys, json
try:
    apps = json.load(sys.stdin)
except json.JSONDecodeError:
    print('  Error: occ did not return valid JSON (is the app container running?)')
    sys.exit(1)
enabled  = apps.get('enabled',  {})
disabled = apps.get('disabled', {})
if not isinstance(enabled, dict) or not isinstance(disabled, dict):
    print('  Error: unexpected occ app:list output format')
    sys.exit(1)
print(f\"  {'Name':<32} {'Version':<12} Status\")
print('  ' + '-' * 58)
for app, info in sorted(enabled.items()):
    ver = info.get('version', 'N/A') if isinstance(info, dict) else 'N/A'
    print(f\"  {app:<32} {ver:<12} \033[0;32menabled\033[0m\")
for app, info in sorted(disabled.items()):
    ver = info.get('version', 'N/A') if isinstance(info, dict) else 'N/A'
    print(f\"  {app:<32} {ver:<12} \033[1;33mdisabled\033[0m\")
print()
print(f'  Enabled: {len(enabled)}   Disabled: {len(disabled)}')
"

    pause
}

_mod_apps_enable() {
    step "Enable an app"

    info "Fetching disabled apps..."
    local disabled_list
    disabled_list=$(_mod_apps_fetch_disabled)

    if [ -z "$disabled_list" ]; then
        warn "No disabled apps found (all apps are already enabled, or Nextcloud is not running)."
        pause
        return
    fi

    echo ""
    echo -e "  ${CYAN}Disabled apps available to enable:${NC}"
    echo ""
    local i=1
    while IFS= read -r app; do
        printf "    %2d) %s\n" "$i" "$app"
        (( i++ ))
    done <<< "$disabled_list"
    echo ""

    local choice
    read -rp "  Enter number or app name (b to cancel): " choice
    [ "$choice" = "b" ] || [ "$choice" = "B" ] && return

    local app_name="$choice"
    # If numeric, resolve to name
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        app_name=$(echo "$disabled_list" | sed -n "${choice}p")
        if [ -z "$app_name" ]; then
            warn "Invalid selection."
            pause
            return
        fi
    fi

    step "Enabling app: $app_name"
    local occ="docker compose exec -T -u www-data app php occ"
    $occ app:enable "$app_name"
    ok "App '$app_name' enabled."
    declare -f journal_record &>/dev/null && \
        journal_record "menu:apps" "app_enable" "CHANGE" "$app_name" "OK" "via menu" 2>/dev/null || true
    pause
}

_mod_apps_disable() {
    step "Disable an app"

    info "Fetching enabled apps..."
    local enabled_list
    enabled_list=$(_mod_apps_fetch_enabled)

    if [ -z "$enabled_list" ]; then
        warn "No enabled apps found (or Nextcloud is not running)."
        pause
        return
    fi

    echo ""
    echo -e "  ${CYAN}Enabled apps available to disable:${NC}"
    echo ""
    local i=1
    while IFS= read -r app; do
        printf "    %2d) %s\n" "$i" "$app"
        (( i++ ))
    done <<< "$enabled_list"
    echo ""

    local choice
    read -rp "  Enter number or app name (b to cancel): " choice
    [ "$choice" = "b" ] || [ "$choice" = "B" ] && return

    local app_name="$choice"
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        app_name=$(echo "$enabled_list" | sed -n "${choice}p")
        if [ -z "$app_name" ]; then
            warn "Invalid selection."
            pause
            return
        fi
    fi

    step "Disabling app: $app_name"
    local occ="docker compose exec -T -u www-data app php occ"
    $occ app:disable "$app_name"
    ok "App '$app_name' disabled."
    declare -f journal_record &>/dev/null && \
        journal_record "menu:apps" "app_disable" "CHANGE" "$app_name" "OK" "via menu" 2>/dev/null || true
    pause
}

_mod_apps_install() {
    step "Install a new app"

    # Show catalogue so the user knows what's available
    _mod_apps_catalogue_inline

    echo ""
    local app_name
    read -rp "  Enter app name to install (b to cancel): " app_name
    if [ -z "$app_name" ] || [ "$app_name" = "b" ] || [ "$app_name" = "B" ]; then
        return
    fi

    step "Installing app: $app_name"
    # Use supervised install if available (adds RAM check, backup, monitoring, journal)
    if declare -f supervised_app_install &>/dev/null; then
        supervised_app_install "$app_name"
    else
        local occ="docker compose exec -T -u www-data app php occ"
        $occ app:install "$app_name"
        ok "App '$app_name' installed."
        info "If the app is disabled after install, enable it with option 2 in this menu."
        declare -f journal_record &>/dev/null && \
            journal_record "menu:apps" "app_install" "CHANGE" "$app_name" "OK" "via menu" 2>/dev/null || true
    fi
    pause
}

# Inline catalogue (no pause — used inside _mod_apps_install)
_mod_apps_catalogue_inline() {
    echo ""
    echo -e "  ${CYAN}${BOLD}Popular Nextcloud apps${NC}"
    echo -e "  ${CYAN}─────────────────────────────────────────────────────────${NC}"
    printf "  %-28s %s\n" "files_external"   "Access external storage (SFTP, S3, etc.)"
    printf "  %-28s %s\n" "photos"            "Photo viewer & gallery"
    printf "  %-28s %s\n" "files_versions"    "Automatic file versioning"
    printf "  %-28s %s\n" "calendar"          "CalDAV calendar"
    printf "  %-28s %s\n" "contacts"          "CardDAV address book"
    printf "  %-28s %s\n" "mail"              "IMAP email client"
    printf "  %-28s %s\n" "deck"              "Kanban project boards"
    printf "  %-28s %s\n" "notes"             "Simple notes"
    printf "  %-28s %s\n" "tasks"             "Task / todo manager"
    printf "  %-28s %s\n" "twofactor_totp"    "TOTP two-factor authentication"
    printf "  %-28s %s\n" "richdocuments"     "Collabora Online (requires Collabora)"
    printf "  %-28s %s\n" "memories"          "Fast photo timeline (needs ffmpeg)"
    printf "  %-28s %s\n" "previewgenerator"  "Background preview generation"
    printf "  %-28s %s\n" "groupfolders"      "Shared team folders with quotas"
    echo -e "  ${CYAN}─────────────────────────────────────────────────────────${NC}"
    echo -e "  Full catalogue: ${BOLD}https://apps.nextcloud.com/${NC}"
}

_mod_apps_catalogue() {
    step "Available apps (top picks)"
    _mod_apps_catalogue_inline
    echo ""
    pause
}

# ── Public entry point ───────────────────────────────────────────────────────────
menu_apps() {
    while true; do
        # Right pane: app counts
        if declare -f igor_right_render &>/dev/null; then
            local _apps_en _apps_dis
            _apps_en=$(docker compose -f "${IGOR_DIR}/docker-compose.yml" \
                exec -T -u www-data app php occ app:list --output=json 2>/dev/null \
                | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('enabled',{})))" \
                2>/dev/null || echo "?")
            _apps_dis=$(docker compose -f "${IGOR_DIR}/docker-compose.yml" \
                exec -T -u www-data app php occ app:list --output=json 2>/dev/null \
                | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('disabled',{})))" \
                2>/dev/null || echo "?")
            igor_right_render "App Management" \
                "Enabled apps"  "${_apps_en}" \
                "Disabled apps" "${_apps_dis}" \
                "hint" "[1] list  [2] enable  [3] disable  [4] install"
        fi
        local opt
        opt=$(igor_fzf_pick "6: Apps" \
            "1:LIST INSTALLED:Show all installed apps and status" \
            "2:ENABLE APP:Pick from disabled apps list" \
            "3:DISABLE APP:Pick from enabled apps list" \
            "4:INSTALL NEW APP:Browse and install from catalogue" \
            "5:VIEW CATALOGUE:Browse available apps" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "6: Apps"
        echo -e "  ${YEL}${BOLD}[6] App Management${NC}"
        echo ""
        echo "   1) List installed apps"
        echo "   2) Enable app         (shows disabled list)"
        echo "   3) Disable app        (shows enabled list)"
        echo "   4) Install new app    (shows catalogue)"
        echo "   5) View app catalogue"
        echo ""
        echo "   b) Back"
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case $opt in
            1) _mod_apps_list ;;
            2) _mod_apps_enable ;;
            3) _mod_apps_disable ;;
            4) _mod_apps_install ;;
            5) _mod_apps_catalogue ;;
            q|Q|b|B) return ;;
        esac
    done
}
