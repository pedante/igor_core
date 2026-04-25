#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/maintenance.sh
#  Maintenance operations module.
#
#  This module handles:
#    • File scanning
#    • Preview generation
#    • Database maintenance
#    • Redis cache management
#    • Nextcloud upgrades
# ==============================================================================

# ── Module helpers (prefixed with _mod_maint_) ─────────────────────────────

_mod_maint_scan_files() {
    step "Scanning all files"
    local occ="nextcloud_docker__compose exec -T -u www-data app php occ"

    info "This may take a long time on large datasets..."
    confirm "Continue?" || return

    $occ files:scan --all

    ok "File scan complete."
    declare -f notify_event &>/dev/null && \
        notify_event "nc_scan_complete" \
            "Nextcloud file scan completed via IGOR maintenance menu" \
        2>/dev/null || true
    pause
}

_mod_maint_generate_previews() {
    step "Generating file previews"
    local occ="nextcloud_docker__compose exec -T -u www-data app php occ"

    info "This uses significant RAM. Consider stopping OnlyOffice first."
    info "Preview size: 1024x1024, scale factor 1 (Pi 3 optimized)"
    confirm "Continue?" || return

    $occ preview:generate-all -vvv

    ok "Preview generation complete."
    pause
}

_mod_maint_db_maintenance() {
    step "Database maintenance"
    local occ="nextcloud_docker__compose exec -T -u www-data app php occ"

    info "Running database maintenance..."
    confirm "Continue?" || return

    $occ db:add-missing-indices
    ok "Missing indices added."

    $occ db:convert-filecache-bigint
    ok "Filecache converted to bigint."

    $occ db:add-missing-columns
    ok "Missing columns added."

    ok "Database maintenance complete."
    pause
}

_mod_maint_redis_flush() {
    step "Flushing Redis cache"
    local redis="nextcloud_docker__compose exec -T redis redis-cli"

    info "This will clear all cached data including active sessions."
    confirm "Continue?" || return

    $redis FLUSHALL

    ok "Redis cache flushed."
    pause
}

_mod_maint_upgrade() {
    step "Upgrading Nextcloud"
    local occ="nextcloud_docker__compose exec -T -u www-data app php occ"

    info "This may take 10-15 minutes on Pi 3."
    warn "Do NOT interrupt the upgrade process."
    confirm "Continue?" || return

    # Stop OnlyOffice if running to free RAM
    if nextcloud_docker__compose ps | grep -q "onlyoffice.*Up"; then
        info "Stopping OnlyOffice to free RAM for upgrade..."
        nextcloud_docker__compose stop onlyoffice
    fi

    $occ upgrade

    ok "Nextcloud upgrade complete."
    pause
}

_mod_maint_repair() {
    step "Running Nextcloud repair"
    local occ="nextcloud_docker__compose exec -T -u www-data app php occ"

    info "Running repair and cache clear..."
    confirm "Continue?" || return

    $occ maintenance:repair

    ok "Repair complete."
    pause
}

# ── [7] Fix file permissions ─────────────────────────────────────────────────
_mod_maint_fix_permissions() {
    step "Fix file permissions"
    local occ="nextcloud_docker__compose exec -T -u www-data app php occ"
    local nc_uid="${NC_UID:-1004}"
    local nc_data="${NC_DATA:-/mnt/nextclouddata/next}"

    info "Step 1: Scan all files (updates NC file cache)..."
    confirm "Continue? (may be slow on large datasets)" || return

    $occ files:scan --all 2>/dev/null && ok "File scan complete." || warn "files:scan returned non-zero"

    echo ""
    info "Step 2: Fix ownership of NC_DATA (${nc_data}) to UID ${nc_uid}..."
    warn "This runs chown -R ${nc_uid}:${nc_uid} on the data directory."
    confirm "Run chown?" || { pause; return; }

    if [ ! -d "$nc_data" ]; then
        fail "NC_DATA not found: ${nc_data}"
        pause
        return
    fi

    if chown -R "${nc_uid}:${nc_uid}" "$nc_data" 2>/dev/null; then
        ok "Ownership fixed: ${nc_data}"
    elif sudo chown -R "${nc_uid}:${nc_uid}" "$nc_data" 2>/dev/null; then
        ok "Ownership fixed (via sudo): ${nc_data}"
    else
        fail "chown failed — try manually: sudo chown -R ${nc_uid}:${nc_uid} ${nc_data}"
    fi

    pause
}

