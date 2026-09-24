"""Last-mile redaction for transport and operational records; never sources config."""

import json
import os
import re
from pathlib import Path


def redactions():
    """Reuse reversible session tokens, then cover stored and environment secrets."""
    pairs = {}
    try:
        pairs.update(json.loads(os.environ.get("IGOR_AI_SCRUB_MAP", "{}")))
    except (ValueError, TypeError):
        pass
    root = Path(os.environ.get("IGOR_DIR", ".")) / "secrets"
    for path in sorted(root.glob("*")):
        if path.suffix not in {".env", ".key"} or path.is_symlink() or not path.is_file():
            continue
        for line in path.read_text(errors="replace").splitlines():
            if path.suffix == ".key":
                value = line.strip()
            else:
                match = re.match(r"(?:export\s+)?[A-Za-z_]\w*\s*=\s*(.*)", line.strip())
                if not match:
                    continue
                value = match.group(1).strip().strip("\"'")
            if len(value) >= 4 and not value.startswith("[IGOR:"):
                pairs.setdefault(value, "[REDACTED]")
    for key, value in os.environ.items():
        if re.search(r"(?:PASSWORD|PASSWD|SECRET|TOKEN|API_KEY)$", key) and len(value) >= 4:
            pairs[value] = "[REDACTED]"
    return sorted(((k, v) for k, v in pairs.items() if isinstance(k, str)
                   and k and isinstance(v, str)), key=lambda pair: -len(pair[0]))


def scrub_text(text, pairs=None):
    for literal, token in redactions() if pairs is None else pairs:
        text = text.replace(literal, token)
    # Do not record terminal escape/control sequences as executable display data.
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)
    text = re.sub(r"(?i)(bearer\s+)[^\s\"']+", r"\1[REDACTED]", text)
    text = re.sub(r"(?i)((?:password|passwd|secret|api[_-]?key|token)\s*[=:]\s*)"
                  r"[^\s,;\"']+", r"\1[REDACTED]", text)
    return text


def scrub_data(value, pairs=None):
    pairs = redactions() if pairs is None else pairs
    if isinstance(value, str):
        return scrub_text(value, pairs)
    if isinstance(value, list):
        return [scrub_data(item, pairs) for item in value]
    if isinstance(value, dict):
        # Protocol keys remain intact; only content/argument values are data.
        return {key: scrub_data(item, pairs) for key, item in value.items()}
    return value
