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
    # Both Bash and the JSON snapshot subprocess stay off host command paths.
    mkdir -p "$IGOR_DIR/mock-bin"
    printf '#!/bin/sh\nexit 1\n' > "$IGOR_DIR/mock-bin/unavailable"
    chmod +x "$IGOR_DIR/mock-bin/unavailable"
    local cmd
    for cmd in crontab docker ip iptables-save ss sudo systemctl ufw; do
        ln -s unavailable "$IGOR_DIR/mock-bin/$cmd"
    done
    export PATH="$IGOR_DIR/mock-bin:$PATH"
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

@test "managed OpenRouter backup omits selected legacy sources and restore refuses old copies" {
    _mod_cb_openrouter_guard() { return 0; }
    mkdir -p "$IGOR_DIR/config/variables"
    printf 'synthetic-managed-key\n' > "$IGOR_DIR/secrets/openrouter.key"
    printf 'OPENROUTER_API_KEY=synthetic-env-key\nOTHER=safe\n' > "$IGOR_DIR/secrets/provider.env"
    printf 'UNRELATED=safe\n' > "$IGOR_DIR/secrets/other.env"
    printf 'OPENROUTER_API_KEY=synthetic-var-key\n' > "$IGOR_DIR/config/variables/provider.env"
    printf 'FEATURE=enabled\n' > "$IGOR_DIR/config/variables/other.env"
    local archive inventory
    archive=$(config_backup_take managed-openrouter)
    [ -f "$archive" ]
    inventory=$(tar -tzf "$archive")
    [[ "$inventory" != *igor-state/secrets-plain/openrouter.key* ]]
    [[ "$inventory" != *igor-state/secrets-plain/provider.env* ]]
    [[ "$inventory" != *igor-state/variables/provider.env* ]]
    tar -tzf "$archive" | grep -q '^igor-state/secrets-plain/other.env$'
    tar -tzf "$archive" | grep -q '^igor-state/variables/other.env$'
    tar -tzf "$archive" | grep -q '^igor-state/openrouter-credential-omitted.txt$'

    local old_tree="$BATS_TEST_TMPDIR/old"
    mkdir -p "$old_tree/igor-state/secrets-plain"
    printf 'synthetic-old-key\n' > "$old_tree/igor-state/secrets-plain/openrouter.key"
    printf 'UNRELATED=restored\n' > "$old_tree/igor-state/secrets-plain/other.env"
    printf 'old archive\n' > "$old_tree/manifest.txt"
    local old_archive="$BATS_TEST_TMPDIR/old.tar.gz"
    tar -czf "$old_archive" -C "$old_tree" .
    config_backup_restore "$old_archive" igor-state || true
    [ "$(cat "$IGOR_DIR/secrets/openrouter.key")" = synthetic-managed-key ]
    grep -q '^UNRELATED=restored$' "$IGOR_DIR/secrets/other.env"
}

@test "managed restore hides and preserves live selected assignments against an unrelated older file" {
    _mod_cb_openrouter_guard() { return 0; }
    warn() { printf '%s\n' "$*"; }
    mkdir -p "$IGOR_DIR/config/variables"
    printf 'OPENROUTER_API_KEY=synthetic-live-preview-sentinel\nOTHER=live\n' > "$IGOR_DIR/config/variables/provider.env"
    local old_tree="$BATS_TEST_TMPDIR/preview-old"
    mkdir -p "$old_tree/igor-state/variables"
    printf 'OTHER=old\n' > "$old_tree/igor-state/variables/provider.env"
    printf 'old archive\n' > "$old_tree/manifest.txt"
    local old_archive="$BATS_TEST_TMPDIR/preview-old.tar.gz"
    tar -czf "$old_archive" -C "$old_tree" .

    run config_backup_restore "$old_archive" igor-state
    [[ "$output" != *synthetic-live-preview-sentinel* ]]
    [[ "$output" == *"Refusing selected credential source"* ]]
    grep -q '^OTHER=live$' "$IGOR_DIR/config/variables/provider.env"
}

@test "managed restore retains unrelated nested variables while refusing selected and linked destinations" {
    _mod_cb_openrouter_guard() { return 0; }
    local old_tree="$BATS_TEST_TMPDIR/nested-old"
    mkdir -p "$old_tree/igor-state/variables/nested" "$IGOR_DIR/config/variables/nested"
    printf 'FEATURE=restored\n' > "$old_tree/igor-state/variables/nested/safe.env"
    printf 'OPENROUTER_API_KEY=synthetic-old-nested-source\n' > "$old_tree/igor-state/variables/nested/provider.env"
    printf 'FEATURE=linked-overwrite\n' > "$old_tree/igor-state/variables/nested/link.env"
    printf 'protected-private-sentinel\n' > "$IGOR_DIR/secrets/protected.key"
    ln -s "$IGOR_DIR/secrets/protected.key" "$IGOR_DIR/config/variables/nested/link.env"
    printf 'old archive\n' > "$old_tree/manifest.txt"
    local old_archive="$BATS_TEST_TMPDIR/nested-old.tar.gz"
    tar -czf "$old_archive" -C "$old_tree" .

    config_backup_restore "$old_archive" igor-state || true
    grep -q '^FEATURE=restored$' "$IGOR_DIR/config/variables/nested/safe.env"
    [ ! -e "$IGOR_DIR/config/variables/nested/provider.env" ]
    [ "$(cat "$IGOR_DIR/secrets/protected.key")" = protected-private-sentinel ]
}

