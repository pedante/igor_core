"""A2 read-only Samba share recognition from one *explicit trusted* local file.

No Samba package installation, service commands, deployment changes, includes,
secrets projection, implicit/default paths, or directory scanning.
The caller must choose and authorize the source path separately; this private
adapter cannot activate a module merely because a file exists.
"""

from __future__ import annotations

import os
import re
import stat
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from resource_recognition import RecognitionError, Recognizer

_SHARE_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}")
_MAX_BYTES = 131072
_UNSUPPORTED = frozenset({"include", "config file", "registry shares", "usershare path"})


def _share_names(text: str) -> list[str]:
    """Recognize only bounded literal sections; never emit parameter values."""
    result: list[str] = []
    all_names: set[str] = set()
    current_section = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("["):
            match = re.fullmatch(r"\[([^\]\[]+)\]", line)
            if not match or not _SHARE_NAME.fullmatch(match.group(1)):
                raise RecognitionError("unsupported Samba section syntax")
            name = match.group(1)
            folded = name.casefold()
            if folded in all_names:
                raise RecognitionError("duplicate Samba share section")
            all_names.add(folded)
            current_section = folded
            if folded in {"homes", "printers"}:
                raise RecognitionError("dynamic Samba sections are not recognized in A2")
            if folded != "global":
                result.append(name)
            continue
        if "=" not in line:
            raise RecognitionError("unsupported Samba configuration line")
        key, _value = line.split("=", 1)
        if key.strip().casefold() in _UNSUPPORTED:
            raise RecognitionError("indirect Samba source requires separate inspection")
        if current_section is None:
            raise RecognitionError("Samba parameter outside explicit section")
        # Never read/return values; include-like sources are explicitly refused.
    return result


class SambaRecognitionAdapter:
    """Trusted Core injects one explicit file path and current module eligibility."""

    def __init__(self, explicit_source: Path, *, clock=None):
        if not isinstance(explicit_source, Path) or not explicit_source.is_absolute():
            raise RecognitionError("Samba requires an explicit absolute source")
        self._source = explicit_source
        self._clock = clock or (lambda: datetime.now(timezone.utc))

    def binding(self, *, active: bool, module_version: str) -> Recognizer:
        return Recognizer("samba", "samba.shares", module_version,
                          "samba.share", active, self.discover)

    def _read(self) -> tuple[str, os.stat_result]:
        flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
        fd = os.open(self._source, flags)
        try:
            before = os.fstat(fd)
            if not stat.S_ISREG(before.st_mode) or not 0 <= before.st_size <= _MAX_BYTES:
                raise RecognitionError("Samba source must be a bounded regular file")
            with os.fdopen(os.dup(fd), "rb") as reader:
                data = reader.read(_MAX_BYTES + 1)
            after = os.fstat(fd)
            if (len(data) > _MAX_BYTES or
                    (before.st_dev, before.st_ino, before.st_mtime_ns, before.st_size) !=
                    (after.st_dev, after.st_ino, after.st_mtime_ns, after.st_size)):
                raise RecognitionError("Samba source changed during inspection")
        finally:
            os.close(fd)
        try:
            return data.decode("utf-8"), after
        except UnicodeDecodeError as exc:
            raise RecognitionError("Samba source encoding unsupported") from exc

    def discover(self, exact_locator: str | None) -> list[dict[str, Any]]:
        if exact_locator is not None and (
                not isinstance(exact_locator, str) or
                not exact_locator.startswith("share:") or
                not _SHARE_NAME.fullmatch(exact_locator[6:])):
            raise RecognitionError("Samba selector must identify one exact literal share")
        text, info = self._read()
        names = _share_names(text)
        now = self._clock()
        if not isinstance(now, datetime) or now.tzinfo is None or now.utcoffset() is None:
            raise RecognitionError("invalid Samba observation clock")
        now = now.astimezone(timezone.utc)
        timestamp = now.isoformat()
        expiry = (now + timedelta(seconds=60)).isoformat()
        # Metadata only: never publish path, raw config, directive values or a
        # hash of potentially secret-bearing configuration bytes.
        source_ref = (f"samba:dev:{info.st_dev}:inode:{info.st_ino}:"
                      f"mtime:{info.st_mtime_ns}:size:{info.st_size}")
        rows: list[dict[str, Any]] = []
        for name in names:
            selector = f"share:{name}"
            if exact_locator is not None and selector != exact_locator:
                continue
            rows.append({
                "candidate_version": 1, "selector": selector,
                "matched_objects": [selector],
                "evidence": [{"source_kind": "provider", "source_ref": source_ref,
                              "observed_at": timestamp}],
                "observed_at": timestamp, "expires_at": expiry,
                "ambiguities": [], "missing_evidence": [],
            })
        return rows

    def inspect_exact(self, selector: str, *, frozen_source_ref: str) -> dict[str, Any]:
        """Recheck source identity and exact selector; still view-only."""
        found = self.discover(selector)
        if len(found) != 1:
            raise RecognitionError("Samba share not observed at selected source")
        if found[0]["evidence"][0]["source_ref"] != frozen_source_ref:
            raise RecognitionError("Samba source evidence changed after recognition")
        return {"selector": selector, "evidence": found[0]["evidence"],
                "observed_at": found[0]["observed_at"]}
