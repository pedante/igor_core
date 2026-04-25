#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/menus/setup_infra.sh
#  Setup and Infrastructure menu for Nextcloud Docker module
# ==============================================================================

# ── Module helpers (prefixed with _mod_nextcloud_setup_) ────────────────────

_mod_nextcloud_setup_wizard() {
    step "Setup Wizard"
    
    local _mod_dir _root _stacks _stack
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    _stack="${_stacks}/nextcloud"
    
    echo "  Nextcloud Docker Setup Wizard"
    echo "  =================================="
    echo ""
    echo "  This wizard will guide you through the initial setup process:"
    echo ""
    echo "  1. Stack directory creation"
    echo "  2. Configuration file generation"
    echo "  3. Service preparation"
    echo ""
    
    if [ ! -d "$_stack" ]; then
        echo "  Stack directory does not exist: $_stack"
        if confirm "Create stack directory and copy defaults?"; then
            if command -v nextcloud_docker__install >/dev/null; then
                nextcloud_docker__install
                ok "Stack directory created and configured"
            else
                warn "Install function not available - manual setup required"
            fi
        else
            info "Setup cancelled"
        fi
    else
        echo "  ✓ Stack directory exists: $_stack"
    fi
    
    pause
}

_mod_nextcloud_initialize_config() {
    step "Initialize Configuration"
    
    local _mod_dir _root _stacks _stack
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    _stack="${_stacks}/nextcloud"
    
    echo "  Configuration initialization..."
    
    # Check for required environment files
    local required_files=("${_root}/nextcloud.env" "${_root}/secrets/db.env")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        else
            echo "  ✓ Found: $file"
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        echo "  ✗ Missing configuration files:"
        for missing in "${missing_files[@]}"; do
            echo "    - $missing"
        done
        echo ""
        echo "  These files should be created before running services"
        echo "  Template files may be available in defaults/ directory"
    fi
    
    pause
}

_mod_nextcloud_validate_setup() {
    step "Validate Setup"
    
    local _mod_dir _root _stacks _stack
    _mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    _root="${IGOR_DIR:-$(cd "${_mod_dir}/../.." && pwd)}"
    _stacks="${IGOR_STACKS:-${_root}/config/stacks}"
    _stack="${_stacks}/nextcloud"
    
    local validation_passed=true
    local checks=()
    
    # Check stack directory
    if [ -d "$_stack" ]; then
        checks+=("✓ Stack directory exists")
    else
        checks+=("✗ Stack directory missing")
        validation_passed=false
    fi
    
    # Check compose file
    if [ -f "${_stack}/docker-compose.yml" ]; then
        checks+=("✓ Docker compose file exists")
    else
        checks+=("✗ Docker compose file missing")
        validation_passed=false
    fi
    
    # Check nginx config
    if [ -f "${_stack}/nginx.conf" ]; then
        checks+=("✓ Nginx configuration exists")
    else
        checks+=("✗ Nginx configuration missing")
        validation_passed=false
    fi
    
    # Check environment files
    if [ -f "${_root}/nextcloud.env" ]; then
        checks+=("✓ Environment file exists")
    else
        checks+=("⚠ Environment file missing - will be created")
    fi
    
    if [ -f "${_root}/secrets/db.env" ]; then
        checks+=("✓ Secrets file exists")
    else
        checks+=("⚠ Secrets file missing - will be created")
    fi
    
    # Check Docker
    if command -v docker &>/dev/null; then
        checks+=("✓ Docker is available")
    else
        checks+=("✗ Docker not installed")
        validation_passed=false
    fi
    
    echo "  Setup validation results:"
    for check in "${checks[@]}"; do
        echo "    $check"
    done
    
    echo ""
    if $validation_passed; then
        ok "Setup validation passed - ready to start services"
    else
        warn "Setup validation failed - missing components"
        echo "  Run the setup wizard and initialization first"
    fi
    
    pause
}

