#!/bin/bash
# ==============================================================================
#  IGOR — extras/extra.sh
#  --extra mode: 7-lens TUI for monitoring and controlling the main session.
#
#  Lenses:
#    1  Output       — live tail of runtime/output.log
#    2  Control      — session state + command panel
#    3  Watch        — containers, resources, logs, network (sub-views a-d)
#    4  State        — all runtime variables (filterable)
#    5  Steer        — AI behaviour controls, model/provider/temperature
#    6  Conversation — message history manager (trim, checkpoint, clear)
#    7  Terminal     — live tail of runtime/terminal.log (--capture output)
#
#  Navigation: [1-7] lens select   Tab/→=next   ←=prev   q=quit   ?=help
#  Entry:      bash igor.sh --extra   (run in a SECOND terminal)
#
#  IPC: writes commands to runtime/commands.fifo
#       reads state from runtime/state.env
#       reads conversation from runtime/conversation.json
#       writes steering to runtime/steering.txt
# ==============================================================================

# ── Runtime paths ─────────────────────────────────────────────────────────────
_EXTRA_CFG="${IGOR_DIR}"
_EXTRA_RT="${IGOR_RUNTIME_DIR:-${_EXTRA_CFG}/data/runtime}"
_EXTRA_PID_FILE="${_EXTRA_RT}/pid"
_EXTRA_STATE_FILE="${_EXTRA_RT}/state.env"
_EXTRA_OUTPUT_LOG="${_EXTRA_RT}/output.log"
_EXTRA_CONV_FILE="${_EXTRA_RT}/conversation.json"
_EXTRA_STEERING="${_EXTRA_RT}/steering.txt"
_EXTRA_FIFO="${_EXTRA_RT}/commands.fifo"

# ── TUI state ─────────────────────────────────────────────────────────────────
_EXTRA_LENS=2          # active lens (1-6); start on Control
_EXTRA_WATCH_SUB="a"   # watch sub-view: a=containers b=resources c=logs d=network
_EXTRA_FILTER=""       # state filter text (lens 4)

# ── ANSI colours (standalone safe — lib/ui.sh may not be loaded) ──────────────
_ER=$'\033[0;31m' _EG=$'\033[0;32m' _EY=$'\033[0;33m'
_EC=$'\033[0;36m' _EM=$'\033[0;35m' _EW=$'\033[1;37m'
_ED=$'\033[2m'    _EB=$'\033[1m'    _EN=$'\033[0m'

# ── Terminal save / restore ───────────────────────────────────────────────────
_extra_term_setup()    {
    tput smcup  2>/dev/null || true
    tput civis  2>/dev/null || true
    stty -echo  2>/dev/null || true
}
_extra_term_teardown() {
    tput rmcup  2>/dev/null || true
    tput cnorm  2>/dev/null || true
    stty echo   2>/dev/null || true
}

# ── Session detection ─────────────────────────────────────────────────────────
_extra_session_active() {
    [ -f "$_EXTRA_PID_FILE" ] || return 1
    local pid; read -r pid < "$_EXTRA_PID_FILE" 2>/dev/null || return 1
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}
_extra_session_pid() {
    [ -f "$_EXTRA_PID_FILE" ] || { echo ""; return; }
    local pid; read -r pid < "$_EXTRA_PID_FILE" 2>/dev/null
    echo "${pid:-}"
}

# ── State helpers ─────────────────────────────────────────────────────────────
_extra_state_get() {
    grep "^${1}=" "$_EXTRA_STATE_FILE" 2>/dev/null | cut -d= -f2- | head -1
}

_extra_nextcloud_active() {
    declare -f igor_has_module >/dev/null 2>&1 || return 1
    igor_has_module nextcloud_docker
}

# ── Non-blocking FIFO write (background + kill after 2s) ─────────────────────
_extra_send_cmd() {
    local cmd="$1"
    [ -p "$_EXTRA_FIFO" ] || { _extra_notice "No session FIFO — is main session running?"; return 1; }
    (printf "COMMAND|%d|%s\n" "${#cmd}" "$cmd" > "$_EXTRA_FIFO") &
    local wp=$!; local n=0
    while [ $n -lt 20 ] && kill -0 "$wp" 2>/dev/null; do sleep 0.1; n=$((n+1)); done
    kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null; return 0
}

# ── Terminal geometry ─────────────────────────────────────────────────────────
_extra_cols()         { tput cols  2>/dev/null || echo 80; }
_extra_rows()         { tput lines 2>/dev/null || echo 24; }
_extra_content_rows() { echo $(( $(_extra_rows) - 4 )); }  # 2 header + 2 footer

# ── Horizontal line ───────────────────────────────────────────────────────────
_extra_hline() { printf '%*s' "$(_extra_cols)" '' | tr ' ' "${1:-─}"; }

