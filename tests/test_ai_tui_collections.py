"""Generic collection projection and navigation; no registered synthetic provider."""

import copy
import json
import os
import platform
import resource
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/ai"))
import tui
from test_collection_contract import collection_descriptor, page_value, record


def fixture(shape="services", count=3):
    descriptor = collection_descriptor()
    page = page_value(count)
    stamp = datetime.now(timezone.utc)
    page["freshness"] = {"observed_at": stamp.isoformat().replace("+00:00", "Z"),
                         "expires_at": (stamp + timedelta(seconds=30)).isoformat().replace("+00:00", "Z")}
    if shape == "volumes":
        descriptor["collection"] = {"resource_kind": "volume", "inventory": "mounted_volumes",
                                    "columns": [{"field": "capacity", "label": "Bytes"},
                                                {"field": "ready", "label": "Ready"},
                                                {"field": "label", "label": "Name"}]}
        outputs = descriptor["outputs"]["properties"]
        outputs["resource_kind"]["enum"] = ["volume"]
        outputs["inventory"]["enum"] = ["mounted_volumes"]
        outputs["rows"]["items"] = record({"reference": {"type": "scoped_reference"},
                                             "label": {"type": "string", "maxLength": 4096},
                                             "ready": {"type": "boolean"},
                                             "capacity": {"type": "integer", "minimum": 0, "maximum": 1024}})
        page.update(resource_kind="volume", inventory="mounted_volumes")
        page["rows"] = [{"reference": {"scope_id": page_value()["rows"][0]["reference"]["scope_id"],
                                       "object_id": f"storage:fixture{i}"},
                         "label": f"Volume {i}", "ready": bool(i % 2), "capacity": i} for i in range(count)]
    entry = {"kind": "capability", "path": descriptor["id"], "target_id": descriptor["id"], "provider": "fixture", "owner": "fixture",
             "availability": "active", "inputs": descriptor["inputs"], "outputs": descriptor["outputs"],
             "collection": descriptor["collection"]}
    result = {"operation_id": "op-" + "a" * 32, "capability_id": descriptor["id"], "capability_version": 3,
              "provider": "fixture", "owner": "fixture", "execution_status": "succeeded",
              "verification_status": "not_applicable", "outcome": "success", "output_status": "valid", "result": page}
    return entry, result


@pytest.mark.parametrize("shape", ["services", "volumes"])
def test_generic_projection_columns_selection_and_page_local_filter(shape):
    entry, result = fixture(shape)
    state = tui.EventState(operator_snapshot={"entries": [entry]})
    assert tui.apply_event(state, {"event_type": "action_result", "sequence": 1, "result": result})
    view = state.collection
    assert view.state == "ready"
    assert [c["field"] for c in view.columns] == [c["field"] for c in entry["collection"]["columns"]]
    view.move(1)
    assert view.selected_reference() == result["result"]["rows"][1]["reference"]
    view.query = "demo2" if shape == "services" else "Volume 2"
    assert len(view.rows()) == 1
    assert "next_cursor" not in json.dumps(view.inspect())
    assert state.activity[-1].result is None


@pytest.mark.parametrize("defect", ["extra", "duplicate", "scope", "type", "count", "status", "version", "provider", "control"])
def test_malformed_collections_are_never_selectable(defect):
    entry, result = fixture()
    page = result["result"]
    if defect == "extra": page["unapproved"] = "REJECTED_SENTINEL"
    elif defect == "duplicate": page["rows"][1]["reference"] = page["rows"][0]["reference"]
    elif defect == "scope": page["rows"][1]["reference"]["scope_id"] = "scope:" + "b" * 32
    elif defect == "type": page["rows"][0]["unit"] = []
    elif defect == "count": page["page"]["returned_count"] = 1
    elif defect == "status": result["output_status"] = "invalid"
    elif defect == "version": result["capability_version"] = 2
    elif defect == "provider": result["provider"] = "another"
    else: page["rows"][0]["unit"] = "bad\x1b.service"
    view = tui.CollectionView(entry)
    view.accept(result)
    assert view.state == "invalid" and view.selected_reference() is None and view.pages == []


def test_requests_correlate_refresh_dismissal_duplicates_and_old_sequences():
    entry, result = fixture()
    view = tui.CollectionView(entry)
    first = view.request()
    old = view.request_id
    latest = view.request()
    assert first != latest and "cursor" not in latest
    state = tui.EventState(collection=view, operator_snapshot={"entries": [entry]})
    stale = {"event_type": "action_result", "sequence": 1, "view_request_id": old, "result": result}
    assert tui.apply_event(state, stale) and view.state == "loading"
    fresh = dict(stale, sequence=2, view_request_id=view.request_id)
    assert tui.apply_event(state, fresh) and view.state == "ready"
    view.move(2)
    assert not tui.apply_event(state, fresh)
    assert view.selection == 2
    assert not tui.apply_event(state, stale)
    state.collection = None
    assert tui.apply_event(state, dict(fresh, sequence=3)) and state.collection is None


