"""Small JSON command bridge for the shell-owned, process-local System Model."""

from __future__ import annotations

import json
import sys

from system_model import ModelError, SystemModel


def main() -> int:
    try:
        if len(sys.argv) > 1 and sys.argv[1].startswith("--"):
            op = sys.argv[1][2:]
            command = {"op": op, "state": json.loads(sys.argv[2])}
            if op == "read":
                command.update(object_id=sys.argv[3], property=sys.argv[4], state_class=sys.argv[5],
                               active_owners=json.loads(sys.argv[6]))
            elif op == "list":
                command.update(object_id=sys.argv[3] or None, property=sys.argv[4] or None,
                               state_class=sys.argv[5] or None, active_owners=json.loads(sys.argv[6]))
            elif op == "observe":
                command.update(owner=sys.argv[3], observer_id=sys.argv[4], descriptor=json.loads(sys.argv[5]))
                if sys.argv[6] == "--failure":
                    command["failure"] = sys.argv[7]
                else:
                    command["envelope"] = json.loads(sys.argv[6])
            elif op == "source":
                command.update(source_id=sys.argv[3], snapshot=json.loads(sys.argv[4]))
            elif op == "health":
                command["result"] = json.loads(sys.argv[3])
            elif op == "revoke":
                command["source_id"] = sys.argv[3]
            else:
                raise ModelError("unknown model operation")
        else:
            command = json.loads(sys.argv[1]) if len(sys.argv) > 1 else json.load(sys.stdin)
        model = SystemModel(command.get("state"))
        op = command["op"]
        if op == "read":
            result = model.read(command["object_id"], command["property"], command["state_class"],
                                active_owners=set(command["active_owners"]))
        elif op == "list":
            result = {
                "facts": model.list_facts(object_id=command.get("object_id"), prop=command.get("property"),
                                          state_class=command.get("state_class"), active_owners=set(command["active_owners"])),
                "responsibilities": [r for r in model.responsibilities if not command.get("object_id") or r["object_id"] == command["object_id"]],
                "observers": model.attempts,
                "health": {key: value for key, value in model.health.items()
                           if value.get("owner") in set(command["active_owners"])},
            }
        elif op == "observe":
            descriptor = command["descriptor"]
            if command.get("failure"):
                model.observer_failure(descriptor, command["owner"], command["observer_id"], command["failure"])
            else:
                try:
                    model.observe(descriptor, command["owner"], command["observer_id"], command["envelope"])
                except (ModelError, KeyError, TypeError) as exc:
                    model.observer_failure(descriptor, command["owner"], command["observer_id"], f"malformed:{exc}")
                    print(json.dumps({"state": model.dump(), "error": str(exc)}))
                    return 0
            result = {"state": model.dump()}
        elif op == "source":
            model.upsert_from_source(command["source_id"], command["snapshot"])
            result = {"state": model.dump()}
        elif op == "health":
            health = command["result"]
            if not isinstance(health, dict) or not all(k in health for k in ("check_id", "owner", "object_id", "status", "used_facts", "evaluated_at")):
                raise ModelError("invalid health result")
            model.health[health["check_id"]] = health
            result = {"state": model.dump()}
        elif op == "revoke":
            model.revoke_source(command["source_id"])
            result = {"state": model.dump()}
        else:
            raise ModelError("unknown model operation")
        print(json.dumps(result, separators=(",", ":")))
        return 0
    except (ValueError, KeyError, TypeError) as exc:
        print(f"model bridge: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
