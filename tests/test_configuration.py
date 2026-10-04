import copy
import json
import os
import sqlite3
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
import configuration
from configuration import ConfigurationService, decode, legacy_verbose
from configuration_schema import ConfigurationError, validate_schema
from secret_refs import SecretReferenceService, SecretSource

OP = "op-" + "a" * 32
CHANGE = {"target": "installation:local", "id": "ai.verbose", "value": False}


def commit(service, changes=None, revision=0):
    return service.commit(changes or [CHANGE], expected_revision=revision, expected_state=service.status()["state_token"], operation_id=OP)


def test_absent_inspection_never_creates_storage(tmp_path):
    service = ConfigurationService(tmp_path)
    assert service.status()["availability"] == "not_created"
    state = service.inspect()
    assert state["desired"]["status"] == "absent"
    assert state["resolved"]["value"] is True
    assert state["observed"]["status"] == "unavailable"
    assert state["application"]["status"] == "not_verified"
    assert service.export()["records"] == []
    assert list(tmp_path.iterdir()) == []


def test_declarations_are_read_only_owner_stamped_schemas(tmp_path):
    schema = {"schema_version": 1, "fields": [
        {"id": "fixture.value", "type": "boolean", "scope": "module",
         "label": "Fixture value"}
    ]}
    service = ConfigurationService(tmp_path, schemas=[("fixture", schema)])
    declarations = service.declarations()
    by_owner = {row["owner"]: row["schema"] for row in declarations}
    assert by_owner["core"]["fields"][0]["id"] == "ai.verbose"
    assert by_owner["fixture"]["owner"] == "fixture"
    assert by_owner["fixture"]["fields"][0]["id"] == "fixture.value"
    assert list(tmp_path.iterdir()) == []


def test_core_verbose_fast_resolve_coexists_with_module_desired_records(tmp_path):
    schema = {"schema_version": 1, "fields": [
        {"id": "fixture.value", "type": "boolean", "scope": "module", "default": False}
    ]}
    full = ConfigurationService(tmp_path, schemas=[("fixture", schema)])
    prepared = full.status()
    full.commit([
        {"target": "installation:local", "id": "ai.verbose", "value": False},
        {"target": "module:fixture", "id": "fixture.value", "value": True},
    ], expected_revision=0, expected_state=prepared["state_token"], operation_id=OP)

    # The startup consumer deliberately knows only Core's schema. It may read
    # Core's desired row + global revision, but it cannot claim a global state
    # token because validating that token requires the fixture schema.
    core_only = ConfigurationService(tmp_path)
    resolved = core_only.resolve_ai_verbose()
    assert resolved["resolved"] == {"status": "resolved", "value": False, "source": "desired"}
    assert resolved["revision"] == 1
    assert "state_token" not in resolved
    with pytest.raises(ConfigurationError, match="schema unavailable"):
        core_only.inspect()


