"""Focused Step 20 public CLI routing tests."""

from __future__ import annotations

import json
import os
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_shell(script: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "-c", script, "_", *args],
        cwd=ROOT,
        env={**os.environ, "IGOR_DIR": str(ROOT)},
        text=True,
        capture_output=True,
        timeout=20,
        check=False,
    )


class OperatorCliTests(unittest.TestCase):
    def test_json_modules_normalizes_to_existing_backend_and_marks_json(self):
        script = r'''
source "$IGOR_DIR/core/lib/operator_cli.sh"
igor_operator_cli_normalize --json modules list || exit $?
printf '%s\n' "$IGOR_CLI_JSON"
printf '%s\n' "${_IGOR_OPERATOR_ARGS[@]}"
'''
        result = run_shell(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["true", "--modules"])

    def test_json_does_not_claim_machine_readable_conversation_output(self):
        for argv in (
            ("--json", "ask", "hello"),
            ("--json", "hello"),
            ("--json", "--help"),
            ("--json",),
        ):
            with self.subTest(argv=argv):
                quoted = " ".join(subprocess.list2cmdline([item]) for item in argv)
                result = run_shell(
                    f'source "$IGOR_DIR/core/lib/operator_cli.sh"; '
                    f'igor_operator_cli_normalize {quoted}'
                )
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_structured_cli_rejects_bad_arity(self):
        result = run_shell(
            r'''
source "$IGOR_DIR/core/lib/operator_cli.sh"
igor_operator_cli_normalize modules inspect
'''
        )
        self.assertEqual(result.returncode, 2)

    def test_default_tui_requires_zero_args_and_both_ttys(self):
        script = r'''
source "$IGOR_DIR/core/lib/operator_cli.sh"
printf '%s\n' "$(igor_operator_default_frontend 0 true true false)"
printf '%s\n' "$(igor_operator_default_frontend 1 true true false)"
printf '%s\n' "$(igor_operator_default_frontend 0 false true false)"
printf '%s\n' "$(igor_operator_default_frontend 0 true true true)"
'''
        result = run_shell(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            ["tui", "existing", "existing", "existing"],
        )

    def test_root_guard_precedes_default_frontend_exec(self):
        source = (ROOT / "igor.sh").read_text(encoding="utf-8")
        root_guard = source.index('Igor is intended to run as a normal user.')
        default_route = source.index('igor_operator_default_frontend "$#"')
        self.assertLess(root_guard, default_route)

    def test_json_modules_entrypoint_uses_structured_module_records(self):
        source = (ROOT / "igor.sh").read_text(encoding="utf-8")
        self.assertIn(
            'if [ "${IGOR_CLI_JSON:-false}" = true ]; then\n'
            '                    igor_module_records\n'
            '                else\n'
            '                    igor_module_list',
            source,
        )

    def test_public_structured_examples_normalize_without_new_authority(self):
        cases = [
            (("deployments", "list"), ["--deployments", "list"]),
            (("history", "recent"), ["--history", "recent"]),
            (("investigations", "list"), ["--investigations", "list"]),
            (("health", "summary"), ["--model", "summary"]),
            (("facts", "host:local"), ["--model", "facts", "host:local"]),
            (
                ("capability", "inspect", "system.host.summary"),
                ["--capabilities", "inspect", "system.host.summary"],
            ),
        ]
        for argv, expected in cases:
            with self.subTest(argv=argv):
                args = " ".join(subprocess.list2cmdline([item]) for item in argv)
                script = f'''
source "$IGOR_DIR/core/lib/operator_cli.sh"
igor_operator_cli_normalize {args} || exit $?
python3 - "${{_IGOR_OPERATOR_ARGS[@]}}" <<'PY'
import json,sys
print(json.dumps(sys.argv[1:]))
PY
'''
                result = run_shell(script)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), expected)


if __name__ == "__main__":
    unittest.main()
