#!/bin/bash
# =============================================================================
#  IGOR — scripts/validate_module.sh
#  Comprehensive module validation and inspection tool
# =============================================================================

set -euo pipefail

# Source Igor core for access to validation functions
IGOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${IGOR_DIR}/igor.sh" --help >/dev/null 2>&1 || true

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Usage information
usage() {
    cat << 'EOF'
IGOR Module Validation Tool

USAGE:
    ./validate_module.sh <MODULE_NAME> [COMMAND]

COMMANDS:
    config        Validate module.conf configuration
    registration  Validate hook and menu registration
    dependencies  Check module and binary dependencies  
    hooks         List all registered hooks for the module
    menu-items    List all menu items for the module
    ai-tools      List AI tools provided by the module
    ai-knowledge  List AI knowledge provided by the module
    ai-patterns   List AI patterns provided by the module
    config-files  List configuration files provided by the module
    health-checks List health checks provided by the module
    env-files     List environment files used by the module
    patterns      List fix patterns provided by the module
    knowledge     List knowledge base files
    runbooks      List runbook files
    test-hooks    Test individual hooks in isolation
    health        Run module health checks
    full          Run all validation (default)

EXAMPLES:
    ./validate_module.sh nextcloud_docker full
    ./validate_module.sh system hooks
    ./validate_module.sh my_module ai-tools
    ./validate_module.sh my_module config-files

EOF
}

