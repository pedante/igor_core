#!/bin/bash
# ==============================================================================
#  IGOR — ai/safety.sh
#  Command safety layer — auditable in isolation.
#
#  Provides:
#    ai_is_denied()         hard denylist check (never runs regardless of tier)
#    ai_cmd_is_read()       tier 1: read-only, auto-runs
#    ai_cmd_is_destroy()    tier 3: destructive, always requires YES
#    ai_execute_tool()      dispatch semantic tool dicts from the AI
#    _safe_file_edit()      literal-replace file editing with backup
#
#  Three tiers:
#    READ    — auto-runs without confirmation
#    CHANGE  — requires confirm (or executive mode auto-runs it)
#    DESTROY — always requires typing YES
#
#  Verbose mode:
#    When IGOR_VERBOSE=true, shows the <explain> reasoning block (if present)
#    before executing each tool. Toggle with 'verbose on/off' in chat.
# ==============================================================================

# Load input validation library
if [ -f "${IGOR_DIR}/core/lib/input_validation.sh" ]; then
    source "${IGOR_DIR}/core/lib/input_validation.sh"
else
    echo "WARNING: input_validation.sh not found - some security features disabled" >&2
fi

# P3-2: Session-level command counters (reset at session start via _ai_reset_cmd_counters)
AI_CMD_READ=0
AI_CMD_CHANGE=0
AI_CMD_BLOCKED=0

# The mode is owned by the session/settings layer, but this is the single
# policy-facing accessor used by the safety boundary.  Keep the old
# executive_mode variable as a read-only compatibility input while sessions
# migrate to ai_mode.
ai_get_mode() {
    case "${ai_mode:-}" in
        guide|assist|executive) printf '%s\n' "$ai_mode" ;;
        *)
            # Legacy executive_mode is consulted only when the new setting is
            # genuinely absent. A malformed explicit value fails closed to
            # Assist instead of silently enabling Executive.
            if [ "${ai_mode+x}" = x ]; then
                printf '%s\n' assist
            elif [ "${executive_mode:-false}" = true ]; then
                printf '%s\n' executive
            else
                printf '%s\n' assist
            fi
            ;;
    esac
}

ai_mode_is() {
    [ "$(ai_get_mode)" = "$1" ]
}

_ai_reset_cmd_counters() {
    AI_CMD_READ=0
    AI_CMD_CHANGE=0
    AI_CMD_BLOCKED=0
}

# ── Hard denylist ─────────────────────────────────────────────────────────────
# Commands that can NEVER run regardless of tier or executive mode.
# nexusai.sh entries are intentional: that script is the v1 predecessor and may
# still exist on the host. Blocking it prevents the AI from accidentally running
# the old monolith and creating a recursive or conflicting management session.
# Other v1 function names (install_stack, nuke_and_reinstall, etc.) are NOT in
# this list because they don't exist as executables — they can't be shell-invoked.
ai_is_denied() {
    local cmd="$1"

    local denied_fixed=(
        "> /etc/fstab"      "> /etc/passwd"     "> /etc/shadow"
        "> /etc/hosts"      "> /etc/ssh"
        "mkfs"              "dd if="
        "curl | sh"         "curl | bash"       "curl|sh"   "curl|bash"
        "wget | sh"         "wget | bash"       "wget|sh"   "wget|bash"
        ":(){ :|:& };:"
        "dd if=/dev/zero of=/dev/mm"
        "dd if=/dev/zero of=/dev/sd"
        "bash ~/igor.sh"    "./igor.sh"         "bash ./igor.sh"
        "bash ~/nexusai.sh" "./nexusai.sh"      "bash ./nexusai.sh"   # nexusai.sh is the monolith predecessor — intentionally kept to block accidental execution if it still exists on host
        "cp ~/templates/nginx"  "cat ~/templates/nginx"
        "DELETE FROM oc_appconfig"
        "DELETE FROM oc_apps"
        "DROP TABLE oc_"
        "TRUNCATE oc_"
    )

    local denied_regex=(
        # Root and critical system directories
        "rm[[:space:]]+-[rf]+[[:space:]]+/$"
        "rm[[:space:]]+-[rf]+[[:space:]]+/\*"
        "rm[[:space:]]+-[rf]+[[:space:]]+/(etc|mnt|usr|bin|sbin|var/lib|home|root|dev|sys|proc|boot)($|/)"
        "rm[[:space:]]+-[rf]+[[:space:]]+~(/.*)?$"

        # Protect chmod/chown on root
        "chmod[[:space:]]+(-R[[:space:]]+)?777[[:space:]]+/$"
        "chown[[:space:]]+-R[[:space:]]+root[[:space:]]+/$"

        # Protect project modules and knowledge
        "rm[[:space:]]+-[rf]*[[:space:]]+.*igor/?$"
        "rm[[:space:]]+-[rf]*[[:space:]]+.*knowledge/?$"

        # Dangerous piping and execution
        "curl.+[|].+(sh|bash)"
        "wget.+[|].+(sh|bash)"
        "mkfs\."
        "nc[[:space:]]+-[el]"
        "base64[[:space:]]+-d.+[|]"
        "python[0-9]?[[:space:]]+-c.+exec"

        # Protect active script files — nexusai.sh kept intentionally (predecessor script may still exist on host)
        "rm.*(igor\.sh|nexusai\.sh|ai_knowledge\.sh|ai_scrub\.sh|docker-compose\.yml)[^.]"
        "rm.*web/nginx.*\.conf"
    )

    for pattern in "${denied_fixed[@]}"; do
        echo "$cmd" | grep -qF "$pattern" && return 0
    done
    for pattern in "${denied_regex[@]}"; do
        echo "$cmd" | grep -qE "$pattern" && return 0
    done
    return 1
}

# Keep the parser path independent of the caller's working/configuration directory.
_AI_INPUT_PARSER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tool_input.py"
_AI_FILE_READER="${_AI_INPUT_PARSER%/*}/file_reader.py"
# Central AI policy/audit hooks are optional during early bootstrap and tests,
# but are loaded whenever the safety layer is used in a normal installation.
_AI_SAFETY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${_AI_SAFETY_DIR}/control.sh" ]; then
    # shellcheck disable=SC1091
    source "${_AI_SAFETY_DIR}/control.sh"
elif [ -f "${IGOR_DIR}/core/ai/control.sh" ]; then
    # shellcheck disable=SC1091
    source "${IGOR_DIR}/core/ai/control.sh"
fi

_ai_audit_dispatch() {
    declare -f ai_audit_tool >/dev/null 2>&1 || return 0
    ai_audit_tool "$@" || warn "AI audit write failed" 2>/dev/null || true
}

# Frontends consume structured activity through the canonical event model.
# Keep this boundary optional during bootstrap and isolated safety tests; event
# creation must never affect authorization, execution, or the tool transcript.
_ai_emit_event() {
    local event_type="$1" payload="${2:-}"
    [ -n "$payload" ] || payload='{}'
    [ -n "${IGOR_AI_EVENT_STREAM:-}" ] || return 0
    if declare -f _ai_event_emit >/dev/null 2>&1; then
        _ai_event_emit "$event_type" "$payload" >/dev/null 2>&1 || true
    fi
}

_ai_event_payload() {
    [ -n "${IGOR_AI_EVENT_STREAM:-}" ] || return 0
    local operation_id="$1" tool="$2" tier="$3" approval="$4" status="$5"
    local text_value="${6:-}" output_value="${7:-}" exit_value="${8:-}"
    local admin_required="${9:-false}" duration_value="${10:-}"
    # Frontend events stay on the owner-only local stream. Scrub only when
    # crossing provider/export boundaries; local scrubbing is both expensive
    # for large output and can damage valid host identifiers.
    AI_EVENT_OPERATION="$operation_id" AI_EVENT_NATIVE_ID="${AI_EVENT_NATIVE_ID:-}" \
        AI_EVENT_TOOL="$tool" \
        AI_EVENT_TIER="$tier" AI_EVENT_APPROVAL="$approval" \
        AI_EVENT_STATUS="$status" AI_EVENT_TEXT="$text_value" \
        AI_EVENT_OUTPUT="$output_value" AI_EVENT_EXIT="$exit_value" \
        AI_EVENT_DURATION="$duration_value" \
        AI_EVENT_MODE="$(ai_get_mode 2>/dev/null || printf '%s' assist)" \
        AI_EVENT_ADMIN_REQUIRED="$admin_required" \
        python3 - <<'PY'
import json, os

payload = {
    "operation_id": os.environ.get("AI_EVENT_OPERATION", ""),
    "tool_call_id": os.environ.get("AI_EVENT_NATIVE_ID", ""),
    "session_id": os.environ.get("IGOR_AI_EVENT_SESSION_ID", ""),
    "tool": os.environ.get("AI_EVENT_TOOL", ""),
    "classification": os.environ.get("AI_EVENT_TIER", ""),
    "approval_state": os.environ.get("AI_EVENT_APPROVAL", ""),
    "status": os.environ.get("AI_EVENT_STATUS", ""),
    "mode": os.environ.get("AI_EVENT_MODE", ""),
    "requires_admin_auth": os.environ.get("AI_EVENT_ADMIN_REQUIRED", "false") == "true",
}
text = os.environ.get("AI_EVENT_TEXT", "")
output = os.environ.get("AI_EVENT_OUTPUT", "")
if text:
    payload["display"] = text
    payload["display_text"] = text
if output:
    payload["output"] = output
exit_code = os.environ.get("AI_EVENT_EXIT", "")
if exit_code.isdigit():
    payload["exit_code"] = int(exit_code)
duration = os.environ.get("AI_EVENT_DURATION", "")
if duration.isdigit():
    payload["duration_ms"] = int(duration)
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
PY
}

# Return success when a command explicitly delegates execution to sudo.  This
# is presentation metadata and an execution input selector only; it never
# grants authorization.  The approved command remains the exact command that
# is executed below, and sudo itself decides whether administrator credentials
# are needed.
_ai_command_requires_admin() {
    local command="${1:-}"
    printf '%s\n' "$command" | grep -qE '(^|[;|&()])[[:space:]]*sudo([[:space:]]|$)'
}

_ai_reject_unrestored_tokens() {
    if [[ "$1" == *'[IGOR:'*']'* ]]; then
        echo "[BLOCKED: unresolved privacy token in executable input]"
        return 1
    fi
    return 0
}

_ai_audit_rejected() {
    local tool="$1" tier="$2" reason="$3" args="$4" id="$5"
    _ai_write_tool_meta "$tier" denied action_denied "" "$reason"
    _ai_audit_dispatch BLOCKED "$tool" "$tier" none "$reason" 1 "" "$args" "" "$id"
}

