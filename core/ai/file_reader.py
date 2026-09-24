"""Bounded AI file reads with resolved-path checks; no shell interpretation."""

import os
import stat
import sys
from pathlib import Path

MAX_BYTES = 65536
SENSITIVE_DIRS = {"secrets", ".ssh", ".gnupg", "gnupg"}
SENSITIVE_SUFFIXES = {".env", ".key", ".pem", ".crt", ".p12", ".pfx"}


def is_within(path, root):
    return path == root or root in path.parents


def sensitive(path):
    return (
        bool(SENSITIVE_DIRS.intersection(path.parts))
        or path.suffix.lower() in SENSITIVE_SUFFIXES
        or path.name == ".env"
        or path.name.startswith(".env.")
    )


def read_text(mode, base, reports, requested, limit):
    base = Path(base).resolve(strict=True)
    if not requested or "\0" in requested:
        raise ValueError("a file path is required")
    if mode == "report":
        root = Path(reports)
        root = (root if root.is_absolute() else base / root).resolve(strict=True)
        if Path(requested).is_absolute():
            raise ValueError("report filenames must be relative to the reports directory")
        original = root / requested
        path = original.resolve(strict=True)
        if not is_within(path, root):
            raise ValueError("report path escapes the reports directory")
    elif mode == "file":
        original = Path(requested)
        original = original if original.is_absolute() else base / original
        path = original.resolve(strict=True)
        # Preserve the core file validator's supported roots and allow module
        # stack directories exported by the loader, even outside the repository.
        roots = [base, Path("/tmp"), Path("/var/tmp"), Path("/mnt")]
        roots.extend(
            Path(value).resolve()
            for key, value in os.environ.items()
            if value and (key.endswith("_STACK_DIR") or key == "IGOR_STACKS")
        )
        if not any(is_within(path, root) for root in roots):
            raise ValueError("file is outside the supported read directories")
        if sensitive(original) or sensitive(path):
            raise ValueError("credential files cannot be read with this tool")
    else:
        raise ValueError("unknown file reader mode")

    # Nonblocking open prevents a FIFO replacing the validated path from hanging.
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("only regular files can be read")
        # Recheck the opened object, not just the pre-open path (Linux platform).
        opened = Path(os.readlink(f"/proc/self/fd/{stream.fileno()}"))
        if opened != path:
            raise ValueError("file path changed while opening")
        data = stream.read(MAX_BYTES + 1)
    if b"\0" in data:
        raise ValueError("binary files cannot be read with this tool")
    lines = data[:MAX_BYTES].decode("utf-8", errors="replace").splitlines(keepends=True)
    result = "".join(lines[:limit])
    if len(data) > MAX_BYTES or len(lines) > limit:
        result += f"\n[... truncated at {limit} lines or {MAX_BYTES} bytes]"
    return result


def main():
    try:
        mode, base, reports, requested, count = sys.argv[1:]
        limit = int(count)
        if not 1 <= limit <= 100:
            raise ValueError("line limit must be between 1 and 100")
        print(read_text(mode, base, reports, requested, limit), end="")
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"[ERROR: {exc}]", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
