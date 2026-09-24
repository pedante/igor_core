#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_BACKUPS_DIR="$IGOR_DIR/data/backups"
    export BACKUP_CONFIG_KEEP=20
    export BACKUP_FULL_KEEP=3

    # Keep the recovery tests independent of the interactive UI and event stack.
    step() { :; }
    ok() { :; }
    info() { :; }
    warn() { :; }
    fail() { :; }
    alert_log() { :; }
    notify_event() { :; }
    journal_record() { :; }
    igor_get_hooks() { :; }
    crontab() { return 1; }
    docker() { return 1; }
    ip() { return 1; }
    iptables-save() { return 1; }
    ss() { return 1; }
    sudo() { return 1; }
    systemctl() { return 1; }
    ufw() { return 1; }
    export -f step ok info warn fail alert_log notify_event journal_record igor_get_hooks
    export -f crontab docker ip iptables-save ss sudo systemctl ufw

    # Python's snapshot collector launches /bin/sh, which does not inherit Bash
    # functions. Keep its host commands mocked through PATH as well.
    mkdir -p "$IGOR_DIR/mock-bin"
    printf '#!/bin/sh\nexit 1\n' > "$IGOR_DIR/mock-bin/unavailable"
    chmod +x "$IGOR_DIR/mock-bin/unavailable"
    local cmd
    for cmd in crontab docker ip iptables-save ss sudo systemctl ufw; do
        ln -s unavailable "$IGOR_DIR/mock-bin/$cmd"
    done
    export PATH="$IGOR_DIR/mock-bin:$PATH"

    source "$REPO_DIR/core/recovery/config_backup.sh"
    source "$REPO_DIR/core/recovery/full_backup.sh"
}

teardown() {
    teardown_igor_tmpdir
}

@test "config backup returns only the archive path on stdout" {
    mkdir -p "$IGOR_DIR/config/variables"
    printf 'TEST_BACKUP_VALUE=ok\n' > "$IGOR_DIR/config/variables/test.env"

    local archive
    archive=$(config_backup_take regression)
    [ -f "$archive" ]
    [[ "$archive" == "$IGOR_DIR/data/backups/config_"*.tar.gz ]]
    [ "$(tar -tzf "$archive" | grep -c '^manifest.txt$')" -eq 1 ]
}

@test "full backup stores an independent readable core copy" {
    mkdir -p "$IGOR_DIR/config/variables"
    printf 'FULL_COPY_VALUE=present\n' > "$IGOR_DIR/config/variables/full.env"

    local dest
    dest=$(full_backup_take)
    [ -d "$dest" ]

    local archive
    archive=$(find "$dest" -maxdepth 1 -type f -name 'config_*.tar.gz' -print -quit)
    [ -f "$archive" ]
    [ ! -L "$archive" ]
    [ -r "$archive" ]
    tar -tzf "$archive" | grep -q '^manifest.txt$'
}

@test "full backup core copy survives config snapshot pruning" {
    mkdir -p "$IGOR_DIR/config/variables"
    printf 'RETENTION_VALUE=present\n' > "$IGOR_DIR/config/variables/retention.env"
    local dest archive
    dest=$(full_backup_take)
    archive=$(find "$dest" -maxdepth 1 -type f -name 'config_*.tar.gz' -print -quit)
    [ -f "$archive" ]

    # A later config rotation may remove the source archive, but the full copy
    # must remain usable because it is a real file inside the full snapshot.
    local source_archive
    source_archive=$(find "$IGOR_DIR/data/backups" -maxdepth 1 -type f -name 'config_*.tar.gz' -print -quit)
    [ -n "$source_archive" ]
    cp "$source_archive" "$IGOR_BACKUPS_DIR/config_9999999999.tar.gz"
    touch -d '2000-01-01' "$source_archive"
    BACKUP_CONFIG_KEEP=1 _mod_cb_prune_old
    [ ! -e "$source_archive" ]
    [ -f "$archive" ]
    tar -tzf "$archive" | grep -q '^manifest.txt$'
}