def test_empty_expiry_and_session_termination():
    entry, result = fixture(count=0)
    view = tui.CollectionView(entry)
    view.accept(result)
    assert view.state == "empty" and view.selected_reference() is None
    view.expires = time.monotonic() - 1
    assert view.expire() and view.state == "expired" and not view.pages
    state = tui.EventState(collection=view)
    assert tui.apply_event(state, {"event_type": "session_finished", "sequence": 1})
    assert state.collection is None


def test_bounded_stream_recovery_and_result_non_exposure(tmp_path):
    entry, result = fixture()
    view = tui.CollectionView(entry)
    view.request()
    state = tui.EventState(collection=view, operator_snapshot={"entries": [entry]})
    event = {"event_type": "action_result", "sequence": 1, "view_request_id": view.request_id,
             "result": result, "rejected": "REJECTED_SENTINEL" * 10000}
    assert not tui.apply_event(state, event)
    assert view.state == "invalid" and not state.activity
    path = tmp_path / "events"
    path.write_bytes(b"X" * 2000000 + b'\n{"event_type":"model_status","sequence":2}\n')
    reader = tui.EventReader(path)
    events = []
    for _ in range(10):
        events.extend(reader.read())
        assert len(reader.partial) <= 1048576
    assert events[-1]["sequence"] == 2


@pytest.mark.parametrize("width", [0, 1, 2, 5, 80])
def test_terminal_safe_cells(width):
    value = tui.cell_text("\x1b[31m\x00\u202e漢字" + "e\u0301" * 100, width)
    assert "\x1b" not in value and "\x00" not in value and "\u202e" not in value
    assert len(value) <= max(1, width * 2)


class Screen:
    def __init__(self, height=24, width=100):
        self.height, self.width = height, width
        self.drawn = []

    def getmaxyx(self):
        return self.height, self.width

    def erase(self):
        self.drawn = []

    def addnstr(self, row, col, text, count, style=0):
        assert 0 <= row < self.height and 0 <= col < self.width
        assert "\x1b" not in text
        self.drawn.append((row, text, style))

    def refresh(self):
        pass

    def timeout(self, _value):
        pass

    def getch(self):
        return 27


@pytest.mark.parametrize("shape", ["services", "volumes"])
@pytest.mark.parametrize("dimensions", [(24, 100), (8, 20), (3, 5), (1, 1)])
def test_bounded_generic_rendering(shape, dimensions):
    entry, result = fixture(shape)
    # Sorted object keys must not reorder descriptor columns.
    entry = json.loads(json.dumps(entry, sort_keys=True))
    view = tui.CollectionView(entry)
    view.accept(result)
    screen = Screen(*dimensions)
    tui._draw_collection(screen, view)
    assert view.selected_reference() == result["result"]["rows"][0]["reference"]
    if dimensions[1] == 100:
        header = next(text for row, text, _ in screen.drawn if row == 3)
        if shape == "volumes":
            assert header.index("Bytes") < header.index("Ready") < header.index("Name")
        assert any(style == tui.curses.A_REVERSE for _, _, style in screen.drawn)


def test_navigation_keys_filter_and_missing_binding_inline_only(monkeypatch):
    entry, result = fixture("volumes")
    view = tui.CollectionView(entry)
    view.accept(result)
    state = tui.EventState(collection=view, backend_ready=True)
    sent = []
    monkeypatch.setattr(tui, "_send", lambda _, command: sent.append(command))
    screen = Screen()
    for key in [tui.curses.KEY_DOWN, ord("/"), ord("2"), 27]:
        assert tui._collection_key(key, screen, 1, state)
    assert len(view.rows()) == 1 and sent == []
    assert view.selected_reference()["object_id"] == "storage:fixture2"
    tui._collection_key(10, screen, 1, state)
    assert view.detail_state == "inline" and sent == []
    tui._collection_key(27, screen, 1, state)
    tui._collection_key(ord("r"), screen, 1, state)
    assert len(sent) == 1 and sent[0].startswith("invoke --view=") and "cursor" not in sent[0]
    assert view.state == "loading" and not state.backend_ready
    tui._collection_key(27, screen, 1, state)
    assert state.collection is None


