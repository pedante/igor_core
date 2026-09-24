#!/bin/bash
# Nextcloud data storage and Docker volume checks.

CHECK_NAME="nextcloud_storage"
CHECK_DESCRIPTION="Nextcloud data mount, ownership, and stack volumes"
CHECK_SCHEDULE="300"

run_check() {
    local hd_mount="${HD_MOUNT:-/mnt/nextclouddata}"
    local nc_data="${NC_DATA:-/mnt/nextclouddata/next}"
    local hd_mounted=false

    if mount | grep -q "$hd_mount" 2>/dev/null; then
        hd_mounted=true
        echo "CHECK_RESULT OK hd_mounted External HD mounted at ${hd_mount}"
        local hd_pct
        hd_pct=$(df "$hd_mount" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
        if [ -n "$hd_pct" ] && [ "$hd_pct" -ge 90 ] 2>/dev/null; then
            echo "CHECK_RESULT CRITICAL hd_full HD mount ${hd_mount} at ${hd_pct}% — Nextcloud data volume almost full"
        elif [ -n "$hd_pct" ] && [ "$hd_pct" -ge 80 ] 2>/dev/null; then
            echo "CHECK_RESULT WARN hd_high HD mount ${hd_mount} at ${hd_pct}% — clean up user data"
        fi
    fi

    if [ "$hd_mounted" = false ]; then
        echo "CHECK_RESULT CRITICAL hd_not_mounted External HD not mounted at ${hd_mount} — Nextcloud data unreachable"
    fi

    if [ ! -d "$nc_data" ]; then
        echo "CHECK_RESULT FAIL nc_data_missing NC data directory does not exist: ${nc_data}"
        return 0
    fi
    echo "CHECK_RESULT OK nc_data_exists NC data directory exists: ${nc_data}"

    local expected_uid="${NC_UID:-1004}" expected_gid="${NC_GID:-1004}"
    local actual_uid actual_gid
    actual_uid=$(stat -c "%u" "$nc_data" 2>/dev/null)
    actual_gid=$(stat -c "%g" "$nc_data" 2>/dev/null)
    if [ "$actual_uid" != "$expected_uid" ] || [ "$actual_gid" != "$expected_gid" ]; then
        echo "CHECK_RESULT FAIL nc_data_wrong_owner NC data dir owned by ${actual_uid}:${actual_gid} — expected ${expected_uid}:${expected_gid}"
    else
        echo "CHECK_RESULT OK nc_data_owner NC data directory has correct ownership (${expected_uid}:${expected_gid})"
    fi

    if command -v docker &>/dev/null; then
        local compose_vols
        compose_vols=$(docker compose config --format json 2>/dev/null | python3 -c '
import json, sys
try:
    for value in sorted(json.load(sys.stdin).get("volumes", {})):
        print(value)
except Exception:
    pass
')
        if [ -n "$compose_vols" ]; then
            local running_svcs
            running_svcs=$(docker compose ps --status running --services 2>/dev/null)
            local vol prefixed
            while IFS= read -r vol; do
                [ -n "$vol" ] || continue
                if docker volume inspect "$vol" &>/dev/null; then
                    echo "CHECK_RESULT OK vol_${vol} Docker volume '${vol}' exists"
                else
                    prefixed=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "_${vol}$|^${vol}$" | head -1)
                    if [ -n "$prefixed" ]; then
                        echo "CHECK_RESULT OK vol_${vol} Docker volume '${vol}' exists (as '${prefixed}')"
                    elif echo "$running_svcs" | grep -qx "$vol"; then
                        echo "CHECK_RESULT OK vol_${vol} Docker volume '${vol}' — service is running (bind mount or anonymous volume)"
                    else
                        echo "CHECK_RESULT WARN vol_${vol}_missing Docker volume '${vol}' not found — stack may not have been started yet"
                    fi
                fi
            done <<< "$compose_vols"
        fi
    fi
}
