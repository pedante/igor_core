"""Describe the executable tool grammar. Provider adapters consume this catalog."""

import json
import sys

from tool_input import SCHEMAS

DESCRIPTIONS = {
    "host": "Propose a host shell command. Read-only journalctl queries are allowed for system journal data; unknown or mutating commands require approval.",
    "occ": "Propose an application OCC command. Requires an active Nextcloud provider.",
    "container": "Start, stop or restart a Compose service with approval.",
    "read_log": "Read bounded application logs. target=terminal reads Igor's terminal/session log; another target reads Docker Compose service logs and requires Docker. This tool does not read the system journal; use a read-only host journalctl query for that.",
    "read_file": "Read a bounded regular file from permitted roots. Credential files are excluded.",
    "read_report": "Read a bounded saved report by filename within the reports directory.",
    "edit_file": "Propose an exact file text replacement; requires approval and path validation.",
    "propose_menu_item": "Propose a pending menu item. Saving it requires approval; it does not execute the item.",
    "reply": "Return a public answer or operational summary, without private reasoning.",
    "run_igor_action": "Request a registered module action; Igor enforces its owner and declared tier.",
}

XML_EXAMPLES = {
    "host": '<host>command</host>',
    "occ": '<occ>status</occ>',
    "run_igor_action": '<run_igor_action>registered_action_name</run_igor_action>',
    "container": '<container action="restart">service_name</container>',
    "read_log": '<read_log target="terminal" lines="20">search text</read_log>',
    "read_file": '<read_file lines="50">config/example.conf</read_file>',
    "read_report": '<read_report>report.txt</read_report>',
    "edit_file": '<edit_file path="config/example.conf"><find>old</find><replace>new</replace></edit_file>',
    "reply": '<reply status="INFO">public answer</reply>',
    "propose_menu_item": '<propose_menu_item><TITLE>title</TITLE><DESCRIPTION>purpose</DESCRIPTION>'
                         '<COMMAND>command</COMMAND><TYPE>ONE_TIME</TYPE><TIER>CHANGE</TIER></propose_menu_item>',
}


def build_catalog(records):
    tools, actions = [], []
    for kind, name, owner, tier, description in records:
        if kind == "action":
            actions.append({"name": name, "owner": owner, "tier": tier, "description": description})
            continue
        if name not in DESCRIPTIONS:
            continue
        allowed, required = SCHEMAS[name]
        props = {field: {"type": "string"} for field in sorted(allowed)}
        if "lines" in props:
            props["lines"] = {"type": "integer", "minimum": 1,
                              "maximum": 50 if name == "read_log" else 100}
        if name == "container":
            props["action"]["enum"] = ["start", "stop", "restart"]
        if name == "reply":
            props["status"]["enum"] = ["FIXED", "NOTHING_TO_FIX", "BLOCKED", "INFO"]
        if name == "propose_menu_item":
            props["tier"]["enum"] = ["READ", "CHANGE", "DESTROY"]
            props["type"]["enum"] = ["ONE_TIME", "REPEATING"]
        tools.append({"name": name, "owner": owner, "tier": tier,
                      "description": DESCRIPTIONS[name], "openai_params": props,
                      "required": sorted(required), "xml_tag": name,
                      "xml_example": XML_EXAMPLES.get(name, ""),
                      "xml_content": "cmd" if "cmd" in props else "message"})
    actions.sort(key=lambda action: action["name"])
    for tool in tools:
        if tool["name"] == "run_igor_action":
            tool["openai_params"]["cmd"]["enum"] = [a["name"] for a in actions]
    tools = [t for t in tools if t["name"] != "run_igor_action" or actions]
    return {"tools": tools, "actions": actions}


def main():
    if sys.argv[1] == "names":
        print("\n".join(DESCRIPTIONS))
        return
    fields = sys.stdin.read().split("\0")[:-1]
    if len(fields) % 5:
        raise ValueError("invalid catalog records")
    print(json.dumps(build_catalog([fields[i:i + 5] for i in range(0, len(fields), 5)])))


if __name__ == "__main__":
    main()
