"""Real curses, outer/inner PTYs and Igor backend over private System/History state."""

import fcntl
import json
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time
from pathlib import Path

import test_operator_cli as cli_tests
from test_ai_tui_collection_backend import Terminal

ROOT = Path(__file__).resolve().parents[1]


def test_system_read_cli_and_real_tui_share_history(tmp_path):
    fixture = cli_tests.PublicCapabilityCliTests()
    fixture.setUp()
    root = fixture.root
    process = None
    master = None
    try:
        (root / "modules/system").symlink_to(ROOT / "modules/system", target_is_directory=True)
        (root / "config/modules.conf").write_text("system=enabled\nfixture=disabled\n")
        (root / "config/variables").mkdir()
        (root / "config/variables/ai_settings.env").write_text(
            "provider=ollama\nmodel=fixture-local\nai_mode=assist\n")
        cli = fixture.cli("--json", "capability", "run", "system.host.summary", "{}", "system")
        assert cli.returncode == 0, cli.stderr + cli.stdout
        cli_result = json.loads(cli.stdout)
        assert cli_result["outcome"] == "success"
        stream = root / "data/runtime/operator-events.jsonl"
        transcript = bytearray()
        terminal = Terminal()
        env = {**fixture.env, "IGOR_DIR": str(root), "TERM": "xterm",
               "IGOR_TUI_MOUSE": "0", "IGOR_AI_CONTEXT": "minimal"}
        # The frontend's owning-service inspection subprocesses use this private
        # installation too; all actual UI/backend/dispatcher code is unchanged.
        launch = '''import sys,signal
from pathlib import Path
sys.path.insert(0,sys.argv[1])
import tui
tui.REPO_ROOT=Path(sys.argv[2])
def stop(*_): raise SystemExit(130)
signal.signal(signal.SIGTERM,stop)
raise SystemExit(tui.run_tui(("bash",str(tui.REPO_ROOT/"igor.sh"),"--ai-tui-backend"),Path(sys.argv[3])))
'''
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 110, 0, 0))
        process = subprocess.Popen(
            [sys.executable, "-c", launch, str(ROOT / "core/ai"), str(root), str(stream)],
            env=env, stdin=slave, stdout=slave, stderr=slave, start_new_session=True,
        )
        os.close(slave)

        def wait_text(expected, timeout=45):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if expected in terminal.text():
                    return
                if select.select([master], [], [], 0.05)[0]:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    transcript.extend(chunk)
                    terminal.feed(chunk)
                if process.poll() is not None:
                    break
            raise AssertionError(f"Missing {expected!r}: {terminal.text()}")

        def events():
            return [json.loads(line) for line in stream.read_text().splitlines()]

        wait_text("READY")
        os.write(master, b"\x02" + b"\x1bOB" * 5 + b"\n")
        wait_text("system · active")
        os.write(master, b"\x02")
        wait_text("LIVE")
        os.write(master, b":sys.host.summary\n")
        wait_text("Verification: not_applicable")
        wait_text("kernel:")
        wait_text("READY")
        tui_result = next(row["result"] for row in events()
                          if row["event_type"] == "action_result" and
                          row.get("result", {}).get("capability_id") == "system.host.summary")
        assert tui_result["outcome"] == "success"
        assert tui_result["operation_id"] != cli_result["operation_id"]
        assert tui_result["provider"] == cli_result["provider"] == "system"
        assert tui_result["result"]["kernel"] == cli_result["result"]["kernel"]
        assert tui_result["result"]["architecture"] == cli_result["result"]["architecture"]

        # Control panel History lists both interfaces, then opens a selected
        # authoritative operation. Arrow bytes use the terminal's application mode.
        # Panel selection remains on Modules, two rows below History.
        os.write(master, b"\x02" + b"\x1bOA" * 2 + b"\n")
        wait_text(cli_result["operation_id"][:28])
        wait_text(tui_result["operation_id"][:28])
        os.write(master, b"\n")
        wait_text("Source: --history inspect")
        wait_text("Read-only")
        os.write(master, b"r")
        wait_text("Source: --history recent 20")
        os.write(master, b"\x02")
        wait_text("LIVE")

        # A stale typed request still enters backend validation, never an AI
        # request or a frontend executor. The unavailable ID has no handler.
        os.write(master, b"invoke system.missing.read\n")
        wait_text("Capability refused")
        wait_text("READY")
        assert any(row["event_type"] == "warning" and row.get("status") == "refused"
                   for row in events())
        os.write(master, b"quit\n")
        process.wait(timeout=12)
        assert process.returncode == 0
        history = fixture.cli("history", "recent", "20")
        assert history.returncode == 0, history.stderr
        records = json.loads(history.stdout)
        assert len(records) == 2
        assert {row["provenance"]["interface"] for row in records} == {"cli", "operator_surface"}
        assert {row["operation_id"] for row in records} == {
            cli_result["operation_id"], tui_result["operation_id"],
        }
        assert all(row["capability"]["id"] == "system.host.summary" and
                   row["provider"]["owner"] == "system" and row["outcome"] == "success" and
                   row["approval"]["result"] == "not_required" and
                   row["privilege"]["result"] == "not_required" for row in records)
        artifact = Path(os.environ.get("IGOR_VALIDATION_REPORT", str(tmp_path / "result.jsonl"))).parent
        (artifact / "system-operator-workflow.json").write_text(json.dumps({
            "frontend": "actual curses with outer/inner PTYs", "backend": "bash igor.sh --ai-tui-backend",
            "capability": "system.host.summary", "cli_operation": cli_result["operation_id"],
            "tui_operation": tui_result["operation_id"], "history": records,
        }, indent=2) + "\n")
    finally:
        if "transcript" in locals():
            artifact = Path(os.environ.get("IGOR_VALIDATION_REPORT", str(tmp_path / "result.jsonl"))).parent
            (artifact / "system-operator-terminal.bin").write_bytes(transcript)
            if stream.exists():
                (artifact / "system-operator-events.jsonl").write_bytes(stream.read_bytes())
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=10)
        if master is not None:
            os.close(master)
        fixture.doCleanups()
