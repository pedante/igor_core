# Igor Codex Handoff

## Current status

Roadmap Steps 1–7 are complete. The full-screen UI now has practical keyboard navigation and a searchable command palette; the classic UI remains available.

Step 7 follow-up: semantic TUI colors, short-lived conversational choices, and native sudo authentication are implemented without moving policy or execution into the frontend.

## Established backend contracts

- Step 1: provider transactions, canonical action results, session states, safety classification, policy, and private runtime.
- Step 2: the command/action registry in `core/ai/session_commands.py`; typed commands and palette selections use the same backend route.
- Step 3: pending approval with Run/Skip/Explain/Stop and exact `YES` for destructive actions.
- Step 4: one Guide/Assist/Executive mode value, persisted in the existing AI settings; legacy `exec on` maps to Executive and `exec off` to Assist. Pending decisions block mode changes.
- Step 5: `core/ai/events.sh` emits ordered JSONL frontend events for session, model, assistant, action lifecycle, approval, explanation, continuation, warning/error, mode, and finish states. The classic renderer remains available.

## Frontend boundary and Step 7 UI

- `core/ai/tui.py` is a small Python standard-library curses frontend. It reads the Step 5 event stream, retains a bounded activity view, and keeps a multiline input area at the bottom. It has a basic registry-backed palette, resize handling, and visible approval hints.
- Launch with `bash igor.sh --ai-tui`. Use `bash igor.sh` for the classic line UI, initial provider setup, or a terminal without curses support. `--ai-tui-backend` is the internal PTY entry point to the existing `menu_ai` session.
- The frontend sends user text and approval responses to the backend PTY. The backend still resolves commands, mode policy, classification, authorization, execution, and provider transactions. Structured events supply assistant, action, result, warning, and error activity. PTY text is shown only as one opaque fallback block for local commands without event output; it never determines state or policy. Event-backed output suppresses that fallback, so replies and results appear once. Activity wraps and reflows from complete stored text, and repeated warnings are compacted.
- TUI sessions use a private per-run JSONL stream in the existing runtime directory. The classic renderer and backend safety behavior remain intact. Existing WIP is kept for explicit later resumption rather than prompting inside the full-screen startup.
- Step 7 palette entries come from the Step 2 command registry, with substring filtering, command descriptions, and visible unavailable states. Ordinary selections send the same text to the backend route as typed commands; commands needing arguments fill the draft. Esc closes the palette and preserves the draft. Availability display is advisory; backend authorization remains authoritative.
- The palette's Settings entry and typed `settings` in TUI mode open a keyboard settings view. It displays a `settings_snapshot` event sourced from the live backend session and sends edits through registered settings, mode, and verbose commands. Provider, model, temperature, max tokens, mode, verbose, AI autostart, and hybrid menu are editable. The classic `settings` command keeps its textual summary. The TUI holds only the latest frontend projection; the existing AI settings file remains the sole persistence store.
- F1 shows keys. Enter sends; Ctrl+O or Alt+Enter inserts a line. Arrows, Home/End, Backspace/Delete, Ctrl+W, and Esc edit or clear the draft. Up/Down recall prior prompts from this TUI session when not moving within multiline input. Ctrl+P or `:` on an empty input opens the palette. Page Up/Down and Shift+Up/Down navigate activity; Home/End move to oldest/latest when the draft is empty. The header shows when the view is older than live output. Ctrl+G folds successful tool output; failures stay visible. Ctrl+C or `/stop` sends the existing stop action.
- Activity distinguishes user input, Igor messages, progress, action class, approval, output/result, explanations, and warnings/errors. Incoming events do not alter the input draft. The UI retains a bounded current-session activity view and prompt list without a new database or history subsystem.
- Activity colors are assigned from structured event types: user/input, Igor prose, actions, output, and warning/error use a restrained palette. Curses attribute styling remains readable without color.
- `core/ai/core.sh` keeps the latest explicit assistant alternatives as ephemeral structured choice state. Numbered, ordinal, and unambiguous text replies add a resolved choice to the original user reply. Answering, stopping, a local command, or a clearly new topic clears the state. The provider does not authorize actions through this state.
- Approved sudo actions use the backend's exact pending command. `privilege_waiting` / `privilege_result` events tell the TUI when to show a hidden password prompt; keystrokes go straight to native sudo through the backend PTY and never enter the editable draft, history, events, or provider messages. Cached OS credentials may be reused, while Igor's normal action authorization still runs for each action. Without a suitable terminal or successful authentication, the action fails closed. Executive does not bypass sudo or DESTROY confirmation.

## Validation

- `python3 -m unittest tests.test_ai_tui tests.test_ai_tui_step7 tests.test_ai_tui_pty -q`: 47 tests pass, including palette filtering/invocation, unavailable entries, navigation, prompt history, multiline editing, folded output, incoming-event draft stability, approval hints, and Step 6 rendering/PTy coverage.
- `bats tests/core/test_ai_tui_backend.bats`: 5 tests pass.
- A real curses PTY interaction exercised palette `stats`, a fresh prompt, Guide READ approval, Run, tool output, a warning, and a final reply. The backend received `stats`, `check sample`, and `run` in order; the display contained the expected activity without `Terminal:` prefixes.
- Python compile checks and `git diff --check` pass. Ruff is unavailable locally.
- Settings editor follow-up: 83 focused Python tests and 27 relevant core BATS pass across registry, backend persistence/snapshots, mode/event contracts, TUI settings interactions, and prior TUI coverage. `bash -n` and `git diff --check` pass. A real curses PTY exercise opened Settings from the palette, toggled Verbose, and returned to the prompt; the backend received `settings snapshot`, `verbose on`, and a second snapshot in order. Ruff and ShellCheck are unavailable locally.
- `bash tests/run_all.sh`: 46 Bash checks, 46 existing Python checks, 261 core BATS, and 40 integration BATS pass. Three module BATS tests in `tests/modules/test_system_storage.bats` retain the documented missing-`nextcloud_docker` storage expectation failures; the module was not restored. The runner exits 1 for those baseline failures. The final save-hook guard was subsequently covered by the focused tests above.
- Step 7 follow-up: 8 pending-choice BATS, 4 privilege BATS, 8 event BATS, and 192 Python AI tests pass. A real dispatcher PTY fixture with a fake sudo executable exercised the native tty password path and confirmed the password was absent from terminal output, events, and audit records. `bash -n`, Python compile, and `git diff --check` pass. ShellCheck and Ruff are unavailable locally.
- Follow-up full `bash tests/run_all.sh`: 46 Bash checks, 46 existing Python checks, 271 core BATS pass with 2 environment skips, and all 40 integration BATS pass. The same three `tests/modules/test_system_storage.bats` expectations fail because the `nextcloud_docker` tree is absent; this remains the documented baseline and was not restored. The runner exits 1 only for those module tests.

## Remaining issues

The UI keeps only current-session prompt/activity history; older backend sessions remain accessible through existing backend commands. Palette state reflects known structured session status, while the backend remains the final gate for state-dependent commands. No mouse support or fuzzy search was added.
