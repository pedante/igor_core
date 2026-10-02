#!/usr/bin/env python3
"""Backend contract tests for the operator surface bridge."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class OperatorBackendTests(unittest.TestCase):
    def _run(self, body, event_stream=""):
        with tempfile.TemporaryDirectory() as runtime:
            env = {**os.environ, "IGOR_DIR": str(ROOT), "IGOR_RUNTIME_DIR": runtime}
            if event_stream:
                env["IGOR_AI_EVENT_STREAM"] = event_stream
            return subprocess.run(["bash", "-c", body], env=env, text=True,
                                  capture_output=True, timeout=20)

    def test_registry_snapshots_decode_nul_framing(self):
        script = r'''
source "$IGOR_DIR/core/lib/module_loader.sh"
_IGOR_MODULE_CONFIG_LOADED=1
_IGOR_MODULE_DIRS[system]="$IGOR_DIR/modules/system"
_IGOR_MODULE_API[system]=2
_IGOR_MODULE_STATE[system]=enabled
_IGOR_MODULE_STATUS[system]=active
_IGOR_LOADED_MODULES[system]=1
_IGOR_CONTRIBUTIONS["observer:host.memory"]='{"kind":"observer","id":"host.memory"}'
_IGOR_CONTRIBUTION_OWNER["observer:host.memory"]=system
_IGOR_CONTRIBUTION_SOURCE["observer:host.memory"]=contracts/host.json
_IGOR_CONTRIBUTION_STATE["observer:host.memory"]=active
igor_module_records
igor_contribution_records
'''
        result = self._run(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        self.assertEqual(lines[0][0]["name"], "system")
        self.assertEqual(lines[0][0]["module_api"], 2)
        self.assertEqual(lines[1][0]["id"], "host.memory")
        self.assertEqual(lines[1][0]["kind"], "observer")
        self.assertEqual(lines[1][0]["owner"], "system")

    def test_snapshot_availability_keeps_dynamic_requirement_failure(self):
        script = r'''
source "$IGOR_DIR/core/lib/module_loader.sh"
_IGOR_MODULE_CONFIG_LOADED=1
_IGOR_MODULE_DIRS[docker]="$IGOR_DIR/modules/docker"
_IGOR_MODULE_API[docker]=2
_IGOR_MODULE_STATE[docker]=enabled
_IGOR_MODULE_STATUS[docker]=active
_IGOR_LOADED_MODULES[docker]=1
_IGOR_CONTRIBUTIONS["capability:docker.test"]='{"kind":"capability","id":"docker.test","description":"test","inputs":{"properties":{},"required":[],"additionalProperties":false},"safety":{"tier":"READ"},"privilege":"none","preconditions":[],"verification":{"kind":"none","required":false},"recovery":{"class":"not_applicable"},"affects":[],"requires":{"bins":["igor-test-binary-that-does-not-exist"]}}'
_IGOR_CONTRIBUTION_OWNER["capability:docker.test"]=docker
_IGOR_CONTRIBUTION_SOURCE["capability:docker.test"]=contracts/docker.json
_IGOR_CONTRIBUTION_STATE["capability:docker.test"]=active
igor_contribution_records
igor_capability_list
'''
        result = self._run(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        for rows in lines:
            row = next(item for item in rows if item["id"] == "docker.test")
            self.assertEqual(row["availability"], "unavailable")
            self.assertEqual(
                row["unavailable_reason"],
                "required binary igor-test-binary-that-does-not-exist is missing",
            )

    def test_operator_snapshot_projects_existing_registries(self):
        with tempfile.TemporaryDirectory() as runtime:
            stream = Path(runtime) / "events.jsonl"
            script = r'''
source "$IGOR_DIR/core/ai/core.sh"
igor_module_records() {
  printf '%s' '[{"name":"system","display_name":"System","status":"active","enabled":true,"module_api":2}]'
}
igor_contribution_records() {
  printf '%s' '[{"id":"host.memory","kind":"observer","owner":"system","availability":"active","unavailable_reason":null,"descriptor":{"kind":"observer","id":"host.memory"}}]'
}
igor_capability_list() {
  printf '%s' '[{"id":"system.host.memory.refresh","owner":"system","provider":"system","availability":"active","unavailable_reason":null,"descriptor":{"description":"Refresh memory","inputs":{"properties":{},"required":[],"additionalProperties":false},"safety":{"tier":"READ"},"privilege":"none","verification":{"kind":"none","required":false},"recovery":{"class":"not_applicable"}}}]'
}
igor_configuration_declarations() { printf '%s' '[]'; }
_ai_emit_operator_snapshot
'''
            result = self._run(script, str(stream))
            self.assertEqual(result.returncode, 0, result.stderr)
            events = [json.loads(line) for line in stream.read_text().splitlines()]
        self.assertEqual(events[-1]["event_type"], "operator_snapshot")
        self.assertEqual(events[-1]["surface"]["state"], "ready")
        self.assertEqual(events[-1]["surface"]["sources"]["capabilities"]["status"], "ok")
        entries = events[-1]["surface"]["entries"]
        self.assertTrue(any(row["path"] == "system.host.memory.refresh"
                            and row["kind"] == "capability" for row in entries))
        self.assertTrue(any(row["path"] == "system.host.memory"
                            and row["kind"] == "observer" for row in entries))

    def test_malformed_registry_source_emits_visible_error_snapshot(self):
        with tempfile.TemporaryDirectory() as runtime:
            stream = Path(runtime) / "events.jsonl"
            script = r'''
source "$IGOR_DIR/core/ai/core.sh"
igor_module_records() { printf '%s' '[]'; }
igor_contribution_records() { printf '%s' '[]'; }
igor_capability_list() { printf '%s' 'not-json'; }
igor_configuration_declarations() { printf '%s' '[]'; }
_ai_emit_operator_snapshot
'''
            result = self._run(script, str(stream))
            self.assertEqual(result.returncode, 0, result.stderr)
            events = [json.loads(line) for line in stream.read_text().splitlines()]
        surface = events[-1]["surface"]
        self.assertEqual(events[-1]["event_type"], "operator_snapshot")
        self.assertEqual(surface["state"], "error")
        self.assertEqual(surface["entry_count"], 0)
        self.assertEqual(surface["sources"]["capabilities"],
                         {"status": "error", "count": 0})

    def test_operator_invoke_only_adapts_into_existing_dispatcher(self):
        script = r'''
source "$IGOR_DIR/core/ai/core.sh"
captured=
ai_execute_tool() { captured="$1"; printf '%s\n' "$1"; }
_ai_operator_invoke 'system.host.memory.refresh@system {"force":false}'
'''
        result = self._run(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout.strip().splitlines()[-1])
        self.assertEqual(payload, {
            "tool": "run_capability",
            "id": "system.host.memory.refresh",
            "provider": "system",
            "inputs": {"force": False},
        })

    def test_operator_invoke_rejects_bad_json_before_dispatch(self):
        script = r'''
source "$IGOR_DIR/core/ai/core.sh"
ai_execute_tool() { exit 9; }
_ai_operator_invoke 'system.host.memory.refresh not-json'
'''
        result = self._run(script)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
