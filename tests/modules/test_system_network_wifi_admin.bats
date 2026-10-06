#!/usr/bin/env bats

load '../helpers/common'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."
PROFILE_UUID="123e4567-e89b-12d3-a456-426614174000"

setup() {
    setup_igor_tmpdir
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config" "$IGOR_DIR/bin" "$IGOR_DIR/runtime"
    cp -a "$REPO_DIR/modules/system" "$IGOR_DIR/modules/system"
    printf 'system=enabled\n' > "$IGOR_DIR/config/modules.conf"

    export WIFI_ACTIVE_STATE="$IGOR_DIR/runtime/wifi-active"
    export WIFI_SUDO_TRACE="$IGOR_DIR/runtime/sudo-trace"
    export WIFI_MUTATION_TRACE="$IGOR_DIR/runtime/wifi-mutation-trace"
    : > "$WIFI_SUDO_TRACE"
    : > "$WIFI_MUTATION_TRACE"

    cat > "$IGOR_DIR/bin/nmcli" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    "--terse --escape yes --fields WIFI-HW,WIFI general status")
        printf '%s\n' 'enabled:enabled'
        ;;
    "--terse --escape yes --fields DEVICE,TYPE,STATE,CONNECTION device status")
        printf '%s\n' 'wlan0:wifi:disconnected:--'
        ;;
    "--terse --escape yes --fields NAME,UUID,TYPE,DEVICE connection show")
        if [ "${WIFI_HIDE_PROFILE:-0}" = 1 ]; then
            exit 0
        elif [ "${WIFI_PROFILE_OTHER_INTERFACE:-0}" = 1 ]; then
            printf '%s\n' 'Home:123e4567-e89b-12d3-a456-426614174000:802-11-wireless:wlan1'
        elif [ -e "$WIFI_ACTIVE_STATE" ]; then
            printf '%s\n' 'Home:123e4567-e89b-12d3-a456-426614174000:802-11-wireless:wlan0'
        else
            printf '%s\n' 'Home:123e4567-e89b-12d3-a456-426614174000:802-11-wireless:--'
        fi
        ;;
    "--wait 30 connection up uuid 123e4567-e89b-12d3-a456-426614174000 ifname wlan0")
        printf '%s\n' "$*" >> "$WIFI_MUTATION_TRACE"
        [ "${WIFI_SKIP_ACTIVATION_STATE:-0}" = 1 ] || : > "$WIFI_ACTIVE_STATE"
        ;;
    *)
        printf 'unexpected nmcli args: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF
    cat > "$IGOR_DIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$WIFI_SUDO_TRACE"
[ "$1" = -n ] && [ "$2" = -- ] || exit 2
shift 2
exec "$@"
EOF
    chmod +x "$IGOR_DIR/bin/nmcli" "$IGOR_DIR/bin/sudo"
    export PATH="$IGOR_DIR/bin:$PATH"

    source "$REPO_DIR/core/lib/module_loader.sh"
    _ml_log() { :; }
    igor_load_all_modules >/dev/null
}

teardown() { teardown_igor_tmpdir; }

_approve_and_execute() {
    local proposal="$1"
    IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
    IGOR_CAPABILITY_APPROVAL_STATUS=approved
    IGOR_CAPABILITY_PRIVILEGE_STATUS=authenticated
    export IGOR_CAPABILITY_APPROVED_DIGEST IGOR_CAPABILITY_APPROVAL_STATUS
    export IGOR_CAPABILITY_PRIVILEGE_STATUS
    igor_capability_execute "$proposal"
}

