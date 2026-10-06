"""System-owned presentation of normalized Core S7 network reads.

This helper does not inspect the host. It receives only normalized Core rows and
turns them into System observer/capability envelopes.
"""

from __future__ import annotations

import json
import sys
from typing import Any

MAX_INTERFACES_TEXT = 4096
MAX_ROUTES_TEXT = 4096
MAX_WIFI_TEXT = 4096


class NetworkSurfaceError(ValueError):
    """Malformed normalized input or unsupported System presentation request."""


def _load() -> Any:
    try:
        return json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise NetworkSurfaceError("normalized network input is invalid") from exc


def _interfaces(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list) or len(value) > 128:
        raise NetworkSurfaceError("interface rows are invalid")
    required = {
        "object_id", "name", "ifindex", "operstate", "admin_up", "carrier",
        "mtu", "mac", "kind", "wireless", "ipv4_addresses", "ipv6_addresses",
        "default_route_v4", "default_route_v6",
    }
    for row in value:
        if not isinstance(row, dict) or set(row) != required:
            raise NetworkSurfaceError("interface row shape is invalid")
    return value


def _routes(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list) or len(value) > 512:
        raise NetworkSurfaceError("route rows are invalid")
    required = {
        "family", "destination", "gateway", "device", "preferred_source",
        "metric", "table", "protocol", "scope", "type",
    }
    for row in value:
        if not isinstance(row, dict) or set(row) != required:
            raise NetworkSurfaceError("route row shape is invalid")
    return value


def _dns(value: Any) -> dict[str, Any]:
    required = {
        "path", "symlink", "symlink_target", "resolved_path", "nameservers",
        "search_domains", "local_stub",
    }
    if not isinstance(value, dict) or set(value) != required:
        raise NetworkSurfaceError("resolver row shape is invalid")
    if not isinstance(value["nameservers"], list) or len(value["nameservers"]) > 16:
        raise NetworkSurfaceError("resolver nameservers are invalid")
    if not isinstance(value["search_domains"], list) or len(value["search_domains"]) > 32:
        raise NetworkSurfaceError("resolver search domains are invalid")
    return value



def _wifi_status(value: Any) -> dict[str, Any]:
    required = {"provider", "wifi_hardware", "wifi_radio", "devices"}
    if not isinstance(value, dict) or set(value) != required:
        raise NetworkSurfaceError("Wi-Fi status row shape is invalid")
    if value["provider"] != "NetworkManager":
        raise NetworkSurfaceError("Wi-Fi provider is invalid")
    for field in ("wifi_hardware", "wifi_radio"):
        if not isinstance(value[field], str) or len(value[field]) > 32:
            raise NetworkSurfaceError("Wi-Fi radio state is invalid")
    devices = value["devices"]
    if not isinstance(devices, list) or len(devices) > 32:
        raise NetworkSurfaceError("Wi-Fi device rows are invalid")
    for row in devices:
        if (
            not isinstance(row, dict)
            or set(row) != {"interface", "state", "connection"}
            or not all(isinstance(row[key], str) for key in row)
            or len(row["interface"]) > 32
            or len(row["state"]) > 64
            or len(row["connection"]) > 160
        ):
            raise NetworkSurfaceError("Wi-Fi device row shape is invalid")
    return value


def _wifi_scan(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list) or len(value) > 256:
        raise NetworkSurfaceError("Wi-Fi scan rows are invalid")
    required = {"active", "ssid", "bssid", "signal", "security", "device"}
    for row in value:
        if not isinstance(row, dict) or set(row) != required:
            raise NetworkSurfaceError("Wi-Fi scan row shape is invalid")
        if (
            type(row["active"]) is not bool
            or type(row["signal"]) is not int
            or not 0 <= row["signal"] <= 100
            or not isinstance(row["ssid"], str)
            or len(row["ssid"]) > 128
            or not isinstance(row["bssid"], str)
            or len(row["bssid"]) > 17
            or not isinstance(row["security"], str)
            or len(row["security"]) > 160
            or not isinstance(row["device"], str)
            or len(row["device"]) > 32
        ):
            raise NetworkSurfaceError("Wi-Fi scan row is invalid")
    return value


