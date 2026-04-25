#!/bin/bash
# ==============================================================================
#  IGOR — notify/core.sh
#  Email notification subsystem.
#
#  Sourced by igor.sh at startup — zero side effects on source (functions only).
#  Sourced by modules/notify.sh on first menu access.
#
#  Config:  ${IGOR_DIR}/secrets/notify.env  (chmod 600 — contains SMTP password)
#  Sending: Python 3 smtplib — already a hard dep, zero new package deps.
#
#  Public functions:
#    notify_send  SUBJECT BODY       — send email; returns 0=ok 1=fail; silent if disabled
#    notify_event EVENT_KEY MESSAGE  — check event enabled, build body, call notify_send
#    menu_notify                     — interactive config + event toggle menu
#
#  Integration hook (guard everywhere with declare -f):
#    declare -f notify_event &>/dev/null && \
#        notify_event "event_key" "human message" 2>/dev/null || true
# ==============================================================================

# ── Config path (set at source time — variable assignment only, no I/O) ───────
# Canonical secrets file is secrets/notifications.env (password only).
# Fall back to legacy secrets/notify.env if present.
_NOTIFY_CFG="${IGOR_DIR}/secrets/notifications.env"
[ ! -f "$_NOTIFY_CFG" ] && [ -f "${IGOR_DIR}/secrets/notify.env" ] && \
    _NOTIFY_CFG="${IGOR_DIR}/secrets/notify.env"
_NOTIFY_VARS_CFG="${IGOR_DIR}/config/variables/notifications.env"

# ── _notify_seed_default_events ───────────────────────────────────────────────
# Write default NOTIFY_ON_* flags to notify.env on first use (legacy config fix).
# Critical-tier events default ON; opt-in events default OFF.
_notify_seed_default_events() {
    local -a _on=(
        NOTIFY_ON_HEALTH_CRITICAL NOTIFY_ON_SERVICE_DOWN  NOTIFY_ON_STACK_DOWN
        NOTIFY_ON_FIX_FAILED      NOTIFY_ON_BACKUP_FAIL   NOTIFY_ON_APP_INSTALL
        NOTIFY_ON_DESTROY_ACTION  NOTIFY_ON_JOURNAL_FAIL
        NOTIFY_ON_DISK_WARNING
    )
    local -a _off=( NOTIFY_ON_FIX_APPLIED NOTIFY_ON_BACKUP_DONE NOTIFY_ON_IGOR_START )
    local _v
    for _v in "${_on[@]}";  do _notify_set_cfg "$_v" "true";  done
    for _v in "${_off[@]}"; do _notify_set_cfg "$_v" "false"; done
}

# ── _notify_collect_module_events ─────────────────────────────────────────────
# Call all notify_events hooks and collect EVENT| lines.
# Output format per line: EVENT|key|label|VAR_SUFFIX|default|severity
_notify_collect_module_events() {
    declare -f igor_get_hooks &>/dev/null || return 0
    local _fn _line
    for _fn in $(igor_get_hooks "notify_events" 2>/dev/null); do
        declare -f "$_fn" &>/dev/null || continue
        while IFS= read -r _line; do
            [[ "$_line" =~ ^EVENT\| ]] && printf '%s\n' "$_line"
        done < <("$_fn" 2>/dev/null)
    done
}

# ── _notify_seed_from_module_hooks ────────────────────────────────────────────
# Auto-write default NOTIFY_ON_* flags for module-declared events that are not
# yet in the config file. Called once from _notify_events_menu on first visit.
_notify_seed_from_module_hooks() {
    local _line _key _label _var _default _sev _vn
    while IFS= read -r _line; do
        IFS='|' read -r _ _key _label _var _default _sev <<< "$_line"
        [ -n "$_var" ] || continue
        _vn="NOTIFY_ON_${_var}"
        if ! grep -q "^${_vn}=" "$_NOTIFY_CFG"      2>/dev/null && \
           ! grep -q "^${_vn}=" "$_NOTIFY_VARS_CFG" 2>/dev/null; then
            _notify_set_cfg "$_vn" "${_default:-false}"
        fi
    done < <(_notify_collect_module_events)
}

# ── _notify_load_config ────────────────────────────────────────────────────────
# Loads notification config from both sources:
#   1. config/variables/notifications.env  — non-sensitive settings
#   2. secrets/notifications.env           — SMTP password only
# Auto-seeds default event flags if none exist.
_notify_load_config() {
    # Load non-sensitive settings first (NOTIFY_ENABLED, SMTP_HOST, etc.)
    [ -f "$_NOTIFY_VARS_CFG" ] && { set -a; source "$_NOTIFY_VARS_CFG" 2>/dev/null || true; set +a; }
    # Layer secrets on top (NOTIFY_SMTP_PASS)
    [ -f "$_NOTIFY_CFG" ] && { set -a; source "$_NOTIFY_CFG" 2>/dev/null || true; set +a; }
    # If secrets file exists but has no event toggle flags, write defaults now.
    # This fixes the "Enabled events: (none enabled)" display bug on legacy configs.
    if [ -f "$_NOTIFY_CFG" ] && ! grep -q "^NOTIFY_ON_" "$_NOTIFY_CFG" 2>/dev/null; then
        _notify_seed_default_events
        set -a; source "$_NOTIFY_CFG" 2>/dev/null || true; set +a
    fi
}