# ── [8] Flush all caches ──────────────────────────────────────────────────────
_mod_maint_flush_caches() {
    step "Flush all caches"
    local occ="nextcloud_docker__compose exec -T -u www-data app php occ"

    warn "This clears Redis (including active sessions) and runs NC maintenance:repair."
    confirm "Continue?" || return

    info "Flushing Redis..."
    docker compose exec -T redis redis-cli FLUSHALL 2>/dev/null \
        && ok "Redis: flushed" \
        || warn "Redis FLUSHALL returned non-zero"

    echo ""
    info "Running occ maintenance:repair..."
    $occ maintenance:repair 2>/dev/null \
        && ok "NC repair: done" \
        || warn "maintenance:repair returned non-zero"

    ok "All caches flushed."
    pause
}

# ── [9] Full NC repair ────────────────────────────────────────────────────────
_mod_maint_full_repair() {
    step "Full Nextcloud repair (--include-expensive)"
    local occ="nextcloud_docker__compose exec -T -u www-data app php occ"

    info "Runs maintenance:repair --include-expensive."
    info "This checks all DB constraints and repairs them — can take several minutes."
    warn "Do not interrupt."
    confirm "Continue?" || return

    $occ maintenance:repair --include-expensive 2>/dev/null \
        && ok "Full repair complete." \
        || warn "maintenance:repair --include-expensive returned non-zero"

    pause
}

# ── Dynamic menu items review ───────────────────────────────────────────────────────
pending_items_review() {
    get_pending_items_list
    local count=${#pending_item_ids[@]}

    if [ "$count" -eq 0 ]; then
        info "No pending dynamic menu items."
        pause
        return
    fi

    while true; do
        clear
        header
        echo -e "  ${YEL}${BOLD}[Pending Dynamic Menu Items]${NC}"
        echo ""

        local i=1
        for id in "${pending_item_ids[@]}"; do
            declare -A item
            read_item_file "$id"
            echo -e "  ${CYAN}$i)${NC} ${item[TITLE]}"
            echo -e "     ${item[DESCRIPTION]}"
            i=$((i+1))
        done

        echo ""
        echo -e "  ${YEL}a)${NC} Approve item  ${YEL}d)${NC} Delete item  ${YEL}v)${NC} View details  ${YEL}b)${NC} Back"
        read -rp "  Select: " opt

        case "$opt" in
            a|A)
                read -rp "  Item number to approve: " num
                if [ "$num" -ge 1 ] && [ "$num" -le "$count" ]; then
                    local id="${pending_item_ids[$((num-1))]}"
                    approve_item "$id"
                    ok "Item approved."
                    # Refresh list
                    get_pending_items_list
                    count=${#pending_item_ids[@]}
                else
                    fail "Invalid selection."
                fi
                ;;
            d|D)
                read -rp "  Item number to delete: " num
                if [ "$num" -ge 1 ] && [ "$num" -le "$count" ]; then
                    local id="${pending_item_ids[$((num-1))]}"
                    delete_item "$id"
                    ok "Item deleted."
                    # Refresh list
                    get_pending_items_list
                    count=${#pending_item_ids[@]}
                else
                    fail "Invalid selection."
                fi
                ;;
            v|V)
                read -rp "  Item number to view: " num
                if [ "$num" -ge 1 ] && [ "$num" -le "$count" ]; then
                    local id="${pending_item_ids[$((num-1))]}"
                    declare -A item
                    read_item_file "$id"
                    echo ""
                    echo -e "  ${CYAN}ID:${NC} ${item[ID]}"
                    echo -e "  ${CYAN}TITLE:${NC} ${item[TITLE]}"
                    echo -e "  ${CYAN}DESCRIPTION:${NC} ${item[DESCRIPTION]}"
                    echo -e "  ${CYAN}COMMAND:${NC} ${item[COMMAND]}"
                    echo -e "  ${CYAN}TYPE:${NC} ${item[TYPE]}"
                    echo -e "  ${CYAN}TIER:${NC} ${item[TIER]}"
                    echo -e "  ${CYAN}CONFIRMED:${NC} ${item[CONFIRMED_COUNT]}"
                    echo -e "  ${CYAN}FAILED:${NC} ${item[FAILED_COUNT]}"
                    echo -e "  ${CYAN}CREATED:${NC} ${item[CREATED]}"
                    echo -e "  ${CYAN}AUTHOR:${NC} ${item[AUTHOR]}"
                    echo ""
                    pause
                else
                    fail "Invalid selection."
                fi
                ;;
            b|B) return ;;
        esac
    done
}

