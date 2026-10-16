# Disposable Step 19 Nextcloud

Development fixture only: project `igor-step19-nc`, service `app`, web endpoint
<http://127.0.0.1:18080>. No production inputs, external volumes/networks, host
Docker socket mounts or database port publication. Compose owns the `db` and
`html` volumes and default bridge network under this project name. No restart
policy or boot enablement is requested. Use only disposable test data.

Pins: official [Nextcloud 32.0.15 Apache manifest](https://github.com/docker-library/repo-info/blob/master/repos/nextcloud/remote/32.0.15-apache.md)
and [MariaDB 11.4.13 manifest](https://github.com/docker-library/repo-info/blob/master/repos/mariadb/remote/11.4.13.md).
Both are immutable digest references, including amd64 for this host.
[Nextcloud 32 supports MariaDB 11.4](https://docs.nextcloud.com/server/32/admin_manual/installation/system_requirements.html).
Digest-only Nextcloud syntax also matches Igor's existing attachment provider.

## Actual host / installation prerequisite

Inspected 2026-10-16, outside the Codex filesystem sandbox: CachyOS (Arch),
x86-64, systemd; user `pooo`. Neither `docker`, `dockerd` nor Docker Compose is
installed. Docker service/socket are inactive; no local rootful or user Docker
socket was found. The user is not in the Docker group. Nothing was installed,
started, enabled or granted. The sandbox's PID 1 is not the host's PID 1.

Owner authorizes normal repository package installation and a consistent full
update, with interactive transaction review. Rootless Docker is preferred;
Docker-group membership, rootful socket permission changes, unreviewed AUR
packages and unrelated host changes are forbidden. No permanent rootful daemon
enablement or automatic sudo fallback in Igor is permitted.

The host already has `newuidmap`/`newgidmap`, subordinate UID/GID ranges
`pooo:100000:65536`, and enabled unprivileged user namespaces. Repository packages
provide Docker, Compose, rootlesskit, slirp4netns and fuse-overlayfs, but not
`docker-rootless-extras`. The [repository Docker file list](https://archlinux.org/packages/extra/x86_64/docker/files/)
omits the rootless launcher. The reviewed
[AUR recipe](https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=docker-rootless-extras)
installs a sysctl file and an install hook running `sysctl --system`; this is
not being applied under the current host-change limits. Rootless mode therefore
still needs an approved launcher installation route; kernel prerequisites alone
do not establish a working rootless daemon. See
[Docker's rootless prerequisites and installation](https://docs.docker.com/engine/security/rootless/).

**Current authentication blocker:** `sudo -n true` reports that a password is
required. Authenticate only in the Owner's host terminal; never send a password
through chat. The following command refreshes repository databases and presents
the complete transaction interactively. Stop at its confirmation prompt and
review before accepting. Stop for explicit Owner confirmation for significant
kernel, bootloader or graphics changes, removals or conflicts. Do not perform a
partial upgrade or use `--noconfirm`.

```bash
sudo pacman -Syu --needed docker docker-compose rootlesskit slirp4netns fuse-overlayfs
```

The read-only preview from cached 2026-10-12/13 databases listed only nine new
packages: libpathrs 0.2.6, runc 1.5.2, containerd 2.4.1, Docker 29.9.0, Compose
5.6.0, rootlesskit 3.2.0, libslirp 4.9.5, slirp4netns 1.3.6 and fuse-overlayfs
1.18 (about 69.5 MiB download). This is **not** a fresh transaction approval.

Do not start a daemon until its mode/security setup is settled. Rootless target
endpoint is `unix:///run/user/1000/docker.sock`; when configured, start only the
user service for this test session, without enablement or lingering. Verify:

```bash
export DOCKER_HOST=unix:///run/user/1000/docker.sock
docker version
docker compose version
docker info --format '{{json .SecurityOptions}}'
```

Require `rootless` in security options. Use the same explicit endpoint for Compose
and Igor's provider checks below; do not change the user's global Docker context.
A manually authorized rootful daemon may support setup-only tests, but sudo
execution does not prove Igor's OS-user execution contract. Such a fallback must
be reported separately, including its endpoint and unverified OS-user check.
No rootless or rootful daemon has been started, enabled or configured here.

## Private credentials and startup

Run in Bash from the repository root. This creates credentials without printing
them and refuses to overwrite existing ones. Reuse them on subsequent starts.
The existing repository `secrets/**` ignore rule covers the file.

```bash
python3 - <<'PY'
import os
from pathlib import Path
import secrets

path = Path('secrets/step19-nextcloud.env')
path.parent.mkdir(exist_ok=True)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    for key in ('STEP19_DB_PASSWORD', 'STEP19_DB_ROOT_PASSWORD', 'STEP19_ADMIN_PASSWORD'):
        stream.write(f'{key}={secrets.token_hex(32)}\n')
PY

compose=(docker compose --project-name igor-step19-nc
  --env-file "$PWD/secrets/step19-nextcloud.env"
  -f "$PWD/tests/fixtures/step19-nextcloud/compose.yaml")
"${compose[@]}" config --quiet
"${compose[@]}" ps -a
```

Before startup, confirm that this project name is unused (or is this exact
fixture), and localhost port 18080 is free. Do not adopt existing project
resources. Then:

```bash
"${compose[@]}" pull
"${compose[@]}" up -d --wait --wait-timeout 600
"${compose[@]}" ps
```

The image automatically installs Nextcloud using the private credentials. Both
services must become healthy. On failure, stop and inspect this project's state;
do not report installation success or automatically reset it. Credentials live
in container environment and config.php as required by the images; Docker
access can read them. Do not publish resolved Compose configuration, full Docker
inspect, config.php or unreviewed logs. Never upload real files to this fixture.

## Native verification and initial value

Use the same Bash `compose` array and OS user, without sudo:

```bash
"${compose[@]}" exec -T --user www-data app id -un
"${compose[@]}" exec -T --user www-data app php occ status --output=json
curl --fail --silent --show-error http://127.0.0.1:18080/status.php
"${compose[@]}" exec -T --user www-data app php occ config:system:set loglevel --type=integer --value=2
"${compose[@]}" exec -T --user www-data app php occ config:system:get loglevel
```

Require `www-data`, `installed: true`, `maintenance: false`,
`needsDbUpgrade: false`, and a fresh final OCC read of exactly `2`. The explicit
integer initialization is fixture setup only. Preserve the **2 → 3 → 2**
change-and-recovery test for the later Igor implementation.

Verify discovery and identification with Igor's **existing** read-only provider;
this does not attach/adopt the installation or grant Igor responsibility:

```bash
export STEP19_APP_ID
STEP19_APP_ID=$("${compose[@]}" ps -q app)
python3 - <<'PY'
import os
import sys

sys.path.insert(0, 'modules/nextcloud_docker/lib')
from attachment import DockerCliTransport, NextcloudAttachmentProvider

provider = NextcloudAttachmentProvider(DockerCliTransport())
candidate = provider.select(provider.discover(locator=os.environ['STEP19_APP_ID']))
assert candidate['project'] == 'igor-step19-nc' and candidate['service'] == 'app'
inspection = provider.inspect(candidate)
assert inspection['configuration_target']['availability'] == 'verified_regular_file'
assert provider.revalidate(inspection) == inspection
print('Identified igor-step19-nc/app:', candidate['container_id'])
PY
```

Record actual command outcomes before claiming these five live checks passed.

## Stop / project-only reset

From the repository root, reconstruct the same `compose` array if needed:

```bash
"${compose[@]}" stop
# Destructive: only after confirming these are this disposable project's resources.
"${compose[@]}" down --volumes
```

`down --volumes` removes this project's containers, network and the two declared
volumes (all test data/configuration). It retains credentials and cached images.
Restart with `up` above to reinstall, then repeat integer initialization and
native/provider verification: container identity will change. Do not use global
prune, volume wildcards, `--remove-orphans` or commands against another project.

## Preparation evidence / remaining work

Owner accepted Step 19 execution architecture B: a narrow typed Nextcloud
adapter through existing canonical dispatch, approval and configuration. That
workflow is not implemented by this fixture. Existing preflight records remain.

Current candidate: `igor2`, base `73a4c06`, this fixture plus the linked status
update; prior Step 19 documentation retained. Private credentials were generated
locally. Owner has authorized bounded package installation and testing; the
fresh interactive package transaction/authentication and rootless launcher
route remain unresolved. Docker mode/endpoint: **none active**. Nextcloud:
**not installed**. Image pull, Compose parsing and all five live checks remain
**unexecuted**. Read-only host checks confirmed kernel/UID prerequisites and the
cached package preview; credential mode/ignore and diff checks passed in the
preparation turn. No containers or volumes were created, no packages installed,
and no group/socket/service/sysctl changes made. No Step 19 governed validation allowance was spent or
borrowed from swap-health. No runtime regression/full gate is relevant to these
configuration/documentation files; governed checks await Step 19 authorization.
Commit/push remains unauthorized by the retained Step 19 instruction.
