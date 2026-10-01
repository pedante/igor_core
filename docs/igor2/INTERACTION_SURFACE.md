# Step 15UI — Interaction Surface Foundation

Status: **implemented bounded interaction foundation**. Validation and closure
evidence are recorded in [STATUS.md](STATUS.md).

15UI introduces the reusable interaction mechanics needed for Igor's current
full-screen TUI to become a practical control surface before Step 20 makes it
the default interface.

It is intentionally placed after Step 15B Operational History and the small
provider-neutral Decision/Judgment Contract, and before Step 15C Durable
Investigations:

```text
15A -> 15B -> Decision/Judgment Contract -> 15UI -> 15C -> 15D
```

This ordering gives the UI durable operational truth and a stable vocabulary for
model judgments without making presentation code responsible for AI policy.
15C can then add durable investigation state to an interaction framework that
already knows how to inspect, select, edit and render structured backend data.
15D adds context relevance and model-role routing behind the same boundary.

## Implemented boundary

The existing `--ai-tui` frontend remains the interaction surface. Its ordered
frontend events and bounded session activity projection remain presentation
state; they are not an Operational History database. The panel reads durable
history through the existing public `--history recent` CLI, without observer refresh,
replay, recovery, reset or execution. Session mode, provider/model, approvals
and execution results come from the current backend event projection.

Schema/property controls collect proposed values. The existing AI settings
backend is the concrete editable semantic-setting integration; frontend code
sends its existing commands and waits for a backend snapshot. This is not a
new Configuration Service, module schema contract or file writer. Future
configuration owners must supply schema and bind submission to their own
validated authority boundary. Secret-value editing/display is excluded.

Current backend contracts do not publish a model-role registry, live judgment
feed or dedicated conversational-question projection. Missing information is
unavailable rather than inferred. Judgment records remain reference data;
15D owns routing. Typed conversational replies still reach the existing
backend choice lifecycle, including cancellation. Approval and exact `YES`
DESTROY confirmation remain backend-owned; sudo input still goes directly to
the backend PTY.

## Step 15C integration

The confirmed [investigation service](INVESTIGATIONS.md) now supplies a read-only
Investigations panel section through `--investigations list`. It reuses the lazy
bounded CLI loader and structured renderer. The UI owns no investigation
persistence, lifecycle updates, judgment invocation or operational authority.
Historical 15UI completion evidence remains separate from this 15C addition.

## Step 15D integration

The [context/routing contract](CONTEXT_ROUTING.md) supplies the latest actual
backend decision through `context_routing` events. The read-only Context / Routing
section displays included/excluded metadata, reasons, limits, optional judgment
status and role/provider/model selection rule. Opening the section invokes no
source collector, model, observer or policy edit. These projections remain
disposable operational provenance, not durable memory. `--context last` exposes
retained audit metadata; `--context select` is explicitly a read-only preview.

## Operator Surface integration

The initial [Operator Surface](OPERATOR_SURFACE.md) extends the same frontend
boundary with a contract-derived `operator_snapshot`. The backend projects its
existing module, contribution, capability and configuration registries; the TUI
does not scan packages or invent actions.

`Ctrl+P` remains the local command palette. `:` on an empty draft opens the
operator namespace explorer, where dotted navigation is a presentation path.
Selecting a zero-input capability submits an `invoke` request back to the
backend; required inputs remain explicit and no frontend default is invented.
The backend adapts `invoke` into the existing `run_capability` dispatcher, so
safety tier, approval, privilege, provider resolution, verification and History
are unchanged. Other contribution kinds remain browse-only in this first slice.

## Current primitives

[Current UI documentation](../interaction_surface.md) lists the operator keys.
`core/ai/interaction.py` owns implementation-private presentation helpers;
`core/ai/tui.py` integrates them with the existing event projection and PTY.

- Tab/Shift+Tab cycles input, output and the open panel. Ctrl+B toggles the
  panel; Ctrl+F returns to latest output independently of draft contents.
- Output focus makes arrows/Home/End navigation explicit. Page Up/Down scrolls
  output outside panel focus; mouse wheel scrolls only over output. The header
  identifies focus and LIVE versus historical output.
- Panel selection uses Up/Down; Page Up/Down navigates selected content.
  Session, read-only AI, Settings, Operational History and latest result are
  data-backed sections. Settings and History use their existing backend paths.
