#!/bin/bash
# ==============================================================================
#  IGOR — Atomic File Operations
#  Provides atomic file operations to prevent corruption and race conditions
# ==============================================================================

# Atomic file write using temporary file + rename
# Usage: igor_atomic_write <file_path> <content> [mode]
igor_atomic_write() {
    local file_path="$1"
    local content="$2"
    local mode="${3:-644}"
    
    # Validate file path
    if ! file_path=$(validate_file_operation "$file_path" "write"); then
        igor_error "INVALID_INPUT" "Cannot write to file: $file_path"
        return 1
    fi
    
    # Create directory if it doesn't exist
    local dir_path
    dir_path=$(dirname "$file_path")
    if [ ! -d "$dir_path" ]; then
        if ! mkdir -p "$dir_path"; then
            igor_error "PERMISSION_DENIED" "Cannot create directory: $dir_path"
            return 1
        fi
    fi
    
    # Create temporary file
    local temp_file="${file_path}.tmp.$$"
    local temp_file2="${file_path}.tmp.$$.2"
    
    # Double-temp strategy for extra safety
    # Write to first temp file
    if ! echo "$content" > "$temp_file" 2>/dev/null; then
        igor_error "PERMISSION_DENIED" "Cannot write to temporary file: $temp_file"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
    
    # Sync to disk
    sync "$temp_file" 2>/dev/null || true
    
    # Copy to second temp file
    if ! cp "$temp_file" "$temp_file2" 2>/dev/null; then
        igor_error "PERMISSION_DENIED" "Cannot copy to temporary file: $temp_file2"
        rm -f "$temp_file" "$temp_file2" 2>/dev/null
        return 1
    fi
    
    # Sync second temp file
    sync "$temp_file2" 2>/dev/null || true
    
    # Atomic rename
    if ! mv "$temp_file2" "$file_path" 2>/dev/null; then
        igor_error "PERMISSION_DENIED" "Cannot rename temporary file to: $file_path"
        rm -f "$temp_file" "$temp_file2" 2>/dev/null
        return 1
    fi
    
    # Clean up first temp file
    rm -f "$temp_file" 2>/dev/null
    
    # Set permissions
    if [ -n "$mode" ]; then
        chmod "$mode" "$file_path" 2>/dev/null || {
            igor_warn "Failed to set permissions on file: $file_path"
        }
    fi
    
    # Final sync
    sync "$file_path" 2>/dev/null || true
    
    return 0
}

# Atomic file append using flock — safe under concurrent access
# Usage: igor_atomic_append <file_path> <content>
igor_atomic_append() {
    local file_path="$1"
    local content="$2"

    # Validate file path
    if ! file_path=$(validate_file_operation "$file_path" "write"); then
        igor_error "INVALID_INPUT" "Cannot append to file: $file_path"
        return 1
    fi

    # Create directory if it doesn't exist
    local dir_path
    dir_path=$(dirname "$file_path")
    if [ ! -d "$dir_path" ]; then
        if ! mkdir -p "$dir_path"; then
            igor_error "PERMISSION_DENIED" "Cannot create directory: $dir_path"
            return 1
        fi
    fi

    # flock provides true atomic append — no read-modify-write race condition
    local lock_file="${file_path}.lock"
    (
        flock -x 200
        printf '%s\n' "$content" >> "$file_path"
    ) 200>"$lock_file"
    local rc=$?
    rm -f "$lock_file" 2>/dev/null || true
    return $rc
}

# Atomic file update (read-modify-write)
# Usage: igor_atomic_update <file_path> <update_function>
igor_atomic_update() {
    local file_path="$1"
    local update_function="$2"
    
    # Validate file path
    if ! file_path=$(validate_file_operation "$file_path" "write"); then
        igor_error "INVALID_INPUT" "Cannot update file: $file_path"
        return 1
    fi
    
    # Read existing content
    local existing_content
    if ! existing_content=$(igor_safe_read "$file_path"); then
        return 1
    fi
    
    # Apply update function
    local new_content
    if ! new_content=$(echo "$existing_content" | "$update_function"); then
        igor_error "GENERAL" "Update function failed: $update_function"
        return 1
    fi
    
    # Write atomically
    igor_atomic_write "$file_path" "$new_content"
}

