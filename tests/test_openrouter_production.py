"""Synthetic production proof; only the final HTTP socket is replaced."""
from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "core/ai"), str(ROOT / "core/lib")]

from operational_history import OperationalHistory
from secret_refs import ManagedOpenRouterSecret

SENTINEL_1 = "sk-or-synthetic-production-first"
SENTINEL_2 = "sk-or-synthetic-production-rotated"
SENTINEL_3 = "sk-or-synthetic-production-third"

# Loaded by *every* Python child before any production import or validation.
SOCKET_FIXTURE = r'''import http.client, json, os, sys
START_ENVIRONMENT = dict(os.environ)
class Response:
    def __init__(self, method, key):
        self.status = int(os.environ.get("FIXTURE_HTTP_STATUS", "200"))
        text = key if os.environ.get("FIXTURE_ECHO") else "synthetic reply"
        if self.status != 200:
            self.data = json.dumps({"error":{"message":text}}).encode()
        elif method == "GET":
            self.data = b'{"data":{"limit":12,"usage":2}}'
        else:
            self.data = ("data: " + json.dumps({"choices":[{"delta":{"content":text},"finish_reason":"stop"}]}) + "\n\ndata: [DONE]\n\n").encode()
    def read(self, amount=-1):
        if amount < 0: amount = len(self.data)
        value, self.data = self.data[:amount], self.data[amount:]
        return value
class Socket:
    def __init__(self, host, **kwargs):
        if host != "openrouter.ai": raise AssertionError("unexpected network host")
        self.host = host
    def request(self, method, path, body=None, headers=None):
        self.method = method
        self.key = (headers or {}).get("Authorization", "").removeprefix("Bearer ")
        with open('/proc/self/environ', 'rb') as source:
            exec_environment = source.read().decode().split('\0')
        record = {"host": self.host, "method": method, "path": path,
                  "body": body.decode() if isinstance(body, bytes) else body,
                  "headers": dict(headers or {}), "argv":sys.argv,
                  "environment":dict(os.environ), "startup_environment":START_ENVIRONMENT,
                  "exec_environment":exec_environment}
        fd = os.open(os.environ["IGOR_SOCKET_CAPTURE"], os.O_WRONLY|os.O_CREAT|os.O_APPEND, 0o600)
        try: os.write(fd, (json.dumps(record)+"\n").encode())
        finally: os.close(fd)
    def getresponse(self):
        if os.environ.get("FIXTURE_CONFIG_RACE"):
            import sqlite3
            with sqlite3.connect(os.environ["IGOR_DATA_DIR"]+"/config/config.db") as db:
                db.execute("UPDATE metadata SET value=CAST(value AS INTEGER)+1 WHERE key='revision'")
        return Response(self.method, self.key)
    def close(self): pass
http.client.HTTPSConnection = Socket
'''


class ProductionFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "igor"
        self.home = Path(self.temp.name) / "home"
        self.home.mkdir(mode=0o700)
        self.root.mkdir(mode=0o700)
        # Isolated installation prevents loading personal configuration/modules.
        shutil.copytree(ROOT / "core", self.root / "core")
        self.data = self.root / "data"
        self.secrets = self.root / "secrets"
        for path in (self.data, self.secrets, self.root / "runtime", self.root / "config/variables", self.root / "modules"):
            path.mkdir(mode=0o700, parents=True, exist_ok=True)
        fixture = self.root / "socket-fixture"
        fixture.mkdir(mode=0o700)
        (fixture / "sitecustomize.py").write_text(SOCKET_FIXTURE)
        self.capture = self.root / "socket-capture.jsonl"
        self.env = {"PATH":os.environ["PATH"], "HOME":str(self.home),
            "PYTHONPATH":str(fixture), "IGOR_SOCKET_CAPTURE":str(self.capture),
            "IGOR_DIR":str(self.root), "IGOR_DATA_DIR":str(self.data),
            "IGOR_RUNTIME_DIR":str(self.root / "runtime"), "IGOR_SECRETS_DIR":str(self.secrets),
            "IGOR_CONFIGURATION_ROOT":str(self.root), "IGOR_CONFIGURATION_DATA_DIR":str(self.data),
            "IGOR_AI_ENABLED":"true", "IGOR_AI_CONTEXT":"minimal", "IGOR_AI_AUDIT":"metadata",
            "IGOR_AI_REQUEST_TYPE":"conversation", "IGOR_AI_ACTIVE_OWNERS":'["core"]',
            "IGOR_AI_ROLE_BINDINGS":"{}", "IGOR_AI_CONTEXT_REQUEST":"{}",
            "IGOR_AI_MODEL_SNAPSHOT":"{}", "IGOR_AI_REQUEST_ID":"request-production",
            "NEXUS_PROVIDER":"openrouter", "NEXUS_MODEL":"openai/fixture-model",
            "NEXUS_MAX_TOKENS":"128", "NEXUS_SYSTEM":"Safe synthetic policy",
            "NEXUS_CONV":'[{"role":"user","content":"Say hello"}]', "NEXUS_TOOLS_JSON":"[]"}
        self.service = ManagedOpenRouterSecret(self.secrets, self.data)

    def tearDown(self):
        self.temp.cleanup()

    def shell(self, script, *, private_input="", env=None):
        process = subprocess.Popen(["bash", "-c", script], env=env or self.env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True)
        try:
            # Canonical approval/History and mandatory durable access audits
            # span several processes; a measured setup takes about 26 seconds.
            stdout, stderr = process.communicate(private_input, timeout=60)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            self.fail("isolated fixture timed out: " + stderr)
        return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)

    def records(self):
        return [json.loads(line) for line in self.capture.read_text().splitlines()] if self.capture.exists() else []

    def install(self, value, *, mode="executive"):
        script = r'''
source "$IGOR_DIR/core/lib/module_loader.sh"
source "$IGOR_DIR/core/ai/core.sh"
ai_mode=MODE provider=openrouter model=openai/fixture-model max_tokens=128
ok() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
_ai_change_key openrouter
'''.replace("MODE", mode)
        result = self.shell(script, private_input=value + "\n")
        self.assertNotIn(value, result.stdout + result.stderr)
        return result

    def assert_request(self, key, *, method="POST"):
        row = self.records()[-1]
        self.assertEqual((row["host"], row["method"]), ("openrouter.ai", method))
        self.assertEqual(row["headers"].get("Authorization"), "Bearer " + key)
        for value in (SENTINEL_1, SENTINEL_2, SENTINEL_3):
            self.assertNotIn(value, str(row["body"]))
            self.assertNotIn(value, repr(row["argv"]))
            self.assertNotIn(value, repr(row["environment"]))
            self.assertFalse(value in repr(row["startup_environment"]),
                             "selected credential inherited at HTTP process launch")
            self.assertFalse(value in repr(row["exec_environment"]),
                             "selected credential present in kernel exec environment")
        return json.loads(row["body"]) if row["body"] else None

    def request(self, *, route="nexus", role=None, request_type="conversation", echo=False):
        env = dict(self.env)
        env["IGOR_AI_REQUEST_TYPE"] = request_type
        if echo:
            env["FIXTURE_ECHO"] = "1"
        if role:
            env["IGOR_AI_ROLE_BINDINGS"] = json.dumps({role:{"provider":"openrouter", "model":"openai/fixture-"+role, "tools":role=="reasoner"}})
        if route == "direct":
            result = subprocess.run([sys.executable, str(self.root / "core/ai/ai_engine.py"), "call"], env=env, capture_output=True, text=True, timeout=60, check=False)
        else:
            script = 'source "$IGOR_DIR/core/ai/core.sh"; provider=openrouter; model=openai/fixture-model; max_tokens=128; _nexus_api_call'
            if route == "raw":
                script = script.replace("_nexus_api_call", "_nexus_api_call_raw")
            if route == "hybrid":
                script = r'''source "$IGOR_DIR/core/ai/core.sh"
source "$IGOR_DIR/core/lib/ai_hybrid.sh"
provider=openrouter model=openai/fixture-model max_tokens=128
_IGOR_HYBRID_SYSTEM_PROMPT='safe synthetic system'
_igor_hybrid_ask hello
'''
            result = self.shell(script, env=env)
        self.assertNotIn(SENTINEL_1, result.stdout + result.stderr)
        self.assertNotIn(SENTINEL_2, result.stdout + result.stderr)
        return result



