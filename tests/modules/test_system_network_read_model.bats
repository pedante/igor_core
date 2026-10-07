#!/usr/bin/env bats

load '../helpers/common'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_DATA_DIR="$IGOR_DIR/data"
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config" "$IGOR_DIR/bin"
    cp -a "$REPO_DIR/modules/system" "$IGOR_DIR/modules/system"
    printf 'system=enabled\n' > "$IGOR_DIR/config/modules.conf"

    cat > "$IGOR_DIR/bin/ip" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    "-j -4 route show table all")
        printf '%s\n' '[{"dst":"default","gateway":"192.0.2.1","dev":"eth0","protocol":"dhcp","metric":100},{"dst":"192.0.2.0/24","dev":"eth0","prefsrc":"192.0.2.10","protocol":"kernel","scope":"link"}]'
        ;;
    "-j -6 route show table all")
        printf '%s\n' '[]'
        ;;
    "-j -d address show")
        printf '%s\n' '[{"ifindex":1,"ifname":"lo","flags":["LOOPBACK","UP","LOWER_UP"],"mtu":65536,"operstate":"UNKNOWN","link_type":"loopback","address":"00:00:00:00:00:00","addr_info":[{"family":"inet","local":"127.0.0.1","prefixlen":8}]},{"ifindex":2,"ifname":"eth0","flags":["BROADCAST","MULTICAST","UP","LOWER_UP"],"mtu":1500,"operstate":"UP","link_type":"ether","address":"02:00:00:00:00:01","addr_info":[{"family":"inet","local":"192.0.2.10","prefixlen":24}]}]'
        ;;
    *)
        printf 'unexpected ip args: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF
    chmod +x "$IGOR_DIR/bin/ip"

    cat > "$IGOR_DIR/bin/nmcli" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    "--terse --escape yes --fields WIFI-HW,WIFI general status")
        printf '%s\n' 'enabled:enabled'
        ;;
    "--terse --escape yes --fields DEVICE,TYPE,STATE,CONNECTION device status")
        printf '%s\n' 'wlan0:wifi:connected:Home'
        printf '%s\n' 'eth0:ethernet:connected:Wired'
        ;;
    "--terse --escape yes --fields IN-USE,SSID,BSSID,SIGNAL,SECURITY,DEVICE device wifi list --rescan auto")
        printf '%s\n' '*:Home:AA\:BB\:CC\:DD\:EE\:FF:78:WPA2:wlan0'
        printf '%s\n' ':Guest:11\:22\:33\:44\:55\:66:35:--:wlan0'
        ;;
    "--terse --escape yes --fields NAME,UUID,TYPE,DEVICE connection show")
        printf '%s\n' 'Home:123e4567-e89b-12d3-a456-426614174000:802-11-wireless:wlan0'
        printf '%s\n' 'Wired:123e4567-e89b-12d3-a456-426614174001:802-3-ethernet:eth0'
        ;;
    *)
        printf 'unexpected nmcli args: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF
    chmod +x "$IGOR_DIR/bin/nmcli"
    export PATH="$IGOR_DIR/bin:$PATH"

    source "$REPO_DIR/core/lib/module_loader.sh"
    _ml_log() { :; }
    igor_load_all_modules >/dev/null
}

teardown() { teardown_igor_tmpdir; }

@test "S7.2 network contracts are active read-only System contributions" {
    records="$(igor_contribution_records)"
    python3 - "$records" <<'PY'
import json
import sys

rows = json.loads(sys.argv[1])
by_id = {row["id"]: row for row in rows}
observer = by_id["network.interfaces"]
assert observer["kind"] == "observer"
assert observer["descriptor"]["object_kind"] == "interface"
assert observer["descriptor"]["freshness_seconds"] == 30
assert observer["descriptor"]["requires"] == {"bins": ["ip"]}

for ident in (
    "system.network.summary",
    "system.network.interfaces.list",
    "system.network.interface.status",
    "system.network.routes.list",
    "system.network.dns.status",
):
    row = by_id[ident]
    assert row["kind"] == "capability"
    assert row["descriptor"]["safety"] == {"tier": "READ"}
    assert row["descriptor"]["privilege"] == "none"

assert by_id["system.network.interface.status"]["descriptor"]["inputs"]["properties"]["interface"]["selector"] == {
    "schema_version": 1,
    "kind": "resource",
    "resource_kind": "interface",
}
assert "requires" not in by_id["system.network.dns.status"]["descriptor"]
PY
}

