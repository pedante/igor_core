#!/usr/bin/env python3
"""Focused tests for the lightweight structured-event TUI boundary."""

import os
import sys
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "core", "ai"))
import tui  # noqa: E402


def event(kind, sequence, **fields):
    return {"event_type": kind, "sequence": sequence, **fields}


class EventProjectionTests(unittest.TestCase):
    def test_events_are_applied_in_order_and_duplicates_are_ignored(self):
        state = tui.EventState()

        self.assertTrue(tui.apply_event(
            state, event("session_started", 1, mode="guide", status="ready")))
        self.assertTrue(tui.apply_event(
            state, event("assistant_message", 2, display="Inspecting")))
        self.assertFalse(tui.apply_event(
            state, event("continuation", 2, display="stale")))
        self.assertFalse(tui.apply_event(
            state, event("warning", 1, display="out of order")))

        self.assertEqual(state.sequence, 2)
        self.assertEqual([item.event_type for item in state.activity],
                         ["assistant_message"])
        self.assertEqual(state.activity[0].text, "Inspecting")

    def test_unknown_events_do_not_change_frontend_state(self):
        state = tui.EventState()
        self.assertFalse(tui.apply_event(state, event("provider_secret", 1,
                                                       display="secret")))
        self.assertEqual(state.sequence, 0)
        self.assertEqual(state.activity, [])

    def test_mode_and_status_are_rendered_from_structured_events(self):
        state = tui.EventState()
        tui.apply_event(state, event("session_started", 1, mode="assist",
                                     status="ready", provider="ollama",
                                     model="small"))
        tui.apply_event(state, event("mode_changed", 2, mode="executive",
                                     status="executive", display="Mode: executive"))

        self.assertEqual(state.mode, "executive")
        self.assertEqual(state.session_status, "ready")
        self.assertEqual(state.provider, "ollama")
        self.assertEqual(state.model, "small")
        self.assertEqual(tui.render_activity(state, 100)[-1],
                         "Mode: executive")

    def test_assistant_message_has_a_clear_speaker_label(self):
        state = tui.EventState()
        tui.apply_event(state, event("assistant_message", 1, display="Ready"))
        self.assertEqual(tui.render_activity(state, 80), ["Igor: Ready"])

    def test_action_lifecycle_keeps_canonical_result_data(self):
        state = tui.EventState()
        tui.apply_event(state, event("action_proposed", 1, action_id="a1",
                                     classification="READ", display="which vlc"))
        tui.apply_event(state, event("action_started", 2, action_id="a1",
                                     display="running"))
        result = {"execution_status": "tool_succeeded", "exit_code": 0,
                  "combined_output": "vlc 3.0"}
        tui.apply_event(state, event("action_result", 3, action_id="a1",
                                     classification="READ", result=result,
                                     display="completed"))

        self.assertEqual(state.activity[-1].result, result)
        self.assertEqual(state.activity[0].classification, "READ")
        self.assertEqual([item.event_type for item in state.activity],
                         ["action_proposed", "action_started", "action_result"])

    def test_operation_id_is_the_canonical_action_identity(self):
        state = tui.EventState()
        tui.apply_event(state, event("approval_waiting", 1,
                                     operation_id="op-1", tool="host",
                                     classification="CHANGE", display="change"))
        self.assertEqual(state.pending_action["operation_id"], "op-1")
        tui.apply_event(state, event("action_result", 2, operation_id="op-2",
                                     result={"execution_status": "tool_succeeded"}))
        self.assertIsNotNone(state.pending_action)
        tui.apply_event(state, event("action_result", 3, operation_id="op-1",
                                     result={"execution_status": "tool_succeeded"}))
        self.assertIsNone(state.pending_action)
        self.assertEqual(state.activity[0].action_id, "op-1")

    def test_approval_explain_skip_and_stop_are_visible_and_clear_pending(self):
        state = tui.EventState()
        tui.apply_event(state, event("approval_waiting", 1, action_id="a1",
                                     classification="CHANGE", display="install vlc"))
        self.assertEqual(state.pending_action["action_id"], "a1")

        tui.apply_event(state, event("explanation", 2, action_id="a1",
                                     display="This changes packages"))
        self.assertIsNotNone(state.pending_action)
        tui.apply_event(state, event("action_declined", 3, action_id="a1",
                                     display="Declined"))
        self.assertIsNone(state.pending_action)

        tui.apply_event(state, event("approval_waiting", 4, action_id="a2",
                                     classification="DESTROY", display="remove data"))
        tui.apply_event(state, event("action_stopped", 5, action_id="a2",
                                     display="Stopped"))
        self.assertIsNone(state.pending_action)
        self.assertEqual([item.event_type for item in state.activity],
                         ["approval_waiting", "explanation", "action_declined",
                          "approval_waiting", "action_stopped"])

    def test_all_modes_and_safety_tiers_remain_display_data(self):
        state = tui.EventState()
        for sequence, mode, tier in (
            (1, "guide", "READ"),
            (2, "assist", "CHANGE"),
            (3, "executive", "DESTROY"),
        ):
            tui.apply_event(state, event("action_proposed", sequence, mode=mode,
                                         action_id=f"a{sequence}",
                                         classification=tier, display=tier))
        self.assertEqual([item.classification for item in state.activity],
                         ["READ", "CHANGE", "DESTROY"])
        self.assertEqual(state.mode, "executive")