# ── Run approved dynamic menu items ────────────────────────────────────────────────
dynamic_menu_items_run() {
    get_approved_items_list
    local count=${#approved_item_ids[@]}

    if [ "$count" -eq 0 ]; then
        info "No approved dynamic menu items."
        pause
        return
    fi

    while true; do
        clear
        header
        echo -e "  ${YEL}${BOLD}[Approved Dynamic Menu Items]${NC}"
        echo ""

        local i=1
        for id in "${approved_item_ids[@]}"; do
            declare -A item
            read_item_file "$id"
            echo -e "  ${CYAN}$i)${NC} ${item[TITLE]} (${item[TYPE]}) [CONFIRMED: ${item[CONFIRMED_COUNT]}, FAILED: ${item[FAILED_COUNT]}]"
            i=$((i+1))
        done

        echo ""
        echo -e "  ${YEL}1-$count)${NC} Run item  ${YEL}b)${NC} Back"
        read -rp "  Select: " opt

        case "$opt" in
            b|B) return ;;
            [0-9]*)
                if [ "$opt" -ge 1 ] && [ "$opt" -le "$count" ]; then
                    local id="${approved_item_ids[$((opt-1))]}"
                    declare -A item
                    read_item_file "$id"

                    echo ""
                    echo -e "  ${CYAN}Command:${NC} ${item[COMMAND]}"
                    echo -e "  ${CYAN}Tier:${NC} ${item[TIER]}"
                    echo ""

                    # Check tier safety
                    if [ "${item[TIER]}" = "DESTROY" ]; then
                        if ! confirm "This is a DESTROY tier command. Continue?"; then
                            continue
                        fi
                        read -rp "Type YES to confirm: " confirm_destroy
                        [ "$confirm_destroy" != "YES" ] && continue
                    elif [ "${item[TIER]}" = "CHANGE" ]; then
                        if ! confirm "This is a CHANGE tier command. Continue?"; then
                            continue
                        fi
                    fi
                    # READ tier runs automatically

                    info "Executing: ${item[COMMAND]}"
                    eval "${item[COMMAND]}"

                    # Update counters
                    local current_confirmed="${item[CONFIRMED_COUNT]:-0}"
                    item[CONFIRMED_COUNT]=$((current_confirmed + 1))
                    write_item_file "$id" item

                    ok "Command executed. Confirmed count: ${item[CONFIRMED_COUNT]}"

                    # Handle ONE_TIME vs REPEATING items
                    if [ "${item[TYPE]}" = "ONE_TIME" ]; then
                        delete_item "$id"
                        info "ONE_TIME item deleted after execution."
                    fi

                    pause

                    # Refresh list
                    get_approved_items_list
                    count=${#approved_item_ids[@]}
                else
                    fail "Invalid selection."
                fi
                ;;
        esac
    done
}

