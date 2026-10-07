# System S8 — Broader System Catalogue Discovery Proposal

Status: **S8 is complete for the Igor 2 System release scope on
`feature/sys-broader-catalogue`. S8.1 host runtime telemetry is implemented
and green; the additional catalogue phases below are explicitly deferred as
post-release growth, consistent with the System scope rule requiring
representative high-quality domains rather than exhaustive Linux coverage. No
new S8 mutation authority is accepted by this document.**

Base: completed S7 stack at `feature/sys-network-wifi`

## Goal

Broaden the existing `:sys` surface into a strong everyday host catalogue
without turning System into a collection of shell-command wrappers.

S8 covers the roadmap areas that remain thin after S1–S7:

- host runtime telemetry and structured health;
- hardware/platform inspection;
- boot and time inspection;
- security posture;
- richer package/log/health inspection;
- only those additional mutations that later earn a narrow reviewed contract.

The existing System package, Module API v2 registry, System Model, Observation
Framework, Capability runtime, D070 selectors and current approval/privilege
path remain authoritative.

## Discovery evidence

### 1. S8 is extension work, not a new module or registry

D020 already places reusable Linux mechanisms in Core/Platform and host-domain
meaning in `system`. S1–S7 established one generated operator namespace,
one semantic-candidate boundary and one capability runtime.

**Recommendation:** keep one `system` owner and one canonical capability
catalogue. Do not add a hardware/security submodule or another inventory
database merely to organize S8.

### 2. The repository already has partial catalogue coverage

The current typed System surface already includes:

- `system.host.summary` and authoritative memory observation/health;
- package update/cleanup inspection and reviewed package mutations;
- service list/status plus reviewed service mutations;
- `system.logs.summary`;
- storage, account/path and network/Wi-Fi surfaces from S4–S7.

S8 should extend those contracts rather than duplicate them.

### 3. Legacy System health/context still contains direct probes

The v1-compatible System hooks still directly read or derive:

- CPU/thermal-zone temperature;
- Raspberry Pi throttle/undervoltage state;
- root filesystem usage;
- swap usage;
- load averages;
- machine model, OS, kernel, architecture and uptime;
- recent I/O-error text.

Host Intelligence already classifies temperature/load/swap and duplicate
CPU/storage probes as **ADAPT to observers/checks** after the memory slice.

**Recommendation:** S8 should close this duplicate-probe debt before adding a
large set of new state-changing commands.

### 4. Current facts and health meaning remain separate

A current load average, swap counter, clock state or security-provider state is
observation. Whether that state is healthy is System-owned interpretation.

**Recommendation:** Core owns bounded normalization; System observers publish
typed facts; System checks interpret only established thresholds. A READ
capability may present normalized current state without turning every value
into a durable System Model object.

Do not infer health from command exit alone, missing providers or stale facts.

### 5. Do not invent durable hardware-component identity yet

S8 does not currently need to select or mutate individual CPUs, PCI devices,
USB devices, thermal zones or firmware records. Serial numbers, board UUIDs,
disk serials and similar hardware identifiers also create unnecessary
fingerprinting exposure.

**Recommendation:** initial hardware/runtime work attaches bounded facts to
`host:local` or returns current READ results. Add component object kinds only
when a real selector, relationship or mutation requires stable identity.

### 6. Thermal state needs provider semantics

The existing fallback assumes `thermal_zone0` is CPU temperature. That is
not a portable semantic guarantee. `vcgencmd` is Raspberry-Pi-specific.

**Recommendation:** do not label an arbitrary Linux thermal zone as CPU truth.
A later hardware slice may use reviewed provider mappings and explicit
source/provenance. Missing provider data is `unknown`/unavailable, not 0°C
and not healthy.

### 7. Security posture should be optional-provider READ first

AppArmor, SELinux, nftables/firewalld/ufw and other controls vary by distro and
installation. Absence of one tool does not imply an insecure host and must not
deactivate System.

**Recommendation:** canonical System security concepts may have optional
provider adapters. Report provider state precisely; do not dump rules, change
policy or synthesize a universal security score in the first slice.

### 8. Richer logs need a data-exposure boundary

The current `system.logs.summary` deliberately returns bounded metadata and
does not persist raw journal messages into Operational History. Raw logs may
contain tokens, paths, usernames, request data or application secrets.

**Recommendation:** S8 may enrich counts, priorities, units and bounded
metadata first. Raw-message retrieval must remain a separate reviewed question;
it must not become an accidental AI/context/History secret channel.

### 9. Reboot, power, clock and security mutation are not implied

The legacy `sysreboot` affordance and the existence of tools such as
`timedatectl`, `bootctl` or firewall managers do not establish a canonical
Capability contract.

**Recommendation:** S8 begins READ-first. Reboot/shutdown, timezone/NTP,
boot-target, firewall and MAC/security-policy changes require explicit later
decisions, exact Core adapters, recovery semantics and deterministic
verification. Remote-session loss risk must remain visible.

