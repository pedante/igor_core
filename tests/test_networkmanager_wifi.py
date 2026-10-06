"""Focused S7.3-S7.4 tests for the bounded NetworkManager Wi-Fi provider."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core" / "lib"))

import networkmanager_wifi
from networkmanager_wifi import (
    NetworkManagerWifiError,
    normalize_profiles,
    normalize_scan,
    normalize_status,
)


class NetworkManagerWifiTests(unittest.TestCase):
    def test_status_normalizes_only_wifi_devices(self):
        result = normalize_status(
            "enabled:enabled\n",
            "wlan0:wifi:connected:Home\\:Lab\neth0:ethernet:connected:Wired\n",
        )
        self.assertEqual(result["provider"], "NetworkManager")
        self.assertEqual(result["devices"], [{
            "interface": "wlan0",
            "state": "connected",
            "connection": "Home:Lab",
        }])

    def test_status_accepts_bounded_networkmanager_state_labels(self):
        result = normalize_status(
            "enabled:enabled\n",
            "wlan0:wifi:connected (externally):Imported\n",
        )
        self.assertEqual(result["devices"][0]["state"], "connected (externally)")

    def test_scan_normalizes_escaped_bssid_signal_security_and_hidden_ssid(self):
        rows = normalize_scan(
            "*:Home\\:Lab:AA\\:BB\\:CC\\:DD\\:EE\\:FF:78:WPA2:wlan0\n"
            ": :11\\:22\\:33\\:44\\:55\\:66:31:--:wlan0\n",
            allowed_devices={"wlan0"},
        )
        self.assertEqual(rows[0]["bssid"], "AA:BB:CC:DD:EE:FF")
        self.assertEqual(rows[0]["ssid"], "Home:Lab")
        self.assertEqual(rows[0]["signal"], 78)
        self.assertEqual(rows[0]["security"], "WPA2")
        self.assertTrue(rows[0]["active"])
        self.assertEqual(rows[1]["security"], "open")

    def test_profiles_use_uuid_and_ignore_non_wifi_profiles(self):
        rows = normalize_profiles(
            "Home:123e4567-e89b-12d3-a456-426614174000:802-11-wireless:wlan0\n"
            "Wired:123e4567-e89b-12d3-a456-426614174001:802-3-ethernet:eth0\n"
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["uuid"], "123e4567-e89b-12d3-a456-426614174000")
        self.assertTrue(rows[0]["active"])
        self.assertEqual(rows[0]["device"], "wlan0")

    def test_malformed_duplicate_and_invalid_provider_rows_fail_closed(self):
        with self.assertRaises(NetworkManagerWifiError):
            normalize_status("enabled\n", "")
        with self.assertRaises(NetworkManagerWifiError):
            normalize_scan(
                ":Home:AA\\:BB\\:CC\\:DD\\:EE\\:FF:101:WPA2:wlan0\n"
            )
        with self.assertRaisesRegex(NetworkManagerWifiError, "duplicate"):
            normalize_scan(
                ":One:AA\\:BB\\:CC\\:DD\\:EE\\:FF:50:WPA2:wlan0\n"
                ":Two:AA\\:BB\\:CC\\:DD\\:EE\\:FF:40:WPA2:wlan0\n"
            )
        with self.assertRaisesRegex(NetworkManagerWifiError, "UUID"):
            normalize_profiles("Home:not-a-uuid:wifi:wlan0\n")
        with self.assertRaisesRegex(NetworkManagerWifiError, "unsupported escape"):
            normalize_profiles(
                "Bad\\q:123e4567-e89b-12d3-a456-426614174000:wifi:wlan0\n"
            )

    def test_scan_rejects_provider_interface_drift(self):
        with self.assertRaisesRegex(NetworkManagerWifiError, "unexpected interface"):
            normalize_scan(
                ":Home:AA\\:BB\\:CC\\:DD\\:EE\\:FF:50:WPA2:wlan1\n",
                allowed_devices={"wlan0"},
            )

    def test_row_and_output_bounds_fail_closed(self):
        too_many = "".join(
            f":N{i}:AA\\:BB\\:CC\\:DD\\:EE\\:FF:50:WPA2:wlan0\n"
            for i in range(257)
        )
        with self.assertRaisesRegex(NetworkManagerWifiError, "row count"):
            normalize_scan(too_many)

        oversized = SimpleNamespace(
            returncode=0,
            stdout=b"x" * (networkmanager_wifi.MAX_NMCLI_OUTPUT_BYTES + 1),
        )
        with (
            patch("networkmanager_wifi.subprocess.run", return_value=oversized),
            self.assertRaisesRegex(NetworkManagerWifiError, "bounded size"),
        ):
            networkmanager_wifi._run_nmcli(
                ["general", "status"], timeout_seconds=1
            )

    def test_query_status_freezes_exact_read_only_argv(self):
        calls = []
        outputs = [b"enabled:enabled\n", b"wlan0:wifi:connected:Home\n"]

        def run(argv, **kwargs):
            calls.append(argv)
            return SimpleNamespace(returncode=0, stdout=outputs.pop(0))

        with patch("networkmanager_wifi.subprocess.run", side_effect=run):
            result = networkmanager_wifi.query_status(timeout_seconds=2)
        self.assertEqual(result["wifi_radio"], "enabled")
        self.assertEqual(calls, [
            [
                "nmcli", "--terse", "--escape", "yes", "--fields",
                "WIFI-HW,WIFI", "general", "status",
            ],
            [
                "nmcli", "--terse", "--escape", "yes", "--fields",
                "DEVICE,TYPE,STATE,CONNECTION", "device", "status",
            ],
        ])

    def test_query_scan_uses_only_read_tokens_and_auto_rescan(self):
        calls = []
        outputs = [
            b"wlan0:wifi:disconnected:--\n",
            b":Home:AA\\:BB\\:CC\\:DD\\:EE\\:FF:70:WPA2:wlan0\n",
        ]

        def run(argv, **kwargs):
            calls.append(argv)
            return SimpleNamespace(returncode=0, stdout=outputs.pop(0))

        with patch("networkmanager_wifi.subprocess.run", side_effect=run):
            rows = networkmanager_wifi.query_scan(timeout_seconds=2)
        self.assertEqual(rows[0]["ssid"], "Home")
        tokens = {token for argv in calls for token in argv}
        for forbidden in (
            "connect", "disconnect", "radio", "password", "psk",
            "--show-secrets", "up", "down",
        ):
            self.assertNotIn(forbidden, tokens)
        self.assertIn("--rescan", calls[1])
        self.assertIn("auto", calls[1])

    def test_query_scan_with_no_wifi_device_does_not_scan(self):
        calls = []

        def run(argv, **kwargs):
            calls.append(argv)
            return SimpleNamespace(
                returncode=0, stdout=b"eth0:ethernet:connected:Wired\n"
            )

        with patch("networkmanager_wifi.subprocess.run", side_effect=run):
            self.assertEqual(
                networkmanager_wifi.query_scan(timeout_seconds=2), []
            )
        self.assertEqual(len(calls), 1)

    def test_query_profiles_never_requests_secrets(self):
        calls = []

        def run(argv, **kwargs):
            calls.append(argv)
            return SimpleNamespace(
                returncode=0,
                stdout=(
                    b"Home:123e4567-e89b-12d3-a456-"
                    b"426614174000:wifi:--\n"
                ),
            )

        with patch("networkmanager_wifi.subprocess.run", side_effect=run):
            rows = networkmanager_wifi.query_profiles(timeout_seconds=2)
        self.assertEqual(rows[0]["name"], "Home")
        tokens = {token for argv in calls for token in argv}
        self.assertNotIn("--show-secrets", tokens)
        self.assertNotIn("password", tokens)
        self.assertNotIn("psk", tokens)

    def test_provider_failure_and_invalid_utf8_fail_closed(self):
        with (
            patch(
                "networkmanager_wifi.subprocess.run",
                return_value=SimpleNamespace(
                    returncode=10, stdout=b"", stderr=b"secret-ish"
                ),
            ),
            self.assertRaisesRegex(NetworkManagerWifiError, "query failed"),
        ):
            networkmanager_wifi._run_nmcli(
                ["device", "status"], timeout_seconds=1
            )

        with (
            patch(
                "networkmanager_wifi.subprocess.run",
                return_value=SimpleNamespace(returncode=0, stdout=b"\xff"),
            ),
            self.assertRaisesRegex(NetworkManagerWifiError, "not UTF-8"),
        ):
            networkmanager_wifi._run_nmcli(
                ["device", "status"], timeout_seconds=1
            )


    def test_connect_known_plan_freezes_exact_non_secret_argv(self):
        status = {
            "provider": "NetworkManager",
            "wifi_hardware": "enabled",
            "wifi_radio": "enabled",
            "devices": [
                {"interface": "wlan0", "state": "disconnected", "connection": ""}
            ],
        }
        profiles = [{
            "name": "Home",
            "uuid": "123e4567-e89b-12d3-a456-426614174000",
            "type": "wifi",
            "device": "",
            "active": False,
        }]
        plan = networkmanager_wifi.freeze_connect_known(
            {
                "interface": "interface:wlan0",
                "profile": "123e4567-e89b-12d3-a456-426614174000",
            },
            status=status,
            profiles=profiles,
        )
        self.assertEqual(plan["commands"], [[
            "sudo", "-n", "--", "nmcli", "--wait", "30",
            "connection", "up", "uuid",
            "123e4567-e89b-12d3-a456-426614174000",
            "ifname", "wlan0",
        ]])
        self.assertNotIn("password", str(plan).lower())
        self.assertNotIn("psk", str(plan).lower())

    def test_connect_known_preflight_rejects_wrong_or_unready_pair(self):
        base = {
            "provider": "NetworkManager",
            "wifi_hardware": "enabled",
            "wifi_radio": "enabled",
            "devices": [
                {"interface": "wlan0", "state": "disconnected", "connection": ""}
            ],
        }
        profiles = [{
            "name": "Home",
            "uuid": "123e4567-e89b-12d3-a456-426614174000",
            "type": "wifi",
            "device": "wlan1",
            "active": True,
        }]
        inputs = {
            "interface": "interface:wlan0",
            "profile": "123e4567-e89b-12d3-a456-426614174000",
        }
        with self.assertRaisesRegex(NetworkManagerWifiError, "another interface"):
            networkmanager_wifi.freeze_connect_known(
                inputs, status=base, profiles=profiles
            )
        with self.assertRaisesRegex(NetworkManagerWifiError, "radio"):
            networkmanager_wifi.freeze_connect_known(
                inputs,
                status={**base, "wifi_radio": "disabled"},
                profiles=[{**profiles[0], "device": "", "active": False}],
            )
        with self.assertRaisesRegex(NetworkManagerWifiError, "interface"):
            networkmanager_wifi.freeze_connect_known(
                {**inputs, "interface": "interface:bad%20name"},
                status=base,
                profiles=[{**profiles[0], "device": "", "active": False}],
            )

    def test_connect_known_verification_requires_same_profile_and_interface(self):
        inputs = {
            "interface": "interface:wlan0",
            "profile": "123e4567-e89b-12d3-a456-426614174000",
        }
        active = [{
            "name": "Home",
            "uuid": "123e4567-e89b-12d3-a456-426614174000",
            "type": "wifi",
            "device": "wlan0",
            "active": True,
        }]
        evidence = networkmanager_wifi.verify_connect_known(
            inputs, profiles=active
        )
        self.assertEqual(
            evidence["check_id"], "system.network.wifi.profile.active"
        )
        self.assertEqual(evidence["observed"], "active")
        with self.assertRaisesRegex(NetworkManagerWifiError, "not active"):
            networkmanager_wifi.verify_connect_known(
                inputs, profiles=[{**active[0], "device": "", "active": False}]
            )


if __name__ == "__main__":
    unittest.main()
