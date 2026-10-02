# Docker Module API v2 experiment

This module probes whether Igor can gain a new application-management domain
without adding Docker-specific behavior to Core.

## What the module owns

Docker-domain meaning and Docker CLI operations:

- runtime status;
- container inventory;
- approved container restart;
- future images, logs and Compose operations;
- installation intent.

## What Core owns

Igor Core remains authoritative for:

- module discovery/enablement;
- capability registration and availability;
- READ/CHANGE/DESTROY policy;
- user approval;
- privilege;
- execution history;
- cross-domain package/service composition.

The module therefore does not contain apt/pacman/systemctl installation logic.

## Current capabilities

- `docker.status` — READ, works even when Docker is absent.
- `docker.container.list` — READ, reports unavailable when the daemon cannot be queried.
- `docker.container.restart` — CHANGE, available only when the Docker CLI exists; execution still goes through Igor's capability approval path.
- `docker.install` — CHANGE, declared but intentionally unavailable until System exposes the required `system.package.install` and `system.service.enable` composition capabilities.

The unavailable install leaf is intentional: it makes a missing composition
contract visible instead of embedding distribution-specific package/service
commands in this module.

## Trying the experiment

New Module API v2 packages are disabled until explicitly adopted.

```bash
bash igor.sh --enable docker
bash igor.sh --modules
```

Restart Igor after enablement, then open the TUI Operator Surface with `:`.
The expected namespace is:

```text
docker
├── container
│   ├── list
│   └── restart
├── install
└── status
```

`docker.install` should be shown unavailable until its System composition
dependencies exist. This is part of the experiment, not a hidden fallback.

Disable it again with:

```bash
bash igor.sh --disable docker
```

After restart, Docker contributions must disappear without affecting System or
other modules. That is the detachability proof.