@test "network interface observer populates canonical interface System Model facts" {
    run igor_observer_refresh network.interfaces
    [ "$status" -eq 0 ]

    run igor_model_read interface:eth0 interface.name observed
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"known"'* ]]
    [[ "$output" == *'"owner":"system"'* ]]
    [[ "$output" == *'"observer":"network.interfaces"'* ]]
    [[ "$output" == *'"value":"eth0"'* ]]

    run igor_model_read interface:eth0 interface.default_route_v4 observed
    [ "$status" -eq 0 ]
    [[ "$output" == *'"value":true'* ]]
}

@test "disabled System owner cannot refresh or present prior interface facts as current" {
    igor_observer_refresh network.interfaces >/dev/null
    _IGOR_MODULE_STATUS["system"]=disabled

    run igor_observer_refresh network.interfaces
    [ "$status" -ne 0 ]

    run igor_model_read interface:eth0 interface.name observed
    [ "$status" -eq 0 ]
    [[ "$output" == *'"availability":"inactive"'* ]]
}

@test "network read handlers consume only normalized Core rows" {
    run bash -c '
        source "$1/modules/system/module.sh"
        _mod_sys_network_read() {
            case "$1" in
                interfaces)
                    printf "%s\n" '\''[
                      {"object_id":"interface:eth0","name":"eth0","ifindex":2,"operstate":"up",
                       "admin_up":true,"carrier":true,"mtu":1500,"mac":"02:00:00:00:00:01",
                       "kind":"ether","wireless":false,"ipv4_addresses":"192.0.2.10/24",
                       "ipv6_addresses":"","default_route_v4":true,"default_route_v6":false},
                      {"object_id":"interface:wlan0","name":"wlan0","ifindex":3,"operstate":"down",
                       "admin_up":false,"carrier":false,"mtu":1500,"mac":"02:00:00:00:00:02",
                       "kind":"ether","wireless":true,"ipv4_addresses":"","ipv6_addresses":"",
                       "default_route_v4":false,"default_route_v6":false}
                    ]'\''
                    ;;
                routes)
                    printf "%s\n" '\''[
                      {"family":"ipv4","destination":"default","gateway":"192.0.2.1","device":"eth0",
                       "preferred_source":"","metric":100,"table":"main","protocol":"dhcp","scope":"","type":"unicast"}
                    ]'\''
                    ;;
                dns)
                    printf "%s\n" '\''{
                      "path":"/etc/resolv.conf","symlink":true,
                      "symlink_target":"../run/systemd/resolve/stub-resolv.conf",
                      "resolved_path":"/run/systemd/resolve/stub-resolv.conf",
                      "nameservers":["127.0.0.53"],"search_domains":["example.org"],"local_stub":true
                    }'\''
                    ;;
                snapshot)
                    printf "%s\n" '\''{
                      "interfaces":[
                        {"object_id":"interface:eth0","name":"eth0","ifindex":2,"operstate":"up",
                         "admin_up":true,"carrier":true,"mtu":1500,"mac":"02:00:00:00:00:01",
                         "kind":"ether","wireless":false,"ipv4_addresses":"192.0.2.10/24",
                         "ipv6_addresses":"","default_route_v4":true,"default_route_v6":false},
                        {"object_id":"interface:wlan0","name":"wlan0","ifindex":3,"operstate":"down",
                         "admin_up":false,"carrier":false,"mtu":1500,"mac":"02:00:00:00:00:02",
                         "kind":"ether","wireless":true,"ipv4_addresses":"","ipv6_addresses":"",
                         "default_route_v4":false,"default_route_v6":false}
                      ],
                      "routes":[
                        {"family":"ipv4","destination":"default","gateway":"192.0.2.1","device":"eth0",
                         "preferred_source":"","metric":100,"table":"main","protocol":"dhcp","scope":"","type":"unicast"}
                      ],
                      "dns":{
                        "path":"/etc/resolv.conf","symlink":true,
                        "symlink_target":"../run/systemd/resolve/stub-resolv.conf",
                        "resolved_path":"/run/systemd/resolve/stub-resolv.conf",
                        "nameservers":["127.0.0.53"],"search_domains":["example.org"],"local_stub":true
                      }
                    }'\''
                    ;;
            esac
        }

        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.network.summary","input":{}}'\'' |
            system__network_summary
        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.network.interfaces.list","input":{}}'\'' |
            system__network_interfaces_list
        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.network.interface.status","input":{"interface":"interface:eth0"}}'\'' |
            system__network_interface_status
        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.network.routes.list","input":{}}'\'' |
            system__network_routes_list
        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.network.dns.status","input":{}}'\'' |
            system__network_dns_status
        printf "%s\n" '\''{"api_version":2,"contribution_id":"network.interfaces","input":{}}'\'' |
            system__observe_interfaces
    ' _ "$REPO_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"interface_count":2'* ]]
    [[ "$output" == *'"wireless_count":1'* ]]
    [[ "$output" == *'"default_route_v4":"eth0"'* ]]
    [[ "$output" == *'"object_id":"interface:eth0"'* ]]
    [[ "$output" == *'192.0.2.1'* ]]
    [[ "$output" == *'"source":"core.network.routes"'* ]]
    [[ "$output" == *'"local_stub":true'* ]]
    [[ "$output" == *'"property":"interface.name","value":"eth0"'* ]]
}

