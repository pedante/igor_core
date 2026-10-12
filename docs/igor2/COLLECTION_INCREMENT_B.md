# Increment B: System collections and temporary navigation

Status: implemented and stabilized on local `igor2`, based on accepted Increment A
`5a0121202f250612428db3f0f71bcf4753dab62a`; Owner accepted at B backend scope on
2026-10-12. Acceptance covers structured System collections, bounded producer
transport, frozen snapshots, pagination, resource accounting, canonical backend
integration and recovery. The Owner authorized one descriptive checkpoint commit.
No push, merge, TUI presentation change or live service operation.
The [RFC](COLLECTION_OPERATOR_RFC.md) remains the single grammar/architecture
authority. The complete Collection Operator milestone remains open.

## System contract and canonical CLI backend

`system.service.list` migrates in place to capability 3/output schema 2. Module
API remains 2 and contribution envelope remains 1. Inputs are optional `limit`
(integer 1–128, handler default 50) and `cursor` (string 1–256, runtime requires
printable ASCII and a valid signed binding). Other capabilities retain v1/v2.
Old exact list-version pins fail before handler execution. The existing closed
[Increment A schema](COLLECTION_INCREMENT_A.md) supplies `resource_kind`,
`inventory`, `rows`, `page`, `freshness`, ordered Unit/Active/Substate columns
and the optional READ `system.service.status` inspection declaration. No row
inspection executes in B.

The controlled real System fixture produces 51 loaded inactive services. Its
first canonical result has `execution_status=succeeded`, `output_status=valid`,
`verification_status=not_applicable`, `outcome=success`; the domain result names
`service` / `loaded_system_services`, returns `unit0000.service` through
`unit0049.service`, and reports returned_count 50, total_count 51, has_more true.
The next page returns `unit0050.service`, returned_count 1, has_more false. It
retains the same revision and freshness even after the source changes. Replayed
cursors yield identical domain pages in independently identified operations.
Explicit refresh (a new list request without cursor) obtains the changed source.

These requests use existing `igor_capability_prepare`, `igor_capability_execute`
and canonical result/History APIs in one long-lived Bash backend. Public opaque
continuations are navigation references; private signing/accounting data is not
projected. A new CLI/backend process is a new session and cannot continue an old
process's cursor. Existing one-shot commands do not create durable cursor
authority. Future frontends consume this same capability and structured result
path; no second dispatcher or execution protocol was introduced.

The platform adapter retains `svc_list_query` and the existing distro boundary,
streaming `systemctl list-units --type=service --all --plain --no-legend --no-pager`
in the C locale. It reads at most 512 KiB / 1024 units with bounded lines, strict
UTF-8 and deterministic columns. It observes unit, active_state and sub_state;
it does not fabricate descriptions, installed-file state or user-manager data.
Templates/transients and distinct reported aliases retain observed names; duplicate
identities and unsupported/malformed names fail the complete inventory, rather
than being skipped or shortened. D049 identity limits remain unchanged, including
the 142-character native-unit suffix budget. Missing command dependencies or a
failed manager query cannot become a successful empty collection.

The stabilization path fix uses the loader-supplied Core root and the module's
source directory. It works when the installation fixture contains modules/config
but does not contain a copied Core tree. stdout, stderr and canonical result are
checked separately; the System assertion was not relaxed.

## Allocation, cursor and lifecycle ownership

`collection_runtime.Snapshots` owns only ephemeral navigation data under the
existing private runtime directory. It does not register resources, dispatch
capabilities or own History. Owner-only directories/files, no-follow opens,
a shared flock, atomic replacement and a bounded index serialize accounting.

- Snapshot: at most 1024 rows / 512 KiB serialized domain data.
- Session: at most two snapshots / 1 MiB.
- Shared runtime: at most eight snapshots / 4 MiB, including 512 KiB reservations
  acquired before producer construction. Committed entries charge actual bytes.
