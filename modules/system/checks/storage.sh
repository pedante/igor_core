#!/bin/bash
# ==============================================================================
#  IGOR — healing/checks/storage.sh
#  Storage and filesystem health check.
#
#  Checks disk usage, external HD mount, NC data dir existence and ownership.
# ==============================================================================

CHECK_NAME="storage"
CHECK_DESCRIPTION="Disk usage, HD mount, NC data directory ownership"
CHECK_SCHEDULE="300"

# PATTERN_HINT disk_full "Root disk is critically full" CHANGE "docker system prune -f"
# PATTERN_HINT hd_not_mounted "External HD not mounted at HD_MOUNT" CHANGE "sudo mount -a"
# PATTERN_HINT nc_data_wrong_owner "NC data dir has wrong ownership" CHANGE "sudo chown -R 1004:1004 /mnt/nextclouddata/next"

run_check() {
    # ── Root filesystem usage ─────────────────────────────────────────────────
    local root_pct
    root_pct=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')

    if [ -n "$root_pct" ] && [ "$root_pct" -ge 95 ] 2>/dev/null; then
        echo "CHECK_RESULT CRITICAL disk_critical Root filesystem at ${root_pct}% — dangerously full"
    elif [ -n "$root_pct" ] && [ "$root_pct" -ge 85 ] 2>/dev/null; then
        echo "CHECK_RESULT FAIL disk_full Root filesystem at ${root_pct}% — action required"
    elif [ -n "$root_pct" ] && [ "$root_pct" -ge 75 ] 2>/dev/null; then
        echo "CHECK_RESULT WARN disk_high Root filesystem at ${root_pct}% — monitor usage"
    else
        echo "CHECK_RESULT OK disk_ok Root filesystem usage normal (${root_pct:-?}%)"
    fi

    # ── External HD mount ─────────────────────────────────────────────────────
    local hd_mount="${HD_MOUNT:-/mnt/nextclouddata}"

    if mount | grep -q "$hd_mount" 2>/dev/null; then
        echo "CHECK_RESULT OK hd_mounted External HD mounted at ${hd_mount}"

        # HD usage check
        local hd_pct
        hd_pct=$(df "$hd_mount" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
        if [ -n "$hd_pct" ] && [ "$hd_pct" -ge 90 ] 2>/dev/null; then
            echo "CHECK_RESULT CRITICAL hd_full HD mount ${hd_mount} at ${hd_pct}% — Nextcloud data volume almost full"
        elif [ -n "$hd_pct" ] && [ "$hd_pct" -ge 80 ] 2>/dev/null; then
            echo "CHECK_RESULT WARN hd_high HD mount ${hd_mount} at ${hd_pct}% — clean up user data"
        fi
    else
        echo "CHECK_RESULT CRITICAL hd_not_mounted External HD not mounted at ${hd_mount} — Nextcloud data unreachable"
    fi

    # ── NC data directory ─────────────────────────────────────────────────────
    local nc_data="${NC_DATA:-/mnt/nextclouddata/next}"

    if [ ! -d "$nc_data" ]; then
        echo "CHECK_RESULT FAIL nc_data_missing NC data directory does not exist: ${nc_data}"
        return 0
    fi

    echo "CHECK_RESULT OK nc_data_exists NC data directory exists: ${nc_data}"

    # Ownership check — must be 1004:1004 (NC_UID:NC_GID)
    local expected_uid="${NC_UID:-1004}"
    local expected_gid="${NC_GID:-1004}"
    local actual_uid actual_gid
    actual_uid=$(stat -c "%u" "$nc_data" 2>/dev/null)
    actual_gid=$(stat -c "%g" "$nc_data" 2>/dev/null)

    if [ "$actual_uid" != "$expected_uid" ] || [ "$actual_gid" != "$expected_gid" ]; then
        echo "CHECK_RESULT FAIL nc_data_wrong_owner NC data dir owned by ${actual_uid}:${actual_gid} — expected ${expected_uid}:${expected_gid}"
    else
        echo "CHECK_RESULT OK nc_data_owner NC data directory has correct ownership (${expected_uid}:${expected_gid})"
    fi

    # ── Docker named volumes (discovered dynamically — no hardcoded names) ──────
    if command -v docker &>/dev/null; then
        # Discover volume names from compose config (works regardless of project name)
        local compose_vols
        compose_vols=$(docker compose config --format json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for v in sorted(d.get('volumes', {}).keys()):
        print(v)
except: pass
" 2>/dev/null)

        # Fallback: find volumes by compose project label
        if [ -z "$compose_vols" ]; then
            local proj_name
            proj_name=$(docker compose config 2>/dev/null | awk '/^name:/{print $2; exit}')
            if [ -n "$proj_name" ]; then
                compose_vols=$(docker volume ls \
                    --filter "label=com.docker.compose.project=${proj_name}" \
                    --format '{{.Name}}' 2>/dev/null | \
                    sed "s/^${proj_name}_//")
            fi
        fi

        if [ -n "$compose_vols" ]; then
            local running_svcs
            running_svcs=$(docker compose ps --status running --services 2>/dev/null)

            while IFS= read -r vol; do
                [ -z "$vol" ] && continue
                # Check bare name first, then project-prefixed name
                if docker volume inspect "$vol" &>/dev/null 2>&1; then
                    echo "CHECK_RESULT OK vol_${vol} Docker volume '${vol}' exists"
                else
                    local prefixed
                    prefixed=$(docker volume ls --format '{{.Name}}' 2>/dev/null \
                        | grep -E "_${vol}$|^${vol}$" | head -1)
                    if [ -n "$prefixed" ]; then
                        echo "CHECK_RESULT OK vol_${vol} Docker volume '${vol}' exists (as '${prefixed}')"
                    elif echo "$running_svcs" | grep -qx "$vol"; then
                        # Service is running — volume exists inside container, not as a named volume
                        echo "CHECK_RESULT OK vol_${vol} Docker volume '${vol}' — service is running (bind mount or anonymous volume)"
                    else
                        echo "CHECK_RESULT WARN vol_${vol}_missing Docker volume '${vol}' not found — stack may not have been started yet"
                    fi
                fi
            done <<< "$compose_vols"
        fi
    fi
}
