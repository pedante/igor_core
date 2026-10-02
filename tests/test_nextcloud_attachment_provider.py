"""Focused read-only brownfield discovery tests for the Nextcloud provider."""
from __future__ import annotations

import copy
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "modules/nextcloud_docker/lib"))

from attachment import AttachmentError, NextcloudAttachmentProvider


def container(cid: str, *, created: str = "2025-01-02T03:04:05Z", project: str = "nc",
              service: str = "app", name: str = "nc-app-1", image: str = "nextcloud:apache"):
    return {
        "Id": cid,
        "Name": "/" + name,
        "Created": created,
        "Config": {"Image": image, "Labels": {
            "com.docker.compose.project": project,
            "com.docker.compose.service": service,
        }, "Env": ["MYSQL_PASSWORD=do-not-copy"]},
        "Image": "sha256:" + "a" * 64,
        "Mounts": [
            {"Type": "volume", "Name": "nc-html", "Source": "/var/lib/docker/volumes/nc-html/_data",
             "Destination": "/var/www/html"},
            {"Type": "volume", "Name": "nc-data", "Source": "/var/lib/docker/volumes/nc-data/_data",
             "Destination": "/var/www/html/data"},
        ],
    }


class FixtureDocker:
    def __init__(self, rows, stat_result=None):
        self.rows = {row["Id"]: copy.deepcopy(row) for row in rows}
        self.calls = []
        self.stat_result = stat_result or {"type": "regular file", "inode": 12345,
                                           "size": 4096, "mtime": 1735787045}

    def info(self):
        self.calls.append("info")
        return {"ID": "daemon-fixture-01"}

    def containers(self):
        self.calls.append("ps")
        return [{"ID": cid, "Names": row["Name"].lstrip("/"), "Image": row["Config"]["Image"]}
                for cid, row in self.rows.items()]

    def inspect(self, container_id):
        self.calls.append(("inspect", container_id))
        return copy.deepcopy(self.rows[container_id])

    def configuration_stat(self, container_id, path):
        self.calls.append(("stat", container_id, path))
        return copy.deepcopy(self.stat_result)


def candidate_ids(*ids):
    return [f"{cid:064x}" for cid in ids]


def test_discovery_and_inspection_freeze_exact_native_evidence_without_secrets():
    cid = candidate_ids(1)[0]
    docker = FixtureDocker([container(cid)])
    provider = NextcloudAttachmentProvider(docker)
    candidates = provider.discover()
    assert len(candidates) == 1
    assert candidates[0]["container_id"] == cid
    inspection = provider.inspect(provider.select(candidates))
    assert inspection["native"] == {
        "provider": provider.provider_id, "provider_scope": "daemon-fixture-01",
        "native_id": cid, "incarnation": "2025-01-02T03:04:05Z"}
    assert inspection["configuration_target"]["source"] == "/var/lib/docker/volumes/nc-html/_data"
    assert inspection["configuration_target"]["path"] == "/var/www/html/config/config.php"
    assert inspection["configuration_target"]["availability"] == "verified_regular_file"
    assert inspection["configuration_target"]["file_evidence"] == {
        "type": "regular file", "inode": 12345, "size": 4096, "mtime": 1735787045}
    assert inspection["storage"]["source"] == "/var/lib/docker/volumes/nc-data/_data"
    assert inspection["evidence"]["compose_project"] == "nc"
    assert inspection["candidate"]["image_id"] == "sha256:" + "a" * 64
    assert "MYSQL_PASSWORD" not in repr(inspection)
    changes = provider.metadata_changes(inspection)
    assert changes[-1]["setting_id"] == "nextcloud_docker.loglevel"
    assert changes[-1]["duty"] == "configuration"
    assert changes[3]["native"]["native_id"].endswith(
        "/var/www/html|/var/www/html/config/config.php")
    assert changes[5]["evidence"] == []
    assert provider.attachment_contract(inspection)["configuration_target"]["source"] == \
        "/var/lib/docker/volumes/nc-html/_data"
    assert provider.revalidate(inspection) == inspection
    assert all(call in ("info", "ps") or call[0] in {"inspect", "stat"} for call in docker.calls)