@test "unavailable credential status fences ordinary snapshot without copying protected material" {
    # Exercise the production guard's failure path, not a fake managed boolean.
    export _IGOR_LOADER_DIR="$IGOR_DIR/missing-core"
    mkdir -p "$IGOR_DIR/secrets/.managed" "$IGOR_DIR/config/variables"
    printf 'synthetic-private-generation\n' > "$IGOR_DIR/secrets/.managed/generation"
    printf 'synthetic-retained-source\n' > "$IGOR_DIR/secrets/openrouter.key"
    printf 'FEATURE=kept\n' > "$IGOR_DIR/config/variables/feature.env"
    local archive inventory
    archive=$(config_backup_take unavailable-openrouter)
    inventory=$(tar -tzf "$archive")
    [[ "$inventory" != *openrouter.key* ]]
    [[ "$inventory" != *.managed* ]]
    [[ "$inventory" == *openrouter-credential-omitted.txt* ]]
    tar -xOzf "$archive" igor-state/variables/feature.env | grep -q '^FEATURE=kept$'
}

@test "corrupt production credential catalog fences retained sources without repairing it" {
    export _IGOR_LOADER_DIR="$REPO_DIR"
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    export IGOR_SECRETS_DIR="$IGOR_DIR/secrets"
    mkdir -p "$IGOR_DIR/data/secrets" "$IGOR_DIR/secrets/.managed"
    chmod 700 "$IGOR_DIR/data/secrets" "$IGOR_DIR/secrets" "$IGOR_DIR/secrets/.managed"
    printf 'damaged-metadata-fixture\n' > "$IGOR_DIR/data/secrets/catalog.db"
    chmod 600 "$IGOR_DIR/data/secrets/catalog.db"
    printf 'synthetic-retained-corrupt-source\n' > "$IGOR_DIR/secrets/openrouter.key"

    _mod_cb_openrouter_guard
    [ "$(cat "$IGOR_DIR/data/secrets/catalog.db")" = damaged-metadata-fixture ]
    local archive inventory
    archive=$(config_backup_take corrupt-openrouter)
    inventory=$(tar -tzf "$archive")
    [[ "$inventory" != *openrouter.key* ]]
    [[ "$inventory" == *openrouter-credential-omitted.txt* ]]
    [ "$(cat "$IGOR_DIR/data/secrets/catalog.db")" = damaged-metadata-fixture ]
}

@test "pending first import omits its retained source from backup while runtime cutover remains false" {
    export _IGOR_LOADER_DIR="$REPO_DIR"
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    export IGOR_SECRETS_DIR="$IGOR_DIR/secrets"
    chmod 700 "$IGOR_DIR/secrets"
    printf 'synthetic-pending-original\n' > "$IGOR_DIR/secrets/openrouter.key"
    chmod 600 "$IGOR_DIR/secrets/openrouter.key"
    python3 - "$REPO_DIR/core/lib" "$IGOR_DIR" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from secret_refs import ManagedOpenRouterSecret
root = Path(sys.argv[2])
service = ManagedOpenRouterSecret(root / "secrets", root / "data")
service.stage(b"synthetic-pending-original", source_kind="private_input", expected_revision=0)
assert service.status()["pending"]
assert not service.cutover_marker()
PY
    _mod_cb_openrouter_guard
    local archive inventory
    archive=$(config_backup_take pending-openrouter)
    inventory=$(tar -tzf "$archive")
    [[ "$inventory" != *openrouter.key* ]]
    [[ "$inventory" == *openrouter-credential-omitted.txt* ]]
    [ "$(cat "$IGOR_DIR/secrets/openrouter.key")" = synthetic-pending-original ]
}

@test "full backup makes selected credential omission visible and retains unrelated snapshot" {
    _mod_cb_openrouter_guard() { return 0; }
    igor_get_hooks() { :; }
    source "$REPO_DIR/core/recovery/full_backup.sh"
    mkdir -p "$IGOR_DIR/config/variables"
    printf 'FEATURE=kept\n' > "$IGOR_DIR/config/variables/feature.env"
    local dest archive
    dest=$(full_backup_take)
    grep -q '^OPENROUTER: .*omitted' "$dest/FULL_BACKUP_MANIFEST.txt"
    archive=$(find "$dest" -maxdepth 1 -name 'config_*.tar.gz' -print -quit)
    tar -tzf "$archive" | grep -q '^igor-state/openrouter-credential-omitted.txt$'
    tar -xOzf "$archive" igor-state/variables/feature.env | grep -q '^FEATURE=kept$'
}
