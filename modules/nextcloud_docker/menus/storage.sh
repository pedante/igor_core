#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/storage.sh
#  External hard drive setup, permissions, and ownership management.
#
#  Entry point: menu_storage()  (loaded by _igor_load_module "storage")
# ==============================================================================

menu_storage() {
    while true; do
        if declare -f igor_right_render &>/dev/null; then
            local _hd_status _hd_free _nc_owner
            _hd_status=$(mount | grep -q "${HD_MOUNT:-/mnt/nextclouddata}" && echo "MOUNTED" || echo "NOT MOUNTED")
            _hd_free=$(df -h "${HD_MOUNT:-/mnt/nextclouddata}" 2>/dev/null \
                | awk 'NR==2{print $4" free ("$5" used)"}' || echo "?")
            _nc_owner=$(stat -c "%u:%g" "${NC_DATA:-/mnt/nextclouddata/next}" 2>/dev/null || echo "?")
            igor_right_render "Storage" \
                "HD Mount"  "${HD_MOUNT:-/mnt/nextclouddata}" \
                "Status"    "${_hd_status}" \
                "Free"      "${_hd_free}" \
                "NC data"   "${NC_DATA:-/mnt/nextclouddata/next}" \
                "Owner"     "${_nc_owner}" \
                "---"       "Quick actions" \
                "hint"      "[1]  MOUNT STATUS" \
                "hint"      "[2]  FIX OWNERSHIP" \
                "hint"      "[3]  DISK USAGE" \
                "hint"      "[b]  BACK"
        fi

        local _opt
        _opt=$(igor_fzf_pick "2: Storage — External HD" \
            "1:MOUNT STATUS:Show mount points and HD health" \
            "2:FIX OWNERSHIP:Repair NC data dir ownership (NC_UID:NC_GID)" \
            "3:DISK USAGE:Full disk usage breakdown" \
            "4:MOUNT HD:Attempt to mount external HD (runs mount -a)" \
            "5:ADD FSTAB NOFAIL:Ensure HD fstab entry has nofail option" \
            "b:BACK:Return to previous menu" 2>/dev/null) || {
            # fzf not available — plain-text fallback
            header
            breadcrumb "Igor" "S: Setup" "2: Storage"
            echo ""
            echo -e "  ${YEL}${BOLD}[2] STORAGE — External HD Setup${NC}"
            echo ""
            echo -e "  ${DIM}── External Drive ──────────────────────────────────${NC}"
            echo -e "  ${CYAN}1.${NC} MOUNT STATUS    — Show mount points and HD health"
            echo -e "  ${CYAN}2.${NC} FIX OWNERSHIP   — Repair NC data dir ownership"
            echo -e "  ${CYAN}3.${NC} DISK USAGE      — Full disk usage breakdown"
            echo -e "  ${CYAN}4.${NC} MOUNT HD        — Attempt to mount external HD"
            echo -e "  ${CYAN}5.${NC} ADD FSTAB NOFAIL — Ensure fstab entry has nofail"
            echo ""
            echo -e "  ${CYAN}b.${NC} Back"
            echo ""
            read -rp "  Select: " _opt
        }

        [ "$_opt" = "_" ] && continue
        case "$_opt" in
            1) _storage_mount_status ;;
            2) _storage_fix_ownership ;;
            3) _storage_disk_usage ;;
            4) _storage_mount_hd ;;
            5) _storage_fstab_nofail ;;
            b|B|q|Q) return ;;
        esac
    done
}

# ── Mount status ──────────────────────────────────────────────────────────────
_storage_mount_status() {
    step "Storage: Mount Status"
    local hd="${HD_MOUNT:-/mnt/nextclouddata}"

    # HD mount
    if mount | grep -q "$hd" 2>/dev/null; then
        ok "External HD: mounted at ${hd}"
        df -h "$hd" 2>/dev/null | tail -1 | \
            awk '{printf "  Disk: %s used of %s (%s free)\n", $3, $2, $4}'
    else
        fail "External HD: NOT mounted at ${hd}"
        warn "Run option 4 to attempt mount, or check your fstab entry."
    fi

    # NC data directory
    local nc_data="${NC_DATA:-/mnt/nextclouddata/next}"
    if [ -d "$nc_data" ]; then
        ok "NC data dir: ${nc_data} exists"
        local uid gid
        uid=$(stat -c "%u" "$nc_data" 2>/dev/null)
        gid=$(stat -c "%g" "$nc_data" 2>/dev/null)
        local expected_uid="${NC_UID:-1004}" expected_gid="${NC_GID:-1004}"
        if [ "$uid" = "$expected_uid" ] && [ "$gid" = "$expected_gid" ]; then
            ok "NC data ownership: ${uid}:${gid} (correct)"
        else
            fail "NC data ownership: ${uid}:${gid} — expected ${expected_uid}:${expected_gid}"
            warn "Run option 2 to fix ownership."
        fi
    else
        fail "NC data dir: ${nc_data} does not exist"
    fi

    echo ""
    info "Root filesystem:"
    df -h / 2>/dev/null | tail -1 | \
        awk '{printf "  / : %s used of %s (%s free, %s)\n", $3, $2, $4, $5}'
    pause
}

