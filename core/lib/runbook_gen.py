#!/usr/bin/env python3
"""
runbook_gen.py — Generate a draft YAML runbook from a session postmortem JSON.

Usage:
    python3 lib/runbook_gen.py <session_json_path> [--out <output_path>]

Reads the session postmortem JSON (P3-2 output) and produces a draft runbook YAML.
Writes to stdout if --out is not given.

Exit codes:
    0 — success
    1 — session JSON not found or insufficient data
    2 — error
"""

import sys
import os
import json
import re
from datetime import date


def _slug(text):
    """Turn problem text into a safe runbook id slug."""
    text = text.lower()
    text = re.sub(r'[^a-z0-9\s-]', '', text)
    text = re.sub(r'\s+', '-', text.strip())
    return 'nc-' + text[:40].rstrip('-')


def _extract_triggers(problem, hypothesis, commands_run):
    """Heuristically extract trigger keywords from session data."""
    candidates = set()
    text = ' '.join([problem or '', hypothesis or ''] + (commands_run or []))
    text_lower = text.lower()

    trigger_map = {
        'login': ['login', 'sign in', 'access denied', 'keeps asking'],
        'csrf': ['csrf', 'cookie check', 'strict cookie'],
        'cloudflare': ['cloudflare', 'tunnel', 'trusted_proxies'],
        '403': ['403', 'forbidden'],
        '404': ['404', 'not found'],
        'nginx': ['nginx', 'try_files', 'location', 'rewrite'],
        'redis': ['redis', 'session', 'memcache', 'locking'],
        'maintenance': ['maintenance', 'maintenance mode', 'upgrade', 'occ upgrade'],
        'container': ['container', 'docker', 'won\'t start', 'exited', 'oom'],
        'database': ['postgres', 'database', 'db', 'postgresql'],
        'permission': ['permission', 'chown', 'ownership', '1004'],
    }

    for trigger, keywords in trigger_map.items():
        for kw in keywords:
            if kw in text_lower:
                candidates.add(trigger)

    # Also add first 3 words of problem as literal triggers
    words = (problem or '').lower().split()
    for w in words[:4]:
        if len(w) > 3 and w not in ('the', 'and', 'for', 'with', 'this', 'that'):
            candidates.add(w)

    return sorted(candidates)


def _commands_to_steps(commands_run):
    """Convert commands_run strings to runbook step dicts."""
    steps = []
    for entry in (commands_run or []):
        # Format: "command → result" or just "command"
        if '→' in entry:
            parts = entry.split('→', 1)
            cmd = parts[0].strip()
            result_hint = parts[1].strip()[:100]
        else:
            cmd = entry.strip()
            result_hint = ''

        if not cmd:
            continue

        step = {
            'description': 'Verify: {}'.format(cmd[:80]),
            'command': cmd,
        }
        if result_hint:
            step['expect'] = result_hint
        steps.append(step)

    return steps[:8]   # cap at 8 steps for readability


def _yaml_str(s):
    """Safely quote a string for YAML."""
    if not s:
        return '""'
    # Use double-quoted if special chars present
    if any(c in s for c in ':{}[]|>&*!,#?-'):
        return '"' + s.replace('"', '\\"') + '"'
    return s


def generate_runbook(session):
    """Return runbook YAML string from session dict."""
    problem = session.get('problem', 'Unknown problem')
    model = session.get('model', '')
    provider = session.get('provider', '')
    session_id = session.get('session_id', '')
    root_cause = session.get('root_cause', '') or ''
    fix_applied = session.get('fix_applied', '') or ''
    runbook_used = session.get('runbook_used', '') or ''

    # Read scratchpad for richer data
    sp = session.get('scratchpad', {}) or {}
    hypothesis = sp.get('hypothesis', '') or ''
    commands_run = sp.get('commands_run', []) or []

    rb_id = _slug(problem)
    triggers = _extract_triggers(problem, hypothesis, commands_run)
    steps = _commands_to_steps(commands_run)

    today = date.today().isoformat()

    lines = []
    lines.append('id: {}'.format(rb_id))
    lines.append('name: {}'.format(_yaml_str(problem[:80])))
    lines.append('priority: medium')
    lines.append('draft: true')
    lines.append('last_updated: "{}"'.format(today))
    lines.append('generated_from: "{}"'.format(session_id))
    lines.append('stack: nextcloud-docker')
    lines.append('triggers:')
    for t in triggers:
        lines.append('  - {}'.format(_yaml_str(t)))
    if not triggers:
        lines.append('  - # add trigger keywords here')

    lines.append('steps:')
    if steps:
        for step in steps:
            lines.append('  - description: {}'.format(_yaml_str(step.get('description', ''))))
            lines.append('    command: {}'.format(_yaml_str(step.get('command', ''))))
            if step.get('expect'):
                lines.append('    expect: {}'.format(_yaml_str(step['expect'])))
            lines.append('    common_fix: "# TODO: describe fix if step fails"')
    else:
        lines.append('  - description: "# TODO: add diagnostic steps"')
        lines.append('    command: "# command"')
        lines.append('    expect: "# expected output"')
        lines.append('    common_fix: "# fix"')

    notes_parts = []
    if root_cause:
        notes_parts.append('Root cause: {}'.format(root_cause))
    if fix_applied:
        notes_parts.append('Fix applied: {}'.format(fix_applied))
    if runbook_used:
        notes_parts.append('Based on runbook: {}'.format(runbook_used))
    if model:
        notes_parts.append('Diagnosed by: {} ({})'.format(model, provider))
    notes_parts.append('Review and edit before using in production.')

    lines.append('notes: |')
    for note in notes_parts:
        lines.append('  {}'.format(note))

    return '\n'.join(lines) + '\n'


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Generate runbook YAML from session postmortem')
    parser.add_argument('session_json', help='Path to session postmortem JSON file')
    parser.add_argument('--out', help='Output YAML path (default: stdout)')
    args = parser.parse_args()

    if not os.path.isfile(args.session_json):
        print('runbook_gen: session file not found: {}'.format(args.session_json), file=sys.stderr)
        sys.exit(1)

    with open(args.session_json, 'r', encoding='utf-8') as f:
        session = json.load(f)

    if session.get('outcome') not in ('fixed', 'resolved', 'solved'):
        print('runbook_gen: session outcome is not "fixed" — skipping', file=sys.stderr)
        sys.exit(1)

    yaml_text = generate_runbook(session)

    if args.out:
        os.makedirs(os.path.dirname(args.out), exist_ok=True)
        with open(args.out, 'w', encoding='utf-8') as f:
            f.write(yaml_text)
        print('runbook_gen: written to {}'.format(args.out), file=sys.stderr)
    else:
        print(yaml_text)

    sys.exit(0)


if __name__ == '__main__':
    main()
