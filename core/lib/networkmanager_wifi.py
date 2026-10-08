"""Bounded NetworkManager Wi-Fi discovery and reviewed known-profile activation.

This optional adapter normalizes NetworkManager/nmcli state for the System
network domain. Generic interface, route and resolver discovery remains in
network_query.py and has no NetworkManager dependency.

S7.4 adds one mutation plan only: activate an already-saved Wi-Fi profile on a
selected wireless interface. The adapter never requests NetworkManager secrets,
never creates/edits profiles and never executes the mutation itself.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.parse
import uuid
from typing import Any

MAX_WIFI_DEVICES = 32
MAX_WIFI_NETWORKS = 256
MAX_WIFI_PROFILES = 256
MAX_NMCLI_OUTPUT_BYTES = 1024 * 1024
MAX_TEXT = 512

_IFNAME = re.compile(r"^[^\s/:]{1,32}$")
_BSSID = re.compile(r"^[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}$")
_WIFI_TYPES = {"wifi", "802-11-wireless"}
_RADIO_STATES = {"enabled", "disabled", "missing"}


class NetworkManagerWifiError(ValueError):
    """Invalid or unavailable NetworkManager Wi-Fi input."""


def _bounded(value: Any, field: str, limit: int = MAX_TEXT) -> str:
    if (
        not isinstance(value, str)
        or len(value) > limit
        or any(ord(char) < 32 or ord(char) == 127 for char in value)
    ):
        raise NetworkManagerWifiError(f"{field} is not bounded printable text")
    return value


def _ifname(value: Any) -> str:
    value = _bounded(value, "Wi-Fi interface", 32)
    if not _IFNAME.fullmatch(value):
        raise NetworkManagerWifiError("Wi-Fi interface is invalid")
    return value


def _split_terse_row(line: str, fields: int) -> list[str]:
    if not isinstance(line, str) or any(ord(char) < 32 for char in line):
        raise NetworkManagerWifiError("nmcli row is invalid")
    values: list[str] = []
    current: list[str] = []
    escaped = False
    for char in line:
        if escaped:
            if char not in {":", "\\"}:
                raise NetworkManagerWifiError("nmcli row contains unsupported escape")
            current.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == ":":
            values.append("".join(current))
            current = []
        else:
            current.append(char)
    if escaped:
        raise NetworkManagerWifiError("nmcli row has a truncated escape")
    values.append("".join(current))
    if len(values) != fields:
        raise NetworkManagerWifiError("nmcli row field count is invalid")
    return values


def _rows(text: str, fields: int, *, limit: int) -> list[list[str]]:
    if not isinstance(text, str):
        raise NetworkManagerWifiError("nmcli output is invalid")
    lines = text.splitlines()
    if len(lines) > limit:
        raise NetworkManagerWifiError("nmcli row count exceeds bound")
    return [_split_terse_row(line, fields) for line in lines if line]


def normalize_devices(text: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    seen: set[str] = set()
    for device, typ, state, connection in _rows(
        text, 4, limit=MAX_WIFI_DEVICES * 4
    ):
        if typ not in _WIFI_TYPES:
            continue
        device = _ifname(device)
        if device in seen:
            raise NetworkManagerWifiError("duplicate Wi-Fi interface is unsupported")
        seen.add(device)
        state = _bounded(state.lower(), "Wi-Fi interface state", 64)
        connection = _bounded(connection, "Wi-Fi connection name", 160)
        if connection == "--":
            connection = ""
        rows.append({
            "interface": device,
            "state": state,
            "connection": connection,
        })
        if len(rows) > MAX_WIFI_DEVICES:
            raise NetworkManagerWifiError("Wi-Fi interface count exceeds bound")
    return sorted(rows, key=lambda row: row["interface"])


def normalize_status(general_text: str, devices_text: str) -> dict[str, Any]:
    general = _rows(general_text, 2, limit=2)
    if len(general) != 1:
        raise NetworkManagerWifiError("nmcli Wi-Fi status row is invalid")
    hardware, radio = (value.lower() for value in general[0])
    if hardware not in _RADIO_STATES or radio not in _RADIO_STATES:
        raise NetworkManagerWifiError("nmcli Wi-Fi radio state is invalid")
    return {
        "provider": "NetworkManager",
        "wifi_hardware": hardware,
        "wifi_radio": radio,
        "devices": normalize_devices(devices_text),
    }


def normalize_scan(
    text: str,
    *,
    allowed_devices: set[str] | None = None,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    for in_use, ssid, bssid, signal, security, device in _rows(
        text, 6, limit=MAX_WIFI_NETWORKS
    ):
        if in_use not in {"", "*"}:
            raise NetworkManagerWifiError("nmcli active marker is invalid")
        ssid = _bounded(ssid, "Wi-Fi SSID", 128)
        if not _BSSID.fullmatch(bssid):
            raise NetworkManagerWifiError("Wi-Fi BSSID is invalid")
        bssid = bssid.upper()
        if not signal.isdigit() or not 0 <= int(signal) <= 100:
            raise NetworkManagerWifiError("Wi-Fi signal is invalid")
        device = _ifname(device)
        if allowed_devices is not None and device not in allowed_devices:
            raise NetworkManagerWifiError("Wi-Fi scan returned an unexpected interface")
        security = _bounded(security, "Wi-Fi security", 160)
        if security in {"", "--"}:
            security = "open"
        key = (device, bssid)
        if key in seen:
            raise NetworkManagerWifiError("duplicate Wi-Fi scan identity is unsupported")
        seen.add(key)
        rows.append({
            "active": in_use == "*",
            "ssid": ssid,
            "bssid": bssid,
            "signal": int(signal),
            "security": security,
            "device": device,
        })
    return sorted(
        rows,
        key=lambda row: (
            row["device"],
            -row["signal"],
            row["ssid"],
            row["bssid"],
        ),
    )


def normalize_profiles(text: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for name, raw_uuid, typ, device in _rows(
        text, 4, limit=MAX_WIFI_PROFILES * 4
    ):
        if typ not in _WIFI_TYPES:
            continue
        name = _bounded(name, "Wi-Fi profile name", 160)
        try:
            profile_uuid = str(uuid.UUID(raw_uuid))
        except (ValueError, AttributeError) as exc:
            raise NetworkManagerWifiError("Wi-Fi profile UUID is invalid") from exc
        if profile_uuid in seen:
            raise NetworkManagerWifiError("duplicate Wi-Fi profile UUID is unsupported")
        seen.add(profile_uuid)
        if device in {"", "--"}:
            normalized_device = ""
        else:
            normalized_device = _ifname(device)
        rows.append({
            "name": name,
            "uuid": profile_uuid,
            "type": "wifi",
            "device": normalized_device,
            "active": bool(normalized_device),
        })
        if len(rows) > MAX_WIFI_PROFILES:
            raise NetworkManagerWifiError("Wi-Fi profile count exceeds bound")
    return sorted(rows, key=lambda row: (row["name"], row["uuid"]))


def _timeout_seconds() -> int:
    raw = os.environ.get("IGOR_PLATFORM_QUERY_TIMEOUT_SECONDS", "5")
    if not raw.isdigit():
        raise NetworkManagerWifiError("NetworkManager timeout is invalid")
    value = int(raw)
    if not 1 <= value <= 99:
        raise NetworkManagerWifiError("NetworkManager timeout is invalid")
    return value


def _run_nmcli(args: list[str], *, timeout_seconds: int) -> str:
    argv = ["nmcli", "--terse", "--escape", "yes", *args]
    try:
        result = subprocess.run(
            argv,
            check=False,
            capture_output=True,
            timeout=timeout_seconds,
            env={**os.environ, "LC_ALL": "C"},
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise NetworkManagerWifiError("NetworkManager Wi-Fi provider is unavailable") from exc
    if result.returncode != 0:
        raise NetworkManagerWifiError("NetworkManager Wi-Fi query failed")
    if len(result.stdout) > MAX_NMCLI_OUTPUT_BYTES:
        raise NetworkManagerWifiError("NetworkManager Wi-Fi output exceeds bounded size")
    try:
        return result.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise NetworkManagerWifiError("NetworkManager Wi-Fi output is not UTF-8") from exc


def query_status(*, timeout_seconds: int | None = None) -> dict[str, Any]:
    timeout = _timeout_seconds() if timeout_seconds is None else timeout_seconds
    if type(timeout) is not int or not 1 <= timeout <= 99:
        raise NetworkManagerWifiError("NetworkManager timeout is invalid")
    general = _run_nmcli(
        ["--fields", "WIFI-HW,WIFI", "general", "status"],
        timeout_seconds=timeout,
    )
    devices = _run_nmcli(
        ["--fields", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"],
        timeout_seconds=timeout,
    )
    return normalize_status(general, devices)


def query_scan(*, timeout_seconds: int | None = None) -> list[dict[str, Any]]:
    timeout = _timeout_seconds() if timeout_seconds is None else timeout_seconds
    if type(timeout) is not int or not 1 <= timeout <= 99:
        raise NetworkManagerWifiError("NetworkManager timeout is invalid")
    devices_text = _run_nmcli(
        ["--fields", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"],
        timeout_seconds=timeout,
    )
    devices = normalize_devices(devices_text)
    allowed = {row["interface"] for row in devices}
    if not allowed:
        return []
    scan = _run_nmcli(
        [
            "--fields", "IN-USE,SSID,BSSID,SIGNAL,SECURITY,DEVICE",
            "device", "wifi", "list", "--rescan", "auto",
        ],
        timeout_seconds=timeout,
    )
    return normalize_scan(scan, allowed_devices=allowed)


def query_profiles(*, timeout_seconds: int | None = None) -> list[dict[str, Any]]:
    timeout = _timeout_seconds() if timeout_seconds is None else timeout_seconds
    if type(timeout) is not int or not 1 <= timeout <= 99:
        raise NetworkManagerWifiError("NetworkManager timeout is invalid")
    profiles = _run_nmcli(
        ["--fields", "NAME,UUID,TYPE,DEVICE", "connection", "show"],
        timeout_seconds=timeout,
    )
    return normalize_profiles(profiles)



def _interface_from_object_id(value: Any) -> str:
    text = _bounded(value, "interface object identity", 160)
    prefix = "interface:"
    if not text.startswith(prefix):
        raise NetworkManagerWifiError("interface object identity is invalid")
    encoded = text[len(prefix):]
    name = _ifname(urllib.parse.unquote(encoded))
    if urllib.parse.quote(name, safe="._+-@") != encoded:
        raise NetworkManagerWifiError("interface object identity is not canonical")
    return name


def _profile_uuid(value: Any) -> str:
    text = _bounded(value, "Wi-Fi profile UUID", 36)
    try:
        normalized = str(uuid.UUID(text))
    except (ValueError, AttributeError) as exc:
        raise NetworkManagerWifiError("Wi-Fi profile UUID is invalid") from exc
    if text != normalized:
        raise NetworkManagerWifiError("Wi-Fi profile UUID is not canonical")
    return normalized


def _connect_known_context(
    raw_inputs: Any,
    *,
    status: dict[str, Any] | None = None,
    profiles: list[dict[str, Any]] | None = None,
) -> tuple[str, str, dict[str, Any]]:
    if not isinstance(raw_inputs, dict) or set(raw_inputs) != {"interface", "profile"}:
        raise NetworkManagerWifiError(
            "connect_known requires interface and profile inputs"
        )
    interface_object = _bounded(
        raw_inputs.get("interface"), "interface object identity", 160
    )
    interface = _interface_from_object_id(interface_object)
    profile_uuid = _profile_uuid(raw_inputs.get("profile"))

    current_status = query_status() if status is None else status
    if (
        not isinstance(current_status, dict)
        or current_status.get("provider") != "NetworkManager"
        or current_status.get("wifi_hardware") != "enabled"
        or current_status.get("wifi_radio") != "enabled"
    ):
        raise NetworkManagerWifiError(
            "NetworkManager Wi-Fi radio is not ready for activation"
        )
    devices = current_status.get("devices")
    if not isinstance(devices, list) or any(not isinstance(row, dict) for row in devices):
        raise NetworkManagerWifiError("NetworkManager Wi-Fi device state is invalid")
    matches = [row for row in devices if row.get("interface") == interface]
    if len(matches) != 1:
        raise NetworkManagerWifiError(
            "selected interface is not a current NetworkManager Wi-Fi device"
        )

    current_profiles = query_profiles() if profiles is None else profiles
    if not isinstance(current_profiles, list) or any(
        not isinstance(row, dict) for row in current_profiles
    ):
        raise NetworkManagerWifiError("NetworkManager Wi-Fi profile state is invalid")
    profile_matches = [
        row for row in current_profiles
        if row.get("uuid") == profile_uuid and row.get("type") == "wifi"
    ]
    if len(profile_matches) != 1:
        raise NetworkManagerWifiError(
            "selected saved Wi-Fi profile is not currently available"
        )
    profile = profile_matches[0]
    active_device = profile.get("device", "")
    if (
        profile.get("active") is True
        and isinstance(active_device, str)
        and active_device
        and active_device != interface
    ):
        raise NetworkManagerWifiError(
            "selected saved Wi-Fi profile is active on another interface"
        )
    return interface_object, interface, profile


def freeze_connect_known(
    raw_inputs: Any,
    *,
    status: dict[str, Any] | None = None,
    profiles: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    interface_object, interface, profile = _connect_known_context(
        raw_inputs, status=status, profiles=profiles
    )
    profile_uuid = _profile_uuid(profile.get("uuid"))
    return {
        "action": "connect_known",
        "interface": interface_object,
        "interface_name": interface,
        "profile_uuid": profile_uuid,
        "commands": [[
            "sudo", "-n", "--", "nmcli", "--wait", "30",
            "connection", "up", "uuid", profile_uuid, "ifname", interface,
        ]],
    }


def connect_known_ready(raw_inputs: Any) -> dict[str, Any]:
    plan = freeze_connect_known(raw_inputs)
    return {
        "ready": True,
        "interface": plan["interface"],
        "profile_uuid": plan["profile_uuid"],
    }


def verify_connect_known(
    raw_inputs: Any,
    *,
    profiles: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    if not isinstance(raw_inputs, dict) or set(raw_inputs) != {"interface", "profile"}:
        raise NetworkManagerWifiError(
            "connect_known verification requires interface and profile inputs"
        )
    interface_object = _bounded(
        raw_inputs.get("interface"), "interface object identity", 160
    )
    interface = _interface_from_object_id(interface_object)
    profile_uuid = _profile_uuid(raw_inputs.get("profile"))
    current_profiles = query_profiles() if profiles is None else profiles
    if not isinstance(current_profiles, list) or any(
        not isinstance(row, dict) for row in current_profiles
    ):
        raise NetworkManagerWifiError("NetworkManager Wi-Fi profile state is invalid")
    matches = [row for row in current_profiles if row.get("uuid") == profile_uuid]
    if len(matches) != 1:
        raise NetworkManagerWifiError("selected saved Wi-Fi profile is unavailable")
    profile = matches[0]
    if (
        profile.get("type") != "wifi"
        or profile.get("active") is not True
        or profile.get("device") != interface
    ):
        raise NetworkManagerWifiError(
            "selected saved Wi-Fi profile is not active on the selected interface"
        )
    return {
        "source": "networkmanager.wifi.profiles",
        "check_id": "system.network.wifi.profile.active",
        "interface": interface_object,
        "profile_uuid": profile_uuid,
        "observed": "active",
        "provider": "NetworkManager",
    }


def main(argv: list[str]) -> int:
    try:
        if len(argv) < 2:
            raise NetworkManagerWifiError("invalid NetworkManager Wi-Fi invocation")
        action = argv[1]
        if action in {"status", "scan", "profiles"}:
            if len(argv) != 2:
                raise NetworkManagerWifiError("invalid NetworkManager Wi-Fi read invocation")
            if action == "status":
                result: Any = query_status()
            elif action == "scan":
                result = query_scan()
            else:
                result = query_profiles()
        elif action in {
            "plan-connect-known", "ready-connect-known", "verify-connect-known"
        }:
            if len(argv) != 3:
                raise NetworkManagerWifiError(
                    "invalid NetworkManager Wi-Fi activation invocation"
                )
            try:
                raw_inputs = json.loads(argv[2])
            except json.JSONDecodeError as exc:
                raise NetworkManagerWifiError(
                    "NetworkManager Wi-Fi activation input is invalid JSON"
                ) from exc
            if action == "plan-connect-known":
                result = freeze_connect_known(raw_inputs)
            elif action == "ready-connect-known":
                result = connect_known_ready(raw_inputs)
            else:
                result = verify_connect_known(raw_inputs)
        else:
            raise NetworkManagerWifiError("unsupported NetworkManager Wi-Fi operation")
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 0
    except NetworkManagerWifiError as exc:
        print(f"networkmanager wifi: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