# Module configuration validation
validate_module_conf() {
    local module_name="$1"
    local module_dir="${IGOR_DIR}/modules/${module_name}"
    local conf_file="${module_dir}/module.conf"
    
    echo -e "${BLUE}=== Module Configuration Validation ===${NC}"
    
    if [ ! -f "$conf_file" ]; then
        echo -e "${RED}✗ module.conf not found${NC}"
        return 1
    fi
    
    # Check required fields
    local required_fields=("name" "display_name" "version" "description" "requires_core")
    local missing_fields=()
    
    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}[[:space:]]*=" "$conf_file"; then
            missing_fields+=("$field")
        fi
    done
    
    if [ ${#missing_fields[@]} -gt 0 ]; then
        echo -e "${RED}✗ Missing required fields: ${missing_fields[*]}${NC}"
        return 1
    fi
    
    # Check syntax (basic INI format validation)
    if ! grep -q "^\[module\]" "$conf_file"; then
        echo -e "${RED}✗ Missing [module] section in module.conf${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Module configuration is valid${NC}"
    
    # Show complete configuration summary
    echo "  ${CYAN}Basic Information:${NC}"
    local name version display_name description requires_core depends_on
    name=$(grep "^name=" "$conf_file" | cut -d= -f2 | tr -d ' ')
    version=$(grep "^version=" "$conf_file" | cut -d= -f2 | tr -d ' ')
    display_name=$(grep "^display_name=" "$conf_file" | cut -d= -f2 | tr -d ' ')
    description=$(grep "^description=" "$conf_file" | cut -d= -f2 | tr -d ' ')
    requires_core=$(grep "^requires_core=" "$conf_file" | cut -d= -f2 | tr -d ' ')
    depends_on=$(grep "^depends_on=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    
    echo "    Name: $name"
    echo "    Display: $display_name"
    echo "    Version: $version"
    echo "    Description: $description"
    echo "    Core Required: $requires_core"
    echo "    Depends On: $depends_on"
    
    echo "  ${CYAN}Menu Configuration:${NC}"
    local menu_section menu_priority menu_items
    menu_section=$(grep "^menu_section=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    menu_priority=$(grep "^menu_priority=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    menu_items=$(grep "^menu_items=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    
    echo "    Section: $menu_section"
    echo "    Priority: $menu_priority"
    echo "    Items: $menu_items"
    
    echo "  ${CYAN}Stack Configuration:${NC}"
    local stack_dir compose_file compose_project_name
    stack_dir=$(grep "^stack_dir=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    compose_file=$(grep "^compose_file=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    compose_project_name=$(grep "^compose_project_name=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    
    if [ "$stack_dir" != "none" ]; then
        echo "    Stack Directory: $stack_dir"
        echo "    Compose File: $compose_file"
        echo "    Project Name: $compose_project_name"
    else
        echo "    No stack configuration"
    fi
    
    echo "  ${CYAN}Environment Files:${NC}"
    local variables_file secrets_files
    variables_file=$(grep "^variables_file=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    secrets_files=$(grep "^secrets_files=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    
    echo "    Variables File: $variables_file"
    echo "    Secrets Files: $secrets_files"
    
    echo "  ${CYAN}Security Configuration:${NC}"
    local variables scrub_patterns
    variables=$(grep "^variables=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    scrub_patterns=$(grep "^scrub_patterns=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    
    echo "    Secret Variables: $variables"
    echo "    Scrub Patterns: $scrub_patterns"
    
    echo "  ${CYAN}Panels:${NC}"
    local panels_lines
    panels_lines=$(grep "^panels=" "$conf_file" || echo "none")
    if [ "$panels_lines" != "none" ]; then
        echo "    Available panels:"
        while IFS= read -r line; do
            if [[ $line =~ ^panels= ]]; then
                local panel_content="${line#panels=}"
                IFS=':' read -r panel_cmd panel_desc <<< "$panel_content"
                echo "      ${GREEN}✓${NC} $panel_cmd: $panel_desc"
            fi
        done <<< "$panels_lines"
    else
        echo "    No panels defined"
    fi
    
    echo "  ${CYAN}Dependencies:${NC}"
    local required_bins optional_bins required_modules optional_modules
    required_bins=$(grep "^required_bins=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    optional_bins=$(grep "^optional_bins=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    required_modules=$(grep "^required_modules=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    optional_modules=$(grep "^optional_modules=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
    
    echo "    Required Binaries: $required_bins"
    echo "    Optional Binaries: $optional_bins"
    echo "    Required Modules: $required_modules"
    echo "    Optional Modules: $optional_modules"
}

# Registration validation
validate_registration() {
    local module_name="$1"
    
    echo -e "${BLUE}=== Hook and Menu Registration Validation ===${NC}"
    
    # Check if module is loaded
    if ! igor_has_module "$module_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Module $module_name is not currently loaded${NC}"
        echo "  Load it first with: source ${IGOR_DIR}/igor.sh"
        return 1
    fi
    
    # Check registered hooks
    local hook_found=false
    local all_hooks=("health" "diagnose" "notify" "mailcmd" "ai_context" "ai_tools" 
                   "ai_tiers" "ai_patterns" "ai_knowledge" "recovery" "status_line" "app_diagnose")
    
    for hook in "${all_hooks[@]}"; do
        local hook_functions
        hook_functions=$(igor_get_hooks "$hook" 2>/dev/null || echo "")
        if echo "$hook_functions" | grep -q "${module_name}__${hook}"; then
            echo -e "${GREEN}✓ $hook hook: ${module_name}__${hook}${NC}"
            hook_found=true
        fi
    done
    
    if ! $hook_found; then
        echo -e "${YELLOW}⚠ No hooks registered for module $module_name${NC}"
    fi
    
    # Check menu items
    if declare -p _IGOR_MENU_REGISTRY &>/dev/null; then
        local menu_items_found=false
        for key in "${!_IGOR_MENU_REGISTRY[@]}"; do
            local entry="${_IGOR_MENU_REGISTRY[$key]}"
            if [[ "$entry" == *"$module_name"* ]]; then
                echo -e "${GREEN}✓ Menu item: $key → $entry${NC}"
                menu_items_found=true
            fi
        done
        
        if ! $menu_items_found; then
            echo -e "${YELLOW}⚠ No menu items registered for module $module_name${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Menu registry not available${NC}"
    fi
}

# Dependency validation
validate_dependencies() {
    local module_name="$1"
    local module_dir="${IGOR_DIR}/modules/${module_name}"
    
    echo -e "${BLUE}=== Dependency Validation ===${NC}"
    
    if [ ! -d "$module_dir" ]; then
        echo -e "${RED}✗ Module directory not found: $module_dir${NC}"
        return 1
    fi
    
    # Source the module loader to get dependency checking functions
    source "${IGOR_DIR}/core/lib/module_loader.sh" 2>/dev/null || {
        echo -e "${RED}✗ Cannot source module loader${NC}"
        return 1
    }
    
    # Check dependencies
    if _ml_check_dependencies "$module_dir" "$module_name"; then
        echo -e "${GREEN}✓ All dependencies satisfied${NC}"
    else
        echo -e "${RED}✗ Dependency check failed${NC}"
        return 1
    fi
}

# Hook inspection
inspect_hooks() {
    local module_name="$1"
    
    echo -e "${BLUE}=== Registered Hooks for $module_name ===${NC}"
    
    if ! igor_has_module "$module_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Module $module_name is not loaded${NC}"
        return 1
    fi
    
    local hooks_found=false
    local all_hooks=("health" "diagnose" "notify" "mailcmd" "ai_context" "ai_tools" 
                   "ai_tiers" "ai_patterns" "ai_knowledge" "recovery" "status_line" "app_diagnose")
    
    for hook in "${all_hooks[@]}"; do
        local hook_functions
        hook_functions=$(igor_get_hooks "$hook" 2>/dev/null || echo "")
        if echo "$hook_functions" | grep -q "${module_name}__${hook}"; then
            echo "  $hook: ${module_name}__${hook}"
            hooks_found=true
            
            # Show if the function exists and is callable
            if declare -f "${module_name}__${hook}" >/dev/null; then
                echo "    Status: $(echo -e "${GREEN}✓${NC}") Implemented"
            else
                echo "    Status: $(echo -e "${RED}✗${NC}") Function not found"
            fi
        fi
    done
    
    if ! $hooks_found; then
        echo "  ${YELLOW}No hooks found for module $module_name${NC}"
    fi
}

# Menu item inspection  
inspect_menu_items() {
    local module_name="$1"
    
    echo -e "${BLUE}=== Menu Items for $module_name ===${NC}"
    
    # Check module.conf for menu_items
    local module_dir="${IGOR_DIR}/modules/${module_name}"
    local conf_file="${module_dir}/module.conf"
    
    # Source module files to check for menu functions
    if [ -d "$module_dir" ]; then
        # Source all .sh files in the module directory
        for sh_file in "${module_dir}"/*.sh; do
            if [ -f "$sh_file" ] && [[ "$sh_file" != *.conf ]]; then
                source "$sh_file" 2>/dev/null || true
            fi
        done
    fi
    
    if [ -f "$conf_file" ]; then
        local menu_items
        menu_items=$(grep "^menu_items=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "none")
        if [ "$menu_items" != "none" ]; then
            echo "  Configuration-defined menu items: $menu_items"
            
            # Check if corresponding menu functions exist
            local IFS=','
            for item in $menu_items; do
                local key="${item%%:*}"
                local label="${item#*:}"
                local func_name="menu_$(echo "$label" | tr '[:upper:]' '[:lower:]' | tr '[:space:]/&' '_')"
                if declare -f "$func_name" >/dev/null; then
                    echo "    $key: $label → $func_name ${GREEN}✓${NC}"
                else
                    echo "    $key: $label → $func_name ${RED}✗ Missing${NC}"
                fi
            done
        fi
    fi
    
    # Check manual registration
    if declare -p _IGOR_MENU_REGISTRY &>/dev/null; then
        local manual_found=false
        for key in "${!_IGOR_MENU_REGISTRY[@]}"; do
            local entry="${_IGOR_MENU_REGISTRY[$key]}"
            if [[ "$entry" == *"$module_name"* ]]; then
                echo "  Manually registered menu item: $key → $entry"
                manual_found=true
            fi
        done
        
        if ! $manual_found; then
            echo "  ${YELLOW}No manually registered menu items${NC}"
        fi
    fi
}

# AI Tools inspection
inspect_ai_tools() {
    local module_name="$1"
    local module_dir="${IGOR_DIR}/modules/${module_name}"
    
    echo -e "${BLUE}=== AI Tools for $module_name ===${NC}"
    
    # Check if module has ai_tools hook
    if ! igor_has_module "$module_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Module $module_name is not loaded${NC}"
        return 1
    fi
    
    local hook_functions
    hook_functions=$(igor_get_hooks "ai_tools" 2>/dev/null || echo "")
    if echo "$hook_functions" | grep -q "${module_name}__ai_tools"; then
        local tools_func="${module_name}__ai_tools"
        if declare -f "$tools_func" >/dev/null; then
            echo "  ${GREEN}✓ AI tools function implemented${NC}"
            echo "  Tools provided:"
            local tools_output
            tools_output=$("$tools_func" 2>/dev/null || echo "Error getting tools")
            if [ -n "$tools_output" ]; then
                # Try to parse as JSON and display nicely
                if command -v python3 &>/dev/null; then
                    echo "$tools_output" | python3 -c '
import sys, json
try:
    tools = json.loads(sys.stdin.read())
    if isinstance(tools, list):
        for tool in tools:
            name = tool.get("name", "unknown")
            desc = tool.get("description", "no description")
            tier = tool.get("tier", "unknown")
            print(f"    - {name} ({tier}): {desc[:80]}...")
                    else:
                        print("    (Output is not a JSON list)")
except:
    print("    (Could not parse as JSON)")
' 2>/dev/null || echo "    $tools_output"
                else
                    echo "    $tools_output"
                fi
            fi
        else
            echo "  ${RED}✗ AI tools function not found${NC}"
        fi
    else
        echo "  ${YELLOW}No AI tools registered${NC}"
    fi
}

# AI Knowledge inspection
inspect_ai_knowledge() {
    local module_name="$1"
    local module_dir="${IGOR_DIR}/modules/${module_name}"
    
    echo -e "${BLUE}=== AI Knowledge for $module_name ===${NC}"
    
    # Check if module has ai_knowledge hook
    if ! igor_has_module "$module_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Module $module_name is not loaded${NC}"
        return 1
    fi
    
    echo "  Hook-based knowledge:"
    local hook_functions
    hook_functions=$(igor_get_hooks "ai_knowledge" 2>/dev/null || echo "")
    if echo "$hook_functions" | grep -q "${module_name}__ai_knowledge"; then
        local knowledge_func="${module_name}__ai_knowledge"
        if declare -f "$knowledge_func" >/dev/null; then
            echo "    ${GREEN}✓ AI knowledge function implemented${NC}"
        else
            echo "    ${RED}✗ AI knowledge function not found${NC}"
        fi
    else
        echo "    ${YELLOW}No AI knowledge hook registered${NC}"
    fi
    
    # Check knowledge directory
    local knowledge_dir="${module_dir}/knowledge"
    if [ -d "$knowledge_dir" ]; then
        echo "  Knowledge files:"
        for knowledge_file in "${knowledge_dir}"/*.md; do
            [ -f "$knowledge_file" ] || continue
            echo "    ${GREEN}✓$(basename "$knowledge_file")${NC}"
        done
    else
        echo "  ${YELLOW}No knowledge directory found${NC}"
    fi
}

# AI Patterns inspection
inspect_ai_patterns() {
    local module_name="$1"
    local module_dir="${IGOR_DIR}/modules/${module_name}"
    
    echo -e "${BLUE}=== AI Patterns for $module_name ===${NC}"
    
    # Check if module has ai_patterns hook
    if ! igor_has_module "$module_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Module $module_name is not loaded${NC}"
        return 1
    fi
    
    echo "  Hook-based patterns:"
    local hook_functions
    hook_functions=$(igor_get_hooks "ai_patterns" 2>/dev/null || echo "")
    if echo "$hook_functions" | grep -q "${module_name}__ai_patterns"; then
        local patterns_func="${module_name}__ai_patterns"
        if declare -f "$patterns_func" >/dev/null; then
            echo "    ${GREEN}✓ AI patterns function implemented${NC}"
            echo "    Static patterns:"
            local patterns_output
            patterns_output=$("$patterns_func" 2>/dev/null || echo "Error getting patterns")
            if [ -n "$patterns_output" ]; then
                echo "$patterns_output" | grep "PATTERN:" | sed 's/^/      /' || echo "      $patterns_output"
            fi
        else
            echo "    ${RED}✗ AI patterns function not found${NC}"
        fi
    else
        echo "    ${YELLOW}No AI patterns hook registered${NC}"
    fi
    
    # Check patterns directory
    local patterns_dir="${module_dir}/patterns"
    if [ -d "$patterns_dir" ]; then
        echo "  Pattern files:"
        for pattern_file in "${patterns_dir}"/*.txt "${patterns_dir}"/*.pattern; do
            [ -f "$pattern_file" ] || continue
            echo "    $(echo -e "${GREEN}✓${NC}")$(basename "$pattern_file")"
        done
    else
        echo "  ${YELLOW}No patterns directory found${NC}"
    fi
}

# Configuration files inspection
inspect_config_files() {
    local module_name="$1"
    local module_dir="${IGOR_DIR}/modules/${module_name}"
    
    echo -e "${BLUE}=== Configuration Files for $module_name ===${NC}"
    
    # Check defaults directory
    local defaults_dir="${module_dir}/defaults"
    if [ -d "$defaults_dir" ]; then
        echo "  Default configuration files:"
        for config_file in "${defaults_dir}"/*; do
            [ -f "$config_file" ] || continue
            local file_size
            file_size=$(wc -l < "$config_file" 2>/dev/null || echo "unknown")
            echo "    ${GREEN}✓$(basename "$config_file")${NC} ($file_size lines)"
        done
    else
        echo "  ${YELLOW}No defaults directory found${NC}"
    fi
    
    # Check stack directory usage
    local conf_file="${module_dir}/module.conf"
    if [ -f "$conf_file" ]; then
        local stack_dir
        stack_dir=$(grep "^stack_dir=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "")
        if [ -n "$stack_dir" ]; then
            local actual_stack="${IGOR_STACKS:-${IGOR_DIR}/config/stacks}/${stack_dir}"
            if [ -d "$actual_stack" ]; then
                echo "  Stack directory exists: ${GREEN}$actual_stack${NC}"
                echo "  Stack files:"
                for stack_file in "${actual_stack}"/*; do
                    [ -f "$stack_file" ] || continue
                    echo "    ${GREEN}✓$(basename "$stack_file")${NC}"
                done
            else
                echo "  Stack directory not found: ${YELLOW}$actual_stack${NC}"
            fi
        fi
    fi
}

# Health checks inspection
inspect_health_checks() {
    local module_name="$1"
    local module_dir="${IGOR_DIR}/modules/${module_name}"
    
    echo -e "${BLUE}=== Health Checks for $module_name ===${NC}"
    
    # Check if module has health hook
    if ! igor_has_module "$module_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Module $module_name is not loaded${NC}"
        return 1
    fi
    
    echo "  Hook-based health check:"
    local hook_functions
    hook_functions=$(igor_get_hooks "health" 2>/dev/null || echo "")
    if echo "$hook_functions" | grep -q "${module_name}__health"; then
        local health_func="${module_name}__health"
        if declare -f "$health_func" >/dev/null; then
            echo "    ${GREEN}✓ Health function implemented${NC}"
            local health_output
            health_output=$("$health_func" 2>/dev/null || echo "Error getting health status")
            echo "    Status: $health_output"
        else
            echo "    ${RED}✗ Health function not found${NC}"
        fi
    else
        echo "    ${YELLOW}No health hook registered${NC}"
    fi
    
    # Check checks directory
    local checks_dir="${module_dir}/checks"
    if [ -d "$checks_dir" ]; then
        echo "  Health check files:"
        for check_file in "${checks_dir}"/*.sh; do
            [ -f "$check_file" ] || continue
            echo "    ${GREEN}✓$(basename "$check_file")${NC}"
        done
    else
        echo "  ${YELLOW}No checks directory found${NC}"
    fi
}

# Environment files inspection
inspect_env_files() {
    local module_name="$1"
    local module_dir="${IGOR_DIR}/modules/${module_name}"
    
    echo -e "${BLUE}=== Environment Files for $module_name ===${NC}"
    
    # Check module.conf for environment file references
    local conf_file="${module_dir}/module.conf"
    if [ -f "$conf_file" ]; then
        local variables_file
        variables_file=$(grep "^variables_file=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "")
        local secrets_files
        secrets_files=$(grep "^secrets_files=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "")
        
        if [ -n "$variables_file" ]; then
            local var_path="${IGOR_DIR}/${variables_file}"
            if [ -f "$var_path" ]; then
                echo "  ${GREEN}✓ Variables file: $var_path${NC}"
            else
                echo "  ${YELLOW}⚠ Variables file not found: $var_path${NC}"
            fi
        fi
        
        if [ -n "$secrets_files" ]; then
            IFS=','
            for secret_file in $secrets_files; do
                secret_file=$(echo "$secret_file" | tr -d ' ')
                local secret_path="${IGOR_DIR}/${secret_file}"
                if [ -f "$secret_path" ]; then
                    echo "  ${GREEN}✓ Secrets file: $secret_path${NC}"
                else
                    echo "  ${YELLOW}⚠ Secrets file not found: $secret_path${NC}"
                fi
            done
        fi
    fi
    
    # Check scrub patterns
    if [ -f "$conf_file" ]; then
        local scrub_patterns
        scrub_patterns=$(grep "^scrub_patterns=" "$conf_file" | cut -d= -f2 | tr -d ' ' || echo "")
        if [ -n "$scrub_patterns" ]; then
            echo "  Scrub patterns: $scrub_patterns"
        else
            echo "  ${YELLOW}No scrub patterns defined${NC}"
        fi
    fi
}

# Knowledge base inspection
inspect_knowledge() {
    local module_name="$1"
    local module_dir="${IGOR_DIR}/modules/${module_name}"
    
    echo -e "${BLUE}=== Knowledge Base for $module_name ===${NC}"
    
    # Check knowledge directory
    local knowledge_dir="${module_dir}/knowledge"
    if [ -d "$knowledge_dir" ]; then
        echo "  Knowledge files:"
        for knowledge_file in "${knowledge_dir}"/*.md; do
            [ -f "$knowledge_file" ] || continue
            local file_size
            file_size=$(wc -l < "$knowledge_file" 2>/dev/null || echo "unknown")
            echo "    ${GREEN}✓$(basename "$knowledge_file")${NC} ($file_size lines)"
        done
        
        # Show content summary for key files
        if [ -f "${knowledge_dir}/primer.md" ]; then
            echo "  Primer summary (first 3 lines):"
            head -3 "${knowledge_dir}/primer.md" | sed 's/^/    /'
        fi
    else
        echo "  ${YELLOW}No knowledge directory found${NC}"
    fi
}

# Runbooks inspection
inspect_runbooks() {
    local module_name="$1"
    local module_dir="${IGOR_DIR}/modules/${module_name}"
    
    echo -e "${BLUE}=== Runbooks for $module_name ===${NC}"
    
    # Check runbooks directory
    local runbooks_dir="${module_dir}/runbooks"
    if [ -d "$runbooks_dir" ]; then
        echo "  Runbook files:"
        for runbook_file in "${runbooks_dir}"/*.md; do
            [ -f "$runbook_file" ] || continue
            local file_size
            file_size=$(wc -l < "$runbook_file" 2>/dev/null || echo "unknown")
            echo "    ${GREEN}✓$(basename "$runbook_file")${NC} ($file_size lines)"
        done
    else
        echo "  ${YELLOW}No runbooks directory found${NC}"
    fi
}

# Hook testing
test_hooks() {
    local module_name="$1"
    
    echo -e "${BLUE}=== Testing Hooks for $module_name ===${NC}"
    
    if ! igor_has_module "$module_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Module $module_name is not loaded${NC}"
        return 1
    fi
    
    # Test basic hooks
    for hook in health diagnose; do
        local hook_func="${module_name}__${hook}"
        if declare -f "$hook_func" >/dev/null; then
            echo -e "${BLUE}Testing $hook_func:${NC}"
            local output
            output=$("$hook_func" 2>&1)
            local exit_code=$?
            if [ $exit_code -eq 0 ]; then
                echo -e "  ${GREEN}✓ Success${NC}"
                if [ -n "$output" ]; then
                    echo "    Output: $output"
                fi
            else
                echo -e "  ${RED}✗ Failed (exit code: $exit_code)${NC}"
                if [ -n "$output" ]; then
                    echo "    Error: $output"
                fi
            fi
        fi
    done
}

# Health checking
check_health() {
    local module_name="$1"
    
    echo -e "${BLUE}=== Health Check for $module_name ===${NC}"
    
    if ! igor_has_module "$module_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Module $module_name is not loaded${NC}"
        return 1
    fi
    
    local health_func="${module_name}__health"
    if declare -f "$health_func" >/dev/null; then
        local health_output
        health_output=$("$health_func" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            echo -e "${GREEN}✓ Health check passed${NC}"
            echo "  Status: $health_output"
        else
            echo -e "${RED}✗ Health check failed (exit code: $exit_code)${NC}"
            echo "  Error: $health_output"
        fi
    else
        echo -e "${YELLOW}⚠ No health function defined${NC}"
    fi
}

# Full comprehensive validation
validate_all() {
    local module_name="$1"
    
    echo -e "${BLUE}=====================================================================${NC}"
    echo -e "${BLUE}  IGOR MODULE VALIDATION: $module_name${NC}"
    echo -e "${BLUE}=====================================================================${NC}"
    echo
    
    validate_module_conf "$module_name"
    echo
    validate_dependencies "$module_name"
    echo
    validate_registration "$module_name"
    echo
    inspect_hooks "$module_name"
    echo
    inspect_menu_items "$module_name"
    echo
    inspect_ai_tools "$module_name"
    echo
    inspect_ai_knowledge "$module_name"
    echo
    inspect_ai_patterns "$module_name"
    echo
    inspect_config_files "$module_name"
    echo
    inspect_health_checks "$module_name"
    echo
    inspect_env_files "$module_name"
    echo
    inspect_knowledge "$module_name"
    echo
    inspect_runbooks "$module_name"
    echo
    check_health "$module_name"
    echo
    echo -e "${BLUE}=====================================================================${NC}"
}

# Main execution
main() {
    local module_name="$1"
    local command="${2:-full}"
    
    if [ -z "$module_name" ]; then
        echo -e "${RED}Error: Module name required${NC}"
        usage
        exit 1
    fi
    
    case "$command" in
        config)        validate_module_conf "$module_name" ;;
        registration)  validate_registration "$module_name" ;;
        dependencies)  validate_dependencies "$module_name" ;;
        hooks)         inspect_hooks "$module_name" ;;
        menu-items)    inspect_menu_items "$module_name" ;;
        ai-tools)      inspect_ai_tools "$module_name" ;;
        ai-knowledge)  inspect_ai_knowledge "$module_name" ;;
        ai-patterns)   inspect_ai_patterns "$module_name" ;;
        config-files)  inspect_config_files "$module_name" ;;
        health-checks) inspect_health_checks "$module_name" ;;
        env-files)     inspect_env_files "$module_name" ;;
        patterns)      inspect_ai_patterns "$module_name" ;;  # alias for ai-patterns
        knowledge)     inspect_knowledge "$module_name" ;;
        runbooks)      inspect_runbooks "$module_name" ;;
        test-hooks)    test_hooks "$module_name" ;;
        health)        check_health "$module_name" ;;
        full)          validate_all "$module_name" ;;
        *)             usage; exit 1 ;;
    esac
}

# Run main function with all arguments
main "$@"