#!/bin/bash
# ==============================================================================
#  IGOR — diagnose/roles.sh
#  Container role detection — infers functional role from image name.
#
#  Provides:
#    • _diag_detect_roles()      — populate global _DIAG_ROLES assoc array
#    • _diag_role_for_service()  — return role string for a service name
#    • _diag_get_service_image() — return image name for a running service
# ==============================================================================

# ── Role detection ─────────────────────────────────────────────────────────────
# Populates the global _DIAG_ROLES associative array:
#   Keys: web | app | db | cache | tunnel | cron | onlyoffice
#   Values: compose service name (empty if role not found)
#
# Tolerant of non-standard service names — detects by image name, not service name.
# Falls back gracefully if docker is not available.
_diag_detect_roles() {
    declare -gA _DIAG_ROLES=()

    if ! command -v docker &>/dev/null; then
        _diag_log "roles: docker not available — skipping role detection"
        return 1
    fi

    local services
    services=$(docker compose config --services 2>/dev/null) || {
        _diag_log "roles: docker compose config --services failed"
        return 1
    }

    [ -z "$services" ] && return 0

    # Get all container IDs for this compose project in one call
    local container_ids
    container_ids=$(docker compose ps -q 2>/dev/null)

    local svc image
    while IFS= read -r svc; do
        [ -z "$svc" ] && continue

        # Try to get image from running container first, then from config
        image=$(_diag_get_service_image "$svc")

        if [ -z "$image" ]; then
            _diag_log "roles: could not determine image for service '${svc}'"
            continue
        fi

        # Normalise to lowercase for matching
        local img_lower
        img_lower=$(echo "$image" | tr '[:upper:]' '[:lower:]')

        case "$img_lower" in
            *nginx*|*openresty*)
                _DIAG_ROLES[web]="$svc"
                ;;
            *nextcloud*|*php*fpm*|*php-fpm*)
                # Could be app or cron — check for published ports to distinguish
                if _diag_service_has_published_port "$svc"; then
                    _DIAG_ROLES[app]="$svc"
                else
                    # If we already have an app, this is cron (same image, no port)
                    if [ -n "${_DIAG_ROLES[app]:-}" ]; then
                        _DIAG_ROLES[cron]="$svc"
                    else
                        _DIAG_ROLES[app]="$svc"
                    fi
                fi
                ;;
            *postgres*|*postgresql*|*mysql*|*mariadb*)
                _DIAG_ROLES[db]="$svc"
                ;;
            *redis*|*valkey*|*keydb*)
                _DIAG_ROLES[cache]="$svc"
                ;;
            *cloudflared*|*cloudflare*)
                _DIAG_ROLES[tunnel]="$svc"
                ;;
            *onlyoffice*)
                _DIAG_ROLES[onlyoffice]="$svc"
                ;;
            *)
                # Fallback: check service name for hints
                local svc_lower
                svc_lower=$(echo "$svc" | tr '[:upper:]' '[:lower:]')
                case "$svc_lower" in
                    *web*|*nginx*|*proxy*)     [ -z "${_DIAG_ROLES[web]:-}"    ] && _DIAG_ROLES[web]="$svc" ;;
                    *app*|*nc*|*nextcloud*)    [ -z "${_DIAG_ROLES[app]:-}"    ] && _DIAG_ROLES[app]="$svc" ;;
                    *db*|*database*|*postgres*|*mysql*) [ -z "${_DIAG_ROLES[db]:-}" ] && _DIAG_ROLES[db]="$svc" ;;
                    *redis*|*cache*)           [ -z "${_DIAG_ROLES[cache]:-}"  ] && _DIAG_ROLES[cache]="$svc" ;;
                    *cron*|*worker*)           [ -z "${_DIAG_ROLES[cron]:-}"   ] && _DIAG_ROLES[cron]="$svc" ;;
                    *tunnel*|*cloudflare*)     [ -z "${_DIAG_ROLES[tunnel]:-}" ] && _DIAG_ROLES[tunnel]="$svc" ;;
                esac
                ;;
        esac
    done <<< "$services"

    # Second pass: if we have app but no cron, look for second nextcloud-image service
    if [ -n "${_DIAG_ROLES[app]:-}" ] && [ -z "${_DIAG_ROLES[cron]:-}" ]; then
        local app_img
        app_img=$(_diag_get_service_image "${_DIAG_ROLES[app]}" | tr '[:upper:]' '[:lower:]')
        while IFS= read -r svc; do
            [ -z "$svc" ] && continue
            [ "$svc" = "${_DIAG_ROLES[app]}" ] && continue
            local other_img
            other_img=$(_diag_get_service_image "$svc" | tr '[:upper:]' '[:lower:]')
            if [ "$other_img" = "$app_img" ] && ! _diag_service_has_published_port "$svc"; then
                _DIAG_ROLES[cron]="$svc"
                break
            fi
        done <<< "$services"
    fi

    # Log what we found
    local role
    for role in web app db cache tunnel cron onlyoffice; do
        if [ -n "${_DIAG_ROLES[$role]:-}" ]; then
            _diag_log "roles: ${role} → ${_DIAG_ROLES[$role]}"
        fi
    done

    return 0
}

