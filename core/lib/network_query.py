"""Bounded read-only Linux network discovery for Igor Core.

This module normalizes kernel/iproute2 and resolver configuration state. It owns
no host health meaning, desired state, network-manager policy or mutation path.
System observers/capabilities consume the normalized rows in later S7 phases.
"""

from __future__ import annotations

import ipaddress
import json
import os
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path
from typing import Any, Callable

MAX_INTERFACES = 128
MAX_ADDRESSES_PER_INTERFACE = 64
MAX_ROUTES = 512
MAX_TEXT = 512
MAX_IP_OUTPUT_BYTES = 1024 * 1024
MAX_RESOLV_CONF_BYTES = 64 * 1024

_IFNAME = re.compile(r"^[^\s/:]{1,32}$")
_SCOPE_ID = re.compile(r"^[A-Za-z0-9_.-]{1,32}$")
_ROUTE_FAMILIES = {"inet": "ipv4", "inet6": "ipv6"}


class NetworkQueryError(ValueError):
    """Invalid or unavailable network discovery input."""


def _bounded(value: Any, field: str, limit: int = MAX_TEXT) -> str:
    if (
        not isinstance(value, str)
        or len(value) > limit
        or any(ord(char) < 32 for char in value)
    ):
        raise NetworkQueryError(f"{field} is not bounded printable text")
    return value


def _ifname(value: Any) -> str:
    value = _bounded(value, "interface name", 32)
    if not _IFNAME.fullmatch(value):
        raise NetworkQueryError("interface name is invalid")
    return value


def interface_object_id(name: str) -> str:
    name = _ifname(name)
    encoded = urllib.parse.quote(name, safe="._+-@")
    ident = f"interface:{encoded}"
    if len(ident) > 160:
        raise NetworkQueryError("interface object identity is too long")
    return ident


def _integer(value: Any, field: str, *, minimum: int = 0) -> int:
    if type(value) is not int or value < minimum:
        raise NetworkQueryError(f"{field} is invalid")
    return value


def _ip_endpoint(value: Any, family: str | None = None) -> str:
    text = _bounded(value, "IP address", 128)
    address_text, separator, scope_id = text.partition("%")
    if separator and (not scope_id or not _SCOPE_ID.fullmatch(scope_id)):
        raise NetworkQueryError("IP scope identifier is invalid")
    try:
        address = ipaddress.ip_address(address_text)
    except ValueError as exc:
        raise NetworkQueryError("IP address is invalid") from exc
    if family == "ipv4" and address.version != 4:
        raise NetworkQueryError("IPv4 address has wrong family")
    if family == "ipv6" and address.version != 6:
        raise NetworkQueryError("IPv6 address has wrong family")
    rendered = str(address)
    return rendered + ("%" + scope_id if separator else "")


def _cidr(local: Any, prefixlen: Any, family: str) -> str:
    prefix = _integer(prefixlen, "address prefix length")
    maximum = 32 if family == "ipv4" else 128
    if prefix > maximum:
        raise NetworkQueryError("address prefix length is outside family range")
    endpoint = _ip_endpoint(local, family)
    address_text, separator, scope_id = endpoint.partition("%")
    try:
        interface = ipaddress.ip_interface(f"{address_text}/{prefix}")
    except ValueError as exc:
        raise NetworkQueryError("interface address is invalid") from exc
    rendered = f"{interface.ip}/{interface.network.prefixlen}"
    return rendered + ("%" + scope_id if separator else "")


def _interface_kind(raw: dict[str, Any], flags: set[str]) -> str:
    linkinfo = raw.get("linkinfo")
    if isinstance(linkinfo, dict) and isinstance(linkinfo.get("info_kind"), str):
        return _bounded(linkinfo["info_kind"], "interface kind", 64)
    if "LOOPBACK" in flags:
        return "loopback"
    link_type = raw.get("link_type")
    if isinstance(link_type, str) and link_type:
        return _bounded(link_type, "interface link type", 64)
    return "unknown"


def _mac(value: Any) -> str:
    if value in {None, ""}:
        return ""
    text = _bounded(value, "interface address", 128).lower()
    if not re.fullmatch(r"[0-9a-f]{2}(?::[0-9a-f]{2}){5,19}", text):
        # Non-Ethernet link-layer addresses vary. Keep valid bounded hexadecimal
        # colon forms while rejecting arbitrary text.
        if not re.fullmatch(r"[0-9a-f]+(?::[0-9a-f]+)+", text):
            raise NetworkQueryError("interface address is invalid")
    return text


