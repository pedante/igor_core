"""Step 16F portable Knowledge Artifact / OKF interchange proofs."""

import json
import stat
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))

from knowledge_artifacts import KnowledgeArtifactError, KnowledgeArtifactService
from local_learning import LocalLearningService
from test_local_learning import (
    build_reference_procedure_sources,
    choose,
    repeated,
    review,
)


def accepted_recurring(data):
    repeated(data)
    service = LocalLearningService(data)
    return review(service, choose(service))


def write_bundle(root, frontmatter, body="# External knowledge\n"):
    root.mkdir()
    (root / "index.md").write_text(
        '---\nokf_version: "0.2"\n---\n# Bundle\n', encoding="utf-8")
    lines = ["---"]
    for key, value in frontmatter.items():
        if isinstance(value, str) and key not in {"status"}:
            rendered = json.dumps(value)
        elif isinstance(value, (list, dict)):
            rendered = json.dumps(value, separators=(",", ":"))
        else:
            rendered = str(value)
        lines.append(f"{key}: {rendered}")
    lines.extend(["---", body])
    (root / "concept.md").write_text("\n".join(lines), encoding="utf-8")


def test_status_is_stateless_and_read_only(tmp_path):
    data = tmp_path / "data"
    result = KnowledgeArtifactService(data).status()
    assert result == {
        "contract": "igor.knowledge_artifact.status",
        "version": 1,
        "authority": "reference_only",
        "persistence": "none",
        "okf_version": "0.2",
        "profile": "single-concept-json-compatible-frontmatter",
        "import_effect": "validate_only",
    }
    assert not data.exists()


def test_accepted_learning_exports_okf_v02_and_round_trips_without_import_persistence(tmp_path):
    data = tmp_path / "data"
    reviewed = accepted_recurring(data)
    learning_store = (data / "local_learning" / "store.json").read_bytes()
    bundle = tmp_path / "bundle"

    service = KnowledgeArtifactService(data)
    manifest = service.export(reviewed["learning_id"], str(bundle))

    assert manifest["contract"] == "igor.knowledge_artifact.export"
    assert manifest["okf_version"] == "0.2"
    assert manifest["artifact_id"].startswith("ka-")
    assert manifest["files"][0] == "index.md"
    assert (bundle / "index.md").read_text().startswith('---\nokf_version: "0.2"\n---')
    concept = bundle / manifest["files"][1]
    raw = concept.read_text()
    assert 'type: "Igor Knowledge Artifact"' in raw
    assert '"status":"stable"' not in raw  # standard status is its own frontmatter key
    assert "status: \"stable\"" in raw
    assert '"authority":"reference_only"' in raw
    assert "## Authority" in raw
    assert stat.S_IMODE(concept.stat().st_mode) == 0o600

    imported = service.import_bundle(str(bundle))
    assert imported["contract"] == "igor.knowledge_artifact.import_candidate"
    assert imported["trust"] == "untrusted_import"
    assert imported["persistence"] == "none"
    assert imported["authority"] == "reference_only"
    assert imported["igor_artifact"]["artifact_id"] == manifest["artifact_id"]
    assert imported["igor_artifact"]["knowledge_type"] == "recurring_outcome"
    assert imported["igor_artifact"]["provenance"]["source_learning_id"] == reviewed["learning_id"]
    assert (data / "local_learning" / "store.json").read_bytes() == learning_store


def test_rejected_learning_cannot_be_exported(tmp_path):
    data = tmp_path / "data"
    repeated(data)
    learning = LocalLearningService(data)
    rejected = review(learning, choose(learning), status="rejected")
    with pytest.raises(KnowledgeArtifactError, match="only accepted"):
        KnowledgeArtifactService(data).export(rejected["learning_id"], str(tmp_path / "bundle"))
    assert not (tmp_path / "bundle").exists()


def test_reference_procedure_round_trip_preserves_structured_semantics(tmp_path):
    data = tmp_path / "data"
    learning, _ = build_reference_procedure_sources(data)
    review(learning, choose(learning, "cross_incident_pattern"))
    reviewed = review(learning, choose(learning, "reference_procedure"))

    bundle = tmp_path / "procedure"
    portability = KnowledgeArtifactService(data)
    manifest = portability.export(reviewed["learning_id"], str(bundle))
    imported = portability.import_bundle(str(bundle))
    artifact = imported["igor_artifact"]

    assert artifact["knowledge_type"] == "reference_procedure"
    assert artifact["content"]["procedure"]["kind"] == "single_action_verified"
    assert artifact["content"]["procedure"]["action"] == "Restarted the affected service"
    assert artifact["content"]["procedure"]["verification"] == "Service health verification passed"
    concept = (bundle / manifest["files"][1]).read_text()
    assert "## Procedure" in concept
    assert "Reference knowledge only" in concept


