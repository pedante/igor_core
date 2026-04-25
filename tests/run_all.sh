#!/bin/bash
# =============================================================================
#  Igor Test Suite — tests/run_all.sh
#
#  Runs all tests: existing bash/python suites + BATS suites.
#  Usage: bash tests/run_all.sh [--fast]   (--fast skips integration tests)
#
#  Exit code: 0 = all pass, 1 = any failure.
# =============================================================================

set -o pipefail

IGOR_DIR="${IGOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export IGOR_DIR

_pass=0; _fail=0; _skip=0
_fast="${1:-}"

_section() { echo ""; echo "══════════════════════════════════════════════════"; echo "  $1"; echo "══════════════════════════════════════════════════"; }
_ok()      { echo "  ✔  $1"; (( _pass++ )); }
_fail()    { echo "  ✗  $1"; (( _fail++ )); }
_skip()    { echo "  ·  SKIP  $1"; (( _skip++ )); }

# ── Check for bats ─────────────────────────────────────────────────────────────
_have_bats=false
_bats_cmd=bats
for _b in bats /usr/local/bin/bats /home/pooo/.npm-global/bin/bats; do
    if command -v "$_b" &>/dev/null || [ -x "$_b" ]; then
        _bats_cmd="$_b"; _have_bats=true; break
    fi
done

# ── 1. Existing bash tests ─────────────────────────────────────────────────────
_section "Existing bash tests (test_igor_core.sh)"
if bash "${IGOR_DIR}/tests/test_igor_core.sh"; then
    _ok "test_igor_core.sh"
else
    _fail "test_igor_core.sh"
fi

# ── 2. Existing python tests ────────────────────────────────────────────────────
_section "Existing python tests (test_ai_render.py)"
if command -v python3 &>/dev/null && python3 -c "import unittest" 2>/dev/null; then
    if python3 -m pytest "${IGOR_DIR}/tests/test_ai_render.py" -q 2>/dev/null \
       || python3 -m unittest discover -s "${IGOR_DIR}/tests" -p "test_ai_render.py" -q; then
        _ok "test_ai_render.py"
    else
        _fail "test_ai_render.py"
    fi
else
    _skip "test_ai_render.py (python3/unittest not available)"
fi

# ── 3. BATS tests ──────────────────────────────────────────────────────────────
if ! $_have_bats; then
    _section "BATS tests"
    echo "  ⚠  bats not installed — skipping BATS suites."
    echo "     Install: sudo apt install bats   OR   npm install -g bats"
    (( _skip += 3 ))
else
    _section "BATS — core/"
    if "$_bats_cmd" "${IGOR_DIR}/tests/core/"; then
        _ok "tests/core/ (all BATS)"
    else
        _fail "tests/core/ (one or more BATS failures)"
    fi

    _section "BATS — modules/"
    if "$_bats_cmd" "${IGOR_DIR}/tests/modules/"; then
        _ok "tests/modules/ (all BATS)"
    else
        _fail "tests/modules/ (one or more BATS failures)"
    fi

    if [ "$_fast" != "--fast" ]; then
        _section "BATS — integration/"
        if "$_bats_cmd" "${IGOR_DIR}/tests/integration/"; then
            _ok "tests/integration/ (all BATS)"
        else
            _fail "tests/integration/ (one or more BATS failures)"
        fi
    else
        _skip "tests/integration/ (--fast mode)"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════"
printf "  Results:  %d passed  %d failed  %d skipped\n" "$_pass" "$_fail" "$_skip"
echo "══════════════════════════════════════════════════"
echo ""

[ "$_fail" -eq 0 ]