# ── Header (lens tab bar) ─────────────────────────────────────────────────────
_extra_draw_header() {
    local tabs="" i names=("" "out" "ctrl" "watch" "state" "steer" "conv" "term")
    for i in 1 2 3 4 5 6 7; do
        if [ "$i" -eq "$_EXTRA_LENS" ]; then
            tabs+="${_EW}${_EB}[${i}]${names[$i]}${_EN} "
        else
            tabs+="${_ED}[${i}]${names[$i]}${_EN} "
        fi
    done
    local sess
    _extra_session_active \
        && sess="${_EG}● ACTIVE${_EN}" \
        || sess="${_ER}○ NO SESSION${_EN}"
    printf "${_EB}${_EM}  IGOR --extra${_EN}  %b   %s\n" "$sess" "$tabs"
    printf '%s\n' "$(_extra_hline)"
}

# ── Footer ────────────────────────────────────────────────────────────────────
_extra_draw_footer() {
    printf '%s\n' "$(_extra_hline)"
    printf "${_ED}  [1-7] lens   Tab/→=next   ←=prev   r=refresh   q=quit   ?=help${_EN}\n"
}

# ── Full redraw ───────────────────────────────────────────────────────────────
_extra_redraw() {
    clear
    _extra_draw_header
    case "$_EXTRA_LENS" in
        1) _extra_lens_1 ;;
        2) _extra_lens_2 ;;
        3) _extra_lens_3 ;;
        4) _extra_lens_4 ;;
        5) _extra_lens_5 ;;
        6) _extra_lens_6 ;;
        7) _extra_lens_7 ;;
    esac
    _extra_draw_footer
}

# ── Transient notice (replaces footer line temporarily) ──────────────────────
_extra_notice() {
    tput cup $(( $(_extra_rows) - 1 )) 0 2>/dev/null || true
    printf "${_EG}  ✔ %-60s${_EN}" "$1"
}

# ══════════════════════════════════════════════════════════════════════════════
#  LENS 1 — OUTPUT: live tail of output.log
# ══════════════════════════════════════════════════════════════════════════════
_extra_lens_1() {
    printf "${_EB}  [1] OUTPUT — live session log${_EN}\n"
    printf '%s\n' "$(_extra_hline ─)"
    local avail; avail=$(( $(_extra_content_rows) - 2 ))
    if [ ! -f "$_EXTRA_OUTPUT_LOG" ]; then
        echo ""; echo "  No output log.  Start a session: bash igor.sh"
        return
    fi
    tail -n "$avail" "$_EXTRA_OUTPUT_LOG" 2>/dev/null | \
        while IFS= read -r line; do printf "  %s\n" "$line"; done
    echo ""
    printf "${_ED}  [auto-scrolling]  f=freeze  s=save snapshot${_EN}\n"
}

# ══════════════════════════════════════════════════════════════════════════════
#  LENS 2 — CONTROL: session state + command panel
# ══════════════════════════════════════════════════════════════════════════════
_extra_lens_2() {
    printf "${_EB}  [2] CONTROL — main session state${_EN}\n"
    printf '%s\n' "$(_extra_hline ─)"
    echo ""
    if ! _extra_session_active; then
        echo "  No active main session."
        echo "  Start one:  bash igor.sh"
        echo ""
        echo "  The control panel will appear here once a session is running."
        return
    fi

    local pid; pid=$(_extra_session_pid)
    local model;    model=$(_extra_state_get "NEXUS_MODEL");            model="${model:-(unknown)}"
    local prov;     prov=$(_extra_state_get "NEXUS_PROVIDER");          prov="${prov:-(unknown)}"
    local exec_m;   exec_m=$(_extra_state_get "executive_mode");        exec_m="${exec_m:-false}"
    local max_tok;  max_tok=$(_extra_state_get "NEXUS_MAX_TOKENS");     max_tok="${max_tok:-2048}"
    local verbose;  verbose=$(_extra_state_get "IGOR_VERBOSE");         verbose="${verbose:-true}"
    local temp;     temp=$(_extra_state_get "NEXUS_TEMPERATURE");       temp="${temp:-0.7}"
    local cost;     cost=$(_extra_state_get "AI_SESSION_COST");         cost="${cost:-0.000000}"
    local in_tok;   in_tok=$(_extra_state_get "AI_SESSION_INPUT_TOKENS");  in_tok="${in_tok:-0}"
    local out_tok;  out_tok=$(_extra_state_get "AI_SESSION_OUTPUT_TOKENS"); out_tok="${out_tok:-0}"
    local conv_len; conv_len=$(_extra_state_get "conversation_length"); conv_len="${conv_len:-0}"
    local health;   health=$(_extra_state_get "health_score");          health="${health:-?}"
    local tunnel;   tunnel=$(_extra_state_get "tunnel_status");         tunnel="${tunnel:-?}"
    local nc_run;   nc_run=$(_extra_state_get "nc_running");            nc_run="${nc_run:-?}"

    local exec_d; [ "$exec_m" = "true" ] && exec_d="${_EY}ON${_EN}" || exec_d="${_ED}off${_EN}"
    local prov_d; [ "$prov" = "openrouter" ] && prov_d="${_EC}OpenRouter${_EN}" || prov_d="${_EM}Anthropic${_EN}"

    printf "  ${_EC}Session:${_EN}    ${_EG}● ACTIVE${_EN} (PID %s)\n" "$pid"
    printf "  ${_EC}Provider:${_EN}   %b\t\t\t[P] switch\n" "$prov_d"
    printf "  ${_EC}Model:${_EN}      %-30s [M] change\n" "$model"
    printf "  ${_EC}Exec mode:${_EN}  %b\t\t\t[E] toggle\n" "$exec_d"
    printf "  ${_EC}Max tokens:${_EN} %-30s [T] change\n" "$max_tok"
    printf "  ${_EC}Verbose:${_EN}    %-30s [V] toggle\n" "$verbose"
    printf "  ${_EC}Temp:${_EN}       %-30s [~] adjust\n" "$temp"
    local _sname2=""
    [ -f "${_EXTRA_RT}/steering_name.txt" ] && _sname2=$(cat "${_EXTRA_RT}/steering_name.txt" 2>/dev/null)
    [ -z "$_sname2" ] && [ -f "$_EXTRA_STEERING" ] && [ -s "$_EXTRA_STEERING" ] && _sname2="(custom)"
    printf "  ${_EC}Steering:${_EN}   %-30s [5] steer lens\n" "${_sname2:-(none)}"
    echo ""
    printf "  ${_EC}Cost:${_EN}       \$%s  (%s in, %s out)\n" "$cost" "$in_tok" "$out_tok"
    printf "  ${_EC}Messages:${_EN}   %s in context\n" "$conv_len"
    echo ""
    printf "  ${_EC}Health:${_EN}     %s%%  | Tunnel: %s | NC: %s\n" "$health" "$tunnel" "$nc_run"
    echo ""
    printf "${_ED}  [H] health check   [R] refresh context   [X] end session${_EN}\n"
}