@test "failed core snapshot produces a partial full manifest and nonzero status" {
    config_backup_take() { printf 'progress only\n' >&2; return 1; }
    export -f config_backup_take

    run full_backup_take
    [ "$status" -ne 0 ]
    local dest
    dest=$(find "$IGOR_DIR/data/backups" -maxdepth 1 -type d -name 'full_*' -print -quit)
    [ -f "$dest/FULL_BACKUP_MANIFEST.txt" ]
    grep -q '^STATUS: PARTIAL$' "$dest/FULL_BACKUP_MANIFEST.txt"
    ! grep -q '^STATUS: COMPLETE$' "$dest/FULL_BACKUP_MANIFEST.txt"
}

@test "a zero-exit snapshot without an archive is a full backup failure" {
    config_backup_take() { printf '%s' "$IGOR_DIR/does-not-exist.tar.gz"; }
    run full_backup_take
    [ "$status" -ne 0 ]
    local dest
    dest=$(find "$IGOR_BACKUPS_DIR" -maxdepth 1 -type d -name 'full_*' -print -quit)
    grep -q '^STATUS: PARTIAL$' "$dest/FULL_BACKUP_MANIFEST.txt"
    grep -q '^ERROR: core snapshot missing or copy failed$' "$dest/FULL_BACKUP_MANIFEST.txt"
}

@test "copy failure is reported instead of claiming a complete backup" {
    printf fixture > "$IGOR_BACKUPS_DIR/config_fixture.tar.gz"
    config_backup_take() { printf '%s' "$IGOR_BACKUPS_DIR/config_fixture.tar.gz"; }
    cp() { return 1; }
    run full_backup_take
    [ "$status" -ne 0 ]
    local dest
    dest=$(find "$IGOR_BACKUPS_DIR" -maxdepth 1 -type d -name 'full_*' -print -quit)
    grep -q '^STATUS: PARTIAL$' "$dest/FULL_BACKUP_MANIFEST.txt"
    grep -q '^ERROR: core snapshot missing or copy failed$' "$dest/FULL_BACKUP_MANIFEST.txt"
}

@test "failed module hook creates a partial backup and no success event" {
    local event_file="$IGOR_DIR/events"
    notify_event() { printf '%s\t%s\n' "$1" "$2" >> "$event_file"; }
    export -f notify_event
    igor_run_all_hooks() { return 1; }
    export -f igor_run_all_hooks

    run full_backup_take
    [ "$status" -ne 0 ]
    local dest
    dest=$(find "$IGOR_DIR/data/backups" -maxdepth 1 -type d -name 'full_*' -print -quit)
    grep -q '^STATUS: PARTIAL$' "$dest/FULL_BACKUP_MANIFEST.txt"
    grep -q '^ERROR: module backup hooks failed' "$dest/FULL_BACKUP_MANIFEST.txt"
    grep -q $'^backup_fail\tFull backup FAILED' "$event_file"
    ! grep -q $'^backup_done\tFull backup complete' "$event_file"
}

@test "failed replacement does not prune a known good full backup" {
    export BACKUP_FULL_KEEP=1
    mkdir -p "$IGOR_DIR/config/variables"
    printf 'GOOD_BACKUP=1\n' > "$IGOR_DIR/config/variables/good.env"
    local good
    good=$(full_backup_take)

    config_backup_take() { return 1; }
    export -f config_backup_take
    run full_backup_take
    [ "$status" -ne 0 ]
    [ -d "$good" ]
    grep -q '^STATUS: COMPLETE$' "$good/FULL_BACKUP_MANIFEST.txt"
}

@test "partial backups do not count against complete backup retention" {
    mkdir -p "$IGOR_BACKUPS_DIR/full_1_old" "$IGOR_BACKUPS_DIR/full_2_partial" "$IGOR_BACKUPS_DIR/full_3_new"
    printf 'STATUS: COMPLETE\n' > "$IGOR_BACKUPS_DIR/full_1_old/FULL_BACKUP_MANIFEST.txt"
    printf 'STATUS: PARTIAL\n' > "$IGOR_BACKUPS_DIR/full_2_partial/FULL_BACKUP_MANIFEST.txt"
    printf 'STATUS: COMPLETE\n' > "$IGOR_BACKUPS_DIR/full_3_new/FULL_BACKUP_MANIFEST.txt"
    touch -d '2000-01-01' "$IGOR_BACKUPS_DIR/full_1_old"
    touch -d '2001-01-01' "$IGOR_BACKUPS_DIR/full_2_partial"
    BACKUP_FULL_KEEP=2 _mod_fb_prune_old
    [ -d "$IGOR_BACKUPS_DIR/full_1_old" ]
    [ -d "$IGOR_BACKUPS_DIR/full_3_new" ]
}

