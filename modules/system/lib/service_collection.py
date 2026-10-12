"""System collection producer over the existing shared platform adapter."""

import os
import subprocess
import sys
from pathlib import Path

CORE_LIB = Path(sys.argv[1])
sys.path.insert(0, str(CORE_LIB))
from capability_runtime import CapabilityError, _decode
from collection_runtime import Snapshots, encoded, read_private, runtime_path


def produce(context):
    adapter = CORE_LIB / "pkg.sh"
    process = subprocess.Popen(["bash", "-c", 'source "$1"; svc_list_query', "_", str(adapter)],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        while True:
            line = process.stdout.readline(1025)
            if not line:
                break
            if len(line) > 1024:
                raise CapabilityError("collection_limit_exceeded")
            fields = line.decode("utf-8", errors="strict").rstrip("\n").split("\t")
            if len(fields) != 3:
                raise CapabilityError("invalid_domain_output")
            unit, active, sub = fields
            yield {"reference": {"scope_id": context["scope_id"], "object_id": "service:systemd:" + unit},
                   "unit": unit, "active_state": active, "sub_state": sub}
        error = process.stderr.read(256).decode("utf-8", errors="replace").strip()
        if process.wait() != 0:
            raise CapabilityError(error if error in {"collection_limit_exceeded", "invalid_domain_output"} else "unavailable")
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait()
        process.stdout.close()
        process.stderr.close()


def main():
    try:
        context = read_private(Path(os.environ["IGOR_COLLECTION_CONTEXT"]), 32768)
        inputs = _decode(sys.stdin.read(8193))
        limit = inputs.get("limit", 50)
        store = Snapshots(runtime_path())
        if "cursor" in inputs:
            result = store.page(context, limit, inputs["cursor"])
        else:
            result = store.build(context, limit, lambda: produce(context))
        print(encoded({"status": "ok", "result": result}).decode())
    except (OSError, ValueError, KeyError):
        # Only these canonical reasons are public; rejected values never escape.
        exc = sys.exc_info()[1]
        code = str(exc) if str(exc) in {"collection_limit_exceeded", "collection_budget_exhausted",
                                      "collection_expired", "invalid_collection_cursor", "invalid_domain_output"} else "unavailable"
        print(encoded({"status": "error", "error": {"code": code, "message": code}}).decode())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