# Atomic configuration file update
# Usage: igor_atomic_config_update <file_path> <key> <value> [separator]
igor_atomic_config_update() {
    local file_path="$1"
    local key="$2"
    local value="$3"
    local separator="${4:-=}"
    
    # Validate file path
    if ! file_path=$(validate_file_operation "$file_path" "write"); then
        igor_error "INVALID_INPUT" "Cannot update config file: $file_path"
        return 1
    fi
    
    # Read existing content
    local existing_content
    if ! existing_content=$(igor_safe_read "$file_path"); then
        return 1
    fi
    
    # Create backup
    local backup_path="${file_path}.bak.$(date +%s)"
    if [ -f "$file_path" ]; then
        cp "$file_path" "$backup_path" 2>/dev/null || {
            igor_warn "Failed to create backup: $backup_path"
        }
    fi
    
    # Update configuration using awk
    local new_content
    new_content=$(echo "$existing_content" | awk -F"$separator" -v key="$key" -v value="$value" '
    BEGIN {
        updated = 0
    }
    {
        # Remove leading/trailing whitespace
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        
        # Check if this line contains the key
        if ($1 == key) {
            # Update the value
            $2 = value
            updated = 1
            # Reconstruct the line with proper separator
            $1 = $1  # Prevent field reconstruction issues
            for (i = 3; i <= NF; i++) {
                $2 = $2 " " $i
            }
        }
        # Print the line
        print
    }
    END {
        # If key was not found, append it
        if (!updated) {
            print key separator value
        }
    }')
    
    # Write atomically
    igor_atomic_write "$file_path" "$new_content"
}

# Atomic line replacement
# Usage: igor_atomic_replace_line <file_path> <old_line> <new_line>
igor_atomic_replace_line() {
    local file_path="$1"
    local old_line="$2"
    local new_line="$3"
    
    # Validate file path
    if ! file_path=$(validate_file_operation "$file_path" "write"); then
        igor_error "INVALID_INPUT" "Cannot replace line in file: $file_path"
        return 1
    fi
    
    # Read existing content
    local existing_content
    if ! existing_content=$(igor_safe_read "$file_path"); then
        return 1
    fi
    
    # Replace line using awk
    local new_content
    new_content=$(echo "$existing_content" | awk -v old="$old_line" -v new="$new_line" '
    {
        if ($0 == old) {
            print new
        } else {
            print
        }
    }')
    
    # Write atomically
    igor_atomic_write "$file_path" "$new_content"
}

# Atomic file rotation (log rotation)
# Usage: igor_atomic_rotate <file_path> [max_files]
igor_atomic_rotate() {
    local file_path="$1"
    local max_files="${2:-10}"
    
    # Validate file path
    if ! file_path=$(validate_file_operation "$file_path" "write"); then
        igor_error "INVALID_INPUT" "Cannot rotate file: $file_path"
        return 1
    fi
    
    # Check if file exists
    if [ ! -f "$file_path" ]; then
        igor_warn "File does not exist, skipping rotation: $file_path"
        return 0
    fi
    
    # Rotate files
    local i=$((max_files - 1))
    while [ $i -gt 0 ]; do
        local old_file="${file_path}.$i"
        local new_file="${file_path}.$((i + 1))"
        
        if [ -f "$old_file" ]; then
            if [ $i -eq $((max_files - 1)) ]; then
                # Remove oldest file
                rm -f "$old_file" 2>/dev/null || true
            else
                # Move to next number
                mv "$old_file" "$new_file" 2>/dev/null || true
            fi
        fi
        
        ((i--))
    done
    
    # Move current file to .1
    mv "$file_path" "${file_path}.1" 2>/dev/null || {
        igor_error "PERMISSION_DENIED" "Cannot rotate file: $file_path"
        return 1
    }
    
    return 0
}

# Safe file locking with atomic operations
# Usage: igor_atomic_file_operation <operation> <file_path> [args...]
igor_atomic_file_operation() {
    local operation="$1"
    shift
    
    case "$operation" in
        "write")
            igor_atomic_write "$@"
            ;;
        "append")
            igor_atomic_append "$@"
            ;;
        "update")
            igor_atomic_update "$@"
            ;;
        "config_update")
            igor_atomic_config_update "$@"
            ;;
        "replace_line")
            igor_atomic_replace_line "$@"
            ;;
        "rotate")
            igor_atomic_rotate "$@"
            ;;
        *)
            igor_error "INVALID_INPUT" "Unknown atomic file operation: $operation"
            return 1
            ;;
    esac
}