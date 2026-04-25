; ==============================================================================
;  IGOR — modules/nextcloud_docker/config/php-fpm.conf.tpl
;
;  PHP-FPM pool configuration template for the Nextcloud app container.
;  Rendered at install time via envsubst into:
;      config/stacks/nextcloud/config/php-fpm.conf
;  Mounted read-only into the app container as:
;      /usr/local/etc/php-fpm.d/zz-igor.conf
;
;  Variables substituted by envsubst:
;    ${NC_TIER_PHP_MEMORY}      memory_limit         (256M / 512M / 1G / 2G)
;    ${NC_TIER_PHP_PM_MAX}      pm.max_children      (5 / 10 / 20 / 40)
;    ${NC_TIER_OPCACHE_MEMORY}  opcache.memory       (64M / 128M / 256M / 512M)
;
;  Edit via Menu 7 (Configure) or regenerate by re-running the install wizard.
; ==============================================================================

[global]
error_log = /proc/self/fd/2

[www]
; FPM socket — matches the upstream block in nginx.conf
listen = 9000

; Dynamic process manager — balances idle memory vs. burst capacity
pm = dynamic
pm.max_children      = ${NC_TIER_PHP_PM_MAX}
pm.start_servers     = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests      = 500

; Pass host environment variables into PHP workers
clear_env = no

; Route PHP errors to the container log (journald / docker logs)
catch_workers_output  = yes
decorate_workers_output = no

; ── Memory & opcode cache ──────────────────────────────────────────────────────
php_admin_value[memory_limit]          = ${NC_TIER_PHP_MEMORY}
php_admin_flag[expose_php]             = off

; OPcache — tuned for Nextcloud's large class graph
php_value[opcache.memory_consumption]    = ${NC_TIER_OPCACHE_MEMORY}
php_value[opcache.interned_strings_buffer] = 16
php_value[opcache.max_accelerated_files]   = 10000
php_value[opcache.revalidate_freq]         = 60
php_flag[opcache.save_comments]            = on
php_flag[opcache.enable_cli]               = off

; ── Upload limits (keep in sync with nginx client_max_body_size) ───────────────
php_admin_value[upload_max_filesize] = 10G
php_admin_value[post_max_size]       = 10G

; ── Nextcloud-recommended settings ────────────────────────────────────────────
php_admin_value[output_buffering]    = 0
php_admin_flag[always_populate_raw_post_data] = off
