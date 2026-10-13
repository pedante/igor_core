# Increment C: generic interactive collection TUI

Increment C on local `igor2`, based on accepted B checkpoint
`9b09403f92b0ccefc28a21fe7e1ba30a4df06270`, was Owner accepted on 2026-10-13 at its
defined generic TUI scope: descriptor-driven rendering, navigation, page-local
filtering, canonical pagination, refresh, backend-session retention, event
correlation and frontend lifecycle handling. The Owner authorized one checkpoint
commit. No push, merge, live service operation, second provider registration or
Increment D READ inspection. The complete Collection Operator milestone remains open.

## Existing interfaces

The existing curses loop consumes canonical `action_result` events and operator
registry `collection`/`outputs` metadata. `collection_view.CollectionView` owns
only disposable presentation state. Admission/result checks call the existing
`capability_runtime` validators. No new schema framework, dispatcher, registry,
resource identity, backend session or execution protocol is introduced.

The existing `invoke` control accepts an optional bounded `--view=<32 hex>` token,
which is echoed as `view_request_id` on result/failure events. It neither enters
capability inputs nor authorizes execution. Existing `ai_execute_tool` preserves
mode, approval, privilege, History and operation identity. Validated collection
results publish before ordinary text truncation through the existing result
event writer; transcript output is a status summary with no rows/cursors.
Scalar and conversational result paths retain their meaning.

`:system`, `:sys` and direct `:system.service.list` resolve through the existing
explorer. Pasted leaf submissions use that same explorer/command resolution;
provider ambiguity remains visible. Page/refresh commands return to the same
PTY/backend process. The UI never reads the private snapshot cache.

## View, keys and bounds

- Up/Down, Home/End and Page Up/Down select/scroll loaded rows.
- Left/Right scroll declared columns; headers retain the descriptor list order
  despite sorted JSON object keys. Values render generically as bounded text,
  booleans, numbers or JSON data, with control characters removed from display.
- `/` edits a filter labelled **Page-local filter**; Enter/Esc finishes editing.
  Filtering never changes the backend inventory/query or reconstructs identities.
- `n` retrieves a continuation or moves to the next retained page; `p` returns to
  the previous retained page. At most one view/two 64 KiB domain pages survive.
- `r` refreshes explicitly with no cursor; page size derives from the validated
  first page. Backend cursor/scope/revision/budget validation remains authoritative.
- Esc/`b` closes the view, `:` returns to the explorer, Ctrl+P opens the existing
  palette, Tab returns to ordinary focus and F1 shows existing keyboard help.
- Enter highlights/selects only; no inspect target, shell command or row action
  executes. The selected D049 reference is opaque UI state.

Loading is non-blocking within the existing 100 ms curses input loop. A busy
backend does not accept a new page request; the view can be dismissed immediately.
An already admitted backend operation continues under existing execution limits;
this increment does not claim an interrupt/cancel mechanism for it. Existing
Ctrl+C/stop and approval/password handling retain priority.

Ready, empty, loading, invalid, unavailable and expired states are explicit.
UTC freshness bounds a conservative monotonic display deadline; paging/back does
not renew it. Expiry discards selectable page data and requires explicit refresh.
Invalid/rejected output is never shown as a valid collection. Frozen revision,
freshness, scope, row uniqueness, counts and page completeness are checked before
replacement. Registry removal/disable/descriptor changes invalidate the view;
session finish clears it. Tokens fence late refresh/page results after dismissal,
and existing event sequence/operation checks reject duplicates/stale events.

Action-result projection checks the 96 KiB UTF-8 event limit. Stream reads are
bounded to 256 KiB per iteration, incomplete lines to 1 MiB, with oversize-line
discard/recovery. Result pages do not accumulate in the activity transcript.
View inspection exposes state, selected reference, provenance, freshness, page
counts and request-pending status, excluding continuation values. Narrow terminals
and missing glyph/color support do not grant execution or leak rejected content.

## Evidence ledger

All executed plans were inspected with --dry-run and use the established governor.
Preserved reports and scenario qualifications are in `/tmp/igor2-c-evidence-ledger.json`.
Initial projection: 19 passes. Navigation: 36 passes. Lifecycle/bounds: 47 passes
before the final managed-secret fixture was added. Two new import lint diagnostics
and one new SIM114 were corrected; broad runner baseline classification did not
make them inherited failures. Final lint is clean for the selected files; the
runner's BASELINE_FIXED label does not imply unrelated baseline debt was repaired.

`/tmp/igor2-c-acceptance/summary.json`: 22 selected groups, complete in 93.070 s,
**403 PASS, 0 FAIL_NEW/FAIL_BASELINE, 2 BASELINE_FIXED, 1 ENV_SKIP; zero timeouts,
errors, cancellations or unavailable tools**. This covers affected TUI input,
settings, colors, privilege, PTY, explorer, command/CLI, transaction, approval,
modes, event, scrubbing, secret and History behavior plus the new collection tests
and actual controlled System slice. Prior unchanged ShellCheck and two Bash syntax
passes remain qualifying evidence. The permitted skip is LAN-IP scrubbing when
hostname -I is unavailable. The two baseline-fixed classifications mean the
selected lint group and stable-event identity pass; historical SIM103/History lint
and reviewed AI CLI/System fixtures were not repaired or represented as passing.