@test "S7.4 declares only reviewed known-profile activation as CHANGE" {
    local key="capability:system.network.wifi.connect_known" raw
    raw="${_IGOR_CONTRIBUTIONS[$key]:-}"
    printf '# state=%s reason=%s owner=%s id=%s handler=%s version=%s privilege=%s\n' \
        "$(igor_contribution_state "$key")" \
        "$(igor_contribution_reason "$key")" \
        "${_IGOR_CONTRIBUTION_OWNER[$key]:-}" \
        "$(_ml_json_field "$raw" id)" \
        "$(_ml_json_field "$raw" handler)" \
        "$(_ml_json_field "$raw" capability_version)" \
        "$(_ml_json_field "$raw" privilege)" >&3
    cap="$(igor_capability_inspect system.network.wifi.connect_known system)"
    python3 - "$cap" <<'PY'
import json,sys
cap=json.loads(sys.argv[1])
assert cap["resolution"]=="resolved"
d=cap["descriptor"]
assert d["handler"]=="system__privileged_marker"
assert d["safety"]=={"tier":"CHANGE"}
assert d["privilege"]=="required"
assert d["requires"]=={"bins":["nmcli"]}
assert d["preconditions"][-1]=={
    "kind":"trusted_validator",
    "validator":"system.network.wifi.connect_known.ready",
}
assert d["verification"]=={
    "kind":"trusted_query",
    "check_id":"system.network.wifi.profile.active",
    "required":True,
}
props=d["inputs"]["properties"]
assert props["interface"]["selector"]["resource_kind"]=="interface"
assert props["profile"]["selector"]["resource_kind"]=="wifi_profile"
assert all(spec["type"]!="secret_ref" for spec in props.values())
PY
}

@test "S7.4 prepare freezes exact NetworkManager activation argv without execution" {
    run igor_capability_prepare system.network.wifi.connect_known         "$(printf '{"interface":"interface:wlan0","profile":"%s"}' "$PROFILE_UUID")" system 1
    [ "$status" -eq 0 ]
    [[ "$output" == *'"precondition_status":"satisfied"'* ]]
    [[ "$output" == *'"privileged_argv":[["sudo","-n","--","nmcli","--wait","30","connection","up","uuid","123e4567-e89b-12d3-a456-426614174000","ifname","wlan0"]]'* ]]
    [ ! -s "$WIFI_SUDO_TRACE" ]
    [ ! -s "$WIFI_MUTATION_TRACE" ]
}

@test "S7.4 executes exact approved argv and verifies the selected profile on the interface" {
    proposal="$(igor_capability_prepare system.network.wifi.connect_known         "$(printf '{"interface":"interface:wlan0","profile":"%s"}' "$PROFILE_UUID")" system 1)"
    run _approve_and_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"execution_status":"succeeded"'* ]]
    [[ "$output" == *'"verification_status":"passed"'* ]]
    [[ "$output" == *'"outcome":"success"'* ]]
    [[ "$output" == *'"check_id":"system.network.wifi.profile.active"'* ]]
    [ "$(tail -n 1 "$WIFI_SUDO_TRACE")" = 'sudo -n -- nmcli --wait 30 connection up uuid 123e4567-e89b-12d3-a456-426614174000 ifname wlan0' ]
    [ "$(tail -n 1 "$WIFI_MUTATION_TRACE")" = '--wait 30 connection up uuid 123e4567-e89b-12d3-a456-426614174000 ifname wlan0' ]
}

@test "execution fence rejects a saved profile that disappears after approval" {
    proposal="$(igor_capability_prepare system.network.wifi.connect_known         "$(printf '{"interface":"interface:wlan0","profile":"%s"}' "$PROFILE_UUID")" system 1)"
    export WIFI_HIDE_PROFILE=1
    run _approve_and_execute "$proposal"
    [ "$status" -ne 0 ]
    [ ! -s "$WIFI_SUDO_TRACE" ]
    [ ! -s "$WIFI_MUTATION_TRACE" ]
}

@test "zero-exit activation is unverified when the profile is not active afterward" {
    proposal="$(igor_capability_prepare system.network.wifi.connect_known         "$(printf '{"interface":"interface:wlan0","profile":"%s"}' "$PROFILE_UUID")" system 1)"
    export WIFI_SKIP_ACTIVATION_STATE=1
    run _approve_and_execute "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"execution_status":"succeeded"'* ]]
    [[ "$output" == *'"verification_status":"failed"'* ]]
    [[ "$output" == *'"outcome":"unverified_change"'* ]]
    [ -s "$WIFI_SUDO_TRACE" ]
}

@test "preflight refuses a profile already active on another interface" {
    export WIFI_PROFILE_OTHER_INTERFACE=1
    run igor_capability_prepare system.network.wifi.connect_known         "$(printf '{"interface":"interface:wlan0","profile":"%s"}' "$PROFILE_UUID")" system 1
    [ "$status" -ne 0 ]
    [ ! -s "$WIFI_SUDO_TRACE" ]
}
