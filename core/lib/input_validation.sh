#!/bin/bash
# ==============================================================================
#  IGOR — Input Validation and Sanitization
#  Provides secure input validation for all user inputs
# ==============================================================================

# Input validation registry
declare -A _VALIDATION_PATTERNS

# Initialize validation patterns
igor_validation_init() {
    # File path validation patterns
    _VALIDATION_PATTERNS[file_path]="^[a-zA-Z0-9_\-/\.][a-zA-Z0-9_\-/\. ]*$"
    _VALIDATION_PATTERNS[relative_path]="^[a-zA-Z0-9_\-\.][a-zA-Z0-9_\-\.\/]*$"
    _VALIDATION_PATTERNS[safe_filename]="^[a-zA-Z0-9_\-][a-zA-Z0-9_\-\.]*$"
    
    # Command validation patterns
    _VALIDATION_PATTERNS[safe_command]="^[a-zA-Z0-9_\-/\. ][a-zA-Z0-9_\-/\. \;\"\'\&\|\(\)<>\?\!\@\#\$\%\^\*\+\=\[\]\{\}]*$"
    _VALIDATION_PATTERNS[occ_command]="^[a-zA-Z0-9_\-:][a-zA-Z0-9_\-: ]*$"
    
    # General validation patterns
    _VALIDATION_PATTERNS[alphanumeric]="^[a-zA-Z0-9]+$"
    _VALIDATION_PATTERNS[hostname]="^[a-zA-Z0-9][a-zA-Z0-9\-\.]*[a-zA-Z0-9]$"
    _VALIDATION_PATTERNS[service_name]="^[a-zA-Z0-9_\-]+$"
    
    # Numeric validation patterns
    _VALIDATION_PATTERNS[port_number]="^[0-9]+$"
    _VALIDATION_PATTERNS[positive_int]="^[1-9][0-9]*$"
    _VALIDATION_PATTERNS[non_negative]="^[0-9]+$"
}

# Validate input against a pattern
# Usage: validate_input <pattern_name> <input> [error_message]
validate_input() {
    local pattern_name="$1"
    local input="$2"
    local error_msg="${3:-Invalid input format}"
    
    if [ -z "${_VALIDATION_PATTERNS[$pattern_name]:-}" ]; then
        echo "ERROR: Unknown validation pattern: $pattern_name" >&2
        return 1
    fi
    
    if [[ ! "$input" =~ ${_VALIDATION_PATTERNS[$pattern_name]} ]]; then
        echo "ERROR: $error_msg" >&2
        return 1
    fi
    
    return 0
}

# Sanitize file paths to prevent directory traversal
# Usage: sanitize_path <path> [base_dir]
sanitize_path() {
    local path="$1"
    local base_dir="${2:-${IGOR_DIR}}"
    
    # Remove leading/trailing whitespace
    path=$(echo "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Resolve relative paths
    if [[ "$path" != /* ]]; then
        path="${base_dir}/${path}"
    fi
    
    # Normalize path (remove redundant slashes, etc.)
    path=$(realpath -m "$path" 2>/dev/null || echo "$path")
    
    # Check for path traversal attempts
    if echo "$path" | grep -qE '\.\./|~|\$\{'; then
        echo "ERROR: Path traversal detected" >&2
        return 1
    fi
    
    # Restrict to safe directories
    local safe_dirs=("$base_dir" "/tmp" "/var/tmp" "/mnt")
    local is_safe=false
    
    for safe_dir in "${safe_dirs[@]}"; do
        if [[ "$path" == "$safe_dir"* ]]; then
            is_safe=true
            break
        fi
    done
    
    if ! $is_safe; then
        echo "ERROR: Access to directory not allowed: ${path}" >&2
        return 1
    fi
    
    echo "$path"
    return 0
}

# Sanitize command input to prevent injection
# Usage: sanitize_command <command>
sanitize_command() {
    local cmd="$1"
    
    # Block dangerous characters and patterns
    local dangerous_patterns=(
        'rm -rf /'
        'rm -rf \*'
        ':(){ :|:& };:'
        'dd if=/dev/zero'
        'mkfs'
        'curl | bash'
        'wget | bash'
        'base64 -d'
        'python -c "import os; os.system('
        'eval \$('
        '$(rm'
        '$(dd'
        '| sh'
        '| bash'
        '>> /etc/passwd'
        '>> /etc/shadow'
    )
    
    for pattern in "${dangerous_patterns[@]}"; do
        if echo "$cmd" | grep -qF "$pattern"; then
            echo "ERROR: Dangerous command pattern detected" >&2
            return 1
        fi
    done
    
    echo "$cmd"
    return 0
}

# Validate and sanitize user input for file operations
# Usage: validate_file_operation <path> [operation_type]
validate_file_operation() {
    local path="$1"
    local operation_type="${2:-read}"
    
    # Validate input is not empty
    if [ -z "$path" ]; then
        echo "ERROR: File path cannot be empty" >&2
        return 1
    fi
    
    # Sanitize path
    local safe_path
    safe_path=$(sanitize_path "$path") || return 1
    
    # Check if file exists (for read operations)
    if [[ "$operation_type" == "read" && ! -f "$safe_path" ]]; then
        echo "ERROR: File not found: $safe_path" >&2
        return 1
    fi
    
    # Check if parent directory exists (for write operations)
    if [[ "$operation_type" == "write" ]]; then
        local parent_dir
        parent_dir=$(dirname "$safe_path")
        if [ ! -d "$parent_dir" ]; then
            echo "ERROR: Parent directory does not exist: $parent_dir" >&2
            return 1
        fi
    fi
    
    # Additional safety checks for system files
    local system_files=(
        "/etc/passwd"
        "/etc/shadow"
        "/etc/hosts"
        "/etc/fstab"
        "/etc/sudoers"
        "/etc/ssh"
        "/boot"
        "/dev"
        "/proc"
        "/sys"
        "/root"
    )
    
    for sys_file in "${system_files[@]}"; do
        if [[ "$safe_path" == "$sys_file"* ]]; then
            echo "ERROR: Access to system files not allowed" >&2
            return 1
        fi
    done
    
    echo "$safe_path"
    return 0
}

# Validate numeric inputs
# Usage: validate_numeric <value> <min> <max> [description]
validate_numeric() {
    local value="$1"
    local min="$2"
    local max="$3"
    local description="${4:-value}"
    
    # Check if numeric
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "ERROR: $description must be a positive integer" >&2
        return 1
    fi
    
    # Check range
    if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
        echo "ERROR: $description must be between $min and $max" >&2
        return 1
    fi
    
    return 0
}

# Validate hostname/domain
# Usage: validate_hostname <hostname>
validate_hostname() {
    local hostname="$1"
    
    # Basic hostname validation
    if ! [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo "ERROR: Invalid hostname format" >&2
        return 1
    fi
    
    # Check length
    if [ ${#hostname} -gt 253 ]; then
        echo "ERROR: Hostname too long (max 253 characters)" >&2
        return 1
    fi
    
    return 0
}

# Validate service/container name
# Usage: validate_service_name <name>
validate_service_name() {
    local name="$1"
    
    validate_input "service_name" "$name" "Invalid service name format"
}

# Validate port number
# Usage: validate_port <port>
validate_port() {
    local port="$1"
    
    validate_numeric "$port" 1 65535 "Port number"
}

# Initialize validation patterns
igor_validation_init