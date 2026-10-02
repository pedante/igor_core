# Docker Module API v2 experiment

This module probes whether a detachable application domain can expose a
high-level installation operation without taking ownership of host package,
service, privilege, or approval mechanisms.

## What the module owns

Docker-domain meaning and Docker CLI operations:

- runtime status;
- container inventory;
- approved container restart;
- Docker installation intent and platform-specific package identity.

## What Core and System own

Core remains authoritative for capability registration, provider resolution,
policy, approval, privilege, frozen execution, verification and history.
System supplies generic host capabilities such as package installation and
service enable/start. Docker contains no apt, pacman, systemctl or sudo logic.

## Composite installation capability

`docker.install` remains a normal capability. Its provider is data-only
composition rather than a Bash handler.

For Debian it resolves:

```text
system.package.install(package=docker.io)
  -> system.service.enable(unit=docker.service)
  -> system.service.start(unit=docker.service)
  -> docker.status  [installed=true, daemon_accessible=true]
```

For Arch the package step uses `docker`. Core resolves the selected variant
into an immutable internal plan with provider/version/input information and a
digest. Each mutating child step re-enters the ordinary capability dispatcher,
so approval, PTY sudo authentication, exact reviewed argv and deterministic
verification remain unchanged. The final typed READ check verifies the
Docker-domain outcome.

The resolved plan is an execution artifact, not a separately registered
operation. AI, TUI and later automation continue to invoke only
`run_capability` / `docker.install`.

## Current capabilities

- `docker.status` — READ and intentionally available while Docker is absent.
- `docker.container.list` — READ and available only when the Docker CLI exists.
- `docker.container.restart` — CHANGE and available only when the Docker CLI exists.
- `docker.install` — CHANGE composite capability, available when its System
  package/service providers are available for the current platform.

A stopped composition records partial progress and does not silently roll back.
Recovery is a separate approved capability request.

## Trying the experiment

New Module API v2 packages are disabled until explicitly adopted.

```bash
bash igor.sh --enable docker
bash igor.sh --modules
```

Restart after enablement. The Operator Surface remains capability-shaped:

```text
docker
├── container
│   ├── list
│   └── restart
├── install
└── status
```

Disable it with:

```bash
bash igor.sh --disable docker
```

After restart, Docker contributions must disappear without affecting System or
other modules.