# ══════════════════════════════════════════════════════════════════════════════
#  LENS 3 — WATCH: live system data (sub-views a-d)
# ══════════════════════════════════════════════════════════════════════════════
_extra_lens_3() {
    printf "${_EB}  [3] WATCH — live system data${_EN}  ${_ED}[a]containers [b]resources [c]logs [d]network${_EN}\n"
    printf '%s\n' "$(_extra_hline ─)"
    echo ""
    case "$_EXTRA_WATCH_SUB" in
        a) _extra_watch_containers ;;
        b) _extra_watch_resources  ;;
        c) _extra_watch_logs       ;;
        d) _extra_watch_network    ;;
    esac
}

_extra_watch_containers() {
    printf "  ${_EB}── containers ─────────────────────────────────────────────${_EN}\n"
    command -v docker &>/dev/null || { echo "  docker not in PATH"; return; }
    local ps; ps=$(docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | tail -n +2) || true
    local stats; stats=$(docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null) || true
    if [ -z "$ps" ]; then echo "  No containers (docker compose running?)"; return; fi
    while IFS=$'\t' read -r name status; do
        local cpu="" mem="" sl
        sl=$(printf '%s' "$stats" | grep "^${name}" | head -1) || true
        [ -n "$sl" ] && cpu=$(printf '%s' "$sl" | cut -f2) && mem=$(printf '%s' "$sl" | cut -f3 | cut -d/ -f1 | xargs)
        if printf '%s' "$status" | grep -qi "up"; then
            printf "  ${_EG}●${_EN} %-22s ${_EG}%-15s${_EN}  CPU: %-8s MEM: %s\n" "$name" "$status" "${cpu:-(?)}" "${mem:-(?)}"
        else
            printf "  ${_ER}○${_EN} %-22s ${_ER}%s${_EN}\n" "$name" "$status"
        fi
    done <<< "$ps"
}

_extra_watch_resources() {
    printf "  ${_EB}── resources ──────────────────────────────────────────────${_EN}\n"
    if [ -f /proc/meminfo ]; then
        local mt ma st sf mu su mp sp bar
        mt=$(grep MemTotal   /proc/meminfo | awk '{print $2}')
        ma=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        st=$(grep SwapTotal  /proc/meminfo | awk '{print $2}')
        sf=$(grep SwapFree   /proc/meminfo | awk '{print $2}')
        mu=$((mt - ma)); mp=$((mu * 100 / mt))
        bar=$(printf '%0.s█' $(seq 1 $((mp/10))))$(printf '%0.s░' $(seq 1 $((10 - mp/10))))
        printf "  RAM:    %dMB / %dMB  %s  %d%%\n" "$((mu/1024))" "$((mt/1024))" "$bar" "$mp"
        if [ "$st" -gt 0 ]; then
            su=$((st - sf)); sp=$((su * 100 / st))
            bar=$(printf '%0.s█' $(seq 1 $((sp/10))))$(printf '%0.s░' $(seq 1 $((10 - sp/10))))
            printf "  Swap:   %dMB / %dMB  %s  %d%%\n" "$((su/1024))" "$((st/1024))" "$bar" "$sp"
        fi
    fi
    echo ""
    df -h / 2>/dev/null | tail -1 | awk '{printf "  Disk:   /          %s / %s  %s\n",$3,$2,$5}' || true
    if _extra_nextcloud_active; then
        local nc_m; nc_m=$(_extra_state_get "HD_MOUNT"); nc_m="${nc_m:-/mnt/nextclouddata}"
        df -h "$nc_m" 2>/dev/null | tail -1 | awk -v mp="$nc_m" '{printf "  Disk:   %-12s%s / %s  %s\n",mp,$3,$2,$5}' 2>/dev/null || true
    fi
    echo ""
    [ -f /sys/class/thermal/thermal_zone0/temp ] && \
        printf "  Temp:   %d°C\n" "$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))"
    local load; load=$(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3) || load="?"
    printf "  Load:   %s\n" "$load"
}

