"""Boundary 1 proofs use metadata fixtures, never application/resource effects."""
import copy
import sqlite3
import sys
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
from deployments import DeploymentError, DeploymentService, decode, validate_record

SOURCE = {"kind": "operator", "id": "console", "owner": "core"}
RESTORE = {"kind": "restore", "id": "recovery", "owner": "core"}
PROVIDERS = [{"id": "fixture.provider", "owner": "fixture", "version": 1}]


def operation():
    return "op-" + uuid.uuid4().hex


def service_at(path, **kwargs):
    service = DeploymentService(path, authorize=lambda _request: True, **kwargs)
    service.initialize(source=SOURCE)
    return service


def resource(key="storage", *, kind="storage", native_id="external-resource"):
    return {"action": "enroll_resource", "key": key, "kind": kind, "label": "External " + kind,
            "origin": "external", "native": {"provider": "fixture.provider", "provider_scope": "host-local",
                                              "native_id": native_id, "incarnation": "first"}}


def deployment(key="app"):
    return {"action": "create_deployment", "key": key, "label": "Fixture application", "application": "fixture.app",
            "providers": copy.deepcopy(PROVIDERS)}


def includes(dep="$app", target="$storage", role="storage"):
    return {"action": "add_relationship", "deployment": dep, "kind": "includes", "subject": dep,
            "target": target, "role": role, "evidence": []}


def grant(dep, subject, *, duty="configuration", setting="fixture.setting"):
    return {"action": "grant_responsibility", "deployment": dep, "subject": subject, "duty": duty,
            "setting_id": setting, "providers": ["fixture.provider"]}


def change(service, changes, *, source=SOURCE):
    proposal = service.prepare(changes, source=source)
    return proposal, service.commit(proposal, operation_id=operation())


def topology(service, *, grants=False):
    changes = [deployment(), resource(), includes()]
    if grants:
        changes.append(grant("$app", "$storage"))
    proposal, result = change(service, changes)
    return proposal["changes"][0]["reference"], proposal["changes"][1]["reference"], result


def restore(service, document, *, op=None):
    status = service.status()
    return service.restore_document(document, expected_revision=status["revision"], expected_state=status["state_token"],
                                    operation_id=op or operation(), source=RESTORE)


def test_absent_reads_and_failed_preparation_never_initialize(tmp_path):
    service = DeploymentService(tmp_path)
    assert service.status()["availability"] == "not_created"
    assert service.status()["scope_id"] is None
    assert service.list() == []
    assert service.export_document()["records"] == []
    with pytest.raises(DeploymentError, match="not initialized"):
        service.prepare([deployment()], source=SOURCE)
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize("authorize", [None, lambda _request: False, lambda _request: 1, lambda _request: {"approved": True}])
def test_initialization_requires_literal_true_core_authorization(tmp_path, authorize):
    service = DeploymentService(tmp_path, authorize=authorize)
    with pytest.raises(DeploymentError, match="trusted Core"):
        service.initialize(source=SOURCE)
    assert list(tmp_path.iterdir()) == []


def test_preparation_has_no_effects_and_commit_is_atomic_explicit_metadata(tmp_path):
    service = service_at(tmp_path)
    before = service.export_document()
    proposal = service.prepare([deployment(), resource(), includes()], source=SOURCE)
    assert service.export_document() == before
    result = service.commit(proposal, operation_id=operation())
    assert result["metadata_only"] is True
    state = service.inspect(proposal["changes"][0]["reference"])
    assert state["management"]["status"] == "no_responsibility"
    assert state["responsibilities"] == []
    assert state["verification"]["status"] == "not_verified"
    assert state["observations"]["availability"] == "not_supplied"
    assert state["configuration"]["availability"] == "not_supplied"
    assert state["history"]["availability"] == "not_supplied"
    assert state["detach"]["status"] == "not_certified"
    assert state["resources"][0]["origin"] == "external"
    assert state["resources"][0]["identity_owner"] == "core.deployments"
    assert service.history.status()["episodes"] == 0
    assert service.status()["revision"] == 1
    assert service.directory.stat().st_mode & 0o777 == 0o700
    assert service.path.stat().st_mode & 0o777 == 0o600


