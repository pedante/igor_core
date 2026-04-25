#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/services.sh
#  Service management module.
#
#  This module handles:
#    • Start/stop/restart containers
#    • View logs
#    • Nuke (complete reset)
# ==============================================================================

# ── Module helpers (prefixed with _mod_services_) ───────────────────────────

_mod_services_start() {
    step "Starting all services"
    docker compose up -d
    ok "Services started."
    declare -f journal_record &>/dev/null && \
        journal_record "menu:services" "stack_start" "CHANGE" "docker compose up -d" "OK" "via menu" 2>/dev/null || true
    declare -f notify_event &>/dev/null && \
        notify_event "nc_services_start" \
            "Nextcloud stack started manually via IGOR Services menu on $(hostname 2>/dev/null || echo 'host')" \
        2>/dev/null || true
    pause
}

_mod_services_stop() {
    step "Stopping all services"
    docker compose down
    ok "Services stopped."
    declare -f journal_record &>/dev/null && \
        journal_record "menu:services" "stack_stop" "CHANGE" "docker compose down" "OK" "via menu" 2>/dev/null || true
    declare -f notify_event &>/dev/null && \
        notify_event "stack_down" \
            "Nextcloud stack stopped manually via Menu 4 (Services)" \
            "Stack Stopped" \
        2>/dev/null || true
    pause
}

_mod_services_restart() {
    step "Restarting all services"
    docker compose restart
    ok "Services restarted."
    declare -f journal_record &>/dev/null && \
        journal_record "menu:services" "service_restart" "CHANGE" "docker compose restart" "OK" "via menu" 2>/dev/null || true
    pause
}

_mod_services_nuke() {
    step "NUKE - Complete reset"
    warn "This will:"
    echo "   • Stop all containers"
    echo "   • Remove all containers"
    echo "   • Remove all volumes (INCLUDING DATA)"
    echo "   • Remove all images"
    echo ""
    confirm "REALLY NUKE EVERYTHING? This CANNOT be undone." || return

    docker compose down --remove-orphans
    docker compose rm -f
    docker volume rm $(docker volume ls -q) 2>/dev/null || true
    docker rmi $(docker images -q) 2>/dev/null || true

    ok "NUKE complete. All Docker resources removed."
    info "Run Menu 0 (INSTALL) for fresh setup."
    pause
}

_mod_services_logs() {
    local service="${1:-}"
    while true; do
        local opt
        opt=$(igor_fzf_pick "4: Services · Logs (${service:-all})" \
            "A:ALL LOGS:Unfiltered — last 80 lines" \
            "E:ERRORS ONLY:grep error|fatal|crit" \
            "W:WARNINGS:grep warn" \
            "C:COMBINED:Errors + warnings together" \
            "X:EXPORT ISSUES:Save to AI knowledge folder" \
            "S:SELECT SERVICE:Currently: ${service:-all}" \
            "b:BACK:Return to Services")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "4: Services" "Logs"
        if [ -z "$service" ]; then
            echo -e "  ${YEL}${BOLD}[4] Log Viewer — All Services${NC}"
        else
            echo -e "  ${YEL}${BOLD}[4] Log Viewer — ${service}${NC}"
        fi
        echo ""
        echo "   A) All         — unfiltered (last 80 lines)"
        echo "   E) Errors only — grep error|fatal|crit"
        echo "   W) Warnings    — grep warn"
        echo "   C) Combined    — errors + warnings together"
        echo "   X) Export issues to IGOR issues folder (for AI knowledge)"
        echo "   S) Select service (current: ${service:-all})"
        echo "   b) Back"
        echo ""
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case "$opt" in
            a|A)
                echo ""
                if [ -z "$service" ]; then
                    docker compose logs --tail=80 2>&1
                else
                    docker compose logs --tail=80 "$service" 2>&1
                fi
                pause ;;
            e|E)
                echo ""
                if [ -z "$service" ]; then
                    docker compose logs --tail=500 2>&1 | grep -i "error\|fatal\|crit" \
                        || echo "  (no errors found)"
                else
                    docker compose logs --tail=500 "$service" 2>&1 | grep -i "error\|fatal\|crit" \
                        || echo "  (no errors found)"
                fi
                pause ;;
            w|W)
                echo ""
                if [ -z "$service" ]; then
                    docker compose logs --tail=500 2>&1 | grep -i "warn" \
                        || echo "  (no warnings found)"
                else
                    docker compose logs --tail=500 "$service" 2>&1 | grep -i "warn" \
                        || echo "  (no warnings found)"
                fi
                pause ;;
            c|C)
                echo ""
                if [ -z "$service" ]; then
                    docker compose logs --tail=500 2>&1 | grep -i "error\|fatal\|crit\|warn" \
                        || echo "  (no issues found)"
                else
                    docker compose logs --tail=500 "$service" 2>&1 | grep -i "error\|fatal\|crit\|warn" \
                        || echo "  (no issues found)"
                fi
                pause ;;
            x|X)
                _mod_services_export_issues "$service"
                pause ;;
            s|S)
                echo ""
                info "Available services:"
                docker compose ps --services 2>/dev/null | while IFS= read -r svc; do
                    echo "    $svc"
                done
                echo "  (enter empty to view all)"
                local _svc
                read -rp "  Service name [all]: " _svc
                service="${_svc:-}"
                ;;
            b|B|q|Q) return ;;
        esac
    done
}

