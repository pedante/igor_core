#!/bin/bash
# ==============================================================================
#  IGOR — core/lib/distro.sh
#
#  Distro detection — sets IGOR_DISTRO_ID and IGOR_DISTRO_FAMILY at startup.
#  Source this file early (before any package install or python invocation).
#
#  Public API:
#    igor_detect_distro   — read /etc/os-release and export the two globals
#
#  Exported globals:
#    IGOR_DISTRO_ID      raw $ID value from os-release  (arch, debian, ubuntu…)
#    IGOR_DISTRO_FAMILY  normalised family               (arch, debian, unknown)
# ==============================================================================

igor_detect_distro() {
    local _id="" _id_like=""

    if [ -r /etc/os-release ]; then
        # Source into a subshell and print — avoids polluting the environment
        # with the many variables in os-release.
        _id=$(       . /etc/os-release 2>/dev/null; printf '%s' "${ID:-}" )
        _id_like=$(  . /etc/os-release 2>/dev/null; printf '%s' "${ID_LIKE:-}" )
    fi

    IGOR_DISTRO_ID="${_id:-unknown}"

    # ── Family detection (priority order) ─────────────────────────────────────
    local _family="unknown"

    # Arch family: exact ID match first, then ID_LIKE contains "arch"
    case "$_id" in
        arch|manjaro|endeavouros|garuda|cachyos)
            _family="arch" ;;
        debian|ubuntu|raspbian|linuxmint|pop|kali|elementary)
            _family="debian" ;;
        fedora|rhel|centos|rocky|almalinux|ol)
            _family="rhel" ;;
        opensuse*|sles)
            _family="opensuse" ;;
        alpine)
            _family="alpine" ;;
        *)
            # Fall back to ID_LIKE
            case " ${_id_like} " in
                *" arch "*)
                    _family="arch" ;;
                *" debian "*|*" ubuntu "*)
                    _family="debian" ;;
                *" rhel "*|*" fedora "*)
                    _family="rhel" ;;
                *" opensuse "*)
                    _family="opensuse" ;;
            esac
            ;;
    esac

    IGOR_DISTRO_FAMILY="$_family"
    export IGOR_DISTRO_ID IGOR_DISTRO_FAMILY
}
