"""Bounded developer validation with explicit reviewed baseline comparison.

Usage: tests/validate.sh focused|affected|full [--base REF] [--test FILE::NODE]
Git selection includes committed changes since the local merge base and all
staged, unstaged and untracked changes. --changed-file adds simulated changes
for mapping proofs; --dry-run emits the plan without executing it. Deleted
paths select affected domains but are not linted. Focused finds changed tests
and conventional test_<python_module>.py matches; supply other feature tests.

Full mirrors the canonical run_all.sh groups (legacy Bash, rendering, Core,
module and integration BATS) and additionally discovers every test_*.py under
tests. Rendering identities execute once. Each test file is a bounded subprocess.
--jobs defaults to 1; higher values overlap reviewed private-state files
with one serial lane for remaining tests, after a serial preflight barrier.
Every subprocess has private home/temp/data/cache directories and controlled
Igor/Python configuration. Baseline classification policy is unchanged.
Persistent development budgets default to 900s total and 240s/command;
CI defaults to 10800s total and 1200s/command and executes gates freshly.
Unchanged local non-security evidence is reused with its original exit code.
File limits are 600s/file, 60s for interactive TUI Python files, and 1200s
for System configuration/administration vertical slices. BATS' native per-test
watchdog is disabled by default because
released BATS 1.13.0 can hold a fast-failing runner open until the watchdog
deadline; the harness' process-group timeout remains authoritative. A native
BATS timeout can still be opted into explicitly. These are ceilings, not
expected durations. No full run is ever triggered by focused/affected. CI and
local validation share this entry point.

Raw output and atomic summary.json checkpoints live in a unique temporary
directory by default; --output-dir must name a new directory. Running/interrupted
evidence includes active/pending groups and cannot claim a successful full run.
Progress heartbeats default to 15 seconds; summaries include per-test timings,
slowest groups/tests and run-wide child CPU time. Counts refer to test identities
and structural/tool groups. Raw group outcomes remain in groups. A new failure,
new timeout, error or unavailable required tool makes exit nonzero. Only exact
reviewed failure/timeout identities can match validation_baseline.json. Only
explicit test-level skip permissions can produce ENV_SKIP; host Docker/systemd
availability is never probed. No baseline is generated or updated by a run.
Markdown checks verify inline local file links, excluding fenced examples;
anchors, reference-style links and external URLs remain outside this check.
"""

import argparse
import concurrent.futures
import json
import math
import os
import re
import resource
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

from validation_domains import affected_tests
from validation_environment import PERMITTED_SKIPS
from validation_governor import (
    Governor,
    ProcessTree,
    digest,
    enable_subreaper,
    fingerprint,
    requires_fresh_security,
)
from validation_reports import bats_observations, group_observation, pytest_observations
from validation_results import compare_results, load_baseline

ROOT = Path(__file__).resolve().parents[1]
SHELLCHECK_FLAGS = ["--severity=warning", "--exclude=SC2086,SC1090,SC1091,SC2034", "--shell=bash"]
PREFLIGHT_KINDS = frozenset({"structure", "ruff", "shellcheck", "syntax", "bats-count", "module-contract"})
INTERACTIVE_PYTEST_FILES = frozenset({"test_ai_tui.py", "test_ai_tui_step7.py"})
# Reviewed service contracts and Bash safety fixtures: state is in private
# temporary directories, host operations are mocked, and repository files are
# only read. New files remain serial until fixtures receive the same review.
PARALLEL_PYTEST_FILES = frozenset({
    "tests/test_local_learning.py", "tests/test_knowledge_artifacts.py",
    "tests/test_baselines.py", "tests/test_capability_runtime.py",
    "tests/test_deployments.py", "tests/test_deployment_attachment.py",
    "tests/test_domain_event.py", "tests/test_module_contract.py",
    "tests/test_context_engine.py", "tests/core/test_system_model.py",
})
PARALLEL_BATS_FILES = frozenset({
    "tests/core/test_safety.bats", "tests/core/test_scrubbing.bats",
    "tests/core/test_ai_modes.bats", "tests/core/test_ai_privilege.bats",
    "tests/core/test_safety_dispatch.bats",
})


