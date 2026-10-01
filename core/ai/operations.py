"""Bounded, private JSONL operational records. No prompts or model reasoning."""

import fcntl
import hashlib
import json
import os
import stat
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

from privacy import scrub_data, scrub_text


def audit_path():
    return Path(os.environ.get("IGOR_RUNTIME_DIR", str(
        Path(os.environ.get("IGOR_DIR", ".")) / "data/runtime"))) / "ai-audit.jsonl"


def append(event):
    level = os.environ.get("IGOR_AI_AUDIT", "metadata")
    if level == "off":
        return
    event = scrub_data(event)
    for field in ("arguments", "result", "task"):
        if field not in event:
            continue
        value = str(event[field])
        event[field + "_chars"] = len(value)
        event[field + "_sha256"] = hashlib.sha256(value.encode()).hexdigest()
        # Metadata mode retains no free text. Sanitized mode deliberately
        # bounds previews; full content is neither necessary nor safe to log.
        event[field] = value[:1200] if level == "sanitized" else "[content omitted]"
    event.update(version=1, timestamp=datetime.now(timezone.utc).isoformat())
    path = audit_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "a", encoding="utf-8") as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise ValueError("audit destination must be a regular file")
        os.fchmod(handle.fileno(), 0o600)
        fcntl.flock(handle, fcntl.LOCK_EX)
        # Bound storage without rename races or following a rotation symlink.
        if os.fstat(handle.fileno()).st_size > 2_000_000:
            handle.truncate(0)
        handle.write(json.dumps(event, ensure_ascii=True) + "\n")
        handle.flush()


def main():
    mode = sys.argv[1]
    if mode == "id":
        print(uuid.uuid4().hex)
    elif mode == "scrub":
        print(scrub_text(sys.stdin.read()), end="")
    elif mode == "status":
        catalog = json.load(sys.stdin)
        interaction_mode = os.environ.get("ai_mode", "")
        if interaction_mode not in {"guide", "assist", "executive"}:
            interaction_mode = (
                "executive" if "ai_mode" not in os.environ
                and os.environ.get("executive_mode", "false") == "true"
                else "assist"
            )
        approval = {
            "guide": "READ proposed, CHANGE confirm, DESTROY explicit YES",
            "assist": "READ automatic, CHANGE confirm, DESTROY explicit YES",
            "executive": "READ automatic, structured CHANGE automatic where policy allows, raw CHANGE confirm, DESTROY explicit YES",
        }[interaction_mode]
        print(json.dumps(scrub_data({
            "enabled": os.environ.get("IGOR_AI_ENABLED", "true") == "true",
            "provider": os.environ.get("provider", "openrouter"),
            "model": os.environ.get("model", ""),
            "mode": interaction_mode,
            "approval": approval,
            "context": os.environ.get("IGOR_AI_CONTEXT", "standard"),
            "audit": os.environ.get("IGOR_AI_AUDIT", "metadata"),
            "scrubbing": "required before transport and audit",
            "configuration": ["config/variables/ai.env", "config/variables/ai_settings.env", "secrets/ai.env"],
            "audit_file": str(audit_path()),
            **catalog,
        }), indent=2))
    elif mode == "tool":
        fields = ("event", "tool", "tier", "approval", "outcome", "exit_code",
                  "owner", "arguments", "result", "operation_id")
        values = sys.stdin.read().split("\0")
        if len(values) != len(fields) + 1:
            raise ValueError("invalid event fields")
        event = dict(zip(fields, values[:-1]))
        event["request_id"] = os.environ.get("IGOR_AI_REQUEST_ID", "")
        if event["tool"] == "run_igor_action":
            try:
                requested = json.loads(event["arguments"])
                event["action"] = requested.get("cmd", "")
            except (ValueError, AttributeError):
                pass
        if event["tool"] == "run_capability" and event["event"] == "RESULT":
            event["capability_operation_id"] = os.environ.get("IGOR_AI_CAPABILITY_OPERATION_ID", "")
            event["capability_outcome"] = os.environ.get("IGOR_AI_CAPABILITY_OUTCOME", "")
            event["verification_status"] = os.environ.get("IGOR_AI_CAPABILITY_VERIFICATION", "")
        if event["tool"] in {"host", "execute"}:
            event["execution_form"] = "unstructured"
            event["fallback_reason"] = "raw_shell_request"
            event["verification_status"] = "unavailable"
            try:
                command = json.loads(event["arguments"]).get("cmd", "")
                event["privilege_requirement"] = "explicit_sudo" if command.lstrip().startswith("sudo ") else "unknown"
            except (ValueError, AttributeError):
                event["privilege_requirement"] = "unknown"
        append(event)
    elif mode in {"last", "decision-last"}:
        path = audit_path()
        if not path.exists():
            if mode == "decision-last":
                print('{"availability":"not_recorded"}')
                return
            print("No AI operations recorded.")
            return
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, encoding="utf-8") as handle:
            records = [json.loads(line) for line in handle if line.strip()]
        if mode == "decision-last":
            record = next((r for r in reversed(records) if r.get("event") == "context_routing"), None)
            print(json.dumps(record or {"availability": "not_recorded"}))
            return
        if not records:
            print("No AI operations recorded.")
            return
        last = records[-1]
        key = "request_id" if last.get("request_id") else "operation_id"
        print(json.dumps([r for r in records if r.get(key) == last.get(key)], indent=2))
    else:
        raise ValueError("unknown operation")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as exc:
        print(f"AI audit unavailable: {type(exc).__name__}", file=sys.stderr)
        sys.exit(1)
