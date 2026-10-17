"""Increment B: temporary navigation authority, bounded construction and recovery."""

import copy
import json
import multiprocessing
import os
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
from capability_runtime import CapabilityDescriptor, CapabilityError
from collection_runtime import SNAPSHOT_BYTES, Snapshots, encoded
from operational_history import _owner
from platform_services import services


@pytest.fixture
def ctx(tmp_path):
    raw = next(x for x in json.loads((ROOT / "modules/system/contracts/host.json").read_text())["contributions"]
               if x["id"] == "system.service.list")
    raw.update(owner="system", provider="system")
    descriptor = CapabilityDescriptor.from_dict(raw).inspect()
    (tmp_path / "config").mkdir()
    (tmp_path / "config/modules.conf").write_text("system=enabled\n")
    return {"descriptor": descriptor, "session_owner": _owner(os.getpid()), "session": "session-a",
            "scope_id": "scope:" + "a" * 32, "igor_dir": str(tmp_path)}


def rows(count):
    return [{"reference": {"scope_id": "scope:" + "a" * 32, "object_id": f"service:systemd:unit{i:04}.service"},
             "unit": f"unit{i:04}.service", "active_state": "inactive", "sub_state": "dead"}
            for i in range(count)]


@pytest.mark.parametrize("count", [0, 1, 50, 128, 1024])
def test_system_schema_and_stable_complete_pages(ctx, tmp_path, count):
    # Ordering/replay is independent of scheduling; TTL is tested separately.
    store = Snapshots(tmp_path / "runtime", clock=lambda: 1000.0)
    source = rows(count)
    first = store.build(ctx, 50, lambda: iter(reversed(source)))
    all_rows = list(first["rows"])
    page = first
    while page["page"]["has_more"]:
        cursor = page["page"]["next_cursor"]
        assert cursor.isascii() and len(cursor) <= 256
        page = store.page(ctx, 50, cursor)
        assert page == store.page(ctx, 50, cursor)
        all_rows.extend(page["rows"])
        assert page["freshness"] == first["freshness"]
        assert page["page"]["snapshot_revision"] == first["page"]["snapshot_revision"]
    assert all_rows == source
    assert first["page"]["total_count"] == count
    assert store.inspect()["snapshots"] == 1


def test_ttl_exact_boundary_no_renewal(ctx, tmp_path):
    now = [1000.0]
    store = Snapshots(tmp_path / "runtime", clock=lambda: now[0])
    first = store.build(ctx, 1, lambda: iter(rows(2)))
    cursor = first["page"]["next_cursor"]
    now[0] += 29.999
    assert store.page(ctx, 1, cursor)["rows"] == rows(2)[1:]
    now[0] = 1030.0
    with pytest.raises(CapabilityError, match="^collection_expired$"):
        store.page(ctx, 1, cursor)
    now[0] += 1
    with pytest.raises(CapabilityError, match="^collection_expired$"):
        store.page(ctx, 1, cursor)
    assert store.inspect()["snapshots"] == 0


@pytest.mark.parametrize("change", ["session", "scope_id", "provider", "version", "schema", "limit", "tamper", "query"])
def test_cursor_all_identity_fences(ctx, tmp_path, change):
    store = Snapshots(tmp_path / "runtime")
    cursor = store.build(ctx, 1, lambda: iter(rows(2)))["page"]["next_cursor"]
    altered = copy.deepcopy(ctx)
    limit = 1
    if change in {"session", "scope_id"}:
        altered[change] += "other"
    elif change == "provider":
        altered["descriptor"]["provider"] = "other"
    elif change == "version":
        altered["descriptor"]["capability_version"] = 2
    elif change == "schema":
        altered["descriptor"]["outputs"]["properties"]["rows"]["items"]["properties"]["unit"]["maxLength"] = 255
    elif change == "query":
        altered["descriptor"]["collection"]["inventory"] = "other"
    elif change == "limit":
        limit = 2
    else:
        cursor = cursor[:-1] + ("a" if cursor[-1] != "a" else "b")
    with pytest.raises(CapabilityError, match="^invalid_collection_cursor$"):
        store.page(altered, limit, cursor)


@pytest.mark.parametrize("cursor", ["", "x" * 256, "x" * 257, "x\n", "é", "a.b.c.d.e", None])
def test_invalid_cursor_is_value_free(ctx, tmp_path, cursor):
    with pytest.raises(CapabilityError, match="^invalid_collection_cursor$"):
        Snapshots(tmp_path / "runtime").page(ctx, 1, cursor)