_extra_watch_logs() {
    printf "  ${_EB}── logs (runtime output) ──────────────────────────────────${_EN}\n"
    if [ -f "$_EXTRA_OUTPUT_LOG" ]; then
        local avail; avail=$(( $(_extra_content_rows) - 5 ))
        tail -n "$avail" "$_EXTRA_OUTPUT_LOG" 2>/dev/null | \
            while IFS= read -r line; do printf "  %s\n" "$line"; done
    else
        echo "  No output log — start a session."
    fi
}

_extra_watch_network() {
    printf "  ${_EB}── network ────────────────────────────────────────────────${_EN}\n"
    if curl -s --max-time 3 https://1.1.1.1 &>/dev/null; then
        printf "  ${_EG}●${_EN} Internet:         connected\n"
    else
        printf "  ${_ER}○${_EN} Internet:         no connection\n"
    fi
    if host cloudflare.com &>/dev/null 2>&1 || nslookup cloudflare.com &>/dev/null 2>&1; then
        printf "  ${_EG}●${_EN} DNS:              resolving\n"
    else
        printf "  ${_EY}?${_EN} DNS:              check failed\n"
    fi
    if systemctl is-active --quiet cloudflared 2>/dev/null || pgrep -x cloudflared &>/dev/null; then
        printf "  ${_EG}●${_EN} Cloudflare tunnel: running\n"
    else
        printf "  ${_ER}○${_EN} Cloudflare tunnel: not running\n"
    fi
    if _extra_nextcloud_active; then
        local code; code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
            "http://localhost:${IGOR_WEB_PORT:-8080}/status.php" 2>/dev/null || echo "000")
        if [ "$code" = "200" ]; then
            printf "  ${_EG}●${_EN} Nextcloud (%s):  ${_EG}%s OK${_EN}\n" "${IGOR_WEB_PORT:-8080}" "$code"
        else
            printf "  ${_ER}○${_EN} Nextcloud (8080):  ${_ER}%s${_EN}\n" "$code"
        fi
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  LENS 4 — STATE: runtime variable inspector
# ══════════════════════════════════════════════════════════════════════════════
_extra_lens_4() {
    printf "${_EB}  [4] STATE — runtime variables${_EN}\n"
    printf '%s\n' "$(_extra_hline ─)"
    [ -n "$_EXTRA_FILTER" ] && printf "  ${_EY}filter: %s${_EN}\n" "$_EXTRA_FILTER"
    echo ""
    if [ ! -f "$_EXTRA_STATE_FILE" ]; then
        echo "  No state file — written by main session every few seconds."
        return
    fi
    local avail count=0; avail=$(( $(_extra_content_rows) - 4 ))
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        [ -n "$_EXTRA_FILTER" ] && ! echo "$key" | grep -qi "$_EXTRA_FILTER" && continue
        printf "  ${_EC}%-35s${_EN} %s\n" "$key" "$value"
        count=$((count+1))
        if [ $count -ge $avail ]; then
            printf "  ${_ED}... (use / to filter)${_EN}\n"; break
        fi
    done < "$_EXTRA_STATE_FILE"
    echo ""
    printf "${_ED}  /=filter   c=clear filter   e=export   r=refresh${_EN}\n"
}

