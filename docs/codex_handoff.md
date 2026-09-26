# Igor Codex Handoff

## Current status

Steps 1–6 are complete. Step 7 can build on the first full-screen AI frontend.

## Established backend contracts

- Step 1: provider transactions, canonical action results, session states, safety classification, policy, and private runtime.
- Step 2: the command/action registry in `core/ai/session_commands.py`; typed commands and palette selections use the same backend route.
- Step 3: pending approval with Run/Skip/Explain/Stop and exact `YES` for destructive actions.
- Step 4: one Guide/Assist/Executive mode value, persisted in the existing AI settings; legacy `exec on` maps to Executive and `exec off` to Assist. Pending decisions block mode changes.
- Step 5: `core/ai/events.sh` emits ordered JSONL frontend events for session, model, assistant, action lifecycle, approval, explanation, continuation, warning/error, mode, and finish states. The classic renderer remains available.

## Step 6 frontend

- `core/ai/tui.py` is a small Python standard-library curses frontend. It reads the Step 5 event stream, retains a bounded activity view, and keeps a multiline input area at the bottom. It has a basic registry-backed palette, resize handling, and visible approval hints.
- Launch with `bash igor.sh --ai-tui`. Use `bash igor.sh` for the classic line UI, initial provider setup, or a terminal without curses support. `--ai-tui-backend` is the internal PTY entry point to the existing `menu_ai` session.
- The frontend sends user text and approval responses to the backend PTY. The backend still resolves commands, mode policy, classification, authorization, execution, and provider transactions. Structured events supply assistant, action, result, warning, and error activity. PTY text is shown only as one opaque fallback block for local commands without event output; it never determines state or policy. Event-backed output suppresses that fallback, so replies and results appear once. Activity wraps and reflows from complete stored text, and repeated warnings are compacted.
- TUI sessions use a private per-run JSONL stream in the existing runtime directory. The classic renderer and backend safety behavior remain intact. Existing WIP is kept for explicit later resumption rather than prompting inside the full-screen startup.

## Validation

- `python3 -m unittest tests.test_ai_tui tests.test_ai_tui_pty`: 32 tests pass, including multiline grouping, duplicate suppression, resize/reflow, redaction placeholders, warnings/debug, ordered events, PTY interactions in all three modes, and a backend startup failure.
- `bats tests/core/test_ai_tui_backend.bats`: 5 tests pass.
- A real curses PTY interaction rendered assistant text, tool output, warning/error, and a final reply from a fixture backend without `Terminal:` prefixes or scrub debug flood.
- `bash -n igor.sh core/ai/core.sh`, Python compile checks, and `git diff --check` pass.
- `bash tests/run_all.sh`: 46 Bash checks, 46 existing Python tests, 261 core BATS, and 40 integration BATS pass. Three module BATS checks retain the known missing-`nextcloud_docker` storage expectation failures. The module was not restored. ShellCheck and Ruff are unavailable locally.

## Step 7 prerequisites

Use the existing event/input boundary and canonical registry. Step 7 may add richer palette search, history, mouse support, and polish without moving policy into the frontend. No Step 7 features were implemented here.