def _wifi_profiles(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list) or len(value) > 256:
        raise NetworkSurfaceError("Wi-Fi profile rows are invalid")
    required = {"name", "uuid", "type", "device", "active"}
    for row in value:
        if not isinstance(row, dict) or set(row) != required:
            raise NetworkSurfaceError("Wi-Fi profile row shape is invalid")
        if (
            row["type"] != "wifi"
            or type(row["active"]) is not bool
            or not isinstance(row["name"], str)
            or len(row["name"]) > 160
            or not isinstance(row["uuid"], str)
            or len(row["uuid"]) > 36
            or not isinstance(row["device"], str)
            or len(row["device"]) > 32
        ):
            raise NetworkSurfaceError("Wi-Fi profile row is invalid")
    return value

def observe_interfaces(value: Any) -> dict[str, Any]:
    rows = _interfaces(value)
    fields = {
        "interface.name": "name",
        "interface.ifindex": "ifindex",
        "interface.operstate": "operstate",
        "interface.admin_up": "admin_up",
        "interface.carrier": "carrier",
        "interface.mtu": "mtu",
        "interface.mac": "mac",
        "interface.kind": "kind",
        "interface.wireless": "wireless",
        "interface.ipv4_addresses": "ipv4_addresses",
        "interface.ipv6_addresses": "ipv6_addresses",
        "interface.default_route_v4": "default_route_v4",
        "interface.default_route_v6": "default_route_v6",
    }
    objects = []
    for row in rows:
        object_id = row["object_id"]
        evidence = [f"core.network.interfaces:{object_id}"]
        objects.append({
            "object_id": object_id,
            "facts": [
                {"property": prop, "value": row[field], "evidence": evidence}
                for prop, field in fields.items()
            ],
            "unavailable": [],
        })
    return {"status": "ok", "result": {"objects": objects}}


