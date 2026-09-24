"""Validate dispatcher input; stdout is NUL-delimited data, never shell code."""

import json
import re
import shlex
import sys

FIELDS = (
    "tool", "cmd", "action", "target", "lines", "search", "path", "find",
    "replace", "filename", "title", "description", "command", "type", "tier",
    "message",
)
SCHEMAS = {
    "host": ({"cmd"}, {"cmd"}),
    "execute": ({"cmd"}, {"cmd"}),
    "occ": ({"cmd"}, {"cmd"}),
    "container": ({"action", "target"}, {"action", "target"}),
    "read_log": ({"target", "lines", "search"}, {"target"}),
    "read_file": ({"path", "lines"}, {"path"}),
    "edit_file": ({"path", "find", "replace"}, {"path", "find", "replace"}),
    "read_report": ({"filename"}, {"filename"}),
    "propose_menu_item": (
        {"title", "description", "command", "type", "tier"},
        {"title", "description", "command", "type", "tier"},
    ),
    "reply": ({"message", "status"}, {"message"}),
    "run_igor_action": ({"cmd"}, {"cmd"}),
}
ALIASES = {"host_command": "host", "occ_command": "occ", "container_action": "container"}


def tool_fields(text):
    data = json.loads(text)
    if not isinstance(data, dict) or not isinstance(data.get("tool"), str):
        raise TypeError("expected a tool object")
    name = ALIASES.get(data["tool"], data["tool"])
    if name not in SCHEMAS:
        raise ValueError("unknown tool")
    allowed, required = SCHEMAS[name]
    if data.keys() - (allowed | {"tool", "__native_id"}) or required - data.keys():
        raise ValueError("unknown or missing tool fields")
    for key, value in data.items():
        if key == "lines" and type(value) is int:
            value = str(value)
        if not isinstance(value, str) or "\0" in value:
            raise ValueError("tool fields must be strings (lines may also be an integer)")
        data[key] = value
    data["tool"] = name
    if name in {"host", "execute", "occ", "run_igor_action"} and not data["cmd"].strip():
        raise ValueError("empty command")
    if name in {"read_log", "read_file"}:
        lines = data.get("lines", "20" if name == "read_log" else "50")
        if not re.fullmatch(r"[0-9]{1,9}", lines) or int(lines) < 1:
            raise ValueError("lines must be a positive integer")
        data["lines"] = str(min(int(lines), 50 if name == "read_log" else 100))
    if name in {"read_log", "container"} and not re.fullmatch(
        r"[a-zA-Z0-9][a-zA-Z0-9_.-]*", data["target"]
    ):
        raise ValueError("invalid service name")
    if name == "container" and data["action"] not in {"start", "stop", "restart"}:
        raise ValueError("unsupported container action")
    if name == "run_igor_action" and not re.fullmatch(r"[a-zA-Z0-9_][a-zA-Z0-9_-]*", data["cmd"]):
        raise ValueError("invalid action identifier")
    return [data.get(field, "") for field in FIELDS]


def command_words(text):
    # Even quoted shell syntax is rejected: semantic tools have no shell language.
    if any(char in text for char in "\0\n\r$`;&|<>()"):
        raise ValueError("shell operators and substitutions are not allowed")
    words = shlex.split(text)
    if not words:
        raise ValueError("empty command")
    return words


def occ_is_read(words):
    if not words:
        return False
    if words[0] == "maintenance:mode":
        return len(words) == 1
    return words[0] in {
        "status", "list", "config:system:get", "config:app:get", "config:list",
        "app:list", "user:list", "user:info", "integrity:check-core", "integrity:check-app",
    }


def journalctl_is_read(words):
    """Return whether a journalctl invocation only reads journal data.

    journalctl is primarily a reader, but its maintenance flags can change
    journal state.  Keep those flags out of the automatic READ allowlist.
    """
    if not words or words[0] != "journalctl":
        return False
    mutating = ("--rotate", "--flush", "--sync", "--relinquish-var")
    return not any(arg == flag or arg.startswith(flag + "=")
                   for arg in words[1:] for flag in mutating) and not any(
                       arg.startswith("--vacuum-") for arg in words[1:]
                   )


def _journalctl_pipeline_is_read(text):
    """Recognize the bounded, read-only journalctl | tail form."""
    if text.count("|") != 1:
        return False
    if any(char in text for char in "\\*?[]{}~"):
        return False
    left, right = (part.strip() for part in text.split("|", 1))
    try:
        journal_words = command_words(left)
        tail_words = command_words(right)
    except ValueError:
        return False
    if not journalctl_is_read(journal_words) or not tail_words or tail_words[0] != "tail":
        return False
    args = tail_words[1:]
    if len(args) == 1 and re.fullmatch(r"-[0-9]+", args[0]):
        return 1 <= int(args[0][1:]) <= 100
    if len(args) == 2 and args[0] in {"-n", "--lines"} and args[1].isdigit():
        return 1 <= int(args[1]) <= 100
    if len(args) == 1 and args[0].startswith("--lines="):
        value = args[0].split("=", 1)[1]
        return value.isdigit() and 1 <= int(value) <= 100
    return False


def command_is_read(text):
    if "|" in text:
        return _journalctl_pipeline_is_read(text)
    try:
        words = command_words(text)
    except ValueError:
        return False
    # Raw commands still run in Bash. Reject expansions that shlex would otherwise
    # turn into innocuous-looking arguments (including quoted command names).
    if any(char in text for char in "\\*?[]{}~"):
        return False
    name, *args = words
    # Streaming modes can hold the agent loop forever. They are not accepted by
    # the automatic READ allowlist; callers may still run them after CHANGE
    # confirmation as ordinary shell commands.
    if any(arg in {"-f", "--follow", "--no-stream=false"} for arg in args):
        return False
    if name == "docker" and args[:1] == ["stats"] and "--no-stream" not in args:
        return False
    if name in {"cat", "head", "tail", "wc", "df", "du", "free", "uptime", "uname", "whoami", "id", "ls"}:
        return True
    if name == "hostname":
        return not args or args in [["-I"], ["-i"], ["-f"], ["-s"]]
    if name == "journalctl":
        return journalctl_is_read(words)
    if name == "docker":
        if args and args[0] in {"ps", "images", "inspect", "logs", "stats", "version", "info"}:
            return True
        if args[:2] in [["volume", "ls"], ["volume", "inspect"], ["network", "ls"], ["network", "inspect"]]:
            return True
        if args[:1] == ["compose"]:
            if args[1:2] in [["ps"], ["logs"], ["images"], ["top"], ["version"]]:
                return True
            # Config can write using --output; only the argument-free form is READ.
            if args == ["compose", "config"]:
                return True
            prefix = ["compose", "exec", "-T", "-u", "www-data", "app", "php", "occ"]
            if args[:len(prefix)] == prefix:
                return occ_is_read(args[len(prefix):])
    return False


def main():
    mode = sys.argv[1]
    text = sys.stdin.read()
    try:
        if mode == "read":
            return 0 if command_is_read(text) else 1
        if mode == "occ-read":
            return 0 if occ_is_read(command_words(text)) else 1
        values = tool_fields(text) if mode == "fields" else command_words(text)
    except (ValueError, TypeError) as exc:
        print(f"Invalid tool input: {exc}", file=sys.stderr)
        return 1
    # The final sentinel lets Bash detect parser failure through process substitution.
    sys.stdout.write("\0".join([*values, "IGOR_INPUT_OK", ""]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
