#!/usr/bin/env python3
"""Boundary N registration timing contracts."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ModuleRegistrationTimingTests(unittest.TestCase):
    def test_tui_registration_timings_partition_v1_and_v2_modules(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            modules = root / "modules"
            (modules / "legacy").mkdir(parents=True)
            (modules / "modern" / "contracts").mkdir(parents=True)
            (root / "config").mkdir()
            (root / "data").mkdir()

            (modules / "legacy" / "module.conf").write_text(
                "name=legacy\ndisplay_name=Legacy\n", encoding="utf-8"
            )
            (modules / "legacy" / "module.sh").write_text(
                "legacy__register() { igor_register_hook health legacy__health; }\n"
                "legacy__health() { printf 'ok:legacy\\n'; }\n",
                encoding="utf-8",
            )

            (modules / "modern" / "module.conf").write_text(
                """[module]
module_api=2
name=modern
display_name=Modern
version=1.0.0
runtime=bash
entrypoint=module.sh
contracts=contracts/contract.json

[requirements]
required_modules=
optional_modules=
required_capabilities=
optional_capabilities=
platform_families=
required_bins=

[compat]
v1_hooks=false
""",
                encoding="utf-8",
            )
            (modules / "modern" / "contracts" / "contract.json").write_text(
                '{"contract_version":1,"contributions":[]}', encoding="utf-8"
            )
            (modules / "modern" / "module.sh").write_text(
                "modern__register() { :; }\n", encoding="utf-8"
            )
            (root / "config" / "modules.conf").write_text(
                "modern=enabled\n", encoding="utf-8"
            )

            script = r"""
source "$REPO/core/lib/module_loader.sh"
igor_load_all_modules >/dev/null
for name in $_IGOR_TUI_MODULE_REGISTRATION_ORDER; do
    printf 'module:%s:%s\n' "$name" "${_IGOR_TUI_MODULE_REGISTRATION_BY_NAME[$name]}"
done
for key in legacy.v1.dependencies legacy.v1.syntax legacy.v1.source legacy.v1.hooks legacy.v1.finalize \
           modern.v2.preflight modern.v2.compat modern.v2.contributions modern.v2.consumer; do
    printf 'phase:%s:%s\n' "$key" "${_IGOR_TUI_MODULE_PHASE_MS[$key]}"
done
printf 'reconcile:%s\n' "$_IGOR_TUI_MODULE_REGISTRATION_RECONCILE_MS"
printf 'aggregate:%s\n' "$_IGOR_TUI_MODULE_REGISTRATION_MS"
"""
            result = subprocess.run(
                ["bash", "-c", script],
                cwd=ROOT,
                env={
                    **os.environ,
                    "REPO": str(ROOT),
                    "IGOR_DIR": temp,
                    "IGOR_DATA_DIR": str(root / "data"),
                    "IGOR_TUI_MODE": "true",
                },
                text=True,
                capture_output=True,
                timeout=30,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        rows = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        module_rows = [row for row in rows if row.startswith("module:")]
        self.assertEqual({row.split(":")[1] for row in module_rows}, {"legacy", "modern"})
        for row in rows:
            if row.startswith(("module:", "phase:", "reconcile:", "aggregate:")):
                value = row.rsplit(":", 1)[-1]
                self.assertRegex(value, r"^\d+$", row)


if __name__ == "__main__":
    unittest.main()
