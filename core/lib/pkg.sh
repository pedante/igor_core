#!/bin/bash
# ==============================================================================
#  IGOR — core/lib/pkg.sh
#
#  Package manager abstraction.  Source after distro.sh so IGOR_DISTRO_FAMILY
#  is already set.
#
#  Public API:
#    pkg_install <logical-or-real-name> [...]
#        Install one or more packages using the distro's package manager.
#        Names starting with "pkg_" are resolved through the name map below.
#        Bare names are passed to the package manager unchanged.
#
#    pkg_svc_name <logical-service-name>
#        Echo the real systemd unit name for a logical service.
#        Returns 0.
#
#  Logical package names  (callers use these; the map resolves to real names):
#    pkg_docker           docker engine
#    pkg_docker_compose   docker compose plugin
#    pkg_python           Python 3 interpreter
#    pkg_pip              pip for Python 3
#    pkg_cron             cron daemon
#    pkg_ncurses          ncurses CLI utilities
#    pkg_rich             python rich library (for AI panels)
#
#  Logical service names:
#    svc_cron             host cron daemon service name
# ==============================================================================

# ── Package name map ───────────────────────────────────────────────────────────
# Format:  _PKG_MAP[<logical>]="<debian-name>|<arch-name>"
declare -A _PKG_MAP=(
    [pkg_docker]="docker.io|docker"
    [pkg_docker_compose]="docker-compose-plugin|docker-compose"
    [pkg_python]="python3|python"
    [pkg_pip]="python3-pip|python-pip"
    [pkg_cron]="cron|cronie"
    [pkg_ncurses]="ncurses-bin|ncurses"
    [pkg_rich]="python3-rich|python-rich"
)

# ── Service name map ───────────────────────────────────────────────────────────
declare -A _SVC_MAP=(
    [svc_cron]="cron|cronie"
)

# ── _pkg_resolve <logical-name> ───────────────────────────────────────────────
# Echo the real package name for the current distro family.
_pkg_resolve() {
    local _logical="$1"
    local _entry="${_PKG_MAP[$_logical]:-}"

    if [ -z "$_entry" ]; then
        # Not a logical name — pass through unchanged
        echo "$_logical"
        return
    fi

    local _deb_name _arch_name
    IFS='|' read -r _deb_name _arch_name <<< "$_entry"

    case "${IGOR_DISTRO_FAMILY:-debian}" in
        arch)   echo "$_arch_name" ;;
        *)      echo "$_deb_name"  ;;
    esac
}

# ── pkg_svc_name <logical-service> ────────────────────────────────────────────
# Echo the real systemd unit name for a logical service identifier.
pkg_svc_name() {
    local _logical="$1"
    local _entry="${_SVC_MAP[$_logical]:-}"

    if [ -z "$_entry" ]; then
        echo "$_logical"
        return
    fi

    local _deb_name _arch_name
    IFS='|' read -r _deb_name _arch_name <<< "$_entry"

    case "${IGOR_DISTRO_FAMILY:-debian}" in
        arch)   echo "$_arch_name" ;;
        *)      echo "$_deb_name"  ;;
    esac
}

# ── pkg_install <name> [...] ───────────────────────────────────────────────────
# Install one or more packages using the distro-appropriate package manager.
pkg_install() {
    if [ $# -eq 0 ]; then return 0; fi

    # Resolve all logical names to real names
    local -a _real_pkgs=()
    for _arg in "$@"; do
        _real_pkgs+=( "$(_pkg_resolve "$_arg")" )
    done

    # Privilege escalation
    local _sudo=""
    [ "$(id -u)" != "0" ] && _sudo="sudo"

    case "${IGOR_DISTRO_FAMILY:-debian}" in
        arch)
            ${_sudo} pacman -S --noconfirm "${_real_pkgs[@]}"
            ;;
        debian)
            ${_sudo} apt-get install -y "${_real_pkgs[@]}"
            ;;
        rhel)
            ${_sudo} dnf install -y "${_real_pkgs[@]}" 2>/dev/null \
                || ${_sudo} yum install -y "${_real_pkgs[@]}"
            ;;
        opensuse)
            ${_sudo} zypper install -n "${_real_pkgs[@]}"
            ;;
        alpine)
            ${_sudo} apk add "${_real_pkgs[@]}"
            ;;
        *)
            warn "pkg_install: unsupported distro family '${IGOR_DISTRO_FAMILY:-unknown}'"
            warn "  Cannot install: ${_real_pkgs[*]}"
            warn "  Install manually and re-run."
            return 1
            ;;
    esac
}

