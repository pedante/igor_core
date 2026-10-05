# Igor 2 resumable work and external dependencies

Status: **accepted design direction; runtime implementation and explicit Igor 2 proof remain future**.

This document extends structured plans with durable waiting and resumption semantics for work that cannot complete synchronously.

Motivating cases include OAuth, DNS propagation, browser authorization, reboot, maintenance windows, commands/actions on another machine, hardware intervention, or another condition outside the current Igor process.

## Product goal

Igor should never need to block indefinitely because the next step is controlled by a person or external system.

~~~text
plan runs
   ↓
external/user dependency reached
   ↓
persist exact waiting state
   ↓
return control to user
   ↓
dependency later becomes satisfiable
   ↓
verify condition
   ↓
resume the same plan safely
~~~

A user may leave Igor entirely and continue later without relying on chat history to reconstruct the work.

## Architectural invariants

1. Waiting is explicit plan state, not a sleeping shell process.
2. The reason for waiting, expected condition and resume point are durable.
3. A user saying "done" does not prove the external condition succeeded; Igor verifies whenever possible.
4. Resume cannot skip ownership, precondition, policy, approval, privilege or capability checks.
5. Restart/crash must not silently rerun an already executed state-changing step.
6. A waiting plan does not acquire new authority because time passed or a callback arrived.
7. Polling/automation may detect readiness but does not authorize the next state-changing operation.
8. Chat history is never the canonical record of a suspended workflow.
9. External provider text does not become executable shell authority.
10. Resumable work is generic infrastructure for configuration, installation, repair and migration.

## Relationship to structured plans

D030 already establishes structured plans for installation, configuration, repair and migration. This proposal adds lifecycle states and durable continuation semantics.

A conceptual vocabulary:

~~~text
PENDING
READY
RUNNING
WAITING_USER
WAITING_EXTERNAL
SUCCEEDED
FAILED
SKIPPED
~~~

Exact names should align with existing plan/history vocabularies when implemented.

## Waiting record

A suspended step needs enough durable information to explain and resume work without replaying prior actions.

~~~json
{
  "plan_id": "configure-cloudflare-17",
  "step_id": "authorize-account",
  "state": "waiting_external",
  "waiting_for": "oauth_authorization",
  "resume_step": "verify-authorization",
  "created_at": "...",
  "expires_at": null,
  "verification": {
    "capability": "cloudflare.authorization.status",
    "inputs": {}
  }
}
~~~

This is illustrative, not a selected schema. A waiting record must not persist arbitrary executable commands or secret values.

## WAITING_USER

Use when progress requires an explicit human action Igor cannot perform.

Examples include connecting a device, entering a code elsewhere, confirming a physical change, choosing among materially different options, or rebooting manually when reboot is not authorized.

Igor should explain the required action, why it is needed, what will be checked afterward, how to resume, and whether the plan expires.

## WAITING_EXTERNAL

Use when progress depends on an external system or condition.

Examples include OAuth/device authorization, DNS propagation, certificate challenge, provider-side provisioning, remote service availability, maintenance window opening or asynchronous approval.

Igor may offer periodic checking when an appropriate Automation capability exists.

## External commands and provider instructions

A provider may instruct the user to run something such as cloudflared tunnel login.

Igor must not treat arbitrary remote text as executable authority. A module/setup workflow may instead declare a known bounded action such as cloudflare.authorize whose reviewed handler/capability performs the expected authorization under normal policy.

~~~text
provider/setup requirement
        ↓
known registered authorization action
        ↓
Igor policy / approval / privilege
        ↓
execute
        ↓
verify expected credential/state
        ↓
continue or wait
~~~

Unknown provider instructions are reference information, not auto-executed shell text.

## OAuth and device-code example

~~~text
Configure Microsoft email
  ✓ account selected
  ✓ local non-secret settings
  ⏸ waiting for account authorization
~~~

Igor can show a device code/URL, persist the suspended plan, and return to the normal interface.

Later:

~~~text
user: continue email setup
        ↓
load plan
        ↓
verify authorization with provider
        ↓
if ready: continue
if not: remain waiting with current evidence
~~~

The conversation may locate the plan, but the plan record is authoritative.

## DNS propagation example

~~~text
WAITING_EXTERNAL
condition: expected TXT record visible
verification: DNS observation capability
~~~

Igor can offer periodic checking through Automation. When the condition becomes true, automation records readiness or notifies. It does not automatically authorize later CHANGE/DESTROY unless policy independently permits unattended execution.

## Reboot example

A reboot-dependent plan should record steps already committed, expected post-reboot condition, resume point, whether reboot was authorized/executed, and a correlation identity that survives restart.

At next startup Igor may report:

> Configuration X is waiting for post-reboot verification.

Verification occurs before earlier changes are marked successful.

## Resumption triggers

### Manual

The user says continue Cloudflare setup. Igor verifies the condition before resuming.

### Polling/Automation

A normal READ automation evaluates the declared condition periodically.

### External callback

A future authenticated interface may receive a callback and mark a dependency potentially ready. Callback data remains untrusted until validated against the expected plan/dependency.

