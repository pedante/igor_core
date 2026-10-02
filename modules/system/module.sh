#!/bin/bash
# =============================================================================
#  MODULE: system
#  Linux system management: services, storage, cron, and hardware monitoring.
#  Architecture-agnostic — uses /proc, /sys, and optional vcgencmd/lsblk.
# =============================================================================

# Module API v2 observer handler. The loader invokes this function in an
# isolated Bash process with one JSON request on stdin. Keep the response to
# one JSON document on stdout; diagnostics belong on stderr.
system__observe_memory() {
    local request available_kb
    IFS= read -r request || {
        printf '%s\n' '{"status":"error","error":{"code":"invalid_request","message":"request is required"}}'
        return 0
    }

    # The adapter validates the complete envelope. This check prevents
    # accidental execution when the handler is called directly with another
    # payload while keeping the Bash adapter independent of jq.
    case "$request" in
        *'"api_version":2'*'"contribution_id":"host.memory"'*) ;;
        *)
            printf '%s\n' '{"status":"error","error":{"code":"invalid_request","message":"expected host.memory v2 request"}}'
            return 0
            ;;
    esac

    available_kb=$(awk '/^MemAvailable:[[:space:]]+[0-9]+[[:space:]]+kB$/ { print $2; exit }' /proc/meminfo 2>/dev/null)
    if [[ ! "$available_kb" =~ ^[0-9]+$ ]]; then
        printf '%s\n' '{"status":"error","error":{"code":"unavailable","message":"MemAvailable is not available"}}'
        return 0
    fi

    printf '{"status":"ok","result":{"object_id":"host:local","facts":[{"property":"memory.available_bytes","value":%s,"evidence":["/proc/meminfo:MemAvailable"]}],"unavailable":[]}}\n' "$((available_kb * 1024))"
    return 0
}

# The capability handler names the declared observer. Igor validates this
# response and performs the refresh in the parent process, where the Wave D
# System Model lives. The handler cannot publish a fact or choose another
# observer by returning arbitrary data.
system__refresh_memory() {
    local request
    IFS= read -r request || return 1
    case "$request" in
        *'"api_version":2'*'"contribution_id":"system.host.memory.refresh"'*'"input":{}'*)
            printf '%s\n' '{"status":"ok","result":{"observer_id":"host.memory"}}'
            ;;
        *)
            printf '%s\n' '{"status":"error","error":{"code":"invalid_request","message":"expected memory refresh request"}}'
            ;;
    esac
}

# A v2 check receives only Igor's fact snapshot. It does not probe /proc or
# choose its own check identity, owner, time, approval or execution policy.
_mod_sys_memory_warning_request() {
    local action="$1" request package
    IFS= read -r request || return 1
    package="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || return 1
    "${IGOR_PYTHON:-python3}" "$package/lib/memory_warning.py" "$action" "$request"
}

system__check_memory() { _mod_sys_memory_warning_request check; }
system__apply_memory_warning() { _mod_sys_memory_warning_request apply; }
system__read_memory_warning() { _mod_sys_memory_warning_request readback; }

# REQUIRED — called at igor startup
system__register() {
    igor_register_hook "health"      "system__health"
    igor_register_hook "diagnose"    "system__diagnose"
    igor_register_hook "ai_context"  "system__ai_context"
    igor_register_hook "ai_tools"    "system__ai_tools"
    igor_register_hook "mailcmd"     "system__mailcmd_verbs"
    igor_register_hook "notify"      "system__notify_sources"
    igor_register_hook "recovery"    "system__recovery_hooks"
    return 0
}

# REQUIRED — called by health status bar
# Returns: "status:message"
system__health() {
    local temp issues=""

    # CPU temperature — try vcgencmd (Pi), fall back to /sys thermal zone
    if igor_has_bin vcgencmd; then
        temp=$(vcgencmd measure_temp 2>/dev/null | grep -o '[0-9]*\.[0-9]*')
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    fi
    if [ -n "$temp" ]; then
        local temp_int; temp_int=$(printf "%.0f" "$temp" 2>/dev/null || echo 0)
        [ "$temp_int" -ge 85 ] && issues+="CPU ${temp}°C CRITICAL; "
        [ "$temp_int" -ge 75 ] && [ "$temp_int" -lt 85 ] && issues+="CPU ${temp}°C; "
    fi

    # Undervoltage (Pi-specific, no-op on other hardware)
    if igor_has_bin vcgencmd; then
        local throttle; throttle=$(vcgencmd get_throttled 2>/dev/null | grep -o '0x[0-9a-f]*')
        case "$throttle" in
            0x5000[05]|0x[0-9a-f]*0005*) issues+="undervoltage; " ;;
        esac
    fi

    if [ -n "$issues" ]; then
        echo "warn:${issues%; }"
    else
        local msg="OK"
        [ -n "$temp" ] && msg="CPU ${temp}°C"
        echo "ok:${msg}"
    fi
    return 0
}

