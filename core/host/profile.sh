#!/bin/bash
# ==============================================================================
#  IGOR — core/host/profile.sh
#  Hardware-tier resource profiling.
#
#  Detects RAM, CPU, architecture, storage type, and virtualisation status.
#  Maps the system to one of four resource tiers:
#    constrained  — < 1 GB RAM  (Pi 3, low-end VPS)
#    standard     — 1–8 GB RAM  (Pi 4/5, most homelab boxes)
#    comfortable  — 8–32 GB RAM (desktop NUC, older workstations)
#    server       — > 32 GB RAM (dedicated servers)
#
#  IGOR_DIR must be set before sourcing this file.
#
#  Public API:
#    igor_detect_profile  — detect hardware, write runtime/system_profile.json,
#                           set IGOR_TIER
#    igor_load_profile    — load from cache (auto-detect if missing or RAM changed)
#    igor_profile_show    — print human-readable profile summary
#    menu_profile         — interactive menu (show + offer re-detect)
# ==============================================================================

# Profile cache shares Igor's configured private runtime directory. Startup
# still detects the tier when the runtime has not yet been prepared by AI.
if declare -f _igor_resolve_dir >/dev/null 2>&1; then
    _PROFILE_FILE="$(_igor_resolve_dir runtime)/system_profile.json"
else
    _PROFILE_FILE="${IGOR_RUNTIME_DIR:-${IGOR_DIR}/data/runtime}/system_profile.json"
fi

