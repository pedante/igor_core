#!/bin/bash
# ==============================================================================
#  IGOR — extras/load.sh
#  Plugin loader for optional feature modules.
#
#  Provides:
#    • load_extras() - Load all enabled optional features
#    • list_extras() - List available extras
#    • is_extra_enabled() - Check if an extra is enabled
#
#  Usage: Source this file and call load_extras()
# ==============================================================================

# ── Configuration ────────────────────────────────────────────────────────
EXTRAS_DIR="$(dirname "$0")"
CONFIG_FILE="${IGOR_DIR}/config.env"
EXTRAS_ENABLED_KEY="EXTRAS_ENABLED"

# ── Load enabled extras from config ────────────────────────────────────────
# Get comma-separated list of enabled extras.
get_enabled_extras() {
    grep "^${EXTRAS_ENABLED_KEY}=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- | tr ',' ' '
}

# Check if a specific extra is enabled.
is_extra_enabled() {
    local extra_name="$1"
    local enabled_extras=$(get_enabled_extras)

    for extra in $enabled_extras; do
        if [ "$extra" = "$extra" ]; then
            return 0
        fi
    done

    return 1
}

# ── List available extras ────────────────────────────────────────────────────
# Display all available extras and their status.
list_extras() {
    step "=== Available Extras ==="
    echo ""

    local found_extras=0
    local enabled_extras=$(get_enabled_extras)

    # Find all .sh files in extras directory
    for extra_file in "${EXTRAS_DIR}"/*.sh; do
        # Skip load.sh
        if [[ "$(basename "$extra_file")" = "load.sh" ]]; then
            continue
        fi

        # Skip if not a regular file
        [ -f "$extra_file" ] || continue

        local extra_name=$(basename "$extra_file" .sh)

        # Check if enabled
        if is_extra_enabled "$extra_name"; then
            ok "  [ENABLED] $extra_name"
        else
            info "  [DISABLED] $extra_name"
        fi

        found_extras=$((found_extras + 1))
    done

    if [ $found_extras -eq 0 ]; then
        warn "No extras found in ${EXTRAS_DIR}"
    fi

    echo ""
}

# ── Load extra source ────────────────────────────────────────────────────────
# Source an extra module if it exists and is enabled.
load_extra() {
    local extra_name="$1"
    local extra_file="${EXTRAS_DIR}/${extra_name}.sh"

    # Check if extra file exists
    if [ ! -f "$extra_file" ]; then
        warn "Extra not found: $extra_name"
        return 1
    fi

    # Source the extra file
    if ! source "$extra_file"; then
        fail "Failed to source extra: $extra_name"
        return 1
    fi

    step "Loaded extra: $extra_name"
    return 0
}

# ── Load all enabled extras ────────────────────────────────────────────────────
# Source all extras that are enabled in config.
load_extras() {
    local enabled_extras=$(get_enabled_extras)

    if [ -z "$enabled_extras" ]; then
        info "No extras enabled"
        return 0
    fi

    step "Loading enabled extras..."
    local loaded=0
    local failed=0

    for extra_name in $enabled_extras; do
        if load_extra "$extra_name"; then
            loaded=$((loaded + 1))
        else
            failed=$((failed + 1))
        fi
    done

    if [ $failed -gt 0 ]; then
        warn "Failed to load $failed extra(s)"
    else
        ok "Loaded $loaded extra(s)"
    fi

    return 0
}

# ── Export public functions ────────────────────────────────────────────────────────
export -f get_enabled_extras
export -f is_extra_enabled
export -f list_extras
export -f load_extra
export -f load_extras
