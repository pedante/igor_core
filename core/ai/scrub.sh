#!/bin/bash
# ==============================================================================
#  IGOR — ai/scrub.sh
#  Enhanced credential scrubbing layer for the AI assistant.
#
#  PURPOSE:
#    Prevent sensitive data (domain, LAN IP, hostname, credentials, API keys,
#    tokens, certificates, private keys) from leaving the machine when calling
#    external AI APIs.
#
#  HOW IT WORKS:
#    1. ai_scrub_build_table()  — called once at session start, reads real
#                                  values from db.env / config.env / system,
#                                  builds two parallel arrays SCRUB_FROM / SCRUB_TO
#    2. ai_scrub_outbound()     — pipes context text through sed, replaces real
#                                  values with [TOKENS] before sending to API
#    3. ai_unscrub_inbound()    — reverses substitution on EXECUTE lines only,
#                                  so commands actually run with real values
#
#  SENSITIVITY TIERS:
#    Tier 1 — OMIT ENTIRELY (never included in context):
#      • DB password, NC admin password, Redis password, JWT secret, API keys,
#        private keys, certificates, tokens, credentials
#
#    Tier 2 — REPLACE WITH TOKEN (sent as placeholder, AI reasons with it):
#      • Domain name           → [IGOR:DOMAIN]
#      • LAN IP                → [IGOR:LAN_IP]
#      • Hostname              → [IGOR:HOSTNAME]
#      • Docker subnet         → [IGOR:DOCKER_NET]
#      • NC admin username     → [IGOR:ADMIN_USER]
#      • DB name               → [IGOR:DB_NAME]
#      • DB user               → [IGOR:DB_USER]
#      • Data path             → [IGOR:DATA_PATH]
#      • Home dir path         → [IGOR:HOME_DIR]
#      • Email addresses       → [IGOR:EMAIL]
#      • Service URLs          → [IGOR:SERVICE_URL]
#      • External IPs          → [IGOR:EXTERNAL_IP]
##
#    Tier 3 — SAFE TO SEND AS-IS:
#      Container names (operational identifiers), Cloudflare IPs (public),
#      OS info, RAM/CPU/load, NC version, HTTP status codes, occ keys/values
#      (after domain/user tokens applied), error messages (paths already tokenised)
#
#  ENHANCEMENTS:
#    - Integration with security configuration system
#    - Expanded sensitive data type detection
#    - Pattern-based scrubbing for unknown sensitive data
#    - Validation of scrubbing effectiveness
# ==============================================================================

# ── Scrub table (parallel arrays) ─────────────────────────────────────────────
SCRUB_FROM=()
SCRUB_TO=()

# ── Enhanced scrubbing patterns from security config ───────────────────────────
# Load security configuration for scrubbing patterns
_SCRUB_PATTERNS=""
_SENSITIVE_FILE_PATTERNS=""

# ── Internal: add a scrub pair ────────────────────────────────────────────────
_scrub_add() {
    local real="$1" token="$2"
    if [ -n "$real" ] && [[ "$real" != \[*\] ]] && [ "${#real}" -gt 0 ]; then
        # Keep the first token assigned to a value for compatibility. If two
        # values would share a reverse token, give later values a unique token.
        local idx existing existing_token suffix=2 candidate used
        for idx in "${!SCRUB_FROM[@]}"; do
            existing="${SCRUB_FROM[$idx]}"
            if [ "$existing" = "$real" ]; then
                return
            fi
            existing_token="${SCRUB_TO[$idx]}"
            if [ "$existing_token" = "$token" ]; then
                while :; do
                    candidate="${token%]}_${suffix}]"
                    used=false
                    for existing_token in "${SCRUB_TO[@]}"; do
                        if [ "$existing_token" = "$candidate" ]; then
                            used=true
                            break
                        fi
                    done
                    if [ "$used" = false ]; then
                        token="$candidate"
                        break
                    fi
                    suffix=$((suffix + 1))
                done
                break
            fi
        done
        SCRUB_FROM+=("$real")
        SCRUB_TO+=("$token")
    fi
}

_scrub_escape_pattern() {
    printf '%s\n' "$1" | sed 's/[.[\*^$\\]/\\&/g; s/|/\\|/g'
}

