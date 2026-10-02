"""Boundary 2 Core attachment tests; the provider fixture has read-only transport."""
from __future__ import annotations

import copy
import json
import sys
import uuid
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "core/lib"), str(ROOT / "modules/nextcloud_docker/lib")]

from attachment import NextcloudAttachmentProvider
from deployment_attachment import (
    AttachmentError,
    DeploymentAttachment,
    capability_records,
)
from deployments import DeploymentService
from operational_history import OperationalHistory


def container(cid: str, *, name="nc-app", project="nc", created="2025-01-02T03:04:05Z"):
    return {"Id": cid, "Name": "/" + name, "Created": created,
            "Config": {"Image": "nextcloud:apache", "Labels": {
                "com.docker.compose.project": project, "com.docker.compose.service": "app"}},
            "Image": "sha256:" + "a" * 64,
            "Mounts": [
                {"Type": "volume", "Name": "nc-html", "Source": "/var/lib/docker/volumes/nc-html/_data",
                 "Destination": "/var/www/html"},
                {"Type": "volume", "Name": "nc-data", "Source": "/var/lib/docker/volumes/nc-data/_data",
                 "Destination": "/var/www/html/data"}]}


class FixtureDocker:
    def __init__(self, rows):
        self.rows = {row["Id"]: copy.deepcopy(row) for row in rows}
        self.calls = []

    def info(self):
        self.calls.append("info")
        return {"ID": "daemon-fixture"}

    def containers(self):
        self.calls.append("ps")
        return [{"ID": cid, "Names": row["Name"].lstrip("/"), "Image": row["Config"]["Image"]}
                for cid, row in self.rows.items()]

    def inspect(self, container_id):
        self.calls.append(("inspect", container_id))
        return copy.deepcopy(self.rows[container_id])

    def configuration_stat(self, container_id, path):
        self.calls.append(("stat", container_id, path))
        return {"type": "regular file", "inode": 12345, "size": 4096, "mtime": 1735787045}


def fixture(tmp_path, rows=None, *, enabled=True):
    data = tmp_path / "data"
    service = DeploymentService(data, authorize=lambda _request: True)
    service.initialize(source={"kind": "operator", "id": "fixture.console", "owner": "core"})
    cid = f"{1:064x}"
    docker = FixtureDocker([container(cid)] if rows is None else rows)
    provider = NextcloudAttachmentProvider(docker, active=enabled)
    coordinator = DeploymentAttachment(service, provider, provider_module_version="1.0.0")
    return data, service, docker, provider, coordinator, cid


def admit_approved_history(data: Path, ident: str, proposal_text: str, capability: str,
                           approval_result="approved") -> str:
    history = OperationalHistory(data)
    proposal = {"capability_id": capability, "capability_version": 1,
                "provider": "core", "owner": "core", "inputs": {"proposal": proposal_text},
                "affected_objects": ["installation:local"], "safety": {"tier": "CHANGE"},
                "privilege": "none", "verification": {"kind": "deployment_metadata_revision", "required": True},
                "recovery": {"class": "reversible"}, "precondition_status": "satisfied"}
    episode = history.prepare(proposal, correlation_id="corr-" + uuid.uuid4().hex,
                              provenance={"actor": "operator", "interface": "fixture", "request_id": None},
                              approval_requirement="change_confirm")
    history.authority(episode["operation_id"], approval_result, "not_required")
    history.running(episode["operation_id"], proposal)
    return episode["operation_id"]


def test_discovery_is_exact_and_proposal_freezes_topology_without_writing_target(tmp_path):
    _data, service, docker, _provider, coordinator, cid = fixture(tmp_path)
    before = copy.deepcopy(docker.rows)
    assert coordinator.discover()["candidates"][0]["container_id"] == cid
    proposal = coordinator.propose(cid)
    assert proposal["inspection"]["native"]["native_id"] == cid
    assert proposal["inspection"]["configuration_target"]["source"].endswith("nc-html/_data")
    assert proposal["contract"]["configuration_target"]["availability"] == "verified_regular_file"
    assert proposal["responsibility"] == {"duty": "configuration", "setting_id": "nextcloud_docker.loglevel",
                                           "supports": ["change", "readback", "recovery"]}
    assert service.status()["revision"] == 0
    assert docker.rows == before
    assert all(call in {"info", "ps"} or call[0] in {"inspect", "stat"} for call in docker.calls)