@test "interface status preparation keeps the selected canonical affected object" {
    run igor_capability_prepare         system.network.interface.status '{"interface":"interface:eth0"}' system 2
    [ "$status" -eq 0 ]
    [[ "$output" == *'"affected_objects":["interface:eth0"]'* ]]
}

@test "interface selector falls back to bounded Core candidates before observation" {
    source "$REPO_DIR/core/lib/input_candidates.sh"

    run igor_input_candidates_resolve system.network.interface.status interface
    [ "$status" -eq 0 ]
    [[ "$output" == *'"kind":"platform"'* ]]
    [[ "$output" == *'"id":"linux.interfaces"'* ]]
    [[ "$output" == *'"value":"interface:eth0"'* ]]
    [[ "$output" == *'"label":"eth0"'* ]]
    [[ "$output" == *'192.0.2.10/24'* ]]
}

@test "fresh interface model candidates win over a failing platform fallback" {
    igor_observer_refresh network.interfaces >/dev/null
    source "$REPO_DIR/core/lib/input_candidates.sh"
    _igor_interface_platform_candidate_raw() {
        printf 'PLATFORM_SHOULD_NOT_RUN\n' >&2
        return 1
    }

    run igor_input_candidates_resolve system.network.interface.status interface
    [ "$status" -eq 0 ]
    [[ "$output" == *'"kind":"system_model"'* ]]
    [[ "$output" == *'"value":"interface:eth0"'* ]]
    [[ "$output" != *'PLATFORM_SHOULD_NOT_RUN'* ]]
}

@test "missing ip disables only ip-backed network contributions" {
    local empty_path="$IGOR_DIR/no-ip"
    mkdir -p "$empty_path"

    [ "$(igor_module_status system)" = active ]

    [ "$(PATH="$empty_path" igor_contribution_state capability:system.network.summary)" = unavailable ]
    [[ "$(PATH="$empty_path" igor_contribution_reason capability:system.network.summary)" == *"required binary ip is missing"* ]]
    [ "$(PATH="$empty_path" igor_contribution_state observer:network.interfaces)" = unavailable ]
    [ "$(PATH="$empty_path" igor_contribution_state capability:system.network.dns.status)" = active ]

    [ "$(igor_module_status system)" = active ]
}