def test_stable_identity_survives_rename_reopen_and_explicit_incarnation_rebind(tmp_path):
    service = service_at(tmp_path)
    dep, res, _ = topology(service)
    native = {**service.inspect(res)["native"], "native_id": "relocated", "incarnation": "second"}
    change(service, [{"action": "rename_deployment", "reference": dep, "label": "Renamed"},
                     {"action": "rebind_resource", "reference": res, "native": native}])
    reopened = DeploymentService(tmp_path)
    state = reopened.inspect(dep["object_id"])
    assert state["identity"]["reference"] == dep
    assert state["identity"]["label"] == "Renamed"
    assert state["resources"][0]["reference"] == res
    assert state["resources"][0]["native"]["incarnation"] == "second"
    assert state["verification"]["status"] == "not_verified"
    assert reopened.status()["scope_id"] == reopened.history.status()["scope_id"]


def test_existing_service_reference_is_reused_and_owner_retained(tmp_path):
    registered = {}
    service = service_at(tmp_path, reference_resolver=lambda ref: registered.get((ref["scope_id"], ref["object_id"])))
    exact = {"scope_id": service.status()["scope_id"], "object_id": "service:external-alpha"}
    registered[(exact["scope_id"], exact["object_id"])] = "system.model"
    enrollment = {**resource(), "reference": exact}
    proposal, _ = change(service, [deployment(), enrollment, includes()])
    state = service.inspect(proposal["changes"][0]["reference"])
    assert state["resources"][0]["reference"] == exact
    assert state["resources"][0]["identity_owner"] == "system.model"
    assert state["resources"][0]["record_owner"] == "core.deployments"
    with pytest.raises(DeploymentError):
        service.prepare([{**resource(), "reference": {**exact, "object_id": "service:missing"}}], source=SOURCE)


def test_registered_reference_owner_is_revalidated_before_commit(tmp_path):
    owner = ["system.model"]
    service = service_at(tmp_path, reference_resolver=lambda _ref: owner[0])
    reference = {"scope_id": service.status()["scope_id"], "object_id": "service:known"}
    proposal = service.prepare([{**resource(), "reference": reference}], source=SOURCE)
    before = service.export_document()
    owner[0] = "another.owner"
    with pytest.raises(DeploymentError, match="owner changed"):
        service.commit(proposal, operation_id=operation())
    assert service.export_document() == before


def test_native_names_are_qualified_by_igor_scope_and_owned_ids_remain_local(tmp_path):
    service = service_at(tmp_path, reference_resolver=lambda _ref: "system.model")
    refs = [{"scope_id": "scope:" + char * 32, "object_id": "service:identical-native"} for char in ("a", "b")]
    change(service, [{**resource("first"), "reference": refs[0]}, {**resource("second"), "reference": refs[1]}])
    assert service.inspect(refs[0])["native"] == service.inspect(refs[1])["native"]
    proposal = service.prepare([resource("owned", native_id="owned-native")], source=SOURCE)
    proposal["changes"][0]["reference"]["scope_id"] = refs[0]["scope_id"]
    before = service.export_document()
    with pytest.raises(DeploymentError, match="local scope"):
        service.commit(proposal, operation_id=operation())
    assert service.export_document() == before


def test_provenance_never_authorizes_mutation_or_accepts_responsibility(tmp_path):
    service = service_at(tmp_path)
    proposal = service.prepare([deployment()], source=SOURCE)
    service.authorize = None
    with pytest.raises(DeploymentError, match="trusted Core"):
        service.commit(proposal, operation_id=operation())
    service.authorize = lambda _request: True
    ai_source = {"kind": "ai", "id": "diagnostic", "owner": "fixture"}
    with pytest.raises(DeploymentError, match="operator acceptance"):
        service.prepare([deployment(), resource(), grant("$app", "$storage")], source=ai_source)
    with pytest.raises(DeploymentError, match="operator transition"):
        service.prepare([deployment(), resource(), includes()], source=ai_source)
    assert service.status()["revision"] == 0


