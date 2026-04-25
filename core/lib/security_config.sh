#!/bin/bash
# ==============================================================================
#  IGOR — core/lib/security_config.sh
#  Centralized security configuration and hardcoded value management.
#
#  This module centralizes all hardcoded values that were previously scattered
#  throughout the codebase, addressing critical security vulnerabilities and
#  improving maintainability.
#
#  Configuration precedence:
#    1. Hardcoded security defaults (this file)
#    2. config/defaults.env (repository defaults)
#    3. $NEXUS_CONFIG/config.env (user overrides)
#    4. Environment variables (runtime)
# ==============================================================================

# ── Security Configuration Defaults ───────────────────────────────────────────────
# These defaults can be overridden by environment variables or config files

# ── Network & Port Configuration ──────────────────────────────────────────────────
# Web server ports
export IGOR_WEB_PORT="${IGOR_WEB_PORT:-8080}"
export IGOR_WEB_SSL_PORT="${IGOR_WEB_SSL_PORT:-8443}"

# PHP-FPM port
export IGOR_PHPFPM_PORT="${IGOR_PHPFPM_PORT:-9000}"

# Database ports
export IGOR_POSTGRES_PORT="${IGOR_POSTGRES_PORT:-5432}"
export IGOR_REDIS_PORT="${IGOR_REDIS_PORT:-6379}"

# OnlyOffice port
export IGOR_ONLYOFFICE_PORT="${IGOR_ONLYOFFICE_PORT:-8081}"

# ── Docker Configuration ──────────────────────────────────────────────────────────
export IGOR_DOCKER_NETWORK="${IGOR_DOCKER_NETWORK:-igor}"
export IGOR_DOCKER_COMPOSE_FILE="${IGOR_DOCKER_COMPOSE_FILE:-${IGOR_DIR}/config/stacks/nextcloud/docker-compose.yml}"

# ── Container Names (configurable) ────────────────────────────────────────────────
export IGOR_CONTAINER_WEB="${IGOR_CONTAINER_WEB:-web}"
export IGOR_CONTAINER_APP="${IGOR_CONTAINER_APP:-app}"
export IGOR_CONTAINER_DB="${IGOR_CONTAINER_DB:-db}"
export IGOR_CONTAINER_CACHE="${IGOR_CONTAINER_CACHE:-cache}"
export IGOR_CONTAINER_CRON="${IGOR_CONTAINER_CRON:-cron}"
export IGOR_CONTAINER_ONLYOFFICE="${IGOR_CONTAINER_ONLYOFFICE:-onlyoffice}"

# ── Path Configuration ─────────────────────────────────────────────────────────────
# Data directories
export IGOR_DATA_DIR="${IGOR_DATA_DIR:-${IGOR_DIR}/data}"
export IGOR_RUNTIME_DIR="${IGOR_RUNTIME_DIR:-${IGOR_DIR}/data/runtime}"
export IGOR_SESSIONS_DIR="${IGOR_SESSIONS_DIR:-${IGOR_DIR}/data/sessions}"
export IGOR_BACKUPS_DIR="${IGOR_BACKUPS_DIR:-${IGOR_DIR}/data/backups}"
export IGOR_REPORTS_DIR="${IGOR_REPORTS_DIR:-${IGOR_DIR}/data/reports}"
export IGOR_ALERTS_DIR="${IGOR_ALERTS_DIR:-${IGOR_DIR}/data/alerts}"
export IGOR_PATTERNS_DIR="${IGOR_PATTERNS_DIR:-${IGOR_DIR}/data/patterns}"
export IGOR_KNOWLEDGE_DIR="${IGOR_KNOWLEDGE_DIR:-${IGOR_DIR}/knowledge}"

# External mount points
export IGOR_HD_MOUNT="${IGOR_HD_MOUNT:-/mnt/nextclouddata}"
export IGOR_NC_DATA="${IGOR_NC_DATA:-${IGOR_HD_MOUNT}/next}"

# ── Security Limits & Thresholds ────────────────────────────────────────────────────
# AI token limits
export IGOR_AI_MAX_TOKENS="${IGOR_AI_MAX_TOKENS:-100000}"
export IGOR_AI_MAX_CONTEXT_TOKENS="${IGOR_AI_MAX_CONTEXT_TOKENS:-180000}"
export IGOR_AI_SESSION_TIMEOUT="${IGOR_AI_SESSION_TIMEOUT:-3600}"

