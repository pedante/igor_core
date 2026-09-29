# Admin Communications — design proposal

Status: **design proposal; no implementation in this PR**.

This document defines a future communications architecture that unifies the
current outbound notification email path with the preserved concept of secure
inbound mail control.

The old core/mailcmd implementation is not present in the repository history.
This proposal therefore preserves the product intent without attempting a
source migration of missing code.

## Product goal

For a headless Linux system, email can be one of Igor's primary administrator
communication channels.

The same communications foundation should support:

- alerts and notifications;
- diagnose/health/incident reports;
- scheduled summaries and heartbeats;
- replies to administrator requests;
- authenticated inbound conversation;
- carefully authorized remote operation.

These are related uses of one communications system, not separate SMTP stacks.

## Core principle

**Email is a transport/interface over Igor, not a parallel command executor.**

Inbound requests ultimately use the same registered settings, capabilities,
policy, approval, privilege, plans, verification and history as local
interfaces.

A valid email signature authenticates an identity. It does not itself authorize
arbitrary operations.

## Conceptual architecture

    Administrator
        |
        | email
        v
    Communications
      |
      +-- transport: email
      |     +-- SMTP outbound
      |     +-- IMAP inbound
      |
      +-- notifications
      +-- reports
      +-- remote conversations
      +-- remote administration
        |
        v
    normal Igor services
      |
      +-- Context / AI
      +-- Configuration
      +-- Capabilities
      +-- Policy / approval
      +-- Verification
      +-- History

Future transports may reuse the same communications contracts without changing
Igor's authority model. This proposal does not require implementing any other
transport.

## One email transport configuration

The current split between notification SMTP configuration and the surviving
mailcmd SMTP/IMAP template should converge.

Conceptually the shared transport owns settings such as:

    communications.email.smtp.host
    communications.email.smtp.port
    communications.email.smtp.tls
    communications.email.smtp.user
    communications.email.smtp.password

    communications.email.imap.host
    communications.email.imap.port
    communications.email.imap.tls
    communications.email.imap.user
    communications.email.imap.password

Separate feature policy then references that transport:

    notifications.enabled
    notifications.recipient
    reports.recipient
    remote_conversation.enabled
    remote_admin.mode

Secrets are represented through Igor's secret mediation rather than copied into
multiple feature-specific files.

The future Configuration Model & Surfaces contract owns these settings and
their setup surface. Communications does not define a second configuration
system.

## Email configuration surface

The email setup should be invokable from the main menu, TUI or AI and return to
the originating interaction.

A future surface may present:

    Communications
      Email
        Account
        Outbound SMTP
        Incoming IMAP
        Administrator identity
        Notifications
        Reports
        Remote conversation
        Remote administration
        Test & verify

Useful bounded setup actions include:

- test SMTP;
- test IMAP;
- import/select administrator public key;
- create/select Igor key;
- send encrypted challenge;
- verify signed administrator response.

The surface returns structured completion/verification state.

## Outbound communications

Outbound email is broader than alerts.

Consumers may include:

### Notifications

Short event-driven messages such as:

- health critical;
- service down;
- backup failure;
- repair failure;
- destructive action notice.

Notification policy decides which events produce messages.

### Reports

Longer structured messages such as:

- diagnose reports;
- incident summaries;
- automation summaries;
- health summaries;
- backup reports.

Reports should reference authoritative structured results/history rather than
inventing success from command output.

### Conversation replies

Responses to authenticated administrator requests.

### Heartbeat / periodic summaries

Periodic administrator reassurance or summary should be implemented through the
normal automation/communications boundary rather than a special permanent cron
path once the relevant automation support exists.

## Inbound email

Inbound mail is treated as untrusted until it passes the configured identity and
message checks.

The initial security flow is conceptually:

    receive message
      -> parse bounded envelope
      -> decrypt if required
      -> verify cryptographic signature
      -> match configured administrator identity
      -> replay/deduplication check
      -> classify conversation/request
      -> normal Igor policy/capability path

Malformed, unauthenticated, replayed or unsupported messages fail closed.

## Administrator identity

The old mailcmd intent used operator email plus GPG identity. The future design
should retain a strong cryptographic administrator identity but improve setup
and inspection.

Prefer full fingerprints over short key IDs.

Identity configuration should expose non-secret status such as:

- operator address;
- configured public-key fingerprint;
- Igor encryption identity;
- verification state;
- last successful challenge.

Changing trusted administrator identity is itself an authority-policy change
and should require stronger/local authorization than ordinary remote settings
changes.

## Replay protection

A signed message may remain cryptographically valid indefinitely, so signature
verification is insufficient.

Communications must durably remember enough message identity to prevent replay,
for example provider/mailbox identity plus UIDVALIDITY/UID or Message-ID,
signature fingerprint and processed result identity.

The exact backend is deferred, but replay state is persistent communications
state, not chat memory.

## Conversation over email

Email should eventually support natural Igor conversation rather than only
subject-line verbs.

An email thread may map to a remote conversation/task identity using safe mail
thread metadata.

Example:

    Admin: What happened to the backup?
    Igor: The NAS was unreachable at 03:17...
    Admin: Is it reachable now?
    Igor: ...

Conversation context helps resolve references, but authoritative machine state
comes from Igor services/history.

A natural-language request never executes directly. It resolves to registered
settings/capabilities before any operational action.

## Authority modes

Remote email should have explicit, inspectable authority modes rather than one
global enabled flag.

A useful conceptual progression is:

### Notify

Outbound only. Inbound administration disabled.

### Conversation

Authenticated inbound conversation and READ operations. No unattended CHANGE.

### Operator

Authenticated administrator may request explicitly allowed CHANGE
capabilities under remote policy.