# ── _notify_set_cfg KEY VALUE ──────────────────────────────────────────────────
# Persist one setting to notify.env (upsert). Creates file as chmod 600.
_notify_set_cfg() {
    local key="$1" val="$2"
    mkdir -p "$(dirname "$_NOTIFY_CFG")" 2>/dev/null || true
    if [ ! -f "$_NOTIFY_CFG" ]; then
        touch "$_NOTIFY_CFG" && chmod 600 "$_NOTIFY_CFG" 2>/dev/null || true
        echo "# IGOR — notify.env — email notification config" >> "$_NOTIFY_CFG"
        echo "# chmod 600 — contains SMTP password" >> "$_NOTIFY_CFG"
    fi
    if grep -q "^${key}=" "$_NOTIFY_CFG" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$_NOTIFY_CFG"
    else
        echo "${key}=${val}" >> "$_NOTIFY_CFG"
    fi
}

# ── _notify_provider_preset PROVIDER ──────────────────────────────────────────
# Populates NOTIFY_SMTP_HOST, PORT, TLS globals and sets _NOTIFY_PROVIDER_NOTE.
_notify_provider_preset() {
    _NOTIFY_PROVIDER_NOTE=""
    case "$1" in
        gmail)
            NOTIFY_SMTP_HOST="smtp.gmail.com"
            NOTIFY_SMTP_PORT=587
            NOTIFY_SMTP_TLS="starttls"
            _NOTIFY_PROVIDER_NOTE="Gmail requires an App Password — NOT your account password.\nGo to: myaccount.google.com → Security → 2-Step Verification → App Passwords\nUse your Gmail address as SMTP username."
            ;;
        outlook)
            NOTIFY_SMTP_HOST="smtp.office365.com"
            NOTIFY_SMTP_PORT=587
            NOTIFY_SMTP_TLS="starttls"
            _NOTIFY_PROVIDER_NOTE="Use your full Microsoft email and account password.\nFor MFA accounts, create an app password at account.microsoft.com → Security."
            ;;
        yahoo)
            NOTIFY_SMTP_HOST="smtp.mail.yahoo.com"
            NOTIFY_SMTP_PORT=587
            NOTIFY_SMTP_TLS="starttls"
            _NOTIFY_PROVIDER_NOTE="Yahoo requires an App Password.\nGo to: login.yahoo.com → Account Security → Generate app password"
            ;;
        fastmail)
            NOTIFY_SMTP_HOST="smtp.fastmail.com"
            NOTIFY_SMTP_PORT=587
            NOTIFY_SMTP_TLS="starttls"
            _NOTIFY_PROVIDER_NOTE="Use an app-specific password from:\nSettings → Privacy & Security → App Passwords"
            ;;
        icloud)
            NOTIFY_SMTP_HOST="smtp.mail.me.com"
            NOTIFY_SMTP_PORT=587
            NOTIFY_SMTP_TLS="starttls"
            _NOTIFY_PROVIDER_NOTE="iCloud requires an app-specific password.\nGo to: appleid.apple.com → Sign-In and Security → App-Specific Passwords"
            ;;
        proton)
            NOTIFY_SMTP_HOST="127.0.0.1"
            NOTIFY_SMTP_PORT=1025
            NOTIFY_SMTP_TLS="starttls"
            _NOTIFY_PROVIDER_NOTE="ProtonMail Bridge must be installed and running on this machine.\nDownload: proton.me/mail/bridge"
            ;;
        zoho)
            NOTIFY_SMTP_HOST="smtp.zoho.com"
            NOTIFY_SMTP_PORT=587
            NOTIFY_SMTP_TLS="starttls"
            _NOTIFY_PROVIDER_NOTE="Use your Zoho email and account password.\nFor 2FA accounts use an app-specific password from zoho.com → My Account → Security."
            ;;
        sendgrid)
            NOTIFY_SMTP_HOST="smtp.sendgrid.net"
            NOTIFY_SMTP_PORT=587
            NOTIFY_SMTP_TLS="starttls"
            NOTIFY_SMTP_USER="apikey"
            _NOTIFY_PROVIDER_NOTE="Username is literally 'apikey'.\nPassword is your SendGrid API key from app.sendgrid.com → Settings → API Keys."
            ;;
        custom)
            NOTIFY_SMTP_HOST=""
            NOTIFY_SMTP_PORT=587
            NOTIFY_SMTP_TLS="starttls"
            _NOTIFY_PROVIDER_NOTE=""
            ;;
    esac
}

