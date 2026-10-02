"""15UI presentation contracts and real existing-backend inspection/edit slices."""

import copy
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/ai"))
sys.path.insert(0, str(ROOT / "core/lib"))
import interaction
import tui
from operational_history import OperationalHistory

SNAPSHOT = {"provider": "ollama", "model": "fixture-model", "temperature": "0.7",
            "max_tokens": "4096", "mode": "assist", "verbose": "false",
            "ai_autostart": "false", "hybrid_menu": "false"}


def prop(kind="text", **changes):
    schema = {"id": "fixture.value", "label": "Fixture", "type": kind,
              "value": "text", "editable": True, "source": "fixture backend"}
    schema.update(changes)
    return interaction.parse_property(schema)


class Screen:
    def __init__(self, keys=(), size=(24, 100)):
        self.keys = list(keys)
        self.size = size
        self.drawn = []

    def keypad(self, _value):
        pass

    def timeout(self, _value):
        pass

    def getmaxyx(self):
        return self.size

    def erase(self):
        pass

    def addnstr(self, *args):
        self.drawn.append(args[2])

    def hline(self, *_args):
        pass

    def move(self, *_args):
        pass

    def refresh(self):
        pass

    def getch(self):
        return self.keys.pop(0) if self.keys else -1


def run_keys(keys, state=None):
    screen = Screen(keys)
    state = state or tui.EventState()
    # This fixture has no backend process; model the explicit stdin-ready
    # boundary that a real backend now emits before accepting normal input.
    if not state.pending_action and not state.privilege_waiting:
        state.backend_ready = True

    def read_events():
        return [] if screen.keys else [{"event_type": "session_finished",
                                       "sequence": state.sequence + 1}]

    with patch.object(tui.EventReader, "read", side_effect=read_events), \
            patch.object(tui.os, "read", side_effect=BlockingIOError), \
            patch.object(tui, "_child_exit_code", return_value=0), \
            patch.object(tui, "_send") as send, \
            patch.object(tui.curses, "ACS_HLINE", "-", create=True):
        assert tui._loop(screen, 123, 17, Path("unused.jsonl"), state) == 0
    return screen, send, state