def test_zero_and_ambiguous_candidates_never_select_first(tmp_path):
    _data, _service, _docker, provider, coordinator, _cid = fixture(tmp_path, rows=[])
    assert coordinator.discover()["candidates"] == []
    with pytest.raises(ValueError, match="no matching"):
        provider.select([])
    ids = [f"{i:064x}" for i in (1, 2)]
    rows = [container(ids[0], name="same"), container(ids[1], name="same", project="other")]
    provider = NextcloudAttachmentProvider(FixtureDocker(rows))
    with pytest.raises(ValueError, match="multiple"):
        provider.select(provider.discover())
    assert provider.select(provider.discover(), locator=ids[1])["container_id"] == ids[1]


def test_adoption_requires_running_explicit_history_and_preserves_native_binding(tmp_path):
    data, service, docker, _provider, coordinator, cid = fixture(tmp_path)
    proposal = coordinator.propose(cid)
    text = json.dumps(proposal, sort_keys=True, separators=(",", ":"))
    operation_id = admit_approved_history(data, "adopt", text, "core.deployments.adopt")
    episode = OperationalHistory(data).inspect(operation_id)
    assert episode["lifecycle"] == "running"
    assert episode["approval"]["result"] == "approved"
    assert episode["inputs"] == {"proposal": json.loads(text),
                                 "proposal_sha256": __import__("hashlib").sha256(text.encode()).hexdigest()}
    result = coordinator.adopt(text, operation_id)
    deployment = result["deployment"]
    assert result["application_mutation"] == "none"
    assert deployment["identity"]["application"] == "nextcloud"
    assert deployment["identity"]["lifecycle"] == "known"
    assert {row["kind"] for row in deployment["resources"]} == {"service", "configuration_target", "storage"}
    assert any(row["native"] and row["native"]["native_id"] == cid for row in deployment["resources"])
    assert len(deployment["relationships"]) >= 6
    assert [(row["duty"], row["setting_id"]) for row in deployment["responsibilities"]] == [
        ("configuration", "nextcloud_docker.loglevel")]
    assert docker.rows == {cid: container(cid)}
    assert service.inspect(deployment["identity"]["reference"])["identity"] == deployment["identity"]
    sys.path.insert(0, str(ROOT / "core/ai"))
    import tui

    rendered = " ".join(tui.panel_rows({"source": "--deployments inspect", "data": deployment}))
    for field in ("relationships", "responsibilities", "observations", "history", "nextcloud_docker.loglevel"):
        assert field in rendered


def test_auto_approval_and_tampered_proposal_are_rejected(tmp_path):
    data, _service, _docker, _provider, coordinator, cid = fixture(tmp_path)
    proposal = coordinator.propose(cid)
    text = json.dumps(proposal, sort_keys=True, separators=(",", ":"))
    op = admit_approved_history(data, "auto", text, "core.deployments.adopt", "auto_approved")
    with pytest.raises(AttachmentError, match="explicit approved History"):
        coordinator.adopt(text, op)
    tampered = copy.deepcopy(proposal)
    relation = next(row for row in tampered["deployment_proposal"]["changes"]
                    if row["action"] == "add_relationship")
    relation["target"] = {"scope_id": tampered["expected_state"][:32], "object_id": "resource:" + "f" * 32}
    tampered_text = json.dumps(tampered, sort_keys=True, separators=(",", ":"))
    with pytest.raises(AttachmentError, match="stale"):
        coordinator.preflight(tampered_text)


