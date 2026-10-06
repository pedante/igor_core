# System S7 — Network & Wi-Fi Discovery Proposal

Status: **D073 accepted; S7.1 Core network read substrate implemented on the feature branch pending the stacked validation gate. Q017–Q018 remain open.**

Branch: feature/sys-network-wifi

## Goal

Make :sys.network a first-class everyday administration surface without turning
System into a NetworkManager wrapper or importing application-specific network
checks.

S7 should deterministically answer which interfaces and addresses exist, which
routes are active, which interface owns the default route, which resolver
endpoints are configured, whether an interface is wireless, and—when a reviewed
provider exists—which Wi-Fi networks/profiles are available.

The AI may interpret this evidence, but discovery, completion and verification
must not depend on the AI.

## Discovery findings

### 1. Core currently has no generic network substrate

The current tree has no reusable Core network library comparable to package,
service, storage or S6 access mechanics. The legacy nextcloud_docker network
check mixes internet probes, DNS, Cloudflare, Docker/nginx routing and
application health. It is migration evidence, not a generic System primitive.

The Module API boundary already assigns reusable network mechanics to
Core/Platform and host-domain meaning to System.

**Recommendation:** add one normalized Core network read boundary. Do not move
the legacy Nextcloud check into System.

### 2. The System Model already chose interface identity

HOST_INTELLIGENCE.md already names interface:eth0 as the intended locally scoped
identity and explicitly allows rename/move to create a new identity.

**Recommendation:** implement that existing vocabulary:

~~~text
object_kind: interface
object_id:   interface:<encoded-interface-name>
~~~

Do not invent network_interface:* or a parallel inventory.

### 3. Do not make every route a durable object yet

Routes are dynamic and include policy-table, source and metric dimensions. S7
does not need a durable routing graph merely to provide strong administration.

**Recommendation:** make interfaces durable observed objects first. Publish
small interface/host facts such as default-route ownership, while
system.network.routes.list returns a bounded normalized current route table.
A later routing-mutation design can add route identities if evidence requires it.

### 4. Generic reads must not depend on NetworkManager

Debian and Arch hosts may use NetworkManager, systemd-networkd, iwd, static
configuration or another manager. Interface/address/route truth exists below
those managers.

**Recommendation:** normalize Linux kernel state through iproute2 JSON (ip -j
link/address/route), with bounded strict parsing. Individual System network
contributions may require ip; the System package itself must remain active when
it is absent.

DNS should initially report resolver endpoints from /etc/resolv.conf plus
source/symlink context. A local stub such as 127.0.0.53 must not be presented as
the upstream recursive resolver.

### 5. Wi-Fi is provider behavior

Scanning networks, activating profiles and creating credentials are
manager-specific.

**Recommendation:** NetworkManager/nmcli is the first optional Wi-Fi provider.
The generic network read model stays independent of it. Later iwd/iwctl or
other providers may satisfy the same System domain without changing canonical
System IDs or creating another plugin runtime.

### 6. Wi-Fi scans are ephemeral candidate data

SSID is not unique, BSSID can disappear, and scan results age quickly.

**Recommendation:** scans feed D070 as bounded ephemeral wifi_network
candidates. Display SSID, signal, security, BSSID and interface; browsing does
not persist facts or grant authority.

Saved NetworkManager profiles remain external configuration. They may be shown
as ephemeral wifi_profile candidates using the provider's UUID without Igor
claiming ownership of the profile.

### 7. Existing saved profiles can be activated without reading secrets

A saved NetworkManager profile may already contain its credential. Igor can
activate it without retrieving that credential.

**Recommendation:** the first Wi-Fi mutation, if accepted, is only:

~~~text
system.network.wifi.connect_known
~~~

with:

~~~text
interface  -> selector resource_kind=interface
profile    -> selector resource_kind=wifi_profile
~~~

Core preflight confirms the interface is currently wireless, the profile still
exists and is Wi-Fi, and the pair is eligible. Core freezes exact provider argv,
the execution fence re-prepares the proposal, and verification confirms the
selected profile UUID is active on the selected interface.

Internet reachability is not success proof: a valid profile may intentionally
have no default route or public connectivity.

### 8. New password-bearing Wi-Fi is blocked by the current secret boundary

Capability schemas understand secret_ref, but the compiler currently marks
generic secret-bearing capability consumers secret_consumer_unavailable.

Passing a Wi-Fi password as an ordinary string, argv captured in History,
candidate, module output or prompt transcript would violate Igor's ownership
and secret contracts.

**Recommendation:** S7 does not create or edit password-bearing Wi-Fi profiles
until the Ownership Foundation supplies an explicitly reviewed secret consumer.
Open-network profile creation should also wait because it creates persistent
external configuration; it is not merely a secret exception.

### 9. Avoid connectivity-destructive mutations in the first slice

Interface down, route deletion, DNS rewrite, disconnect and profile deletion
can sever the session administering the host. General remote approval remains
Q011.

**Recommendation:** the only initial network mutation is positive activation of
an existing saved Wi-Fi profile. Interface up/down, disconnect, route/DNS
changes, profile create/edit/delete and radio power changes stay deferred.

## S7.1 implementation

Core now provides `core/lib/network_query.py` and the thin
`core/lib/network.sh` bridge.

The normalized read boundary exposes:

~~~text
network_interfaces_query
network_routes_query
network_dns_query
network_snapshot_query
~~~

