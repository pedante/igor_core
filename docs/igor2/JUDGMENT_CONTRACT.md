# Decision/Judgment Contract

Status: **accepted bounded contract; in-memory implementation** (D055).

A judgment is a model-generated structured interpretation: for example, a
classification, ranking, recommendation, hypothesis assessment or abstention.
It is reference material. It is neither an operational decision nor a fact,
approval, verified result, executable tool request or durable investigation.
`valid` means schema-valid, not true or authorized.

The implementation is [core/ai/judgment.py](../../core/ai/judgment.py).
There is one Igor envelope, independent of provider, model, local/remote
inference, UI, investigation, Context Engine and operational capabilities.
It has no transport, storage, registry, scheduler or operational consumer.

## Request and kind contract

The Igor caller supplies a closed JSON-compatible request:

```json
{
  "contract": "igor.judgment",
  "version": 1,
  "kind": "interpretation",
  "kind_version": 1,
  "input": {"question": "What might explain this symptom?"},
  "references": [
    {"id": "evidence-1", "source": "host.memory",
     "recorded_at": "2026-09-30T12:00:00Z"}
  ],
  "output_schema": {
    "type": "object",
    "properties": {"topic": {"type": "string", "maxLength": 80}},
    "required": ["topic"],
    "additionalProperties": false
  }
}
```

`version` versions the Igor envelope; `kind_version` versions the caller's
interpretation/payload contract. Kind is a lowercase identifier of at most
64 characters with optional dot, underscore or hyphen separators. Neither
names a model role or selects a provider. The caller owns the meaning and
kind/schema pairing; no speculative built-in kind catalog is introduced.
There is no role-requirement field because runtime role contracts are not yet
accepted or implemented. Future roles can use this boundary without granting
their outputs authority.

`input` is a bounded object, supplied as already sanitized reference data.
References have `id`, `source`, UTC `recorded_at`, optional `locator`, and
optional paired `scope_id`/`object_id`. They retain caller provenance without
dereferencing, fetching, checking availability, refreshing facts or creating a
scope. In-memory local references need no durable identity allocation. A later
durable consumer must retain the scoped identity rules of
[PERSISTENT_MEMORY.md](PERSISTENT_MEMORY.md).

The payload schema is a small, strictly validated JSON Schema subset:

- closed objects: `type`, `properties`, `required`, `additionalProperties: false`;
- arrays: `items`, required `maxItems` (0–64), optional `minItems`;
- strings: required `maxLength` (0–4096), optional `minLength` and `enum`;
- integers/numbers: optional `minimum`, `maximum` and `enum`;
- booleans/null: optional `enum`.

Root payloads are objects. Objects allow at most 32 properties, enums at most
32 values, and schema recursion at most four child levels, subject also to the
whole-request depth bound. Unknown schema keywords, external references,
patterns and executable validators are rejected. Output must match this kind's
schema; a ranking caller can constrain candidate IDs with enums. Validation
does not resolve or approve those candidates.

Request and model response each allow at most 16,384 bytes of canonical JSON,
512 value nodes and eight nesting levels. JSON object keys are at most 160
characters. Duplicate fields, non-JSON/nonfinite numbers and unsupported
Python objects are rejected. At most 32 unique references/evidence links are
accepted. Reference IDs/source/object/scope strings are at most 160 characters;
locators at most 512; metadata excludes control characters. Record inspection
allows 36,864 bytes and 1,088 value nodes to accommodate both provenance and
output. Invalid caller contracts raise `JudgmentError` before adapter invocation.

## Tool-free provider interface

```python
record = judge(request, adapter, provider="configured-provider", model="configured-model")
view = validate_record(record, request)
payload = payload_or_fallback(record, request, {"topic": "ask_user"})
```

The injected `JudgmentAdapter` takes one detached request and returns one
JSON string or object. Its response has only:

```json
{
  "status": "valid",
  "payload": {"topic": "memory"},
  "evidence": ["evidence-1"],
  "reason": null,
  "confidence": 0.7
}
```

Only `valid`, `abstain` and `unknown` are model-produced statuses. Evidence
contains unique IDs from the request's references; invented links are invalid.
Confidence is optional, finite and in [0,1], allowed only for `valid`. It is
self-reported reference data, not calibration, approval or escalation policy.
For abstain/unknown, payload is null and confidence is absent.

