"""Ephemeral collection leases within the canonical capability runtime.

The registry/validators and Operational History remain authoritative. This cache
owns only bounded navigation data; it cannot authorize or dispatch an operation.
"""

import contextlib
import fcntl
import hashlib
import hmac
import json
import os
import secrets
import signal
import stat
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

from capability_runtime import (
    COLLECTION_PAGE_BYTES,
    CapabilityError,
    _decode,
    _serialized_bound,
    _validate_output_record_value,
    validate_output_schema,
    validate_outputs,
)
from operational_history import OperationalHistory, _alive, _owner, object_ref

SNAPSHOT_BYTES = 512 * 1024
SESSION_BYTES = 1024 * 1024
GLOBAL_BYTES = 4 * 1024 * 1024
TTL = 30


def encoded(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def private_directory(path):
    path = Path(path).absolute()
    for part in (path, *path.parents):
        if part.is_symlink():
            raise CapabilityError("collection_runtime_unavailable")
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise CapabilityError("collection_runtime_unavailable")
    return path


def read_private(path, ceiling):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise CapabilityError("collection_runtime_unavailable")
        value = stream.read(ceiling + 1)
        if len(value) > ceiling:
            raise CapabilityError("collection_limit_exceeded")
        return _decode(value.decode("utf-8", errors="strict"))


class Snapshots:
    def __init__(self, runtime, *, clock=time.monotonic):
        self.directory = private_directory(private_directory(runtime) / "collections")
        self.clock = clock

    @contextlib.contextmanager
    def locked(self):
        fd = os.open(self.directory / "lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "r+") as lock:
            info = os.fstat(lock.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise CapabilityError("collection_runtime_unavailable")
            fcntl.flock(lock, fcntl.LOCK_EX)
            path = self.directory / "index.json"
            state = read_private(path, 32768) if path.exists() else {"key": secrets.token_hex(32), "entries": {}}
            self._sweep(state)
            try:
                yield state
            finally:
                self._write("index.json", state)

    def _write(self, name, value):
        tmp = self.directory / (".write-" + secrets.token_hex(12))
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(encoded(value))
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(tmp, self.directory / name)
        finally:
            tmp.unlink(missing_ok=True)

    def _enabled(self, entry):
        # Disabled owners lose all leases even when another session still runs.
        config = Path(entry["igor_dir"]) / "config/modules.conf"
        if config.exists():
            for line in config.read_text().splitlines():
                key, _, value = line.partition("=")
                if key.strip() == entry["owner"] and value.strip() == "disabled":
                    return False
        return True

    def _drop(self, state, revision):
        entry = state["entries"].get(revision)
        if (entry and entry["state"] == "reserved" and
                entry["builder"]["pid"] != os.getpid() and _alive(entry["builder"])):
            # Revoke authority immediately, but retain allocation until the
            # builder actually exits. Dead sessions cannot free live reservations.
            entry["revoked"] = True
            os.kill(entry["builder"]["pid"], signal.SIGTERM)
            if _alive(entry["builder"]):
                return
        state["entries"].pop(revision, None)
        (self.directory / (revision + ".json")).unlink(missing_ok=True)

    def _sweep(self, state):
        for revision, entry in list(state["entries"].items()):
            if (entry.get("revoked") or self.clock() - entry["created"] >= TTL or not _alive(entry["session_owner"]) or
                    not self._enabled(entry) or
                    entry["state"] == "reserved" and not _alive(entry["builder"])):
                self._drop(state, revision)
        # Crash between data replacement and index publication leaves no authority.
        for path in self.directory.glob("*.json"):
            if path.name != "index.json" and path.stem not in state["entries"]:
                path.unlink()
        for path in self.directory.glob(".write-*"):
            path.unlink()

    def inspect(self):
        with self.locked() as state:
            entries = state["entries"].values()
            return {"snapshots": len(state["entries"]), "serialized_bytes": sum(x["bytes"] for x in entries),
                    "reservations": sum(x["state"] == "reserved" for x in entries),
                    "limits": {"snapshot_rows": 1024, "snapshot_bytes": SNAPSHOT_BYTES,
                               "session_snapshots": 2, "session_bytes": SESSION_BYTES,
                               "global_snapshots": 8, "global_bytes": GLOBAL_BYTES, "ttl_seconds": TTL}}

    def release(self, *, owner=None, session=None):
        with self.locked() as state:
            for revision, entry in list(state["entries"].items()):
                if (owner is None or entry["owner"] == owner) and (session is None or entry["session"] == session):
                    self._drop(state, revision)

    @staticmethod
    def binding(context, limit):
        descriptor = context["descriptor"]
        value = {key: context[key] for key in ("session", "session_owner", "scope_id")}
        value.update(descriptor=descriptor, limit=limit, query=descriptor["collection"]["inventory"])
        return hashlib.sha256(encoded(value)).hexdigest()

    def _cursor(self, key, revision, position, entry):
        prefix = f"{revision}.{position}.{entry['created']:.9f}"
        signature = hmac.new(bytes.fromhex(key), (prefix + "." + entry["binding"]).encode(), hashlib.sha256).hexdigest()
        return prefix + "." + signature

    def _page(self, state, revision, entry, snapshot, position, context, limit):
        rows = snapshot["rows"][position:position + limit]
        more = position + len(rows) < len(snapshot["rows"])
        value = {key: snapshot[key] for key in ("resource_kind", "inventory", "freshness")}
        value.update(rows=rows, page={"snapshot_revision": revision, "returned_count": len(rows),
                                     "total_count": len(snapshot["rows"]), "has_more": more})
        if more:
            value["page"]["next_cursor"] = self._cursor(state["key"], revision, position + len(rows), entry)
        desc = context["descriptor"]
        return validate_outputs(desc["outputs"], value, collection=desc["collection"], scope_id=context["scope_id"])

    def page(self, context, limit, cursor):
        if type(limit) is not int or not 1 <= limit <= 128:
            raise CapabilityError("invalid_collection_limit")
        if not isinstance(cursor, str) or not 1 <= len(cursor) <= 256 or not cursor.isascii():
            raise CapabilityError("invalid_collection_cursor")
        with self.locked() as state:
            try:
                revision, position, seconds, nanos, _signature = cursor.split(".")
                if (len(revision) != 32 or any(c not in "0123456789abcdef" for c in revision) or
                        not position.isdecimal() or not seconds.isdecimal() or
                        len(nanos) != 9 or not nanos.isdecimal()):
                    raise ValueError
                created = float(seconds + "." + nanos)
                entry = {"binding": self.binding(context, limit), "created": created}
                expected = self._cursor(state["key"], revision, int(position), entry)
                if not hmac.compare_digest(cursor, expected):
                    raise ValueError
            except (ValueError, OverflowError):
                raise CapabilityError("invalid_collection_cursor") from None
            if self.clock() - created >= TTL:
                raise CapabilityError("collection_expired")
            entry = state["entries"].get(revision)
            if (entry is None or entry["state"] != "committed" or
                    entry["binding"] != self.binding(context, limit)):
                raise CapabilityError("invalid_collection_cursor")
            snapshot = read_private(self.directory / (revision + ".json"), SNAPSHOT_BYTES)
            offset = int(position)
            if not 0 < offset < len(snapshot["rows"]) or offset % limit:
                raise CapabilityError("invalid_collection_cursor")
            return self._page(state, revision, entry, snapshot, offset, context, limit)

    def build(self, context, limit, producer):
        if type(limit) is not int or not 1 <= limit <= 128:
            raise CapabilityError("invalid_collection_limit")
        revision = secrets.token_hex(16)
        created = self.clock()
        desc = context["descriptor"]
        row_schema = validate_output_schema(desc["outputs"], collection=desc["collection"])["properties"]["rows"]["items"]
        stamp = datetime.now(timezone.utc)
        snapshot = {"resource_kind": desc["collection"]["resource_kind"],
                    "inventory": desc["collection"]["inventory"], "rows": [],
                    "freshness": {"observed_at": stamp.isoformat().replace("+00:00", "Z"),
                                  "expires_at": (stamp + timedelta(seconds=TTL)).isoformat().replace("+00:00", "Z")}}
        entry = {"session": context["session"], "session_owner": context["session_owner"],
                 "owner": desc["owner"], "igor_dir": context["igor_dir"], "binding": self.binding(context, limit),
                 "created": created, "bytes": SNAPSHOT_BYTES, "builder": _owner(os.getpid()), "state": "reserved"}
        with self.locked() as state:
            # Explicit refresh replaces this session's same collection; other sessions
            # and different collections retain their fresh leases.
            for old, row in list(state["entries"].items()):
                if row["session"] == entry["session"] and row.get("collection") == desc["id"]:
                    self._drop(state, old)
            same = [row for row in state["entries"].values() if row["session"] == entry["session"]]
            if (len(same) >= 2 or sum(row["bytes"] for row in same) + SNAPSHOT_BYTES > SESSION_BYTES or
                    len(state["entries"]) >= 8 or
                    sum(row["bytes"] for row in state["entries"].values()) + SNAPSHOT_BYTES > GLOBAL_BYTES):
                raise CapabilityError("collection_budget_exhausted")
            entry["collection"] = desc["id"]
            state["entries"][revision] = entry
        try:
            size = len(encoded(snapshot))
            seen = set()
            for row in producer():
                if self.clock() - created >= TTL:
                    raise CapabilityError("collection_expired")
                if len(snapshot["rows"]) >= 1024:
                    raise CapabilityError("collection_limit_exceeded")
                ref = object_ref(context["scope_id"], row["reference"]["object_id"])
                row = dict(row, reference=ref)
                # Admit once; use the same canonical record validator per row.
                row = _validate_output_record_value(row_schema, row)
                _serialized_bound(row, COLLECTION_PAGE_BYTES)
                identity = ref["object_id"]
                if identity in seen:
                    raise CapabilityError("invalid_domain_output")
                size += len(encoded(row)) + (1 if snapshot["rows"] else 0)
                if size > SNAPSHOT_BYTES:
                    raise CapabilityError("collection_limit_exceeded")
                seen.add(identity)
                snapshot["rows"].append(row)
            snapshot["rows"].sort(key=lambda row: (row["reference"]["scope_id"], row["reference"]["object_id"]))
            _serialized_bound(snapshot, SNAPSHOT_BYTES)
            with self.locked() as state:
                if (revision not in state["entries"] or state["entries"][revision].get("revoked") or
                        self.clock() - created >= TTL):
                    raise CapabilityError("collection_expired")
                page = self._page(state, revision, entry, snapshot, 0, context, limit)
                # Check every page before committing a snapshot; no late-page partial success.
                for offset in range(limit, len(snapshot["rows"]), limit):
                    self._page(state, revision, entry, snapshot, offset, context, limit)
                self._write(revision + ".json", snapshot)
                entry.update(state="committed", bytes=len(encoded(snapshot)))
                state["entries"][revision] = entry
                return page
        except BaseException:
            with self.locked() as state:
                self._drop(state, revision)
            raise


def runtime_path():
    return Path(os.environ.get("IGOR_RUNTIME_DIR", str(Path(os.environ.get("IGOR_DATA_DIR", str(Path(os.environ["IGOR_DIR"]) / "data"))) / "runtime")))


def context(proposal, pid, session):
    desc = proposal["descriptor"]
    return {"descriptor": desc, "session_owner": _owner(pid),
            "session": session, "scope_id": OperationalHistory(Path(os.environ.get("IGOR_DATA_DIR", str(Path(os.environ["IGOR_DIR"]) / "data")))).ensure_scope(),
            "igor_dir": os.environ["IGOR_DIR"]}


def main():
    import sys
    try:
        action = sys.argv[1]
        if action == "context":
            value = _decode(sys.stdin.read())
            print(encoded(context(value, int(sys.argv[2]), sys.argv[3])).decode())
        elif runtime_path().joinpath("collections").exists():
            store = Snapshots(runtime_path())
            if action == "release-owner":
                store.release(owner=sys.argv[2])
            elif action == "release-session":
                store.release(session=sys.argv[2])
            elif action == "inspect":
                print(encoded(store.inspect()).decode())
            else:
                raise CapabilityError("invalid_collection_request")
        elif action == "inspect":
            print('{"snapshots":0,"serialized_bytes":0,"reservations":0}')
        return 0
    except (OSError, ValueError, KeyError):
        print("collection runtime unavailable", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
