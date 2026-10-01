# Host basics

Igor's system module describes the Linux host that runs Igor. Host observations
are reference data: they help explain current conditions and never authorize an
operation.

The `host.memory` observer reports the amount of memory currently available to
the Linux kernel, in bytes. It reads `/proc/meminfo` when invoked and does not
change host state.

The system module also retains the v1 health, diagnostic, context, notification
and recovery hooks while those consumers migrate to the Module API v2
contribution model.
