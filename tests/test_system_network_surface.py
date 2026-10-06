"""Focused S7.2 tests for System-owned network presentation."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SURFACE = ROOT / "modules/system/lib/network_surface.py"
spec = importlib.util.spec_from_file_location("system_network_surface", SURFACE)
assert spec and spec.loader
network_surface = importlib.util.module_from_spec(spec)
spec.loader.exec_module(network_surface)


class NetworkSurfaceTests(unittest.TestCase):
    def interfaces(self):
        return [
            {
                "object_id": "interface:eth0",
                "name": "eth0",
                "ifindex": 2,
                "operstate": "up",
                "admin_up": True,
                "carrier": True,
                "mtu": 1500,
                "mac": "02:00:00:00:00:01",
                "kind": "ether",
                "wireless": False,
                "ipv4_addresses": "192.0.2.10/24",
                "ipv6_addresses": "",
                "default_route_v4": True,
                "default_route_v6": False,
            },
            {
                "object_id": "interface:wlan0",
                "name": "wlan0",
                "ifindex": 3,
                "operstate": "down",
                "admin_up": False,
                "carrier": False,
                "mtu": 1500,
                "mac": "02:00:00:00:00:02",
                "kind": "ether",
                "wireless": True,
                "ipv4_addresses": "",
                "ipv6_addresses": "",
                "default_route_v4": False,
                "default_route_v6": False,
            },
        ]

    def routes(self):
        return [
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
            }
        ]

    def dns(self):
        return {
            "path": "/etc/resolv.conf",
            "symlink": True,
            "symlink_target": "../run/systemd/resolve/stub-resolv.conf",
            "resolved_path": "/run/systemd/resolve/stub-resolv.conf",
            "nameservers": ["127.0.0.53"],
            "search_domains": ["example.org"],
            "local_stub": True,
        }

    def test_observer_maps_every_declared_interface_fact(self):
        envelope = network_surface.observe_interfaces(self.interfaces())
        objects = envelope["result"]["objects"]
        self.assertEqual(len(objects), 2)
        eth0 = objects[0]
        self.assertEqual(eth0["object_id"], "interface:eth0")
        facts = {row["property"]: row["value"] for row in eth0["facts"]}
        self.assertEqual(facts["interface.name"], "eth0")
        self.assertEqual(facts["interface.ipv4_addresses"], "192.0.2.10/24")
        self.assertTrue(facts["interface.default_route_v4"])
        self.assertFalse(facts["interface.wireless"])
        self.assertEqual(
            eth0["facts"][0]["evidence"],
            ["core.network.interfaces:interface:eth0"],
        )

    def test_summary_is_host_meaning_over_normalized_snapshot(self):
        result = network_surface.summary({
            "interfaces": self.interfaces(),
            "routes": self.routes(),
            "dns": self.dns(),
        })["result"]
        self.assertEqual(result["interface_count"], 2)
        self.assertEqual(result["admin_up_count"], 1)
        self.assertEqual(result["carrier_count"], 1)
        self.assertEqual(result["wireless_count"], 1)
        self.assertEqual(result["default_route_v4"], "eth0")
        self.assertEqual(result["default_route_v6"], "")
        self.assertEqual(result["resolver_count"], 1)
        self.assertTrue(result["resolver_local_stub"])

    def test_status_returns_only_selected_canonical_row(self):
        result = network_surface.interface_status(
            self.interfaces(), "interface:wlan0"
        )["result"]
        self.assertEqual(result["name"], "wlan0")
        self.assertTrue(result["wireless"])
        with self.assertRaisesRegex(
            network_surface.NetworkSurfaceError, "not currently present"
        ):
            network_surface.interface_status(
                self.interfaces(), "interface:missing"
            )

    def test_route_and_interface_presentations_are_bounded(self):
        many_interfaces = self.interfaces() * 128
        interfaces = network_surface.interfaces_list(many_interfaces)["result"]
        self.assertLessEqual(len(interfaces["interfaces"]), 4096)

        many_routes = self.routes() * 512
        routes = network_surface.routes_list(many_routes)["result"]
        self.assertLessEqual(len(routes["routes"]), 4096)
        self.assertIn("ipv4\tdefault via 192.0.2.1 dev eth0", routes["routes"])

    def test_dns_status_keeps_stub_and_source_context_without_upstream_claim(self):
        result = network_surface.dns_status(self.dns())["result"]
        self.assertEqual(result["nameservers"], "127.0.0.53")
        self.assertEqual(result["search_domains"], "example.org")
        self.assertTrue(result["local_stub"])
        self.assertTrue(result["symlink"])
        self.assertNotIn("upstream", result)

    def test_malformed_normalized_shapes_fail_closed(self):
        with self.assertRaisesRegex(
            network_surface.NetworkSurfaceError, "interface row shape"
        ):
            network_surface.interfaces_list([{"object_id": "interface:eth0"}])
        with self.assertRaisesRegex(
            network_surface.NetworkSurfaceError, "route row shape"
        ):
            network_surface.routes_list([{"family": "ipv4"}])
        with self.assertRaisesRegex(
            network_surface.NetworkSurfaceError, "resolver row shape"
        ):
            network_surface.dns_status({"nameservers": []})


if __name__ == "__main__":
    unittest.main()