Adapters are trusted integration code, not model-generated callbacks or a
sandbox. They must offer no tools, enforce their transport deadlines, and
signal `ProviderUnavailable`, `ProviderFailure` or `TimeoutError`. Other
adapter exceptions map to provider failure. Raw responses and exception text
are discarded on failure; reasons are closed codes, with no provider prose.
The service makes one call with no retry, repair, escalation or model selection.

No live adapter is added here. A future adapter should reuse the existing
AI/provider and request/privacy boundaries for transport rather than establish
a second gateway. OpenAI, OpenRouter, Ollama, Anthropic and future adapters
all return the same Igor response; vendor-native envelopes stay private.
Callers must exclude secret values by default, and transport adapters must
preserve last-mile redaction and administrator AI-disable policy. This service
reads no secret, environment, configuration or storage and cannot authorize
secret access. It does not enforce network policy on arbitrary local code.

## Record, outcomes and fallback

Igor adds `judgment_id`, contract/version, kind/version,
`input_provenance: {request_digest, references}`,
`invocation: {id, provider, model}`, UTC `started_at`/`completed_at`, and
`validation` to the validated response. Judgment and invocation IDs are fresh
Igor-generated UUID hex strings. Provider/model come from caller binding,
never model output. The SHA-256 digest binds the entire canonical request,
including input, references and output schema. It is not an authentication
signature or a persisted cache. Timestamps describe inference, never fact
freshness. Caller input and adapter output are detached from retained records.

| Status | Validation | Reason | Fallback helper |
|---|---|---|---|
| `valid` | `valid` | null | Returns schema-validated reference payload |
| `abstain` | `valid` | `insufficient_information`, `insufficient_confidence`, `cannot_decide` | Returns caller's deterministic default |
| `unknown` | `valid` | `insufficient_information`, `cannot_decide` | Returns caller's deterministic default |
| `invalid_output` | `invalid` | `schema_failure` | Returns caller's deterministic default |
| `provider_failure` | `not_run` | `provider_failed` | Returns caller's deterministic default |
| `unavailable` | `not_run` | `provider_unavailable` | Returns caller's deterministic default |
| `timeout` | `not_run` | `provider_timeout` | Returns caller's deterministic default |

Abstain is a successful choice to withhold judgment. Unknown is a successful
report that the answer cannot be established from the supplied information.
Neither is an invalid response or provider failure. No automatic confidence
threshold or role-routing policy is selected here.

Transport/schema failures contain no payload, evidence or confidence. The
fallback helper revalidates the record against the original request and
returns a detached caller-chosen, schema-valid default for all nondecision
statuses or malformed/mismatched records. Defaults are data, not callbacks.
An invalid request/default remains a caller error. Callers can inspect status
to choose a deterministic clarification or other existing behavior; no helper
can silently execute an action or invoke another model.

`validate_record` is the programmatic inspection surface. It returns the same
closed record with provenance/status without writes, refreshes or model calls.
Schema validation is not proof of authenticity, semantic accuracy or authority.

## Authority boundary and later ownership

Judgments cannot create/alter System Model facts or make stale facts fresh;
activate modules; register capabilities; authoritatively select an operational
provider; classify READ/CHANGE/DESTROY; approve execution; grant privilege;
satisfy preconditions; enable automation; change desired state; create
responsibility; verify capability results; change recovery semantics; or
authorize secret access. Payload fields or prose claiming any such power
remain reference data. Deterministic Igor runtime owns each transition.

The contract has no dispatcher, state writer or authority handle. The existing
tool parser rejects judgment records, including judgments spliced into tool
requests. A later caller must keep judgments in the reference plane and
independently apply current registration, policy, freshness, preconditions,
approval, privilege and verification whenever it proposes an operation.

[MODEL_ROLES.md](MODEL_ROLES.md) and [AI_SPECIALISTS.md](AI_SPECIALISTS.md)
remain design explorations. This contract accepts neither their proposed
roles nor named Jet/Laya policy, budgets, agents or a provider/model solver.
Step **15D** owns actual relevance/context routing and model-routing policy.
15UI and 15C can consume this contract later under their own accepted gates.
There is no investigation lifecycle, UI feature or context selector here.

There is no judgment persistence, history database, durable migration or
restart replay. Future Operational History consumers may reference that a
judgment was used; history and judgments retain distinct ownership. No history
integration is added by this task.
