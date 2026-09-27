#!/usr/bin/env bats
# =============================================================================
#  tests/modules/test_module_conf.bats
#  Phase 3: module.conf structure validation — pure file parsing, no sourcing.
#
#  Every modules/*/module.conf must satisfy these structural rules so that
#  the module loader, menu system, and dependency resolver work correctly.
# =============================================================================

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."
MODULES_DIR="${REPO_DIR}/modules"

# ── Helper: list all module.conf files ────────────────────────────────────────
_all_module_confs() {
    find "$MODULES_DIR" -maxdepth 2 -name "module.conf" | sort
}

# ── Helper: get a field value from a module.conf ──────────────────────────────
_conf_get() {
    local file="$1" key="$2"
    grep -m1 "^${key}[[:space:]]*=" "$file" 2>/dev/null \
        | sed "s/^${key}[[:space:]]*=[[:space:]]*//"
}

_conf_is_v2() { [ "$(_conf_get "$1" module_api)" = 2 ]; }

setup() {
    # No tmpdir needed — reading repo files directly
    :
}

teardown() {
    :
}

# ══════════════════════════════════════════════════════════════════════════════
#  Structural presence checks (run once for all modules)
# ══════════════════════════════════════════════════════════════════════════════

@test "at least one module.conf exists in modules/" {
    local count
    count=$(find "$MODULES_DIR" -maxdepth 2 -name "module.conf" | wc -l)
    [ "$count" -gt 0 ]
}

# ══════════════════════════════════════════════════════════════════════════════
#  Per-module structural tests
# ══════════════════════════════════════════════════════════════════════════════

@test "each module.conf has a [module] section" {
    local conf
    while IFS= read -r conf; do
        grep -q "^\[module\]" "$conf" || fail "missing [module] section in $conf"
    done < <(_all_module_confs)
}

@test "each module.conf has a non-empty name= field" {
    local conf
    while IFS= read -r conf; do
        local name; name=$(_conf_get "$conf" "name")
        [ -n "$name" ] || fail "missing or empty name= in $conf"
    done < <(_all_module_confs)
}

@test "each module.conf has a version= field matching semver" {
    local conf
    while IFS= read -r conf; do
        local ver; ver=$(_conf_get "$conf" "version")
        [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
            || fail "version '${ver}' in $conf does not match semver (X.Y.Z)"
    done < <(_all_module_confs)
}

@test "v1 module.conf retains requires_core metadata" {
    local conf
    while IFS= read -r conf; do
        _conf_is_v2 "$conf" && continue
        grep -q "^requires_core[[:space:]]*=" "$conf" \
            || fail "missing requires_core= in $conf"
    done < <(_all_module_confs)
}

@test "each module.conf has a display_name= field" {
    local conf
    while IFS= read -r conf; do
        local dn; dn=$(_conf_get "$conf" "display_name")
        [ -n "$dn" ] || fail "missing or empty display_name= in $conf"
    done < <(_all_module_confs)
}

@test "v1 module.conf retains its dependencies section" {
    local conf
    while IFS= read -r conf; do
        _conf_is_v2 "$conf" && continue
        grep -q "^\[dependencies\]" "$conf" \
            || fail "missing [dependencies] section in $conf"
    done < <(_all_module_confs)
}

@test "each module.conf variables_file path exists in the repo" {
    local conf
    while IFS= read -r conf; do
        local vf; vf=$(_conf_get "$conf" "variables_file")
        # variables_file is optional — skip if not set
        [ -z "$vf" ] && continue
        [ -f "${REPO_DIR}/${vf}" ] \
            || fail "variables_file '${vf}' declared in $conf but not found at ${REPO_DIR}/${vf}"
    done < <(_all_module_confs)
}

@test "each module.conf module.sh file exists" {
    local conf
    while IFS= read -r conf; do
        local module_dir; module_dir="$(dirname "$conf")"
        [ -f "${module_dir}/module.sh" ] \
            || fail "module.sh missing for module at $module_dir"
    done < <(_all_module_confs)
}

@test "each module required_bins entry has no spaces (valid binary name)" {
    local conf
    while IFS= read -r conf; do
        local bins; bins=$(_conf_get "$conf" "required_bins")
        [ -z "$bins" ] && continue
        # required_bins is comma-separated; each entry must not contain spaces
        IFS=',' read -ra _bins_arr <<< "$bins"
        local b
        for b in "${_bins_arr[@]}"; do
            b="${b//[[:space:]]/}"   # strip whitespace
            # A binary name is just the first word before any : (optional_bins format)
            local bin_name="${b%%:*}"
            [[ "$bin_name" =~ ^[a-zA-Z0-9._-]+$ ]] \
                || fail "suspicious required_bin entry '${bin_name}' in $conf — may contain spaces or special chars"
        done
    done < <(_all_module_confs)
}

# ══════════════════════════════════════════════════════════════════════════════
#  Known module spot-checks
# ══════════════════════════════════════════════════════════════════════════════

@test "system module.conf: name is 'system'" {
    local conf="${MODULES_DIR}/system/module.conf"
    [ -f "$conf" ] || skip "system module not found"
    local name; name=$(_conf_get "$conf" "name")
    [ "$name" = "system" ]
}

@test "system module.conf: required_bins includes systemctl" {
    local conf="${MODULES_DIR}/system/module.conf"
    [ -f "$conf" ] || skip "system module not found"
    local bins; bins=$(_conf_get "$conf" "required_bins")
    [[ "$bins" == *"systemctl"* ]] || fail "systemctl not in required_bins: $bins"
}

@test "nextcloud_docker module.conf: name is 'nextcloud_docker'" {
    local conf="${MODULES_DIR}/nextcloud_docker/module.conf"
    [ -f "$conf" ] || skip "nextcloud_docker module not found"
    local name; name=$(_conf_get "$conf" "name")
    [ "$name" = "nextcloud_docker" ]
}

@test "nextcloud_docker module.conf: depends_on includes system" {
    local conf="${MODULES_DIR}/nextcloud_docker/module.conf"
    [ -f "$conf" ] || skip "nextcloud_docker module not found"
    local deps; deps=$(_conf_get "$conf" "depends_on")
    [[ "$deps" == *"system"* ]] || fail "nextcloud_docker does not depend on system: $deps"
}

@test "nextcloud_docker module.conf: menu_items is non-empty" {
    local conf="${MODULES_DIR}/nextcloud_docker/module.conf"
    [ -f "$conf" ] || skip "nextcloud_docker module not found"
    local items; items=$(_conf_get "$conf" "menu_items")
    [ -n "$items" ] || fail "menu_items is empty in $conf"
}

@test "nextcloud_docker module.conf: menu_items entries follow KEY:LABEL format" {
    local conf="${MODULES_DIR}/nextcloud_docker/module.conf"
    [ -f "$conf" ] || skip "nextcloud_docker module not found"
    local items; items=$(_conf_get "$conf" "menu_items")
    [ -z "$items" ] && skip "menu_items not set"
    IFS=',' read -ra _items_arr <<< "$items"
    local item
    for item in "${_items_arr[@]}"; do
        item="${item#"${item%%[! ]*}"}"  # ltrim
        [[ "$item" == *":"* ]] \
            || fail "menu_items entry '${item}' in $conf does not follow KEY:LABEL format"
    done
}
