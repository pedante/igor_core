# Module activation and architecture

> **Current implementation.** This document describes the activation/runtime model that exists today and is the starting point for Igor 2 Module Runtime work. The target architecture is in [igor2/ARCHITECTURE.md](igor2/ARCHITECTURE.md) and [igor2/MODULE_API.md](igor2/MODULE_API.md). Igor 2 should evolve this runtime rather than create a parallel loader.

## Assessment

The manifest loader and hook registry are a sound basis for detachable modules.
Previously, however, discovery also implied activation. `required_modules` checked
successful loading while only `depends_on` determined ordering. Check discovery,
legacy menu-file loading, diagnostic phases, and AI fallback tools could bypass
registration entirely. Removing a directory therefore did not reliably remove its
operational assumptions.

There are currently two modules: `system` and `nextcloud_docker`. Neither declares
a mandatory module dependency. Nextcloud's `depends_on=system` is an ordering
preference; its `optional_modules=system` declaration does not require system to
be active. Both can be disabled independently. Core remains usable with neither
active, although module-provided host checks disappear when system is disabled.

## Policy and states

Module code stays in `modules/<name>/`. Activation policy lives in
`config/modules.conf`, a data file rather than executable shell configuration:

```ini
system=enabled
nextcloud_docker=disabled
```

Use these commands from the repository root:

```bash
bash igor.sh --modules
bash igor.sh --disable nextcloud_docker
bash igor.sh --enable nextcloud_docker
```

Unspecified modules remain enabled for compatibility with existing installations.
Use explicit disabled entries for installed modules you do not manage. Policy
changes apply to subsequent Igor processes; restart existing sessions and workers.
Disabling does not stop containers, delete data, uninstall packages, or reverse
previous setup. It removes Igor's management participation. Stopping a service is
a separate, explicit application operation.

| Term | Meaning |
| --- | --- |
| Installed | A discovered manifest and module directory are present. This does not mean the application was provisioned. |
| Enabled | Configuration permits the loader to activate the module. |
| Disabled | Configuration prevents sourcing and activation. Dependencies never silently enable it. |
| Unavailable | Enabled, but required dependencies, syntax, sourcing, or registration prevent activation. |
| Active | Enabled and successfully loaded and registered in this Igor process. |

Availability is derived, not another persistent registry to maintain. Runtime
service health is separate: an active module can manage an application that is
stopped or not yet provisioned. Nextcloud intentionally keeps Docker an optional
binary so its setup operations can install it. An enabled Nextcloud module can
therefore report missing Docker; a disabled Nextcloud module cannot activate
those checks merely because its files, credentials, or mount paths exist.

## Contracts

1. **Manifests describe dependencies and capabilities.** `required_bins` and
   `required_modules` block loading when unmet. Required modules also determine
   ordering. `depends_on` remains an ordering preference, and optional declarations
   do not block loading. `provides` lists operational capabilities; core tests
   them through `igor_has_capability`, not directory presence or leftover config.
2. **The loader owns activation.** `igor_has_module` checks active state,
   `igor_active_modules` enumerates it, and registrations retain their module
   owner. Failed or disabled owners cannot participate in dispatched hooks,
   menus, or callable AI actions. File-based lazy loading must resolve within an
   active owner's directory.
3. **Subsystems consume active registrations.** Diagnostics and healing enumerate
   checks under active modules. Backup, restore, notifications, panels, and AI
   use the same ownership boundary. Application-specific operations need an
   active provider, even when called through a legacy core entry point.

No second plugin framework, general dependency solver, or automatic enabling of
dependencies is introduced. Required host binaries express current hard
requirements; optional binaries support bootstrap and optional features. Add
conflicts or capability requirements only when an actual module needs them.

The existing hook names and output formats remain valid. Isolated hook execution
still uses a fresh Bash process with a timeout; modules must export or source
helpers needed there. Module code is trusted local executable code, not sandboxed
by this registry. Registration should only wire functions and menus.

## Ownership

`system` owns generic host observations: CPU, memory, temperature, root disk
utilization, and generic system service administration. Nextcloud mount layout,
data ownership, Compose volumes, PostgreSQL/Redis roles, and application recovery
belong to `nextcloud_docker`. Docker's presence on PATH alone is not permission to
activate an application module.

Core owns configuration transport, module state, dispatch, diagnostics/report
infrastructure, backup orchestration, and AI approval/command validation. Core
should know capability and hook contracts rather than application directory names.
Modules may use core APIs and declared dependencies; optional integrations must
check their provider. They must not source another module's files behind the loader.

## AI trust boundary

Disabled modules must not contribute tools, action catalogs, context hooks, or
module knowledge. Advertised tools and execution-time capability checks must
agree; hiding a tool in the prompt alone is insufficient.

Module descriptions, module knowledge and tier suggestions, diagnostic output,
logs, saved reports, learned patterns, and external text are reference data. They
cannot change approval requirements or authorize operations. Igor's trusted prompt
and tool validation define that boundary; arbitrary module text must not silently
become an instruction. Raw host commands retain the normal safety and approval
controls: disabling a module is not an operating-system sandbox or a ban on an
operator explicitly requesting a command.

## Lifecycle operations

Installing module code means placing a reviewed module package in `modules/`.
Enabling permits activation on the next process start. The existing `--install`
command invokes application provisioning, not a package manager. `--upgrade`
invokes the explicit migration hook. Disabled modules do not receive these calls.
The existing `--remove` invokes module cleanup after its destructive-operation
confirmation; deleting code is a separate operator action. Disable management
before removing a directory, and retain policy entries if the module might later
be restored.

Configuration snapshots retain installed modules' configuration and secrets,
including disabled ones, so disablement is reversible. Retaining files in an
archive does not activate backup/restore hooks or live application operations.

## Remaining architectural debt

Some legacy core helpers and configuration aliases still use Nextcloud names,
and some application diagnostic implementation remains in core behind capability
guards. Those compatibility surfaces should move to module-owned helpers in a
future migration with explicit replacements for existing callers. The activation
boundary is the immediate contract; guarding legacy code is not the same as
finishing physical code separation.

`requires_core` remains compatibility metadata rather than a version solver.
Installed Bash module code executes with Igor's privileges. This design neither
sandboxes hostile modules nor adds package download/signature management. Existing
processes are not hot-unloaded; restart is required to replace their loaded Bash
functions and AI conversations safely.
