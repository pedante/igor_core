#!/bin/bash
# API key entry and persistence. Prompts never write into captured key output.

_ai_openrouter_cutover() {
    local _root="${IGOR_DIR:-}" _data _state
    [ -n "$_root" ] || return 0
    _data="${IGOR_DATA_DIR:-${_root}/data}"
    if [ ! -f "${_root}/core/lib/configuration.py" ]; then
        [ -e "${_data}/secrets/catalog.db" ]
        return $?
    fi
    _state=$(IGOR_CONFIGURATION_ROOT="$_root" IGOR_CONFIGURATION_DATA_DIR="$_data" \
        env -u OPENROUTER_API_KEY -u OR_API_KEY -u NEXUS_API_KEY \
        python3 "${_root}/core/lib/configuration.py" openrouter-cutover-guard 2>/dev/null) || return 0
    [ "$_state" != legacy ]
}

# Existing sessions can outlive an external rotation or first cutover. Read a
# legacy cache only while the authoritative refusal fence permits that source.
_ai_openrouter_cached_key() {
    if ! _ai_openrouter_cutover; then
        printf '%s' "${or_api_key:-}"
    fi
}

# Resolve OpenRouter lifecycle state without retaining credential material in
# the interactive process.  The status command creates no store when absent.
_ai_openrouter_status() {
    if ! declare -f _igor_configuration_call >/dev/null 2>&1; then
        # Configuration adapter is linted directly; do not expand lazy import cycles.
        # shellcheck source=/dev/null
        source "${IGOR_DIR}/core/lib/configuration.sh" || return 1
    fi
    _igor_configuration_call secret-status
}

_ai_openrouter_inspect() {
    _igor_configuration_call inspect '{"id":"ai.openrouter.credential","target":"installation:local"}'
}

# Stage a private credential, then submit only the opaque ticket and CAS
# metadata through the existing canonical CHANGE dispatcher. Validation of
# the staged value happens inside Configuration Service after approval.
_ai_openrouter_commit_private() {
    local _key="$1" _source_kind="${2:-private_input}" _secret _view _ticket _payload
    local _generation _revision _state _action
    if ! declare -f _igor_configuration_call >/dev/null 2>&1; then
        # Configuration adapter is linted directly; do not expand lazy import cycles.
        # shellcheck source=/dev/null
        source "${IGOR_DIR}/core/lib/configuration.sh" || return 1
    fi
    _secret="$(_ai_openrouter_status)" || return 1
    _generation="$(printf '%s' "$_secret" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("revision",0))')" || return 1
    _view="$(_ai_openrouter_inspect)" || return 1
    _revision="$(printf '%s' "$_view" | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])')" || return 1
    _state="$(printf '%s' "$_view" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state_token"])')" || return 1
    _ticket="$(printf '%s' "$_key" | IGOR_CONFIGURATION_ROOT="$IGOR_DIR" \
        IGOR_CONFIGURATION_DATA_DIR="${IGOR_DATA_DIR:-${IGOR_DIR}/data}" \
        IGOR_SECRET_SOURCE_KIND="$_source_kind" IGOR_SECRET_EXPECTED_REVISION="$_generation" \
        python3 "${IGOR_DIR}/core/lib/configuration.py" stage-openrouter)" || return 1
    [[ "$_ticket" =~ ^[0-9a-f]{48}$ ]] || return 1
    _ai_openrouter_commit_ticket "$_ticket" "$_source_kind" "$_generation" "$_secret" "$_revision" "$_state"
}

_ai_openrouter_discard_if_uncommitted() {
    local _ticket="$1" _expected_revision="$2" _current
    _current="$(_ai_openrouter_inspect 2>/dev/null)" || return 0
    local _revision
    _revision="$(printf '%s' "$_current" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("revision",-1))' 2>/dev/null)" || return 0
    [ "$_revision" = "$_expected_revision" ] || return 0
    _igor_configuration_call secret-discard "$(python3 -c 'import json,sys; print(json.dumps({"ticket":sys.argv[1]}))' "$_ticket")" >/dev/null 2>&1 || true
}

_ai_openrouter_import_private_stdin() {
    local _mode="${1:-normal}" _secret _view _generation _revision _state _ticket
    if ! declare -f _igor_configuration_call >/dev/null 2>&1; then
        # Configuration adapter is linted directly; do not expand lazy import cycles.
        # shellcheck source=/dev/null
        source "${IGOR_DIR}/core/lib/configuration.sh" || return 1
    fi
    _secret="$(_ai_openrouter_status)" || return 1
    if [ "$_mode" = reimport ]; then
        _generation=0
    else
        _generation="$(printf '%s' "$_secret" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("revision",0))')" || return 1
    fi
    _view="$(_ai_openrouter_inspect)" || return 1
    _revision="$(printf '%s' "$_view" | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])')" || return 1
    _state="$(printf '%s' "$_view" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state_token"])')" || return 1
    local _stage_action=stage-openrouter
    [ "$_mode" = reimport ] && _stage_action=stage-openrouter-recovery
    _ticket="$(IGOR_CONFIGURATION_ROOT="$IGOR_DIR" \
        IGOR_CONFIGURATION_DATA_DIR="${IGOR_DATA_DIR:-${IGOR_DIR}/data}" \
        IGOR_SECRET_SOURCE_KIND=private_input IGOR_SECRET_EXPECTED_REVISION="$_generation" \
        python3 "${IGOR_DIR}/core/lib/configuration.py" "$_stage_action")" || return 1
    [[ "$_ticket" =~ ^[0-9a-f]{48}$ ]] || return 1
    _ai_openrouter_commit_ticket "$_ticket" private_input "$_generation" "$_secret" "$_revision" "$_state" "$_mode"
}

