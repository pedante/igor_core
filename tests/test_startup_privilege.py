"""Startup privilege and terminal-input regressions with isolated Igor roots."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class StartupPrivilegeTests(unittest.TestCase):
    def run_igor(self, input_text="\nq\n", *, root=False, pending=False,
                 ai_mode=False):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            shutil.copy2(ROOT / "igor.sh", work / "igor.sh")
            shutil.copy2(ROOT / "VERSION", work / "VERSION")
            (work / "core").symlink_to(ROOT / "core", target_is_directory=True)
            (work / "modules").symlink_to(ROOT / "modules", target_is_directory=True)
            (work / "config" / "variables").mkdir(parents=True)
            (work / "config" / "variables" / "igor.env").write_text(
                "IGOR_USE_TMUX=false\nIGOR_FZF_ALREADY_ASKED=true\n"
            )
            if ai_mode:
                # These cases test classic Start/Fast input and session lifecycle,
                # not OpenRouter credential import. Boundary B deliberately
                # rejects inherited OPENROUTER_API_KEY after managed cutover.
                # Use a local provider with a synthetic curl health response.
                (work / "config" / "variables" / "ai.env").write_text(
                    "provider=ollama\nmodel=llama3.2:3b\n"
                )
            (work / "secrets").mkdir()
            (work / "data").mkdir()
            (work / "home").mkdir()
            if pending:
                (work / "data" / "alerts").mkdir()
                (work / "data" / "alerts" / "pending.log").write_text("fixture alert\n")

            bin_dir = work / "bin"
            bin_dir.mkdir()
            sudo_log = work / "sudo.log"
            sudo = bin_dir / "sudo"
            sudo.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$TEST_SUDO_LOG\"\nexit 1\n")
            sudo.chmod(0o755)
            if ai_mode:
                curl = bin_dir / "curl"
                curl.write_text("#!/bin/sh\nprintf 200\n")
                curl.chmod(0o755)
            if root:
                fake_id = bin_dir / "id"
                fake_id.write_text(
                    "#!/bin/sh\nif [ \"$1\" = -u ]; then echo 0; else /usr/bin/id \"$@\"; fi\n"
                )
                fake_id.chmod(0o755)
            else:
                fake_id = bin_dir / "id"
                fake_id.write_text(
                    "#!/bin/sh\nif [ \"$1\" = -u ]; then echo 1000; else /usr/bin/id \"$@\"; fi\n"
                )
                fake_id.chmod(0o755)

            env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}",
                   "TEST_SUDO_LOG": str(sudo_log), "IGOR_USE_TMUX": "false",
                   "IGOR_FZF_ALREADY_ASKED": "true", "TERM": "dumb",
                   "AI_AUTOSTART": "false", "AI_SKIP_INTERSTITIAL": "true",
                   "OPENROUTER_API_KEY": "", "OR_API_KEY": "",
                   "NEXUS_API_KEY": "", "ANTHROPIC_API_KEY": "",
                   "IGOR_OLLAMA_HOST": "http://127.0.0.1:11434",
                   "HOME": str(work / "home")}
            result = subprocess.run(
                ["bash", str(work / "igor.sh")], input=input_text, text=True,
                capture_output=True, env=env, timeout=20,
            )
            runtime = work / "data" / "runtime"
            state = runtime / "state.env"
            runtime_info = (runtime.exists(),
                            runtime.stat().st_mode & 0o777 if runtime.is_dir() else None,
                            runtime.stat().st_uid if runtime.is_dir() else None)
            return result, sudo_log.read_text() if sudo_log.exists() else "", \
                runtime_info, state.read_text() if state.is_file() else ""

    def test_normal_user_reaches_menu_without_sudo_and_pause_works(self):
        result, sudo_calls, _, _ = self.run_igor()
        self.assertEqual(result.returncode, 0, result.stderr[-1000:])
        self.assertIn("Main Menu", result.stdout)
        self.assertIn("Select option:", result.stdout)
        self.assertEqual(sudo_calls, "")

    def test_alert_continue_keeps_menu_input(self):
        result, sudo_calls, _, _ = self.run_igor("\nq\n", pending=True)
        self.assertEqual(result.returncode, 0, result.stderr[-1000:])
        self.assertIn("fixture alert", result.stdout)
        self.assertIn("Select option:", result.stdout)
        self.assertEqual(sudo_calls, "")

    def test_press_enter_after_invalid_choice_returns_to_menu(self):
        result, sudo_calls, _, _ = self.run_igor("\nx\n\nq\n")
        self.assertEqual(result.returncode, 0)
        self.assertIn("Invalid option. Please try again.", result.stdout)
        self.assertGreaterEqual(result.stdout.count("Main Menu"), 2)
        self.assertEqual(sudo_calls, "")

    def test_root_launch_rejected_before_runtime_initialization(self):
        result, sudo_calls, runtime, _ = self.run_igor("", root=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("intended to run as a normal user", result.stderr)
        self.assertFalse(runtime[0])
        self.assertEqual(sudo_calls, "")

    def test_closed_menu_input_exits_instead_of_spinning(self):
        result, _, _, _ = self.run_igor("\n")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.count("Main Menu"), 1)

    def test_start_and_fast_enter_after_normal_user_startup(self):
        for choice in ("s", "f"):
            with self.subTest(choice=choice):
                result, sudo_calls, runtime, state = self.run_igor(
                    f"\na\n{choice}\nq\n", ai_mode=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr[-1000:])
                self.assertIn("Ollama (local)", result.stdout)
                self.assertIn("Session ended.", result.stdout)
                self.assertIn("AI_SESSION_STATE=user_exited", state)
                self.assertTrue(runtime[0])
                self.assertEqual(runtime[1], 0o700)
                self.assertEqual(runtime[2], os.getuid())
                self.assertEqual(sudo_calls, "")
                if choice == "f":
                    self.assertIn("Fast mode", result.stdout)

    def test_privileged_package_operation_elevates_when_requested(self):
        script = r'''
source core/lib/pkg.sh
id() { [ "$1" = -u ] && echo 1000; }
sudo() { printf 'sudo %s\n' "$*"; }
IGOR_DISTRO_FAMILY=arch
pkg_install vlc
'''
        result = subprocess.run(["bash", "-c", script], cwd=ROOT,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertIn("sudo pacman -S --noconfirm vlc", result.stdout)

    def test_profile_cache_uses_private_resolved_runtime(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            runtime = root / "private-runtime"
            env = {**os.environ, "IGOR_DIR": temp,
                   "IGOR_RUNTIME_DIR": str(runtime)}
            script = f'''
source "{ROOT}/core/lib/helpers.sh"
source "{ROOT}/core/host/profile.sh"
_profile_read_ram_mb() {{ echo 4096; }}
igor_load_profile
printf 'tier=%s path=%s\\n' "$IGOR_TIER" "$_PROFILE_FILE"
mkdir -m 700 "$IGOR_RUNTIME_DIR"
igor_detect_profile
'''
            result = subprocess.run(["bash", "-c", script], env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f"path={runtime}/system_profile.json", result.stdout)
            cache = runtime / "system_profile.json"
            self.assertTrue(cache.is_file())
            self.assertEqual(cache.stat().st_mode & 0o777, 0o600)
            self.assertEqual(cache.stat().st_uid, os.getuid())

    def test_status_hook_does_not_elevate_for_read_only_display(self):
        script = r'''
source modules/nextcloud_docker/module.sh
sudo() { echo sudo-called; return 1; }
systemctl() { [ "$1" = is-active ]; }
journalctl() { printf 'Connection registered\n'; }
_nc_check_http() { printf '200'; }
nextcloud_docker__status_line
'''
        result = subprocess.run(["bash", "-c", script], cwd=ROOT,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("sudo-called", result.stdout)
        self.assertIn("CONNECTED", result.stdout)

    def test_network_health_read_does_not_elevate(self):
        for service_state, expected in (("active", "tunnel_connected"),
                                        ("inactive", "tunnel_down")):
            with self.subTest(service_state=service_state):
                script = r'''
source modules/nextcloud_docker/checks/network.sh
sudo() { echo sudo-called; return 1; }
ping() { return 1; }
getent() { return 1; }
systemctl() { printf '%s\n' "$TEST_SERVICE_STATE"; [ "$TEST_SERVICE_STATE" = active ]; }
journalctl() { printf 'Connection registered\n'; }
ss() { :; }
run_check
'''
                result = subprocess.run(
                    ["bash", "-c", script], cwd=ROOT,
                    env={**os.environ, "TEST_SERVICE_STATE": service_state},
                    capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 0)
                self.assertNotIn("sudo-called", result.stdout)
                self.assertIn(expected, result.stdout)

    def test_hook_child_cannot_consume_other_hooks_input(self):
        script = r'''
source core/lib/module_loader.sh
stealing_hook() { cat >/dev/null; echo first; }
second_hook() { echo second; }
igor_register_hook status_line stealing_hook
igor_register_hook status_line second_hook
igor_run_all_hooks status_line
'''
        result = subprocess.run(["bash", "-c", script], cwd=ROOT,
                                input="menu choice\n", capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertIn("first", result.stdout)
        self.assertIn("second", result.stdout)


if __name__ == "__main__":
    unittest.main()