# Write the canonical dispatcher transition for the transaction recorder.
_ai_write_tool_meta() {
    local classification="$1" approval="$2" execution_status="$3"
    local exit_code="${4:-}" reason="${5:-}"
    local runtime="${IGOR_RUNTIME_DIR:-${IGOR_DIR}/data/runtime}"
    local meta="${IGOR_AI_TOOL_META_FILE:-}"
    [[ "$classification" =~ ^(READ|CHANGE|DESTROY)$ ]] || return 0
    [[ "$approval" =~ ^(pending|not_required|auto_approved|approved|denied)$ ]] || approval=denied
    [[ "$execution_status" =~ ^(pending|tool_succeeded|tool_failed|action_denied)$ ]] || execution_status=action_denied
    [[ -n "$meta" && "$meta" == "$runtime/.ai-tool-meta."* && -f "$meta" && ! -L "$meta" && -O "$meta" ]] || return 0
    IGOR_META_TIER="$classification" IGOR_META_APPROVAL="$approval" \
        IGOR_META_STATUS="$execution_status" IGOR_META_EXIT="$exit_code" IGOR_META_REASON="$reason" \
        python3 -c 'import json,os; d={"classification":os.environ["IGOR_META_TIER"],"approval_status":os.environ["IGOR_META_APPROVAL"],"execution_status":os.environ["IGOR_META_STATUS"]}; e=os.environ["IGOR_META_EXIT"]; d["exit_code"]=int(e) if e.isdigit() else None; d["error_type"]=os.environ["IGOR_META_REASON"]; print(json.dumps(d))' \
        > "$meta" 2>/dev/null || true
}

# Build the UI-independent approval record.  The record is deliberately kept
# separate from the command string so future frontends can render the same
# pending request without reparsing provider output.
_ai_build_pending_approval() {
    local tool_json="$1" tier="$2" display="$3" reason="$4" operation_id="$5" normalized_cmd="${6:-}"
    local native_id
    native_id=$(printf '%s' "$tool_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("__native_id", ""))' 2>/dev/null) || return 1
    AI_PENDING_APPROVAL_JSON=$(AI_PENDING_TOOL_JSON="$tool_json" AI_PENDING_TIER="$tier" \
        AI_PENDING_DISPLAY="$display" AI_PENDING_REASON="$reason" \
        AI_PENDING_OPERATION="$operation_id" AI_PENDING_NATIVE_ID="$native_id" \
        AI_PENDING_NORMALIZED_CMD="$normalized_cmd" \
        python3 - <<'PY'
import json, os, sys
try:
    request = json.loads(os.environ["AI_PENDING_TOOL_JSON"])
except (KeyError, json.JSONDecodeError):
    raise SystemExit(1)
args = {k: v for k, v in request.items() if k not in {"tool", "__native_id"}}
if os.environ.get("AI_PENDING_NORMALIZED_CMD") and "cmd" in request:
    request["cmd"] = os.environ["AI_PENDING_NORMALIZED_CMD"]
    args["cmd"] = request["cmd"]
command = str(request.get("cmd", request.get("command", "")))
elevated = command.lstrip().startswith("sudo ") or request.get("sudo") is True
record = {
    "native_tool_id": os.environ.get("AI_PENDING_NATIVE_ID", ""),
    "tool": request.get("tool", ""),
    "normalized_args": args,
    "tier": os.environ.get("AI_PENDING_TIER", ""),
    "display": os.environ.get("AI_PENDING_DISPLAY", ""),
    "approval_reason": os.environ.get("AI_PENDING_REASON", ""),
    "authorization_state": "pending",
    "elevation_known": elevated,
    "operation_id": os.environ.get("AI_PENDING_OPERATION", ""),
}
print(json.dumps(record, ensure_ascii=False, sort_keys=True))
PY
    ) || return 1
    [ -n "$AI_PENDING_APPROVAL_JSON" ]
}

# Ask the configured Igor model to explain the pending action. The backend
# facts remain authoritative; this function returns informational prose only.
_ai_explain_pending_approval() {
    local pending_json="${1:-${AI_PENDING_APPROVAL_JSON:-}}"
    [ -n "$pending_json" ] || return 1
    local renderer="${_AI_SAFETY_DIR}/approval_explain.py"
    [ -f "$renderer" ] || return 1
    if [ "${AI_EXPLANATION_CACHE_PENDING:-}" = "$pending_json" ] &&
       [ -n "${AI_EXPLANATION_CACHE_TEXT:-}" ]; then
        if [ "${_AI_EXPLANATION_DISPLAY_ONLY:-false}" = true ]; then
            printf '%s\n' "$AI_EXPLANATION_CACHE_TEXT" >&2
        else
            printf '%s\n' "$AI_EXPLANATION_CACHE_TEXT"
        fi
        return 0
    fi
    local explanation
    explanation=$(
        set -o pipefail
        local request_json system_prompt user_data scrubbed_system scrubbed_user
        request_json=$(printf '%s' "$pending_json" | python3 "$renderer") || exit 1
        system_prompt=$(printf '%s' "$request_json" | python3 -c \
            'import json,sys; print(json.load(sys.stdin)["system"], end="")') || exit 1
        user_data=$(printf '%s' "$request_json" | python3 -c \
            'import json,sys; print(json.load(sys.stdin)["user"], end="")') || exit 1
        declare -f ai_scrub_outbound >/dev/null 2>&1 || exit 1
        scrubbed_system=$(ai_scrub_outbound "$system_prompt") || exit 1
        scrubbed_user=$(ai_scrub_outbound "$user_data") || exit 1
        [ -n "$scrubbed_system" ] && [ -n "$scrubbed_user" ] || exit 1
        declare -f _nexus_api_call >/dev/null 2>&1 || exit 1
        declare -f _nexus_parse_result >/dev/null 2>&1 || exit 1
        local conversation
        conversation=$(printf '%s' "$scrubbed_user" | python3 -c \
            'import json,sys; print(json.dumps([{"role":"user","content":sys.stdin.read()}], ensure_ascii=False), end="")') || exit 1
        local provider="${NEXUS_PROVIDER:-${IGOR_AI_PROVIDER:-anthropic}}"
        local model="${NEXUS_MODEL:-${IGOR_AI_MODEL:-}}"
        local api_key="${NEXUS_API_KEY:-${OR_API_KEY:-${ANTHROPIC_API_KEY:-}}}"
        export IGOR_AI_TEXT_ONLY=true NEXUS_TOOLS_JSON='[]' IGOR_MODULE_TOOLS=''
        export NEXUS_PROVIDER="$provider" NEXUS_MODEL="$model" NEXUS_API_KEY="$api_key"
        export NEXUS_SYSTEM="$scrubbed_system" NEXUS_CONV="$conversation"
        export NEXUS_MAX_TOKENS=700 NEXUS_TEMPERATURE=0.2 IGOR_AI_REQUEST_ID=''
        if declare -f ai_begin_request >/dev/null 2>&1; then ai_begin_request || exit 1; fi
        local raw reply in_tokens out_tokens
        local -a returned_commands=()
        raw=$(_nexus_api_call 2>/dev/null) || exit 1
        _nexus_parse_result "$raw" reply returned_commands in_tokens out_tokens || exit 1
        [ "${IGOR_PROVIDER_ERROR:-false}" != true ] || exit 1
        [ "${#returned_commands[@]}" -eq 0 ] || exit 1
        reply="${reply#"${reply%%[![:space:]]*}"}"
        reply="${reply%"${reply##*[![:space:]]}"}"
        [ -n "$reply" ] || exit 1
        printf '%s' "$reply"
    ) || return 1
    [ -n "$explanation" ] || return 1
    AI_EXPLANATION_CACHE_PENDING="$pending_json"
    AI_EXPLANATION_CACHE_TEXT="$explanation"
    if [ "${_AI_EXPLANATION_DISPLAY_ONLY:-false}" = true ]; then
        printf '%s\n' "$explanation" >&2
    else
        printf '%s\n' "$explanation"
    fi
}

# Return codes are stable for callers: 0 approve, 1 decline, 3 stop.  Explain
# is handled in this loop so it can never consume or replace the approval.
# EOF fails closed as a decline.
_ai_approval_prompt() {
    local pending_json="${1:-${AI_PENDING_APPROVAL_JSON:-}}" tier="${2:-CHANGE}"
    local operation_id="${3:-}"
    local answer=""
    _AI_APPROVAL_OUTCOME=WAITING_APPROVAL
    while :; do
        case "$tier" in
            DESTROY)
                printf '  [E] Explain  [N] Cancel  type YES to execute  [/stop] Stop: ' >&2 ;;
            READ)
                printf '  [R] Run  [S] Skip  [E] Explain  [/stop] Stop: ' >&2 ;;
            *)
                printf '  [Y] Run  [N] Cancel  [E] Explain  [/stop] Stop: ' >&2 ;;
        esac
        if [ -t 0 ] && [ -r /dev/tty ]; then
            IFS= read -r answer </dev/tty || {
                _AI_APPROVAL_OUTCOME=DECLINE
                return 1
            }
        else
            IFS= read -r answer || {
                _AI_APPROVAL_OUTCOME=DECLINE
                return 1
            }
        fi
        case "${answer,,}" in
            /stop|stop) _AI_APPROVAL_OUTCOME=STOP; return 3 ;;
            e|explain)
                _AI_APPROVAL_OUTCOME=EXPLAIN
                declare -f _ai_set_session_state >/dev/null 2>&1 && \
                    _ai_set_session_state explaining_pending_action || true
                _AI_EXPLANATION_DISPLAY_ONLY=true
                if ! _ai_explain_pending_approval "$pending_json"; then
                    echo "  Unable to explain this pending action; nothing was executed." >&2
                else
                    _ai_emit_event explanation "$(_ai_event_payload "$operation_id" "" "$tier" pending explanation "${AI_EXPLANATION_CACHE_TEXT:-}")"
                fi
                _AI_EXPLANATION_DISPLAY_ONLY=false
                declare -f _ai_set_session_state >/dev/null 2>&1 && \
                    _ai_set_session_state awaiting_approval || true
                _AI_APPROVAL_OUTCOME=WAITING_APPROVAL
                ;;
            n|no|cancel|s|skip) _AI_APPROVAL_OUTCOME=DECLINE; return 1 ;;
            y|yes|r|run)
                [ "$tier" = DESTROY ] && [ "$answer" != YES ] && {
                    echo "  Type YES exactly to execute this destructive action." >&2
                    continue
                }
                _AI_APPROVAL_OUTCOME=APPROVE
                return 0 ;;
            *) echo "  Choose Run, Skip, Explain, or /stop${tier:+ (or type YES for destructive actions)}." >&2 ;;
        esac
    done
}

