#!/usr/bin/env bash
# Developer validation only; no Igor runtime initialization.
set -euo pipefail
exec "${IGOR_VALIDATE_PYTHON:-python3}" "$(dirname "${BASH_SOURCE[0]}")/validation_runner.py" "$@"
