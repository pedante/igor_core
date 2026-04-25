#!/bin/bash
# ==============================================================================
#  IGOR — modules/nextcloud_docker/lib/tier_config.sh
#
#  Single source of truth for all tier defaults within the nextcloud_docker
#  module.  Source this file AFTER igor_load_profile() has run so that
#  $IGOR_TIER is already exported.  All variables use the NC_TIER_ prefix
#  to avoid collisions with igor-core globals.
#
#  User overrides: create  config/stacks/nextcloud/tier_overrides.env
#  and set any NC_TIER_* variable there.  _mod_install_load_tier() (in
#  install.sh) sources that file immediately after sourcing this one and
#  prints a notice for every variable that changed.
#
#  Visibility values for NC_TIER_SATELLITE_* variables:
#    hidden   — option is not rendered in any menu
#    optional — rendered, default state off
#    default  — rendered, default state on
# ==============================================================================

_nc_tier="${IGOR_TIER:-constrained}"
_nc_data_base="${HD_MOUNT:-/mnt/nextclouddata}"

case "$_nc_tier" in
    constrained)
        NC_TIER_VOLUME_STRATEGY=named
        NC_TIER_DATA_PATH=""
        NC_TIER_PHP_MEMORY=256M
        NC_TIER_PHP_PM_MAX=5
        NC_TIER_OPCACHE_MEMORY=64M
        NC_TIER_REDIS_MEMORY=64m
        NC_TIER_DB_SHARED_BUFFERS=64MB
        NC_TIER_DB_WORK_MEM=2MB
        NC_TIER_DB_EFFECTIVE_CACHE_SIZE=128MB
        NC_TIER_DB_MAX_CONNECTIONS=20
        NC_TIER_ENABLE_PREVIEWS=false
        NC_TIER_CRON_MODE=webcron
        NC_TIER_SATELLITE_IMMICH=hidden
        NC_TIER_SATELLITE_COLLABORA=hidden
        NC_TIER_SATELLITE_ONLYOFFICE=hidden
        NC_TIER_SATELLITE_COTURN=optional
        ;;
    standard)
        NC_TIER_VOLUME_STRATEGY=named
        NC_TIER_DATA_PATH=""
        NC_TIER_PHP_MEMORY=512M
        NC_TIER_PHP_PM_MAX=10
        NC_TIER_OPCACHE_MEMORY=128M
        NC_TIER_REDIS_MEMORY=128m
        NC_TIER_DB_SHARED_BUFFERS=128MB
        NC_TIER_DB_WORK_MEM=4MB
        NC_TIER_DB_EFFECTIVE_CACHE_SIZE=256MB
        NC_TIER_DB_MAX_CONNECTIONS=50
        NC_TIER_ENABLE_PREVIEWS=false
        NC_TIER_CRON_MODE=cron
        NC_TIER_SATELLITE_IMMICH=optional
        NC_TIER_SATELLITE_COLLABORA=optional
        NC_TIER_SATELLITE_ONLYOFFICE=hidden
        NC_TIER_SATELLITE_COTURN=optional
        ;;
    comfortable)
        NC_TIER_VOLUME_STRATEGY=bind
        NC_TIER_DATA_PATH="${_nc_data_base}/nextcloud"
        NC_TIER_PHP_MEMORY=1G
        NC_TIER_PHP_PM_MAX=20
        NC_TIER_OPCACHE_MEMORY=256M
        NC_TIER_REDIS_MEMORY=256m
        NC_TIER_DB_SHARED_BUFFERS=256MB
        NC_TIER_DB_WORK_MEM=8MB
        NC_TIER_DB_EFFECTIVE_CACHE_SIZE=512MB
        NC_TIER_DB_MAX_CONNECTIONS=100
        NC_TIER_ENABLE_PREVIEWS=true
        NC_TIER_CRON_MODE=system
        NC_TIER_SATELLITE_IMMICH=optional
        NC_TIER_SATELLITE_COLLABORA=optional
        NC_TIER_SATELLITE_ONLYOFFICE=optional
        NC_TIER_SATELLITE_COTURN=optional
        ;;
    server)
        NC_TIER_VOLUME_STRATEGY=bind
        NC_TIER_DATA_PATH="${_nc_data_base}/nextcloud"
        NC_TIER_PHP_MEMORY=2G
        NC_TIER_PHP_PM_MAX=40
        NC_TIER_OPCACHE_MEMORY=512M
        NC_TIER_REDIS_MEMORY=512m
        NC_TIER_DB_SHARED_BUFFERS=512MB
        NC_TIER_DB_WORK_MEM=16MB
        NC_TIER_DB_EFFECTIVE_CACHE_SIZE=1GB
        NC_TIER_DB_MAX_CONNECTIONS=200
        NC_TIER_ENABLE_PREVIEWS=true
        NC_TIER_CRON_MODE=system
        NC_TIER_SATELLITE_IMMICH=default
        NC_TIER_SATELLITE_COLLABORA=optional
        NC_TIER_SATELLITE_ONLYOFFICE=optional
        NC_TIER_SATELLITE_COTURN=optional
        ;;
    *)
        # Unknown tier — fall back to constrained
        NC_TIER_VOLUME_STRATEGY=named
        NC_TIER_DATA_PATH=""
        NC_TIER_PHP_MEMORY=256M
        NC_TIER_PHP_PM_MAX=5
        NC_TIER_OPCACHE_MEMORY=64M
        NC_TIER_REDIS_MEMORY=64m
        NC_TIER_DB_SHARED_BUFFERS=64MB
        NC_TIER_DB_WORK_MEM=2MB
        NC_TIER_DB_EFFECTIVE_CACHE_SIZE=128MB
        NC_TIER_DB_MAX_CONNECTIONS=20
        NC_TIER_ENABLE_PREVIEWS=false
        NC_TIER_CRON_MODE=webcron
        NC_TIER_SATELLITE_IMMICH=hidden
        NC_TIER_SATELLITE_COLLABORA=hidden
        NC_TIER_SATELLITE_ONLYOFFICE=hidden
        NC_TIER_SATELLITE_COTURN=optional
        ;;
esac

export NC_TIER_VOLUME_STRATEGY NC_TIER_DATA_PATH \
       NC_TIER_PHP_MEMORY NC_TIER_PHP_PM_MAX NC_TIER_OPCACHE_MEMORY \
       NC_TIER_REDIS_MEMORY \
       NC_TIER_DB_SHARED_BUFFERS NC_TIER_DB_WORK_MEM \
       NC_TIER_DB_EFFECTIVE_CACHE_SIZE NC_TIER_DB_MAX_CONNECTIONS \
       NC_TIER_ENABLE_PREVIEWS NC_TIER_CRON_MODE \
       NC_TIER_SATELLITE_IMMICH NC_TIER_SATELLITE_COLLABORA \
       NC_TIER_SATELLITE_ONLYOFFICE NC_TIER_SATELLITE_COTURN

unset _nc_tier _nc_data_base