def test_two_page_cache_frozen_identity_and_expired_back():
    entry, result = fixture(count=1)
    result["result"]["page"].update(has_more=True, total_count=3, next_cursor="OPAQUE_CONTINUATION")
    view = tui.CollectionView(entry)
    view.accept(result)
    for i in range(1, 3):
        command = view.request("next")
        assert "OPAQUE_CONTINUATION" in command
        page = json.loads(json.dumps(result))
        page["result"]["rows"][0]["reference"]["object_id"] = f"service:systemd:page{i}.service"
        page["result"]["rows"][0]["unit"] = f"page{i}.service"
        if i == 2:
            page["result"]["page"].update(has_more=False)
            del page["result"]["page"]["next_cursor"]
        view.accept(page)
        assert view.state == "ready"
    assert len(view.pages) == 2 and view.pages[0][1] == 1
    assert view.cached_page(-1)
    view.expires = time.monotonic() - 1
    assert not view.cached_page(1) and view.selected_reference() is None
    assert view.state == "expired"
    assert "OPAQUE_CONTINUATION" not in json.dumps(view.inspect())


@pytest.mark.parametrize("reason,state", [("collection_expired", "expired"), ("invalid_collection_cursor", "expired"),
                                         ("collection_budget_exhausted", "unavailable"), ("collection_limit_exceeded", "unavailable")])
def test_canonical_failure_states(reason, state):
    entry, result = fixture()
    result.update(execution_status="failed", outcome="failed", output_status="not_applicable", result=None,
                  verification_evidence=[{"reason": reason}])
    view = tui.CollectionView(entry)
    view.accept(result)
    assert view.state == state and view.selected_reference() is None


@pytest.mark.parametrize("command", ["fixture.resources.list", "sys.service.list", "system.service.list"])
def test_pasted_leaf_uses_existing_explorer_resolution(command, monkeypatch):
    entry, _ = fixture()
    entry.update(path="system.service.list" if command.startswith(("sys.", "system.")) else command,
                 target_id="system.service.list" if command.startswith(("sys.", "system.")) else command)
    state = tui.EventState(backend_ready=True, operator_snapshot={"entries": [entry], "aliases": {"sys": "system"}})
    sent = []
    monkeypatch.setattr(tui, "_send", lambda _, text: sent.append(text))
    monkeypatch.setattr(tui.os, "read", lambda *_: (_ for _ in ()).throw(BlockingIOError()))
    class Reader:
        def read(self):
            return []
    selected = tui._operator_overlay(Screen(), 1, Reader(), state, tui.InputBuffer(), command)
    assert selected == sent[0] and selected.startswith("invoke --view=")
    assert entry["target_id"] + "@fixture" in selected and state.collection.state == "loading"


@pytest.mark.parametrize("change", ["revision", "freshness", "scope", "omission", "duplicate"])
def test_next_page_cannot_mix_replace_or_omit_frozen_rows(change):
    entry, result = fixture(count=1)
    result["result"]["page"].update(total_count=2, has_more=True, next_cursor="OPAQUE")
    view = tui.CollectionView(entry)
    view.accept(result)
    view.request("next")
    page = copy.deepcopy(result)
    page["result"]["rows"][0]["unit"] = "new.service"
    page["result"]["rows"][0]["reference"]["object_id"] = "service:systemd:new.service"
    page["result"]["page"].update(has_more=False)
    del page["result"]["page"]["next_cursor"]
    if change == "revision": page["result"]["page"]["snapshot_revision"] = "different"
    elif change == "freshness": page["result"]["freshness"] = fixture()[1]["result"]["freshness"]
    elif change == "scope": page["result"]["rows"][0]["reference"]["scope_id"] = "scope:" + "b" * 32
    elif change == "omission": page["result"]["page"]["total_count"] = 3
    else: page["result"]["rows"][0]["reference"] = result["result"]["rows"][0]["reference"]
    view.accept(page)
    assert view.state == "invalid" and view.selected_reference() is None


@pytest.mark.parametrize("change", ["disabled", "removed", "descriptor"])
def test_registry_lifecycle_revokes_frontend_state(change):
    entry, result = fixture()
    view = tui.CollectionView(entry)
    view.accept(result)
    state = tui.EventState(collection=view)
    updated = copy.deepcopy(entry)
    if change == "disabled": updated["availability"] = "unavailable"
    elif change == "descriptor": updated["collection"]["columns"][0]["label"] = "Changed"
    snapshot = {"entries": [] if change == "removed" else [updated]}
    assert tui.apply_event(state, {"event_type": "operator_snapshot", "sequence": 1, "surface": snapshot})
    assert view.state == "unavailable" and view.selected_reference() is None