# File size limits
export IGOR_MAX_LOG_SIZE="${IGOR_MAX_LOG_SIZE:-5242880}"  # 5MB
export IGOR_MAX_UPLOAD_SIZE="${IGOR_MAX_UPLOAD_SIZE:-10485760}"  # 10MB
export IGOR_MAX_SESSION_FILES="${IGOR_MAX_SESSION_FILES:-1000}"

# Resource limits
export IGOR_MAX_PROCESSES="${IGOR_MAX_PROCESSES:-100}"
export IGOR_MAX_MEMORY_PERCENT="${IGOR_MAX_MEMORY_PERCENT:-80}"

# ── AI Configuration ───────────────────────────────────────────────────────────────
# Model and provider settings
export IGOR_AI_DEFAULT_MODEL="${IGOR_AI_DEFAULT_MODEL:-claude-haiku-4-5}"
export IGOR_AI_DEFAULT_PROVIDER="${IGOR_AI_DEFAULT_PROVIDER:-anthropic}"
export IGOR_AI_TEMPERATURE="${IGOR_AI_TEMPERATURE:-0.7}"

# Security settings
export IGOR_AI_EXECUTIVE_MODE="${IGOR_AI_EXECUTIVE_MODE:-false}"
export IGOR_AI_HYBRID_MODE="${IGOR_AI_HYBRID_MODE:-false}"
export IGOR_AI_LOOP_LIMIT="${IGOR_AI_LOOP_LIMIT:-15}"

# Context configuration
export IGOR_AI_CONTEXT_REFRESH_INTERVAL="${IGOR_AI_CONTEXT_REFRESH_INTERVAL:-300}"  # 5 minutes
export IGOR_AI_MAX_MESSAGES="${IGOR_AI_MAX_MESSAGES:-50}"
export IGOR_AI_SESSION_COST_LIMIT="${IGOR_AI_SESSION_COST_LIMIT:-1.00}"  # $1.00

# ── Template & Configuration Mappings ──────────────────────────────────────────────
# Template variable mappings (fixes template-environment mismatch)
export IGOR_TEMPLATE_MAPPING_DOMAIN="${IGOR_TEMPLATE_MAPPING_DOMAIN:-NEXTCLOUD_DOMAIN}"
export IGOR_TEMPLATE_MAPPING_HOST="${IGOR_TEMPLATE_MAPPING_HOST:-HOSTNAME}"
export IGOR_TEMPLATE_MAPPING_IP="${IGOR_TEMPLATE_MAPPING_IP:-LAN_IP}"
export IGOR_TEMPLATE_MAPPING_USER="${IGOR_TEMPLATE_MAPPING_USER:-ADMIN_USER}"
export IGOR_TEMPLATE_MAPPING_DB="${IGOR_TEMPLATE_MAPPING_DB:-DB_NAME}"
export IGOR_TEMPLATE_MAPPING_DATA="${IGOR_TEMPLATE_MAPPING_DATA:-DATA_PATH}"

# ── Security Validation Patterns ──────────────────────────────────────────────────
# These patterns are used by input validation to ensure security

# Allowed file paths (regex patterns)
export IGOR_ALLOWED_PATH_PATTERNS="${IGOR_ALLOWED_PATH_PATTERNS:-^(/mnt/nextclouddata|/var/www/html|/tmp|${IGOR_DIR})}"

# Allowed commands (whitelist)
export IGOR_ALLOWED_COMMANDS="${IGOR_ALLOWED_COMMANDS:-^(docker|ls|cat|grep|find|ps|df|du|curl|wget|python3|bash|occ)$}"

# Allowed hostnames (regex)
export IGOR_ALLOWED_HOSTNAME_PATTERNS="${IGOR_ALLOWED_HOSTNAME_PATTERNS:-^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$}"

# Allowed numeric ranges
export IGOR_ALLOWED_PORT_RANGE="${IGOR_ALLOWED_PORT_RANGE:-1024-65535}"
export IGOR_ALLOWED_UID_RANGE="${IGOR_ALLOWED_UID_RANGE:-1000-65534}"
export IGOR_ALLOWED_GID_RANGE="${IGOR_ALLOWED_GID_RANGE:-1000-65534}"

# ── Credential Scrubbing Patterns ──────────────────────────────────────────────────
# Patterns for detecting and scrubbing credentials
export IGOR_SCRUB_PATTERNS="${IGOR_SCRUB_PATTERNS:-password|secret|key|token|api_key|private_key|credential}"

