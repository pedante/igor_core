#!/bin/bash
# ==============================================================================
#  IGOR — Enhanced Path Resolution
#  Provides consistent and secure path resolution throughout the system
# ==============================================================================

# Global path registry
declare -A _IGOR_PATHS

# Initialize standard paths
igor_paths_init() {
    # Base directories
    _IGOR_PATHS[IGOR_DIR]="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    _IGOR_PATHS[CONFIG_DIR]="${_IGOR_PATHS[IGOR_DIR]}/config"
    _IGOR_PATHS[MODULES_DIR]="${_IGOR_PATHS[IGOR_DIR]}/modules"
    _IGOR_PATHS[CORE_DIR]="${_IGOR_PATHS[IGOR_DIR]}/core"
    _IGOR_PATHS[LIB_DIR]="${_IGOR_PATHS[CORE_DIR]}/lib"
    
    # Data directories
    _IGOR_PATHS[DATA_DIR]="${_IGOR_PATHS[IGOR_DIR]}/data"
    _IGOR_PATHS[SESSIONS_DIR]="${_IGOR_PATHS[DATA_DIR]}/sessions"
    _IGOR_PATHS[REPORTS_DIR]="${_IGOR_PATHS[DATA_DIR]}/reports"
    _IGOR_PATHS[ALERTS_DIR]="${_IGOR_PATHS[DATA_DIR]}/alerts"
    _IGOR_PATHS[PATTERNS_DIR]="${_IGOR_PATHS[DATA_DIR]}/patterns"
    _IGOR_PATHS[BACKUPS_DIR]="${_IGOR_PATHS[DATA_DIR]}/backups"
    _IGOR_PATHS[RUNTIME_DIR]="${_IGOR_PATHS[DATA_DIR]}/runtime"
    
    # Configuration directories
    _IGOR_PATHS[VARIABLES_DIR]="${_IGOR_PATHS[CONFIG_DIR]}/variables"
    _IGOR_PATHS[STACKS_DIR]="${_IGOR_PATHS[CONFIG_DIR]}/stacks"
    _IGOR_PATHS[KNOWLEDGE_DIR]="${_IGOR_PATHS[IGOR_DIR]}/knowledge"
    
    # Security directories
    _IGOR_PATHS[SECRETS_DIR]="${_IGOR_PATHS[IGOR_DIR]}/secrets"
    
    # Runtime files
    _IGOR_PATHS[PID_FILE]="${_IGOR_PATHS[RUNTIME_DIR]}/pid"
    _IGOR_PATHS[STATE_FILE]="${_IGOR_PATHS[RUNTIME_DIR]}/state.sh"
    _IGOR_PATHS[IPC_FILE]="${_IGOR_PATHS[RUNTIME_DIR]}/ipc.sh"
    _IGOR_PATHS[HEARTBEAT_FILE]="${_IGOR_PATHS[RUNTIME_DIR]}/diag_heartbeat"
    
    # Default external paths (can be overridden by config)
    _IGOR_PATHS[HD_MOUNT]="${HD_MOUNT:-/mnt/nextclouddata}"
    _IGOR_PATHS[NC_DATA]="${NC_DATA:-${_IGOR_PATHS[HD_MOUNT]}/next}"
    _IGOR_PATHS[INSTALL_DIR]="${INSTALL_DIR:-${_IGOR_PATHS[IGOR_DIR]}}"
    
    # Export all paths for use in subshells
    for path_key in "${!_IGOR_PATHS[@]}"; do
        local var_name="_IGOR_PATHS_${path_key}"
        export "$var_name"="${_IGOR_PATHS[$path_key]}"
    done
}

# Get a registered path by key
# Usage: igor_get_path <key> [fallback]
igor_get_path() {
    local key="$1"
    local fallback="${2:-}"
    
    if [ -z "${_IGOR_PATHS[$key]:-}" ]; then
        if [ -n "$fallback" ]; then
            echo "$fallback"
            return 0
        else
            echo "ERROR: Unknown path key: $key" >&2
            return 1
        fi
    fi
    
    echo "${_IGOR_PATHS[$key]}"
    return 0
}

