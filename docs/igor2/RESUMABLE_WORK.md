# Resumable Work & External Dependencies — design proposal

Status: **design proposal; no implementation in this PR**.

This document extends Igor's structured-plan direction so work may pause for a
user or external dependency without blocking a process, losing context, or
pretending completion.

The motivating examples include OAuth/device authorization, DNS propagation,
provider login flows, reboot requirements, maintenance windows, hardware/user
intervention and temporarily unavailable external services.

## Problem

Some legitimate operational work cannot complete in one uninterrupted process.

Examples:

- Cloudflare asks the user to authorize in a browser;
- an email provider requires a device code;
- a DNS TXT record must propagate;
- a certificate challenge must become visible;
- a reboot is required before verification;
- a NAS must become reachable;
- a user must complete an action on another machine;
- work must wait for a maintenance window.

A shell wizard commonly handles this badly by:

- blocking indefinitely;
- losing its place when the process exits;
- trusting the user's statement instead of verifying completion;
- embedding polling loops in feature-specific code;
- repeating already completed steps after restart.

Igor should instead persist the work and resume it deliberately.

## Core principle

**Igor does not wait forever. It persists why work is paused, returns control,
and resumes only after the dependency is verified.**

Waiting is a first-class state of structured work, not a failure and not
completion.

## Relationship to structured plans

D030 already establishes structured plans for installation, configuration,
repair and migration.

This proposal adds durable waiting/resumption semantics to those plans.

It does not create a second workflow engine.

A plan remains an ordered/structured set of resolved work with:

- preconditions;
- capabilities;
- approval/privilege points;
- affected objects;
- recovery semantics;
- verification.

A waiting step records an external dependency that must become satisfied before
the plan may continue.

## Step states

A useful minimum vocabulary is:

- PENDING: not yet eligible;
- READY: eligible to run;
- RUNNING: actively executing;
- WAITING_USER: explicit human action/input is required;
- WAITING_EXTERNAL: a non-user external condition must become true;
- SUCCEEDED: terminal verified success for this step;
- FAILED: terminal failure unless the plan defines an explicit retry/recovery;
- SKIPPED: deliberately not executed under plan semantics.

Exact implementation names may change, but waiting must remain distinct from
running, failed and succeeded.

A crash while RUNNING is not silently converted to success. Existing
interrupted/unknown principles remain applicable.

## Waiting record

A waiting step should persist enough structured information to answer:

- what are we waiting for;
- who/what can satisfy it;
- when the wait started;
- whether there is a deadline/expiry;
- how completion is verified;
- which plan and step resume afterward;
- whether automated checking is allowed;
- what user-facing instructions are safe to show;
- what happens on timeout/cancellation.

The record stores references and non-secret metadata, not secret tokens unless a
dedicated secret service owns them.

## Waiting categories

The contract should stay small and typed. Likely categories include:

### User action

The user must do something that Igor cannot safely or physically perform.

Examples:

- approve in browser;
- press hardware button;
- insert a drive;
- complete a provider confirmation.

### External condition

Igor can verify a condition but cannot force it immediately.

Examples:

- DNS record visible;
- remote service reachable;
- certificate issued;
- replication completed.

### Time/window

Work may resume only after a defined time or maintenance window.

This may integrate with Automation without turning time into an ad-hoc sleep
loop.

### Restart/reboot boundary

The machine or a managed service must restart before the next verification
phase.

The persisted plan must survive the boundary if the workflow claims resumability.

Only add categories when they change behavior; avoid a sprawling workflow DSL.

## Verification before resume

A user statement such as:

    I authorized it.

is a request to re-check, not proof.

The next transition is:

    user says done
      -> run declared verifier
      -> verified true: resume
      -> verified false: remain waiting and explain

The verifier must be a registered observer/check/capability or other
Igor-owned deterministic mechanism appropriate to the dependency.

Model output cannot mark a wait satisfied.

## External commands requested by providers

Providers sometimes instruct users to run a command, for example a login helper.

Igor must not execute arbitrary command text simply because a remote provider
returned it.

A supported setup flow should instead know the expected bounded action, for
example conceptually:

    cloudflare.authorize

which may internally invoke the reviewed provider CLI through the normal
capability/policy boundary.

After execution Igor verifies the expected result.

Unexpected provider instructions remain untrusted text.

## OAuth and device authorization

A common flow is:

    request authorization
      -> receive URL/device code
      -> persist WAITING_USER
      -> return control
      -> user authorizes elsewhere
      -> verify token/credential status
      -> continue plan

The authorization URL/code may have an expiry. Expired state returns to an
explicit restart/reissue step rather than looping indefinitely.

Secret access/refresh tokens remain owned by the secret service.

## DNS and propagation waits

Example:

    create/confirm desired DNS record
      -> WAITING_EXTERNAL: dns_record_visible
      -> optional scheduled checks
      -> deterministic DNS verification
      -> resume

The plan should retain the expected record identity/value hash as needed for
verification without exposing unrelated credentials.

## Automation integration

Automation may check a waiting condition when policy allows.

A waiting plan is not itself an automation scheduler.

Conceptually:

    waiting record
      -> automation/check tick
      -> verifier
      -> condition false: remain waiting
      -> condition true: mark wait satisfied
      -> resume policy decides whether next work runs automatically or awaits
         user attention/approval

Resumption must not silently bypass approval that would have been required in a
continuous local flow.

Step 14's persistence/claim rules should inform this design, especially
duplicate prevention and interrupted/unknown behavior.

## User notifications

A waiting workflow may optionally request notification when:

- action from the user is required;
- a condition becomes true;
- the wait expires;
- resumed work succeeds/fails.

