#!/usr/bin/env bash
# Core-owned bounded Linux identity/path mechanics for System S6.

_access_python() {
    if [ -n "${IGOR_PYTHON:-}" ] && command -v "$IGOR_PYTHON" >/dev/null 2>&1; then
        printf '%s\n' "$IGOR_PYTHON"
    elif command -v python3 >/dev/null 2>&1; then
        printf 'python3\n'
    else
        return 1
    fi
}

_access_root() {
    local _root="${_IGOR_LOADER_DIR:-${IGOR_DIR:-}}"
    [ -n "$_root" ] || return 2
    printf '%s\n' "$_root"
}

_access_run() {
    local _script="${1:-}" _action="${2:-}" _arg="${3-}" _py _root
    [ -n "$_script" ] && [ -n "$_action" ] || return 2
    _py="$(_access_python)" || return 2
    _root="$(_access_root)" || return 2
    if [ "$#" -ge 3 ]; then
        "$_py" "$_root/core/lib/$_script" "$_action" "$_arg"
    else
        "$_py" "$_root/core/lib/$_script" "$_action"
    fi
}

account_users_query() { _access_run account_query.py users; }
account_groups_query() { _access_run account_query.py groups; }

path_candidates_query() { _access_run access.py candidates "${1:-}"; }
mutable_path_candidates_query() { _access_run access.py candidates-mutable "${1:-}"; }
path_status_query() { _access_run access.py inspect "$1"; }

permission_owner_plan() { _access_run access.py plan-owner "$1"; }
permission_group_plan() { _access_run access.py plan-group "$1"; }
permission_mode_plan() { _access_run access.py plan-mode "$1"; }

permission_owner_verify() { _access_run access.py verify-owner "$1"; }
permission_group_verify() { _access_run access.py verify-group "$1"; }
permission_mode_verify() { _access_run access.py verify-mode "$1"; }
