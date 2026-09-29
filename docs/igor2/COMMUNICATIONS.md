# Igor 2 admin communications

Status: **design proposal for architectural review; no implementation is implied by this document**.

This document preserves the useful intent of the absent historical core/mailcmd subsystem while replacing the old command-mail concept with a future shared communications architecture.

Email is one transport for administrator communication, not a parallel execution engine.

## Product goal

For a headless Igor installation, the administrator should be able to receive useful alerts and reports, reply naturally, continue a conversation with Igor, and—when explicitly authorized—request real operations remotely.

~~~text
Igor detects backup failure
        ↓
email report
        ↓
admin replies "Why did it fail?"
        ↓
authenticated remote conversation
        ↓
Igor investigates using normal evidence/capabilities
        ↓
email response
        ↓
admin replies "try the backup again"
        ↓
normal remote policy + capability path
        ↓
execution + verification
        ↓
email result
~~~

## Architectural invariants

1. Authentication proves who sent a request; it does not grant arbitrary authorization.
2. Email never introduces a second shell dispatcher.
3. Remote requests resolve to the same capabilities, configuration service, policy, privilege and verification paths used locally.
4. Notifications, reports, replies and remote conversation share transport and identity infrastructure where practical.
5. SMTP/IMAP credentials and administrator cryptographic identity are mediated secrets and never enter AI context by default.
6. A signed message cannot bypass READ/CHANGE/DESTROY classification, approval, privilege, preconditions or verification.
7. Remote authority is explicitly configured, inspectable, revocable and may be time- or capability-scoped.
8. A remote administrator cannot implicitly redefine the rules that grant that same remote authority.
9. Inbound processing is replay-resistant and durable enough to avoid executing the same authenticated request twice across restarts.
10. Email is the first transport, not a permanent hard-coded Core assumption.

## One communications architecture

~~~text
                     Admin
                       │
              ┌────────┴────────┐
              │                 │
           outbound          inbound
              │                 │
              ▼                 ▼
        Communications / Transport Layer
              │                 │
       ┌──────┴──────┐          │
       │             │          │
 notifications    reports    authenticated
                               messages
       │             │          │
       └─────────────┴──────────┘
                       │
                    Igor
                       │
       context / history / configuration
                       │
                  capabilities
                       │
          policy / approval / privilege
                       │
              execution / verification
~~~

## Email transport

Outbound responsibilities include SMTP connection and sender identity, alert delivery, report delivery, replies, heartbeat/summary messages and test messages.

Inbound responsibilities include IMAP or equivalent mailbox access, bounded polling or later callback integration, thread/message identity, cryptographic identity verification, replay protection and conversion into a remote-interface request.

The outbound SMTP implementation should not be duplicated between notifications and command mail.

## Unified configuration

Communications should consume the shared Configuration Model & Surfaces service rather than own arbitrary env parsing forever.

~~~text
communications.email.enabled

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
communications.email.imap.folder

communications.email.identity.operator_address
communications.email.identity.operator_fingerprint
communications.email.identity.igor_key

communications.notifications.recipient
communications.reports.recipient

communications.remote.mode
communications.remote.poll_interval
~~~

SMTP credentials should normally be configured once and reused by alerts, reports and replies.

## Configuration surface

~~~text
Communications
└── Email
    ├── Account
    ├── Outbound SMTP
    ├── Incoming IMAP
    ├── Administrator identity
    ├── Notifications
    ├── Reports
    ├── Remote conversation
    ├── Remote administration
    └── Test & verify
~~~

Bounded setup actions may test SMTP/IMAP, import or select an administrator public key, generate/import an Igor key, send an encrypted challenge and verify the response.

The surface should produce structured completion/verification state rather than merely writing files.

## Administrator identity

The historical design intended GPG-signed/encrypted email. A future design may keep GPG as the first supported cryptographic identity mechanism. Prefer full fingerprints rather than short key IDs.

~~~text
incoming message
    ↓
decrypt if required
    ↓
verify signature
    ↓
match configured administrator identity
    ↓
replay/expiry checks
    ↓
remote-interface policy
~~~

Cryptographic verification is an authentication fact. It has no direct meaning for capability tier, privilege or approval.

## Replay protection

Signed messages can remain valid indefinitely. Remote command processing therefore needs durable replay protection.

Useful retained metadata may include mailbox/account identity, UIDVALIDITY or equivalent generation, UID and/or Message-ID, signature fingerprint, received and processed timestamps, remote request/conversation ID and operation ID.

A replayed authenticated message must never silently execute the same state-changing request again.

## Remote modes

One global MAILCMD_ENABLED switch is too coarse.

### Notify

Outbound alerts and reports only. Inbound remote requests disabled.

### Conversation

Authenticated administrator may converse with Igor and request information. Initial implementation should naturally align with READ-only remote execution.

### Operator

Authenticated administrator may request explicitly permitted CHANGE capabilities under configured remote policy.

### Remote Admin

Strongest remote mode, still bounded by capability policy, privilege, recovery and verification. It is not unrestricted shell access.

Names are provisional; explicit graduated authority is the requirement.

## Remote grants

Remote authorization should support expiry, allowed safety tiers, capability allowlists and explicit denial.

~~~text
Allow this administrator by signed email for 24 hours:
  READ: normal remote-readable capabilities
  CHANGE:
    nextcloud.service.restart
    nextcloud.repair.*
  DESTROY: none
~~~

Expiration or revocation returns the interface to a lower mode without disabling outbound communication.

