"""Boundary 1 owning-service CLI and generic 15UI inspection proof."""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
sys.path.insert(0, str(ROOT / "core/ai"))


def cli(data, action, *arguments):
    return subprocess.run(
        ["bash", str(ROOT / "igor.sh"), "--deployments", action, *arguments],
        env={**os.environ, "IGOR_DATA_DIR": str(data)}, capture_output=True,
        text=True, timeout=10, check=False,
    )


def inventory(data):
    return {str(path.relative_to(data)): path.read_bytes()
            for path in data.rglob("*") if path.is_file()}


def test_absent_cli_reads_do_not_create_store_or_installation_identity(tmp_path):
    data = tmp_path / "absent"
    for action in ("status", "list", "export"):
        result = cli(data, action)
        assert result.returncode == 0, result.stderr
        json.loads(result.stdout)
        assert not data.exists()
    result = cli(data, "inspect", "deployment:" + "0" * 32)
    assert result.returncode != 0
    assert not data.exists()


def test_public_cli_rejects_mutation_and_invalid_arguments_before_storage(tmp_path):
    data = tmp_path / "absent"
    for action in ("initialize", "prepare", "commit", "restore", "adopt", "attach",
                   "grant", "release", "detach", "destroy", "execute", "refresh"):
        result = cli(data, action)
        assert result.returncode != 0, action
    for action, arguments in (("inspect", ()), ("status", ("unexpected",)),
                              ("list", ("unexpected",)),
                              ("status", ("unexpected", "extra"))):
        assert cli(data, action, *arguments).returncode != 0
    assert not data.exists()


def test_real_registry_cli_and_15ui_preserve_authority_and_storage(tmp_path):
    import tui
    from deployments import DeploymentService
    from operational_history import OperationalHistory

    data = tmp_path / "data"
    service = DeploymentService(data, authorize=lambda request: True)
    source = {"kind": "operator", "id": "fixture.console", "owner": "core"}
    service.initialize(source=source)
    scope = OperationalHistory(data).status()["scope_id"]
    # Other authorities' opaque state must not be inspected or rewritten by the
    # metadata service. No observer/configuration/History execution is invoked.
    (data / "runtime").mkdir()
    (data / "runtime/model.json").write_text('{"observed":"opaque fixture"}')
    (data / "desired.fixture").write_text("another authority's desired state")
    proposal = service.prepare([
        {"action": "create_deployment", "key": "app", "label": "Fixture application",
         "application": "fixture.app", "providers": [
             {"id": "fixture.provider", "owner": "fixture", "version": 1}]},
        {"action": "enroll_resource", "key": "storage", "kind": "storage",
         "label": "External storage", "origin": "external", "native": {
             "provider": "fixture.provider", "provider_scope": "host-local",
             "native_id": "fixture-native", "incarnation": "one"}},
        {"action": "add_relationship", "deployment": "$app", "kind": "includes",
         "subject": "$app", "target": "$storage", "role": "storage", "evidence": []},
    ], source=source)
    before_prepare_commit = inventory(data)
    assert proposal["scope_id"] == scope
    service.commit(proposal, operation_id="op-" + "a" * 32)
    deployment = proposal["changes"][0]["reference"]
    resource = proposal["changes"][1]["reference"]
    unowned = service.inspect(deployment)
    assert unowned["management"]["status"] == "no_responsibility"
    assert unowned["responsibilities"] == []
    assert unowned["resources"][0]["origin"] == "external"
    grant = service.prepare([{
        "action": "grant_responsibility", "deployment": deployment, "subject": resource,
        "duty": "configuration", "setting_id": "fixture.setting",
        "providers": ["fixture.provider"],
    }], source=source)
    service.commit(grant, operation_id="op-" + "b" * 32)
    row = service.inspect(deployment)
    assert row["management"]["execution_authority"] == "separate"
    for joined in ("configuration", "observations", "history"):
        assert row[joined]["availability"] == "not_supplied"
    assert row["verification"]["status"] == "not_verified"
    assert row["detach"]["status"] == "not_certified"
    before_reads = inventory(data)
    for action in ("status", "list", "export"):
        result = cli(data, action)
        assert result.returncode == 0, result.stderr + result.stdout
        json.loads(result.stdout)
    result = cli(data, "inspect", deployment["object_id"])
    assert result.returncode == 0, result.stderr + result.stdout
    assert json.loads(result.stdout) == row
    rendered = " ".join(tui.panel_rows({
        "source": "--deployments inspect", "data": json.loads(result.stdout),
    }))
    for text in ("Fixture application", deployment["object_id"], resource["object_id"],
                 "relationships", "configuration", "responsibilities", "external",
                 "fixture.setting", "not_supplied", "not_certified", "fixture.console"):
        assert text in rendered
    assert inventory(data) == before_reads
    assert (data / "runtime/model.json").read_bytes() == before_prepare_commit["runtime/model.json"]
    assert (data / "desired.fixture").read_bytes() == before_prepare_commit["desired.fixture"]
    assert OperationalHistory(data).recent() == []
    assert OperationalHistory(data).status()["scope_id"] == deployment["scope_id"]

    # A later unrelated environment secret must not invalidate persisted
    # structural metadata or turn an ordinary read into a corrupt-store error.
    environment = {**os.environ, "IGOR_DATA_DIR": str(data),
                   "FIXTURE_SECRET": "Fixture application"}
    result = subprocess.run(
        ["bash", str(ROOT / "igor.sh"), "--deployments", "inspect", deployment["object_id"]],
        env=environment, capture_output=True, text=True, timeout=10, check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert json.loads(result.stdout)["identity"]["reference"] == deployment
    assert inventory(data) == before_reads
