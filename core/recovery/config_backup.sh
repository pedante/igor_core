#!/bin/bash
# IGOR — recovery/config_backup.sh
# Core snapshot — module-agnostic environment capture.
#
# What is captured (no module dependency):
#   Igor state   — config/variables/ dir, secrets/ dir (with optional encryption)
#   System       — crontabs, fstab, hosts, hostname, timezone, sshd, ufw, services
#   Docker       — compose files and .env files found under DATA_ROOT, network/volume/container state
#   Network      — ip addr/route, resolv.conf, cloudflared/caddy if present
#   JSON index   — igor-snapshot.json (machine-readable, safe to email)
#
# Module-specific data is captured via the hook API (called from full_backup.sh):
#   modules/*/hooks/backup.sh → igor_module_backup_hook "$SNAPSHOT_DIR" "$MODULE_NAME"
#
# Storage: $IGOR_BACKUP_DIR/config_{EPOCH}[-enc].tar.gz  (chmod 600)
#
# Public functions:
#   config_backup_take [REASON]             — create a full core snapshot archive
#   config_backup_list [--full]             — list existing backups
#   config_backup_restore [ARCHIVE] [SCOPE] — staged restore with diff + confirm
#   config_backup_secrets                   — GPG + secrets backup (root-only)
#   config_backup_auto [REASON]             — fire-and-forget hook (never blocks/fails)
#   _mod_cb_prune_old                       — remove oldest beyond BACKUP_CONFIG_KEEP

# ── Path resolution (fixes the hardcoded /data bug) ──────────────────────────
# _igor_resolve_dir is provided by core/lib/helpers.sh.
# If not yet loaded (e.g. cron context), fall back gracefully.
_cb_backup_dir() {
    if declare -f _igor_resolve_dir &>/dev/null; then
        _igor_resolve_dir backups
    else
        echo "${IGOR_BACKUPS_DIR:-${IGOR_DIR}/data/backups}"
    fi
}
BACKUP_DIR="$(_cb_backup_dir)"

# Return supported secret files without following directory entries that are
# symlinks.  Module manifests may declare any secrets/*.env file; *.key files
# are also part of the supported secrets store.  Keep the archive flat for
# compatibility with existing snapshots and restore logic.
_mod_cb_secret_files() {
    local secrets_dir="$1"
    [ -d "$secrets_dir" ] || return 0
    find -P "$secrets_dir" -maxdepth 1 -type f \
        \( -name '*.env' -o -name '*.key' \) -print 2>/dev/null | sort
}

# Once the selected OpenRouter credential has cut over, ordinary snapshots and
# restores must not recreate its legacy material authority. A damaged status
# also omits these candidates; it cannot be treated as a fresh installation.
_mod_cb_openrouter_guard() {
    local _state
    _state=$(IGOR_CONFIGURATION_ROOT="$IGOR_DIR" \
        IGOR_CONFIGURATION_DATA_DIR="${IGOR_DATA_DIR:-${IGOR_DIR}/data}" \
        python3 "${_IGOR_LOADER_DIR:-${IGOR_DIR}}/core/lib/configuration.py" openrouter-backup-guard 2>/dev/null) || return 0
    [ "$_state" != legacy ]
}

_mod_cb_selected_key_bearing() {
    local _path="$1" _name
    _name=$(basename -- "$_path")
    case "$_name" in
        openrouter.key|or.key|nexus.key) return 0 ;;
        *.env)
            [ -r "$_path" ] || return 0
            grep -aEq '(^|[^A-Za-z0-9_])(OPENROUTER_API_KEY|OR_API_KEY|NEXUS_API_KEY)([^A-Za-z0-9_]|$)' "$_path"
            return $? ;;
    esac
    return 1
}

# The managed-key restore fence still restores unrelated nested variables. Do
# not let an existing destination link redirect that copy into private material.
_mod_cb_variable_destination_safe() {
    local _path="$1" _root="${IGOR_DIR}/config/variables"
    while [[ "$_path" == "$_root" || "$_path" == "$_root/"* ]]; do
        [ ! -L "$_path" ] || return 1
        [ "$_path" != "$_root" ] || return 0
        _path=$(dirname -- "$_path")
    done
    return 1
}

_mod_cb_docker_available() {
    if declare -f igor_has_capability >/dev/null 2>&1; then
        igor_has_capability docker
    else
        # A binary on PATH is not activation state.  Fail closed until the
        # lifecycle/capability registry has been initialized.
        return 1
    fi
}

# ── config_backup_take [REASON] ───────────────────────────────────────────────
config_backup_take() (
    # Isolate cleanup traps and reserve stdout for the resulting archive path.
    local _cb_result_fd
    exec {_cb_result_fd}>&1
    _mod_cb_take "$@" >&2
)

