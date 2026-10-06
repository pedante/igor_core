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