_mod_services_export_issues() {
    local service="${1:-}"
    local issues_dir="${NEXUS_CONFIG:-$HOME/.config/igor}/issues"
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    local outfile="${issues_dir}/errors_${ts}.log"

    mkdir -p "$issues_dir" 2>/dev/null || true

    step "Exporting issues from all monitored log sources"
    echo ""

    {
        echo "# IGOR — Issue Export — $(date)"
        echo "# Source: Docker container logs${service:+ (service: $service)} + system journal"
        echo ""
        echo "## Docker container logs (errors + warnings):"
        if [ -z "$service" ]; then
            docker compose logs --tail=500 2>&1 | grep -i "error\|fatal\|crit\|warn" || true
        else
            docker compose logs --tail=500 "$service" 2>&1 | grep -i "error\|fatal\|crit\|warn" || true
        fi
        echo ""
        echo "## System journal — last 200 lines (errors + warnings):"
        journalctl -n 200 --no-pager 2>/dev/null | grep -i "error\|fatal\|crit\|warn" || true
    } > "$outfile" 2>/dev/null

    local linecount; linecount=$(wc -l < "$outfile" 2>/dev/null || echo 0)
    ok "Exported ${linecount} lines to:"
    info "${outfile}"
    info "IGOR's AI module can reference this file via the knowledge base tool."
}

_mod_services_status() {
    step "Service status"
    docker compose ps
    pause
}

# ── Public entry point ───────────────────────────────────────────────────────────
menu_services() {
    while true; do
        # Right pane: container status (background — don't block fzf render)
        if declare -f igor_right_render &>/dev/null; then
            (
                local -a _svc_args=("Services Status")
                local _cname _cstate
                while IFS='|' read -r _cname _cstate; do
                    [ -n "$_cname" ] && _svc_args+=("$_cname" "$_cstate")
                done < <(docker compose -f "${IGOR_DIR}/docker-compose.yml" ps \
                    --format '{{.Name}}|{{.State}}' 2>/dev/null || true)
                [ "${#_svc_args[@]}" -eq 1 ] && _svc_args+=("containers" "docker not available")
                igor_right_render "${_svc_args[@]}" \
                    "---"  "Quick actions" \
                    "hint" "[1]  START ALL" \
                    "hint" "[2]  STOP ALL" \
                    "hint" "[3]  RESTART ALL" \
                    "hint" "[q]  BACK"
            ) &
        fi

        # igor_render_menu assigns keys dynamically; returns action_id
        local _action
        _action=$(igor_render_menu "Services" \
            "start_all:START ALL:Bring all containers up" \
            "stop_all:STOP ALL:Bring all containers down" \
            "restart_all:RESTART ALL:Full restart cycle" \
            "view_logs:VIEW LOGS:Filter by errors / warnings / all / export" \
            "status:STATUS:Live container status" \
            "nuke:NUKE:Destroy all containers & volumes [DESTRUCTIVE]" \
            "back:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "4: Services"
        echo -e "  ${YEL}${BOLD}[4] Service Management${NC}"
        echo "   1) Start all services"
        echo "   2) Stop all services"
        echo "   3) Restart all services"
        echo "   4) View logs  (filter: errors / warnings / all / export)"
        echo "   5) Show status"
        echo -e "   6) ${RED}NUKE${NC} — destroy all containers & volumes ${YEL}[DESTRUCTIVE]${NC}"
        echo "   b) Back"
        read -rp "  Select: " _action
        # Map legacy numeric fallback keys to action IDs
        case "$_action" in
            1) _action="start_all" ;; 2) _action="stop_all" ;;
            3) _action="restart_all" ;; 4) _action="view_logs" ;;
            5) _action="status" ;; 6) _action="nuke" ;;
            b|B|q|Q) return ;;
        esac ;; esac
        [ "$_action" = "_" ] && continue
        case "$_action" in
            start_all)   _mod_services_start   ;;
            stop_all)    _mod_services_stop    ;;
            restart_all) _mod_services_restart ;;
            view_logs)   _mod_services_logs    ;;
            status)      _mod_services_status  ;;
            nuke)        _mod_services_nuke    ;;
            back|q|Q)    return ;;
        esac
    done
}