# ══════════════════════════════════════════════════════════════════════════════
#  LENS 5 — STEER: AI behaviour controls
# ══════════════════════════════════════════════════════════════════════════════
_extra_lens_5() {
    printf "${_EB}  [5] STEER — AI behaviour controls${_EN}\n"
    printf '%s\n' "$(_extra_hline ─)"
    echo ""
    local _sname_file="${_EXTRA_RT}/steering_name.txt"
    local _sname=""
    [ -f "$_sname_file" ] && _sname=$(cat "$_sname_file" 2>/dev/null)
    if [ -f "$_EXTRA_STEERING" ] && [ -s "$_EXTRA_STEERING" ]; then
        [ -n "$_sname" ] && printf "  ${_EY}Active preset: ${_EB}%s${_EN}\n" "$_sname" \
                         || printf "  ${_EY}Active steering (custom):${_EN}\n"
        head -3 "$_EXTRA_STEERING" | while IFS= read -r l; do printf "  ${_ED}  › %s${_EN}\n" "$l"; done
        echo ""
    else
        printf "  ${_ED}Active steering: (none — default behaviour)${_EN}\n\n"
    fi
    printf "  ${_EB}── Quick modes ─────────────────────────────────────────────${_EN}\n"
    local _presets=("FOCUS" "VERBOSE" "CAUTIOUS" "AGGRESSIVE" "TEACHING" "BRIEF")
    local _descs=(
        "Only the reported issue — skip unrelated checks"
        "Explain each command before running it"
        "Ask before every command, even read-only"
        "Fix all found issues, minimal confirmation"
        "Explain what + why at every step"
        "No explanations — commands and results only"
    )
    for i in "${!_presets[@]}"; do
        local n=$((i+1))
        local marker="  "
        [ "$_sname" = "${_presets[$i]}" ] && marker="${_EY}▶${_EN}"
        printf "  %b %d) %-11s %s\n" "$marker" "$n" "${_presets[$i]}" "${_descs[$i]}"
    done
    echo "    7) CUSTOM      Type your own steering instruction"
    echo "    8) CLEAR       Remove all steering, reset to base"
    echo ""
    printf "  ${_EB}── Model controls ──────────────────────────────────────────${_EN}\n"
    local model; model=$(_extra_state_get "NEXUS_MODEL");        model="${model:-(unknown)}"
    local prov;  prov=$(_extra_state_get "NEXUS_PROVIDER");      prov="${prov:-(unknown)}"
    local temp;  temp=$(_extra_state_get "NEXUS_TEMPERATURE");   temp="${temp:-0.7}"
    printf "  M) Switch model     current: %s\n" "$model"
    printf "  P) Switch provider  current: %s\n" "$prov"
    printf "  T) Temperature      current: %s   (0.0=det  1.0=creative  2.0=chaotic)\n" "$temp"
    echo ""
    printf "${_ED}  [1-8] quick mode   M/P/T model controls   Enter to confirm${_EN}\n"
}

# ══════════════════════════════════════════════════════════════════════════════
#  LENS 6 — CONVERSATION: history manager
# ══════════════════════════════════════════════════════════════════════════════
_extra_lens_6() {
    printf "${_EB}  [6] CONVERSATION — message history${_EN}\n"
    printf '%s\n' "$(_extra_hline ─)"
    echo ""
    if [ ! -f "$_EXTRA_CONV_FILE" ]; then
        echo "  No conversation file — written during AI chat session."
        return
    fi
    local avail; avail=$(( $(_extra_content_rows) - 6 ))
    python3 - "$_EXTRA_CONV_FILE" "$avail" 2>/dev/null <<'PYEOF'
import json, sys

path, avail = sys.argv[1], int(sys.argv[2])
try:
    with open(path) as f:
        msgs = json.load(f)
except Exception as e:
    print("  Error: " + str(e)); sys.exit(0)

print("  Messages: " + str(len(msgs)))
print()
lines = 0
for i, msg in enumerate(msgs):
    role = msg.get("role","?").upper()
    content = str(msg.get("content",""))
    short = content[:70].replace("\n"," ")
    if len(content) > 70: short += "..."
    line = "  [{:2d}] {:10s}  {}".format(i+1, role, short)
    print(line)
    lines += 1
    if lines >= avail - 5: print("  ..."); break

print()
total = sum(len(str(m.get("content",""))) for m in msgs)
est = total // 4
pct = min(100, est * 100 // 40000)
bar = "█"*(pct//10) + "░"*(10 - pct//10)
print("  Context: {}  {}%  (est {:,} / 40k tokens)".format(bar, pct, est))
PYEOF
    echo ""
    printf "${_ED}  t=trim   s=summarise   c=checkpoint   x=clear all${_EN}\n"
}

# ══════════════════════════════════════════════════════════════════════════════
#  LENS 7 — TERMINAL: live tail of runtime/terminal.log (--capture mode)
# ══════════════════════════════════════════════════════════════════════════════
_extra_lens_7() {
    local tlog="${_EXTRA_RT}/terminal.log"
    printf "${_EB}  [7] TERMINAL — live terminal capture${_EN}\n"
    printf '%s\n' "$(_extra_hline ─)"
    if [ ! -f "$tlog" ]; then
        echo ""
        echo "  No terminal log.  Start capture:"
        echo "    bash igor.sh --capture"
        echo ""
        echo "  Captures all terminal output while you work."
        echo "  Igor can read it via: <read_log target=\"terminal\" lines=\"20\"/>"
        return
    fi
    local avail; avail=$(( $(_extra_content_rows) - 3 ))
    local sz; sz=$(wc -l < "$tlog" 2>/dev/null || echo 0)
    printf "  ${_ED}Log: %s  (%s lines total)${_EN}\n" "$tlog" "$sz"
    tail -n "$avail" "$tlog" 2>/dev/null | \
        while IFS= read -r line; do printf "  %s\n" "$line"; done
    echo ""
    printf "${_ED}  s=save snapshot   c=clear log   [auto-refresh 3s]${_EN}\n"
}

# ══════════════════════════════════════════════════════════════════════════════
#  KEY HANDLERS (lens-specific actions that need user input)
# ══════════════════════════════════════════════════════════════════════════════

# ── Lens 2 — Control action keys ─────────────────────────────────────────────
_extra_ctrl_action() {
    local key="$1"
    case "$key" in
        P|p)
            _extra_term_teardown
            printf "\n  Switch provider [1=Anthropic 2=OpenRouter]: "
            local c; read -r c
            case "$c" in
                1) _extra_send_cmd "provider:anthropic";   echo "  → Anthropic"   ;;
                2) _extra_send_cmd "provider:openrouter";  echo "  → OpenRouter"  ;;
                *) echo "  Cancelled." ;;
            esac
            sleep 1.5; _extra_term_setup ;;
        M|m)
            _extra_term_teardown
            printf "\n  Model ID (e.g. claude-haiku-4-5-20251001): "
            local nm; read -r nm
            [ -n "$nm" ] && _extra_send_cmd "model:${nm}" && echo "  Command sent."
            sleep 1.5; _extra_term_setup ;;
        E|e)
            local em; em=$(_extra_state_get "executive_mode")
            [ "$em" = "true" ] && _extra_send_cmd "exec_mode:off" || _extra_send_cmd "exec_mode:on" ;;
        T|t)
            _extra_term_teardown
            printf "\n  Max tokens [512/1024/2048/4096]: "
            local tok; read -r tok
            case "$tok" in
                512|1024|2048|4096) _extra_send_cmd "max_tokens:${tok}"; echo "  Command sent." ;;
                *) echo "  Cancelled." ;;
            esac
            sleep 1.5; _extra_term_setup ;;
        V|v)
            local vb; vb=$(_extra_state_get "IGOR_VERBOSE")
            [ "$vb" = "true" ] && _extra_send_cmd "verbose:off" || _extra_send_cmd "verbose:on" ;;
        '~')
            _extra_term_teardown
            printf "\n  Temperature [0.0–2.0, default 0.7]: "
            local tmp; read -r tmp
            if [[ "$tmp" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                _extra_send_cmd "temperature:${tmp}"; echo "  Command sent."
            else
                echo "  Cancelled."
            fi
            sleep 1.5; _extra_term_setup ;;
        H|h) _extra_send_cmd "health_check" ;;
        R|r) _extra_send_cmd "refresh" ;;
        X|x)
            _extra_term_teardown
            printf "\n  End the main session? [y/N]: "
            local yn; read -r yn
            [[ "$yn" =~ ^[yY]$ ]] && _extra_send_cmd "end_session"
            _extra_term_setup ;;
    esac
}

