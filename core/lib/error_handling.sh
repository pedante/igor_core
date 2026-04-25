#!/bin/bash
# ==============================================================================
#  IGOR — Standardized Error Handling
#  Provides consistent error handling patterns across all subsystems
# ==============================================================================

# Error codes
declare -A _IGOR_ERROR_CODES
_IGOR_ERROR_CODES[SUCCESS]=0
_IGOR_ERROR_CODES[GENERAL]=1
_IGOR_ERROR_CODES[INVALID_INPUT]=2
_IGOR_ERROR_CODES[FILE_NOT_FOUND]=3
_IGOR_ERROR_CODES[PERMISSION_DENIED]=4
_IGOR_ERROR_CODES[RESOURCE_LIMIT]=5
_IGOR_ERROR_CODES[TIMEOUT]=6
_IGOR_ERROR_CODES[DEPENDENCY_MISSING]=7
_IGOR_ERROR_CODES[CONFIGURATION_ERROR]=8
_IGOR_ERROR_CODES[NETWORK_ERROR]=9
_IGOR_ERROR_CODES[VALIDATION_ERROR]=10

# Error context stack for nested operations
declare -a _IGOR_ERROR_CONTEXT_STACK=()

# Initialize error handling system
igor_error_init() {
    # Clear context stack
    _IGOR_ERROR_CONTEXT_STACK=()
    
    # Set up error trap if not already set
    if [ -z "${_IGOR_ERROR_TRAP_SET:-}" ]; then
        trap '_igor_error_handler' ERR
        export _IGOR_ERROR_TRAP_SET=true
    fi
}

# Add context to error stack
# Usage: igor_error_push_context <context>
igor_error_push_context() {
    local context="$1"
    _IGOR_ERROR_CONTEXT_STACK+=("$context")
}

