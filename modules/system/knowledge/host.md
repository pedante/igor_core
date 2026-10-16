# Host basics

Igor's system module describes the Linux host that runs Igor. Host observations
are reference data: they help explain current conditions and never authorize an
operation.

The `host.memory` observer reports the amount of memory currently available to
the Linux kernel, in bytes. It reads `/proc/meminfo` when invoked and does not
change host state.

The v2 memory health check warns below its consumed
`system.memory.warning_threshold_mib` value (default 150 MiB, range 81–4096),
and treats less than 80 MiB as critical. Core owns desired configuration;
the System package declares its meaning and applies it to an Igor process.
An independent readback reports what that health consumer uses. Desired values
alone do not prove consumption or runtime state. `memory-warning MIB` uses the
normal deterministic approval and History path; this document grants no
authority. Recovery explicitly proposes and applies the prior/default value
through that same path. No automatic rollback is implied.

`host.runtime` supplies observed uptime, load and swap counters from Core's
bounded Linux procfs normalization. `host.swap.health` interprets those facts:
configured swap below 60% use is OK, at least 60% is WARN, and at least 85% is
FAIL. Comparisons use integer byte counters, not the rounded percentage shown
in the runtime inventory. No configured swap is SKIP, not a health failure.
Missing, unavailable, stale or malformed evidence cannot establish healthy swap;
the structured result retains the used facts and their availability/timestamps.

Swap occupancy alone does not prove active paging, current memory pressure or
the need for repair. This check does not change swap, swappiness or host settings,
and its findings do not authorize an operation. Diagnose and Healing reuse the
structured result rather than issuing another swap-health probe.

`system.host.runtime.status` capability v3/output schema 2 shares the same System
interpretation for its fresh READ, with `observed_at` and
`observation_scope=current_read`. That operation is recorded in History but does
not refresh the process-local System Model or an older stored health result.
Inspect the model/check timestamps separately; retained v2 operations still
describe their original counters-only output.

The system module also retains the v1 health, diagnostic, context, notification
and recovery hooks while those consumers migrate to the Module API v2
contribution model.
