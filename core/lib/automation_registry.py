"""Step 14A configured intent. This module has no execution path."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from capability_runtime import CapabilityError, validate_inputs

VERSION = 1
IDENT = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
SECRET_NAME = re.compile(r"(?:secret|password|token|credential|private_key)", re.IGNORECASE)


class AutomationError(ValueError):
    """A typed registry, policy, or store failure."""


def _closed(value: Any, fields: set[str], required: set[str], where: str) -> dict[str, Any]:
    if type(value) is not dict or set(value) - fields or required - set(value):
        raise AutomationError(f"{where} has unknown or missing fields")
    return value


def _timestamp(value: Any) -> str:
    if type(value) is not str or not value.endswith("Z"):
        raise AutomationError("once_at must be an absolute UTC timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise AutomationError("once_at is invalid") from exc
    if parsed.tzinfo != timezone.utc:
        raise AutomationError("once_at must be UTC")
    return value


def _trigger(value: Any) -> dict[str, Any]:
    obj = _closed(value, {"kind", "schema_version", "once_at"}, {"kind", "schema_version", "once_at"}, "trigger")
    if obj["kind"] != "once_at" or type(obj["schema_version"]) is not int or obj["schema_version"] != 1:
        raise AutomationError("trigger is unsupported in 14A")
    _timestamp(obj["once_at"])
    return obj


def _proposal(value: Any) -> dict[str, Any]:
    obj = _closed(value, {"id", "owner", "module_version", "source", "availability", "descriptor"},
                  {"id", "owner", "module_version", "source", "availability", "descriptor"}, "proposal")
    desc = _closed(obj["descriptor"], {"kind", "id", "owner", "source", "trigger", "target", "requires"},
                   {"kind", "id", "trigger", "target"}, "proposal descriptor")
    if (desc["kind"] != "automation" or desc["id"] != obj["id"] or
            type(obj["owner"]) is not str or type(obj["id"]) is not str or
            not obj["id"].startswith(obj["owner"] + ".") or
            type(obj["module_version"]) is not str):
        raise AutomationError("proposal identity or owner is invalid")
    _closed(desc["trigger"], {"kind", "schema_version"}, {"kind", "schema_version"}, "proposal trigger")
    if desc["trigger"] != {"kind": "once_at", "schema_version": 1}:
        raise AutomationError("proposal trigger is unsupported in 14A")
    _target_shape(desc["target"])
    return obj


def _target_shape(value: Any) -> dict[str, Any]:
    obj = _closed(value, {"capability_id", "provider", "inputs"}, {"capability_id", "inputs"}, "target")
    if (type(obj["capability_id"]) is not str or not IDENT.fullmatch(obj["capability_id"]) or
            "." not in obj["capability_id"] or type(obj["inputs"]) is not dict):
        raise AutomationError("target identity or inputs are invalid")
    if "provider" in obj and (type(obj["provider"]) is not str or not IDENT.fullmatch(obj["provider"])):
        raise AutomationError("target provider is invalid")
    if any(SECRET_NAME.search(key) for key in obj["inputs"] if type(key) is str):
        raise AutomationError("secret values are not automation inputs")
    return obj


def _digest(proposal: dict[str, Any]) -> str:
    payload = {key: proposal[key] for key in ("id", "owner", "module_version", "descriptor")}
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _record(value: Any) -> dict[str, Any]:
    fields = {"id", "schema_version", "owner", "source", "enabled", "trigger", "target",
              "execution_policy", "retry_policy", "schedule_cursor", "last_attempt"}
    obj = _closed(value, fields, fields, "automation record")
    if type(obj["id"]) is not str or not re.fullmatch(r"a_[0-9a-f]{32}", obj["id"]):
        raise AutomationError("automation id is invalid")
    if type(obj["schema_version"]) is not int or obj["schema_version"] != VERSION:
        raise AutomationError("automation record version is unsupported")
    if type(obj["owner"]) is not str or obj["owner"] not in {"user", "system"} or type(obj["enabled"]) is not bool:
        raise AutomationError("automation owner or enabled state is invalid")
    source = _closed(obj["source"], {"kind", "actor", "proposal_id", "module_owner", "module_version", "proposal_digest"}, {"kind", "actor"}, "source")
    if type(source["actor"]) is not str or not source["actor"] or len(source["actor"]) > 128:
        raise AutomationError("source actor is invalid")
    if source["kind"] == "manual" and set(source) != {"kind", "actor"}:
        raise AutomationError("manual source is invalid")
    if source["kind"] == "module" and set(source) != {"kind", "actor", "proposal_id", "module_owner", "module_version", "proposal_digest"}:
        raise AutomationError("module source is incomplete")
    if source["kind"] == "module" and (
            any(type(source[key]) is not str or not source[key] for key in ("proposal_id", "module_owner", "module_version")) or
            type(source["proposal_digest"]) is not str or not re.fullmatch(r"[0-9a-f]{64}", source["proposal_digest"])):
        raise AutomationError("module source provenance is invalid")
    if source["kind"] not in {"manual", "module"}:
        raise AutomationError("source kind is invalid")
    _trigger(obj["trigger"])
    _target_shape(obj["target"])
    policy = _closed(obj["execution_policy"], {"schema_version", "kind"}, {"schema_version", "kind"}, "execution policy")
    if type(policy["schema_version"]) is not int or policy != {"schema_version": 1, "kind": "read_unattended"}:
        raise AutomationError("execution policy is unsupported")
    retry = _closed(obj["retry_policy"], {"max_attempts"}, {"max_attempts"}, "retry policy")
    if type(retry["max_attempts"]) is not int or retry != {"max_attempts": 1}:
        raise AutomationError("retry policy is unsupported")
    if obj["schedule_cursor"] is not None or obj["last_attempt"] is not None:
        raise AutomationError("14A does not accept run state")
    return obj


def _json_file(path: Path) -> Any:
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise AutomationError(f"duplicate JSON field {key}")
            result[key] = value
        return result
    return json.loads(path.read_text(), object_pairs_hook=unique)


class Registry:
    def __init__(self, data_dir: Path, capabilities: list[dict[str, Any]], proposals: list[dict[str, Any]]):
        self.directory = data_dir / "automation"
        self.path = self.directory / "registry.v1.json"
        self.lock_path = self.directory / "registry.v1.lock"
        self.capabilities = capabilities
        self.proposals = {_proposal(row)["id"]: row for row in proposals if row["availability"] == "active"}

    def _path_check(self) -> None:
        for path in (self.directory, self.path, self.lock_path):
            if path.is_symlink():
                raise AutomationError("automation store path is a symlink")

    def _load(self) -> dict[str, Any]:
        self._path_check()
        if not self.path.exists():
            return {"schema_version": VERSION, "instances": []}
        try:
            data = _json_file(self.path)
            _closed(data, {"schema_version", "instances"}, {"schema_version", "instances"}, "registry")
            if type(data["schema_version"]) is not int or data["schema_version"] != VERSION:
                raise AutomationError("registry version is unsupported")
            if type(data["instances"]) is not list or len(data["instances"]) > 1024:
                raise AutomationError("registry instances are invalid")
            ids = [_record(row)["id"] for row in data["instances"]]
            if len(ids) != len(set(ids)):
                raise AutomationError("duplicate automation id")
            return data
        except (OSError, UnicodeError, json.JSONDecodeError, AutomationError, TypeError, KeyError, AttributeError) as exc:
            raise AutomationError(f"automation store invalid: {exc}; original retained at {self.path}") from exc

    def _write(self, data: dict[str, Any]) -> None:
        self._path_check()
        fd, name = tempfile.mkstemp(prefix=".registry.", dir=self.directory)
        try:
            with os.fdopen(fd, "w") as stream:
                os.fchmod(stream.fileno(), 0o600)
                json.dump(data, stream, sort_keys=True, separators=(",", ":"))
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, self.path)
            dirfd = os.open(self.directory, os.O_RDONLY)
            try:
                os.fsync(dirfd)
            finally:
                os.close(dirfd)
        finally:
            if os.path.exists(name):
                os.unlink(name)

    @contextlib.contextmanager
    def _mutating(self):
        self._path_check()
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.directory, 0o700)
        self._path_check()
        fd = os.open(self.lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            data = self._load()
            yield data
            self._write(data)

    def _target(self, value: Any, *, enable: bool = False) -> tuple[dict[str, Any], str | None]:
        target = _target_shape(value)
        rows = [r for r in self.capabilities if r["id"] == target["capability_id"] and r["availability"] == "active"]
        if "provider" in target:
            rows = [r for r in rows if r["provider"] == target["provider"]]
        if len(rows) != 1:
            return target, "target_unavailable" if not rows else "target_ambiguous"
        descriptor = rows[0]["descriptor"]
        if any(spec.get("type") == "secret_ref" for spec in descriptor["inputs"]["properties"].values()):
            raise AutomationError("secret references are unsupported for automation targets")
        try:
            inputs = validate_inputs(descriptor["inputs"], target["inputs"])
        except CapabilityError as exc:
            raise AutomationError(str(exc)) from exc
        normalized = {**target, "inputs": inputs}
        if enable and (descriptor["safety"]["tier"] != "READ" or descriptor["privilege"] != "none"):
            raise AutomationError("only unprivileged READ targets may be enabled")
        return normalized, None

    def create(self, config: Any, actor: str) -> dict[str, Any]:
        if actor != "operator":
            raise AutomationError("explicit authenticated operator is required")
        cfg = _closed(config, {"owner", "proposal_id", "trigger", "target"}, {"owner", "trigger"}, "configuration")
        if type(cfg["owner"]) is not str or cfg["owner"] not in {"user", "system"}:
            raise AutomationError("owner must be user or system")
        proposal = None
        if "proposal_id" in cfg:
            proposal = self.proposals.get(cfg["proposal_id"])
            if proposal is None:
                raise AutomationError("active proposal is unavailable")
            if "target" in cfg:
                raise AutomationError("proposal target cannot be overridden")
            target = proposal["descriptor"]["target"]
        else:
            if "target" not in cfg:
                raise AutomationError("manual target is required")
            target = cfg["target"]
        trigger = _trigger(cfg["trigger"])
        target, reason = self._target(target)
        if reason:
            raise AutomationError(reason)
        source = ({"kind": "module", "actor": actor, "proposal_id": proposal["id"],
                   "module_owner": proposal["owner"], "module_version": proposal["module_version"],
                   "proposal_digest": _digest(proposal)} if proposal else {"kind": "manual", "actor": actor})
        row = {"id": "a_" + uuid.uuid4().hex, "schema_version": VERSION, "owner": cfg["owner"],
               "source": source, "enabled": False, "trigger": trigger, "target": target,
               "execution_policy": {"schema_version": 1, "kind": "read_unattended"},
               "retry_policy": {"max_attempts": 1}, "schedule_cursor": None, "last_attempt": None}
        _record(row)
        with self._mutating() as data:
            data["instances"].append(row)
        return row

    def mutate(self, action: str, ident: str, actor: str, config: Any = None) -> dict[str, Any]:
        if actor != "operator":
            raise AutomationError("explicit authenticated operator is required")
        if action == "reset" and ident == "all":
            return self.reset_all()
        with self._mutating() as data:
            row = next((r for r in data["instances"] if r["id"] == ident), None)
            if row is None:
                raise AutomationError("automation not found")
            if action == "enable":
                _, reason = self._target(row["target"], enable=True)
                if reason or self._source_reason(row):
                    raise AutomationError(reason or self._source_reason(row))
                row["enabled"] = True
            elif action == "disable":
                row["enabled"] = False
            elif action == "edit":
                cfg = _closed(config, {"trigger", "target"}, set(), "edit")
                if not cfg:
                    raise AutomationError("edit requires trigger or target")
                if "trigger" in cfg:
                    row["trigger"] = _trigger(cfg["trigger"])
                if "target" in cfg:
                    if row["source"]["kind"] == "module":
                        raise AutomationError("copied proposal target cannot be edited")
                    target, reason = self._target(cfg["target"])
                    if reason:
                        raise AutomationError(reason)
                    row["target"] = target
                row["enabled"] = False
            elif action in {"delete", "reset"}:
                data["instances"].remove(row)
            else:
                raise AutomationError("unknown mutation")
            return row

    def reset_all(self) -> dict[str, Any]:
        """Explicit recovery cutover. Retain original bytes before replacing intent."""
        self._path_check()
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.directory, 0o700)
        self._path_check()
        fd = os.open(self.lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            backup = self.directory / "registry.v1.recovery.json"
            if backup.is_symlink():
                raise AutomationError("recovery path is a symlink")
            if self.path.exists():
                if backup.exists():
                    raise AutomationError("recovery copy already exists; move it before another full reset")
                with self.path.open("rb") as source, backup.open("xb") as target:
                    os.chmod(backup, 0o600)
                    shutil.copyfileobj(source, target)
                    target.flush()
                    os.fsync(target.fileno())
            self._write({"schema_version": VERSION, "instances": []})
            return {"schema_version": VERSION, "instances": [],
                    "recovery_copy": str(backup) if backup.exists() else None}

    def _source_reason(self, row: dict[str, Any]) -> str | None:
        source = row["source"]
        if source["kind"] == "manual":
            return None
        proposal = self.proposals.get(source["proposal_id"])
        if proposal is None:
            return "source_proposal_inactive"
        if _digest(proposal) != source["proposal_digest"]:
            return "source_proposal_changed"
        return None

    def inspect(self, ident: str | None = None, *, mode: str = "Assist") -> dict[str, Any]:
        data = self._load()
        items = []
        for row in data["instances"]:
            if ident and row["id"] != ident:
                continue
            source_reason = self._source_reason(row)
            try:
                _, target_reason = self._target(row["target"])
            except AutomationError:
                target_reason = "target_inputs_invalid"
            if target_reason is None and row["enabled"]:
                selected = [r for r in self.capabilities if r["id"] == row["target"]["capability_id"] and
                            r["availability"] == "active" and
                            ("provider" not in row["target"] or r["provider"] == row["target"]["provider"])]
                if len(selected) == 1 and (selected[0]["descriptor"]["safety"]["tier"] != "READ" or
                                           selected[0]["descriptor"]["privilege"] != "none"):
                    target_reason = "target_policy_incompatible"
            if not row["enabled"]:
                state, reason = "disabled", "disabled"
            elif source_reason or target_reason:
                state, reason = "unavailable", source_reason or target_reason
            elif mode == "Guide":
                state, reason = "unavailable", "guide_mode"
            else:
                state, reason = "unavailable", "execution_not_installed"
            items.append({**row, "state": state, "availability_reason": reason,
                          "next_due_at": row["trigger"]["once_at"], "in_flight": False})
        if ident and not items:
            raise AutomationError("automation not found")
        return {"schema_version": VERSION, "store": str(self.path), "instances": items,
                "diagnostic": "14B may admit due enabled instances after installation"}

    def list_proposals(self) -> list[dict[str, Any]]:
        return [{**p, "proposal_digest": _digest(p)} for p in self.proposals.values()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["proposals", "list", "inspect", "create", "enable", "disable", "edit", "delete", "reset"])
    parser.add_argument("argument", nargs="?")
    parser.add_argument("configuration", nargs="?")
    parser.add_argument("--mode", default="Assist")
    args = parser.parse_args()
    try:
        context = json.load(sys.stdin)
        registry = Registry(Path(context["data_dir"]), context["capabilities"], context["proposals"])
        if args.action == "proposals":
            result = registry.list_proposals()
        elif args.action in {"list", "inspect"}:
            result = registry.inspect(args.argument if args.action == "inspect" else None, mode=args.mode)
        elif args.action == "create":
            result = registry.create(json.loads(args.argument or "{}"), "operator")
        else:
            result = registry.mutate(args.action, args.argument or "", "operator",
                                     json.loads(args.configuration or "{}") if args.action == "edit" else None)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (AutomationError, ValueError, KeyError, OSError, TypeError, AttributeError) as exc:
        print(f"automation: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
