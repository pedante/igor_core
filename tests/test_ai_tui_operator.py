#!/usr/bin/env python3
"""Focused coverage for the contract-driven ':' operator explorer."""

import os
import sys
import unittest
from unittest.mock import patch


sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "core", "ai"))
import tui  # noqa: E402


class Screen:
    def __init__(self, keys=()):
        self.keys = list(keys)
        self.drawn = []
        self.timeouts = []

    def timeout(self, value):
        self.timeouts.append(value)

    def getmaxyx(self):
        return (18, 110)

    def erase(self):
        self.drawn.clear()

    def addnstr(self, *args):
        self.drawn.append(args)

    def refresh(self):
        pass

    def getch(self):
        return self.keys.pop(0) if self.keys else 27


class Reader:
    def __init__(self, events):
        self.events = list(events)

    def read(self):
        return [self.events.pop(0)] if self.events else []


def snapshot_event(sequence, entries, *, state_name=None, sources=None):
    if state_name is None:
        state_name = "empty" if not entries else "ready"
    if sources is None:
        sources = {
            name: {"status": "ok", "count": 0}
            for name in ("modules", "contributions", "capabilities", "configurations")
        }
    return {"event_type": "operator_snapshot", "sequence": sequence,
            "surface": {"surface_version": 1, "digest": "0" * 64,
                        "state": state_name, "entry_count": len(entries),
                        "sources": sources, "entries": entries}}


def capability(path="system.host.memory.refresh", required=(), provider_required=False):
    return {
        "path": path,
        "kind": "capability",
        "owner": "system",
        "target_id": "system.host.memory.refresh",
        "provider": "system",
        "provider_required": provider_required,
        "availability": "active",
        "unavailable_reason": None,
        "description": "Refresh memory",
        "inputs": {"required": list(required), "properties": {}},
    }


class OperatorExplorerTests(unittest.TestCase):
    def test_operator_snapshot_is_metadata_not_activity(self):
        state = tui.EventState()
        event = snapshot_event(1, [capability()])
        self.assertTrue(tui.apply_event(state, event))
        self.assertEqual(state.operator_snapshot["entries"][0]["kind"], "capability")
        self.assertEqual(state.activity, [])

    def test_empty_snapshot_has_actionable_message(self):
        event = snapshot_event(1, [])
        summary, notice = tui._operator_surface_summary(event["surface"])
        self.assertIn("0 entries", summary)
        self.assertIn("No operator contracts registered", notice)
        self.assertIn("Ctrl+R", notice)

    def test_failed_source_is_visible_instead_of_looking_empty(self):
        sources = {
            "modules": {"status": "ok", "count": 1},
            "contributions": {"status": "ok", "count": 0},
            "capabilities": {"status": "error", "count": 0},
            "configurations": {"status": "ok", "count": 1},
        }
        event = snapshot_event(1, [], state_name="error", sources=sources)
        summary, notice = tui._operator_surface_summary(event["surface"])
        self.assertIn("modules 1", summary)
        self.assertIn("Projection failed for: capabilities", notice)

    def test_cached_snapshot_opens_without_backend_request(self):
        state = tui.EventState()
        self.assertTrue(tui.apply_event(state, snapshot_event(1, [capability()])))
        sent = []
        with patch.object(tui, "_send", side_effect=lambda master, text:
                          sent.append((master, text))), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._operator_overlay(
                Screen([27]), 17, Reader([]), state, tui.InputBuffer())
        self.assertEqual(sent, [])
        self.assertEqual(state.sequence, 1)
        self.assertIsNotNone(state.operator_snapshot)

    def test_ctrl_r_refreshes_without_discarding_cached_snapshot(self):
        state = tui.EventState()
        self.assertTrue(tui.apply_event(state, snapshot_event(1, [capability()])))
        sent = []
        with patch.object(tui, "_send", side_effect=lambda master, text:
                          sent.append((master, text))), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._operator_overlay(
                Screen([18, 27]), 17,
                Reader([snapshot_event(2, [capability("system.host.summary")])]),
                state, tui.InputBuffer())
        self.assertEqual(sent, [(17, "surface snapshot")])
        self.assertEqual(state.sequence, 2)
        paths = [row["path"] for row in state.operator_snapshot["entries"]]
        self.assertEqual(paths, ["system.host.summary"])

    def test_invoke_command_preserves_provider_only_when_required(self):
        command, needs_input = tui._operator_invoke_command(capability())
        self.assertEqual(command, "invoke system.host.memory.refresh")
        self.assertFalse(needs_input)
        command, _ = tui._operator_invoke_command(capability(provider_required=True))
        self.assertEqual(command, "invoke system.host.memory.refresh@system")

    def test_required_inputs_prepare_a_draft_instead_of_guessing(self):
        entry = capability(required=("unit",))
        keys = [ord(c) for c in "system"] + [ord(".")] + \
               [ord(c) for c in "host"] + [ord(".")] + \
               [ord(c) for c in "memory"] + [ord(".")] + \
               [ord(c) for c in "refresh"] + [10]
        buffer = tui.InputBuffer()
        state = tui.EventState()
        with patch.object(tui, "_send") as send, \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._operator_overlay(Screen(keys), 17, Reader([snapshot_event(1, [entry])]),
                                  state, buffer)
        self.assertEqual(buffer.text(), "invoke system.host.memory.refresh ")
        self.assertEqual(send.call_args_list[0], unittest.mock.call(17, "surface snapshot"))
        self.assertEqual(len(send.call_args_list), 1)

    def test_dot_navigation_invokes_zero_input_capability_through_backend(self):
        entry = capability()
        keys = [ord(c) for c in "system"] + [ord(".")] + \
               [ord(c) for c in "host"] + [ord(".")] + \
               [ord(c) for c in "memory"] + [ord(".")] + \
               [ord(c) for c in "refresh"] + [10]
        state = tui.EventState()
        sent = []
        with patch.object(tui, "_send", side_effect=lambda master, text:
                          sent.append((master, text))), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            selected = tui._operator_overlay(
                Screen(keys), 17, Reader([snapshot_event(1, [entry])]),
                state, tui.InputBuffer())
        self.assertEqual(selected, "invoke system.host.memory.refresh")
        self.assertEqual(sent, [(17, "surface snapshot"),
                                (17, "invoke system.host.memory.refresh")])


if __name__ == "__main__":
    unittest.main()
