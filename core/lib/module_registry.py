#!/usr/bin/env python3
"""Compile validated Module API v2 registration metadata for fast startup.

The cache contains structural package metadata only. It never records host
availability, requirement truth, approval state, privilege, or execution
results. Dynamic checks remain in the shell loader and capability dispatcher.
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any

CACHE_VERSION = 1


class RegistryError(ValueError):
    """Unsafe or malformed derived registry state."""


def _json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def _cache_directory(path: Path) -> Path:
    directory = path.parent
    try:
        directory.mkdir(parents=True, mode=0o700, exist_ok=True)
        info = directory.lstat()
    except OSError as exc:
        raise RegistryError("module registry cache directory unavailable") from exc
    if (directory.is_symlink() or not stat.S_ISDIR(info.st_mode) or
            info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700):
        raise RegistryError("module registry cache directory is unsafe")
    return directory


def _cache_file_safe(path: Path) -> bool:
    try:
        info = path.lstat()
    except (FileNotFoundError, OSError):
        return False
    return (
        not path.is_symlink()
        and stat.S_ISREG(info.st_mode)
        and info.st_uid == os.geteuid()
        and info.st_nlink == 1
        and stat.S_IMODE(info.st_mode) == 0o600
    )


def _hash_package(hasher: "hashlib._Hash", package: Path) -> None:
    root = package.resolve()
    hasher.update(b"package\0")
    hasher.update(package.name.encode())
    hasher.update(b"\0")
    for current, dirs, files in os.walk(root, followlinks=False):
        current_path = Path(current)
        dirs.sort()
        files.sort()
        for dirname in dirs:
            path = current_path / dirname
            if path.is_symlink():
                rel = path.relative_to(root).as_posix()
                hasher.update(b"symlink-dir\0" + rel.encode() + b"\0")
                hasher.update(os.readlink(path).encode() + b"\0")
        for filename in files:
            path = current_path / filename
            rel = path.relative_to(root).as_posix()
            if path.is_symlink():
                hasher.update(b"symlink\0" + rel.encode() + b"\0")
                hasher.update(os.readlink(path).encode() + b"\0")
                continue
            try:
                info = path.stat()
            except OSError as exc:
                raise RegistryError(f"cannot stat module package file: {rel}") from exc
            if not stat.S_ISREG(info.st_mode):
                continue
            hasher.update(b"file\0" + rel.encode() + b"\0")
            try:
                with path.open("rb") as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        hasher.update(block)
            except OSError as exc:
                raise RegistryError(f"cannot read module package file: {rel}") from exc
            hasher.update(b"\0")


def source_digest(module_dirs: list[Path]) -> str:
    """Fingerprint compiler semantics plus the complete installed v2 packages."""
    hasher = hashlib.sha256()
    lib_dir = Path(__file__).resolve().parent
    hasher.update(f"module-registry-cache-v{CACHE_VERSION}".encode())
    for name in (
        "module_registry.py",
        "module_contract.py",
        "capability_runtime.py",
        "configuration_schema.py",
    ):
        path = lib_dir / name
        if not path.is_file():
            continue
        hasher.update(b"core\0" + name.encode() + b"\0")
        hasher.update(path.read_bytes())
        hasher.update(b"\0")
    for package in sorted(module_dirs, key=lambda item: item.name):
        _hash_package(hasher, package)
    return hasher.hexdigest()


def _capability_dependencies(record: dict[str, Any]) -> list[str]:
    result: list[str] = []
    implementation = record.get("implementation")
    if not isinstance(implementation, dict) or implementation.get("kind") != "composition":
        return result
    for variant in implementation.get("variants", []):
        if not isinstance(variant, dict):
            continue
        for step in variant.get("steps", []):
            if isinstance(step, dict) and isinstance(step.get("capability_id"), str):
                result.append(step["capability_id"])
    final = implementation.get("final_check")
    if isinstance(final, dict) and isinstance(final.get("capability_id"), str):
        result.append(final["capability_id"])
    return list(dict.fromkeys(result))


def _memory_query_supported(record: dict[str, Any]) -> bool:
    reviewed = {
        "system.memory.warning.apply": "system__apply_memory_warning",
        "system.memory.warning.readback": "system__read_memory_warning",
    }
    ident = record.get("id")
    if ident not in reviewed:
        return False
    verification = record.get("verification")
    expected_tier = "CHANGE" if str(ident).endswith("apply") else "READ"
    return (
        record.get("owner") == "system"
        and record.get("handler") == reviewed[ident]
        and record.get("capability_version") == 2
        and record.get("privilege") == "none"
        and verification
        == {
            "kind": "trusted_query",
            "check_id": "system.memory.warning.consumer",
            "required": True,
        }
        and isinstance(record.get("safety"), dict)
        and record["safety"].get("tier") == expected_tier
    )


def _trusted_query_supported(record: dict[str, Any]) -> bool:
    if _memory_query_supported(record):
        return True
    verification = record.get("verification")
    if record.get("owner") != "system" or record.get("handler") != "system__privileged_marker":
        return False
    if record.get("capability_version") != 1 or record.get("privilege") != "required":
        return False
    if not isinstance(record.get("safety"), dict) or record["safety"].get("tier") != "CHANGE":
        return False
    expected = {
        "system.package.upgrade": {
            "kind": "trusted_query",
            "check_id": "system.package.updates.empty",
            "required": True,
        },
        "system.package.install": {
            "kind": "trusted_query",
            "check_id": "system.package.installed",
            "required": True,
        },
        "system.service.enable": {
            "kind": "trusted_query",
            "check_id": "system.service.enabled",
            "required": True,
        },
    }
    return record.get("id") in expected and verification == expected[record["id"]]


def static_unavailable_reason(record: dict[str, Any], owner: str) -> str:
    """Compile only static loader policy; never evaluate host requirements."""
    kind = record.get("kind")
    if kind == "capability":
        needed = {
            "capability_version",
            "description",
            "inputs",
            "safety",
            "privilege",
            "preconditions",
            "verification",
            "recovery",
            "affects",
        }
        if not needed <= record.keys():
            return "contract_incomplete"
        properties = record.get("inputs", {}).get("properties", {})
        if any(
            isinstance(spec, dict) and spec.get("type") == "secret_ref"
            for spec in properties.values()
        ):
            return "secret_consumer_unavailable"
        if record.get("privilege") == "required" and record.get("capability_version") == 2:
            return "typed_privileged_output_adapter_unavailable"
        if record.get("privilege") == "required":
            ident = record.get("id")
            reviewed = ident == "system.service.restart" or (
                owner == "system"
                and record.get("handler") == "system__privileged_marker"
                and ident
                in {
                    "system.package.install",
                    "system.package.upgrade",
                    "system.package.cache.clean",
                    "system.service.start",
                    "system.service.enable",
                }
            )
            if not reviewed:
                return "privileged_adapter_unavailable"
        preconditions = record.get("preconditions", [])
        unsupported = any(
            isinstance(item, dict)
            and item.get("kind") in {"platform_feature", "trusted_validator"}
            for item in preconditions
        )
        verification = record.get("verification", {})
        if isinstance(verification, dict) and verification.get("kind") == "trusted_query":
            unsupported = unsupported or not _trusted_query_supported(record)
        if record.get("id") in {
            "system.memory.warning.apply",
            "system.memory.warning.readback",
        }:
            unsupported = unsupported or not _memory_query_supported(record)
        if unsupported:
            return "trusted_adapter_unavailable"
        recovery = record.get("recovery")
        if isinstance(recovery, dict) and recovery.get("class") == "snapshot_required":
            return "snapshot_precondition_unavailable"
    elif kind == "configuration":
        if "schema" not in record:
            return "schema_missing"
    elif kind in {"relationship", "lifecycle"}:
        return "consumer deferred beyond Wave C"
    return ""


def _compile_contribution(record: dict[str, Any], owner: str) -> dict[str, Any]:
    requires = record.get("requires", {})
    if not isinstance(requires, dict):
        requires = {}
    normalized_requires = {
        key: list(requires.get(key, []))
        for key in ("modules", "capabilities", "platform_features", "platform_families", "bins")
    }
    return {
        "key": f'{record["kind"]}:{record["id"]}',
        "record": record,
        "source": record.get("source", ""),
        "requires": normalized_requires,
        "handler": record.get("handler", ""),
        "timeout": record.get("timeout_seconds", 30),
        "capability_dependencies": _capability_dependencies(record),
        "static_reason": static_unavailable_reason(record, owner),
    }


def compile_registry(module_dirs: list[Path]) -> list[dict[str, Any]]:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from module_contract import ValidationError, validate_module

    result: list[dict[str, Any]] = []
    for package in sorted(module_dirs, key=lambda item: item.name):
        name = package.name
        try:
            data = validate_module(package)
        except ValidationError as exc:
            result.append({"name": name, "status": "error", "error": f"module contract: {exc}"})
            continue
        except Exception as exc:  # isolate one broken package like the legacy subprocess path
            result.append(
                {
                    "name": name,
                    "status": "error",
                    "error": f"module registry compiler: {type(exc).__name__}: {exc}",
                }
            )
            continue
        result.append(
            {
                "name": name,
                "status": "ok",
                "data": data,
                "contributions": [
                    _compile_contribution(record, name)
                    for record in data["contributions"]
                ],
            }
        )
    return result


def _read_cache(path: Path, digest: str) -> list[dict[str, Any]] | None:
    if not _cache_file_safe(path):
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return None
    if (
        not isinstance(value, dict)
        or value.get("cache_version") != CACHE_VERSION
        or value.get("source_digest") != digest
        or not isinstance(value.get("modules"), list)
    ):
        return None
    return value["modules"]


def _write_cache(path: Path, digest: str, modules: list[dict[str, Any]]) -> None:
    directory = _cache_directory(path)
    fd, temporary = tempfile.mkstemp(prefix=".module-registry-", dir=directory)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(
                {
                    "cache_version": CACHE_VERSION,
                    "source_digest": digest,
                    "modules": modules,
                },
                stream,
                sort_keys=True,
                separators=(",", ":"),
            )
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def load_registry(cache_path: Path, module_dirs: list[Path]) -> tuple[list[dict[str, Any]], str]:
    digest = source_digest(module_dirs)
    try:
        directory = _cache_directory(cache_path)
        lock_path = directory / (cache_path.name + ".lock")
        flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
        lock_fd = os.open(lock_path, flags, 0o600)
        try:
            info = os.fstat(lock_fd)
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != os.geteuid()
                or stat.S_IMODE(info.st_mode) != 0o600
            ):
                raise RegistryError("module registry lock is unsafe")
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
            cached = _read_cache(cache_path, digest)
            if cached is not None:
                return cached, "hit"
            modules = compile_registry(module_dirs)
            _write_cache(cache_path, digest, modules)
            return modules, "miss"
        finally:
            os.close(lock_fd)
    except (OSError, RegistryError):
        return compile_registry(module_dirs), "bypass"


def _frame(*fields: object) -> None:
    stream = sys.stdout.buffer
    for field in fields:
        value = "" if field is None else str(field)
        if "\x00" in value:
            raise RegistryError("NUL is not allowed in registry framing")
        stream.write(value.encode("utf-8"))
        stream.write(b"\0")


def emit_registry(cache_path: Path, module_dirs: list[Path]) -> None:
    modules, cache_state = load_registry(cache_path, module_dirs)
    for module in modules:
        name = str(module.get("name", ""))
        status = module.get("status")
        if status != "ok":
            _frame(
                "MODULE", name, "error", module.get("error", "module validation failed"),
                "", "", "", "", "", "", "", "", "", "",
            )
            continue
        data = module["data"]
        manifest = data["manifest"]
        requirements = manifest["requirements"]
        module_requirements = {
            "modules": requirements["required_modules"],
            "capabilities": requirements["required_capabilities"],
            "platform_families": requirements["platform_families"],
            "bins": requirements["required_bins"],
        }
        rows = [item["key"] for item in module["contributions"]]
        _frame(
            "MODULE",
            name,
            "ok",
            "",
            _json(data),
            manifest.get("entrypoint") or "",
            manifest.get("version") or "",
            "true" if manifest.get("compat", {}).get("v1_hooks") else "false",
            _json(module_requirements),
            " ".join(module_requirements["modules"]),
            " ".join(module_requirements["capabilities"]),
            " ".join(module_requirements["platform_families"]),
            " ".join(module_requirements["bins"]),
            "\n".join(rows),
        )
        for item in module["contributions"]:
            requires = item["requires"]
            _frame(
                "CONTRIBUTION",
                name,
                item["key"],
                _json(item["record"]),
                item["source"],
                " ".join(requires["modules"]),
                " ".join(requires["capabilities"]),
                " ".join(requires["platform_features"]),
                " ".join(requires["platform_families"]),
                " ".join(requires["bins"]),
                item["handler"],
                item["timeout"],
                " ".join(item["capability_dependencies"]),
                item["static_reason"],
            )
    _frame("END", cache_state)


def main(argv: list[str]) -> int:
    if len(argv) < 4 or argv[1] != "emit":
        print("usage: module_registry.py emit CACHE_PATH MODULE_DIR [MODULE_DIR ...]", file=sys.stderr)
        return 2
    try:
        emit_registry(Path(argv[2]), [Path(item) for item in argv[3:]])
        return 0
    except (OSError, RegistryError, ValueError) as exc:
        print(f"module registry: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