# ── Lens 5 — Steer action keys ───────────────────────────────────────────────
_extra_steer_action() {
    local key="$1" msg="" preset_name=""
    case "$key" in
        1) msg="Focus only on the current problem. Do not run checks unrelated to what the user just reported. Stop when the reported issue is resolved."
           preset_name="FOCUS" ;;
        2) msg="Explain every command in plain English before running it"
           preset_name="VERBOSE" ;;
        3) msg="Ask before every command, even read-only ones"
           preset_name="CAUTIOUS" ;;
        4) msg="Fix everything you find, minimal questions"
           preset_name="AGGRESSIVE" ;;
        5) msg="Explain what you are doing and why — I want to learn"
           preset_name="TEACHING" ;;
        6) msg="Be concise, skip explanations, just fix"
           preset_name="BRIEF" ;;
        7)
            _extra_term_teardown
            printf "\n  Custom steering: "
            read -r msg
            _extra_term_setup ;;
        8)
            rm -f "$_EXTRA_STEERING"
            rm -f "${_EXTRA_RT}/steering_name.txt"
            _extra_send_cmd "steer:clear"
            return ;;
        M|m)
            _extra_term_teardown
            local _cur_prov; _cur_prov=$(_extra_state_get "NEXUS_PROVIDER")
            printf "\n  Switch model  (current provider: %s)\n\n" "${_cur_prov:-unknown}"
            if [ "${_cur_prov}" = "anthropic" ]; then
                echo "  1) claude-haiku-4-5         (fast, cheap)"
                echo "  2) claude-sonnet-4-6        (balanced — default)"
                echo "  3) claude-opus-4-6          (most capable)"
                echo "  m) Manual entry"
                printf "  [1-3/m]: "
                local mc; read -r mc
                case "$mc" in
                    1) _extra_send_cmd "model:claude-haiku-4-5" ;;
                    2) _extra_send_cmd "model:claude-sonnet-4-6" ;;
                    3) _extra_send_cmd "model:claude-opus-4-6" ;;
                    m|M) printf "  Model ID: "; local mm; read -r mm; [ -n "$mm" ] && _extra_send_cmd "model:${mm}" ;;
                esac
            else
                echo "  Anthropic"
                echo "   1) anthropic/claude-haiku-4-5         (\$0.80/M)"
                echo "   2) anthropic/claude-sonnet-4-6        (\$3.00/M)"
                echo "  Google"
                echo "   3) google/gemini-2.5-flash            (\$0.15/M)"
                echo "   4) google/gemini-2.5-pro              (\$1.25/M)"
                echo "  OpenAI"
                echo "   5) openai/gpt-4o-mini                 (\$0.15/M)"
                echo "   6) openai/gpt-4o                      (\$2.50/M)"
                echo "  DeepSeek"
                echo "   7) deepseek/deepseek-chat-v3-0324     (\$0.20/M)"
                echo "   8) deepseek/deepseek-r1               (\$0.55/M)"
                echo "   9) deepseek/deepseek-r1-0528          (\$0.55/M)"
                echo "  Meta"
                echo "  10) meta-llama/llama-3.3-70b-instruct  (free)"
                echo "   m) Manual entry"
                printf "  [1-10/m]: "
                local mc; read -r mc
                case "$mc" in
                    1)  _extra_send_cmd "model:anthropic/claude-haiku-4-5" ;;
                    2)  _extra_send_cmd "model:anthropic/claude-sonnet-4-6" ;;
                    3)  _extra_send_cmd "model:google/gemini-2.5-flash" ;;
                    4)  _extra_send_cmd "model:google/gemini-2.5-pro" ;;
                    5)  _extra_send_cmd "model:openai/gpt-4o-mini" ;;
                    6)  _extra_send_cmd "model:openai/gpt-4o" ;;
                    7)  _extra_send_cmd "model:deepseek/deepseek-chat-v3-0324" ;;
                    8)  _extra_send_cmd "model:deepseek/deepseek-r1" ;;
                    9)  _extra_send_cmd "model:deepseek/deepseek-r1-0528" ;;
                    10) _extra_send_cmd "model:meta-llama/llama-3.3-70b-instruct" ;;
                    m|M) printf "  Model ID: "; local mm; read -r mm; [ -n "$mm" ] && _extra_send_cmd "model:${mm}" ;;
                esac
            fi
            sleep 1; _extra_term_setup; return ;;
        P|p)
            _extra_term_teardown
            printf "\n  Switch provider [1=Anthropic 2=OpenRouter]: "
            local pc; read -r pc
            case "$pc" in
                1) _extra_send_cmd "provider:anthropic"  ;;
                2) _extra_send_cmd "provider:openrouter" ;;
            esac
            sleep 1; _extra_term_setup; return ;;
        T|t)
            _extra_term_teardown
            printf "\n  Temperature [0.0–2.0]: "
            local tmp; read -r tmp
            [[ "$tmp" =~ ^[0-9]+(\.[0-9]+)?$ ]] && _extra_send_cmd "temperature:${tmp}"
            sleep 1; _extra_term_setup; return ;;
        *) return ;;
    esac
    if [ -n "$msg" ]; then
        echo "$msg" >> "$_EXTRA_STEERING"
        [ -n "$preset_name" ] && printf '%s' "$preset_name" > "${_EXTRA_RT}/steering_name.txt" \
                              || rm -f "${_EXTRA_RT}/steering_name.txt"
        _extra_send_cmd "steer:${msg}"
    fi
}

