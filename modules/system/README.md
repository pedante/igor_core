# System Administration module experiment

This module is the first v2 experiment for treating operating system administration as a normal Igor module.

## Design goal

The module owns system administration concepts:

- host information
- package update visibility
- cleanup previews
- service inspection
- log summaries
- host observations

It does not own distribution-specific commands. Platform mechanisms are provided through Core adapters.

Current target families:

- Debian
- Arch

## Boundary

The module declares meaning and contracts:

```
system.package.updates.list
system.package.install
system.package.upgrade
system.service.list
system.service.status
system.service.enable
system.service.start
system.service.restart
system.logs.summary
system.host.summary
```

The implementation intentionally separates:

- READ operations: inspection and observation
- CHANGE operations: updates, cleanup and service changes
- privilege handling: Core approval/privilege paths

A module handler must not bypass Igor's capability dispatcher.

`system.service.list` now uses capability v3/output schema 2 for frozen, bounded
loaded system-manager service pages. Optional limit defaults to 50 (maximum 128);
continuation is valid only in its original live backend session for less than
30 seconds. Refresh is explicit. See the
[Increment B contract and evidence](../../docs/igor2/COLLECTION_INCREMENT_B.md).
Other administration contracts retain their existing versions.

`system.host.runtime.status` now uses capability v3/output schema 2. It retains
uptime/load/swap counters and adds System swap status, finding and explanation,
plus an explicit current-READ timestamp/scope. `host.swap.health` consumes the
existing runtime facts through the shared health runner. WARN begins at 60%,
FAIL at 85%, based on byte counters; no configured swap is SKIP and unknown
evidence is not healthy. Neither path changes host configuration. A current
capability READ does not refresh older model facts/checks. Retained capability
v2 History remains counters-only. See [the increment record](docs/SYS_BROADER_CATALOGUE_PROPOSAL.md#approved-swap-health-increment--2026-10-15).


## Platform abstraction

Examples:

```
system.package.updates.list
        |
        +-- Debian -> apt
        |
        +-- Arch   -> pacman
```

The module should grow by adding platform providers, not distribution checks throughout the module.

## Current experiment status

Implemented:

- Module API v2 contract structure
- host observer and health integration
- system summary capability
- package update discovery
- cleanup preview
- service inspection
- journal summary
- reviewed package install/upgrade/cache-clean adapters
- reviewed service enable/start/restart adapters
- deterministic verification for package installation and service state

Still experimental:

- generic orphan cleanup execution
- richer health facts
- broader platform providers

The purpose is to validate that system administration can be built using the same contracts, capabilities and operator surface as application modules.