- Page: default 50 / maximum 128 rows / 64 KiB strict UTF-8 JSON.
- Lifetime: absolute elapsed time strictly less than 30 seconds. UTC Z timestamps
  display the fixed observation/expiry interval; paging does not renew it.

Rows are validated with the existing admitted record validator before retention;
full pages use shared collection validation before snapshot commitment. Every
page is checked, so a later oversized page cannot turn an earlier partial
inventory into successful complete discovery. Allocation is conservative; actual
process memory includes Python objects, parsers and temporary encoding overhead.
Serialized accounting is not an RSS limit.

Opaque HMAC continuations bind session/process identity (PID/start/boot), scope,
owner/provider, descriptor identity/version/digest, inventory query, revision,
page size, position and creation time. Refresh replaces this session's same
collection; independent sessions' fresh snapshots are not evicted. Invalid,
cross-session, mismatched and expired continuations fail without requerying live
rows. Capacity exhaustion uses `collection_budget_exhausted`; size failures use
`collection_limit_exceeded`; expired valid continuations use `collection_expired`
through existing canonical evidence/status paths. Failed construction/refresh
never publishes a successful partial inventory.

Cache entry points sweep expiry, dead owners/builders and disabled owners; normal
release and the module-disable path also revoke leases. Physical abandoned-file
cleanup is lazy at the next cache boundary, while dead/expired ownership never
grants cursor authority. Revoked live builders are terminated, and their reserved
allocation stays charged until exit. Failed writes/construction, replacement,
session release, actual process termination, PID-start mismatch, abandoned leases
and orphan files have controlled evidence. Restart cannot recreate navigation
authority from History. No persistent inventory/configuration migration or daemon.

## Transport, privacy and verification

`bounded_handler.py` wraps the existing Module API handler process before Bash
capture, with the 96 KiB response ceiling and an independent maximum 30-second
deadline. A TERM-ignoring fixture is killed within its shortened test deadline.
The shared handler bridge still validates envelopes/output. Larger domain data
uses stdin instead of an argv slot when constructing the canonical result.
Invalid output retains existing execution/output/verification distinctions and
clears rejected domain data. Operation identities are unchanged.

The existing frontend event writer checks action-result JSON including its event
envelope at 96 KiB before append, using strict UTF-8 rather than expanding Unicode
with ASCII escapes. Exact-byte and oversize-event checks pass. Managed-secret
material is staged through the real secret service for privacy fixtures; rejected
collection values do not enter results, cache files or History. The shared output
validator loads one existing secret projector per page, checking raw string
values so JSON escaping cannot hide material. This is not a second validator.
History stores a cursor digest with inputs_redacted, while retaining exact current
operation binding checks and unrelated metadata projection semantics.

## Governed evidence and limitations

Every executed stabilization plan was inspected with --dry-run. The 25-case
System file progressed steadily, but exceeded the aggregate 240-second ceiling.
Its unchanged test bodies now run in three governed groups (11/7/7 cases), sharing
an isolated fixture; all bodies remain covered. Registered parallel groups use
private state and mocked host commands. `--only-group` permits exact focused-plan
IDs only, records exclusions and rejects unknown IDs or affected/full filtering.
It does not renew the governor or waive excluded acceptance evidence. Collection
security checks are explicitly protected from reuse.

Final evidence is tracked in [STATUS](STATUS.md), with qualifying scenario ledger
`/tmp/igor2-b-qualifying-ledger.json`. Unique covered identities/check groups:
**438 PASS, 3 FAIL_BASELINE, 2 BASELINE_FIXED, 1 ENV_SKIP; zero unresolved new
failures, cancellations or required B checks unexecuted.** This combines
qualifying unchanged proof with the final affected and correction runs; it is not
a single full-suite result. Earlier failed/interrupted evidence remains preserved.

