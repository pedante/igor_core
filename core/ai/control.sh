#!/bin/bash
# The small administrator policy surface shared by discovery and dispatch.
_AI_CONTROL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ai_begin_request() {
    IGOR_AI_REQUEST_ID=$(python3 "${_AI_CONTROL_DIR}/operations.py" id) || return 1
    export IGOR_AI_REQUEST_ID
}

ai_private_text() {
    ai_export_privacy_map || return 1
    python3 "${_AI_CONTROL_DIR}/operations.py" scrub
}

ai_policy_tool_allowed() {
    [ "${IGOR_AI_ENABLED:-true}" = true ] || return 1
    local tool="$1" entry
    case "$tool" in
        execute|host_command) tool=host ;;
        occ_command) tool=occ ;;
        container_action) tool=container ;;
    esac
    local allowed="${IGOR_AI_ALLOWED_TOOLS-all}"
    [ "$allowed" = all ] && return 0
    for entry in ${allowed//,/ }; do
        [ "$entry" = "$tool" ] && return 0
    done
    return 1
}

ai_policy_action_allowed() {
    ai_policy_tool_allowed run_igor_action || return 1
    local name
    local disabled="${IGOR_AI_DISABLED_ACTIONS:-}"
    for name in ${disabled//,/ }; do
        [ "$name" = "$1" ] && return 1
    done
    return 0
}

ai_tool_available() {
    local tool="$1" capability=""
    ai_policy_tool_allowed "$tool" || return 1
    case "$tool" in
        occ) capability=nextcloud ;;
        container) capability=docker ;;
        # The legacy menu proposal writer has no default backend in core.
        propose_menu_item) [ -n "${items_dir:-}" ]; return $? ;;
    esac
    if [ -n "$capability" ]; then
        declare -f igor_has_capability >/dev/null 2>&1 &&
            igor_has_capability "$capability" && command -v docker >/dev/null 2>&1
        return $?
    fi
    return 0
}

ai_tool_owner() {
    local tool="$1" capability module provided owners=""
    case "$tool" in
        occ) capability=nextcloud ;;
        container) capability=docker ;;
        *) printf 'core'; return 0 ;;
    esac
    if declare -f igor_active_modules >/dev/null 2>&1; then
        for module in $(igor_active_modules); do
            provided=$(_ml_read_conf "${_IGOR_MODULE_DIRS[$module]}" provides)
            case " ${provided//,/ } " in
                *" $capability "*) owners+="${owners:+,}$module" ;;
            esac
        done
    fi
    printf '%s' "${owners:-unavailable}"
}

# Owner identifiers originate in the loader, never module prose or model output.
ai_catalog_json() {
    local name owner tier entry desc fn lazy problems menu
    {
        while IFS= read -r name; do
            ai_tool_available "$name" || continue
            # The canonical capability tool is emitted below from the active
            # executable v2 contribution index. Do not advertise an empty
            # generic tool when no provider is available.
            [ "$name" = run_capability ] && continue
            owner=$(ai_tool_owner "$name"); tier=READ
            case "$name" in
                host|occ) tier=classified ;;
                container|edit_file|propose_menu_item) tier=CHANGE ;;
                run_igor_action) tier=registered ;;
            esac
            printf '%s\0' tool "$name" "$owner" "$tier" ""
        done < <(python3 "${_AI_CONTROL_DIR}/catalog.py" names)
        if ai_tool_available run_capability &&
           declare -f igor_capability_list >/dev/null 2>&1 &&
           [ -f "${_AI_CONTROL_DIR%/ai}/lib/capability_runtime.py" ]; then
            # Keep owner, provider, descriptor and safety sourced from the
            # loader's active contribution index; model text never supplies
            # capability metadata. A composition has no leaf handler, so its
            # declared implementation can make it executable. The canonical
            # CapabilityRegistry resolves the complete index in one pass.
            igor_capability_list 2>/dev/null | python3 -c '
import json, sys
sys.path.insert(0, sys.argv[1])
from capability_runtime import CapabilityDescriptor, CapabilityRegistry

rows = json.load(sys.stdin)
registry = CapabilityRegistry()
valid = []
for row in rows:
    descriptor = row.get("descriptor") or {}
    if descriptor.get("kind") != "capability":
        continue
    descriptor = dict(descriptor)
    for field in ("owner", "provider", "source"):
        if field in row:
            descriptor[field] = row[field]
    descriptor["active"] = row.get("availability") == "active"
    if row.get("unavailable_reason"):
        descriptor["unavailable_reason"] = row["unavailable_reason"]
    try:
        registry.register(CapabilityDescriptor.from_dict(descriptor))
        valid.append((row, descriptor))
    except (TypeError, ValueError):
        continue

