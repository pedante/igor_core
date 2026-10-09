"""Gate A2 synthetic read-only integration of two materially different domains."""
from __future__ import annotations

import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "core/lib"),
                str(ROOT / "modules/nextcloud_docker/lib"),
                str(ROOT / "modules/samba/lib")]

from nextcloud_recognition import NextcloudRecognitionAdapter
from resource_recognition import RecognitionCoordinator, RecognitionError
from samba_recognition import SambaRecognitionAdapter

NOW = datetime(2026, 10, 10, 12, tzinfo=timezone.utc)
CID = "a" * 64
CID2 = "b" * 64


class FakeNextcloud:
    def __init__(self, *ids):
        self.ids = ids
        self.calls = []
        self.available = True

    def discover(self, locator=None):
        self.calls.append(("discover", locator))
        return [{"container_id": cid, "daemon_id": "docker:daemon:fixture",
                 "image_id": "sha256:" + "c" * 64, "project": "files",
                 "service": "app", "created": "2026-10-09T10:00:00Z"}
                for cid in self.ids if locator is None or cid == locator]

    def select(self, candidates, *, locator=None):
        self.calls.append(("select", locator))
        selected = [item for item in candidates if item["container_id"] == locator]
        if len(selected) != 1:
            raise RecognitionError("invalid selected container")
        return selected[0]

    def inspect(self, candidate):
        self.calls.append(("inspect", candidate["container_id"]))
        return {"fingerprint": "fixture:native", "native": {"native_id": candidate["container_id"]}}


def write_source(tmp_path: Path, content: str) -> Path:
    path = tmp_path / "smb.conf"
    path.write_text(content, encoding="utf-8")
    return path


def test_shared_coordinator_sees_two_domains_without_adoption(tmp_path):
    path = write_source(tmp_path, "[global]\nworkgroup = FAMILY\n[media]\npath = /srv/media\n")
    provider = FakeNextcloud(CID)
    nc = NextcloudRecognitionAdapter(provider, clock=lambda: NOW)
    samba = SambaRecognitionAdapter(path, clock=lambda: NOW)
    runtime = RecognitionCoordinator([nc.binding(active=True, module_version="1"),
                                      samba.binding(active=True, module_version="1")])
    a = runtime.discover("nextcloud.application", now=NOW)
    b = runtime.discover("samba.share", now=NOW)
    assert (a["status"], b["status"]) == ("ready", "ready")
    assert (a["provider"]["owner"], b["provider"]["owner"]) == ("nextcloud_docker", "samba")
    assert a["candidates"][0]["selector"] == CID
    assert b["candidates"][0]["selector"] == "share:media"
    assert "FAMILY" not in repr(b) and "/srv/media" not in repr(b)
    assert provider.calls == [("discover", None)]


def test_multiple_sources_do_not_choose_first(tmp_path):
    path = write_source(tmp_path, "[global]\n[archive]\npath=/mnt/a\n[media]\npath=/mnt/b\n")
    provider = FakeNextcloud(CID, CID2)
    nc = NextcloudRecognitionAdapter(provider, clock=lambda: NOW)
    samba = SambaRecognitionAdapter(path, clock=lambda: NOW)
    runtime = RecognitionCoordinator([nc.binding(active=True, module_version="1"),
                                      samba.binding(active=True, module_version="1")])
    assert runtime.discover("nextcloud.application", now=NOW)["status"] == "ambiguous"
    result = runtime.discover("samba.share", now=NOW)
    assert result["status"] == "ambiguous"
    assert [r["selector"] for r in result["candidates"]] == ["share:archive", "share:media"]
    assert runtime.discover("samba.share", exact_locator="share:media", now=NOW)["status"] == "ready"
    assert runtime.discover("samba.share", exact_locator="share:missing", now=NOW)["status"] == "empty"


