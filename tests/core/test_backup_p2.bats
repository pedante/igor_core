#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_BACKUPS_DIR="$IGOR_DIR/data/backups"
    step() { :; }
    ok() { :; }
    info() { :; }
    warn() { :; }
    fail() { :; }
    confirm() { return 0; }
    export -f step ok info warn fail confirm
    source "$REPO_DIR/core/recovery/config_backup.sh"
}

teardown() {
    teardown_igor_tmpdir
}

@test "core backup captures and restores module-declared secret env files" {
    mkdir -p "$IGOR_DIR/config/variables"
    printf 'DEFAULT_SECRET=one\n' > "$IGOR_DIR/secrets/site.env"
    printf 'MODULE_SECRET=two\n' > "$IGOR_DIR/secrets/my_service.env"
    printf 'API_KEY=three\n' > "$IGOR_DIR/secrets/my_service.key"

    local archive
    archive=$(config_backup_take p2-custom-secrets)
    tar -tzf "$archive" | grep -q '^igor-state/secrets-plain/my_service.env$'
    tar -tzf "$archive" | grep -q '^igor-state/secrets-plain/my_service.key$'

    rm "$IGOR_DIR/secrets/site.env" "$IGOR_DIR/secrets/my_service.env" "$IGOR_DIR/secrets/my_service.key"
    config_backup_restore "$archive" igor-state || true

    grep -q '^DEFAULT_SECRET=one$' "$IGOR_DIR/secrets/site.env"
    grep -q '^MODULE_SECRET=two$' "$IGOR_DIR/secrets/my_service.env"
    grep -q '^API_KEY=three$' "$IGOR_DIR/secrets/my_service.key"
    [ "$(stat -c '%a' "$IGOR_DIR/secrets/my_service.env")" = 600 ]
    [ "$(stat -c '%a' "$IGOR_DIR/secrets/my_service.key")" = 600 ]
}

@test "declining the all-scope Igor state step skips its restore" {
    mkdir -p "$IGOR_DIR/config/variables"
    printf 'ORIGINAL=one\n' > "$IGOR_DIR/config/variables/state.env"
    printf 'SECRET_ORIGINAL=one\n' > "$IGOR_DIR/secrets/site.env"
    local archive
    archive=$(config_backup_take p2-decline)

    printf 'ORIGINAL=two\n' > "$IGOR_DIR/config/variables/state.env"
    printf 'SECRET_ORIGINAL=two\n' > "$IGOR_DIR/secrets/site.env"
    confirm() { return 1; }
    export -f confirm
    config_backup_restore "$archive" all || true

    grep -q '^ORIGINAL=two$' "$IGOR_DIR/config/variables/state.env"
    grep -q '^SECRET_ORIGINAL=two$' "$IGOR_DIR/secrets/site.env"
}

@test "restore refuses a symlinked secrets directory" {
    mkdir -p "$IGOR_DIR/outside"
    printf 'OUTSIDE=untouched\n' > "$IGOR_DIR/outside/site.env"
    printf 'MODULE_SECRET=two\n' > "$IGOR_DIR/secrets/my_service.env"
    local archive
    archive=$(config_backup_take p2-symlink)

    rm -rf "$IGOR_DIR/secrets"
    ln -s "$IGOR_DIR/outside" "$IGOR_DIR/secrets"
    config_backup_restore "$archive" igor-state || true

    grep -q '^OUTSIDE=untouched$' "$IGOR_DIR/outside/site.env"
    [ ! -e "$IGOR_DIR/outside/my_service.env" ]
}