# ── notify_send SUBJECT BODY ───────────────────────────────────────────────────
# Send an email via Python smtplib. All config read from loaded env vars.
# Returns 0=sent, 1=failed, silently returns 0 if NOTIFY_ENABLED != true.
# NEVER fatal — always called with 2>/dev/null || true from hooks.
notify_send() {
    [ "${NOTIFY_ENABLED:-false}" = "true" ] || return 0
    _notify_load_config
    [ -z "${NOTIFY_SMTP_HOST:-}" ] && return 1
    [ -z "${NOTIFY_TO:-}" ]        && return 1

    local subject="$1" body="$2"

    # Pass all values as env vars — avoids shell quoting issues in Python strings
    _NOTIFY_TO="$NOTIFY_TO" \
    _NOTIFY_FROM="${NOTIFY_FROM:-${NOTIFY_SMTP_USER:-igor@localhost}}" \
    _NOTIFY_HOST="$NOTIFY_SMTP_HOST" \
    _NOTIFY_PORT="${NOTIFY_SMTP_PORT:-587}" \
    _NOTIFY_USER="${NOTIFY_SMTP_USER:-}" \
    _NOTIFY_PASS="${NOTIFY_SMTP_PASS:-}" \
    _NOTIFY_TLS="${NOTIFY_SMTP_TLS:-starttls}" \
    _NOTIFY_PREFIX="${NOTIFY_SUBJECT_PREFIX:-[IGOR]}" \
    _NOTIFY_SUBJECT="$subject" \
    _NOTIFY_BODY="$body" \
    python3 - <<'PYEOF'
import smtplib, ssl, sys, os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

to     = os.environ.get('_NOTIFY_TO', '')
from_a = os.environ.get('_NOTIFY_FROM', '')
host   = os.environ.get('_NOTIFY_HOST', '')
port   = int(os.environ.get('_NOTIFY_PORT', '587'))
user   = os.environ.get('_NOTIFY_USER', '')
pw     = os.environ.get('_NOTIFY_PASS', '')
tls    = os.environ.get('_NOTIFY_TLS', 'starttls')
prefix = os.environ.get('_NOTIFY_PREFIX', '[IGOR]')
subj   = f"{prefix} {os.environ.get('_NOTIFY_SUBJECT', '')}"
body   = os.environ.get('_NOTIFY_BODY', '')

if not to or not host:
    print("ERROR: missing recipient or SMTP host", file=sys.stderr)
    sys.exit(1)

msg = MIMEMultipart()
msg['From']    = from_a or to
msg['To']      = to
msg['Subject'] = subj
msg.attach(MIMEText(body, 'plain'))

try:
    if tls == 'ssl':
        ctx = ssl.create_default_context()
        with smtplib.SMTP_SSL(host, port, context=ctx, timeout=15) as s:
            if user: s.login(user, pw)
            s.sendmail(msg['From'], [to], msg.as_string())
    elif tls == 'starttls':
        ctx = ssl.create_default_context()
        with smtplib.SMTP(host, port, timeout=15) as s:
            s.ehlo()
            s.starttls(context=ctx)
            s.ehlo()
            if user: s.login(user, pw)
            s.sendmail(msg['From'], [to], msg.as_string())
    else:
        with smtplib.SMTP(host, port, timeout=15) as s:
            s.ehlo()
            if user: s.login(user, pw)
            s.sendmail(msg['From'], [to], msg.as_string())
    sys.exit(0)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ── notify_event EVENT_KEY MESSAGE [SUBJECT_OVERRIDE] ─────────────────────────
# Primary integration hook. Checks if the event type is enabled, then sends.
#
# EVENT_KEY  — matches NOTIFY_ON_<UPPERCASE_KEY> in notify.env
# MESSAGE    — one-line human description of what happened
# SUBJECT    — optional email subject (auto-generated from event key if empty)
#
# Example:
#   declare -f notify_event &>/dev/null && \
#       notify_event "fix_failed" "nginx_well_known_missing unresolved after 5 attempts" \
#       2>/dev/null || true
notify_event() {
    [ "${NOTIFY_ENABLED:-false}" = "true" ] || return 0
    _notify_load_config

    local event="$1" message="$2" subject_override="${3:-}"

    # Derive config var name: health_critical → NOTIFY_ON_HEALTH_CRITICAL
    local var_name="NOTIFY_ON_${event^^}"
    # Bash indirect expansion
    local enabled="${!var_name:-false}"
    [ "$enabled" = "true" ] || return 0

    # Auto-generate subject from event key (health_critical → "Health Critical")
    local subject
    if [ -n "$subject_override" ]; then
        subject="$subject_override"
    else
        subject=$(echo "$event" | tr '_' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}')
    fi

    local hostname_str; hostname_str=$(hostname 2>/dev/null || echo "igor-host")
    local ts; ts=$(date "+%Y-%m-%d %H:%M:%S")

    local body
    body="$(printf '%s\n\nHost:   %s\nTime:   %s\nEvent:  %s\n\n--\nIGOR — I Guard. Observe. Repair.' \
        "$message" "$hostname_str" "$ts" "$event")"

    notify_send "$subject" "$body" 2>/dev/null || true
}

# ── _notify_events_menu ────────────────────────────────────────────────────────
_notify_events_menu() {
    local GRN='\033[0;32m' RED='\033[0;31m' CYAN='\033[0;36m' YEL='\033[1;33m'
    local DIM='\033[2m' BOLD='\033[1m' NC='\033[0m'
    _notify_load_config

    # Seed module event defaults on first visit (no-op if already set)
    _notify_seed_from_module_hooks

    # ── Core system events — KEY|Display label|Config var suffix ──────────────
    # Severity prefix: ★ critical  ▲ warning  ● info
    local -a SYSTEM_EVENTS=(
        "health_critical|★ Health CRITICAL alert (from healing checks)|HEALTH_CRITICAL"
        "service_down|★ Container / service went down|SERVICE_DOWN"
        "stack_down|★ Entire stack went down|STACK_DOWN"
        "disk_warning|★ Host disk usage critical (≥90%)|DISK_WARNING"
        "fix_failed|▲ Diagnose fix unresolved after all retries|FIX_FAILED"
        "backup_fail|▲ Backup failed|BACKUP_FAIL"
        "destroy_action|▲ AI ran a DESTROY-tier command|DESTROY_ACTION"
        "app_install|● App install completed|APP_INSTALL"
        "fix_applied|● Diagnose fix successful (can be noisy)|FIX_APPLIED"
        "backup_done|● Backup completed (can be noisy)|BACKUP_DONE"
        "journal_fail|● 24h journal FAIL summary on startup|JOURNAL_FAIL"
        "igor_start|● Igor session started (noisy)|IGOR_START"
    )

    # ── Collect module events ──────────────────────────────────────────────────
    # Format from hook: EVENT|key|label|VAR_SUFFIX|default|severity
    local -a MOD_EVENTS=()
    local _mline _mkey _mlabel _mvar _mdef _msev
    while IFS= read -r _mline; do
        IFS='|' read -r _ _mkey _mlabel _mvar _mdef _msev <<< "$_mline"
        [ -n "$_mvar" ] || continue
        local _sev_prefix
        case "$_msev" in
            critical) _sev_prefix="★" ;;
            warning)  _sev_prefix="▲" ;;
            *)        _sev_prefix="●" ;;
        esac
        MOD_EVENTS+=( "${_mkey}|${_sev_prefix} ${_mlabel}|${_mvar}" )
    done < <(_notify_collect_module_events)

    # ── Combined list for numbering ────────────────────────────────────────────
    # We display sections visually but use a flat numbered list for input.
    # ALL_EVENTS holds the combined sequence.
    local -a ALL_EVENTS=()
    local -a ALL_SECTION=()   # parallel: "sys" or "mod" (for section header rendering)
    local _ev
    for _ev in "${SYSTEM_EVENTS[@]}"; do ALL_EVENTS+=("$_ev"); ALL_SECTION+=("sys"); done
    for _ev in "${MOD_EVENTS[@]}";    do ALL_EVENTS+=("$_ev"); ALL_SECTION+=("mod"); done

    local _RELOAD_DEFAULTS=false

    while true; do
        # Reload config so toggles are reflected immediately
        _notify_load_config

        echo ""
        echo -e "  ${BOLD}Event Notification Settings${NC}"
        echo -e "  ${CYAN}─────────────────────────────────────────────────────────────${NC}"
        echo -e "  ${DIM}★ critical  ▲ warning  ● info / optional${NC}"
        echo ""

        local i=1 _prev_section=""
        local _total="${#ALL_EVENTS[@]}"
        for _ev in "${ALL_EVENTS[@]}"; do
            local _idx=$(( i - 1 ))
            local _sec="${ALL_SECTION[$_idx]}"

            # Section header
            if [ "$_sec" != "$_prev_section" ]; then
                if [ "$_sec" = "sys" ]; then
                    echo -e "  ${CYAN}── SYSTEM ──────────────────────────────────────────────${NC}"
                else
                    echo -e "  ${CYAN}── NEXTCLOUD MODULE ────────────────────────────────────${NC}"
                fi
                _prev_section="$_sec"
            fi

            IFS='|' read -r _key _label _var <<< "$_ev"
            local _vn="NOTIFY_ON_${_var}"
            local _val="${!_vn:-false}"
            local _marker
            [ "$_val" = "true" ] \
                && _marker="${GRN}✔${NC}" \
                || _marker="${RED}✗${NC}"
            printf "  %2d. [%b] %s\n" "$i" "$_marker" "$_label"
            (( i++ ))
        done

        echo ""
        echo -e "  ${CYAN}─────────────────────────────────────────────────────────────${NC}"
        echo -e "  Enter number to toggle, ${CYAN}a${NC}=all on, ${CYAN}n${NC}=all off, ${CYAN}b${NC}=back:"
        local choice
        read -rp "  > " choice

        case "$choice" in
            b|B) return ;;
            a|A)
                for _ev in "${ALL_EVENTS[@]}"; do
                    IFS='|' read -r _key _label _var <<< "$_ev"
                    local _vn="NOTIFY_ON_${_var}"
                    _notify_set_cfg "$_vn" "true"
                    printf -v "$_vn" '%s' "true"
                done
                ;;
            n|N)
                for _ev in "${ALL_EVENTS[@]}"; do
                    IFS='|' read -r _key _label _var <<< "$_ev"
                    local _vn="NOTIFY_ON_${_var}"
                    _notify_set_cfg "$_vn" "false"
                    printf -v "$_vn" '%s' "false"
                done
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && \
                   (( choice >= 1 && choice <= _total )); then
                    IFS='|' read -r _key _label _var <<< "${ALL_EVENTS[$(( choice - 1 ))]}"
                    local _vn="NOTIFY_ON_${_var}"
                    local _cur="${!_vn:-false}"
                    local _new; [ "$_cur" = "true" ] && _new="false" || _new="true"
                    _notify_set_cfg "$_vn" "$_new"
                    printf -v "$_vn" '%s' "$_new"
                fi
                ;;
        esac
    done
}