Final review corrected cell-width padding for wide/combining Unicode and made
inspection evaluate expiry before reporting state. These changed presentation
inputs only: ASCII System fixture text, event correlation, capability execution,
approval, privacy and History semantics stayed equivalent. The inspected focused
recheck `/tmp/igor2-c-display-correction/summary.json` completed in 8.138 s:
**109 PASS, 1 BASELINE_FIXED, zero failures/skips/timeouts/errors**. It covers the
49 collection scenarios plus affected existing TUI/color cases. No broad repeat.

Final diff review found that unknown-descriptor rejected-result warnings lacked
the existing 2000-item transcript cap. A one-line correction retained that bound;
`/tmp/igor2-c-warning-bound/summary.json` records **1 PASS, 1 BASELINE_FIXED,
zero failures/skips/timeouts/errors**, using the inspected exact malformed-event
node and lint selection. Successful collection/backend inputs remain unchanged.

The deduplicated qualifying ledger therefore records **408 PASS, 0 failures,
2 BASELINE_FIXED, 1 ENV_SKIP; zero required C checks unverified or cancelled**.
Earlier fixture failures and the three new lint diagnostics remain preserved and
classified as new failures in the historical ledger, regardless of broad runner
labels. No governor timeouts or tool-unavailable attempts occurred in C. Accepted
A/B baseline failures and skips remain documented limitations, not passing C gates.

The actual curses/PTY controlled System slice passed discovery (50/51 rows),
continuation (1/51), cached back, source change/explicit refresh, unique operation
IDs, no ordinary cursor display, view dismissal and backend session finish.
Its first two failures were fixture defects: expecting full strings in curses'
incremental terminal writes, then expecting an implicit stream at an explicit
path. Screen reconstruction and the existing explicit stream API corrected those
assertions; canonical page assertions were retained.

Synthetic fixtures exercise different resource labels, columns and primitive
types without registering a provider or parsing identities. Tests cover exact
64 KiB UTF-8 pages / 96 KiB events and overflows, malformed structures, frozen
membership/scope, stale/late/duplicate responses, private-data rejection, expiry,
module projection changes, dismissal and session shutdown.

| EXECUTION proof | Increment C evidence | Deferred |
|---|---|---|
| Contract | Shared validation, two fixture shapes, ordered columns, exact limits and safe narrow rendering. | D inspection transition, E independent provider. |
| Regression | Final affected TUI/operator/CLI/approval/privacy/History selections pass; unchanged shell inputs retain their governed proof. | Unrelated full release/CI gates. |
| Vertical slice | Actual curses/PTY and canonical System/page/refresh pass with the final scope/completeness guards; later padding changes preserve ASCII fixture rendering. | Pi-class performance and independent provider. |
| Inspection | Bounded UI inspect state/reference/page/provenance; no frontend execution authority. | Backend-authorized READ inspection. |
| Recovery | Expiry, malformed/mismatched results, registry disable/removal, late events and dismissal tests. | Detail/removal transitions in D/E. |

Measured x86_64 Linux 7.2.6 CachyOS/glibc 2.44: the first successful actual curses
fixture showed loading in 0.0116 s, a busy-key redraw in 0.0010 s, first page in
9.7935 s and cached back in 0.0047 s. These are controlled fixture observations,
not a latency guarantee or an optimization claim against B's 11.261-second
managed-secret first-page follow-up. Two hundred 128-row recording-screen renders
averaged 0.00683 s/frame; its pytest high-water RSS was unchanged at 58008 KiB,
which is not isolated incremental frontend peak-memory proof.

The final affected actual-curses run, under concurrent governed load, measured
loading at **0.02954 s**, busy-key redraw **0.00252 s**, first page **14.39537 s**,
cached back **0.00625 s**, and the full sequence **44.89402 s**. Frontend-process
VmRSS samples and VmHWM both went from **29344 to 32512 KiB** (+3168 KiB high-water
increment) for the 51-row fixture. This is a measured process high-water observation;
it does not establish maximum-page/Pi memory acceptance or allocator release.
The final corrected 200-frame recording-screen loop averaged **0.00744 s/frame**;
pytest-process ru_maxrss stayed at 56708 KiB and is not an isolated frontend peak.
Backend discovery/dispatch dominates first-page latency; no snapshot optimization
or limit adjustment was made. B's 11.261-second performance follow-up remains.
Raw measurements are in the acceptance and display-correction evidence directories.
Raspberry Pi,
maximum-rich-UTF-8 peak RSS and ten human-paced detail/back sequences remain
whole-milestone performance work; no accepted numerical limits were increased.

Production files: `core/ai/collection_view.py`, `core/ai/tui.py`, `core/ai/core.sh`,
`core/ai/safety.sh`. Tests: `tests/test_ai_tui_collections.py`,
`tests/test_ai_tui_collection_backend.py`. Documentation: this report,
`docs/igor2/STATUS.md`, `docs/igor2/OPERATOR_SURFACE.md`, `docs/igor2/LEGACY.md`,
`README.md`. The candidate manifest fingerprints all eleven files and preserved
reports; only final evidence/status documentation changed after the last test.

The checkpoint commit containing this Owner acceptance record closes Increment C
at its defined generic TUI scope. All eleven files matched the accepted manifest
before the two acceptance-document updates; production/tests and qualifying
evidence remain unchanged. No expensive qualifying validation was repeated.
The recorded latency, RSS/VmHWM and hardware-performance limitations remain.
D must add the
backend-authorized READ inspect transition using the accepted descriptor binding
and scoped selected reference; no inspection execution exists here. E must prove
an independent registered provider. No next increment starts automatically.
