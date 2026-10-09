"""Explicit, non-executable legacy credential source selection."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core/lib"))

from openrouter_import import candidates, selected
from secret_refs import SecretReferenceError


def _private(path: Path, value: str):
    path.write_text(value)
    path.chmod(0o600)


def test_multiple_sources_have_value_free_status_and_explicit_choice(tmp_path):
    root = tmp_path / "igor"
    secret_root = root / "secrets"
    secret_root.mkdir(parents=True, mode=0o700)
    home = tmp_path / "home"
    home.mkdir()
    _private(secret_root / "openrouter.key", "synthetic-file-key\n")
    _private(home / ".nexus_or_key", "synthetic-home-key\n")
    environment = {"OPENROUTER_API_KEY": "synthetic-env-key"}
    rows = candidates(root, home=home, secret_root=secret_root, environment=environment)
    assert {row["source"] for row in rows} == {
        "private_input", "environment:OPENROUTER_API_KEY",
        "file:secrets/openrouter.key", "home:.nexus_or_key"}
    assert all(row["status"] == "available" for row in rows)
    assert "synthetic-" not in repr(rows)
    assert selected(root, home=home, secret_root=secret_root, environment=environment,
                    source="home:.nexus_or_key") == (b"synthetic-home-key", "home_import")
    with pytest.raises(SecretReferenceError):
        selected(root, home=home, secret_root=secret_root, environment=environment,
                 source="home:unknown")


def test_literal_env_parser_rejects_executable_syntax_without_running_it(tmp_path):
    root = tmp_path / "igor"
    secret_root = root / "secrets"
    secret_root.mkdir(parents=True, mode=0o700)
    home = tmp_path / "home"
    home.mkdir()
    marker = tmp_path / "must-not-exist"
    source = secret_root / "provider.env"
    _private(source, f'OPENROUTER_API_KEY="$(touch {marker})"\n')
    rows = candidates(root, home=home, secret_root=secret_root, environment={})
    assert rows[-1] == {"source": "env_file:secrets/provider.env",
                        "status": "unsafe", "kind": "env_file_import"}
    with pytest.raises(SecretReferenceError):
        selected(root, home=home, secret_root=secret_root, environment={},
                 source="env_file:secrets/provider.env")
    assert not marker.exists()
    _private(source, 'OTHER_KEY="safe"\nOPENROUTER_API_KEY="synthetic-literal-key"\n')
    assert selected(root, home=home, secret_root=secret_root, environment={},
                    source="env_file:secrets/provider.env") == (
                        b"synthetic-literal-key", "env_file_import")
    source.chmod(0o644)
    assert candidates(root, home=home, secret_root=secret_root,
                      environment={})[-1]["status"] == "unsafe"
