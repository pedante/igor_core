"""Linux-only external deadline for a noninteractive Codex development session."""

import argparse
import json
import os
import signal
import sys
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from validation_governor import Governor, atomic_json, enable_subreaper
from validation_runner import execute, positive_seconds


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=positive_seconds, default=1800)
    parser.add_argument("--validation-seconds", type=positive_seconds, default=900)
    parser.add_argument("--new-budget", metavar="REASON", help="owner-authorized validation budget renewal")
    parser.add_argument("--output-dir", type=Path, help="new directory for session log and result")
    parser.add_argument("--codex", default="codex", help="Codex executable (also permits synthetic supervisor tests)")
    parser.add_argument("arguments", nargs=argparse.REMAINDER, help="arguments after --, beginning with exec")
    args = parser.parse_args(argv)
    arguments = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
    if not arguments or arguments[0] != "exec":
        parser.error("use -- exec PROMPT (noninteractive Codex only)")
    if args.new_budget is not None and not args.new_budget.strip():
        parser.error("--new-budget requires an owner authorization reason")
    # PR_SET_CHILD_SUBREAPER: orphaned/double-forked children remain our descendants.
    if not enable_subreaper():
        parser.error("Linux subreaper support is required for descendant enforcement")
    output = args.output_dir.resolve() if args.output_dir else Path(tempfile.mkdtemp(prefix="igor-codex-"))
    if args.output_dir:
        output.mkdir(parents=True, exist_ok=False)
    if args.new_budget:
        governor = Governor(ROOT / ".igor-governor", args.validation_seconds, args.new_budget)
        governor.close()
    cancel = threading.Event()
    previous = {}
    for signum in (signal.SIGTERM, signal.SIGINT):
        previous[signum] = signal.signal(signum, lambda *_: cancel.set())
    summary = {"status": "UNVERIFIED", "deadline_seconds": args.seconds, "exit_code": 1}
    atomic_json(output / "session.json", summary)
    print(f"Supervised session: deadline {args.seconds}s; evidence {output}", flush=True)
    try:
        # Never alter credential, privilege, sandbox or approval settings.
        command = [args.codex, "-c", "features.multi_agent=false", "-c", "agents.enabled=false",
                   "-c", "features.multi_agent_v2.enabled=false", *arguments]
        result = execute(command, ROOT, output / "session.log", args.seconds,
                         cancel_event=cancel, tree_root=os.getpid())
        code = 124 if result["status"] == "TIMEOUT" else result["returncode"] or (0 if result["status"] == "PASS" else 1)
        summary.update(result, exit_code=code)
        atomic_json(output / "session.json", summary)
        print(json.dumps(summary), flush=True)
        return code
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


if __name__ == "__main__":
    sys.exit(main())
