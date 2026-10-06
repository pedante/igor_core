# Optional bounded read-only NetworkManager Wi-Fi provider for System S7.3.
# Generic interface/route/DNS reads remain in core/lib/network.sh.

_networkmanager_wifi_python() {
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

_networkmanager_wifi_run() {
    local _kind="${1:-}" _py _root
    [ "$#" -eq 1 ] && [[ "$_kind" =~ ^(status|scan|profiles)$ ]] || return 2
    _py="$(_networkmanager_wifi_python)" || return 2
    _root="${_IGOR_LOADER_DIR:-${IGOR_DIR:-}}"
    [ -n "$_root" ] || return 2
    "$_py" "$_root/core/lib/networkmanager_wifi.py" "$_kind"
}

networkmanager_wifi_status_query() { _networkmanager_wifi_run status; }
networkmanager_wifi_scan_query() { _networkmanager_wifi_run scan; }
networkmanager_wifi_profiles_query() { _networkmanager_wifi_run profiles; }
