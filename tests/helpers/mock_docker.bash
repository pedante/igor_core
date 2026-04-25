#!/usr/bin/env bash
# =============================================================================
#  tests/helpers/mock_docker.bash
#  Shell function stubs that override the real 'docker' command in tests.
#
#  Load with:  load '../helpers/mock_docker'
#
#  After loading, call  setup_mock_docker  in your setup() to activate stubs.
#  Each docker call is routed by its argument pattern to a canned response.
#
#  To simulate a 5-container Nextcloud stack call:
#      MOCK_DOCKER_PRESET=nextcloud_stack   setup_mock_docker
#
#  To simulate docker being unavailable:
#      MOCK_DOCKER_PRESET=unavailable       setup_mock_docker
# =============================================================================

# ── Activate mock docker ───────────────────────────────────────────────────────
setup_mock_docker() {
    local preset="${MOCK_DOCKER_PRESET:-nextcloud_stack}"

    case "$preset" in
        nextcloud_stack) _install_nextcloud_stack_mock ;;
        unavailable)     _install_unavailable_mock ;;
        *)               _install_nextcloud_stack_mock ;;
    esac
}

# ── Nextcloud stack mock ───────────────────────────────────────────────────────
# Simulates a running 5-container Nextcloud stack (web, app, db, redis, cron).
_install_nextcloud_stack_mock() {
    docker() {
        local args="$*"
        case "$args" in
            "network inspect nextcloud_default"*)
                printf '[{"IPAM":{"Config":[{"Subnet":"172.20.0.0/16"}]}}]\n'
                return 0 ;;
            "network ls"*)
                printf 'NETWORK ID     NAME                 DRIVER\nabc123         nextcloud_default    bridge\n'
                return 0 ;;
            "network inspect"*"--format"*"Subnet"*)
                printf '172.20.0.0/16\n'
                return 0 ;;
            "compose config --services"*)
                printf 'web\napp\ndb\nredis\ncron\n'
                return 0 ;;
            "compose ps -q web"*)   printf 'cid_web\n';   return 0 ;;
            "compose ps -q app"*)   printf 'cid_app\n';   return 0 ;;
            "compose ps -q db"*)    printf 'cid_db\n';    return 0 ;;
            "compose ps -q redis"*) printf 'cid_redis\n'; return 0 ;;
            "compose ps -q cron"*)  printf 'cid_cron\n';  return 0 ;;
            "compose ps -q"*)       printf 'cid_web\ncid_app\ncid_db\ncid_redis\ncid_cron\n'; return 0 ;;
            "compose ps"*)
                printf 'NAME   IMAGE   COMMAND   SERVICE   CREATED   STATUS\n'
                printf 'web    nginx:alpine   ...   web   ...   Up\n'
                printf 'app    nextcloud:custom-fpm   ...   app   ...   Up\n'
                printf 'db     postgres:15   ...   db   ...   Up\n'
                printf 'redis  redis:7   ...   redis   ...   Up\n'
                printf 'cron   nextcloud:custom-fpm   ...   cron   ...   Up\n'
                return 0 ;;
            # docker inspect image
            "inspect --format"*"Config.Image"*"cid_web"*)
                printf 'nginx:alpine\n'; return 0 ;;
            "inspect --format"*"Config.Image"*"cid_app"*)
                printf 'nextcloud:custom-fpm\n'; return 0 ;;
            "inspect --format"*"Config.Image"*"cid_db"*)
                printf 'postgres:15\n'; return 0 ;;
            "inspect --format"*"Config.Image"*"cid_redis"*)
                printf 'redis:7\n'; return 0 ;;
            "inspect --format"*"Config.Image"*"cid_cron"*)
                printf 'nextcloud:custom-fpm\n'; return 0 ;;
            # docker inspect published ports
            "inspect --format"*"NetworkSettings.Ports"*"cid_web"*)
                printf '8080/tcp\n'; return 0 ;;
            "inspect --format"*"NetworkSettings.Ports"*"cid_app"*)
                printf '9000/tcp\n'; return 0 ;;
            "inspect --format"*"NetworkSettings.Ports"*"cid_db"*)
                printf '5432/tcp\n'; return 0 ;;
            "inspect --format"*"NetworkSettings.Ports"*"cid_redis"*)
                printf '6379/tcp\n'; return 0 ;;
            "inspect --format"*"NetworkSettings.Ports"*"cid_cron"*)
                # cron has NO published ports — makes _diag_service_has_published_port return false
                printf ''; return 0 ;;
            "compose config --format json"*)
                # Minimal JSON understood by _diag_get_service_image
                printf '{"services":{"web":{"image":"nginx:alpine"},"app":{"image":"nextcloud:custom-fpm"},"db":{"image":"postgres:15"},"redis":{"image":"redis:7"},"cron":{"image":"nextcloud:custom-fpm"}}}\n'
                return 0 ;;
            "compose config"*)
                printf 'services:\n  web:\n    image: nginx:alpine\n  app:\n    image: nextcloud:custom-fpm\n  db:\n    image: postgres:15\n  redis:\n    image: redis:7\n  cron:\n    image: nextcloud:custom-fpm\n'
                return 0 ;;
            *)
                # Unknown docker call — return failure
                return 1 ;;
        esac
    }
    export -f docker
}

# ── Unavailable docker mock ────────────────────────────────────────────────────
_install_unavailable_mock() {
    docker() { return 127; }
    export -f docker
}

# ── Minimal health mock (docker compose ps returns running containers) ──────────
setup_mock_docker_health_ok() {
    docker() {
        case "$*" in
            "compose ps --status running"*)
                printf 'web\napp\ndb\nredis\ncron\n'; return 0 ;;
            *) return 0 ;;
        esac
    }
    export -f docker
}

setup_mock_docker_health_down() {
    docker() { return 1; }
    export -f docker
}