_scrub_escape_replacement() {
    printf '%s\n' "$1" | sed 's/[&\\|]/\\&/g'
}

_scrub_apply_mapping() {
    local text="$1" from="$2" to="$3" escaped_from escaped_to
    escaped_from=$(_scrub_escape_pattern "$from")
    escaped_to=$(_scrub_escape_replacement "$to")
    printf '%s\n' "$text" | sed "s|${escaped_from}|${escaped_to}|g"
}

_scrub_sorted_indexes() {
    local i j key key_len
    local -a indexes=()
    for i in "${!SCRUB_FROM[@]}"; do indexes+=("$i"); done
    for ((i = 1; i < ${#indexes[@]}; i++)); do
        key="${indexes[$i]}"
        key_len=${#SCRUB_FROM[$key]}
        j=$((i - 1))
        while ((j >= 0 && ${#SCRUB_FROM[${indexes[$j]}]} < key_len)); do
            indexes[$((j + 1))]="${indexes[$j]}"
            j=$((j - 1))
        done
        indexes[$((j + 1))]="$key"
    done
    printf '%s\n' "${indexes[@]}"
}

# ── Enhanced: detect and scrub sensitive patterns ───────────────────────────────
_scrub_sensitive_patterns() {
    local text="$1"
    local systemd_at_sentinel="__IGOR_SYSTEMD_AT__"

    # systemd instance units such as user@1000.service look like email
    # addresses to generic privacy regexes. Protect their @ while applying
    # unknown-value fallbacks, then restore it below.
    text=$(printf '%s\n' "$text" | sed -E 's/([a-zA-Z0-9_.:+-]+)@([a-zA-Z0-9_.:+-]+\.(service|socket|target|timer|mount|path|slice|scope|device|automount|swap))([[:space:]]|$)/\1__IGOR_SYSTEMD_AT__\2\4/g')

    # Enhanced email detection and scrubbing
    text=$(printf '%s\n' "$text" | sed -E 's/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/[IGOR:EMAIL]/g')
    
    # Enhanced URL detection and scrubbing
    text=$(echo "$text" | sed -E 's|https?://[^[:space:]]+|[IGOR:SERVICE_URL]|g')
    
    # External IP detection
    text=$(echo "$text" | sed -E 's/\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/[IGOR:EXTERNAL_IP]/g')
    
    # Port number scrubbing (if not in safe range)
    text=$(echo "$text" | sed -E 's/:[0-9]{4,5}\b/[IGOR:PORT]/g')
    
    # UUID scrubbing
    text=$(echo "$text" | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[IGOR:UUID]/gi')
    
    # MAC address scrubbing
    text=$(echo "$text" | sed -E 's/[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}/[IGOR:MAC_ADDRESS]/g')
    
    # Basic auth scrubbing
    text=$(printf '%s\n' "$text" | sed -E 's/[a-zA-Z0-9._%+-]+:[^[:space:]]+@[a-zA-Z0-9.-]+/[IGOR:BASIC_AUTH]/g')

    text="${text//${systemd_at_sentinel}/@}"
    printf '%s\n' "$text"
}

# ── Enhanced: load scrubbing patterns from security config ─────────────────────
_load_scrub_config() {
    # Load patterns from security configuration
    if [[ -n "${IGOR_SCRUB_PATTERNS:-}" ]]; then
        _SCRUB_PATTERNS="$IGOR_SCRUB_PATTERNS"
    else
        # Default enhanced patterns
        _SCRUB_PATTERNS="password|secret|key|token|api_key|private_key|credential|auth|jwt|certificate|cert|pem|p12|pfx"
    fi
    
    if [[ -n "${IGOR_SENSITIVE_FILE_PATTERNS:-}" ]]; then
        _SENSITIVE_FILE_PATTERNS="$IGOR_SENSITIVE_FILE_PATTERNS"
    else
        # Default sensitive file patterns
        _SENSITIVE_FILE_PATTERNS=".*\.env$|.*\.key$|.*\.pem$|.*\.crt$|.*\.p12$|.*\.pfx$|.*\.conf$|.*\.config$"
    fi
}

# ── Enhanced: validate scrubbing effectiveness ──────────────────────────────────
_validate_scrubbing() {
    local text="$1"
    local issues=0
    
    # Check for remaining sensitive patterns
    if echo "$text" | grep -iE "($_SCRUB_PATTERNS)" >/dev/null 2>&1; then
        echo "WARNING: Potential sensitive content remaining after scrubbing" >&2
        issues=$((issues + 1))
    fi
    
    # Check for remaining IPs
    if echo "$text" | grep -E '\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b' >/dev/null 2>&1; then
        echo "WARNING: Potential IP addresses remaining after scrubbing" >&2
        issues=$((issues + 1))
    fi
    
    # Check for remaining email addresses
    if echo "$text" | grep -E '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' >/dev/null 2>&1; then
        echo "WARNING: Potential email addresses remaining after scrubbing" >&2
        issues=$((issues + 1))
    fi
    
    return $issues
}

# ── Enhanced: build the substitution table ───────────────────────────────────────
# Call once at the start of an AI session.
ai_scrub_build_table() {
    SCRUB_FROM=()
    SCRUB_TO=()
    
    # Load scrub configuration
    _load_scrub_config
    
    local hostname_val lan_ip home_dir
    hostname_val=$(hostname 2>/dev/null)
    lan_ip=""
    local _lan_ips _lan_ip
    _lan_ips=$(hostname -I 2>/dev/null) || _lan_ips=""
    for _lan_ip in $_lan_ips; do
        case "$_lan_ip" in
            *.*) lan_ip="$_lan_ip"; break ;;
        esac
    done
    if [ -z "$lan_ip" ] && command -v ip >/dev/null 2>&1; then
        lan_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '
            { for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }
        ')
    fi
    if [ -z "$lan_ip" ] && command -v ip >/dev/null 2>&1; then
        lan_ip=$(ip -4 -o addr show scope global 2>/dev/null | awk 'NR == 1 {split($4, a, "/"); print a[1]}')
    fi
    home_dir="$HOME"
    
    _scrub_add "$hostname_val"  "[IGOR:HOSTNAME]"
    _scrub_add "$lan_ip"        "[IGOR:LAN_IP]"
    _scrub_add "$home_dir"      "[IGOR:HOME_DIR]"
    
    # Enhanced domain handling (multiple domains)
    if [ -f "${IGOR_DIR}/secrets/db.env" ]; then
        local domains domain
        domains=$(grep "^NEXTCLOUD_TRUSTED_DOMAINS=" "${IGOR_DIR}/secrets/db.env" 2>/dev/null \
                 | cut -d= -f2- | tr ',' ' ' | tr '"' ' ')
        # Prefer the externally useful name for the stable DOMAIN token. Keep
        # localhost as a distinct alias when it is also configured.
        for domain in $domains; do
            domain=$(echo "$domain" | xargs)  # trim whitespace
            [ -n "$domain" ] && [ "$domain" != "localhost" ] && \
                _scrub_add "$domain" "[IGOR:DOMAIN]"
        done
        for domain in $domains; do
            domain=$(echo "$domain" | xargs)
            [ -n "$domain" ] && [ "$domain" = "localhost" ] && \
                _scrub_add "$domain" "[IGOR:DOMAIN]"
        done
    fi
    
    # NC admin username and other users (NOT password)
    local admin_user
    admin_user=$(grep "^NEXTCLOUD_ADMIN_USER=" "${IGOR_DIR}/secrets/db.env" 2>/dev/null \
                 | cut -d= -f2-)
    _scrub_add "$admin_user" "[IGOR:ADMIN_USER]"
    
    # Enhanced database configuration
    local db_name db_user db_host db_port
    db_name=$(grep "^POSTGRES_DB="   "${IGOR_DIR}/secrets/db.env" 2>/dev/null | cut -d= -f2-)
    db_user=$(grep "^POSTGRES_USER=" "${IGOR_DIR}/secrets/db.env" 2>/dev/null | cut -d= -f2-)
    db_host=$(grep "^POSTGRES_HOST=" "${IGOR_DIR}/secrets/db.env" 2>/dev/null | cut -d= -f2-)
    db_port=$(grep "^POSTGRES_PORT=" "${IGOR_DIR}/secrets/db.env" 2>/dev/null | cut -d= -f2-)
    
    _scrub_add "$db_name" "[IGOR:DB_NAME]"
    _scrub_add "$db_user" "[IGOR:DB_USER]"
    [ -n "$db_host" ] && _scrub_add "$db_host" "[IGOR:DB_HOST]"
    [ -n "$db_port" ] && _scrub_add "$db_port" "[IGOR:DB_PORT]"
    
    # Enhanced path handling with security config
    local data_path hd_mount
    if [ -n "${NC_DATA:-}" ]; then
        data_path="$NC_DATA"
    elif declare -f igor_get_security_config >/dev/null 2>&1; then
        data_path="$(igor_get_security_config "IGOR_NC_DATA")"
    fi
    if [ -n "${HD_MOUNT:-}" ]; then
        hd_mount="$HD_MOUNT"
    elif declare -f igor_get_security_config >/dev/null 2>&1; then
        hd_mount="$(igor_get_security_config "IGOR_HD_MOUNT")"
    fi
    
    _scrub_add "$data_path" "[IGOR:DATA_PATH]"
    _scrub_add "$hd_mount"  "[IGOR:HD_MOUNT]"
    
    # Container names are operational identifiers, not credentials. Avoid
    # literal substring mappings here: a short configured name can otherwise
    # corrupt unrelated unit/package names before the model sees them.
    
    # Enhanced Docker network configuration
    local docker_subnet docker_gw docker_network_name
    if declare -f igor_get_security_config >/dev/null 2>&1; then
        docker_network_name="$(igor_get_security_config "IGOR_DOCKER_NETWORK")"
    fi
    
    docker_subnet=$(docker network inspect "$docker_network_name" \
                    --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null \
                    | head -1)
    if [ -z "$docker_subnet" ]; then
        docker_subnet=$(docker network ls --format '{{.Name}}' 2>/dev/null \
                        | grep -E "_default$" | head -1 \
                        | xargs -I{} docker network inspect {} \
                            --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null \
                        | head -1)
    fi
    _scrub_add "$docker_subnet" "[IGOR:DOCKER_NET]"
    
    if [ -n "$docker_subnet" ]; then
        docker_gw=$(echo "$docker_subnet" | sed 's|\.[0-9]*/.*|.1|')
        _scrub_add "$docker_gw" "[IGOR:DOCKER_GW]"
    fi
    
    # Port configurations from security config
    local ports
    ports="$IGOR_WEB_PORT $IGOR_PHPFPM_PORT $IGOR_POSTGRES_PORT $IGOR_REDIS_PORT $IGOR_ONLYOFFICE_PORT"
    for port in $ports; do
        if [ -n "$port" ] && [ "$port" -ne 80 ] && [ "$port" -ne 443 ]; then
            _scrub_add ":$port" "[IGOR:PORT]"
        fi
    done
    
    # Enhanced: scrub any service URLs from configuration
    local service_urls
    if [ -f "${IGOR_DIR}/config/defaults.env" ]; then
        service_urls=$(grep -E "^[A-Z_]*URL=" "${IGOR_DIR}/config/defaults.env" 2>/dev/null | cut -d= -f2-)
        for url in $service_urls; do
            url=$(echo "$url" | xargs)  # trim whitespace
            [ -n "$url" ] && _scrub_add "$url" "[IGOR:SERVICE_URL]"
        done
    fi
}

# ── Enhanced: scrub outbound text ──────────────────────────────────────────────
ai_scrub_outbound() {
    local text="$1"
    local i from to

    # Apply reversible mappings first. Generic URL/IP patterns must not turn a
    # known value into a generic token that cannot be restored.
    while IFS= read -r i; do
        [ -n "$i" ] || continue
        from="${SCRUB_FROM[$i]}"
        to="${SCRUB_TO[$i]}"
        text=$(_scrub_apply_mapping "$text" "$from" "$to")
    done < <(_scrub_sorted_indexes)

    # Protect labelled tokens while handling unknown values. This keeps
    # https://[IGOR:DOMAIN]/status useful to the model.
    local -a protected_tokens=() protected_sentinels=()
    local token sentinel token_index=0
    while [[ "$text" =~ (\[IGOR:[A-Z0-9_]+\]) ]]; do
        token="${BASH_REMATCH[1]}"
        sentinel="__IGOR_TOKEN_${token_index}__"
        text="${text/"$token"/$sentinel}"
        protected_tokens+=("$token")
        protected_sentinels+=("$sentinel")
        token_index=$((token_index + 1))
    done
    # The URL fallback pattern sees a protected token as part of a URL. Hide
    # the scheme while that pass runs, then put it back below.
    for sentinel in "${protected_sentinels[@]}"; do
        text="${text//"https://${sentinel}"/__IGOR_HTTPS__${sentinel}}"
        text="${text//"http://${sentinel}"/__IGOR_HTTP__${sentinel}}"
    done
    text=$(_scrub_sensitive_patterns "$text")
    text="${text//__IGOR_HTTPS__/https://}"
    text="${text//__IGOR_HTTP__/http://}"
    for token_index in "${!protected_tokens[@]}"; do
        text="${text//"${protected_sentinels[$token_index]}"/${protected_tokens[$token_index]}}"
    done
    
    # Final pass: catch any remaining literals registered by the scrub engine
    # (e.g. values from secrets/*.env not covered by the AI token table)
    if declare -f igor_scrub >/dev/null 2>&1; then
        text=$(igor_scrub "$text")
    fi
    
    # Validate scrubbing effectiveness (in debug mode)
    if [ "${IGOR_VERBOSE:-false}" = "true" ]; then
        if ! _validate_scrubbing "$text"; then
            echo "DEBUG: Scrubbing validation detected potential issues" >&2
        fi
    fi
    
    printf '%s\n' "$text"
}

# ── Enhanced: unscrub inbound commands ────────────────────────────────────────────
# Reverses substitution on a trusted command field. Callers decide whether a
# field is executable; dispatchers pass already-extracted command text.
ai_unscrub_inbound() {
    local text="$1"
    local i from to

    while IFS= read -r i; do
        [ -n "$i" ] || continue
        from="${SCRUB_FROM[$i]}"
        to="${SCRUB_TO[$i]}"
        text=$(_scrub_apply_mapping "$text" "$to" "$from")
    done < <(_scrub_sorted_indexes)
    printf '%s\n' "$text"
}

# ── Enhanced: debug print the scrub table ────────────────────────────────────────
ai_scrub_debug_table() {
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │  IGOR ENHANCED SCRUB TABLE — what stays on the machine          │"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""
    printf "  %-40s  →  %s\n" "REAL VALUE" "API TOKEN"
    printf "  %-40s  →  %s\n" "───────────────────────────────────────────" "──────────────────"
    local i
    for i in "${!SCRUB_FROM[@]}"; do
        local display="${SCRUB_FROM[$i]}"
        [ "${#display}" -gt 40 ] && display="${display:0:37}..."
        printf "  %-40s  →  %s\n" "$display" "${SCRUB_TO[$i]}"
    done
    echo ""
    echo "  Active scrub patterns: $_SCRUB_PATTERNS"
    echo "  Sensitive file patterns: $_SENSITIVE_FILE_PATTERNS"
    echo ""
}

# ── Enhanced: secure file content scrubbing ─────────────────────────────────────
ai_scrub_file_content() {
    local file_path="$1"
    
    # Check if file matches sensitive patterns
    if echo "$file_path" | grep -qE "$_SENSITIVE_FILE_PATTERNS"; then
        echo "WARNING: Refusing to read sensitive file: $file_path" >&2
        return 1
    fi
    
    # Check if file exists and is readable
    if [ ! -f "$file_path" ]; then
        echo "ERROR: File not found: $file_path" >&2
        return 1
    fi
    
    if [ ! -r "$file_path" ]; then
        echo "ERROR: File not readable: $file_path" >&2
        return 1
    fi
    
    # Read file content and scrub it
    local content
    content=$(cat "$file_path")
    ai_scrub_outbound "$content"
}

# ── Enhanced: validate file paths before processing ──────────────────────────────
ai_validate_file_path() {
    local path="$1"
    
    # Use path resolution validation from security module
    if declare -f validate_file_path >/dev/null 2>&1; then
        if ! validate_file_path "$path"; then
            echo "ERROR: Invalid file path: $path" >&2
            return 1
        fi
    fi
    
    # Additional file-specific validation
    local basename
    basename=$(basename "$path")
    
    # Check for obviously sensitive files
    if echo "$basename" | grep -qiE "($_SCRUB_PATTERNS)"; then
        echo "ERROR: Potential sensitive file: $path" >&2
        return 1
    fi
    
    return 0
}
