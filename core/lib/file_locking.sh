#!/bin/bash
# ==============================================================================
#  IGOR — File Locking Mechanism
#  Provides safe concurrent access to shared resources
# ==============================================================================

# Global lock file registry
declare -A _IGOR_LOCKS
_IGOR_LOCK_TIMEOUT=${_IGOR_LOCK_TIMEOUT:-30}  # 30 seconds default timeout

# Initialize locking system
igor_lock_init() {
    # Resolve lock dir: prefer explicit var, fall back to paths array, then IGOR_DIR
    local lock_dir="${IGOR_LOCK_DIR:-}"
    if [ -z "$lock_dir" ]; then
        if [ -n "${_IGOR_PATHS[RUNTIME_DIR]:-}" ]; then
            lock_dir="${_IGOR_PATHS[RUNTIME_DIR]}/locks"
        elif [ -n "${IGOR_DIR:-}" ]; then
            lock_dir="${IGOR_DIR}/data/runtime/locks"
        else
            echo "ERROR: Cannot determine lock directory — IGOR_DIR not set" >&2
            return 1
        fi
    fi
    mkdir -p "$lock_dir" 2>/dev/null || {
        echo "ERROR: Cannot create lock directory: $lock_dir" >&2
        return 1
    }
    export _IGOR_LOCK_TIMEOUT
    export IGOR_LOCK_DIR="$lock_dir"
    return 0
}

# Acquire a lock for a resource
# Usage: igor_lock_acquire <resource_name> [timeout]
igor_lock_acquire() {
    local resource_name="$1"
    local timeout="${2:-$_IGOR_LOCK_TIMEOUT}"
    
    if [ -z "$resource_name" ]; then
        echo "ERROR: Resource name cannot be empty" >&2
        return 1
    fi
    
    # Sanitize resource name
    resource_name=$(echo "$resource_name" | sed 's/[^a-zA-Z0-9_\-]/_/g')
    
    local lock_file="${IGOR_LOCK_DIR}/${resource_name}.lock"
    local pid=$$
    local start_time=$(date +%s)
    
    # Check if lock directory exists
    if [ ! -d "$IGOR_LOCK_DIR" ]; then
        echo "ERROR: Lock directory not found: $IGOR_LOCK_DIR" >&2
        return 1
    fi
    
    # Try to acquire lock with timeout
    while true; do
        # Try to create lock file with our PID
        if ( set -o noclobber; echo "$pid" > "$lock_file" ) 2>/dev/null; then
            # Lock acquired successfully
            _IGOR_LOCKS["$resource_name"]="$lock_file"
            
            # Set up trap to release lock on exit
            trap "igor_lock_release '$resource_name' 2>/dev/null || true" EXIT
            
            return 0
        fi
        
        # Check if lock is stale (process no longer exists)
        if [ -f "$lock_file" ]; then
            local lock_pid
            lock_pid=$(cat "$lock_file" 2>/dev/null)
            if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                # Lock is stale, remove it
                rm -f "$lock_file" 2>/dev/null
                continue
            fi
        fi
        
        # Check timeout
        local current_time=$(date +%s)
        if [ $((current_time - start_time)) -gt "$timeout" ]; then
            echo "ERROR: Timeout waiting for lock: $resource_name" >&2
            return 1
        fi
        
        # Wait a bit before retrying
        sleep 0.1
    done
}

# Release a lock for a resource
# Usage: igor_lock_release <resource_name>
igor_lock_release() {
    local resource_name="$1"
    
    if [ -z "$resource_name" ]; then
        echo "ERROR: Resource name cannot be empty" >&2
        return 1
    fi
    
    # Sanitize resource name
    resource_name=$(echo "$resource_name" | sed 's/[^a-zA-Z0-9_\-]/_/g')
    
    local lock_file="${IGOR_LOCK_DIR}/${resource_name}.lock"

    # Check if we own this lock
    if [ -f "$lock_file" ]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null)
        local current_pid=$$
        
        if [ "$lock_pid" = "$current_pid" ]; then
            # We own this lock, remove it
            rm -f "$lock_file" 2>/dev/null
            unset _IGOR_LOCKS["$resource_name"]
            return 0
        else
            echo "WARNING: Attempted to release lock not owned by current process: $resource_name" >&2
            return 1
        fi
    else
        # Lock file doesn't exist, already released
        unset _IGOR_LOCKS["$resource_name"]
        return 0
    fi
}