def _wireless_sysfs(name: str) -> bool:
    root = Path("/sys/class/net", name)
    return (root / "wireless").is_dir() or (root / "phy80211").is_dir()


def normalize_interfaces(
    payload: Any,
    routes: list[dict[str, Any]] | None = None,
    *,
    wireless_checker: Callable[[str], bool] | None = None,
) -> list[dict[str, Any]]:
    if not isinstance(payload, list):
        raise NetworkQueryError("ip address returned an invalid document")
    if len(payload) > MAX_INTERFACES:
        raise NetworkQueryError("interface inventory exceeds bounded row count")
    routes = routes or []
    default_v4 = {
        row["device"] for row in routes
        if row.get("family") == "ipv4" and row.get("destination") == "default"
        and row.get("device")
    }
    default_v6 = {
        row["device"] for row in routes
        if row.get("family") == "ipv6" and row.get("destination") == "default"
        and row.get("device")
    }
    if wireless_checker is None:
        wireless_checker = _wireless_sysfs

    rows: list[dict[str, Any]] = []
    seen_names: set[str] = set()
    seen_indexes: set[int] = set()
    for raw in payload:
        if not isinstance(raw, dict):
            raise NetworkQueryError("interface row is not an object")
        name = _ifname(raw.get("ifname"))
        ifindex = _integer(raw.get("ifindex"), "interface index", minimum=1)
        if name in seen_names or ifindex in seen_indexes:
            raise NetworkQueryError("duplicate interface identity is unsupported")
        seen_names.add(name)
        seen_indexes.add(ifindex)

        flags_raw = raw.get("flags", [])
        if not isinstance(flags_raw, list) or any(
            not isinstance(flag, str) or len(flag) > 64 for flag in flags_raw
        ):
            raise NetworkQueryError("interface flags are invalid")
        flags = set(flags_raw)
        mtu = _integer(raw.get("mtu"), "interface MTU", minimum=1)
        operstate = raw.get("operstate", "UNKNOWN")
        operstate = _bounded(operstate, "interface operational state", 32).lower()
        addr_info = raw.get("addr_info", [])
        if not isinstance(addr_info, list):
            raise NetworkQueryError("interface addresses are invalid")
        if len(addr_info) > MAX_ADDRESSES_PER_INTERFACE:
            raise NetworkQueryError("interface address count exceeds bound")

        ipv4: list[str] = []
        ipv6: list[str] = []
        for address in addr_info:
            if not isinstance(address, dict):
                raise NetworkQueryError("interface address row is invalid")
            family_raw = address.get("family")
            if family_raw not in _ROUTE_FAMILIES:
                continue
            family = _ROUTE_FAMILIES[family_raw]
            local = address.get("local")
            prefixlen = address.get("prefixlen")
            if local is None or prefixlen is None:
                raise NetworkQueryError("interface address is incomplete")
            rendered = _cidr(local, prefixlen, family)
            target = ipv4 if family == "ipv4" else ipv6
            if rendered not in target:
                target.append(rendered)

        try:
            wireless = bool(wireless_checker(name))
        except OSError as exc:
            raise NetworkQueryError("wireless interface inspection failed") from exc

        rows.append({
            "object_id": interface_object_id(name),
            "name": name,
            "ifindex": ifindex,
            "operstate": operstate,
            "admin_up": "UP" in flags,
            "carrier": "LOWER_UP" in flags,
            "mtu": mtu,
            "mac": _mac(raw.get("address")),
            "kind": _interface_kind(raw, flags),
            "wireless": wireless,
            "ipv4_addresses": ",".join(sorted(ipv4)),
            "ipv6_addresses": ",".join(sorted(ipv6)),
            "default_route_v4": name in default_v4,
            "default_route_v6": name in default_v6,
        })
    rows.sort(key=lambda row: (row["ifindex"], row["name"]))
    return rows


def _network(value: Any, family: str) -> str:
    text = _bounded(value, "route destination", 128)
    if text == "default":
        return text
    try:
        network = ipaddress.ip_network(text, strict=False)
    except ValueError as exc:
        raise NetworkQueryError("route destination is invalid") from exc
    if family == "ipv4" and network.version != 4:
        raise NetworkQueryError("route destination has wrong family")
    if family == "ipv6" and network.version != 6:
        raise NetworkQueryError("route destination has wrong family")
    return str(network)


def _route_table(value: Any) -> str:
    if value is None:
        return "main"
    if type(value) is int:
        if value < 0:
            raise NetworkQueryError("route table is invalid")
        return str(value)
    text = _bounded(value, "route table", 64)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", text):
        raise NetworkQueryError("route table is invalid")
    return text