# OPTIONAL — called by IGOR DIAGNOSE aggregator
# Output one line per check: CHECK:<name>:<status>:<message>
system__diagnose() {
    # CPU temperature
    local temp=""
    if igor_has_bin vcgencmd; then
        temp=$(vcgencmd measure_temp 2>/dev/null | grep -o '[0-9]*\.[0-9]*')
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    fi
    if [ -n "$temp" ]; then
        local ti; ti=$(printf "%.0f" "$temp" 2>/dev/null || echo 0)
        if   [ "$ti" -ge 85 ]; then echo "CHECK:cpu_temp:fail:CPU temperature ${temp}°C — CRITICAL (≥85°C)"
        elif [ "$ti" -ge 75 ]; then echo "CHECK:cpu_temp:warn:CPU temperature ${temp}°C — elevated (≥75°C)"
        else                         echo "CHECK:cpu_temp:ok:CPU temperature ${temp}°C"
        fi
    else
        echo "CHECK:cpu_temp:skip:temperature sensor not available"
    fi

    # Undervoltage (Pi-specific)
    if igor_has_bin vcgencmd; then
        local throttle; throttle=$(vcgencmd get_throttled 2>/dev/null | grep -o '0x[0-9a-f]*')
        if [ -n "$throttle" ] && [ "$throttle" != "0x0" ]; then
            echo "CHECK:undervoltage:warn:vcgencmd reports throttle flags: ${throttle} — check power supply"
        else
            echo "CHECK:undervoltage:ok:no undervoltage or throttling detected"
        fi
    fi

    # Root filesystem usage
    local root_pct
    root_pct=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    if [ -n "$root_pct" ]; then
        if   [ "$root_pct" -ge 90 ]; then echo "CHECK:rootfs:fail:root filesystem ${root_pct}% full — CRITICAL"
        elif [ "$root_pct" -ge 75 ]; then echo "CHECK:rootfs:warn:root filesystem ${root_pct}% full"
        else                              echo "CHECK:rootfs:ok:root filesystem ${root_pct}% used"
        fi
    fi

    # Swap usage
    local swap_pct
    swap_pct=$(free 2>/dev/null | awk '/^Swap:/{if($2>0) printf "%d", $3*100/$2; else print 0}')
    if [ -n "$swap_pct" ] && [ "$swap_pct" -gt 0 ]; then
        if   [ "$swap_pct" -ge 85 ]; then echo "CHECK:swap:fail:swap ${swap_pct}% used — CRITICAL"
        elif [ "$swap_pct" -ge 60 ]; then echo "CHECK:swap:warn:swap ${swap_pct}% used — elevated"
        else                              echo "CHECK:swap:ok:swap ${swap_pct}% used"
        fi
    fi
}

# OPTIONAL — called by AI context builder
system__ai_context() {
    local ctx=""
    ctx+="\n=== SYSTEM ===\n"

    # Model identification — Pi-specific or generic
    if [ -f /proc/device-tree/model ]; then
        ctx+="Model: $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)\n"
    fi
    ctx+="OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')\n"
    ctx+="Kernel: $(uname -r 2>/dev/null)\n"
    ctx+="Arch: $(uname -m 2>/dev/null)\n"
    ctx+="Uptime: $(uptime -p 2>/dev/null || uptime 2>/dev/null)\n"
    ctx+="Tier: ${IGOR_TIER:-unknown}\n"

    # Temperature
    local temp=""
    if igor_has_bin vcgencmd; then
        temp=$(vcgencmd measure_temp 2>/dev/null | grep -o '[0-9]*\.[0-9]*')
        ctx+="CPU temp: ${temp}°C\n"
        local throttle; throttle=$(vcgencmd get_throttled 2>/dev/null)
        ctx+="Throttle flags: ${throttle:-unknown}\n"
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        ctx+="CPU temp: ${temp}°C\n"
    fi

    # Memory availability is supplied once by the Igor System Model context.
    ctx+="$(free -h 2>/dev/null | grep -E '^Swap:')\n"
    ctx+="Load: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)\n"

    # Recent I/O errors
    local io_errors
    io_errors=$(dmesg 2>/dev/null | grep -i "i/o error\|mmcblk.*error\|end_request" | tail -5)
    if [ -n "$io_errors" ]; then
        ctx+="\n=== RECENT I/O ERRORS ===\n${io_errors}\n"
    fi

    echo -e "$ctx"
    return 0
}

# OPTIONAL — called by AI tool registrar
system__ai_tools() {
    return 0
}

# OPTIONAL — mailcmd verbs handled by this module
system__mailcmd_verbs() {
    echo "sysstatus sysupdate sysreboot"
    return 0
}

# OPTIONAL — notification sources
system__notify_sources() {
    return 0
}

# OPTIONAL — recovery hooks
system__recovery_hooks() {
    return 0
}