def test_stale_candidate_and_registry_revision_invalidate_proposal(tmp_path):
    _data, service, docker, _provider, coordinator, cid = fixture(tmp_path)
    proposal = coordinator.propose(cid)
    frozen = json.dumps(proposal, sort_keys=True, separators=(",", ":"))
    docker.rows[cid]["Created"] = "2026-01-01T00:00:00Z"
    with pytest.raises(AttachmentError, match="incarnation changed|stale"):
        coordinator.preflight(frozen)
    docker.rows[cid]["Created"] = proposal["inspection"]["candidate"]["created"]
    unrelated = service.prepare([{"action": "create_deployment", "label": "Concurrent", "application": "fixture.app",
                                  "providers": [{"id": "fixture.provider", "owner": "fixture", "version": 1}]}],
                                source={"kind": "operator", "id": "fixture.concurrent", "owner": "core"})
    service.commit(unrelated, operation_id="op-" + "e" * 32)
    with pytest.raises(AttachmentError, match="stale"):
        coordinator.preflight(frozen)


def test_disabled_provider_does_not_erase_binding_and_release_is_metadata_only(tmp_path):
    data, service, docker, _provider, coordinator, cid = fixture(tmp_path)
    adoption = coordinator.propose(cid)
    adoption_text = json.dumps(adoption, sort_keys=True, separators=(",", ":"))
    op = admit_approved_history(data, "adopt", adoption_text, "core.deployments.adopt")
    result = coordinator.adopt(adoption_text, op)
    deployment_id = result["deployment"]["identity"]["reference"]["object_id"]
    disabled = NextcloudAttachmentProvider(docker, active=False)
    with pytest.raises(ValueError, match="disabled|unavailable"):
        disabled.discover()
    assert service.inspect(deployment_id)["identity"]["lifecycle"] == "known"
    release_coordinator = DeploymentAttachment(service, None)
    release = release_coordinator.propose_release(deployment_id)
    release_text = json.dumps(release, sort_keys=True, separators=(",", ":"))
    release_op = admit_approved_history(data, "release", release_text, "core.deployments.release")
    released = release_coordinator.release(release_text, release_op)
    assert released["detach"]["status"] == "not_certified"
    assert released["application_mutation"] == "none"
    assert released["deployment"]["identity"]["lifecycle"] == "known"
    assert not any(row["lifecycle"] == "active" for row in released["deployment"]["responsibilities"])
    assert cid in docker.rows
    assert not any(row["lifecycle"] == "retired" for row in released["deployment"]["relationships"])


def test_core_capabilities_disable_provider_dependent_operations_only():
    enabled = {row["id"]: row["availability"] for row in capability_records(True)}
    disabled = {row["id"]: row["availability"] for row in capability_records(False)}
    assert enabled["core.deployments.adopt"] == "active"
    assert disabled["core.deployments.adopt"] == "inactive"
    assert disabled["core.deployments.discover"] == "inactive"
    assert disabled["core.deployments.propose"] == "inactive"
    assert disabled["core.deployments.release"] == "active"
    assert disabled["core.deployments.initialize"] == "active"


def test_independent_verifier_rejects_metadata_changed_after_adoption(tmp_path):
    from deployment_attachment import verify_result

    data, service, _docker, provider, coordinator, cid = fixture(tmp_path)
    proposal = coordinator.propose(cid)
    document = json.dumps(proposal, sort_keys=True, separators=(",", ":"))
    op = admit_approved_history(data, "verify", document, "core.deployments.adopt")
    result = coordinator.adopt(document, op)
    assert verify_result(document, result, service, provider)["status"] == "verified"
    grant = result["deployment"]["responsibilities"][0]
    release = service.prepare([{"action": "release_responsibility", "reference": grant["reference"],
                                "disposition": "retained_external"}],
                              source={"kind": "operator", "id": "fixture.release", "owner": "core"})
    service.commit(release, operation_id="op-" + uuid.uuid4().hex)
    with pytest.raises(AttachmentError, match="verification failed"):
        verify_result(document, result, service, provider)
    with pytest.raises(AttachmentError, match="stale|already has an Igor identity"):
        coordinator.preflight(document)