# Remove context from error stack
# Usage: igor_error_pop_context
igor_error_pop_context() {
    local last_index=$((${#_IGOR_ERROR_CONTEXT_STACK[@]} - 1))
    if [ "$last_index" -ge 0 ]; then
        unset _IGOR_ERROR_CONTEXT_STACK[$last_index]
    fi
}

# Get current error context
igor_error_get_context() {
    if [ ${#_IGOR_ERROR_CONTEXT_STACK[@]} -eq 0 ]; then
        echo ""
    else
        local context_str
        context_str=$(IFS=" > "; echo "${_IGOR_ERROR_CONTEXT_STACK[*]}")
        echo "Context: $context_str"
    fi
}

# Global error handler — registered via: trap '_igor_error_handler' ERR
# Bash ERR trap does not pass args; use BASH_COMMAND and BASH_LINENO instead.
_igor_error_handler() {
    local exit_code=$?
    local line_number="${BASH_LINENO[0]:-}"
    local command_name="${BASH_COMMAND:-}"

    # Get the error context
    local context
    context=$(igor_error_get_context)

    # Format error message
    local error_msg="ERROR: Command '${command_name}' failed with exit code ${exit_code}"
    [ -n "$line_number" ] && error_msg="$error_msg at line $line_number"
    [ -n "$context"     ] && error_msg="$error_msg\n  $context"

    # Log error
    echo -e "$error_msg" >&2

    # Log to error file if runtime dir exists
    local error_log="${_IGOR_PATHS[RUNTIME_DIR]}/error.log"
    if [ -d "$(dirname "$error_log")" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $error_msg" >> "$error_log"
    fi
}

# Standardized error reporting
# Usage: igor_error <error_code> <message> [additional_details...]
igor_error() {
    local error_code="$1"
    local message="$2"
    shift 2
    
    # Validate error code
    if [ -z "${_IGOR_ERROR_CODES[$error_code]}" ]; then
        echo "ERROR: Unknown error code: $error_code" >&2
        error_code="GENERAL"
    fi
    
    # Get error context
    local context
    context=$(igor_error_get_context)
    
    # Format error message
    local formatted_msg="ERROR: $message"
    [ -n "$context" ] && formatted_msg="$formatted_msg\n  $context"
    
    # Add additional details if provided
    if [ $# -gt 0 ]; then
        formatted_msg="$formatted_msg\n  Details: $*"
    fi
    
    # Print error
    echo -e "$formatted_msg" >&2
    
    # Log to error file if runtime dir exists
    local error_log="${_IGOR_PATHS[RUNTIME_DIR]}/error.log"
    if [ -d "${_IGOR_PATHS[RUNTIME_DIR]:-}" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${error_code}] $formatted_msg" >> "$error_log"
    fi
    
    return "${_IGOR_ERROR_CODES[$error_code]}"
}

# Warning reporting (non-fatal)
# Usage: igor_warn <message> [additional_details...]
igor_warn() {
    local message="$1"
    shift
    
    # Get error context
    local context
    context=$(igor_error_get_context)
    
    # Format warning message
    local formatted_msg="WARNING: $message"
    [ -n "$context" ] && formatted_msg="$formatted_msg\n  $context"
    
    # Add additional details if provided
    if [ $# -gt 0 ]; then
        formatted_msg="$formatted_msg\n  Details: $*"
    fi
    
    # Print warning
    echo -e "$formatted_msg" >&2
    
    # Log to warning file if runtime dir exists
    local warning_log="${_IGOR_PATHS[RUNTIME_DIR]}/warning.log"
    if [ -d "${_IGOR_PATHS[RUNTIME_DIR]:-}" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $formatted_msg" >> "$warning_log"
    fi
}

# Safe command execution with error handling
# Usage: igor_safe_exec <command> [error_code] [error_message]
igor_safe_exec() {
    local command="$1"
    local error_code="${2:-GENERAL}"
    local error_message="${3:-Command failed: $command}"
    
    # Add command to context
    igor_error_push_context "executing: $command"
    
    # Execute command with error handling
    local output
    output=$(eval "$command" 2>&1)
    local exit_code=$?
    
    # Remove command from context
    igor_error_pop_context
    
    if [ $exit_code -ne 0 ]; then
        igor_error "$error_code" "$error_message" "Exit code: $exit_code" "Output: $output"
        return $exit_code
    fi
    
    echo "$output"
    return 0
}

# Safe file operations with error handling
# Usage: igor_safe_read <file_path>
igor_safe_read() {
    local file_path="$1"
    
    # Validate file path
    if ! igor_validate_file "$file_path" "r"; then
        igor_error "FILE_NOT_FOUND" "Cannot read file: $file_path"
        return 1
    fi
    
    # Read file with error handling
    local content
    if ! content=$(cat "$file_path" 2>/dev/null); then
        igor_error "PERMISSION_DENIED" "Cannot read file: $file_path"
        return 1
    fi
    
    echo "$content"
    return 0
}

# Usage: igor_safe_write <file_path> <content> [backup]
igor_safe_write() {
    local file_path="$1"
    local content="$2"
    local backup="${3:-true}"
    
    # Validate file path for writing
    if ! file_path=$(validate_file_operation "$file_path" "write"); then
        igor_error "INVALID_INPUT" "Cannot write to file: $file_path"
        return 1
    fi
    
    # Create backup if requested
    if [ "$backup" = "true" ] && [ -f "$file_path" ]; then
        local backup_path="${file_path}.bak.$(date +%s)"
        if ! cp "$file_path" "$backup_path"; then
            igor_warn "Failed to create backup: $backup_path"
        fi
    fi
    
    # Write content with error handling
    igor_error_push_context "writing to: $file_path"
    if ! echo "$content" > "$file_path" 2>/dev/null; then
        igor_error_pop_context
        igor_error "PERMISSION_DENIED" "Cannot write to file: $file_path"
        return 1
    fi
    igor_error_pop_context
    
    return 0
}

# Safe directory operations
# Usage: igor_safe_mkdir <directory_path> [mode]
igor_safe_mkdir() {
    local dir_path="$1"
    local mode="${2:-755}"
    
    # Validate directory path
    if ! dir_path=$(igor_resolve_path "$dir_path"); then
        igor_error "INVALID_INPUT" "Cannot create directory: $dir_path"
        return 1
    fi
    
    # Create directory with error handling
    igor_error_push_context "creating directory: $dir_path"
    if ! mkdir -p "$dir_path"; then
        igor_error_pop_context
        igor_error "PERMISSION_DENIED" "Cannot create directory: $dir_path"
        return 1
    fi
    
    # Set permissions if specified
    if [ -n "$mode" ]; then
        if ! chmod "$mode" "$dir_path" 2>/dev/null; then
            igor_warn "Failed to set permissions on directory: $dir_path"
        fi
    fi
    
    igor_error_pop_context
    return 0
}

# Retry operations with exponential backoff
# Usage: igor_retry <command> [max_attempts] [base_delay]
igor_retry() {
    local command="$1"
    local max_attempts="${2:-3}"
    local base_delay="${3:-1}"
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        igor_error_push_context "attempt $attempt/$max_attempts"
        
        if eval "$command"; then
            igor_error_pop_context
            return 0
        fi
        
        igor_error_pop_context
        
        # Don't delay on last attempt
        if [ $attempt -lt $max_attempts ]; then
            local delay=$((base_delay * attempt))
            igor_warn "Command failed, retrying in $delay second(s)..."
            sleep "$delay"
        fi
        
        ((attempt++))
    done
    
    igor_error "TIMEOUT" "Command failed after $max_attempts attempts: $command"
    return 1
}

# Initialize error handling system when this module is loaded
igor_error_init