## Privilege

Remote authorization does not itself provide OS authentication.

A future remote-CHANGE design must define privileged capability behavior without storing a reusable administrator password. Until that contract is accepted, remote privileged CHANGE remains unavailable even when email identity is authenticated.

Igor approval and OS authentication remain separate boundaries.

## Remote configuration and AI settings

Remote conversation may eventually change ordinary typed settings through the canonical Configuration Service.

Reasonable examples may include reasoner provider/model, temperature, max tokens, verbose mode and notification preferences.

More sensitive changes need stronger treatment: enabling stronger remote authority, allowing remote DESTROY, replacing the trusted administrator key, modifying policy that authorizes the current identity, or disabling safety/secret controls.

Distinguish **using granted authority** from **redefining the authority grant itself**.

## Natural conversation

Inbound mail should not be limited to command verbs in subject lines.

~~~text
Message-ID / References / authenticated sender
        ↓
remote conversation ID
        ↓
bounded conversational state + Igor history/context
~~~

Natural requests may use the normal AI reasoning path, but operations still resolve to registered capabilities and policy. Conversation state is not operational history and cannot substitute for authoritative machine state.

## Reports

Notifications should evolve beyond one-line alerts where structured evidence exists.

Useful messages may include incident summary, affected objects, observed evidence, action performed, execution result, verification result, whether admin action is required, and correlation/history reference.

~~~text
Subject: [IGOR] Nextcloud incident resolved

Nextcloud was unavailable from 03:14-03:19.

Cause:
Redis service stopped.

Action:
Restarted Redis.

Verification:
- Redis healthy
- Nextcloud HTTP healthy
- database reachable

No administrator action is required.
Reply to this thread for more detail.
~~~

The email is a projection of structured evidence/history, not the canonical record itself.

## Domain events

Notification transports should eventually consume shared domain events/history rather than requiring each execution path to call SMTP directly.

Transport delivery is a projection of normal Igor signals, not an authority source. Delivery policy decides which events deserve email.

## Polling and Automation

Inbound mailbox polling is naturally periodic. Once the relevant capability/security semantics exist, the Automation Engine can schedule it rather than introducing another permanent cron-only architecture.

~~~text
periodic automation
    ↓
communications.email.poll
    ↓
read/validate new messages
    ↓
produce authenticated remote requests
~~~

Polling and any state-changing request derived from a message remain separate operations with separate authority.

## Transport neutrality

Core should eventually understand a remote/admin communications interface rather than email-specific business logic everywhere.

Any later transport must still map into:

~~~text
authenticated request
    ↓
shared remote-interface policy
    ↓
normal Igor services/capabilities
~~~

Email remains the first concrete case and may be the only bundled transport for a long time.

## Migration of current notification code

Current core/notify is working outbound functionality and should be preserved while the shared Communications boundary is introduced.

Migration should identify current SMTP configuration/event preferences, define canonical settings, import or alias current values, preserve alert delivery during cutover, move notification delivery behind the shared transport, verify equivalent behavior, and retire duplicate direct config only after consumers migrate.

## Historical mailcmd classification

The absent historical core/mailcmd implementation should **not** be reintroduced as a parallel verb or shell dispatcher.

Preserve the product requirements: inbound authenticated email, encrypted/signed identity where supported, replies, heartbeat, module/domain operations and powerful remote administration when explicitly enabled.

Replace the old architecture with:

~~~text
email interface -> shared conversation/config/capability/policy/history
~~~

The legacy mailcmd hook and command-verb model become migration artifacts once an authenticated shared interface exists.

## Failure behavior

- Transport failure must not corrupt canonical operational state.
- Outbound delivery failure should be visible in history/inspection.
- Inbound authentication failure never becomes an AI request.
- Invalid or replayed messages do not execute capabilities.
- AI/provider failure cannot bypass remote policy.
- SMTP success does not prove the administrator read the message.
- Capability execution success does not imply verification success; remote reports preserve both.

## Non-goals

This design does not immediately provide unrestricted remote shell access, remote privileged CHANGE, remote DESTROY, a second AI runtime, a permanent polling daemon, arbitrary commands embedded in email subjects, transport-specific authorization semantics, or trust based only on sender address.

## Roadmap fit

- Configuration Model & Surfaces: shared email and remote-policy configuration.
- Step 15: operational history provides durable evidence for reports and follow-up.
- Step 20: TUI exposes Communications configuration and status.
- Step 22: authenticated mail/external interfaces consume shared capabilities, policy and history.
- Step 23: old notification/mailcmd config and hook compatibility are removed only after migration.

Remote CHANGE/approval remains part of Q011/Step 22.

## Proof requirements for implementation

1. **Contract proof** — untrusted, replayed and malformed messages fail before operational dispatch; message content cannot spoof remote policy.
2. **Regression proof** — existing outbound notifications remain functional during migration.
3. **Vertical-slice proof** — one authenticated inbound READ request traverses the normal capability/context path and returns a verified reply.
4. **Inspection proof** — transport status, identity status, remote mode/grants and recent results are visible without secrets.
5. **Migration/recovery proof** — notification settings migrate idempotently and replay state survives restart.

## Questions left for later decisions

- first cryptographic identity mechanism and key lifecycle;
- mailbox polling and durable cursor storage;
- exact remote-mode names;
- remote privilege model;
- remotely mutable settings at each authority level;
- conversation storage boundary;
- attachment/report size limits;
- future API/callback relation to the same remote policy.