# ── Lens 6 — Conversation action keys ────────────────────────────────────────
_extra_conv_action() {
    local key="$1"
    case "$key" in
        t|T)
            _extra_term_teardown
            printf "\n"
            printf "  ${_EY}⚠  Trimming will lose context of removed exchanges.\n"
            printf "     Checkpoint first is recommended.${_EN}\n"
            printf "  Trim to last N pairs [4]: "
            local n; read -r n; n="${n:-4}"
            [[ "$n" =~ ^[0-9]+$ ]] && _extra_send_cmd "conversation:trim:${n}" && echo "  Command sent."
            sleep 1.5; _extra_term_setup ;;
        s|S)
            _extra_term_teardown
            printf "\n  Summarise conversation to one message? [y/N]: "
            local yn; read -r yn
            [[ "$yn" =~ ^[yY]$ ]] && _extra_send_cmd "conversation:summarise" && echo "  Command sent."
            sleep 1.5; _extra_term_setup ;;
        c|C)
            _extra_send_cmd "checkpoint"
            _extra_notice "Checkpoint requested" ;;
        x|X)
            _extra_term_teardown
            printf "\n  Clear ALL conversation history? [y/N]: "
            local yn; read -r yn
            [[ "$yn" =~ ^[yY]$ ]] && _extra_send_cmd "conversation:clear" && echo "  Cleared."
            sleep 1.5; _extra_term_setup ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
