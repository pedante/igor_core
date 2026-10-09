# Operator Interfaces: CLI and TUI

Status: **Igor 2 roadmap direction; Step 20 completion contract not yet implemented**.

Igor should expose one backend operating model through multiple frontends. The
CLI and TUI must not become separate command/permission systems.

## Shared rule

```text
TUI ----------\
CLI -----------+--> backend/session + owning services
automation ----+        -> capability policy/approval
future API ----/        -> privilege/execution/verification
                        -> History
```

A frontend may select, render and submit typed intent. It cannot invent facts,
bindings, capabilities, approvals, privilege or success.

## Step 20A — First-class CLI

The current headless inspection flags remain migration inputs. Igor 2 should
also offer one coherent user-facing CLI.

Target interaction shapes include:

```bash
igor "check why Nextcloud is slow"
igor ask "show me my Samba shares"

igor modules list
igor discover nextcloud
igor deployments list
igor deployments inspect <id>
igor capability inspect docker.install
igor config get system.memory.warning_threshold_mib

igor --json deployments list
```

Exact command spelling is implementation work; the contract is:

- natural-language one-shot use enters the normal Igor conversation/backend;
- structured commands address the same canonical backend objects;
- machine-readable output is versioned/typed enough for scripting;
- inspection remains read-only unless a canonical mutation is explicitly
  requested;
- interactive CLI may present the same approval and PTY authentication flow;
- non-interactive CLI never answers approval/authentication prompts on the
  user's behalf;
- when authorization is required but unavailable, return a clear typed/nonzero
  result such as approval required rather than silently changing policy;
- secrets stay redacted under the same projection rules;
- no CLI-only shell dispatcher or alternate privilege path exists.

CLI/headless operation remains available after the TUI becomes default.

## Step 20B — TUI completion

The full-screen TUI already has the interaction foundation. Completion means
turning backend contracts into a coherent operator experience, not merely
changing the default launcher.

The normal session should visually distinguish at least:

- user input;
- Igor conversational output;
- proposed/executing capability activity;
- command/tool output;
- success/verification results;
- warnings/errors/unknown state;
- pending question/choice;
- approval/privilege prompts.

Color/style may help, but meaning must not depend on color alone.

Generated backend-driven views should cover mature surfaces such as:

- System/current facts and health;
- Modules and availability;
- Discovery/recognition candidates and ambiguity;
- Deployments/relationships/responsibility;
- Configuration and source/desired/applied/observed distinctions;
- Capabilities and proposed effects;
- Operational History;
- Investigations;
- waiting/resumable work when implemented;
- AI/provider role state where useful.

### Proposal and approval review

Before a meaningful CHANGE/DESTROY, the UI should be able to present the
backend's frozen target/effects, current/requested value where applicable,
provider, privilege need, verification and recovery limitations.

Presentation does not replace canonical approval. DESTROY keeps its exact
confirmation rule.

### Configuration UX

Typed schema controls may edit proposals/staged values, show validation and
source/provenance, and submit through Configuration Service/canonical
capabilities. The TUI does not parse arbitrary module files or become the
configuration authority.

### Generated module/domain surfaces

Modules declare contracts and semantic metadata. The TUI groups/renders them
through shared projections. Modules do not ship a second custom frontend or
menu authority.

### Empty/error/refresh behavior

A surface must distinguish:

- genuinely empty;
- unavailable provider;
- failed refresh/projection;
- stale data;
- permission/approval required.

No indefinite blank panel should masquerade as success.

## Step 20C — Default cutover

Only after representative system/module/application workflows are usable through
shared backend contracts should `./igor.sh` launch the full-screen TUI by
default.

Preserve CLI/headless scripting, recovery and test paths. Keep `--ai-tui` as a
migration alias until removal is proven safe.

## Discovery interaction

Both CLI and TUI consume the same recognition candidate contract:

```text
find Nextcloud
  -> zero/one/many candidates
  -> inspect exact evidence
  -> select
  -> frozen adoption proposal
```

A user's "this one" answer selects a candidate; it is not proof or authority.

### A3 bounded recognition view (candidate)

A3's `recognition` CLI only projects a separately supplied A1 result; it
does not query the host. Examples:

```bash
# JSON produced by a trusted, reviewed recognition caller:
cat candidate.json | bash igor.sh --json recognition view
cat candidate.json | bash igor.sh recognition view
bash igor.sh --json recognition status  # unavailable until provider integration
```

The control panel's Recognition inspector consumes the same read-only model
and returns `unavailable` until A2 active-provider binding is implemented.
Nothing in this view selects a deployment or submits a proposal. A future
domain-discovery CLI and a live panel require separately verified active
module/provider eligibility and exact target inspection, without accepting
candidate data as authorization. This partial A3 view is not Step 20 CLI/TUI
completion.

## Proof gate

Before Step 20 completion, prove:

1. CLI and TUI invoke the same canonical capability without semantic drift;
2. a noninteractive CLI refuses/returns approval-required rather than bypassing
   policy;
3. discovery candidates and ambiguous selection render consistently;
4. configuration proposal/apply/readback distinctions are visible;
5. approval/privilege/result states are distinguishable from conversation;
6. History/Investigation/Deployment inspection uses owning-service records;
7. frontend restart cannot reinterpret stale selection as authority;
8. headless/JSON paths remain usable when TUI is default.
