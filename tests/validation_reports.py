"""Read native runner reports without treating raw error text as test identity."""

import json
import math
import re
from pathlib import Path


def group_observation(group, status=None, detail=None):
    return {"suite": "group", "identity": group["id"], "status": status or group["status"],
            "log": group.get("log"), **({"detail": detail} if detail else {})}


def pytest_observations(group, report_path, require_collection=False):
    observations = []
    active = set()
    finished = set()
    collected = None
    timings = {}
    errors = []
    if report_path.exists():
        for number, line in enumerate(report_path.read_text(encoding="utf-8").splitlines(), 1):
            try:
                record = json.loads(line)
                if record["event"] == "collection":
                    identities = record["identities"]
                    if collected is not None or not isinstance(identities, list) or not all(
                            isinstance(identity, str) and identity for identity in identities):
                        raise ValueError("invalid/duplicate collection manifest")
                    if len(identities) != len(set(identities)):
                        raise ValueError("duplicate collected pytest identity")
                    collected = set(identities)
                    continue
                identity = record["identity"]
                if not isinstance(identity, str) or not identity:
                    raise ValueError("invalid pytest identity")
                if record["event"] == "start":
                    active.add(identity)
                elif record["event"] == "finish":
                    finished.add(identity)
                    active.discard(identity)
                elif record["event"] == "duration":
                    elapsed = record["elapsed_seconds"]
                    if type(elapsed) not in (int, float) or not math.isfinite(elapsed) or elapsed < 0:
                        raise ValueError("invalid pytest duration")
                    if record["phase"] not in ("setup", "call", "teardown"):
                        raise ValueError("invalid pytest phase")
                    timings.setdefault(identity, {})[record["phase"]] = elapsed
                elif record["event"] == "result":
                    observations.append({"suite": "pytest", "log": group["log"],
                                         **{key: value for key, value in record.items() if key != "event"}})
                else:
                    raise ValueError("unknown pytest report event")
            except (ValueError, KeyError, TypeError) as error:
                # Keep completed evidence even when a kill truncates the final
                # JSONL record. Corruption still creates a non-baseline ERROR.
                errors.append(f"Invalid pytest report line {number}: {error}")
    if collected is not None:
        group["collected_identities"] = sorted(collected)
    for observation in observations:
        phases = timings.get(observation["identity"])
        if phases:
            observation["phase_seconds"] = {key: round(value, 6) for key, value in phases.items()}
            observation["elapsed_seconds"] = round(sum(phases.values()), 6)
    if require_collection and collected is None and group["status"] in ("PASS", "FAIL"):
        errors.append("Missing pytest collection manifest")
    if collected is not None and group["status"] in ("PASS", "FAIL"):
        if collected != finished:
            errors.append("Collected pytest nodes lack complete execution evidence")
        reported = {row["identity"].split("::subtest[", 1)[0] for row in observations}
        if not collected <= reported:
            errors.append("Collected pytest nodes lack result evidence")
    observations.extend(group_observation(group, "ERROR", error) for error in errors)
    if group["status"] == "TIMEOUT":
        # An outer timeout proves only the active node, never unexecuted siblings.
        for identity in sorted(active):
            observations.append({"suite": "pytest", "identity": identity, "status": "TIMEOUT", "log": group["log"],
                                 "detail": "Runner process deadline exceeded"})
        if not active:
            observations.append(group_observation(group))
    elif group["status"] in ("TOOL_UNAVAILABLE", "ERROR"):
        observations.append(group_observation(group))
    elif group["returncode"] not in (0, 1):
        observations.append(group_observation(group, "ERROR", "Pytest collection/usage/internal failure"))
    elif not observations or active:
        observations.append(group_observation(group, "ERROR", "Missing or incomplete pytest report"))
    elif group["status"] == "FAIL" and not any(row["status"] in ("FAIL", "TIMEOUT", "ERROR") for row in observations):
        observations.append(group_observation(group, "ERROR", "Nonzero pytest exit without a failing test report"))
    # PASS call reports cannot override a later failure or an outer deadline.
    failures = {row["identity"] for row in observations if row["status"] in ("FAIL", "TIMEOUT", "ERROR")}
    observations = [row for row in observations if row["status"] != "PASS" or row["identity"] not in failures]
    return observations


def bats_observations(group):
    observations = []
    text = Path(group["log"]).read_text(encoding="utf-8", errors="replace")
    declared = re.search(r"^1\.\.(\d+)\s*$", text, re.MULTILINE)
    names = set()
    for match in re.finditer(r"^(not ok|ok) \d+ (.+)$", text, re.MULTILINE):
        outcome, name = match.groups()
        status = "PASS" if outcome == "ok" else "FAIL"
        details = {}
        timeout = re.search(r" # timeout after \d+s.*$", name)
        skip = re.search(r" # skip(?: (.*))?$", name, re.IGNORECASE)
        if timeout:
            name = name[:timeout.start()]
            status = "TIMEOUT"
        elif skip:
            name = name[:skip.start()]
            status = "SKIP"
            details["skip_reason"] = skip.group(1) or ""
        # BATS writes timing before a trailing skip/timeout directive.
        timing = re.search(r" in (\d+)ms$", name)
        if timing:
            details["elapsed_seconds"] = int(timing.group(1)) / 1000
            name = name[:timing.start()]
        # --timing adds duration to the native test name; never part of identity.
        identity = f"{group['files'][0]}::{name}"
        if identity in names:
            raise ValueError(f"Duplicate BATS test identity: {identity}")
        names.add(identity)
        observations.append({"suite": "bats", "identity": identity, "status": status,
                             "log": group["log"], **details})
    if group["status"] in ("TOOL_UNAVAILABLE", "ERROR") or group["status"] == "TIMEOUT" and group.get("returncode") is None:
        observations.append(group_observation(group))
    elif not declared or len(observations) != int(declared.group(1)):
        observations.append(group_observation(group, "ERROR", "Missing/incomplete BATS TAP report"))
    elif group["status"] != "PASS" and not any(row["status"] in ("FAIL", "TIMEOUT") for row in observations):
        observations.append(group_observation(group, "ERROR", "Nonzero BATS exit without failing test report"))
    return observations
