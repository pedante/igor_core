#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_BACKUPS_DIR="$IGOR_DIR/data/backups"
    mkdir -p "$IGOR_DIR/config/variables" "$IGOR_DIR/secrets"
    printf 'ENCRYPTION_FIXTURE=present\n' > "$IGOR_DIR/config/variables/encryption.env"
    printf 'SECRET_FIXTURE=retained\n' > "$IGOR_DIR/secrets/site.env"

    step() { :; }
    ok() { :; }
    info() { :; }
    warn() { :; }
    fail() { :; }
    export -f step ok info warn fail

    # Neither Bash nor the Python snapshot collector may invoke live services.
    mkdir -p "$IGOR_DIR/mock-bin"
    printf '#!/bin/sh\nexit 1\n' > "$IGOR_DIR/mock-bin/unavailable"
    chmod +x "$IGOR_DIR/mock-bin/unavailable"
    local cmd
    for cmd in crontab docker ip iptables-save ss sudo systemctl ufw; do
        ln -s unavailable "$IGOR_DIR/mock-bin/$cmd"
    done
    export PATH="$IGOR_DIR/mock-bin:$PATH"

    # Test-only crypto simulation: preserve the tar payload at the requested
    # .gpg path and validate the archive/component bookkeeping around it.
    gpg() {
        local output='' input='' mode='' pass_fd='' passphrase=''
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --output) output="$2"; shift 2 ;;
                --pinentry-mode) mode="$2"; shift 2 ;;
                --passphrase-fd) pass_fd="$2"; shift 2 ;;
                --batch|--yes|--symmetric) shift ;;
                --*) return 2 ;;
                *) input="$1"; shift ;;
            esac
        done
        [ "$mode" = loopback ] && [ "$pass_fd" = 3 ] || return 2
        IFS= read -r passphrase <&3
        [ "$passphrase" = fixture-passphrase ] || return 2
        [ -n "$output" ] && [ -f "$input" ] || return 2
        cp -- "$input" "$output"
    }
    export -f gpg
    source "$REPO_DIR/core/recovery/config_backup.sh"
}

teardown() {
    teardown_igor_tmpdir
}

@test "simulated encryption keeps encrypted member and removes plaintext member" {
    local output_file="$IGOR_DIR/pty-output"
    python3 "$BATS_TEST_DIRNAME/../helpers/pty_command.py" \
        "source '$REPO_DIR/core/recovery/config_backup.sh'; config_backup_take encrypted-fixture" \
        $'y\nfixture-passphrase\nfixture-passphrase\n' >"$output_file" 2>&1

    local archive
    archive=$(find "$IGOR_DIR/data/backups" -maxdepth 1 -type f -name 'config_*-enc.tar.gz' -print -quit)
    [ -f "$archive" ]
    tar -tzf "$archive" | grep -q '^igor-state/secrets-plain.tar.gz.gpg$'
    if tar -tzf "$archive" | grep -q '^igor-state/secrets-plain/site.env$'; then
        return 1
    fi

    local payload="$IGOR_DIR/secrets-payload.tar.gz"
    tar -xOf "$archive" igor-state/secrets-plain.tar.gz.gpg > "$IGOR_DIR/secrets-payload.gpg"
    # The mock GPG preserves the tar stream, so inspect the retained payload
    # directly. A real GPG test separately validates cryptographic recovery.
    mv "$IGOR_DIR/secrets-payload.gpg" "$payload"
    tar -xOf "$payload" secrets-plain/site.env | grep -q '^SECRET_FIXTURE=retained$'
}
