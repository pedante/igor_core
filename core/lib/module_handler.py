"""Bounded Module API v2 leaf invocation; admission and approval belong upstream.

The Python executor can call invoke directly. The remaining shell consumers use
the stdin CLI while their session-local domain-event callbacks are migrated.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import selectors
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from capability_runtime import COLLECTION_RESULT_BYTES, _decode

REQUEST_BYTES = 128 * 1024
RESPONSE_BYTES = 1024 * 1024
DIAGNOSTIC_BYTES = 16 * 1024


class HandlerError(ValueError):
    """A failed invocation without provider-controlled diagnostics."""


class HandlerTimeout(HandlerError):
    pass


class OutputLimit(HandlerError):
    pass


def run_bounded(argv: list[str], request: bytes, *, timeout: float,
                output_limit: int, env: dict[str, str]) -> bytes:
    """Bound both pipes and reap the process group, including on cancellation."""
    deadline = time.monotonic() + timeout
    with tempfile.TemporaryFile() as incoming, selectors.DefaultSelector() as selector:
        incoming.write(request)
        incoming.seek(0)
        process = subprocess.Popen(argv, stdin=incoming, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, env=env, start_new_session=True)
        try:
            selector.register(process.stdout, selectors.EVENT_READ, output_limit)
            selector.register(process.stderr, selectors.EVENT_READ, DIAGNOSTIC_BYTES)
            output = bytearray()
            diagnostic_size = 0
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise HandlerTimeout("handler timed out")
                for key, _ in selector.select(remaining):
                    size = len(output) if key.fileobj is process.stdout else diagnostic_size
                    part = os.read(key.fd, min(65536, key.data - size + 1))
                    if not part:
                        selector.unregister(key.fileobj)
                    elif key.fileobj is process.stdout:
                        output.extend(part)
                        if len(output) > output_limit:
                            raise OutputLimit("handler output limit exceeded")
                    else:
                        diagnostic_size += len(part)
                        if diagnostic_size > DIAGNOSTIC_BYTES:
                            raise HandlerError("handler diagnostic limit exceeded")
            try:
                code = process.wait(timeout=max(0, deadline - time.monotonic()))
            except subprocess.TimeoutExpired as exc:
                raise HandlerTimeout("handler timed out") from exc
            if code:
                raise HandlerError(f"handler exited with status {code}")
            return bytes(output)
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            process.stdout.close()
            process.stderr.close()


def _document(raw: bytes, label: str):
    try:
        return _decode(raw.decode("utf-8"))
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise HandlerError(f"invalid JSON {label}") from exc


def invoke(package: Path, owner: str, handler: str, contribution_id: str,
           timeout: int, inputs: bytes, *, entrypoint: str = "module.sh",
           env: dict[str, str] | None = None, collection: bool = False,
           defer_response_validation: bool = False) -> bytes:
    """Invoke exactly one admitted handler; never interpret arbitrary shell text."""
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]*", owner):
        raise HandlerError("invalid owner")
    if not re.fullmatch(re.escape(owner) + r"__[A-Za-z_][A-Za-z0-9_]*", handler):
        raise HandlerError("handler is outside owner namespace")
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*", contribution_id):
        raise HandlerError("invalid contribution id")
    if type(timeout) is not int or timeout <= 0:
        raise HandlerError("timeout must be a positive integer")
    if len(inputs) > REQUEST_BYTES:
        raise HandlerError("handler input limit exceeded")
    value = _document(inputs, "input")
    if not isinstance(value, dict):
        raise HandlerError("handler input must be a JSON object")
    package = package.resolve(strict=True)
    relative = Path(entrypoint)
    if relative.is_absolute() or ".." in relative.parts:
        raise HandlerError("entrypoint is missing or escapes module package")
    try:
        path = (package / relative).resolve(strict=True)
        if not path.is_relative_to(package) or not path.is_file():
            raise HandlerError("entrypoint is missing or escapes module package")
    except OSError as exc:
        raise HandlerError("entrypoint is missing or escapes module package") from exc

    child_env = dict(os.environ if env is None else env)
    for name in list(child_env):
        if name in {"BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS"} or name.startswith("BASH_FUNC_"):
            del child_env[name]
    child_env["IGOR_PYTHON"] = sys.executable
    deadline = time.monotonic() + timeout
    run_bounded(["bash", "--noprofile", "--norc", "-n", str(path)], b"",
                timeout=timeout, output_limit=DIAGNOSTIC_BYTES, env=child_env)
    script = '''set -e
entrypoint=$1
handler=$2
_IGOR_DOMAIN_REQUEST_DIR=$3
_IGOR_DOMAIN_SCHEMAS_FILE=$4
_IGOR_LOADER_DIR=$5
if [ -n "$_IGOR_DOMAIN_REQUEST_DIR" ]; then
    source -- "$_IGOR_LOADER_DIR/core/lib/domain_event_client.sh"
fi
source -- "$entrypoint"
declare -F "$handler" >/dev/null 2>&1 || exit 127
"$handler"
'''
    argv = ["bash", "--noprofile", "--norc", "-c", script, "_", str(path), handler,
            child_env.get("_IGOR_DOMAIN_REQUEST_DIR", ""),
            child_env.get("_IGOR_DOMAIN_SCHEMAS_FILE", ""),
            child_env.get("_IGOR_LOADER_DIR", "")]
    try:
        request = json.dumps({"api_version": 2, "contribution_id": contribution_id,
                              "input": value}, separators=(",", ":"), allow_nan=False).encode() + b"\n"
    except (ValueError, RecursionError) as exc:
        raise HandlerError("invalid JSON input") from exc
    try:
        response = run_bounded(argv, request, timeout=max(0, deadline - time.monotonic()),
                               output_limit=COLLECTION_RESULT_BYTES if collection else RESPONSE_BYTES,
                               env=child_env)
    except OutputLimit:
        if not collection:
            raise
        response = b'{"status":"error","error":{"code":"collection_limit_exceeded","message":"collection_limit_exceeded"}}'
    if defer_response_validation:
        # The canonical typed-output validator distinguishes execution failure
        # from invalid output; retaining the raw envelope preserves that result.
        return response
    envelope = _document(response, "response")
    if not isinstance(envelope, dict):
        raise HandlerError("response must be a JSON object")
    if envelope.get("status") == "error" and set(envelope) == {"status", "error"}:
        error = envelope["error"]
        if (isinstance(error, dict) and isinstance(error.get("code"), str)
                and isinstance(error.get("message"), str)):
            # Provider prose may contain secrets; only Core-owned errors escape.
            raise HandlerError("handler reported an error")
    if envelope.get("status") != "ok" or set(envelope) != {"status", "result"}:
        raise HandlerError("invalid output envelope")
    return response


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("owner")
    parser.add_argument("handler")
    parser.add_argument("contribution_id")
    parser.add_argument("timeout", type=int)
    parser.add_argument("--entrypoint", default="module.sh")
    parser.add_argument("--collection", action="store_true")
    parser.add_argument("--defer-response-validation", action="store_true")
    args = parser.parse_args()

    def cancelled(_signum, _frame):
        raise HandlerError("handler cancelled")

    signal.signal(signal.SIGTERM, cancelled)
    signal.signal(signal.SIGINT, cancelled)
    try:
        raw = sys.stdin.buffer.read(REQUEST_BYTES + 1)
        response = invoke(args.package, args.owner, args.handler, args.contribution_id,
                          args.timeout, raw, entrypoint=args.entrypoint,
                          collection=args.collection,
                          defer_response_validation=args.defer_response_validation)
        sys.stdout.buffer.write(response)
        return 0
    except HandlerTimeout:
        print("module handler: handler timed out", file=sys.stderr)
        return 124
    except HandlerError as exc:
        print(f"module handler: {exc}", file=sys.stderr)
        return 1
    except (OSError, ValueError):
        print("module handler: invocation unavailable", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
