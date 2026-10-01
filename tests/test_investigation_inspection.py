"""Step 15C headless and shared read-only interaction surface."""

import json
import os
import subprocess
import sys
import time
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/ai"))
sys.path.insert(0, str(ROOT / "core/lib"))
import tui
from judgment import judge
from operational_history import OperationalHistory


def cli(data, action, fields=None):
    args = ["bash", str(ROOT / "igor.sh"), "--investigations", action]
    if fields is not None:
        args.append("-")
    return subprocess.run(args, input=json.dumps(fields) if fields is not None else None,
                          env={**os.environ, "IGOR_DATA_DIR": str(data)},
                          capture_output=True, text=True, check=False)


def load(query, data):
    with patch.dict(os.environ, {"IGOR_DATA_DIR": str(data)}):
        try:
            query.start()
            deadline = time.monotonic() + 8
            while query.process is not None and time.monotonic() < deadline:
                query.poll()
                time.sleep(0.01)
        finally:
            query.close()


def test_absent_inspection_allocates_no_scope_or_storage(tmp_path):
    data = tmp_path / "absent"
    query = tui.InvestigationInspection()
    load(query, data)
    assert query.data == [], query.status
    assert not data.exists()
    result = cli(data, "status")
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["availability"] == "not_created"
    assert not data.exists()


def test_real_cli_creation_panel_and_inspection_are_read_only(tmp_path):
    data = tmp_path / "data"
    history = OperationalHistory(data)
    episode = history.prepare(
        {"capability_id": "system.host.memory.refresh", "capability_version": 1,
         "provider": "system.host.memory", "owner": "system", "inputs": {},
         "safety": {"tier": "READ"}, "privilege": "none", "precondition_status": "satisfied",
         "verification": {"kind": "none", "required": False}, "recovery": {"class": "not_applicable"},
         "affected_objects": ["host:local"]}, correlation_id="corr-investigation-ui",
        provenance={"actor": "operator", "interface": "fixture", "request_id": None})
    fields = {"title": "Understand backup failure", "summary": "Uncertain cause",
              "source": "operator", "owner": "operator",
              "provenance": {"source": "fixture", "recorded_at": "2026-10-01T12:00:00Z"}}
    result = cli(data, "create", fields)
    assert result.returncode == 0, result.stderr
    row = json.loads(result.stdout)
    ident = row["investigation_id"]
    scope = row["scope_id"]
    assert scope == episode["scope_id"]

    def update(action, **values):
        result = cli(data, action, {"investigation_id": ident, **values})
        assert result.returncode == 0, result.stdout + result.stderr
        return json.loads(result.stdout)

    update("add_evidence", evidence={"id": "operation-1", "kind": "operation", "scope_id": scope,
                                     "target": episode["operation_id"], "source": "operational_history",
                                     "recorded_at": "2026-10-01T12:00:00Z", "availability": "available"})
    update("add_hypothesis", statement="Failure cause remains uncertain")
    request = {"contract": "igor.judgment", "version": 1, "kind": "assessment", "kind_version": 1,
               "input": {"question": "Can the cause be established?"}, "references": [],
               "output_schema": {"type": "object", "properties": {}, "required": [],
                                 "additionalProperties": False}}
    record = judge(request, lambda _: {"status": "abstain", "payload": None, "evidence": [],
                                       "reason": "insufficient_information"},
                   provider="fixture", model="fixture")
    update("attach_judgment", request=request, record=record)
    update("set_findings", findings=["No established cause"])
    row = update("set_questions", unresolved_questions=["Which condition caused backup failure?"])
    before = {p.relative_to(data): p.read_bytes() for p in data.rglob("*") if p.is_file()}
    query = tui.InvestigationInspection()
    load(query, data)
    assert query.data[0]["investigation_id"] == ident, query.status
    section = next(s for s in tui.panel_sections(tui.EventState(), tui.HistoryInspection(), query)
                   if s["id"] == "investigations")
    rendered = " ".join(tui.panel_rows(section))
    for text in ("Understand backup failure", "scope_id", "status", "evidence",
                 "hypotheses", "judgments", "findings", "unresolved_questions", "fixture",
                 "Failure cause remains uncertain", "abstain", "No established cause",
                 "Which condition caused backup failure?", episode["operation_id"]):
        assert text in rendered
    inspected = subprocess.run(["bash", str(ROOT / "igor.sh"), "--investigations", "inspect", ident],
                               env={**os.environ, "IGOR_DATA_DIR": str(data)},
                               capture_output=True, text=True, check=True)
    assert json.loads(inspected.stdout) == row
    assert {p.relative_to(data): p.read_bytes() for p in data.rglob("*") if p.is_file()} == before


def test_cli_rejects_unknown_authority_action_before_storage(tmp_path):
    for action in ("execute", "approve", "activate", "refresh", "automate", "verify"):
        result = cli(tmp_path / "absent", action)
        assert result.returncode != 0
    assert not (tmp_path / "absent").exists()


def test_panel_enter_queries_only_read_only_investigation_command():
    from test_ai_interaction_surface import run_keys

    keys = [2] + [tui.curses.KEY_DOWN] * 4 + [10, 2]
    with patch.object(tui.InvestigationInspection, "start") as start:
        _screen, send, _state = run_keys(keys)
    start.assert_called_once_with()
    send.assert_not_called()
    assert tui.InvestigationInspection.command == ("--investigations", "list")