def execute(command, root, log, seconds, env=None, cancel_event=None, tree_root=None):
    """Write directly to disk (no pipe deadlocks); bound and clean the process group."""
    started = time.monotonic()
    enable_subreaper()
    status = "ERROR"
    returncode = None
    with log.open("w", encoding="utf-8") as output:
        output.write(f"Command: {command!r}\n")
        output.flush()
        if seconds <= 0:
            output.write("TIMEOUT: budget exhausted before dispatch; command not executed\n")
            return {"status": "TIMEOUT", "returncode": None,
                    "elapsed_seconds": round(time.monotonic() - started, 3), "log": str(log)}
        try:
            process = subprocess.Popen(command, cwd=root, stdout=output, stderr=subprocess.STDOUT,
                                       env=env, start_new_session=True)
        except FileNotFoundError as error:
            output.write(f"Required tool unavailable: {error}\n")
            status = "TOOL_UNAVAILABLE"
        except OSError as error:
            output.write(f"Runner error: {error}\n")
        else:
            tree = ProcessTree(tree_root or process.pid)
            try:
                while True:
                    tree.capture()
                    if cancel_event is not None and cancel_event.is_set():
                        output.write("\nINTERRUPTED: validation cancelled\n")
                        break
                    remaining = seconds - (time.monotonic() - started)
                    if remaining <= 0:
                        raise subprocess.TimeoutExpired(command, seconds)
                    try:
                        returncode = process.wait(timeout=min(remaining, 0.05))
                        status = "PASS" if returncode == 0 else "FAIL"
                        break
                    except subprocess.TimeoutExpired:
                        continue
            except subprocess.TimeoutExpired:
                output.write(f"\nTIMEOUT: process group exceeded {seconds}s\n")
                status = "TIMEOUT"
            finally:
                tree.cleanup()
                if status == "TIMEOUT" or cancel_event is not None and cancel_event.is_set():
                    # The governor stops the complete run on timeout. Include
                    # adopted double-forked descendants, across parallel lanes.
                    ProcessTree(os.getpid()).cleanup()
                # Also remove children left behind by successful/failed fixtures.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=1)
                    except subprocess.TimeoutExpired:
                        pass
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
    return {"status": status, "returncode": returncode,
            "elapsed_seconds": round(time.monotonic() - started, 3), "log": str(log)}


def git(root, *args):
    result = subprocess.run(["git", *args], cwd=root, capture_output=True, timeout=30, check=True)
    return result.stdout


def changed_files(root, base):
    """Committed changes since merge base, staged/unstaged changes, and untracked files."""
    names = set()
    for output in (git(root, "diff", "--name-only", "-z", "--no-renames", f"{base}...HEAD"),
                   git(root, "diff", "--name-only", "-z", "--no-renames", "HEAD"),
                   git(root, "ls-files", "--others", "--exclude-standard", "-z")):
        names.update(os.fsdecode(name) for name in output.split(b"\0") if name)
    return sorted(names)


def local_path(root, name):
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f"Path outside repository: {name}")
    return path


def documentation_errors(path, root):
    """Check local Markdown file references; anchors and external URLs are not checked."""
    content = re.sub(r"```.*?```", "", path.read_text(encoding="utf-8"), flags=re.DOTALL)
    errors = []
    for target in re.findall(r"\]\(([^)]+)\)", content):
        target = target.strip().strip("<>").split("#", 1)[0]
        if not target or re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target):
            continue
        destination = root / target.lstrip("/") if target.startswith("/") else path.parent / target
        if not destination.exists():
            errors.append(f"{path.relative_to(root)}: missing reference {target}")
    return errors


def structural_checks(root, changed):
    errors = []
    checked = []
    for name in changed:
        path = local_path(root, name)
        if not path.is_file():
            continue  # Deleted files still participate in affected-domain selection.
        if path.suffix == ".py":
            compile(path.read_bytes(), name, "exec")
            checked.append(name)
        elif path.suffix == ".json":
            json.loads(path.read_text(encoding="utf-8"))
            checked.append(name)
        elif path.suffix == ".md":
            errors.extend(documentation_errors(path, root))
            checked.append(name)
    return checked, errors


