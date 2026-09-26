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

## Configuration

**Defaults** (`config/variables/system.env`):
- `SYSTEM_TEMP_WARN` — CPU temperature warning threshold in °C (default: 75)
- `SYSTEM_TEMP_CRIT` — CPU temperature critical threshold in °C (default: 85)
- `SYSTEM_RAM_WARN_MB` — Available RAM warning threshold in MB (default: 80)

## Dependencies

- `systemctl` (required)
- `vcgencmd` (optional — Raspberry Pi hardware sensors)
- `lsblk`, `findmnt`, `udevadm` (optional — storage enumeration)