class FocusNavigationTests(unittest.TestCase):
    def test_focus_cycles_only_visible_regions_and_close_returns_input(self):
        focus = interaction.FocusModel()
        focus.cycle()
        self.assertEqual(focus.region, "output")
        focus.cycle()
        self.assertEqual(focus.region, "input")
        focus.toggle_panel()
        self.assertEqual((focus.region, focus.panel_open), ("panel", True))
        focus.cycle()
        self.assertEqual(focus.region, "input")
        focus.cycle(reverse=True)
        self.assertEqual(focus.region, "panel")
        focus.toggle_panel()
        self.assertEqual((focus.region, focus.panel_open), ("input", False))
        with self.assertRaises(ValueError):
            focus.set_focus("panel")
        with self.assertRaises(ValueError):
            focus.set_focus("policy")

    def test_navigation_preserves_composer_and_historical_view(self):
        focus, navigator = interaction.FocusModel(), tui.ActivityNavigator()
        draft = tui.InputBuffer()
        draft.insert("unfinished\nrequest")
        self.assertTrue(tui.navigation_key(tui.curses.KEY_PPAGE, focus, navigator, 8, 30))
        self.assertEqual(navigator.scroll, 8)
        navigator.preserve_view(3, 33)
        self.assertEqual(navigator.scroll, 11)
        tui.navigation_key(9, focus, navigator, 8, 33)
        tui.navigation_key(tui.curses.KEY_HOME, focus, navigator, 8, 33)
        self.assertEqual(navigator.scroll, 33)
        tui.navigation_key(tui.curses.KEY_DOWN, focus, navigator, 8, 33)
        self.assertEqual(navigator.scroll, 32)
        tui.navigation_key(6, focus, navigator, 8, 33)
        self.assertEqual(navigator.scroll, 0)
        self.assertEqual(draft.text(), "unfinished\nrequest")

    def test_mouse_wheel_only_over_output_and_click_focus(self):
        focus, navigator = interaction.FocusModel(), tui.ActivityNavigator()
        focus.toggle_panel()
        with patch.object(tui.curses, "BUTTON5_PRESSED", 2, create=True), \
                patch.object(tui.curses, "BUTTON4_PRESSED", 1, create=True), \
                patch.object(tui.curses, "BUTTON1_CLICKED", 4, create=True), \
                patch.object(tui.curses, "BUTTON1_PRESSED", 8, create=True):
            self.assertTrue(tui.mouse_navigation((0, 2, 3, 0, 1), focus, navigator, 24, 100, 18, 40))
            self.assertEqual(navigator.scroll, 3)
            self.assertFalse(tui.mouse_navigation((0, 80, 3, 0, 1), focus, navigator, 24, 100, 18, 40))
            self.assertFalse(tui.mouse_navigation((0, 2, 23, 0, 1), focus, navigator, 24, 100, 18, 40))
            tui.mouse_navigation((0, 2, 3, 0, 2), focus, navigator, 24, 100, 18, 40)
            self.assertEqual(navigator.scroll, 0)
            tui.mouse_navigation((0, 2, 3, 0, 4), focus, navigator, 24, 100, 18, 40)
            self.assertEqual(focus.region, "output")
            tui.mouse_navigation((0, 80, 3, 0, 4), focus, navigator, 24, 100, 18, 40)
            self.assertEqual(focus.region, "panel")
            tui.mouse_navigation((0, 2, 23, 0, 4), focus, navigator, 24, 100, 18, 40)
            self.assertEqual(focus.region, "input")

    def test_loop_panel_selection_scroll_and_close_preserve_draft(self):
        keys = list(map(ord, "draft")) + [2, tui.curses.KEY_DOWN,
                tui.curses.KEY_NPAGE, tui.curses.KEY_HOME, 2, 10]
        screen, send, _state = run_keys(keys)
        self.assertEqual(send.call_args_list, [unittest.mock.call(17, "draft")])
        self.assertTrue(any("Focus:PANEL" in row for row in screen.drawn))
        self.assertTrue(any("> AI (read-only)" in row for row in screen.drawn))
        self.assertTrue(any("routing_authority" in row for row in screen.drawn))

    def test_output_focus_does_not_submit_draft_or_insert_navigation(self):
        keys = list(map(ord, "draft")) + [9, tui.curses.KEY_UP, 10, 10]
        _screen, send, _state = run_keys(keys)
        self.assertEqual(send.call_args_list, [unittest.mock.call(17, "draft")])

    def test_panel_page_keys_scroll_content_without_output_navigation(self):
        state = tui.EventState(settings_snapshot=copy.deepcopy(SNAPSHOT))
        positions = []
        original_draw = tui._draw

        def draw(screen, state, buffer, navigator, focus, sections):
            original_draw(screen, state, buffer, navigator, focus, sections)
            positions.append((focus.panel_scroll, navigator.scroll))

        keys = [2, tui.curses.KEY_DOWN, tui.curses.KEY_DOWN, tui.curses.KEY_NPAGE,
                tui.curses.KEY_PPAGE, tui.curses.KEY_END, tui.curses.KEY_HOME, 2]
        with patch.object(tui, "_draw", side_effect=draw):
            _screen, send, _ = run_keys(keys, state)
        send.assert_not_called()
        self.assertTrue(any(panel > 0 for panel, _output in positions))
        self.assertTrue(all(output == 0 for _panel, output in positions))
        self.assertEqual(positions[-1], (0, 0))

    def test_draw_live_indicator_focus_resize_and_reopen_are_presentation_only(self):
        state = tui.EventState(settings_snapshot=copy.deepcopy(SNAPSHOT))
        state.accept({"event_type": "assistant_message", "sequence": 1,
                      "display": "\n".join(f"line {n}" for n in range(60))})
        before = copy.deepcopy(state)
        screen, focus = Screen(), interaction.FocusModel()
        navigator, draft = tui.ActivityNavigator(scroll=10), tui.InputBuffer()
        draft.insert("draft")
        focus.toggle_panel()
        with patch.object(tui.curses, "ACS_HLINE", "-", create=True):
            tui._draw(screen, state, draft, navigator, focus,
                      tui.panel_sections(state, tui.HistoryInspection()))
            focus.toggle_panel()
            screen.size = (12, 50)
            tui._draw(screen, state, draft, navigator, focus)
            focus.toggle_panel()
            tui._draw(screen, state, draft, navigator, focus,
                      tui.panel_sections(state, tui.HistoryInspection()))
        self.assertEqual(state, before)
        self.assertEqual(draft.text(), "draft")
        self.assertTrue(any("Ctrl+F=live" in row for row in screen.drawn))
        navigator.latest()
        with patch.object(tui.curses, "ACS_HLINE", "-", create=True):
            tui._draw(screen, state, draft, navigator, focus)
        self.assertTrue(any("LIVE" in row for row in screen.drawn))