def test_positive_grant_release_retains_resources_and_does_not_certify_detach(tmp_path):
    service = service_at(tmp_path)
    dep, res, _ = topology(service, grants=True)
    state = service.inspect(dep)
    responsibility = state["responsibilities"][0]
    assert state["management"]["status"] == "responsibility_accepted"
    assert responsibility["accepted_by"] == SOURCE
    assert responsibility["setting_id"] == "fixture.setting"
    change(service, [{"action": "release_responsibility", "reference": responsibility["reference"], "disposition": "retained_external"}])
    state = service.inspect(dep)
    assert state["management"]["status"] == "no_responsibility"
    assert state["responsibilities"][0]["lifecycle"] == "released"
    assert state["resources"][0]["reference"] == res
    assert state["detach"]["status"] == "not_certified"


def test_grant_participation_and_shared_setting_conflicts(tmp_path):
    service = service_at(tmp_path)
    dep, res, _ = topology(service, grants=True)
    with pytest.raises(DeploymentError, match="responsibility conflict"):
        service.prepare([grant(dep, res)], source=SOURCE)
    # Another setting is independently scoped.
    change(service, [grant(dep, res, setting="fixture.other")])
    with pytest.raises(DeploymentError, match="responsibility conflict"):
        service.prepare([grant(dep, dep, setting=None)], source=SOURCE)
    with pytest.raises(DeploymentError, match="participation"):
        service.prepare([deployment("second"), grant("$second", res)], source=SOURCE)
    with pytest.raises(DeploymentError, match="responsibility conflict"):
        service.prepare([deployment("second"), includes("$second", res), grant("$second", res)], source=SOURCE)


def test_deployment_wide_scope_blocks_shared_resource_and_observation_can_coexist(tmp_path):
    service = service_at(tmp_path)
    dep, res, _ = topology(service)
    change(service, [grant(dep, dep, setting=None)])
    with pytest.raises(DeploymentError, match="responsibility conflict"):
        service.prepare([deployment("second"), includes("$second", res), grant("$second", res)], source=SOURCE)
    first, _ = change(service, [grant(dep, res, duty="observation", setting=None)])
    second, _ = change(service, [deployment("second"), includes("$second", res), grant("$second", res, duty="observation", setting=None)])
    assert service.inspect(second["changes"][0]["reference"])["responsibilities"][0]["duty"] == "observation"
    with pytest.raises(DeploymentError, match="responsibility conflict"):
        service.prepare([grant(dep, res, duty="observation", setting=None)], source=SOURCE)
    assert first["changes"][0]["duty"] == "observation"


def test_atomic_failure_preserves_every_record(tmp_path):
    service = service_at(tmp_path)
    dep, res, _ = topology(service)
    before = service.export_document()
    changes = [{"action": "rename_deployment", "reference": dep, "label": "Must not persist"},
               grant(dep, res), grant(dep, res)]
    with pytest.raises(DeploymentError, match="responsibility conflict"):
        service.prepare(changes, source=SOURCE)
    assert service.export_document() == before
    proposal = service.prepare([{ "action": "rename_deployment", "reference": dep, "label": "Valid"}], source=SOURCE)
    proposal["changes"].append({"action": "rebind_resource", "reference": res, "native": {"invalid": True}})
    with pytest.raises(DeploymentError):
        service.commit(proposal, operation_id=operation())
    assert service.export_document() == before


def test_relationship_types_and_dangling_targets_fail_before_effects(tmp_path):
    service = service_at(tmp_path)
    dep, res, _ = topology(service)
    before = service.export_document()
    invalid = [
        {**includes(dep, res), "kind": "arbitrary"},
        {**includes(dep, dep), "role": "self"},
        {**includes(dep, res), "kind": "uses", "role": "database"},
        {**includes(dep, res), "kind": "exposes"},
        {**includes(dep, res), "target": {**res, "object_id": "resource:" + "a" * 32}},
    ]
    for item in invalid:
        with pytest.raises(DeploymentError):
            service.prepare([item], source=SOURCE)
    assert service.export_document() == before
    with pytest.raises(DeploymentError, match="native resource"):
        service.prepare([resource("duplicate")], source=SOURCE)


