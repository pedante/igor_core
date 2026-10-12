"""Byte ceiling around the existing Module API Bash handler process."""

import json
import os
import selectors
import signal
import subprocess
import sys
import time

from capability_runtime import COLLECTION_RESULT_BYTES


def main():
    process = subprocess.Popen(sys.argv[1:], stdin=sys.stdin.buffer, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    seconds = min(30, float(sys.argv[3].rstrip("s"))) if sys.argv[1] == "timeout" else 30
    deadline = time.monotonic() + seconds
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    try:
        raw = bytearray()
        while len(raw) <= COLLECTION_RESULT_BYTES:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                return 124
            part = os.read(process.stdout.fileno(), min(65536, COLLECTION_RESULT_BYTES + 1 - len(raw)))
            if not part:
                break
            raw.extend(part)
        if len(raw) > COLLECTION_RESULT_BYTES:
            os.killpg(process.pid, signal.SIGKILL)
            print(json.dumps({"status": "error", "error": {"code": "collection_limit_exceeded",
                                                         "message": "collection_limit_exceeded"}}))
            return 0
        try:
            rc = process.wait(timeout=max(0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            return 124
        if rc:
            return rc
        sys.stdout.buffer.write(raw)
        return 0
    finally:
        selector.close()
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        process.stdout.close()


if __name__ == "__main__":
    raise SystemExit(main())
