"""M1 shared Python handler boundary, using only private disposable fixtures."""

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))

from module_handler import REQUEST_BYTES, HandlerError, invoke


def package(tmp_path, body):
    (tmp_path / "module.sh").write_text("fixture__run() {\n" + body + "\n}\n")
    return tmp_path


def call(path, inputs=b"{}", **kwargs):
    return invoke(path, "fixture", "fixture__run", "fixture.run", 3, inputs, **kwargs)


def test_request_is_canonical_and_independent_of_cwd(tmp_path, monkeypatch):
    package(tmp_path, '''IFS= read -r request
printf '{"status":"ok","result":%s}' "$request"''')
    monkeypatch.chdir("/")
    result = json.loads(call(tmp_path, b'{ "number" : 42 }'))
    assert result["result"] == {"api_version": 2, "contribution_id": "fixture.run",
                                "input": {"number": 42}}


@pytest.mark.parametrize("inputs", [b"[]", b"null", b"{", b'{"a":1,"a":2}',
                                   b'{"n":NaN}', b'{"n":1e999}', b"\xff",
                                   b" " * (REQUEST_BYTES + 1)])
def test_bad_input_never_sources_package(tmp_path, inputs):
    marker = tmp_path / "called"
    (tmp_path / "module.sh").write_text(f"touch '{marker}'\nfixture__run() {{ :; }}\n")
    with pytest.raises(HandlerError):
        call(tmp_path, inputs)
    assert not marker.exists()


def test_invalid_source_never_executes_its_prefix(tmp_path):
    marker = tmp_path / "called"
    (tmp_path / "module.sh").write_text(f"touch '{marker}'\nfixture__run() {{\n")
    with pytest.raises(HandlerError):
        call(tmp_path)
    assert not marker.exists()


@pytest.mark.parametrize("entrypoint", ["../outside.sh", "/outside.sh", "escape.sh"])
def test_entrypoint_containment(tmp_path, entrypoint):
    package(tmp_path, ":")
    (tmp_path / "escape.sh").symlink_to("/bin/true")
    with pytest.raises(HandlerError, match="escapes module package"):
        call(tmp_path, entrypoint=entrypoint)


def test_shell_startup_and_exported_functions_cannot_inject(tmp_path):
    marker = tmp_path / "injected"
    startup = tmp_path / "startup.sh"
    startup.write_text(f"touch '{marker}'\n")
    package(tmp_path, "printf '%s' '{\"status\":\"ok\",\"result\":{}}'")
    env = dict(os.environ, BASH_ENV=str(startup), ENV=str(startup))
    env["BASH_FUNC_fixture__run%%"] = f"() {{ touch '{marker}'; }}"
    assert json.loads(call(tmp_path, env=env))["status"] == "ok"
    assert not marker.exists()


@pytest.mark.parametrize("response", [
    "not-json", '{"status":"ok","result":{},"tier":"READ"}',
    '{"status":"ok","status":"error","result":{}}',
    '{"status":"error","error":{"code":"secret","message":"PRIVATE_SENTINEL"}}',
])
def test_invalid_response_and_provider_errors_do_not_leak(tmp_path, response):
    package(tmp_path, f"printf '%s' '{response}'")
    with pytest.raises(HandlerError) as error:
        call(tmp_path)
    assert "PRIVATE_SENTINEL" not in str(error.value)


def test_deferred_validation_preserves_typed_output_classification(tmp_path):
    package(tmp_path, "printf '%s' 'invalid typed response'")
    assert call(tmp_path, defer_response_validation=True) == b"invalid typed response"


@pytest.mark.parametrize("stream", ["stdout", "stderr"])
def test_all_handler_streams_are_bounded_without_leaking(tmp_path, stream):
    package(tmp_path, f'''"$IGOR_PYTHON" -c 'import sys; sys.{stream}.write("PRIVATE_SENTINEL" * 100000)' ''')
    with pytest.raises(HandlerError, match="limit exceeded") as error:
        call(tmp_path)
    assert "PRIVATE_SENTINEL" not in str(error.value)


def _running(pid):
    try:
        state = Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()[0]
    except FileNotFoundError:
        return False
    return state != "Z"


def test_success_cleans_up_background_descendants(tmp_path):
    pidfile = tmp_path / "child"
    package(tmp_path, f'''sleep 30 </dev/null >/dev/null 2>&1 &
printf '%s' "$!" > '{pidfile}'
printf '%s' '{{"status":"ok","result":{{}}}}' ''')
    assert json.loads(call(tmp_path))["status"] == "ok"
    pid = int(pidfile.read_text())
    deadline = time.monotonic() + 1
    while _running(pid) and time.monotonic() < deadline:
        time.sleep(0.01)
    assert not _running(pid)


def test_cancellation_kills_term_ignoring_descendant(tmp_path):
    pidfile = tmp_path / "child"
    package(tmp_path, f'''trap "" TERM
sleep 30 &
printf '%s' "$!" > '{pidfile}'
wait''')
    process = subprocess.Popen(
        [sys.executable, str(ROOT / "core/lib/module_handler.py"), str(tmp_path),
         "fixture", "fixture__run", "fixture.run", "10"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    pid = None
    try:
        process.stdin.write(b"{}")
        process.stdin.close()
        process.stdin = None
        deadline = time.monotonic() + 3
        while not pidfile.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert pidfile.exists(), "fixture did not start"
        pid = int(pidfile.read_text())
        process.send_signal(signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=3)
        assert process.returncode != 0
        assert not stdout and b"handler cancelled" in stderr
        deadline = time.monotonic() + 1
        while _running(pid) and time.monotonic() < deadline:
            time.sleep(0.01)
        assert not _running(pid)
    finally:
        if process.poll() is None:
            process.kill()
        process.communicate()
        if pid is not None and _running(pid):
            os.kill(pid, signal.SIGKILL)