def test_four_typed_relationships_round_trip_without_observed_facts(tmp_path):
    service = service_at(tmp_path)
    changes = [deployment(), resource("service", kind="service", native_id="service-native"),
               resource(), resource("endpoint", kind="endpoint", native_id="endpoint-native"),
               includes(target="$service", role="application"), includes(), includes(target="$endpoint", role="public"),
               {"action": "add_relationship", "deployment": "$app", "kind": "depends_on", "subject": "$app",
                "target": "$service", "role": "application", "evidence": []},
               {"action": "add_relationship", "deployment": "$app", "kind": "uses", "subject": "$service",
                "target": "$storage", "role": "storage", "evidence": []},
               {"action": "add_relationship", "deployment": "$app", "kind": "exposes", "subject": "$endpoint",
                "target": "$service", "role": "public", "evidence": []}]
    proposal, _ = change(service, changes)
    state = service.inspect(proposal["changes"][0]["reference"])
    assert {row["kind"] for row in state["relationships"]} == {"includes", "depends_on", "uses", "exposes"}
    assert state["verification"]["status"] == "not_verified"


def test_claims_preserve_competing_sources_and_require_explicit_resolution(tmp_path):
    service = service_at(tmp_path)
    dep, res, _ = topology(service)
    new_resource, _ = change(service, [resource("alternative", native_id="alternative-native")])
    alternative = new_resource["changes"][0]["reference"]
    source = {"kind": "discovery", "id": "inventory", "owner": "fixture"}
    claim = {**includes(dep, alternative), "action": "record_claim"}
    proposal, _ = change(service, [claim], source=source)
    claim_ref = proposal["changes"][0]["reference"]
    state = service.inspect(dep)
    assert state["claims"][0]["source"] == source
    assert state["claims"][0]["lifecycle"] == "proposed"
    assert state["relationships"][0]["target"] == res
    assert state["conflicts"][0]["claim"] == claim_ref
    with pytest.raises(DeploymentError, match="claims block"):
        service.prepare([grant(dep, res)], source=SOURCE)
    with pytest.raises(DeploymentError, match="claims block"):
        service.prepare([{"action": "rebind_resource", "reference": res, "native": {**service.inspect(res)["native"], "incarnation": "changed"}}], source=SOURCE)
    # Rejecting the alternate claim leaves the approved binding unchanged.
    change(service, [{"action": "resolve_claim", "reference": claim_ref, "decision": "reject"}])
    assert service.inspect(dep)["conflicts"] == []
    change(service, [grant(dep, res)])
    assert service.inspect(dep)["claims"][0]["source"] == source


def test_claim_acceptance_is_atomic_with_retirement_and_preserves_claim_source(tmp_path):
    service = service_at(tmp_path)
    dep, res, _ = topology(service)
    proposal, _ = change(service, [resource("alternate", native_id="alternate")])
    alternate = proposal["changes"][0]["reference"]
    source = {"kind": "module", "id": "recognizer", "owner": "fixture"}
    proposal, _ = change(service, [{**includes(dep, alternate), "action": "record_claim"}], source=source)
    claim_ref = proposal["changes"][0]["reference"]
    old = service.inspect(dep)["relationships"][0]["reference"]
    with pytest.raises(DeploymentError, match="relationship slot"):
        service.prepare([{"action": "resolve_claim", "reference": claim_ref, "decision": "accept"}], source=SOURCE)
    change(service, [{"action": "retire_relationship", "reference": old},
                     {"action": "resolve_claim", "reference": claim_ref, "decision": "accept"}])
    state = service.inspect(dep)
    assert state["conflicts"] == []
    assert state["claims"][0]["lifecycle"] == "accepted"
    relation = next(row for row in state["relationships"] if row["lifecycle"] == "active")
    assert relation["target"] == alternate and relation["claim"] == claim_ref
    assert relation["source"] == source
    assert relation["last_change"]["source"] == SOURCE
    assert service.inspect(res)["origin"] == "external"