# ── Fix ownership ─────────────────────────────────────────────────────────────
_storage_fix_ownership() {
    step "Storage: Fix NC Data Ownership"
    local nc_data="${NC_DATA:-/mnt/nextclouddata/next}"
    local uid="${NC_UID:-1004}" gid="${NC_GID:-1004}"

    if [ ! -d "$nc_data" ]; then
        fail "NC data dir not found: ${nc_data}"
        warn "Mount the external HD first (option 4)."
        pause; return
    fi

    warn "This will run: sudo chown -R ${uid}:${gid} ${nc_data}"
    warn "It may take several minutes on a large data directory."
    if confirm "Proceed?"; then
        if sudo chown -R "${uid}:${gid}" "$nc_data" 2>&1; then
            ok "Ownership fixed: ${nc_data} → ${uid}:${gid}"
            info "Restart the app container to clear any cached permission errors:"
            info "  docker compose restart app"
        else
            fail "chown failed — check sudo permissions"
        fi
    fi
    pause
}

# ── Disk usage ────────────────────────────────────────────────────────────────
_storage_disk_usage() {
    step "Storage: Disk Usage"
    echo ""
    info "Filesystem overview:"
    df -h 2>/dev/null | grep -v "^tmpfs\|^udev\|^overlay" | head -20
    echo ""
    local hd="${HD_MOUNT:-/mnt/nextclouddata}"
    if mount | grep -q "$hd" 2>/dev/null; then
        info "Top 10 largest directories under ${hd}:"
        sudo du -sh "${hd}"/* 2>/dev/null | sort -rh | head -10
    fi
    pause
}

# ── Mount HD ─────────────────────────────────────────────────────────────────
_storage_mount_hd() {
    step "Storage: Mount External HD"
    local hd="${HD_MOUNT:-/mnt/nextclouddata}"

    if mount | grep -q "$hd" 2>/dev/null; then
        ok "External HD already mounted at ${hd}"
        pause; return
    fi

    info "Running: sudo mount -a"
    if sudo mount -a 2>&1; then
        sleep 1
        if mount | grep -q "$hd" 2>/dev/null; then
            ok "External HD mounted at ${hd}"
        else
            fail "mount -a succeeded but ${hd} still not in mount list"
            warn "Check /etc/fstab entry for your external drive."
        fi
    else
        fail "mount -a failed — check /etc/fstab and cable connection"
    fi
    pause
}

# ── fstab nofail ─────────────────────────────────────────────────────────────
_storage_fstab_nofail() {
    step "Storage: Verify fstab nofail Option"
    local hd="${HD_MOUNT:-/mnt/nextclouddata}"

    if [ ! -r /etc/fstab ]; then
        fail "Cannot read /etc/fstab"
        pause; return
    fi

    local entry
    entry=$(grep "$hd" /etc/fstab 2>/dev/null | grep -v '^#' | head -1)

    if [ -z "$entry" ]; then
        warn "No fstab entry found for ${hd}"
        info "Without an fstab entry Igor cannot auto-mount the drive on reboot."
        pause; return
    fi

    info "Current fstab entry:"
    echo "  ${entry}"
    echo ""

    if echo "$entry" | grep -q "nofail"; then
        ok "fstab entry already has 'nofail' option"
    else
        warn "fstab entry is missing 'nofail' — Pi will hang on boot if drive is unplugged"
        if confirm "Add 'nofail' to this fstab entry?"; then
            sudo cp /etc/fstab /etc/fstab.bak.$(date +%s) 2>/dev/null
            sudo sed -i "s|${hd}\\([[:space:]].*\\)defaults|${hd}\\1defaults,nofail|" /etc/fstab 2>&1 && \
                ok "Added 'nofail' to fstab entry (backup saved)" || \
                fail "sed failed — edit /etc/fstab manually"
        fi
    fi
    pause
}