@test "S7.2 network read surface never invokes Wi-Fi or privileged mutation tools" {
    run bash -c '
        source "$1/modules/system/module.sh"
        nmcli() { printf "MUTATION_CALLED\n"; return 99; }
        sudo() { printf "MUTATION_CALLED\n"; return 99; }
        ping() { printf "MUTATION_CALLED\n"; return 99; }
        _mod_sys_network_read() {
            case "$1" in
                interfaces) printf "%s\n" "[]" ;;
                routes) printf "%s\n" "[]" ;;
                dns)
                    printf "%s\n" '\''{"path":"/etc/resolv.conf","symlink":false,"symlink_target":"",
                      "resolved_path":"/etc/resolv.conf","nameservers":[],"search_domains":[],"local_stub":false}'\''
                    ;;
                snapshot)
                    printf "%s\n" '\''{"interfaces":[],"routes":[],"dns":{"path":"/etc/resolv.conf",
                      "symlink":false,"symlink_target":"","resolved_path":"/etc/resolv.conf",
                      "nameservers":[],"search_domains":[],"local_stub":false}}'\''
                    ;;
            esac
        }
        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.network.summary","input":{}}'\'' |
            system__network_summary
    ' _ "$REPO_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *MUTATION_CALLED* ]]
    [[ "$output" == *'"interface_count":0'* ]]
}


@test "S7.3 NetworkManager contributions are optional read-only leaves" {
    records="$(igor_contribution_records)"
    python3 - "$records" <<'PY'
import json
import sys
rows = json.loads(sys.argv[1])
by_id = {row["id"]: row for row in rows}
for ident in (
    "system.network.wifi.status",
    "system.network.wifi.scan",
    "system.network.wifi.profiles.list",
):
    row = by_id[ident]
    assert row["kind"] == "capability"
    assert row["descriptor"]["safety"] == {"tier": "READ"}
    assert row["descriptor"]["privilege"] == "none"
    assert row["descriptor"]["requires"] == {"bins": ["nmcli"]}
    assert row["descriptor"]["inputs"] == {
        "properties": {}, "required": [], "additionalProperties": False,
    }
PY
}

@test "S7.3 Wi-Fi read handlers normalize status scan and saved profile references" {
    run bash -c '
        export _IGOR_LOADER_DIR="$1"
        source "$1/modules/system/module.sh"
        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.network.wifi.status","input":{}}'\'' |
            system__network_wifi_status
        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.network.wifi.scan","input":{}}'\'' |
            system__network_wifi_scan
        printf "%s\n" '\''{"api_version":2,"contribution_id":"system.network.wifi.profiles.list","input":{}}'\'' |
            system__network_wifi_profiles_list
    ' _ "$REPO_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"provider":"NetworkManager"'* ]]
    [[ "$output" == *'"wifi_radio":"enabled"'* ]]
    [[ "$output" == *'AA:BB:CC:DD:EE:FF'* ]]
    [[ "$output" == *'signal=78'* ]]
    [[ "$output" == *'123e4567-e89b-12d3-a456-426614174000'* ]]
    [[ "$output" != *'password'* ]]
    [[ "$output" != *'psk'* ]]
    [[ "$output" != *'secret'* ]]
}

@test "S7.3 candidate sources are bounded ephemeral non-secret references" {
    source "$REPO_DIR/core/lib/input_candidates.sh"
    _igor_input_candidate_spec() {
        case "$3" in
            network)
                printf '%s\n' system string '{"schema_version":1,"kind":"resource","resource_kind":"wifi_network"}' wifi_network
                ;;
            profile)
                printf '%s\n' system string '{"schema_version":1,"kind":"resource","resource_kind":"wifi_profile"}' wifi_profile
                ;;
            *) return 2 ;;
        esac
    }

    run igor_input_candidates_resolve fixture.select network
    [ "$status" -eq 0 ]
    [[ "$output" == *'"id":"networkmanager.wifi.scan"'* ]]
    [[ "$output" == *'"value":"AA:BB:CC:DD:EE:FF"'* ]]
    [[ "$output" == *'"label":"Home"'* ]]
    [[ "$output" != *'password'* ]]
    [[ "$output" != *'psk'* ]]
    python3 - "$output" <<'PY'
