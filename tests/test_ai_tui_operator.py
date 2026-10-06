"""Focused coverage for the contract-driven ':' operator explorer."""

import os
import sys
import unittest
from unittest.mock import patch


sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "core", "ai"))
import tui


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


def ready_event(sequence):
    return {"event_type": "model_status", "sequence": sequence, "status": "input_ready"}


def candidate_event(sequence, capability_id="system.service.status", input_name="unit"):
    return {
        "event_type": "operator_candidates",
        "sequence": sequence,
        "capability_id": capability_id,
        "provider": "system",
        "input_name": input_name,
        "result": {
            "candidate_api_version": 1,
            "selector": {"schema_version": 1, "kind": "resource", "resource_kind": "service"},
            "state": "ready",
            "source": {"kind": "platform", "id": "systemd.services",
                       "freshness": "not_applicable"},
            "candidates": [
                {"value": "cron.service", "label": "cron.service",
                 "detail": "active / running"},
                {"value": "ssh.service", "label": "ssh.service",
                 "detail": "inactive / dead"},
            ],
            "reason": None,
            "resolved_at": "2026-10-06T08:00:00Z",
        },
    }


def capability(path="system.host.memory.refresh", required=(), provider_required=False,
               selector=False):
    inputs = {"required": list(required), "properties": {}}
    if selector and required:
        name = required[0]
        inputs["properties"][name] = {"type": "string", "validator": "systemd_unit"}
        inputs["selectors"] = {
            name: {"schema_version": 1, "kind": "resource", "resource_kind": "service"}
        }
    return {
        "path": path,
        "kind": "capability",
        "owner": "system",
        "target_id": path,
        "provider": "system",
        "provider_required": provider_required,
        "availability": "active",
        "unavailable_reason": None,
        "description": "Refresh memory",
        "inputs": inputs,
    }