# Wave D platform primitives
#
# These helpers deliberately return mechanisms or an argv specification.  The
# latter is data until an already-authorized capability executes it.  They do
# not add a second privilege path and fail closed for unsupported families.
_pkg_validate_name() {
    local _name="${1:-}"
    [[ "$_name" =~ ^[A-Za-z0-9][A-Za-z0-9+_.:@-]*$ ]]
}

_pkg_wave_d_family() {
    case "${IGOR_DISTRO_FAMILY:-unknown}" in
        debian|arch) return 0 ;;
        *) return 1 ;;
    esac
}

_pkg_query_timeout() {
    local _seconds="${IGOR_PLATFORM_QUERY_TIMEOUT_SECONDS:-5}"
    [[ "$_seconds" =~ ^[1-9][0-9]?$ ]] || return 2
    printf '%s\n' "$_seconds"
}

_pkg_wave_d_names() {
    local _arg
    [ "$#" -gt 0 ] || return 2
    _pkg_wave_d_family || return 1
    for _arg in "$@"; do
        _pkg_validate_name "$_arg" || return 2
        _pkg_resolve "$_arg"
    done
}

# pkg_query <package>
# Return 0 when installed, 1 when absent, and 2 for invalid/unsupported or
# package-manager errors.  Query output is intentionally left to the caller.
pkg_query() {
    local _name="${1:-}" _real _timeout
    [ "$#" -eq 1 ] && _pkg_validate_name "$_name" || return 2
    _pkg_wave_d_family || return 2
    command -v timeout >/dev/null 2>&1 || return 2
    _timeout="$(_pkg_query_timeout)" || return 2
    _real="$(_pkg_resolve "$_name")"
    case "$IGOR_DISTRO_FAMILY" in
        debian)
            local _status
            _status="$(timeout "$_timeout" dpkg-query -W -f='${Status}' -- "$_real" 2>/dev/null)"
            local _query_rc=$?
            # dpkg-query uses exit 1 for a package that is not installed.
            [ "$_query_rc" -eq 1 ] && return 1
            [ "$_query_rc" -ne 0 ] && return 2
            [ "$_status" = 'install ok installed' ] && return 0
            return 1
            ;;
        arch) timeout "$_timeout" pacman -Q -- "$_real" >/dev/null 2>&1 || {
                local _rc=$?
                [ "$_rc" -eq 1 ] && return 1
                return 2
            } ;;
    esac
    local _rc=$?
    [ "$_rc" -eq 0 ] && return 0
    [ "$_rc" -eq 1 ] && return 1
    return 2
}

pkg_install_argv() {
    [ "$#" -gt 0 ] || return 2
    local _arg
    for _arg in "$@"; do _pkg_validate_name "$_arg" || return 2; done
    local -a _names=()
    for _arg in "$@"; do
        _names+=( "$(_pkg_resolve "$_arg")" )
    done
    case "$IGOR_DISTRO_FAMILY" in
        debian) printf 'apt-get install -y';;
        arch) printf 'pacman -S --noconfirm';;
        *) return 2;;
    esac
    printf ' %s' "${_names[@]}"
    printf '\n'
}