- Property types are text, enum, boolean, integer and number. Properties carry
  identity, label, value availability, editability, source and presentation
  constraints. Unsupported types/fields fail closed. A proposal contains only
  `property_id` and a typed `value`; trusted owning-backend integration binds it
  to an edit interface. There is no command or storage path in the schema.
- Structured rendering is bounded and read-only, preserving displayed source
  and provenance. Secret properties are masked and cannot submit proposals.

Size, duration and richer module schemas are deferred until a concrete owning
backend requires them; the conceptual Nextcloud example below remains a future
schema contribution, not an implemented setting.

## Goals

15UI should provide the reusable primitives for:

- mouse-wheel scrolling over Igor output/history;
- keyboard navigation and movable selection;
- explicit focus among output, prompt/input and controls;
- a toggleable control panel that does not replace the conversation;
- reusable text, selector, boolean and typed value editors;
- read-only rendering of structured subsystem inspection data;
- schema-driven configuration/property presentation;
- visibility into current AI role/provider/model activity where that data is
  already authoritative;
- consistent rendering of pending questions, approvals and choices owned by the
  existing interaction runtime.
- contract-driven discovery of active module capabilities/configuration/checks
  without adding module-owned TUI menus.

The result should feel like one operator surface over Igor's backend, not a
collection of menus that each reimplement domain behavior.

## Non-goals

15UI does **not**:

- make the TUI authoritative for configuration, history, investigations,
  capabilities, safety, approval, privilege or provider selection;
- implement Step 15C durable investigations;
- implement Step 15D context relevance/model routing;
- choose when to invoke a cheap/helper model;
- add Jet, Laya or another named model/provider to Igor's public contract;
- make model price/provider names part of UI semantics;
- add Nextcloud-specific settings screens;
- require every module to expose rich properties immediately;
- make the TUI the default launcher yet;
- remove CLI/headless/recovery interfaces;
- read or mutate arbitrary config files directly from presentation code.

Step 20 remains the default-TUI/consolidation milestone after backend workflows
are ready.

## Backend owns truth

The interaction surface follows one rule:

> The backend owns truth and policy; the UI renders state and submits typed
> user intent.

The TUI may show a configuration value, capability, provider, history episode,
pending approval or model role only through the owning subsystem's public
inspection/edit boundary.

A widget must not infer authority from presentation state. Selecting a row,
opening a panel, changing a local control or displaying a model suggestion
cannot itself:

- activate a module;
- change desired state;
- approve an operation;
- grant privilege;
- select an execution provider;
- mark a fact fresh;
- change a verification outcome;
- enable an automation;
- create executable capability authority.

## Interaction layout

The current conversation remains the primary surface. 15UI adds a compact
toggleable control panel rather than replacing the prompt with a menu-driven
application.

Conceptually:

```text
+ IGOR --------------------------------+ CONTROL ----------------+
|                                      | Session                  |
| output / conversation                | Modules                  |
|                                      | Configuration            |
| mouse-wheel / keyboard history       | History                  |
|                                      | AI roles                 |
+--------------------------------------+--------------------------+
| > user input                         | apply / reset where valid|
+--------------------------------------+--------------------------+
```

The exact geometry is a frontend decision. The contract is that output,
input and controls have explicit focus and predictable navigation.

## Scrolling and selection

15UI should make long-running Igor sessions usable without terminal workarounds.

Minimum interaction behavior:

- mouse wheel scrolls the output viewport when the pointer is over output;
- keyboard scrolling works without moving or corrupting prompt input;
- reaching historical output does not stop new backend events from being
  retained;
- returning to the live edge is explicit/predictable;
- selection is visible and movable with keyboard controls;
- focus state is visible;
- a pending Igor question remains the authoritative conversational choice even
  while the user browses older output or opens the control panel;
- malformed frontend state cannot manufacture a backend choice/approval.

The current structured frontend event stream remains presentation data. It does
not become the Operational History store.

## Toggleable control panel

The control panel is a reusable container for subsystem inspection surfaces.

Initial sections may expose, when available:

- session/mode state;
- active modules and availability;
- configuration status and editable semantic settings;
- recent Operational History;
- current pending interaction/approval;
- capability/context inspection;
- AI role/provider/model status and cost/token metadata.

A section may be absent when its backend contract does not exist yet. The panel
must degrade cleanly rather than read private subsystem storage.

15C can later add an Investigations section. 15D can later add context/routing
inspection without replacing the panel framework.

## Schema-driven configuration and properties

15UI should establish a generic renderer, not application-specific forms.

Conceptually a backend-owned semantic property may expose:

