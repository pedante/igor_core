# Current interaction surface

Launch with `bash igor.sh --ai-tui`. The frontend projects the existing ordered
backend event stream and sends user input through its PTY. Classic and headless
paths remain available; Step 20 owns default launch and consolidation.

The standalone TUI's first `input_ready` no longer waits for provider-network
validation, a full server-context scan, or construction of the provider system
prompt around placeholder context. Those operations remain mandatory before the
first provider-bound request: the TUI shows CONNECTING while provider pre-flight
runs and PREPARING while full context is assembled. Context preparation still
loads the capability projection and refreshes the reviewed `host.memory`
observation before gathering/scrubbing context and rebuilding the authoritative
system prompt. A local mode change during this deferred window updates the mode
without forcing an early prompt render; the rebuilt prompt uses the current
mode.

The curses frontend also skips the classic backend presentation path before
READY: it does not render the classic system/header status block, enter the tmux
AI layout, print the classic banner, or build the classic right-pane command
reference. Those are presentation-only surfaces owned by the classic UI; the
standalone TUI already owns its screen, header and command palette.

The startup read of Core-owned `ai.verbose` still comes from Configuration
Service's current private SQLite authority on every session, but it uses a
narrow consumer that returns only the resolved value and global revision. It
does not compute a global configuration state token or rediscover module
configuration schemas; full inspection/write interfaces keep those stronger
namespace/state-token contracts. Local commands, settings/navigation and the
operator surface remain usable before the first provider request.

## Focus and navigation

Tab/Shift+Tab cycles input → output → panel (when open). Ctrl+B toggles the panel
and focuses it on opening; Ctrl+F returns to latest output without changing the
draft. Output focus uses Up/Down, Home/End and Page Up/Down to navigate activity.
The header identifies focus and whether the viewport is LIVE. New activity is
retained while browsing older output. Mouse wheel acts only over output, where
terminal support is available; clicking a region changes presentation focus.
Input focus retains prompt recall and editing. Panel Up/Down moves visible
section selection; Page Up/Down scrolls section content. Terminal resize and
panel toggling preserve the composer and backend projection.

Ctrl+P opens the existing local command palette. Typing `:` on an empty draft
opens the contract-driven operator explorer. Session startup publishes a
compiled `operator_snapshot` from loader-validated registration metadata. The
derived projection is cached at
`${IGOR_DATA_DIR}/cache/operator-surface-v1.json` and keyed by the current
structural registration digest, so unchanged sessions reuse it instead of
walking dynamic capability/configuration registries again. Type a segment to
filter; `.` or Enter descends; Backspace/Esc returns toward the root; `Ctrl+R`
requests the current compiled snapshot without losing the backend authority
boundary.

The compiled surface is presentation metadata, not runtime authority. Its
`availability_model` is `registration`: package/module/schema/enablement and
base contract changes invalidate the structural digest, while changing host
facts such as a binary appearing or disappearing do not. Selecting a capability
still enters the canonical dispatcher, which freshly resolves provider,
requirements, approval, privilege, execution-fence preconditions and
verification before effect. The explorer displays total/source counts and
distinguishes a populated projection, a genuinely empty set of registered
operator contracts, projection failures and a backend that has not returned a
snapshot. Browsing and refresh perform no model call or host probe. The cache is
disposable derived state; deleting or corrupting it causes a safe rebuild.

## Panel and inspection

The reusable panel holds data-backed sections rather than module-specific forms.
Session/AI and execution information come from current frontend events.
Provider/model display is read-only; an unreported role is unavailable. Enter on
History queries recent durable Operational History using the existing public
read-only CLI. Enter on Investigations lists durable investigation records
through its owning read-only CLI and the same structured renderer. Status,
evidence, hypotheses, judgments, findings and uncertainty remain reference data.
Enter on Settings reuses the existing backend settings editor.
No live System Model subprocess snapshot is presented as current session truth.
The structured renderer can display other owning-backend data when integrated;
this milestone does not create inspection APIs for missing panel content.

## Properties and controls

`core/ai/interaction.py` contains private presentation helpers for text, enum,
boolean, integer and number controls. A property describes its identifier,
label, type, current value, editability, source and applicable basic constraints.
Enum choices and numeric limits come from schema; no default configuration
values are invented. Missing values are unavailable. Unknown types and malformed
schemas/values are rejected. Secret properties are masked and cannot be edited.

Proposals contain detached typed values, without a storage location, executable
command or authority handle. A trusted integration must bind a proposal to its
own backend interface. Existing AI settings are the concrete integration: the
frontend adapts backend snapshots, collects a proposal, sends an existing
validated settings command, and waits for the returned snapshot. Basic frontend
validation does not replace backend validation or persistence semantics.
Size/duration and module/configuration schemas wait for real owning-backend
requirements. Nextcloud settings and Configuration Service authority are absent.

## Authority and recovery

Focus, panel, selection, viewport and drafts are disposable presentation state.
They cannot change facts, activation, automation, routing, safety, privilege,
approval or history. Read-only rendering performs no execution or file writes.
Conversation choices still use backend-owned pending-choice handling; there is
no dedicated question projection or frontend choice inference. Pending approvals
reuse current backend prompts, including exact `YES` for DESTROY. Sudo password
input goes directly to the backend PTY and bypasses drafts/history.

Closing/restarting the frontend does not apply a draft, property or selection.
A selected capability is sent back as `invoke <capability-id[@provider]> [JSON]`
and enters the existing structured `run_capability` dispatcher; the TUI does
not classify, approve, elevate, execute or verify it. Capabilities with required
inputs prepare a draft instead of guessing values. Non-capability leaves are
browse-only in this first slice.
No persistent layout migration or second history store is introduced.
The [15C investigation service](igor2/INVESTIGATIONS.md) owns durable knowledge
organization; 15D owns context relevance and model routing.
The [15UI contract](igor2/INTERACTION_SURFACE.md) and
[completion evidence](igor2/STATUS.md) record the milestone boundary.