# ── Public entry point ───────────────────────────────────────────────────────────
menu_maintenance() {
    while true; do
        # Right pane: maintenance state snapshot
        if declare -f igor_right_render &>/dev/null; then
            local _mm_mode _mm_bg _mm_last
            _mm_mode=$(docker compose -f "${IGOR_DIR}/docker-compose.yml" \
                exec -T -u www-data app php occ maintenance:mode 2>/dev/null \
                | grep -o 'enabled\|disabled' || echo "?")
            _mm_bg=$(docker compose -f "${IGOR_DIR}/docker-compose.yml" \
                exec -T -u www-data app php occ background:queue:status 2>/dev/null \
                | grep -c 'status' || echo "?")
            _mm_last=$(stat -c '%y' "/data/runtime/output.log" 2>/dev/null \
                | cut -d. -f1 || echo "never")
            igor_right_render "Maintenance" \
                "Maint mode"   "${_mm_mode}" \
                "BG jobs"      "${_mm_bg}" \
                "Last output"  "${_mm_last}" \
                "hint"         "[12] run health check  [b] back"
        fi
        local _pcount; _pcount=$(get_pending_item_count 2>/dev/null || echo 0)
        local _pitem_label
        if [ "$_pcount" -gt 0 ]; then
            _pitem_label="PENDING ITEMS (${_pcount})"
        else
            _pitem_label="PENDING ITEMS"
        fi
        local opt
        opt=$(igor_fzf_pick "4: Maintenance" \
            "1:SCAN FILES:Scan all files and update the index" \
            "2:GENERATE PREVIEWS:Generate file preview thumbnails" \
            "3:DB MAINTENANCE:Run database optimization and cleanup" \
            "4:FLUSH REDIS:Clear Redis session and file-lock cache" \
            "5:UPGRADE NEXTCLOUD:Pull latest NC image and upgrade" \
            "6:RUN REPAIR:Run occ maintenance:repair" \
            "7:FIX PERMISSIONS:Fix file ownership and permissions" \
            "8:FLUSH ALL CACHES:Flush all caches at once" \
            "9:FULL REPAIR:occ maintenance:repair --include-expensive" \
            "10:${_pitem_label}:Dynamic menu items awaiting approval" \
            "11:RUN APPROVED:Execute approved dynamic menu items" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "4: Maintenance"
        echo -e "  ${YEL}${BOLD}[4] Maintenance${NC}"
        echo "   1) Scan all files"
        echo "   2) Generate file previews"
        echo "   3) Database maintenance"
        echo "   4) Flush Redis cache"
        echo "   5) Upgrade Nextcloud"
        echo "   6) Run repair"
        echo "   7) Fix file permissions"
        echo "   8) Flush all caches"
        echo "   9) Full NC repair (--include-expensive)"
        if [ "$_pcount" -gt 0 ]; then
            echo "  10) ${YEL}Pending menu items ($_pcount awaiting review)${NC}"
        else
            echo "  10) Pending menu items (none)"
        fi
        echo "  11) Run approved items"
        echo "   b) Back"
        read -rp "  Select: " opt ;; esac
        [ "$opt" = "_" ] && continue
        case $opt in
            1)  _mod_maint_scan_files ;;
            2)  _mod_maint_generate_previews ;;
            3)  _mod_maint_db_maintenance ;;
            4)  _mod_maint_redis_flush ;;
            5)  _mod_maint_upgrade ;;
            6)  _mod_maint_repair ;;
            7)  _mod_maint_fix_permissions ;;
            8)  _mod_maint_flush_caches ;;
            9)  _mod_maint_full_repair ;;
            10) pending_items_review ;;
            11) dynamic_menu_items_run ;;
            q|Q|b|B) return ;;
        esac
    done
}
