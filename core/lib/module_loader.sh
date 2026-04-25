#!/bin/bash
# =============================================================================
#  MODULE LOADER — core/lib/module_loader.sh
#
#  Discovers, sorts, loads, and registers Igor modules.
#
#  Public API:
#    igor_discover_modules   — scan modules/, return sorted name list
#    igor_sort_modules       — topological sort by depends_on
#    igor_load_module        — syntax-check, dep-check, source, call __register
#    igor_register_hook      — add function to named hook
#    igor_run_all_hooks      — run all functions for a hook (timeout 30)
#    igor_get_hooks          — echo functions registered for a hook
#    igor_has_bin            — test if a binary is on PATH
#    igor_has_module         — test if a module has been loaded
#
#  All functions are safe to call multiple times (idempotent discovery).
#  Errors are logged but never fatal — a broken module is skipped, not a crash.
# =============================================================================

# Hook registry: _IGOR_HOOKS[hook_name]="fn1 fn2 fn3"
declare -gA _IGOR_HOOKS 2>/dev/null || true

# Loaded module tracker: _IGOR_LOADED_MODULES["name"]=1
declare -gA _IGOR_LOADED_MODULES 2>/dev/null || true

# Capability catalog: _IGOR_CAPABILITIES[action_name]="description|function|load_module|tier|problems|menu_path"
# Populated by igor_load_capabilities() at AI session start from ai_capabilities hooks.
declare -gA _IGOR_CAPABILITIES 2>/dev/null || true

# Menu registry: _IGOR_MENU_REGISTRY[key]="label|load_type|load_arg|menu_func"
#   load_type: "module" → _igor_load_module arg  |  "subsystem" → _igor_load_subsystem label path
#   Modules call igor_register_menu_item to add entries here.
#   The main menu dispatcher checks this registry in the *) catch-all.
declare -gA _IGOR_MENU_REGISTRY 2>/dev/null || true

# Root of the Igor installation — resolved relative to this file's location
_IGOR_LOADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && cd ../.. && pwd)"

# ---------------------------------------------------------------------------
# _ml_log <level> <message>
#   Internal logging. Writes to stdout (info/ok) or stderr (warn/error).
# ---------------------------------------------------------------------------
_ml_log() {
    local _level="$1"; shift
    local _msg="$*"
    case "$_level" in
        ok)    printf '  [module_loader] ✔  %s\n' "$_msg" ;;
        info)  printf '  [module_loader]    %s\n' "$_msg" ;;
        warn)  printf '  [module_loader] ⚠  %s\n' "$_msg" >&2 ;;
        error) printf '  [module_loader] ✗  %s\n' "$_msg" >&2 ;;
    esac
}

# ---------------------------------------------------------------------------
# _ml_read_conf <module_dir> <key> [section]
#   Parse a single key from module.conf (simple INI parser, no deps).
#   Reads the first matching key= in the file (section filtering optional).
# ---------------------------------------------------------------------------
_ml_read_conf() {
    local _dir="$1" _key="$2"
    local _conf="${_dir}/module.conf"
    [ -f "$_conf" ] || return 1
    # Strip comments, extract key=value, return value
    grep -m1 "^${_key}[[:space:]]*=" "$_conf" 2>/dev/null \
        | sed 's/^[^=]*=[[:space:]]*//' \
        | sed 's/[[:space:]]*$//'
}