_ai_openrouter_commit_ticket() {
    local _ticket="$1" _source_kind="$2" _generation="$3" _secret="$4" _revision="$5" _state="$6" _mode="${7:-normal}"
    local _action _payload
    if [ "$_mode" = reimport ]; then
        _action=core.configuration.openrouter_credential.reimport
    elif printf '%s' "$_secret" | python3 -c 'import json,sys; raise SystemExit(0 if json.load(sys.stdin).get("cutover") else 1)'; then
        _action=core.configuration.openrouter_credential.rotate
    else
        _action=core.configuration.openrouter_credential.set
    fi
    _payload="$(python3 - "$_action" "$_ticket" "$_source_kind" "$_generation" "$_revision" "$_state" <<'PY'
import json,sys
ident,ticket,source,generation,revision,state=sys.argv[1:]
print(json.dumps({"tool":"run_capability","id":ident,"provider":"core","inputs":{
    "ticket":ticket,"source_kind":source,"generation_revision":int(generation),
    "revision":int(revision),"state":state}},separators=(",",":")))
PY
)" || return 1
    if ! declare -f ai_execute_tool >/dev/null 2>&1; then
        source "${IGOR_DIR}/core/lib/capability.sh" || return 1
        _igor_capability_load_dispatcher || {
            _ai_openrouter_discard_if_uncommitted "$_ticket" "$_revision"
            return 1
        }
    fi
    IGOR_CAPABILITY_LAST_RESULT=""
    ai_execute_tool "$_payload"
    local _dispatch_rc=$?
    if [ "$(printf '%s' "$IGOR_CAPABILITY_LAST_RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("outcome",""))' 2>/dev/null)" != success ]; then
        _ai_openrouter_discard_if_uncommitted "$_ticket" "$_revision"
        return 1
    fi
    [ "$_dispatch_rc" -eq 0 ]
}

_ai_openrouter_import_source() {
    local _source="$1" _mode="${2:-normal}" _secret _view _generation _revision _state _staged _ticket _kind _stage_action
    if ! declare -f _igor_configuration_call >/dev/null 2>&1; then
        # Configuration adapter is linted directly; do not expand lazy import cycles.
        # shellcheck source=/dev/null
        source "${IGOR_DIR}/core/lib/configuration.sh" || return 1
    fi
    _secret="$(_ai_openrouter_status)" || return 1
    if [ "$_mode" = reimport ]; then
        _generation=0
        _stage_action=stage-openrouter-recovery-source
    else
        _generation="$(printf '%s' "$_secret" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("revision",0))')" || return 1
        _stage_action=stage-openrouter-source
    fi
    _view="$(_ai_openrouter_inspect)" || return 1
    _revision="$(printf '%s' "$_view" | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])')" || return 1
    _state="$(printf '%s' "$_view" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state_token"])')" || return 1
    _staged="$(_igor_configuration_call "$_stage_action" "$(python3 - "$_source" "$_generation" <<'PY'
import json,sys
print(json.dumps({"source":sys.argv[1],"generation_revision":int(sys.argv[2])},separators=(",",":")))
PY
)" )" || return 1
    _ticket="$(printf '%s' "$_staged" | python3 -c 'import json,sys; print(json.load(sys.stdin)["ticket"])')" || return 1
    _kind="$(printf '%s' "$_staged" | python3 -c 'import json,sys; print(json.load(sys.stdin)["source_kind"])')" || return 1
    _ai_openrouter_commit_ticket "$_ticket" "$_kind" "$_generation" "$_secret" "$_revision" "$_state" "$_mode"
}

# Reuse the retained private stage under a new canonical approval after an
# interrupted/terminal operation. Running ownership is rejected by Core.
_ai_openrouter_resume_pending() {
    local _secret _view _ticket _source _generation _revision _state
    _secret="$(_ai_openrouter_status)" || return 1
    _view="$(_ai_openrouter_inspect)" || return 1
    read -r _ticket _source _generation < <(printf '%s' "$_secret" | python3 -c '
import json,sys
r=json.load(sys.stdin)
if not r.get("pending"): raise SystemExit(1)
print(r["pending_ticket"],r["pending_source_kind"],r["revision"])
')
    [[ "$_ticket" =~ ^[0-9a-f]{48}$ ]] || return 1
    read -r _revision _state < <(printf '%s' "$_view" | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r["revision"],r["state_token"])')
    _ai_openrouter_commit_ticket "$_ticket" "$_source" "$_generation" "$_secret" "$_revision" "$_state"
}

_ai_openrouter_recover_previous() {
    local _secret _view _generation _revision _state _payload
    if ! declare -f _igor_configuration_call >/dev/null 2>&1; then
        # Configuration adapter is linted directly; do not expand lazy import cycles.
        # shellcheck source=/dev/null
        source "${IGOR_DIR}/core/lib/configuration.sh" || return 1
    fi
    _secret="$(_ai_openrouter_status)" || return 1
    _generation="$(printf '%s' "$_secret" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("revision",0))')" || return 1
    _view="$(_ai_openrouter_inspect)" || return 1
    _revision="$(printf '%s' "$_view" | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])')" || return 1
    _state="$(printf '%s' "$_view" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state_token"])')" || return 1
    _payload="$(python3 - "$_generation" "$_revision" "$_state" <<'PY'
