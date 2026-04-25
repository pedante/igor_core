#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/lib/install/orphan.sh
#  Interactive Docker orphan cleanup (volumes, containers, images, networks).
#
#  Sourced by modules/nextcloud_docker/install.sh.
# ==============================================================================

# ── _mod_setup_orphan_cleanup ─────────────────────────────────────────────────
# Scans for Docker volumes/containers that belong to no active project.
# Interactive per-item — never bulk-deletes without showing each resource first.
_mod_setup_orphan_cleanup() {
    header
    breadcrumb "Igor" "S: Setup & Infra" "6: Orphan Cleanup"
    echo -e "  ${YEL}${BOLD}[6] Orphan Cleanup${NC}"
    echo ""

    step "Scanning for orphaned Docker resources"
    echo ""

    # ── Volumes ────────────────────────────────────────────────────────────────
    local active_vols=()
    while IFS= read -r _v; do
        active_vols+=("$_v")
    done < <(nextcloud_docker__compose config --volumes 2>/dev/null \
             | grep -v '^#' | tr -d ' ' || true)

    local all_vols=()
    while IFS= read -r _v; do
        all_vols+=("$_v")
    done < <(docker volume ls -q 2>/dev/null)

    local orphan_vols=()
    for _v in "${all_vols[@]}"; do
        local _is_active=false
        for _a in "${active_vols[@]}"; do
            [[ "$_v" == *"$_a"* ]] && { _is_active=true; break; }
        done
        # Flag volumes matching igor naming patterns not owned by current project
        if [[ "$_v" =~ _nextcloud$|_db$|_onlyoffice ]] && [[ ! "$_v" =~ ^nextcloud_ ]]; then
            orphan_vols+=("$_v")
        fi
    done

    # ── Containers ─────────────────────────────────────────────────────────────
    local orphan_containers=()
    while IFS= read -r _c; do
        [[ -n "$_c" ]] && orphan_containers+=("$_c")
    done < <(docker ps -a --filter "status=exited" --format "{{.Names}}" 2>/dev/null | grep -v '^$')

    # ── Images ─────────────────────────────────────────────────────────────────
    local orphan_images=()
    while IFS= read -r _i; do
        [[ -n "$_i" ]] && orphan_images+=("$_i")
    done < <(docker images --filter "dangling=true" --format "{{.Repository}}:{{.Tag}} ({{.ID}})" 2>/dev/null)

    # ── Display summary ────────────────────────────────────────────────────────
    if [ ${#orphan_vols[@]} -eq 0 ] && [ ${#orphan_containers[@]} -eq 0 ] && [ ${#orphan_images[@]} -eq 0 ]; then
        ok "No orphaned resources found — Docker is clean."
        pause; return
    fi

    # ── Per-volume interactive prompt ──────────────────────────────────────────
    if [ ${#orphan_vols[@]} -gt 0 ]; then
        echo -e "  ${YEL}Orphaned volumes (pattern matches old Igor installations):${NC}"
        echo ""
        for _v in "${orphan_vols[@]}"; do
            local _sz; _sz=$(docker volume inspect "$_v" \
                --format '{{.Mountpoint}}' 2>/dev/null \
                | xargs du -sh 2>/dev/null | cut -f1 || echo "?")
            echo -e "  ${CYAN}${_v}${NC}  (${_sz})"
            echo ""
            local _choice
            read -rp "    [k]eep  [d]elete  [i]nspect: " _choice
            case "${_choice,,}" in
                d)
                    docker volume rm "$_v" 2>/dev/null \
                        && ok "Deleted: ${_v}" \
                        || warn "Could not delete: ${_v}" ;;
                i)
                    echo ""
                    docker volume inspect "$_v" 2>/dev/null || true
                    echo ""
                    read -rp "    Now [k]eep or [d]elete? " _choice2
                    [[ "${_choice2,,}" == "d" ]] && \
                        docker volume rm "$_v" 2>/dev/null && ok "Deleted: ${_v}" || true ;;
                *) info "Kept: ${_v}" ;;
            esac
            echo ""
        done
    fi

    # ── Exited containers ──────────────────────────────────────────────────────
    if [ ${#orphan_containers[@]} -gt 0 ]; then
        echo -e "  ${YEL}Exited containers:${NC}"
        for _c in "${orphan_containers[@]}"; do
            printf "  ${CYAN}%-40s${NC}\n" "$_c"
        done
        echo ""
        if confirm "Remove all exited containers?"; then
            docker container prune -f 2>/dev/null && ok "Exited containers removed."
        fi
        echo ""
    fi

    # ── Dangling images ────────────────────────────────────────────────────────
    if [ ${#orphan_images[@]} -gt 0 ]; then
        echo -e "  ${YEL}Dangling images:${NC}"
        for _i in "${orphan_images[@]}"; do
            echo "  ${_i}"
        done
        echo ""
        if confirm "Remove dangling images?"; then
            docker image prune -f 2>/dev/null && ok "Dangling images removed."
        fi
        echo ""
    fi

    # ── Stale networks (subnet conflict source) ────────────────────────────────
    # Networks from old project names (igor_*, igor_new_*) share the same
    # subnet config. Docker refuses to start a new network when an old one with
    # the same subnet already exists. These are safe to remove if unused.
    local stale_nets=()
    while IFS= read -r _n; do
        [[ -n "$_n" ]] && stale_nets+=("$_n")
    done < <(docker network ls --format '{{.Name}}' 2>/dev/null \
        | grep -E "_nextcloud_network$" \
        | grep -v "^nextcloud_nextcloud_network$" || true)

    if [ ${#stale_nets[@]} -gt 0 ]; then
        echo -e "  ${YEL}Stale Docker networks (subnet conflict risk):${NC}"
        for _n in "${stale_nets[@]}"; do
            printf "  ${CYAN}%-45s${NC}\n" "$_n"
        done
        echo ""
        if confirm "Remove stale networks? (only removes unused ones)"; then
            for _n in "${stale_nets[@]}"; do
                docker network rm "$_n" 2>/dev/null \
                    && ok "Removed: ${_n}" \
                    || warn "Could not remove ${_n} — may still be in use by a container"
            done
        fi
        echo ""
    fi

    ok "Orphan cleanup complete."
    pause
}