def test_restore_rejects_claim_self_acceptance_and_preserves_original(tmp_path):
    service = service_at(tmp_path)
    dep, res, _ = topology(service)
    proposal, _ = change(service, [{**includes(dep, res, role="proposal"), "action": "record_claim"}],
                         source={"kind": "ai", "id": "proposal", "owner": "fixture"})
    change(service, [{"action": "resolve_claim", "reference": proposal["changes"][0]["reference"], "decision": "reject"}])
    before = service.export_document()
    altered = copy.deepcopy(before)
    claim = next(row for row in altered["records"] if row["record_type"] == "claim")
    claim["resolution"]["source"]["kind"] = "ai"
    with pytest.raises(DeploymentError, match="operator provenance"):
        restore(service, altered)
    assert service.export_document() == before
    assert not (service.directory / "recovery.json").exists()


def test_unrelated_resource_grant_remains_possible_with_preserved_conflicting_claim(tmp_path):
    service = service_at(tmp_path)
    dep, res, _ = topology(service)
    proposal, _ = change(service, [resource("alternate", native_id="alternate"),
                                  resource("unrelated", native_id="unrelated"), includes(dep, "$unrelated", role="unrelated")])
    alternate, unrelated = (proposal["changes"][index]["reference"] for index in (0, 1))
    change(service, [{**includes(dep, alternate), "action": "record_claim"}],
           source={"kind": "discovery", "id": "inventory", "owner": "fixture"})
    change(service, [grant(dep, unrelated)])
    assert service.inspect(dep)["conflicts"]
    with pytest.raises(DeploymentError, match="claims block"):
        service.prepare([grant(dep, res)], source=SOURCE)


def test_idempotent_operation_reentry_and_payload_identity_conflict(tmp_path):
    service = service_at(tmp_path)
    proposal = service.prepare([deployment()], source=SOURCE)
    op = operation()
    result = service.commit(proposal, operation_id=op)
    assert service.commit(proposal, operation_id=op) == result
    assert service.status()["revision"] == 1
    altered = copy.deepcopy(proposal)
    altered["changes"][0]["label"] = "Changed payload"
    with pytest.raises(DeploymentError, match="different metadata"):
        service.commit(altered, operation_id=op)


def test_concurrent_compare_and_swap_has_one_winner(tmp_path):
    service = service_at(tmp_path)
    topology(service)
    dep = service.list()[0]["identity"]["reference"]
    proposals = [service.prepare([{"action": "rename_deployment", "reference": dep, "label": label}], source=SOURCE)
                 for label in ("First", "Second")]
    def attempt(proposal):
        try:
            return DeploymentService(tmp_path, authorize=lambda _request: True).commit(proposal, operation_id=operation())["revision"]
        except DeploymentError:
            return "conflict"
    with ThreadPoolExecutor(2) as pool:
        assert sorted(pool.map(attempt, proposals), key=str) == [2, "conflict"]
    assert service.status()["revision"] == 2


def test_export_restore_preserves_identity_retains_later_records_and_fences_replay(tmp_path):
    service = service_at(tmp_path)
    dep, res, _ = topology(service)
    document = service.export_document()
    proposal, receipt = change(service, [grant(dep, res)])
    stale = service.prepare([{ "action": "rename_deployment", "reference": dep, "label": "Stale"}], source=SOURCE)
    before_restore = service.export_document()
    status = service.status()
    op = operation()
    result = service.restore_document(document, expected_revision=status["revision"], expected_state=status["state_token"], operation_id=op, source=RESTORE)
    assert result["epoch"] != document["epoch"]
    assert decode((service.directory / "recovery.json").read_text()) == before_restore
    assert (service.directory / "recovery.json").stat().st_mode & 0o777 == 0o600
    assert service.inspect(dep)["identity"]["reference"] == dep
    assert service.inspect(dep)["resources"][0]["reference"] == res
    grant_row = service.inspect(dep)["responsibilities"][0]
    assert grant_row["lifecycle"] == "released" and grant_row["disposition"] == "unresolved"
    assert service.restore_document(document, expected_revision=status["revision"], expected_state=status["state_token"], operation_id=op, source=RESTORE) == result
    with pytest.raises(DeploymentError, match="fenced"):
        service.commit(proposal, operation_id=receipt["operation_id"])
    with pytest.raises(DeploymentError, match="state conflict"):
        service.commit(stale, operation_id=operation())
    # Reusing a retained identity with a new operation is never an insert path.
    proposal = service.prepare([grant(dep, res)], source=SOURCE)
    proposal["changes"][0]["reference"] = grant_row["reference"]
    with pytest.raises(DeploymentError, match="never reused"):
        service.commit(proposal, operation_id=operation())


