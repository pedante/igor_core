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

The system module also retains the v1 health, diagnostic, context, notification
and recovery hooks while those consumers migrate to the Module API v2
contribution model.
