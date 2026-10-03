"""Pytest report adapter: stable node/subtest identities, no execution policy."""

import ast
import json
import os
import subprocess

import pytest


def emit(record):
    path = os.environ.get("IGOR_VALIDATION_REPORT")
    if path:
        with open(path, "a", encoding="utf-8") as output:
            output.write(json.dumps(record, sort_keys=True) + "\n")


def pytest_runtest_logstart(nodeid, location):
    emit({"event": "start", "identity": nodeid})


def pytest_runtest_logfinish(nodeid, location):
    emit({"event": "finish", "identity": nodeid})


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    report = outcome.get_result()
    report.igor_timeout = bool(call.excinfo and call.excinfo.errisinstance((TimeoutError, subprocess.TimeoutExpired)))


def pytest_runtest_logreport(report):
    if report.when != "call" and not (report.failed or report.skipped):
        return
    identity = report.nodeid
    context = getattr(report, "context", None)
    if context is not None:
        # Reject unrepresentable parameters rather than relying on object repr/PIDs.
        try:
            params = context.kwargs
            # Pytest 9's built-in context stores saferepr strings. Normalize
            # literal values; arbitrary object repr is not a stable identity.
            if type(context).__module__ == "_pytest.subtests":
                params = {key: ast.literal_eval(value) for key, value in params.items()}
            suffix = json.dumps({"msg": context.msg, "params": params}, sort_keys=True,
                                separators=(",", ":"), allow_nan=False)
        except (TypeError, ValueError, SyntaxError):
            emit({"event": "result", "identity": identity, "status": "ERROR",
                  "detail": "Subtest parameters are not stable JSON values"})
            return
        identity += f"::subtest[{suffix}]"
    status = "PASS"
    if report.failed:
        status = "TIMEOUT" if getattr(report, "igor_timeout", False) else "FAIL"
    elif report.skipped:
        status = "SKIP"
    record = {"event": "result", "identity": identity, "status": status,
              "phase": report.when}
    if report.failed:
        record["detail"] = str(report.longrepr)
    if report.skipped:
        record["skip_reason"] = str(report.longrepr[2]) if isinstance(report.longrepr, tuple) else str(report.longrepr)
    # xfail is not an environmental skip and requires explicit failure review.
    if getattr(report, "wasxfail", None):
        record["status"] = "ERROR"
        record["detail"] = "xfail/xpass requires explicit validation policy"
    emit(record)