```text
id: nextcloud.php.memory_limit
type: size
value: 1024MB
editable: true
source: module
```

The UI can render that as a typed field because the schema describes the
semantics. The UI does not learn where the value is stored or how Nextcloud is
configured.

Useful primitive field types include:

- string/text;
- boolean;
- enum/selector;
- integer/number;
- size;
- duration;
- path/reference where explicitly safe;
- secret reference/status without secret-value display.

The Configuration Service/owning backend remains responsible for validation,
scope, provenance, defaults, secret handling, migration, write semantics and
verification.

Rich properties such as Nextcloud upload size, memory limits or application
settings are therefore a later module/configuration contribution. They are a
useful proof case, not a prerequisite for 15UI.

## AI communication visibility

15UI should make model use understandable without making the TUI the model
router.

The panel may display backend-reported information such as:

- active role (for example reasoner or semantic scout);
- provider/model actually used;
- local versus remote where known;
- invocation/fallback reason;
- latency;
- token/cost information where available;
- bounded result/validation status.

The role concepts are described in [MODEL_ROLES.md](MODEL_ROLES.md) and
[AI_SPECIALISTS.md](AI_SPECIALISTS.md).

The actual decision about whether a cheap/local helper should interpret,
compress or rank context belongs to the provider-neutral Decision/Judgment
Contract plus Step 15D routing. 15UI only renders the resulting state and lets
the user edit supported policy/configuration through backend-owned settings.

## Decision/Judgment dependency

Before 15UI exposes AI decision state, Igor should establish the small
provider-neutral Decision/Judgment Contract planned after 15B.

That contract should define at least:

- a small versioned judgment/result schema;
- explicit abstain/unknown behavior;
- provenance/evidence references;
- provider-neutral invocation/result interfaces;
- validation and failure/fallback semantics;
- tests proving judgment output cannot become operational authority.

The contract should not introduce named models such as Jet/Laya, a provider
solver, recursive agents or Step 15D routing policy.

15UI consumes that vocabulary for presentation only.

## Relationship to 15C and 15D

15C owns durable investigation state. It should plug into 15UI through an
inspection/edit contract rather than teaching the TUI how investigations are
stored.

15D owns relevance and routing integration. It may use deterministic signals
and validated model judgments to choose context/model roles, but the resulting
decision/provenance should be inspectable through the same UI foundation.

This keeps the dependency direction:

```text
backend authority/state
        |
        v
inspection/edit contracts
        |
        v
15UI presentation
```

not:

```text
TUI state -> backend policy
```

## Compatibility and migration

15UI extends the existing full-screen TUI and interaction runtime. It must not
introduce a second session state machine.

During migration:

- `--ai-tui` remains usable;
- CLI/headless inspection remains available;
- classic paths remain until Step 20/23 has evidence that they can be retired;
- new controls call existing/shared backend contracts;
- no subsystem may become observable only through the TUI.

## Completion proof

A bounded 15UI implementation should prove at minimum:

### Contract proof

- focus, scrolling, selection and panel state cannot mutate backend authority;
- typed controls reject malformed values before submission;
- backend validation remains authoritative;
- secret values are not exposed by generic property rendering;
- model/judgment display is informational and cannot grant execution authority.

### Regression proof

- existing interaction, approval, privilege and pending-choice tests remain
  green;
- CLI/headless behavior remains available;
- the TUI still renders existing frontend events correctly.

### Vertical slice

Use real backend data for at least:

- one scrolling conversation/output session;
- one movable selection/control-panel interaction;
- one editable non-secret semantic setting or isolated fixture through its
  owning backend;
- one read-only Operational History view when 15B is available.

### Inspection proof

The operator can distinguish:

- focus/selection state;
- current backend mode/session state;
- source/provenance for rendered structured data where available;
- model role/provider state where available;
- validation errors without corrupting the session.

### Migration/recovery proof

- resizing/reopening/toggling the panel does not lose authoritative session
  state;
- UI reset is presentation reset unless an explicit backend reset operation is
  invoked;
- a frontend crash/restart does not reinterpret stale UI selections as pending
  approvals or configuration writes.

## Step 20 hand-off

15UI is not Step 20 moved earlier.

15UI builds the reusable interaction primitives while Step 15 is still being
implemented. Step 20 later makes the full-screen TUI the default and
consolidates mature subsystem surfaces after normal workflows use shared
backend contracts.

That distinction lets Igor improve day-to-day usability now without coupling
architecture progress to a final UI rewrite.
