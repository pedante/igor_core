#!/bin/bash
# =============================================================================
#  TUNING ENGINE — core/lib/tuning.sh
#
#  Reads resource-tier from $IGOR_TIER (set by core/host/profile.sh R0-1),
#  scans each loaded module's defaults/tuning.conf, and proposes tier-
#  appropriate configuration values for editable stack config files.
#
#  Safety contract:
#  - ALL writes are CHANGE-tier: shows diff + requires confirm() before writing
#  - Lines written by Igor are tagged:  value  # igor-managed: <tier> tier
#  - On subsequent runs, only igor-managed lines are updated — user edits are
#    left untouched
#  - An undo stack entry is pushed after each file write (if undo_stack.py
#    is available)
#
#  Public API:
#    igor_tune [--dry-run] [--module <name>]
#      Run the full tuning pass. With --dry-run, shows proposed changes only.
#    igor_tune_show_profile
#      Print current tier and profile JSON.
# =============================================================================

# ---------------------------------------------------------------------------
# _tune_tier_index
#   Return the 0-based index for the current tier (for pipe-separated values).
# ---------------------------------------------------------------------------
_tune_tier_index() {
    case "${IGOR_TIER:-standard}" in
        constrained) echo 0 ;;
        standard)    echo 1 ;;
        comfortable) echo 2 ;;
        server)      echo 3 ;;
        *)           echo 1 ;;   # unknown → standard
    esac
}

# ---------------------------------------------------------------------------
# _tune_parse_value <line> <tier_index>
#   Given a line like:  shared_buffers = 64MB | 128MB | 256MB | 512MB
#   and a tier_index (0–3), extract the value for that tier.
#   Prints the value; returns 1 if the line is not a pipe-delimited tuning line.
# ---------------------------------------------------------------------------
_tune_parse_value() {
    local _line="$1"
    local _idx="${2:-1}"

    # Must contain at least one pipe
    [[ "$_line" == *"|"* ]] || return 1

    # Strip key= part
    local _val_part
    _val_part="${_line#*=}"
    _val_part="${_val_part// /}"   # remove spaces

    # Split by pipe and pick index
    local _i=0
    local _field
    while IFS='|' read -ra _fields; do
        echo "${_fields[$_idx]}" | tr -d ' '
        return 0
    done <<< "$_val_part"
    return 1
}

