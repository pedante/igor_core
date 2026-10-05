"""Headless Step 16F OKF portability vertical slice."""

import json
import os
import subprocess
import sys
from pathlib import Path

from test_local_learning import choose, repeated, review

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))

from local_learning import LocalLearningService


def cli(data, action, argument=None, *, stdin=None, check=True):
    args = ["bash", str(ROOT / "igor.sh"), "--knowledge", action]
    if argument is not None:
        args.append(json.dumps(argument) if isinstance(argument, dict) else argument)
    result = subprocess.run(
        args,
        input=stdin,
        text=True,
        capture_output=True,
        env={**os.environ, "IGOR_DATA_DIR": str(data)},
        timeout=30,
        check=check,
    )
    if check:
        return json.loads(result.stdout)
    return result


def test_headless_status_is_static_and_allocates_nothing(tmp_path):
    data = tmp_path / "data"
    result = cli(data, "status")
    assert result["authority"] == "reference_only"
    assert result["persistence"] == "none"
    assert result["okf_version"] == "0.2"
    assert result["import_effect"] == "validate_only"
    assert not data.exists()


def test_headless_export_import_round_trip_does_not_mutate_learning(tmp_path):
    data = tmp_path / "data"
    repeated(data)
    learning = LocalLearningService(data)
    reviewed = review(learning, choose(learning))
    frozen = (data / "local_learning" / "store.json").read_bytes()

    bundle = tmp_path / "portable"
    exported = cli(data, "export", {
        "learning_id": reviewed["learning_id"],
        "directory": str(bundle),
    })
    assert exported["okf_version"] == "0.2"
    assert exported["artifact_id"].startswith("ka-")

    imported = cli(data, "import", "-", stdin=json.dumps({"directory": str(bundle)}))
    assert imported["trust"] == "untrusted_import"
    assert imported["persistence"] == "none"
    assert imported["igor_artifact"]["artifact_id"] == exported["artifact_id"]
    assert (data / "local_learning" / "store.json").read_bytes() == frozen


def test_headless_import_failure_is_nonmutating_and_nonzero(tmp_path):
    data = tmp_path / "data"
    bundle = tmp_path / "invalid"
    bundle.mkdir()
    (bundle / "index.md").write_text('---\nokf_version: "9.9"\n---\n# Bad\n', encoding="utf-8")
    (bundle / "concept.md").write_text('---\ntype: "Reference"\n---\n# Note\n', encoding="utf-8")

    result = cli(data, "import", {"directory": str(bundle)}, check=False)
    assert result.returncode == 2
    assert "unsupported OKF version" in result.stderr
    assert not data.exists()