_mod_cb_take() {
    local reason="${1:-manual}"
    local RED='\033[0;31m' GRN='\033[0;32m' YEL='\033[1;33m'
    local CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'

    BACKUP_DIR="$(_cb_backup_dir)"
    step "Taking core snapshot (reason: ${reason})"
    mkdir -p "$BACKUP_DIR"
    # Resolve to absolute path — relative paths break when tar runs inside (cd "$workdir" && ...)
    BACKUP_DIR=$(cd "$BACKUP_DIR" 2>/dev/null && pwd) || {
        fail "Backup directory inaccessible: $BACKUP_DIR"
        return 1
    }

    local ts; ts=$(date +%s)
    local workdir; workdir=$(mktemp -d) || return 1
    # Expand the path now: the helper's locals are gone when the subshell exits.
    # shellcheck disable=SC2064
    trap "rm -rf -- $(printf '%q' "$workdir")" EXIT

    local components=()
    local _or_guard=false
    _mod_cb_openrouter_guard && _or_guard=true

    # ── 1. Igor state — config/variables/ ────────────────────────────────────
    step "Igor state"
    local _vars_dir="${IGOR_DIR}/config/variables"
    if [ -d "$_vars_dir" ] && [ "$(ls -A "$_vars_dir" 2>/dev/null)" ]; then
        mkdir -p "${workdir}/igor-state/variables"
        if "$_or_guard"; then
            local _var_file _var_relative _var_dest
            while IFS= read -r _var_file; do
                if _mod_cb_selected_key_bearing "$_var_file"; then
                    warn "Omitted selected credential source from variables snapshot"
                    continue
                fi
                _var_relative="${_var_file#${_vars_dir}/}"
                _var_dest="${workdir}/igor-state/variables/${_var_relative}"
                mkdir -p -- "$(dirname -- "$_var_dest")"
                cp -- "$_var_file" "$_var_dest" 2>/dev/null || return 1
            done < <(find -P "$_vars_dir" -type f -print 2>/dev/null)
            components+=("igor-state/variables/")
        else
            cp -r "${_vars_dir}/." "${workdir}/igor-state/variables/" 2>/dev/null && \
                components+=("igor-state/variables/")
        fi
        local _var_count; _var_count=$(ls "${workdir}/igor-state/variables/" 2>/dev/null | wc -l)
        ok "config/variables/  (${_var_count} files)"
    else
        info "config/variables/ — empty or missing, skipped"
    fi

    # Module activation is installation state, not module content.  Preserve
    # the registry alongside Igor state so a restored host keeps optional
    # modules disabled or enabled on the next process start.
    local _module_state="${IGOR_DIR}/config/modules.conf"
    if [ -f "$_module_state" ]; then
        cp -- "$_module_state" "${workdir}/igor-state/modules.conf" 2>/dev/null && \
            components+=("igor-state/modules.conf")
    fi

    # ── 2. Igor state — secrets/ env files + API keys ────────────────────────
    local _secrets_dir="${IGOR_DIR}/secrets"
    local _secrets_captured=()
    if [ -d "$_secrets_dir" ]; then
        mkdir -p "${workdir}/igor-state/secrets-plain"
        while IFS= read -r _sf_path; do
            [ -n "$_sf_path" ] || continue
            if "$_or_guard" && _mod_cb_selected_key_bearing "$_sf_path"; then
                warn "Omitted selected credential source from secrets snapshot"
                continue
            fi
            local _sf; _sf=$(basename -- "$_sf_path")
            cp -- "$_sf_path" "${workdir}/igor-state/secrets-plain/${_sf}" 2>/dev/null && \
                _secrets_captured+=("$_sf")
        done < <(_mod_cb_secret_files "$_secrets_dir")

        if [ ${#_secrets_captured[@]} -gt 0 ]; then
            components+=("igor-state/secrets-plain/")
            ok "secrets/           (${_secrets_captured[*]})"
        else
            rmdir "${workdir}/igor-state/secrets-plain" 2>/dev/null || true
            info "secrets/ — no env or key files found, skipped"
        fi
    fi
    if "$_or_guard"; then
        printf '%s\n' 'Managed OpenRouter material and selected legacy credential sources are omitted from this ordinary snapshot. Recover through approved local re-import or retained generation.' \
            > "${workdir}/igor-state/openrouter-credential-omitted.txt"
        components+=("igor-state/openrouter-credential-omitted.txt")
    fi

    # ── 3. Igor version + git hash ────────────────────────────────────────────
    local _igor_ver; _igor_ver=$(cat "${IGOR_DIR}/VERSION" 2>/dev/null || echo "unknown")
    local _git_hash; _git_hash=$(git -C "${IGOR_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    {
        echo "IGOR_VERSION=${_igor_ver}"
        echo "GIT_HASH=${_git_hash}"
        echo "SNAPSHOT_TIME=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "SNAPSHOT_HOST=$(hostname 2>/dev/null || echo "unknown")"
        echo "REASON=${reason}"
    } > "${workdir}/igor-state/version.env" 2>/dev/null
    components+=("igor-state/version.env")
    ok "version.env         (igor ${_igor_ver} @ ${_git_hash})"

    # ── 4. System config ──────────────────────────────────────────────────────
    step "System config"
    mkdir -p "${workdir}/system"
    local _sys_captured=()

    crontab -l > "${workdir}/system/crontab.snapshot" 2>/dev/null && \
        { components+=("system/crontab.snapshot"); _sys_captured+=("crontab"); } || true
    sudo crontab -l > "${workdir}/system/crontab-root.snapshot" 2>/dev/null && \
        { components+=("system/crontab-root.snapshot"); _sys_captured+=("crontab-root"); } || true
    cp /etc/fstab "${workdir}/system/fstab.snapshot" 2>/dev/null && \
        { components+=("system/fstab.snapshot"); _sys_captured+=("fstab"); } || true
    cp /etc/hosts    "${workdir}/system/hosts.snapshot"    2>/dev/null && \
        { components+=("system/hosts.snapshot");    _sys_captured+=("hosts"); }    || true
    cp /etc/hostname "${workdir}/system/hostname.snapshot" 2>/dev/null && \
        { components+=("system/hostname.snapshot"); _sys_captured+=("hostname"); } || true
    cp /etc/timezone "${workdir}/system/timezone.snapshot" 2>/dev/null && \
        { components+=("system/timezone.snapshot"); _sys_captured+=("timezone"); } || true
    sudo cp /etc/ssh/sshd_config "${workdir}/system/sshd_config.snapshot" 2>/dev/null && \
        { components+=("system/sshd_config.snapshot"); _sys_captured+=("sshd_config"); } || true
    cp ~/.ssh/authorized_keys "${workdir}/system/authorized_keys.snapshot" 2>/dev/null && \
        { components+=("system/authorized_keys.snapshot"); _sys_captured+=("authorized_keys"); } || true
    sudo ufw status verbose > "${workdir}/system/ufw_status.snapshot" 2>/dev/null || \
        sudo iptables-save  > "${workdir}/system/iptables.snapshot"   2>/dev/null || true
    [ -f "${workdir}/system/ufw_status.snapshot" ] && \
        { components+=("system/ufw_status.snapshot"); _sys_captured+=("ufw"); } || true
    [ -f "${workdir}/system/iptables.snapshot" ] && \
        { components+=("system/iptables.snapshot"); _sys_captured+=("iptables"); } || true
    ss -tlnp > "${workdir}/system/open_ports.snapshot" 2>/dev/null && \
        { components+=("system/open_ports.snapshot"); _sys_captured+=("open_ports"); } || true
    systemctl list-unit-files --state=enabled --type=service --no-legend \
        > "${workdir}/system/enabled_services.snapshot" 2>/dev/null && \
        { components+=("system/enabled_services.snapshot"); _sys_captured+=("enabled_services"); } || true

    ok "system/             (${_sys_captured[*]})"

    # ── 5. Docker state ───────────────────────────────────────────────────────
    step "Docker state"
    mkdir -p "${workdir}/docker"

    # Capture config/stacks/ in full — compose files, nginx.conf, Dockerfile, etc.
    # This is the user's live stack configuration, distinct from defaults/ templates.
    local _stacks_dir="${IGOR_DIR}/config/stacks"
    if [ -d "$_stacks_dir" ] && [ "$(ls -A "$_stacks_dir" 2>/dev/null)" ]; then
        mkdir -p "${workdir}/stacks"
        cp -r "${_stacks_dir}/." "${workdir}/stacks/" 2>/dev/null
        local _stacks_count; _stacks_count=$(find "${workdir}/stacks" -type f 2>/dev/null | wc -l)
        components+=("stacks/")
        ok "config/stacks/      (${_stacks_count} files)"
    else
        info "config/stacks/ — empty or missing, skipped"
    fi

    local _docker_state=()
    if _mod_cb_docker_available; then
        docker network ls  > "${workdir}/docker/networks.snapshot"   2>/dev/null && \
            { components+=("docker/networks.snapshot");   _docker_state+=("networks"); }   || true
        docker volume ls   > "${workdir}/docker/volumes.snapshot"    2>/dev/null && \
            { components+=("docker/volumes.snapshot");    _docker_state+=("volumes"); }    || true
        docker ps          > "${workdir}/docker/containers.snapshot" 2>/dev/null && \
            { components+=("docker/containers.snapshot"); _docker_state+=("containers"); } || true
        docker images      > "${workdir}/docker/images.snapshot"     2>/dev/null && \
            { components+=("docker/images.snapshot");     _docker_state+=("images"); }     || true
    fi

    [ ${#_docker_state[@]} -gt 0 ] && \
        ok "docker state       (${_docker_state[*]})" || \
        info "docker not available — state snapshots skipped"

    # ── 6. Learned patterns ───────────────────────────────────────────────────
    local _patterns_dir="${IGOR_DIR}/config/patterns"
    if [ -d "$_patterns_dir" ] && [ "$(ls -A "$_patterns_dir" 2>/dev/null)" ]; then
        mkdir -p "${workdir}/patterns"
        cp -r "${_patterns_dir}/." "${workdir}/patterns/" 2>/dev/null
        local _pat_count; _pat_count=$(find "${workdir}/patterns" -type f 2>/dev/null | wc -l)
        components+=("patterns/")
        ok "config/patterns/    (${_pat_count} files)"
    fi

    # ── 7. Network context ────────────────────────────────────────────────────
    step "Network"
    mkdir -p "${workdir}/network"
    local _net_captured=()

    ip addr show  > "${workdir}/network/ip_addr.snapshot"  2>/dev/null && \
        { components+=("network/ip_addr.snapshot");  _net_captured+=("ip_addr"); }  || true
    ip route show > "${workdir}/network/ip_route.snapshot" 2>/dev/null && \
        { components+=("network/ip_route.snapshot"); _net_captured+=("ip_route"); } || true
    cp /etc/resolv.conf "${workdir}/network/resolv.conf.snapshot" 2>/dev/null && \
        { components+=("network/resolv.conf.snapshot"); _net_captured+=("resolv.conf"); } || true

    for _cf_cfg in /etc/cloudflared/config.yml \
                   "${HOME}/.cloudflared/config.yml" \
                   "${IGOR_DIR}/cloudflared.yml"; do
        if [ -f "$_cf_cfg" ]; then
            sudo cp "$_cf_cfg" "${workdir}/network/cloudflared.conf.snapshot" 2>/dev/null || \
                cp  "$_cf_cfg" "${workdir}/network/cloudflared.conf.snapshot" 2>/dev/null || true
            [ -f "${workdir}/network/cloudflared.conf.snapshot" ] && \
                { components+=("network/cloudflared.conf.snapshot"); _net_captured+=("cloudflared"); }
            break
        fi
    done

    for _caddy in /etc/caddy/Caddyfile "${IGOR_DIR}/Caddyfile"; do
        if [ -f "$_caddy" ]; then
            cp "$_caddy" "${workdir}/network/Caddyfile.snapshot" 2>/dev/null && \
                { components+=("network/Caddyfile.snapshot"); _net_captured+=("Caddyfile"); }
            break
        fi
    done

    ok "network/            (${_net_captured[*]:-none})"

    if [ ${#components[@]} -eq 0 ]; then
        fail "No components captured — snapshot aborted"
        return 1
    fi

    echo ""
    info "$(printf '─%.0s' {1..45})"
    info "Total: ${#components[@]} items captured"
    echo ""

    # ── 7. Secrets encryption prompt ─────────────────────────────────────────
    # NOT called via $() — that captures stdout and breaks read/echo display.
    # Result is communicated via _CB_ENC_RESULT global.
    local _enc_suffix=""
    _CB_ENC_RESULT=""
    if [ -t 0 ] && [ -t 2 ]; then
        _mod_cb_encrypt_secrets_prompt "$workdir"
        if [ "$_CB_ENC_RESULT" = "enc" ]; then
            _enc_suffix="-enc"
            local i
            for i in "${!components[@]}"; do
                if [ "${components[$i]}" = "igor-state/secrets-plain/" ]; then
                    components[$i]="igor-state/secrets-plain.tar.gz.gpg"
                fi
            done
        fi
    fi

    # ── 8. Generate igor-snapshot.json ────────────────────────────────────────
    local _docker_available=false
    _mod_cb_docker_available && _docker_available=true
    IGOR_DOCKER_AVAILABLE="$_docker_available" _mod_cb_generate_json "$workdir" "$reason"
    [ -f "${workdir}/igor-snapshot.json" ] && components+=("igor-snapshot.json")

    # ── 9. Write manifest.txt ─────────────────────────────────────────────────
    _mod_cb_write_manifest "$workdir" "$reason" "${components[@]}" > "${workdir}/manifest.txt"

    # ── 10. Create tar.gz ─────────────────────────────────────────────────────
    local archive="${BACKUP_DIR}/config_${ts}${_enc_suffix}.tar.gz"
    local _tar_err
    _tar_err=$(cd "$workdir" && tar -czf "$archive" manifest.txt "${components[@]}" 2>&1)
    local tar_rc=$?
    chmod 600 "$archive" 2>/dev/null || true

    if [ $tar_rc -ne 0 ]; then
        fail "Archive creation failed${_tar_err:+: ${_tar_err}}"
        rm -f "$archive"
        declare -f notify_event &>/dev/null && \
            notify_event "backup_fail" \
                "Core snapshot FAILED (reason: ${reason}) — archive error" \
                "Snapshot Failed" 2>/dev/null || true
        return 1
    fi

    local sz; sz=$(du -sh "$archive" 2>/dev/null | cut -f1)
    ok "Snapshot saved: $(basename "${archive}") (${sz})"

    # ── Journal + prune ───────────────────────────────────────────────────────
    declare -f journal_record &>/dev/null && \
        journal_record "menu:recovery" "backup_taken" "CHANGE" \
            "config_backup_take $reason" "OK" \
            "archive:$(basename "$archive") size:${sz}"

    declare -f notify_event &>/dev/null && \
        notify_event "backup_done" \
            "Core snapshot completed (${sz}) — reason: ${reason}" \
            "Snapshot Done" 2>/dev/null || true

    _mod_cb_prune_old

    # Return archive path to caller
    printf '%s\n' "$archive" >&"$_cb_result_fd"
}

# ── _mod_cb_encrypt_secrets_prompt WORKDIR ────────────────────────────────────
# Prompts for GPG symmetric encryption of the secrets-plain subdir.
# Result communicated via global _CB_ENC_RESULT ("enc" or "").
# MUST be called directly — never via $() — so that read/echo reach the terminal.
_mod_cb_encrypt_secrets_prompt() {
    local workdir="$1"
    local CYAN='\033[0;36m' YEL='\033[1;33m' BOLD='\033[1m' NC='\033[0m'
    _CB_ENC_RESULT=""

    local _sp="${workdir}/igor-state/secrets-plain"
    if [ ! -d "$_sp" ] || [ -z "$(ls -A "$_sp" 2>/dev/null)" ]; then
        # Nothing to encrypt
        return 0
    fi

    local _files; _files=$(ls "$_sp" 2>/dev/null | tr '\n' ' ')

    echo ""
    echo -e "  ${CYAN}${BOLD}Encrypt secrets before archiving?${NC}"
    echo -e "  Files that will be encrypted: ${YEL}${_files}${NC}"
    echo ""
    echo -e "  ${BOLD}[y]${NC} Yes — GPG passphrase-encrypt  (recommended for email or offsite storage)"
    echo -e "  ${BOLD}[n]${NC} No  — include plaintext        (local storage only, chmod 600)"
    echo ""
    # Read directly from /dev/tty — works even if stdin is redirected
    read -rp "  Choice [y/N]: " _enc_choice </dev/tty

    [[ "$_enc_choice" =~ ^[yY]$ ]] || return 0

    local passphrase passphrase2
    printf "  Passphrase: " >/dev/tty
    read -rsp "" passphrase </dev/tty
    printf "\n  Confirm:    " >/dev/tty
    read -rsp "" passphrase2 </dev/tty
    printf "\n" >/dev/tty

    if [ -z "$passphrase" ]; then
        warn "Empty passphrase — secrets will be stored plaintext"
        return 0
    fi
    if [ "$passphrase" != "$passphrase2" ]; then
        warn "Passphrases do not match — secrets will be stored plaintext"
        return 0
    fi

    (cd "${workdir}/igor-state" && \
     tar -czf secrets-plain.tar.gz secrets-plain/ 2>/dev/null && \
     gpg --batch --yes --symmetric \
         --pinentry-mode loopback \
         --passphrase-fd 3 \
         --output secrets-plain.tar.gz.gpg \
         secrets-plain.tar.gz 2>/dev/null 3<<<"$passphrase" && \
     rm -rf secrets-plain/ secrets-plain.tar.gz) || {
        warn "GPG encryption failed — secrets will be stored plaintext"
        return 0
    }

    ok "Secrets encrypted → secrets-plain.tar.gz.gpg (decrypt with: gpg -d)"
    _CB_ENC_RESULT="enc"
}

# ── _mod_cb_generate_json WORKDIR REASON ──────────────────────────────────────
# Writes igor-snapshot.json: structured machine-readable snapshot index.
_mod_cb_generate_json() {
    local workdir="$1" reason="${2:-manual}"
    python3 - "$workdir" "$reason" <<'PYEOF' 2>/dev/null || true
import json, subprocess, os, sys, datetime

workdir = sys.argv[1]
reason  = sys.argv[2]

def run(cmd, default=''):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL,
                                       timeout=6).decode(errors='replace').strip()
    except Exception:
        return default

def run_lines(cmd):
    return [l for l in run(cmd).splitlines() if l.strip()]

igor_dir = os.environ.get('IGOR_DIR', '.')
docker_available = os.environ.get('IGOR_DOCKER_AVAILABLE') == 'true'

snapshot = {
    "igor": {
        "version": open(os.path.join(igor_dir, 'VERSION')).read().strip()
                   if os.path.exists(os.path.join(igor_dir, 'VERSION')) else "unknown",
        "git_hash": run(f"git -C {igor_dir} rev-parse --short HEAD"),
        "timestamp": datetime.datetime.now().isoformat(),
        "hostname":  run("hostname -f") or run("hostname"),
        "reason":    reason,
    },
    "system": {
        "hostname":         run("hostname -f"),
        "timezone":         run("cat /etc/timezone"),
        "ufw_status":       run("ufw status verbose"),
        "open_ports":       run_lines("ss -tlnp"),
        "enabled_services": run_lines("systemctl list-unit-files --state=enabled --type=service --no-legend"),
    },
    "docker": ({
        "networks":   run_lines("docker network ls --format '{{.Name}}'"),
        "volumes":    run_lines("docker volume ls  --format '{{.Name}}'"),
        "containers": run_lines("docker ps         --format '{{.Names}}\t{{.Status}}\t{{.Image}}'"),
    } if docker_available else {}),
    "network": {
        "addresses": run("ip addr show"),
        "routes":    run("ip route show"),
        "dns":       run("cat /etc/resolv.conf"),
    },
}

with open(os.path.join(workdir, 'igor-snapshot.json'), 'w') as f:
    json.dump(snapshot, f, indent=2)
PYEOF
}

# ── _mod_cb_write_manifest WORKDIR REASON COMPONENTS... ───────────────────────
_mod_cb_write_manifest() {
    local workdir="$1" reason="$2"; shift 2
    local components=("$@")

    cat <<EOF
IGOR Core Snapshot
TIMESTAMP: $(date "+%Y-%m-%d %H:%M:%S")
HOST:      $(hostname 2>/dev/null || echo "unknown")
REASON:    ${reason}
IGOR_VER:  $(cat "${IGOR_DIR}/VERSION" 2>/dev/null || echo "unknown")
WARNING:   Contains credentials. chmod 600. Do not share or commit.

COMPONENTS:
EOF
    local c
    for c in "${components[@]}"; do
        local path="${workdir}/${c}"
        local sz=0
        if [ -f "$path" ]; then
            sz=$(stat -c%s "$path" 2>/dev/null || echo 0)
            printf '  %-50s %8d bytes\n' "$c" "$sz"
        elif [ -d "$path" ]; then
            sz=$(du -sb "$path" 2>/dev/null | cut -f1 || echo 0)
            printf '  %-50s %8d bytes (dir)\n' "$c" "$sz"
        fi
    done
    echo ""
    echo "RESTORE_CMD: bash igor.sh  ->  V  ->  4 (Browse Snapshots)"
}

# ── config_backup_list [--full] ───────────────────────────────────────────────
config_backup_list() {
    local full=false
    [ "${1:-}" = "--full" ] && full=true

    BACKUP_DIR="$(_cb_backup_dir)"
    local CYAN='\033[0;36m' BOLD='\033[1m' YEL='\033[1;33m' NC='\033[0m'

    echo ""
    printf "  ${BOLD}%-4s  %-19s  %-8s  %-6s  %-4s  %s${NC}\n" \
        "#" "DATE" "SIZE" "FILES" "ENC" "ARCHIVE"
    printf "  %s\n" "$(printf '─%.0s' {1..75})"

    local i=0 archives=()
    while IFS= read -r f; do
        archives+=("$f")
    done < <(ls -t "${BACKUP_DIR}"/config_*.tar.gz 2>/dev/null)

    if [ ${#archives[@]} -eq 0 ]; then
        echo "  (no snapshots found)"
        echo ""
        return 0
    fi

    for f in "${archives[@]}"; do
        (( i++ ))
        local epoch; epoch=$(basename "$f" | grep -oE '[0-9]+' | head -1)
        local dt; dt=$(date -d "@${epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$epoch")
        local sz; sz=$(du -sh "$f" 2>/dev/null | cut -f1)
        local comp_count; comp_count=$(tar -tzf "$f" 2>/dev/null | grep -v '^manifest.txt$' | wc -l || echo "?")
        local enc_flag=""
        [[ "$(basename "$f")" == *"-enc"* ]] && enc_flag="${YEL}yes${NC}"
        printf "  %-4s  %-19s  %-8s  %-6s  %-4b  %s\n" \
            "$i" "$dt" "$sz" "$comp_count" "${enc_flag:- no }" "$(basename "$f")"
        if $full; then
            tar -xzf "$f" manifest.txt --to-stdout 2>/dev/null | grep -A 99 "COMPONENTS:" | head -25
            echo ""
        fi
    done
    echo ""
    echo "  Total: ${i} snapshot(s)  (keep: ${BACKUP_CONFIG_KEEP:-7})"
    echo ""
    _BACKUP_LIST_ARCHIVES=("${archives[@]}")
}

# ── config_backup_restore [ARCHIVE] [SCOPE] ───────────────────────────────────
# Staged restore: shows contents summary, diff, scope selection, confirm per step.
# SCOPE: igor-state | system | docker | network | all
config_backup_restore() {
    local archive="${1:-}" scope="${2:-}"
    local RED='\033[0;31m' GRN='\033[0;32m' YEL='\033[1;33m'
    local CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'

    BACKUP_DIR="$(_cb_backup_dir)"
    local _or_guard=false
    _mod_cb_openrouter_guard && _or_guard=true

    # Archive picker
    if [ -z "$archive" ]; then
        config_backup_list
        [ ${#_BACKUP_LIST_ARCHIVES[@]} -eq 0 ] && return 1
        read -rp "  Select snapshot number: " _sel
        archive="${_BACKUP_LIST_ARCHIVES[$(( _sel - 1 ))]}"
        [ -z "$archive" ] || [ ! -f "$archive" ] && { fail "Invalid selection"; return 1; }
    fi
    [ ! -f "$archive" ] && { fail "Archive not found: $archive"; return 1; }

    # Show contents summary
    echo ""
    echo -e "  ${BOLD}Snapshot contents:${NC}"
    tar -xzf "$archive" manifest.txt --to-stdout 2>/dev/null || true
    echo ""

    # Encrypted check
    if [[ "$(basename "$archive")" == *"-enc"* ]]; then
        echo -e "  ${YEL}Note:${NC} This snapshot contains encrypted secrets (secrets-plain.tar.gz.gpg)."
        echo "  You will need the passphrase used at backup time to restore secrets."
        echo ""
    fi

    # Scope picker
    if [ -z "$scope" ]; then
        local _choice
        _choice=$(igor_fzf_pick "Restore Snapshot — Scope" \
            "1:IGOR STATE:Variables and env files (igor-state/)" \
            "2:SYSTEM CONFIG:fstab, crontab, hosts, sshd, ufw, services" \
            "3:DOCKER STATE:Compose files and .env files only" \
            "4:ALL CORE:All of the above with per-step confirm" \
            "b:BACK:Go back without restoring")
        case $? in 1|2)
            echo "    1) Igor state (variables, env files)"
            echo "    2) System config (fstab, crontab, hosts, sshd, ufw)"
            echo "    3) Docker compose + env files"
            echo "    4) All (staged, per-step confirmation)"
            echo "    b) Back"
            echo ""
            read -rp "  Choice: " _choice ;; esac
        case "$_choice" in
            1) scope="igor-state" ;;
            2) scope="system" ;;
            3) scope="docker" ;;
            4) scope="all" ;;
            b|B) return 0 ;;
            *) fail "Invalid choice"; return 1 ;;
        esac
    fi

    local workdir; workdir=$(mktemp -d)
    # A RETURN trap also fires for every helper called below (confirm, hooks,
    # etc.) when functrace is enabled, deleting the restore tree too early.
    # Clean up explicitly after all restore stages instead.
    tar -xzf "$archive" -C "$workdir" 2>/dev/null || {
        fail "Archive extract failed"
        rm -rf -- "$workdir"
        return 1
    }

    # ── Igor state restore ────────────────────────────────────────────────────
    if [[ "$scope" == "igor-state" || "$scope" == "all" ]]; then
        local _proceed=true
        [ "$scope" = "all" ] && { confirm "Restore Igor state (variables, env files)?" || _proceed=false; }

        if "$_proceed"; then
            # config/variables/ restore
            if [ -d "${workdir}/igor-state/variables" ]; then
                echo -e "  ${CYAN}Diff — config/variables/:${NC}"
                for f in "${workdir}/igor-state/variables/"*; do
                    [ -e "$f" ] || continue
                    local fname; fname=$(basename "$f")
                    local live="${IGOR_DIR}/config/variables/${fname}"
                    if "$_or_guard" && { _mod_cb_selected_key_bearing "$f" ||
                        { [ -f "$live" ] && _mod_cb_selected_key_bearing "$live"; }; }; then
                        warn "Selected credential source omitted from variables preview"
                        continue
                    fi
                    if [ -f "$live" ]; then
                        diff --color=always -u "$live" "$f" 2>/dev/null | head -30 || true
                    else
                        echo -e "  ${GRN}+ NEW:${NC} ${fname}"
                    fi
                done
                if confirm "Apply config/variables/ from snapshot?"; then
                    mkdir -p "${IGOR_DIR}/config/variables"
                    if "$_or_guard"; then
                        local _var_restore _var_relative _var_live
                        while IFS= read -r _var_restore; do
                            _var_relative="${_var_restore#${workdir}/igor-state/variables/}"
                            _var_live="${IGOR_DIR}/config/variables/${_var_relative}"
                            if _mod_cb_selected_key_bearing "$_var_restore" ||
                               { [ -f "$_var_live" ] && _mod_cb_selected_key_bearing "$_var_live"; }; then
                                warn "Refusing selected credential source from variables restore"
                                continue
                            fi
                            if ! _mod_cb_variable_destination_safe "$_var_live"; then
                                warn "Refusing linked variables destination during managed credential restore"
                                continue
                            fi
                            mkdir -p -- "$(dirname -- "$_var_live")"
                            cp -- "$_var_restore" "$_var_live" 2>/dev/null || true
                        done < <(find -P "${workdir}/igor-state/variables" -type f -print 2>/dev/null)
                    else
                        cp -r "${workdir}/igor-state/variables/." "${IGOR_DIR}/config/variables/" 2>/dev/null
                    fi
                    ok "config/variables/ restored"
                fi
            fi

            if [ -f "${workdir}/igor-state/modules.conf" ]; then
                if confirm "Restore module activation state (config/modules.conf)?"; then
                    mkdir -p "${IGOR_DIR}/config"
                    if cp -- "${workdir}/igor-state/modules.conf" "${IGOR_DIR}/config/modules.conf"; then
                        ok "config/modules.conf restored (takes effect on next Igor start)"
                    else
                        fail "config/modules.conf restore failed"
                    fi
                fi
            fi

            # secrets restore
            if [ -d "${workdir}/igor-state/secrets-plain" ]; then
                if confirm "Restore secrets env files and API keys?"; then
                    if [ -L "${IGOR_DIR}/secrets" ]; then
                        fail "Refusing to restore secrets through a symlinked directory"
                    elif mkdir -p "${IGOR_DIR}/secrets"; then
                        while IFS= read -r _sf_path; do
                            [ -n "$_sf_path" ] || continue
                            if "$_or_guard" && _mod_cb_selected_key_bearing "$_sf_path"; then
                                warn "Refusing selected credential source from secrets restore"
                                continue
                            fi
                            local _sf_name; _sf_name=$(basename -- "$_sf_path")
                            local _sf_dest="${IGOR_DIR}/secrets/${_sf_name}"
                            if [ -L "$_sf_dest" ]; then
                                warn "Skipping symlinked secret destination: ${_sf_name}"
                                continue
                            fi
                            if cp -- "$_sf_path" "$_sf_dest" && chmod 600 "$_sf_dest" 2>/dev/null; then
                                ok "${_sf_name} restored"
                            else
                                fail "${_sf_name} restore failed"
                            fi
                        done < <(find -P "${workdir}/igor-state/secrets-plain" -maxdepth 1 -type f \
                            \( -name '*.env' -o -name '*.key' \) -print 2>/dev/null | sort)
                    else
                        fail "Could not create secrets directory"
                    fi
                fi
            elif [ -f "${workdir}/igor-state/secrets-plain.tar.gz.gpg" ]; then
                warn "Secrets are encrypted. Decrypt manually:"
                echo "  gpg --output secrets-plain.tar.gz --decrypt \\"
                echo "       ${workdir}/igor-state/secrets-plain.tar.gz.gpg"
            fi
        fi
    fi

    # ── System config restore ─────────────────────────────────────────────────
    if [[ "$scope" == "system" || "$scope" == "all" ]]; then
        local _sp=true
        [ "$scope" = "all" ] && { confirm "Restore system config (fstab, crontab, sshd, etc.)?" || _sp=false; }

        if $_sp; then
            # fstab
            if [ -f "${workdir}/system/fstab.snapshot" ]; then
                echo -e "\n  ${YEL}fstab diff:${NC}"
                diff --color=always -u /etc/fstab "${workdir}/system/fstab.snapshot" 2>/dev/null || true
                echo ""
                confirm "Apply fstab? (CAUTION — wrong fstab can prevent boot)" && {
                    sudo cp "${workdir}/system/fstab.snapshot" /etc/fstab && ok "fstab restored" || \
                        fail "fstab restore failed (sudo required)"
                } || echo "  fstab skipped."
            fi

            # crontab
            if [ -f "${workdir}/system/crontab.snapshot" ]; then
                echo -e "\n  ${CYAN}crontab diff:${NC}"
                diff --color=always <(crontab -l 2>/dev/null) "${workdir}/system/crontab.snapshot" 2>/dev/null || true
                confirm "Apply crontab?" && {
                    crontab "${workdir}/system/crontab.snapshot" && ok "crontab restored" || \
                        fail "crontab restore failed"
                } || echo "  crontab skipped."
            fi

            # sshd_config
            if [ -f "${workdir}/system/sshd_config.snapshot" ]; then
                confirm "Restore sshd_config?" && {
                    sudo cp "${workdir}/system/sshd_config.snapshot" /etc/ssh/sshd_config && \
                        ok "sshd_config restored" || fail "sshd_config restore failed"
                } || true
            fi
        fi
    fi

    # ── Stack files restore (config/stacks/) ─────────────────────────────────
    if [[ "$scope" == "docker" || "$scope" == "all" ]]; then
        local _dp=true
        [ "$scope" = "all" ] && { confirm "Restore config/stacks/ (compose files, nginx.conf, Dockerfile, etc.)?" || _dp=false; }

        if $_dp; then
            if [ -d "${workdir}/stacks" ]; then
                local _stacks_count; _stacks_count=$(find "${workdir}/stacks" -type f 2>/dev/null | wc -l)
                echo -e "  ${CYAN}config/stacks/:${NC} ${_stacks_count} files"
                while IFS= read -r _sf; do
                    local _rel="${_sf#${workdir}/stacks/}"
                    local _live="${IGOR_DIR}/config/stacks/${_rel}"
                    if [ -f "$_live" ]; then
                        diff --color=always -u "$_live" "$_sf" 2>/dev/null | head -15 || true
                    else
                        echo -e "  ${GRN}+ NEW:${NC} config/stacks/${_rel}"
                    fi
                done < <(find "${workdir}/stacks" -type f | sort)
                if confirm "Apply config/stacks/ from snapshot?"; then
                    mkdir -p "${IGOR_DIR}/config/stacks"
                    cp -r "${workdir}/stacks/." "${IGOR_DIR}/config/stacks/"
                    ok "config/stacks/ restored"
                fi
            else
                # Legacy: old backups stored individual compose_*.yml files with encoded paths
                local _legacy_found=false
                for _cf in "${workdir}/docker/"compose_*.yml; do
                    [ -f "$_cf" ] || continue
                    _legacy_found=true
                    local _cf_name; _cf_name=$(basename "$_cf")
                    echo -e "  ${YEL}Legacy compose file:${NC} ${_cf_name}"
                    echo "  (legacy backups used encoded filenames — restore to config/stacks/ manually)"
                    if declare -f igor_has_module >/dev/null 2>&1 &&
                       ! igor_has_module nextcloud_docker; then
                        warn "Skipping legacy Nextcloud compose restore: nextcloud_docker is disabled"
                        continue
                    fi
                    confirm "Copy ${_cf_name} to ${IGOR_DIR}/config/stacks/nextcloud/$(basename "${_cf_name#compose_}")?" && \
                        { mkdir -p "${IGOR_DIR}/config/stacks/nextcloud"; \
                          cp "$_cf" "${IGOR_DIR}/config/stacks/nextcloud/$(basename "${_cf_name#compose_}")" 2>/dev/null; \
                          ok "Copied"; } || true
                done
                $_legacy_found || info "No stack files found in snapshot"
            fi
        fi
    fi

    # ── Patterns restore ──────────────────────────────────────────────────────
    if [[ "$scope" == "all" ]] && [ -d "${workdir}/patterns" ]; then
        if confirm "Restore config/patterns/ (learned repair patterns)?"; then
            mkdir -p "${IGOR_DIR}/config/patterns"
            cp -r "${workdir}/patterns/." "${IGOR_DIR}/config/patterns/"
            local _pat_count; _pat_count=$(find "${workdir}/patterns" -type f | wc -l)
            ok "config/patterns/ restored (${_pat_count} files)"
        fi
    fi

    declare -f journal_record &>/dev/null && \
        journal_record "menu:recovery" "config_restore" "CHANGE" \
            "config_backup_restore $scope" "OK" "archive:$(basename "$archive")" 2>/dev/null || true

    ok "Restore complete."

    # ── Post-restore checklist (fresh clone) ──────────────────────────────────
    echo ""
    echo -e "  ${BOLD}${CYAN}Post-restore checklist:${NC}"
    echo "  Igor state is restored. If this is a fresh clone, you still need:"
    echo ""
    echo "  □ secrets/ — verify all files are present and credentials are correct"
    echo "       ls -la \${IGOR_DIR}/secrets/"
    echo "  □ config/stacks/ — verify compose files were restored"
    echo "       ls -la \${IGOR_DIR}/config/stacks/"
    echo "  □ External drive — mount at the path set in secrets/site.env (HD_MOUNT)"
    echo "  □ Docker — install docker + compose plugin if not present"
    echo "  □ Docker volumes — may need to be recreated before starting the stack"
    echo "       docker volume create <volume_name>"
    echo "  □ Nextcloud data — restore DB and files via the module backup (Menu V → Module)"
    echo "  □ Cloudflare Tunnel — re-authenticate if token is not in secrets/"
    echo ""

    # Post-restore health check
    declare -f health_check_full &>/dev/null && {
        info "Running health checks post-restore..."
        health_check_full "false" 2>/dev/null || true
    }

    rm -rf -- "$workdir"
}

# ── config_backup_secrets ─────────────────────────────────────────────────────
# Exports GPG private key + password env files to root-only /root/igor-secrets/.
config_backup_secrets() {
    local CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'
    local RED='\033[0;31m' GRN='\033[0;32m' YEL='\033[1;33m'

    local _secrets_dir="/root/igor-secrets"
    local _ts; _ts=$(date +%s)
    local _archive_name="igor_secrets_${_ts}.tar.gz"
    local _workdir; _workdir=$(mktemp -d)
    trap 'rm -rf "$_workdir"' RETURN

    local _secrets_components=()
    local _or_guard=false
    _mod_cb_openrouter_guard && _or_guard=true
    if "$_or_guard"; then
        printf '%s\n' 'Managed OpenRouter material and selected legacy credential sources are omitted. Recover through approved local re-import or retained generation.' \
            > "${_workdir}/openrouter-credential-omitted.txt"
        _secrets_components+=("openrouter-credential-omitted.txt")
    fi
    step "Backing up secrets (sudo required)"

    # GPG private key export
    local _gpg_home="${IGOR_DIR}/secrets/gnupg"
    if [ -d "$_gpg_home" ]; then
        local _key_id=""
        # MAILCMD_OPERATOR_KEY_ID is the canonical variable (set in secrets/mailcmd.env)
        [ -f "${IGOR_DIR}/secrets/mailcmd.env" ] && \
            _key_id=$(grep "^MAILCMD_OPERATOR_KEY_ID=" "${IGOR_DIR}/secrets/mailcmd.env" 2>/dev/null | cut -d= -f2-)

        if [ -n "$_key_id" ]; then
            gpg --homedir "$_gpg_home" --batch --yes --armor --export-secret-keys "$_key_id" \
                > "${_workdir}/igor_gpg_private.asc" 2>/dev/null
        else
            gpg --homedir "$_gpg_home" --batch --yes --armor --export-secret-keys \
                > "${_workdir}/igor_gpg_private.asc" 2>/dev/null
        fi

        if [ -s "${_workdir}/igor_gpg_private.asc" ]; then
            _secrets_components+=("igor_gpg_private.asc")
            ok "GPG private key exported"
        else
            warn "No GPG private keys found in keyring"
        fi

        gpg --homedir "$_gpg_home" --batch --yes --export-ownertrust \
            > "${_workdir}/igor_gpg_trustdb.txt" 2>/dev/null && \
            [ -s "${_workdir}/igor_gpg_trustdb.txt" ] && \
            _secrets_components+=("igor_gpg_trustdb.txt") || true
    fi

    # Password env files
    for _ef_src in \
        "${IGOR_DIR}/secrets/site.env" \
        "${IGOR_DIR}/secrets/mailcmd.env" \
        "${IGOR_DIR}/secrets/notifications.env" \
        "${IGOR_DIR}/secrets/db.env"; do
        local _ef_name; _ef_name=$(basename "$_ef_src")
        if "$_or_guard" && [ -f "$_ef_src" ] && _mod_cb_selected_key_bearing "$_ef_src"; then
            warn "Omitted selected credential source from secrets export"
            continue
        fi
        [ -f "$_ef_src" ] && cp "$_ef_src" "${_workdir}/${_ef_name}" 2>/dev/null && \
            _secrets_components+=("$_ef_name") || true
    done

    if [ ${#_secrets_components[@]} -eq 0 ]; then
        warn "No secret components found — secrets backup skipped"
        return 0
    fi

    {
        echo "IGOR Secrets Backup"
        echo "TIMESTAMP: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "WARNING: HIGHLY SENSITIVE — private GPG key and passwords."
        echo "         chmod 600 owned by root. Keep offline."
        echo "COMPONENTS:"
        for _sc in "${_secrets_components[@]}"; do
            printf '  %-35s %8d bytes\n' "$_sc" \
                "$(stat -c%s "${_workdir}/${_sc}" 2>/dev/null || echo 0)"
        done
    } > "${_workdir}/secrets_manifest.txt"
    _secrets_components=("secrets_manifest.txt" "${_secrets_components[@]}")

    local _tmp_archive="${_workdir}/${_archive_name}"
    (cd "$_workdir" && tar -czf "$_tmp_archive" "${_secrets_components[@]}" 2>/dev/null)
    [ $? -ne 0 ] && { fail "Secrets archive creation failed"; return 1; }

    if sudo mkdir -p "$_secrets_dir" 2>/dev/null && \
       sudo cp "$_tmp_archive" "${_secrets_dir}/${_archive_name}" 2>/dev/null && \
       sudo chmod 600 "${_secrets_dir}/${_archive_name}" 2>/dev/null && \
       sudo chown root:root "${_secrets_dir}/${_archive_name}" 2>/dev/null && \
       sudo chmod 700 "$_secrets_dir" 2>/dev/null; then
        ok "Secrets backup saved: ${_secrets_dir}/${_archive_name}"
        echo ""
        echo -e "  ${YEL}${BOLD}Important:${NC}"
        echo "  • Only root can read this file (chmod 600, chown root:root)"
        echo "  • Copy it offline: sudo cp ${_secrets_dir}/${_archive_name} /media/usb/"
        echo "  • Restore GPG key:"
        echo "      sudo tar -xzf ${_secrets_dir}/${_archive_name} igor_gpg_private.asc"
        echo "      gpg --homedir \${IGOR_DIR}/secrets/gnupg --import igor_gpg_private.asc"
    else
        fail "Could not write to ${_secrets_dir} (sudo required)"
    fi

    declare -f journal_record &>/dev/null && \
        journal_record "menu:recovery" "secrets_backup" "CHANGE" \
            "config_backup_secrets" "OK" \
            "archive:${_secrets_dir}/${_archive_name}" 2>/dev/null || true
}

# ── config_backup_auto [REASON] ───────────────────────────────────────────────
# Fire-and-forget hook. Always returns 0. No output. No encryption prompt.
# Called from ai/safety.sh and diagnose/fixes.sh before CHANGE/DESTROY actions.
config_backup_auto() {
    local reason="${1:-auto}"
    BACKUP_DIR="$(_cb_backup_dir)"
    {
        mkdir -p "$BACKUP_DIR"
        config_backup_take "$reason" < /dev/null > /dev/null 2>&1
        _mod_cb_prune_old > /dev/null 2>&1
    } 2>/dev/null || true
    return 0
}

# ── _mod_cb_prune_old ─────────────────────────────────────────────────────────
_mod_cb_prune_old() {
    BACKUP_DIR="$(_cb_backup_dir)"
    local keep="${BACKUP_CONFIG_KEEP:-7}"
    local i=0
    ls -t "${BACKUP_DIR}"/config_*.tar.gz 2>/dev/null | while IFS= read -r f; do
        i=$(( i + 1 ))
        [ "$i" -gt "$keep" ] && rm -f "$f" 2>/dev/null || true
    done
}
