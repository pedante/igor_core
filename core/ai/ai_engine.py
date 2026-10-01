#!/usr/bin/env python3
"""
ai_engine.py — Consolidated Python engine for IGOR AI subsystem.

Modes (dispatched by argv[1]):
  call      — full API round-trip: HTTP stream + parse + validate + emit markers
  append    — append a message to conversation JSON with MAX_MESSAGES trimming
  compress  — progressive context compression of conversation JSON (stdin → stdout)
  validate  — validate a single tool call (NEXUS_TOOL_JSON env var)

All modes write diagnostics/warnings to stderr only.
stdout is reserved for structured output (JSON or markers).
"""

import sys
import os
import json
import re
import base64
import http.client
import ssl
import ipaddress

from request_boundary import prepare as prepare_request
from transactions import TransactionError, trim, validate_history

# ══════════════════════════════════════════════════════════════════════════════
#  SHARED: VALIDATION LOGIC  (used by both call and validate modes)
# ══════════════════════════════════════════════════════════════════════════════

def _validate_ascii(value, field_name):
    if not value:
        return True, None
    try:
        value.encode('ascii')
        return True, None
    except UnicodeEncodeError:
        return False, f"Non-ASCII characters in {field_name}"

def _validate_denylist(command):
    patterns = [
        r'rm\s+-rf', r'mkfs', r'dd\s+if=', r'docker\s+compose\s+down',
        r'\.\/dev\/sdt0',
    ]
    for p in patterns:
        if re.search(p, command):
            return False, "Command matches denylist pattern"
    return True, None

def _validate_no_path_traversal(path):
    if not path:
        return True, None
    norm = os.path.normpath(path)
    if ".." in norm:
        return False, f"Path traversal attempt detected (contains '..')"
    return True, None

def _validate_edit_file(tool):
    path = tool.get("path", tool.get("args", {}).get("path", ""))
    if not path:
        return True, None
    norm = os.path.normpath(path)
    if norm.startswith("..") or "/../" in "/" + norm or norm == "..":
        return False, f"Path traversal attempt: '{path}'"
    for prefix in ("/etc/", "/usr/", "/bin/", "/sbin/", "/boot/", "/sys/", "/proc/"):
        if norm.startswith(prefix):
            return True, f"Writing to system directory: {norm}"
    return True, None

def _validate_container(tool):
    action = tool.get("action", "")
    if action.lower() in ('kill', 'rm', 'prune'):
        return False, f"Dangerous container action '{action}'"
    return True, None

def validate_tool_call(tool):
    """Return (valid: bool, blocked: bool, block_reason: str|None, warnings: list[str])."""
    tool_type = tool.get("tool", tool.get("type", ""))
    valid = True
    blocked = False
    block_reason = None
    warnings = []

    if tool_type in ("host", "execute"):
        cmd = tool.get("cmd", tool.get("command", ""))
        ok, reason = _validate_denylist(cmd)
        if not ok:
            return False, True, reason, []
        ok, reason = _validate_ascii(cmd, "host command")
        if not ok:
            return False, True, reason, []

    elif tool_type == "occ":
        cmd = tool.get("cmd", tool.get("command", ""))
        ok, reason = _validate_ascii(cmd, "occ command")
        if not ok:
            return False, True, reason, []
        ok, reason = _validate_denylist(cmd)
        if not ok:
            return False, True, reason, []

    elif tool_type == "container":
        ok, reason = _validate_container(tool)
        if not ok:
            return False, True, reason, []

    elif tool_type == "edit_file":
        ok, reason = _validate_edit_file(tool)
        if not ok:
            return False, True, reason, []
        if reason:
            warnings.append(reason)

    elif tool_type in ("read_file", "read_report"):
        path = tool.get("path", tool.get("filename", ""))
        ok, reason = _validate_no_path_traversal(path)
        if not ok:
            return False, True, reason, []

    elif tool_type == "run_capability":
        if not isinstance(tool.get("id"), str) or not tool["id"].strip():
            return False, True, "Capability id is required", []
        if not isinstance(tool.get("inputs"), dict):
            return False, True, "Capability inputs must be an object", []
    elif tool_type in ("read_log", "propose_menu_item", "reply", "run_igor_action"):
        pass  # always valid — run_igor_action tier is determined by the capability catalog

    else:
        return False, True, f"Unknown tool type '{tool_type}'", []

    return True, False, None, warnings


# ══════════════════════════════════════════════════════════════════════════════
#  SHARED: SCRATCHPAD + EVIDENCE ENFORCEMENT  (P2-4)
# ══════════════════════════════════════════════════════════════════════════════

_EVIDENCE_REQUIRED_STATUSES = {"fixed", "not_fixed"}
_EVIDENCE_INJECTION_MSG = (
    "[SYSTEM: Status claim rejected — no evidence_ref provided. "
    "Continue investigating.]"
)


