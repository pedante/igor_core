"""System swap interpretation; collection and model authority remain in Core."""

from __future__ import annotations

import json
import sys
from datetime import UTC, datetime

PROPERTIES = ("swap.total_bytes", "swap.free_bytes", "swap.used_bytes")
EVIDENCE = ["/proc/meminfo:SwapTotal", "/proc/meminfo:SwapFree"]


def evaluate(facts: dict) -> dict:
    """Evaluate the supplied snapshot, never probe or refresh it."""
    used = [
        {"key": ["host:local", prop, "observed"],
         "recorded_at": fact.get("recorded_at"), "availability": fact.get("availability")}
        for prop, fact in facts.items() if isinstance(fact, dict)
    ]
    status, code, message = "UNKNOWN", "swap_unavailable", "Swap counters are unavailable"
    rows = [facts.get(prop) for prop in PROPERTIES]
    if any(not isinstance(fact, dict) for fact in rows):
        if any(prop in facts and not isinstance(facts[prop], dict) for prop in PROPERTIES):
            code, message = "swap_malformed", "Swap facts are malformed"
    elif any(fact.get("availability") == "stale" for fact in rows):
        code, message = "swap_stale", "Swap counters are stale"
    elif all(fact.get("availability") == "known" for fact in rows):
        total, free, consumed = [fact.get("value") for fact in rows]
        if (any(type(value) is not int or value < 0 for value in (total, free, consumed))
                or free + consumed != total
                or any(not isinstance(fact.get("recorded_at"), str)
                       or not fact["recorded_at"] for fact in rows)
                or any(fact["recorded_at"] != rows[0]["recorded_at"] for fact in rows)):
            code, message = "swap_malformed", "Swap counters are malformed or inconsistent"
        elif total == 0:
            status, code, message = "SKIP", "swap_not_configured", "No swap is configured"
        else:
            # Display rounding must not move the established 60/85% boundaries.
            percent = consumed * 100 // total
            if consumed * 100 >= total * 85:
                status, code = "FAIL", "swap_critical"
            elif consumed * 100 >= total * 60:
                status, code = "WARN", "swap_high"
            else:
                status, code = "OK", "swap"
            message = f"Swap {percent}% used ({consumed}/{total} bytes)"
    return {"status": status, "finding_code": code, "message": message,
            "used_facts": used, "evidence": EVIDENCE}


def runtime_status(row: dict) -> dict:
    observed_at = datetime.now(UTC).isoformat().replace("+00:00", "Z")
    facts = {prop: {"value": row[prop.replace(".", "_", 1)],
                    "availability": "known", "recorded_at": observed_at}
             for prop in PROPERTIES}
    health = evaluate(facts)
    return {**row, "source": "core.host.runtime", "observed_at": observed_at,
            "observation_scope": "current_read",
            "swap_health_status": health["status"],
            "swap_finding_code": health["finding_code"],
            "swap_health_message": health["message"]}


def main() -> int:
    try:
        value = json.load(sys.stdin)
        if sys.argv[1] == "check":
            result = evaluate(value["facts"])
        elif sys.argv[1] == "runtime":
            result = runtime_status(value)
        else:
            raise ValueError("unsupported swap request")
        print(json.dumps({"status": "ok", "result": result}, separators=(",", ":")))
        return 0
    except (KeyError, ValueError, TypeError, AttributeError):
        print(json.dumps({"status": "error", "error": {
            "code": "invalid_input", "message": "Invalid swap health input"}}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
