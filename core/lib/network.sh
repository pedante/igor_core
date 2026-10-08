# Bounded read-only Linux network discovery for the System network domain.
# These helpers inspect kernel/iproute2 and resolver state only. They do not
# probe internet reachability, change interfaces/routes/DNS or invoke Wi-Fi
# providers.

_network_query_python() {
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

_network_query_run() {
    local _kind="${1:-}" _py _root
    [ "$#" -eq 1 ] && [[ "$_kind" =~ ^(interfaces|routes|dns|snapshot)$ ]] || return 2
    _py="$(_network_query_python)" || return 2
    _root="${_IGOR_LOADER_DIR:-${IGOR_DIR:-}}"
    [ -n "$_root" ] || return 2
    "$_py" "$_root/core/lib/network_query.py" "$_kind"
}

network_interfaces_query() { _network_query_run interfaces; }
network_routes_query() { _network_query_run routes; }
network_dns_query() { _network_query_run dns; }
network_snapshot_query() { _network_query_run snapshot; }
