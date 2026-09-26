# Igor 2 migration policy

Igor 2 is an incremental migration, not a flag-day rewrite.

## Core migration rule

When a new subsystem becomes authoritative, remove or explicitly disable the old authoritative path.

Do not leave two permanent implementations of the same responsibility.

## Compatibility lifecycle

A legacy path may remain only when all are true:

1. it is still needed for working behavior;
2. its replacement is named;
3. its removal condition/target is recorded in `LEGACY.md`;
4. new code does not expand the legacy contract without a migration reason.

## Cleanup timing

Cleanup happens in three forms.

### Before migration work

Identify contradictions, duplicates and application-specific leakage. Classify them without rewriting everything.

### During each roadmap step

As soon as a replacement is proven by tests, retire the superseded execution/state path.

Examples:

- Module Runtime v2 authoritative -> remove filesystem presence as module activation.
- Observation framework authoritative -> remove equivalent independent probing by AI/diagnose/healing.
- Capability v2 authoritative -> remove duplicate operation implementations from interfaces.
- Context engine authoritative -> remove equivalent ad-hoc prompt injection paths.

### Final consolidation

Step 23 removes compatibility shims and obsolete documentation/contracts that survived migration intentionally.

## Preserve working implementation, change ownership

Working scripts do not need to be rewritten merely because their current architectural placement is wrong.

Example: mail IMAP/GPG/SMTP code may remain as implementation while its ownership changes from an independent core operating subsystem to an interface/transport adapter using shared Igor capabilities and policy.

## Regression fixtures

Preserve representative working behavior while changing architecture.

The existing Nextcloud/Docker deployment is a primary migration fixture.

Important regression properties include:

- disabling a module makes all of its runtime contributions disappear;
- active module knowledge cannot leak from disabled modules;
- core diagnostics do not assume Nextcloud/Docker;
- safety tiers and approvals remain deterministic;
- changes remain verifiable;
- current TUI remains usable through migrations;
- Debian and Arch platform behavior is tested where claimed.

## Scope discipline for coding agents

For an implementation task:

1. read Igor 2 status/architecture;
2. inspect the affected subsystem and direct dependencies;
3. expand scope only when repository evidence requires it;
4. implement through the current roadmap boundary;
5. add/update tests;
6. remove superseded paths that have become safe to remove;
7. update `STATUS.md` and `LEGACY.md`.

Do not repeatedly perform a whole-repository audit unless the roadmap calls for a milestone audit.

## Decision gates

Implementation may proceed through straightforward details without asking for approval.

Stop and surface a decision when:

- a listed open architectural decision blocks a durable public contract;
- repository reality contradicts the accepted architecture;
- a change risks user data/resources or migration compatibility;
- two plausible designs have materially different long-term API consequences.

## Documentation migration

Until Igor 2 components are authoritative:

- existing README/docs describe current behavior;
- `docs/igor2/` describes target architecture and migration.

When a subsystem completes migration, update its primary current-state documentation rather than leaving contradictory descriptions indefinitely.
