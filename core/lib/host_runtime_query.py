"""Bounded read-only Linux host runtime telemetry for Igor Core.

This module normalizes procfs uptime, load and swap counters. It owns no host
health thresholds, desired state or mutation path. System may publish the
normalized values as observed host facts or present them through READ
capabilities.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any

MAX_PROC_BYTES = 64 * 1024
MAX_COUNTER_KIB = (2**63 - 1) // 1024


class HostRuntimeQueryError(ValueError):
    """Invalid or unavailable host runtime telemetry."""


def _single_line(text: Any, field: str) -> str:
    if not isinstance(text, str):
        raise HostRuntimeQueryError(f"{field} is invalid")
    lines = text.splitlines()
    if len(lines) != 1 or not lines[0]:
        raise HostRuntimeQueryError(f"{field} has invalid line shape")
    if any(ord(char) < 32 and char not in "\t" for char in lines[0]):
        raise HostRuntimeQueryError(f"{field} contains control characters")
    return lines[0]


def _nonnegative_float(token: str, field: str) -> float:
    try:
        value = float(token)
    except (TypeError, ValueError) as exc:
        raise HostRuntimeQueryError(f"{field} is invalid") from exc
    if not math.isfinite(value) or value < 0 or value > 1e12:
        raise HostRuntimeQueryError(f"{field} is outside bounded range")
    return value


def parse_uptime(text: str) -> int:
    fields = _single_line(text, "uptime").split()
    if len(fields) != 2:
        raise HostRuntimeQueryError("uptime has invalid field count")
    uptime = _nonnegative_float(fields[0], "uptime seconds")
    _nonnegative_float(fields[1], "idle seconds")
    return int(uptime)


def parse_loadavg(text: str) -> tuple[float, float, float]:
    fields = _single_line(text, "load average").split()
    if len(fields) != 5:
        raise HostRuntimeQueryError("load average has invalid field count")
    loads = tuple(
        _nonnegative_float(fields[index], f"load average {index}")
        for index in range(3)
    )
    running, separator, total = fields[3].partition("/")
    if (
        not separator
        or not running.isdigit()
        or not total.isdigit()
        or int(running) < 0
        or int(total) < 1
        or int(running) > int(total)
    ):
        raise HostRuntimeQueryError("load process counts are invalid")
    if not fields[4].isdigit() or int(fields[4]) < 1:
        raise HostRuntimeQueryError("load last PID is invalid")
    return loads


def parse_swap_meminfo(text: str) -> dict[str, int]:
    if not isinstance(text, str):
        raise HostRuntimeQueryError("meminfo is invalid")
    values: dict[str, int] = {}
    for raw in text.splitlines():
        if not raw:
            continue
        if any(ord(char) < 32 and char not in "\t" for char in raw):
            raise HostRuntimeQueryError("meminfo contains control characters")
        name, separator, remainder = raw.partition(":")
        if not separator:
            raise HostRuntimeQueryError("meminfo row is malformed")
        if name not in {"SwapTotal", "SwapFree"}:
            continue
        if name in values:
            raise HostRuntimeQueryError(f"duplicate {name} is unsupported")
        fields = remainder.split()
        if len(fields) != 2 or fields[1] != "kB" or not fields[0].isdigit():
            raise HostRuntimeQueryError(f"{name} is malformed")
        kib = int(fields[0])
        if kib > MAX_COUNTER_KIB:
            raise HostRuntimeQueryError(f"{name} exceeds bounded range")
        values[name] = kib * 1024
    if set(values) != {"SwapTotal", "SwapFree"}:
        raise HostRuntimeQueryError("swap counters are unavailable")
    total = values["SwapTotal"]
    free = values["SwapFree"]
    if free > total:
        raise HostRuntimeQueryError("swap free exceeds total")
    used = total - free
    use_percent = min(100, max(0, round(used * 100 / total) if total else 0))
    return {
        "swap_total_bytes": total,
        "swap_free_bytes": free,
        "swap_used_bytes": used,
        "swap_use_percent": use_percent,
    }


def _read_bounded(path: Path, field: str) -> str:
    try:
        with path.open("rb") as stream:
            payload = stream.read(MAX_PROC_BYTES + 1)
    except OSError as exc:
        raise HostRuntimeQueryError(f"{field} is unavailable") from exc
    if len(payload) > MAX_PROC_BYTES:
        raise HostRuntimeQueryError(f"{field} exceeds bounded size")
    try:
        return payload.decode("ascii")
    except UnicodeDecodeError as exc:
        raise HostRuntimeQueryError(f"{field} is not ASCII") from exc


def query_runtime(
    *,
    uptime_path: Path = Path("/proc/uptime"),
    loadavg_path: Path = Path("/proc/loadavg"),
    meminfo_path: Path = Path("/proc/meminfo"),
) -> dict[str, Any]:
    uptime_seconds = parse_uptime(_read_bounded(uptime_path, "uptime"))
    load_1, load_5, load_15 = parse_loadavg(
        _read_bounded(loadavg_path, "load average")
    )
    swap = parse_swap_meminfo(_read_bounded(meminfo_path, "meminfo"))
    return {
        "uptime_seconds": uptime_seconds,
        "load_1": load_1,
        "load_5": load_5,
        "load_15": load_15,
        **swap,
    }


def main(argv: list[str]) -> int:
    try:
        if argv != [argv[0], "status"]:
            raise HostRuntimeQueryError("usage: host_runtime_query.py status")
        result = query_runtime()
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 0
    except HostRuntimeQueryError as exc:
        print(f"host runtime query: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
