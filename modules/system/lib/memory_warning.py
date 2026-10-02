"""System memory health consumer. Desired configuration is never read here."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def consumer() -> dict:
    package = Path(__file__).resolve().parents[1]
    contract = json.loads((package / "contracts/host.json").read_text())
    field = next(field for row in contract["contributions"] if row["kind"] == "configuration"
                 for field in row["schema"]["fields"]
                 if field["id"] == "system.memory.warning_threshold_mib")
    value = int(os.environ.get("IGOR_SYSTEM_MEMORY_WARNING_MIB", field["default"]))
    revision = int(os.environ.get("IGOR_SYSTEM_MEMORY_WARNING_REVISION", "0"))
    state = os.environ.get("IGOR_SYSTEM_MEMORY_WARNING_STATE", "0" * 64)
    if (not field["minimum"] <= value <= field["maximum"] or revision < 0 or
            len(state) != 64 or any(c not in "0123456789abcdef" for c in state)):
        raise ValueError("invalid memory consumer state")
    return {"value": value, "revision": revision, "state": state,
            "consumer_id": os.environ.get("IGOR_SYSTEM_MEMORY_CONSUMER_ID", "unbound"),
            "source": "system.host.memory.health.consumer"}


def main() -> int:
    try:
        request = json.loads(sys.argv[2])
        action = sys.argv[1]
        expected = {"check": "host.memory.health", "apply": "system.memory.warning.apply",
                    "readback": "system.memory.warning.readback"}[action]
        if request.get("api_version") != 2 or request.get("contribution_id") != expected:
            raise ValueError("wrong memory request")
        if action == "apply":
            # The isolated module handler validates application intent. Core
            # alone can consume this reviewed result in the parent process.
            result = request["input"]
            if set(result) != {"value", "revision", "state"}:
                raise ValueError("invalid application input")
            if type(result["value"]) is not int or not 81 <= result["value"] <= 4096:
                raise ValueError("invalid warning value")
        else:
            runtime = consumer()
            if action == "readback":
                result = runtime
            else:
                fact = request["input"]["facts"]["memory.available_bytes"]
                if not isinstance(fact, dict):
                    raise ValueError("invalid fact")
                availability = fact.get("availability")
                used = [{"key": ["host:local", "memory.available_bytes", "observed"],
                         "recorded_at": fact.get("recorded_at"), "availability": availability}]
                if availability != "known":
                    status, code, message = "UNKNOWN", "memory_unknown", f"Available memory is {availability or 'unknown'}"
                else:
                    value = fact.get("value")
                    if type(value) is not int or value < 0:
                        raise ValueError("invalid available bytes")
                    mib = value // (1024 * 1024)
                    if value < 80 * 1024 * 1024:
                        status, code, message = "CRITICAL", "low_ram", f"Only {mib}MiB RAM available — critical"
                    elif value < runtime["value"] * 1024 * 1024:
                        status, code, message = "WARN", "ram_low", f"Only {mib}MiB RAM available — low"
                    else:
                        status, code, message = "OK", "ram", f"{mib}MiB RAM available"
                result = {"status": status, "finding_code": code, "message": message,
                          "used_facts": used, "evidence": ["/proc/meminfo:MemAvailable",
                          f"warning_mib={runtime['value']};revision={runtime['revision']}"]}
        print(json.dumps({"status": "ok", "result": result}, separators=(",", ":")))
        return 0
    except (KeyError, ValueError, TypeError, OSError) as exc:
        print(json.dumps({"status": "error", "error": {"code": "invalid_input", "message": str(exc)}}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
