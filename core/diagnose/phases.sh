#!/bin/bash
# ==============================================================================
#  IGOR — diagnose/phases.sh
#  All six diagnostic phases.
#
#  Provides:
#    • _diag_collect_check()   — run a check file and tag results with phase
#    • _diag_emit()            — emit a CHECK_RESULT line (for inline checks)
#    • _diag_phase_0()         — Environment Discovery (context only, no results)
#    • _diag_phase_1()         — System Layer (Pi hardware, RAM, NTP, entropy)
#    • _diag_phase_2()         — Storage Layer (mounts, inodes, ownership)
#    • _diag_phase_3()         — Container Layer (general + role-specific)
#    • _diag_phase_4()         — Cross-Container (network, env vars, startup order)
#    • _diag_phase_5()         — Application Layer (end-to-end Nextcloud)
# ==============================================================================

# ── Emit a CHECK_RESULT line and accumulate it ─────────────────────────────────
# Usage: _diag_emit SEVERITY CODE "message" [phase_override]
_diag_emit() {
    local sev="$1" code="$2" msg="$3"
    local phase="${4:-${_DIAG[current_phase]:-0}}"
    _DIAG_RESULTS+=("${sev}|${code}|${msg}|phase${phase}")
    _diag_log "[P${phase}] ${sev} ${code}: ${msg}"

    # Print non-OK results to terminal (OK suppressed for noise)
    if [ "$sev" != "OK" ]; then
        case "$sev" in
            WARN)     warn "${code}: ${msg}" ;;
            FAIL)     fail "${code}: ${msg}" ;;
            CRITICAL) echo -e "  ${RED}${BOLD}✘ CRITICAL${NC} ${code}: ${msg}" ;;
        esac
    else
        [ "${NEXUS_VERBOSE:-false}" = "true" ] && echo -e "  ${GRN}✔${NC} ${code}"
    fi
}

# ── Collect check file results ─────────────────────────────────────────────────
# Run a healing/-style check file in a subshell, tag each result with phase.
_diag_collect_check() {
    local phase="$1"
    local check_file="$2"

    [ -f "$check_file" ] || return 1

    # Run check in subshell (healing/_healing_run_check pattern)
    local raw_output
    if declare -f _healing_run_check &>/dev/null; then
        raw_output=$(_healing_run_check "$check_file" 2>/dev/null)
    else
        # Fallback: source and run directly
        raw_output=$(
            source "${IGOR_DIR}/core/lib/ui.sh"    2>/dev/null
            source "${IGOR_DIR}/core/lib/config.sh" 2>/dev/null
            source "$check_file"
            run_check 2>/dev/null
        )
    fi

    while IFS= read -r line; do
        [[ "$line" == CHECK_RESULT* ]] || continue
        local sev code msg
        sev=$(echo "$line"  | awk '{print $2}')
        code=$(echo "$line" | awk '{print $3}')
        msg=$(echo "$line"  | cut -d' ' -f4-)
        _diag_emit "$sev" "$code" "$msg" "$phase"
    done <<< "$raw_output"
}

# ── Phase 0 — Environment Discovery ───────────────────────────────────────────
# Populates _DIAG[] context. No CHECK_RESULT entries.
_diag_phase_0() {
    _DIAG[current_phase]=0
    step "Phase 0: Environment Discovery"
    _diag_log "phase 0: start"

    # Basic identity
    _DIAG[env_hostname]=$(hostname 2>/dev/null || echo "unknown")
    _DIAG[env_pi_model]=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "unknown")
    _DIAG[env_ram_total]=$(free -m 2>/dev/null | awk 'NR==2{print $2}' || echo "?")
    _DIAG[env_swap_total]=$(free -m 2>/dev/null | awk 'NR==3{print $2}' || echo "?")
    _DIAG[env_uptime]=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "unknown")

    # Docker versions
    _DIAG[env_docker_version]=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unavailable")
    _DIAG[env_compose_version]=$(docker compose version --short 2>/dev/null || echo "unavailable")

    # Role detection (populates _DIAG_ROLES)
    if [ "${_DIAG[env_docker_version]}" != "unavailable" ]; then
        _diag_detect_roles
    fi
    _DIAG[env_roles_summary]=$(_diag_roles_summary 2>/dev/null || echo "none")

    # Heartbeat check — was previous session interrupted?
    local hb_file="${_DIAG[heartbeat_file]}"
    if [ -f "$hb_file" ]; then
        local now mtime gap
        now=$(date +%s)
        mtime=$(stat -c "%Y" "$hb_file" 2>/dev/null || echo "$now")
        gap=$(( now - mtime ))
        if (( gap > 600 )); then
            _DIAG[recovery_triggered]="Orphaned heartbeat detected (gap: ${gap}s — last session may have crashed)"
            _diag_log "phase 0: heartbeat gap ${gap}s — recovery mode flagged"
        fi
    fi

    # ── Docker daemon health ───────────────────────────────────────────────────
    local docker_info
    docker_info=$(docker info 2>&1)
    local docker_info_exit=$?
    if (( docker_info_exit != 0 )) || ! echo "$docker_info" | grep -q "Server:"; then
        _diag_emit CRITICAL docker_daemon_unhealthy "Docker daemon not responding correctly — 'docker info' failed or returned no Server section"
    else
        _diag_emit OK docker_daemon_health "Docker daemon responding (docker info OK)"
    fi

    # ── Network interfaces ─────────────────────────────────────────────────────
    local iface_list
    iface_list=$(ip -br link show 2>/dev/null | awk '{print $1}' | tr '\n' ' ' | sed 's/ *$//')
    _DIAG[env_network_ifaces]="${iface_list:-unknown}"
    # Check if we have any non-loopback interface
    local non_lo
    non_lo=$(ip -br link show 2>/dev/null | awk '$1 != "lo" {print $1}' | wc -l | tr -d '[:space:]')
    if (( non_lo == 0 )); then
        _diag_emit WARN net_no_interfaces "Only loopback interface detected — no physical/virtual network interfaces found; Docker networking may be broken"
    else
        _diag_emit OK network_interfaces "Network interfaces: ${iface_list}"
    fi

    ok "Environment: ${_DIAG[env_hostname]} · Docker ${_DIAG[env_docker_version]} · Roles: ${_DIAG[env_roles_summary]}"
    _diag_log "phase 0: complete"
}