def _parse_xml_scratchpad(inner: str) -> dict:
    """Parse scratchpad content in pure-XML format (current default)."""
    sp: dict = {}
    # commands_run: collect all <cmd> children
    cmds = re.findall(r'<cmd>(.*?)</cmd>', inner, re.DOTALL)
    sp["commands_run"] = [c.strip() for c in cmds]
    # commands_planned: text content (may hold multiple items as newline-separated)
    m = re.search(r'<commands_planned>(.*?)</commands_planned>', inner, re.DOTALL)
    sp["commands_planned"] = m.group(1).strip() if m else ""
    # scalar fields
    for field in ("hypothesis", "confidence", "blocked_on", "status",
                  "evidence_ref", "canary_command"):
        m = re.search(fr'<{field}>(.*?)</{field}>', inner, re.DOTALL)
        if m:
            sp[field] = m.group(1).strip()
        else:
            sp[field] = None
    return sp


def _sp_to_xml(sp: dict) -> str:
    """Serialize a scratchpad dict back to inner XML (without outer <scratchpad> tags)."""
    lines = []
    # commands_run as a block of <cmd> tags
    cmds = sp.get("commands_run") or []
    if cmds:
        lines.append("  <commands_run>")
        for cmd in cmds:
            lines.append(f"    <cmd>{cmd}</cmd>")
        lines.append("  </commands_run>")
    else:
        lines.append("  <commands_run></commands_run>")
    # scalar fields (emit in a stable order)
    for field in ("hypothesis", "confidence", "commands_planned", "blocked_on",
                  "status", "evidence_ref", "canary_command"):
        val = sp.get(field)
        if val is None or val == "":
            lines.insert(0 if field in ("hypothesis", "confidence") else len(lines),
                         f"  <{field}/>")
        else:
            lines.insert(0 if field in ("hypothesis", "confidence") else len(lines),
                         f"  <{field}>{val}</{field}>")
    # Rebuild in logical order: hypothesis, confidence, commands_run, rest
    ordered = []
    for f in ("hypothesis", "confidence"):
        val = sp.get(f)
        ordered.append(f"  <{f}/>" if not val else f"  <{f}>{val}</{f}>")
    # commands_run block (already built above)
    cr_block = "\n".join(l for l in lines if "commands_run" in l or "<cmd>" in l)
    ordered.append(cr_block)
    for f in ("commands_planned", "blocked_on", "status", "evidence_ref", "canary_command"):
        val = sp.get(f)
        ordered.append(f"  <{f}/>" if not val else f"  <{f}>{val}</{f}>")
    return "\n".join(ordered)


def parse_scratchpad(text):
    """Extract scratchpad from text. Accepts XML (current) or JSON (legacy).
    Returns (sp_dict_or_None, evidence_rejected, injection_msg)."""
    match = re.search(r'<scratchpad>\s*(.*?)\s*</scratchpad>', text, re.DOTALL)
    if not match:
        return None, False, ""
    inner = match.group(1).strip()
    # Try JSON first (backwards compatibility with older sessions)
    try:
        sp = json.loads(inner)
    except json.JSONDecodeError:
        # XML format (current default)
        sp = _parse_xml_scratchpad(inner)
        if not sp:
            return None, False, ""

    status = sp.get("status", "investigating") or "investigating"
    evidence_ref = sp.get("evidence_ref", "") or ""
    evidence_rejected = (
        status in _EVIDENCE_REQUIRED_STATUSES
        and not str(evidence_ref).strip()
    )
    if evidence_rejected:
        sp["status"] = "investigating"
        return sp, True, _EVIDENCE_INJECTION_MSG
    return sp, False, ""


# ══════════════════════════════════════════════════════════════════════════════
#  MODE: append
# ══════════════════════════════════════════════════════════════════════════════

def mode_append():
    """Append a message to conversation JSON with MAX_MESSAGES trimming."""
    conv_raw = os.environ.get("NEXUS_CONV", "[]")
    role     = os.environ.get("NEXUS_ROLE", "user")
    msg      = os.environ.get("NEXUS_MSG",  "")

    try:
        msgs = json.loads(conv_raw)
    except Exception:
        msgs = []

    # Only Igor's assistant adapter may append structured text blocks here.
    # Native tool turns use transactions.complete(); user JSON remains text.
    if role == "assistant":
        try:
            parsed = json.loads(msg)
        except (ValueError, TypeError):
            parsed = None
        if isinstance(parsed, list) and all(
            isinstance(block, dict) and block.get("type") == "text"
            for block in parsed
        ):
            msgs.append({"role": "assistant", "content": parsed})
        else:
            msgs.append({"role": "assistant", "content": msg})
    else:
        msgs.append({"role": role, "content": msg})

    try:
        msgs = trim(msgs)
    except TransactionError as error:
        print(f"conversation append rejected: {error}", file=sys.stderr)
        sys.exit(1)

    print(json.dumps(msgs))


# ══════════════════════════════════════════════════════════════════════════════
#  MODE: compress
# ══════════════════════════════════════════════════════════════════════════════

THRESH_CURRENT = 4000
THRESH_PREV    = 200
THRESH_OLD     = 80
TOKEN_WARN_THRESHOLD = 8000


def _is_tool_output_message(msg):
    role    = msg.get("role", "")
    content = msg.get("content", "")
    if role == "user" and isinstance(content, list):
        return any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content)
    if role == "tool":
        return True
    if role == "user" and isinstance(content, str):
        return bool(re.search(
            r'(TOOL[_ ]RESULT|Command output:|<host_result|<occ_result|\[TOOL)',
            content, re.IGNORECASE
        ))
    return False


