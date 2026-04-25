#!/bin/bash
# ==============================================================================
#  IGOR — Resource Management
#  Provides resource limits and monitoring to prevent resource exhaustion
# ==============================================================================

# Resource limit configuration
declare -A _IGOR_RESOURCE_LIMITS

# Initialize resource limits
igor_resource_init() {
    # Token limits for AI operations
    _IGOR_RESOURCE_LIMITS[max_session_tokens]="${AI_MAX_TOKENS:-100000}"
    # Note: session cost is a float — handled by cost.sh, not igor_check_limit
    _IGOR_RESOURCE_LIMITS[max_file_size_bytes]="$((10 * 1024 * 1024))"  # 10MB
    _IGOR_RESOURCE_LIMITS[max_log_lines]=10000
    _IGOR_RESOURCE_LIMITS[max_pattern_files]=100
    _IGOR_RESOURCE_LIMITS[max_session_files]=50

    # Process limits — count only direct igor child processes, not all user procs
    _IGOR_RESOURCE_LIMITS[max_subprocesses]=50
    _IGOR_RESOURCE_LIMITS[subprocess_timeout]=30  # seconds
    _IGOR_RESOURCE_LIMITS[health_check_timeout]=60  # seconds

    # Memory limits (in MB) — Pi 3 has 1GB RAM + 1GB swap
    _IGOR_RESOURCE_LIMITS[max_memory_mb]=900  # warn when used > 900MB on Pi 3
    _IGOR_RESOURCE_LIMITS[ai_memory_mb]=512
    
    # Export limits
    for limit_key in "${!_IGOR_RESOURCE_LIMITS[@]}"; do
        local var_name="_IGOR_RESOURCE_LIMITS_${limit_key}"
        export "$var_name"="${_IGOR_RESOURCE_LIMITS[$limit_key]}"
    done
}

# Check if a resource limit is exceeded
# Usage: igor_check_limit <resource_type> <current_value> [custom_limit]
igor_check_limit() {
    local resource_type="$1"
    local current_value="$2"
    local custom_limit="$3"
    
    if [ -z "$resource_type" ] || [ -z "$current_value" ]; then
        echo "ERROR: Resource type and current value required" >&2
        return 1
    fi
    
    local limit="${custom_limit:-${_IGOR_RESOURCE_LIMITS[$resource_type]}}"
    
    if [ -z "$limit" ]; then
        echo "ERROR: Unknown resource limit type: $resource_type" >&2
        return 1
    fi
    
    # Check if current value exceeds limit
    if [ "$current_value" -gt "$limit" ]; then
        echo "ERROR: Resource limit exceeded for $resource_type: $current_value > $limit" >&2
        return 1
    fi
    
    return 0
}

# Get current resource usage
# Usage: igor_get_resource_usage <resource_type>
igor_get_resource_usage() {
    local resource_type="$1"
    
    case "$resource_type" in
        "memory_mb")
            # Get current used memory in MB (MemTotal - MemAvailable)
            local total_kb avail_kb
            total_kb=$(grep -E '^MemTotal:'     /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
            avail_kb=$(grep -E '^MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
            echo $(( (total_kb - avail_kb) / 1024 ))
            ;;
        "disk_usage_percent")
            # Get disk usage percentage for IGOR_DIR
            local disk_usage
            disk_usage=$(df "${_IGOR_PATHS[IGOR_DIR]}" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
            echo "$disk_usage"
            ;;
        "session_files")
            # Count session files
            local sessions_dir="${_IGOR_PATHS[SESSIONS_DIR]}"
            if [ -d "$sessions_dir" ]; then
                find "$sessions_dir" -name "session_*.json" 2>/dev/null | wc -l
            else
                echo "0"
            fi
            ;;
        "pattern_files")
            # Count pattern files
            local patterns_dir="${_IGOR_PATHS[PATTERNS_DIR]}"
            if [ -d "$patterns_dir" ]; then
                find "$patterns_dir" -name "*.pattern" 2>/dev/null | wc -l
            else
                echo "0"
            fi
            ;;
        "log_file_size")
            # Get total size of log files in bytes
            local log_dirs=("${_IGOR_PATHS[DATA_DIR]}" "/var/log")
            local total_size=0
            for log_dir in "${log_dirs[@]}"; do
                if [ -d "$log_dir" ]; then
                    local dir_size
                    dir_size=$(find "$log_dir" -name "*.log" -type f -exec du -b {} + 2>/dev/null | awk '{sum += $1} END {print sum+0}')
                    total_size=$((total_size + dir_size))
                fi
            done
            echo "$total_size"
            ;;
        "active_processes")
            # Count direct child processes of this shell (not all user processes)
            pgrep -P $$ 2>/dev/null | wc -l
            ;;
        *)
            echo "ERROR: Unknown resource type: $resource_type" >&2
            return 1
            ;;
    esac
}