# ── _notify_show_config ────────────────────────────────────────────────────────
_notify_show_config() {
    local GRN='\033[0;32m' RED='\033[0;31m' CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'
    _notify_load_config

    echo ""
    echo -e "  ${BOLD}Notification Configuration${NC}"
    echo -e "  ${CYAN}──────────────────────────────────────────────${NC}"

    local status_str
    if [ "${NOTIFY_ENABLED:-false}" = "true" ]; then
        status_str="${GRN}● ENABLED${NC}"
    else
        status_str="${RED}○ DISABLED${NC}"
    fi

    echo -e "  Status:    ${status_str}"
    echo -e "  Recipient: ${NOTIFY_TO:-(not set)}"
    echo -e "  From:      ${NOTIFY_FROM:-${NOTIFY_SMTP_USER:-(not set)}}"
    echo -e "  SMTP host: ${NOTIFY_SMTP_HOST:-(not set)}:${NOTIFY_SMTP_PORT:-587}  (${NOTIFY_SMTP_TLS:-starttls})"
    echo -e "  SMTP user: ${NOTIFY_SMTP_USER:-(not set)}"
    if [ -n "${NOTIFY_SMTP_PASS:-}" ]; then
        echo -e "  Password:  ${GRN}[set]${NC}"
    else
        echo -e "  Password:  ${RED}(not set)${NC}"
    fi
    echo -e "  Prefix:    ${NOTIFY_SUBJECT_PREFIX:-[IGOR]}"
    echo -e "  Config:    $_NOTIFY_CFG"
    echo ""

    # Event summary — core system events
    echo -e "  ${BOLD}Enabled events:${NC}"
    local -a EVENT_VARS=(
        "NOTIFY_ON_HEALTH_CRITICAL:health_critical"
        "NOTIFY_ON_SERVICE_DOWN:service_down"
        "NOTIFY_ON_STACK_DOWN:stack_down"
        "NOTIFY_ON_DISK_WARNING:disk_warning"
        "NOTIFY_ON_FIX_FAILED:fix_failed"
        "NOTIFY_ON_FIX_APPLIED:fix_applied"
        "NOTIFY_ON_BACKUP_FAIL:backup_fail"
        "NOTIFY_ON_BACKUP_DONE:backup_done"
        "NOTIFY_ON_APP_INSTALL:app_install"
        "NOTIFY_ON_DESTROY_ACTION:destroy_action"
        "NOTIFY_ON_JOURNAL_FAIL:journal_fail"
        "NOTIFY_ON_IGOR_START:igor_start"
    )
    local any_on=false
    for pair in "${EVENT_VARS[@]}"; do
        IFS=':' read -r var key <<< "$pair"
        [ "${!var:-false}" = "true" ] && { echo -e "    ${GRN}✔${NC} $key"; any_on=true; }
    done
    # Module events
    local _mline _mkey _mvar _vn
    while IFS= read -r _mline; do
        IFS='|' read -r _ _mkey _ _mvar _ _ <<< "$_mline"
        [ -n "$_mvar" ] || continue
        _vn="NOTIFY_ON_${_mvar}"
        [ "${!_vn:-false}" = "true" ] && { echo -e "    ${GRN}✔${NC} ${_mkey}"; any_on=true; }
    done < <(_notify_collect_module_events 2>/dev/null)
    $any_on || echo -e "    ${RED}(none enabled)${NC}"
    echo ""
}

