"""Read-only discovery and inspection for existing official Nextcloud containers.

This module is a provider contribution only. It does not attach records to Igor,
grant responsibility, or execute application commands. Callers freeze an
``Inspection`` and submit it to the Core Deployment Service for an explicit,
revision-checked approval.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from dataclasses import asdict, dataclass
from typing import Any, Protocol

_ID = re.compile(r"^[0-9a-f]{64}$")
_OFFICIAL_IMAGE = re.compile(r"^(?:docker\.io/library/)?nextcloud(?::[^/@]+|@sha256:[0-9a-f]{64})?$")


class AttachmentError(ValueError):
    """Discovery, selection or inspection cannot safely identify one target."""


class ReadOnlyDockerTransport(Protocol):
    def info(self) -> dict[str, Any]: ...
    def containers(self) -> list[dict[str, Any]]: ...
    def inspect(self, container_id: str) -> dict[str, Any]: ...
    def configuration_stat(self, container_id: str, path: str) -> dict[str, Any]: ...


class DockerCliTransport:
    """Small subprocess transport with a fixed read-only Docker command set."""

    def __init__(self, executable: str = "docker", timeout: int = 15):
        self.executable = executable
        self.timeout = timeout

    def _run(self, args: list[str]) -> str:
        result = subprocess.run([self.executable, *args], check=False, capture_output=True,
                                text=True, timeout=self.timeout)
        if result.returncode:
            raise AttachmentError("Docker read-only query failed")
        return result.stdout

    def info(self) -> dict[str, Any]:
        return json.loads(self._run(["info", "--format", "{{json .}}" ]))

    def containers(self) -> list[dict[str, Any]]:
        output = self._run(["ps", "-a", "--no-trunc", "--format", "{{json .}}"])
        try:
            return [json.loads(line) for line in output.splitlines() if line.strip()]
        except json.JSONDecodeError as exc:
            raise AttachmentError("Docker returned malformed container listing") from exc

    def inspect(self, container_id: str) -> dict[str, Any]:
        if not _ID.fullmatch(container_id):
            raise AttachmentError("container locator must be an exact full container ID")
        rows = json.loads(self._run(["inspect", container_id]))
        if type(rows) is not list or len(rows) != 1 or type(rows[0]) is not dict:
            raise AttachmentError("Docker inspect did not return one exact container")
        return rows[0]

    def configuration_stat(self, container_id: str, path: str) -> dict[str, Any]:
        if not _ID.fullmatch(container_id) or path != "/var/www/html/config/config.php":
            raise AttachmentError("configuration stat requires the exact supported target")
        output = self._run(["exec", "--user", "www-data", container_id, "stat",
                            "--format=%F|%i|%s|%Y", "--", path])
        fields = output.rstrip("\r\n").split("|")
        if len(fields) != 4:
            raise AttachmentError("configuration target stat returned malformed evidence")
        try:
            return {"type": fields[0], "inode": int(fields[1]),
                    "size": int(fields[2]), "mtime": int(fields[3])}
        except ValueError as exc:
            raise AttachmentError("configuration target stat returned malformed evidence") from exc


@dataclass(frozen=True)
class Candidate:
    container_id: str
    name: str
    image: str
    project: str
    service: str
    created: str
    daemon_id: str
    image_id: str | None


class NextcloudAttachmentProvider:
    """Deterministic, read-only Docker discovery for official Nextcloud services."""

    provider_id = "nextcloud_docker.attachment"

    def __init__(self, transport: ReadOnlyDockerTransport, *, active: bool = True,
                 version: str = "1"):
        self.transport = transport
        self.active = active
        self.version = version

    @property
    def available(self) -> bool:
        return self.active and isinstance(self.version, str) and bool(self.version.strip())

    def _ready(self) -> str:
        if not self.active:
            raise AttachmentError("Nextcloud attachment provider is disabled")
        if not isinstance(self.version, str) or not self.version.strip():
            raise AttachmentError("Nextcloud attachment provider version is unavailable")
        info = self.transport.info()
        daemon_id = info.get("ID") or info.get("Id")
        if not isinstance(daemon_id, str) or not daemon_id.strip():
            raise AttachmentError("Docker daemon identity is unavailable")
        return daemon_id.strip()

    def discover(self, locator: str | None = None) -> list[dict[str, Any]]:
        if locator is not None and (not isinstance(locator, str) or not _ID.fullmatch(locator.lower())):
            raise AttachmentError("explicit locator must be an exact full container ID")
        daemon_id = self._ready()
        found: list[Candidate] = []
        for row in self.transport.containers():
            raw_id = row.get("ID") or row.get("Id")
            if not isinstance(raw_id, str):
                continue
            cid = raw_id.lower()
            if not _ID.fullmatch(cid):
                continue
            raw = self.transport.inspect(cid)
            config = raw.get("Config") or {}
            labels = config.get("Labels") or {}
            image = config.get("Image") or row.get("Image") or ""
            if not isinstance(image, str) or not _OFFICIAL_IMAGE.fullmatch(image.lower()):
                continue
            project = labels.get("com.docker.compose.project")
            service = labels.get("com.docker.compose.service")
            # Compose metadata is mandatory candidate evidence; name alone is not identity.
            if not isinstance(project, str) or not project.strip() or not isinstance(service, str) or not service.strip():
                continue
            created = raw.get("Created")
            if not isinstance(created, str) or not created.strip():
                continue
            name = raw.get("Name") or row.get("Names") or ""
            name = name.lstrip("/") if isinstance(name, str) else ""
            image_id = raw.get("Image")
            if not isinstance(image_id, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
                continue
            found.append(Candidate(cid, name, image, project.strip(), service.strip(), created,
                                   daemon_id, image_id))
        candidates = sorted(found, key=lambda c: (c.project, c.service, c.container_id))
        if locator is not None:
            candidates = [candidate for candidate in candidates if candidate.container_id == locator.lower()]
        return [asdict(candidate) for candidate in candidates]

    def select(self, candidates: list[dict[str, Any]] | None = None, *, locator: str | None = None) -> dict[str, Any]:
        candidates = self.discover() if candidates is None else list(candidates)
        if locator is not None:
            if not isinstance(locator, str) or not _ID.fullmatch(locator.lower()):
                raise AttachmentError("explicit locator must be an exact full container ID")
            matches = [candidate for candidate in candidates if candidate.get("container_id") == locator.lower()]
            if len(matches) != 1:
                raise AttachmentError("explicit container locator did not identify one Nextcloud candidate")
            return matches[0]
        if not candidates:
            raise AttachmentError("no matching Nextcloud deployment candidate was found")
        if len(candidates) != 1:
            raise AttachmentError("multiple Nextcloud deployment candidates require an exact container ID")
        return candidates[0]

    def inspect(self, candidate: dict[str, Any] | Candidate) -> dict[str, Any]:
        if isinstance(candidate, dict):
            try:
                candidate = Candidate(**candidate)
            except (TypeError, ValueError) as exc:
                raise AttachmentError("candidate has an invalid frozen shape") from exc
        daemon_id = self._ready()
        if candidate.daemon_id != daemon_id:
            raise AttachmentError("candidate belongs to a different Docker daemon")
        raw = self.transport.inspect(candidate.container_id)
        cid = (raw.get("Id") or "").lower()
        if cid != candidate.container_id or raw.get("Created") != candidate.created:
            raise AttachmentError("candidate container identity or incarnation changed")
        config = raw.get("Config") or {}
        labels = config.get("Labels") or {}
        image = config.get("Image") or ""
        if not _OFFICIAL_IMAGE.fullmatch(image.lower() if isinstance(image, str) else ""):
            raise AttachmentError("selected container no longer has a supported Nextcloud image")
        if labels.get("com.docker.compose.project") != candidate.project or labels.get("com.docker.compose.service") != candidate.service:
            raise AttachmentError("selected container Compose identity changed")
        mounts = raw.get("Mounts") or []
        safe_mounts = []
        for mount in mounts:
            if not isinstance(mount, dict):
                continue
            source, destination = mount.get("Source"), mount.get("Destination")
            if isinstance(source, str) and isinstance(destination, str):
                safe_mounts.append({"type": mount.get("Type"), "source": source,
                                    "destination": destination, "name": mount.get("Name")})
        safe_mounts.sort(key=lambda m: (m["destination"], m["source"], str(m["type"])))
        config_mounts = [m for m in safe_mounts if m["destination"] == "/var/www/html/config"]
        if not config_mounts:
            config_mounts = [m for m in safe_mounts if m["destination"] == "/var/www/html"]
        if len(config_mounts) != 1:
            raise AttachmentError("configuration target is not deterministically identified by supported mount topology")
        config_path = "/var/www/html/config/config.php"
        if any(m["destination"] == config_path for m in safe_mounts):
            raise AttachmentError("configuration file mount override requires a separate supported target adapter")
        if config_mounts[0]["type"] not in {"bind", "volume"} or not config_mounts[0]["source"]:
            raise AttachmentError("configuration backing mount is unsupported")
        storage_mounts = [m for m in safe_mounts if m["destination"] == "/var/www/html/data"]
        if not storage_mounts:
            storage_mounts = [m for m in safe_mounts if m["destination"] == "/var/www/html"]
        if len(storage_mounts) != 1:
            raise AttachmentError("backing storage is not deterministically identified by supported mount topology")
        if storage_mounts[0]["type"] not in {"bind", "volume"} or not storage_mounts[0]["source"]:
            raise AttachmentError("storage backing mount is unsupported")
        image_id = raw.get("Image")
        if not isinstance(image_id, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
            raise AttachmentError("selected container image identity is unavailable")
        if candidate.image_id and image_id != candidate.image_id:
            raise AttachmentError("selected container image identity changed")
        evidence = {"provider": self.provider_id, "provider_version": self.version,
                    "daemon_id": daemon_id, "container_id": cid, "created": raw["Created"],
                    "compose_project": candidate.project, "compose_service": candidate.service,
                    "image": image, "image_id": image_id}
        logical = {"kind": "nextcloud.application", "project": candidate.project, "service": candidate.service}
        native = {"provider": self.provider_id, "provider_scope": daemon_id,
                  "native_id": cid, "incarnation": raw["Created"]}
        config_target = {**config_mounts[0], "path": "/var/www/html/config/config.php",
                         "availability": "locator_only"}
        try:
            stat_result = self.transport.configuration_stat(cid, config_target["path"])
        except (OSError, subprocess.SubprocessError) as exc:
            raise AttachmentError("configuration target is unavailable for read-only stat") from exc
        if (type(stat_result) is not dict or stat_result.get("type") != "regular file" or
                type(stat_result.get("inode")) is not int or stat_result["inode"] <= 0 or
                type(stat_result.get("size")) is not int or stat_result["size"] < 0 or
                type(stat_result.get("mtime")) is not int or stat_result["mtime"] < 0):
            raise AttachmentError("configuration target is missing, non-regular, or has invalid stat evidence")
        file_evidence = {key: stat_result[key] for key in ("type", "inode", "size", "mtime")}
        config_target["availability"] = "verified_regular_file"
        config_target["file_evidence"] = file_evidence
        topology = {"mounts": safe_mounts, "evidence": evidence,
                    "configuration_file": file_evidence}
        fingerprint = hashlib.sha256(json.dumps(topology, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        storage = {"kind": "storage", **storage_mounts[0]}
        relationships = (
            {"kind": "includes", "subject": "deployment", "target": "application", "role": "application"},
            {"kind": "includes", "subject": "deployment", "target": "runtime", "role": "runtime_realization"},
            {"kind": "includes", "subject": "deployment", "target": "configuration", "role": "configuration_target"},
            {"kind": "includes", "subject": "deployment", "target": "storage", "role": "storage"},
            {"kind": "depends_on", "subject": "application", "target": "runtime", "role": "runtime_realization"},
            {"kind": "uses", "subject": "application", "target": "configuration", "role": "configuration"},
            {"kind": "uses", "subject": "application", "target": "storage", "role": "storage"},
        )
        return {"candidate": asdict(candidate), "fingerprint": fingerprint,
                "application": logical, "native": native,
                "configuration_target": config_target, "storage": storage,
                "relationships": list(relationships), "evidence": evidence}

    def attachment_contract(self, inspection: dict[str, Any]) -> dict[str, Any]:
        """Return the module-owned application and narrow setting contract."""
        candidate = inspection["candidate"]
        return {"provider": self.provider_id, "provider_owner": "nextcloud_docker",
                "provider_version": int(self.version), "application": "nextcloud",
                "application_kind": inspection["application"]["kind"],
                "setting_id": "nextcloud_docker.loglevel",
                "configuration_target": copy_dict(inspection["configuration_target"]),
                "native": copy_dict(inspection["native"]),
                "candidate_id": candidate["container_id"],
                "evidence": copy_dict(inspection["evidence"])}

    def metadata_changes(self, inspection: dict[str, Any]) -> list[dict[str, Any]]:
        """Build Boundary 1 Deployment Service change inputs for explicit approval."""
        contract = self.attachment_contract(inspection)
        candidate = inspection["candidate"]
        provider = {"id": self.provider_id, "owner": "nextcloud_docker",
                    "version": contract["provider_version"]}
        app_native = None
        config = copy_dict(inspection["configuration_target"])
        config_native = {"provider": self.provider_id,
                         "provider_scope": candidate["daemon_id"],
                         "native_id": (config["source"] + "|" + config["destination"] +
                                       "|" + config["path"]),
                         "incarnation": "inode:" + str(config["file_evidence"]["inode"])}
        storage = copy_dict(inspection["storage"])
        storage_native = {"provider": self.provider_id,
                          "provider_scope": candidate["daemon_id"],
                          "native_id": storage["source"],
                          "incarnation": None}
        # The canonical operational History input contains the complete frozen
        # inspection. Deployment relationship evidence is a closed History-ref
        # contract, so this proposal does not invent a reference here.
        evidence: list[dict[str, Any]] = []
        return [
            {"action": "create_deployment", "key": "deployment",
             "label": "Nextcloud " + candidate["project"], "application": "nextcloud",
             "providers": [provider]},
            {"action": "enroll_resource", "key": "application", "kind": "service",
             "label": candidate["project"] + "/" + candidate["service"],
             "origin": "external", "native": app_native},
            {"action": "enroll_resource", "key": "runtime", "kind": "service",
             "label": "Nextcloud container realization", "origin": "external",
             "native": copy_dict(inspection["native"])},
            {"action": "enroll_resource", "key": "configuration", "kind": "configuration_target",
             "label": "Nextcloud configuration target", "origin": "external",
             "native": config_native},
            {"action": "enroll_resource", "key": "storage", "kind": "storage",
             "label": "Nextcloud application storage", "origin": "external",
             "native": storage_native},
            {"action": "add_relationship", "deployment": "$deployment", "kind": "includes",
             "subject": "$deployment", "target": "$application", "role": "application",
             "evidence": evidence},
            {"action": "add_relationship", "deployment": "$deployment", "kind": "includes",
             "subject": "$deployment", "target": "$configuration", "role": "configuration_target",
             "evidence": evidence},
            {"action": "add_relationship", "deployment": "$deployment", "kind": "includes",
             "subject": "$deployment", "target": "$runtime", "role": "runtime_realization",
             "evidence": evidence},
            {"action": "add_relationship", "deployment": "$deployment", "kind": "includes",
             "subject": "$deployment", "target": "$storage", "role": "storage",
             "evidence": evidence},
            {"action": "add_relationship", "deployment": "$deployment", "kind": "depends_on",
             "subject": "$application", "target": "$runtime", "role": "runtime_realization",
             "evidence": evidence},
            {"action": "add_relationship", "deployment": "$deployment", "kind": "uses",
             "subject": "$application", "target": "$configuration", "role": "configuration",
             "evidence": evidence},
            {"action": "add_relationship", "deployment": "$deployment", "kind": "uses",
             "subject": "$application", "target": "$storage", "role": "storage",
             "evidence": evidence},
            {"action": "grant_responsibility", "deployment": "$deployment", "subject": "$configuration",
             "duty": "configuration", "setting_id": contract["setting_id"],
             "providers": [self.provider_id]},
        ]

    def revalidate(self, frozen: dict[str, Any]) -> dict[str, Any]:
        """Re-read the exact frozen native ID and reject any changed evidence."""
        try:
            candidate = frozen["candidate"]
            expected_native = frozen["native"]
            expected_fingerprint = frozen["fingerprint"]
        except (KeyError, TypeError) as exc:
            raise AttachmentError("frozen inspection is incomplete") from exc
        current = self.inspect(candidate)
        if current["fingerprint"] != expected_fingerprint or current["native"] != expected_native:
            raise AttachmentError("frozen Nextcloud candidate evidence is stale")
        return current


def copy_dict(value: dict[str, Any]) -> dict[str, Any]:
    """Copy provider contract data through JSON-shaped objects only."""
    return json.loads(json.dumps(value, sort_keys=True))
