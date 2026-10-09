"""Reviewed OpenRouter HTTPS consumers; credential bytes never cross the CLI.

Routing and request policy are owned by the existing AI path. This component
only injects the admitted credential at the final HTTPS authorization boundary.
"""

from __future__ import annotations

import http.client
import json
import math
import os
import ssl
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

from configuration import ConfigurationService
from privacy import _managed_openrouter
from secret_refs import SecretReferenceError


class _PrivateResponse:
    """Streaming output contains no admitted or retained credential literal."""

    def __init__(self, response, key, service):
        self.status = response.status
        self._response = response
        if service is not None:
            self._project = service._response_projector(
                operation_id=os.environ.get("IGOR_AI_REQUEST_ID") or "credential-query",
                admitted=key.encode("ascii"))
        else:
            # Legacy compatibility also keeps the admitted value private.
            self._project = None
        self._key = key.encode("ascii") if service is None else b""
        self._buffer = b""
        self._eof = False
        self._size = 0

    def read(self, amount=-1):
        if amount == 0:
            return b""
        while not self._eof and (amount < 0 or not self._buffer or self._project is None):
            part = self._response.read(65536 if amount < 0 else max(1, amount))
            self._size += len(part)
            if self._size > 8 * 1024 * 1024:
                raise SecretReferenceError("OpenRouter response exceeds private projection limit")
            self._eof = not part
            if self._project is not None:
                self._buffer += self._project(part, final=self._eof)
            else:
                self._buffer += part
                if self._eof:
                    self._buffer = self._buffer.replace(self._key, b"[REDACTED]")
                else:
                    # Legacy output is buffered so a split key cannot escape.
                    continue
            if amount >= 0 and self._buffer:
                break
        end = len(self._buffer) if amount < 0 else amount
        value, self._buffer = self._buffer[:end], self._buffer[end:]
        return value


def binding():
    service = _managed_openrouter()
    if service is None:
        return None, None, False
    configuration = ConfigurationService(service.data_root, secret_service=service)
    desired = configuration.resolve_openrouter_credential()
    managed = service.cutover_marker() or desired["reference"] is not None
    return service, configuration, managed


def request(method, path, *, body=None, headers=None, consumer="transport",
            legacy_key=None, staged=None):
    """Create the connection only after mandatory private access audit commits."""
    operation_id = (staged[2] if staged else
                    os.environ.get("IGOR_AI_REQUEST_ID") or uuid.uuid4().hex)
    service, configuration, managed = binding() if not staged else (staged[0], None, True)
    if managed:
        # Inherited values are explicit import input only. They must not follow
        # an approved private stage into validation or any managed consumer.
        for name in ("OPENROUTER_API_KEY", "OR_API_KEY", "NEXUS_API_KEY"):
            os.environ.pop(name, None)

    def send(stream):
        key = stream.read().decode("ascii") if stream is not None else legacy_key
        if not key:
            raise SecretReferenceError("OpenRouter credential unavailable")
        selected_headers = dict(headers or {})
        selected_headers["Authorization"] = "Bearer " + key
        connection = http.client.HTTPSConnection("openrouter.ai", context=ssl.create_default_context(), timeout=90)
        try:
            connection.request(method, path, body=body, headers=selected_headers)
            response = connection.getresponse()
            return connection, _PrivateResponse(response, key, service if managed else None)
        except (OSError, ValueError, TypeError, http.client.HTTPException):
            connection.close()
            raise SecretReferenceError("OpenRouter connection unavailable") from None

    if staged:
        if len(staged) > 3 and staged[3]:
            connection, response = service.use_recovery_validation(staged[1], operation_id, send)
            if response.status == 200:
                service._validated_recovery = (staged[1], operation_id)
        else:
            connection, response = service.use_staged_for_validation(
                staged[1], operation_id=operation_id, consume=send)
    elif managed:
        desired = configuration.resolve_openrouter_credential()
        connection, response = service.use(
            desired["reference"] or "unavailable", owner="core", purpose="auth",
            consumer=consumer, operation_id=operation_id, configuration=configuration,
            consume=send)
    else:
        connection, response = send(None)
    if managed and not (staged and len(staged) > 3 and staged[3]):
        try:
            service.observe_response(operation_id=operation_id, consumer=consumer, status=response.status)
        except ValueError:
            connection.close()
            raise SecretReferenceError("OpenRouter credential observation unavailable") from None
    return connection, response


def validate_staged(service, ticket, operation_id, *, recovering=False):
    connection, response = request("GET", "/api/v1/auth/key", consumer="validation",
                                   staged=(service, ticket, operation_id, recovering))
    try:
        return response.status == 200
    finally:
        connection.close()


def validate(legacy_key=None):
    connection, response = request("GET", "/api/v1/auth/key", consumer="validation", legacy_key=legacy_key)
    try:
        return response.status == 200
    finally:
        connection.close()


def balance(legacy_key=None):
    connection, response = request("GET", "/api/v1/auth/key", consumer="balance", legacy_key=legacy_key)
    try:
        if response.status != 200:
            return "unavailable"
        raw = response.read(65537)
        if len(raw) > 65536:
            return "unavailable"
        data = json.loads(raw).get("data", {})
        limit, used = data.get("limit"), data.get("usage", 0)
        if limit is None:
            return "unlimited"
        if (type(limit) not in (int, float) or type(used) not in (int, float) or
                not math.isfinite(limit) or not math.isfinite(used)):
            return "unavailable"
        return f"${max(0, limit - used):.2f} remaining"
    finally:
        connection.close()


def cli():
    action = sys.argv[1] if len(sys.argv) == 2 else ""
    try:
        if action == "validate":
            return 0 if validate() else 1
        if action == "balance":
            print(balance())
            return 0
        if action in {"validate-private", "balance-private"}:
            # Legacy compatibility still uses protected stdin, never argv/env.
            candidate = sys.stdin.buffer.read(16385).decode("ascii").strip()
            if action == "validate-private":
                return 0 if validate(candidate) else 1
            print(balance(candidate))
            return 0
    except (OSError, ValueError, TypeError, http.client.HTTPException):
        if action.startswith("balance"):
            print("unavailable")
        return 1
    return 2


if __name__ == "__main__":
    from privacy import launch_private_transport
    try:
        launch_private_transport(openrouter=True)
    except (OSError, ValueError):
        raise SystemExit(1) from None
    raise SystemExit(cli())