# ── _notify_test_send ──────────────────────────────────────────────────────────
_notify_test_send() {
    local GRN='\033[0;32m' RED='\033[0;31m' YEL='\033[1;33m' CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'
    _notify_load_config

    if [ -z "${NOTIFY_SMTP_HOST:-}" ] || [ -z "${NOTIFY_TO:-}" ]; then
        warn "Email not configured. Run option 1 (Configure) first."
        pause
        return 1
    fi

    echo ""
    echo -e "  ${BOLD}Sending test email...${NC}"
    echo -e "  From: ${NOTIFY_SMTP_USER:-?}  →  To: ${NOTIFY_TO}"
    echo -e "  Server: ${NOTIFY_SMTP_HOST}:${NOTIFY_SMTP_PORT:-587}  (${NOTIFY_SMTP_TLS:-starttls})"
    echo ""

    local hostname_str; hostname_str=$(hostname 2>/dev/null || echo "igor-host")
    local body
    body="$(printf 'This is a test notification from IGOR.\n\nHost:   %s\nTime:   %s\nSMTP:   %s:%s (%s)\n\nIf you received this, email notifications are working correctly.\n\n--\nIGOR — I Guard. Observe. Repair.' \
        "$hostname_str" "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$NOTIFY_SMTP_HOST" "${NOTIFY_SMTP_PORT:-587}" "${NOTIFY_SMTP_TLS:-starttls}")"

    local err rc
    # Temporarily force NOTIFY_ENABLED for the test (user may have it disabled while configuring)
    err=$(NOTIFY_ENABLED="true" notify_send "Test Notification" "$body" 2>&1)
    rc=$?

    if [ $rc -eq 0 ]; then
        echo -e "  ${GRN}${BOLD}✔ Email sent successfully!${NC}"
        echo ""
        echo "  Check your inbox at: ${NOTIFY_TO}"
        echo "  (May take a minute — also check your spam folder)"
    else
        echo -e "  ${RED}${BOLD}✗ Failed to send email${NC}"
        echo ""

        # Show the full error in a visible box
        if [ -n "$err" ]; then
            echo -e "  ${RED}┌─ Error details ────────────────────────────────────────────┐${NC}"
            echo "$err" | while IFS= read -r line; do
                printf "  ${RED}│${NC} %s\n" "$line"
            done
            echo -e "  ${RED}└────────────────────────────────────────────────────────────┘${NC}"
            echo ""
        fi

        # Translate common SMTP errors into plain-language hints
        local hint=""
        if echo "$err" | grep -qi "535\|authentication\|auth.*fail\|invalid.*credential\|username.*password"; then
            hint="${YEL}  ► Authentication failed — wrong username or password.${NC}
     If you use Gmail, Yahoo, or iCloud: you need an App Password,
     NOT your regular account password.
     See option 1 → select your provider for setup instructions."
        elif echo "$err" | grep -qi "534\|app.*password\|less.*secure\|application.*password"; then
            hint="${YEL}  ► Your email provider requires an App Password.${NC}
     An App Password is a special one-time code you generate in your
     email account security settings — it's different from your login password.
     Go to option 1 → select your provider for a direct link."
        elif echo "$err" | grep -qi "connection.*refused\|connect.*failed\|timed out\|timeout\|network"; then
            hint="${YEL}  ► Cannot reach the mail server.${NC}
     • Check that the Pi has internet access: ping google.com
     • Verify the SMTP host and port are correct for your provider
     • Some home routers block outbound port 587 — try port 465 with SSL"
        elif echo "$err" | grep -qi "certificate\|ssl\|tls\|handshake"; then
            hint="${YEL}  ► SSL/TLS error.${NC}
     • Try changing the TLS mode in option 1 (switch between starttls/ssl)
     • Port 587 usually needs STARTTLS; port 465 usually needs SSL"
        elif echo "$err" | grep -qi "recipient\|relay\|550\|551\|no.*such.*user"; then
            hint="${YEL}  ► Problem with the recipient address.${NC}
     • Double-check the 'Send alerts TO' email address in option 1
     • Some servers block relaying to external addresses"
        else
            hint="${YEL}  ► General tips:${NC}
     • Gmail/Yahoo: use an App Password, not your account password
     • Gmail: 2-Step Verification must be ON to create App Passwords
     • Outlook: account.microsoft.com → Security → App passwords
     • Check SMTP host:port are correct for your provider"
        fi

        [ -n "$hint" ] && echo -e "$hint"
        echo ""
        echo "  You can re-run the wizard (option 1) to correct settings."
    fi

    echo ""
    pause
}

