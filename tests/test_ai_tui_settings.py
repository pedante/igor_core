#!/usr/bin/env python3
"""Focused coverage for the interactive TUI settings view."""

import os
import sys
import unittest
from unittest.mock import patch


sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "core", "ai"))
import tui  # noqa: E402


def event(sequence, **fields):
    return {"event_type": "settings_snapshot", "sequence": sequence,
            "settings": fields}


class Screen:
    """Minimal curses screen with deterministic input and draw capture."""

    def __init__(self, keys=()):
        self.keys = list(keys)
        self.drawn = []
        self.all_drawn = []
        self.timeouts = []

    def timeout(self, value):
        self.timeouts.append(value)

    def getmaxyx(self):
        return (20, 100)

    def erase(self):
        self.drawn.clear()

    def addnstr(self, *args):
        self.drawn.append(args)
        self.all_drawn.append(args)

    def refresh(self):
        pass

    def move(self, *_args):
        pass

    def getch(self):
        if not self.keys:
            return 27
        return self.keys.pop(0)


class Reader:
    def __init__(self, events, after_send=None):
        self.events = list(events)
        self.after_send = after_send

    def read(self):
        if self.events:
            return [self.events.pop(0)]
        if self.after_send:
            result = self.after_send()
            if result:
                self.after_send = None
                return result if isinstance(result, list) else [result]
        return []


SNAPSHOT = {
    "provider": "openrouter",
    "model": "deepseek/deepseek-chat-v3-0324",
    "temperature": "0.7",
    "max_tokens": "4096",
    "mode": "assist",
    "verbose": "false",
    "ai_autostart": "false",
    "hybrid_menu": "false",
}


