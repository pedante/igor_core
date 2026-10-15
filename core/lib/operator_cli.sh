#!/usr/bin/env bash
# Step 20 CLI routing and presentation. Backend services own facts,
# authorization, privilege, execution and canonical results.

igor_operator_cli_normalize() {
    _IGOR_OPERATOR_ARGS=()
    if [ "${1:-}" = "--json" ]; then
        export IGOR_CLI_JSON=true
        shift
    else
        export IGOR_CLI_JSON=false
    fi
    [ "${IGOR_CLI_JSON}" != true ] || [ "$#" -gt 0 ] || return 2
    local _cmd="${1:-}" _sub _prompt _inputs
    case "$_cmd" in
        "") ;;
        modules)
            shift
            case "${1:-list}" in
                list) _IGOR_OPERATOR_ARGS=(--modules) ;;
                inspect|detach-plan)
                    _sub="$1"; shift
                    [ "$#" -eq 1 ] || return 2
                    _IGOR_OPERATOR_ARGS=(--modules "$_sub" "$1") ;;
                *) return 2 ;;
            esac ;;
        capability|capabilities)
            shift
            case "${1:-list}" in
                list) _IGOR_OPERATOR_ARGS=(--capabilities list) ;;
                inspect)
                    shift
                    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
                    _IGOR_OPERATOR_ARGS=(--capabilities inspect "$@") ;;
                plan)
                    shift; [ "$#" -eq 1 ] || return 2
                    _IGOR_OPERATOR_ARGS=(--capabilities plan "$1") ;;
                run)
                    shift; [ "$#" -ge 1 ] && [ "$#" -le 3 ] || return 2
                    _inputs="${2:-}"
                    [ -n "$_inputs" ] || _inputs='{}'
                    _IGOR_OPERATOR_ARGS=(--capability-run "$1" "$_inputs" "${3:-}") ;;
                *) return 2 ;;
            esac ;;
        recognition)
            shift
            [ "$#" -eq 0 ] || [ "$#" -eq 1 ] || return 2
            case "${1:-status}" in
                status|view) _IGOR_OPERATOR_ARGS=(--recognition "${1:-status}") ;;
                *) return 2 ;;
            esac ;;
        deployments) shift; _IGOR_OPERATOR_ARGS=(--deployments "${@:-list}") ;;
        history) shift; _IGOR_OPERATOR_ARGS=(--history "${@:-recent}") ;;
        investigations) shift; _IGOR_OPERATOR_ARGS=(--investigations "${@:-list}") ;;
        config|configuration) shift; _IGOR_OPERATOR_ARGS=(--configuration "${@:-status}") ;;
        health)
            shift
            case "${1:-summary}" in
                summary) _IGOR_OPERATOR_ARGS=(--model summary) ;;
                inspect) shift; _IGOR_OPERATOR_ARGS=(--model health "${1:-}") ;;
                *) return 2 ;;
            esac ;;
        facts) shift; _IGOR_OPERATOR_ARGS=(--model facts "$@") ;;
        ask)
            [ "${IGOR_CLI_JSON}" != true ] || return 2
            shift; [ "$#" -ge 1 ] || return 2
            _prompt="$*"; _IGOR_OPERATOR_ARGS=(--ask-once-backend "$_prompt") ;;
        --*)
            [ "${IGOR_CLI_JSON}" != true ] || return 2
            _IGOR_OPERATOR_ARGS=("$@") ;;
        *)
            [ "${IGOR_CLI_JSON}" != true ] || return 2
            _prompt="$*"; _IGOR_OPERATOR_ARGS=(--ask-once-backend "$_prompt") ;;
    esac
}

igor_operator_default_frontend() {
    local _argc="${1:-0}" _stdin_tty="${2:-false}" _stdout_tty="${3:-false}" _classic="${4:-false}"
    if [ "$_argc" -eq 0 ] && [ "$_stdin_tty" = true ] && [ "$_stdout_tty" = true ] && [ "$_classic" != true ]; then
        printf 'tui\n'
    else
        printf 'existing\n'
    fi
}

# Render an owning-service result; presentation never supplies execution state.
igor_operator_cli_result() {
    printf '%s' "$1" | "${IGOR_PYTHON:-python3}" -c '
import json,sys
sys.path[:0] = [sys.argv[1]+"/core/ai", sys.argv[1]+"/core/lib"]
from capability_runtime import _validate_result
from interaction import display_text, render_structured
from privacy import scrub_data
try:
    result=json.load(sys.stdin)
    if "operation_id" in result:
        _validate_result(result)
        for key in ("result", "verification_evidence", "affected_objects", "recovery"):
            if key in result:
                result[key]=scrub_data(result[key])
        status=result["outcome"]
    else:
        status=result["status"]
        result=scrub_data(result)
    if sys.argv[2]=="true":
        print(json.dumps(result,ensure_ascii=False,allow_nan=False,separators=(",",":")))
    elif "operation_id" in result:
        print("Capability: "+display_text(result["capability_id"]))
        print("Outcome: "+display_text(status))
        print("Execution: %s · Output: %s · Verification: %s" % tuple(
            display_text(result.get(key,"not_applicable")) for key in
            ("execution_status","output_status","verification_status")))
        print("Provider: "+display_text(result.get("provider","unavailable")))
        print("Operation: "+display_text(result["operation_id"]))
        if result.get("result") is not None:
            print("\n".join(render_structured(result["result"],root_label="Result")))
        print("History: bash igor.sh history inspect "+display_text(result["operation_id"]))
    else:
        print("Request refused: "+display_text(status)+" — "+display_text(result.get("reason","")))
except (OSError,ValueError,TypeError,KeyError):
    print("{\"status\":\"result_unavailable\",\"interface\":\"cli\"}" if sys.argv[2]=="true"
          else "Result unavailable; inspect Operational History before retrying.")
    raise SystemExit(1) from None
raise SystemExit(0 if status=="success" else 3 if status=="approval_required" else
                 2 if status=="invalid_arguments" else 1)
' "$IGOR_DIR" "${IGOR_CLI_JSON:-false}"
}

igor_operator_cli_refuse() {
    local _result
    _result="$("${IGOR_PYTHON:-python3}" -c 'import json,sys
print(json.dumps(dict(status=sys.argv[1],capability_id=sys.argv[2],reason=sys.argv[3],interface="cli")))' \
        "$1" "$2" "$3")" || return 1
    igor_operator_cli_result "$_result"
}