# Check and enforce resource limits
# Usage: igor_enforce_limits
igor_enforce_limits() {
    local violations=()
    
    # Check session file count
    local session_files
    session_files=$(igor_get_resource_usage "session_files")
    if ! igor_check_limit "max_session_files" "$session_files"; then
        violations+=("Session files: $session_files")
    fi
    
    # Check pattern file count
    local pattern_files
    pattern_files=$(igor_get_resource_usage "pattern_files")
    if ! igor_check_limit "max_pattern_files" "$pattern_files"; then
        violations+=("Pattern files: $pattern_files")
    fi
    
    # Check log file size
    local log_size
    log_size=$(igor_get_resource_usage "log_file_size")
    if ! igor_check_limit "max_file_size_bytes" "$log_size"; then
        violations+=("Log file size: $((log_size / 1024 / 1024))MB")
    fi
    
    # Check active processes
    local active_processes
    active_processes=$(igor_get_resource_usage "active_processes")
    if ! igor_check_limit "max_subprocesses" "$active_processes"; then
        violations+=("Active processes: $active_processes")
    fi
    
    # Report violations
    if [ ${#violations[@]} -gt 0 ]; then
        echo "WARNING: Resource limit violations detected:" >&2
        for violation in "${violations[@]}"; do
            echo "  - $violation" >&2
        done
        return 1
    fi
    
    return 0
}

# Clean up old session files
# Usage: igor_cleanup_old_sessions [max_files_to_keep]
igor_cleanup_old_sessions() {
    local max_files="${1:-20}"
    local sessions_dir="${_IGOR_PATHS[SESSIONS_DIR]}"
    
    if [ ! -d "$sessions_dir" ]; then
        return 0
    fi
    
    # Find and remove oldest session files, keeping the most recent ones
    local session_files=()
    while IFS= read -r -d '' file; do
        session_files+=("$file")
    done < <(find "$sessions_dir" -name "session_*.json" -type f -printf "%T@ %p\0" 2>/dev/null | sort -z -n)
    
    local total_files=${#session_files[@]}
    if [ "$total_files" -gt "$max_files" ]; then
        local files_to_remove=$((total_files - max_files))
        for ((i=0; i<files_to_remove; i++)); do
            local file_to_remove="${session_files[i]#* }"
            rm -f "$file_to_remove" 2>/dev/null || true
        done
        echo "Cleaned up $files_to_remove old session files" >&2
    fi
}

# Clean up old log files
# Usage: igor_cleanup_old_logs [max_age_days]
igor_cleanup_old_logs() {
    local max_age="${1:-30}"
    # Only clean Igor's own data directory — never touch system log directories
    local log_dir="${_IGOR_PATHS[DATA_DIR]}"
    if [ -d "$log_dir" ]; then
        find "$log_dir" -name "*.log" -type f -mtime +"$max_age" -delete 2>/dev/null || true
    fi
}

# Monitor resource usage during AI operations
# Usage: igor_monitor_ai_usage
igor_monitor_ai_usage() {
    local start_time=$(date +%s)
    local start_memory=$(igor_get_resource_usage "memory_mb")
    local start_processes=$(igor_get_resource_usage "active_processes")
    
    # Set up trap to monitor usage
    trap '_igor_log_ai_resource_usage $start_time $start_memory $start_processes' RETURN
}

# Log AI resource usage
# Usage: _igor_log_ai_resource_usage <start_time> <start_memory> <start_processes>
_igor_log_ai_resource_usage() {
    local start_time="$1"
    local start_memory="$2"
    local start_processes="$3"
    
    local end_time=$(date +%s)
    local end_memory=$(igor_get_resource_usage "memory_mb")
    local end_processes=$(igor_get_resource_usage "active_processes")
    
    local duration=$((end_time - start_time))
    local memory_diff=$((end_memory - start_memory))
    local processes_diff=$((end_processes - start_processes))
    
    # Log usage if it's significant
    if [ "$duration" -gt 60 ] || [ ${memory_diff#-} -gt 100 ] || [ ${processes_diff#-} -gt 5 ]; then
        echo "AI resource usage: ${duration}s, memory ${memory_diff:+${memory_diff}}MB, processes ${processes_diff:+${processes_diff#}}" >&2
    fi
}

# Initialize resource management when this module is loaded
igor_resource_init