@test "timed-out registered hook is recorded as a partial backup" {
    source "$REPO_DIR/core/lib/module_loader.sh"
    _backup_slow() { sleep 2; }
    igor_register_hook backup _backup_slow
    IGOR_HOOK_TIMEOUT=0.1
    run full_backup_take
    [ "$status" -ne 0 ]
    local dest
    dest=$(find "$IGOR_BACKUPS_DIR" -maxdepth 1 -type d -name 'full_*' -print -quit)
    grep -q '^STATUS: PARTIAL$' "$dest/FULL_BACKUP_MANIFEST.txt"
    grep -q '_backup_slow timed out' "$dest/MODULE_BACKUP_ERRORS.txt"
}

@test "fallback hook dispatch reports missing and failed hooks" {
    _fallback_good() { :; }
    _fallback_bad() { return 7; }
    igor_get_hooks() { printf '%s\n' _fallback_good _fallback_missing _fallback_bad; }
    export -f igor_get_hooks _fallback_good _fallback_bad
    unset -f igor_run_all_hooks 2>/dev/null || true

    local errors
    errors="$IGOR_DIR/hook-errors"
    if _mod_fb_run_hooks "$IGOR_DIR/data/backups" 2>"$errors"; then
        return 1
    fi
    grep -q 'Backup hook missing: _fallback_missing' "$errors"
    grep -q 'Backup hook failed: _fallback_bad' "$errors"
}

@test "no registered fallback hooks is successful" {
    igor_get_hooks() { :; }
    export -f igor_get_hooks
    unset -f igor_run_all_hooks 2>/dev/null || true
    _mod_fb_run_hooks "$IGOR_DIR/data/backups"
}

@test "encrypted secrets snapshot contains only the GPG payload" {
    command -v gpg >/dev/null || skip "gpg unavailable"
    mkdir -p "$IGOR_DIR/config/variables" "$IGOR_DIR/secrets"
    export GNUPGHOME="$IGOR_DIR/gnupg"
    mkdir -p "$GNUPGHOME"
    chmod 700 "$GNUPGHOME"
    # Some restricted runners cannot create the gpg-agent socket. Keep the
    # test deterministic there while still exercising real GPG where it works.
    if ! printf 'probe-secret\n' | gpg --batch --yes --pinentry-mode loopback \
        --passphrase probe-pass --symmetric --output "$IGOR_DIR/probe.gpg"; then
        skip "GPG agent unavailable in this runner"
    fi
    printf 'ENC_VALUE=present\n' > "$IGOR_DIR/config/variables/encrypted.env"
    printf 'SECRET_VALUE=fixture-only\n' > "$IGOR_DIR/secrets/site.env"

    # The helper allocates a PTY, allowing the real prompt/read path to run.
    # The passphrase is fixture data and never leaves this temporary snapshot.
    local output_file="$IGOR_DIR/pty-output"
    python3 "$BATS_TEST_DIRNAME/../helpers/pty_command.py" \
        "source '$REPO_DIR/core/recovery/config_backup.sh'; config_backup_take encrypted" \
        $'y\nfixture-passphrase\nfixture-passphrase\n' >"$output_file" 2>&1

    local archive
    archive=$(find "$IGOR_DIR/data/backups" -maxdepth 1 -type f -name 'config_*-enc.tar.gz' -print -quit)
    [ -f "$archive" ]
    tar -tzf "$archive" | grep -q 'igor-state/secrets-plain.tar.gz.gpg'
    if tar -tzf "$archive" | grep -q 'igor-state/secrets-plain/site.env'; then
        return 1
    fi
    local encrypted
    encrypted="$IGOR_DIR/decrypted.tar.gz"
    tar -xOf "$archive" igor-state/secrets-plain.tar.gz.gpg > "$IGOR_DIR/secrets.gpg"
    gpg --batch --pinentry-mode loopback --passphrase fixture-passphrase \
        --decrypt --output "$encrypted" "$IGOR_DIR/secrets.gpg" 2>/dev/null
    tar -xOf "$encrypted" secrets-plain/site.env | grep -q '^SECRET_VALUE=fixture-only$'
}