# ── _notify_wizard ─────────────────────────────────────────────────────────────
_notify_wizard() {
    local YEL='\033[1;33m' CYAN='\033[0;36m' GRN='\033[0;32m' BOLD='\033[1m' NC='\033[0m'
    _notify_load_config

    echo ""
    echo -e "  ${BOLD}Email Notification Setup${NC}"
    echo -e "  ${CYAN}──────────────────────────────────────────────${NC}"
    echo ""
    echo "  Igor will send you an email when something needs your attention"
    echo "  (e.g. a container crashes, a backup fails, or disk runs out of space)."
    echo ""
    echo "  Which email service do you want Igor to send FROM?"
    echo "  (This is the account Igor uses to send alerts — can be the same"
    echo "  one you use personally, or a dedicated account.)"
    echo ""
    echo -e "  ${CYAN}1.${NC} Gmail              — most common, free"
    echo -e "  ${CYAN}2.${NC} Outlook / Microsoft 365"
    echo -e "  ${CYAN}3.${NC} Yahoo Mail"
    echo -e "  ${CYAN}4.${NC} Fastmail"
    echo -e "  ${CYAN}5.${NC} iCloud (Apple)"
    echo -e "  ${CYAN}6.${NC} ProtonMail Bridge   (advanced — requires local Bridge app)"
    echo -e "  ${CYAN}7.${NC} Zoho Mail"
    echo -e "  ${CYAN}8.${NC} SendGrid            (advanced — for developers with API key)"
    echo -e "  ${CYAN}9.${NC} Custom SMTP         (advanced — I know my own server settings)"
    echo ""

    local prov_choice
    read -rp "  Enter a number (1-9, or b to cancel): " prov_choice

    local provider
    case "$prov_choice" in
        1) provider="gmail"     ;;
        2) provider="outlook"   ;;
        3) provider="yahoo"     ;;
        4) provider="fastmail"  ;;
        5) provider="icloud"    ;;
        6) provider="proton"    ;;
        7) provider="zoho"      ;;
        8) provider="sendgrid"  ;;
        9) provider="custom"    ;;
        b|B) return 0           ;;
        *) echo "  Cancelled."; return 1 ;;
    esac

    _notify_provider_preset "$provider"

    # Show provider-specific note
    if [ -n "$_NOTIFY_PROVIDER_NOTE" ]; then
        echo ""
        echo -e "  ${YEL}  ┌─ READ BEFORE CONTINUING ───────────────────────────────┐${NC}"
        echo -e "$_NOTIFY_PROVIDER_NOTE" | while IFS= read -r line; do
            echo -e "  ${YEL}  │${NC} $line"
        done
        echo -e "  ${YEL}  └────────────────────────────────────────────────────────┘${NC}"
        echo ""
        read -rp "  Press Enter when ready to continue... " _dummy
    fi

    # Custom: ask for host/port/TLS
    if [ "$provider" = "custom" ]; then
        echo ""
        echo -e "  ${BOLD}Custom SMTP settings${NC}"
        echo "  (Check your email provider's documentation for these values)"
        echo ""
        local cur_host="${NOTIFY_SMTP_HOST:-}"
        read -rp "  SMTP server address (e.g. smtp.example.com)${cur_host:+ [$cur_host]}: " _host
        NOTIFY_SMTP_HOST="${_host:-$cur_host}"

        local cur_port="${NOTIFY_SMTP_PORT:-587}"
        read -rp "  SMTP port (usually 587 or 465) [$cur_port]: " _port
        NOTIFY_SMTP_PORT="${_port:-$cur_port}"

        local _tls
        _tls=$(igor_fzf_pick "Notifications — SMTP Encryption" \
            "1:STARTTLS:Port 587, most common  (recommended)" \
            "2:SSL/TLS:Port 465" \
            "3:NONE:No encryption — not recommended")
        case $? in 1|2)
            echo ""
            echo "  Encryption type:"
            echo "   1. STARTTLS  — port 587, most common (recommended)"
            echo "   2. SSL/TLS   — port 465"
            echo "   3. None      — no encryption (not recommended)"
            read -rp "  Select [1]: " _tls ;; esac
        case "${_tls:-1}" in
            2) NOTIFY_SMTP_TLS="ssl"      ;;
            3) NOTIFY_SMTP_TLS="none"     ;;
            *) NOTIFY_SMTP_TLS="starttls" ;;
        esac
    fi

    # ── Question 1: WHERE to send alerts ──────────────────────────────────────
    echo ""
    echo -e "  ${BOLD}Step 1 of 3 — Where should Igor send alerts?${NC}"
    echo "  Enter the email address where YOU want to receive notifications."
    echo "  This is YOUR inbox — where you'll see the alerts."
    echo "  (It can be the same as the sending account, or a different one.)"
    echo ""
    local cur_to="${NOTIFY_TO:-}"
    read -rp "  Your email address (alerts go here)${cur_to:+ [$cur_to]}: " _to
    NOTIFY_TO="${_to:-$cur_to}"

    # ── Question 2: WHICH account sends ───────────────────────────────────────
    echo ""
    echo -e "  ${BOLD}Step 2 of 3 — Which account does Igor log in to for sending?${NC}"
    if [ "$provider" = "sendgrid" ]; then
        NOTIFY_SMTP_USER="apikey"
        echo "  SendGrid username is always 'apikey' — no need to enter it."
    else
        echo "  This is the email address Igor uses to LOG IN to ${provider}."
        echo "  Usually the same as your email address for this account."
        echo ""
        local cur_user="${NOTIFY_SMTP_USER:-}"
        read -rp "  ${provider^} account / login email${cur_user:+ [$cur_user]}: " _user
        NOTIFY_SMTP_USER="${_user:-$cur_user}"
    fi
    NOTIFY_FROM="$NOTIFY_SMTP_USER"

    # ── Question 3: Password ───────────────────────────────────────────────────
    echo ""
    echo -e "  ${BOLD}Step 3 of 3 — Password${NC}"

    # Explain what kind of password is needed
    case "$provider" in
        gmail)
            echo "  Gmail requires an App Password — a special 16-character code"
            echo "  that you generate in your Google account. Do NOT use your"
            echo "  regular Gmail login password here — it will not work."
            echo ""
            echo "  How to get an App Password:"
            echo "  1. Go to myaccount.google.com"
            echo "  2. Security → 2-Step Verification (must be enabled first)"
            echo "  3. Scroll down → App Passwords"
            echo "  4. Create one named 'Igor' and paste the code below"
            ;;
        yahoo)
            echo "  Yahoo requires an App Password — a special code separate"
            echo "  from your regular Yahoo login password."
            echo ""
            echo "  How to get one:"
            echo "  1. Go to login.yahoo.com → Account Security"
            echo "  2. Generate app password → name it 'Igor'"
            ;;
        icloud)
            echo "  iCloud requires an App-Specific Password — not your Apple ID password."
            echo ""
            echo "  How to get one:"
            echo "  1. Go to appleid.apple.com → Sign-In and Security"
            echo "  2. App-Specific Passwords → Generate"
            echo "  3. Name it 'Igor' and paste the code below"
            ;;
        outlook)
            echo "  For most Outlook accounts: use your regular account password."
            echo "  If you have multi-factor authentication enabled:"
            echo "  → account.microsoft.com → Security → App passwords"
            ;;
        fastmail)
            echo "  Fastmail requires an app-specific password."
            echo "  Go to: Settings → Privacy & Security → App Passwords → New"
            ;;
        sendgrid)
            echo "  Paste your SendGrid API key here (starts with SG.)"
            echo "  Get one at: app.sendgrid.com → Settings → API Keys"
            ;;
        *)
            echo "  Enter the password for the sending account."
            ;;
    esac

    echo ""
    echo -e "  ${YEL}Note: The password is saved to notify.env on this Pi (readable only by you).${NC}"
    echo ""
    local _pass
    if [ -n "${NOTIFY_SMTP_PASS:-}" ]; then
        read -rsp "  Password (press Enter to keep the existing one): " _pass
    else
        read -rsp "  Password: " _pass
    fi
    echo ""
    [ -n "$_pass" ] && NOTIFY_SMTP_PASS="$_pass"

    # ── Subject prefix (optional, keep quiet) ─────────────────────────────────
    local cur_prefix="${NOTIFY_SUBJECT_PREFIX:-[IGOR]}"
    # Don't ask for this unless they already have a custom one — it's a noise question
    if [ "$cur_prefix" != "[IGOR]" ]; then
        read -rp "  Email subject prefix [$cur_prefix]: " _prefix
        NOTIFY_SUBJECT_PREFIX="${_prefix:-$cur_prefix}"
    else
        NOTIFY_SUBJECT_PREFIX="[IGOR]"
    fi

    # Save everything
    _notify_set_cfg "NOTIFY_SMTP_HOST"      "$NOTIFY_SMTP_HOST"
    _notify_set_cfg "NOTIFY_SMTP_PORT"      "${NOTIFY_SMTP_PORT:-587}"
    _notify_set_cfg "NOTIFY_SMTP_TLS"       "${NOTIFY_SMTP_TLS:-starttls}"
    _notify_set_cfg "NOTIFY_TO"             "$NOTIFY_TO"
    _notify_set_cfg "NOTIFY_SMTP_USER"      "$NOTIFY_SMTP_USER"
    _notify_set_cfg "NOTIFY_FROM"           "$NOTIFY_FROM"
    _notify_set_cfg "NOTIFY_SMTP_PASS"      "$NOTIFY_SMTP_PASS"
    _notify_set_cfg "NOTIFY_SUBJECT_PREFIX" "$NOTIFY_SUBJECT_PREFIX"

    echo ""
    echo -e "  ${GRN}✔${NC} Settings saved."
    echo ""

    # Enable + test
    if confirm "Send a test email now to verify everything works?"; then
        _notify_set_cfg "NOTIFY_ENABLED" "true"
        NOTIFY_ENABLED="true"
        _notify_test_send
    else
        echo ""
        echo "  Settings saved. You can test any time with option 3 in this menu."
        echo "  Enable notifications with option 5 when you're ready."
        pause
    fi
}