def normalize_routes(payload: Any, family: str) -> list[dict[str, Any]]:
    if family not in {"ipv4", "ipv6"}:
        raise NetworkQueryError("route family is invalid")
    if not isinstance(payload, list):
        raise NetworkQueryError("ip route returned an invalid document")
    if len(payload) > MAX_ROUTES:
        raise NetworkQueryError("route inventory exceeds bounded row count")

    rows: list[dict[str, Any]] = []
    for raw in payload:
        if not isinstance(raw, dict):
            raise NetworkQueryError("route row is not an object")
        destination = _network(raw.get("dst", "default"), family)
        device = raw.get("dev", "")
        device = _ifname(device) if device else ""
        gateway = raw.get("gateway", "")
        gateway = _ip_endpoint(gateway, family) if gateway else ""
        preferred = raw.get("prefsrc", "")
        preferred = _ip_endpoint(preferred, family) if preferred else ""
        metric = raw.get("metric", 0)
        metric = _integer(metric, "route metric")
        protocol = _bounded(raw.get("protocol", ""), "route protocol", 64)
        scope = _bounded(raw.get("scope", ""), "route scope", 64)
        route_type = _bounded(raw.get("type", "unicast"), "route type", 64)
        rows.append({
            "family": family,
            "destination": destination,
            "gateway": gateway,
            "device": device,
            "preferred_source": preferred,
            "metric": metric,
            "table": _route_table(raw.get("table")),
            "protocol": protocol,
            "scope": scope,
            "type": route_type,
        })
    rows.sort(key=lambda row: (
        row["family"],
        row["destination"] != "default",
        row["table"],
        row["metric"],
        row["destination"],
        row["device"],
        row["gateway"],
    ))
    return rows


def parse_resolv_conf(
    text: str,
    *,
    path: str = "/etc/resolv.conf",
    symlink_target: str = "",
    resolved_path: str = "/etc/resolv.conf",
) -> dict[str, Any]:
    if len(text.encode("utf-8")) > MAX_RESOLV_CONF_BYTES:
        raise NetworkQueryError("resolver configuration exceeds bounded size")
    nameservers: list[str] = []
    search_domains: list[str] = []
    for raw in text.splitlines():
        hash_at = raw.find("#")
        semicolon_at = raw.find(";")
        cuts = [index for index in (hash_at, semicolon_at) if index >= 0]
        line = raw[:min(cuts)].strip() if cuts else raw.strip()
        if not line:
            continue
        parts = line.split()
        if parts[0] == "nameserver":
            if len(parts) != 2:
                raise NetworkQueryError("resolver nameserver line is invalid")
            endpoint = _ip_endpoint(parts[1])
            if endpoint not in nameservers:
                nameservers.append(endpoint)
                if len(nameservers) > 16:
                    raise NetworkQueryError("resolver nameserver count exceeds bound")
        elif parts[0] in {"search", "domain"}:
            domains = parts[1:]
            if not domains:
                raise NetworkQueryError("resolver search line is invalid")
            parsed_domains: list[str] = []
            for domain in domains:
                domain = _bounded(domain, "resolver search domain", 253).rstrip(".")
                if not domain or not re.fullmatch(r"[A-Za-z0-9_.-]+", domain):
                    raise NetworkQueryError("resolver search domain is invalid")
                if domain not in parsed_domains:
                    parsed_domains.append(domain)
                    if len(parsed_domains) > 32:
                        raise NetworkQueryError("resolver search domain count exceeds bound")
            # resolv.conf search/domain directives replace the previous search list.
            search_domains = parsed_domains

    local_stub = False
    for endpoint in nameservers:
        address_text = endpoint.partition("%")[0]
        try:
            if ipaddress.ip_address(address_text).is_loopback:
                local_stub = True
        except ValueError as exc:  # pragma: no cover - guarded by _ip_endpoint
            raise NetworkQueryError("resolver endpoint is invalid") from exc

    return {
        "path": _bounded(path, "resolver path"),
        "symlink": bool(symlink_target),
        "symlink_target": _bounded(symlink_target, "resolver symlink target"),
        "resolved_path": _bounded(resolved_path, "resolved resolver path"),
        "nameservers": nameservers,
        "search_domains": search_domains,
        "local_stub": local_stub,
    }


