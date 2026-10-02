# Module: system

Architecture-agnostic Linux system management. Works on Raspberry Pi and
standard x86/arm64 servers. Uses `/proc`, `/sys`, and optional tools
(`vcgencmd`, `lsblk`).

## Entry points

| Hook | Function | Description |
|------|----------|-------------|
| `health` | `system__health()` | CPU temp, RAM, undervoltage check |
| `diagnose` | `system__diagnose()` | Phase 2 system checks in diagnose subsystem |
| `ai_context` | `system__ai_context()` | Injects host metrics into AI context |
| `ai_tools` | `system__ai_tools()` | legacy reference/tool text; current executable tools come from the core catalog/capability path |
| `mailcmd` | `system__mailcmd_verbs()` | reserved v1 verbs; no mail dispatcher exists in the current tree |
| `notify` | `system__notify_sources()` | Notification sources for alert subsystem |
| `recovery` | `system__recovery_hooks()` | Recovery hooks for the journal framework |

## Files

| File | Purpose |
|------|---------|
| `module.sh` | Hook registration + health/diagnose implementations |
| `module.conf` | Module metadata and dependencies |
| `checks/storage.sh` | Storage health check plugin (used by healing subsystem) |
| `contracts/host.json` | Owned v2 knowledge, observation, check, schema and capability declarations |
| `lib/memory_warning.py` | Shared memory health consumer and independent runtime readback |

## Configuration

The v2 memory check declares `system.memory.warning_threshold_mib`, an integer
from 81 to 4096 MiB, default 150 MiB. The critical boundary remains 80 MiB.
Core stores desired values for `module:system`; the package stores no mutable
configuration. `SYSTEM_RAM_WARN_MB` is an unused legacy declaration and is
neither imported nor consulted by this consumer.

In an active System session, `memory-warning 220` proposes the desired change,
then applies the committed revision to that Igor process and performs an
independent READ of the actual health consumer. Core owns both CHANGE approvals,
privilege checks, typed-output validation and Operational History. Guide retains
its READ confirmation. This changes Igor's warning classification, not host
memory or operating-system configuration.

Desired commit, application and readback have separate correlated History
episodes. An application failure retains desired intent and the prior consumer;
verification failure is `unverified_change`. Inspect the configuration and
History before recovery. Explicitly run the same command with the prior value or
`150` for the package default; there is no automatic rollback. A new active
process consumes already-approved desired resolution during startup, including
a desired commit whose previous explicit application failed or was declined.
Startup consumption does not claim verification.

`--configuration inspect system.memory.warning_threshold_mib` and structured
module inspection distinguish desired/resolved input from process consumption.
The independent readback source is `system.host.memory.health.consumer`, scoped
to an Igor process identity. Configuration does not create System Model facts.
Disabled packages retain data-only schema/desired inspection but contribute no
application or readback. Removing the package/schema remains outside this proof.

**Legacy declarations** (`config/variables/system.env`; not v2 authority):
- `SYSTEM_TEMP_WARN` — CPU temperature warning threshold in °C (default: 75)
- `SYSTEM_TEMP_CRIT` — CPU temperature critical threshold in °C (default: 85)
- `SYSTEM_RAM_WARN_MB` — unused legacy RAM declaration (80); not the v2 warning boundary

## Dependencies

- `systemctl` (required)
- `vcgencmd` (optional — Raspberry Pi hardware sensors)
- `lsblk`, `findmnt`, `udevadm` (optional — storage enumeration)
