"""Canonical frontend publication bounds and selected-secret protection."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("delta", [0, 1])
def test_frontend_utf8_exact_event_boundary(tmp_path, delta):
    stream = tmp_path / "events"
    script = r'''source "$1/core/ai/events.sh"
payload="$(cat)"
_ai_event_emit action_result "$payload"
'''
    # First learn the actual envelope's fixed-width sequence/time framing.
    env = dict(os.environ, IGOR_AI_EVENT_STREAM=str(stream), IGOR_DIR=str(tmp_path))
    seed = {"session_id": "fixture", "result": {"padding": ""}}
    initial = subprocess.run(["bash", "-c", script, "_", str(ROOT)], input=json.dumps(seed),
                             text=True, capture_output=True, env=env, check=True)
    assert not initial.stdout and not initial.stderr
    event = json.loads(stream.read_text())
    size = len(json.dumps(event, ensure_ascii=False, separators=(",", ":")).encode())
    remaining = 98304 + delta - size
    seed["result"]["padding"] = "😀" * (remaining // 4) + "x" * (remaining % 4)
    stream.unlink()
    Path(str(stream) + ".seq").unlink()
    result = subprocess.run(["bash", "-c", script, "_", str(ROOT)], input=json.dumps(seed, ensure_ascii=False),
                            text=True, capture_output=True, env=env, check=False)
    if delta:
        assert result.returncode == 2
        assert result.stderr.strip() == "collection_limit_exceeded"
        assert not stream.read_bytes()
    else:
        assert result.returncode == 0, result.stderr
        wire = stream.read_bytes().rstrip(b"\n")
        assert len(wire) == 98304
        assert json.loads(wire)["result"] == seed["result"]


def test_selected_secret_redacted_before_event_publication(tmp_path):
    stream = tmp_path / "events"
    sys.path.insert(0, str(ROOT / "core/lib"))
    from secret_refs import ManagedOpenRouterSecret
    service = ManagedOpenRouterSecret(tmp_path / "secrets", tmp_path / "data")
    service.stage(b"PRIVATE_SENTINEL", source_kind="private_input", expected_revision=0)
    env = dict(os.environ, IGOR_AI_EVENT_STREAM=str(stream), IGOR_DIR=str(tmp_path),
               IGOR_DATA_DIR=str(tmp_path / "data"), IGOR_SECRETS_DIR=str(tmp_path / "secrets"))
    result = subprocess.run(["bash", "-c", 'source "$1/core/ai/events.sh"; _ai_event_emit action_result "$(cat)"',
                             "_", str(ROOT)], input=json.dumps({"result": {"unit": "PRIVATE_SENTINEL.service"}}),
                            text=True, capture_output=True, env=env, check=False)
    assert result.returncode == 0
    assert "PRIVATE_SENTINEL" not in stream.read_text() + result.stdout + result.stderr


def test_handler_deadline_kills_term_ignoring_fixture(tmp_path):
    (tmp_path / "module.sh").write_text(
        'fixture__run() { trap "" TERM; sleep 10; }\n')
    result = subprocess.run([sys.executable, str(ROOT / "core/lib/module_handler.py"),
                             str(tmp_path), "fixture", "fixture__run", "fixture.run", "1"],
                            input=b"{}", capture_output=True, check=False, timeout=3)
    assert result.returncode == 124
    assert not result.stdout
    assert result.stderr.strip() == b"module handler: handler timed out"
