"""Snapshot admission exercised through the existing operator consumers."""

import copy
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core/ai"))
import tui
from test_ai_tui_collections import Screen as CollectionScreen
from test_ai_tui_collections import fixture
from test_ai_tui_operator import Reader, Screen, capability


@pytest.mark.parametrize("defect", ["alias", "input_type"])
def test_reported_metadata_crashes_are_rejected_before_explorer_use(defect, monkeypatch):
    entry = capability(required=("unit",), selector=True)
    entry["inputs"].pop("selectors")
    snapshot = {"entries": [entry], "aliases": {"sys": "system"}}
    state = tui.EventState(backend_ready=True)
    assert state.accept({"event_type": "operator_snapshot", "sequence": 1, "surface": snapshot})
    malformed = copy.deepcopy(snapshot)
    if defect == "alias":
        malformed["aliases"] = {"system": "."}
        initial = "system."
    else:
        malformed["entries"][0]["inputs"]["properties"]["unit"]["type"] = []
        initial = entry["path"]
    accepted = state.accept({"event_type": "operator_snapshot", "sequence": 2, "surface": malformed})
    sent = []
    monkeypatch.setattr(tui, "_send", lambda _, text: sent.append(text))
    monkeypatch.setattr(tui.os, "read", lambda *_: (_ for _ in ()).throw(BlockingIOError()))
    assert tui._operator_overlay(Screen([10, 27]), 1, Reader([]), state, tui.InputBuffer(), initial) is None
    assert not accepted and state.operator_snapshot_rejected
    assert state.operator_snapshot == snapshot and sent == []


@pytest.mark.parametrize("path,value", [
    (("aliases",), {"system": "."}),
    (("aliases",), {"bad.alias": "fixture"}),
    (("aliases",), {"sys": []}),
    (("sources",), []),
    (("sources",), {"modules": {"status": [], "count": 1}}),
    (("entry_count",), True),
    (("entries", 0, "provider_required"), []),
    (("entries", 0, "owner"), None),
    (("entries", 0, "target_id"), ""),
    (("entries", 0, "target_id"), "fixture.resources.list\nYES"),
    (("entries", 0, "path"), "fixture.resources.list@."),
    (("entries", 0, "inputs", "required"), "limit"),
    (("entries", 0, "inputs", "required"), [[]]),
    (("entries", 0, "inputs", "required"), ["undeclared"]),
    (("entries", 0, "inputs", "properties"), []),
    (("entries", 0, "inputs", "properties"), {"bad\nname": {"type": "string"}}),
    (("entries", 0, "inputs", "properties", "cursor"), []),
    (("entries", 0, "inputs", "properties", "cursor", "type"), []),
    (("entries", 0, "inputs", "properties", "cursor", "maxLength"), []),
    (("entries", 0, "inputs", "selectors"), []),
    (("entries", 0, "inputs", "selectors"), {"cursor": {"schema_version": 1, "kind": "resource", "resource_kind": []}}),
    (("entries", 0, "collection", "columns"), []),
    (("entries", 0, "collection", "inspect"), []),
    (("entries", 0, "outputs"), {}),
    (("entries", 0, "outputs", "properties", "rows", "items", "properties", "unit", "type"), []),
])
def test_malformed_consumer_metadata_revokes_pending_selection_and_recovers(path, value, monkeypatch):
    entry, result = fixture()
    entry["inputs"]["properties"]["cursor"] = {"type": "string", "maxLength": 256}
    snapshot = {"entries": [entry], "aliases": {"sys": "fixture"}}
    state = tui.EventState(backend_ready=True)
    assert state.accept({"event_type": "operator_snapshot", "sequence": 1, "surface": snapshot})
    assert state.accept({"event_type": "action_result", "sequence": 2, "result": result})
    view = state.collection
    view.move(1)
    assert view.inspection_request() is not None
    pending = view.request_id
    state.operator_candidates = {"pending": True}
    malformed = copy.deepcopy(snapshot)
    container = malformed
    for key in path[:-1]:
        container = container[key]
    container[path[-1]] = value
    assert not state.accept({"event_type": "operator_snapshot", "sequence": 3, "surface": malformed})
    assert state.operator_snapshot == snapshot and state.operator_snapshot_rejected
    assert state.operator_candidates is None
    assert state.activity[-1].event_type == "warning"
    assert view.state == "unavailable" and view.selected_reference() is None
    assert not view.request_id and not view.detail_state and not view.pages
    sent = []
    monkeypatch.setattr(tui, "_send", lambda _, text: sent.append(text))
    monkeypatch.setattr(tui.os, "read", lambda *_: (_ for _ in ()).throw(BlockingIOError()))
    tui._draw_collection(CollectionScreen(), view)
    for key in (10, ord("n"), ord("r")):
        assert tui._collection_key(key, CollectionScreen(), 1, state)
    assert tui._operator_overlay(Screen([10, 27]), 1, Reader([]), state, tui.InputBuffer()) is None
    assert sent == []
    assert state.accept({"event_type": "action_result", "sequence": 4, "result": result, "view_request_id": pending})
    assert view.state == "unavailable" and not view.pages
    assert state.accept({"event_type": "operator_snapshot", "sequence": 5, "surface": snapshot})
    assert not state.operator_snapshot_rejected and view.selected_reference() is None
    assert tui._collection_key(ord("r"), CollectionScreen(), 1, state)
    assert len(sent) == 1
    assert state.accept({"event_type": "action_result", "sequence": 6, "result": result, "view_request_id": view.request_id})
    assert tui._collection_key(tui.curses.KEY_DOWN, CollectionScreen(), 1, state)
    assert view.selected_reference() == result["result"]["rows"][1]["reference"]
    assert state.accept({"event_type": "model_status", "sequence": 7, "status": "input_ready"})
    assert tui._collection_key(10, CollectionScreen(), 1, state)
    assert len(sent) == 2 and "--inspect" in sent[-1]


@pytest.mark.parametrize("kind,spec,expected", [
    ("string", {"maxLength": 4}, "demo"),
    ("path", {"root": "/", "maxLength": 20}, "demo"),
    ("object_id", {}, "demo"),
])
def test_valid_projected_text_inputs_reach_one_backend_invoke(kind, spec, expected, monkeypatch):
    entry = capability(required=("value",))
    entry["inputs"]["properties"] = {"value": {"type": kind, **spec}}
    entry["safety"] = None  # The canonical projection permits unavailable safety metadata.
    state = tui.EventState(backend_ready=True)
    assert state.accept({"event_type": "operator_snapshot", "sequence": 1, "surface": {"entries": [entry]}})
    sent = []
    monkeypatch.setattr(tui, "_send", lambda _, text: sent.append(text))
    monkeypatch.setattr(tui.os, "read", lambda *_: (_ for _ in ()).throw(BlockingIOError()))
    text = "/demo" if kind == "path" else "demo"
    command = tui._operator_overlay(Screen([*[ord(char) for char in text], 10]), 1, Reader([]), state,
                                    tui.InputBuffer(), entry["path"])
    assert sent == [command]
    assert command == 'invoke system.host.memory.refresh {"value":"' + expected + '"}'