# Policy and module availability can change while the prompt is open. Fail
# closed before recording approval if the pending request is no longer valid.
_ai_pending_still_valid() {
    local tool_json="$1" tier="$2" tool="$3" action="$4"
    local owner="${5:-}" expected_entry="${6:-}" verdict verdict_flags
    if declare -f ai_policy_tool_allowed >/dev/null 2>&1 &&
       ! ai_policy_tool_allowed "$tool"; then
        return 1
    fi
    if [ "$tool" = run_igor_action ]; then
        if declare -f ai_policy_action_allowed >/dev/null 2>&1 &&
           ! ai_policy_action_allowed "$action"; then
            return 1
        fi
        [ -n "$owner" ] && declare -f _ml_owner_active >/dev/null 2>&1 &&
            _ml_owner_active "$owner" || return 1
        [ "${_IGOR_CAPABILITIES[$action]:-}" = "$expected_entry" ] || return 1
    fi
    case "$tool" in
        occ) _ai_require_active_capability nextcloud || return 1 ;;
        container) _ai_require_active_capability docker || return 1 ;;
    esac
    verdict=$(_ai_validate_tool_call "$tool_json") || return 1
    verdict_flags=$(printf '%s\n' "$verdict" | sed -n '/^BLOCKED: /p')
    [ "$verdict_flags" = "BLOCKED: false" ] || return 1
    # Guide READ proposals are revalidated too: mode changes or policy/module
    # changes while the prompt is open must never turn a stale request into an
    # executable action.
    [ "$tier" = READ ] || [ "$tier" = CHANGE ] || [ "$tier" = DESTROY ]
}