pkg_remove_argv() {
    [ "$#" -gt 0 ] || return 2
    local _arg
    for _arg in "$@"; do _pkg_validate_name "$_arg" || return 2; done
    local -a _names=()
    for _arg in "$@"; do
        _names+=( "$(_pkg_resolve "$_arg")" )
    done
    case "$IGOR_DISTRO_FAMILY" in
        debian) printf 'apt-get remove -y';;
        arch) printf 'pacman -R --noconfirm';;
        *) return 2;;
    esac
    printf ' %s' "${_names[@]}"
    printf '\n'
}

pkg_update_argv() {
    [ "$#" -eq 0 ] || return 2
    case "${IGOR_DISTRO_FAMILY:-unknown}" in
        debian) printf '%s\n' 'apt-get update' ;;
        arch) printf '%s\n' 'pacman -Syu --noconfirm' ;;
        *) return 2 ;;
    esac
}

pkg_upgrade_argv() {
    [ "$#" -eq 0 ] || return 2
    case "${IGOR_DISTRO_FAMILY:-unknown}" in
        debian) printf '%s\n' 'apt-get upgrade -y' ;;
        arch) printf '%s\n' 'pacman -Syu --noconfirm' ;;
        *) return 2 ;;
    esac
}

_svc_validate_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.@:+-]*$ ]]
}

svc_query() {
    [ "$#" -eq 1 ] && _svc_validate_name "$1" || return 2
    _pkg_wave_d_family || return 2
    command -v systemctl >/dev/null 2>&1 || return 2
    command -v timeout >/dev/null 2>&1 || return 2
    local _state _rc _timeout
    _timeout="$(_pkg_query_timeout)" || return 2
    _state="$(timeout "$_timeout" \
        systemctl is-active -- "$1" 2>/dev/null)"
    _rc=$?
    [ "$_rc" -eq 124 ] && return 2
    # systemctl returns 3 for an inactive/failed unit, which is still a
    # deterministic state.  Exit 4 means the unit is not known.
    case "$_rc" in
        0|3) printf '%s\n' "${_state:-unknown}"; return 0 ;;
        4) printf '%s\n' "${_state:-unknown}"; return 1 ;;
        *) return 2 ;;
    esac
}

_svc_argv() {
    local _op="${1:-}" _unit="${2:-}"
    [[ "$_op" =~ ^(start|stop|restart|enable|disable)$ ]] || return 2
    [ "$#" -eq 2 ] && _svc_validate_name "$_unit" || return 2
    _pkg_wave_d_family || return 2
    command -v systemctl >/dev/null 2>&1 || return 2
    printf 'systemctl %s %s\n' "$_op" "$_unit"
}

svc_start_argv() { _svc_argv start "$@"; }
svc_stop_argv() { _svc_argv stop "$@"; }
svc_restart_argv() { _svc_argv restart "$@"; }
svc_enable_argv() { _svc_argv enable "$@"; }
svc_disable_argv() { _svc_argv disable "$@"; }

# Read-only administration queries shared by the System module. These expose
# mechanisms, not policy: callers decide how to present or interpret results.
pkg_updates_list() {
    [ "$#" -eq 0 ] || return 2
    _pkg_wave_d_family || return 2
    command -v timeout >/dev/null 2>&1 || return 2
    local _timeout _output _rc
    _timeout="$(_pkg_query_timeout)" || return 2
    case "$IGOR_DISTRO_FAMILY" in
        debian)
            command -v apt-get >/dev/null 2>&1 || return 2
            _output="$(timeout "$_timeout" apt-get -s upgrade 2>/dev/null)" || return 2
            printf '%s\n' "$_output" | awk '/^Inst[[:space:]]+/ { print $2 }' | sort -u
            ;;
        arch)
            command -v pacman >/dev/null 2>&1 || return 2
            _output="$(timeout "$_timeout" pacman -Qu 2>/dev/null)"
            _rc=$?
            [ "$_rc" -eq 0 ] || [ "$_rc" -eq 1 ] || return 2
            printf '%s\n' "$_output" | awk 'NF { print $1 }' | sort -u
            ;;
    esac
}