# Sensitive file patterns
export IGOR_SENSITIVE_FILE_PATTERNS="${IGOR_SENSITIVE_FILE_PATTERNS:-.*\.env$|.*\.key$|.*\.pem$|.*\.crt$}"

# ── File Locking Configuration ─────────────────────────────────────────────────────
# Lock file settings
export IGOR_LOCK_DIR="${IGOR_LOCK_DIR:-${IGOR_RUNTIME_DIR}/locks}"
export IGOR_LOCK_TIMEOUT="${IGOR_LOCK_TIMEOUT:-30}"  # seconds
export IGOR_LOCK_RETRY_INTERVAL="${IGOR_LOCK_RETRY_INTERVAL:-1}"  # second

# ── Error Handling Configuration ───────────────────────────────────────────────────
# Error reporting settings
export IGOR_ERROR_LOG_FILE="${IGOR_ERROR_LOG_FILE:-${IGOR_RUNTIME_DIR}/error.log}"
export IGOR_ERROR_MAX_SIZE="${IGOR_ERROR_MAX_SIZE:-1048576}"  # 1MB
export IGOR_ERROR_KEEP_COUNT="${IGOR_ERROR_KEEP_COUNT:-10}"

# ── Initialize Security Configuration ─────────────────────────────────────────────
igor_init_security_config() {
    # Create required directories
    mkdir -p "${IGOR_RUNTIME_DIR}" 2>/dev/null || true
    mkdir -p "${IGOR_LOCK_DIR}" 2>/dev/null || true
    mkdir -p "${IGOR_SESSIONS_DIR}" 2>/dev/null || true
    mkdir -p "${IGOR_BACKUPS_DIR}" 2>/dev/null || true
    mkdir -p "${IGOR_REPORTS_DIR}" 2>/dev/null || true
    mkdir -p "${IGOR_ALERTS_DIR}" 2>/dev/null || true
    mkdir -p "${IGOR_PATTERNS_DIR}" 2>/dev/null || true
    mkdir -p "${IGOR_KNOWLEDGE_DIR}" 2>/dev/null || true
    
    # Validate critical security settings
    _validate_security_config
}

# ── Security Configuration Validation ───────────────────────────────────────────────
_validate_security_config() {
    local errors=0
    
    # Validate port ranges
    if [[ ! "$IGOR_WEB_PORT" =~ ^[0-9]+$ ]] || [ "$IGOR_WEB_PORT" -lt 1024 ] || [ "$IGOR_WEB_PORT" -gt 65535 ]; then
        echo "WARNING: IGOR_WEB_PORT is not in valid range (1024-65535): $IGOR_WEB_PORT" >&2
        errors=$((errors + 1))
    fi
    
    # Validate path existence
    if [ ! -d "$IGOR_DIR" ]; then
        echo "ERROR: IGOR_DIR does not exist: $IGOR_DIR" >&2
        errors=$((errors + 1))
    fi
    
    # Validate directory creation
    if [ ! -d "$IGOR_RUNTIME_DIR" ]; then
        echo "ERROR: Failed to create runtime directory: $IGOR_RUNTIME_DIR" >&2
        errors=$((errors + 1))
    fi
    
    # Return validation status
    [ $errors -eq 0 ]
}

# ── Get Security Configuration Value ────────────────────────────────────────────────
# Usage: igor_get_security_config <key> [default_value]
igor_get_security_config() {
    local key="$1"
    local default="${2:-}"
    
    # Check if the variable is set and not empty
    if [[ -n "${!key+x}" ]] && [[ -n "${!key}" ]]; then
        echo "${!key}"
    else
        echo "$default"
    fi
}

# ── Set Security Configuration Value ────────────────────────────────────────────────
# Usage: igor_set_security_config <key> <value>
igor_set_security_config() {
    local key="$1"
    local value="$2"
    
    # Validate the value if it's a port
    if [[ "$key" =~ PORT$ ]] && [[ "$value" =~ ^[0-9]+$ ]]; then
        if [ "$value" -lt 1024 ] || [ "$value" -gt 65535 ]; then
            echo "ERROR: Port value out of range (1024-65535): $value" >&2
            return 1
        fi
    fi
    
    # Set the value
    export "$key"="$value"
    
    # Update runtime state if needed
    if declare -f _ai_update_state &>/dev/null; then
        _ai_update_state
    fi
}

# ── Auto-initialize on module load ─────────────────────────────────────────────────
igor_init_security_config