# ── Phase 1 — System Layer ─────────────────────────────────────────────────────
_diag_phase_1() {
    local deep="${1:-false}"
    _DIAG[current_phase]=1
    step "Phase 1: System Layer"
    _diag_log "phase 1: start (deep=${deep})"

    # ── CPU temperature ───────────────────────────────────────────────────────
    local temp_file="/sys/class/thermal/thermal_zone0/temp"
    if [ -r "$temp_file" ]; then
        local raw_temp temp_c
        raw_temp=$(cat "$temp_file" 2>/dev/null || true)
        temp_c=$(( raw_temp / 1000 ))
        if (( temp_c >= 85 )); then
            _diag_emit CRITICAL cpu_temp_critical "CPU temperature ${temp_c}°C ≥ 85°C — throttling likely, causing timeouts and slowness"
        elif (( temp_c >= 75 )); then
            _diag_emit WARN cpu_temp_warn "CPU temperature ${temp_c}°C ≥ 75°C — approaching throttle threshold"
        else
            _diag_emit OK cpu_temp "CPU temperature ${temp_c}°C"
        fi
    else
        _diag_emit WARN cpu_temp_unavail "CPU temperature sensor not readable at ${temp_file}"
    fi

    # ── CPU throttling ────────────────────────────────────────────────────────
    if command -v dmesg &>/dev/null; then
        local throttle_count
        throttle_count=$(dmesg --since "1 hour ago" 2>/dev/null | grep -ic "throttl" || true)
        if (( throttle_count > 0 )); then
            _diag_emit WARN cpu_throttling "CPU throttling events in last hour: ${throttle_count} — correlate with container restarts"
        else
            _diag_emit OK cpu_throttling "No CPU throttling events in last hour"
        fi
    fi

    # ── Available RAM ─────────────────────────────────────────────────────────
    local free_mb
    free_mb=$(free -m 2>/dev/null | awk 'NR==2{print $7}' || true)
    if (( free_mb < 80 )); then
        _diag_emit CRITICAL ram_critical "Available RAM ${free_mb}MB < 80MB — OOM killer may be active, container stability at risk"
    elif (( free_mb < 150 )); then
        _diag_emit WARN ram_low "Available RAM ${free_mb}MB < 150MB — risk of OOM kills under load"
    else
        _diag_emit OK ram_ok "Available RAM ${free_mb}MB"
    fi

    # ── OOM kill events ───────────────────────────────────────────────────────
    if command -v dmesg &>/dev/null; then
        local oom_lines
        oom_lines=$(dmesg 2>/dev/null | grep -i "out of memory\|oom-kill\|killed process" | tail -5)
        if [ -n "$oom_lines" ]; then
            local oom_count
            oom_count=$(echo "$oom_lines" | wc -l)
            _diag_emit FAIL oom_events "OOM kill events found in kernel log (${oom_count} recent) — check container memory limits"
        else
            _diag_emit OK oom_events "No OOM kill events in kernel log"
        fi
    fi

    # ── Swap usage ────────────────────────────────────────────────────────────
    local swap_total swap_used swap_pct
    swap_total=$(free -m 2>/dev/null | awk 'NR==3{print $2}' || true)
    swap_used=$(free -m  2>/dev/null | awk 'NR==3{print $3}' || true)
    if (( swap_total > 0 )); then
        swap_pct=$(( swap_used * 100 / swap_total ))
        if (( swap_pct >= 85 )); then
            _diag_emit CRITICAL swap_critical "Swap usage ${swap_pct}% ≥ 85% — severe I/O latency, SD card wear accelerating"
        elif (( swap_pct >= 60 )); then
            _diag_emit WARN swap_high "Swap usage ${swap_pct}% ≥ 60% — system under memory pressure"
        else
            _diag_emit OK swap_ok "Swap usage ${swap_pct}%"
        fi
    else
        _diag_emit WARN swap_none "No swap configured — 1GB Pi 3 RAM only; add swap for stability"
    fi

    # ── NTP time sync ─────────────────────────────────────────────────────────
    if command -v timedatectl &>/dev/null; then
        local sync_status
        sync_status=$(timedatectl show --property=NTPSynchronized --value 2>/dev/null | tr -d '[:space:]')
        if [ "$sync_status" = "yes" ]; then
            _diag_emit OK ntp_sync "NTP time synchronised"
        else
            _diag_emit WARN ntp_unsync "Time not NTP-synchronised — SSL validation failures and NC integrity check failures may occur"
        fi
    fi

    # ── Entropy ───────────────────────────────────────────────────────────────
    local entropy
    entropy=$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null || echo "9999")
    # Modern kernels (5.6+) use ChaCha20 and never block even at low entropy.
    # Only flag truly extreme values — 64 is the kernel's internal minimum.
    if (( entropy < 64 )); then
        _diag_emit WARN entropy_low "Entropy pool very low (${entropy}) — consider installing haveged or rng-tools"
    else
        _diag_emit OK entropy_ok "Entropy pool ${entropy}"
    fi

    # ── Root filesystem ───────────────────────────────────────────────────────
    local root_pct
    root_pct=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}' || true)
    if (( root_pct >= 90 )); then
        _diag_emit CRITICAL disk_root_critical "Root filesystem ${root_pct}% full — Docker cannot write logs, container state may corrupt"
    elif (( root_pct >= 75 )); then
        _diag_emit WARN disk_root_warn "Root filesystem ${root_pct}% full"
    else
        _diag_emit OK disk_root_ok "Root filesystem ${root_pct}% used"
    fi

    # ── SD card errors ────────────────────────────────────────────────────────
    if command -v dmesg &>/dev/null; then
        # Get root device name (e.g. mmcblk0, sda)
        local root_dev
        root_dev=$(df / 2>/dev/null | awk 'NR==2{print $1}' | sed 's|/dev/||;s|[0-9]*$||')
        if [ -n "$root_dev" ]; then
            local io_errors
            io_errors=$(dmesg 2>/dev/null | grep -ic "I/O error.*${root_dev}\|${root_dev}.*I/O error" || true)
            if (( io_errors > 0 )); then
                _diag_emit CRITICAL sd_io_errors "SD card I/O errors detected on ${root_dev} (${io_errors} events) — DATA LOSS RISK"
            else
                _diag_emit OK sd_io_errors "No SD card I/O errors on ${root_dev}"
            fi
        fi
    fi

    # ── USB bus events ────────────────────────────────────────────────────────
    if command -v dmesg &>/dev/null; then
        local usb_disconnects
        usb_disconnects=$(dmesg 2>/dev/null | grep -ic "USB disconnect\|usb.*error\|usb.*reset" || true)
        if (( usb_disconnects > 0 )); then
            _diag_emit WARN usb_events "USB disconnect/error events in kernel log (${usb_disconnects}) — may correlate with HD unmount events"
        else
            _diag_emit OK usb_events "No USB disconnect events in kernel log"
        fi
    fi

    # ── System uptime ─────────────────────────────────────────────────────────
    local uptime_secs
    uptime_secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "9999")
    if (( uptime_secs < 1800 )); then
        _diag_emit WARN uptime_recent "System rebooted ${uptime_secs}s ago — containers may still be stabilising"
    else
        _diag_emit OK uptime_ok "System uptime $(( uptime_secs / 3600 ))h $(( (uptime_secs % 3600) / 60 ))m"
    fi

    # ── Load average vs CPU cores ─────────────────────────────────────────────
    local load1 ncores
    load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || true)
    ncores=$(nproc 2>/dev/null || echo "1")
    # Use integer arithmetic: multiply by 100 to avoid floats
    local load1_int
    load1_int=$(echo "$load1" | awk '{printf "%d", $1 * 100}')
    local thresh_warn=$(( ncores * 200 ))   # nproc * 2 * 100
    local thresh_crit=$(( ncores * 400 ))   # nproc * 4 * 100
    if (( load1_int >= thresh_crit )); then
        _diag_emit CRITICAL load_avg_critical "1-min load average ${load1} ≥ ${ncores}×4 cores — severe CPU saturation; containers will time out"
    elif (( load1_int >= thresh_warn )); then
        _diag_emit WARN load_avg_high "1-min load average ${load1} ≥ ${ncores}×2 cores — system under heavy CPU pressure"
    else
        _diag_emit OK load_avg_vs_cores "1-min load average ${load1} on ${ncores} core(s)"
    fi

    # ── Swappiness ────────────────────────────────────────────────────────────
    local swappiness
    swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "60")
    if (( swappiness > 60 )); then
        _diag_emit WARN swap_swappiness_high "vm.swappiness=${swappiness} > 60 — Pi 3 with SD card swap should use 10–30 to reduce SD card wear; fix: sysctl -w vm.swappiness=10"
    else
        _diag_emit OK swap_swappiness "vm.swappiness=${swappiness} (acceptable for Pi 3)"
    fi

    # ── Zombie processes ──────────────────────────────────────────────────────
    local zombie_count
    zombie_count=$(ps aux 2>/dev/null | awk '$8 == "Z" {count++} END {print count+0}')
    if (( zombie_count > 0 )); then
        _diag_emit WARN zombie_processes "${zombie_count} zombie process(es) detected — may indicate a crashed container entrypoint or unreaped child"
    else
        _diag_emit OK zombie_processes "No zombie processes"
    fi

    # ── Read-only filesystem check ────────────────────────────────────────────
    local ro_mounts
    ro_mounts=$(mount 2>/dev/null | grep " ro," \
        | grep -vE "^/dev/loop|squashfs|snap|tmpfs" || true)
    if [ -n "$ro_mounts" ]; then
        local hd_ro
        hd_ro=$(echo "$ro_mounts" | grep -c "${HD_MOUNT:-/mnt/nextclouddata}" || true)
        if (( hd_ro > 0 )); then
            _diag_emit FAIL ro_filesystem "External HD is mounted read-only — writes will fail; check dmesg for I/O errors causing remount"
        else
            local ro_count
            ro_count=$(echo "$ro_mounts" | wc -l | tr -d '[:space:]')
            _diag_emit WARN ro_filesystem "${ro_count} non-loop filesystem(s) mounted read-only — check if this is intentional"
        fi
    else
        _diag_emit OK ro_filesystem "No unexpected read-only mounts"
    fi

    # ── EXT4 filesystem errors in kernel log ─────────────────────────────────
    if command -v dmesg &>/dev/null; then
        local ext4_errors
        ext4_errors=$(dmesg 2>/dev/null | grep -cE "EXT4-fs error|EXT4-fs.*abort|journal abort" || true)
        if (( ext4_errors > 0 )); then
            _diag_emit FAIL ext4_fs_errors "EXT4 filesystem errors in kernel log (${ext4_errors} events) — POTENTIAL DATA CORRUPTION; run fsck when unmounted"
        else
            _diag_emit OK ext4_fs_errors "No EXT4 filesystem errors in kernel log"
        fi
    fi

    # ── Pi undervoltage detection ──────────────────────────────────────────────
    local undervoltage=0
    if command -v vcgencmd &>/dev/null; then
        local throttled_hex
        throttled_hex=$(vcgencmd get_throttled 2>/dev/null | sed 's/throttled=//')
        # Bit 16 = under-voltage has occurred; bit 0 = currently under-voltage
        if [ -n "$throttled_hex" ] && (( throttled_hex != 0 )); then
            undervoltage=1
        fi
    fi
    if (( undervoltage == 0 )) && command -v dmesg &>/dev/null; then
        local uv_count
        uv_count=$(dmesg 2>/dev/null | grep -ciE "Under-voltage|voltage.*low|undervoltage" || true)
        (( uv_count > 0 )) && undervoltage=$uv_count
    fi
    if (( undervoltage > 0 )); then
        _diag_emit WARN pi_undervoltage "Pi undervoltage detected (${undervoltage} event(s)) — use official Pi power supply ≥2.5A; causes random crashes and SD corruption"
    else
        _diag_emit OK pi_undervoltage "No undervoltage events detected"
    fi

    # ── Igor secret file permissions ─────────────────────────────────────────
    # Checks secrets/ env files and API key files: all should be 600 (no group/world bits).
    local _insecure_files=()
    local _secrets_dir="${IGOR_DIR}/secrets"
    if [ -d "$_secrets_dir" ]; then
        for _sf in "${_secrets_dir}"/*.env; do
            [ -f "$_sf" ] || continue
            local _sp; _sp=$(stat -c "%a" "$_sf" 2>/dev/null || echo "")
            [ -z "$_sp" ] && continue
            # Last two octal digits = group + world bits; any non-zero → insecure
            [[ "${_sp: -2}" != "00" ]] && _insecure_files+=("${_sf#"${IGOR_DIR}/"}")
        done
    fi
    for _kf in "${HOME}/.nexus_api_key" "${HOME}/.nexus_or_key"; do
        [ -f "$_kf" ] || continue
        local _kp; _kp=$(stat -c "%a" "$_kf" 2>/dev/null || echo "")
        [ -z "$_kp" ] && continue
        [[ "${_kp: -2}" != "00" ]] && _insecure_files+=("$_kf")
    done
    if [ ${#_insecure_files[@]} -gt 0 ]; then
        local _if_list; _if_list="${_insecure_files[*]}"
        _diag_emit WARN igor_insecure_perms \
            "Insecure permissions on ${#_insecure_files[@]} secret file(s) (should be 600): ${_if_list}"
    else
        _diag_emit OK igor_insecure_perms "Igor secret file permissions OK"
    fi

    # ── Deep mode: extended dmesg scan ────────────────────────────────────────
    if [ "$deep" = "true" ]; then
        _diag_phase_1_deep_checks
    fi

    _diag_log "phase 1: complete"
}

_diag_phase_1_deep_checks() {
    info "Phase 1 deep: extended kernel log scan"
    local errors
    errors=$(dmesg 2>/dev/null | grep -iE "error|fail|panic|oops|bug:" | tail -20)
    if [ -n "$errors" ]; then
        local count
        count=$(echo "$errors" | wc -l)
        _diag_emit WARN kernel_errors "Kernel log has ${count} error/fail/panic entries (deep scan)"
    else
        _diag_emit OK kernel_errors "Kernel log clean (deep scan)"
    fi
}

# ── Phase 2 — Storage Layer ────────────────────────────────────────────────────
_diag_phase_2() {
    local deep="${1:-false}"
    _DIAG[current_phase]=2
    step "Phase 2: Storage Layer"
    _diag_log "phase 2: start (deep=${deep})"

    # ── Reuse healing storage check ───────────────────────────────────────────
    local healing_storage="${IGOR_DIR}/modules/system/checks/storage.sh"
    if [ -f "$healing_storage" ]; then
        _diag_collect_check 2 "$healing_storage"
    fi

    # ── HD mount content verification ─────────────────────────────────────────
    if mount | grep -q "${HD_MOUNT:-/mnt/nextclouddata}" 2>/dev/null; then
        # Check NC data marker
        local marker="${NC_DATA:-/mnt/nextclouddata/next}/.ncdata"
        if [ -f "$marker" ]; then
            _diag_emit OK nc_data_marker "NC data marker file (.ncdata) present"
        else
            _diag_emit WARN nc_data_marker_missing "NC data marker file (.ncdata) absent — NC may not have initialised the data directory"
        fi
    fi

    # ── fstab nofail check ────────────────────────────────────────────────────
    if [ -r /etc/fstab ]; then
        local hd_device
        hd_device=$(grep "${HD_MOUNT:-/mnt/nextclouddata}" /etc/fstab 2>/dev/null | grep -v '^#' | head -1)
        if [ -n "$hd_device" ]; then
            if echo "$hd_device" | grep -q "nofail"; then
                _diag_emit OK fstab_nofail "External HD fstab entry has nofail option"
            else
                _diag_emit WARN fstab_nofail_missing "External HD fstab entry lacks nofail — missing drive at boot will drop system to emergency mode"
            fi
        fi
    fi

    # ── fstab optimization checks ─────────────────────────────────────────────
    if [ -r /etc/fstab ]; then
        local hd_fstab_line
        hd_fstab_line=$(grep "${HD_MOUNT:-/mnt/nextclouddata}" /etc/fstab 2>/dev/null | grep -v '^#' | head -1)
        if [ -n "$hd_fstab_line" ]; then
            if ! echo "$hd_fstab_line" | grep -q "noatime"; then
                _diag_emit WARN fstab_noatime "HD fstab entry lacks 'noatime' — access time updates cause unnecessary SD card writes; add noatime to mount options"
            else
                _diag_emit OK fstab_optimization "HD fstab entry has noatime"
            fi
            if ! echo "$hd_fstab_line" | grep -q "errors=remount-ro"; then
                _diag_emit WARN fstab_errors_opt "HD fstab entry lacks 'errors=remount-ro' — without this, filesystem errors may cause silent data corruption instead of a safe remount-ro"
            fi
        fi
    fi

    # ── tmpfs usage ───────────────────────────────────────────────────────────
    local tmpfs_line
    while IFS= read -r tmpfs_line; do
        local mnt_pt pct
        mnt_pt=$(echo "$tmpfs_line" | awk '{print $6}')
        pct=$(echo "$tmpfs_line" | awk '{gsub(/%/,"",$5); print $5}')
        if (( pct >= 80 )); then
            _diag_emit WARN "tmpfs_high_${mnt_pt//\//_}" "tmpfs at ${mnt_pt} is ${pct}% full — /tmp or /run running out of space causes unpredictable failures"
        fi
    done < <(df -t tmpfs 2>/dev/null | awk 'NR>1')

    # ── Docker container log bloat ────────────────────────────────────────────
    if [ -d /var/lib/docker/containers ]; then
        local big_logs
        big_logs=$(find /var/lib/docker/containers -name "*.log" -size +100M 2>/dev/null | wc -l | tr -d '[:space:]')
        if (( big_logs > 0 )); then
            local total_log_mb
            total_log_mb=$(du -sm /var/lib/docker/containers 2>/dev/null | awk '{print $1}' || echo "?")
            _diag_emit WARN docker_log_bloat "${big_logs} container log file(s) > 100MB (total docker/containers: ${total_log_mb}MB) — add logging driver limits or truncate"
        else
            _diag_emit OK docker_log_bloat "No container log files > 100MB"
        fi

        # ── Docker log directory total size ───────────────────────────────────
        local containers_mb
        containers_mb=$(du -sm /var/lib/docker/containers 2>/dev/null | awk '{print $1}' || true)
        if (( containers_mb > 500 )); then
            _diag_emit WARN docker_log_size "Docker containers directory is ${containers_mb}MB > 500MB — log accumulation likely; consider log rotation"
        else
            _diag_emit OK docker_log_size "Docker containers directory: ${containers_mb}MB"
        fi
    fi

    # ── USB autosuspend check ─────────────────────────────────────────────────
    # Autosuspend on the USB bus device that owns the HD can cause random HD disconnects.
    # Find USB devices that have block device children (i.e. the HD's USB bridge).
    local usb_suspend_warn=0
    local usb_suspend_detail=""
    local usb_dev
    for usb_dev in /sys/bus/usb/devices/*/power/autosuspend_delay_ms; do
        [ -r "$usb_dev" ] || continue
        local delay
        delay=$(cat "$usb_dev" 2>/dev/null | tr -d '[:space:]')
        # Autosuspend is active when delay >= 0; -1 means disabled
        [[ "$delay" =~ ^-?[0-9]+$ ]] || continue
        if (( delay >= 0 )); then
            # Check if this USB device has block device children
            local usb_path="${usb_dev%/power/autosuspend_delay_ms}"
            local has_block
            has_block=$(find "$usb_path" -name "block" -type d 2>/dev/null | head -1)
            if [ -n "$has_block" ]; then
                usb_suspend_warn=1
                usb_suspend_detail="${usb_path##*/sys/bus/usb/devices/} (delay=${delay}ms)"
                break
            fi
        fi
    done
    if (( usb_suspend_warn )); then
        _diag_emit WARN usb_autosuspend_enabled "USB autosuspend active on storage device ${usb_suspend_detail} — can cause HD disconnects under load; fix: echo -1 > /sys/bus/usb/devices/.../power/autosuspend_delay_ms"
    else
        _diag_emit OK usb_autosuspend "USB autosuspend not active on storage devices"
    fi

    # ── SMART health check ────────────────────────────────────────────────────
    if command -v smartctl &>/dev/null; then
        # Find the HD device via the mount point
        local hd_dev
        hd_dev=$(df "${HD_MOUNT:-/mnt/nextclouddata}" 2>/dev/null | awk 'NR==2{print $1}' | sed 's/[0-9]*$//' | head -1)
        if [ -n "$hd_dev" ] && [ -b "$hd_dev" ]; then
            local smart_result
            smart_result=$(sudo -n smartctl -H "$hd_dev" 2>/dev/null | grep "SMART overall-health\|result:" || echo "")
            if echo "$smart_result" | grep -qi "FAILED"; then
                _diag_emit FAIL smartctl_health "SMART health check FAILED on ${hd_dev} — drive failure imminent; backup data immediately"
            elif echo "$smart_result" | grep -qi "old_age\|pre-fail"; then
                _diag_emit WARN smartctl_health "SMART reports old_age/pre-fail attributes on ${hd_dev} — drive aging; consider replacement"
            elif [ -n "$smart_result" ]; then
                _diag_emit OK smartctl_health "SMART health PASSED on ${hd_dev}"
            fi
        fi
    fi

    # ── Inode usage ───────────────────────────────────────────────────────────
    local mounts_to_check=("/" "${HD_MOUNT:-/mnt/nextclouddata}")
    local mnt
    for mnt in "${mounts_to_check[@]}"; do
        if mount | grep -q " $mnt " 2>/dev/null || [ "$mnt" = "/" ]; then
            local inode_pct
            inode_pct=$(df -i "$mnt" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}' || true)
            local code_suffix
            code_suffix=$(echo "$mnt" | tr '/' '_' | sed 's/^_//')
            if (( inode_pct >= 95 )); then
                _diag_emit CRITICAL "inodes_critical_${code_suffix}" "Inode usage ${inode_pct}% on ${mnt} — writes failing despite available disk space"
            elif (( inode_pct >= 80 )); then
                _diag_emit WARN "inodes_warn_${code_suffix}" "Inode usage ${inode_pct}% on ${mnt}"
            else
                _diag_emit OK "inodes_ok_${code_suffix}" "Inode usage ${inode_pct}% on ${mnt}"
            fi
        fi
    done

    # ── Docker storage ────────────────────────────────────────────────────────
    if [ -d /var/lib/docker ]; then
        local docker_pct
        docker_pct=$(df /var/lib/docker 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}' || true)
        if (( docker_pct >= 95 )); then
            _diag_emit CRITICAL disk_docker_critical "Docker storage /var/lib/docker at ${docker_pct}% — containers will fail to write logs"
        elif (( docker_pct >= 85 )); then
            _diag_emit WARN disk_docker_warn "Docker storage /var/lib/docker at ${docker_pct}%"
        else
            _diag_emit OK disk_docker_ok "Docker storage at ${docker_pct}%"
        fi
    fi

    # ── NC_DATA permissions ───────────────────────────────────────────────────
    if [ -d "${NC_DATA:-/mnt/nextclouddata/next}" ]; then
        local perms
        perms=$(stat -c "%a" "${NC_DATA:-/mnt/nextclouddata/next}" 2>/dev/null || echo "000")
        # Should be 750 (not world-readable)
        if [[ "$perms" == *"7" ]]; then
            _diag_emit WARN nc_data_world_readable "NC data directory permissions ${perms} — should not be world-readable (should be 750)"
        else
            _diag_emit OK nc_data_perms "NC data directory permissions ${perms}"
        fi
    fi

    # ── Deep: tune2fs error check ─────────────────────────────────────────────
    if [ "$deep" = "true" ] && command -v tune2fs &>/dev/null; then
        local hd_device
        hd_device=$(df "${HD_MOUNT:-/mnt/nextclouddata}" 2>/dev/null | awk 'NR==2{print $1}' | head -1)
        if [ -n "$hd_device" ]; then
            local err_count
            err_count=$(sudo -n tune2fs -l "$hd_device" 2>/dev/null | grep "Mount count\|Filesystem errors" | grep -i "errors" | awk '{print $NF}')
            if [ -n "$err_count" ] && (( err_count > 0 )); then
                _diag_emit WARN fs_errors "tune2fs reports ${err_count} filesystem errors on ${hd_device}"
            fi
        fi
    fi

    _diag_log "phase 2: complete"
}