# Bound external READ commands; module capability functions keep their existing
# in-process environment and module/hook-specific execution contracts.
_ai_run_read_command() {
    local duration="${IGOR_AI_READ_TIMEOUT:-30}"
    if [[ ! "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]] || [[ "$duration" != *[1-9]* ]]; then
        duration=30
    fi
    if ! command -v timeout >/dev/null 2>&1; then
        echo "[ERROR: timeout is required for bounded read commands]" >&2
        return 127
    fi
    local rc=0
    timeout --kill-after=2s "${duration}s" "$@" || rc=$?
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
        echo "[TIMEOUT: read command exceeded ${duration}s]" >&2
    fi
    return "$rc"
}

# Unknown commands require approval. Only explicitly read-only forms auto-run.
ai_cmd_is_read() {
    printf '%s' "$1" | python3 "$_AI_INPUT_PARSER" read
}

# Parse semantic command arguments as data; never evaluate them as shell syntax.
# The caller supplies a local _ai_words array (Bash dynamic scope).
_ai_parse_words() {
    local word
    _ai_words=()
    while IFS= read -r -d '' word; do
        _ai_words+=("$word")
    done < <(printf '%s' "$1" | python3 "$_AI_INPUT_PARSER" words)
    local count=${#_ai_words[@]}
    [ "$count" -gt 1 ] && [ "${_ai_words[count-1]}" = "IGOR_INPUT_OK" ] || return 1
    unset '_ai_words[count-1]'
}

# Module-backed semantic tools must not become a second module loader.  The
# The normal startup path provides igor_has_capability from module_loader.sh.
# Module-backed tools fail closed if the loader is unavailable; callers that
# exercise the dispatcher in isolation must provide an explicit test stub.
_ai_require_active_capability() {
    local _cap="$1"
    if ! declare -f igor_has_capability >/dev/null 2>&1 || \
       ! igor_has_capability "$_cap"; then
        echo "[ERROR: Capability '${_cap}' is unavailable because no active module provides it]"
        return 1
    fi
    return 0
}

# D038 keeps raw shell as an unstructured fallback. These exact, maintained
# forms have canonical v2 operations and therefore must not be used as an AI
# workaround when the structured provider is unavailable or inactive.
_ai_reject_equivalent_raw_command() {
    local command="${1:-}" unit
    if [[ "$command" =~ ^[[:space:]]*(sudo[[:space:]]+)?(systemctl|/usr/bin/systemctl)[[:space:]]+restart[[:space:]]+([A-Za-z0-9][A-Za-z0-9_.@:+-]*)[[:space:]]*$ ]]; then
        unit="${BASH_REMATCH[3]}"
        echo "[BLOCKED: '${command}' is the structured capability system.service.restart; invoke run_capability with unit '${unit}']"
        return 0
    fi
    if [[ "$command" =~ ^[[:space:]]*(free|/usr/bin/free)([[:space:]]+(-b|--bytes))?[[:space:]]*$ ]]; then
        echo "[BLOCKED: '${command}' is covered by system.host.memory.refresh; invoke run_capability]"
        return 0
    fi
    return 1
}

# ── Tier 3: destructive commands ──────────────────────────────────────────────
ai_cmd_is_destroy() {
    local cmd="$1"
    # Package removal is data loss; normal package installs and upgrades are
    # CHANGE. Match the operation flag, including combined removal modifiers.
    if printf '%s\n' "$cmd" | grep -qE '(^|[[:space:]|&;])pacman[[:space:]]+(-R[[:alnum:]]*|--remove)([[:space:]]|$)'; then
        return 0
    fi
    # Require rm to be a shell word. A substring match incorrectly treated
    # pacman's --noconfirm option (ending in "rm ") as destructive removal.
    if printf '%s\n' "$cmd" | grep -qE '(^|[[:space:]|&;])(/usr/bin/|/bin/)?rm([[:space:]]|$)'; then
        return 0
    fi
    local destroy_patterns=(
        "docker volume rm"      "docker volume prune"
        "docker compose down"   "docker system prune"
        "FLUSHALL"          "DROP TABLE"            "DROP DATABASE"
        "DELETE FROM"       "TRUNCATE "
        "nuke"              "shred "                "wipe "
        "> /mnt/"
    )
    for pattern in "${destroy_patterns[@]}"; do
        echo "$cmd" | grep -qF "$pattern" && return 0
    done
    return 1
}

# ── Execute a semantic tool dict from the AI ─────────────────────────────────
# $1 = JSON tool dict e.g. {"tool":"occ","cmd":"status"}
# $2 = (optional) explain text to display in verbose mode
ai_execute_tool() {
    local tool_json="$1"
    local explain_text="${2:-}"
    local output=""
    unset IGOR_AI_CAPABILITY_OPERATION_ID IGOR_AI_CAPABILITY_OUTCOME IGOR_AI_CAPABILITY_VERIFICATION
    IGOR_CAPABILITY_LAST_RESULT=""
    local _operation_id AI_EVENT_NATIVE_ID
    local IGOR_HISTORY_OPERATION_ID="" IGOR_HISTORY_CORRELATION_ID="${IGOR_HISTORY_CORRELATION_ID:-}" IGOR_CAPABILITY_PRIVILEGE_STATUS=""
    _operation_id="ai_$(date +%s%N 2>/dev/null || date +%s)_$$"
    AI_EVENT_NATIVE_ID=$(printf '%s' "$tool_json" | python3 -c \
        'import json,sys; print(json.load(sys.stdin).get("__native_id", ""))' 2>/dev/null || true)
    _ai_audit_dispatch REQUEST "unknown" "unknown" "none" "requested" "0" \
        "" "$tool_json" "" "$_operation_id"

    # Fixed-position, validated data from Python. No tool-controlled shell code.
    local -a _fields=()
    local _field
    while IFS= read -r -d '' _field; do
        _fields+=("$_field")
    done < <(printf '%s' "$tool_json" | python3 "$_AI_INPUT_PARSER" fields)
    if [ "${#_fields[@]}" -ne 21 ] || [ "${_fields[20]:-}" != "IGOR_INPUT_OK" ]; then
        _ai_audit_dispatch BLOCKED "unknown" "unknown" "none" "invalid-input" "1" \
            "" "" "" "$_operation_id"
        echo "[BLOCKED: Invalid tool input]"
        return 1
    fi
    local T_TOOL="${_fields[0]}" T_CMD="${_fields[1]}" T_ACTION="${_fields[2]}"
    local T_TARGET="${_fields[3]}" T_LINES="${_fields[4]}" T_SEARCH="${_fields[5]}"
    local T_PATH="${_fields[6]}" T_FIND="${_fields[7]}" T_REPLACE="${_fields[8]}"
    local T_FILENAME="${_fields[9]}" T_TITLE="${_fields[10]}" T_DESCRIPTION="${_fields[11]}"
    local T_COMMAND="${_fields[12]}" T_TYPE="${_fields[13]}" T_TIER="${_fields[14]}"
    local T_MESSAGE="${_fields[15]}"
    local T_CAPABILITY_ID="${_fields[16]:-}" T_INPUTS="${_fields[17]:-}" T_PROVIDER="${_fields[18]:-}"
    local T_CAPABILITY_VERSION="${_fields[19]:-}"
    local -a _ai_words=() run_argv=()
    if declare -f ai_policy_tool_allowed >/dev/null 2>&1 &&
       ! ai_policy_tool_allowed "$T_TOOL"; then
        _ai_write_tool_meta "${T_TIER:-CHANGE}" denied action_denied "" policy
        _ai_audit_dispatch BLOCKED "$T_TOOL" "${T_TIER:-CHANGE}" "blocked" "policy" "1" \
            "" "$tool_json" "" "$_operation_id"
        echo "[BLOCKED: Tool is not allowed by active AI policy]"
        return 1
    fi
    if [ "$T_TOOL" = run_igor_action ] &&
       declare -f ai_policy_action_allowed >/dev/null 2>&1 &&
       ! ai_policy_action_allowed "$T_CMD"; then
        _ai_write_tool_meta "${T_TIER:-CHANGE}" denied action_denied "" action-policy
        _ai_audit_dispatch BLOCKED "$T_TOOL" "${T_TIER:-CHANGE}" "blocked" "action-policy" "1" \
            "" "$tool_json" "" "$_operation_id"
        echo "[BLOCKED: Action is not allowed by active AI policy]"
        return 1
    fi

    # These tools are supplied by modules and must remain unavailable when the
    # owning module is disabled.  This check happens before tier classification
    # and approval so a stale/native tool call cannot reach execution.
    case "${T_TOOL}" in
        occ)
            if ! _ai_require_active_capability nextcloud; then
                _ai_write_tool_meta READ denied action_denied "" capability-unavailable
                _ai_audit_dispatch BLOCKED "$T_TOOL" "READ" "none" "capability-unavailable" "1" \
                    "" "$T_CMD" "" "$_operation_id"
                return 1
            fi
            ;;
        container)
            if ! _ai_require_active_capability docker; then
                _ai_write_tool_meta CHANGE denied action_denied "" capability-unavailable
                _ai_audit_dispatch BLOCKED "$T_TOOL" "CHANGE" "none" "capability-unavailable" "1" \
                    "" "$T_ACTION $T_TARGET" "" "$_operation_id"
                return 1
            fi
            ;;
        read_log)
            if [ "${T_TARGET}" != terminal ] && ! _ai_require_active_capability docker; then
                _ai_write_tool_meta READ denied action_denied "" capability-unavailable
                _ai_audit_dispatch BLOCKED "$T_TOOL" "READ" "none" "capability-unavailable" "1" \
                    "" "$tool_json" "" "$_operation_id"
                return 1
            fi
            ;;
    esac

    local tier="READ"
    local run_cmd=""
    local display_cmd=""
    local _requires_admin=false
    local _cap_approved_digest=""
    # Raw host/legacy execute requests are deliberately stricter than
    # structured capabilities.  D038 keeps them available as an unstructured
    # fallback, but a mutating raw request always needs an explicit approval,
    # including in Executive mode.
    local _raw_shell=false
    # For run_igor_action: populated in case block, used in execution block
    local _ria_fn="" _ria_mod=""

    case "$T_TOOL" in
        occ)
            T_CMD=$(ai_unscrub_inbound "$T_CMD")
            if ! _ai_reject_unrestored_tokens "$T_CMD"; then
                _ai_audit_rejected "$T_TOOL" READ unresolved-token "$tool_json" "$_operation_id"; return 1
            fi
            display_cmd="occ ${T_CMD}"
            if ! _ai_parse_words "$T_CMD"; then
                _ai_audit_rejected "$T_TOOL" CHANGE invalid-arguments "$tool_json" "$_operation_id"
                echo "[BLOCKED: Invalid OCC arguments]"
                return 1
            fi
            run_argv=(docker compose exec -T -u www-data app php occ "${_ai_words[@]}")
            printf -v run_cmd '%q ' "${run_argv[@]}"
            if printf '%s' "$T_CMD" | python3 "$_AI_INPUT_PARSER" occ-read; then
                tier="READ"
            else
                tier="CHANGE"
            fi
            ;;
        host)
            _raw_shell=true
            T_CMD=$(ai_unscrub_inbound "$T_CMD")
            if ! _ai_reject_unrestored_tokens "$T_CMD"; then
                _ai_audit_rejected "$T_TOOL" CHANGE unresolved-token "$tool_json" "$_operation_id"; return 1
            fi
            if ai_is_denied "$T_CMD"; then
                _ai_audit_rejected "$T_TOOL" DESTROY denylist "$tool_json" "$_operation_id"
                echo -e "\n  ${RED}${BOLD}⛔ BLOCKED:${NC} Command is on the hard denylist." >&2
                echo -e "  ${RED}Matched:${NC} $T_CMD" >&2
                echo "[BLOCKED BY DENYLIST: ${T_CMD}]"
                return 1
            fi
            if [[ "$T_CMD" == *'<<'* ]]; then
                _ai_audit_rejected "$T_TOOL" CHANGE heredoc "$tool_json" "$_operation_id"
                echo "[BLOCKED: heredoc syntax is not allowed in AI raw shell]"
                return 1
            fi
            if _ai_reject_equivalent_raw_command "$T_CMD"; then
                _ai_audit_rejected "$T_TOOL" CHANGE equivalent-capability "$tool_json" "$_operation_id"
                return 1
            fi
            
            # Enhanced command validation using input_validation if available
            if declare -f sanitize_command >/dev/null; then
                if ! safe_cmd=$(sanitize_command "$T_CMD"); then
                    _ai_audit_rejected "$T_TOOL" CHANGE command-validation "$tool_json" "$_operation_id"
                    echo -e "\n  ${RED}${BOLD}⛔ BLOCKED:${NC} Command validation failed." >&2
                    echo -e "  ${RED}Reason:${NC} $safe_cmd" >&2
                    echo "[BLOCKED: Command validation failed]"
                    return 1
                fi
                T_CMD="$safe_cmd"
            fi
            
            if   ai_cmd_is_destroy "$T_CMD"; then tier="DESTROY"
            elif ai_cmd_is_read    "$T_CMD"; then tier="READ"
            else                                  tier="CHANGE"
            fi
            display_cmd="host: ${T_CMD}"
            
            run_cmd="$T_CMD"
            ;;
        container)
            tier="CHANGE"
            display_cmd="docker compose ${T_ACTION} ${T_TARGET}"
            run_argv=(docker compose "$T_ACTION" "$T_TARGET")
            printf -v run_cmd '%q ' "${run_argv[@]}"
            ;;
        read_log)
            tier="READ"
            display_cmd="read_log: ${T_TARGET} last ${T_LINES} lines  search='${T_SEARCH}'"
            if [ "$T_TARGET" = "terminal" ]; then
                local _tlog="${IGOR_RUNTIME_DIR:-${IGOR_DIR}/data/runtime}/terminal.log"
                run_argv=(tail -n "$T_LINES" -- "$_tlog")
            else
                run_argv=(docker compose logs --tail "$T_LINES" "$T_TARGET")
            fi
            printf -v run_cmd '%q ' "${run_argv[@]}"
            ;;
        edit_file)
            tier="CHANGE"
            display_cmd="edit_file: ${T_PATH}\n  find:    ${T_FIND}\n  replace: ${T_REPLACE}"
            ;;
        execute)
            # Legacy fallback — raw bash from <execute> tag
            _raw_shell=true
            local _cmd; _cmd=$(ai_unscrub_inbound "$T_CMD")
            if ! _ai_reject_unrestored_tokens "$_cmd"; then
                _ai_audit_rejected "$T_TOOL" CHANGE unresolved-token "$tool_json" "$_operation_id"; return 1
            fi
            if ai_is_denied "$_cmd"; then
                _ai_audit_rejected "$T_TOOL" DESTROY denylist "$tool_json" "$_operation_id"
                echo -e "\n  ${RED}${BOLD}⛔ BLOCKED:${NC} Command is on the hard denylist." >&2
                echo "[BLOCKED BY DENYLIST: ${_cmd}]"
                return 1
            fi
            if _ai_reject_equivalent_raw_command "$_cmd"; then
                _ai_audit_rejected "$T_TOOL" CHANGE equivalent-capability "$tool_json" "$_operation_id"
                return 1
            fi
            if echo "$_cmd" | grep -q '<<'; then
                _ai_audit_rejected "$T_TOOL" CHANGE heredoc "$tool_json" "$_operation_id"
                output="[BLOCKED: heredoc syntax (<<) not allowed. Use: printf '...' > /tmp/fix.py && python3 /tmp/fix.py]"
                echo -e "  ${RED}⛔ BLOCKED: heredoc syntax not allowed.${NC}" >&2
                echo "$output"; return 1
            fi
            if   ai_cmd_is_destroy "$_cmd"; then tier="DESTROY"
            elif ai_cmd_is_read    "$_cmd"; then tier="READ"
            else                                  tier="CHANGE"
            fi
            display_cmd="\$ ${_cmd}"
            run_cmd="$_cmd"
            ;;
        read_report)
            tier="READ"
            display_cmd="read_report: ${T_FILENAME}"
            local _rdir
            if [ -n "${REPORTS_DIR:-}" ]; then
                _rdir="$REPORTS_DIR"
            elif declare -f _igor_resolve_dir >/dev/null; then
                _rdir=$(_igor_resolve_dir reports)
            else
                _rdir="${IGOR_REPORTS_DIR:-${IGOR_DIR}/data/reports}"
            fi
            T_FILENAME=$(ai_unscrub_inbound "$T_FILENAME")
            if ! _ai_reject_unrestored_tokens "$T_FILENAME"; then
                _ai_audit_rejected "$T_TOOL" READ unresolved-token "$tool_json" "$_operation_id"; return 1
            fi
            output=$(_ai_run_read_command python3 "$_AI_FILE_READER" report "$IGOR_DIR" "$_rdir" "$T_FILENAME" 100 2>&1)
            local exit_code=$?
            _ai_audit_dispatch RESULT "$T_TOOL" "$tier" "automatic-read" \
                "$([ "$exit_code" -eq 0 ] && echo completed || echo failed)" "$exit_code" \
                "" "$tool_json" "$output" "$_operation_id"
            local _report_status="tool_succeeded"; [ "$exit_code" -ne 0 ] && _report_status="tool_failed"
            _ai_write_tool_meta READ not_required "$_report_status" "$exit_code" \
                "$([ "$exit_code" -eq 0 ] && echo || echo execution)"
            printf '%s\n' "$output"
            return "$exit_code"
            ;;
        read_file)
            tier="READ"
            T_PATH=$(ai_unscrub_inbound "$T_PATH")
            if ! _ai_reject_unrestored_tokens "$T_PATH"; then
                _ai_audit_rejected "$T_TOOL" READ unresolved-token "$tool_json" "$_operation_id"; return 1
            fi
            display_cmd="read_file: ${T_PATH} (up to ${T_LINES} lines)"
            run_argv=(python3 "$_AI_FILE_READER" file "$IGOR_DIR" "" "$T_PATH" "$T_LINES")
            printf -v run_cmd '%q ' "${run_argv[@]}"
            ;;
        propose_menu_item)
            # AI proposes a new dynamic menu item
            if [ -z "${items_dir:-}" ]; then
                _ai_audit_rejected "$T_TOOL" CHANGE unavailable-menu-backend "$tool_json" "$_operation_id"
                echo "[BLOCKED: Dynamic menu proposal storage is unavailable]"
                return 1
            fi
            tier="CHANGE"
            display_cmd="Propose dynamic menu item: ${T_TITLE}"
            ;;
        reply)
            # P2-1: Final reply tool — output prefixed message for caller to display and exit
            _ai_write_tool_meta READ not_required tool_succeeded 0 ""
            _ai_audit_dispatch RESULT "$T_TOOL" READ automatic-read completed 0 \
                "" "$tool_json" "$T_MESSAGE" "$_operation_id"
            echo "[REPLY] ${T_MESSAGE}"
            return 0
            ;;
        run_igor_action)
            # Look up action in the capability catalog populated by igor_load_capabilities()
            local _ria_name="${T_CMD:-}"
            local _ria_entry="${_IGOR_CAPABILITIES[${_ria_name}]:-}"
            if [ -z "$_ria_entry" ]; then
                _ai_audit_rejected "$T_TOOL" CHANGE unknown-action "$tool_json" "$_operation_id"
                echo "[ERROR: Unknown Igor action '${_ria_name}' — check AVAILABLE IGOR ACTIONS in context]"
                return 1
            fi
            local _ria_owner=""
            if declare -p _IGOR_CAPABILITY_OWNERS >/dev/null 2>&1; then
                _ria_owner="${_IGOR_CAPABILITY_OWNERS[${_ria_name}]:-}"
            fi
            if [ -z "$_ria_owner" ] || ! declare -f _ml_owner_active >/dev/null 2>&1 || \
               ! _ml_owner_active "$_ria_owner"; then
                _ai_audit_rejected "$T_TOOL" CHANGE inactive-owner "$tool_json" "$_operation_id"
                echo "[ERROR: Igor action '${_ria_name}' is unavailable because its owning module is inactive]"
                return 1
            fi
            local _ria_desc _ria_tier _ria_probs _ria_mpath
            IFS='|' read -r _ria_desc _ria_fn _ria_mod _ria_tier _ria_probs _ria_mpath <<< "$_ria_entry"
            tier="${_ria_tier:-CHANGE}"
            display_cmd="Igor action: ${_ria_name} → ${_ria_fn}()  [${_ria_mpath:-module: ${_ria_mod}}]"
            ;;
        run_capability)
            if ! declare -f igor_capability_prepare >/dev/null 2>&1; then
                _ai_audit_rejected "$T_TOOL" CHANGE capability-runtime-unavailable "$tool_json" "$_operation_id"
                echo "[ERROR: Capability runtime is unavailable]"
                return 1
            fi
            local _cap_prepared
            _cap_prepared=$(igor_capability_prepare "$T_CAPABILITY_ID" "$T_INPUTS" "$T_PROVIDER" "$T_CAPABILITY_VERSION") || {
                _ai_audit_rejected "$T_TOOL" CHANGE capability-unavailable "$tool_json" "$_operation_id"
                echo "[ERROR: Capability '${T_CAPABILITY_ID}' is unavailable or its inputs are invalid]"
                return 1
            }
            if printf '%s' "$_cap_prepared" | python3 -c 'import json,sys; raise SystemExit(0 if "composition_plan" in json.load(sys.stdin) else 1)'; then
                local _composite_tier _composite_rc _composite_output _composite_admin=false
                if [ "$(printf '%s' "$_cap_prepared" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("precondition_status","failed"))')" != satisfied ]; then
                    _composite_output=$(printf '%s' "$_cap_prepared" | python3 -c '
import json,sys
p=json.load(sys.stdin)
print(json.dumps({"capability_id":p.get("capability_id"),"capability_version":p.get("capability_version"),
                  "provider":p.get("provider"),"owner":p.get("owner"),
                  "execution_status":"not_executed","verification_status":"not_applicable",
                  "outcome":"precondition_failed","affected_objects":p.get("affected_objects",[]),
                  "recovery":p.get("recovery",{})},sort_keys=True,separators=(",",":")))
')
                    IGOR_CAPABILITY_LAST_RESULT="$_composite_output"
                    _ai_audit_rejected "$T_TOOL" CHANGE precondition_failed "$tool_json" "$_operation_id"
                    printf '%s\n' "$_composite_output"
                    return 1
                fi
                _composite_tier=$(printf '%s' "$_cap_prepared" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("safety",{}).get("tier","CHANGE"))') || _composite_tier=CHANGE
                [ "$(printf '%s' "$_cap_prepared" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("composition_summary",{}).get("privilege","none"))')" = required ] && _composite_admin=true
                IGOR_HISTORY_CORRELATION_ID="${IGOR_HISTORY_CORRELATION_ID:-${IGOR_AI_REQUEST_ID:-$_operation_id}}"
                _ai_audit_dispatch CLASSIFIED "$T_TOOL" "$_composite_tier" orchestrated admitted 0                     "$(_igor_capability_field "$_cap_prepared" owner 2>/dev/null)" "$tool_json" "" "$_operation_id"
                _ai_emit_event continuation "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$_composite_tier" orchestrated running "Composite capability: $T_CAPABILITY_ID" "" "" "$_composite_admin")"
                IGOR_CAPABILITY_LAST_RESULT=""
                _composite_output=$(igor_capability_composite_execute "$_cap_prepared")
                _composite_rc=$?
                [ -n "$IGOR_CAPABILITY_LAST_RESULT" ] && _composite_output="$IGOR_CAPABILITY_LAST_RESULT"
                _ai_audit_dispatch RESULT "$T_TOOL" "$_composite_tier" orchestrated                     "$([ "$_composite_rc" -eq 0 ] && printf completed || printf failed)" "$_composite_rc"                     "$(_igor_capability_field "$_cap_prepared" owner 2>/dev/null)" "$tool_json" "$_composite_output" "$_operation_id"
                printf '%s\n' "$_composite_output"
                return "$_composite_rc"
            fi
            # Operational identity is durable before approval, authentication,
            # compatibility backups, or the provider's possible external effect.
            IGOR_HISTORY_CORRELATION_ID="${IGOR_HISTORY_CORRELATION_ID:-${IGOR_AI_REQUEST_ID:-$_operation_id}}"
            IGOR_HISTORY_OPERATION_ID="$(_igor_history_begin "$_cap_prepared" "$IGOR_HISTORY_CORRELATION_ID" "$(ai_get_mode)")" || {
                _ai_audit_rejected "$T_TOOL" CHANGE history-unavailable "$tool_json" "$_operation_id"
                echo "[ERROR: Operational History unavailable; capability not admitted]"
                return 1
            }
            if [ "$(printf '%s' "$_cap_prepared" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("precondition_status","failed"))')" != satisfied ]; then
                output="$(_igor_capability_nonexecution_result "$_cap_prepared" precondition_failed)"
                IGOR_CAPABILITY_LAST_RESULT="$output"
                _ai_audit_rejected "$T_TOOL" CHANGE precondition_failed "$tool_json" "$_operation_id"
                printf '%s\n' "$output"
                return 1
            fi
            local _cap_tier _cap_privilege _cap_display
            _cap_tier=$(printf '%s' "$_cap_prepared" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("safety",{}).get("tier", ""))') || _cap_tier=""
            case "$_cap_tier" in
                READ|CHANGE|DESTROY) tier="$_cap_tier" ;;
                *) echo "[ERROR: Capability has invalid safety tier]"; return 1 ;;
            esac
            _cap_privilege=$(printf '%s' "$_cap_prepared" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("privilege", "none"))') || _cap_privilege="none"
            [ "$_cap_privilege" = required ] && _requires_admin=true
            _cap_display=$(printf '%s' "$_cap_prepared" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("description") or d.get("capability_id") or "capability")') || _cap_display="$T_CAPABILITY_ID"
            display_cmd="capability: ${T_CAPABILITY_ID}${T_PROVIDER:+ [provider ${T_PROVIDER}]} — ${_cap_display}"
            run_cmd="capability:${T_CAPABILITY_ID}"
            ;;
        error|*)
            echo "[ERROR: Unknown or malformed tool — ${T_TOOL:-?}${T_ERROR:+ ($T_ERROR)}]"
            return 1
            ;;
    esac

    _ai_command_requires_admin "$run_cmd" && _requires_admin=true

    _ai_audit_dispatch CLASSIFIED "$T_TOOL" "$tier" none classified 0 \
        "${_ria_owner:-}" "$tool_json" "" "$_operation_id"
    local _proposal_payload
    _proposal_payload=$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" proposed proposed "$display_cmd" "" "" "$_requires_admin")
    _ai_emit_event action_proposed "$_proposal_payload"
    _ai_write_tool_meta "$tier" pending pending "" ""

    # ── P1-4: Pre-execution validation (CHANGE tier) ─────────────────────────
    # Call ai_validate.py for CHANGE-tier commands; block if verdict says blocked.
    # Warnings are shown but do not block; blocked commands return early.
    if [[ "$tier" == "CHANGE" || "$tier" == "DESTROY" ]]; then
        local _verdict_lines _v_blocked="" _v_reason="" _v_warnings=""
        _verdict_lines=$(_ai_validate_tool_call "$tool_json")
        local _validator_rc=$?
        while IFS= read -r _vline; do
            case "$_vline" in
                "BLOCKED: true")  _v_blocked="true" ;;
                "REASON: "*)      _v_reason="${_vline#REASON: }" ;;
                "WARNINGS: "*)
                    _v_warnings="${_vline#WARNINGS: }"
                    if [ -n "$_v_warnings" ]; then
                        echo "" >&2
                        IFS='|' read -ra _vw_arr <<< "$_v_warnings"
                        for _vw in "${_vw_arr[@]}"; do
                            [ -n "$_vw" ] && echo -e "  ${YEL}⚠  Validator: ${_vw}${NC}" >&2
                        done
                    fi
                    ;;
            esac
        done <<< "$_verdict_lines"
        if [ "$_validator_rc" -ne 0 ] || [ -z "$_verdict_lines" ] ||
           ! printf '%s\n' "$_verdict_lines" | grep -q '^BLOCKED: \(true\|false\)$'; then
            _v_blocked=true
            _v_reason="validator unavailable or returned malformed output"
        fi
        if [ "$_v_blocked" = "true" ]; then
            echo -e "\n  ${RED}✘ Command blocked by validator: ${_v_reason}${NC}" >&2
            echo "[VALIDATION BLOCKED: ${_v_reason}]"
            _ai_audit_dispatch BLOCKED "$T_TOOL" "$tier" "none" "validator" "1" \
                "${_ria_owner:-}" "$tool_json" "$_v_reason" "$_operation_id"
            _ai_write_tool_meta "$tier" denied action_denied "" validation
            _IGOR_LAST_EXEC_TIER="CHANGE"
            if [ "$T_TOOL" = run_capability ]; then
                IGOR_CAPABILITY_LAST_RESULT="$(_igor_capability_nonexecution_result "$_cap_prepared" validation_blocked denied not_requested)"
            fi
            return 1
        fi
    fi

    # ── Verbose explanation box ───────────────────────────────────────────────
    if [ "${IGOR_VERBOSE:-true}" = "true" ] && [ -n "$explain_text" ]; then
        echo "" >&2
        echo -e "  ${CYAN}── WHY ──────────────────────────────────────────────────────${NC}" >&2
        echo "$explain_text" | fold -s -w 70 | sed 's/^/    /' >&2
        echo -e "  ${CYAN}────────────────────────────────────────────────────────────${NC}" >&2
    fi

    # ── UI tier display ───────────────────────────────────────────────────────
    # In quiet loop mode, suppress display for READ-only commands.
    local _mode; _mode=$(ai_get_mode)
    local _cap_requires_explicit_approval=false
    if [ "${T_TOOL:-}" = run_capability ]; then
        case "${T_CAPABILITY_ID:-}" in
            core.deployments.initialize|core.deployments.adopt|core.deployments.release)
                _cap_requires_explicit_approval=true ;;
        esac
    fi
    local _ui_quiet=false
    [ "${IGOR_QUIET_LOOP:-false}" = "true" ] && [ "$tier" = "READ" ] && \
        [ "$_mode" != guide ] && _ui_quiet=true

    if [ "$_ui_quiet" = "false" ] &&
       [ "${IGOR_AI_EVENT_RENDER:-false}" = true ] &&
       [ -n "${IGOR_AI_EVENT_STREAM:-}" ] &&
       declare -f _ai_event_render_payload >/dev/null 2>&1; then
        _ai_event_render_payload action_proposed "$_proposal_payload"
    elif [ "$_ui_quiet" = "false" ]; then
        echo "" >&2
        case "$tier" in
            READ)
                if [ "$_mode" = guide ]; then
                    echo -e "  ${CYAN}── PROPOSED (read-only) ──────────────────────────────────────${NC}" >&2
                else
                    echo -e "  ${CYAN}── AUTO-RUNNING (read-only) ──────────────────────────────────${NC}" >&2
                fi
                ;;
            CHANGE)
                if [ "$_mode" = executive ] && [ "$_raw_shell" = false ] &&
                   [ "$_cap_requires_explicit_approval" = false ]; then
                    echo -e "  ${YEL}── AUTO-RUNNING (policy-approved change) ─────────────────────${NC}" >&2
                else
                    echo -e "  ${YEL}── NEEDS APPROVAL (modifies system) ──────────────────────────${NC}" >&2
                fi
                ;;
            DESTROY) echo -e "  ${RED}${BOLD}── DESTRUCTIVE — DATA LOSS POSSIBLE ─────────────────────────${NC}" >&2 ;;
        esac
        echo -e "  ${BOLD}${display_cmd}${NC}" >&2
        echo "" >&2
    fi

    # ── Approval gate ─────────────────────────────────────────────────────────
    local run=false
    local approval_mode="automatic-read"
    case "$tier" in
        READ)
            if [ "$_mode" = guide ]; then
                approval_mode="guide"
                _ai_build_pending_approval "$tool_json" "$tier" "$display_cmd" \
                    "This read-only action is proposed for your review." "$_operation_id" "${T_CMD:-}" || {
                    echo "[BLOCKED: Could not create approval record]"
                    _ai_write_tool_meta "$tier" denied action_denied "" approval_record
                    if [ "$T_TOOL" = run_capability ]; then
                        IGOR_CAPABILITY_LAST_RESULT="$(_igor_capability_nonexecution_result "$_cap_prepared" approval_record_failed denied not_requested)"
                    fi
                    return 1
                }
                _ai_write_tool_meta "$tier" pending pending "" ""
                _ai_emit_event approval_waiting "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" pending awaiting_approval "$display_cmd" "" "" "$_requires_admin")"
                declare -f _ai_set_session_state >/dev/null 2>&1 && _ai_set_session_state awaiting_approval || true
                _ai_approval_prompt "$AI_PENDING_APPROVAL_JSON" READ "$_operation_id" || true
                case "$_AI_APPROVAL_OUTCOME" in
                    APPROVE) run=true ;;
                    STOP) approval_mode="stopped" ;;
                esac
            else
                run=true
            fi
            ;;
        CHANGE)
            if [ "$_mode" = executive ] && [ "$_raw_shell" = false ] && [ "$_cap_requires_explicit_approval" = false ]; then
                approval_mode="executive"
                echo -e "  ${YEL}Executive mode — auto-running.${NC}" >&2
                run=true
            else
                approval_mode="confirm"
                if [ "$_raw_shell" = true ] && [ "$_mode" = executive ]; then
                    echo -e "  ${YEL}Raw shell fallback — explicit approval is required in Executive mode.${NC}" >&2
                fi
                _ai_build_pending_approval "$tool_json" "$tier" "$display_cmd" \
                    "$([ "$_raw_shell" = true ] && echo 'Raw shell fallback requires explicit approval; no deterministic verifier is implied.' || echo 'This action may modify system state.')" "$_operation_id" "${T_CMD:-}" || {
                    echo "[BLOCKED: Could not create approval record]"
                    _ai_write_tool_meta "$tier" denied action_denied "" approval_record
                    if [ "$T_TOOL" = run_capability ]; then
                        IGOR_CAPABILITY_LAST_RESULT="$(_igor_capability_nonexecution_result "$_cap_prepared" approval_record_failed denied not_requested)"
                    fi
                    return 1
                }
                _ai_write_tool_meta "$tier" pending pending "" ""
                _ai_emit_event approval_waiting "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" pending awaiting_approval "$display_cmd" "" "" "$_requires_admin")"
                declare -f _ai_set_session_state >/dev/null 2>&1 && _ai_set_session_state awaiting_approval || true
                _ai_approval_prompt "$AI_PENDING_APPROVAL_JSON" CHANGE "$_operation_id" || true
                case "$_AI_APPROVAL_OUTCOME" in
                    APPROVE) run=true ;;
                    STOP) approval_mode="stopped" ;;
                esac
            fi
            ;;
        DESTROY)
            approval_mode="explicit-YES"
            _ai_build_pending_approval "$tool_json" "$tier" "$display_cmd" \
                "This action may delete data or cause irreversible effects." "$_operation_id" "${T_CMD:-}" || {
                echo "[BLOCKED: Could not create approval record]"
                _ai_write_tool_meta "$tier" denied action_denied "" approval_record
                if [ "$T_TOOL" = run_capability ]; then
                    IGOR_CAPABILITY_LAST_RESULT="$(_igor_capability_nonexecution_result "$_cap_prepared" approval_record_failed denied not_requested)"
                fi
                return 1
            }
            _ai_write_tool_meta "$tier" pending pending "" ""
            _ai_emit_event approval_waiting "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" pending awaiting_approval "$display_cmd" "" "" "$_requires_admin")"
            declare -f _ai_set_session_state >/dev/null 2>&1 && _ai_set_session_state awaiting_approval || true
            _ai_approval_prompt "$AI_PENDING_APPROVAL_JSON" DESTROY "$_operation_id" || true
            case "$_AI_APPROVAL_OUTCOME" in
                APPROVE) run=true ;;
                STOP) approval_mode="stopped" ;;
            esac
            ;;
    esac

    if [ "$run" = true ] && [ "$approval_mode" != automatic-read ] &&
       [ "$approval_mode" != executive ] &&
       ! _ai_pending_still_valid "$tool_json" "$tier" "$T_TOOL" "$T_CMD" \
           "${_ria_owner:-}" "${_ria_entry:-}"; then
        output="[VALIDATION BLOCKED: pending action is no longer valid]"
        _ai_write_tool_meta "$tier" denied action_denied "" approval_revalidation
        _ai_audit_dispatch BLOCKED "$T_TOOL" "$tier" none validation 1 \
            "${_ria_owner:-}" "$tool_json" "$output" "$_operation_id"
        if [ "$T_TOOL" = run_capability ]; then
            IGOR_CAPABILITY_LAST_RESULT="$(_igor_capability_nonexecution_result "$_cap_prepared" approval_invalid denied not_requested)"
        fi
        echo "$output"
        return 1
    fi

    local _approval_outcome="declined"
    [ "$run" = true ] && _approval_outcome="approved"
    [ "$approval_mode" = "stopped" ] && _approval_outcome="stopped"
    local _meta_approval="denied"
    if [ "$run" = true ]; then
        case "$approval_mode" in
            automatic-read) _meta_approval="not_required" ;;
            executive) _meta_approval="auto_approved" ;;
            *) _meta_approval="approved" ;;
        esac
    fi
    _ai_write_tool_meta "$tier" "$_meta_approval" pending "" ""
    _ai_audit_dispatch APPROVAL "$T_TOOL" "$tier" "$approval_mode" \
        "$_approval_outcome" 0 "${_ria_owner:-}" "$tool_json" "" "$_operation_id"
    # Operational History records one canonical authority transition only after
    # the final privilege outcome is known. Declined/stopped/auth-failed paths
    # terminalize directly from admitted with their canonical result.
    if [ "$approval_mode" = "stopped" ]; then
        output="[USER STOPPED] Pending action cancelled: ${display_cmd}"
        if [ "$T_TOOL" = run_capability ]; then
            output="$(_igor_capability_nonexecution_result "$_cap_prepared" approval_stopped stopped not_requested)"
            IGOR_CAPABILITY_LAST_RESULT="$output"
        fi
        echo -e "  ${YEL}  (stopped — command not run)${NC}" >&2
        _ai_write_tool_meta "$tier" denied action_denied "" approval_stopped
        _ai_audit_dispatch STOPPED "$T_TOOL" "$tier" stopped stopped "0" \
            "${_ria_owner:-}" "$tool_json" "" "$_operation_id"
        _ai_emit_event action_stopped "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" denied stopped "$display_cmd")"
        (( AI_CMD_BLOCKED++ )) || true
    elif $run; then
        local exit_code=0
        local _action_started_ms=""
        _action_started_ms=$(date +%s%3N 2>/dev/null || true)
        _ai_emit_event action_started "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" "$_meta_approval" started "$display_cmd" "" "" "$_requires_admin")"
        local _admin_auth_failed=false
        if [ "$_requires_admin" = true ]; then
            # Authenticate before backups or undo-state reads. sudo owns the
            # password exchange through /dev/tty; Igor never reads it.
            if sudo -n -v </dev/null >/dev/null 2>&1; then
                _ai_emit_event privilege_result "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" "$_meta_approval" authenticated "Administrator authentication already available" "" 0 true)"
            elif [ -t 0 ] && [ -r /dev/tty ]; then
                _ai_emit_event privilege_waiting "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" "$_meta_approval" waiting "Administrator authentication required" "" "" true)"
                if sudo -v </dev/tty >/dev/tty 2>&1; then
                    _ai_emit_event privilege_result "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" "$_meta_approval" authenticated "Administrator authentication completed" "" 0 true)"
                else
                    _admin_auth_failed=true
                    output="[ADMIN AUTHENTICATION FAILED] The approved action was not run."
                    exit_code=1
                    _ai_emit_event privilege_result "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" "$_meta_approval" failed "Administrator authentication failed; action not run" "" 1 true)"
                fi
            else
                _admin_auth_failed=true
                output="[ADMIN AUTHENTICATION FAILED] A terminal is required; the approved action was not run."
                exit_code=1
                _ai_emit_event privilege_result "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" "$_meta_approval" failed "Administrator authentication requires a terminal; action not run" "" 1 true)"
            fi
        fi
        if [ "$T_TOOL" = run_capability ] && [ "$_admin_auth_failed" = false ]; then
            local _history_privilege_result=not_required
            [ "$_requires_admin" = true ] && _history_privilege_result=authenticated
            if ! _igor_history_update authority "$IGOR_HISTORY_OPERATION_ID" "$_meta_approval" "$_history_privilege_result"; then
                output="$(_igor_capability_nonexecution_result "$_cap_prepared" history_unavailable "$_meta_approval" "$_history_privilege_result")"
                IGOR_CAPABILITY_LAST_RESULT="$output"
                printf '%s\n' "$output"
                return 1
            fi
        fi
        # Backups and undo-state reads happen only after approval.
        if [ "$_admin_auth_failed" = false ] && [[ "$tier" == "CHANGE" || "$tier" == "DESTROY" ]]; then
            declare -f config_backup_auto &>/dev/null && \
                config_backup_auto "pre-ai:${T_TOOL}" 2>/dev/null || true
        fi
        local _undo_prev_occ=""
        if [ "$_admin_auth_failed" = false ] && [[ "$tier" == "CHANGE" && "$T_TOOL" == "occ" ]] &&
           [[ "$run_cmd" == *"config:system:set"* ]]; then
            local _undo_occ_arg; _undo_occ_arg=$(echo "$run_cmd" | sed 's/.*php occ //')
            _undo_prev_occ=$(python3 "${IGOR_DIR}/core/lib/undo_stack.py" get-prev-occ "$_undo_occ_arg" 2>/dev/null || echo "UNSET")
        fi
        if [ "$_admin_auth_failed" = true ]; then
            if [ "$T_TOOL" = run_capability ]; then
                output="$(_igor_capability_nonexecution_result "$_cap_prepared" privilege_failed "$_meta_approval" failed)"
                IGOR_CAPABILITY_LAST_RESULT="$output"
            fi
        elif [ "$T_TOOL" = "edit_file" ]; then
            output=$(_safe_file_edit "$T_PATH" "$T_FIND" "$T_REPLACE" 2>&1)
            local exit_code=$?
        elif [ "$T_TOOL" = "propose_menu_item" ]; then
            output=$(_ai_propose_menu_item "$T_TITLE" "$T_DESCRIPTION" "$T_COMMAND" "$T_TYPE" "$T_TIER" 2>&1)
            local exit_code=$?
        elif [ "$T_TOOL" = "run_igor_action" ]; then
            # Load the module that owns this action, then call the function directly.
            # _ria_fn and _ria_mod were set in the case block above.
            if declare -f _igor_load_module &>/dev/null && [ -n "$_ria_mod" ]; then
                _igor_load_module "$_ria_mod" 2>/dev/null || true
            fi
            if ! declare -f "$_ria_fn" &>/dev/null; then
                output="[ERROR: Function ${_ria_fn} not found after loading module ${_ria_mod}]"
                local exit_code=1
            else
                output=$("$_ria_fn" </dev/null 2>&1)
                local exit_code=$?
            fi
        elif [ "$T_TOOL" = "run_capability" ]; then
            if ! declare -f igor_capability_execute >/dev/null 2>&1; then
                output="[ERROR: Capability runtime is unavailable]"
                local exit_code=1
            else
                _cap_approved_digest=$(printf '%s' "$_cap_prepared" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("digest", ""))')
                [ -n "$_cap_approved_digest" ] || {
                    output="[ERROR: Capability proposal has no approval digest]"
                    local exit_code=1
                    _cap_approved_digest=""
                }
                if [ -n "$_cap_approved_digest" ]; then
                    IGOR_CAPABILITY_APPROVED_DIGEST="$_cap_approved_digest"
                    IGOR_CAPABILITY_APPROVAL_STATUS="$_meta_approval"
                    IGOR_CAPABILITY_PRIVILEGE_STATUS="${_history_privilege_result:-not_required}"
                    export IGOR_CAPABILITY_APPROVED_DIGEST
                    export IGOR_CAPABILITY_APPROVAL_STATUS
                    local exit_code
                    if [ "$T_CAPABILITY_ID" = system.memory.warning.apply ] &&
                       [ "$(_igor_capability_field "$_cap_prepared" owner)" = system ] &&
                       [ "$(_igor_capability_field "$_cap_prepared" descriptor.handler)" = system__apply_memory_warning ] &&
                       [ "$(_igor_capability_field "$_cap_prepared" capability_version)" = 2 ] &&
                       [ "$(_igor_capability_field "$_cap_prepared" privilege)" = none ] &&
                       _igor_configuration_memory_warning_contract "$_cap_prepared"; then
                        # Exact reviewed process-local consumer: a command
                        # substitution would apply only to a disposable child.
                        # The same prepared/approved operation owns execution,
                        # verification and History in this session process.
                        IGOR_CAPABILITY_LAST_RESULT=""
                        igor_capability_execute "$_cap_prepared" >/dev/null
                        exit_code=$?
                        output="$IGOR_CAPABILITY_LAST_RESULT"
                    else
                        output=$(igor_capability_execute "$_cap_prepared" 2>&1)
                        exit_code=$?
                    fi
                    IGOR_CAPABILITY_LAST_RESULT="$output"
                    if [ "$exit_code" -eq 0 ]; then
                        local _cap_outcome _cap_metadata
                        _cap_metadata=$(printf '%s' "$output" | python3 -c 'import json,sys; r=json.load(sys.stdin); print("|".join(str(r.get(k,"")) for k in ("operation_id","outcome","verification_status")))' 2>/dev/null) || _cap_metadata='|failed|'
                        IFS='|' read -r IGOR_AI_CAPABILITY_OPERATION_ID _cap_outcome IGOR_AI_CAPABILITY_VERIFICATION <<< "$_cap_metadata"
                        IGOR_AI_CAPABILITY_OUTCOME="$_cap_outcome"
                        export IGOR_AI_CAPABILITY_OPERATION_ID IGOR_AI_CAPABILITY_OUTCOME IGOR_AI_CAPABILITY_VERIFICATION
                        [ "$_cap_outcome" = success ] || exit_code=1
                    fi
                    unset IGOR_CAPABILITY_APPROVED_DIGEST
                    unset IGOR_CAPABILITY_APPROVAL_STATUS
                fi
            fi
        else
            # Semantic tools execute argv directly; only approved raw tools use Bash.
            if [ "${#run_argv[@]}" -gt 0 ]; then
                if [ "$tier" = "READ" ]; then
                    output=$(cd "${IGOR_DIR:-.}" 2>/dev/null || cd /tmp || exit 1; _ai_run_read_command "${run_argv[@]}" </dev/null 2>&1)
                else
                    output=$(cd "${IGOR_DIR:-.}" 2>/dev/null || cd /tmp || exit 1; "${run_argv[@]}" </dev/null 2>&1)
                fi
                local exit_code=$?
                if [ "$T_TOOL" = "read_log" ] && [ -n "$T_SEARCH" ]; then
                    output=$(printf '%s\n' "$output" | grep -i -- "$T_SEARCH")
                fi
            else
                if [ "$_admin_auth_failed" = true ]; then
                    :
                elif [ "$tier" = "READ" ]; then
                    output=$(cd "${IGOR_DIR:-.}" 2>/dev/null || cd /tmp || exit 1; _ai_run_read_command bash -c "$run_cmd" </dev/null 2>&1)
                    local exit_code=$?
                elif [ "$_requires_admin" = true ]; then
                    # Authentication, when needed, was completed above.  Keep the
                    # approved command's stdin closed so later input cannot become
                    # a command argument or an accidental password channel.
                    output=$(cd "${IGOR_DIR:-.}" 2>/dev/null || cd /tmp || exit 1; bash -c "$run_cmd" </dev/null 2>&1)
                    local exit_code=$?
                else
                    output=$(cd "${IGOR_DIR:-.}" 2>/dev/null || cd /tmp || exit 1; bash -c "$run_cmd" </dev/null 2>&1)
                    local exit_code=$?
                fi
            fi
        fi

        # Truncate long output
        if [ "$_raw_shell" = true ]; then
            # Raw shell has no capability-level verifier or recovery contract.
            # Keep this status visible to callers and in the transcript; a
            # later named verification operation may establish its own result.
            output=$'[UNSTRUCTURED RAW SHELL; VERIFICATION UNAVAILABLE]\n'"${output}"
        fi
        local line_count; line_count=$(echo "$output" | wc -l)
        if [ "$line_count" -gt 35 ]; then
            local head_out tail_out
            head_out=$(echo "$output" | head -n 15)
            tail_out=$(echo "$output" | tail -n 10)
            output="${head_out}
