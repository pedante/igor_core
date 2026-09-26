import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SettingsBackendTests(unittest.TestCase):
    def _run(self, body, event_stream="", extra_env=None):
        with tempfile.TemporaryDirectory() as runtime:
            env = {
                **os.environ,
                "IGOR_DIR": str(ROOT),
                "IGOR_RUNTIME_DIR": runtime,
            }
            if event_stream:
                env["IGOR_AI_EVENT_STREAM"] = event_stream
            env.update(extra_env or {})
            return subprocess.run(
                ["bash", "-c", body], env=env, text=True,
                capture_output=True, timeout=20,
            )

    def test_editable_values_use_save_hook_and_validate(self):
        with tempfile.TemporaryDirectory() as directory:
            settings_file = Path(directory) / "config" / "variables" / "ai_settings.env"
            script = r'''
source "$IGOR_DIR/core/ai/core.sh"
provider=openrouter model=old/model max_tokens=4096 NEXUS_TEMPERATURE=0.7
IGOR_VERBOSE=true AI_AUTOSTART=false AI_HYBRID_MODE=false ai_mode=assist
ai_get_mode() { printf '%s' "$ai_mode"; }
ai_set_cost_rates() { :; }
ai_scrub_build_table() { :; }
_ai_save_settings() { _ai_persist_settings "$TEST_SETTINGS_PATH"; }
_ai_apply_session_setting provider ollama
_ai_apply_session_setting model deepseek/deepseek-chat
_ai_apply_session_setting temperature 1.1
_ai_apply_session_setting max_tokens 2048
printf 'final=%s|%s|%s|%s\n' "$provider" "$model" "$max_tokens" "$NEXUS_TEMPERATURE"
if _ai_apply_session_setting temperature 4.0; then exit 9; fi
if _ai_apply_session_setting provider unknown; then exit 10; fi
if _ai_apply_session_setting max_tokens 0; then exit 11; fi
'''
            result = self._run(script, extra_env={"TEST_SETTINGS_PATH": str(settings_file)})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("final=ollama|deepseek/deepseek-chat|2048|1.1", result.stdout)
            saved = dict(line.split("=", 1) for line in settings_file.read_text().splitlines())
            self.assertEqual(saved["provider"], "ollama")
            self.assertEqual(saved["model"], "deepseek/deepseek-chat")
            self.assertEqual(saved["temperature"], "1.1")
            self.assertEqual(saved["max_tokens"], "2048")
            self.assertEqual(saved["ai_mode"], "assist")

    def test_snapshot_is_structured_and_contains_current_settings(self):
        with tempfile.TemporaryDirectory() as runtime:
            stream = Path(runtime) / "events.jsonl"
            script = r'''
source "$IGOR_DIR/core/ai/core.sh"
provider=openrouter model=demo/model max_tokens=1234 NEXUS_TEMPERATURE=0.4
IGOR_VERBOSE=false AI_AUTOSTART=true AI_HYBRID_MODE=true ai_mode=executive
ai_get_mode() { printf '%s' "$ai_mode"; }
_ai_emit_settings_snapshot
'''
            result = self._run(script, str(stream))
            self.assertEqual(result.returncode, 0, result.stderr)
            events = [json.loads(line) for line in stream.read_text().splitlines()]
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["event_type"], "settings_snapshot")
        self.assertEqual(events[0]["settings"], {
            "mode": "executive",
            "provider": "openrouter",
            "model": "demo/model",
            "temperature": "0.4",
            "max_tokens": "1234",
            "verbose": "false",
            "ai_autostart": "true",
            "hybrid_menu": "true",
        })

    def test_provider_switch_keeps_a_usable_model_and_rejects_wrong_model_family(self):
        script = r'''
source "$IGOR_DIR/core/ai/core.sh"
provider=openrouter model=deepseek/deepseek-chat max_tokens=4096
NEXUS_TEMPERATURE=0.7 IGOR_VERBOSE=true ai_mode=assist
_ai_save_settings() { :; }
ai_set_cost_rates() { :; }
ai_scrub_build_table() { :; }
_ai_apply_session_setting provider anthropic
printf 'anthropic=%s\n' "$model"
if _ai_apply_session_setting model deepseek/deepseek-chat; then exit 9; fi
printf 'after_reject=%s\n' "$model"
_ai_apply_session_setting provider openrouter
printf 'openrouter=%s\n' "$model"
'''
        result = self._run(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("anthropic=claude-sonnet-4-6", result.stdout)
        self.assertIn("after_reject=claude-sonnet-4-6", result.stdout)
        self.assertIn("openrouter=anthropic/claude-sonnet-4-6", result.stdout)

    def test_failed_save_restores_the_live_setting(self):
        script = r'''
source "$IGOR_DIR/core/ai/core.sh"
provider=openrouter model=old/model max_tokens=4096 NEXUS_TEMPERATURE=0.7
IGOR_VERBOSE=true ai_mode=assist
_ai_save_settings() { return 1; }
ai_set_cost_rates() { :; }
if _ai_apply_session_setting temperature 1.2; then exit 9; fi
printf 'temperature=%s tokens=%s\n' "$NEXUS_TEMPERATURE" "$max_tokens"
'''
        result = self._run(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("temperature=0.7 tokens=4096", result.stdout)

    def test_setting_change_requires_the_existing_save_hook(self):
        script = r'''
source "$IGOR_DIR/core/ai/core.sh"
provider=openrouter model=old/model max_tokens=4096 NEXUS_TEMPERATURE=0.7
IGOR_VERBOSE=true ai_mode=assist
ai_set_cost_rates() { :; }
if _ai_apply_session_setting max_tokens 2048; then exit 9; fi
printf 'tokens=%s\n' "$max_tokens"
'''
        result = self._run(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tokens=4096", result.stdout)


if __name__ == "__main__":
    unittest.main()