Notification delivery failure does not alter the underlying waiting state.

Admin Communications is a natural consumer.

## Return control and later resume

Configuration or install flows should not trap the user.

Example:

    Configure email
      ✓ SMTP
      ✓ IMAP
      ⏸ WAITING_USER: verify administrator GPG challenge

Igor returns to the originating TUI/AI interaction with a structured status.

Later the user may say:

    continue email setup

or:

    what am I waiting for?

Igor resolves the durable plan/waiting record and continues from the stored
boundary.

Conversation history is not the durable workflow state.

## Resume identity

A resumable plan needs stable identity independent of a specific shell process
or chat.

At minimum retain:

- plan/work ID;
- step ID;
- owner/source;
- affected deployment/object references where applicable;
- current state;
- waiting record;
- prior completed step outcomes;
- verification/recovery status needed to resume safely.

The exact storage backend is deferred.

## Restart and crash semantics

Resumable work must define behavior across process and machine restart.

Rules should include:

- completed steps are not repeated solely because Igor restarted;
- a persisted WAITING state remains waiting;
- a RUNNING step interrupted without a committed terminal result becomes
  interrupted/unknown rather than retried blindly;
- resume revalidates relevant preconditions/freshness before continuing;
- state format migrations follow D031.

## Idempotency and duplicate prevention

A resume action must not execute the same committed step twice.

Plan step execution should use durable claim/transition semantics compatible
with the principles already proven by Step 14B.

Where the external system is not idempotent, the plan/capability must declare
the limitation and use verification/reconciliation before retry.

## Deadlines, expiry and cancellation

Waiting records may define:

- expiry/deadline;
- next suggested check time;
- maximum automated checks;
- cancellation behavior.

Expiry is an explicit state/outcome, not silent deletion.

Cancelling a waiting plan must not undo prior changes unless an explicit
recovery/compensation plan exists.

## Security and authority

Resumability cannot weaken authorization.

In particular:

- approval is not cached forever merely because a plan is waiting;
- privilege credentials are never persisted for later use;
- post-wait CHANGE/DESTROY steps still use current policy;
- external callbacks/messages are untrusted until authenticated/validated;
- a provider cannot redefine the plan by returning instructions;
- model interpretation cannot satisfy a deterministic wait condition;
- secrets remain referenced/mediated.

A plan may persist that a user approved a specific frozen action where the
existing authority contract explicitly permits that approval to remain valid,
but this requires deliberate semantics; it is not the default assumption.

## Configuration integration

Configuration surfaces use resumable work when setup requires external/user
dependencies.

Examples:

- email OAuth;
- GPG challenge verification;
- Cloudflare browser login;
- DNS validation.

The Configuration Service owns settings. The resumable plan owns progress
through the setup/apply workflow. These are not the same state.

## Installation and migration integration

The same mechanism should support:

- installer waiting for provider authorization;
- migration waiting for maintenance window;
- update requiring reboot;
- restore waiting for storage availability.

This prevents each subsystem from inventing custom marker files and retry loops.

## History integration

Step 15 Operational History should eventually record meaningful plan/wait
transitions such as:

- entered waiting;
- dependency verified;
- resumed;
- expired/cancelled;
- terminal result.

Operational History is evidence/audit; it is not the mutable workflow store.

## Inspection

When resumable work becomes authoritative Igor should expose read-only
inspection sufficient to answer:

- what work is active/waiting;
- why it is waiting;
- what the user must do;
- what verifies completion;
- when it expires/next checks;
- what already completed;
- what operation would run next;
- whether next work will require approval/privilege.

The inspection path must not itself resume or execute work.

## Resource profile

The mechanism must remain low-resource:

- no requirement for a resident workflow daemon;
- persistence may be file/SQLite-backed;
- checks run only on explicit resume or configured Automation cadence;
- bounded state;
- no busy-wait polling.

## Relationship to roadmap

This design spans existing roadmap work:

- D030 structured plans: base abstraction;
- Step 14 Automation: optional condition/time checks and durable claim lessons;
- Step 15 Operational History: durable evidence of transitions;
- Step 17 deployments: stable affected deployment/object identity;
- Step 20 TUI: display waiting work and resume actions;
- Step 22 external interfaces: authenticated callbacks/remote continuation;
- Step 23 consolidation: remove legacy ad-hoc wait/retry markers after cutover.

Implementation sequencing is deferred until reconciled with the roadmap.

## Non-goals of this proposal

This PR does not:

- implement a general DAG/workflow engine;
- create a daemon;
- implement OAuth;
- implement external callbacks;
- change Step 14 automation behavior;
- persist sudo credentials;
- make every command resumable;
- guarantee rollback across an external wait;
- allow model output to advance workflow state.

## Proposed design decisions for reconciliation

Decision numbers are intentionally not assigned in this PR to avoid conflicts
with parallel design proposals.

1. Structured Igor work may enter durable WAITING_USER or WAITING_EXTERNAL
   states rather than blocking or pretending failure/completion.
2. A wait records a typed dependency plus a deterministic verification/resume
   contract.
3. User statements and model output may request verification but cannot satisfy
   a wait by themselves.
4. Resumption preserves normal policy/approval/privilege boundaries and never
   persists authentication credentials.
5. Interrupted RUNNING work becomes unknown/interrupted rather than being
   blindly retried.
6. Automation may check waiting conditions but does not own the plan or bypass
   authorization on resume.
7. Configuration, installation, repair and migration reuse the same resumable
   work mechanism instead of feature-specific wait loops.
8. Resumable work is persistent operational state; history records transitions
   but is not the workflow store.
