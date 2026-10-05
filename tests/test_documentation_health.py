"""Regression guards for Igor 2 documentation and ownership clarity."""

from pathlib import Path
import re

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


def test_status_does_not_reopen_already_accepted_boundary_a_recommendations():
    status = read("docs/igor2/STATUS.md")
    top = "\n".join(status.splitlines()[:80])
    assert "implementation unaccepted" not in top
    assert "recommendations accepted" in top
    assert "requiring owner confirmation" not in top


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