class SettingsViewTests(unittest.TestCase):
    def test_palette_settings_opens_view_without_sending_command(self):
        screen = Screen([10])
        commands = [{"name": "settings", "syntax": "settings",
                     "description": "show or edit settings"}]
        draft = tui.InputBuffer()
        draft.insert("unfinished request")
        with patch.object(tui, "_send") as send:
            selected = tui._palette_overlay(
                screen, 17, draft, tui.EventState(), commands)
        self.assertEqual(selected, "settings_view")
        self.assertEqual(draft.text(), "unfinished request")
        send.assert_not_called()

    def test_settings_snapshot_is_projected_without_parallel_state(self):
        state = tui.EventState()
        snapshot = {**SNAPSHOT, "temperature": 0.7, "max_tokens": 4096}
        self.assertTrue(tui.apply_event(state, event(1, **snapshot)))
        self.assertEqual(state.settings_snapshot, snapshot)
        self.assertEqual((state.mode, state.provider, state.model),
                         ("assist", "openrouter", SNAPSHOT["model"]))
        self.assertEqual(tui.settings_value(snapshot, "mode"), "Assist")
        self.assertEqual(tui.settings_value(snapshot, "verbose"), "Off")

    def test_snapshot_metadata_does_not_hide_typed_command_output(self):
        state = tui.EventState()
        state.begin_terminal_capture()
        self.assertTrue(tui.apply_event(state, event(1, **SNAPSHOT)))
        state.add_terminal_output("Settings updated")
        self.assertIn("Settings updated", tui.render_activity(state, 80))

    def test_navigation_moves_selection_and_cancel_returns(self):
        screen = Screen([tui.curses.KEY_DOWN, tui.curses.KEY_UP, 27])
        state = tui.EventState()
        reader = Reader([event(1, **SNAPSHOT)])
        with patch.object(tui, "_send"), patch.object(tui.os, "read",
                                                       side_effect=BlockingIOError):
            tui._settings_overlay(screen, 17, reader, state)
        # The rendered settings rows include both the selected Provider and
        # the selected Model after moving down, proving arrow navigation ran.
        selected = [str(call[2]) for call in screen.all_drawn
                    if len(call) > 2 and str(call[2]).startswith(">")]
        self.assertTrue(any("Provider" in line for line in selected))
        self.assertTrue(any("Model" in line for line in selected))

    def test_boolean_toggle_uses_existing_settings_command_route(self):
        # Verbose is row 5. The second snapshot is what the backend would
        # emit after accepting the command and persisting the new value.
        keys = [tui.curses.KEY_DOWN] * 5 + [10, 27]
        changed = {**SNAPSHOT, "verbose": "true"}
        state = tui.EventState()
        sent = []
        reader = Reader([event(1, **SNAPSHOT)],
                        after_send=lambda: event(2, **changed) if
                        (17, "verbose on") in sent else None)
        screen = Screen(keys)
        def capture_send(master, text):
            sent.append((master, text))
        with patch.object(tui, "_send", side_effect=capture_send), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._settings_overlay(screen, 17, reader, state)
        self.assertIn((17, "verbose on"), sent)
        self.assertEqual(sent.count((17, "settings snapshot")), 2)
        self.assertEqual(state.settings_snapshot["verbose"], "true")
        self.assertTrue(any(len(call) > 2 and call[2] == "Saved"
                            for call in screen.all_drawn))

    def test_enum_selection_returns_canonical_value(self):
        screen = Screen([tui.curses.KEY_DOWN, 10])
        self.assertEqual(tui._settings_choice(
            screen, "Mode", ("guide", "assist", "executive"), "guide"), "assist")
        self.assertEqual(tui.settings_change_command("mode", "executive"),
                         "mode executive")

    def test_mode_enum_selection_sends_canonical_handler_command(self):
        keys = [tui.curses.KEY_DOWN] * 4 + [10, tui.curses.KEY_DOWN, 10, 27]
        changed = {**SNAPSHOT, "mode": "executive"}
        sent = []
        reader = Reader([event(1, **SNAPSHOT)],
                        after_send=lambda: event(2, **changed) if
                        (17, "mode executive") in sent else None)
        with patch.object(tui, "_send", side_effect=lambda master, text:
                          sent.append((master, text))), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._settings_overlay(Screen(keys), 17, reader, tui.EventState())
        self.assertIn((17, "mode executive"), sent)

    def test_provider_enum_selection_uses_settings_backend(self):
        keys = [10, tui.curses.KEY_DOWN, 10, 27]
        changed = {**SNAPSHOT, "provider": "anthropic"}
        sent = []
        reader = Reader([event(1, **SNAPSHOT)],
                        after_send=lambda: event(2, **changed) if
                        (17, "settings provider anthropic") in sent else None)
        with patch.object(tui, "_send", side_effect=lambda master, text:
                          sent.append((master, text))), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._settings_overlay(Screen(keys), 17, reader, tui.EventState())
        self.assertIn((17, "settings provider anthropic"), sent)

    def test_numeric_and_text_editing_use_single_line_input(self):
        numeric = Screen([tui.curses.KEY_END, ord("2"), 10])
        self.assertEqual(tui._settings_edit(numeric, "Temperature", "0.7"), "0.72")
        text = Screen([tui.curses.KEY_END, ord("x"), 10])
        self.assertEqual(tui._settings_edit(text, "Model", "model"), "modelx")
        self.assertEqual(tui.settings_change_command("temperature", "0.72"),
                         "settings temperature 0.72")
        self.assertEqual(tui.settings_change_command("model", "modelx"),
                         "settings model modelx")

    def test_temperature_editor_sends_value_through_backend(self):
        keys = [tui.curses.KEY_DOWN] * 2 + [10, 21, ord("1"), ord("."),
                                            ord("2"), 10, 27]
        changed = {**SNAPSHOT, "temperature": "1.2"}
        sent = []
        reader = Reader([event(1, **SNAPSHOT)],
                        after_send=lambda: event(2, **changed) if
                        (17, "settings temperature 1.2") in sent else None)
        with patch.object(tui, "_send", side_effect=lambda master, text:
                          sent.append((master, text))), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._settings_overlay(Screen(keys), 17, reader, tui.EventState())
        self.assertIn((17, "settings temperature 1.2"), sent)

    def test_backend_warning_is_not_replaced_by_a_saved_notice(self):
        keys = [tui.curses.KEY_DOWN] * 5 + [10, 27]
        sent = []
        warning = {"event_type": "warning", "sequence": 2,
                   "display": "Could not update setting 'verbose'."}
        reader = Reader([event(1, **SNAPSHOT)],
                        after_send=lambda: [warning, event(3, **SNAPSHOT)] if
                        (17, "verbose on") in sent else None)
        screen = Screen(keys)
        with patch.object(tui, "_send", side_effect=lambda master, text:
                          sent.append((master, text))), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._settings_overlay(screen, 17, reader, tui.EventState())
        self.assertTrue(any(len(call) > 2 and
                            call[2] == "Could not update setting 'verbose'."
                            for call in screen.all_drawn))

    def test_edit_cancel_does_not_send_or_change_snapshot(self):
        # Select Model, enter its editor, cancel the edit, then leave Settings.
        screen = Screen([tui.curses.KEY_DOWN, 27, 27])
        state = tui.EventState()
        reader = Reader([event(1, **SNAPSHOT)])
        with patch.object(tui, "_send") as send, \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._settings_overlay(screen, 17, reader, state)
        self.assertEqual(state.settings_snapshot, SNAPSHOT)
        self.assertEqual(send.call_args_list, [unittest.mock.call(17, "settings snapshot")])

    def test_mode_change_goes_through_canonical_mode_handler(self):
        self.assertEqual(tui.settings_change_command("mode", "guide"), "mode guide")
        self.assertEqual(tui.settings_change_command("mode", "executive"),
                         "mode executive")


if __name__ == "__main__":
    unittest.main()
