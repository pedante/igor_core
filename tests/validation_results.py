"""Strict baseline metadata and stable validation-result comparison."""

from __future__ import annotations

import ast
import json
import re
from pathlib import Path

SCHEMA_VERSION = 1
BASELINE_CLASSIFICATIONS = {"FAIL", "TIMEOUT"}
RESULT_STATUSES = {"PASS", "FAIL", "TIMEOUT", "SKIP", "TOOL_UNAVAILABLE", "ERROR"}
FINAL_CLASSIFICATIONS = (
    "PASS", "FAIL_NEW", "FAIL_BASELINE", "BASELINE_FIXED", "TIMEOUT_NEW",
    "TIMEOUT_BASELINE", "ENV_SKIP", "TOOL_UNAVAILABLE", "ERROR",
)
_GROUPS = {"structure", "ruff", "shellcheck", "canonical:bash"}


class BaselineError(ValueError):
    """Invalid or unsafe baseline metadata."""


def _object_without_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise BaselineError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _reject_constant(value):
    raise BaselineError(f"non-finite JSON value: {value}")


def _node_names(tree):
    found = set()

    def visit(node, scope=()):
        for child in getattr(node, "body", ()):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                found.add((*scope, child.name))
                if isinstance(child, ast.ClassDef):
                    visit(child, (*scope, child.name))
    visit(tree)
    return found


def _valid_pytest_identity(identity: str, root: Path) -> bool:
    parts = identity.split("::")
    file = parts[0]
    if not file.startswith("tests/") or not file.endswith(".py") or not _safe_repo_file(file, root):
        return False
    if len(parts) < 2:
        return False
    # Parametrization and the runner's JSON-encoded subtest suffixes are data,
    # not part of the declared Python function identity.
    names = []
    for index, item in enumerate(parts[1:], 1):
        if item.startswith("subtest["):
            if index != len(parts) - 1 or not item.endswith("]"):
                return False
            try:
                params = json.loads(item[8:-1], object_pairs_hook=_object_without_duplicate_keys,
                                    parse_constant=_reject_constant)
            except (ValueError, TypeError):
                return False
            if not isinstance(params, dict) or set(params) != {"msg", "params"} or not isinstance(params["params"], dict):
                return False
            break
        if "[" in item and not item.endswith("]"):
            return False
        names.append(re.sub(r"\[.*$", "", item))
    if not all(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", item) for item in names):
        return False
    try:
        declared = _node_names(ast.parse((root / file).read_text(encoding="utf-8")))
    except (OSError, SyntaxError, UnicodeError) as error:
        raise BaselineError(f"cannot validate pytest identity {identity!r}: {error}") from error
    return tuple(names) in declared


def _valid_bats_identity(identity: str, root: Path) -> bool:
    file, sep, test_name = identity.partition("::")
    if not sep or not test_name or not file.startswith("tests/") or not file.endswith(".bats"):
        return False
    path = root / file
    if not _safe_repo_file(file, root):
        return False
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise BaselineError(f"cannot validate BATS identity {identity!r}: {error}") from error
    return re.search(r"(?m)^\s*@test\s+(['\"])" + re.escape(test_name) + r"\1\s*\{", source) is not None


def _valid_group_identity(identity: str, root: Path) -> bool:
    if identity in _GROUPS:
        return True
    if identity.startswith("syntax:"):
        return _safe_repo_file(identity.removeprefix("syntax:"), root)
    if identity.startswith("contract:"):
        module = identity.removeprefix("contract:")
        return bool(re.fullmatch(r"modules/[A-Za-z0-9_-]+", module) and
                    (root / module / "module.conf").is_file())
    return False


def _safe_repo_file(name: str, root: Path) -> bool:
    path = (root / name).resolve()
    return path.is_relative_to(root.resolve()) and path.is_file()


def load_baseline(path, root) -> list[dict]:
    """Load and validate a small versioned manifest; reject every ambiguity."""
    path, root = Path(path), Path(root).resolve()
    try:
        data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_object_without_duplicate_keys,
                          parse_constant=_reject_constant)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise BaselineError(f"cannot read baseline: {error}") from error
    if not isinstance(data, dict) or set(data) != {"schema_version", "source_commit", "entries"}:
        raise BaselineError("baseline must contain exactly schema_version, source_commit, and entries")
    if type(data["schema_version"]) is not int or data["schema_version"] != SCHEMA_VERSION:
        raise BaselineError("unsupported or malformed baseline schema_version")
    if not isinstance(data["source_commit"], str) or not re.fullmatch(r"[0-9a-fA-F]{40}", data["source_commit"]):
        raise BaselineError("source_commit must be a 40-character Git object id")
    if not isinstance(data["entries"], list):
        raise BaselineError("entries must be an array")
    seen = set()
    entries = []
    for index, entry in enumerate(data["entries"]):
        if not isinstance(entry, dict):
            raise BaselineError(f"entry {index} must be an object")
        required = {"suite", "identity", "classification", "reason"}
        if not required <= set(entry) or set(entry) - required - {"reference"}:
            raise BaselineError(f"entry {index} has missing or unknown fields")
        if not all(isinstance(entry[key], str) and entry[key].strip()
                   for key in ("suite", "identity", "reason")):
            raise BaselineError(f"entry {index} suite, identity, and reason must be nonempty strings")
        if not isinstance(entry["classification"], str) or entry["classification"] not in BASELINE_CLASSIFICATIONS:
            raise BaselineError(f"entry {index} has unknown baseline classification")
        if "reference" in entry and (not isinstance(entry["reference"], str) or not entry["reference"].strip()):
            raise BaselineError(f"entry {index} reference must be a nonempty string")
        suite, identity = entry["suite"], entry["identity"]
        valid = (_valid_pytest_identity(identity, root) if suite == "pytest" else
                 _valid_bats_identity(identity, root) if suite == "bats" else
                 _valid_group_identity(identity, root) if suite == "group" else False)
        if not valid:
            raise BaselineError(f"entry {index} has unknown {suite!r} identity {identity!r}")
        key = (suite, identity)
        if key in seen:
            raise BaselineError(f"duplicate or contradictory baseline identity: {suite}:{identity}")
        seen.add(key)
        entries.append(dict(entry))
    return entries