def test_recovery_backup_failure_rolls_back_without_changing_registry(tmp_path):
    service = service_at(tmp_path)
    dep, _, _ = topology(service)
    document = service.export_document()
    change(service, [{"action": "rename_deployment", "reference": dep, "label": "Current"}])
    before = service.export_document()
    with patch.object(service, "_write_recovery", side_effect=OSError("fixture backup unavailable")), pytest.raises(DeploymentError, match="backend unavailable"):
        restore(service, document)
    assert service.export_document() == before


def test_restore_rejects_unknown_versions_malformed_dangling_and_scope_before_writes(tmp_path):
    service = service_at(tmp_path)
    topology(service, grants=True)
    document = service.export_document()
    malformed = []
    for key, value in [("deployment_export_version", 2), ("deployment_export_version", True), ("unexpected", 1),
                       ("scope_id", "scope:" + "f" * 32), ("epoch", []), ("identities", []), ("operation_ids", ["not-an-operation"])]:
        candidate = copy.deepcopy(document)
        candidate[key] = value
        malformed.append(candidate)
    candidate = copy.deepcopy(document)
    next(row for row in candidate["records"] if row["record_type"] == "relationship")["target"]["object_id"] = "resource:" + "e" * 32
    malformed.append(candidate)
    candidate = copy.deepcopy(document)
    next(row for row in candidate["records"] if row["record_type"] == "resource")["origin"] = "igor_provisioned"
    malformed.append(candidate)
    for candidate in malformed:
        with pytest.raises(DeploymentError):
            restore(service, candidate)
        assert service.export_document() == document
    assert not (service.directory / "recovery.json").exists()


def test_restoration_to_an_initialized_same_scope_store_fences_imported_operations(tmp_path):
    source = service_at(tmp_path / "original")
    dep, _, receipt = topology(source)
    document = source.export_document()
    target = service_at(tmp_path / "target")
    # Recovery of the same installation may preserve scope; this fixture changes
    # only History's scope metadata, not any deployment/runtime resources.
    with sqlite3.connect(target.history._path) as db:
        db.execute("UPDATE metadata SET value=? WHERE key='scope_id'", (document["scope_id"],))
    with sqlite3.connect(target.path) as db:
        db.execute("UPDATE metadata SET value=? WHERE key='scope_id'", (document["scope_id"],))
    restore(target, document)
    assert target.inspect(dep)["identity"]["reference"] == dep
    proposal = target.prepare([{ "action": "rename_deployment", "reference": dep, "label": "New"}], source=SOURCE)
    with pytest.raises(DeploymentError, match="fenced"):
        target.commit(proposal, operation_id=receipt["operation_id"])


@pytest.mark.parametrize("text", ['{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}', '{"a":1e400}', '{"broken"'])
def test_strict_json_fails_closed(text):
    with pytest.raises(DeploymentError):
        decode(text)


@pytest.mark.parametrize("bad", [
    {"schema_version": True}, {"schema_version": 9}, {"unexpected": 1}, {"revision": True},
    {"record_owner": "fixture"}, {"lifecycle": []}, {"providers": [{"id": "fixture.provider", "owner": "fixture", "version": True}]},
    {"label": "password=unsafe"}, {"reference": {"scope_id": "scope:" + "a" * 32, "object_id": "deployment:path-based"}},
])
def test_closed_record_validation_rejects_malformed_contracts(tmp_path, bad):
    service = service_at(tmp_path)
    dep, _, _ = topology(service)
    row = {**service.inspect(dep)["identity"], **bad}
    with pytest.raises(DeploymentError):
        validate_record(row)


