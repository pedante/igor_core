"""Menu startup lifecycle regressions without network or host operations."""

import json
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AIMenuStartupTests(unittest.TestCase):
    def run_menu(self, selection, *, failure="", input_text="q\nx", fallback=False,
                 runtime_case="absent", tui=False):
        shell = r'''
source "$IGOR_DIR/core/ai/core.sh"
header(){ :; }
clear(){ :; }
igor_fzf_pick(){
    if [ "$TEST_FALLBACK" = true ]; then return 2; fi
    printf '%s' "$TEST_SELECTION"
}
_nexus_validate_or_key(){
    [ -z "$TEST_PROVIDER_MARKER" ] || printf 'validated\n' >> "$TEST_PROVIDER_MARKER"
    [ "$TEST_FAILURE" != key ]
}
_nexus_get_or_balance(){ :; }
ai_knowledge_load(){ printf 'knowledge'; }
ai_knowledge_show_status(){ :; }
ai_gather_context(){
    [ -z "$TEST_CONTEXT_MARKER" ] || printf 'gathered\n' >> "$TEST_CONTEXT_MARKER"
    printf 'fixture context'
}
ai_scrub_build_table(){ :; }
_ai_scrub_context_for_display(){
    if [ "$TEST_FAILURE" = scrub ]; then return 1; fi
    printf 'fixture context'
}
_ai_build_system_prompt(){
    [ -z "$TEST_PROMPT_MARKER" ] || printf 'built\n' >> "$TEST_PROMPT_MARKER"
    printf 'fixture policy'
}
igor_ai_entry(){
    [ -z "$TEST_CLASSIC_UI_MARKER" ] || printf 'entry\n' >> "$TEST_CLASSIC_UI_MARKER"
}
igor_right_render(){
    [ -z "$TEST_CLASSIC_UI_MARKER" ] || printf 'right\n' >> "$TEST_CLASSIC_UI_MARKER"
}
_ai_prompt_interstitial(){
    case "$TEST_FAILURE" in
        prompt_cancel) return 1 ;;
        prompt_input) return 2 ;;
    esac
    return 0
}
ai_knowledge_session_end(){ :; }
save_conversation_to_output(){ :; }
_write_session_postmortem(){ :; }
_ai_read_steering_name(){ :; }
if [ "$TEST_FAILURE" = log ]; then _ai_session_log_create(){ return 1; }; fi
if [ "$TEST_FAILURE" = foreign ]; then _ai_runtime_owner_ok(){ return 1; }; fi
menu_ai
printf '\nMENU_RETURN=%s\n' "$?"
'''
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "core").symlink_to(ROOT / "core", target_is_directory=True)
            runtime = root / "data" / "runtime"
            (root / "data" / "sessions").mkdir(parents=True)
            (root / "secrets").mkdir()
            if runtime_case == "existing":
                runtime.mkdir()
                runtime.chmod(0o755)
            elif runtime_case == "symlink":
                target = root / "runtime-target"
                target.mkdir()
                runtime.symlink_to(target, target_is_directory=True)
            elif runtime_case == "parent_symlink":
                target = root / "parent-target"
                target.mkdir()
                (root / "parent-link").symlink_to(target, target_is_directory=True)
                runtime = root / "parent-link" / "runtime"
            elif runtime_case == "parent_file":
                (root / "unavailable").write_text("parent is a file")
                runtime = root / "unavailable" / "runtime"
            elif runtime_case == "state_file_dir":
                runtime.mkdir()
                (runtime / "state.env").mkdir()
            elif runtime_case != "absent":
                raise ValueError(runtime_case)
            tmptrap = root / "tmptrap"
            tmptrap.mkdir()
            provider_marker = root / "provider.marker"
            context_marker = root / "context.marker"
            prompt_marker = root / "prompt.marker"
            classic_ui_marker = root / "classic-ui.marker"
            env = {**os.environ, "IGOR_DIR": temp,
                   "IGOR_RUNTIME_DIR": str(runtime),
                   "TMPDIR": str(tmptrap),
                   "OPENROUTER_API_KEY": "fixture-key", "provider": "openrouter",
                   "TEST_SELECTION": selection, "TEST_FAILURE": failure,
                   "TEST_FALLBACK": str(fallback).lower(),
                   "TEST_PROVIDER_MARKER": str(provider_marker),
                   "TEST_CONTEXT_MARKER": str(context_marker),
                   "TEST_PROMPT_MARKER": str(prompt_marker),
                   "TEST_CLASSIC_UI_MARKER": str(classic_ui_marker),
                   "TERM": "dumb", "IGOR_AI_ENABLED": "true"}
            if tui:
                env["IGOR_TUI_MODE"] = "true"
                env["AI_SKIP_INTERSTITIAL"] = "true"
                env["IGOR_TUI_STARTED_MS"] = str(int(time.time() * 1000))
                # core.sh is sourced directly in this fixture, so seed the
                # upstream Boundary I observations that igor.sh normally owns.
                env.update({
                    "_IGOR_TUI_BACKEND_SPAWN_MS": "1",
                    "_IGOR_TUI_BACKEND_PREBOOTSTRAP_MS": "2",
                    "_IGOR_TUI_BOOTSTRAP_CONFIG_MS": "3",
                    "_IGOR_TUI_BOOTSTRAP_MODULES_MS": "4",
                    "_IGOR_TUI_BOOTSTRAP_MODULE_CONFIG_MS": "5",
                    "_IGOR_TUI_BOOTSTRAP_AUX_SOURCES_MS": "6",
                    "_IGOR_TUI_BOOTSTRAP_CONFIG_HOOKS_MS": "7",
                    "_IGOR_TUI_BACKEND_DISPATCH_MS": "8",
                    "_IGOR_TUI_AI_SOURCE_MS": "9",
                })
            result = subprocess.run(["bash", "-c", shell], input=input_text,
                                    text=True, capture_output=True, env=env, timeout=15)
            state = runtime / "state.env"
            logs = list((root / "data" / "sessions").glob("session_*.log"))
            trace = logs[0].read_text() if logs else ""
            event_rows = []
            if runtime.is_dir():
                for event_file in runtime.glob("frontend-*.jsonl"):
                    for line in event_file.read_text().splitlines():
                        try:
                            event_rows.append(json.loads(line))
                        except (OSError, ValueError):
                            pass
            runtime_info = {"path": str(runtime), "exists": runtime.is_dir(),
                            "symlink": runtime.is_symlink(),
                            "mode": runtime.stat().st_mode & 0o777 if runtime.is_dir() else None,
                            "tmp_entries": list(tmptrap.iterdir()),
                            "target_mode": (root / "runtime-target").stat().st_mode & 0o777
                            if (root / "runtime-target").exists() else None,
                            "provider_validated": provider_marker.exists(),
                            "context_gathered": context_marker.exists(),
                            "prompt_built": prompt_marker.exists(),
                            "classic_ui_used": classic_ui_marker.exists(),
                            "events": event_rows}
            return result, state.read_text() if state.is_file() else "", trace, runtime_info

    def test_start_and_fast_enter_same_chat_loop_until_explicit_exit(self):
        for selection in ("s", "f"):
            with self.subTest(selection=selection):
                result, state, trace, runtime = self.run_menu(selection)
                self.assertIn("Igor", result.stdout)
                self.assertIn("Session ended.", result.stdout)
                self.assertIn("MENU_RETURN=0", result.stdout)
                self.assertIn("AI_SESSION_STATE=user_exited", state)
                self.assertIn("AI_SESSION_ACTIVE=0", state)
                self.assertTrue(runtime["exists"])
                self.assertEqual(runtime["mode"], 0o700)
                self.assertEqual(runtime["tmp_entries"], [])
                self.assertTrue(runtime["classic_ui_used"])
                self.assertTrue(runtime["prompt_built"])
                positions = [trace.index(f"[STATE] {name}") for name in
                             ("ready", "running", "user_exited")]
                self.assertEqual(positions, sorted(positions))
                if selection == "f":
                    self.assertIn("Fast mode — skipping server scan", result.stdout)
                    self.assertNotIn("Context auto-refreshing", result.stdout)
                else:
                    self.assertIn("Scanning your server", result.stdout)

    def test_text_selection_fallback_enters_both_sessions_and_back_works(self):
        for selection in ("s", "f"):
            with self.subTest(selection=selection):
                result, state, _, _ = self.run_menu(selection, fallback=True,
                                                    input_text=f"{selection}\nq\nx")
                self.assertIn("Session ended.", result.stdout)
                self.assertIn("MENU_RETURN=0", result.stdout)
                self.assertIn("AI_SESSION_STATE=user_exited", state)
        back, _, _, _ = self.run_menu("q", fallback=True, input_text="q\n")
        self.assertIn("MENU_RETURN=0", back.stdout)
        self.assertNotIn("Session ended.", back.stdout)

    def test_startup_failure_is_visible_and_distinct_from_exit(self):
        for selection in ("s", "f"):
            with self.subTest(selection=selection):
                result, state, _, _ = self.run_menu(selection, failure="log", input_text="")
                self.assertIn("AI session initialization failed", result.stderr + result.stdout)
                self.assertIn("stage: session_log", result.stderr + result.stdout)
                self.assertIn("MENU_RETURN=2", result.stdout)
                self.assertIn("AI_SESSION_STATE=startup_failed", state)

    def test_provider_key_failure_and_back(self):
        result, state, _, _ = self.run_menu("s", failure="key")
        self.assertIn("stage: provider_key", result.stderr + result.stdout)
        self.assertIn("MENU_RETURN=2", result.stdout)
        self.assertIn("AI_SESSION_STATE=startup_failed", state)
        back, _, _, _ = self.run_menu("q", input_text="")
        self.assertIn("MENU_RETURN=0", back.stdout)
        self.assertNotIn("AI session initialization failed", back.stdout + back.stderr)

    def test_context_and_prompt_startup_outcomes(self):
        for failure, stage in (("scrub", "context_scrub"),
                               ("prompt_input", "prompt_input")):
            with self.subTest(failure=failure):
                result, state, _, _ = self.run_menu("s", failure=failure, input_text="")
                self.assertIn(f"stage: {stage}", result.stderr + result.stdout)
                self.assertIn("MENU_RETURN=2", result.stdout)
                self.assertIn("AI_SESSION_STATE=startup_failed", state)
        cancelled, state, _, _ = self.run_menu("s", failure="prompt_cancel", input_text="")
        self.assertIn("MENU_RETURN=0", cancelled.stdout)
        self.assertIn("AI_SESSION_STATE=user_exited", state)
        self.assertNotIn("AI session initialization failed", cancelled.stderr)


    def test_tui_reaches_input_ready_before_provider_or_context_preflight(self):
        result, state, trace, runtime = self.run_menu("s", tui=True, input_text="q\nx")
        self.assertIn("MENU_RETURN=0", result.stdout)
        self.assertIn("AI_SESSION_STATE=user_exited", state)
        self.assertFalse(runtime["provider_validated"])
        self.assertFalse(runtime["context_gathered"])
        self.assertFalse(runtime["prompt_built"])
        self.assertFalse(runtime["classic_ui_used"])
        self.assertTrue(any(row.get("event_type") == "model_status" and
                            row.get("status") == "input_ready"
                            for row in runtime["events"]))
        self.assertNotIn("[TIMING] provider.preflight=", trace)
        self.assertNotIn("[TIMING] context.first_request=", trace)
        for stage in (
            "tui.backend_spawn",
            "tui.backend_prebootstrap",
            "tui.bootstrap_config",
            "tui.bootstrap_modules",
            "tui.bootstrap_module_config",
            "tui.bootstrap_aux_sources",
            "tui.bootstrap_config_hooks",
            "tui.backend_dispatch",
            "tui.ai_source",
            "tui.ai_pre_session",
            "tui.ai_session_runtime",
            "tui.ai_local_ui",
            "tui.ai_local_knowledge",
            "tui.ai_local_prompt",
            "tui.ai_local_session_header",
            "tui.ai_local_command_reference",
            "tui.ai_local_setup",
            "tui.ai_operator_snapshot",
            "tui.ai_ready_finalize",
            "tui.startup_to_input_ready",
        ):
            self.assertIn(f"[TIMING] {stage}=", trace)

    def test_deferred_request_preparation_runs_provider_before_context_once(self):
        shell = r"""
source "$IGOR_DIR/core/ai/core.sh"
provider=openrouter
or_api_key=fixture-key
knowledge_block=knowledge
system_prompt='placeholder prompt'
system_context='placeholder context'
scrubbed_context='placeholder context'
_provider_preflight_deferred=true
_context_deferred=true
_context_captured_at=0
_context_refresh_interval=300
_key_status='deferred'
_nexus_validate_or_key(){ printf 'provider\n' >> "$ORDER_MARKER"; return 0; }
ai_gather_context(){ printf 'context\n' >> "$ORDER_MARKER"; printf 'fresh context'; }
ai_scrub_build_table(){ :; }
_ai_scrub_context_for_display(){ cat; }
_ai_build_system_prompt(){ printf 'fresh prompt'; }

_ai_prepare_deferred_request_runtime || exit 11
printf 'provider_deferred=%s\n' "$_provider_preflight_deferred"
printf 'context_deferred=%s\n' "$_context_deferred"
printf 'prompt=%s\n' "$system_prompt"
_ai_prepare_deferred_request_runtime || exit 12
"""
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "core").symlink_to(ROOT / "core", target_is_directory=True)
            order_marker = root / "order.marker"
            env = {**os.environ, "IGOR_DIR": temp, "TERM": "dumb",
                   "ORDER_MARKER": str(order_marker)}
            result = subprocess.run(["bash", "-c", shell], text=True,
                                    capture_output=True, env=env, timeout=15)
            order = order_marker.read_text().splitlines()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(order, ["provider", "context"])
        self.assertIn("provider_deferred=false", result.stdout)
        self.assertIn("context_deferred=false", result.stdout)
        self.assertIn("prompt=fresh prompt", result.stdout)

    def test_mode_change_does_not_force_deferred_prompt_render(self):
        shell = r"""
source "$IGOR_DIR/core/ai/core.sh"
provider=openrouter
ai_mode=assist
executive_mode=false
knowledge_block=knowledge
scrubbed_context='placeholder context'
system_prompt='placeholder prompt'
_context_deferred=true
PROMPT_CALLS=0
_ai_save_settings(){ :; }
_ai_frontend_event(){ :; }
_ai_build_system_prompt(){ PROMPT_CALLS=$((PROMPT_CALLS + 1)); printf 'rendered-%s' "$PROMPT_CALLS"; }

_ai_set_mode guide >/dev/null || exit 11
printf 'deferred_calls=%s\n' "$PROMPT_CALLS"
printf 'deferred_prompt=%s\n' "$system_prompt"
_context_deferred=false
_ai_set_mode assist >/dev/null || exit 12
printf 'ready_calls=%s\n' "$PROMPT_CALLS"
printf 'ready_prompt=%s\n' "$system_prompt"
"""
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "core").symlink_to(ROOT / "core", target_is_directory=True)
            env = {**os.environ, "IGOR_DIR": temp, "TERM": "dumb"}
            result = subprocess.run(["bash", "-c", shell], text=True,
                                    capture_output=True, env=env, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("deferred_calls=0", result.stdout)
        self.assertIn("deferred_prompt=placeholder prompt", result.stdout)
        self.assertIn("ready_calls=1", result.stdout)
        self.assertIn("ready_prompt=rendered-1", result.stdout)

    def test_input_eof_is_not_a_user_exit(self):
        result, state, _, _ = self.run_menu("f", input_text="")
        self.assertIn("input closed unexpectedly", result.stderr)
        self.assertIn("MENU_RETURN=2", result.stdout)
        self.assertIn("AI_SESSION_STATE=input_closed", state)

    def test_existing_runtime_is_reused_and_made_private(self):
        result, state, _, runtime = self.run_menu("s", runtime_case="existing")
        self.assertIn("MENU_RETURN=0", result.stdout)
        self.assertIn("AI_SESSION_STATE=user_exited", state)
        self.assertEqual(runtime["mode"], 0o700)

    def test_unsafe_runtime_paths_fail_with_resolved_path_and_detail(self):
        for case, failure, detail in (("symlink", "", "symlink"),
                                      ("parent_symlink", "", "symlink"),
                                      ("parent_file", "", "not a directory"),
                                      ("existing", "foreign", "another user")):
            with self.subTest(case=case, failure=failure):
                result, _, _, runtime = self.run_menu("f", runtime_case=case,
                                                      failure=failure, input_text="")
                output = result.stderr + result.stdout
                self.assertIn("stage: runtime", output)
                self.assertIn(f"path: {runtime['path']}", output)
                self.assertIn(detail, output)
                self.assertIn("MENU_RETURN=2", result.stdout)
                self.assertNotIn("Session ended.", result.stdout)
                self.assertEqual(runtime["tmp_entries"], [])
                if case == "symlink":
                    self.assertEqual(runtime["target_mode"], 0o755)

    def test_state_file_failure_is_distinct_from_directory_failure(self):
        result, _, _, runtime = self.run_menu("s", runtime_case="state_file_dir",
                                              input_text="")
        output = result.stderr + result.stdout
        self.assertIn("stage: runtime_state", output)
        self.assertIn(f"path: {runtime['path']}", output)
        self.assertIn("runtime state file", output)
        self.assertIn("MENU_RETURN=2", result.stdout)

    def test_concurrent_runtime_preparation_uses_one_private_directory(self):
        shell = r'''
source "$IGOR_DIR/core/ai/core.sh"
declare -a pids=()
for _ in 1 2 3 4 5 6 7 8; do
    (_ai_runtime_private_dir >/dev/null) &
    pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || exit 1; done
'''
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "core").symlink_to(ROOT / "core", target_is_directory=True)
            (root / "data").mkdir()
            runtime = root / "data" / "runtime"
            env = {**os.environ, "IGOR_DIR": temp, "IGOR_RUNTIME_DIR": str(runtime)}
            result = subprocess.run(["bash", "-c", shell], text=True,
                                    capture_output=True, env=env, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(runtime.stat().st_mode & 0o777, 0o700)

    def test_default_runtime_uses_igor_resolver_not_xdg_or_global_tmp(self):
        shell = r'''
source "$IGOR_DIR/core/lib/helpers.sh"
source "$IGOR_DIR/core/ai/core.sh"
_ai_runtime_private_dir
'''
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "core").symlink_to(ROOT / "core", target_is_directory=True)
            (root / "data").mkdir()
            xdg = root / "xdg"
            xdg.mkdir()
            env = {**os.environ, "IGOR_DIR": temp, "XDG_RUNTIME_DIR": str(xdg)}
            env.pop("IGOR_RUNTIME_DIR", None)
            result = subprocess.run(["bash", "-c", shell], text=True,
                                    capture_output=True, env=env, timeout=15)
            expected = root / "data" / "runtime"
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, str(expected))
            self.assertEqual(expected.stat().st_mode & 0o777, 0o700)
            self.assertEqual(list(xdg.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