The current failures are the reproduced historical History Ruff diagnostics and
the reviewed System namespace/package-upgrade fixtures. The original accepted
SIM103, AI CLI and Step 18 fixture failures remain documented limitations; they
were not all re-executed here. The LAN-IP scrub skip is the existing permitted
`hostname -I unavailable` guard. None is represented as passing.

The five [EXECUTION classes](EXECUTION.md#completion-model) are scoped as follows:

| Proof | Established in B | Deferred |
|---|---|---|
| Contract | Admission, closed output, exact allocation/row/byte/TTL/cursor bounds, stable/replayed pages and value-free errors. | Later complete-milestone consumer proof. |
| Regression | Retained v1/v2, A contracts, approvals, modes, privilege, privacy, secrets, History, owner lifecycle and operator metadata. | Broad CI/release and frontend presentation gates. |
| Vertical slice | Controlled actual System/platform/handler/canonical CLI backend/result/History; paging, replay and explicit refresh. | TUI navigation and unrelated synthetic producer. |
| Inspection | Registry schema/columns/READ binding; page completeness, scoped references, freshness, canonical provenance and cache budgets. | Frontend collection/detail/expiry views and row inspection execution. |
| Migration/recovery | Same list ID/version cutover, old-pin rejection, no persistent format change, abandoned/expired/disabled/dead-process leases and failed construction. | Complete operator selection/removal/detail recovery. |

Actual measurement environment: x86_64, Linux 7.2.6 CachyOS kernel, glibc 2.44,
controlled fixtures under concurrent governed load. Before the last privacy
projector optimization, a 1024-row/190638-byte snapshot took 18.009 s for first
page; resident samples were 24948 KiB before and 28404 KiB after construction.
The 50000 KiB unchanged high-water mark can inherit the parent's peak: the
reported zero increment does not prove zero allocation or a transient RSS ceiling.
Release returned retained rows/bytes to zero. The final managed-secret System
fixture's first 50-of-51 canonical page took 11.261 s including backend dispatch.
**Performance follow-up:** retain this 11.261-second first-page latency for later
authorized measurement and optimization; backend acceptance does not establish
a frontend latency target as met. The resident samples above are sampled RSS,
not a measurement of transient peak memory.
These are host observations, not Raspberry Pi acceptance or a global RSS proof.
Maximum-rich-UTF-8/global RSS and ten human-paced navigation sequences remain
whole-milestone work. No numerical limits were raised.

The exact oversized-capture node passed before the final deadline/read-loop
change; that change invalidates its prior proof. The final governed recheck used
`--dry-run` and exact selection, but setup left only 0.09 s for pytest before
exhaustion. `/tmp/igor2-b-final-capture/summary.json` records 0 PASS, 1 TIMEOUT_NEW;
no completed test identity. The ledger removed the obsolete capture pass.

After Owner renewal, all 33 candidate hashes matched the preserved manifest and
the governor reported 554.051 s available. The Owner's default-interpreter run
`/tmp/igor-validation-wmb7rwyw/summary.json` recorded eight TOOL_UNAVAILABLE
pytest groups; those attempts are not passing evidence. Existing qualifying
pytest proof remains applicable. The exact-node plan was inspected with --dry-run
using the recorded pytest interpreter; `/tmp/igor2-b-capture-resumed/summary.json`
then recorded **1 PASS, zero failures/skips/timeouts/errors**, complete in 5.127 s
(test body 0.303 s). Its raw log confirms bounded rejection with no rejected-value
exposure. This closes the final capture invalidation without production changes
or a redundant broad run. Historical failures/timeouts remain in their reports.

Owner accepted B at its defined backend scope. The checkpoint commit containing
this record closes the increment; it does not accept the complete Collection
Operator milestone. Only evidence/status documentation changed after the final
test; the accepted candidate manifest remains preserved. No expensive qualifying
tests were repeated for the checkpoint. No push, merge or C/D/E work is authorized.