def test_refresh_replaces_old_and_never_substitutes_other_session(ctx, tmp_path):
    store = Snapshots(tmp_path / "runtime")
    old = store.build(ctx, 1, lambda: iter(rows(2)))
    other = dict(ctx, session="session-b")
    other_page = store.build(other, 1, lambda: iter(rows(3)))
    fresh = store.build(ctx, 1, lambda: iter(rows(4)))
    assert fresh["page"]["snapshot_revision"] != old["page"]["snapshot_revision"]
    with pytest.raises(CapabilityError):
        store.page(ctx, 1, old["page"]["next_cursor"])
    assert store.page(other, 1, other_page["page"]["next_cursor"])["page"]["total_count"] == 3
    assert store.inspect()["snapshots"] == 2


@pytest.mark.parametrize("failure", ["rows", "duplicate", "invalid", "producer", "utf8", "late_page"])
def test_construction_failure_releases_reservation(ctx, tmp_path, failure):
    store = Snapshots(tmp_path / "runtime")
    data = rows(1025 if failure == "rows" else 2)
    if failure == "duplicate":
        data[1] = data[0]
    elif failure == "invalid":
        data[0]["unit"] = "bad;SECRET_REJECTED"
    elif failure in {"utf8", "late_page"}:
        props = ctx["descriptor"]["outputs"]["properties"]["rows"]["items"]["properties"]
        for i in range(6):
            props[f"detail_{i}"] = {"type": "string", "maxLength": 4096}
            data[1][f"detail_{i}"] = ("\ud800" if failure == "utf8" else "😀" * 4096)
    def producer():
        yield data[0]
        if failure == "producer":
            raise CapabilityError("unavailable")
        yield from data[1:]
    with pytest.raises((CapabilityError, ValueError)):
        store.build(ctx, 1, producer)
    assert store.inspect()["snapshots"] == 0
    assert not list(store.directory.glob("[0-9a-f]" * 32 + ".json"))


@pytest.mark.parametrize("delta", [0, 1])
def test_exact_snapshot_byte_ceiling(ctx, tmp_path, delta):
    props = ctx["descriptor"]["outputs"]["properties"]["rows"]["items"]["properties"]
    props["detail"] = {"type": "string", "maxLength": 4096}
    data = rows(128)
    for row in data:
        row["detail"] = ""
    # The UTC text is a fixed length when microseconds are nonzero; freeze it.
    from datetime import UTC, datetime

    import collection_runtime
    class Stamp:
        @staticmethod
        def now(tz):
            return datetime(2026, 10, 12, microsecond=123456, tzinfo=UTC)
    from unittest.mock import patch
    base = {"resource_kind": "service", "inventory": "loaded_system_services", "rows": data,
            "freshness": {"observed_at": "2026-10-12T00:00:00.123456Z", "expires_at": "2026-10-12T00:00:30.123456Z"}}
    remaining = SNAPSHOT_BYTES + delta - len(encoded(base))
    for row in data:
        row["detail"] = "x" * min(4096, remaining)
        remaining -= len(row["detail"])
    assert remaining == 0 and len(encoded(base)) == SNAPSHOT_BYTES + delta
    store = Snapshots(tmp_path / "runtime")
    with patch.object(collection_runtime, "datetime", Stamp):
        if delta:
            with pytest.raises(CapabilityError, match="collection_limit_exceeded"):
                store.build(ctx, 1, lambda: iter(data))
            assert store.inspect()["snapshots"] == 0
        else:
            store.build(ctx, 1, lambda: iter(data))
            assert store.inspect()["serialized_bytes"] == SNAPSHOT_BYTES


def test_session_and_global_reservations_exact_caps(ctx, tmp_path):
    store = Snapshots(tmp_path / "runtime")
    contexts = []
    for session in range(4):
        for collection in range(2):
            c = copy.deepcopy(ctx)
            c["session"] = f"session-{session}"
            c["descriptor"]["id"] = f"fixture.collection{collection}.list"
            contexts.append(c)
    def reserve(index):
        def producer():
            if index + 1 < len(contexts):
                reserve(index + 1)
            else:
                info = store.inspect()
                assert info["snapshots"] == 8 and info["reservations"] == 8
                assert info["serialized_bytes"] == 4 * 1024 * 1024
                extra = dict(ctx, session="extra")
                with pytest.raises(CapabilityError, match="collection_budget_exhausted"):
                    store.build(extra, 1, lambda: iter(rows(1)))
                extra = copy.deepcopy(contexts[0])
                extra["descriptor"]["id"] = "fixture.third.list"
                with pytest.raises(CapabilityError, match="collection_budget_exhausted"):
                    store.build(extra, 1, lambda: iter(rows(1)))
            yield from rows(1)
        store.build(contexts[index], 1, producer)
    reserve(0)
    assert store.inspect()["snapshots"] == 8


