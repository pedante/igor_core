# Increment A: typed collection contract foundation

Increment A implements D079 admission and result validation through the existing
capability machinery. It does not migrate `system.service.list`, construct a
snapshot, paginate, invoke row inspection or render a collection frontend.
Module API remains 2 and the contribution envelope remains 1. Existing capability
v1 and v2 declarations keep their current output contracts; v3 requires output
schema 2. An optional `collection` block is legal only on v3/schema 2.

## Exact declaration example

The following is the supported service-shaped contract fragment, exercised by
an isolated contract fixture. It is **not** the live System declaration. `enum`
is the existing scalar enum type, including the two required singleton enums.

```json
{
  "capability_version": 3,
  "collection": {
    "resource_kind": "service",
    "inventory": "loaded_system_services",
    "columns": [
      {
        "field": "unit",
        "label": "Unit"
      }
    ],
    "inspect": {
      "capability_id": "system.service.status",
      "inputs_from_row": {
        "unit": "unit"
      }
    }
  },
  "outputs": {
    "properties": {
      "resource_kind": {
        "type": "enum",
        "enum": [
          "service"
        ]
      },
      "inventory": {
        "type": "enum",
        "enum": [
          "loaded_system_services"
        ]
      },
      "rows": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "reference": {
              "type": "scoped_reference"
            },
            "unit": {
              "type": "string",
              "maxLength": 256,
              "validator": "systemd_unit"
            },
            "active_state": {
              "type": "string",
              "maxLength": 80
            },
            "sub_state": {
              "type": "string",
              "maxLength": 80
            }
          },
          "required": [
            "reference",
            "unit",
            "active_state",
            "sub_state"
          ],
          "additionalProperties": false
        },
        "minItems": 0,
        "maxItems": 128
      },
      "page": {
        "type": "object",
        "properties": {
          "snapshot_revision": {
            "type": "string",
            "minLength": 1,
            "maxLength": 128
          },
          "returned_count": {
            "type": "integer",
            "minimum": 0,
            "maximum": 128
          },
          "total_count": {
            "type": "integer",
            "minimum": 0,
            "maximum": 1024
          },
          "has_more": {
            "type": "boolean"
          },
          "next_cursor": {
            "type": "string",
            "minLength": 1,
            "maxLength": 256
          }
        },
        "required": [
          "snapshot_revision",
          "returned_count",
          "total_count",
          "has_more"
        ],
        "additionalProperties": false
      },
      "freshness": {
        "type": "object",
        "properties": {
          "observed_at": {
            "type": "string",
            "maxLength": 32
          },
          "expires_at": {
            "type": "string",
            "maxLength": 32
          }
        },
        "required": [
          "observed_at",
          "expires_at"
        ],
        "additionalProperties": false
      }
    },
    "required": [
      "resource_kind",
      "inventory",
      "rows",
      "page",
      "freshness"
    ],
    "additionalProperties": false,
    "schema_version": 2
  }
}
```

