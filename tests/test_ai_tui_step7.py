#!/usr/bin/env python3
"""Focused daily-use coverage for the lightweight Step 7 frontend."""

import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "core", "ai"))
import tui  # noqa: E402


def event(kind, sequence, **fields):
    return {"event_type": kind, "sequence": sequence, **fields}


class Step7PaletteTests(unittest.TestCase):
    def test_palette_filter_is_case_insensitive_and_uses_registry_descriptions(self):
        entries = tui.palette_entries(tui.registry_commands(), "HISTORY", "ready")
        self.assertTrue(entries)
        self.assertTrue(all(
            "history" in (entry["name"] + entry["syntax"] + entry["description"]).lower()
            for entry in entries
        ))
        self.assertTrue(any(entry["name"] == "history" for entry in entries))

    def test_palette_marks_inapplicable_stop(self):
        entries = tui.palette_entries(tui.registry_commands(), "stop", "stopped_by_user")
        stop = next(entry for entry in entries if entry["name"] == "stop")
        self.assertFalse(stop["available"])

    def test_unavailable_palette_choice_does_not_send_or_replace_draft(self):
        class Screen:
            def __init__(self):
                self.keys = iter((10, 27))
                self.lines = []

            def timeout(self, _value):
                pass

            def getmaxyx(self):
                return (12, 80)

            def erase(self):
                pass

            def addnstr(self, _row, _col, text, *_args):
                self.lines.append(text)

            def refresh(self):
                pass

            def getch(self):
                return next(self.keys)

        command = {"name": "stop", "syntax": "stop", "description": "pause",
                   "states": ["ready"]}
        state = tui.EventState(command_state="stopped_by_user")
        buffer = tui.InputBuffer()
        buffer.insert("unfinished question")
        screen = Screen()
        with patch.object(tui, "_send") as send:
            self.assertIsNone(tui._palette_overlay(screen, 31, buffer, state, [command]))
        send.assert_not_called()
        self.assertEqual(buffer.text(), "unfinished question")
        self.assertTrue(any("unavailable in stopped_by_user" in line
                            for line in screen.lines))

    def test_palette_cancel_preserves_multiline_draft(self):
        class Screen:
            def timeout(self, _value):
                pass

            def getmaxyx(self):
                return (12, 80)

            def erase(self):
                pass

            def addnstr(self, *_args):
                pass

            def refresh(self):
                pass

            def getch(self):
                return 27

        buffer = tui.InputBuffer()
        buffer.insert("first\nsecond")
        with patch.object(tui, "_send") as send:
            tui._palette_overlay(Screen(), 31, buffer, commands=[])
        send.assert_not_called()
        self.assertEqual(buffer.text(), "first\nsecond")

    def test_palette_selection_invokes_the_same_backend_input_route(self):
        class Screen:
            def timeout(self, _value):
                pass

            def getmaxyx(self):
                return (12, 80)

            def erase(self):
                pass

            def addnstr(self, *_args):
                pass

            def refresh(self):
                pass

            def getch(self):
                return 10

        entries = [{"name": "stats", "syntax": "stats",
                    "description": "show token statistics"}]
        with patch.object(tui, "_send") as send:
            tui._palette_overlay(Screen(), 31, tui.InputBuffer(), commands=entries)
        send.assert_called_once_with(31, "stats")

    def test_palette_query_filters_before_invocation(self):
        class Screen:
            def __init__(self):
                self.keys = iter((ord("s"), ord("t"), 10))

            def timeout(self, _value):
                pass

            def getmaxyx(self):
                return (12, 80)

            def erase(self):
                pass

            def addnstr(self, *_args):
                pass

            def refresh(self):
                pass

            def getch(self):
                return next(self.keys)

        commands = [
            {"name": "help", "syntax": "help", "description": "list commands"},
            {"name": "stats", "syntax": "stats", "description": "show statistics"},
        ]
        with patch.object(tui, "_send") as send:
            selected = tui._palette_overlay(Screen(), 31, tui.InputBuffer(),
                                            commands=commands)
        self.assertEqual(selected, "stats")
        send.assert_called_once_with(31, "stats")