def query_dns(path: Path = Path("/etc/resolv.conf")) -> dict[str, Any]:
    try:
        path.lstat()
    except OSError as exc:
        raise NetworkQueryError("resolver configuration is unavailable") from exc
    symlink_target = ""
    if path.is_symlink():
        try:
            symlink_target = os.readlink(path)
        except OSError as exc:
            raise NetworkQueryError("resolver symlink is unreadable") from exc
    try:
        resolved = path.resolve(strict=True)
        data = resolved.read_bytes()
    except OSError as exc:
        raise NetworkQueryError("resolver configuration is unreadable") from exc
    if len(data) > MAX_RESOLV_CONF_BYTES:
        raise NetworkQueryError("resolver configuration exceeds bounded size")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise NetworkQueryError("resolver configuration is not UTF-8") from exc
    # lstat above deliberately runs even for a regular file so a broken path
    # never becomes an accidental successful empty resolver result.
    return parse_resolv_conf(
        text,
        path=path.as_posix(),
        symlink_target=symlink_target,
        resolved_path=resolved.as_posix(),
    )


def _timeout_seconds() -> int:
    raw = os.environ.get("IGOR_PLATFORM_QUERY_TIMEOUT_SECONDS", "5")
    if not raw.isdigit():
        raise NetworkQueryError("network timeout is invalid")
    value = int(raw)
    if not 1 <= value <= 99:
        raise NetworkQueryError("network timeout is invalid")
    return value


def _run_ip_json(args: list[str], *, timeout_seconds: int) -> Any:
    try:
        result = subprocess.run(
            ["ip", "-j", *args],
            check=False,
            capture_output=True,
            timeout=timeout_seconds,
            env={**os.environ, "LC_ALL": "C"},
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise NetworkQueryError("iproute2 is unavailable") from exc
    if result.returncode != 0:
        raise NetworkQueryError("iproute2 query failed")
    if len(result.stdout) > MAX_IP_OUTPUT_BYTES:
        raise NetworkQueryError("iproute2 output exceeds bounded size")
    try:
        text = result.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise NetworkQueryError("iproute2 output is not UTF-8") from exc
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise NetworkQueryError("iproute2 returned invalid JSON") from exc


def query_routes(*, timeout_seconds: int | None = None) -> list[dict[str, Any]]:
    timeout = _timeout_seconds() if timeout_seconds is None else timeout_seconds
    if type(timeout) is not int or not 1 <= timeout <= 99:
        raise NetworkQueryError("network timeout is invalid")
    ipv4 = _run_ip_json(["-4", "route", "show", "table", "all"], timeout_seconds=timeout)
    ipv6 = _run_ip_json(["-6", "route", "show", "table", "all"], timeout_seconds=timeout)
    rows = normalize_routes(ipv4, "ipv4") + normalize_routes(ipv6, "ipv6")
    if len(rows) > MAX_ROUTES:
        raise NetworkQueryError("combined route inventory exceeds bounded row count")
    return sorted(rows, key=lambda row: (
        row["family"], row["destination"] != "default", row["table"],
        row["metric"], row["destination"], row["device"], row["gateway"],
    ))


def query_interfaces(
    *,
    timeout_seconds: int | None = None,
    routes: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    timeout = _timeout_seconds() if timeout_seconds is None else timeout_seconds
    if type(timeout) is not int or not 1 <= timeout <= 99:
        raise NetworkQueryError("network timeout is invalid")
    effective_routes = query_routes(timeout_seconds=timeout) if routes is None else routes
    payload = _run_ip_json(["-d", "address", "show"], timeout_seconds=timeout)
    return normalize_interfaces(payload, effective_routes)


def query_snapshot(*, timeout_seconds: int | None = None) -> dict[str, Any]:
    timeout = _timeout_seconds() if timeout_seconds is None else timeout_seconds
    if type(timeout) is not int or not 1 <= timeout <= 99:
        raise NetworkQueryError("network timeout is invalid")
    routes = query_routes(timeout_seconds=timeout)
    return {
        "interfaces": query_interfaces(timeout_seconds=timeout, routes=routes),
        "routes": routes,
        "dns": query_dns(),
    }


def main(argv: list[str]) -> int:
    try:
        if len(argv) != 2 or argv[1] not in {"interfaces", "routes", "dns", "snapshot"}:
            raise NetworkQueryError(
                "usage: network_query.py {interfaces|routes|dns|snapshot}"
            )
        kind = argv[1]
        if kind == "interfaces":
            result: Any = query_interfaces()
        elif kind == "routes":
            result = query_routes()
        elif kind == "dns":
            result = query_dns()
        else:
            result = query_snapshot()
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 0
    except (NetworkQueryError, ValueError, TypeError) as exc:
        print(f"network query: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