# Resolve a path safely (with path traversal prevention)
# Usage: igor_resolve_path <path> [base_dir]
igor_resolve_path() {
    local path="$1"
    local base_dir="${2:-${_IGOR_PATHS[IGOR_DIR]}}"
    
    # Handle empty path
    if [ -z "$path" ]; then
        echo "ERROR: Path cannot be empty" >&2
        return 1
    fi
    
    # Remove leading/trailing whitespace
    path=$(echo "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Resolve relative paths
    if [[ "$path" != /* ]]; then
        path="${base_dir}/${path}"
    fi
    
    # Normalize path (remove redundant slashes, resolve . and ..)
    # Use python for robust path normalization
    local normalized_path
    normalized_path=$(python3 -c "
import os, sys
try:
    path = '$path'
    normalized = os.path.normpath(os.path.abspath(path))
    print(normalized)
except Exception as e:
    print('ERROR: Path normalization failed:', str(e), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Path normalization failed" >&2
        return 1
    fi
    
    # Check for path traversal attempts
    if echo "$normalized_path" | grep -qE '\.\./|~|\$\{|\$\('; then
        echo "ERROR: Path traversal detected in: $path" >&2
        return 1
    fi
    
    # Restrict to safe directories
    local safe_dirs=(
        "${_IGOR_PATHS[IGOR_DIR]}"
        "/tmp"
        "/var/tmp"
        "/mnt"
        "/home"
        "/opt"
    )
    
    local is_safe=false
    for safe_dir in "${safe_dirs[@]}"; do
        if [[ "$normalized_path" == "$safe_dir"* ]]; then
            is_safe=true
            break
        fi
    done
    
    if ! $is_safe; then
        echo "ERROR: Access to directory not allowed: ${normalized_path}" >&2
        return 1
    fi
    
    # Additional security checks for sensitive system directories
    local restricted_dirs=(
        "/root"
        "/etc"
        "/boot"
        "/dev"
        "/proc"
        "/sys"
        "/usr/sbin"
        "/bin"
        "/sbin"
        "/lib"
        "/lib64"
    )
    
    for restricted_dir in "${restricted_dirs[@]}"; do
        if [[ "$normalized_path" == "$restricted_dir"* ]]; then
            echo "ERROR: Access to restricted directory: $restricted_dir" >&2
            return 1
        fi
    done
    
    echo "$normalized_path"
    return 0
}

# Ensure a directory exists and is accessible
# Usage: igor_ensure_dir <path> [mode]
igor_ensure_dir() {
    local dir_path="$1"
    local mode="${2:-755}"
    
    # Resolve path first
    if ! dir_path=$(igor_resolve_path "$dir_path"); then
        return 1
    fi
    
    # Create directory if it doesn't exist
    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path" || {
            echo "ERROR: Failed to create directory: $dir_path" >&2
            return 1
        }
    fi
    
    # Set permissions if specified
    if [ -n "$mode" ]; then
        chmod "$mode" "$dir_path" 2>/dev/null || {
            echo "WARNING: Failed to set permissions on $dir_path" >&2
        }
    fi
    
    # Check if directory is writable
    if [ ! -w "$dir_path" ]; then
        echo "ERROR: Directory not writable: $dir_path" >&2
        return 1
    fi
    
    echo "$dir_path"
    return 0
}

# Validate file existence and accessibility
# Usage: igor_validate_file <path> [access_mode]
igor_validate_file() {
    local file_path="$1"
    local access_mode="${2:-r}"  # r=read, w=write, x=execute
    
    # Resolve path first
    if ! file_path=$(igor_resolve_path "$file_path"); then
        return 1
    fi
    
    # Check if file exists
    if [ ! -f "$file_path" ]; then
        echo "ERROR: File not found: $file_path" >&2
        return 1
    fi
    
    # Check access permissions
    case "$access_mode" in
        "r")
            if [ ! -r "$file_path" ]; then
                echo "ERROR: File not readable: $file_path" >&2
                return 1
            fi
            ;;
        "w")
            if [ ! -w "$file_path" ]; then
                echo "ERROR: File not writable: $file_path" >&2
                return 1
            fi
            ;;
        "x")
            if [ ! -x "$file_path" ]; then
                echo "ERROR: File not executable: $file_path" >&2
                return 1
            fi
            ;;
        *)
            echo "ERROR: Invalid access mode: $access_mode" >&2
            return 1
            ;;
    esac
    
    echo "$file_path"
    return 0
}

# Initialize path system
igor_paths_init