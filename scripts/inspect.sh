#!/bin/bash
# =============================================================================
#  run.sh — Igor module inspector and developer tooling
#
#  Standalone script: no Igor library deps. Works with grep/sed/awk only.
#  Must be run from the Igor project root (where igor.sh lives).
#
#  Usage:
#    ./run.sh inspect <module_dir>       Print module manifest
#    ./run.sh inspect --all              Inspect all modules in modules/
#    ./run.sh list                       List all discovered modules
#    ./run.sh deps                       Show inter-module dependency graph
#
#  Future:
#    ./run.sh lint <module_dir>          Validate module against interface contract
#    ./run.sh diff <module_dir>          Compare defaults vs stacks
# =============================================================================

set -o pipefail

# ── Colour codes ──────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    _B='\033[1m'   # bold
    _C='\033[36m'  # cyan
    _G='\033[32m'  # green
    _Y='\033[33m'  # yellow
    _R='\033[31m'  # red
    _D='\033[2m'   # dim
    _N='\033[0m'   # reset
else
    _B=''; _C=''; _G=''; _Y=''; _R=''; _D=''; _N=''
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

# _conf_get <file> <key>
#   Read first matching key= line from a flat conf file (no section awareness).
_conf_get() {
    local _file="$1" _key="$2"
    [ -f "$_file" ] || return 1
    grep -m1 "^${_key}[[:space:]]*=" "$_file" 2>/dev/null \
        | sed 's/^[^=]*=[[:space:]]*//' \
        | sed 's/[[:space:]]*$//'
}

