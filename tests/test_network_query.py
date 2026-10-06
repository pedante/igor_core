"""Focused S7.1 tests for bounded Linux network discovery."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core" / "lib"))

import network_query
from network_query import (
    NetworkQueryError,
    interface_object_id,
    normalize_interfaces,
    normalize_routes,
    parse_resolv_conf,
    query_dns,
)


class NetworkQueryTests(unittest.TestCase):
    def test_interface_identity_and_normalization(self) -> None:
        routes = [
            {
                "family": "ipv4",
                "destination": "default",
                "gateway": "192.0.2.1",
                "device": "eth0",
                "preferred_source": "",
                "metric": 100,
                "table": "main",
                "protocol": "dhcp",
                "scope": "",
                "type": "unicast",
            },
            {
                "family": "ipv6",
                "destination": "default",
                "gateway": "2001:db8::1",
                "device": "eth0",
                "preferred_source": "",
                "metric": 100,
                "table": "main",
                "protocol": "ra",
                "scope": "",
                "type": "unicast",
            },
        ]
        payload = [
            {
                "ifindex": 1,
                "ifname": "lo",
                "flags": ["LOOPBACK", "UP", "LOWER_UP"],
                "mtu": 65536,
                "operstate": "UNKNOWN",
                "link_type": "loopback",
                "address": "00:00:00:00:00:00",
                "addr_info": [
                    {"family": "inet", "local": "127.0.0.1", "prefixlen": 8},
                    {"family": "inet6", "local": "::1", "prefixlen": 128},
                ],
            },
            {
                "ifindex": 2,
                "ifname": "eth0",
                "flags": ["BROADCAST", "MULTICAST", "UP", "LOWER_UP"],
                "mtu": 1500,
                "operstate": "UP",
                "link_type": "ether",
                "address": "02:00:00:00:00:01",
                "addr_info": [
                    {
                        "family": "inet",
                        "local": "192.0.2.10",
                        "prefixlen": 24,
                    },
                    {
                        "family": "inet6",
                        "local": "2001:db8::10",
                        "prefixlen": 64,
                    },
                ],
            },
            {
                "ifindex": 3,
                "ifname": "wlan0",
                "flags": ["BROADCAST", "MULTICAST"],
                "mtu": 1500,
                "operstate": "DOWN",
                "link_type": "ether",
                "address": "02:00:00:00:00:02",
                "addr_info": [],
            },
        ]

        rows = normalize_interfaces(
            payload,
            routes,
            wireless_checker=lambda name: name == "wlan0",
        )

        self.assertEqual(
            [row["object_id"] for row in rows],
            ["interface:lo", "interface:eth0", "interface:wlan0"],
        )
        eth0 = rows[1]
        self.assertEqual(eth0["ipv4_addresses"], "192.0.2.10/24")
        self.assertEqual(eth0["ipv6_addresses"], "2001:db8::10/64")
        self.assertTrue(eth0["admin_up"])
        self.assertTrue(eth0["carrier"])
        self.assertTrue(eth0["default_route_v4"])
        self.assertTrue(eth0["default_route_v6"])
        self.assertFalse(eth0["wireless"])
        self.assertTrue(rows[2]["wireless"])
        self.assertFalse(rows[2]["admin_up"])

    def test_interface_identity_percent_encodes_noncanonical_characters(self) -> None:
        self.assertEqual(interface_object_id("veth0@if5"), "interface:veth0@if5")
        self.assertEqual(interface_object_id("eth%lab"), "interface:eth%25lab")
        with self.assertRaises(NetworkQueryError):
            interface_object_id("bad/name")
        with self.assertRaises(NetworkQueryError):
            interface_object_id("bad:name")

    def test_interface_normalization_rejects_duplicates_and_excess_addresses(self) -> None:
        base = {
            "ifindex": 2,
            "ifname": "eth0",
            "flags": ["UP"],
            "mtu": 1500,
            "operstate": "UP",
            "link_type": "ether",
            "address": "02:00:00:00:00:01",
            "addr_info": [],
        }
        with self.assertRaisesRegex(NetworkQueryError, "duplicate interface"):
            normalize_interfaces(
                [base, {**base, "ifindex": 3}],
                wireless_checker=lambda _name: False,
            )

        too_many = {
            **base,
            "addr_info": [
                {"family": "inet", "local": f"192.0.2.{index % 254 + 1}", "prefixlen": 24}
                for index in range(network_query.MAX_ADDRESSES_PER_INTERFACE + 1)
            ],
        }
        with self.assertRaisesRegex(NetworkQueryError, "address count"):
            normalize_interfaces([too_many], wireless_checker=lambda _name: False)

    def test_interface_normalization_rejects_malformed_route_and_flag_rows(self) -> None:
        base = {
            "ifindex": 2,
            "ifname": "eth0",
            "flags": ["UP"],
            "mtu": 1500,
            "operstate": "UP",
            "link_type": "ether",
            "address": "02:00:00:00:00:01",
            "addr_info": [],
        }
        with self.assertRaisesRegex(NetworkQueryError, "route rows"):
            normalize_interfaces(
                [base],
                ["not-a-route"],
                wireless_checker=lambda _name: False,
            )
        with self.assertRaisesRegex(NetworkQueryError, "flags"):
            normalize_interfaces(
                [{**base, "flags": ["UP\nBAD"]}],
                wireless_checker=lambda _name: False,
            )

    def test_interface_address_text_is_bounded_for_typed_consumers(self) -> None:
        base = {
            "ifindex": 2,
            "ifname": "eth0",
            "flags": ["UP"],
            "mtu": 1500,
            "operstate": "UP",
            "link_type": "ether",
            "address": "02:00:00:00:00:01",
            "addr_info": [
                {
                    "family": "inet6",
                    "local": (
                        f"ffff:ffff:ffff:ffff:ffff:ffff:ffff:f{index:03x}%"
                        + ("scope" + str(index)).ljust(32, "x")
                    ),
                    "prefixlen": 64,
                }
                for index in range(64)
            ],
        }
        with self.assertRaisesRegex(NetworkQueryError, "address text"):
            normalize_interfaces(
                [base],
                wireless_checker=lambda _name: False,
            )

    def test_route_normalization_preserves_default_and_family(self) -> None:
        ipv4 = normalize_routes(
            [
                {
                    "dst": "default",
                    "gateway": "192.0.2.1",
                    "dev": "eth0",
                    "protocol": "dhcp",
                    "metric": 100,
                },
                {
                    "dst": "192.0.2.0/24",
                    "dev": "eth0",
                    "prefsrc": "192.0.2.10",
                    "protocol": "kernel",
                    "scope": "link",
                },
            ],
            "ipv4",
        )
        ipv6 = normalize_routes(
            [
                {
                    "dst": "default",
                    "gateway": "2001:db8::1",
                    "dev": "eth0",
                    "protocol": "ra",
                    "metric": 200,
                    "table": 254,
                }
            ],
            "ipv6",
        )

        self.assertEqual(ipv4[0]["destination"], "default")
        self.assertEqual(ipv4[0]["gateway"], "192.0.2.1")
        self.assertEqual(ipv4[1]["destination"], "192.0.2.0/24")
        self.assertEqual(ipv4[1]["preferred_source"], "192.0.2.10")
        self.assertEqual(ipv6[0]["family"], "ipv6")
        self.assertEqual(ipv6[0]["table"], "254")

    def test_route_normalization_rejects_wrong_family_and_unbounded_rows(self) -> None:
        with self.assertRaisesRegex(NetworkQueryError, "wrong family"):
            normalize_routes([{"dst": "2001:db8::/64"}], "ipv4")
        with self.assertRaisesRegex(NetworkQueryError, "bounded row count"):
            normalize_routes(
                [{} for _ in range(network_query.MAX_ROUTES + 1)],
                "ipv4",
            )

    def test_resolver_parser_reports_configured_endpoints_without_upstream_claim(self) -> None:
        row = parse_resolv_conf(
            """
            # managed by systemd-resolved
            nameserver 127.0.0.53
            nameserver 2001:db8::53 ; configured IPv6 resolver
            domain obsolete.example
            search lan.example example.org
            options edns0 trust-ad
            """,
            symlink_target="../run/systemd/resolve/stub-resolv.conf",
            resolved_path="/run/systemd/resolve/stub-resolv.conf",
        )

        self.assertEqual(row["nameservers"], ["127.0.0.53", "2001:db8::53"])
        self.assertEqual(row["search_domains"], ["lan.example", "example.org"])
        self.assertTrue(row["local_stub"])
        self.assertTrue(row["symlink"])
        self.assertEqual(
            row["symlink_target"],
            "../run/systemd/resolve/stub-resolv.conf",
        )
        self.assertNotIn("upstream", row)

    def test_query_dns_preserves_symlink_context_but_reads_bounded_target(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            target = root / "resolved.conf"
            target.write_text("nameserver 192.0.2.53\n", encoding="utf-8")
            link = root / "resolv.conf"
            link.symlink_to(target.name)

            row = query_dns(link)

        self.assertEqual(row["path"], str(link))
        self.assertTrue(row["symlink"])
        self.assertEqual(row["symlink_target"], target.name)
        self.assertEqual(row["resolved_path"], str(target))
        self.assertEqual(row["nameservers"], ["192.0.2.53"])
        self.assertFalse(row["local_stub"])

    def test_ip_runner_is_read_only_bounded_and_uses_json_mode(self) -> None:
        result = SimpleNamespace(returncode=0, stdout=b"[]", stderr=b"")
        with patch("network_query.subprocess.run", return_value=result) as run:
            payload = network_query._run_ip_json(
                ["-4", "route", "show", "table", "all"],
                timeout_seconds=5,
            )

        self.assertEqual(payload, [])
        args, kwargs = run.call_args
        self.assertEqual(
            args[0],
            ["ip", "-j", "-4", "route", "show", "table", "all"],
        )
        self.assertFalse(kwargs["check"])
        self.assertEqual(kwargs["timeout"], 5)
        self.assertNotIn("sudo", args[0])

    def test_ip_runner_rejects_nonzero_invalid_json_and_oversized_output(self) -> None:
        cases = [
            SimpleNamespace(returncode=1, stdout=b"", stderr=b"failure"),
            SimpleNamespace(returncode=0, stdout=b"{", stderr=b""),
            SimpleNamespace(
                returncode=0,
                stdout=b"x" * (network_query.MAX_IP_OUTPUT_BYTES + 1),
                stderr=b"",
            ),
        ]
        for result in cases:
            with (
                self.subTest(result=result.returncode, size=len(result.stdout)),
                patch("network_query.subprocess.run", return_value=result),
                self.assertRaises(NetworkQueryError),
            ):
                network_query._run_ip_json(
                    ["-4", "route", "show"],
                    timeout_seconds=5,
                )

    def test_snapshot_queries_only_kernel_routes_addresses_and_resolver(self) -> None:
        route4 = [{"dst": "default", "dev": "eth0", "gateway": "192.0.2.1"}]
        route6: list[dict[str, object]] = []
        links = [{
            "ifindex": 2,
            "ifname": "eth0",
            "flags": ["UP", "LOWER_UP"],
            "mtu": 1500,
            "operstate": "UP",
            "link_type": "ether",
            "address": "02:00:00:00:00:01",
            "addr_info": [{"family": "inet", "local": "192.0.2.10", "prefixlen": 24}],
        }]
        dns = {
            "path": "/etc/resolv.conf",
            "symlink": False,
            "symlink_target": "",
            "resolved_path": "/etc/resolv.conf",
            "nameservers": ["192.0.2.53"],
            "search_domains": [],
            "local_stub": False,
        }

        def fake_ip(args, *, timeout_seconds):
            self.assertEqual(timeout_seconds, 5)
            if args[:2] == ["-4", "route"]:
                return route4
            if args[:2] == ["-6", "route"]:
                return route6
            if args == ["-d", "address", "show"]:
                return links
            self.fail(f"unexpected ip query {args}")

        with (
            patch("network_query._run_ip_json", side_effect=fake_ip),
            patch("network_query.query_dns", return_value=dns),
            patch("network_query.Path.is_dir", return_value=False),
        ):
            snapshot = network_query.query_snapshot(timeout_seconds=5)

        self.assertEqual(snapshot["interfaces"][0]["object_id"], "interface:eth0")
        self.assertTrue(snapshot["interfaces"][0]["default_route_v4"])
        self.assertEqual(snapshot["routes"][0]["destination"], "default")
        self.assertEqual(snapshot["dns"], dns)


if __name__ == "__main__":
    unittest.main()
