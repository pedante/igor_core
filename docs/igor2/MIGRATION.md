# Igor 2 migration policy

Igor 2 is an incremental migration, not a flag-day rewrite.

## Roadmap outcomes are not rebuild instructions

Recent `master` work already implements substantial parts of the interaction runtime, privilege flow, module activation boundary, platform helpers, AI trust boundary and capability catalog.

Before implementing a roadmap step:

1. inspect the current implementation;
2. classify the target as implemented, partial, acceptable-different, or missing;
3. preserve correct foundations;
4. create a replacement only when the current design cannot satisfy the target.

Do not build parallel systems merely because the roadmap uses a newer name.

## Core migration rule

When a new subsystem becomes authoritative, remove or explicitly disable the superseded authoritative path.

Do not leave two permanent implementations of the same responsibility.

## Persistent migration rule

A persistent layout/contract change is not complete until an existing-style
installation can move through it safely.

Document and test:

- source version/location;
- target version/location;
- validation before cutover;
- recovery point/backup behavior where needed;
- idempotency and safe re-entry after interruption;
- verification after migration;
- the cutover rule that prevents permanent dual-source ambiguity.

Configuration, secrets, state, machine memory, learned data, investigations and
operational history must not be silently co-located merely because the current
tree does so.

## Compatibility lifecycle

A legacy path remains only when all are true:

1. working behavior still needs it;
2. its replacement/target is named;
3. its removal condition is recorded in `LEGACY.md`;
4. new work does not expand the legacy contract without a migration reason.

## Cleanup timing

### Before migration work

Identify contradictions, duplicates, stale docs and application-specific leakage. Classify them without speculative rewrites.

### During each roadmap step

When a replacement is proven, retire the superseded path if compatibility no longer needs it.

Examples:

- active module registry authoritative -> no inactive module contribution path;
- System Model/observers authoritative -> remove equivalent independent probes where migrated;
- capability API authoritative -> remove duplicate interface-specific operations;
- context engine authoritative -> remove equivalent ad-hoc context/prompt paths.

### Final consolidation

Step 23 removes compatibility shims and obsolete contracts intentionally retained during migration.

## Vertical-slice migration rule

Do not migrate every domain at once.

During Wave C:

- extend the existing loader rather than create a second one;
- use a small part of `system` as the mixed v1/v2 reference;
- keep `nextcloud_docker` on v1 to prove compatibility.

After Wave C is green, use bounded real slices rather than migrate every domain.

The current Nextcloud direction first proves brownfield recognition/attachment
and one reversible adopted setting across ownership/configuration, module
contribution, capability, approval/privilege, execution, deterministic
verification and history. The reusable recognition contract should then be
proved with a second materially different domain before its shape becomes a
general Core assumption.

Greenfield provisioning comes after the brownfield/application proof and uses
the same capabilities, Configuration Service, Deployment Service, verification
and History boundaries. Generalize only after each slice proves the contracts
compose correctly.

## Ownership Foundation gate

Broad Module v2 migration waits for one authoritative ownership model for
canonical paths, configuration, secrets, persistent state, machine memory,
knowledge, learning, investigations, history and runtime.

Early Wave C contract/loader work may proceed where independent, but public
Module v2 contracts must not encode the current mixed storage assumptions.

## Preserve proven implementation, change ownership where needed

Working code does not need rewriting solely because its architectural ownership changes.

Examples:

- current TUI/event stream can remain while backend contracts become more general;
- current module activation can be formalized into Module Runtime v2;
- current distro/package helpers can expand into the platform layer;
- current AI audit/journal data can seed operational history.

The old documented `core/mailcmd/` implementation is **not present in the current tree**. If mail control returns, design it as a shared-engine interface rather than assuming code exists to migrate.

## Regression properties

Important migration properties include:

- disabled modules contribute no runtime behavior or AI reference data;
- active module ownership is enforced at advertisement and execution time;
- core does not assume a specific application deployment;
- safety tiers and approvals remain deterministic;
- privilege remains separate from autonomy;
- state-changing operations are verifiable where practical;
- recovery semantics are declared per capability/plan rather than assumed
  universally reversible;
- secret values remain outside normal AI context and secret access follows the
  mediated/auditable contract;
- each new authoritative subsystem has a minimal inspection surface;
- the current TUI remains usable throughout migration;
- module/context reference data cannot authorize actions;
- Debian and Arch behavior is tested wherever support is claimed.

## Scope discipline for coding agents

For implementation work:

1. read Igor 2 status/architecture;
2. inspect the affected current subsystem and direct dependencies;
3. expand scope only when evidence requires it;
4. implement through the requested roadmap boundary;
5. add/update tests;
6. remove superseded paths that are safe to retire;
7. update `STATUS.md` and `LEGACY.md`;
8. satisfy the relevant completion proof categories in `EXECUTION.md`.

Do not repeatedly perform whole-repository audits except at planned milestones.

## Decision gates

Proceed through straightforward implementation details.

Stop and surface a decision when:

- an open architectural question blocks a durable public contract;
- repository reality contradicts an accepted invariant;
- a change risks user data/resources or compatibility;
- plausible designs have materially different long-term API consequences.

## Documentation policy

- Root/current subsystem docs describe current behavior.
- `docs/igor2/` describes target architecture and migration.
- Superseded planning/handoff documents should be removed rather than kept as searchable active documentation; Git history is the archive.
- When a subsystem completes migration, update its current-state documentation so target/current docs do not remain contradictory.