import json,sys
generation,revision,state=sys.argv[1:]
print(json.dumps({"tool":"run_capability","id":"core.configuration.openrouter_credential.restore_previous",
 "provider":"core","inputs":{"generation_revision":int(generation),"revision":int(revision),"state":state}},separators=(",",":")))
PY
)" || return 1
    if ! declare -f ai_execute_tool >/dev/null 2>&1; then
        source "${IGOR_DIR}/core/lib/capability.sh" || return 1
        _igor_capability_load_dispatcher || return 1
    fi
    IGOR_CAPABILITY_LAST_RESULT=""
    ai_execute_tool "$_payload" || return 1
    if [ "$(printf '%s' "$IGOR_CAPABILITY_LAST_RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("outcome",""))' 2>/dev/null)" = success ]; then
        unset OPENROUTER_API_KEY OR_API_KEY NEXUS_API_KEY or_api_key
        return 0
    fi
    return 1
}

_ai_prompt_key() {
    local _key
    if [ "$1" = openrouter ]; then
        printf '  Enter %s API key (hidden; Enter cancels):\n' "$1" >&2
        IFS= read -r -s _key || return 1
        printf '\n' >&2
    else
        printf '  Enter %s API key (visible; Enter cancels):\n' "$1" >&2
        IFS= read -r _key || return 1
    fi
    # Remove surrounding paste whitespace, but reject embedded whitespace.
    _key="${_key#"${_key%%[![:space:]]*}"}"
    _key="${_key%"${_key##*[![:space:]]}"}"
    [[ -n "$_key" && "$_key" != *[[:space:]]* ]] || return 1
    printf '%s' "$_key"
}

_ai_write_key() {
    local _provider="$1" _key="$2" _env
    case "$_provider" in
        anthropic) _env=ANTHROPIC_API_KEY ;;
        openrouter) _ai_openrouter_commit_private "$2" ; return $? ;;
        *) return 1 ;;
    esac
    _key="${_key#"${_key%%[![:space:]]*}"}"
    _key="${_key%"${_key##*[![:space:]]}"}"
    [[ -n "$_key" && "$_key" != *[[:space:]]* ]] || return 1
    local _sec_dir="${IGOR_DIR}/secrets" _tmp
    mkdir -p "$_sec_dir" || return 1
    _tmp=$(mktemp "${_sec_dir}/.${_provider}.key.XXXXXX") || return 1
    if ! { chmod 600 "$_tmp" && printf '%s\n' "$_key" > "$_tmp" &&
           mv -fT "$_tmp" "${_sec_dir}/${_provider}.key"; }; then
        rm -f "$_tmp"
        return 1
    fi
    # Startup exports these variables; replace that cached value immediately.
    export "${_env}=${_key}"
}

# Called in menu_ai's scope, so the active chat key changes without a restart.
_ai_change_key() {
    local _provider="$1" _new_key
    case "$_provider" in
        anthropic|openrouter) ;;
        *) echo '  This provider does not require an API key.'; return 0 ;;
    esac
    _new_key=$(_ai_prompt_key "$_provider") || return 1
    if [ "$_provider" = openrouter ]; then
        if _ai_openrouter_commit_private "$_new_key"; then
            unset OPENROUTER_API_KEY OR_API_KEY NEXUS_API_KEY or_api_key
            _ai_openrouter_available=true
            ok 'OpenRouter credential approved and activated for the next request.'
            return 0
        fi
        warn 'OpenRouter credential was not changed; approval, validation, or storage failed.'
        return 1
    fi
    if ! _nexus_validate_key "$_provider" "$_new_key"; then
        warn 'Key rejected or provider unreachable — existing key kept.'
        return 1
    fi
    _ai_write_key "$_provider" "$_new_key" || {
        fail 'API key could not be saved — existing key kept.'
        return 1
    }
    case "$_provider" in
        anthropic) api_key="$_new_key" ;;
        openrouter) or_api_key="$_new_key" ;;
    esac
    ok "${_provider} key validated and saved. It is active for your next message."
}

_nexus_validate_key() {
    case "$1" in
        anthropic) _nexus_validate_ant_key "$2" ;;
        openrouter) _nexus_validate_or_key "$2" ;;
        *) return 1 ;;
    esac
}