pkg_cleanup_candidates() {
    [ "$#" -eq 0 ] || return 2
    _pkg_wave_d_family || return 2
    command -v timeout >/dev/null 2>&1 || return 2
    local _timeout _output _rc
    _timeout="$(_pkg_query_timeout)" || return 2
    case "$IGOR_DISTRO_FAMILY" in
        debian)
            command -v apt-get >/dev/null 2>&1 || return 2
            _output="$(timeout "$_timeout" apt-get -s autoremove 2>/dev/null)" || return 2
            printf '%s\n' "$_output" | awk '/^Remv[[:space:]]+/ { print $2 }' | sort -u
            ;;
        arch)
            command -v pacman >/dev/null 2>&1 || return 2
            _output="$(timeout "$_timeout" pacman -Qdtq 2>/dev/null)"
            _rc=$?
            [ "$_rc" -eq 0 ] || [ "$_rc" -eq 1 ] || return 2
            printf '%s\n' "$_output" | awk 'NF { print $1 }' | sort -u
            ;;
    esac
}

pkg_cache_usage() {
    [ "$#" -eq 0 ] || return 2
    _pkg_wave_d_family || return 2
    local _path _kb
    case "$IGOR_DISTRO_FAMILY" in
        debian) _path=/var/cache/apt/archives ;;
        arch) _path=/var/cache/pacman/pkg ;;
    esac
    [ -d "$_path" ] || {
        printf '%s\t0\n' "$_path"
        return 0
    }
    _kb="$(du -sk -- "$_path" 2>/dev/null | awk 'NR==1 { print $1 }')" || return 2
    [[ "$_kb" =~ ^[0-9]+$ ]] || return 2
    printf '%s\t%s\n' "$_path" "$((_kb * 1024))"
}

svc_list_query() {
    [ "$#" -eq 0 ] || return 2
    _pkg_wave_d_family || return 2
    command -v systemctl >/dev/null 2>&1 || return 2
    command -v timeout >/dev/null 2>&1 || return 2
    local _timeout
    _timeout="$(_pkg_query_timeout)" || return 2
    timeout "$_timeout" systemctl list-units --type=service --all --plain --no-legend --no-pager 2>/dev/null |
        awk 'NF >= 4 { print $1 "\t" $3 "\t" $4 }'
}

# ── pkg_install_docker_post ───────────────────────────────────────────────────
# Post-install activation for Docker.  Safe to call on any distro — no-ops
# if Docker is already running.
#
# On Debian, apt starts the daemon automatically.
# On Arch (and others), the service must be explicitly enabled and started.
pkg_install_docker_post() {
    local _sudo=""
    [ "$(id -u)" != "0" ] && _sudo="sudo"

    step "Enabling and starting Docker service..."

    ${_sudo} systemctl enable docker 2>/dev/null || true
    ${_sudo} systemctl start  docker 2>/dev/null || true

    # Verify the daemon responds
    local _attempts=0
    while [ $_attempts -lt 10 ]; do
        docker info &>/dev/null && break
        _attempts=$(( _attempts + 1 ))
        sleep 1
    done

    if ! docker info &>/dev/null; then
        warn "Docker daemon did not respond after start."
        warn "  Try: sudo systemctl status docker"
        return 1
    fi
    ok "Docker daemon is running."

    # Add current user to docker group if not already a member
    if [ -n "${SUDO_USER:-}" ] && ! groups "$SUDO_USER" | grep -qw docker; then
        ${_sudo} usermod -aG docker "$SUDO_USER" 2>/dev/null && \
            info "  Added ${SUDO_USER} to the docker group — re-login required."
    elif [ "$(id -u)" != "0" ] && ! groups | grep -qw docker; then
        ${_sudo} usermod -aG docker "$USER" 2>/dev/null && \
            info "  Added ${USER} to the docker group — re-login required."
    fi
}