# ── Get image for a service ────────────────────────────────────────────────────
# Tries running container first (most accurate), then compose config parse.
_diag_get_service_image() {
    local svc="$1"

    # Try from running container
    local cid
    cid=$(docker compose ps -q "$svc" 2>/dev/null | head -1)
    if [ -n "$cid" ]; then
        local img
        img=$(docker inspect --format '{{.Config.Image}}' "$cid" 2>/dev/null)
        if [ -n "$img" ]; then
            echo "$img"
            return 0
        fi
    fi

    # Fallback: parse docker compose config text output with grep/awk
    # Look for the service block and extract the image: line
    local config_text
    config_text=$(docker compose config 2>/dev/null) || return 1

    # Extract image line for this service using Python json (compose config --format json
    # available in Compose v2.12+; fall back to text parsing)
    local img
    img=$(docker compose config --format json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    svc = d.get('services', {}).get('${svc}', {})
    print(svc.get('image', ''))
except Exception:
    pass
" 2>/dev/null)

    if [ -n "$img" ]; then
        echo "$img"
        return 0
    fi

    # Last resort: grep the text config
    echo "$config_text" | awk "/^  ${svc}:/{found=1} found && /^    image:/{print \$2; exit}"
    return 0
}

# ── Check if a service has any published ports ─────────────────────────────────
_diag_service_has_published_port() {
    local svc="$1"
    local cid
    cid=$(docker compose ps -q "$svc" 2>/dev/null | head -1)
    [ -z "$cid" ] && return 1

    local ports
    ports=$(docker inspect --format '{{range $k, $v := .NetworkSettings.Ports}}{{if $v}}{{$k}}{{end}}{{end}}' "$cid" 2>/dev/null)
    [ -n "$ports" ]
}

# ── Return role for a service name ─────────────────────────────────────────────
_diag_role_for_service() {
    local svc="$1"
    local role
    for role in web app db cache tunnel cron onlyoffice; do
        if [ "${_DIAG_ROLES[$role]:-}" = "$svc" ]; then
            echo "$role"
            return 0
        fi
    done
    echo "unknown"
    return 1
}

# ── Summary of detected roles ──────────────────────────────────────────────────
_diag_roles_summary() {
    local parts=()
    local role
    for role in web app db cache tunnel cron onlyoffice; do
        if [ -n "${_DIAG_ROLES[$role]:-}" ]; then
            parts+=("${role}=${_DIAG_ROLES[$role]}")
        fi
    done
    if [ ${#parts[@]} -eq 0 ]; then
        echo "(no roles detected)"
    else
        local IFS=', '
        echo "${parts[*]}"
    fi
}