class OpenRouterProductionTests(ProductionFixture):
    def test_inherited_scrub_map_is_private_before_http_process_startup(self):
        self.assertEqual(self.install(SENTINEL_1).returncode, 0)
        self.env["IGOR_AI_SCRUB_MAP"] = json.dumps({
            SENTINEL_1: "[IGOR:API_KEY]", "fixture-host": "[IGOR:HOSTNAME]"})
        # An unintended inherited alias must not bypass the same projection.
        self.env["FIXTURE_STALE_SESSION"] = "cached " + SENTINEL_1
        self.env["NEXUS_SYSTEM"] += " reference " + SENTINEL_1
        self.env["IGOR_AI_EVENT_STREAM"] = str(self.root / "runtime/events.jsonl")
        routes = (("direct", "reasoner", "conversation"),
                  ("direct", "summarizer", "summarize"),
                  ("direct", "context_ranker", "rank_context"),
                  ("nexus", None, "conversation"), ("raw", None, "conversation"),
                  ("hybrid", None, "conversation"))
        for status in ("200", "401"):
            self.env["FIXTURE_HTTP_STATUS"] = status
            for route, role, request_type in routes:
                with self.subTest(status=status, route=route, role=role):
                    result = self.request(route=route, role=role,
                                          request_type=request_type, echo=True)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assert_request(SENTINEL_1)
                    if route == "direct":
                        safe_map = json.loads(self.records()[-1]["startup_environment"]["IGOR_AI_SCRUB_MAP"])
                        self.assertEqual(safe_map, {"fixture-host": "[IGOR:HOSTNAME]"})
                        if status == "200":
                            self.assertIn("[REDACTED]", result.stdout + result.stderr)
                        else:
                            self.assertIn("ERROR: OpenRouter HTTP 401", result.stdout)
                    if status == "401" and route == "direct":
                        self.assertIn("PROVIDER_ERROR: true", result.stdout)
                        projected = self.shell('source "$IGOR_DIR/core/ai/core.sh"; display=$(cat); _ai_frontend_event error "$display" failed',
                                               private_input=result.stdout)
                        self.assertEqual(projected.returncode, 0, projected.stderr)
        # Independently read the real private HTTP error projection. The engine
        # deliberately emits a generic error instead of displaying its body.
        projected = self.shell(r'''python3 -c '
import os, sys
sys.path.insert(0, os.environ["IGOR_DIR"] + "/core/ai")
from privacy import launch_private_transport
from openrouter_transport import request
launch_private_transport(openrouter=True)
connection, response = request("GET", "/api/v1/auth/key", consumer="validation")
try:
    assert response.status == 401
    print(response.read().decode())
finally:
    connection.close()
'
''', env={**self.env, "FIXTURE_ECHO": "1"})
        self.assertEqual(projected.returncode, 0, projected.stderr)
        self.assertIn("[REDACTED]", projected.stdout)
        self.assertNotIn(SENTINEL_1, projected.stdout + projected.stderr)
        self.assert_request(SENTINEL_1, method="GET")
        del self.env["FIXTURE_HTTP_STATUS"]
        # Construct/export the session mapping through the actual shell boundary.
        result = self.shell(r'''source "$IGOR_DIR/core/ai/core.sh"
IFS= read -r cached
SCRUB_FROM=("$cached" fixture-host)
SCRUB_TO=('[IGOR:API_KEY]' '[IGOR:HOSTNAME]')
ai_export_privacy_map || exit 1
python3 "$IGOR_DIR/core/ai/ai_engine.py" call
''', private_input=SENTINEL_1 + "\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_request(SENTINEL_1)
        self.assertEqual(json.loads(self.records()[-1]["environment"]["IGOR_AI_SCRUB_MAP"]),
                         {"fixture-host": "[IGOR:HOSTNAME]"})
        # Provider echo data still uses Secret Service redaction after map removal.
        from test_operational_history import finish_result, prepare, proposal
        with patch.dict(os.environ, self.env, clear=True):
            history = OperationalHistory(self.data)
            source = proposal()
            source["inputs"]["note"] = "provider error " + SENTINEL_1
            row = prepare(history, source)
            history.authority(row["operation_id"], "approved", "authenticated")
            history.running(row["operation_id"])
            terminal = finish_result(row, execution="failed", outcome="failed", verification="failed")
            terminal["verification_evidence"] = [{"message": "provider error " + SENTINEL_1}]
            history.finish(row["operation_id"], terminal)
            stored = history.inspect(row["operation_id"])
            self.assertNotIn(SENTINEL_1, repr(stored))
            self.assertIn("[REDACTED]", repr(stored))
        for directory in (self.data, self.root / "runtime"):
            for path in directory.rglob("*"):
                if path.is_file():
                    self.assertFalse(SENTINEL_1.encode() in path.read_bytes(),
                                     "credential retained in History, context or event data")

    def test_explicit_environment_import_is_private_at_final_validation(self):
        self.env.update(OPENROUTER_API_KEY=SENTINEL_1, OR_API_KEY=SENTINEL_2,
                        NEXUS_API_KEY=SENTINEL_3)
        imported = self.shell('source "$IGOR_DIR/core/lib/module_loader.sh"; source "$IGOR_DIR/core/ai/core.sh"; ai_mode=executive; igor_configuration_cli import-openrouter environment:OPENROUTER_API_KEY')
        self.assertEqual(imported.returncode, 0, imported.stdout + imported.stderr)
        self.assert_request(SENTINEL_1, method="GET")
        queried = self.shell('python3 "$IGOR_DIR/core/ai/openrouter_transport.py" balance')
        self.assertEqual(queried.returncode, 0, queried.stderr)
        self.assert_request(SENTINEL_1, method="GET")
        self.request(route="direct")
        self.assert_request(SENTINEL_1)

    def test_canonical_setup_restart_rotate_session_and_recovery(self):
        result = self.install(SENTINEL_1)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_request(SENTINEL_1, method="GET")
        first = self.service.status()
        self.assertTrue(first["cutover"])
        self.assertRegex(first["reference"], r"^secret:[0-9a-f]{32}$")
        for route in ("nexus", "raw", "hybrid", "direct"):
            with self.subTest(route=route):
                result = self.request(route=route, echo=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assert_request(SENTINEL_1)
        result = self.install(SENTINEL_2)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.request()
        self.assert_request(SENTINEL_2)
        second = self.service.status()
        self.assertEqual(second["reference"], first["reference"])
        self.assertNotEqual(second["generation"], first["generation"])
        self.assertEqual(second["revision"], 2)
        restored = self.shell('source "$IGOR_DIR/core/lib/module_loader.sh"; source "$IGOR_DIR/core/ai/core.sh"; ai_mode=executive; _ai_openrouter_recover_previous')
        self.assertEqual(restored.returncode, 0, restored.stdout + restored.stderr)
        self.request(route="direct")
        self.assert_request(SENTINEL_1)
        self.assertEqual(self.service.status()["generation"], first["generation"])
        self.assertEqual(self.service.status()["revision"], 3)
        history = OperationalHistory(self.data).recent()
        self.assertEqual(len(history), 3)
        self.assertTrue(all(row["outcome"] == "success" for row in history))
        self.assertNotIn(SENTINEL_1, repr(history))
        self.assertNotIn(SENTINEL_2, repr(history))

    def test_all_roles_and_auxiliary_consumers(self):
        self.assertEqual(self.install(SENTINEL_1).returncode, 0)
        for request_type, role in (("conversation", "reasoner"), ("summarize", "summarizer"), ("rank_context", "context_ranker")):
            with self.subTest(role=role):
                result = self.request(role=role, request_type=request_type, route="direct")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.assert_request(SENTINEL_1)["model"], "openai/fixture-" + role)
        for action in ("validate", "balance"):
            result = self.shell('python3 "$IGOR_DIR/core/ai/openrouter_transport.py" ' + action)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assert_request(SENTINEL_1, method="GET")
        self.assertIn("$10.00 remaining", result.stdout)

    def test_old_sources_policy_and_failed_validation(self):
        self.assertEqual(self.install(SENTINEL_1).returncode, 0)
        for path in (self.secrets / "openrouter.key", self.home / ".nexus_or_key"):
            path.write_text("synthetic-old-source-poison")
            path.chmod(0o600)
        self.env.update(OPENROUTER_API_KEY="synthetic-old-environment-poison", NEXUS_API_KEY="synthetic-old-cache-poison")
        for route in ("nexus", "direct", "hybrid"):
            self.request(route=route)
            self.assert_request(SENTINEL_1)
        mixed = self.secrets / "mixed.env"
        mixed.write_text("OPENROUTER_API_KEY=" + SENTINEL_1 + "\nUNRELATED_FIXTURE=preserved\n")
        mixed.chmod(0o600)
        marker = self.root / "must-not-exist"
        unsafe = self.secrets / "unsafe.env"
        unsafe.write_text('OPENROUTER_API_KEY="$(touch ' + str(marker) + ')"\n')
        unsafe.chmod(0o600)
        loaded = self.shell('source "$IGOR_DIR/core/lib/config_loader.sh"; igor_load_config; [ "$UNRELATED_FIXTURE" = preserved ] && [ -z "${OPENROUTER_API_KEY:-}" ]')
        self.assertEqual(loaded.returncode, 0, loaded.stdout + loaded.stderr)
        self.assertNotIn(SENTINEL_1, loaded.stdout + loaded.stderr)
        self.assertFalse(marker.exists())
        self.env["FIXTURE_HTTP_STATUS"] = "401"
        self.request(route="direct", echo=True)
        self.assert_request(SENTINEL_1)
        self.assertNotEqual(self.install(SENTINEL_2).returncode, 0)
        self.assertEqual(self.service.status()["revision"], 1)
        self.assertFalse(self.service.status()["pending"])
        del self.env["FIXTURE_HTTP_STATUS"]
        self.request()
        self.assert_request(SENTINEL_1)
        before = len(self.records())
        self.assertNotEqual(self.install(SENTINEL_2, mode="guide").returncode, 0)
        self.assertEqual(len(self.records()), before)
        self.assertEqual(self.service.status()["revision"], 1)

    def test_corrupt_catalog_fails_closed_and_explicit_reimport_retains_damage(self):
        self.assertEqual(self.install(SENTINEL_1).returncode, 0)
        reference = self.service.status()["reference"]
        damaged = b"synthetic corrupt catalog"
        self.service.db_path.write_bytes(damaged)
        self.env["OPENROUTER_API_KEY"] = "synthetic-old-environment-poison"
        before = len(self.records())
        result = self.request(route="direct")
        self.assertEqual(len(self.records()), before)
        self.assertNotIn("synthetic-old-environment-poison", result.stdout + result.stderr)
        self.assertEqual(self.service.db_path.read_bytes(), damaged)
        # Explicit recovery still requires canonical approval; Guide cannot
        # validate, repair or discard the damaged registration implicitly.
        denied = self.shell('source "$IGOR_DIR/core/lib/module_loader.sh"; source "$IGOR_DIR/core/ai/core.sh"; ai_mode=guide; _ai_openrouter_import_private_stdin reimport', private_input=SENTINEL_2)
        self.assertNotEqual(denied.returncode, 0)
        self.assertEqual(len(self.records()), before)
        self.assertEqual(self.service.db_path.read_bytes(), damaged)
        recovered = self.shell('source "$IGOR_DIR/core/lib/module_loader.sh"; source "$IGOR_DIR/core/ai/core.sh"; ai_mode=executive; _ai_openrouter_import_private_stdin reimport', private_input=SENTINEL_2)
        self.assertEqual(recovered.returncode, 0, recovered.stdout + recovered.stderr)
        self.assertEqual(self.service.status()["reference"], reference)
        retained = list((self.data / "secrets/damaged").glob("*/catalog.db"))
        self.assertTrue(retained)
        self.assertTrue(any(path.read_bytes() == damaged for path in retained))
        self.request(route="direct")
        self.assert_request(SENTINEL_2)

    def test_protected_import_backup_restore_and_missing_material(self):
        original = self.secrets / "openrouter.key"
        original.write_text(SENTINEL_1)
        original.chmod(0o600)
        imported = self.shell('source "$IGOR_DIR/core/lib/module_loader.sh"; source "$IGOR_DIR/core/ai/core.sh"; ai_mode=executive; igor_configuration_cli import-openrouter file:secrets/openrouter.key')
        self.assertEqual(imported.returncode, 0, imported.stdout + imported.stderr)
        self.assert_request(SENTINEL_1, method="GET")
        self.assertEqual(original.read_text(), SENTINEL_1)
        self.request()
        self.assert_request(SENTINEL_1)
        variable = self.root / "config/variables/provider.env"
        variable.write_text("OPENROUTER_API_KEY=" + SENTINEL_1 + "\n")
        variable.chmod(0o600)
        unrelated = self.root / "config/variables/other.env"
        unrelated.write_text("FEATURE=enabled\n")
        mockbin = self.root / "mock-bin"
        mockbin.mkdir()
        for name in ("sudo", "docker", "ip", "ss", "systemctl", "crontab", "iptables-save", "ufw"):
            path = mockbin / name
            path.write_text("#!/bin/sh\nexit 1\n")
            path.chmod(0o700)
        self.env["PATH"] = str(mockbin) + ":" + self.env["PATH"]
        backup = self.shell(r'''source "$IGOR_DIR/core/recovery/config_backup.sh"
step() { :; }; ok() { :; }; info() { :; }; warn() { :; }; fail() { :; }
cp() { local arg; for arg in "$@"; do case "$arg" in /etc/*) return 1;; esac; done; command cp "$@"; }
config_backup_take managed-proof
''')
        self.assertEqual(backup.returncode, 0, backup.stdout + backup.stderr)
        archive = Path(backup.stdout.strip())
        with tarfile.open(archive) as snapshot:
            names = snapshot.getnames()
            self.assertIn("igor-state/openrouter-credential-omitted.txt", names)
            self.assertIn("igor-state/variables/other.env", names)
            self.assertFalse(any("openrouter.key" in name or ".managed" in name or "provider.env" in name for name in names))
            for member in snapshot:
                if member.isfile():
                    self.assertNotIn(SENTINEL_1.encode(), snapshot.extractfile(member).read())
        old_tree = self.root / "old-archive/igor-state/secrets-plain"
        old_tree.mkdir(parents=True)
        (old_tree / "openrouter.key").write_text(SENTINEL_2)
        (old_tree.parent.parent / "manifest.txt").write_text("old synthetic archive")
        old_archive = self.root / "old.tar.gz"
        with tarfile.open(old_archive, "w:gz") as snapshot:
            snapshot.add(old_tree.parent.parent, arcname=".")
        restored = self.shell(r'''source "$IGOR_DIR/core/recovery/config_backup.sh"
step() { :; }; ok() { :; }; info() { :; }; warn() { :; }; fail() { :; }; confirm() { return 0; }
config_backup_restore "$IGOR_DIR/old.tar.gz" igor-state
''')
        self.assertNotIn(SENTINEL_2, restored.stdout + restored.stderr)
        self.assertEqual(original.read_text(), SENTINEL_1)
        with self.service._store() as db:
            active = self.service._row(db)[2]
        (self.service.material_dir / active).unlink()
        before = len(self.records())
        self.request(route="direct")
        self.assertEqual(len(self.records()), before)
        self.assertTrue(self.service.status()["cutover"])
        self.assertEqual(original.read_text(), SENTINEL_1)

    def test_session_cache_summary_role_selection_and_disabled_policy(self):
        self.assertEqual(self.install(SENTINEL_1).returncode, 0)
        conversation = [{"role": "user" if n % 2 == 0 else "assistant", "content":"synthetic turn " + str(n)} for n in range(16)]
        self.env["IGOR_AI_ROLE_BINDINGS"] = json.dumps({"summarizer":{"provider":"openrouter", "model":"openai/fixture-summary", "tools":False}})
        result = self.shell(r'''source "$IGOR_DIR/core/lib/module_loader.sh"
source "$IGOR_DIR/core/ai/core.sh"
ai_mode=executive provider=openrouter model=openai/fixture-model max_tokens=128
ok() { :; }; warn() { printf '%s\n' "$*" >&2; }
IFS= read -r or_api_key
IFS= read -r conversation
_nexus_api_call || exit 1
_ai_change_key openrouter || exit 1
_nexus_api_call_raw || exit 1
_ai_trim_with_summary "$conversation"
''', private_input=SENTINEL_1 + "\n" + json.dumps(conversation) + "\n" + SENTINEL_2 + "\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        requests = [row for row in self.records() if row["method"] == "POST"]
        self.assertEqual([row["headers"]["Authorization"] for row in requests],
                         ["Bearer " + SENTINEL_1, "Bearer " + SENTINEL_2, "Bearer " + SENTINEL_2])
        self.assertEqual(self.assert_request(SENTINEL_2)["model"], "openai/fixture-summary")
        self.env["NEXUS_PROVIDER"] = "anthropic"
        result = self.request(route="direct", role="reasoner")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.assert_request(SENTINEL_2)["model"], "openai/fixture-reasoner")
        self.env["IGOR_AI_ENABLED"] = "false"
        before = len(self.records())
        self.request(route="direct", role="reasoner")
        self.assertEqual(len(self.records()), before)


if __name__ == "__main__":
    unittest.main()
