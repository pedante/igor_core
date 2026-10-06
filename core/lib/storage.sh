# Bounded read-only Linux storage discovery shared by System observers and UI
# candidate resolution. These helpers do not mount, unmount or edit persistence.

_storage_query_python() {
    if [ -n "${IGOR_PYTHON:-}" ] && command -v "$IGOR_PYTHON" >/dev/null 2>&1; then
        printf '%s\n' "$IGOR_PYTHON"
    elif command -v python3 >/dev/null 2>&1; then
        printf 'python3\n'
    elif command -v python >/dev/null 2>&1 && python --version 2>&1 | grep -q '^Python 3'; then
        printf 'python\n'
    else
        return 1
    fi
}

_storage_query_run() {
    local _kind="${1:-}" _py _root
    [ "$#" -eq 1 ] && [[ "$_kind" =~ ^(mounts|filesystems)$ ]] || return 2
    _py="$(_storage_query_python)" || return 2
    _root="${_IGOR_LOADER_DIR:-${IGOR_DIR:-}}"
    [ -n "$_root" ] || return 2
    "$_py" "$_root/core/lib/storage_query.py" "$_kind"
}

storage_mounts_query() { _storage_query_run mounts; }
storage_filesystems_query() { _storage_query_run filesystems; }

_storage_admin_run() {
    local _action="${1:-}" _inputs="${2:-}" _py _root
    [ "$#" -eq 2 ] && [ -n "$_action" ] && [ -n "$_inputs" ] || return 2
    _py="$(_storage_query_python)" || return 2
    _root="${_IGOR_LOADER_DIR:-${IGOR_DIR:-}}"
    [ -n "$_root" ] || return 2
    "$_py" "$_root/core/lib/storage_admin.py" "$_action" "$_inputs"
}

storage_admin_plan_mount() { _storage_admin_run plan-mount "$1"; }
storage_admin_plan_unmount() { _storage_admin_run plan-unmount "$1"; }
storage_admin_ready_mount() { _storage_admin_run ready-mount "$1"; }
storage_admin_ready_unmount() { _storage_admin_run ready-unmount "$1"; }
storage_admin_verify_mount() { _storage_admin_run verify-mount "$1"; }
storage_admin_verify_unmount() { _storage_admin_run verify-unmount "$1"; }
