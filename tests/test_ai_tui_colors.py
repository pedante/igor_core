#!/usr/bin/env python3
"""Focused tests for the semantic, capability-aware TUI colour layer."""

import os
import sys
import unittest
from unittest.mock import patch


sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "core", "ai"))
import tui  # noqa: E402


class SemanticColorTests(unittest.TestCase):
    def test_roles_are_derived_from_structured_event_types(self):
        cases = {
            "user": "user",
            "assistant_message": "assistant",
            "explanation": "assistant",
            "action_proposed": "action",
            "approval_waiting": "action",
            "action_output": "output",
            "action_result": "output",
            "warning": "warning",
            "error": "error",
        }
        for event_type, expected in cases.items():
            with self.subTest(event_type=event_type):
                self.assertEqual(tui.activity_color_role(tui.Activity(event_type, "x")), expected)

    def test_no_color_terminal_gets_readable_attribute_fallback(self):
        with patch.object(tui.curses, "has_colors", return_value=False):
            theme = tui.color_theme(object())
        self.assertEqual(set(theme), set(tui.COLOR_ROLES))
        self.assertEqual(theme["user"], tui.curses.A_BOLD)
        self.assertEqual(theme["assistant"], tui.curses.A_NORMAL)
        self.assertEqual(theme["error"], tui.curses.A_BOLD)

    def test_color_terminal_uses_small_stable_palette(self):
        initialized = []
        with patch.object(tui.curses, "has_colors", return_value=True), \
                patch.object(tui.curses, "start_color"), \
                patch.object(tui.curses, "init_pair", side_effect=lambda n, fg, bg: initialized.append((n, fg, bg))), \
                patch.object(tui.curses, "color_pair", side_effect=lambda n: n << 8):
            theme = tui.color_theme(object())
        self.assertEqual(len(initialized), len(tui.COLOR_ROLES))
        self.assertEqual(set(theme), set(tui.COLOR_ROLES))
        self.assertNotEqual(theme["user"], theme["assistant"])
        self.assertNotEqual(theme["error"], theme["output"])

    def test_rows_keep_text_and_order_while_exposing_roles(self):
        state = tui.EventState()
        state.activity = [
            tui.Activity("user", "check status"),
            tui.Activity("assistant_message", "I will inspect it"),
            tui.Activity("action_proposed", "uname", classification="READ"),
            tui.Activity("action_output", "Linux"),
            tui.Activity("warning", "slow response"),
            tui.Activity("error", "provider failed"),
        ]
        rows = tui._activity_rows(state, 80)
        self.assertEqual([role for text, role in rows if text],
                         ["user", "assistant", "action", "output", "warning", "error"])
        self.assertIn("You: check status", [text for text, _role in rows])
        self.assertIn("Error: provider failed", [text for text, _role in rows])

    def test_draw_passes_semantic_attributes_to_activity_rows(self):
        class Screen:
            def __init__(self):
                self.calls = []

            def erase(self):
                pass

            def getmaxyx(self):
                return (12, 80)

            def addnstr(self, *args):
                self.calls.append(args)

            def hline(self, *args):
                pass

            def move(self, *args):
                pass

            def refresh(self):
                pass

        state = tui.EventState()
        state.activity = [tui.Activity("user", "hello"),
                          tui.Activity("assistant_message", "answer")]
        screen = Screen()
        theme = {role: index + 100 for index, role in enumerate(tui.COLOR_ROLES)}
        with patch.object(tui, "color_theme", return_value=theme), \
                patch.object(tui.curses, "ACS_HLINE", "-", create=True):
            tui._draw(screen, state, tui.InputBuffer(), 0)
        activity_calls = [call for call in screen.calls if len(call) == 5 and call[2] in {"You: hello", "Igor: answer"}]
        self.assertEqual([call[4] for call in activity_calls], [theme["user"], theme["assistant"]])


if __name__ == "__main__":
    unittest.main()