for row, descriptor in valid:
    implementation = descriptor.get("implementation") or {}
    if (row.get("availability") != "active" or
            not (descriptor.get("handler") or
                 implementation.get("kind") == "composition") or
            descriptor.get("safety", {}).get("tier") not in {"READ", "CHANGE", "DESTROY"}):
        continue
    ident = descriptor.get("id", row.get("id", ""))
    provider = row.get("provider", row.get("owner", ""))
    resolution = registry.resolve(ident)
    if resolution.status != "available" or resolution.selected_provider != provider:
        continue
    sys.stdout.write("%s\0%s\0%s\0%s\0%s\0" % (
        ident, provider,
        descriptor.get("safety", {}).get("tier", ""),
        "composition" if implementation.get("kind") == "composition" else "leaf",
        json.dumps({
            "provider": provider,
            "owner": row.get("owner", ""),
            "description": descriptor.get("description", ""),
            "descriptor": descriptor,
        }, sort_keys=True, separators=(",", ":"))))
' "${_AI_CONTROL_DIR%/ai}/lib" | while IFS= read -r -d '' ident &&
              IFS= read -r -d '' provider &&
              IFS= read -r -d '' tier &&
              IFS= read -r -d '' kind &&
              IFS= read -r -d '' metadata; do
                # Preparing a composition performs only canonical resolution,
                # input validation and plan construction. It rejects missing
                # child capabilities/platform variants without authorizing or
                # executing any step.
                if [ "$kind" = composition ]; then
                    declare -f igor_capability_prepare >/dev/null 2>&1 || continue
                    igor_capability_prepare "$ident" '{}' "$provider" >/dev/null 2>&1 || continue
                fi
                printf '%s\0' capability "$ident" "$provider" "$tier" "$metadata"
            done
        fi
        if declare -p _IGOR_CAPABILITIES >/dev/null 2>&1; then
            for name in "${!_IGOR_CAPABILITIES[@]}"; do
                ai_policy_action_allowed "$name" || continue
                owner="${_IGOR_CAPABILITY_OWNERS[$name]:-}"
                [ -n "$owner" ] && _ml_owner_active "$owner" || continue
                entry="${_IGOR_CAPABILITIES[$name]}"
                IFS='|' read -r desc fn lazy tier problems menu <<< "$entry"
                printf '%s\0' action "$name" "$owner" "$tier" "$desc"
            done
        fi
    } | python3 "${_AI_CONTROL_DIR}/catalog.py" build
}

# Export only the existing reversible mapping, never the full shell environment.
ai_export_privacy_map() {
    local i
    IGOR_AI_SCRUB_MAP=$(
        for i in "${!SCRUB_FROM[@]}"; do
            printf '%s\0%s\0' "${SCRUB_FROM[$i]}" "${SCRUB_TO[$i]}"
        done | IGOR_AI_PRIVACY_DIR="$_AI_CONTROL_DIR" python3 -c 'import sys,json,os
sys.path.insert(0,os.environ["IGOR_AI_PRIVACY_DIR"])
from privacy import sanitize_selected_text
a=sys.stdin.read().split("\0")
print(json.dumps({key:value for key,value in zip(a[::2],a[1::2]) if key and sanitize_selected_text(key)==key}))'
    ) || { unset IGOR_AI_SCRUB_MAP; return 1; }
    export IGOR_AI_SCRUB_MAP
}

# Fixed event fields: event tool tier approval outcome exit owner args result id.
# Called at authoritative dispatcher transitions, never from model assertions.
ai_audit_tool() {
    [ "${IGOR_AI_AUDIT:-metadata}" = off ] && return 0
    ai_export_privacy_map || return 0
    local -a values=("$@")
    [ -n "${values[6]:-}" ] || values[6]=$(ai_tool_owner "${values[1]:-unknown}")
    if declare -f ai_scrub_outbound >/dev/null 2>&1; then
        values[7]=$(ai_scrub_outbound "${values[7]:-}") || values[7]='[scrubbing failed]'
        values[8]=$(ai_scrub_outbound "${values[8]:-}") || values[8]='[scrubbing failed]'
    fi
    printf '%s\0' "${values[@]}" | python3 "${_AI_CONTROL_DIR}/operations.py" tool ||
        printf 'AI operation could not be recorded.\n' >&2
    return 0
}
