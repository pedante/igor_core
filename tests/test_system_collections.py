"""Controlled System producer through the canonical long-lived CLI backend."""

import json
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def backend(tmp_path):
    root = tmp_path / "installation"
    (root / "modules").mkdir(parents=True)
    shutil.copytree(ROOT / "modules/system", root / "modules/system")
    (root / "config").mkdir()
    (root / "config/modules.conf").write_text("system=enabled\n")
    (root / "data/runtime").mkdir(parents=True, mode=0o700)
    (root / "bin").mkdir()
    source = root / "inventory"
    source.write_text("".join(f"unit{i:04}.service loaded inactive dead Fixture\n" for i in range(51)))
    command = root / "bin/systemctl"
    command.write_text('#!/bin/sh\n[ "$1" = list-units ] || exit 2\ncat "$COLLECTION_SOURCE"\n')
    command.chmod(0o700)
    sys.path.insert(0, str(ROOT / "core/lib"))
    from secret_refs import ManagedOpenRouterSecret
    ManagedOpenRouterSecret(root / "secrets", root / "data").stage(
        b"PRIVATE_SENTINEL", source_kind="private_input", expected_revision=0)
    env = dict(os.environ, IGOR_DIR=str(root), IGOR_DATA_DIR=str(root / "data"),
               IGOR_RUNTIME_DIR=str(root / "data/runtime"), IGOR_PYTHON=sys.executable,
               IGOR_DISTRO_ID="debian", IGOR_DISTRO_FAMILY="debian", COLLECTION_SOURCE=str(source),
               OPENROUTER_API_KEY="PRIVATE_SENTINEL", PATH=str(root / "bin") + ":" + os.environ["PATH"])
    script = r'''source "$1/core/lib/module_loader.sh"
_ml_log() { :; }
igor_load_all_modules >/dev/null
source "$1/core/ai/events.sh"
printf 'READY\n'
while IFS= read -r request; do
    case "$request" in
        HISTORY) igor_history_cli recent 10 ;;
        INSPECT) "$IGOR_PYTHON" "$1/core/lib/collection_runtime.py" inspect ;;
        DISABLE) igor_module_set_enabled system disabled >/dev/null; printf '{}\n' ;;
        CLOSE) "$IGOR_PYTHON" "$1/core/lib/collection_runtime.py" release-session "$IGOR_CAPABILITY_RESULT_FILE"; break ;;
        *)
            proposal="$(igor_capability_prepare system.service.list "$request" system 3)" || exit 1
            IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
            IGOR_CAPABILITY_APPROVAL_STATUS=auto_approved
            igor_capability_execute "$proposal"
            ;;
    esac
done
'''
    errors = root / "backend-stderr"
    with errors.open("w") as stderr:
        process = subprocess.Popen(["bash", "-c", script, "_", str(ROOT)], env=env, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=stderr, text=True)
        try:
            assert process.stdout.readline().strip() == "READY"
            def request(value):
                process.stdin.write((json.dumps(value) if isinstance(value, dict) else value) + "\n")
                process.stdin.flush()
                line = process.stdout.readline()
                assert line, errors.read_text()
                return json.loads(line)
            yield request, source, errors, process, root
        finally:
            if process.poll() is None:
                process.stdin.write("CLOSE\n")
                process.stdin.flush()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
            process.wait()
            process.stdin.close()
            process.stdout.close()


def test_canonical_system_page_replay_refresh_history_and_disable(backend):
    request, source, errors, _, root = backend
    started = time.monotonic()
    first = request({})
    latency = time.monotonic() - started
    assert first["capability_version"] == 3 and first["outcome"] == "success"
    assert first["execution_status"] == "succeeded" and first["output_status"] == "valid"
    assert first["verification_status"] == "not_applicable"
    page = first["result"]
    assert page["resource_kind"] == "service" and page["inventory"] == "loaded_system_services"
    assert len(page["rows"]) == 50 and page["page"]["total_count"] == 51
    cursor = page["page"]["next_cursor"]
    source.write_text("changed.service loaded active running New\n")
    second = request({"cursor": cursor})
    replay = request({"cursor": cursor})
    assert second["result"] == replay["result"]
    assert second["operation_id"] != replay["operation_id"] != first["operation_id"]
    assert second["result"]["rows"][0]["unit"] == "unit0050.service"
    assert second["result"]["page"]["snapshot_revision"] == page["page"]["snapshot_revision"]
    history = request("HISTORY")
    assert cursor not in json.dumps(history)
    assert history[0]["inputs_redacted"] and "cursor_sha256" in history[0]["inputs"]
    fresh = request({})
    assert fresh["result"]["rows"][0]["unit"] == "changed.service"
    assert fresh["result"]["page"]["snapshot_revision"] != page["page"]["snapshot_revision"]
    stale = request({"cursor": cursor})
    assert stale["result"] is None and stale["outcome"] != "success"
    request("DISABLE")
    assert request("INSPECT")["snapshots"] == 0
    assert not errors.read_text(), errors.read_text()
    artifact = os.environ.get("IGOR_VALIDATION_REPORT")
    if artifact:
        (Path(artifact).parent / "system-collection-example.json").write_text(json.dumps(first, indent=2) + "\n")
        (Path(artifact).parent / "system-collection-latency.json").write_text(json.dumps({
            "first_page_seconds": latency, "environment": {"platform": platform.platform(), "machine": platform.machine()},
            "fixture": "51 controlled loaded units; canonical backend; no live service operations"}, indent=2) + "\n")
    assert not (root / "core").exists()  # A module-only fixture must use the loader's Core root.


@pytest.mark.parametrize("source_text,reason", [
    ("PRIVATE_SENTINEL.service loaded active running Fixture\n", None),
    ("a.service loaded active running " + "x" * 4096 + "\n", "collection_limit_exceeded"),
])
def test_canonical_rejected_producer_values_are_not_retained(backend, source_text, reason):
    request, source, errors, _, root = backend
    source.write_text(source_text)
    result = request({})
    assert result["outcome"] != "success" and result["result"] is None
    if reason:
        assert result["verification_evidence"][0]["reason"] == reason
    assert request("INSPECT")["snapshots"] == 0
    assert "PRIVATE_SENTINEL" not in json.dumps(result) + errors.read_text() + json.dumps(request("HISTORY"))
    for path in (root / "data").rglob("*"):
        if path.is_file():
            assert b"PRIVATE_SENTINEL" not in path.read_bytes()


def test_backend_termination_revokes_committed_snapshot(backend):
    request, _, _, process, root = backend
    result = request({})
    assert result["outcome"] == "success" and result["result"]["page"]["has_more"]
    process.terminate()
    process.wait(timeout=3)
    sys.path.insert(0, str(ROOT / "core/lib"))
    from collection_runtime import Snapshots
    assert Snapshots(root / "data/runtime").inspect()["snapshots"] == 0