# Execute a function with exclusive lock
# Usage: igor_with_lock <resource_name> <function> [args...]
igor_with_lock() {
    local resource_name="$1"
    shift
    
    if [ -z "$resource_name" ]; then
        echo "ERROR: Resource name cannot be empty" >&2
        return 1
    fi
    
    # Initialize locking system if needed
    if [ -z "${IGOR_LOCK_DIR:-}" ]; then
        igor_lock_init || return 1
    fi
    
    # Acquire lock
    if ! igor_lock_acquire "$resource_name"; then
        return 1
    fi
    
    # Execute function with lock held
    local exit_code=0
    "$@" || exit_code=$?
    
    # Release lock
    igor_lock_release "$resource_name" 2>/dev/null || true
    
    return $exit_code
}

# Check if a resource is locked
# Usage: igor_is_locked <resource_name>
igor_is_locked() {
    local resource_name="$1"
    
    if [ -z "$resource_name" ]; then
        echo "ERROR: Resource name cannot be empty" >&2
        return 1
    fi
    
    # Sanitize resource name
    resource_name=$(echo "$resource_name" | sed 's/[^a-zA-Z0-9_\-]/_/g')
    
    local lock_file="${IGOR_LOCK_DIR}/${resource_name}.lock"

    if [ ! -f "$lock_file" ]; then
        return 1  # Not locked
    fi
    
    # Check if lock is still active
    local lock_pid
    lock_pid=$(cat "$lock_file" 2>/dev/null)
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        return 0  # Locked and active
    else
        # Stale lock, remove it
        rm -f "$lock_file" 2>/dev/null
        return 1  # Not locked (stale lock removed)
    fi
}

# Wait for lock to be released
# Usage: igor_wait_for_lock <resource_name> [timeout]
igor_wait_for_lock() {
    local resource_name="$1"
    local timeout="${2:-$_IGOR_LOCK_TIMEOUT}"
    
    if [ -z "$resource_name" ]; then
        echo "ERROR: Resource name cannot be empty" >&2
        return 1
    fi
    
    local start_time=$(date +%s)
    
    while igor_is_locked "$resource_name"; do
        local current_time=$(date +%s)
        if [ $((current_time - start_time)) -gt "$timeout" ]; then
            echo "ERROR: Timeout waiting for lock release: $resource_name" >&2
            return 1
        fi
        sleep 0.1
    done
    
    return 0
}

# Clean up stale locks
igor_lock_cleanup() {
    local lock_dir="${IGOR_LOCK_DIR}"
    
    if [ ! -d "$lock_dir" ]; then
        return 0
    fi
    
    local cleaned_count=0
    # Use find to avoid potential globbing issues
    while IFS= read -r -d '' lock_file; do
        if [ -f "$lock_file" ]; then
            local lock_pid
            lock_pid=$(cat "$lock_file" 2>/dev/null)
            if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                # Stale lock, remove it
                rm -f "$lock_file" 2>/dev/null
                ((cleaned_count++))
            fi
        fi
    done < <(find "$lock_dir" -name "*.lock" -print0 2>/dev/null)
    
    if [ "$cleaned_count" -gt 0 ]; then
        echo "Cleaned up $cleaned_count stale lock files" >&2
    fi
    
    return 0
}

# Initialize locking system when this module is loaded
if [ -z "${IGOR_LOCK_DIR:-}" ]; then
    igor_lock_init 2>/dev/null || true
fi