_mod_nextcloud_system_readiness() {
    step "System Readiness Check"
    
    echo "  System readiness assessment..."
    
    local system_checks=()
    
    # Check available disk space
    local disk_space
    disk_space=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//')
    if [ "$disk_space" -lt 90 ]; then
        system_checks+=("✓ Disk space: ${disk_space}% used")
    else
        system_checks+=("⚠ Disk space: ${disk_space}% used (getting full)")
    fi
    
    # Check available memory
    local mem_available
    if command -v free &>/dev/null; then
        mem_available=$(free -m | awk 'NR==2{printf "%.0f", $7/$2 * 100.0}')
        if [ "$mem_available" -gt 10 ]; then
            system_checks+=("✓ Available memory: ${mem_available}%")
        else
            system_checks+=("⚠ Low memory: ${mem_available}% available")
        fi
    fi
    
    # Check swap
    if command -v swapon &>/dev/null; then
        local swap_total
        swap_total=$(swapon --show | tail -n +2 | awk '{total += $3} END {print total}')
        if [ -n "$swap_total" ] && [ "$swap_total" -gt 0 ]; then
            system_checks+=("✓ Swap available: ${swap_total}MB")
        else
            system_checks+=("⚠ No swap configured (recommended for Pi 3)")
        fi
    fi
    
    # Check required ports
    local ports_in_use=()
    for port in 8080 5432 6379; do
        if netstat -ln 2>/dev/null | grep -q ":$port "; then
            ports_in_use+=("Port $port")
        fi
    done
    
    if [ ${#ports_in_use[@]} -eq 0 ]; then
        system_checks+=("✓ Required ports available (8080, 5432, 6379)")
    else
        system_checks+=("⚠ Ports already in use: ${ports_in_use[*]}")
    fi
    
    echo "  System status:"
    for check in "${system_checks[@]}"; do
        echo "    $check"
    done
    
    pause
}

# ── Public entry point ───────────────────────────────────────────────────────────

menu_setup_infra() {
    while true; do
        if declare -f igor_right_render &>/dev/null; then
            local _dc_v _sys_swap _sys_mem
            _dc_v=$(docker --version 2>/dev/null | grep -o 'version [^ ,]*' | head -1 || echo "not installed")
            _sys_swap=$(free -h 2>/dev/null | awk 'NR==3{print $2}' || echo "?")
            _sys_mem=$(free -h 2>/dev/null | awk 'NR==2{print $3"/"$2}' || echo "?")
            igor_right_render "Setup & Infrastructure" \
                "Docker"  "${_dc_v}" \
                "Memory"  "${_sys_mem}" \
                "Swap"    "${_sys_swap}" \
                "---"     "Quick actions" \
                "hint"    "[0]  WIZARD" \
                "hint"    "[4]  START STACK" \
                "hint"    "[6]  RESET STACK" \
                "hint"    "[8]  ADOPT EXISTING" \
                "hint"    "[b]  BACK"
        fi
        local _opt
        _opt=$(igor_fzf_pick "S: Setup & Install" \
            "_:  FIRST TIME SETUP  :" \
            "0:WIZARD:Guided first-run installation — start here" \
            "_:  PREREQUISITES  :" \
            "2:STORAGE:Mount point, data dir, fstab nofail entry" \
            "3:TUNNEL:Cloudflare tunnel setup and token configuration" \
            "_:  STACK OPERATIONS  :" \
            "4:START STACK:Start services using existing volumes and data" \
            "5:START FRESH:Full reinstall — new volumes, wipe app data" \
            "6:RESET STACK:Destroy containers + volumes, keep user files" \
            "7:ORPHAN CLEANUP:Find and remove orphaned volumes/containers" \
            "8:ADOPT EXISTING:Import a Nextcloud stack into Igor management" \
            "9:SATELLITES:Enable OnlyOffice, Immich, Collabora, COTURN" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        breadcrumb "Igor" "S: Setup & Install"
        echo -e "  ${YEL}${BOLD}[S] Setup & Install${NC}"
        echo ""
        echo -e "  ${DIM}── First Time Setup ───────────────────────────────${NC}"
        echo -e "  ${CYAN}0.${NC} WIZARD        — Guided first-run installation (start here)"
        echo ""
        echo -e "  ${DIM}── Prerequisites ──────────────────────────────────${NC}"
        echo -e "  ${CYAN}2.${NC} STORAGE       — Mount point, data dir, fstab nofail entry"
        echo -e "  ${CYAN}3.${NC} TUNNEL        — Cloudflare tunnel setup and token configuration"
        echo ""
        echo -e "  ${DIM}── Stack Operations ───────────────────────────────${NC}"
        echo -e "  ${CYAN}4.${NC} START STACK   — Start services using existing volumes and data"
        echo -e "  ${CYAN}5.${NC} START FRESH   — Full reinstall: new volumes, wipe app data"
        echo -e "  ${CYAN}6.${NC} RESET STACK   — Destroy containers + volumes, keep user files"
        echo -e "  ${CYAN}7.${NC} ORPHAN CLEANUP — Find and remove orphaned volumes/containers"
        echo -e "  ${CYAN}8.${NC} ADOPT EXISTING — Import a Nextcloud stack into Igor management"
        echo -e "  ${CYAN}9.${NC} SATELLITES    — Enable OnlyOffice, Immich, Collabora, COTURN"
        echo ""
        echo -e "  ${CYAN}b.${NC} Back"
        echo ""
        read -rp "  Select: " _opt ;; esac
        [ "$_opt" = "_" ] && continue
        case "$_opt" in
            0) _igor_load_module "install"; menu_install ;;
            2) _igor_load_module "storage"; menu_storage ;;
            3) _igor_load_module "tunnel"; menu_tunnel ;;
            4) _igor_load_module "install"; _mod_setup_start_stack ;;
            5) _igor_load_module "install"; _mod_setup_start_fresh ;;
            6) _igor_load_module "install"; _mod_setup_reset_stack ;;
            7) _igor_load_module "install"; _mod_setup_orphan_cleanup ;;
            8) _igor_load_module "install"; _mod_setup_migrate ;;
            9) source "$(dirname "${BASH_SOURCE[0]}")/satellite_menu.sh"; menu_satellites ;;
            b|B|q|Q) return ;;
        esac
    done
}