def _heuristic_summary(text, max_chars):
    if len(text) <= max_chars:
        return text
    lines = [l for l in text.splitlines() if l.strip()]
    if not lines:
        return text[:max_chars]
    error_lines = [l for l in lines if re.search(
        r'\b(error|Error|ERROR|fatal|FATAL|failed|FAILED|exception|Exception'
        r'|warning|Warning|WARNING|critical|Critical|CRITICAL)\b', l)]
    if error_lines:
        core = " | ".join(error_lines[:3])
    elif len(lines) == 1:
        core = lines[0]
    else:
        core = lines[0] + " … " + lines[-1]
    tag = f"[{len(lines)}L] "
    available = max_chars - len(tag) - 1
    if len(core) > available:
        core = core[:available - 1] + "…"
    return tag + core


def _compress_message(msg, threshold):
    content = msg.get("content", "")
    if isinstance(content, list):
        new_blocks = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                raw = block.get("content", "")
                if isinstance(raw, str) and len(raw) > threshold:
                    block = dict(block, content=_heuristic_summary(raw, threshold))
            new_blocks.append(block)
        return dict(msg, content=new_blocks)
    if isinstance(content, str) and len(content) > threshold:
        return dict(msg, content=_heuristic_summary(content, threshold))
    return msg


def _estimate_tokens(messages):
    total = 0
    for msg in messages:
        content = msg.get("content", "")
        if isinstance(content, str):
            total += len(content)
        elif isinstance(content, list):
            for b in content:
                if isinstance(b, dict):
                    v = b.get("content", b.get("text", ""))
                    total += len(str(v)) if v else 0
                else:
                    total += len(str(b))
    return total // 4


def mode_compress():
    """Apply progressive context compression (stdin → stdout)."""
    raw = sys.stdin.read().strip()
    if not raw:
        print("[]")
        return
    try:
        messages = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"[context_compress] ERROR: Invalid JSON: {e}\n")
        sys.exit(1)
    if not isinstance(messages, list):
        print(raw)
        return
    tokens_before = _estimate_tokens(messages)
    tool_positions = [i for i, m in enumerate(messages) if _is_tool_output_message(m)]
    result = list(messages)
    for age, idx in enumerate(reversed(tool_positions)):
        threshold = THRESH_CURRENT if age == 0 else THRESH_PREV if age == 1 else THRESH_OLD
        result[idx] = _compress_message(result[idx], threshold)
    tokens_after = _estimate_tokens(result)
    if tokens_after > TOKEN_WARN_THRESHOLD:
        sys.stderr.write(f"[context_compress] tokens={tokens_after} (>{TOKEN_WARN_THRESHOLD} — saved {tokens_before - tokens_after})\n")
    else:
        sys.stderr.write(f"[context_compress] tokens={tokens_after} (saved {tokens_before - tokens_after})\n")
    print(json.dumps(result))


# ══════════════════════════════════════════════════════════════════════════════
#  MODE: validate
# ══════════════════════════════════════════════════════════════════════════════

def mode_validate():
    """Validate a single tool call. Reads NEXUS_TOOL_JSON env var.
    Outputs line-format verdict to stdout:
        VALID: true|false
        BLOCKED: true|false
        REASON: <text or empty>
        WARNINGS: msg1|msg2 (or empty)
    """
    tool_raw = os.environ.get("NEXUS_TOOL_JSON", "")
    try:
        tool = json.loads(tool_raw)
    except Exception:
        # Fail-open on bad input
        print("VALID: true\nBLOCKED: false\nREASON: \nWARNINGS: ")
        return
    valid, blocked, block_reason, warnings = validate_tool_call(tool)
    print(f"VALID: {'true' if valid else 'false'}")
    print(f"BLOCKED: {'true' if blocked else 'false'}")
    print(f"REASON: {block_reason or ''}")
    print(f"WARNINGS: {'|'.join(warnings)}")


# ══════════════════════════════════════════════════════════════════════════════
#  MODE: call
# ══════════════════════════════════════════════════════════════════════════════

def _b64(s):
    if isinstance(s, str):
        s = s.encode()
    return base64.b64encode(s).decode()


def _tools_mode(provider, model):
    if provider == "anthropic":
        return "anthropic"
    if provider == "openrouter":
        if model.startswith(("openai/", "anthropic/")) or any(
            family in model for family in ("claude-", "gpt-4", "gpt-3.5")
        ):
            return "openai"
    return "xml"


_TOOL_NAME_MAP = {
    "host_command":     "host",
    "occ_command":      "occ",
    "container_action": "container",
    "read_file":        "read_file",
    "edit_file":        "edit_file",
    "reply":            "reply",
}


