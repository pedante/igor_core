"""Last-mile redaction for transport and operational records; never sources config."""

import json
import os
import re
import sys
from pathlib import Path


def _managed_openrouter():
    root = os.environ.get("IGOR_DIR")
    if not root:
        return None
    lib = Path(__file__).resolve().parents[1] / "lib"
    if str(lib) not in sys.path:
        sys.path.insert(0, str(lib))
    from secret_refs import ManagedOpenRouterSecret
    location = Path(root)
    override = os.environ.get("IGOR_SECRETS_DIR")
    if override and not Path(override).is_absolute():
        raise ValueError("managed secret root unavailable")
    return ManagedOpenRouterSecret(
        Path(override or str(location / "secrets")),
        Path(os.environ.get("IGOR_DATA_DIR", str(location / "data"))))


def managed_openrouter_cutover():
    service = _managed_openrouter()
    if service is None:
        return False
    from configuration import ConfigurationService
    return service.cutover_marker() or ConfigurationService(
        service.data_root, secret_service=service).openrouter_source_fence()


def redactions():
    """Reuse reversible session tokens, then cover stored and environment secrets."""
    pairs = {}
    try:
        cutover = managed_openrouter_cutover()
    except ValueError:
        cutover = True
    try:
        pairs.update(json.loads(os.environ.get("IGOR_AI_SCRUB_MAP", "{}")))
    except (ValueError, TypeError):
        pass
    root = Path(os.environ.get("IGOR_SECRETS_DIR",
                               str(Path(os.environ.get("IGOR_DIR", ".")) / "secrets")))
    for path in sorted(root.glob("*")):
        if path.suffix not in {".env", ".key"} or path.is_symlink() or not path.is_file():
            continue
        if cutover and path.name in {"openrouter.key", "or.key", "nexus.key"}:
            continue
        for line in path.read_text(errors="replace").splitlines():
            if path.suffix == ".key":
                value = line.strip()
            else:
                match = re.match(r"(?:export\s+)?[A-Za-z_]\w*\s*=\s*(.*)", line.strip())
                if not match:
                    continue
                if cutover and re.match(r"(?:export\s+)?(?:OPENROUTER_API_KEY|OR_API_KEY|NEXUS_API_KEY)\s*=", line.strip()):
                    continue
                value = match.group(1).strip().strip("\"'")
            if len(value) >= 4 and not value.startswith("[IGOR:"):
                pairs.setdefault(value, "[REDACTED]")
    for key, value in os.environ.items():
        if cutover and key in {"OPENROUTER_API_KEY", "OR_API_KEY", "NEXUS_API_KEY"}:
            continue
        if re.search(r"(?:PASSWORD|PASSWD|SECRET|TOKEN|API_KEY)$", key) and len(value) >= 4:
            pairs[value] = "[REDACTED]"
    return sorted(((k, v) for k, v in pairs.items() if isinstance(k, str)
                   and k and isinstance(v, str)), key=lambda pair: -len(pair[0]))


def sanitize_selected_text(text):
    service = _managed_openrouter()
    if service is not None:
        text = service.sanitize(text, operation_id=os.environ.get("IGOR_AI_REQUEST_ID") or "local-redaction")
    return text


def sanitize_selected_data(value):
    if isinstance(value, str):
        return sanitize_selected_text(value)
    if isinstance(value, list):
        return [sanitize_selected_data(item) for item in value]
    if isinstance(value, dict):
        return {key: sanitize_selected_data(item) for key, item in value.items()}
    return value


def launch_private_transport(*, openrouter=False, staged=False):
    """Exec the HTTP consumer with selected material absent at process birth.

    Direct engine callers can bypass the shell's map export. Project inherited
    data through the same Secret Service before exec, retaining safe reversible
    mappings. No material is returned by this boundary or used as authentication.
    """
    service = _managed_openrouter()
    if service is None:
        return
    project = service._response_projector(
        operation_id=os.environ.get("IGOR_AI_REQUEST_ID") or "transport-launch")

    def private(value):
        return project(value.encode("utf-8"), final=True).decode("utf-8")

    environment = {name: private(value) for name, value in os.environ.items()
                   if private(name) == name}
    raw_map = os.environ.get("IGOR_AI_SCRUB_MAP")
    if raw_map is not None:
        try:
            pairs = json.loads(raw_map)
            if isinstance(pairs, dict):
                environment["IGOR_AI_SCRUB_MAP"] = json.dumps({
                    key: value for key, value in pairs.items()
                    if isinstance(value, str) and private(key) == key
                    and private(value) == value})
        except (ValueError, TypeError):
            # Malformed maps retain existing redaction's fail-safe handling.
            pass
    # Approved staged/recovery commands consume a private ticket, including
    # before cutover or with damaged catalog evidence. Alias removal cannot
    # depend on that catalog; actual access still requires the owner's checks.
    if staged or managed_openrouter_cutover():
        for name in ("OPENROUTER_API_KEY", "OR_API_KEY"):
            environment.pop(name, None)
        if openrouter:
            environment.pop("NEXUS_API_KEY", None)
    if environment != dict(os.environ):
        # Preserve interpreter flags, argv, pipes and PID. The preflight process
        # never opens HTTP; only the clean exec image can release authentication.
        os.execve(sys.executable, [sys.executable, *sys.orig_argv[1:]], environment)


def scrub_text(text, pairs=None):
    text = sanitize_selected_text(text)
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


if __name__ == "__main__":
    # Internal projection bridge: input/output only on protected process pipes.
    try:
        print(sanitize_selected_text(sys.stdin.read()), end="")
    except (OSError, ValueError):
        raise SystemExit(1) from None