class PropertyControlTests(unittest.TestCase):
    def test_five_typed_controls_and_detached_proposals(self):
        fixtures = [prop(), prop("enum", value="one", options=["one", "two"]),
                    prop("boolean", value=False), prop("integer", value=2, minimum=1),
                    prop("number", value=0.7, minimum=0, maximum=2)]
        expected = ["new", "two", True, 3, 1.2]
        texts = ["new", "two", "true", "3", "1.2"]
        with patch.object(tui, "_send") as send:
            for field, text, result in zip(fixtures, texts, expected):
                value = interaction.parse_control_input(field, text)
                self.assertEqual(interaction.propose_property(field, value),
                                 {"property_id": "fixture.value", "value": result})
                self.assertIn("[" + field.type + "]", interaction.property_text(field))
        send.assert_not_called()

    def test_generic_editor_returns_data_without_backend_write(self):
        with patch.object(tui, "_send") as send:
            self.assertEqual(tui.edit_property(Screen(), prop("boolean", value=False)),
                             {"property_id": "fixture.value", "value": True})
            screen = Screen([21, ord("3"), 10])
            self.assertEqual(tui.edit_property(screen, prop("integer", value=2))["value"], 3)
        send.assert_not_called()

    def test_malformed_unknown_schema_and_values_fail_without_commands(self):
        schemas = [None, [], {"id": "x", "type": "command", "value": "rm"},
                   {"id": "x", "type": "text", "handler": "writer"},
                   {"id": "../secrets", "type": "text"},
                   {"id": "x", "type": "boolean", "value": "false"},
                   {"id": "x", "type": "number", "value": float("nan")},
                   {"id": "x", "type": "text", "editable": "true"},
                   {"id": "x", "type": "enum", "options": []}]
        for schema in schemas:
            with self.subTest(schema=schema), self.assertRaises(ValueError):
                interaction.parse_property(schema)
        fixtures = [(prop(), "a\nb"), (prop("enum", value="a", options=["a"]), "b"),
                    (prop("boolean", value=False), "yes"), (prop("integer", value=2), "2.5"),
                    (prop("number", value=1), "nan"), (prop("number", value=1), "inf"),
                    (prop("number", value=1, maximum=2), "3")]
        for field, text in fixtures:
            with self.subTest(text=text), self.assertRaises(ValueError):
                interaction.parse_control_input(field, text)
        rows = interaction.render_properties(schemas)
        self.assertTrue(all("Invalid" in row for row in rows))

    def test_no_defaults_or_secret_values_and_readonly_proposals_rejected(self):
        schema = {"id": "fixture", "type": "text", "editable": True, "source": "module"}
        field = interaction.parse_property(schema)
        self.assertFalse(field.available)
        self.assertFalse(field.editable)
        self.assertIn("unavailable", interaction.property_text(field))
        secret = {**schema, "value": "never-visible", "secret": True}
        field = interaction.parse_property(secret)
        self.assertIsNone(field.value)
        self.assertNotIn("never-visible", " ".join(interaction.render_properties([secret])))
        with self.assertRaises(ValueError):
            interaction.propose_property(field, "replacement")
        with self.assertRaises(ValueError):
            interaction.propose_property(prop(editable=False), "replacement")

    def test_existing_settings_adapter_validates_and_never_optimistically_updates(self):
        before = copy.deepcopy(SNAPSHOT)
        field = interaction.parse_property(tui.settings_properties(SNAPSHOT)[2])
        proposal = interaction.propose_property(field, 1.2)
        self.assertEqual(tui.settings_proposal_command(proposal, SNAPSHOT), "settings temperature 1.2")
        self.assertEqual(SNAPSHOT, before)
        with self.assertRaises(ValueError):
            tui.settings_proposal_command({"property_id": "password", "value": "x"}, SNAPSHOT)
        with self.assertRaises(ValueError):
            tui.settings_proposal_command({"property_id": "temperature", "value": "1.2"}, SNAPSHOT)
        self.assertTrue(all(not row.get("value") for row in tui.settings_properties({})))


