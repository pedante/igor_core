"""A2 adapter: translate the existing read-only Nextcloud provider into A1 candidates.

The adapter does not load a module, activate it, adopt a deployment, or mutate
Docker. A trusted caller injects the already-admitted Nextcloud provider.
"""

from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from typing import Any

from resource_recognition import RecognitionError, Recognizer

_CONTAINER_ID = re.compile(r"[0-9a-f]{64}")
_COMPOSE_LABEL = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}")
_DAEMON_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9:_.-]{0,127}")


class NextcloudRecognitionAdapter:
    def __init__(self, provider: Any, *, clock=None):
        self._provider = provider
        self._clock = clock or (lambda: datetime.now(timezone.utc))

    def binding(self, *, active: bool, module_version: str) -> Recognizer:
        # Eligibility is determined by the trusted Core caller, not the provider.
        return Recognizer("nextcloud_docker", "nextcloud_docker.attachment",
                          module_version, "nextcloud.application", active,
                          self.discover)

    def discover(self, exact_locator: str | None) -> list[dict[str, Any]]:
        if exact_locator is not None and not _CONTAINER_ID.fullmatch(exact_locator):
            raise RecognitionError("invalid Nextcloud exact container selector")
        candidates = self._provider.discover(exact_locator)
        if type(candidates) is not list:
            raise RecognitionError("invalid Nextcloud provider candidate collection")
        now = self._clock()
        if not isinstance(now, datetime) or now.tzinfo is None or now.utcoffset() is None:
            raise RecognitionError("invalid recognition observation clock")
        now = now.astimezone(timezone.utc)
        timestamp = now.isoformat()
        expiry = (now + timedelta(seconds=60)).isoformat()
        result: list[dict[str, Any]] = []
        for item in candidates:
            if type(item) is not dict:
                raise RecognitionError("invalid Nextcloud candidate")
            cid = item.get("container_id")
            daemon_id = item.get("daemon_id")
            image_id = item.get("image_id")
            project = item.get("project")
            service = item.get("service")
            created = item.get("created")
            if (not isinstance(cid, str) or not _CONTAINER_ID.fullmatch(cid)
                    or not isinstance(daemon_id, str) or not _DAEMON_ID.fullmatch(daemon_id)
                    or not isinstance(image_id, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id)
                    or not isinstance(project, str) or not _COMPOSE_LABEL.fullmatch(project)
                    or not isinstance(service, str) or not _COMPOSE_LABEL.fullmatch(service)
                    or not isinstance(created, str) or not created or len(created) > 80
                    or any(not char.isprintable() for char in created)):
                raise RecognitionError("Nextcloud native identity is unavailable")
            result.append({
                "candidate_version": 1, "selector": cid,
                "matched_objects": [f"container:{cid}", f"compose:{project}/{service}"],
                "evidence": [{"source_kind": "provider", "source_ref": f"docker:{daemon_id}",
                              "observed_at": timestamp}],
                "observed_at": timestamp, "expires_at": expiry,
                "ambiguities": [], "missing_evidence": [],
            })
        return result

    def inspect_exact(self, exact_locator: str) -> dict[str, Any]:
        """Re-enter existing deterministic inspection, *not* adoption."""
        if not isinstance(exact_locator, str) or not _CONTAINER_ID.fullmatch(exact_locator):
            raise RecognitionError("exact full container ID required")
        candidate = self._provider.select(self._provider.discover(), locator=exact_locator)
        return self._provider.inspect(candidate)
