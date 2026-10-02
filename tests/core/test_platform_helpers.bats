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

@test "Wave D package argv resolution is deterministic on Debian and Arch" {
    source "$REPO_DIR/core/lib/pkg.sh"
    IGOR_DISTRO_FAMILY=debian
    [ "$(pkg_install_argv pkg_docker pkg_python)" = "apt-get install -y docker.io python3" ]
    [ "$(pkg_remove_argv pkg_docker)" = "apt-get remove -y docker.io" ]
    [ "$(pkg_update_argv)" = "apt-get update" ]
    [ "$(pkg_upgrade_argv)" = "apt-get upgrade -y" ]
    IGOR_DISTRO_FAMILY=arch
    [ "$(pkg_install_argv pkg_docker pkg_python)" = "pacman -S --noconfirm docker python" ]
    [ "$(pkg_remove_argv pkg_docker)" = "pacman -R --noconfirm docker" ]
    [ "$(pkg_update_argv)" = "pacman -Syu --noconfirm" ]
    [ "$(pkg_upgrade_argv)" = "pacman -Syu --noconfirm" ]
}

@test "Wave D package argv rejects invalid names and unknown families" {
    source "$REPO_DIR/core/lib/pkg.sh"
    IGOR_DISTRO_FAMILY=debian
    run pkg_install_argv 'bad name'
    [ "$status" -eq 2 ]
    run pkg_remove_argv --bad
    [ "$status" -eq 2 ]
    IGOR_DISTRO_FAMILY=unknown
    run pkg_update_argv
    [ "$status" -eq 2 ]
    run pkg_upgrade_argv
    [ "$status" -eq 2 ]
}

@test "Wave D package query distinguishes installed and missing packages" {
    source "$REPO_DIR/core/lib/pkg.sh"
    mkdir -p "$IGOR_DIR/bin"
    cat > "$IGOR_DIR/bin/dpkg-query" <<'EOF'
#!/bin/bash
case "$4" in
    installed) printf 'install ok installed';;
    missing) printf 'unknown ok not-installed';;
    *) exit 3;;
esac
EOF
    chmod +x "$IGOR_DIR/bin/dpkg-query"
    export PATH="$IGOR_DIR/bin:$PATH"
    IGOR_DISTRO_FAMILY=debian
    run pkg_query installed
    [ "$status" -eq 0 ]
    run pkg_query missing
    [ "$status" -eq 1 ]
    run pkg_query error
    [ "$status" -eq 2 ]
    run pkg_query 'bad name'
    [ "$status" -eq 2 ]
}

@test "Wave D Arch package and service queries distinguish states and errors" {
    source "$REPO_DIR/core/lib/pkg.sh"
    mkdir -p "$IGOR_DIR/bin"
    cat > "$IGOR_DIR/bin/pacman" <<'EOF'
#!/bin/bash
case "$3" in installed) exit 0;; missing) exit 1;; *) exit 2;; esac
EOF
    cat > "$IGOR_DIR/bin/systemctl" <<'EOF'
#!/bin/bash
case "$3" in active) printf 'active\n'; exit 0;; inactive) printf 'inactive\n'; exit 3;; *) exit 4;; esac
EOF
    chmod +x "$IGOR_DIR/bin/pacman" "$IGOR_DIR/bin/systemctl"
    export PATH="$IGOR_DIR/bin:$PATH"
    IGOR_DISTRO_FAMILY=arch
    run pkg_query installed
    [ "$status" -eq 0 ]
    run pkg_query missing
    [ "$status" -eq 1 ]
    run pkg_query error
    [ "$status" -eq 2 ]
    # shellcheck disable=SC2218 # pkg.sh is sourced above through a dynamic path.
    [ "$(svc_query active)" = active ]
    # shellcheck disable=SC2218 # pkg.sh is sourced above through a dynamic path.
    [ "$(svc_query inactive)" = inactive ]
    [ "$(svc_stop_argv cronie.service)" = "systemctl stop cronie.service" ]
}

@test "Wave D service query and operation argv validate units" {
    source "$REPO_DIR/core/lib/pkg.sh"
    IGOR_DISTRO_FAMILY=debian
    mkdir -p "$IGOR_DIR/bin"
    cat > "$IGOR_DIR/bin/systemctl" <<'EOF'
#!/bin/bash
[ "$1" = is-active ] && printf 'active\n'
EOF
    chmod +x "$IGOR_DIR/bin/systemctl"
    export PATH="$IGOR_DIR/bin:$PATH"
    [ "$(svc_query docker.service)" = active ]
    [ "$(svc_restart_argv docker.service)" = "systemctl restart docker.service" ]
    [ "$(svc_enable_argv docker.service)" = "systemctl enable docker.service" ]
    run svc_start_argv 'bad unit'
    [ "$status" -eq 2 ]
}