class InspectionAuthorityTests(unittest.TestCase):
    def test_structured_inspection_preserves_provenance_and_hides_secrets(self):
        data = {"scope_id": "scope:fixture", "owner": "system", "source": "host.memory",
                "facts": [{"property": "memory.available_bytes", "value": 123,
                           "availability": "known"}], "api_key": "never-visible",
                "secret_field": {"secret": True, "value": "also-hidden"}}
        before = copy.deepcopy(data)
        rows = interaction.render_structured(data)
        self.assertEqual(data, before)
        self.assertIn("source: host.memory", " ".join(rows))
        self.assertIn("availability: known", " ".join(rows))
        self.assertNotIn("never-visible", " ".join(rows))
        self.assertNotIn("also-hidden", " ".join(rows))

    def test_inspection_unknown_cycle_and_large_results_are_bounded(self):
        cycle = {"self": None}
        cycle["self"] = cycle
        self.assertIn("bounded", " ".join(interaction.render_structured(cycle)))
        self.assertLessEqual(len(interaction.render_structured(list(range(1000)))), 200)
        self.assertIn("unsupported", " ".join(interaction.render_structured(object())))
        state = tui.EventState()
        for payload in (None, [], {"event_type": []}, {"event_type": "ui_apply", "sequence": 5}):
            self.assertFalse(state.accept(payload))
        self.assertEqual(state.sequence, 0)
        self.assertIsNone(state.pending_action)

    def test_ai_role_provider_model_are_readonly_event_projection(self):
        state = tui.EventState()
        state.accept({"event_type": "model_status", "sequence": 1, "role": "reasoner",
                      "provider": "configured", "model": "actual", "status": "ready"})
        before = copy.deepcopy(state)
        section = tui.panel_sections(state, tui.HistoryInspection())[1]
        rendered = " ".join(tui.panel_rows(section))
        self.assertIn("role: reasoner", rendered)
        self.assertIn("provider: configured", rendered)
        self.assertIn("model: actual", rendered)
        _screen, send, _ = run_keys([2, tui.curses.KEY_DOWN, 10, 2], state)
        send.assert_not_called()
        self.assertEqual(state.provider, before.provider)
        self.assertEqual(state.model, before.model)
        self.assertEqual(state.role, before.role)

    def test_panel_cannot_approve_and_pending_settings_never_send(self):
        state = tui.EventState(pending_action={"operation_id": "op", "classification": "DESTROY"})
        keys = [2, tui.curses.KEY_DOWN, tui.curses.KEY_DOWN, 10, 2] + list(map(ord, "YES\n"))
        _screen, send, _ = run_keys(keys, state)
        self.assertEqual(send.call_args_list, [unittest.mock.call(17, "YES")])
        self.assertEqual(state.pending_action["classification"], "DESTROY")
        with patch.object(tui, "_send") as send:
            tui._settings_overlay(Screen(), 17, tui.EventReader(Path("unused")), state)
        send.assert_not_called()

    def test_frontend_restart_drops_selections_and_emits_no_stale_intent(self):
        state = tui.EventState(settings_snapshot=copy.deepcopy(SNAPSHOT))
        _screen, send, _ = run_keys([2, tui.curses.KEY_DOWN], state)
        send.assert_not_called()
        _screen, send, _ = run_keys([], tui.EventState())
        send.assert_not_called()

    def test_plain_question_answer_keeps_existing_backend_choice_routing(self):
        _screen, send, _ = run_keys([2, 2, ord("2"), 10])
        self.assertEqual(send.call_args_list, [unittest.mock.call(17, "2")])
        script = '''source "$IGOR_DIR/core/ai/core.sh"
_ai_pending_choice_capture 'Which area?
1. Memory
2. Storage'
_ai_pending_choice_route_input "$1" || exit $?
printf '%s' "$_AI_PENDING_CHOICE_ROUTED_INPUT"
'''
        result = subprocess.run(["bash", "-c", script, "choice-fixture", "2"],
                                env={**os.environ, "IGOR_DIR": str(ROOT)},
                                capture_output=True, text=True, check=True)
        self.assertIn("Storage", result.stdout)