# ---------------------------------------------------------------------------
# _tune_read_section <conf_file> <section>
#   Print all key=value lines from [section] in conf_file that contain pipes.
#   Format: key=val1|val2|val3|val4
# ---------------------------------------------------------------------------
_tune_read_section() {
    local _conf="$1" _sect="$2"
    awk -v section="[${_sect}]" '
        /^\[/ { in_section = ($0 == section); next }
        in_section && /^\s*#/ { next }
        in_section && /\|/ && /=/ { print }
    ' "$_conf"
}

# ---------------------------------------------------------------------------
# _tune_read_nginx_value <nginx_conf> <key>
#   Read current value of a bare nginx directive (e.g. worker_processes 2;)
#   Returns the value without the trailing semicolon.
# ---------------------------------------------------------------------------
_tune_read_nginx_value() {
    local _file="$1" _key="$2"
    grep -m1 "^[[:space:]]*${_key}[[:space:]]" "$_file" 2>/dev/null \
        | sed "s/^[[:space:]]*${_key}[[:space:]]*//" \
        | sed 's/[[:space:]]*;.*//' \
        | sed 's/[[:space:]]*#.*//' \
        | tr -d ' '
}

# ---------------------------------------------------------------------------
# _tune_write_nginx_value <nginx_conf> <key> <new_value> <tier>
#   Update or append a nginx directive.
#   If a line with the key exists AND is tagged "# igor-managed", replace it.
#   If a line with the key exists but has no tag, leave it (user-customized).
#   If the key doesn't exist, append to the end of the first non-comment block.
# ---------------------------------------------------------------------------
_tune_write_nginx_value() {
    local _file="$1" _key="$2" _val="$3" _tier="$4"
    local _tag="# igor-managed: ${_tier} tier"
    local _new_line="${_key} ${_val};  ${_tag}"

    if grep -q "^[[:space:]]*${_key}[[:space:]].*# igor-managed" "$_file" 2>/dev/null; then
        # Replace existing igor-managed line
        sed -i "s|^[[:space:]]*${_key}[[:space:]].*# igor-managed.*|${_new_line}|" "$_file"
    elif grep -q "^[[:space:]]*${_key}[[:space:]]" "$_file" 2>/dev/null; then
        # Line exists but no igor-managed tag — user-customized, leave it
        return 1
    else
        # Key not found — append before closing brace of first block or at end
        echo "${_new_line}" >> "$_file"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# _tune_push_undo <file> <description>
#   Push a file-snapshot undo entry to the undo stack (if undo_stack.py exists).
# ---------------------------------------------------------------------------
_tune_push_undo() {
    local _file="$1" _desc="$2"
    local _undo_py="${IGOR_DIR}/core/lib/undo_stack.py"
    [ -f "$_undo_py" ] || return 0
    [ -f "$_file" ]    || return 0

    local _session_id; _session_id="tuning-$(date +%Y%m%dT%H%M%S)"
    local _content; _content=$(cat "$_file" 2>/dev/null | base64 2>/dev/null || true)
    [ -z "$_content" ] && return 0

    python3 "$_undo_py" push "$_session_id" \
        "{\"type\":\"file_snapshot\",\"path\":\"${_file}\",\"description\":\"${_desc}\",\"content_b64\":\"${_content}\"}" \
        2>/dev/null || true
}

# ---------------------------------------------------------------------------
# igor_tune_show_profile
#   Print the current hardware tier and system profile summary.
# ---------------------------------------------------------------------------
igor_tune_show_profile() {
    local _profile="${IGOR_RUNTIME_DIR:-${IGOR_DIR}/data/runtime}/system_profile.json"
    echo ""
    if [ -n "${IGOR_TIER:-}" ]; then
        echo -e "  ${CYAN}Current tier:${NC} ${BOLD}${IGOR_TIER}${NC}"
    else
        echo -e "  ${YEL}IGOR_TIER not set — run 'igor profile' first.${NC}"
    fi
    if [ -f "$_profile" ]; then
        local _ram _cores _arch _storage
        _ram=$(    grep '"ram_mb"'      "$_profile" | grep -o '[0-9]*' | head -1)
        _cores=$(  grep '"cpu_cores"'   "$_profile" | grep -o '[0-9]*' | head -1)
        _arch=$(   grep '"arch"'        "$_profile" | sed 's/.*"arch"[^"]*"//;s/".*//')
        _storage=$(grep '"storage_type"' "$_profile" | sed 's/.*"storage_type"[^"]*"//;s/".*//')
        echo -e "  ${CYAN}RAM:${NC}          ${_ram:-?} MB"
        echo -e "  ${CYAN}CPU cores:${NC}    ${_cores:-?}"
        echo -e "  ${CYAN}Arch:${NC}         ${_arch:-?}"
        echo -e "  ${CYAN}Storage:${NC}      ${_storage:-?}"
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# igor_tune [--dry-run] [--module <name>]
#
#   Main entry point. Scans all loaded modules (or a single named module)
#   for defaults/tuning.conf, computes tier values, compares with current
#   stack config, and proposes/applies changes.
#
#   Only the [nginx] section writes directly to nginx.conf.
#   All other sections are printed as recommendations only.
# ---------------------------------------------------------------------------
igor_tune() {
    local _dry_run=false
    local _target_module=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run|-n) _dry_run=true ;;
            --module)     _target_module="${2:-}"; shift ;;
        esac
        shift
    done

    echo ""
    igor_tune_show_profile

    local _tier="${IGOR_TIER:-standard}"
    local _tier_idx; _tier_idx=$(_tune_tier_index)

    echo -e "  ${CYAN}Scanning modules for tuning.conf...${NC}"
    echo ""

    local _any_found=false
    local _any_changes=false

    local _mod
    for _mod in $(printf '%s\n' "${!_IGOR_LOADED_MODULES[@]:-}" | sort); do
        [ -n "$_target_module" ] && [ "$_mod" != "$_target_module" ] && continue

        local _dir="${_IGOR_MODULE_DIRS[$_mod]:-}"
        [ -z "$_dir" ] && continue

        local _tuning_conf="${_dir}/defaults/tuning.conf"
        [ -f "$_tuning_conf" ] || continue

        _any_found=true
        echo -e "  ${BOLD}Module: ${_mod}${NC}"
        echo -e "  ${CYAN}Tuning config:${NC} ${_tuning_conf}"
        echo ""

        # Locate the stack dir for this module
        local _stack_name; _stack_name=$(grep -m1 "^stack_dir" "${_dir}/module.conf" 2>/dev/null \
            | sed 's/^[^=]*=[[:space:]]*//' | sed 's/[[:space:]]*$//')
        local _stack_dir="${IGOR_STACKS:-${IGOR_DIR}/config/stacks}/${_stack_name}"

        # ── Iterate over sections in tuning.conf ─────────────────────────
        local _current_section=""
        while IFS= read -r _raw_line; do
            local _line="${_raw_line%%#*}"   # strip inline comments
            _line="${_line//[$'\t']/}"       # strip tabs
            _line="${_line#"${_line%%[![:space:]]*}"}"   # ltrim

            [ -z "$_line" ] && continue

            # Section header
            if [[ "$_line" =~ ^\[([a-zA-Z_-]+)\]$ ]]; then
                _current_section="${BASH_REMATCH[1]}"
                continue
            fi

            # Must be a tuning line (contains pipe)
            [[ "$_line" == *"|"* ]] || continue
            [[ "$_line" == *"="* ]] || continue

            local _param; _param="${_line%%=*}"
            _param="${_param// /}"

            # Get the tier value
            local _new_val; _new_val=$(_tune_parse_value "$_line" "$_tier_idx")
            [ -z "$_new_val" ] && continue

            # ── nginx section: we CAN edit the file ──────────────────────
            if [ "$_current_section" = "nginx" ]; then
                local _nginx_conf="${_stack_dir}/nginx.conf"
                if [ ! -f "$_nginx_conf" ]; then
                    echo -e "    ${YEL}[nginx] nginx.conf not found at ${_nginx_conf} — skipping${NC}"
                    continue
                fi

                local _cur_val; _cur_val=$(_tune_read_nginx_value "$_nginx_conf" "$_param")
                local _tag="igor-managed"

                if [ "$_cur_val" = "$_new_val" ]; then
                    echo -e "    ${GRN}✔${NC} nginx/${_param}: ${_cur_val} (already correct)"
                    continue
                fi

                # Check if line is user-customized (no igor-managed tag)
                if grep -q "^[[:space:]]*${_param}[[:space:]]" "$_nginx_conf" 2>/dev/null \
                   && ! grep -q "^[[:space:]]*${_param}[[:space:]].*# igor-managed" "$_nginx_conf" 2>/dev/null; then
                    echo -e "    ${CYAN}↷${NC} nginx/${_param}: ${_cur_val:-unset} → ${_new_val}  ${YEL}(user-customized — skipping)${NC}"
                    continue
                fi

                echo -e "    ${YEL}~${NC} nginx/${_param}:"
                echo -e "      current:  ${_cur_val:-unset}"
                echo -e "      proposed: ${_new_val}  ${CYAN}(${_tier} tier)${NC}"
                _any_changes=true

                if ! $_dry_run; then
                    if confirm "    Apply nginx/${_param} = ${_new_val}?"; then
                        _tune_push_undo "$_nginx_conf" "tuning: nginx/${_param} before ${_tier} tier update"
                        if _tune_write_nginx_value "$_nginx_conf" "$_param" "$_new_val" "$_tier"; then
                            echo -e "    ${GRN}✔ Applied.${NC}"
                        else
                            echo -e "    ${YEL}⚠  Write skipped (user-customized line detected).${NC}"
                        fi
                    else
                        echo -e "    ${CYAN}Skipped.${NC}"
                    fi
                fi
                echo ""

            # ── All other sections: informational recommendations ─────────
            else
                echo -e "    ${CYAN}[${_current_section}]${NC} ${_param} = ${BOLD}${_new_val}${NC}  ${GRN}(${_tier} tier recommendation)${NC}"
            fi

        done < "$_tuning_conf"

        echo ""
    done

    if ! $_any_found; then
        if [ -n "$_target_module" ]; then
            echo -e "  ${YEL}No tuning.conf found for module: ${_target_module}${NC}"
        else
            echo -e "  ${YEL}No modules have a defaults/tuning.conf. Nothing to tune.${NC}"
        fi
    elif ! $_any_changes; then
        echo -e "  ${GRN}✔ All tunable values are already correct for the ${_tier} tier.${NC}"
    fi

    if $_dry_run && $_any_changes; then
        echo -e "  ${CYAN}(dry-run — no changes written)${NC}"
    fi

    echo ""
}
