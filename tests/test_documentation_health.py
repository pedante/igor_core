"""Regression guards for Igor 2 documentation and ownership clarity."""

import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_igor2_documents_do_not_have_competing_top_status_markers():
    for path in sorted((ROOT / "docs" / "igor2").glob("*.md")):
        top = "\n".join(path.read_text(encoding="utf-8").splitlines()[:20])
        markers = re.findall(r"^Status:\s*", top, flags=re.MULTILINE)
        assert len(markers) <= 1, f"{path.name} has competing top-level Status markers"


def test_roadmap_uses_status_for_current_cursor_not_stale_now_headings():
    roadmap = read("docs/igor2/ROADMAP.md")
    assert not re.search(r"^## Step .*— NOW\s*$", roadmap, flags=re.MULTILINE)
    assert "current-work cursor lives in [STATUS.md]" in roadmap


def test_resolved_questions_are_not_under_open_decisions():
    decisions = read("docs/igor2/DECISIONS.md")
    open_section = decisions.split("## Open decisions", 1)[1].split(
        "## Resolved questions retained for traceability", 1
    )[0]
    assert "resolved by D063" not in open_section
    assert "resolved by D062" not in open_section
    assert "### Q007" not in open_section
    assert "### Q012" not in open_section


def test_step16_baseline_contract_does_not_claim_overall_track_is_partial():
    baselines = read("docs/igor2/BASELINES.md")
    assert "Step 16 remains PARTIAL" not in baselines
    assert "completed Step 16 learning/knowledge track" in baselines


def test_accepted_milestone_decision_is_linked_and_not_left_open():
    decisions = read("docs/igor2/DECISIONS.md")
    accepted, remaining = decisions.split("## Open decisions", 1)
    opened, resolved = remaining.split("## Resolved questions retained for traceability", 1)
    assert re.search(r"^### D081\b", accepted, re.MULTILINE)
    assert not re.search(r"^### Q025\b", opened, re.MULTILINE)
    assert re.search(r"^### Q025\b", resolved, re.MULTILINE)
    for relative in (
        "docs/igor2/ARCHITECTURE.md", "docs/igor2/ROADMAP.md",
        "docs/igor2/DEVELOPMENT_POLICY.md", "docs/igor2/MODULE_API.md",
        "docs/igor2/MIGRATION.md", "docs/igor2/EXECUTION.md", "docs/igor2/LEGACY.md",
    ):
        assert "D081" in read(relative), relative


def test_architecture_index_defines_lifecycle_and_has_no_literal_newline_artifact():
    index = read("docs/igor2/README.md")
    assert "## Document lifecycle and authority" in index
    assert "\\n- [Portable Knowledge Artifacts]" not in index


def test_legacy_configuration_comments_match_current_ownership_contracts():
    igor = read("config/variables/igor.env")
    assert "Legacy tracked compatibility defaults" in igor
    assert "secrets/site.env" in igor
    assert "Do not personalize this tracked file" in igor

    system = read("config/variables/system.env")
    ram = system.split("SYSTEM_RAM_WARN_MB=80", 1)[0][-600:]
    assert "Legacy compatibility input only" in ram
    assert "not the authoritative warning policy" in ram
    assert "system.memory.warning_threshold_mib" in ram

    ai = read("config/variables/ai.env")
    verbose = ai.split("verbose=true", 1)[0][-600:]
    assert "Configuration Service" in verbose
    assert "cannot override" in verbose

    defaults = read("core/config/defaults.env")
    mail = defaults.split("MAILCMD_ENABLED=false", 1)[0][-900:]
    assert "legacy/unavailable compatibility defaults" in mail
    assert "historical core/mailcmd implementation is absent" in mail


def test_active_igor2_guidance_uses_independent_policy_not_master_gate():
    for relative in (
        "AGENTS.md", ".codex/README.md", ".codex/config.toml",
        "docs/igor2/README.md", "docs/igor2/ARCHITECTURE.md",
        "docs/igor2/MIGRATION.md", "docs/igor2/ROADMAP.md",
        "docs/igor2/VALIDATION.md",
    ):
        document = read(relative)
        assert "DEVELOPMENT_POLICY.md" in document, relative
        assert "verify the working branch contains the intended current `master`" not in document
        assert "owner confirmation and intended-master reconciliation before implementation" not in document


def test_collection_closure_keeps_existing_execution_proofs_and_read_only_gate():
    execution = read("docs/igor2/EXECUTION.md")
    proofs = re.findall(r"^### [1-5]\. (.+)$", execution, flags=re.MULTILINE)
    assert proofs == [
        "Contract proof", "Regression proof", "Vertical-slice proof",
        "Inspection proof", "Migration/recovery proof",
    ]

    rfc = read("docs/igor2/COLLECTION_OPERATOR_RFC.md")
    assert "Status: **DISCOVERY closed; approved first READ-only EXECUTION milestone ready**" in rfc
    assert "no runtime\nimplementation or push" in rfc
    assert "remain open EXECUTION acceptance gates" in rfc
    for proof in proofs:
        assert f"| {proof} |" in rfc
    assert "COLLECTION_OPERATOR_RFC.md" in read("docs/igor2/ROADMAP.md")
    assert "### D078" in read("docs/igor2/DECISIONS.md")
    assert "### D079" in read("docs/igor2/DECISIONS.md")


def test_collection_fidelity_archive_matches_candidate_bound_review():
    archive = ROOT / ".igor2-fidelity"
    hashes = {}
    for line in (archive / "SHA256SUMS").read_text().splitlines():
        expected, name = line.split("  ", 1)
        assert hashlib.sha256((archive / name).read_bytes()).hexdigest() == expected, name
        hashes[name] = expected
    assert len(hashes) == 3
    report = (archive / "evidence/igor2_collection_rfc_v2_fidelity_review.md").read_text()
    for name in (
        "source/igor2_collection_operator_rfc_v2.md",
        "reviewed_candidate/COLLECTION_OPERATOR_RFC.reviewed.md.txt",
    ):
        assert hashes[name] in report
    assert "PASS" in report
    rfc = read("docs/igor2/COLLECTION_OPERATOR_RFC.md")
    for digest in hashes.values():
        assert digest in rfc
