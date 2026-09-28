#!/usr/bin/env bats

setup() {
    IGOR_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export IGOR_DIR
}

@test "module handler request is owner-bound, validated, and inactive owner is rejected" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        source "$IGOR_DIR/core/lib/module_handler.sh"
        _IGOR_LOADED_MODULES[system]=1
        _IGOR_MODULE_STATUS[system]=active
        igor_module_enabled() { return 0; }
        _ml_index_contribution domain_event:system.host.changed system fixture '\''{"id":"system.host.changed","owner":"system","payload_schema":{"properties":{"value":{"type":"integer"}},"required":["value"],"additionalProperties":false}}'\''
        _IGOR_DOMAIN_HANDLER_OWNER=system
        called() { printf callback > "$IGOR_DOMAIN_EVENT_FILE.called"; }
        igor_domain_event_subscribe called
        igor_domain_event_publish system.host.changed '\''{"payload":{"value":"bad"}}'\'' >/dev/null 2>&1 && exit 5
        [ ! -e "$IGOR_DOMAIN_EVENT_FILE.called" ] || exit 6
        [ "$(igor_domain_event_recent)" = "[]" ] || exit 7
        fixture="$(mktemp -d)"
        cat > "$fixture/module.sh" <<'\''EOF'\''
system__event_test() {
    igor_domain_event_publish system.host.changed '\''{"payload":{"value":"bad"}}'\'' >/dev/null 2>&1 && return 11
    igor_domain_event_publish system.host.changed '\''{"payload":{"value":3}}'\''
    [ -f "$IGOR_DOMAIN_EVENT_FILE.called" ] || return 12
    [ "$(python3 "$_IGOR_LOADER_DIR/core/lib/domain_event.py" inspect "$IGOR_DOMAIN_EVENT_FILE" '\''{}'\'')" != '\''[]'\'' ] || return 13
    printf '\''{"status":"ok","result":{}}\n'\''
}
EOF
        _ml_bash_handler_invoke "$fixture" system system__event_test system.host.changed 5
        igor_domain_event_recent
        _IGOR_MODULE_STATUS[system]=disabled
        _IGOR_DOMAIN_HANDLER_OWNER=system
        igor_domain_event_publish system.host.changed '\''{"payload":{"value":4}}'\'' && exit 3
        igor_domain_event_types
        igor_domain_event_recent
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'"source":"module:system"'* ]]
    [[ "$output" == *'"value":3'* ]]
    [[ "$output" == *'"availability":"inactive"'* ]]
    [[ "$output" != *'"value":4'* ]]
}

@test "fresh session has empty buffer and frontend stream stays separate" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        [ "$(igor_domain_event_recent)" = "[]" ] || exit 2
        source "$IGOR_DIR/core/ai/events.sh"
        [ -n "$IGOR_DOMAIN_EVENT_FILE" ] || exit 3
        [ "$IGOR_DOMAIN_EVENT_FILE" != "${IGOR_AI_EVENT_STREAM:-}" ] || exit 4
        [ "$(igor_domain_event_recent)" = "[]" ]
    '
    [ "$status" -eq 0 ]
}

@test "inspection does not invoke observation, capability, check, or privilege" {
    run bash -c '
        source "$IGOR_DIR/core/lib/module_loader.sh"
        marker="$(mktemp)"
        igor_observer_refresh() { printf observer >> "$marker"; }
        igor_capability_execute() { printf capability >> "$marker"; }
        igor_health_run_v2_check() { printf check >> "$marker"; }
        sudo() { printf privilege >> "$marker"; }
        igor_domain_event_types >/dev/null
        igor_domain_event_recent '\''{"event_type":"capability.completed","owner":"system","object_id":"host:local"}'\'' >/dev/null
        [ ! -s "$marker" ]
    '
    [ "$status" -eq 0 ]
}