## Recommended phases

| Phase | Outcome |
|---|---|
| S8.0 | Discovery, Q019–Q021, proof gate |
| S8.1 | Host runtime telemetry READ substrate: normalized uptime/load/swap; typed host observation/status; no new mutation |
| S8.2 | Hardware/platform READ catalogue: bounded non-identifying hardware summary and reviewed optional thermal provider semantics |
| S8.3 | Boot & time READ catalogue: canonical status with optional provider-specific evidence |
| S8.4 | Security posture READ catalogue: optional AppArmor/SELinux/firewall-provider state without policy mutation |
| S8.5 | Richer packages/logs/health: structured metadata, health cutover from duplicate v1 probes, no unreviewed raw-log channel |
| S8.6 | Selectively verified mutations only where an accepted decision and real operator need justify them |
| S8.7 | Debian/Arch/provider fixtures, detachability proof, docs and stacked affected gate |

S8 remains intentionally iterative. Igor 2 does not need an exhaustive clone
of Linux administration commands.

## Proposed S8.1 boundary

The first implementation slice should be **host runtime telemetry READ only**.

Core should provide one bounded Linux runtime query for data that is common on
the supported Debian/Arch families:

- uptime seconds;
- 1/5/15-minute load averages;
- swap total/free/used bytes and use percentage.

The first slice should not parse human-oriented `uptime` or `free` output
when stable procfs values exist.

System may publish these as fresh `host:local` observed facts and expose a
small canonical READ capability such as `system.host.runtime.status`.
Exact property names and schema must be fixed during S8.1 implementation after
checking existing Host Intelligence conventions.

S8.1 explicitly excludes thermal semantics, raw logs and all mutation. It is
designed to be portable, deterministic and independent of optional desktop or
network managers.

## Provider and failure rules

- contribution-local requirements only;
- an optional provider failure disables only its leaf/contribution;
- bounded byte/row/text limits and timeouts;
- malformed or ambiguous input fails closed;
- missing state is explicit `unknown`/unavailable;
- no AI-dependent sensing or validation;
- no frontend-specific host authority;
- no secret-bearing values in candidate data, facts, History or provider
  diagnostics;
- Debian/Arch support is claimed only where fixtures prove equivalent semantics.

## Proof requirements

### Contract proof

- no second module, registry, inventory or execution path;
- typed bounded schemas;
- initial S8.1 facts remain on canonical `host:local`;
- optional-provider absence is localized;
- no serial/UUID/raw-log/credential leakage.

### Regression proof

- preserve S1–S7 System surfaces;
- preserve module detachability;
- preserve System Model/Observation semantics;
- preserve capability approval/privilege/History;
- preserve Debian/Arch support claims only where exercised.

### Vertical proof

For S8.1:

1. normalize procfs runtime fixtures;
2. publish or present canonical bounded host runtime data;
3. inspect it through the generated `:sys` surface;
4. prove malformed/oversized procfs data fails closed;
5. prove no sudo, mutation, AI or optional provider is required;
6. prove System disabled/inactive state contributes no active behavior.

### Migration/recovery proof

S8.1 introduces no persistent backend, no object-ID migration and no
state-changing capability. Legacy direct probes remain compatibility only until
their structured replacement has equivalent proof; do not double-count one
health signal after cutover.

## Open decisions

The authoritative open questions are recorded in
`docs/igor2/DECISIONS.md`.

- Q019 — should initial S8 hardware/runtime state remain `host:local` facts and
  bounded current reads until a real need proves component identities?
  Recommendation: **yes**.
- Q020 — should richer log work keep raw journal messages outside typed
  capability/History/AI output by default until a dedicated sensitive-log
  contract exists? Recommendation: **yes**.
- Q021 — should reboot/power, time, boot and security-policy mutation remain
  deferred until each has an explicit reviewed capability/recovery decision?
  Recommendation: **yes**.

None of Q019–Q021 blocks the proposed read-only S8.1 telemetry slice if the
Project Owner accepts the recommendations.


## Igor 2 release-scope closure

The Project Owner directed the System sequence forward to S9/S10 after the
green S8.1 gate. Under the release standard in `SYS_OPERATOR_PROPOSAL.md`,
S8 does not need to clone every Linux administration domain before Igor 2 can
ship.

The completed S8 release slice is:

- bounded Core procfs normalization for uptime, load and swap;
- typed `host.runtime` observation on canonical `host:local`;
- `system.host.runtime.status` as a privilege-free READ capability;
- deterministic malformed/oversized-input failure;
- focused and affected stacked validation.

S8.2–S8.7 remain useful future catalogue work, not hidden completion claims.
Hardware component identity, thermal provider semantics, boot/time catalogues,
security-provider posture, raw-log exposure and additional S8 mutations remain
deferred under Q019–Q021 and their existing authority boundaries.

This closure introduces no persistence migration and no new execution authority.