def test_core_verbose_cli_fast_path_skips_installed_schema_discovery(tmp_path, monkeypatch, capsys):
    service = ConfigurationService(tmp_path)
    prepared = service.status()
    service.commit([CHANGE], expected_revision=0, expected_state=prepared["state_token"],
                   operation_id=OP)

    def forbidden(_root):
        raise AssertionError("installed module schemas must not be discovered")

    monkeypatch.setattr(configuration, "installed_schemas", forbidden)
    monkeypatch.setenv("IGOR_CONFIGURATION_ROOT", str(ROOT))
    monkeypatch.setenv("IGOR_CONFIGURATION_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("IGOR_CONFIGURATION_INHERITED_VERBOSE", "")
    monkeypatch.setattr(sys, "argv", ["configuration.py", "resolve-ai-verbose"])
    assert configuration.cli() == 0
    result = json.loads(capsys.readouterr().out)
    assert result["resolved"]["value"] is False
    assert result["revision"] == 1
    assert "state_token" not in result


def test_system_memory_fast_resolve_keeps_global_state_proof_deferred(tmp_path):
    schema = {"schema_version": 1, "fields": [{
        "id": "system.memory.warning_threshold_mib", "type": "integer",
        "scope": "module", "default": 150, "minimum": 81, "maximum": 4096,
    }]}
    service = ConfigurationService(tmp_path, schemas=[("system", schema)])
    prepared = service.status()
    service.commit([
        {"target": "module:system", "id": "system.memory.warning_threshold_mib", "value": 220},
        {"target": "installation:local", "id": "ai.verbose", "value": False},
    ], expected_revision=0, expected_state=prepared["state_token"], operation_id=OP)

    narrow = ConfigurationService(tmp_path, schemas=[("system", schema)])
    result = narrow.resolve_system_memory_warning()
    assert result["resolved"] == {"status": "resolved", "value": 220, "source": "desired"}
    assert result["revision"] == 1
    assert "state_token" not in result


def test_system_memory_cli_fast_path_uses_supplied_validated_schema(tmp_path, monkeypatch, capsys):
    schema = {"schema_version": 1, "fields": [{
        "id": "system.memory.warning_threshold_mib", "type": "integer",
        "scope": "module", "default": 150, "minimum": 81, "maximum": 4096,
    }]}
    service = ConfigurationService(tmp_path, schemas=[("system", schema)])
    prepared = service.status()
    service.commit(
        [{"target": "module:system", "id": "system.memory.warning_threshold_mib", "value": 225}],
        expected_revision=0, expected_state=prepared["state_token"], operation_id=OP,
    )

    def forbidden(_root):
        raise AssertionError("installed module schemas must not be rediscovered")

    monkeypatch.setattr(configuration, "installed_schemas", forbidden)
    monkeypatch.setenv("IGOR_CONFIGURATION_DATA_DIR", str(tmp_path))
    monkeypatch.setenv(
        "IGOR_CONFIGURATION_SYSTEM_MEMORY_RECORD",
        json.dumps({"kind": "configuration", "id": "system.memory.preferences", "schema": schema}),
    )
    monkeypatch.setattr(sys, "argv", ["configuration.py", "resolve-system-memory-warning"])
    assert configuration.cli() == 0
    assert capsys.readouterr().out.strip() == "225:1"


def test_startup_snapshot_resolves_core_and_system_from_one_revision(tmp_path):
    schema = {"schema_version": 1, "fields": [{
        "id": "system.memory.warning_threshold_mib", "type": "integer",
        "scope": "module", "default": 150, "minimum": 81, "maximum": 4096,
    }]}
    service = ConfigurationService(tmp_path, schemas=[("system", schema)])
    prepared = service.status()
    service.commit([
        {"target": "installation:local", "id": "ai.verbose", "value": False},
        {"target": "module:system", "id": "system.memory.warning_threshold_mib", "value": 240},
    ], expected_revision=0, expected_state=prepared["state_token"], operation_id=OP)

    snapshot = ConfigurationService(
        tmp_path, schemas=[("system", schema)]
    ).resolve_startup_snapshot()
    assert snapshot["revision"] == 1
    assert snapshot["ai_verbose"] == {"value": False, "source": "desired"}
    assert snapshot["system_memory_warning_mib"] == {"value": 240, "source": "desired"}
    assert "state_token" not in snapshot


def test_startup_snapshot_cli_skips_installed_schema_discovery(tmp_path, monkeypatch, capsys):
    schema = {"schema_version": 1, "fields": [{
        "id": "system.memory.warning_threshold_mib", "type": "integer",
        "scope": "module", "default": 150, "minimum": 81, "maximum": 4096,
    }]}
    service = ConfigurationService(tmp_path, schemas=[("system", schema)])
    prepared = service.status()
    service.commit([
        {"target": "installation:local", "id": "ai.verbose", "value": False},
        {"target": "module:system", "id": "system.memory.warning_threshold_mib", "value": 230},
    ], expected_revision=0, expected_state=prepared["state_token"], operation_id=OP)

    def forbidden(_root):
        raise AssertionError("installed module schemas must not be rediscovered")

    monkeypatch.setattr(configuration, "installed_schemas", forbidden)
    monkeypatch.setenv("IGOR_CONFIGURATION_ROOT", str(ROOT))
    monkeypatch.setenv("IGOR_CONFIGURATION_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("IGOR_CONFIGURATION_INHERITED_VERBOSE", "")
    monkeypatch.setenv(
        "IGOR_CONFIGURATION_SYSTEM_MEMORY_RECORD",
        json.dumps({"kind": "configuration", "id": "system.memory.preferences", "schema": schema}),
    )
    monkeypatch.setattr(sys, "argv", ["configuration.py", "resolve-startup-snapshot"])
    assert configuration.cli() == 0
    assert capsys.readouterr().out.strip() == "false:230:1"


def test_desired_revision_scope_permissions_and_reopen(tmp_path):
    service = ConfigurationService(tmp_path)
    assert commit(service)["application"] == "not_verified"
    state = ConfigurationService(tmp_path).inspect()
    assert state["scope_id"] == service.history.status()["scope_id"]
    assert state["desired"]["value"] is False
    assert state["resolved"]["source"] == "desired"
    assert state["last_change"]["operation_id"] == OP
    assert state["observed"]["status"] == "unavailable"
    assert service.directory.stat().st_mode & 0o777 == 0o700
    assert service.path.stat().st_mode & 0o777 == 0o600
    assert (service.directory / "recovery.json").stat().st_mode & 0o777 == 0o600


def test_validation_conflict_and_domain_failure_preserve_all_values(tmp_path):
    schema = {"schema_version": 1, "fields": [{"id": "fixture.limit", "type": "integer", "scope": "module", "minimum": 1}]}
    service = ConfigurationService(tmp_path, schemas=[("fixture", schema)])
    commit(service)
    before = service.export()
    with pytest.raises(ConfigurationError):
        commit(service, [CHANGE, {"target": "module:fixture", "id": "fixture.limit", "value": 0}], 1)
    with pytest.raises(ConfigurationError, match="conflict"):
        commit(service)
    service.domain_validator = lambda _candidate: (_ for _ in ()).throw(ConfigurationError("domain conflict"))
    with pytest.raises(ConfigurationError, match="domain"):
        commit(service, revision=1)
    assert service.export() == before


def test_concurrent_compare_and_swap_has_one_winner(tmp_path):
    service = ConfigurationService(tmp_path)
    commit(service)
    def attempt(value):
        try:
            return commit(ConfigurationService(tmp_path), [{**CHANGE, "value": value}], 1)["revision"]
        except ConfigurationError:
            return "conflict"
    with ThreadPoolExecutor(2) as pool:
        assert sorted(pool.map(attempt, [True, False]), key=str) == [2, "conflict"]
    assert service.status()["revision"] == 2


@pytest.mark.parametrize("field", [
    {"type": []}, {"scope": []}, {"overrides": [[]]}, {"sensitivity": []},
    {"type": "secret_ref", "sensitivity": "secret", "default": "plaintext", "secret_purpose": "auth"},
    {"type": "string", "sensitivity": "secret"}, {"minimum": 10**1000},
    {"type": "enum", "enum": ["a", "a"]}, {"unknown": 1},
    {"minimum": 4, "maximum": 2, "type": "integer"},
])
def test_closed_schema_rejects_malformed_types_and_secret_defaults(field):
    schema = {"schema_version": 1, "fields": [{"id": "fixture.value", "type": "boolean", "scope": "module", **field}]}
    with pytest.raises(ConfigurationError):
        validate_schema(schema, "fixture")


def test_scoped_module_owner_and_inactive_retention(tmp_path):
    schema = {"schema_version": 1, "fields": [{"id": "fixture.value", "type": "boolean", "scope": "module"}]}
    active = {"core", "fixture"}
    # Consume the exact owner-stamped shape returned by the module registry.
    service = ConfigurationService(tmp_path, schemas=[("fixture", validate_schema(schema, "fixture"))], owner_active=lambda owner: owner in active)
    change = {"id": "fixture.value", "target": "module:fixture", "value": True}
    commit(service, [change])
    active.remove("fixture")
    assert service.inspect("fixture.value", "module:fixture")["availability"] == "owner_inactive"
    with pytest.raises(ConfigurationError, match="inactive"):
        commit(service, [change], 1)
    with pytest.raises(ConfigurationError, match="scope"):
        service.inspect("fixture.value", "installation:local")
    with pytest.raises(ConfigurationError):
        validate_schema(schema, "other")


def test_explicit_override_precedence_and_rejection(tmp_path):
    schema = {"schema_version": 1, "fields": [{"id": "fixture.value", "type": "integer", "scope": "module", "default": 1, "overrides": ["session", "environment"]}]}
    service = ConfigurationService(tmp_path, schemas=[("fixture", schema)])
    commit(service, [{"target": "module:fixture", "id": "fixture.value", "value": 2}])
    result = service.inspect("fixture.value", "module:fixture", overrides={"environment": 3, "session": 4})
    assert result["resolved"] == {"status": "resolved", "value": 4, "source": "session"}
    assert result["desired"]["value"] == 2
    with pytest.raises(ConfigurationError, match="override"):
        service.inspect(overrides={"environment": False})


def test_secret_handles_only_and_path_validation(tmp_path):
    secrets = tmp_path / "secrets"
    secrets.mkdir(mode=0o700)
    material = secrets / "fixture.key"
    material.write_text("TOP_SECRET_TEST_VALUE")
    material.chmod(0o600)
    secret_service = SecretReferenceService(secrets)
    secret_service.register(SecretSource("fixture.credential", "fixture", "auth", "fixture.consumer", material))
    schema = {"schema_version": 1, "fields": [
        {"id": "fixture.auth", "type": "secret_ref", "scope": "module", "sensitivity": "secret", "secret_purpose": "auth"},
        {"id": "fixture.path", "type": "path", "scope": "module", "path_roots": ["data"], "path_kind": "directory"},
    ]}
    service = ConfigurationService(tmp_path / "data", schemas=[("fixture", schema)], secret_service=secret_service, path_roots={"data": tmp_path})
    commit(service, [{"target": "module:fixture", "id": "fixture.auth", "value": {"reference": "fixture.credential"}},
                     {"target": "module:fixture", "id": "fixture.path", "value": {"root": "data", "relative": "secrets"}}])
    assert "TOP_SECRET_TEST_VALUE" not in json.dumps(service.export())
    assert "TOP_SECRET_TEST_VALUE" not in json.dumps(service.inspect("fixture.auth", "module:fixture"))
    for value in ["TOP_SECRET_TEST_VALUE", {"reference": "missing"}, {"reference": "fixture.credential", "value": "TOP_SECRET_TEST_VALUE"}]:
        with pytest.raises(ConfigurationError):
            service.validate([{"target": "module:fixture", "id": "fixture.auth", "value": value}])
    for value in [{"root": "data", "relative": "../secrets"}, {"root": {}, "relative": "secrets"}, {"root": "data", "relative": "secrets\n"}]:
        with pytest.raises(ConfigurationError):
            service.validate([{"target": "module:fixture", "id": "fixture.path", "value": value}])


def test_legacy_precedence_literal_import_cutover_and_prior_value_recovery(tmp_path):
    root = tmp_path / "installation"
    for directory in ["config/variables", "secrets"]:
        (root / directory).mkdir(parents=True)
    sources = {"config/variables/ai.env": "verbose=false\n", "config/variables/ai_settings.env": "verbose=true\n", "secrets/site.env": "export verbose=true\nPASSWORD=never-import-this\n", "zz.env": "verbose='false'\n"}
    for name, content in sources.items():
        (root / name).write_text(content)
    legacy = legacy_verbose(root, "true")
    assert legacy["value"] is False
    assert legacy["source"]["path"] == "zz.env"
    service = ConfigurationService(tmp_path / "data")
    assert service.inspect(compatibility=legacy)["resolved"]["source"] == "compatibility"
    service.commit([{**CHANGE, "value": True}], expected_revision=0, expected_state=service.status()["state_token"], operation_id=OP, legacy=legacy)
    assert service.inspect()["last_change"]["source"]["kind"] == "operator"
    backup = decode((service.directory / "recovery.json").read_text())
    assert backup["legacy_baseline"]["value"] is False
    assert "never-import-this" not in json.dumps(backup)
    (root / "zz.env").write_text("verbose=false\n")
    assert service.inspect(compatibility=legacy_verbose(root))["resolved"]["value"] is True
    service.restore(backup, expected_revision=1, expected_state=service.status()["state_token"], operation_id=OP)
    assert service.inspect()["desired"]["value"] is False
    assert service.inspect()["last_change"]["source"] == {"kind": "restore"}
    assert service.status()["revision"] == 2
    assert (root / "secrets/site.env").read_text() == sources["secrets/site.env"]


def test_recovery_cannot_put_secret_material_into_provenance(tmp_path, monkeypatch):
    service = ConfigurationService(tmp_path)
    commit(service)
    document = service.export()
    monkeypatch.setenv("FIXTURE_PASSWORD", "credential-value")
    for source in [{"kind": "compatibility_file", "path": "credential-value.env"},
                   {"kind": "compatibility_file", "path": "../secret.env"},
                   {"kind": "compatibility_environment", "name": "credential-value"}]:
        malformed = copy.deepcopy(document)
        malformed["records"][0]["source"]["legacy"] = source
        with pytest.raises(ConfigurationError):
            service.restore(malformed, expected_revision=1, expected_state=service.status()["state_token"], operation_id=OP)
    assert service.export() == document


def test_legacy_executable_assignment_fails_without_execution(tmp_path):
    (tmp_path / "ai.env").write_text('verbose=$(touch "$MARKER")\n')
    with pytest.raises(ConfigurationError, match="grammar"):
        legacy_verbose(tmp_path)
    assert not (tmp_path / "marker").exists()


@pytest.mark.parametrize("source", ["if false; then\nverbose=true\nfi", "change() {\nverbose=true\n}", "source other.env", "eval 'verbose=true'", "value=${verbose:=false}"])
def test_legacy_control_flow_cannot_be_imported_as_literal_configuration(tmp_path, source):
    (tmp_path / "ai.env").write_text(source)
    with pytest.raises(ConfigurationError):
        legacy_verbose(tmp_path, "false")


def test_export_restore_scope_validation_and_empty_backend_recovery(tmp_path):
    service = ConfigurationService(tmp_path)
    commit(service)
    snapshot = service.export()
    commit(service, [{**CHANGE, "value": True}], 1)
    bad = copy.deepcopy(snapshot)
    bad["scope_id"] = "scope:" + "f" * 32
    with pytest.raises(ConfigurationError, match="scope"):
        service.restore(bad, expected_revision=2, expected_state=service.status()["state_token"], operation_id=OP)
    service.path.rename(tmp_path / "retained-backend.sqlite3")
    result = ConfigurationService(tmp_path).restore(snapshot, expected_revision=0, expected_state=service.status()["state_token"], operation_id=OP)
    assert result["revision"] == 1
    assert service.inspect()["desired"]["value"] is False
    assert service.inspect()["scope_id"] == snapshot["scope_id"]


@pytest.mark.parametrize("mode", ["corrupt", "version", "symlink", "permissions"])
def test_damaged_store_is_retained_and_inspection_fails_closed(tmp_path, mode):
    service = ConfigurationService(tmp_path)
    commit(service)
    if mode == "corrupt":
        service.path.write_bytes(b"original corrupt data")
    elif mode == "version":
        with sqlite3.connect(service.path) as db:
            db.execute("PRAGMA user_version=99")
    elif mode == "symlink":
        service.path.rename(tmp_path / "original")
        service.path.symlink_to(tmp_path / "original")
    else:
        service.path.chmod(0o644)
    before = service.path.read_bytes()
    with pytest.raises(ConfigurationError):
        service.inspect()
    assert service.path.read_bytes() == before


def test_missing_history_does_not_replace_desired_authority(tmp_path):
    service = ConfigurationService(tmp_path)
    commit(service)
    history_directory = tmp_path / "operational_history"
    history_directory.rename(tmp_path / "retained-history")
    assert service.inspect()["desired"]["value"] is False
    with pytest.raises(ConfigurationError, match="scope unavailable"):
        commit(service, revision=1)


def test_initialization_failure_and_backup_failure_leave_recoverable_store(tmp_path):
    service = ConfigurationService(tmp_path)
    with patch.object(service.history, "ensure_scope", side_effect=ValueError("unavailable")), pytest.raises(ValueError):
        commit(service)
    assert not service.path.exists()
    commit(service)
    before = service.export()
    with patch.object(service, "_backup", side_effect=OSError("unavailable")), pytest.raises(OSError):
        commit(service, revision=1)
    assert service.export() == before


def run_shell(tmp_path, script):
    env = {**os.environ, "IGOR_DIR": str(ROOT), "IGOR_DATA_DIR": str(tmp_path / "data"), "IGOR_RUNTIME_DIR": str(tmp_path / "runtime")}
    return subprocess.run(["bash", "-c", script], env=env, text=True, capture_output=True, timeout=45, check=False)


def test_ai_verbose_canonical_write_session_verify_reopen_and_no_legacy_write(tmp_path):
    result = run_shell(tmp_path, r'''
source "$IGOR_DIR/core/lib/module_loader.sh"
source "$IGOR_DIR/core/ai/core.sh"
ai_mode=executive provider=openrouter model=demo max_tokens=4096
ai_scrub_outbound() { printf '%s' "$1"; }
ai_unscrub_inbound() { printf '%s' "$1"; }
_ai_configuration_verbose_load || exit 3
_ai_configuration_verbose_set false || exit 4
printf 'session=%s revision=%s\n' "$IGOR_VERBOSE" "$IGOR_VERBOSE_REVISION"
_ai_persist_settings "$IGOR_DATA_DIR/saved.env" || exit 5
IGOR_VERBOSE=true verbose=true
_ai_configuration_verbose_load || exit 6
printf 'reopened=%s\n' "$IGOR_VERBOSE"
''')
    assert result.returncode == 0, result.stdout + result.stderr
    assert "session=false revision=1" in result.stdout
    assert "reopened=false" in result.stdout
    assert "verbose=" not in (tmp_path / "data/saved.env").read_text()
    service = ConfigurationService(tmp_path / "data")
    episodes = service.history.recent()
    assert len(episodes) == 2
    assert {row["capability"]["id"] for row in episodes} == {"core.configuration.ai_verbose.set", "core.configuration.ai_verbose.verify"}
    assert all(row["outcome"] == "success" and row["verification"]["status"] == "passed" for row in episodes)
    assert service.inspect()["application"]["status"] == "not_verified"


def test_declined_ai_verbose_keeps_session_and_store_unchanged(tmp_path):
    result = run_shell(tmp_path, r'''
source "$IGOR_DIR/core/lib/module_loader.sh"
source "$IGOR_DIR/core/ai/core.sh"
ai_mode=assist IGOR_VERBOSE=true
ai_scrub_outbound() { printf '%s' "$1"; }
ai_unscrub_inbound() { printf '%s' "$1"; }
_ai_approval_prompt() { _AI_APPROVAL_OUTCOME=DECLINE; return 1; }
if _ai_configuration_verbose_set false; then exit 4; fi
printf 'session=%s\n' "$IGOR_VERBOSE"
''')
    assert result.returncode == 0, result.stdout + result.stderr
    assert "session=true" in result.stdout
    service = ConfigurationService(tmp_path / "data")
    assert service.status()["availability"] == "not_created"
    assert service.history.recent()[0]["approval"]["result"] == "denied"


def test_json_duplicate_and_nonfinite_recovery_rejected():
    for document in ['{"schema_version":1,"schema_version":2}', '{"value":NaN}']:
        with pytest.raises(ConfigurationError):
            decode(document)


def test_recovery_rejects_frozen_proposal_when_revision_number_repeats(tmp_path):
    service = ConfigurationService(tmp_path)
    commit(service)
    frozen = service.status()
    snapshot = service.export()
    snapshot["records"][0]["value"] = True
    service.path.rename(tmp_path / "retained-backend.sqlite3")
    service.restore(snapshot, expected_revision=0, expected_state=service.status()["state_token"],
                    operation_id="op-" + "b" * 32)
    assert service.status()["revision"] == frozen["revision"]
    recovery = (service.directory / "recovery.json").read_bytes()
    with pytest.raises(ConfigurationError, match="conflict"):
        service.commit([CHANGE], expected_revision=frozen["revision"], expected_state=frozen["state_token"], operation_id=OP)
    assert service.inspect()["desired"]["value"] is True
    assert (service.directory / "recovery.json").read_bytes() == recovery


def test_linked_core_defaults_remain_readable_but_mutable_config_links_fail(tmp_path):
    (tmp_path / "core").symlink_to(ROOT / "core", target_is_directory=True)
    assert legacy_verbose(tmp_path)["value"] is True
    (tmp_path / "linked.env").symlink_to(ROOT / "core/config/defaults.conf")
    with pytest.raises(ConfigurationError, match="symlink"):
        legacy_verbose(tmp_path)