def compare_results(observations, baseline, permitted_skips) -> dict:
    """Annotate observations and compare only baseline entries exercised in scope."""
    entries = {(item["suite"], item["identity"]): item for item in baseline}
    exercised = set()
    results = []
    nonpasses = {(row.get("suite"), row.get("identity")) for row in observations
                 if isinstance(row.get("suite"), str) and isinstance(row.get("identity"), str)
                 and row.get("status") != "PASS"}
    for observation in observations:
        suite, identity = observation.get("suite"), observation.get("identity")
        status = observation.get("status")
        if suite not in ("pytest", "bats", "group") or not isinstance(identity, str) or not identity or not isinstance(status, str) or status not in RESULT_STATUSES:
            result = {**observation, "classification": "ERROR", "detail": "malformed result observation"}
        else:
            key = (suite, identity)
            exercised.add(key)
            expected = entries.get(key)
            classification = status
            if status == "PASS" and expected and key not in nonpasses:
                classification = "BASELINE_FIXED"
            elif status == "FAIL":
                classification = "FAIL_BASELINE" if expected and expected["classification"] == "FAIL" else "FAIL_NEW"
            elif status == "TIMEOUT":
                classification = "TIMEOUT_BASELINE" if expected and expected["classification"] == "TIMEOUT" else "TIMEOUT_NEW"
            elif status == "SKIP":
                allowed = permitted_skips.get(key, set())
                reason = observation.get("skip_reason")
                classification = "ENV_SKIP" if isinstance(reason, str) and reason in allowed else "ERROR"
                if classification == "ERROR":
                    result = {**observation, "classification": classification,
                              "detail": "skip is not permitted by the test contract"}
                    results.append(result)
                    continue
            result = {**observation, "classification": classification}
            if expected:
                result["baseline_entry"] = dict(expected)
        results.append(result)

    # Uniquely count each identity/classification. Repeated observations retain
    # their detail and logs, while mixed failure/timeout outcomes remain visible.
    counts = {name: 0 for name in FINAL_CLASSIFICATIONS}
    counted = set()
    for result in results:
        classification = result["classification"]
        key = (result.get("suite"), result.get("identity"), classification)
        if key not in counted:
            counts[classification] += 1
            counted.add(key)
    unexercised = [dict(entry) for key, entry in entries.items() if key not in exercised]
    bad = any(counts[name] for name in ("FAIL_NEW", "TIMEOUT_NEW", "TOOL_UNAVAILABLE", "ERROR"))
    return {"results": results, "counts": counts, "unexercised_baseline": unexercised,
            "exit_code": int(bad)}
