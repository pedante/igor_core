# Bounded read-only Linux host runtime telemetry for System S8.1.
# This bridge reads procfs through the Core Python normalizer only. It does not
# interpret health, invoke privilege, change host state or use optional providers.

_host_runtime_python() {
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

host_runtime_status_query() {
    local _py _root
    [ "$#" -eq 0 ] || return 2
    _py="$(_host_runtime_python)" || return 2
    _root="${_IGOR_LOADER_DIR:-${IGOR_DIR:-}}"
    [ -n "$_root" ] || return 2
    "$_py" "$_root/core/lib/host_runtime_query.py" status
}