def _parallel_build(runtime, ctx):
    store = Snapshots(runtime)
    try:
        store.build(ctx, 1, lambda: iter(rows(2)))
        return "ok"
    except CapabilityError as exc:
        return str(exc)


def test_concurrent_processes_atomic_global_capacity(ctx, tmp_path):
    runtime = tmp_path / "runtime"
    # Parent owns the sessions; worker process exit does not end these sessions.
    contexts = [dict(ctx, session=f"concurrent-{i}") for i in range(12)]
    with ProcessPoolExecutor(max_workers=12, mp_context=multiprocessing.get_context("fork")) as pool:
        results = list(pool.map(_parallel_build, [runtime] * 12, contexts))
    assert results.count("ok") == 8
    assert results.count("collection_budget_exhausted") == 4
    assert Snapshots(runtime).inspect()["snapshots"] == 8


@pytest.mark.parametrize("cause", ["disable", "session_end", "restart", "dead_reservation", "orphan"])
def test_lifecycle_and_abandoned_lease_recovery(ctx, tmp_path, cause):
    store = Snapshots(tmp_path / "runtime")
    first = store.build(ctx, 1, lambda: iter(rows(2)))
    revision = first["page"]["snapshot_revision"]
    if cause == "disable":
        (tmp_path / "config/modules.conf").write_text("system=disabled\n")
    elif cause == "session_end":
        store.release(session=ctx["session"])
    elif cause in {"restart", "dead_reservation"}:
        with store.locked() as state:
            entry = state["entries"][revision]
            if cause == "restart":
                entry["session_owner"]["start"] = "0"
            else:
                entry.update(state="reserved", builder={"pid": 99999999, "start": "0", "boot": "unknown"})
    else:
        with store.locked() as state:
            state["entries"].pop(revision)
    assert store.inspect()["snapshots"] == 0
    assert not (store.directory / (revision + ".json")).exists()
    with pytest.raises(CapabilityError):
        store.page(ctx, 1, first["page"]["next_cursor"])


@pytest.mark.parametrize("kind", ["directory", "symlink", "file"])
def test_private_runtime_permissions(ctx, tmp_path, kind):
    runtime = tmp_path / "runtime"
    runtime.mkdir(mode=0o700)
    if kind == "directory":
        runtime.chmod(0o755)
    elif kind == "symlink":
        (runtime / "collections").symlink_to(tmp_path / "target")
    else:
        store = Snapshots(runtime)
        store.build(ctx, 1, lambda: iter(rows(1)))
        (runtime / "collections/index.json").chmod(0o644)
    with pytest.raises((CapabilityError, OSError)):
        Snapshots(runtime).inspect()


@pytest.mark.parametrize("output", [b"", b"alias.service loaded inactive dead Alias\ntemplate@.service loaded active running T\ntransient@123.service loaded active running T\n",
                                    b"bad;name.service loaded active running S\n", b"bad.service loaded active\n",
                                    b"bad.service loaded active running \xff\n", b"a.service loaded active running X\n" * 1025,
                                    b"a.service loaded active running " + b"x" * 4096 + b"\n"])
def test_bounded_platform_parse(tmp_path, monkeypatch, output):
    path = tmp_path / "systemctl"
    data = tmp_path / "source"
    data.write_bytes(output)
    path.write_text('#!/bin/sh\ncat "' + str(data) + '"\n')
    path.chmod(0o700)
    monkeypatch.setenv("PATH", str(tmp_path) + ":" + os.environ["PATH"])
    if output in (b"",) or output.startswith(b"alias"):
        result = list(services(5))
        assert len(result) == (0 if not output else 3)
    else:
        with pytest.raises((CapabilityError, UnicodeError)):
            list(services(5))


def test_missing_systemd_never_becomes_empty_success(tmp_path, monkeypatch):
    path = tmp_path / "systemctl"
    path.write_text("#!/bin/sh\nexit 1\n")
    path.chmod(0o700)
    monkeypatch.setenv("PATH", str(tmp_path) + ":" + os.environ["PATH"])
    with pytest.raises(CapabilityError, match="^unavailable$"):
        list(services(5))