Interface discovery uses one `ip -j -d address show` snapshot so link and
address state are coherent within one Platform read. Route discovery reads
bounded IPv4 and IPv6 tables separately and normalizes family, destination,
gateway, device, preferred source, metric, table, protocol, scope and route
type. Interface rows derive only current default-route ownership from those
normalized route rows.

Wireless detection in S7.1 is only a bounded sysfs property check
(`/sys/class/net/<name>/wireless` or `phy80211`). It does not scan Wi-Fi,
select a manager or activate a connection.

Resolver discovery reads at most 64 KiB from the resolved target of
`/etc/resolv.conf`, retains the visible symlink target/resolved path, parses
configured nameserver/search directives, recognizes loopback resolver stubs,
and deliberately makes no upstream-resolver claim.

The iproute2 subprocess boundary has a bounded timeout and 1 MiB stdout limit;
interface/address/route counts are bounded and malformed data fails closed.
No S7.1 function contains a privileged or mutating command.

## Proposed S7 read model

### Interface collection

Proposed observer: network.interfaces

Proposed facts per interface:<name>:

~~~text
interface.name
interface.ifindex
interface.operstate
interface.admin_up
interface.carrier
interface.mtu
interface.mac
interface.kind
interface.wireless
interface.ipv4_addresses
interface.ipv6_addresses
interface.default_route_v4
interface.default_route_v6
~~~

Address collections are normalized bounded strings in the first System Model
shape because current facts are scalar.

### Read capabilities

~~~text
system.network.summary
system.network.interfaces.list
system.network.interface.status
system.network.routes.list
system.network.dns.status
system.network.wifi.status
system.network.wifi.scan
system.network.wifi.profiles.list
~~~

Wi-Fi entries are available only when their reviewed provider exists. Generic
interface/route/DNS inspection never depends on NetworkManager.

### Candidate kinds

~~~text
interface       durable identity from fresh System Model or bounded Core read
wifi_network    ephemeral provider scan result
wifi_profile    ephemeral external-provider profile reference
~~~

Only interface is a System Model object in the initial recommendation.

## Authority flow

~~~text
System observer/capability declaration
        |
        v
Core normalized network read
        |
        +--> iproute2 JSON: link/address/route
        +--> resolver configuration
        |
        v
System Model interface facts + READ capability results
        |
        v
D070 candidate resolver
        |
        +--> interface candidates
        +--> NetworkManager Wi-Fi scan/profile candidates
        |
        v
explicit operator selection
        |
        v
canonical capability prepare
        |
        |  connect_known only
        v
Core NetworkManager preflight
        -> exact frozen argv
        -> Igor approval/authentication
        -> execution-fence re-prepare
        -> active-profile/interface verification
        -> Operational History
~~~

No frontend, module prose or AI call gains network authority.

## Proposed phases

| Phase | Outcome | Rough focused effort |
|---|---|---:|
| S7.0 | Discovery, Q016–Q018, proof gate | Q016 resolved by D073; Q017–Q018 open |
| S7.1 | **Implemented:** Core bounded link/address/route/DNS reads, shell bridge and focused tests | complete pending stacked validation |
| S7.2 | interface System Model collection observer + READ capabilities/selectors | 1–2 days |
| S7.3 | NetworkManager Wi-Fi read provider + scan/profile candidates | 1–2 days |
| S7.4 | Reviewed connect_known CHANGE adapter + verification | 1–2 days |
| S7.5 | Docs, Debian/Arch/provider fixtures, affected PR gate | 1 day |
| later | New/open Wi-Fi profiles after secret/config ownership consumer | separate decision |

The focused S7 remains in the original 5–10 day estimate. Password-bearing
profile creation is not part of that estimate because the missing secret
consumer is an ownership-foundation dependency, not a network-domain task.

## Proof requirements

Contract proof:
- interface collection objects are bounded and strictly validated;
- malformed network/provider rows fail closed;
- Wi-Fi candidates are bounded, non-secret reference data;
- no PSK/password/802.1X secret enters outputs, candidates or History.

Regression proof:
- preserve Module API v2, System Model and D070 semantics;
- preserve S2 services, S4/S5 storage and S6 access;
- preserve approval/privilege/History;
- System remains detachable and active when optional network providers are absent.

Vertical proof:
1. discover interfaces/addresses from fixtures;
2. publish interface:* facts;
3. select an interface through the generic chooser;
4. inspect routes/DNS read-only;
5. with a NetworkManager fixture, select a saved profile;
6. prepare connect_known;
7. prove exact frozen argv;
8. verify selected profile active on selected interface;
9. prove stale/malformed profile state fails before execution.

Failure proof:
- missing ip disables only network contributions;
- missing nmcli disables only NetworkManager Wi-Fi contributions;
- provider output drift fails closed;
- failed activation is never success;
- verification mismatch fails even after a zero process exit;
- no fallback creates a profile or asks for a password.

## Questions requiring Project Owner decision

The authoritative questions live in docs/igor2/DECISIONS.md:

- Q016 — **resolved by D073:** interface:<name> is the first durable S7 network
  object; routes and DNS remain bounded reads/derived evidence.
- Q017 — accept NetworkManager/nmcli as the first optional Wi-Fi provider and
  connect_known as the only initial Wi-Fi mutation.
- Q018 — defer new/open/password-bearing profile creation until an explicit
  configuration/secret-consumer authority exists.

Recommendation: **yes to all three**. This gives Igor a strong portable network
view now without weakening the ownership foundation to make Wi-Fi setup appear
convenient.