def _normalize_native_tool(name, raw_input, native_id):
    internal = _TOOL_NAME_MAP.get(name, name)
    base = {"__native_id": native_id}
    if not isinstance(raw_input, dict):
        return {**base, "tool": internal, "invalid_input": "expected object"}
    from tool_input import SCHEMAS
    if name in SCHEMAS:
        return {**raw_input, **base, "tool": internal}
    # The canonical catalog uses the same field names as the dispatcher.
    # Retain legacy aliases only for older provider/session records.
    if internal in ("host", "occ") and "cmd" in raw_input:
        return {**raw_input, **base, "tool": internal}
    if internal == "container" and "target" in raw_input:
        return {**raw_input, **base, "tool": internal}
    if internal == "host":
        return {**base, "tool": "host", "cmd": raw_input.get("command", "")}
    if internal == "occ":
        return {**base, "tool": "occ", "cmd": raw_input.get("command", "")}
    if internal == "container":
        return {**base, "tool": "container",
                "action": raw_input.get("action", ""),
                "target": raw_input.get("name", "")}
    if internal == "read_file":
        return {**base, "tool": "read_file",
                "path": raw_input.get("path", ""),
                "lines": str(raw_input.get("lines", 50))}
    if internal == "edit_file":
        return {**base, "tool": "edit_file",
                "path": raw_input.get("path", ""),
                "find": raw_input.get("find", ""),
                "replace": raw_input.get("replace", "")}
    if internal == "reply":
        return {**base, "tool": "reply",
                "message": raw_input.get("message", ""),
                "status": raw_input.get("status", "INFO")}
    return {**base, "tool": internal, **raw_input}


def _extract_xml_tools(reply_text):
    """Extract XML tool tags from reply_text. Returns (tools_list, cleaned_text)."""
    tools = []

    def _capability_xml_tool(groups):
        try:
            inputs = json.loads(groups[2].strip())
        except (TypeError, ValueError):
            return {"tool": "run_capability", "id": groups[0].strip(), "inputs": None}
        if isinstance(inputs, dict) and "inputs" in inputs and len(inputs) == 1:
            inputs = inputs["inputs"]
        tool = {"tool": "run_capability", "id": groups[0].strip(), "inputs": inputs}
        if groups[1]:
            tool["provider"] = groups[1].strip()
        return tool

    def _extract(pattern, builder, text):
        found = re.findall(pattern, text, re.DOTALL)
        clean = re.sub(pattern, '', text, flags=re.DOTALL)
        for groups in found:
            t = builder(groups)
            if t:
                tools.append(t)
        return clean

    reply_text = _extract(r'<occ>\s*(.*?)\s*</occ>',
        lambda g: {"tool": "occ", "cmd": g.strip()}, reply_text)
    reply_text = _extract(r'<host>\s*(.*?)\s*</host>',
        lambda g: {"tool": "host", "cmd": g.strip()}, reply_text)
    reply_text = _extract(r'<container\s+action="([^"]+)">\s*(.*?)\s*</container>',
        lambda g: {"tool": "container", "action": g[0].strip(), "target": g[1].strip()}, reply_text)
    reply_text = _extract(r'<read_log\s+target="([^"]+)"\s+lines="([0-9]+)">\s*(.*?)\s*</read_log>',
        lambda g: {"tool": "read_log", "target": g[0], "lines": g[1], "search": g[2].strip()}, reply_text)
    reply_text = _extract(
        r'<edit_file\s+path="([^"]+)">\s*<find>(.*?)</find>\s*<replace>(.*?)</replace>\s*</edit_file>',
        lambda g: {"tool": "edit_file", "path": g[0].strip(), "find": g[1], "replace": g[2]}, reply_text)
    reply_text = _extract(
        r'<propose_menu_item>\s*<TITLE>(.*?)</TITLE>\s*<DESCRIPTION>(.*?)</DESCRIPTION>'
        r'\s*<COMMAND>(.*?)</COMMAND>\s*<TYPE>(.*?)</TYPE>\s*<TIER>(.*?)</TIER>\s*</propose_menu_item>',
        lambda g: {"tool": "propose_menu_item", "title": g[0].strip(), "description": g[1].strip(),
                   "command": g[2].strip(), "type": g[3].strip(), "tier": g[4].strip()}, reply_text)
    reply_text = _extract(r'<execute>\s*(.*?)\s*</execute>',
        lambda g: {"tool": "execute", "cmd": g.strip()}, reply_text)
    reply_text = _extract(r'<run_igor_action>\s*(.*?)\s*</run_igor_action>',
        lambda g: {"tool": "run_igor_action", "cmd": g.strip()}, reply_text)
    reply_text = _extract(r'<run_capability\s+id="([^"]+)"(?:\s+provider="([^"]+)")?>\s*(.*?)\s*</run_capability>',
        lambda g: _capability_xml_tool(g), reply_text)
    reply_text = _extract(r'<read_file\s+lines="([0-9]+)">\s*(.*?)\s*</read_file>',
        lambda g: {"tool": "read_file", "lines": g[0], "path": g[1].strip()}, reply_text)
    reply_text = _extract(r'<read_report>\s*(.*?)\s*</read_report>',
        lambda g: {"tool": "read_report", "filename": g.strip()}, reply_text)
    reply_text = _extract(r'<reply\s+status="([^"]+)">\s*(.*?)\s*</reply>',
        lambda g: {"tool": "reply", "status": g[0], "message": g[1]}, reply_text)

    return tools, reply_text.strip()


def _emit_error(msg, kind="provider"):
    from privacy import scrub_text
    msg = " ".join(scrub_text(msg).splitlines())
    _audit_response("failed")
    sys.stdout.write(f"REPLY_START\nERROR: {msg}\nREPLY_END\nPROVIDER_ERROR: true\nERROR_KIND: {kind}\nTOKENS_IN: 0\nTOKENS_OUT: 0\n")
    sys.stdout.flush()