[... $(( line_count - 25 )) lines omitted — use grep/head/tail to target output ...]
${tail_out}"
        fi
        if [ ${#output} -gt 2500 ]; then
            output="${output:0:2500}
[... truncated at 2500 chars ...]"
        fi

        # Keep the local presentation copy separate from the provider
        # TOOL:/OUTPUT: transport envelope and attach one wall-clock duration.
        local _display_output="$output" _duration_ms="" _action_finished_ms=""
        _action_finished_ms=$(date +%s%3N 2>/dev/null || true)
        if [[ "$_action_started_ms" =~ ^[0-9]+$ && "$_action_finished_ms" =~ ^[0-9]+$ ]] &&
           [ "$_action_finished_ms" -ge "$_action_started_ms" ]; then
            _duration_ms=$((_action_finished_ms - _action_started_ms))
        fi

        if [ "$_ui_quiet" = "false" ]; then
            echo -e "  ${CYAN}── OUTPUT ────────────────────────────────────────────────────${NC}" >&2
            while IFS= read -r _oline; do echo "  $_oline" >&2; done <<< "$output"
            echo "" >&2
            [ $exit_code -eq 0 ] \
                && echo -e "  ${GRN}✔ done (exit 0)${NC}" >&2 \
                || echo -e "  ${YEL}! exit code: ${exit_code}${NC}" >&2
            echo -e "  ${CYAN}──────────────────────────────────────────────────────────────${NC}" >&2
        fi

        output="TOOL:${T_TOOL} EXIT:${exit_code}\nOUTPUT:\n${output}"
        local _exec_status="tool_succeeded"; [ "$exit_code" -ne 0 ] && _exec_status="tool_failed"
        _ai_write_tool_meta "$tier" "$_meta_approval" "$_exec_status" "$exit_code" \
            "$([ "$exit_code" -eq 0 ] && echo || echo execution)"
        _ai_audit_dispatch RESULT "$T_TOOL" "$tier" "$approval_mode" \
            "$([ "$exit_code" -eq 0 ] && echo completed || echo failed)" "$exit_code" \
            "${_ria_owner:-}" "$tool_json" "$output" "$_operation_id"
        unset IGOR_AI_CAPABILITY_OPERATION_ID IGOR_AI_CAPABILITY_OUTCOME IGOR_AI_CAPABILITY_VERIFICATION
        _ai_emit_event action_output "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" "$_meta_approval" output "$_display_output" "$_display_output" "$exit_code" "$_requires_admin" "$_duration_ms")"
        [[ "$tier" == "CHANGE" || "$tier" == "DESTROY" ]] && \
            [ "$_admin_auth_failed" = false ] && ai_knowledge_mark_changed
        # P3-2: track executed command counts
        if [ "$_admin_auth_failed" = false ]; then
            case "$tier" in
                READ)            (( AI_CMD_READ++ ))   || true ;;
                CHANGE|DESTROY)  (( AI_CMD_CHANGE++ )) || true ;;
            esac
            # Signal tier to the agentic loop so it can inject a verify reminder.
            _IGOR_LAST_EXEC_TIER="$tier"
        else
            _IGOR_LAST_EXEC_TIER=""
        fi

        # ── Change journal hook ────────────────────────────────────────────
        # Legacy/raw operations retain their command-oriented recovery source.
        # Canonical operations cut over to Operational History; do not duplicate
        # their outcomes in the legacy journal or infer generic rollback.
        if [ "$_admin_auth_failed" = false ] && [ "$T_TOOL" != run_capability ] && declare -f journal_record &>/dev/null; then
            local _js="OK"; [ $exit_code -ne 0 ] && _js="FAIL"
            journal_record "igor" "occ_exec" "$tier" \
                "${run_cmd:-${display_cmd}}" "$_js" "exit:${exit_code}"
        fi

        # ── Undo stack push (CHANGE tier only, successful executions) ─────────
        if [[ "$tier" == "CHANGE" && $exit_code -eq 0 ]] && \
           declare -f _undo_stack_push_entry &>/dev/null; then
            _undo_stack_push_entry "$T_TOOL" "$run_cmd"
        fi

        # ── Notify hook — DESTROY-tier actions ────────────────────────────────
        if [ "$_admin_auth_failed" = false ] && [ "$tier" = "DESTROY" ]; then
            local _ns="OK"; [ $exit_code -ne 0 ] && _ns="FAIL (exit ${exit_code})"
            declare -f notify_event &>/dev/null && \
                notify_event "destroy_action" \
                    "AI ran DESTROY command (${_ns}): ${display_cmd}" \
                    "DESTROY Action Executed" \
                2>/dev/null || true
        fi

        # ── Pattern auto-proposal hook (Milestone 5) ───────────────────────
        # After successful CHANGE/DESTROY repairs, check if pattern is auto-eligible
        if [ $exit_code -eq 0 ] && [[ "$tier" == "CHANGE" || "$tier" == "DESTROY" ]]; then
            declare -f pattern_eligible_check &>/dev/null && _ai_pattern_to_menu_hook "$T_TOOL" "$run_cmd"
        fi
    else
        # The structured tool result carries denial to the parent session.
        if [ "$T_TOOL" = run_capability ]; then
            output="$(_igor_capability_nonexecution_result "$_cap_prepared" approval_denied denied not_requested)"
            IGOR_CAPABILITY_LAST_RESULT="$output"
        elif [ "$tier" = "DESTROY" ]; then
            output="[USER DECLINED] Destructive command not confirmed: ${display_cmd}"
        else
            output="[USER DECLINED] Command skipped: ${display_cmd}"
        fi
        echo -e "  ${YEL}  (skipped — command not run)${NC}" >&2
        _ai_write_tool_meta "$tier" denied action_denied "" approval_denied
        _ai_audit_dispatch DECLINED "$T_TOOL" "$tier" "declined" "declined" "0" \
            "${_ria_owner:-}" "$tool_json" "" "$_operation_id"
        local _decline_event=action_declined
        [ "$tier" = READ ] && _decline_event=action_skipped
        _ai_emit_event "$_decline_event" "$(_ai_event_payload "$_operation_id" "$T_TOOL" "$tier" denied declined "$display_cmd")"
        # P3-2: count declined/blocked commands
        (( AI_CMD_BLOCKED++ )) || true
    fi

    echo "$output"
}