def summary(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {"interfaces", "routes", "dns"}:
        raise NetworkSurfaceError("network snapshot is invalid")
    interfaces = _interfaces(value["interfaces"])
    _routes(value["routes"])
    dns = _dns(value["dns"])
    default_v4 = sorted(
        row["name"] for row in interfaces if row["default_route_v4"]
    )
    default_v6 = sorted(
        row["name"] for row in interfaces if row["default_route_v6"]
    )
    return {
        "status": "ok",
        "result": {
            "interface_count": len(interfaces),
            "admin_up_count": sum(row["admin_up"] is True for row in interfaces),
            "carrier_count": sum(row["carrier"] is True for row in interfaces),
            "wireless_count": sum(row["wireless"] is True for row in interfaces),
            "default_route_v4": ",".join(default_v4)[:1024],
            "default_route_v6": ",".join(default_v6)[:1024],
            "resolver_count": len(dns["nameservers"]),
            "resolver_local_stub": dns["local_stub"],
            "source": "core.network",
        },
    }


def interfaces_list(value: Any) -> dict[str, Any]:
    rows = _interfaces(value)
    lines = []
    for row in rows:
        addresses = ",".join(
            item for item in (row["ipv4_addresses"], row["ipv6_addresses"]) if item
        ) or "no-address"
        flags = []
        if row["admin_up"]:
            flags.append("up")
        if row["carrier"]:
            flags.append("carrier")
        if row["wireless"]:
            flags.append("wireless")
        if row["default_route_v4"]:
            flags.append("default-v4")
        if row["default_route_v6"]:
            flags.append("default-v6")
        lines.append(
            f'{row["object_id"]}\t{row["name"]}\t{row["operstate"]}\t'
            f'{addresses}\t{",".join(flags) or "none"}'
        )
    return {
        "status": "ok",
        "result": {
            "count": len(rows),
            "interfaces": "\n".join(lines)[:MAX_INTERFACES_TEXT],
            "source": "core.network.interfaces",
        },
    }


def interface_status(value: Any, object_id: str) -> dict[str, Any]:
    rows = _interfaces(value)
    row = next((item for item in rows if item["object_id"] == object_id), None)
    if row is None:
        raise NetworkSurfaceError("interface object is not currently present")
    return {"status": "ok", "result": row}


def routes_list(value: Any) -> dict[str, Any]:
    rows = _routes(value)
    lines = []
    for row in rows:
        via = f' via {row["gateway"]}' if row["gateway"] else ""
        dev = f' dev {row["device"]}' if row["device"] else ""
        src = f' src {row["preferred_source"]}' if row["preferred_source"] else ""
        lines.append(
            f'{row["family"]}\t{row["destination"]}{via}{dev}{src}\t'
            f'metric={row["metric"]}\ttable={row["table"]}\t'
            f'protocol={row["protocol"]}\tscope={row["scope"]}\ttype={row["type"]}'
        )
    return {
        "status": "ok",
        "result": {
            "count": len(rows),
            "routes": "\n".join(lines)[:MAX_ROUTES_TEXT],
            "source": "core.network.routes",
        },
    }


def dns_status(value: Any) -> dict[str, Any]:
    row = _dns(value)
    return {
        "status": "ok",
        "result": {
            "nameserver_count": len(row["nameservers"]),
            "nameservers": ",".join(row["nameservers"])[:4096],
            "search_domains": ",".join(row["search_domains"])[:4096],
            "local_stub": row["local_stub"],
            "symlink": row["symlink"],
            "symlink_target": row["symlink_target"],
            "resolved_path": row["resolved_path"],
            "source": "core.network.dns",
        },
    }



def wifi_status(value: Any) -> dict[str, Any]:
    row = _wifi_status(value)
    lines = [
        f'{device["interface"]}\t{device["state"]}\t'
        f'{device["connection"] or "no-connection"}'
        for device in row["devices"]
    ]
    return {
        "status": "ok",
        "result": {
            "provider": row["provider"],
            "wifi_hardware": row["wifi_hardware"],
            "wifi_radio": row["wifi_radio"],
            "device_count": len(row["devices"]),
            "devices": "\n".join(lines)[:MAX_WIFI_TEXT],
            "source": "core.networkmanager.wifi.status",
        },
    }


def wifi_scan(value: Any) -> dict[str, Any]:
    rows = _wifi_scan(value)
    lines = []
    for row in rows:
        label = row["ssid"].strip() or "<hidden>"
        state = "active" if row["active"] else "seen"
        lines.append(
            f'{row["device"]}\t{label}\t{row["bssid"]}\t'
            f'signal={row["signal"]}\tsecurity={row["security"]}\t{state}'
        )
    return {
        "status": "ok",
        "result": {
            "count": len(rows),
            "networks": "\n".join(lines)[:MAX_WIFI_TEXT],
            "source": "core.networkmanager.wifi.scan",
        },
    }


def wifi_profiles_list(value: Any) -> dict[str, Any]:
    rows = _wifi_profiles(value)
    lines = []
    for row in rows:
        state = (
            f'active:{row["device"]}'
            if row["active"] and row["device"]
            else "inactive"
        )
        lines.append(f'{row["uuid"]}\t{row["name"]}\t{state}')
    return {
        "status": "ok",
        "result": {
            "count": len(rows),
            "profiles": "\n".join(lines)[:MAX_WIFI_TEXT],
            "source": "core.networkmanager.wifi.profiles",
        },
    }

def main(argv: list[str]) -> int:
    try:
        if len(argv) not in {2, 3}:
            raise NetworkSurfaceError("invalid network surface invocation")
        action = argv[1]
        value = _load()
        if action == "observe-interfaces" and len(argv) == 2:
            result = observe_interfaces(value)
        elif action == "summary" and len(argv) == 2:
            result = summary(value)
        elif action == "interfaces-list" and len(argv) == 2:
            result = interfaces_list(value)
        elif action == "interface-status" and len(argv) == 3:
            result = interface_status(value, argv[2])
        elif action == "routes-list" and len(argv) == 2:
            result = routes_list(value)
        elif action == "dns-status" and len(argv) == 2:
            result = dns_status(value)
        elif action == "wifi-status" and len(argv) == 2:
            result = wifi_status(value)
        elif action == "wifi-scan" and len(argv) == 2:
            result = wifi_scan(value)
        elif action == "wifi-profiles-list" and len(argv) == 2:
            result = wifi_profiles_list(value)
        else:
            raise NetworkSurfaceError("unsupported network surface action")
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 0
    except (NetworkSurfaceError, KeyError, TypeError, ValueError) as exc:
        print(f"system network surface: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