def _audit_response(outcome, **metadata):
    from operations import append
    try:
        append({"event": "response", "request_id": os.environ.get("IGOR_AI_REQUEST_ID", ""),
                "outcome": outcome, **metadata})
    except (OSError, ValueError):
        print("AI response could not be recorded.", file=sys.stderr)


class _ScratchpadFilter:
    """
    Suppress <scratchpad>...</scratchpad> blocks from the real-time stderr stream.

    Handles partial tag delivery across chunk boundaries.  Everything outside
    a scratchpad block is forwarded immediately; the block itself is silently
    consumed so only the Rich panel (rendered later) is visible to the user.
    """
    _OPENS = {"<scratchpad>": "</scratchpad>", "<think>": "</think>"}

    def __init__(self):
        self._hold  = ""    # partial tag candidate held at chunk boundary
        self._skip  = False # True while inside a scratchpad block
        self._close = ""

    def feed(self, chunk: str) -> str:
        """Return the portion of chunk that is safe to display."""
        text = self._hold + chunk
        self._hold = ""
        out = []

        while text:
            if self._skip:
                end = text.find(self._close)
                if end >= 0:
                    text = text[end + len(self._close):]
                    self._skip = False
                else:
                    # Tail might be a partial closing tag — hold it
                    for n in range(len(self._close) - 1, 0, -1):
                        if text.endswith(self._close[:n]):
                            self._hold = text[-n:]
                            text = ""
                            break
                    else:
                        text = ""   # consume (still inside block)
            else:
                candidates = [(text.find(tag), tag) for tag in self._OPENS if tag in text]
                start, opening = min(candidates) if candidates else (-1, "")
                if start >= 0:
                    out.append(text[:start])
                    text = text[start + len(opening):]
                    self._close = self._OPENS[opening]
                    self._skip = True
                else:
                    # Tail might be a partial opening tag — hold it
                    for n in range(max(map(len, self._OPENS)) - 1, 0, -1):
                        if any(text.endswith(tag[:n]) for tag in self._OPENS if len(tag) > n):
                            out.append(text[:-n])
                            self._hold = text[-n:]
                            text = ""
                            break
                    else:
                        out.append(text)
                        text = ""

        return "".join(out)