def test_zero_and_ambiguous_candidates_fail_closed_and_exact_locator_resolves():
    empty = NextcloudAttachmentProvider(FixtureDocker([]))
    assert empty.discover() == []
    with pytest.raises(AttachmentError, match="no matching"):
        empty.select([])
    ids = candidate_ids(1, 2)
    provider = NextcloudAttachmentProvider(FixtureDocker([
        container(ids[0], name="nc-same-name"), container(ids[1], name="nc-same-name", project="nc2")]))
    candidates = provider.discover()
    with pytest.raises(AttachmentError, match="multiple"):
        provider.select(candidates)
    assert provider.select(candidates, locator=ids[1])["container_id"] == ids[1]
    assert provider.discover(locator=ids[1])[0]["container_id"] == ids[1]
    with pytest.raises(AttachmentError, match="exact full"):
        provider.discover(locator="nc-same-name")


def test_recreation_or_changed_mounts_invalidate_frozen_inspection():
    cid = candidate_ids(1)[0]
    docker = FixtureDocker([container(cid)])
    provider = NextcloudAttachmentProvider(docker, version="7")
    frozen = provider.inspect(provider.select())
    docker.rows[cid]["Created"] = "2025-02-01T00:00:00Z"
    with pytest.raises(AttachmentError, match="identity or incarnation changed"):
        provider.revalidate(frozen)
    docker.rows[cid]["Created"] = frozen["candidate"]["created"]
    docker.rows[cid]["Mounts"][0]["Source"] = "/new/source"
    with pytest.raises(AttachmentError, match="stale"):
        provider.revalidate(frozen)


@pytest.mark.parametrize("file_type", ["missing", "symbolic link", "directory"])
def test_missing_or_non_regular_configuration_target_is_not_adoptable(file_type):
    cid = candidate_ids(1)[0]
    docker = FixtureDocker([container(cid)], {"type": file_type, "inode": 12345,
                                              "size": 4096, "mtime": 1735787045})
    provider = NextcloudAttachmentProvider(docker)
    with pytest.raises(AttachmentError, match="missing, non-regular"):
        provider.inspect(provider.select())


@pytest.mark.parametrize("field,value", [("inode", 99999), ("mtime", 1736000000)])
def test_configuration_file_replacement_or_update_invalidates_frozen_inspection(field, value):
    cid = candidate_ids(1)[0]
    docker = FixtureDocker([container(cid)])
    provider = NextcloudAttachmentProvider(docker)
    frozen = provider.inspect(provider.select())
    docker.stat_result[field] = value
    with pytest.raises(AttachmentError, match="stale"):
        provider.revalidate(frozen)


def test_cli_configuration_stat_uses_fixed_read_only_argv(monkeypatch):
    import attachment

    observed = []

    def fake_run(argv, **kwargs):
        observed.append((argv, kwargs))
        return subprocess.CompletedProcess(argv, 0, "regular file|12345|4096|1735787045\n", "")

    monkeypatch.setattr(attachment.subprocess, "run", fake_run)
    cid = candidate_ids(1)[0]
    transport = attachment.DockerCliTransport(executable="docker-test")
    assert transport.configuration_stat(cid, "/var/www/html/config/config.php") == {
        "type": "regular file", "inode": 12345, "size": 4096, "mtime": 1735787045}
    assert observed[0][0] == ["docker-test", "exec", "--user", "www-data", cid,
                              "stat", "--format=%F|%i|%s|%Y", "--",
                              "/var/www/html/config/config.php"]
    assert "shell" not in observed[0][1]
    assert "capture_output" in observed[0][1]


def test_disabled_or_unversioned_provider_fails_closed():
    row = container(candidate_ids(1)[0])
    with pytest.raises(AttachmentError, match="disabled"):
        NextcloudAttachmentProvider(FixtureDocker([row]), active=False).discover()
    with pytest.raises(AttachmentError, match="version"):
        NextcloudAttachmentProvider(FixtureDocker([row]), version=" ").discover()


def test_configuration_file_mount_override_refuses_incorrect_backing_reference():
    cid = candidate_ids(1)[0]
    row = container(cid)
    row["Mounts"].append({"Type": "bind", "Source": "/operator/other-config.php",
                          "Destination": "/var/www/html/config/config.php"})
    provider = NextcloudAttachmentProvider(FixtureDocker([row]))
    with pytest.raises(AttachmentError, match="file mount override"):
        provider.inspect(provider.select())