class Step7NavigationTests(unittest.TestCase):
    def test_line_page_oldest_and_latest_navigation(self):
        navigation = tui.ActivityNavigator()
        navigation.line_up(20)
        self.assertEqual(navigation.scroll, 1)
        navigation.page_up(7, 20)
        self.assertEqual(navigation.scroll, 8)
        navigation.preserve_view(3, 23)
        self.assertEqual(navigation.scroll, 11)
        navigation.page_down(7)
        navigation.line_down()
        self.assertEqual(navigation.scroll, 3)
        navigation.oldest(23)
        self.assertEqual(navigation.scroll, 23)
        navigation.latest()
        navigation.preserve_view(4, 27)
        self.assertEqual(navigation.scroll, 0)

    def test_successful_output_can_collapse_but_failure_remains_visible(self):
        state = tui.EventState()
        tui.apply_event(state, event("action_output", 1, display="one\ntwo\nthree",
                                     exit_code=0))
        tui.apply_event(state, event("action_output", 2, display="failure detail",
                                     exit_code=1))
        state.collapse_output = True
        collapsed = tui.render_activity(state, 80)
        self.assertIn("Output: 3 lines collapsed (Ctrl+G expands)", collapsed)
        self.assertIn("Output: failure detail", collapsed)
        state.collapse_output = False
        self.assertIn("Output: one", tui.render_activity(state, 80))

    def test_scrolling_keeps_order_and_can_return_to_latest(self):
        state = tui.EventState()
        for sequence in range(1, 7):
            tui.apply_event(state, event("assistant_message", sequence,
                                         display=f"message {sequence}"))

        # The activity projection remains chronological; the live view always
        # ends at the newest item.  _draw owns the viewport offset and can
        # move this ordered list without changing the underlying state.
        latest = tui.render_activity(state, 80)
        self.assertEqual(latest[-1], "Igor: message 6")
        self.assertEqual(latest[0], "Igor: message 1")
        self.assertEqual(tui.render_activity(state, 80)[-1], latest[-1])

    def test_events_do_not_modify_a_prompt_being_edited(self):
        state = tui.EventState()
        buffer = tui.InputBuffer()
        buffer.insert("keep this draft")
        tui.apply_event(state, event("continuation", 1, display="working"))
        tui.apply_event(state, event("warning", 2, display="check output"))
        self.assertEqual(buffer.text(), "keep this draft")
        self.assertEqual([item.event_type for item in state.activity],
                         ["continuation", "warning"])

    def test_page_sized_activity_rendering_preserves_complete_event_blocks(self):
        state = tui.EventState()
        tui.apply_event(state, event("assistant_message", 1,
                                     display="first response"))
        tui.apply_event(state, event("action_output", 2,
                                     display="tool line one\ntool line two"))
        tui.apply_event(state, event("assistant_message", 3,
                                     display="final response"))
        lines = tui.render_activity(state, 80)
        self.assertEqual(lines, [
            "Igor: first response", "",
            "Output: tool line one", "tool line two", "",
            "Igor: final response",
        ])


class Step7InputAndApprovalTests(unittest.TestCase):
    def test_prompt_history_restores_the_unsent_draft(self):
        history = tui.InputHistory()
        history.add("first prompt")
        history.add("second prompt")
        self.assertEqual(history.previous("draft text"), "second prompt")
        self.assertEqual(history.previous("ignored"), "first prompt")
        self.assertEqual(history.next(), "second prompt")
        self.assertEqual(history.next(), "draft text")
        self.assertIsNone(history.next())

    def test_cursor_editing_works_across_multiline_input(self):
        buffer = tui.InputBuffer()
        buffer.insert("alpha\nbeta")
        buffer.move_left()
        buffer.insert("!")
        self.assertEqual(buffer.text(), "alpha\nbet!a")
        self.assertTrue(buffer.move_up())
        buffer.move_end()
        buffer.delete()
        self.assertEqual(buffer.text(), "alphabet!a")
        buffer.move_home()
        buffer.move_right()
        buffer.delete_word_left()
        self.assertEqual(buffer.text(), "lphabet!a")

    def test_multiline_editing_and_clear_are_local_to_the_frontend(self):
        buffer = tui.InputBuffer()
        buffer.insert("line one")
        buffer.insert("\nline two")
        self.assertEqual(buffer.text(), "line one\nline two")
        self.assertEqual(buffer.clear(), "line one\nline two")
        self.assertEqual(buffer.text(), "")

    def test_each_approval_tier_has_a_distinct_safe_prompt(self):
        class Screen:
            def __init__(self):
                self.text = []

            def erase(self):
                pass

            def getmaxyx(self):
                return (12, 100)

            def addnstr(self, *_args):
                if len(_args) > 2:
                    self.text.append(_args[2])

            def hline(self, *_args):
                pass

            def move(self, *_args):
                pass

            def refresh(self):
                pass

        for tier, expected in (("READ", "RUN / SKIP / EXPLAIN / STOP"),
                               ("CHANGE", "YES / NO / EXPLAIN / STOP"),
                               ("DESTROY", "type YES exactly")):
            screen = Screen()
            state = tui.EventState(pending_action={"classification": tier})
            with patch.object(tui.curses, "ACS_HLINE", "-", create=True):
                tui._draw(screen, state, tui.InputBuffer(), 0)
            self.assertTrue(any(expected in text for text in screen.text), tier)


if __name__ == "__main__":
    unittest.main()
