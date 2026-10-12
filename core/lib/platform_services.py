"""Bounded system-manager inventory adapter used by pkg.sh on Debian/Arch."""

import os
import subprocess
import sys

from capability_runtime import CapabilityError, _validate_value

SOURCE_BYTES = 512 * 1024
SOURCE_ROWS = 1024


def services(timeout: int):
    env = dict(os.environ, LC_ALL="C", SYSTEMD_COLORS="0")
    process = subprocess.Popen(
        ["timeout", "--signal=TERM", f"{timeout}s", "systemctl", "list-units",
         "--type=service", "--all", "--plain", "--no-legend", "--no-pager"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env)
    consumed = count = 0
    seen = set()
    try:
        while True:
            line = process.stdout.readline(min(4097, SOURCE_BYTES - consumed + 1))
            if not line:
                break
            consumed += len(line)
            if consumed > SOURCE_BYTES or len(line) > 4096:
                raise CapabilityError("collection_limit_exceeded")
            text = line.decode("utf-8", errors="strict").rstrip("\n")
            if not text.strip():
                continue
            fields = text.split(None, 4)
            if len(fields) < 4 or fields[1] not in {"loaded", "not-found", "error", "masked", "bad-setting"}:
                raise CapabilityError("invalid_domain_output")
            unit, _, active, sub = fields[:4]
            _validate_value("unit", unit, {"type": "string", "validator": "systemd_unit", "maxLength": 256})
            if not unit.endswith(".service") or unit in seen:
                raise CapabilityError("invalid_domain_output")
            for state in (active, sub):
                if not state or len(state) > 80 or not all(32 < ord(char) < 127 for char in state):
                    raise CapabilityError("invalid_domain_output")
            count += 1
            if count > SOURCE_ROWS:
                raise CapabilityError("collection_limit_exceeded")
            seen.add(unit)
            yield unit, active, sub
        if process.wait() != 0:
            raise CapabilityError("unavailable")
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait()
        process.stdout.close()


def main():
    try:
        for row in services(int(sys.argv[1])):
            print("\t".join(row), flush=True)
    except (OSError, ValueError) as exc:
        reason = str(exc) if str(exc) in {"collection_limit_exceeded", "invalid_domain_output"} else "unavailable"
        print(reason, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