# ── Phase 3 — Container Layer ──────────────────────────────────────────────────
_diag_phase_3() {
    local deep="${1:-false}"
    _DIAG[current_phase]=3
    step "Phase 3: Container Layer"
    _diag_log "phase 3: start (deep=${deep})"

    # ── General container checks (reuse healing) ───────────────────────────────
    local healing_containers="${IGOR_DIR}/modules/nextcloud_docker/checks/containers.sh"
    if [ -f "$healing_containers" ]; then
        _diag_collect_check 3 "$healing_containers"
    fi

    # ── Docker restart policies ───────────────────────────────────────────────
    local no_restart_svcs
    no_restart_svcs=$(docker compose config 2>/dev/null | python3 -c "
import sys
try:
    import yaml
except ImportError:
    print('')
    sys.exit(0)
import yaml
try:
    data = yaml.safe_load(sys.stdin)
    services = data.get('services', {})
    bad = []
    for name, cfg in services.items():
        policy = (cfg.get('restart') or 'no')
        if policy in ('no', ''):
            bad.append(name)
    print(','.join(bad))
except Exception:
    print('')
" 2>/dev/null || echo "")
    if [ -n "$no_restart_svcs" ]; then
        _diag_emit WARN docker_restart_policies "Services with no restart policy (will not auto-restart after crash): ${no_restart_svcs} — set restart: unless-stopped"
    else
        _diag_emit OK docker_restart_policies "All services have a restart policy configured"
    fi

    # ── Role-specific checks ───────────────────────────────────────────────────
    local role svc
    for role in web app db cache tunnel cron; do
        svc="${_DIAG_ROLES[$role]:-}"
        [ -z "$svc" ] && continue

        # Verify container is actually running before role checks
        local running
        running=$(docker compose ps --status running --services 2>/dev/null | grep -c "^${svc}$" || true)
        if (( running == 0 )); then
            _diag_log "phase 3: skipping role checks for ${role}=${svc} (not running)"
            continue
        fi

        info "Checking ${role} role: ${svc}"
        case "$role" in
            web)   _diag_check_role_web   "$svc" "$deep" ;;
            app)
                # Dispatch to registered role_check_app hooks (in-process so _diag_emit works).
                # Registered by modules via: igor_register_hook "role_check_app" "fn_name"
                local _rc_fn
                for _rc_fn in $(declare -f igor_get_hooks &>/dev/null && \
                                igor_get_hooks "role_check_app" 2>/dev/null || true); do
                    declare -f "$_rc_fn" &>/dev/null && "$_rc_fn" "$svc" "$deep"
                done
                ;;
            db)    _diag_check_role_db    "$svc" "$deep" ;;
            cache) _diag_check_role_cache "$svc" "$deep" ;;
            tunnel)_diag_check_role_tunnel "$svc" "$deep" ;;
            cron)  _diag_check_role_cron  "$svc" "$deep" ;;
        esac
    done

    _diag_log "phase 3: complete"
}