# _conf_get_section <file> <section> <key>
#   Section-aware reader: returns value of <key> inside [<section>].
#   Returns all matching lines if the key appears more than once (e.g. panels=).
_conf_get_section() {
    local _file="$1" _section="$2" _key="$3"
    [ -f "$_file" ] || return 1
    awk -v section="[${_section}]" -v key="${_key}" '
        /^\[/ { in_section = ($0 == section) }
        in_section && /^[[:space:]]*[^#]/ {
            if ($0 ~ "^" key "[[:space:]]*=") {
                sub(/^[^=]*=[[:space:]]*/, "")
                sub(/[[:space:]]*$/, "")
                print
            }
        }
    ' "$_file"
}

# _hr [char] [width]
#   Print a horizontal rule.
_hr() {
    local _char="${1:-─}" _width="${2:-60}"
    printf '%s' "$_D"
    printf '%*s' "$_width" '' | tr ' ' "$_char"
    printf '%s\n' "$_N"
}

# _section <title>
#   Print a section heading.
_section() {
    printf '\n%s%s%s\n' "$_C" "$1" "$_N"
    _hr
}

# ── inspect_module <module_dir> ───────────────────────────────────────────────
inspect_module() {
    local _dir="${1%/}"  # strip trailing slash

    # Validate
    if [ ! -f "${_dir}/module.conf" ]; then
        printf '%sERROR:%s Not a valid module — no module.conf in: %s\n' "$_R" "$_N" "$_dir" >&2
        return 1
    fi

    local _conf="${_dir}/module.conf"
    local _module_sh="${_dir}/module.sh"

    local _name; _name=$(_conf_get "$_conf" "name")
    local _display; _display=$(_conf_get "$_conf" "display_name")
    local _version; _version=$(_conf_get "$_conf" "version")
    local _desc; _desc=$(_conf_get "$_conf" "description")
    local _requires_core; _requires_core=$(_conf_get "$_conf" "requires_core")
    local _depends; _depends=$(_conf_get "$_conf" "depends_on")
    local _stack; _stack=$(_conf_get "$_conf" "stack_dir")
    local _compose; _compose=$(_conf_get "$_conf" "compose_file")
    local _priority; _priority=$(_conf_get "$_conf" "menu_priority")
    local _section_name; _section_name=$(_conf_get "$_conf" "menu_section")

    printf '\n'
    printf '%s%s=== MODULE MANIFEST ===%s\n' "$_B" "$_C" "$_N"
    _hr '═'
    printf '  %-16s %s%s%s\n' "Name:"         "$_B" "${_name:-?}" "$_N"
    printf '  %-16s %s\n'     "Display:"      "${_display:-—}"
    printf '  %-16s %s\n'     "Version:"      "${_version:-—}"
    printf '  %-16s %s\n'     "Description:"  "${_desc:-—}"
    printf '  %-16s %s\n'     "Core req:"     "${_requires_core:-—}"
    printf '  %-16s %s\n'     "Depends on:"   "${_depends:-(none)}"
    printf '  %-16s %s\n'     "Menu section:" "${_section_name:-—}"
    printf '  %-16s %s\n'     "Menu priority:""${_priority:-—}"
    printf '  %-16s %s\n'     "Stack dir:"    "${_stack:-(no stack)}"
    [ -n "$_compose" ] && printf '  %-16s %s\n' "Compose file:" "$_compose"

    # ── Hooks ────────────────────────────────────────────────────────────────
    _section "HOOKS (module.sh)"
    if [ -f "$_module_sh" ]; then
        local _found=0
        local _required_hooks="__register __health"
        local _line
        while IFS= read -r _line; do
            local _fn; _fn=$(echo "$_line" | sed 's/()[[:space:]]*{.*//')
            local _tag=""
            case "$_fn" in
                *__register|*__health) _tag="${_G}[REQUIRED]${_N}" ;;
                *__install)            _tag="${_Y}[lifecycle]${_N}" ;;
                *__upgrade)            _tag="${_Y}[lifecycle]${_N}" ;;
                *__uninstall)          _tag="${_Y}[lifecycle: DESTROY]${_N}" ;;
                *__diagnose)           _tag="${_D}[hook]${_N}" ;;
                *__ai_context)         _tag="${_D}[hook]${_N}" ;;
                *__notify_sources)     _tag="${_D}[hook]${_N}" ;;
                *)                     _tag="${_D}[optional]${_N}" ;;
            esac
            printf '  %s  %b\n' "$_fn" "$_tag"
            _found=1
        done < <(grep -E "^${_name:-[a-z_]+}__[a-z_]+\(\)" "$_module_sh" 2>/dev/null)
        [ $_found -eq 0 ] && printf '  %s(none found)%s\n' "$_D" "$_N"
    else
        printf '  %smodule.sh not found%s\n' "$_R" "$_N"
    fi

    # ── Secrets ──────────────────────────────────────────────────────────────
    _section "SECRETS ([secrets] section)"
    local _vars; _vars=$(_conf_get_section "$_conf" "secrets" "variables")
    local _patterns; _patterns=$(_conf_get_section "$_conf" "secrets" "scrub_patterns")
    if [ -n "$_vars" ]; then
        printf '  Variables:     %s\n' "$_vars"
        printf '  Scrub patterns:%s\n' "${_patterns:-(none)}"
    else
        printf '  %s(no [secrets] section)%s\n' "$_D" "$_N"
    fi

    # ── Panels ───────────────────────────────────────────────────────────────
    _section "PANELS ([panels] section)"
    local _panels_out=0
    while IFS= read -r _panel_line; do
        [ -z "$_panel_line" ] && continue
        local _pname _pcmd _pdesc
        IFS=':' read -r _pname _pcmd _pdesc <<< "$_panel_line"
        printf '  %-20s %s\n' "${_pname}:" "${_pdesc:-${_pcmd}}"
        _panels_out=1
    done < <(_conf_get_section "$_conf" "panels" "panels")
    [ $_panels_out -eq 0 ] && printf '  %s(no panels declared)%s\n' "$_D" "$_N"

    # ── Dependencies ─────────────────────────────────────────────────────────
    _section "DEPENDENCIES ([dependencies] section)"
    local _req_bins; _req_bins=$(_conf_get_section "$_conf" "dependencies" "required_bins")
    local _opt_bins; _opt_bins=$(_conf_get_section "$_conf" "dependencies" "optional_bins")
    local _req_mods; _req_mods=$(_conf_get_section "$_conf" "dependencies" "required_modules")
    local _opt_mods; _opt_mods=$(_conf_get_section "$_conf" "dependencies" "optional_modules")

    local _dep_found=0
    if [ -n "$_req_bins" ]; then
        local _b
        for _b in $(echo "$_req_bins" | tr ',' ' '); do
            [ -z "$_b" ] && continue
            if command -v "$_b" >/dev/null 2>&1; then
                printf '  %s[required bin]%s  %-20s %s✔ found%s\n' "$_G" "$_N" "$_b" "$_G" "$_N"
            else
                printf '  %s[required bin]%s  %-20s %s✗ MISSING%s\n' "$_R" "$_N" "$_b" "$_R" "$_N"
            fi
            _dep_found=1
        done
    fi
    if [ -n "$_opt_bins" ]; then
        local _entry
        while IFS= read -r _entry; do
            [ -z "$_entry" ] && continue
            local _obin _opkg _odesc
            IFS=':' read -r _obin _opkg _odesc <<< "$_entry"
            _obin="${_obin// /}"
            [ -z "$_obin" ] && continue
            if command -v "$_obin" >/dev/null 2>&1; then
                printf '  %s[optional bin]%s  %-20s %s✔ found%s\n' "$_D" "$_N" "$_obin" "$_G" "$_N"
            else
                printf '  %s[optional bin]%s  %-20s %s✗ not found%s  (%s)\n' \
                    "$_D" "$_N" "$_obin" "$_Y" "$_N" "${_odesc:-no description}"
            fi
            _dep_found=1
        done < <(echo "$_opt_bins" | tr ',' '\n')
    fi
    if [ -n "$_req_mods" ]; then
        local _m
        for _m in $(echo "$_req_mods" | tr ',' ' '); do
            [ -z "$_m" ] && continue
            printf '  %s[required mod]%s  %s\n' "$_G" "$_N" "$_m"
            _dep_found=1
        done
    fi
    if [ -n "$_opt_mods" ]; then
        local _me
        while IFS= read -r _me; do
            [ -z "$_me" ] && continue
            local _om _omd
            IFS=':' read -r _om _omd <<< "$_me"
            _om="${_om// /}"
            [ -z "$_om" ] && continue
            printf '  %s[optional mod]%s  %-20s (%s)\n' "$_D" "$_N" "$_om" "${_omd:-}"
            _dep_found=1
        done < <(echo "$_opt_mods" | tr ',' '\n')
    fi
    [ $_dep_found -eq 0 ] && printf '  %s(no dependencies declared)%s\n' "$_D" "$_N"

    # ── Directory structure ───────────────────────────────────────────────────
    _section "STRUCTURE"
    local _struct_found=0
    local _sd
    for _sd in checks knowledge runbooks patterns healing recovery alerts tools validators defaults; do
        if [ -d "${_dir}/${_sd}" ]; then
            local _fcount; _fcount=$(ls "${_dir}/${_sd}" 2>/dev/null | wc -l)
            printf '  %-20s %d file(s)\n' "${_sd}/" "$_fcount"
            _struct_found=1
        fi
    done
    [ -f "$_module_sh" ] && { printf '  %-20s ✔\n' "module.sh"; _struct_found=1; }
    [ $_struct_found -eq 0 ] && printf '  %s(empty — only module.conf present)%s\n' "$_D" "$_N"

    # ── AI tools ─────────────────────────────────────────────────────────────
    if [ -d "${_dir}/tools" ] && ls "${_dir}/tools/"*.json >/dev/null 2>&1; then
        _section "AI TOOLS"
        local _tf
        for _tf in "${_dir}/tools/"*.json; do
            [ -f "$_tf" ] || continue
            if command -v python3 >/dev/null 2>&1; then
                python3 -c "