def test_generic_okf_v02_is_normalized_but_never_trusted_or_persisted(tmp_path):
    data = tmp_path / "data"
    bundle = tmp_path / "external"
    write_bundle(bundle, {
        "type": "Reference",
        "title": "External Linux note",
        "description": "Human-readable external reference",
        "tags": ["linux", "ops"],
        "status": "stable",
        "generated": {"by": "human:alice", "at": "2026-10-05T12:00:00Z"},
        "verified": {"by": "human:alice", "at": "2026-10-05T12:05:00Z"},
        "vendor_field": "preserved by producer, ignored by Igor normalization",
    })

    result = KnowledgeArtifactService(data).import_bundle(str(bundle))
    assert result["trust"] == "untrusted_import"
    assert result["persistence"] == "none"
    assert result["igor_artifact"] is None
    assert result["concept"]["type"] == "Reference"
    assert result["concept"]["tags"] == ["linux", "ops"]
    assert result["provenance"]["verified"]["by"] == "human:alice"
    assert result["import_id"].startswith("ki-")
    assert not data.exists()


@pytest.mark.parametrize("version", ["0.1", "1.0", "garbage"])
def test_unsupported_declared_okf_version_is_rejected(tmp_path, version):
    bundle = tmp_path / "external"
    write_bundle(bundle, {"type": "Reference"})
    (bundle / "index.md").write_text(
        f'---\nokf_version: "{version}"\n---\n# Bundle\n', encoding="utf-8")
    with pytest.raises(KnowledgeArtifactError, match="unsupported OKF version"):
        KnowledgeArtifactService(tmp_path / "data").import_bundle(str(bundle))


def test_multi_concept_bundle_is_bounded_out_for_initial_profile(tmp_path):
    bundle = tmp_path / "external"
    write_bundle(bundle, {"type": "Reference"})
    (bundle / "second.md").write_text('---\ntype: "Reference"\n---\n# Two\n', encoding="utf-8")
    with pytest.raises(KnowledgeArtifactError, match="exactly one concept"):
        KnowledgeArtifactService(tmp_path / "data").import_bundle(str(bundle))


def test_symlinked_concept_is_rejected(tmp_path):
    bundle = tmp_path / "external"
    write_bundle(bundle, {"type": "Reference"})
    target = bundle / "real.txt"
    target.write_text('---\ntype: "Reference"\n---\n# Real\n', encoding="utf-8")
    (bundle / "concept.md").unlink()
    (bundle / "concept.md").symlink_to(target)
    with pytest.raises(KnowledgeArtifactError, match="symlink"):
        KnowledgeArtifactService(tmp_path / "data").import_bundle(str(bundle))


def test_secret_bearing_import_is_rejected_without_side_effects(tmp_path, monkeypatch):
    monkeypatch.setenv("PORTABLE_TOKEN", "portable-secret-value")
    bundle = tmp_path / "external"
    write_bundle(bundle, {"type": "Reference"}, body="# Note\nportable-secret-value\n")
    data = tmp_path / "data"
    with pytest.raises(KnowledgeArtifactError, match="secret-bearing"):
        KnowledgeArtifactService(data).import_bundle(str(bundle))
    assert not data.exists()


def test_multiline_yaml_features_fail_closed_in_initial_profile(tmp_path):
    bundle = tmp_path / "external"
    bundle.mkdir()
    (bundle / "index.md").write_text('---\nokf_version: "0.2"\n---\n# Bundle\n', encoding="utf-8")
    (bundle / "concept.md").write_text(
        "---\ntype: Reference\nsources:\n  - resource: https://example.test/source\n---\n# Note\n",
        encoding="utf-8",
    )
    with pytest.raises(KnowledgeArtifactError, match="outside Igor OKF profile"):
        KnowledgeArtifactService(tmp_path / "data").import_bundle(str(bundle))
