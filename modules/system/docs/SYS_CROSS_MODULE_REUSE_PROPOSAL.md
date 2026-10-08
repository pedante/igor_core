# System S9 — Cross-Module Reuse Discovery Proposal

Status: **S9 is complete for the Igor 2 System release scope on
`feature/sys-cross-module-reuse`. The representative S9.1 production cutover
is implemented and the stacked affected gate is green. S8 is complete for its
release scope; remaining S8/S9 expansion is explicitly deferred rather than
hidden behind compatibility fallbacks.**

## Goal

Make real domain modules consume Igor's canonical System capabilities and
System Model objects instead of reimplementing Linux host mechanics.

S9 is not a generic refactor mandate. Domain-specific Docker/Nextcloud logic
stays with those modules. The target is duplicated host work such as package
installation, service activation/status, mount/filesystem inspection,
permissions and other Linux mechanisms for which a reviewed System contract
already exists.

## Discovery findings

### 1. Reuse already has one production precedent

The Module API v2 `docker.install` capability is already a data-only
composition of canonical host capabilities:

- `system.package.install`
- `system.service.enable`
- `system.service.start`

Its final check is `docker.status`. This proves that cross-module reuse does
not require another execution engine, integration registry or AI-only planner.

S9 should extend this pattern to real remaining consumers.

### 2. Nextcloud Docker still duplicates reviewed host mechanics

The legacy `nextcloud_docker` package still contains host-level operations
that now overlap System/Core authority. Examples include:

- starting/enabling `docker.service` directly with `systemctl` when the
  daemon is unavailable;
- direct mount/`df` inspection in storage health and menus;
- direct service-state reads for `cloudflared`;
- package/service setup for optional host cron;
- direct permission changes, including recursive ownership repair.

These are not all safe to migrate in one step.

### 3. The first cutover should be Docker runtime readiness

The Nextcloud installation/start-stack workflows are explicitly user-triggered
and already mutate the host. When Docker is missing or inaccessible they
currently invoke legacy host helpers or raw `sudo systemctl enable/start
docker`.

Igor already owns a better canonical operation: `docker.install`, whose
implementation composes reviewed System package/service capabilities and
preserves ordinary approval, privilege, exact child providers, verification
and Operational History.

**S9.1 recommendation:** replace the Nextcloud raw Docker-daemon recovery path
with one canonical `docker.install` request through the existing capability
dispatcher. After it completes, Nextcloud independently rechecks `docker
info` before continuing its domain workflow.

No raw `systemctl` or `pkg_install_docker_post` fallback should remain in
the migrated Nextcloud path. If the canonical provider is disabled,
unavailable, declined or fails verification, Nextcloud stops and reports the
dependency instead of silently reacquiring host authority.

### 4. Background health reads are a different boundary

Legacy check scripts are executed in isolated subprocesses. They do not share
the process-local System Model and should not call user-operation capability
execution merely to obtain health data; doing so would also create misleading
Operational History for background checks.

Therefore S9 must **not** mechanically replace every raw read with
`run_capability`.

A later read cutover should use one of these existing authoritative shapes:

- a v2 check supplied with canonical facts;
- a reusable System Model projection available in the same runtime;
- a deliberately reviewed integration-rule/snapshot handoff.

Do not create a second hidden read dispatcher merely for legacy checks.

### 5. Recursive permission repair is outside the current System authority

S6 permits reviewed non-recursive single-path owner/group/mode changes on
bounded roots. Nextcloud's legacy storage repair may use recursive `chown -R`.

S9 must not pretend those operations are equivalent. Recursive repair remains
legacy/domain behavior until a separate capability contract justifies its
scope, affected-object accounting, recovery and verification.

### 6. External reachability remains application context

The Nextcloud network check uses ping/DNS/HTTP/tunnel evidence. S7 explicitly
does not model public internet reachability as host network truth.

S9 should not route those application/tunnel checks through
`system.network.*` merely to reduce shell commands. Only truly equivalent
host mechanics should be reused.

## Accepted initial boundary — D076

For S9's first reuse slice:

1. a user-triggered module workflow may call another active module's canonical
   capability only through Igor's existing capability dispatcher;
2. the consumer does not copy the provider's package/service/sudo mechanics;
3. CHANGE/DESTROY reuse preserves ordinary approval, privilege, exact-provider
   resolution, verification and History;
4. a missing/disabled/unavailable canonical provider fails closed for the
   migrated operation—no raw-shell fallback silently restores duplicate
   authority;