The authoritative [RFC grammar](COLLECTION_OPERATOR_RFC.md#minimal-declaration-grammar-step-1820)
permits the existing bounded scalar types, pure type-compatible validators,
closed object records, the root `rows` array of closed records, and the D049
`scoped_reference` spelling. No additional JSON Schema vocabulary is admitted.
Each object has at most 32 fields; nesting is at most four record/array levels
(root 1, rows array 2, row 3, reference 4). Arrays of arrays and arrays elsewhere
are rejected. Strings are at most 4096 characters (tighter declared bounds
apply); output text/column labels cannot contain terminal control characters.
Domain JSON is compact strict UTF-8 (`ensure_ascii=false`, no nonfinite numbers),
at most 65536 bytes; the canonical v3 result validation ceiling is 98304 bytes.
The handler-output bridge bounds its raw input before UTF-8 decoding/JSON parsing.

All five root fields are required. Page/freshness shapes and limits are fixed as
shown. `next_cursor` is present iff `has_more`, and is printable ASCII. Returned
count equals row count, total count cannot be smaller, empty pages cannot imply a
nonempty inventory, and more pages require a larger total. A last page may have a
smaller returned count than total because earlier pages exist; comparison with
the actual frozen snapshot belongs to the next increment. Times use UTC `Z`,
with optional 1–6 fractional digits and exactly 30 seconds between observation
and expiry. This validates declarations/data, not elapsed-time freshness.

Resource references delegate to `operational_history.object_ref`; no new
identity parser or scope store is introduced. References must be unique and
belong to one scope. `validate_outputs(..., scope_id=...)` additionally fences
against a caller-supplied authoritative scope. Actual backend scope stamping,
snapshot revision/cursor ownership and observation provenance remain the snapshot
increment's responsibility; a structurally valid page does not establish them.

`columns` and `inspect` may be omitted. Column fields are unique declared scalar
row fields. Inspect bindings admit only a dotted canonical capability ID and at
most 32 direct scalar-field mappings. Package admission never probes a target.
`CapabilityRegistry.inspection_binding` evaluates current active providers,
ambiguity, READ tier, target types/constraints/validators, required inputs and
D070 selector resource kind. It reports incompatible/unavailable bindings without
disabling the list. Explicit provider selection uses existing registry resolution;
no detail execution, selector probe or provider assumption is added.

## Canonical functions and consumers

- `capability_runtime.validate_output_schema` is shared by package admission,
  descriptor construction and `validate_outputs` runtime result validation.
  Its bounded record grammar and collection metadata checks are the one
  authoritative schema implementation.
- `CapabilityDescriptor.from_dict`, `_version`, `CapabilityRegistry.prepare`,
  CLI bridges and `tool_input.tool_fields` recognize v3 with exact version pins.
- `CapabilityDescriptor.inspect` and `operator_surface` carry validated collection
  metadata; `CapabilityRegistry.inspect` exposes inspection binding availability.
- The existing Bash capability dispatcher passes frozen collection metadata to
  the shared handler-output bridge and retains ordinary execution/output/
  verification/History outcomes. Invalid output retains possible provider
  completion, stores no rejected domain payload and cannot become success.
  Limit failures preserve `collection_limit_exceeded` through that same canonical
  evidence field and History; other invalid output keeps `invalid_domain_output`.
  Dispatcher transport completion is separate from the operation outcome.
- The existing loader and compiled registry keep typed privileged operations
  unavailable without a reviewed typed output adapter, for both v2 and v3.

## Evidence and remaining milestone work

The current [STATUS evidence ledger](STATUS.md) records actual results. The
[EXECUTION proof classes](EXECUTION.md#completion-model) remain independent:
contract/regression and fixture-level inspection are established only to the
reported extent. Isolated dispatcher/History fixtures are a foundation integration
proof, not the required live System/synthetic collection frontend vertical slice.
No persistent schema or data layout changes in A; existing History retains its
contract version. Snapshot interruption/expiry/disable/recovery, live consumer
cutover, constrained-hardware/RSS measurements and human navigation remain open.

Implementation findings for subsequent increments:

- D049's existing object reference allows at most 150 characters after its kind
  prefix, with an additional 160-character total-text ceiling, while the System
  `unit` field permits 256 characters. In `service:systemd:<unit>`, the suffix
  budget leaves at most 142 characters for the unit. Native service
  identities exceeding D049's current bound must fail; this increment does not
  invent shortened IDs or extend the identity contract.
- Existing Bash handler capture precedes the bounded bridge, and several
  result/event projections serialize with ASCII escaping. Snapshot producer
  reads and final frontend publication/transport need the RFC's own bounded
  proof before live pages are exposed; A's validator tests are not that proof.
- Existing writers sort JSON object keys. The in-memory validated schema retains
  declaration order; later no-hint presentation must account for serialization
  order instead of assuming original source order survives every projection.
  The tested sorted round trip preserves named-field validation, references and
  row order; explicit column-list order also survives. No-hint presentation may
  use the RFC's escaped validated-JSON fallback. No serializer redesign is needed
  for A, and no renderer is implemented here.

No commits, pushes, merges or live service operations are part of this increment.

## Stabilization acceptance

The final [STATUS ledger](STATUS.md#stabilization-evidence-ledger-2026-10-12)
records the candidate, environment, actual counts, inherited failures, one
permitted environmental skip and all five proof classes. All 101 tests in the
collection contract file pass, including canonical invalid/duplicate/oversize
results and non-exposure scans, exact 65536-byte domain and 98304-byte result
validation boundaries, malformed UTF-8/deep/oversized-integer JSON, and D049
limits. The final History, operator and secret-reference groups are complete.

A proves bounded schema admission and result validation. It does not prove that
an upstream handler/source read is bounded before Bash capture, that a snapshot
is frozen/provenanced, or that a frontend event writer enforces its own 96 KiB
publication cap. Those producer/snapshot/frontend guarantees remain subsequent
increment work. No persistent format or layout changes, live service operations,
real provider migration, row inspection execution or frontend changes are made.
Increment A meets its scoped acceptance checks and is ready for Owner review.