# ── Role: web (nginx) ──────────────────────────────────────────────────────────
_diag_check_role_web() {
    local svc="$1" deep="$2"

    # nginx config syntax
    local nginx_test
    nginx_test=$(docker compose exec -T "$svc" nginx -t 2>&1)
    if echo "$nginx_test" | grep -qi "syntax is ok"; then
        _diag_emit OK nginx_config_ok "nginx configuration syntax OK"
    else
        _diag_emit FAIL nginx_config_invalid "nginx configuration has syntax errors — reload will fail: $(echo "$nginx_test" | tail -1)"
    fi

    # conf.d/default.conf must be absent
    local default_conf
    default_conf=$(docker compose exec -T "$svc" ls /etc/nginx/conf.d/ 2>/dev/null)
    if echo "$default_conf" | grep -q "default.conf"; then
        _diag_emit FAIL nginx_default_conf "conf.d/default.conf present — causes 403 on all requests (deleted on clean container start)"
    else
        _diag_emit OK nginx_conf_d_clean "conf.d/ directory clean (no default.conf)"
    fi

    # HTTP routing spot-check
    local http_port=$(igor_get_port "nextcloud_http" "8080")
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 http://localhost:${http_port}/status.php 2>/dev/null)
    case "$code" in
        200) _diag_emit OK nginx_route_status "status.php → 200" ;;
        404) _diag_emit FAIL nginx_404_status "status.php → 404 — missing location block in nginx config" ;;
        403) _diag_emit FAIL nginx_403_status "status.php → 403 — nginx config issue (try_files or conf.d/default.conf)" ;;
        000) _diag_emit FAIL nginx_not_responding "nginx not responding on :${http_port}" ;;
        *)   _diag_emit WARN "nginx_unexpected_status" "status.php → unexpected HTTP ${code}" ;;
    esac

    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 http://localhost:${http_port}/apps/files/ 2>/dev/null)
    case "$code" in
        200)         _diag_emit OK nginx_route_files "/apps/files/ → 200" ;;
        301|302|307) _diag_emit OK nginx_route_files "/apps/files/ → ${code} redirect (expected)" ;;
        401)         _diag_emit OK nginx_route_files "/apps/files/ → 401 (auth required — correct for unauthenticated request)" ;;
        403)         _diag_emit FAIL nginx_403_apps_files "/apps/files/ → 403 — try_files in location / or conf.d/default.conf present" ;;
        000)         : ;; # nginx_not_responding already reported above
        *)           _diag_emit WARN nginx_apps_files_unexpected "/apps/files/ → HTTP ${code} (unexpected)" ;;
    esac

    # Fastcgi params — check for required directives
    local nginx_conf
    nginx_conf=$(docker compose exec -T "$svc" nginx -T 2>/dev/null)
    if ! echo "$nginx_conf" | grep -q "HTTP_X_FORWARDED_PROTO"; then
        _diag_emit WARN nginx_no_forwarded_proto "HTTP_X_FORWARDED_PROTO not set in fastcgi_params — secure cookie check will fail via Cloudflare"
    else
        _diag_emit OK nginx_forwarded_proto "HTTP_X_FORWARDED_PROTO fastcgi param present"
    fi

    # client_max_body_size
    local max_body
    max_body=$(echo "$nginx_conf" | grep -i "client_max_body_size" | head -1 | awk '{print $2}' | tr -d ';')
    if [ -z "$max_body" ]; then
        _diag_emit WARN nginx_no_body_limit "client_max_body_size not set — uploads limited to nginx default (1MB)"
    else
        _diag_emit OK nginx_body_size "client_max_body_size: ${max_body}"
    fi

    # worker_connections
    local worker_conns
    worker_conns=$(echo "$nginx_conf" | grep -i "worker_connections" | head -1 | awk '{print $2}' | tr -d ';[:space:]')
    if [ -n "$worker_conns" ] && (( worker_conns < 256 )); then
        _diag_emit WARN nginx_worker_connections "worker_connections=${worker_conns} < 256 — may limit concurrent Nextcloud requests; recommend ≥ 256"
    else
        _diag_emit OK nginx_worker_connections "worker_connections: ${worker_conns:-default}"
    fi

    # .well-known routing — must have location ^~ /.well-known block in nginx config
    # Admin panel warning "web server not configured" for .well-known = missing nginx block, not occ issue
    if echo "$nginx_conf" | grep -q '\.well-known'; then
        local wk_code
        wk_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:${http_port}/.well-known/webfinger 2>/dev/null)
        case "$wk_code" in
            301|302|200) _diag_emit OK nginx_well_known ".well-known routed correctly (HTTP ${wk_code})" ;;
            404)         _diag_emit WARN nginx_well_known_404 "/.well-known/webfinger → 404 — nginx block present but route unreachable" ;;
            *)           _diag_emit WARN nginx_well_known_status "/.well-known/webfinger → HTTP ${wk_code:-000}" ;;
        esac
    else
        _diag_emit FAIL nginx_well_known_missing "No .well-known location block in nginx config — NC admin will warn 'web server not configured'. Fix: add location ^~ /.well-known block before location / in ./web/nginx.conf"
    fi

    # SSL — terminated by Cloudflare, no local cert to check
    _diag_emit OK nginx_ssl_cloudflare "SSL handled by Cloudflare tunnel (no local certificate to check)"
}