# ── Safe file editing with backup + validation ───────────────────────────────
# Uses Python for literal string replacement — no sed, no awk, no regex escaping.
# Auto-validates nginx.conf after edit; rolls back on failure.
_safe_file_edit() {
    local path="$1"
    local find_str="$2"
    local replace_str="$3"
    local backup_path="${path}.bak.$(date +%s)"

    # Validate file path with enhanced security
    if declare -f validate_file_operation >/dev/null; then
        if ! safe_path=$(validate_file_operation "$path" "write"); then
            echo "Error: $safe_path"
            return 1
        fi
        path="$safe_path"
    else
        # Fallback validation if input_validation.sh not available
        if [ ! -f "$path" ]; then
            echo "Error: File not found on host: $path"
            return 1
        fi
    fi

    # Validate input strings
    if [ -z "$path" ]; then
        echo "Error: File path cannot be empty"
        return 1
    fi

    # Validate find and replace strings
    if [ -z "$find_str" ]; then
        echo "Error: <find> string cannot be empty"
        return 1
    fi

    # Check for dangerous patterns in replace string
    if echo "$replace_str" | grep -qE 'rm -rf|dd if=|mkfs|:|&|rm /'; then
        echo "Error: Dangerous replacement pattern detected"
        return 1
    fi

    echo "Creating backup: $backup_path"
    cp "$path" "$backup_path" || { echo "Error: Could not create backup."; return 1; }

    # Block empty <find> on nginx configs — "" in Python prepends content, corrupting the file
    if [ -z "$find_str" ] && [[ "$path" == *"nginx"* ]]; then
        echo "Error: Empty <find> is not allowed for nginx config files."
        echo "Read the file first with <host> grep -n 'keyword' ./web/nginx.conf </host>"
        echo "then provide a specific <find> string that uniquely matches the section to modify."
        mv "$backup_path" "$path"
        return 1
    fi

    export _SFE_PATH="$path" _SFE_FIND="$find_str" _SFE_REPLACE="$replace_str"
    python3 - << 'PYEOF'
import os, sys
path    = os.environ["_SFE_PATH"]
find    = os.environ["_SFE_FIND"]
replace = os.environ["_SFE_REPLACE"]
try:
    with open(path, "r") as f:
        content = f.read()
    if find not in content:
        print("Error: <find> text not found in file. No changes made.")
        sys.exit(1)
    with open(path, "w") as f:
        f.write(content.replace(find, replace, 1))
    print("Replacement applied.")
except Exception as e:
    print(f"Python error: {e}")
    sys.exit(1)
PYEOF
    local py_exit=$?
    unset _SFE_PATH _SFE_FIND _SFE_REPLACE

    if [ $py_exit -ne 0 ]; then
        echo "Rolling back to backup."
        mv "$backup_path" "$path"
        return 1
    fi

    if [[ "$path" == *"nginx.conf"* ]]; then
        echo "Validating nginx syntax..."
        if ! docker compose exec web nginx -t 2>&1; then
            echo "Nginx validation FAILED — rolling back."
            mv "$backup_path" "$path"
            return 1
        fi
        echo "Nginx OK — reloading."
        docker compose exec web nginx -s reload
    fi

    echo "Edit applied successfully. Backup kept at: $backup_path"
    return 0
}

