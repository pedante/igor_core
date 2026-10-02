"""Core coordinator for read-only discovery and approved deployment attachment.

Application facts come from an injected provider. This module owns the
application-neutral proposal and asks DeploymentService to persist metadata
only after the canonical dispatcher has recorded explicit approval.
"""
from __future__ import annotations

import copy
import json
import re
import sys
from pathlib import Path
from typing import Any

from deployments import DeploymentError, DeploymentService
from operational_history import HistoryError, OperationalHistory, project_inputs

SOURCE = {"kind": "operator", "id": "core.deployments.adoption", "owner": "core"}


class AttachmentError(ValueError):
    """A candidate, proposal, provider or authorization is unavailable."""


def _compact(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def _load_provider(root: Path, *, active: bool):
    module_dir = root / "modules" / "nextcloud_docker" / "lib"
    module_conf = root / "modules" / "nextcloud_docker" / "module.conf"
    try:
        lines = module_conf.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        raise AttachmentError("attachment provider package metadata unavailable") from exc
    section, package_fields = "", {}
    for raw in lines:
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if section == "module" and "=" in line:
            key, value = (part.strip() for part in line.split("=", 1))
            if key in {"name", "version"}:
                if key in package_fields:
                    raise AttachmentError("attachment provider package metadata is malformed")
                package_fields[key] = value
    if package_fields.get("name") != "nextcloud_docker":
        raise AttachmentError("attachment provider package identity changed")
    package_version = package_fields.get("version", "")
    if not package_version or len(package_version) > 64:
        raise AttachmentError("attachment provider package version unavailable")
    policy = root / "config" / "modules.conf"
    if policy.is_symlink():
        raise AttachmentError("attachment provider policy unavailable")
    try:
        lines = policy.read_text(encoding="utf-8").splitlines() if policy.exists() else []
    except (OSError, UnicodeError) as exc:
        raise AttachmentError("attachment provider policy unavailable") from exc
    seen, explicitly_enabled = set(), None
    for raw in lines:
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        match = re.fullmatch(r"([a-z][a-z0-9]*(?:[._-][a-z0-9]+)*)\s*=\s*(enabled|disabled)", line)
        if not match or match.group(1) in seen:
            raise AttachmentError("attachment provider policy is malformed")
        name, state = match.groups()
        seen.add(name)
        if name == "nextcloud_docker":
            explicitly_enabled = state == "enabled"
    # Module API v1 retains the current implicit-enabled compatibility policy.
    active = active and explicitly_enabled is not False
    if not active:
        raise AttachmentError("attachment provider unavailable")
    sys.path.insert(0, str(module_dir))
    try:
        from attachment import DockerCliTransport, NextcloudAttachmentProvider
        return NextcloudAttachmentProvider(DockerCliTransport(), active=active), package_version
    finally:
        try:
            sys.path.remove(str(module_dir))
        except ValueError:
            pass


class DeploymentAttachment:
    """Application-neutral service composition with an injected domain provider."""

    def __init__(self, deployments: DeploymentService, provider: Any, *,
                 provider_module_version: str = "", history: OperationalHistory | None = None):
        self.deployments = deployments
        self.provider = provider
        self.provider_module_version = provider_module_version
        self.history = history or OperationalHistory(deployments.data_dir)

    def discover(self, locator: str | None = None) -> dict:
        if not getattr(self.provider, "available", False):
            raise AttachmentError("attachment provider unavailable")
        try:
            candidates = self.provider.discover(locator)
        except Exception as exc:
            raise AttachmentError(str(exc)) from exc
        return {"provider": self.provider.provider_id, "provider_version": self.provider.version,
                "provider_module_version": self.provider_module_version,
                "candidates": copy.deepcopy(candidates), "selection_required": len(candidates) > 1}

    def propose(self, locator: str) -> dict:
        """Discover, select exactly one locator, inspect, and freeze metadata."""
        if not getattr(self.provider, "available", False):
            raise AttachmentError("attachment provider unavailable")
        try:
            candidates = self.provider.discover()
            candidate = self.provider.select(candidates, locator=locator)
            inspection = self.provider.inspect(candidate)
        except Exception as exc:
            raise AttachmentError(str(exc)) from exc
        if not getattr(self.provider, "available", False):
            raise AttachmentError("attachment provider became unavailable")
        provider_version = self.provider.version
        contract = self.provider.attachment_contract(inspection)
        changes = self.provider.metadata_changes(inspection)
        if not isinstance(contract, dict) or not isinstance(changes, list):
            raise AttachmentError("provider attachment contract is malformed")
        setting_id = contract.get("setting_id")
        if (contract.get("provider") != self.provider.provider_id or
                not isinstance(contract.get("provider_owner"), str) or not contract["provider_owner"] or
                type(contract.get("provider_version")) is not int or
                not isinstance(setting_id, str) or not setting_id):
            raise AttachmentError("provider attachment contract is malformed")
        grants = [change for change in changes if change.get("action") == "grant_responsibility"]
        if (len(grants) != 1 or grants[0].get("duty") != "configuration" or
                grants[0].get("setting_id") != setting_id or
                grants[0].get("providers") != [self.provider.provider_id]):
            raise AttachmentError("provider responsibility exceeds the approved scoped contract")
        responsibility = {"duty": "configuration", "setting_id": setting_id,
                           "supports": ["change", "readback", "recovery"]}
        try:
            metadata = self.deployments.prepare(changes, source=SOURCE)
        except (DeploymentError, OSError) as exc:
            raise AttachmentError(str(exc)) from exc
        return {"schema_version": 1, "action": "adopt", "provider": self.provider.provider_id,
                "provider_version": provider_version, "inspection": copy.deepcopy(inspection),
                "provider_module_version": self.provider_module_version,
                "contract": copy.deepcopy(contract),
                "deployment_proposal": metadata,
                "responsibility": copy.deepcopy(responsibility),
                "expected_revision": metadata["expected_revision"],
                "expected_state": metadata["expected_state"], "expected_epoch": metadata["epoch"],
                "expected_registry_availability": "available"}

    def _authorize(self, operation_id: str, capability_id: str, serialized_input: str) -> bool:
        try:
            episode = self.history.inspect(operation_id)
        except (HistoryError, OSError):
            return False
        try:
            expected_inputs = project_inputs(capability_id, {"proposal": serialized_input})
        except (HistoryError, json.JSONDecodeError):
            return False
        return bool(episode.get("lifecycle") == "running" and
                    episode.get("approval", {}).get("result") == "approved" and
                    episode.get("capability") == {"id": capability_id, "version": 1} and
                    episode.get("provider", {}).get("id") == "core" and
                    episode.get("provider", {}).get("owner") == "core" and
                    episode.get("inputs") == expected_inputs and
                    episode.get("execution_status") == "running")

    def initialize(self, proposal_document: str, operation_id: str) -> dict:
        if proposal_document != "{}":
            raise AttachmentError("registry initialization takes no mutable proposal")
        if not self._authorize(operation_id, "core.deployments.initialize", proposal_document):
            raise AttachmentError("registry initialization requires explicit approved History episode")
        service = DeploymentService(self.deployments.data_dir,
                                   authorize=lambda request: request.get("action") == "initialize" and
                                   self._authorize(operation_id, "core.deployments.initialize", proposal_document))
        status = service.initialize(source=SOURCE)
        return {"operation_id": operation_id, "transition": "initialize", "registry": status,
                "metadata_only": True}

    def adopt(self, proposal_document: str, operation_id: str) -> dict:
        proposal = json.loads(proposal_document)
        if proposal.get("action") != "adopt" or proposal.get("schema_version") != 1:
            raise AttachmentError("invalid adoption proposal")
        if (not getattr(self.provider, "available", False) or
                self.provider.version != proposal.get("provider_version") or
                self.provider_module_version != proposal.get("provider_module_version")):
            raise AttachmentError("attachment provider unavailable or changed")
        current = self.provider.revalidate(proposal["inspection"])
        try:
            if current != proposal["inspection"]:
                raise AttachmentError("candidate evidence changed after proposal")
            fresh = self.propose(proposal["inspection"]["candidate"]["container_id"])
        except Exception as exc:
            if isinstance(exc, AttachmentError):
                raise
            raise AttachmentError(str(exc)) from exc
        if _proposal_semantics(fresh) != _proposal_semantics(proposal):
            raise AttachmentError("adoption proposal became stale")
        # The adapter passes the exact serialized dispatcher inputs. A hand-built
        # JSON approved flag is never authority.
        if not self._authorize(operation_id, "core.deployments.adopt", proposal_document):
            raise AttachmentError("adoption requires explicit approved History episode")
        service = DeploymentService(self.deployments.data_dir,
                                   authorize=lambda request: request.get("action") == "commit" and
                                   request.get("operation_id") == operation_id and
                                   self._authorize(operation_id, "core.deployments.adopt", proposal_document),
                                   reference_resolver=self.deployments.reference_resolver)
        result = service.commit(proposal["deployment_proposal"], operation_id=operation_id)
        deployment_ref = proposal["deployment_proposal"]["changes"][0]["reference"]
        projection = service.inspect(deployment_ref)
        return {"operation_id": operation_id, "transition": "adopt", "metadata": result,
                "deployment": projection, "verification": {"status": "committed_pending_independent_check",
                "source": "deployment_service", "metadata_only": True}, "application_mutation": "none"}

    def propose_release(self, deployment_id: str) -> dict:
        projection = self.deployments.inspect(deployment_id)
        responsible_providers = {row["id"] for row in projection["identity"]["providers"]}
        changes = [{"action": "release_responsibility", "reference": row["reference"],
                    "disposition": "retained_external"}
                   for row in projection["responsibilities"]
                   if row["lifecycle"] == "active" and row["duty"] == "configuration" and
                   row["setting_id"] is not None and responsible_providers.intersection(row["providers"])]
        if not changes:
            raise AttachmentError("no active scoped responsibility to release")
        metadata = self.deployments.prepare(changes, source=SOURCE)
        return {"schema_version": 1, "action": "release", "deployment_id": deployment_id,
                "deployment_proposal": metadata, "expected_revision": metadata["expected_revision"],
                "expected_state": metadata["expected_state"], "detach": "not_certified",
                "resources_retained": projection["resources"]}

    def release(self, proposal_document: str, operation_id: str) -> dict:
        proposal = json.loads(proposal_document)
        if proposal.get("action") != "release" or proposal.get("schema_version") != 1:
            raise AttachmentError("invalid release proposal")
        if self.propose_release(proposal["deployment_id"]) != proposal:
            raise AttachmentError("release proposal became stale")
        if not self._authorize(operation_id, "core.deployments.release", proposal_document):
            raise AttachmentError("release requires explicit approved History episode")
        service = DeploymentService(self.deployments.data_dir,
                                   authorize=lambda request: request.get("action") == "commit" and
                                   request.get("operation_id") == operation_id and
                                   self._authorize(operation_id, "core.deployments.release", proposal_document),
                                   reference_resolver=self.deployments.reference_resolver)
        result = service.commit(proposal["deployment_proposal"], operation_id=operation_id)
        projection = service.inspect(proposal["deployment_id"])
        return {"operation_id": operation_id, "transition": "release", "metadata": result,
                "deployment": projection, "application_mutation": "none",
                "detach": {"status": "not_certified", "resources_retained": projection["resources"]}}

    def preflight(self, proposal_document: str) -> dict:
        proposal = json.loads(proposal_document)
        if proposal.get("action") == "adopt":
            if (not getattr(self.provider, "available", False) or
                    self.provider.version != proposal.get("provider_version") or
                    self.provider_module_version != proposal.get("provider_module_version")):
                raise AttachmentError("attachment provider unavailable or changed")
            try:
                if self.provider.revalidate(proposal["inspection"]) != proposal["inspection"]:
                    raise AttachmentError("candidate evidence changed after proposal")
                fresh = self.propose(proposal["inspection"]["candidate"]["container_id"])
            except Exception as exc:
                if isinstance(exc, AttachmentError):
                    raise
                raise AttachmentError(str(exc)) from exc
            if _proposal_semantics(fresh) != _proposal_semantics(proposal):
                raise AttachmentError("adoption proposal became stale")
            return {"status": "current", "provider": proposal["provider"]}
        if proposal.get("action") == "release":
            if _proposal_semantics(self.propose_release(proposal["deployment_id"])) != _proposal_semantics(proposal):
                raise AttachmentError("release proposal became stale")
            return {"status": "current", "provider": "core"}
        raise AttachmentError("unsupported deployment proposal")


def capability_records(provider_active: bool) -> list[dict]:
    rows = []
    definitions = [
        ("core.deployments.discover", "READ", {"locator": {"type": "string", "maxLength": 128}}, [],
         "Discover existing Nextcloud candidates; no metadata is written.", "not_applicable"),
        ("core.deployments.propose", "READ", {"locator": {"type": "string", "maxLength": 128}}, ["locator"],
         "Inspect an exact candidate and prepare an adoption proposal.", "not_applicable"),
        ("core.deployments.release.propose", "READ", {"deployment_id": {"type": "object_id"}}, ["deployment_id"],
         "Prepare a scoped responsibility release proposal.", "not_applicable"),
        ("core.deployments.initialize", "CHANGE", {"proposal": {"type": "string", "maxLength": 4096}}, ["proposal"],
         "Initialize the Igor deployment registry after explicit approval.", "reversible"),
        ("core.deployments.adopt", "CHANGE", {"proposal": {"type": "string", "maxLength": 262144}}, ["proposal"],
         "Attach an existing deployment and accept only scoped configuration responsibility.", "reversible"),
        ("core.deployments.release", "CHANGE", {"proposal": {"type": "string", "maxLength": 262144}}, ["proposal"],
         "Release scoped deployment responsibility while retaining resources and identity.", "reversible"),
    ]
    for ident, tier, properties, required, description, recovery in definitions:
        active = ident in {"core.deployments.initialize", "core.deployments.release",
                           "core.deployments.release.propose"} or provider_active
        verification = "deployment_metadata_revision" if tier == "CHANGE" else "none"
        preconditions = ([{"kind": "deployment_proposal_current"}]
                         if ident in {"core.deployments.adopt", "core.deployments.release"} else [])
        descriptor = {"kind": "capability", "id": ident, "handler": "core_deployment_attachment_adapter",
                      "capability_version": 1, "description": description,
                      "inputs": {"properties": properties, "required": required, "additionalProperties": False},
                      "safety": {"tier": tier}, "privilege": "none", "preconditions": preconditions,
                      "verification": {"kind": verification, "required": tier == "CHANGE"},
                      "recovery": {"class": recovery}, "affects": ["installation:local"]}
        rows.append({"id": ident, "owner": "core", "provider": "core", "source": "core.deployments.attachment.v1",
                     "availability": "active" if active else "inactive",
                     "unavailable_reason": None if active else "attachment_provider_inactive", "descriptor": descriptor})
    return rows


def cli(action: str) -> int:
    """Canonical dispatcher adapter; direct public CLI remains read-only."""
    try:
        request = json.load(sys.stdin)
        root = Path(request["igor_dir"]).resolve()
        data = Path(request["data_dir"])
        active = bool(request.get("provider_active"))
        service = DeploymentService(data)
        operation_id = request.get("operation_id", "")
        proposal_action = None
        if action in {"verify", "preflight"} and isinstance(request.get("proposal"), str):
            try:
                proposal_action = json.loads(request["proposal"]).get("action")
            except (ValueError, AttributeError):
                proposal_action = None
        needs_provider = (action in {"discover", "propose", "adopt"} or
                          (action in {"verify", "preflight"} and proposal_action == "adopt"))
        if needs_provider:
            provider, package_version = _load_provider(root, active=active)
            if not provider.available:
                raise AttachmentError("attachment provider unavailable")
        else:
            provider, package_version = None, ""
        coordinator = DeploymentAttachment(service, provider, provider_module_version=package_version)
        if action == "discover":
            result = coordinator.discover(request.get("locator"))
        elif action == "propose":
            result = coordinator.propose(request["locator"])
        elif action == "release-propose":
            result = coordinator.propose_release(request["deployment_id"])
        elif action == "initialize":
            result = coordinator.initialize(request["proposal"], operation_id)
        elif action == "adopt":
            result = coordinator.adopt(request["proposal"], operation_id)
        elif action == "release":
            result = coordinator.release(request["proposal"], operation_id)
        elif action == "verify":
            result = verify_result(request["proposal"], request["execution_result"], service, provider)
        elif action == "preflight":
            result = coordinator.preflight(request["proposal"])
        else:
            raise AttachmentError("unsupported deployment attachment action")
        print(_compact(result))
        return 0
    except (AttachmentError, DeploymentError, HistoryError, OSError, KeyError, TypeError,
            ValueError, json.JSONDecodeError) as exc:
        print("deployment attachment unavailable: " + str(exc), file=sys.stderr)
        return 1


def verify_result(proposal_document: str, execution_result: str, service: DeploymentService,
                  provider: Any) -> dict:
    proposal = json.loads(proposal_document)
    result = json.loads(execution_result) if isinstance(execution_result, str) else execution_result
    if result.get("transition") == "initialize":
        status = service.status()
        if status["availability"] != "available":
            raise AttachmentError("deployment registry initialization verification failed")
        return {"source": "deployment_service", "status": "verified",
                "revision": status["revision"], "metadata_only": True}
    if proposal.get("action") == "adopt":
        deployment = service.inspect(proposal["deployment_proposal"]["changes"][0]["reference"])
        if not getattr(provider, "available", False):
            raise AttachmentError("provider unavailable for independent verification")
        current = provider.revalidate(proposal["inspection"])
        metadata_result = result.get("metadata", {})
        status = service.status()
        expected_revision = proposal["expected_revision"] + 1
        if (current != proposal["inspection"] or deployment["identity"]["lifecycle"] != "known" or
                metadata_result.get("revision") != expected_revision or status["revision"] != expected_revision or
                deployment["identity"]["revision"] != expected_revision):
            raise AttachmentError("adoption verification failed")
        changes = proposal["deployment_proposal"]["changes"]
        expected_resources = {tuple(change["reference"].items()) for change in changes
                              if change["action"] == "enroll_resource"}
        actual_resources = {tuple(row["reference"].items()) for row in deployment["resources"]}
        if expected_resources != actual_resources:
            raise AttachmentError("adoption resource verification failed")
        by_ref = {tuple(row["reference"].items()): row for row in deployment["relationships"]}
        for change in (row for row in changes if row["action"] == "add_relationship"):
            actual = by_ref.get(tuple(change["reference"].items()))
            if actual is None or any(actual.get(key) != change.get(key)
                                     for key in ("deployment", "kind", "subject", "target", "role")):
                raise AttachmentError("adoption relationship verification failed")
        expected_grants = [row for row in changes if row["action"] == "grant_responsibility"]
        actual_grants = {tuple(row["reference"].items()): row for row in deployment["responsibilities"]}
        for change in expected_grants:
            actual = actual_grants.get(tuple(change["reference"].items()))
            if actual is None or actual["lifecycle"] != "active" or any(
                    actual.get(key) != change.get(key)
                    for key in ("deployment", "subject", "duty", "setting_id", "providers")):
                raise AttachmentError("adoption responsibility verification failed")
        return {"source": "deployment_service_and_provider", "status": "verified",
                "deployment": deployment["identity"]["reference"], "native": proposal["inspection"]["native"]}
    if proposal.get("action") == "release":
        deployment = service.inspect(proposal["deployment_id"])
        metadata_result = result.get("metadata", {})
        expected_revision = proposal["expected_revision"] + 1
        if metadata_result.get("revision") != expected_revision or service.status()["revision"] != expected_revision:
            raise AttachmentError("release revision verification failed")
        released = [service.inspect(change["reference"])
                    for change in proposal["deployment_proposal"]["changes"]]
        if any(row["lifecycle"] != "released" for row in released):
            raise AttachmentError("responsibility release verification failed")
        if {json.dumps(row, sort_keys=True) for row in deployment["resources"]} != {
                json.dumps(row, sort_keys=True) for row in proposal["resources_retained"]}:
            raise AttachmentError("release resource retention verification failed")
        return {"source": "deployment_service", "status": "verified",
                "deployment": deployment["identity"]["reference"], "detach": "not_certified"}
    raise AttachmentError("unsupported verification proposal")


def _proposal_semantics(value: Any) -> Any:
    """Normalize only newly issued identities; preserve all external references."""
    try:
        changes = value["deployment_proposal"]["changes"]
        aliases = {}
        index = 0
        for change in changes:
            action = change.get("action")
            created = action in {"create_deployment", "enroll_resource", "add_relationship",
                                 "grant_responsibility", "record_claim"}
            reference = change.get("reference")
            if created and isinstance(reference, dict):
                key = (reference.get("scope_id"), reference.get("object_id"))
                if key in aliases:
                    return None
                aliases[key] = {"created_identity": index, "record_type": {
                    "create_deployment": "deployment", "enroll_resource": "resource",
                    "add_relationship": "relationship", "grant_responsibility": "responsibility",
                    "record_claim": "claim"}[action]}
                index += 1
        def visit(item):
            if type(item) is dict:
                if set(item) == {"scope_id", "object_id"}:
                    return aliases.get((item["scope_id"], item["object_id"]), item)
                return {key: visit(child) for key, child in sorted(item.items())}
            if type(item) is list:
                return [visit(child) for child in item]
            return item
        return visit(value)
    except (KeyError, TypeError, AttributeError):
        return None


if __name__ == "__main__":
    try:
        raise SystemExit(cli(sys.argv[1]))
    except (IndexError, ValueError):
        raise SystemExit(2)
