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
