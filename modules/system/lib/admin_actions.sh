#!/bin/bash
# System administration action seam.
#
# This file intentionally contains domain actions only. It does not own
# distro commands. Package and service execution must be provided by the
# Core platform adapter layer.

system_admin_upgrade() {
    if ! command -v pkg_upgrade >/dev/null 2>&1; then
        printf '%s\n' '{"status":"error","error":{"code":"unsupported","message":"package upgrade adapter unavailable"}}'
        return 0
    fi
    pkg_upgrade
}

system_admin_cleanup() {
    if ! command -v pkg_cleanup >/dev/null 2>&1; then
        printf '%s\n' '{"status":"error","error":{"code":"unsupported","message":"package cleanup adapter unavailable"}}'
        return 0
    fi
    pkg_cleanup
}

system_admin_service_restart() {
    local unit="$1"
    if ! command -v svc_restart >/dev/null 2>&1; then
        printf '%s\n' '{"status":"error","error":{"code":"unsupported","message":"service restart adapter unavailable"}}'
        return 0
    fi
    svc_restart "$unit"
}
