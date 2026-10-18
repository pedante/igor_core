# Shared isolated System administration fixture; host commands are mocked.
setup() {
    setup_igor_tmpdir
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    chmod 700 "$IGOR_DIR/data/runtime"
    export IGOR_DISTRO_ID=debian
    export IGOR_DISTRO_FAMILY=debian
    export IGOR_PLATFORM_QUERY_TIMEOUT_SECONDS=5
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config" "$IGOR_DIR/bin" "$IGOR_DIR/runtime"
    export ADMIN_UPDATE_STATE="$IGOR_DIR/runtime/updates-pending"
    export ADMIN_PRIVILEGE_TRACE="$IGOR_DIR/runtime/privileged-argv"
    export ADMIN_PACKAGE_STATE="$IGOR_DIR/runtime/docker-package-installed"
    export ADMIN_DOCKER_ENABLED="$IGOR_DIR/runtime/docker-enabled"
    export ADMIN_DOCKER_ACTIVE="$IGOR_DIR/runtime/docker-active"
    printf 'pending\n' > "$ADMIN_UPDATE_STATE"
    : > "$ADMIN_PRIVILEGE_TRACE"
    cp -a "$REPO_DIR/modules/system" "$IGOR_DIR/modules/system"
    cp -a "$REPO_DIR/modules/docker" "$IGOR_DIR/modules/docker"
    printf 'system=enabled\ndocker=enabled\n' > "$IGOR_DIR/config/modules.conf"

    cat > "$IGOR_DIR/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "-s upgrade" ]; then
    [ -e "$ADMIN_UPDATE_STATE" ] && printf 'Inst curl [1] (2 repo)\nInst openssl [1] (2 repo)\n'
    exit 0
elif [ "$1 $2" = "-s autoremove" ]; then
    printf 'Remv old-kernel [1]\nRemv unused-lib [1]\n'
elif [ "$1" = update ] && [ "$#" -eq 1 ]; then
    exit 0
elif [ "$1 $2 $3" = "install -y docker.io" ]; then
    : > "$ADMIN_PACKAGE_STATE"
elif [ "$1 $2" = "upgrade -y" ]; then
    rm -f "$ADMIN_UPDATE_STATE"
elif [ "$1" = clean ] && [ "$#" -eq 1 ]; then
    exit 0
else
    exit 2
fi
EOF
    cat > "$IGOR_DIR/bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
[ -e "$ADMIN_PACKAGE_STATE" ] || exit 1
case "$*" in
    *"-- docker.io") printf 'install ok installed'; exit 0 ;;
    *) exit 1 ;;
esac
EOF
    cat > "$IGOR_DIR/bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -Qu) [ -e "$ADMIN_UPDATE_STATE" ] && printf 'curl 1 -> 2\nlinux 1 -> 2\n' ;;
    -Qdtq) printf 'unused-a\nunused-b\n' ;;
    -Syu)
        [ "$2" = --noconfirm ] || exit 2
        rm -f "$ADMIN_UPDATE_STATE"
        ;;
    -Sc) [ "$2" = --noconfirm ] || exit 2 ;;
    *) exit 2 ;;
esac
EOF
    cat > "$IGOR_DIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list-units)
        printf 'cron.service loaded active running Cron\n'
        printf 'ssh.service loaded inactive dead SSH\n'
        ;;
    is-active)
        case "$3" in
            cron.service) printf 'active\n'; exit 0 ;;
            ssh.service) printf 'inactive\n'; exit 3 ;;
            docker.service)
                if [ -e "$ADMIN_DOCKER_ACTIVE" ]; then printf 'active\n'; exit 0
                else printf 'inactive\n'; exit 3; fi
                ;;
            *) printf 'unknown\n'; exit 4 ;;
        esac
        ;;
    is-enabled)
        [ "$3" = docker.service ] || exit 2
        if [ -e "$ADMIN_DOCKER_ENABLED" ]; then printf 'enabled\n'; exit 0
        else printf 'disabled\n'; exit 1; fi
        ;;
    enable)
        [ "$2" = docker.service ] || exit 2
        : > "$ADMIN_DOCKER_ENABLED"
        ;;
    start)
        [ "$2" = docker.service ] || exit 2
        : > "$ADMIN_DOCKER_ACTIVE"
        ;;
    restart) exit 0 ;;
    *) exit 2 ;;
esac
EOF
    cat > "$IGOR_DIR/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
printf '2026-10-02T12:00:00+0000 host kernel: boot ok\n'
printf '2026-10-02T12:00:01+0000 host systemd: service ready\n'
EOF
    cat > "$IGOR_DIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$ADMIN_PRIVILEGE_TRACE"
[ "$1" = -n ] && [ "$2" = -- ] || exit 2
shift 2
exec "$@"
EOF
    chmod +x "$IGOR_DIR/bin/sudo"
    chmod +x "$IGOR_DIR/bin/apt-get" "$IGOR_DIR/bin/dpkg-query" "$IGOR_DIR/bin/pacman" "$IGOR_DIR/bin/systemctl" "$IGOR_DIR/bin/journalctl"
    export PATH="$IGOR_DIR/bin:$PATH"

    source "$REPO_DIR/core/lib/module_loader.sh"
    _ml_log() { :; }
    igor_load_all_modules >/dev/null
}

teardown() { teardown_igor_tmpdir; }

_execute_read() {
    local id="$1" inputs="${2:-}" proposal
    [ -n "$inputs" ] || inputs='{}'
    local version=2
    [ "$id" != system.service.list ] || version=3
    proposal="$(igor_capability_prepare "$id" "$inputs" system "$version")" || return 1
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    IGOR_CAPABILITY_APPROVAL_STATUS=auto_approved
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    igor_capability_execute "$proposal"
}