_profile_runtime_ready() {
    local runtime="${_PROFILE_FILE%/*}" component probe="" mode
    local -a components
    [[ "$runtime" == /* && "$runtime" != / ]] || return 1
    IFS='/' read -r -a components <<< "${runtime#/}"
    for component in "${components[@]}"; do
        [ -n "$component" ] || continue
        [ "$component" != . ] && [ "$component" != .. ] || return 1
        probe+="/$component"
        [ ! -L "$probe" ] || return 1
    done
    [ -d "$runtime" ] && [ -O "$runtime" ] || return 1
    mode=$(stat -c %a -- "$runtime" 2>/dev/null || stat -f %Lp "$runtime" 2>/dev/null) || return 1
    [ "$mode" = 700 ]
}

_profile_cache_file_ok() {
    local mode
    _profile_runtime_ready && [ -f "$_PROFILE_FILE" ] &&
        [ ! -L "$_PROFILE_FILE" ] && [ -O "$_PROFILE_FILE" ] || return 1
    mode=$(stat -c %a -- "$_PROFILE_FILE" 2>/dev/null || stat -f %Lp "$_PROFILE_FILE" 2>/dev/null) || return 1
    [ "$mode" = 600 ]
}

# Global tier — set by igor_load_profile / igor_detect_profile.
# Readable by all modules and the tuning engine.
export IGOR_TIER=""

# ---------------------------------------------------------------------------
# _profile_read_ram_mb
#   Read current MemTotal from /proc/meminfo.  Echoes an integer MB value.
# ---------------------------------------------------------------------------
_profile_read_ram_mb() {
    local _kib
    _kib=$(grep '^MemTotal:' /proc/meminfo 2>/dev/null | awk '{print $2}')
    [ -n "$_kib" ] || { echo 0; return 1; }
    echo $(( _kib / 1024 ))
}

# ---------------------------------------------------------------------------
# _profile_detect_tier <ram_mb>
#   Echo the tier name for the given RAM amount.
# ---------------------------------------------------------------------------
_profile_detect_tier() {
    local _ram="$1"
    if   [ "$_ram" -lt 1024 ];  then echo "constrained"
    elif [ "$_ram" -lt 8192 ];  then echo "standard"
    elif [ "$_ram" -lt 32768 ]; then echo "comfortable"
    else                              echo "server"
    fi
}

# ---------------------------------------------------------------------------
# _profile_detect_storage
#   Echo one of: sdcard | nvme | ssd | hdd | unknown
# ---------------------------------------------------------------------------
_profile_detect_storage() {
    # SD card — mmcblk block device present
    if [ -b /dev/mmcblk0 ] || [ -d /sys/block/mmcblk0 ]; then
        echo "sdcard"; return
    fi
    # NVMe
    for _d in /sys/block/nvme*; do
        [ -d "$_d" ] && { echo "nvme"; return; }
    done
    # SSD vs HDD via rotational flag
    for _d in /sys/block/sd*; do
        [ -d "$_d" ] || continue
        local _rot
        _rot=$(cat "${_d}/queue/rotational" 2>/dev/null || echo "")
        if [ "$_rot" = "0" ]; then echo "ssd"; return; fi
        if [ "$_rot" = "1" ]; then echo "hdd"; return; fi
    done
    echo "unknown"
}

# ---------------------------------------------------------------------------
# igor_detect_profile
#
#   Run full hardware detection, write runtime/system_profile.json, and set
#   IGOR_TIER.  Safe to call multiple times (overwrites the cache each time).
# ---------------------------------------------------------------------------
igor_detect_profile() {
    local _ram_mb _cpu_cores _arch _storage _tier
    local _is_container="false" _is_vm="false"

    # RAM
    _ram_mb=$(_profile_read_ram_mb 2>/dev/null || echo 0)
    [ "$_ram_mb" -gt 0 ] || _ram_mb=1024   # safe default if /proc unavailable

    # CPU cores
    _cpu_cores=$(nproc 2>/dev/null \
        || grep -c '^processor' /proc/cpuinfo 2>/dev/null \
        || echo 1)

    # Architecture
    _arch=$(uname -m 2>/dev/null || echo "unknown")

    # Storage type
    _storage=$(_profile_detect_storage 2>/dev/null || echo "unknown")

    # Container detection
    if [ -f /.dockerenv ] \
        || grep -qa 'docker\|lxc\|kubepods' /proc/1/cgroup 2>/dev/null; then
        _is_container="true"
    fi

    # VM detection — systemd-detect-virt preferred; fallback to cpuinfo flag
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        local _virt
        _virt=$(systemd-detect-virt 2>/dev/null || echo "none")
        case "$_virt" in
            none|container-other) ;;
            *) _is_vm="true" ;;
        esac
    elif grep -qi 'hypervisor' /proc/cpuinfo 2>/dev/null; then
        _is_vm="true"
    fi

    # Tier
    _tier=$(_profile_detect_tier "$_ram_mb")

    # Timestamp (ISO 8601 UTC)
    local _ts
    _ts=$(date -u +%Y-%m-%dT%H:%M:%S+00:00 2>/dev/null || echo "unknown")

    # AI owns runtime preparation. Cache only in an already private directory;
    # tier detection itself never needs privilege or persistent storage.
    local _profile_tmp=""
    if _profile_runtime_ready && { [ ! -e "$_PROFILE_FILE" ] || _profile_cache_file_ok; }; then
        _profile_tmp=$(mktemp "${_PROFILE_FILE}.XXXXXX") || _profile_tmp=""
    fi
    if [ -n "$_profile_tmp" ]; then
        cat > "$_profile_tmp" << PROFILE_EOF
{
    "tier": "${_tier}",
    "ram_mb": ${_ram_mb},
    "cpu_cores": ${_cpu_cores},
    "arch": "${_arch}",
    "storage_type": "${_storage}",
    "is_container": ${_is_container},
    "is_vm": ${_is_vm},
    "detected_at": "${_ts}"
}
PROFILE_EOF
        chmod 600 -- "$_profile_tmp" && mv -f -- "$_profile_tmp" "$_PROFILE_FILE" ||
            rm -f -- "$_profile_tmp"
    fi

    IGOR_TIER="$_tier"
    export IGOR_TIER
}

# ---------------------------------------------------------------------------
# igor_load_profile
#
#   Read runtime/system_profile.json and set IGOR_TIER.
#   Automatically runs igor_detect_profile when:
#     • the cache file doesn't exist, or
#     • the cached ram_mb differs from current MemTotal by more than 128 MB
#       (indicates a hardware change — upgrade, hot-swap, VM resize)
# ---------------------------------------------------------------------------
igor_load_profile() {
    local _run_detect=false

    if ! _profile_cache_file_ok; then
        _run_detect=true
    else
        local _cached_ram _current_ram _delta
        _cached_ram=$(grep '"ram_mb"' "$_PROFILE_FILE" 2>/dev/null \
            | grep -oE '[0-9]+' | head -1)
        _cached_ram="${_cached_ram:-0}"
        _current_ram=$(_profile_read_ram_mb 2>/dev/null || echo 0)
        _delta=$(( _current_ram - _cached_ram ))
        # Absolute value comparison without external tools
        [ "${_delta#-}" -gt 128 ] && _run_detect=true
    fi

    if $_run_detect; then
        igor_detect_profile
        return
    fi

    # Load tier from cached JSON (simple grep — no python required)
    local _cached_tier
    _cached_tier=$(grep '"tier"' "$_PROFILE_FILE" 2>/dev/null \
        | sed 's/.*"tier"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    if [ -n "$_cached_tier" ]; then
        IGOR_TIER="$_cached_tier"
        export IGOR_TIER
    fi
}

# ---------------------------------------------------------------------------
# igor_profile_show
#
#   Print a formatted summary of the cached system profile.
# ---------------------------------------------------------------------------
igor_profile_show() {
    if [ ! -f "$_PROFILE_FILE" ]; then
        warn "No profile found. Run 'igor profile' to detect."
        return 1
    fi

    local _tier _ram _cores _arch _storage _is_container _is_vm _ts
    _tier=$(grep '"tier"' "$_PROFILE_FILE" \
        | sed 's/.*"tier"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    _ram=$(grep '"ram_mb"' "$_PROFILE_FILE" \
        | grep -oE '[0-9]+' | head -1)
    _cores=$(grep '"cpu_cores"' "$_PROFILE_FILE" \
        | grep -oE '[0-9]+' | head -1)
    _arch=$(grep '"arch"' "$_PROFILE_FILE" \
        | sed 's/.*"arch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    _storage=$(grep '"storage_type"' "$_PROFILE_FILE" \
        | sed 's/.*"storage_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    _is_container=$(grep '"is_container"' "$_PROFILE_FILE" \
        | grep -oE 'true|false' | head -1)
    _is_vm=$(grep '"is_vm"' "$_PROFILE_FILE" \
        | grep -oE 'true|false' | head -1)
    _ts=$(grep '"detected_at"' "$_PROFILE_FILE" \
        | sed 's/.*"detected_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    # Colour-code the tier
    local _tier_color
    case "${_tier:-}" in
        constrained) _tier_color="${RED}"  ;;
        standard)    _tier_color="${YEL}"  ;;
        comfortable) _tier_color="${GRN}"  ;;
        server)      _tier_color="${MAG}"  ;;
        *)           _tier_color="${DIM}"  ;;
    esac

    echo ""
    echo -e "  ${BOLD}System Profile${NC}"
    echo ""
    printf "  %-16s: %b%s%b\n" "Tier"        "$_tier_color" "${_tier:-unknown}"        "$NC"
    printf "  %-16s: %s MB\n"  "RAM"          "${_ram:-?}"
    printf "  %-16s: %s\n"     "CPU cores"    "${_cores:-?}"
    printf "  %-16s: %s\n"     "Architecture" "${_arch:-?}"
    printf "  %-16s: %s\n"     "Storage"      "${_storage:-?}"
    printf "  %-16s: %s\n"     "Container"    "${_is_container:-?}"
    printf "  %-16s: %s\n"     "VM"           "${_is_vm:-?}"
    printf "  %-16s: %s\n"     "Detected at"  "${_ts:-?}"
    echo ""
}

# ---------------------------------------------------------------------------
# menu_profile
#
#   Interactive profile menu — display current profile, offer re-detection.
# ---------------------------------------------------------------------------
menu_profile() {
    while true; do
        header
        breadcrumb "Igor" "System Profile"
        igor_profile_show

        local _opt
        _opt=$(igor_fzf_pick "System Profile" \
            "r:RE-DETECT:Re-scan hardware and update profile" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        echo -e "  ${CYAN}r.${NC} Re-detect  (re-scan hardware now)"
        echo -e "  ${CYAN}b.${NC} Back"
        echo ""
        read -rp "  Select: " _opt ;; esac
        case "$_opt" in
            r|R)
                step "Detecting hardware profile..."
                igor_detect_profile
                ok "Profile updated — tier: ${IGOR_TIER}"
                pause
                ;;
            b|B|q|Q) return ;;
        esac
    done
}
