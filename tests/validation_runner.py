"""Bounded developer validation with explicit reviewed baseline comparison.

Usage: tests/validate.sh focused|affected|full [--base REF] [--test FILE::NODE]
Git selection includes committed changes since the local merge base and all
staged, unstaged and untracked changes. --changed-file adds simulated changes
for mapping proofs; --dry-run emits the plan without executing it. Deleted
paths select affected domains but are not linted. Focused finds changed tests
and conventional test_<python_module>.py matches; supply other feature tests.

Full mirrors the canonical run_all.sh groups (legacy Bash, rendering, Core,
module and integration BATS) and additionally discovers every test_*.py under
tests. Each test file is a bounded subprocess. BATS uses its native per-test
watchdog and continuation; a Python file timeout moves on to the next file.
Limits default to 600s/file, 1200s for System configuration/administration vertical slices,
and 180s/BATS test. These are ceilings, not expected durations. No full run is
ever triggered by focused/affected. CI and local validation share this entry point.

Raw output and summary.json live in a unique temporary directory by default;
--output-dir must name a new directory. Summary counts refer to test identities
and structural/tool groups. Raw group outcomes remain in groups. A new failure,
new timeout, error or unavailable required tool makes exit nonzero. Only exact
reviewed failure/timeout identities can match validation_baseline.json. Only
explicit test-level skip permissions can produce ENV_SKIP; host Docker/systemd
availability is never probed. No baseline is generated or updated by a run.
Markdown checks verify inline local file links, excluding fenced examples;
anchors, reference-style links and external URLs remain outside this check.
"""

import argparse
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from validation_domains import affected_tests
from validation_environment import PERMITTED_SKIPS
from validation_reports import bats_observations, group_observation, pytest_observations
from validation_results import compare_results, load_baseline

ROOT = Path(__file__).resolve().parents[1]
SHELLCHECK_FLAGS = ["--severity=warning", "--exclude=SC2086,SC1090,SC1091,SC2034", "--shell=bash"]


def execute(command, root, log, seconds, env=None):
    """Write directly to disk (no pipe deadlocks); bound and clean the process group."""
    started = time.monotonic()
    status = "ERROR"
    returncode = None
    with log.open("w", encoding="utf-8") as output:
        output.write(f"Command: {command!r}\n")
        output.flush()
        try:
            process = subprocess.Popen(command, cwd=root, stdout=output, stderr=subprocess.STDOUT,
                                       env=env, start_new_session=True)
        except FileNotFoundError as error:
            output.write(f"Required tool unavailable: {error}\n")
            status = "TOOL_UNAVAILABLE"
        except OSError as error:
            output.write(f"Runner error: {error}\n")
        else:
            try:
                returncode = process.wait(timeout=seconds)
                status = "PASS" if returncode == 0 else "FAIL"
            except subprocess.TimeoutExpired:
                output.write(f"\nTIMEOUT: process group exceeded {seconds}s\n")
                status = "TIMEOUT"
            finally:
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
    for name in sorted(tests):
        if not local_path(root, name.split("::", 1)[0]).is_file():
            # A removed test is not executable; explicit missing targets fail closed.
            if name in supplied:
                raise ValueError(f"Explicit test does not exist: {name}")
            continue
        kind = "bats" if name.endswith(".bats") else "pytest"
        plan.append({"id": f"{kind}:{name}", "kind": kind, "files": [name]})
    return domains, plan


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
    env = {**os.environ, "IGOR_DIR": str(root), "BATS_TEST_TIMEOUT": str(args.bats_timeout)}
    report_path = output_dir / f"{index:03d}-pytest.jsonl"
    if kind == "pytest":
        env["IGOR_VALIDATION_REPORT"] = str(report_path)
        env["PYTHONPATH"] = str(Path(__file__).parent) + os.pathsep + env.get("PYTHONPATH", "")
    seconds = args.group_timeout
    if any(Path(name.split("::", 1)[0]).name in ("test_system_configuration_workflow.py",
                                                   "test_system_admin_surface.bats") for name in files):
        seconds = args.slow_timeout
    result = execute(commands[kind], root, log, seconds, env)
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
            combined["observations"] = pytest_observations(combined, report_path)
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
    parser.add_argument("--group-timeout", type=positive_seconds, default=600)
    parser.add_argument("--slow-timeout", type=positive_seconds, default=1200)
    parser.add_argument("--bats-timeout", type=int, default=180)
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--ruff", default=shutil.which("ruff") or "ruff")
    parser.add_argument("--shellcheck", default=shutil.which("shellcheck") or "shellcheck")
    parser.add_argument("--bats", default=shutil.which("bats") or "bats")
    args = parser.parse_args(argv)
    if args.bats_timeout <= 0:
        parser.error("--bats-timeout must be positive")
    started = time.monotonic()
    output_dir = args.output_dir.resolve() if args.output_dir else Path(tempfile.mkdtemp(prefix="igor-validation-"))
    if args.output_dir:
        output_dir.mkdir(parents=True, exist_ok=False)
    summary = {"schema_version": 2, "mode": args.mode, "base": args.base,
               "baseline": str(args.baseline), "count_unit": "test_identities_and_check_groups",
               "changed_files": [], "domains": [], "groups": []}
    baseline = []
    try:
        baseline = load_baseline(args.baseline, ROOT)
        changed = sorted(set(changed_files(ROOT, args.base)) | set(args.changed_file))
        for name in changed:
            local_path(ROOT, name)
        domains, plan = make_plan(ROOT, args.mode, changed, args.test)
        summary.update(changed_files=changed, domains=domains)
        if args.dry_run:
            summary["plan"] = plan
            print(json.dumps(summary, indent=2))
            return 0
        for index, group in enumerate(plan):
            print(f"Running {group['id']}", flush=True)
            result = run_group(group, ROOT, output_dir, index, args)
            summary["groups"].append(result)
            print(f"  {result['status']} {result['elapsed_seconds']}s", flush=True)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        summary["groups"].append({"id": "runner", "status": "ERROR", "detail": str(error),
                                  "elapsed_seconds": 0})
    observations = []
    for group in summary["groups"]:
        observations.extend(group.get("observations", [group_observation(group)]))
    summary.update(compare_results(observations, baseline, PERMITTED_SKIPS))
    summary["elapsed_seconds"] = round(time.monotonic() - started, 3)
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"\nValidation: {args.mode} (test identities and check groups)")
    for status, count in summary["counts"].items():
        print(f"{status:18} {count}")
    regressions = summary["counts"]["FAIL_NEW"] + summary["counts"]["TIMEOUT_NEW"]
    print(f"New regressions: {regressions or 'none'}")
    for result in summary["results"]:
        if result["classification"] != "PASS":
            print(f"  {result['classification']}: {result['suite']} {result['identity']} ({result.get('log', 'no log')})")
    print(f"Baseline entries not exercised: {len(summary['unexercised_baseline'])}")
    print(f"Elapsed: {summary['elapsed_seconds']}s; evidence: {output_dir / 'summary.json'}")
    return summary["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