def test_64k_utf8_page_and_96k_event_exact_boundaries():
    entry, result = fixture("volumes", count=16)
    for row in result["result"]["rows"]:
        row["label"] = "é" * 2000
    size = lambda item: len(json.dumps(item, ensure_ascii=False, separators=(",", ":")).encode())
    excess = size(result["result"]) - 65536
    assert excess > 0
    result["result"]["rows"][-1]["label"] = "é" * (2000 - (excess + 1) // 2) + ("a" if excess % 2 else "")
    assert size(result["result"]) == 65536
    event = {"event_type": "action_result", "sequence": 1, "result": result, "padding": ""}
    event["padding"] = "x" * (98304 - size(event))
    assert size(event) == 98304
    state = tui.EventState(operator_snapshot={"entries": [entry]})
    assert tui.apply_event(state, event) and state.collection.state == "ready"
    view = tui.CollectionView(entry)
    view.request()
    oversized = dict(event, sequence=2, view_request_id=view.request_id)
    state.collection = view
    assert not tui.apply_event(state, oversized) and view.state == "invalid"
    result["result"]["rows"][-1]["label"] += "é"
    view.accept(result)
    assert view.state == "invalid"


def test_session_fence_late_warning_and_duplicate_operation():
    entry, result = fixture()
    state = tui.EventState(operator_snapshot={"entries": [entry]}, session_id="current")
    event = {"event_type": "action_result", "sequence": 1, "result": result, "session_id": "other"}
    assert not tui.apply_event(state, event) and state.collection is None
    event["session_id"] = "current"
    assert tui.apply_event(state, event)
    state.collection.move(2)
    assert tui.apply_event(state, dict(event, sequence=2)) and state.collection.selection == 2
    state.collection.request()
    old = state.collection.request_id
    state.collection.request()
    assert tui.apply_event(state, {"event_type": "warning", "sequence": 3, "view_request_id": old, "display": "REJECTED"})
    assert state.collection.state == "loading" and "REJECTED" not in str(state.activity)


def test_frontend_render_and_navigation_measurement():
    entry, result = fixture("volumes", count=128)
    view = tui.CollectionView(entry)
    baseline = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    view.accept(result)
    screen = Screen()
    started = time.perf_counter()
    for _ in range(200):
        view.move(1)
        tui._draw_collection(screen, view)
    elapsed = time.perf_counter() - started
    assert view.selected_reference() is not None
    measurement = {"environment": platform.platform(), "surface": "real navigation/renderer with recording curses screen",
                   "frames": 200, "seconds": elapsed, "mean_frame_seconds": elapsed / 200,
                   "baseline_peak_rss_kib": baseline, "peak_rss_kib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
                   "limitation": "pytest-process high-water observations, not isolated incremental frontend peak memory"}
    if os.environ.get("IGOR_VALIDATION_REPORT"):
        (Path(os.environ["IGOR_VALIDATION_REPORT"]).parent / "collection-render-measurement.json").write_text(json.dumps(measurement, indent=2) + "\n")


def test_managed_secret_in_collection_is_rejected_without_ui_retention(tmp_path, monkeypatch):
    from secret_refs import ManagedOpenRouterSecret
    ManagedOpenRouterSecret(tmp_path / "secrets", tmp_path / "data").stage(
        b"UI_PRIVATE_SENTINEL", source_kind="private_input", expected_revision=0)
    monkeypatch.setenv("IGOR_DIR", str(tmp_path))
    monkeypatch.setenv("IGOR_SECRETS_DIR", str(tmp_path / "secrets"))
    monkeypatch.setenv("IGOR_DATA_DIR", str(tmp_path / "data"))
    entry, result = fixture("volumes")
    result["result"]["rows"][0]["label"] = "UI_PRIVATE_SENTINEL"
    state = tui.EventState(operator_snapshot={"entries": [entry]})
    assert tui.apply_event(state, {"event_type": "action_result", "sequence": 1, "result": result})
    assert state.collection.state == "invalid" and state.collection.pages == []
    assert "UI_PRIVATE_SENTINEL" not in str(state.activity) + json.dumps(state.collection.inspect())


def test_wide_combining_cells_keep_column_width_and_inspection_expires():
    assert tui.cell_text("漢", 4, pad=True) == "漢  "
    assert tui.cell_text("é\u0301", 4, pad=True) == "é\u0301   "
    assert tui.cell_text("\u0301", 4, pad=True) == "?   "
    entry, result = fixture()
    view = tui.CollectionView(entry)
    view.accept(result)
    view.expires = time.monotonic() - 1
    inspection = view.inspect()
    assert inspection["state"] == "expired" and inspection["page"] is None and inspection["selected_reference"] is None


def test_rejected_unknown_descriptor_events_keep_transcript_bounded():
    state = tui.EventState(operator_snapshot={"entries": []})
    for sequence in range(1, 2101):
        assert tui.apply_event(state, {"event_type": "action_result", "sequence": sequence,
                                       "result": {"capability_version": 3, "result": "REJECTED_SENTINEL"}})
    assert state.collection is None and len(state.activity) == 2000
    assert "REJECTED_SENTINEL" not in str(state.activity)