# ── menu_notify ────────────────────────────────────────────────────────────────
menu_notify() {
    local GRN='\033[0;32m' RED='\033[0;31m' CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'

    while true; do
        _notify_load_config
        header

        echo -e "  ${CYAN}Notifications${NC}"
        echo ""

        # Status badge
        local status_str smtp_summary=""
        if [ "${NOTIFY_ENABLED:-false}" = "true" ]; then
            status_str="${GRN}● ENABLED${NC}"
            smtp_summary="  → ${NOTIFY_TO:-?}  via  ${NOTIFY_SMTP_HOST:-?}:${NOTIFY_SMTP_PORT:-587}"
        else
            status_str="${RED}○ DISABLED${NC}"
        fi
        echo -e "  Status:  ${status_str}${smtp_summary}"
        echo ""
        local _toggle_notify
        if [ "${NOTIFY_ENABLED:-false}" = "true" ]; then
            _toggle_notify="DISABLE NOTIFICATIONS"
        else
            _toggle_notify="ENABLE NOTIFICATIONS"
        fi
        local choice
        choice=$(igor_fzf_pick "Notifications" \
            "1:CONFIGURE EMAIL:Wizard — provider, credentials, SMTP" \
            "2:EVENT SETTINGS:Choose what triggers alerts" \
            "3:SEND TEST EMAIL:Verify your setup with a test message" \
            "4:SHOW CONFIG:Display current notification settings" \
            "5:${_toggle_notify}:Toggle NOTIFY_ENABLED" \
            "b:BACK:Return to main menu")
        case $? in 1) return ;; 2)
        header
        echo -e "  ${CYAN}Notifications${NC}"
        echo ""
        echo -e "  ${CYAN}1.${NC} Configure email      (wizard — provider, credentials)"
        echo -e "  ${CYAN}2.${NC} Event settings       (choose what triggers alerts)"
        echo -e "  ${CYAN}3.${NC} Send test email"
        echo -e "  ${CYAN}4.${NC} Show current config"
        if [ "${NOTIFY_ENABLED:-false}" = "true" ]; then
            echo -e "  ${CYAN}5.${NC} Disable notifications"
        else
            echo -e "  ${CYAN}5.${NC} Enable notifications"
        fi
        echo ""
        echo -e "  ${CYAN}b.${NC} Back to main menu"
        echo ""
        read -rp "  Select option: " choice ;; esac
        [ "$choice" = "_" ] && continue

        case "$choice" in
            1) _notify_wizard ;;
            2) _notify_events_menu ;;
            3) _notify_test_send ;;
            4) _notify_show_config; pause ;;
            5)
                if [ "${NOTIFY_ENABLED:-false}" = "true" ]; then
                    _notify_set_cfg "NOTIFY_ENABLED" "false"
                    NOTIFY_ENABLED="false"
                    ok "Notifications disabled."
                    pause
                else
                    if [ -z "${NOTIFY_SMTP_HOST:-}" ] || [ -z "${NOTIFY_TO:-}" ]; then
                        warn "Email not configured yet — run option 1 first."
                        pause
                    else
                        _notify_set_cfg "NOTIFY_ENABLED" "true"
                        NOTIFY_ENABLED="true"
                        ok "Notifications enabled."
                        pause
                    fi
                fi
                ;;
            b|B) return ;;
            *) warn "Invalid option."; pause ;;
        esac
    done
}