# ---------------------------------------------------------------------------
# igor_has_bin <binary_name>
#   Returns 0 if binary is available on PATH, 1 otherwise.
#   Modules use this at runtime to guard optional features.
# ---------------------------------------------------------------------------
igor_has_bin() {
    command -v "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# igor_has_module <module_name>
#   Returns 0 if the named module has been successfully loaded, 1 otherwise.
# ---------------------------------------------------------------------------
igor_has_module() {
    [ -n "${_IGOR_LOADED_MODULES[${1:-}]:-}" ]
}

# ---------------------------------------------------------------------------
# _ml_check_dependencies <module_dir> <module_name>
#
#   Reads the [dependencies] section of module.conf and validates:
#     required_bins   — comma-separated binary names; all must be on PATH
#     optional_bins   — comma-separated bin[:package[:desc]]; warn if absent
#     required_modules — comma-separated module names; all must be loaded
#     optional_modules — comma-separated mod[:desc]; warn if not loaded
#
#   Returns 0 if all required dependencies are satisfied.
#   Returns 1 if any required dependency is missing (caller should skip module).
#   Missing optional dependencies produce warnings but do not block loading.
# ---------------------------------------------------------------------------
_ml_check_dependencies() {
    local _dir="$1" _name="$2"
    local _conf="${_dir}/module.conf"
    [ -f "$_conf" ] || return 0   # no conf → no deps → pass

    local _fail=0

    # ── required_bins ──────────────────────────────────────────────────────
    local _req_bins
    _req_bins="$(_ml_read_conf "$_dir" "required_bins" 2>/dev/null || true)"
    _req_bins="${_req_bins//,/ }"
    local _bin
    for _bin in $_req_bins; do
        [ -z "$_bin" ] && continue
        if ! command -v "$_bin" >/dev/null 2>&1; then
            _ml_log error "${_name}: missing required binary: ${_bin}"
            _fail=1
        fi
    done

    # ── optional_bins (format per entry: bin[:package[:description]]) ──────
    local _opt_bins
    _opt_bins="$(_ml_read_conf "$_dir" "optional_bins" 2>/dev/null || true)"
    if [ -n "$_opt_bins" ]; then
        local _entry _obin _opkg _odesc
        while IFS= read -r _entry; do
            _entry="${_entry#"${_entry%%[![:space:]]*}"}"   # ltrim
            [ -z "$_entry" ] && continue
            IFS=':' read -r _obin _opkg _odesc <<< "$_entry"
            _obin="${_obin// /}"
            [ -z "$_obin" ] && continue
            if ! command -v "$_obin" >/dev/null 2>&1; then
                if [ -n "$_opkg" ]; then
                    _ml_log warn "${_name}: optional '${_obin}' not found — install ${_opkg} for: ${_odesc:-${_obin} features}"
                else
                    _ml_log warn "${_name}: optional '${_obin}' not found — some features disabled"
                fi
            fi
        done < <(printf '%s\n' "$_opt_bins" | tr ',' '\n')
    fi

    # ── required_modules ───────────────────────────────────────────────────
    local _req_mods
    _req_mods="$(_ml_read_conf "$_dir" "required_modules" 2>/dev/null || true)"
    _req_mods="${_req_mods//,/ }"
    local _mod
    for _mod in $_req_mods; do
        [ -z "$_mod" ] && continue
        if [ -z "${_IGOR_LOADED_MODULES[$_mod]:-}" ]; then
            _ml_log error "${_name}: required module '${_mod}' is not loaded"
            _fail=1
        fi
    done

    # ── optional_modules (format per entry: module[:description]) ──────────
    local _opt_mods
    _opt_mods="$(_ml_read_conf "$_dir" "optional_modules" 2>/dev/null || true)"
    if [ -n "$_opt_mods" ]; then
        local _mod_entry _omod _omod_desc
        while IFS= read -r _mod_entry; do
            _mod_entry="${_mod_entry#"${_mod_entry%%[![:space:]]*}"}"   # ltrim
            [ -z "$_mod_entry" ] && continue
            IFS=':' read -r _omod _omod_desc <<< "$_mod_entry"
            _omod="${_omod// /}"
            [ -z "$_omod" ] && continue
            if [ -z "${_IGOR_LOADED_MODULES[$_omod]:-}" ]; then
                _ml_log warn "${_name}: optional module '${_omod}' not loaded — ${_omod_desc:-some features may be limited}"
            fi
        done < <(printf '%s\n' "$_opt_mods" | tr ',' '\n')
    fi

    return $_fail
}

# ---------------------------------------------------------------------------
# igor_discover_modules
#
#   Scan ${IGOR_DIR}/modules/ for directories containing module.conf.
#   Prints one module name per line (unsorted — use igor_sort_modules next).
#   Sets global array _IGOR_MODULE_DIRS[name]=path for use by other functions.
# ---------------------------------------------------------------------------
declare -gA _IGOR_MODULE_DIRS 2>/dev/null || true

igor_discover_modules() {
    local _modules_root="${IGOR_DIR:-$_IGOR_LOADER_DIR}/modules"
    local _names=()

    if [ ! -d "$_modules_root" ]; then
        _ml_log warn "modules/ directory not found: $_modules_root"
        return 0
    fi

    local _dir _name
    for _dir in "${_modules_root}"/*/; do
        [ -d "$_dir" ] || continue
        [ -f "${_dir}module.conf" ] || continue
        _name="$(_ml_read_conf "$_dir" "name")"
        if [ -z "$_name" ]; then
            # Fall back to directory basename
            _name="$(basename "$_dir")"
        fi
        _IGOR_MODULE_DIRS["$_name"]="${_dir%/}"
        _names+=("$_name")
    done

    printf '%s\n' "${_names[@]}"
}

# ---------------------------------------------------------------------------
# igor_sort_modules [name...]
#
#   Topological sort of module names passed on stdin or as arguments.
#   Reads depends_on from module.conf for each module.
#   Outputs names in load order (dependencies first).
#   Cycles are detected and cause the offending module to be skipped with a
#   warning.
# ---------------------------------------------------------------------------
igor_sort_modules() {
    local _input_names=("$@")

    # If no args, read from stdin
    if [ ${#_input_names[@]} -eq 0 ]; then
        while IFS= read -r _line; do
            [ -n "$_line" ] && _input_names+=("$_line")
        done
    fi

    [ ${#_input_names[@]} -eq 0 ] && return 0

    # Build dependency map: _deps[name]="dep1 dep2"
    declare -A _deps
    local _n _dep_str
    for _n in "${_input_names[@]}"; do
        local _dir="${_IGOR_MODULE_DIRS[$_n]:-}"
        if [ -n "$_dir" ]; then
            _dep_str="$(_ml_read_conf "$_dir" "depends_on" 2>/dev/null || echo "")"
        else
            _dep_str=""
        fi
        # Normalize: comma or space separated → space separated
        _dep_str="${_dep_str//,/ }"
        _deps["$_n"]="$_dep_str"
    done

    # Kahn's algorithm (iterative topological sort)
    declare -A _in_degree
    declare -A _is_input
    local _name

    for _name in "${_input_names[@]}"; do
        _in_degree["$_name"]=0
        _is_input["$_name"]=1
    done

    # Count in-degrees (only count deps that are in our input set)
    for _name in "${_input_names[@]}"; do
        local _dep
        for _dep in ${_deps[$_name]}; do
            [ -n "${_is_input[$_dep]:-}" ] || continue
            _in_degree["$_name"]=$(( ${_in_degree[$_name]:-0} + 1 ))
        done
    done

    # Queue: all nodes with in_degree 0
    local _queue=()
    for _name in "${_input_names[@]}"; do
        [ "${_in_degree[$_name]}" -eq 0 ] && _queue+=("$_name")
    done

    local _sorted=()
    while [ ${#_queue[@]} -gt 0 ]; do
        # Pop first element
        _name="${_queue[0]}"
        _queue=("${_queue[@]:1}")
        _sorted+=("$_name")

        # Reduce in-degree for modules that depend on _name
        local _other
        for _other in "${_input_names[@]}"; do
            local _dep
            for _dep in ${_deps[$_other]}; do
                if [ "$_dep" = "$_name" ]; then
                    _in_degree["$_other"]=$(( ${_in_degree[$_other]} - 1 ))
                    if [ "${_in_degree[$_other]}" -eq 0 ]; then
                        _queue+=("$_other")
                    fi
                fi
            done
        done
    done

    # Detect cycle: if sorted < input, something was in a cycle
    if [ ${#_sorted[@]} -lt ${#_input_names[@]} ]; then
        for _name in "${_input_names[@]}"; do
            local _found=0
            local _s
            for _s in "${_sorted[@]}"; do
                [ "$_s" = "$_name" ] && { _found=1; break; }
            done
            [ "$_found" -eq 0 ] && \
                _ml_log warn "Dependency cycle detected — skipping module: $_name"
        done
    fi

    printf '%s\n' "${_sorted[@]}"
}

# ---------------------------------------------------------------------------
# igor_load_module <name>
#
#   Load a single module by name:
#     1. Locate module.sh via _IGOR_MODULE_DIRS
#     2. _ml_check_dependencies (required bins + modules)
#     3. bash -n syntax check
#     4. source module.sh
#     5. call <name>__register
#
#   Idempotent: already-loaded modules are silently skipped.
#   Returns 0 on success, 1 on failure (and logs the reason).
# ---------------------------------------------------------------------------
igor_load_module() {
    local _name="$1"
    [ -n "$_name" ] || { _ml_log error "igor_load_module: no module name given"; return 1; }

    # Idempotency check
    if [ -n "${_IGOR_LOADED_MODULES[$_name]:-}" ]; then
        return 0
    fi

    local _dir="${_IGOR_MODULE_DIRS[$_name]:-}"
    if [ -z "$_dir" ]; then
        _ml_log error "Module not found in registry: $_name (run igor_discover_modules first)"
        return 1
    fi

    local _module_sh="${_dir}/module.sh"
    if [ ! -f "$_module_sh" ]; then
        _ml_log error "module.sh missing for $_name: $_module_sh"
        return 1
    fi

    # Step 1: dependency check
    if ! _ml_check_dependencies "$_dir" "$_name"; then
        _ml_log error "Module $_name skipped — unmet required dependencies (see above)"
        return 1
    fi

    # Step 3: syntax check
    if ! bash -n "$_module_sh" 2>/tmp/_igor_ml_syntax_err; then
        local _syntax_err
        _syntax_err="$(cat /tmp/_igor_ml_syntax_err 2>/dev/null)"
        _ml_log error "Syntax error in $_name — SKIPPED: ${_syntax_err:-unknown}"
        return 1
    fi

    # Step 4: source
    # shellcheck disable=SC1090
    if ! source "$_module_sh" 2>/tmp/_igor_ml_source_err; then
        local _source_err
        _source_err="$(cat /tmp/_igor_ml_source_err 2>/dev/null)"
        _ml_log error "Failed to source $_name — SKIPPED: ${_source_err:-unknown}"
        return 1
    fi

    # Step 5: call __register
    local _register_fn="${_name}__register"
    if declare -f "$_register_fn" >/dev/null 2>&1; then
        if ! "$_register_fn" 2>/tmp/_igor_ml_register_err; then
            local _reg_err
            _reg_err="$(cat /tmp/_igor_ml_register_err 2>/dev/null)"
            _ml_log error "${_register_fn} failed for $_name — SKIPPED: ${_reg_err:-unknown}"
            return 1
        fi
    else
        _ml_log warn "$_name: no ${_register_fn} function found — hooks not registered"
    fi

    _IGOR_LOADED_MODULES["$_name"]=1

    # Export STACK_DIR if module declares stack_dir in module.conf
    # e.g. nextcloud_docker + stack_dir=nextcloud → NEXTCLOUD_DOCKER_STACK_DIR=/path/config/stacks/nextcloud
    local _stack_dir
    _stack_dir="$(_ml_read_conf "$_dir" "stack_dir" 2>/dev/null || echo "")"
    if [[ -n "$_stack_dir" ]]; then
        local _stacks="${IGOR_STACKS:-${_IGOR_LOADER_DIR}/config/stacks}"
        local _full_stack="${_stacks}/${_stack_dir}"
        local _var_name="${_name^^}_STACK_DIR"
        _var_name="${_var_name//-/_}"       # normalize hyphens → underscores
        export "${_var_name}"="${_full_stack}"
        if [[ ! -d "$_full_stack" ]]; then
            _ml_log warn "Module ${_name}: stack dir missing at ${_full_stack}"
            _ml_log warn "  → First time? Run:  bash igor.sh --install ${_name}"
        fi
    fi

    _ml_log ok "Loaded module: $_name"
    return 0
}

# ---------------------------------------------------------------------------
# igor_load_all_modules
#
#   Convenience: discover → sort → load all modules in dependency order.
#   Returns 0 even if some modules fail (errors are logged).
# ---------------------------------------------------------------------------
igor_load_all_modules() {
    # Call igor_discover_modules directly (NOT in a subshell) so that
    # _IGOR_MODULE_DIRS is populated in the current shell context.
    # Discard stdout — we'll read from _IGOR_MODULE_DIRS directly.
    igor_discover_modules > /dev/null

    local _names=("${!_IGOR_MODULE_DIRS[@]}")
    [ ${#_names[@]} -eq 0 ] && return 0

    local _sorted_list
    _sorted_list="$(igor_sort_modules "${_names[@]}")"

    local _name
    while IFS= read -r _name; do
        [ -n "$_name" ] || continue
        igor_load_module "$_name"
    done <<< "$_sorted_list"

    return 0
}

# ---------------------------------------------------------------------------
# igor_module_install <module_name>
#
#   Run first-time setup for a module.
#   Calls <name>__install() if it exists. No-op if the function is absent.
#   Idempotency is the responsibility of each module's __install hook.
# ---------------------------------------------------------------------------
igor_module_install() {
    local _name="${1:-}"
    [ -n "$_name" ] || { _ml_log error "igor_module_install: no module name given"; return 1; }

    if [ -z "${_IGOR_LOADED_MODULES[$_name]:-}" ]; then
        _ml_log error "Module '${_name}' is not loaded — run igor_load_all_modules first"
        return 1
    fi

    local _install_fn="${_name}__install"
    if declare -f "$_install_fn" >/dev/null 2>&1; then
        _ml_log info "Running ${_install_fn}..."
        if "$_install_fn"; then
            _ml_log ok "${_name} install complete"
        else
            _ml_log error "${_name}__install failed"
            return 1
        fi
    else
        _ml_log info "Module '${_name}' has no __install hook — nothing to do"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# igor_module_upgrade <module_name>
#
#   Run post-update migration for a module.
#   Calls <name>__upgrade() if it exists. No-op if the function is absent.
# ---------------------------------------------------------------------------
igor_module_upgrade() {
    local _name="${1:-}"
    [ -n "$_name" ] || { _ml_log error "igor_module_upgrade: no module name given"; return 1; }

    if [ -z "${_IGOR_LOADED_MODULES[$_name]:-}" ]; then
        _ml_log error "Module '${_name}' is not loaded — run igor_load_all_modules first"
        return 1
    fi

    local _upgrade_fn="${_name}__upgrade"
    if declare -f "$_upgrade_fn" >/dev/null 2>&1; then
        _ml_log info "Running ${_upgrade_fn}..."
        if "$_upgrade_fn"; then
            _ml_log ok "${_name} upgrade complete"
        else
            _ml_log error "${_name}__upgrade failed"
            return 1
        fi
    else
        _ml_log info "Module '${_name}' has no __upgrade hook — nothing to do"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# igor_module_remove <module_name>
#
#   Run cleanup for a module. Always asks for confirmation before proceeding.
#   Calls <name>__uninstall() if it exists. No-op if the function is absent.
#   DESTROY-tier: the hook itself may contain further DESTROY prompts.
# ---------------------------------------------------------------------------
igor_module_remove() {
    local _name="${1:-}"
    [ -n "$_name" ] || { _ml_log error "igor_module_remove: no module name given"; return 1; }

    if [ -z "${_IGOR_LOADED_MODULES[$_name]:-}" ]; then
        _ml_log error "Module '${_name}' is not loaded — run igor_load_all_modules first"
        return 1
    fi

    local _uninstall_fn="${_name}__uninstall"
    if ! declare -f "$_uninstall_fn" >/dev/null 2>&1; then
        _ml_log info "Module '${_name}' has no __uninstall hook — nothing to do"
        return 0
    fi

    printf '\n  [module_loader] ⚠  Removing module: %s\n' "$_name"
    printf '  [module_loader]    This may make destructive changes. Type YES to confirm: '
    local _confirm
    read -r _confirm
    if [ "$_confirm" != "YES" ]; then
        _ml_log info "Remove cancelled."
        return 0
    fi

    _ml_log info "Running ${_uninstall_fn}..."
    if "$_uninstall_fn"; then
        _ml_log ok "${_name} removal complete"
    else
        _ml_log error "${_name}__uninstall failed"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# igor_register_hook <hook_name> <function_name>
#
#   Add <function_name> to the registry for <hook_name>.
#   The same function can only be registered once per hook (idempotent).
# ---------------------------------------------------------------------------
igor_register_hook() {
    local _hook="$1" _fn="$2"
    [ -n "$_hook" ] || { _ml_log error "igor_register_hook: missing hook name"; return 1; }
    [ -n "$_fn" ]   || { _ml_log error "igor_register_hook: missing function name"; return 1; }

    local _existing="${_IGOR_HOOKS[$_hook]:-}"

    # Idempotency: skip if already registered
    local _entry
    for _entry in $_existing; do
        [ "$_entry" = "$_fn" ] && return 0
    done

    _IGOR_HOOKS["$_hook"]="${_existing:+$_existing }${_fn}"
    return 0
}

# ---------------------------------------------------------------------------
# igor_register_menu_item <key> <label> <load_type> <load_arg> <menu_func>
#
#   Register a custom main-menu entry for a module.
#   <key>       — single character or short string the user types at the menu
#   <label>     — description shown in recent-items and on dispatch
#   <load_type> — "module" (calls _igor_load_module) or "subsystem" (calls _igor_load_subsystem)
#   <load_arg>  — module name OR "subsystem_id path/to/core.sh"
#   <menu_func> — function to call after loading (e.g. menu_foo)
#
#   Idempotent: re-registering the same key overwrites the previous entry.
#
#   Example (inside a module's __register function):
#     igor_register_menu_item "x" "MY MODULE — does stuff" "module" "my_module" "menu_my_module"
# ---------------------------------------------------------------------------
igor_register_menu_item() {
    local _key="$1" _label="$2" _type="$3" _arg="$4" _func="$5"
    [ -n "$_key" ]   || { _ml_log error "igor_register_menu_item: missing key";   return 1; }
    [ -n "$_label" ] || { _ml_log error "igor_register_menu_item: missing label"; return 1; }
    [ -n "$_func" ]  || { _ml_log error "igor_register_menu_item: missing func";  return 1; }
    _IGOR_MENU_REGISTRY["$_key"]="${_label}|${_type}|${_arg}|${_func}"
    return 0
}

# ---------------------------------------------------------------------------
# igor_dispatch_menu_item <key>
#
#   Look up <key> in _IGOR_MENU_REGISTRY and dispatch to the registered entry.
#   Returns 0 if dispatched, 1 if key not found (caller handles unknown input).
# ---------------------------------------------------------------------------
igor_dispatch_menu_item() {
    local _key="$1"
    local _entry="${_IGOR_MENU_REGISTRY[$_key]:-}"
    [ -n "$_entry" ] || return 1

    local _label _type _arg _func
    IFS='|' read -r _label _type _arg _func <<< "$_entry"

    _igor_record_recent "$_key" "$_label"
    case "$_type" in
        module)    _igor_load_module "$_arg" ;;
        subsystem) _igor_load_subsystem $_arg ;;   # _arg may be "id path/to/core.sh"
    esac
    "$_func"
    return 0
}

# ---------------------------------------------------------------------------
# igor_get_hooks <hook_name>
#
#   Print the list of functions registered for <hook_name>, one per line.
#   Prints nothing if no functions are registered.
# ---------------------------------------------------------------------------
igor_get_hooks() {
    local _hook="$1"
    [ -n "$_hook" ] || return 0
    local _entry
    for _entry in ${_IGOR_HOOKS[$_hook]:-}; do
        printf '%s\n' "$_entry"
    done
}

# ---------------------------------------------------------------------------
# igor_run_all_hooks <hook_name> [arg...]
#
#   Run every function registered for <hook_name>, in registration order.
#   Each call gets a 30-second timeout (IGOR_HOOK_TIMEOUT overrides).
#   Failures are logged but do not stop subsequent hooks.
#   Returns 0 if all hooks succeeded, 1 if any hook failed.
# ---------------------------------------------------------------------------
igor_run_all_hooks() {
    local _hook="$1"; shift
    [ -n "$_hook" ] || { _ml_log error "igor_run_all_hooks: missing hook name"; return 1; }

    local _timeout="${IGOR_HOOK_TIMEOUT:-30}"
    local _any_fail=0
    local _fn

    for _fn in ${_IGOR_HOOKS[$_hook]:-}; do
        if ! declare -f "$_fn" >/dev/null 2>&1; then
            _ml_log warn "Hook $_hook: function $_fn not found — skipping"
            _any_fail=1
            continue
        fi

        if ! timeout "$_timeout" bash -c "$(declare -f "$_fn"); $_fn $(printf '%q ' "$@")" \
            2>/tmp/_igor_ml_hook_err; then
            local _exit_code=$?
            local _hook_err
            _hook_err="$(cat /tmp/_igor_ml_hook_err 2>/dev/null)"
            if [ "$_exit_code" -eq 124 ]; then
                _ml_log warn "Hook $_hook: $_fn timed out after ${_timeout}s"
            else
                _ml_log warn "Hook $_hook: $_fn failed (exit ${_exit_code}): ${_hook_err:-}"
            fi
            _any_fail=1
        fi
    done

    return $_any_fail
}

# ---------------------------------------------------------------------------
# igor_load_capabilities
#
#   Calls all functions registered for the "ai_capabilities" hook and parses
#   their output into the _IGOR_CAPABILITIES associative array.
#
#   Each module's ai_capabilities function emits one or more blocks:
#     ACTION <name>
#     DESCRIPTION <text>
#     FUNCTION <bash_function_name>
#     LOAD_MODULE <module_name>
#     TIER READ|CHANGE|DESTROY
#     PROBLEMS <comma-separated keywords>
#     MENU_PATH <human-readable path>
#
#   Stored as: _IGOR_CAPABILITIES[name]="desc|fn|mod|tier|problems|menu_path"
#   Idempotent — re-running clears and repopulates.
# ---------------------------------------------------------------------------
igor_load_capabilities() {
    _IGOR_CAPABILITIES=()   # clear before repopulating

    local _fns="${_IGOR_HOOKS[ai_capabilities]:-}"
    [ -z "$_fns" ] && return 0

    local _fn
    for _fn in $_fns; do
        declare -f "$_fn" &>/dev/null || continue
        local _raw; _raw=$("$_fn" 2>/dev/null) || continue
        [ -z "$_raw" ] && continue

        # Parse blocks separated by blank lines or ACTION lines
        local _name="" _desc="" _func="" _mod="" _tier="CHANGE" _probs="" _mpath=""
        while IFS= read -r _line || [ -n "$_line" ]; do
            case "$_line" in
                ACTION\ *)
                    # Save previous block if complete
                    if [ -n "$_name" ] && [ -n "$_func" ]; then
                        _IGOR_CAPABILITIES["$_name"]="${_desc}|${_func}|${_mod}|${_tier}|${_probs}|${_mpath}"
                    fi
                    _name="${_line#ACTION }"; _name="${_name## }"; _name="${_name%% }"
                    _desc=""; _func=""; _mod=""; _tier="CHANGE"; _probs=""; _mpath=""
                    ;;
                DESCRIPTION\ *)  _desc="${_line#DESCRIPTION }" ;;
                FUNCTION\ *)     _func="${_line#FUNCTION }" ;;
                LOAD_MODULE\ *)  _mod="${_line#LOAD_MODULE }" ;;
                TIER\ *)         _tier="${_line#TIER }" ;;
                PROBLEMS\ *)     _probs="${_line#PROBLEMS }" ;;
                MENU_PATH\ *)    _mpath="${_line#MENU_PATH }" ;;
            esac
        done <<< "$_raw"

        # Save final block
        if [ -n "$_name" ] && [ -n "$_func" ]; then
            _IGOR_CAPABILITIES["$_name"]="${_desc}|${_func}|${_mod}|${_tier}|${_probs}|${_mpath}"
        fi
    done

    return 0
}