#  HELP SCREEN
# ══════════════════════════════════════════════════════════════════════════════
_extra_show_help() {
    clear
    printf "\n${_EB}${_EM}  IGOR --extra  help${_EN}\n\n"
    printf "  ${_EB}Navigation${_EN}\n"
    echo "  [1-6]  select lens    Tab/→ next   ← prev    q quit    r refresh"
    echo ""
    printf "  ${_EB}Lens 1 — Output${_EN}\n"
    echo "  f=freeze scroll    s=save snapshot to file"
    echo ""
    printf "  ${_EB}Lens 2 — Control${_EN}\n"
    echo "  P=provider  M=model  E=exec-mode  T=max-tokens  V=verbose  ~=temp"
    echo "  H=health-check  R=refresh-context  X=end-session"
    echo ""
    printf "  ${_EB}Lens 3 — Watch${_EN}\n"
    echo "  a=containers  b=resources  c=logs  d=network"
    echo ""
    printf "  ${_EB}Lens 4 — State${_EN}\n"
    echo "  /=filter  c=clear-filter  e=export-to-file"
    echo ""
    printf "  ${_EB}Lens 5 — Steer${_EN}\n"
    echo "  [1-8]=quick-modes  M=model  P=provider  T=temperature"
    echo ""
    printf "  ${_EB}Lens 6 — Conversation${_EN}\n"
    echo "  t=trim  s=summarise  c=checkpoint  x=clear-all"
    echo ""
    printf "  ${_EB}Lens 7 — Terminal${_EN}\n"
    echo "  s=save snapshot   c=clear log"
    echo "  Start capture: bash igor.sh --capture"
    echo ""
    printf "${_ED}  Press any key to return...${_EN}"
    read -rsn1 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN KEY DISPATCHER
# ══════════════════════════════════════════════════════════════════════════════
_extra_handle_key() {
    local key="$1"

    # Global keys (all lenses)
    case "$key" in
        1|2|3|4|5|6|7) _EXTRA_LENS="$key"; return 0 ;;
        $'\t')          _EXTRA_LENS=$(( (_EXTRA_LENS % 7) + 1 )); return 0 ;;
        q|Q)            return 1 ;;  # quit
        r|R)            return 0 ;;  # just redraw
        '?')            _extra_show_help; return 0 ;;
    esac

    # Lens-specific keys
    case "$_EXTRA_LENS" in
        1)
            case "$key" in
                s|S)
                    local snap="${_EXTRA_RT}/output_$(date +%Y%m%d_%H%M%S).snapshot"
                    cp "$_EXTRA_OUTPUT_LOG" "$snap" 2>/dev/null && _extra_notice "Saved: $snap"
                    ;;
            esac ;;
        2)  _extra_ctrl_action "$key" ;;
        3)
            case "$key" in
                a|A) _EXTRA_WATCH_SUB="a" ;;
                b|B) _EXTRA_WATCH_SUB="b" ;;
                c|C) _EXTRA_WATCH_SUB="c" ;;
                d|D) _EXTRA_WATCH_SUB="d" ;;
            esac ;;
        4)
            case "$key" in
                '/')
                    _extra_term_teardown
                    printf "\n  Filter (regex): "
                    read -r _EXTRA_FILTER
                    _extra_term_setup ;;
                c|C) _EXTRA_FILTER="" ;;
                e|E)
                    local exp="${_EXTRA_RT}/state_$(date +%Y%m%d_%H%M%S).export"
                    cp "$_EXTRA_STATE_FILE" "$exp" 2>/dev/null && _extra_notice "Exported: $exp"
                    ;;
            esac ;;
        5)  _extra_steer_action "$key" ;;
        6)  _extra_conv_action  "$key" ;;
        7)
            local tlog="${_EXTRA_RT}/terminal.log"
            case "$key" in
                s|S)
                    local snap="${_EXTRA_RT}/terminal_$(date +%Y%m%d_%H%M%S).snapshot"
                    cp "$tlog" "$snap" 2>/dev/null && _extra_notice "Saved: $snap"
                    ;;
                c|C)
                    _extra_term_teardown
                    printf "\n  Clear terminal.log? [y/N]: "
                    local yn; read -r yn
                    [[ "$yn" =~ ^[yY]$ ]] && > "$tlog" && _extra_notice "terminal.log cleared"
                    _extra_term_setup ;;
            esac ;;
    esac
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN LOOP
# ══════════════════════════════════════════════════════════════════════════════
extra_main() {
    mkdir -p "$_EXTRA_RT" 2>/dev/null || true

    if [ ! -d "$_EXTRA_RT" ]; then
        echo "ERROR: Cannot create runtime dir: $_EXTRA_RT" >&2
        exit 1
    fi

    _extra_term_setup
    trap '_extra_term_teardown; echo ""; echo "  igor --extra closed."; exit 0' INT TERM EXIT

    while true; do
        _extra_redraw

        # Read one key with 3-second auto-refresh timeout
        local key=""
        if ! read -rsn1 -t 3 key 2>/dev/null; then
            continue  # timeout → redraw
        fi

        # Escape sequence (arrow keys)
        if [ "$key" = $'\x1b' ]; then
            local s1="" s2=""
            read -rsn1 -t 0.1 s1 2>/dev/null || true
            read -rsn1 -t 0.1 s2 2>/dev/null || true
            case "${s1}${s2}" in
                "[C") key=$'\t' ;;                          # → = next lens
                "[D")                                        # ← = prev lens
                    _EXTRA_LENS=$(( (_EXTRA_LENS - 2 + 7) % 7 + 1 ))
                    continue ;;
                "[A"|"[B") continue ;;                      # up/down ignored
            esac
        fi

        _extra_handle_key "$key" || break
    done

    _extra_term_teardown
    echo ""
    echo "  igor --extra closed."
}
