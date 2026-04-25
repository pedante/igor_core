#!/usr/bin/env python3
"""Undo stack for Igor AI session CHANGE commands.

CLI:
  push <session_id> <json_entry>   — append entry to stack
  pop  <session_id>                — remove + print last entry as JSON
  list <session_id>                — print all entries as JSON array
  get-prev-occ <occ_cmd>           — print previous occ value or UNSET
"""

import json
import os
import subprocess
import sys
from pathlib import Path


def _stack_path() -> Path:
    cfg = os.environ.get("IGOR_DIR") or os.environ.get("IGOR_CONFIG") or os.environ.get("NEXUS_CONFIG")
    if not cfg:
        raise RuntimeError("IGOR_DIR not set — cannot locate undo stack")
    return Path(cfg) / "runtime" / "undo_stack.json"


def _load(session_id: str) -> dict:
    p = _stack_path()
    if p.exists():
        try:
            data = json.loads(p.read_text())
            if data.get("session_id") == session_id:
                return data
        except (json.JSONDecodeError, KeyError):
            pass
    return {"session_id": session_id, "entries": []}


def _save(data: dict) -> None:
    p = _stack_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=2))


def cmd_push(session_id: str, entry_json: str) -> None:
    entry = json.loads(entry_json)
    data = _load(session_id)
    data["entries"].append(entry)
    _save(data)


def cmd_pop(session_id: str) -> None:
    data = _load(session_id)
    if not data["entries"]:
        sys.exit(0)
    entry = data["entries"].pop()
    _save(data)
    print(json.dumps(entry))


def cmd_list(session_id: str) -> None:
    data = _load(session_id)
    print(json.dumps(data["entries"]))


def cmd_get_prev_occ(occ_cmd: str) -> None:
    """Extract the config key from an occ config:system:set command and read its current value."""
    parts = occ_cmd.strip().split()
    try:
        idx = next(i for i, p in enumerate(parts) if "config:system:set" in p)
        key = parts[idx + 1]
    except (StopIteration, IndexError):
        print("UNSET")
        return

    igor_dir = os.environ.get("IGOR_DIR") or os.environ.get("NEXUS_CONFIG") or "."
    result = subprocess.run(
        ["docker", "compose", "exec", "-T", "-u", "www-data", "app",
         "php", "occ", "config:system:get", key],
        capture_output=True, text=True, cwd=igor_dir
    )
    if result.returncode != 0:
        print("UNSET")
    else:
        print(result.stdout.strip())


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: undo_stack.py <push|pop|list|get-prev-occ> [args]", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "push" and len(sys.argv) >= 4:
        cmd_push(sys.argv[2], sys.argv[3])
    elif cmd == "pop" and len(sys.argv) >= 3:
        cmd_pop(sys.argv[2])
    elif cmd == "list" and len(sys.argv) >= 3:
        cmd_list(sys.argv[2])
    elif cmd == "get-prev-occ" and len(sys.argv) >= 3:
        cmd_get_prev_occ(sys.argv[3] if len(sys.argv) > 3 else sys.argv[2])
    else:
        print(f"Unknown command or missing args: {sys.argv[1:]}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