def test_bounded_handler_rejects_before_bash_capture(tmp_path):
    (tmp_path / "module.sh").write_text(
        "fixture__run() { \"$IGOR_PYTHON\" -c 'import sys; "
        "sys.stdout.buffer.write(b\"SECRET_REJECTED\"*10000)'; }\n")
    result = subprocess.run([sys.executable, str(ROOT / "core/lib/module_handler.py"),
                             str(tmp_path), "fixture", "fixture__run", "fixture.run", "5",
                             "--collection", "--defer-response-validation"],
                            input=b"{}", capture_output=True, timeout=5, check=False)
    assert result.returncode == 0
    assert json.loads(result.stdout)["error"]["code"] == "collection_limit_exceeded"
    assert b"SECRET_REJECTED" not in result.stdout + result.stderr


def test_backend_resource_measurement(ctx, tmp_path):
    script = r'''
import json,resource,sys,time,platform
sys.path.insert(0,sys.argv[1])
from collection_runtime import Snapshots
context=json.loads(sys.argv[3])
store=Snapshots(sys.argv[2])
baseline=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
def resident_kib():
    return int(open("/proc/self/statm").read().split()[1])*resource.getpagesize()//1024
baseline_resident=resident_kib()
def producer():
    for i in range(1024):
        unit=f"unit{i:04}.service"
        yield {"reference":{"scope_id":context["scope_id"],"object_id":"service:systemd:"+unit},
               "unit":unit,"active_state":"inactive","sub_state":"dead"}
started=time.monotonic()
first=store.build(context,128,producer)
duration=time.monotonic()-started
resident_after_build=resident_kib()
while first["page"]["has_more"]:
    first=store.page(context,128,first["page"]["next_cursor"])
peak=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
retained=store.inspect()
store.release(session=context["session"])
print(json.dumps({"platform":platform.platform(),"machine":platform.machine(),
                 "rows":1024,"first_page_seconds":duration,"ttl_seconds":30,
                 "baseline_peak_rss_kib":baseline,"peak_rss_kib":peak,"increment_peak_rss_kib":peak-baseline,
                 "baseline_resident_kib":baseline_resident,"resident_after_build_kib":resident_after_build,
                 "measurement_limit":"high-water mark may inherit parent peak; resident samples are not transient peak proof",
                 "retained":retained,"after_release":store.inspect(),"fixture":"controlled rows; no host probe"}))
'''
    result = subprocess.run([sys.executable, "-c", script, str(ROOT / "core/lib"),
                             str(tmp_path / "measured-runtime"), json.dumps(ctx)],
                            text=True, capture_output=True, check=True, timeout=30)
    metrics = json.loads(result.stdout)
    assert metrics["retained"]["snapshots"] == 1
    assert metrics["after_release"]["snapshots"] == 0
    assert metrics["first_page_seconds"] < 30
    report = os.environ.get("IGOR_VALIDATION_REPORT")
    if report:
        (Path(report).parent / "collection-resource-measurement.json").write_text(json.dumps(metrics, indent=2) + "\n")


def test_dead_session_terminates_live_builder_before_releasing_reservation(ctx, tmp_path):
    owner = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
    ctx = dict(ctx, session_owner=_owner(owner.pid))
    runtime = tmp_path / "runtime"
    script = '''import sys,json,time
sys.path.insert(0,sys.argv[1])
from collection_runtime import Snapshots
def producer():
    time.sleep(30)
    return iter(())
Snapshots(sys.argv[2]).build(json.loads(sys.argv[3]),1,producer)
'''
    builder = subprocess.Popen([sys.executable, "-c", script, str(ROOT / "core/lib"), str(runtime), json.dumps(ctx)])
    try:
        store = Snapshots(runtime)
        deadline = time.monotonic() + 5
        while store.inspect()["reservations"] != 1 and time.monotonic() < deadline:
            time.sleep(0.01)
        assert store.inspect()["reservations"] == 1
        owner.terminate()
        owner.wait(timeout=3)
        store.inspect()
        builder.wait(timeout=3)
        assert builder.returncode != 0
        assert store.inspect()["snapshots"] == 0
    finally:
        for process in (owner, builder):
            if process.poll() is None:
                process.kill()
            process.wait()


@pytest.mark.parametrize("reason", ["collection_limit_exceeded", "collection_expired", "collection_budget_exhausted"])
def test_collection_errors_use_existing_handler_failure_bridge(ctx, reason):
    desc = ctx["descriptor"]
    result = subprocess.run([sys.executable, str(ROOT / "core/lib/capability_runtime.py"), "handler-output",
                             json.dumps(desc["outputs"]), json.dumps(desc["collection"])],
                            input=json.dumps({"status": "error", "error": {"code": reason, "message": "PRIVATE_SENTINEL"}}),
                            text=True, capture_output=True, check=False)
    assert result.returncode == 2
    assert not result.stdout
    assert result.stderr.strip() == "capability runtime: " + reason