def test_disabled_provider_is_not_invoked(tmp_path):
    path = write_source(tmp_path, "[media]\npath=/mnt/media\n")
    nc = FakeNextcloud(CID)
    runtime = RecognitionCoordinator([
        NextcloudRecognitionAdapter(nc).binding(active=False, module_version="1"),
        SambaRecognitionAdapter(path).binding(active=False, module_version="1")])
    assert runtime.discover("nextcloud.application")["status"] == "unavailable"
    assert runtime.discover("samba.share")["status"] == "unavailable"
    assert nc.calls == []


def test_nextcloud_inspection_remains_read_only(tmp_path):
    nc = FakeNextcloud(CID)
    a = NextcloudRecognitionAdapter(nc, clock=lambda: NOW)
    inspected = a.inspect_exact(CID)
    assert inspected["native"]["native_id"] == CID
    assert [c[0] for c in nc.calls] == ["discover", "select", "inspect"]
    with pytest.raises(RecognitionError):
        a.inspect_exact("short-id")


def test_samba_reinspection_fences_changed_source(tmp_path):
    path = write_source(tmp_path, "[media]\npath = /media\n")
    a = SambaRecognitionAdapter(path, clock=lambda: NOW)
    frozen = a.discover("share:media")[0]["evidence"][0]["source_ref"]
    assert a.inspect_exact("share:media", frozen_source_ref=frozen)["selector"] == "share:media"
    path.write_text("[media]\npath = /different-media\n", encoding="utf-8")
    with pytest.raises(RecognitionError, match="changed"):
        a.inspect_exact("share:media", frozen_source_ref=frozen)


@pytest.mark.parametrize("text", [
    "[media]\ninclude = /etc/samba/private.conf\n",
    "[media]\nconfig file = /other.conf\n",
    "[homes]\npath = /home/%U\n",
    "[media]\npath=x\n[MEDIA]\npath=y\n",
    "[secret: weird]\npath=x\n",
    "[media]\nnot_a_parameter\n",
])
def test_unsupported_source_fails_without_echoing_config(tmp_path, text):
    a = SambaRecognitionAdapter(write_source(tmp_path, text + "secret = SENTINEL\n"), clock=lambda: NOW)
    result = RecognitionCoordinator([a.binding(active=True, module_version="1")]).discover("samba.share", now=NOW)
    assert result["status"] == "error"
    assert "SENTINEL" not in repr(result)


def test_symlink_is_not_opened(tmp_path):
    target = write_source(tmp_path, "[media]\npath=/mnt\n")
    link = tmp_path / "link"
    link.symlink_to(target)
    a = SambaRecognitionAdapter(link, clock=lambda: NOW)
    assert RecognitionCoordinator([a.binding(active=True, module_version="1")]).discover("samba.share", now=NOW)["status"] == "error"


def test_nonregular_source_refused_without_blocking(tmp_path):
    path = tmp_path / "pipe"
    os.mkfifo(path)
    a = SambaRecognitionAdapter(path, clock=lambda: NOW)
    assert RecognitionCoordinator([a.binding(active=True, module_version="1")]).discover("samba.share", now=NOW)["status"] == "error"


def test_oversize_and_bad_encoding_refused(tmp_path):
    path = tmp_path / "smb.conf"
    a = SambaRecognitionAdapter(path, clock=lambda: NOW)
    path.write_bytes(b"X" * 131073)
    assert RecognitionCoordinator([a.binding(active=True, module_version="1")]).discover("samba.share", now=NOW)["status"] == "error"
    path.write_bytes(b"\xff")
    assert RecognitionCoordinator([a.binding(active=True, module_version="1")]).discover("samba.share", now=NOW)["status"] == "error"


def test_original_source_unchanged(tmp_path):
    path = write_source(tmp_path, "[global]\nsecurity = user\n[media]\npath = /mnt/media\n")
    before = path.read_bytes()
    a = SambaRecognitionAdapter(path, clock=lambda: NOW)
    assert RecognitionCoordinator([a.binding(active=True, module_version="1")]).discover("samba.share", now=NOW)["status"] == "ready"
    assert path.read_bytes() == before
