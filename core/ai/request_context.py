"""Step 15D source adapters and request-local operational provenance.

Reads explicit evidence through its owner; never refreshes, judges or executes.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from context_engine import inspect_context, select_request_context
from privacy import redactions, scrub_data

REQUEST_FIELDS = {"ids", "tags", "domain", "object_id", "capability_id", "scope_id"}


class ContextSelectionError(ValueError):
    def __init__(self, inspection):
        super().__init__("context selection cannot satisfy request")
        self.inspection = inspection


def context_request(value):
    if isinstance(value, str):
        if len(value.encode()) > 4096:
            raise ValueError("context request too large")
        value = json.loads(value)
    if not isinstance(value, dict) or set(value) - REQUEST_FIELDS:
        raise ValueError("unsupported context request")
    for key, child in value.items():
        values = child if key in {"ids", "tags"} else [child]
        if not isinstance(values, list) or len(values) > 32:
            raise ValueError("invalid context request")
        if any(not isinstance(item, str) or not item or len(item) > 160
               or any(ord(char) < 32 for char in item) for item in values):
            raise ValueError("invalid context request")
    return json.loads(json.dumps(value))


def evidence_sources(request, data_dir):
    """Only explicit scoped episode/investigation IDs; absent targets stay absent."""
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
    from investigations import InvestigationError, InvestigationService
    from operational_history import HistoryError, OperationalHistory
    sources = []
    for ident in request.get("ids", []):
        if not ident.startswith(("inv-", "op-")):
            continue
        try:
            if ident.startswith("inv-"):
                row = InvestigationService(Path(data_dir)).inspect(ident)
                kind = "investigation"
                content = {key: row[key] for key in (
                    "title", "summary", "status", "hypotheses", "findings",
                    "unresolved_questions", "evidence")}
                if "typed_findings" in row:
                    content["typed_findings"] = row["typed_findings"]
            else:
                row = OperationalHistory(Path(data_dir)).inspect(ident)
                kind, content = "operational_history", row
            if not request.get("scope_id") or row["scope_id"] != request["scope_id"]:
                continue
            sources.append({"id": ident, "kind": kind, "owner": "core",
                            "source_id": kind, "scope_id": row["scope_id"],
                            "recorded_at": row.get("timestamps", row.get("times", {})).get("updated_at", row.get("times", {}).get("terminal_at")),
                            "availability": "available", "freshness": "historical",
                            "content": content})
            if kind == "investigation":
                # Validate attachments through the existing contract, never invoke it.
                from judgment import validate_record
                for attachment in row.get("judgments", []):
                    record = validate_record(attachment["record"], attachment["request"])
                    sources.append({"id": record["judgment_id"], "kind": "judgment",
                                    "owner": "core", "source_id": ident,
                                    "scope_id": row["scope_id"], "tags": request.get("tags", []),
                                    "recorded_at": record["completed_at"], "content": record})
        except (InvestigationError, HistoryError, ValueError, KeyError):
            # Selector records the explicitly requested missing ID without exception text.
            continue
    return sources


def assemble(reference, request, *, active_owners=None, data_dir=None, include_runtime=True):
    request = context_request(request)
    if active_owners is None:
        active_owners = json.loads(os.environ.get("IGOR_AI_ACTIVE_OWNERS", '["core"]'))
    stamp = datetime.now(timezone.utc).isoformat()
    sources = []
    kinds = {"module_knowledge": "module_knowledge", "module_tier_claims": "legacy_context",
             "persistent_knowledge_and_reports": "legacy_context",
             "host_and_module_state": "legacy_context", "administrator_reference": "legacy_context",
             "session_state": "legacy_context"}
    for key, content in reference.items():
        if key == "context_candidates" and isinstance(content, list):
            sources.extend(content)
        elif key != "module_contributors" and content:
            if key == "host_and_module_state" and isinstance(content, str):
                match = re.search(r"CONTEXT_ENGINE_V1: (\{.*\})", content)
                if match:
                    try:
                        structured = json.JSONDecoder().raw_decode(match[1])[0]
                        sources.extend(structured["items"])
                        continue
                    except (ValueError, KeyError, TypeError):
                        pass
            sources.append({"id": "reference." + key, "kind": kinds.get(key, "legacy_context"), "owner": "core",
                            "source_id": "legacy." + key, "collected_at": stamp,
                            "freshness": "unverified", "content": content})
    snapshot = json.loads(os.environ.get("IGOR_AI_MODEL_SNAPSHOT", "{}")) if include_runtime else {}
    for fact in snapshot.get("facts", []):
        if any(item.get("kind") == "system_fact" and item.get("object_id") == fact.get("object_id")
               and isinstance(item.get("content"), dict)
               and item["content"].get("property") == fact.get("property") for item in sources):
            continue
        sources.append({"id": "fact." + ".".join(str(fact.get(key, "")) for key in (
            "object_id", "property", "state_class")), "kind": "system_fact",
            "owner": fact["owner"], "source_id": fact["source"], "object_id": fact["object_id"],
            "recorded_at": fact.get("recorded_at"), "freshness": fact.get("availability", "unknown"),
            "tags": fact.get("property", "").split("."),
            "availability": fact.get("availability", "unknown"),
            "sensitivity": "secret" if re.search(r"secret|password|credential|private.?key|api.?key|token", fact["property"], re.IGNORECASE) else "public",
            "authority_class": "current_state_projection", "content": fact})
    for health in snapshot.get("health", {}).values():
        sources.append({"id": health["check_id"], "kind": "health_result", "owner": health["owner"],
                        "source_id": health.get("source", health["check_id"]),
                        "tags": health["check_id"].split("."),
                        "object_id": health.get("object_id"), "recorded_at": health.get("evaluated_at"),
                        "freshness": "evaluation", "content": health})
    for capability in json.loads(os.environ.get("IGOR_AI_CAPABILITY_SNAPSHOT", "[]")) if include_runtime else []:
        descriptor = capability.get("descriptor", capability)
        sources.append({"id": descriptor["id"], "kind": "capability_metadata",
                        "owner": capability["owner"], "source_id": descriptor["id"],
                        "capability_id": descriptor["id"], "tags": descriptor["id"].split("."),
                        "availability": "unavailable" if capability.get("availability") in {"inactive", "unavailable"} else "available",
                        "content": descriptor})
    if data_dir:
        sources.extend(evidence_sources(request, data_dir))
    # Reject accidental sensitive metadata before it can become an inspection label.
    pairs = redactions()
    safe = scrub_data(sources, pairs)
    for raw, sanitized in zip(sources, safe):
        if any(raw.get(key) != sanitized.get(key) for key in (
                "id", "owner", "source_id", "scope_id", "object_id", "capability_id")):
            sanitized.update(id="redacted-source", availability="unavailable", content="")
    selection = select_request_context(request, safe, active_owners=active_owners)
    if selection.get("status", "ready") not in {"ready", "selected", "ok"}:
        raise ContextSelectionError(inspect_context(selection))
    return {"context_items": selection["items"]}, inspect_context(selection)


def publish(decision):
    """Use the existing frontend event owner; audit is optional diagnostic retention."""
    from operations import append
    safe = scrub_data(decision)
    try:
        append({"event": "context_routing", **safe})
    except (OSError, ValueError):
        pass
    if os.environ.get("IGOR_AI_EVENT_STREAM"):
        env = {**os.environ, "IGOR_AI_DECISION": json.dumps({"decision": safe})}
        try:
            subprocess.run(["bash", "-c", 'source "$1"; _ai_event_emit context_routing "$IGOR_AI_DECISION"',
                            "igor", str(Path(__file__).with_name("events.sh"))],
                           env=env, capture_output=True, timeout=5, check=False)
        except (OSError, subprocess.TimeoutExpired):
            pass


def main():
    mode = sys.argv[1]
    if mode == "validate":
        print(json.dumps(context_request(sys.stdin.read())))
    elif mode == "select":
        request = context_request(sys.stdin.read())
        selection, inspection = assemble({}, request,
                                         data_dir=os.environ.get("IGOR_DATA_DIR", str(Path(os.environ.get("IGOR_DIR", ".")) / "data")))
        print(json.dumps({"preview": True, "context": inspection,
                          "item_count": len(selection["context_items"])}))
    else:
        raise ValueError("unsupported context inspection")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print(json.dumps({"status": "unavailable", "reason": "context_request_invalid_or_unavailable",
                          "context": getattr(error, "inspection", {})}))
        sys.exit(2)