def make_plan(root, mode, changed, supplied=()):
    """Plan all required groups first so missing tools cannot silently omit coverage."""
    domains, affected = affected_tests(changed, root)
    tests = set(supplied)
    for name in supplied:
        if Path(name.split("::", 1)[0]).suffix not in (".py", ".bats"):
            raise ValueError(f"Expected a Python node/file or BATS file: {name}")
    # Focused infers direct test changes and conventional test_<module>.py matches.
    tests.update(name for name in changed if name.startswith("tests/") and
                 (Path(name).name.startswith("test_") and Path(name).suffix in (".py", ".bats")))
    for name in changed:
        candidate = f"tests/test_{Path(name).stem}.py"
        if Path(name).suffix == ".py" and (root / candidate).is_file():
            tests.add(candidate)
    if mode == "affected":
        tests.update(affected)
    plan = [{"id": "structure", "kind": "structure", "files": list(changed)}]
    modules = set()
    for name in changed:
        parts = Path(name).parts
        if len(parts) >= 3 and parts[0] == "modules" and (
                parts[2] == "module.conf" or (parts[2] == "contracts" and name.endswith(".json"))) and (
                root / "modules" / parts[1] / "module.conf").is_file():
            modules.add(f"modules/{parts[1]}")
    for module in sorted(modules):
        plan.append({"id": f"contract:{module}", "kind": "module-contract", "files": [module]})
    python = sorted(name for name in changed if name.endswith(".py") and (root / name).is_file())
    shell = sorted(name for name in changed if Path(name).suffix in (".sh", ".bash", ".bats")
                   and (root / name).is_file())
    if python:
        plan.append({"id": "ruff", "kind": "ruff", "files": python})
    if shell:
        plan.append({"id": "shellcheck", "kind": "shellcheck", "files": shell})
        for name in shell:
            plan.append({"id": f"syntax:{name}", "kind": "bats-count" if name.endswith(".bats")
                         else "syntax", "files": [name]})
    if mode == "full":
        plan.append({"id": "canonical:bash", "kind": "bash", "files": ["tests/test_igor_core.sh"]})
        plan.append({"id": "canonical:rendering", "kind": "pytest", "files": ["tests/test_ai_render.py"]})
        for directory in ("core", "modules", "integration"):
            files = sorted(str(path.relative_to(root)) for path in (root / "tests" / directory).glob("*.bats"))
            if not files:
                raise ValueError(f"Canonical BATS suite missing or empty: {directory}")
            for name in files:
                plan.append({"id": f"canonical:{directory}:{name}", "kind": "bats", "files": [name]})
        tests = {str(path.relative_to(root)) for path in (root / "tests").rglob("test_*.py")}
        if not tests:
            raise ValueError("Complete Python suite missing or empty")
        # The canonical rendering group already exercises these identities.
        tests.discard("tests/test_ai_render.py")
    for name in sorted(tests):
        if not local_path(root, name.split("::", 1)[0]).is_file():
            # A removed test is not executable; explicit missing targets fail closed.
            if name in supplied:
                raise ValueError(f"Explicit test does not exist: {name}")
            continue
        kind = "bats" if name.endswith(".bats") else "pytest"
        plan.append({"id": f"{kind}:{name}", "kind": kind, "files": [name]})
    return domains, plan


def group_environment(root, output_dir, index, python):
    """Private process state; ambient developer configuration is not test input."""
    work = output_dir / "work" / f"{index:03d}"
    directories = {name: work / name for name in ("home", "tmp", "config", "cache", "data", "runtime", "igor-data")}
    for directory in directories.values():
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    secret_name = re.compile(r"secret|token|password|credential|(?:api|private|access)[_-]?key|(?:^|_)key(?:$|_)", re.IGNORECASE)
    env = {key: value for key, value in os.environ.items()
           if not key.upper().startswith(("IGOR_", "NEXUS_", "PYTEST_", "PYTHON", "BASH_FUNC_",
                                          "OPENROUTER_", "ANTHROPIC_", "OLLAMA_"))
           and key.upper() not in ("AI_MODE", "EXECUTIVE_MODE", "BASH_ENV", "ENV")
           and not secret_name.search(key)}
    executable = shutil.which(python)
    if executable:
        # Preserve virtualenv symlinks: resolving their target would select the
        # host interpreter instead of the sibling python3 used by Bash fixtures.
        interpreter_dir = Path(executable).absolute().parent
        if (interpreter_dir / "python3").is_file():
            env["PATH"] = str(interpreter_dir) + os.pathsep + env.get("PATH", os.defpath)
    env.update(IGOR_DIR=str(root), IGOR_DATA_DIR=str(directories["igor-data"]),
               HOME=str(directories["home"]), TMPDIR=str(directories["tmp"]),
               XDG_CONFIG_HOME=str(directories["config"]), XDG_CACHE_HOME=str(directories["cache"]),
               XDG_DATA_HOME=str(directories["data"]), XDG_RUNTIME_DIR=str(directories["runtime"]),
               PYTHONDONTWRITEBYTECODE="1", PYTEST_DISABLE_PLUGIN_AUTOLOAD="1")
    return env, work