class OperatorExplorerTests(unittest.TestCase):
    def test_operator_candidate_event_is_metadata_not_activity(self):
        state = tui.EventState()
        event = candidate_event(1)
        self.assertTrue(tui.apply_event(state, event))
        self.assertEqual(state.operator_candidates["input_name"], "unit")
        self.assertEqual(state.activity, [])

    def test_service_selector_chooses_candidate_and_invokes_canonical_backend(self):
        entry = capability(
            path="system.service.status",
            required=("unit",),
            selector=True,
        )
        state = tui.EventState()
        state.backend_ready = True
        reader = Reader([])
        sent = []

        def send(master, text):
            sent.append((master, text))
            if text.startswith("candidates "):
                reader.events.extend([candidate_event(1), ready_event(2)])

        with patch.object(tui, "_send", side_effect=send), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            outcome, command = tui._operator_candidate_overlay(
                Screen([-1, -1, 10]), 17, reader, state, tui.InputBuffer(),
                entry, "unit",
            )

        self.assertEqual(outcome, "invoke")
        self.assertEqual(
            command,
            'invoke system.service.status {"unit":"cron.service"}',
        )
        self.assertEqual(
            sent,
            [
                (17, "candidates system.service.status unit"),
                (17, 'invoke system.service.status {"unit":"cron.service"}'),
            ],
        )

    def test_service_selector_tab_preserves_manual_input_path(self):
        entry = capability(
            path="system.service.status",
            required=("unit",),
            selector=True,
        )
        state = tui.EventState()
        state.backend_ready = True
        buffer = tui.InputBuffer()
        sent = []
        with patch.object(tui, "_send", side_effect=lambda master, text:
                          sent.append((master, text))):
            outcome, command = tui._operator_candidate_overlay(
                Screen([9]), 17, Reader([]), state, buffer, entry, "unit"
            )
        self.assertEqual(outcome, "draft")
        self.assertIsNone(command)
        self.assertEqual(buffer.text(), "invoke system.service.status ")
        self.assertEqual(sent, [(17, "candidates system.service.status unit")])

    def test_selector_capability_uses_candidate_chooser_before_raw_draft(self):
        entry = capability(
            path="system.service.status",
            required=("unit",),
            selector=True,
        )
        keys = [ord(c) for c in "system"] + [ord(".")] + \
               [ord(c) for c in "service"] + [ord(".")] + \
               [ord(c) for c in "status"] + [10]
        state = tui.EventState()
        state.backend_ready = True
        self.assertTrue(tui.apply_event(state, snapshot_event(1, [entry])))
        buffer = tui.InputBuffer()
        with patch.object(tui, "_operator_candidate_overlay",
                          return_value=("draft", None)) as chooser, \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._operator_overlay(Screen(keys), 17, Reader([]), state, buffer)
        chooser.assert_called_once()
        self.assertEqual(buffer.text(), "")

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
        state.backend_ready = True
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
        state.backend_ready = True
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

    def test_failed_refresh_keeps_cache_and_allows_retry(self):
        state = tui.EventState()
        self.assertTrue(tui.apply_event(state, snapshot_event(1, [capability()])))
        state.backend_ready = True
        reader = Reader([])
        sent = []

        def send(master, text):
            sent.append((master, text))
            if text != "surface snapshot":
                return
            if len(sent) == 1:
                reader.events.extend([
                    {
                        "event_type": "warning",
                        "sequence": 2,
                        "display": "Operator surface projection failed. Press Ctrl+R to retry.",
                    },
                    ready_event(3),
                ])
            else:
                reader.events.extend([
                    snapshot_event(4, [capability("system.host.summary")]),
                    ready_event(5),
                ])

        with patch.object(tui, "_send", side_effect=send), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._operator_overlay(
                Screen([18, -1, 18, -1, 27]), 17, reader, state, tui.InputBuffer())

        self.assertEqual(sent, [(17, "surface snapshot"), (17, "surface snapshot")])
        self.assertEqual(state.sequence, 5)
        self.assertEqual(
            [row["path"] for row in state.operator_snapshot["entries"]],
            ["system.host.summary"],
        )

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
        self.assertTrue(tui.apply_event(state, snapshot_event(1, [entry])))
        with patch.object(tui, "_send") as send, \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            tui._operator_overlay(Screen(keys), 17, Reader([]), state, buffer)
        self.assertEqual(buffer.text(), "invoke system.host.memory.refresh ")
        send.assert_not_called()

    def test_dot_navigation_invokes_zero_input_capability_through_backend(self):
        entry = capability()
        keys = [ord(c) for c in "system"] + [ord(".")] + \
               [ord(c) for c in "host"] + [ord(".")] + \
               [ord(c) for c in "memory"] + [ord(".")] + \
               [ord(c) for c in "refresh"] + [10]
        state = tui.EventState()
        self.assertTrue(tui.apply_event(state, snapshot_event(1, [entry])))
        state.backend_ready = True
        sent = []
        with patch.object(tui, "_send", side_effect=lambda master, text:
                          sent.append((master, text))), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            selected = tui._operator_overlay(
                Screen(keys), 17, Reader([]), state, tui.InputBuffer())
        self.assertEqual(selected, "invoke system.host.memory.refresh")
        self.assertEqual(sent, [(17, "invoke system.host.memory.refresh")])
        self.assertFalse(state.backend_ready)

    def test_busy_backend_does_not_queue_operator_invocation(self):
        entry = capability()
        keys = [ord(c) for c in "system"] + [ord(".")] + \
               [ord(c) for c in "host"] + [ord(".")] + \
               [ord(c) for c in "memory"] + [ord(".")] + \
               [ord(c) for c in "refresh"] + [10, 27]
        state = tui.EventState()
        self.assertTrue(tui.apply_event(state, snapshot_event(1, [entry])))
        screen = Screen(keys)
        sent = []
        with patch.object(tui, "_send", side_effect=lambda master, text:
                          sent.append((master, text))), \
                patch.object(tui.os, "read", side_effect=BlockingIOError):
            selected = tui._operator_overlay(
                screen, 17, Reader([]), state, tui.InputBuffer())
        self.assertIsNone(selected)
        self.assertEqual(sent, [])
        self.assertTrue(any("Backend busy" in str(args[2])
                            for args in screen.drawn if len(args) > 2))

    def test_operator_selection_is_not_rendered_as_conversation(self):
        state = tui.EventState()
        state.add_operator_input("invoke system.service.list")
        self.assertEqual(tui.render_activity(state, 100),
                         ["Operator: system.service.list"])


if __name__ == "__main__":
    unittest.main()