5. domain-specific postconditions remain the consumer's responsibility;
6. background checks do not invoke mutating/user-operation capabilities as a
   read shortcut;
7. legacy code outside the explicitly migrated seam remains compatibility
   debt, not evidence that System contracts are optional.

## S9 phases

| Phase | Outcome |
|---|---|
| S9.0 | Inventory duplicate host mechanics and accept D076 reuse boundary |
| S9.1 | Nextcloud install/start-stack Docker prerequisite uses canonical `docker.install`; raw Docker service enable/start fallback removed |
| S9.2 | Add one safe user-triggered READ reuse where canonical identity/input can be resolved without inventing a second dispatcher |
| S9.3 | Audit remaining duplicates into migrate/defer/keep categories; prove disabled-provider/detach behavior |
| S9.4 | Docs, affected stacked validation and closure evidence |

S9 is representative, not exhaustive. S10 remains the shared operator/TUI and
release-polish gate.

## S9.1 proof requirements

### Contract

- Nextcloud calls only canonical `docker.install`;
- no direct `sudo systemctl enable/start docker` remains in the migrated
  install/start-stack prerequisite path;
- no call to legacy `pkg_install_docker_post` remains there;
- the canonical request identifies provider `docker` and capability version
  1 explicitly;
- no new approval or privilege API is introduced.

### Vertical slice

1. Docker daemon is inaccessible;
2. Nextcloud asks Igor to execute `docker.install`;
3. the existing dispatcher handles its canonical composition;
4. System package/service child capabilities retain their own authority;
5. Docker's typed final check completes;
6. Nextcloud independently rechecks `docker info`;
7. only then does the Nextcloud stack workflow continue.

### Failure proof

- declined/failed/unavailable `docker.install` stops the Nextcloud workflow;
- a dispatcher/provider absence does not fall back to raw systemctl;
- a nominal capability success followed by inaccessible `docker info` still
  fails the Nextcloud prerequisite;
- already-accessible Docker performs no capability invocation.

### Regression / detachability

- Docker and System remain independently disable-able;
- disabling either provider makes the migrated prerequisite unavailable rather
  than giving Nextcloud new host authority;
- existing S1–S8 capability/safety behavior is unchanged;
- Nextcloud domain-specific Docker Compose operations remain module-owned.

## Deferred candidates

- Cloudflared service-state reuse: defer until a background-safe canonical fact
  or integration-rule projection exists.
- Nextcloud mount/usage health: defer until the check can consume System facts
  in the authoritative runtime rather than an isolated v1 subprocess.
- Recursive ownership repair: defer; current System permissions capability is
  intentionally non-recursive.
- Host cron setup: candidate for a later composition once package/service
  naming and verification are represented without Nextcloud-specific shell.


## Igor 2 release-scope closure

S9 closes on the representative production integration promised by the System
release rule rather than forcing every legacy Nextcloud host probe through a
new abstraction.

Implemented and proved:

- Nextcloud install/start-stack Docker readiness now requests canonical
  `docker.install@docker`;
- `docker.install` remains a data-only composition of
  `system.package.install`, `system.service.enable` and
  `system.service.start`, followed by typed `docker.status`;
- already-accessible Docker invokes no cross-module capability;
- provider/approval failure does not regain authority through raw
  `systemctl` or `pkg_install_docker_post`;
- canonical success is independently followed by `docker info` before the
  Nextcloud workflow continues;
- focused S9 proof and the affected stacked validation are green.

The proposed S9.2 read migration is intentionally deferred. Discovery showed
that classic-menu legacy check/status paths do not share the AI-session
dispatcher or process-local System Model uniformly. Adding a second direct
capability executor merely to remove a raw read would violate D076 and Step 20's
single-backend rule. S10 is the correct place to consolidate interface entry
paths first.

The remaining legacy duplicates are classified as follows:

- Cloudflared/background service reads: defer until a shared fact/integration
  projection exists;
- Nextcloud mount/usage background health: defer until the check runs through
  authoritative v2 facts rather than an isolated v1 subprocess;
- recursive ownership repair: defer because S6 is deliberately non-recursive;
- public reachability/DNS/HTTP application checks: keep domain-owned; they are
  not equivalent to S7 host-network truth;
- optional host cron setup: future composition candidate, not required for the
  representative release proof.

No persistent migration is introduced by S9. Recovery is provider failure:
the consumer stops instead of silently reacquiring host authority.