### Remote Admin

The strongest remote mode, still bounded by Igor's normal safety, privilege and
remote-authorization rules.

Exact names may change during implementation; the important contract is that
remote authority is explicit and graduated.

## Capability-scoped and time-scoped grants

Powerful remote administration should be grantable narrowly.

Examples:

- permit service restart but not package/network changes;
- permit a named Nextcloud repair capability;
- permit selected CHANGE capabilities for 24 hours;
- keep DESTROY unavailable remotely.

A grant records:

- trusted identity;
- capability/safety scope;
- start/expiry;
- provenance/authorizer;
- status.

Expiration must be deterministic and fail closed.

## Authentication is not authorization

A valid administrator signature proves who sent the request.

It does not mean:

- skip Igor approval/policy;
- bypass capability classification;
- bypass OS privilege authentication;
- permit raw shell;
- permit DESTROY;
- allow changing the remote-authority policy itself.

Remote administration reuses the canonical capability dispatcher.

The old concept of arbitrary MAILCMD_SHELL_MODE should not be preserved as a
privileged bypass.

## Remote CHANGE and DESTROY

Initial inbound implementation should favor READ/conversation.

Remote CHANGE requires an explicit remote-approval design under Step 22/Q011.

DESTROY should remain unavailable remotely until a deliberately stronger
contract exists. A GPG signature must not silently become equivalent to the
local exact-confirmation rule.

## Remote AI/settings changes

Some Igor settings are reasonable remote administration targets once exposed
through the Configuration Service, for example:

- AI provider/model;
- temperature;
- max tokens;
- verbosity;
- notification/report preferences.

They resolve as typed configuration operations, not shell edits.

More sensitive policy includes:

- enabling stronger remote authority;
- changing trusted administrator identity;
- changing remote capability grants;
- weakening safety policy;
- changing secret-access policy.

An authenticated remote user must not automatically gain the ability to
redefine the rules that authorize that same remote user.

## Provider-requested authorization

Email setup may require external authorization, device codes or provider
workflows. Communications does not block indefinitely waiting for them.

Such setup uses the Resumable Work contract:

    start authorization
      -> persist waiting condition
      -> return control
      -> verify external completion
      -> resume setup

## Domain events and notifications

Notification transports should eventually consume shared domain events or
history-derived incidents rather than maintaining a competing operational
truth.

A notification writer/model may summarize structured evidence, but it does not
choose safety severity or authorize repair.

The exact Step 13/15 integration belongs to implementation planning.

## Reports and attachments

The communications layer should support structured report delivery.

The initial implementation may send plain text. The architecture should not
assume every message is one line.

Report delivery may include:

- concise body;
- structured summary;
- bounded attachment/reference where appropriate.

Secret-containing artifacts must not be attached merely because they exist.

## Failure semantics

Outbound communication failure must not change the canonical result of the
operation being reported.

Examples:

- a successful backup remains successful if its email notification fails;
- notification failure becomes its own inspectable communications result/event;
- an inbound request is not considered processed if durable replay state cannot
  be committed safely.

Communications is evidence/delivery, not authority over the originating
operation.

## Resource profile

The design must remain suitable for low-resource hosts.

Initial email transport should not require a permanently running database or
large message broker.

Polling may use Igor Automation once periodic execution exists. External
callbacks may be added later without becoming required for basic operation.

## Legacy classification

The surviving mailcmd concept should be reclassified from "remove stale
feature" to:

**REDESIGN / PRESERVE PRODUCT INTENT**

What should not survive as permanent architecture:

- a separate SMTP credential stack;
- direct mail-specific module verbs as a second action registry;
- arbitrary shell mode;
- mail-specific authority rules;
- permanent cron ownership when shared automation can replace it.

What should survive:

- secure inbound administrator communication;
- cryptographic identity;
- outbound heartbeat/reports;
- remote administration as an explicit feature.

The missing core/mailcmd source is not a code migration target.

## Relationship to configuration

Communications depends on the future Configuration Service for:

- transport settings;
- secret references;
- identity settings;
- notification/report preferences;
- remote policy;
- setup surfaces.

The communications implementation should not introduce another environment-file
contract while that architecture is being established.

## Relationship to roadmap

This proposal fits existing roadmap ownership:

- Step 13/15: domain events/history become better sources for messages;
- Step 14: periodic mail polling/heartbeat can become automation consumers;
- Step 20: communications configuration and status surfaces in the TUI;
- Step 22: authenticated external interface and remote approval;
- Step 23: retire obsolete notify/mailcmd config paths after migration proof.

## Non-goals of this proposal

This PR does not:

- restore the missing core/mailcmd implementation;
- implement IMAP polling;
- implement GPG/OAuth;
- change current notification behavior;
- add remote CHANGE approval;
- allow arbitrary shell over email;
- choose an email library/provider;
- create a background mail daemon.

## Proposed design decisions for reconciliation

Decision numbers are intentionally not assigned in this PR to avoid conflicts
with parallel design proposals.

1. Notifications, reports, inbound email and remote conversation share one
   communications architecture and email transport configuration.
2. Email is an interface over normal Igor settings/capabilities/policy/history,
   never a parallel shell/action executor.
3. Cryptographic authentication proves identity but does not itself authorize
   an operation.
4. Remote authority is explicit, graduated and may be capability/time scoped.
5. Trusted identity and remote-authority policy cannot be casually redefined by
   the authority they grant.
6. Replay protection is durable communications state.
7. mailcmd product intent is preserved, but the missing old implementation and
   duplicate SMTP/action architecture are not.
8. Communications configuration is provided through the shared Configuration
   Model & Surfaces design.
9. External authorization during setup uses resumable work rather than blocking.