def test_unknown_store_version_and_corrupt_index_never_repair(tmp_path):
    service = service_at(tmp_path)
    topology(service)
    with sqlite3.connect(service.path) as db:
        db.execute("PRAGMA user_version=99")
    before = service.path.read_bytes()
    with pytest.raises(DeploymentError, match="unknown deployment store version"):
        service.status()
    with pytest.raises(DeploymentError):
        service.initialize(source=SOURCE)
    assert service.path.read_bytes() == before
    with sqlite3.connect(service.path) as db:
        db.execute("PRAGMA user_version=1")
        db.execute("UPDATE records SET id='wrong-index' WHERE id=(SELECT id FROM records LIMIT 1)")
    before = service.path.read_bytes()
    with pytest.raises(DeploymentError, match="index"):
        service.list()
    assert service.path.read_bytes() == before


def test_corrupt_store_and_scope_mismatch_are_retained(tmp_path):
    service = service_at(tmp_path)
    topology(service)
    with sqlite3.connect(service.path) as db:
        db.execute("UPDATE metadata SET value=? WHERE key='scope_id'", ("scope:" + "a" * 32,))
    before = service.path.read_bytes()
    with pytest.raises(DeploymentError, match="scope differs"):
        service.status()
    assert service.path.read_bytes() == before
    service.path.write_bytes(b"not-a-database")
    with pytest.raises(DeploymentError, match="backend unavailable/corrupt"):
        service.export_document()
    assert service.path.read_bytes() == b"not-a-database"


def test_symlink_and_nonprivate_storage_are_not_followed_or_repaired(tmp_path):
    outside = tmp_path / "outside"
    outside.mkdir()
    data = tmp_path / "data"
    data.mkdir()
    (data / "deployments").symlink_to(outside, target_is_directory=True)
    with pytest.raises(DeploymentError, match="symlink"):
        DeploymentService(data).status()
    assert list(outside.iterdir()) == []
    service = service_at(tmp_path / "private")
    service.path.chmod(0o644)
    with pytest.raises(DeploymentError, match="not private"):
        service.status()
    assert service.path.stat().st_mode & 0o777 == 0o644


def test_new_secrets_do_not_change_record_integrity_or_ids(tmp_path, monkeypatch):
    service = service_at(tmp_path)
    dep, res, _ = topology(service)
    before = service.export_document()
    monkeypatch.setenv("FIXTURE_PASSWORD", "Fixture application")
    monkeypatch.setenv("FIXTURE_TOKEN", "external-resource")
    assert service.export_document() == before
    assert service.inspect(dep)["identity"]["reference"] == dep
    assert service.inspect(res)["native"]["native_id"] == "external-resource"
    with pytest.raises(DeploymentError, match="secret-bearing"):
        service.prepare([deployment("copy")], source=SOURCE)
    assert service.export_document() == before


def test_admission_blocks_secret_material_and_isolated_metadata_has_no_effects(tmp_path, monkeypatch):
    monkeypatch.setenv("FIXTURE_PASSWORD", "ULTRA_SECRET_FIXTURE")
    service = service_at(tmp_path)
    before = service.export_document()
    with pytest.raises(DeploymentError, match="secret-bearing"):
        service.prepare([{**resource(), "label": "ULTRA_SECRET_FIXTURE"}], source=SOURCE)
    assert service.export_document() == before
    assert service.history.status()["episodes"] == 0
    assert not (tmp_path / "config").exists()
    assert not (tmp_path / "system_model").exists()


def test_no_implicit_privilege_execution_or_resource_destroy_contract():
    # The public module exports metadata methods; CLI adapters add READ only.
    for name in ("execute", "provision", "destroy", "adopt", "detach", "verify"):
        assert not hasattr(DeploymentService, name)
    assert "shell=True" not in (ROOT / "core/lib/deployments.py").read_text()
