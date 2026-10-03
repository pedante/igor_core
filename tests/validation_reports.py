"""Read native runner reports without treating raw error text as test identity."""

import json
import re
from pathlib import Path


def group_observation(group, status=None, detail=None):
    return {"suite": "group", "identity": group["id"], "status": status or group["status"],
            "log": group.get("log"), **({"detail": detail} if detail else {})}


def pytest_observations(group, report_path):
    observations = []
    active = set()
    finished = set()
    if report_path.exists():
        for line in report_path.read_text(encoding="utf-8").splitlines():
            record = json.loads(line)
            identity = record["identity"]
            if record["event"] == "start":
                active.add(identity)
            elif record["event"] == "finish":
                finished.add(identity)
                active.discard(identity)
            elif record["event"] == "result":
                observations.append({"suite": "pytest", "log": group["log"],
                                     **{key: value for key, value in record.items() if key != "event"}})
            else:
                raise ValueError("Unknown pytest report event")
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
        # --timing adds duration to the native test name; never part of identity.
        name = re.sub(r" in \d+ms$", "", name)
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