# ── Role: app — moved to modules/nextcloud_docker/module.sh ──────────────────
# _diag_check_role_app() was removed from core. Modules register via:
#   igor_register_hook "role_check_app" "fn_name"
# The nextcloud_docker module registers _nc_check_role_app for this hook.
#
# ── Role: db (PostgreSQL) ──────────────────────────────────────────────────────
_diag_check_role_db() {
    local svc="$1" deep="$2"

    # pg_isready
    if docker compose exec -T "$svc" pg_isready -q 2>/dev/null; then
        _diag_emit OK db_ready "PostgreSQL accepting connections (pg_isready)"
    else
        _diag_emit CRITICAL db_not_ready "PostgreSQL not accepting connections — may be in crash recovery or starting up"
        return
    fi

    # Connection count
    local db_name="${POSTGRES_DB:-nextcloud}"
    local conn_info
    conn_info=$(docker compose exec -T "$svc" psql -U "${POSTGRES_USER:-oc_admin}" -d "$db_name" \
        -t -c "SELECT count(*), (SELECT setting FROM pg_settings WHERE name='max_connections') FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')
    if [ -n "$conn_info" ]; then
        local cur max
        IFS='|' read -r cur max <<< "$conn_info"
        cur="${cur//[[:space:]]/}"
        max="${max//[[:space:]]/}"
        if [ -n "$max" ] && [ -n "$cur" ] && (( max > 0 )); then
            local conn_pct=$(( cur * 100 / max ))
            if (( conn_pct >= 80 )); then
                _diag_emit WARN db_conn_high "DB connections: ${cur}/${max} (${conn_pct}%) — new connections may be refused"
            else
                _diag_emit OK db_conn_ok "DB connections: ${cur}/${max} (${conn_pct}%)"
            fi
        fi
    fi

    # Stale postmaster.pid check
    local pg_pid_exists
    pg_pid_exists=$(docker compose exec -T "$svc" sh -c '[ -f /var/lib/postgresql/data/postmaster.pid ] && echo yes || echo no' 2>/dev/null | tr -d '[:space:]')
    if [ "$pg_pid_exists" = "yes" ]; then
        _diag_emit OK db_postmaster_pid "postmaster.pid present (PostgreSQL running)"
    fi

    # Deep: long queries, lock contention, WAL size
    if [ "$deep" = "true" ]; then
        _diag_check_role_db_deep "$svc" "$db_name"
    fi
}

_diag_check_role_db_deep() {
    local svc="$1" db_name="$2"
    local db_user="${POSTGRES_USER:-oc_admin}"

    # Long-running queries
    local long_q
    long_q=$(docker compose exec -T "$svc" psql -U "$db_user" -d "$db_name" \
        -t -c "SELECT count(*) FROM pg_stat_activity WHERE state='active' AND now()-query_start > interval '30 seconds';" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$long_q" ] && (( long_q > 0 )); then
        _diag_emit WARN db_long_queries "${long_q} queries running longer than 30s — possible lock or index issue"
    else
        _diag_emit OK db_long_queries "No queries running longer than 30s"
    fi

    # Lock contention
    local blocked
    blocked=$(docker compose exec -T "$svc" psql -U "$db_user" -d "$db_name" \
        -t -c "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock';" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$blocked" ] && (( blocked > 0 )); then
        _diag_emit WARN db_lock_contention "${blocked} queries waiting on locks — application may be hanging"
    else
        _diag_emit OK db_locks_ok "No lock contention"
    fi

    # WAL size
    local wal_size
    wal_size=$(docker compose exec -T "$svc" du -sm /var/lib/postgresql/data/pg_wal 2>/dev/null | awk '{print $1}' || true)
    if (( wal_size > 512 )); then
        _diag_emit WARN db_wal_large "pg_wal directory is ${wal_size}MB — excessive WAL accumulation may fill volume"
    else
        _diag_emit OK db_wal_ok "pg_wal directory ${wal_size}MB"
    fi

    # Max connections — Pi 3 constraint (each PG connection ~5MB RAM)
    local max_conn
    max_conn=$(docker compose exec -T "$svc" psql -U "$db_user" -d "$db_name" \
        -t -c "SELECT current_setting('max_connections')::int;" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$max_conn" ] && (( max_conn > 100 )); then
        _diag_emit WARN db_max_connections "max_connections=${max_conn} > 100 — each PG connection uses ~5MB RAM; on Pi 3 (1GB) this risks OOM under full connection load"
    elif [ -n "$max_conn" ]; then
        _diag_emit OK db_max_connections "max_connections=${max_conn} (acceptable for Pi 3)"
    fi

    # Vacuum status — tables that have never been vacuumed or not in 7 days
    local stale_tables
    stale_tables=$(docker compose exec -T "$svc" psql -U "$db_user" -d "$db_name" \
        -t -c "SELECT count(*) FROM pg_stat_user_tables WHERE last_autovacuum < now() - interval '7 days' OR last_autovacuum IS NULL;" \
        2>/dev/null | tr -d '[:space:]')
    if [ -n "$stale_tables" ] && (( stale_tables > 5 )); then
        _diag_emit WARN db_vacuum_stale "${stale_tables} tables not vacuumed in 7+ days — dead tuples accumulate; query performance degrades; run VACUUM ANALYZE"
    else
        _diag_emit OK db_vacuum_status "Autovacuum running (${stale_tables:-0} tables pending)"
    fi

    # Buffer/index cache hit rate — should be > 90% for healthy workload
    local cache_hit_rate
    cache_hit_rate=$(docker compose exec -T "$svc" psql -U "$db_user" -d "$db_name" \
        -t -c "SELECT round(sum(blks_hit)*100/nullif(sum(blks_hit+blks_read),0)) FROM pg_statio_user_tables;" \
        2>/dev/null | tr -d '[:space:]')
    if [ -n "$cache_hit_rate" ] && [ "$cache_hit_rate" != "" ] && (( cache_hit_rate < 90 )); then
        _diag_emit WARN db_index_cache_hit_rate "DB buffer cache hit rate ${cache_hit_rate}% < 90% — queries are reading from disk; increase shared_buffers or reduce DB load"
    elif [ -n "$cache_hit_rate" ] && [ "$cache_hit_rate" != "" ]; then
        _diag_emit OK db_index_cache_hit_rate "DB buffer cache hit rate ${cache_hit_rate}%"
    fi
}

# ── Role: cache (Redis) ────────────────────────────────────────────────────────
_diag_check_role_cache() {
    local svc="$1" deep="$2"

    # Reuse healing caching check
    local healing_cache="${IGOR_DIR}/modules/nextcloud_docker/checks/caching.sh"
    if [ -f "$healing_cache" ]; then
        _diag_collect_check 3 "$healing_cache"
    fi

    # Additional checks not in healing/
    local ping
    ping=$(docker compose exec -T "$svc" redis-cli PING 2>/dev/null | tr -d '[:space:]')
    [ "$ping" = "PONG" ] || return

    # Eviction count
    local evicted
    evicted=$(docker compose exec -T "$svc" redis-cli INFO stats 2>/dev/null | grep "evicted_keys" | cut -d: -f2 | tr -d '[:space:]')
    if [ -n "$evicted" ] && (( evicted > 0 )); then
        _diag_emit WARN redis_evictions "Redis has evicted ${evicted} keys — session data may have been lost; check maxmemory"
    else
        _diag_emit OK redis_evictions "Redis: 0 evictions"
    fi

    # Eviction policy
    local policy
    policy=$(docker compose exec -T "$svc" redis-cli CONFIG GET maxmemory-policy 2>/dev/null | tail -1 | tr -d '[:space:]')
    if [ "$policy" = "allkeys-lru" ]; then
        _diag_emit WARN redis_eviction_policy "Redis eviction policy is allkeys-lru — will evict session data silently (should be volatile-lru or noeviction)"
    else
        _diag_emit OK redis_policy "Redis eviction policy: ${policy:-default}"
    fi

    # Persistence status
    local bgsave
    bgsave=$(docker compose exec -T "$svc" redis-cli INFO persistence 2>/dev/null | grep "rdb_last_bgsave_status" | cut -d: -f2 | tr -d '[:space:]')
    if [ "$bgsave" = "err" ]; then
        _diag_emit WARN redis_bgsave_failed "Redis background save failed — data will be lost on restart"
    else
        _diag_emit OK redis_persistence "Redis persistence status: ${bgsave:-ok}"
    fi

    # maxmemory configured
    local redis_maxmem
    redis_maxmem=$(docker compose exec -T "$svc" redis-cli CONFIG GET maxmemory 2>/dev/null | tail -1 | tr -d '[:space:]')
    if [ -z "$redis_maxmem" ] || [ "$redis_maxmem" = "0" ]; then
        _diag_emit WARN redis_maxmemory_not_set "Redis maxmemory not set (unlimited) — Redis can consume all available RAM and trigger OOM kills on Pi 3; set maxmemory 100mb"
    else
        # Convert bytes to MB for display
        local maxmem_mb=$(( redis_maxmem / 1048576 ))
        _diag_emit OK redis_maxmemory_configured "Redis maxmemory=${maxmem_mb}MB"

        # Check how close we are to the limit
        local used_mem
        used_mem=$(docker compose exec -T "$svc" redis-cli INFO memory 2>/dev/null \
            | grep "^used_memory:" | cut -d: -f2 | tr -d '[:space:]' || true)
        if [ -n "$used_mem" ] && [ -n "$redis_maxmem" ] && (( redis_maxmem > 0 )); then
            local mem_pct=$(( used_mem * 100 / redis_maxmem ))
            if (( mem_pct >= 90 )); then
                _diag_emit WARN redis_maxmemory_enforced "Redis memory usage ${mem_pct}% of maxmemory (${maxmem_mb}MB) — evictions imminent; session data at risk"
            else
                _diag_emit OK redis_maxmemory_enforced "Redis memory ${mem_pct}% of limit (${maxmem_mb}MB)"
            fi
        fi
    fi

    # Deep: hit rate + slowlog
    if [ "$deep" = "true" ]; then
        _diag_check_role_cache_deep "$svc"
    fi
}

_diag_check_role_cache_deep() {
    local svc="$1"

    local stats
    stats=$(docker compose exec -T "$svc" redis-cli INFO stats 2>/dev/null)
    local hits misses
    hits=$(echo "$stats" | grep "keyspace_hits" | cut -d: -f2 | tr -d '[:space:]')
    misses=$(echo "$stats" | grep "keyspace_misses" | cut -d: -f2 | tr -d '[:space:]')

    if [ -n "$hits" ] && [ -n "$misses" ]; then
        local total=$(( hits + misses ))
        # Require 500+ requests for a meaningful sample — avoids false positives
        # on freshly started or recently-recovered systems
        if (( total > 500 )); then
            local hit_pct=$(( hits * 100 / total ))
            if (( hit_pct < 70 )); then
                _diag_emit WARN redis_hit_rate "Cache hit rate ${hit_pct}% < 70% — cache too small or eviction occurring; check maxmemory"
            else
                _diag_emit OK redis_hit_rate "Cache hit rate ${hit_pct}%"
            fi
        else
            _diag_emit OK redis_hit_rate "Cache hit rate not yet meaningful (${total} requests — need 500+ for reliable reading)"
        fi
    fi
}

# ── Role: tunnel (cloudflared) ─────────────────────────────────────────────────
_diag_check_role_tunnel() {
    local svc="$1" deep="$2"

    # Process alive inside container
    local cf_pid
    cf_pid=$(docker compose exec -T "$svc" pgrep cloudflared 2>/dev/null | head -1 | tr -d '[:space:]')
    if [ -n "$cf_pid" ]; then
        _diag_emit OK tunnel_process "cloudflared process alive in container (PID ${cf_pid})"
    else
        _diag_emit FAIL tunnel_process_dead "cloudflared process not running inside container — tunnel not passing traffic"
    fi

    # Log scan for reconnects/errors
    local log_errors
    log_errors=$(docker compose logs --no-log-prefix --tail=30 "$svc" 2>/dev/null \
        | grep -ic "failed\|error\|reconnect\|connection reset" || true)
    if (( log_errors > 3 )); then
        _diag_emit WARN tunnel_log_errors "${log_errors} error/reconnect events in last 30 log lines — network instability"
    else
        _diag_emit OK tunnel_logs "Tunnel logs clean (${log_errors} errors in last 30 lines)"
    fi

    # Reuse healing network check for tunnel systemd status
    local healing_network="${IGOR_DIR}/modules/nextcloud_docker/checks/network.sh"
    if [ -f "$healing_network" ]; then
        _diag_collect_check 3 "$healing_network"
    fi
}

# ── Role: cron ─────────────────────────────────────────────────────────────────
_diag_check_role_cron() {
    local svc="$1" deep="$2"

    # Container running (healing already checks this)

    # Last execution in logs — checked first so we can use it as a cron-alive fallback
    local last_run
    last_run=$(docker compose logs --no-log-prefix --tail=100 "$svc" 2>/dev/null \
        | grep -iE "php occ cron|cron\.php|nextcloud cron" | tail -1)

    # Cron process alive — check multiple names:
    # cron (Debian), crond (Alpine), supercronic (lightweight), php (entrypoint loop pattern)
    local cron_pid
    cron_pid=$(docker compose exec -T "$svc" \
        sh -c 'pgrep -x cron 2>/dev/null || pgrep -x crond 2>/dev/null || pgrep supercronic 2>/dev/null || pgrep -f "cron.php" 2>/dev/null || pgrep -f "php.*occ" 2>/dev/null' \
        2>/dev/null | head -1 | tr -d '[:space:]')

    if [ -n "$cron_pid" ]; then
        _diag_emit OK cron_process "Cron process running inside container (PID ${cron_pid})"
    elif [ -n "$last_run" ]; then
        # No persistent daemon found but logs confirm recent job execution (entrypoint loop pattern)
        _diag_emit OK cron_process "Cron active — recent execution in logs (scheduled entrypoint pattern, no persistent daemon)"
    else
        _diag_emit WARN cron_process_dead "No cron daemon detected (checked: cron, crond, supercronic, cron.php) — background jobs may not be executing"
    fi

    if [ -n "$last_run" ]; then
        _diag_emit OK cron_last_run "Cron last execution visible in container logs"
    else
        _diag_emit WARN cron_no_log "No recent cron execution found in last 100 log lines"
    fi
}

# ── Phase 4 — Cross-Container ──────────────────────────────────────────────────
_diag_phase_4() {
    local deep="${1:-false}"
    _DIAG[current_phase]=4
    step "Phase 4: Cross-Container"
    _diag_log "phase 4: start"

    local app_svc="${_DIAG_ROLES[app]:-}"
    local web_svc="${_DIAG_ROLES[web]:-}"
    local db_svc="${_DIAG_ROLES[db]:-}"
    local cache_svc="${_DIAG_ROLES[cache]:-}"

    # ── app → db connectivity ─────────────────────────────────────────────────
    # IMPORTANT: tests run from INSIDE the source container — Docker DNS resolves
    # service names only within the compose network, not from the host.
    if [ -n "$app_svc" ] && [ -n "$db_svc" ]; then
        local db_host="${db_svc}"
        local db_port=$(igor_get_port "postgres" "5432")
        local reach
        # Try nc first (available in Alpine and Debian), then python3 fallback
        reach=$(docker compose exec -T "$app_svc" \
            sh -c "nc -zw3 ${db_host} ${db_port} 2>/dev/null && echo ok || echo fail" \
            2>/dev/null | tr -d '[:space:]' | grep -E '^ok$|^fail$' | head -1)
        if [ -z "$reach" ]; then
            reach=$(docker compose exec -T "$app_svc" \
                python3 -c "import socket; socket.create_connection(('${db_host}',${db_port}),5); print('ok')" \
                2>/dev/null | tr -d '[:space:]' | grep -E '^ok$' | head -1)
            [ -z "$reach" ] && reach="fail"
        fi
        case "$reach" in
            ok)   _diag_emit OK cross_app_db "app → db TCP reachability OK (${db_host}:${db_port})" ;;
            fail) _diag_emit FAIL cross_app_db "app cannot reach db on ${db_host}:${db_port} — network misconfiguration or db not listening" ;;
            *)    _diag_emit WARN cross_app_db "app → db connectivity check inconclusive (nc/python3 not available in container)" ;;
        esac
    fi

    # ── app → redis connectivity ───────────────────────────────────────────────
    if [ -n "$app_svc" ] && [ -n "$cache_svc" ]; then
        local redis_host="${cache_svc}"
        local redis_port=$(igor_get_port "redis" "6379")
        local reach
        reach=$(docker compose exec -T "$app_svc" \
            sh -c "nc -zw3 ${redis_host} ${redis_port} 2>/dev/null && echo ok || echo fail" \
            2>/dev/null | tr -d '[:space:]' | grep -E '^ok$|^fail$' | head -1)
        if [ -z "$reach" ]; then
            reach=$(docker compose exec -T "$app_svc" \
                python3 -c "import socket; socket.create_connection(('${redis_host}',${redis_port}),5); print('ok')" \
                2>/dev/null | tr -d '[:space:]' | grep -E '^ok$' | head -1)
            [ -z "$reach" ] && reach="fail"
        fi
        case "$reach" in
            ok)   _diag_emit OK cross_app_redis "app → redis TCP reachability OK (${redis_host}:${redis_port})" ;;
            fail) _diag_emit FAIL cross_app_redis "app cannot reach redis on ${redis_host}:${redis_port} — network misconfiguration" ;;
            *)    _diag_emit WARN cross_app_redis "app → redis connectivity check inconclusive" ;;
        esac
    fi

    # ── web → app FastCGI connectivity ────────────────────────────────────────
    if [ -n "$web_svc" ] && [ -n "$app_svc" ]; then
        local fpm_host="${app_svc}"
        local reach
        # nginx containers (Alpine) always have nc
        local fpm_port=$(igor_get_port "nextcloud_fpm" "9000")
        reach=$(docker compose exec -T "$web_svc" \
            sh -c "nc -zw3 ${fpm_host} ${fpm_port} 2>/dev/null && echo ok || echo fail" \
            2>/dev/null | tr -d '[:space:]' | grep -E '^ok$|^fail$' | head -1)
        [ -z "$reach" ] && reach="fail"
        case "$reach" in
            ok)   _diag_emit OK cross_web_app "web → app FastCGI reachability OK (${fpm_host}:${fpm_port})" ;;
            fail) _diag_emit FAIL cross_web_app "web cannot reach app on ${fpm_host}:${fpm_port} — nginx cannot forward PHP requests" ;;
        esac
    fi

    # ── Env var consistency: DB_HOST in app ───────────────────────────────────
    if [ -n "$app_svc" ] && [ -n "$db_svc" ]; then
        local db_host_env
        db_host_env=$(docker compose exec -T "$app_svc" sh -c 'echo $POSTGRES_HOST' 2>/dev/null | tr -d '[:space:]')
        if [ -z "$db_host_env" ]; then
            db_host_env=$(docker compose exec -T "$app_svc" sh -c 'echo $NEXTCLOUD_DB_HOST' 2>/dev/null | tr -d '[:space:]')
        fi
        if [ -n "$db_host_env" ] && [ "$db_host_env" != "$db_svc" ]; then
            _diag_emit WARN cross_db_host_mismatch "app DB_HOST env='${db_host_env}' does not match detected db service name '${db_svc}'"
        fi
    fi

    # ── Startup order ─────────────────────────────────────────────────────────
    if [ -n "$app_svc" ] && [ -n "$db_svc" ]; then
        local db_start app_start
        db_start=$(docker inspect --format '{{.State.StartedAt}}' \
            "$(docker compose ps -q "$db_svc" 2>/dev/null | head -1)" 2>/dev/null)
        app_start=$(docker inspect --format '{{.State.StartedAt}}' \
            "$(docker compose ps -q "$app_svc" 2>/dev/null | head -1)" 2>/dev/null)
        if [ -n "$db_start" ] && [ -n "$app_start" ] && [[ "$app_start" < "$db_start" ]]; then
            _diag_emit WARN cross_startup_order "App container started before DB (app=${app_start} db=${db_start}) — app may have initialised without DB"
        else
            _diag_emit OK cross_startup_order "Container startup order OK (DB started before app)"
        fi
    fi

    # ── Resource budget ────────────────────────────────────────────────────────
    local total_ram
    total_ram=$(free -m 2>/dev/null | awk 'NR==2{print $2}' || echo "1024")
    local sum_limits=0
    local svc_list
    svc_list=$(docker compose config --services 2>/dev/null)
    local svc
    while IFS= read -r svc; do
        [ -z "$svc" ] && continue
        local cid limit
        cid=$(docker compose ps -q "$svc" 2>/dev/null | head -1)
        [ -z "$cid" ] && continue
        limit=$(docker inspect --format '{{.HostConfig.Memory}}' "$cid" 2>/dev/null || true)
        if (( limit > 0 )); then
            sum_limits=$(( sum_limits + limit / 1048576 ))
        fi
    done <<< "$svc_list"

    if (( sum_limits > 0 && total_ram > 0 )); then
        local budget_pct=$(( sum_limits * 100 / total_ram ))
        if (( budget_pct > 80 )); then
            _diag_emit WARN cross_resource_budget "Container memory limits sum to ${sum_limits}MB (${budget_pct}% of ${total_ram}MB RAM) — OOM killer likely"
        else
            _diag_emit OK cross_resource_budget "Container memory budget ${sum_limits}MB / ${total_ram}MB (${budget_pct}%)"
        fi
    fi

    # ── Container clock drift ─────────────────────────────────────────────────
    local host_ts
    host_ts=$(date +%s)
    local drifted_svcs=""
    while IFS= read -r svc; do
        [ -z "$svc" ] && continue
        # Only check running containers
        local running
        running=$(docker compose ps --status running --services 2>/dev/null | grep -c "^${svc}$" || true)
        (( running == 0 )) && continue
        local ctr_ts
        ctr_ts=$(docker compose exec -T "$svc" date +%s 2>/dev/null | tr -d '[:space:]')
        [ -z "$ctr_ts" ] && continue
        local drift=$(( ctr_ts - host_ts ))
        # Absolute drift
        [ $drift -lt 0 ] && drift=$(( -drift ))
        if (( drift > 60 )); then
            drifted_svcs="${drifted_svcs}${svc}(${drift}s) "
        fi
    done < <(docker compose config --services 2>/dev/null)
    if [ -n "$drifted_svcs" ]; then
        _diag_emit WARN container_time_drift "Container clock drift > 60s detected: ${drifted_svcs}— may cause SSL/cookie/session failures"
    else
        _diag_emit OK container_time_drift "Container clocks within 60s of host"
    fi

    # ── Docker DNS resolution — can app resolve db by service name? ───────────
    if [ -n "$app_svc" ] && [ -n "$db_svc" ]; then
        local dns_result
        dns_result=$(docker compose exec -T "$app_svc" \
            sh -c "getent hosts ${db_svc} 2>/dev/null || nslookup ${db_svc} 2>/dev/null | grep -i 'address'" \
            2>/dev/null | head -1 | tr -d '[:space:]')
        if [ -n "$dns_result" ]; then
            _diag_emit OK docker_dns_resolution "app can resolve '${db_svc}' via Docker DNS"
        else
            _diag_emit FAIL docker_dns_resolution "app cannot resolve '${db_svc}' via Docker DNS — containers may be on different networks or DNS is broken"
        fi
    fi

    # ── Internal port exposure check ──────────────────────────────────────────
    # postgres, redis, php-fpm bound to 0.0.0.0 is dangerous
    # http to 0.0.0.0 is expected (nginx)
    local exposed_internal
    local postgres_port=$(igor_get_port "postgres" "5432")
    local redis_port=$(igor_get_port "redis" "6379")
    local fpm_port=$(igor_get_port "nextcloud_fpm" "9000")
    exposed_internal=$(docker compose config 2>/dev/null | python3 -c "
import sys
try:
    import yaml
except ImportError:
    print('')
    sys.exit(0)
import yaml
DANGEROUS_PORTS = {${postgres_port}, ${redis_port}, ${fpm_port}}
try:
    data = yaml.safe_load(sys.stdin)
    services = data.get('services', {})
    bad = []
    for name, cfg in services.items():
        for port in (cfg.get('ports') or []):
            ps = str(port)
            # format: '0.0.0.0:PORT:PORT' or 'PORT:PORT'
            parts = ps.split(':')
            if len(parts) >= 2:
                host_ip = parts[0] if len(parts) == 3 else ''
                host_port = int(parts[-2]) if parts[-2].isdigit() else 0
                ctr_port_s = parts[-1].split('/')[0]
                ctr_port = int(ctr_port_s) if ctr_port_s.isdigit() else 0
                if ctr_port in DANGEROUS_PORTS and (host_ip == '0.0.0.0' or host_ip == ''):
                    bad.append(f'{name}:{ctr_port}')
    print(','.join(bad))
except Exception as e:
    print('')
" 2>/dev/null || echo "")
    if [ -n "$exposed_internal" ]; then
        _diag_emit FAIL internal_port_exposure "Internal service ports bound to 0.0.0.0 (externally accessible!): ${exposed_internal} — should only bind to 127.0.0.1 or not be published"
    else
        _diag_emit OK internal_port_exposure "No internal ports (5432/6379/9000) exposed to 0.0.0.0"
    fi

    _diag_log "phase 4: complete"
}

# ── Phase 5 — moved to nextcloud_docker module ──────────────────────────────
# _diag_phase_5() was removed from core. The nextcloud_docker module defines
# _nc_diag_phase_5() and nextcloud_docker__app_diagnose() calls it directly.
# Core dispatches phase 5 via: igor_get_hooks "app_diagnose" (in diagnose/core.sh)
