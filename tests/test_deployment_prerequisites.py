"""Independent Configuration/observation admission without desired/app writes."""
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
from configuration import ConfigurationError, ConfigurationService
from deployments import DeploymentService
from system_model import ModelError, SystemModel

SOURCE = {"kind": "operator", "id": "fixture.console", "owner": "core"}
SETTING = "fixture.loglevel"


def bound(data):
    service = DeploymentService(data, authorize=lambda request: True)
    service.initialize(source=SOURCE)
    proposal = service.prepare([
        {"action": "create_deployment", "key": "app", "label": "Existing app", "application": "fixture.app",
         "providers": [{"id": "fixture.provider", "owner": "fixture", "version": 1}]},
        {"action": "enroll_resource", "key": "target", "kind": "configuration_target", "label": "Exact config selector",
         "origin": "external", "native": {"provider": "fixture.provider", "provider_scope": "daemon-one",
                                           "native_id": "volume-one/config.php", "incarnation": None}},
        {"action": "add_relationship", "deployment": "$app", "kind": "includes", "subject": "$app",
         "target": "$target", "role": "configuration", "evidence": []},
        {"action": "grant_responsibility", "deployment": "$app", "subject": "$target", "duty": "configuration",
         "setting_id": SETTING, "providers": ["fixture.provider"]},
    ], source=SOURCE)
    service.commit(proposal, operation_id="op-" + "a" * 32)
    return service, proposal["changes"][0]["reference"], proposal["changes"][1]["reference"]


def test_target_admission_uses_deployment_authority_without_config_or_observation(tmp_path):
    deployment, ref, resource = bound(tmp_path)
    configuration = ConfigurationService(tmp_path)
    before = deployment.export_document()
    status = deployment.status()
    target = configuration.validate_deployment_target(
        ref["scope_id"], ref["object_id"], SETTING, deployment_service=deployment,
        provider_available=lambda provider: provider == "fixture.provider",
        expected_revision=status["revision"], expected_state=status["state_token"])
    assert target["reference"] == {"scope_id": ref["scope_id"], "deployment_id": ref["object_id"], "setting_id": SETTING}
    assert target["binding"]["resource"]["reference"] == resource
    assert target["desired_value"] == "not_created"
    assert target["writer"] == "not_registered"
    assert not configuration.path.exists()
    assert deployment.export_document() == before
    assert SystemModel().list_facts() == []
    with pytest.raises(ConfigurationError, match="setting schema unavailable"):
        configuration.validate([{"id": SETTING, "target": ref["object_id"], "value": 2}])


def test_target_checks_provider_scope_revision_and_release(tmp_path):
    deployment, ref, _ = bound(tmp_path)
    configuration = ConfigurationService(tmp_path)
    def validate(**kwargs):
        return configuration.validate_deployment_target(
            ref["scope_id"], ref["object_id"], SETTING, deployment_service=deployment,
            provider_available=kwargs.pop("provider_available", lambda provider: True), **kwargs)
    with pytest.raises(ConfigurationError, match="provider unavailable"):
        validate(provider_available=lambda provider: False)
    assert deployment.inspect(ref)["responsibilities"][0]["lifecycle"] == "active"
    with pytest.raises(ConfigurationError, match="revision conflict"):
        validate(expected_revision=0)
    with pytest.raises(ConfigurationError, match="state conflict"):
        validate(expected_state="0" * 64)
    with pytest.raises(ConfigurationError, match="scope mismatch"):
        configuration.validate_deployment_target("scope:" + "0" * 32, ref["object_id"], SETTING,
            deployment_service=deployment, provider_available=lambda provider: True)
    grant = deployment.inspect(ref)["responsibilities"][0]
    proposal = deployment.prepare([{"action": "release_responsibility", "reference": grant["reference"],
                                    "disposition": "retained_external"}], source=SOURCE)
    deployment.commit(proposal, operation_id="op-" + "b" * 32)
    with pytest.raises(ConfigurationError, match="responsibility missing"):
        validate()
    assert not configuration.path.exists()


def test_resource_observer_facts_have_independent_provenance_and_freshness(tmp_path):
    deployment, ref, resource = bound(tmp_path)
    before = deployment.export_document()
    model = SystemModel()
    descriptor = {"object_kind": "resource", "object_id": resource["object_id"], "freshness_seconds": 30,
                  "properties": [{"name": "native.present", "value_type": "boolean"}]}
    at = datetime(2026, 1, 1, tzinfo=timezone.utc)
    envelope = {"status": "ok", "result": {"object_id": resource["object_id"],
        "facts": [{"property": "native.present", "value": True, "evidence": ["independent docker inspect"]}], "unavailable": []}}
    model.observe(descriptor, "fixture", "fixture.native", envelope, at=at)
    joined = DeploymentService(tmp_path, system_model=model, active_owners={"fixture"}).inspect(ref)
    assert joined["observations"]["source"] == "system_model"
    assert joined["observations"]["facts"][0]["object_id"] == resource["object_id"]
    fact = model.read(resource["object_id"], "native.present", "observed", at=at)
    assert fact["availability"] == "known"
    assert fact["provenance"]["kind"] == "observer"
    assert model.read(resource["object_id"], "native.present", "observed", at=at + timedelta(seconds=31))["availability"] == "stale"
    assert model.read(resource["object_id"], "native.present", "observed", active_owners=set(), at=at)["availability"] == "inactive"
    model.observer_failure(descriptor, "fixture", "fixture.native", "native_missing", at=at)
    assert model.read(resource["object_id"], "native.present", "observed", at=at)["availability"] == "stale"
    assert deployment.export_document() == before
    assert deployment.inspect(ref)["management"]["status"] == "responsibility_accepted"
    envelope["result"]["object_id"] = ref["object_id"]
    with pytest.raises(ModelError, match="undeclared observer target"):
        model.observe(descriptor, "fixture", "fixture.native", envelope)
    with pytest.raises(ModelError, match="unsupported observer target"):
        model.observer_failure({**descriptor, "object_id": "resource:guessed-name"}, "fixture", "fixture.native", "missing")