### Startup/restart inspection

Igor discovers suspended work after restart and surfaces it. Discovery does not automatically execute the next state-changing step.

## Authority on resume

Resumption re-evaluates active owner/module, capability provider, current inputs, preconditions, safety tier, remote/local authority context, privilege requirement, expiry and relevant configuration/deployment identity.

A plan created under an old policy does not retain unlimited authority forever.

If previously approved exact work may safely retain approval across a wait, that must be explicit contract behavior rather than assumption.

## Exactly-once and interruption semantics

Each step needs durable execution identity or claim state sufficient to distinguish never started, claimed/running, completed with canonical result, and interrupted with unknown external effect.

This follows the same principle proven by Step 14B: after durable claim, restart must not blindly execute the same slot again.

For state-changing steps, interrupted/unknown outcome requires verification or explicit reconciliation before retry.

## Verification

Each waiting dependency should define how readiness is established where possible.

~~~text
oauth_authorization -> token/status check
dns_propagation     -> DNS observation
service_available   -> health observation
device_connected    -> device discovery
reboot_completed    -> boot identity + postcondition
maintenance_window  -> current time/policy
~~~

Human assertion is retained with provenance only where deterministic verification is impossible.

## History and provenance

Step 15 operational history is the natural durable record of plan creation, completed steps, waiting-state entry, dependency, readiness checks, resume attempts and final result.

The resumable plan store holds current authoritative workflow state; history records what happened over time.

## Configuration integration

~~~text
Email Configuration
  ✓ SMTP
  ✓ IMAP
  ⏸ administrator verification
      ↓
return to Igor
      ↓
later resume same configuration plan
~~~

A configuration UI need not remain open for hours or survive terminal disconnect.

## Installation and migration integration

The same mechanism applies to provider authorization, service provisioning, reboot-required migrations, maintenance windows, storage moves, DNS/certificate changes and other external dependencies.

This avoids subsystem-specific marker files and resume logic.

## Automation integration

~~~text
resumable plan owns:
  what work is suspended and why

automation owns:
  when/how a readiness check runs

capability/policy owns:
  what may execute when work resumes
~~~

Do not collapse these into one scheduler-specific state model.

## Inspection and UX

Useful inspection may include:

~~~text
work list
work inspect <plan-id>
work continue <plan-id>
work cancel <plan-id>
~~~

The TUI can surface waiting work. Cancelling a plan must explain whether committed external changes remain and what recovery/compensation is available.

## Persistence

The exact backend follows ownership decisions rather than driving them.

Durable state needs plan identity/version, current step/state, input references, committed result/correlation IDs, waiting dependency, resume/verification descriptor, timestamps/expiry and recovery metadata—without raw secrets.

Persistent schema migrations follow D031.

## Failure behavior

- Invalid or unsupported waiting state fails closed.
- Unknown plan version never guesses a resume path.
- Disabled/stale module makes the contribution unavailable with a precise reason.
- Failed readiness checks normally leave the plan waiting unless contract says terminal failure.
- Provider timeout does not imply success or failure.
- Expired authorization/grant is re-established rather than reused silently.
- Failed resume does not erase prior evidence.

## Non-goals

This design does not require a distributed workflow engine, arbitrary DAG jobs, a permanent background daemon, continuous polling, keeping a UI open, executing provider-supplied shell text, automatic retry of unknown-effect CHANGE, or bypassing capability approval on resume.

## Roadmap fit

Resumable Work is now an explicit Igor 2 completion gate rather than an
unassigned design proposal.

- D030 structured plans provide the base representation.
- Step 14 Automation can check selected future conditions without owning plan authority.
- Step 15 history records waits, resumes and outcomes.
- Step 17 configuration and the Provisioning/Installation gate may need continuation.
- Step 19 deployment identity/bindings provide stable targets across waits.
- Step 20 CLI/TUI surfaces waiting work and resume/cancel controls.
- Step 22 external interfaces may deliver callbacks or remote continuation requests.
- Step 23 removes subsystem-specific resume markers only after equivalent behavior is proven.

The first runtime slice should be selected from a real workflow with a genuine
external/user/restart dependency. Do not implement a generic durable workflow
engine merely to satisfy the roadmap.

## Proof requirements for implementation

1. **Contract proof** — malformed or unsupported wait records fail closed and cannot inject execution.
2. **Regression proof** — synchronous plans/capabilities remain unchanged when no wait exists.
3. **Vertical-slice proof** — one real workflow enters durable wait, Igor exits/restarts, dependency is verified, and the plan resumes without repeating the committed step.
4. **Inspection proof** — waiting reason, plan identity, resume condition and prior result are visible without secrets.
5. **Migration/recovery proof** — persistent wait state has explicit schema versioning and interruption/reconciliation behavior.

## Questions left for later decisions

- exact plan persistence backend;
- final state vocabulary;
- approval lifetime across long waits;
- cancellation/compensation semantics;
- callback authentication and correlation;
- whether readiness automation may resume READ-only steps or only mark/notify readiness;
- plan retention and garbage collection.
