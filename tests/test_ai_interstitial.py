"""Interactive setup and scrub-status regressions, without a live provider."""

import base64
import json
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class InterstitialTests(unittest.TestCase):
    def test_context_sections_count_reference_envelope(self):
        if not shutil.which("script"):
            self.skipTest("script PTY utility unavailable")
        reference = base64.b64encode(json.dumps({
            "host_and_module_state": "Hostname: fixture-host",
            "module_knowledge": "",
        }).encode()).decode()
        with tempfile.TemporaryDirectory() as runtime:
            shell = '''
source "$IGOR_DIR/core/ai/core.sh"
prompt="$TEST_PROMPT"
_ai_prompt_interstitial prompt test-model test-provider
'''
            result = subprocess.run(
                ["script", "-qefc", "bash -c " + shlex.quote(shell), "/dev/null"],
                input="\n", text=True, capture_output=True, timeout=10,
                env={**os.environ, "IGOR_DIR": str(ROOT), "IGOR_RUNTIME_DIR": runtime,
                     "TEST_PROMPT": "Policy\nIGOR_REFERENCE_V1:" + reference + "\n"},
            )
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("Sections:", result.stdout)
            self.assertIn("Sections: 1", result.stdout)

    def test_prompt_ready_enter_renders_single_control_row(self):
        if not shutil.which("script"):
            self.skipTest("script PTY utility unavailable")
        with tempfile.TemporaryDirectory() as runtime:
            shell = '''
source "$IGOR_DIR/core/ai/core.sh"
prompt="test policy"
igor_right_render(){ printf 'RIGHT_RENDER\\n'; }
_ai_prompt_interstitial prompt test-model test-provider
'''
            result = subprocess.run(
                ["script", "-qefc", "bash -c " + shlex.quote(shell), "/dev/null"],
                input="\n", text=True, capture_output=True, timeout=10,
                env={**os.environ, "IGOR_DIR": str(ROOT), "IGOR_RUNTIME_DIR": runtime},
            )
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(result.stdout.count("RIGHT_RENDER"), 1)
            self.assertEqual(result.stdout.count("[Enter] start"), 1)

    def test_prompt_ready_controls_once_and_private_editor_file(self):
        if not shutil.which("script"):
            self.skipTest("script PTY utility unavailable")
        with tempfile.TemporaryDirectory() as runtime:
            shell = '''
source "$IGOR_DIR/core/ai/core.sh"
prompt="test policy"
igor_right_render(){ printf 'RIGHT_RENDER\\n'; }
igor_edit_file(){
    printf 'EDITOR_MODE=%s\\n' "$(stat -c %a "$1")"
    printf 'edited policy' > "$1"
}
_ai_prompt_interstitial prompt test-model test-provider
printf 'FINAL_PROMPT=%s\\n' "$prompt"
'''
            result = subprocess.run(
                ["script", "-qefc", "bash -c " + shlex.quote(shell), "/dev/null"],
                input="e\n", text=True, capture_output=True, timeout=10,
                env={**os.environ, "IGOR_DIR": str(ROOT), "IGOR_RUNTIME_DIR": runtime},
            )
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(result.stdout.count("RIGHT_RENDER"), 2)
            self.assertEqual(result.stdout.count("[Enter] start"), 2)
            self.assertIn("EDITOR_MODE=600", result.stdout)
            self.assertIn("FINAL_PROMPT=edited policy", result.stdout)
            self.assertEqual(list(Path(runtime).glob(".igor_prompt.*")), [])
            self.assertNotIn("/tmp/igor_prompt_last.txt", result.stdout)
            self.assertNotIn("/tmp/igor_prompt_last.txt",
                             (ROOT / "core/ai/core.sh").read_text())

    def test_scrub_warning_has_a_distinct_status_from_success(self):
        with tempfile.TemporaryDirectory() as runtime:
            for warning, expected in (("", "STATUS=0"), ("validation warning", "STATUS=2")):
                shell = '''
source "$IGOR_DIR/core/ai/core.sh"
ai_scrub_outbound(){
    printf 'safe context\\n'
    if [ -n "$TEST_WARNING" ]; then printf '%s\\n' "$TEST_WARNING" >&2; fi
}
_ai_scrub_context_for_display "context"
printf 'STATUS=%s\\n' "$?"
'''
                result = subprocess.run(
                    ["bash", "-c", shell], capture_output=True, text=True, check=True,
                    env={**os.environ, "IGOR_DIR": str(ROOT),
                         "IGOR_RUNTIME_DIR": runtime, "TEST_WARNING": warning},
                )
                self.assertIn(expected, result.stdout)
                self.assertEqual(list(Path(runtime).glob(".scrub-warnings.*")), [])


if __name__ == "__main__":
    unittest.main()