@test "Wave D service query distinguishes inactive and unknown units" {
    source "$REPO_DIR/core/lib/pkg.sh"
    IGOR_DISTRO_FAMILY=debian
    mkdir -p "$IGOR_DIR/bin"
    cat > "$IGOR_DIR/bin/systemctl" <<'EOF'
#!/bin/bash
case "$3" in
    inactive) printf 'inactive\n'; exit 3;;
    unknown) printf 'unknown\n'; exit 4;;
    *) printf 'active\n'; exit 0;;
esac
EOF
    chmod +x "$IGOR_DIR/bin/systemctl"
    export PATH="$IGOR_DIR/bin:$PATH"
    # shellcheck disable=SC2218 # pkg.sh is sourced above through a dynamic path.
    [ "$(svc_query inactive)" = inactive ]
    run svc_query unknown
    [ "$status" -eq 1 ]
    [ "$output" = unknown ]
}

@test "Wave D service operations fail closed without systemctl" {
    source "$REPO_DIR/core/lib/pkg.sh"
    mkdir -p "$IGOR_DIR/empty-bin"
    PATH="$IGOR_DIR/empty-bin" run svc_stop_argv docker.service
    [ "$status" -eq 2 ]
}

@test "Wave D service operations fail closed for unknown family" {
    source "$REPO_DIR/core/lib/pkg.sh"
    IGOR_DISTRO_FAMILY=unknown
    run svc_restart_argv docker.service
    [ "$status" -eq 2 ]
}


@test "System admin package discovery normalizes Debian update and cleanup candidates" {
    source "$REPO_DIR/core/lib/pkg.sh"
    mkdir -p "$IGOR_DIR/bin"
    cat > "$IGOR_DIR/bin/apt-get" <<'EOF'
#!/bin/bash
if [ "$1 $2" = "-s upgrade" ]; then
    printf 'Inst curl [1] (2 repo)\nInst openssl [1] (2 repo)\n'
elif [ "$1 $2" = "-s autoremove" ]; then
    printf 'Remv old-kernel [1]\nRemv unused-lib [1]\n'
else
    exit 2
fi
EOF
    chmod +x "$IGOR_DIR/bin/apt-get"
    export PATH="$IGOR_DIR/bin:$PATH"
    IGOR_DISTRO_FAMILY=debian
    [ "$(pkg_updates_list)" = curl\nopenssl' ]
    [ "$(pkg_cleanup_candidates)" = old-kernel\nunused-lib' ]
}

@test "System admin package discovery normalizes Arch update and orphan candidates" {
    source "$REPO_DIR/core/lib/pkg.sh"
    mkdir -p "$IGOR_DIR/bin"
    cat > "$IGOR_DIR/bin/pacman" <<'EOF'
#!/bin/bash
case "$1" in
    -Qu) printf 'curl 1 -> 2\nlinux 1 -> 2\n' ;;
    -Qdtq) printf 'unused-a\nunused-b\n' ;;
    *) exit 2 ;;
esac
EOF
    chmod +x "$IGOR_DIR/bin/pacman"
    export PATH="$IGOR_DIR/bin:$PATH"
    IGOR_DISTRO_FAMILY=arch
    [ "$(pkg_updates_list)" = curl\nlinux' ]
    [ "$(pkg_cleanup_candidates)" = unused-a\nunused-b' ]
}

@test "System admin service listing is a bounded platform query" {
    source "$REPO_DIR/core/lib/pkg.sh"
    mkdir -p "$IGOR_DIR/bin"
    cat > "$IGOR_DIR/bin/systemctl" <<'EOF'
#!/bin/bash
[ "$1" = list-units ] || exit 2
printf 'cron.service loaded active running Cron\nssh.service loaded inactive dead SSH\n'
EOF
    chmod +x "$IGOR_DIR/bin/systemctl"
    export PATH="$IGOR_DIR/bin:$PATH"
    IGOR_DISTRO_FAMILY=debian
    [ "$(svc_list_query)" = cron.service\tactive\trunning\nssh.service\tinactive\tdead' ]
}