def run_group(group, root, output_dir, index, args):
    kind = group["kind"]
    log = output_dir / f"{index:03d}-{kind}.log"
    files = group["files"]
    if kind == "structure":
        started = time.monotonic()
        try:
            checked, errors = structural_checks(root, files)
            log.write_text(json.dumps({"checked": checked, "errors": errors}, indent=2) + "\n")
            status = "FAIL" if errors else "PASS"
        except (ValueError, OSError, SyntaxError) as error:
            log.write_text(f"{type(error).__name__}: {error}\n")
            status = "FAIL"
        return {**group, "status": status, "returncode": None,
                "elapsed_seconds": round(time.monotonic() - started, 3), "log": str(log)}
    commands = {
        "ruff": [args.ruff, "check", *files],
        "shellcheck": [args.shellcheck, *SHELLCHECK_FLAGS, *files],
        "syntax": ["bash", "-n", *files],
        "bats-count": [args.bats, "--count", *files],
        "bash": ["bash", *files],
        "bats": [args.bats, "--tap", "--timing", *files],
        "pytest": [args.python, "-m", "pytest", "-p", "validation_pytest", "-q", *files],
        "module-contract": [args.python, "core/lib/module_contract.py", "validate", *files],
    }
    env, work = group_environment(root, output_dir, index, args.python)
    # BATS 1.13.0 issue #1206: a native watchdog can keep a fast-failing suite
    # alive until the timeout expires. The outer process-group timeout already
    # fails closed, so do not enable the defective watchdog unless explicitly
    # requested for a targeted reproduction.
    env.pop("BATS_TEST_TIMEOUT", None)
    if args.bats_timeout:
        env["BATS_TEST_TIMEOUT"] = str(args.bats_timeout)
    report_path = output_dir / f"{index:03d}-pytest.jsonl"
    if kind == "pytest":
        env["IGOR_VALIDATION_REPORT"] = str(report_path)
        env["PYTHONPATH"] = str(Path(__file__).parent)
        commands[kind].extend(["--basetemp", str(work / "pytest-tmp"),
                               "-o", f"cache_dir={work / 'pytest-cache'}", "-o", "addopts="])
    seconds = args.group_timeout
    if kind == "pytest" and any(
        Path(name.split("::", 1)[0]).name in INTERACTIVE_PYTEST_FILES for name in files
    ):
        seconds = min(seconds, args.interactive_timeout)
    if any(Path(name.split("::", 1)[0]).name in ("test_system_configuration_workflow.py",
                                                   "test_system_admin_surface.bats") for name in files):
        seconds = args.slow_timeout
    seconds = min(seconds, getattr(args, "command_timeout", seconds))
    deadline = getattr(args, "deadline", None)
    if deadline is not None:
        seconds = min(seconds, max(0, deadline - time.monotonic()))
    cancellation = getattr(args, "cancel_event", None)
    result = (execute(commands[kind], root, log, seconds, env, cancellation) if cancellation is not None
              else execute(commands[kind], root, log, seconds, env))
    content = log.read_text(encoding="utf-8", errors="replace")
    if kind == "pytest" and "No module named pytest" in content:
        result["status"] = "TOOL_UNAVAILABLE"
    # BATS continues after a native per-test timeout; retain that distinction.
    if kind == "bats":
        result["native_timeout_count"] = len(re.findall(r"^not ok .* # timeout after \d+s", content, re.MULTILINE))
        result["native_failure_count"] = len(re.findall(r"^not ok ", content, re.MULTILINE)) - result["native_timeout_count"]
        result["runner_skip_count"] = len(re.findall(r"^ok .* # skip", content, re.MULTILINE | re.IGNORECASE))
        if result["native_timeout_count"] and result["status"] == "FAIL":
            result["status"] = "TIMEOUT"
    combined = {**group, **result}
    try:
        if kind == "pytest":
            combined["report"] = str(report_path)
            combined["observations"] = pytest_observations(combined, report_path, require_collection=True)
        elif kind == "bats":
            combined["observations"] = bats_observations(combined)
    except (ValueError, OSError, KeyError, TypeError) as error:
        combined["observations"] = [group_observation(combined, "ERROR", f"Invalid runner report: {error}")]
    return combined


