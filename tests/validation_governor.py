"""Development-only budgets and evidence reuse; no Igor runtime imports."""

import ctypes
import fcntl
import hashlib
import importlib.metadata
import json
import os
import platform
import re
import shutil
import signal
import sys
import time
from pathlib import Path


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def file_digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def atomic_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def enable_subreaper():
    return (sys.platform.startswith("linux") and
            ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) == 0)


class ProcessTree:
    """Track Linux descendants, including children that create a new session.

    The external supervisor also acts as a subreaper, retaining daemonized children.
    Start times prevent signalling a recycled PID.
    """

    def __init__(self, root):
        self.root = root
        self.seen = {}

    def capture(self):
        processes = {}
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            try:
                fields = (entry / "stat").read_text().rsplit(")", 1)[1].split()
                processes[int(entry.name)] = (int(fields[1]), fields[19])
            except (OSError, ValueError, IndexError):
                continue
        parents = {self.root, *[pid for pid, start in self.seen.items()
                               if pid in processes and processes[pid][1] == start]}
        while True:
            children = {pid for pid, (parent, _) in processes.items() if parent in parents}
            if children <= parents:
                break
            parents.update(children)
        for pid in parents - {self.root}:
            if pid in processes:
                self.seen[pid] = processes[pid][1]

    def kill(self, signum):
        self.capture()
        for pid, start in self.seen.items():
            try:
                fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
                if fields[19] == start:
                    os.kill(pid, signum)
            except (OSError, ValueError, IndexError):
                pass

    def cleanup(self):
        self.kill(signal.SIGTERM)
        self.kill(signal.SIGKILL)


class BudgetError(ValueError):
    pass


def requires_fresh_security(plan):
    """Security suites may never be satisfied by cached execution evidence."""
    protected = re.compile(r"security|safety|privilege|approval|privacy|secret|scrubb|"
                           r"request_boundary|capability|input_candidates|transactions|trust_boundary")
    return any(protected.search(name) for group in plan if group["kind"] in ("pytest", "bats", "bash")
               for name in group["files"])


class Governor:
    """One locked ledger per checkout; crashes consume the reserved remainder."""

    def __init__(self, directory, seconds, reason=None):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.directory = directory
        self.lock = (directory / "lock").open("a")
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close()
            raise BudgetError("Another governed validation is active") from None
        self.path = directory / "budget.json"
        self.started = None
        try:
            self.state = json.loads(self.path.read_text()) if self.path.exists() else {}
            if reason or not self.state:
                evidence_dirs = self.state.get("evidence_dirs", [])
                self.state = {"remaining_seconds": seconds, "authorization": reason or "default budget",
                              "attempts": {}, "broad": [], "evidence_dirs": evidence_dirs}
                atomic_json(self.path, self.state)
        except Exception:
            self.close()
            raise

    def exclusions(self):
        return [self.directory.resolve(), *map(Path, self.state["evidence_dirs"])]

    def note_evidence(self, output_dir):
        name = str(output_dir.resolve())
        if name not in self.state["evidence_dirs"]:
            self.state["evidence_dirs"].append(name)
            atomic_json(self.path, self.state)

    def begin(self, key, candidate, mode, output_dir, rerun_reason=None, started=None):
        if self.state["remaining_seconds"] <= 0:
            raise BudgetError("Validation budget exhausted; owner must authorize --new-budget REASON")
        count = self.state["attempts"].get(key, 0)
        if mode == "full" and candidate in self.state["broad"]:
            raise BudgetError("Broad validation already attempted for this candidate; authorize a new budget")
        if count and (not rerun_reason or count >= 2 or mode == "full"):
            raise BudgetError("Unchanged validation already attempted; reuse evidence or justify one targeted rerun")
        self.allowance = self.state["remaining_seconds"]
        self.state["remaining_seconds"] = 0  # Fail closed if killed before settlement.
        self.state["attempts"][key] = count + 1
        if mode == "full":
            self.state["broad"].append(candidate)
        self.note_evidence(output_dir)
        self.state["last_rerun_reason"] = rerun_reason
        self.started = started if started is not None else time.monotonic()
        atomic_json(self.path, self.state)
        return self.started + self.allowance

    def finish(self, exhausted=False):
        if self.started is not None:
            self.state["remaining_seconds"] = (0 if exhausted else
                                               max(0, self.allowance - (time.monotonic() - self.started)))
            atomic_json(self.path, self.state)
            self.started = None

    def close(self):
        self.lock.close()

    def reuse(self, key):
        path = self.directory / f"{key}.json"
        if not path.exists():
            return None
        try:
            record = json.loads(path.read_text())
            if all(file_digest(name) == expected for name, expected in record["files"].items()):
                summary = json.loads(Path(record["summary"]).read_text())
                if summary["run_state"] == "complete":
                    return summary
        except (OSError, ValueError, KeyError, TypeError):
            pass
        return None

    def remember(self, key, output_dir, summary):
        # Failures may be reused as failures. Partial/timeout/unavailable evidence cannot be reused.
        if summary["run_state"] != "complete" or any(
            row["classification"] in ("ERROR", "TOOL_UNAVAILABLE", "TIMEOUT_NEW", "TIMEOUT_BASELINE")
            for row in summary["results"]
        ):
            return
        paths = [output_dir / "summary.json"]
        for group in summary["groups"]:
            paths.extend(Path(group[name]) for name in ("log", "report") if group.get(name))
        record = {"summary": str(output_dir / "summary.json"),
                  "files": {str(path): file_digest(path) for path in paths}}
        atomic_json(self.directory / f"{key}.json", record)


def fingerprint(root, names, plan, args, env, exclusions):
    """Conservative whole source tree, plan, baseline, tools and local environment identity.

    No guessed dependency graph: unrelated source changes may cause extra invalidation.
    Only digests are persisted, never ambient environment or source contents.
    """
    sources = []
    for name in sorted(set(names)):
        path = root / name
        if any(path.absolute().is_relative_to(directory) for directory in exclusions):
            continue
        sources.append((name, file_digest(path) if path.is_file() else "deleted",
                        path.stat().st_mode if path.exists() else 0))
    tools = []
    for command in (args.python, args.ruff, args.shellcheck, args.bats, "bash", "rg", "git"):
        path = shutil.which(command)
        tools.append((command, path, file_digest(path) if path else "unavailable"))
    packages = []
    for dist in importlib.metadata.distributions():
        files = []
        for name in dist.files or ():
            path = dist.locate_file(name)
            if path.is_file() and path.suffix != ".pyc":
                stat = path.stat()
                files.append((str(path), stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns))
        packages.append((dist.metadata["Name"], dist.version, sorted(files)))
    packages.sort()
    # Private directories are fresh on every run, so compare their contract rather than random paths.
    private = {"HOME", "TMPDIR", "IGOR_DATA_DIR", "IGOR_DIR", "IGOR_VALIDATION_REPORT"}
    environment = {key: value for key, value in env.items() if key not in private and not key.startswith("XDG_")}
    candidate = digest({"source": sources, "tools": tools, "packages": packages,
                        "environment": environment, "platform": platform.platform(),
                        "baseline": file_digest(args.baseline), "environment_key": args.environment_key})
    key = digest({"candidate": candidate, "plan": plan, "mode": args.mode, "jobs": args.jobs,
                  "limits": [args.command_timeout, args.group_timeout, args.interactive_timeout,
                             args.slow_timeout, args.bats_timeout], "preflight": args.fail_fast_preflight})
    return candidate, key