class ExistingBackendSlices(unittest.TestCase):
    def test_typed_setting_real_backend_handler_persists_and_reports_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            setting = interaction.parse_property(tui.settings_properties(SNAPSHOT)[2])
            proposal = interaction.propose_property(setting, 1.2)
            command = tui.settings_proposal_command(proposal, SNAPSHOT)
            self.assertEqual(command, "settings temperature 1.2")
            script = '''source "$IGOR_DIR/core/ai/core.sh"
provider=ollama model=fixture-model max_tokens=4096 ai_mode=assist
IGOR_VERBOSE=false AI_AUTOSTART=false AI_HYBRID_MODE=false NEXUS_TEMPERATURE=0.7
_ai_save_settings() { _ai_persist_settings "$FIXTURE_SETTINGS"; }
_ai_apply_session_setting "$1" "$2"
'''
            env = {**os.environ, "IGOR_DIR": str(ROOT), "IGOR_RUNTIME_DIR": str(temp),
                   "IGOR_AI_EVENT_STREAM": str(temp / "events.jsonl"),
                   "FIXTURE_SETTINGS": str(temp / "settings")}
            result = subprocess.run(["bash", "-c", script, "settings-fixture",
                                     proposal["property_id"], str(proposal["value"])],
                                    env=env, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("temperature=1.2", (temp / "settings").read_text())
            state = tui.EventState()
            for event in tui.EventReader(temp / "events.jsonl").read():
                state.accept(event)
            self.assertEqual(state.settings_snapshot["temperature"], "1.2")
            rows = interaction.render_properties(tui.settings_properties(state.settings_snapshot))
            self.assertIn("Temperature [number]: 1.2", rows)

    def test_real_history_inspection_reads_service_without_write_or_recovery(self):
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory) / "data"
            service = OperationalHistory(data)
            proposal = {"capability_id": "system.service.restart", "capability_version": 1,
                        "provider": "fixture", "owner": "system", "inputs": {},
                        "safety": {"tier": "CHANGE"}, "privilege": "none",
                        "precondition_status": "satisfied", "verification": {"kind": "none", "required": False},
                        "recovery": {"class": "best_effort"}, "affected_objects": []}
            row = service.prepare(proposal, correlation_id="corr-ui",
                                  provenance={"actor": "operator", "interface": "fixture", "request_id": None})
            before = {path: path.read_bytes() for path in data.rglob("*") if path.is_file()}
            query = tui.HistoryInspection()
            with patch.dict(os.environ, {"IGOR_DATA_DIR": str(data)}):
                try:
                    query.start()
                    deadline = time.monotonic() + 8
                    while query.process is not None and time.monotonic() < deadline:
                        query.poll()
                        time.sleep(0.01)
                finally:
                    query.close()
            self.assertEqual(query.data[0]["operation_id"], row["operation_id"], query.status)
            section = next(section for section in tui.panel_sections(tui.EventState(), query)
                           if section["id"] == "history")
            rendered = " ".join(tui.panel_rows(section))
            self.assertIn("corr-ui", rendered)
            self.assertIn("Source: --history recent 20", rendered)
            self.assertIn("scope_id", rendered)
            self.assertEqual({path: path.read_bytes() for path in data.rglob("*") if path.is_file()}, before)

    def test_history_query_lazy_headless_absent_store_stays_absent(self):
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory) / "absent"
            query = tui.HistoryInspection()
            self.assertIsNone(query.process)
            with patch.dict(os.environ, {"IGOR_DATA_DIR": str(data)}):
                try:
                    query.start()
                    deadline = time.monotonic() + 8
                    while query.process is not None and time.monotonic() < deadline:
                        query.poll()
                        time.sleep(0.01)
                finally:
                    query.close()
            self.assertEqual(query.data, [])
            self.assertFalse(data.exists())
            result = subprocess.run(["bash", str(ROOT / "igor.sh"), "--history", "recent", "20"],
                                    env={**os.environ, "IGOR_DATA_DIR": str(data)},
                                    capture_output=True, text=True, check=True)
            self.assertEqual(json.loads(result.stdout), [])
            self.assertFalse(data.exists())

    def test_history_failure_timeout_and_cancel_cleanup(self):
        query = tui.HistoryInspection()
        with patch.object(tui.subprocess, "Popen", side_effect=OSError):
            query.start()
        self.assertIsNone(query.process)
        self.assertIn("unavailable", query.status)
        # Use a local sleeping inspection fixture only to exercise cancellation.
        with patch.object(tui.subprocess, "Popen", wraps=subprocess.Popen) as launch:
            process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(20)"],
                                       stdout=subprocess.PIPE, start_new_session=True)
            query.process = process
            os.set_blocking(process.stdout.fileno(), False)
            query.started = time.monotonic() - 10
            self.assertTrue(query.poll())
            self.assertIsNotNone(process.returncode)
            self.assertIsNone(query.process)
            self.assertIn("timed out", query.status)
            self.assertEqual(launch.call_count, 1)


if __name__ == "__main__":
    unittest.main()