def positive_seconds(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("timeout must be finite and positive")
    return number


def nonnegative_int(value):
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("timeout must be zero or positive")
    return number


def positive_jobs(value):
    number = int(value)
    if number < 1 or number > 32:
        raise argparse.ArgumentTypeError("jobs must be between 1 and 32")
    return number


def progress_seconds(value):
    number = positive_seconds(value)
    if number > 30:
        raise argparse.ArgumentTypeError("progress interval must be at most 30 seconds")
    return number


def parallel_safe(group):
    allowed = {"pytest": PARALLEL_PYTEST_FILES, "bats": PARALLEL_BATS_FILES}.get(group["kind"], ())
    return bool(group["files"]) and all(name.split("::", 1)[0] in allowed for name in group["files"])


def run_plan(plan, root, output_dir, args, checkpoint):
    """One serial lane plus reviewed isolated files; aggregation uses plan order."""
    completed, active = {}, {}
    pending = set(range(len(plan)))
    preflight = [index for index, group in enumerate(plan) if group["kind"] in PREFLIGHT_KINDS]
    serial = [index for index, group in enumerate(plan)
              if group["kind"] not in PREFLIGHT_KINDS and not parallel_safe(group)]
    isolated = [index for index, group in enumerate(plan)
                if group["kind"] not in PREFLIGHT_KINDS and parallel_safe(group)]
    # Stable explicit priority: start the measured longest private-state service
    # while the serial lane works through BATS. No mutable timing cache/schedule.
    isolated.sort(key=lambda index: (plan[index]["files"][0].split("::", 1)[0] !=
                                    "tests/test_local_learning.py", index))
    futures = {}
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs)
    next_progress = time.monotonic() + args.progress_interval
    stopped = False

    def publish(state="running"):
        checkpoint(state, completed, active, pending)

    def launch(index):
        pending.remove(index)
        active[index] = time.monotonic()
        print(f"Running [{index + 1}/{len(plan)}] {plan[index]['id']}", flush=True)
        futures[pool.submit(run_group, plan[index], root, output_dir, index, args)] = index
        publish()

    publish()
    try:
        while pending or futures:
            if time.monotonic() >= getattr(args, "deadline", float("inf")):
                args.budget_exhausted = True
                args.cancel_event.set()
            if args.cancel_event.is_set():
                stopped = True
            if not stopped:
                if args.jobs == 1:
                    if not futures and pending:
                        launch(min(pending))
                elif preflight or any(plan[index]["kind"] in PREFLIGHT_KINDS for index in active):
                    if not futures and preflight:
                        launch(preflight.pop(0))
                else:
                    # Only one unknown/host-facing group may run at a time.
                    serial_active = any(not parallel_safe(plan[index]) for index in active)
                    if serial and not serial_active and len(futures) < args.jobs:
                        launch(serial.pop(0))
                    while isolated and len(futures) < args.jobs:
                        launch(isolated.pop(0))
            if not futures:
                break
            done, _ = concurrent.futures.wait(futures, timeout=0.2,
                                              return_when=concurrent.futures.FIRST_COMPLETED)
            for future in sorted(done, key=lambda item: futures[item]):
                index = futures.pop(future)
                error = future.exception()
                if error is None:
                    result = future.result()
                else:
                    result = {**plan[index], "status": "ERROR", "returncode": None,
                              "detail": f"Worker error: {type(error).__name__}: {error}",
                              "elapsed_seconds": round(time.monotonic() - active[index], 3)}
                completed[index] = result
                active.pop(index)
                print(f"  [{index + 1}/{len(plan)}] {result['status']} "
                      f"{result['elapsed_seconds']}s {result['id']}", flush=True)
                if (args.fail_fast_preflight and plan[index]["kind"] in PREFLIGHT_KINDS
                        and result["status"] != "PASS"):
                    print("  stopping after preflight failure", flush=True)
                    stopped = True
                if result["status"] == "TIMEOUT":
                    # A command ceiling is a governor stop, even for a reviewed timeout.
                    args.budget_exhausted = True
                    args.cancel_event.set()
                publish()
            if time.monotonic() >= next_progress:
                running = ", ".join(f"{plan[index]['id']} ({time.monotonic() - active[index]:.1f}s)"
                                    for index in sorted(active))
                print(f"Progress: {len(completed)}/{len(plan)} complete; "
                      f"{len(pending)} pending; active: {running or 'none'}", flush=True)
                publish()
                next_progress = time.monotonic() + args.progress_interval
        state = ("budget_exhausted" if getattr(args, "budget_exhausted", False) else
                 "interrupted" if args.cancel_event.is_set() else "incomplete" if pending else "complete")
        publish(state)
        return state
    finally:
        if futures:
            args.cancel_event.set()
        pool.shutdown(wait=True, cancel_futures=True)


