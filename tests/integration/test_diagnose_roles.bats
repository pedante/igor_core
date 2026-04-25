#!/usr/bin/env bats
# =============================================================================
#  tests/integration/test_diagnose_roles.bats
#  Phase 4: Role detection engine — _diag_detect_roles()
#
#  Runs _diag_detect_roles() with mocked docker commands that simulate a
#  standard 5-container Nextcloud stack, then asserts the correct role
#  assignments are made without touching a real Docker daemon.
# =============================================================================

load "${BATS_TEST_DIRNAME}/../helpers/common"
load "${BATS_TEST_DIRNAME}/../helpers/mock_docker"

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    stub_ui

    # Source roles.sh first so our stubs defined below override its real
    # _diag_get_service_image and _diag_service_has_published_port definitions.
    # shellcheck source=/dev/null
    source "${REPO_DIR}/core/diagnose/roles.sh"

    # Override _diag_get_service_image and _diag_service_has_published_port
    # to use controlled fixture data instead of calling docker inspect.
    # This isolates the role-matching logic from docker availability.
    _diag_get_service_image() {
        case "$1" in
            web)   echo "nginx:alpine" ;;
            app)   echo "nextcloud:custom-fpm" ;;
            db)    echo "postgres:15" ;;
            redis) echo "redis:7" ;;
            cron)  echo "nextcloud:custom-fpm" ;;
            *)     echo "" ;;
        esac
    }
    export -f _diag_get_service_image

    # app has a published port (9000), cron does NOT
    _diag_service_has_published_port() {
        case "$1" in
            web|app|db|redis) return 0 ;;  # has ports
            cron)             return 1 ;;  # no ports
            *)                return 1 ;;
        esac
    }
    export -f _diag_service_has_published_port

    _diag_log() { :; }
    export -f _diag_log

    # docker compose config --services returns the 5 services
    docker() {
        case "$*" in
            "compose config --services"*) printf 'web\napp\ndb\nredis\ncron\n'; return 0 ;;
            "compose ps -q"*)             printf 'cid_mock\n'; return 0 ;;
            *)                            return 1 ;;
        esac
    }
    export -f docker
}

teardown() {
    teardown_igor_tmpdir
}

# ── Run role detection once and cache result ──────────────────────────────────
_run_detection() {
    unset _DIAG_ROLES 2>/dev/null || true
    _diag_detect_roles
}

# ══════════════════════════════════════════════════════════════════════════════
#  Role assignment tests
# ══════════════════════════════════════════════════════════════════════════════

@test "detect_roles: succeeds (exit 0)" {
    run _diag_detect_roles
    [ "$status" -eq 0 ]
}

@test "detect_roles: nginx container → web role" {
    _run_detection
    [ "${_DIAG_ROLES[web]:-}" = "web" ] \
        || fail "web role not assigned to 'web' service; got: '${_DIAG_ROLES[web]:-}'"
}

@test "detect_roles: nextcloud FPM with published port → app role" {
    _run_detection
    [ "${_DIAG_ROLES[app]:-}" = "app" ] \
        || fail "app role not assigned to 'app' service; got: '${_DIAG_ROLES[app]:-}'"
}

@test "detect_roles: postgres container → db role" {
    _run_detection
    [ "${_DIAG_ROLES[db]:-}" = "db" ] \
        || fail "db role not assigned to 'db' service; got: '${_DIAG_ROLES[db]:-}'"
}

@test "detect_roles: redis container → cache role" {
    _run_detection
    [ "${_DIAG_ROLES[cache]:-}" = "redis" ] \
        || fail "cache role not assigned to 'redis' service; got: '${_DIAG_ROLES[cache]:-}'"
}

@test "detect_roles: nextcloud FPM without published port → cron role" {
    _run_detection
    [ "${_DIAG_ROLES[cron]:-}" = "cron" ] \
        || fail "cron role not assigned to 'cron' service; got: '${_DIAG_ROLES[cron]:-}'"
}

@test "detect_roles: all 5 expected roles are assigned" {
    _run_detection
    local missing=()
    for role in web app db cache cron; do
        [ -z "${_DIAG_ROLES[$role]:-}" ] && missing+=("$role")
    done
    [ "${#missing[@]}" -eq 0 ] \
        || fail "missing roles after detection: ${missing[*]}"
}

@test "detect_roles: app and cron are different services" {
    _run_detection
    [ "${_DIAG_ROLES[app]:-}" != "${_DIAG_ROLES[cron]:-}" ] \
        || fail "app and cron mapped to same service name"
}

# ══════════════════════════════════════════════════════════════════════════════
#  Fallback: docker unavailable
# ══════════════════════════════════════════════════════════════════════════════

@test "detect_roles: returns non-zero when docker compose fails" {
    docker() { return 1; }
    export -f docker
    run _diag_detect_roles
    [ "$status" -ne 0 ]
}

# ══════════════════════════════════════════════════════════════════════════════
#  _diag_role_for_service — reverse lookup
# ══════════════════════════════════════════════════════════════════════════════

@test "role_for_service: returns correct role for web service" {
    _run_detection
    local role
    role=$(_diag_role_for_service "web")
    [ "$role" = "web" ]
}

@test "role_for_service: returns 'unknown' for unlisted service" {
    _run_detection
    local role
    role=$(_diag_role_for_service "nonexistent_svc") || true
    [ "$role" = "unknown" ]
}
