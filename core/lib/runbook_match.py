#!/usr/bin/env python3
"""
runbook_match.py — Match user input against YAML runbooks and emit a formatted block.

Usage:
    python3 lib/runbook_match.py <runbooks_dir> "<user_message>"

Exit codes:
    0  — match found, runbook block printed to stdout
    1  — no match
    2  — error (bad args, unreadable dir, etc.)

PyYAML is optional — falls back to a minimal YAML parser for the subset used here.
"""

import sys
import os
import re


def _load_yaml_minimal(text):
    """
    Minimal YAML loader that handles the subset used in Igor runbooks:
    - top-level key: value (scalar)
    - top-level key: | (block scalar)
    - top-level list (triggers, steps) with - items
    - step dicts with description/command/expect/common_fix keys
    Returns a dict. Not a general YAML parser.
    """
    result = {}
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        # Skip blank lines and comments
        if not line.strip() or line.strip().startswith('#'):
            i += 1
            continue

        # Top-level key
        m = re.match(r'^(\w[\w_-]*):\s*(.*)', line)
        if not m:
            i += 1
            continue

        key = m.group(1)
        val = m.group(2).strip()

        # Block scalar |
        if val == '|':
            i += 1
            block_lines = []
            while i < len(lines) and (not lines[i] or lines[i][0] == ' '):
                block_lines.append(lines[i].rstrip())
                i += 1
            # Dedent
            if block_lines:
                indent = len(block_lines[0]) - len(block_lines[0].lstrip())
                result[key] = '\n'.join(l[indent:] for l in block_lines)
            else:
                result[key] = ''
            continue

        # List value (next lines start with '  -')
        if val == '':
            # Peek
            items = []
            i += 1
            while i < len(lines) and lines[i].startswith('  '):
                item_line = lines[i]
                if re.match(r'^\s+-\s+', item_line):
                    item_val = re.sub(r'^\s+-\s+', '', item_line).strip().strip('"')
                    # Check if this is a dict item (step)
                    if i + 1 < len(lines) and re.match(r'^\s{4,}\w', lines[i + 1]):
                        # dict item: collect key: value pairs
                        step = {}
                        i += 1
                        while i < len(lines) and re.match(r'^\s{4,}\w', lines[i]):
                            sm = re.match(r'^\s+(\w[\w_]*):\s*"?(.*?)"?\s*$', lines[i])
                            if sm:
                                step[sm.group(1)] = sm.group(2)
                            i += 1
                        items.append(step)
                        continue
                    else:
                        items.append(item_val)
                i += 1
            result[key] = items
            continue

        # Quoted scalar
        val = val.strip('"').strip("'")
        result[key] = val
        i += 1

    return result


def load_runbook(path):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    try:
        import yaml  # type: ignore
        data = yaml.safe_load(text)
    except ImportError:
        data = _load_yaml_minimal(text)
    return data


def score_runbook(runbook, user_msg):
    """Return match score (0 = no match). Higher = better match."""
    triggers = runbook.get('triggers', [])
    if not triggers:
        return 0
    msg_lower = user_msg.lower()
    score = 0
    for trigger in triggers:
        t = str(trigger).lower()
        if t in msg_lower:
            # Longer trigger = more specific = higher weight
            score += len(t.split())
    return score


def format_runbook_block(runbook):
    lines = []
    lines.append("=== RUNBOOK: {} ===".format(runbook.get('name', runbook.get('id', 'unknown'))))
    lines.append("Priority: {}".format(runbook.get('priority', 'normal')))
    lines.append("")
    lines.append("Diagnostic steps (follow in order):")

    steps = runbook.get('steps', [])
    for idx, step in enumerate(steps, 1):
        if isinstance(step, dict):
            desc = step.get('description', '')
            cmd = step.get('command', '')
            expect = step.get('expect', '')
            fix = step.get('common_fix', '')
            lines.append("")
            lines.append("Step {}: {}".format(idx, desc))
            if cmd:
                lines.append("  Command: {}".format(cmd))
            if expect:
                lines.append("  Expected: {}".format(expect))
            if fix:
                lines.append("  Fix if wrong: {}".format(fix))

    notes = runbook.get('notes', '')
    if notes:
        lines.append("")
        lines.append("Notes:")
        for note_line in notes.strip().splitlines():
            lines.append("  {}".format(note_line))

    lines.append("")
    lines.append("=== END RUNBOOK ===")
    return '\n'.join(lines)


def main():
    if len(sys.argv) < 3:
        print("Usage: runbook_match.py <runbooks_dir> <user_message>", file=sys.stderr)
        sys.exit(2)

    runbooks_dir = sys.argv[1]
    user_msg = sys.argv[2]

    if not os.path.isdir(runbooks_dir):
        print("runbook_match: directory not found: {}".format(runbooks_dir), file=sys.stderr)
        sys.exit(2)

    best_score = 0
    best_runbook = None

    for fname in os.listdir(runbooks_dir):
        if not fname.endswith('.yaml') and not fname.endswith('.yml'):
            continue
        fpath = os.path.join(runbooks_dir, fname)
        try:
            rb = load_runbook(fpath)
        except Exception as e:
            print("runbook_match: skipping {}: {}".format(fname, e), file=sys.stderr)
            continue

        score = score_runbook(rb, user_msg)
        if score > best_score:
            best_score = score
            best_runbook = rb

    if best_runbook is None or best_score == 0:
        sys.exit(1)

    print(format_runbook_block(best_runbook))
    sys.exit(0)


if __name__ == '__main__':
    main()