import json
import sys
row = json.loads(sys.argv[1])["result"]["candidates"][0]
assert len(row.get("detail", "")) <= 512
assert "object_id" not in row
PY

    run igor_input_candidates_resolve fixture.select profile
    [ "$status" -eq 0 ]
    [[ "$output" == *'"id":"networkmanager.wifi.profiles"'* ]]
    [[ "$output" == *'"value":"123e4567-e89b-12d3-a456-426614174000"'* ]]
    [[ "$output" == *'"label":"Home"'* ]]
    [[ "$output" != *'object_id'* ]]
}

@test "missing nmcli disables only Wi-Fi contributions and leaves generic network active" {
    local providerless="$IGOR_DIR/providerless"
    mkdir -p "$providerless"
    ln -s "$IGOR_DIR/bin/ip" "$providerless/ip"

    [ "$(igor_module_status system)" = active ]
    [ "$(PATH="$providerless" igor_contribution_state capability:system.network.wifi.status)" = unavailable ]
    [[ "$(PATH="$providerless" igor_contribution_reason capability:system.network.wifi.status)" == *"required binary nmcli is missing"* ]]
    [ "$(PATH="$providerless" igor_contribution_state capability:system.network.wifi.scan)" = unavailable ]
    [ "$(PATH="$providerless" igor_contribution_state capability:system.network.wifi.profiles.list)" = unavailable ]

    [ "$(PATH="$providerless" igor_contribution_state capability:system.network.summary)" = active ]
    [ "$(PATH="$providerless" igor_contribution_state capability:system.network.interfaces.list)" = active ]
    [ "$(PATH="$providerless" igor_contribution_state capability:system.network.routes.list)" = active ]
    [ "$(PATH="$providerless" igor_contribution_state capability:system.network.dns.status)" = active ]
    [ "$(igor_module_status system)" = active ]
}

@test "inactive System owner cannot prepare S7.3 Wi-Fi reads" {
    _IGOR_MODULE_STATUS["system"]=disabled
    run igor_capability_prepare system.network.wifi.status '{}' system 2
    [ "$status" -ne 0 ]
}

@test "S7.3 Wi-Fi reads stay READ while S7.4 is the sole reviewed Wi-Fi mutation" {
    records="$(igor_contribution_records)"
    python3 - "$records" <<'PY'
import json
import sys
rows = json.loads(sys.argv[1])
by_id = {row["id"]: row for row in rows}
for ident in (
    "system.network.wifi.status",
    "system.network.wifi.scan",
    "system.network.wifi.profiles.list",
):
    assert by_id[ident]["descriptor"]["safety"] == {"tier": "READ"}
    assert by_id[ident]["descriptor"]["privilege"] == "none"
mutation = by_id["system.network.wifi.connect_known"]["descriptor"]
assert mutation["safety"] == {"tier": "CHANGE"}
assert mutation["privilege"] == "required"
assert mutation["handler"] == "system__privileged_marker"
assert not any(
    row["id"].startswith("system.network.wifi.")
    and row["descriptor"].get("safety", {}).get("tier") != "READ"
    and row["id"] != "system.network.wifi.connect_known"
    for row in rows
)
PY
}


@test "S7.5 Debian and Arch fixtures preserve generic and optional provider reads" {
    local family
    for family in debian arch; do
        run env IGOR_DISTRO_FAMILY="$family" IGOR_DISTRO_ID="$family" \
            _IGOR_LOADER_DIR="$REPO_DIR" PATH="$PATH" bash -c '
                source "$1/modules/system/module.sh"
                printf "%s\n" '\''{"api_version":2,"contribution_id":"system.network.interfaces.list","input":{}}'\'' |
                    system__network_interfaces_list
                printf "%s\n" '\''{"api_version":2,"contribution_id":"system.network.wifi.status","input":{}}'\'' |
                    system__network_wifi_status
            ' _ "$REPO_DIR"
        [ "$status" -eq 0 ]
        [[ "$output" == *'"source":"core.network.interfaces"'* ]]
        [[ "$output" == *'"provider":"NetworkManager"'* ]]
        [[ "$output" == *'"source":"networkmanager.wifi.status"'* ]]
    done
}