def mode_call():
    """Full API round-trip: HTTP stream + parse + validate + emit markers."""
    from role_transport import from_environment
    route = from_environment()
    os.environ["IGOR_AI_ROUTING"] = json.dumps(route)
    if route["status"] != "selected":
        from request_context import publish
        publish({"request_id": os.environ.get("IGOR_AI_REQUEST_ID", ""), "routing": route,
                 "outcome": "not_invoked"})
        _emit_error("Model role unavailable", "configuration_error")
        return
    original_provider = os.environ.get("NEXUS_PROVIDER", "anthropic")
    provider = route["provider"]
    if provider != original_provider:
        os.environ["NEXUS_API_KEY"] = os.environ.get(provider.upper() + "_API_KEY", "") if provider != "ollama" else ""
    os.environ["NEXUS_PROVIDER"] = provider
    os.environ["NEXUS_MODEL"] = route["model"]
    if route["selected_role"] != "reasoner":
        os.environ["NEXUS_TOOLS_JSON"] = "[]"
    if os.environ.get("IGOR_AI_ENABLED", "true") != "true":
        _emit_error("AI is disabled by administrator policy", "payload_blocked")
        return
    if provider not in {"anthropic", "openrouter", "ollama"}:
        _emit_error("Unsupported AI provider", "configuration_error")
        return
    api_key    = os.environ.get("NEXUS_API_KEY",      "").strip()
    model      = os.environ.get("NEXUS_MODEL",        "claude-haiku-4-5-20251001")
    max_tokens = int(os.environ.get("NEXUS_MAX_TOKENS", "2048"))
    system     = os.environ.get("NEXUS_SYSTEM",       "")
    conv_raw   = os.environ.get("NEXUS_CONV",         "[]")

    try:
        temperature = float(os.environ.get("NEXUS_TEMPERATURE", "0.7"))
        temperature = max(0.0, min(2.0, temperature))
    except (ValueError, TypeError):
        temperature = 0.7

    if not api_key and provider != "ollama":
        _emit_error("No API key set. Add key with: menu A → settings", "configuration_error")
        return

    try:
        messages = json.loads(conv_raw)
    except Exception as e:
        _emit_error(f"conversation parse failed: {e}", "malformed_response")
        return

    try:
        validate_history(messages)
    except TransactionError as error:
        _emit_error(f"invalid provider conversation: {error}", "malformed_response")
        return

    _tools_defs = []
    # Native schemas from the canonical catalog (set by ai_router.sh).
    _nexus_tools_raw = os.environ.get("NEXUS_TOOLS_JSON", "").strip()
    if _nexus_tools_raw and _nexus_tools_raw != "[]":
        try:
            _tools_defs = json.loads(_nexus_tools_raw)
        except Exception:
            pass
    # An empty catalog is intentional. Never resurrect tools from a second,
    # static source when policy or active modules provided no tools.
    try:
        system, messages, _tools_defs = prepare_request(system, messages, _tools_defs)
    except (ValueError, OSError, TypeError) as exc:
        _emit_error(f"request boundary rejected input: {type(exc).__name__}",
                    "payload_blocked")
        return

    ctx = ssl.create_default_context()
    full_text    = []
    input_tok    = 0
    output_tok   = 0
    buffer       = b""
    tools_to_run = []
    asst_content_for_conv = None
    tool_conv_fmt = ""
    _tmode = _tools_mode(provider, model)
    stop_reason = ""
    _sp_filter = _ScratchpadFilter()

    sys.stderr.write("\n  \033[1;35mIgor:\033[0m\n  ")
    sys.stderr.flush()

    # ── Anthropic path ──────────────────────────────────────────────────────
    if provider == "anthropic":
        payload_dict = {
            "model": model, "max_tokens": max_tokens,
            "temperature": temperature, "system": system,
            "messages": messages, "stream": True,
        }
        if _tmode == "anthropic" and _tools_defs:
            payload_dict["tools"] = _tools_defs
        payload = json.dumps(payload_dict).encode()

        conn = http.client.HTTPSConnection("api.anthropic.com", context=ctx, timeout=90)
        try:
            conn.request("POST", "/v1/messages", body=payload, headers={
                "Content-Type": "application/json",
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "Accept": "text/event-stream",
            })
            resp = conn.getresponse()
        except Exception as e:
            _emit_error(f"connection failed: {e}")
            return

        if resp.status != 200:
            _emit_error(f"HTTP {resp.status}: {resp.read().decode()[:300]}"); return

        _ant_blocks = {}
        try:
            while True:
                chunk = resp.read(64)
                if not chunk: break
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    line = line.decode("utf-8", errors="replace").rstrip()
                    if not line.startswith("data: "): continue
                    data_str = line[6:]
                    if data_str == "[DONE]": break
                    try: event = json.loads(data_str)
                    except: continue
                    etype = event.get("type", "")
                    if etype == "content_block_start":
                        idx = event.get("index", 0)
                        blk = event.get("content_block", {})
                        if blk.get("type") == "tool_use":
                            _ant_blocks[idx] = {"type": "tool_use", "id": blk.get("id", ""),
                                                "name": blk.get("name", ""), "input_json": ""}
                        else:
                            _ant_blocks[idx] = {"type": "text", "text": ""}
                    elif etype == "content_block_delta":
                        idx   = event.get("index", 0)
                        delta = event.get("delta", {})
                        dtype = delta.get("type", "")
                        if dtype == "text_delta":
                            text = delta.get("text", "")
                            if text:
                                full_text.append(text)
                                _visible = _sp_filter.feed(text)
                                if _visible:
                                    sys.stderr.write(_visible.replace("\n", "\n  "))
                                    sys.stderr.flush()
                                if idx in _ant_blocks and _ant_blocks[idx]["type"] == "text":
                                    _ant_blocks[idx]["text"] = _ant_blocks[idx].get("text", "") + text
                        elif dtype == "input_json_delta":
                            partial = delta.get("partial_json", "")
                            if idx in _ant_blocks and _ant_blocks[idx]["type"] == "tool_use":
                                _ant_blocks[idx]["input_json"] = _ant_blocks[idx].get("input_json", "") + partial
                    elif etype == "message_delta":
                        output_tok = event.get("usage", {}).get("output_tokens", output_tok)
                        sr = event.get("delta", {}).get("stop_reason", "")
                        if sr: stop_reason = sr
                    elif etype == "message_start":
                        input_tok = event.get("message", {}).get("usage", {}).get("input_tokens", 0)
        except Exception as e:
            sys.stderr.write(f"\n  [stream error: {e}]\n")
        finally:
            conn.close()

        if _tmode == "anthropic" and _ant_blocks:
            _asst_content = []
            for _idx in sorted(_ant_blocks.keys()):
                _blk = _ant_blocks[_idx]
                if _blk["type"] == "text":
                    _txt = _blk.get("text", "").strip()
                    if _txt:
                        _asst_content.append({"type": "text", "text": _txt})
                elif _blk["type"] == "tool_use":
                    try: _inp = json.loads(_blk["input_json"] or "{}")
                    except: _inp = {}
                    _asst_content.append({"type": "tool_use", "id": _blk["id"],
                                          "name": _blk["name"], "input": _inp})
                    tools_to_run.append(_normalize_native_tool(_blk["name"], _inp, _blk["id"]))
            if _asst_content:
                asst_content_for_conv = _asst_content
                tool_conv_fmt = "anthropic"

    # ── OpenRouter path ────────────────────────────────────────────────────
    elif provider == "openrouter":
        or_messages = []
        if system:
            or_messages.append({"role": "system", "content": system})
        or_messages.extend(messages)
        payload_dict = {
            "model": model, "max_tokens": max_tokens,
            "temperature": temperature, "messages": or_messages, "stream": True,
        }
        if _tmode == "openai" and _tools_defs:
            payload_dict["tools"] = [
                t if "function" in t else {"type": "function", "function": {
                    "name": t["name"], "description": t["description"],
                    "parameters": t["input_schema"],
                }} for t in _tools_defs
            ]
            payload_dict["tool_choice"] = "auto"
        payload = json.dumps(payload_dict).encode()

        conn = http.client.HTTPSConnection("openrouter.ai", context=ctx, timeout=90)
        try:
            conn.request("POST", "/api/v1/chat/completions", body=payload, headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
                "HTTP-Referer": os.environ.get("IGOR_GITHUB_URL", "https://github.com/yourusername/igor"),
                "X-Title": os.environ.get("IGOR_APP_TITLE", "IGOR"),
                "Accept": "text/event-stream",
            })
            resp = conn.getresponse()
        except Exception as e:
             _emit_error(f"connection failed: {e}")
             return

        if resp.status != 200:
            _emit_error(f"HTTP {resp.status}: {resp.read().decode()[:300]}"); return

        _or_tcs = {}
        try:
            while True:
                chunk = resp.read(64)
                if not chunk: break
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    line = line.decode("utf-8", errors="replace").rstrip()
                    if not line.startswith("data: "): continue
                    data_str = line[6:]
                    if data_str == "[DONE]": break
                    try: event = json.loads(data_str)
                    except: continue
                    choice = event.get("choices", [{}])[0]
                    delta  = choice.get("delta", {})
                    text   = delta.get("content") or ""
                    if text:
                        full_text.append(text)
                        _visible = _sp_filter.feed(text)
                        if _visible:
                            sys.stderr.write(_visible.replace("\n", "\n  "))
                            sys.stderr.flush()
                    for _tc in delta.get("tool_calls", []):
                        _tci = _tc.get("index", 0)
                        if _tci not in _or_tcs:
                            _or_tcs[_tci] = {"id": "", "name": "", "arguments": ""}
                        if _tc.get("id"): _or_tcs[_tci]["id"] = _tc["id"]
                        _fn = _tc.get("function", {})
                        if _fn.get("name"):      _or_tcs[_tci]["name"]      += _fn["name"]
                        if _fn.get("arguments"): _or_tcs[_tci]["arguments"] += _fn["arguments"]
                    fr = choice.get("finish_reason")
                    if fr: stop_reason = fr
                    usage = event.get("usage", {})
                    if usage:
                        input_tok  = usage.get("prompt_tokens",     input_tok)
                        output_tok = usage.get("completion_tokens", output_tok)
        except Exception as e:
            sys.stderr.write(f"\n  [stream error: {e}]\n")
        finally:
            conn.close()

        if _tmode == "openai" and _or_tcs:
            _tc_list = []
            for _tci in sorted(_or_tcs.keys()):
                _tc = _or_tcs[_tci]
                try: _inp = json.loads(_tc["arguments"] or "{}")
                except: _inp = {}
                tools_to_run.append(_normalize_native_tool(_tc["name"], _inp, _tc["id"]))
                _tc_list.append({"id": _tc["id"], "type": "function",
                                 "function": {"name": _tc["name"], "arguments": _tc["arguments"]}})
            asst_content_for_conv = {"role": "assistant",
                                     "content": "".join(full_text) or None,
                                     "tool_calls": _tc_list}
            tool_conv_fmt = "openai"

    # ── Ollama path ────────────────────────────────────────────────────────
    elif provider == "ollama":
        import urllib.parse
        ollama_host = os.environ.get("IGOR_OLLAMA_HOST", "http://127.0.0.1:11434").rstrip("/")
        parsed = urllib.parse.urlparse(ollama_host)
        _scheme   = parsed.scheme or "http"
        _hostname = parsed.hostname or "127.0.0.1"
        _port     = parsed.port or (443 if _scheme == "https" else 11434)

        # Tier-based timeout
        _igor_tier = os.environ.get("IGOR_TIER", "standard")
        _tier_timeouts = {"constrained": 120, "standard": 90, "comfortable": 60, "server": 30}
        _timeout = _tier_timeouts.get(_igor_tier, 90)

        # Tier-based context window
        _tier_ctx = {"constrained": 4096, "standard": 8192, "comfortable": 16384, "server": 32768}
        _num_ctx  = int(os.environ.get("IGOR_OLLAMA_NUM_CTX", str(_tier_ctx.get(_igor_tier, 8192))))

        ol_messages = []
        if system:
            ol_messages.append({"role": "system", "content": system})
        ol_messages.extend(messages)

        payload_dict = {
            "model":    model,
            "messages": ol_messages,
            "stream":   True,
            "options": {
                "num_ctx":     _num_ctx,
                "num_predict": max_tokens,
                "temperature": temperature,
            },
        }
        payload = json.dumps(payload_dict).encode()

        try:
            if _scheme == "https":
                conn = http.client.HTTPSConnection(_hostname, _port, context=ctx, timeout=_timeout)
            else:
                conn = http.client.HTTPConnection(_hostname, _port, timeout=_timeout)
            conn.request("POST", "/api/chat", body=payload, headers={
                "Content-Type": "application/json",
            })
            resp = conn.getresponse()
        except Exception as e:
            _emit_error(f"Ollama connection failed ({ollama_host}): {e}")
            return

        if resp.status != 200:
            _emit_error(f"Ollama HTTP {resp.status}: {resp.read().decode()[:300]}"); return

        try:
            while True:
                chunk = resp.read(256)
                if not chunk:
                    break
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    line = line.decode("utf-8", errors="replace").strip()
                    if not line:
                        continue
                    try:
                        event = json.loads(line)
                    except Exception:
                        continue
                    text = event.get("message", {}).get("content", "")
                    if text:
                        full_text.append(text)
                        _visible = _sp_filter.feed(text)
                        if _visible:
                            sys.stderr.write(_visible.replace("\n", "\n  "))
                            sys.stderr.flush()
                    if event.get("done"):
                        input_tok  = event.get("prompt_eval_count",  input_tok)
                        output_tok = event.get("eval_count",         output_tok)
                        stop_reason = event.get("done_reason", "stop")
                        break
        except Exception as e:
            sys.stderr.write(f"\n  [Ollama stream error: {e}]\n")
        finally:
            conn.close()

    else:
        _emit_error(f"Unknown provider: {provider}")
        return

    sys.stderr.write("\n")
    sys.stderr.flush()

    reply_text = "".join(full_text)

    # ── Strip <think> blocks ──────────────────────────────────────────────
    think_text = ""
    m = re.search(r'<think>\s*(.*?)\s*</think>', reply_text, re.DOTALL)
    if m:
        think_text = m.group(1).strip()
        reply_text = re.sub(r'<think>.*?</think>', '', reply_text, flags=re.DOTALL)

    # ── Extract <explain> tag ─────────────────────────────────────────────
    explain_text = ""
    m = re.search(r'<explain>\s*(.*?)\s*</explain>', reply_text, re.DOTALL)
    if m:
        explain_text = m.group(1).strip()
        reply_text = re.sub(r'<explain>.*?</explain>', '', reply_text, flags=re.DOTALL)

    # ── Extract scratchpad + P2-4 evidence enforcement ────────────────────
    sp_data, evidence_rejected, ev_injection_msg = parse_scratchpad(reply_text)
    scratchpad_text = ""
    if sp_data is not None:
        # Persist as XML so the injected scratchpad (next turn) matches the
        # XML format shown in the system prompt.
        scratchpad_text = _sp_to_xml(sp_data)
    reply_text = re.sub(r'<scratchpad>.*?</scratchpad>', '', reply_text, flags=re.DOTALL)

    # ── Extract XML tool tags (fallback for non-native tool_use) ─────────
    # Only run if no native tools were collected from the stream
    if not tools_to_run:
        xml_tools, reply_text = _extract_xml_tools(reply_text)
        tools_to_run.extend(xml_tools)
    else:
        reply_text = reply_text.strip()

    # ── Validate all tool calls inline ───────────────────────────────────
    validation_results = []
    for idx, tool in enumerate(tools_to_run):
        valid, blocked, block_reason, warnings = validate_tool_call(tool)
        validation_results.append({
            "tool_idx": idx,
            "valid": valid,
            "blocked": blocked,
            "block_reason": block_reason,
            "warnings": warnings,
        })

    # ── Emit marker protocol ──────────────────────────────────────────────
    sys.stdout.write("REPLY_START\n")
    sys.stdout.write(reply_text + "\n")
    sys.stdout.write("REPLY_END\n")
    if think_text:
        sys.stdout.write(f"THINK_B64: {_b64(think_text)}\n")
    if explain_text:
        sys.stdout.write(f"EXPLAIN_B64: {_b64(explain_text)}\n")
    if scratchpad_text:
        sys.stdout.write(f"SCRATCHPAD_B64: {_b64(scratchpad_text)}\n")
    for t in tools_to_run:
        sys.stdout.write(f"TOOL_B64: {_b64(json.dumps(t))}\n")
    if asst_content_for_conv:
        sys.stdout.write(f"ASSISTANT_MSG_B64: {_b64(json.dumps(asst_content_for_conv))}\n")
    if tool_conv_fmt:
        sys.stdout.write(f"TOOL_CONV_FMT: {tool_conv_fmt}\n")
    sys.stdout.write(f"TOKENS_IN: {input_tok}\n")
    sys.stdout.write(f"TOKENS_OUT: {output_tok}\n")
    if stop_reason in ("max_tokens", "length"):
        sys.stdout.write("TRUNCATED: true\n")
    # New markers
    if evidence_rejected:
        sys.stdout.write("EVIDENCE_REJECTED: true\n")
        sys.stdout.write(f"STATUS_INJECTION_B64: {_b64(ev_injection_msg)}\n")
    sys.stdout.write(f"VALIDATION_B64: {_b64(json.dumps(validation_results))}\n")
    _audit_response("received", tokens_in=input_tok, tokens_out=output_tok,
                    tool_count=len(tools_to_run), stop_reason=stop_reason)
    sys.stdout.flush()


# ══════════════════════════════════════════════════════════════════════════════
#  ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "call"
    if   mode == "call":     mode_call()
    elif mode == "append":   mode_append()
    elif mode == "compress": mode_compress()
    elif mode == "validate": mode_validate()
    else:
        sys.stderr.write(f"ai_engine.py: unknown mode '{mode}'\n")
        sys.stderr.write("Usage: ai_engine.py <call|append|compress|validate>\n")
        sys.exit(1)