def write_summary(output_dir, summary):
    temporary = output_dir / ".summary.json.tmp"
    temporary.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    temporary.replace(output_dir / "summary.json")


def slow_reports(groups, results, limit=20):
    slow_groups = sorted(({"identity": group["id"], "elapsed_seconds": group["elapsed_seconds"],
                           "log": group.get("log")} for group in groups),
                         key=lambda row: (-row["elapsed_seconds"], row["identity"]))[:limit]
    tests = {}
    for result in results:
        if result["suite"] not in ("pytest", "bats") or "elapsed_seconds" not in result:
            continue
        key = result["suite"], result["identity"]
        row = {key: result[key] for key in ("suite", "identity", "elapsed_seconds", "log")}
        if key not in tests or row["elapsed_seconds"] > tests[key]["elapsed_seconds"]:
            tests[key] = row
    slow_tests = sorted(tests.values(), key=lambda row: (-row["elapsed_seconds"], row["suite"], row["identity"]))[:limit]
    return {"slow_groups": slow_groups, "slow_tests": slow_tests}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("focused", "affected", "full"))
    parser.add_argument("--base", default="igor2", help="local comparison ref (default: igor2)")
    parser.add_argument("--test", action="append", default=[], help="explicit Python node/file or BATS file")
    parser.add_argument("--changed-file", action="append", default=[], help="add paths to Git selection")
    parser.add_argument("--output-dir", type=Path, help="new directory for logs and summary.json")
    parser.add_argument("--baseline", type=Path, default=ROOT / "tests/validation_baseline.json",
                        help="reviewed JSON baseline; never written by this runner")
    parser.add_argument("--dry-run", action="store_true", help="print JSON plan; execute nothing")
    parser.add_argument("--jobs", type=positive_jobs, default=1,
                        help="bounded workers; only reviewed private-state files overlap the serial lane (default: 1)")
    parser.add_argument("--progress-interval", type=progress_seconds, default=15,
                        help="active-group heartbeat, at most 30 seconds (default: 15)")
    parser.add_argument("--group-timeout", type=positive_seconds, default=600)
    parser.add_argument("--total-timeout", type=positive_seconds,
                        default=10800 if os.environ.get("CI") else 900,
                        help="persistent cumulative validation budget (development: 900s; CI: 10800s)")
    parser.add_argument("--command-timeout", type=positive_seconds,
                        default=1200 if os.environ.get("CI") else 240,
                        help="hard ceiling for every subprocess (development: 240s; CI: 1200s)")
    parser.add_argument("--new-budget", metavar="REASON", help="owner-authorized fresh budget; retain evidence")
    parser.add_argument("--rerun-reason", help="justify one additional targeted attempt on unchanged inputs")
    parser.add_argument("--environment-key", default="local-isolated-v1",
                        help="additional environment identity for external fixture dependencies")
    parser.add_argument("--interactive-timeout", type=positive_seconds, default=60,
                        help="timeout for interactive TUI Python files (default: 60s)")
    parser.add_argument("--slow-timeout", type=positive_seconds, default=1200)
    parser.add_argument("--fail-fast-preflight", action="store_true",
                        help="stop after the first structural/lint/syntax preflight failure")
    parser.add_argument("--bats-timeout", type=nonnegative_int, default=0,
                        help="opt-in BATS native per-test watchdog; 0 disables it (default)")
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--ruff", default=shutil.which("ruff") or "ruff")
    parser.add_argument("--shellcheck", default=shutil.which("shellcheck") or "shellcheck")
    parser.add_argument("--bats", default=shutil.which("bats") or "bats")
    args = parser.parse_args(argv)
    if args.new_budget is not None and not args.new_budget.strip():
        parser.error("--new-budget requires an owner authorization reason")
    if args.rerun_reason is not None and not args.rerun_reason.strip():
        parser.error("--rerun-reason requires a justification")
    args.cancel_event = threading.Event()
    started = time.monotonic()
    child_cpu = resource.getrusage(resource.RUSAGE_CHILDREN)
    output_dir = args.output_dir.resolve() if args.output_dir else Path(tempfile.mkdtemp(prefix="igor-validation-"))
    if args.output_dir:
        output_dir.mkdir(parents=True, exist_ok=False)
    summary = {"schema_version": 2, "mode": args.mode, "base": args.base,
               "baseline": str(args.baseline), "count_unit": "test_identities_and_check_groups",
               "changed_files": [], "domains": [], "groups": [], "jobs": args.jobs,
               "run_state": "running", "plan": [], "active_groups": [], "pending_groups": []}
    baseline = []
    interruption = {}
    previous_handlers = {}
    governor = None
    cache_key = None

    def interrupt(signum, _frame):
        interruption["signal"] = signum
        args.cancel_event.set()

    if threading.current_thread() is threading.main_thread():
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.signal(signum, interrupt)

    def checkpoint(state, completed, active, pending):
        summary["run_state"] = state
        summary["groups"] = [completed[index] for index in sorted(completed)]
        summary["active_groups"] = [{"index": index, "id": summary["plan"][index]["id"],
                                     "elapsed_seconds": round(time.monotonic() - active[index], 3),
                                     "log": str(output_dir / f"{index:03d}-{summary['plan'][index]['kind']}.log"),
                                     **({"report": str(output_dir / f"{index:03d}-pytest.jsonl")}
                                        if summary["plan"][index]["kind"] == "pytest" else {})}
                                    for index in sorted(active)]
        summary["pending_groups"] = [{"index": index, "id": summary["plan"][index]["id"]}
                                     for index in sorted(pending)]
        observations = []
        for group in summary["groups"]:
            observations.extend(group.get("observations", [group_observation(group)]))
        summary.update(compare_results(observations, baseline, PERMITTED_SKIPS))
        if state != "complete":
            summary["exit_code"] = 1
        if interruption:
            summary["interruption"] = dict(interruption)
            summary["exit_code"] = 128 + interruption["signal"]
        summary["elapsed_seconds"] = round(time.monotonic() - started, 3)
        cpu = resource.getrusage(resource.RUSAGE_CHILDREN)
        summary["child_cpu_seconds"] = {"user": round(cpu.ru_utime - child_cpu.ru_utime, 3),
                                        "system": round(cpu.ru_stime - child_cpu.ru_stime, 3)}
        summary.update(slow_reports(summary["groups"], summary["results"]))
        write_summary(output_dir, summary)

    try:
        # Select before our first write: CI may place evidence inside the checkout.
        changed = sorted(set(changed_files(ROOT, args.base)) | set(args.changed_file))
        if not args.dry_run:
            governor = Governor(ROOT / ".igor-governor", args.total_timeout, args.new_budget)
            governor.note_evidence(output_dir)
            exclusions = [*governor.exclusions(), output_dir]
            changed = [name for name in changed if not any(
                (ROOT / name).absolute().is_relative_to(directory) for directory in exclusions)]
        checkpoint("running", {}, {}, set())
        baseline = load_baseline(args.baseline, ROOT)
        for name in changed:
            local_path(ROOT, name)
        domains, plan = make_plan(ROOT, args.mode, changed, args.test)
        summary.update(changed_files=changed, domains=domains, plan=plan)
        if args.dry_run:
            summary.update(run_state="planned", exit_code=0)
            write_summary(output_dir, summary)
            print(json.dumps(summary, indent=2))
            return 0
        names = [os.fsdecode(name) for name in git(ROOT, "ls-files", "-z", "--cached", "--others",
                                                  "--exclude-standard").split(b"\0") if name]
        env, _ = group_environment(ROOT, output_dir, len(plan), args.python)
        candidate, cache_key = fingerprint(ROOT, names, plan, args, env, exclusions)
        # CI always exercises gates anew; local evidence never omits a selected identity.
        reusable = not os.environ.get("CI") and not requires_fresh_security(plan)
        # The current interpreter's installed files are fingerprinted. Alternate
        # interpreters must execute rather than inherit that environment evidence.
        reusable = reusable and os.path.realpath(shutil.which(args.python) or args.python) == os.path.realpath(sys.executable)
        cached = governor.reuse(cache_key) if reusable else None
        if cached is not None:
            summary = {**cached, "reused": True, "reused_from": cached.get("evidence_dir"),
                       "reuse_elapsed_seconds": round(time.monotonic() - started, 3)}
            write_summary(output_dir, summary)
            print(f"Reused unchanged validation: {summary['reused_from']} (exit {summary['exit_code']})")
            return summary["exit_code"]
        # Changing timeout/scheduling knobs cannot silently authorize another attempt.
        attempt_key = digest({"candidate": candidate, "mode": args.mode, "plan": plan})
        args.deadline = min(started + args.total_timeout,
                            governor.begin(attempt_key, candidate, args.mode, output_dir, args.rerun_reason, started))
        summary.update(evidence_dir=str(output_dir), reused=False,
                       budget={"total_seconds": args.total_timeout, "command_seconds": args.command_timeout,
                               "authorization": governor.state["authorization"]})
        run_plan(plan, ROOT, output_dir, args, checkpoint)
        if reusable:
            # Refuse to retain evidence if tests mutated any source input.
            final_names = [os.fsdecode(name) for name in git(ROOT, "ls-files", "-z", "--cached", "--others",
                                                            "--exclude-standard").split(b"\0") if name]
            _, final_key = fingerprint(ROOT, final_names, plan, args, env, exclusions)
            if final_key == cache_key:
                governor.remember(cache_key, output_dir, summary)
    except (ValueError, OSError, subprocess.SubprocessError, KeyboardInterrupt) as error:
        print(f"Runner stopped: {error}", flush=True)
        summary["groups"].append({"id": "runner", "status": "ERROR", "detail": str(error),
                                  "elapsed_seconds": 0})
        checkpoint("interrupted" if isinstance(error, KeyboardInterrupt) else "incomplete",
                   dict(enumerate(summary["groups"])), {}, set())
    finally:
        if governor is not None:
            governor.finish(getattr(args, "budget_exhausted", False))
            governor.close()
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
    print(f"\nValidation: {args.mode} (test identities and check groups)")
    for status, count in summary["counts"].items():
        print(f"{status:18} {count}")
    regressions = summary["counts"]["FAIL_NEW"] + summary["counts"]["TIMEOUT_NEW"]
    print(f"New regressions: {regressions or 'none'}")
    for result in summary["results"]:
        if result["classification"] != "PASS":
            print(f"  {result['classification']}: {result['suite']} {result['identity']} ({result.get('log', 'no log')})")
    print(f"Baseline entries not exercised: {len(summary['unexercised_baseline'])}")
    print(f"Run state: {summary['run_state']}; child CPU: {summary['child_cpu_seconds']}")
    print("Slowest groups:")
    for row in summary["slow_groups"][:5]:
        print(f"  {row['elapsed_seconds']}s {row['identity']}")
    print("Slowest tests:")
    for row in summary["slow_tests"][:5]:
        print(f"  {row['elapsed_seconds']}s {row['identity']}")
    print(f"Elapsed: {summary['elapsed_seconds']}s; evidence: {output_dir / 'summary.json'}")
    return summary["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
