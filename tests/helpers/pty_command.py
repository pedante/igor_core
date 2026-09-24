"""Run one shell command on a pseudo-terminal and feed deterministic input."""

import errno
import os
import pty
import select
import signal
import sys
import time


def main() -> int:
    command = sys.argv[1]
    input_data = sys.argv[2].encode()
    deadline = time.monotonic() + 20
    pid, fd = pty.fork()
    if pid == 0:
        os.execl("/bin/bash", "bash", "-c", command)

    offset = 0
    try:
        while True:
            if time.monotonic() >= deadline:
                os.killpg(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
                return 124
            readable, _, _ = select.select([fd], [], [], 0.2)
            if fd in readable:
                try:
                    data = os.read(fd, 4096)
                except OSError as exc:
                    if exc.errno != errno.EIO:
                        raise
                    break
                if not data:
                    break
                if data:
                    os.write(sys.stdout.fileno(), data)
                if offset < len(input_data):
                    offset += os.write(fd, input_data[offset:])
            try:
                waited, status = os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                return 1
            if waited:
                return os.waitstatus_to_exitcode(status)
    finally:
        os.close(fd)

    _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status)


if __name__ == "__main__":
    raise SystemExit(main())
