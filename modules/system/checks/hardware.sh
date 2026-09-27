#!/bin/bash
# ==============================================================================
#  IGOR — modules/system/checks/hardware.sh
#  Host hardware health check: CPU temperature, undervoltage, disk, swap.
#
#  Discoverable by _healing_discover_checks() in core/healing/core.sh.
#  Architecture-agnostic: uses /proc, /sys, and optional vcgencmd (Pi).
# ==============================================================================

CHECK_NAME="hardware"
CHECK_DESCRIPTION="CPU temperature, undervoltage (Pi), root filesystem, swap"
CHECK_SCHEDULE="60"

# PATTERN_HINT cpu_overtemp "CPU temperature critical (≥85°C)" CHANGE "sudo systemctl stop docker && sleep 30 && sudo systemctl start docker"
# PATTERN_HINT low_ram "Available RAM critically low (<80MB)" CHANGE "docker system prune -f"
# PATTERN_HINT rootfs_full "Root filesystem critically full (≥90%)" CHANGE "docker system prune -af --volumes"

run_check() {
    # ── CPU temperature ───────────────────────────────────────────────────────
    local temp=""
    if command -v vcgencmd &>/dev/null; then
        temp=$(vcgencmd measure_temp 2>/dev/null | grep -o '[0-9]*\.[0-9]*')
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    fi

    if [ -n "$temp" ]; then
        local ti; ti=$(printf "%.0f" "$temp" 2>/dev/null || echo 0)
        if   [ "$ti" -ge 85 ]; then
            echo "CHECK_RESULT CRITICAL cpu_overtemp CPU temperature ${temp}°C — critical (≥85°C)"
        elif [ "$ti" -ge 75 ]; then
            echo "CHECK_RESULT WARN cpu_warm CPU temperature ${temp}°C — elevated (≥75°C)"
        else
            echo "CHECK_RESULT OK cpu_temp CPU temperature ${temp}°C"
        fi
    else
        echo "CHECK_RESULT OK cpu_temp CPU temperature sensor not available (non-Pi hardware)"
    fi

    # ── Undervoltage (Pi-specific, no-op on other hardware) ──────────────────
    if command -v vcgencmd &>/dev/null; then
        local throttle; throttle=$(vcgencmd get_throttled 2>/dev/null | grep -o '0x[0-9a-f]*')
        if [ -n "$throttle" ] && [ "$throttle" != "0x0" ]; then
            echo "CHECK_RESULT WARN undervoltage vcgencmd throttle flags: ${throttle} — check power supply"
        else
            echo "CHECK_RESULT OK undervoltage No undervoltage or throttling detected"
        fi
    fi

    # ── Root filesystem usage ─────────────────────────────────────────────────
    local root_pct
    root_pct=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    if [ -n "$root_pct" ]; then
        if   [ "$root_pct" -ge 90 ]; then
            echo "CHECK_RESULT CRITICAL rootfs_full Root filesystem ${root_pct}% full — critical"
        elif [ "$root_pct" -ge 75 ]; then
            echo "CHECK_RESULT WARN rootfs_high Root filesystem ${root_pct}% full"
        else
            echo "CHECK_RESULT OK rootfs Root filesystem ${root_pct}% used"
        fi
    fi

    # ── Swap usage ────────────────────────────────────────────────────────────
    local swap_pct
    swap_pct=$(free 2>/dev/null | awk '/^Swap:/{if($2>0) printf "%d", $3*100/$2; else print 0}')
    if [ -n "$swap_pct" ] && [ "$swap_pct" -gt 0 ]; then
        if   [ "$swap_pct" -ge 85 ]; then
            echo "CHECK_RESULT FAIL swap_critical Swap ${swap_pct}% used — critical"
        elif [ "$swap_pct" -ge 60 ]; then
            echo "CHECK_RESULT WARN swap_high Swap ${swap_pct}% used — elevated"
        else
            echo "CHECK_RESULT OK swap Swap ${swap_pct}% used"
        fi
    fi
}
