#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

source "$REPO_DIR/core/lib/distro.sh"

setup() {
    setup_igor_tmpdir
    stub_ui
    export IGOR_DISTRO_ID=unknown IGOR_DISTRO_FAMILY=unknown
    id() { [ "${1:-}" = -u ] && printf '1000\n' || command id "$@"; }
}

teardown() {
    teardown_igor_tmpdir
}

# distro.sh intentionally reads /etc/os-release.  Override the shell source
# builtin only in these tests so detection is exercised against deterministic
# fixtures without depending on the host running the suite.
mock_os_release() {
    TEST_FIXTURE_ID="$1"
    TEST_FIXTURE_LIKE="${2:-}"
    .() {
        ID="$TEST_FIXTURE_ID"
        ID_LIKE="$TEST_FIXTURE_LIKE"
    }
}

install_package_stub() {
    local command_name="$1"
    cat > "$IGOR_DIR/bin/$command_name" <<'EOF'
#!/bin/bash
printf '%s\n' "$0 $*" >> "$IGOR_DIR/package-calls"
EOF
    chmod +x "$IGOR_DIR/bin/$command_name"
}

@test "distro detection recognizes Debian and Arch fixtures" {
    mock_os_release debian
    igor_detect_distro
    [ "$IGOR_DISTRO_ID" = debian ]
    [ "$IGOR_DISTRO_FAMILY" = debian ]

    mock_os_release arch
    igor_detect_distro
    [ "$IGOR_DISTRO_ID" = arch ]
    [ "$IGOR_DISTRO_FAMILY" = arch ]
}

@test "distro detection uses ID_LIKE for supported derivative families" {
    mock_os_release custom "arch"
    igor_detect_distro
    [ "$IGOR_DISTRO_ID" = custom ]
    [ "$IGOR_DISTRO_FAMILY" = arch ]

    mock_os_release custom "debian"
    igor_detect_distro
    [ "$IGOR_DISTRO_ID" = custom ]
    [ "$IGOR_DISTRO_FAMILY" = debian ]
}

@test "unknown distro fixture remains unknown" {
    mock_os_release mystery "unmapped"
    igor_detect_distro
    [ "$IGOR_DISTRO_ID" = mystery ]
    [ "$IGOR_DISTRO_FAMILY" = unknown ]
}

@test "package and service mappings resolve Debian names" {
    source "$REPO_DIR/core/lib/pkg.sh"
    IGOR_DISTRO_FAMILY=debian
    [ "$(_pkg_resolve pkg_docker)" = docker.io ]
    [ "$(_pkg_resolve pkg_python)" = python3 ]
    [ "$(pkg_svc_name svc_cron)" = cron ]
    [ "$(_pkg_resolve unregistered-package)" = unregistered-package ]
    [ "$(pkg_svc_name unregistered-service)" = unregistered-service ]
}

@test "package and service mappings resolve Arch names" {
    source "$REPO_DIR/core/lib/pkg.sh"
    IGOR_DISTRO_FAMILY=arch
    [ "$(_pkg_resolve pkg_docker)" = docker ]
    [ "$(_pkg_resolve pkg_python)" = python ]
    [ "$(pkg_svc_name svc_cron)" = cronie ]
}

@test "Debian package installation invokes apt with mapped names" {
    source "$REPO_DIR/core/lib/pkg.sh"
    mkdir -p "$IGOR_DIR/bin"
    install_package_stub sudo
    install_package_stub apt-get
    export PATH="$IGOR_DIR/bin:$PATH"
    IGOR_DISTRO_FAMILY=debian

    pkg_install pkg_docker pkg_python

    grep -q 'sudo apt-get install -y docker.io python3' "$IGOR_DIR/package-calls"
}

@test "Arch package installation invokes pacman with mapped names" {
    source "$REPO_DIR/core/lib/pkg.sh"
    mkdir -p "$IGOR_DIR/bin"
    install_package_stub sudo
    install_package_stub pacman
    export PATH="$IGOR_DIR/bin:$PATH"
    IGOR_DISTRO_FAMILY=arch

    pkg_install pkg_docker pkg_python

    grep -q 'sudo pacman -S --noconfirm docker python' "$IGOR_DIR/package-calls"
}

@test "unsupported package families fail explicitly" {
    source "$REPO_DIR/core/lib/pkg.sh"
    warn() { printf '%s\n' "$*"; }
    IGOR_DISTRO_FAMILY=unknown
    run pkg_install pkg_docker
    [ "$status" -eq 1 ]
    [[ "$output" == *"unsupported distro family 'unknown'"* ]]
}