import json, sys
try:
    tools = json.load(open('${_tf}'))
    if not isinstance(tools, list): tools = [tools]
    for t in tools:
        name = t.get('name','?')
        desc = t.get('description','')[:60]
        print(f'  {name:<24} {desc}...')
except Exception as e:
    print(f'  (parse error: {e})')
" 2>/dev/null
            else
                printf '  %s (python3 needed to parse JSON tools)\n' "$(basename "$_tf")"
            fi
        done
    fi

    printf '\n'
    _hr '═'
    printf '\n'
}

# ── list_modules ──────────────────────────────────────────────────────────────
list_modules() {
    local _root="${1:-modules}"
    printf '\n%s%sModules in %s/%s\n' "$_B" "$_C" "$_root" "$_N"
    _hr

    local _found=0
    local _mdir
    for _mdir in "${_root}"/*/; do
        [ -d "$_mdir" ] || continue
        [ -f "${_mdir}module.conf" ] || continue
        local _n; _n=$(_conf_get "${_mdir}module.conf" "name")
        local _d; _d=$(_conf_get "${_mdir}module.conf" "display_name")
        local _v; _v=$(_conf_get "${_mdir}module.conf" "version")
        printf '  %-30s %-10s %s\n' "${_n:-$(basename "$_mdir")}" "${_v:-?}" "${_d:-}"
        _found=1
    done
    [ $_found -eq 0 ] && printf '  %s(no modules found in %s)%s\n' "$_D" "$_root" "$_N"
    printf '\n'
}

# ── deps_graph ────────────────────────────────────────────────────────────────
deps_graph() {
    local _root="${1:-modules}"
    printf '\n%s%sDependency graph%s\n' "$_B" "$_C" "$_N"
    _hr

    local _mdir
    for _mdir in "${_root}"/*/; do
        [ -d "$_mdir" ] || continue
        [ -f "${_mdir}module.conf" ] || continue
        local _n; _n=$(_conf_get "${_mdir}module.conf" "name")
        local _dep; _dep=$(_conf_get "${_mdir}module.conf" "depends_on")
        if [ -n "$_dep" ]; then
            printf '  %-30s → %s\n' "${_n:-$(basename "$_mdir")}" "$_dep"
        else
            printf '  %-30s %s(no deps)%s\n' "${_n:-$(basename "$_mdir")}" "$_D" "$_N"
        fi
    done
    printf '\n'
}

# ── usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

${_B}run.sh${_N} — Igor module inspector

${_C}Usage:${_N}
  ./run.sh inspect <module_dir>      Print manifest for a single module
  ./run.sh inspect --all             Inspect all modules in modules/
  ./run.sh list                      List all modules with versions
  ./run.sh deps                      Show inter-module dependency graph
  ./run.sh help                      Show this help

${_C}Examples:${_N}
  ./run.sh inspect modules/nextcloud_docker
  ./run.sh inspect --all
  ./run.sh list
  ./run.sh deps

EOF
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
_SUBCOMMAND="${1:-}"
shift || true

case "$_SUBCOMMAND" in
    inspect)
        _target="${1:-}"
        if [ "$_target" = "--all" ]; then
            _found=0
            for _mdir in modules/*/; do
                [ -d "$_mdir" ] || continue
                [ -f "${_mdir}module.conf" ] || continue
                inspect_module "$_mdir"
                _found=1
            done
            [ $_found -eq 0 ] && printf '%sNo modules found in modules/%s\n' "$_Y" "$_N"
        elif [ -n "$_target" ]; then
            inspect_module "$_target"
        else
            printf '%sUsage: ./run.sh inspect <module_dir>  |  ./run.sh inspect --all%s\n' "$_Y" "$_N"
            exit 1
        fi
        ;;
    list)
        list_modules "modules"
        ;;
    deps)
        deps_graph "modules"
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        printf '%sUnknown subcommand: %s%s\n' "$_R" "$_SUBCOMMAND" "$_N" >&2
        usage >&2
        exit 1
        ;;
esac