# ── Propose dynamic menu item ────────────────────────────────────────────────
# Writes a pending dynamic menu item file to the config directory.
# $1=TITLE $2=DESCRIPTION $3=COMMAND $4=TYPE $5=TIER
_ai_propose_menu_item() {
    local title="$1"
    local description="$2"
    local command="$3"
    local item_type="$4"
    local tier="$5"

    # Validate inputs
    [ -z "$title" ] && { echo "Error: TITLE is required."; return 1; }
    [ -z "$description" ] && { echo "Error: DESCRIPTION is required."; return 1; }
    [ -z "$command" ] && { echo "Error: COMMAND is required."; return 1; }
    [ -z "$item_type" ] && { echo "Error: TYPE is required."; return 1; }
    [ -z "$tier" ] && { echo "Error: TIER is required."; return 1; }

    # Validate TYPE
    [[ ! "$item_type" =~ ^(ONE_TIME|REPEATING)$ ]] && \
        { echo "Error: TYPE must be ONE_TIME or REPEATING."; return 1; }

    # Validate TIER
    [[ ! "$tier" =~ ^(READ|CHANGE|DESTROY)$ ]] && \
        { echo "Error: TIER must be READ, CHANGE, or DESTROY."; return 1; }

    # Generate ID from timestamp
    local item_id="$(date +%s)"

    # Write item file
    mkdir -p "$items_dir"
    local item_file="${items_dir}/${item_id}.item"

    {
        echo "ID: ${item_id}"
        echo "TITLE: ${title}"
        echo "DESCRIPTION: ${description}"
        echo "COMMAND: ${command}"
        echo "TYPE: ${item_type}"
        echo "TIER: ${tier}"
        echo "APPROVED: 0"
        echo "CONFIRMED_COUNT: 0"
        echo "FAILED_COUNT: 0"
        echo "CREATED: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "AUTHOR: AI Assistant"
    } > "$item_file"

    echo "Dynamic menu item proposed: ${title}"
    echo "Item ID: ${item_id}"
    echo "Type: ${item_type} | Tier: ${tier}"
    echo ""
    echo "The item is pending user approval. It will appear in:"
    echo "  Maintenance → Pending menu items"
    echo ""
    echo "To approve it manually:"
    echo "  Edit ${item_id}.item and set APPROVED: 1"

    return 0
}