class InputAndRenderingTests(unittest.TestCase):
    def test_multiline_tool_output_is_one_ordered_activity_block(self):
        state = tui.EventState()
        tui.apply_event(state, event("action_output", 1, operation_id="op-1",
                                     display="first line\nsecond line\nthird line"))
        self.assertEqual(len(state.activity), 1)
        self.assertEqual(tui.render_activity(state, 80),
                         ["first line", "second line", "third line"])

    def test_structured_output_prevents_duplicate_result_body(self):
        state = tui.EventState()
        output = "package version 1.2"
        tui.apply_event(state, event("action_output", 1, operation_id="op-1",
                                     tool_call_id="call-1", display=output))
        tui.apply_event(state, event("action_result", 2, action_id="call-1",
                                     result={"execution_status": "tool_succeeded",
                                             "exit_code": 0, "combined_output": output}))
        rendered = "\n".join(tui.render_activity(state, 80))
        self.assertEqual(rendered.count(output), 1)
        self.assertNotIn("Result: tool_succeeded", rendered)

    def test_result_without_output_event_still_shows_canonical_output(self):
        state = tui.EventState()
        tui.apply_event(state, event("action_result", 1, action_id="call-1",
                                     result={"execution_status": "tool_failed",
                                             "combined_output":
                                             "TOOL:host EXIT:1\\nOUTPUT:\\nfailure detail"}))
        self.assertEqual(tui.render_activity(state, 80),
                         ["Result: tool_failed", "failure detail"])

    def test_raw_backend_text_is_ignored_without_local_capture(self):
        state = tui.EventState()
        state.add_terminal_output("DEBUG: scrub warning\nassistant answer\n")
        tui.apply_event(state, event("assistant_message", 1,
                                     display="assistant answer"))
        self.assertEqual(tui.render_activity(state, 80), ["Igor: assistant answer"])

    def test_structured_event_cancels_opaque_local_output(self):
        state = tui.EventState()
        state.begin_terminal_capture()
        state.add_terminal_output("old formatted answer\n")
        tui.apply_event(state, event("assistant_message", 1,
                                     display="structured answer"))
        self.assertEqual(tui.render_activity(state, 80), ["Igor: structured answer"])

    def test_word_wrapping_and_resize_reflow_preserve_content(self):
        state = tui.EventState()
        message = "alpha beta [IGOR:HOSTNAME] gamma delta"
        tui.apply_event(state, event("assistant_message", 1, display=message))
        wide = tui.render_activity(state, 80)
        narrow = tui.render_activity(state, 22)
        self.assertEqual(wide, ["Igor: " + message])
        self.assertEqual("".join(narrow), wide[0])
        self.assertTrue(any("[IGOR:HOSTNAME]" in line for line in narrow))
        self.assertEqual(tui.render_activity(state, 80), wide)

    def test_warning_and_debug_lines_are_compact(self):
        state = tui.EventState()
        state.begin_terminal_capture()
        state.add_terminal_output("DEBUG: scrub scan\nWARNING: review context\n"
                                  "WARNING: review context\n")
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(tui.render_activity(state, 80),
                             ["WARNING: review context"])
        with patch.dict(os.environ, {"IGOR_VERBOSE": "true"}, clear=True):
            self.assertIn("DEBUG: scrub scan", tui.render_activity(state, 80))
        state.end_terminal_capture()
        tui.apply_event(state, event("warning", 1, display="Scrub needs review"))
        tui.apply_event(state, event("warning", 2, display="Scrub needs review"))
        tui.apply_event(state, event("error", 3, display="Refresh failed"))
        self.assertEqual([item.event_type for item in state.activity],
                         ["terminal", "warning", "error"])
        self.assertIn("Warning: Scrub needs review (×2)",
                      tui.render_activity(state, 80))
        self.assertIn("Error: Refresh failed", tui.render_activity(state, 80))

    def test_ordered_event_blocks_do_not_interleave(self):
        state = tui.EventState()
        tui.apply_event(state, event("assistant_message", 1,
                                     display="Before\nSecond sentence"))
        tui.apply_event(state, event("action_output", 2,
                                     display="tool line one\ntool line two"))
        tui.apply_event(state, event("assistant_message", 3, display="After"))
        self.assertEqual(tui.render_activity(state, 80), [
            "Igor: Before", "Second sentence", "",
            "tool line one", "tool line two", "",
            "Igor: After",
        ])

    def test_normal_mode_hides_success_lifecycle_chatter(self):
        state = tui.EventState()
        tui.apply_event(state, event("action_proposed", 1, operation_id="op-1",
                                     classification="READ", display="list services"))
        tui.apply_event(state, event("action_started", 2, operation_id="op-1",
                                     display="list services"))
        tui.apply_event(state, event("action_output", 3, operation_id="op-1",
                                     display="svc.service\tactive\trunning",
                                     exit_code=0, duration_ms=37))
        tui.apply_event(state, event("action_result", 4, operation_id="op-1",
                                     result={"execution_status": "tool_succeeded",
                                             "exit_code": 0}))
        self.assertEqual(tui.render_activity(state, 100),
                         ["svc.service\tactive\trunning"])

    def test_verbose_mode_keeps_lifecycle_and_timing(self):
        state = tui.EventState(verbose=True)
        tui.apply_event(state, event("action_proposed", 1, operation_id="op-1",
                                     classification="READ", display="list services"))
        tui.apply_event(state, event("action_started", 2, operation_id="op-1",
                                     display="list services"))
        tui.apply_event(state, event("action_output", 3, operation_id="op-1",
                                     display="svc.service\tactive\trunning",
                                     exit_code=0, duration_ms=37))
        rendered = tui.render_activity(state, 100)
        self.assertIn("Action [READ]: list services", rendered)
        self.assertIn("Started: list services", rendered)
        self.assertIn("Output (37 ms): svc.service\tactive\trunning", rendered)

    def test_multiline_input_is_independent_from_activity_history(self):
        state = tui.EventState()
        tui.apply_event(state, event("assistant_message", 1, display="old output"))
        buffer = tui.InputBuffer()
        buffer.insert("first line\nsecond line")

        self.assertEqual(buffer.text(), "first line\nsecond line")
        self.assertEqual(tui.render_activity(state, 80),
                         ["Igor: old output"])
        self.assertEqual(buffer.text(), "first line\nsecond line")
        self.assertEqual(len(state.activity), 1)

    def test_input_clear_returns_text_without_rendering_or_executing_it(self):
        buffer = tui.InputBuffer()
        buffer.insert("/stop")
        with patch.object(tui, "_send") as send:
            text = buffer.clear()
            self.assertEqual(text, "/stop")
            send.assert_not_called()
        self.assertEqual(buffer.text(), "")

    def test_send_only_writes_user_intent_to_backend_channel(self):
        writes = []
        with patch.object(tui.os, "write", side_effect=lambda fd, data: writes.append((fd, data))):
            tui._send(17, "/stop")
        self.assertEqual(writes, [(17, b"/stop\n")])

    def test_wide_key_input_keeps_natural_language_characters(self):
        class Screen:
            def get_wch(self):
                return "ü"

        key = tui._next_key(Screen())
        buffer = tui.InputBuffer()
        buffer.insert(key if isinstance(key, str) else chr(key))
        self.assertEqual(buffer.text(), "ü")

    def test_activity_wraps_to_requested_width_and_preserves_order(self):
        state = tui.EventState()
        tui.apply_event(state, event("warning", 1, display="abcdef"))
        tui.apply_event(state, event("error", 2, display="123456"))
        self.assertEqual(tui.render_activity(state, 3),
                         ["War", "nin", "g: ", "abc", "def", "", "Err", "or:", " ", "123", "456"])

    def test_terminal_output_preserves_line_order_after_backend_activity(self):
        state = tui.EventState()
        tui.apply_event(state, event("action_started", 1, display="running"))
        state.begin_terminal_capture()
        state.add_terminal_output("backend line 1\nbackend line 2\n")
        state.add_terminal_output("backend line 3\n")
        lines = tui.render_activity(state, 100)
        self.assertEqual(lines, [
            "backend line 1",
            "backend line 2",
            "backend line 3",
        ])

    def test_event_path_uses_an_absolute_configured_stream(self):
        with tempfile.TemporaryDirectory() as directory:
            configured = Path(directory) / "events.jsonl"
            with patch.dict(os.environ, {"IGOR_AI_EVENT_STREAM": str(configured)}):
                self.assertEqual(tui.event_path(), configured)
                self.assertTrue(tui.event_path().is_absolute())

    def test_partial_jsonl_line_is_retried_after_more_data_arrives(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.jsonl"
            complete = json.dumps(event("warning", 1, display="ready"))
            path.write_text(complete + "\n{" + '"event_type":"error"', encoding="utf-8")
            reader = tui.EventReader(path)
            first = reader.read()
            self.assertEqual(len(first), 1)
            self.assertEqual(first[0]["event_type"], "warning")

            with path.open("a", encoding="utf-8") as stream:
                stream.write(',"sequence":2,"display":"late"}\n')
            second = reader.read()
            self.assertEqual([item["event_type"] for item in second], ["error"])

    def test_private_stream_path_is_scoped_to_runtime_when_default_environment_is_empty(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, {}, clear=True), \
                    patch.object(tui, "REPO_ROOT", Path(directory)):
                stream = tui._private_stream_path()
            self.assertTrue(stream.is_absolute())
            self.assertEqual(stream.parent, Path(directory) / "data" / "runtime")
            self.assertTrue(stream.name.startswith("ai-tui-"))
            self.assertNotEqual(stream.parent, Path.cwd())
            self.assertEqual((Path(directory) / "data" / "runtime").stat().st_mode & 0o777, 0o700)

    def test_palette_reads_the_canonical_registry_and_only_formats_entries(self):
        completed = type("Completed", (), {
            "stdout": "mode\tmode <guide|assist|executive>\tSet interaction mode\n",
        })()
        with patch.object(tui.subprocess, "run", return_value=completed) as run:
            entries = tui.registry_palette("mode")
        self.assertEqual(entries, [{
            "name": "mode",
            "syntax": "mode <guide|assist|executive>",
            "description": "Set interaction mode",
        }])
        command = run.call_args.args[0]
        self.assertEqual(command[-2:], ["ready", "mode"])
        self.assertEqual(command[1], str(Path(tui.__file__).with_name("session_commands.py")))

    def test_palette_prefills_commands_that_need_arguments(self):
        class Screen:
            def __init__(self):
                self.keys = [10]

            def timeout(self, _):
                pass

            def getmaxyx(self):
                return (12, 80)

            def erase(self):
                pass

            def addnstr(self, *_):
                pass

            def refresh(self):
                pass

            def getch(self):
                return self.keys.pop(0)

        buffer = tui.InputBuffer()
        entries = [{"name": "mode", "syntax": "mode guide|assist|executive",
                    "description": "select mode"}]
        with patch.object(tui, "_send") as send:
            tui._palette_overlay(Screen(), 17, buffer, commands=entries)
        self.assertEqual(buffer.text(), "mode ")
        send.assert_not_called()

    def test_palette_sends_a_complete_local_command_to_backend(self):
        class Screen:
            def timeout(self, _):
                pass

            def getmaxyx(self):
                return (12, 80)

            def erase(self):
                pass

            def addnstr(self, *_):
                pass

            def refresh(self):
                pass

            def getch(self):
                return 10

        entries = [{"name": "stats", "syntax": "stats", "description": "show stats"}]
        with patch.object(tui, "_send") as send:
            tui._palette_overlay(Screen(), 17, tui.InputBuffer(), commands=entries)
        send.assert_called_once_with(17, "stats")

    def test_approval_hint_includes_the_backend_classification(self):
        class Screen:
            def __init__(self):
                self.text = []

            def erase(self):
                pass

            def getmaxyx(self):
                return (12, 80)

            def addnstr(self, *args):
                self.text.append(args[2])

            def hline(self, *args):
                pass

            def move(self, *args):
                pass

            def refresh(self):
                pass

        screen = Screen()
        state = tui.EventState(pending_action={"classification": "DESTROY"})
        with patch.object(tui.curses, "ACS_HLINE", "-", create=True):
            tui._draw(screen, state, tui.InputBuffer(), 0)
        self.assertTrue(any("DESTROY pending" in text for text in screen.text))
        self.assertTrue(any("STOP" in text for text in screen.text))

    def test_resize_draw_reads_current_dimensions_and_keeps_input_area(self):
        class Screen:
            def __init__(self):
                self.calls = []

            def erase(self):
                self.calls.append(("erase",))

            def getmaxyx(self):
                return (12, 40)

            def addnstr(self, *args):
                self.calls.append(("text", *args))

            def hline(self, *args):
                self.calls.append(("line", *args))

            def move(self, *args):
                self.calls.append(("move", *args))

            def refresh(self):
                self.calls.append(("refresh",))

        screen = Screen()
        state = tui.EventState(mode="guide", session_status="ready")
        with patch.object(tui.curses, "ACS_HLINE", "-", create=True):
            tui._draw(screen, state, tui.InputBuffer(), 0)
        self.assertEqual(screen.calls[0], ("erase",))
        self.assertIn(("refresh",), screen.calls)
        self.assertTrue(any(call[0] == "line" for call in screen.calls))
        self.assertTrue(any(call[0] == "move" for call in screen.calls))


if __name__ == "__main__":
    unittest.main()
