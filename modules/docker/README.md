# Docker Module API v2 experiment

This module probes whether Igor can gain a new application-management domain
without adding Docker-specific privilege or distribution behavior to Core.

## What the module owns

Docker-domain meaning and Docker CLI operations:

- runtime status;
- container inventory;
- approved container restart;
- future images, logs and Compose operations;
- the semantic installation plan.

## What Core and platform providers own

Igor Core remains authoritative for:

- module discovery/enablement;
- capability and plan registration/availability;
- READ/CHANGE/DESTROY policy;
- user approval and privilege;
- execution history and verification;
- registered plan resolution/execution.

The System/platform layer owns reusable host mechanics such as package install
and service enable/start. The Docker module contains no apt, pacman, systemctl,
sudo, docker-group membership, or other privilege implementation.

## Current surface

- `docker.status` — READ; intentionally available even when Docker is absent so
  Igor can report that fact.
- `docker.container.list` — READ; available only when the Docker CLI exists.
- `docker.container.restart` — CHANGE; available only when the Docker CLI
  exists and still goes through Igor's normal capability dispatcher.
- `docker.install` — a data-only registered plan:
  `system.package.install(pkg_docker)` →
  `system.service.enable(docker.service)` →
  `system.service.start(docker.service)`.

The logical package name `pkg_docker` is resolved by the platform layer
(`docker.io` on Debian, `docker` on Arch). Every changing plan step re-enters
Core's canonical capability dispatcher, so the module cannot acquire approval,
sudo, or verification authority from the plan itself.

Installation deliberately does **not** add the user to the `docker` group.
Daemon socket access remains a separately observed security state.

## Trying the experiment

New Module API v2 packages are disabled until explicitly adopted.

```bash
bash igor.sh --enable docker
bash igor.sh --modules
```

Restart Igor after enablement, then open the TUI Operator Surface with `:`.
On a host without Docker the useful shape is:

```text
docker
├── install
└── status
```

After Docker is installed, container administration leaves can become available
from the same contracts without adding a custom menu.

Disable it again with:

```bash
bash igor.sh --disable docker
```

After restart, Docker contributions must disappear without uninstalling Docker,
deleting containers, or erasing machine/history state. That is the detachability
proof.
