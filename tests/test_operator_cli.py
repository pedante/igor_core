"""Focused Step 20 public CLI routing tests."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
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
    def test_capability_json_arguments_survive_normalization(self):
        for inputs in (None, "", "{}", '{"label":"a } b", "count":2}'):
            with self.subTest(inputs=inputs):
                argv = ["capability", "run", "fixture.read"]
                if inputs is not None:
                    argv.extend([inputs, "fixture"])
                result = run_shell(r'''
source "$IGOR_DIR/core/lib/operator_cli.sh"
igor_operator_cli_normalize "$@" || exit $?
printf '%s\n' "${_IGOR_OPERATOR_ARGS[@]}"
''', *argv)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), [
                    "--capability-run", "fixture.read", inputs or "{}",
                    "fixture" if inputs is not None else "",
                ])

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


class PublicCapabilityCliTests(unittest.TestCase):
    """Real bootstrap/dispatcher in private storage, with a data-only READ fixture."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "igor.sh").write_bytes((ROOT / "igor.sh").read_bytes())
        (self.root / "core").symlink_to(ROOT / "core", target_is_directory=True)
        module = self.root / "modules/fixture"
        (module / "contracts").mkdir(parents=True)
        (self.root / "config").mkdir()
        (self.root / "config/modules.conf").write_text("fixture=enabled\n")
        (module / "module.conf").write_text("""[module]
module_api=2
name=fixture
display_name=CLI fixture
version=1.0.0
runtime=bash
entrypoint=module.sh
contracts=contracts/read.json

[requirements]
required_modules=
optional_modules=
required_capabilities=
optional_capabilities=
platform_families=
required_bins=

[compat]
v1_hooks=false
""")
        descriptor = {
            "kind": "capability", "id": "fixture.read", "handler": "fixture__read",
            "capability_version": 2, "description": "Read CLI fixture.",
            "inputs": {"properties": {"label": {"type": "string"}},
                       "required": [], "additionalProperties": False},
            "outputs": {"schema_version": 1,
                        "properties": {"label": {"type": "string"}},
                        "required": ["label"], "additionalProperties": False},
            "safety": {"tier": "READ"}, "privilege": "none", "preconditions": [],
            "verification": {"kind": "none", "required": False},
            "recovery": {"class": "not_applicable"}, "affects": [],
        }
        (module / "contracts/read.json").write_text(json.dumps({
            "contract_version": 1, "contributions": [descriptor],
        }))
        (module / "module.sh").write_text(r'''
printf 'source\n' >> "$IGOR_DIR/module-sources"
fixture__read() {
    local request
    IFS= read -r request || return 1
    python3 - "$request" "$IGOR_DIR/handler-inputs" <<'PY'
import json,sys
inputs = json.loads(sys.argv[1])["input"]
with open(sys.argv[2], "a", encoding="utf-8") as stream:
    stream.write(json.dumps(inputs) + "\n")
print(json.dumps({"status":"ok","result":{"label":inputs.get("label", "")}}))
PY
}
''')
        self.env = {**os.environ, "HOME": str(self.root / "home"),
                    "IGOR_DATA_DIR": str(self.root / "data"),
                    "IGOR_USE_TMUX": "true", "IGOR_FZF_ALREADY_ASKED": "false"}
        (self.root / "home").mkdir()
        # Abort on any startup feature/session/UI invocation, without replacing
        # security, module loading, approval, authentication or dispatch.
        guard = self.root / "startup-guard.sh"
        guard.write_text(r'''
set -T
trap 'case "$BASH_COMMAND" in
    igor_ensure_session*|igor_setup_features*|igor_layout_standard*|*"Press any key to continue"*)
        printf "unexpected startup UI: %s\n" "$BASH_COMMAND" >&2; exit 97 ;;
esac' DEBUG
''')
        self.env["BASH_ENV"] = str(guard)

    def cli(self, *args):
        return subprocess.run(["bash", str(self.root / "igor.sh"), *args],
                              env=self.env, input="", text=True, capture_output=True,
                              timeout=35, check=False)

    def assert_read(self, result, label=""):
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("Outcome: success", result.stdout)
        self.assertIn("label: " + label, result.stdout)
        self.assertNotIn("TOOL:", result.stdout)
        self.assertIn("History: bash igor.sh history inspect op-", result.stdout)
        self.assertNotIn("Press any key", result.stderr + result.stdout)
        self.assertNotIn("[module_loader]", result.stderr + result.stdout)
        self.assertTrue((self.root / "data/runtime/locks").is_dir())

    def test_public_read_disable_reenable_json_and_history(self):
        self.assert_read(self.cli("capability", "run", "fixture.read", "{}", "fixture"))
        inputs = self.root / "handler-inputs"
        self.assertEqual([json.loads(line) for line in inputs.read_text().splitlines()], [{}])
        sources_before = (self.root / "module-sources").read_text()
        (self.root / "config/modules.conf").write_text("fixture=disabled\n")
        result = self.cli("capability", "run", "fixture.read", "{}", "fixture")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(inputs.read_text().splitlines()), 1)
        self.assertEqual((self.root / "module-sources").read_text(), sources_before)
        (self.root / "config/modules.conf").write_text("fixture=enabled\n")
        self.assert_read(self.cli("capability", "run", "fixture.read"))
        label = 'spaces } and "quotes"'
        self.assert_read(self.cli("capability", "run", "fixture.read",
                                  json.dumps({"label": label}), "fixture"), label)
        # Also reach the legacy flag's argument handling without normalization.
        self.assert_read(self.cli("--capability-run", "fixture.read", "{}", "fixture"))
        self.assertEqual([json.loads(line) for line in inputs.read_text().splitlines()],
                         [{}, {}, {"label": label}, {}])
        history = self.cli("history", "recent", "10")
        self.assertEqual(history.returncode, 0, history.stderr)
        records = json.loads(history.stdout)
        self.assertEqual(len(records), 4)
        for record in records:
            self.assertEqual(record["provenance"]["interface"], "cli")
            self.assertEqual(record["provenance"]["actor"], "operator")
            self.assertEqual(record["outcome"], "success")
            self.assertEqual(record["provider"]["id"], "fixture")
            self.assertEqual(record["provider"]["owner"], "fixture")
            self.assertEqual(record["approval"]["result"], "not_required")
            self.assertEqual(record["privilege"]["result"], "not_required")

    def test_invalid_inputs_and_noninteractive_change_never_execute(self):
        for raw in ("{", "[]", '{"unknown":true}'):
            result = self.cli("capability", "run", "fixture.read", raw)
            self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse((self.root / "handler-inputs").exists())
        contract = self.root / "modules/fixture/contracts/read.json"
        data = json.loads(contract.read_text())
        data["contributions"][0]["safety"]["tier"] = "CHANGE"
        contract.write_text(json.dumps(data))
        result = self.cli("--json", "capability", "run", "fixture.read", "{}")
        self.assertEqual(result.returncode, 3, result.stderr + result.stdout)
        self.assertEqual(json.loads(result.stdout)["status"], "approval_required")
        self.assertFalse((self.root / "handler-inputs").exists())

    def test_existing_system_read_runs_through_public_cli(self):
        (self.root / "modules/system").symlink_to(ROOT / "modules/system",
                                                  target_is_directory=True)
        (self.root / "config/modules.conf").write_text("system=enabled\nfixture=disabled\n")
        result = self.cli("--json", "capability", "run", "system.host.memory.refresh", "{}", "system")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn('"outcome":"success"', result.stdout)
        self.assertIn('"verification_status":"passed"', result.stdout)
        history = self.cli("history", "recent", "10")
        self.assertEqual(history.returncode, 0, history.stderr)
        records = json.loads(history.stdout)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["capability"]["id"], "system.host.memory.refresh")
        self.assertEqual(records[0]["provenance"]["interface"], "cli")
        self.assertEqual(records[0]["outcome"], "success")

    def test_json_is_canonical_and_redacted_failure_is_nonzero(self):
        self.env["CLI_TEST_SECRET"] = "private-fixture-value"
        result = self.cli("--json", "capability", "run", "fixture.read",
                          json.dumps({"label": self.env["CLI_TEST_SECRET"]}))
        self.assertEqual(result.returncode, 0, result.stderr)
        row = json.loads(result.stdout)
        self.assertEqual(row["result"]["label"], "[REDACTED]")
        self.assertNotIn(self.env["CLI_TEST_SECRET"], result.stdout + result.stderr)
        history = self.cli("history", "inspect", row["operation_id"])
        self.assertEqual(json.loads(history.stdout)["outcome"], row["outcome"])
        (self.root / "modules/fixture/module.sh").write_text('''fixture__read() {
    printf '%s\\n' '{"status":"error","error":{"code":"fixture_unavailable","message":"unavailable"}}'
}
''')
        result = self.cli("--json", "capability", "run", "fixture.read", "{}")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        row = json.loads(result.stdout)
        self.assertEqual(row["execution_status"], "failed")
        self.assertEqual(row["outcome"], "failed")
        self.assertTrue(row["operation_id"].startswith("op-"))

    def test_classic_startup_still_enters_session_setup(self):
        result = self.cli("--classic")
        self.assertEqual(result.returncode, 97)
        self.assertIn('unexpected startup UI: igor_ensure_session "$@"', result.stderr)


if __name__ == "__main__":
    unittest.main()
