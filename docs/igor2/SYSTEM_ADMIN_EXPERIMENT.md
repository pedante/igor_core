# System Administration Operator Surface Experiment

Status: **experimental System 2.3.0 slice**. This is a product/architecture
experiment over the existing Module API v2, Capability System, Platform
abstraction and Operator Surface. It is intentionally smaller than a complete
host-management product.

## Why this extends `system`

Igor already has a first-class `system` module whose responsibility is
host-domain meaning. Creating a second `sysadmin` module would split one
ownership domain and create ambiguous providers for ordinary host operations.

The separation used by this experiment is:

```text
Core / Platform
  distro detection
  apt/pacman mechanics
  systemd query/argv mechanics
  approval + privilege + exact argv execution
          |
          v
System module
  host/package/service/log semantics
  capability declarations
  typed read results
          |
          v
Operator Surface
  :system.host.*
  :system.package.*
  :system.service.*
  :system.logs.*
```

The module therefore says **what an operation means**. Core decides **how a
Debian/Arch mechanism is represented and authorized**.

## Experimental namespace

The System package now declares:

| Namespace | Capability | Safety | Meaning |
|---|---|---:|---|
| Host | `system.host.summary` | READ | distro, kernel, architecture, uptime and package-manager summary |
| Packages | `system.package.updates.list` | READ | packages considered upgradable by current local package metadata |
| Packages | `system.package.cleanup.preview` | READ | orphan/autoremove candidates plus package-cache usage |
| Packages | `system.package.upgrade` | CHANGE + privilege | perform a reviewed distro upgrade sequence |
| Packages | `system.package.cache.clean` | CHANGE + privilege | clean only the distro package cache |
| Services | `system.service.list` | READ | list systemd service units and active/sub states |
| Services | `system.service.status` | READ | read one validated systemd unit state |
| Services | `system.service.restart` | CHANGE + privilege | restart one validated existing systemd unit |
| Logs | `system.logs.summary` | READ | recent/warning/error counts and latest timestamp; no raw log body is persisted |

The existing memory observer, health/configuration capabilities and knowledge
remain part of the same module.

In the namespace explorer this should naturally look like:

```text
:system.
  host
  logs
  memory
  package
  service

:system.package.
  cache.clean
  cleanup.preview
  updates.list
  upgrade

:system.service.
  list
  restart
  status
```

The explorer does not contain special System-menu code. These paths appear
because the contracts exist.

## Debian / Arch normalization

The user-facing capabilities are the same on both families. Core/Platform owns
the family-specific mechanism:

| Semantic operation | Debian family | Arch family |
|---|---|---|
| Discover pending updates | `apt-get -s upgrade` | `pacman -Qu` |
| Discover cleanup candidates | `apt-get -s autoremove` | `pacman -Qdtq` |
| Package cache | `/var/cache/apt/archives` | `/var/cache/pacman/pkg` |
| Upgrade | `apt-get update` then `apt-get upgrade -y` | `pacman -Syu --noconfirm` |
| Cache clean | `apt-get clean` | `pacman -Sc --noconfirm` |
| Services | systemd | systemd |
| Logs | journald | journald |

The preview capabilities intentionally describe **current local package
metadata**. They do not silently refresh repositories. The mutating
`system.package.upgrade` operation performs the appropriate refresh/full-sync
as part of the reviewed operation.

This avoids the unsafe Arch pattern of treating `pacman -Sy` as equivalent to
Debian's index-only refresh.

## Privilege boundary

Read handlers may call bounded unprivileged platform queries.

Mutating package/service handlers do **not** run `sudo` themselves. Their
declared handler is a marker only. Core recognizes the small reviewed capability
set, freezes the exact argv into the proposal digest and then uses the existing
approval and sudo-through-PTY path.

Examples:

```text
system.service.restart
  -> ["sudo","-n","--","systemctl","restart","cron.service"]

system.package.upgrade (Debian)
  -> ["sudo","-n","--","apt-get","update"]
  -> ["sudo","-n","--","apt-get","upgrade","-y"]

system.package.upgrade (Arch)
  -> ["sudo","-n","--","pacman","-Syu","--noconfirm"]
```

Re-resolution occurs immediately before execution. A changed provider, input,
platform-derived argv or proposal digest is rejected.

The package upgrade has an independent post-check:
`system.package.updates.empty`. A successful command sequence with remaining
updates is therefore an **unverified change**, not a false success.

Package-cache cleaning is deliberately different. A distro-neutral definition
of "clean enough" has not been established: Arch normally retains package files
that Debian's `apt-get clean` removes. The action is therefore marked
irreversible with no fake verifier. This is useful feedback from the experiment
and should be resolved before treating cache cleaning as a polished workflow.

## Cleanup is deliberately conservative

`system.package.cleanup.preview` discovers Debian autoremove candidates or Arch
orphans, but this experiment does **not** automatically remove them.

The discovered package set is machine state. A later removal capability should
freeze the exact candidate/package identities into an approved operation rather
than rerun discovery after approval.

Raw journal messages are also deliberately excluded from the generic capability
result. Capability v2 results become part of Operational History, and arbitrary
journal text may contain credentials or other sensitive material. The first
Logs contract therefore reports bounded metadata only. A useful raw-log
experience should be a dedicated read-only viewer/stream with explicit
scrubbing and retention semantics rather than an ordinary durable capability
result.

Likewise, this experiment does not yet add:

- automatic journal vacuuming;
- reboot/poweroff;
- user/group administration;
- firewall/network mutation;
- filesystem deletion;
- arbitrary shell commands;
- generic orphan removal;
- storage repair or filesystem resizing.

Those can become additional System contracts if the generated operator
experience proves useful, but each mutating family needs deterministic inputs,
safety classification, verification and recovery semantics.

## What this experiment is testing

This slice is primarily answering product questions:

1. Does a contract-generated `:system.*` tree feel better than handwritten
   administration menus?
2. Are semantic namespaces such as `package.upgrade`,
   `service.restart` and `logs.recent` understandable without memorizing
   commands?
3. Is the same contract useful to the TUI, AI and future CLI/UI?
4. Does keeping distro mechanics in Core/Platform make Debian and Arch support
   simple rather than duplicating module logic?
5. Where do current capability contracts need richer typed outputs, input forms
   or verification semantics?

No new persistent database, menu registry or execution authority is introduced
by this experiment.
