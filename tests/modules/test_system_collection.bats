#!/usr/bin/env bats

load '../helpers/common'
load '../helpers/system_admin'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

@test "service inventory and status use the shared systemd platform abstraction" {
    run --separate-stderr _execute_read system.service.list '{}'
    [ "$status" -eq 0 ]
    python3 - "$output" <<'PYOUT'
import json,sys
r=json.loads(sys.argv[1])
assert r["capability_version"]==3 and r["output_status"]=="valid"
assert r["result"]["inventory"]=="loaded_system_services"
assert [(x["unit"],x["active_state"],x["sub_state"]) for x in r["result"]["rows"]]==[
    ("cron.service","active","running"),("ssh.service","inactive","dead")]
assert r["result"]["page"]["total_count"]==2
PYOUT

    run _execute_read system.service.status '{"unit":"cron.service"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"unit":"cron.service"'* ]]
    [[ "$output" == *'"state":"active"'* ]]

    run igor_capability_prepare system.service.status '{"unit":"bad unit;reboot"}' system 2
    [ "$status" -ne 0 ]
}

@test "service-list provider bridge metadata is compiled at module load" {
    [ "${_IGOR_HANDLER_FUNCTION[capability:system.service.list]:-}" = system__service_list ]
    [ "${_IGOR_HANDLER_TIMEOUT[capability:system.service.list]:-}" = 30 ]
    [ "${_IGOR_MODULE_ENTRYPOINT[system]:-}" = module.sh ]
    [ "${_IGOR_OWNER_HAS_DOMAIN_EVENTS[system]:-0}" = 0 ]
    [ "${_IGOR_MODULE_VERSION[system]:-}" = 2.11.0 ]
}

@test "targeted preparation evaluates only the selected capability requirement path" {
    local trace="$IGOR_DIR/runtime/dynamic-requirements"
    : > "$trace"
    eval "$(declare -f _ml_contribution_dynamic_failure | sed '1s/_ml_contribution_dynamic_failure/_original_dynamic_failure/')"
    _ml_contribution_dynamic_failure() {
        printf '%s\n' "$1" >> "$trace"
        _original_dynamic_failure "$@"
    }

    run igor_capability_prepare system.service.list '{}' system 3
    [ "$status" -eq 0 ]
    [ "$(cat "$trace")" = "capability:system.service.list" ]
}

@test "service-list prepare stays below a bounded Python process budget" {
    local real_python counter wrapper count
    real_python="$(command -v python3)"
    counter="$IGOR_DIR/runtime/python-invocations"
    wrapper="$IGOR_DIR/bin/counting-python"
    : > "$counter"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
printf '.\n' >> "$counter"
exec "$real_python" "\$@"
EOF
    chmod +x "$wrapper"
    export IGOR_PYTHON="$wrapper"

    run igor_capability_prepare system.service.list '{}' system 3
    [ "$status" -eq 0 ]
    count="$(wc -l < "$counter")"
    [ "$count" -le 6 ]
}


@test "service-list resolution closure is precompiled without Python" {
    local real_python counter wrapper
    real_python="$(command -v python3)"
    counter="$IGOR_DIR/runtime/resolution-python-invocations"
    wrapper="$IGOR_DIR/bin/resolution-counting-python"
    : > "$counter"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
printf '.\n' >> "$counter"
exec "$real_python" "\$@"
EOF
    chmod +x "$wrapper"
    export IGOR_PYTHON="$wrapper"

    run _ml_capability_resolution_ids system.service.list
    [ "$status" -eq 0 ]
    [ "$output" = system.service.list ]
    [ ! -s "$counter" ]
}

@test "execution fence evaluates current preconditions exactly once" {
    local proposal trace
    proposal="$(igor_capability_prepare system.service.list '{}' system 3)"
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    IGOR_CAPABILITY_APPROVAL_STATUS=approved
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    trace="$IGOR_DIR/runtime/precondition-calls"
    : > "$trace"
    eval "$(declare -f _igor_capability_preconditions | sed '1s/_igor_capability_preconditions/_original_capability_preconditions/')"
    _igor_capability_preconditions() {
        printf '.\n' >> "$trace"
        _original_capability_preconditions "$@"
    }

    run igor_capability_execute "$proposal"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$trace")" -eq 1 ]
}

@test "log summary is bounded metadata and never persists raw journal messages" {
    run _execute_read system.logs.summary '{}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"source":"systemd.journal"'* ]]
    [[ "$output" == *'"recent_count":2'* ]]
    [[ "$output" != *'boot ok'* ]]
    [[ "$output" != *'service ready'* ]]
    history="$(igor_history_cli recent 1)"
    [[ "$history" != *'boot ok'* ]]
    [[ "$history" != *'service ready'* ]]
}