# ── Pattern to dynamic menu item hook ───────────────────────────────────────
# Checks if a successful repair matches an auto-eligible pattern and proposes
# a dynamic menu item for it. This is the bridge between pattern system
# (M4) and dynamic menu items (M5).
# $1 = tool_type $2 = command_executed
_ai_pattern_to_menu_hook() {
    local tool_type="$1"
    local cmd_executed="$2"

    # Only hook specific tool types
    case "$tool_type" in
        occ|host|container) ;;
        *) return 0 ;;
    esac

    # For Stage 1, this is a skeleton. Full implementation would:
    # 1. Match cmd_executed against known patterns
    # 2. Check pattern_eligible_check() for auto-eligibility
    # 3. If eligible, call _ai_propose_menu_item() with pattern data
    #
    # For now, this is documented for future enhancement as patterns accumulate.

    return 0
}

# ── Undo stack entry builder ─────────────────────────────────────────────────
# Called after successful CHANGE execution. Pushes an undo entry to the stack.
# Args: $1=tool $2=run_cmd
# Expects outer-scope vars: T_PATH T_FIND T_REPLACE _undo_prev_occ session_id
_undo_stack_push_entry() {
    local _tool="$1" _run_cmd="$2"
    local _ts; _ts=$(date -u +"%Y-%m-%dT%H:%M:%S")
    local _turn="${_ai_turn:-0}"
    local _igor_dir="${IGOR_DIR:-.}"
    local _py="${_igor_dir}/lib/undo_stack.py"
    [ -f "$_py" ] || return 0

    local _entry=""
    case "$_tool" in
        edit_file)
            _entry=$(python3 -c "
import json, sys
find_str = sys.argv[1]
repl_str = sys.argv[2]
path_str = sys.argv[3]
e = {
  'turn': int('${_turn}'),
  'timestamp': '${_ts}',
  'tool': 'edit_file',
  'forward': {'path': path_str, 'find': find_str, 'replace': repl_str},
  'reverse': {'path': path_str, 'find': repl_str, 'replace': find_str},
  'backup_path': path_str + '.bak.*'
}
print(json.dumps(e))
" "$T_FIND" "$T_REPLACE" "$T_PATH" 2>/dev/null) ;;
        occ)
            local _fwd_cmd; _fwd_cmd=$(echo "$_run_cmd" | sed 's/.*php occ //')
            local _prev="${_undo_prev_occ:-UNSET}"
            local _key; _key=$(echo "$_fwd_cmd" | awk '{print $2}')
            local _rev_cmd
            if [ "$_prev" = "UNSET" ]; then
                _rev_cmd="config:system:delete ${_key}"
            else
                _rev_cmd="config:system:set ${_key} --value=${_prev}"
            fi
            _entry=$(python3 -c "
import json
e = {
  'turn': int('${_turn}'),
  'timestamp': '${_ts}',
  'tool': 'occ',
  'forward': {'command': '${_fwd_cmd}'},
  'reverse': {'command': '${_rev_cmd}'},
  'previous_value': None if '${_prev}' == 'UNSET' else '${_prev}'
}
print(json.dumps(e))
" 2>/dev/null) ;;
        *)
            _entry=$(python3 -c "
import json
e = {
  'turn': int('${_turn}'),
  'timestamp': '${_ts}',
  'tool': '${_tool}',
  'forward': {'command': '${_run_cmd}'},
  'reverse': None,
  'manual_undo': True
}
print(json.dumps(e))
" 2>/dev/null) ;;
    esac

    [ -n "$_entry" ] && \
        python3 "$_py" push "${session_id:-unknown}" "$_entry" 2>/dev/null || true
}
