"""Focused S8.1 tests for bounded Linux host runtime telemetry."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core" / "lib"))

from host_runtime_query import (  # noqa: E402
    HostRuntimeQueryError,
    MAX_PROC_BYTES,
    parse_loadavg,
    parse_swap_meminfo,
    parse_uptime,
    query_runtime,
)


class HostRuntimeQueryTests(unittest.TestCase):
    def test_uptime_is_bounded_nonnegative_seconds(self):
        self.assertEqual(parse_uptime("123.99 456.12\n"), 123)
        for value in (
            "-1.0 1.0\n",
            "nan 1.0\n",
            "inf 1.0\n",
            "1.0\n",
            "1.0 2.0 3.0\n",
            "1.0 2.0\nextra\n",
        ):
            with self.subTest(value=value):
                with self.assertRaises(HostRuntimeQueryError):
                    parse_uptime(value)

    def test_loadavg_normalizes_three_load_values(self):
        self.assertEqual(
            parse_loadavg("0.25 1.50 2.75 2/100 4242\n"),
            (0.25, 1.5, 2.75),
        )
        for value in (
            "nan 1 2 1/2 3\n",
            "1 2 3 3/2 4\n",
            "1 2 3 1/x 4\n",
            "1 2 3 1/2 0\n",
            "1 2 3 1/2\n",
        ):
            with self.subTest(value=value):
                with self.assertRaises(HostRuntimeQueryError):
                    parse_loadavg(value)

    def test_swap_meminfo_is_exact_and_handles_no_swap(self):
        result = parse_swap_meminfo(
            "MemTotal:       1000 kB\n"
            "SwapTotal:      2048 kB\n"
            "SwapFree:        512 kB\n"
        )
        self.assertEqual(result["swap_total_bytes"], 2048 * 1024)
        self.assertEqual(result["swap_free_bytes"], 512 * 1024)
        self.assertEqual(result["swap_used_bytes"], 1536 * 1024)
        self.assertEqual(result["swap_use_percent"], 75)

        zero = parse_swap_meminfo("SwapTotal: 0 kB\nSwapFree: 0 kB\n")
        self.assertEqual(zero["swap_use_percent"], 0)

    def test_swap_meminfo_fails_closed_on_malformed_or_conflicting_rows(self):
        cases = (
            "SwapTotal: 1 kB\n",
            "SwapTotal: 1 MB\nSwapFree: 0 kB\n",
            "SwapTotal: 1 kB\nSwapTotal: 1 kB\nSwapFree: 0 kB\n",
            "SwapTotal: 1 kB\nSwapFree: 2 kB\n",
            "malformed row\nSwapTotal: 1 kB\nSwapFree: 0 kB\n",
        )
        for value in cases:
            with self.subTest(value=value):
                with self.assertRaises(HostRuntimeQueryError):
                    parse_swap_meminfo(value)

    def test_query_runtime_reads_only_bounded_proc_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            uptime = root / "uptime"
            loadavg = root / "loadavg"
            meminfo = root / "meminfo"
            uptime.write_text("12.7 30.0\n", encoding="ascii")
            loadavg.write_text("0.10 0.20 0.30 1/5 99\n", encoding="ascii")
            meminfo.write_text(
                "SwapTotal: 1024 kB\nSwapFree: 768 kB\n",
                encoding="ascii",
            )
            self.assertEqual(
                query_runtime(
                    uptime_path=uptime,
                    loadavg_path=loadavg,
                    meminfo_path=meminfo,
                ),
                {
                    "uptime_seconds": 12,
                    "load_1": 0.1,
                    "load_5": 0.2,
                    "load_15": 0.3,
                    "swap_total_bytes": 1024 * 1024,
                    "swap_free_bytes": 768 * 1024,
                    "swap_used_bytes": 256 * 1024,
                    "swap_use_percent": 25,
                },
            )

            meminfo.write_bytes(b"x" * (MAX_PROC_BYTES + 1))
            with self.assertRaisesRegex(HostRuntimeQueryError, "bounded size"):
                query_runtime(
                    uptime_path=uptime,
                    loadavg_path=loadavg,
                    meminfo_path=meminfo,
                )


if __name__ == "__main__":
    unittest.main()
